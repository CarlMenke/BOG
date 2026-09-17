#!/usr/bin/env bash
# Write the `.import` file for every clip in assets/source/anims/ that does
# not have one yet, so a freshly fetched clip imports with the settings the
# pipeline needs (D-095) instead of Godot's defaults, which would land it a
# centimetre tall with its hip bob optimised away and no post-import script.
#
#   bash tools/clip_imports.sh          # only clips with no .import
#   bash tools/clip_imports.sh --all    # rewrite every clip's .import
#
# The settings are the ones D-095 lists, and the reasons are there. Godot fills
# in the uid and the destination path on the next `--import`.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANIMS="assets/source/anims"
SCRIPT="res://tools/import_clip.gd"
written=0

for fbx in "$ROOT"/$ANIMS/*.fbx; do
    [ -e "$fbx" ] || continue
    import="$fbx.import"
    if [ -e "$import" ] && [ "${1:-}" != "--all" ]; then
        continue
    fi
    rel="$ANIMS/$(basename "$fbx")"
    cat > "$import" <<EOF
[remap]

importer="scene"
importer_version=1
type="PackedScene"

[deps]

source_file="res://$rel"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
mesh_library/use_node_names_as_mesh_names=false
array_mesh/deduplicate_surfaces=true
nodes/apply_root_scale=true
nodes/root_scale=180.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=false
meshes/create_shadow_meshes=false
meshes/light_baking=0
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=false
animation/import_rest_as_RESET=false
import_script/path="$SCRIPT"
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={}
fbx/importer=0
fbx/allow_geometry_helper_nodes=false
fbx/embedded_image_handling=1
fbx/naming_version=2
EOF
    written=$((written + 1))
    echo "wrote $rel.import"
done
echo "clip_imports: $written written"
