local context = require "opentelemetry.context"
local ds = require "plugins.opentelemetry.deferred_sampler"
local result = require "opentelemetry.trace.sampling.result"
local span_context = require "opentelemetry.trace.span_context"

describe("should_sample", function()
    it("returns RECORD_ONLY when parent context is empty", function()
        local s = ds.new()
        assert.are.same(s:should_sample({ parent_ctx = span_context.new() }).decision, result.record_only)
    end)

    it("returns RECORD_AND_SAMPLE when parent context is sampled", function()
        local span_ctx = span_context.new("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "aaaaaaaaaaaaaaaa", 1, "", false)
        local s        = ds.new()
        assert.are.same(s:should_sample({ parent_ctx = span_ctx }).decision, result.record_and_sample)
    end)

    it("returns RECORD_ONLY when parent context is not sampled", function()
        local span_ctx = span_context.new("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "aaaaaaaaaaaaaaaa", 0, "", false)
        local ctx      = context:with_span_context(span_ctx)
        local s        = ds.new()
        assert.are.same(s:should_sample({ parent_ctx = ctx }).decision, result.record_only)
    end)
end)
