## shopify-localdev

This directory contains some files that can help you develop Lua plugins in this repository.

### TL;DR

```
podman-compose -f shopify-localdev build # build localdev containers
dev server # starts nginx
curl localhost:1024 # hits backing service via nginx
```

### Tips

- Changes to Lua files and/or `nginx.conf.dev` require an nginx reload, hit it with a `podman ps | grep nginx-dev | awk '{print $1}' | xargs -I"{}" podman exec {} nginx -s reload`
- You may need to comment out some methods in lua plugins to avoid too much log noise (e.g. `local function send(payload)` in `monitor.lua`)
- You may want to run the nginx server in the foreground, you can run `podman-compose -f shopify-localdev/podman-compose.yml run --service-ports nginx-dev` to do this
- You may want to use a debugger, I like [this one](https://github.com/slembcke/debugger.lua)
- YMMV, PRs welcome :)
