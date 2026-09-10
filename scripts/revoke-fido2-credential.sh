#!/bin/bash
# Revokes ALL FIDO2/U2F credentials registered for one local account
# (removes their entire authfile line). There is no selective
# single-credential revocation in pam_u2f's authfile format without
# re-parsing/reconstructing the colon-separated groups by hand, which
# would risk corrupting another credential's data on a parsing mistake -
# revoke-all-then-re-enroll-the-ones-still-wanted is the safe path this
# project exposes. Never touches any other user's line.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/fido2-authfile.sh
source "$SCRIPT_DIR/lib/fido2-authfile.sh"

[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }

USER_ARG="${1:-}"
[ -n "$USER_ARG" ] || { echo "usage: $0 <local-username>"; exit 1; }

PWLINE="$(getent passwd -- "$USER_ARG")" || { echo "no such local account: $USER_ARG"; exit 1; }
CANON_USER="$(cut -d: -f1 <<<"$PWLINE")"

AUTHFILE="$(fido2_resolve_authfile)"
if [ ! -f "$AUTHFILE" ] || ! grep -q "^${CANON_USER}:" "$AUTHFILE"; then
    echo "no FIDO2 credentials registered for $CANON_USER, nothing to revoke"
    exit 0
fi

fido2_revoke_user "$AUTHFILE" "$CANON_USER"
echo "OK: all FIDO2 credentials revoked for $CANON_USER"
