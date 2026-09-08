#!/bin/bash
# Emergency rollback: restores the pre-install /etc/pam.d/sddm from the
# timestamped backup install.sh created, and removes every component this
# project installed. Does NOT touch common-auth, sudo PAM, sshd PAM,
# LUKS, or initramfs. Never restarts SDDM automatically.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }

BACKUP="${1:-}"
if [ -z "$BACKUP" ]; then
    BACKUP=$(ls -dt /root/sddm-authelia-passkey-backup-* 2>/dev/null | head -1 || true)
fi
[ -n "$BACKUP" ] && [ -d "$BACKUP" ] || { echo "no backup directory found/given"; exit 1; }
echo "using backup: $BACKUP"

echo "== restoring pre-install /etc/pam.d/sddm =="
install -o root -g root -m 0644 -T "$BACKUP/sddm.pam.orig" /etc/pam.d/sddm
sha256sum /etc/pam.d/sddm
diff -u "$BACKUP/sddm.pam.orig.sha256" <(sha256sum /etc/pam.d/sddm) && echo "HASH_MATCHES_BACKUP"

echo "== stopping/disabling services =="
systemctl disable --now sddm-authelia-passkey-kwallet-secretd.service 2>&1 || true
systemctl disable --now sddm-authelia-passkey-broker.service 2>&1 || true

echo "== removing installed components =="
rm -f /usr/lib/x86_64-linux-gnu/security/pam_authelia_passkey.so
rm -f /lib/x86_64-linux-gnu/security/pam_authelia_passkey.so
rm -rf /usr/lib/sddm-authelia-passkey
rm -f /etc/systemd/system/sddm-authelia-passkey-broker.service
rm -f /etc/systemd/system/sddm-authelia-passkey-kwallet-secretd.service
rm -f /etc/credstore.encrypted/kwallet.secret
systemctl daemon-reload

echo "== theme selection (if this project's theme was selected, revert) =="
if grep -q 'debian-breeze-authelia-passkey' /etc/sddm.conf.d/*.conf 2>/dev/null; then
    grep -rl 'debian-breeze-authelia-passkey' /etc/sddm.conf.d/*.conf 2>/dev/null | xargs -r rm -f
    echo "removed theme override, SDDM will use its compiled default on next restart"
fi
rm -rf /usr/share/sddm/themes/debian-breeze-authelia-passkey

echo
echo "ROLLBACK=DONE"
echo "Note: config at /etc/sddm-authelia-passkey/ was left in place; remove it manually if desired."
