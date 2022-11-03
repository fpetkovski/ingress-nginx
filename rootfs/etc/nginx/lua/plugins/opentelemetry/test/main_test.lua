local main = require("plugins.opentelemetry.main")

describe("make_propagation_header_metric_tags", function()
    it("returns trace_id_present = false if no propagation headers present", function()
        local headers = {}
        local expected = { trace_id_present = 'false', traceparent = 'false', upstream_name = "mycoolservice" }
        expected["x-cloud-trace-context"] = 'false'
        expected["x-shopify-trace-context"] = 'false'
        assert.are.same(main.make_propagation_header_metric_tags(headers, "mycoolservice"), expected)
    end)

    it("returns traceparent = true when only traceparent is supplied", function()
        local headers = { traceparent = "hi" }
        local expected = { trace_id_present = 'true', traceparent = 'true', upstream_name = "mycoolservice" }
        expected["x-cloud-trace-context"] = 'false'
        expected["x-shopify-trace-context"] = 'false'
        assert.are.same(main.make_propagation_header_metric_tags(headers, "mycoolservice"), expected)
    end)

    it("returns multiple headers when multiple are present", function()
        local headers = {}
        headers["x-shopify-trace-context"] = "hi"
        headers["x-cloud-trace-context"] = "hi"
        headers["traceparent"] = "hi"
        local result = main.make_propagation_header_metric_tags(headers, "mycoolservice")
        local expected = { trace_id_present = 'true', traceparent = 'true', upstream_name = "mycoolservice" }
        expected["x-cloud-trace-context"] = 'true'
        expected["x-shopify-trace-context"] = 'true'
        table.sort(result)
        table.sort(expected)
        assert.are.same(result, expected)
    end)
end)

describe("request_is_traced", function()
    it("returns true when both headers are present and o=1", function()
        ngx.ctx["shopify_headers_present"] = nil
        stub(ngx.req, "get_headers", function()
            return {
                ["x-shopify-trace-context"] = "B2993819A27935B8EF8295DFFC6DC44B/13421691958286113626;o=1",
                ["x-cloud-trace-context"] = "B2993819A27935B8EF8295DFFC6DC44B/13421691958286113626;o=1"
            }
        end)
        assert.is_true(main.request_is_traced())
        assert.is_true(ngx.ctx["shopify_headers_present"])
        ngx.req.get_headers:revert()
    end)

    it("returns false when both headers are present and o=0", function()
        ngx.ctx["shopify_headers_present"] = nil
        stub(ngx.req, "get_headers", function()
            return {
                ["x-shopify-trace-context"] = "B2993819A27935B8EF8295DFFC6DC44B/13421691958286113626;o=0",
                ["x-cloud-trace-context"] = "B2993819A27935B8EF8295DFFC6DC44B/13421691958286113626;o=0"
            }
        end)
        assert.is_false(main.request_is_traced())
        assert.is_false(ngx.ctx["shopify_headers_present"])
        ngx.req.get_headers:revert()
    end)
end)

describe("parse_upstream_addr", function()
    it("returns table with addr and port when it contains a single colon", function()
        local input = "foo:8080"
        local expected = { addr = "foo", port = 8080 }
        local output = main.parse_upstream_addr(input)
        assert.are_same(output.addr, expected.addr)
        assert.are_same(output.port, expected.port)
    end)

    it("returns table with addr and port when it contains numerical IP", function()
        local input = "127.0.0.1:8080"
        local expected = { addr = "127.0.0.1", port = 8080 }
        local output = main.parse_upstream_addr(input)
        assert.are_same(output.addr, expected.addr)
        assert.are_same(output.port, expected.port)
    end)

    it("returns nil values when input has no colon", function()
        local input = "foo8x0"
        local expected = { addr = nil, port = nil }
        local output = main.parse_upstream_addr(input)
        assert.are_same(output.addr, expected.addr)
        assert.are_same(output.port, expected.port)
    end)

    it("returns table with last address input contains a long list of addrs", function()
        local input = "foo:8080, bar:8081, baz:8082"
        local expected = { addr = "baz", port = 8082 }
        local output = main.parse_upstream_addr(input)
        assert.are_same(output.addr, expected.addr)
        assert.are_same(output.port, expected.port)
    end)

    it("returns table with last address input contains a long list of addrs", function()
        local input = "foo:8080, bar:8081, baz:8082 : qux:8083 : what:8084"
        local expected = { addr = "what", port = 8084 }
        local output = main.parse_upstream_addr(input)
        assert.are_same(output.addr, expected.addr)
        assert.are_same(output.port, expected.port)
    end)
end)
