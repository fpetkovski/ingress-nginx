local ngx = ngx
local tonumber = tonumber

local _M = {}

function _M.rewrite()
  -- BLOCK smuggle bug attack
  local body_length = tonumber(ngx.var.request_length)
  local request_method = ngx.var.request_method

  -- block request if body length > 0 and request method is GET OPTION or HEAD
  if body_length > 0 and (request_method == ngx.HTTP_GET or request_method == ngx.HTTP_OPTIONS
  or request_method == ngx.HTTP_HEAD) then
    ngx.exit(ngx.HTTP_FORBIDDEN)
    return
  end
  -- BLOCK smuggle bug attack end
end

return _M
