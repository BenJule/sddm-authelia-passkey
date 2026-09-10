#!/bin/bash
# Lists which local accounts have FIDO2/U2F credentials enrolled, and how
# many each - never prints the raw key handles/public keys.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/fido2-authfile.sh
source "$SCRIPT_DIR/lib/fido2-authfile.sh"

[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }

AUTHFILE="$(fido2_resolve_authfile)"
if [ ! -f "$AUTHFILE" ]; then
    echo "no authfile at $AUTHFILE - no credentials enrolled yet"
    exit 0
fi
fido2_list_credentials "$AUTHFILE"
