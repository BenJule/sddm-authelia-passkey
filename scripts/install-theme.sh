#!/bin/bash
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "must run as root" >&2; exit 1; }

BASE=/usr/share/sddm/themes/debian-breeze
DEST=/usr/share/sddm/themes/debian-breeze-authelia-passkey
THEMES=/usr/share/sddm/themes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/theme/Main.qml.patch" ]; then
    PATCH_DIR="$SCRIPT_DIR/theme"
elif [ -f "$SCRIPT_DIR/../theme/debian-breeze-authelia-passkey-patch/Main.qml.patch" ]; then
    PATCH_DIR="$SCRIPT_DIR/../theme/debian-breeze-authelia-passkey-patch"
else
    echo "theme patches not found" >&2
    exit 1
fi

[ -d "$BASE" ] || { echo "pristine Debian Breeze theme not found: $BASE" >&2; exit 1; }
[ -f "$BASE/Main.qml" ] || { echo "pristine Breeze Main.qml missing" >&2; exit 1; }
[ -f "$BASE/metadata.desktop" ] || { echo "pristine Breeze metadata.desktop missing" >&2; exit 1; }
[ -f "$PATCH_DIR/Main.qml.patch" ] || { echo "Main.qml.patch missing" >&2; exit 1; }
[ -f "$PATCH_DIR/metadata.desktop.patch" ] || { echo "metadata.desktop.patch missing" >&2; exit 1; }

[ ! -L "$DEST" ] || { echo "refusing to replace symlink destination: $DEST" >&2; exit 1; }
if [ -e "$DEST" ] && [ ! -d "$DEST" ]; then
    echo "refusing to replace non-directory destination: $DEST" >&2
    exit 1
fi

TMP="$(mktemp -d "$THEMES/.debian-breeze-authelia-passkey.XXXXXX")"
PREV=""

cleanup() {
    rm -rf "$TMP"
    if [ -n "$PREV" ] && [ -d "$PREV" ] && [ ! -e "$DEST" ]; then
        mv "$PREV" "$DEST" || true
    fi
}
trap cleanup EXIT

cp -a --no-preserve=ownership "$BASE/." "$TMP/"

patch --batch --forward --reject-file=- -p1 -d "$TMP" < "$PATCH_DIR/Main.qml.patch"
patch --batch --forward --reject-file=- -p1 -d "$TMP" < "$PATCH_DIR/metadata.desktop.patch"

grep -q 'targetUsername' "$TMP/Main.qml"
grep -q 'sddmSelectedUsername' "$TMP/Main.qml"
grep -q 'Smartphone-Login' "$TMP/Main.qml"

find "$TMP" -type d -exec chmod 0755 {} +
find "$TMP" -type f -exec chmod 0644 {} +
chown -R root:root "$TMP"

if [ -d "$DEST" ]; then
    PREV="${DEST}.previous.$$"
    mv "$DEST" "$PREV"
fi

mv "$TMP" "$DEST"
TMP=""

if [ -n "$PREV" ]; then
    rm -rf "$PREV"
    PREV=""
fi

trap - EXIT

echo "THEME_INSTALL=GREEN"
echo "THEME=$DEST"
echo "NOTE=SDDM was not restarted and theme selection was not changed"
