#!/bin/bash
# READ-ONLY comprehensive diagnostic ("doctor") for sddm-authelia-passkey.
# Aggregates and extends the checks preflight.sh/postflight.sh already do
# piecemeal, adding OIDC discovery/JWKS reachability, NSS/SSSD state,
# identity-provenance config consistency, and a systematic local/directory
# username collision scan - the production activation gate v2.3.0's
# roadmap calls for. Never writes anything, never restarts/enables/
# disables any service, never touches PAM. Run as: sudo bash doctor.sh
#
# Usage:
#   doctor.sh            [KEY]=[GREEN|RED|SKIP] lines
#   doctor.sh --explain   same, plus a one-line reason under any non-GREEN
#   doctor.sh --json      single-line {"KEY":"STATUS",...} object instead
#
# Exit code reflects LOGIN_ENABLEMENT only (0=GREEN, 1=RED) - the single
# aggregate answer to "would it be safe to enable the passwordless login
# path right now".
set -uo pipefail

MODE=plain
case "${1:-}" in
    --explain) MODE=explain ;;
    --json) MODE=json ;;
    "") ;;
    *) echo "usage: $0 [--explain|--json]" >&2; exit 2 ;;
esac

[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }

CONFIG=/etc/sddm-authelia-passkey/config.conf
BROKER_BIN=/usr/lib/sddm-authelia-passkey/broker
PAMFILE=/etc/pam.d/sddm

declare -A RESULT
declare -A REASON

set_result() {
    RESULT["$1"]="$2"
    REASON["$1"]="${3:-}"
}

# --- SDDM -----------------------------------------------------------------
if systemctl is-active --quiet sddm; then
    DM_TARGET=$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)
    if [ "$(basename "${DM_TARGET:-}")" = "sddm.service" ]; then
        set_result SDDM GREEN
    else
        set_result SDDM RED "display-manager.service does not point to sddm.service"
    fi
else
    set_result SDDM RED "sddm.service is not active"
fi

# --- PAM_CONFIG -------------------------------------------------------------
if [ -f "$PAMFILE" ]; then
    if grep -q 'pam_authelia_passkey.so' "$PAMFILE"; then
        set_result PAM_CONFIG GREEN
    else
        set_result PAM_CONFIG SKIP "PAM not yet integrated (run enable-pam.sh) - password-only login is unaffected"
    fi
else
    set_result PAM_CONFIG RED "$PAMFILE not found"
fi

# --- BROKER_CONFIG (delegates to the broker's own --check-config) ---------
if [ -x "$BROKER_BIN" ]; then
    if CHECK_OUT=$("$BROKER_BIN" --check-config 2>&1); then
        set_result BROKER_CONFIG GREEN
    else
        set_result BROKER_CONFIG RED "$CHECK_OUT"
    fi
else
    set_result BROKER_CONFIG RED "$BROKER_BIN not installed"
fi

# --- BROKER: is it actually running and responsive -------------------------
if systemctl is-active --quiet sddm-authelia-passkey-broker; then
    HTTP_CODE=$(curl -s -o /dev/null --max-time 5 -w '%{http_code}' -X POST 'http://127.0.0.1:7899/start?username=nobody-not-allowlisted' 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "403" ]; then
        set_result BROKER GREEN
    else
        set_result BROKER RED "broker did not return 403 for a non-allowlisted user (got $HTTP_CODE)"
    fi
else
    set_result BROKER RED "sddm-authelia-passkey-broker.service is not active"
fi

# --- config-derived fields (only if config exists) --------------------------
ACCOUNT_SOURCE=local
PROVIDER_KIND=authelia
REJECT_SHADOW=""
REQUIRED_SOURCE=""
if [ -f "$CONFIG" ]; then
    ACCOUNT_SOURCE=$(awk -F= '/^account_source=/{print $2; exit}' "$CONFIG")
    ACCOUNT_SOURCE="${ACCOUNT_SOURCE:-local}"
    PROVIDER_KIND=$(awk -F= '/^provider_kind=/{print $2; exit}' "$CONFIG")
    PROVIDER_KIND="${PROVIDER_KIND:-authelia}"
    REJECT_SHADOW=$(awk -F= '/^reject_local_shadowing=/{print $2; exit}' "$CONFIG")
    REQUIRED_SOURCE=$(awk -F= '/^required_identity_source=/{print $2; exit}' "$CONFIG")
fi

# --- OIDC_DISCOVERY ----------------------------------------------------------
if [ ! -f "$CONFIG" ]; then
    set_result OIDC_DISCOVERY SKIP "no config.conf yet"
elif [ "$PROVIDER_KIND" = "oidc" ]; then
    DISCOVERY_URL=$(awk -F= '/^oidc_discovery_url=/{print $2; exit}' "$CONFIG")
    if [ -z "$DISCOVERY_URL" ]; then
        set_result OIDC_DISCOVERY RED "provider_kind=oidc but oidc_discovery_url is not set"
    else
        DOC=$(curl -s --max-time 5 "$DISCOVERY_URL" 2>/dev/null || true)
        if printf '%s' "$DOC" | grep -q '"device_authorization_endpoint"'; then
            set_result OIDC_DISCOVERY GREEN
        else
            set_result OIDC_DISCOVERY RED "discovery document at $DISCOVERY_URL did not advertise device_authorization_endpoint (or was unreachable)"
        fi
    fi
else
    BASE_URL=$(awk -F= '/^authelia_base_url=/{print $2; exit}' "$CONFIG")
    if [ -z "$BASE_URL" ]; then
        set_result OIDC_DISCOVERY RED "authelia_base_url is not set"
    else
        HTTP_CODE=$(curl -s -o /dev/null --max-time 5 -w '%{http_code}' "$BASE_URL/api/health" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ]; then
            set_result OIDC_DISCOVERY GREEN
        else
            set_result OIDC_DISCOVERY RED "Authelia health check at $BASE_URL returned $HTTP_CODE"
        fi
    fi
fi

# --- JWKS (only meaningful for provider_kind=oidc) ---------------------------
if [ ! -f "$CONFIG" ] || [ "$PROVIDER_KIND" != "oidc" ]; then
    set_result JWKS SKIP "only checked for provider_kind=oidc"
else
    DISCOVERY_URL=$(awk -F= '/^oidc_discovery_url=/{print $2; exit}' "$CONFIG")
    if [ -z "$DISCOVERY_URL" ]; then
        set_result JWKS RED "cannot check jwks_uri without oidc_discovery_url"
    else
        DOC=$(curl -s --max-time 5 "$DISCOVERY_URL" 2>/dev/null || true)
        JWKS_URI=$(printf '%s' "$DOC" | grep -o '"jwks_uri"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*"(https?:[^"]*)"/\1/')
        if [ -z "$JWKS_URI" ]; then
            set_result JWKS RED "discovery document did not advertise jwks_uri (or was unreachable)"
        else
            JWKS_DOC=$(curl -s --max-time 5 "$JWKS_URI" 2>/dev/null || true)
            if printf '%s' "$JWKS_DOC" | grep -q '"keys"'; then
                set_result JWKS GREEN
            else
                set_result JWKS RED "jwks_uri ($JWKS_URI) did not return a keys array (or was unreachable)"
            fi
        fi
    fi
fi

# --- NSS / SSSD (only meaningful for account_source=nss) ---------------------
if [ "$ACCOUNT_SOURCE" != "nss" ]; then
    set_result NSS SKIP "account_source=local, NSS is not consulted for authorization"
    set_result SSSD SKIP "account_source=local, SSSD is not consulted for authorization"
else
    if getent passwd root >/dev/null 2>&1; then
        set_result NSS GREEN
    else
        set_result NSS RED "basic NSS passwd lookup failed"
    fi
    if systemctl is-active --quiet sssd 2>/dev/null; then
        set_result SSSD GREEN
    elif [ "$REQUIRED_SOURCE" = "sssd" ] || [ "$REJECT_SHADOW" = "true" ]; then
        set_result SSSD RED "sssd.service is not active, but required_identity_source/reject_local_shadowing depends on the sss NSS service actually being backed by it"
    else
        set_result SSSD SKIP "sssd.service is not active (only a hard requirement when required_identity_source=sssd or reject_local_shadowing=true)"
    fi
fi

# --- IDENTITY_PROVENANCE ------------------------------------------------------
if [ "$ACCOUNT_SOURCE" != "nss" ]; then
    set_result IDENTITY_PROVENANCE SKIP "only meaningful for account_source=nss"
elif [ "${RESULT[BROKER_CONFIG]}" != "GREEN" ]; then
    set_result IDENTITY_PROVENANCE RED "config did not validate - see BROKER_CONFIG"
else
    set_result IDENTITY_PROVENANCE GREEN
fi

# --- USER_COLLISIONS: systematic files-vs-sss UID-disagreement scan ----------
# Proactively finds the exact real-world class of gap docs/identity-binding.md
# documents, on any host - not just the one already-known VM124 case.
if [ "$ACCOUNT_SOURCE" != "nss" ] || [ "${RESULT[SSSD]}" != "GREEN" ]; then
    set_result USER_COLLISIONS SKIP "only scanned when account_source=nss and sssd is active"
else
    COLLISIONS=""
    while IFS=: read -r name _ uid _; do
        case "$uid" in ''|*[!0-9]*) continue ;; esac
        [ "$uid" -ge 1000 ] || continue
        SSS_LINE=$(getent -s sss passwd "$name" 2>/dev/null || true)
        if [ -n "$SSS_LINE" ]; then
            SSS_UID=$(printf '%s' "$SSS_LINE" | cut -d: -f3)
            [ "$SSS_UID" != "$uid" ] && COLLISIONS="$COLLISIONS $name(files=$uid,sss=$SSS_UID)"
        fi
    done < <(getent -s files passwd 2>/dev/null || true)
    if [ -z "$COLLISIONS" ]; then
        set_result USER_COLLISIONS GREEN
    else
        set_result USER_COLLISIONS RED "local/directory identity collisions found:$COLLISIONS - consider reject_local_shadowing=true"
    fi
fi

# --- BREAK_GLASS: is the panic-button script present and applicable ----------
BREAK_GLASS_SCRIPT="/usr/share/sddm-authelia-passkey/break-glass.sh"
[ -x "$BREAK_GLASS_SCRIPT" ] || BREAK_GLASS_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/break-glass.sh"
if [ -x "$BREAK_GLASS_SCRIPT" ] && [ -f "$PAMFILE" ]; then
    set_result BREAK_GLASS GREEN
else
    set_result BREAK_GLASS RED "break-glass.sh missing or $PAMFILE not found"
fi

# --- LOGIN_ENABLEMENT: aggregate gate -----------------------------------------
CRITICAL="SDDM PAM_CONFIG BROKER_CONFIG BROKER OIDC_DISCOVERY JWKS NSS SSSD IDENTITY_PROVENANCE USER_COLLISIONS BREAK_GLASS"
GATE_FAIL=0
for k in $CRITICAL; do
    [ "${RESULT[$k]}" = "RED" ] && GATE_FAIL=1
done
if [ "$GATE_FAIL" -eq 1 ]; then
    set_result LOGIN_ENABLEMENT RED "one or more critical checks failed - see above"
else
    set_result LOGIN_ENABLEMENT GREEN
fi

# --- output --------------------------------------------------------------------
ORDER="SDDM PAM_CONFIG BROKER_CONFIG BROKER OIDC_DISCOVERY JWKS NSS SSSD IDENTITY_PROVENANCE USER_COLLISIONS BREAK_GLASS LOGIN_ENABLEMENT"

case "$MODE" in
    json)
        printf '{'
        first=1
        for k in $ORDER; do
            [ "$first" -eq 1 ] || printf ','
            first=0
            printf '"%s":"%s"' "$k" "${RESULT[$k]}"
        done
        printf '}\n'
        ;;
    explain)
        for k in $ORDER; do
            printf '%s=%s\n' "$k" "${RESULT[$k]}"
            [ -n "${REASON[$k]:-}" ] && printf '  -> %s\n' "${REASON[$k]}"
        done
        ;;
    *)
        for k in $ORDER; do
            printf '%s=%s\n' "$k" "${RESULT[$k]}"
        done
        ;;
esac

[ "${RESULT[LOGIN_ENABLEMENT]}" = "GREEN" ] && exit 0 || exit 1
