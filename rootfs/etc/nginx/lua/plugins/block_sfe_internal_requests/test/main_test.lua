local SNI_TO_BLOCK = {
  'app.sfe.shopifyinternal.com',
  'service.shopifyinternal.com',
  'sfr-internal.shopifycloud.com',
  'sfr-internal-canada.shopifycloud.com',
  'sfapi-internal.shopifycloud.com',
  'sfapi-internal.shopifycloud.COM',
}

local original_ngx = ngx

local function mock_ngx(mock)
  local _ngx = mock
  setmetatable(_ngx, { __index = ngx })
  _G.ngx = _ngx
end

local function mock_ssl_server_name(sni)
  package.loaded['ngx.ssl']['server_name'] = function()
    return sni, nil
  end
end

local mock_exit = spy.new(function(status)
  assert.are.equal(403, status)
end)

local function reset_ngx()
  _G.ngx = original_ngx
  mock_exit:clear()
end

describe('Block SNI ', function()
  before_each(function()
    package.loaded['plugins.block_sfe_internal_requests.main'] = nil
    package.loaded['ngx.ssl'] = nil
  end)

  after_each(function()
    reset_ngx()
  end)

  it('dissallows any request with a blocked sni', function()
    for _, sni in ipairs(SNI_TO_BLOCK) do
      reset_ngx()
      mock_ngx({
        var = {
          http_host = sni,
          https = 'on',
        },
        exit = mock_exit,
      })
      local plugin = require('plugins.block_sfe_internal_requests.main')
      mock_ssl_server_name(sni)

      plugin.rewrite()
      assert.spy(mock_exit).was.called(1)
    end
  end)

  it('dissallows any https request with a blocked host', function()
    for _, host in ipairs(SNI_TO_BLOCK) do
      reset_ngx()
      mock_ngx({
        var = {
          http_host = host,
          https = 'on',
        },
        exit = mock_exit,
      })
      local plugin = require('plugins.block_sfe_internal_requests.main')

      plugin.rewrite()
      assert.spy(mock_exit).was.called(1)
    end
  end)

  it('dissallows any http request with a blocked host', function()
    for _, host in ipairs(SNI_TO_BLOCK) do
      reset_ngx()
      mock_ngx({
        var = {
          http_host = host,
          https = nil,
        },
        exit = mock_exit,
      })
      local plugin = require('plugins.block_sfe_internal_requests.main')

      plugin.rewrite()
      assert.spy(mock_exit).was.called(1)
    end
  end)

  it('allows snis and hosts not in the blocked list', function()
    local mock_ngx_table = {
      var = {
        http_host = "some-other-sni.shopifycloud.com",
        https = "on",
      },
      exit = mock_exit,
    }

    -- check sni
    mock_ngx(mock_ngx_table)
    local plugin = require('plugins.block_sfe_internal_requests.main')
    mock_ssl_server_name("some-other-sni.shopifycloud.com")
    plugin.rewrite()
    assert.spy(mock_exit).was.called(0)

    -- check host header
    reset_ngx()
    mock_ngx(mock_ngx_table)
    local plugin = require('plugins.block_sfe_internal_requests.main')
    plugin.rewrite()
    assert.spy(mock_exit).was.called(0)
  end)
end)
