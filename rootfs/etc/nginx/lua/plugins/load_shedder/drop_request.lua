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
local io = io
local ipairs = ipairs
local math = math
local ngx = ngx
local shopify_utils = require("plugins.load_shedder.shopify_utils")
local string = string
local tostring = tostring

local DROPPED_REQUEST_EXIT_CODE = ngx.HTTP_SERVICE_UNAVAILABLE
local RETRY_AFTER_HEADER = "Retry-After"

local function static_errors()
  local accepts_json = shopify_utils.is_content_present_in_header("Accept", "application/json")
  local content

  local ERROR_PAGE = "/etc/nginx/lua/plugins/load_shedder/error-pages/503"
  local error_page_extensions = {"json","html"}
  local error_page_content = {}

  for _, value in ipairs(error_page_extensions) do
    local file, err = io.open(ERROR_PAGE .. "." .. value)
    if err ~= nil then
      ngx.log(ngx.ERR, string.format("Unable to open error page %s: %s", value, err))
      return
    end
    io.input(file)
    error_page_content[value] = io.read("*a")
    io.close(file)
  end

  if accepts_json then
    content = error_page_content["json"]
  else
    content = error_page_content["html"]
  end

  if content then
    ngx.status = DROPPED_REQUEST_EXIT_CODE
    ngx.header.content_type = accepts_json and 'application/json' or 'text/html'
    ngx.print(content)
  else
    ngx.log(
      ngx.WARN,
      string.format("unable to find error page for %d status", DROPPED_REQUEST_EXIT_CODE)
    )
  end
end

local function drop_request()
  ngx.header[RETRY_AFTER_HEADER] = tostring(60 + math.floor(math.random() * 120))
  static_errors()
  ngx.exit(DROPPED_REQUEST_EXIT_CODE)
end

return drop_request
