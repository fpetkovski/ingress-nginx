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

local function flush_request_count()
  ngx.shared.balancer_least_requests:flush_all()
end

local function set_endpoint_count(endpoint, count)
  ngx.shared.balancer_least_requests:set(endpoint, count)
end

local function get_endpoint_count(endpoint)
  return ngx.shared.balancer_least_requests:get(endpoint)
end

local function string_contains(str, text)
  return str:find(text, 0, true) ~= nil
end

describe("Balancer least_requests", function()
  local balancer_least_requests = require("balancer.least_requests")
  local ngx_now = 1543238266
  local backend, instance

  before_each(function()
    mock_ngx({ now = function() return ngx_now end, var = {} })

    package.loaded["balancer.least_requests"] = nil
    balancer_least_requests = require("balancer.least_requests")

    backend = {
      name = "namespace-service-port", ["load-balance"] = "least_requests",
      endpoints = {
        { address = "10.10.10.1", port = "8080", maxFails = 0, failTimeout = 0 },
        { address = "10.10.10.2", port = "8080", maxFails = 0, failTimeout = 0 },
        { address = "10.10.10.3", port = "8080", maxFails = 0, failTimeout = 0 },
      }
    }
    set_endpoint_count("10.10.10.1:8080", 0)
    set_endpoint_count("10.10.10.2:8080", 1)
    set_endpoint_count("10.10.10.3:8080", 3)

    instance = balancer_least_requests:new(backend)
  end)

  after_each(function()
    reset_ngx()
    flush_request_count()
  end)

  describe("after_balance()", function()
    it("decrements request count", function()
      ngx.var = { upstream_addr = "10.10.10.2:8080" }

      local count_before = get_endpoint_count(ngx.var.upstream_addr)
      instance:after_balance()
      local count_after = get_endpoint_count(ngx.var.upstream_addr)

      assert.are.equals(count_before - 1, count_after)
    end)
  end)

  describe("balance()", function()
    it("increments request count", function()
      single_backend = {
        name = "namespace-service-port", ["load-balance"] = "least_requests",
        endpoints = {
          { address = "10.10.10.1", port = "8080", maxFails = 0, failTimeout = 0 },
        }
      }
      set_endpoint_count("10.10.10.1:8080", 0)

      local single_instance = balancer_least_requests:new(single_backend)
      single_instance:balance()

      assert.are.equals(1, get_endpoint_count("10.10.10.1:8080"))
    end)

    it("picks the endpoint with fewest requests when there are 2", function()
      double_backend = {
        name = "namespace-service-port", ["load-balance"] = "least_requests",
        endpoints = {
          { address = "10.10.10.1", port = "8080", maxFails = 0, failTimeout = 0 },
          { address = "10.10.10.2", port = "8080", maxFails = 0, failTimeout = 0 },
        }
      }
      set_endpoint_count("10.10.10.1:8080", 3)
      set_endpoint_count("10.10.10.2:8080", 0)

      local double_instance = balancer_least_requests:new(double_backend)
      local peer = double_instance:balance()

      assert.are.equals("10.10.10.2:8080", peer)
    end)

    it("does not pick the endpoint with the most requests when there are 3", function()
      set_endpoint_count("10.10.10.1:8080", 3)
      set_endpoint_count("10.10.10.2:8080", 0)
      set_endpoint_count("10.10.10.3:8080", 5)

      local peer = instance:balance()

      -- Because we pick from 2 random choices, we can only assert that the peer with the most
      -- requests is _not_ selected
      assert.is.truthy(peer) -- i.e. not nil
      assert.are_not.equals("10.10.10.3:8080", peer)
    end)

    it("adds debug info to response headers when debug is set", function()
      set_endpoint_count("10.10.10.1:8080", 3)
      set_endpoint_count("10.10.10.2:8080", 3)
      set_endpoint_count("10.10.10.3:8080", 3)
      ngx.var.arg_debug_headers = "1"

      instance:balance()

      assert.is_true(string_contains(ngx.header["X-Served-By"], "current-requests=4"))
    end)
  end)

  describe("sync()", function()
    it("removes values for deleted endpoints", function()
      local backend_copy = util.deepcopy(backend)

      current_upstream = backend.endpoints[1].address .. ":8080"
      backend_copy.endpoints[1].address = "10.10.10.10" -- Effectively one deleted, one added

      instance:sync(backend_copy)

      assert.are.equals(nil, get_endpoint_count(current_upstream))
    end)

    it("does not flush values when endpoints have not changed", function()
      local backend_copy = util.deepcopy(backend)

      instance:sync(backend_copy)

      assert.are.same(backend_copy.endpoints, instance.peers)
      assert.are.same(backend_copy.endpoints, backend.endpoints)

      assert.are.equals(0, get_endpoint_count("10.10.10.1:8080"))
      assert.are.equals(1, get_endpoint_count("10.10.10.2:8080"))
      assert.are.equals(3, get_endpoint_count("10.10.10.3:8080"))
    end)
  end)
end)
