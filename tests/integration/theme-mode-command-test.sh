#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="$REPO/scripts/theme-mode.sh"
ADMIN="$REPO/scripts/sddm-authelia-passkey-admin.sh"
ROLLBACK="$REPO/scripts/rollback.sh"

bash -n "$MODE"
bash -n "$ADMIN"
bash -n "$ROLLBACK"

# Admin CLI must remain fixed-dispatch.
grep -q '^mode-status)' "$ADMIN"
grep -q '^apply-mode)' "$ADMIN"
grep -q 'native|compatibility|backend-only' "$ADMIN"
grep -q 'theme-mode.sh.*status' "$ADMIN"
grep -q 'theme-mode.sh.*apply.*MODE' "$ADMIN"

if grep -Eq '(^|[[:space:]])eval[[:space:]]|bash[[:space:]]+-c|sh[[:space:]]+-c' "$ADMIN"; then
    echo "FAIL: general command execution found in admin CLI"
    false
fi

echo "ADMIN_FIXED_DISPATCH=GREEN"

# Rollback must prefer v1.16 managed restoration while retaining
# compatibility with installations predating theme-mode state.
grep -q '^THEME_MODE_STATE=' "$ROLLBACK"
grep -q 'theme-mode.sh.*apply backend-only' "$ROLLBACK"
grep -q 'THEME_ROLLBACK=MANAGED' "$ROLLBACK"
grep -q 'THEME_ROLLBACK=LEGACY' "$ROLLBACK"

if grep -Eqi \
    'systemctl[[:space:]]+(restart|stop)[[:space:]]+sddm|pkill[[:space:]].*sddm|killall[[:space:]].*sddm' \
    "$ROLLBACK"
then
    echo "FAIL: SDDM session disruption path found"
    false
fi

echo "ROLLBACK_MODE_INTEGRATION=GREEN"
echo "ROLLBACK_SDDM_RESTART_USED=NO"

# A broken config symlink must produce one clean rejection and must not
# create state or follow the link.
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

ln -s missing-target.conf "$ROOT/etc/sddm.conf"

if OUT="$(
    SDDM_AUTHELIA_TEST_ROOT="$ROOT" \
        bash "$MODE" apply native 2>&1
)"; then
    echo "FAIL: broken config symlink was accepted"
    false
fi

ERROR_COUNT="$(
    printf '%s\n' "$OUT" |
    grep -c '^THEME_MODE_ERROR='
)"

test "$ERROR_COUNT" -eq 1
test -L "$ROOT/etc/sddm.conf"
test ! -e "$ROOT/etc/missing-target.conf"
test ! -e \
    "$ROOT/var/lib/sddm-authelia-passkey/theme-mode/state.conf"

echo "ERROR_PROPAGATION=GREEN"
echo "SYMLINK_REJECTION_COUNT=$ERROR_COUNT"
echo "THEME_MODE_COMMAND_TEST=GREEN"
