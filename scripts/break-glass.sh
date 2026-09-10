#!/bin/bash
# Emergency recovery: forces /etc/pam.d/sddm back to password-only login
# RIGHT NOW, without depending on locating any specific prior backup (see
# scripts/rollback.sh for the normal, backup-based full removal path -
# this script is the zero-dependency panic button for when that backup
# can't be found/trusted, or a calmer full rollback isn't wanted yet).
#
# Neutralizes (never deletes) every pam_authelia_passkey.so and
# pam_u2f.so auth line by prefixing it with a distinct
# "# BREAK-GLASS-DISABLED: " marker, so the exact same line can be
# restored later with --restore. Nothing else is touched: services,
# theme, config and credentials are left completely alone - this is
# intentionally the smallest possible blast radius, not a substitute for
# a full rollback.sh run once things have calmed down.
#
# Usage:
#   break-glass.sh            neutralize (idempotent - a no-op if already done)
#   break-glass.sh --restore  undo a prior break-glass.sh run
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }

ok()   { echo "[OK]   $*"; }
info() { echo "[INFO] $*"; }
bad()  { echo "[FAIL] $*" >&2; }

PAMFILE=/etc/pam.d/sddm
MODE="${1:-disable}"
[ "$MODE" = "--restore" ] && MODE="restore"
case "$MODE" in
    disable|restore) ;;
    *) bad "usage: $0 [--restore]"; exit 1 ;;
esac

[ -f "$PAMFILE" ] || { bad "$PAMFILE not found"; exit 1; }

MARKER="# BREAK-GLASS-DISABLED: "

if [ "$MODE" = "restore" ]; then
    if ! grep -qF "$MARKER" "$PAMFILE"; then
        info "no break-glass markers present, nothing to restore"
        echo "BREAK_GLASS_RESTORE=GREEN"
        exit 0
    fi

    BACKUP="/root/sddm-authelia-passkey-backup-$(date +%Y%m%d-%H%M%S)-break-glass-restore"
    mkdir -p "$BACKUP"
    cp -a "$PAMFILE" "$BACKUP/sddm.pam.orig"
    sha256sum /etc/pam.d/common-auth /etc/pam.d/sudo /etc/pam.d/sshd > "$BACKUP/common-auth-sudo-sshd.sha256" 2>/dev/null || true

    TMPFILE=$(mktemp)
    awk -v marker="$MARKER" '
        index($0, marker) == 1 { print substr($0, length(marker) + 1); next }
        { print }
    ' "$PAMFILE" > "$TMPFILE"

    if grep -qF "$MARKER" "$TMPFILE"; then
        bad "failed to fully restore break-glass-disabled lines - refusing to install a half-edited file"
        rm -f "$TMPFILE"
        exit 1
    fi

    install -o root -g root -m 0644 -T "$TMPFILE" "$PAMFILE"
    rm -f "$TMPFILE"

    sha256sum /etc/pam.d/common-auth /etc/pam.d/sudo /etc/pam.d/sshd > /tmp/sddm-authelia-passkey-break-glass-restore-post.sha256 2>/dev/null || true
    if ! diff -q "$BACKUP/common-auth-sudo-sshd.sha256" /tmp/sddm-authelia-passkey-break-glass-restore-post.sha256 >/dev/null 2>&1; then
        bad "SAFETY VIOLATION: common-auth/sudo/sshd PAM changed unexpectedly - rolling back."
        cp -a "$BACKUP/sddm.pam.orig" "$PAMFILE"
        exit 1
    fi
    rm -f /tmp/sddm-authelia-passkey-break-glass-restore-post.sha256

    ok "BREAK_GLASS_RESTORE=GREEN"
    echo "READY_FOR_SDDM_RESTART=YES (not done automatically)"
    exit 0
fi

if ! grep -qE 'pam_(authelia_passkey|u2f)\.so' "$PAMFILE"; then
    info "no pam_authelia_passkey.so/pam_u2f.so lines present, nothing to neutralize"
    echo "BREAK_GLASS_DISABLE=GREEN"
    exit 0
fi

# Idempotent: a line already carrying the marker is left untouched, never
# double-prefixed.
ALREADY_DONE=1
while IFS= read -r line; do
    case "$line" in
        "$MARKER"*) ;;
        *) ALREADY_DONE=0 ;;
    esac
done < <(grep -E 'pam_(authelia_passkey|u2f)\.so' "$PAMFILE")

if [ "$ALREADY_DONE" -eq 1 ]; then
    info "all pam_authelia_passkey.so/pam_u2f.so lines are already break-glass-disabled"
    echo "BREAK_GLASS_DISABLE=GREEN"
    exit 0
fi

BACKUP="/root/sddm-authelia-passkey-backup-$(date +%Y%m%d-%H%M%S)-break-glass"
mkdir -p "$BACKUP"
cp -a "$PAMFILE" "$BACKUP/sddm.pam.orig"
sha256sum /etc/pam.d/common-auth /etc/pam.d/sudo /etc/pam.d/sshd > "$BACKUP/common-auth-sudo-sshd.sha256" 2>/dev/null || true
info "backup: $BACKUP"

TMPFILE=$(mktemp)
awk -v marker="$MARKER" '
    /pam_(authelia_passkey|u2f)\.so/ && index($0, marker) != 1 { print marker $0; next }
    { print }
' "$PAMFILE" > "$TMPFILE"

install -o root -g root -m 0644 -T "$TMPFILE" "$PAMFILE"
rm -f "$TMPFILE"

sha256sum /etc/pam.d/common-auth /etc/pam.d/sudo /etc/pam.d/sshd > /tmp/sddm-authelia-passkey-break-glass-post.sha256 2>/dev/null || true
if ! diff -q "$BACKUP/common-auth-sudo-sshd.sha256" /tmp/sddm-authelia-passkey-break-glass-post.sha256 >/dev/null 2>&1; then
    bad "SAFETY VIOLATION: common-auth/sudo/sshd PAM changed unexpectedly - rolling back."
    cp -a "$BACKUP/sddm.pam.orig" "$PAMFILE"
    exit 1
fi
rm -f /tmp/sddm-authelia-passkey-break-glass-post.sha256

ok "BREAK_GLASS_DISABLE=GREEN (password-only login restored, nothing else touched)"
echo "RESTORE_WITH=$0 --restore"
echo "READY_FOR_SDDM_RESTART=YES (not done automatically - restart sddm yourself when ready)"
