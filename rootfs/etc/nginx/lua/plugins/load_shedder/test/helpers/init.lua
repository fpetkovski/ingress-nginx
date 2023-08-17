package.path = "./rootfs/etc/nginx/lua/plugins/load_shedder/test/?.lua;./rootfs/etc/nginx/lua/plugins/load_shedder/test/helpers/?.lua;" .. package.path

math.randomseed(123)

-- avoid warning during test runs caused by
-- https://github.com/openresty/lua-nginx-module/blob/2524330e59f0a385a9c77d4d1b957476dce7cb33/src/ngx_http_lua_util.c#L810
setmetatable(_G, { __newindex = function(table, key, value) rawset(table, key, value) end })

ngx = require("ngx_mock")
package.loaded["ngx.upstream"] = ngx.upstream
ngx.reset()

ngx.shopify = {}
ngx.shopify.env = "test"
ngx.shopify.location = "local"
ngx.shopify.lua_modules_path = "."

require("stub")
require("helpers.statsd")
