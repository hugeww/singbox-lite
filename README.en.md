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
- Live panel: serves the official [sing-box dashboard](https://github.com/SagerNet/sing-box-dashboard) through `clash_api.external_ui` (default), with a built-in LuCI panel (traffic, connections, proxy-group switching, latency tests) as the alternative; the Clash API listens on `0.0.0.0:9090` with a random secret.
- LuCI pages: Overview, Panel, Subscriptions, Nodes, Rule Sets & Routing, Egress Groups, Settings, Logs.

## Requirements

- OpenWrt 25.12+ with apk; 24.10 is best-effort only.
- ~100 MB free space for the full sing-box binary.
- A GitHub mirror is recommended in mainland China (configurable in Settings).

## Install

```sh
apk add --allow-untrusted ./singbox-lite-*.apk ./luci-app-singbox-lite-*.apk
apk add --allow-untrusted ./luci-i18n-singbox-lite-zh-cn-*.apk   # optional: Simplified Chinese UI
```

`apk add` does not execute the `uci-defaults` shipped in the language pack, so the language is only registered on the next boot. Activate it explicitly, otherwise the UI stays English:

```sh
/etc/uci-defaults/luci-i18n-singbox-lite-zh-cn
uci set luci.main.lang=zh_cn && uci commit luci
rm -f /tmp/luci-indexcache
```

Then force-reload the browser (Ctrl+F5): page strings come from `/cgi-bin/luci/admin/translations/<lang>`, which carries no version parameter.

Open **Services → sing-box Lite**, install/update the core, add subscriptions/nodes, save & check, then start.

## Build and release

Plain pushes never build. A build runs only when it is requested: manually (Actions → `build` → `Run workflow`, artifacts only) or by pushing a `v*` version tag, which also publishes the GitHub Release that the plugin self-update reads (`singbox-lite-<arch>-openwrt-25.12.tar.gz`).

Every build carries a new version. `scripts/bump-version.sh` keeps `PKG_VERSION`/`PKG_RELEASE` in both package Makefiles and the backend `VERSION` in sync:

```sh
scripts/bump-version.sh patch   # 0.1.0 -> 0.1.1
git commit -am "release: 0.1.1"
git tag v0.1.1
git push origin main v0.1.1
```

The workflow fails when the tag does not match `PKG_VERSION`, and a manual build without an explicit version uses the next patch after the latest tag.

## Documentation

See [README.md](README.md) for the full Chinese documentation, data paths, rule/egress model and build instructions.

## License

GPL-3.0-or-later. Bundled [sing-geosite](https://github.com/SagerNet/sing-geosite) and [sing-geoip](https://github.com/SagerNet/sing-geoip) rule sets are GPL-3.0; see the LICENSE files under the rulesets directory.
