# Prompt: rebuild the BOG's animation pipeline from the new source

You are taking over a Godot 4.7 multiplayer game, BOG, at the point where its
character animation setup is being rebuilt from scratch. The source material has
been fetched and verified; nothing has been implemented against it yet. Your job
is to plan and implement the whole replacement, end to end, and retire the old
setup once the new one runs. Read this file completely before touching anything.

## Who you are working with

The owner, Carl, is not a game developer. He built this project by "messing
around" and is now using it to learn. He wants a result that feels like a
professionally animated game and he wants the setup behind it to be clean enough
that adding a clip or a skin later is a one-file job. He is not attached to any
existing clip, timing, or tool. He will judge results **visually**, in previews
or in play, and he will veto what reads wrong.

Rules for working with him, learned the hard way on this repo:

- **Decide measurements yourself.** Which of two clips blends better, what a
  playback rate should be, what a release time is: those are yours. State the
  choice in one line with the reason. Do not hand him two numbers and ask him
  to pick.
- **Ask only design questions**, the ones that change what the game *is*. Should
  the bow out-range the Elder. Is the great sword a one-shot. Batch those and
  ask them at natural checkpoints, not one at a time.
- **When a judgement is visual, show it, do not describe it.** Render the
  candidates in a preview scene and let him look. `tools/preview_*.tscn` and
  `tools/capture_preview.gd` are the existing pattern for this.
- Report honestly. If a gate fails, say so with the output. If something was
  skipped, say that.

## What the game needs from its character

One player character, the BOG, seen in third person, on a small island, in
teams. It idles, walks, runs, strafes, backs up, crouches and crouch-walks,
jumps, double-jumps into a dive and roll, slides, throws a spear, draws and
looses a bow, swings a great sword, casts as the Elder, drinks a potion, picks
up and carries letters, takes hits, and dies into a ragdoll. Skins for now mean
**recolours and clothing on this same body and skeleton**. Other meshes with
similar proportions may come much later; keep the door open but do not build
for it.

Everything about the current animation *feel* is considered slop by the owner:
foot skating, timing constants that were typed in by hand, grips that were
argued from screenshots, a ragdoll built from a table, a robe fitted to a body
that no longer exists. The rebuild is the opportunity to do every one of those
properly. Best practices are expected, not optional.

## What exists today, and why it is being replaced

Three layers stacked over time, each a workaround for the one before:

1. **`tools/build_bog.py`** (3300 lines, Blender 5.2 headless) merges packs of
   Mixamo FBX files from `assets/source/` into one `art/generated/bog.glb`
   with every clip inside. It strips the `mixamorig:` prefix, scales to 1.80 m,
   locks root motion while measuring authored speed, mirrors a strafe, aligns
   facing, synthesises a crouch idle, checks the floor, and exports.
2. **A weight transfer** (D-077 in `docs/DECISIONS.md`): the BOG sculpt was a
   static Tripo mesh, so it borrowed the old Gub's skin weights face by face
   and rides the Gub's Mixamo skeleton. This is the source of the belly crease
   in Run and the bottle entering the head in Drink.
3. **`scripts/player/bog_animator.gd`** (1900 lines) builds an
   `AnimationNodeBlendTree` in code with blend spaces for locomotion, OneShots
   for actions, and a scrubbed airborne pose. It is in decent shape
   structurally, but every event time (`THROW_RELEASE_IN_CLIP 1.567` and about
   thirty more) is a constant measured against the old clips.

Also downstream of the old skeleton and clips: `scripts/items/held_gear.gd`
(grip offsets per weapon, all hand-measured), `scripts/player/ragdoll_builder.gd`
(13 segments with hand-set girths), `scripts/player/bog_aim.gd` (spine aim
shares), `tools/build_elder.py` and `scripts/player/elder_robe.gd` (the Elder's
robe is a second skinned mesh on the same skeleton), and the per-clip speeds in
`scripts/player/bog.gd`. The survey of every bone-naming script is in D-077's
neighbourhood and in `docs/ARCHITECTURE.md`; re-survey with grep before you
change bone names.

None of it is to be deleted until the new path runs in the game. The game keeps
working the whole way through.

## The new source of truth

`assets/source_reorg/` — read its `README.md` first.

- `BOG.fbx`: the sculpt as **Mixamo auto-rigged it**, one T-pose with skin.
  49 `mixamorig` bones, one skinned mesh of 15 872 vertices, one 4096²
  texture, one `mixamo_com` animation that is the T-pose.
- `anims/`: **104 animation-only FBX files**, one per clip, fetched on that
  rig. Names are `<Role>-<MixamoName>[-n].fbx`. Several files per role are
  candidates; one gets chosen per role, the rest deleted.
- `clips.json`: the table those files came from. Role, Mixamo id, file name,
  provisional loop flag. Adding a clip later is one row plus a re-run of
  `tools/mixamo_fetch.py`, which generates a browser console script the owner
  pastes into the Mixamo tab.
- `anims/VERIFIED.md`: per-clip length, hips travel and hips bob, measured in
  Godot. Travel over length is the authored speed of a cycle.

### Verified facts, do not re-derive

Verified in a scratch Godot 4.7.2 project on 2026-09-16:

- Godot imports these FBX files natively. Every clip's skeleton is the body's
  skeleton, bone for bone. A clip's animation added to the body's
  `AnimationPlayer` puts every bone within 0.1 mm of where the clip's own
  skeleton puts it. **Retargeting by bone name is exact for the BOG. No bone
  map is required for the BOG itself.**
- The files are in Mixamo's centimetre scale. At the default importer scale the
  body is 1 cm tall and the importer's animation optimizer collapses every hips
  position track to a single key, which silently deletes the bob. Set
  `nodes/root_scale` on every file; at 100 the body is 1.00 unit tall and all
  keys survive. Pick the final height once and apply the same scale to the body
  and every clip. Verified with `animation/remove_immutable_tracks = false`.
- Godot turns the colon in `mixamorig:Hips` into `mixamorig_Hips`.
- Clips were fetched **with their travel** on purpose. Strip it at import,
  after recording it. Do not use Mixamo's in-place export.
- Mixamo's own "Sliding" product exports as a single frame; the slide is
  "Running To Slide And Back To Running".

## The agreed design

This is what the owner signed off on. Implement it; do not reopen it.

1. **No Blender in the loop.** The FBX files are imported by Godot directly.
   `tools/build_bog.py`, `tools/build_elder.py` and `assets/source/` are
   retired at the end.
2. **Clips live apart from the body.** The body is one imported scene; the clips
   become a shared animation library applied to the body's skeleton. A skin is
   a texture swap or a clothing mesh bound to this same skeleton, and it
   inherits every clip without touching them.
3. **One small, declarative import layer** replaces the 3300 lines: a table of
   clip rules (one line per chosen clip: loop or not, event markers, rate hints)
   and a short post-import script that, for each clip, records the authored
   speed from the hips travel, locks the horizontal hips motion, sets the loop
   mode, and writes the event markers. Godot 4.3+ animation markers are the
   intended mechanism. Keep it near a hundred lines, not a thousand.
4. **Events live on the clip, not in the animator.** Spear release, arrow
   loose, cast, sword hit window, footsteps, landing impact: markers on the
   animation, placed once per chosen clip, read by the animator at runtime.
   Changing a clip must never mean re-measuring the animator.
5. **One cohesive clip family.** Choose locomotion, jumps and crouch from one
   consistent set so posture does not pop between them, and choose weapon sets
   that match that posture. The great sword set has its own walk, run and
   strafes; use them while the sword is drawn. The bow set has aiming walks and
   strafes; use them while aiming.
6. **Locomotion is an eight-way blend with matched cycles.** Walk and run cycles
   get their stride phase aligned so a blend between them does not cross-fade
   two feet in different places. Playback rate follows game speed divided by
   authored speed so feet plant. Keep the existing rule of thumb: ground poses
   from speed, air poses from the arc, actions are one-shots.
7. **Jumps are three pieces**: take-off, airborne loop, landing, driven by the
   physics body's state, with a light and a hard landing. The double-jump dive
   and roll use the roll candidates.
8. **Grips are set once, visually.** A tool shows the hand and the prop in the
   editor or a preview scene and saves the offset. No numbers argued from
   screenshots.
9. **The ragdoll derives from the rig.** Segment lengths from the skeleton,
   girths from the mesh, so a rig change re-derives them.
10. **The Elder's robe is refit** to the new body as a clothing mesh on the same
    skeleton, which also makes it the first worked example of a skin.
11. **A skin is a folder.** Recolour: a texture through the existing team-tint
    shader path. Clothing: a mesh bound to the skeleton, dropped in place.

Not in scope, deliberately: foot IK on slopes, motion matching, hand IK on the
bow string, per-bone physics on clothing. They are a second project.

## Order of work

Work in this order. Each step ends with something the owner can look at.

1. **Import layer.** Decide the final scale, import the body and all 104 clips
   with the right settings, build the shared library, prove a clip plays on the
   body inside the real project (not the scratch one). Commit.
2. **Clip choice.** For every role with more than one candidate, render the
   candidates side by side in a preview scene and pick, using the family rule
   above. Where the pick is a pure taste call, show the owner and let him veto.
   Delete the unchosen files and their rows. Commit the choice as a decision.
3. **Clip table and markers.** Write the rule table for the chosen clips and
   the post-import script. Place every event marker by looking at the clip, not
   by guessing. Commit.
4. **Animator.** Rebuild `bog_animator.gd` around the library and the markers.
   Keep its structure where it is sound; delete every hardcoded clip time.
   Locomotion, crouch, jumps, actions, carry poses, weapon locomotion. Get the
   smoke test green at each sub-step. Commit.
5. **Grips, aim, ragdoll, robe.** In that order, each with its preview.
6. **Skins.** One recolour and one clothing piece as the worked example, and a
   short README on how to add the next one.
7. **Retire the old path.** Delete `tools/build_bog.py`, `tools/build_elder.py`,
   `assets/source/`, `art/generated/bog.glb` and `elder.glb` and every script
   that only served them. Move `assets/source_reorg/` to `assets/source/`.
   Update `docs/ARCHITECTURE.md`, `docs/STATUS.md`, `docs/PLAN.md`.

Do not start a later step before the earlier one is green. Do not skip the
previews; they are how the owner participates.

## Repo conventions you must keep

- **`docs/DECISIONS.md`** is the decision log: numbered `D-0xx` entries, each
  explaining what was decided, what was rejected and why, with the measurements.
  The last entry is D-089. Every design choice you make above the level of a
  variable name gets an entry. Read D-029 (the current animator), D-063
  (the throw release), D-066 (the locomotion plane), D-071 (the strafe mirror),
  D-074/D-075 (grips), D-077 (the body swap) before you touch the things they
  describe.
- **`docs/STATUS.md`** is the resume point; update it when a step lands.
- **`bash tools/smoke_test.sh`** is the gate, 134 checks, about six minutes.
  It must pass before every commit that touches gameplay or a re-import.
  `bash tools/net_test.sh` after anything that touches networking.
- `tools/find_godot.sh` locates the Godot 4.7 console binary; source it, do not
  hardcode a path. Run Godot headless for anything automated.
- `assets/` is `.gdignore`d and raw; `art/generated/` is what the game loads.
  Keep that split.
- Commit small and often, with messages that say why. Do not push without the
  owner asking.
- Do not reconnect the Blender MCP or run Blender; it is not part of this
  pipeline any more.

## Starting point

`main` at commit `0060526`, "Start the BOG animation pipeline over". The
working tree is clean. Begin with step 1.
