# Practice range — requirements

> **LANDED, 2026-09-17, as D-112..D-116.** All six units are built and in the
> gate. D-112 is the foundation (practice as a property of the map, and the
> dummy substrate), D-113 the place itself, D-114 the brains and stations,
> D-115 the wells, the refill stone and the weapon racks, and D-116 the
> non-Bog targets and the feedback. `docs/ARCHITECTURE.md` says where every
> piece lives and `docs/PLAN.md` Phase 9 carries the item-by-item state. On
> 2026-09-18 **D-119** moved the range to golden hour, shortened the lane rails
> and removed the six stations (the brains are now authored per area, the
> stats reset is a plain signboard), so the station half of D-114 and the
> night sky of D-113 no longer describe the map; what
> is still open is 9.6, which is that nobody has stood on it. This document is
> kept as written — it is the scope the five records were argued against, and
> the ➖ cuts in it are the list of things that were deliberately not built.


A map in the lobby's picker, chosen like any other, that exists to let a player
learn every weapon, ability and movement the game has, alone or with friends,
with nothing on a clock and nothing at stake. The reference points are Valorant's
range and Overwatch's practice range: a built place, not a settings menu, where
every station teaches one thing and the dummies do interesting things.

Working name **Glowworm Grounds** (id `range`). A cleared bog at night where the
Elders train: torch posts, glowworm lanterns marking distance, wooden target
boards on stakes, a lodge at the back. The theme is the game's own (night forest,
torches, the MegaKit) — the range should look like a corner of Whisperbloom
Hollow somebody built things in, not like a grey box.

This document is the scope. Each numbered section below is one unit of work: an
Opus agent plans it, the plan is reviewed, then it is implemented. The
"Facts" block under each section is what the survey of the code found and what
the plan must respect. `docs/DECISIONS.md` gets one entry per landed unit.

## What the surveys established (read before planning anything)

- **Maps** are one row in `scripts/world/map_catalog.gd` (`id`, `display_name`,
  `kind`, `scene`, `loading_line`) plus a scene whose root extends `StaticMap`.
  The `.tscn` holds only `Environment`, `Sun` and marker nodes; the map's
  `_ready()` builds all geometry from `const` tables **before** `super()` (that
  is collision) and dresses **after** it (that is not). Required: `Spawns` with
  eight inward-facing `Marker3D`s, `void_height`. Optional: `Bases`, `Letters`,
  `platforms`/`off_limits` for the parkour report. See `wharf_map.gd`,
  `quarry_map.gd`, `static_map.gd:18-79`.
- **Solo works today** (`MatchConfig.MIN_PLAYERS := 1`), but the only entry is
  Host, which binds a port. `Net.start_offline()` is the socket-less session the
  dev tools use (D-011).
- **No map-placed item exists.** Every pickup is a corpse drop minted host-side
  by `MatchState._spawn_drop(kind, letter, spot)` → `_spawn_pickup` RPC, parented
  under the `spawned_items` group, 30 s lifetime unless `_keeps`. Kinds:
  `Pickup.Kind { SHIELD, MAGNET, LETTER, ELDER_ROBE, POTION }`. Weapons are never
  pickups; they come from the lobby loadout (`Net.player_weapon`), read once in
  `MatchState._create_bog`. Grant API: `BogCombat.grant_shield/magnet/potion(n)`,
  host only.
- **Damage lands only on `Bog`s.** One door: `MatchState.report_damage(...)`,
  host only, keyed by `peer_id` in `MatchState.bogs`/`stats`. Projectiles cast
  `collider as Bog`; sword and lightning pick from `MatchState.living_bogs()`.
  There is no `take_hit` interface and **no per-hit signal**; `report_damage`
  returns the amount and emits nothing. Void kills come from `_tick_void()`.
- **Dummies today** (`tools/combat_range.gd`, dev-only) are real Bogs spawned from
  fake `Net.players` rows at ids 900+; they take hits, die, ragdoll and respawn
  through the normal flow. They never move: nothing drives them. **There is no
  AI, navigation or bot code anywhere.** A Bog's transform replicates through a
  `MultiplayerSynchronizer` from whichever peer holds its authority; `Combat`
  authority is already forced to peer 1.
- **Nameplates**: `Nameplate.set_display_name/set_team/set_ally/set_health`,
  wired in `_create_bog`. Skins via `Bog.wear_skin` / `Skins`.
- **World scale**: Bog 1.80 m, run 5.4 m/s, hop rise 1.69 m, leap 2.30 m, dive
  rise 4.23 m, a 4 m wall is over every jump. Spear 42 m/s, flat to 28 m. Bow
  8.5 m (tap) to 50.6 m (full draw) flat. Sword arc 75°, advances 1.7 m.
- **Gate**: `bash tools/smoke_test.sh` (135 checks). A map adds a playthrough
  block, a `preview_map` block and a `parkour_report` block with its own
  `EXPECT` row. Count moves in `docs/STATUS.md` (two places). D-numbers are
  claimed at commit time. Sounds are synthesised by `tools/make_sfx.py`.

## Everything a practice range could have

The full list, so nothing is forgotten. ✅ in scope, ➖ deliberately cut (with
why), ❓ decided below.

**Getting there**
- ✅ In the map picker like any map. Works hosted (friends can join) and solo.
- ✅ A **Practice** entry on the main menu that skips the lobby: offline session,
  range map, straight to the arena. No port, no code, one click.
- ✅ No clock, no kill limit, no results screen; leave from the pause menu.
- ✅ Instant-ish respawn (1 s), no spawn protection, no warmup.
- ➖ A settings-menu "practice options" panel. Options live on in-world
  stations instead (Overwatch's model); a menu would be a second home for the
  same switches.

**Targets**
- ✅ Bog dummies (real Bogs; hittable by everything; ragdoll; respawn at their
  station). Hidden from the lobby roster, scoreboard and results.
- ✅ Dummy behaviours: stand, strafe, patrol, pop-up from cover, jumper,
  rusher (runs at you, retreats), wanderer (random walk in a zone), circler
  (orbits the melee pit). Each station's dummies have a default and a station
  switch.
- ✅ Dummies face the nearest player (or their lane).
- ✅ Static target boards (non-Bog): ringed wooden boards on stakes that score
  a hit by ring, knock back on impact, ring a sound, and show the distance.
- ✅ Drifting glowworm orbs for tracking practice (bow), launched on a loop
  across the long lane; burst when hit.
- ✅ A gong at 28 m on the spear lane (the spear's flat range) that rings.
- ➖ Dummies that shoot back / bots with aim. No AI exists and "shoots back" is
  a bot, not a dummy; out of scope for this pass. Rusher + pop-up give the
  reactive feel without it.
- ➖ Headshot multiplier. Damage does not vary by bone today; the range
  reports the bone hit but does not invent a rule the game lacks.

**Items and loadout**
- ✅ Item wells: map-placed pedestals that keep a pickup of one kind present,
  re-minting it a few seconds after it is taken. Shield, magnet, potion, and
  an Elder robe well (lightning practice) on a longer timer.
- ✅ Refill stone near the lodge: stepping on it fills shields/magnets/potions
  to the game's caps.
- ✅ Weapon racks: three racks (spear, bow, great sword); walking into one swaps
  your weapon live, so every weapon can be practised without a trip back to
  the lobby.
- ✅ Letter and base practice: `Letters` and `Bases` markers, so a Capture-mode
  practice is possible from the lobby with the same map.
- ➖ Infinite cooldowns / no-recharge toggle. The point of the range is the
  real timings; wells and the refill stone keep supply up without lying about
  cadence.

**Movement**
- ✅ Parkour course sized from the measured reaches: hop steps, leap gaps, a
  dive wall, a momentum-hop runway, a crouch tunnel. Start and finish plates
  with a timer and a best-time board.
- ✅ A marked void edge with a railing gap, so "fell off the island" can be
  learned on purpose, respawning at the lodge.
- ✅ Distance posts every 5 m on the throwing lanes (5 → 30 m) and 10 m on the
  long lane (to 60 m), lantern-lit so they read at night.

**Feedback**
- ✅ Hit marker (HUD flash + the existing `hitmarker.wav`) on every landed hit.
- ✅ Floating damage numbers at the hit point, and the distance of the shot.
- ✅ A stats board: throws, hits, accuracy, kills, longest hit, current streak,
  per weapon, for this session. Shown as a small HUD panel in the range and as
  a wooden board on the lodge wall. Reset from a station.
- ✅ Parkour timer readout while a run is live.
- ➖ Replay / recording. Out of scope.

**Controls in the world**
- ✅ Stations: torch-lit signposts you walk into that switch a zone's dummy
  behaviour, reset a zone, or reset the stats. Feedback is a lantern colour
  change and a chime; no menus.

**Place**
- ✅ Built from tables like every other static map, with the MegaKit and the
  project's shaders; night sky through `enchanted_sky.gdshader`; torches and
  glowworm lanterns; a lodge; fog low over the bog.
- ✅ All eight spawns on the lodge deck, facing the range.
- ✅ Passes `preview_map`, `parkour_report` (own `EXPECT` row: the range wants
  long sightlines, so its caps are its own), and a range branch of
  `playthrough` that ends when dummies and wells are proven rather than on a
  kill limit.

## Units of work

Dependencies: **1 lands first**; 2, 3, 4, 5 run in parallel on disjoint files
against 1's APIs; **6 integrates and closes**. Every unit adds its own gate
checks and its own D-entry text (written to the unit's plan file, folded into
`docs/DECISIONS.md` by unit 6).

### 1. Foundation — the range as a kind of match, and the dummy substrate

Owns: `map_catalog.gd`, `match_config.gd`, `match_state.gd`, `net.gd`,
`scene_flow.gd`, `main_menu.gd/.tscn`, `lobby.gd`, `match_settings.gd`,
`scoreboard.gd`, `results_screen.gd`, `pause_menu.gd`, `bog.gd` (only if
authority needs a hook), a placeholder `scenes/world/maps/range.tscn` +
`scripts/world/maps/range_map.gd` (flat floor, eight spawns; unit 2 replaces the
body), `scripts/world/range/range_dummies.gd` (new).

Must deliver:
- Catalog row `range` with a `practice: true` flag (or equivalent) that the rest
  of the game reads from one place. `MatchState`: in a practice map no win
  check, no clock, `respawn_delay` 1.0, `spawn_protection` 0, `warmup_time` 0,
  kill feed still on. Lobby: with the range selected the Limits rows fold away
  and one line says what practice is. Pause menu's Leave ends it as today.
- **Practice** on the main menu: `Net.start_offline()`, `config.map = "range"`,
  straight to the arena via `SceneFlow`. Returning to the menu tears the
  session down cleanly.
- **Dummy substrate**: a host-side registry that spawns N dummies as real Bogs
  at ids 900+, with `"dummy": true` rows that the lobby list, `can_start_match`,
  scoreboard and results all skip. Dummies get a nameplate ("Dummy" + number),
  a fixed pale skin, no spawn protection, and respawn at **their own station**
  (not a spawn pad) after `respawn_delay`. Their transform authority is the
  host, so a driver on the host moves them and clients see it through the
  normal synchronizer (verify; this is the one risk in the unit). API for
  unit 3: `RangeDummies.spawn(station: Transform3D, brain: String) -> int`,
  `set_brain(id, name)`, `station_of(id)`, and a per-tick driver hook that a
  brain script implements (`func drive(bog: Bog, delta: float)`).
- **`MatchState.hit_landed(attacker_id, victim_id, amount, cause, point, bone)`**
  emitted from `report_damage` when damage is dealt, on every peer (add it to
  the `_do_damage` RPC payload or a sibling RPC). Units 4 and 5 hang off it.
- **`MatchState.place_pickup(kind, spot, keeps) -> int`**, a public wrapper on
  `_spawn_drop` for map-placed items, plus a signal `pickup_taken(id, kind,
  by_peer)` so a well knows when to re-mint.
- Gate: the range playthrough block (a `practice` branch in
  `tools/playthrough.gd` that proves a dummy spawned, took a hit, died and
  respawned, and a placed pickup was claimed, then passes), and unit tests of
  the roster filter in `smoke_test.sh`.

### 2. The place — Glowworm Grounds geometry, zones, sky, ambience

Owns: `scripts/world/maps/range_map.gd`, `scenes/world/maps/range.tscn`,
`resources/config/range_env.tres`, `range_sky.tres`,
`scripts/world/maps/range_ambience.gd`, `tools/parkour_report.gd` `EXPECT` row,
`tools/smoke_test.sh` map blocks (preview_map, parkour).

Layout, roughly 70 × 100 m, lodge at the south end, void beyond the north and
east edges. Zones, each a named `const` table and a `Node3D` group:
1. **Lodge**: raised deck, roof, eight spawns facing north, torch posts, the
   refill stone and the weapon racks (unit 4 places them on `Marker3D`s named
   in the `Racks`/`Wells`/`Stations`/`Targets`/`Dummies` marker groups — this
   unit authors the markers with `meta` saying kind and default behaviour).
2. **Throwing lanes** ×3, 32 m long, low rope fences, distance posts at 5 m
   steps, dummies at 8/15/22 m, a gong at 28 m on the middle lane.
3. **Long lane**, 60 m, for the bow: posts every 10 m, a dummy at 45 m, the orb
   launcher at the far end.
4. **Gallery**: waist-high walls with pop-up and strafing dummies at 12–20 m.
5. **Melee pit**: sunken ring 10 m across with circling and rushing dummies.
6. **Ability yard**: open ground with a clump of five standing dummies (magnet),
   a 3 m ledge (magnet pull over an edge), shield-plant marks.
7. **Parkour course**: sized from the reaches above, start and finish plates,
   checkpoint torches; ends on a summit overlooking the range.
8. **Void edge**: a railing with a gap, signposted.
9. **Letters and bases** for Capture practice.

Night bog: torches, glowworm lanterns on posts (emissive spheres + soft light),
low fog, fireflies from the island's ambience if reusable, the enchanted sky
with a low moon. Dressing after `super()`.

### 3. Dummy brains and stations

Owns: `scripts/world/range/brains/*.gd` (one file per behaviour),
`scripts/world/range/station.gd`, `scripts/world/range/parkour_timer.gd`, their
scenes, sounds they need (added to `tools/make_sfx.py`).

- Behaviours per the list above, each a small script with `drive(bog, delta)`
  writing the Bog's replicated state (position, yaw, velocity, grounded, and
  whatever the animator reads so a strafing dummy animates as running and a
  jumper as jumping). Deterministic-random per dummy from a seeded RNG.
- Stations: `Area3D` signposts; entering one steps a zone's behaviour, resets
  a zone (all dummies back to station, boards reset), or resets stats
  (unit 5's API). Lantern colour + chime feedback. Replicated: stations act on
  the host and broadcast their state.
- Parkour timer: start plate arms, finish plate stops; best time per session;
  a readout unit 5 can show.

### 4. Items in the world — wells, refill stone, weapon racks

Owns: `scripts/items/item_well.gd`, `refill_stone.gd`, `weapon_rack.gd`, their
scenes and meshes, the live weapon-swap path in `bog.gd`/`held_gear.gd`/
`bog_combat.gd` (coordinate: unit 1 has finished with those files by then).

- Well: pedestal + kind icon; keeps one pickup present via
  `MatchState.place_pickup(kind, spot, true)`; re-mints N s after
  `pickup_taken` (shield 4 s, magnet 4 s, potion 6 s, Elder robe 20 s). Glow
  dims while empty.
- Refill stone: on body entered (host), `grant_*` up to the caps read from
  `BogCombat`; 2 s per-player cooldown; chime.
- Weapon rack: on body entered, host sets the Bog's weapon, refreshes held
  gear and resets combat state; replicated so every peer sees the new weapon.
  Also update the roster's `weapon` for that peer so a respawn keeps it.

### 5. Targets and feedback

Owns: `scripts/world/range/range_target.gd` (board), `glow_orb.gd`,
`orb_launcher.gd`, `gong.gd`, the projectile hooks in `spear_projectile.gd`,
`arrow_projectile.gd` (and the sword's sweep if boards should take a swing),
`scripts/ui/range_stats.gd` + scene, hit-marker and damage-number code in
`hud.gd`/`hud.tscn` (range-only nodes), `scripts/world/range/range_stats.gd`
(the counter, host-authoritative, broadcast), sounds via `make_sfx.py`.

- Boards, orbs and gong are non-Bog targets: projectiles check for a
  `range_hit(point, by_peer, weapon)` method on the collider before the Bog
  cast. Boards score by ring, knock, and show distance; orbs burst; the gong
  rings and shows the distance.
- Feedback: hit marker on `hit_landed` and on `range_hit`; floating damage
  number (3D label, 0.8 s, rises and fades) at the point; distance text.
- Stats: per-weapon throws/hits/accuracy/kills/longest hit/streak; counted on
  the host from `hit_landed`, projectile launches and `player_killed`;
  broadcast; HUD panel (range only, corner, small) and the lodge board
  (`Label3D`s on a plank). `reset()` for unit 3's station.

### 6. Integration, gate, docs

Owns: the wiring of 2–5 into the map's markers, `docs/DECISIONS.md` entries
(one per unit, in this order), `docs/PLAN.md` item, `docs/ARCHITECTURE.md`
pointer, `docs/STATUS.md` count and resume point, a full `smoke_test.sh` run
green, and a set of `tools/snapshot.gd` photographs of every zone.

## Design decisions taken here (change them before unit 1 plans)

- Name: Glowworm Grounds, id `range`.
- Entry: both the picker and a **Practice** menu button (offline, no lobby).
- Dummies are real Bogs (the only thing damage lands on); hidden from every
  roster-derived screen; respawn at their station.
- Weapon racks exist (live swap in the range).
- Practice ends only by leaving; no results screen.
- Kill feed stays on (it is feedback).
