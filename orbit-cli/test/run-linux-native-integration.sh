#!/bin/sh
set -eu

format=${1:?usage: run-linux-native-integration.sh deb|rpm|arch}
case "$format" in
  deb|rpm|arch) ;;
  *) echo "unsupported format: $format" >&2; exit 2 ;;
esac

repository=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

node "$repository/orbit-cli/scripts/linux-native-fixture.mjs" "$format" "$work/first"
node "$repository/orbit-cli/scripts/linux-native-fixture.mjs" "$format" "$work/second"
artifact=$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).artifact)' "$work/first/result.json")
second=$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).artifact)' "$work/second/result.json")
cmp "$artifact" "$second"

extract="$work/extract"
mkdir -p "$extract"
case "$format" in
  deb)
    dpkg-deb --info "$artifact" >/dev/null
    dpkg-deb --contents "$artifact" | grep -q 'usr/bin/orbit-native-fixture'
    dpkg-deb --field "$artifact" Depends | grep -q 'libwebkit2gtk-4.1-0'
    dpkg-deb --extract "$artifact" "$extract"
    ;;
  rpm)
    rpm -qpi "$artifact" >/dev/null
    rpm -qpl "$artifact" | grep -q '/usr/bin/orbit-native-fixture'
    rpm -qpR "$artifact" | grep -q 'webkit2gtk4.1'
    (cd "$extract" && rpm2cpio "$artifact" | cpio -idm --quiet)
    ;;
  arch)
    pacman -Qip "$artifact" >/dev/null
    pacman -Qip "$artifact" | grep -q 'webkit2gtk-4.1'
    bsdtar -tf "$artifact" | grep -q 'usr/bin/orbit-native-fixture'
    bsdtar -xf "$artifact" -C "$extract"
    ;;
esac

desktop="$extract/usr/share/applications/dev.orbit.nativefixture.desktop"
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$desktop"
else
  grep -q '^Type=Application$' "$desktop"
  grep -q '^Exec=orbit-native-fixture$' "$desktop"
fi
node "$repository/orbit-cli/bin/orbit.mjs" verify-package \
  --package-dir "$extract/usr/lib/dev.orbit.nativefixture"
"$extract/usr/lib/dev.orbit.nativefixture/bin/orbit-native-fixture" | grep -qx 'orbit-native-fixture'
node "$repository/orbit-cli/bin/orbit.mjs" verify-linux-package --artifact "$artifact"

echo "$format native package integration passed"
