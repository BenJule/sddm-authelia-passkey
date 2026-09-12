#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO/scripts/validate-branding-overrides.sh"

bash -n "$SCRIPT"

ROOT="$(mktemp -d)"

cleanup() {
    rm -rf "$ROOT"
}

trap cleanup EXIT

NATIVE_DIR="$ROOT/usr/share/sddm/themes/sddm-authelia-passkey-native"
COMPAT_DIR="$ROOT/usr/share/sddm/themes/debian-breeze-authelia-passkey"

mkdir -p "$NATIVE_DIR" "$COMPAT_DIR"

run_validate() {
    SDDM_AUTHELIA_TEST_ROOT="$ROOT" bash "$SCRIPT"
}

# --- absent override: no-op, no files created ---
OUT="$(run_validate)"
printf '%s\n' "$OUT" | grep -q '^BRANDING_OVERRIDE_NATIVE=ABSENT$'
printf '%s\n' "$OUT" | grep -q '^BRANDING_OVERRIDE_COMPAT=ABSENT$'
printf '%s\n' "$OUT" | grep -q '^BRANDING_VALIDATION_RESULT=GREEN$'

echo "ABSENT_IS_NOOP=GREEN"

# --- symlink override is neutralized, target file itself untouched ---
ln -s /etc/hostname "$NATIVE_DIR/theme.conf.user"

OUT="$(run_validate)"
printf '%s\n' "$OUT" | grep -q '^BRANDING_OVERRIDE_NATIVE=UNSAFE reason="symlink"$'
printf '%s\n' "$OUT" | grep -q '^BRANDING_OVERRIDE_NATIVE_NEUTRALIZED='

test ! -e "$NATIVE_DIR/theme.conf.user"
test ! -L "$NATIVE_DIR/theme.conf.user"
test -e /etc/hostname

REJECTED="$(find "$NATIVE_DIR" -name 'theme.conf.user.rejected-unsafe.*')"
test -L "$REJECTED"
test "$(readlink "$REJECTED")" = /etc/hostname

echo "SYMLINK_NEUTRALIZED_TARGET_UNTOUCHED=GREEN"

rm -f "$REJECTED"

# --- world-writable regular file is neutralized. The exact reported
# reason ("group/world writable") only fires once ownership is already
# root:root, so that specific assertion needs real root; otherwise
# just confirm unsafe-detection-and-neutralization happens at all.
echo "ui_brand_name=x" > "$COMPAT_DIR/theme.conf.user"
chmod 0666 "$COMPAT_DIR/theme.conf.user"

if [ "$(id -u)" -eq 0 ]; then
    chown root:root "$COMPAT_DIR/theme.conf.user"
fi

OUT="$(run_validate)"
printf '%s\n' "$OUT" | grep -q '^BRANDING_OVERRIDE_COMPAT=UNSAFE'
test ! -e "$COMPAT_DIR/theme.conf.user"

if [ "$(id -u)" -eq 0 ]; then
    printf '%s\n' "$OUT" | grep -q '^BRANDING_OVERRIDE_COMPAT=UNSAFE reason="group/world writable (mode 666)"$'
fi

echo "WORLD_WRITABLE_NEUTRALIZED=GREEN"

rm -f "$COMPAT_DIR"/theme.conf.user.rejected-unsafe.*

# --- non-root-owned regular file is neutralized ---
echo "ui_brand_name=x" > "$NATIVE_DIR/theme.conf.user"
chmod 0644 "$NATIVE_DIR/theme.conf.user"

if [ "$(id -u)" -eq 0 ]; then
    chown 1000:1000 "$NATIVE_DIR/theme.conf.user"

    OUT="$(run_validate)"
    printf '%s\n' "$OUT" | grep -q '^BRANDING_OVERRIDE_NATIVE=UNSAFE reason="not root:root owned (was 1000:1000)"$'
    test ! -e "$NATIVE_DIR/theme.conf.user"

    echo "NON_ROOT_OWNED_NEUTRALIZED=GREEN"

    rm -f "$NATIVE_DIR"/theme.conf.user.rejected-unsafe.*

    # --- safe file (root:root, 0644) is preserved untouched ---
    echo "ui_brand_name=Safe" > "$NATIVE_DIR/theme.conf.user"
    chown root:root "$NATIVE_DIR/theme.conf.user"
    chmod 0644 "$NATIVE_DIR/theme.conf.user"

    BEFORE_SUM="$(sha256sum "$NATIVE_DIR/theme.conf.user")"

    OUT="$(run_validate)"
    printf '%s\n' "$OUT" | grep -q '^BRANDING_OVERRIDE_NATIVE=SAFE$'

    AFTER_SUM="$(sha256sum "$NATIVE_DIR/theme.conf.user")"
    test "$BEFORE_SUM" = "$AFTER_SUM"

    echo "SAFE_FILE_PRESERVED=GREEN"
else
    echo "SKIP_ROOT_ONLY_ASSERTIONS=not running as root locally"
fi

# --- never touches PAM, broker, FIDO2, OIDC, or theme selection mode ---
if grep -Eq \
    'pam_authelia_passkey|/etc/pam\.d|apt-get|dpkg[[:space:]]|systemctl|theme-mode\.sh|theme-migrate\.sh' \
    "$SCRIPT"
then
    echo "FAIL: validate-branding-overrides.sh touches out-of-scope state"
    false
fi

echo "SCOPE_INVARIANTS=GREEN"

echo "VALIDATE_BRANDING_OVERRIDES_TEST=GREEN"
