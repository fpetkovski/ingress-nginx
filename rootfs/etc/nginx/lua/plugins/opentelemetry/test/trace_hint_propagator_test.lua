local context      = require("opentelemetry.context")
local propagator   = require("plugins.opentelemetry.trace_hint_propagator")
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

    it("injects shopify trace hint header", function()
        stub(ngx.req, "set_header")

        local context   = context.new()
        local hint_prop = propagator.new()

        local trace_id         = "0123456789abcdef0123456789abcdef"
        local span_id          = "89abcdef"
        local sampled          = 0
        local new_span_context = span_context.new(trace_id, span_id, sampled, tracestate.new({}), false)
        local new_ctx          = context:with_span_context(new_span_context)

        hint_prop:inject(new_ctx, ngx.req)

        assert.stub(ngx.req.set_header).was_called_with("x-shopify-trace-hint", "true")
    end)
end)

describe("extract", function()
    before_each(otel_global.set_context_storage({}))

    it("extracts the same context that was passed in", function()
        local trace_id         = "00000000000000000000000000000001"
        local span_id          = "00000001"
        local sampled          = 1
        local span_context = span_context.new(trace_id, span_id, sampled, "", false)

        local hint_prop = propagator.new()
        local new_span_context = hint_prop:extract(context:with_span_context(span_context), ngx.req).sp:context()
        assert.are.same(span_context.trace_id, new_span_context.trace_id)
        assert.are.same(span_context.trace_id, new_span_context.trace_id)
    end)
end)
