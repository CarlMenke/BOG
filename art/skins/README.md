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
    roughness.png         its shine, if the download had one (see below)
    emission.png          its glow, if the download had one (see below)
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
(D-108). The first thirteen team skins are exactly that — `bogina`, `boo`,
`clank`, `crag`, `gilt`, `glub`, `gum`, `muck`, `rime`, `roar`, `slag`, `toad`
and `void` — so re-running the script rebuilds them, and the downloads are
untracked source rather than anything the game loads.

### Shine and glow (D-154)

A recolour folder may also hold `roughness.png` and `emission.png`. Tripo ships
a metallic-roughness map with a retexture and can ship an emissive;
`extract_skins.py` writes whichever the `.glb` carried — the roughness as a
grey map, glTF's green channel, and the emissive as it is — and writes nothing
for the ones it did not. **The file being there is the whole of the record**:
`Skins.roughness_of` / `Skins.emission_of` answer `null` for a folder without
them, `Bog.wear_skin` puts whatever there is on both the plain material and the
team-tint shader, and both are no-ops when absent, so every skin that shipped
before this renders exactly as it did. None of the thirteen has either map
today; their downloads predate anybody asking for them.

### A recolour that is not the body's mesh

Tripo does not promise to keep the mesh. The second batch — `bloom`, `buzz`,
`chip`, `crack`, `dash`, `fudge`, `gourd`, `koi`, `ooze`, `volt`, `wrap`
(D-126) — came back *regenerated*: 9 124 vertices in Tripo's own UV layout,
the same creature to the eye and two centimetres off to the ruler. Its texture
cannot be worn as it is; it renders as a patchwork. `tools/bake_skin.py` is the
step for that: it registers the body's vertices onto the download's surface
(the quarter turns tried against the bounding box, similarity and affine ICP
for the whole, then a similarity per bone of the body's rig blended by skin
weight, then a smoothed non-rigid pull, to 1.9 mm) and paints every texel of
the body's layout from the nearest points of the download's paint that face
its way, writing the same `basecolor.png`. `extract_skins.py` takes that route by itself whenever a
download's vertex count is not the body's 15 872. It bakes onto
`build/body_ref.glb`, which is the body as Godot imports it:

    "$GODOT" --headless --path . --script tools/export_body_ref.gd

Baked or extracted, a skin is the same folder with the same three files, and
the game cannot tell them apart. **A player can.** The bake reached 1.9 mm of
fit and eyes that read as eyes, and beside the first batch — whose paint *is*
the body's layout, texel for texel — they are not the same thing: a face
registered onto another face is a face moved millimetres, and millimetres show
in an iris. So the second batch is parked (D-128) until its downloads are
redone the way the first batch's were: a Tripo *retexture* of the original
sculpt that comes back at the body's 15 872 vertices, which `extract_skins.py`
then wears directly. The bake stays as the route for a download that cannot
be redone, with that caveat on it.

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
    muck  rime  roar  slag  toad  void  shirt

Fifteen: the thirteen recolours, **`bog`, the plain body**, which is a skin
called "no texture at all" and is the default, and **`shirt`**, which is the
other way round again -- no paint at all, only clothes (D-163). The second batch —
`bloom`, `buzz`, `chip`, `crack`, `dash`, `fudge`, `gourd`, `koi`, `ooze`,
`volt`, `wrap` — is **parked** in `Skins.PARKED` (D-128): complete folders,
not pickable, for the reason the next section ends on. `art/skins/bog/` is a folder
like the rest and holds a README and a thumb and nothing else;
`Skins.texture_of` answers `null` for it, which is `Bog.wear_skin`'s own word
for "put the imported texture back".

The folders that are **not** pickable are not oversights:

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
and its name appended to `Skins.NAMES` (plus whichever of `roughness.png` and
`emission.png` its download carried). Miss the last and nothing can pick it;
miss the thumb and its tile is an empty square. A **garment** skin swaps the
second for a `garment.glb` (D-163) and is otherwise the same four things --
`shirt/` holds no `basecolor.png` at all.
