local ngx = ngx

local request = require("plugins.load_shedder.request_priority")
local tenant = require("plugins.load_shedder.tenant")

local _M = {
  -- Lower levels will shed first
  LEVELS = {
    LEVEL_1 = 1,
    LEVEL_2 = 2,
    LEVEL_3 = 3,
    LEVEL_4 = 4,
    LEVEL_5 = 5,
    LEVEL_6 = 6,
    LEVEL_UNSHEDDABLE = 7
  },
  MAX_SHEDDABLE = 6
}

-- The current mapping is from request priorities and tenancy to levels. The alternative
-- is to set up the mapping from request rules and tenancy to levels instead, if we decide
-- we want different mapping for the requests of same priority but different rules.
-- (e.g., between low priority uri and search bots).
local LEVELS_MAP = {
  unicorn = {
    [tenant.GROUPS.ABUSING] = {
      [request.PRIORITIES.LOW] =         _M.LEVELS.LEVEL_1, -- bad/bot clients
      -- exceptional rule: shed admin AFTER storefront when we're overloaded
      [request.PRIORITIES.MEDIUM] =      _M.LEVELS.LEVEL_2, -- admin
      [request.PRIORITIES.HIGH] =        _M.LEVELS.LEVEL_1, -- storefront
      [request.PRIORITIES.UNSHEDDABLE] = _M.LEVELS.LEVEL_UNSHEDDABLE, -- checkout
      [request.PRIORITIES.UNKNOWN] =     _M.LEVELS.LEVEL_2  -- empty
    },
    [tenant.GROUPS.EXCEEDING] = {
      [request.PRIORITIES.LOW] =         _M.LEVELS.LEVEL_2,
      [request.PRIORITIES.MEDIUM] =      _M.LEVELS.LEVEL_3,
      [request.PRIORITIES.HIGH] =        _M.LEVELS.LEVEL_4,
      [request.PRIORITIES.UNSHEDDABLE] = _M.LEVELS.LEVEL_UNSHEDDABLE,
      [request.PRIORITIES.UNKNOWN] =     _M.LEVELS.LEVEL_4
    },
    [tenant.GROUPS.STANDARD] = {
      [request.PRIORITIES.LOW] =         _M.LEVELS.LEVEL_4,
      [request.PRIORITIES.MEDIUM] =      _M.LEVELS.LEVEL_5,
      [request.PRIORITIES.HIGH] =        _M.LEVELS.LEVEL_6,
      [request.PRIORITIES.UNSHEDDABLE] = _M.LEVELS.LEVEL_UNSHEDDABLE,
      [request.PRIORITIES.UNKNOWN] =     _M.LEVELS.LEVEL_UNSHEDDABLE
    }
  }
}

local function get_level(controller_class, priority, tenancy)
  if not LEVELS_MAP[controller_class] then
    return nil
  end

  if not LEVELS_MAP[controller_class][tenancy] then
    return nil
  end

  return LEVELS_MAP[controller_class][tenancy][priority]
end

function _M.get(controller_class, priority, tenancy)
  if ngx.ctx.access_level == nil then
    ngx.ctx.access_level = get_level(controller_class, priority, tenancy)
  end
  return ngx.ctx.access_level
end

return _M
