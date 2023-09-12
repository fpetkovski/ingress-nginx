local util = require("util")

local original_ngx = ngx
local function reset_ngx()
  _G.ngx = original_ngx
end

local function mock_ngx(mock)
  local _ngx = mock
  setmetatable(_ngx, { __index = ngx })
  _G.ngx = _ngx
end

describe("Balancer random", function()
  local ngx_now = 1543238266
  local backend, instance

  before_each(function()
    mock_ngx({ now = function() return ngx_now end })
    package.loaded["balancer.random"] = nil
    balancer_random = require("balancer.random")

    backend = {
      name = "namespace-service-port", ["load-balance"] = "random",
      endpoints = {
        { address = "10.10.10.1", port = "8080", maxFails = 0, failTimeout = 0 },
        { address = "10.10.10.2", port = "8080", maxFails = 0, failTimeout = 0 },
        { address = "10.10.10.3", port = "8080", maxFails = 0, failTimeout = 0 },
      }
    }

    instance = balancer_random:new(backend)
  end)

  after_each(function()
    reset_ngx()
  end)

  describe("balance()", function()
    it("returns a random endpoint", function()
      local peer = instance:balance()
      assert.is_truthy(peer:match("^10.10.10.%d+:8080$"))
    end)

    it("returns single endpoint when the given backend has only one endpoint", function()
      local single_endpoint_backend = util.deepcopy(backend)
      table.remove(single_endpoint_backend.endpoints, 3)
      table.remove(single_endpoint_backend.endpoints, 2)
      local single_endpoint_instance = balancer_random:new(single_endpoint_backend)

      local peer = single_endpoint_instance:balance()

      assert.are.equals("10.10.10.1:8080", peer)
    end)

    it("doesn't pick the tried endpoint while retry", function()
      local two_endpoints_backend = util.deepcopy(backend)
      table.remove(two_endpoints_backend.endpoints, 2)
      local two_endpoints_instance = balancer_random:new(two_endpoints_backend)

      ngx.ctx.balancer_random_tried_endpoints = {
        ["10.10.10.3:8080"] = true,
      }
      local peer = two_endpoints_instance:balance()
      assert.equal("10.10.10.1:8080", peer)
      assert.equal(true, ngx.ctx.balancer_random_tried_endpoints["10.10.10.1:8080"])
    end)
  end)

  describe("sync()", function()
    it("does not reset stats when endpoints do not change", function()
      local new_backend = util.deepcopy(backend)

      instance:sync(new_backend)

      assert.are.same(new_backend.endpoints, instance.peers)
    end)

    it("resets alternative backends and traffic shaping policy even if endpoints do not change", function()
      assert.are.same(nil, instance.alternativeBackends)
      assert.are.same(nil, instance.trafficShapingPolicy)

      local new_backend = util.deepcopy(backend)
      new_backend.alternativeBackends = {"my-canary-namespace-my-canary-service-my-port"}
      new_backend.trafficShapingPolicy = {
        cookie = "",
        header = "",
        headerPattern = "",
        headerValue = "",
        weight = 20,
      }

      instance:sync(new_backend)

      assert.are.same(new_backend.alternativeBackends, instance.alternative_backends)
      assert.are.same(new_backend.trafficShapingPolicy, instance.traffic_shaping_policy)
      assert.are.same(new_backend.endpoints, instance.peers)
    end)

    it("updates peers", function()
      local new_backend = util.deepcopy(backend)

      -- existing endpoint 10.10.10.2 got deleted
      -- and replaced with 10.10.10.4
      new_backend.endpoints[2].address = "10.10.10.4"
      -- and there's one new extra endpoint
      table.insert(new_backend.endpoints, { address = "10.10.10.5", port = "8080", maxFails = 0, failTimeout = 0 })

      instance:sync(new_backend)

      assert.are.same(new_backend.endpoints, instance.peers)
    end)
  end)
end)
