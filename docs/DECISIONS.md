# Design & Engineering Decisions

Running log. Newest phase last. Each entry: what was decided, and why.

---

## D-001 — Engine: Godot 4.7.2 stable, GDScript, Forward+
The user has `Godot_v4.7.2-stable_win64` locally, so the project pins that version.
GDScript over C# to keep the toolchain to a single dependency (no .NET SDK required to
build). Forward+ renderer because the map leans on volumetric fog, many small dynamic
torch lights, and SDFGI/SSAO — all Forward+-only or Forward+-preferred features.

## D-002 — World scale: 1 unit = 1 metre
*The Gub's half of this is history: it is now authored at 1.80 m and imported at
`root_scale 1.0` (**D-029**). Everything else still holds.*
The Stylized Nature MegaKit is authored at roughly human scale (a common tree is ~7 m
tall, tall grass ~1.8 m). The supplied `Gub.glb` is 5.18 units tall in bind pose, so the
Gub is imported at **0.35 scale** → ~1.81 m. Spear (1.90 units) is scaled to ~0.75 →
1.42 m. This lets us use realistic gravity and jump tuning without fighting the kit.

## D-003 — Source meshes are decimated offline
*The Gub is no longer one of these targets — it has its own pipeline,
`tools/build_gub.py` (**D-029**). The three props below are unchanged.*
Every supplied `.glb` (`Gub`, `Spear`, `Lure`, `Mushroom/base_*`) is a ~500,000-triangle
photogrammetry-style mesh with a 4K texture. Eight networked Gubs plus spears, deployed
mushrooms and lures would be 5M+ triangles per frame before shadows — untenable.

`tools/decimate_assets.py` performs quadric-error decimation (`fast_simplification`) and
re-attaches UVs by seam-aware nearest-source-vertex transfer, then rewrites a clean `.glb`
into `art/generated/`. Skin weights are *not* transferred — they are solved on the
decimated mesh itself, for the reason in D-023. Sources in `assets/` are never modified — the
pipeline is re-runnable and the raw art stays pristine.

Targets: Gub 18k tris (skinned, drawn up to 8× plus shadows), Spear 4k, Lure 6k,
Mushroom 12k.

## D-004 — Networking: ENet, host-authoritative, host also plays
Godot's high-level multiplayer over ENet. The host runs the authoritative match state
(scores, kills, spawns, projectile simulation) and also plays. This is the right shape for
a casual 2–8 player party game: no dedicated server to operate, no matchmaking backend.

Split of authority:
- **Client-authoritative**: its own Gub's position/rotation/animation (replicated via
  `MultiplayerSynchronizer`). Cheating a position in a friends-only party game is an
  acceptable trade for eliminating prediction/reconciliation complexity.
- **Server-authoritative**: throwing (client sends an *intent* RPC), all projectile
  simulation, hit resolution, deaths, respawns, scoring, match phase, and timers.

## D-005 — Invite codes encode the host endpoint
The user asked for "click invite, get a key, anyone with the key can join". Doing that
across the internet with no fixed address normally needs a signalling/relay server, which
means infrastructure to run and pay for. Instead the invite code is a **Crockford-base32
encoding of the host's IPv4 address + port**, formatted `XXXXX-XXXXX`. Six bytes
of payload become exactly ten characters, so there is no padding and every code
is the same length.

This is real and works today over LAN, over a VPN (Tailscale/Hamachi/Radmin), or over the
internet with one forwarded port — and it needs zero backend. The code is opaque enough to
feel like a lobby key while remaining a pure client-to-client dial.

`docs/ARCHITECTURE.md` records the seam where a relay/signalling transport would slot in
later without touching game code (`Net` exposes `host()`/`join()` against an
abstract `MultiplayerPeer`).

## D-006 — Ragdolls are built at runtime, not authored
Hand-authoring 29 `PhysicalBone3D` nodes with fitted capsules into a `.tscn` is fragile and
unreadable in diffs. `scripts/player/ragdoll_builder.gd` walks the imported skeleton's rest
pose and generates the physical-bone hierarchy procedurally (capsule length/radius derived
from each bone's child offset). One code path, no scene bloat, and it survives a re-import
of `Gub.glb`.

## D-007 — The map is generated from a seed, not hand-placed
The island surface, its rocky underside, and the several hundred scattered props are
produced by a seeded generator (`scripts/world/`). Reasons: a hand-placed `.tscn` with 600
nodes is unreviewable; a seed guarantees every client builds a byte-identical map without
replicating placement; and it lets the layout be tuned by changing numbers instead of
dragging meshes. Landmarks (shrine, arch, bridges, torch ring, spawn pads) are placed
explicitly on top of the generated terrain, so the map still reads as designed rather
than as noise.

## D-008 — The Gub's animation clips needed three fixes before they were usable
*History. The asset these fixes were applied to no longer exists — the Gub was
rebuilt from eight Mixamo clips in **D-029**, which had to solve the facing
problem below a second time, on a different rig.*
Inspecting `Gub.glb` turned up three problems that would each have been a
mysterious bug later. All three are fixed in `tools/decimate_assets.py`, so they
stay fixed across re-imports rather than being patched around in game code.

**1. Every clip shipped twice.** `Idle` has two keyframes — a held pose — while
`Idle.001` has the 326 keyframes that are the actual animation. That is what a
Blender NLA export looks like when both the strip and its action get written.
The pipeline keeps whichever variant has the most keyframes and gives it the
clean name, so gameplay code asks for `Idle`, not `Idle_001`. Eight real clips
survive: Idle, SlowRun, FastRun, CrouchWalk, Crouch, Jump, Slide, SpearThrow.

**2. Every clip carried its travel baked into the root joint.** SlowRun walks
4.5 units forward over its 0.73 s; Jump arcs 12.6 units and rises 3.0. Left in,
the mesh slides out of the `CharacterBody3D` carrying it. The pipeline locks the
root joint's horizontal translation always, and its vertical translation only
when the rise is over 0.5 units — that keeps the weight-shift bob that gives a
run cycle its life while discarding the leap the physics body is already doing.

That baked travel is useful on the way out, though: it is the speed each clip
was *authored* to move at, and matching it is the difference between feet that
grip and feet that skate. The pipeline prints it, and `gub.gd` uses it:

| clip       | authored speed |
|------------|----------------|
| CrouchWalk | 1.21 m/s       |
| SlowRun    | 2.20 m/s       |
| Slide      | 3.00 m/s       |
| FastRun    | 4.01 m/s       |

**3. Every clip was authored at a different resting yaw.** Idle sits 65.8° off
the rest pose, CrouchWalk 33.9°, FastRun 13.4°. One clip at a time this is
invisible; the moment an AnimationTree blends between two of them the body
swings sideways on every state change.

Measuring this correctly needs forward kinematics: the root bone carries the
rig's own rest orientation, so reading a Euler yaw off its quaternion measures
the bone, not the body. `tools/rig_math.py` walks the rest hierarchy and takes
the facing from the line between the hips — the one pair of joints that stays
put while the arms and torso animate. The pipeline then applies a compensating
yaw to the root joint's rotation keys. Motion *within* a clip is untouched, so a
throw still winds the body up. After the pass every clip measures within 0.01°
of the rest facing.

## D-009 — The sky is a shader, and the environment is tuned around torches
Whisperbloom Hollow's sky (`resources/shaders/enchanted_sky.gdshader`,
`resources/config/arena_sky.tres`) is fully procedural: gradient, stars, moon,
aurora and cloud wisps are all computed in one `shader_type sky` pass. A
panorama texture would have been simpler, but it cannot animate, it cannot be
retuned without a round trip through an image editor, and a night sky that never
moves reads as a painted backdrop the moment a player stands still. Every
animated term is driven off `TIME` at speeds between 0.012 and 0.05 — a cloud
wisp takes about ninety seconds to cross the dome — so the sky has life without
ever pulling the eye during a fight.

**Cost is controlled by which pass does what.** The sky is drawn three ways per
frame: the screen, the radiance cubemap, and (because the shader declares
`use_quarter_res_pass`) a quarter-resolution buffer.

- *Aurora and clouds* — the only fbm noise in the shader — run **only** in the
  quarter-res pass and are composited back with premultiplied alpha. That is a
  16× saving on the expensive half of the sky, and the upscale blur is free art
  direction on something that is meant to look like vapour.
- *Stars* run **only** at full res. They are single-cell hash lookups, not
  loops, and in a 256 px radiance cubemap they would be sub-texel sparkle noise
  in the ambient term; in a reduced-res pass they would alias into crawling
  dots.
- The *cubemap pass* has no sub-res buffer to read, so it recomputes the
  aurora and clouds at one octave instead of three. The ambient light only ever
  wanted the low-frequency colour.

There is no raymarch anywhere. The aurora is three gaussian bands whose centre
heights wander with 2-octave noise; the moon is a disc with a phase terminator
in a disc-local frame, so its face does not slide as the camera turns.

**The moon follows LIGHT0.** With `moon_follow_light` on (the default) the disc
is drawn at `LIGHT0_DIRECTION`, so the arena's DirectionalLight3D *is* the moon
and the two can never disagree. `moon_direction` is the fallback when no
directional light exists. The arena is expected to carry one: cool
(≈`Color(0.62, 0.72, 1.0)`), energy ≈0.30, aimed at the island from
`(-0.42, 0.38, -0.82)`, shadows on. That value is deliberately low — it is fill,
not key. The torches are the key light.

**Colour uniforms are declared in linear space in the shader** so the in-source
defaults land on the same colour as the sRGB values `arena_sky.tres` writes back
through the `source_color` hint. Without that the two disagree by a gamma curve
and the shader's own defaults look like a different sky.

### The environment (`resources/config/arena_env.tres`)
- **Glow threshold 1.45, not 1.0.** The Gub is near-saturated yellow. At the
  default threshold he wore a permanent halo and read as a light source rather
  than a target. At 1.45 a torch-lit Gub peaks around 0.9 and stays crisp, while
  flames, the moon and emissive props still bloom hard.
- **Ambient energy 2.5 with the source set to the sky.** The number looks large
  until you remember what it is multiplying: the radiance cubemap of a night sky
  averages out almost black. At 1.0 everything outside a torch pool crushed to
  literal `(0, 0, 0)`; at 2.5 it reads as dark. Retuning the sky retunes the
  island's fill light for free, which is the whole point of sourcing it there.
- **Volumetric fog at density 0.02**, with the depth fog kept very thin
  (0.0035) purely to separate the island's far edge from the void. Torch
  OmniLights need `light_volumetric_fog_energy` around 2.0 to punch a visible
  halo through it.
- **SDFGI is off.** The island is generated at load and then never moves, so
  SDFGI's cascades would spend their budget re-solving static geometry. Sky
  ambient plus SSAO gets the same read for a fraction of the cost.

`tools/preview_sky.tscn` is the harness all of this was judged in — a floating
slab, torches, silhouette cones and a Gub, with the camera framing picked by a
trailing `horizon` / `up` / `edge` argument that `tools/snapshot.gd` passes
through untouched.

## D-010 — Ragdolls are local and cosmetic, and barely damped
Corpses are **not** replicated. Each client builds and simulates its own, so two
players see the same death land slightly differently. That costs nothing: by the
time a Gub is a ragdoll it has stopped being part of the game, and nobody makes
a decision from where a corpse ended up. Replicating thirteen rigid bodies per
death — with an instant-kill weapon and eight players — would spend most of the
bandwidth budget on scenery.

The bodies are generated from the skeleton's rest pose by
`scripts/player/ragdoll_builder.gd` (see D-006) and placed at the *current* pose
before simulation starts, so the corpse begins mid-stride rather than snapping
to a T-pose first.

One tuning note worth keeping, because it cost a debugging pass: the first
version used heavy damping (linear 0.35, angular 1.6) to stop corpses twitching.
It worked — so well that a Gub killed while standing still simply *stayed
standing*, held up by its own joint limits. A ragdoll that does not fall over is
worse than one that jitters. Damping is now near zero (0.02 / 0.22), joints are
slack (softness 0.92), and `can_sleep` handles the settling instead.

## D-011 — The testbeds run the real match, not a parallel offline branch
`Net.start_offline()` opens a session on an `OfflineMultiplayerPeer`: peer id 1,
`is_server()` true, no socket, no port, no firewall prompt. Everything
downstream — every `Net.is_host` branch, every `@rpc`, every authority check —
then takes exactly the path it takes when hosting for real. The `rpc()` half of
the codebase's `rpc()`-then-call-locally pattern simply reaches nobody, and the
local half still runs.

The alternative was an `if offline:` branch inside `GubCombat`. That would have
been three lines and it would have been wrong: the offline path is the one the
testbeds exercise every day and the networked path is the one that ships, so any
divergence between them rots in exactly the direction that hurts.

`tools/combat_range.tscn` builds on this. It writes fake entries straight into
`Net.players` for peer ids in the 900s, and `MatchState` spawns a Gub for each
without ever asking whether the peer behind one is real. The opponents are
therefore *remote* Gubs to the running client — no input, no gravity, no camera —
which is both what a target dummy should be and the only regular look anyone
takes at the remote-Gub code path before eight people do. Two of the three bugs
found on the first run of that scene were remote-Gub bugs.

## D-012 — Snapshot warmup is counted in physics ticks
`tools/snapshot.gd` used to count its own `_process` calls. On a fast card that
loop runs at several hundred frames a second, so "90 frames" meant a different
amount of *game* time on every machine and in every window size — and the first
few frames are the slow ones (scene load, shader compilation), during which the
physics engine catches up by running several ticks inside one draw.

It now caps `Engine.max_fps` to the physics rate and waits on
`Engine.get_physics_frames()`, so one warmup unit is one physics tick and a scene
that scripts itself off `_physics_process` is caught at the moment it intended.

This is not a tidiness fix. Every visual check in Phases 2 and 4 was made through
this tool, and the ragdoll was signed off on a frame that — under the old
counter — was about 0.2 s after death. The corpse pulls itself apart at 0.5 s.
A verification loop that silently samples earlier than you asked will certify
broken things, and did.

## D-013 — The ragdoll's joints were too tight, not too loose
A corpse held together perfectly in the air and detonated the instant it touched
the ground — always starting at a foot, reaching 200 m/s within a dozen ticks.
Three plausible causes were investigated and are recorded here so nobody spends
another afternoon on them:

- **The basis handedness** (`_basis_along`) was genuinely wrong once and is now
  right. Fixing it changed nothing.
- **`body_offset`** is correct. Instrumenting the corpse showed every bone
  tracking its rigid body exactly; the bodies themselves were separating.
- **Continuous collision detection**, which the small fast-moving shin capsules
  looked like a textbook case for, delays the blow-up by four physics ticks and
  fixes nothing.

The actual cause: a cone-twist joint driven past its limit does not clamp.
Godot's limit solver pushes back, and past a large enough violation it pushes
back hard enough to *add* energy. Chain thirteen of them and the corpse tears
itself apart. Landing folds a knee far further than the 44 degrees it was
allowed, so the explosion happened on the first ground contact, every time.

Bisecting the joint configuration is what proved it. With the angular limits
removed entirely (pin joints) the corpse settled normally. With Godot's stock
softness/relaxation/bias but the original spans, it still exploded. So the
solver tuning — the obvious suspect, and the thing D-010 spends a paragraph on —
was never involved. The spans were.

Two changes were needed. The spans are now wide enough to cover the range a
falling body actually reaches (knees and elbows to 105 degrees). And the joint
frame is rotated 90 degrees about Z, because a cone-twist measures swing and
twist about its frame's local **X** while the capsules run along local **Y**:
with an identity basis the cone opened sideways across the limb, so "swing"
limited rotation about the bone and "twist" limited the bend. A knee folding on
impact was being checked against a 14-degree twist limit.

The lesson worth keeping: **when in doubt, open a ragdoll joint up.** A corpse
that bends too freely looks rubbery, which is the intended look anyway. One that
bends too little does not look stiff — it explodes.

## D-014 — Thrown arcs are solved, not aimed
The lure is slow enough for gravity to matter — 22 m/s under 22 m/s² — so firing
it flat along the aim direction dropped it about five metres from the thrower no
matter where the crosshair was. A lure "lobbed past cover" landed at your feet
every time, and the ability was unusable in a way no amount of tuning would have
fixed.

The host now solves the launch angle that actually reaches the aim point, taking
the flatter of the two solutions so it reads as a thrown object rather than a
mortar shell, and falling back to 45 degrees — maximum range — when the point is
out of reach, so an over-ambitious throw still travels as far as it can.

This puts a hard ceiling on the ability at `s²/g`, about 22 m, which is a
feature: the lure pulls someone out of nearby cover, it is not a way to reach
across the island.

The wire format carries the **target point**, not a velocity. The client still
chooses where the lure goes and the host still chooses how fast it gets there,
so a modified client cannot fling one at an arbitrary speed. `LURE_GRAVITY` in
`gub_combat.gd` must stay equal to `Lure.GRAVITY`, which integrates the flight —
the arc is solved in one file and flown in another, and if they disagree the
lure lands somewhere other than where it was aimed.

The spear does not need this. At 42 m/s with a third of world gravity its drop
is small enough over its useful range that leading the target is a skill rather
than an obstacle, which is the point of D-004's fast, flat, instant-kill weapon.

## D-015 — Anything a still frame cannot prove gets a harness
Two things shipped as "done" that were not, and both failed the same way: the
only check on them was a rendered frame, and a rendered frame cannot show a
trend, a rule, or a decision.

The ragdoll was certified on a screenshot taken 0.2 s after death, and pulled
itself apart at 0.5 s (D-012 covers the clock bug that made that sampling
possible). The match rules ran, but only ever in free-for-all with one live
player — teams, lives, the clock and the results summary were written, compiled,
and never once executed.

So there are now three tiers of verification, each for a different kind of claim:

| tool | proves |
|---|---|
| `tools/preview_*.tscn` | it *looks* right — needs a person, always will |
| `tools/ragdoll_stability.tscn` | a corpse is still a corpse 150 ticks later |
| `tools/match_rules.tscn` | 42 assertions across 8 scoring scenarios |
| `tools/smoke_test.sh` | all of the above, plus the import, as one gate |

Two details make these worth more than they look. `ragdoll_stability` was
checked against the *old* builder and correctly FAILs — a regression guard that
has never been seen to fail is not a guard. And `smoke_test.sh` treats any
`SCRIPT ERROR` in the output as a failure, because Godot prints one and carries
on running: a clean exit code proves nothing on its own, which is exactly how
the lure managed to be "compiling" for a week while never once launching.

`match_rules` runs as a *scene*, not a `--script` main loop. A script main loop
is compiled before the autoloads are registered, so it cannot so much as name
`MatchState` or `Net` without failing to parse — and any script it statically
references inherits that failure, silently loading the scene without its script
attached. That is worth knowing before writing the next dev tool.

## D-016 — The sound effects are synthesised, not sampled
There is no sound library for this project, so `tools/make_sfx.py` generates the
whole set: filtered noise for the throw whoosh, a 150→62 Hz sweep with a noise
slap for a body hit, three *inharmonic* partials for the lure's struck-glass
chime (whole-number ratios would sound like a musical note rather than glass), a
rising tone for its fuse and a falling one for its pull.

For a game that looks like this, that is not a compromise. A Gub is a cartoon,
and short synthetic hits read as deliberate stylisation where a mismatched
library sample reads as an accident. It is also the same argument already made
for the meshes (D-003) and the ragdoll (D-006): generated means diffable,
tunable from a single number, and reproducible on any machine. The complete set
is 381 KB.

Placement carries as much meaning as the sounds. Impacts, throws, deaths and
deployments are **3D and positional**, because they are events in the world that
give away where you are. Three are deliberately **2D**: the spear regrowing in
your hand, the respawn, and the hitmarker. Each is feedback about your own
situation rather than something another player could hear — and the hitmarker in
particular is the only confirmation a thrower ever gets that a spear landed,
since the victim may be sixty metres away behind a tree and the spear is already
gone.

## D-017 — The engine version is part of the source, and 4.6 is not close enough
`project.godot` pins 4.7 (D-001) and that pin is load-bearing rather than
aspirational. Opening this project in Godot **4.6** does not degrade gracefully:
`AnimationNodeBlendSpace1D.add_blend_point()` gained a fourth `name` argument in
4.7, `gub_animator.gd` passes it, and the whole animation tree therefore fails to
parse. Every single check in `tools/smoke_test.sh` then fails — including the
ones that have nothing to do with animation — with

```
Parse Error: Too many arguments for "add_blend_point()" call.
             Expected at most 3 but received 4.
```

which reads exactly like a bug in this repository and is not one. That cost real
time to diagnose on a machine whose `/Applications/Godot.app` was 4.6.3.

Two things follow, both now in the tree:

- `tools/smoke_test.sh` **finds** the engine instead of hardcoding one path, and
  refuses a binary that does not report 4.7 rather than running it and producing
  a wall of misleading parse errors. Having several Godots installed at once is
  the normal state of a machine, not an exotic one.
- The correct diagnostic is `--version`, and it is worth reaching for early. A
  clean `--headless --path . --import` that rewrites **no** `.import` files is
  the confirmation that the engine in hand is the one the committed assets were
  generated by; if those files come back modified, the engine is wrong.

## D-018 — The arena instances the HUD, and nothing had ever put the two together
`scripts/ui/hud.gd` was written on `feat/ui` and opens with "the arena is
expected to instance this once". `scripts/world/arena.gd` was written on
`feat/island` and never did. Both branches were green, both were reviewed, both
were honest — and the game they merged into would have run every match with no
crosshair, no score, no kill feed, no scoreboard, no pause menu and no results
screen, because the one line joining them belonged to neither author.

Neither a code review of a branch nor a screenshot of a testbed can catch that
class of defect: `tools/hud_range.tscn` hangs the HUD on the combat range by
hand, so the HUD had been *seen working* the whole time. Only something that
walks the real path from the menu to the results screen can notice a join that
nobody made. That is what `tools/playthrough.tscn` is for (D-019), and finding
this is what it was written to prevent happening again.

The same merge produced a quieter version of the same bug. `Ambience.LOOPS`
pointed at `res://assets/audio/ambience/forest_night.ogg`, a path invented on the
island branch; the audio branch committed the real beds to
`res://audio/ambience/ambient_forest.wav`. `_build_audio` skips a file that does
not exist **in silence**, by design, so the island shipped with no ambience at
all and nothing anywhere said so. A silent fallback is the right behaviour for a
missing optional asset and the wrong behaviour for a typo, and there is no way
for the code to tell those apart — so the guard against it is a test that asserts
the sound is playing, not a louder `if`.

## D-019 — Anything that crosses two systems gets a playthrough, not a testbed
D-015 established that anything a still frame cannot prove gets a harness, and
four of them exist. Every one looks at a single seam: `match_rules` scores a
match with no island under it, `combat_range` throws a spear in a room with no
lobby in front of it, `ui_range` photographs screens that were never navigated
to, `ragdoll_stability` drops a corpse. All were worth writing. Not one of them
could see D-018, because the defect was not inside any seam — it was the absence
of a join between two of them.

`tools/playthrough.tscn` runs the whole path in one go — menu, host, lobby,
start, arena build, warmup, kills, results — through the real scenes and the real
autoloads, and asserts something at every stop. It is in `smoke_test.sh` and it
is the only check there that can notice a scene flow coming apart.

The rule this generalises to: **a harness per seam catches bugs inside parts, and
only a harness per path catches bugs between them.** Two agents working on
disjoint file sets will produce clean merges and broken games, and this is the
cheapest thing that notices.

## D-020 — Spectating is a change of subject, not a second camera
A dead Gub is hidden, never freed (`MatchState._apply_death`), so its
`GubCamera` is still alive and still holds the viewport. Spectating therefore
needed no new node: `GubCamera.spectate(gub)` swaps which body `_follow` tracks
and everything else — the spring arm, the collision mask that ignores players,
mouse look, shake, the aim zoom — is already solved and stays solved.

A separate spectator rig was the obvious alternative and would have had to
re-derive all of that, then drift out of step with the real camera the first time
either was tuned. The cost of the chosen approach is two guards in `_process`
(do not hand a view basis to a body that is not ours, do not let a corpse aim),
which is a good trade for not owning a second camera.

The target is held in the HUD as an **index** into `MatchState.living_gubs()`
rather than as a reference to a Gub. The list changes constantly underneath —
the watched player dies, respawns, or disconnects — and an index degrades into
"you are now watching somebody else" where a stale reference degrades into a
crash.

## D-021 — Ending a match is a broadcast, not a navigation
The results screen's "back to the lobby" moved exactly one person. Every other
client stayed on a results screen whose only remaining exit was leaving the
session, because `Net` had no "the match is over, everyone come back" message at
all — the previous author noted this in a comment rather than fixing it, which
was the right call at the time and is fixed now.

`Net.request_return_to_lobby()` and `Net.request_rematch()` are host-only and
broadcast. A match is something a lobby does together, so ending one or running
it again is a decision with one owner, and the buttons that make it are shown
only to the host; everyone else is told who they are waiting for. A *client's*
own "back to the lobby" still works and still moves only them, because leaving a
match you are finished with should never need anyone's permission.

A rematch deliberately keeps the map seed. "Again" is a request for another go at
the match everyone just agreed to, and quietly handing them a different island
would be answering a different question. Rerolling the map is a lobby control.

A related hole was open in the same place: a client that dropped mid-match left
its Gub standing in the arena **on every other machine**, because `Net` erased
the roster entry and nothing told `MatchState` to clear up the body. It stayed
targetable and, worse, kept counting toward "last Gub standing", so a lives match
could reach a state where it could never end. `Net.player_left` is broadcast now,
and `MatchState` frees the Gub and re-runs the win check.

## D-022 — Two processes, one socket: what offline mode could never show
*Since D-044 this is in the gate, bound to loopback on a random port, and the
engine error it always reported was the harness's own teardown.*
D-011 argued that `Net.start_offline()` is the right shape for a testbed, and it
was: peer 1, `is_server()` true, no socket, and every `is_host` branch and
authority check downstream takes the shipping path. That argument has one hole it
was always honest about — `rpc()` reaches nobody. Only the "call locally" half of
the codebase's rpc-then-call-locally pattern had ever run, and **nothing had ever
been serialised**.

`tools/net_loopback.tscn` and `tools/net_test.sh` close it on one machine: two
real Godot processes, a real ENet socket on 127.0.0.1, and nine stages —
connect, roster, name collision, config, chat both ways, match start, the arena
with the client's three abilities used in it (added later, by D-024), a kill, and
a disconnect. Both peers load the real arena and build the same island from the
replicated seed, so the kill is asserted end to end: the host calls
`report_kill`, the client's `player_killed` fires, and both sides' `stats` agree.

It is deliberately **not** in `smoke_test.sh`. It binds UDP 27015, and a firewall
prompt would hang an automated gate with no way to tell that apart from a hang in
the game.

Three bugs fell out of the first run, and the interesting thing about all three
is *why* offline mode hid them:

- **The host RPC'd itself.** `send_chat`, `set_ready`, `set_team` and
  `set_name_local` all sent to peer 1 and then called locally, and on the host
  peer 1 is itself. Godot refuses (`RPC on yourself is not allowed by selected
  mode`) once per chat line for the whole session. Nothing was lost — the local
  call did the work — so the only symptom was a filling log.
  `OfflineMultiplayerPeer` swallows `rpc_id` in silence, so no testbed could see
  it. The fix is to send only when we are *not* the host.
- **A spawned Gub raced its own synchronizer**, and chasing it turned up a
  second, larger bug behind it. `_create_gub` is reliable; the
  `MultiplayerSynchronizer` pushes position as unreliable from the moment the
  node enters the tree. Different ENet channels, no ordering between them, so an
  update arrives before the node it addresses exists. Offline has no channels to
  race.

  The first attempt — hold the owner's synchronizer quiet for a third of a
  second — barely helped, and the reason why was the real finding: **the host
  began the match as soon as its own island had built, while other peers were
  still building theirs.** The island is generated and blocks the main thread for
  two to six seconds per machine, so the host was spawning Gubs and replicating
  them into peers that had no arena yet. Worse than the noise, `_create_gub` is
  sent once and never re-sent, so a peer still building when it arrived could
  miss a spawn permanently and spend the match in an empty arena including its
  own body. That never actually bit, because the RPC queues behind the blocking
  build rather than being dropped — but that was luck, not design.

  So `register_arena` now reports up to the host, and the host waits for every
  peer before starting (with `ARENA_READY_TIMEOUT`, so one crashed peer cannot
  hang a lobby for ever). Nobody plays until everybody can. With the receiver
  guaranteed to have an arena, the quiet window only has to outlast channel
  reordering, which is what it is sized for now.

  `MultiplayerSpawner` remains Godot's real answer — it puts the spawn and the
  state on one ordered path — and adopting it is a rewrite of `_create_gub` worth
  doing before this ships to strangers.
- **`MatchState` asked a peer that was already gone**, exactly as `Gub.is_local`
  used to. Everything there goes through `Net.local_id()` now, which guards it.

Two paths worked correctly the first time over a real socket and are worth
recording as such: the connect timeout (a client dialling a dead host fails
cleanly at eight seconds with the right message) and the bind-failure branch
(`Could not open port 27015` when something already holds it).

What this still cannot tell anyone: latency. Loopback has none, so nothing here
says whether a client-authoritative Gub *feels* right on a real link, or whether
the lure's client-side pull reads as fair to the person being pulled. That needs
two machines and remains the largest untested thing in the project.

## D-023 — The Gub's skin was rebound, because the tearing was in the weights
*History. The mesh, the rig and `tools/rig_clean.py` are all gone — see **D-029**,
which records what the replacement asset is worse at, measured with the same tool.*
D-008 fixed what was wrong with the Gub's *clips*. It did not touch what was
wrong with its *bind*, and that was the larger problem: at a dead run, triangles
detached from the Gub's back and hung in the air behind it.

**A number first.** "It tears" is not something you can fix twice and compare,
so `tools/rig_report.py` runs the same linear-blend skinning the GPU runs, over
every clip at 60fps, and reports four things: how far mesh edges stretch, the
third derivative of vertex motion (which spikes at a bad keyframe and at nothing
else), the gap between a looping clip's first and last pose, and how differently
the left and right halves are bound. On the asset as it shipped, 19% of vertices
sat on an edge that stretched past 1.5× its rest length.

Ratios turned out to be a poor headline: the mesh has edges a fifth the median
length, where half a millimetre of drift reads as "6×". The metric that matches
what an eye sees is edge growth measured against the body's own size, and that
is what `torn` counts.

**What was actually wrong.** Seven of the twenty-nine bones — `breast.L/R`,
`pelvis.L/R`, `heel.02.L/R` and `spine.005` — rotate by exactly 0.0° in every
clip. They are Rigify helpers, meant for posing and never for deforming.
Automatic weights does not know that and gave them 19% of the mesh, including a
band of chest either side of the armpit. That band stayed welded to the ribcage
while the vertices beside it, bound to `upper_arm.L`, swung through 89°. That
one boundary was the worst edge in the file, at 99× its rest length.

The same blindness bound the right heel to `heel.02.R` and the left to `foot.L`,
so the two feet deformed differently — one bending at the ankle, the other
pivoting around a point behind it.

**What replaced it** (`tools/rig_clean.py`). The helpers are unbound and the
skin is computed rather than painted: label each vertex with the nearest bone
*segment*, then delete any label region that is not connected across the surface
to the bone it names — the chest can only reach the arm bone across open air, so
that label is a lie — then diffuse the labels by solving `(A + a L) W = A P` with
the cotangent Laplacian. Clamping the cotangent weights at zero keeps that an
M-matrix, which is the guarantee that no weight overshoots into [0,1]; and since
`L` annihilates constants, the rows sum to exactly 1 with no renormalising.
Finally left and right are averaged so the Gub deforms symmetrically.

`spine.005` is deliberately left bound. It is as motionless as the rest, but it
is a link in the neck chain rather than a helper hanging off one, and binding it
is what makes the neck's falloff graded instead of a step halfway up.

**The bind is solved on the decimated mesh, not transferred onto it.** This
reverses part of D-003. A nearest-source-vertex transfer of a smooth weight
field does not arrive smooth — doing it that way put back a tenth of the tearing
this removes — so `decimate_assets` now carries only UVs across and binds the
finished 18k-triangle geometry directly. The seam-aware transfer still earns its
place for UVs, which genuinely are per-corner data with no other source.

**Three more things were wrong with the curves**, beyond D-008's three:

- **Quaternion sign flips**, 44 of them. A quaternion and its negation are the
  same rotation and the exporter emits both; between two keys that straddle the
  sign, interpolating the *numbers* takes the long way round the sphere.
- **Corrupted keyframes.** `toe.L` in `SlowRun` turns 155° in one 60th of a
  second and comes back — an axis flip in whatever produced the bake.
  `forearm.L` in `Jump` holds still to within half a degree for five frames and
  then leaves at 51° per frame, a pose snapped in with no ease at all. Both are
  the same measurement: an angular acceleration nobody authored. Keys are eased
  back toward the local trend only in proportion to how far past a per-track
  threshold they sit, so ordinary motion is left bit-identical — the median
  acceleration across every track is unchanged at 1.87°, while the worst falls
  from 122° to 18°.
- **Two thirds of every clip was dead.** 474 of 696 channels never leave the
  rest pose — every `scale` track, and every `translation` but the root's. And
  because Blender bakes from frame 1, each clip's first key sat one frame in,
  so a looping clip held its opening pose an extra 60th of a second every time
  round: a stutter once per stride at a 32-frame sprint.

**`Crouch` was the T-pose.** It shipped as two keyframes of the bind pose, so a
crouching Gub stood bolt upright with its arms out. There is no other crouched
motion in the file, so the pose is taken from `CrouchWalk` at the frame where the
skeleton is closest to its own mirror image — the passing pose, legs together —
rather than by guessing which frame of a cycle that is. Its ground position comes
from the clip's start, not from that frame, or the still pose would stand a
stride and a half to one side of the body carrying it.

**Result**, on the shipped `art/generated/gub.glb`:

| | before | after |
|---|---|---|
| edges torn (grown >2% of body) | 1294 | 257 |
| worst edge growth | 7.66% of body | 4.42% |
| worst vertex jerk | 0.419 | 0.119 |
| worst angular acceleration | 122.4°/frame² | 18.5° |
| worst single-frame turn | 154.7° | 45.9° |
| quaternion sign flips | 44 | 0 |
| animation channels | 696 | 222 |
| file size | 2.17 MB | 1.97 MB |

What none of that proves is that it *looks* right, so it was also checked by eye
in Godot at the worst frame of each clip. The flying triangles are gone; the hip
reads as one surface; the crouch crouches. The remaining 257 torn edges are at
the outside of hard bends, which is where linear-blend skinning always loses and
where the fix is a corrective shape, not a better weight.

## D-024 — The `Combat` node belongs to the host, not to the Gub around it
The first real playtest found that **a non-host player's abilities happened for
nobody** — not for the other players, and not even for themselves. The thrower
saw their cooldown sweep, because that is predicted locally, and nothing else:
the spear stayed in their hand, no mushroom grew, no lure flew. The host's own
abilities worked perfectly for everyone, which is what made it look like a
rendering bug rather than a networking one.

Every non-host console said what was actually happening, three lines per press:

```
ERROR: RPC '_do_throw_spear' is not allowed on node
       /root/Arena/Players/Gub_565667163/Combat from: 1.
       Mode is "authority", authority is 565667163.
```

`MatchState._create_gub` calls `set_multiplayer_authority(peer_id)` on the Gub,
and that is recursive, so the `Combat` child was owned by the client too. But
`GubCombat`'s traffic runs in *both* directions: `_request_*` goes client → host
and is `any_peer` with a sender check, while `_do_*` goes host → everyone and is
`authority`. Godot checks an `authority` RPC against whoever owns the node it
**lands on**, so a broadcast from peer 1 arriving at a node owned by peer
565667163 is refused — on every machine, including the thrower's own.

So `_create_gub` now hands that one child back:
`combat.set_multiplayer_authority(1, false)`. It reads oddly next to D-004 until
you say the split out loud: **the owner decides *when*, the host decides
*whether*.** The node the deciding lands on is the host's. The alternative —
`@rpc("any_peer")` on the three `_do_*` methods plus a
`get_remote_sender_id() == 1` guard in each — works, but it makes three methods
carry a check that the authority system exists to make for them, and it would
leave `Combat` owned by a peer that never broadcasts anything from it.

Two things this did not touch, on purpose. The `MultiplayerSynchronizer` beside
`Combat` must keep belonging to the peer whose position it publishes, which is
why the call is non-recursive. And `Gub.is_local()` still asks the *Gub*, so
input, movement and the camera are unaffected.

**The lure's pull was the same bug wearing a different hat.** `Lure._catch` runs
on the host and told each victim's client to apply the pull with
`_pull_target.rpc_id(peer, ...)` *on the lure node*. An RPC is addressed by node
path, and a lure has no path two machines agree on: every peer builds its own
copy into `spawned_items`, and Godot disambiguates a duplicate name with a
counter local to that process. Before this fix the client had no lure at all and
the log said so —

```
ERROR: Node not found: "Arena/SpawnedItems/Lure" (relative to "/root").
ERROR: Invalid packet received. Requested node was not found.
```

— and after it, two lures in the air would have been enough to deliver a pull to
the wrong crystal. The message now lands on `GubCombat.apply_lure_pull`, because
`Players/Gub_<peer>/Combat` is a name both ends already have and is now owned by
the host, so it can stay an `authority` RPC with no guard. The host/victim split
from `Lure`'s header is unchanged, and `caught` still carries the whole victim
list, which is what `tools/combat_range.gd`'s `lure` mode listens to.
`ShieldMushroom` was checked for the same shape and has no RPCs at all.

**Why nothing caught this.** `net_loopback`'s kill stage kills the client by
calling `MatchState.report_kill` on the *host*, which never goes near
`GubCombat`. Eight green stages and a release tag, and no stage had ever asked a
non-host peer to *do* something. Stage 7 now does: the client throws a spear,
plants a mushroom and lobs a lure through the public `try_*` calls, and both
peers assert the three items exist and that the spear left the client's hand —
which is the host's broadcast arriving, not local prediction. The throw is short
enough that the thrower is inside its own lure's radius, so the same stage
exercises the pull travelling back the other way. `net_test.sh` also fails a peer
outright on `is not allowed on node` now, because Godot prints that on the
*receiver* and carries on, so the sender is told nothing and the damage surfaces
somewhere else entirely.

That is the same lesson as D-018 and D-019 with a new seam: **a harness proves
what it exercises, and this one was exercising only the host.**

## D-025 — The spear leaves the hand at the animation's release, not at the click
*Still the design. The number moved: the release is 0.71 s into the new throw clip,
not 0.57 s, and it is derived rather than measured by hand — see **D-029**.*
The first playtest's complaint was "it throws and then the animation comes in
later". It was right, and it was the wrong way round: `try_throw_spear` spawned
the projectile on the frame of the click and fired the `SpearThrow` OneShot
underneath it, so the spear was already twenty metres away while the Gub was
still drawing its arm back. Nothing about the throw could be *timed*, either —
the aim was sampled on the click, so a target that ran during the animation was
hit anyway.

So the click now starts a windup and the spear leaves at
`GubCombat.THROW_RELEASE_TIME`, **0.57 s** later, with the aim read at that
moment and not before. In the designer's words, you have to time it out: a Gub
that walks during your windup has to be led.

**Where 0.57 comes from.** Not from taste. `SpearThrow` is 1.53 s, and the
`hand.R` bone tracked against the spine through an `AnimationPlayer` says the
arm draws back until 0.39 s, whips up over the shoulder to its highest at
0.54 s, crosses in front of the body at 0.55 s, and reaches furthest forward at
0.60 s. A thrown object separates at peak forward hand speed, which is the
0.54-0.60 s stretch; by 0.60 the hand is already decelerating and a release
there would read as a push rather than a throw. `tools/preview_anim.tscn` takes
an optional `from`/`to` window now, so a contact sheet can be made of that sixth
of a second instead of of the whole clip — six evenly spaced Gubs across 1.53 s
put one sample anywhere near the release, which is not enough to pick a frame
off. The OneShot's 0.10 s fade-in needs no allowance on top: the clip barely
moves for its first 0.21 s, so the blend has long finished before anything the
eye is following depends on it.

**Four consequences, and they are the interesting part.**

- *The windup is a broadcast of its own.* A tell only the thrower can see is not
  a tell. The thrower plays the animation on its own click; the host relays a
  cosmetic `_do_throw_windup` to everyone else, and the thrower's copy of that
  relay returns early on `_gub.is_local()` — replaying it half a round trip in
  would snap the arm back to the start of a throw it was in the middle of.
  `_do_throw_spear` no longer calls `play_throw()` at all, for the same reason.
  The relay is deliberately **not** gated on the host's cooldown: it is
  cosmetic, and a Gub that winds up and produces no spear is an honest picture
  of a client that asked for a throw it could not have.
- *The cooldown starts at the click, and the HUD had to be told.* The input is
  spent either way, and a crosshair that sits ready through half a second of
  windup only invites the second click that will be refused. The local
  prediction is therefore `THROW_RELEASE_TIME + spear_recharge`, and the HUD
  divides by `GubCombat.spear_cycle()` rather than by the recharge alone —
  otherwise the ring pegs at full through the windup and then jumps, which reads
  as a stall rather than as a throw being made. The host's
  `_server_spear_ready_at` still starts when the throw actually happens, and the
  two land on the same instant.
- *The held spear stays in the hand until the release.* `HeldSpear`'s header
  says an empty hand is how other players read that you are harmless, so the
  timing has to be honest: the hand empties at 0.57 s, when the spear really is
  gone, and not on the click.
- *A windup can be cancelled.* Dying, being respawned, or losing ownership
  mid-windup drops the throw — the animation is left to fade out on its own,
  because it is cosmetic, but no spear comes out of it. `reset()` clears a
  pending one along with the cooldowns.

**What it cost the harnesses.** `tools/smoke_test.sh`'s "spear kills" check
snapshots `combat_range` in `hit` mode, which clicks on tick 20; the spear now
appears on tick 55 and the kill lands on tick 75, so that warmup went from 70
ticks to 110. The old count would have failed with a message that reads exactly
like a broken throw. `tools/net_loopback.gd` needed no change at all — its stage
7 waits on the spear *existing*, with a 20 s timeout, rather than on a frame
count. That is the difference between a harness that waits for an outcome and
one that waits for a clock, and only one of them survives a timing change.

## D-026 — Single jump and double-tap dive, and why the old one froze
*Still the design, on a rebuilt graph. The clips, the windows and the freeze-proof
rule are **D-029**; the input design and the serial-not-flag pattern below are
unchanged.*
The same playtest reported two things that turned out to be one thing: "the dive
plays one time in a hundred", and "there is a weird position the jump goes into
that isn't the actual animation".

`Jump` is 2.37 s and was never a jump. It is a full dive — leap, tumble, roll,
stand up — and D-008 already measured it arcing 12.6 m forward and 3.0 m up
before the pipeline locked the root joint. It sat as input 1 of the `grounded`
Blend2 as a plain `AnimationNodeAnimation`, and **an animation node inside a
blend runs its own clock from the moment the tree starts**, whether or not
anything is blending toward it. So the first jump of a match caught the clip
somewhere near its beginning and looked more or less right, and 2.37 s into the
round the clip reached its last frame and stopped there for good. Every later
jump showed one frozen pose from the end of a dive. It was never one jump in a
hundred working — it was the *first* one, and nothing after it.

The fix is two clips out of the one file, and that is the design change:

**A single jump is the take-off only, and it restarts.** The airborne node uses
a custom timeline over 0.34-0.50 s of `Jump` — the push-off, and the legs coming
up under the body — with `stretch_time_scale` off so it plays at authored speed
and `loop_mode` none so it runs out and *holds*. 0.00-0.30 s is the anticipation
crouch, which has already happened by the time the Gub is off the ground; past
0.50 s the clip pitches over into the dive it really is. An
`AnimationNodeTimeSeek` in front of it is driven to 0 every time the feet leave
the ground, so the sixth jump of a match is the same as the first.

That seek hangs off the grounded→airborne *transition* rather than off
`Gub.jumped`, on purpose: `jumped` fires only on the owning client, while
`is_grounded()` reads the replicated `sync_grounded` on everyone else's screen.
One code path then covers the Gub you are driving, the seven you are watching,
and stepping off a ledge.

**A double jump is the dive, whole.** Press jump while already airborne, once
per airtime, and the Gub commits: `DIVE_FORWARD_SPEED` (9.5 m/s, well above
RUN_SPEED, or it would be a worse way of running) along the wish direction — or
the facing, if you are asking for nothing — plus `DIVE_UP_VELOCITY` (5.4 m/s,
enough to keep it airborne long enough for the leap to read, not enough to clear
the treeline). No further air jumps until the feet touch anything at all, and
the flag comes back on landing and on respawn. The lure still blocks it, because
the lure is meant to feel like being grabbed.

The gate is `_coyote <= 0.0`, which is what makes a double-tap on flat ground
jump first and dive second rather than dive twice: coyote time is still running
for the twelfth of a second after walking off a ledge, and is zeroed by a jump.
An airborne press past that point dives instead of going into the jump buffer.
That costs the buffer exactly one press per airtime, which is the price of the
ability having a button at all.

**Remote Gubs see it because a number changed, not because a message arrived.**
`Gub.sync_dive_serial` is an `int` on the existing `MultiplayerSynchronizer`
(spawn, on-change), bumped once per dive; `GubAnimator` fires the dive OneShot
whenever the value it last acted on stops matching. A counter and not a flag,
because a bool that goes true and false again inside one replication tick
arrives as no change at all, and two dives in a row have to be two dives on
every screen. No new RPC, and one code path for the local Gub and the remote
ones — the pattern `sync_grounded` already set.

The one place the clip and the physics cannot be reconciled is the landing. The
dive clip is 2.37 s and a dive is airborne for well under a second, so its
tumble-and-recover half can never line up with a real touchdown; the OneShot is
faded out on landing rather than left to play a ground roll on top of a run
cycle.

Noted here and deliberately not fixed: `Crouch` is a two-keyframe held pose.
That is an art limitation, not a fault in the graph.

## D-027 — Readability passes: the name shrinks, the spear is lit, the landing is drawn
Three complaints from the same playtest, all of them about what the player can
*see* rather than about what the game does.

**"That's the biggest bug right now is you can't see the spear."** Part of that
was the throw RPC and is fixed elsewhere. The rest is that a thrown stick is a
thin, dark, fast object in a night forest, and nothing about it was loud. Three
changes, in order of how much each one bought:

- The trail is twice as long — `SpearTrail.SAMPLES` 12 → 24, which is 0.4 s of
  flight and about seventeen metres — nearly twice as wide (`HALF_WIDTH` 0.055
  → 0.09), and warm instead of pale blue. The colour mattered more than
  expected: the old streak sat in the same range as the sky and the fog and was
  swallowed by both, while every other thing in this game worth looking at is
  torch-coloured. Its brightness falls off as `t^1.4` rather than `t²`, because
  squared put the whole ribbon in its front quarter and made the extra length
  decorative. It is still one additive draw call and still shortens to nothing
  0.4 s after impact.
- The projectile is lit in flight and unlit the moment it stops. This is
  smaller than it sounds, because of something worth writing down about the
  art: **every model in `art/generated` has a black albedo and a pre-shaded
  emission texture**, so a Gub and a spear are already made entirely of
  emission. There is no glow to add, only one to turn up, and it has to be
  turned up through `emission_energy_multiplier` — the materials' emission
  operator is multiply, so giving one a warm colour *darkens* its blue instead
  of warming it. `GLOW_BOOST` is 3.0, tuned by eye rather than by theory: the
  environment tonemaps ACES at a white point of 6.0, and at the 1.25 that
  sounded right on paper the spear was indistinguishable from an unlit one. A
  copy of the material per projectile, freed with it, the way `GubRagdoll`
  copies materials to fade a corpse.
- The glow comes off in `_stick` and `_stick_in`. A spear in the dirt and a
  spear through a corpse are scenery and have to read as scenery; leaving them
  lit would make every miss a beacon and every body a lamp.

**"I wish I knew where my spear was going, does it have drop?"** It does — a
third of world gravity — and no crosshair can answer that question, because the
crosshair is a point on a ray and the spear flies a parabola. So the answer is
drawn in the world: `scripts/player/aim_marker.gd`, a ring on the ground where a
spear thrown right now would land, shown only while the aim button is held and
only for the Gub you are driving. Local, cosmetic, and nowhere near the network.

Two things about it are load-bearing. The first is that the path is not a
closed-form parabola but the projectile's *own* integration loop — same speed,
same gravity, same mask, same exclusion of the thrower, and crucially the same
step, because Euler integration is step-size dependent and predicting at 30 Hz
would put the ring metres from where the spear actually lands. The second is
that a flat ring alone does not work. It is seen from eye height along a nearly
flat throw, which foreshortens it to a line about one pixel tall at the ranges
anybody throws from; the first render of it looked like nothing at all. What
makes it visible is the low band standing up off the ring's rim — a vertical
surface is never edge-on to a camera roughly level with it.

It is gated on the aim button rather than always on, deliberately. Judging the
arc is where a lot of the skill in this fight lives (D-014, D-025), and a
permanent marker turns the throw from something you read into something you line
up. Holding the button is the price of the answer, and it costs the wider field
of view while you ask.

`tools/combat_range.tscn` gained an `aim` mode for it: it holds the button at
the far wall and never throws, which is a state no other mode here spends a
single frame in, because every other mode's job is to get the projectile out of
the hand. It aims deliberately off the centre line — straight down it the spear
meets Dummy 1 at fourteen metres and the ring is drawn on a Gub's chest, which
proves the marker works on players and shows nothing about drop — and it prints
where the ring landed, so a run says something without anybody opening the PNG.
Aimed at a wall 43 m away it reports the spear coming down on open dirt at 23 m,
19.8 m short and 1.2 m low. That number *is* the answer to the question.

**"The names are too big."** `Nameplate` was `fixed_size`, which pins a label to
a constant number of screen pixels at any range. That reads as correct in a
screenshot and wrong in motion: a name across the island was exactly as large as
the name on the Gub beside you, so a crowd came out as a wall of identical
floating text with the players somewhere behind it. Perspective is the cue that
says which name belongs to which body, and it was the one thing being thrown
away. The plate now has a size in the world — `FONT_SIZE * PIXEL_SIZE`, about
0.21 m tall, so a six-letter name is roughly the width of a Gub's shoulders —
and it shrinks and grows with the Gub like everything else.

Two consequences. The fade came down with it, from 34-46 m to 20-28 m: at a
fixed screen size the old numbers were honest, but in perspective a name at 34 m
is four or five pixels tall and is no longer a name, it is a smear saying
"somebody is over there", which the Gub's own silhouette already says for free.
Fading it out where it stops being readable is the same decision the old numbers
made, applied to a plate that now has a size. And `GubBackdrop` lost its
`plate_scale`: it existed to shrink lobby plates by 0.60 and 0.40 because those
formations are shot at 42 and 36 degrees against the game's 75, and a fixed-size
plate does not care how wide the lens is. A plate with a world size does — the
narrow lens magnifies the name and the Gub under it by exactly the same amount —
so the two now stay matched with nothing to tune. The lobby renders
pixel-for-pixel the same as it did with the correction in place, which is the
proof that the correction was only ever undoing the bug.

**Corpses, one line.** `GubRagdoll.LINGER` 9.0 → 2.5 s and `FADE` 1.6 → 0.8 s.
All of the value in a ragdoll is the flight, and the flight is over in about a
second and a half; after that a body is clutter, and at eight players with a
three-second respawn the corpse from your last kill was still lying between you
and your next one. `tools/smoke_test.sh` moved its ragdoll grab from tick 160 to
155, which is now a narrow window with a reason at each end: `ragdoll_stability`
does not print its verdict until tick 150, and the corpse starts fading at 160
and is gone by 208.

## D-028 — The host runs a tunnel, so that nobody else has to install anything
Until now the only way to play this across the internet was `docs/PLAYING.md`'s
first instruction: *everybody* installs Tailscale, makes an account, and joins
one tailnet. That works — D-005's code carries whatever address `select_ipv4()`
picks, and a tailnet address is a real routable address that reaches both across
the country and across a shared LAN. It is also five people's setup before
anyone throws a spear, and the free plan caps at six people against a lobby cap
of eight, so a full game needed a paid seat.

The designers' framing was the whole design: *"then only the host has to set
up"*. The host is already the person doing something different from everyone
else — they open the lobby, they read out the code — so they are the right
person to carry the cost. Everyone else should download one `.exe` and paste
ten characters, which is what they were promised in the first place.

**What was added.** A persisted setting, `public_address`, a String, default
`""`, edited in Settings → Network. The host puts the address of a
[playit.gg](https://playit.gg) UDP tunnel in it — `angry-gub.at.ply.gg:41235` —
and when the lobby opens, `Net.invite_code()` encodes that endpoint instead of a
local one. `invite_scope()` says `INTERNET (PLAYIT)`. Blank is the old
behaviour exactly, tailnet and LAN and all, which is what everybody who is not
hosting will always have.

playit was chosen over the obvious alternative of "tell the host to forward
UDP 27015 on their router" because port forwarding is unavailable to a growing
share of players (carrier-grade NAT), is different on every router, and cannot
be checked from inside the game. A tunnel agent is one download, and it either
says connected or it does not.

**The local port is fixed at 27015 and the public port is not.** playit
allocates the outside port; the inside port is whatever the host configures the
agent to forward to. Making the game bind whatever the tunnel's public port
happens to be would be backwards — the two numbers are on opposite sides of the
tunnel and nothing connects them. So the game keeps binding `DEFAULT_PORT`, the
docs require the tunnel's local port to be 27015, and the *public* port is what
goes in the code. That is the one setup step a host can get wrong in a way the
game cannot detect, which is why it is in a table in `docs/PLAYING.md` and in
the caption under the settings field.

**Why the code carries the resolved IP and not the hostname.** The tempting
change is to widen the invite code so it can hold `angry-gub.at.ply.gg` and let
the joiner resolve it. We did not, for three reasons:

1. **Six bytes is the format.** Four for the address, two for the port, which is
   exactly ten Crockford characters with no padding — every code the same
   length, which is most of what makes a code readable down a phone line
   (D-005). A hostname is 20-ish bytes and variable, so codes become long,
   variable-length, and no longer the thing this project promised.
2. **The lookup belongs on the side that can report it.** Resolving on the
   host means one machine does it, once, at a moment when there is a lobby
   caption to say it failed. Resolving on the joiner's side means every joiner
   does it, in the middle of a dial, where a DNS failure is indistinguishable
   from a host who is not there.
3. **playit's addresses are stable per region.** The hostname resolves to a
   playit anycast IPv4 that does not move under a live tunnel.

The known risk, stated plainly: **if playit re-homes a tunnel to a different
IP, every code already handed out points at the old one.** The fix is the fix
for a stale code, which this game has always had and already documents — the
host reopens the lobby and reads out a fresh one, and reopening is what
re-runs the lookup. Nothing new to learn, and the same failure the LAN path has
when a DHCP lease changes.

**Resolution happens once, when the port is bound — not in `invite_code()`.**
`IP.resolve_hostname` blocks for a DNS round trip, and `lobby.gd::_refresh_invite`
calls `invite_code()` on every roster change. Resolving there would freeze the
lobby for a moment every time somebody joined, readied up, or switched team. The
tunnel's address does not change while a lobby is open, so it is resolved in
`host_lobby()` and cached with the port for the life of the session.

**Parsing is separate from resolving, and static.** `Net.parse_public_address`
takes a String and returns `{host, port}` or nothing: it strips whitespace
anywhere (this arrives via a clipboard), demands exactly one colon and a port in
1..65535, and touches no network. That makes it exhaustively testable with no
socket, which is what `tools/invite_codes.gd` does with it — a valid address,
whitespace in four places, an IPv4 literal (accepted with no lookup at all), and
fourteen kinds of rubbish including a URL, an IPv6 address, and a bare hostname
with no port. `Net.is_ipv4_literal` does double duty: it skips the resolver for
a host who typed an IP, and it checks what came *back* from the resolver, since
a well-formed IPv6 answer will not fit in four bytes and has to be refused
rather than truncated.

**Failure is loud, because the fallback is silent.** A public address that does
not parse or does not resolve falls back to the local address, which produces a
perfectly valid code that simply does not leave the building — the exact shape
of failure D-005's address selection was written to avoid. So `invite_problem()`
returns a line, and the lobby prints it *instead of* the scope caption:
`PUBLIC ADDRESS DID NOT RESOLVE — USING LAN`. There is one line of space there
and this is the more urgent thing for it to say.

**Nothing changed on the joining side, and that is the point.** A resolved
playit anycast address is four bytes and a port, which is what
`ENetMultiplayerPeer.create_client` has always been given; ENet speaks plain UDP
to whatever it is pointed at, and a tunnel is transparent to it. The seam
`docs/ARCHITECTURE.md` describes did not have to move.

**One trap in the tooling.** Godot keys its user data directory on the project
*name*, not the path, so every checkout and every process of this project shares
one `user://settings.cfg` — the thing that already forced `tools/net_loopback.gd`
to set player names explicitly. `public_address` lands in that same file, so a
developer who has set up a tunnel for a playtest would find `tools/net_test.sh`
resolving their tunnel's hostname over real DNS and encoding a public endpoint
into a loopback test. `Net.ignore_public_address` exists for that, set by the
harness before it hosts. Turned off explicitly rather than by clearing the
setting, because clearing it would write to the file the person running the test
is about to host a real game with.

## D-029 — The Gub was rebuilt from eight Mixamo clips, and its animator was rebuilt around them
Two playtest complaints, one root: "the transitions are poor" and "you never see
the whole jump or the whole slide". D-026 had already found the mechanism for
half of it — an `AnimationNodeAnimation` inside a blend runs its own clock from
tree start and freezes on its last frame — and fixed it for the jump by carving
a 0.16 s slice out of a 2.37 s dive. The slide had the identical bug and nobody
had looked. Behind both sat an asset that could not give a better answer: one
`Gub.glb`, an 18k decimation of a 500k-triangle photogrammetry mesh on a
hand-made Rigify rig, carrying eight clips — one of which had shipped as the
bind pose where a crouch should be (D-023), and one of which was a whole dive
where a jump should be (D-026).

So the instruction was to replace the asset and **not to base the new
implementation on the old one**. Both halves of that happened, and this entry is
the record of what the new source actually turned out to be, which was not what
anyone assumed. The retired source, `assets/source/Gub.glb`, is deleted from the
tree in the same commit: nothing builds from it any more, and git history has it
if D-008 or D-023 ever need re-reading against the file they describe.

### The source, and the one script that builds it

`assets/source/GUB_2/` holds eight Mixamo FBX files — same character, same mesh,
one clip each at 60 fps, a 2048² base-colour JPG packed in every file. All eight
agree on 8814 vertices, 49 bones, 40 vertex groups and a bind pose identical to
a matrix delta of **0.0**, which is what makes consolidating them into one
armature legitimate rather than hopeful.

`tools/build_gub.py` (Blender 5.2, headless, 1303 lines) does the whole
conversion and prints every measurement it takes, in the style
`tools/decimate_assets.py` established. `bash tools/build_gub.sh` locates
Blender the way `tools/find_godot.sh` locates Godot. Three consecutive runs
produce a **byte-identical** `art/generated/gub.glb`, so "rebuild it and see" is
a real answer to a question.

Three things in that script exist only because Blender or the exporter lied
first:

- **Blender 5.2 actions are layered and slotted.** `action.fcurves` does not
  exist; the curves are at `action.layers[].strips[].channelbags[].fcurves`.
  Every loop in the script goes the long way round for that reason.
- **Applying an armature's scale does not scale its pose-bone `location`
  fcurves.** The mesh comes out 1.80 m tall and the root motion stays at a fifth
  of it, so the Gub travels a fifth of the distance its feet do. 960 location
  fcurves are multiplied by the armature-local factor **1.903149** by hand at
  the moment the transform is applied. Every measurement is then re-derived at
  scale before anything is stripped — Run's hips travel 1.941 m in 0.450 s,
  JumpOne's reach 1.120 m at 0.750 s — so a scale mistake fails loudly instead
  of shipping.
- **The extracted texture is named after the image's *filepath*, not its
  datablock.** Renaming the datablock to `basecolor` was not enough; the first
  build produced `gub_cartoon+monster+3d+model_basecolor.jpg`. The script sets
  `image.filepath_raw = '//basecolor.jpg'`, and because the embedded image stays
  JPEG the file Godot extracts is **`art/generated/gub_basecolor.jpg`**, not the
  `.png` everyone including the spec expected.

The old `art/generated/gub_shaded.png` is deleted, `tools/rig_clean.py` and
`tools/rig_math.py` with it, and `tools/decimate_assets.py` — which is now three
unskinned props and nothing else — raises rather than silently discarding a rig
if a source ever turns out to be skinned.

### The clips

Nine, not the eight that arrived: `CrouchIdle` is synthesised from `CrouchWalk`
frame 37, the passing pose, after root-motion locking so its hips sit at the
origin. Lengths are what Godot reports; the four cycles are one frame shorter
than the source because the duplicate tail key is dropped (`DROP_LOOP_TAIL`), or
the loop holds its first pose twice.

| clip | length | loops | authored speed | playback rate in game |
|---|---|---|---|---|
| `Idle` | 4.15 s | yes | 0 | 1.0 |
| `Walk` | 1.233 s | yes | **1.079 m/s** | 2.1316 |
| `Run` | 0.433 s | yes | **4.314 m/s** | 1.2517 |
| `CrouchWalk` | 1.117 s | yes | **1.273 m/s** | 1.2569 |
| `CrouchIdle` | 1.000 s | yes | 0 | 1.0 |
| `Slide` | 1.767 s | no | 3.9→1 m/s | 1.0 |
| `JumpOne` | 1.883 s | no | 0 (in place) | scrubbed |
| `JumpTwo` | 2.367 s | no | leaps 4.6 m | scrubbed |
| `Throw` | 3.833 s | no | steps ~0.9 m | 1.6 |

**Every clip faced a different way**, which is D-008's problem arriving a second
time on a completely different rig. The build measures each clip's facing by
forward kinematics — the yaw of the `LeftUpLeg`→`RightUpLeg` line in world space
— against the rest pose measured identically, and pre-multiplies the Hips
`rotation_quaternion` keys by the compensating yaw about the bone's local +Y.
The corrections are not small: Idle **+50.96°**, CrouchIdle +39.48, JumpOne
+38.20, CrouchWalk +37.74, Slide −35.58, JumpTwo −19.19, Throw +17.59, Run
−6.22, Walk +1.06. All nine now measure **0.00°** residual against the same
reference, and the build aborts above 1°. Motion *within* a clip is untouched:
the slide still turns 120° onto its side and the throw's torso still swings 162°.

**Loop modes are declared in the GLB, not in the `.import`.** `_subresources`
with `settings/loop_mode` does work — but Godot then rewrites `gub.glb.import`
with every default for every animation it names, all 256 `slice_N` blocks
apiece: **348,496 bytes instead of 1,137**, regenerated on every import, with
the answer to "does this clip loop?" split across two files. So the five cycles
are exported as `Idle-loop`, `Walk-loop`, `Run-loop`, `CrouchWalk-loop`,
`CrouchIdle-loop`; Godot's importer strips the suffix and sets `LOOP_LINEAR`.
`_subresources={}`, and `nodes/use_name_suffixes` must stay true or the clips
arrive with `-loop` still in their names. The single source of truth for which
clips loop is the `CLIPS` table in `build_gub.py`. Anything that reads the GLB
directly rather than through Godot has to strip the suffix, which is why
`tools/rig_report.py` has a `clip_base()`.

### The vertical rule: one clamp was right and one was catastrophic

Both jump clips rise — JumpOne's pelvis by 0.41 m, JumpTwo's by 0.57 — and the
physics capsule already performs that arc, so the first pass clamped the hips Y
to its first key in both. For **JumpOne**, a vertical hop, that is exactly
right: the legs tuck under a pelvis that stays put and the ballistic motion is
left to the body that is really doing it.

For **JumpTwo** it was a disaster, and the reason is that JumpTwo is not a jump.
It is a front somersault that plants its hands and rolls out. Pin the pelvis and
the inverted body rotates about a point 0.62 m too low: head and hands went
**0.41 m below the floor** from clip 1.00 to 1.60 s, and the dive touched down
upside-down. The raw clip is self-consistent — the hands reach the ground at
1.18 s *because* the hips are high.

    VERTICAL_RISE_KEPT = {"JumpOne": 0.0, "JumpTwo": 1.0}

The up axis is scaled toward the first key by `1 − kept`, so 0.0 is the old flat
clamp and 1.0 leaves the clip alone; only keys *above* the first key move, so
every clip keeps its landing absorb and ground roll either way. With the rise
kept, JumpTwo's hips top out at **0.900 s** at 1.293 m (0.618 m above the first
key), the hands take the ground at **1.183 s** and stay down until 1.833, and
the feet arrive at 1.530. Those are the numbers `JUMP_TWO_APEX` and the roll
window are read off.

**The build now refuses to ship a clip that goes through the floor.** After
processing, `check_ground()` samples every bone head over each jump, prints the
deepest one either side of the frame the hands plant, and aborts against a
per-clip `FLOOR_LIMIT`. A companion `check_tables()` refuses a build whose rule
table names a clip that is not built, or a clip with no limit.

| | JumpOne | JumpTwo |
|---|---|---|
| deepest joint, shipped | −0.141 m (`LeftToe_End`, 0.583 s) | −0.167 m (`RightHandThumb4`, 1.400 s) |
| deepest joint while airborne | — | −0.103 m (1.183 s) |
| deepest joint if clamped | — | **−0.410 m** (1.167 s) |
| `FLOOR_LIMIT` | −0.15 | −0.20 |

`FLOOR_LIMIT["JumpTwo"]` is −0.20 and not the −0.08 that was asked for, because
**no build of this clip can meet −0.08**: the *authored* ground roll takes a
knuckle to −0.167 m at 1.400 s, and those hips keys are below the clip's first
key, which the vertical rule deliberately never touches. The first run with
−0.08 aborted correctly and refused to write the GLB, which is how we know the
check works. −0.20 still bites: a clamped JumpTwo measures −0.410.

### The graph, and the one sentence that makes D-026's bug impossible

`scripts/player/gub_animator.gd` is a new `AnimationNodeBlendTree` built in
code. The rule it is built to is written at the top of the class:

> **Ground poses come from speed, air poses come from the arc, events are
> one-shots.** Nothing in the tree runs a clock that is not either a looping
> locomotion cycle, a OneShot that restarts on fire, or a node that is scrubbed
> every frame.

```
stand    BlendSpace1D  Idle @ 0 | Walk @ 2.3 | Run @ 5.4      (positions in game m/s)
crouch   BlendSpace1D  CrouchIdle @ 0 | CrouchWalk @ 1.6
stance   Blend2(stand, crouch)
air_one  TimeSeek -> JumpOne    scrubbed to an absolute clip time every frame
air_two  TimeSeek -> JumpTwo    scrubbed every frame
air      Blend2(air_one, air_two)     1 while this airtime contains a dive
grounded Blend2(stance, air)
slide -> land -> roll -> throw  four chained OneShots; throw filtered to 37 upper-body bones
```

Every locomotion node carries its own rate in a custom timeline
(`timeline_length = length / (game_speed / authored_speed)`,
`stretch_time_scale = true`, node-level `LOOP_LINEAR`), so the feet stay planted
without a global TimeScale node and without the `.import` having an opinion.
That replaces `SPEED_SCALE`, `JOG_SPEED` and `AUTHORED_JOG`, which are gone.

**The airborne clips are indexed, not played.** JumpOne is 0.35 s airborne
against a 0.70 s physics jump, so a clock can never agree with the body:

    phase = clamp(0.5 * (1 - vy / v_launch), 0, 1)    # 0 leaving, 0.5 apex, 1 about to land
    t     = phase < 0.5 ? lerp(START, APEX, phase / 0.5)
                        : lerp(APEX,  END,  (phase - 0.5) / 0.5)

    JumpOne  START 0.68  APEX 0.83  END 0.95    v_launch = JUMP_VELOCITY (9.0)
    JumpTwo  START 0.58  APEX 0.90  END 1.48    v_launch = vy when the dive serial changed

`JUMP_ONE_START` is 0.68 rather than 0.60 because the push-off frames before it
extend the legs 0.13 m below the floor and the physics take-off is instant
anyway. A Gub that walks off a ledge has vy ≈ 0, so phase *starts* at 0.5 — the
apex pose — and falls through to the pre-landing pose. Falls are covered by the
same mechanism with no extra clip.

**The trap in that rule, which only a trace found:** `move_and_slide` zeroes vy
on touchdown, the arc reads vy = 0 as "apex", and the air pose snapped back to
the top of the leap on the landing frame — a **0.48 m hip pop** on every
landing. A grounded Gub now holds the about-to-land pose instead; the residual
bump is 0.14 m.

**Every unweighted cycle was frozen at phase 0.** `sync = false` on the two
BlendSpace1Ds and the three Blend2s meant a node nothing was blending toward did
not advance, so the sprint entry cross-faded a *static* Run frame into a
mid-stride Walk — the same class of defect as D-026, one layer up. Measured on
the shipped tree: after 1.5 s of walking, `parameters/stand/{idle,walk,run}` and
`crouch/{still,walk}` all read `current_position` **0.0000**. With `sync = true`
they read 0.2816 / 0.0540 / 0.5503 and advance. (`sync` is the legacy alias:
setting it true reads back as `sync_mode = INDEPENDENT`.
`SYNC_MODE_CYCLIC_MUTABLE` would go further and phase-*lock* them — measured at
26.4% against 26.5% of their own timelines — at the cost of the phase rate
stepping once as the blend crosses the midpoint. Not shipped; noted for whoever
tunes the sprint entry.)

The throw's window is `[0.50, 2.10]` of `Throw` at rate 1.6, and
`THROW_RELEASE_TIME` is now derived rather than tasted:

    (THROW_RELEASE_IN_CLIP - THROW_CLIP_START) / THROW_RATE = (1.633 - 0.50) / 1.6 = 0.7081 s

which is **42.5 physics ticks**, up from D-025's 0.57 s / 34 ticks on the old
`SpearThrow`. `gub_combat.gd` reads it from `GubAnimator`, so the number exists
once. The kill in `combat_range hit` lands about tick 83 of the 110-tick budget;
the lure's 132 is unaffected.

### Emission 0.15, because the new texture is not pre-shaded

The old asset was a pre-shaded emission texture and was always visible (D-027).
This one is a flat base colour with a Principled BSDF over it, and at night in
unlit undergrowth it measured **1.5×** the shadowed background — a brown smudge
at 20 m — while the still-pre-shaded spear in its hand stayed bright. The build
wires the base-colour texture into Emission Color at `--emission`, default
**0.15**:

| | 0.00 | 0.15 |
|---|---|---|
| distant Gub in unlit undergrowth, mean luminance | 21.7 | 38.9 |
| …as a ratio to the shadowed background | 1.51× | 2.71× |
| torch-lit Gub against the sky, mean luminance | 43.4 | 64.0 |
| …its *peak* luminance | 166 | 142 |
| clipped channels, either view | 0 | 0 |

The peak falling is the point: 0.15 lifts the shadow side into legibility
without flattening the shading gradient or turning the Gub into a lamp, and the
torch flames are still the brightest things in frame. At exactly 0 the emission
socket is left unconnected rather than wired to black — a wired-but-black
emission is a second texture sample per fragment that can never do anything.

### The hitbox follows the pose the clips actually strike

The new crouch is not a low pose. Measured silhouette heights: Idle 1.49 m,
**CrouchWalk 1.51**, Run 1.41, Walk 1.73 (the antennae). `CROUCH_HEIGHT` was
0.95, which left the whole chest and head outside the capsule and made a
crouching Gub's head **unhittable**. It is now **1.35**.

The slide is the opposite problem and is genuinely prone — the hips drop to
0.165 m — so `SLIDE_HEIGHT := 0.75` is layered on the crouch blend through a new
`pose_height()` that the capsule, `eye_height()`, `_has_headroom()` and
`_follow_network` all read, so a remote Gub is shaped like a local one.

| pose | capsule top | mesh top | eye height |
|---|---|---|---|
| idle / run | 1.55 | 1.427 / 1.412 | 1.33 |
| crouch | 1.35 | 1.499 | 1.16 |
| slide | 0.77 | 0.730 | 0.65 |

1014 of 8818 vertices are still above the crouch capsule — 602 of them the two
antennae and the crown of the head blob, 412 the raised right fist. That is
0.10 m of crown and 0.29 m of antenna, against 0.56 m of chest-and-head before.
For scale: **the old asset had 0.5 m of head outside its crouch capsule too**,
so this is not a defect that was introduced, it is one that was measured. The
capsule *radius* is unchanged at 0.38 m, so in every pose the spread feet and
out-held arms are outside it laterally — most obviously in the slide, where a
vertical capsule cannot follow a prone body at all.

### One number for the roll, shared by the rule and the animation

`ROLL_LOCK` (0.45 s of ignored input and gentle friction after a dive landing,
so the body travels with the roll instead of skating through it) is a new
gameplay rule, and it needed three coherence fixes:

- It outlived the floor. A dive that landed on a ledge and carried over its edge
  kept the lock in the air: no air control, and `ROLL_FRICTION` (10.0) dragging
  on the fall instead of `AIR_FRICTION` (1.5). Two reviewers found it
  independently. `_tick_timers` now zeroes `_roll_lock` the moment the feet
  leave the floor — the roll is a ground move, and a fall out of it is an
  ordinary fall.
- It armed on *any* landing, including a one-tick scuff off a kerb.
  `Gub.ROLL_MIN_AIRTIME := 0.20` now gates it, and the animator's
  `LAND_MIN_AIRTIME` is literally `Gub.ROLL_MIN_AIRTIME` — the rule and the
  animation cannot drift apart because there is one constant.
- The comment on `_handle_jump` promised that a jump pressed during the roll
  fires when the lock ends. It did not: the buffer decays in 0.14 s and the lock
  lasts 0.45. `_jump_buffered` is now frozen while `is_rolling()`. Measured:
  lock armed at tick 106, press at 112, jump fired at **134** — the first tick
  `is_rolling()` was false — at vy exactly 9.00. Before, that press was silently
  dropped at tick 120.

`Gub.vertical_speed()` returns `velocity.y` locally and `sync_velocity.y`
remotely, and feeds both the arc scrub and the dive launch speed. On a remote
Gub that is a tick fresher than `velocity`, because the synchronizer writes
`sync_velocity` before `_follow_network` copies it out.

**Respawn used to pin every remote copy airborne.** `revive_at()` ended with
`_publish()`, which sets `sync_grounded = is_on_floor()` — and on a remote copy
`is_on_floor()` is permanently false. The owner's own value never changed
(true→true), so ON_CHANGE replication never corrected it, and every other screen
showed a Gub falling on the spot. `revive_at` now seeds the replicated fields
field by field, `sync_grounded = true` among them, because a spawn pad is on the
ground.

### The spear was in the Gub's head, and the fix was 5 cm

The idle is a boxer's guard: the right fist sits beside the face. The first
grip, derived against a three-ellipsoid stand-in for the body, ran the shaft **in
under the chin and out above the crown** — nearest-skin distance 0.004 m, i.e.
through the surface — and in Walk the tip ploughed the ground at 0.004 m. The
stand-in was the error: the real belly is 0.37 m half-depth and the head 0.35 m
across.

Re-derived against the actual skinned mesh — 27 poses over the six clips the
spear is carried in, scoring the shaft's distance to the nearest
head-or-torso-weighted vertex:

    HAND_BONE      "RightHand"
    GRIP_OFFSET    (-0.206, -0.582, 0.097)
    GRIP_ROTATION  (-12, 0, -15)

A near-vertical Idle carry — shaft 81–86° above horizontal, 53° round from
forward toward the Gub's own right — with the fist 55% up the 1.236 m shaft so
the butt clears the ground when the arm hangs. `GRIP_OFFSET` is *derived*, not
free: it is the palm pass-point minus `0.55 × 1.236 ×` the shaft direction, and
it has to be recomputed if `GRIP_ROTATION` changes.

The 5 cm that matter are lateral. Passing the shaft 5 cm off the wrist axis
instead of through it is what takes it from grazing the face to 11 cm clear, and
5 cm is still inside the fist — the `RightHand`-weighted skin spans
x −0.083…0.085, z −0.065…0.065.

| nearest skin, metres | Idle | Walk | Run | CrouchWalk | CrouchIdle | Throw |
|---|---|---|---|---|---|---|
| before | 0.004 | 0.029 | 0.080 | 0.019 | 0.061 | 0.006 |
| after | **0.114** | 0.151 | 0.254 | 0.187 | 0.193 | 0.055 |

Walk and Run still point the tip *down* (−14…−42° and −43…−59°) and that is not
fixable with a rigid `BoneAttachment3D`: the hand's world orientation differs by
more than 100° between a raised guard and a hanging arm. What is fixed is the
tip in the ground — Walk's lowest shaft end went 0.004 → 0.234 m, and both ends
now stay at least 0.148 m up in every ground clip. Standing the shaft up in Walk
as well needs an animated or IK'd attachment.

### The ragdoll's headline defect was a material, not a joint

The corpse looked shattered: eyeball meshes apparently outside the head, black
self-intersecting seams, a shard-edged crumple. Every one of those is the same
bug, and it is not physics. **The corpse's materials were switched to
`TRANSPARENCY_ALPHA` at spawn.** An alpha material renders in the transparent
pass and writes no depth, so a closed body stops occluding *itself* — you were
looking straight through the skin at the inside of the head and the backs of the
eyes. The bodies were exactly where they belonged the whole time, which was
proven by dumping bone world positions: `RightHand` at
`(0.123545, 0.984243, -0.318786)` on the live Gub and on its corpse, to six
decimals. Corpse materials now stay opaque for the whole 2.5 s linger and switch
to alpha plus `DEPTH_DRAW_ALWAYS` at the first frame of the 0.8 s fade.

On top of that, real improvements that are not what fixed the picture: the 13
bodies of the new `SEGMENTS` table were refitted to the mesh's outer extent
(pelvis radius 0.329, chest 0.301, head 0.320 — the head is a third of the
character), which required **`MAX_RADIUS` 0.30 → 0.40 out of necessity, not
tidiness**: at 0.30 the pelvis and head were being silently clamped and the
refit had no effect at all. A p90 fit is right for a cylindrical limb and wrong
for three overlapping blobs, which is why the torso rows sit near the outer
extent while the hand and foot rows sit near the median — their splayed digits
double the p90. Total mass 39.0 kg, worst ratio 8:1.

**The neck is 35°/25° and the spine stayed at 45°, against a request for 30°
everywhere.** This is D-013's warning arriving on schedule — a cone-twist driven
past its limit adds energy rather than clamping — and the reason is measurable: a
corpse is snapped to the pose it died in, so any span below the bend the
*animation* already contains starts the joint outside its own limit. Idle alone
bends the neck 38°, Run 69°, JumpTwo 71°; JumpOne bends Spine1 49°.

| configuration | `ragdoll_stability` |
|---|---|
| head 60/50, spine 45 (first pass) | PASS but jittery — 1.46 m/s at settle against a 1.5 limit |
| head 45/25, spine 45 | PASS, 0.47 m/s |
| **head 35/25, spine 45 — shipped** | **PASS, 0.55 m spread / 0.76 m/s** |
| head 30/25, spine 45 | PASS marginally, 1.18 m/s |
| head 25/25, spine 45 | FAIL — 160 m/s at tick 121 |
| head 18/25, spine 45 | FAIL — 285 m/s at tick 33 |
| head 45/25, **spine 30** | FAIL — 123 m/s at tick 55 |

**And "settled spread 0.59 m for a 1.80 m body" was a misread metric, not a
crumpled corpse.** `ragdoll_stability`'s spread is the maximum distance of a body
from the centroid — a *radius* — so 1.0–1.5 m is geometrically impossible for
this rig, and anything over 1.5 fails the test outright. It reads 0.55 m, and
the corpse is prone: its thirteen body centres occupy 0.70 × 0.29 × 0.89 m,
about 1.4 m of skin on the ground once the capsule radii and the 0.36 m of skull
beyond the head body are counted.

Last, **every corpse faced backwards**, and had done since before this rework.
`GubRagdoll._adopt` copied `Model`'s yaw onto the holder, but the 180° turn that
makes `body_yaw` mean "the way the Gub is looking" lives on the `Model/gub`
*child* in `gub.tscn`. The whole chain is now composed, found by walking up from
the skeleton rather than by name.

### What this asset is worse at than the old one

`tools/rig_report.py` measures the new asset the same way it measured the old one
for D-023, and the honest answer is that **Mixamo's stock weights skin worse at
the neck and shoulder ring than D-023's solved bind did**:

| | old asset, after D-023 | new asset |
|---|---|---|
| worst edge growth | 4.42% of body | **9.81%** (Throw) |
| torn-edge instances | 258 over 8 clips / 28113 edges | **1061** over 9 clips / 19033 edges |
| left/right bind asymmetry (mean) | 0.762 | **0.219** |

The table it reports, on the shipped GLB — `stretch` is a multiple of rest edge
length, `jerk` is per frame as a fraction of body size, and the clip names carry
the `-loop` suffix because `rig_report` reads the GLB rather than Godot's copy of
it:

```
  binding
    8818 verts, 10542 tris, 49 joints; 7444 have a mirror twin within 2.0% of body size (84%)
    left/right asymmetry:  mean 0.219  p95 1.000  max 1.000   (0 = mirrored exactly)
    influences/vertex: [0, 2879, 2846, 2208, 885]   weights under 0.02: 4085

    clip           frames    dur  stretch    p99.9    torn%  jerk avg  jerk max loop seam
    Idle-loop         250   4.15     5.30     3.28   0.284%   0.00007   0.00518    0.0015
    Walk-loop          75   1.23     5.36     2.98   0.289%   0.00055   0.02100    0.0014
    Run-loop           27   0.43     8.00     3.38   0.336%   0.00413   0.18424    0.0114
    CrouchWalk-loop    68   1.12     7.53     5.01   0.720%   0.00081   0.08413    0.0040
    Slide             107   1.77    11.88     4.08   1.235%   0.00329   0.25157         -
    JumpOne           114   1.88     8.09     3.34   0.594%   0.00171   0.03444         -
    JumpTwo           143   2.37     7.22     3.12   0.678%   0.00684   0.16445         -
    Throw             231   3.83    11.88     4.00   0.856%   0.00051   0.02537         -
    CrouchIdle-loop    61   1.00     7.26     4.92   0.583%   0.00000   0.00000    0.0000
```

The `stretch` column is the ratio D-023 already warned is a poor headline: this
mesh also has edges a fifth of the median length, where half a millimetre reads
as "12×". Measured against the body's own size instead, the worst edge growth per
clip is Walk 4.00%, Idle 4.43%, CrouchIdle 6.55%, JumpOne 6.61%, CrouchWalk
6.74%, JumpTwo 7.01%, Slide 8.25%, Run 9.33%, **Throw 9.81%**. The loop seams are
all under 1.2% of body size, so dropping the duplicate tail key did not cost the
cycles their joins.

It is not the old failure mode — there are no detached flying triangles, and the
Idle sheet is clean. It is the jaw/chest ring, where a cartoon head sits straight
on the shoulders with no neck to grade the falloff, plus the hip ring in Slide:
the outside of a hard bend, where linear-blend skinning always loses and where
the fix is a corrective shape, not a better weight. The bind is markedly *more
symmetric* than the old solved one, and the figure is stable across pairing
tolerance, so that part is real. If the tearing turns out to be visible at
gameplay distance the fix is a re-solve or a corrective — and `tools/rig_clean.py`,
which is what earned the old numbers, is deleted.

(Two measurement footnotes for anyone comparing against an older `rig_report`
run. Its mirror-pairing tolerance is now 2% of the body diagonal rather than an
absolute 1 mm; at 1 mm the pairing found 0–1 vertices on *any* generated asset,
so the asymmetry row was statistics over one vertex. And the old asset's torn
count above is the adapted tool's own re-run on `HEAD`'s GLB, which reads 258
where D-023's table reads 257 — one edge, and worth knowing only so that nobody
goes looking for a discrepancy that means something.)

### Art limitations, kept on purpose

None of these are bugs and all of them are visible if you look for them:

- **`CrouchWalk`'s feet slip 53%.** At the game's 1.6 m/s crouch speed the
  stance foot still travels 0.849 m/s. Walk is 9.4% and Run 16.3%, which are
  fine; CrouchWalk is authored at 1.273 m/s and would need its rate nearly
  doubled to plant, for a 0.17 m/s gain. The clip is what it is.
- **`JumpTwo`'s ground roll is authored below the floor.** From clip 1.333 s on,
  the kept and clamped variants are numerically identical — those hips keys are
  *below* the first key, which the vertical rule never touches — and the skin
  reaches 0.247 m under the plane three ticks after a dive landing, recovering to
  ~0.10 m ten ticks in. It is a human-proportioned roll retargeted onto a body
  whose head is a 0.8 m blob. The air scrub hands over at 1.48, which is the
  most-sunk 0.15 s of the clip, so `ROLL_CLIP_START` is 1.62 instead — within
  0.10 m of the floor and closing (1.73 would be within 0.03 m) — at the cost of
  the first two frames of the tumble, which the touchdown's own impact hides.
  What remains is invisible from the chase camera, which looks down, and visible
  on a contact sheet.
- **The nameplate crosses the model at dive apex.** Keeping JumpTwo's rise puts
  the pelvis 0.618 m above the capsule at clip 0.90 s, and the plate is pinned to
  the capsule at 1.80 m — down from 2.05, which fixed the standing case: the gap
  above the antennae went 0.46 → 0.18 m. Anything keyed off the capsule rather
  than the model — plate, camera height, a `BoneAttachment3D` — separates from
  the body mid-dive. Fixing it properly means offsetting the plate by the model's
  own head height.
- **A sliding Gub is hard to hit.** The 0.77 m capsule is vertically correct —
  nothing of the body is above it — but its 0.38 m radius sits over the hips of a
  body whose head is half a metre forward of the axis.
- **A held spear vanishes when its Gub dies.** `_adopt_spears` adopts *embedded*
  projectiles, not the carried one, so a corpse carries the spear that killed it
  and not the one it was holding. Pre-existing, and left.
- **A settled corpse still creases at the neck and shoulder rings** at 2× zoom,
  for the skinning reason above. The real fix is *more bodies* — driving `Neck`
  and the shoulders instead of leaving them frozen at the death pose — which is a
  change to the size of `SEGMENTS`, not to its numbers. Resetting those undriven
  links to rest at death was tried, rendered, and reverted: no visible gain, and
  it costs the corpse the pose it died in.

### Result

`bash tools/smoke_test.sh` is 10 of 10. `art/generated/gub.glb` is 1.53 MB
against the old 1.97 MB, with 10542 triangles (down from 18k), 49 unprefixed
bones, an AABB of 1.902 × 1.800 × 0.748 with its base at y = 0, and
`nodes/root_scale = 1.0` — the model is authored in metres and the skeleton is
unscaled, so bone attachments and ragdoll capsules are in the same units as the
world.
## D-030 — A map is an id in the match config, not a scene path on the wire
The game is about to have a second map: a bought `.glb` of a well-known FPS arena,
hand-made where Whisperbloom Hollow is generated (D-007). Making room for it needed
one decision — how a peer learns which map it is building — and everything else
followed from it.

**`MatchConfig.map` carries an id, and `MapCatalog` turns ids into maps.** A scene
path would have been shorter by a whole file. It would also mean a client calling
`load()` on a string a peer sent it, which is the one thing the config's flat
dictionary of primitives exists to avoid: `apply_dict` validates everything it
reads because on a client every value in it is attacker-controlled (see the header
of `match_config.gd`). An id is validated the same way every other field is — an
entry that is not in the catalog clamps to `MapCatalog.DEFAULT` in `_clamp_all`,
alongside the kill limit and the enums — and the only paths in the build are the
ones a developer typed into the catalog.

The id also survives version skew in the only direction that matters. A host running
a build with a map an older client does not have sends an id that client cannot
resolve, and the client falls back to the island rather than to a failed `load()`
inside `_ready`. That is still a broken match, but it is a broken match that reaches
the results screen instead of one that hangs behind a loading card forever.

**The catalog is one table because "the map" was previously spelled out three times.**
`arena.gd` built it, `SceneFlow` named it on the loading card, and the lobby offered
a seed for it, and each of those knew "Whisperbloom Hollow" independently. Two of them
disagreeing about which map is loading is not a bug anyone would think to look for.
The entry carries the display name and the loading line as well as the kind and the
scene, so the card is generated from the same row the arena builds from.

**The seed and the map are separate fields, and only one of them means anything at a
time.** A static map has no seed — the lobby hides the seed row rather than greying it
out, for the same reason `friendly_fire` is hidden in a free-for-all: a greyed control
invites the question of what it would do, and there is no good answer.

**`arena.gd` branches once, at the top, and the branch is about lighting as much as
geometry.** A static map owns its own `WorldEnvironment` and `Sun`, so
`_build_environment` and the moon must not run for one — the island's environment is
tuned around torches being the key light at 0.30 moon energy (D-009), and dropping it
over a daylit arena makes both look broken. That is why the contract in
`static_map.gd` names the nodes it does, and why the void height is an export on the
map rather than `MatchState.VOID_HEIGHT`: -45 metres is a property of a floating island
with a deep rocky underside, not of an arena standing on the ground.

`scripts/world/static_map.gd` is written and the first map scene is not. The stub is
deliberate — the plumbing is testable today, and `MapCatalog` deliberately contains
no entry for a scene that does not exist yet, because `tools/playthrough.tscn` loads
for real every scene a map names.

## D-031 — Rust: collision baked in world space at load, and culling put back
The second map is a hand-made one — a fan remake of a small industrial FPS arena,
42 x 28 x 64 m of shipping containers and scaffolding, 148 meshes and 96,301
triangles — instanced whole by `arena.gd`'s static branch (D-029). Three things
about it needed deciding, and all three came out differently from what the
obvious answer would have been.

**Collision is built at runtime, in world space, from transformed triangles.**
The obvious answer is the importer's `-col` name suffix, or a `CollisionShape3D`
under each mesh carrying that mesh's `create_trimesh_shape()`. Neither works
here: 66 of the map's 150 nodes carry a **non-uniform** scale and five carry a
**negative** one, and a `ConcavePolygonShape3D` is not reliably scaled by the
transform of the node above it — the physics server takes a single scale off the
shape's owner, and a non-uniform one comes out wrong. The failure is not
dramatic, which is the problem: the containers look right and you fall through a
corner of one.

So `StaticMap._ready` walks every `MeshInstance3D`, transforms its `get_faces()`
into world space by its own `global_transform`, and hands the result to a single
`StaticBody3D` that has no transform of its own. The scaling problem stops
existing rather than being worked around. **`backface_collision` is on**, because
those five negatively scaled instances arrive wound the other way and a spear
would otherwise pass straight through the tower supports. The nets keep their
collision — they are chain-link, you can see through them, and a spear should
still stop on one.

Runtime rather than baked into a `.res`: it costs **110-190 ms** on the machine
this was written on, against 2.8 s to load the `.glb` itself, so a bake would
save under 7% of the map's load time and would add a build artefact that goes
stale silently the next time the source changes. The triangles are grouped into
16 m cells by *instance* — 12 shapes for this map — which keeps each shape's
bounding box tight without a per-triangle loop in GDScript. Bucketing whole
instances is 148 iterations; bucketing triangles would be 96,301, and the actual
vertex work stays inside the engine's `Transform3D * PackedVector3Array`.

**Back-face culling is forced back on, at load, on 28 of the 30 materials.**
Every material in the export is `doubleSided`, so the importer gives them all
`CULL_DISABLED` and the renderer draws the inside of every container, barrel and
oil tank before throwing it away behind the outside. The two exceptions are the
transparent ones — the chain-link `Net` and the `Solid Glass` in the doors — which
have to stay double-sided or they become see-through from one side only. The five
negative-determinant instances get a *duplicated* material with culling still off,
per instance, because a negative determinant reverses the winding the rasteriser
sees and back-face culling turns them inside out; duplicating is how the other
hundred-odd nodes sharing those materials keep their culling. `Mesh.030` on
`SM _ Tower _001` carries COLOR_0/COLOR_1, and its material imports with
`vertex_color_use_as_albedo` false, so nothing is tinting it — checked, not
assumed.

**Spawns sit at y ≈ 1.70 and were found by rendering, not by reading
coordinates.** The map's floor is not at zero: the walkable plane is 1.70 m up,
with a second tier near 2.0 and catwalks at 4-6.5 m. The eight pads are on the
main plane, each lifted 0.12 m the way the island lifts its solved pads, each
with its own measured floor height because the yard is not flat (1.59 to 1.82 m
across the eight). Finding them needed a tool: `tools/preview_map.gd` scans the
floor on a 2 m grid and prints three ASCII maps — height, whether a Gub-sized
capsule fits, and **how far you can see toward the middle from there** — and that
third one is the one that mattered. Two of the first eight pads passed every
geometric test and opened onto a container wall a metre away. The tool then
re-checks each pad with the physics the match will use, and the check is in the
gate, so a pad that ends up inside a shipping container fails a build rather than
being found by a player.

**The void is at -13 m, not -45.** The lowest vertex in the map is -0.64, so
anything below -13 has left through the one gap in the perimeter and is not
coming back. Forty-five metres of falling is a property of a floating island
(D-029), not of a yard.

**The environment is lighting and nothing else.** None of Whisperbloom Hollow's
look comes across — no sky shader, no moon, no aurora, no volumetric fog, no
torches, no scatter. Rust's own textures are the look. `rust_env.tres` is a plain
`ProceduralSkyMaterial`, one warm sun at 50 degrees with shadows, sky-sourced
ambient and reflections, and the island's tonemapping unchanged. It keeps glow
(a thrown spear makes its own material emissive so it can be seen coming, D-027,
and with glow off it simply cannot), keeps SSAO at about half the island's
intensity, drops volumetrics for plain distance fog, and has no `Lights` node at
all — it is outdoors under a hard sun and the containers with interiors are open
at one end.

One thing worth writing down because it cost an hour: **with
`ambient_light_source` set to SKY, Godot 4.7 ignores `ambient_light_energy` and
`ambient_light_sky_contribution` entirely.** Sweeping the energy from 1.0 to 2.0
produced byte-identical renders; only switching the source off changed anything.
The control that works is `background_energy_multiplier`, and 1.45 is where the
shadow under the drilling tower stops crushing (9% of the frame below 8/255 at
1.0, 1.6% at 1.45) with nothing anywhere clipping. This also means
`arena_env.tres`'s `ambient_light_energy = 2.5` does nothing — left alone, since
that is the island's file and its look is already signed off, but the comment
there is wrong about why it is dark.


## D-032 — Mushrooms and lures are carried stock off corpses, not abilities on a timer
The mushroom and the lure used to be abilities: `mushroom_cooldown` and
`lure_cooldown` refilled them forever, so every Gub in the match had one of each
roughly every twelve and eighteen seconds regardless of how the match was going.
That is a metronome, not an economy — it cost nothing to spend one badly, and a
player who had been losing for five minutes was armed exactly as well as the
player who had been beating them.

**They are inventory now, and the only source is a death.** One item drops per
kill, rolled once on the host in `MatchState._drop_loot`, and the only way to get
a mushroom is to walk over one. The two config dials that replaced the cooldowns
are named for what they do — `mushroom_use_delay` and `lure_use_delay`, a floor
on how fast a stack can be emptied, not a refill rate. Renaming rather than
retuning was the point: `mushroom_cooldown = 1.5` would have been a lie sitting
in the lobby for the next person to read.

**Spawning empty was the contentious half, and it was chosen deliberately.**
Spawning with one of each would have kept the old feel for the first thirty
seconds of a life and made the drops a top-up; it also would have meant every
respawn hands out free cover, which is precisely the thing that makes a losing
player's death cheap. Starting at zero makes the first kill of a match worth
something to everyone watching it, and it makes "I am holding two mushrooms" a
real position rather than a bookkeeping detail. The spear is untouched and is
still the thing you always have, so an empty Gub is inconvenienced, never
helpless.

**Carried stock is lost on death; letters are not.** `GubCombat.reset` zeroes
both counts on every respawn, which is what stops the player who is already
winning compounding into the player who cannot be approached. The drop is an
*independent* roll rather than the victim's actual inventory, for the same
reason: dropping a hoard would make the hoarder the most profitable thing on the
map and would let two players trade the same six mushrooms back and forth
forever. Stock has to leave the economy when its owner does.

**Nothing drops for a `VOID` death.** The Gub went off the edge; an item spawned
where it was would go off the edge too, and a drop nobody can reach is worse than
no drop. A self-kill does drop — a death is a death, and the alternative is a
rule nobody would guess.

There is no cap, no slot limit and no inventory screen. The only decision worth
having here is "spend it or keep it", and a cap adds "throw one away" to that in
exchange for nothing.

What would have to be true to revisit it: if matches routinely reach five minutes
with nobody holding anything — which happens if kills are rare rather than if
drops are — the answer is a starting stock of one, not a return to the timer.

## D-033 — Letters are uniform, duplicates are wasted, and this reverses the first instinct
`WinCondition.LETTERS` ends the match when one Gub holds G, U and B, which is how
the Gubs card game this is named after ends. Three decisions inside it are worth
writing down, because two of them look like oversights.

**A card's letter is `randi() % 3` and nothing else.** The first instinct — and an
earlier instruction, which this reverses — was to hand out the letter the picker
still needed, or to make them arrive in order. Both were dropped on purpose. A
card that knows who is about to pick it up is not an object in the world, it is a
progress bar with a mesh on it: two players racing for the same card would be
racing for different things, and the card on the ground would be worth more to
whoever is behind. Uniform means the thing lying in the grass is the same thing
for everybody, which is what makes contesting it a fight rather than an
arithmetic problem.

**Picking up a letter you already hold consumes it and grants nothing.** This is
the price of the rule above, and the alternative is worse in a way that is easy
to miss: a duplicate that refuses to be collected is a card three players take
turns walking over, sitting in the open, permanently, as the most conspicuous
object on the map. Consuming it keeps the map clean and makes the third player to
arrive pay for being third.

The cost is real and is not hidden: collecting three distinct letters with
duplicates wasted is the coupon-collector problem, 3·(1 + ½ + ⅓) ≈ 5.5 cards into
one pair of hands, and in a contested lobby most cards land in somebody else's.
At the shipping `letter_drop_chance` of 0.08 that is hundreds of deaths. **That
number is the one the user asked for and it ships unchanged**, with the dial
exposed in the lobby's Match panel — so the correction, if the first real match
wants one, is five seconds of slider rather than a release. The arithmetic being
written down here is the whole reason the dial exists.

**Letters are kept on death, and they are per player even in Teams.** They are
the only thing on a stats row a respawn does not touch, which is what makes them
progress rather than a streak. In Teams a team wins when *one of its members*
completes the set; the letters do not pool. A team of four pooling three letters
would beat a team of two before anybody had to fight for the third, and the card
game's ending is one hand with the whole word in it. *(**Superseded by D-049 in
its Teams half:** a Teams match is now won on the team's pooled letters, and
duplicates are judged against the team. Letters are still kept on death, and a
free-for-all is still per player.)*

Stored as a three-bit mask on `MatchState.stats` rather than as a set, because
`stats` is replicated whole on every score change and an int costs three bits of
that where an `Array[String]` costs an allocation per player per push. It is also
what the HUD wants: three lamps are `mask & LETTER_G`, with no membership test and
no ordering to get wrong.

## D-034 — A mushroom is planted where the camera is looking, not where the body is pointed
`GubCombat._mushroom_spot` used `_gub.facing()`, which is the body's yaw. The body
faces wherever it is *moving*, not wherever you are *looking* — that is the whole
design of the camera rig (see the header of `gub_camera.gd`) — so planting cover
while strafing put it out to one side, and planting it while backing away from a
fight put it behind you. Cover you have to stop and square up to is cover you die
placing.

**It now uses the camera's forward, flattened to horizontal and normalised**, and
the yaw handed to `ShieldMushroom.plant` is the camera's too, so the cap faces the
way you were looking rather than the way your feet happen to be.

**Which forced the direction onto the wire**, and that is the part worth knowing.
`GubCamera` shuts itself down on every copy but the owner's, so the host's copy of
a remote Gub's rig has never moved and never will — asking it would have planted
every client's mushroom due north while the host's worked perfectly, which is the
exact shape of the bug D-024 was. So `try_place_mushroom` reads the look on the
client that owns the Gub and sends it, precisely as `_request_throw_spear` already
sends the aim it read at the release.

The host still owns everything that matters. It flattens and normalises whatever
arrives (a client is free to send a zero, a NaN, or a vector pointing at the sky),
and both validation rays are unchanged — the blocked-ahead ray and the
ground-below ray never depended on which direction was handed in, and they are
what keeps a mushroom out of a wall and off a cliff edge. What a modified client
gains from this is the ability to choose a direction, which it could already do by
turning.

**And the mushroom is a quarter bigger**, asked for directly: at the old size the
cap cleared a standing Gub's shoulders but not its head, so cover you were behind
still showed the one part of you worth throwing at. `MODEL_SCALE` is 1.25 and the
five collision constants are the same 1.25 applied by hand. They have to move
together — scale one and not the other and the mushroom either stops spears a foot
outside itself or lets them through a cap you can see, both of which read to a
player as the netcode being wrong.

> **Superseded by D-039, and it is the whole of that entry's first half.** Every
> sentence in the paragraph above is wrong in a way that took a player in a real
> match to find. `mushroom.glb.import` already applies a `root_scale` of 1.25, so
> `MODEL_SCALE = 1.25` made a planted mushroom **1.5625** rather than 1.25. The
> five collision constants were never a fit to the mesh, so scaling them
> preserved nothing. And because this asset's canopy starts halfway up it,
> scaling the mushroom to widen the cap also *raised* it: the cap ended up
> spanning 1.86–2.44 m over a Gub 1.55 m tall, with a 0.55 m post the only thing
> anywhere in the band a body occupies. A Gub half a metre off the line of fire
> was 13% covered. The complaint this paragraph is answering — "cover you were
> behind still showed the one part of you worth throwing at" — was a symptom of
> collision constants that had never been measured, and making the whole mushroom
> bigger was the wrong remedy for it. The quarter is kept in **width** and the
> height comes back down; see D-039.
>
> What survives unamended is everything above this paragraph: planting along the
> camera's forward, the direction on the wire, and the host flattening whatever
> arrives.

## D-035 — A letter is earned by standing still for ten seconds, and dying gives it back to the map
Touching a letter card used to grant the letter. Now it starts a **hold**: the
Gub holds the card up for `letter_hold_time` seconds — ten by default — cannot
throw a spear for any of them, and only then is the letter theirs.

**Why the card is not the prize.** A card that pays on contact makes the whole
mode a footrace, and a footrace is decided before anybody is in range of
anybody. The two Gubs sprinting for a card were never going to fight over it:
whoever was closer took it and the other one turned around. The hold moves the
contest from *before* the card to *after* it, which is the only place a contest
can actually happen — the card is now a ten-second announcement that its holder
is standing somewhere with no spear, and that announcement is the mode.

It is also what gives the drop rate somewhere to hide. At 8% (D-033) cards are
scarce enough that the coupon-collector arithmetic is brutal; the hold means
each card that *does* appear is worth a fight, so scarcity reads as tension
rather than as waiting.

**Dying re-drops the card; it is not destroyed.** This is the half that makes
the rest work. A card that evaporated with its carrier would mean killing a
holder costs the match a letter, so the correct play against somebody nine
seconds into a hold would be to kill them and *nothing else would happen* — the
mode would grind to a halt in a lobby that understood it. Re-dropping makes the
kill a transfer instead of a deletion: the card lands at the corpse, free for
anyone, and the killer is standing over it. And with a letter potentially a
hundred deaths from being replaced, a card leaving circulation is a match that
can stop being winnable at all.

A letter therefore gets a fallback the abilities do not. `_drop_loot` skips a
drop it cannot settle onto ground, which is right for a mushroom — another one
exists after the next death — but a card that cannot find ground under the
corpse, because the carrier was lured off the edge, is put back on a **spawn
pad** instead. The pads are the one set of points on any map guaranteed to be
standable and reachable. A card turning up somewhere slightly arbitrary is a far
smaller problem than a letter leaving the match.

A **disconnect is treated exactly as a death**, down to the re-drop, with the
last known position of the Gub as the place. Anything else makes closing the
game the cheapest way to deny a card to everybody.

**Movement is untouched, and that is a decision, not an omission.** The obvious
instinct is to slow a carrier down — every game with a flag in it does. It was
considered and rejected by the user directly. Taking the spear away is already
the cost, and it is a cost that is *legible to the other player*: an empty hand
across a clearing is information, and information is what makes somebody walk
toward you. A movement penalty is only felt by the person paying it, adds
nothing anybody else can read, and turns "hold this in the open" into "hold this
in a corner", which is the least interesting ten seconds the mode could produce.
Layering both would make carrying a letter simply bad.

**Duplicates do not start a hold, and one hold at a time.** A card for a letter
you already hold is consumed on touch exactly as before — standing still for ten
seconds to be told "no change" would be the most miserable thing in the game.
A card walked over *while* a hold is running is left on the ground untouched,
not consumed and not queued: it is still there for you when you finish, and
still there for whoever gets to it first, which is the more interesting version
of both outcomes.

**It lives on `MatchState`, not on the Gub.** The hold is match state: it has to
survive being watched by peers who collected nothing, it ends in `award_letter`
which is already there, and — the part that decides it — the host must be the
only machine that can finish one. A countdown running on the client that stands
to gain from it is not a countdown. Clients keep their own copy purely to draw
it, and `is_holding_letter` is the *presence* of that row rather than
`remaining > 0`, so a client whose clock runs out a round trip early shows zero
and waits instead of putting a spear back in a hand the host still refuses to
throw with.

**The hand and the throw gate are one thing.** `GubCombat.has_spear()` is the
single gate — the throw asks it, the host asks it again, the aim marker asks it,
and `_refresh_hand` draws from it — so a hold is not a rule bolted on beside the
spear, it is the fact that the hand the spear comes out of has a card in it.
There is deliberately no second timer anywhere in the chain; the spear's own
header has insisted on that property since it was written, and this is the
second reason for it rather than an exception to it.

**The card in the hand brings a light, and that is what actually reads.** The
first pass put the glyph in the fist and left it there. Checked from the
touchline in `tools/combat_range.tscn letter`, a gold G in a gold Gub's fist at
twenty metres is a gold smudge on a gold body — the size was never the problem,
the contrast was. The card now carries a small `OmniLight3D`, the same trick the
card on the ground already uses, and a Gub mid-hold is lit up like a lamp from
across the clearing. Its position in the hand is derived from the spear's own
measured grip rather than guessed: it rides 22 cm up the shaft, the one volume
around that hand already proven clear of the Gub's skin in every carried clip.

**No new animation.** The Gub has eight Mixamo clips and no raised-arm pose, and
adding one means new source FBX and a headless Blender rebuild. The card in the
existing hand, with the spear visibly gone, is the tell. It is a real
compromise — the `Idle` guard reads as "boxer holding a letter" rather than
"holding it aloft" — and it is worth revisiting only if the pose turns out to be
what people miss, which the light makes unlikely.

*(**Amended by D-050:** the lit card is no longer the only tell. A pickup is
now announced in the kill feed, and a carrier gets a marker over its head that
everyone sees through walls. The hold itself is unchanged.)*

`letter_hold_time` is a lobby dial beside `letter_drop_chance`, and **zero is a
legal value** meaning "grant on touch" — the mode as it was, for a host who
finds the hold miserable. Zero is taken as a special case in
`_begin_letter_hold` rather than as a hold that expires on the next tick,
because a one-frame hold is one frame of the spear leaving the hand and coming
back: a visible flicker for the one setting chosen precisely so that there is
nothing to see.

## D-036 — The crosshair's recharge ring was deleted rather than fixed a third time, and the hand is the only spear indicator left
The crosshair used to close an amber ring around itself while the spear grew
back. It is gone, and so is every other timer on the HUD bar one — no ring, no
fill, no fade tied to a clock, and nothing on the ability bar that sweeps or
counts down.

**This is the second version of that ring to be thrown away, and that is the
argument.** The first divided by the recharge alone, so the ring sat full
through the 0.71 s windup and then dropped, which reads as a stall rather than
as a throw being made. The second divided by `spear_cycle()` — windup included —
so it swept from the click, which reads as a spear that has already gone while
it is still visibly in the hand. The comment that used to sit at `hud.gd:200`
was the record of that second attempt. Both are honest about a different half of
one throw and neither is honest about the throw, because the windup makes
"recharge" two different questions with one answer expected. A third
denominator would have been a third wrong one.

**The honest indicator already existed and is better: the spear in the Gub's
hand.** `held_spear.gd` has insisted since it was written that it be driven
straight off the cooldown the throw checks rather than by a timer of its own,
and after D-035 `GubCombat.has_spear()` is one expression covering the recharge
*and* a letter hold. So there is one truth, it is drawn in the world, and it is
drawn where the Gub facing you can read it too — which a ring on your own screen
never was. Two indicators for one fact is one too many the moment they can
disagree, and across a 0.71 s windup they did.

**The spear tile stays and goes binary.** The first instinct was to delete it
with the ring; the user corrected that directly — *"we can just indicate it down
their. i think i over complicated saying just remove the reload ring from the
cursor"* — on the condition that the hand is genuinely empty while reloading,
which was checked and is true. So the tile is lit when `has_spear()` and dark
when not, with no arc, no seconds and no number, and that one call covers a
recharge and a hold without the bar ever having to decide which is taking the
spear away. *(**Amended by D-054:** the tile times the recharge again, with a fill
and the seconds left, but only from the release. It is silent through the
windup and under a hold. The crosshair stays ring-free.)*

**The mushroom and lure tiles show counts, because they are stock and not
cooldowns** (D-032). `set_cooldown(remaining, total)` was the wrong shape for
them the moment the ability stopped refilling: the number that decides anything
is how many you are holding. Zero is drawn as plainly empty — dimmer than a tile
merely waiting out its use-delay — because you now spawn with none and spend
down to none regularly, and "you have none" and "not for another second" are
different answers that a player who cannot tell apart will keep pressing the key
for. The use-delay itself only dims the tile. It is a floor on spend rate, not a
resource anybody plans a fight around, and drawing a wedge for it would be
re-importing the thing this entry removes.

**The letter hold is the one timer still drawn, and it is a deliberate
exception.** A card being held up shows as three G/U/B lamps with the one being
earned filling from the bottom in amber, plus the exact seconds under it. That
is not the ring wearing a different hat: it is a single ten-second commitment
rather than a per-throw rhythm, there is no windup for it to be misread against,
and it is nowhere near the aim point. Standing unable to throw for ten seconds
with nothing on screen saying how much longer would read as the game having
broken, which is the failure this exception is spent on. It fills upward rather
than draining, because it is a thing being earned rather than a thing running
out — and nothing on this HUD drains any more.

Two smaller decisions inside it. **Nobody else's hold gets a HUD element**: the
lit card in their fist is the tell and it is meant to be an in-world one
(D-035), so the announcement is made to the clearing rather than to a corner of
your screen. *(**Amended by D-050:** somebody else's hold now gets a feed row
when it starts and when it is banked, and a marker over their head; the lamps
and the seconds are still yours alone.)* And **the seconds never show zero while a hold is running**,
because `is_holding_letter` is the presence of the host's row rather than
`remaining > 0` — a client whose copy of the clock expires a round trip early
would otherwise print "0" over a Gub the host still refuses to throw with.

The armed/disarmed distinction on the crosshair is kept, and it is worth saying
why it survived a cull of everything around it: it is not a timer and never was.
It says whether there is a living Gub behind the crosshair at all, which is why
a dead or spectating player gets grey ticks and an empty centre instead of an
invitation to aim.

What the UI had to be given to do this: one field. `MatchState._finish` now puts
`win_condition` in the summary beside `mode`, because the results screen is
driven entirely from that snapshot rather than from live state — the host can be
changing the next match's settings while people are still reading the table —
and without it the screen cannot tell a letters match from any other one.
Nothing else moved, and no rule moved into the UI.

## D-037 — The Elder is a second skinned mesh on the Gub's own skeleton, not a second Gub
`art/generated/elder.glb` is a purple robe and a wizard hat — 4,352 triangles, one
material, a copy of the skeleton to bind against and **no animation data at all**.
Its `MeshInstance3D` is re-parented onto a live Gub's `Skeleton3D` and keeps its
`Skin`, which binds by bone *name*. `tools/build_elder.py` builds it from
`art/generated/gub.glb`; `tools/preview_elder.gd` is the tool that does the
attach and takes the renders. This entry is the asset only — there is no
gameplay in it yet: no drop, no Elder state, no lightning.

**The alternative was a whole `gub_elder.glb` variant**, mesh and skeleton and
all nine clips, and it is worth saying what the shared skeleton buys and what it
costs. It buys one copy of the clips in the project instead of two — about
1.5 MB, but far more importantly one *place* they are defined, so the next round
of animation work on D-029's pipeline reaches the Elder without anybody
remembering to re-export it. It costs the guarantee: two files that were built
separately have to agree about where every bone rests, or the robe deforms
around a body that is not the one wearing it.

So the guarantee is bought back as a check rather than assumed. `build_elder.py`
finishes by reading both GLBs with `tools/gltf_io.py` and comparing, bone for
bone, the joint rest transforms and the inverse bind matrices. They agree to
2.2e-5 — round-trip float error through Blender's glTF importer and exporter,
four orders of magnitude under the 1e-4 the build refuses at — and the joint
names and their order come out identical, so Godot's name-based bind has nothing
to fall back on and nothing to get wrong. `preview_elder.gd` then resolves all 49
bind names against a real Gub's skeleton and prints the verdict, because a check
that only runs inside Blender does not describe what Godot does with the file.

**Nothing about the robe is a typed-in dimension.** The Gub's silhouette is
measured — 48 directions by 41 slices, as a *support function* over the body's
vertices with the arms left out — and the robe is the upper convex hull of that,
per angle, with the hem and the collar added as the two points cloth is *put* at
rather than measured from. The hull is the whole idea: cloth over a body rests on
its widest points and bridges the hollows between them, so a hull is what holds
the robe out at the belly at z = 0.75 and takes it straight down to the hem
instead of pinching in at the thigh gap at z = 0.45. The first attempt ray-cast a
mesh with the arm *faces* deleted, and it was wrong in a way worth recording:
deleting those faces takes the shoulder caps with them, so the silhouette at
collar height measured as nothing and the robe tapered to a funnel.

**The hat is rigid-weighted 100% to `Head`, which makes it correct by
construction** — it cannot clip a head it never moves relative to, in any clip,
ever. Its crown base is sized by measuring the skull at the brim plane (0.418 m
across, so 0.237 m of crown) and its axis leans 18 degrees back, which is the
angle at which the brim's front edge rides above the Gub's eyes instead of across
them. The Gub's two antennae leave the crown at z = 1.58 and arch forward to
z = 1.80, which is exactly the space a hat wants, so **they come out through the
front of the crown and that is deliberate**: the alternatives are a hat floating
above a head it does not touch, or a crown fat enough to swallow two antennae,
which is a bucket. The hat takes the Elder to 2.06 m against the Gub's 1.80, and
that is most of what makes it a different thing at range.

**The hem is the known risk and it is measured, not hoped for.** There is no
cloth simulation — this is a game asset and eight of them can be on screen — so
the skirt is skinned `LEG_SHARE_MAX` = 0.35 to the thighs at the hem, split
left/right by how far across the body a vertex sits. That number was 0.55 first,
and 0.55 is visibly worse: 0.6 m below a hip joint a 40-degree thigh swing drags
the cloth 0.42 m, and `Run` rendered as a sack being pulled about rather than as
a skirt. Every clip is then played, both meshes are evaluated with their armature
deformation applied, and every Gub vertex that starts the rest pose *inside* the
robe is tested against the cloth with a signed distance.

The report splits what comes out into two columns, because "outside the robe" is
two different things: a leg below the hem is outside it and is supposed to be —
that is what a hem is for — while a knee through a panel is the failure. They are
told apart by where the nearest cloth is, since anything that left through an
opening has the open edge itself as its nearest surface. What that measures, at
0.35:

    clip         through a panel   under the hem   deepest panel poke
    Idle              0.00%            3.14%       —
    Walk              0.00%            6.06%       —
    CrouchIdle        0.00%            5.75%       —
    Throw             0.27%            9.47%       0.140 m
    CrouchWalk        0.74%            4.57%       0.243 m
    JumpOne           0.91%            4.66%       0.048 m
    JumpTwo           2.00%            5.48%       0.275 m
    Slide             2.96%            5.16%       0.366 m
    Run               3.78%            7.43%       0.185 m

**Idle, Walk and CrouchIdle are clean. Run is not, and the render says so.** A
shin comes through the front of the skirt around knee height at the extremes of
the stride — 0.185 m at its worst — and the honest description of
`out/elder_run_sheet.png` is "the leg emerges through the robe a little too
high", not "the robe holds". `Slide` and `JumpTwo`'s ground roll are worse in a
different way: the body curls up inside the skirt and the robe becomes a bag with
limbs out of it. Both are inherent to a rigid surface over a body that folds in
half, both are under a second long, and both are seen from behind at speed. They
are recorded here rather than fixed, because fixing them properly means cloth
simulation, and that is a different decision from this one.

**The material is what the brief was actually about** — *"the material is
important of rit, make it a dark purple and very wizard style"* — and it is two
1024² images this script generates, not shader nodes. That is not a preference:
glTF carries images and flat factors, and a Noise Texture node would not survive
the export at all. The base colour carries a vertical value ramp, the fold
shading *in phase with the modelled folds* (the texture and the geometry share
`FOLDS`, so painted valleys land in modelled valleys), a woven grain, and the
trim bands and rune glyphs. Roughness is 0.82 against the Gub's 0.9: velvet is
not quite as flat as whatever a Gub is made of, and a fraction of sheen is most
of what tells a viewer they are looking at two materials.

The purple itself was picked by rendering, not by picking. The first build was
`#3A2A58`, which is a perfectly good dark purple on a swatch and came back as
lilac, because a robe is lit by an ambient term and a key light and then run
through ACES before anybody sees it. The shipped value is `#2F1D45` — 274
degrees, 58% saturation, 27% value — with folds down to `#140C20` and shoulders
up to `#3F2A5B`. Checked in both maps' own light rather than in a studio:
`out/elder_noon_rust.png` uses `rust_env.tres` and `rust.tscn`'s exact `Sun`
transform, `out/elder_dusk_whisperbloom.png` uses `arena_env.tres` with
`arena.gd`'s moon and `torch.gd`'s flame.

**`--emission` is the same lever D-027 argued for, and the Elder needs it more
than the Gub did.** The emissive map is near-black cloth with bright runes on it,
so the glow is arcane detail rather than a robe-shaped lamp, and one strength
scales both. Default 1.0. At 0 the socket is left unwired — a plain base-colour
PBR material rather than one multiplied by nothing — and
`out/elder_dusk_emission0.png` is what that looks like under Whisperbloom's
0.30-energy moon: a black cut-out with no purple in it and no runes at all, which
is precisely the failure D-027 measured on the Gub's yellow. The robe has further
to fall than the Gub did — 0.10 in linear against 0.6.

**The robe has no sleeves and no mantle, and that is forced by this body.** The
Gub's arms leave the shoulders at z = 1.098, directly under a head that starts at
1.15; there is no room for a cape that an elbow does not live inside. What there
is instead is a standing cowl over the back 96 degrees only, rising 0.26 m to
z = 1.42 — behind the head, clear of the arms, and under the hat's brim so the
two never argue. Wider than 96 degrees and its two ends come round far enough to
stand up beside the Gub's cheeks in a front view, which reads as a broken collar
rather than as a wizard.

One number the cowl is on notice for: the Head bone turns up to **76 degrees**
against the chest in `Run`, which is a lot, and the cowl's top edge follows it
only 45% of the way from 75 mm away. Nothing shows in the renders. If a future
clip turns the head further, it will show there first.

**`tools/find_blender.sh` was split out of `tools/build_gub.sh`** so both build
scripts share one search, for the reason `tools/find_godot.sh` gives at the top
of itself: a search for where somebody installed a large application has to stay
in step with reality, and two copies of it will not.

## D-038 — The Elder: a robe off a corpse, a bolt out of the hand, and a death that consumes it
*Four parts of this are superseded by **D-040**, which turned the Elder into a
timed invincible burst after the user played this version of it. Each is marked
where it stands. In short: the Elder **cannot be killed** and lasts **20 seconds**
rather than until it dies; the bolt leaves **0.2 s** after the click rather than
at the clip's 0.71 s release; the cooldown is **1.0 s** rather than 5.0; and the
drop chance is **2%** rather than 5%. Everything else below — the robe as a
fourth drop, the roll order, the bolt out of the hand, the 28 m range, the
crackling fist, the hold gate, two Elders at once — still stands.*

D-037 built the robe and stopped there, deliberately: an asset with no drop, no
state and no weapon behind it. This is the rest of it.

**The robe is a fourth thing that falls out of a corpse**, rolled by
`MatchState._drop_loot` alongside the mushroom, the lure and the letter card.
`elder_drop_chance` is 0.05 against the other two's ~47% each *(**superseded by
D-040**: 0.02, because what the dial hands out is no longer a modest upgrade)*,
and — unlike the letter — **it is not gated on a win condition**. That is the one asymmetry worth
arguing for: a letter is a scoring mechanic and only exists in the mode that
scores it, but the Elder is a *weapon*, and a weapon that only appears in one of
four modes is a weapon nobody ever learns to play against. So the dial sits in
the lobby's Match panel above the friendly-fire toggle rather than in the pair of
rows that hide themselves.

The roll order is **letter, then robe, then the remainder split evenly between
mushroom and lure**, and it is written into the comment at the roll because it is
exactly the sort of thing that gets reordered for tidiness and silently changes
the balance: put the robe first and a letters match quietly drops fewer cards
than the number on the slider in front of the host.

### Dying consumes the robe. It does not drop.
***Superseded by D-040 in its central claim.** The Elder cannot be killed any
more, so a death is no longer what ends one: a twenty-second clock is, and the
only death that can still reach the robe is a fall into the void. What survives
is the second sentence of this section — a robe that ends is **consumed**, never
put back on the ground — which now applies to the clock, the void and a
disconnect alike. "Nothing else ends it" below is the paragraph that is simply
no longer true.*

This is the opposite of the letter rule (D-035) and it was chosen on purpose.
A card that evaporated with its carrier would take a letter out of a mode that
may be a hundred deaths from replacing it, so the card lands at the corpse and
the kill is a *transfer*. The robe is the other shape: killing an Elder has to be
worth doing for its own sake, and a robe lying on the body would hand the whole
reward of that fight to whoever won the scramble afterwards rather than to
whoever won the fight. So an Elder's death takes the Elder out of the match, and
the next one arrives when the drop table says so.

Nothing else ends it. Not a respawn timer, not picking up a mushroom, not
finishing a letter hold — an Elder that survives is still the Elder, which is
what makes killing one the play. A disconnect is treated exactly as a death, as
it is for a hold, and the world gains nothing from it.

**Two Elders can exist at once and that needs no rule.** Two robes can be on the
ground; both can be picked up. An artificial "only one" would mean a robe that
refuses to be collected, which is the most conspicuous object a map can have.

### The lightning comes out of the hand, not out of the sky
The user: *"it should come from the elders hand, you can use the same throw
animation"*. A sky strike was the obvious alternative and it is rejected here
permanently, because of what it would quietly break.

A shield mushroom's entire definition is cover you cannot be hit through
(D-032, D-034). A bolt that falls from above has no line to block, so every
mushroom in the game would go on *looking* like cover while being none against
the strongest weapon in it — and the player behind one would have no way to find
that out except by dying. The bolt therefore leaves the Elder's fist and travels
to the target as a **hitscan ray on the world, player and deployable layers**, so
it is stopped by exactly the things that stop a spear. Cover works because the
bolt is a line, and it is a line because the user said it should come from the
hand.

**It replaces the spear rather than joining it.** `has_spear()` is false for an
Elder for as long as it is one, the fist carries no shaft, and the same mouse
button fires the bolt. One weapon, one button, one thing to learn.

### It reuses the Throw clip, and the release time is the point
***Superseded by D-040 in its timing.** The clip is still reused and the branch
is still taken at the release, which is the part that mattered; but the release
is now `MatchConfig.lightning_delay` — 0.2 s — and the clip is played at 5.67x so
the arm gets there. The paragraph below about "half a second of a Gub visibly
winding up" is the thing the user asked to be removed.*

A click plays the existing `Throw` one-shot and the bolt leaves at
`GubAnimator.THROW_RELEASE_TIME` — 0.71 s, derived in `gub_combat.gd` from the
clip window and the playback rate — with the aim read at that moment and not at
the click, exactly as D-025 specifies for the spear. The branch between "throw a
spear" and "cast a bolt" is taken **at the release**, beside where the aim is
read, so one windup, one cancel-on-death, one cancel-on-letter-hold and one relay
to the other peers serve both. A parallel windup for the Elder would have been a
second copy of the one piece of timing D-025 exists to keep honest.

It also means the Elder gives its target the same warning a thrower does: half a
second of a Gub visibly winding up. There is no charge-up, no beam, no warning
ring on the ground, because the animation already is the warning.

**Range: 28 m, and it is derived from the spear rather than picked.** Hitscan
with no travel and no drop would be a map-wide delete at any range you can see.
A spear leaves at 42 m/s and falls at 8 m/s², so at 28 m it has been in the air
0.67 s and dropped 1.78 m — one Gub's height, near enough exactly. Inside 28 m
the spear is a point-and-click weapon; past it the throw becomes a judgement
about arc, which is where D-014 says the skill in this fight lives. So the Elder
owns precisely the band where the spear needs no skill, and outside it the spear
is still the better tool. On Rust (42 x 64 m) that is most of a fight and not the
length of the yard.

**Cooldown: 5.0 s against the spear's 3.0**, and a separate dial. *(**Superseded
by D-040**: 1.0 s. The argument below is still sound and simply stopped applying
— it prices a weapon somebody carries until they die, and the Elder is now a
twenty-second window in which four shots and twenty shots are different
weapons.)* A spear can be
dodged — it takes a third of a second to cross fourteen metres and it drops — and
a bolt cannot: once it is released the shot has already landed. The only price
that can be charged for that is the wait before the next one.

**A letter hold stops it.** `has_lightning()` shares the hold half of the spear's
gate and not the recharge half. Without that, becoming the Elder would make the
ten-second hold free for exactly the player who most needs to be vulnerable
during it.

### The hand crackles when it is loaded and is bare while it recharges
The spear's great virtue is that an empty hand says "harmless" from across a
clearing, and D-036 deleted the HUD's recharge ring precisely because the hand
said it better. An Elder has no spear — so without something in its place, the
most dangerous Gub in the match would be the one player nobody could read.

So the Elder's fist carries `HandCrackle`: three short arcs of the bolt's own
geometry, restruck every thirtieth of a second, around a small violet light. Same
language, same distance, no HUD required. It hangs off the same
`BoneAttachment3D` as the shaft and the letter card, so the hand can never hold
two things, and which one is showing is still decided in one place —
`GubCombat._refresh_hand`, off the same gates the shot is refused by.

The light is what actually carries at range, and that is D-035's lesson rather
than a guess: a glyph in a gold fist at twenty metres is a gold smudge on a gold
body, and what reads is that the Gub is *lit*.

**It is put back by a poll, not by a timer**, and that was the one place this
deliberately departed from the spear. The spear's `_regrow_spear` arranged the
same thing with a `SceneTreeTimer` started at the moment `_spear_ready_at` is
set — two clocks measuring one interval, a `Time.get_ticks_msec()` deadline and
a sum of frame deltas. They agree to about a millisecond, and a millisecond the
wrong way means `has_spear()` is still false on the frame the timer fires and
nothing ever asks again. `GubCombat._tick_charge` instead compares the hand
against the gate every frame, on Elders only, and cannot drift from it.

*Since D-039 the spear does the same and `_regrow_spear` is gone.* Writing this
paragraph was not enough to fix the thing it was about, which is the whole
lesson of that entry: the spear went on losing that race for the rest of the
session, in front of a player, while the correct argument for why it would sat
here in the document.

### "Way over the top" is the requirement, and here is what it cost
`LightningBolt` is built fresh — there was almost no particle work in this
project to copy — and it is drawn to the rule `SpearTrail` was written to: this
is light, not a surface, so everything in it is unshaded and additively blended
and is therefore brighter than the night forest *and* than Rust's noon.

It is an `ImmediateMesh` rather than a particle system, for the trail's reason and
one more: a stroke of lightning is a continuous jagged line, and the whole read of
the effect is that its shape changes every other frame — re-emitting a particle
system at 30 Hz costs far more than rebuilding four hundred vertices. One mesh
carries a white core inside a violet glow plus four forks, re-jittered every
0.03 s over the 0.22 s it lives, pinned at both ends by a `sin(pi t)` taper so it
genuinely leaves the hand and genuinely arrives at the body.

Per bolt: one mesh (ten surfaces, ~450 vertices, rebuilt seven times), two
shadowless `OmniLight3D`s dead by 0.16 s, a one-shot burst of 40 CPU sparks gone
by 0.7 s, and a scorch quad where it hit a surface. Two Elders firing at once is
four extra dynamic lights for a sixth of a second — a quarter of what the
island's fifteen torches cost, for a sixtieth of the time. The victim is thrown
along the bolt at a little over twice a flat spear's shove, and the caster and
anybody within 16 m of the impact get a camera kick through
`GubCamera.shake`, which already respects the `camera_shake` user setting.

Two numbers came out of looking at it rather than out of reasoning, and both are
recorded in the file because they were wrong in the same instructive way.
**The flash started at 26 energy over 15 m and blew the entire frame to white**,
taking with it the body it was supposed to be lighting; a flash that hides the
kill is not a flash, it is a wipe. And **48 additive spark quads emitted from one
point on one frame is not a shower, it is a white ball** — they only become
sparks once they have separated, and the first three frames are the ones anybody
sees. They now start scattered through a 0.45 m sphere and leave at 16 m/s.
Sized on the quad rather than through `CPUParticles3D.scale_amount_*`, which did
not take: the sparks came out half a metre across regardless of it.

The thunder is two synthesised voices rather than one — `thunder_crack` and
`thunder_roll`, both new in `tools/make_sfx.py` — played together at the impact
through the existing 3D-varied playback. Two clips because the balance between
the crack and the roll is the whole difference between "that landed near me" and
"there is weather somewhere", and that balance should be a number in
`LightningBolt` rather than a re-run of the script.

`out/lightning.png` is the evidence. `out/elder_hand.png` is the crackle.

### The HUD tile changes weapon and stays binary
The ability bar's first slot swaps its glyph and its label and goes on being lit
or dark off one boolean — `has_lightning()` instead of `has_spear()`, covering
the longer recharge and the letter hold in exactly the same way. No sweep, no
seconds, no second kind of readout. That is D-036 applied to a second weapon
rather than an exception to it. The kill feed gets one mark of its own (⚡),
because it is the one kill in this game worth reading the feed to find out about.

### What checks it
`tools/match_rules.gd` grew a scenario (122 → 159 checks): the robe is claimable,
claiming it sets the Elder state *and* puts the cloth on the skeleton, an Elder
has no spear and a crackling hand, the cooldown gates a second cast, a letter
hold blocks one on the client and again on the host, death ends it and drops
nothing, a respawn does not give it back, two Elders can coexist, and a leaver
takes their robe with them. *(D-040 rewrote the death half of that scenario —
nothing kills an Elder but the void — and took the file to 195.)*

`tools/combat_range.tscn lightning` is the other half and is the one that
matters: it kills a dummy with `elder_drop_chance` forced to 1, lets the player's
own body walk over what falls out, and fires one bolt at a Gub fourteen metres
away — then **prints its own verdict**, because a still frame of a bolt looks
identical whether or not the thing at the far end of it fell over. The smoke gate
runs it, which takes it from 13 checks to 14.

The runtime attach is `tools/preview_elder.gd`'s, line for line, in
`ElderRobe.don`: find the `Skeleton3D`, re-parent the `MeshInstance3D`, keep its
`Skin`, clear its transform, null its owner. That tool resolves all 49 bind names
against a live Gub and prints the verdict, so it is the thing that says the robe
binds at all — and a second, subtly different attach path in the game would have
meant the thing that is checked and the thing that ships were not the same thing.

## D-039 — Two bugs a player found, and the same shape under both: a number nobody ever measured, and a clock nobody ever re-read
Both came out of a real match, in one sentence each — *"the mushroom is not
reliably blocking spears / you can run through it"* and *"the spear model is not
reliably reappearing in the gubs hand after the delay after throwing"*. They are
unrelated in the code and identical in shape: in each one something was worked
out once, correctly, written down, and then never asked again.

### The mushroom's cap was a metre above the fight

`shield_mushroom.gd` had a cap cylinder spanning **1.86 → 2.44 m**. A standing
Gub's collision capsule is **0 → 1.55 m**. So the only thing anywhere in the band
a Gub occupies was the stem: a post **0.55 m wide**, with a 5 cm gap above it
where the stem stopped and the cap had not started.

Measured by `tools/combat_range.tscn cover`, which stands a real mushroom up and
fires a comb of rays through it on the deployable layer. Before:

    y 0.15 … 1.80 m   0.54 m wide
    y 1.95 … 2.40 m   2.06 m wide
    a standing Gub squarely behind it, from 14 m:  87% hidden
    the same Gub half a metre out of line:         13% hidden

**Those two numbers together are the bug.** Standing exactly behind the post you
were covered, so the mushroom "worked" every time anybody checked it deliberately
— and one step to either side, which is what a fight does to you inside a second,
and you were a target with a decoration in front of you. There was no cap
anywhere near the fight; 87% was a 0.55 m post doing all of it. Walking was the
same story with no ambiguity in it: a Gub closed to **0.66 m** of the middle of a
mushroom whose cap is 2.06 m across, which is exactly what "you can run through
it" means.

**D-034 caused it, and the mechanism is a trap the next asset will have too.**
`mushroom.glb.import` carries `nodes/root_scale = 1.25`, so the scene Godot hands
back is *already* a quarter bigger than the file. D-034 then set
`MODEL_SCALE = 1.25` in the script on top of it. The two multiply: a planted
mushroom was **1.5625**, standing 2.54 m tall. And this asset's canopy begins 54%
of the way up it, so scaling the mushroom to make the cap wider is also scaling it
to lift the cap — at 1.5625 the canopy ran 1.38–2.54 m over a stalk 0.4 m thick,
hanging clean over the head of the thing it was meant to be hiding. **Cover you
stand under is not cover.**

The five collision constants were moved by the same 1.25 by hand, and the comment
above them said they *were* that 1.25 and had to "move together" with the model.
Both halves were false. They had never been fitted to the mesh in the first
place, and a uniform scale is precisely the operation that cannot preserve a fit
between a cylinder and a mushroom.

### What the model actually is, since nobody had looked

Sliced horizontally, `mushroom.glb` is not one mushroom. It is a **cluster** —
one large one with a couple of small ones round its foot — and the large one
**leans**. In raw model units, with the file 1.6235 tall:

    0.04-0.22   the foot and the small mushrooms, 0.66-1.34 across
    0.22-0.52   the stalk, 0.53-0.77 across
    0.58-0.82   the neck, 0.25-0.58 across — the thinnest part of it
    0.88-1.60   the canopy, an ellipse 1.19 by 0.81 at its widest

and the canopy's centre is at **(0.035, -0.40)**, not the origin. That off-centre
axis was its own bug and had been there all along: planted, the mushroom you
could see stood **0.63 m to one side** of the point the ability had checked the
ground at, and every collision cylinder stood beside the mushroom rather than
inside it.

### The fix: wide and tall are separate

`MODEL_SCALE` is gone; there are two now.

* **`MODEL_SCALE_WIDE` stays at 1.25.** The quarter the user asked for is kept,
  in the axis it was asked about: the cap is 1.86 m across, a quarter wider than
  before D-034.
* **`MODEL_SCALE_TALL` is 0.86**, putting the canopy's underside at **0.95 m** —
  low enough that a standing Gub is behind it from the chest up and a crouching
  one is behind it entirely, high enough that its top edge at 1.75 m leaves the
  antennae of the 1.80 m Gub model showing over it. The mushroom is 1.75 m tall
  rather than 2.54, which is *shorter than it was before D-034* and *wider*.
* **`MODEL_AXIS`** slides the model back onto its own axis, so the mushroom
  stands where it was planted — which is also what lets both cylinders stay on
  the node's origin and still be inside the mushroom.
* The cylinders are a **measurement** of the mesh at those scales rather than an
  arithmetic scaling of anything: stem 0 → 0.95, cap 0.95 → 1.75, meeting with no
  gap. `CAP_RADIUS` 1.03 and `STEM_RADIUS` 0.275 are untouched.

After, from the same rays:

    y 0.15 … 0.90 m   0.54 m wide
    y 1.05 … 1.65 m   2.06 m wide     <- a standing Gub tops out at 1.55
    squarely behind it:        93% hidden   (was 87)
    half a metre out of line:  58% hidden   (was 13)
    walked into it and held 1.41 m off the middle   (was 0.66)

**`CAP_RADIUS` 1.03 circumscribes the canopy rather than fitting it** — 10 cm
proud across the ellipse's wide axis and 32 cm across its narrow one — and that
is a choice rather than a leftover. A cylinder cannot be an ellipse, and of the
two ways to be wrong, a spear that stops a handspan short of a cap reads as a
spear hitting a mushroom, while one that passes through a cap you are looking at
reads as the game being broken. The stem stays thin on the other half of the same
argument: 0.275 m is inside the stalk everywhere except the neck directly under
the cap, and the cap already covers anything aimed there.

**The missing 7% is the legs, and it is meant to be there.** Below 0.95 m the
only cover is the stem, so a thrower who aims low and from the side gets a shin.
That is what a mushroom is, it is what this file has always claimed ("a thin stem
so a Gub can stand close and still peek round it"), and it is a better
counterplay than the lure alone. What is gone is being shot in the chest through
a cap.

### The spear was waiting on a clock nothing ever re-read

`_do_throw_spear` set `_spear_ready_at = _now() + spear_recharge`, off
`Time.get_ticks_msec()`. `_regrow_spear` then awaited
`get_tree().create_timer(spear_recharge)` — a sum of frame deltas — and called
`_refresh_hand()` once when it fired. `_refresh_hand` asks `has_spear()`, which
requires `spear_cooldown() <= 0.0`.

**Two clocks measuring one interval, and one callback between them.** When the
`SceneTreeTimer` got there first — by a millisecond, or by rather more — the
shaft was correctly not restored, and **nothing ever asked again**. The hand
stayed empty until the Gub died. That is the whole of "not reliably": an outcome
that depends on how the frame deltas happened to land.

It is not even rare. Driven headless, where `_process` runs unbounded and the
delta sum arrives well ahead of the wall clock, the old code lost **12 of 12**
cycles.

The fix is `GubCombat._tick_hand`: `_tick_charge` for the shaft. Compare the hand
against the gate every frame and repaint only on the frame the answer changes.
The `await` is deleted rather than kept beside it — leaving one of two wrong
clocks in place as an optimisation only leaves it there to be believed.

Three properties are kept deliberately:

* **The hand still reads `has_spear()`** and never a timer of its own. That is
  what `held_spear.gd`'s header has insisted on since it was written, and what
  D-035 and D-036 both lean on. **The bug was the missing retry, not the
  delegation.**
* **The chime fires once.** The poll acts only on the transition, and it asks
  `has_spear()` rather than its own `want`, so it is silent through a windup —
  when the arm is going back and the spear is on its way *out* — and never sounds
  for a Gub mid-letter-hold, which D-035 is explicit about. It is also silent for
  a corpse: a Gub killed mid-recharge used to be chimed at while dead.
* **The condition lives in one place.** `_wants_shaft()` is the single
  expression, asked by the refresh that acts on it and by the poll that notices
  it has gone stale, exactly as `_wants_crackle()` already was. Two copies that
  drift by one clause is a Gub whose hand is repainted every frame for ever.

**D-038 already contained the correct argument for all of this**, written about
the Elder's crackle, and ending: "`_regrow_spear` arranges the same thing with a
`SceneTreeTimer` … and nothing ever asks again." It was right, it named the exact
failure, and it was in this document — and the spear went on losing that race for
the rest of the session, in front of a player. Writing down why the thing without
the bug does not have it does nothing for the thing that does.

### The checks, which are the real point

`mushroom deploys` asserted **`snapshot: wrote`**. It proved a PNG existed. It
passed on every run while the cap sat a metre above the fight, because a cover
item whose only check is that it rendered is not checked at all — the README
calls this "a thing wired into a testbed and into nothing else", and this is the
third time.

Two modes were added to `tools/combat_range.gd`; the gate goes from 14 checks
to 18.

**`cover`** stands a real `ShieldMushroom` up through `plant()`, prints the ray
profile above, and asserts three things in one run:

1. a spear thrown at a Gub standing behind a mushroom does not kill it;
2. the **same** throw, after the mushroom has withered, does;
3. a Gub walking into one is held off at `CAP_RADIUS + CAPSULE_RADIUS`.

The second is not a nicety. "Did not die" is satisfied by a spear that has
stopped killing anybody at all — a broken launch, a dummy already dead, a
`report_kill` that never arrived — so **without a control on the same geometry
the first assertion proves nothing**, which is the exact failure that let the
real mushroom get here. The threshold in the third is derived from the two radii
rather than typed in, so it follows the constants instead of having to be
remembered beside them.

And the mushroom is planted **half a metre off the line of fire**, which is the
other half of why the mode is worth anything. Lined up perfectly the 0.55 m stem
blocks the shot on its own — the mode was written that way first and it passed,
against a mushroom that stopped nothing, which is the 87%-versus-13% above
happening to a test instead of to a player. Half a metre is one step by either
Gub and nowhere near the edge of a cap 2 m across, so anything that stops the
spear there is stopping it with the cap.

**`recharge`** throws twelve times and requires the shaft to be back in the fist
at the end of every cycle, counting the *consecutive frames* the hand and the
gate disagreed for rather than a boolean — "not reliably" is a duration, not a
yes or no. Then it does the half that cannot pass by luck: it empties the fist by
hand while the gate still says armed, and requires the hand to refill itself. A
hand repainted by a one-shot timer has already had its chance and stays empty for
ever; a polled hand notices on the next frame. Twelve real cycles catch the race
if this machine happens to lose it and prove nothing at all if it happens to win
twelve in a row, which is the trouble with checking a race by running it — so the
fault is *stated* rather than waited for.

Both were run against the old code first, because a regression guard that has
never been seen to fail is not a guard (D-015). `cover` fails two of its three
verdicts; `recharge` fails all twelve cycles and then reports that nothing ever
put the spear back.

One trap paid for on the way: a `StaticBody3D` added to the tree does not exist
to the physics server until the next step, so rays fired on the frame a mushroom
is planted report it **0.00 m wide at every height** — a thoroughly convincing
picture of exactly the bug being measured, and wrong. The profile is taken a
frame later.

`out/mushroom_cover.png` is a spear stopped dead in the cap with the Gub standing
untouched behind it.

## D-040 — The Elder is twenty seconds of being unkillable, not a weapon you keep until somebody takes it off you
The user played one and came back with six sentences:

> There should be basically no delay for the lightning, right when you press then
> it should shoot maybe .2 seconds after. also it should recharge faster, way
> faster, also they should be invincible, and it should last for 20 seconds
> rather then until they die. They should also get boosted speed and jump.

**Four of those reverse decisions made earlier in the same session**, and D-038
is superseded in the places named below rather than left standing beside this
one. A document that records both answers as current is worse than one that
records neither.

### What it was, and why "until you die" stopped working the moment it could not
D-038's Elder was a *persistent upgrade*: a robe off a corpse, a stronger weapon
on a five-second recharge, held for as long as you could stay alive, and
consumed by the death that ended it. The whole shape of that rested on one
sentence — **the counter-play to an Elder is killing it** — and the cooldown,
the drop chance and the consume-on-death rule were all priced off it.

Invincibility deletes that sentence. An Elder that cannot be killed and stays
the Elder until it is killed is the Elder for the rest of the match, so the exit
has to be something else, and the only honest candidate is a clock. That is why
the twenty seconds and the invincibility are one change and not two: neither is
coherent without the other. What replaces the old counter-play is not weaker,
only different — **you no longer beat an Elder, you outlast one** — and twenty
seconds is a length of time a player can decide to spend behind a rock.

Everything else in the list follows from that. A window that fires four times is
not the same weapon as a window that fires twenty, so the recharge came down to
1.0 s. A window you spend walking is not a window, so speed and jump went up.
And two thirds of a second of wind-up is a third of a bolt's worth of warning
when the whole state lasts twenty, so the cast delay came down to 0.2 s.

### The cast: 0.71 s becomes 0.2, and the clip is sped up to meet it
The bolt used to leave at `GubAnimator.THROW_RELEASE_TIME` — 0.71 s, the moment
the `Throw` clip's right hand reaches peak forward speed — because the user had
said "you can use the same throw animation" and reusing the release was the
honest way to do that. **That half of D-038 is superseded.** The clip stays;
what changes is how fast it runs.

`lightning_delay` (0.2 s, a lobby dial) is the number now, and the clip is played
at whatever rate puts its own release there. Firing at 0.2 s while an arm
authored to take 1.133 s of clip is still winding up would look broken in a way
no amount of particle work covers, so:

    GubAnimator.THROW_WINDOW    = 1.633 - 0.50 = 1.133 s of clip
    throw_rate_for_release(0.2) = 1.133 / 0.2  = 5.67x
                                = 3.54x the spear's own 1.6

**Derived, never typed.** A hard-coded 5.67 sitting beside a dial that can be
dragged to 0.5 is a hand that finishes a third of a second before the bolt it is
supposed to be throwing, and nothing anywhere would say so — which is precisely
the failure D-025 exists because of, one level up. `play_throw(rate)` sets the
`TimeScale` node before firing the one-shot, and `GubCombat._play_windup` works
the rate out from replicated state on *every* peer rather than sending it, so it
cannot arrive wrong at the far end.

**Zero is a legal setting and means "on the frame of the click".** It is also a
division by zero, so `throw_rate_for_release` saturates at `THROW_RATE_MAX` —
8x, the whole arm in 0.14 s — rather than returning infinity. Below about 0.14 s
of delay the bolt therefore leads the hand by up to a seventh of a second, which
at that setting is exactly what was asked for; everywhere above it the two are
the same number.

The animator's arc scrub had the same shape of dependency and was fixed with it.
`_scrub_air` measured the jump clip's phase against a constant `JUMP_VELOCITY`,
and phase is a *ratio*, so against a Gub that left the ground 25% faster it held
the take-off pose for the first fifth of the climb. It asks
`Gub.jump_velocity()` now.

### Invincible, and the void is the exception for the reason spawn protection's is
`MatchState.report_kill` is the one place a death is decided, and it now refuses
one whose victim is the Elder — beside the `is_invulnerable()` spawn-protection
check it is modelled on, and **carving out `Gub.Cause.VOID` for the same reason
that one does**: a Gub that cannot die to the void falls past the bottom of the
island for ever, alive, unreachable and unrespawnable. Without that clause the
invincibility is a soft-lock waiting for somebody to walk off a ledge.

Three details were decided rather than fallen into.

**It sits after the friendly-fire check, not beside the invulnerability one.** A
shot stopped because the thrower is on your team was never going to kill you and
the robe had nothing to do with it; flashing a ward at it would credit the robe
with a save it did not make. What reaches the Elder clause is a shot that would
otherwise have landed.

**Invincibility is about death, not motion.** An Elder is still solid, still
lured, still shoved by a bolt, still knocked off a ledge. Making it immovable
would have been one line and would have deleted the lure as counter-play at the
exact moment the lure is the most interesting thing in the fight. The refused hit
also calls `note_attack`, which is the clearest case that function has ever had:
an Elder lured over the edge is a void death somebody earned.

**A survived hit has to read as one.** `SpearProjectile._stick_in` hides a spear
and parks it on the victim for a ragdoll to adopt, and against an Elder there is
no ragdoll coming — so the strongest weapon in the game would hit the strongest
target in it and simply cease to exist, with nothing at either end saying whether
the throw had even happened. A spear now `_glance_off`s an Elder: it stops at the
point of impact and is freed. The *feedback* is `WardFlash`, broadcast from
`report_kill` and only from there, because that is the one place that knows a
death was refused — which is also what gets the other Elder's bolt the same
treatment without a second copy of the rule living on the projectile. It is the
robe's violet rather than the bolt's white, a shell and a light gone in 0.26 s,
and it is deliberately not a shield: a ward that lingers reads as cover that is
*up*, and the Elder has none.

### The clock is host-owned, and it is the letter hold's clock
`_elders` was `peer_id -> true` and is now `peer_id -> {ends_at}`, written by the
same shape of RPC as `_letter_holds`, ticked by `_tick_elders` beside
`_tick_letter_holds`, and read by `elder_remaining()` under the same contract as
`letter_hold_remaining()`. `is_elder()` stays **the presence of the row** and
never `remaining <= 0`, for the reason D-035 gives about the hold: a client's
countdown can reach zero a round trip before the host's, and a Gub that took its
own robe off on that frame would be a Gub the host still refuses to let throw a
spear.

Three things end a robe and all three run the same teardown — the clock, a void
death, and a disconnect. **Expiry is not a death**: the Gub keeps its letters,
keeps its carried mushrooms and lures, gets its spear back, and goes on standing
where it was. The obvious way to write that teardown is to reuse the death path,
which would take the stock with it, so `tools/match_rules.gd` asserts against it
by name.

### Speed and jump: one multiplier each, at one place each
`elder_speed_multiplier` 1.35 is applied in `Gub.target_speed()` — the single
point walking, sprinting and crouching all come out of. Applying it to
`RUN_SPEED` instead would have produced a sprinting Elder that walks at exactly
everybody else's pace, and the difference between that bug and no bug at all is
invisible from the dial.

`elder_jump_multiplier` 1.25 is applied in `Gub.jump_velocity()`, read by
`_handle_jump` and by the animator's arc scrub. **The dive is deliberately not
boosted**: `DIVE_UP_VELOCITY` is added on top of whatever the body is already
doing, so a boosted jump already carries a boosted dive, and scaling it as well
would multiply the same factor in twice.

**The number on the slider is not the number that matters, and here it is.**
Height goes as the square of launch velocity, so 1.25 is not +25%:

    jump apex          1.69 m -> 2.64 m   (+56%)
    jump + dive apex   2.30 m -> 3.25 m

Measured against Rust, whose walkable surfaces were probed on a 2 m grid with the
scan ceiling temporarily lifted from 3 m to 40 m
(`tools/preview_map.tscn probe`):

    standing on the 1.70 m plane, a Gub's feet reach world   3.39 m
    with a dive                                              4.00 m
    an Elder's                                               4.34 m
    an Elder with a dive                                     4.94 m

**That opens exactly one tier**: surfaces topping out between world 4.0 and
4.9 m — about a dozen cells on the map, all of them two stacked containers —
which an ordinary Gub cannot reach at all and an Elder can reach with a dive.
Nothing above 5 m moves within reach, so the catwalks (7-8 m), the tower
(12-17 m) and the perimeter structures are exactly as unreachable as they were,
and no route out of the yard opens up. **The number is reported rather than
quietly lowered**, which is both the instruction and the right call: two-high
container stacks are a thing a container-yard map obviously has, they are inside
the arena, and standing on one for twenty seconds is the Elder being the Elder.
The dial is in the lobby if a real match says otherwise.

The one thing the boost cannot drag along with it is the animation. The
locomotion blend space's fastest point *is* `RUN_SPEED`, with the `Run` clip's
playback rate baked in when the graph is built, so a boosted Elder runs at
7.3 m/s with its feet planted for 5.4 of it — up to a third of a skate, for
twenty seconds, on the one Gub in the match wearing a robe that already says it
is not ordinary. Rebuilding the blend space to follow a config dial would be a
graph that changes shape mid-match, which is a far worse trade than a visible
skate on a deliberately conspicuous state.

### The drop chance came down to 2% to meet what the robe became
`elder_drop_chance` was 0.05, set for an Elder that was a modest upgrade held
until somebody killed you. What the dial hands out now is twenty seconds during
which a Gub cannot be killed at all, moves a third faster, and fires a one-shot
weapon about once a second. Arriving several times a match, that is not an event;
it is the match. **2% makes it an event**, which is the word D-038 used for what
it was trying to build and did not price for. The user has been told this is
happening and the slider is in the lobby.

### Every number is a lobby dial
`lightning_delay` 0.2 (0-2), `lightning_cooldown` 1.0 (0.2-10, was 5.0 in
0.5-30), `elder_duration` 20 (1-120), `elder_speed_multiplier` 1.35 (1-3),
`elder_jump_multiplier` 1.25 (1-3), and `elder_drop_chance` 0.02. All six are in
`_FIELDS`, all six are clamped in `_clamp_all`, and all six are rows in the
lobby's Match panel — because this is the feature most likely to need tuning the
moment real people meet it, and a rebuild is the wrong unit of tuning.

Two of the readouts are deliberately not the stored number. The speed row reads
"+35%", because that is a sentence about the game where 1.35 is a number about
the code; and the jump row reads **"2.64 m high"**, because the multiplier is on
velocity and a host reading "+25%" would be tuning the wrong quantity.

### The HUD: a countdown, and not on the crosshair
Twenty seconds of god mode with no idea how long is left is the same problem the
letter hold had, and it gets the same answer. `ElderTrack` is `LetterTrack`'s
shape — a `Control` in the same column, one `set_state` push, an early-out when
nothing moved, polled from `HUD._process` because the deadline lives on the host
with no per-frame signal behind it. A bar and the whole seconds, in the robe's
violet, amber for the last three.

**Not on the crosshair** (D-036, which stands). The recharge ring was deleted
rather than fixed a third time, and a countdown put back in its place would be
that decision reversed by the next feature that happened to want a timer.

It **drains**, which is the opposite of what the hold's lamp does. D-036's
"nothing on this HUD drains any more" was about cooldowns — a ring emptying while
you wait to be allowed to act, which is a worse way of saying "not yet". This is
a thing you have and are losing, and a bar that filled as it ran out would be
describing the wrong event.

Nobody else gets a HUD element. The robe is the tell and it is in-world on
purpose; the *clock* is not handed out, because "he has four seconds left" should
be judged from how long that robe has been on screen rather than read off a
display. The ability tile keeps its binary lit/dark. At a 1 s recharge it blinks,
which is fine and honest and is exactly what D-036 kept it binary for.

### What checks it, and the one check that matters
`tools/match_rules.gd` goes from 159 assertions to 195. The Elder scenario is
rewritten around the new rule — a spear does not kill an Elder and costs nobody
a kill or a death, the attacker is still remembered for the void, the robe burns
out on its own, expiry keeps the letters and the stock and hands the spear back,
the void *does* kill, two robes run two independent clocks — and it sets all four
Elder dials to values unlike their defaults, because a check against a multiplier
that happens to be 1.0 passes whether or not anything applies it. The rate
arithmetic is asserted in both directions, including the zero that would
otherwise be a division by it.

**And none of that would have caught the bug worth catching.** `match_rules` has
no world, no geometry and nothing standing fourteen metres away, so all it can
prove is that `report_kill` refuses a kill it was handed. D-039's lesson is that
a rule checked only in a harness that stands its subject up by hand is a rule
nobody has tested — the mushroom passed a green gate for its whole life while
stopping nothing, because its only check asserted that a PNG got written.

So `tools/combat_range.tscn ward` throws a **real spear at a real Elder**. It
drops a robe on top of a dummy and lets the dummy's own body trip the `Pickup`
area, waits on the Elder state rather than on a frame number, throws, and prints
three verdicts:

1. **`ward`** — the Elder survives it.
2. **`expiry`** — the robe then burns out *by itself*, on `_tick_elders` running
   in a real match loop, rather than by the run winding the row's deadline back.
   That is the half `match_rules` structurally cannot claim: it can prove the
   teardown is right once something calls it, and only this can prove something
   does.
3. **`control`** — the *same* throw at the *same* Gub, robe gone, kills it.

The third is the point, and it is `cover`'s argument restated. "Did not die" is
satisfied by a spear that never left the hand, a dummy that was already dead, or
a `report_kill` that never arrived — so without a control on the same geometry
the first verdict proves nothing at all.

Both were run against the code without them first (D-015): with the invincibility
clause removed `ward` fails and the other two still pass; with `_tick_elders`
removed `expiry` fails. The gate goes from 18 checks to 21.

## D-041 — A letter card is a letter: three meshes through the prop pipeline, self-lit, spun on the ground and held upright in the fist
The card the letters mode is about (D-033, D-035) was a `Label3D` glyph on a
billboard, and the comment above the constants gave the honest reason: *there is
no card mesh in `art/generated/`*. That was a placeholder with an expiry date on
it. The user has now supplied `G_LETTER`, `U_LETTER` and `B_LETTER` — Tripo
exports, exactly one metre tall with the origin at the base, ornate gold,
fronting on +Z.

**They go through `decimate_assets.py`, which is only half a decimator.** 6000
triangles and a 512-square texture each. The budget is barely a reduction — they
arrive at 8.5k–10.6k against the props' half a million — and it is deliberately
the *lure's* number rather than the spear's tighter one, because a letter is
read for its shape: a G that has lost the inside of its curve is a C, and no
texture puts that back. What they are really in the target list for is the other
half of that script, the 4096-square base colour coming down to 512 and the
repack into one clean single-buffer `.glb`.

One thing had to be taught: Godot extracts an embedded texture as
`<glb stem>_<image name>`, and these arrive named `G_LETTER_basecolor.jpg`, so
the file landing beside the mesh was `letter_g_G_LETTER_basecolor.jpg.png`. The
script now strips the extension and a leading source stem off the image name
before repacking — a no-op for the three props, and those three were **not**
re-run, their outputs being committed from whatever libraries were current then.

### 0.60 m on the ground, which is bigger than the glyph was
The glyph stood about 0.47 m. A shaded solid has less presence at a given height
than an outlined unshaded one — it is lit like the world instead of shouting
over it — and the other things that fall out of a corpse stand 0.5 to 0.7 m (the
lure 0.49, the robe 0.70), so at the glyph's height a card would have been the
one drop on the map reading as smaller than the rest. The sources being a metre
tall means the height *is* the scale, and it goes on the model rather than on
the pivot `build_card` returns, which both callers place by and would otherwise
multiply into.

### It emits its own albedo, and the operator is the whole trick
The glyph was unshaded and that argument outlives it: a card whose brightness
depends on which side of the island it landed on is a card you can miss. So
every surface gets a **duplicated** material — the imported one is shared by
every instance of the scene, and setting emission on it would light every card
of that letter ever built — with `emission_texture` set to the albedo at 0.7.

The albedo rather than a flat gold, because the ornament is most of what makes
one of these read as a letter at four metres; emit one colour instead and it is
a glyph again with worse edges. And `emission_operator` must be **MULTIPLY**:
the default *adds* the emission colour to the emission texture, so `Color.WHITE`
— which is there to mean "the texture, unaltered" — instead means a flat white
term on top of the gold. It was looked at that way at 0.7, 0.3 and 0.15 and all
three were cream-coloured blobs. The fix was the operator, not the energy.

### On the ground it spins; in the fist it stands still and faces forward
A billboard is already facing you and spinning one costs a matrix for nothing,
which is why the card never turned. A mesh is the other case — it has a back,
and a letter seen from behind is a mirrored letter — so the ground card now
turns at `SPIN_SPEED` like the mushroom and the lure, which is what lets it be
read from whichever side you came at it from.

In the hand it is instead held **upright in the world and square to the Gub's
own facing**, every frame, off `Gub.facing()`; `Basis.looking_at` aims −Z and
these letters front on +Z, so the target is the facing negated. Position is
untouched and still comes from `_card_offset()` through the bone, so the card
rides the one line around that fist already measured clear of the Gub's skin in
every carried clip — its half-height is now 0.21 m, leaving the bottom about
23 cm up through a full run cycle. Two alternatives were rejected. **Aligned to
the shaft** it inherits the wrist, and `Walk` and `Run` lay that over far enough
to tip the letter 60 degrees forward, which reads as dropped rather than held.
**Spun like the ground card** it reads as a trophy, the opposite of what a hold
is.

### What checks it
`tools/combat_range.tscn cards` puts one of each letter on the ground three
metres in front of the player and prints how tall each actually stands, measured
off the mesh's own AABB. It is the one mode in that file reaching past a public
API — straight at `MatchState._spawn_drop` — and the roll is why: a card's
letter is `randi() % 3` and nothing else (D-033), so the existing `letter` mode
photographs whichever letter came up, and a picture of one random letter is not
a picture of the asset. The gate runs it, 21 checks to 22, and it prints a
verdict because a letter at half the height it should be is still,
unmistakably, a letter.

The cards spin from zero at spawn, so a still is a question of when: tick 363 is
one full turn after the drop on tick 20 and catches all three face-on.
`out/cards.png` is that frame and `out/cards_turned.png` the gate's own;
`out/letter_hold.png`, `out/letter_pov.png`, `out/hud_hold.png` and
`out/assets.png` are the card in a fist from the touchline, the same from the
holder's own camera, the letter row unchanged with a letter in the hand, and all
seven generated meshes in a row.

One thing worth writing down rather than fixing: from the holder's **own**
camera the letter is mostly behind the Gub's head. That is not new — the
position is `CARD_ABOVE_FIST`, exactly where the glyph hung — and it is the
right way round anyway, because the hold is an announcement aimed at everybody
else (D-035).

## D-042 — Kopje Crossing: a map written as a table, checked as a jump graph, and coloured on white leaves
The third map, id `safari`, is a 96 m savanna plateau with a rock kopje in the
middle, a hundred and twenty-three climbable platforms around it in eight zones
(the kopje's spiral, a ridge, a termite field, a baobab, a waterhole, a dead
forest, connector runs and eight lone rocks), and eight spawn pads on a 44 m ring
out in the open grass. It is a `StaticMap` in the D-030 sense — one row in
`MapCatalog`, instanced whole by `arena.gd`'s static branch — and nothing in
`arena.gd`, `SceneFlow` or the lobby changed to admit it, which was the point of
that decision and is the first time it has been tested by a map nobody planned
for when it was written.

**There is no `.glb`.** Rust is a bought arena that `static_map.gd` wraps
collision around (D-031). Kopje Crossing is the other kind of hand-made map:
every rock is a MegaKit piece placed from layout tables in
`scripts/world/maps/safari_map.gd`, built in `_ready`, and then handed to the
very same `super()` that sweeps Rust into world-space trimesh collision — 313,400
triangles into 18 shapes in about 300 ms. The alternative was to block the map
out in Blender and export it like Rust, and it was rejected for the reason that
matters most on a parkour map: a gap that plays badly is a number in a table, not
a re-export and a re-import, and the whole map is a hundred kilobytes of script
instead of forty megabytes of mesh.

The price is that every peer builds the map itself, so the map *is* its RNG.
Every random draw comes from one `RandomNumberGenerator` seeded with a constant
and consumed in a fixed order — two peers that disagreed about where a rock is
would disagree about where the floor is. Build order is the other thing to be
careful of and the header says so: everything added before `super()` is
collision and everything after is scenery. Trees go in after, with the same
cylinder trunks `PropScatter` gives them; grass, bushes, pebbles and the water
get no collider at all.

### Reachability is a check, not a feeling
`tools/parkour_report.gd` rebuilds the Gub's jump arc from the constants on `Gub`
(run speed, jump velocity, the dive's forward and up speeds, and the 1.35x fall
multiplier that is still a literal in `_apply_gravity`), builds the whole graph
of which landing can reach which from `SafariMap.platforms`, and walks it from
the ground. It also checks the table against the physics: a ray down onto every
landing has to find the rock within 30 cm of where the table says it is, and a
Gub-sized capsule has to fit on it. It fails the build if anything is
unreachable by hops and leaps alone — the hard "big" dive is allowed as a
shortcut and never as the only way somewhere — if anything strands a player, or
if a landing or a trunk crowds a spawn pad. On this layout the tree is 69% hops
to 31% leaps. It is about six seconds, so it is in the gate.

A render cannot show any of that. That is the same argument as D-015's and the
one that put `preview_map` in the gate for Rust: the failure a picture cannot see
is the one worth a checker.

### The spawn pads passed, and the sightline was looked at rather than asserted
`tools/preview_map.gd` takes a `map=` argument, and pointed at `safari.tscn` it
passes all 60 checks: floor, capsule, facing, separation. Its reported sightline
down each pad's nose is 21.8 m and 26.9 m for pads 2 and 5 and 6.0–7.8 m for the
other six. On Rust that number moved two pads, because six metres was a container
wall. Here the probe's sightline grid reads 5–15 m almost everywhere inside the
ring — the map is a field of rocks you are meant to climb — and the eye-height
renders from every pad show open ground with the first hop in front of it. No
pad moved. A minimum-sightline assertion in `preview_map` was considered and
rejected: the right floor for a container yard and for a rock garden are
different numbers, and one threshold in a shared tool would be wrong for one of
them.

### The canopies are coloured on white leaf cards
The first renders had temperate-green acacias and a dark red baobab. There was no
random hue range to wrap — every canopy has one fixed tint — and the cause was in
the kit: each leaf card ships as a painted `_C` texture, which the meshes use,
and as a white one with the same alpha. `albedo_color` multiplies, and a multiply
can only take channels away. The twisted-tree leaf is painted (169, 23, 23), so
any tint of it is a darker red; the common tree's is (88, 123, 0), so any tint of
it is a green. The bushes share the twisted tree's card and were forty red dots.

So the three leaf materials load the white cards and take their whole colour from
`ACACIA_TINT`, `BAOBAB_TINT` and `BUSH_TINT`. Two alternatives were rejected:
tints above 1.0, which brighten without moving the hue (a red canopy at 1.4 is
pink), and recolouring the kit's PNGs, which would recolour every other user of
the kit, the island included.

### What checks it
Four lines in the gate, 22 checks to 26: a whole playthrough on `safari` with an
`also` that it was Kopje Crossing that got built, `preview_map` on its pads, and
`parkour_report`. Renders are not committed; `out/safari_top.png`,
`out/safari_side.png` and `out/safari_pad0.png` … `out/safari_pad7.png` come from
`preview_map` with `map=res://scenes/world/maps/safari.tscn` and the `top`,
`side` and `pad<n>` views.

One trap worth writing down: a new `class_name` is invisible to a script run with
`--script` until the class cache is rebuilt, so `parkour_report` fails to parse on
`SafariMap` straight after a checkout until `--import` has run once. The gate
imports first; running the tool by hand is where it bites.

Like Rust (STATUS, "what is left"), nobody has played a match on it. Whether
eight Gubs on a 96 m plateau find each other, whether a 9.5 m summit with dives
to both saddles is a king-of-the-hill or a sniper's nest, and whether 3,100 grass
instances hide a crouched Gub more than they should are questions for a person.

## D-043 — A snapshot from a life that is over is not about this Gub
A player, after a match: *"there is a bug where you spawn with either an item or
the elder randomly, it seems like after you die you respawn first where you died
and picked it up from there or something?"* That breaks two rules at once — D-032
(everything carried is lost on death) and D-038 (a robe that ends is consumed,
never handed on) — and the player's guess about the mechanism was exactly right.

### What was happening
Movement is client-authoritative (D-004): the owner of a Gub publishes
`sync_position` every tick, and every other copy of that Gub eases toward it in
`Gub._follow_network`, snapping straight there when it is more than 6 m off. A
dead Gub keeps publishing — it lies still and says so, every tick.

When the respawn delay runs out, the **host** revives its own copy of the dead
Gub at the pad (`_respawn` → `_do_respawn` → `revive_at`), marks it alive, and
sends `_do_respawn` to everybody reliably. The owner's client is still dead until
that message arrives, and every snapshot it sends in the meantime says *I am
lying on my corpse*. The host's copy — alive now, and more than 6 m from the
corpse — snapped straight back onto it. The corpse is where `_drop_loot` puts
the drop. The host's `Pickup` saw a living Gub walk into it, `claim_pickup`
checked `is_alive` and got yes, and the stock or the robe went to the Gub whose
death had just produced it. "Randomly" was the loot roll: a mushroom or a lure
nearly every time, a robe one time in fifty.

**Only a Gub owned by a client could do this.** The host's own Gub has no remote
owner to contradict it and was never affected, and no offline testbed could see
it, because an `OfflineMultiplayerPeer` has no round trip.

### Checking the guess before fixing it
The planning pass named the mechanism from the code alone, and it was right in
every particular but one, which only running it showed.

`tools/net_loopback.gd` grew a stage that kills the client with the robe forced
and a mushroom dropped beside it, then logs the host's copy every tick. Over
127.0.0.1 it **never reproduces**: the dead client's snapshots do arrive on every
tick, but the first one after the revive already carries the pad, because a
loopback round trip is shorter than a physics tick. The stage passed against the
bug.

The first reproduction offline also passed, and for the reason that is the one
particular the reading missed. Replaying the dead client's snapshot on *every*
tick after the revive puts the body back on the corpse before the physics server
has ever stepped it at the pad — so as far as the `Pickup` is concerned it never
left, never came back, and no `body_entered` fires. The bug needs **one physics
step at the pad before the stale snapshot lands**, which is exactly what real
packets give: they do not arrive once per physics tick, and a 100–200 ms tunnel
round trip is six to twelve ticks of them. With the replay on every other tick,
`combat_range respawn` failed against the old code with the dummy holding a
mushroom and wearing the robe, and all four drops taken.

### The fix: every snapshot says which life it is from
`Gub.sync_life` is replicated **ALWAYS, in the same synchronizer packet as
`sync_position`**, and `Gub.life` is which life this copy is in.
`_follow_network` does nothing — no move, zero velocity — while the two differ.

* A snapshot from the life before is a corpse arriving after the revive: refused.
  That is the bug.
* A snapshot from the life after is the owner arriving before its `_do_respawn`
  has: also refused, and the copy stays where it is, still hidden, for one more
  round trip — which is what it looks like on every other screen anyway.

**`life` is the host's number, never a local count.** `MatchState._life_of` is
the Gub's deaths so far, passed through `_create_gub` and `_do_respawn` to
`revive_at` on every peer. The obvious alternative — `revive_at` increments a
counter — gives the same numbers in a clean match and different ones the first
time anything revives a Gub an extra time, and the testbeds do exactly that. A
remote Gub whose two ends disagree about its life stands frozen for the rest of
the match, so the number has to be one nobody can count differently. Deaths are
already the host's, only ever go up, and every respawn follows exactly one.

The counter rides in the snapshot rather than on its own channel because the
pair is judged together: a life number arriving on a reliable ON_CHANGE schedule
would vouch for positions it was never sent with.

`_respawn` also calls `_end_elder` before the respawn goes out. Nothing that can
kill an Elder leaves the robe on today — since D-040 only the void can, and
`report_kill` ends the robe there — but a Gub coming back from a death is the one
Gub that certainly should not be wearing one, and saying so costs nothing when
there is nothing to end. `GubCombat.reset` already zeroed stock on every peer;
the host path was checked and was never the problem.

### Rejected: taking the dead body out of the physics
The suggested second half of the fix was to take a dead Gub off the player layer
until `revive_at` — a dead Gub with no body the world can touch. It is a good
rule on its own merits: an invisible capsule stands where a Gub fell for the
length of a respawn delay, and `_lightning_hit` already carries a loop to step
round it. It was built, and it made the bug **worse**.

Putting `collision_layer` back at the pad, in either order relative to the move,
made the physics engine (4.7's default) report `body_entered` for every `Pickup`
at the corpse on the next step — with the body 9 m away at the pad — so the
*host's own* Gub started collecting its loot too. Disabling the collision shape
instead did the same. It only came right with the body restored two physics
frames after the move, from a coroutine: a fix that works because of how many
steps the physics server takes to notice a teleport is a clock nobody re-reads,
which is D-039's lesson, and it is not going in to buy what the life number
already fixes on its own. The corpse capsule and the loop in `_lightning_hit`
stay as they were. If the dead body is ever taken out of the world, it has to be
done somewhere the teleport cannot race it — and `combat_range respawn` is what
that change has to pass, because it goes red on exactly this.

### What checks it
**`tools/combat_range.tscn respawn`**, in the gate (26 checks to 27). The player
dies holding a mushroom and a dummy dies as the Elder holding one too, both
killed **off their spawn pads**: a Gub that dies on a pad is handed the same pad
back, never leaves its loot's catch volume and so never enters it, and passes
whatever the code does. The loopback stage fell into exactly that on its first
run, so the mode requires both revivals to land more than 6 m from their
corpses. Loot lies on both corpses. The dummy is a remote Gub, so the mode plays
its client: dead, it publishes the corpse; revived, it goes on publishing the
corpse in the old life for 12 ticks (200 ms), a snapshot every other tick. A
second after both respawns nobody may hold a mushroom or a lure, be the Elder,
wear a robe, or have taken any of the four drops.

**`tools/net_loopback.gd` stage 9/10** is the other side. It cannot open the
window, and says so in its header, but it checks what the fix puts at risk: that
over a real socket the host's copy of a respawned client follows it to its pad in
the same life, and that nothing was picked up. `net_test.sh` is now 102 + 32
assertions over ten stages; the one engine error at match start is the same one
it has always reported.

## D-044 — A rematch has to find the players who already went home
A player: *"rematch only works 50% of the time / takes a while"*. Both halves
were one bug, and it was not a race.

A client's results screen has exactly one button that does anything: BACK TO
LOBBY (D-021 gave REMATCH to the host alone). Pressing it walks that client to
the lobby scene and leaves it connected, which is correct. But the rematch
broadcast, `Net.rematch_requested`, was heard by one thing only — the HUD, which
lives in the arena that client has just left. The lobby listened for a match
*start* and not for a rematch. So every client that had pressed the button stayed
in the lobby; the host built its arena and waited for a ready report that could
never come, sat out the whole of `ARENA_READY_TIMEOUT` (25 s), and started the
match without them. Whether a rematch "worked" depended on whether anyone had
clicked the only button they had, which from the host's chair looks like a coin
flip with a long delay on the bad side. The lobby now treats a rematch as a match
start.

**Measured, not read.** `tools/net_loopback.gd` stage 10 runs a match to a
result and presses the host's real REMATCH button ten times in a row, with the
client pressing its own BACK TO LOBBY first on every other round, while the host
logs a timestamp for the reset, each `register_arena`, each ready report and the
warmup. Against the old lobby, round 1 (client still on the results screen) took
3.3 s and round 2 stalled: the host registered its arena, logged its own ready
report, and then nothing — no report from the client, no warmup, for the whole
20 s the round allows. With the fix all ten rounds take 2.3-2.4 s, from the lobby
or not, and with the lobby line removed again round 2 stalls again.

### The other thing a rematch was doing: freeing Gubs somebody was still sending
With the stall gone, the run still failed on the engine log, and this is the
second fix. A `MultiplayerSynchronizer` keeps publishing to a peer that has
already freed its copy of the node, and the receiver logs *Node not found:
"Arena/Players/Gub_1/Sync"* and *Failed to get cached node* for every packet.
Freeing happens at different moments on different machines — the host on its own
REMATCH, a client when the broadcast arrives, a client in the lobby whenever it
pressed the button — so every rematch left a burst on the host, and a client in
the lobby logged about sixty pairs a second for as long as the host sat on the
results screen. Harmless to play, and exactly the sort of noise that hides the
next real error. `MatchState._sync_finish` now turns every Gub's synchronizer
private on every peer when the match ends (`_stop_publishing`), while every copy
still exists, so nothing is sending by the time anything is freed. The results
screen covers the arena, and a rematch builds new Gubs that start public. Without
it the same run logs about three hundred of these.

**The "engine error at match start" that `net_test.sh` had reported since D-022
was the same error, from the harness.** It was never at match start: the client
half's "leave" called `MatchState.reset()` a frame *before* `Net.leave_lobby`,
the host's Gub was still publishing, and one packet landed on the freed copy.
The harness now leaves first and then tidies up, which is the order the pause
menu's Leave takes. `net_test.sh` exits zero for the first time.

### Defensive, not the cause
`reset()` left `_players_root` and `_spawn_points` pointing into the arena about
to be freed, so a `_try_begin_warmup` landing between a reset and the next
`register_arena` would have spawned every Gub into the dying scene and set the
phase to WARMUP, and the new arena's own call would then have returned early.
Nothing reached that window in any of the traced rounds — every client report
came after the host's own register, because no client can have a new arena
before the host has sent the rematch that starts building one — but it costs two
lines to close: `reset` forgets both, and `_try_begin_warmup` and `_create_gub`
require a players root that is valid and inside the tree.

Also looked at and not the cause: `SceneFlow.go_to` keeping only the latest
pending request (a client pressing BACK TO LOBBY while a rematch is in flight
ends up in the arena, which is where it should be); a rematch racing the result
broadcast (both are reliable, on one channel, in order); ready reports sent
before the host resets (the host resets synchronously before its broadcast
leaves, so none can arrive first).

### In the gate now
D-022 kept the loopback test out of `smoke_test.sh` because binding UDP 27015
could raise a firewall dialog, and a gate that can stop for a dialog is not a
gate. That is still right, and the answer was to stop binding like a server:
`Net.bind_ip` (default `"*"`) lets the harness listen on 127.0.0.1 alone, which
no firewall asks about, and it picks a random port in 27100-27899 with up to
eight tries, so a real game hosted on this machine or a port Windows has
reserved costs a retry rather than a red gate. The whole of `net_test.sh` runs
as one check, "two processes, ten rematches" (27 checks to 28), and adds about
forty seconds, nearly all of it island builds. Stage 10 sets the warmup to zero
for its rounds — stages 6 and 7 already walk a real one — and stays on the
Hollow, which was the fastest to rematch here: slowest round 3.3 s against
Kopje Crossing's 3.4 s and Rust's 4.0 s, all with the one-second warmup still
in, and 2.4 s without it.

What loopback still cannot say: a client that is slow to *leave* the results
screen over a real link, or a host that presses REMATCH while a client's own
BACK TO LOBBY transition is mid-fade. The second is handled by `SceneFlow`'s
pending request and was reasoned about, not run.

## D-045 — The camera is swept as a sphere along the path it is actually on
A player: *"too frequently the camera is inside meshes and stuff when there are
meshes behind the character"*.

**What the old rig did.** A `SpringArm3D` with no `shape`, so it cast a single
ray down the middle of the boom — and then the `Camera3D` under it was moved
0.62 m sideways (`_camera.position.x = _shoulder`), off the line that had been
tested. A wall beside or behind the shoulder was never looked for. The arm also
does its cast in its own physics step while the view is turned in `_process`, so
a camera swung into a wall was placed from a direction that was already stale.

**Measured before fixing.** `tools/camera_range.tscn` (new) walks the local Gub
through seven legs — a wall on each shoulder walked along, a corner, under a
canopy and at its edge, a wall at its back with the view swung and flicked
through it, and a low tunnel — and asks every one of 1,700 frames, after the rig
has placed its camera, whether the lens is inside the scenery: a point query at
the camera, a 0.1 m sphere there (the near plane reaches about 0.09 m), and a ray
from the Gub's eye to the camera (is it on the far side of a wall). Against the
old rig 942 of 1,700 frames failed, and every leg failed: wall on the right
86/200, on the left 24/200, corner 181/260, under the canopy 181/260, canopy edge
182/260, back to a wall 98/260 (as much as 2.91 m behind a surface), tunnel
190/260. With the new rig, 0 of 1,700.

**What it does now** (`GubCamera._place_camera`). Two sphere sweeps, radius
0.26 m, on world and camera-blocker layers only (`1 | 64`, as before — never
players, projectiles or pickups): pivot out to the shoulder, then from wherever
the shoulder got to back along the boom. Each is held a further 0.05 m off its
first hit. So the shoulder offset cannot carry the lens through a wall either,
and a ceiling or a canopy is the same sweep as a wall — looking down lifts the
boom into it. It runs every frame after the view has turned. It pulls in to the
hit at once and eases back out at `RETURN_RATE` 5 /s (exponential, about 0.46 s
to 90 %), never further than that frame's sweep says is clear, so the ease cannot
cross a surface. If the sphere does not fit even at the start (a head right under
a low ceiling), that segment falls back to a ray rather than collapsing the
camera into the Gub. The boom and shoulder lengths themselves did not change; the
`SpringArm3D` node became a plain `Boom`.

**The aim does not move** (D-025). `aim_ray` used to be projected from the
`Camera3D`; it is now built from where the camera *would* be with nothing in the
way — the rig's pivot, yaw and pitch, the full boom and shoulder, plus shake's
offset because shake moves the crosshair too. It carries `clear_of`, the boom
length, and `GubCombat._aim_point` starts its hit test that far along: anything
nearer is behind the thrower. That second half is not optional. Without it, the
wall that pushed the camera forward is the first thing on the unobstructed ray,
and a Gub with its back to a wall would aim at the wall. It was also the old
rig's behaviour by accident, since its lens was usually past that wall. The
`MIN_AIM_DISTANCE` clamp, which only ever produced points behind the Gub from a
camera 3.6 m back, no longer triggers. `look_at_point` solves from the same
origin, so the testbeds that use it aim exactly as before.

When the shoulder is squeezed in, the lens is off the aim ray, and a crosshair at
the centre of the screen would sit up to a shoulder's width to one side of where
the spear goes at every range. So in that case only, the lens is turned in to
meet the aim ray where the aim ray meets the world (up to 60 m). The reticle stays
on the thing being aimed at; the spear is unaffected either way.

The range checks this too: every frame, `GubCombat._aim_point` has to be within
1 cm of the point worked out independently from the unobstructed camera. 0 of
1,700 frames off (worst 3 mm, float noise at 220 m). With `aim_ray` taken from the
pulled-in lens instead, 1,030 of 1,700 frames are off, by up to 212 m — which is
also why the check is worth having: it fails loudly on exactly the regression it
exists for.

In the gate as "camera stays out of the scenery", `clip PASS` and `aim PASS`,
headless with `--fixed-fps 60`, about two seconds. 28 checks to 30.

### Rejected
- **Giving the `SpringArm3D` a `SphereShape3D`.** It still sweeps one line, the
  middle of the boom, and the camera still is not on it; and it still updates on
  its own physics step behind the view.
- **Moving the shoulder offset onto the rig so the arm's line is the camera's.**
  Then a wall beside the Gub is inside the arm's start and the whole boom
  collapses, instead of just the shoulder.
- **Easing in as well as out.** Every frame of easing in is a frame drawn from
  inside the wall, which is the complaint.
- **Aiming from the pulled-in lens with the old code path.** Where the pull-in is
  straight down the boom the line is the same, but the shoulder squeeze moves the
  line, and the range measured exactly that.
- **A shorter boom.** Not asked for; this is collision only.

### What this does not cover
- The range is boxes. Rust and Kopje Crossing are trimeshes; a sphere sweep treats
  those the same, but a thin single-sided face is only as good as the map's
  collision.
- Aiming (the 2.4 m boom and 0.48 m shoulder) is swept by the same code but is not
  one of the legs.
- In a tight space the lens can end up very close to the head: 0.23 m from the
  pivot in the 2.6 m-wide, 2.2 m-high tunnel while looking down. It is outside the
  scenery, but it is inside the Gub. The cave (PLAN 5.2) will want either more
  headroom than that or the local Gub faded when the camera is that close.

## D-046 — In Teams, the Gub's body is recoloured to its team, and the Elder's robe is not
The user: *"For teams, the gubs change color to the hue, should be able to just
tint the mesh."* The team colours already existed, in `Nameplate.TEAM_COLOURS`,
shared through `UIPalette.team_colour` by the plate, the lobby stripe, the
scoreboard, the kill feed and chat. The body now uses the same eight.

**Only the body.** The Elder's robe (D-037, D-038) is a second skinned mesh on the
same skeleton, and it keeps its purple. The user chose this: "that is an Elder"
and "that is my team" are two separate reads, and a robe in the team colour
would merge them. A Gub on Team 1 wearing the robe is a blue Gub in a purple robe.

**How: a recolour shader, not a multiply.** `gub.glb` has one mesh and one
`StandardMaterial3D`, textured with a saturated yellow (`gub_basecolor.jpg`) that
also contains the eye whites, the pupils and some dark patches. Its emission is
the same texture times a grey. Multiplying `albedo_color` by a team colour can't
produce most of the palette: yellow times blue is olive, and yellow times violet
is brown. `resources/shaders/gub_team_tint.gdshader` finds the yellow skin by hue
(about 15-95 degrees) and saturation, replaces its colour with the team colour at
the same brightness (`team_colour * value / 0.9`), and leaves everything else
alone. So the eyes stay white, and the painted shading and the brown stripes
still show. Roughness, specular and emission are copied from the imported
material, so a tinted Gub is lit like a yellow one. `reference_value` 0.72 was
tried first. Every team came out a step paler than the yellow Gub next to it. At
0.9 the brightness matches.

**Where.** `Gub.set_team_tint(team)` makes one `ShaderMaterial` per Gub the
first time it is needed, sets `team_colour`, and applies it with
`set_surface_override_material` on `body_mesh`. `body_mesh` is found in `_ready`
before the spear or any robe is attached. `TEAM_NONE` clears the override and
puts the imported material back. It is called from `MatchState._create_gub`
with the same team the nameplate gets, and from `GubBackdrop._apply_slot`. Every
lobby roster change goes through `_apply_slot`, so a player switching team
repaints their Gub in the ring.

**Free-for-all is the imported yellow.** The nameplate is neutral there because
everyone is a threat, and the body follows the plate. Nothing else in the UI has
a per-player colour to stay consistent with, so there was nothing to invent.
Team 4's amber ends up close to that yellow, but the two never share a match.

**The corpse.** `GubRagdoll._adopt` used to copy `mesh.surface_get_material`,
which is the imported yellow, so a blue Gub would have died yellow. It now takes
`get_active_material` from the live mesh with the same name. That also leaves the
robe out, because the corpse is a fresh `gub.glb` with no "Elder" in it. The
shader material is shared rather than duplicated. The fade is
`GeometryInstance3D.transparency`, which moves the draw to the transparent pass
by itself, and the shader has `depth_draw_always` built in. So nothing needs to
change when the fade starts, which is what the `StandardMaterial3D` copies still
do. Rendered mid-fade, a teal corpse dissolves the same way the yellow one does.

**Checked.** `tools/team_tint.tscn`, headless, in the gate as "team colours on the
body". Every assertion reads `get_active_material`: eight Gubs each exactly in
their nameplate colour; a Gub moved from a team to `TEAM_NONE` is back on the
imported material; the robe's active material is its own, while the body under it
stays tinted; a corpse of a tinted Gub is still tinted and a corpse of a yellow
one is still a `StandardMaterial3D`; and `GubBackdrop.set_roster` repaints a Gub
whose team changed. With the old ragdoll `corpse` fails, and with the old backdrop
`lobby` fails. The same scene through `snapshot.gd` renders the lineup under
`studio`, `dusk` (Whisperbloom's env) or `noon` (Rust's). 29 checks to 33.

### Rejected
- **`albedo_color` multiply.** Olive blues and brown violets, as above.
- **Per-team textures, generated or authored.** Eight 1024² images for something a
  uniform can do. Generating them at match start is a second of GDScript pixel
  loops.
- **Tinting the robe too, or a team trim on it.** The user's call. See above.
- **A per-player colour in free-for-all.** Nothing else in the UI uses one, and
  the body should say what the plate says.
- **Saturating the team colours for the body.** They are pastel because they are
  UI colours, and a body in a different shade from its own plate is two colours
  for one team.

### What this does not cover
- `MatchState._create_gub`'s call is not asserted by the check. It is one line
  beside the plate's and reads the same `shown_team`, but only the backdrop path
  is exercised.
- The hue window is fitted to this texture. A re-bake of `gub_basecolor.jpg` in a
  different base colour needs the window in the shader moved with it.

## D-047 — A teammate's name is drawn through walls and never fades, an enemy's is not, and the HUD says which team you are on
The user: *"it should be obvious what team you are on and who your teammates are,
teammates names should be clearer and always there".* D-046 painted the body; this
is the other two reads.

**Through walls is teammates only, by design.** `Nameplate`'s own header says a
plate visible through a boulder is a wallhack, and for an enemy that is still
true and still enforced: an enemy's plate is depth-tested and fades out between
20 and 28 m exactly as before. A teammate's plate is the deliberate exception.
Where your own side is carries no information an opponent could be denied, it
does not change during a match, and a teammate you cannot find is one you cannot
help. So `Nameplate.set_ally(true)` turns off the depth test, skips the fade, and
holds the plate's on-screen height from 11 m out (the pixel size grows with
distance past that), so a teammate across the island is still a readable name
rather than a four-pixel smear. Nothing about it can reach a plate on another
team, and nothing in free-for-all is ever an ally.

**Distinct from an enemy's plate, not only by colour.** 20% larger up close, a
thicker outline, and a thin bar in the team colour under the name (also drawn
through the scenery). Colour already differs from every enemy's, but two team
colours can sit close and not every player separates them; size and the bar do
not depend on hue.

**Per viewer.** "Teammate" means the same team as the player on *this* machine.
`MatchState.is_teammate(peer_id)` answers it from the roster (`Net.player_team`
of both), not from the local Gub, so a teammate who spawns before this player's
own body exists is recognised. `_create_gub` calls it beside `set_team`. Teams do
not change during a match (a pick only moves in the lobby, and the next match
spawns every Gub again), so the answer at spawn holds. Your own plate stays
hidden as before. The lobby backdrop never calls `set_ally`, so lobby plates are
unchanged. The Elder and a letter carrier get nothing new: the plate knows
nothing about either, and a teammate wearing the robe is still a teammate.

**The HUD.** A `TEAM n` chip under the score line, in the team's colour with a
border of it, shown in Teams only. The score line already shows every team's
colour, which is why it cannot answer the question: two coloured numbers do not
say which one is yours. "Team n" is the name the lobby buttons and the results
headline already use.

**Checked.** `tools/team_plates.tscn`, headless, in the gate as "teammate names
through walls" and "free-for-all names unchanged". The real spawn path, with a
wall between the local Gub's camera and a teammate and an enemy about 43 m out,
and one of each 9 m out in the open. `wall` proves by ray that the wall is in the
line of sight; `ally` wants the far teammate's plate not depth-tested, visible,
at full alpha and in its colour, with its bar up; `enemy` wants both enemies
depth-tested, barless, and faded exactly when past `FADE_END`; `hud` wants the
chip up saying `TEAM 1` in team 1's colour. The `ffa` run wants no allies, the
old fade, the neutral colour, the old pixel size and no chip. With
`set_ally(false)` in `_create_gub`, `ally` fails; with `set_ally(true)`, `enemy`
and `ffa` fail. Through `snapshot.gd` the same scene renders the Gub's own view:
the far teammate's name over the wall, the far enemy's absent. 33 checks to 38.

### Rejected
- **A wider fade for teammates instead of none.** Still "sometimes there", which
  is what the user asked to be rid of.
- **`fixed_size` for teammates.** The header explains why a constant screen size
  broke the crowd up close. Holding the size only past 11 m keeps perspective
  where it does the most work.
- **A symbol glyph (a diamond, an arrow) before the name.** The Label3D font is
  not guaranteed to carry one; a quad cannot go missing.
- **Showing enemy names through walls "briefly" or at short range.** That is the
  wallhack with a timer on it.

## D-048 — Random teams are dealt at Start, round-robin over a shuffle, and a rematch keeps them
The user: *"random teams".* Asked whether a rematch should deal again, the user
said no: teams stay as dealt until everyone is back in the lobby.

**A config field, a lobby toggle, and one place that deals.**
`MatchConfig.random_teams` is in `_FIELDS`, so it reaches every client with the
rest of the config. It is a bool, so `apply_dict`'s type check is its whole
validation. The settings panel shows it under the team count, and hides it
outside Teams with the other team-only rows. `Net.request_match_start` is the only
caller of `_deal_random_teams`. It deals, broadcasts the roster, and only then
sends `_begin_match`. Both are reliable RPCs on the default channel, so ENet
delivers them in order, and every client has its team before it loads the arena
that tints and labels by it (D-046, D-047). `request_rematch` is a different
function and deals nothing. Returning to the lobby deals nothing either. The next
Start from the lobby deals again.

**Dealing is a pure static function, `Net.deal_teams(ids, team_count)`.** It
shuffles a copy and assigns index mod team count. After k Gubs the sizes are the
floor and ceiling of k / team_count, so they never differ by more than one. More
teams than Gubs leaves the tail empty, which a hand-picked lobby may already
start with. Harnesses that write stand-in roster rows never call Start, so they
never deal.

**The lobby.** Under random teams `can_start_match` asks only for two or more
Gubs, because the current roster teams are about to be overwritten. The team
picker becomes one line, "Random — n teams dealt when the match starts". The
host refuses a `_request_team` sent anyway. The row stripes and the backdrop Gubs
go neutral, because otherwise they would show the default or last match's teams,
a line-up nobody will play. In the match every Gub is tinted, plated and
chip-labelled from the dealt roster, unchanged from D-046 and D-047.

**Checked.** `tools/match_rules.gd`, scenario "random teams", already in the gate
as "match rules" (so the gate count stays 38). It runs 25 deals each of 7 into 2,
5 into 3, 8 into 8, 2 into 5, 1 into 2 and 8 into 3. Every Gub must be dealt,
onto a real team, with sizes within one. Then through the real host path in an
offline session: seven Gubs all on team 0 may start; a team pick is refused; Start
deals 4 and 3. Five rematches and a return to the lobby must keep that line-up.
A new Start must deal a different one within twenty tries (a repeat is 1/35 each).
With the toggle off, Start must leave hand-picked teams alone. The config
round-trip asserts `random_teams` survives `to_dict`/`apply_dict` and is in the
key list. `net_test.sh` passes unchanged. It runs free-for-all, so it does not
cover the ordering across a real socket. That rests on ENet's channel ordering.

### Rejected
- **Dealing when the toggle is flipped.** Players who join afterwards unbalance
  it, and the lobby would show teams that change again at Start anyway.
- **Each Gub to the currently smallest team, in shuffled order.** It gives the
  same sizes, but it is a loop with a tie-break to get wrong. Round-robin gives
  the balance by construction.
- **Dealing on rematch too.** The user's call.
- **Balancing by skill or past score.** Nothing records skill, and "random" was
  the request.

## D-049 — In Teams, letters pool across the team, and a leaver's letters stay with it
The user, after playing: *"for gub game in team, the gub spelling scoring should
be per team".* Asked what per team meant, the user said pooled means pooled: any
teammates' letters combine, so three teammates holding G, U and B between them
win. Asked about a player who leaves mid-match, the user said their letters stay
counted for the team.

**This reverses a rule.** D-033 said letters are per player even in Teams, and
`MatchState._check_win` carried a comment saying a team whose members hold G, U
and B between them "has not won anything: the card game's ending is one hand
with all three in it". That rule is gone for Teams. The comment was not deleted.
It was rewritten to say what it used to claim, that D-049 reverses it, and why.
The reason is the playtest note. A team that had spelled the word between its
members and was told to keep going read as the game being wrong, not as a
subtle rule. The old rule's worry was a big team beating a small one on
arithmetic. That worry is real, but it belongs to the lobby (random teams are
dealt even, D-048), not to letters that refuse to add up.

**What changed.**
- `MatchState._team_letters` is a team → three-bit mask, on every peer. In
  Teams, `_check_win` under LETTERS scans those masks and ends the match when one
  is complete. Free-for-all still scans players, exactly as before.
- **Duplicates are judged against the team.** `award_letter` and
  `_begin_letter_hold` both test `scoring_letters(peer)`, which is the team mask
  in Teams and the player's own otherwise. A G your teammate already banked is
  consumed on touch in your hands, starts no hold, and grants nothing: D-033's
  "duplicates are wasted", per team.
- **A teammate's hold for the letter just banked ends.** Two teammates standing
  still for U: the first to finish banks it, and the other's hold is ended with
  the card spent, not re-dropped. Anything else is ten seconds of standing still
  for a letter the team already has, the thing `_begin_letter_hold` exists to
  refuse. The other team's hold for the same letter is untouched.
- **The ten-second hold and "death returns the card" (D-035) are unchanged.**
  Only what a banked letter counts toward changed.
- **Each player's row still keeps the letters they personally banked.** The
  scoreboard and results show both: the team's word, and who carried it.

**The leaver rule is why the mask is stored, not derived.** `_on_player_left`
erases the leaver's `stats` row. A team mask OR-ed together from rows would lose
the leaver's letters the moment they disconnected. That punishes a team for a
teammate's connection, and takes a letter out of a match that may be a hundred
deaths from replacing it. So `_team_letters` is written only by `award_letter`
(through `_sync_letters`) and cleared only by `reset` and a fresh warmup, never
by a departure. A hold running when somebody leaves is still treated as a death
(D-035): the card is re-dropped, not banked.

**Replication.** `_sync_letters` now carries `(peer, mask, team, team_mask)`, so
the player's letters and the team's pooled mask arrive in one reliable message
and no peer can show one without the other. `reset` runs on every peer on a
rematch and on the way back to the lobby, so the mask starts empty each match.
`_finish` adds `team_letters` to the summary under Teams + letters.

**UI.**
- HUD lamps show `scoring_letters` for the local player: the team's pooled mask
  in Teams, labelled "TEAM LETTERS" under the lamps when no hold is using that
  line. The HUD now refreshes the lamps on any peer's `letters_changed`, because
  a teammate's letter lights your lamps.
- Scoreboard: each team header carries the pooled letters in the letters column.
  Under letters, teams sort by pooled count, then kills.
- Results: under Teams + letters, a row per team (colour, kills, pooled letters)
  sits above the player rows. The headline crowns the team with the most pooled
  letters, kills breaking ties. Before this it crowned the team with the most
  kills even in a letters match. The subtitle reads "The team spelled it between
  them."

**Checked.** `tools/match_rules.gd`, already in the gate as "match rules" (so the
gate count stays 38), three scenarios. "teams, letters pool": G and U on team 0
with B on team 1 does not end the match; a teammate's G is wasted and the other
team can still take one; team 0 banking B ends it with nobody holding all three
alone; the summary carries both masks. "teams, a leaver's letters stay with the
team": a player banks G and U and leaves; the mask survives, G is still a
duplicate, B wins, and `reset` clears it. "teams, a hold for a letter the team
already has": a team duplicate card starts no hold; two teammates holding U, the
first to finish ends the other's hold while an enemy's U hold carries on. The
free-for-all letters scenarios are untouched and pass. Renders:
`tools/hud_range.gd` modes `hud_letters_teams`, `scoreboard_letters_teams`,
`results_letters_teams`.

Writing that third scenario found a bug: `_tick_letter_holds` iterates a copy of
the hold keys, and banking a letter can now end a *different* row later in that
copy. It skips rows that are gone.

### Rejected
- **Deriving the team mask from `stats` rows.** Loses a leaver's letters, which
  the user ruled out.
- **Pooling across teams, or in free-for-all.** Nobody asked, and free-for-all
  has no team to pool into.
- **Letting a teammate's duplicate hold run to the end.** Ten seconds without a
  spear for nothing.
- **Re-dropping that ended hold's card for the other team.** A duplicate is
  consumed on touch (D-033); holding it is having touched it.
- **Replacing per-player rows with the team mask.** It would erase who banked
  what, which is the one interesting thing on a teammate's row.

## D-050 — A letter picked up is told to everyone: a line in the feed, and a gold card over the carrier that shows through walls
The user: *"some kind of notification when someone picks up a letter, maybe it
should also show people with letters through walls / on the map?"* Asked, the
user chose both halves for everyone — both teams, and every player in a
free-for-all — and a marker only, no minimap.

**This amends D-035 and D-036.** D-035 made the lit card in a carrier's fist the
tell, and D-036 said nobody else's hold gets anything on your screen, so that
the announcement was made "to the clearing rather than to a corner of your
screen". That only reaches the players standing in the clearing. At an 8% drop
rate a letter is the rarest event in the match, and a hold that ended out of
sight read as a letter appearing from nowhere. A ten-second hold is only a fight
if the people who could contest it know it is happening, and the fist told the
one or two players already looking. The card in the fist, its light, the hold
itself, and the lamps and seconds being yours alone are all unchanged.

**The feed.** `KillFeed.add_event(segments)` builds a non-kill row from
segments: a peer id (their name, coloured the way a kill row colours it), a word
in the verb colour, or `[text, colour]`. `add_kill` is now one call to it, so
there is one row builder and one eviction loop, and the
`remove_child`-before-`queue_free` fix that stopped the sixth row hanging the
game still covers every row. Two rows use it: **"Name picked up G"** when a card
starts a hold, and **"Name banked G"** when a letter is awarded. Banking is
announced because it is the moment the lamps change for somebody. With a hold
time of zero there is no hold, and "banked" is the only line a card produces.

**Driven by events, not by diffing state.** `MatchState.letter_picked_up` fires
from `_do_begin_hold` and `letter_banked` from `_sync_letters`. Both run on
every peer from reliable RPCs, so clients announce exactly what the host did.
They carry the letter, unlike `letter_hold_changed`, because they report things
that happened rather than copying state. `_sync_letters` now carries the letter
too, so no client has to work it out from its own old mask, which can be a score
push behind. **A duplicate wasted on touch announces nothing**, because it never
reaches `_do_begin_hold` (D-033, D-049). Neither does a card walked over
mid-hold. A hold lost to death is not announced: the kill row already says the
carrier died.

**The marker.** `CarrierMarker` is built on every Gub at the nameplate's anchor:
a gold card with a dark border and the letter in dark ink. It has no depth test,
so it is drawn through scenery. Past 11 m it holds its on-screen size, the same
distance a teammate's plate does, so the gap between the two stays constant as
both grow. It sits above the plate, clear of even a teammate's enlarged one. It
is deliberately unlike a nameplate (D-047): a filled shape with one glyph and no
name, where a plate is outlined lettering. "Who is my teammate" and "who has a
letter" are both drawn through walls, and they must not read as one thing.
`GubCombat` drives it from `letter_hold_changed`, beside the hand and off the
same row, so the card in the fist and the card over the head cannot disagree.
Every end of a hold — banked, killed, disconnected, a teammate banking the same
letter, the match ending — reaches it as that row going away.

- **Hidden over your own Gub.** You know you are carrying: the lamps say so and
  count the seconds, and a card above your head sits in the middle of your view.
- **Hidden over a dead Gub** from the frame `alive` drops, not a round trip
  later when the host's hold-end arrives.
- **Reusable.** The marker knows nothing about letters: `set_carrying(glyph,
  colour)`, with `""` to clear. Capture-the-flag carriers are meant to turn on
  the same marker and announce through the same `add_event`.

**Why through walls is allowed here when an enemy's name is not.** D-047 calls
an enemy plate through a wall a wallhack, and it still is. A carrier is the
exception because the carrier has already announced themselves: the hold is a
ten-second commitment to stand without a spear, and the mode is built around
somebody coming to stop it. A marker seen only by people who can already see
the fist would add nothing. It reveals who is carrying and nobody else, and it
is gone the moment the hold ends.

**Checked.** `tools/letter_carriers.tscn`, headless, in the gate as "letter
pickups told to everyone" and "free-for-all letter carriers". It uses the real
spawn path, the real HUD, and cards claimed through `claim_pickup`. A bank puts
"Thornbeak banked B" on top of the feed. Thornbeak's second B is consumed with
no hold, no row and no marker. "Nettle picked up G" and then "Pipwick picked up
U" go on top. Nettle (an enemy in Teams) and Pipwick stand forty metres out
behind a wall proven by ray. Both markers are up with the right glyph, every
part undepth-tested, and the card's bottom above the plate's top. The local
player's own hold is carrying but not shown. After Pipwick's hold is banked on
its own clock, and after Nettle is killed, each marker is gone. The feed never
exceeds `MAX_ROWS`. Without `_refresh_carrier_marker` the marker verdict fails;
without the `letter_picked_up` emit both pickup rows fail. Through `snapshot.gd`
the same scene renders the Gub's own view with the feed: both cards over the
wall, the enemy's with no name under it. 38 checks to 43.

### Rejected
- **Diffing `letter_hold_changed` in the HUD to find a start.** It fires for
  starts and ends alike, so the HUD would need its own record of who was
  holding: a second copy of `_letter_holds`.
- **A minimap, or an arrow at the screen edge.** The user chose a marker only.
- **Showing the marker to yourself.** It is in your way, and it tells you nothing
  the lamps do not.
- **Hanging the marker on the nameplate.** The plate is about names and whether
  they are an ally's. Carrying is a different fact, and capture the flag needs a
  marker that does not care what a plate is.
- **Announcing a hold lost to death.** The kill row already says so, and a
  second row for the same moment pushes older rows out of a five-row feed.

## D-051 — Capture G·U·B: three letters in the world, carried into your own base, dropped where a carrier dies and sent home after a host-set time
The user: *"capture the flag game mode with the letters, you have to pick up the
letter and drop it in your base, there are only 3 and dont drop from users
dying"*. Asked what happens to a carrier's letter, the user said it drops on the
ground for a host-set time and then returns to its spawn, and that anyone,
including the other team, can pick it up. Asked for its own section of rules in
the lobby, visible now, with bases a map can declare, and a fallback so the mode
is playable until the dedicated map lands.

**A new win condition, `MatchConfig.WinCondition.CAPTURE`, appended after
LETTERS.** LETTERS is not changed. Its drop chance, its ten-second hold, its
re-drop at the corpse and its checks in `match_rules` all stand exactly as they
were. The two modes share the three-bit masks, the pooled team mask (D-049), the
card mesh (D-041), the hold row, the carrier marker and the feed (D-050), and
differ in how a letter is earned.

**What it inverts, and why LETTERS keeps the original.**
- **D-033's uniform drop chance.** There are exactly three cards, G, U and B,
  spawned once at match start. No corpse drops a letter, whatever
  `letter_drop_chance` says: `_drop_loot` still only rolls cards under LETTERS.
  In LETTERS the drop is the whole economy, and a card is a thing a fight
  produces. Here the cards are the objective, and more of them would be a
  second objective.
- **D-035's ten-second hold.** Touching a card does not start a countdown. It
  starts a carry, which scores only when the carrier walks into their own base.
  In LETTERS standing still is the tension; here the run home is. The hold's
  "no spear while the card is in your hand" is kept, because the carry *is* the
  hold row with an infinite deadline (below).
- **D-035's "death returns the card at the corpse" is kept, and given a clock.**
  In LETTERS a re-dropped card is an ordinary pickup and withers after
  `Pickup.LIFETIME`, which is fine when another card is only a few deaths away.
  Here a card that withered would be a letter leaving the match for good and
  the match could deadlock, so capture cards never wither
  (`Pickup._keeps`) and the host sends a dropped one home after
  `capture_return_time`.

**The rules as built.**
- **A carry is a hold with no clock.** `claim_pickup` starts a row in
  `_letter_holds` whose `ends_at` is INF, through the same `_do_begin_hold` RPC.
  So on every peer, and with no new replication: the card is in the fist, the
  spear or bolt is gone, the gold marker is over the carrier through walls, and
  the feed says "Name picked up G". `_tick_letter_holds` never ends one.
- **One carry at a time.** A carrier walking over another card leaves it where
  it is, as a hold does.
- **Banking.** Every tick the host checks each carrier against *its own team's*
  base only: horizontal distance within the base radius and height within 3 m.
  The carrier must be alive in `stats` **and** in its body. D-043 keeps a dead
  Gub's body and collision where it fell, and a carrier that died on the edge of
  a base must not bank from there. Banking ends the carry, calls `award_letter`
  (team mask, the banker's own row, "Name banked G", the win check), and the
  card goes straight back to its home point. Walking into the enemy base does
  nothing.
- **A team cannot pick up a letter it has already banked.** The card stays on
  the ground for the other team. The alternative, a banked team carrying it off
  for no score, lets a team that is ahead take the letter the other team needs
  and sit on it. With this rule the late game is a fight over the middle, not a
  keep-away.
- **A dead carrier drops the card where they died**, on the ground under the
  death point, for `capture_return_time` seconds (lobby dial, 15 s default,
  3-60). Anybody may take it in that time: the killers, or the carrier's own
  team recovering it. Picking it up clears the return. When the time runs out
  the host withers the dropped copy on every peer and spawns the card at home,
  and the feed says "G went home". A carrier who disconnects drops exactly as a
  death does. **A death with no ground under it** (the void, a gorge) sends the
  card home at once, with the same feed line.
- **Winning** is the Teams letters test on the same pooled mask: the first team
  holding G, U and B wins, with reason `capture` ("The team carried G·U·B
  home."). A match ending mid-carry grants nothing, as a hold does.
- **Carriers are slower.** `capture_carrier_speed` (lobby dial, 0.9 default,
  0.5-1.2) multiplies ground speed at `Gub.target_speed`, beside the Elder's
  boost. An Elder can carry: it is a faster Elder and a slower carrier at once,
  still unkillable except by the void, for the rest of its twenty seconds.
- **Spawns.** In this mode a Gub spawns and respawns on its own team's pads:
  each pad belongs to one base (below), so the defenders come back next to what
  they are defending.
- **Rematch** is a scene reload after `MatchState.reset`, which clears the
  cards, the declared objectives and the layout; the next warmup spawns three
  fresh cards.

**Free-for-all.** Capture G·U·B is a Teams mode: a base belongs to a team.
`MatchConfig._clamp_all` forces `mode = TEAMS` whenever the condition is
CAPTURE, so every path into a config (the lobby, a peer's dictionary, a harness)
comes out playable. The lobby handles the other direction. Picking Free-for-all
while Capture is selected sets the condition back to the kill limit in the same
push. The clamp cannot do that, because it cannot tell which of the two fields
was just changed.

**The lobby.** "Capture G·U·B (teams)" is the fifth entry in "Ends on". Picking it
shows a section of its own, **CAPTURE G·U·B**, between Limits and Feel: "Dropped
letter returns" (after 15 s) and "Carrier speed" (-10%), and one line of small
print stating the rules that are not dials. Both fields are in `_FIELDS` with
clamps. The kill-limit, lives and letter rows hide as they do for any other
condition.

**HUD.** The G·U·B lamps show for both letter conditions, labelled TEAM LETTERS.
While carrying, the lamp is full and the caption reads "CARRYING G · TO YOUR
BASE" instead of a countdown. `letter_hold_remaining` is INF for a carry, so the
HUD does not pass it on to be divided. The scoreboard and results show and rank
by letters under CAPTURE as they do under LETTERS (`MatchConfig.scores_letters`).
New feed rows: "Name dropped G" and "G went home", from two new event signals,
`letter_dropped` and `letter_returned`, sent by one reliable `_announce_capture`
RPC.

**Bases, and the contract for a map built for this mode.** A `StaticMap` scene
may declare:
- a **`Bases`** node with one `Marker3D` per team, **in team order** (first child
  is Team 1), each on the floor at the middle of the base;
- **`base_radius`** (export on `StaticMap`, default 4.0 m);
- a **`Letters`** node with three `Marker3D`s **in G, U, B order**, on the floor
  where each card starts and returns;
- its eight **`Spawns`** as before; each pad belongs to the nearest declared base.

`StaticMap.base_points()` and `letter_points()` read them. `arena.gd` hands them
to `MatchState.set_capture_map` before `register_arena`, which plans a
`CaptureLayout` from them and the pads on every peer. Too few bases for the
lobby's team count, or fewer than three letters, and that half falls back whole,
with a warning. Declared letter points are still settled onto the nearest
standable floor.

**The fallback is a placeholder**, and today it is used on every map, because no
map declares anything yet:
- **Bases**: the pads are split by bearing around their centroid into one
  contiguous arc per team, choosing the rotation that keeps the arcs tightest.
  Each team's base is the pad in its arc nearest the arc's middle by bearing,
  tie broken anticlockwise on every arc so the bases on an even ring come out
  opposite. A pad, not the centroid, because a pad is proven standable and a
  centroid can be inside a container. Pads belong to the arc they came from.
- **Letters**: G at the midpoint of the first two bases, U and B either side of
  it across the base-to-base axis (30% of the distance, 4-10 m), so all three are
  equidistant from both bases. The host settles each onto real ground once the
  physics has stepped: a ray peeled down the column, a floor no steeper than
  normal.y 0.7 with a Gub's capsule of head room, nearest the bases' height. It
  searches rings 2 m apart out to 10 m, first for a floor within 1.5 m of the
  bases' height and only then for any floor, and keeps each card 4 m clear of the
  ones already placed.
- As measured in the gate: Whisperbloom Hollow's bases are 18.8 m apart (its
  spawn ring is small) with the letters within 6 m of the middle. Rust's are
  43 m apart, at the north yard and the south-west wall. Kopje Crossing's are at
  opposite corners, 88 m apart, with the letters on the ground round the foot
  of the central kopje rather than on top of it.

**The bases are drawn** by `CaptureBase` on every peer, only in this mode: a
glowing band at the edge fading upward, which reads on a slope where a flat ring
would sink in, a faint 14 m column of light, a floor wash and a light, all in the
team's colour, with no collision.

**Checked.**
- `tools/match_rules.gd`, "match rules" in the gate, three new scenarios, in a
  Node3D arena with a floor box so drops land on real ground.
  - "three cards, carried home, dropped and returned": three cards spawn on their
    homes a few frames in. A kill at 100% letter drop chance drops loot but no
    letter. Touching G makes a carrier with no clock, no spear, and 0.8x walking
    speed. A second card is left on the ground. The enemy base banks nothing; the
    own base banks G into the team mask and the banker's row, and G is back on
    its home point with three cards in the world. A team leaves its own banked G
    on the ground. An enemy carrier killed at a point drops U on the floor there,
    due home in 12 s, and the drop is announced. A tick does not return it
    early. The killing team picks it up. Dropped again and wound past its clock,
    it goes home, the dropped copy is gone, and the return is announced. A
    carrier lost to the void sends B home at once. A carrier whose `stats` row
    says alive but whose body is dead banks nothing in its own base; once
    respawned, the same carry banks, and the third letter wins with reason
    `capture` and the team mask in the summary. `reset` clears it all.
  - "bases and letters out of the spawn pads": the fallback on an eight-pad
    ring gives two far-apart bases that are pads, a 4-4 pad split, three letter
    points equidistant from both bases and outside them, and `in_base` rejects
    a point outside the radius, a ledge 6 m up and the other team's base. Three
    teams give three bases. Declared bases, letters and radius are used, and too
    few declared bases fall back whole.
  - "a Teams mode": `apply_dict` turns Teams on for CAPTURE. The real lobby
    panel, under the host's `update_config`, shows the capture section and its
    dial, and picking Free-for-all gives a free-for-all on the kill limit with
    the section hidden. Both fields round-trip through `_FIELDS` and clamp at
    both ends. A condition past CAPTURE clamps to it.
  - Every existing LETTERS scenario passes unchanged. Removing the body-alive
    guard from `_tick_capture` fails the dead-body check.
- `tools/playthrough.gd` checks the layout on each map it walks, and the gate
  greps "playthrough: capture layout PASS" on Whisperbloom Hollow, Rust and
  Kopje Crossing. Two bases for two teams, well apart, each team with pads and
  a floor under its base. Three settled letter points on a floor with head room,
  outside both bases, apart.
- `tools/capture_preview.tscn -- safari`, headless, in the gate as "capture match
  on a real map". It builds the real arena in this mode and checks that both
  bases are drawn, three cards are at home, and every Gub spawned on its own
  team's pad. It also passes on hollow and rust by hand. Through `snapshot.gd`
  it renders from above Team 1's base (`out/capture_base_*.png`). `ui_range`
  mode `lobby_capture` renders the lobby section.
- 43 checks to 47.

### Rejected
- **Changing LETTERS.** The user asked for a mode, and LETTERS is a finished
  mode with its own checks.
- **A card that returns home the moment its carrier dies.** The user chose a
  drop with a timer, and a drop is what makes a kill on a carrier a fight over
  the ground rather than a reset.
- **A dropped card that belongs to nobody for ever** (no return), or one that
  withers. Either can take a letter out of the match, and three letters is all
  there are.
- **Letting a team pick up a letter it has banked.** Keep-away with the other
  team's last letter, for no score.
- **Only the carrier's own team recovering a drop**, or only the enemy. The
  user said anyone.
- **Hiding Capture in the lobby under Free-for-all.** The user wanted it visible.
  Forcing Teams on selection keeps it one click away, and falling back to the
  kill limit when Free-for-all is picked keeps that picker honest.
- **Base volumes as `Area3D`s.** An overlap on the host is one more thing to be
  wrong about a dead body (D-043) and a remote Gub's interpolated position. A
  distance test against the live body, gated on alive, is the whole rule and
  reads the same in a harness.
- **The centroid of a team's pads as its fallback base.** On Rust it can be
  inside a container; a pad is proven standable.
- **Letting carriers throw.** The carry is the hold row, and a thrown spear from
  a hand showing a card is the disagreement D-035 exists to prevent. If
  playtesting says carriers need to fight, it is a dial on the throw gate, not
  a second kind of carry.

## D-052 — Jumps carry momentum, and timed hops build it up to 1.3x run speed
*Amends the feel of D-026's single jump. D-026's input design, the dive and its
roll (D-029) are unchanged.*

The user: *"bunny hopping / jumping need to account for momentum a little
more"*. Asked for a cap, the user chose 1.3x the Gub's current run speed, scaled
by whatever multipliers apply, and to tune it after a playtest.

**What was scrubbing it.** Two things, one after the other. In the air,
`_handle_movement` pulled horizontal speed toward `wish * target_speed` at
AIR_ACCELERATION (12 m/s²), so anything above target was cut back to it. On the
first ground tick, before `_handle_jump` could fire a buffered press,
GROUND_ACCELERATION (48 m/s², 0.8 m/s a tick) cut it again. And nothing ever put
speed above target in the first place, so keeping momentum alone would have
changed nothing a player could feel.

**The rule.**
- **Kept, not cut.** Horizontal speed between target and the cap is steered
  toward the stick at the usual rate but keeps its length, in the air and for
  `LANDING_GRACE` (0.1 s) after a landing. Only while pushing forward of the
  current travel: let go, or pull back, and the Gub slows as before. Speed
  above the cap (a lure fling, a robe coming off) bleeds down the old way
  until it reaches the cap, so nothing is clamped in one tick.
- **Gained by timing.** A jump fired inside the landing grace, within ~45° of
  the way the Gub is travelling (`HOP_ALIGNMENT` 0.7) and at 0.9x target or
  more, adds `HOP_GAIN` (0.04) of target speed, up to `HOP_SPEED_CAP` (1.3) of
  it. The first jump out of a run gets nothing, because it is not a landing.
  A plain run of hops reaches the cap on the eighth timed hop after it, about
  five and a half seconds of unbroken chain.
- **A landing is a real landing.** The grace is only given after
  `HOP_MIN_AIRTIME` (0.2 s) in the air, so the floor flickering under a Gub
  running over bumps is not a string of landings.
- **Everything is a fraction of `target_speed`**, so the Elder's boost (D-040)
  and the carrier's slowdown (D-051) scale the cap and the gain with nothing
  else knowing about them.
- **Vertical take-off is untouched.** `jump_velocity()` and the jump arc are
  the same numbers, so the animator's arc ratio (D-040) holds.
- **The dive keeps its tuning.** No momentum is kept through a dive's airtime
  (`_air_jump_spent`), so a dive still decays toward target as it did and is
  no longer. A dive landing starts the roll lock and gets no grace. By the time
  the lock lets the buffered jump fire, ROLL_FRICTION has already slowed the
  body and the jump is ordinary.
- Remote Gubs follow snapshots and run none of this. They show the carried
  speed through `sync_velocity`, like an Elder's 7.3 m/s. Up to 1.3x run, the
  run cycle skates a little.

**Measured** by `tools/combat_range.tscn -- bhop` (headless, `--fixed-fps 60`),
top horizontal speed in m/s. Before is this commit's check run against the
movement code before it:

| subject | run | one jump | before: top with hops | after: top with hops | late hop |
|---|---|---|---|---|---|
| Gub | 5.40 | 5.40 | 5.40 (1.00x) | 7.02 (1.30x) | 5.40 |
| Elder (1.35) | 7.29 | 7.29 | 7.29 (1.00x) | 9.48 (1.30x) | 7.29 |
| Capture carrier (0.9) | 4.86 | 4.86 | 4.86 (1.00x) | 6.32 (1.30x) | 4.86 |

**Checked.** In the gate as "bunny hops carry, up to a cap". For each subject:
sprint, one jump, ten hops pressed on the first ground tick, a hop pressed 0.25 s
after landing, and a dive whose roll is jumped out of. Hops must reach 1.15x and
stay at or below 1.3x (+0.02 m/s). Running, one jump and the late hop may not
beat run speed, and the hop out of a dive roll may not beat the larger of its
ground speed and run speed. Against the old movement all three subjects fail at
1.00x. With `LANDING_GRACE` at 0 the hops fail, and at 5 s the late hop keeps
the bonus and fails. 47 checks to 48.

### Rejected
- **Keeping momentum without a gain.** Nothing in plain movement exceeds target,
  so there would be nothing to keep.
- **A gain for any jump, not only one timed off a landing.** Then jumping once
  out of a run would be faster than running, and it would stop being a skill.
- **Momentum through the dive's airtime.** 9.5 m/s held all the way to the
  floor lengthens every dive. That is a dive retune, not a hop.
- **Clamping to the cap at once.** A lure fling or a robe coming off would lose
  metres per second in one tick. Bleeding down the old way reads better.
- **Scaling `jump_velocity()` with the hop speed.** Hop height would change with
  speed and break the animator's arc ratio (D-040).
- **Absolute m/s numbers for the cap and gain.** The Elder's boost and the
  carrier's slowdown would stop applying to hop speed, and D-040 and D-051 put
  every speed through `target_speed` so that could not happen. A chained
  carrier still reaches 6.32 m/s, above a plain Gub's run. It is 0.7 m/s under
  a hopping chaser, so the carrier can still be caught.

## D-053 — The Elder's bolt has a small blast radius, a hard edge that kills or does nothing
*Amends D-038's "a ray, and whatever it hits". The ray, the cooldown, cover and
D-040's ward are unchanged.*

The user: *"the lightning should have an aoe (small blast radius) so that if you
hit pretty close it still hits them, this should still be a one shot kill, but
not too far"*.

**The rule** (`GubCombat._host_cast_lightning`, `_blast_victims`):
- **Where it lands.** The blast is centred on the point the ray stopped at: the
  world, a deployable, or a Gub. A bolt that hit nothing (sky, or the end of
  `LIGHTNING_RANGE`) has no blast and no ring. A sphere of death hanging in
  mid-air 28 m away is a second, invisible weapon, not "hit pretty close".
- **How far.** Measured from the impact to the **surface of the victim's
  collision capsule** (`Gub.distance_to_body`: distance to the capsule axis
  minus its radius). So a crouched or sliding Gub is a smaller target for the
  blast, as it is for the ray. The drawn ring's outer edge is exactly
  `lightning_radius` around the impact, which on flat ground is the sphere's
  own cross-section: a body touching that sphere dies.
- **No falloff.** Inside the radius it is the same kill a direct hit is.
  Outside it is nothing. There is no health for a falloff to take.
- **Line of sight.** A ray from the impact, backed off 0.1 m along the bolt so
  it does not start inside the surface it struck, to the nearest point on the
  victim's axis, then to the capsule's centre. Either clear is enough. World
  and deployables block it, so a wall or a shield mushroom is still cover
  (D-038). Other Gubs do not block it.
- **Who.** Every living Gub except the caster and the direct victim (who is
  already handled). Dead Gubs keep their collision (D-043) and are skipped.
- **Through `report_kill`**, one call per victim, so spawn protection,
  friendly fire and the Elder ward (D-040) apply exactly as they do to the ray.
  An Elder in the blast is warded, not killed. Capture carriers still cannot
  cast (D-051).
- **The dial.** `MatchConfig.lightning_radius`, default 1.5 m, range 0 to 4,
  clamped, in `_FIELDS`. The lobby slider "Lightning blast" sits right after
  "Lightning delay". 0 reads "Direct hit" and is the old bolt.
- **The picture.** The host sends the radius with the bolt
  (`_do_cast_lightning`), so every peer draws the ring the host killed with,
  not its own config's. The ring is a thin bright band drawn inward from the
  edge over a faint disc, in the plane of the struck surface (level on a body),
  at full size from the first frame and fading over 0.5 s. A ring that grows in
  shows a smaller radius than the rule for most of its life.

**Checked** by `tools/combat_range.tscn -- blast`, in the gate as "lightning
blast radius". The player is made the Elder and fires three exact casts through
`_host_cast_lightning`. Distances are re-measured at the cast and printed:
- ground impact, dummy at 1.30 m (radius − 0.2): dies;
- same impact, dummy at 1.70 m (radius + 0.2): survives;
- ground impact 0.35 m in front of a 0.2 m wall, that survivor 1.30 m away
  behind it: survives. With the line-of-sight test forced clear it dies and
  the check fails;
- a bolt into an Elder's chest, landing on its capsule: survives, still Elder;
- `lightning_radius` round-trips `to_dict`/`apply_dict`, clamps 9 to 4 and −1
  to 0, and defaults to 1.5.

The ring is photographed at `out/blast.png` (tick 43). 48 checks to 49.

### Rejected
- **Falloff, or a knock-back ring outside the kill ring.** The user asked for a
  one-shot kill and "not too far". Two radii would be two things to read.
- **Distance to the feet or to the chest.** Feet make a jumping Gub immune to a
  bolt at the ground under it. The chest makes a bolt into the ground at a
  Gub's toes miss. The capsule surface matches what the ray already hits.
- **A blast at the end of the range when nothing was hit.** See above.
- **A fat ray (killing anyone the bolt passes near).** That is a wider beam,
  not a blast, and it would make the bolt kill through the gap beside cover.
- **Drawing a sphere.** A glowing ball hides the body it is killing. The ground
  ring is the part a distance can be read off.
- **Each peer drawing the ring from its own config.** A client with a stale
  config would draw a ring that disagrees with who died.

## D-054 — The spear tile times its recharge from the release; the crosshair stays a plain reticle
*Amends D-036. The slot half of what D-036 deleted is back, for the first tile
only; the crosshair half stays gone.*

The user: *"There should be an indicator into how long until you get a spear
reload ONLY in the bottom bar menu, not on the main cursor"*, then, asked
whether that meant a timer: *"go ahead and do the reload timer as well, it
should be on top of the thing that shows whether its up or not in the bottom of
the players screen"*.

D-036's complaint was never that a recharge timer is wrong. It was that both
rings it tried were wrong about the windup: one sat full through the 0.71 s
windup and then dropped, the other swept from the click while the spear was
still in the hand. The tile's timer answers that by **not running during the
windup at all**.

**What the tile shows** (`AbilitySlot.set_armed(lit, remaining, total)`, fed by
`HUD._refresh_abilities`):
- **Ready:** lit, nothing else. Unchanged.
- **Winding up:** dark, no fill, no number. The spear is still in the hand and
  nothing is growing back yet, so the tile says nothing.
- **Recharging** (after the release): dark, a faint yellow wedge that fills
  clockwise from twelve o'clock out to the square's corners, and the seconds
  left printed over the glyph with a black outline. The denominator is
  `spear_recharge` and the remaining time is `spear_cooldown()`, which the
  release resets to exactly `spear_recharge`. So the fill starts empty and the
  number starts at the full recharge. Tenths under ten seconds, whole seconds
  above, always rounded up, so it never reads "0.0" over a spear that is not
  back. Both disappear the frame `has_spear()` is true.
- **Holding a letter, or carrying one in Capture G·U·B** (D-051 made a carry a
  hold with no clock): dark, no timer, as before. A recharge counting down to
  zero over a Gub who still cannot throw would be a countdown to nothing, and
  the lamps are that player's timer.
- **The Elder:** the same tile with the bolt glyph gets the same treatment off
  `lightning_cooldown()` over `MatchConfig.lightning_cooldown` (D-040's 1 s),
  also silent through its own windup. It is one tile in one place. Timing one
  weapon in that square and not the other would be two rules for one square,
  and the code is the same call with a different clock.

Mushroom and lure tiles are unchanged: stock counts, per the user's "spear".

`GubCombat.spear_cycle()` is still what the click spends. Its comment claimed
the HUD divided by it, which has been untrue since D-036 and is now corrected.
Nothing on screen divides by the whole cycle.

**Checked** by `tools/hud_range.tscn -- reload_timer`, in the gate as "spear
reload timer on the tile". It throws a real spear with a 3 s recharge and reads
the tile's own `recharge_progress()` and `recharge_text()` just before each
frame is drawn:
- every windup frame (44 of them): no sweep and no number;
- every recharge frame: the number is within 0.1 s of `spear_cooldown()`, and
  halfway through the sweep is between 0 and 1, matches `1 - remaining/total`,
  and the number matches the time since the release (it printed "1.5" at 1.51 s,
  over a 0.51 sweep);
- the frame the spear is back: both gone;
- throughout: the `Crosshair` script has no property or method named for a ring,
  a recharge, a cooldown, a progress, a fraction or a cycle, and `set_state`
  still takes one argument;
- the number format, on a detached tile: 1.41 reads "1.5", 0.01 reads "0.1",
  12.3 reads "13", and armed or zero-total reads "".

With the windup gate removed from the HUD, the check fails on windup frame 0
(the tile read "3.0"). The tile is photographed mid-recharge at
`out/reload_timer.png` (tick 130). 49 checks to 50.

### Rejected
- **Timing from the click.** That is D-036's second ring moved to the bottom
  of the screen. The sweep would move while the spear is visibly still in the
  hand.
- **Showing the recharge (full, not moving) during the windup.** That is
  D-036's first ring. A tile that holds "3.0" for 0.71 s and then starts
  counting reads as a stall.
- **Anything on the crosshair.** The user said "ONLY in the bottom bar".
- **A draining fill.** D-036 settled that nothing on this HUD drains. The
  letter hold fills, and so does this.
- **Timing the recharge under a letter hold.** See above.

## D-055 — Whisperbloom Hollow is a 23 m island with a dozen trees twice as tall, and its spawn ring searches from the ideal pad outward
*Amends D-007's layout and D-051's measured base distance for this map.*

The user: *"The existing enchanted forest map should be a little bigger and
reduce the amount of trees by 60% and make them all on average way taller,
double the height"*.

**Measured before and after** by `tools/island_report.tscn` on the default seed
(20260904). The report is now a scene rather than a `--script` main loop, so it
can solve the spawn ring through `Arena` (which names `Net`), and it builds the
whole procedural layout without a scene tree.

| | before | after |
|---|---|---|
| main island radius | 19 m | 23 m |
| footprint | 51 x 50.5 m | 57.5 x 58 m |
| living trees placed | 29 (of 42 asked) | 12 (of 12) |
| dead trees placed | 5 (of 7) | 2 (of 2) |
| mean living-tree height | 7.4 m (5.4-10.3) | 15.0 m (11.0-20.7) |
| mean canopy point height | 5.0 m | 10.8 m |
| capture bases apart | 18.8 m | 30.4 m |
| closest pair of spawn pads | 3.8 m | 6.3 m |
| props, all layers | 1399 (~716k tris) | 2199 (~1008k tris) |
| torches | 15 | 17 |

**Bigger.** `IslandGenerator.MAIN_RADIUS` is 23. That is as far as "a little"
goes before the footprint passes the 60 m the fog is tuned for (D-009). The
islets hang off the rim at a fixed gap, so they and their bridges move out on
their own. Every hand-typed coordinate on the main island (the hollow, knoll
and shoulder features, the grove centre, the path hub, the firefly swarms) is
multiplied by `LAYOUT_SCALE` = 23/19. Without that, the landmarks bunch up in
the middle of a larger island. Heights are not scaled. The arch, bridges and
spawn ring were already solved against the rim.

**Fewer trees, measured by what landed.** The dart throw under-places, so
`count` is not the number. 34 trees landed before (29 living, 5 dead) and 14
land now (12 and 2), which is 41%. On the bigger island, with fewer trunks in
the way, every tree asked for lands, on every seed swept.

**Twice as tall, not twice as big.** `scale` is still the footprint (width,
trunk radius, reserve). A new `stretch` multiplies only the height. The
footprint went up 1.41x and the stretch is 1.37, which comes out at 2.0x the
mean height on the default seed. Across four seeds the mean is 13.8-15.0 m. The trunk cylinder
is stretched with the drawn tree: height from the stretched mesh, radius from
the footprint. The minimum gap grew with the crowns (3.7 m to 5.2 m).

**The spawn ring was fixed, not just widened.** `_solve_spawn`'s comment said
the ideal ring was tried first. The loop actually counted from the innermost
alternate (0.66 - 0.165 of the rim) and took the first pad that passed, so
nearly every pad sat at about half the rim radius. That is why D-051 measured
bases only 18.8 m apart. It now tries the ideal fraction, then alternates
either side. Pads also have to be 6 m from every pad solved before them.
Bearings that both swing clear of the knoll used to land 3-5 m apart. With the
search fixed and `SPAWN_RING` unchanged at 0.66, the bases are 29-34 m apart
across the seeds swept. One seed in twelve (20263835) now takes a 0.48 slope
for one pad rather than doubling up. That is walkable, and it warns.

**Ambience.** Leaves came from a ring sized to where the trees were. Twelve
trees make most of that ring open sky, so leaves now emit from 32 points
scattered through each crown. `PropScatter.canopy_radii` gives the crown's
reach, and the vertical spread is 4 m. There are five leaves per tree, and
the lifetime went from 11 s to 16 s so a leaf from a 10 m crown reaches the
ground before it fades. Spores rise to about 13 m instead of 9.5 m, with 420
motes instead of 260 to keep the density in a bigger box. Fireflies stay at
head height and move with the layout scale.

**Sightlines and camera.** Cover on the island is now mostly trunks: 0.5-0.7 m
radius columns about 9 m tall, instead of three times as many 0.35-0.5 m ones.
The hollow is more open from the pads. The camera (D-045) sweeps against
collision, and only the trunks collide, so taller crowns change nothing for it.
`out/hollow_after_canopy.png` is a camera at boom height beside a trunk,
looking at the middle of the map, and it reads clearly.

**Triangles.** The dense layers are per square metre, so 47% more land is
about 45% more grass. That is most of the ~300k extra triangles. It is left
alone because thinning the grass would change the look the user did not ask
to change.

**Checked.**
- `tools/island_report.tscn -- 20260904 4`, in the gate as "the hollow's
  forest and pads". On four seeds: the main radius equals `MAIN_RADIUS`, 10-14
  living trees are placed, the mean height is 12-18 m, the capture bases are
  more than 25 m apart, and no two pads are within 5.5 m. With the old tree
  table, the old search order and no pad spacing, all four seeds fail (12
  verdicts).
- "full playthrough" and its capture layout still pass on the island (bases
  30.3 m apart). `capture_preview -- hollow` passes by hand.
- `tools/preview_map`'s pad physics check is for static maps only. The island's
  pads are solved against the height oracle, and `preview_island ... match`
  shows every Gub settling on its pad.
- `preview_island` gains `top` (orthographic plan, lit plainly), `eye0`-`eye7`,
  `canopy` and `tree`, and `hollow` is scaled with the layout. The before and
  after renders are `out/hollow_before_*.png` and `out/hollow_after_*.png`.
- 50 checks to 51.

### Rejected
- **Doubling `scale`.** It doubles the crowns' width with their height, and a
  twelve-metre crown roofs a quarter of the hollow.
- **A radius of 24 m or more.** The footprint passes 60 m and the far edge goes
  into the fog.
- **Moving the landmarks by hand.** `LAYOUT_SCALE` keeps them where they were
  relative to the rim, and the next resize is one number.
- **Pushing `SPAWN_RING` out to widen the bases.** The ring was never being
  used. At 0.70 and 0.74 on the old search, the bases only reached 22.7 m and
  24.4 m.
- **Keeping the leaf ring.** Over twelve trees it drops leaves out of empty sky.
- **Thinning the grass to hold the triangle count.** Not asked for, and it
  changes the look.

## D-056 — Lantern Wharf: a small symmetric box yard, built from a table, held to a 25 m sightline and to tops nobody can reach
The user: *"add shipment call of duty map"*.

What was built is the *shape* of that kind of map, not a copy of one: a small,
dense, walled, mirror-symmetric yard with two bases facing each other across a
grid of hard cover, where nothing is ever far away and the fight is meant to be
chaotic. The geometry, the props, the textures and the name are this game's
own. No layout, name or asset from any other game was used or referred to; the
layout came out of a search against this game's own sightline and jump numbers
(below). The map is **Lantern Wharf**, id `wharf`, the fourth row in
`MapCatalog`.

**What it is.**
- A 36 x 36 m yard at y = 0, walled by container stacks three high (7.8 m; four
  wall boxes carry a fourth tier for the skyline), on a floor that stops at the
  walls' outer face. `void_height` is -10 and nobody meets it.
- Inside: **14 towers** (three containers, 7.8 m), **6 singles** (one container,
  2.6 m, climbable) and **8 crates** (1.2 m, a hop from the ground). 88 wall
  boxes. 1,714 triangles swept into 9 collision shapes in about 3 ms; the
  dressing adds door bars, two quay cranes beyond the north and south walls and
  four floodlight masts, none of it collision.
- The north half is the table and the south half is its mirror across z = 0.
  The table happens to be symmetric in x too; it is written out both sides so a
  later edit can break that without touching the mirror.
- Eight pads, four per team, alternating north and south: two in each end's
  corner pockets and two in the bays either side of its base. Each faces the
  middle and sees 7.3-8.3 m down its nose, which on a box map is the right
  number: the first thing in front of a spawning Gub is cover.
- **Capture G·U·B is declared, not fallen back to** (D-051's contract). `Bases`
  are (0, 0, -15.5) and (0, 0, 15.5), 31 m apart, each in the 6.6 m bay between
  two towers against its back wall, behind a spine tower; `base_radius` is 4.
  `Letters` are G at the crossroads in the centre and U and B in the pockets
  against the west and east walls, each the same distance from both bases.
  `playthrough -- wharf` and `capture_preview -- wharf` both report the layout
  as declared by the map.

**Built from a table, like Kopje Crossing (D-042).** `WharfMap` extends
`StaticMap`, lays the floor, walls, boxes and crates, calls `super()` to bake
them, and then adds the dressing. There is no random draw anywhere, so every
peer builds the same yard by construction. The container is a hand-built mesh
rather than a `BoxMesh`, for its UVs: every face is mapped in metres along and
0-1 up, so the ribs are vertical and even on every side and the rails of the
texture land on every edge. The corrugation albedo, its normal map, the crate
planks and the wet concrete are all computed at load. Rust's textures were
considered and not used: the repository records no licence for the Rust
source, and a painted box needs nothing an image file would add.

### The two numbers the layout answers to
**No jump reaches a tall top.** The Gub's jump reaches 1.69 m, a leap 2.30 m,
and the one-tick dive `parkour_report` calls "big" 4.23 m of rise. So a
two-high stack (5.2 m) beside a single (2.6 m) is reachable, and from 5.2 m every
roof on the map is in view. There are no two-high stacks: cover is either
climbable (a single, a crate) or out of reach of everything (a tower, a wall).
`StaticMap` grew `off_limits` for this, and `parkour_report` fails the build if
any hop, leap or big dive off any landing, or from the ground, reaches one of
the 56 tower and wall tops.

**No eye-to-eye sightline over 25 m.** A 36 m square has 51 m diagonals.
`parkour_report` now samples the floor every 2 m (288 standable points) plus
every landing, eyes 1.45 m up, and casts every pair. The longest line between
two Gubs on the ground is **23.4 m**; from a roof it is **25.0 m** (24.97 m,
the roof of a yard box to the far end's corner pocket). The gate allows 25 m on
the ground and 26 m from a roof: the roof number is deterministic, but a limit
that passes by three centimetres fails the day `EYE` or a box moves. It also
checks that no spawn pad sees any pad belonging to the other base, and none does.

**How the layout was found.** The first hand-drawn layout measured 34.5 m on the
ground and 40 m from a roof, and a second was worse. A line over 25 m inside a
36 m square has to run more than 17.7 m along one axis, so every such line
crosses the middle of the map or runs down a wall. So the layout was searched: a
throwaway annealing script (not committed; it was scaffolding, and the committed
check is the arbiter) moved a handful of mirrored towers and singles on a
half-metre grid, kept every gap either flush or at least 1.6 m so there are no
slots to get stuck in, kept the pads, base and a connected floor clear, and
scored every visible pair of eyes past 24 m. Every result that left the strip
along the back wall open stayed at 34 m, which is what put two towers either
side of each base. The best result was then read, trimmed and given crates by
hand, and checked in Godot against the real collision; the Python and the
engine agreed to the tenth of a metre on both layouts compared.

**Parkour.** 20 landings, all reachable by hops alone (44 hop, 56 leap, 52 big
edges in the whole graph). Every crate is flush against the box it is a step
onto, and every single has one.

### Lighting
Dusk, so it is neither Rust's afternoon nor Kopje Crossing's noon: an orange sun
17 degrees up over the west-south-west wall (energy 0.9, shadowed), a
violet-to-orange sky that is also the ambient, and four shadowless sodium
floodlights on masts at the wall corners, aimed short of the middle so the pools
overlap there and each base gets two. The containers are painted bright (red,
blue, yellow, green, tangerine, teal, cream) and the walls are the same palette
darkened to 62% and pulled toward grey, because a boundary as bright as the
cover in front of it is a map where the cover does not stand out.
`background_energy_multiplier` is 1.5. Counted with PIL on `out/wharf_pad0.png`,
`wharf_pad4.png`, `wharf_parkour_iso.png` and `wharf_top.png`: 0.00% of pixels
below 8/255 and 0.00% at 255 in all channels.

### What changed around it
- `StaticMap.Platform` (moved from `SafariMap`), `platforms` and `off_limits` are
  on `StaticMap`, so the report reads any built map. Kopje Crossing is unchanged
  and still passes its own nine checks.
- `parkour_report` takes `map=` and holds each map to its own row in `EXPECT`
  (landing count, big-edge floor, the summit rule, sightline limits, framing).
  The sightline and off-limits checks run only for a map that asks for them.
- `preview_map` takes `min_triangles=`: its 90,000 floor means "Rust imported",
  and a box yard of 1,700 triangles is right to be under it.
- `playthrough`'s capture line says whether the bases and letters were declared
  or fallen back to, so the gate can tell.

### What checks it
Six lines in the gate, 51 checks to 57: a playthrough on `wharf` with `also`s
that Lantern Wharf was built, that its capture layout passed and that the layout
was declared; `preview_map` on its pads; and `parkour_report` on it. Renders are
not committed: `out/wharf_top.png`, `wharf_side.png`, `wharf_pad0.png`,
`wharf_pad4.png` and `wharf_pad7.png` from `preview_map`,
`out/wharf_parkour.png` and `wharf_parkour_iso.png` from `parkour_report`, and
`out/capture_base_wharf.png` from `capture_preview`.

Nobody has played it. Whether 36 m with fourteen towers is good chaos for eight
Gubs or a maze, whether the roofs of the six singles are worth the climb, and
whether the floods read in a fight are for a person.

### Rejected
- **Reproducing a known map's layout.** The user named a map; the request was
  read as its shape. A copy of someone else's level is not this game's to ship.
- **Two-high stacks.** Reachable by the one-tick dive from any single beside
  them, and a perch over every roof.
- **An open strip along the back wall with the base in the middle of it.** A
  34 m lane every spawn crosses; no layout the search found kept it and got
  under 30 m.
- **A roof limit of exactly 25 m.** It passes by 3 cm; see above.
- **Rust's industrial textures.** No licence is recorded for them in the
  repository, and computed corrugation is a few lines.
- **A `BoxMesh` container.** Its 3x2 UV atlas puts the ribs on the wrong axis on
  half the faces.
- **Crane booms reaching in over the yard.** The first render read as a gate
  from the ground, and the boom's shadow crossed a base; the booms now point out
  over the water.
- **Shadowed floodlights.** Four more shadow maps for a small map whose long sun
  shadows already give every box its shape.

## D-057 — Halcyon Wake: a yacht four decks high on a sea that is the void, where every deck has a walk up and a hop up
The user: *"a yacht map"*.

The map is **Halcyon Wake**, id `yacht`, the fifth row in `MapCatalog`: a
superyacht at anchor on open water on a bright morning. Where Kopje Crossing is
a rock garden you climb and Lantern Wharf a yard you run through, this one goes
up: four decks on one hull, and the fight is over who holds which.

**What it is.**
- A hull lofted from cross-sections — keel, waterline, boot top, deck edge,
  bulwark — 62 m from stem to transom and 13 m in beam, with a swim platform a
  metre under the aft deck taking it to 66 m. The deck is full width from
  amidships aft and narrows to the stem along `1 - t^2.2`; the waterline is
  narrower and its stem 5 m further aft, which is the rake and the flare. White
  topsides, a navy boot top, oxide below the water, a line of hull windows.
- **Main deck, y = 0.** The foredeck (the tender on its chocks, Team 1's base),
  two 1.85 m walkways under the upper deck's 1 m overhang, a salon cut straight
  through the deckhouse — 9 m across, 6 m deep, 2.9 m to the ceiling, open both
  sides — and the aft deck (Team 2's base). The salon is the only roofed space
  and is deliberately wide and open-ended for the camera (D-045).
- **Upper deck, y = 3.2.** A forward balcony, 2 m side walkways and an aft
  terrace round the upper deckhouse. **Sun deck, y = 6.2**, with a hot tub, a
  sun pad and G. **Flybridge, y = 8.8**, a 5 x 3.5 m open top under the mast.
- Glass rails, a metre tall, are collision on every upper deck, with gaps only
  where a stair or a step arrives. The main deck has a solid bulwark. Both are a
  hop to clear, so going over on purpose is always possible; the swim platform
  has no rail at all.
- **The sea is the void.** It is a 2.4 km dressing quad at y = -3.0 with a
  scrolling ripple shader, not collision; `void_height` is -3.5. A Gub that goes
  over the side falls about half a second, disappears into the water and dies.
- 2,225 triangles swept into collision in 3 ms, which is why its
  `preview_map` line carries `min_triangles=1000` as the wharf's does.

**Getting up: every deck has a walk and a hop.** The Gub has no step-up, so a
staircase is a smooth ramp in the collision, never drawn, under a flight of
0.2 m treads that are dressing and never collide (26-29 degrees against a 52
degree `floor_max_angle`). A throwaway `CharacterBody3D` with the Gub's capsule,
snap and floor angle walked up both stairs at run speed without a jump. The hop
routes are white boxes flush against the face they lead to, each rise 1.0-1.3 m
against a 1.69 m jump:

| from -> to | walk | hop |
|---|---|---|
| main -> upper | twin stairs up from the aft deck | two steps (1.1, 2.2) at the deckhouse's forward face |
| upper -> sun | a stair up the middle of the aft terrace | two steps (4.3, 5.3) along the upper deckhouse's forward face |
| sun -> fly | — | a 7.5 m step each side at the flybridge's aft face |

The stern team walks up; the bow team hops up faster, so the two ends are
different rather than mirrored, which a hull cannot be anyway.

**What the report reads.** A deck is not one landing — the report reads a
landing as a circle, and one circle big enough for a deck promises floor over
its side — so each open deck is declared as a 2.2 m grid of records, each kept
0.55 m clear of anything standing on the deck and given the radius it can
honestly promise. Stair records sit 0.08 m over the slope, which is what a 0.38 m
capsule on a 30 degree slope needs. 75 landings: upper 31, sun 14, flybridge 4,
swim platform 5, steps 10, stairs 8, and the tender, sun pad and hot tub. Every
one is reachable from the main deck with hops and leaps alone: 69 hops and 6
leaps along the tree (976 hop, 1,112 leap, 996 big edges in the graph). The
mast top (14.2) and its yard (13.4) are `off_limits` — the one-tick dive from
the flybridge reaches 13.03 — and nothing reaches either.

**Sightlines.** A 62 m hull is a 62 m lane if nothing stands in it. The side
walkways are the risk: each is filled for 2 m by a pillar beside the salon that
holds the upper deck up, so the way past is a step into the salon and back out,
and a crane pedestal stands in each at the aft deck. The tender blocks the
middle of the foredeck. Longest eye-to-eye line between two Gubs on the main
deck: **19.0 m** (a foredeck diagonal); from any landing: **35.8 m** (the
tender's top to the sun pad). The gate holds them to 21 m and 38 m. The roof
number is long on purpose and is the price of a map that is about height: the
decks see down onto the ends of the ship, and the ends are where the cover is.
No spawn pad sees any pad of the other base.

**Over the side.** `parkour_report` grew an `overboard` row in `EXPECT`, set
only for this map. Off both ends of every row of the ground grid it marches out
to where the deck ends — under anything standing at the edge — steps a metre
further, and casts from above the rail down past the void: 54 columns, none of
which meets anything. It also asserts the void is under the lowest floor (the
swim platform, -1.0) and within 5 m of it. That is the geometric half of void
death; the other half, `MatchState` killing a Gub under `void_height`, is what
every static map already relies on.

**Capture G·U·B is declared** (D-051). Bases at (0, 0, -23) on the foredeck and
(0, 0, 20.5) on the aft deck, 43.5 m apart, `base_radius` 4. U and B at
(-2.8, 0, -0.5) and (2.8, 0, -0.5) in the salon either side of the bar; G at
(0, 6.2, 2.1) on the sun deck above them — the first letter on any map that
starts off the main floor. Eight pads, four per end, alternating bow and stern;
forward sight down their noses is 4.8-16 m. `playthrough -- yacht` and
`capture_preview -- yacht` report the layout as declared.

### Lighting
A clear morning at sea, so the brightest and bluest map: a white-gold sun 38
degrees up over the starboard bow (energy 1.2, shadowed to 90 m), a deep blue
sky that is the ambient, and a sea-coloured lower sky so the far edge of the sea
does not show a seam under the fog. The white superstructure's shaded faces go
cool blue and its lit faces stay warm, which is what separates one deck from the
one under it. The window bands are a dark blue-grey rather than black: at black
they read as doorways. `background_energy_multiplier` 1.0. Counted with PIL on
`out/yacht_pad0.png`, `yacht_pad1.png`, `yacht_pad6.png`,
`yacht_parkour_iso.png` and `yacht_top.png`: 0.00% of pixels below 8/255
everywhere; 0.11% at 255 on the top view only, which is the sun's glint on the
water.

### What changed around it
- `StaticMap.BACKDROP_GROUP`: meshes in it are left out when `preview_map`
  measures a map's bounds. Without it the sea would make the top-down frame
  2.4 km wide and move the "middle" the pads are checked facing.
- `parkour_report`'s capsule-fit test stands the capsule 2 cm up. Exactly
  touching, a step top whose height does not round cleanly in float32 (2.2 m,
  7.5 m) read as blocked while a 3.2 m deck beside it passed; the test is for
  something standing *in* the landing, not the landing itself. The ground
  sampling the sightline check did is now `_ground_points`, shared with the
  overboard check.

### What checks it
Six lines in the gate, 57 checks to 63: a playthrough on `yacht` with `also`s
that Halcyon Wake was built, its capture layout passed and was declared;
`preview_map` on its pads; and `parkour_report` on it. Renders are not
committed: `out/yacht_top.png`, `yacht_side.png`, `yacht_pad0.png`,
`yacht_pad1.png`, `yacht_pad5.png`, `yacht_pad6.png` from `preview_map`,
`out/yacht_parkour.png`, `yacht_parkour_side.png`, `yacht_parkour_iso.png` from
`parkour_report`, and `out/capture_base_yacht.png` from `capture_preview`.

Nobody has played it. Whether the flybridge is a hill worth taking or a perch
with no cover, whether the walkways are flanks or corridors, whether the camera
copes in the salon and under the 1 m overhangs, and whether the stern team's
stairs against the bow team's hop steps is fair, are for a person.

### Rejected
- **A mirrored yacht.** A hull has a bow and a stern; the two ends are balanced
  by giving each a different way up, not by pretending they are the same.
- **Enclosed interiors** — a closed salon, cabins, a wheelhouse you walk into.
  The third-person camera and a one-hit spear both play badly in rooms; the one
  roofed space is open at both ends.
- **Stairs as real steps in the collision.** The Gub has no step-up; 0.2 m
  treads are a wall to it.
- **One landing per deck.** One circle big enough for a deck promises floor
  over the rail; the report would pass and be wrong.
- **An open walkway from bow to stern.** A line along it would run from the
  shoulder of the bow to the transom, over 40 m; the pillars and pedestals are
  what keep the main deck under 21.
- **A reachable mast.** From 13 m the whole ship is a gallery.
- **Hull collision below the waterline, or a sea you can stand on.** A ledge a
  falling Gub lands on is a Gub stuck against the hull waiting for nothing.
- **A black window band.** It read as a row of doorways into rooms that are not
  there.

## D-058 — Halcyon Wake gets a sea that moves, a coast to lie off, and a wind everything agrees with
The user, on the five maps: *"one of them has the best details and lighting and
background and theme, this is the wisperhollow map, by far my favorite. All the
other maps have good structure but not the same good feel."* This is the first
of four atmosphere passes, one per map, each with its own intentional direction
rather than the island's night copied over the top of it.

Gameplay is untouched. Spawns, collision, sightlines, the jump graph, bases and
letters are exactly where D-057 left them, and the gate is 63 of 63.

**The sea was the whole map.** It was a two-triangle `PlaneMesh` with a
scrolling noise normal, and it is most of what a player can see from three of
the four decks — a yacht on a still pane of colour reads as a model on a table,
and normal-mapping does not fix that, because the eye reads silhouette before it
reads shading. It is now a displaced 96x96 grid out to 120 m with a flat skirt
to the horizon, 18,432 triangles in one draw call, running
`resources/shaders/yacht_sea.gdshader`: three deep-water sines in the vertex
shader at their real phase speeds `c = sqrt(g/k)`, four more per fragment, a
Cox-Munk sun track (one `exp`) that runs to the horizon because the flatter the
view angle the less slope a facet needs to put the sun in your eye, the hull's
foam and the shadow of her underwater body as a 2D distance field rather than as
geometry, and a body colour near-black looking straight down and Mediterranean
toward the horizon. Over the side is a death, so the water has to look like it
will kill you as well as look beautiful; the depth gradient is that.

**No water normal map, deliberately**, though it was the first thing suggested.
Neither CC0 library this project can reach ships an ocean normal set, and a
tiling normal on a plane 2.8 km across announces its repeat somewhere between
the rail and the horizon however it is scrolled. Seven analytic waves cost less
than two texture fetches, never repeat, carry their own exact derivatives, and —
the part that matters — can be faded by distance, with the lost slope variance
handed to roughness. That trade is the entire mechanism behind the sun track.

**The map ends somewhere.** Three headlands at 330, 560 and 880 m to port and
across the stern, and three other boats at anchor at 160, 260 and 640 m; all in
`BACKDROP_GROUP`, none of it collision, about 900 triangles in one draw call.
Aerial perspective does the work — the near head a grey-violet solid, the far
range a stain on the haze — and the ridge is the dark part with the foot washed
out, not the other way round, which is the difference between a headland and a
meringue. The sector the sun's track runs out through is left as empty water on
purpose: the flybridge looking down-sun is the best view on the map.

**Everything that moves in the wind agrees.** She lies head to her cable, so the
swell runs bow to stern, the ensign at the transom and the burgee at the
masthead stream aft (`yacht_cloth.gdshader`), and the cable leads forward off the
stem into the water. The ensign is also the only saturated warm colour on a map
made of white, blue and teak, and it flies over Team 2's base.

**The sky is the island's shader with different numbers.** `yacht_sky.tres`
points at `enchanted_sky.gdshader` for cirrus crossing the dome in about two
minutes, a sun disc, and a marine haze band the sea's far edge dissolves into;
stars and aurora are at zero energy. The disc does not follow LIGHT0 — it types
the same 38-degree direction the `Sun` node carries and `yacht_map.gd` hands to
the sea shader, so the disc, the shadows and the glitter are one number in three
places rather than three opinions.

**One new light, `SeaBounce`**: straight up, 0.18, unshadowed, no specular. It
can only touch downward-facing surfaces, so it cannot reach a deck, a tread or a
Gub's hat, and D-057's 38-degree deck-on-deck shadow stack — a readability
decision, not a mood one — is preserved by construction rather than by taste.

**Ambience**, in `scripts/world/maps/yacht_ambience.gd`: six gulls on six
mutually-prime circles, banked into their turns, wings beating three times then
gliding; steam off the hot tub; and audio wired exactly as `ambience.gd` does it
— named paths, the `Ambience` bus, a missing file skipped in silence. Only
`ambient_wind.wav` exists, so only it plays.

**Exposure did not move**, and that is measured rather than felt:
`background_energy_multiplier` is still 1.0, mean luminance across the eight
pads is 146-155 against the old 141-154, the 1st percentile 25-34 against 23-42,
nothing clips, and 0.07% is crushed at the worst pad. The deck is a CC0 Poly
Haven teak (`assets/maps/yacht/`, 1.7 MB, sources recorded beside it) multiplied
at load by the map's own 16-plank caulk layout, seams baked into the normal
because that is what makes raking light read the planks.

### What checks it
No new gate lines: this pass changes how the map looks and nothing about what it
promises, and the six lines D-057 added — the `yacht` playthrough, `preview_map`
on its pads, `parkour_report` for the jump graph and the overboard test — are
exactly the ones that would catch dressing that became collision or moved a pad.
63 of 63, green. Renders are not committed.

### Rejected
- **An HDRI dome.** A 2k clear-Mediterranean-morning HDRI was downloaded and
  rendered as this map's sky, and the render settled it. A photographic dome
  brings its own baked coastline — which fights the authored one, and which the
  sea plane cuts through at the trunks of its palm trees — and its own baked
  sun, which cannot be moved to 38 degrees over the starboard bow without
  canting the horizon. And it does not move, and motion is the whole thesis. One
  lesson was kept from it: its ambient made the white paint read white rather
  than blue.
- **Spray at the waterline.** She is at anchor on a flat calm.
- **A bimini over the aft terrace.** It would blind the flybridge to the sun deck.
- **Dressing ship with signal flags.** Noise across the one clean sky on the map.
- **Bobbing the hull.** Collision is built in world space at load and would not
  bob with it.
- **A transparent sea.** It would look better and would cost alpha sorting on the
  largest mesh in the map. A bad trade for an eight-player networked game.

### Left for later
`ambient_sea.wav` and `ambient_gulls.wav` are named by the wiring and do not
exist. Caustics on the white deckheads are a static up-facing fill here; the real
version is two or three `Decal` nodes projecting a drifting caustic texture
upward. The teak bake costs about 160 ms at load (build 46 -> 215 ms), behind a
loading screen; if that ever matters, ship a pre-baked 512 instead of
multiplying two textures at load.
