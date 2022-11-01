local util = require("util")

local original_ngx = ngx
local function reset_ngx()
  _G.ngx = original_ngx
end

describe("Balancer chashboundedloads", function()
  local balancer_chashboundedloads = require("balancer.chashboundedloads")
  local backend, instance

  before_each(function()
    balancer_chashboundedloads = require_without_cache("balancer.chashboundedloads")

    backend = {
      name = "namespace-service-port", ["load-balance"] = "ewma",
      upstreamHashByConfig = { ["upstream-hash-by"] = "$request_uri", ["upstream-hash-by-balance-factor"] = 2,  ["upstream-hash-by"] = "$request_uri" },
      endpoints = {
        { address = "10.10.10.1", port = "8080", maxFails = 0, failTimeout = 0 },
        { address = "10.10.10.2", port = "8080", maxFails = 0, failTimeout = 0 },
        { address = "10.10.10.3", port = "8080", maxFails = 0, failTimeout = 0 },
      }
    }

    ngx.header = {}
    ngx.req = {
      get_uri_args = function()
        return {}
      end
    }

    instance = balancer_chashboundedloads:new(backend)
  end)

  after_each(function()
    reset_ngx()
    ngx.var = {}
    ngx.ctx = {}
  end)

  it("sets balance_factor", function()
    backend = {
      name = "namespace-service-port", ["load-balance"] = "ewma",
      upstreamHashByConfig = { ["upstream-hash-by"] = "$request_uri", ["upstream-hash-by-balance-factor"] = 2.5,  ["upstream-hash-by"] = "$request_uri" },
      endpoints = {
        { address = "10.10.10.1", port = "8080", maxFails = 0, failTimeout = 0 },
        { address = "10.10.10.2", port = "8080", maxFails = 0, failTimeout = 0 },
        { address = "10.10.10.3", port = "8080", maxFails = 0, failTimeout = 0 },
      }
    }

    instance = balancer_chashboundedloads:new(backend)
    assert.are.equals(2.5, instance.balance_factor)
  end)

  it("does not allow balance_factor <= 1", function()
    local new_backend = util.deepcopy(backend)
    new_backend.upstreamHashByConfig["upstream-hash-by-balance-factor"] = 1

    instance = balancer_chashboundedloads:new(new_backend)
    assert.are.equals(2, instance.balance_factor)

    new_backend.upstreamHashByConfig["upstream-hash-by-balance-factor"] = 0.1
    instance = balancer_chashboundedloads:new(new_backend)
    assert.are.equals(2, instance.balance_factor)
  end)

  it("sets default balance factor", function()
    backend = {
      name = "namespace-service-port", ["load-balance"] = "ewma",
      upstreamHashByConfig = { ["upstream-hash-by"] = "$request_uri",  ["upstream-hash-by"] = "$request_uri" },
      endpoints = {
        { address = "10.10.10.1", port = "8080", maxFails = 0, failTimeout = 0 },
        { address = "10.10.10.2", port = "8080", maxFails = 0, failTimeout = 0 },
        { address = "10.10.10.3", port = "8080", maxFails = 0, failTimeout = 0 },
      }
    }

    instance = balancer_chashboundedloads:new(backend)
    assert.are.equals(2, instance.balance_factor)
  end)

  it("uses round-robin and does not touch counters when hash_by value is missing", function()
    ngx.var = { request_uri = nil }

    instance.roundrobin = {
      find = function(self)
        return "some-round-robin-endpoint"
      end
    }

    local endpoint = instance:balance()
    assert.are.equals("some-round-robin-endpoint", endpoint)
    assert.are.same({}, instance.requests_by_endpoint)
    assert.are.equals(0, instance.total_requests)

    instance:after_balance()
    assert.are.same({}, instance.requests_by_endpoint)
    assert.are.equals(0, instance.total_requests)
  end)

  it("skips tried endpoint", function()
    ngx.var = { request_uri = "/alma/armud" }

    ngx.ctx.balancer_chashbl_tried_endpoints = {["10.10.10.1:8080"]=true}
    local endpoint = instance:balance()

    assert.are.equals("10.10.10.2:8080", endpoint)

    assert.are.same({["10.10.10.2:8080"] = 1}, instance.requests_by_endpoint)
    assert.are.equals(1, instance.total_requests)
  end)

  it("after_balance decrements all tried endpoints", function()
    instance.requests_by_endpoint["10.10.10.1:8080"] = 1
    instance.requests_by_endpoint["10.10.10.2:8080"] = 1
    instance.total_requests = 2

    ngx.var = { request_uri = "/alma/armud", upstream_addr = "10.10.10.1:8080 : 10.10.10.2:8080" }

    instance:after_balance()

    assert.are.same({}, instance.requests_by_endpoint)
    assert.are.equals(0, instance.total_requests)
  end)

  it("spills over", function()
    ngx.var = { request_uri = "/alma/armud" }
    local endpoint = instance:balance()
    assert.are.equals("10.10.10.1:8080", endpoint)

    assert.are.same({["10.10.10.1:8080"] = 1}, instance.requests_by_endpoint)
    assert.are.equals(1, instance.total_requests)

    ngx.ctx.balancer_chashbl_tried_endpoints = nil

    local endpoint = instance:balance()
    assert.are.equals("10.10.10.1:8080", endpoint)

    assert.are.same({["10.10.10.1:8080"] = 2}, instance.requests_by_endpoint)
    assert.are.equals(2, instance.total_requests)

    ngx.ctx.balancer_chashbl_tried_endpoints = nil

    local endpoint = instance:balance()
    assert.are.equals("10.10.10.2:8080", endpoint)

    assert.are.same({["10.10.10.1:8080"] = 2, ["10.10.10.2:8080"] = 1}, instance.requests_by_endpoint)
    assert.are.equals(3, instance.total_requests)
  end)

  it("balances and keeps track of requests", function()
    local expected_endpoint = instance.chash:find("/alma/armud")

    ngx.var = { request_uri = "/alma/armud" }
    local endpoint = instance:balance()
    assert.are.equals(expected_endpoint, endpoint)

    assert.are.same({[expected_endpoint] = 1}, instance.requests_by_endpoint)
    assert.are.equals(1, instance.total_requests)

    ngx.var = { upstream_addr = endpoint }

    instance:after_balance()
    assert.are.same({}, instance.requests_by_endpoint)
    assert.are.equals(0, instance.total_requests)
  end)

  it("starts from the beginning of the ring if first_endpoints points to the end of ring", function()
    instance.chash = {
      find = function(self, key)
        return "10.10.10.3:8080"
      end
    }
    instance.requests_by_endpoint["10.10.10.3:8080"] = 2
    instance.total_requests = 2

    ngx.var = { request_uri = "/alma/armud" }
    local endpoint = instance:balance()
    assert.are.equals("10.10.10.1:8080", endpoint)
  end)

  it("balances to the first when all endpoints have identical load", function()
    instance.requests_by_endpoint["10.10.10.1:8080"] = 2
    instance.requests_by_endpoint["10.10.10.2:8080"] = 2
    instance.requests_by_endpoint["10.10.10.3:8080"] = 2
    instance.total_requests = 6

    local expected_endpoint = instance.chash:find("/alma/armud")

    ngx.var = { request_uri = "/alma/armud" }
    local endpoint = instance:balance()
    assert.are.equals(expected_endpoint, endpoint)
  end)

  describe("is_affinitized()", function()
    it("returns false is alternative_backends is empty", function()
      instance.alternative_backends = nil
      assert.is_false(instance:is_affinitized())

      instance.alternative_backends = {}
      assert.is_false(instance:is_affinitized())
    end)

    it("returns false if tenant was not seen", function()
      ngx.var = { request_uri = "/alma/armud" }

      instance.alternative_backends = {"omglol"}
      assert.is_false(instance:is_affinitized())
    end)

    it("returns true if tenant was seen", function()
      ngx.var = { request_uri = "/alma/armud" }

      instance.alternative_backends = {"omglol"}
      instance.seen_hash_by_values:set("/alma/armud", true)
      assert.is_true(instance:is_affinitized())
    end)
  end)

  describe("sync()", function()
    it("updates endpoints and total_endpoints", function()
      local new_backend = util.deepcopy(backend)
      new_backend.endpoints[4] = { address = "10.10.10.4", port = "8080", maxFails = 0, failTimeout = 0 },

      assert.are.same({"10.10.10.1:8080", "10.10.10.2:8080", "10.10.10.3:8080"}, instance.endpoints)
      assert.are.equal(3, instance.total_endpoints)
      assert.are.same({["10.10.10.1:8080"] = 1,["10.10.10.2:8080"] = 2, ["10.10.10.3:8080"] = 3}, instance.endpoints_reverse)
      instance:sync(new_backend)

      assert.are.same({"10.10.10.1:8080", "10.10.10.2:8080", "10.10.10.3:8080", "10.10.10.4:8080"}, instance.endpoints)
      assert.are.equal(4, instance.total_endpoints)
      assert.are.same({["10.10.10.1:8080"] = 1,["10.10.10.2:8080"] = 2, ["10.10.10.3:8080"] = 3, ["10.10.10.4:8080"] = 4}, instance.endpoints_reverse)
    end)

    it("updates chash and roundrobin", function()
      instance.roundrobin = {
        reinit = function(self, nodes)
          self.nodes = nodes
        end
      }

      instance.chash = {
        reinit = function(self, nodes)
          self.nodes = nodes
        end
      }

      local new_backend = util.deepcopy(backend)
      new_backend.endpoints[4] = { address = "10.10.10.4", port = "8080", maxFails = 0, failTimeout = 0 },
      assert.are.equal(3, instance.total_endpoints)

      instance:sync(new_backend)
      assert.are.equal(4, instance.total_endpoints)
      assert.are.same({["10.10.10.1:8080"] = 1,["10.10.10.2:8080"] = 1,["10.10.10.4:8080"] = 1,["10.10.10.3:8080"] = 1}, instance.roundrobin.nodes)
      assert.are.same(instance.roundrobin.nodes, instance.chash.nodes)
    end)

    it("updates balance-factor", function()
      local new_backend = util.deepcopy(backend)
      new_backend.upstreamHashByConfig["upstream-hash-by-balance-factor"] = 4

      instance:sync(new_backend)

      assert.are.equal(4, instance.balance_factor)
    end)
  end)
end)
