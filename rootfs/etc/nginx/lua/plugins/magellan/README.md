# Magellan plugin for `ingress-nginx`

## Overview
This plugin enables nginx lua to read data from [Magellan key-value store](https://github.com/Shopify/magellan), and keep such data in-sync in nginx worker memory through periodic polling.

## Enabling
1. Add `magellan` to [`ingress-nginx` config-map `plugins` entry](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#plugins)
2. Add these required entries to [`lua-shared-dict` config-map entry](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#lua-shared-dicts)
    * `lua-shared-dicts: "registered_services: 512K, registered_services_ttl: 16K, registered_services_version: 16K, registered_services_using_regional: 16K"`
    * update sizing of these dicts as appropriate for the number of services being registered.
3. Configure additional plugin options in config-map:
    * `plugin-magellan-endpoint`: `string` the endpoint to which the magellan plugin will send magellan related requests
    * `plugin-magellan-keepalive-timeout`: `int` the keepalive idle timeout in milliseconds which the plugin will attempt to reuse connections to the magellan endpoint
    * `plugin-magellan-keepalive-pool-size`: `int` the maximum size of the keepalive pool
    * `plugin-magellan-service-identifier`: `string` the service identifier that will be used to construct the service name in magellan, in the form: `production_<PluginMagellanServiceIdentifier>_<servicename>`
    * `plugin-magellan-timer-poll-interval`: `(float32)` the time in seconds between polls of the magellan service

## Usage
Once enabled, magellan data can be grabbed via:

```lua
local magellan = require("plugins.magellan.main")
local service_name = "some_service_name"

local service_data = magellan.get_service(name)
```

Or kept in sync in `ngx.shared` with a timer poll via:
```lua
local magellan = require("plugins.magellan.main")
local service_name = "some_service_name"

magellan.register(service_name)
```

and later retrieved via:
```lua
value = ngx.shared.some_service_name:get("some_key")
```
