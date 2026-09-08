#!/bin/bash
# READ-ONLY preflight check for sddm-authelia-passkey. Never writes
# anything. Exits non-zero (fail closed) if any hard requirement is not
# met. Run as: sudo bash preflight.sh
set -euo pipefail

FAIL=0
ok()   { echo "[OK]   $*"; }
bad()  { echo "[FAIL] $*"; FAIL=1; }
info() { echo "[INFO] $*"; }

[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }

# --- OS / versions -----------------------------------------------------
if [ -f /etc/debian_version ]; then
    DEBVER=$(cat /etc/debian_version)
    [[ "$DEBVER" == 13.* || "$DEBVER" == "trixie/sid" ]] && ok "Debian $DEBVER" || \
        info "Debian $DEBVER - only Debian 13 (Trixie) is officially supported, proceeding is EXPERIMENTAL (see docs/installation.md)"
else
    info "not a Debian system - UNSUPPORTED/EXPERIMENTAL (see docs/installation.md)"
fi

command -v sddm >/dev/null 2>&1 && ok "sddm present" || bad "sddm not found"
SDDM_VER=$(dpkg-query -W -f='${Version}' sddm 2>/dev/null || echo "unknown")
info "sddm version: $SDDM_VER (0.21.x verified)"

dpkg -s libpam-modules >/dev/null 2>&1 && ok "libpam-modules (pam_exec) present" || bad "libpam-modules missing"
[ -d /usr/lib/x86_64-linux-gnu/security ] || [ -d /lib/x86_64-linux-gnu/security ] || \
    bad "expected PAM module directory not found (only x86_64 supported currently)"

# --- SDDM state --------------------------------------------------------
systemctl is-active --quiet sddm && ok "sddm active" || info "sddm not currently active"
DM_TARGET=$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)
[ "$(basename "${DM_TARGET:-}")" = "sddm.service" ] && ok "display-manager.service -> sddm.service" || \
    bad "display-manager.service does not point to sddm - this project only supports SDDM as the display manager"

# --- PAM stack shape (see install.sh for the full rationale) ------------
if [ -f /etc/pam.d/common-auth ]; then
    LAST_TWO=$(grep '^auth' /etc/pam.d/common-auth | tail -2)
    if printf '%s\n' "$LAST_TWO" | grep -qE 'requisite[[:space:]]+pam_deny\.so' && \
       printf '%s\n' "$LAST_TWO" | tail -1 | grep -qE 'required[[:space:]]+pam_permit\.so'; then
        ok "common-auth ends in the standard pam-auth-update failsafe pair ($(grep -c '^auth' /etc/pam.d/common-auth) lines)"
    else
        bad "common-auth does not match the expected pam-auth-update shape - install.sh will refuse to patch PAM"
    fi
else
    bad "/etc/pam.d/common-auth not found"
fi

# --- existing install state ---------------------------------------------
[ -e /usr/lib/sddm-authelia-passkey/broker ] && info "broker binary already installed (re-run scripts/uninstall.sh first for a clean re-install)" || ok "broker not yet installed (clean)"
grep -q 'pam_authelia_passkey.so' /etc/pam.d/sddm 2>/dev/null && info "PAM already integrated" || ok "PAM not yet integrated (clean)"

# --- config / network (only if config already present) ------------------
CONFIG=/etc/sddm-authelia-passkey/config.conf
if [ -f "$CONFIG" ]; then
    BASE_URL=$(awk -F= '/^authelia_base_url=/{print $2}' "$CONFIG")
    if [ -n "$BASE_URL" ]; then
        HOST=$(echo "$BASE_URL" | sed -E 's#^https?://##; s#/.*##')
        getent hosts "$HOST" > /dev/null && ok "DNS resolves $HOST" || bad "DNS resolution failed for $HOST"
        HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/health" || echo "000")
        [ "$HTTP_CODE" = "200" ] && ok "Authelia health check 200 ($BASE_URL)" || bad "Authelia health check returned $HTTP_CODE ($BASE_URL)"
    fi
else
    info "no config.conf yet - network checks skipped (run again after configuring)"
fi

# --- disk space ----------------------------------------------------------
AVAIL_MB=$(df --output=avail -m /usr | tail -1 | tr -d ' ')
[ "$AVAIL_MB" -gt 100 ] && ok "sufficient free space on /usr (${AVAIL_MB}MB)" || bad "low free space on /usr (${AVAIL_MB}MB)"

echo
if [ "$FAIL" -eq 0 ]; then
    echo "PREFLIGHT_RESULT=GREEN"
else
    echo "PREFLIGHT_RESULT=RED - do not proceed with install.sh"
    exit 1
fi
