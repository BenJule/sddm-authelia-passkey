#!/bin/bash
# Integration tests for pam_authelia_passkey.so via pamtester, against an
# isolated test PAM service - never touches /etc/pam.d/sddm. Requires:
# pamtester, pam_authelia_passkey.so already installed to the system PAM
# module directory (see scripts/install.sh or run this against a build in
# /usr/lib/x86_64-linux-gnu/security/ manually for development).
#
# Run as root. Uses a real local test account name passed as $1 (must
# exist, UID >= 1000) so pam_get_user()/getpwnam_r() succeeds.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }
TESTUSER="${1:?usage: $0 <existing-local-username-uid-1000-plus>}"
TESTUID="$(id -u "$TESTUSER")"

MARKER_DIR=/run/sddm-authelia-passkey
SVC=/etc/pam.d/sddm-authelia-passkey-test
FAIL=0
ok()  { echo "[OK]   $*"; }
bad() { echo "[FAIL] $*"; FAIL=1; }

# v2 marker format: PAM requires VERSION=2 and a UID= line matching a
# fresh NSS lookup of the target account - see writeApprovalMarker in
# src/broker/main.go and consume_login_approval in src/pam/.
write_marker() {
    install -o root -g root -m 0600 /dev/null "$MARKER_DIR/approved-$TESTUSER"
    {
        echo "VERSION=2"
        echo "USERNAME=$TESTUSER"
        echo "UID=$TESTUID"
        echo "NONCE=test"
        echo "APPROVED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$MARKER_DIR/approved-$TESTUSER"
    chmod 0600 "$MARKER_DIR/approved-$TESTUSER"
}

mkdir -p "$MARKER_DIR"
rm -f "$MARKER_DIR/approved-$TESTUSER" "$MARKER_DIR/kwallet-ready-$TESTUSER"

cat > "$SVC" <<'EOF'
auth requisite pam_nologin.so
auth required pam_succeed_if.so user != root quiet_success
auth sufficient pam_authelia_passkey.so
auth requisite pam_deny.so
auth required pam_permit.so
EOF

echo "-- no marker --"
if pamtester sddm-authelia-passkey-test "$TESTUSER" authenticate < /dev/null 2>/dev/null; then
    bad "authenticated with no marker present"
else
    ok "correctly rejected with no marker"
fi

echo "-- valid marker --"
write_marker
if pamtester sddm-authelia-passkey-test "$TESTUSER" authenticate < /dev/null 2>/dev/null; then
    ok "correctly accepted with valid marker"
else
    bad "rejected a valid marker"
fi

echo "-- marker single-use (replay) --"
if pamtester sddm-authelia-passkey-test "$TESTUSER" authenticate < /dev/null 2>/dev/null; then
    bad "marker was reusable (should have been consumed)"
else
    ok "correctly rejected replayed marker"
fi

echo "-- expired marker (default TTL 30s) --"
write_marker
touch -d "60 seconds ago" "$MARKER_DIR/approved-$TESTUSER"
if pamtester sddm-authelia-passkey-test "$TESTUSER" authenticate < /dev/null 2>/dev/null; then
    bad "accepted an expired (60s, TTL 30s) marker"
else
    ok "correctly rejected expired marker"
fi

echo "-- marker for a different user does not grant this user --"
install -o root -g root -m 0600 /dev/null "$MARKER_DIR/approved-someoneelse"
if pamtester sddm-authelia-passkey-test "$TESTUSER" authenticate < /dev/null 2>/dev/null; then
    bad "authenticated $TESTUSER using someoneelse's marker"
else
    ok "correctly rejected mismatched-username marker"
fi
rm -f "$MARKER_DIR/approved-someoneelse"

echo "-- kwallet-secretd down + valid marker: login still succeeds --"
systemctl stop sddm-authelia-passkey-kwallet-secretd.service 2>/dev/null || true
write_marker
if pamtester sddm-authelia-passkey-test "$TESTUSER" authenticate < /dev/null 2>/dev/null; then
    ok "login succeeded even with kwallet-secretd unavailable (fail-open for login)"
else
    bad "login was affected by kwallet-secretd being down - this must never happen"
fi
systemctl start sddm-authelia-passkey-kwallet-secretd.service 2>/dev/null || true

echo "-- marker with wrong ownership (not root:root) is rejected --"
install -o "$TESTUSER" -g "$TESTUSER" -m 0600 /dev/null "$MARKER_DIR/approved-$TESTUSER"
if pamtester sddm-authelia-passkey-test "$TESTUSER" authenticate < /dev/null 2>/dev/null; then
    bad "authenticated using a marker not owned by root:root"
else
    ok "correctly rejected a marker not owned by root:root"
fi
rm -f "$MARKER_DIR/approved-$TESTUSER"

echo "-- marker with wrong permissions (world-readable) is rejected --"
install -o root -g root -m 0644 /dev/null "$MARKER_DIR/approved-$TESTUSER"
if pamtester sddm-authelia-passkey-test "$TESTUSER" authenticate < /dev/null 2>/dev/null; then
    bad "authenticated using a world-readable (0644) marker"
else
    ok "correctly rejected a marker with unexpected permissions"
fi
rm -f "$MARKER_DIR/approved-$TESTUSER"

rm -f "$SVC" "$MARKER_DIR/approved-$TESTUSER" "$MARKER_DIR/kwallet-ready-$TESTUSER"

echo
[ "$FAIL" -eq 0 ] && echo "PAM_FLOW_TESTS=GREEN" || { echo "PAM_FLOW_TESTS=RED"; exit 1; }
