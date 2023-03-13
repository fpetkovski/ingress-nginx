local id_generator = require("opentelemetry.trace.id_generator")
local recording_span = require("opentelemetry.trace.recording_span")
local span_buffering_processor = require "plugins.opentelemetry.span_buffering_processor"
local span_context = require("opentelemetry.trace.span_context")

local test_span_processor = {}
local mt = { __index = test_span_processor }

function test_span_processor.new()
    return setmetatable({ spans = {} }, mt)
end

function test_span_processor.on_end(self, sp)
    table.insert(self.spans, sp)
end

local function make_span(trace_id)
    local span_id = id_generator.new_span_id()
    if not trace_id then
        span_id, trace_id = id_generator.new_ids()
    end

    local new_span_context = span_context.new(trace_id, span_id, 0, nil, false)
    return recording_span.new(nil, nil, new_span_context, "test_span",  {})
end

describe("span_buffering_processor", function()
    before_each(function()
        ngx.ctx.opentelemetry_spans = nil
    end)

    describe("on_end", function()
        it("adds spans to ngx.ctx", function()
            local sbp = span_buffering_processor.new()
            local span = make_span()
            local span_2 = make_span()
            sbp:on_end(span)
            sbp:on_end(span_2)
            assert.are_equal(span, ngx.ctx.opentelemetry_spans[1])
            assert.are_equal(span_2, ngx.ctx.opentelemetry_spans[2])
        end)
    end)

    describe("send_spans", function()
        before_each(function ()
            ngx.ctx.opentelemetry_spans = nil
        end)

        it("sends spans to next span processor", function()
            local test_sp = test_span_processor.new()
            stub(test_sp, "on_end")
            local sbp = span_buffering_processor.new(test_sp)
            local span = make_span()
            sbp:on_end(span)
            sbp:send_spans(true)
            assert.stub(test_sp.on_end).was_called_with(test_sp, span)
        end)

        it("does not blow up if there are no spans", function()
            assert.is_nil(ngx.ctx.opentelemetry_spans)
            local sbp = span_buffering_processor.new({})
            assert.has_no.errors(function() sbp:send_spans() end)
        end)

        it("marks spans as sampled if update_span_ctx is true", function()
            local test_sp = test_span_processor.new()
            local sbp = span_buffering_processor.new(test_sp)
            local span = make_span()
            span:context().trace_flags = 0
            sbp:on_end(span)
            sbp:send_spans(true)
            assert(test_sp.spans[1]:context().trace_flags == 1)
        end)

        it("does not mark spans as sampled if update_span_ctx is false", function()
            local test_sp = test_span_processor.new()
            local sbp = span_buffering_processor.new(test_sp)
            local span = make_span()
            span:context().trace_flags = 0
            sbp:on_end(span)
            sbp:send_spans(false)
            assert.is_same(0, test_sp.spans[1]:context().trace_flags)
        end)
    end)
end)
