local ffi = require("ffi")
local tonumber = tonumber
local MICROSECONDS = 1000000

local _M = {}

-- define timeval if not already defined
if not pcall(ffi.typeof, "struct timeval") then
  ffi.cdef[[
    typedef long time_t;

    typedef struct timeval {
      time_t tv_sec;
      time_t tv_usec;
    } timeval;

    int gettimeofday(struct timeval* t, void* tzp);
  ]]
end

local gettimeofday_struct = ffi.new("timeval")

function _M.gettimeofday()
  ffi.C.gettimeofday(gettimeofday_struct, nil)
  return tonumber(gettimeofday_struct.tv_sec) * MICROSECONDS + tonumber(gettimeofday_struct.tv_usec)
end

return _M
