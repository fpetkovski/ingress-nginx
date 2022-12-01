local context      = require("opentelemetry.context")
local propagator   = require("plugins.opentelemetry.shopify_propagator")
local codec        = require("plugins.opentelemetry.shopify_utils")
local span_context = require("opentelemetry.trace.span_context")
local tracestate   = require("opentelemetry.trace.tracestate")
local match        = require("luassert.match")
local otel_global  = require("opentelemetry.global")

local function set_context_storage()
    otel_global.set_context_storage({})
end

-- This function shouldn't need to be so protective, but here we are.
local function reset_ngx_req()
    if not ngx.req.set_header or not ngx.req.get_headers then
        return
    end

    if (type(ngx.req.set_header) ~= "function" and ngx.req.set_header["revert"]) then
        ngx.req.set_header:revert()
    end

    if (type(ngx.req.get_headers) ~= "function" and ngx.req.get_headers["revert"]) then
        ngx.req.get_headers:revert()
    end
end

describe("inject", function()
    before_each(reset_ngx_req)
    before_each(set_context_storage)

    it("injects shopify trace headers with correct sampling decision", function()
        stub(ngx.req, "set_header")

        local context   = context.new()
        local shop_prop = propagator.new()

        local trace_id         = "0123456789abcdef0123456789abcdef"
        local span_id          = "89abcdef"
        local sampled          = 0
        local new_span_context = span_context.new(trace_id, span_id, sampled, tracestate.new({}), false)
        local new_ctx          = context:with_span_context(new_span_context)
        local expected_header  = string.format("%s/%s;o=0", trace_id,
            codec.hex_to_decimal_string(span_id))

        shop_prop:inject(new_ctx, ngx.req)

        local shop_headers = { "x-shopify-trace-context", "x-cloud-trace-context" }
        for i = 1, #shop_headers do
            assert.stub(ngx.req.set_header).was_called_with(shop_headers[i], expected_header)
        end
    end)

    it("does not blow up when casting span_id to decimal does not work", function()
        stub(ngx.req, "set_header")

        local context   = context.new()
        local shop_prop = propagator.new()

        local trace_id         = "0123456789abcdef0123456789abcdef"
        local span_id          = "gggggggggg" -- g is not a valid hexadecimal character
        local tracestate       = {}
        local sampled          = 0
        local new_span_context = span_context.new(trace_id, span_id, sampled, tracestate, false)
        local new_ctx          = context:with_span_context(new_span_context)

        shop_prop:inject(new_ctx, ngx.req)

        local shop_headers = { "x-shopify-trace-context", "x-cloud-trace-context" }
        for i = 1, #shop_headers do
            assert.stub(ngx.req.set_header).was_not_called_with(shop_headers[i], match._)
        end
    end)

    it("does not inject invalid spans", function()
        stub(ngx.req, "set_header")
        local context   = context.new()
        local shop_prop = propagator.new()

        local trace_id         = "00000000000000000000000000000000"
        local span_id          = "00000000"
        local tracestate       = {}
        local sampled          = 0
        local new_span_context = span_context.new(trace_id, span_id, sampled, tracestate, false)
        local new_ctx          = context:with_span_context(new_span_context)

        shop_prop:inject(new_ctx, ngx.req)

        local shop_headers = { "x-shopify-trace-context", "x-cloud-trace-context" }
        for i = 1, #shop_headers do
            assert.stub(ngx.req.set_header).was_not_called_with(shop_headers[i], match._)
        end
    end)

    it("propagates tracestate", function()
        stub(ngx.req, "set_header")
        local context   = context.new()
        local shop_prop = propagator.new()

        local trace_id         = "00000000000000000000000000000001"
        local span_id          = "00000001"
        local tracestate       = tracestate.parse_tracestate("foo=bar,baz=bat")
        local sampled          = 0
        local new_span_context = span_context.new(trace_id, span_id, sampled, tracestate, false)
        local new_ctx          = context:with_span_context(new_span_context)
        shop_prop:inject(new_ctx, ngx.req)
        assert.stub(ngx.req.set_header).was_called_with("tracestate", tracestate:as_string())
    end)
end)

describe("extract", function()
    before_each(otel_global.set_context_storage({}))

    it("extracts well-formed shopify trace headers when BOTH x-shopify-trace-context and x-cloud-trace-context are present"
        ,
        function()
            stub(ngx.req, "get_headers", function()
                return {
                    ["x-shopify-trace-context"] = "0123456789abcdef0123456789abcdef/192839324957267370;o=1",
                    ["x-cloud-trace-context"] = "0123456789abcdef0123456789abcdef/192839324957267370;o=1"
                }
            end)
            local shop_prop = propagator.new()
            local context   = context.new()
            local trace_id  = "0123456789abcdef0123456789abcdef"
            local span_id   = "192839324957267370"
            local span_ctx  = shop_prop:extract(context, ngx.req).sp:context()
            assert.are.same(span_ctx.trace_id, trace_id)
            assert.are.same(span_ctx.span_id, codec.decimal_to_hex_string(span_id))
            assert.is_true(span_ctx:is_sampled())
        end)

    it("does not extract well-formed shopify trace headers when just one trace header is present", function()
        stub(ngx.req, "get_headers", function()
            return {
                ["x-cloud-trace-context"] = "0123456789abcdef0123456789abcdef/192839324957267370;o=0"
            }
        end)
        local shop_prop = propagator.new()
        local context   = context.new()
        local trace_id  = "0123456789abcdef0123456789abcdef"
        local span_id   = "192839324957267370"
        local span_ctx  = shop_prop:extract(context, ngx.req).sp:context()
        assert.are_not.same(span_ctx.trace_id, trace_id)
        assert.are_not.same(span_ctx.span_id, codec.decimal_to_hex_string(span_id))
    end)

    it("does not set trace_id or span_id in context when header span id is invalid", function()
        stub(ngx.req, "get_headers", function()
            return {
                ["x-cloud-trace-context"] = "0123456789abcdef0123456789abcdef/1000092098230498230498230498230948230948;o=0"
            }
        end)
        local shop_prop = propagator.new()
        local context   = context.new()
        local span_ctx  = shop_prop:extract(context, ngx.req).sp:context()
        assert.is_nil(span_ctx.trace_id)
        assert.is_nil(span_ctx.span_id)
    end)

    it("does not extract shopify trace headers when context's trace id is invalid", function()
        -- g is not a valid hexadecimal character, so this is invalid
        stub(ngx.req, "get_headers", function()
            return {
                ["x-cloud-trace-context"] = "ggggg/00000001;o=0"
            }
        end)
        local shop_prop = propagator.new()
        local context   = context.new()
        local span_ctx  = shop_prop:extract(context, ngx.req).sp:context()
        assert.is_nil(span_ctx.trace_id)
        assert.is_nil(span_ctx.span_id)
    end)

    it("does not blow up when span_id is not a base 10 number", function()
        -- g is not a valid hexadecimal character, so this is invalid
        stub(ngx.req, "get_headers", function()
            return {
                ["x-cloud-trace-context"] = "aaaaaaaaaaaaaaaa/invalid;o=0"
            }
        end)
        local shop_prop = propagator.new()
        local context   = context.new()
        local span_ctx  = shop_prop:extract(context, ngx.req).sp:context()
        assert.is_nil(span_ctx.trace_id)
        assert.is_nil(span_ctx.span_id)
    end)


    it("marks span as unsampled when sampled flag is set to 0", function()
        stub(ngx.req, "get_headers", function()
            return {
                ["x-shopify-trace-context"] = "0123456789abcdef0123456789abcdef/192839324957267370;o=0",
                ["x-cloud-trace-context"] = "0123456789abcdef0123456789abcdef/192839324957267370;o=0"
            }
        end)
        local shop_prop = propagator.new()
        local context   = context.new()
        local trace_id  = "0123456789abcdef0123456789abcdef"
        local span_id   = "192839324957267370"
        local span_ctx  = shop_prop:extract(context, ngx.req).sp:context()
        assert.are.same(span_ctx.trace_id, trace_id)
        assert.are.same(span_ctx.span_id, codec.decimal_to_hex_string(span_id))
        assert.is_false(span_ctx:is_sampled())
    end)

    it("does not extract invalid traces and spans", function()
        stub(ngx.req, "get_headers", function()
            return {
                ["x-shopify-trace-context"] = "00000000000000000000000000000000/0000000000000000;o=0",
                ["x-cloud-trace-context"] = "00000000000000000000000000000000/0000000000000000;o=0"
            }
        end)
        local shop_prop = propagator.new()
        local context   = context.new()
        local span_ctx  = shop_prop:extract(context, ngx.req).sp:context()
        assert.is_nil(span_ctx.trace_id)
        assert.is_nil(span_ctx.span_id)
    end)

    it("extracts tracestate", function()
        stub(ngx.req, "get_headers", function()
            return {
                ["x-shopify-trace-context"] = "00000000000000000000000000000001/0000000000000001;o=0",
                ["x-cloud-trace-context"] = "00000000000000000000000000000001/0000000000000001;o=0",
                ["tracestate"] = "foo=bar,baz=bat"
            }
        end)
        local shop_prop = propagator.new()
        local context   = context.new()
        local span_ctx  = shop_prop:extract(context, ngx.req).sp:context()
        assert.are.same(span_ctx.trace_state:as_string(), "foo=bar,baz=bat")
    end)
end)
