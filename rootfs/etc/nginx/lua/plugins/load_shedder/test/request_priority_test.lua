package.path = "./rootfs/etc/nginx/lua/plugins/load_shedder/test/?.lua;./rootfs/etc/nginx/lua/plugins/load_shedder/test/helpers/?.lua;" .. package.path
require("helpers.init")

local busted = require('busted')
local assert = require('luassert')
local request = require("plugins.load_shedder.request_priority")

local now
function stub_time()
  now = 2000
  register_stub(ngx, 'now', function()
    return now / 1000
  end)
end

function advance_time(delta_ms)
  now = now + delta_ms
end

local function assert_get_matches(correct_priority, correct_rule)
  local request_priority, request_rule = request.get_priority_and_rule()
  local msg = string.format(
    "Expected request to have priority=%s,rule=%s but was priority=%s,rule=%s\nngx.var.uri=%s, ngx.var.http_user_agent=%s",
    correct_priority, correct_rule, request_priority, request_rule, ngx.var.uri, ngx.var.http_user_agent
  )
  assert.are.equal(request_priority, correct_priority, msg)
  assert.are.equal(request_rule, correct_rule, msg)
end

local function setup()
  ngx.reset()
  reset_stubs()
  stub_time()
end

describe("plugins.load_shedder.request_priority", function()

  before_each(function()
    setup()
  end)

  it("unknown_request", function()
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)
    ngx.var.http_user_agent = ""
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)
  end)

  it("low_request_for_bot_user_agents", function()
    ngx.var.http_user_agent = "This-Is_ ; LoadShedderUnitTests//1.1.1"
    assert_get_matches(request.PRIORITIES.LOW, request.RULES.KNOWN_BOT_UA)

    ngx.var.http_user_agent = "Mozilla"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)
  end)

  it("low_request_for_bot_user_agents", function()
    ngx.var.http_user_agent = "Genghis/run_uuid='someflow.lua' worker_id='someworker' exec_id='10'"
    assert_get_matches(request.PRIORITIES.LOW, request.RULES.GENGHIS_UA)

    ngx.var.http_user_agent = "Mozilla"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)
  end)

  it("low_request_for_storefront_renderer_reverse_verification", function()
    ngx.header["X-Sfr-Reverse-Verification-Request"] = '1'
    assert_get_matches(request.PRIORITIES.LOW, request.RULES.SFR_VERIFICATION)

    ngx.header["X-Sfr-Reverse-Verification-Request"] = '0'
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)
  end)

  it("shopify_POS_has_POS_rule", function()
    ngx.var.http_user_agent = "Shopify POS/5.0.5 (iPad; iOS 11.4; Scale/2.00)"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.POS_UA)
  end)

  it("sheddable_resouces_are_medium_priority_uri", function()
    ngx.var.uri = "/blogs/size-charts/dresses?view=content"
    assert_get_matches(request.PRIORITIES.MEDIUM, request.RULES.MED_PRIORITY_URI)

    ngx.var.uri = "/blogs/news"
    assert_get_matches(request.PRIORITIES.MEDIUM, request.RULES.MED_PRIORITY_URI)

    ngx.var.uri = "/blogs"
    assert_get_matches(request.PRIORITIES.MEDIUM, request.RULES.MED_PRIORITY_URI)

    ngx.var.uri = "/pages.json?limit=1"
    assert_get_matches(request.PRIORITIES.MEDIUM, request.RULES.MED_PRIORITY_URI)

    ngx.var.uri = "/search.js?view=fhsprod-labelme-json&q=handle:%22our-generation-morgan-foal"
    assert_get_matches(request.PRIORITIES.MEDIUM, request.RULES.MED_PRIORITY_URI)
  end)

  it("sitemap_and_products_endpoints_are_low_priority_uri", function()
    ngx.var.uri = "/sitemap_products_1.xml"
    assert_get_matches(request.PRIORITIES.LOW, request.RULES.LOW_PRIORITY_URI)

    ngx.var.uri = "/sitemap_products_42.xml?foo=bar"
    assert_get_matches(request.PRIORITIES.LOW, request.RULES.LOW_PRIORITY_URI)

    ngx.var.uri = "/sitemap.xml"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)

  end)

  it("robots_txt_endpoints_are_low_priority", function()

    ngx.var.uri = "/robots.txt"
    assert_get_matches(request.PRIORITIES.LOW, request.RULES.LOW_PRIORITY_URI)

    ngx.var.uri = "/collections/harry-barker-home/robots.txt"
    assert_get_matches(request.PRIORITIES.LOW, request.RULES.LOW_PRIORITY_URI)

    ngx.var.uri = "/robots.txt?1541529844561"
    assert_get_matches(request.PRIORITIES.LOW, request.RULES.LOW_PRIORITY_URI)
  end)

  it("checkout_paths_have_unsheddable_priority", function()
    ngx.var.uri = "/2939442/checkouts/uuid-uuid-uuid-uuid/thank-you"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/2939442/checkouts"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/2939442/checkouts?foo=bar"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/2939442/orders/uuid-uuid-uuid-uuid/thank-you"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/2939442/orders"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/2939442/orders?foo=bar"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/api/checkouts.json"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/api/checkouts/005ab0ec362c092a72a3b7b664eb47f2/payments.json"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/api/checkouts/39e6befdac1a29e7909762a4100c4ee4.json?token=70c2741de85b022a37c36a86553b9944"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/wallets/checkouts.json"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/wallets/checkouts?format=json"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/wallets/checkouts/a8724a52a95397c6d6f98fbcc5b24b99.json"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/checkpoint"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/checkpoint?foo=bar"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/queue/poll"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/throttle/queue"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    -- used for third party integrations in checkout
    ngx.var.uri = "/2939277/sandbox/autocomplete_service?locale=en"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)

    ngx.var.uri = "/2939277/sandbox/google_maps?locale=en"
    assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)
  end)

  it("cart_priorities", function()
    ngx.var.uri = "/cart"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)

    ngx.var.uri = "/cart.js"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)

    ngx.var.uri = "/cart/add"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)

    ngx.var.uri = "/cart/add.js"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)

    ngx.var.uri = "/cart/change?line=1&quantity=0"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)

    ngx.var.uri = "/cart/change.js"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)

    ngx.var.uri = "/cart/clear"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)

    ngx.var.uri = "/cart/update.js"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)

    ngx.var.uri = "/cart?view=ajax"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)

    -- permalinks
    ngx.var.uri = "/cart/43242:5"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)

    ngx.var.uri = "/cart/2942460854298:1?checkout[reduction_code]=discountcode"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)

    ngx.var.uri = "/cart/checkout"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)

    -- legacy paths that translate to /cart
    ngx.var.uri = "/checkout"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)

    ngx.var.uri = "/checkout?foo=bar"
    assert_get_matches(request.PRIORITIES.HIGH, request.RULES.URI_INFERENCE)
  end)

  it("uri_inference", function()
    tests = {
      ["/"                                                                                                 ] = request.PRIORITIES.HIGH,
      ["/.well-known/apple-app-site-association"                                                           ] = request.PRIORITIES.HIGH,
      ["/a/smpl/wishlist_index/ajaxAdd"                                                                    ] = request.PRIORITIES.HIGH,
      ["/account"                                                                                          ] = request.PRIORITIES.HIGH,
      ["/account/login"                                                                                    ] = request.PRIORITIES.HIGH,
      ["/apple-app-site-association"                                                                       ] = request.PRIORITIES.HIGH,
      ["/apple-touch-icon.png"                                                                             ] = request.PRIORITIES.HIGH,
      ["/apps/bouncex/2889/bx-manifest.json"                                                               ] = request.PRIORITIES.HIGH,
      ["/apps/customer"                                                                                    ] = request.PRIORITIES.HIGH,
      ["/apps/pushowl/sdks/service-worker.js?v1.6"                                                         ] = request.PRIORITIES.HIGH,
      ["/collections/all-tops"                                                                             ] = request.PRIORITIES.HIGH,
      ["/collections/all?view=curve.json"                                                                  ] = request.PRIORITIES.HIGH,
      ["/collections/all?view=men.json"                                                                    ] = request.PRIORITIES.HIGH,
      ["/collections/all?view=women.json"                                                                  ] = request.PRIORITIES.HIGH,
      ["/collections/dresses"                                                                              ] = request.PRIORITIES.HIGH,
      ["/collections/dresses?page=2"                                                                       ] = request.PRIORITIES.HIGH,
      ["/discount/Labor30"                                                                                 ] = request.PRIORITIES.HIGH,
      ["/en-CA/collections/dresses?page=2"                                                                 ] = request.PRIORITIES.HIGH,
      ["/zh-Hant/collections/dresses?page=2"                                                               ] = request.PRIORITIES.HIGH,
      ["/zh-Hant-TW/collections/dresses?page=2"                                                            ] = request.PRIORITIES.HIGH,
      ["/favicon.ico"                                                                                      ] = request.PRIORITIES.HIGH,
      ["/products/a-perfect-match-trouser-pants-white.json"                                                ] = request.PRIORITIES.HIGH,
      ["/services/payments/2939277/accounts/474225/events"                                                 ] = request.PRIORITIES.HIGH,
    }

    for uri,expected_priority in pairs(tests) do
      setup()
      ngx.var.uri = uri
      assert.are.equal(request.get_section(), request.SECTIONS.OTHER)
      assert_get_matches(expected_priority, request.RULES.URI_INFERENCE)
    end
  end)

  it("admin_api_uri_inference", function()
    tests = {
      ["/admin/inventory_levels/adjust.json"                                                               ] = request.PRIORITIES.MEDIUM,
      ["/admin/shop.json"                                                                                  ] = request.PRIORITIES.MEDIUM,
    }

    for uri,expected_priority in pairs(tests) do
      setup()
      ngx.var.uri = uri
      assert.are.equal(request.get_section(), request.SECTIONS.ADMIN)
      assert_get_matches(expected_priority, request.RULES.URI_INFERENCE)
    end
  end)

  it("admin_api_uri_inference", function()
    tests = {
      ["/admin/api/graphql.json"                                                                           ] = request.PRIORITIES.MEDIUM,
    }

    for uri,expected_priority in pairs(tests) do
      setup()
      ngx.var.uri = uri
      assert.are.equal(request.get_section(), request.SECTIONS.ADMIN_API)
      assert_get_matches(expected_priority, request.RULES.URI_INFERENCE)
    end
  end)

  it("api_uri_inference", function()
    tests = {
      ["/////api/graphql"                                                                                  ] = request.PRIORITIES.MEDIUM,
      ["/api/graphql"                                                                                      ] = request.PRIORITIES.MEDIUM,
    }

    for uri,expected_priority in pairs(tests) do
      setup()
      ngx.var.uri = uri
      assert.are.equal(request.get_section(), request.SECTIONS.API)
      assert_get_matches(expected_priority, request.RULES.URI_INFERENCE)
    end
  end)

  it("cart_uri_inference", function()
    tests = {
      ["/cart"                                                                                             ] = request.PRIORITIES.HIGH,
      ["/cart.js"                                                                                          ] = request.PRIORITIES.HIGH,
      ["/cart/2942460854298:1?checkout[reduction_code]=discountcode"                                       ] = request.PRIORITIES.HIGH,
      ["/cart/add"                                                                                         ] = request.PRIORITIES.HIGH,
      ["/cart/add.js"                                                                                      ] = request.PRIORITIES.HIGH,
      ["/cart/change?line=1&quantity=0"                                                                    ] = request.PRIORITIES.HIGH,
      ["/cart/change.js"                                                                                   ] = request.PRIORITIES.HIGH,
      ["/cart/checkout"                                                                                    ] = request.PRIORITIES.HIGH,
      ["/cart/clear"                                                                                       ] = request.PRIORITIES.HIGH,
      ["/cart/update.js"                                                                                   ] = request.PRIORITIES.HIGH,
      ["/cart?view=ajax"                                                                                   ] = request.PRIORITIES.HIGH,
      -- legacy /cart route ⬇️
      ["/checkout"                                                                                         ] = request.PRIORITIES.HIGH,
    }

    for uri,expected_priority in pairs(tests) do
      setup()
      ngx.var.uri = uri
      assert.are.equal(request.get_section(), request.SECTIONS.CART)
      assert_get_matches(expected_priority, request.RULES.URI_INFERENCE)
    end
  end)

  it("checkout_uri_inference", function()
    tests = {
      "//api/checkouts/76254437863b189e85483f75744a6024.json"                                            ,
      "/2939277/digital_wallets/dialog"                                                                  ,
      "/2939277/orders/undefined//cdn.shopify.com/s/assets/flags/abc.svg"                                ,
      "/2939277/orders/undefined/cdn.shopify.com/s/assets/flags/abc.svg"                                 ,
      "/2939277/sandbox/autocomplete_service?locale=en"                                                  ,
      "/2939277/sandbox/google_maps?locale=en"                                                           ,
      "/3986849/3ds/callback?payment_intent=abc&payment_intent_client_secret=[FILTERED]&source_type=card",
      "/admin/api/2019-07/merchant_checkouts"                                                            ,
      "/admin/merchant_checkouts/e879d728182badcdb63981fc4b8f53b0/processing"                            ,
      "/api/2019-07/checkouts/4bd1bd8f95d8a930bda9acab484d1f37/payments/1305433342076.json"              ,
      "/api/unstable/checkouts/e9f02a502612f9ee16833d4278776969/payments/988906160201.json"              ,
      "/payments/config?currency=USD"                                                                    ,
      "/services/ping/notify_integration"                                                                ,
      "/services/ping/notify_integration/quadpay/2939277"                                                ,
      "/offsite/2939277/callback"                                                                        ,
      "/shopify_pay/checkout_customizations.json"                                                        ,
      "/shopify_pay/checkout_customizations.json"                                                        ,
      "/wallets/checkouts.json"                                                                          ,
      "/wallets/checkouts/7174155dab9b9010a1b8ead69bca9f54.json"                                         ,
      "/checkpoint"                                                                                      ,
    }

    for _, uri in ipairs(tests) do
      setup()
      ngx.var.uri = uri
      assert.are.equal(request.get_section(), request.SECTIONS.CHECKOUT, uri)
      assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)
    end
  end)

  it("checkout_one_uri_inference", function()
    tests = {
      "/checkouts"                                                                                       ,
      "/checkouts/unstable/graphql"                                                                      ,
      "/checkouts/graphql"                                                                               ,
      -- The authoritative list of source types is available in Checkouts::One::Web::SourceType
      -- https://github.com/Shopify/shopify/blob/221b61617452a91a8ebef8d8d758521fa2421729/components/checkouts/one/app/models/checkouts/one/web/source_type.rb#L50-L61
      "/checkouts/c/dc857bb83e18522db6a95e2e525aadfc"                                                    ,
      "/checkouts/os/dc857bb83e18522db6a95e2e525aadfc"                                                   ,
      "/checkouts/co/dc857bb83e18522db6a95e2e525aadfc"                                                   ,
      "/checkouts/o/dc857bb83e18522db6a95e2e525aadfc"                                                    ,
      "/checkouts/ac/dc857bb83e18522db6a95e2e525aadfc"                                                   ,
      "/checkouts/cn/dc857bb83e18522db6a95e2e525aadfc"                                                   ,
      "/checkouts/do/dc857bb83e18522db6a95e2e525aadfc"                                                   ,
      "/checkouts/md/dc857bb83e18522db6a95e2e525aadfc"                                                   ,
      "/checkouts/bin/dc857bb83e18522db6a95e2e525aadfc"                                                  ,
      "/checkouts/sh/dc857bb83e18522db6a95e2e525aadfc"                                                   ,
      "/checkouts/sim/dc857bb83e18522db6a95e2e525aadfc"                                                  ,
      "/checkouts/e/dc857bb83e18522db6a95e2e525aadfc"                                                    ,
    }

    for _, uri in ipairs(tests) do
      setup()
      ngx.var.uri = uri
      assert.are.equal(request.get_section(), request.SECTIONS.CHECKOUT_ONE, uri)
      assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)
    end
  end)

  it("shop_pay_checkout_one_uri_inference", function()
    tests = {
      -- Shop Pay logged-in requests are served by C1 controller
      "/checkout/62660247574/c/dc857bb83e18522db6a95e2e525aadfc"                                         ,
    }

    for _, uri in ipairs(tests) do
      setup()
      ngx.var.uri = uri
      assert.are.equal(request.get_section(), request.SECTIONS.SHOP_PAY_CHECKOUT_ONE, uri)
      assert_get_matches(request.PRIORITIES.UNSHEDDABLE, request.RULES.CHECKOUT_URI_INFERENCE)
    end
  end)

end)
