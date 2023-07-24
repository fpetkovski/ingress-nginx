local resty_lock = require("resty.lock")
local util = require("util")
local split = require("util.split")
local duration_parser = require("util.duration_parsing")

local ngx = ngx
local math = math
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local string = string
local setmetatable = setmetatable
local string_format = string.format
local table_insert = table.insert
local ngx_log = ngx.log
local INFO = ngx.INFO

local LOCK_KEY = ":ewma_server_timing_key"
local PICK_SET_SIZE = 2
local SERVER_TIMING_HEADER = "Server-Timing"
local SERVER_TIMING_UTIL = "util"

local ewma_lock, ewma_lock_err = resty_lock:new(
  "balancer_ewma_server_timing_locks", {timeout = 0, exptime = 0.1}
)
if not ewma_lock then
  error(ewma_lock_err)
end

local _M = { name = "ewma" }

local function lock(upstream)
  local _, err = ewma_lock:lock(upstream .. LOCK_KEY)
  if err then
    if err ~= "timeout" then
      ngx.log(
        ngx.ERR,
        string.format("EWMA Server-Timing Balancer failed to lock: %s", tostring(err))
      )
    end
  end

  return err
end

local function unlock()
  local ok, err = ewma_lock:unlock()
  if not ok then
    ngx.log(ngx.ERR, string.format("EWMA Balancer failed to unlock: %s", tostring(err)))
  end

  return err
end

local function store_stats(upstream, ewma, now)
  local success, err, forcible = ngx.shared.balancer_ewma_server_timing_last_touched_at:set(
    upstream, now
  )
  if not success then
    ngx.log(ngx.WARN, "balancer_ewma_server_timing_last_touched_at:set failed " .. err)
  end
  if forcible then
    ngx.log(
      ngx.WARN,
      "balancer_ewma_server_timing_last_touched_at:set valid items forcibly overwritten"
    )
  end

  success, err, forcible = ngx.shared.balancer_ewma_server_timing:set(upstream, ewma)
  if not success then
    ngx.log(ngx.WARN, "balancer_ewma_server_timing:set failed " .. err)
  end
  if forcible then
    ngx.log(ngx.WARN, "balancer_ewma_server_timing:set valid items forcibly overwritten")
  end
end

local function get_or_update_ewma(upstream, state, update)
  local lock_err = nil
  if update then
    lock_err = lock(upstream)
  end
  local ewma = ngx.shared.balancer_ewma_server_timing:get(upstream) or 0
  if lock_err ~= nil then
    return ewma, lock_err
  end

  local now = ngx.now()

  if not update then
    return ewma, nil
  end

  store_stats(upstream, state, now)

  unlock()

  return ewma, nil
end


local function get_upstream_name(upstream)
   return upstream.address .. ":" .. upstream.port
end


local function score(upstream)
  -- Original implementation used names
  -- Endpoints don't have names, so passing in IP:Port as key instead
  local upstream_name = get_upstream_name(upstream)
  return get_or_update_ewma(upstream_name, 0, false)
end

-- implementation similar to https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle
-- or https://en.wikipedia.org/wiki/Random_permutation
-- loop from 1 .. k
-- pick a random value r from the remaining set of unpicked values (i .. n)
-- swap the value at position i with the value at position r
local function shuffle_peers(peers, k)
  for i=1, k do
    local rand_index = math.random(i,#peers)
    peers[i], peers[rand_index] = peers[rand_index], peers[i]
  end
  -- peers[1 .. k] will now contain a randomly selected k from #peers
end

local function pick_and_score(peers, k)
  shuffle_peers(peers, k)
  local lowest_score_index = 1
  local lowest_score = score(peers[lowest_score_index])
  for i = 2, k do
    local new_score = score(peers[i])
    if new_score < lowest_score then
      lowest_score_index, lowest_score = i, new_score
    end
  end

  return peers[lowest_score_index], lowest_score
end

-- slow_start_ewma is something we use to avoid sending too many requests
-- to the newly introduced endpoints. We currently use average ewma values
-- of existing endpoints.
local function calculate_slow_start_ewma(self)
  local total_ewma = 0
  local endpoints_count = 0

  for _, endpoint in pairs(self.peers) do
    local endpoint_string = get_upstream_name(endpoint)
    local ewma = ngx.shared.balancer_ewma_server_timing:get(endpoint_string)

    if ewma then
      endpoints_count = endpoints_count + 1
      total_ewma = total_ewma + ewma
    end
  end

  if endpoints_count == 0 then
    ngx.log(ngx.INFO, "no ewma value exists for the endpoints")
    return nil
  end

  return total_ewma / endpoints_count
end

function _M.is_affinitized()
  return false
end

function _M.balance(self)
  local peers = self.peers
  local endpoint, ewma_score = peers[1], -1

  if #peers > 1 then
    local k = (#peers < PICK_SET_SIZE) and #peers or PICK_SET_SIZE

    local tried_endpoints
    if not ngx.ctx.balancer_ewma_server_timing_tried_endpoints then
      tried_endpoints = {}
      ngx.ctx.balancer_ewma_server_timing_tried_endpoints = tried_endpoints
    else
      tried_endpoints = ngx.ctx.balancer_ewma_server_timing_tried_endpoints
    end

    local filtered_peers
    for _, peer in ipairs(peers) do
      if not tried_endpoints[get_upstream_name(peer)] then
        if not filtered_peers then
          filtered_peers = {}
        end
        table_insert(filtered_peers, peer)
      end
    end

    if not filtered_peers then
      ngx.log(ngx.WARN, "all endpoints have been retried")
      filtered_peers = util.deepcopy(peers)
    end

    if #filtered_peers > 1 then
      endpoint, ewma_score = pick_and_score(filtered_peers, k)
    else
      endpoint, ewma_score = filtered_peers[1], score(filtered_peers[1])
    end

    tried_endpoints[get_upstream_name(endpoint)] = true
  end

  ngx.var.balancer_ewma_server_timing_score = ewma_score

  -- TODO(elvinefendi) move this processing to _M.sync
  return get_upstream_name(endpoint)
end

function _M.after_balance(_)
  local upstream = split.get_first_value(ngx.var.upstream_addr)
  local raw_server_timing = ngx.ctx.server_timing_internal or ngx.header[SERVER_TIMING_HEADER]

  ngx.log(
    ngx.DEBUG,
    string.format("Read header `%s`: %s", SERVER_TIMING_HEADER, tostring(raw_server_timing))
  )

  if util.is_blank(upstream) or util.is_blank(raw_server_timing) then
    return
  end

  local state, err = duration_parser.duration(raw_server_timing, SERVER_TIMING_UTIL)
  if err ~= nil then
    ngx.log(
      ngx.WARN,
      string.format("Server timing balancer unable to parse header: %s", tostring(err))
    )
    return
  end

  get_or_update_ewma(upstream, state, true)
end

function _M.sync(self, backend)
  self.traffic_shaping_policy = backend.trafficShapingPolicy
  self.alternative_backends = backend.alternativeBackends

  local normalized_endpoints_added, normalized_endpoints_removed =
    util.diff_endpoints(self.peers, backend.endpoints)

  if #normalized_endpoints_added == 0 and #normalized_endpoints_removed == 0 then
    ngx.log(ngx.INFO, "endpoints did not change for backend " .. tostring(backend.name))
    return
  end

  ngx_log(INFO, string_format("[%s] peers have changed for backend %s", self.name, backend.name))

  self.peers = backend.endpoints

  for _, endpoint_string in ipairs(normalized_endpoints_removed) do
    ngx.shared.balancer_ewma_server_timing:delete(endpoint_string)
    ngx.shared.balancer_ewma_server_timing_last_touched_at:delete(endpoint_string)
  end

  local slow_start_ewma = calculate_slow_start_ewma(self)
  if slow_start_ewma ~= nil then
    local now = ngx.now()
    for _, endpoint_string in ipairs(normalized_endpoints_added) do
      store_stats(endpoint_string, slow_start_ewma, now)
    end
  end
end

function _M.new(self, backend)
  local o = {
    peers = backend.endpoints,
    traffic_shaping_policy = backend.trafficShapingPolicy,
    alternative_backends = backend.alternativeBackends,
  }
  setmetatable(o, self)
  self.__index = self
  return o
end

return _M
