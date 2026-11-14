# sing-box Lite (OpenWrt 25.12+)

A lightweight, bare-core sing-box manager for LuCI. It converts airport subscriptions and self-hosted VPS nodes into a sing-box configuration, with configurable rule sets, country/custom egress groups, scheduled refresh and core updates. It does not manage firewall/NAT or generate TUN/TPROXY.

## Features

- Multiple airport subscriptions and manual VPS nodes in one node pool.
- Subscription formats: base64 / URI lists, sing-box JSON, Clash YAML (requires `yq`).
- Configurable rule sets: built-in CN/AI/streaming/social/dev sets, plus inline domain/IP lists, remote `.srs` URLs and local `.srs` paths.
- Configurable egress groups: direct, auto, default, US/Japan/Hong Kong/Other, native and custom selector/urltest groups.
- Routing = ordered "rule set → egress group" rules; custom rules run before built-in rules.
- Bare-core runtime: a single `mixed` inbound; no firewall/network/dhcp changes.
- Scheduled subscription refresh with `sing-box check`, optional automatic restart and rollback safety.
- Core manager: requires sing-box >= 1.14.4, downloads GitHub releases, verifies, atomically installs and rolls back on failure.
- Version manager: shows the installed core and plugin versions, lists GitHub release tags, and updates either of them from the Settings page (the plugin is reinstalled with apk).
- Live panel: real-time traffic, connection count, proxy-group switching and latency tests, and a connection list, powered by the sing-box Clash API (bound to `127.0.0.1` with a random secret and proxied through LuCI).
- LuCI pages: Overview, Panel, Subscriptions, Nodes, Rule Sets & Routing, Egress Groups, Settings, Logs.

## Requirements

- OpenWrt 25.12+ with apk; 24.10 is best-effort only.
- ~100 MB free space for the full sing-box binary.
- A GitHub mirror is recommended in mainland China (configurable in Settings).

## Install

```sh
apk add --allow-untrusted ./singbox-lite-*.apk ./luci-app-singbox-lite-*.apk
```

Open **Services → sing-box Lite**, install/update the core, add subscriptions/nodes, save & check, then start.

## Documentation

See [README.md](README.md) for the full Chinese documentation, data paths, rule/egress model and build instructions.

## License

GPL-3.0-or-later. Bundled [sing-geosite](https://github.com/SagerNet/sing-geosite) and [sing-geoip](https://github.com/SagerNet/sing-geoip) rule sets are GPL-3.0; see the LICENSE files under the rulesets directory.
