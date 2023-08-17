package.path = "./rootfs/etc/nginx/lua/plugins/load_shedder/test/?.lua;./rootfs/etc/nginx/lua/plugins/load_shedder/test/helpers/?.lua;" .. package.path
require("helpers.init")
require("helpers.load_shedder")

local busted = require('busted')
local assert = require('luassert')
local json = require("cjson")

local load_shedder = require("plugins.load_shedder.main")
local access_controller = require("plugins.load_shedder.access_controller")
local access_level = require("plugins.load_shedder.access_level")
local configuration = require("plugins.load_shedder.configuration")
local request = require("plugins.load_shedder.request_priority")
local util = require("plugins.load_shedder.shopify_utils")
local tenant = require("plugins.load_shedder.tenant")

local now
function stub_time()
  now = 2000
  register_stub(ngx, 'now', function()
    return now / 1000
  end)
end

function advance_time(delta_ms)
  now = now + delta_ms
end


describe("plugins.load_shedder.main", function()

  before_each(function()
    ngx.reset()
    reset_stubs()
    stub_time()
    configuration.clear_cache()
  end)

  local function assert_get_matches(correct_priority, correct_tenancy, correct_level, correct_rule)
    ngx.ctx.request_priority = nil
    ngx.ctx.tenancy = nil
    ngx.ctx.access_level = nil

    local priority, tenancy, level, rule =
      load_shedder.get_priority_tenancy_level_rule(ngx.ctx.shop_id,
                                                   util.get_request_header(load_shedder.SORTING_HAT_POD_ID_HEADER),
                                                   util.get_request_header(load_shedder.SORTING_HAT_POD_TYPE_HEADER))
    assert.are.equal(priority, correct_priority)
    assert.are.equal(tenancy, correct_tenancy)
    assert.are.equal(level, correct_level)
    assert.are.equal(rule, correct_rule)
  end

  it("canary_pods", function()

    ngx.req.set_header(load_shedder.SORTING_HAT_POD_ID_HEADER, '21')
    assert_get_matches(request.PRIORITIES.HIGH,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_6,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.URI_INFERENCE)

    ngx.req.set_header(load_shedder.SORTING_HAT_POD_ID_HEADER, '42')
    ngx.req.set_header(load_shedder.SORTING_HAT_POD_TYPE_HEADER, 'canary')
    assert_get_matches(request.PRIORITIES.HIGH,
                       tenant.GROUPS.ABUSING,
                       access_level.LEVELS.LEVEL_1,
                       tenant.RULES.CANARY_POD .. "+" .. request.RULES.URI_INFERENCE)
  end)

  it("shop_overrides_correct_and_respects_expire_at", function()
    set_tenancy_override("shops", "42", ngx.now() + 1, "abusing")

    ngx.ctx.shop_id = '24'
    assert_get_matches(request.PRIORITIES.HIGH,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_6,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.URI_INFERENCE)

    ngx.ctx.shop_id = '42'
    assert_get_matches(request.PRIORITIES.HIGH,
                       tenant.GROUPS.ABUSING,
                       access_level.LEVELS.LEVEL_1,
                       tenant.RULES.SHOP_OVERRIDE .. "+" .. request.RULES.URI_INFERENCE)

    advance_time(1001)

    ngx.ctx.shop_id = '24'
    assert_get_matches(request.PRIORITIES.HIGH,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_6,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.URI_INFERENCE)

    ngx.ctx.shop_id = '42'
    assert_get_matches(request.PRIORITIES.HIGH,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_6,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.URI_INFERENCE)
  end)

  it("pod_overrides_correct_and_respects_expire_at", function()
    set_tenancy_override("pods", "42", ngx.now() + 1, "exceeding")

    ngx.req.set_header(load_shedder.SORTING_HAT_POD_ID_HEADER, "24")
    assert_get_matches(request.PRIORITIES.HIGH,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_6,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.URI_INFERENCE)

    ngx.req.set_header(load_shedder.SORTING_HAT_POD_ID_HEADER, "42")
    assert_get_matches(request.PRIORITIES.HIGH,
                       tenant.GROUPS.EXCEEDING,
                       access_level.LEVELS.LEVEL_4,
                       tenant.RULES.POD_OVERRIDE .. "+" .. request.RULES.URI_INFERENCE)

    advance_time(1001)

    ngx.req.set_header(load_shedder.SORTING_HAT_POD_ID_HEADER, "24")
    assert_get_matches(request.PRIORITIES.HIGH,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_6,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.URI_INFERENCE)

    ngx.req.set_header(load_shedder.SORTING_HAT_POD_ID_HEADER, "42")
    assert_get_matches(request.PRIORITIES.HIGH,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_6,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.URI_INFERENCE)
  end)

  it("sheddable_checkouts", function()
    ngx.ctx.shop_id = '33'
    ngx.var.uri = '/checkouts'
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_UNSHEDDABLE,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.CHECKOUT_URI_INFERENCE)

    set_tenant_override("shops", "33", "sheddable_checkouts", ngx.now() + 1, "true")
    assert_get_matches(request.PRIORITIES.HIGH,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_6,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.OVERRIDDEN)

    advance_time(1001)
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_UNSHEDDABLE,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.CHECKOUT_URI_INFERENCE)
  end)

  it("anon_sheddable_checkouts_always", function()
    ngx.ctx.shop_id = '33'
    ngx.var.uri = '/checkouts'
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_UNSHEDDABLE,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.geoip2_is_anonymous = "1"
    assert_get_matches(request.PRIORITIES.HIGH,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_6,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.OVERRIDDEN)
  end)

  it("anon_sheddable_checkouts_can_be_disabled_by_shop", function()
    ngx.ctx.shop_id = '33'
    ngx.var.uri = '/checkouts'
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_UNSHEDDABLE,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.CHECKOUT_URI_INFERENCE)

    set_tenant_override("shops", "33", "prevent_shops_sheddable_checkouts", ngx.now() + 1, "true")

    ngx.var.geoip2_is_anonymous = "1"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_UNSHEDDABLE,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.CHECKOUT_URI_INFERENCE)

    set_tenant_override("shops", "33", "sheddable_checkouts", ngx.now() + 1, "true")
    ngx.var.geoip2_is_anonymous = "0"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_UNSHEDDABLE,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.CHECKOUT_URI_INFERENCE)
  end)

  it("anon_sheddable_checkouts_can_be_disabled_across_platform", function()
    ngx.ctx.shop_id = '33'
    ngx.var.uri = '/checkouts'
    ngx.var.geoip2_is_anonymous = "1"
    assert_get_matches(request.PRIORITIES.HIGH,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_6,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.OVERRIDDEN)

    set_tenant_override("global", "-1", "prevent_all_checkout_shedding_globally", ngx.now() + 1, "true")

    ngx.var.geoip2_is_anonymous = "1"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_UNSHEDDABLE,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.CHECKOUT_URI_INFERENCE)

    advance_time(1001)
    ngx.var.geoip2_is_anonymous = "1"
    assert_get_matches(request.PRIORITIES.HIGH,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_6,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.OVERRIDDEN)
  end)

  it("sheddable_checkouts_can_be_disabled_across_platform", function()
    ngx.ctx.shop_id = '33'
    ngx.var.uri = '/checkouts'
    ngx.var.geoip2_is_anonymous = "0"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_UNSHEDDABLE,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.CHECKOUT_URI_INFERENCE)

    set_tenant_override("shops", "33", "sheddable_checkouts", ngx.now() + 1, "true")

    assert_get_matches(request.PRIORITIES.HIGH,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_6,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.OVERRIDDEN)

    set_tenant_override("global", "-1", "prevent_all_checkout_shedding_globally", ngx.now() + 1, "true")

    assert_get_matches(request.PRIORITIES.UNSHEDDABLE,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_UNSHEDDABLE,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.CHECKOUT_URI_INFERENCE)

    advance_time(1001)

    assert_get_matches(request.PRIORITIES.UNSHEDDABLE,
                      tenant.GROUPS.STANDARD,
                      access_level.LEVELS.LEVEL_UNSHEDDABLE,
                      tenant.RULES.DEFAULT .. "+" .. request.RULES.CHECKOUT_URI_INFERENCE)
  end)

  it("sheddable_checkouts_doesnt_apply_to_other_requests", function()
    set_tenant_override("shops", "33", "sheddable_checkouts", ngx.now() + 1, "true")

    ngx.ctx.shop_id = '33'
    ngx.var.uri = '/admin'

    set_tenant_override("shops", "33", "sheddable_checkouts", ngx.now() + 1, "true")
    assert_get_matches(request.PRIORITIES.MEDIUM,
                       tenant.GROUPS.STANDARD,
                       access_level.LEVELS.LEVEL_5,
                       tenant.RULES.DEFAULT .. "+" .. request.RULES.URI_INFERENCE)
  end)

end)
