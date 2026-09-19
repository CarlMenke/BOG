# The letters round, 2026-09-18

One letters game, two flavours, and everything around it: the guide line, the
capture performance, the minimap, the tutorial, the menu's real letters. Each
group below is one Opus agent. Decisions are fixed here; agents implement and
report. **Nobody runs Godot or the gate in this round** — the integrator imports
and runs `bash tools/smoke_test.sh` once at the end, so write the code complete
and write your gate lines into your report rather than into `smoke_test.sh`.

## The core truth (decided by the owner, 2026-09-18)

**There is one letters game, called B·O·G.** Its Free-for-all form is the
collect race (`WinCondition.LETTERS`): letters fall out of corpses, one at a
time, you capture one by standing with it, first to hold B, O and G wins. Its
Teams form is capture-the-flag (`WinCondition.CAPTURE`): three cards at home
points, bases, vaults, steals — exactly as D-051/D-068/D-092 built it. The
Match type switch is what picks between them; the "Ends on" picker offers a
single **B·O·G** entry. Both ordinals stay on the wire (the enum is append-only).
Teams + pooled-collect (D-049) is no longer reachable from the UI; its code
stays because Capture uses the pooling.

What applies to which flavour:

| piece | FFA collect (LETTERS) | Teams capture (CAPTURE) |
|---|---|---|
| one letter alive at a time, B→O→G cycle | yes | no — three cards at home, as today |
| guide line | yes, one target | yes, up to three, trunk-merged |
| capture performance (arm up, pouch, letter descends) | yes — a hold with a clock | no — a carry keeps the card in the fist and runs |
| steal performance (arm up, card rises out of the vault) | — | yes |
| sunburst + chime when a letter is banked | yes | yes (bank and steal) |
| minimap | yes | yes, plus bases/vaults |
| tutorial | yes | yes, one Teams card |

## Working rules for every agent

- **Own only the files your group lists.** A change you need in somebody
  else's file is written into your report under "asks", not made. Two agents
  in one file is a merge nobody can do.
- **Do not edit** `tools/smoke_test.sh`, `project.godot`, or anything under
  `docs/`. Return your gate `check`/`also` lines and your decision-record text
  (no D-number) in the report; the integrator lands both.
- **Do not run Godot.** No `--import`, no headless tools, no snapshots. Python
  for maths and for `tools/make_sfx.py` is fine. Write complete, self-consistent
  code; the integrator runs the gate once and fixes what it finds.
- **Code to the contract below.** Other groups' new API exists by the time
  anything runs. Name things exactly as written here.
- Match the house style: `##` doc comments that say *why*, one home per
  concern (D-098), measured constants with the reason beside them, Mixamo bone
  names with the `mixamorig_` prefix, `queue_free` never inside a loop that
  re-reads `get_child_count()`.
- New `.gd` files need no `.uid` — the import writes it.
- Windows: write files as UTF-8 with LF line endings.

---

## The contract — new API every group may rely on

### `MatchState` (Group A)

```gdscript
signal letter_appeared(letter: int, at: Vector3)   # every peer, when a LETTER pickup lands (any mode)

func letter_active() -> bool            # a live untaken LETTER pickup exists, or any hold row exists
func next_letter() -> int               # host: the cycle head, LETTER_B first every match
func letter_hold_fraction(peer_id: int) -> float   # 0..1 of a timed hold; 0.0 for a carry or no hold
func letter_hold_total(peer_id: int) -> float      # seconds of the hold; INF for a carry; 0.0 for none
func letter_hold_is_timed(peer_id: int) -> bool    # a hold row exists and its total is finite
func loose_letter_pickups() -> Array[Pickup]       # live, untaken LETTER pickups, every mode, vault cards included
func letter_carriers() -> Array[int]               # peers with a hold row, timed or not
```

The hold row becomes `{letter, ends_at, started_at, seconds}` — `_do_begin_hold`
already carries `seconds`, so `started_at = _now()` and `seconds` are written
beside `ends_at` on every peer with no wire change.

### `MatchConfig` (Group A)

- `letter_drop_chance` is **removed** — field, `_FIELDS` entry, export. The
  gate's `capture: fields` compares the settings sheet to `fields()` both ways.
- `_clamp_all`: **mode decides the flavour.** `LETTERS` under `TEAMS` becomes
  `CAPTURE`; `CAPTURE` under `FREE_FOR_ALL` becomes `LETTERS`. (Today CAPTURE
  forces TEAMS; that line goes.)
- `static func is_bog(condition: int) -> bool` — alias of `scores_letters`.
- `summary()` prints `B·O·G` for both ordinals (the mode is already printed).

### `UIPalette` (Group D)

```gdscript
const GUIDE_LOOSE := AMBER                          # a letter nobody holds: go take it
const GUIDE_ENEMY := Color(1.00, 0.36, 0.33)        # an enemy carries it: go kill them
const GUIDE_ALLY  := Color(0.45, 0.72, 1.00)        # a friendly destination: your teammate, or your vault
```

### `AudioDirector` (Group C)

```gdscript
const LETTER_APPEARS  := preload("res://audio/sfx/letter_appears.wav")   # soft bell, 2D, everyone
const LETTER_CAPTURED := preload("res://audio/sfx/letter_captured.wav")  # the sunburst's chime, 3D at the pouch
```

### `Tutorial` (Group D) — `scenes/ui/tutorial.tscn`, `scripts/ui/tutorial.gd`

```gdscript
class_name Tutorial extends CanvasLayer
func open() -> void
func close() -> void
func maybe_auto_open() -> void     # opens once per machine (Settings "tutorial_seen"), marks seen on close
signal closed
```
Instanced by the main menu and the lobby (Group E) as a node named `Tutorial`
with `unique_name_in_owner`, by path `res://scenes/ui/tutorial.tscn`.

### `NavBake` (Group B) — `scripts/world/nav/nav_bake.gd`

```gdscript
class_name NavBake extends Node3D          # added by arena.gd after the map; in group "nav_bake"
signal baked(msec: int)
func is_ready() -> bool
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array   # empty before baked
func outline_image() -> Image              # top-down rasterised walkable area, white on transparent
func bounds() -> AABB                      # world bounds the outline image maps to
func link_count() -> int
func polygon_count() -> int
```

### `HeldGear` (Group C)

```gdscript
func set_pouch(carried: bool) -> void       # the left fist's third object (bow, potion, pouch — exclusive, BogCombat decides)
func has_pouch() -> bool
func pouch_mouth_global() -> Vector3        # where the letter ends its descent
func hand_transform() -> Transform3D        # mixamorig_RightHand, global
func bow_hand_transform() -> Transform3D    # mixamorig_LeftHand, global
```

### `Settings.DEFAULTS` (Group D)

`"tutorial_seen": false`.

---

## Group A — the rules: one letter, the cycle, the B·O·G picker

Owns: `scripts/game/match_state.gd`, `scripts/game/match_config.gd`,
`scripts/ui/match_settings.gd`, `tools/match_rules.gd`,
`tools/letter_carriers.gd`, and **only the `letter_drop_chance` line(s)** in
`tools/combat_range.gd`.

1. **One letter at a time** (LETTERS only). In `_drop_loot`, when the condition
   is LETTERS: if `letter_active()` is false, the death drops `next_letter()`
   as the *whole* drop — no roll, no shield beside it — and the cycle advances;
   if a letter is active, the death rolls the ordinary table with the letter
   share at zero. `letter_active()` reads `_pickups` (live, untaken, kind
   LETTER) and `_letter_holds`. The cycle index lives beside `_letter_holds`
   and resets wherever `_letter_holds`/`_team_letters` are cleared for a new
   match. A re-dropped card (`_interrupt_letter_hold`) does not touch the
   cycle: it is the same letter coming back.
2. **The hold row** gains `started_at` and `seconds`; add `letter_hold_fraction`,
   `letter_hold_total`, `letter_hold_is_timed`, `loose_letter_pickups`,
   `letter_carriers`, `next_letter`. Emit `letter_appeared(letter, at)` from
   `_spawn_pickup` for every LETTER kind, every mode.
3. **`MatchConfig`**: remove `letter_drop_chance` everywhere (field, `_FIELDS`,
   the panel's slider, `match_rules`, `letter_carriers`, `combat_range`'s
   line). Rewrite `_clamp_all`'s coupling so the mode decides the flavour. Add
   `is_bog`. `summary()` says `B·O·G`.
4. **The picker.** `match_settings.gd`'s `_choice("win_condition", "Ends on", …)`
   becomes four entries: kills, last standing, the clock, **B·O·G**. The fourth
   writes `LETTERS` or `CAPTURE` by the current mode; `_apply_config` shows the
   B·O·G entry selected for either ordinal; `_push("mode", …)` no longer
   special-cases CAPTURE (the clamp does it). Under the picker, a note visible
   only when B·O·G is picked: *"Free-for-all races to collect B, O and G, one
   letter out at a time. Teams captures the letters home."* The
   `letter_hold_time` row shows under LETTERS as today, retitled **"Capture
   time"**; the Capture section shows under CAPTURE as today.
5. **Harnesses.** `match_rules.gd`: every `c.letter_drop_chance` line goes.
   Add one scenario `_run_one_letter_at_a_time`: FFA LETTERS, 3 players; kill
   → exactly one LETTER pickup appears and it is B; a second kill while it lies
   there → no second letter; claim it (hold starts) → a kill → still none; expire
   the hold → a kill → the next letter is O; kill the O-holder → the re-dropped
   card is O and the cycle head is still G. `letter_carriers.gd`: drop its
   dial line only; its three simultaneous holds go through `_spawn_drop` and
   stay legal.
6. Report: gate lines (the new scenario prints through `match_rules: PASS`, so
   likely none), decision text, asks.

## Group B — the guide line: navmesh, jump links, path, ribbon

Owns: new `scripts/world/nav/` (`nav_bake.gd`, `jump_arc.gd`, `jump_links.gd`,
`guide_path.gd`, `guide_targets.gd`, `guide_line.gd`), new
`resources/shaders/guide_line.gdshader`, `scripts/world/arena.gd`,
`tools/parkour_report.gd` (only to read `JumpArc`), new `tools/nav_check.gd` +
`tools/nav_check.tscn`.

The line is **local and cosmetic**: nothing replicates, every client paths for
itself, like a ragdoll. It is added by `arena.gd` on every peer.

1. **`JumpArc`** (`class_name JumpArc`, static): lift `_hop_reach`,
   `_leap_reach`, `_big_reach` and the apex/gravity derivations out of
   `tools/parkour_report.gd` verbatim, reading `Bog.RUN_SPEED`,
   `Bog.JUMP_VELOCITY`, `Bog.DIVE_FORWARD_SPEED`, `Bog.DIVE_UP_VELOCITY`,
   `FALL_MULTIPLIER 1.35` and project gravity. Add
   `static func arc_points(from: Vector3, to: Vector3, count: int) -> PackedVector3Array`
   — a parabola through both ends whose apex is the hop apex above the higher
   end. `parkour_report.gd` calls `JumpArc` instead of its own copies; its
   printed numbers must not change.
2. **`NavBake`**: on `_ready`, defer two physics frames (the static maps'
   collision is built in their `_ready`; see `_try_spawn_capture_letters`),
   then `NavigationMesh` with `cell_size 0.25`, `cell_height 0.2`,
   `agent_radius Bog.CAPSULE_RADIUS`, `agent_height Bog.STAND_HEIGHT`,
   `agent_max_climb 0.3` (the Bog has no step-up; stairs are ramps),
   `agent_max_slope 50°`, `region_min_size 2`, `edge_max_length 4.0`,
   `geometry_parsed_geometry_type = PARSED_GEOMETRY_STATIC_COLLIDERS`,
   `geometry_collision_mask = 1`, source root = the arena. Parse on the main
   thread (`NavigationServer3D.parse_source_geometry_data`), bake with
   `bake_from_source_geometry_data_async`, then put the mesh on a
   `NavigationRegion3D` child (default world map). After the bake: build links,
   rasterise the outline (an `Image` 512 px on the long side, one polygon fan
   per navmesh polygon, `bounds()` from the vertices), emit `baked(msec)`,
   print `nav_bake: <map> <polygons> polygons, <links> links, <msec> ms`.
3. **`JumpLinks.build(navmesh, space_state, parent) -> int`**: walk the
   navmesh polygons, collect edges that appear exactly once (borders), sample
   each border every 1.5 m plus its midpoint. For each sample with outward
   normal `n` (perpendicular to the edge in XZ, away from the polygon's
   centroid): skip if a ray from `sample + 0.3 up` along `n` for 0.6 m hits
   layer 1 (that is a wall, not a ledge). **Drops**: ray down from
   `sample + n·0.9 + 0.3 up` up to 14 m; if it hits and the map's closest
   point is within 0.3 m of the hit, add a one-way `NavigationLink3D`
   (`bidirectional false`, `travel_cost 1.2`). **Jumps**: for `d` in
   1.0..6.0 step 0.5 along `n`, `P = sample + n·d`, `Q = map_get_closest_point(P)`;
   accept if `|Q−P|` in XZ < 0.4, `rise = Q.y − sample.y ≤ hop apex` and
   `d − Bog.CAPSULE_RADIUS ≤ JumpArc.leap_reach(rise)`; add a link
   (`bidirectional` if the reverse also passes, `travel_cost 2.25` — the
   report's `LEAP_COST`). Dedupe links whose both ends are within 1.0 m of an
   existing one's; cap at 800. One pass on the main thread after the bake is
   acceptable.
4. **`GuideTargets.resolve() -> Array[Dictionary]`** `{pos, colour, kind}`:
   nothing unless `MatchConfig.is_bog(win_condition)`, phase PLAYING and the
   local Bog is alive. If the local peer holds a **timed** letter → nothing. If
   it carries (CAPTURE, `INF`) → `[vault of my team]` in `GUIDE_ALLY`. Else:
   every `loose_letter_pickups()` card whose `banked_team_of(letter)` is not
   my team → `GUIDE_LOOSE` at the card; every carrier in `letter_carriers()`
   other than me → `GUIDE_ENEMY` at their Bog if `Net.player_team` differs (or
   FFA), `GUIDE_ALLY` if it matches.
5. **`GuidePath`**: for each target, `NavBake.find_path(me, target)`; when the
   bake is not ready, or the path is empty, use the straight segment. Repath a
   target every 0.2 s or when it moved > 0.5 m; the head is re-anchored to the
   player and the tail to the live target every frame. Detect link segments
   (both ends within 0.5 m of a link's end points) and replace them with
   `JumpArc.arc_points`; Chaikin-smooth the rest twice; resample every
   0.35 m; lift 0.35 m. Temporal smoothing: keep the shown polyline and move
   each shown point toward the new point at the same arc fraction at 12 m/s.
   Sort targets by path length; the nearest draws whole; each other target
   shares its prefix with the nearest (points within 0.6 m) and only its
   divergent tail draws, at half width and 0.5 alpha; at most three.
   **Hysteresis**: a line whose path is under 2.0 m fades out; it fades back
   in above 3.0 m; fades take 0.25 s.
6. **`GuideLine`** renders: one `ImmediateMesh` per target, a camera-facing
   strip 0.12 m wide, `UV.x` = metres along the path, vertex alpha carrying
   the head fade (first 1.5 m from the player ramps 0→1) and the tail fade
   (last 0.5 m). Two `MeshInstance3D`s share each mesh: **pass one** depth
   tested, alpha 0.85; **pass two** `no_depth_test`, alpha 0.18,
   `render_priority` below pass one. The shader is unshaded, alpha blend,
   dashes `1.2 m` long with a `0.5` duty, scrolling toward the target at
   2.5 m/s, soft-edged (`smoothstep` 0.08 m), colour from the target,
   multiplied by the global fade. No shadows, no depth write.
7. **`tools/nav_check.gd` + `.tscn`** (headless): for each map id in
   `MapCatalog` build the arena offline the way `capture_preview.gd` does,
   wait for `baked`, print the census line, require `polygons ≥ 50`, and
   `find_path(pad 0, pad last)` non-empty on every map, then print
   `nav_check: PASS`. Also print per map the path length and how many link
   segments it took.
8. Report: the gate line for `nav_check`, the census you expect per map (you
   cannot run it — say "unknown, measure"), decision text, asks.

## Group C — the capture performance: rig, pouch, layer, sunburst, sounds

Owns: new `scripts/player/capture_rig.gd`, new `scripts/items/pouch_mesh.gd`,
new `scripts/items/sunburst.gd`, `scripts/player/bog_animator.gd`,
`scripts/player/bog_combat.gd`, `scripts/items/held_gear.gd`,
`scripts/player/bog.gd`, `assets/source/clips.json`, `tools/make_sfx.py` and the
two `.wav`s it writes, `scripts/util/audio_director.gd`, new
`tools/preview_capture.gd` + `tools/preview_capture.tscn`.

The owner: *"when the bog first captures the letter, it will be above their
right hand, bigger and floating kinda high; their right hand will be up in the
air, as if it's pulling the letter down; there is a small woolen loot pouch in
the user's left hand, down by their hip, maybe a little up and out; as the time
progresses the letter gets smaller and slowly moves down into the pouch; when
it hits 0, a short small gold array of sunburst, along with a sound."* And:
*"players might incorrectly assume you can punch, so make it so they are
actually doing something with their hands — capturing."* The letter **floats
and bobs around the Bog**; it is not pinned to the hand, and movement is free.

1. **`CaptureRig`** (`class_name CaptureRig extends Node3D`), built by
   `Bog._build_capture_rig()` right after `_equip_spear()`, on every peer for
   every Bog. Each frame, when `MatchState.letter_hold_is_timed(peer)`:
   `f = letter_hold_fraction(peer)`, `A = hand_transform().origin + 0.55 up`,
   `B = pouch_mouth_global()`. The letter is `Pickup.build_card(letter)` on a
   pivot under this node; position `lerp(A, B, smoothstep(f))` plus a bob of
   `0.06·(1−f)·sin(2.6 t)`; pivot scale `lerp(1.6, 0.25, smoothstep(f))`; yaw
   `1.1 rad/s·(1−f)`; an `OmniLight3D` in `Pickup.LETTER_COLOUR` riding it,
   energy `1.8·(1−0.7 f)`. Hidden otherwise. Reads
   `MatchState.letter_hold_letter(peer)` to build the right card and rebuilds
   only when it changes.
2. **The burst.** On `MatchState.letter_banked(peer, letter)` for this rig's
   peer: `Sunburst.fire(parent, at)` at `B` (or at the hand for a CTF bank) and
   `AudioDirector.play_3d(LETTER_CAPTURED, at)`. `Sunburst` (`class_name
   Sunburst extends Node3D`, static `fire`): 14 thin gold rays
   (`QuadMesh`/`ImmediateMesh` triangles 0.02 m wide, unshaded, additive,
   `Pickup.LETTER_COLOUR`), lengths 0.05→0.6 m and alpha 1→0 over 0.35 s,
   plus a flash `OmniLight3D` energy 4→0; frees itself.
3. **The steal** (CAPTURE): on `MatchState.steal_progress(peer, letter,
   from_team, done)` for this rig's peer with `letter != 0`: a ghost card
   rising from `MatchState.capture_layout().vaults[from_team] + 0.6 up` to `A`
   by `done`, scale 1.0→1.3; on `letter_stolen(peer, …)` for this peer: burst
   at `A` + chime; on `letter == 0`: hide.
4. **The pouch.** `PouchMesh.build() -> Node3D`: a drawstring sack, origin at
   the mouth's centre, body hanging −Y: a squashed sphere (r 0.065, then scale
   `(1, 1.25, 1)`), a neck cylinder (r 0.028, h 0.02), a cinch torus (inner
   0.026, outer 0.034) at the neck, two cord tails (r 0.004, 0.06 long, splayed),
   a gathered-fabric torus at the mouth (inner 0.02, outer 0.032). Wool
   `Color(0.45, 0.36, 0.27)` roughness 1.0; cord `Color(0.62, 0.53, 0.36)`.
   `HeldGear` hangs it on the **left-hand** attachment beside the bow and the
   potion with `POUCH_GRIP_OFFSET`/`POUCH_GRIP_ROTATION` constants (a first
   guess: the mouth in the fist, the sack hanging down and slightly outward),
   `set_pouch`, `has_pouch`, `set_pouch_grip` for the preview, and
   `pouch_mouth_global`. `BogCombat._wants_pouch()` = `is_holding_letter() and
   MatchState.letter_hold_is_timed(peer)`; `_refresh_hand` calls
   `set_pouch(_wants_pouch())` beside the other five and passes the fist card
   only for a carry: `set_letter(letter if holding and not timed else 0)`.
   The pouch also empties the bow hand's other objects (BogCombat's exclusivity).
5. **The layer.** `bog_animator.gd`: `CAPTURE_ROLE := "Capture"`,
   `CAPTURE_FALLBACK := "CastIdle"`, `static var CAPTURE_PLAYS :=
   clip_or(CAPTURE_ROLE, CAPTURE_FALLBACK)`; node `capture_clip` =
   `_cycle(player, CAPTURE_PLAYS, 0.0)`, node `capture` = `_upper_body_blend()`;
   wire `capture.0 ← draw`, `capture.1 ← capture_clip`, `loose.0 ← capture`
   (it sits over the carry and the draw, under every one-shot).
   `P_CAPTURE := "parameters/capture/blend_amount"`, `_capture_blend` moved
   toward 1 at `CAPTURE_BLEND_SPEED 6.0` while `letter_hold_is_timed(peer)`;
   while it is up, the carry target is 0. **Not** in `REQUIRED_CLIPS`; one
   `push_warning` when the fallback is in use, behind a static flag, like the
   punch. `clips.json` gains a row `{"file": "Capture", "role": "Capture",
   "suite": "letters", "mixamo_name": null, "mixamo_id": null, "mixamo_query":
   "reaching", "in_place": false, "loop": true, "face": "hips", "untwist":
   true, "markers": {}}` — check the carry idles' rows for the exact key set
   and copy it.
6. **Sounds.** `make_sfx.py`: `letter_appears` — a soft two-partial bell,
   ~0.9 s, gentle attack; `letter_captured` — a brighter three-note rising
   chime with a short shimmer tail, ~0.7 s. Register both, run the script,
   commit the `.wav`s (the `.import` files are written by the engine later).
   `AudioDirector` gains the two constants.
7. **`tools/preview_capture.tscn`** (window): one Bog holding a timed letter
   with `_letter_holds[1] = {letter: 1, ends_at: now+10, started_at: now,
   seconds: 10}` set directly, the camera on the right hand, `-- f=0.5` to
   freeze the fraction; prints the letter's and the pouch mouth's world
   positions and the hand's, so the offsets can be read off a render later.
8. Report: gate lines (a snapshot of `preview_capture` with `capture: wrote`),
   the Mixamo searches the owner should try for the real `Capture` clip,
   decision text, asks.

## Group D — the HUD: minimap, wording, tutorial

Owns: new `scripts/ui/minimap.gd`, new `scripts/ui/tutorial.gd` +
`scenes/ui/tutorial.tscn`, `scripts/ui/hud.gd`, `scenes/ui/hud.tscn`,
`scripts/ui/letter_track.gd`, `scripts/ui/ui_palette.gd`,
`scripts/util/settings.gd`, `tools/hud_range.gd` (and its `letter_drop_chance`
line).

1. **`UIPalette`** gains the three `GUIDE_*` colours. **`Settings.DEFAULTS`**
   gains `"tutorial_seen": false`.
2. **`Minimap`** (`class_name Minimap extends Control`), 180×180, anchored
   top-right at 32 px margins in `hud.tscn` under `Root`, shown only when
   `MatchConfig.is_bog(win_condition)` and hidden while the results are up.
   **Heading-up circle**: a parent that draws a filled disc in `UIPalette.PANEL`
   with `clip_children = CLIP_CHILDREN_ONLY`, a child that draws the world
   rotated by the local camera's yaw (`get_viewport().get_camera_3d()`), you at
   the centre, `RANGE_M 30.0` metres to the rim. Ground: `NavBake.outline_image()`
   (found via group `"nav_bake"`, converted once on `baked`) drawn at
   `UIPalette.RAISED_STRONG`, mapped by `NavBake.bounds()`; nothing before the
   bake. Blips: **you** — a white triangle pointing up; **teammates** —
   `UIPalette.team_colour` dots 5 px (`Net.player_team == mine`, alive);
   **loose letters** — `MatchState.loose_letter_pickups()` as the glyph
   (`letter_name`) in `GUIDE_LOOSE`, 11 px bold; **enemy carriers** —
   `letter_carriers()` on another team, a `GUIDE_ENEMY` dot with the glyph
   beside it; **teammate carriers** — their dot with the glyph in `GUIDE_ALLY`;
   **CAPTURE bases/vaults** — a ring per team in its colour at
   `capture_layout().vaults`. Enemies without a letter are not drawn. A 2 px
   `UIPalette.LINE_STRONG` rim and an N tick. `func debug_counts() ->
   Dictionary` `{allies, letters, carriers}` for the harness.
3. **Wording.** `LetterTrack`'s caption: `HOLDING X · N s` → `CAPTURING X · N s`;
   the CTF carry caption stays. `hud.gd`: on `MatchState.letter_appeared`
   play `AudioDirector.LETTER_APPEARS` 2D when phase is PLAYING; the feed row
   `[letter] appeared` (FFA only — CAPTURE already prints "went home").
4. **`Tutorial`**: layer 20, a scrim `UIPalette.VOID` at 0.6, a centred card
   760×460 in the theme's panel style, title, an animated figure area 700×220
   (`_draw` per card, driven by a running clock), body text
   (`UIPalette.FONT_BODY`), six pips, BACK / NEXT / DONE, Esc closes, mouse
   free while open (`SceneFlow.release_cursor("tutorial")` /
   `recapture_cursor`). Cards, each with a loop of 3–4 s drawn from
   primitives (dots for Bogs in `TEXT`, letters as glyphs in `GUIDE_LOOSE`,
   dashed lines with scrolling dashes, a pouch as a rounded rectangle):
   1. **A letter falls** — a Bog blip goes down, a gold B pops out and bobs.
      *"Every death drops the next letter — B, then O, then G. Only one is
      ever out at a time."*
   2. **Follow the line** — a dashed gold line from you to the letter bending
      round a wall block, dashes scrolling toward it. *"A dashed line shows the
      fastest way there, jumps and all. Gold: nobody has it — go take it."*
   3. **Capture it** — a blip with an arm up, the letter shrinking down into a
      pouch over a few seconds, then a small sunburst. *"Walk into the letter
      to start capturing. You're unarmed for the whole capture; the letter
      sinks into your pouch, and when it lands it's yours."*
   4. **Red and blue** — the line goes red to an enemy blip carrying a letter,
      then blue to a teammate. *"Red: an enemy has it — kill them and it
      drops. Blue: a teammate has it — go cover them."*
   5. **The minimap** — the circle with your triangle, team dots, a letter
      glyph, a red carrier. *"Top right: you, your team, loose letters, and
      only the enemies who carry one."*
   6. **Spell it** — three lamps light B, O, G. *"Hold all three and you win.
      In Teams the letters live at your base: carry each one home to your
      vault, and guard it — the other team can steal it back."*
5. **`tools/hud_range.gd`**: drop its `letter_drop_chance` line; add modes
   `minimap` (a LETTERS match with one loose card 12 m north-east, one enemy
   carrier 18 m west, one teammate 8 m south; prints
   `hud_range: minimap allies=1 letters=1 carriers=1 PASS` off
   `debug_counts()`) and `tutorial` (instances the tutorial over the HUD, opens
   it on card 3, prints `hud_range: tutorial PASS` when it is visible).
6. Report: the two gate lines (snapshot form, as the other `hud_range` checks),
   decision text, asks.

## Group E — the menu and the lobby: real letters over the fire

Owns: `scripts/ui/bog_backdrop.gd`, new `scripts/ui/menu_letters.gd`,
`scripts/ui/main_menu.gd`, `scenes/ui/main_menu.tscn`, `scripts/ui/lobby.gd`,
`scenes/ui/lobby.tscn`, `tools/ui_range.gd`.

The owner: *"remove the GUI BOG letters from the menu, replace them with the
real, floating, gently bobbing real asset letters; when the game starts the
letters should bounce down then bounce out of the top of the screen, as if they
are leaving first, and then the screen goes, so we see them leave. The campfire
should be moved to the left in the menu and the BOG hovers above it; in the
lobby the letters are much smaller but still hovering over the campfire — same
scale relationship to the campfire in both."* Chosen composition: **fire
centre-left under the letters, the hero Bog standing beside the fire lit from
the side.**

1. **`MenuLetters`** (`class_name MenuLetters extends Node3D`): three
   `Pickup.build_card(letter)` pivots for B, O, G in a row, each scaled to
   `LETTER_WORLD_HEIGHT 0.85` m (`/ Pickup.LETTER_HEIGHT`), `LETTER_GAP 0.25`
   m between glyph boxes, centred over the parent at `HOVER_HEIGHT 1.55` m.
   Bob: each letter its own two detuned sines, amplitude 0.05 m, phases
   offset so they never move together; yaw **sway** ±12° at 0.3 Hz rather
   than a spin (a spinning wordmark cannot be read). `func leave() -> void`
   (awaitable): each letter, staggered 0.06 s, dips 0.25 m over 0.18 s
   (QUAD out) then rises 9 m over 0.55 s (QUAD in); the method returns when
   the last has gone. **One world rig, one size**, in both formations: the
   menu camera at 5.7 m / 24° makes them the wordmark, the lobby camera at
   9.95 m / 36° makes them small, and the letter-to-fire proportion is
   identical by construction.
2. **`BogBackdrop`**: `_build_letters()` after `_build_fire()`, the rig a child
   of the `Fire` node. **HERO**: the hero slot moves to beside the fire
   (start at `Vector3(1.15, 0.0, -0.35)`, yaw so he faces the lens with a
   quarter turn toward the flame) and `FRAMING[HERO]` re-aims so the fire and
   the letters sit in the frame's left half with the letters in the upper-left
   quadrant clear of the Bog and the bottom rail — adjust `eye`/`look`, keep
   the 24° lens. **RING**: unchanged framing; if the letters at `HOVER_HEIGHT`
   cover a Bog's face in the eight-Bog ring, raise `HOVER_HEIGHT` (it applies
   to both formations, which is what keeps the proportion). Expose
   `func letters_leave() -> void` (awaits the rig).
3. **`main_menu.tscn`**: delete the `Title` label; keep `Quip`, anchored so it
   reads as the caption under the letters (about x 112–600, y 300–340 — tune
   against the render); add `HowToPlayButton` "HOW TO PLAY" to `Nav` between
   PRACTICE RANGE and SETTINGS, wired in `main_menu.gd` to `%Tutorial.open()`;
   instance `res://scenes/ui/tutorial.tscn` as `Tutorial` under `UI/Root`
   with `unique_name_in_owner`. **`lobby.tscn`** instances it the same way;
   `lobby.gd` calls `%Tutorial.maybe_auto_open()` when the lobby opens with
   `MatchConfig.is_bog(Net.config.win_condition)` and again when the config
   changes to one (once per machine either way — `Tutorial` keeps the flag).
   `_on_match_start`: `await _backdrop.letters_leave()` before
   `SceneFlow.go_to_arena()`, on every peer.
4. **`tools/ui_range.gd`**: `menu` and `lobby_full` already photograph both
   screens. Add a `menu_letters` mode that prints the projected screen box of
   the three letters and of the hero Bog's capsule (like `lobby_character`
   prints its frame) so overlap is a number, and a `lobby_letters` mode that
   prints the letters' box and every ring plate's top.
5. Report: the two gate lines (snapshot form), the framing constants you chose
   with the reasoning, decision text, asks.

## Group F — hands on props: the finger grip layer (after Group C lands)

Owns: new `tools/grip_poses.gd`, `scripts/player/bog_animator.gd` (its own
section only — Group C has finished with the file by the time this runs).

From the owner's conversation: *"one grip pose per prop, not per clip; the
finger bones get a single frozen pose while the prop is held, layered over
whatever the body clip is doing … author it once by stealing it from a clip
where the hand is closed."* Small priority.

1. **`tools/grip_poses.gd`** (headless `--script`): load
   `art/generated/bog_clips.res`; for each pose sample the 12 finger bones of
   one hand (`Thumb1..4`, `Index1..4`, `Middle1..4` — the mitten has three
   digits; see `BogAnimator.UPPER_BODY_BONES`) at a time: `fist_right` from
   `SwordCarry` 0.5 s, `fist_left` from `SwordCarry` 0.5 s, `hook_left` from
   `BowCarry` 0.5 s, `open_right`/`open_left` from `Idle` 0.0 s; write a
   one-frame looping `Animation` per pose (rotation tracks only, the body's
   skeleton path) into an `AnimationLibrary` saved as
   `art/generated/grip_poses.res`; print `grip_poses: 5 poses, 12 tracks each`
   and `grip_poses: PASS`.
2. **The layer**: `BogAnimator._ready` adds the library to the player as
   `"grip"` when the file exists (a `push_warning` once when it does not).
   Two filtered `Blend2`s, `grip_left` (its filter the left hand's 12) and
   `grip_right`, each with a `Transition` between that hand's poses, wired
   **over the emote**: `grip_left.0 ← emote`, `grip_right.0 ← grip_left`,
   `output ← grip_right`. Targets: right fist while `held_gear.is_carried()
   or has_sword() or has_arrow()`; left hook while `has_bow()`; left fist
   while `has_potion() or has_pouch()`; otherwise 0. `GRIP_BLEND_SPEED 8.0`.
3. Report: the gate line for `grip_poses`, decision text, asks.

---

## The integrator's list (after every report is in)

1. `git status`; read every "asks" section and land them.
2. `Godot --headless --import` (slow, background).
3. `bash tools/smoke_test.sh`; fix what it finds; add the returned gate lines.
4. Write D-129.. from the returned decision text; STATUS, PLAN, ARCHITECTURE.
5. Commit and push; `[FINAL]` on the last commit of the batch.
