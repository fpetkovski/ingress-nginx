local busted = require('busted')
local assert = require('luassert')
local mock = require('luassert.mock')

local function split_pair(pair, seperator)
  local i = pair:find(seperator)
  if i == nil then
    return pair, nil
  else
    local name = pair:sub(1, i - 1)
    local value = pair:sub(i + 1, -1)
    return name, value
  end
end

describe("plugins.statsd.main", function()

  local old_ngx = _G.ngx
  local old_udp = _G.ngx.socket.udp
  local old_getenv = _G.os.getenv
  local packet

  local udp_mock = mock(
    function(...)
      local socket = old_udp(...)
      socket.send = function(self, p) packet = p end
      socket.setpeername = function(self, host, port) return 1 end
      return socket
    end
  )
  local ngx_mock = mock({
    ctx = {},
    WARN = 1,
    ERR = 2,
    socket = {
      udp = udp_mock,
    },
    log = spy.new(function() end),
  })
  local getenv_mock = mock(
    function(str)
      local hash = {
        STATSD_ADDR = "127.0.0.1:1234",
        STATSD_SAMPLING_RATE = "1",
      }
      return hash[str]
    end
  )
  _G.ngx = ngx_mock
  _G.os.getenv = getenv_mock

  before_each(function()
    package.loaded["plugins.statsd.main"] = nil

    -- Reset our ngx mock
    ngx.log:clear()
    ngx.ctx = {}
    ngx.socket.udp = udp_mock

    -- Reset our udp packet
    packet = ""

    -- Load the module under test
    statsd = require("plugins.statsd.main")
  end)

  teardown(function()
    -- Reset the globals
    _G.ngx = old_ngx
    _G.os.getenv = old_getenv
  end)

  it("increments a counter metric", function()
    statsd.increment("foo")
    statsd.defer_to_timer.flush_queue()

    assert.are.equal(packet, "foo:1|c")
  end)

  it("increment preserves decimals", function()
    statsd.increment("foo", 0.05)
    statsd.defer_to_timer.flush_queue()

    assert.are.equal(packet, "foo:0.05|c")
  end)

  it("gauge sends integers", function()
    statsd.gauge("foo", 1)
    statsd.defer_to_timer.flush_queue()

    assert.are.equal(packet, "foo:1|g")
  end)

  it("gauge preserves decimals", function()
    statsd.gauge("foo", 1.05)
    statsd.defer_to_timer.flush_queue()

    assert.are.equal(packet, "foo:1.05|g")
  end)

  it("gauge logs failure without a value", function()
    statsd.gauge("omg")
    statsd.defer_to_timer.flush_queue()

    assert.spy(ngx.log).was.called_with(ngx.WARN, "failed logging to statsd: no value passed")
  end)

  it("histogram sends integer", function()
    statsd.histogram("foo", 1)
    statsd.defer_to_timer.flush_queue()

    assert.are.equal(packet, "foo:1|h")
  end)

  it("histogram logs failure without a key", function()
    statsd.histogram(nil, 134)
    statsd.defer_to_timer.flush_queue()

    assert.spy(ngx.log).was.called_with(ngx.WARN, "failed logging to statsd: no value passed")
  end)

  it("distribution sends integer", function()
    statsd.distribution("foo", 1)
    statsd.defer_to_timer.flush_queue()

    assert.are.equal(packet, "foo:1|d")
  end)

  it("set sends integer", function()
    statsd.set("foo", 1)
    statsd.defer_to_timer.flush_queue()

    assert.are.equal(packet, "foo:1|s")
  end)

  it("measure sends some value", function()
    statsd.measure("foo", function() end)
    statsd.defer_to_timer.flush_queue()

    assert.is.not_nil(packet)
  end)

  it("measure returns multiple results from inner function", function()
    local one, two = statsd.measure("foo", function()
      return "one", "two"
    end)

    assert.are.equal(one, "one")
    assert.are.equal(two, "two")
  end)

  it("measure returns many results from inner function", function()
    local one, two, three, four, five = statsd.measure("foo", function()
      return "one", "two", "three", "four", "five"
    end)

    assert.are.equal(one, "one")
    assert.are.equal(two, "two")
    assert.are.equal(three, "three")
    assert.are.equal(four, "four")
    assert.are.equal(five, "five")
  end)

  it("generates tags", function()
    statsd.increment("foo", 1, { foo = "bar", bar = "baz"})
    statsd.defer_to_timer.flush_queue()

    local metric, tags_str = split_pair(packet, '#')
    assert.are.equal('foo:1|c|', metric)
    local tag1, tag2 = split_pair(tags_str, ',')
    local actual = {tag1, tag2}
    local expected = {'bar:baz', 'foo:bar'}
    table.sort(actual)
    table.sort(expected)
    assert.are.same(actual, expected)

    statsd.increment("foo", 1)
    statsd.defer_to_timer.flush_queue()

    assert.are.equal(packet, "foo:1|c")
  end)

  it("increments with sampling rate", function()
    math.random = function(self) return 0.4 end

    old_sampling_rate = statsd.config.sampling_rate
    statsd.config.sampling_rate = 0.5

    statsd.increment("foo")
    statsd.defer_to_timer.flush_queue()

    statsd.config.sampling_rate = old_sampling_rate

    assert.are.equal(packet, "foo:1|c|@0.5")
  end)

  it("measure accurately measures time", function()
    local gettime_called = false
    local gettime_mock = mock({
      gettimeofday = function()
        if gettime_called then
          return 10000000
        else
          gettime_called = true
          return 5000000
        end
      end
    })
    package.loaded['plugins.statsd.time'] = gettime_mock
    package.loaded["plugins.statsd.main"] = nil
    statsd = require("plugins.statsd.main")

    local ret = statsd.measure("test", function()
      return 1
    end)
    statsd.defer_to_timer.flush_queue()

    assert.are.equal(packet, "test:5000000|h") -- diff in microseconds
    assert.are.equal(1, ret)
  end)

  it("increments without sampling", function()
    local c = 0

    package.loaded["plugins.statsd.main"] = nil
    _G.ngx.socket.udp = function(...)
      local socket = old_udp(...)
      socket.setpeername = function(self, host, port) return 1 end
      socket.send = function(self, p) c = c + 1 end
      return socket
    end
    statsd = require("plugins.statsd.main")

    assert.are.equal(statsd.config.sampling_rate, 1)
    for i=1,10 do
      statsd.increment("foo")
    end
    statsd.defer_to_timer.flush_queue()

    assert.are.equal(10, c)
    _G.ngx.socket.udp = old_udp
  end)

  describe("when udp setpeername fails with error", function()

    before_each(function()
      package.loaded["plugins.statsd.main"] = nil
      _G.ngx.socket.udp = function(...)
        local socket = old_udp(...)
        socket.setpeername = function(self, host, port) return nil, "err" end
        return socket
      end
      statsd = require("plugins.statsd.main")
    end)

    after_each(function()
      _G.ngx.socket.udp = old_udp
    end)

    it("measure still returns values", function()
      local one, two = statsd.measure("foo", function()
        return "one", "two"
      end)
      statsd.defer_to_timer.flush_queue()

      assert.are.equal(one, "one")
      assert.are.equal(two, "two")
    end)

    it("logs a failure message", function()
      statsd.increment("foo")
      statsd.defer_to_timer.flush_queue()

      assert.spy(ngx.log).was.called_with(ngx.WARN, "failed logging to statsd: err")
    end)
  end)

  describe("when udp send fails with error", function()

    before_each(function()
      package.loaded["plugins.statsd.main"] = nil
      _G.ngx.socket.udp = function(...)
        local socket = old_udp(...)
        socket.setpeername = function(self, host, port) return 1 end
        socket.send = function(self, p) return nil, "err" end
        return socket
      end
      statsd = require("plugins.statsd.main")
    end)

    after_each(function()
      _G.ngx.socket.udp = old_udp
    end)

    it("logs when it fails to send", function()
      statsd.increment("foo")
      statsd.defer_to_timer.flush_queue()

      assert.spy(ngx.log).was.called_with(ngx.WARN, "failed logging to statsd: err")
    end)
  end)
end)
