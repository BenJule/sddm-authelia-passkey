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
# Consumes the whole block enable-fido2.sh can produce, in either shape:
# marker comment, 1-2 more comment lines, an optional group-gating
# pam_succeed_if.so guard line (only present when fido2_required_group
# was set), the pam_u2f.so line itself, then exactly one trailing blank
# line - classified by content (not a fixed line count) so both the
# gated and ungated variants round-trip byte-identically.
awk '
    /^# Native FIDO2\/U2F security key path/ { insection = 1; next }
    insection && /^#/ { next }
    insection && /pam_succeed_if\.so.*notingroup/ { next }
    insection && /pam_u2f\.so/ { insection = 0; sawline = 1; next }
    sawline && $0 == "" { sawline = 0; next }
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
