local context = require("opentelemetry.context")
local recording_span = require("opentelemetry.trace.recording_span")
local span_context = require("opentelemetry.trace.span_context")
local span_kind = require("opentelemetry.trace.span_kind")
local tracestate = require("opentelemetry.trace.tracestate")
local vs = require "plugins.opentelemetry.verbosity_sampler"

describe("verbose_probability_sampled", function()
    it("returns false if characters 9-16 of TraceID are > verbosity_id_upper_bound", function()
        local sampler = vs.new(0.5)
        assert.is_false(sampler:verbose_probability_sampled("00000000ffffffff0000000000000000"))
    end)

    it("returns true if characters 9-16 of TraceID are < verbosity_id_upper_bound", function()
        local sampler = vs.new(0.5)
        -- chars 9-16 hold a small value in hex, so this will be < verbosity_id_upper_bound
        assert.is_true(sampler:verbose_probability_sampled("00000000111111110000000000000000"))
    end)
end)

describe("should_sample?", function()
    it("returns false if TraceID is malformed", function()
        local sampler = vs.new(1)
        local tracestate = tracestate.new({ foo = "bar" })
        local new_span_context = span_context.new("malformed", "30e2bb20d2ad42b9", 0, tracestate, false)
        local span = recording_span.new(nil, nil, new_span_context, "test_span", { kind = span_kind.server })
        local ctx = context.new({}, span)
        local result = sampler:should_sample(
            {
                trace_id = "invalid traceid (should be 16 bytes represented as hex)",
                parent_ctx = ctx
            }
        )
        assert.is_same(result.trace_state, tracestate)
        assert.is_false(result:is_sampled())
    end)

    it("always returns true if span kind is server", function()
        local tracestate = tracestate.new({ foo = "bar" })
        local new_span_context = span_context.new("eea85efa015a9fc70e1e1fc9af41f94f", "30e2bb20d2ad42b9", 0, tracestate,
            false)
        local span = recording_span.new(nil, nil, new_span_context, "test_span", { kind = span_kind.server })
        local ctx = context.new({}, span)
        local sampler = vs.new(0)
        local result = sampler:should_sample(
            {
                trace_id = "11111111111111111111111111111111",
                parent_ctx = ctx,
                kind = span_kind.server
            }
        )
        assert.is_same(result.trace_state, tracestate)
        assert.is_true(result:is_sampled())
    end)

    it("returns false if verbose_probability_sampled is false and span kind ~= server", function()
        local sampler = vs.new(0)
        local tracestate = tracestate.new({ foo = "bar" })
        local new_span_context = span_context.new("eea85efa015a9fc70e1e1fc9af41f94f", "30e2bb20d2ad42b9", 0, tracestate,
            false)
        local span = recording_span.new(nil, nil, new_span_context, "test_span", { kind = span_kind.producer })
        local ctx = context.new({}, span)
        local result = sampler:should_sample(
            {
                trace_id = "11111111111111111111111111111111",
                parent_ctx = ctx,
                kind = span_kind.client
            }
        )
        assert.is_same(result.trace_state, tracestate)
        assert.is_false(result:is_sampled())
    end)
end)
