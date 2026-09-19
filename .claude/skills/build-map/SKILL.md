---
name: build-map
description: Build a new BOG map end to end - ask the brief, get the asset pack in, hand the construction to the map-builder agent, then wire it into the catalog, the gate and the lobby carousel. The contract a map owes the match is here so nobody re-derives it a sixth time. Use when Carl says "new map", "build a map", "another arena", "make a <theme> map", names a map that does not exist yet, or when a map ticket comes out of Todo.
---

# Build a map

Seven maps exist and the first six each re-derived this list from the code. This
is the list. **Do not build geometry from this file** — the construction is the
`map-builder` agent's job (`.claude/agents/map-builder.md`); this is the brief,
the contract and the wiring either side of it.

Records, not restated here: **D-031** (collision baked in world space),
**D-042** (a map is a table, checked as a jump graph), **D-056** (sightline
budgets and tops nobody reaches), **D-057** (a void you fall into, backdrops),
**D-082**/**D-146** (a map drawn for Capture B·O·G; even without being
mirrored), **D-112** (practice is a property of the map), **D-119**/**D-135**
(lighting, and the no-bare-primitives rule), **D-160** (three ways onto the top),
**D-161** (fittings checked against physics), **D-162** (the lobby carousel).

## 1. Ask before building

Never start from a one-line request. Ask these, in one message, and wait:

1. **Theme and time of day.** What place is this, and what hour is it? The
   answer decides the sky, the sun and half the geometry.
2. **Size and player count.** Eight is the roster (`MatchConfig.MAX_PLAYERS`);
   the wharf is 43 m square, the quarry 48 m inside an 11 m rim, the range 90 m
   long. Which of those is it nearest?
3. **Modes.** Capture B·O·G as well as Free-for-all? A practice map (D-112)?
   Capture is the one that adds `Bases`, `Letters` and per-team pads.
4. **The asset pack, and where it is.** Which pack, and has he fetched it? The
   hand-off is his `Downloads` folder — he drops it there and says so
   (CLAUDE.md). Never a pack you invent.
5. **Terrain.** What is the *structural* difference — hills, a pit, decks, a
   ridge? Carl, 2026-09-18: *"like Fortnite has hills and stuff... structural
   differences."* Flat is allowed only when the model count carries it, the way
   Whisperbloom Hollow does.
6. **The reference for effort.** Which existing map is the bar? The prompt that
   worked for Rust: *"look at the Enchanted Forest map, and make sure to put the
   same amount of effort into the theming and the ambiance and the general feel
   and lighting... ambiance, lighting, theme, background, like skybox."*

Then state the plan back in five lines and start.

## 2. The asset rule, before any geometry

**A map is built from a pack, never from nothing.** Carl: *"Claude just makes up
random shapes that aren't too good. Asset packs have textures."* Primitives are
for collision and for stand-ins that get replaced (D-135: nothing a player looks
at is a bare unshaded primitive; if you cannot say what it is *made of*, it does
not go in the world).

If the pack — or any single mesh, sound or texture — is not in the repo, the ask
goes out **before building**, one line per item, in CLAUDE.md's form:

```
FETCH <what> — <where from> — <exact search term or prompt> — <format>
```

and the ticket gets **Needs a human** and an `Open:` line. Then wait.

**The route in**, once it is in `Downloads`:

| | |
|---|---|
| Raw pack | `assets/<name>_asset_pack/` — gitignored, plus a `.gdignore` so Godot never imports 5 GB. |
| Trim it | A per-pack script beside `tools/trim_quarry_pack.py`, which is thirty lines over `tools/decimate_assets.py`'s weld → decimate → UV-transfer → repack. Output `art/maps/<id>/`. Julian's 5 GB mining pack came out at **62 MB**. |
| Committed | `.gitignore` keeps `art/maps/*/*.glb` and its `.import` and nothing else. Models the map does not place go in `art/maps/<id>_spare/` behind a `.gdignore`. |
| One huge `.glb` | `tools/prepare_map.py`'s path instead: strip, re-encode textures to JPEG, repack (Rust, 337 MB → 43 MB). |
| Textures | CC0 sets under `assets/maps/<id>/` with a `SOURCES.md`, world-triplanar (D-146). |

## 3. Hand the construction over

Spawn the **`map-builder`** agent with: the answered brief, the pack path, the
reference map, and a pointer to this file for the contract. It plans
coordinates on paper, builds from `const` tables, renders, looks, and fixes —
at least twice. Come back here for sections 4 to 8.

Small edits to an existing map do not need the agent.

## 4. The contract

Six files and a row. `<id>` is the string on the wire; never rename one.

| | |
|---|---|
| `scripts/world/maps/<id>_map.gd` | `class_name <Id>Map extends StaticMap`. Builds the place in `_ready()` from `const` tables, then calls `super()`. |
| `scripts/world/maps/<id>_ambience.gd` | The air: motes, mist, dust, birds. Built after `super()`, never collision. |
| `scenes/world/maps/<id>.tscn` | Four nodes and a script — see below. No geometry in it. |
| `resources/config/<id>_env.tres` | The `Environment`. |
| `resources/config/<id>_sky.tres` | The sky, if it is authored rather than a `ProceduralSkyMaterial`. `sun_follow_light` so the visible disc and the shadows can never disagree. |
| `scripts/world/map_catalog.gd` | One row in `MAPS`. |

**The catalog row** (every field is documented on the constant; read it):
`id`, `display_name`, `kind: Kind.STATIC`, `scene`, `loading_line` (**no `%d`**
— a static map has no seed), `thumb_camera` (a partial override of
`THUMB_CAMERA`: `yaw` bearing, `pitch`, `zoom`, `look_at`, `fov` — never a world
coordinate, D-162), and `"practice": true` only for a range (D-112). Do not add
a row for a scene that is not on disk: the gate really loads it.

**The scene**, which is all `static_map.gd` asks for:

- Root `Node3D` with the map script, `void_height` and `base_radius` set.
  `void_height` is the floor of the map, not -45: the wharf and quarry use -10,
  the range -12. A Bog that walks off should be dead before the fall gets
  boring.
- `Environment` — a `WorldEnvironment` child with the map's `.tres`. `arena.gd`
  builds none for a static map.
- `Sun` — a `DirectionalLight3D`. Shadows on; it is the key. A `.tscn`
  serialises a `Transform3D` **row-major** — the range's sun was 59.6 degrees
  wrong for a whole pass because it was written as columns.
- `Bounce` — a second shadowless `DirectionalLight3D`, roughly anti-parallel to
  the sun, warm, at a fraction of its energy, `sky_mode = 1` (LIGHT_ONLY) so it
  cannot steal LIGHT0 from the sky shader. Not physical; it is the difference
  between a lit map and a grey one with a bright side (D-119, D-146).
- `Spawns` — **eight `Marker3D`s**, each **facing inward**, at least
  `preview_map.PAD_SEPARATION` (6 m) apart. In Capture, a Bog respawns only on
  its own team's pads, so put four near each base and alternate them so a
  two-player match opens at opposite ends.
- `Lights` — optional, a group node for everything else the map lights with
  (floodlights, festoon strings, work lamps). Built in the script.

Markers may be **built in the script instead of typed into the scene** when
their positions are *derived* from the same tables as the geometry — Highsun
Grounds carries fifty-odd markers across eight groups and builds every one,
because fifty typed coordinates go stale silently the first time a lane moves.
A map that does this **prints its own census** (`27 dummies, 4 wells, 3 racks,
1 signboard(s), 8 targets`) and the gate greps it, so a marker dropped by a
later edit fails the gate rather than a playtest.

**For Capture B·O·G** (D-051), all three or the fallback layout is used:

- `Bases` — one `Marker3D` per team, **in team order**, on the floor at the
  middle of the base. `base_radius` is how far it reaches; a carrier must also
  be within 3 m of the marker's height.
- `Letters` — **three `Marker3D`s, in B, O, G order** (the child order is what
  is read; the names are labels). Put them where both teams reach them — on the
  perpendicular bisector of the base-to-base line is the trick that makes an
  asymmetric map even (D-146).

**For the jump checker**, fill before `super()`:

- `platforms` — a `StaticMap.Platform` per landing: centre at the *top* surface,
  the **inscribed** radius less a 0.15 m lip, a zone and a label.
- `off_limits` — tops nobody may stand on (a column, a mast, a roof). The report
  fails if any jump reaches one.

**Other groups:** `StaticMap.BACKDROP_GROUP` (`"map_backdrop"`) on the far
distance — a sea, a coast, a lit town — added *after* `super()`, never
collision, and left out of the bounds `preview_map` frames with (D-057).

**The build-order line is the whole discipline:** everything added before
`super()` is swept into world-space trimesh collision on layer 1; everything
after is dressing that players walk through. Things that *read* as cover must be
cover — the quarry's carts stand on a code-built box, not on the art's trimesh.
Nothing random: every peer builds the same map by construction.

**Navigation is automatic.** `NavBake` parses static colliders on layer 1 from
the arena down and `JumpLinks` adds the ledges, gaps and drops off `JumpArc` —
the same arithmetic `parkour_report` holds the map to. No map declares anything.
What the map owes is collision on layer 1 and gaps a Bog can actually cross;
`nav_check` proves a route from the first pad to the last.

## 5. What to focus on while it is being built

- **Sightlines.** Budget them and hold to it. The wharf searched for a layout
  under 25 m and got 45 after a 1.2x pass (D-056, D-145); the quarry allows 30 m
  on the floor. **No spawn pad may see the other base's pads** — the thing that
  closes those lines is usually one solid object on the map's middle (D-082).
- **Cover, at named heights.** The quarry's grammar: 1.2 m kerbs (a hop),
  1.85 m berms (over a 1.45 m eye, under a ground leap), 3.0 m blocks (climbable
  off a kerb only), 4.0 m benches (the high ground). Say what each height means
  and carry it in the *material*, so a player can read it.
- **A hill worth taking, with more than one door.** D-160: the top needs at
  least three separate ways on, 60 degrees apart around it, or whoever holds it
  watches one corridor. `top_height` / `top_routes` / `top_spread` in
  `parkour_report.EXPECT` count them.
- **Lighting is intentional, not low.** A key that actually lands, a bounce that
  rescues the shaded floors, and real effort on the far distance and the clouds.
- **Terrain.** Height changes that change how the map is played, not props
  scattered on a flat square.

Three dimensions are not taste, and getting one wrong is invisible until play:

- **The Bog has no step-up.** `floor_max_angle` is 52 degrees, so a ramp is the
  only climbable slope there is — every stair in this game is a ramp. A face
  taller than a leap is a wall, and that is how the quarry's 4 m benches are
  reached by haul ramps and nothing else.
- **A corridor has to fit the camera, not the capsule.** The Bog is 0.38 m
  across and 1.55 m tall, but `bog_camera.gd` sweeps a sphere behind the
  player's head: a passage that fits the body and not the arm is one the player
  plays blind. The quarry's adit is 4.0 m wide with 3.4 m of headroom.
- **An interior wants a bend.** A straight bore is a sightline with a man at
  each end of it; an L has no line through it at all.

## 6. Wire it into the gate

Add to `tools/smoke_test.sh`, beside the six that are there:

```bash
# eight pads on solid floor, a Bog-sized capsule on each, the geometry imported
check "<id> spawns and collision" "preview_map: PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 900x1100 --script tools/snapshot.gd -- \
    res://tools/preview_map.tscn "$GODOT_LOG_DIR/<id>_top.png" 30 top \
    map=res://scenes/world/maps/<id>.tscn min_triangles=<own floor>

# the jump graph, the off-limits tops and the sightline budgets
check "<id> parkour and <what it promises>" "parkour_report: PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 1000x1000 --script tools/snapshot.gd -- \
    res://tools/parkour_report.tscn "$GODOT_LOG_DIR/<id>_parkour.png" 40 top \
    map=res://scenes/world/maps/<id>.tscn

# the whole match on it, and the capture layout planned off the declared bases
check "<id> playthrough" "playthrough: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/playthrough.tscn -- <id>
also "<id> playthrough" "arena: <Display Name> built from"
also "<id> playthrough" "playthrough: capture layout PASS"
also "<id> playthrough" "capture layout on '<id>' — declared bases"
```

- `min_triangles` is the map's **own** floor — Rust's 90,000 would fail the
  wharf's 1,700 for being cheap, and the quarry's 400 would pass anything.
- A row in `parkour_report.EXPECT` keyed by scene path: `min_platforms`,
  `min_big_edges`, `summit_zone`, `top_height`/`top_routes`/`top_spread` (D-160),
  `sightline`, `roof_sightline`, `reach`, `grid`, `overboard`. Write the
  *argument* for each number in the comment; the next person needs it.
- `nav_check` picks the map up from the catalog with no edit; add an
  `also "navmesh on every map" "nav_check: <id>"` if it is worth naming.
- `tools/capture_preview.tscn -- <id>` plays a real Capture match on a real map
  and renders it. It runs once in the gate, on `safari`; a new capture map does
  not need a second copy — but run it by hand on the new map once, because it is
  the only thing that puts bases, letters and carriers on it together.
- A practice map adds the `playthrough: practice PASS` lines; a map with
  authored fittings adds a physics probe of its own (D-161).
- A map with a fairness claim gets a checker that re-proves it from the built
  scene, the way `tools/quarry_check.gd` does (D-146).
- **Any number the map argues from, it prints back out of the built scene and
  the gate reads.** `range_map._check_sun_and_sky` exists because the range's
  sun was 59.6 degrees off design for a whole pass and no render showed it. A
  census, a sun bearing, a pad coordinate — assert the value, not the comment
  that claims it.

## 7. Renders to judge it by

Not optional, and not a substitute for the gate:

```bash
# top-down with a marker on every pad; also side, front
... --script tools/snapshot.gd -- res://tools/preview_map.tscn out/<id>_top.png 30 top map=…
# eye height on a pad, looking at the middle — the only framing a player gets
... res://tools/preview_map.tscn out/<id>_pad0.png 30 pad0 map=…
# the ASCII floor scan: height, does a Bog fit, can you see out
... res://tools/preview_map.tscn out/<id>_probe.png 30 probe map=…
# the jump graph drawn
... res://tools/parkour_report.tscn out/<id>_parkour.png 40 top map=…
```

**Look at the images.** `probe` is the one that earns its place — two of Rust's
first eight pads passed every geometric test and opened onto a container wall a
metre away. Then the lobby's photograph (D-162), which is not in the gate:

```bash
"$GODOT" --path . --resolution 960x540 tools/map_thumbs.tscn -- <id>
"$GODOT" --path . --resolution 960x540 tools/map_thumbs.tscn -- <id> candidates   # to choose the row
"$GODOT" --headless --path . --import
```

It writes `art/generated/map_thumbs/<id>.png`, which is committed. Re-bake it
after any rebuild of the map.

## 8. The checklist

Mechanically checkable. Everything must be true before the ticket moves.

- [ ] `scripts/world/maps/<id>_map.gd`, `<id>_ambience.gd`,
      `scenes/world/maps/<id>.tscn`, `resources/config/<id>_env.tres` exist.
- [ ] `MapCatalog.MAPS` has the row; `loading_line` has no `%d`; `thumb_camera`
      is a partial override.
- [ ] The scene has `Environment`, `Sun`, `Spawns` with **eight** inward-facing
      markers, and `void_height` and `base_radius` set on the root.
- [ ] Capture: `Bases` in team order, `Letters` three in B, O, G order, pads
      split near the bases.
- [ ] `platforms` filled before `super()`; `off_limits` holds every top nobody
      may stand on; the backdrop is in `map_backdrop` and added after `super()`.
- [ ] Nothing bare and unshaded is in the world (D-135); every prop is from the
      pack or has a `FETCH` line against it.
- [ ] `bash tools/smoke_test.sh` — the new `preview_map: PASS`,
      `parkour_report: PASS`, `<id> playthrough` and `nav_check: PASS` lines are
      green, and so are all the others.
- [ ] `art/generated/map_thumbs/<id>.png` is baked and committed.
- [ ] The renders in section 7 have been **looked at** and what they showed was
      fixed.

## 9. Land it

CLAUDE.md's rules, none of them optional:

1. Ticket **In Progress** before building; if the pack has to be fetched,
   **Needs a human** with the `FETCH` line and wait.
2. Commit each coherent piece and push to `main`; `git pull --rebase` first.
   Last push of the batch is `[FINAL]`.
3. A **D-record** in `docs/DECISIONS.md`: what the map is, the numbers with the
   arguments under them, what was rejected, and what is known weak. Reference it
   from the scene's header comment.
4. `docs/STATUS.md`: the gate's count, and a line on the map.
5. Ticket to **In Review** with the commit and the D-record in a comment, and
   say what is in the queue. **Done** only when Carl has played it.
