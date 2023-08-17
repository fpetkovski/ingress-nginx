-- Tenant (shop, pods) categorization
local error = error
local ngx = ngx
local string = string
local tonumber = tonumber
local tostring = tostring

local configuration = require("plugins.load_shedder.configuration")
local quota_tracker = require("plugins.load_shedder.quota_tracker")
local shopify_utils = require("plugins.load_shedder.shopify_utils")
local statsd = require("plugins.statsd.main")

local _M = {
  QUOTA_TRACKER_DICT_NAME = "load_shedder_quota_tracker",

  GROUPS = {
    ABUSING = "abusing",
    EXCEEDING = "exceeding",
    STANDARD = "standard"
  },

  RULES = {
    CANARY_POD = "canary_pods",
    SHOP_OVERRIDE = "shop_tenancy_override",
    POD_OVERRIDE = "pod_tenancy_override",
    SHOP_AND_POD_EXCEEDING = "shop_and_pod_exceeding",
    POD_EXCEEDING = "pod_exceeding",
    SHOP_EXCEEDING = "shop_exceeding",
    DEFAULT = "default_tenancy",
  },

  trackers = {},
}

shopify_utils.assert_dict(_M.QUOTA_TRACKER_DICT_NAME)

local function tenancy_override(override)
  local upper_case = string.upper(tostring(override))
  -- These strings have to match those in spy/app/shedder/shedder_service.rb
  if upper_case == "ABUSING" then
    return _M.GROUPS.ABUSING
  elseif upper_case == "EXCEEDING" then
    return _M.GROUPS.EXCEEDING
  end
end

local function pod_override(pod_id)
  if not pod_id then return end
  return tenancy_override(configuration.pod_tenancy_override(pod_id))
end

local function shop_override(shop_id)
  if not shop_id then return end
  return tenancy_override(configuration.shop_tenancy_override(shop_id))
end

local function is_canary_pod_request(pod_type)
    return pod_type == "canary"
end

-- resource is the resource that the total usage is in the context of - e.g. a single mysql shard
-- resource is likely to come from controller/controller_class in the future
function _M.tracker_for(resource, usage_metric)
  if not usage_metric then
    local msg = "load shedder tenant.tracker_for passed nil usage_metric for " .. resource
    statsd.increment("load_shedder.tenant.nil_usage_metric", 1, { resource=resource })
    ngx.log(ngx.ERR, msg)
    error(msg)
  end

  -- e.g. mysql_pod_21.query_time_by_shop, unicorn_shopify_pool.processing_by_shop
  local metric_name = resource .. "." .. usage_metric
  local tracker = _M.trackers[metric_name]

  if not tracker then
    tracker = quota_tracker.new(_M.QUOTA_TRACKER_DICT_NAME, metric_name)
    _M.trackers[metric_name] = tracker
  end

  return tracker
end

-- TODO(tdickers): the shopify_pool part should come from upstream_name in the future
local unicorn_pod_tracker = _M.tracker_for("unicorn_shopify_pool", "processing_by_pod")
local unicorn_shop_tracker = _M.tracker_for("unicorn_shopify_pool", "processing_by_shop")

function _M.pod_requests_share(pod_id)
  return unicorn_pod_tracker:share(pod_id)
end

function _M.shop_requests_share(shop_id)
  return unicorn_shop_tracker:share(shop_id)
end

function _M.pod_requests_add(pod_id, time_spent)
  unicorn_pod_tracker:add(pod_id, time_spent)
end

function _M.shop_requests_add(shop_id, time_spent)
  unicorn_shop_tracker:add(shop_id, time_spent)
end

function _M.get_tenancy_and_rule(shop_id, pod_id, pod_type, pod_share, shop_share)
  ----------------------------
  -- Explicit manual overrides
  ----------------------------
  local shop_tenancy = shop_override(shop_id)
  if shop_tenancy then
    return shop_tenancy, _M.RULES.SHOP_OVERRIDE
  end

  local pod_tenancy = pod_override(pod_id)
  if pod_tenancy then
    return pod_tenancy, _M.RULES.POD_OVERRIDE
  end

  if is_canary_pod_request(pod_type) then
    return _M.GROUPS.ABUSING, _M.RULES.CANARY_POD
  end

  ----------------------
  -- Non-default tenant detection
  ----------------------
  local pod_share_limit = configuration.pod_tenant_share_limit(pod_id)
  local shop_share_limit = configuration.shop_tenant_share_limit(shop_id)
  if shop_share_limit > pod_share_limit then
    -- do not emit shop_id as a tag: possible datadog cardinality issue
    statsd.increment('load_shedder.invalid_share_limits', 1, {pod_id=pod_id})
    ngx.log(
      ngx.WARN,
      "invalid configuration for shop_id=" .. shop_id .. ", pod_id=" .. pod_id ..
      ". shop_share_limit=" ..  tostring(shop_share_limit) ..
      " is larger than pod_share_limit=" .. tostring(pod_share_limit)
    )
    shop_share_limit = pod_share_limit
  end

  local shop_is_exceeding = false
  if shop_share and shop_share > shop_share_limit then
    statsd.increment('load_shedder.shop_exceeding', 1, {shop_id=shop_id})
    shop_is_exceeding = true
  end

  local pod_is_exceeding = false
  if pod_share and pod_share > pod_share_limit then
    statsd.increment('load_shedder.pod_exceeding', 1, {pod_id=pod_id})
    pod_is_exceeding = true
  end

  if shop_is_exceeding and pod_is_exceeding then
    return _M.GROUPS.ABUSING, _M.RULES.SHOP_AND_POD_EXCEEDING
  elseif shop_is_exceeding then
    return _M.GROUPS.EXCEEDING, _M.RULES.SHOP_EXCEEDING
  elseif pod_is_exceeding then
    return _M.GROUPS.EXCEEDING, _M.RULES.POD_EXCEEDING
  end

  ----------------------
  -- Nothing special about this tenant
  ----------------------
  return _M.GROUPS.STANDARD, _M.RULES.DEFAULT
end

function _M.get(shop_id, pod_id, pod_type)
  local pod_requests_share = _M.pod_requests_share(pod_id)
  local shop_requests_share = _M.shop_requests_share(shop_id)

  -- For now, this is how we can test request levels that we can't simulate otherwise
  -- If this gets removed, we may be able to remove require("shopify.util") above
  -- luacheck: ignore ngx
  if ngx['shopify'] and ngx.shopify.env == "test" then
    local req_tenancy_override = shopify_utils.get_request_header("request-tenancy-override")
    local tenancy_rule_override = shopify_utils.get_request_header("request-tenancy-rule-override")
    if req_tenancy_override and tenancy_rule_override then
      return req_tenancy_override, tenancy_rule_override
    end

    pod_requests_share = tonumber(
      shopify_utils.get_request_header("request-pod-share-override")) or pod_requests_share
    shop_requests_share = tonumber(
      shopify_utils.get_request_header("request-shop-share-override")) or shop_requests_share
  end

  if ngx.ctx.tenancy == nil then
    ngx.ctx.tenancy, ngx.ctx.tenancy_rule = _M.get_tenancy_and_rule(
      shop_id, pod_id, pod_type, pod_requests_share, shop_requests_share
    )
  end
  return ngx.ctx.tenancy, ngx.ctx.tenancy_rule
end

return _M
