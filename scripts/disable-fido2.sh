#!/bin/bash
# Cleanly removes the pam_u2f.so line (and its two preceding comment
# lines) added by enable-fido2.sh from /etc/pam.d/sddm, restoring exactly
# the pam_authelia_passkey.so/common-auth stacking that existed before.
# Idempotent - a no-op if pam_u2f.so isn't present. Never touches
# common-auth, sudo PAM, or sshd PAM, never restarts SDDM. Does not
# remove /etc/sddm-authelia-passkey/fido2_mappings or the libpam-u2f
# package itself - only the PAM stack line.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }

ok()   { echo "[OK]   $*"; }
info() { echo "[INFO] $*"; }
bad()  { echo "[FAIL] $*" >&2; }

PAMFILE=/etc/pam.d/sddm
[ -f "$PAMFILE" ] || { bad "$PAMFILE not found"; exit 1; }

if ! grep -q 'pam_u2f\.so' "$PAMFILE"; then
    info "$PAMFILE has no pam_u2f.so line, nothing to do"
    echo "FIDO2_PAM_REMOVE=GREEN"
    exit 0
fi

BACKUP="/root/sddm-authelia-passkey-backup-$(date +%Y%m%d-%H%M%S)-fido2-disable"
mkdir -p "$BACKUP"
cp -a "$PAMFILE" "$BACKUP/sddm.pam.orig"
sha256sum /etc/pam.d/common-auth /etc/pam.d/sudo /etc/pam.d/sshd > "$BACKUP/common-auth-sudo-sshd.sha256" 2>/dev/null || true

TMPFILE=$(mktemp)
# Exactly 4 lines follow the marker comment line matched below (see
# enable-fido2.sh's own print sequence): the 2nd/3rd comment lines, the
# pam_u2f.so auth line, and a trailing blank line - always remove all 4
# regardless of their content, never conditionally, so a stray blank line
# or comment-shaped text can't accidentally survive or over-consume.
awk '
    /^# Native FIDO2\/U2F security key path/ { skip = 4; next }
    skip > 0 { skip--; next }
    { print }
' "$PAMFILE" > "$TMPFILE"

if grep -q 'pam_u2f\.so' "$TMPFILE"; then
    bad "failed to fully remove pam_u2f.so line - refusing to install a half-edited file"
    rm -f "$TMPFILE"
    exit 1
fi

install -o root -g root -m 0644 -T "$TMPFILE" "$PAMFILE"
rm -f "$TMPFILE"

sha256sum /etc/pam.d/common-auth /etc/pam.d/sudo /etc/pam.d/sshd > /tmp/sddm-authelia-passkey-fido2-disable-post.sha256 2>/dev/null || true
if ! diff -q "$BACKUP/common-auth-sudo-sshd.sha256" /tmp/sddm-authelia-passkey-fido2-disable-post.sha256 >/dev/null 2>&1; then
    bad "SAFETY VIOLATION: common-auth/sudo/sshd PAM changed unexpectedly - rolling back."
    cp -a "$BACKUP/sddm.pam.orig" "$PAMFILE"
    exit 1
fi
rm -f /tmp/sddm-authelia-passkey-fido2-disable-post.sha256

ok "FIDO2_PAM_REMOVE=GREEN"
echo "READY_FOR_SDDM_RESTART=YES (not done automatically)"
