#!/bin/bash
# Interactively registers a new FIDO2/U2F hardware security key (YubiKey,
# Nitrokey, SoloKey, or any other CTAP2/U2F-compliant authenticator) for
# one local account. Touch the key when it starts blinking. Supports
# multiple credentials per user - each run appends one more, never
# overwrites the user's existing ones. Never accepts key material as an
# argument; pamu2fcfg performs the actual registration ceremony against
# the physically-present device.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/fido2-authfile.sh
source "$SCRIPT_DIR/lib/fido2-authfile.sh"

[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }

USER_ARG="${1:-}"
[ -n "$USER_ARG" ] || { echo "usage: $0 <local-username>"; exit 1; }

PWLINE="$(getent passwd -- "$USER_ARG")" || { echo "no such local account: $USER_ARG"; exit 1; }
CANON_USER="$(cut -d: -f1 <<<"$PWLINE")"
[ "$CANON_USER" != "root" ] || { echo "refusing: root must never have a FIDO2 credential"; exit 1; }
[[ "$CANON_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo "refusing: unexpected username shape: $CANON_USER"; exit 1; }

command -v pamu2fcfg >/dev/null 2>&1 || { echo "pamu2fcfg not found - apt install libpam-u2f"; exit 1; }

AUTHFILE="$(fido2_resolve_authfile)"
install -d -m 0755 -o root -g root "$(dirname "$AUTHFILE")"
[ -f "$AUTHFILE" ] || install -o root -g root -m 0600 /dev/null "$AUTHFILE"

echo "Registering a new FIDO2/U2F key for: $CANON_USER"
echo "Touch/tap the security key now when it prompts (blinking LED, etc.)."
NEWCRED="$(pamu2fcfg -n -u "$CANON_USER" -V)" || { echo "registration failed or was cancelled"; exit 1; }
[ -n "$NEWCRED" ] || { echo "empty registration output, refusing"; exit 1; }

fido2_append_credential "$AUTHFILE" "$CANON_USER" "$NEWCRED"

echo "OK: credential added for $CANON_USER in $AUTHFILE"
echo "Takes effect on the next login attempt immediately - pam_u2f reads the file live, no service restart needed."
