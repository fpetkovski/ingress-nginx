local context        = require("opentelemetry.context")
local main           = require("plugins.opentelemetry.main")
local old_getenv     = os.getenv
local recording_span = require("opentelemetry.trace.recording_span")
local result         = require("opentelemetry.trace.sampling.result")
local span_context   = require("opentelemetry.trace.span_context")
local span_kind      = require("opentelemetry.trace.span_kind")
local test_utils     = require("plugins.opentelemetry.test.utils")
local utils          = require("plugins.opentelemetry.shopify_utils")

local orig_plugin_mode = main.plugin_mode

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
main.plugin_open_telemetry_captured_request_headers               = {}

describe("should_force_sample_buffered_spans", function()
    it("returns true if initial sampling decision was record_and_sample", function()
        local ngx_resp = make_ngx_resp(
            { traceresponse = "00-00000000000000000000000000000001-0000000000000001-01" }
        )
        assert.is_true(main.should_force_sample_buffered_spans(ngx_resp, result.record_and_sample, "DEFERRED_SAMPLING"))
    end)

    it("returns true if initial sampling decision was record_only and traceresponse includes sampling decision 01",
        function()
            local ngx_resp = make_ngx_resp(
                { traceresponse = "00-00000000000000000000000000000001-0000000000000001-01" }
            )
            assert.is_true(main.should_force_sample_buffered_spans(ngx_resp, result.record_only, "DEFERRED_SAMPLING"))
        end)

    it("returns false if plugin mode is not deferred_sampling",
        function()
            local ngx_resp = make_ngx_resp(
                { traceresponse = "00-00000000000000000000000000000001-0000000000000001-01" }
            )
            assert.is_false(main.should_force_sample_buffered_spans(ngx_resp, result.record_only, "NOT_DEFERRED_SAMPLING"))
        end)

    it("returns false if initial sampling decision was record_only and traceresponse includes sampling decision 00",
        function()
            local ngx_resp = make_ngx_resp(
                { traceresponse = "00-00000000000000000000000000000001-0000000000000001-00" }
            )
            assert.is_false(main.should_force_sample_buffered_spans(ngx_resp, result.record_only, "DEFERRED_SAMPLING"))
        end)

    it("returns false if initial sampling decision was record_only and traceresponse was absent", function()
        local ngx_resp = make_ngx_resp({ hi = "mom" })
        assert.is_false(main.should_force_sample_buffered_spans(ngx_resp, result.record_only, "DEFERRED_SAMPLING"))
    end)
end)

describe("make_propagation_header_metric_tags", function()
    it("returns trace_id_present = false if no propagation headers present", function()
        local headers = {}
        local expected = { trace_id_present = 'false', traceparent = 'false', upstream_name = "mycoolservice", plugin_mode = "VERBOSITY_SAMPLING" }
        expected["x-cloud-trace-context"] = 'false'
        expected["x-shopify-trace-context"] = 'false'
        assert.are.same(main.make_propagation_header_metric_tags(headers, "mycoolservice", "VERBOSITY_SAMPLING"), expected)
    end)

    it("returns traceparent = true when only traceparent is supplied", function()
        local headers = { traceparent = "hi" }
        local expected = { trace_id_present = 'true', traceparent = 'true', upstream_name = "mycoolservice", plugin_mode = "VERBOSITY_SAMPLING" }
        expected["x-cloud-trace-context"] = 'false'
        expected["x-shopify-trace-context"] = 'false'
        assert.are.same(main.make_propagation_header_metric_tags(headers, "mycoolservice", "VERBOSITY_SAMPLING"), expected)
    end)

    it("returns multiple headers when multiple are present", function()
        local headers = {}
        headers["x-shopify-trace-context"] = "hi"
        headers["x-cloud-trace-context"] = "hi"
        headers["traceparent"] = "hi"
        local result = main.make_propagation_header_metric_tags(headers, "mycoolservice", "VERBOSITY_SAMPLING")
        local expected = { trace_id_present = 'true', traceparent = 'true', upstream_name = "mycoolservice", plugin_mode = "VERBOSITY_SAMPLING" }
        expected["x-cloud-trace-context"] = 'true'
        expected["x-shopify-trace-context"] = 'true'
        table.sort(result)
        table.sort(expected)
        assert.are.same(result, expected)
    end)
end)

describe("propagation_context", function()
    it("returns proxy context when proxy context is sampled", function()
        local sampled            = 1
        local proxy_span_context = span_context.new("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "aaaaaaaaaaaaaaaa", sampled, "",
            false)
        local proxy_ctx          = context:with_span_context(proxy_span_context)
        local request_ctx        = context.new()
        assert.are.same(proxy_ctx, main.propagation_context(request_ctx, proxy_ctx, "VERBOSITY_SAMPLING"))
    end)

    it("returns request context when proxy context is not sampled and plugin mode is VERBOSITY_SAMPLING", function()
        local sampled            = 0
        local proxy_span_context = span_context.new("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "aaaaaaaaaaaaaaaa", sampled, "",
            false)
        local proxy_ctx          = context:with_span_context(proxy_span_context)
        local request_ctx        = context.new()
        assert.are.same(request_ctx, main.propagation_context(request_ctx, proxy_ctx, "VERBOSITY_SAMPLING"))
    end)

    it("returns proxy context when proxy context is not sampled and plugin mode is deferred sampling", function()
        local sampled            = 0
        local proxy_span_context = span_context.new("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "aaaaaaaaaaaaaaaa", sampled, "",
            false)
        local proxy_ctx          = context:with_span_context(proxy_span_context)
        local request_ctx        = context.new()
        assert.are.same(proxy_ctx, main.propagation_context(request_ctx, proxy_ctx, "DEFERRED_SAMPLING"))
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

describe("plugin_mode", function()
    before_each(function()
        ngx.ctx.opentelemetry_plugin_mode = nil
    end)

    it("respects preexisting context values", function()
        ngx.ctx.opentelemetry_plugin_mode = "hello, world!"
        assert.are_same("hello, world!", main.plugin_mode())
    end)

    it("returns BYPASSED if request is bypassed", function()
        local orig = main.request_is_bypassed
        main.request_is_bypassed = function() return true end
        assert.are.same(main.plugin_mode(), "BYPASSED")
        main.request_is_bypassed = orig
    end)

    it("returns DEFERRED_SAMPLING if request is NOT bypassed and using deferred sampler", function()
        local orig_bypass = main.request_is_bypassed
        local orig_deferred = main.should_use_deferred_sampler
        main.request_is_bypassed = function() return false end
        main.should_use_deferred_sampler = function() return true end
        assert.are.same(main.plugin_mode(), "DEFERRED_SAMPLING")
        main.request_is_bypassed = orig_bypass
        main.should_use_deferred_sampler = orig_deferred
    end)

    it("returns BYPASSED if request is NOT bypassed, is NOT using deferred sampler, and does NOT  have tracing headers",
        function()
            local orig_bypass = main.request_is_bypassed
            local orig_deferred = main.should_use_deferred_sampler
            local orig_request_has_tracing_headers = main.request_has_tracing_headers
            main.plugin_open_telemetry_firehose_upstreams = {}
            main.request_is_bypassed = function() return false end
            main.should_use_deferred_sampler = function() return false end
            main.request_has_tracing_headers = function() return false end
            assert.are.same(main.plugin_mode(), "BYPASSED")
            main.request_is_bypassed = orig_bypass
            main.should_use_deferred_sampler = orig_deferred
            main.request_has_tracing_headers = orig_request_has_tracing_headers
        end)

    it("returns VERBOSITY_SAMPLING if request is NOT bypassed, is NOT using verbosity sampler, and DOES have tracing headers"
        ,
        function()
            local orig_bypass = main.request_is_bypassed
            local orig_deferred = main.should_use_deferred_sampler
            local orig_request_has_tracing_headers = main.request_has_tracing_headers
            main.request_is_bypassed = function() return false end
            main.should_use_deferred_sampler = function() return false end
            main.request_has_tracing_headers = function() return true end
            main.plugin_open_telemetry_firehose_upstreams = {}
            assert.are.same(main.plugin_mode(), "VERBOSITY_SAMPLING")
            main.request_is_bypassed = orig_bypass
            main.should_use_deferred_sampler = orig_deferred
            main.request_has_tracing_headers = orig_request_has_tracing_headers
        end)

    it("returns VERBOSITY_SAMPLING if request is NOT bypassed, DOES NOT have tracing headers, and IS in firehose"
        ,
        function()
            local orig_bypass = main.request_is_bypassed
            local orig_deferred = main.should_use_deferred_sampler
            local orig_request_has_tracing_headers = main.request_has_tracing_headers
            main.request_is_bypassed = function() return false end
            main.should_use_deferred_sampler = function() return false end
            main.request_has_tracing_headers = function() return false end
            main.plugin_open_telemetry_firehose_upstreams = { wat = true }
            assert.are.same(main.plugin_mode("wat"), "VERBOSITY_SAMPLING")
            main.request_is_bypassed = orig_bypass
            main.should_use_deferred_sampler = orig_deferred
            main.request_has_tracing_headers = orig_request_has_tracing_headers
        end)

    it("returns VERBOSITY_SAMPLING if request is NOT bypassed, DOES NOT have tracing headers, and firehose is set to ALL"
        ,
        function()
            local orig_bypass = main.request_is_bypassed
            local orig_deferred = main.should_use_deferred_sampler
            local orig_request_has_tracing_headers = main.request_has_tracing_headers
            main.request_is_bypassed = function() return false end
            main.should_use_deferred_sampler = function() return false end
            main.request_has_tracing_headers = function() return false end
            main.plugin_open_telemetry_firehose_upstreams = { all = true }
            assert.are.same(main.plugin_mode("wat"), "VERBOSITY_SAMPLING")
            main.request_is_bypassed = orig_bypass
            main.should_use_deferred_sampler = orig_deferred
            main.request_has_tracing_headers = orig_request_has_tracing_headers
        end)
end)

describe("log()", function()
    local orig_get_headers = ngx.req.get_headers
    before_each(function()
        main.plugin_mode = function() return "VERBOSITY_SAMPLING" end
        ngx.req.get_headers = function() return {} end
        main.span_buffering_processor = {
            send_spans = function(_, __) end
        }
        stub(recording_span, "finish")
        local proxy_span = recording_span.new(
            nil, nil, span_context.new(), "test_span", { kind = span_kind.server })
        local request_span = recording_span.new(
            nil, nil, span_context.new(), "test_span", { kind = span_kind.server })
        local response_span = recording_span.new(
            nil, nil, span_context.new(), "test_span", { kind = span_kind.server })
        ngx.ctx = {
            opentelemetry = {
                proxy_span_ctx = { sp = proxy_span },
                request_span_ctx = { sp = request_span },
                response_span_ctx = { sp = response_span }
            }
        }
    end)

    after_each(function()
        recording_span.finish:revert()
        main.plugin_mode = orig_plugin_mode
        ngx.req.get_headers = orig_get_headers
        ngx.ctx = {}
    end)

    it("sets status and http status on spans", function()
        ngx.var.status = 504
        main.log()
        local req_span = ngx.ctx.opentelemetry.request_span_ctx.sp
        local req_span_has_http_status = false
        for i, attr in ipairs(req_span.attributes) do
            if attr.key == "http.status_code" and attr.value.int_value == 504 then
                req_span_has_http_status = true
            end
        end

        assert.is_true(req_span_has_http_status)
        assert.are_same(ngx.ctx.opentelemetry.request_span_ctx.sp.status.code, 2)
        assert.are_same(ngx.ctx.opentelemetry.proxy_span_ctx.sp.status.code, 2)
    end)

    it("records configured HTTP headers", function()
        main.plugin_open_telemetry_captured_request_headers = { ["x-bar"] = "x_bar" }
        ngx.req.get_headers = function() return { ["x-bar"] = "baz" } end

        main.log()
        local req_span = ngx.ctx.opentelemetry.request_span_ctx.sp
        local req_span_has_header_attr = false
        for i, attr in ipairs(req_span.attributes) do
            if attr.key == "http.request.header.x_bar" and attr.value.string_value == "baz" then
                req_span_has_header_attr = true
            end
        end

        assert.is_true(req_span_has_header_attr)
    end)

    it("semicolon-concatenates HTTP headers when there are multiples", function()
        main.plugin_open_telemetry_captured_request_headers = { ["x-bar"] = "x_bar" }
        ngx.req.get_headers = function() return { ["x-bar"] = { "baz", "bat" } } end
        main.log()
        local req_span = ngx.ctx.opentelemetry.request_span_ctx.sp
        local req_span_has_header_attr = false
        for i, attr in ipairs(req_span.attributes) do
            if attr.key == "http.request.header.x_bar" and attr.value.string_value == "baz;bat" then
                req_span_has_header_attr = true
            end
        end

        assert.is_true(req_span_has_header_attr)
    end)

    it("truncates long http header values", function()
        main.plugin_open_telemetry_captured_request_headers = { ["x-bar"] = "x_bar" }
        local long_header = string.rep("a", 200)
        ngx.req.get_headers = function() return { ["x-bar"] = long_header } end

        main.log()
        local req_span = ngx.ctx.opentelemetry.request_span_ctx.sp
        local req_span_has_header_attr = false
        for i, attr in ipairs(req_span.attributes) do
            if attr.key == "http.request.header.x_bar" and attr.value.string_value == string.sub(long_header, 0, 128) then
                req_span_has_header_attr = true
            end
        end

        assert.is_true(req_span_has_header_attr)
    end)

    it("does not add attribute when header is not present", function()
        main.plugin_open_telemetry_captured_request_headers = { ["x-bar"] = "x_bar" }
        ngx.req.get_headers = function() return { } end
        main.log()
        local req_span = ngx.ctx.opentelemetry.request_span_ctx.sp
        local req_span_has_header_attr = false
        for i, attr in ipairs(req_span.attributes) do
            if attr.key == "http.request.header.x_bar" then
                req_span_has_header_attr = true
            end
        end

        assert.is_false(req_span_has_header_attr)
    end)

    describe("when spans are absent", function()
        before_each(function()
            ngx.ctx = {
                opentelemetry = { hi = "ok"}
            }
        end)

        it("does not error if spans are nil", function()
            -- test will fail if there are errors
            main.log()
        end)
    end)

end)

describe("header_filters", function()
    before_each(function()
        main.plugin_open_telemetry_strip_traceresponse = true
        main.plugin_mode = function() return "BYPASSED" end
    end)

    after_each(function()
        main.plugin_mode = orig_plugin_mode
        ngx.var.arg_debug_headers = nil
    end)

    it("strips traceresponse when strip_traceresponse setting is true and debug_headers is not present", function()
        main.plugin_open_telemetry_strip_traceresponse = true
        ngx.var.arg_debug_headers = nil
        ngx.header["traceresponse"] = "im_here"
        main.header_filter()
        assert.is_nil(ngx.header["traceresponse"])
    end)

    it("does not strip traceresponse when strip_traceresponse is true and ?debug_headers is present", function()
        main.plugin_open_telemetry_strip_traceresponse = true
        ngx.header["traceresponse"] = "im_here"
        ngx.var.arg_debug_headers = "hi"
        main.header_filter()
        assert.are_same(ngx.header["traceresponse"], "im_here")
    end)

    it("does not strip traceresponse headers when strip_traceresponse is false", function()
        main.plugin_open_telemetry_strip_traceresponse = false
        ngx.header["traceresponse"] = "im_here"
        main.header_filter()
        assert.are_same(ngx.header["traceresponse"], "im_here")
    end)
end)

describe("init_worker", function()
    before_each(function()
        package.loaded['plugins.opentelemetry.main'] = nil -- so we can re-require and pick up env vars
        os.getenv = old_getenv
        ngx.ctx.opentelemetry_tracer = nil
    end)

    it("does not attach env-var sourced attributes when absent ", function()
        local main = require("plugins.opentelemetry.main")
        main.init_worker(test_utils.make_config())

        local env_attrs = { POD_NAMESPACE = "k8s.namespace.name", POD_NAME = "k8s.pod.name",
        NODE_NAME = "k8s.node.name", KUBE_LOCATION = "cloud.region", KUBE_CLUSTER = "k8s.cluster.name" }
        for _, attr in pairs(env_attrs) do
            local present = false
            for _i, r_attr in ipairs(main.tracer("DEFERRED_SAMPLING").provider.resource.attrs) do
                if r_attr.key == attr then
                    present = true
                end
            end
            assert.is_false(present)
        end
    end)

    it("attaches env-var sourced attributes when present", function()
        os.getenv = function(str)
            local hash = { POD_NAMESPACE = "my-namespace", POD_NAME = "abc123",
                           NODE_NAME = "my-cool-node", KUBE_LOCATION = "us-north-northwest-1",
                           KUBE_CLUSTER = "my-cool-cluster" }
            return hash[str]
        end
        local main = require("plugins.opentelemetry.main")

        main.init_worker(test_utils.make_config())

        local env_attrs = { POD_NAMESPACE = "k8s.namespace.name", POD_NAME = "k8s.pod.name",
                            NODE_NAME = "k8s.node.name", KUBE_LOCATION = "cloud.region",
                            KUBE_CLUSTER = "k8s.cluster.name" }
        for _, attr in pairs(env_attrs) do
            local present = false
            for _i, r_attr in ipairs(main.tracer("DEFERRED_SAMPLING").provider.resource.attrs) do
                if r_attr.key == attr then
                    present = true
                end
            end
            assert.is_true(present)
        end
    end)
end)
