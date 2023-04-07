local main = require("plugins.opentelemetry.main")
local result = require("opentelemetry.trace.sampling.result")

local start = os.clock()
local ngx_resp = { get_headers = function() return { traceresponse = "00-12345678123456781234567812345678-1234567812345678-01" } end }

for i = 1, 1000000 do
    main.should_force_sample_buffered_spans(ngx_resp, result.record_only, "DEFERRED_SAMPLING")
end

print('Unfamiliar traceresponse - time taken: ' .. (os.clock() - start) ..' seconds.')

local start = os.clock()
local ngx_resp = { get_headers = function() return { traceresponse = "00-61616161616161616161616161616161-6161616161616161-00" } end }

for i = 1, 1000000 do
    main.should_force_sample_buffered_spans(ngx_resp, result.record_only, "DEFERRED_SAMPLING")
end

print('Familiar traceresponse - time taken: ' .. (os.clock() - start) ..' seconds.')
