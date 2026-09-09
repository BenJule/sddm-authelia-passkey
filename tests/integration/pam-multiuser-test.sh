#!/bin/bash
# Multi-user PAM integration tests: proves the core security invariant
# (alice's approval can never authenticate bob, and vice versa) against
# the real compiled pam_authelia_passkey.so via pamtester, using two
# real local test accounts. Never touches /etc/pam.d/sddm.
#
# Run as root on a lab host with two existing local test accounts, e.g.
# useradd -m alice && useradd -m bob (uid >= 1000 both):
#   sudo bash pam-multiuser-test.sh alice bob
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }
ALICE="${1:?usage: $0 <alice-username> <bob-username>}"
BOB="${2:?usage: $0 <alice-username> <bob-username>}"

ALICE_UID="$(id -u "$ALICE")"
BOB_UID="$(id -u "$BOB")"

MARKER_DIR=/run/sddm-authelia-passkey
SVC=/etc/pam.d/sddm-authelia-passkey-test
FAIL=0
ok()  { echo "[OK]   $*"; }
bad() { echo "[FAIL] $*"; FAIL=1; }

mkdir -p "$MARKER_DIR"
rm -f "$MARKER_DIR/approved-$ALICE" "$MARKER_DIR/approved-$BOB"

cat > "$SVC" <<'EOF'
auth requisite pam_nologin.so
auth required pam_succeed_if.so user != root quiet_success
auth sufficient pam_authelia_passkey.so
auth requisite pam_deny.so
auth required pam_permit.so
EOF

write_marker() {
    local user="$1" uid="$2"
    install -o root -g root -m 0600 /dev/null "$MARKER_DIR/approved-$user"
    {
        echo "VERSION=2"
        echo "USERNAME=$user"
        echo "UID=$uid"
        echo "NONCE=test"
        echo "APPROVED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$MARKER_DIR/approved-$user"
    chmod 0600 "$MARKER_DIR/approved-$user"
}

echo "-- alice marker -> PAM alice: must succeed --"
write_marker "$ALICE" "$ALICE_UID"
if pamtester sddm-authelia-passkey-test "$ALICE" authenticate < /dev/null 2>/dev/null; then
    ok "alice's own approval authenticated alice"
else
    bad "alice's own approval was rejected for alice"
fi
rm -f "$MARKER_DIR/approved-$ALICE"

echo "-- alice marker -> PAM bob: must be rejected --"
write_marker "$ALICE" "$ALICE_UID"
if pamtester sddm-authelia-passkey-test "$BOB" authenticate < /dev/null 2>/dev/null; then
    bad "SECURITY: bob was authenticated using alice's approval marker"
else
    ok "bob correctly rejected alice's approval marker"
fi
rm -f "$MARKER_DIR/approved-$ALICE"

echo "-- bob marker -> PAM alice: must be rejected --"
write_marker "$BOB" "$BOB_UID"
if pamtester sddm-authelia-passkey-test "$ALICE" authenticate < /dev/null 2>/dev/null; then
    bad "SECURITY: alice was authenticated using bob's approval marker"
else
    ok "alice correctly rejected bob's approval marker"
fi
rm -f "$MARKER_DIR/approved-$BOB"

echo "-- alice marker with wrong (bob's) UID embedded -> PAM alice: must be rejected --"
write_marker "$ALICE" "$BOB_UID"
if pamtester sddm-authelia-passkey-test "$ALICE" authenticate < /dev/null 2>/dev/null; then
    bad "SECURITY: alice authenticated despite marker's UID not matching alice's real UID"
else
    ok "UID/username mismatch inside a marker correctly rejected"
fi
rm -f "$MARKER_DIR/approved-$ALICE"

echo "-- v1-style marker (no UID= field) -> must be rejected (fail closed) --"
install -o root -g root -m 0600 /dev/null "$MARKER_DIR/approved-$ALICE"
if pamtester sddm-authelia-passkey-test "$ALICE" authenticate < /dev/null 2>/dev/null; then
    bad "a marker with no VERSION=2/UID= binding was accepted"
else
    ok "marker without UID binding correctly rejected"
fi
rm -f "$MARKER_DIR/approved-$ALICE"

echo "-- parallel: alice and bob markers coexist, each only authenticates its own user --"
write_marker "$ALICE" "$ALICE_UID"
write_marker "$BOB" "$BOB_UID"
A_OK=0; B_OK=0
pamtester sddm-authelia-passkey-test "$ALICE" authenticate < /dev/null 2>/dev/null && A_OK=1
pamtester sddm-authelia-passkey-test "$BOB" authenticate < /dev/null 2>/dev/null && B_OK=1
if [ "$A_OK" = 1 ] && [ "$B_OK" = 1 ]; then
    ok "parallel alice+bob markers both independently authenticated their own user"
else
    bad "parallel alice/bob markers did not both succeed independently (alice=$A_OK bob=$B_OK)"
fi
rm -f "$MARKER_DIR/approved-$ALICE" "$MARKER_DIR/approved-$BOB"

rm -f "$SVC"
echo
[ "$FAIL" -eq 0 ] && echo "PAM_MULTIUSER_TESTS=GREEN" || { echo "PAM_MULTIUSER_TESTS=RED"; exit 1; }
