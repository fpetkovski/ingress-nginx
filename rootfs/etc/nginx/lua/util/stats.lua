local math = math
local ipairs = ipairs

local _M = {}

function _M.mean(values)
  if #values == 0 then
    return 0
  end

  local sum = 0

  for _,v in ipairs(values) do
    sum = sum + v
  end

  return (sum / #values)
end

function _M.stddev(values, offset_to_mean)
  if #values == 0 then
    return 0
  end

  local mean = _M.mean(values)
  local sum = 0
  local difference

  for _,v in ipairs(values) do
    difference = v - mean
    sum = sum + (difference * difference)
  end

  local result = math.sqrt(sum / #values)

  if offset_to_mean then
    -- We support this parameter so that a caller does not have to recalculate the mean
    -- if this is what they are trying to determine
    result = mean + (result * offset_to_mean)
  end

  return result
end

return _M
