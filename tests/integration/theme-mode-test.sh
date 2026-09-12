#!/bin/bash
set -euo pipefail

ROOT="$(mktemp -d)"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="$REPO/scripts/theme-mode.sh"

cleanup() {
    rm -rf "$ROOT"
}

trap cleanup EXIT

make_theme() {
    local name="$1"

    mkdir -p "$ROOT/usr/share/sddm/themes/$name"

    printf 'import QtQuick\nItem {}\n' \
        > "$ROOT/usr/share/sddm/themes/$name/Main.qml"

    printf '[SddmGreeterTheme]\nName=%s\nMainScript=Main.qml\n' "$name" \
        > "$ROOT/usr/share/sddm/themes/$name/metadata.desktop"

    chmod 0644 \
        "$ROOT/usr/share/sddm/themes/$name/Main.qml" \
        "$ROOT/usr/share/sddm/themes/$name/metadata.desktop"
}

run_mode() {
    SDDM_AUTHELIA_TEST_ROOT="$ROOT" \
        bash "$MODE" "$@"
}

mkdir -p \
    "$ROOT/etc/sddm.conf.d" \
    "$ROOT/usr/lib/sddm/sddm.conf.d"

make_theme "unrelated-theme"
make_theme "sddm-authelia-passkey-native"
make_theme "debian-breeze-authelia-passkey"

cat > "$ROOT/etc/sddm.conf" <<'CFG'
[General]
DisplayServer=wayland

[Theme]
CursorTheme=breeze_cursors
Current=unrelated-theme

[X11]
ServerArguments=-nolisten tcp
CFG

chmod 0640 "$ROOT/etc/sddm.conf"

BASE_SHA="$(
    sha256sum "$ROOT/etc/sddm.conf" |
    awk '{print $1}'
)"

BASE_MODE="$(stat -c '%a' "$ROOT/etc/sddm.conf")"

run_mode status |
    grep -q '^INSTALL_MODE=backend-only$'

run_mode apply native |
    grep -q '^MODE_APPLY=GREEN$'

grep -q '^Current=sddm-authelia-passkey-native$' \
    "$ROOT/etc/sddm.conf"

NATIVE_SHA="$(
    sha256sum "$ROOT/etc/sddm.conf" |
    awk '{print $1}'
)"

run_mode apply native |
    grep -q '^MODE_APPLY=NOOP$'

test "$NATIVE_SHA" = "$(
    sha256sum "$ROOT/etc/sddm.conf" |
    awk '{print $1}'
)"

run_mode apply compatibility |
    grep -q '^MODE_APPLY=GREEN$'

grep -q '^Current=debian-breeze-authelia-passkey$' \
    "$ROOT/etc/sddm.conf"

run_mode apply backend-only |
    grep -q '^MODE_APPLY=GREEN$'

test "$BASE_SHA" = "$(
    sha256sum "$ROOT/etc/sddm.conf" |
    awk '{print $1}'
)"

test "$BASE_MODE" = "$(
    stat -c '%a' "$ROOT/etc/sddm.conf"
)"

grep -q '^Current=unrelated-theme$' \
    "$ROOT/etc/sddm.conf"

test -d "$ROOT/usr/share/sddm/themes/unrelated-theme"

run_mode apply backend-only |
    grep -q '^MODE_APPLY=NOOP$'

echo "THEME_MODE_ROUNDTRIP=GREEN"
echo "THEME_MODE_IDEMPOTENCY=GREEN"

# External modification of a managed SDDM config must fail closed.
rm -rf "$ROOT"
ROOT="$(mktemp -d)"

mkdir -p \
    "$ROOT/etc/sddm.conf.d" \
    "$ROOT/usr/lib/sddm/sddm.conf.d"

make_theme "sddm-authelia-passkey-native"
make_theme "debian-breeze-authelia-passkey"

cat > "$ROOT/etc/sddm.conf" <<'CFG'
[Theme]
Current=debian-breeze
CFG

chmod 0644 "$ROOT/etc/sddm.conf"

run_mode apply native >/dev/null

printf '\n# external-admin-change\n' \
    >> "$ROOT/etc/sddm.conf"

DRIFT_SHA="$(
    sha256sum "$ROOT/etc/sddm.conf" |
    awk '{print $1}'
)"

if run_mode apply compatibility >/dev/null 2>&1; then
    echo "FAIL: external SDDM config drift was overwritten"
    false
fi

test "$DRIFT_SHA" = "$(
    sha256sum "$ROOT/etc/sddm.conf" |
    awk '{print $1}'
)"

echo "THEME_MODE_DRIFT_FAIL_CLOSED=GREEN"

# An incomplete/invalid target theme must be rejected before state/config
# mutation.
rm -rf "$ROOT"
ROOT="$(mktemp -d)"

mkdir -p \
    "$ROOT/etc/sddm.conf.d" \
    "$ROOT/usr/lib/sddm/sddm.conf.d" \
    "$ROOT/usr/share/sddm/themes/sddm-authelia-passkey-native"

printf 'import QtQuick\nItem {}\n' \
    > "$ROOT/usr/share/sddm/themes/sddm-authelia-passkey-native/Main.qml"

cat > "$ROOT/etc/sddm.conf" <<'CFG'
[Theme]
Current=debian-breeze
CFG

chmod 0644 "$ROOT/etc/sddm.conf"

TARGET_BASE_SHA="$(
    sha256sum "$ROOT/etc/sddm.conf" |
    awk '{print $1}'
)"

if run_mode apply native >/dev/null 2>&1; then
    echo "FAIL: invalid Native Theme was accepted"
    false
fi

test "$TARGET_BASE_SHA" = "$(
    sha256sum "$ROOT/etc/sddm.conf" |
    awk '{print $1}'
)"

test ! -e \
    "$ROOT/var/lib/sddm-authelia-passkey/theme-mode/state.conf"

echo "THEME_MODE_TARGET_VALIDATION=GREEN"

# A symlinked SDDM config must never be followed or replaced.
rm -rf "$ROOT"
ROOT="$(mktemp -d)"

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

ln -s missing-target.conf "$ROOT/etc/sddm.conf"

if run_mode apply native >/dev/null 2>&1; then
    echo "FAIL: symlinked SDDM config was accepted"
    false
fi

test -L "$ROOT/etc/sddm.conf"
test ! -e "$ROOT/etc/missing-target.conf"
test ! -e \
    "$ROOT/var/lib/sddm-authelia-passkey/theme-mode/state.conf"

# A theme with symlinked required files must also fail closed.
rm -rf "$ROOT"
ROOT="$(mktemp -d)"

mkdir -p \
    "$ROOT/etc" \
    "$ROOT/usr/share/sddm/themes/sddm-authelia-passkey-native"

cat > "$ROOT/etc/sddm.conf" <<'CFG'
[Theme]
Current=debian-breeze
CFG

chmod 0644 "$ROOT/etc/sddm.conf"

printf 'import QtQuick\nItem {}\n' > "$ROOT/real-Main.qml"

ln -s "$ROOT/real-Main.qml" \
    "$ROOT/usr/share/sddm/themes/sddm-authelia-passkey-native/Main.qml"

printf '[SddmGreeterTheme]\nMainScript=Main.qml\n' \
    > "$ROOT/usr/share/sddm/themes/sddm-authelia-passkey-native/metadata.desktop"

SYMLINK_BASE_SHA="$(
    sha256sum "$ROOT/etc/sddm.conf" |
    awk '{print $1}'
)"

if run_mode apply native >/dev/null 2>&1; then
    echo "FAIL: symlinked theme payload was accepted"
    false
fi

test "$SYMLINK_BASE_SHA" = "$(
    sha256sum "$ROOT/etc/sddm.conf" |
    awk '{print $1}'
)"

test ! -e \
    "$ROOT/var/lib/sddm-authelia-passkey/theme-mode/state.conf"

echo "THEME_MODE_SYMLINK_SAFETY=GREEN"
echo "THEME_MODE_RESULT=GREEN"
