# GUB_2 — the body of record

Eight Mixamo FBX files: **the Gub as uploaded to Mixamo**, exported once per
animation. Idle, Walking, Run, CrouchWalking, Slide, JumpOne, JumpTwo, Throw.

Seven of the eight are declared. `Throw.fbx` is not, since D-063: the throw the
game plays now comes from `2_Spear_Suite/SpearThrowLonger.fbx` under the same
clip name, because this one's release frame looked like every frame around it
and the complaint was that nobody could see the spear leave. The file stays here
— a clip we decided against and a clip we threw away are different states, and
only one of them is reversible — and putting it back is one `Clip(...)` line in
`PACKS`, spelled out in the comment where it used to be.

**Do not move or rename anything in here.** `tools/build_gub.py` names these
files in `PACKS`, and everything else in `assets/source/` is measured against
`GUB_2/Idle.fbx` — same 8814 vertices, same 49 `mixamorig:` bones, same 40
vertex groups, bind poses agreeing to 1e-5. That comparison
(`assert_same_character`) is what makes it legitimate to land clips from six
different folders on one skeleton, and this pack is the thing it compares to.

Every file carries a full copy of the mesh and a 2048² base-colour JPEG, which
is why each one is about 2 MB. That duplication is the point: it is what proves
the clips are talking about the same body.

## Adding a clip here

Almost certainly you want a new pack instead — `2_Spear_Suite/` and its
neighbours exist so a suite downloaded in one sitting stays one thing on disk.
This folder is the eight clips the game shipped with, and keeping it that way
keeps "is this still the same Gub?" a question with an obvious answer — which is
also why the retired `Throw.fbx` is still sitting in it.

## Rebuild

    bash tools/build_gub.sh                 # writes art/generated/gub.glb
    bash tools/build_gub.sh -- --list-packs  # audit the folders, build nothing

Three consecutive runs produce a byte-identical GLB (D-029), so "rebuild it and
see" is a real answer to a question.
