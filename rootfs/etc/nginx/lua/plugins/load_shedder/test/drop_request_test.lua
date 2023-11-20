package.path = "./rootfs/etc/nginx/lua/plugins/load_shedder/test/?.lua;./rootfs/etc/nginx/lua/plugins/load_shedder/test/helpers/?.lua;" .. package.path
require("helpers.init")
require("helpers.load_shedder")

local busted = require('busted')
local assert = require('luassert')
local drop_request = require("plugins.load_shedder.drop_request")

describe("plugins.load_shedder.drop_request", function()

  before_each(function()
    ngx.reset()
    reset_stubs()
  end)

  it("exits with status 503", function()
    drop_request()
    assert.equals(ngx.HTTP_SERVICE_UNAVAILABLE, ngx.status)
  end)

  it("sets a custom response body", function()
    drop_request()
    assert.contains("There was a problem loading this website", ngx.printed)
  end)

end)
