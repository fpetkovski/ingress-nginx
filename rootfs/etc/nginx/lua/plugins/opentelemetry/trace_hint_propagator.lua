--------------------------------------------------------------------------------
-- The propagator injects an x-shopify-trace-hint header
-- headers
--------------------------------------------------------------------------------

local setmetatable       = setmetatable
local text_map_getter    = require("opentelemetry.trace.propagation.text_map.getter")
local text_map_setter    = require("opentelemetry.trace.propagation.text_map.setter")

local _M = {}

local mt = {
    __index = _M,
}

local SHOPIFY_HINT_KEY = "x-shopify-trace-hint"

function _M.new()
    return setmetatable(
        {
            text_map_setter = text_map_setter.new(),
            text_map_getter = text_map_getter.new()
        }, mt
    )
end

--------------------------------------------------------------------------------
-- Add trace hint header to request
--
-- @param context       context storage
-- @param carrier       nginx request
-- @param setter        setter for interacting with carrier
-- @return nil
--------------------------------------------------------------------------------
function _M:inject(context, carrier, setter)
    setter = setter or self.text_map_setter

    -- inject trace hint
    setter.set(carrier, SHOPIFY_HINT_KEY, "true")
end

--------------------------------------------------------------------------------
-- Extract is a noop for the trace hint propagator
--
-- @param context       context storage
-- @param carrier       nginx request
-- @param getter        getter for interacting with carrier
-- @return nil
--------------------------------------------------------------------------------
function _M:extract(context, _carrier, _getter)
    -- noop
    return context
end

return _M
