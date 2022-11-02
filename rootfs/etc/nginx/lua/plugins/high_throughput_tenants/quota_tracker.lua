-- Original author: Hormoz Kheradmand (2019)

local rate_tracker = require("plugins.high_throughput_tenants.rate")

local ngx = ngx
local setmetatable = setmetatable
local tostring = tostring

local _M = {}
_M.__index = _M

local DEFAULT_WINDOW_SIZE_MS = 15000

-- Only consider returning any values when at least once time window has passed
local ENABLE_ROLLOVER_SAFETY = true

--
-- A quota tracker instance keeps track of the percentage of capacity (a
-- metric, denoted by +metric_name+, that measures time usually) being used by
-- some scope (a subset of the previous metric) so that we can determine if a
-- shop / pod / section / etc is exceeding their fair share (e.g. we could
-- enforce a policy where a pod is allowed to only take up 10% of capacity
-- during overload state).
--
--
-- How does it work?
--
--   The total_rate counter sums up a metric (e.g. app server time) used by every
--   request passing through the nginx instance.
--
--   The scope_rate counter sums up a metric used by a shop/pod/scope - a subset
--   of the total_rate counter.
--
--   The division of the two counters gives us the ratio (i.e. percentage) of
--   our capacity that was being used by that shop/pod/scope in the last
--   +window_size_ms+ milliseconds.

function _M.new(dict_name, metric_name, window_size_ms)
  window_size_ms = window_size_ms or DEFAULT_WINDOW_SIZE_MS

  -- ensure shared dictionary exists before we use it in the rate.lua module
  if not ngx.shared[dict_name] then
    return nil, "shared dict: " .. dict_name .. " was not found"
  end

  return setmetatable({
    dict_name = dict_name,
    metric_name = metric_name,
    window_size_ms = window_size_ms,
  }, _M)
end

-- most likely error would be an OOM on the rate trackers' shared dictionary
local function emit_err(err)
  ngx.log(ngx.ERR, "quota tracker failed: " .. tostring(err))
end

local function tracker_for(self, key)
  local prefix = self.metric_name .. ":" .. tostring(key) .. ":"
  return rate_tracker.new(self.dict_name, prefix, self.window_size_ms)
end

local function current_and_last_count(tracker)
  local c1, _, err = tracker:last_count()
  if err then
    emit_err(err)
    return 0
  end

  -- wait for the first window to roll over before assuming valid data
  if c1 <= 0 and ENABLE_ROLLOVER_SAFETY then
    return 0
  end

  local c2
  c2, _, err = tracker:count()
  if err then
    emit_err(err)
    return 0
  end

  return c1 + c2
end

function _M:add(scope_key, weight)
  if weight <= 0 then
    return
  end

  local _, _, err = tracker_for(self, "_total"):incoming(weight)
  if err then
    emit_err(err)
  end

  _, _, err = tracker_for(self, scope_key):incoming(weight)
  if err then
    emit_err(err)
  end
end

function _M:usage(scope_key)
  return current_and_last_count(tracker_for(self, scope_key)),
         current_and_last_count(tracker_for(self, "_total"))
end

function _M:share(scope_key)
  local scope_rate, total_rate = self:usage(scope_key)
  if total_rate <= 0 then
    return 0
  end

  return scope_rate / total_rate
end

return _M
