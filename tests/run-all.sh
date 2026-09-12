#!/bin/bash
# Single entry point that runs this project's entire test corpus in one
# pass - the "test platform" a real admin/CI run can invoke instead of
# remembering each script individually (see docs/testing.md). Intended
# for a disposable lab VM or CI container, never production - several of
# these tests write to the real /etc/pam.d/sddm and /run/sddm-authelia-passkey.
#
# This does NOT replace a real distro/display-manager/desktop-environment
# matrix - see docs/validated-environment.md for the honest scope of what
# has actually been exercised (Debian 13 / SDDM / KDE Plasma 6 only).
#
# Usage: sudo tests/run-all.sh <local-test-user-1> <local-test-user-2>
# Both users must already exist (UID >= 1000).
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }
USER1="${1:?usage: $0 <local-test-user-1> <local-test-user-2>}"
USER2="${2:?usage: $0 <local-test-user-1> <local-test-user-2>}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
run() {
    local desc="$1"
    shift
    echo "=== $desc ==="
    if "$@"; then
        echo "--- PASS: $desc ---"
    else
        echo "--- FAIL: $desc ---"
        FAIL=1
    fi
    echo
}

run "broker unit tests"          bash -c "cd '$ROOT_DIR/src/broker' && go test ./..."
run "broker unit tests (-race)"  bash -c "cd '$ROOT_DIR/src/broker' && go test -race ./..."
run "kwallet-secretd unit tests" bash -c "cd '$ROOT_DIR/src/kwallet-secretd' && go test ./..."
run "credstore-dir-test"         bash "$ROOT_DIR/tests/integration/credstore-dir-test.sh"
run "pam-backup-test"            bash "$ROOT_DIR/tests/integration/pam-backup-test.sh"
run "pam-disable-structure-test" bash "$ROOT_DIR/tests/integration/pam-disable-structure-test.sh"
run "break-glass-test"           bash "$ROOT_DIR/tests/integration/break-glass-test.sh"
run "fido2-authfile-test"        bash "$ROOT_DIR/tests/integration/fido2-authfile-test.sh"
run "fido2-pam-integration-test" bash "$ROOT_DIR/tests/integration/fido2-pam-integration-test.sh"
run "theme-mode-test"            bash "$ROOT_DIR/tests/integration/theme-mode-test.sh"
run "theme-mode-command-test"    bash "$ROOT_DIR/tests/integration/theme-mode-command-test.sh"
run "theme-mode-check-target-test" bash "$ROOT_DIR/tests/integration/theme-mode-check-target-test.sh"
run "theme-migrate-test"         bash "$ROOT_DIR/tests/integration/theme-migrate-test.sh"
run "theme-migrate-command-test" bash "$ROOT_DIR/tests/integration/theme-migrate-command-test.sh"
run "validate-branding-overrides-test" bash "$ROOT_DIR/tests/integration/validate-branding-overrides-test.sh"
run "interface-freeze-test"        bash "$ROOT_DIR/tests/integration/interface-freeze-test.sh"
run "doctor-test"                bash "$ROOT_DIR/tests/integration/doctor-test.sh"
run "pam-flow-test"              bash "$ROOT_DIR/tests/integration/pam-flow-test.sh" "$USER1"
run "pam-multiuser-test"         bash "$ROOT_DIR/tests/integration/pam-multiuser-test.sh" "$USER1" "$USER2"

echo
if [ "$FAIL" -eq 0 ]; then
    echo "RUN_ALL_RESULT=GREEN"
else
    echo "RUN_ALL_RESULT=RED"
    exit 1
fi
