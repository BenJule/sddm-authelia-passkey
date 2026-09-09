#!/bin/bash
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }

BACKUP="${1:-}"
pam_integrated=0

if grep -q 'pam_authelia_passkey.so' /etc/pam.d/sddm 2>/dev/null; then
    pam_integrated=1
fi

if [ "$pam_integrated" -eq 1 ]; then
    if [ -z "$BACKUP" ]; then
        BACKUP="$(ls -dt /root/sddm-authelia-passkey-backup-* 2>/dev/null | head -1 || true)"
    fi

    [ -n "$BACKUP" ] && [ -d "$BACKUP" ] || {
        echo "PAM is integrated but no rollback backup directory was found" >&2
        exit 1
    }

    [ -f "$BACKUP/sddm.pam.orig" ] || {
        echo "backup missing sddm.pam.orig: $BACKUP" >&2
        exit 1
    }

    install -o root -g root -m 0644 -T "$BACKUP/sddm.pam.orig" /etc/pam.d/sddm

    if [ -f "$BACKUP/sddm.pam.orig.sha256" ]; then
        EXPECTED="$(awk '{print $1; exit}' "$BACKUP/sddm.pam.orig.sha256")"
        ACTUAL="$(sha256sum /etc/pam.d/sddm | awk '{print $1}')"
        [ "$EXPECTED" = "$ACTUAL" ] || {
            echo "restored PAM hash does not match backup" >&2
            exit 1
        }
    fi

    echo "PAM_ROLLBACK=GREEN"
else
    echo "PAM_ROLLBACK=NOT_NEEDED"
fi

systemctl disable --now sddm-authelia-passkey-kwallet-secretd.service 2>/dev/null || true
systemctl disable --now sddm-authelia-passkey-broker.service 2>/dev/null || true

if grep -q 'debian-breeze-authelia-passkey' /etc/sddm.conf.d/*.conf 2>/dev/null; then
    grep -rl 'debian-breeze-authelia-passkey' /etc/sddm.conf.d/*.conf 2>/dev/null | xargs -r rm -f
fi

rm -rf /usr/share/sddm/themes/debian-breeze-authelia-passkey

if dpkg-query -W -f='${Status}' sddm-authelia-passkey 2>/dev/null | grep -q 'ok installed'; then
    echo "PACKAGE_MANAGED=YES"
else
    echo "PACKAGE_MANAGED=NO"
    rm -f /usr/lib/x86_64-linux-gnu/security/pam_authelia_passkey.so
    rm -f /lib/x86_64-linux-gnu/security/pam_authelia_passkey.so
    rm -rf /usr/lib/sddm-authelia-passkey
    rm -f /etc/systemd/system/sddm-authelia-passkey-broker.service
    rm -f /etc/systemd/system/sddm-authelia-passkey-kwallet-secretd.service
fi

systemctl daemon-reload

echo "KWALLET_CREDENTIALS_RETAINED=YES"
echo "CONFIG_RETAINED=/etc/sddm-authelia-passkey"
echo "SDDM_RESTART_USED=NO"
echo "ROLLBACK=DONE"
