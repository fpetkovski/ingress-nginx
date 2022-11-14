local original_ngx = ngx
local function reset_ngx()
  _G.ngx = original_ngx
end

local function mock_ngx(mock)
  local _ngx = mock
  setmetatable(_ngx, { __index = ngx })
  _G.ngx = _ngx
end

describe('high_throughput_tenants middleware', function()
  local high_throughput_tenants

  before_each(function()
    ngx.shared.high_throughput_tracker:flush_all()

    now = 0
    mock_ngx({
      now = function()
        return now / 1000
      end
    })
    high_throughput_tenants = require_without_cache("plugins.high_throughput_tenants.main")
  end)

  after_each(function()
    reset_ngx()
  end)

  describe('rewrite phase', function()
    local function set_quotas(k, r)
      ngx.shared.high_throughput_tracker:set(k..":_total:-1:count", 100)
      ngx.shared.high_throughput_tracker:set(k..":123:-1:count", 100 * r)
      ngx.shared.high_throughput_tracker:set(k..":_total:0:count", 100)
      ngx.shared.high_throughput_tracker:set(k..":123:0:count", 100 * r)
    end

    local headers = {}

    before_each(function()
      ngx.var = { http_x_sorting_hat_shopid = 123 }

      ngx.req = {
        set_header = function(h, v)
          headers[h] = v
        end
      }
    end)

    after_each(function()
      headers = {}
    end)

    it("sets the header to time share when it's bigger", function()
      set_quotas("t", 0.5)
      set_quotas("c", 0.1)

      high_throughput_tenants.rewrite()

      assert.are.same("0.50", headers["X-High-Throughput-Tenant"])
    end)

    it("sets the header to count share when it's bigger", function()
      set_quotas("t", 0.1)
      set_quotas("c", 0.5)

      high_throughput_tenants.rewrite()

      assert.are.same("0.50", headers["X-High-Throughput-Tenant"])
    end)

    it("sets header to zero", function()
      high_throughput_tenants.rewrite()

      assert.are.same("0.00", headers["X-High-Throughput-Tenant"])
    end)
  end)

  describe('log phase', function()
    it("tracks time and count", function()
      ngx.var = { http_x_sorting_hat_shopid = 123 }
      ngx.resp = {
        get_headers = function()
          return { ["Server-Timing"] = "processing;dur=100" }
        end
      }

      high_throughput_tenants.log()

      assert.are.equal(100, ngx.shared.high_throughput_tracker:get("t:_total:0:count"))
      assert.are.equal(100, ngx.shared.high_throughput_tracker:get("t:123:0:count"))
      assert.are.equal(1, ngx.shared.high_throughput_tracker:get("c:_total:0:count"))
      assert.are.equal(1, ngx.shared.high_throughput_tracker:get("c:123:0:count"))
    end)

    it("tracks upstream_response_time if server-timing is missing", function()
      ngx.var = { http_x_sorting_hat_shopid = 123, upstream_response_time = "0.2" }
      ngx.resp = {
        get_headers = function()
          return { }
        end
      }

      high_throughput_tenants.log()

      assert.are.equal(200, ngx.shared.high_throughput_tracker:get("t:_total:0:count"))
      assert.are.equal(200, ngx.shared.high_throughput_tracker:get("t:123:0:count"))
      assert.are.equal(1, ngx.shared.high_throughput_tracker:get("c:_total:0:count"))
      assert.are.equal(1, ngx.shared.high_throughput_tracker:get("c:123:0:count"))
    end)


    it("tracks only count if upstream_response_time and server-timing are missing", function()
      ngx.var = { http_x_sorting_hat_shopid = 123, upstream_response_time = nil }
      ngx.resp = {
        get_headers = function()
          return { }
        end
      }

      high_throughput_tenants.log()

      assert.are.equal(nil, ngx.shared.high_throughput_tracker:get("t:_total:0:count"))
      assert.are.equal(nil, ngx.shared.high_throughput_tracker:get("t:123:0:count"))
      assert.are.equal(1, ngx.shared.high_throughput_tracker:get("c:_total:0:count"))
      assert.are.equal(1, ngx.shared.high_throughput_tracker:get("c:123:0:count"))
    end)

    it("does not track if tenant is missing", function()
      ngx.var = { }
      ngx.resp = {
        get_headers = function()
          return { ["Server-Timing"] = "processing;dur=100" }
        end
      }

      high_throughput_tenants.log()

      assert.are.equal(nil, ngx.shared.high_throughput_tracker:get("t:_total:0:count"))
      assert.are.equal(nil, ngx.shared.high_throughput_tracker:get("t:123:0:count"))
      assert.are.equal(nil, ngx.shared.high_throughput_tracker:get("c:_total:0:count"))
      assert.are.equal(nil, ngx.shared.high_throughput_tracker:get("c:123:0:count"))
    end)
  end)
end)
