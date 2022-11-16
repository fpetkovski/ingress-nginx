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

### Enabling and disabling the plugin globally

Disable this plugin by removing `"opentelemetry"` from the `plugins: ` configmap
entry OR setting `plugin-opentelemetry-bypassed-upstreams: "all"`.`

Enable this plugin by adding `"opentelemetry"` to the `plugins:` configmap entry
AND setting `plugin-opentelemetry-bypassed-upstreams: ""`.

There are two steps to enable the plugin because nginx-routing-modules requires
you to update `nginx.tmpl` and do a code deploy to enable/disable plugins (at
the time of this writing). `plugin-opentelemetry-bypassed-upstreams` is
therefore provided as an emergency shutoff.

### Disabling the plugin for individual upstreams

To disable the plugin for an individual NGINX upstream (i.e. an app), add that
app's name to the `plugin-opentelemetry-bypassed-upstreams` configmap entry. It
is a comma-separated list. So if you were trying to bypass `arrive-server` and
`kepler`, you'd set `plugin-opentelemetry-bypassed-upstreams:
"arrive-server,kepler`. This works on a regex match, so you could also do
`plugin-opentelemetry-bypassed-upstreams: "arrive-s,kepl"`.

### Enabling deferred sampling

To enable deferred sampling for an upstream, use
`plugin-opentelemetry-deferred-sampling-upstreams`. Like `bypassed-upstreams`,
it is a comma-separated list whose constituent elements are regex-matched. So to
enable deferred sampling for `core`, you would set
`plugin-opentelemetry-deferred-sampling-upstreams: core`
