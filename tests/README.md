# Tests

The backend is plain ucode and is testable on a Linux host with the `ucode` interpreter.

## Build a host ucode

```sh
git clone --depth 1 https://github.com/jow-/ucode /tmp/ucode
cmake -S /tmp/ucode -B /tmp/ucode/build \
  -DCMAKE_BUILD_TYPE=Release \
  -DUCI_SUPPORT=OFF -DUBUS_SUPPORT=OFF -DULOOP_SUPPORT=OFF \
  -DRTNL_SUPPORT=OFF -DNL80211_SUPPORT=OFF -DZLIB_SUPPORT=OFF
cmake --build /tmp/ucode/build -j"$(nproc)"
```

On Debian/Ubuntu install `cmake libjson-c-dev gcc make` first.

## Run unit tests

```sh
export LD_LIBRARY_PATH=/tmp/ucode/build/lib
export SINGBOX_LITE_LIB="$PWD/singbox-lite/files/usr/share/singbox-lite"
export SINGBOX_LITE_ETC=/tmp/singbox-lite-test
export SINGBOX_LITE_TESTDIR="$PWD"
mkdir -p /tmp/sbxmods
for m in common config links nodes rulesets subs generator core releases plugin panel; do
  ln -sf "$SINGBOX_LITE_LIB/ucode/$m.uc" "/tmp/sbxmods/sbx_$m.uc"
done
/tmp/ucode/build/ucode -L /tmp/sbxmods tests/run.uc
```

## Generated config check

Needs a sing-box >= 1.14.4 binary:

```sh
UCODE_BIN=/tmp/ucode/build/ucode \
CORE_BIN=/tmp/sing-box-1.14.4/sing-box \
tests/check-config.sh
```

The script builds `tests/cli-config.json` (a TUN + auto_redirect config), runs `sing-box check`, and fails on any error.

## Config matrix

```sh
UCODE_BIN=/tmp/ucode/build/ucode \
CORE_BIN=/tmp/sing-box-1.14.4/sing-box \
tests/matrix.sh
```

It checks generated configs for DNS modes `split`, `system` and `proxy`; the inbound is always `tun` with `auto_route`/`auto_redirect`.
