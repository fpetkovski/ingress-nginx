local statsd = require("plugins.statsd.main")
local busted = require('busted')
local assert = require('luassert')

local statsd_trackers = { increment={}, histogram={}, gauge={} }

function _assertNotStatsdEmitted(type, key)
  assert.are.equal(statsd_trackers[type][key], nil, "expected not to receive "..type.." metric "..key)
end

function assertNotStatsdIncrement(key)
  _assertNotStatsdEmitted("increment", key)
end

function assertNotStatsdGauge(key)
  _assertNotStatsdEmitted("gauge", key)
end

function _assertStatsdEmitted(type, key, value, tags)
  local entry = statsd_trackers[type][key]
  assert.is.not_nil(entry, "expected statsd "..type.." metric '" ..key .. "' was not emitted")

  if value then
    assert.are.equal(entry.value, value)
  end

  if tags then
    assert.are.same(entry.tags, tags)
  end
end

function assertStatsdIncrement(key, value, tags)
  _assertStatsdEmitted("increment", key, value, tags)
end

function assertStatsdGauge(key, value, tags)
  _assertStatsdEmitted("gauge", key, value, tags)
end

function assertStatsdHistogram(key, value, tags)
  _assertStatsdEmitted("histogram", key, value, tags)
end

function reset_statsd_trackers()
  for tracker, _value in pairs(statsd_trackers) do
    statsd_trackers[tracker] = {}
  end
end

function _stub_statsd(type)
  statsd_trackers[type] = {}
  register_stub(statsd, type, function(key, value, tags)
    statsd_trackers[type][key] = {}
    statsd_trackers[type][key].value = value
    statsd_trackers[type][key].tags = tags or {}
  end)
end

function stub_statsd_increment()
  _stub_statsd("increment")
end

function stub_statsd_histogram()
  _stub_statsd("histogram")
end

function stub_statsd_gauge()
  _stub_statsd("gauge")
end
