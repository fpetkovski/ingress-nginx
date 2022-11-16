-- set globals to locals
local error    = error
local ipairs   = ipairs
local ngx      = ngx
local ngx_var  = ngx.var
local pairs    = pairs
local pcall    = pcall
local table    = table
local string   = string
local tonumber = tonumber
local unpack   = unpack

local OPENTELEMETRY_PLUGIN_VERSION = "0.2.1"

local shopify_utils = require("plugins.opentelemetry.shopify_utils")
local otel_utils = require("opentelemetry.util")
local otel_global = require("opentelemetry.global")
local metrics_reporter = require("plugins.opentelemetry.metrics_reporter")
otel_global.set_metrics_reporter(metrics_reporter)
local trace_context_propagator = require("plugins.opentelemetry.shopify_propagator").new()
local baggage_propagator = require("opentelemetry.baggage.propagation.text_map.baggage_propagator").new()
local composite_propagator = require(
  "opentelemetry.trace.propagation.text_map.composite_propagator"
).new({ trace_context_propagator, baggage_propagator })
local traceresponse_propagator = require("plugins.opentelemetry.traceresponse_propagator").new()
local exporter_client_new = require("opentelemetry.trace.exporter.http_client").new
local otlp_exporter_new = require("opentelemetry.trace.exporter.otlp").new
local batch_span_processor_new = require("opentelemetry.trace.batch_span_processor").new
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


local function make_tracer_provider(sampler)
  local exporter = otlp_exporter_new(exporter_client_new(
    _M.plugin_open_telemetry_exporter_otlp_endpoint,
    _M.plugin_open_telemetry_exporter_timeout,
    _M.plugin_open_telemetry_exporter_otlp_headers)
  )

  -- There are various assertions in the batch span processor initializer in
  -- opentelemetry-lua; catch and report them with pcall
  local ok, batch_span_processor = pcall(batch_span_processor_new,
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
    error("Couldn't create batch span processor: " .. batch_span_processor)
  end

  local resource_attrs = {
    attr.string("hostname", shopify_utils.get_hostname()),
    attr.string("service.name", _M.plugin_open_telemetry_service),
    attr.string("deployment.environment", _M.plugin_open_telemetry_environment)
  }

  -- Create tracer provider
  local tp = tracer_provider_new(batch_span_processor, {
    resource = resource_new(unpack(resource_attrs)),
    sampler = sampler,
  })

  return tp
end

function _M.create_tracer_provider(sampler_name, sampler_arg)
  local samplers = {
    ShopifyVerbositySampler = verbosity_sampler,
    ShopifyDeferredSampler = deferred_sampler
  }
  local sampler_mod

  if samplers[sampler_name] then
    ngx.log(ngx.INFO, "using sampler " .. sampler_name)
    sampler_mod = samplers[sampler_name]
  else
    error("could not find sampler " .. sampler_name)
  end

  return make_tracer_provider(
    sampler_mod.new(sampler_arg)
  )
end

--------------------------------------------------------------------------------
-- This function tells us whether or not the plugin should run for a given
-- request. Here are the rules:
-- * If the request is bypassed (via opentelemetry-plugin-bypassed-upstreams),
--   then we don't want to run.
-- * If the request is not bypassed and the upstream is configured to use the
--   deferred sampler, then we want to run.
-- * If the request is not bypassed and the upstream is configured to use the
--   verbosity sampler, we only want to run if there are already tracing headers
--   present on the request.
-- @param proxy_upstream_name The name of the upstream that the request is being
--                            proxied to.
-- @return boolean
--------------------------------------------------------------------------------
function _M.plugin_should_run(proxy_upstream_name)
  if ngx.ctx.opentelemetry_plugin_should_run ~= nil then
    return ngx.ctx.opentelemetry_plugin_should_run
  end

  if _M.request_is_bypassed(proxy_upstream_name) then
    ngx.ctx.opentelemetry_plugin_should_run = false
    return false
  end

  if _M.should_use_deferred_sampler(proxy_upstream_name) then
    ngx.ctx.opentelemetry_plugin_should_run = true
    return true
  end

  -- We're if we're not using the deferred sampler, we're using the verbosity
  -- sampler, and we only want to run if there are tracing headers
  ngx.ctx.opentelemetry_plugin_should_run = _M.request_has_tracing_headers()
  return ngx.ctx.opentelemetry_plugin_should_run
end

function _M.tracer()
  if ngx.ctx.opentelemetry_tracer then
    return ngx.ctx.opentelemetry_tracer
  end

  if _M.should_use_deferred_sampler(ngx.var.proxy_upstream_name) then
    ngx.ctx.opentelemetry_tracer = _M.ShopifyDeferredSampler
  else
    ngx.ctx.opentelemetry_tracer = _M.ShopifyVerbositySampler
  end

  return ngx.ctx.opentelemetry_tracer
end

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

--------------------------------------------------------------------------------
-- Check to see if request has tracing headers. We only regard the request as
-- having tracing headers if ;o=1.
--------------------------------------------------------------------------------
function _M.request_has_tracing_headers()
  local ngx_ctx = ngx.ctx

  if ngx_ctx["shopify_headers_present"] ~= nil then
    return ngx_ctx["shopify_headers_present"]
  end

  local headers = ngx.req.get_headers()
  if headers["x-cloud-trace-context"] and headers["x-shopify-trace-context"] then
    local sampled = string.match(headers["x-shopify-trace-context"], ";o=1") ~= nil
    ngx_ctx["shopify_headers_present"] = sampled
    return sampled
  else
    ngx_ctx["shopify_headers_present"] = false
    return false
  end
end

--------------------------------------------------------------------------------
-- Decide whether or not we should force sample spans. The logic also holds for
-- whether or not we should return a traceresponse header to the requester. The
-- logic is defined here:
-- https://docs.google.com/spreadsheets/d/1idsmrcB_x-vmJJi9YZg8QOIBstrFuFRUa-QK0yywFDc/
--
-- @param ngx_resp                    Should be be ngx.resp.
-- @param initial_sampling_decision   The sampling decision made initially by
--                                    the deferred sampler
-- @return boolean
--------------------------------------------------------------------------------
function _M.should_force_sample_buffered_spans(ngx_resp, initial_sampling_decision)
  if initial_sampling_decision == result.record_and_sample then
    return false
  end

  local ctx = traceresponse_propagator:extract(new_context(), ngx_resp)
  if ctx:span_context():is_valid() then
    return ctx:span_context():is_sampled()
  else
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
function _M.make_propagation_header_metric_tags(ngx_headers, upstream_name)
  local ret = { trace_id_present = "false", upstream_name = upstream_name }
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
  if ngx.ctx.opentelemetry_should_use_deferred_sampler ~= nil then
    return ngx.ctx.opentelemetry_should_use_deferred_sampler
  end

  if _M.plugin_open_telemetry_deferred_sampling_upstreams["all"] then
    ngx.ctx.opentelemetry_should_use_deferred_sampler = true
    return true
  end

  for us, _ in pairs(_M.plugin_open_telemetry_deferred_sampling_upstreams) do
    if string.match(proxy_upstream_name, us) then
      ngx.ctx.opentelemetry_should_use_deferred_sampler = true
      return true
    end
  end

  ngx.ctx.opentelemetry_should_use_deferred_sampler = false
  return false
end

function _M.init_worker(config)
  _M.plugin_open_telemetry_bypassed_upstreams = shopify_utils.parse_upstream_list(config.plugin_open_telemetry_bypassed_upstreams)
  _M.plugin_open_telemetry_deferred_sampling_upstreams = shopify_utils.parse_upstream_list(config.plugin_open_telemetry_deferred_sampling_upstreams)
  _M.plugin_open_telemetry_exporter_otlp_endpoint = config.plugin_open_telemetry_exporter_otlp_endpoint
  _M.plugin_open_telemetry_exporter_otlp_headers = shopify_utils.w3c_baggage_to_table(config.plugin_open_telemetry_exporter_otlp_headers)
  _M.plugin_open_telemetry_exporter_timeout = config.plugin_open_telemetry_exporter_timeout
  _M.plugin_open_telemetry_bsp_max_queue_size = config.plugin_open_telemetry_bsp_max_queue_size
  _M.plugin_open_telemetry_bsp_batch_timeout = config.plugin_open_telemetry_bsp_batch_timeout
  _M.plugin_open_telemetry_bsp_max_export_batch_size = config.plugin_open_telemetry_bsp_max_export_batch_size
  _M.plugin_open_telemetry_bsp_inactive_timeout = config.plugin_open_telemetry_bsp_inactive_timeout
  _M.plugin_open_telemetry_bsp_drop_on_queue_full = config.plugin_open_telemetry_bsp_drop_on_queue_full
  _M.plugin_open_telemetry_shopify_verbosity_sampler_percentage = config.plugin_open_telemetry_shopify_verbosity_sampler_percentage
  _M.plugin_open_telemetry_service = config.plugin_open_telemetry_service
  _M.plugin_open_telemetry_environment = config.plugin_open_telemetry_environment

  local samplers = {
    ShopifyVerbositySampler = _M.plugin_open_telemetry_shopify_verbosity_sampler_percentage,
    ShopifyDeferredSampler = ""
  }

  for s, a in pairs(samplers) do
    local ok, tp = pcall(
      _M.create_tracer_provider, s, a)

    local t_ok, tracer = pcall(
      tp.tracer,
      tp,
      "ingress_nginx.plugins.opentelemetry",
      { version = OPENTELEMETRY_PLUGIN_VERSION, schema_url = "" })

    if not ok then
      ngx.log(ngx.ERR, "Failed to creaue tracer provider during plugin init: " .. tp)
      ngx.log(ngx.ERR, "Settings: " .. shopify_utils.table_to_string(_M))
    end

    if t_ok then
      _M[s] = tracer
    end
  end

  ngx.log(ngx.ERR, "OpenTelemetry ingress-nginx plugin enabled. Settings: " .. shopify_utils.table_to_string(_M))
  metrics_reporter.statsd.defer_to_timer.init_worker()
end

-- This is a hack, but we're replacing the verbosity sampler with deferred sampling anyway. If the proxy_span_ctx is
-- not sampled, then the request is not verbosity sampled. In that situation, we want to propagate the context of the
-- outermost span, which is always included.
function _M.propagation_context(request_span_ctx, proxy_span_ctx)
  if proxy_span_ctx:span_context():is_sampled() then
    return proxy_span_ctx
  else
    return request_span_ctx
  end
end

function _M.rewrite()
  if _M.request_is_bypassed(ngx.var.proxy_upstream_name) then
    return
  end

  local rewrite_start = otel_utils.gettimeofday_ms()
  metrics_reporter:add_to_counter(
    "otel.nginx.traceable_request",
    1,
    _M.make_propagation_header_metric_tags(
      ngx.req.get_headers(),
      ngx.var.proxy_upstream_name)
  )

  -- Extract trace context from the headers of downstream HTTP request
  local upstream_context = composite_propagator:extract(new_context(), ngx.req)

  -- Attributes aspire to align with HTTP and network semantic conventions
  -- https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/semantic_conventions/http.md
  -- https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/semantic_conventions/span-general.md
  -- http.target is supposed to have query params attached to it, but we exclude them since they might contain PII
  local common_attributes = {
    attr.string("http.target", ngx_var.uri),
    attr.string("http.flavor", string.gsub(ngx_var.server_protocol, "HTTP/", "") or "unknown"),
    attr.string("http.method", ngx_var.request_method),
    attr.string("http.scheme", ngx_var.scheme),
    attr.string("http.user_agent", ngx_var.http_user_agent),
  }

  -- Assemble additional nginx.request span attributes
  local server_attributes = shopify_utils.shallow_copy(common_attributes)

  table.insert(server_attributes, attr.string("net.host.name", ngx_var.server_name))
  table.insert(server_attributes, attr.int("net.host.port", tonumber(ngx_var.server_port)))

  local request_span_ctx = _M.tracer():start(upstream_context, "nginx.request", {
    kind = span_kind.server,
    attributes = server_attributes,
  })

  -- Assemble additional nginx.proxy span attributes
  local proxy_attributes = shopify_utils.shallow_copy(common_attributes)
  table.insert(proxy_attributes, attr.string("net.peer.name", ngx_var.proxy_host))

  local proxy_span_ctx = _M.tracer():start(request_span_ctx, "nginx.proxy", {
    kind = span_kind.client,
    attributes = proxy_attributes,
  })

  composite_propagator:inject(
    _M.propagation_context(request_span_ctx, proxy_span_ctx),
    ngx.req)

  ngx.ctx["opentelemetry"] = {
    initial_sampling_decision = request_span_ctx:span_context():is_sampled() and result.record_and_sample or
        result.record_only,
    request_span_ctx          = request_span_ctx,
    proxy_span_ctx            = proxy_span_ctx,
  }

  local rewrite_end = otel_utils.gettimeofday_ms()
  metrics_reporter:record_value("otel.nginx.rewrite_phase_ms", rewrite_end - rewrite_start)
end

-- ngx.var.upstream_address can contain a list of addresses, separated by
-- commas. The final one is the one we want to capture. See
-- http://nginx.org/en/docs/http/ngx_http_upstream_module.html#var_upstream_addr
function _M.parse_upstream_addr(input)
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

function _M.header_filter()
  if _M.request_is_bypassed(ngx.var.proxy_upstream_name) or not _M.request_has_tracing_headers() then
    return
  end

  local header_start = otel_utils.gettimeofday_ms()
  local ngx_ctx = ngx.ctx

  if not ngx_ctx["opentelemetry"] then
    ngx.log(ngx.ERR,
      "Bailing from header_filter(). ngx_ctx['opentelemetry'] is nil.")
    return
  end

  local upstream_status = tonumber(ngx_var.upstream_status) or 0

  local parsed_upstream = _M.parse_upstream_addr(ngx_var.upstream_addr)

  -- This is not in semconv, but we capture the full upstream addr as an attribute for debugging purposes
  local attrs = { attr.string("nginx.upstream_addr", ngx_var.upstream_addr) }
  if parsed_upstream.addr then
    table.insert(attrs, attr.string("net.sock.peer.addr", parsed_upstream.addr))
  end
  if parsed_upstream.port then
    table.insert(attrs, attr.int("net.peer.port", parsed_upstream.port))
  end

  ngx_ctx.opentelemetry.proxy_span_ctx.sp:set_attributes(unpack(attrs))

  -- See https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/semantic_conventions/http.md#status
  -- for rules on which spans should be marked as having error status
  if upstream_status >= 400 then
    ngx_ctx.opentelemetry.proxy_span_ctx.sp:set_status(span_status.error)
  end
  if upstream_status >= 500 then
    ngx_ctx.opentelemetry.request_span_ctx.sp:set_status(span_status.error)
  end
  ngx_ctx.opentelemetry.request_span_ctx.sp:set_attributes(attr.int("http.status_code", upstream_status))

  ngx_ctx.opentelemetry.proxy_span_end_time = otel_utils.time_nano()
  local response_span = _M.tracer():start(ngx_ctx.opentelemetry.request_span_ctx, "nginx.response", {
    kind = span_kind.client,
    attributes = {},
  })
  ngx_ctx.opentelemetry["response_span_ctx"] = response_span

  if _M.should_use_deferred_sampler(ngx.var.proxy_upstream_name) then
    if _M.should_force_sample_buffered_spans(ngx.resp, ngx_ctx.opentelemetry.initial_sampling_decision) then
      ngx_ctx.opentelemetry.proxy_span_ctx:span_context().trace_flags = 1
      ngx_ctx.opentelemetry.response_span_ctx:span_context().trace_flags = 1
      ngx_ctx.opentelemetry.request_span_ctx:span_context().trace_flags = 1
      -- We need to update the child ID in the traceresponse header. To do this, we can just overwrite the traceresponse
      -- header to match the context from NGINX's outermost span (the request span) since the trace ID in the
      -- traceresponse header we received back from the proxied-to service originated in this plugin or the initial
      -- request that hit NGINX.
      traceresponse_propagator:inject(ngx_ctx.opentelemetry.request_span_ctx, ngx)
      -- remove log after testing in sandbox
      ngx.log(ngx.NOTICE, "plugin force sampling spans")
    else
      -- remove log after testing in sandbox
      ngx.log(ngx.NOTICE,
        "Plugin not force-sampling spans, initial sampling decision: ", ngx_ctx.opentelemetry.initial_sampling_decision)
    end
  end

  local header_end = otel_utils.gettimeofday_ms()
  metrics_reporter:record_value("otel.nginx.header_phase_ms", header_end - header_start)
end

function _M.log()
  if _M.request_is_bypassed(ngx.var.proxy_upstream_name) or not _M.request_has_tracing_headers() then
    return
  end

  local log_start = otel_utils.gettimeofday_ms()
  local ngx_ctx = ngx.ctx
  if not ngx_ctx["opentelemetry"] then
    ngx.log(ngx.ERR,
      "Bailing from log(). ngx_ctx['opentelemetry'] is nil")
    return
  end

  -- close proxy span using end time from header_filter
  ngx_ctx.opentelemetry.proxy_span_ctx.sp:finish(ngx_ctx.opentelemetry.proxy_span_end_time)

  -- close response span
  ngx_ctx.opentelemetry.response_span_ctx.sp:finish()

  -- close request span
  ngx_ctx.opentelemetry.request_span_ctx.sp:finish()

  -- Send stats now that the log phase is over.
  local log_end = otel_utils.gettimeofday_ms()
  metrics_reporter:record_value("otel.nginx.log_phase_ms", log_end - log_start)
end

return _M
