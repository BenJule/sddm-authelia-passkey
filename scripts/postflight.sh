#!/bin/bash
# READ-ONLY post-install verification. Run after install.sh, and again
# after any SDDM restart.
set -euo pipefail

FAIL=0
ok()  { echo "[OK]   $*"; }
bad() { echo "[FAIL] $*"; FAIL=1; }

systemctl is-active --quiet sddm-authelia-passkey-broker && ok "broker active" || bad "broker not active"
curl -s -o /dev/null -w '%{http_code}\n' -X POST 'http://127.0.0.1:7899/start?username=nobody-not-allowlisted' | grep -q 403 && \
    ok "broker rejects non-allowlisted user (403)" || bad "broker did not reject non-allowlisted user"

if grep -q 'pam_authelia_passkey.so' /etc/pam.d/sddm; then
    ok "/etc/pam.d/sddm integrated"
    sha256sum /etc/pam.d/sddm
else
    bad "/etc/pam.d/sddm not integrated (may be expected if install.sh refused - check its output)"
fi

systemctl is-active --quiet sddm && ok "sddm active" || bad "sddm not active"
DM_TARGET=$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)
[ "$(basename "${DM_TARGET:-}")" = "sddm.service" ] && ok "display-manager.service -> sddm.service" || bad "display-manager.service unexpected"

if systemctl list-unit-files sddm-authelia-passkey-kwallet-secretd.service >/dev/null 2>&1; then
    if systemctl is-enabled --quiet sddm-authelia-passkey-kwallet-secretd 2>/dev/null; then
        systemctl is-active --quiet sddm-authelia-passkey-kwallet-secretd && ok "kwallet-secretd active" || bad "kwallet-secretd enabled but not active"
    else
        echo "[INFO] kwallet-secretd installed but not enabled (kwallet_auto_unlock is off - this is the default)"
    fi
fi

CURRENT_THEME=$(grep -h '^Current=' /etc/sddm.conf.d/*.conf 2>/dev/null | tail -1 || true)
echo "[INFO] current theme override: ${CURRENT_THEME:-<none, using compiled default>}"

echo
[ "$FAIL" -eq 0 ] && echo "POSTFLIGHT_RESULT=GREEN" || { echo "POSTFLIGHT_RESULT=RED"; exit 1; }
