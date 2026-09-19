# Architecture

How BOG is put together, and where the seams are.

`docs/PLAN.md` is the scope. `docs/DECISIONS.md` is why non-obvious things are
the way they are, and this file points into it rather than repeating it.
`docs/STATUS.md` is where the work is up to. Read this one when you need to know
*where a thing lives* or *what you are allowed to change without breaking
something two directories away*.

---

## The shape of it

Five autoloads and one scene at a time. Nothing else is global.

```
Settings        local, per-machine preferences. Never replicated.
Net             transport, roster, chat. Owns the socket.
MatchState      the authoritative match: alive, kills, score, phase, respawns.
SceneFlow       scene changes, the fade, the loading card, mouse-capture policy.
AudioDirector   bus volumes and a pooled one-shot player.
```

Exactly one scene is loaded at a time — `main_menu.tscn`, `lobby.tscn` or
`arena.tscn` — and `SceneFlow` is the only thing that swaps them.

The dependency direction is strictly one way:

```
        Settings          (depends on nothing)
           ↑
          Net             (roster; asks Settings for the player's name)
           ↑
      MatchState          (the match; asks Net who is here)
           ↑
   arena / bog / ui       (the world and the screens)
```

Nothing below reaches up. `Net` does not know a match exists; `MatchState` does
not know what a spear is; the arena does not know what a lobby is. The one
call that closes the loop between the world and the match is
`MatchState.register_arena(players_root, spawn_points)` — until something makes
it, there is no game. `scenes/world/arena.tscn` makes it, and so does
`tools/combat_range.tscn`, which is why a testbed can run the real match code.

### Why `Net` and `MatchState` are two files

They were one, briefly. Splitting them means a disconnect is handled in exactly
one place: `Net` notices the peer is gone and emits `player_left`, `MatchState`
listens and clears up the body that peer left standing in the arena. The roster
is `Net`'s business; a corpse in the world is not. It also means the whole lobby
can be exercised with no match code loaded at all.

---

## Authority

Host-authoritative, and the host also plays (**D-004**). There is no dedicated
server and no matchmaking backend — the host is peer 1.

| owned by | what |
|---|---|
| **the owning client** | its own Bog's position, rotation, animation state |
| **the host** | throws, projectile hits, deaths, respawns, scoring, phase, timers, the roster |

A client's Bog is client-authoritative because prediction and reconciliation is
a large amount of complexity to buy accuracy that a friends-only party game does
not need. `set_multiplayer_authority(peer_id)` is called on spawn and a
`MultiplayerSynchronizer` pushes the result out; remote Bogs run no input and no
gravity, they only smooth toward what the network last said.

One child is deliberately held back from that: the Bog's **`Combat` node belongs
to the host** on every machine (**D-024**). The owner decides *when* it wants to
throw and the host decides *whether* it happened, and it is the host that
broadcasts the answer — so the node that answer arrives at has to be the host's,
or every peer refuses it. That is also where a magnet's pull is delivered, because
`Players/Bog_<peer>/Combat` is a path both ends agree on and a spawned magnet's
is not.

Everything else is a request. `BogCombat` decides *when* it wants to throw and
plays its own feedback immediately so the game feels instant, but it sends an
intent RPC and the host decides whether the throw actually happened. Cooldowns
are therefore tracked twice on purpose — the local copy drives the HUD sweep
without a round trip, the host's copy is the one that counts, and a client that
lies about its cooldown gets its request dropped.

The spear is the one thing whose *feedback* is instant and whose *effect* is
not. A click starts the throw animation everywhere — locally, and on the other
peers through a cosmetic relay the host sends — and the spear leaves the hand
0.50 s later, on the frame the throwing arm reaches full extension. That
number is derived from the throw clip's window and rate rather than tuned:
`BogAnimator.THROW_RELEASE_TIME`, which `bog_combat.gd` reads. The aim is read
then and not at the click, so a moving target has to be led (**D-025**,
**D-029**). The Elder's bolt runs through the same windup and the same release
tick and comes out the other end as hitscan instead of a shaft (**D-038**) — on
its own clip, at its own rate, releasing at `MatchConfig.lightning_delay`
(**D-040**, **D-064**). One windup, one release tick, two outcomes; the only
thing that branches is which clip is fired and how fast.

The pattern throughout is **`rpc()` then call locally**. Both halves matter, and
only one of them has ever been exercised offline — see the testbed note below.

### Two things that deliberately do not replicate

- **The terrain.** Every client generates it from `Net.config.map_seed` and must
  land on a byte-identical island, because a spear that clears a ridge on the
  host has to clear it everywhere (**D-007**).
- **Ragdolls.** Local and cosmetic. A corpse that disagrees between machines
  costs nothing, and replicating thirteen physical bones costs a great deal
  (**D-010**).

Thrown spears sit between the two: every peer simulates its own copy from the
same launch parameters, so the flight is pure ballistics with no packets, and
only the host's copy is allowed to declare a kill.

---

## The transport seam

`Net` dials an **abstract `MultiplayerPeer`**. `ENetMultiplayerPeer.new()`
appears in exactly two places in the codebase, both of them in
`scripts/net/net.gd`:

- `host_lobby(port)` — `create_server()`
- `join_address(ip, port)` — `create_client()`

Nothing in `scripts/game`, `scripts/player`, `scripts/world` or `scripts/ui`
constructs a peer or names a transport. That is the seam a relay or signalling
transport slots into later (**D-005**): swap what those two functions assign to
`multiplayer.multiplayer_peer` and no game code changes.

This is not a hypothetical. `start_offline()` already exercises it — it assigns
an `OfflineMultiplayerPeer`, which reports itself as peer 1 and as the server, so
every `is_host` branch and every authority check downstream takes the shipping
path. That is the mechanism the testbeds run on (**D-011**), and it is the proof
the seam is real.

The invite code is the other half of having no backend: a Crockford-base32
encoding of an IPv4 address and port, ten characters, formatted `XXXXX-XXXXX`
(**D-005**). It also means the code carries the host's address, which is a
product decision worth confirming rather than a settled one.

*Which* endpoint goes into it is decided in one place, `Net.invite_code()`, and
there are two answers:

- **Local.** `select_ipv4()` picks the best address this machine has — a mesh
  VPN address (Tailscale, ZeroTier) ahead of a LAN one, because it reaches both
  — and the code carries it with the bound port. Good on a LAN and across a
  tailnet; useless past the host's NAT.
- **Public.** If the host has set `public_address` in `Settings` to the
  `host:port` of a [playit.gg](https://playit.gg) UDP tunnel, the hostname is
  resolved to an IPv4 **once, when the lobby opens**, and the code carries that
  address and the tunnel's *public* port. The socket still binds 27015; the
  agent forwards the public port to it. This is the internet path, and only the
  host sets anything up (**D-028**).

Both produce the same six bytes, so nothing about the code format, the join
path or the transport changes between them — `join_address()` gets four bytes
and a port and does not care where they came from. `invite_scope()` reports
which answer is in play (`LAN` / `TAILNET` / `INTERNET (PLAYIT)`) and
`invite_problem()` reports a public address that was typed and could not be
used, because the fallback code is well-formed and would otherwise fail
silently.

---

## The match, end to end

```
main_menu ──host/join──> lobby ──start──> arena ──> results ──> lobby
```

`SceneFlow` drives every one of those arrows, and it is also the only thing that
decides whether the mouse is captured. Cursor state is a stack of named holds
(`release_cursor("pause")`, `recapture_cursor("pause")`) rather than a boolean,
because the "I opened the pause menu and now I can't click anything" bug is what
a boolean gets you the moment two things want the cursor at once. Anything gated
on the cursor asks `SceneFlow.cursor_is_free()`.

Inside a match, `MatchState` runs a phase machine — warmup, then live, then
finished. Ending a match is a **broadcast, not a navigation** (**D-021**): the
host declares the match over and every peer's results screen comes up off that
signal, rather than each client deciding on its own that it is time to leave.
Spectating is a change of subject rather than a second camera (**D-020**) — a
dead player's camera re-targets a living Bog, it does not switch to some other
rig.

A match ends on one of five win conditions, `MatchConfig.WinCondition`, whose
ordinal travels on the wire, so it is only ever appended to: the kill limit,
last Bog standing, the clock, **Collect B·O·G** (letters out of corpses, held up
for ten seconds each, **D-033**, **D-035**) and **Capture B·O·G** (**D-051**).
Capture is capture the flag with the three letters, and a Teams mode: three
cards spawn once, a carrier walks one onto its own team's **vault** to bank it
into the team's mask (**D-049**), and a dead carrier's card lies where they fell
for the host's `capture_return_time` before going home. The vault is a small
point inside each base, pushed to the side furthest from the enemy, and a banked
card **stands on it** rather than returning to its home point (**D-068**) — so
what a team holds is visible in the world, and an enemy who stands on that vault
for `capture_steal_time` lifts the card back out and takes the letter off them.
It is the only score in the game that can go down. A carry is a letter hold with no deadline, so the card in the fist,
the carrier marker and the feed are the letters mode's own (**D-050**). The
bases and home points come from `CaptureLayout`, below.

The loading card exists because the arena is *generated* and that costs two to
six seconds inside `arena.gd`'s `_ready`. `change_scene_to_file` does not return
until that finishes, so the card has to be on screen *before* the call — there is
no main thread left to animate anything once the island starts building.

---

## The world

`scenes/world/arena.tscn` is whichever map the lobby chose. Which one is
`Net.config.map`, an id into `scripts/world/map_catalog.gd` that rides with the
roster the way `map_seed` does, so every peer knows the answer before the scene
loads; an id this build does not have sanitises to the island rather than
becoming a `load()` of a string off the wire (**D-030**). `arena.gd` branches on
the catalog entry's `kind` exactly once: a **procedural** map is generated below,
and a **static** one is a hand-made scene that brings its own environment, sun,
lights and spawn markers — the contract is written down in
`scripts/world/static_map.gd`, and no procedural step runs for one.

There are six maps.

**Rust** is the static one: a hand-made industrial arena, 42 x 28 x 64 m,
instanced whole from `art/maps/rust/rust.glb` (148 meshes, 96,301 triangles) by
`scenes/world/maps/rust.tscn`. Nothing about it is authored except four nodes and
eight coordinates — the geometry is the import, untouched. The two things the
import cannot supply, `StaticMap` builds at load in about 150 ms (**D-031**):

- **collision**, baked into *world-space* triangles on one `StaticBody3D` on
  physics layer 1, because two thirds of the map's nodes carry a non-uniform
  scale and a `ConcavePolygonShape3D` under one of those is not scaled reliably;
- **back-face culling**, which the importer turned off on all 30 materials
  because the export marks every one of them `doubleSided`.

Its walkable floor is at y ≈ 1.70, not zero, and its eight spawn pads sit on that
plane. They were found with `tools/preview_map.gd`, which scans the floor on a
grid and prints it, and they are re-checked by that same tool in the gate with
the physics the match will use — a ray that has to find a floor and a Bog-sized
capsule that has to fit.

**Kopje Crossing** is also static, and has no import behind it (**D-042**).
`scenes/world/maps/safari.tscn` carries the same four nodes Rust's does, but its
root script `SafariMap` extends `StaticMap` and *builds* the map before calling
`super()`: a superellipse plateau 96 m across at y = 0, a cliff skirt, and 123
MegaKit rock platforms from layout tables in eight zones. `super()` then bakes
all of it into collision exactly as it does Rust. Dressing — acacias, baobabs,
dead trees, boulders, grass, bushes, the waterhole — is added *after* `super()`,
so it is not trimesh collision; trees and boulders bring their own simple
colliders. Every peer builds the map independently, so every random draw comes
from one constant-seeded `RandomNumberGenerator` in a fixed order.
`SafariMap.platforms` is also the input to `tools/parkour_report.gd`, which
rebuilds the Bog's jump arc from `Bog`'s constants and fails the gate if any
landing is unreachable from the ground.

**Lantern Wharf** is a third built map, and the small one (**D-056**):
`scenes/world/maps/wharf.tscn` with `WharfMap` extending `StaticMap`, a 36 m
walled yard at dusk built from layout tables — container walls three high,
fourteen three-high towers, six single containers and eight crates, the north
half written and the south half mirrored. Its landings and its `off_limits`
tower and wall tops are both on `StaticMap` (the `Platform` record moved there
from `SafariMap`), so the same `parkour_report` walks it, proves no jump reaches
a tower top, and measures the longest eye-to-eye sightline. Its scene also
declares `Bases` and `Letters` for Capture B·O·G rather than leaving them to the
fallback. Its industrial dressing — pipe runs up the wall faces, machinery on the
wall tops, panels and floor markings — is Kenney Factory Kit props added after
the collision bake, and every one of them is above head height or flat on the
ground: on a map whose grammar is *this is cover and that is not*, a prop at the
height of a crate that a spear flies through is a lie (**D-084**).

**Halcyon Wake** is the fourth built map, and the tall one (**D-057**):
`scenes/world/maps/yacht.tscn` with `YachtMap` extending `StaticMap`. A hull
lofted from cross-sections (66 m with the swim platform, 13 m beam), and on it a
main deck at y = 0, an upper deck at 3.2, a sun deck at 6.2 and a flybridge at
8.8, each deck's open floor declared as a grid of landing records. Stairs are
invisible collision ramps under dressing treads, because the Bog has no step-up;
hop steps are plain boxes. The sea is a 2.4 km dressing quad in
`StaticMap.BACKDROP_GROUP`, which `preview_map` leaves out of the map's bounds,
and `void_height` is half a metre under it. `parkour_report` walks all four decks,
holds the mast `off_limits`, measures sightlines, and — for this map only
(`overboard` in its `EXPECT` row) — proves there is nothing to land on over any
edge of the deck. It declares `Bases` and `Letters`, with G on the sun deck.

**Twin Quarry** is the fifth built map, and the one drawn for a *mode* rather
than for a shape (**D-082**): `scenes/world/maps/quarry.tscn` with `QuarryMap`
extending `StaticMap`. A 48 m stone pit inside an 11 m cliff, with each team's
Capture G·U·B base four metres up on a cut bench in opposite corners, reached by
two 19 degree haul ramps and by nothing else — 4 m is over every jump the Gub
has from flat ground, and the ramps declare a landing every 0.9 m of rise so
`parkour_report` walks them the way it walks the yacht's stairs. A 1.8 m wall
rings each pad, with a gap at each ramp head and one drop port that only goes
down. Its symmetry is **rotational**, not mirrored, which is what puts the two
bases on a diagonal — and which forces the middle to be solid, because under a
turn every pad's line to its antipode runs through the origin. That rock was the
Stack; it is now a **13 m shaft down to a bench nobody reaches**, since
`void_height` is -10 and its floor is at -16 (**D-089**). A hole closes no
sightline at all, so of the nine lines the Stack was holding, the four
spawn-to-spawn ones — a hard check — are closed by widening the two **axis
rocks** to 8 m out at ±15.5, where all four of those lines pass. That deliberately
keeps the duty *off* the hole's rim, which is four low blocks placed by eye, one
to an edge and not mirrors of each other: a mirrored table builds eight to do
four blocks' work and jams them together (**D-090**, **D-091**). The rest, bench
to bench included, are open — the hole is meant to be the map's biggest hazard,
not a walled garden — and the sightline limits say so. G still sits on the other diagonal.

Its cover runs at three heights and the split is the map's rule: 1.2 m kerbs are
the step up, 3 m blocks break every line at head height — the sightline scan runs
at 1.45 m — and only eleven columns are 10.2 m. Tall rock boxes the third-person
camera in, so it is spent only where a line has to be broken for a Bog standing
on a bench or a wall top, whose eyes are 2.65 m to 5.45 m up and clear every
block on the map. Its props are MegaKit rubble, weeds, spoil and dead trees
banked against the stone faces. The weeds and pebbles are `MultiMeshInstance3D`
and pass straight through — a multimesh is not something `StaticMap`'s sweep can
pick up by accident, because that only collects `MeshInstance3D` — but the
**spoil rocks are solid**, built above `super()` and swept into collision like
any slab, sitting at kerb height and declared as landings (**D-085**). The line
is not "props are scenery" but "anything a player could mistake for cover is
solid".

**Whisperbloom Hollow** is the procedural one. It is built
from one integer seed at load, in an order that is load-bearing:

1. **terrain** — everything else asks it how high the ground is;
2. **landmarks** — hand-placed, and they get first refusal on where they stand;
3. **spawn points** — dodge the landmarks, then become obstacles themselves;
4. **prop scatter** — fills what is left, never landing on 2 or 3;
5. **torches** — in the spots the landmarks asked for.

`IslandGenerator` is also the map's **height oracle**: prop scatter, landmark
placement and spawn points all ask `height_at`/`slope_at` rather than
ray-casting, so they can run before any collision shape exists. Nothing in the
generator touches the global RNG — every random number comes from a local
`RandomNumberGenerator` or a seeded `FastNoiseLite`, both pure functions of the
seed. Break that and clients silently get different islands.

The main island is 23 m in radius (`IslandGenerator.MAIN_RADIUS`, **D-055**),
and every hand-placed coordinate on it — the hollow, the knoll, the shoulder,
the grove, the path hub, the firefly swarms — is written for the original 19 m
island and multiplied by `LAYOUT_SCALE`, so a change of size moves the
landmarks with the rim. The forest is a dozen trees about 15 m tall, and the
falling leaves are emitted from points inside those crowns rather than from a
ring over the map. `tools/island_report.tscn` measures all of it.

The surface mesh is built in **polar** coordinates, not on a square grid,
because the rim is the most-looked-at line on a floating island and a grid
leaves a staircase edge there. A polar ring lands on the outline by
construction, and the last surface ring *is* the first underside ring.

### Capture B·O·G bases and letter points

`scripts/game/capture_layout.gd` plans one base per team and three letter home
points for every arena, on every peer, from the spawn pads and whatever the map
declares (**D-051**). A static map built for the mode declares, on its
`StaticMap` root:

- `Bases` — one `Marker3D` per team **in team order** (first child = Team 1), on
  the floor at the middle of each base;
- `base_radius` — the export on `StaticMap`, default 4 m (a carrier also has to
  be within 3 m of the marker's height);
- `Letters` — three `Marker3D`s **in B, O, G order**, on the floor where each card
  starts and returns;
- `Spawns` as always; each pad belongs to the nearest base, and in this mode Bogs
  spawn only on their own team's pads.

**Lantern Wharf, Halcyon Wake and Twin Quarry declare all of them (D-056,
D-057, D-082); every other map plays on a placeholder fallback**:
the pads are split into one arc per team by bearing, each team's base is the pad
nearest its arc's middle, and the letters sit between the first two bases (B at
the midpoint, O and G either side across the axis). The host settles each card
onto a standable floor near the bases' height once the physics has stepped.
`tools/playthrough.gd` checks the result on all six maps, and says in its log
line whether the layout was declared or fallen back to. `CaptureBase` draws
each base in its team's colour, only in this mode.

### The practice range

**Glowworm Grounds** (`range`) is a map like any other in the picker, and
everything that makes it a practice range hangs off its own `Marker3D` groups
rather than off a mode (**D-112**..**D-116**, **D-119**). It is worth knowing
where the pieces are, because none of them is reachable from a search for
"practice":

- `scripts/world/maps/range_map.gd` + `scenes/world/maps/range.tscn` — the place
  itself, built from `const` tables before `super()` like every static map, and
  dressed after it. It authors the marker groups every other piece reads:
  `DummyStations`, `Signs`, `Plates`, `Wells`, `Racks`, `Targets`, `Boards`,
  plus the usual `Spawns`, `Bases` and `Letters`. Its build log prints the
  census, and the gate greps it, so a marker dropped by a later edit fails there
  rather than in a playtest: `27 dummies (27 live, 0 reserved), 4 wells, 3
  racks, 1 signboard(s), 9 targets`.
- **The hour is golden** (**D-119**). `resources/shaders/range_sky.gdshader` is
  a fork of Kopje's `safari_sky.gdshader` — the third fork, not a second set of
  values in the second — with a third gradient stop, a stated cloud shadow
  colour and a warm wash keyed on the angle to the sun; `range_sky.tres` is the
  material and `range_env.tres` derives its ambient from it. The scene's `Sun`
  stands 9° up on a bearing 30° east of north, so the west bank's 50.5 m of
  shadow falls off the map and no lane has the disc at its vanishing point, and
  a shadowless `Bounce` comes back from the south-south-west at −6°. That second
  light is `sky_mode = LIGHT_ONLY` and it is not optional: the sky follows
  LIGHT0 for its disc, and a second light reaching it would move the sun.
- `scripts/world/range/range_director.gd` — the one thing that walks those
  groups. Two lines in `range_map.gd` add it and `RangeDummies` after `super()`;
  it waits for `PLAYING`, then stands the dummies, the signboard and the parkour
  plates on their marks and calls `RangeItems.build(map)` and
  `RangeStats.build(map)` behind `ResourceLoader.exists` guards. It carries no
  RPC: since the stations went there is no shared state left to agree about.
- `scripts/world/range/range_dummies.gd` — the registry. A dummy is a **real
  Bog** on a roster row at id 900+, with only its `Sync` node handed to the host
  so it replicates without stealing a camera or reading a keyboard.
  `drive_to(bog, pos, yaw, vel, grounded, jumped)` is the single writer of a
  dummy's body *and* its snapshot; nothing else may touch a `sync_*` field.
- `scripts/world/range/brains/*.gd` — one file per behaviour, each a position as
  a function of time, because a dummy runs `move_and_slide` on no machine at all.
  **Which brain a dummy runs is authored per area** in `range_map.gd`'s `DUMMIES`
  table and the markers' meta, and never changes at runtime (**D-119**): a lane
  is one lesson and you choose the lesson by walking to a different lane.
- `scripts/world/range/signboard.gd`, `parkour_timer.gd` — the stats reset and
  the clock. The signboard is what is left of the six stations: a timber post
  and a board in the lodge's own timber with a carved STATS label and an
  `Area3D`, no lantern, no light and no chime, because the feedback is the HUD
  panel going to zero (**D-119**).
- `scripts/world/range/range_target.gd`, `gong.gd`, `glow_orb.gd`,
  `orb_launcher.gd` — things to shoot that are not Bogs. A projectile asks
  `collider.has_method("range_hit")` before it asks whether it is a body;
  damage still lands only on Bogs.
- `scripts/world/range/range_stats.gd` + `scripts/ui/range_stats_panel.gd` — the
  per-weapon counter (host-authoritative, broadcast whole at 4 Hz) and its two
  readouts: a HUD panel bottom-left and `Label3D`s on the lodge wall.
- `scripts/items/item_well.gd`, `refill_stone.gd`, `weapon_rack.gd` +
  `scenes/items/*.tscn` — the furniture. A well mints a real `Pickup` through
  `MatchState.place_pickup` and re-mints on `pickup_taken`; a rack swaps your
  weapon live through `MatchState.set_weapon`, which is the host deciding and
  not the lobby's refused-while-running request.
- Tools: `tools/playthrough.tscn -- range` (the practice branch),
  `tools/range_brains.tscn`, `tools/range_items.tscn -- all`,
  `tools/range_targets.tscn`, `tools/hud_range.tscn` `range` mode, and the usual
  `preview_map` and `parkour_report` with `map=res://scenes/world/maps/range.tscn`.

The one thing the range changed about an ordinary match is the **hit marker**:
`Crosshair.strike()` now fires on `MatchState.hit_landed` on every map, because
`hitmarker.wav` has fired on every landed hit since D-062 and the picture had
never caught up with the sound. Damage numbers and the stats panel stay
practice-only. Its shape is **D-122**: 3 px arms that land 40% oversize and pull
to size over 70 ms before the fade, a hit held 0.45 s, and a **kill** that is a
different event rather than a louder one — the four arms reach in through the
centre gap and meet as a full white X, held 0.6 s, with `hitmarker_kill.wav`
under it where `_apply_death` played `HITMARKER`. `strike()` takes a `kill` flag,
so `flash_hit` — the range's boards — keeps the hit shape by saying nothing.
The vocabulary is unchanged: `UIPalette.BOG` yellow is a hit, white a kill, amber
a board.

---

## Where things live

```
art/generated/   game-ready meshes and textures — committed, no Python needed
assets/          raw source art (.gdignore'd; the two kits are imported)
audio/sfx/       synthesised sound effects — committed, see tools/make_sfx.py
docs/            STATUS, PLAN, DECISIONS, ARCHITECTURE
resources/       shaders, environment, theme, bus layout
scenes/          player, items, ui, world
scripts/         game, items, net, player, ui, util, world
tools/           dev tools and testbeds — none of this ships
```

`scripts/` mirrors `scenes/`. A few files worth knowing by name:

| file | what it is |
|---|---|
| `scripts/net/net.gd` | the socket, the roster, chat. The transport seam |
| `scripts/net/invite_code.gd` | endpoint ⇄ ten characters, and back |
| `scripts/game/match_state.gd` | the authoritative match |
| `scripts/game/match_config.gd` | mode, limits, timers, use delays, friendly fire |
| `scripts/util/scene_flow.gd` | transitions, the fade, cursor policy |
| `scripts/world/arena.gd` | the map scene, and `register_arena` |
| `scripts/world/map_catalog.gd` | the list of maps; ids in, entries out |
| `scripts/world/static_map.gd` | what a hand-made map scene owes the match, and its collision |
| `scripts/world/range/range_director.gd` | the practice range's marker walker: dummies, the signboard, plates, items, targets (**D-112**..**D-116**, **D-119**) |
| `scripts/game/capture_layout.gd` | Capture B·O·G's bases and letter points: declared by a map, or the fallback (**D-051**) |
| `scripts/world/capture_base.gd` | a team's base drawn in its colour (**D-051**) |
| `scripts/world/island_generator.gd` | terrain, and the height oracle |
| `scripts/player/bog.gd` | a player character |
| `scripts/player/bog_animator.gd` | the blend tree, built in code over the clip library and its markers (**D-098**) |
| `scripts/player/bog_combat.gd` | spear, shield, magnet — and the Elder's bolt in the spear's place (**D-038**, **D-040**) |
| `scripts/player/ragdoll_builder.gd` | 13 physical bones, generated at runtime, their radii measured off the mesh (**D-099**) |
| `scripts/items/spear_projectile.gd` | hand-integrated ballistics, swept for hits |
| `scripts/items/pickup.gd` | what a death leaves on the ground (**D-032**) |
| `scripts/player/elder_robe.gd` | the robe skin on a live Bog's own skeleton (**D-037**, **D-038**, **D-099**) |
| `scripts/items/lightning_bolt.gd` | the bolt: one `ImmediateMesh`, two lights, forty sparks |
| `scripts/items/ward_flash.gd` | what a spear looks like when it fails to kill an Elder (**D-040**) |
| `scripts/ui/elder_track.gd` | how much of the Elder is left, for its wearer only (**D-040**) |
| `tools/import_clip.gd`, `tools/import_body.gd` | the character's whole art pipeline: Godot's importer plus a clip table (**D-095**) |
| `tools/movement_check.tscn` | the moves as numbers, counted in physics ticks on flat ground — 33 checks over `draw`, `slide_jump`, `landing` and `remote` (**D-123**). The `remote` one is the one worth naming: the snapshot handed to a second Bog is copied field by field out of the replication config `scenes/player/bog.tscn` actually ships, so a field left out of that config fails here rather than in a match. **In the gate**, headless |
| `tools/preview_carry.tscn` | the carry layer for all three props, and since **D-121** the bow's **head** clearance beside its floor and trunk: `-- measure` prints a `head PASS` line (`HEAD_MIN` 0.06 m, the limb segment against the head's skinned vertices and the `Neck`/`Head`/`HeadTop_End` joints), `-- probe` walks the whole 360 × 180 of the tilt at 15° and prints head, layered floor and bare-armed floor in every cell, and `-- candidates <weapon>` sheets that weapon rather than only the spear |

### The showroom

`tools/showroom/` is how a look or a layout gets chosen (**D-117**, **D-118**). A
theme is the one part of this game that cannot be judged from a diff, and a
screen layout is the second. So `showroom_theme.gd` is a parameterised copy of
`scripts/ui/ui_theme.gd` — the same file in the same order, so every knob traces
back to the line it replaced — driven by one dictionary per candidate, and
`showroom_layouts.gd` is one recipe per candidate that re-parents and re-anchors
the nodes of the **real** scene rather than mocking a screen up. Both are
photographed through `tools/ui_range.gd` on the real menu, the real lobby and the
real HUD, with the live 3D behind them.

What the lobby does with the layout it was given lives in two places and no
others: `lobby.gd`'s `_refresh_surface`, still the only thing that writes
`visible` on a panel, and `scripts/ui/bog_backdrop.gd`, which since **D-120**
carries `_bog_wanted(index)` beside `_plate_wanted` — on the Weapon and
Character page **the ring hides**, every Bog but your own slot, on this client
only, so the subject keeps the spot the ring put him in with the fire lighting
his face from the front. It is read by `_apply_slot` as well as by
`focus_on_local`, so somebody joining while you are choosing a skin re-dresses
the ring without putting the hidden half of it back on screen.
`tools/ui_range.gd`'s `lobby_character` mode prints what the portrait frame
contains, in fractions of the frame rather than pixels, because the window a
screenshot is taken at is not the window a player runs.

It stays in the tree as a dev tool, like `combat_range` and `preview_map`: the
next look and the next layout are compared the same way, and the recipes that
lost are the record of what was ruled out. Renders go to `tools/showroom/out/`,
which is gitignored — the tool that made them is committed instead.

---

`export_presets.cfg` is deliberately committed — it is the only record of what a
shippable build excludes (`tools/`, `assets/`, `docs/`), and ignoring it would
make "there is an export preset" a claim nobody could check out.

---

## The character: one body, one library, one table

The BOG is `art/bog/BOG.fbx`, the sculpt as Mixamo auto-rigged it, imported by
Godot itself at `root_scale = 180` (1.80 m, feet at 0). Its 72 clips are
animation-only FBX files under `assets/source/anims/`, one per row of
`assets/source/clips.json` — 72 rows, `SlideJump` and `Punch` the newest
(**D-123**, **D-124**, fetched and chosen in **D-125**) — and that table
is the whole rule table: per clip
its role, whether it loops, which body line the import squares to the body's
forward (`face`), and its events in seconds (`markers`). `tools/import_clip.gd`
runs inside Godot's importer on every clip and applies the row — records the
authored speed off the hips' travel, yaws the hips so the named line is
square, locks the hips to the axis, sets the loop mode, writes the markers —
then files the clip in `art/generated/bog_clips.res`, keyed by role.
`tools/import_body.gd` puts that library on the body's own AnimationPlayer at
import, so every scene and tool that instances the body has every clip. A
re-import is the build; there is no Blender (**D-095**, **D-096**, **D-097**).

`scripts/player/bog_animator.gd` reads nothing but that: every event is a
marker (`BogAnimator.marker("Throw", "release")`), every rate is the game's
speed over the clip's `authored_speed`. Three ground planes (plain, great
sword, archer) and a crouch plane over the body-relative velocity, an air loop
or an arc-scrubbed leap or dive, light and heavy landings, one-shots for the
actions, upper-body layers for the carry, the pull, the loose, the drink, the
cast and the throw (**D-098**). Bone names carry Mixamo's prefix everywhere:
`mixamorig_Hips`, `mixamorig_RightHand`.

**What a Bog's hands are doing is its own state** (**D-124**). `Bog.sync_holstered`
is an ON_CHANGE bool the owner writes on **H** and everybody reads, and it is the
fifth clause of `has_spear`/`has_bow`/`has_sword` — which is the whole
implementation, because the gates are where a weapon goes away. Holstered there
is no prop in either fist, `target_speed()` takes `FISTS_SPEED_SCALE` (the only
factor above 1.0, 5.94 m/s against 5.40), the HUD tile keeps the picked weapon's
photograph at the 20% "nothing to spend" level with H on the key cap, and the
primary click is a **punch**: `Bog.Cause.FIST`, 20 damage at 1.1 m inside a 50°
front on a 0.5 s cycle, thrown as an **upper-body one-shot** so you keep the
camera and full speed through it. `_bare_handed()` is the one sentence the
holster and the emote share, so the dance empties the hands too.

**The great sword has two attacks** (**D-124**): the primary click is a
three-slash chain on `SwordCombo`, windowed per slash between its own `swing_N`
and `end_N` markers, upper-body over the sword plane at `SLASH_SPEED_SCALE` 0.85
with turning and jumping allowed; `SwordSpin` (D-068) stays exactly as it was and
is now the **sprint attack**, taken on the speed the player is already carrying
rather than on a second key. The chain's clocks live on `Bog` beside the spin's,
because what they decide is what is in the fists and how fast the body travels;
only "which slash is next" stays in `BogCombat`.

**Movement's two new pieces** (**D-123**). A full draw costs speed —
`target_speed()` scales by `lerp(1.0, DRAW_SPEED_SCALE, draw_fraction())` with
`DRAW_SPEED_SCALE = 0.5`, so a full draw walks at 1.15 m/s on every screen,
because `draw_fraction()` reads the replicated `sync_draw`. And a jump out of a
slide is its own move, replicated as **`sync_slide_jump_serial`** — a second
ON_CHANGE counter beside `sync_jump_serial`, bumped in the same physics tick, so
the animator is told which take-off it was on the frame `_open_airtime` runs.
Crouch in the air pre-arms the pose through **`_crouch_pose`**, a second blend
beside `_crouch_blend` and the only one allowed to rise airborne: `_crouch_blend`
is the **rule** (the capsule, `is_crouching()`, the speed, the headroom) and
stays grounded-only, `_crouch_pose` is only what the body looks like. The camera
sits closer for all of it — `DISTANCE_DEFAULT` 3.1 and `DISTANCE_AIMING` 2.15,
shoulders unchanged.

**A role can ship before its clip.** `BogAnimator.clip_or(role, fallback)`
resolves a role to a stand-in while its FBX is absent — `SlideJump` to
`RunJump` and `Punch` to `Cast` for the hours between D-123/D-124 and D-125 —
with a single `push_warning` at `_ready` behind a static flag: once per run,
never per Bog and never per frame. Such a role is not in `REQUIRED_CLIPS`: a
missing *required* clip is a Bog that never moves and must fail the gate, a
missing optional one is a move drawn with the wrong picture. `tools/clip_check.gd`
skips a row with no FBX with a note, and requires `lift`/`apex`/`land` on
`SlideJump` and `hit` on `Punch` now that both are there. A search row
(`mixamo_query`) can have several takes on disk while one is being chosen; the
import keys them by file until one remains, counting the candidates in
`assets/source/anims/` rather than in the table (D-125).

**The bow's yaw correction follows the pelvis, not the clip.** The draw is an
upper-body layer square to its own hips; the archer's side-on is the pelvis the
`BowAim` plane drives, and the air branch and every full-body one-shot (`Land`,
`LandHard`, `Roll`, the slide, the take-off) replace that pelvis with a square
one while the layer goes on holding the bow. `BogAnimator.plane_lost()` is how
much of the plane is gone — the airborne blend and each shot's own fade weight,
read one frame late to match the pose in the skeleton, composed as a product —
and `BogAim` lerps `BOW_OFF_FACING` (0°) toward `BOW_OFF_AIR` (−92°) by it
(**D-127**). `tools/movement_check.tscn`'s `air_draw` leg is the witness.

**A skin whose download is not the body's mesh is baked, not extracted.**
`tools/extract_skins.py` reads each Tripo `.glb` under `assets/source/skins/`;
when its vertex count is the body's, the base colour is the skin. When Tripo has
regenerated the sculpt instead — the eleven of **D-126** came back at 9 124
vertices in their own UV layout — `tools/bake_skin.py` registers the body's
vertices onto the download's surface (quarter turns, similarity and affine ICP
for the whole; a similarity per bone of the body's rig, blended by skin
weight; then a smoothed non-rigid pull, to 1.9 mm) and paints every texel of
the body's layout from the nearest points of the download's paint that face
the texel's way. It bakes onto
`build/body_ref.glb`, the body as Godot imports it, written by
`tools/export_body_ref.gd`. A baked skin is a registered face, not the body's
own paint, and the eleven are **parked** in `Skins.PARKED` rather than in
`Skins.NAMES` until their downloads are redone on the original mesh
(**D-128**); the bake remains the route for a download that cannot be.

Grips are solved by their own tools against the new hands — `preview_bow`,
`preview_sword`, `preview_carry` — and the sheets are the judge; the ragdoll
measures its capsules off the mesh when it is built; the Elder's robe is a
skin, a mesh bound to the same skeleton by bone name (**D-099**). A skin is a
folder under `art/skins/`, a recolour or a clothing mesh (**D-100**).

Adding a clip is a row in `clips.json`, `python tools/mixamo_fetch.py` pasted
into the Mixamo tab, `bash tools/clip_imports.sh`, and an import.
`tools/clip_check.gd` is the gate for all of it; `tools/clip_measure.gd`,
`tools/clip_events.gd` and `tools/preview_bog.tscn` are how a clip is looked
at before a marker is placed.

---

## Two rules that are easy to break by accident

- **`queue_free()` is deferred.** A `while` loop that frees a child and re-reads
  `get_child_count()` never terminates. That hung the whole game on the sixth
  death of every match.
- **A testbed supplies things by hand.** Every integration defect this project
  has had was a thing wired into a testbed and into nothing else — movement
  input, the HUD, the mouse grab, the ambience path. When you add a harness, ask
  what it is providing that the real game does not, because that list is the
  list of things nothing is checking (**D-018**, **D-019**).

Verification is three tiers and the table of what each tool proves is in
`docs/STATUS.md`. The gate is `bash tools/smoke_test.sh`.
