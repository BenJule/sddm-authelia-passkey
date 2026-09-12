#!/bin/bash
set -euo pipefail
umask 077

TEST_ROOT="${SDDM_AUTHELIA_TEST_ROOT:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

root_path() {
    printf '%s%s\n' "$TEST_ROOT" "$1"
}

CONFIG_FILE="$(root_path /etc/sddm.conf)"
CONFIG_DIR="$(root_path /etc/sddm.conf.d)"
SYSTEM_CONFIG_DIR="$(root_path /usr/lib/sddm/sddm.conf.d)"
THEMES_DIR="$(root_path /usr/share/sddm/themes)"

STATE_DIR="$(root_path /var/lib/sddm-authelia-passkey/theme-mode)"
STATE_FILE="$STATE_DIR/state.conf"
BACKUP_FILE="$STATE_DIR/selection.before"
MANAGED_FILE="$CONFIG_DIR/99-sddm-authelia-passkey-theme.conf"

NATIVE_THEME="sddm-authelia-passkey-native"
COMPAT_THEME="debian-breeze-authelia-passkey"

fail() {
    echo "THEME_MODE_ERROR=$*" >&2
    return 64
}

state_get() {
    local key="$1"

    [ -f "$STATE_FILE" ] || return 0

    awk -F= -v key="$key" '
        $1 == key {
            sub(/^[^=]*=/, "")
            print
            found=1
        }
        END {
            if (!found)
                print ""
        }
    ' "$STATE_FILE"
}

theme_from_file() {
    local file="$1"

    [ -f "$file" ] || return 0

    awk '
        /^\[[^]]+\][[:space:]]*$/ {
            in_theme = ($0 ~ /^\[Theme\][[:space:]]*$/)
            next
        }

        in_theme &&
        /^[[:space:]]*Current[[:space:]]*=/ {
            line=$0
            sub(/^[^=]*=/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            value=line
        }

        END {
            if (value != "")
                print value
        }
    ' "$file"
}

sorted_conf_files() {
    local dir="$1"

    [ -d "$dir" ] || return 0

    find "$dir" \
        -maxdepth 1 \
        -type f \
        -name '*.conf' \
        -print0 2>/dev/null |
        sort -z
}

effective_theme() {
    local theme=""
    local dir
    local file
    local value

    for dir in "$SYSTEM_CONFIG_DIR" "$CONFIG_DIR"; do
        while IFS= read -r -d '' file; do
            value="$(theme_from_file "$file")"
            [ -z "$value" ] || theme="$value"
        done < <(sorted_conf_files "$dir")
    done

    if [ -f "$CONFIG_FILE" ]; then
        value="$(theme_from_file "$CONFIG_FILE")"
        [ -z "$value" ] || theme="$value"
    fi

    printf '%s\n' "$theme"
}

safe_config_file() {
    local file="$1"
    local owner
    local mode
    local mode_dec

    if [ -L "$file" ]; then
        fail "refusing symlink SDDM config: $file" || return 64
    fi

    [ -f "$file" ] || return 0

    if [ -z "$TEST_ROOT" ]; then
        owner="$(stat -c '%u:%g' "$file")"

        if [ "$owner" != "0:0" ]; then
            fail "SDDM config must be root:root: $file" || return 64
        fi
    fi

    mode="$(stat -c '%a' "$file")"
    mode_dec=$((8#$mode))

    if (( (mode_dec & 022) != 0 )); then
        fail "SDDM config is group/world writable: $file" || return 64
    fi

    return 0
}

choose_selection_file() {
    local file
    local value
    local chosen=""

    if [ -e "$CONFIG_FILE" ] || [ -L "$CONFIG_FILE" ]; then
        safe_config_file "$CONFIG_FILE" || return 64
        printf '%s\n' "$CONFIG_FILE"
        return 0
    fi

    while IFS= read -r -d '' file; do
        value="$(theme_from_file "$file")"
        [ -z "$value" ] || chosen="$file"
    done < <(sorted_conf_files "$CONFIG_DIR")

    if [ -n "$chosen" ]; then
        safe_config_file "$chosen" || return 64
        printf '%s\n' "$chosen"
    else
        printf '%s\n' "$MANAGED_FILE"
    fi
}

count_theme_current() {
    local file="$1"

    if [ ! -f "$file" ]; then
        printf '0\n'
    else
        awk '
            /^\[[^]]+\][[:space:]]*$/ {
                in_theme = ($0 ~ /^\[Theme\][[:space:]]*$/)
                next
            }

            in_theme &&
            /^[[:space:]]*Current[[:space:]]*=/ {
                count++
            }

            END {
                print count+0
            }
        ' "$file"
    fi
}

set_theme_current() {
    local file="$1"
    local target="$2"
    local tmp
    local mode
    local uid
    local gid
    local count

    mkdir -p "$(dirname "$file")"

    [ ! -L "$file" ] ||
        fail "refusing symlink SDDM config: $file"

    if [ ! -e "$file" ]; then
        printf '[Theme]\nCurrent=%s\n' "$target" > "$file"
        chmod 0644 "$file"

        if [ -z "$TEST_ROOT" ]; then
            chown root:root "$file"
        fi
    else
        safe_config_file "$file"

        count="$(count_theme_current "$file")"

        if [ "$count" -gt 1 ]; then
            fail "multiple Theme/Current entries: $file"
        else
            tmp="$(mktemp "$(dirname "$file")/.theme-mode.XXXXXX")"

            mode="$(stat -c '%a' "$file")"
            uid="$(stat -c '%u' "$file")"
            gid="$(stat -c '%g' "$file")"

            awk -v new="$target" '
                BEGIN {
                    in_theme=0
                    saw_theme=0
                    wrote=0
                }

                /^\[[^]]+\][[:space:]]*$/ {
                    if (in_theme && !wrote) {
                        print "Current=" new
                        wrote=1
                    }

                    in_theme = ($0 ~ /^\[Theme\][[:space:]]*$/)

                    if (in_theme)
                        saw_theme=1

                    print
                    next
                }

                {
                    if (in_theme &&
                        $0 ~ /^[[:space:]]*Current[[:space:]]*=/) {
                        if (!wrote) {
                            print "Current=" new
                            wrote=1
                        }
                        next
                    }

                    print
                }

                END {
                    if (in_theme && !wrote)
                        print "Current=" new

                    if (!saw_theme) {
                        print ""
                        print "[Theme]"
                        print "Current=" new
                    }
                }
            ' "$file" > "$tmp"

            install \
                -o "$uid" \
                -g "$gid" \
                -m "$mode" \
                -T "$tmp" \
                "$file"

            rm -f "$tmp"
        fi
    fi
}

theme_is_valid() {
    local name="$1"
    local dir
    local file
    local owner
    local mode
    local mode_dec
    local valid=1

    dir="$THEMES_DIR/$name"

    [ -d "$dir" ] || valid=0
    [ ! -L "$dir" ] || valid=0

    for file in "$dir/Main.qml" "$dir/metadata.desktop"; do
        [ -f "$file" ] || valid=0
        [ ! -L "$file" ] || valid=0

        if [ "$valid" -eq 1 ] && [ -z "$TEST_ROOT" ]; then
            owner="$(stat -c '%u:%g' "$file")"
            [ "$owner" = "0:0" ] || valid=0
        fi

        if [ "$valid" -eq 1 ]; then
            mode="$(stat -c '%a' "$file")"
            mode_dec=$((8#$mode))

            (( (mode_dec & 022) == 0 )) || valid=0
        fi
    done

    test "$valid" -eq 1
}

write_state() {
    local mode="$1"
    local managed="$2"
    local selection="$3"
    local created="$4"
    local baseline="$5"
    local managed_hash="$6"
    local tmp

    mkdir -p "$STATE_DIR"
    chmod 0700 "$STATE_DIR"

    tmp="$(mktemp "$STATE_DIR/.state.XXXXXX")"

    {
        printf 'mode=%s\n' "$mode"
        printf 'managed=%s\n' "$managed"
        printf 'selection_path=%s\n' "$selection"
        printf 'selection_created=%s\n' "$created"
        printf 'baseline_theme=%s\n' "$baseline"
        printf 'managed_hash=%s\n' "$managed_hash"
    } > "$tmp"

    if [ -z "$TEST_ROOT" ]; then
        install -o root -g root -m 0600 -T "$tmp" "$STATE_FILE"
    else
        install -m 0600 -T "$tmp" "$STATE_FILE"
    fi

    rm -f "$tmp"
}

ensure_target_theme() {
    local mode="$1"
    local target="$2"

    if theme_is_valid "$target"; then
        true
    else
        if [ "$mode" = "compatibility" ] &&
           [ -z "$TEST_ROOT" ] &&
           [ -x "$SCRIPT_DIR/install-theme.sh" ]; then
            "$SCRIPT_DIR/install-theme.sh"
        fi

        theme_is_valid "$target" ||
            fail "invalid or missing target theme: $target"
    fi
}

verify_managed_hash() {
    local path
    local expected
    local actual

    path="$(state_get selection_path)"
    expected="$(state_get managed_hash)"

    [ -n "$path" ] ||
        fail "missing managed selection path"

    [ -n "$expected" ] ||
        fail "missing managed selection hash"

    [ -f "$path" ] ||
        fail "managed SDDM config missing: $path"

    [ ! -L "$path" ] ||
        fail "managed SDDM config became symlink: $path"

    safe_config_file "$path"

    actual="$(sha256sum "$path" | awk '{print $1}')"

    [ "$actual" = "$expected" ] ||
        fail "managed SDDM config changed externally: $path"
}

capture_baseline() {
    local selection
    local created=0
    local baseline

    selection="$(choose_selection_file)" || return 64
    baseline="$(effective_theme)"

    mkdir -p "$STATE_DIR"
    chmod 0700 "$STATE_DIR"

    if [ -e "$selection" ] || [ -L "$selection" ]; then
        safe_config_file "$selection" || return 64

        # STATE_DIR is 0700, so the backup remains private while
        # preserving the original owner/group/mode for exact rollback.
        cp -a "$selection" "$BACKUP_FILE"
    else
        created=1
        rm -f "$BACKUP_FILE"
    fi

    write_state \
        "backend-only" \
        "1" \
        "$selection" \
        "$created" \
        "$baseline" \
        ""
}

apply_theme_mode() {
    local requested="$1"
    local target
    local managed
    local current_mode
    local selection
    local created
    local baseline
    local managed_hash
    local current_effective
    local new_hash

    case "$requested" in
        native)
            target="$NATIVE_THEME"
            ;;
        compatibility)
            target="$COMPAT_THEME"
            ;;
        *)
            fail "unsupported theme mode: $requested"
            ;;
    esac

    ensure_target_theme "$requested" "$target"

    managed="$(state_get managed)"
    current_mode="$(state_get mode)"
    managed_hash="$(state_get managed_hash)"

    if [ "$managed" != "1" ]; then
        capture_baseline
    else
        if [ -n "$managed_hash" ]; then
            verify_managed_hash
        elif [ "$current_mode" != "backend-only" ]; then
            fail "incomplete managed theme state"
        fi
    fi

    current_mode="$(state_get mode)"
    managed_hash="$(state_get managed_hash)"

    if [ "$current_mode" = "$requested" ] &&
       [ -n "$managed_hash" ]; then

        verify_managed_hash
        current_effective="$(effective_theme)"

        if [ "$current_effective" = "$target" ]; then
            echo "INSTALL_MODE=$requested"
            echo "MODE_APPLY=NOOP"
            echo "MODE_TARGET=$target"
            echo "EFFECTIVE_THEME=$current_effective"
            echo "SDDM_RESTART_USED=NO"
            return 0
        fi
    fi

    selection="$(state_get selection_path)"
    created="$(state_get selection_created)"
    baseline="$(state_get baseline_theme)"

    [ -n "$selection" ] ||
        fail "missing selection_path in theme state"

    set_theme_current "$selection" "$target"

    new_hash="$(
        sha256sum "$selection" |
        awk '{print $1}'
    )"

    write_state \
        "$requested" \
        "1" \
        "$selection" \
        "$created" \
        "$baseline" \
        "$new_hash"

    current_effective="$(effective_theme)"

    [ "$current_effective" = "$target" ] ||
        fail "effective theme does not match requested mode"

    echo "INSTALL_MODE=$requested"
    echo "MODE_APPLY=GREEN"
    echo "MODE_TARGET=$target"
    echo "SELECTION_FILE=$selection"
    echo "BASELINE_THEME=${baseline:-<compiled-default>}"
    echo "EFFECTIVE_THEME=$current_effective"
    echo "SDDM_RESTART_USED=NO"
}

apply_backend_only() {
    local managed
    local selection
    local created
    local baseline
    local current
    local managed_hash

    managed="$(state_get managed)"
    managed_hash="$(state_get managed_hash)"

    if [ "$managed" != "1" ]; then
        mkdir -p "$STATE_DIR"
        chmod 0700 "$STATE_DIR"

        rm -f "$BACKUP_FILE"

        current="$(effective_theme)"

        write_state \
            "backend-only" \
            "0" \
            "" \
            "" \
            "$current" \
            ""

        echo "INSTALL_MODE=backend-only"
        echo "MODE_APPLY=NOOP"
        echo "EFFECTIVE_THEME=${current:-<compiled-default>}"
        echo "SDDM_RESTART_USED=NO"

        return 0
    fi

    [ -n "$managed_hash" ] ||
        fail "managed state has no configuration hash"

    verify_managed_hash

    selection="$(state_get selection_path)"
    created="$(state_get selection_created)"
    baseline="$(state_get baseline_theme)"

    [ -n "$selection" ] ||
        fail "managed state has no selection path"

    case "$created" in
        1)
            rm -f "$selection"
            ;;
        0)
            [ -f "$BACKUP_FILE" ] ||
                fail "theme-selection backup missing"

            [ ! -L "$BACKUP_FILE" ] ||
                fail "theme-selection backup became symlink"

            rm -f "$selection"
            cp -a "$BACKUP_FILE" "$selection"
            ;;
        *)
            fail "invalid selection_created state"
            ;;
    esac

    rm -f "$BACKUP_FILE"

    current="$(effective_theme)"

    write_state \
        "backend-only" \
        "0" \
        "" \
        "" \
        "$current" \
        ""

    echo "INSTALL_MODE=backend-only"
    echo "MODE_APPLY=GREEN"
    echo "RESTORED_THEME=${baseline:-<compiled-default>}"
    echo "EFFECTIVE_THEME=${current:-<compiled-default>}"
    echo "SDDM_RESTART_USED=NO"
}

status_mode() {
    local mode
    local managed
    local effective
    local target=""
    local target_valid="N/A"
    local selection
    local baseline

    mode="$(state_get mode)"
    managed="$(state_get managed)"
    effective="$(effective_theme)"
    selection="$(state_get selection_path)"
    baseline="$(state_get baseline_theme)"

    [ -n "$mode" ] || mode="backend-only"
    [ -n "$managed" ] || managed="0"

    case "$mode" in
        native)
            target="$NATIVE_THEME"
            ;;
        compatibility)
            target="$COMPAT_THEME"
            ;;
        backend-only)
            ;;
        *)
            target_valid="NO"
            ;;
    esac

    if [ -n "$target" ]; then
        if theme_is_valid "$target"; then
            target_valid="YES"
        else
            target_valid="NO"
        fi
    fi

    echo "INSTALL_MODE=$mode"

    if [ "$managed" = "1" ]; then
        echo "THEME_SELECTION_MANAGED=YES"
    else
        echo "THEME_SELECTION_MANAGED=NO"
    fi

    echo "EFFECTIVE_THEME=${effective:-<compiled-default>}"
    echo "MODE_TARGET=${target:-<none>}"
    echo "TARGET_VALID=$target_valid"
    echo "SELECTION_FILE=${selection:-<none>}"
    echo "BASELINE_THEME=${baseline:-<unknown-or-compiled-default>}"
    echo "SDDM_RESTART_USED=NO"
}

check_target_theme() {
    local requested="$1"
    local target=""

    case "$requested" in
        native)
            target="$NATIVE_THEME"
            ;;
        compatibility)
            target="$COMPAT_THEME"
            ;;
        backend-only)
            ;;
        *)
            fail "unsupported theme mode: $requested"
            ;;
    esac

    echo "TARGET=${target:-<none>}"

    if [ -z "$target" ]; then
        echo "TARGET_VALID=N/A"
    elif theme_is_valid "$target"; then
        echo "TARGET_VALID=YES"
    else
        echo "TARGET_VALID=NO"
    fi
}

usage() {
    echo \
        "usage: $0 {status|apply native|apply compatibility|apply backend-only|check-target native|check-target compatibility|check-target backend-only}" \
        >&2
    false
}

if [ -z "$TEST_ROOT" ] && [ "$(id -u)" -ne 0 ]; then
    fail "must run as root"
fi

COMMAND="${1:-}"

case "$COMMAND" in
    status)
        status_mode
        ;;

    apply)
        REQUESTED="${2:-}"

        case "$REQUESTED" in
            native|compatibility)
                apply_theme_mode "$REQUESTED"
                ;;
            backend-only)
                apply_backend_only
                ;;
            *)
                usage
                ;;
        esac
        ;;

    check-target)
        REQUESTED="${2:-}"

        case "$REQUESTED" in
            native|compatibility|backend-only)
                check_target_theme "$REQUESTED"
                ;;
            *)
                usage
                ;;
        esac
        ;;

    *)
        usage
        ;;
esac
