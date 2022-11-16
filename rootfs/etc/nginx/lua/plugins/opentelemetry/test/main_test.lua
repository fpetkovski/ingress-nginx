local main         = require("plugins.opentelemetry.main")
local context      = require("opentelemetry.context")
local result       = require("opentelemetry.trace.sampling.result")
local span_context = require("opentelemetry.trace.span_context")
local utils        = require("plugins.opentelemetry.shopify_utils")

local function make_ngx_resp(headers)
    return {
        get_headers = function()
            return headers
        end
    }
end

-- Set defaults, normally provided via config passed to `init_worker`
main.plugin_open_telemetry_bsp_inactive_timeout                 = 2
main.plugin_open_telemetry_bsp_max_export_batch_size            = 512
main.plugin_open_telemetry_service                              = "nginx"
main.plugin_open_telemetry_environment                          = "production"
main.plugin_open_telemetry_shopify_verbosity_sampler_percentage = 1
main.plugin_open_telemetry_bsp_drop_on_queue_full               = true
main.plugin_open_telemetry_exporter_otlp_endpoint               = "otel-collector.dns.podman:4318"
main.plugin_open_telemetry_exporter_timeout                     = 5
main.plugin_open_telemetry_enabled                              = true
main.plugin_open_telemetry_bsp_max_queue_size                   = 2048
main.plugin_open_telemetry_traces_sampler                       = "ShopifyVerbositySampler"
main.plugin_open_telemetry_traces_sampler_arg                   = "0.5"

describe("should_force_sample_buffered_spans", function()
    it("returns false if initial sampling decision was record_and_sample", function()
        local ngx_resp = make_ngx_resp(
            { traceresponse = "00-00000000000000000000000000000001-0000000000000001-01" }
        )
        assert.is_false(main.should_force_sample_buffered_spans(ngx_resp, result.record_and_sample))
    end)

    it("returns true if initial sampling decision was record_only and traceresponse includes sampling decision 01",
        function()
            local ngx_resp = make_ngx_resp(
                { traceresponse = "00-00000000000000000000000000000001-0000000000000001-01" }
            )
            assert.is_true(main.should_force_sample_buffered_spans(ngx_resp, result.record_only))
        end)

    it("returns false if initial sampling decision was record_only and traceresponse includes sampling decision 00",
        function()
            local ngx_resp = make_ngx_resp(
                { traceresponse = "00-00000000000000000000000000000001-0000000000000001-00" }
            )
            assert.is_false(main.should_force_sample_buffered_spans(ngx_resp, result.record_only))
        end)

    it("returns false if initial sampling decision was record_only and traceresponse was absent", function()
        local ngx_resp = make_ngx_resp({ hi = "mom" })
        assert.is_false(main.should_force_sample_buffered_spans(ngx_resp, result.record_only))
    end)
end)

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

describe("request_is_bypassed", function()
    it("returns true if bypassed_upstreams contains all", function()
        main.plugin_open_telemetry_bypassed_upstreams = utils.parse_upstream_list("all,foo,bar")
        local upstream = "remote_gcp-us-east1_core_production_pool_ssl"
        assert.is_true(main.request_is_bypassed(upstream))
    end)

    it("returns false if bypassed_upstreams does not contain match for upstream", function()
        main.plugin_open_telemetry_bypassed_upstreams = utils.parse_upstream_list("wat,foo,bar,baz")
        local upstream = "remote_gcp-us-east1_core_production_pool_ssl"
        assert.is_false(main.request_is_bypassed(upstream))
    end)

    it("returns true if any part of upstream matches", function()
        main.plugin_open_telemetry_bypassed_upstreams = utils.parse_upstream_list("core")
        local upstream = "remote_gcp-us-east1_core_production_pool_ssl"
        assert.is_true(main.request_is_bypassed(upstream))
    end)
end)

describe("new_tracer_provider", function()
    it("returns a tracer provider with sampler and arg as specified", function()
        local provider = main.create_tracer_provider(
            "ShopifyVerbositySampler", "0.25")
        assert.are_same(
            "ShopifyVerbositySampler{0.25}",
            provider.sampler:get_description()
        )
    end)

    it("errors out if sampler is nonexistent", function()
        assert.has_error(
            function() main.create_tracer_provider("MakeBelieveSampler") end,
            "could not find sampler MakeBelieveSampler")
    end)
end)

describe("should_use_deferred_sampler", function()
    it("returns true if deferred_sampling_upstreams matches arg", function()
        ngx.ctx.opentelemetry_should_use_deferred_sampler = nil
        main.plugin_open_telemetry_deferred_sampling_upstreams = { foo = true }
        assert.is_true(main.should_use_deferred_sampler("foo-bar-80"))
    end)

    it("returns false if deferred_sampling_upstreams does not match arg", function()
        ngx.ctx.opentelemetry_should_use_deferred_sampler = nil
        main.plugin_open_telemetry_deferred_sampling_upstreams = { foo = true }
        assert.is_false(main.should_use_deferred_sampler("baz-bat-80"))
    end)

    it("returns true if deferred_sampling_upstreams is all", function()
        ngx.ctx.opentelemetry_should_use_deferred_sampler = nil
        main.plugin_open_telemetry_deferred_sampling_upstreams = { all = true }
        assert.is_true(main.should_use_deferred_sampler("baz-bat-80"))
    end)

    it("returns false if deferred_sampling_upstreams is empty table", function()
        ngx.ctx.opentelemetry_should_use_deferred_sampler = nil
        main.plugin_open_telemetry_deferred_sampling_upstreams = {}
        assert.is_false(main.should_use_deferred_sampler("baz-bat-80"))
    end)
end)

describe("plugin_should_run", function()
    before_each(function()
        ngx.ctx.opentelemetry_plugin_should_run = nil
    end)
    it("respects preexisting context values", function()
        ngx.ctx.opentelemetry_plugin_should_run = "hello, world!"
        assert.are_same("hello, world!", main.plugin_should_run())
    end)

    it("returns false if request is bypassed", function()
        local orig = main.request_is_bypassed
        main.request_is_bypassed = function() return true end
        assert.is_false(main.plugin_should_run())
        main.request_is_bypassed = orig
    end)

    it("returns true if request is NOT bypassed and using deferred sampler", function()
        local orig_bypass = main.request_is_bypassed
        local orig_deferred = main.should_use_deferred_sampler
        main.request_is_bypassed = function() return false end
        main.should_use_deferred_sampler = function() return true end
        assert.is_true(main.plugin_should_run())
        main.request_is_bypassed = orig_bypass
        main.should_use_deferred_sampler = orig_deferred
    end)

    it("returns false if request is NOT bypassed, is NOT using deferred sampler, and does NOT  have tracing headers",
        function()
            local orig_bypass = main.request_is_bypassed
            local orig_deferred = main.should_use_deferred_sampler
            local orig_request_has_tracing_headers = main.request_has_tracing_headers
            main.request_is_bypassed = function() return false end
            main.should_use_deferred_sampler = function() return false end
            main.request_has_tracing_headers = function() return false end
            assert.is_false(main.plugin_should_run())
            main.request_is_bypassed = orig_bypass
            main.should_use_deferred_sampler = orig_deferred
            main.request_has_tracing_headers = orig_request_has_tracing_headers
        end)

    it("returns true if request is NOT bypassed, is NOT using verbosity sampler, and DOES have tracing headers",
        function()
            local orig_bypass = main.request_is_bypassed
            local orig_deferred = main.should_use_deferred_sampler
            local orig_request_has_tracing_headers = main.request_has_tracing_headers
            main.request_is_bypassed = function() return false end
            main.should_use_deferred_sampler = function() return false end
            main.request_has_tracing_headers = function() return true end
            assert.is_true(main.plugin_should_run())
            main.request_is_bypassed = orig_bypass
            main.should_use_deferred_sampler = orig_deferred
            main.request_has_tracing_headers = orig_request_has_tracing_headers
        end)
end)
