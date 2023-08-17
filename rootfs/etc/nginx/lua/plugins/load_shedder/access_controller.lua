local math = math
local ngx = ngx
local setmetatable = setmetatable

local shopify_utils = require("plugins.load_shedder.shopify_utils")
local statsd = require("plugins.statsd.main")

local _M = {}
_M.__index = _M

local function calculate_drop_rate(soft, hard, max_drop_rate, current_utilization)
  --
  --  drop rate is the following ratio:
  --    num_rejected / num_requests
  --
  --  for example, a ratio of 1/4 means for every 4 requests drop 1 one of them
  --  or in simple words, drop 25% of requests, up to a maximum of the max_drop_rate

  --  calculate the target drop rate based on this _linear_ scale:
  --
  --      soft                   hard
  --   <---|-----------|-----------|--->
  --       0%        max/2%      max%
  --
  local rate = (current_utilization - soft) / (hard - soft)
  rate = math.min(rate, 1)
  rate = math.max(rate, 0)

  return rate * max_drop_rate
end

local function drop_rate_for_level(self, level)
  local drop_rate = 0
  if self.drop_rates[level] then
    drop_rate = self.drop_rates[level]
  end
  return drop_rate
end

local function emit_statsd_metrics(self)
  statsd.gauge(self.statsd_prefix .. '.util_avg', self.util_avg, self.statsd_tags)

  local total_drop_level = 0
  for level = 1, self.number_of_levels do
    total_drop_level = total_drop_level + self.drop_rates[level]

    statsd.gauge(
      self.statsd_prefix .. '.drop_rate',
      self.drop_rates[level],
      shopify_utils.merge_tables_by_key({level=level}, self.statsd_tags)
    )
  end
  statsd.gauge(self.statsd_prefix .. '.drop_level', total_drop_level, self.statsd_tags)
end

local function update_drop_rates(self)
  -- calculate mutually exclusive drop rates in order of increasing level
  --
  -- this means that all requests from a lower level will be dropped
  -- at max_drop_rate before we move on to dropping the next level
  --
  -- for example, with 3 levels, we'll have 3 **distinct** drop_rate
  -- functions as shown below:
  --
  --             drop_rate
  --                |
  --   global      ... . . . . . ****. . ****. . ****
  -- max_drop_rate% |          / .      /.      /.
  --                |         /  .     / .     / .
  --                |        /   .    /  .    /  .
  --                |       /    .   /   .   /   .
  --                |      /     .  /    .  /    .
  --                |     /      . /     . /     .
  --                |    /       ./      ./      .
  --                |   /        /       /       .
  --        0% -----****|-----***|----***-----***|--------- utilization
  --                    |<-step->|               |
  --                    |                        |
  --                  global                   global
  --                  soft                     hard
  --                  limit                    limit
  --
  local soft_limit, global_hard_limit, max_drop_rate = self.configuration.limits(self.class)

  local step = (global_hard_limit - soft_limit) / self.number_of_levels
  local hard_limit = soft_limit + step

  for level = 1, self.number_of_levels do
    if level == self.number_of_levels then
      hard_limit = global_hard_limit
    end

    self.drop_rates[level] = calculate_drop_rate(
      soft_limit, hard_limit, max_drop_rate, self.util_avg
    )

    soft_limit = hard_limit
    hard_limit = soft_limit + step
  end
end

-- Access controller implements a mechanism where requests are rejected in increasing priority.
-- Request levels can be used to implement access allowed rules such as:
--   - Rejecting requests in order of their levels
--   - Rejecting out-of-quota consumers before those within
--   - Creating a consistent user experience during overload (by hashing client IPs to levels)
function _M.new(number_of_levels, controller_class, controller_name, statsd_prefix, configuration)
  local self = {
    number_of_levels = number_of_levels,
    name = controller_name,
    class = controller_class,
    statsd_tags = {
      controller_class=controller_class,
      controller=controller_name,
      worker_id=ngx.worker.id()
    },
    drop_rates = {},
    util_avg = 0,
    statsd_prefix = statsd_prefix,
    configuration = configuration,
  }

  update_drop_rates(self)

  return setmetatable(self, _M)
end

function _M:update(util_avg)
  self.util_avg = util_avg or 0
  update_drop_rates(self)
  emit_statsd_metrics(self)
end

-- access levels above self.number_of_levels will always be allowed
function _M:allow(access_level)
  return math.random() >= drop_rate_for_level(self, access_level)
end

function _M:enabled()
  return self.configuration.enabled()
end

return _M
