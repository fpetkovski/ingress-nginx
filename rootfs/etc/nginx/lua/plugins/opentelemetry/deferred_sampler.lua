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
    -- This should_sample method is built to expect params.parent_ctx to be a
    -- span_context (not a full context object). Once
    -- https://github.com/yangxikun/opentelemetry-lua/issues/48 has been merged,
    -- we'll need to update it to expect a full context object.
    if params.parent_ctx.trace_flags and params.parent_ctx:is_sampled() then
        return result.new(result.record_and_sample, params.parent_ctx.trace_state)
    else
        return result.new(result.record_only, params.parent_ctx.trace_state)
    end
end

return _M
