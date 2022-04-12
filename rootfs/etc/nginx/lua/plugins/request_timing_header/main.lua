local _M = {}
local string = string
local ngx = ngx

local function reformat_header(raw)
  return 'http_' .. string.lower(string.gsub(raw, '-', '_'))
end

local X_SHOPIFY_REQUEST_TIMING_HEADER = 'X-Shopify-Request-Timing'
local X_SHOPIFY_REQUEST_TIMING_HEADER_LC = reformat_header(X_SHOPIFY_REQUEST_TIMING_HEADER)
local KUBE_LOCATION = os.getenv('KUBE_LOCATION')
local POD_NAMESPACE = os.getenv('POD_NAMESPACE')

if not KUBE_LOCATION then
  error('KUBE_LOCATION env variable is not available')
end

if not POD_NAMESPACE then
  error('POD_NAMESPACE env variable is not available')
end

local function generate_header_value(pod_namespace, kube_location)
  return string.format(
      '%s;desc=%s;t=%s',
      pod_namespace,
      kube_location,
      ngx.var.msec
    )
end

local function build_chain(prev)
  if prev == nil then
    return generate_header_value(POD_NAMESPACE, KUBE_LOCATION)
  else
    return prev .. ', ' .. generate_header_value(POD_NAMESPACE, KUBE_LOCATION)
  end
end

function _M.rewrite()
  local incoming_request_timing_header = ngx.var[X_SHOPIFY_REQUEST_TIMING_HEADER_LC]
  local timing_header = build_chain(incoming_request_timing_header)
  ngx.req.set_header(X_SHOPIFY_REQUEST_TIMING_HEADER, timing_header)
end

return _M
