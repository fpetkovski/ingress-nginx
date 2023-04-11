local context = require("opentelemetry.context")
local span_context = require("opentelemetry.trace.span_context")
local trp = require("plugins.opentelemetry.traceresponse_propagator")

local function new_response_header_carrier(headers_table)
    local r = {
        header = {},
        resp = {},
    }
    r.header = headers_table
    r.resp.get_headers = function() return r.header end
    return r
end

describe("fields", function()
    it("should return { traceresponse }", function()
        assert.are.same({ "traceresponse" }, trp.new():fields())
    end)
end)

describe("parse_trace_response", function()
    it("when well-formed, returns table with version, trace id, child span id, traceflags", function()
        local trace_response = trp.parse_trace_response("00-12345678123456781234567812345678-1234567812345678-00")
        assert.are.same(trace_response.version, "00")
        assert.are.same(trace_response.trace_id, "12345678123456781234567812345678")
        assert.are.same(trace_response.child_id, "1234567812345678")
        assert.are.same(trace_response.trace_flags, "00")
        assert.are.same(trace_response.valid, true)
    end)

    it("when less than 4 parts, returns table with valid set to false", function()
        local trace_response = trp.parse_trace_response("lessthan-four-parts")
        assert.are.same(trace_response.version, nil)
        assert.are.same(trace_response.trace_id, nil)
        assert.are.same(trace_response.child_id, nil)
        assert.are.same(trace_response.trace_flags, nil)
        assert.is_not_true(trace_response.valid)
    end)
end)

describe("extract", function()
    it("returns same context object if traceresponse header is empty", function()
        local carrier = new_response_header_carrier({ foo = "bar" }).resp
        local ctx = context.new()
        local new_trp = trp.new()
        local new_ctx = new_trp:extract(ctx, carrier)
        assert.are.same(ctx, new_ctx)
    end)

    it("returns same context object if traceresponse header is invalid", function()
        local carrier = new_response_header_carrier({ traceresponse = "mraaahhhh" }).resp
        local ctx = context.new()
        local new_trp = trp.new()
        local new_ctx = new_trp:extract(ctx, carrier)
        assert.are.same(ctx, new_ctx)
    end)

    it("returns context object with span, trace id, and sampling decision", function()
        local carrier = new_response_header_carrier({ traceresponse = "00-12345678123456781234567812345678-1234567812345678-00" })
            .resp
        local ctx = context.new()
        local new_trp = trp.new()
        local new_span_ctx = new_trp:extract(ctx, carrier).sp:context()
        assert.are.same("12345678123456781234567812345678", new_span_ctx.trace_id)
        assert.are.same("1234567812345678", new_span_ctx.span_id)
        -- Last segment of traceresponse is sampling decision; 00 is unsampled.
        assert.are.same(new_span_ctx:is_sampled(), false)
    end)

    it("handles single-character sampling decisions", function()
        local cases = { { sampled = false,  flag = 0 }, { sampled = true, flag = 1 } }
        for _, case in ipairs(cases) do
            local carrier = new_response_header_carrier({ traceresponse = "00-12345678123456781234567812345678-1234567812345678-" .. case.flag })
                .resp
            local ctx = context.new()
            local new_trp = trp.new()
            local new_span_ctx = new_trp:extract(ctx, carrier).sp:context()
            assert.are.same(new_span_ctx:is_sampled(), case.sampled)
        end
    end)
end)

describe("inject", function()
    it("does nothing when context has no associated span", function()
        local carrier = new_response_header_carrier({ foo = "bar" })
        local ctx = context.new()
        local new_trp = trp.new()
        spy.on(carrier, "set_header")
        new_trp:inject(ctx, carrier)
        assert.spy(carrier.set_header).was_not_called()
    end)

    it("adds span context to traceresponse header", function()
        local carrier = new_response_header_carrier({ foo = "bar" })
        local ctx = context.new():with_span_context(
            span_context.new("12345678123456781234567812345678", "1234567812345678", 1))
        trp.new():inject(ctx, carrier)
        assert.are.same(
            carrier.resp.get_headers()["traceresponse"],
            "00-12345678123456781234567812345678-1234567812345678-1")
    end)
end)
