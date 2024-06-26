-- set globals to locals
local error    = error
local io       = io
local ipairs   = ipairs
local ngx      = ngx
local pairs    = pairs
local pcall    = pcall
local table    = table
local string   = string
local tonumber = tonumber
local tostring = tostring
local type     = type
local unpack   = unpack
local os       = os

local OPENTELEMETRY_PLUGIN_VERSION = "0.2.5"
local BYPASSED = "BYPASSED"
local DEFERRED_SAMPLING = "DEFERRED_SAMPLING"
local VERBOSITY_SAMPLING = "VERBOSITY_SAMPLING"

-- This file monkey-patches the upstream tracer implementation so that the
-- verbosity sampler works.
require("plugins.opentelemetry.tracer_patch")

local shopify_utils = require("plugins.opentelemetry.shopify_utils")
local otel_utils = require("opentelemetry.util")
local otel_global = require("opentelemetry.global")
local metrics_reporter = require("plugins.opentelemetry.metrics_reporter")
otel_global.set_metrics_reporter(metrics_reporter)
local shopify_trace_propagator = require("plugins.opentelemetry.shopify_propagator").new()
local shopify_hint_propagator = require("plugins.opentelemetry.trace_hint_propagator").new()
local trace_context_propagator = require("opentelemetry.trace.propagation.text_map.trace_context_propagator").new()
local composite_propagator = require(
  "opentelemetry.trace.propagation.text_map.composite_propagator"
).new({ trace_context_propagator, shopify_trace_propagator, shopify_hint_propagator })
local traceresponse_propagator = require("plugins.opentelemetry.traceresponse_propagator").new()
local exporter_client_new = require("opentelemetry.trace.exporter.http_client").new
local otlp_exporter_new = require("opentelemetry.trace.exporter.otlp").new
local batch_span_processor_new = require("opentelemetry.trace.batch_span_processor").new
local span_buffering_processor = require("plugins.opentelemetry.span_buffering_processor")
local tracer_provider_new = require("opentelemetry.trace.tracer_provider").new
local deferred_sampler = require("plugins.opentelemetry.deferred_sampler")
local verbosity_sampler = require("plugins.opentelemetry.verbosity_sampler")
local span_kind = require("opentelemetry.trace.span_kind")
local span_status = require("opentelemetry.trace.span_status")
local resource_new = require("opentelemetry.resource").new
local result = require("opentelemetry.trace.sampling.result")
local attr = require("opentelemetry.attribute")
local new_context = require("opentelemetry.context").new

local _M = {}

-- Parse common attributes when module is required (instead of when module functions are invoked from NGINX config file)
-- so that env vars are available to the Lua VM. If you were to run this code from a foo_by_lua block in an NGINX
-- configuration file, os.getenv would not return the env vars on the pod, since NGINX strips most env vars.
local env_attrs = { POD_NAMESPACE = "k8s.namespace.name", POD_NAME = "k8s.pod.name",
                    NODE_NAME = "k8s.node.name", KUBE_LOCATION = "cloud.region", KUBE_CLUSTER = "k8s.cluster.name",
                    REVISION = "service.version" }
local parsed_env_attrs = {}
local function get_env_attrs()
  for env_var, attr_name in pairs(env_attrs) do
    local value = os.getenv(env_var)

    if value ~= nil then
      if env_var == "KUBE_LOCATION" then
        value = shopify_utils.parse_region(value)
      end
      parsed_env_attrs[attr_name] = value
    end
  end
end

local ev_ok, maybe_err = pcall(get_env_attrs)
if not ev_ok then
  ngx.log(ngx.ERR, "Error reading resource attrs from environment: " .. maybe_err)
end

--------------------------------------------------------------------------------
-- This is from https://gist.github.com/h1k3r/089d43771bdf811eefe8.
-- Why not just use ngx.var to get this value? We need the hostname before it's
-- available in ngx.var, so we need to run /bin/hostname inside the container.
-- Since it's doing i/o, we should only use this function during worker
-- initialization. ApiSix uses a variant of this strategy. I think we might be
-- better off just setting an env var on the pod and reading it.
--------------------------------------------------------------------------------
local function get_hostname()
  local f = io.popen("/bin/hostname")

  if f ~= nil then
    local h = f:read("*a") or ""
    h = string.gsub(h, "[\n]", "")
    f:close()
    return h
  else
    return "unknown"
  end
end

--------------------------------------------------------------------------------
-- Make a span_buffering_processor
--
-- @return A buffering span processor
--------------------------------------------------------------------------------
local function create_span_buffering_processor()
  local exporter = otlp_exporter_new(exporter_client_new(
    _M.plugin_open_telemetry_exporter_otlp_endpoint,
    _M.plugin_open_telemetry_exporter_timeout,
    _M.plugin_open_telemetry_exporter_otlp_headers)
  )

  -- There are various assertions in the batch span processor initializer in
  -- opentelemetry-lua; catch and report them with pcall
  local ok, span_processor = pcall(batch_span_processor_new,
    exporter,
    {
      drop_on_queue_full = _M.plugin_open_telemetry_bsp_drop_on_queue_full,
      max_queue_size = _M.plugin_open_telemetry_bsp_max_queue_size,
      batch_timeout = _M.plugin_open_telemetry_bsp_batch_timeout,
      inactive_timeout = _M.plugin_open_telemetry_bsp_inactive_timeout,
      max_export_batch_size = _M.plugin_open_telemetry_bsp_max_export_batch_size,
    }
  )

  if not ok then
    error("Couldn't create batch span processor: " .. span_processor)
  end

  -- Allow for injection of span processor, for testing purposes
  return span_buffering_processor.new(_M.plugin_open_telemetry_span_processor or span_processor)
end

--------------------------------------------------------------------------------
-- Make a tracer provider, given a sampler and span buffering processor.
--
-- @param sampler_name The sampler to use in the provider.
-- @param sbp A span buffering processor to use.
-- @param is_cf A bool to indicate if this is a phony cf tracer_provider
--
-- @return The tracer provider.
--------------------------------------------------------------------------------
function _M.create_tracer_provider(sampler, sbp, is_cf)
  local resource_attrs
  if is_cf then
    resource_attrs = {
      attr.string("service.name", "cloudflare-cdn"),
      attr.string("deployment.environment", _M.plugin_open_telemetry_environment),
      attr.string("cloud.provider", "cloudflare"),
      attr.bool("phony", true)
    }
  else
    resource_attrs = {
      attr.string("host.name", get_hostname()),
      attr.string("service.name", _M.plugin_open_telemetry_service),
      attr.string("deployment.environment", _M.plugin_open_telemetry_environment),
      attr.string("cloud.provider", "gcp")
    }
    for k, v in pairs(parsed_env_attrs) do
      table.insert(resource_attrs, attr.string(k, v))
    end
  end

  -- Create tracer provider
  local tp = tracer_provider_new(sbp, {
    resource = resource_new(unpack(resource_attrs)),
    sampler = sampler,
  })

  return tp
end

--------------------------------------------------------------------------------
-- Returns true if a request is bypassed due to opentelemetry_bypassed_upstreams
-- setting.
--
-- @param proxy_upstream_name The name of the upstream being proxied to
-- @return boolean
--------------------------------------------------------------------------------
function _M.request_is_bypassed(proxy_upstream_name)
  if _M.plugin_open_telemetry_bypassed_upstreams["all"] then
    return true
  end

  for us, _ in pairs(_M.plugin_open_telemetry_bypassed_upstreams) do
    if string.match(proxy_upstream_name, us) then
      return true
    end
  end

  return false
end

local function firehose_enabled_for_upstream(proxy_upstream_name)
  if not _M.plugin_open_telemetry_firehose_upstreams then
    metrics_reporter:add_to_counter("otel.nginx.firehose_enabled", 1, { evaluation = "false", upstream = proxy_upstream_name or "unknown" })
    return false
  elseif _M.plugin_open_telemetry_firehose_upstreams["all"] then
    metrics_reporter:add_to_counter("otel.nginx.firehose_enabled", 1, { evaluation = "true", upstream = proxy_upstream_name or "unknown" })
    return true
  end

  for us, _ in pairs(_M.plugin_open_telemetry_firehose_upstreams) do
    if string.match(proxy_upstream_name, us) then
      metrics_reporter:add_to_counter("otel.nginx.firehose_enabled", 1, { evaluation = "true", upstream = proxy_upstream_name or "unknown" })
      return true
    end
  end

  metrics_reporter:add_to_counter("otel.nginx.firehose_enabled", 1, { evaluation = "false", upstream = proxy_upstream_name or "unknown" })

  return false
end
--------------------------------------------------------------------------------
-- Returns true if inbound request has Shopify tracing headers and the inbound
-- trace context indicates that the parent span was sampled in (;o=1).
--
-- @return boolean
--------------------------------------------------------------------------------
function _M.request_has_tracing_headers()
  local headers = ngx.req.get_headers()
  if headers["x-cloud-trace-context"] and headers["x-shopify-trace-context"] then
    local sampled = string.match(headers["x-shopify-trace-context"], ";o=1") ~= nil
    return sampled
  else
    return false
  end
end

--------------------------------------------------------------------------------
-- Tells us what mode the plugin should run in for a given request. We have to
-- make this calculation on a request-by-request basis because it currently
-- depends on the upstream.
-- * If the request is bypassed (via opentelemetry-plugin-bypassed-upstreams),
--   then the plug in is in BYPASSED mode
-- * If the request is not bypassed and the upstream is configured to use the
--   deferred sampler, then we are in DEFERRED_SAMPLING mode
-- * If the request is not bypassed and the upstream is configured to use the
--   verbosity sampler, we are in VERBOSITY_SAMPLING mode if and only if the
--   request has tracing headers present
--
-- @param proxy_upstream_name The name of the upstream that the request is being
--                            proxied to.
-- @return boolean
--------------------------------------------------------------------------------
function _M.plugin_mode(proxy_upstream_name)
  if ngx.ctx.opentelemetry_plugin_mode ~= nil then
    return ngx.ctx.opentelemetry_plugin_mode
  end

  if _M.request_is_bypassed(proxy_upstream_name) then
    ngx.log(ngx.INFO, "plugin mode: bypassed")
    ngx.ctx.opentelemetry_plugin_mode = BYPASSED
    return ngx.ctx.opentelemetry_plugin_mode
  end

  if _M.should_use_deferred_sampler(proxy_upstream_name) then
    ngx.log(ngx.INFO, "plugin mode: deferred_sampling")
    ngx.ctx.opentelemetry_plugin_mode = DEFERRED_SAMPLING
    return ngx.ctx.opentelemetry_plugin_mode
  end

  -- If we're not using the deferred sampler, we're using the verbosity
  -- sampler, and we only want to run if there are tracing headers
  if firehose_enabled_for_upstream(proxy_upstream_name) or _M.request_has_tracing_headers() then
    ngx.log(ngx.INFO, "plugin mode: verbosity sampling")
    ngx.ctx.opentelemetry_plugin_mode = VERBOSITY_SAMPLING
  else
    ngx.log(ngx.INFO, "plugin mode: bypassed (no tracing headers)")
    ngx.ctx.opentelemetry_plugin_mode = BYPASSED
  end

  return ngx.ctx.opentelemetry_plugin_mode
end

--------------------------------------------------------------------------------
-- Function to return a tracer stored on _M. We can't just set _M.tracer per
-- request because multiple requests share _M's state. We cache on ngx.ctx
-- to save operations.
--
-- @param plugin_mode The mode the plugin is running in.
-- @return tracer instance.
--------------------------------------------------------------------------------
function _M.tracer(plugin_mode)
  if ngx.ctx.opentelemetry_tracer then
    return ngx.ctx.opentelemetry_tracer
  end

  if plugin_mode == nil then
    error("plugin mode not set, cannot get tracer")
  elseif plugin_mode == DEFERRED_SAMPLING then
    ngx.log(ngx.INFO, "using deferred sampler")
    ngx.ctx.opentelemetry_tracer = _M.DeferredSamplerTracer
  elseif plugin_mode == VERBOSITY_SAMPLING then
    ngx.log(ngx.INFO, "using verbosity sampler")
    ngx.ctx.opentelemetry_tracer = _M.VerbositySamplerTracer
  end

  return ngx.ctx.opentelemetry_tracer
end

--------------------------------------------------------------------------------
-- Function to return a cloudflare tracer stored on _M.
-- It's the same thing as the above but for the cf tracer
--
-- @param plugin_mode The mode the plugin is running in.
-- @return tracer instance.
--------------------------------------------------------------------------------
function _M.cf_tracer(plugin_mode)
  if ngx.ctx.cloudflare_tracer then
    return ngx.ctx.cloudflare_tracer
  end

  if plugin_mode == nil then
    error("plugin mode not set, cannot get tracer")
  elseif plugin_mode == DEFERRED_SAMPLING then
    ngx.ctx.cloudflare_tracer = _M.CFDeferredSamplerTracer
  elseif plugin_mode == VERBOSITY_SAMPLING then
    ngx.ctx.cloudflare_tracer = _M.CFVerbositySamplerTracer
  end

  return ngx.ctx.cloudflare_tracer
end

--------------------------------------------------------------------------------
-- Decide whether or not we should force sample spans. The logic also holds for
-- whether or not we should return a traceresponse header to the requester. The
-- logic is also spelled out here:
-- https://docs.google.com/spreadsheets/d/1idsmrcB_x-vmJJi9YZg8QOIBstrFuFRUa-QK0yywFDc/
--
-- @param ngx_resp                    Should be be ngx.resp.
-- @param initial_sampling_decision   The sampling decision made initially by
--                                    the deferred sampler
-- @param plugin_mode                 The plugin mode
--
-- @return boolean
--------------------------------------------------------------------------------
function _M.should_force_sample_buffered_spans(ngx_resp, initial_sampling_decision, plugin_mode)
  if plugin_mode ~= DEFERRED_SAMPLING then
    return false
  end

  if initial_sampling_decision == result.record_and_sample then
    return true
  end

  if ngx_resp.get_headers()["traceresponse"] and string.sub(ngx_resp.get_headers()["traceresponse"], -3) == "-00" then
    metrics_reporter:add_to_counter("otel.nginx.deferred_sampling_decision", 1, { is_sampled = "false", context_valid = "true" })
    return false
  end

  local ctx = traceresponse_propagator:extract(new_context(), ngx_resp)
  if ctx:span_context():is_valid() then
    local is_sampled = ctx:span_context():is_sampled()
    metrics_reporter:add_to_counter("otel.nginx.deferred_sampling_decision", 1, { is_sampled = tostring(is_sampled), context_valid = "true" })
    return is_sampled
  else
    metrics_reporter:add_to_counter("otel.nginx.deferred_sampling_decision", 1, { is_sampled = "false", context_valid = "false" })
    return false
  end
end

--------------------------------------------------------------------------------
-- Make tags for response metric in main.lua
--
-- @param ngx_headers The table returned by ngx.req.get_headers()
-- @param upstream_name The name of the service being proxied to
-- @return Table containing tags for propagation header metrics
--------------------------------------------------------------------------------
function _M.make_propagation_header_metric_tags(ngx_headers, upstream_name, plugin_mode)
  local ret = { trace_id_present = "false", upstream_name = upstream_name, plugin_mode = plugin_mode }
  for _, header in ipairs({ "traceparent", "x-cloud-trace-context", "x-shopify-trace-context" }) do
    if ngx_headers[header] ~= nil then
      ret[header] = "true"
      ret.trace_id_present = "true"
    else
      ret[header] = "false"
    end
  end
  return ret
end

function _M.should_use_deferred_sampler(proxy_upstream_name)
  if _M.plugin_open_telemetry_deferred_sampling_upstreams["all"] then
    return true
  end

  for us, _ in pairs(_M.plugin_open_telemetry_deferred_sampling_upstreams) do
    if string.match(proxy_upstream_name, us) then
      return true
    end
  end

  return false
end

function _M.init_worker(config)
  _M.plugin_open_telemetry_bypassed_upstreams                   = shopify_utils.parse_upstream_list(config.plugin_open_telemetry_bypassed_upstreams)
  _M.plugin_open_telemetry_firehose_upstreams                   = shopify_utils.parse_upstream_list(config.plugin_open_telemetry_firehose_upstreams)
  _M.plugin_open_telemetry_deferred_sampling_upstreams          = shopify_utils.parse_upstream_list(config.plugin_open_telemetry_deferred_sampling_upstreams)
  _M.plugin_open_telemetry_exporter_otlp_endpoint               = config.plugin_open_telemetry_exporter_otlp_endpoint
  _M.plugin_open_telemetry_exporter_otlp_headers                = shopify_utils.w3c_baggage_to_table(config.plugin_open_telemetry_exporter_otlp_headers)
  _M.plugin_open_telemetry_exporter_timeout                     = config.plugin_open_telemetry_exporter_timeout
  _M.plugin_open_telemetry_bsp_max_queue_size                   = config.plugin_open_telemetry_bsp_max_queue_size
  _M.plugin_open_telemetry_bsp_batch_timeout                    = config.plugin_open_telemetry_bsp_batch_timeout
  _M.plugin_open_telemetry_bsp_max_export_batch_size            = config.plugin_open_telemetry_bsp_max_export_batch_size
  _M.plugin_open_telemetry_bsp_inactive_timeout                 = config.plugin_open_telemetry_bsp_inactive_timeout
  _M.plugin_open_telemetry_bsp_drop_on_queue_full               = config.plugin_open_telemetry_bsp_drop_on_queue_full
  _M.plugin_open_telemetry_shopify_verbosity_sampler_percentage = config.plugin_open_telemetry_shopify_verbosity_sampler_percentage
  _M.plugin_open_telemetry_service                              = config.plugin_open_telemetry_service
  _M.plugin_open_telemetry_environment                          = config.plugin_open_telemetry_environment
  _M.plugin_open_telemetry_set_traceresponse                    = config.plugin_open_telemetry_set_traceresponse
  _M.plugin_open_telemetry_strip_traceresponse                  = config.plugin_open_telemetry_strip_traceresponse
  _M.plugin_open_telemetry_captured_request_headers             = shopify_utils.parse_http_header_list(config.plugin_open_telemetry_captured_request_headers)
  _M.plugin_open_telemetry_captured_response_headers            = shopify_utils.parse_http_header_list(config.plugin_open_telemetry_captured_response_headers)
  _M.plugin_open_telemetry_record_p                             = config.plugin_open_telemetry_record_p
  _M.plugin_open_telemetry_add_cloudflare_span                  = config.plugin_open_telemetry_add_cloudflare_span

  local tracer_samplers = {
    VerbositySamplerTracer = verbosity_sampler.new(_M.plugin_open_telemetry_shopify_verbosity_sampler_percentage),
    DeferredSamplerTracer = deferred_sampler.new()
  }
  local ok, sbp = pcall(create_span_buffering_processor)
  if not ok then
    ngx.log(ngx.ERR, "ingress-nginx failed to create buffering span processor: ", sbp)
    return
  end

  -- We need a handle on the span buffering processor so that we can flush it in the log phase. Although the span
  -- buffering processor is shared by all requests, the underlying storage is actually on ngx.ctx, so it should be
  -- safe to share.
  _M.span_buffering_processor = sbp

  for t, s in pairs(tracer_samplers) do
    -- We can reuse the buffering span processor because each request only has one sampling mode
    -- and hence, only uses one tracer.
    local tp = _M.create_tracer_provider(s, span_buffering_processor, false)
    local cf_tp = _M.create_tracer_provider(s, span_buffering_processor, true)
    local tracer = tp:tracer("ingress_nginx.plugins.opentelemetry",
      { version = OPENTELEMETRY_PLUGIN_VERSION, schema_url = "" })
    local cf_tracer = cf_tp:tracer("ingress_nginx.plugins.opentelemetry",
      { version = OPENTELEMETRY_PLUGIN_VERSION, schema_url = "" })
    _M[t] = tracer
    _M["CF" .. t] = cf_tracer
  end

  ngx.log(ngx.INFO, "OpenTelemetry ingress-nginx plugin enabled.")
  metrics_reporter.statsd.defer_to_timer.init_worker()
end

function _M.rewrite()
  ngx.ctx.opentelemetry_inbound_tracestate = ngx.req.get_headers()["tracestate"]
  local plugin_mode = _M.plugin_mode(ngx.var.proxy_upstream_name)
  metrics_reporter:add_to_counter(
    "otel.nginx.request",
    1,
    _M.make_propagation_header_metric_tags(
      ngx.req.get_headers(),
      ngx.var.proxy_upstream_name,
      plugin_mode)
  )
  if plugin_mode == BYPASSED then
    metrics_reporter:add_to_counter("otel.nginx.phase_skip", 1, { phase = "rewrite", reason = "bypassed" })
    ngx.log(ngx.INFO, "skipping rewrite")
    return
  end
  local tracer = _M.tracer(plugin_mode)

  local rewrite_start = otel_utils.gettimeofday_ms()

  local upstream_context = composite_propagator:extract(new_context(), ngx.req)
  local cf_span_context = nil

  if _M.should_create_cloudflare_span(ngx.req.get_headers()["x-shopify-request-timing"]) then
    local cf_tracer = _M.cf_tracer(plugin_mode)
    cf_span_context = cf_tracer:start(upstream_context, "cloudflare.proxy", {
      kind = span_kind.server
    })
  end

  -- Extract trace context from the headers of downstream HTTP request
  local request_span_ctx = tracer:start(cf_span_context or upstream_context, "nginx.request", {
    kind = span_kind.server,
  })

  composite_propagator:inject(
    request_span_ctx,
    ngx.req)

  ngx.ctx["opentelemetry"] = {
    initial_sampling_decision = request_span_ctx:span_context():is_sampled() and result.record_and_sample or
        result.record_only,
    request_span_ctx          = request_span_ctx,
    cf_span_ctx               = cf_span_context,
  }

  local rewrite_end = otel_utils.gettimeofday_ms()
  metrics_reporter:record_value("otel.nginx.rewrite_phase_ms", rewrite_end - rewrite_start)
end

-- ngx.var.upstream_address can contain a list of addresses, separated by
-- commas. The final one is the one we want to capture. See
-- http://nginx.org/en/docs/http/ngx_http_upstream_module.html#var_upstream_addr
function _M.parse_upstream_addr(input)
  if not input then return { addr = nil, port = nil } end

  local t = {}
  for a, p in string.gmatch(input, "([^:%s]+):([^%s,:]+)") do
    table.insert(t, { addr = a, port = p })
  end

  if #t > 0 then
    return { addr = t[#t].addr, port = tonumber(t[#t].port) }
  else
    return { addr = nil, port = nil }
  end
end

local function should_strip_traceresponse()
  return _M.plugin_open_telemetry_strip_traceresponse and
    ngx.var.arg_debug_headers == nil
end

function _M.should_create_cloudflare_span(timing_header)
  if not _M.plugin_open_telemetry_add_cloudflare_span then
    return false
  end

  ngx.ctx.opentelemetry_cf_span_start = shopify_utils.cloudflare_start_from_timing_header(timing_header)
  return ngx.ctx.opentelemetry_cf_span_start ~= nil
end

function _M.header_filter()
  if _M.plugin_mode(ngx.var.proxy_upstream_name) == BYPASSED then
    -- As noted in readme, we strip traceresponse when settings say so, even when in BYPASSED MODE
    if should_strip_traceresponse() then
      ngx.header["traceresponse"] = nil
    end

    ngx.log(ngx.INFO, "skipping header filter")
    metrics_reporter:add_to_counter("otel.nginx.phase_skip", 1, { phase = "header_filter", reason = "bypassed" })
    return
  end

  local header_start = otel_utils.gettimeofday_ms()
  local ngx_ctx = ngx.ctx

  if not ngx_ctx["opentelemetry"] then
    metrics_reporter:add_to_counter("otel.nginx.phase_skip", 1, { phase = "header_filter", reason = "missing_otel_ctx" })
    ngx.log(ngx.INFO,
      "Bailing from header_filter(). ngx_ctx['opentelemetry'] is nil.")
    return
  end

  ngx_ctx.opentelemetry_span_end_time = otel_utils.time_nano()

  if _M.plugin_open_telemetry_set_traceresponse then
    metrics_reporter:add_to_counter("otel.nginx.set_traceresponse", 1, { upstream = ngx.var.proxy_upstream_name or "unknown" })
    -- We need to update the child ID in the traceresponse header. To do this, we can just overwrite the traceresponse
    -- header to match the context from NGINX's outermost span (the request span) since the trace ID in the
    -- traceresponse header we received back from the proxied-to service originated in this plugin or the initial
    -- request that hit NGINX. The global proxy is responsible for stripping traceresponse headers.
    traceresponse_propagator:inject(ngx_ctx.opentelemetry.request_span_ctx, ngx)
  end

  -- Cache whether or not we should force sample buffered spans, since we may strip the header
  ngx_ctx.opentelemetry_should_force_sample_buffered_spans = _M.should_force_sample_buffered_spans(
    ngx.resp, ngx_ctx.opentelemetry.initial_sampling_decision, ngx.ctx.opentelemetry_plugin_mode)

  -- Cache tracesampling-p, since we may strip the header
  if ngx_ctx.opentelemetry_should_force_sample_buffered_spans then
    ngx_ctx.opentelemetry_tracesampling_p = ngx.resp.get_headers()["x-shopify-tracesampling-p"]

    ngx_ctx.exemplar_value = ngx_ctx.opentelemetry.request_span_ctx and ngx_ctx.opentelemetry.request_span_ctx.sp.ctx.trace_id
  end

  if _M.plugin_mode(ngx.var.proxy_upstream_name) ~= DEFERRED_SAMPLING then
    ngx_ctx.exemplar_value = ngx_ctx.opentelemetry.request_span_ctx and ngx_ctx.opentelemetry.request_span_ctx.sp.ctx.trace_id
  end

  if should_strip_traceresponse() then
    ngx.header["traceresponse"] = nil
    ngx.header["x-shopify-tracesampling-p"] = nil
  end

  local header_end = otel_utils.gettimeofday_ms()
  metrics_reporter:record_value("otel.nginx.header_phase_ms", header_end - header_start)
end

function _M.log()
  if _M.plugin_mode(ngx.var.proxy_upstream_name) == BYPASSED then
    metrics_reporter:add_to_counter("otel.nginx.phase_skip", 1, { phase = "log", reason = "bypassed" })
    ngx.log(ngx.INFO, "skipping log")
    return
  end

  local log_start = otel_utils.gettimeofday_ms()
  local status = tonumber(ngx.var.status) or 0

  local ngx_ctx = ngx.ctx
  if not ngx_ctx["opentelemetry"] then
    metrics_reporter:add_to_counter("otel.nginx.phase_skip", 1, { phase = "log", reason = "missing_otel_ctx" })
    return
  end
  local ngx_var = ngx.var
  local cf_attributes = {}

  -- close request span if present
  -- See https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/semantic_conventions/http.md#status
  -- for rules on which spans should be marked as having error status
  if ngx_ctx.opentelemetry.request_span_ctx then
    -- parse upstream
    local parsed_upstream = _M.parse_upstream_addr(ngx_var.upstream_addr)

    -- Assemble attributes

    -- Attributes aspire to align with HTTP and network semantic conventions
    -- https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/semantic_conventions/http.md
    -- https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/semantic_conventions/span-general.md
    -- http.target is supposed to have query params attached to it, but we exclude them since they might contain PII
    local attributes = {
      attr.string("http.target", ngx_var.uri),
      attr.string("http.flavor", string.gsub(ngx_var.server_protocol or "unknown", "HTTP/", "")),
      attr.string("http.method", ngx_var.request_method),
      attr.string("http.scheme", ngx_var.scheme),
      attr.string("http.user_agent", ngx_var.http_user_agent),
      attr.string("nginx.proxy_upstream_name", ngx_var.proxy_upstream_name or "unknown"),
      attr.string("http.request.header.x_request_id", ngx_var.req_id or "unknown"),
      attr.string("net.peer.name", ngx_var.proxy_host),
      attr.string("net.host.name", ngx_var.server_name),
      attr.int("net.host.port", tonumber(ngx_var.server_port)),
      attr.int("http.status_code", status),
      attr.string("nginx.plugin_mode", _M.plugin_mode(ngx_var.proxy_upstream_name)),
    }

    if ngx_var.upstream_connect_time then
      table.insert(attributes, attr.string("nginx.upstream_connect_time", ngx_var.upstream_connect_time))
    end
    if parsed_upstream.addr then
      table.insert(attributes, attr.string("net.sock.peer.addr", parsed_upstream.addr))
    end
    if parsed_upstream.port then
      table.insert(attributes, attr.int("net.peer.port", parsed_upstream.port))
    end
    if ngx_ctx.opentelemetry_inbound_tracestate then
      table.insert(attributes, attr.string("nginx.inbound_tracestate", ngx_ctx.opentelemetry_inbound_tracestate))
    end
    if ngx_ctx.opentelemetry_tracesampling_p then
      table.insert(attributes, attr.string("http.response.header.x_shopify_tracesampling_p", ngx_ctx.opentelemetry_tracesampling_p))
    end

    if status >= 500 then
      ngx_ctx.opentelemetry.request_span_ctx.sp:set_status(span_status.ERROR)
    end

    -- add request header attributes, if configured
    local req_headers = ngx.req.get_headers()
    for lowercased_attr, underscored_attr in pairs(_M.plugin_open_telemetry_captured_request_headers) do
      local header_value = req_headers[lowercased_attr]

      -- If multiple values for the same header are present, openresty puts them into a table; in this situation
      -- we concatenate and join with a semicolon. See https://openresty-reference.readthedocs.io/en/latest/Lua_Nginx_API/#ngxreqget_headers.
      if type(header_value) == "table" then
        header_value = table.concat(header_value, ";")
      end

      if header_value then
        -- upstream doesn't have attr limits, so we do here; see https://github.com/yangxikun/opentelemetry-lua/issues/73
        local truncated_value = string.sub(header_value, 0, 128)
        table.insert(attributes, attr.string("http.request.header." .. underscored_attr, truncated_value))
        -- add the attr to the phony cf span if it starts with edge_ or cf_
        if underscored_attr:sub(1, #"edge_") == "edge_" or underscored_attr:sub(1, #"cf_") == "cf_" then
          table.insert(cf_attributes, attr.string(underscored_attr, truncated_value))
        end
      end
    end

    -- add response header attributes, if configured
    if _M.plugin_open_telemetry_captured_response_headers then
      local resp_headers = ngx.resp.get_headers()
      for lowercased_attr, underscored_attr in pairs(_M.plugin_open_telemetry_captured_response_headers) do
        local header_value = resp_headers[lowercased_attr]

        -- If multiple values for the same header are present, openresty puts them into a table; in this situation
        -- we concatenate and join with a semicolon. See https://openresty-reference.readthedocs.io/en/latest/Lua_Nginx_API/#ngxreqget_headers.
        if type(header_value) == "table" then
          header_value = table.concat(header_value, ";")
        end

        if header_value then
          -- upstream doesn't have attr limits, so we do here; see https://github.com/yangxikun/opentelemetry-lua/issues/73
          local truncated_value = string.sub(header_value, 0, 128)
          table.insert(attributes, attr.string("http.response.header." .. underscored_attr, truncated_value))
        end
      end
    end

    ngx_ctx.opentelemetry.request_span_ctx.sp:set_attributes(unpack(attributes))
    ngx_ctx.opentelemetry.request_span_ctx.sp:finish(ngx_ctx.opentelemetry_span_end_time)
  end



  local timing_header = ngx.req.get_headers()["x-shopify-request-timing"]
  if _M.should_create_cloudflare_span(timing_header) then
    -- If we are creating a CF span, attempt to fix the start time using the request timing header
    -- Check if we have a request start in the timing header and use for span if there
    local request_start = shopify_utils.request_start_from_timing_header(timing_header)
    if request_start and request_start < ngx_ctx.opentelemetry.request_span_ctx.sp.start_time then
      -- We can do this timestamping more cleanly when we address https://github.com/yangxikun/opentelemetry-lua/issues/86
      ngx_ctx.opentelemetry.request_span_ctx.sp.start_time = request_start
    end
    ngx_ctx.opentelemetry.cf_span_ctx.sp:set_attributes(unpack(cf_attributes))
    -- We can do this timestamping more cleanly when we address https://github.com/yangxikun/opentelemetry-lua/issues/86
    ngx_ctx.opentelemetry.cf_span_ctx.sp.start_time = ngx_ctx.opentelemetry_cf_span_start
    ngx_ctx.opentelemetry.cf_span_ctx.sp:finish(ngx_ctx.opentelemetry_span_end_time)
  end

  -- Handle deferred sampling
  if  ngx_ctx.opentelemetry_should_force_sample_buffered_spans then
    -- set p to be consistent with upstream consistent probability sampling
    if ngx_ctx.opentelemetry_tracesampling_p and _M.plugin_open_telemetry_record_p then
      for _, s in ipairs(_M.span_buffering_processor.spans()) do
        -- This is clobbering upstream ot vendor tag
        -- OK for now, since we're not really using the ot vendor tag for anything besides
        -- consistent probability sampling and this is happening AFTER trace propagation,
        -- but we should make this smarter.
        s:context().trace_state:set("ot", "p:" .. ngx_ctx.opentelemetry_tracesampling_p)
      end
    end
    _M.span_buffering_processor:send_spans(true)
  else
    _M.span_buffering_processor:send_spans(false)
  end

  -- Send stats now that the log phase is over.
  local log_end = otel_utils.gettimeofday_ms()
  metrics_reporter:record_value("otel.nginx.log_phase_ms", log_end - log_start)
end

return _M
