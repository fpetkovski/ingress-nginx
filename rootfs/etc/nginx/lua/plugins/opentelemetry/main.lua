-- set globals to locals
local error    = error
local io       = io
local ipairs   = ipairs
local ngx      = ngx
local ngx_var  = ngx.var
local pairs    = pairs
local pcall    = pcall
local table    = table
local string   = string
local tonumber = tonumber
local tostring = tostring
local unpack   = unpack

local OPENTELEMETRY_PLUGIN_VERSION = "0.2.1"

-- This file monkey-patches the upstream tracer implementation so that the
-- verbosity sampler works.
require("plugins.opentelemetry.tracer_patch")

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
local exporter_client_new = require("opentelemetry.trace.exporter.http_client").new
local otlp_exporter_new = require("opentelemetry.trace.exporter.otlp").new
local batch_span_processor_new = require("opentelemetry.trace.batch_span_processor").new
local tracer_provider_new = require("opentelemetry.trace.tracer_provider").new
local verbosity_sampler = require("plugins.opentelemetry.verbosity_sampler")
local span_kind = require("opentelemetry.trace.span_kind")
local span_status = require("opentelemetry.trace.span_status")
local resource_new = require("opentelemetry.resource").new
local attr = require("opentelemetry.attribute")
local new_context = require("opentelemetry.context").new

local _M = {}

-- This is from https://gist.github.com/h1k3r/089d43771bdf811eefe8.
-- Why not just use ngx.var to get this value? We need the hostname before it's
-- available in ngx.var, so we need to run /bin/hostname inside the container.
-- Since it's doing i/o, we should only use this function during worker
-- initialization. ApiSix uses a variant of this strategy. I think we might be
-- better off just setting an env var on the pod and reading it.
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

local function create_tracer_provider()
  -- create exporter
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

  -- We should make sampler configurable by adding support for sampler env vars
  -- to opentelemetry-lua and/or configmap. For now, we can hard-code for
  -- Shopify's purposes.
  local sampler = verbosity_sampler.new(
    _M.plugin_open_telemetry_shopify_verbosity_sampler_percentage)

  local resource_attrs = {
    attr.string("hostname", get_hostname()),
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

local function create_tracer()
  return _M.tracer_provider:tracer("ingress_nginx.plugins.opentelemetry",
    { version = OPENTELEMETRY_PLUGIN_VERSION, schema_url = "" }
  )
end

--------------------------------------------------------------------------------
-- At present, we only want to run tracing code if Shopify headers are present.
-- We use tracing_enabled to figure out whether or not to run tracing code so
-- that we do not have to make sampling decisions that propagate downstream.
--------------------------------------------------------------------------------
function _M.request_is_traced()
  local ngx_ctx = ngx.ctx

  if ngx_ctx["shopify_headers_present"] ~= nil then
    return ngx_ctx["shopify_headers_present"]
  end

  local headers = ngx.req.get_headers()
  if headers["x-cloud-trace-context"] and headers["x-shopify-trace-context"] then
    ngx_ctx["shopify_headers_present"] = true
    return true
  else
    ngx_ctx["shopify_headers_present"] = false
    return false
  end

end

--------------------------------------------------------------------------------
-- Some deployments of ingress-nginx do not let you toggle plugins with a
-- configmap (e.g. nginx-routing-modules). This function exists to give those
-- deployments a kill switch.
--------------------------------------------------------------------------------
function _M.plugin_enabled()
  return _M.plugin_open_telemetry_enabled
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

function _M.init_worker(config)
  _M.plugin_open_telemetry_enabled = config.plugin_open_telemetry_enabled
  if not _M.plugin_enabled() then
    return
  end
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

  local settings = ""
  for k, v in pairs(_M) do
    settings = settings .. k .. "=" .. tostring(v) .. " \n"
  end

  local ok, tracer_provider = pcall(create_tracer_provider)
  _M.tracer_provider = tracer_provider
  if not ok then
    ngx.log(ngx.ERR, "Failed to create tracer provider during plugin init: " .. tracer_provider)
    ngx.log(ngx.ERR, "Settings: " .. settings)
    return
  end

  local t_ok, tracer = pcall(create_tracer)
  if t_ok then
    ngx.log(ngx.INFO,
      "OpenTelemetry ingress-nginx plugin enabled. Settings: " .. settings)
    _M.tracer = tracer
    metrics_reporter.statsd.defer_to_timer.init_worker()
  end
end

function _M.rewrite()
  if not _M.plugin_enabled() then
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

  if not _M.request_is_traced() then
    return
  end
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

  local request_span_ctx = _M.tracer:start(upstream_context, "nginx.request", {
    kind = span_kind.server,
    attributes = server_attributes,
  })

  -- Assemble additional nginx.proxy span attributes
  local proxy_attributes = shopify_utils.shallow_copy(common_attributes)
  table.insert(proxy_attributes, attr.string("net.peer.name", ngx_var.proxy_host))

  local proxy_span_ctx = _M.tracer:start(request_span_ctx, "nginx.proxy", {
    kind = span_kind.client,
    attributes = proxy_attributes,
  })

  -- Inject trace context into the headers of proxy HTTP request
  composite_propagator:inject(proxy_span_ctx, ngx.req)

  ngx.ctx["opentelemetry"] = {
    request_span_ctx = request_span_ctx,
    proxy_span_ctx   = proxy_span_ctx,
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
  if not _M.plugin_enabled() or not _M.request_is_traced() then
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

  ngx_ctx.opentelemetry.proxy_span_ctx.sp:finish()
  local response_span = _M.tracer:start(ngx_ctx.opentelemetry.proxy_span_ctx, "nginx.response", {
    kind = span_kind.client,
    attributes = {},
  })
  ngx_ctx.opentelemetry["response_span_ctx"] = response_span

  local header_end = otel_utils.gettimeofday_ms()
  metrics_reporter:record_value("otel.nginx.header_phase_ms", header_end - header_start)
end

function _M.log()
  if not _M.plugin_enabled() or not _M.request_is_traced() then
    return
  end
  local log_start = otel_utils.gettimeofday_ms()
  local ngx_ctx = ngx.ctx
  if not ngx_ctx["opentelemetry"] then
    ngx.log(ngx.ERR,
      "Bailing from log(). ngx_ctx['opentelemetry'] is nil")
    return
  end

  -- close response span
  ngx_ctx.opentelemetry.response_span_ctx.sp:finish()

  -- close request span
  ngx_ctx.opentelemetry.request_span_ctx.sp:finish()

  -- Send stats now that the log phase is over.
  local log_end = otel_utils.gettimeofday_ms()
  metrics_reporter:record_value("otel.nginx.log_phase_ms", log_end - log_start)
end

return _M
