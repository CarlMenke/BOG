# Feel round, 2026-09-18

Thirteen pieces of playtest feedback, grouped by the code they touch and by the
feel they are after. Each group is one Opus agent. Decisions are fixed here;
agents implement, measure and report. The gate is `bash tools/smoke_test.sh`.

Working rules for every agent in this round:

- **Own only the files your group lists.** A change you need in somebody else's
  file is reported back, not made. `docs/DECISIONS.md`, `docs/STATUS.md`,
  `docs/PLAN.md` and `docs/ARCHITECTURE.md` are written by the integrator at
  the end: return your decision-record text (no number) instead.
- `tools/smoke_test.sh`: edit only the lines of the checks you own, and add new
  checks as one contiguous block named for your group.
- The Tripo Bridge addon rewrites `project.godot`'s `last_cleanup` every Godot
  run: `git checkout project.godot` afterwards unless you changed it on purpose.
- New `class_name` scripts and new clip rows need `--import` before headless
  tools parse. Imports are slow: run them in the background with a long timeout.
- One home per concern (D-098 and the rebuild): clip feel in `clips.json` and
  `tools/import_clip.gd`, event timing as markers on the clip, state in
  `bog_animator.gd`, grips solved by `tools/preview_carry.gd` and pasted into
  `held_gear.gd`, lobby view state through `_refresh` (D-069). Do not tack
  things where they are convenient.
- Numbers are measured, not eyeballed: a render, a headless tool line or a gate
  check backs every claim in your report.

## Group 1 — the range at sunset (`range`)

Owns: `scenes/world/maps/range.tscn`, `scripts/world/maps/range_map.gd`,
`scripts/world/maps/range_ambience.gd`, `resources/config/range_env.tres`,
`resources/config/range_sky.tres`, a new `resources/shaders/range_sky.gdshader`
if one is needed, `scripts/world/range/range_director.gd`,
`scripts/world/range/station.gd`, `scripts/world/map_catalog.gd` (the range row
only), `tools/preview_map.gd` (range views only), the range checks in
`tools/smoke_test.sh`. Not `safari_sky.gdshader` or `enchanted_sky.gdshader`:
Kopje and the Hollow own those; fork, do not edit.

1. **Sunset, not night.** The brief is the phrase *cotton candy skies*: a low
   warm sun, towering cumulus lit pink and peach from below, lavender and
   periwinkle shadow sides, a sky that runs from apricot at the horizon through
   rose to a soft blue overhead. Real clouds, not a flat sheet: start from
   `safari_sky.gdshader`'s ray-marched cumulus (D-061) and tune it for golden
   hour, forked as `range_sky.gdshader` so Kopje is untouched. Sun elevation
   about 9 degrees, azimuth **north-north-east** (about 30 degrees east of
   north): the glory sits ahead-right of every lane and shadows run
   south-south-west along the lanes rather than across them (the 8 m west bank
   must not throw a shadow over the map; D-113's argument still holds, re-run
   it for the new azimuth). The sun must not sit exactly at the lanes'
   vanishing point: an archer at the firing line looking down the long lane
   should see sky glory, not a disc in the crosshair.
2. **Ground reads.** Ambient is 100% sky-derived (`ambient_light_source = 3`),
   so retuning the sky retunes the ground. Target: peat at the far end of the
   bow lane (45 m) clearly visible in a `preview_map` pad render, no black
   bottom half. Re-measure `ambient_light_energy` against the new sky; it will
   not stay 8.0. Warm the peat/timber/stone albedos only if the sky alone does
   not get there.
3. **Lanterns and glowworms at dusk.** Keep them, dimmer and warmer: this is the
   hour they come out. Torches stay lit. Fog thinner and warmer.
4. **Dividers much shorter.** The lane fences and the bow-lane rails become a
   single rail at **0.60 m** (thigh height, a hop clears it, a standing Bog sees
   over it from anywhere). Posts stay 2.2 m to carry the lanterns. Same for the
   bow lane's two lines. Cover blocks stay 1.25 m: those are meant to hide a
   pop-up.
5. **No stations.** Delete the six glowing signposts and the walk-near cycling.
   Dummies default to a fixed behaviour by area, authored in the `DUMMIES`
   table and marker meta: lane 1 (west) all `stand`; lane 2 `strafe`; lane 3
   `patrol` at 8 and 22 m with a `popup` behind the cover block at 15 m; bow
   lane `stand` at 45 m; gallery unchanged (3 `popup`, 2 `strafe`); melee pit 2
   `circler` + 1 `rusher`; yard 3 `stand` + `wanderer` + `jumper` (the reserved
   ones become live); parkour summit `stand` live. `RangeDirector.RINGS`,
   `cycle_zone`, `reset_zone`, `_reserved` and the station RPC go. Stats reset
   becomes a plain timber signboard on the deck with a carved STATS label and an
   `Area3D`: no lantern, no light, no chime. The census line the gate greps
   changes; update it (27 dummies all live, and say in the report whether the
   signboard counts as a station or as nothing).
6. **Verification.** Re-render `preview_map` `top`, `side`, `pad0..pad7` at eye
   height to `tools/showroom/out/range_sunset/` and look at every one. Gate
   blocks: range playthrough, dummy brains (station sub-check goes), range items,
   range targets, range spawns and collision, range parkour. All green.

## Group 2 — the character page keeps its spot (`lobby`)

Owns: `scripts/ui/bog_backdrop.gd`, the `lobby_character` mode of
`tools/ui_range.gd`, `tools/weapon_select.gd` if its band checks need it.

- `PORTRAIT_STEP` and its rationale go. The subject stays on the ring, facing
  the camera as D-111 placed him, lit by the fire from the front.
- While `_focused`, every Bog except `_local_slot` is hidden on this client
  only: a `_bog_wanted(index)` mirroring `_plate_wanted`, applied to all slots
  from `focus_on_local`. Nameplates as now.
- Re-derive the portrait framing for a subject at radius 3.0 rather than 0.2:
  `PORTRAIT_YAW`, `PORTRAIT_SUBJECT_X`, margin. The face must be lit, the
  weapon in frame, the fire not across the chest. Snapshot `lobby_character`
  and `lobby_skins` at 1600x900 and read them. `weapon_select` and `widths`
  gate checks green.

## Group 3 — the bow off the face (`bow`)

Owns: `scripts/items/held_gear.gd` (bow constants and `bow_basis` only),
`tools/preview_carry.gd`, `tools/preview_bow.gd`, the carry checks in
`tools/smoke_test.sh`.

- At rest with the bow (`BowCarry` layered over Idle/Walk/Run) the top limb
  passes through the nose. D-110 squared the head into the limb's path and the
  bow was re-solved against the floor only (`skin_floor` is 0 for the bow).
- Give the bow a head clearance in `preview_carry -- measure`: nearest distance
  from the limb segment to the `Neck`/`Head`/`HeadTop_End` bones and to the
  head's skin vertices, minimum **0.06 m**, asserted like the spear's
  `SKIN_MIN`. Make `-- candidates` take the weapon so it can sheet the bow.
- Re-solve `CARRY_TILT` (and `BOW_GRIP_ROTATION`/`OFFSET` only if the tilt
  alone cannot) so the bow clears the face by at least 0.06 m and the floor by
  at least `CARRY_MIN` in Idle, Walk and Run, layered. Judge the bearing by eye
  off a front + side sheet as D-103 did, and include the sheet paths in the
  report.

## Group 4 — hit markers that land (`hitmarker`)

Owns: `scripts/ui/crosshair.gd`, `scripts/ui/hud.gd` (`_on_hit_landed`,
`flash_hit` and the `HIT_MARK`/`KILL_MARK` constants only), `tools/make_sfx.py`
(`hitmarker` and one new effect), `scripts/util/audio_director.gd` (one const),
`scripts/game/match_state.gd` (the two `play_2d(HITMARKER)` lines only),
`audio/sfx/hitmarker*.wav`, `tools/hud_range.gd` (the strike it freezes).

- The marker exists (D-116) and is too quiet to notice in play: 2 px arms
  9..17 px, 0.4 s fade. Make it unmistakable without making it loud: arms 3 px,
  a snap-in from 1.4x to 1x over the first 70 ms then the fade, hit 0.45 s.
  Vocabulary stays: `UIPalette.BOG` yellow = hit, white = kill, amber = range
  target.
- A kill is a bigger event: arms extend to a full X through the centre gap,
  held 0.6 s, and a second sound `hitmarker_kill.wav` (lower, a hair longer)
  played where `_apply_death` plays `HITMARKER` today.
- Every damage path already reports through `report_damage`; confirm sword,
  spear, arrow and lightning each flash in `tools/playthrough` and say so.

## Group 5 — movement (`movement`)

Owns: `scripts/player/bog.gd`, `scripts/player/bog_camera.gd`,
`scripts/player/bog_animator.gd` (slide-jump only), `scenes/player/bog.tscn`
(one replicated field), `assets/source/clips.json` (one row), movement checks
in `tools/smoke_test.sh`, `tools/playthrough.gd` (movement assertions). Group 6
edits the same files **after** this group reports, so finish cleanly and do not
leave half-made hooks.

1. **Slower at full draw.** In `target_speed()`, scale by
   `lerp(1.0, DRAW_SPEED_SCALE, draw_fraction())` with `DRAW_SPEED_SCALE = 0.5`.
   Works for remote Bogs off `sync_draw` already. Fix the stale `AIM_SPEED_SCALE`
   comment in the animator. Confirm the aim plane still reads at 1.15 m/s.
2. **Camera closer.** `DISTANCE_DEFAULT` 3.6 to 3.1, `DISTANCE_AIMING` 2.4 to
   2.15, shoulders unchanged. Check the probe still clears walls in
   `tools/playthrough` and the HUD renders.
3. **Slide-jump.** Jumping during a slide is its own move: horizontal speed
   `max(current, SLIDE_SPEED) * 1.2` along the slide direction, jump impulse
   x 1.12, then normal air control. Replicated as `sync_slide_jump_serial` so
   remote animators see it. New clip role `SlideJump`, a `clips.json` row with
   `mixamo_query: "flip"` (candidates fetched, the owner picks) scrubbed by the
   arc exactly like `RunJump`; until the FBX exists the animator falls back to
   `RunJump` for that role with a single `push_warning` at `_ready`, never per
   frame. `REQUIRED_CLIPS` must not fail the gate on the missing clip.
4. **Crouch into a slide.** Drop `wants_sprint` from slide entry: crouch held
   at or above `SLIDE_ENTRY_SPEED` on the ground starts a slide. Crouch held in
   the air pre-arms: the crouch pose blend may rise airborne (pose only, capsule
   and headroom unchanged), and when a slide begins on the landing tick the
   animator skips `Land`/`LandHard` and fades the `Slide` one-shot in from the
   air pose. The dive roll keeps priority; a hard landing (11 m/s or more)
   still hard-lands.

Measure: a `tools/playthrough`-style headless check that a slide-jump leaves at
the expected speed, that a landing with crouch held at run speed is sliding on
the next tick, and that full draw walks at 1.15 m/s.

## Group 6 — fists, the emote and the sword (`combat`), runs after 4 and 5

Owns: `scripts/player/bog_combat.gd`, `scripts/player/bog.gd`,
`scripts/player/bog_animator.gd`, `scenes/player/bog.tscn`,
`assets/source/clips.json` (one row), `project.godot` (one input action),
`scripts/ui/hud.gd` (weapon tile only), `scripts/ui/ability_slot.gd`,
`scripts/game/match_config.gd` (sword dials), `scripts/game/loadout.gd`,
`tools/playthrough.gd`, `tools/weapon_select.gd`, combat checks in
`tools/smoke_test.sh`.

1. **Hands out.** Key **H** (`holster`) toggles `sync_holstered` on your own
   Bog (ON_CHANGE, owner-written, like `sync_draw`). Holstered: no prop in
   hand, the `stand` plane with the `Idle` carry, `target_speed() x 1.10`
   (`FISTS_SPEED_SCALE`), `has_spear/bow/sword` false, LMB punches. Refused
   while busy, drawing, holding a letter or emoting. The HUD weapon tile keeps
   the picked weapon's photo at the 20% "not ready" level with the key cap
   reading H, so it says "put away".
2. **Punch.** `PUNCH_DAMAGE = 20`, reach 1.1 m, half-arc 50 degrees, cycle
   0.5 s, hit at the clip's `hit` marker, upper-body one-shot so you keep
   moving and turning at full speed. Relay it with the sword's four-function
   shape; the host checks the attacker is holstered. `weapon_launched("fist")`;
   the range stats panel ignores fists. New clip role `Punch`, a `clips.json`
   row with `mixamo_query: "punch"` (candidates fetched, the owner picks); until
   the FBX exists the animator uses `Cast` for the role with one warning at
   `_ready`.
3. **Emote empties the hands.** While `emoting`, every `_wants_*` is false and
   `_tick_hand` agrees, so the prop vanishes for the dance and returns after.
4. **The sword, less committing.** The primary click becomes a three-slash
   chain on `SwordCombo` (`swing_N/hit_N/end_N` markers): click for slash 1,
   click again before `end_N` + 0.15 s for the next, damage **50** per slash
   (two connect to kill), reach = `sword_reach` dial + 0.35 m step, upper-body
   layer over the sword plane at `SLASH_SPEED_SCALE 0.85` with turning and
   jumping allowed. `sword_recharge` (default 0.8 to 0.5) now runs between
   chains. `SwordSpin` stays as the **sprint attack**: clicking at or above
   0.8 x `RUN_SPEED` fires the spin as today, 100 damage, fully committed.
   Remote peers run the chain from a serial + slash index.

Measure in `tools/playthrough`: a punch deals 20, a holstered Bog walks 10%
faster, two slashes kill, a sprint click spins, the dancer's hand is empty.

## Integration (the orchestrator)

Gate green, `net_test` by hand, the decision records numbered from the tip of
`DECISIONS.md`, STATUS/PLAN/ARCHITECTURE updated, a fresh
`build/windows/BOG.exe`. The owner then pastes `python tools/mixamo_fetch.py`
into the Mixamo tab once for the `SlideJump` and `Punch` candidates.

## Landed

> **LANDED, 2026-09-18, as D-119..D-124.** All six groups are built and in the
> gate, in the order they are written above: **D-119** the range at golden hour
> with thigh-high dividers and no stations, **D-120** the character page's Bog
> keeping his place on the ring, **D-121** the bow's carry re-solved on a map
> with a head clearance to measure it against, **D-122** the hit marker and the
> kill's own shape, **D-123** the draw's speed cost, the closer camera and the
> slide you crouch into and jump out of, **D-124** the holster, the fist, the
> empty-handed dance and the sword's chain. `docs/PLAN.md` Phase 10 carries the
> item-by-item state and `docs/ARCHITECTURE.md` says where each piece lives.
>
> **Two clips are stand-ins.** `SlideJump` is drawn with `RunJump` and `Punch`
> with `Cast`, through `BogAnimator.clip_or`, each with one `push_warning` at
> `_ready` and neither in `REQUIRED_CLIPS`. The owner finishes them: `python
> tools/mixamo_fetch.py` pasted into the Mixamo tab, a take chosen from the
> `"flip"` and `"punch"` candidates, `bash tools/clip_imports.sh`, an
> `--import`, then `lift`/`apex`/`land` and `hit` placed with
> `tools/clip_events.gd`.
>
> This document is kept as written — it is the scope the six records were
> argued against, and the decisions fixed in it are the ones the agents were
> not free to re-take.
