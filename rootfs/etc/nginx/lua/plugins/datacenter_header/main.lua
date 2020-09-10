local _M = {}
local string = string
local type = type
local table = table
local ngx = ngx

local function reformat_header(raw)
  return 'http_' .. string.lower(string.gsub(raw, '-', '_'))
end

local X_DC_HEADER = 'X-Dc'
local X_DOWNSTREAM_DC_HEADER = 'X-Downstream-Dc'
local X_DOWNSTREAM_DC_HEADER_LC = reformat_header(X_DOWNSTREAM_DC_HEADER)
local KUBE_LOCATION = os.getenv('KUBE_LOCATION')

if not KUBE_LOCATION then
  error('KUBE_LOCATION env variable is not available')
end

local function build_chain(prev)
  if prev == nil then
    return KUBE_LOCATION
  elseif type(prev) == 'table' then
    -- This will only happen if two DCs without this middleware have added the X-Dc header,
    -- which should only be possible in the duration of the initial deploy of this middleware
    -- (and only for requests that hit more than two DCs).
    return KUBE_LOCATION .. ',' .. table.concat(prev, ',')
  else
    return KUBE_LOCATION .. ',' .. prev
  end
end

function _M.rewrite()
  local downstream_dc_header = ngx.var[X_DOWNSTREAM_DC_HEADER_LC]
  local dc_path = build_chain(downstream_dc_header)
  ngx.req.set_header(X_DOWNSTREAM_DC_HEADER, dc_path)
end

function _M.header_filter()
  ngx.ctx.dc_path = build_chain(ngx.header[X_DC_HEADER])
  ngx.header[X_DC_HEADER] = ngx.ctx.dc_path
end

return _M
