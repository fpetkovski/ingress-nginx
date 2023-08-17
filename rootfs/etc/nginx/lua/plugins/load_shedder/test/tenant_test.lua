package.path = "./rootfs/etc/nginx/lua/plugins/load_shedder/test/?.lua;./rootfs/etc/nginx/lua/plugins/load_shedder/test/helpers/?.lua;" .. package.path
require("helpers.init")
require("helpers.load_shedder")

local busted = require('busted')
local assert = require('luassert')
local configuration = require("plugins.load_shedder.configuration")
local tenant = require("plugins.load_shedder.tenant")

local WINDOW_SIZE = 15000

local now
function stub_time(init_time)
  now = init_time or 2000
  register_stub(ngx, 'now', function()
    return now / 1000
  end)
end

function advance_time(delta_ms)
  now = now + delta_ms
end

local function assert_get_matches(shop_id, pod_id, pod_type, correct_group, correct_rule, pod_share, shop_share)
  local group, rule = tenant.get_tenancy_and_rule(shop_id, pod_id, pod_type, pod_share, shop_share)
  assert.are.equal(group, correct_group)
  assert.are.equal(rule, correct_rule)
end

describe("plugins.load_shedder.tenant", function()

  before_each(function()
    ngx.reset()
    reset_stubs()
    reset_statsd_trackers()
    stub_time()
    configuration.clear_cache()
  end)

  it("canary_pods", function()
    assert_get_matches(nil, "21", "", tenant.GROUPS.STANDARD, tenant.RULES.DEFAULT, nil)
    assert_get_matches(nil, "42", "canary", tenant.GROUPS.ABUSING, tenant.RULES.CANARY_POD, nil)
  end)

  it("shop_tenancy_overrides_correct_and_respects_expire_at", function()
    set_tenancy_override("shops", "42", ngx.now() + 1, "abusing")

    assert_get_matches('24', -1, "", tenant.GROUPS.STANDARD, tenant.RULES.DEFAULT, nil)
    assert_get_matches('42', -1, "", tenant.GROUPS.ABUSING, tenant.RULES.SHOP_OVERRIDE, nil)

    advance_time(1001)

    assert_get_matches('24', -1, "", tenant.GROUPS.STANDARD, tenant.RULES.DEFAULT, nil)
    assert_get_matches('42', -1, "", tenant.GROUPS.STANDARD, tenant.RULES.DEFAULT, nil)
  end)

  it("pod_tenancy_overrides_correct_and_respects_expire_at", function()
    set_tenancy_override("pods", "42", ngx.now() + 1, "exceeding")

    assert_get_matches('123', '24', "", tenant.GROUPS.STANDARD, tenant.RULES.DEFAULT, nil)
    assert_get_matches('123', '42', "", tenant.GROUPS.EXCEEDING, tenant.RULES.POD_OVERRIDE, nil)

    advance_time(1001)

    assert_get_matches('123', '24', "", tenant.GROUPS.STANDARD, tenant.RULES.DEFAULT, nil)
    assert_get_matches('123', '42', "", tenant.GROUPS.STANDARD, tenant.RULES.DEFAULT, nil)
  end)

  it("tenant_share_overrides_correct_and_respects_expire_at", function()
    -- shop_limit > pod_limit ==> invalid config ==> shop_limit = pod_limit
    local shop_limit = 0.1
    local pod_limit = 0.05
    set_tenant_share_override("shops", "99", ngx.now() + 1, shop_limit)
    set_tenant_share_override("pods", "42", ngx.now() + 1, pod_limit)

    -- shop_exceeding, pod_exceeding
    assert_get_matches('99' , '42' , "", tenant.GROUPS.ABUSING   , tenant.RULES.SHOP_AND_POD_EXCEEDING , pod_limit + 0.1 , shop_limit + 0.1)
    -- shop_standard, pod_exceeding
    assert_get_matches('99' , '42' , "", tenant.GROUPS.EXCEEDING , tenant.RULES.POD_EXCEEDING          , pod_limit + 0.1 , shop_limit - 0.1)
    -- shop_exceeding, pod_standard
    assert_get_matches('99' , '42' , "", tenant.GROUPS.EXCEEDING , tenant.RULES.SHOP_EXCEEDING         , pod_limit - 0.1 , shop_limit + 0.1)
    -- shop_standard, pod_standard
    assert_get_matches('99' , '42' , "", tenant.GROUPS.STANDARD , tenant.RULES.DEFAULT                 , pod_limit - 0.1 , shop_limit - 0.1)

    -- shop_limit < pod_limit
    local shop_limit = 0.05
    local pod_limit = 0.1
    set_tenant_share_override("shops", "99", ngx.now() + 1, shop_limit)
    set_tenant_share_override("pods", "42", ngx.now() + 1, pod_limit)

    -- shop_exceeding, pod_exceeding
    assert_get_matches('99' , '42' , "", tenant.GROUPS.ABUSING   , tenant.RULES.SHOP_AND_POD_EXCEEDING , pod_limit + 0.1 , shop_limit + 0.1)
    -- shop_standard, pod_exceeding
    assert_get_matches('99' , '42' , "", tenant.GROUPS.EXCEEDING , tenant.RULES.POD_EXCEEDING          , pod_limit + 0.1 , shop_limit - 0.1)
    -- shop_exceeding, pod_standard
    assert_get_matches('99' , '42' , "", tenant.GROUPS.EXCEEDING , tenant.RULES.SHOP_EXCEEDING         , pod_limit - 0.1 , shop_limit + 0.1)
    -- shop_standard, pod_standard
    assert_get_matches('99' , '42' , "", tenant.GROUPS.STANDARD , tenant.RULES.DEFAULT                 , pod_limit - 0.1 , shop_limit - 0.1)

    -- shop_limit == pod_limit
    local shop_limit = 0.1
    local pod_limit = 0.1
    set_tenant_share_override("shops", "99", ngx.now() + 1, shop_limit)
    set_tenant_share_override("pods", "42", ngx.now() + 1, pod_limit)

    -- shop_exceeding, pod_exceeding
    assert_get_matches('99' , '42' , "", tenant.GROUPS.ABUSING   , tenant.RULES.SHOP_AND_POD_EXCEEDING , pod_limit + 0.1 , shop_limit + 0.1)
    -- shop_standard, pod_exceeding
    assert_get_matches('99' , '42' , "", tenant.GROUPS.EXCEEDING , tenant.RULES.POD_EXCEEDING          , pod_limit + 0.1 , shop_limit - 0.1)
    -- shop_exceeding, pod_standard
    assert_get_matches('99' , '42' , "", tenant.GROUPS.EXCEEDING , tenant.RULES.SHOP_EXCEEDING         , pod_limit - 0.1 , shop_limit + 0.1)
    -- shop_standard, pod_standard
    assert_get_matches('99' , '42' , "", tenant.GROUPS.STANDARD , tenant.RULES.DEFAULT                 , pod_limit - 0.1 , shop_limit - 0.1)

    set_tenant_share_override("pods", "42", ngx.now() + 1, 0.0)
    set_tenant_share_override("shops", "99", ngx.now() + 1, 0.0)

    -- valid config, most tenants in steady-state
    assert_get_matches('123' , '24' , "", tenant.GROUPS.STANDARD , tenant.RULES.DEFAULT                , 0.1 , 0.1)
    -- invalid config => shop_limit set to pod_limit (default of 10%)
    assert_get_matches('99'  , '24' , "", tenant.GROUPS.STANDARD , tenant.RULES.DEFAULT                , 0.1 , 0.1)
    -- invalid config => shop_limit set to pod_limit (default of 10%)
    assert_get_matches('123' , '42' , "", tenant.GROUPS.ABUSING  , tenant.RULES.SHOP_AND_POD_EXCEEDING , 0.1 , 0.1)
    -- valid config
    assert_get_matches('99'  , '42' , "", tenant.GROUPS.ABUSING  , tenant.RULES.SHOP_AND_POD_EXCEEDING , 0.1 , 0.1)

    advance_time(1001)

    assert_get_matches('123' , '24' , "", tenant.GROUPS.STANDARD , tenant.RULES.DEFAULT , 0.1, 0.1)
    assert_get_matches('123' , '42' , "", tenant.GROUPS.STANDARD , tenant.RULES.DEFAULT , 0.1, 0.1)
    assert_get_matches('99'  , '24' , "", tenant.GROUPS.STANDARD , tenant.RULES.DEFAULT , 0.1, 0.1)
    assert_get_matches('99'  , '42' , "", tenant.GROUPS.STANDARD , tenant.RULES.DEFAULT , 0.1, 0.1)
  end)

  it("high_utilization_shops_and_pods", function()
    non_canary_pod_id = "21"
    canary_pod_id = "42"

    shop_id = "123456"

    -- shop=non-exceeding, pod=non-exceeding, canary_pod=false
    assert_get_matches(shop_id, non_canary_pod_id, "", tenant.GROUPS.STANDARD, tenant.RULES.DEFAULT, 0.08, 0.08)
    -- shop=non-exceeding, pod=exceeding, canary_pod=false
    assert_get_matches(shop_id, non_canary_pod_id, "", tenant.GROUPS.EXCEEDING, tenant.RULES.POD_EXCEEDING, 0.12, 0.08)
    -- shop=non-exceeding, pod=non-exceeding, canary_pod=true
    assert_get_matches(shop_id, canary_pod_id, "canary", tenant.GROUPS.ABUSING, tenant.RULES.CANARY_POD, 0.05, 0.08)
    -- shop=non-exceeding, pod=exceeding, canary_pod=true
    assert_get_matches(shop_id, canary_pod_id, "canary", tenant.GROUPS.ABUSING, tenant.RULES.CANARY_POD, 0.14, 0.08)
    -- shop=exceeding, pod=non-exceeding, canary_pod=false
    assert_get_matches(shop_id, non_canary_pod_id, "", tenant.GROUPS.EXCEEDING, tenant.RULES.SHOP_EXCEEDING, 0.08, 0.12)
    -- shop=exceeding, pod=exceeding, canary_pod=false
    assert_get_matches(shop_id, non_canary_pod_id, "", tenant.GROUPS.ABUSING, tenant.RULES.SHOP_AND_POD_EXCEEDING, 0.12, 0.12)
    -- shop=exceeding, pod=non-exceeding, canary_pod=true
    assert_get_matches(shop_id, canary_pod_id, "canary", tenant.GROUPS.ABUSING, tenant.RULES.CANARY_POD, 0.05, 0.12)
    -- shop=exceeding, pod=exceeding, canary_pod=true
    assert_get_matches(shop_id, canary_pod_id, "canary", tenant.GROUPS.ABUSING, tenant.RULES.CANARY_POD, 0.14, 0.12)
  end)

  it("pod_tenancy_overrides_have_precedence_over_pod_tenant_share_overrides", function()
    set_tenancy_override("pods", "42", ngx.now() + 1, "abusing")
    set_tenant_share_override("pods", "42", ngx.now() + 1, 0.0)

    assert_get_matches('123', '42', "", tenant.GROUPS.ABUSING, tenant.RULES.POD_OVERRIDE, 0.1)
  end)

  it("shop_tenancy_overrides_have_precedence_over_pod_tenant_share_overrides", function()
    set_tenancy_override("shops", "123", ngx.now() + 1, "abusing")
    set_tenant_share_override("pods", "42", ngx.now() + 1, 0.0)

    assert_get_matches('123', '42', "", tenant.GROUPS.ABUSING, tenant.RULES.SHOP_OVERRIDE, 0.1)
  end)

  it("standard_tenancy_override_is_noop", function()
    set_tenancy_override("shops", "123", ngx.now() + 1, "standard")
    set_tenancy_override("pods", "24", ngx.now() + 1, "standard")

    assert_get_matches('123', '42', "", tenant.GROUPS.STANDARD, tenant.RULES.DEFAULT, nil)
    assert_get_matches('456', '24', "", tenant.GROUPS.STANDARD, tenant.RULES.DEFAULT, nil)
  end)

  it("pod_requests_tracking", function()
    stub_time(0)

    tenant.pod_requests_add("42", 100)
    tenant.pod_requests_add("42", 100)
    tenant.pod_requests_add("42", 100)
    tenant.pod_requests_add("24", 100)

    advance_time(WINDOW_SIZE)

    assert.are.equal(tenant.pod_requests_share("42"), 0.75)
    assert.are.equal(tenant.pod_requests_share("24"), 0.25)

    advance_time(WINDOW_SIZE - 1)

    tenant.pod_requests_add("24", 100)
    tenant.pod_requests_add("24", 100)

    assert.are.equal(tenant.pod_requests_share("42"), 0.5)
    assert.are.equal(tenant.pod_requests_share("24"), 0.5)

    advance_time(WINDOW_SIZE + 1)

    assert.are.equal(tenant.pod_requests_share("42"), 0)
    assert.are.equal(tenant.pod_requests_share("24"), 0)
  end)

  it("tracker_for_returns_correct_tracker_for_params", function()
    local tracker = tenant.tracker_for("unicorn_shopify_pool", "processing_by_pod")
    assert.are.equal(tracker.dict_name, "load_shedder_quota_tracker")
    assert.are.equal(tracker.metric_name, "unicorn_shopify_pool.processing_by_pod")

    tracker = tenant.tracker_for("unicorn_shopify_pool", "processing_by_shop")
    assert.are.equal(tracker.dict_name, "load_shedder_quota_tracker")
    assert.are.equal(tracker.metric_name, "unicorn_shopify_pool.processing_by_shop")
  end)

  it("tracker_for_only_constructs_once", function()
    local tracker1 = tenant.tracker_for("unicorn_shopify_pool", "processing_by_pod")
    local tracker2 = tenant.tracker_for("unicorn_shopify_pool", "processing_by_pod")
    assert.is_not_nil(tracker1)
    assert.are.equal(tracker1, tracker2)
  end)

  it("tracker_for_nil_metric_raises_error", function()
    stub_statsd_increment()
    assert.has_error(function() tenant.tracker_for("unicorn_shopify_pool", nil) end)
    assertStatsdIncrement("load_shedder.tenant.nil_usage_metric", 1, { resource="unicorn_shopify_pool" })
  end)
end)
