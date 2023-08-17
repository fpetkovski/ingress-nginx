local error = error
local string = string
local tonumber = tonumber
local tostring = tostring

local MAGELLAN_SERVICE = "load_shedder_config"

local magellan = require("plugins.magellan.main")
magellan.register(MAGELLAN_SERVICE)

local load_shedder_config = require("plugins.load_shedder.cached_config").new(MAGELLAN_SERVICE)

local DEFAULT_ENABLED = false
local DEFAULT_SOFT_LIMIT = 1.0
local DEFAULT_HARD_LIMIT = 2.0
local DEFAULT_MAX_DROP_RATE = 0.7
local DEFAULT_TENANT_SHARE_LIMIT = 0.1
local DEFAULT_SHEDDABLE_CHECKOUTS = false
local DEFAULT_PREVENT_SHOPS_SHEDDABLE_CHECKOUTS = false
local DEFAULT_PREVENT_ALL_CHECKOUT_SHEDDING_GLOBALLY = false
local DEFAULT_UPSTREAMS = {}

local _M = {}

function _M.clear_cache()
  load_shedder_config:clear_cache()
end

function _M.enabled()
  return tostring(load_shedder_config:get("enabled")) == 'true' or DEFAULT_ENABLED
end

function _M.pod_tenancy_override(pod_id)
  -- These values are interpreted in tenant.lua and match values set via spy
  local override = load_shedder_config:get_expirable_value('pods', tostring(pod_id), 'tenancy')
  if override then
    return string.upper(override)
  end
end

function _M.shop_tenancy_override(shop_id)
  -- These values are interpreted in tenant.lua and match values set via spy
  local override = load_shedder_config:get_expirable_value('shops', tostring(shop_id), 'tenancy')
  if override then
    return string.upper(override)
  end
end

function _M.limits(controller_class)
  if controller_class == "unicorn" then
    local limits = load_shedder_config:get("limits") or {}
    return tonumber(limits.soft_limit or DEFAULT_SOFT_LIMIT),
           tonumber(limits.hard_limit or DEFAULT_HARD_LIMIT),
           tonumber(limits.max_drop_rate or DEFAULT_MAX_DROP_RATE)
  else
    error("unrecognized controller_class=" .. tostring(controller_class))
  end
end

function _M.shop_tenant_share_limit(shop_id)
  local share_limit_override = load_shedder_config:get_expirable_value(
    'shops', tostring(shop_id), 'tenant_share'
  )
  if share_limit_override then
    return tonumber(share_limit_override)
  end

  local limits = load_shedder_config:get("limits") or {}
  return tonumber(limits.tenant_share_limit) or tonumber(DEFAULT_TENANT_SHARE_LIMIT)
end

function _M.pod_tenant_share_limit(pod_id)
  local share_limit_override = load_shedder_config:get_expirable_value(
    'pods', tostring(pod_id), 'tenant_share'
  )
  if share_limit_override then
    return tonumber(share_limit_override)
  end

  local limits = load_shedder_config:get("limits") or {}
  return tonumber(limits.tenant_share_limit or DEFAULT_TENANT_SHARE_LIMIT)
end

function _M.upstreams()
  return load_shedder_config:get("upstreams") or DEFAULT_UPSTREAMS
end

function _M.sheddable_checkouts(shop_id)
  local shop_override = load_shedder_config:get_expirable_value(
    'shops', tostring(shop_id), 'sheddable_checkouts'
  )
  return tostring(shop_override) == 'true' or DEFAULT_SHEDDABLE_CHECKOUTS
end

function _M.prevent_shops_sheddable_checkouts(shop_id)
  local shop_override = load_shedder_config:get_expirable_value(
    'shops', tostring(shop_id), 'prevent_shops_sheddable_checkouts'
  )
  return tostring(shop_override) == 'true' or DEFAULT_PREVENT_SHOPS_SHEDDABLE_CHECKOUTS
end

function _M.prevent_all_checkout_shedding_globally()
  local global_override = load_shedder_config:get_expirable_value(
    "global", "-1", 'prevent_all_checkout_shedding_globally'
  )
  return tostring(global_override) == 'true' or DEFAULT_PREVENT_ALL_CHECKOUT_SHEDDING_GLOBALLY
end

return _M
