local json = require("cjson")

function set_tenant_override(tenant_type, tenant_id, override_key, expire_at, value)
  local json_config = {}

  -- merge with any existing override
  local configs_data = ngx.shared.load_shedder_config:get(tenant_type)
  if configs_data then
    _, json_config = pcall(json.decode, configs_data)
  end

  local tenant_config = json_config[tenant_id] or {}
  tenant_config[override_key] = { value = value, expire_at = expire_at }
  json_config[tenant_id] = tenant_config

  local ok, result = pcall(json.encode, json_config)
  if not ok then
    assert(false)
  end

  ngx.shared.load_shedder_config:set(tenant_type, result)
end

function set_tenancy_override(tenant_type, tenant_id, expire_at, tenancy)
  set_tenant_override(tenant_type, tenant_id, 'tenancy', expire_at, tenancy)
end

function set_tenant_share_override(tenant_type, tenant_id, expire_at, tenant_share)
  set_tenant_override(tenant_type, tenant_id, 'tenant_share', expire_at, tenant_share)
end
