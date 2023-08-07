local busted = require('busted')
local assert = require('luassert')
local mock = require('luassert.mock')

describe("Timer module", function()
  -- Mock ngx object
  local ngx_mock = mock({
    timer = {
      at = function(delay, func, ...)
        if delay == 0 then
            -- premature argument is false
            func(false, ...)
        else
            table.insert(_ngx._queued_timers, { delay = delay, func = func, args = {...} })
        end
        return true
      end,
      every = function() end
    },
    worker = {
      exiting = function() return false end,
      id = function() return 0 end
    },
    log = function() end,
    ERR = "error",
    shopify = {
      env = "test"
    }
  })

  before_each(function()
    -- Replace ngx with the mock
    _G.ngx = ngx_mock

    timer_module = require('plugins.magellan.timer')
  end)

  after_each(function()
    -- Reset the mock
    mock.revert(ngx_mock)
  end)

  it("should execute at interval", function()
    -- Mock function to be executed
    local func = function() end
    local func_mock = mock(func, true) -- the second parameter makes it a 'strict' mock

    -- Call the function
    timer_module.execute_at_interval(5, true, func_mock)

    -- Check that ngx.timer.at and ngx.timer.every were called
    assert.spy(ngx.timer.at).was.called()
    assert.spy(ngx.timer.every).was.called()

    -- Check that the function was called
    assert.spy(func_mock).was.called()
  end)
end)
