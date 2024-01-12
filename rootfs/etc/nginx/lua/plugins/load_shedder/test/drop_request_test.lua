package.path = "./rootfs/etc/nginx/lua/plugins/load_shedder/test/?.lua;./rootfs/etc/nginx/lua/plugins/load_shedder/test/helpers/?.lua;" .. package.path
require("helpers.init")
require("helpers.load_shedder")

local match = require("luassert.match")
local busted = require('busted')
local assert = require('luassert')
local drop_request = require("plugins.load_shedder.drop_request")

local original_io = _G.io

describe("plugins.load_shedder.drop_request", function()

  before_each(function()
    ngx.reset()
    reset_stubs()
  end)

  after_each(function()
    _G.io = original_io
  end)

  it("exits with status 503 and sets a custom response body", function()
    ngx.req.set_header('accept', "text/html")
    stub(ngx, "exit")
    stub(ngx, "print")

    drop_request()
    assert.equals(ngx.HTTP_SERVICE_UNAVAILABLE, ngx.status)
    assert.equals('text/html', ngx.header.content_type)
    assert.stub(ngx.exit).was_called_with(ngx.HTTP_SERVICE_UNAVAILABLE)
    assert.stub(ngx.print).was_called_with(match.has_match('There was a problem loading this website'))
  end)

  it("exits with status 503 and sets a custom response body", function()
    ngx.req.set_header('accept', "application/json")
    stub(ngx, "exit")
    stub(ngx, "print")

    drop_request()
    assert.equals(ngx.HTTP_SERVICE_UNAVAILABLE, ngx.status)
    assert.equals('application/json', ngx.header.content_type)
    assert.stub(ngx.exit).was_called_with(ngx.HTTP_SERVICE_UNAVAILABLE)
    assert.stub(ngx.print).was_called_with(match.has_match('There was a problem loading this website. Please try again.'))
  end)

  it("exits because unable to open error page", function()
    stub(ngx, "exit")
    stub(ngx, "log")
    _G.io.open = function(filename, extension) return false, "err" end

    drop_request()
    assert.equal(ngx.status, ngx.HTTP_SERVICE_UNAVAILABLE)
    assert.stub(ngx.exit).was_called_with(ngx.HTTP_SERVICE_UNAVAILABLE)
    assert.stub(ngx.log).was_called_with(ngx.ERR, "Unable to open error page json: err")
  end)

  it("exits because unable to find error page", function()
    stub(ngx, "exit")
    stub(ngx, "log")
    _G.io.open = function(filename, extension) return true, nil end
    _G.io.input = function(filename) return true end
    _G.io.read = function() return nil end
    _G.io.close = function(filename) return true end

    drop_request()
    assert.equal(ngx.status, ngx.HTTP_SERVICE_UNAVAILABLE)
    assert.stub(ngx.exit).was_called_with(ngx.HTTP_SERVICE_UNAVAILABLE)
    assert.stub(ngx.log).was_called_with(ngx.WARN, "unable to find error page for 503 status")
  end)


end)
