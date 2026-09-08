#!/bin/bash
# Normal, deliberate removal (as opposed to rollback.sh's emergency-
# restore framing - functionally similar, but also offers to remove the
# configuration directory, which rollback.sh leaves in place on purpose).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/rollback.sh" "${1:-}"

read -rp "Also remove /etc/sddm-authelia-passkey/ (config)? [y/N] " REMOVE_CONFIG
if [[ "$REMOVE_CONFIG" =~ ^[Yy]$ ]]; then
    rm -rf /etc/sddm-authelia-passkey
    echo "config removed"
fi

echo "UNINSTALL=DONE"
