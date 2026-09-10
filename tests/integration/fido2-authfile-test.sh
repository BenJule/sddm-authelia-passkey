#!/bin/bash
# Proves the FIDO2/U2F authfile manipulation logic (scripts/lib/fido2-
# authfile.sh) directly - append/revoke/list and, critically, that one
# user's credentials can never leak into or be affected by another
# user's entry (the same cross-user isolation invariant enforced
# everywhere else in this project).
set -euo pipefail

[ "$(id -u)" -eq 0 ] || {
  echo "SKIP: requires root"
  exit 77
}

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

# shellcheck source=../../scripts/lib/fido2-authfile.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib/fido2-authfile.sh"

AUTHFILE="$ROOT/fido2_mappings"

# First credential for alice creates a new line.
fido2_append_credential "$AUTHFILE" "alice" "kh-a1,pk-a1,es256,+presence"
[ "$(cat "$AUTHFILE")" = "alice:kh-a1,pk-a1,es256,+presence" ]
[ "$(stat -c '%a' "$AUTHFILE")" = "600" ]

# A second credential for alice appends to her SAME line, not a new one.
fido2_append_credential "$AUTHFILE" "alice" "kh-a2,pk-a2,es256,+presence"
[ "$(wc -l < "$AUTHFILE")" -eq 1 ]
[ "$(cat "$AUTHFILE")" = "alice:kh-a1,pk-a1,es256,+presence:kh-a2,pk-a2,es256,+presence" ]

# bob's own enrollment must never touch alice's line.
fido2_append_credential "$AUTHFILE" "bob" "kh-b1,pk-b1,es256,+presence"
[ "$(wc -l < "$AUTHFILE")" -eq 2 ]
grep -q '^alice:kh-a1,pk-a1,es256,+presence:kh-a2,pk-a2,es256,+presence$' "$AUTHFILE"
grep -q '^bob:kh-b1,pk-b1,es256,+presence$' "$AUTHFILE"

# list reports the right credential counts per user, no raw key material
# beyond what's already there (nothing added/removed by listing).
LIST_OUT="$(fido2_list_credentials "$AUTHFILE")"
grep -q '^alice: 2 credential(s)$' <<<"$LIST_OUT"
grep -q '^bob: 1 credential(s)$' <<<"$LIST_OUT"

# Revoking bob must never affect alice's line/credentials.
fido2_revoke_user "$AUTHFILE" "bob"
[ "$(wc -l < "$AUTHFILE")" -eq 1 ]
grep -q '^alice:kh-a1,pk-a1,es256,+presence:kh-a2,pk-a2,es256,+presence$' "$AUTHFILE"
! grep -q '^bob:' "$AUTHFILE"

# Revoking a user with no entry is a safe no-op (lib callers check this;
# here we exercise the underlying function directly).
fido2_revoke_user "$AUTHFILE" "mallory"
[ "$(wc -l < "$AUTHFILE")" -eq 1 ]

echo "FIDO2_AUTHFILE_APPEND=GREEN"
echo "FIDO2_AUTHFILE_MULTI_CREDENTIAL=GREEN"
echo "FIDO2_AUTHFILE_CROSS_USER_ISOLATION=GREEN"
echo "FIDO2_AUTHFILE_REVOKE=GREEN"
echo "FIDO2_AUTHFILE_LIST=GREEN"
