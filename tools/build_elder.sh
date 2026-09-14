#!/usr/bin/env bash
# Build `art/generated/elder.glb` — the Elder's purple robe and wizard hat, as
# one skinned mesh that binds to the Gub's own skeleton.
#
#   bash tools/build_elder.sh                    # the shipped build (emission 1.0)
#   bash tools/build_elder.sh -- --emission 0.0  # no glow, to re-judge the night
#   bash tools/build_elder.sh -- --emission 2.0  # brighter runes
#
# All this does is find Blender and hand it `tools/build_elder.py`, which is
# where the actual work and all the explanation live. The search itself is in
# `tools/find_blender.sh`, shared with `tools/build_gub.sh`, for the reason
# `tools/find_godot.sh` gives at the top of itself.
#
# Anything after `--` is passed through to the script. Blender itself needs the
# `--` to stop parsing arguments, so it is included whether you pass one or not.
#
# The input is `art/generated/gub.glb`, so a rebuilt Gub means a rebuilt Elder:
#
#   bash tools/build_gub.sh
#   bash tools/build_elder.sh
#
# After a successful build the asset still has to be imported and looked at:
#
#   GODOT --headless --path . --import
#   GODOT --headless --path . --script tools/inspect_scene.gd -- res://art/generated/elder.glb
#   GODOT --path . --resolution 1100x900 --script tools/snapshot.gd -- \
#       res://tools/preview_elder.tscn out/elder_idle_front.png 40 mid studio Idle 1.2
#
# Inputs:  $BLENDER (optional override), art/generated/gub.glb.
# Outputs: art/generated/elder.glb, and (after the import) elder_basecolor.png
#          and elder_emissive.png.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BLENDER_TAG=build_elder
. "$ROOT/tools/find_blender.sh"

# `--factory-startup` is deliberate: this machine has third-party add-ons that
# print into the log and open sockets on load, and a build that depends on what
# add-ons somebody has enabled is not a build.
"$BLENDER_BIN" --background --factory-startup \
    --python "$ROOT/tools/build_elder.py" -- "$@"
status=$?

if [ "$status" -ne 0 ]; then
    echo "build_elder: Blender exited $status — the GLB was NOT rewritten if the"
    echo "       failure was before the export step. Read the log above."
fi
exit "$status"
