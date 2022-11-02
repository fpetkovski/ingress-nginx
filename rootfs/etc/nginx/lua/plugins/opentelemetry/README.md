## OpenTelemetry

This plugin makes NGINX emit spans and export them to the OpenTelemetry
collector.

There's a good amount of code in the plugin, but it's chiefly a wrapper around
[`yangxikun/opentelemetry-lua`](https://github.com/yangxikun/opentelemetry-lua).
That library is not (yet) officially part of the OpenTelemetry GitHub
organization.

`defer_to_timer.lua` and `statsd.lua` are copied from `statsd_monitor`. If we
figure out a way to share code between plugins, this duplication should be
removed.

### Configuring the plugin

This plugin's behavior can be configured using ingress-nginx's configmap. See
[`configmap.md`](docs/user-guide/nginx-configuration/configmap.md) for details.

### Enabling and disabling the plugin

Enable this plugin by adding `"opentelemetry"` to the `plugins:` configmap entry
AND setting `plugin-opentelemetry-enabled: true`.

There are two steps to enable the plugin because nginx-routing-modules requires
you to update `nginx.tmpl` and do a code deploy to enable/disable plugins (at
the time of this writing). `plugin-opentelemetry-enabled` is therefore provided
as an emergency shutoff.
