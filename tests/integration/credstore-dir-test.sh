#!/bin/bash
set -euo pipefail

[ "$(id -u)" -eq 0 ] || {
  echo "SKIP: requires root"
  exit 77
}

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

# shellcheck source=../../scripts/lib/credstore-dir.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib/credstore-dir.sh"

mode_is() {
  [ "$(stat -c '%a' "$2")" = "$1" ]
}

T="$ROOT/credstore"

harden_credstore_dir "$T"
mode_is 700 "$T"
[ "$(stat -c '%U:%G' "$T")" = "root:root" ]
rm -rf "$T"

install -d -o root -g root -m 0700 "$T"
harden_credstore_dir "$T"
mode_is 700 "$T"
rm -rf "$T"

install -d -o root -g root -m 0755 "$T"
harden_credstore_dir "$T"
mode_is 700 "$T"
rm -rf "$T"

install -d -o root -g root -m 0750 "$T"
harden_credstore_dir "$T"
mode_is 700 "$T"
rm -rf "$T"

install -d -o root -g root -m 0700 "$T"
chown 65534:65534 "$T"
! harden_credstore_dir "$T"
rm -rf "$T"

install -d -o root -g root -m 0700 "$ROOT/real"
ln -s "$ROOT/real" "$T"
! harden_credstore_dir "$T"
rm -f "$T"
rm -rf "$ROOT/real"

touch "$T"
! harden_credstore_dir "$T"
rm -f "$T"

echo "CREDSTORE_PERMISSION_REGRESSION=GREEN"
echo "CREDSTORE_NEVER_LOOSENED=GREEN"
