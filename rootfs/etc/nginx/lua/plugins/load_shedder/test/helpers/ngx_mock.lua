ngx.shopify = { location = "local" }

local _shared_dict = { __index = {
    get_stale = function(self, key)
        if key == nil then error("nil key") end
        return self._vals[key], {}, false
    end,
    get = function(self, key)
        if key == nil then error("nil key") end
        return self._vals[key]
    end,
    set = function(self, key, val, expires)
        if key == nil then error("nil key") end
        self._vals[key] = val
        return true, nil, false
    end,
    delete = function(self, key)
        return self:set(key, nil)
    end,
    incr = function(self, key, val)
        if not self:get(key) then return nil, "not found" end
        self:set(key, self:get(key) + val)
        return self:get(key), nil
    end,
    add = function(self, key, val)
        if self:get(key) then return false, "exists", false end
        return self:set(key, val)
    end,
    get_keys = function(self, count)
        local keys = {}
        for key, _ in pairs(self._vals) do
          table.insert(keys, key)
        end
        return keys
    end
}}

local _ngx = {
    req = {},
    header = {},
    arg = {},
    shared = {},
    socket = {},
    thread = {},
    timer = {},
    var = {},
    worker = {},
    null = "7abdd51e-b6c4-40ea-a16a-00ae69ccfd94", -- hopefully not duplicated
    _req_headers = {},
    _logs = {},
    _args = {},
    _threads = {},
    _now = 0,
    ctx = {},
    HTTP_BAD_REQUEST = 400,
    HTTP_INTERNAL_SERVER_ERROR = 500,
    HTTP_GATEWAY_TIMEOUT = 504,
    upstream = {
      get_upstreams = function()
        return {
          "shopify_pod_0_pool",
          "shopify_pod_1_pool",
          "shopify_pool",
          "dynamic_test_pool",
          "alt_dynamic_test_pool",
          "override"
        }
      end,
      get_primary_peers = function(pool)
        if not string.match(pool, "dynamic_test_pool") then return {} end

        return {
          { name="127.0.0.1" },
          { name="127.0.0.2" },
          { name="127.0.0.3", weight=2 }
        }
      end,
    },
}

_ngx.WARN = 1
_ngx.ERR = 2

_ngx.OK = 0
_ngx.HTTP_OK = 200
_ngx.HTTP_MOVED_PERMANENTLY = 301
_ngx.HTTP_MOVED_TEMPORARILY = 302
_ngx.HTTP_NOT_MODIFIED = 304
_ngx.HTTP_FORBIDDEN = 403
_ngx.HTTP_NOT_FOUND = 404
_ngx.HTTP_TOO_MANY_REQUESTS = 429
_ngx.HTTP_CLOSE = 444

function _ngx.reset()
    _ngx._logs = {}
    _ngx._queued_timers = {}
    _ngx._req_headers = {}
    _ngx.arg = {}
    _ngx._args = {}
    _ngx._post_args = {}
    _ngx._threads = {}
    _ngx.shared.balancer = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.balancer_ewma = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.balancer_ewma_last_touched_at = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.balancer_ewma_locks = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.balancer_algorithm = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.cached_config_fixture = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.config = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.dicts_test = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.external_upstreams = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.error_page_mapping_config = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.load_shedder_config = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.load_shedder_quota_tracker = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.load_shedder_ewma = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.pod_id_cache = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.pod_to_upstream = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.pods_state = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.profiled_sessions = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.profiling_sessions_rate_tracker = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.registered_services = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.registered_services_ttl = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.registered_services_version = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.registered_services_using_regional = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.shop_id_cache = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.customer_account_cache = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.user_agent_cache = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.waf_banned_clients = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.healthcheck_worker_events = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.healthcheck = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.apps_domain_hosts_to_load_balancer_names = setmetatable({_vals = {}}, _shared_dict)
    _ngx.shared.load_balancer_rewrites = setmetatable({_vals = {}}, _shared_dict)
    _ngx._method = "GET"
    _ngx.var = {}
    _ngx.var.uri = "/"
    _ngx.var.scheme = 'http'
    _ngx.var.hostname = "nginx"
    _ngx.var.remote_addr = "127.0.0.1"
    _ngx.printed = nil
    _ngx.exit_code = nil
    _ngx.redirect_location = nil
    _ngx.ctx = {}
    _ngx.location = {}
    _ngx._phase = "access"
    _ngx._http_version = "1.1"
end

function _ngx.log(a, ...)
    table.insert(_ngx._logs, {...})
end

function _ngx.req.get_method()
    return _ngx._method
end

function _ngx.req.get_headers()
    return _ngx._req_headers
end

function _ngx.req.clear_header(header)
    _ngx._req_headers[header] = nil
    _ngx.var[convert_to_var_header_name(header)] = nil
end

function _ngx.req.set_header(header, value)
    _ngx._req_headers[header] = value
    _ngx.var[convert_to_var_header_name(header)] = value
end

function _ngx.req.get_uri_args()
    return _ngx._args
end

function _ngx.req.set_uri_arg(key, value)
    _ngx._args[key] = value
end

function _ngx.req.get_post_args()
    return _ngx._post_args
end

function _ngx.req.http_version()
    return _ngx._http_version
end

function _ngx.req.read_body()
end

function convert_to_var_header_name(header_name)
  local var_name = string.gsub(header_name, "-", "_")
  return "http_" .. string.lower(var_name)
end

local function strip_regex_compile_from_options(options)
    -- The "j"and "o" options are not available in lrexlib-PCRE which we use
    -- for testing
    if options then
        return (options:gsub("[jo]", ""))
    end
end

-- Build a char->hex map
local escapes = {}
for i = 0, 255 do
    escapes[string.char(i)] = string.format("%%%02X", i)
end

function _ngx.unescape_uri(str)
    if not str then return end
    return (str:gsub("%%(%x%x)", function (hex) return string.char(tonumber(hex, 16)) end))
end

function _ngx.print(str)
    _ngx.printed = str
end

function _ngx.send_headers() end

function _ngx.quote_sql_str(str)
  return str
end

function _ngx.now()
    return os.time()
end

function _ngx.time()
  return os.time()
end

function _ngx.cookie_time(seconds)
  return os.date("%a, %d-%b-%y %H:%M:%S GMT", seconds)
end

function _ngx.parse_http_time(str)
    -- example: "Fri, 06 Jul 2035 19:44:51 -0000"
    local day, month_name, year, hour, min, sec = str:match("^%w+, (%d+) (%w+) (%d+) (%d+):(%d+):(%d+)")
    if day == nil then return nil end
    local months = {Jan=1, Feb=2, Mar=3, Apr=4, May=5, Jun=6, Jul=7, Aug=8, Sep=9, Oct=10, Nov=11, Dec=12}
    local month = months[month_name]
    if month == nil then return nil end

    local local_time = os.time{year=year, month=month, day=day, hour=hour, min=min, sec=sec, isdst=false}
    local tz_offset = os.difftime(local_time, os.time(os.date("!*t", local_time)))

    return local_time + tz_offset
end

-- this is NOT a real thread, but should be good enough to emulate current cacheable behaviour
function _ngx.thread.spawn(func, ...)
    local co = coroutine.create(func)
    _ngx._threads[co] = { ... }
    return co
end

function _ngx.thread.wait(th)
    assert(type(th) == 'thread')
    return coroutine.resume(th, unpack(_ngx._threads[th]))
end

local tcpsock = {
    connect = function(self, host, port, options_table) return 1; end,
    send = function(self, data) return string.len(tostring(data)); end,
    receive = function(self, size) return 0; end,
    settimeout = function(self, time) return true; end,
    setkeepalive = function(self, time) return true; end
}

local tcpsock_mt = {
    __index = tcpsock
}

_ngx.socket.tcpsock = tcpsock

function _ngx.socket.tcp()
    return setmetatable({}, tcpsock_mt)
end

function _ngx.timer.at(delay, func, ...)
    if delay == 0 then
        -- premature argument is false
        func(false, ...)
    else
        table.insert(_ngx._queued_timers, { delay = delay, func = func, args = {...} })
    end
    return true
end

function _ngx.timer.every(delay, func, ...)
    assert(delay ~= 0)
    table.insert(_ngx._queued_timers, { delay = delay, func = func, args = {...} })
    return true
end

function _ngx.timer.pending_count()
    return #_ngx._queued_timers
end

function _run_queued_timers(premature)
    local queue = _ngx._queued_timers
    _ngx._queued_timers = {}
    for _, timer in ipairs(queue) do
        timer.func(premature, unpack(timer.args))
    end
end

function _ngx.print(body)
    return true, nil
end

function _ngx.say(body)
  return _ngx.print(body)
end

function _ngx.sleep(seconds)
    return
end

function _ngx.hmac_sha1(key, data)
    return key .. data
end

function _ngx.encode_base64(blob)
    return blob
end

function _ngx.worker.id()
  return 0
end

function _ngx.worker.pid()
  return 1
end

function _ngx.worker.exiting()
  return false
end

function _ngx.get_phase()
  return _ngx._phase
end

function _ngx.encode_args(table)
  local args = ''
  for k, v in pairs(table) do
    args = args .. k .. '=' .. v .. '&'
  end

  return args:sub(1, -2)
end

local mt = {}
mt.__index = ngx
setmetatable(_ngx, mt)

return _ngx
