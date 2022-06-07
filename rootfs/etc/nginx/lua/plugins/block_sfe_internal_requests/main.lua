local require = require
local ngx = ngx
local ipairs = ipairs

local ssl = require("ngx.ssl")
local re_match = ngx.re.match

local SFR_INTERNAL_SNI_REGEX = "sfr-internal.*\\.shopifycloud\\.com"
local SFAPI_INTERNAL_SNI_REGEX = "sfapi-internal.*\\.shopifycloud\\.com"
local GLOBAL_PROXY_INTERNAL_SNI_REGEX = ".+\\.shopifyinternal\\.com"

local SNI_TO_BLOCK_REGEX = {
  SFR_INTERNAL_SNI_REGEX,
  SFAPI_INTERNAL_SNI_REGEX,
  GLOBAL_PROXY_INTERNAL_SNI_REGEX,
}

local function should_block_request(host, regex)
  local match, err = re_match(host, regex, "joi")
  if err then
    ngx.log(ngx.ERR, "failed to process ", host, " with error: ", err)
    return true
  end

  if match then
    ngx.log(ngx.NOTICE, "ingress controller cannot process requests with ", host)
    return true
  end

  return false
end

local function should_block_by_sni()
  if ngx.var.https ~= "on" then
    return false
  end

  local sni, err = ssl.server_name()
  if err then
    ngx.log(ngx.ERR, "failed fetching sni to categorize request to the ingress controller: ", err)
    return true
  end

  for _, sni_regex in ipairs(SNI_TO_BLOCK_REGEX) do
    if should_block_request(sni, sni_regex) then
      return true
    end
  end

  return false
end

local function should_block_by_host_header()
  local host = ngx.var.http_host
  if not host then
    return false
  end

  for _, sni_regex in ipairs(SNI_TO_BLOCK_REGEX) do
    if should_block_request(host, sni_regex) then
      return true
    end
  end

  return false
end


local _M = {}

function _M.rewrite()
  if should_block_by_sni() or should_block_by_host_header() then
    ngx.exit(ngx.HTTP_FORBIDDEN)
    return
  end
end

return _M
