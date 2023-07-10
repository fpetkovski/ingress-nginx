local busted = require('busted')
local assert = require('luassert')

local function has_service(name)
  return ngx.shared.registered_services:get(name) ~= nil
end

local _shared_dict = { __index = {
  get_stale = function(self, key)
      if key == nil then error("nil key") end
      return self._vals[key], {}, false
  end,
  get = function(self, key)
      if key == nil then error("nil key") end
      return self._vals[key]
  end,
  set = function(self, key, val, expires)
      if key == nil then error("nil key") end
      self._vals[key] = val
      return true, nil, false
  end,
  delete = function(self, key)
      return self:set(key, nil)
  end,
  incr = function(self, key, val)
      if not self:get(key) then return nil, "not found" end
      self:set(key, self:get(key) + val)
      return self:get(key), nil
  end,
  add = function(self, key, val)
      if self:get(key) then return false, "exists", false end
      return self:set(key, val)
  end,
  get_keys = function(self, count)
      local keys = {}
      for key, _ in pairs(self._vals) do
        table.insert(keys, key)
      end
      return keys
  end
}}

describe("plugins.magellan.main:", function()

  local old_getenv = _G.os.getenv

  setup(function()
    os.getenv = function(str)
      local hash = { KUBE_LOCATION = "gcp-north-northwest-1" }
      return hash[str]
    end
    ngx.shopify = { env = "test" }
  end)

  teardown(function()
    os.getenv = old_getenv
  end)

  before_each(function()
    ngx.shared.registered_services = setmetatable({_vals = {}}, _shared_dict)
    ngx.shared.registered_services_ttl = setmetatable({_vals = {}}, _shared_dict)
    ngx.shared.registered_services_version = setmetatable({_vals = {}}, _shared_dict)
    ngx.shared.registered_services_using_regional = setmetatable({_vals = {}}, _shared_dict)
    ngx.shared.dicts_test = setmetatable({_vals = {}}, _shared_dict)
    magellan = require('plugins.magellan.main')
    http = require('resty.http')
  end)

  describe("init_worker", function()
    it("returns without error", function()
      local config = {
        plugin_magellan_endpoint = 'endpoint',
        plugin_magellan_service_identifier = 'service_identifier',
        plugin_magellan_keepalive_timeout = 5000,
        plugin_magellan_keepalive_pool_size = 100,
        plugin_magellan_timer_poll_interval = '0.2',
      }
      local ok, err = magellan.init_worker(config)
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("configures the plugin vars", function()
      local config = {
        plugin_magellan_endpoint = 'endpoint',
        plugin_magellan_service_identifier = 'service_identifier',
        plugin_magellan_keepalive_timeout = 5000,
        plugin_magellan_keepalive_pool_size = 100,
        plugin_magellan_timer_poll_interval = '0.2',
      }
      local ok, err = magellan.init_worker(config)
      assert.are.same('endpoint', magellan.plugin_magellan_endpoint)
      assert.are.same('service_identifier', magellan.plugin_magellan_service_identifier)
      assert.are.same(5000, magellan.plugin_magellan_keepalive_timeout)
      assert.are.same(100, magellan.plugin_magellan_keepalive_pool_size)
      -- allow a small tollerance for floating point comparison errors
      assert.is.near(0.2, magellan.plugin_magellan_timer_poll_interval, 0.00001)
    end)
  end)

  describe("service_name", function()
    it("should return the service name", function()
      magellan.plugin_magellan_service_identifier = 'magellan_service_identifier'
      local service_name = magellan.service_name('env', 'service')
      assert.are.same('env_magellan_service_identifier_service', service_name)
    end)
  end)

  describe("get_service", function()
    it("throws error if name is blank", function()
      local service, err = magellan.get_service("")
      assert.are.equal("magellan: must pass a non-blank name to get_service", err)
      assert.are.equal(nil, service)
    end)

    it("throws error if http request fails", function()
      http.new = function()
        return {
          request_uri = function(self, uri, opts)
            return nil, "http request failed"
          end,
        }
      end

      local service, err = magellan.get_service("my-service")
      assert.are.equal("magellan: error performing http request err=http request failed", err)
      assert.are.equal(nil, service)
    end)

    it("throws error if http request has non-200 status", function()
      http.new = function()
        return {
          request_uri = function(self, uri, opts)
            return {status = 500, body = "error 500" }, nil
          end,
        }
      end

      local service, err = magellan.get_service("my-service")
      assert.are.equal("magellan: failed to get service status=\"500\" body=\"error 500\"", err)
      assert.are.equal(nil, service)
    end)

    it("throws error if body doesnt json decode", function()
      http.new = function()
        return {
          request_uri = function(self, uri, opts)
            return {
              status = 200,
              body = "{not json}"
            }, nil
          end,
        }
      end

      local service, err = magellan.get_service("my-service")
      assert.are.equal("magellan: failed to decode service body=\"{not json}\" " ..
        "err=\"Expected object key string but found invalid token at character 2\"", err)
      assert.are.equal(nil, service)
    end)

    it("returns the service body", function()
      http.new = function()
        return {
          request_uri = function(self, uri, opts)
            return {
              status = 200,
              body = [[{"name":"production_nginx_my-service","body":{"foo":"bar"}}]],
            }
          end,
        }
      end

      local service, err = magellan.get_service("my-service")
      assert.are.equal(nil, err)
      assert.are.equal("table", type(service))
      assert.are.equal("production_nginx_my-service", service.name)
      assert.are.equal("table", type(service.body))
      assert.are.equal("bar", service.body.foo)
    end)
  end)

  describe("register", function()

    it("warns and returns nil if dict doesnt exist", function()
      ngx.log = spy.new(function() end)
      local result = magellan.register("no_dict")
      assert.spy(ngx.log).was.called_with(ngx.WARN, "could not find dictionary for service no_dict")
      assert.is_nil(result)
    end)

    it("doesnt allow empty service names", function()
      ngx.shared[""] = {}
      local result, err = magellan.register("")
      assert.is_nil(result)
      assert.are.equal(err, "service: must pass a non-blank service name to register")
      assert.is_false(has_service(""))
    end)

    it("adds the registered service", function()
      magellan.register("dicts_test")
      assert.is_true(has_service("dicts_test"))
    end)

    it("uses the appropriate service name", function()
      magellan.get_service = spy.new(function() end)
      magellan.register("dicts_test")
      magellan.force_fetch()
      assert.spy(magellan.get_service).was.called_with("production_ngx_config_dicts_test")
    end)
  end)

  describe("register_with_local_memory", function()
    it("doesn't register service if dict does not exist", function()
      local result = magellan.register_with_local_memory("no_dict")
      assert.is_nil(result)
    end)

    it("adds the service name", function()
      magellan.register_with_local_memory("dicts_test")
      assert.is_true(has_service("dicts_test"))
    end)

    it("doesn't register service name if it's blank", function()
      magellan.register_with_local_memory("")
      assert.is_false(has_service(""))
    end)
  end)

  describe("register_with_region_suffix", function()
    it("registers with the using_regional dict", function()
      magellan.register_with_regional_suffix("dicts_test")
      assert.is_true(ngx.shared.registered_services_using_regional:get("dicts_test"))
    end)

    it("does not register with the using_regional dict", function()
      magellan.register("dicts_test")
      assert.is_false(ngx.shared.registered_services_using_regional:get("dicts_test"))
    end)

    it("uses appropriate service name", function()
      magellan.get_service = spy.new(function() end)
      magellan.register_with_regional_suffix("dicts_test")
      magellan.force_fetch()
      assert.spy(magellan.get_service).was.called_with("production_ngx_config_dicts_test_north_northwest_1")
    end)
  end)

  describe("unregister", function()
    it("removes the service name", function()
      magellan.register("dicts_test")
      assert.is_true(has_service("dicts_test"))
      magellan.unregister("dicts_test")
      assert.is_false(has_service("dicts_test"))
    end)
  end)

  describe("get_service_body_from_local_memory", function()
    it("returns the service body", function()
      assert.is_false(has_service("dicts_test"))
      assert.is_nil(magellan.get_service_body_from_local_memory("dicts_test"))
      magellan.register_with_local_memory("dicts_test")
      assert.equal(#magellan.get_service_body_from_local_memory("dicts_test"), 0)
    end)
  end)
end)
