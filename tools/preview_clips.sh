#!/usr/bin/env bash
# Look at a raw Mixamo FBX before anybody writes a `Clip(...)` line for it.
#
#   bash tools/preview_clips.sh 2_Spear_Suite/SpearThrowLonger.fbx
#   bash tools/preview_clips.sh GUB_2/Throw.fbx 2_Spear_Suite/SpearThrowLonger.fbx \
#       --out out/spear_candidates.png --title "Step 4 — which throw?"
#   bash tools/preview_clips.sh 7_GreatSword_Suite/GreatSwordHighSpinAttack.fbx \
#       "_rejected/Great Sword Pack/GreatSwordAttack.fbx" --align first
#   bash tools/preview_clips.sh GUB_2/Throw.fbx --mode flat   # the silhouette
#
# One PNG contact sheet, one row per clip, columns aligned on each clip's own
# release so the poses can be compared down a column. Paths are relative to
# `assets/source/` (or to the repo, or to where you are standing), and nothing
# has to be declared in `PACKS` first — that is the whole point. Files inside
# `assets/source/_rejected/` work too, which is where the fallbacks live.
#
# `--help` lists every option. The arguments worth knowing about:
#
#   --mode flat        a true black-on-white silhouette instead of lit clay
#   --focus S          override the detected release (per clip: `--focus 1.6,1.2`)
#   --align first      face the clip's *first* frame front instead of its release
#   --azimuth 0        dead front; 90 is a side view; the default is 35
#   --yaw              force the floor compass on for a clip that turns
#
# All this does is find Blender and hand it `tools/preview_clips.py`, which is
# where the work and all the explanation live. It exists for the same reason
# `tools/build_bog.sh` does: nobody should have to remember where Blender
# unpacked itself, and the search lives once in `tools/find_blender.sh`.
#
# This is the *raw source* half of a pair. `tools/preview_anim.gd` does the same
# job one stage later, on clips that have already been declared and built:
#
#   GODOT --path . --resolution 1600x700 --script tools/snapshot.gd -- \
#       res://tools/preview_anim.tscn out/anim_Throw.png 30 Throw 1.45 1.80
#
# Inputs:  $BLENDER (optional override), any .fbx under assets/source/.
# Outputs: one PNG under out/ (gitignored). Nothing is declared, nothing is
#          built, and art/generated/ is not touched.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BLENDER_TAG=preview_clips
. "$ROOT/tools/find_blender.sh"

# `--factory-startup` is deliberate, as in `tools/build_bog.sh`: this machine has
# third-party add-ons that print into the log and open sockets on load, and a
# preview that depends on what add-ons somebody has enabled is not a preview.
"$BLENDER_BIN" --background --factory-startup \
    --python "$ROOT/tools/preview_clips.py" -- "$@"
status=$?

if [ "$status" -ne 0 ]; then
    echo "preview_clips: Blender exited $status — read the log above. Nothing"
    echo "       was written except possibly the PNG."
fi
exit "$status"
