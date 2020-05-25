local _M = {}

local function durations(rawheader)
  local durationTable = {}
  if type(rawheader) ~= "string" then
    return durationTable
  end

  for word in string.gmatch(rawheader, '([^,]+)') do
    local name = string.match(word, "([%w_-]+);?")
    local matched = string.match(word, "dur[%s]?=[%s]?(%d*.?%d*)")
    durationTable[name] = tonumber(matched)
  end

  return durationTable
end

function _M.duration(rawheader, key)
  local table = durations(rawheader)
  if not table or type(table) ~= "table" or table[key] == nil then
    return 0, "not a valid key or table"
  end
  return table[key]
end

return _M
