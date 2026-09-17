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
    thumb.png             the picker's 128² tile, if it is a skin a player picks
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

## Which skins a player can pick

Not all of them, and the list is not this directory. `scripts/game/skins.gd`
(`Skins.NAMES`) is the pickable set, in the order the lobby's strip shows it:

    bog  bogina  boo  clank  crag  gilt  glub  gum
    muck  rime  roar  slag  toad  void

Fourteen: the thirteen recolours plus **`bog`, the plain body**, which is a
skin called "no texture at all" and is the default. `art/skins/bog/` is a folder
like the rest and holds a README and a thumb and nothing else;
`Skins.texture_of` answers `null` for it, which is `Bog.wear_skin`'s own word
for "put the imported texture back".

The two folders that are **not** pickable are not oversights:

- `example/` is D-100's worked example of *how a recolour is made*, not a skin
  anyone wears.
- `elder/` is a garment, and it is worn by being the Elder (D-038). A robe is
  not a body, and the picker is a strip of bodies.

`NAMES` is **appended to, never reordered**: the index is what travels on the
wire, sits in a roster row and sits in `Net.team_skins`, so moving a name would
silently put one player — or one whole team — in somebody else's body.

## Every skin has a thumb

    art/skins/<name>/thumb.png    128², head and shoulders, over `Idle`

The tile the lobby's picker draws. Rendered, never painted, and reproducible:

    "$GODOT" --path . --resolution 512x512 --script tools/skin_thumbs.gd
    "$GODOT" --path . --resolution 512x512 --script tools/skin_thumbs.gd -- muck
    "$GODOT" --headless --path . --import          # then let Godot see them

`tools/skin_thumbs.gd` stands one BOG in `Idle`, asks the skeleton where
`mixamorig_Head` is, puts an orthographic camera in front of it with a fixed
extent in metres and photographs the body once per skin — so the crop is the
camera rather than a rectangle somebody dragged, every tile is framed
identically by construction, and a re-rig re-aims it instead of going stale.
Not a step in `tools/extract_skins.py`: that is Python and Pillow and never
opens Godot, and a thumb is a *render* through the game's own importer,
material and lights. Run `extract_skins.py` when a download changes, and this
when the picker's look does.

**A new skin is four things**: the folder, its `basecolor.png`, its `thumb.png`,
and its name appended to `Skins.NAMES`. Miss the last and nothing can pick it;
miss the thumb and its tile is an empty square.
