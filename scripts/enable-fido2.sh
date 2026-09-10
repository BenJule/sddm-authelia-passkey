#!/bin/bash
# Integrates pam_u2f.so into /etc/pam.d/sddm as an additive, opt-in,
# faster local hardware-security-key path tried BEFORE the existing
# smartphone/passkey line and the password fallback - see docs/fido2.md.
# This project never implements the FIDO2/CTAP2/U2F protocol itself:
# pam_u2f.so (package libpam-u2f) is the mature, widely-used upstream PAM
# module; this script only wires it in additively using the exact same
# dynamic [success=N default=ignore] jump-skip pattern already used for
# pam_authelia_passkey.so, computed fresh from the live common-auth, not
# assumed. Requires pam_authelia_passkey.so to already be integrated
# (scripts/enable-pam.sh) since this inserts directly above that line.
# Safe to re-run (idempotent no-op if already integrated). Never touches
# common-auth, sudo PAM, or sshd PAM. Never restarts SDDM.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }

ok()   { echo "[OK]   $*"; }
bad()  { echo "[FAIL] $*" >&2; }
info() { echo "[INFO] $*"; }

CONFIG=/etc/sddm-authelia-passkey/config.conf
PAMFILE=/etc/pam.d/sddm

[ -f "$PAMFILE" ] || { bad "$PAMFILE not found"; exit 1; }

FOUND=0
for d in /usr/lib/x86_64-linux-gnu/security /lib/x86_64-linux-gnu/security; do
    [ -f "$d/pam_u2f.so" ] && FOUND=1
done
[ "$FOUND" -eq 1 ] || { bad "pam_u2f.so not installed - run: apt install libpam-u2f"; exit 1; }

grep -q 'pam_authelia_passkey\.so' "$PAMFILE" || {
    bad "pam_authelia_passkey.so not integrated yet - run scripts/enable-pam.sh first"
    exit 1
}

if grep -q 'pam_u2f\.so' "$PAMFILE"; then
    info "$PAMFILE already has pam_u2f.so integrated, leaving it untouched"
    echo "FIDO2_PAM_INSTALL=GREEN"
    echo "READY_FOR_SDDM_RESTART=YES"
    exit 0
fi

AUTHFILE=/etc/sddm-authelia-passkey/fido2_mappings
UV=true
PINV=false
if [ -f "$CONFIG" ]; then
    v=$(awk -F= '/^fido2_authfile=/{print $2; exit}' "$CONFIG") && [ -n "$v" ] && AUTHFILE="$v"
    v=$(awk -F= '/^fido2_require_user_verification=/{print $2; exit}' "$CONFIG") && [ -n "$v" ] && UV="$v"
    v=$(awk -F= '/^fido2_require_pin_verification=/{print $2; exit}' "$CONFIG") && [ -n "$v" ] && PINV="$v"
fi

MODULE_ARGS="authfile=$AUTHFILE cue"
case "$(tr '[:upper:]' '[:lower:]' <<<"$UV")" in
    true|1|yes) MODULE_ARGS="$MODULE_ARGS userverification=1" ;;
    false|0|no) MODULE_ARGS="$MODULE_ARGS userverification=0" ;;
esac
case "$(tr '[:upper:]' '[:lower:]' <<<"$PINV")" in
    true|1|yes) MODULE_ARGS="$MODULE_ARGS pinverification=1" ;;
esac

COMMON_AUTH_LINES=$(grep -c '^auth' /etc/pam.d/common-auth)
SKIP=$((COMMON_AUTH_LINES + 1))

BACKUP="/root/sddm-authelia-passkey-backup-$(date +%Y%m%d-%H%M%S)-fido2"
mkdir -p "$BACKUP"
cp -a "$PAMFILE" "$BACKUP/sddm.pam.orig"
sha256sum /etc/pam.d/common-auth /etc/pam.d/sudo /etc/pam.d/sshd > "$BACKUP/common-auth-sudo-sshd.sha256" 2>/dev/null || true
info "backup: $BACKUP"

TMPFILE=$(mktemp)
awk -v skip="$SKIP" -v args="$MODULE_ARGS" '
    /^auth[ \t]+\[success=[0-9]+[ \t]+default=ignore\][ \t]+pam_authelia_passkey\.so/ && !done {
        print "# Native FIDO2/U2F security key path (optional, opt-in) -"
        print "# tried first: fastest local path, no phone/network needed."
        print "# See docs/fido2.md."
        print "auth    [success=" skip " default=ignore]      pam_u2f.so " args
        print ""
        print $0
        done = 1
        next
    }
    { print }
' "$PAMFILE" > "$TMPFILE"

if ! grep -q 'pam_u2f\.so' "$TMPFILE"; then
    bad "could not locate the pam_authelia_passkey.so line to insert above"
    bad "FIDO2_PAM_INSTALL=REFUSED - $PAMFILE was NOT changed."
    rm -f "$TMPFILE"
    exit 1
fi

install -o root -g root -m 0644 -T "$TMPFILE" "$PAMFILE"
rm -f "$TMPFILE"

sha256sum /etc/pam.d/common-auth /etc/pam.d/sudo /etc/pam.d/sshd > /tmp/sddm-authelia-passkey-fido2-post.sha256 2>/dev/null || true
if ! diff -q "$BACKUP/common-auth-sudo-sshd.sha256" /tmp/sddm-authelia-passkey-fido2-post.sha256 >/dev/null 2>&1; then
    bad "SAFETY VIOLATION: common-auth/sudo/sshd PAM changed unexpectedly - rolling back."
    cp -a "$BACKUP/sddm.pam.orig" "$PAMFILE"
    exit 1
fi
rm -f /tmp/sddm-authelia-passkey-fido2-post.sha256

install -d -m 0755 -o root -g root "$(dirname "$AUTHFILE")"
[ -f "$AUTHFILE" ] || install -o root -g root -m 0600 /dev/null "$AUTHFILE"

echo
ok "FIDO2_PAM_INSTALL=GREEN (success=$SKIP computed fresh from live common-auth)"
echo "READY_FOR_SDDM_RESTART=YES (not done automatically - restart sddm yourself when ready)"
