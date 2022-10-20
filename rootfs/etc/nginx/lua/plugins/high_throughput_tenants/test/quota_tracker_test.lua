local original_ngx = ngx
local function reset_ngx()
  _G.ngx = original_ngx
end

local function mock_ngx(mock)
  local _ngx = mock
  setmetatable(_ngx, { __index = ngx })
  _G.ngx = _ngx
end

local function advance_time(delta_ms)
  now = now + delta_ms
end

describe('quota tracker', function()
  local quota_tracker

  before_each(function()
    ngx.shared.quota_tracker:flush_all()

    now = 0
    mock_ngx({
      now = function()
        return now / 1000
      end
    })

    quota_tracker = require_without_cache("plugins.high_throughput_tenants.quota_tracker")
  end)

  after_each(function()
    reset_ngx()
  end)

  it("err_non_existent_dict", function()
    local tracker, err = quota_tracker.new("dont_exist", "foo")
    assert.are.equal(nil, tracker)
    assert.are.equal(err, "shared dict: dont_exist was not found")
  end)

  it("uninitialized", function()
    local tracker = quota_tracker.new("quota_tracker", "foo")
    assert.are.equal(tracker:share("foo"), 0)
  end)

  it("negative_weight", function()
    local tracker = quota_tracker.new("quota_tracker", "foo")
    tracker:add("foo", -1)
    assert.are.equal(tracker:share("foo"), 0)
  end)

  local test_with_window = function(window_size)
    local tracker = quota_tracker.new("quota_tracker", "foo", window_size)
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
  end

  it("tracks_quota with window=300000", function()
    test_with_window(300000)
  end)

  it("tracks_quota with window=100", function()
    test_with_window(100)
  end)

  it("tracks_quota with window=nil", function()
    test_with_window(nil)
  end)

  it("getting_usage", function()
    local window_size = 15000

    local tracker = quota_tracker.new("quota_tracker", "foo", window_size)
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
    local tracker = quota_tracker.new("quota_tracker", "foo")

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
