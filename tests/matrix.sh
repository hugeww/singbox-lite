#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UCODE_BIN="${UCODE_BIN:-ucode}"
CORE_BIN="${CORE_BIN:-/tmp/sing-box-1.14.4/sing-box}"
TMP="${TMPDIR:-/tmp}/singbox-lite-matrix.$$"
MODDIR="$TMP/modules"

[ -x "$CORE_BIN" ] || { echo "sing-box binary not found: $CORE_BIN" >&2; exit 1; }
mkdir -p "$TMP" "$MODDIR"
trap 'rm -rf "$TMP"' EXIT

for m in common config links nodes rulesets subs generator core; do
	ln -s "$ROOT/singbox-lite/files/usr/share/singbox-lite/ucode/$m.uc" "$MODDIR/sbx_$m.uc"
done

run_case() {
	name="$1"
	dns_mode="$2"
	sed "s/\"mode\": \"split\"/\"mode\": \"$dns_mode\"/" "$ROOT/tests/cli-config.json" >"$TMP/case.json"
	SINGBOX_LITE_CONFIG_JSON="$TMP/case.json" \
	SINGBOX_LITE_ETC="$TMP/etc" \
	SINGBOX_LITE_CORE="$CORE_BIN" \
	SINGBOX_LITE_LIB="$ROOT/singbox-lite/files/usr/share/singbox-lite" \
	SINGBOX_LITE_ARCH="x86_64" \
	"$UCODE_BIN" -L "$MODDIR" "$ROOT/singbox-lite/files/usr/share/singbox-lite/cli.uc" build >"$TMP/out.json"
	grep -q '"ok": true' "$TMP/out.json"
	"$CORE_BIN" check -c "$TMP/etc/config.json"
	echo "OK: $name"
}

run_case "dns split" split
run_case "dns system" system
run_case "dns proxy" proxy

echo "MATRIX OK"
