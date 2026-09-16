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
| `scripts/game/capture_layout.gd` | Capture B·O·G's bases and letter points: declared by a map, or the fallback (**D-051**) |
| `scripts/world/capture_base.gd` | a team's base drawn in its colour (**D-051**) |
| `scripts/world/island_generator.gd` | terrain, and the height oracle |
| `scripts/player/bog.gd` | a player character |
| `scripts/player/bog_animator.gd` | the blend tree, built in code (**D-029**) |
| `scripts/player/bog_combat.gd` | spear, shield, magnet — and the Elder's bolt in the spear's place (**D-038**, **D-040**) |
| `scripts/player/ragdoll_builder.gd` | 13 physical bones, generated at runtime |
| `scripts/items/spear_projectile.gd` | hand-integrated ballistics, swept for hits |
| `scripts/items/pickup.gd` | what a death leaves on the ground (**D-032**) |
| `scripts/player/elder_robe.gd` | the robe on a live Bog's own skeleton (**D-037**, **D-038**) |
| `scripts/items/lightning_bolt.gd` | the bolt: one `ImmediateMesh`, two lights, forty sparks |
| `scripts/items/ward_flash.gd` | what a spear looks like when it fails to kill an Elder (**D-040**) |
| `scripts/ui/elder_track.gd` | how much of the Elder is left, for its wearer only (**D-040**) |
| `tools/build_bog.py` | the Bog's whole art pipeline: several source packs in, one `.glb` out |

`export_presets.cfg` is deliberately committed — it is the only record of what a
shippable build excludes (`tools/`, `assets/`, `docs/`), and ignoring it would
make "there is an export preset" a claim nobody could check out.

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
