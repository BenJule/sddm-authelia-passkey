#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MIGRATE="$REPO/scripts/theme-migrate.sh"
ADMIN="$REPO/scripts/sddm-authelia-passkey-admin.sh"

bash -n "$MIGRATE"
bash -n "$ADMIN"

# Admin CLI must remain fixed-dispatch for the new migration subcommands.
grep -q '^migrate-preflight)' "$ADMIN"
grep -q '^migrate)' "$ADMIN"
grep -q '^rollback-migration)' "$ADMIN"
grep -q '^migrate-resume)' "$ADMIN"
grep -q '^migrate-status)' "$ADMIN"
grep -q 'theme-migrate.sh.*preflight.*MODE' "$ADMIN"
grep -q 'theme-migrate.sh.*migrate.*MODE' "$ADMIN"
grep -q 'theme-migrate.sh.*rollback-migration' "$ADMIN"
grep -q 'theme-migrate.sh.*resume' "$ADMIN"
grep -q 'theme-migrate.sh.*status' "$ADMIN"

if grep -Eq '(^|[[:space:]])eval[[:space:]]|bash[[:space:]]+-c|sh[[:space:]]+-c' "$ADMIN"; then
    echo "FAIL: general command execution found in admin CLI"
    false
fi

echo "ADMIN_MIGRATE_FIXED_DISPATCH=GREEN"

# theme-migrate.sh must never touch PAM, package management, or SDDM's
# running session - it is pure theme-selection-mode orchestration.
if grep -Eq \
    'pam_authelia_passkey|/etc/pam\.d|apt-get|dpkg[[:space:]]|systemctl[[:space:]]+(restart|stop)[[:space:]]+sddm|pkill|killall' \
    "$MIGRATE"
then
    echo "FAIL: theme-migrate.sh touches PAM/packaging/session state"
    false
fi

echo "MIGRATE_SCOPE_INVARIANTS=GREEN"

ROOT="$(mktemp -d)"

cleanup() {
    rm -rf "$ROOT"
}

trap cleanup EXIT

mkdir -p \
    "$ROOT/etc" \
    "$ROOT/usr/share/sddm/themes/sddm-authelia-passkey-native" \
    "$ROOT/usr/share/sddm/themes/debian-breeze-authelia-passkey" \
    "$ROOT/var/lib/sddm-authelia-passkey/migrate"

for theme in sddm-authelia-passkey-native debian-breeze-authelia-passkey; do
    printf 'import QtQuick\nItem {}\n' \
        > "$ROOT/usr/share/sddm/themes/$theme/Main.qml"
    printf '[SddmGreeterTheme]\nMainScript=Main.qml\n' \
        > "$ROOT/usr/share/sddm/themes/$theme/metadata.desktop"
    chmod 0644 \
        "$ROOT/usr/share/sddm/themes/$theme/Main.qml" \
        "$ROOT/usr/share/sddm/themes/$theme/metadata.desktop"
done

chmod 0700 "$ROOT/var/lib/sddm-authelia-passkey/migrate"

run_migrate() {
    SDDM_AUTHELIA_TEST_ROOT="$ROOT" bash "$MIGRATE" "$@"
}

MARKER_FILE="$ROOT/var/lib/sddm-authelia-passkey/migrate/migrate.inprogress"
STATE_FILE="$ROOT/var/lib/sddm-authelia-passkey/migrate/migrate.state"

# --- hand-planted interruption blocks a plain migrate ---
cat > "$MARKER_FILE" <<EOF
migration_id=planted-1
from_mode=backend-only
to_mode=native
started_at=2026-09-12T00:00:00Z
pid=99999
EOF
chmod 0600 "$MARKER_FILE"

if run_migrate migrate compatibility; then
    echo "FAIL: migrate proceeded despite pending interruption"
    false
fi

echo "INTERRUPTION_BLOCKS_MIGRATE=GREEN"

# --- resolved via migrate-resume ---
OUT="$(run_migrate resume)"
printf '%s\n' "$OUT" | grep -q '^MIGRATE_RESUME_FROM=backend-only$'
printf '%s\n' "$OUT" | grep -q '^MIGRATE_RESUME_TO=native$'
test ! -e "$MARKER_FILE"
test -e "$STATE_FILE"

echo "RESUME_RESOLVES_INTERRUPTION=GREEN"

# --- a second interruption resolved instead via rollback-migration,
# restoring the marker's from_mode (not the stale migrate.state) ---
cat > "$MARKER_FILE" <<EOF
migration_id=planted-2
from_mode=native
to_mode=compatibility
started_at=2026-09-12T00:00:01Z
pid=99998
EOF
chmod 0600 "$MARKER_FILE"

OUT="$(run_migrate rollback-migration)"
printf '%s\n' "$OUT" | grep -q '^MIGRATE_ROLLBACK_SOURCE=INTERRUPTED_OPERATION$'
printf '%s\n' "$OUT" | grep -q '^MIGRATE_ROLLBACK_FROM=compatibility$'
printf '%s\n' "$OUT" | grep -q '^MIGRATE_ROLLBACK_TO=native$'
test ! -e "$MARKER_FILE"

echo "ROLLBACK_RESOLVES_INTERRUPTION=GREEN"

# --- stale marker (same migration_id as a completed state entry) is
# benign and silently cleaned up, not treated as a genuine interruption ---
MID="$(awk -F= '$1=="migration_id"{print $2}' "$STATE_FILE")"

cat > "$MARKER_FILE" <<EOF
migration_id=$MID
from_mode=compatibility
to_mode=native
started_at=2026-09-12T00:00:02Z
pid=99997
EOF
chmod 0600 "$MARKER_FILE"

OUT="$(run_migrate status)"
printf '%s\n' "$OUT" | grep -q '^MIGRATE_INTERRUPTED_MARKER=STALE_CLEANED$'
printf '%s\n' "$OUT" | grep -q '^MIGRATE_INTERRUPTED=NO$'
test ! -e "$MARKER_FILE"

echo "STALE_MARKER_CLEANUP=GREEN"

echo "THEME_MIGRATE_COMMAND_TEST=GREEN"
