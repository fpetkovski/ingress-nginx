local math = math
local ngx = ngx
local setmetatable = setmetatable
local tostring = tostring

local _M = {}
_M.__index = _M

-- Creates a new rate tracker, using a given dict and key prefix.
-- window_duration specifies the minimum length of time (in ms) to sample before
-- rolling over to a new window.
function _M.new(dict_name, key, window_duration)
  local dict = ngx.shared[dict_name]
  if not dict then
    return nil, "shared dict not found"
  end

  return setmetatable(
    { dict = dict, dict_name = dict_name, key = key, window_duration = window_duration },
    _M
  )
end

local function build_count_key(prefix, time, window_duration)
  return prefix .. tostring(math.floor(time / window_duration)) .. ":count"
end

local function dict_incr_or_init(dict, key, value, expiry)
  value = value or 1

  ::retry::
  local conn, err = dict:incr(key, value)
  if conn then
    -- key already existed, and was atomically incremented
    return conn, err, false
  end

  if err ~= "not found" then
    -- unknown error, bail out
    return nil, err
  end

  -- At the time incr returned, the key did not exist.
  -- Try adding it now.
  local ok
  ok, err = dict:add(key, value, expiry)
  if ok then
    -- key was atomically added, adds from other calls will fail with "exists"
    return value, err, true
  end

  if err == "exists" then
    -- key was added by another concurrent call.
    -- At this point, the retried call to incr will succeed.
    goto retry
  end

  -- unknown error
  return nil, err
end

local function update_and_fetch(self, increment_count, time)
  local dict = self.dict
  local window = self.window_duration
  local now = time or (ngx.now() * 1000) -- ms

  local count_key = build_count_key(self.key, now, window)
  local key_expiry = (self.window_duration * 2) / 1000 -- seconds

  local window_count, err, rolled_over_window = dict_incr_or_init(
    dict,
    count_key,
    increment_count,
    key_expiry
  )
  if err then
    return nil, nil, err
  end

  return window_count, rolled_over_window
end

-- Signals an incoming event that should be tracked.
-- Returns the new number of events in the window, and a boolean indicating
-- if the previous window was ended on this call.
function _M:incoming(incr_count)
  return update_and_fetch(self, incr_count or 1)
end

-- Returns the number of events in the current window, and a boolean indicating
-- if the previous window was ended on this call.
function _M:count()
  return update_and_fetch(self, 0)
end

-- Returns the number of events in the last window.
function _M:last_count()
  local last_window_time = ngx.now() * 1000 - self.window_duration
  return update_and_fetch(self, 0, last_window_time)
end

return _M
