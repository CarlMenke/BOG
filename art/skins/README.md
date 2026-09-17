# art/skins — a skin is a folder

A skin is anything worn on the BOG's own body and skeleton (D-099, design
item 11): it inherits every clip in `art/generated/bog_clips.res` without
touching them, because it rides the same 49 `mixamorig_*` bones the clips
drive. Two kinds, one folder each:

```
art/skins/<name>/
    README.md            what it is and how it was made
    *.png                 its textures, with the .import Godot writes
    robe.res / robe.tscn  a clothing mesh (see below), or
    basecolor.png         a recolour (see below)
```

## A recolour

A texture in the body's UV layout, swapped in through the team-tint path:
`Bog.set_team_tint` builds a `ShaderMaterial` from the body's imported
material (`resources/shaders/bog_team_tint.gdshader`) and the base colour
texture is one of its inputs. `art/skins/example/` is the worked example
(D-100): the body's own texture, re-hued, dropped in place.

A recolour can also arrive from outside. Send the sculpt through Tripo with a
retexture prompt that asks for the structure to stay put and what comes back
is the same mesh in the same UV layout wearing a different paint job — a
recolour by another route. `python tools/extract_skins.py` is the step between
the download and the skin: it reads the `.glb` in
`assets/source/skins/<NAME>/`, pulls the base-colour image out of the
container, downsamples it to 2048² and writes `art/skins/<name>/basecolor.png`
(D-108). The thirteen team skins are exactly that — `bogina`, `boo`, `clank`,
`crag`, `gilt`, `glub`, `gum`, `muck`, `rime`, `roar`, `slag`, `toad` and
`void` — so re-running the script rebuilds all thirteen, and the downloads are
untracked source rather than anything the game loads.

## A clothing mesh

A mesh bound to the body's skeleton **by bone name**, with its own `Skin`
whose binds are the inverse of the body's rest pose, so it lands where it
was modelled while the body stands and follows the bones when it moves.
`ElderRobe.don` takes the `MeshInstance3D` out of the skin's scene and
re-parents it under the BOG's `Skeleton3D`; `tools/preview_elder.tscn`
proves the bind and renders it.

`art/skins/elder/` is the worked example: `tools/refit_robe.gd` took the robe
geometry the old Blender build fitted to this sculpt, scaled it to the new
body's height, and gave every vertex fresh weights against the new skeleton's
rest pose (the spine chain blended by height, a thigh share toward the hem,
the hat rigid to the head). A new piece of clothing needs the same three
things: geometry that fits the sculpt, weights against `art/bog/BOG.fbx`'s
rest pose, and a `Skin` with binds named after the bones. A mesh that arrives
already skinned to a Mixamo rig (its bones are `mixamorig:*`, the colon
becomes an underscore on import) binds without any of that.
