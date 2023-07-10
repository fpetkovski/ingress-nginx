local ipairs   = ipairs
local ngx      = ngx
local os       = os
local pairs    = pairs
local pcall    = pcall
local string   = string
local tostring = tostring
local type     = type
local ngx_crc32_short = ngx.crc32_short

local http   = require("resty.http")
local json   = require("cjson")
local util   = require("plugins.magellan.utils")
local timer  = require("plugins.magellan.timer")
local statsd = require("plugins.statsd.main")

local MEMORY_STRATEGIES = {
  SHARED_ONLY = 0,
  SHARED_AND_LOCAL = 1,
}

local _M = {}

local function get_regional_suffix()
  local kube_location = os.getenv("KUBE_LOCATION")
  if kube_location ~= nil then
    return kube_location:gsub("^gcp%-", ""):gsub("-", "_")
  end
  return ""
end

local regional_suffix = get_regional_suffix()

local function get_magellan_service_name(service_name)
  local using_regional = ngx.shared.registered_services_using_regional:get(service_name) or false

  if using_regional then
    return "production_ngx_config_" .. service_name .. "_" .. regional_suffix
  end
  return "production_ngx_config_" .. service_name
end

local local_service_bodies = {}
local body_mappers = {}

local function extract_body(service_data)
  local body = {}

  if service_data == nil or type(service_data['body']) ~= "table" then
    return body
  end

  for k, v in pairs(service_data['body']) do
    body[k] = v
  end

  return body
end

local function copy_service_into_local_memory(service_name)
  local shared_service_dict = ngx.shared[service_name]
  if not shared_service_dict then return end

  local_service_bodies[service_name] = {}
  for _, body_key in ipairs(shared_service_dict:get_keys(0)) do
    local raw_value = shared_service_dict:get(body_key)
    local value = util.optimistic_json_decode(raw_value)
    local_service_bodies[service_name][body_key] = value
  end
end

local function map_body(service_name, body)
  local mapper = body_mappers[service_name]
  if mapper then
    body = mapper(body)
  end
  return body
end

local function update_service(service)
  local service_dict = ngx.shared[service]
  if not service_dict then
    return
  end

  local magellan_service_name = get_magellan_service_name(service)
  local service_data, err = _M.get_service(magellan_service_name)
  if service_data == nil then
    statsd.increment("nginx.magellan_httpdb.error")
    ngx.log(ngx.WARN,
      string.format("could not retrieve service %s from Magellan: %s",
        service, err
      )
    )
    return
  end

  local body = extract_body(service_data)
  body = map_body(service, body)

  local ttl = ngx.shared.registered_services_ttl:get(service) or 0

  if ttl == 0 then
  -- remove any values that are no longer needed and will not expire via. ttl
    for _, v in ipairs(service_dict:get_keys(0)) do
      if body[v] == nil then
        service_dict:delete(v)
      end
    end
  -- otherwise, flush any expired keys
  else
    service_dict:flush_expired()
  end

  -- add any new values that are missing
  for k, v in pairs(body) do
    -- ngx.shared.DICT.set does not support table value
    -- encode it as json in such case
    -- see https://github.com/openresty/lua-nginx-module#ngxshareddictset
    if type(v) == 'table' then
      v = json.encode(v)
    end
    local ok, error, forcible
    ok, error, forcible = service_dict:set(k, v, ttl)
    if not ok then
      ngx.log(ngx.WARN,
        string.format("could not set dict value: %s, service=%s, key=%s, ttl=%s",
          error, service, k, ttl
        )
      )
    end
    if forcible then
      ngx.log(ngx.WARN,
        string.format("forced out valid key in dict to insert another, service=%s, key=%s",
          service, k
        )
      )
    end
  end

  -- Notice we don't just emit the version itself but instead emit its CRC code. One of the
  -- main features of CRC is to produce a completely different output when input changes slightly.
  -- We need that otherwise the version changes won't be visible in Datadog.
  -- For example version 5019 would be rounded to 5.02K in DD, which then would not be different
  -- than version 5020.
  statsd.gauge(
    "nginx.magellan_httpdb.version",
    ngx_crc32_short(tostring(service_data.version)),
    { service_name = service }
  )
  local ok, error, forcible = ngx.shared.registered_services_version:set(
    service, service_data.version
  )
  if not ok then
    ngx.log(ngx.WARN,
      string.format("could not set version for registered service: %s, name=%s",
        error, service
      )
    )
  end
  if forcible then
    ngx.log(ngx.WARN,
      string.format("forced out valid key in registered_services_version, service=%s",
        service
      )
    )
  end
end

local function poll_magellan()
  for _, service in ipairs(ngx.shared.registered_services:get_keys(0)) do
    update_service(service)
  end
end

local function copy_services_into_local_memory()
  for _, service_name in ipairs(ngx.shared.registered_services:get_keys(0)) do
    local memory_strategy = ngx.shared.registered_services:get(service_name)

    if memory_strategy == MEMORY_STRATEGIES.SHARED_AND_LOCAL then
      copy_service_into_local_memory(service_name)
    end
  end
end

local function set_registered_service_ttl(name, ttl)
  if type(ttl) ~= 'number' then
    ngx.log(ngx.WARN,
      string.format("could not set ttl for registered service %s, as ttl was not a number, ttl=%s",
        name, ttl
      )
    )
    return
  end

  local ok, err, _ = ngx.shared.registered_services_ttl:set(name, ttl)
  if not ok then
    ngx.log(ngx.WARN,
      string.format("could not set ttl for registered service: %s, name=%s",
        err, name
      )
    )
  end
end

local function set_registered_service_using_regional(name, using_regional)
  local ok, err, _ = ngx.shared.registered_services_using_regional:set(name, using_regional)
  if not ok then
    ngx.log(ngx.WARN,
      string.format("could not set using_regional for registered service: %s, name=%s",
        err, name
      )
    )
  end
end

-- Takes the service name to register along with optional ttl value
-- and adds it to the dict of registered_services to automatically poll and update.
--
-- Params:
-- service_name: string - the name of the service to be registered
-- ttl: number - representing ttl (in seconds) on keys in the service dict
-- copy_to_local_memory: boolean - whether the service content should be copied to local memory
-- mapper: function - maps the service body after fetching from Magellan.
--
-- Example:
-- register('banned_clients', 120)
local function register(service_name, ttl, copy_to_local_memory, mapper, uses_regional_suffix)
  local service_dict = ngx.shared[service_name]

  if not service_dict then
    ngx.log(ngx.WARN, string.format("could not find dictionary for service %s", service_name))
    return nil
  end

  if util.is_blank(service_name) then
    return nil, 'service: must pass a non-blank service name to register'
  end

  if ttl ~= nil then
    set_registered_service_ttl(service_name, ttl)
  end

  set_registered_service_using_regional(service_name, uses_regional_suffix)

  local memory_strategy = MEMORY_STRATEGIES.SHARED_ONLY -- default strategy

  if copy_to_local_memory then
    memory_strategy = MEMORY_STRATEGIES.SHARED_AND_LOCAL

    -- initialize local memory table for later use
    if local_service_bodies[service_name] == nil then
      local_service_bodies[service_name] = {}
    end
  end

  if mapper then body_mappers[service_name] = mapper end

  local ok, err, forcible = ngx.shared.registered_services:set(service_name, memory_strategy)

  if not ok then
    ngx.log(ngx.WARN,
      string.format("could not set service in registered_services: %s, service_name=%s",
        err, service_name
      )
    )
    ngx.shared.registered_services_ttl:delete(service_name)
    ngx.shared.registered_services_using_regional:delete(service_name)
  end
  if forcible then
    ngx.log(ngx.WARN,
      string.format("forced existing key out of registered_services dict, service_name=%s",
        service_name
      )
    )
  end

  return true
end

function _M.force_fetch()
  poll_magellan()

  -- In test environments, there's only one worker process, so we can just run
  -- this directly and be sure any changes are visible to the next request.
  copy_services_into_local_memory()
end

function _M.get_service(name)
  if util.is_blank(name) then
    return nil, "magellan: must pass a non-blank name to get_service"
  end

  local httpc = http.new()
  local res, err = httpc:request_uri(_M.plugin_magellan_endpoint .. "/services/" .. name,
    {
      method = "GET",
      keepalive_timeout = _M.plugin_magellan_keepalive_timeout,
      keepalive_pool = _M.plugin_magellan_keepalive_pool_size,
    })

  if not res then
    return nil, "magellan: error performing http request err=" .. tostring(err)
  end

  if res.status ~= 200 then
    return nil, string.format(
      "magellan: failed to get service status=%q body=%q",
      tostring(res.status), tostring(res.body)
    )
  end

  local ok, service = pcall(json.decode, res.body)
  if not ok then
    return nil, string.format(
      "magellan: failed to decode service body=%q err=%q",
      tostring(res.body), tostring(service)
    )
  end

  return service, nil
end

function _M.get_service_body_from_local_memory(service_name)
  return local_service_bodies[service_name]
end

function _M.get_service_version(service_name)
  return ngx.shared.registered_services_version:get(service_name)
end

function _M.register(service_name, ttl, mapper)
  return register(service_name, ttl, false, mapper, false)
end

function _M.register_with_regional_suffix(service_name, ttl, mapper)
  return register(service_name, ttl, false, mapper, true)
end

function _M.register_with_local_memory(service_name, mapper)
  return register(service_name, nil, true, mapper, false) -- no ttl, never expires
end

function _M.service_name(env, service)
  local name_pattern = "%s_" .. _M.plugin_magellan_service_identifier .. "_%s"
  return string.format(name_pattern, env, service)
end

function _M.unregister(service_name)
  ngx.shared.registered_services:delete(service_name)
  ngx.shared.registered_services_ttl:delete(service_name)
  ngx.shared.registered_services_using_regional:delete(service_name)
  ngx.shared.registered_services_version:delete(service_name)
  local_service_bodies[service_name] = nil
  return true
end

function _M.init_worker(config)
  _M.plugin_magellan_endpoint            = config.plugin_magellan_endpoint
  _M.plugin_magellan_service_identifier  = config.plugin_magellan_service_identifier
  _M.plugin_magellan_keepalive_timeout   = config.plugin_magellan_keepalive_timeout
  _M.plugin_magellan_keepalive_pool_size = config.plugin_magellan_keepalive_pool_size
  _M.plugin_magellan_timer_poll_interval = config.plugin_magellan_timer_poll_interval

  timer.execute_at_interval(
    _M.plugin_magellan_timer_poll_interval, false, poll_magellan
  ) -- runs in worker0 only
  timer.execute_at_interval(
    _M.plugin_magellan_timer_poll_interval, true, copy_services_into_local_memory
  ) -- runs in all workers

  return true, nil
end

return _M
