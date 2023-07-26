local util = require("util")
local split = require("util.split")

local ngx = ngx
local math = math
local ipairs = ipairs
local tostring = tostring
local string = string
local setmetatable = setmetatable
local string_format = string.format
local table_insert = table.insert

local PICK_SET_SIZE = 2

local _M = { name = "least_requests" }

local function incr_req_count(endpoint, by)
  local result, err = ngx.shared.balancer_least_requests:incr(endpoint, by, 0, 0)
  if err ~= nil then
    ngx.log(ngx.ERR, string_format("Error incrementing endpoint %s: %s", endpoint, err))
    return nil, err
  end

  return result
end

local function get_request_count(endpoint)
  local value, err = ngx.shared.balancer_least_requests:get(endpoint)
  if err ~= nil then
    ngx.log(ngx.ERR, string_format("Error fetching endpoint %s: %s", endpoint, err))
    return nil, err
  end

  return value or 0
end

local function get_upstream_name(upstream)
   return upstream.address .. ":" .. upstream.port
end

local function debug_header(endpoint)
  if ngx.var.arg_debug_headers then
    local count = tostring(get_request_count(endpoint))
    ngx.header["X-Served-By"] =
      "served-by;desc=" .. endpoint .. ";current-requests=" .. count
  end
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

local function pick_lowest_count(peers, k)
  shuffle_peers(peers, k)
  local lowest_count_index = 1
  local lowest_count = get_request_count(get_upstream_name(peers[lowest_count_index]))

  for i = 2, k do
    local new_count = get_request_count(get_upstream_name(peers[i]))
    if new_count < lowest_count then
      lowest_count_index, lowest_count = i, new_count
    end
  end

  return peers[lowest_count_index]
end

function _M.is_affinitized()
  return false
end

function _M.balance(self)
  local peers = self.peers
  local endpoint = peers[1]

  if #peers > 1 then
    local k = (#peers < PICK_SET_SIZE) and #peers or PICK_SET_SIZE

    local tried_endpoints
    if not ngx.ctx.balancer_least_requests_tried_endpoints then
      tried_endpoints = {}
      ngx.ctx.balancer_least_requests_tried_endpoints = tried_endpoints
    else
      tried_endpoints = ngx.ctx.balancer_least_requests_tried_endpoints
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
      endpoint = pick_lowest_count(filtered_peers, k)
    else
      endpoint = filtered_peers[1]
    end

    tried_endpoints[get_upstream_name(endpoint)] = true
  end

  local upstream = get_upstream_name(endpoint)
  incr_req_count(upstream, 1)
  debug_header(upstream)

  return upstream
end

function _M.after_balance(_)
  local upstream = split.get_last_value(ngx.var.upstream_addr)

  if util.is_blank(upstream) then
    return
  end

  incr_req_count(upstream, -1)
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

  ngx.log(
    ngx.INFO,
    string_format("[%s] peers have changed for backend %s", self.name, backend.name)
  )

  self.peers = backend.endpoints

  for _, endpoint_string in ipairs(normalized_endpoints_removed) do
    ngx.shared.balancer_least_requests:delete(endpoint_string)
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
