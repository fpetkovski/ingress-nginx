local ipairs = ipairs
local unpack = unpack
local ngx = ngx
local string = string
local tostring = tostring
local table = table

local queue = {}
local MAX_QUEUE_SIZE = 10000
local FLUSH_INTERVAL = 1

local _M = {}

local function flush_queue()
  local current_queue = queue
  queue = {}

  for _,v in ipairs(current_queue) do
    v.func(unpack(v.args))
  end
end

function _M.init_worker()
  local _, err = ngx.timer.every(FLUSH_INTERVAL, flush_queue)
  if err then
    ngx.log(ngx.ERR,
      string.format("error when setting up timer.every for flush_queue: %s",
      tostring(err)))
  end
end

function _M.enqueue(func, ...)
  if #queue >= MAX_QUEUE_SIZE then
    return "deferred timer queue full"
  end

  table.insert(queue, { func = func, args = {...} })
end

setmetatable(_M, {__index = {
  MAX_QUEUE_SIZE = MAX_QUEUE_SIZE,
  get_queue = function() return queue end,
  flush_queue = flush_queue,
}})

return _M
