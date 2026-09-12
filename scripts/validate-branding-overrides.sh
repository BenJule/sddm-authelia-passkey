#!/bin/bash
set -euo pipefail
umask 077

# v1.18.0 hardening: theme.conf.user (the optional admin branding
# override, both compat and native theme) is read directly by SDDM's
# own config object with no ownership/writability check of its own -
# the only enforcement point compat theme had was install-theme.sh's
# one-time regenerate-time check, which never re-fires between
# upgrades, and native theme (a static, non-regenerated tree) had none
# at all. This script closes that gap: an unsafe override (symlink,
# not root-owned, group/world-writable) is neutralized (moved aside,
# never deleted) rather than trusted, so the greeter always falls back
# to safe zero-config branding instead of rendering attacker-influenced
# content. Idempotent and safe to run at any time, not just at install.
#
# Never touches PAM, the broker, FIDO2, OIDC, or theme selection mode -
# purely a branding-override safety check.

TEST_ROOT="${SDDM_AUTHELIA_TEST_ROOT:-}"

root_path() {
    printf '%s%s\n' "$TEST_ROOT" "$1"
}

NATIVE_THEME_DIR="$(root_path /usr/share/sddm/themes/sddm-authelia-passkey-native)"
COMPAT_THEME_DIR="$(root_path /usr/share/sddm/themes/debian-breeze-authelia-passkey)"

if [ -z "$TEST_ROOT" ] && [ "$(id -u)" -ne 0 ]; then
    echo "must run as root" >&2
    exit 1
fi

check_one() {
    local label="$1"
    local theme_dir="$2"
    local conf="$theme_dir/theme.conf.user"
    local reason=""

    if [ ! -e "$conf" ] && [ ! -L "$conf" ]; then
        echo "BRANDING_OVERRIDE_${label}=ABSENT"
        return 0
    fi

    if [ -L "$conf" ]; then
        reason="symlink"
    elif [ ! -f "$conf" ]; then
        reason="not a regular file"
    else
        local owner mode mode_dec
        owner="$(stat -c '%u:%g' "$conf")"

        if [ "$owner" != "0:0" ]; then
            reason="not root:root owned (was $owner)"
        else
            mode="$(stat -c '%a' "$conf")"
            mode_dec=$((8#$mode))

            if (( mode_dec & 022 )); then
                reason="group/world writable (mode $mode)"
            fi
        fi
    fi

    if [ -z "$reason" ]; then
        echo "BRANDING_OVERRIDE_${label}=SAFE"
        return 0
    fi

    echo "BRANDING_OVERRIDE_${label}=UNSAFE reason=\"$reason\""

    # PID-qualified: a bare per-second timestamp can collide across two
    # invocations in the same second (e.g. native+compat both unsafe in
    # one run), and mv -n silently no-ops on an existing destination -
    # that would fail OPEN, leaving the unsafe file in place unnoticed.
    local rejected
    rejected="${conf}.rejected-unsafe.$(date -u +%Y%m%dT%H%M%SZ).$$"

    mv -n -- "$conf" "$rejected"

    if [ -e "$conf" ] || [ -L "$conf" ]; then
        echo "BRANDING_OVERRIDE_${label}_NEUTRALIZE_FAILED=$conf" >&2
        return 1
    fi

    echo "BRANDING_OVERRIDE_${label}_NEUTRALIZED=$rejected"
}

check_one NATIVE "$NATIVE_THEME_DIR"
check_one COMPAT "$COMPAT_THEME_DIR"

echo "BRANDING_VALIDATION_RESULT=GREEN"
