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

local ERROR_PAGE_DIRECTORY = "/etc/nginx/lua/plugins/load_shedder/error-pages"
local ERROR_PAGE_JSON = "503.json"
local ERROR_PAGE_HTML = "503.html"

local error_page_content = {
  ERROR_PAGE_JSON = nil,
  ERROR_PAGE_HTML = nil,
}

for _, i in ipairs(error_page_content) do
  local h, err = io.open(ERROR_PAGE_DIRECTORY .. "/" .. i)
  if err ~= nil then
    ngx.log(ngx.ERR, string.format("Unable to open error page %s: %s", i, err))
    return
  end
  error_page_content[i] = h:read("*a")
  h:close()
end

local function static_errors()
  local accepts_json = shopify_utils.is_content_present_in_header("Accept", "application/json")
  local content

  if accepts_json then
    content = error_page_content[ERROR_PAGE_JSON]
  else
    content = error_page_content[ERROR_PAGE_HTML]
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
