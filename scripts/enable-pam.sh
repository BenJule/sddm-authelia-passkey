#!/bin/bash
# Integrates pam_authelia_passkey.so into /etc/pam.d/sddm. Separate from
# install.sh so it also works standalone after installing the .deb
# package (which deliberately does NOT touch PAM automatically in
# postinst - see docs/installation.md). Safe to re-run; a no-op if
# already integrated. Never touches common-auth, sudo PAM, or sshd PAM.
# Never restarts SDDM.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }

ok()   { echo "[OK]   $*"; }
bad()  { echo "[FAIL] $*" >&2; }
info() { echo "[INFO] $*"; }

[ -f /etc/pam.d/sddm ] || { bad "/etc/pam.d/sddm not found"; exit 1; }
[ -f /usr/lib/x86_64-linux-gnu/security/pam_authelia_passkey.so ] || \
[ -f /lib/x86_64-linux-gnu/security/pam_authelia_passkey.so ] || \
    { bad "pam_authelia_passkey.so not installed yet - run install.sh or install the .deb package first"; exit 1; }

BACKUP="/root/sddm-authelia-passkey-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
cp -a /etc/pam.d/sddm "$BACKUP/sddm.pam.orig"
sha256sum /etc/pam.d/sddm > "$BACKUP/sddm.pam.orig.sha256"
sha256sum /etc/pam.d/common-auth /etc/pam.d/sudo /etc/pam.d/sshd > "$BACKUP/common-auth-sudo-sshd.sha256" 2>/dev/null || true
info "backup: $BACKUP"

# Debian's pam-auth-update legitimately produces common-auth files of
# different lengths depending on which profiles are enabled (e.g. a
# local-only system vs one joined to SSSD/AD) - both are supported, and
# the exact line count (N, used below for the [success=N] jump) is always
# computed fresh from the live file, never assumed. What we DO require is
# that the file follows the standard pam-auth-update convention: some
# number of "[success=k default=ignore] pam_X.so ..." identity-source
# lines, followed by the fixed "requisite pam_deny.so" / "required
# pam_permit.so" failsafe pair. If a site hand-edited common-auth into
# some other shape, our jump-skip arithmetic can no longer be trusted to
# land in the right place, so we refuse rather than guess.
COMMON_AUTH_LINES=$(grep -c '^auth' /etc/pam.d/common-auth)
LAST_TWO=$(grep '^auth' /etc/pam.d/common-auth | tail -2)
if ! printf '%s\n' "$LAST_TWO" | grep -qE 'requisite[[:space:]]+pam_deny\.so' || \
   ! printf '%s\n' "$LAST_TWO" | tail -1 | grep -qE 'required[[:space:]]+pam_permit\.so'; then
    bad "installed common-auth does not end in the standard pam-auth-update"
    bad "'requisite pam_deny.so' / 'required pam_permit.so' failsafe pair."
    bad "PAM_INSTALL=REFUSED - /etc/pam.d/sddm was NOT changed."
    bad "See docs/installation.md to add PAM integration manually/carefully for your setup."
    echo "READY_FOR_SDDM_RESTART=NO"
    exit 1
fi

if grep -q 'pam_authelia_passkey.so' /etc/pam.d/sddm; then
    info "/etc/pam.d/sddm already integrated, leaving it untouched"
else
    TMPFILE=$(mktemp)
    awk -v n="$COMMON_AUTH_LINES" '
        /^auth[ \t]+required[ \t]+pam_succeed_if\.so[ \t]+user[ \t]*!=[ \t]*root[ \t]+quiet_success/ && !done {
            print
            print ""
            print "# Authelia Passkey passwordless path + optional KWallet auto-unlock."
            print "# See docs/architecture.md for the PAM control-flow design."
            print "auth    [success=" n " default=ignore]      pam_authelia_passkey.so"
            done = 1
            next
        }
        { print }
    ' /etc/pam.d/sddm > "$TMPFILE"
    if ! grep -q 'pam_authelia_passkey.so' "$TMPFILE"; then
        bad "could not locate the expected insertion point in /etc/pam.d/sddm"
        bad "PAM_INSTALL=REFUSED - /etc/pam.d/sddm was NOT changed."
        rm -f "$TMPFILE"
        echo "READY_FOR_SDDM_RESTART=NO"
        exit 1
    fi
    install -o root -g root -m 0644 -T "$TMPFILE" /etc/pam.d/sddm
    rm -f "$TMPFILE"
    ok "PAM_INSTALL=DONE (success=$COMMON_AUTH_LINES computed from live common-auth, not assumed)"
fi

sha256sum /etc/pam.d/common-auth /etc/pam.d/sudo /etc/pam.d/sshd > /tmp/sddm-authelia-passkey-post.sha256 2>/dev/null || true
if ! diff -q "$BACKUP/common-auth-sudo-sshd.sha256" /tmp/sddm-authelia-passkey-post.sha256 >/dev/null 2>&1; then
    bad "SAFETY VIOLATION: common-auth/sudo/sshd PAM changed unexpectedly - this must never happen. Rolling back."
    cp -a "$BACKUP/sddm.pam.orig" /etc/pam.d/sddm
    exit 1
fi
rm -f /tmp/sddm-authelia-passkey-post.sha256

echo
echo "PAM_INSTALL=GREEN"
echo "READY_FOR_SDDM_RESTART=YES (not done automatically - restart sddm yourself when ready)"
