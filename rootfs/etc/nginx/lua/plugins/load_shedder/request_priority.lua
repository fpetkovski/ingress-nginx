-- Request categorization
local ngx = ngx
local ipairs = ipairs

local statsd = require("plugins.statsd.main")
local shopify_utils = require("plugins.load_shedder.shopify_utils")
local util = require("util")

local magellan = require("plugins.magellan.main")
magellan.register("key_accounts")

local SFR_REVERSE_VERIFICATION_REQUEST = "X-Sfr-Reverse-Verification-Request"

local CHECKOUT_DOMAIN = "checkout.shopify.com"
local SHOP_APP_DOMAIN = "shop.app"
local SORTING_HAT_SHOP_ID_HEADER = "X-Sorting-Hat-ShopId"


local _M = {
  PRIORITIES = {
    LOW = "low",
    MEDIUM = "medium",
    HIGH = "high",
    UNSHEDDABLE = "unsheddable",
    UNKNOWN = "unknown"
  },

  RULES = {
    POS_UA = "pos_user_agent",
    KNOWN_BOT_UA = "known_bot_user_agent",
    GENGHIS_UA = "genghis_user_agent",
    PINGDOM_BOT_UA = "pingdom_user_agent",
    LOW_PRIORITY_URI = 'low_priority_uris',
    MED_PRIORITY_URI = 'medium_priority_uris',
    CHECKOUT_HOST = "checkout_host",
    CHECKOUT_URI_INFERENCE = "checkout_uri_inference",
    URI_INFERENCE = "uri_inference",
    SFR_VERIFICATION = "sfr_verification",
    OVERRIDDEN = "overridden",
    UNKNOWN = "unknown",
    KEY_ACCOUNT = "key_account",
  },

  SECTIONS = {
    ADMIN = "admin",
    ADMIN_API = "admin_api",
    API = "api",
    CART = "cart",
    CHECKOUT = "checkout",
    CHECKOUT_ONE = "checkout_one",
    SHOP_PAY_CHECKOUT_ONE = "shop_pay_checkout_one",
    STOREFRONT = "storefront",
    OTHER = "other",
  }
}

local ORDERED_PRIORITY_RE_MAP = {
  -- more specific prefixes should come first
  { regex = "^/services/internal",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.OTHER },
  { regex = "^/services",
    priority = _M.PRIORITIES.HIGH,        section = _M.SECTIONS.OTHER },
  { regex = "^/admin/api",
    priority = _M.PRIORITIES.MEDIUM,      section = _M.SECTIONS.ADMIN_API },
  { regex = "^/admin",
    priority = _M.PRIORITIES.MEDIUM,      section = _M.SECTIONS.ADMIN },
  { regex = "^/api",
    priority = _M.PRIORITIES.MEDIUM,      section = _M.SECTIONS.API },

  -- legacy /cart route ⬇️
  { regex = "^/checkout",
    priority = _M.PRIORITIES.HIGH,        section = _M.SECTIONS.CART },
  { regex = "^/cart/checkout",
    priority = _M.PRIORITIES.HIGH,        section = _M.SECTIONS.CART },

  { regex = "^/cart/\\d+:",
    priority = _M.PRIORITIES.HIGH,        section = _M.SECTIONS.CART },
  { regex = "^/cart",
    priority = _M.PRIORITIES.HIGH,        section = _M.SECTIONS.CART },
  { regex = "^/identity",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.OTHER },
  { regex = "^/([a-z]{2,3})(?:-[a-zA-Z]{4})?(?:-([a-zA-Z0-9]+))?",
    priority = _M.PRIORITIES.HIGH,        section = _M.SECTIONS.OTHER },
  { regex = "^/",
    priority = _M.PRIORITIES.HIGH,        section = _M.SECTIONS.OTHER },
}

local ORDERED_CHECKOUTS_RE_MAP = {
  { regex    = "^/admin/api/\\b(\\d{4}-\\d{2}|unstable|unversioned)\\b/merchant_checkouts",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/admin/merchant_checkouts/",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/api/checkouts",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/api/\\b(\\d{4}-\\d{2}|unstable|unversioned)\\b/checkout",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/checkpoint",
    priority = _M.PRIORITIES.UNSHEDDABLE, section  = _M.SECTIONS.CHECKOUT },
  { regex    = "^/queue/poll",
    priority = _M.PRIORITIES.UNSHEDDABLE, section  = _M.SECTIONS.CHECKOUT },
  { regex    = "^/throttle/queue",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/checkout/\\d+",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.SHOP_PAY_CHECKOUT_ONE },
  { regex    = "^/checkouts",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT_ONE },
  { regex    = "^/wallets",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/payments",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/services/ping/notify_integration",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/offsite/\\d+/callback",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/shopify_pay",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/\\d+/checkouts",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/\\d+/digital_wallets",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/\\d+/amazon_payments",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/\\d+/apple_pay",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/\\d+/orders",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/\\d+/policies",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/\\d+/invoices",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/\\d+/3ds",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/\\d+/checkoutapp",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/\\d+/order_payment",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex = "^/\\d+/sandbox",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "^/gift_cards",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
  { regex    = "/payment_handler",
    priority = _M.PRIORITIES.UNSHEDDABLE, section = _M.SECTIONS.CHECKOUT },
}

-- Known bots
-- Before adding anything here,
-- make sure it's not already here: https://radar.cloudflare.com/traffic/verified-bots
local KNOWN_BOT_UAS = {
  "; AwarioBot/",
  "; GeedoBot;",
  "; HTTrack",
  "; LinkpadBot/",
  "; LoadShedderUnitTests/",
  "; MJ12bot/",
  "; Mail.RU_Bot/",
  "; SEOkicks",
  "; SiteExplorer/",
  "; XoviBot/",
  "Remo/",
  "facebookexternalhit/",
  "omnisendbot",
  "serpstatbot/",
}

local KNOWN_BOT_UAS_RE = shopify_utils.union_regexes(KNOWN_BOT_UAS, ".*", ".*")

local GENGHIS_UAS = "Genghis/"

local POS_UAS_RE = "Shopify POS.*"

local PINGDOM_UA = "Pingdom.com_bot_version_"
local PINGDOM_URIS = {
  "/",
  "/services/ping",
  "/services/ping/shopify",
}
local PINGDOM_URIS_RES = shopify_utils.union_regexes(PINGDOM_URIS, "^", "$")

local MED_PRIORITY_RESOURCE_STRINGS = {
  "blogs",
  "pages",
  "search",
  "password",
}

local MED_PRIORITY_RESOURCES = shopify_utils.union_regexes(MED_PRIORITY_RESOURCE_STRINGS)

local MED_PRIORITY_URIS_RES = {
  "/("..MED_PRIORITY_RESOURCES..")/.*",        -- /blogs/foo
  "/("..MED_PRIORITY_RESOURCES..")(\\?.*)?",   -- /search?q=bar
  "/("..MED_PRIORITY_RESOURCES..")\\..*",      -- /pages.json?foo=bar
}
local MED_PRIORITY_URIS_RE = shopify_utils.union_regexes(MED_PRIORITY_URIS_RES, "^", "$")

local LOW_PRIORITY_URIS_RES = {
  "/sitemap_products_\\d+.xml(\\?.*)?",
  ".*/robots.txt(\\?.*)?",
}
local LOW_PRIORITY_URIS_RE = shopify_utils.union_regexes(LOW_PRIORITY_URIS_RES, "^", "$")

local KEY_ACCOUNT_URIS = {
  "/admin/api",
  "/admin",
  "/api",
}
local KEY_ACCOUNT_URIS_RES = shopify_utils.union_regexes(KEY_ACCOUNT_URIS, "^", "/.*")

local function is_checkout_host(host)
  return host == CHECKOUT_DOMAIN or host == SHOP_APP_DOMAIN
end

local function is_pos_user_agent()
  local http_user_agent = ngx.var.http_user_agent
  if not http_user_agent then return end
  return ngx.re.find(http_user_agent, POS_UAS_RE, "ijo")
end

local function is_known_bot_user_agent()
  local edge_client_bot = ngx.req.get_headers()["edge_client_bot"]
  if edge_client_bot == "true" then return true end

  local http_user_agent = ngx.var.http_user_agent
  if not http_user_agent then return end
  return ngx.re.find(http_user_agent, KNOWN_BOT_UAS_RE, "ijo")
end

local function is_genghis_user_agent()
  local http_user_agent = ngx.var.http_user_agent
  if not http_user_agent then return end
  return shopify_utils.startswith(http_user_agent, GENGHIS_UAS)
end

local function is_pingdom_bot_user_agent()
  local http_user_agent = ngx.var.http_user_agent
  if not http_user_agent then return end

  -- We rely on Cloudflare's verified bot heuristic to make sure attackers don't
  -- abuse the elevated priority of Pingdom's user-agent to DDoS our platform
  local edge_client_bot = ngx.req.get_headers()["edge_client_bot"]
  if edge_client_bot ~= "true" then
    return false
  end

  if not shopify_utils.startswith(http_user_agent, PINGDOM_UA) then
    return false
  end

  return ngx.re.find(ngx.var.uri, PINGDOM_URIS_RES, "ijo")
end

local function is_storefront_renderer_reverse_verification()
  return ngx.header[SFR_REVERSE_VERIFICATION_REQUEST] == '1'
end

local function is_medium_priority_uri()
  return ngx.re.find(ngx.var.uri, MED_PRIORITY_URIS_RE, "ijo")
end

local function is_low_priority_uri()
  return ngx.re.find(ngx.var.uri, LOW_PRIORITY_URIS_RE, "ijo")
end

local function is_key_account_request()
  local shop_id = shopify_utils.get_request_header(SORTING_HAT_SHOP_ID_HEADER)
  if not shop_id or not ngx.shared["key_accounts"]:get(shop_id) then return false end
  return ngx.re.find(ngx.var.uri, KEY_ACCOUNT_URIS_RES, "ijo")
end

local function infer_priority_from_uri(dict)
  local uri_path = shopify_utils.normalize_uri_path(ngx.var.uri)
  for _,config in ipairs(dict) do
    if ngx.re.find(uri_path, config.regex, "jo") then
      return config.priority
    end
  end
end

local function priority_and_rule_from_uri()
  local priority = infer_priority_from_uri(ORDERED_CHECKOUTS_RE_MAP)
  if priority then
    return priority, _M.RULES.CHECKOUT_URI_INFERENCE
  end

  priority = infer_priority_from_uri(ORDERED_PRIORITY_RE_MAP)
  if priority then
    return priority, _M.RULES.URI_INFERENCE
  end

  return _M.PRIORITIES.UNKNOWN, _M.RULES.UNKNOWN
end

function _M.get_priority_and_rule()
  ------------------
  -- User Agent Rules
  ------------------
  if is_pos_user_agent() then
    return _M.PRIORITIES.UNSHEDDABLE, _M.RULES.POS_UA
  end
  if is_known_bot_user_agent() then
    return _M.PRIORITIES.LOW, _M.RULES.KNOWN_BOT_UA
  end
  if is_genghis_user_agent() then
    return _M.PRIORITIES.LOW, _M.RULES.GENGHIS_UA
  end
  if is_pingdom_bot_user_agent() then
    return _M.PRIORITIES.HIGH, _M.RULES.PINGDOM_BOT_UA
  end

  -------------------------------------------
  -- StorefrontRenderer reverse verification
  -------------------------------------------
  if is_storefront_renderer_reverse_verification() then
    return _M.PRIORITIES.LOW, _M.RULES.SFR_VERIFICATION
  end

  -- TODO: add test
  if is_checkout_host(util.get_hostname()) then
    return _M.PRIORITIES.UNSHEDDABLE, _M.RULES.CHECKOUT_HOST
  end

  if is_key_account_request() then
    return _M.PRIORITIES.HIGH, _M.RULES.KEY_ACCOUNT
  end

  if is_medium_priority_uri() then
    return _M.PRIORITIES.MEDIUM, _M.RULES.MED_PRIORITY_URI
  end

  if is_low_priority_uri() then
    return _M.PRIORITIES.LOW, _M.RULES.LOW_PRIORITY_URI
  end

  return priority_and_rule_from_uri()
end

function _M.get_section()
  if is_checkout_host(util.get_hostname()) then
    return _M.SECTIONS.CHECKOUT
  end

  local uri_path = shopify_utils.normalize_uri_path(ngx.var.uri)
  for _, config in ipairs(ORDERED_CHECKOUTS_RE_MAP) do
    if ngx.re.find(uri_path, config.regex, "jo") then
      return config.section
    end
  end

  for _, config in ipairs(ORDERED_PRIORITY_RE_MAP) do
    if ngx.re.find(uri_path, config.regex, "jo") then
      return config.section
    end
  end

  return _M.SECTIONS.OTHER
end

function _M.get()
  if ngx.ctx.request_priority == nil then
    ngx.ctx.request_priority, ngx.ctx.request_rule = _M.get_priority_and_rule()
    statsd.increment(
      'request.priority.log',
      1,
      {priority=ngx.ctx.request_priority, matched_rule=ngx.ctx.request_rule}
    )
  end
  return ngx.ctx.request_priority, ngx.ctx.request_rule
end

return _M

