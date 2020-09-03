local function reformat_header(raw)
  return 'http_' .. string.lower(string.gsub(raw, '-', '_'))
end

local X_DC_HEADER = 'X-Dc'
local X_DOWNSTREAM_DC_HEADER = 'X-Downstream-Dc'
local X_DOWNSTREAM_DC_HEADER_LC = reformat_header(X_DOWNSTREAM_DC_HEADER)

local original_os_getenv = os.getenv
local function mock_current_location(location)
  os.getenv = function(key)
    if key == 'KUBE_LOCATION' then
      return location
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
      ctx = {},
      header = {},
      var = {},
      req = {
        set_header = function(key, value)
          ngx.var[reformat_header(key)] = value
        end,
      }
    })
    package.loaded['plugins.datacenter_header.main'] = nil
  end)

  after_each(function()
    reset_ngx()
  end)
  
  it('sets X-Dc to current location', function()
    mock_current_location('gcp-us-east1')
    local datacenter_header = require('plugins.datacenter_header.main')

    datacenter_header.rewrite()
    datacenter_header.header_filter()

    assert.equal(ngx.var[X_DOWNSTREAM_DC_HEADER_LC], 'gcp-us-east1')
    assert.equal(ngx.header[X_DC_HEADER], 'gcp-us-east1')
  end)

  it('prepends current location to existing X-Dc', function()
    mock_ngx({
      header = {[X_DC_HEADER] = 'gcp-us-east1'},
      var = {[X_DOWNSTREAM_DC_HEADER_LC] = 'gcp-us-east1'},
    })
    mock_current_location('gcp-us-central1')
    local datacenter_header = require('plugins.datacenter_header.main')

    datacenter_header.rewrite()
    datacenter_header.header_filter()

    assert.equal(ngx.var[X_DOWNSTREAM_DC_HEADER_LC], 'gcp-us-central1,gcp-us-east1')
    assert.equal(ngx.header[X_DC_HEADER], 'gcp-us-central1,gcp-us-east1')
  end)
end)
