--------------------------------------------------------------------------------
-- Sampler for use in deferred sampling. If parent context is sampled, then
-- record_and_sample; otherwise record_only. main.lua will update spans'
-- sampling decision after the proxied-to service has responded.
--------------------------------------------------------------------------------
local result = require("opentelemetry.trace.sampling.result")
local setmetatable = setmetatable

local _M = {}

local mt = {
    __index = _M
}

--------------------------------------------------------------------------------
-- Create a new instance of the deferred_sampler.
--
-- @return sampler instance
--------------------------------------------------------------------------------
function _M.new()
    return setmetatable({}, mt)
end

function _M.should_sample(_, params)
    local tracestate = params.parent_ctx:span_context().trace_state
    if params.parent_ctx:span_context().trace_flags and params.parent_ctx:span_context():is_sampled() then
        return result.new(result.record_and_sample, tracestate)
    else
        return result.new(result.record_only, tracestate)
    end
end

return _M
