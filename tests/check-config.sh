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

MODDIR="$TMP/modules"
mkdir -p "$MODDIR"
for m in common config links nodes rulesets subs generator core releases plugin panel; do
  ln -s "$SINGBOX_LITE_LIB/ucode/$m.uc" "$MODDIR/sbx_$m.uc"
done
"$UCODE_BIN" -L "$MODDIR" "$ROOT/singbox-lite/files/usr/share/singbox-lite/cli.uc" build >"$TMP/build.json"
grep -q '"ok": true' "$TMP/build.json"
"$CORE_BIN" check -c "$TMP/config.json"
# sing-box check does not catch an empty direct outbound used as a DNS detour;
# assert the generated non-empty direct-dns outbound and its use explicitly.
grep -q '"tag": "direct-dns"' "$TMP/config.json"
grep -q '"tcp_fast_open": true' "$TMP/config.json"
grep -q '"detour": "direct-dns"' "$TMP/config.json"
echo "CONFIG CHECK OK"
