package.path = "./rootfs/etc/nginx/lua/plugins/load_shedder/test/?.lua;./rootfs/etc/nginx/lua/plugins/load_shedder/test/helpers/?.lua;" .. package.path
require("helpers.init")

local busted = require('busted')
local assert = require('luassert')
local json = require("cjson")
local util = require("plugins.load_shedder.shopify_utils")
local request = require("plugins.load_shedder.request_priority")
local tenant = require("plugins.load_shedder.tenant")
local access_level = require("plugins.load_shedder.access_level")


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

local function assert_get_matches(correct_level, priority, tenancy, controller_class)
  ngx.ctx.access_level = nil

  local level = access_level.get(controller_class, priority, tenancy)
  assert.are.equal(level, correct_level)
end


describe("plugins.load_shedder.access_level", function()

  before_each(function()
    ngx.reset()
    reset_stubs()
    stub_time()
  end)

  it("correct_number_of_levels", function()
    local count = 0
    for k,v in pairs(access_level.LEVELS) do
      count = count + 1
    end
    assert.are.equal(count, access_level.MAX_SHEDDABLE + 1)
  end)

  it("abusing_unicorn", function()
    assert_get_matches(access_level.LEVELS.LEVEL_1, request.PRIORITIES.LOW, tenant.GROUPS.ABUSING, "unicorn")
    assert_get_matches(access_level.LEVELS.LEVEL_2, request.PRIORITIES.MEDIUM, tenant.GROUPS.ABUSING, "unicorn")
    assert_get_matches(access_level.LEVELS.LEVEL_1, request.PRIORITIES.HIGH, tenant.GROUPS.ABUSING, "unicorn")
    assert_get_matches(access_level.LEVELS.LEVEL_UNSHEDDABLE, request.PRIORITIES.UNSHEDDABLE, tenant.GROUPS.ABUSING, "unicorn")
    assert_get_matches(access_level.LEVELS.LEVEL_2, request.PRIORITIES.UNKNOWN, tenant.GROUPS.ABUSING, "unicorn")
  end)

  it("exceeding_unicorn", function()
    assert_get_matches(access_level.LEVELS.LEVEL_2, request.PRIORITIES.LOW, tenant.GROUPS.EXCEEDING, "unicorn")
    assert_get_matches(access_level.LEVELS.LEVEL_3, request.PRIORITIES.MEDIUM, tenant.GROUPS.EXCEEDING, "unicorn")
    assert_get_matches(access_level.LEVELS.LEVEL_4, request.PRIORITIES.HIGH, tenant.GROUPS.EXCEEDING, "unicorn")
    assert_get_matches(access_level.LEVELS.LEVEL_UNSHEDDABLE, request.PRIORITIES.UNSHEDDABLE, tenant.GROUPS.EXCEEDING, "unicorn")
    assert_get_matches(access_level.LEVELS.LEVEL_4, request.PRIORITIES.UNKNOWN, tenant.GROUPS.EXCEEDING, "unicorn")
  end)

  it("standard_unicorn", function()
    assert_get_matches(access_level.LEVELS.LEVEL_4, request.PRIORITIES.LOW, tenant.GROUPS.STANDARD, "unicorn")
    assert_get_matches(access_level.LEVELS.LEVEL_5, request.PRIORITIES.MEDIUM, tenant.GROUPS.STANDARD, "unicorn")
    assert_get_matches(access_level.LEVELS.LEVEL_6, request.PRIORITIES.HIGH, tenant.GROUPS.STANDARD, "unicorn")
    assert_get_matches(access_level.LEVELS.LEVEL_UNSHEDDABLE, request.PRIORITIES.UNSHEDDABLE, tenant.GROUPS.STANDARD, "unicorn")
    assert_get_matches(access_level.LEVELS.LEVEL_UNSHEDDABLE, request.PRIORITIES.UNKNOWN, tenant.GROUPS.STANDARD, "unicorn")
  end)

end)
