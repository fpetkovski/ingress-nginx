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

-- Given baggage in the current context
-- When the verbosity_key is present in baggage
-- Then should_sample returns true
--------------------------------------------------------------------------------

local setmetatable = setmetatable
local tonumber = tonumber
local result_new = require("opentelemetry.trace.sampling.result").new
local span_kind = require("opentelemetry.trace.span_kind")
local string = string

-- verbosity key should be kept in sync with https://github.com/Shopify/opentelemetry-ruby-shopify/blob/master/opentelemetry-shopify/lib/opentelemetry/shopify.rb#L45
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
        verbosity_probability = verbosity_probability or 1,
        verbosity_id_upper_bound = (verbosity_probability or 1) * tonumber("ffffffff", 16),
    }, mt)
end

function _M.verbose_probability_sampled(self, trace_id)
    return tonumber(string.sub(trace_id, 9, 16), 16) < self.verbosity_id_upper_bound
end

function _M.should_sample(self, params)
    -- discard malformed trace_ids
    if string.len(params.trace_id) ~= 32 then
        return result_new(RESULT_CODES.drop, params.parent_ctx.trace_state)
    end

    if ALWAYS_SAMPLE[params.kind] then
        return result_new(RESULT_CODES.record_and_sample, params.parent_ctx.trace_state)
    end

    if self:verbose_probability_sampled(params.trace_id) then
        return result_new(RESULT_CODES.record_and_sample, params.parent_ctx.trace_state)
    else
        return result_new(RESULT_CODES.drop, params.parent_ctx.trace_state)
    end
end

return _M
