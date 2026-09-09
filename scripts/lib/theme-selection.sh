# shellcheck shell=bash
replace_sddm_theme_current() {
    local file="$1"
    local old_theme="$2"
    local new_theme="$3"
    local tmp mode uid gid

    [ -f "$file" ] || return 0
    [ ! -L "$file" ] || {
        echo "refusing symlink SDDM config: $file" >&2
        return 1
    }

    tmp="$(mktemp)"
    awk -v old="$old_theme" -v new="$new_theme" '
        /^\[[^]]+\][[:space:]]*$/ {
            in_theme = ($0 ~ /^\[Theme\][[:space:]]*$/)
        }
        {
            if (in_theme && $0 ~ /^[[:space:]]*Current[[:space:]]*=/ && index($0, old)) {
                gsub(old, new)
            }
            print
        }
    ' "$file" > "$tmp"

    if ! cmp -s "$file" "$tmp"; then
        mode="$(stat -c '%a' "$file")"
        uid="$(stat -c '%u' "$file")"
        gid="$(stat -c '%g' "$file")"
        install -o "$uid" -g "$gid" -m "$mode" -T "$tmp" "$file"
        echo "THEME_SELECTION_RESTORED=$file"
    fi
    rm -f "$tmp"
}
