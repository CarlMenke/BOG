# Prompt: wear a garment — the Clothes section of the Weapon and Character page

Paste everything below this line to the implementing agent.

---

You are working in the Godot 4.7 project at the repo root (BOG). Read, in this
order, before touching anything: `CLAUDE.md` if present, `docs/SKIN_PIPELINE.md`,
`art/skins/README.md`, `art/skins/shirt/README.md`, `scripts/game/skins.gd`,
`scripts/player/elder_robe.gd`, the `wear_skin` / `set_team_tint` /
`make_tint_material` block of `scripts/player/bog.gd`, the skins section of
`scripts/ui/lobby.gd` (from the `# --- skins ---` divider down), the `skin` and
`team_skins` comments in `scripts/net/net.gd`, `tools/skin_thumbs.gd`, and
D-100, D-108 and D-109 in `docs/DECISIONS.md`.

## What exists

A **skin** is a folder under `art/skins/<name>/` (D-100). Today every pickable
skin is a *recolour*: a `basecolor.png` in the body's UV layout, worn by
`Bog.wear_skin`, listed by index in `Skins.NAMES` (appended to, never
reordered — the index travels on the wire), chosen on the **Weapon and
Character page** the lobby opens from its header (`%CharacterPage`, with
`%WeaponRow` above `%SkinRow`), stored per player on the roster row as `skin`
in free-for-all and per team in `Net.team_skins` in Teams (D-109).

A **garment** is the other kind of skin: a mesh bound to the body's 49
`mixamorig_*` bones. `art/skins/shirt/garment.glb` is the first one made by the
new route — a Tripo mesh fitted by `tools/fit_garment.py` and already committed,
with 49 joints named `mixamorig:*` (Godot imports the colon as an underscore)
and one material. `ElderRobe.don` is the existing proof of how such a mesh is
worn: take the `MeshInstance3D` out of the garment scene, re-parent it under
the Bog's `Skeleton3D`, set `transform = IDENTITY` and `skeleton = ".."`. Nothing
about the body, the rig or the clip library changes.

## What to build

**Clothes are a third pick on the Weapon and Character page**, a section under
the skin section, and a garment is a thing a player wears *over* whichever body
they have.

### 1. `Garments` — the registry (`scripts/game/garments.gd`, new)

`Skins`' sibling and shaped exactly like it: statics only, `NAMES` appended-to
never reordered, `DEFAULT := 0`, `sanitize`, `garment_name`, `label`, `all`,
a cached `scene_of(index) -> PackedScene` (null for the default) and
`thumb_of`. `NAMES := ["none", "shirt"]`. `"none"` is index zero for `bog`'s
reason: an absent key, a cleared dictionary and an old roster row all read as
"wearing nothing". The folder rule: `res://art/skins/<name>/garment.glb` and
`res://art/skins/<name>/thumb.png`.

### 2. The wire (`scripts/net/net.gd`)

One more key on the roster row, `garment`, next to `weapon` and `skin`, and one
more chosen value in `Settings` (`chosen_garment`, saved like `chosen_skin`).
**A garment is the player's own in every mode**, like a weapon and unlike a
skin: in Teams the body colour is the team's identity (D-109) and clothes are
not — two players on one team in different shirts is fine, and a team does not
"hold" a garment. So there is no `team_garments`; `garment_for(peer_id)` reads
the row and only the row. A `_request_garment` RPC mirrors `_request_skin`'s
shape minus the collision rule. Sanitise everything that arrives.

### 3. Wearing it (`scripts/player/bog.gd`)

`Bog.wear_garment(scene: PackedScene)`: free whatever garment mesh is currently
on the skeleton, then if `scene` is non-null don it the way `ElderRobe.don`
does, under a fixed node name (`"Garment"`) so it can be found again. Call it
from every place `wear_skin` is called for a body that has a peer
(`match_state.gd` on spawn, `bog_backdrop.gd` for the lobby's ring and the
page's portrait) with `Garments.scene_of(Net.garment_for(peer_id))`.

Interactions, decided:

- **Team tint.** The garment keeps its own material; it is not the body and
  `set_team_tint` must not touch it. (The tint shader's own comment already says
  the same about the robe.)
- **The Elder's robe.** While a Bog wears the robe, its garment is hidden
  (`visible = false`), and shown again on `doff`. A robe over a shirt is two
  cloth layers fighting; the robe is the outer one and the shirt waits.
- **The corpse.** The ragdoll keeps the garment: whatever `bog_ragdoll.gd`
  does to hand the body mesh to the corpse, do the same for the `Garment`
  node, so a dead Bog in a shirt is still in a shirt. It fades with the body
  (the body's `transparency` path).
- **`Skin` resource.** The imported `garment.glb` arrives with its own
  `Skeleton3D` and a `Skin` whose binds are named `mixamorig_*`; re-parenting
  the `MeshInstance3D` under the Bog's skeleton binds it by those names. Do not
  rebuild the skin by hand. If the mesh does not deform, the first thing to
  check is `skins/use_named_skins=true` on the `.import`.

### 4. The picker (`scripts/ui/lobby.gd`, `scenes/ui/lobby.tscn`)

A **`%ClothesRow`** under `%SkinRow` on `%CharacterPage`: a caption in the same
style as `%SkinCaption` ("YOU · SHIRT") and a row (or short grid) of swatches
built the way `_rebuild_skin_picker` builds skin swatches — same cell, same
picture-through-the-button treatment, same focus and caption behaviour — one
per `Garments.all()`, the first being "none". Picking one calls the request
RPC; `_refresh` redraws it from the roster like everything else on the page
(D-069: view state flows through `_refresh`, never poked directly). The page's
portrait wears the pick immediately on the roster echo, which is the whole
feedback. Do not touch the skin grid's layout beyond making room; D-109 measured
it.

### 5. Thumbs (`tools/skin_thumbs.gd`)

The garment tile is the same photograph as a skin's — head and shoulders over
`Idle` — of the **plain body wearing the garment**, so a shirt tile shows a
shirt on a yellow Bog. Extend the tool so `-- garment shirt` renders
`art/skins/shirt/thumb.png` this way, and give `none` a tile (the plain body,
which already exists as `art/skins/bog/thumb.png`; reuse it rather than
render a second copy). Keep the camera rule: aimed off `mixamorig_Head`, fixed
extent, never a dragged rectangle.

### 6. Proof

- `tools/preview_bog.tscn` gains a trailing `garment=<name>` argument beside
  `skin=<name>`; render `Idle`, `Walk-StandardWalk`, `CrouchIdle`, the dive
  roll and `SwordCombo` with `garment=shirt` and look at them. The Blender
  proof in `art/skins/shirt/README.md` says what to expect: clean everywhere,
  the hem lifting off the belly past ~60° of forward bend, small poke-through
  at the shoulder seam under 15 mm.
- A ragdoll render with the shirt on the corpse.
- The lobby: open the Weapon and Character page, pick the shirt, see it on the
  portrait and on your Bog in the ring; a second client sees it too.
- A check in `tools/smoke_test.sh`, as one contiguous block named `garments`:
  every `Garments.NAMES` entry past zero has a `garment.glb` whose imported
  scene contains exactly one `MeshInstance3D` and whose skin binds all resolve
  on `art/bog/BOG.fbx`'s skeleton (the way `preview_elder` checks the robe),
  and every entry has a `thumb.png`.
- `bash tools/smoke_test.sh` green.

## Working rules

- Somebody else may be working in this repo. Before you start, run
  `git status`; if `scripts/player/bog.gd`, `tools/skin_thumbs.gd`,
  `scripts/ui/lobby.gd` or `scenes/ui/lobby.tscn` show as modified by work
  that is not yours, stop and report rather than editing over it.
- Do not edit `docs/DECISIONS.md`, `docs/STATUS.md`, `docs/PLAN.md` or
  `docs/ARCHITECTURE.md`; return your decision-record text (no number) in your
  report for the integrator.
- The Tripo Bridge addon rewrites `project.godot`'s `last_cleanup` on every
  Godot run: `git checkout project.godot` afterwards unless you changed it on
  purpose.
- New `class_name` scripts need `--import` before headless tools parse them;
  imports are slow, run them in the background with a long timeout.
- One home per concern: the registry in `garments.gd`, the wire in `net.gd`,
  the wearing in `bog.gd`, the view in `lobby.gd` through `_refresh`. Do not
  tack things where they are convenient.
- Numbers are measured, not eyeballed: a render or a headless tool line backs
  every claim in your report.
- Do not commit. Report what you changed, the renders' paths, and the
  decision-record text.
