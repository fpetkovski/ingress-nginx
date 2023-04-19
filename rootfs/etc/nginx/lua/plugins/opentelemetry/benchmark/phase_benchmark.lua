------------------------------------------------------------------------------------------------------------------------
-- These benchmarks run plugin phases, sometimes in serial.
------------------------------------------------------------------------------------------------------------------------
local call_count = 5000000

local response_header_setter = require("plugins.opentelemetry.response_header_setter")
local test_span_processor = require("plugins.opentelemetry.test.test_span_processor")
local test_utils = require("plugins.opentelemetry.test.utils")

--- No upstreams bypassed, no trace headers

ngx.var = test_utils.make_ngx_var()
package.loaded['plugins.opentelemetry.main'] = nil
local main = require("plugins.opentelemetry.main")
main.plugin_open_telemetry_span_processor = test_span_processor.new()
local config = test_utils.make_config({ plugin_open_telemetry_bypassed_upstreams = "" })
main.init_worker(config)
ngx.req.get_headers = function() return {  } end
ngx.req.set_header = function() return {} end
ngx.resp.get_headers = function() return {} end
response_header_setter.set = function() return {} end

local start = os.clock()

for _ = 1, call_count do
    ngx.ctx.opentelemetry_plugin_mode = nil
    ngx.ctx.opentelemetry_tracer = nil
    ngx.ctx.opentelemetry = nil
    ngx.ctx.opentelemetry_spans = nil
    main.rewrite()
end

print(tostring(call_count) .. ' rewrite(): no upstreams bypassed, no headers - ' .. (os.clock() - start) ..' seconds.')

--- Rewrite: no upstreams bypassed, sampled in trace header

ngx.var = test_utils.make_ngx_var()
package.loaded['plugins.opentelemetry.main'] = nil
local main = require("plugins.opentelemetry.main")
main.plugin_open_telemetry_span_processor = test_span_processor.new()
local config = test_utils.make_config({ plugin_open_telemetry_bypassed_upstreams = "" })
main.init_worker(config)
ngx.req.get_headers = function() return {
        ["x-cloud-trace-context"] = "bb3ba1dcf2d6a66fadce442cc703af9f/11221422501110509816;o=1",
        ["x-shopify-trace-context"] = "bb3ba1dcf2d6a66fadce442cc703af9f/11221422501110509816;o=1" } end
ngx.req.set_header = function() return {} end
ngx.resp.get_headers = function() return {} end
response_header_setter.set = function() return {} end

local start = os.clock()

for _ = 1, call_count do
    ngx.ctx.opentelemetry_plugin_mode = nil
    ngx.ctx.opentelemetry_tracer = nil
    ngx.ctx.opentelemetry = nil
    ngx.ctx.opentelemetry_spans = nil
    main.rewrite()
end

print(tostring(call_count) .. ' rewrite(): no upstreams bypassed, sampled in trace header - ' .. (os.clock() - start) ..' seconds.')

-- rewrite and header filter: sampled in trace header

ngx.var = test_utils.make_ngx_var()
package.loaded['plugins.opentelemetry.main'] = nil
local main = require("plugins.opentelemetry.main")
main.plugin_open_telemetry_span_processor = test_span_processor.new()
local config = test_utils.make_config({ plugin_open_telemetry_bypassed_upstreams = "" })
main.init_worker(config)
ngx.req.get_headers = function() return {
        ["x-cloud-trace-context"] = "bb3ba1dcf2d6a66fadce442cc703af9f/11221422501110509816;o=1",
        ["x-shopify-trace-context"] = "bb3ba1dcf2d6a66fadce442cc703af9f/11221422501110509816;o=1" } end
ngx.req.set_header = function() return {} end
ngx.resp.get_headers = function() return {} end
response_header_setter.set = function() return {} end

local start = os.clock()

for _ = 1, call_count do
    ngx.ctx.opentelemetry_plugin_mode = nil
    ngx.ctx.opentelemetry_tracer = nil
    ngx.ctx.opentelemetry = nil
    ngx.ctx.opentelemetry_spans = nil
    main.rewrite()
    main.header_filter()
end

print(tostring(call_count) .. ' rewrite() and header_filter(): no upstreams bypassed, sampled in trace header - ' .. (os.clock() - start) ..' seconds.')
