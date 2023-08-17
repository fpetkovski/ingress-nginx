package.path = "./rootfs/etc/nginx/lua/plugins/load_shedder/test/?.lua;./rootfs/etc/nginx/lua/plugins/load_shedder/test/helpers/?.lua;" .. package.path
require("helpers.init")

local busted = require('busted')
local assert = require('luassert')
local ewma_shared = require("plugins.load_shedder.ewma_shared")
local DECAY_WINDOW = ewma_shared.DECAY_TIME
local STARTING_TIME = 1000000 -- last_touched_at initializes to 0, so in practice our delta t is $LARGEVAL when adding first sample

local function assert_ewma_stats(upstream, ewma, touched_at)
  local actual_ewma, actual_last_touched_at = ewma_shared.get(upstream)
  assert.is.near(actual_ewma, ewma, 0.001)
  assert.are.equal(actual_last_touched_at, touched_at)
end

local now
function stub_time()
  now = STARTING_TIME
  register_stub(ngx, 'now', function()
    return now
  end)
end

function advance_time(delta_s)
  now = now + delta_s
end

describe("plugins.load_shedder.ewma_shared", function()

  before_each(function()
    stub_time()
    ngx.reset()
  end)

  -- deliberately verbose to help understanding
  it("correct_decay", function()
    local first_sample = 1
    local second_sample = 0

    -- set starting state
    local ewma = ewma_shared.update("upstream1", first_sample)
    assert.is.near(1, ewma, 0.001)

    local time_delta = 10 -- seconds
    local weight = math.exp(-time_delta / DECAY_WINDOW) -- weight = time since last update / decay time
    local expected_ewma = first_sample * weight + second_sample * (1.0 - weight)
    assert.is.near(0.6065, expected_ewma, 0.001)

    -- 10s passes - this is half of our decay window; by using 0 as the value, we get first_sample * weight,
    --  which is just 1 * weight, which is the weight at x=10 for y=1-e^-(x/20)
    advance_time(time_delta)
    ewma = ewma_shared.update("upstream1", second_sample)
    assert.is.near(expected_ewma, ewma, 0.001)
  end)

  it("update_sets_shared_dict_state", function()
    ewma_shared.update("upstream1", 0.5)
    assert_ewma_stats("upstream1", 0.5, STARTING_TIME)

    advance_time(13)
    ewma_shared.update("upstream1", 0.3)
    assert_ewma_stats("upstream1", 0.404, STARTING_TIME + 13)

    local serialized_value = ngx.shared.load_shedder_ewma:get("upstream1")
    assert.are.equal(tostring(0.4044091553522) .. ":" .. tostring(STARTING_TIME + 13), serialized_value)
  end)

  it("all_zeros", function()
    for _=1, DECAY_WINDOW do
      advance_time(1)
      ewma_shared.update("upstream1", 0)
    end

    assert.is.near(0, ewma_shared.get("upstream1"), 0.001)
  end)

  it("all_ones", function()
    for _=1, DECAY_WINDOW do
      advance_time(1)
      ewma_shared.update("upstream1", 1)
    end

    assert.is.near(1, ewma_shared.get("upstream1"), 0.001)
  end)

  it("multiple_upstreams", function()
    ewma_shared.update("upstream1", 0.5)
    advance_time(1)
    ewma_shared.update("upstream2", 0.8)

    assert_ewma_stats("upstream1", 0.5, STARTING_TIME)
    assert_ewma_stats("upstream2", 0.8, STARTING_TIME + 1)
  end)

  it("initialize_non_existent_upstream", function()
    assert.is_nil(ngx.shared.load_shedder_ewma:get("upstream1"))

    local ewma, last_touched_at = ewma_shared.update("upstream1", 0.5)
    assert.is.near(0.5, ewma, 0.001)
    assert.are.equal(last_touched_at, STARTING_TIME)
    assert_ewma_stats("upstream1", 0.5, STARTING_TIME)
  end)

  it("get_non_existent_upstream", function()
    assert.is_nil(ngx.shared.load_shedder_ewma:get("upstream1"))

    local ewma, last_touched_at = ewma_shared.get("upstream1")
    assert.are.equal(last_touched_at, 0)
    assert.are.equal(ewma, 0)
  end)


end)
