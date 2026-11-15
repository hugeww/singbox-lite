#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UCODE_BIN="${UCODE_BIN:-ucode}"
CORE_BIN="${CORE_BIN:-/tmp/sing-box-1.14.4/sing-box}"
TMP="${TMPDIR:-/tmp}/singbox-lite-test.$$"

[ -x "$CORE_BIN" ] || { echo "sing-box binary not found: $CORE_BIN" >&2; exit 1; }
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

export SINGBOX_LITE_CONFIG_JSON="$ROOT/tests/cli-config.json"
export SINGBOX_LITE_ETC="$TMP"
export SINGBOX_LITE_CORE="$CORE_BIN"
export SINGBOX_LITE_LIB="$ROOT/singbox-lite/files/usr/share/singbox-lite"
export SINGBOX_LITE_ARCH="x86_64"
# Keep lock/status/log files inside the test sandbox: the host may run other
# CLI commands concurrently, and post-upgrade writes run/post-upgrade.json.
export SINGBOX_LITE_RUN_DIR="$TMP/run"
export SINGBOX_LITE_LOG_DIR="$TMP/log"
export SINGBOX_LITE_CLI="$TMP/bin/singbox-lite"

MODDIR="$TMP/modules"
mkdir -p "$MODDIR"
for m in common config links nodes rulesets subs generator core releases plugin panel; do
  ln -s "$SINGBOX_LITE_LIB/ucode/$m.uc" "$MODDIR/sbx_$m.uc"
done
# Host wrapper matching the installed /usr/bin/singbox-lite (ucode + cli.uc),
# so anything spawning PATH.cli inside the CLI runs the code under test.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/singbox-lite" <<EOF
#!/bin/sh
exec "$UCODE_BIN" -L "$MODDIR" "$SINGBOX_LITE_LIB/cli.uc" "\$@"
EOF
chmod +x "$TMP/bin/singbox-lite"
CLI_UC="$SINGBOX_LITE_LIB/cli.uc"
"$UCODE_BIN" -L "$MODDIR" "$ROOT/singbox-lite/files/usr/share/singbox-lite/cli.uc" build >"$TMP/build.json"
grep -q '"ok": true' "$TMP/build.json"
"$CORE_BIN" check -c "$TMP/config.json"
# sing-box check does not catch an empty direct outbound used as a DNS detour;
# assert the generated non-empty direct-dns outbound and its use explicitly.
grep -q '"tag": "direct-dns"' "$TMP/config.json"
grep -q '"tcp_fast_open": true' "$TMP/config.json"
grep -q '"detour": "direct-dns"' "$TMP/config.json"

# --- post-upgrade regression -------------------------------------------------
# Package upgrade with an existing config.json: rebuild succeeds from the
# current UCI/meta, reports changed=false when the deployed JSON is already up
# to date, does not rewrite the file and does not restart the service.
CONFIG_SUM="$(cksum "$TMP/config.json")"
"$UCODE_BIN" -L "$MODDIR" "$CLI_UC" post-upgrade --json >"$TMP/post-upgrade.json"
grep -q '"state": "done"' "$TMP/post-upgrade.json"
grep -q '"ok": true' "$TMP/post-upgrade.json"
grep -q '"changed": false' "$TMP/post-upgrade.json"
grep -q '"restarted": false' "$TMP/post-upgrade.json"
[ "$(cksum "$TMP/config.json")" = "$CONFIG_SUM" ]

# First install: a fresh ETC has no config.json, so the hook must skip before
# touching anything (core path points at a missing binary on purpose) and must
# never create a config or download a core/dashboard.
FIRST_ETC="$TMP/first-install"
FIRST_RUN="$TMP/first-install-run"
mkdir -p "$FIRST_ETC"
SINGBOX_LITE_ETC="$FIRST_ETC" SINGBOX_LITE_RUN_DIR="$FIRST_RUN" SINGBOX_LITE_CORE="$TMP/no-such-core" \
  "$UCODE_BIN" -L "$MODDIR" "$CLI_UC" post-upgrade --json >"$TMP/post-upgrade-first.json"
grep -q '"state": "skipped"' "$TMP/post-upgrade-first.json"
grep -q '"skipped": "first-install"' "$TMP/post-upgrade-first.json"
grep -q '"ok": true' "$TMP/post-upgrade-first.json"
[ ! -e "$FIRST_ETC/config.json" ]
[ ! -e "$FIRST_RUN/core-update.json" ]
[ ! -e "$FIRST_RUN/dashboard-update.json" ]

# Static guard: the post-upgrade implementation itself never updates/downloads
# a core, dashboard or subscriptions (first install must not fetch anything).
awk '/^function cmd_post_upgrade\(/{f=1} f{print} f&&/^}$/{exit}' "$CLI_UC" >"$TMP/cmd-post-upgrade.txt"
[ -s "$TMP/cmd-post-upgrade.txt" ]
grep -q 'first-install' "$TMP/cmd-post-upgrade.txt"
! grep -qE 'update_core|update_dashboard|refresh|download_url|shell_http_get|fetch_subscription|update_plugin' "$TMP/cmd-post-upgrade.txt"

# Static guard: package postinst runs post-upgrade only when config.json already
# exists, and never triggers curl/update-core/update-dashboard/refresh. The
# extracted snippet is unescaped and syntax-checked with sh -n.
awk '/^define Package\/singbox-lite\/postinst$/{f=1;next} f&&/^endef$/{exit} f{print}' "$ROOT/singbox-lite/Makefile" \
  | sed 's/\$\$/$/g' >"$TMP/postinst.sh"
[ -s "$TMP/postinst.sh" ]
sh -n "$TMP/postinst.sh"
grep -c 'post-upgrade --json' "$TMP/postinst.sh" | grep -qx '1'
sed -n '/\[ -f \/etc\/singbox-lite\/config.json \]/,/^fi$/p' "$TMP/postinst.sh" >"$TMP/postinst-guard.sh"
[ -s "$TMP/postinst-guard.sh" ]
grep -q 'post-upgrade --json' "$TMP/postinst-guard.sh"
! grep -qE 'curl|update-core|update-dashboard|refresh' "$TMP/postinst.sh"

# Static guard: plugin update status carries the post-upgrade result in its
# `config` field and the settings UI reads it (existence only).
grep -q 'config: post_upgrade' "$ROOT/singbox-lite/files/usr/share/singbox-lite/ucode/plugin.uc"
grep -q 'st.config' "$ROOT/luci-app-singbox-lite/htdocs/luci-static/resources/view/singbox-lite/settings.js"
grep -q 'first install' "$ROOT/luci-app-singbox-lite/htdocs/luci-static/resources/view/singbox-lite/settings.js"

echo "CONFIG CHECK OK"
