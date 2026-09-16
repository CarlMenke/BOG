#!/usr/bin/env bash
# Rebuild `art/generated/bog.glb` from the Mixamo source packs.
#
#   bash tools/build_bog.sh                    # the shipped build (emission 0.15)
#   bash tools/build_bog.sh -- --emission 0.0  # no emission, to re-judge the night
#   bash tools/build_bog.sh -- --body -        # the old body, for an A/B
#   bash tools/build_bog.sh -- --list-packs    # audit assets/source/, build nothing
#
# **The body is not in the Mixamo files any more.** It comes from
# `assets/source/BOG.glb` — one static mesh, no skin and no skeleton — and the
# FBX in the packs below donate the skeleton, every clip and the *weights*: the
# `-- body` stage fits the new mesh over the old one, transfers the skin onto it
# face by face and throws the old mesh away. Not a bone moves, which is the
# point: the 1.80 m rig, the authored speeds, the grips and the ragdoll are all
# still measured against the same skeleton they always were. `--body -` keeps
# the Mixamo mesh instead, which is the Bog as it looked before the swap and is
# there so an A/B is a second build rather than a checkout.
#
# The source is not one folder. `assets/source/` holds a pack per batch of clips
# — `GUB_2/` and, as they are downloaded, `2_Spear_Suite/`, `3_Bow_Suite/`,
# `4_Elder_Suite/`, `5_Locomotion/`, `6_Utility/` — and `PACKS` in the Python
# says which files each one contains and what rules ride on each clip. A pack
# that declares clips must have them; a pack that declares none is a labelled
# empty folder and is skipped out loud. `--list-packs` is that audit on its own,
# without reading an FBX or writing the GLB, which is what to run after dropping
# a hand-downloaded batch into a folder.
#
# All this does is find Blender and hand it `tools/build_bog.py`, which is where
# the actual work and all the explanation live. It exists for the same reason
# `tools/find_godot.sh` does: nobody should have to remember where Blender
# unpacked itself on their machine, and a search that lives in one file does not
# go stale in the second copy.
#
# Anything after `--` is passed through to the script. Blender itself needs the
# `--` to stop parsing arguments, so it is included whether you pass one or not.
#
# After a successful build the asset still has to be imported and looked at:
#
#   GODOT --headless --path . --import
#   GODOT --headless --path . --script tools/inspect_scene.gd -- res://art/generated/bog.glb
#   GODOT --path . --resolution 1600x700 --script tools/snapshot.gd -- \
#       res://tools/preview_anim.tscn out/anim_Run.png 30 Run
#
# Inputs:  $BLENDER (optional override), the packs under assets/source/.
# Outputs: art/generated/bog.glb, and (after the import) bog_basecolor.jpg.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The search itself lives in `tools/find_blender.sh`, shared with
# `tools/build_elder.sh`, for the reason `tools/find_godot.sh` gives at the top
# of itself: a search for where somebody installed Blender has to stay in step
# with reality, and two copies of it will not. It is sourced, so a missing
# Blender ends this script rather than a subshell.
BLENDER_TAG=build_bog
. "$ROOT/tools/find_blender.sh"

# `--factory-startup` is deliberate: this machine has third-party add-ons that
# print into the log and open sockets on load, and a build that depends on what
# add-ons somebody has enabled is not a build.
"$BLENDER_BIN" --background --factory-startup \
    --python "$ROOT/tools/build_bog.py" -- "$@"
status=$?

if [ "$status" -ne 0 ]; then
    echo "build_bog: Blender exited $status — the GLB was NOT rewritten if the"
    echo "       failure was before the export step. Read the log above."
fi
exit "$status"
