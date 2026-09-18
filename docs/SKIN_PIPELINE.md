# Skin pipeline: image AI → Tripo → the BOG's own skeleton

How a new look gets onto the BOG without touching the body, the rig or the
clip library. Two kinds of skin (D-100): a **recolour** (a texture in the
body's UV layout) and a **garment** (a mesh bound to the body's bones). Most
of the list below is a recolour; a few want a garment on top.

Every prompt takes **one reference image**: the original front-on BOG picture
that the thirteen retextures were made from (call it `bog_front.png` below).
Same image every time, so every outfit is drawn on the same body.

---

## Route 1 — Recolour (texture only)

The pipeline that already exists (D-108). Nothing new to build.

**Step 1. Tripo → Retexture** on the BOG sculpt, with this prompt (fill the
bracket from the table at the bottom):

> Retexture only. Keep the mesh, the silhouette and the UV layout exactly as
> they are; change nothing about the shape. Paint the whole body as
> **[MATERIAL]**. Keep the eyes readable: white eyeballs, dark pupils. Matte
> stylised game look, no text, no logos.

Download with the texture embedded → `assets/source/skins/<NAME>/<NAME>.glb`.

**Step 2.** `python tools/extract_skins.py` → `art/skins/<name>/basecolor.png`.

**Step 3.** Append `<name>` to `Skins.NAMES` in `scripts/game/skins.gd`
(append only, never reorder — the index goes on the wire).

**Step 4.** Thumb: `"$GODOT" --path . --resolution 512x512 --script tools/skin_thumbs.gd -- <name>`

**Step 5.** Proof render: `preview_bog.tscn ... skin=<name>` over `Idle`
against `example`. Eyes are eyes, markings where the sculpt puts them.

---

## Route 2 — Accessory (one rigid piece on one bone)

For a pumpkin head, a petal ring, a tag, a visor: an object that sits on
**one** bone and never bends. No segmentation, no weight painting.

**Step 1. Image AI**, reference `bog_front.png` attached so the style matches:

> Match the art style, materials and lighting of the attached character, but do
> **not** draw the character. Draw only a single **[OBJECT]** as a standalone
> prop, centred, three-quarter front view, floating, plain flat light-grey
> background, soft even studio light, no shadow on the ground, no text.
> Stylised matte 3D-render look, clean edges, one object only.

Optional: ask the same again "seen from directly behind" for a second view.

**Step 2. Tripo → Image to 3D** with that image. Latest model, PBR texture on.
Download `.glb` → `assets/source/skins/<NAME>/<NAME>_part.glb`.

**Step 3. Fit (Blender, headless — to be built once, `tools/fit_garment.py`):**
import `art/bog/BOG.fbx` and the part, scale the part to a stated size in
metres, place it against the named bone (`mixamorig_Head`, `_Spine2`,
`_Hips`…), assign every vertex weight 1.0 to that bone, export `garment.glb`.

**Step 4. Wear** — see *Godot side* below.

---

## Route 3 — Fitted clothes (jacket, wraps, robe, armour)

Clothes that follow more than one bone. The body is generated *inside* the
clothes so they fit it, then cut back out.

**Step 1. Image AI — dressed BOG, front.** Reference `bog_front.png` attached:

> Use the attached character exactly as it is: same body shape and
> proportions, same face, same pose (arms straight out, T-pose), same camera
> (straight-on front view, full body, feet visible), centred, plain flat
> light-grey background, soft even studio lighting, no shadows on the
> background, no ground plane. Dress the character in **[OUTFIT]**. The
> clothes sit on top of the body and follow its shape; do not change the body
> underneath, do not change the pose, no weapon, no props, no text. Clean
> stylised matte 3D-render look.

**Step 1b (optional, better mesh).** Same prompt twice more, changing only
the camera line, and attaching the *front result* as the reference this time
so the outfit stays consistent:

> …same character, same outfit, same lighting and background, now seen from
> the **left side** / from **directly behind**, T-pose, full body…

If the side and back drift from the front (different details, different
colours), throw them away and use the front alone. One good view beats three
that disagree.

**Step 2. Tripo → Image to 3D** (or *Multi-view* if you kept the extra
views). Latest model, PBR texture on, T/A-pose option **on** if it is
offered, face count on the high side so the cut in step 3 is clean.
Download `.glb` → `assets/source/skins/<NAME>/<NAME>_dressed.glb`.

**Step 3. Cut the body out.** First choice: Tripo's part segmentation on the
result, keep the clothing parts, delete the body parts, download. Fallback:
the fit script does it — align the dressed mesh over `BOG.fbx` and delete
every face within a few millimetres of the body's surface.

**Step 4. Fit + weights (Blender, headless, `tools/fit_garment.py`):**
scale to the body's height, align hips and head, push any clothing vertex
that sits inside the body to just outside the surface, then **Data Transfer**
vertex groups from the BOG body (nearest-face interpolated), parent to the
Mixamo armature, export `garment.glb`. Bone names come out `mixamorig:*`,
which Godot reads as `mixamorig_*` and binds by name with no refit.

**Step 5. Wear** — below.

---

## Godot side (to be built once, then free)

- A skin folder may hold `garment.glb` beside (or instead of) `basecolor.png`.
- `Skins` gains `garment_of(skin)`; `Bog.wear_skin` dons it the way
  `ElderRobe.don` does: re-parent the mesh under `Skeleton3D`, `skeleton = ".."`.
- `tools/skin_thumbs.gd` dons the garment before photographing.
- The corpse keeps the garment on the ragdoll.
- Team tint: garment material gets the same tint shader or its own colour.
- Proof: `preview_bog.tscn` over `Idle`, `Walk`, `Crouch`, `DiveRoll`,
  `SwordSpin` — look for the body poking through.

---

## The list

| # | name | route | [MATERIAL] for the retexture | [OBJECT] / [OUTFIT] for the garment |
|---|---|---|---|---|
| 13 | BUZZ | recolour | golden honeycomb: hexagonal wax cells, some filled with glossy amber honey, drips at the edges | — |
| 14 | CHIP | recolour | white glazed porcelain with fine blue floral pattern, hairline cracks, thin gold kintsugi seams, glossy | — |
| 15 | OOZE | recolour | translucent toxic green slime, darker green depths, bubbles under the surface, dripping edges | — |
| 16 | DASH | recolour | cheetah fur: tawny gold with black rosette spots, white belly, dark tear-lines from the eyes | — |
| 17 | GOURD | recolour + accessory | ridged orange pumpkin skin, deeper orange in the grooves, a hint of green near the top | OBJECT: a carved jack-o-lantern head with a triangle-eyed grinning face lit from inside, short brown stem on top |
| 18 | FUDGE | recolour | dark chocolate: glossy segmented bar pattern on the chest and back, melted drips on the limbs | — |
| 19 | VOLT | recolour (+ optional accessory) | matte black cyberpunk suit with glowing cyan and magenta circuit lines, neon seams along the limbs | OBJECT: a slim glowing cyan visor that wraps around the eyes |
| 20 | BLOOM | recolour + accessory | sunflower: dark brown seed-head pattern on the face and chest, green stem-like limbs with leaf veins | OBJECT: a ring of bright yellow sunflower petals with two green leaves, shaped to sit around a head |
| 21 | KOI | recolour | koi fish: pearly white scales with orange and black patches, fine scale pattern, slightly glossy | — |
| 22 | WRAP | recolour + fitted clothes | aged linen bandages wound tightly around the whole body, yellowed, frayed edges, gaps showing dark skin | OUTFIT: loose mummy bandages, several strips hanging free from the arms, torso and head, frayed ends |
| 23 | PLUSH | recolour + accessory | soft plush toy fabric, visible stitched seams down the middle and along the limbs, fuzzy texture, button eyes | OBJECT: a small white fabric care-tag sewn on, folded slightly |
| 24 | CRACK | recolour | dark storm cloud grey with billowing cloud shapes, bright branching lightning bolts glowing white-blue | — |

Proving piece for Route 3: **the wizard.** OUTFIT: *a long purple wizard robe
with wide sleeves and a tall pointed purple hat with a floppy tip*. It already
exists as `art/skins/elder/` (Blender-built), so the Tripo one can be judged
side by side and the fit script tuned on it before any of the list runs.

---

## Cheap win for every recolour

`tools/extract_skins.py` only reads `baseColorTexture`; the tint shader only
takes albedo. Tripo also ships a metallic-roughness map (and can ship
emissive). Extracting those and giving `bog_team_tint.gdshader` optional
roughness and emission textures is what makes CHIP gloss, OOZE wet and VOLT
and CRACK glow. Small change, applies to all twelve.
