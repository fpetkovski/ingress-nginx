local ngx = ngx
local math = math
local ipairs = ipairs
local string = string
local setmetatable = setmetatable
local string_format = string.format
local table_insert = table.insert
local tostring = tostring
local util = require("util")

local _M = { name = "random" }

local function get_upstream_name(upstream)
   return upstream.address .. ":" .. upstream.port
end

function _M.is_affinitized()
  return false
end

function _M.balance(self)
  local peers = self.peers
  local endpoint = get_upstream_name(peers[1])

  if #peers > 1 then
    local tried_endpoints
    if ngx.ctx.balancer_random_tried_endpoints then
      tried_endpoints = ngx.ctx.balancer_random_tried_endpoints
    else
      tried_endpoints = {}
      ngx.ctx.balancer_random_tried_endpoints = tried_endpoints
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

    local rand_index =  math.random(#filtered_peers)
    endpoint = get_upstream_name(filtered_peers[rand_index])
    tried_endpoints[endpoint] = true
  end

  return endpoint
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
    ngx.INFO, string_format("[%s] peers have changed for backend %s", self.name, backend.name)
  )

  self.peers = backend.endpoints
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
