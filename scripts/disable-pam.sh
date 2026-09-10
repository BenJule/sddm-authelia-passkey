#!/bin/bash
# Cleanly removes the pam_authelia_passkey.so line (and its 3 accompanying
# lines: a leading blank line and two comment lines) added by
# scripts/enable-pam.sh from /etc/pam.d/sddm, restoring the PAM stack to
# exactly what it was before this project was integrated. Symmetric
# counterpart to enable-pam.sh, which previously had no removal path.
#
# Refuses (does not guess) if scripts/enable-fido2.sh's pam_u2f.so line is
# still present: that line was inserted directly above the
# pam_authelia_passkey.so line, so removing this block first would leave
# pam_u2f.so pointing at nothing sensible and could misalign the
# [success=N] jump target. Run disable-fido2.sh first in that case.
#
# Idempotent - a no-op if pam_authelia_passkey.so isn't present. Never
# touches common-auth, sudo PAM, or sshd PAM, never restarts SDDM. Does
# not remove the broker/PAM-module binaries or config themselves - only
# the PAM stack line.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }

ok()   { echo "[OK]   $*"; }
info() { echo "[INFO] $*"; }
bad()  { echo "[FAIL] $*" >&2; }

PAMFILE=/etc/pam.d/sddm
[ -f "$PAMFILE" ] || { bad "$PAMFILE not found"; exit 1; }

if ! grep -q 'pam_authelia_passkey\.so' "$PAMFILE"; then
    info "$PAMFILE has no pam_authelia_passkey.so line, nothing to do"
    echo "PAM_REMOVE=GREEN"
    exit 0
fi

if grep -q 'pam_u2f\.so' "$PAMFILE"; then
    bad "pam_u2f.so (FIDO2) is still integrated above pam_authelia_passkey.so"
    bad "run scripts/disable-fido2.sh first, then re-run this script"
    bad "PAM_REMOVE=REFUSED - $PAMFILE was NOT changed."
    exit 1
fi

BACKUP="/root/sddm-authelia-passkey-backup-$(date +%Y%m%d-%H%M%S)-pam-disable"
mkdir -p "$BACKUP"
cp -a "$PAMFILE" "$BACKUP/sddm.pam.orig"
sha256sum /etc/pam.d/common-auth /etc/pam.d/sudo /etc/pam.d/sshd > "$BACKUP/common-auth-sudo-sshd.sha256" 2>/dev/null || true
info "backup: $BACKUP"

TMPFILE=$(mktemp)
# enable-pam.sh's insertion, in order, after the matched pam_succeed_if.so
# line (which it preserves): a blank line, two comment lines, then the
# pam_authelia_passkey.so auth line - always exactly these 4 lines, so we
# always remove exactly 4 lines after the match, never conditionally.
awk '
    /^auth[ \t]+required[ \t]+pam_succeed_if\.so[ \t]+user[ \t]*!=[ \t]*root[ \t]+quiet_success/ && !done {
        print
        skip = 4
        done = 1
        next
    }
    skip > 0 { skip--; next }
    { print }
' "$PAMFILE" > "$TMPFILE"

if grep -q 'pam_authelia_passkey\.so' "$TMPFILE"; then
    bad "failed to fully remove pam_authelia_passkey.so line - refusing to install a half-edited file"
    rm -f "$TMPFILE"
    exit 1
fi

install -o root -g root -m 0644 -T "$TMPFILE" "$PAMFILE"
rm -f "$TMPFILE"

sha256sum /etc/pam.d/common-auth /etc/pam.d/sudo /etc/pam.d/sshd > /tmp/sddm-authelia-passkey-pam-disable-post.sha256 2>/dev/null || true
if ! diff -q "$BACKUP/common-auth-sudo-sshd.sha256" /tmp/sddm-authelia-passkey-pam-disable-post.sha256 >/dev/null 2>&1; then
    bad "SAFETY VIOLATION: common-auth/sudo/sshd PAM changed unexpectedly - rolling back."
    cp -a "$BACKUP/sddm.pam.orig" "$PAMFILE"
    exit 1
fi
rm -f /tmp/sddm-authelia-passkey-pam-disable-post.sha256

ok "PAM_REMOVE=GREEN"
echo "READY_FOR_SDDM_RESTART=YES (not done automatically - restart sddm yourself when ready)"
