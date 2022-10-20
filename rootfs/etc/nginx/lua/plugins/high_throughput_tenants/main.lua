local ngx = ngx
local math = math
local tonumber = tonumber

local X_HIGH_THROUGHPUT_HEADER = 'X-High-Throughput-Tenant'
local SHARED_DICT_NAME = 'high_throughput_tracker'
local MIN_REQUEST_PERCENTAGE = 0.2
local SERVER_TIMING_HEADER = "Server-Timing"

local quota_tracker = require("plugins.high_throughput_tenants.quota_tracker")
local util = require("plugins.high_throughput_tenants.util")
local split = require("util.split")

local function get_tenant()
  return ngx.var.http_x_sorting_hat_shopid
end

local function get_time_tracker()
  return quota_tracker.new(SHARED_DICT_NAME, "t")
end

local function get_count_tracker()
  return quota_tracker.new(SHARED_DICT_NAME, "c")
end

local function get_server_timing_processing()
  local timing_header = ngx.resp.get_headers()[SERVER_TIMING_HEADER]
  if not timing_header then
    return nil
  end

  return util.parse_server_timing_processing(timing_header)
end

local _M = {}

function _M.rewrite()
  local tenant = get_tenant()
  if not tenant then
    return
  end

  local time_tracker = get_time_tracker()
  local time_share = time_tracker:share(tenant)

  local count_tracker = get_count_tracker()
  local count_share = count_tracker:share(tenant)

  local share = math.max(time_share, count_share)

  if share > MIN_REQUEST_PERCENTAGE then
    ngx.req.set_header(X_HIGH_THROUGHPUT_HEADER, 'true')
  end
end

function _M.log()
  local tenant = get_tenant()
  if not tenant then
    return
  end

  local processing_time_ms = get_server_timing_processing()
  if not processing_time_ms then
    -- Server-Timing is not available. The server process might have been killed due to a timeout.
    -- We will fallback to using `upstream_response_time` in that case.
    local response_time_secs = tonumber(split.get_first_value(ngx.var.upstream_response_time))
    if response_time_secs then
      processing_time_ms = response_time_secs * 1000
    end
  end

  if processing_time_ms then
    local time_tracker = get_time_tracker()
    time_tracker:add(tenant, processing_time_ms)
  end

  local count_tracker = get_count_tracker()
  count_tracker:add(tenant, 1)
end

return _M
