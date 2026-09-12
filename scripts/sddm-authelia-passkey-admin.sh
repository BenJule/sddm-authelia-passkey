#!/bin/bash
# Fixed-dispatch admin CLI for sddm-authelia-passkey - a single, safe
# entry point for common day-to-day administration. Deliberately NOT a
# general shell/config-editing tool; only apply-mode changes theme selection:
# every subcommand delegates to an existing, already-tested script or
# broker mechanism rather than reimplementing any logic here.
#
# Subcommands:
#   status       - is the broker/sddm/kwallet-secretd stack up right now
#                  (delegates to postflight.sh)
#   health       - alias for status
#   test-config  - validate /etc/sddm-authelia-passkey/config.conf
#                  without starting anything (delegates to the broker's
#                  own --check-config flag, no root required)
#   list-users   - who is currently eligible for the passwordless path,
#                  and who has a FIDO2 credential enrolled (delegates to
#                  list-fido2-credentials.sh for the latter)
#   audit-log    - security-relevant broker log lines (journalctl, "SECURITY:"
#                  tagged entries only - authorization denials, identity
#                  mismatches, successful approvals)
#   migrate-preflight, migrate, rollback-migration, migrate-resume,
#   migrate-status - theme mode migration tooling (delegates to
#                  theme-migrate.sh, same as apply-mode delegates to
#                  theme-mode.sh)
set -euo pipefail

CONFIG=/etc/sddm-authelia-passkey/config.conf
BROKER_BIN=/usr/lib/sddm-authelia-passkey/broker

# Packaged installs place this CLI in /usr/sbin, separate from the
# one-shot scripts it delegates to (/usr/share/sddm-authelia-passkey/);
# fall back to running from the source tree (next to those scripts
# directly) so this also works uninstalled, e.g. for VM124/CI testing.
if [ -d /usr/share/sddm-authelia-passkey ]; then
    SHARE_DIR=/usr/share/sddm-authelia-passkey
else
    SHARE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

usage() {
    echo "usage: $0 {status|health|test-config|list-users|audit-log|mode-status|apply-mode|migrate-preflight|migrate|rollback-migration|migrate-resume|migrate-status}" >&2
    exit 1
}

cmd="${1:-}"
[ -n "$cmd" ] || usage

case "$cmd" in
status|health)
    [ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }
    [ -f "$SHARE_DIR/postflight.sh" ] || { echo "[FAIL] $SHARE_DIR/postflight.sh not found" >&2; exit 1; }
    exec bash "$SHARE_DIR/postflight.sh"
    ;;

test-config)
    [ -f "$BROKER_BIN" ] || { echo "[FAIL] $BROKER_BIN not installed" >&2; exit 1; }
    exec "$BROKER_BIN" --check-config
    ;;

list-users)
    [ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }
    [ -f "$CONFIG" ] || { echo "[FAIL] $CONFIG not found" >&2; exit 1; }

    ACCOUNT_SOURCE=$(awk -F= '/^account_source=/{print $2; exit}' "$CONFIG")
    ACCOUNT_SOURCE="${ACCOUNT_SOURCE:-local}"
    echo "account_source=$ACCOUNT_SOURCE"

    ALLOWED_USERS=$(awk -F= '/^allowed_users=/{print $2; exit}' "$CONFIG")
    if [ "$ACCOUNT_SOURCE" = "local" ]; then
        echo "allowed_users (smartphone/passkey eligible): ${ALLOWED_USERS:-<none configured>}"
    else
        MIN_UID=$(awk -F= '/^minimum_uid=/{print $2; exit}' "$CONFIG")
        DENY_USERS=$(awk -F= '/^deny_users=/{print $2; exit}' "$CONFIG")
        ALLOWED_GROUPS=$(awk -F= '/^allowed_groups=/{print $2; exit}' "$CONFIG")
        echo "account_source=nss: minimum_uid=${MIN_UID:-1000} deny_users=root,${DENY_USERS:-} allowed_groups=${ALLOWED_GROUPS:-<none>}"
        [ -n "$ALLOWED_USERS" ] && echo "additionally restricted to: $ALLOWED_USERS"
    fi

    echo
    echo "FIDO2 credentials enrolled:"
    if [ -f "$SHARE_DIR/list-fido2-credentials.sh" ]; then
        bash "$SHARE_DIR/list-fido2-credentials.sh"
    else
        echo "  (list-fido2-credentials.sh not found)"
    fi
    ;;

mode-status)
    [ "$(id -u)" -eq 0 ] || {
        echo "must run as root" >&2
        false
    }

    [ -f "$SHARE_DIR/theme-mode.sh" ] || {
        echo "[FAIL] $SHARE_DIR/theme-mode.sh not found" >&2
        false
    }

    exec bash "$SHARE_DIR/theme-mode.sh" status
    ;;

apply-mode)
    [ "$(id -u)" -eq 0 ] || {
        echo "must run as root" >&2
        false
    }

    MODE="${2:-}"

    case "$MODE" in
        native|compatibility|backend-only)
            ;;
        *)
            echo                 "usage: $0 apply-mode {native|compatibility|backend-only}"                 >&2
            false
            ;;
    esac

    [ -f "$SHARE_DIR/theme-mode.sh" ] || {
        echo "[FAIL] $SHARE_DIR/theme-mode.sh not found" >&2
        false
    }

    exec bash "$SHARE_DIR/theme-mode.sh" apply "$MODE"
    ;;

migrate-preflight)
    [ "$(id -u)" -eq 0 ] || {
        echo "must run as root" >&2
        false
    }

    MODE="${2:-}"

    case "$MODE" in
        native|compatibility|backend-only)
            ;;
        *)
            echo                 "usage: $0 migrate-preflight {native|compatibility|backend-only}"                 >&2
            false
            ;;
    esac

    [ -f "$SHARE_DIR/theme-migrate.sh" ] || {
        echo "[FAIL] $SHARE_DIR/theme-migrate.sh not found" >&2
        false
    }

    exec bash "$SHARE_DIR/theme-migrate.sh" preflight "$MODE"
    ;;

migrate)
    [ "$(id -u)" -eq 0 ] || {
        echo "must run as root" >&2
        false
    }

    MODE="${2:-}"

    case "$MODE" in
        native|compatibility|backend-only)
            ;;
        *)
            echo                 "usage: $0 migrate {native|compatibility|backend-only}"                 >&2
            false
            ;;
    esac

    [ -f "$SHARE_DIR/theme-migrate.sh" ] || {
        echo "[FAIL] $SHARE_DIR/theme-migrate.sh not found" >&2
        false
    }

    exec bash "$SHARE_DIR/theme-migrate.sh" migrate "$MODE"
    ;;

rollback-migration)
    [ "$(id -u)" -eq 0 ] || {
        echo "must run as root" >&2
        false
    }

    [ -f "$SHARE_DIR/theme-migrate.sh" ] || {
        echo "[FAIL] $SHARE_DIR/theme-migrate.sh not found" >&2
        false
    }

    exec bash "$SHARE_DIR/theme-migrate.sh" rollback-migration
    ;;

migrate-resume)
    [ "$(id -u)" -eq 0 ] || {
        echo "must run as root" >&2
        false
    }

    [ -f "$SHARE_DIR/theme-migrate.sh" ] || {
        echo "[FAIL] $SHARE_DIR/theme-migrate.sh not found" >&2
        false
    }

    exec bash "$SHARE_DIR/theme-migrate.sh" resume
    ;;

migrate-status)
    [ "$(id -u)" -eq 0 ] || {
        echo "must run as root" >&2
        false
    }

    [ -f "$SHARE_DIR/theme-migrate.sh" ] || {
        echo "[FAIL] $SHARE_DIR/theme-migrate.sh not found" >&2
        false
    }

    exec bash "$SHARE_DIR/theme-migrate.sh" status
    ;;

audit-log)
    [ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }
    # The broker's log lines carry Go's default "log" package timestamp
    # prefix (e.g. "2026/09/10 02:41:53 SECURITY: ..."), so the pattern
    # must not anchor at the start of the line.
    exec journalctl -u sddm-authelia-passkey-broker --no-pager -o cat -g 'SECURITY:'
    ;;

*)
    usage
    ;;
esac
