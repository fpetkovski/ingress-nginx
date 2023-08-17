package.path = "./rootfs/etc/nginx/lua/plugins/load_shedder/test/?.lua;./rootfs/etc/nginx/lua/plugins/load_shedder/test/helpers/?.lua;" .. package.path
require("helpers.init")

local busted = require('busted')
local assert = require('luassert')

local access_controller = require("plugins.load_shedder.access_controller")
local dummy_configuration = {
  limits = function()
    return 0, 1.0, 1
  end,
  enabled = function ()
    return true
  end
}
local now
function stub_time()
  now = 0
  register_stub(ngx, 'now', function()
    return now / 1000
  end)
end

function advance_time(delta_ms)
  now = now + delta_ms
end

local function set_shedder_config(soft, hard, max_drop)
  dummy_configuration['limits'] = function ()
    return soft, hard, max_drop
  end
end

local function access_controller_new(soft, hard, max_drop, num_levels)
  set_shedder_config(soft, hard, max_drop)
  return access_controller.new(num_levels, 'unicorn', 'controller_name', 'prefix', dummy_configuration)
end

describe("plugins.load_shedder.access_controller", function()
  before_each(function()
    ngx.reset()
    reset_stubs()
    stub_statsd_gauge()
    stub_time()
  end)

  it("never_drops_levels_higher_than_num_levels", function()
    local controller = access_controller_new(0, 0, 1.0, 1)

    assert.are.equal(controller.util_avg, 0)
    assert.are.equal(controller.drop_rates[1], 1.0)
    assert.are.equal(controller.drop_rates[2], nil)

    assert.are.equal(controller:allow(1), false)
    assert.are.equal(controller:allow(2), true)
  end)

  it("function updates_utilization_average_and_drop_rate_on_update", function()
    local soft = 0.5
    local hard = 1
    local max_drop = 0.8
    local controller = access_controller_new(soft, hard, max_drop, 1)

    assert.are.equal(controller.util_avg, 0)
    assert.are.equal(controller.drop_rates[1], 0)

    local update_to = soft + 0.2 * (hard - soft)
    controller:update(update_to)

    assert.are.equal(controller.util_avg, update_to)

    expected_drop_rate = max_drop * (controller.util_avg - soft) / (hard - soft)
    assert.is.near(controller.drop_rates[1], expected_drop_rate, 0.001)

    controller:update(0.4)
    assert.are.equal(controller.util_avg, 0.4)
    assert.are.equal(controller.drop_rates[1], 0)
  end)

  it("respects_statsd_prefix", function()
    controller = access_controller.new(1, 'unicorn', 'ignore', 'skywalker', dummy_configuration)
    controller:update(1)

    assertStatsdGauge('skywalker.util_avg')
  end)

  it("uses_max_drop_rate_from_configuration", function()
    local expected_drop_rate = 0.685

    local adhoc_configuration = {
      limits = function ()
        return 0, 1, expected_drop_rate
      end
    }

    local controller = access_controller.new(1, 'ignore', 'ignore', 'ignore', adhoc_configuration)
    controller:update(1)

    assert.are.equal(controller.drop_rates[1], expected_drop_rate)
  end)

  it("enable_from_configuration", function()
    local adhoc_configuration = {
      limits = function ()
        return 0, 0, 0
      end
    }

    adhoc_configuration.enabled = function() return true end
    local controller = access_controller.new(1, 'ignore', 'ignore', 'ignore', adhoc_configuration)
    assert.are.equal(controller:enabled(), true)

    adhoc_configuration.enabled = function() return false end
    local controller = access_controller.new(1, 'ignore', 'ignore', 'ignore', adhoc_configuration)
    assert.are.equal(controller:enabled(), false)
  end)

  it("doesnt_go_above_max_drop_rate", function()
    local soft = 0.5
    local hard = 1
    local max_drop = 0.6
    local controller = access_controller_new(soft, hard, max_drop, 1)

    assert.are.equal(controller.util_avg, 0)
    assert.are.equal(controller.drop_rates[1], 0)

    controller:update(42)

    assert.are.equal(controller.util_avg, 42)
    assert.are.equal(controller.drop_rates[1], max_drop)
  end)

  it("allows_correct_number_of_requests_based_on_drop_rate", function()
    local soft = 1.0
    local hard = 3.0
    local max_drop = 0.7
    local controller = access_controller_new(soft, hard, max_drop, 1)

    assert.are.equal(controller.util_avg, 0)
    assert.are.equal(controller.drop_rates[1], 0)

    local update_to = soft + 0.3 * (hard - soft)
    controller:update(update_to)
    assert.are.equal(controller.util_avg, update_to)

    expected_drop_rate = max_drop * (controller.util_avg - soft) / (hard - soft)
    assert.is.near(controller.drop_rates[1], expected_drop_rate, 0.001)

    local allowed = 0

    for i=1,100 do
      if controller:allow(1) then
        allowed = allowed + 1
      end
    end
    assert.is_true(allowed < 100)

    -- if the level is too high, we let it through
    allowed = 0
    for i=1,100 do
      if controller:allow(75) then
        allowed = allowed + 1
      end
    end
    assert.are.equal(allowed, 100)
  end)

  it("updates_utilization_average_and_drop_rate_on_update_multi_level", function()
    local soft = 0.5
    local hard = 2.0
    local max_drop = 0.8
    local controller = access_controller_new(soft, hard, max_drop, 3)

    assert.are.equal(controller.util_avg, 0)
    assert.are.same(controller.drop_rates, { [1] = 0, [2] = 0, [3] = 0 })

    controller:update(0.6)
    assert.are.equal(controller.util_avg, 0.6)

    assert.is.near(controller.drop_rates[1], 0.16, 0.001)
    assert.are.equal(controller.drop_rates[2], 0.0)
    assert.are.equal(controller.drop_rates[3], 0.0)

    controller:update(0.4)
    assert.are.equal(controller.util_avg, 0.4)

    assert.are.same(controller.drop_rates, { [1] = 0, [2] = 0, [3] = 0 })
  end)

  it("doesnt_go_above_max_drop_rate_multi", function()
    local controller = access_controller_new(0.6, 1.1, 0.6, 5)

    assert.are.equal(controller.util_avg, 0)
    assert.are.same(controller.drop_rates, { [1] = 0.0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 })

    controller:update(42)

    assert.are.equal(controller.util_avg, 42)
    assert.are.same(controller.drop_rates, { [1] = 0.6, [2] = 0.6, [3] = 0.6, [4] = 0.6, [5] = 0.6 })
  end)

  it("allows_correct_number_of_requests_based_on_drop_rate_multi", function()
    local controller = access_controller_new(0.5, 1.0, 0.6, 1)

    assert.are.equal(controller.util_avg, 0)
    assert.are.same(controller.drop_rates, { [1] = 0.0 })

    controller:update(0.6)

    assert.are.equal(controller.util_avg, 0.6)
    assert.is.near(controller.drop_rates[1], 0.12, 0.001)

    local allowed = 0

    for i=1,100 do
      if controller:allow(1) then
        allowed = allowed + 1
      end
    end
    assert.is_true(allowed < 100)

    allowed = 0
    for i=1,100 do
      if controller:allow(5) then
        allowed = allowed + 1
      end
    end
    assert.are.equal(allowed, 100)
  end)

  it("block_all_lower_requests_multi", function()
    local controller = access_controller_new(0.5, 1, 0.6, 5)

    assert.are.equal(controller.util_avg, 0)
    assert.are.same(controller.drop_rates, { [1] = 0.0, [2] = 0.0, [3] = 0.0, [4] = 0.0, [5] = 0.0 })

    controller:update(0.7)

    assert.are.equal(controller.util_avg, 0.7)
    assert.are.same(controller.drop_rates, { [1] = 0.6, [2] = 0.6, [3] = 0.0, [4] = 0.0, [5] = 0.0 })

    -- test on levels higher than setup
    local allowed = { [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 0, [7] = 0 }
    for i = 1, 100 do
      for cat = 1, 7 do
        if controller:allow(cat) then
          allowed[cat] = allowed[cat] + 1
        end
      end
    end

    assert.is_true(allowed[1] < 100)
    assert.is_true(allowed[2] < 100)
    assert.is.equal(allowed[3], 100)
    assert.is.equal(allowed[4], 100)
    assert.is.equal(allowed[5], 100)
    assert.is.equal(allowed[6], 100)
    assert.is.equal(allowed[7], 100)
    -- assert.are.same(allowed, { [1] = 45, [2] = 42, [3] = 100, [4] = 100, [5] = 100, [6] = 100, [7] = 100 })
  end)

  it("block_some_high_requests_multi", function()
    local controller = access_controller_new(0.5, 1.0, 0.6, 5)

    assert.are.equal(controller.util_avg, 0)
  --  assert.are.equal(controller:drop_rate(0), 0)

    controller:update(0.95)

    assert.are.equal(controller.util_avg, 0.95)
    assert.are.equal(controller.drop_rates[1], 0.6)
    assert.are.equal(controller.drop_rates[2], 0.6)
    assert.are.equal(controller.drop_rates[3], 0.6)
    assert.are.equal(controller.drop_rates[4], 0.6)
    assert.is.near(controller.drop_rates[5], 0.3, 0.001)

    local allowed = { [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 0 }
    for i = 1, 100 do
      for cat = 1, 6 do
        if controller:allow(cat) then
          allowed[cat] = allowed[cat] + 1
        end
      end
    end

    assert.is_true(allowed[1] < 100)
    assert.is_true(allowed[2] < 100)
    assert.is_true(allowed[3] < 100)
    assert.is_true(allowed[4] < 100)
    assert.is_true(allowed[5] < 100)
    assert.is.equal(allowed[6], 100)
    -- assert.are.same(allowed, { [1] = 40, [2] = 38, [3] = 36, [4] = 37, [5] = 80, [6] = 100 })
  end)

  it("computation_two_segments", function()
    local controller = access_controller_new(1.0, 5.0, 0.7, 2)

    assert.are.equal(controller.util_avg, 0)
    assert.are.same(controller.drop_rates, { [1] = 0, [2] = 0 })

    controller:update(2.0)
    assert.are.equal(controller.util_avg, 2.0)

    assert.are.same(controller.drop_rates, { [1] = 0.35, [2] = 0 })
  end)

  it("picks_up_new_config_changes", function()
    local controller = access_controller_new(1.0, 5.0, 0.7, 2)
    advance_time(5000)

    assert.are.equal(controller.util_avg, 0)
    assert.are.same(controller.drop_rates, { [1] = 0, [2] = 0 })

    controller:update(2.0)
    assert.are.equal(controller.util_avg, 2.0)

    assert.are.same(controller.drop_rates, { [1] = 0.35, [2] = 0 })

    set_shedder_config(1.0, 3.0, 0.7)
    advance_time(3000) -- assumes configuration.CACHE_TTL of 2s

    controller:update(2.0)
    assert.are.same(controller.drop_rates, { [1] = 0.7, [2] = 0 })

    advance_time(1001)

    controller:update(2.0)
    assert.are.same(controller.drop_rates, { [1] = 0.7, [2] = 0 })
  end)

  it("nil_utilization_treated_as_zero", function()
    local controller = access_controller_new(1.0, 2.0, 0.99, 2)
    controller:update(2.0)
    assert.are.same(controller.drop_rates, { [1] = 0.99, [2] = 0.99 })

    controller:update(nil)
    assert.are.same(controller.drop_rates, { [1] = 0, [2] = 0 })
  end)

end)


