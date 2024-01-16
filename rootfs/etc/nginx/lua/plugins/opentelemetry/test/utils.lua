local _M = {}

------------------------------------------------------------------------------------------------------------------------
-- This config is what results from Golang parsing the configmap. To refresh against the current rendered config, you
-- can shell into a running container and examine /etc/nginx/nginx.conf.
------------------------------------------------------------------------------------------------------------------------
function _M.make_config(overrides)
    local default = {
        plugin_open_telemetry_bsp_batch_timeout = 3,
        plugin_open_telemetry_bsp_drop_on_queue_full = true,
        plugin_open_telemetry_bsp_inactive_timeout = 1,
        plugin_open_telemetry_bsp_max_export_batch_size = 512,
        plugin_open_telemetry_bsp_max_queue_size = 2048,
        plugin_open_telemetry_bypassed_upstreams = "",
        plugin_open_telemetry_deferred_sampling_upstreams = "",
        plugin_open_telemetry_environment = "production",
        plugin_open_telemetry_exporter_otlp_endpoint = "localhost:4318",
        plugin_open_telemetry_exporter_otlp_headers = "",
        plugin_open_telemetry_exporter_timeout = 1,
        plugin_open_telemetry_service = "global-proxy-staging",
        plugin_open_telemetry_set_traceresponse = false,
        plugin_open_telemetry_shopify_verbosity_sampler_percentage = 1,
        plugin_open_telemetry_strip_traceresponse = false,
        plugin_open_telemetry_captured_request_headers = "",
        plugin_open_telemetry_captured_response_headers = "",
        plugin_open_telemetry_record_p = false
    }
    for k, v in pairs(overrides or {}) do
        default[k] = v
    end
    return default
end

------------------------------------------------------------------------------------------------------------------------
-- Make a table that stubs out ngx.var, which is invoked throughout the plugin
------------------------------------------------------------------------------------------------------------------------
function _M.make_ngx_var(overrides)
    local default = {
        http_user_agent = "mycooluseragent",
        http_x_request_id = "",
        proxy_upstream_name = "mycoolupstream",
        request_method = "GET",
        scheme = "https",
        server_name = "mycoolserver",
        server_port = 1234,
        server_protocol = "1",
        status = 200,
        upstream_addr = "127.0.0.1:5678",
        uri = "/mycoolpath"
    }

    for k, v in pairs(overrides or {}) do
        default[k] = v
    end
    return default
end

return _M
