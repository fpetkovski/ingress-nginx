local ngx_timer_every = ngx.timer.every
local ngx_timer_at = ngx.timer.at
local ngx = ngx

local _M = {}

local function interval_thread(premature, all_workers, func, ...)
  if premature or ngx.worker.exiting() then return end
  if all_workers or ngx.worker.id() == 0 then
    func(...)
  end
end

-- limit_concurrent returns a function that wrap callback_func
-- to only allow one concurrent call to callback_func
local function limit_concurrent(callback_func)
  local callback_running = false
  return function(...)
    if callback_running then
        ngx.log(ngx.ERR, "callback for timer not executed")
        return
    end

    callback_running = true
    callback_func(...)
    callback_running = false
  end
end

function _M.execute_at_interval(interval, all_workers, func, ...)
  local limited_cb = limit_concurrent(interval_thread)

  -- Schedule a run ASAP, useful to initialize some things right after nginx startup
  -- even if the interval is high
  ngx_timer_at(0, limited_cb, all_workers, func, ...)

  -- Schedule a recurring timer every `interval`
  ngx_timer_every(interval, limited_cb, all_workers, func, ...)
end

-- luacheck: ignore ngx
if ngx['shopify'] and ngx.shopify.env == "test" then
  _M.__limit_concurrent = limit_concurrent
end

return _M
