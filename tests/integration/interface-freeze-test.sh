#!/bin/bash
set -euo pipefail

# v1.19.0: guards the frozen interfaces documented in docs/stability.md
# (install-mode, migration, branding schema) against accidental removal.
# This is deliberately a simple presence check, not a schema validator -
# it exists to catch "field silently renamed/removed" during later
# refactors, not to replace the human review a real breaking change
# needs before shipping (see docs/stability.md's own deprecation rule).

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

MODE="$REPO/scripts/theme-mode.sh"
MIGRATE="$REPO/scripts/theme-migrate.sh"
BRANDING="$REPO/scripts/validate-branding-overrides.sh"
CONFIG_EXAMPLE="$REPO/config/examples/config.conf.example"
NATIVE_BRANDING="$REPO/theme/native/components/BrandingConfig.qml"

FAIL=0

require() {
    local file="$1"
    local pattern="$2"

    if ! grep -Fq -- "$pattern" "$file"; then
        echo "FAIL: missing frozen field '$pattern' in $file" >&2
        FAIL=1
    fi
}

# --- install-mode interface ---
for field in \
    'INSTALL_MODE=' \
    'THEME_SELECTION_MANAGED=' \
    'EFFECTIVE_THEME=' \
    'MODE_TARGET=' \
    'TARGET_VALID=' \
    'SELECTION_FILE=' \
    'BASELINE_THEME=' \
    'RESTORED_THEME=' \
    'MODE_APPLY=' \
    'SDDM_RESTART_USED=' \
    'THEME_MODE_ERROR=' \
    'TARGET='
do
    require "$MODE" "$field"
done

for mode in native compatibility backend-only; do
    require "$MODE" "$mode"
done

# --- migration interface ---
for field in \
    'MIGRATE_FROM_MODE=' \
    'MIGRATE_TO_MODE=' \
    'MIGRATE_NOOP=' \
    'MIGRATE_TARGET_VALID=' \
    'MIGRATE_INTERRUPTED=' \
    'MIGRATE_PREFLIGHT=' \
    'MIGRATE_APPLY=' \
    'MIGRATION_ID=' \
    'MIGRATE_ROLLBACK_SOURCE=' \
    'MIGRATE_ROLLBACK_FROM=' \
    'MIGRATE_ROLLBACK_TO=' \
    'MIGRATE_ROLLBACK_RESULT=' \
    'MIGRATE_RESUME_FROM=' \
    'MIGRATE_RESUME_TO=' \
    'MIGRATE_RESUME_RESULT=' \
    'MIGRATE_LAST_FROM=' \
    'MIGRATE_LAST_TO=' \
    'MIGRATE_LAST_COMPLETED_AT=' \
    'MIGRATE_INTERRUPTED_FROM=' \
    'MIGRATE_INTERRUPTED_TO=' \
    'MIGRATE_INTERRUPTED_STARTED_AT=' \
    'MIGRATE_INTERRUPTED_PID=' \
    'THEME_MIGRATE_ERROR='
do
    require "$MIGRATE" "$field"
done

for subcommand in preflight migrate rollback-migration resume status; do
    require "$MIGRATE" "$subcommand"
done

# --- branding schema ---
for key in \
    'ui_brand_name' \
    'ui_brand_logo' \
    'ui_show_hostname' \
    'ui_show_domain' \
    'ui_brand_domain' \
    'ui_show_avatar' \
    'ui_accent' \
    'ui_accent_color'
do
    require "$NATIVE_BRANDING" "$key"
done

for field in 'BRANDING_OVERRIDE_' 'BRANDING_VALIDATION_RESULT='; do
    require "$BRANDING" "$field"
done

# --- config.conf schema (spot-check the documented example is intact) ---
for key in \
    'provider_kind=' \
    'authelia_base_url=' \
    'oidc_client_id=' \
    'allowed_verification_host=' \
    'account_source=' \
    'allowed_users=' \
    'minimum_uid=' \
    'deny_users=' \
    'allowed_groups=' \
    'require_group_match=' \
    'approval_ttl_seconds=' \
    'user_cooldown_seconds=' \
    'max_parallel_flows=' \
    'failure_lockout_threshold=' \
    'failure_lockout_seconds=' \
    'kwallet_auto_unlock=' \
    'kwallet_credential_name=' \
    'fido2_authfile=' \
    'fido2_require_user_verification=' \
    'fido2_require_pin_verification='
do
    require "$CONFIG_EXAMPLE" "$key"
done

if [ "$FAIL" -ne 0 ]; then
    echo "INTERFACE_FREEZE_RESULT=RED"
    exit 1
fi

echo "INTERFACE_FREEZE_RESULT=GREEN"
