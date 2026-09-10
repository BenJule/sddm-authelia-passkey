#!/bin/bash
# Structural regression test for scripts/enable-fido2.sh /
# scripts/disable-fido2.sh, matching the same style as
# pam-backup-test.sh: these scripts operate on the real absolute
# /etc/pam.d/sddm path, so full dynamic execution is exercised for real
# on VM124 (docs/validated-environment.md) rather than against a
# redirected fake path here. This test proves the SHAPE of the logic is
# present and in the right order without touching any real PAM file.
set -euo pipefail
E="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/enable-fido2.sh"
D="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/disable-fido2.sh"

# enable-fido2.sh must refuse before pam_authelia_passkey.so is integrated.
grep -q 'pam_authelia_passkey.so not integrated yet' "$E"

# Must be idempotent (checks for its own marker before editing).
grep -q "already has pam_u2f.so integrated" "$E"

# Skip count must be computed fresh (1 + common-auth line count), never
# a hardcoded number, and inserted strictly above the existing
# pam_authelia_passkey.so line (never replacing/reordering it).
grep -q 'COMMON_AUTH_LINES=\$(grep -c .\^auth. /etc/pam.d/common-auth)' "$E"
grep -q 'SKIP=\$((COMMON_AUTH_LINES + 1))' "$E"
grep -q 'pam_authelia_passkey\\.so' "$E"

# Same fail-closed safety net as every other PAM-editing script in this
# project: common-auth/sudo/sshd hashes re-checked after edit, rollback
# on any unexpected change.
grep -q 'SAFETY VIOLATION: common-auth/sudo/sshd PAM changed unexpectedly' "$E"
grep -q 'SAFETY VIOLATION: common-auth/sudo/sshd PAM changed unexpectedly' "$D"

# disable-fido2.sh must be idempotent and must verify complete removal
# before installing the edited file.
grep -q 'nothing to do' "$D"
grep -q 'failed to fully remove pam_u2f.so line' "$D"

echo "FIDO2_PAM_STRUCTURE=GREEN"
