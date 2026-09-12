#!/bin/bash
set -euo pipefail
umask 077

# v1.17.0 Migration & Rollback: a thin orchestrator around the already
# tested scripts/theme-mode.sh (v1.16.0), invoked as a subprocess -
# never reimplementing its validation/atomic-write/idempotency logic.
# This script only adds: a per-migration "what mode was active before
# this transition" record (distinct from theme-mode.sh's own one-time
# original-baseline backup), an interrupted-operation marker, and the
# `rollback-migration`/`resume` verbs built on top of that record.
#
# Never touches PAM, the broker, FIDO2/OIDC config, or any package
# manager - purely theme-selection-mode orchestration, exactly like
# theme-mode.sh itself.

TEST_ROOT="${SDDM_AUTHELIA_TEST_ROOT:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_MODE_SH="$SCRIPT_DIR/theme-mode.sh"

root_path() {
    printf '%s%s\n' "$TEST_ROOT" "$1"
}

MIGRATE_DIR="$(root_path /var/lib/sddm-authelia-passkey/migrate)"
STATE_FILE="$MIGRATE_DIR/migrate.state"
MARKER_FILE="$MIGRATE_DIR/migrate.inprogress"

fail() {
    echo "THEME_MIGRATE_ERROR=$*" >&2
    return 64
}

run_theme_mode() {
    if [ -n "$TEST_ROOT" ]; then
        SDDM_AUTHELIA_TEST_ROOT="$TEST_ROOT" bash "$THEME_MODE_SH" "$@"
    else
        bash "$THEME_MODE_SH" "$@"
    fi
}

field() {
    # Extracts KEY=value from a captured theme-mode.sh output blob.
    local blob="$1"
    local key="$2"

    printf '%s\n' "$blob" |
        awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; found=1 } END { if (!found) print "" }'
}

conf_get() {
    local file="$1"
    local key="$2"

    [ -f "$file" ] || return 0

    awk -F= -v key="$key" '
        $1 == key {
            sub(/^[^=]*=/, "")
            print
            found=1
        }
        END {
            if (!found)
                print ""
        }
    ' "$file"
}

write_conf() {
    # Atomically (mktemp + install) writes a key=value file, mirroring
    # theme-mode.sh's own write_state() convention exactly.
    local file="$1"
    shift
    local tmp

    mkdir -p "$MIGRATE_DIR"
    chmod 0700 "$MIGRATE_DIR"

    tmp="$(mktemp "$MIGRATE_DIR/.migrate.XXXXXX")"

    printf '%s\n' "$@" > "$tmp"

    if [ -z "$TEST_ROOT" ]; then
        install -o root -g root -m 0600 -T "$tmp" "$file"
    else
        install -m 0600 -T "$tmp" "$file"
    fi

    rm -f "$tmp"
}

new_migration_id() {
    printf '%s-%s\n' "$(date -u +%s)" "$$"
}

# Detects and, where safe, cleans up a stale interruption marker left
# over from a crash *after* a migration actually completed (state
# written) but *before* this script removed the marker on the previous
# run. A marker that does not correspond to a completed state entry is
# a genuine interruption and is left untouched here - callers decide
# whether to block, resume, or roll it back.
reconcile_marker() {
    [ -f "$MARKER_FILE" ] || return 0

    local marker_id state_id state_completed

    marker_id="$(conf_get "$MARKER_FILE" migration_id)"
    state_id="$(conf_get "$STATE_FILE" migration_id)"
    state_completed="$(conf_get "$STATE_FILE" completed_at)"

    if [ -n "$marker_id" ] && [ "$marker_id" = "$state_id" ] && [ -n "$state_completed" ]; then
        rm -f "$MARKER_FILE"
        echo "MIGRATE_INTERRUPTED_MARKER=STALE_CLEANED"
    fi
}

marker_present() {
    reconcile_marker
    [ -f "$MARKER_FILE" ]
}

cmd_preflight() {
    local target="$1"
    local from_mode noop target_valid interrupted status_blob check_blob

    status_blob="$(run_theme_mode status)"
    from_mode="$(field "$status_blob" INSTALL_MODE)"

    check_blob="$(run_theme_mode check-target "$target")"
    target_valid="$(field "$check_blob" TARGET_VALID)"

    if [ "$from_mode" = "$target" ]; then
        noop="YES"
    else
        noop="NO"
    fi

    if marker_present; then
        interrupted="YES"
    else
        interrupted="NO"
    fi

    echo "MIGRATE_FROM_MODE=$from_mode"
    echo "MIGRATE_TO_MODE=$target"
    echo "MIGRATE_NOOP=$noop"
    echo "MIGRATE_TARGET_VALID=$target_valid"
    echo "MIGRATE_INTERRUPTED=$interrupted"

    if [ "$interrupted" = "YES" ] || [ "$target_valid" = "NO" ]; then
        echo "MIGRATE_PREFLIGHT=BLOCKED"
    else
        echo "MIGRATE_PREFLIGHT=GREEN"
    fi
}

do_apply_and_record() {
    # Shared by migrate/resume: performs the single mutating
    # theme-mode.sh apply call inside the marker's protection, then
    # records completion and removes the marker. Never called unless
    # the marker for this exact transition already exists.
    local from_mode="$1"
    local to_mode="$2"
    local migration_id="$3"
    local apply_blob

    apply_blob="$(run_theme_mode apply "$to_mode")"

    write_conf "$STATE_FILE" \
        "migration_id=$migration_id" \
        "from_mode=$from_mode" \
        "from_effective_theme=$(field "$apply_blob" EFFECTIVE_THEME)" \
        "to_mode=$to_mode" \
        "started_at=$(conf_get "$MARKER_FILE" started_at)" \
        "completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    rm -f "$MARKER_FILE"

    printf '%s\n' "$apply_blob"
}

cmd_migrate() {
    local target="$1"
    local from_mode migration_id apply_blob

    if marker_present; then
        fail "an interrupted migration is pending (from=$(conf_get "$MARKER_FILE" from_mode) to=$(conf_get "$MARKER_FILE" to_mode) started=$(conf_get "$MARKER_FILE" started_at)); run migrate-resume or rollback-migration first"
        return 64
    fi

    from_mode="$(field "$(run_theme_mode status)" INSTALL_MODE)"

    echo "MIGRATE_FROM_MODE=$from_mode"
    echo "MIGRATE_TO_MODE=$target"

    if [ "$from_mode" = "$target" ]; then
        # Already at the target mode: nothing actually transitions, so
        # no marker/state bookkeeping is created for it (single-level
        # undo history must only ever reflect real transitions).
        apply_blob="$(run_theme_mode apply "$target")"
        echo "MIGRATE_APPLY=NOOP"
        printf '%s\n' "$apply_blob"
        return 0
    fi

    migration_id="$(new_migration_id)"

    write_conf "$MARKER_FILE" \
        "migration_id=$migration_id" \
        "from_mode=$from_mode" \
        "to_mode=$target" \
        "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "pid=$$"

    apply_blob="$(do_apply_and_record "$from_mode" "$target" "$migration_id")"

    echo "MIGRATE_APPLY=GREEN"
    printf '%s\n' "$apply_blob"
    echo "MIGRATION_ID=$migration_id"
}

cmd_resume() {
    local from_mode to_mode migration_id apply_blob

    if ! marker_present; then
        fail "no interrupted operation found"
        return 64
    fi

    from_mode="$(conf_get "$MARKER_FILE" from_mode)"
    to_mode="$(conf_get "$MARKER_FILE" to_mode)"
    migration_id="$(conf_get "$MARKER_FILE" migration_id)"

    apply_blob="$(do_apply_and_record "$from_mode" "$to_mode" "$migration_id")"

    echo "MIGRATE_RESUME_FROM=$from_mode"
    echo "MIGRATE_RESUME_TO=$to_mode"
    echo "MIGRATE_RESUME_RESULT=GREEN"
    printf '%s\n' "$apply_blob" | grep -E '^(EFFECTIVE_THEME|SDDM_RESTART_USED)='
}

cmd_rollback_migration() {
    local source from to migration_id apply_blob

    if marker_present; then
        source="INTERRUPTED_OPERATION"
        from="$(conf_get "$MARKER_FILE" to_mode)"
        to="$(conf_get "$MARKER_FILE" from_mode)"
    else
        [ -f "$STATE_FILE" ] ||
            fail "no prior migration recorded"

        source="LAST_MIGRATION"
        from="$(conf_get "$STATE_FILE" to_mode)"
        to="$(conf_get "$STATE_FILE" from_mode)"

        [ -n "$to" ] ||
            fail "no prior migration recorded"
    fi

    migration_id="$(new_migration_id)"

    write_conf "$MARKER_FILE" \
        "migration_id=$migration_id" \
        "from_mode=$from" \
        "to_mode=$to" \
        "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "pid=$$"

    apply_blob="$(do_apply_and_record "$from" "$to" "$migration_id")"

    echo "MIGRATE_ROLLBACK_SOURCE=$source"
    echo "MIGRATE_ROLLBACK_FROM=$from"
    echo "MIGRATE_ROLLBACK_TO=$to"
    echo "MIGRATE_ROLLBACK_RESULT=GREEN"
    printf '%s\n' "$apply_blob" | grep -E '^(EFFECTIVE_THEME|SDDM_RESTART_USED)='
}

cmd_status() {
    local interrupted

    echo "MIGRATE_LAST_FROM=$(conf_get "$STATE_FILE" from_mode)"
    echo "MIGRATE_LAST_TO=$(conf_get "$STATE_FILE" to_mode)"
    echo "MIGRATE_LAST_COMPLETED_AT=$(conf_get "$STATE_FILE" completed_at)"

    if marker_present; then
        interrupted="YES"
    else
        interrupted="NO"
    fi

    echo "MIGRATE_INTERRUPTED=$interrupted"

    if [ "$interrupted" = "YES" ]; then
        echo "MIGRATE_INTERRUPTED_FROM=$(conf_get "$MARKER_FILE" from_mode)"
        echo "MIGRATE_INTERRUPTED_TO=$(conf_get "$MARKER_FILE" to_mode)"
        echo "MIGRATE_INTERRUPTED_STARTED_AT=$(conf_get "$MARKER_FILE" started_at)"
        echo "MIGRATE_INTERRUPTED_PID=$(conf_get "$MARKER_FILE" pid)"
    fi
}

usage() {
    echo \
        "usage: $0 {preflight <mode>|migrate <mode>|rollback-migration|resume|status}" \
        >&2
    false
}

if [ -z "$TEST_ROOT" ] && [ "$(id -u)" -ne 0 ]; then
    fail "must run as root"
fi

[ -x "$THEME_MODE_SH" ] || fail "theme-mode.sh not found: $THEME_MODE_SH"

COMMAND="${1:-}"

case "$COMMAND" in
    preflight)
        TARGET="${2:-}"
        case "$TARGET" in
            native|compatibility|backend-only)
                cmd_preflight "$TARGET"
                ;;
            *)
                usage
                ;;
        esac
        ;;

    migrate)
        TARGET="${2:-}"
        case "$TARGET" in
            native|compatibility|backend-only)
                cmd_migrate "$TARGET"
                ;;
            *)
                usage
                ;;
        esac
        ;;

    rollback-migration)
        cmd_rollback_migration
        ;;

    resume)
        cmd_resume
        ;;

    status)
        cmd_status
        ;;

    *)
        usage
        ;;
esac
