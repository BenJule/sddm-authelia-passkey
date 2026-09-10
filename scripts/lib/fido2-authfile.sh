# shellcheck shell=bash
# Shared helpers for the FIDO2/U2F authfile scripts - resolving the
# configured path, and validated append/revoke/list operations on the
# pam_u2f.so authfile format:
#   <username>:<KeyHandle1>,<UserKey1>,<CoseType1>,<Options1>:<KeyHandle2>,...
# (one line per user; multiple credentials are additional colon-separated
# groups on that SAME line, never additional lines for the same user).

fido2_resolve_authfile() {
    local config="${1:-/etc/sddm-authelia-passkey/config.conf}"
    local authfile=/etc/sddm-authelia-passkey/fido2_mappings
    if [ -f "$config" ]; then
        local v
        v=$(awk -F= '/^fido2_authfile=/{print $2; exit}' "$config")
        [ -n "$v" ] && authfile="$v"
    fi
    printf '%s\n' "$authfile"
}

# Appends $2 (a "KeyHandle,UserKey,CoseType,Options" group, as produced by
# `pamu2fcfg -n`) to $1's (the authfile) entry for user $3 - creating a
# new line if the user has none yet, or appending a further
# colon-separated credential group to their existing line otherwise.
# Never touches any other user's line.
fido2_append_credential() {
    local authfile="$1" user="$2" cred="$3"
    local tmp
    tmp="$(mktemp "$(dirname "$authfile")/.fido2_mappings.XXXXXX")"
    if grep -q "^${user}:" "$authfile" 2>/dev/null; then
        awk -v u="$user" -v new="$cred" -F: 'BEGIN{OFS=":"} $1==u {print $0 ":" new; next} {print}' "$authfile" > "$tmp"
    else
        [ -f "$authfile" ] && cp -a "$authfile" "$tmp" || : > "$tmp"
        printf '%s:%s\n' "$user" "$cred" >> "$tmp"
    fi
    install -o root -g root -m 0600 -T "$tmp" "$authfile"
    rm -f "$tmp"
}

# Removes user $2's entire line (all credentials) from authfile $1.
# Never touches any other user's line.
fido2_revoke_user() {
    local authfile="$1" user="$2"
    local tmp
    tmp="$(mktemp "$(dirname "$authfile")/.fido2_mappings.XXXXXX")"
    grep -v "^${user}:" "$authfile" > "$tmp" 2>/dev/null || : > "$tmp"
    install -o root -g root -m 0600 -T "$tmp" "$authfile"
    rm -f "$tmp"
}

# Prints "username: N credential(s)" for every user in authfile $1 -
# never the raw key material.
fido2_list_credentials() {
    local authfile="$1"
    [ -f "$authfile" ] || return 0
    awk -F: 'NF>1 && $1!="" {print $1": "(NF-1)" credential(s)"}' "$authfile"
}
