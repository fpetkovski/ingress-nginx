local setmetatable = setmetatable

local _M = {
}

local mt = {
    __index = _M
}

function _M.new()
    return setmetatable({}, mt)
end

------------------------------------------------------------------
-- Extract headers from nginx request
--
-- @param carrier (should be ngx.resp)
-- @param key HTTP header to get
-- @return value of HTTP header
------------------------------------------------------------------
function _M.get(carrier, key)
    return carrier.get_headers()[key]
end

return _M
