--------------------------------------------------------------------------------
-- This propagator extracts context from and injects Shopify-specific HTTP
-- headers
--------------------------------------------------------------------------------

local setmetatable       = setmetatable
local ngx                = ngx
local string             = string
local tracestate         = require("opentelemetry.trace.tracestate")
local text_map_getter    = require("opentelemetry.trace.propagation.text_map.getter")
local text_map_setter    = require("opentelemetry.trace.propagation.text_map.setter")
local shopify_utils      = require("plugins.opentelemetry.shopify_utils")
local span_context_new   = require("opentelemetry.trace.span_context").new
local empty_span_context = span_context_new()

local _M = {
    INVALID_TRACE_ID = "00000000000000000000000000000000",
    INVALID_SPAN_ID = "0000000000000000"
}

local mt = {
    __index = _M,
}
-- regex reflects https://github.com/Shopify/opentelemetry-go-shopify/blob/25419c7222c379496fec0b4a519c9b51b7399755/shopify-tracing.go#L60-L63
local SHOPIFY_HEADER_REGEXP = '^(\\w{32})(/(\\d+))?(;o=(\\d+))?'
local GKE_HEADER_KEY = "x-cloud-trace-context"
local SHOPIFY_HEADER_KEY = "x-shopify-trace-context"
local TRACESTATE_HEADER_KEY = "tracestate"

function _M.new()
    return setmetatable(
        {
            text_map_setter = text_map_setter.new(),
            text_map_getter = text_map_getter.new()
        }, mt
    )
end

--------------------------------------------------------------------------------
-- Add shopify-specific HTTP headers to request
--
-- @param context       context storage
-- @param carrier       nginx request
-- @param setter        setter for interacting with carrier
-- @return nil
--------------------------------------------------------------------------------
function _M:inject(context, carrier, setter)
    setter = setter or self.text_map_setter
    local span_id, err
    local span_context = context:span_context()

    if span_context.span_id then
        span_id, err = shopify_utils.hex_to_decimal_string(span_context.span_id)
        if err then
            ngx.log(ngx.WARN, "error while converting hex span_id to decimal: ", err)
            return
        end
    end

    if span_id == _M.INVALID_SPAN_ID then
        ngx.log(ngx.WARN, "invalid span_id: " .. span_id)
        return
    end

    if span_context.trace_id == _M.INVALID_TRACE_ID then
        ngx.log(ngx.WARN, "invalid trace_id: " .. span_context.trace_id)
        return
    end

    local sampled = span_context:is_sampled() and "1" or "0"
    local header_value = string.format("%s/%s;o=%s", span_context.trace_id, span_id, sampled)

    -- inject Shopify headers
    setter.set(carrier, SHOPIFY_HEADER_KEY, header_value)
    setter.set(carrier, GKE_HEADER_KEY, header_value)

    if span_context.trace_state then
        setter.set(carrier, TRACESTATE_HEADER_KEY, span_context.trace_state:as_string())
    end
end

--------------------------------------------------------------------------------
-- Look at shopify-specific HTTP headers and extract trace context
--
-- @param context       context storage
-- @param carrier       nginx request
-- @param getter        getter for interacting with carrier
-- @return nil
--------------------------------------------------------------------------------
function _M:extract(context, carrier, getter)
    getter = getter or self.text_map_getter

    local shopify_header = getter.get(carrier, SHOPIFY_HEADER_KEY)
    local gke_header = getter.get(carrier, GKE_HEADER_KEY)

    if not shopify_header or not gke_header then
        -- If we don't have both these headers, we don't trust either of them.
        -- As such, return original context.
        return context
    end

    local captures, err = ngx.re.match(gke_header, SHOPIFY_HEADER_REGEXP)
    if err then
        ngx.log(ngx.ERR, "propagator extract - error while matching " .. GKE_HEADER_KEY .. err)
        return context:with_span_context(empty_span_context)
    end

    if not captures then
        ngx.log(ngx.INFO, "propagator extract - no matches found in trace propagation header " .. GKE_HEADER_KEY)
        return context:with_span_context(empty_span_context)
    end

    local trace_id = captures[1]
    local raw_span_id = captures[3]
    local raw_sampled = captures[5]

    if raw_span_id == _M.INVALID_SPAN_ID then
        ngx.log(ngx.WARN, "propagator extract - invalid span id found: " .. raw_span_id)
        return context:with_span_context(empty_span_context)
    end

    if trace_id == _M.INVALID_TRACE_ID then
        ngx.log(ngx.WARN, "propagator extract - invalid trace id found: " .. trace_id)
        return context:with_span_context(empty_span_context)
    end

    local span_id
    if raw_span_id then
        span_id, err = shopify_utils.decimal_to_hex_string(raw_span_id)

        if err then
            ngx.log(ngx.ERR, "propagator extract - error while converting decimal span_id to hex: ", err)
            return context:with_span_context(empty_span_context)
        end
    end

    local sampled = raw_sampled == "1" and 1 or "0"
    local trace_state = tracestate.parse_tracestate(
        getter.get(carrier, TRACESTATE_HEADER_KEY))

    -- TODO: handle traceflags better. Currently there's only one bit, which is
    -- for whether or not the trace is sampled. In the future, this will change.
    -- See https://www.w3.org/TR/trace-context/#trace-flags.
    return context:with_span_context(
        span_context_new(trace_id, span_id, sampled, trace_state, true))
end

return _M
