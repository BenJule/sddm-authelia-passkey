#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MIGRATE="$REPO/scripts/theme-migrate.sh"
MODE="$REPO/scripts/theme-mode.sh"

bash -n "$MIGRATE"

ROOT="$(mktemp -d)"

cleanup() {
    rm -rf "$ROOT"
}

trap cleanup EXIT

mkdir -p \
    "$ROOT/etc" \
    "$ROOT/usr/share/sddm/themes/sddm-authelia-passkey-native" \
    "$ROOT/usr/share/sddm/themes/debian-breeze-authelia-passkey"

for theme in sddm-authelia-passkey-native debian-breeze-authelia-passkey; do
    printf 'import QtQuick\nItem {}\n' \
        > "$ROOT/usr/share/sddm/themes/$theme/Main.qml"
    printf '[SddmGreeterTheme]\nMainScript=Main.qml\n' \
        > "$ROOT/usr/share/sddm/themes/$theme/metadata.desktop"
    chmod 0644 \
        "$ROOT/usr/share/sddm/themes/$theme/Main.qml" \
        "$ROOT/usr/share/sddm/themes/$theme/metadata.desktop"
done

run_migrate() {
    SDDM_AUTHELIA_TEST_ROOT="$ROOT" bash "$MIGRATE" "$@"
}

run_mode() {
    SDDM_AUTHELIA_TEST_ROOT="$ROOT" bash "$MODE" "$@"
}

STATE_FILE="$ROOT/var/lib/sddm-authelia-passkey/migrate/migrate.state"

# --- preflight is fully read-only ---
snapshot() {
    { find "$ROOT/var/lib" "$ROOT/etc" 2>/dev/null || true; } | sort
}

for target in native compatibility backend-only; do
    BEFORE="$(snapshot)"
    run_migrate preflight "$target" >/dev/null
    AFTER="$(snapshot)"

    if [ "$BEFORE" != "$AFTER" ]; then
        echo "FAIL: preflight $target mutated state"
        false
    fi
done

echo "PREFLIGHT_READONLY=GREEN"

# --- NOOP migrate never writes migrate.state ---
OUT="$(run_migrate migrate backend-only)"
printf '%s\n' "$OUT" | grep -q '^MIGRATE_APPLY=NOOP$'
test ! -e "$STATE_FILE"

echo "NOOP_NO_STATE=GREEN"

# --- full round trip ---
OUT="$(run_migrate migrate native)"
printf '%s\n' "$OUT" | grep -q '^MIGRATE_APPLY=GREEN$'
printf '%s\n' "$OUT" | grep -q '^MIGRATE_FROM_MODE=backend-only$'
printf '%s\n' "$OUT" | grep -q '^MIGRATE_TO_MODE=native$'

OUT="$(run_migrate migrate compatibility)"
printf '%s\n' "$OUT" | grep -q '^MIGRATE_FROM_MODE=native$'
printf '%s\n' "$OUT" | grep -q '^MIGRATE_TO_MODE=compatibility$'

OUT="$(run_migrate migrate backend-only)"
printf '%s\n' "$OUT" | grep -q '^MIGRATE_FROM_MODE=compatibility$'
printf '%s\n' "$OUT" | grep -q '^MIGRATE_TO_MODE=backend-only$'

echo "ROUND_TRIP=GREEN"

# --- rollback three times in a row proves single-level-undo threading,
# not a history stack and not the deep v1.16 baseline restore ---
OUT="$(run_migrate rollback-migration)"
printf '%s\n' "$OUT" | grep -q '^MIGRATE_ROLLBACK_FROM=backend-only$'
printf '%s\n' "$OUT" | grep -q '^MIGRATE_ROLLBACK_TO=compatibility$'

OUT="$(run_migrate rollback-migration)"
printf '%s\n' "$OUT" | grep -q '^MIGRATE_ROLLBACK_FROM=compatibility$'
printf '%s\n' "$OUT" | grep -q '^MIGRATE_ROLLBACK_TO=backend-only$'

OUT="$(run_migrate rollback-migration)"
printf '%s\n' "$OUT" | grep -q '^MIGRATE_ROLLBACK_FROM=backend-only$'
printf '%s\n' "$OUT" | grep -q '^MIGRATE_ROLLBACK_TO=compatibility$'

echo "SINGLE_LEVEL_UNDO=GREEN"

run_mode status | grep -q '^INSTALL_MODE=compatibility$'

echo "ROLLBACK_MATCHES_MODE_STATUS=GREEN"

# --- fail closed with no prior state ---
rm -rf "$ROOT/var/lib/sddm-authelia-passkey/migrate"

ERR_FILE="$ROOT/err.log"

if run_migrate rollback-migration 2>"$ERR_FILE"; then
    echo "FAIL: rollback-migration succeeded with no prior state"
    false
fi

grep -q '^THEME_MIGRATE_ERROR=' "$ERR_FILE"

if run_migrate resume 2>"$ERR_FILE"; then
    echo "FAIL: resume succeeded with no marker"
    false
fi

grep -q '^THEME_MIGRATE_ERROR=' "$ERR_FILE"
rm -f "$ERR_FILE"

echo "FAIL_CLOSED_NO_HISTORY=GREEN"

echo "THEME_MIGRATE_TEST=GREEN"
