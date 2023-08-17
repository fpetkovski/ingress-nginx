local ngx = ngx
local math = math
local pairs = pairs
local pcall = pcall
local string = string
local tonumber = tonumber
local tostring = tostring

local access_controller = require("plugins.load_shedder.access_controller")
local access_level = require("plugins.load_shedder.access_level")
local configuration = require("plugins.load_shedder.configuration")
local drop_request = require("plugins.load_shedder.drop_request")
local ewma_shared = require("plugins.load_shedder.ewma_shared")
local request = require("plugins.load_shedder.request_priority")
local shopify_utils = require("plugins.load_shedder.shopify_utils")
local statsd = require("plugins.statsd.main")
local tenant = require("plugins.load_shedder.tenant")

local duration = require("util.duration_parsing").duration
local get_first_value = require("util.split").get_first_value

local SERVER_TIMING_HEADER = "Server-Timing"
local SORTING_HAT_POD_ID_HEADER = "X-Sorting-Hat-PodId"
local SORTING_HAT_SHOP_ID_HEADER = "X-Sorting-Hat-ShopId"
local SORTING_HAT_POD_TYPE_HEADER = "X-Sorting-Hat-PodType"

local NUM_ACCESS_LEVELS = access_level.MAX_SHEDDABLE
local STATSD_REPORTING_UNICORN_SHOP_SHARES_MIN_PERCENTAGE = 0.05

local UNICORN_CONTROLLER_CLASS = "unicorn"

local _M = {
  controllers = {},
  SORTING_HAT_POD_ID_HEADER = SORTING_HAT_POD_ID_HEADER,
  SORTING_HAT_POD_TYPE_HEADER = SORTING_HAT_POD_TYPE_HEADER,
  SORTING_HAT_SHOP_ID_HEADER = SORTING_HAT_SHOP_ID_HEADER,
}

local function get_server_timing_header()
  local timing_header = ngx.ctx.server_timing_internal
  -- fallback to get the header
  if not timing_header then
    timing_header = ngx.resp.get_headers()[SERVER_TIMING_HEADER]
  end

  return timing_header
end

local function update_controller(upstream_name, controller, req_statsd_tags)
  local util_sample, err = duration(get_server_timing_header(), "util")
  if err then
    statsd.increment('load_shedder.util_sample.not_found', 1, req_statsd_tags)
  else
    local new_ema, _ = ewma_shared.update(upstream_name, util_sample)
    controller:update(new_ema)
  end
end

local function update_unicorn_request_stats(pod_id, shop_id, req_statsd_tags)
  -- Get the app server time usage and add it to the pod weight count
  local processing_time_ms, err = duration(get_server_timing_header(), "processing")
  if err then
    statsd.increment('load_shedder.processing_sample.not_found', 1, req_statsd_tags)

    -- Server-Timing is not available. The unicorn serving the request might have been
    -- killed due to a timeout. We will fallback to using `upstream_response_time` in that
    -- case. See https://github.com/Shopify/service-disruptions/issues/1179 for context.
    if ngx.status == ngx.HTTP_BAD_GATEWAY then
      statsd.increment('load_shedder.server_timing_fallback.count', 1, req_statsd_tags)

      local response_time_secs = tonumber(get_first_value(ngx.var.upstream_response_time))
      if response_time_secs then
        processing_time_ms = response_time_secs * 1000
        statsd.histogram(
          'load_shedder.server_timing_fallback.processing_time_ms',
          processing_time_ms,
          req_statsd_tags
        )
      end
    end
  end

  if processing_time_ms then
    tenant.pod_requests_add(pod_id, processing_time_ms)
    tenant.shop_requests_add(shop_id, processing_time_ms)
  end

  -- Update metric regardless of if we didn't get a new sample this request
  -- (traffic for other pods still affects share)
  statsd.gauge(
    'load_shedder.unicorn.pod_shares', tenant.pod_requests_share(pod_id), {pod_id=tostring(pod_id)}
  )
  local shop_share = tenant.shop_requests_share(shop_id)
  -- reduce reporting cardinality by only reporting shops that are above a certain threshold
  if shop_share > STATSD_REPORTING_UNICORN_SHOP_SHARES_MIN_PERCENTAGE then
    statsd.gauge('load_shedder.unicorn.shop_shares', shop_share, {shop_id=tostring(shop_id)})
  end
end

local function update_request_stats(pod_id, shop_id, req_statsd_tags)
  -- report and track nil as unknown
  pod_id = pod_id or "unknown"
  shop_id = shop_id or "unknown"

  update_unicorn_request_stats(pod_id, shop_id, req_statsd_tags)
end

local function emit_dict_free_space(metric_name, dict_name)
  local dict = ngx.shared[dict_name]
  if not dict then
    return
  end

  statsd.gauge(metric_name, dict:free_space())
end

local function unsafe_emit_free_bytes()
  -- in test: always run
  -- otherwise: run only every ~100 calls
  -- luacheck: ignore ngx
  if ngx['shopify'] and ngx.shopify.env == "test" or math.random() >= 0.99 then
    emit_dict_free_space("load_shedder.shops_quota_dict_free_bytes", tenant.QUOTA_TRACKER_DICT_NAME)
    emit_dict_free_space("load_shedder.util_ewma_dict_free_bytes", ewma_shared.EWMA_DICT)
  end
end

local function should_drop_request(controller, level_value, statsd_tags)
  local tags = shopify_utils.merge_tables_by_key(
    { controller = controller.name, controller_class = controller.class },
    statsd_tags
  )

  if not controller:allow(level_value) then
    statsd.increment("load_shedder.request.would_drop", 1, tags)

    if controller:enabled() then
      statsd.increment("load_shedder.request.dropped", 1, tags)
      return true
    end
  end
  return false
end

local function call_access_phase(upstream, controller, request_priority, level_value, statsd_tags)
  ngx.req.set_header("X-Request-Priority", request_priority)

  -- get latest ewma because it could have been updated by another worker
  local util_avg = ewma_shared.get(upstream)
  controller:update(util_avg)

  if should_drop_request(controller, level_value, statsd_tags) then
    ngx.ctx.request_dropped_by_load_shedder = true
    drop_request()
  end
end

local function call_log_phase(upstream_name, controller, pod_id, shop_id, request_statsd_tags)
  local req_statsd_tags = shopify_utils.merge_tables_by_key(
    {dropped=tostring(ngx.ctx.request_dropped_by_load_shedder == true)},
    request_statsd_tags
  )
  statsd.increment('load_shedder.request.log', 1, req_statsd_tags)

  if ngx.ctx.request_dropped_by_load_shedder then
    return
  end

  update_controller(upstream_name, controller, req_statsd_tags)
  update_request_stats(pod_id, shop_id, req_statsd_tags)

  if not pcall(unsafe_emit_free_bytes) then
    statsd.increment('load_shedder.emit_free_bytes_error', 1)
  end
end

local function protect_or_ignore_upstream(upstream)
  -- return two values: first one specifies if we found the upstream in the list of protected
  -- upstreams; the second one is meaningful only when the first one is false, and it tells
  -- us if we found it in the list of ignored upstreams
  local upstreams = configuration.upstreams()

  if upstreams then
    local state = upstreams[upstream]
    return state == "protect", state == "ignore"
  end
  return false, false
end

local function controller_for_unicorn_upstream(upstream_name)
  local controller_name = UNICORN_CONTROLLER_CLASS .. "_" .. upstream_name

  local controller = _M.controllers[controller_name]
  if not controller then
    controller = access_controller.new(
      NUM_ACCESS_LEVELS,
      UNICORN_CONTROLLER_CLASS,
      controller_name,
      'load_shedder',
      configuration
    )

    _M.controllers[controller_name] = controller
  end
  return controller
end

local function apply_priority_overrides(priority, priority_rule, shop_id)
  if configuration.prevent_all_checkout_shedding_globally() then
    -- global "disable checkout shedding" enabled
    return priority, priority_rule
  elseif (priority_rule == request.RULES.CHECKOUT_HOST or
          priority_rule == request.RULES.CHECKOUT_URI_INFERENCE) then
    if configuration.prevent_shops_sheddable_checkouts(shop_id) then
      -- shop "disable checkout shedding" enabled
      return priority, priority_rule
    elseif ngx.var.geoip2_is_anonymous=="1" then
      -- `anon:1` always shed
      ngx.ctx.request_priority = request.PRIORITIES.HIGH
      ngx.ctx.request_rule = request.RULES.OVERRIDDEN
      return request.PRIORITIES.HIGH, request.RULES.OVERRIDDEN
    elseif configuration.sheddable_checkouts(shop_id) then
      -- `anon:0` only shed when turned on per shop
      statsd.increment("load_shedder.sheddable_checkouts")
      ngx.ctx.request_priority = request.PRIORITIES.HIGH
      ngx.ctx.request_rule = request.RULES.OVERRIDDEN
      return request.PRIORITIES.HIGH, request.RULES.OVERRIDDEN
    end
  end
  return priority, priority_rule
end

function _M.get_priority_tenancy_level_rule(shop_id, pod_id, pod_type)
  local priority, priority_rule = request.get()
  priority, priority_rule = apply_priority_overrides(priority, priority_rule, shop_id)
  local tenancy, tenancy_rule = tenant.get(shop_id, pod_id, pod_type)
  local level = access_level.get(UNICORN_CONTROLLER_CLASS, priority, tenancy)
  if not level then
    ngx.log(
      ngx.ERR,
      "could not determine load shedder access level - controller_class=" ..
        UNICORN_CONTROLLER_CLASS
    )
    statsd.increment(
      "load_shedder.error.nil_access_level",
      1,
      {controller_class=UNICORN_CONTROLLER_CLASS}
    )
    level = NUM_ACCESS_LEVELS + 1 -- fallback to unsheddable
  end
  local matched_rule = tenancy_rule .. "+" .. priority_rule
  return priority, tenancy, level, matched_rule
end

local function should_run(upstream_name)
  if not upstream_name or upstream_name == "" then
    -- TODO: alert on this? first we need to distinguish what was served by upstream vs from cache
    --
    -- not logging error here because any cache misses
    statsd.increment('load_shedder.upstream.not_found', 1)
    return false
  end

  -- TODO: get rid of is_ignored in favour of using just last_request_in_proxy_path & a protect list
  local is_protected, is_ignored = protect_or_ignore_upstream(upstream_name)
  if not is_protected then
    if not is_ignored then
      local upstreams = ""
      for k, v in pairs(configuration.upstreams()) do
        upstreams = upstreams .. string.format("%s=%s&", k, v)
      end
      if upstreams == "" then
        upstreams = "empty_list"
      end
      statsd.increment(
        'load_shedder.upstream.skipped',
        1,
        {upstream=upstream_name, upstreams=upstreams}
      )
    end
    return false
  end
  return true
end

function _M.should_drop_request_for_upstream(upstream_name, pod_id, matched_rule, level_value)
  if not should_run(upstream_name) then return false end

  local controller = controller_for_unicorn_upstream(upstream_name)
  local statsd_tags = {
    upstream=upstream_name,
    pod_id=pod_id,
    level=level_value,
    matched_rule=matched_rule,
    worker_id=ngx.worker.id()
  }

  return should_drop_request(controller, level_value, statsd_tags)
end

local function setup(upstream_name)
  local shop_id = shopify_utils.get_request_header(SORTING_HAT_SHOP_ID_HEADER)
  local pod_id = shopify_utils.get_request_header(SORTING_HAT_POD_ID_HEADER)
  local pod_type = shopify_utils.get_request_header(SORTING_HAT_POD_TYPE_HEADER)

  if ngx.ctx.load_shedder_priority == nil then
    ngx.ctx.load_shedder_priority, ngx.ctx.load_shedder_tenancy,
    ngx.ctx.load_shedder_level, ngx.ctx.load_shedder_matched_rule =
       _M.get_priority_tenancy_level_rule(shop_id, pod_id, pod_type)
  end

  local is_anon = ngx.var.geoip2_is_anonymous
  if (ngx.var.http_shopify_storefront_private_token ~= nil and
      ngx.var.http_shopify_storefront_buyer_ip ~= nil) then
    is_anon = ngx.var.geoip2_is_anonymous_buyer_ip_untrusted
  end

  -- statsd tags
  local statsd_tags = {
    upstream=upstream_name,
    pod_id=pod_id,
    priority=ngx.ctx.load_shedder_priority,
    level=ngx.ctx.load_shedder_level,
    tenancy=ngx.ctx.load_shedder_tenancy,
    matched_rule=ngx.ctx.load_shedder_matched_rule,
    worker_id=ngx.worker.id(),
    is_anon=is_anon
  }

  local controller = controller_for_unicorn_upstream(upstream_name)

  return controller, pod_id, shop_id, statsd_tags
end

function _M.access()
  local upstream_name = ngx.var.proxy_upstream_name
  if not should_run(upstream_name) then return end

  local controller, _, _, statsd_tags = setup(upstream_name)
  call_access_phase(
    upstream_name,
    controller,
    ngx.ctx.load_shedder_priority,
    ngx.ctx.load_shedder_level,
    statsd_tags
  )
end

function _M.log()
  local upstream_name = ngx.var.proxy_upstream_name
  if not should_run(upstream_name) then return end

  local controller, pod_id, shop_id, statsd_tags = setup(upstream_name)
  call_log_phase(
    upstream_name,
    controller,
    pod_id,
    shop_id,
    statsd_tags
  )
end

return _M
