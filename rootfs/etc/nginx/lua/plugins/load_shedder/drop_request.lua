-- It's important that we return the right status under load. For example, the
-- Googlebot expects a 503 when there's server downtime or overload
--
-- (https://webmasters.googleblog.com/2011/01/how-to-deal-with-planned-site-downtime.html)
--
--
-- The Retry-After response-header field can be used with a 503 (Service
-- Unavailable) response to indicate how long the service is expected to
-- be unavailable to the requesting client
--
-- (https://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.37)
local math = math
local ngx = ngx
local tostring = tostring

local DROPPED_REQUEST_EXIT_CODE = ngx.HTTP_SERVICE_UNAVAILABLE
local RETRY_AFTER_HEADER = "Retry-After"

local function drop_request()
  ngx.header[RETRY_AFTER_HEADER] = tostring(60 + math.floor(math.random() * 120))
  ngx.exit(DROPPED_REQUEST_EXIT_CODE)
end

return drop_request
