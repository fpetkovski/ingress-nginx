local baggage = require("opentelemetry.baggage")
local context = require("opentelemetry.context")
local otel_global = require("opentelemetry.global")
local span_kind = require("opentelemetry.trace.span_kind")
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
        assert.is_false(
            sampler:should_sample(
                {
                    trace_id = "invalid traceid (should be 16 bytes represented as hex)",
                    parent_ctx = { trace_state = "trace_state" }
                }
            ):is_sampled())
    end)

    it("always returns true if span kind is server", function()
        local sampler = vs.new(0)
        assert.is_true(
            sampler:should_sample(
                {
                    trace_id = "11111111111111111111111111111111",
                    parent_ctx = { trace_state = "trace_state" },
                    kind = span_kind.server
                }):is_sampled())
    end)

    it("returns false if verbose_probability_sampled is false and span kind ~= server", function()
        local sampler = vs.new(0)
        assert.is_false(
            sampler:should_sample(
                {
                    trace_id = "11111111111111111111111111111111",
                    parent_ctx = { trace_state = "trace_state" },
                    kind = span_kind.client
                }):is_sampled())
    end)
end)
