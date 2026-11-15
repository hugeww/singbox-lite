# sing-box Lite (OpenWrt 25.12+)

A lightweight TUN + auto_redirect sing-box manager for LuCI. It converts airport subscriptions and self-hosted VPS nodes into a sing-box configuration, with configurable rule sets, country/custom egress groups, scheduled refresh and core updates. sing-box owns the transparent-proxy rules (`tun` + `auto_route` + `auto_redirect`); the plugin never writes fw4 rules. `auto_redirect` writes its compatibility file under `/etc/nftables.d` and reloads fw4 on start/stop.

## Features

- Multiple airport subscriptions and manual VPS nodes in one node pool.
- Subscription formats: base64 / URI lists, sing-box JSON, Clash YAML (requires `yq`).
- Configurable rule sets: built-in CN/AI/streaming/social/dev sets, plus inline domain/IP lists, remote `.srs` URLs and local `.srs` paths.
- Configurable egress groups: direct, auto, default, US/Japan/Hong Kong/Other, native and custom selector/urltest groups.
- Routing = ordered "rule set → egress group" rules; custom rules run before built-in rules.
- TUN runtime: `tun` + `auto_route` + `auto_redirect`; no `mixed` proxy port is exposed and LAN clients need no manual proxy setting.
- Save/apply separation: save & check writes a `config.json` draft only; start/restart deploys `active.json`, which is what procd respawns, so an unconfirmed save never goes live.
- Concurrency guard: build/check/refresh, core/plugin/dashboard updates are serialized by a CLI lock, so cron and manual actions cannot overwrite each other.
- Bounded downloads and logs: subscriptions are capped at 5 MB, remote `.srs` at 16 MB and checked for the `SRS` magic; `log_max_kb` truncates the log at service start and log files are root-only.
- Kernel-level CN bypass: `geoip-cn` is added to `route_exclude_address_set`, so direct CN destinations never enter sing-box connection handling.
- DNS hijack with split: domestic DNS goes to `223.5.5.5` directly, everything else goes through DoH over the proxy.
- `strict_route` is off by default: router DHCP/PPPoE relies on `SO_BINDTODEVICE`; enabling it captures that traffic too. Turn it on only when stricter leak prevention is needed.
- Scheduled subscription refresh with `sing-box check`, optional automatic restart and rollback safety; unchanged content does not trigger a restart, and a failed restart restores the previous config.
- Core manager: requires sing-box >= 1.14.4, downloads GitHub releases, verifies, atomically installs and rolls back on failure.
- Version manager: shows the installed core and plugin versions, lists GitHub release tags, and updates either of them from the Settings page (the plugin is reinstalled with apk).
- Live panel: the official [sing-box dashboard](https://github.com/SagerNet/sing-box-dashboard) is served by the **sing-box API service** (`services[type=api]` / `dashboard`) at `/dashboard/` and uses gRPC-Web, not the Clash API. A built-in LuCI panel (traffic, connections, proxy-group switching, latency tests) uses the Clash API as the alternative. The API/Clash API listens on `0.0.0.0:9090` with a random secret by default.
- LuCI pages: Overview, Panel, Subscriptions, Nodes, Rule Sets & Routing, Egress Groups, Settings, Logs.
- Config preview/download: Overview previews the generated sing-box JSON and can download it as `singbox-lite-config.json`; preview is read-only and does not write `/etc/singbox-lite/config.json`.

## Requirements

- OpenWrt 25.12+ with apk; 24.10 is best-effort only.
- ~120 MB free space for the full sing-box binary and its compressed archive.
- Kernel modules: `kmod-tun`, `kmod-nft-core` (includes `nft_redir`), `kmod-nft-nat`, `kmod-nft-queue`, `kmod-nfnetlink-queue`. The apk dependencies pull them in; custom images must build them in. Without `kmod-nft-queue`/`kmod-nfnetlink-queue`, redirect still works but pre-match (the CN bypass) is disabled.
- firewall4/nftables (the OpenWrt 25.12 default); fw3/iptables is not supported.
- Do not combine with mwan3, passwall or other fwmark-based policy routing/transparent proxies; auto_redirect conflicts with `route.default_mark` and `dialOptions.routing_mark`.
- Starting/stopping sing-box triggers one `fw4 reload`, which is expected.
- fw4 software/hardware flow offloading and auto_redirect may or may not coexist depending on kernel/driver; disable offload for the first validation run, then re-enable once confirmed.
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

Open **Services → sing-box Lite**, install/update the core, add subscriptions/nodes, save & check, then start. On start, the router and LAN-forwarded traffic are captured automatically; clients need no manual proxy port. For a bypass-router setup, point client gateways at this router.

## Config save and apply

- "Save & check config" writes the `config.json` draft only; it does not touch the running configuration.
- Start/restart deploys the draft to `active.json`; procd runs and respawns from that file.
- A saved draft therefore needs a restart to take effect, and a crash/respawn cannot apply an unconfirmed draft.
- Scheduled refresh compares the generated config with the current one: unchanged content does not restart; a failed restart restores `config.json.bak` and starts again.

## Panel

The panel type is selected in Settings:

- **Official sing-box dashboard (default)**: served by the sing-box API service (`services[type=api]`) at `http://<router>:9090/dashboard/`. It is a gRPC-Web client of the sing-box API, not a Clash dashboard; it will not work through `experimental.clash_api.external_ui`. Download the dashboard files to `/etc/singbox-lite/ui`, save and restart.
- **Built-in LuCI panel**: the backend proxies the Clash API (`experimental.clash_api`); traffic, connections, group switching and latency tests stay inside LuCI.

Both modes use the same `listen:port` (`0.0.0.0:9090` by default) and are mutually exclusive. To use metacubexd/yacd, select the built-in mode, listen on `0.0.0.0`, restart, and open the port in the firewall yourself.

The panel page shows the **panel URL** (`IP:port/dashboard/`), the **backend API URL** (`IP:port`) and the **API secret** (with a copy button). In built-in mode it shows the Clash API backend URL and secret instead.

## Editing configuration

There is no separate JSON editor. UCI is the config source; Overview's "Save & Check Config" only compiles the UCI intent into `config.json` and runs `sing-box check`. Edit the source pages instead:

- **Subscriptions**: airport URLs, UA and format.
- **Nodes**: manual share links/outbound JSON and country/native overrides.
- **Rule Sets & Routing**: rule-set content, enable state, target egress group and order.
- **Egress Groups**: custom selector/urltest groups, members and default node.
- **Settings**: log, DNS mode, TUN, panel and core/plugin updates.

Save the page, then use "Save & Check Config" on Overview. Editing `/etc/singbox-lite/config.json` directly is possible via SSH, but the next save or scheduled refresh regenerates and overwrites it. A raw JSON editor is not part of the current design; the project deliberately keeps UCI forms as the source of truth.

## Build and release

Plain pushes never build. A build runs only when it is requested: manually (Actions → `build` → `Run workflow`, artifacts only) or by pushing a `v*` version tag, which also publishes the GitHub Release that the plugin self-update reads (`singbox-lite-<arch>-openwrt-25.12.tar.gz`).

Every build carries a new version. `scripts/bump-version.sh` keeps `PKG_VERSION`/`PKG_RELEASE` in both package Makefiles and the backend `VERSION` in sync:

```sh
scripts/bump-version.sh patch   # 0.1.1 -> 0.1.2
git commit -am "release: 0.1.2"
git tag v0.1.2
git push origin main v0.1.2
```

The workflow fails when the tag does not match `PKG_VERSION`, and a manual build without an explicit version uses the next patch after the latest tag.

## Tests

The host harness is `tests/run.uc`; `tests/check-config.sh` and `tests/matrix.sh` run `sing-box check` against sing-box 1.14.4. See [tests/README.md](tests/README.md).

```sh
mkdir -p /tmp/sbxmods
for m in common config links nodes rulesets subs generator core releases plugin panel; do
  ln -sf "$PWD/singbox-lite/files/usr/share/singbox-lite/ucode/$m.uc" "/tmp/sbxmods/sbx_$m.uc"
done
ucode -L /tmp/sbxmods tests/run.uc
```

## Limitations

- One generated configuration; no profile/multi-config switching. `active.json` is the save/apply runtime copy, not a profile.
- No FakeIP or access control; domain routing depends on sniffing, and unrecognised traffic falls back to IP rules/default group.
- No TPROXY/redirect inbound; only TUN + auto_redirect.
- The plugin does not manage fw4 zones/NAT; sing-box owns its `inet sing-box` table and nftables compatibility file.
- Plugin self-update consumes `singbox-lite-<arch>-openwrt-25.12.tar.gz` from GitHub Releases; only x86_64 and aarch64_cortex-a53 are built.
- Clash YAML conversion needs `yq` (not a hard dependency).

## Documentation

See [README.md](README.md) for the full Chinese documentation, data paths, rule/egress model and build instructions.

## License

GPL-3.0-or-later. Bundled [sing-geosite](https://github.com/SagerNet/sing-geosite) and [sing-geoip](https://github.com/SagerNet/sing-geoip) rule sets are GPL-3.0; see the LICENSE files under the rulesets directory.
