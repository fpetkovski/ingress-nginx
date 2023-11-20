-- Much of this file was adapted from https://github.com/Shopify/nginx-routing-modules/
local error      = error
local ipairs     = ipairs
local ngx        = ngx
local pairs      = pairs
local pcall      = pcall
local re_gsub    = ngx.re.gsub
local string     = string
local string_len = string.len
local string_sub = string.sub
local type       = type

local json = require("cjson")

local _M = {}

-- For init-time checks that a dict is defined
function _M.assert_dict(dict_name)
  if not ngx.shared[dict_name] then
    local msg = "assert_dict failed: No shared dictionary named " .. dict_name .. " found."
    ngx.log(ngx.ERR, msg)
    error(msg)
  end
end

function _M.dig(data, ...)
  local ret = data
  for _, k in ipairs({...}) do
    if ret[k] then
      ret = ret[k]
    else
      return nil
    end
  end
  return ret
end

function _M.convert_header_name_to_var_name(header_name)
  local var_name = string.gsub(header_name, "-", "_")
  return "http_" .. string.lower(var_name)
end

function _M.get_request_header(header_name)
  return ngx.var[_M.convert_header_name_to_var_name(header_name)]
end

function _M.is_content_present_in_header(header_key, content)
  local header_value = _M.get_request_header(header_key)

  -- ngx.req.get_headers can return a string or a table
  -- https://openresty-reference.readthedocs.io/en/latest/Lua_Nginx_API/#ngxreqget_headers
  if type(header_value) == "string" and string.find(header_value, content) ~= nil then
    return true
  elseif type(header_value) == "table" then
    for _, value in ipairs(header_value) do
      if string.find(value, content) ~= nil then
        return true
      end
    end
  end
  return false
end

function _M.merge_tables_by_key(t1, t2)
  for k,v in pairs(t2) do
    t1[k] = v
  end
  return t1
end

function _M.normalize_uri_path(uri_path)
  return re_gsub(uri_path, "/(/)+", '/', 'jo')
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

function _M.split_pair(pair, seperator)
  local i = pair:find(seperator)
  if i == nil then
    return pair, nil
  else
    local name = pair:sub(1, i - 1)
    local value = pair:sub(i + 1, -1)
    return name, value
  end
end

function _M.startswith(str, start)
  return string_sub(str, 1, string_len(start)) == start
end

function _M.union_regexes(regexes, prefix, suffix)
  prefix = prefix or ""
  suffix = suffix or ""

  local result = prefix .. "("
  for idx,re in ipairs(regexes) do
    if idx == #regexes then
      result = result .. re .. ")" .. suffix
    else
      result = result .. re .. "|"
    end
  end

  return result
end

return _M
