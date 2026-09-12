#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="$REPO/scripts/theme-mode.sh"

bash -n "$MODE"

ROOT="$(mktemp -d)"

cleanup() {
    rm -rf "$ROOT"
}

trap cleanup EXIT

mkdir -p \
    "$ROOT/etc" \
    "$ROOT/usr/share/sddm/themes/sddm-authelia-passkey-native"

printf 'import QtQuick\nItem {}\n' \
    > "$ROOT/usr/share/sddm/themes/sddm-authelia-passkey-native/Main.qml"

printf '[SddmGreeterTheme]\nMainScript=Main.qml\n' \
    > "$ROOT/usr/share/sddm/themes/sddm-authelia-passkey-native/metadata.desktop"

chmod 0644 \
    "$ROOT/usr/share/sddm/themes/sddm-authelia-passkey-native/Main.qml" \
    "$ROOT/usr/share/sddm/themes/sddm-authelia-passkey-native/metadata.desktop"

snapshot() {
    find "$ROOT" | sort
}

BEFORE="$(snapshot)"

OUT="$(SDDM_AUTHELIA_TEST_ROOT="$ROOT" bash "$MODE" check-target native)"
printf '%s\n' "$OUT" | grep -q '^TARGET=sddm-authelia-passkey-native$'
printf '%s\n' "$OUT" | grep -q '^TARGET_VALID=YES$'

OUT="$(SDDM_AUTHELIA_TEST_ROOT="$ROOT" bash "$MODE" check-target backend-only)"
printf '%s\n' "$OUT" | grep -q '^TARGET=<none>$'
printf '%s\n' "$OUT" | grep -q '^TARGET_VALID=N/A$'

# compatibility target theme directory does not exist in this scratch
# root, so it must be reported invalid rather than crashing.
OUT="$(SDDM_AUTHELIA_TEST_ROOT="$ROOT" bash "$MODE" check-target compatibility)"
printf '%s\n' "$OUT" | grep -q '^TARGET_VALID=NO$'

AFTER="$(snapshot)"

if [ "$BEFORE" != "$AFTER" ]; then
    echo "FAIL: check-target mutated filesystem state"
    diff <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") || true
    false
fi

test ! -e "$ROOT/var/lib/sddm-authelia-passkey/theme-mode"

echo "CHECK_TARGET_READONLY=GREEN"

# Must not require root when running under SDDM_AUTHELIA_TEST_ROOT
# (theme-mode.sh's own root-check bypass convention).
if [ "$(id -u)" -ne 0 ]; then
    SDDM_AUTHELIA_TEST_ROOT="$ROOT" bash "$MODE" check-target native >/dev/null
    echo "CHECK_TARGET_NONROOT_TEST_OK=GREEN"
fi

echo "THEME_MODE_CHECK_TARGET_TEST=GREEN"
