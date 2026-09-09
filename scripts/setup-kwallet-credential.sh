#!/bin/bash
# Interactively creates (or replaces) the per-user KWallet auto-unlock
# credential for one local account. Never accepts the secret as an
# argument (would leak into argv/process listing/shell history) - always
# reads it interactively, without echo. Run as: sudo bash
# setup-kwallet-credential.sh <username>
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }

USER_ARG="${1:-}"
[ -n "$USER_ARG" ] || { echo "usage: $0 <local-username>"; exit 1; }

# Canonicalize via NSS - refuse anything getent doesn't resolve to a real
# account, and never build a filesystem path from the raw argv string.
PWLINE="$(getent passwd -- "$USER_ARG")" || { echo "no such local account: $USER_ARG"; exit 1; }
CANON_USER="$(cut -d: -f1 <<<"$PWLINE")"
UID_NUM="$(cut -d: -f3 <<<"$PWLINE")"

[ "$CANON_USER" != "root" ] || { echo "refusing: root must never have a smartphone/KWallet credential"; exit 1; }
[[ "$CANON_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo "refusing: unexpected username shape: $CANON_USER"; exit 1; }

CREDSTORE=/etc/credstore.encrypted
DEST="$CREDSTORE/kwallet.secret.$CANON_USER"

install -d -m 0755 "$CREDSTORE"

echo "Creating KWallet auto-unlock credential for: $CANON_USER (uid $UID_NUM)"
echo "This should be that user's real KWallet password (usually the same"
echo "as their login password, unless they changed KWallet's password"
echo "separately)."
read -r -s -p "KWallet password for $CANON_USER: " SECRET
echo
[ -n "$SECRET" ] || { echo "empty secret refused"; exit 1; }

TMP="$(mktemp "$CREDSTORE/.kwallet.secret.$CANON_USER.XXXXXX")"
trap 'rm -f "$TMP"; unset SECRET' EXIT
printf '%s' "$SECRET" | systemd-creds encrypt --with-key=host --name="kwallet.secret.$CANON_USER" - "$TMP"
unset SECRET

install -o root -g root -m 0600 -T "$TMP" "$DEST"
rm -f "$TMP"

echo "OK: $DEST"
echo "Restart the daemon to pick it up: systemctl restart sddm-authelia-passkey-kwallet-secretd.service"
