#!/bin/bash
# sddm-authelia-passkey installer.
#
# Installs the broker, PAM module, systemd units, and (if requested) the
# theme integration. Never restarts SDDM. Never touches common-auth, sudo
# PAM, or sshd PAM. Refuses to patch /etc/pam.d/sddm if the installed
# SDDM's PAM stack does not match a supported, exactly-verified shape -
# see docs/installation.md "Supported platforms".
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ok()   { echo "[OK]   $*"; }
bad()  { echo "[FAIL] $*" >&2; }
info() { echo "[INFO] $*"; }

[ "$(id -u)" -eq 0 ] || { bad "must run as root"; exit 1; }

# --- Preflight -----------------------------------------------------------
FAIL=0
command -v sddm >/dev/null 2>&1 || { bad "sddm not found"; FAIL=1; }
[ -f /etc/pam.d/sddm ] || { bad "/etc/pam.d/sddm not found"; FAIL=1; }
command -v systemctl >/dev/null 2>&1 || { bad "systemd not found"; FAIL=1; }
[ -d /usr/lib/x86_64-linux-gnu/security ] || [ -d /lib/x86_64-linux-gnu/security ] || \
    { bad "expected PAM module directory not found (only x86_64 supported currently)"; FAIL=1; }
ldconfig -p 2>/dev/null | grep -q libpam.so || { bad "libpam0g not found"; FAIL=1; }
[ "$FAIL" -eq 0 ] || { bad "preflight failed, aborting"; exit 1; }
ok "preflight checks passed"

PAM_MODULE_DIR=/usr/lib/x86_64-linux-gnu/security
[ -d "$PAM_MODULE_DIR" ] || PAM_MODULE_DIR=/lib/x86_64-linux-gnu/security

# --- Config ---------------------------------------------------------------
CONFIG_DIR=/etc/sddm-authelia-passkey
if [ ! -f "$CONFIG_DIR/config.conf" ]; then
    install -d -m 0755 "$CONFIG_DIR"
    install -o root -g root -m 0644 "$PROJECT_ROOT/config/examples/config.conf.example" "$CONFIG_DIR/config.conf"
    info "installed example config to $CONFIG_DIR/config.conf - EDIT IT before enabling the PAM integration (see docs/configuration.md)"
else
    info "existing config at $CONFIG_DIR/config.conf left untouched"
fi

# --- Backup -----------------------------------------------------------
BACKUP="/root/sddm-authelia-passkey-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
cp -a /etc/pam.d/sddm "$BACKUP/sddm.pam.orig"
sha256sum /etc/pam.d/sddm > "$BACKUP/sddm.pam.orig.sha256"
sha256sum /etc/pam.d/common-auth /etc/pam.d/sudo /etc/pam.d/sshd > "$BACKUP/common-auth-sudo-sshd.sha256" 2>/dev/null || true
info "backup: $BACKUP"

# --- Install broker + PAM module + systemd units -----------------------
install -d -m 0755 /usr/lib/sddm-authelia-passkey
install -o root -g root -m 0755 "$PROJECT_ROOT/src/broker/broker" /usr/lib/sddm-authelia-passkey/broker
install -o root -g root -m 0644 "$PROJECT_ROOT/src/pam/pam_authelia_passkey.so" "$PAM_MODULE_DIR/pam_authelia_passkey.so"
install -o root -g root -m 0644 "$PROJECT_ROOT/systemd/sddm-authelia-passkey-broker.service" /etc/systemd/system/sddm-authelia-passkey-broker.service

read -rp "Enable optional KWallet auto-unlock component? [y/N] " ENABLE_KWALLET
if [[ "$ENABLE_KWALLET" =~ ^[Yy]$ ]]; then
    install -o root -g root -m 0755 "$PROJECT_ROOT/src/kwallet-secretd/kwallet-secretd" /usr/lib/sddm-authelia-passkey/kwallet-secretd
    install -o root -g root -m 0644 "$PROJECT_ROOT/systemd/sddm-authelia-passkey-kwallet-secretd.service" /etc/systemd/system/sddm-authelia-passkey-kwallet-secretd.service
    install -d -m 0755 /etc/credstore.encrypted
    info "KWallet component installed but NOT enabled - see docs/kwallet.md for the interactive credential setup, then set kwallet_auto_unlock=true in config.conf"
fi

systemctl daemon-reload
ok "broker/PAM module/units installed"

# --- PAM stack detection + integration (Phase 9/14: refuse rather than
# guess; extracted to enable-pam.sh so it also works standalone after
# installing the .deb package, which does not touch PAM automatically) --
"$SCRIPT_DIR/enable-pam.sh" || {
    echo "INSTALL=PARTIAL (broker/module installed, PAM not integrated - see above)"
    exit 0
}

echo
echo "INSTALL=GREEN"
echo "NEXT: edit $CONFIG_DIR/config.conf, then: systemctl enable --now sddm-authelia-passkey-broker.service"
