# load_shedder plugin for `ingress-nginx`

## Overview
Load shedding is the process of intentionally serving degraded responses or outright rejecting requests once a system is at or near its maximum capacity. It's a fundamental way of keeping a system's response time stable.

Please see: https://vault.shopify.io/page/Concepts-and-FAQ~3666.md

## Enabling
1. `load_shedder` plugin relies on `magellan` plugin to fetch its configuration, so [it must be enabled](../magellan/README.md#enabling).
2. Add `load_shedder` to [`ingress-nginx` config-map `plugins` entry](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#plugins)
3. Add these required entries to [`lua-shared-dicts` config-map entry](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#lua-shared-dicts)
    * `lua-shared-dicts: "load_shedder_config: 1M, load_shedder_quota_tracker: 30M, load_shedder_ewma: 1M, key_accounts: 32K"`
    * sizing can be adjusted based on number of upstreams being protected

## Usage
Once enabled, `load_shedder` behavior can be adjusted via spy commands: https://spy-v2.docs.shopify.io/commands/shedder.html
