#!/bin/bash
# Direct functional test for break-glass.sh's core transform: unlike the
# PAM-editing scripts (which hardcode the real absolute /etc/pam.d/sddm
# path and are proven for real on VM124 - see
# docs/validated-environment.md), this test exercises the exact same awk
# programs break-glass.sh uses, against a synthetic fixture, so the
# disable/restore round trip is proven byte-identical here in CI without
# touching any real PAM file.
set -euo pipefail
MARKER="# BREAK-GLASS-DISABLED: "

FIXTURE=$(mktemp)
trap 'rm -f "$FIXTURE" "$DISABLED" "$RESTORED"' EXIT
cat > "$FIXTURE" <<'EOF'
auth    requisite       pam_nologin.so
auth    required        pam_succeed_if.so user != root quiet_success

# Authelia Passkey passwordless path + optional KWallet auto-unlock.
auth    [success=3 default=ignore]      pam_u2f.so authfile=/etc/x cue
auth    [success=3 default=ignore]      pam_authelia_passkey.so
@include common-auth
EOF

DISABLED=$(mktemp)
awk -v marker="$MARKER" '
    /pam_(authelia_passkey|u2f)\.so/ && index($0, marker) != 1 { print marker $0; next }
    { print }
' "$FIXTURE" > "$DISABLED"

grep -q "^${MARKER}auth    \[success=3 default=ignore\]      pam_u2f.so authfile=/etc/x cue$" "$DISABLED"
grep -q "^${MARKER}auth    \[success=3 default=ignore\]      pam_authelia_passkey.so$" "$DISABLED"
grep -q '^@include common-auth$' "$DISABLED"

# Idempotent: running the same transform again on already-disabled lines
# must never double-prefix them.
DISABLED_TWICE=$(mktemp)
awk -v marker="$MARKER" '
    /pam_(authelia_passkey|u2f)\.so/ && index($0, marker) != 1 { print marker $0; next }
    { print }
' "$DISABLED" > "$DISABLED_TWICE"
diff -q "$DISABLED" "$DISABLED_TWICE" >/dev/null

RESTORED=$(mktemp)
awk -v marker="$MARKER" '
    index($0, marker) == 1 { print substr($0, length(marker) + 1); next }
    { print }
' "$DISABLED" > "$RESTORED"

diff -q "$FIXTURE" "$RESTORED" >/dev/null

rm -f "$DISABLED_TWICE"
echo "BREAK_GLASS_TRANSFORM=GREEN"
