#!/usr/bin/env bash
# Photograph every candidate *arrangement* of every screen. Development tool for
# the UI showroom, not shipped, and it writes nothing outside tools/showroom/out/.
#
#   bash tools/showroom/render_layouts.sh                  # all 18
#   bash tools/showroom/render_layouts.sh menu             # one screen
#   bash tools/showroom/render_layouts.sh menu__card       # one layout
#   bash tools/showroom/render_layouts.sh hud__compact lobby__columns
#
# The sibling of `render.sh`. That one holds the layout still and changes the
# look; this one holds the look still — every shot is the `quiet` style the owner
# picked, now with radii — and changes where the pieces are.
#
# Each render opens a small Godot window for a few seconds; that is the only way
# to get a real image out of the engine (see the header of tools/snapshot.gd).
# They run one at a time on purpose: eighteen GPU contexts at once is a machine
# that stops responding.
#
# Output:
#   tools/showroom/out/layouts/<screen>__<layout>.png      2560x1440
#   tools/showroom/out/web_layouts/<screen>__<layout>.jpg  1600 wide
#
# Exits non-zero if any PNG or JPG is missing at the end, and prints every Godot
# error it saw so a broken recipe is loud rather than merely ugly.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/tools/showroom/out"
PNG_DIR="$OUT/layouts"
WEB_DIR="$OUT/web_layouts"
LOG_DIR="$OUT/logs"

# The style every one of these wears. The showroom's other half has already been
# looked at and answered; this one is only about arrangement, so a second
# variable here would be a knob nobody is turning.
VARIANT=quiet

# `<screen>:<range mode>:<layout>`. `current` is in the list for every screen
# because the acceptance test is "reads better than what we have" and that needs
# what we have, rendered fresh through the same pipeline and the same theme.
SHOTS=(
    "menu:menu:current"
    "menu:menu:centred"
    "menu:menu:bottombar"
    "menu:menu:rightcolumn"
    "menu:menu:card"

    "lobby:lobby_full:current"
    "lobby:lobby_full:rightrail"
    "lobby:lobby_full:bottomdock"
    "lobby:lobby_full:leftrail"
    "lobby:lobby_full:columns"

    "settings:settings:current"
    "settings:settings:sheet"
    "settings:settings:page"
    "settings:settings:tabs"

    "hud:hud:current"
    "hud:hud:corners"
    "hud:hud:rightstack"
    "hud:hud:compact"
)

# An argument is either a screen (`menu`) or one shot (`menu__card`). No
# argument is everything.
wanted() {
    local screen="$1" layout="$2"
    [ "$#" -lt 3 ] && return 0
    shift 2
    local arg
    for arg in "$@"; do
        [ "$arg" = "$screen" ] && return 0
        [ "$arg" = "${screen}__${layout}" ] && return 0
    done
    return 1
}

# The engine. Sourced, so a missing Godot ends this script rather than a
# subshell. Sets $GODOT and $GODOT_ROOT (the latter WSL-translated).
GODOT_TAG=showroom
. "$ROOT/tools/find_godot.sh"

mkdir -p "$PNG_DIR" "$WEB_DIR" "$LOG_DIR"

# Physics ticks before the shot, from `render.sh`: 40 is what tools/ui_range.gd's
# own docs use, and the HUD range stands a whole combat range up first and wants
# longer before the Bogs have landed and the ability bar has settled.
ticks_for() {
    case "$1" in
        hud*) echo 90 ;;
        *) echo 40 ;;
    esac
}

renders=0
missing=0
failed=0
errors=0
skipped=0

echo "showroom: layouts, all in the '$VARIANT' style"
echo

for shot in "${SHOTS[@]}"; do
    IFS=: read -r screen mode layout <<<"$shot"
    if ! wanted "$screen" "$layout" "$@"; then
        skipped=$((skipped + 1))
        continue
    fi

    stem="${screen}__${layout}"
    png="$PNG_DIR/$stem.png"
    rel="tools/showroom/out/layouts/$stem.png"
    log="$LOG_DIR/layout__$stem.log"
    rm -f "$png"
    renders=$((renders + 1))

    # Run from the repo root: snapshot.gd hands a relative path straight to
    # Image.save_png(), which resolves it against the process's directory.
    ( cd "$ROOT" && "$GODOT" --path "$GODOT_ROOT" --resolution 1600x900 \
        --script tools/snapshot.gd -- \
        res://tools/showroom/showroom_range.tscn "$rel" "$(ticks_for "$mode")" \
        "$mode" "$VARIANT" "$layout" ) >"$log" 2>&1
    status=$?

    # `grep -c` prints 0 and exits 1 when it finds nothing, so the `|| true` is
    # what keeps `set -o pipefail` quiet without a second "0" in $errs.
    errs=$(grep -cE "SCRIPT ERROR|ERROR:|USER ERROR" "$log" 2>/dev/null || true)
    errors=$((errors + errs))
    if [ ! -f "$png" ]; then
        printf '  %-9s %-11s MISSING (exit %d, %s errors) %s\n' \
            "$screen" "$layout" "$status" "$errs" "$log"
        missing=$((missing + 1))
        [ "$status" -ne 0 ] && failed=$((failed + 1))
        continue
    fi
    size=$(grep -o '([0-9]*x[0-9]*)' "$log" | tail -1)
    printf '  %-9s %-11s ok %s  errors:%s\n' "$screen" "$layout" "${size:-?}" "$errs"
done

# ------------------------------------------------------------------- web ---
# Pillow if it is there (it is, on this machine), and a Godot SceneTree script
# otherwise, so a checkout without Python still gets the small copies.
echo
if python -c "import PIL" >/dev/null 2>&1; then
    echo "showroom: shrinking with Pillow"
    python "$ROOT/tools/showroom/shrink.py" "$PNG_DIR" "$WEB_DIR" \
        || echo "showroom: shrink failed"
else
    echo "showroom: no Pillow, shrinking with Godot"
    ( cd "$ROOT" && "$GODOT" --headless --path "$GODOT_ROOT" \
        --script tools/showroom/shrink.gd -- \
        tools/showroom/out/layouts tools/showroom/out/web_layouts ) \
        >"$LOG_DIR/shrink_layouts.log" 2>&1 \
        || echo "showroom: shrink failed, see $LOG_DIR/shrink_layouts.log"
fi

pngs=$(find "$PNG_DIR" -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
jpgs=$(find "$WEB_DIR" -name '*.jpg' 2>/dev/null | wc -l | tr -d ' ')

echo
echo "showroom: $pngs PNG, $jpgs JPG, $renders renders attempted ($skipped skipped)"
echo "showroom: $errors Godot error line(s) across the logs in $LOG_DIR"
echo "showroom: full size  $PNG_DIR"
echo "showroom: web size   $WEB_DIR"

if [ "$missing" -gt 0 ]; then
    echo "showroom: FAILED - $missing render(s) produced no PNG ($failed exited non-zero)"
    exit 1
fi
if [ "$jpgs" -lt "$renders" ]; then
    echo "showroom: FAILED - expected at least $renders web copies, found $jpgs"
    exit 1
fi
echo "showroom: ok"
