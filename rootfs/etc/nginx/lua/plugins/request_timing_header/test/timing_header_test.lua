local function reformat_header(raw)
  return 'http_' .. string.lower(string.gsub(raw, '-', '_'))
end

local X_SHOPIFY_REQUEST_TIMING_HEADER = 'X-Shopify-Request-Timing'
local X_SHOPIFY_REQUEST_TIMING_HEADER_LC = reformat_header(X_SHOPIFY_REQUEST_TIMING_HEADER)

local original_os_getenv = os.getenv
local function mock_location_and_namespace(location, namespace)
  os.getenv = function(key)
    if key == 'KUBE_LOCATION' then
      return location
    end
    if key == 'POD_NAMESPACE' then
      return namespace
    end
    return original_os_getenv(key)
  end
end

local original_ngx = ngx
local function reset_ngx()
  _G.ngx = original_ngx
end

local function mock_ngx(mock)
  local _ngx = mock
  setmetatable(_ngx, { __index = ngx })
  _G.ngx = _ngx
end

describe('DC Header Updates', function()
  before_each(function()
    mock_ngx({
      var = {},
      req = {
        set_header = function(key, value)
          ngx.var[reformat_header(key)] = value
        end,
      }
    })
    package.loaded['plugins.request_timing_header.main'] = nil
  end)

  after_each(function()
    reset_ngx()
  end)

  teardown(function()
    os.getenv = original_os_getenv
  end)

  it('sets X-Shopify-Request-Timing for first hop', function()
    mock_location_and_namespace('gcp-us-east1', 'global-proxy-cloudflare-production')
    local request_timing_header = require('plugins.request_timing_header.main')

    request_timing_header.rewrite()

    assert.equal(ngx.var[X_SHOPIFY_REQUEST_TIMING_HEADER_LC], 'global-proxy-cloudflare-production;desc=gcp-us-east1;t=nil')
  end)

  it('prepends timing data to existing X-Shopify-Request-Timing header', function()
    mock_ngx({
      var = {[X_SHOPIFY_REQUEST_TIMING_HEADER_LC] = 'cf;t=1234.12345, global-proxy-cloudflare-production;desc=gcp-us-east1;t=nil'},
    })
    mock_location_and_namespace('gcp-us-central1', 'ingress-nginx-production')

    local request_timing_header = require('plugins.request_timing_header.main')

    request_timing_header.rewrite()

    assert.equal(ngx.var[X_SHOPIFY_REQUEST_TIMING_HEADER_LC], 'cf;t=1234.12345, global-proxy-cloudflare-production;desc=gcp-us-east1;t=nil, ingress-nginx-production;desc=gcp-us-central1;t=nil')
  end)
end)
