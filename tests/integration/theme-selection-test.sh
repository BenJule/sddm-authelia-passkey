#!/bin/bash
set -euo pipefail

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

# shellcheck source=../../scripts/lib/theme-selection.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib/theme-selection.sh"

F="$ROOT/sddm.conf"
cat > "$F" <<'CFG'
[General]
DisplayServer=wayland

[Theme]
CursorTheme=breeze_cursors
Current=debian-breeze-authelia-passkey

[X11]
ServerArguments=-nolisten tcp
CFG

chmod 0640 "$F"
before_general="$(grep -A1 '^\[General\]' "$F")"
before_x11="$(grep -A1 '^\[X11\]' "$F")"

replace_sddm_theme_current "$F" debian-breeze-authelia-passkey debian-breeze

grep -q '^Current=debian-breeze$' "$F"
test "$(stat -c '%a' "$F")" = "640"
test "$before_general" = "$(grep -A1 '^\[General\]' "$F")"
test "$before_x11" = "$(grep -A1 '^\[X11\]' "$F")"
test "$(grep -c '^Current=' "$F")" -eq 1

echo "THEME_SELECTION_PRESERVATION=GREEN"
