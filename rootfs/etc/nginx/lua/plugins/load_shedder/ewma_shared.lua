-- Original Authors: Shiv Nagarajan & Scott Francis
-- Accessed: March 12, 2018
-- Inspiration drawn from:
-- https://github.com/twitter/finagle/blob/1bc837c4feafc0096e43c0e98516a8e1c50c4421
--   /finagle-core/src/main/scala/com/twitter/finagle/loadbalancer/PeakEwma.scala
--
-- Adapted for use by load_shedder.lua
local math = math
local ngx = ngx
local tonumber = tonumber
local tostring = tostring

local util = require("plugins.load_shedder.shopify_utils")

local _M = {
  DECAY_TIME = 20, -- this value is in seconds
  EWMA_DICT = "load_shedder_ewma",
}

util.assert_dict(_M.EWMA_DICT)

-- See https://stackoverflow.com/a/1027808 for a good explanation of how weight is derived
local function decay_ewma(ewma, last_touched_at, value, now)
  local td = now - last_touched_at
  td = (td > 0) and td or 0
  local weight = math.exp(-td/_M.DECAY_TIME)

  ewma = ewma * weight + value * (1.0 - weight)
  return ewma
end

local function store_ewma(upstream, ewma, now)
  local val = tostring(ewma) .. ":" .. tostring(now)
  local success, err, forcible = ngx.shared[_M.EWMA_DICT]:set(upstream, val)
  if not success then
    ngx.log(ngx.WARN, _M.EWMA_DICT..":set failed " .. err)
  end
  if forcible then
    ngx.log(
      ngx.WARN,
      _M.EWMA_DICT..":set overwrote existing entries since shared memory was full;" ..
                    " check load_shedder.util_ewma_dict_free_bytes"
    )
  end
end

local function get_ewma(upstream)
  local val = ngx.shared[_M.EWMA_DICT]:get(upstream)
  if not val then
    return 0, 0
  end

  local ewma, last_touched_at = util.split_pair(val, ":")
  return tonumber(ewma), tonumber(last_touched_at)
end

function _M.get(upstream)
  return get_ewma(upstream)
end

function _M.update(upstream, value)
  local ewma, last_touched_at = get_ewma(upstream)
  local now = ngx.now()

  ewma = decay_ewma(ewma, last_touched_at, value, now)
  store_ewma(upstream, ewma, now)

  return ewma, now
end

return _M
