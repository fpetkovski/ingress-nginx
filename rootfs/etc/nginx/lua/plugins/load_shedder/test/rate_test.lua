package.path = "./rootfs/etc/nginx/lua/plugins/load_shedder/test/?.lua;./rootfs/etc/nginx/lua/plugins/load_shedder/test/helpers/?.lua;" .. package.path
require("helpers.init")

local busted = require('busted')
local assert = require('luassert')
local rate = require("plugins.load_shedder.rate")

local function new_rate()
  local r, err = rate.new('dicts_test', 'bar', 10)
  assert.is_nil(err)

  local now = 0 -- ms
  register_stub(ngx, 'now', function()
    return now / 1000
  end)

  return r, function(delta)
    now = now + delta
  end
end

describe("plugins.load_shedder.rate", function()

  before_each(function()
    reset_stubs()
    ngx.reset()
  end)

  it("rate_tracking", function()
    local r, advance = new_rate()

    for i = 0, 1 do
      assert.are.equal(r:count(), 0)

      for j = 0, 29 do
        local count, updated = r:incoming()
        assert.are.equal(count, j % 10 + 1)
        assert.are.equal(updated, count == 1 and j > 0)
        advance(1)
      end

      assert.are.equal(r:last_count(), 10)
      assert.are.equal(r:count(), 0)

      for j = 0, 29 do
        local count, updated = r:incoming()
        assert.are.equal(count, j % 5 + 1)
        assert.are.equal(updated, count == 1 and j > 0)
        advance(2)
      end

      assert.are.equal(r:last_count(), 5)
      assert.are.equal(r:count(), 0)

      for j = 0, 5 do
        advance(10)
        local count = r:incoming()
        assert.are.equal(count, 1)
        advance(10)
      end

      assert.are.equal(r:last_count(), 1)
      assert.are.equal(r:count(), 0)

      for j = 1, 5 do
        advance(10)
        local count = r:incoming(j)
        assert.are.equal(count, j)
        assert.are.equal(r:count(), j)
        assert.are.equal(r:last_count(), j-1)
      end

      advance(10)
    end
  end)

  it("dict_name_is_accessible", function()
    local r, err = rate.new('dicts_test', 'bar', 10)
    assert.are.equal(r.dict_name, 'dicts_test')
  end)

end)
