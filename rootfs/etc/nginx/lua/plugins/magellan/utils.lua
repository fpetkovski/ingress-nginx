local ngx    = ngx
local pairs  = pairs
local pcall  = pcall
local string = string
local type   = type
local json   = require("cjson")

local _M = {}

function _M.is_blank(str)
  return str == nil or string.len(str) == 0
end

function _M.optimistic_json_decode(value)
  -- value might be a json-encoded table or array, optimistically attempt to decode it
  if type(value) == 'string' then
    local first_character = string.sub(value, 1, 1)
    if first_character == '{' or first_character == '[' then
      local ok, decoded_value = pcall(json.decode, value)
      if ok then
        value = decoded_value
      else
        ngx.log(ngx.WARN, string.format("Optimistic JSON decode failed on value: %s", value))
      end
    end
  end

  -- Edge case: the cjson lib uses a lightweight userdata type to represent null/nil
  -- (i.e. cjson.null), so we need to convert these to plain Lua nil values
  if type(value) == 'table' then
    for nested_key in pairs(value) do
      if value[nested_key] == json.null then value[nested_key] = nil end
    end
  end

  return value
end

return _M
