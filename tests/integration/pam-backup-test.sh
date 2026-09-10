#!/bin/bash
set -euo pipefail
E="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/enable-pam.sh"
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/rollback.sh"
A="$(grep -n 'Idempotent re-runs must not create' "$E"|cut -d: -f1)"
B="$(grep -n '^BACKUP=' "$E"|head -1|cut -d: -f1)"
test -n "$A" -a -n "$B" -a "$A" -lt "$B"
grep -q "find /root -maxdepth 1 -mindepth 1 -type d -name" "$R"
grep -q 'refusing already-integrated PAM backup' "$R"
echo PAM_BACKUP_REGRESSION=GREEN
