#!/bin/bash
# doctor.sh regression: argument handling, read-only invariant, and
# output-shape checks that don't depend on a fully installed/running
# stack (this CI container has no systemd PID1, no broker, no SDDM -
# doctor.sh must degrade to well-formed RED/SKIP output, never crash,
# exactly like preflight.sh/postflight.sh already do in this same job).
set -euo pipefail

DOCTOR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/doctor.sh"
[ -x "$DOCTOR" ] || { echo "doctor.sh not found or not executable" >&2; exit 1; }

# --- read-only invariant: never mutates PAM/services/packages -----------
if grep -Eq '(^|[[:space:]])(systemctl[[:space:]]+(start|stop|restart|enable|disable)|apt-get|dpkg[[:space:]]+-i|rm[[:space:]]+-rf|>[[:space:]]*/etc/pam\.d)' "$DOCTOR"; then
    echo "doctor.sh must never mutate PAM/services/packages" >&2
    exit 1
fi
echo "DOCTOR_READ_ONLY=GREEN"

# --- invalid flag is rejected with usage, exit 2 -------------------------
set +e
OUT=$("$DOCTOR" --bogus 2>&1)
RC=$?
set -e
[ "$RC" -eq 2 ] || { echo "expected exit 2 for an invalid flag, got $RC" >&2; exit 1; }
printf '%s' "$OUT" | grep -q '^usage:' || { echo "expected a usage line for an invalid flag" >&2; exit 1; }
echo "DOCTOR_ARG_VALIDATION=GREEN"

# --- must run as root -----------------------------------------------------
if [ "$(id -u)" -eq 0 ] && command -v runuser >/dev/null 2>&1 && id nobody >/dev/null 2>&1; then
    set +e
    OUT=$(runuser -u nobody -- "$DOCTOR" 2>&1)
    RC=$?
    set -e
    [ "$RC" -ne 0 ] || { echo "doctor.sh must refuse to run as non-root" >&2; exit 1; }
    printf '%s' "$OUT" | grep -qi 'must run as root' || { echo "expected a root-required message" >&2; exit 1; }
    echo "DOCTOR_ROOT_REQUIRED=GREEN"
else
    echo "[INFO] skipping non-root refusal check (runuser/nobody unavailable in this environment)"
fi

[ "$(id -u)" -eq 0 ] || { echo "remaining checks require root" >&2; exit 1; }

# --- plain output: all 12 keys present, well-formed KEY=STATUS lines -----
EXPECTED_KEYS="SDDM PAM_CONFIG BROKER_CONFIG BROKER OIDC_DISCOVERY JWKS NSS SSSD IDENTITY_PROVENANCE USER_COLLISIONS BREAK_GLASS LOGIN_ENABLEMENT"

set +e
PLAIN_OUT=$("$DOCTOR" 2>&1)
set -e
for k in $EXPECTED_KEYS; do
    printf '%s\n' "$PLAIN_OUT" | grep -Eq "^${k}=(GREEN|RED|SKIP)\$" || {
        echo "missing or malformed line for $k in plain output:" >&2
        printf '%s\n' "$PLAIN_OUT" >&2
        exit 1
    }
done
echo "DOCTOR_PLAIN_OUTPUT=GREEN"

# --- --explain output: same keys, at least one reason line for a RED ------
set +e
EXPLAIN_OUT=$("$DOCTOR" --explain 2>&1)
set -e
for k in $EXPECTED_KEYS; do
    printf '%s\n' "$EXPLAIN_OUT" | grep -Eq "^${k}=(GREEN|RED|SKIP)\$" || {
        echo "missing or malformed line for $k in --explain output" >&2
        exit 1
    }
done
printf '%s\n' "$EXPLAIN_OUT" | grep -q '^  -> ' || { echo "expected at least one '  -> reason' line in --explain output (nothing is installed, so at least SDDM/BROKER should be RED)" >&2; exit 1; }
echo "DOCTOR_EXPLAIN_OUTPUT=GREEN"

# --- --json output: one object, all 12 keys, valid GREEN/RED/SKIP values --
set +e
JSON_OUT=$("$DOCTOR" --json 2>&1)
set -e
printf '%s' "$JSON_OUT" | grep -Eq '^\{.*\}$' || { echo "--json output is not a single JSON object: $JSON_OUT" >&2; exit 1; }
for k in $EXPECTED_KEYS; do
    printf '%s' "$JSON_OUT" | grep -Eq "\"${k}\":\"(GREEN|RED|SKIP)\"" || {
        echo "missing or malformed \"$k\" in --json output: $JSON_OUT" >&2
        exit 1
    }
done
echo "DOCTOR_JSON_OUTPUT=GREEN"

# --- exit code matches LOGIN_ENABLEMENT -----------------------------------
set +e
"$DOCTOR" --json >/dev/null 2>&1
DOCTOR_RC=$?
set -e
if printf '%s' "$JSON_OUT" | grep -q '"LOGIN_ENABLEMENT":"GREEN"'; then
    [ "$DOCTOR_RC" -eq 0 ] || { echo "expected exit 0 when LOGIN_ENABLEMENT=GREEN" >&2; exit 1; }
else
    [ "$DOCTOR_RC" -eq 1 ] || { echo "expected exit 1 when LOGIN_ENABLEMENT is not GREEN" >&2; exit 1; }
fi
echo "DOCTOR_EXIT_CODE=GREEN"

echo "DOCTOR_TEST=GREEN"
