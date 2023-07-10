local busted = require('busted')
local assert = require('luassert')
local mock = require('luassert.mock')
local spy = require('luassert.spy')

describe("Utils module", function()

  -- Mock ngx object
  local ngx_mock = mock({
    log = function() end,
    WARN = "warn"
  })

  -- Create a spy for ngx.log
  local log_spy

  before_each(function()
    -- Replace ngx with the mock
    _G.ngx = ngx_mock

    -- Set up the spy
    log_spy = spy.on(ngx, 'log')

    utils = require('plugins.magellan.utils')
  end)

  after_each(function()
    -- Reset the mock
    mock.revert(ngx_mock)

    -- Reset the spy
    log_spy:revert()
  end)

  describe("is_blank", function()
    it("should return true for nil", function()
      assert.is_true(utils.is_blank(nil))
    end)

    it("should return true for empty string", function()
      assert.is_true(utils.is_blank(""))
    end)

    it("should return false for non-empty string", function()
      assert.is_false(utils.is_blank("non-empty"))
    end)
  end)

  describe("optimistic_json_decode", function()
    it("should return the same value for non-string input", function()
      assert.are.same(123, utils.optimistic_json_decode(123))
      assert.are.same({1, 2, 3}, utils.optimistic_json_decode({1, 2, 3}))
    end)

    it("should decode a JSON string", function()
      assert.are.same({key = "value"}, utils.optimistic_json_decode('{"key":"value"}'))
    end)

    it("should log a warning for invalid JSON", function()
      utils.optimistic_json_decode('{invalid json}')
      assert.spy(log_spy).was.called_with(ngx.WARN, "Optimistic JSON decode failed on value: {invalid json}")
    end)

    it("should replace cjson.null with nil", function()
      local cjson = require("cjson")
      local input = {key = cjson.null}
      assert.are.same({key = nil}, utils.optimistic_json_decode(input))
    end)
  end)
end)
