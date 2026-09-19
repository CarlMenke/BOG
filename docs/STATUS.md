# Where this is up to

Resume point for BOG. Read this first, then `docs/ARCHITECTURE.md` (how it fits
together), `docs/PLAN.md` (the full task list, with checkboxes) and
`docs/DECISIONS.md` (why things are the way they are).

Last updated: 2026-09-19. What comes next is in Linear (workspace BOG), not
here: see `CLAUDE.md`.

---

## The short version

Everything is on **`main`** and there are no other branches. What `main` now
carries is the consolidation of **two independent integrations of the same two
feature branches**, done in parallel without either knowing about the other.
Both merged `feat/island` and `feat/ui`; both then went looking for what the
merge had broken, and they found overlapping but different sets of it.
Everything from both is here.

The game runs from the main menu through a lobby into a real match on a real
island and out to a results screen, and two automated checks now walk that path:
one in a single process, one across two processes over a real socket.

```
bash tools/smoke_test.sh        # 205 checks, ~10 minutes, all green; finds Godot by itself
bash tools/net_test.sh          # two processes, one socket; ~100 s, run by hand
```

`smoke_test.sh` is the gate; it is at **205 of 205** (D-148..D-166, 2026-09-19). `net_test.sh` is kept out
of it to keep the gate fast; run it by hand after touching networking, the lobby
or the results screen. It passes all thirteen stages (263 + 53 assertions; stage 12 walks a peer out of a running match and back into it as a spectator, D-164; stage 4 carries the Teams skin rules over the socket, and stage 9's hit, a headshot since D-130, is at `body_centre()` now, D-155), ten of
which end in a rematch, with the engine quiet in both processes — the error it
had reported at "match start" since D-022 was its own teardown. Rematch was
stalling for 25 s whenever a client had pressed BACK TO LOBBY; D-044 is the fix
and the measurement. Stage 4 is the weapon pick crossing the socket (D-069),
which is the one place it can be proved: every other harness drives it in an
offline session, where `rpc_id` reaches nobody and the local call does the work.

**Both binaries build**, which had never been done before: `build/windows/BOG.exe`
and a universal `build/macos/BOG.app` that boots clean. See the README.

**The game is called BOG** (**D-081**). The GUB branding was swept out of every
tracked file in one pass — 4,282 replacements across 137 files, plus twenty-four
`git mv`s, so the character is `scripts/player/bog.gd`, the asset was
`art/generated/bog.glb` (now `art/bog/BOG.fbx`, D-101) and the build is `build/windows/BOG.exe`. Five things
keep the old spelling on purpose and the entry says why each: Godot `uid://`
strings, the `assets/source/GUB_2/` pack folder, playit's `angry-gub.at.ply.gg`,
and two sentences quoting the user. (The `CarlMenke/Gubs_Game` repo URL was on
this list until 2026-09-17, when the repo and folder were renamed to `BOG`.)

The whole of it is merged to `main` and tagged **`v0.1.0`**, so Phase 7 is closed
out. The one networking feature that was outstanding — hosting across the
internet without every player installing Tailscale — is done (D-028) and needs a
real tunnel and a real second machine to confirm. What is left below is
play-testing, not build or release work.

### Where the work is right now — the letters round

**One letters game, and everything around it**, argued out with the owner on
2026-09-18 and built by six Opus agents in parallel against
`docs/PLAN_LETTERS.md`, then integrated and gated in one pass. Landed as
**D-129..D-134**; `docs/PLAN.md` Phase 11 carries the item state.

- **The core truth** (**D-129**). Free-for-all is the collect race, Teams is
  capture-the-flag, and the Match type switch is the only thing that picks: the
  "Ends on" picker offers one **B·O·G** entry and `_clamp_all` turns `LETTERS`
  into `CAPTURE` under Teams and back. In the race **one letter is alive at a
  time** — every death deals the next letter, B then O then G, when none is out
  or being captured — and `letter_drop_chance` is gone. The hold row carries its
  own clock (`started_at`, `seconds`), and `letter_hold_is_timed` is the one
  question that tells a capture from a carry.
- **The guide line** (**D-130**). `scripts/world/nav/`: a navmesh baked per
  client per map from layer-1 colliders (588–1019 polygons, 83–285 ms, on every
  map), jump and drop links from `JumpArc` (lifted out of `parkour_report`, whose
  numbers did not move), and a two-pass dashed ribbon — gold to a loose card, red
  to an enemy carrier, blue to a teammate or your own vault — trunk-merged in
  Capture, fading under 2 m of path and back above 3. Local and cosmetic; nothing
  replicates. `tools/nav_check.tscn` bakes every map in the gate and walks a
  route pad to pad. **The one bug the gate caught**: since 4.4 the server builds
  a map's iteration asynchronously, and on every map the first path was asked a
  frame before the iteration with the polygons landed; `NavBake` now runs its
  map with synchronous iterations and forces the sync. **Known and left**: the
  link generator is conservative — the quarry's 1.2 m kerbs produce no links,
  so the line routes around a step a player would hop.
- **The capture performance** (**D-131**). A timed hold is no longer a card in
  a fist: `HeldGear.set_pouch` hangs a procedural wool pouch in the left hand,
  `BogAnimator`'s `capture` layer raises the arm (the `Capture` role, drawn with
  `CastIdle` until a take is fetched — searches to try: *reaching up*, *hold
  torch*, *victory idle*, *praying*), and `CaptureRig` floats the letter from
  above the hand down into the pouch mouth over the hold, 1.6× → 0.25×, with a
  fourteen-ray `Sunburst` and `letter_captured.wav` when it lands. The steal is
  the same rig in reverse. A Capture carry keeps the card in the fist.
  `tools/preview_capture.tscn -- f=0.5` prints both anchors; the pouch grip
  constants were written down, not solved, and want a render.
- **The minimap and the tutorial** (**D-132**). A heading-up circle top-right,
  on under B·O·G only, the navmesh outline as its ground, teammates, loose
  letters and carriers — never an enemy without a letter. Six drawn, looping
  tutorial cards behind HOW TO PLAY on the menu, opened once per machine on the
  first B·O·G lobby (`Settings.tutorial_seen`). The lamp says CAPTURING.
- **The menu's wordmark stands in the glade** (**D-133**). Three real letters
  over the fire, bobbing and swaying, kerned off their meshes; the hero Bog
  beside the fire; one rig at one size for the menu (5.7 m / 24°) and the lobby
  (9.95 m / 36°); the letters dip and launch out of frame on Start before the
  fade. `HOVER_HEIGHT` is 1.35 and not the planned 1.55, because the lobby's
  camera is pitched down at a ring standing *behind* the fire and raising the
  row walks it into the faces. `ui_range menu_letters` / `lobby_letters` print
  the boxes and fail on overlap.
- **Finger grips** (**D-134**). Five one-frame poses measured out of the clip
  library (`tools/grip_poses.tscn`, committed as `art/generated/grip_poses.res`;
  the fists sit 41–44° off the open hand, so the takes do animate the mitten)
  on two filtered blends over the emote. A scene tool and not a `--script`,
  because the animator's dependency chain names the autoloads.

**What the single gate run found**, in order: the grip tool could not compile
`BogAnimator` under `--script` (fixed by asking `Bog.is_capturing()` and making
the tool a scene); three fingertip leaf bones have no track in any clip (the
tool skips them, nine joints a hand); the lobby ring was already outside the
panel band from the commit before this round (`ring_radius` 3.0 → 3.5, never
re-measured); a duplicate-card harness measured its feed before the card's own
"appeared" row; and the navigation race above; and, on the fourth run, a type inference off
a *new* member of a class in a reference cycle (`Bog.is_capturing`,
`Bog.capture_rig`) failing on a cold cache — which took `preview_capture`'s
own script down and hung the gate, so `check()` now runs every tool under a
wall clock and the locals are typed by hand. Everything else — 185 checks
including every new one — passed first time.

**And a second wave the same evening, off the first build** (**D-135..D-137**):
the range by day — fences, lantern spheres and the shootable orbs gone, the sun
at 32°, renamed **Highsun Grounds**, and the rule that nothing in the world is
a bare unshaded primitive; a moon over the viewer's shoulder in the menu and
the lobby at a *measured* third of the fire (`MOON_ENERGY 0.45`), the hero a
step right and back, and the lobby camera 18% further out so the 3.5 m ring
sits inside the panel band again; and rebindable controls in Settings, saved as
the difference from the project's defaults.

**And the lobby ring stands in two rows** (**D-139**): alternate slots 0.35 m
inside and 0.65 m outside the 3.5 m arc, each Bog's angle solved so the eight
stay evenly spaced on the screen and the ends stay where the band check put
them (435 .. 1123 of 400 .. 1140), so a full lobby reads as a group rather than
a queue without a Bog going behind a panel.

**And the campfire under the wordmark is a model now** (**D-138**). The owner
found one he wanted in his downloads, so `BogBackdrop._build_fire` no longer
builds a fire out of five boxes and two cones: `assets/source/props/CAMPFIRE.glb`
goes through `tools/decimate_assets.py` at the shield's 10000 triangles and 1024
textures and is placed at `FIRE_MODEL_SCALE` 0.88 and `FIRE_YAW_DEGREES` 212,
with the `OmniLight3D`, the flicker and `HOVER_HEIGHT` untouched. A Tripo
download emits nothing, so the pipeline manufactures the glow rather than a
menu script overriding the material: `tools/flame_glow.py` cuts the saturated
red-to-yellow 15.8% of the base colour into an emission texture at strength 2.6,
over the environment's 1.45 glow threshold. **To rebuild it:** `python
tools/decimate_assets.py campfire`, then `ROOT="$PWD" GODOT_TAG=fire .
tools/find_godot.sh` and `"$GODOT" --headless --path . --import` — the
`.import` file and the extracted `art/generated/campfire_*.png` are committed,
and the import has to be re-run after every rebuild of the GLB. The gate ended
**191 checks, 0 failures**.

**Nobody has played any of this.** Same sentence as the two rounds before.

### Previously — the feel round

**Thirteen pieces of playtest feedback**, grouped by the code they touch into
six units, implemented in parallel and landed as **D-119..D-124**.
`docs/PLAN_FEEL.md` is the spec they were argued against and `docs/PLAN.md`
Phase 10 carries the item-by-item state. What each unit landed:

- **The range at sunset** (**D-119**). Glowworm Grounds moved an hour earlier:
  `resources/shaders/range_sky.gdshader`, a third fork of Kopje's cumulus, under
  a sun 9° up on a bearing 30° east of north so 50 m of bank shadow falls off the
  map instead of across it; `ambient_light_energy` 8.0 → 0.62 with a shadowless
  `LIGHT_ONLY` `Bounce` from below the southern horizon. The lane fences are one
  0.60 m rail instead of eight lines of 1.8 m timber, and **the six stations are
  gone** — a zone's behaviour is authored in the map's tables and never changes,
  all twenty-seven dummies stand up, and the only thing left to walk into is a
  timber signboard that zeroes your stats.
- **The character page** (**D-120**). `PORTRAIT_STEP` is gone: the subject keeps
  his place on the ring with the fire lighting his face from the front, and
  `_bog_wanted` hides the other seven on this client while the page is open. The
  framing re-solved for a subject three metres back.
- **The bow off the face** (**D-121**). `preview_carry` measures a **head**
  clearance now — 0.06 m to the skinned head, the spear's own number — and
  `-- probe` maps the whole tilt space: `CARRY_TILT` (47.5, −34) → (40, +10),
  and the limb that passed through the nose at 0.002 m clears it by 0.134.
- **The hit marker** (**D-122**). 3 px arms that land 40% oversize and pull to
  size over 70 ms before the fade, held 0.45 s; a **kill** is a full white X
  through the centre gap held 0.6 s with `hitmarker_kill.wav` under it. Sword,
  spear, arrow and lightning each proven to reach it.
- **Movement** (**D-123**). A full draw walks at 1.15 m/s (`DRAW_SPEED_SCALE`),
  the camera comes in to 3.1 m and 2.15 aiming, a **slide jump** is its own move
  replicated as `sync_slide_jump_serial`, and **crouch alone slides** — held in
  the air it pre-arms the pose, so a landing at run speed is sliding on the tick
  the feet arrive with neither `Land` nor `LandHard`.
- **Fists, the emote and the sword** (**D-124**). **H** holsters: no prop in the
  fists, 10% more speed, and LMB **punches** for 20. The dance empties the hands.
  The great sword's click is a three-slash chain at 50 a slash, and the spin it
  replaced is now the **sprint attack** at 0.8 of run speed.

**The two stand-ins retired the same evening (D-125).** `SlideJump` is
`Doing A Forward Flip While Running` (1.10 s, `lift` 0.333, `apex` 0.600,
`land` 0.867) and `Punch` is `Cross Punch` (0.87 s, `hit` 0.367), each chosen
from the whole of its Mixamo search on `tools/clip_measure.gd`'s numbers and a
`preview_bog` sheet, with the markers read off `tools/clip_events.gd`.
`BogAnimator.clip_or(role, fallback)` stays as the mechanism for the next
move that ships before its take is picked; nothing plays a stand-in today.

**A drawn bow through a jump (D-127).** The archer's 92° of side-on lives in
the pelvis, which the air pose and the `Land` clip take away while the draw
layer keeps holding the bow, so the top half swung a right angle left for the
length of every jump. `BogAim` now lerps its yaw correction by
`BogAnimator.plane_lost()` — the airborne blend and every full-body one-shot's
own fade, as a product — and `tools/movement_check.tscn` gained an `air_draw`
verdict that reads a 1.0° swing where there was 91.8°, with the ground
unchanged to the degree.

**Eleven more skins (D-126), parked (D-128).** bloom, buzz, chip, crack, dash,
fudge, gourd, koi, ooze, volt and wrap have complete folders under
`art/skins/` and are **not pickable**. Tripo regenerated the sculpt for this
batch (9 124 vertices in its own UV layout), so their paint could not be worn
as it was; `tools/bake_skin.py` registers the body onto each download and
paints the body's layout from it (1.9 mm fit), and the result is good and is
not the first batch, whose paint *is* the body's layout. The owner's call is
to get the second batch the way the first was made — a Tripo retexture of the
original mesh, 15 872 vertices, worn straight through `extract_skins.py` —
rather than tune a registration; until then `Skins.PARKED` holds the names and
the gate pins the pickable list at fifteen (SHIRT, the first garment skin, D-163). `PLUSH` is an empty folder and
`SHIRT` is a garment (the pipeline spike), so neither is a skin.

The gate is at **178 of 178** and green, and `net_test.sh` passed after the
round with the engine quiet in both processes. D-124 touched replicated fields
on the Bog (`sync_holstered`) as D-123 did (`sync_slide_jump_serial`); the
socket run carries them, though no stage presses H or slide-jumps yet. Two things were
deliberately left out and are PLAN 10.14 and 10.15 — a `✊` kill-feed glyph for
the fist and a `fist_hit.wav`.

**Committed and pushed on 2026-09-18**, together with the practice-range and UI
round of 2026-09-17 (**D-112..D-118**) that it is built on top of, which had
been sitting in the working tree. Nobody has played any of it: every number
above is a render, a headless tool line or a gate check.

### Before that — the practice range

**Glowworm Grounds** (`range`) is built and in the gate, as **D-112..D-116** and
`docs/PLAN.md` Phase 9. It is the seventh map and the first that is not an
arena: a cleared bog with three throwing lanes, a sixty-metre bow lane,
a gallery, a melee pit, an ability yard, a parkour course and two void lips off
one lodge deck. A **Practice** button on the main menu goes straight there with
no lobby and no port. Twenty-seven dummies — real Bogs at roster ids 900+, hidden
from every roster screen, driven by the host — stand on their marks running eight
behaviours; three weapon racks line the lodge's east wall and four item wells its west, with a refill stone in the middle of the deck (D-161);
and boards, drifting orbs and a gong are things to shoot that are not Bogs.
`docs/PLAN_RANGE.md` is the scope it was all argued against and
`docs/ARCHITECTURE.md` says where each piece lives.

*Three things this paragraph said on 2026-09-17 are no longer true, and D-119 is
why: it was built **at night** and is now an hour before sunset; it had
**twenty-three** dummies and four more held in reserve for a station to mint,
and all twenty-seven stand up; and the **six signposts** that switched a zone's
behaviour are gone along with `AudioDirector.RANGE_CHIME` and its wav, so a
lane's lesson is authored in the map and the only thing to walk into is the
stats signboard.*

The one thing it changed about an ordinary match: the **hit marker flashes on
every landed hit, on every map**, because `hitmarker.wav` has done so since
D-062 and the picture had never caught up with the sound. Damage numbers and the
stats panel stay practice-only. *Its shape is **D-122**'s now — 3 px arms with a
snap-in, and a kill is a full white X with its own sound rather than the same
mark in another colour.*

Four new headless tools back it — `tools/range_brains.tscn`,
`tools/range_items.tscn -- all`, `tools/range_targets.tscn` and the `range`
branch of `tools/playthrough.tscn` — plus the usual `preview_map` and
`parkour_report` rows and a `range` mode on `tools/hud_range.tscn`. That is the
141 → 166 move. **Nobody has stood on it**; PLAN 9.6 is the list of questions
that need eyes, and the renders to look at first are
`tools/showroom/out/range_sunset/range_pad{0..7}.png` and `range_top.png` —
D-119's re-render of the same views an hour before sunset. (`range_final/` is
the night set, and is what those questions were first asked of.)

### And the UI pass — the look and all three layouts

Landed the same day, as **D-117** and **D-118**, and chosen the same way: built
as candidates in `tools/showroom/` over a parameterised copy of the real theme
builder and the real scenes, photographed with the live 3D behind them, and
picked by the owner off the pictures.

**D-117 is the look.** Seven candidates; **Quiet** won. Surfaces are white at an
alpha rather than a lighter blue-grey, so a panel is a dimming of whatever is
behind it and works over the forest at night and the arena at noon. Nothing is
bordered — four strokes are left in the whole UI and each means something. The
two accents collapsed into one (`AMBER` is now exactly `BOG`), the accent is a
wash except on a hovered primary button, and the wordmark went 44 → 72 px,
because a quiet UI has to earn its one loud thing.

**D-118 is where everything is.** The menu is one bar along the foot with a
random quip under the wordmark instead of a rule and a place name. The lobby is
a 460 px match rail and a 480 px room, with the ring reframed to stand in the
gap on three ranks of nameplate, and the weapon and skin pickers moved out to a
Weapon and Character page with a computed portrait and 256² cut-out thumbnails.
The HUD puts everything about you in the bottom-right under the hand on the
mouse, runs the kill feed up the left edge off the chat, and takes the borders
off the ability tiles — they were the last accent outlines in the game.

`tools/showroom/` stays as a dev tool; `tools/showroom/out/` is gitignored.
`docs/ARCHITECTURE.md` says what is in it.

### What the two integrations each found

Worth reading as a list, because they are all the same shape and the next one
will be too — **a thing wired into a testbed and into nothing else**:

- Nothing in a real match **read the movement keys**. `Bog` exposed
  `input_direction` and nothing filled it; both testbeds had their own reader,
  so WASD worked everywhere except in the game. Abilities worked, because
  `BogCombat` reads its own input inside the Bog scene — which is what made it
  look like input was fine.
- The arena **never instanced the HUD**, so a match had no crosshair, no score,
  no scoreboard, no pause menu and no results screen.
- Entering a match **never took the mouse**. The menu and the lobby each take a
  cursor hold and neither gives it back, so mouse-look and throwing — both gated
  on `SceneFlow.cursor_is_free()` — were dead.
- The **ambient loops pointed at a path that never existed**. A missing optional
  asset is skipped in silence by design, which is right for an absent file and
  wrong for a typo, so the island shipped with no ambience and nothing said so.
- The **kill feed hung the game on the sixth death of every match** —
  `queue_free()` inside `while get_child_count() > MAX_ROWS`, and `queue_free`
  defers, so the count never fell. 100% CPU, no error, no output.

Every one of those passed all the checks that existed when it was written.
`tools/playthrough.tscn` and `tools/cursor_flow.tscn` exist so that the next one
does not.

**If you add a harness, ask what it is supplying by hand.** That list is the list
of things nothing else is checking.

---

## The animation rebuild — done (D-095..D-101)

The character's animation pipeline is being rebuilt from scratch
(`ANIMATION_REBUILD_PROMPT.md` was the brief; **D-095** to **D-101** are the
records; `docs/ARCHITECTURE.md` has the shape of it). **The game runs on the
new body and the new animator**: `scenes/player/bog.tscn` instances
`art/bog/BOG.fbx` and `scripts/player/bog_animator.gd` reads the library and
its markers. The old path — the Blender builds, the Mixamo packs, `bog.glb`,
`elder.glb` — is gone (D-101); `assets/source/` is the clips, `clips.json`
and the raw props and map the other pipelines still read.

**The gate is 135 of 135** since D-099: the grips are re-solved on the new
hands by their own tools, the ragdoll measures its capsules off the mesh at
build time, and the Elder's robe is refit to the new skeleton as the first
skin in `art/skins/elder/` (`tools/refit_robe.gd`).

What exists now:

- `art/bog/BOG.fbx` — the body as Mixamo rigged it, imported by Godot at
  `root_scale = 180` (1.80 m, feet at 0). Its texture `art/bog/BOG_0.png` is
  extracted on import and gitignored — **and so is its `.import`**, which is
  the pairing D-102 is about. A fresh checkout therefore needs three import
  passes before the body has a texture: `--import` writes the PNG, a second
  `--import` imports it, then delete `.godot/imported/BOG.fbx-*` and run
  `--import` once more so the material is built on a texture that loads.
  `clip_check` asserts the albedo, because every other check in this project
  passed on a flat grey BOG.
- `assets/source/anims/*.fbx` — **72 clips, one per role** (D-096 chose
  68 from 104; D-125 added `SlideJump` and `Punch` from 101 fetched takes),
  each with a `.import` that names `tools/import_clip.gd`. `clips.json`
  carries **72 rows**, one per clip.
  The two newest are `SpearCarry` (the one-handed ready idle the spear's
  grip is solved over, D-103) and `Twerk` (the emote on **Y**, D-105); the
  spear also has its own overhead `Throw-SpearThrowObject` now (D-104).
- `assets/source/clips.json` — **the rule table** (D-097): per clip
  `loop`, `face` (`hips` / `chest` / `none`: which body line the import
  squares to the body's forward), `untwist` and `markers` (its events in
  seconds). The import script applies them all: records the authored speed,
  yaws the hips by the facing rule, squares the chest and head over the hips
  where `untwist` says to, locks the hips, sets the loop mode, writes the
  markers onto the `Animation`, and files it in `art/generated/bog_clips.res`
  (one `.res` per clip under `art/generated/clips/`). Every library key is a
  role: `Walk`, `Run`, `CrouchIdle`, `BowDraw`, `SwordCombo`, `Slide`.
- **`untwist` is D-110**, and only `SpearCarry` and `BowCarry` carry it. A
  carry clip plays as an upper-body layer over `Spine1`…`Head`, so its own
  spine twist lands on whatever the legs are doing — the head was 51° and 58°
  off the chest, which read as a Bog looking over its own shoulder in every
  pose and worst in the air. `face` cannot reach it, because a hips yaw carries
  the chest with it. Two constant counter-turns at `Spine1` and `Neck`, each
  the clip's own mean so the sway survives, and `clip_check` holds both joints
  inside `UNTWIST_TOLERANCE` (3°). The archer's plane keeps its turned stance:
  there the stance *is* the pose.
- 113 markers on 52 clips, each from `tools/clip_events.gd`'s kinematics and
  a six-frame sheet: `release` on Throw (0.800), BowLoose (0.183) and Cast
  (1.000), with `windup` 0.300 on Throw — the spear's throw plays at rate 1.0
  because that 0.500 s window is what the clip authored (D-104);
  `swing`/`hit`/`end` on every sword attack; `dive`/`apex`/`land`/
  `up` on the roll; `down`/`up` on the slide; `raise`..`done` on the drink;
  `step_left`/`step_right` on every travelling cycle. The animator reads
  these; it carries no clip times.
- `tools/clip_check.gd` — in the gate, now also holding the squared lines
  under 1° and the required markers present. `tools/clip_measure.gd` — every
  clip as numbers. `tools/clip_events.gd` — where a clip's events are.
  `tools/preview_bog.tscn` — the picture, one row per clip key, several keys
  stack, a `from`/`to` window zooms.

```
"$GODOT" --headless --path . --import                       # the build, ~10 s
"$GODOT" --headless --path . --script tools/clip_check.gd   # the gate check
"$GODOT" --path . --resolution 1600x1400 --script tools/snapshot.gd -- \
    res://tools/preview_bog.tscn out.png 30 Run-StandardRunning,Run-RunningForward-1
```

Skins are folders under `art/skins/` (D-100): the robe is the clothing
example, `example/` the recolour (`tools/make_recolour.gd`,
`Bog.wear_skin`), and `art/skins/README.md` says how to add the next one.
**Thirteen team skins** sit beside them — bogina, boo, clank, crag, gilt,
glub, gum, muck, rime, roar, slag, toad, void (D-108) — each a Tripo retexture
of the same sculpt, extracted from its `.glb` by `python
tools/extract_skins.py`; a second batch of eleven (D-126) is baked through
`tools/bake_skin.py` because Tripo regenerated the sculpt for it, and is
**parked** out of the pickable list until its downloads are redone on the
original mesh (D-128). The downloads live under `assets/source/skins/` behind a
`.gdignore` and are untracked; the 2048² PNGs are what is committed. **The
lobby picks them** (D-109): `scripts/game/skins.gd` is the pickable list — the
thirteen plus `bog`, the plain body at index zero — and the strip is one line
of 40 px swatches under the weapon blurb. In free-for-all a skin is one more roster key
with `weapon`'s whole lifecycle; in **Teams it belongs to the team**, lives in
`Net.team_skins` indexed by team, can be changed by any member, and no two
teams may wear the same one. `Net.skin_for(peer_id)` is the one call every
dresser makes, so the ring, the arena and the lit swatch cannot disagree.
Because the team skin *is* the team's identity there, the in-game team recolour
is off in Teams — the nameplate keeps the colour. `Bog.set_team_tint` now gets
a real team from only two places: `tools/team_tint.tscn`, which is the check
that the shader still works, and backdrop entries with no `skin` key.

**One thing only the user can do** (PLAN 8.8), one row in `clips.json` plus
the fetch: the Magic pack's `Standing Run Left`, so the running strafes stop
sliding at 1.12 of body speed (D-098 says what the import needs: a
`mirror_of` rule for the right-hand twin). The other half of that item is
done — the one-handed carry idle is `SpearCarry`, and the spear's trunk
clearance is a measurement again (D-103).

**Both props were re-solved when `untwist` landed** (D-110), because a rigid
grip is a measurement of a pose and squaring the head moved it: the spear's
trunk clearance fell to 0.053 m against 0.06 allowed and the bow's composed
floor clearance to 0.127 m against 0.15, and the gate said so. The spear's
`GRIP_ROTATION` is **(20.79, 0.00, 22.98)** with `GRIP_OFFSET` **(0.2524,
−0.4261, −0.1801)** derived — the bearing is on the centre line now, because
"the tip points where the Bog is looking" moved when the head did — and the
bow's `CARRY_TILT` is **(47.5, −34.0)**, six degrees on Z off D-070's. Trunk
0.069 m, letter card 0.165 m above the grass, gate back to 135 of 135.

Answered at the step 2 checkpoint by the user and built at step 4: **backing
up is slower** (`Bog.BACK_SPEED_SCALE` 0.6); **the crouch is the deep squat**;
**the double jump is a head-first dive** (`Roll` scrubbed by the arc). Also
decided at step 4: a BOG with a bow drawn walks (`Bog.AIM_WALKS`), and the
draw's pull is `BowReload`'s nock-to-cheek half second scrubbed by the
charge, because the aim and draw clips are the same pose.

## Voice memos (BOG-45)

A memo dropped in `memos/` (gitignored, `.gdignore`d) becomes Linear tickets
through the `memo` skill: `tools/transcribe.py` writes a timestamped
`<name>.raw.txt` next to the audio, the skill untangles that into a dated
`feedback/*-memo-*.md` with every want quoted and timestamped, and the
`triage` skill takes it from there. A memo is "done" when a feedback file
names it on its `Source:` line.

Transcription is local, no API key:

```
pip install faster-whisper nvidia-cublas-cu12 nvidia-cudnn-cu12
python tools/transcribe.py            # first run downloads medium.en (~1.5 GB) to ~/.cache/huggingface
```

The two nvidia wheels are what let CTranslate2 use the RTX 3080 (cuBLAS 12 and
cuDNN 9 as loose DLLs; the script finds them under the user site-packages,
where the Store Python keeps them). With them a memo runs at about ten times
realtime; without them the script falls back to the CPU and says so, which is
slower than realtime. No ffmpeg needed, faster-whisper decodes mp3 itself.

---

## The engine, and the one thing that will waste your afternoon

The project needs **Godot 4.7.x**. A 4.6 binary does not fail gracefully — it
fails with a wall of

```
Parse Error: Too many arguments for "add_blend_point()" call.
```

which looks exactly like a bug in this repository and is not one. `add_blend_point`
gained a fourth argument in 4.7. See **D-017**.

`tools/smoke_test.sh` now finds the engine itself and *refuses* a 4.6 binary
rather than running it, so this should not bite again. `$GODOT` still overrides.

| machine | path |
|---|---|
| this Mac | `~/Downloads/Godot_v4.7.2-stable_macos/Godot.app/Contents/MacOS/Godot` |
| the Windows box | `~/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe` |

Note that on Windows the `.exe` in that path is a **directory**, and you want the
`_console` binary — the plain one detaches and prints nowhere. On macOS,
`/Applications/Godot.app` is 4.6.3 and is the wrong one.

A useful trick: a clean `--headless --path . --import` that rewrites **no**
`.import` files means the engine in hand is the one the committed assets were
generated by. If those files come back modified, the engine is wrong.

---

## What is done

Phases 0-7 are complete. `docs/PLAN.md` has the item-by-item state. Highlights
of what that means:

- **The whole loop works.** Menu → host → lobby → start → island → warmup →
  match → results → rematch or back to the lobby.
- **The island** (Whisperbloom Hollow) is generated from `Net.config.map_seed`:
  a 23 m main island with a dozen trees standing about 15 m tall (D-055), ~2200
  props in all, a shrine on the high ground, a mushroom grove, a
  rock arch, log bridges to two satellite islets, stone paths, 17 torches,
  fireflies, spores, falling leaves, and two ambient beds. It takes 2-6 seconds
  to build, which is why `SceneFlow` shows a loading card.
- **The second map** (Rust) is hand-made rather than generated: an industrial
  yard, 42 x 28 x 64 m, instanced from a 43 MB `.glb` with its collision and its
  back-face culling built at load (**D-031**). The host picks between the maps in
  the lobby's Match panel; the seed row hides itself for the static ones.
- **The third map** (Kopje Crossing) is hand-made and has no import: a 96 m
  savanna plateau whose 127 rock platforms are laid out of tables in
  `safari_map.gd` and baked into collision by the same `StaticMap` (**D-042**).
  A checker proves every platform is reachable on the Bog's real jump arc.
- **The fourth map** (Lantern Wharf) is built the same way and is the opposite
  kind of map: a 36 m walled box yard at dusk, mirror-symmetric between two
  bases, with no eye-to-eye sightline over 25 m on the ground (**D-056**). It
  declares its own Capture B·O·G bases and letters.
- **The fifth map** (Halcyon Wake) is built the same way and is the tall one: a
  66 m superyacht on open water on a bright morning, with four decks joined by
  stairs and hop steps, the sea as the void, and B two decks up (**D-057**).
- **All four static maps have had an atmosphere pass** (**D-058** to **D-061**),
  one per map, after the user's verdict that Whisperbloom Hollow was the only one
  that felt like a place. Each got its own hour and its own weather rather than
  the island's night copied over: Halcyon Wake a sea of seven analytic waves with
  a sun-glitter track, a coast to lie off and a wind everything agrees with; Rust
  an HDR panorama whose sun elevation was *measured* off the file and matched by
  the scene's own light, plus dust, heat shimmer and a refinery horizon; Lantern
  Wharf the dusk its name promises, with the floods as real sources, wet
  reflective concrete and a working port beyond the walls; Kopje Crossing towering
  cumulus, a 3.6 km plain with three receding ranges, dust devils and vultures.
  None of it is collision — all of it is built after `StaticMap`'s `super()` — and
  no pad, sightline or jump moved. The gate is still 63 of 63.
  stairs and hop steps, the sea as the void, and G two decks up (**D-057**).
- **The sixth map** (Twin Quarry) is built the same way and is the first one
  drawn for **Capture G·U·B** rather than fitted to it: a 48 m stone pit under
  an overcast, with each team's base four metres up on a cut bench inside a
  1.8 m wall, reached by two haul ramps and by nothing else. Its symmetry is a
  180 degree turn rather than a mirror, which is what forces the middle of the
  map to be solid rock and G onto the other diagonal (**D-082**). It is also the
  map that wrote down the height rule the others only imply: **3 m cover breaks
  every line at head height, and tall rock is only for lines seen from above** —
  ten-metre columns box the third-person camera in, so there are eleven of them
  and not seventeen. It dresses itself out of the MegaKit, none of it collision.
- **Capture G·U·B has a vault** (**D-068**, **D-070**): banked letters stand on
  a point inside each base rather than teleporting home, so what a team holds is
  visible in the world, and an enemy who stands on that vault for
  `capture_steal_time` (a 1-5 s lobby dial) lifts one back out. It is the only
  score in the game that can go down. Both ends of the clock are drawn — a bar
  for the thief, an alarm for the team being robbed.
- **Every letter is called out across the top of the screen** (**D-093**), in the
  team's colour, in every mode: picked up, the full set, and stolen. Text only,
  no sound.
- **The camera near geometry is measured, not guessed at** (**D-088**).
  `tools/camera_range.gd` now carries a fourth verdict, `calm`, which watches the
  lens's own motion with the player's walking and turning subtracted out. The
  uncommanded rotation it was added to catch went from 13.84 deg in one frame to
  1.00, and the old rig fails the new check on all three of its counts.
- **There are three asset kits now.** The Stylized Nature MegaKit (CC0,
  Quaternius) it always had, Kenney's **Factory Kit** (CC0, 143 models on a 1 m
  grid, one colour atlas) for industrial dressing, and Kenney's **City Kit
  (Industrial)** (CC0, 37 models) for what stands beyond a wall. Lantern Wharf
  uses the first for pipe runs, wall-top machinery, panels and floor markings and
  the second for a town outside its wall; none of either is collision (**D-084**,
  **D-063**). Neither kit has a forklift, a barrel or a pallet — those are built
  in code, like the map's containers and cranes already are.
- **The UI** is themed and complete: menu with a live glade behind it, an
  eight-Bog lobby, HUD, scoreboard, kill feed, pause, settings, chat, results.
  On the home screen the hero Bog **stands across the fire** and turns back
  over it on a 24° lens, so the one warm light in the glade lands on his face
  instead of outlining him (**D-106**). Both he and the lobby's ring now
  **face the lens and turn back toward the fire**, not the other way round
  (**D-111**): the old arithmetic corrected away from the flame and so put the
  Bogs at the ends of the arc 62° off the camera — a row of profiles with one
  face in the middle. Every face is at the lens by construction now, with the
  ends turned 11.6° inward and the hero 4° off. In the lobby the weapon strip is
  always on, over the ring's heads; the three panels each **fold to their own
  heading** rather than collapsing as a stack, the roster starts folded to
  its count and the match config is host-only, so a client sees the strip, a
  `Bogs 3 / 8` bar and a line to type in (**D-107**).
- **Combat** is a one-hit spear, a shield you cannot be shot through, and a
  magnet that drags people into the open. The shield is a plank barricade
  (**D-079**): 1.75 m tall and 1.22 wide, one box of collision solid from the
  ground to the top, planted facing the planter's yaw exactly so a row of them
  is a shield wall. The spear leaves the hand **half a
  second** after the click, on the frame the throwing arm reaches full extension
  (D-025, **D-063**) — an overhand delivery with the shaft raised over the head
  first, so the moment it goes has a shape of its own and nothing on the HUD has
  to explain it.
- **The Bog itself was rebuilt** (D-029). Eight Mixamo FBX files become one
  `art/generated/bog.glb` through `tools/build_bog.py` — nine clips, 10.5k
  triangles, 1.80 m, root motion locked and every clip's facing aligned — and
  `BogAnimator` is a new tree built to a rule that makes the old freeze
  impossible: ground poses come from speed, air poses come from the arc, events
  are one-shots. The collision capsule now follows the pose (stand 1.55, crouch
  1.35, slide 0.75), the spear sits in the fist instead of through the head, and
  a corpse reads as a body.
- **The Elder is playable** (D-037 built the asset, **D-038** made it real,
  **D-040** turned it into the thing the user asked for after playing it).
  `tools/build_elder.sh` fits a purple robe and a wizard hat to the Bog's
  measured silhouette and writes `art/generated/elder.glb`: 4,352 triangles, no
  animation data, bound onto a live Bog's own `Skeleton3D` at runtime. In a
  match it is a fourth kind of drop off a corpse at **2%** in **every** mode.
  The Bog that walks over it becomes, on every peer's screen, **twenty seconds
  of a thing that cannot be killed**: nothing but the void takes an Elder down,
  the robe burns out on a host-owned clock rather than on a death, and a spear
  thrown at one is turned aside in a violet flash. It moves 35% faster, jumps
  to 2.64 m instead of 1.69, and carries **no spear at all**. The same mouse
  button plays the Elder's **own `Cast` clip**, not the spear's `Throw` (D-064):
  its `windup`-to-`release` window is 0.533 s and `BogAnimator.cast_rate_for_release`
  plays it at whatever rate puts the release on `lightning_delay` — about 2.7x at
  the default 0.2 s, floored at a 0.14 s wind-up so the arm is still seen to move —
  and fires a hitscan **bolt out of the hand 0.2 s after the
  click**: 28 m, 1 s recharge, one hit kills, stopped by a shield
  exactly as a spear is, and refused during a letter hold. The fist crackles
  while it is loaded and is bare while it recharges, which is the spear's
  empty-hand tell kept intact, and the wearer gets a draining countdown above
  the ability bar — never on the crosshair (D-036). Expiry is not a death: the
  letters and the carried stock survive it. The bolt is a branching
  `ImmediateMesh` stroke with a flash at both ends, a spark burst, a scorch,
  layered thunder and a camera kick: `out/lightning.png` and
  `out/elder_hand.png`.
  The known asset risk is unchanged — the hem does not survive `Run`, `Slide`
  and `JumpTwo` cleanly, and D-037 says how badly, with the renders. One new
  one: a boosted Elder outruns its own `Run` clip by up to a third, because the
  locomotion blend space tops out at `RUN_SPEED` with the clip's rate baked in.

---

## What is left

1. **Real multiplayer has never been played.** See the next section — this is
   the big one.
2. **Mid-match join as spectator is built and has never been played** (PLAN 1.8,
   **D-164**). A peer that joins a running match is no longer refused: it is told
   the phase, the clock, every Bog that is standing and what is left of each,
   everything lying on the ground, the teams' letters, every hold and robe with the
   time already run, and the scoreboard, and it watches the rest of the round,
   joining properly at the next match. `net_test.sh` stage 12 proves it over a real
   socket with one process leaving and rejoining. What no harness covers is the
   lobby's own path, three or more peers (a client-owned Bog still leaks one
   `Node not found` line into a joiner's log), and joining a Teams, B·O·G or lives
   match rather than a free-for-all.
3. **Rust has never been played on by a person.** The map itself is **done** —
   `scenes/world/maps/rust.tscn`, `resources/config/rust_env.tres`, the
   `"rust"` row in `MapCatalog`, and `scripts/world/static_map.gd` filled in
   (**D-031**). The host picks it in the lobby's Match panel, and the gate walks
   a whole match on it and re-checks all eight spawn pads with the physics every
   build. What no harness covers is the part that needs eyes and hands: whether
   the pads are *fair* rather than merely standable, whether a 42 x 64 m yard of
   shipping containers plays well with a spear that drops, and whether it holds
   frame rate with eight Bogs and their ragdolls in it. Nobody has stood on it
   in a real match. Two smaller things are also unconfirmed: the map is lit by
   one sun and no fill lights, so a container interior that turns out too dark
   in play wants a couple of shadowless `OmniLight3D`s under a `Lights` node
   (the contract already allows for it and the scene has none); and the void
   height of -13 m was reasoned from the geometry, not fallen through.
   **Kopje Crossing is in the same state** (**D-042**): built, in the lobby,
   walked end to end and checked for reachability by the gate, and never played
   by a person. Its open questions are its own — whether the 9.5 m summit is a
   hill to fight over or a perch nobody leaves, and whether knee-high grass hides
   a crouched Bog more than a one-hit spear can afford. **Lantern Wharf** too
   (**D-056**): whether a 36 m yard is chaos in the good sense for eight Bogs,
   and whether the dusk floodlights read in a fight, are for a person. And
   **Halcyon Wake** (**D-057**): whether the flybridge is a hill worth taking or
   a perch with no cover, whether the 2 m walkways under the upper deck are good
   flanks or corridors, and whether the third-person camera copes in the salon
   and under the overhangs. And **Twin Quarry** (**D-082**), whose questions are
   the ones an elevated base raises: whether two ramps is one too few to break a
   defended bench, whether the drop port in the wall is a sniper slot, and
   whether the team whose bench U or B happens to sit beside is ahead.
4. **Playing it, properly.** A person has walked around the island and thrown
   spears, and the automated checks cover the rest — but nobody has played a
   *match* to a conclusion against another person, and no one has tuned the feel:
   movement, camera, spear arc, cooldowns, or how readable the map is in a fight
   at night. That is the work no harness can do.

---

## The state of the networking

Everything networked runs through `Net.start_offline()` in every test, which is
a real session on an `OfflineMultiplayerPeer`: peer 1, `is_server()` true, and
**no socket** (D-011). Every `is_host` branch and every authority check takes the
shipping path — but `rpc()` reaches nobody, so only the "call locally" half of
the codebase's `rpc()`-then-call-locally pattern has ever run.

**Serialization has never been exercised. No packet has ever been sent.**

That is no longer true, and the first time people played it the gap showed:
**a non-host's abilities happened for nobody**, because the recursive
`set_multiplayer_authority` on a spawned Bog left the host's `_do_*` broadcasts
landing on a node the host did not own, and every peer refused them. The fix and
the reason nothing caught it are **D-024**. `net_loopback` has a stage for it
now — the client throws a spear, plants a shield and lobs a magnet through the
public `BogCombat` calls, and both processes assert the results — and
`net_test.sh` fails a peer outright on `is not allowed on node`.

`tools/net_loopback.tscn` and `tools/net_test.sh` exist to change that by running
two real processes against 127.0.0.1. Read that tool's header for what it covers
and what it found. Two things it still cannot tell you, and only two machines
can: real latency, and whether a client-authoritative Bog feels right to the
person driving it.

Worth knowing before that session:

- The **invite code is an IP and port**, Crockford base32 (D-005). Which one
  depends on whether the host has set a **public address** in Settings: blank
  and it is this machine's best local address (tailnet ahead of LAN), set and it
  is a resolved playit.gg tunnel endpoint, which is the internet path and the
  only one where nobody but the host installs anything (D-028). No backend
  either way. It also means the code leaks the host's address, which is a
  product decision worth confirming rather than a settled one.
- The tunnel's **local** port must be **27015**; its public port is whatever
  playit allocated, and that is the one the code carries. Getting that pair
  backwards is the one setup mistake the game cannot detect for you.
- macOS may raise a firewall prompt the first time a Godot binary binds 27015.
  The loopback harness binds 127.0.0.1 only, so the gate never meets one.
- Godot's user data is keyed on **project name, not path**, so every checkout of
  this project on one machine shares `user://settings.cfg`. A name typed into
  one worktree's menu changes what another one's testbed prints, and a public
  address typed into one would have sent `tools/net_test.sh` to a real resolver
  — hence `Net.ignore_public_address` (D-028).

---

## Verification, and what each tool is for

Three tiers, because three different kinds of claim need three different proofs
(D-015, D-019).

| tool | proves |
|---|---|
| `tools/smoke_test.sh` | **the gate** — import, and one hundred and twenty-six checks |
| `tools/cursor_flow.tscn` | entering a match takes the mouse, and leaving gives it back |
| `tools/playthrough.tscn` | the whole path, menu to results; 50 assertions on the island, 58 on Rust. Takes a map id after a `--` |
| `tools/match_rules.tscn` | 888 assertions across 20 scoring scenarios, the last of them three Bogs carrying three different weapons (D-069) |
| `tools/invite_codes.tscn` | 2675 assertions over 1296 endpoints, plus the host's typed public address |
| `tools/combat_range.tscn cover` | a shield stops a spear, the same throw without one does not, and a Bog cannot walk through it (D-039, D-079) |
| `tools/combat_range.tscn recharge` | the spear is back in the fist after twelve throws, and an emptied fist refills itself (D-039) |
| `tools/combat_range.tscn release` | the shaft appears `THROW_RELEASE_TIME` after the click, the fist is empty on that same tick, and that tick is the one the throwing arm is furthest forward — the only check that reads the animation rather than the constant (D-063) |
| `tools/combat_range.tscn bow` | the bow, in numbers (D-065): a letter hold refuses the draw and empties the bow hand, a snap shot let go one frame after the key went down takes exactly `bow_damage_snap` and flies the snap dials, and a full draw takes `bow_damage_full` and flies the full ones. Neither flight is read off the arrow — the speed and the drop are fitted off six ticks of its own positions. **In the gate**, headless |
| `tools/combat_range.tscn draw` | the charge as a *tell*: one float published onto a **remote** Bog, and the two skeletons agreeing about how far the string is back to within a centimetre at five charge levels — with the control that the draw moved the hands 0.41 m, so agreeing means something (D-065). Also prints how far off the Bog's facing the composed bow points, which was **91°** when this weapon shipped and is 1° now that `BogAim` turns the torso onto the crosshair (D-066). **In the gate**, headless; through `snapshot.gd` it renders the two Bogs side by side |
| `tools/preview_bow.tscn` | the bow in the hand across the charge: `-- measure` solves the grip off the draw clip and prints the three constants `HeldGear` carries, and the default sheet is six Bogs from brace to full draw with the string bending under the blend shape (D-065). `-- measure` also checks what the **carry tilt** buys on its own: the lowest limb tip over the twelve clips a Bog walks around in, which has to stay 0.15 m off the ground and reaches 0.284 m where `Run` used to plough by 0.158 (D-066). That is half the answer since D-070 — a carried bow wears a *pose* as well now, and `preview_carry` is what composes it — and it is kept because it is the half that says the tilt is still earning its keep. **In the gate**, headless |
| `tools/combat_range.tscn strafe` | the feet, round the compass (D-066): eight bearings at walking and running speed on a Bog held facing one way, with the slower of its two toes measured every tick. Forward and backward plant at 0.28 of body speed or better and no leg passes 1.25, against 1.36 for the one-dimensional space this replaced — and the crouch, which is still one clip behind a line, is the control that spreads 0.21 to 1.41. Since D-071 it also holds the **strafe axis** itself: the four sideways legs plant at 0.85 or better (running sideways is 0.43 and 0.30 where it was 0.98 and 0.93), and the two halves of that axis have to be the **same move**, within 0.20 of each other. The second of those is the one that earns its place — Mixamo's aim-strafe families are handed, so a downloaded right strafe passes the first line by a hundredth and fails the second at 0.54. **In the gate**, headless with `--fixed-fps 60`; `-- strafing` is the picture |
| `tools/combat_range.tscn spine` | the torso that aims (D-066), swept round the whole horizon and through the camera's whole pitch range at a full draw: the bow holds within 3° of bearing and 5° in space of the crosshair (against D-065's **91°**), tracks 123° of elevation, and two arrows fired from one spot at the two ends of that range leave from the *same point* 122° apart — D-025 and D-045 asserted against the thing most likely to break them. **In the gate**, headless; `-- aiming` is the picture |
| `tools/combat_range.tscn sword` | the great sword, end to end (D-068). It opens with a **rehearsal** — one swing at nobody, with the blade read off the bone attachment at the release — because nothing in the mode can be placed until that number exists: `Swing` turns the body through a revolution inside the skeleton, and at the release the blade is **55–66° off the Bog's own facing**, so a sweep along `-basis.z` would point at empty grass. Then the fists are checked on all 112 ticks of a swing, the kill is required to land `SWING_RELEASE_TIME` after the click and *within three ticks of the blade's own full extension*, 0.35 m inside the reach dies and 0.35 m outside lives, and an Elder takes nothing and wards. **In the gate**, headless |
| `tools/combat_range.tscn chain` | the swing as a movement tech, measured the way D-052 measured the hop and against the same ceiling (D-068). A Bog at a dead stop chains seven swings — 0.00, then 2.00 after the first, then **7.02** from the last, which is 1.30x run and is exactly `HOP_SPEED_CAP` — and a Bog that builds 7.02 with ten timed hops first has to *keep* it when it swings. Neither may pass the cap. **In the gate**, headless and deliberately **not** `--fixed-fps`: the spin and the recharge are wall-clock deadlines |
| `tools/preview_sword.tscn` | the great sword in the hands (D-068): `-- measure` solves the grip as an equation — a two-handed hilt has to reach from the fist that holds it to the fist that joins it, so the sword's **size is a measurement of the swing** (1.26 m, from fists 0.096–0.231 m apart) — and prints the three constants `HeldGear` carries, the point's 1.412 m reach at the release, and how far the blade dips. That offset moved 3 cm at D-074 and neither the scale nor the rotation did: the sword's grip starts from `HeldGear.fist_offset()`, which is the spear's palm point, so correcting where a Bog's fist actually is corrected all three props at once. The default sheet is seven Bogs across the swing, each set back by the advance it has covered by then, with a compass ring and a hip-line spoke under every one. `-- carry` is **gone** (D-070) along with the `SWORD_CARRY_TILT` it swept: a great sword is carried in `GreatSwordIdle` now, whose fists were drawn holding this exact prop, so the grip solved here is the grip for the swing *and* for the carry and a tilt had nothing left to do. `preview_carry` measures what replaced it. **In the gate**, headless |
| `tools/combat_range.tscn cast` | the Elder's half of the same question, and a different question (D-064): the bolt appears `MatchConfig.lightning_delay` after the click, the composed arm is 83% of the way out when it does, and the tick it appears on is the tick that arm stops going forward — which on `Cast` is a third of a second before it is furthest forward |
| `tools/combat_range.tscn potion` | the heal potion, end to end (D-067): a real death rolls the fifth `Pickup.Kind` and a dummy standing on the corpse collects it through its own `Area3D`; drinking it delivers **no** health on the frame of the click, some of it half way through and all forty at the end; a hit half way in ends the channel, spends the potion and keeps the half that had arrived; running ends a channel and a *magnet* dragging the same Bog at 4.5 m/s does not; two potions are lost on death; and the three lobby dials survive `to_dict`/`apply_dict` and both clamps. Since D-075 it also reads the **fists**: half way through the channel there is a bottle in the drinking one and no spear, bow, arrow or great sword in either, and one frame after the arm comes down the bottle is gone and the fist agrees with `has_spear()` again. D-067 made a drink empty both hands and proved it with a sheet of a Bog raising nothing, which is a weak thing to assert — an empty hand is also what a broken attachment looks like — so the bottle is what turns it into a measurement. **In the gate**, headless, with the channel shortened to 1.5 s |
| `tools/combat_range.tscn primary` | **one button, four weapons** (D-070). `throw_spear`, `draw_bow` and `swing_sword` are one `primary_attack` on LMB, and the four weapons do not read it the same way: a spear, a swing and the Elder's bolt fire on the **press**, a bow charges while **held** and fires on the **release**. So this presses the one action on a Bog carrying each in turn — moving the weapon the way the lobby does, `Bog.weapon` then `refresh_hand()` — and requires a windup, a draw, a spin and a windup. Through `Input.action_press` and not `try_throw_spear`, which is the opposite of every other mode here and the point of this one: the witness has to be the poll in `BogCombat._process`. The bow's round then **holds** the button for forty ticks, requires the draw to still be running on every one and past half charge, and requires letting go to loose. **In the gate**, headless |
| `tools/hud_range.tscn controls` | the input map, checked rather than read (D-070). Every action the settings panel names is in the map; **no two actions anywhere share a key or a mouse button** (`ui_*` excepted, which are meant to overlap); and the three actions D-070 retired are gone rather than orphaned. It exists because `swing_sword` and `respawn` were both physical keycode 82 for two decision records and nothing could say so. **In the gate**, headless |
| `tools/combat_range.tscn ward` | a real spear cannot kill an Elder, the robe burns out on its own, and the same throw kills once it has (D-040) |
| `tools/combat_range.tscn bhop` | timed hops climb to 1.3x run speed and no further, as a Bog, an Elder and a capture carrier; running, one jump, a late hop and a hop out of a dive roll do not beat run speed (D-052). **In the gate**, headless with `--fixed-fps 60` |
| `tools/combat_range.tscn respawn` | a Bog that dies holding a shield and an Elder that dies in its robe both come back empty-handed, including a remote Bog whose client is 200 ms behind the host (D-043) |
| `tools/preview_carry.tscn` | **the carry layer, for all three props at once** (D-070), and the one tool here that is not about one weapon — because the carry is one *mechanism*: a `Blend2` filtered to `UPPER_BODY_BONES` over the locomotion plane, pointed at `Loadout.CARRY_CLIPS` by a `Transition`. `-- measure` composes it a bone at a time, exactly as the graph does, and requires every prop to stay 0.15 m off the ground and 0.06 m off the Bog's **skinned trunk** over twelve clips — the real mesh, every head- and torso-weighted vertex, skinned by the formula the GPU runs, which is the method D-065 used and the reason its table is believable. It also requires the spear's shaft to stay within 30° of horizontal in every carried clip (D-072) — the one claim about this grip that was prose twice and went stale twice, once to D-066's six new clips and once to D-071's remirrored strafes; it is `LEVEL_MAX` now and a clip that swings the shaft fails the gate on the commit that lands it. It recomputes `HeldGear.GRIP_OFFSET` from `GRIP_ROTATION` and fails if the const has drifted, and checks the **letter card** — which rides the same grip and therefore moves with it — is out of the grass. Since D-074 it also asks the one question none of those can: whether the shaft is **in the hand**. A spear riding the knuckles is exactly as far from the trunk, as level and as high off the grass as one in the fist, so it measures the whole mitten — the hand bone and the three finger chains, 1,030 vertices skinned in the carry pose — and requires the shaft's axis to pass inside it (`PALM_MAX`, half the mitten's own 0.132 m thickness). D-072's grip passed everything else and reads 0.076 m here; the shipped one reads 0.050. `-- fist` is its picture, one Bog per palm point, framed on the hand from behind the right shoulder — which is the only angle the question can be seen from, because head-on a shaft passing in front of a fist looks the same as one passing through it. `-- solve` is how the spear's grip was found: aim the shaft where it is wanted in the Bog's own frame, read the grip back off the hand, and score every bearing against the trunk — 24 of them for D-070, and 288 for D-072, which had to find the bearing nearest straight forward that still clears the Bog. `-- poses` prints what each candidate clip does with the two fists; `-- sweep` nudges a lever and `-- sheet <weapon>` is the picture, one weapon in Idle, Walk and Run with the layer off and on. `-- hilt` is the **second** thing it is in the gate for (D-073) and is the general form of the fault `level` was a special case of: the great sword's three constants are seventeen poses of `Swing` averaged, so it averages them again and fails if they have drifted (`fit`), if `SWORD_GRIP_OFFSET` has been left behind by its own rotation — or, as at D-074, by the palm point both props hang off (`derived`), or if the pose the sword is *carried* in no longer closes its second fist on the hilt (`carried`) — it found a 0.6 mm drift four steps old on the commit it was written. `-- solve sword` and `-- elevations <weapon> plan` are what said the sword's 45° to the right is the carry pose's own fist line and not a fit. Since D-075 `measure` asks the palm question of the **other** hand as well (`bottle`): the heal potion is the first thing this game puts in a fist that is not a weapon, and it is measured off the left mitten's own 1,073 vertices in the pose `Drink` opens the fingers into — which is 9.5 cm further out along the hand's axis than the fist a spear is carried in, so the *shared* palm point `fist_offset()` lands 0.133 m away and the bottle is the one prop with its own. It reads 0.050 of `PALM_MAX`'s 0.066, and the 0.050 is deliberate: centred in that mitten the bottle spends half its belly inside the Bog's stomach. `-- potion` is the fit — the fist's centre, the two rotations worth arguing about and what each does across the window, and the scale table — and `-- drink fist|body` is the picture, three fists close or six whole Bogs across the channel. **In the gate** twice, headless — forty seconds for `measure` and four for `hilt` |
| `tools/weapon_select.tscn` | the lobby weapon pick as a **roster row** (D-069): the default for a row that never heard of weapons, a request through the host and back on the rebroadcast, a bogus ordinal refused into a spear, the lock the moment Start is pressed, three rematches keeping it, the real lobby's shape since D-107 (strip and panels up together, no collapse button, the fold defaults, the count live behind a fold, both toggles dropping to `SHRINK_END`, the chat's three states and a submit that keeps the caret, and a second lobby instanced as a client with the config gone), and three **remote** backdrop Bogs each holding only what its row says — and, since D-070, *standing* in only what its row says: the ring asserts each Bog's `carry_pick` is pointing at its own weapon's pose, and that a change of pick moves the stance on the same call that moves the prop. Since D-109 the same `lobby` stage also drives the **skin** strip — a free-for-all pick round-tripping through the roster and coming back on the Bog in the ring (read off `get_active_material`, so it is what the renderer will draw), two teams starting in different bodies, a pick moving the *team's* entry and not the picker's own row, the other team's swatch disabled and a request for it refused at the host, a team switch as a change of clothes with nothing sent, and the ring's ceiling re-measured at eight Bogs and at five so a taller swatch cannot creep back over their faces. 184 checks. The half that is a *Bog* — the gate, the hand and the three overrides — is `match_rules`. **In the gate**, headless |
| `tools/team_tint.tscn` | every Bog's body is in its team's nameplate colour, free-for-all is the body's own imported colour, the Elder's robe stays purple, a corpse keeps its colour, and a lobby team switch repaints the Bog (D-046). **In the gate**, headless; through `snapshot.gd` it renders the lineup |
| `tools/letter_carriers.tscn` | a letter card that starts a hold puts "Name picked up G" in the feed and a wasted duplicate puts nothing; carriers behind a wall, enemy included, have a gold card marker over their heads drawn through it and above the nameplate, your own hold marks nothing on your screen, and the marker goes on bank and on death; the same in free-for-all (`-- ffa`) (D-050). **In the gate**, headless; through `snapshot.gd` it renders the Bog's own view with the feed |
| `tools/capture_preview.tscn` | a Capture B·O·G match in the real arena: both team bases drawn, three letter cards at home, every Bog on its own team's pad (D-051). **In the gate** on Kopje Crossing, headless; takes a map id; through `snapshot.gd` it renders the view from above Team 1's base. The mode's rules are `match_rules`, and the base/letter layout on every map is checked by `playthrough` |
| `tools/map_thumbs.tscn` | the lobby carousel's seven 480x270 map photographs (D-162), baked through the real `arena.tscn` into `art/generated/map_thumbs/<id>.png` from each `MapCatalog` row's `thumb_camera`. **Not** in the gate and **not headless**. `"$GODOT" --path . --resolution 960x540 tools/map_thumbs.tscn` (a trailing `-- quarry` does just that map; `-- <id> candidates` sweeps angles into `out/`), then `--import` |
| `tools/range_views.tscn` | Highsun Grounds at eye height, with the range's items built (which `preview_map` does not). Its `probe` view stands a Bog-sized capsule on all eight pads and walks one out from every rack: no pad blocked, no pad arming a swap, and the depth of floor in front of each rack (D-161). **In the gate** as a snapshot |
| `tools/shoulder_shots.gd` | `snapshot.gd` with the aim button held from frame 0 and a crosshair painted at centre, for choosing the aiming shoulder from renders (D-159). Not in the gate |
| `tools/fps_readout.tscn` | the FPS readout (D-148): off out of the box, following the Settings toggle in both directions with a real frame rate in it, kept by `settings.cfg`, and hidden whenever a render tool has set the suppression flag, so no `preview_*` shot carries it. **In the gate**, headless, about five seconds |
| `tools/preview_plate.tscn` | the nameplate against the head (D-150): twelve moments of eighteen clips, the name 0.120 m clear of the crown at its tightest (`RunJump`) and the lift a flat 0.000 m in every ground clip. **In the gate**, headless; `sheet <Clip>` through `snapshot.gd` draws the picture |
| `tools/combat_range.tscn -- emote` | the Y key pressed for real (D-155): start, stop, start again off `Bog.emoting`, the `Twerk` blend reaching full and the joints travelling, and a step ending it. **In the gate**, headless |
| `tools/team_plates.tscn` | a teammate's nameplate is drawn through a wall and never fades, an enemy's beside it is occluded and faded as before, the HUD chip says which team you are on, and free-for-all plates are unchanged (`-- ffa`) (D-047). **In the gate**, headless; through `snapshot.gd` it renders the Bog's own view |
| `tools/ragdoll_stability.tscn` | a corpse is still a corpse 150 ticks later |
| `tools/combat_range.tscn` | the real match path: a spear, a shield, a magnet, a letter, the Elder's bolt |
| `tools/net_loopback.tscn` | two processes, one socket, including a *client* using all three abilities, dying and respawning, a weapon picked on the client and decided by the host (D-069), and ten rematches with the client in the lobby for half of them (D-044). **In the gate** through `net_test.sh`, bound to 127.0.0.1 on a random port |
| `tools/preview_map.tscn` | Rust, Kopje Crossing, Lantern Wharf and Halcyon Wake: renders one, and checks every spawn pad with the physics. **In the gate** for all four |
| `tools/island_report.tscn` | Whisperbloom Hollow as numbers: footprint, slope, every scatter layer's placed count, tree heights, spawn spacing and the capture bases (D-055). **In the gate** on four seeds |
| `tools/parkour_report.tscn` | every platform on a built map has its rock, fits a Bog, and is reachable from the ground (D-042); on Lantern Wharf also that no jump reaches a tower or wall top, no sightline runs past 25 m (26 m from a roof), and no pad sees the other base's pads (D-056); on Halcyon Wake every deck reachable, the mast out of reach, sightlines under 21 m on the main deck and 38 m from a landing, and nothing but the void over every edge of the deck (D-057). **In the gate** for all three |
| `tools/bake_tiles.gd` | the ability bar's seven tiles, photographed from the real `.glb`s under one camera, one light rig and one framing rule — the geometric mean of a silhouette's on-screen width and height is 66% of the tile, capped at 88% on the longer side, slender props laid on the diagonal (D-076). `-- check` re-measures the **committed** PNGs and is **in the gate**, headless, because what has to hold on every machine is that the pictures in the repository obey the rule rather than that this machine's GPU can reproduce them; `-- sheet` writes `out/tiles_sheet.png`, the seven side by side, which is the only way to answer "do they read as a set" |
| `tools/combat_range.tscn` | the real match path: a spear, a mushroom, a lure, a letter, the Elder's bolt |
| `tools/net_loopback.tscn` | two processes, one socket, including a *client* using all three abilities, dying and respawning, and ten rematches with the client in the lobby for half of them (D-044). **In the gate** through `net_test.sh`, bound to 127.0.0.1 on a random port |
| `tools/preview_map.tscn` | Rust, Kopje Crossing, Lantern Wharf, Halcyon Wake and Twin Quarry: renders one, and checks every spawn pad with the physics. **In the gate** for all five |
| `tools/island_report.tscn` | Whisperbloom Hollow as numbers: footprint, slope, every scatter layer's placed count, tree heights, spawn spacing and the capture bases (D-055). **In the gate** on four seeds |
| `tools/parkour_report.tscn` | every platform on a built map has its rock, fits a Gub, and is reachable from the ground (D-042); on Lantern Wharf also that no jump reaches a tower or wall top, no sightline runs past 25 m (26 m from a roof), and no pad sees the other base's pads (D-056); on Halcyon Wake every deck reachable, the mast out of reach, sightlines under 21 m on the main deck and 38 m from a landing, and nothing but the void over every edge of the deck (D-057); on Twin Quarry that each team's bench is reachable from the pit floor by its two haul ramps and by nothing else, that no jump reaches a 10.2 m column top or the rim, and that no sightline runs past 30 m on the floor or 43 m from a landing (D-082). **In the gate** for all four |
| `tools/clip_check.gd` | the rebuilt character's import layer (D-095): the body 1.80 m tall with its feet on the floor and 49 bones, every row of `clips.json` in the shared library, every track of every clip on a body bone with the hips locked to the axis, the loop mode from the table, and four clips from four suites posing the body within 0.12 mm of where their own skeleton poses it. **In the gate**, headless, about ten seconds |
| `tools/preview_bog.tscn` | the rebuilt body playing clips from the library, six BOGs across a clip, one row per clip key — the sheet the clip choice is made from |
| `tools/skin_thumbs.gd` | the picker's fourteen 128² tiles, rendered rather than painted (D-109): one BOG in `Idle`, the camera aimed off `mixamorig_Head`, one shot per skin, the centre square cut. **Not** in the gate and **not headless** — it needs a real window to render into. `"$GODOT" --path . --resolution 512x512 --script tools/skin_thumbs.gd` (a trailing `-- muck rime` does just those), then `--import` so Godot sees the new PNGs |
| `tools/preview_*.tscn` | it *looks* right. Needs a person, always will |
| `tools/nav_check.tscn` | every map bakes a navmesh from its layer-1 colliders and walks a route from the first pad to the last; prints the census per map — polygons, links, bounds, route length and how many leaps it took (D-130). **In the gate**, headless, every map in turn; `-- <map id>` for one |
| `tools/preview_capture.tscn` | the capture performance measured on one Bog: pouch in the left fist, no card in the right, the pouch mouth below the raised hand, the floating letter on the line between them; prints both anchors and the descent in world metres so the pouch grip can be read off a render (D-131). `-- f=0.5` freezes the fraction. **In the gate** headless and as a snapshot |
| `tools/grip_poses.tscn` | writes `art/generated/grip_poses.res` — five one-frame finger poses measured out of the clip library — and prints how far each closed hand sits from the open one (D-134). Runs after the import; **commit what it writes**. **In the gate**, headless |
| `tools/hud_range.tscn minimap` / `tutorial` | the corner map's blips counted off `Minimap.debug_counts()` — an ally, a loose card and an enemy carrier, and no enemy without a letter — and the how-to-play cards opened once, marked seen on close, reopenable (D-132). **In the gate** as snapshots |
| `tools/ui_range.tscn menu_letters` / `lobby_letters` | the menu's letter row and the hero's capsule projected into frame fractions and required not to overlap; the same rig in the lobby required inside the panels' band and below every ring Bog's head (D-133). **In the gate** as snapshots |

**`playthrough` is the one that catches integration.** Every other harness looks
at a single seam, and a defect that lives *between* two of them is invisible to
all of them — which is exactly what happened when `feat/island` and `feat/ui`
merged cleanly into a game with no HUD (D-018). Add to it whenever you add a
screen to the flow.

```bash
# Render any scene to a PNG and quit. The number is PHYSICS TICKS (D-012).
"$GODOT" --path . --resolution 1600x900 --script tools/snapshot.gd -- \
    res://tools/preview_island.tscn out.png 150 shrine

# The island with the HUD over it, which is the only way to judge the two together
"$GODOT" --path . --resolution 1600x900 --script tools/snapshot.gd -- \
    res://tools/preview_island.tscn out.png 150 wide match hud
```

`preview_island` views: `wide under eye eye0..eye7 shrine grove arch bridge
spawns hollow top canopy tree`,
plus `match` for real Bogs and the diagnostic flags in its `FLAGS` dictionary.
`ui_range` modes: `menu menu_join menu_notice settings settings_network lobby
lobby_full lobby_teams lobby_client lobby_map lobby_capture lobby_weapons
lobby_skins lobby_ffa_skins lobby_chat lobby_feel widths capture_config`. The last two print a verdict and sit in the
gate (D-076): `widths` puts every slider in the match panel at the value that
renders its own unit widest, under every win condition, and fails if any track
is under 180 px — 245 rows, narrowest track **448 px**, and it read **zero**
for `bow_drop_full` before that entry;
`capture_config` drives the capture sheet through its real buttons, copies to the
real clipboard, reads it back and prints the whole payload. `lobby_feel` is the
same worst-label config, photographed. `lobby_map` scrolls the Match
panel down to the Map section, which is the only way to photograph it — the panel
scrolls and the section is below the fold at every size the game runs at.
`lobby_weapons` no longer presses a collapse button — there is no surface to
collapse to since D-107 — so what is left of it is the part that was doing
the work: it deals all three weapons into one shot, three buttons in the
strip and three pairs of hands in the ring above it. `lobby_chat` is the
panel whose open state is not a boolean, photographed with the caret in its
input box. `lobby_skins` is Teams — two teams in two bodies, the local player
on one, the other team's swatch disabled — and `lobby_ffa_skins` is six
stand-ins in six bodies; **only those two deal skins**, so every other lobby
mode leaves the roster's `skin` key alone and the reference shots that predate
the picker stay comparable with themselves. Every lobby mode now deals its
stand-ins different weapons, so any of them is also a shot of the ring
carrying three things at once. `hud_range` modes:
`hud hud_teams hud_cooldown hud_letters hud_hold hud_elder killfeed scoreboard
scoreboard_letters pause results results_letters dead spectate hud_letters_teams
scoreboard_letters_teams results_letters_teams reload_timer weapon_tiles`. The
last two are the two that print a verdict and sit in the gate: `reload_timer`
measures the recharge sweep against the real clock (D-054), and `weapon_tiles`
stands the same HUD up under three loadouts and an Elder and requires the first
square's glyph, caption **and key cap** to follow the pick (D-069).

**A trap worth knowing in `zsh`:** unquoted `$args` is not word-split, so passing
several trailing arguments through a variable silently sends them as one string
and the tool quietly uses its defaults. Pass them literally.

---

## Known issues


Five more are limitations of the source art rather than faults in the code, and
D-029 argues each one out rather than pretending it is fixed:

- **`CrouchWalk`'s feet slip 53%** at the game's crouch speed (Walk 9.4%, Run
  16.3%). The clip is authored at 1.273 m/s and would need its rate nearly
  doubled to plant, for 0.17 m/s of gain.
- **`JumpTwo`'s ground roll is authored below the floor** — the skin reaches
  0.247 m under the plane in the clip's first 0.15 s of roll. Those hips keys
  sit below the clip's first key, so the pipeline's vertical rule cannot lift
  them; `ROLL_CLIP_START` is 1.62 rather than the 1.48 the air scrub hands over
  at, which skips the most-sunk stretch (within 0.10 m of the floor from there)
  at the cost of the first two frames of the tumble. A few centimetres of
  sinking remain through the rest of the roll.
- **The nameplate crosses the model at dive apex.** The plate is pinned to the
  capsule at 1.80 m while `JumpTwo` keeps a 0.618 m pelvis rise. The fix is to
  offset it by the model's own head height, in `scripts/player/nameplate.gd`.
- **A sliding Bog is hard to hit.** The slide capsule is vertically right but a
  vertical capsule cannot follow a prone body whose head is half a metre forward
  of the axis.

One thing two reviewers flagged is settled: **`ROLL_LOCK` is a ground rule.**
A Bog that rolls off a ledge inside the 0.45 s lock used to keep the lock in
the air — no air control, `ROLL_FRICTION` (10.0) instead of `AIR_FRICTION`
(1.5). `_tick_timers` now zeroes `_roll_lock` the moment the feet leave the
floor, so the fall is an ordinary fall. Whether the lock itself (0.45 s of no
input after a dive landing) feels right is still a play-test question; it is one
constant and 0.0 turns it off.

---

## Things worth knowing that are not obvious from the code

- **When in doubt, open a ragdoll joint up.** A cone-twist driven past its limit
  adds energy rather than clamping. Too floppy looks rubbery; too tight explodes.
  That is true of the limit's *strength* as well as its span:
  `joint_constraints/bias` went 0.25 to 0.10 in D-153 and the corpse's peak
  speed halved, because a limit pushing back hard tears the two bodies apart at
  the joint before the point constraint can pull them back. Raising it, or
  raising the project's solver iterations, detonates the corpse. The elbow
  still separates 0.081 m at worst, and `ragdoll_stability` settles at 1.45 m/s
  against its 1.5 limit.
- `MAGNET_GRAVITY` in `bog_combat.gd` must equal `Magnet.GRAVITY`. The arc is solved
  in one file and flown in the other (D-014).
- **The Bog is authored at 1.80 m and imported at `root_scale 1.0`** — the whole
  model, skeleton included, is in metres, so a bone attachment offset and a
  ragdoll capsule radius mean what they say. Never scale the model node instead:
  a scaled `Skeleton3D` gives scaled rigid bodies and the capsules stop matching
  the mesh. (The old asset was imported at 0.35; that is D-002, and D-029
  replaced it.)
- The Bog mesh is authored facing **+Z**; `bog.tscn` turns the model 180° so
  `body_yaw` means "the way the Bog is looking" in Godot's -Z-forward convention.
- Ragdolls are local and cosmetic and deliberately **not replicated** (D-010).
- **Game speeds and clip speeds are separate numbers, and the animator divides
  them.** `Bog.WALK_SPEED` / `RUN_SPEED` / `CROUCH_SPEED` are gameplay choices;
  each clip's `authored_speed` is what `tools/import_clip.gd` measured off its
  hips at import and stored as metadata on the clip. Each locomotion node
  plays at `game / authored` in its own custom timeline, which is what keeps
  the feet planted. Change a game speed freely; the authored one re-measures
  itself on the next import (D-029, D-095).
- **Mixamo's aim-strafe families are handed** — every right strafe in every
  pack is a −37 to −47 degree diagonal, while its left twin can be a true
  lateral (D-071). The rebuilt library has no mirrored clip yet, so the
  running strafes are diagonal poles blended by the plane and slide at 1.12
  of body speed; the fix is the Magic pack's `Standing Run Left` plus a
  `mirror_of` rule in `clips.json` (D-098, PLAN 8.8).
- **Nothing in the animation tree runs a clock it does not own.** Every node is
  either a looping cycle, a OneShot that restarts on fire, or scrubbed every
  frame — because an `AnimationNodeAnimation` sitting in a blend runs from tree
  start and freezes on its last frame, which is what broke the old jump and
  slide (D-026, D-029).
- Sound placement encodes a rule: **3D means an event in the world that gives
  your position away; 2D means feedback only you could have** (D-016).
- `queue_free()` is deferred. A `while` loop that frees a child and re-reads
  `get_child_count()` never terminates; that hung the whole game on the sixth
  death of every match and is written up in the commit that fixed it.

---

## Git

**Everything is on `main`, and `main` is the only branch.** `feat/complete-game`
was merged (a fast-forward — it already had `origin/main` as an ancestor) and
then deleted, locally and on the remote, along with `feat/island` and `feat/ui`,
which were ancestors of both integrations and had nothing left in them.

Two tags mark the ends of that work:

| tag | what it is |
|---|---|
| `pre-merge-baseline` | the last commit before the two feature branches landed — use it to see what each side looked like on its own |
| `v0.1.0` | the release: both binaries built, `smoke_test.sh` 10/10 |

The repo is **https://github.com/CarlMenke/BOG** (public), owned by
CarlMenke, with JulianC775 as a collaborator, so plain `git push` works. If it
ever 403s, check that first:

```bash
gh api repos/CarlMenke/BOG --jq '.permissions'
```

Start the next piece of work on a branch off `main`.
