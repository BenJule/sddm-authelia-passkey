#!/bin/bash
# Structural regression test for scripts/disable-pam.sh, matching the
# same style as fido2-pam-integration-test.sh: this script operates on
# the real absolute /etc/pam.d/sddm path, so full dynamic execution
# (enable-pam.sh -> disable-pam.sh round-trip producing a byte-identical
# file) is exercised for real on VM124 (docs/validated-environment.md)
# rather than against a redirected fake path here.
set -euo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/disable-pam.sh"
E="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/enable-pam.sh"

# Must be idempotent (checks for its own marker before editing).
grep -q "has no pam_authelia_passkey.so line, nothing to do" "$D"

# Must refuse if FIDO2 is still layered on top, rather than guessing at a
# now-misaligned removal.
grep -q "pam_u2f.so (FIDO2) is still integrated" "$D"
grep -q "run scripts/disable-fido2.sh first" "$D"

# Must remove exactly the 4 lines enable-pam.sh inserts after the
# pam_succeed_if.so anchor (blank + 2 comments + the auth line) - the
# same anchor regex enable-pam.sh matches on insertion.
grep -q 'pam_succeed_if\\.so\[ \\t\]+user\[ \\t\]\*!=\[ \\t\]\*root\[ \\t\]+quiet_success' "$E"
grep -q 'pam_succeed_if\\.so\[ \\t\]+user\[ \\t\]\*!=\[ \\t\]\*root\[ \\t\]+quiet_success' "$D"
grep -q 'skip = 4' "$D"

# Must verify complete removal before installing the edited file, and
# must carry the same fail-closed safety net as every other PAM-editing
# script in this project.
grep -q 'failed to fully remove pam_authelia_passkey.so line' "$D"
grep -q 'SAFETY VIOLATION: common-auth/sudo/sshd PAM changed unexpectedly' "$D"

echo "PAM_DISABLE_STRUCTURE=GREEN"
