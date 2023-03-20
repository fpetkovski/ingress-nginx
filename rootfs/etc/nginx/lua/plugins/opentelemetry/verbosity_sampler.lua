--------------------------------------------------------------------------------
-- The verbosity sampler ensures that every request samples in one span that
-- represents when NGINX processes the request. We'll emit _verbose_ spans for a
-- configurable percentage of requests. At present, this configuration is
-- global. We should make it configurable on a per-service basis at some point.

-- The canonical implementation of Shopify's verbosity sampler is located in
-- opentelemetry-ruby-shopify:
-- https://github.com/Shopify/opentelemetry-ruby-shopify/blob/master/opentelemetry-shopify/lib/opentelemetry/shopify/verbosity_sampler.rb

-- We adhere to the following rules:

-- Given a verbosity percentage set to X%
-- When ingress-nginx processes a traceless request
-- Then ingress-nginx will emit verbose spans for X% of requests, while it will
-- emit one essential span for 1-X% of requests

-- Given a verbosity percentage set to X%
-- When ingress-nginx processes a trusted Shopify-traced request
-- Then ingress-nginx will emit verbose spans for X% of requests, while it will emit one essential span for 1-X% of requests
--------------------------------------------------------------------------------

local setmetatable = setmetatable
local tonumber = tonumber
local result_new = require("opentelemetry.trace.sampling.result").new
local span_kind = require("opentelemetry.trace.span_kind")
local string = string

local ALWAYS_SAMPLE = {}
ALWAYS_SAMPLE[span_kind.server] = true

-- There is a PR upstream to make these available on the
-- opentelemetry.trace.sampling.result package. We can remove this when that
-- gets merged
local RESULT_CODES = {
    drop = 0,
    record_only = 1,
    record_and_sample = 2
}

local _M = {}

local mt = {
    __index = _M
}

------------------------------------------------------------------
-- Create a new instance of the verbosity_sampler.
--
-- @param verbosity_probability the percentage of traces that will emit verbose spans
-- @return sampler instance
------------------------------------------------------------------
function _M.new(verbosity_probability)
    return setmetatable({
        verbosity_probability = tonumber(verbosity_probability or 1),
        verbosity_id_upper_bound = tonumber(verbosity_probability or 1) * tonumber("ffffffff", 16),
    }, mt)
end

function _M.verbose_probability_sampled(self, trace_id)
    if self.verbosity_probability == 0 then return false end;
    return tonumber(string.sub(trace_id, 9, 16), 16) < self.verbosity_id_upper_bound
end

function _M.should_sample(self, params)
    local parent_span_context = params.parent_ctx:span_context()
    local tracestate = parent_span_context.trace_state

    -- discard malformed trace_ids
    if string.len(params.trace_id) ~= 32 then
        return result_new(RESULT_CODES.drop, tracestate)
    end

    -- General note on trace_flags: span_context.trace_flags defaults to nil in
    -- opentelemetry-lua. As such, if parent_ctx:span_context() does not have trace flags, it likely came when:
    --
    -- 1. We minted a new context object upon receving a request (that context object's span context has trace_flags of
    --    nil).
    -- 2. Passed the new context object to the composite propagator's extract method, which did not successfully extract
    --    a span context from the headers, and got it right back. (i.e. there were no valid Shopify trace headers on the
    --    req)
    -- 3. Used this context object as the parent_ctx for the plugin's first span, and hence passed it to should_sample.
    if parent_span_context.trace_flags and not parent_span_context:is_sampled() then
        -- If we affirmatively know that the parent context was unsampled, we drop
        return result_new(RESULT_CODES.drop, tracestate)
    elseif ALWAYS_SAMPLE[params.kind] then
        -- Otherwise, if it's a SERVER span, we record and sample
        return result_new(RESULT_CODES.record_and_sample, tracestate)
    elseif self:verbose_probability_sampled(params.trace_id) then
        -- If it's not a server span, do some math to determine if we keep
        return result_new(RESULT_CODES.record_and_sample, tracestate)
    else
        -- Otherwise, drop
        return result_new(RESULT_CODES.drop, tracestate)
    end
end

function _M.get_description(self)
    return "ShopifyVerbositySampler{" .. self.verbosity_probability .. "}"
end

return _M
