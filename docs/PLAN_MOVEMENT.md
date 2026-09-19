# The movement round — proposals, 2026-09-19

**Status: proposals. Nothing here is decided.** This is the research and the
options for a movement pass: things in the world that move you fast, items
that move you fast, and the verbs a Bog has. Carl weighs it; the hammering
happens on this document; only after that does it become groups, tickets and
D-records the way `PLAN_LETTERS.md` did. Linear parks the round as one Backlog
ticket until then.

Carl's brief, 2026-09-19: *"add some movement items … made in Tripo … a solid
few, maybe 3 or 4. Both items and in-game movement, on theme, tied into the
theme of the map, quick ways to go around the map and big jumps … basically a
movement pass."*

## 1. What a Bog can do today (measured, not remembered)

Everything is in `scripts/player/bog.gd` unless noted. Speeds are metres per
second, heights are apex rise.

| verb | numbers | source |
|---|---|---|
| walk / run / crouch | 2.3 / 5.4 / 1.6 | `:133-135` |
| backpedal | ×0.6 | `:74` |
| jump | launch 9.0 → 1.69 m | `:140`, D-026 |
| gravity | 24.0, ×1.35 while falling | `project.godot`, `_apply_gravity` |
| air control | accel 12, friction 1.5 | `:146-147` |
| bunny hop | +0.04×run per timed hop, cap 1.3×run = 7.0 | `:167-179`, D-052 |
| dive (double-tap jump, once per airtime) | +9.5 forward, +5.4 up; roll on landing | `:218-222` |
| slide (crouch above 3.78) | 4.0 for 1.0 s, 0.9 s cooldown | `:234-248`, D-123 |
| slide-jump | ×1.2 forward, ×1.12 up → 5.75 / 10.08 | `:262-263` |
| sword spin | +0.20×run, same 7.0 cap | D-068 |
| reach tiers (`JumpArc`) | jump 1.69 m, leap 2.30 m, big 4.23 m | D-042, `nav/jump_arc.gd` |

Missing: climb, mantle, vault, ledge grab, wall run, dodge, grapple, zipline,
swim, fall damage. The void is the only fall that costs anything.

Existing movement *modifiers*: the magnet (drag to 11 m/s, jump locked), the
Elder (×1.35 speed, jump to 2.64 m for 20 s), the letter carrier
(`capture_carrier_speed`), the draw (×0.5), holster (×1.10), slash (×0.85).
All of them go through one function, `target_speed()` at `bog.gd:1497`. A new
speed or jump modifier is a multiplier there plus a sync field, which is what
makes the cheap proposals cheap.

**Networking.** Movement is client-authoritative; outcomes are host's (D-004).
A thing that changes *your own* velocity or position runs on your client and
the synchroniser carries the result, so launch pads, dashes, buffs and
teleports cost no new netcode beyond a replicated "I did X" serial for the
animator, the way `dive_serial` and `sync_slide_jump_serial` already work.
Only things that move *other* Bogs (a pad that anyone can use is fine; a
thrown thing that pushes an enemy is not) need the magnet's RPC-to-the-victim
route (D-024).

**Animation.** Clips play at game speed over authored speed (D-095/D-098), so
a faster Bog needs no new clip. What needs a clip: any verb with a new body
shape (a mantle, a hang, a dash pose). A Mixamo take is a fetch by Carl, then
`clips.json` and a grip solve. The four recommended pieces below need **no new
clip**; the alternates each need one.

## 2. The maps, and what "around the map" means here

| map | size | verticality |
|---|---|---|
| Whisperbloom Hollow (default, seeded) | 23 m radius island | trees 15 m, shrine, arch, log bridges, mushroom grove |
| Rust | 43×63 m | container stacks |
| Kopje Crossing | 96 m | 123 rocks, 0.4–9.5 m, every one reachable on the real arc |
| Lantern Wharf | 36 m box | crates, kit props above head height or on the floor (D-084) |
| Halcyon Wake | four decks | every deck has a walk up and a hop up (D-057) |
| Twin Quarry | 48 m | bases a storey up on benches, 1.2 m kerbs, 3 m cover rule (D-082) |
| Highsun Grounds (range) | 60×90 m | banks 8 m, `LEDGE` 3.0, `UNJUMPABLE` 4.5 |

A run across the biggest arena is about ten seconds. Bases in Capture are
30 m apart. So "quick ways around" is not about distance; it is about
**skipping the ground contest**: over the middle instead of through it, up a
storey without the ramp, out of a magnet's reach, onto a carrier before the
vault. And "big jumps" means a tier above the 4.23 m the dive chain can do
today, which is exactly the tier the range calls `UNJUMPABLE`.

The letters game sets the stakes. In FFA collect the contest is the ten-second
standstill at the card (D-035); in Teams it is the three-second stand on the
enemy vault (D-092). Movement decides who *arrives* at those stands and how
fast help comes. A launch pad next to a hold point changes the game more than
any speed number.

## 3. Theme

The game's world is an enchanted night bog: peat, reeds, a mushroom grove,
torches, a shrine, fireflies, drifting spores, falling leaves, glowworms on
the range, a wool pouch in the hand. The items so far are folk objects: a
plank barricade, a lodestone magnet, a stoppered potion, a robe. D-135's rule
holds for anything new: a thing a player looks at, walks past or shoots is a
textured, themed prop, never a bare primitive. That is why the assets are
Tripo's.

Four of the seven maps are not bogs (a container yard, a wharf, a yacht, a
quarry). The honest answer to "tie it into the theme of the map" is a
decision, see §7: one prop set, the bog's, everywhere (the shield and magnet
already work this way), or a re-skin per map, which multiplies the asset count
by seven.

## 4. What other games did (the reference shelf)

Not to copy, to know the shapes and their known failures.

- **Launch pad** (Quake jump pads, Fortnite launch pad, Halo man cannon,
  Apex jump tower). Fixed, readable, everyone can use it, predictable landing.
  Failure mode: a pad with a fixed landing spot is a free kill for anyone
  watching the landing; the fix is letting the rider steer in the air (our air
  control is weak on purpose, so the pad's push should be along the rider's
  own run direction, not a fixed vector).
- **Bounce deployable** (Fortnite bouncer, Apex Octane pad). An item that
  makes a launch pad where it lands. Team utility and self-escape in one
  object. Failure mode: spam; fixed by lifetime and one-at-a-time per owner.
- **Zipline** (Apex, Fortnite). Best "around the map" tool in the genre;
  needs a hang clip, a rail solver, a mount/dismount rule, and it is a
  hitscan gallery for anyone under it. Heaviest to build.
- **Dash / shockwave** (Overwatch, Fortnite shockwave). A burst along a
  direction. Feels the best in the hand; balance is the hardest because it
  is a combat dodge as much as a traversal tool. Breaks the ten-second stand
  the least because it is short.
- **Speed/jump buff** (Fortnite hop rocks, Apex stim, Halo speed boost).
  Cheapest possible; already exists here as the Elder's multipliers. Needs a
  loud tell so the enemy knows.
- **Portal / rift** (Fortnite rifts, Splatoon launch, Portal). Point to
  point. Fastest "around". Disorients unless both ends are visible from far
  and the exit facing is authored. Guide line and minimap must know it.
- **Vertical lift** (Halo grav lift, Apex updraft, geysers). A column, not a
  pad: you rise and steer. Softer than a pad and readable from a distance.
- **Slide surfaces** (Apex's slopes, Titanfall). Make an existing slide
  faster on authored terrain. Uses what the game already has.
- **Mantle** (Apex, Titanfall, Fortnite Ch4). Not an item, a verb: the 1.2 m
  kerb is a hop today and a 2.3 m ledge is a leap; a mantle makes every edge
  under ~2 m climbable without a jump lined up. Needs one Mixamo clip.

## 5. Candidates, on theme

Each is one Tripo prop. W = a thing in the world, authored per map. I = an
item, a fifth kind of drop and a well on the range.

| # | piece | kind | what it does | theme object | needs |
|---|---|---|---|---|---|
| A | **Puffball** | W | a giant springy mushroom cap; run onto it, it throws you up a storey and on along your run direction | bog mushroom cap | no clip (`RunJump` → `AirLoop` → `LandHard`) |
| A' | **Spore pod** | I | the puffball as a throw: lands, swells into a puffball for 12 s, anyone can use it; the same mesh at pocket scale | closed puffball | reuses the magnet's throw, arc and state machine |
| B | **Fairy ring** | W | a ring of small mushrooms; step in, a beat later you stand up out of its twin, facing where the twin points | the folk portal | no clip; a `NavigationLink3D` so the guide line routes through it |
| C | **Hollow log chute** | W | a split, mossy log laid down a slope; sliding in it has no timeout and runs to ~10 m/s; a slide-jump off the lip is the big jump | fallen log, slick inside | no clip (`Slide`, `SlideJump`) |
| D | **Firefly jar** | I | uncork it: ×1.25 run and ×1.2 jump launch for 10 s, a swarm trailing you so everyone sees | corked jar of fireflies | no clip (`Drink`, the potion's) |
| E | **Gust bag** | I | a burst of marsh wind: +9 m/s along your move direction, one use | a tied bladder | one clip (a dash/lunge take) |
| F | **Reed line** | W | a vine strung post to post; jump on, hang, slide down it | vine and lantern posts | one clip (hanging), a rail system |
| G | **Bog vent** | W | a geyser of marsh gas on a timer; stand in it when it blows and rise 8 m | a bubbling pool | no clip; a timing readout (bubbles) |
| H | **Mantle** | verb | any edge up to ~1.9 m is climbed by walking into it and pressing jump | none | one clip (a climb-up take), no asset |

## 6. The recommended set (four Tripo assets, no new clips)

**A + A' Puffball and spore pod, B Fairy ring, C Hollow log chute, D Firefly
jar.** One asset each for the puffball (both scales), the ring, the log and
the jar. Why this four:

- Each answers a different need. The puffball is *up*, the ring is *across*,
  the chute is *down and fast*, the jar is *me, now*.
- Two are guaranteed on every map (authored world pieces) and two are luck
  (drops), so a map's routes are dependable and the items swing tempo.
- The item and the world piece share a mechanism (a spore pod *is* a
  puffball), so the game teaches itself: you have jumped off the big one
  before you ever throw the small one.
- Nothing needs a Mixamo fetch, so the round is not gated on Carl finding a
  clip. E, F and H are the alternates if the hand wants a new pose.

Starting numbers, for tuning in the hammering, not for shipping:

| piece | number | reason |
|---|---|---|
| puffball launch | 19.5 m/s up → ~8 m apex, ~1.5 s in the air, run momentum kept | clears `UNJUMPABLE` 4.5 with margin; the "storey" on every map is 3–4 m |
| puffball push | +4 m/s along the rider's run direction, none if standing | steerable landing, not a fixed kill spot |
| spore pod | throw like the magnet; pad lives 12 s; one live pod per owner | spam guard |
| fairy ring | 0.4 s beat both ends, spore burst both ends, 3 s per-ring cooldown | readable from across the map; a chaser can follow |
| log chute | slide cap 10 m/s inside, no timeout; on leaving, decay to the 7.0 hop cap within 1.5 s | the chute is a burst, not a new top speed |
| firefly jar | 10 s, ×1.25 run, ×1.2 jump launch (2.43 m apex) | under the Elder's ×1.35 / 2.64 m so the robe stays the prize |

Per map: two or three puffballs, one ring pair, one chute where there is a
slope, none where there is not. The island generator places them by seed; the
static maps carry `Puffballs`, `Rings`, `Chutes` marker groups, which becomes
part of the map contract BOG-29 is writing down.

## 7. Decisions this needs from Carl

1. **One prop set everywhere, or per map?** Recommend one set, the bog's,
   like the shield and magnet today. Rust, the wharf, the yacht and the quarry
   get the bog's mushrooms grown into their corners. A per-map re-theme is
   seven times the Tripo work and can come later map by map.
2. **The four**, or swap one for E (gust bag), F (reed line) or H (mantle)?
   Recommend the four plus H as a fifth, clip-gated, since a mantle is the
   thing every playtester will reach for first on the quarry's kerbs.
3. **Where items come from.** Today only corpses drop items (D-032) and the
   range's wells mint them. Movement items from corpses only is on-brand for
   a game where a death deals the next letter; authored item spawns on the
   map is the Fortnite answer and a new mechanism. Recommend corpses only,
   pod and jar at 10% each, and leave spawn points to a later round.
4. **A letter carrier and the ten-second hold.** Recommend: all of it works
   while *carrying* (the buff multiplies the carrier scale, so a jarred
   carrier is still slower than a jarred chaser), and nothing works during the
   *hold*, the way every other key already refuses it.
5. **Jump fatigue (BOG-28).** A pass that adds launchers should decide the
   fatigue rule with them: a puffball or chute launch is not a "jump" for the
   chain. Recommend folding BOG-28 into this round.
6. **Height ceiling.** An 8 m apex reaches container roofs, the quarry's
   columns and the yacht's top deck. D-082's ten-metre columns box the camera
   in on purpose; the wharf's kit is placed above head height (D-084).
   Puffballs will need a per-map look at what they expose.

## 8. What the round would touch (for sizing, not for doing)

- `bog.gd`: launch, chute and buff paths through `target_speed()` and two new
  sync serials; `bog_animator.gd`: the launch pose is the existing jump
  three-piece with `LandHard`.
- `pickup.gd` (two new `Kind`s, append-only), `match_state.gd` drop roll,
  `item_well.gd`, `bog_combat.gd` stock and keys, `hud.gd` slots, two new
  actions in `project.godot` and the Controls rows (BOG-42).
- `scripts/world/`: `Puffball`, `FairyRing`, `LogChute` nodes; marker groups
  in the six static maps; a placement rule in `island_generator.gd`.
- `scripts/world/nav/`: `JumpArc` learns the puffball tier; `jump_links.gd`
  emits a link per puffball and per ring so the guide line and minimap are
  honest.
- `tools/`: `parkour_report` gains the new tiers; `movement_check` gains
  `puffball`, `chute`, `jar` verdicts; `combat_range` gains a `pod` mode;
  `decimate_assets.py` gets four rows.
- Assets: four Tripo generations, decimated to ~6k tris, textured, through
  the existing route. Carl generates and downloads; the trap is Tripo
  remeshing (D-126), which does not bite props, only skins.

## 9. Process, as asked

1. This document: Carl reads, argues, strikes and adds. Comments on the
   Linear ticket or edits here.
2. Hammering: the numbers in §6 get walked in `movement_check` before any
   map is touched, so the tiers are real before the pads are placed.
3. Then the plan: §5–§8 become the groups of a `PLAN_MOVEMENT.md` in the
   letters-round shape, one Opus agent per group, tickets in Todo, a Linear
   project named after the round.
4. Then the build, the gate, the D-records, and BOG-18's playtest with
   movement on its list.
