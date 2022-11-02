local string = string
local tonumber = tonumber

local _M = {}

-- Example input: processing;dur=26, db;dur=13
function _M.parse_server_timing_processing(value)
  local matched = string.match(value, "processing;dur=(%d*%.?%d*)")
  return tonumber(matched)
end

return _M
