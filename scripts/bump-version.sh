#!/bin/sh
# Set the version of both packages in one place.
#
# Usage:
#   scripts/bump-version.sh            # patch bump: 0.1.0 -> 0.1.1
#   scripts/bump-version.sh minor      # 0.1.0 -> 0.2.0
#   scripts/bump-version.sh major      # 0.1.0 -> 1.0.0
#   scripts/bump-version.sh 0.2.3      # exact version
#
# Updates PKG_VERSION (and resets PKG_RELEASE) in both package Makefiles and the
# VERSION constant of the backend, so every build carries the same version.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
makefiles="$root/singbox-lite/Makefile $root/luci-app-singbox-lite/Makefile"
common="$root/singbox-lite/files/usr/share/singbox-lite/ucode/common.uc"

current=$(sed -n 's/^PKG_VERSION:=//p' "$root/singbox-lite/Makefile" | head -n 1)
if [ -z "$current" ]; then
	echo "bump-version: cannot read PKG_VERSION from singbox-lite/Makefile" >&2
	exit 1
fi

case "${1:-patch}" in
patch | minor | major)
	major=${current%%.*}
	rest=${current#*.}
	minor=${rest%%.*}
	patch=${rest#*.}
	case "$1" in
	patch) patch=$((patch + 1)) ;;
	minor) minor=$((minor + 1)); patch=0 ;;
	major) major=$((major + 1)); minor=0; patch=0 ;;
	esac
	next="$major.$minor.$patch"
	;;
*)
	next=$1
	;;
esac

if ! printf '%s' "$next" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
	echo "bump-version: version must be X.Y.Z, got '$next'" >&2
	exit 1
fi

for f in $makefiles; do
	sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$next/" "$f"
	sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=1/" "$f"
done
sed -i "s/^const VERSION = '[^']*';/const VERSION = '$next';/" "$common"

for f in $makefiles; do
	grep -q "^PKG_VERSION:=$next" "$f" || {
		echo "bump-version: failed to update $f" >&2
		exit 1
	}
done
grep -q "^const VERSION = '$next';" "$common" || {
	echo "bump-version: failed to update $common" >&2
	exit 1
}

printf '%s\n' "$next"