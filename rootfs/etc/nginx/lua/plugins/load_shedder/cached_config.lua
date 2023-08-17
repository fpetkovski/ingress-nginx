local error = error
local ngx = ngx
local setmetatable = setmetatable
local tonumber = tonumber
local tostring = tostring
local type = type

local util = require('plugins.load_shedder.shopify_utils')
local json = require("cjson")

local _M = {}
_M.__index = _M

local DEFAULT_CACHE_TTL_SECONDS = 2
local EXPIRE_AT_KEY = "expire_at"
local VALUE_KEY = "value"

local caches = {}

local function new_cache(ttl_s)
  local cache = {}
  local reset_time = 0

  local clear = function(now)
    cache = {}
    reset_time = now
  end

  local get = function(key)
    local now = ngx.now()
    if now >= (reset_time + ttl_s) then
      clear(now)
    end

    return cache[key]
  end

  local set = function(key, value)
    cache[key] = value
  end

  return {
    get = get,
    set = set,
    clear = clear,
  }
end

local function config_cache(self)
  if not caches[self.dict] then
    caches[self.dict] = new_cache(self.cache_ttl_s)
  end
  return caches[self.dict]
end

local function evaluate_field(self, key)
  local dict = ngx.shared[self.dict]
  if not dict then
    error("accessing missing dict: " .. tostring(self.dict))
  end

  local field = dict:get(key)
  local ret = util.optimistic_json_decode(field)

  -- Treat json.null as nil. See https://docs.coronalabs.com/api/library/json/decode.html
  if ret == json.null then
    return nil
  end
  return ret
end

local function get_or_evaluate_field(self, key)
  local cache = config_cache(self)

  if not cache.get(key) then
    cache.set(key, evaluate_field(self, key))
  end
  return cache.get(key)
end

-- Reads configuration fields from a shared dictionary that's been registered with magellan:
-- * Caches fields for 2 seconds by default. Interface methods are safe to be called in hot paths
-- * Automatically digs fields out of nested hashes. e.g, config.get("limits", "shops", "123456")
-- * Supports fields with an expiry time. The expirable field must have a `expire_at` unix timestamp
--
-- Here's an example config showcasing the features:
--
-- {
--   // regular fields
--   "default_limits": {
--     "soft": 1.0,
--     "hard": 2.0
--   },
--
--   // expirable values (special case of expirable fields)
--   "default_tenant_quota": {
--     "value": 0.1,
--     "expire_at": 1572308481
--   }
--
--   // expirable fields
--   "active_shedders": {
--     "by_shop": {
--       "2939277": {
--         "limits": { "soft": 0.8, "hard": 1.5 },
--         "expire_at": 1572308481
--       }
--     },
--   }
-- }
function _M.new(dict, cache_ttl_s)
  if cache_ttl_s == nil or cache_ttl_s <= 0 then
    cache_ttl_s = DEFAULT_CACHE_TTL_SECONDS
  end

  return setmetatable({ dict = dict, cache_ttl_s = cache_ttl_s }, _M)
end

function _M:clear_cache()
  return config_cache(self).clear(ngx.now())
end

function _M:get(key, ...)
  local field = get_or_evaluate_field(self, key)
  if type(field) == 'table' then
    return util.dig(field, ...)
  end
  return field
end

function _M:get_expirable(key, ...)
  local expirable_field = self:get(key, ...)
  if not expirable_field then
    return
  end

  if not expirable_field[EXPIRE_AT_KEY] or
      ngx.now() >= tonumber(expirable_field[EXPIRE_AT_KEY]) then
    return
  end
  return expirable_field
end

function _M:get_expirable_value(key, ...)
  local expirable_field = self:get_expirable(key, ...)
  if not expirable_field then
    return
  end
  return expirable_field[VALUE_KEY]
end

return _M
