--------------------------------------------------------------------------------
-- This module is a wrapper around statsd and defer_to_timer, which were
-- copy/pasta'd from statsd_monitor.
--------------------------------------------------------------------------------
local statsd = require("plugins.statsd.main")
local pairs = pairs

local _M = { statsd = statsd }
local default_labels = {
    ["telemetry.sdk.version"] = '0.2.2',
    ["telemetry.sdk.language"] = 'lua'
}
--------------------------------------------------------------------------------
-- Increment a counter
--------------------------------------------------------------------------------
function _M:add_to_counter(metric, increment, labels)
    self.statsd.increment(metric, increment, _M.make_labels(labels))
end

--------------------------------------------------------------------------------
-- Records a value for a metric with provided labels (corresponds to histogram
-- metric type in datadog)
--------------------------------------------------------------------------------
function _M:record_value(metric, value, labels)
    self.statsd.distribution(metric, value, _M.make_labels(labels))
end

--------------------------------------------------------------------------------
-- Observe a value for a metric with provided labels (corresponds to gauge
-- metric type in datadog
--------------------------------------------------------------------------------
function _M:observe_value(metric, value, labels)
    self.statsd.gauge(metric, value, _M.make_labels(labels))
end

function _M.make_labels(labels)
    if not labels then
        return default_labels
    else
        for k, v in pairs(default_labels) do
            labels[k] = v
        end

        return labels
    end
end

return _M
