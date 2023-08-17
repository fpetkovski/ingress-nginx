package.path = "./rootfs/etc/nginx/lua/plugins/load_shedder/test/?.lua;./rootfs/etc/nginx/lua/plugins/load_shedder/test/helpers/?.lua;" .. package.path
require("helpers.init")
require("helpers.load_shedder")

local busted = require('busted')
local assert = require('luassert')
local quota_tracker = require("plugins.load_shedder.quota_tracker")

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

local function setup()
  ngx.reset()
  reset_stubs()
  stub_time()
end

describe("plugins.load_shedder.quota_tracker", function()

  before_each(function()
    setup()
  end)

  it("err_non_existent_dict", function()
    local tracker, err = quota_tracker.new("dont_exist", "test_metric")
    assert.is_nil(tracker)
    assert.are.equal(err, "shared dict: dont_exist was not found")
  end)

  it("uninitialized", function()
    local tracker = quota_tracker.new("load_shedder_quota_tracker", "test_metric")
    assert.are.equal(tracker:share("foo"), 0)
  end)

  it("negative_weight", function()
    local tracker = quota_tracker.new("load_shedder_quota_tracker", "test_metric")
    tracker:add("foo", -1)
    assert.are.equal(tracker:share("foo"), 0)
  end)

  it("tracks_quota", function()
    local test_with_window = function(window_size)
      local tracker = quota_tracker.new("load_shedder_quota_tracker", "test_metric", window_size)
      window_size = window_size or 15000

      tracker:add("42", 100)
      tracker:add("42", 100)
      tracker:add("42", 100)
      tracker:add("24", 100)

      advance_time(window_size)

      assert.are.equal(tracker:share("42"), 0.75)
      assert.are.equal(tracker:share("24"), 0.25)

      tracker:add("24", 50)
      tracker:add("24", 50)
      tracker:add("24", 50)
      tracker:add("24", 50)

      assert.are.equal(tracker:share("42"), 0.5)
      assert.are.equal(tracker:share("24"), 0.5)

      advance_time(window_size * 2)

      assert.are.equal(tracker:share("42"), 0)
      assert.are.equal(tracker:share("24"), 0)

      -- setup()
    end

    test_with_window(300000)
    test_with_window(100)
    test_with_window(nil)
  end)

  it("getting_usage", function()
    local window_size = 15000

    local tracker = quota_tracker.new("load_shedder_quota_tracker", "test_metric", window_size)
    tracker:add("42", 100)
    tracker:add("42", 100)
    tracker:add("42", 100)
    tracker:add("24", 100)

    advance_time(window_size)
    assert.are.equal(tracker:usage("42"), 300)
    assert.are.equal(tracker:usage("24"), 100)

    tracker:add("24", 50)
    tracker:add("24", 50)
    tracker:add("24", 50)
    tracker:add("24", 50)

    assert.are.equal(tracker:usage("42"), 300)
    assert.are.equal(tracker:usage("24"), 300)
  end)

  it("behaviour_with_nil_key", function()
    local tracker = quota_tracker.new("load_shedder_quota_tracker", "test_metric")

    tracker:add("42", 100)
    tracker:add("42", 100)
    tracker:add("42", 100)
    tracker:add(nil, 100)

    advance_time(15000)

    assert.are.equal(tracker:share("42"), 0.75)
    assert.are.equal(tracker:share(nil), 0.25)

    tracker:add(nil, 50)
    tracker:add(nil, 50)
    tracker:add(nil, 50)
    tracker:add(nil, 50)

    assert.are.equal(tracker:share("42"), 0.5)
    assert.are.equal(tracker:share(nil), 0.5)

    advance_time(30000)

    assert.are.equal(tracker:share("42"), 0)
    assert.are.equal(tracker:share(nil), 0)
  end)
end)
