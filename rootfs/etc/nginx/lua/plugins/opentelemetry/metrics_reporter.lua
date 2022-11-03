--------------------------------------------------------------------------------
-- This module is a wrapper around statsd and defer_to_timer, which were
-- copy/pasta'd from statsd_monitor.
--------------------------------------------------------------------------------
local statsd = require("plugins.opentelemetry.statsd")

local _M = { statsd = statsd }

--------------------------------------------------------------------------------
-- Increment a counter
--------------------------------------------------------------------------------
function _M:add_to_counter(metric, increment, labels)
    self.statsd.increment(metric, increment, labels)
end

--------------------------------------------------------------------------------
-- Records a value for a metric with provided labels (corresponds to histogram
-- metric type in datadog)
-- todo(plantfansam): make this a statsd distribution
--------------------------------------------------------------------------------
function _M:record_value(metric, value, labels)
    self.statsd.histogram(metric, value, labels)
end

--------------------------------------------------------------------------------
-- Observe a value for a metric with provided labels (corresponds to gauge
-- metric type in datadog
--------------------------------------------------------------------------------
function _M:observe_value(metric, value, labels)
    self.statsd.gauge(metric, value, labels)
end

return _M
