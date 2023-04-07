std = 'ngx_lua'
max_line_length = 100
exclude_files = {'./rootfs/etc/nginx/lua/test/**/*.lua', './rootfs/etc/nginx/lua/plugins/**/test/**/*.lua', './rootfs/etc/nginx/lua/plugins/opentelemetry/benchmark/*.lua'}
files["rootfs/etc/nginx/lua/lua_ingress.lua"] = {
  ignore = { "122" },
  -- TODO(elvinefendi) figure out why this does not work
  --read_globals = {"math.randomseed"},
}
files["rootfs/etc/nginx/lua/plugins/opentelemetry/*.lua"] = {
  ignore = { "631" },
}
