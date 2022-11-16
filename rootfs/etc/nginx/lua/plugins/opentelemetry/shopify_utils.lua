-- Much of this file was adapted from https://github.com/Shopify/nginx-routing-modules/pull/2745/files
local ffi      = require('ffi')
local tostring = tostring
local ngx      = ngx
local pairs    = pairs
local string   = string
local table    = table
local tonumber = tonumber

ffi.cdef [[
  int sscanf(const char*, const char *, ...);
  int sprintf(char *, const char *, ...);

  typedef union {
    uint64_t raw;
    struct {
      uint32_t low;
      uint32_t high;
    } decoded;
  } number_conversion;
]]

local sscanf = ffi.C.sscanf
local sprintf = ffi.C.sprintf
local ffi_new = ffi.new
local ffi_string = ffi.string

local GKE_HEADER_KEY = 'x-cloud-trace-context'
local SHOPIFY_HEADER_KEY = 'x-shopify-trace-context'
-- This is in compliance with https://github.com/Shopify/shopify-tracing/blob/ed75b0f288d2c18b4174fd4d79a84a9f764c6521/lib/shopify/tracing/formats/format_helper.rb#L8

local SHOPIFY_HEADER_REGEXP = '^(\\w{32})(/(\\d+))?(;o=(\\d))?'

local _M = {}

-- A collection of functions to convert between B3 and Stackdriver (shopify flavor)
-- propagation format.
local function decimal_to_hex_string(input)
  local bytes = ffi_new("number_conversion")

  local z = sscanf(input, "%llu", bytes)
  if z <= 0 then
    return nil, "sscanf(" .. tostring(input) .. ", ...) returned " .. tostring(z)
  end

  return string.format("%08x%08x", bytes.decoded.high, bytes.decoded.low), nil
end

_M.decimal_to_hex_string = decimal_to_hex_string

local function hex_to_decimal_string(input)
  if input:len() <= 8 then
    return string.format("%d", tonumber(input, 16)), nil
  end

  local bytes = ffi_new("number_conversion")

  local low = tonumber(input:sub(9), 16)
  local high = tonumber(input:sub(1, 8), 16)
  if low == nil or high == nil then
    return nil, "input " .. tostring(input) .. " is an invalid hex"
  end

  bytes.decoded.low = low
  bytes.decoded.high = high

  local number = ffi_new("char[32]", 0)
  local z = sprintf(number, "%llu", bytes.raw)
  if z <= 0 then
    return nil, "sprintf(" .. tostring(number) .. ", ...) returned " .. tostring(z)
  end

  return ffi_string(number, z), nil
end

_M.hex_to_decimal_string = hex_to_decimal_string

-- This is following https://github.com/Shopify/shopify-tracing/blob/77e8ff79bd25580336ed92c62b7aa57e2795206b/lib/shopify/tracing/formats/http_format.rb#L15.
-- The trust model and header prioritization are taken from that implementation.
function _M.extract()
  local headers = ngx.req.get_headers()
  if not headers[GKE_HEADER_KEY] or not headers[SHOPIFY_HEADER_KEY] then
    -- If not both of these headers are present, we then don't trust any.
    return nil, nil
  end

  local captures, err = ngx.re.match(headers[GKE_HEADER_KEY], SHOPIFY_HEADER_REGEXP)
  if err then
    return nil, err
  end
  if not captures then
    return nil, nil
  end

  local trace_id = captures[1]
  local raw_span_id = captures[3]
  local raw_sampled = captures[5]

  local span_id
  if raw_span_id then
    span_id, err = decimal_to_hex_string(raw_span_id)
    if err then
      return nil, err
    end
  end

  local sampled
  if raw_sampled == '1' then
    sampled = 1
  elseif raw_sampled == '0' then
    sampled = 0
  elseif not raw_sampled and trace_id then
    -- Normally this should be considered a malformed header value
    -- but we are being liberal here and accepting it. We assume the trace is
    -- sampled in this case.
    sampled = 1
  end

  return {
    trace_id = trace_id,
    span_id = span_id,
    sampled = sampled,
  }, nil
end

function _M.shallow_copy(t)
  local copy = {}
  for key, value in pairs(t) do
    copy[key] = value
  end
  return copy
end

-------------------------------------------------------------------------------
-- Turn w3c baggage-style string (key1=value1,key2=value2) into a table.
-- TODO(plantfansam): cast values to appropriate type
--
-- @param str w3c baggage-style string
-- @return table containing key/value pairs from w3c baggage-style string
--------------------------------------------------------------------------------
function _M.w3c_baggage_to_table(str)
  local t = {}
  for k, v in string.gmatch(str, "(%w+)=(%w+)") do
    t[k] = v
  end
  return t
end

-- Remove once https://github.com/yangxikun/opentelemetry-lua/pull/46 is released
function _M.trim(s)
  return s:match '^%s*(.*%S)' or ''
end

-- Remove once https://github.com/yangxikun/opentelemetry-lua/pull/46 is released
function _M.split(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
    table.insert(t, str)
  end
  return t
end

return _M
