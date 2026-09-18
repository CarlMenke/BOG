#!/usr/bin/env bash
# Photograph every candidate UI style on every screen. Development tool for the
# UI showroom, not shipped, and it writes nothing outside tools/showroom/out/.
#
#   bash tools/showroom/render.sh              # everything
#   bash tools/showroom/render.sh toybox quiet # only these variants
#
# Each render opens a small Godot window for a few seconds; that is the only way
# to get a real image out of the engine (see the header of tools/snapshot.gd).
# They run one at a time on purpose: eight of these at once is eight GPU
# contexts and a machine that stops responding.
#
# Output:
#   tools/showroom/out/<variant>/<mode>.png      2560x1440, what Godot produced
#   tools/showroom/out/web/<variant>__<mode>.jpg 1600 wide, for looking at
#
# Exits non-zero if any PNG or JPG is missing at the end, and prints every
# Godot error it saw so a broken candidate is loud rather than merely ugly.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/tools/showroom/out"
LOG_DIR="$OUT/logs"

MODES=(menu lobby_full settings hud)
ALL_VARIANTS=(current hearth toybox storybook arcade quiet terminal swampglow)
# `current` is the baseline and is always rendered, because the acceptance test
# is "no errors the baseline does not also produce" and that needs the baseline.
if [ "$#" -gt 0 ]; then
    VARIANTS=(current "$@")
else
    VARIANTS=("${ALL_VARIANTS[@]}")
fi

# The engine. Sourced, so a missing Godot ends this script rather than a
# subshell. Sets $GODOT and $GODOT_ROOT (the latter WSL-translated).
GODOT_TAG=showroom
. "$ROOT/tools/find_godot.sh"

mkdir -p "$LOG_DIR" "$OUT/web"

# Physics ticks before the shot. 40 is what tools/ui_range.gd's own docs use; the
# HUD range stands a whole combat range up first and wants longer before the
# Bogs have landed and the ability bar has settled.
ticks_for() {
    case "$1" in
        hud*) echo 90 ;;
        *) echo 40 ;;
    esac
}

renders=0
missing=0
failed=0

for variant in "${VARIANTS[@]}"; do
    mkdir -p "$OUT/$variant"
    for mode in "${MODES[@]}"; do
        png="$OUT/$variant/$mode.png"
        rel="tools/showroom/out/$variant/$mode.png"
        log="$LOG_DIR/${variant}__${mode}.log"
        rm -f "$png"
        renders=$((renders + 1))

        # Run from the repo root: snapshot.gd hands a relative path straight to
        # Image.save_png(), which resolves it against the process's directory.
        ( cd "$ROOT" && "$GODOT" --path "$GODOT_ROOT" --resolution 1600x900 \
            --script tools/snapshot.gd -- \
            res://tools/showroom/showroom_range.tscn "$rel" "$(ticks_for "$mode")" \
            "$mode" "$variant" ) >"$log" 2>&1
        status=$?

        # `grep -c` prints 0 and exits 1 when it finds nothing, so the `|| true`
        # is what keeps `set -o pipefail` quiet without a second "0" in $errs.
        errs=$(grep -cE "SCRIPT ERROR|ERROR:|USER ERROR" "$log" 2>/dev/null || true)
        if [ ! -f "$png" ]; then
            printf '  %-12s %-11s MISSING (exit %d, %s errors) %s\n' \
                "$variant" "$mode" "$status" "$errs" "$log"
            missing=$((missing + 1))
            [ "$status" -ne 0 ] && failed=$((failed + 1))
            continue
        fi
        size=$(grep -o '([0-9]*x[0-9]*)' "$log" | tail -1)
        printf '  %-12s %-11s ok %s  errors:%s\n' "$variant" "$mode" "${size:-?}" "$errs"
    done
done

# ------------------------------------------------------------------- web ---
# Pillow if it is there (it is, on this machine), and a Godot SceneTree script
# otherwise, so a checkout without Python still gets the small copies.
echo
if python -c "import PIL" >/dev/null 2>&1; then
    echo "showroom: shrinking with Pillow"
    python "$ROOT/tools/showroom/shrink.py" "$OUT" || echo "showroom: shrink failed"
else
    echo "showroom: no Pillow, shrinking with Godot"
    ( cd "$ROOT" && "$GODOT" --headless --path "$GODOT_ROOT" \
        --script tools/showroom/shrink.gd -- tools/showroom/out ) \
        >"$LOG_DIR/shrink.log" 2>&1 || echo "showroom: shrink failed, see $LOG_DIR/shrink.log"
fi

jpgs=$(find "$OUT/web" -name '*.jpg' 2>/dev/null | wc -l | tr -d ' ')
pngs=$(find "$OUT" -name '*.png' 2>/dev/null | wc -l | tr -d ' ')

echo
echo "showroom: $pngs PNG, $jpgs JPG, $renders renders attempted"
echo "showroom: full size  $OUT"
echo "showroom: web size   $OUT/web"

if [ "$missing" -gt 0 ]; then
    echo "showroom: FAILED - $missing render(s) produced no PNG ($failed exited non-zero)"
    exit 1
fi
if [ "$jpgs" -lt "$renders" ]; then
    echo "showroom: FAILED - expected $renders web copies, found $jpgs"
    exit 1
fi
echo "showroom: ok"
