package.path = "./rootfs/etc/nginx/lua/plugins/load_shedder/test/?.lua;./rootfs/etc/nginx/lua/plugins/load_shedder/test/helpers/?.lua;" .. package.path
require("helpers.init")
require("helpers.load_shedder")

local busted = require('busted')
local assert = require('luassert')
local json = require("cjson")
local configuration = require("plugins.load_shedder.configuration")

local function set_config(dict, key, config)
  if type(config) == "table" then
    local ok, config = pcall(json.encode, config)
    if not ok then
      assert(false)
    end
  end

  ngx.shared[dict]:set(key, config)
end

local function set_unicorn_config(key, config)
  set_config("load_shedder_config", key, config)
end

local function set_limit(key, value)
  local config = {}
  config[key] = value
  set_unicorn_config('limits', { [key] = value })
end

local now
function stub_time()
  now = 0
  register_stub(ngx, 'now', function()
    return now / 1000
  end)
end

function advance_time_ms(delta_ms)
  now = now + delta_ms
end


describe("plugins.load_shedder.configuration", function()

  before_each(function()
    ngx.reset()
    stub_time()
    configuration.clear_cache()
  end)

  it("enabled_state_is_configurable", function()
    assert.are.equal(false, configuration.enabled())

    set_unicorn_config('enabled', true)
    assert.are.equal(true, configuration.enabled())
  end)

  it("enabled_returns_default_if_config_syntax_invalid", function()
    set_unicorn_config('enabled', "invalid JSON")
    assert.are.equal(configuration.enabled(), false)
  end)

  it("soft_limit_is_configurable", function()
    local soft_limit, _, _ = configuration.limits("unicorn")
    assert.are.equal(soft_limit, 1.0)

    set_limit('soft_limit', 1.5)
    soft_limit, _, _ = configuration.limits("unicorn")
    assert.are.equal(soft_limit, 1.5)
  end)

  it("soft_limit_is_configurable_as_string", function()
    local soft_limit, _, _ = configuration.limits("unicorn")
    assert.are.equal(soft_limit, 1.0)

    set_limit('soft_limit', '1.5')
    soft_limit, _, _ = configuration.limits("unicorn")
    assert.are.equal(soft_limit, 1.5)
  end)

  it("hard_limit_is_configurable", function()
    local _, hard_limit, _ = configuration.limits("unicorn")
    assert.are.equal(hard_limit, 2.0)

    set_limit('hard_limit', 3.0)
    _, hard_limit, _ = configuration.limits("unicorn")
    assert.are.equal(hard_limit, 3.0)
  end)

  it("hard_limit_is_configurable_as_string", function()
    local _, hard_limit, _ = configuration.limits("unicorn")
    assert.are.equal(hard_limit, 2.0)

    set_limit('hard_limit', '3.0')
    _, hard_limit, _ = configuration.limits("unicorn")
    assert.are.equal(hard_limit, 3.0)
  end)

  it("max_drop_rate_is_configurable", function()
    local _, _, max_drop_rate = configuration.limits("unicorn")
    assert.are.equal(max_drop_rate, 0.7)

    set_limit('max_drop_rate', 1.0)
    _, _, max_drop_rate = configuration.limits("unicorn")
    assert.are.equal(max_drop_rate, 1.0)
  end)

  it("max_drop_rate_is_configurable_as_string", function()
    local _, _, max_drop_rate = configuration.limits("unicorn")
    assert.are.equal(max_drop_rate, 0.7)

    set_limit('max_drop_rate', '1.0')
    _, _, max_drop_rate = configuration.limits("unicorn")
    assert.are.equal(max_drop_rate, 1.0)
  end)

  it("tenant_share_limit_returns_defaults_if_global_json_syntax_invalid", function()
    set_unicorn_config('limits', 'invalid JSON')
    assert.are.equal(configuration.pod_tenant_share_limit('42'), 0.1)
  end)

  it("tenant_share_limit_is_configurable", function()
    assert.are.equal(configuration.pod_tenant_share_limit(), 0.1)

    set_limit('tenant_share_limit', 0.5)
    assert.are.equal(configuration.pod_tenant_share_limit(), 0.5)
  end)

  it("tenant_share_limit_is_configurable_as_string", function()
    assert.are.equal(configuration.pod_tenant_share_limit(), 0.1)

    set_limit('tenant_share_limit', '0.5')
    assert.are.equal(configuration.pod_tenant_share_limit(), 0.5)
  end)

  it("upstreams_are_configurable", function()
    assert.are.same(configuration.upstreams(), { })

    local expected_upstreams = { abc=protect, def=ignore }
    set_unicorn_config('upstreams', expected_upstreams)
    assert.are.same(configuration.upstreams(), expected_upstreams)
  end)

  it("tenancy_overrides_return_nil_if_json_syntax_invalid", function()
    set_unicorn_config('pods', 'invalid JSON')
    set_unicorn_config('shops', 'invalid JSON')

    assert.is_nil(configuration.pod_tenancy_override('42'))
    assert.is_nil(configuration.shop_tenancy_override('42'))
  end)

  -- Note: applying overrides is tested in tenant_test.lua
  it("pod_tenancy_override_defaults_to_nil", function()
    assert.is_nil(configuration.pod_tenancy_override(1))
  end)

  it("shop_tenancy_override_defaults_to_nil", function()
    assert.is_nil(configuration.shop_tenancy_override(1))
  end)

  it("pod_tenancy_override_expires_at_can_be_string", function()
    set_tenancy_override('pods', '42', tostring(ngx.now() + 1), 'abusing')

    tenancy_override = configuration.pod_tenancy_override('42')
    assert.is_not_nil(tenancy_override, 'tenancy override was expired')
    assert.are.equal('ABUSING', tenancy_override)
  end)

  it("shop_tenancy_override_expires_at_can_be_string", function()
    set_tenancy_override('shops', '42', tostring(ngx.now() + 1), 'abusing')

    tenancy_override = configuration.shop_tenancy_override('42')
    assert.is_not_nil(tenancy_override, 'tenancy override was expired')
    assert.are.equal('ABUSING', tenancy_override)
  end)

  it("pod_share_limit_override_is_configurable", function()
    set_tenant_share_override('pods', '42', ngx.now() + 1, 0.456)
    set_tenant_share_override('shops', '1234', ngx.now() + 1, 0.654)

    assert.are.equal(configuration.pod_tenant_share_limit('42'), 0.456)
    assert.are.equal(configuration.shop_tenant_share_limit('1234'), 0.654)
  end)

  it("pod_share_limit_override_respects_expire_at", function()
    set_limit('tenant_share_limit', 0.123)
    set_tenant_share_override('pods', '42', ngx.now() - 10, 0.456)
    set_tenant_share_override('shops', '1234', ngx.now() - 10, 0.654)

    assert.are.equal(configuration.pod_tenant_share_limit('42'), 0.123)
    assert.are.equal(configuration.shop_tenant_share_limit('1234'), 0.123)
  end)

  it("pod_share_limit_override_and_expires_at_are_configurable_as_strings", function()
    set_tenant_share_override('pods', '42', tostring(ngx.now() + 1), '0.456')
    set_tenant_share_override('shops', '1234', tostring(ngx.now() + 1), '0.654')

    assert.are.equal(configuration.pod_tenant_share_limit('42'), 0.456)
    assert.are.equal(configuration.shop_tenant_share_limit('1234'), 0.654)
  end)

  it("tenant_share_limits_returns_default_if_override_is_invalid_json", function()
    set_unicorn_config('pods', 'invalid JSON')

    share_limit = configuration.pod_tenant_share_limit('42')
    assert.are.equal(share_limit, 0.1)
  end)

  it("tenant_share_limit_configuration_precedence", function()
    pod_default = configuration.pod_tenant_share_limit('42')
    assert.are.equal(pod_default, 0.1)
    shop_default = configuration.shop_tenant_share_limit('1234')
    assert.are.equal(shop_default, 0.1)

    set_limit('tenant_share_limit', 0.1234)
    assert.are.equal(configuration.pod_tenant_share_limit('42'), 0.1234)
    assert.are.equal(configuration.shop_tenant_share_limit('1234'), 0.1234)

    set_tenant_share_override('pods', '42', ngx.now() + 1, 0.456)
    assert.are.equal(configuration.pod_tenant_share_limit('42'), 0.456)
    set_tenant_share_override('shops', '1234', ngx.now() + 1, 0.654)
    assert.are.equal(configuration.shop_tenant_share_limit('1234'), 0.654)
  end)

  -- These tests use pod_tenancy_override but are intended to exercise the get_tenant_override() code path
  it("tenant_override_with_nil_expire_at_returns_nil", function()
    set_tenancy_override('pods', '42', nil, 0.456)

    assert.are.equal(configuration.pod_tenancy_override('42'), nil)
  end)

  it("tenant_override_with_nil_value_returns_nil", function()
    set_tenancy_override('pods', '42', ngx.now() + 1, nil)

    assert.are.equal(configuration.pod_tenancy_override('42'), nil)
  end)

  it("sheddable_checkouts_is_configurable", function()
    assert.False(configuration.sheddable_checkouts('33'))

    set_tenant_override('shops', '33', 'sheddable_checkouts', ngx.now() + 1, true)
    assert.True(configuration.sheddable_checkouts('33'))

    set_tenant_override('shops', '33', 'sheddable_checkouts', ngx.now() + 1, 'true')
    assert.True(configuration.sheddable_checkouts('33'))
  end)

  it("sheddable_checkouts_is_false_by_default", function()
    assert.False(configuration.sheddable_checkouts(1))
  end)

  it("sheddable_checkouts_is_false_when_shop_id_nil", function()
    assert.False(configuration.sheddable_checkouts(nil))
  end)

  it("cached_values", function()
    local soft_limit, _, _ = configuration.limits("unicorn")
    assert.are.equal(soft_limit, 1.0)

    -- We only have the default value, so this is the first we're
    -- setting the soft_limit explicitly. This is why we see it
    -- even though the time hasn't advanced - the default value
    -- isn't cached, there is no json for it.
    set_limit('soft_limit', 1.5)
    soft_limit, _, _ = configuration.limits("unicorn")
    assert.are.equal(soft_limit, 1.5)

    set_limit('soft_limit', 2.5)
    soft_limit, _, _ = configuration.limits("unicorn")
    assert.are.equal(soft_limit, 1.5)

    advance_time_ms(3000) -- assumes configuration.CACHE_TTL of 2s
    soft_limit, _, _ = configuration.limits("unicorn")
    assert.are.equal(soft_limit, 2.5)
  end)

  it("deprecated_unicorn_limits_behaviour", function()
    set_unicorn_config("limits", { soft_limit=1.5 })
    set_limit('soft_limit', 2.0)

    soft_limit, _, _ = configuration.limits("unicorn");
    assert.are.equal(soft_limit, 2.0)
  end)

end)
