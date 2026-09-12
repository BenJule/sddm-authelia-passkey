#!/usr/bin/env bash
set +e
set -u

ROOT="tests/native/visual/baselines"
TMP="tests/native/visual/.render-current"
OUT="${1:-/tmp/v115-visual-regression}"
STOP=0
PASS=0
UPDATE_BASELINES=0
[ "${2:-}" = "--update-baselines" ] && UPDATE_BASELINES=1

FONT_ROOT="$(mktemp -d /tmp/v115-fonts-XXXXXXXX)"
FONT_DIR="$FONT_ROOT/fonts"
FONTCONF="$FONT_ROOT/fonts.conf"
FONT_SRC="/usr/share/fonts/truetype/noto"

ALL_STATES=(
    idle password smartphone_panel_idle starting
    waiting alternate_code approved logging_in
    rate_limited offline denied expired
    invalid_branding_asset long_branding no_avatar
    directory_account smartphone_unreachable fido2_available
)

MATRIX_STATES=(
    idle waiting offline long_branding
)

rm -rf "$TMP" "$OUT"
mkdir -p "$OUT" "$FONT_DIR"

for F in     NotoSans-Regular.ttf     NotoSans-Bold.ttf     NotoSans-Italic.ttf     NotoSans-BoldItalic.ttf
do
    cp "$FONT_SRC/$F" "$FONT_DIR/$F" || STOP=1
done

cat > "$FONTCONF" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>$FONT_DIR</dir>
  <cachedir>$FONT_ROOT/cache</cachedir>
  <alias>
    <family>sans-serif</family>
    <prefer><family>Noto Sans</family></prefer>
  </alias>
  <alias>
    <family>Sans Serif</family>
    <prefer><family>Noto Sans</family></prefer>
  </alias>
  <match target="font">
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
    <edit name="rgba" mode="assign"><const>none</const></edit>
    <edit name="embeddedbitmap" mode="assign"><bool>false</bool></edit>
  </match>
</fontconfig>
EOF

render_case() {
    STATE="$1"
    WIDTH="$2"
    HEIGHT="$3"
    SCALE="$4"

    rm -rf "$TMP"
    cp -a tests/native/visual/harness "$TMP"

    sed -i \
        "s/^visual_state=.*/visual_state=$STATE/" \
        "$TMP/theme.conf"

    ID="${WIDTH}x${HEIGHT}@${SCALE}__${STATE}"
    EXPECTED="$ROOT/${WIDTH}x${HEIGHT}@${SCALE}/${STATE}.png"
    ACTUAL="$OUT/${ID}.actual.png"
    DIFF="$OUT/${ID}.diff.png"
    LOG="$OUT/${ID}.log"
    METRIC="$OUT/${ID}.metric"

    xvfb-run -a \
        --server-args="-screen 0 ${WIDTH}x${HEIGHT}x24 -dpi 96" \
        bash -c "
            unset WAYLAND_DISPLAY WAYLAND_SOCKET
            unset QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE
            unset XDG_CURRENT_DESKTOP DESKTOP_SESSION
            unset KDE_FULL_SESSION KDE_SESSION_VERSION
            export FONTCONFIG_FILE='$FONTCONF'
            export LANG=C.UTF-8
            export LC_ALL=C.UTF-8
            export QT_FONT_DPI=96
            export QT_QPA_PLATFORM=xcb
            export QT_QUICK_BACKEND=software
            export LIBGL_ALWAYS_SOFTWARE=1
            export XDG_SESSION_TYPE=x11
            export QT_SCALE_FACTOR='$SCALE'
            export QT_SCALE_FACTOR_ROUNDING_POLICY=PassThrough

            sddm-greeter-qt6 \
                --test-mode \
                --theme '$TMP' \
                >'$LOG' 2>&1 &

            PID=\$!
            sleep 3

            import -window root '$ACTUAL'
            RC=\$?

            kill \$PID >/dev/null 2>&1
            wait \$PID >/dev/null 2>&1

            test \$RC -eq 0
        "

    RENDER_RC=$?

    FATAL=NO
    grep -Eqi \
        'QQmlApplicationEngine failed|failed to load component|ReferenceError|TypeError|SyntaxError|module .* is not installed|is not a type' \
        "$LOG" &&
        FATAL=YES

    if [ "$UPDATE_BASELINES" -eq 1 ] &&
       [ "$RENDER_RC" -eq 0 ] &&
       [ "$FATAL" = "NO" ]; then
        mkdir -p "$(dirname "$EXPECTED")"
        cp "$ACTUAL" "$EXPECTED"
        COMPARE_RC=0
        CHANGED=0
        printf '0\n' > "$METRIC"
        : > "$DIFF"
    else
        compare \
            -metric AE \
            -fuzz 6% \
            "$EXPECTED" \
            "$ACTUAL" \
            "$DIFF" \
            2>"$METRIC"

        COMPARE_RC=$?
        CHANGED="$(head -n1 "$METRIC" | awk '{print $1}')"
    fi

    MAX_CHANGED=$((WIDTH * HEIGHT / 100))

    case "$CHANGED" in
        ''|*[!0-9]*) VALID=NO ;;
        *) VALID=YES ;;
    esac

    echo "$ID RENDER=$RENDER_RC COMPARE=$COMPARE_RC CHANGED=$CHANGED MAX=$MAX_CHANGED FATAL=$FATAL"

    if [ "$RENDER_RC" -ne 0 ] ||
       [ "$COMPARE_RC" -gt 1 ] ||
       [ "$VALID" != "YES" ] ||
       [ "$FATAL" != "NO" ] ||
       [ "$CHANGED" -gt "$MAX_CHANGED" ]; then
        STOP=1
    else
        PASS=$((PASS + 1))
    fi
}

for STATE in "${ALL_STATES[@]}"
do
    [ "$STOP" -eq 0 ] || break
    render_case "$STATE" 1280 720 1.00
done

for SCALE in 1.00 1.25
do
    for STATE in "${MATRIX_STATES[@]}"
    do
        [ "$STOP" -eq 0 ] || break
        render_case "$STATE" 1920 1080 "$SCALE"
    done
done

rm -rf "$TMP" "$FONT_ROOT"

echo
echo "VISUAL_PASS=$PASS"

if [ "$STOP" -eq 0 ] &&
   [ "$PASS" -eq 26 ]; then
    echo "VISUAL_REGRESSION=26_OF_26_GREEN"
    echo "VISUAL_STATES=18"
    echo "MATRIX_CASES=8"
    echo "FUZZ=6_PERCENT"
    echo "MAX_CHANGED_RATIO=1_PERCENT"
    echo "RENDER_FONT=NOTO_SANS"
    echo "RENDER_DPI=96"
else
    echo "VISUAL_REGRESSION=FAILED"
    echo "DIAGNOSTICS=$OUT"
fi

test "$STOP" -eq 0
