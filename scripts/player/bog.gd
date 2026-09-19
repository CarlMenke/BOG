class_name Bog
extends CharacterBody3D
## A player character.
##
## One of these exists per peer in a match. The peer it belongs to owns it:
## `set_multiplayer_authority(peer_id)` is called on spawn, that peer runs the
## movement code, and a `MultiplayerSynchronizer` pushes the result to everyone
## else (see docs/DECISIONS.md D-004). Remote Bogs run no input and no gravity —
## they only smooth toward what the network last said.
##
## Movement speeds here are gameplay choices, and the animation is made to fit
## them rather than the other way round. Each locomotion clip carries the ground
## speed it was authored at as metadata (`authored_speed`, recorded by the
## import from the hips' travel — D-095), and `BogAnimator` plays each one back
## at `game speed / authored speed`, so the feet stay planted at whichever of
## these speeds the clip is assigned to. Change a speed here and the playback
## rate follows; there is no number to keep in step.

signal died(killer_id: int, cause: int)
signal respawned()
signal landed(fall_speed: float)
signal jumped()
signal dived()
signal threw_spear(origin: Vector3, direction: Vector3)

## Appended to, never reordered — the ordinal is what `MatchState._apply_death`
## puts on the wire and what the kill feed switches on. LIGHTNING therefore sits
## *after* UNKNOWN rather than beside SPEAR where it belongs by meaning, because
## a tidier order would have renumbered every cause already in flight.
## Appended to, never reordered: the ordinal is what travels in
## `MatchState._do_kill` and in the kill feed, so inserting one in the middle
## would turn every older peer's lightning into a fall.
## What killed a Bog, for the feed and for the refusals.
##
## **Appended, never inserted.** These travel on the wire and are written into
## `stats` rows, so a value added in the middle would silently turn every death
## already in flight into a different kind of death — the same warning
## `Pickup.Kind` carries and for the same reason. SWORD is D-068's, and FIST is
## the feel round's: a Bog with its weapon put away still has two of them, and a
## punch is the one kind of damage in this game that no weapon did.
enum Cause { SPEAR, FALL, VOID, UNKNOWN, LIGHTNING, ARROW, SWORD, FIST }

## Full health, and the unit every damage number in the game is written in
## (D-062). A Bog starts each life on exactly this and is dead at zero.
##
## It is a constant and **not a lobby dial**, which is the whole reason the
## spear can keep its promise. `BogCombat.SPEAR_DAMAGE` is this same constant,
## so "a spear always kills" is a number rather than a branch: a spear takes a
## whole body's worth, so it kills a Bog on 100 and it kills a Bog on 3, and no
## dial the host can reach makes it less. A `starting_health` slider would
## quietly turn the spear into a two-shot the first time anybody dragged it, and
## the balance dial that actually matters — how much damage a weapon does — is
## per weapon and belongs beside that weapon (the bow brings its own).
##
## 100 rather than 1.0 because damage is authored by hand: "an arrow is 20 to
## 80" is a sentence somebody says out loud, and a bar that is 37 full is a
## number a player can be told.
const MAX_HEALTH := 100.0

## The body in a team's colour; see `set_team_tint` and D-046.
const TINT_SHADER := preload("res://resources/shaders/bog_team_tint.gdshader")
## The body mesh's node name inside `art/bog/BOG.fbx`, as `tools/import_body.gd` names it.
const BODY_MESH_NAME := "Bog"

## Backing up is slower than going forward (D-098). The user's call at the
## rebuild's second checkpoint, and what the clips wanted anyway: the backward
## cycles are authored at 0.8 and 1.5 m/s, and carrying a full run backwards
## would play them at 3.6x. At this scale a run backwards plays `RunBack` at
## 2.2x and a walk backwards plays `WalkBack` at 1.7x. Applied in
## `_handle_movement` by how far behind the facing the stick points, so a
## diagonal is scaled by the backward part of it; `BogAnimator` puts its
## backward blend points at the same scaled speeds, so a backpedal lands on its
## own clip rather than short of it.
const BACK_SPEED_SCALE := 0.6

## A BOG with a bow drawn walks (D-098). The archer set has aiming walks and
## strafes and no aiming run, and a sprint under a drawn bow would play them at
## six times their speed; a walk while aiming is also the convention of every
## third-person shooter this game borrows from. Applied in `target_speed`.
const AIM_WALKS := true

## And a BOG at **full** draw creeps (the feel round). `AIM_WALKS` takes the
## archer down to a walk the moment the string moves, which is a rule about the
## clips; this is the rule about the fight — a full draw is the shot that can
## kill in one, and the price of holding it is that you cannot also be moving
## like somebody who is not. Scaled continuously by `draw_fraction()`, so the
## cost arrives with the charge rather than at a threshold nobody can see: 2.3
## m/s at brace, 1.72 at half, **1.15 at full**.
##
## It works on every screen for free, because `draw_fraction()` answers off the
## replicated `sync_draw` on a Bog this machine does not own (D-065) and
## `target_speed()` is the one place every stance already comes out of.
##
## Below `WALK_SPEED` the aim plane has nothing between the walk ring and its
## idle, so a creeping archer blends toward `BowAim` — which is the pose a
## drawn bow moving that slowly should be in anyway.
const DRAW_SPEED_SCALE := 0.5

## What a Bog with its weapon put away travels at, as a factor on every stance
## (the feel round).
##
## **The only scale in `target_speed` that is above 1.0**, and that is the whole
## point of the key. Holstering costs you the weapon — `has_spear`, `has_bow`
## and `has_sword` all answer no for as long as it is away, and what is left is
## a 20-damage punch — so the thing it has to buy is the thing a player with
## nothing to shoot at actually wants, which is to get somewhere. A tenth is
## small enough that it is not a second sprint and large enough to be worth the
## press across a map: 5.94 m/s against 5.40 running, which is the length of
## Lantern Wharf about half a second sooner.
##
## It works on every screen for free, for `DRAW_SPEED_SCALE`'s reason:
## `is_holstered()` answers off a replicated bool on a Bog this machine does not
## own, and this is the one place every stance already comes out of.
const FISTS_SPEED_SCALE := 1.10

## What a Bog travels at while a sword slash is playing (the feel round).
##
## The sword's *commitment* used to be total — `is_spinning()` drops the stick
## entirely for 1.867 s — and the slash chain is the opposite trade: you keep
## the stick, you keep the camera, you keep the jump, and what the swing costs
## is a sixth of your speed while the blade is out. Applied here rather than in
## `_handle_movement` so that it composes with the crouch, the Elder's boost and
## the carrier's tax the way every other scale does, and so a remote Bog's
## animator sees the same slowed locomotion plane its owner does.
const SLASH_SPEED_SCALE := 0.85

## How fast the Bog actually moves. Chosen for how the game plays, not for what
## the clips were made at: walking is brisk, sprinting is nearly twice that, and
## crouching is slow enough that choosing it costs you something. Each of these
## is a blend point in the animator's locomotion space, so a Bog travelling at
## exactly one of them is running exactly one clip at a rate that plants its
## feet; in between, two cycles are blended.
const WALK_SPEED := 2.3
const RUN_SPEED := 5.4
const CROUCH_SPEED := 1.6

## Gravity is 24 m/s² (project setting), which is deliberately about 2.4x real:
## it keeps jumps short and readable rather than floaty. 9.0 m/s of launch under
## that gravity is a 1.69 m apex — just under the Bog's own height.
const JUMP_VELOCITY := 9.0

const GROUND_ACCELERATION := 48.0
const GROUND_FRICTION := 42.0
## Air control is real but weak: enough to adjust a jump, not enough to make
## mid-air dodging the dominant way to avoid a spear.
const AIR_ACCELERATION := 12.0
const AIR_FRICTION := 1.5

## Bunny hopping (D-052). A jump used to throw its speed away twice: in the air,
## AIR_ACCELERATION pulled anything above `target_speed` back down to it, and on
## the first ground frame GROUND_ACCELERATION (0.8 m/s a tick) scrubbed the rest
## before a re-jump could fire. Now speed you already have is *kept* — steered,
## not cut — in the air and for LANDING_GRACE after touching down, and a jump
## fired inside that grace while holding roughly the way you are travelling adds
## HOP_GAIN of your target speed, up to HOP_SPEED_CAP of it. A run of well-timed
## hops climbs from 5.4 m/s to 7.0 in eight hops after the first jump; miss one and the ground
## takes the bonus back in a couple of frames.
##
## Every number is a fraction of `target_speed`, so the Elder's boost and the
## capture carrier's slowdown scale the cap with them and nothing else has to
## know. The take-off *vertical* speed is untouched: `jump_velocity` is what the
## animator scrubs the arc by (D-040).
##
## The cap, as a multiple of the Bog's current target speed. The thing to tune
## after a playtest: 1.0 turns the gain off (momentum is still kept, but nothing
## is ever above target to keep).
const HOP_SPEED_CAP := 1.3
## Added per timed hop, as a fraction of target speed.
const HOP_GAIN := 0.04
## How long after touching down the ground leaves speed above target alone. Six
## ticks: long enough for a press made on landing (or buffered by JUMP_BUFFER
## just before it) to fire, short enough that standing still is not a hop.
const LANDING_GRACE := 0.1
## A landing only counts as the end of a hop after this long in the air, so the
## floor flickering under a Bog running over bumps is not a string of landings.
const HOP_MIN_AIRTIME := 0.2
## The hop only pays if you are already moving at near your target speed, and
## pressing within ~45 degrees of the way you are going.
const HOP_MIN_SPEED := 0.9
const HOP_ALIGNMENT := 0.7

## The great sword's spinning advance, in metres: the swing clip's own
## authored travel, read off its metadata by `BogAnimator` (D-098). The body
## produces the metres the clip was drawn covering, which is what keeps the
## feet planted through the swing for exactly the reason a run cycle's rate
## keeps them planted through a run. `tools/combat_range.tscn -- sword` reads
## the distance a standing swing actually covers and checks it against this.
static var SPIN_ADVANCE: float = BogAnimator.SWING_ADVANCE

## What a swing adds to the momentum budget, as a fraction of target speed
## (D-068).
##
## **The same budget the bunny hop uses, under the same ceiling.** `_begin_spin`
## is `_hop_gain` with a sword in it: it reads the speed the body already has,
## adds this much of `target_speed()`, and clamps to `hop_speed_cap()` — the one
## `HOP_SPEED_CAP` number that already has a decision record and a smoke check
## behind it (D-052). So hop and spin compose rather than competing, and there is
## no second speed system to have a second ceiling.
##
## Five times `HOP_GAIN`, and the ratio is the price of each: a hop costs
## nothing but timing and can be fired every 0.35 s, while a swing costs 1.867 s
## of committed, unsteerable, undodgeable animation. Eight hops take a Bog from
## 5.4 m/s to the 7.02 cap in about five and a half seconds; six swings take it
## there from a standing start in about eleven, and either way the ceiling is the
## same one.
const SPIN_GAIN := 0.20

## The dive: jump again while already in the air and the Bog commits to a leap
## along whichever way it is trying to go. Once per airtime — that is what makes
## it a decision rather than free flight. The animator shows it with the
## `JumpTwo` clip, scrubbed by where the body is in its arc, and lands it with
## that clip's ground roll; see `BogAnimator`.
##
## The forward speed is deliberately well above RUN_SPEED: a dive that moved you
## no faster than running would be a worse way of running. Air friction is
## almost nothing (AIR_FRICTION 1.5), so this is very close to how fast the Bog
## is still travelling when it lands.
const DIVE_FORWARD_SPEED := 9.5
## Modest on purpose. The dive is meant to carry you *across* a gap, not over the
## treeline: at 24 m/s² this is 0.6 m of extra height on its own, and enough to
## keep the Bog in the air long enough for the leap to read.
const DIVE_UP_VELOCITY := 5.4

## A jump pressed this long after walking off an edge still counts.
const COYOTE_TIME := 0.12
## A jump pressed this long before landing fires on touchdown.
const JUMP_BUFFER := 0.14

## The slide. Its duration is set by the clip and not by taste: `Slide` puts the
## hips on the floor from 0.43 s and keeps them there until 1.13 s, so a slide
## the physics ends at 1.0 s ends while the body is still down, and the
## animator's fade-out lands on the clip's own stand-up. A slide that outlasted
## the low part of the clip would stand the Bog up and keep it sliding.
const SLIDE_SPEED := 4.0
const SLIDE_DURATION := 1.0
const SLIDE_FRICTION := 2.8
## Sliding has to be worth doing and worth stopping: you must already be moving
## near a run to enter one, and you cannot re-enter immediately.
##
## **Sprint is not part of the entry** (the feel round). It used to be, and the
## effect of asking for both keys was that nobody ever slid: the sprint key is
## held all the time and the crouch key is the one a player presses on purpose,
## so the move looked like it needed a chord. What actually makes a slide a
## decision is the speed floor and the cooldown, both of which are still here —
## crouch under `SLIDE_ENTRY_SPEED` is a crouch, crouch over it is a slide, and
## a walking Bog cannot slide at all.
const SLIDE_ENTRY_SPEED := RUN_SPEED * 0.7
const SLIDE_COOLDOWN := 0.9

## Jumping out of a slide is its own move, not a jump that happens to interrupt
## one (the feel round). The slide is already a commitment — a fixed direction,
## a fixed duration, a cooldown — and paying all of that to arrive at an
## ordinary hop is why the slide was worth nothing but its hitbox. The exchange
## is a fifth again of horizontal speed along the way the slide was already
## going, and a little more lift so the extra speed has somewhere to go.
##
## The horizontal is taken from `max(current, SLIDE_SPEED)` rather than from
## the velocity alone: `SLIDE_FRICTION` has been eating the slide since it
## started, so a jump at the end of a long one would otherwise be worth less
## than a jump at the start of it and the move would have a right moment that
## nobody could see.
const SLIDE_JUMP_SPEED_SCALE := 1.2
const SLIDE_JUMP_IMPULSE_SCALE := 1.12

## After landing from a dive the Bog is committed to its roll: movement input is
## ignored for this long, nothing but ROLL_FRICTION acts on the horizontal
## velocity, and jumping is refused but not lost (`_tick_timers` holds the
## buffered press until the lock ends) — so the body carries through the roll
## instead of skating across the floor in a tumbling pose. It is a gameplay rule
## as much as a cosmetic one: the dive is fast (DIVE_FORWARD_SPEED 9.5 m/s) and
## this is what it costs you at the far end. 0.45 s is a little under the 0.48 s
## of `JumpTwo` the animator plays as the roll, so control is back before the
## animation finishes rather than after it.
##
## It is a *ground* rule: the lock ends the moment the feet leave the floor
## (`_tick_timers`), so a Bog that rolls off a ledge gets its air control and
## AIR_FRICTION back at once instead of falling deaf to the stick with
## ROLL_FRICTION dragging on it.
##
## Set to 0.0 to turn the rule off completely: every use of it is guarded, so at
## zero the landing behaves exactly as it did before the rule existed.
const ROLL_LOCK := 0.45
## And only an airtime that lasted at least this long is rolled out of. The
## animator declines to play its roll one-shot below the same threshold —
## `BogAnimator.LAND_MIN_AIRTIME` *is* this constant — so without the guard here
## a dive that clipped the ground after a tenth of a second would take movement
## away for 0.45 s with no roll animation to explain it: the Bog would stand in
## a locomotion pose, deaf to the stick. One number, one rule, both sides.
const ROLL_MIN_AIRTIME := 0.20
## Deliberately much less than GROUND_FRICTION (42): the point is that the body
## keeps travelling.
const ROLL_FRICTION := 10.0

## The collision capsule follows the *pose the clips actually strike*, which is
## not the pose the word "crouch" suggests. Measured off silhouettes of the
## built asset: Idle stands 1.49 m (a hunched boxer's guard), CrouchWalk 1.51,
## Run 1.41 and Walk 1.73 — the new crouch is not lower than the new idle at
## all. So a 0.95 m crouch capsule, which is the right number for a character
## that folds up when it crouches, would leave the whole chest and head of this
## one outside its own hitbox: a crouching Bog could not be speared in the
## head. 1.35 m keeps everything but the antennae inside, and still sits 0.20 m
## below STAND_HEIGHT so crouching under an overhang works.
##
## The old asset had the same bug in a smaller size — 0.5 m of head outside its
## 0.95 m crouch capsule — which is why this is stated in metres of measured
## silhouette rather than as a fraction of standing height.
const STAND_HEIGHT := 1.55
const CROUCH_HEIGHT := 1.35
## The slide is the one pose that really is prone: `Slide` puts the hips at
## 0.17 m and keeps the body flat until ~0.95 s, and the whole mesh is under
## 0.73 m through it (measured). A sliding Bog is therefore genuinely a low
## target, and this is the height that says so. `_apply_capsule` rounds it up to
## 0.77 — a 0.38 m radius capsule cannot be shorter than its own two
## hemispheres — which is close enough to the pose that it is not worth
## narrowing the body for.
const SLIDE_HEIGHT := 0.75
const CAPSULE_RADIUS := 0.38
## Blend units per second, for both the crouch and the slide blend: a full
## stand-to-crouch takes 1/9 s either way.
const CROUCH_TRANSITION := 9.0

## How fast the body swings to face where it is going. Fast enough to feel
## responsive, slow enough that the turn reads as a turn.
const TURN_SPEED := 14.0

## **Idle yaw slack**: how far the view may swing off a Bog that is only looking
## around before the body is dragged after it. See `_face`.
##
## The owner, after the first evening on the PvP rig: *"if they are standing
## still, not moving at all and just moving the camera, then let them get it a
## little further around before it starts moving the character, not all the way
## just further, and then if they start moving, smooth it back to inside the
## previous clamp."* That is Fortnite's standing behaviour, and it is the answer
## to the one cosmetic gap `docs/PLAN_CAMERA.md` knowingly left open: with the
## body welded to the camera, a Bog that stands still and looks around slides
## its feet across the floor for every degree of it, because this repo has no
## turn-in-place clips to hide the turn with. The slack does not remove the
## slide — it removes the *occasion* for it. A look round the room is now a look
## round the room, and the feet only move when the player has actually
## re-pointed the Bog.
##
## 60 degrees because that is what a look costs: a glance over either shoulder,
## a check of a flank, reading a room, all sit inside it, and anything wider is
## a turn the player meant. Past the edge the body is dragged so that it sits
## exactly *on* the edge rather than snapping onto the view — the slack travels
## round with you, which is what makes it read as a shoulder and not a dead
## zone you fall out of.
const YAW_SLACK := 1.047
## Radians a second the slack closes at once the Bog is doing anything but
## standing there. The second half of the owner's sentence, and it is a **rate
## and not a switch** for the reason that sentence gives: dropping the slack to
## zero the moment a key goes down would leave the body up to 60 degrees off the
## view with nothing but `TURN_SPEED` between them, and 60 degrees at 800 deg/s
## is an 0.075 s snap — the Bog would *flick* onto the camera on the first step
## of every walk, which is the jerk the slack was bought to avoid. At 4 rad/s
## the whole 60 degrees is handed back over 0.26 s, slower than the body could
## turn and therefore the thing you actually see: the Bog squares up as it sets
## off, one motion, and is locked to the view again by the time it is moving.
const SLACK_CLOSE_RATE := 4.0
## Horizontal speed under which a Bog with no key down counts as standing still
## — the slide's own 0.35 m/s, for the same reason it uses it: below that a
## velocity is the tail of a stop and not travel.
const IDLE_SPEED := 0.35

## Magnet. Once caught, the Bog is dragged toward the magnet until it is inside
## MAGNET_GRIP metres, then pinned there for the rest of the hold. Jumping is
## blocked for the duration — the magnet is meant to feel like being grabbed, and
## an escape hatch would make it never worth throwing.
const MAGNET_GRIP := 1.1
const MAGNET_MAX_SPEED := 11.0
const MAGNET_PIN_DAMP := 26.0

## Physics layers, from project.godot.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_DEPLOYABLE := 8

@export var peer_id: int = 1

## Replicated state. The owning peer writes these; everyone else reads them.
@export var sync_position: Vector3
@export var sync_yaw: float
@export var sync_velocity: Vector3
@export var sync_crouching: bool
@export var sync_sliding: bool
@export var sync_grounded: bool
## Bumped once per dive. A counter and not a flag, because a flag that goes true
## and false again inside one replication tick arrives as no change at all, and
## two dives in a row have to be two dives on every screen. `BogAnimator` watches
## it, so remote Bogs fire the dive from the same value their own client wrote.
@export var sync_dive_serial: int = 0
## How far this Bog's bow is drawn, or **-1 for "not drawing"** (D-065).
##
## One float and not a float beside a flag, which is the whole of why the charge
## can be trusted on somebody else's screen. A bow that is 40% drawn and a bow
## that is not being drawn at all are two states, and with two fields they are
## two packets that can arrive in either order — so for one tick a Bog would be
## "not drawing, 40%" or "drawing, 0%", and both of those are a pose. Out of
## band is the cheapest way to say "neither": `draw_fraction` reads 0 from it
## and `is_drawing` reads false, off the one number, on every peer.
##
## Written by the owner like every other `sync_*` field here. The charge is not
## health — it is an input the player is holding down, and the peer holding it
## is the only one that can know. What the *host* does with it is check it: the
## claim that arrives with a loose is clamped to the draw it has been watching
## (`BogCombat._host_loose_arrow`), exactly as a throw's origin is clamped to
## somewhere near the Bog.
##
## ON_CHANGE, so a Bog standing about sends nothing and a drawing one sends a
## float a tick. That is the price of the tell and it is the smallest price
## there is: no serial, no start time, no clock to keep in step — a peer that
## misses a packet is corrected by the next one and is wrong about a pose for a
## sixtieth of a second.
@export var sync_draw: float = -1.0
## Where this Bog is aiming, above or below the horizon, in radians (D-066).
##
## The one thing about a Bog that the body itself has never had. `body_yaw` is
## replicated because the body turns; nothing pitches, because a
## `CharacterBody3D` standing on a floor has no business leaning — so until the
## torso started tracking the crosshair there was nothing here to send.
##
## Read off the camera boom and not off `_view_basis`: the rig yaws and the boom
## under it pitches, and the basis the camera hands down for movement is the
## rig's, which is flat on purpose (`_wish_direction` would otherwise walk a
## Bog into the floor when it looked down).
##
## ON_CHANGE and one float, for D-065's reasons exactly: a Bog that is not
## looking around sends nothing, one that is sends a float a tick, and a peer
## that misses a packet is wrong about a torso for a sixtieth of a second. It
## is deliberately **not** on the always-packet beside `sync_yaw`, because yaw
## moves a body through the world and this moves a pose.
@export var sync_aim_pitch: float = 0.0
## Bumped once per ordinary jump, for the same reason and read the same way.
## Nothing has to *fire* on a jump — the animator scrubs the jump clip by where
## the body is in its arc, and leaving the ground with a positive vertical
## velocity is already the whole story — but the serial says which kind of
## airtime this is, which is what decides between the landing absorb and the
## dive roll. It also arrives on time when `sync_grounded` does not: a remote
## Bog whose grounded flag is a tick late still starts its airtime on the frame
## the jump happened.
@export var sync_jump_serial: int = 0
## Bumped once per **slide** jump, in the same tick as `sync_jump_serial` and
## never on its own (the feel round).
##
## A second counter rather than a flag beside the first, for exactly D-098's
## reason: a bool that went true and false again inside one replication tick
## would arrive as no change at all, and two slide jumps in a row have to be two
## slide jumps on every screen. A second counter rather than a *kind* packed
## into the first, because the jump serial is the news that an airtime opened
## and nothing else in this game should have to know how it is encoded to read
## it; the animator reads this one beside it and picks the leap clip.
##
## ON_CHANGE and in the same replication config as the jump serial, so the two
## arrive in one packet and the animator never sees an airtime open without
## knowing which kind it was.
@export var sync_slide_jump_serial: int = 0
## Whether this Bog has put its weapon away (the feel round).
##
## **Written by the owner and read by everybody, including the owner**, which is
## what makes it one field rather than a local flag beside a replicated one the
## way the draw is (`draw` / `sync_draw`). The draw needs both because the
## charge is a continuous quantity the owner computes every frame and everyone
## else samples; this is a toggle the player presses, so the owner writing
## straight into the replicated field and reading it back is one source of truth
## rather than two that could disagree for a tick.
##
## ON_CHANGE, beside `sync_draw` and for its reasons: a Bog that never presses H
## sends nothing, and the one packet a press costs is a bool. There is no "true
## and false again inside one tick" hazard that would want a serial instead
## (D-098) — the two edges are a player's two keypresses and cannot land on one
## frame.
##
## What reads it: `has_spear`/`has_bow`/`has_sword` and the five `_wants_*` in
## `BogCombat`, so the prop leaves both fists on every screen; `target_speed`
## below, for `FISTS_SPEED_SCALE`; and the HUD's weapon tile, which greys the
## photograph and puts H on the cap. `BogCombat` owns the *decision* — when the
## toggle may be made — exactly as it owns the emote's.
@export var sync_holstered: bool = false
## Which life of this Bog the snapshot it rides in was taken in. See `life`.
##
## Replicated ALWAYS, in the same packet as `sync_position`, and that is the
## whole point of it: a counter on its own reliable channel would arrive on a
## different schedule from the position it is meant to vouch for, and the pair
## has to be judged together or not at all.
@export var sync_life: int = 0

## Which life this copy of the Bog is in. Set only by `revive_at`, from a number
## the host hands out (D-043) — never counted up locally, so every peer's copy
## of one Bog agrees about it however many times a testbed revives it by hand.
##
## `_follow_network` ignores any snapshot whose `sync_life` is not this. That is
## the fix for a player coming back from a death holding what they died on: the
## host revives its copy of a remote Bog at the pad, but the owner's client is
## still dead until the reliable `_do_respawn` reaches it, and every snapshot it
## sends in the meantime says "I am lying on my corpse". Followed, those put the
## host's live copy back on its own loot for a round trip, and the `Pickup`
## there handed it over. They carry the life before, so now they are refused.
var life: int = 0

var display_name: String = "Bog"
## Everything in the Bog's two hands. Hidden and shown off the one gate in
## `BogCombat`.
var held_gear: HeldGear
## The local half of `sync_draw`, written by `BogCombat` on the owning client
## only and published from `_publish` like every other owner-authored value.
## -1 while nothing is being drawn.
var draw: float = -1.0
## True while this Bog is playing the emote.
##
## **Written by `BogCombat` on every peer**, from the relay rather than from a
## `sync_` field, which is the one thing about this flag worth arguing. A start
## and a stop are two *events* the animator cross-fades between; a bool sampled
## by the synchroniser would arrive somewhere inside the fade on a machine whose
## packet was late, and a peer that dropped the packet carrying `false` would
## dance forever. The throw's wind-up is relayed for the same reason and by the
## same road (D-024), and this rides beside it.
##
## Read by the animator, by `_read_input` below and by nothing else. It lives on
## the body rather than in the combat node because the two things it changes —
## whether this Bog walks, and whether it is still dancing after a hit — are both
## written here.
var emoting: bool = false
## The robe, while this Bog is the Elder (D-038), and null the rest of the time
## — which is almost always. Built on demand rather than in `_ready` like the
## spear, because seven of every eight Bogs in a match will never wear one and a
## hidden second skinned mesh on every rig is 4,352 triangles of nothing.
var elder_robe: ElderRobe
## The gold card over this Bog's head while it carries a letter, for everyone
## but its owner (D-050). Switched by whoever decides what is carried.
var carrier_marker: CarrierMarker
## The capture performance: the letter this Bog is pulling out of the air and
## down into its pouch, while a **timed** hold is running (the letters round).
##
## Beside the marker and the gear rather than inside either, because it is a
## third answer to a different question. The marker says *who* is carrying, over
## the head and through walls; the gear says what is *in the hands*; this says
## what the hands are *doing*, in world space between them. It watches
## `MatchState` itself and needs nobody to switch it.
var capture_rig: CaptureRig
var team: int = MatchConfig.TEAM_NONE
## Which weapon this Bog brought to the match, as a `Loadout.Weapon` (D-069).
##
## Seeded by whoever builds the Bog — `MatchState._create_bog` off the roster,
## `BogBackdrop._apply_slot` off the lobby's, a testbed by hand — and read by
## `BogCombat`, which gates `has_spear`, `has_bow` and `has_sword` on it.
##
## **A field on the body rather than a question asked of `Net` each time**, which
## is the opposite of how `is_elder()` and `is_holding_letter()` are done, and
## the difference is what the value *is*. Those two are match state that changes
## under a Bog while it stands there, so a copy of either would be a second
## opinion about who is dangerous. A weapon is fixed the moment the host presses
## Start and cannot change for the rest of the match — and the Bogs in the lobby
## ring have peer ids that are in no roster at all (`BogBackdrop`), so a lookup
## would have nothing to find for the very Bogs this feature is most visible on.
## It is therefore `team`'s kind of value and gets `team`'s treatment: set once,
## beside the plate and the tint, from the row the peer already has.
##
## **"Cannot change" is a rule of the lobby, not of this field** (D-115). The
## practice range's weapon racks write it mid-match and repaint the hand in the
## same frame, because nothing here forbids it: `carries()` re-reads it every
## time it is asked and `HeldGear` preloads all four models. What stays locked
## is the *client's* route to it — `Net.set_weapon` is still refused while
## `match_running`, which is what D-069 actually bought. A rack is the host
## deciding, through `MatchState.set_weapon`, and it writes the roster row too
## so a respawn keeps what you picked up.
var weapon: int = Loadout.DEFAULT
## The body's own skinned mesh out of `BOG.fbx`, found once in `_ready` before
## anything else is hung off the skeleton — so never the spear, and never the
## robe (D-046). Null only on a rig a re-import has broken.
var body_mesh: MeshInstance3D
## This Bog's copy of the team-colour material, made the first time it is
## tinted and reused after that. Null on a Bog that has never been on a team.
var _tint_material: ShaderMaterial
## The recolour skin this Bog wears, if any (D-100): the texture, and the plain
## material carrying it for a Bog with no team colour.
var _skin_texture: Texture2D
var _skin_material: Material
var alive: bool = true
## What is left of this Bog, from `MAX_HEALTH` down to zero (D-062).
##
## **The host owns this number and every copy of it is a copy of the host's.**
## It is deliberately not one of the `sync_*` fields above: those are written by
## the peer that *owns* the Bog, and health is the one thing about a body its
## owner does not get a vote on. It travels instead on
## `MatchState._do_damage`, an `@rpc("authority")` from peer 1, the same road
## every other host decision takes (D-004, D-024).
##
## It lives on the body rather than in the `stats` row beside kills and deaths,
## and there is only one of it. The row is the match's ledger — what a player
## has scored and how many lives they have left, kept across deaths — while
## health belongs to the Bog standing in the world: it is what the bar over its
## head draws, it dies with the body and it comes back with `revive_at`. A
## second copy in the row would be a copy waiting to disagree with this one.
var health: float = MAX_HEALTH
## Set while the round is starting or just after a respawn; blocks damage.
var invulnerable_until: float = 0.0

## Movement intent for this frame. Filled from the keyboard in `_read_input`
## when this Bog is the local one, and set directly by the testbeds that script
## a Bog through a pose — see `reads_local_input`.
var input_direction: Vector2 = Vector2.ZERO
var wants_sprint: bool = false
var wants_crouch: bool = false
## Is the aim button down this frame? `BogCamera` reads the same key and answers
## `is_aiming()` off it, and this is deliberately a second read rather than a
## call into the rig: `_face` wants it on the same tick as `input_direction`, it
## is only ever asked on the Bog we own, and a body that had to reach up into
## its own camera to find out whether it may stand still would be the dependency
## pointing the wrong way. See YAW_SLACK — a player lining up a shot is not
## standing still, however still they are.
var wants_aim: bool = false
## False on a Bog whose movement is being driven by something other than the
## player: `tools/sandbox.gd` walks one through scripted poses for a snapshot,
## and reading an empty keyboard over the top of that would zero it every frame.
var reads_local_input: bool = true
var body_yaw: float = 0.0
## How far the view is currently allowed to be off `body_yaw` before the body
## follows it: `YAW_SLACK` while this Bog is only looking around, closing to
## zero at `SLACK_CLOSE_RATE` the moment it does anything else. See `_face`.
##
## Local only, and there is nothing to replicate: what other peers need is where
## the body ended up, and that arrives on `sync_yaw` already slacked.
var _yaw_slack: float = 0.0
## This Bog's animation tree, found the first time `_face` needs it and kept.
## The body asks it exactly one question — `is_throwing()`, which is true
## through a wind-up, a cast and a loose — and asking the scene tree for a child
## by name every physics tick to get it would be a lookup a frame for a node
## that never moves.
var _animator: BogAnimator

var _coyote: float = 0.0
var _jump_buffered: float = 0.0
## Spent by the dive, returned by touching the ground.
var _air_jump_spent: bool = false
var _slide_time: float = 0.0
var _slide_cooldown: float = 0.0
## Counts down through the roll after a dive landing. See ROLL_LOCK.
var _roll_lock: float = 0.0
## Counts down on the ground after a landing. See LANDING_GRACE.
var _landing_grace: float = 0.0
## How long the Bog has been off the ground, in seconds, reset on touchdown.
## Read by `_detect_landing` to decide whether an airtime was long enough to be
## worth rolling out of — see ROLL_MIN_AIRTIME.
var _airtime: float = 0.0
var _crouch_blend: float = 0.0
## How crouched the *pose* is, which is the same number on the ground and is
## allowed to rise in the air. See `_handle_crouch` and `crouch_pose`.
var _crouch_pose: float = 0.0
## How prone the body is, on top of the crouch blend. See `pose_height`.
var _slide_blend: float = 0.0
var _was_grounded: bool = true
var _fall_speed: float = 0.0
## Set by the camera each frame, and the one input the whole PvP rig is built
## on: movement is relative to where you are looking, and so is the *facing* —
## see `_face`. Flat, always; the pitch travels beside it as a number.
var _view_basis: Basis = Basis.IDENTITY
## The view's pitch on the Bog we own, handed down by `set_view_basis`. The
## local half of `aim_pitch()`, exactly as `draw` is the local half of
## `draw_fraction()`.
var aim_pitch_local: float = 0.0

var _magnet_centre: Vector3 = Vector3.ZERO
var _magnet_strength: float = 0.0
var _magnet_until: float = 0.0

## When the great sword's spin ends, or 0 for "not spinning" (D-068).
##
## **Kept on every peer**, unlike `_roll_lock` and `_landing_grace` next to it,
## and that is deliberate: this is the one movement clock in this file that
## something outside the body has to be able to ask about a Bog it does not own.
## `BogCombat` draws the sword into the fists for exactly as long as this is
## running, on all eight screens, and `has_spear()` refuses a throw for exactly
## as long too — so a second clock in the combat node would be a second opinion
## about whether there is a sword in that hand. One clock, on the body, started
## on every machine by the same relay that starts the animation.
##
## The other two fields are the *local* half and are written only on the copy
## whose owner is swinging, for the reason everything about movement is
## (D-004): the host cannot push a body it does not own, and a remote Bog's
## advance arrives the way all its motion does, through `sync_velocity`.
var _spin_until: float = 0.0
var _spin_direction: Vector3 = Vector3.ZERO
var _spin_speed: float = 0.0
## The slash chain's two clocks, both run on **every** peer for the spin's
## reason (D-068): what they decide is what is in the fists and how fast the
## body travels, and both of those have to be the same answer on eight screens.
##
## Two and not one because they answer two different questions. `_slash_until`
## is the clip — the window between `swing_N` and `end_N` — and it is what
## `SLASH_SPEED_SCALE` and the animator's own timing hang off. `_chain_until` is
## that plus the grace a second click is still accepted in, and it is what keeps
## the great sword in the fists *between* two slashes: without it the blade
## would blink out for the 0.15 s a player is deciding whether to swing again.
var _slash_until: float = 0.0
var _chain_until: float = 0.0
## Whether the spin was still running last tick, so the frame it *ends* can open
## the landing grace. See `_tick_timers`.
var _was_spinning: bool = false

## The floating name, and since D-062 the health bar under it. Held rather than
## looked up each time because `set_health` pushes to it on every hit.
@onready var nameplate: Nameplate = $Nameplate
@onready var _collision: CollisionShape3D = $Collision
@onready var _model_root: Node3D = $Model
@onready var _capsule: CapsuleShape3D = ($Collision as CollisionShape3D).shape as CapsuleShape3D


func _ready() -> void:
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD | LAYER_DEPLOYABLE
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.4
	# Slide along walls rather than sticking to them; a Bog that catches on
	# scenery during a fight feels broken even when it is technically correct.
	wall_min_slide_angle = deg_to_rad(12.0)

	add_to_group("bogs")
	body_yaw = rotation.y
	sync_position = global_position
	sync_yaw = body_yaw
	_apply_capsule(STAND_HEIGHT)
	body_mesh = _find_body_mesh()
	_equip_spear()
	_build_carrier_marker()
	_build_capture_rig()


## The mesh `tools/import_body.gd` names "Bog", under the skeleton. Looked for by name
## first, and failing that the first skinned mesh there, because this runs
## before the spear or a robe has been attached and at that moment the body is
## the only mesh the rig has.
func _find_body_mesh() -> MeshInstance3D:
	var skeleton := _model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return null
	var named := skeleton.get_node_or_null(BODY_MESH_NAME) as MeshInstance3D
	if named != null:
		return named
	for child in skeleton.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			return child
	return null


## Paint the body in `team`'s colour, or put the imported yellow back for
## `MatchConfig.TEAM_NONE` (D-046).
##
## Free-for-all is TEAM_NONE, and so is every Bog in it: the nameplate goes
## neutral there because everyone is a threat, and the body follows the
## nameplate rather than inventing a per-player colour nobody else in the UI
## uses. The colour is `Nameplate.colour_for_team`, the one the plate, the
## lobby stripe, the scoreboard and the kill feed already share.
##
## Only the body mesh. The robe is a second mesh on the same skeleton and is
## never touched: "that is an Elder" and "that is my team" are two reads, and the
## purple is the first of them.
##
## Safe to call as often as a lobby roster changes; the material is made once
## per Bog and only its colour moves after that.
func set_team_tint(new_team: int) -> void:
	if body_mesh == null:
		return
	if new_team < 0:
		body_mesh.set_surface_override_material(0, _skin_material)
		return
	if _tint_material == null:
		_tint_material = make_tint_material(body_mesh.mesh.surface_get_material(0))
		if _skin_texture != null:
			_tint_material.set_shader_parameter("albedo_texture", _skin_texture)
	_tint_material.set_shader_parameter("team_colour", Nameplate.colour_for_team(new_team))
	body_mesh.set_surface_override_material(0, _tint_material)


## A recolour skin: a texture in the body's own layout, through the team-tint
## path (D-100, design item 11). `null` puts the body's own texture back. The
## tint shader finds the skin by hue on whatever texture it is given, so a
## recoloured body still takes its team's colour where the shader's window
## still matches it, and keeps the recolour where it does not.
func wear_skin(texture: Texture2D) -> void:
	_skin_texture = texture
	_skin_material = null
	if body_mesh == null:
		return
	if texture != null:
		var plain := body_mesh.mesh.surface_get_material(0).duplicate() as BaseMaterial3D
		if plain != null:
			plain.albedo_texture = texture
			_skin_material = plain
	if _tint_material != null:
		_tint_material.set_shader_parameter("albedo_texture",
			texture if texture != null else (body_mesh.mesh.surface_get_material(0) as BaseMaterial3D).albedo_texture)
	# Put the skin on unless the body is currently drawn *through the tint*, in
	# which case the parameter written above is already the whole of the change.
	#
	# The `_tint_material != null` half is load-bearing and was missing until
	# this call had a caller (D-100 shipped `wear_skin` with nobody using it):
	# on a Bog that has never been tinted both sides of the comparison are
	# `null`, the guard read "the override is the tint material", and the first
	# skin a lobby ever put on a body was silently dropped.
	if _tint_material == null \
			or body_mesh.get_surface_override_material(0) != _tint_material:
		body_mesh.set_surface_override_material(0, _skin_material)


## The team-colour shader, carrying over what the imported body material sets so
## a tinted Bog is lit exactly like a yellow one. Static so the corpse can build
## the same thing if it ever has to.
static func make_tint_material(imported: Material) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TINT_SHADER
	var source := imported as BaseMaterial3D
	if source != null:
		material.set_shader_parameter("albedo_texture", source.albedo_texture)
		material.set_shader_parameter("roughness", source.roughness)
		material.set_shader_parameter("specular", source.metallic_specular)
		# A `Color`, not a `Vector3`: only a Color is converted to linear on its
		# way into a `source_color` uniform, and the material's getter is sRGB.
		material.set_shader_parameter("emission",
			source.emission if source.emission_enabled else Color.BLACK)
		material.set_shader_parameter("emission_energy", source.emission_energy_multiplier)
	return material


## The colour this Bog's body is currently drawn in, read back off the material
## the renderer will actually use — or null while it wears the imported one.
## For the checks.
static func tint_of(mesh: MeshInstance3D) -> Variant:
	if mesh == null:
		return null
	var active := mesh.get_active_material(0) as ShaderMaterial
	if active == null or active.shader != TINT_SHADER:
		return null
	return active.get_shader_parameter("team_colour")


## At the nameplate's own anchor, because the marker places itself above the
## plate by the plate's measurements and would drift off it from anywhere else.
func _build_carrier_marker() -> void:
	carrier_marker = CarrierMarker.new()
	carrier_marker.name = "CarrierMarker"
	var plate := get_node_or_null("Nameplate") as Node3D
	carrier_marker.position = plate.position if plate != null else Vector3(0.0, 1.8, 0.0)
	add_child(carrier_marker)


func _equip_spear() -> void:
	var skeleton := _model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	held_gear = HeldGear.new()
	held_gear.name = "HeldGear"
	add_child(held_gear)
	held_gear.attach_to(skeleton)


## After `_equip_spear`, and that order is load-bearing: the rig reads both
## hands off `held_gear` every frame, so the gear has to have found its bones
## before anything asks it where they are.
##
## On **every** Bog on **every** peer, exactly like the carrier marker above and
## for a sharper version of its reason. A capture is ten seconds of standing in
## the open with no weapon, and what it buys the other seven players is that
## they can see it happening from across a clearing — so a rig built only for
## the local player would be the vulnerability with its tell removed.
func _build_capture_rig() -> void:
	capture_rig = CaptureRig.new()
	capture_rig.name = "CaptureRig"
	add_child(capture_rig)


## Put the Elder's robe on this Bog, or take it off again.
##
## Called on **every** peer's copy from `MatchState._do_set_elder`, never from
## here: who the Elder is is match state and the host decides it (D-038). This
## is only the wardrobe.
##
## Idempotent, because the truth it reflects is replicated and a message that
## arrives twice must not leave two robes on one skeleton. `elder_robe != null`
## *is* the flag — there is no second boolean to disagree with it, which is the
## same rule the hand and the throw gate follow.
func set_elder(wearing: bool) -> void:
	if wearing == (elder_robe != null):
		return
	if wearing:
		elder_robe = ElderRobe.don(self)
		return
	elder_robe.doff()
	elder_robe = null


func is_local() -> bool:
	# `is_multiplayer_authority()` asks the peer for its own id, and there is a
	# window every time a match ends where there is no peer to ask: leaving nulls
	# `multiplayer.multiplayer_peer` immediately, and `SceneFlow` then fades for
	# FADE_OUT seconds before the arena is freed. Every Bog still in the tree is
	# processed through those frames — this one, its animator and its combat all
	# ask — which is thirteen frames of engine errors on the way out of every
	# match. `Net.local_id` already guards the same call the same way.
	#
	# Nothing is locally controlled in a session that has ended, so the honest
	# answer is no: movement and input stop, and anything reading through
	# `is_grounded`/`is_sliding` falls back to the last synced values.
	if multiplayer.multiplayer_peer == null:
		return false
	return is_multiplayer_authority()


## Called by the camera rig each frame. The view is where this Bog walks
## relative to *and* where it looks (`docs/PLAN_CAMERA.md`).
##
## It used to carry a third argument, `face_view`, which said whether the body
## should point at the camera this frame instead of at its own velocity. There
## is nothing left for that flag to decide: in a PvP third-person rig the body
## always points at the camera, so the two callers that used to raise it — a
## drawn bow and a wind-up — are now the ordinary case rather than an exception
## to it.
##
## `pitch` is the view's, and it is a second argument rather than a pitched
## `basis` because the two are wanted for opposite reasons: everything that
## reads `_view_basis` — `_wish_direction`, `_face` — wants it flat, and the
## only thing that wants the pitch is a torso that is not steering anything
## (D-066).
func set_view_basis(basis: Basis, pitch: float = 0.0) -> void:
	_view_basis = basis
	aim_pitch_local = pitch


func _physics_process(delta: float) -> void:
	if not is_local():
		_follow_network(delta)
		return
	if not alive:
		velocity = Vector3.ZERO
		_publish()
		return

	_read_input()
	_tick_timers(delta)
	_apply_gravity(delta)
	_handle_slide(delta)
	_handle_crouch(delta)
	if is_pulled():
		_handle_magnet(delta)
	else:
		_handle_movement(delta)
		_handle_jump()

	var grounded_before := is_on_floor()
	_fall_speed = -velocity.y
	move_and_slide()
	_detect_landing(grounded_before)

	_face(delta)
	_publish()


# ------------------------------------------------------------------- input ---

## The keyboard half of a Bog. The mouse half lives in `BogCamera`, and the
## ability keys in `BogCombat`, which reads them exactly like this.
##
## This belongs on the Bog rather than on whatever scene is hosting it. It used
## to live only in `tools/combat_range.gd` and `tools/sandbox.gd`, which meant
## every testbed could be walked around and the actual game could not: the arena
## had nothing playing the part those two were playing, so `input_direction`
## stayed at zero for the whole match while the abilities — which do read their
## own keys — worked perfectly, and made it look like input was fine.
func _read_input() -> void:
	if not reads_local_input:
		return
	# Typing in chat, or reading the scoreboard, is not walking into a wall.
	if SceneFlow.cursor_is_free():
		input_direction = Vector2.ZERO
		wants_sprint = false
		wants_crouch = false
		wants_aim = false
		return
	input_direction = Input.get_vector("move_left", "move_right",
		"move_forward", "move_back")
	wants_sprint = Input.is_action_pressed("sprint")
	wants_crouch = Input.is_action_pressed("crouch")
	wants_aim = Input.is_action_pressed("aim")
	var jumping := Input.is_action_just_pressed("jump")
	# **The half of the emote's stop list that is made of movement**, and it is
	# here because this is where movement is read: walking, jumping or crouching
	# ends the dance, and until one of them does, the dance is what the Bog is
	# doing instead of walking. Everything else that ends it — a hit, a death, an
	# action, a letter, leaving the ground — is in `BogCombat.refresh_emote`,
	# which runs every frame beside this one and is the only writer of the flag.
	#
	# Zeroing the input rather than gating `move_and_slide` keeps this to the one
	# place: the friction, the facing and the animator all read the same emptied
	# input the rest of the body already reads while the cursor is free, a few
	# lines above.
	if emoting:
		var combat := _combat()
		if combat != null and (input_direction != Vector2.ZERO or wants_crouch or jumping):
			combat.stop_emote()
		else:
			input_direction = Vector2.ZERO
			wants_sprint = false
			wants_crouch = false
			wants_aim = false
			return
	if jumping:
		request_jump()


## This Bog's own combat node, which owns the emote's state and its relay.
##
## The dependency runs the other way everywhere else in the project —
## `BogCombat` holds a `Bog`, and six other files reach the combat node with
## `bog.get_node("Combat")` — and it runs this way here for one reason: the
## emote is ended by things the *body* is the only reader of. Resolved on demand
## rather than cached in `_ready` so that a Bog built without a combat node (the
## lobby backdrop, some of the harnesses) is a null and not a crash.
func _combat() -> BogCombat:
	return get_node_or_null("Combat") as BogCombat


# ------------------------------------------------------------------ motion ---

func _tick_timers(delta: float) -> void:
	if is_on_floor():
		_coyote = COYOTE_TIME
		_airtime = 0.0
	else:
		_coyote = maxf(0.0, _coyote - delta)
		_airtime += delta
	# Frozen rather than decayed while the roll lock is running. `_handle_jump`
	# refuses a jump during the roll and promises it fires on the frame the lock
	# ends; a 0.14 s buffer running inside a 0.45 s lock would always be empty
	# by then, so the promise was only true for a press made in the last 0.14 s
	# of the roll. Nothing else can consume the buffer meanwhile — the Bog is on
	# the floor, so `_coyote` is full and `_handle_jump` is the only reader.
	if not is_rolling():
		_jump_buffered = maxf(0.0, _jump_buffered - delta)
	_slide_cooldown = maxf(0.0, _slide_cooldown - delta)
	# The roll is a ground move. Leave the floor mid-roll — a dive that lands on
	# a ledge and carries over its edge — and the lock ends there, or the fall
	# would have no air control and ROLL_FRICTION instead of AIR_FRICTION.
	_roll_lock = maxf(0.0, _roll_lock - delta) if is_on_floor() else 0.0
	_landing_grace = maxf(0.0, _landing_grace - delta) if is_on_floor() else 0.0
	# The frame a spin ends is a landing, as far as the momentum budget is
	# concerned (D-068). Without this the ground takes the whole advance back in
	# a couple of ticks — GROUND_FRICTION is 42 m/s², which is 0.7 m/s a tick —
	# and a swing could never be chained into another one however well it was
	# timed. With it, the sword gets exactly the window a bunny hop gets, off
	# exactly the same field: press again inside `LANDING_GRACE` and the speed
	# you built is still there to be added to, miss it and it is gone. That is
	# D-052's rule, asked by a second move, which is the whole reason the swing
	# feeds this budget instead of having one of its own.
	var spinning := is_spinning()
	if _was_spinning and not spinning:
		_landing_grace = LANDING_GRACE
	_was_spinning = spinning


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))
	# Falling faster than rising makes a jump feel decisive rather than floaty.
	if velocity.y < 0.0:
		gravity *= 1.35
	velocity.y -= gravity * delta
	velocity.y = maxf(velocity.y, -60.0)


## The crouch, in two numbers that agree on the ground and part company in the
## air (the feel round).
##
## `_crouch_blend` is the **rule**: the capsule, `is_crouching()`, the speed and
## the headroom, and it is grounded-only exactly as it always was — a crouch
## pressed in mid-air must not shrink the hitbox, must not drop the camera into
## the body and must not turn air control down to `CROUCH_SPEED`.
##
## `_crouch_pose` is only what the body **looks like**, and that is allowed to
## tuck in the air, because it is the pre-arm half of a landing slide: while
## airborne the animator's stance blend carries no weight at all (the air branch
## has it), so the whole of what this buys is the tenth of a second after
## touchdown in which the airborne blend is falling. Held crouched already, the
## body comes out of the air into a crouch and the slide's own one-shot fades
## over that; ramping from standing put one upright frame between the landing
## and the slide, which is precisely the frame that made a landing slide read as
## a stumble.
func _handle_crouch(delta: float) -> void:
	var held := wants_crouch or is_sliding()
	var target := 1.0 if held and is_on_floor() else 0.0
	if target < 0.5 and _crouch_blend > 0.0 and not _has_headroom():
		target = 1.0  # something overhead; stay down
	_crouch_blend = move_toward(_crouch_blend, target, CROUCH_TRANSITION * delta)
	_crouch_pose = move_toward(_crouch_pose, 1.0 if (held or target > 0.5) else 0.0,
		CROUCH_TRANSITION * delta)
	_slide_blend = move_toward(_slide_blend, 1.0 if is_sliding() else 0.0,
		CROUCH_TRANSITION * delta)
	_apply_capsule(pose_height())


func _handle_slide(delta: float) -> void:
	if is_sliding():
		_slide_time -= delta
		var horizontal := Vector3(velocity.x, 0.0, velocity.z)
		horizontal = horizontal.move_toward(Vector3.ZERO, SLIDE_FRICTION * delta)
		velocity.x = horizontal.x
		velocity.z = horizontal.z
		if _slide_time <= 0.0 or not is_on_floor() or horizontal.length() < 1.2:
			_end_slide()
		return

	if _can_slide():
		_begin_slide()


## Whether crouch held right now starts a slide. Its own function because it is
## asked from two places and they have to answer alike: here, on any tick the
## key is down, and from `_detect_landing`, on the tick the feet arrive — and a
## landing slide that used a second copy of this list would be the same move
## with two sets of rules.
##
## Not while rolling out of a dive: a dive lands well above SLIDE_ENTRY_SPEED,
## so without that a held crouch turns every dive landing into a slide, on top
## of a roll that is already playing.
func _can_slide() -> bool:
	return wants_crouch and not is_sliding() and is_on_floor() \
		and _slide_cooldown <= 0.0 and not is_rolling() \
		and Vector3(velocity.x, 0.0, velocity.z).length() >= SLIDE_ENTRY_SPEED


func _begin_slide() -> void:
	_slide_time = SLIDE_DURATION
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() > 0.01:
		# A slide commits to the direction you entered it in, at a fixed speed,
		# so it is a decision rather than a free speed boost.
		horizontal = horizontal.normalized() * maxf(horizontal.length(), SLIDE_SPEED)
		velocity.x = horizontal.x
		velocity.z = horizontal.z


func _end_slide() -> void:
	_slide_time = 0.0
	_slide_cooldown = SLIDE_COOLDOWN


## Remote Bogs never call `move_and_slide` and never run the slide timer, so on
## anything but the owning client these read the replicated flags instead. Left
## as `is_on_floor()` and `_slide_time`, a remote Bog is permanently airborne and
## never sliding, and the animator plays the Jump clip at everyone else forever.
func is_sliding() -> bool:
	return _slide_time > 0.0 if is_local() else sync_sliding


func is_grounded() -> bool:
	return is_on_floor() if is_local() else sync_grounded


## Is this Bog drawing a bow, and how far?
##
## Local value on your own Bog, the replicated one on everybody else's — the
## same shape `is_crouching` and `is_sliding` have, and the reason this pair is
## written this way rather than as something the animator asks `BogCombat` for.
## `BogCombat` on a remote Bog belongs to the host and has no idea what that
## player is holding down; this field does, on every machine (D-065).
## True while this Bog is playing the emote, on every machine. The animator's
## one question about it.
func is_emoting() -> bool:
	return emoting


## Is this Bog standing a letter down into its pouch — a hold with a clock on
## it, as opposed to a Capture B·O·G carry (D-131)? Asked here and not in the
## animator for the reason every other question the animator asks goes through
## the body (`is_drawing`, `is_emoting`, `crouch_pose`): `BogAnimator` names no
## autoload, so the headless `--script` tools that load it to read its tables
## (`tools/clip_check.gd`, `tools/grip_poses.gd`) can compile it in a process
## where `MatchState` does not exist.
func is_capturing() -> bool:
	return MatchState.letter_hold_is_timed(peer_id)


func is_drawing() -> bool:
	return (draw if is_local() else sync_draw) >= 0.0


## 0 at brace, 1 at full draw, and 0 for a Bog that is not drawing at all — so
## `BogAnimator.draw_time` can be handed it unconditionally and lands on the
## first frame of the window.
func draw_fraction() -> float:
	return maxf(draw if is_local() else sync_draw, 0.0)


## Where this Bog is aiming, above or below the horizon, in radians (D-066).
##
## The same two-sided accessor as `draw_fraction` and for the same reason: one
## code path for the Bog you are driving and the seven you are watching, so
## `BogAim` never asks which kind it is looking at.
func aim_pitch() -> float:
	return aim_pitch_local if is_local() else sync_aim_pitch


func is_crouching() -> bool:
	return _crouch_blend > 0.5


## How crouched this Bog's pose is, 0 to 1 — the animator's stance blend, and
## the *only* thing that reads the pre-armed crouch (see `_handle_crouch`).
## `is_crouching()` stays the question everything else asks, because everything
## else is a rule and the rules did not change: this is what the body looks
## like, not what it is allowed to do.
##
## One code path for the Bog you are driving and the seven you are watching, as
## `is_sliding` and `draw_fraction` are: `_follow_network` moves it toward the
## replicated crouch flag, so a remote Bog's pose is as crouched as its capsule.
func crouch_pose() -> float:
	return _crouch_pose


## Vertical speed, in metres per second, for anything that reads the arc rather
## than simulating it — the animator scrubs both jump clips by this and records
## a dive's launch speed from it.
##
## Locally it is just `velocity.y`. On a remote Bog it is the replicated value
## and *not* the copy in `velocity`, which is one physics tick staler: the
## synchronizer applies an incoming packet during idle processing, in the same
## pass `BogAnimator._process` runs in, and `_follow_network` only copies
## `sync_velocity` into `velocity` on the next physics tick. On the one frame
## that matters — the frame a dive's serial arrives, when the launch speed is
## read once and used for the whole leap — reading `velocity` there gives the
## speed the body had *before* it dived.
func vertical_speed() -> float:
	return velocity.y if is_local() else sync_velocity.y


## True through the ROLL_LOCK window after landing from a dive. Local only —
## nothing on a remote Bog reads it, because a remote Bog is not simulated and
## its animator fires the roll off `sync_dive_serial` instead.
func is_rolling() -> bool:
	return _roll_lock > 0.0


func _handle_movement(delta: float) -> void:
	if is_sliding():
		return
	# Rolling out of a dive: the input is dropped and only a light friction acts,
	# so the body travels with the roll animation. Steering out of a tumble would
	# make the roll a free reposition rather than the price of the dive.
	if is_rolling():
		var rolling := Vector3(velocity.x, 0.0, velocity.z)
		rolling = rolling.move_toward(Vector3.ZERO, ROLL_FRICTION * delta)
		velocity.x = rolling.x
		velocity.z = rolling.z
		return

	# The spin is committed, exactly as the roll is, and for a sharper version of
	# the roll's reason (D-068). `Swing` turns the body through a whole
	# revolution over 1.867 s while carrying it 1.712 m; the direction was
	# chosen at the click and the *animation* is drawn around travelling that
	# way. Steering out of it would be a Bog sliding sideways under a spin drawn
	# going forwards, and it would make a chainable movement tech into free
	# flight with a sword attached. So the input is dropped and the body holds
	# the speed and the heading it was given until the clip is over.
	if is_spinning():
		velocity.x = _spin_direction.x * _spin_speed
		velocity.z = _spin_direction.z * _spin_speed
		return

	var wish := _wish_direction()
	var speed := target_speed() * backward_scale(wish)
	var accelerating := is_on_floor()
	var acceleration := GROUND_ACCELERATION if accelerating else AIR_ACCELERATION
	var friction := GROUND_FRICTION if accelerating else AIR_FRICTION

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if _keeps_momentum(horizontal, wish, speed):
		# Steer, keeping the length. The chord toward the wish is always a
		# little shorter than the arc, so put the length back.
		var kept := horizontal.length()
		var steered := horizontal.move_toward(wish * kept, acceleration * delta)
		if steered.length_squared() > 0.0001:
			horizontal = steered.normalized() * kept
	elif wish.length_squared() > 0.001:
		horizontal = horizontal.move_toward(wish * speed, acceleration * delta)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, friction * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Should speed above target be left alone this tick, rather than pulled back
## to target? See HOP_SPEED_CAP.
##
## Only speed between target and the cap: anything faster (a magnet's fling, a
## robe coming off mid-air) bleeds down the ordinary way until it reaches the
## cap, so nothing is clamped in one frame. Only while pushing forward-ish — let
## go of the stick, or pull back, and the Bog slows as it always did. Only in
## the air or inside the landing grace — a Bog running on the ground is at its
## target in a couple of ticks. And not in a dive's airtime: the dive has its
## own tuned speed and roll (D-026), and keeping 9.5 m/s all the way to the
## floor would lengthen every dive rather than reward a hop.
## How much of the target speed a stick pointed `wish` gets: all of it
## forward and sideways, BACK_SPEED_SCALE of it straight back, and the blend
## between on a backward diagonal (D-098). Off `facing()`, which is the way the
## BOG looks and not necessarily the way it moves.
func backward_scale(wish: Vector3) -> float:
	return lerpf(1.0, BACK_SPEED_SCALE, clampf(-wish.dot(facing()), 0.0, 1.0))


func _keeps_momentum(horizontal: Vector3, wish: Vector3, speed: float) -> bool:
	if wish.length_squared() < 0.001 or _air_jump_spent:
		return false
	if is_on_floor() and _landing_grace <= 0.0:
		return false
	var moving := horizontal.length()
	return moving > speed and moving <= hop_speed_cap() + 0.001 \
		and wish.dot(horizontal) > 0.0


## The fastest a Bog can carry by hopping, in m/s: HOP_SPEED_CAP of whatever it
## is asking to travel at now, so the Elder and the capture carrier scale it.
func hop_speed_cap() -> float:
	return target_speed() * HOP_SPEED_CAP


## A jump fired inside the landing grace, pointed the way the Bog is already
## going at near its target speed, adds HOP_GAIN of target to that speed, up to
## the cap. Never takes speed away: above the cap it does nothing.
func _hop_gain() -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := target_speed()
	var moving := horizontal.length()
	if moving < speed * HOP_MIN_SPEED:
		return
	var wish := _wish_direction()
	if wish.dot(horizontal / moving) < HOP_ALIGNMENT:
		return
	var boosted := minf(moving + speed * HOP_GAIN, hop_speed_cap())
	if boosted <= moving:
		return
	horizontal *= boosted / moving
	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Start the great sword's spinning advance (D-068).
##
## Called on **every** peer, from `BogCombat._begin_swing`, which is the same
## call that fires the animation — so the clock and the clip start together on
## every machine and `is_spinning()` means the same thing everywhere. Only the
## owning client goes on to latch a direction and a speed, because movement is
## client-authoritative (D-004) and a remote Bog's advance arrives through
## `sync_velocity` like every other metre it travels.
##
## `seconds` is handed in rather than read from a constant here, because it is
## `BogAnimator.SWING_SECONDS` — the length of the window the clip is played
## over — and the advance and that window are two halves of one number: the
## distance is fixed by the animation and the time is fixed by the animation, so
## the speed below is the one the feet were drawn for. Reading it from the
## animator here would also point this file at the node hanging off it.
##
## **The impulse is `_hop_gain` with a sword in it.** Same reading of the speed
## already carried, same fraction of `target_speed()` added, same
## `hop_speed_cap()` ceiling — see SPIN_GAIN. Two things differ and both are the
## swing rather than the hop: there is a **floor** as well as a ceiling, because
## a Bog standing still has to produce the clip's own 0.917 m/s or its feet skate
## through the whole swing; and there is no alignment test, because a spin has
## no stick to be aligned with — it commits to the way the body was facing when
## the player asked for it.
## `advance` is the metres the clip was drawn covering over `seconds`
## (`BogAnimator.SWING_ADVANCE`), and the body produces them.
func begin_spin(seconds: float, advance: float = SPIN_ADVANCE) -> void:
	_spin_until = Time.get_ticks_msec() * 0.001 + maxf(seconds, 0.01)
	if not is_local():
		return
	_spin_direction = facing()
	# The speed the clip itself travels at. A standing swing gets exactly this
	# and so covers exactly the clip's advance; anything already moving keeps
	# what it has and is given more.
	var authored := advance / maxf(seconds, 0.01)
	var carried := maxf(Vector3(velocity.x, 0.0, velocity.z).length(), authored)
	# `maxf` on the ceiling for the floor's sake: a crouching Bog's cap is
	# 2.08 m/s and a walking one's is 2.99, both well over the authored speed,
	# but a dial dragged low enough to go under it must slow the game down
	# rather than make this one clip's feet skate.
	_spin_speed = minf(carried + target_speed() * SPIN_GAIN,
		maxf(hop_speed_cap(), authored))
	velocity.x = _spin_direction.x * _spin_speed
	velocity.z = _spin_direction.z * _spin_speed


## Is this Bog in the middle of a swing's advance? True on every peer for every
## Bog, which is the point of the clock living on all of them.
##
## Asked by four things and for four reasons: the movement above, to hold the
## heading; `_face`, to refuse to turn the body under it; `BogCombat`, to keep
## the sword in the fists and the spear out of them for exactly this long; and
## the swing gate, to refuse a second swing on top of the one that is running.
func is_spinning() -> bool:
	return _spin_until > 0.0 and Time.get_ticks_msec() * 0.001 < _spin_until


## Stop the spin now. A death, a respawn or a round reset; not a cancel a player
## can ask for, because the commitment is the price of the weapon.
func end_spin() -> void:
	_spin_until = 0.0


## Start one slash of the sword chain (the feel round). `begin_spin`'s sibling,
## and the interesting part is everything it does *not* do.
##
## The spin latches a direction, drops the stick and holds a speed for 1.867 s.
## A slash latches nothing: the body keeps its input, keeps its turning and
## keeps its jump, and all this leaves behind is two deadlines and a nudge. That
## is the whole of "less committing" expressed as code — there is no
## `_slash_direction` for `_handle_movement` to force the body along and no
## clause in `_face` to refuse a turn, because a slash has nothing to commit to.
##
## `seconds` is the clip's own window between `swing_N` and `end_N` and
## `chain_seconds` is that plus the grace a follow-up click is taken in; both
## are `BogAnimator`'s, handed in for `begin_spin`'s reason — the numbers are
## the animation's and this file carries no clip time.
##
## `step` is the metres the slash carries you forward, and it is an **impulse
## rather than a lock**: the speed it asks for is what covers `step` over the
## slash, added to whatever the body already had and clamped to the same
## `hop_speed_cap()` everything else in this file is clamped to (D-052), after
## which ordinary acceleration and friction have it back. So a slash from a
## standstill steps; a slash at a run adds nothing it was not already going to
## have; and neither is a free reposition. Owner only, because movement is
## client-authoritative (D-004) — every other peer sees the metres arrive
## through `sync_velocity` like all the rest.
func begin_slash(seconds: float, chain_seconds: float, step: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	_slash_until = now + maxf(seconds, 0.01)
	_chain_until = now + maxf(chain_seconds, seconds)
	if not is_local():
		return
	var step_speed := step / maxf(seconds, 0.01)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z) + facing() * step_speed
	var cap := maxf(hop_speed_cap(), step_speed)
	if horizontal.length() > cap:
		horizontal = horizontal.normalized() * cap
	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Is a slash's clip actually playing? True on every peer, which is why
## `target_speed` may read it: `SLASH_SPEED_SCALE` has to slow the locomotion
## plane on the seven machines watching as well as on the one swinging.
func is_slashing() -> bool:
	return _slash_until > 0.0 and Time.get_ticks_msec() * 0.001 < _slash_until


## Is a slash chain open — a slash playing, or inside the window a second click
## would continue it in? What `BogCombat._wants_sword` asks, so the blade stays
## in the fists across the whole chain instead of blinking out between slashes.
func in_chain() -> bool:
	return _chain_until > 0.0 and Time.get_ticks_msec() * 0.001 < _chain_until


## Drop both slash clocks. A death, a respawn or a round reset, exactly like
## `end_spin`.
func end_slash() -> void:
	_slash_until = 0.0
	_chain_until = 0.0


## Is this Bog holstered — its weapon put away and its fists up (the feel
## round)? Off the replicated bool, so one road for the Bog you are driving and
## the seven you are watching.
func is_holstered() -> bool:
	return sync_holstered


## How fast this Bog is travelling over the ground, in m/s. Off `velocity` on
## the copy that simulates it and off `sync_velocity` everywhere else, which is
## `vertical_speed()`'s rule one axis further — and it exists because the host
## has to be able to ask it about a Bog it does not own, when a client claims
## the sword's sprint attack.
func ground_speed() -> float:
	var v := velocity if is_local() else sync_velocity
	return Vector2(v.x, v.z).length()


## Called on the caught Bog's own client, because movement is client-authoritative
## and the host cannot simply move the body itself.
func apply_magnet(centre: Vector3, strength: float, duration: float) -> void:
	_magnet_centre = centre
	_magnet_strength = strength
	_magnet_until = Time.get_ticks_msec() * 0.001 + duration
	if is_sliding():
		_end_slide()


## Mark this copy of a Bog as being dragged about, without dragging it (D-067).
##
## `apply_magnet` is delivered to the caught Bog's *own* client, because movement
## is client-authoritative and the host must not move a body it does not own.
## That left the host unable to answer one question it now has to: "is that Bog
## moving because it chose to?" — which is the whole of the rule that ends a
## heal channel. A Bog yanked out of cover mid-drink keeps drinking, and one
## that pressed W does not, and only the host can be trusted to decide which.
##
## So `Magnet` calls this on the host's own copy of every victim as well. It moves
## nothing: `_magnet_centre` and `_magnet_strength` are untouched, so `_handle_magnet`
## has no pull to apply even if this copy ever ran it. `maxf` because the caught
## Bog may also be the host's own, where `apply_magnet` has already set a longer
## one from the same catch.
func note_pulled(duration: float) -> void:
	_magnet_until = maxf(_magnet_until, Time.get_ticks_msec() * 0.001 + duration)


func is_pulled() -> bool:
	return Time.get_ticks_msec() * 0.001 < _magnet_until


func _handle_magnet(delta: float) -> void:
	var to_centre := _magnet_centre - (global_position + Vector3.UP * 0.6)
	var distance := to_centre.length()
	if distance > MAGNET_GRIP:
		velocity += to_centre.normalized() * _magnet_strength * delta
		# Cap it, or a long pull accelerates the Bog into the magnet hard enough
		# to launch it off the far side of the island.
		var horizontal := Vector3(velocity.x, 0.0, velocity.z)
		if horizontal.length() > MAGNET_MAX_SPEED:
			horizontal = horizontal.normalized() * MAGNET_MAX_SPEED
			velocity.x = horizontal.x
			velocity.z = horizontal.z
		return
	# Arrived: pinned until the hold expires.
	velocity.x = move_toward(velocity.x, 0.0, MAGNET_PIN_DAMP * delta)
	velocity.z = move_toward(velocity.z, 0.0, MAGNET_PIN_DAMP * delta)


func _wish_direction() -> Vector3:
	if input_direction.length_squared() < 0.0001:
		return Vector3.ZERO
	var forward := -_view_basis.z
	var right := _view_basis.x
	forward.y = 0.0
	right.y = 0.0
	var wish := (right * input_direction.x + forward * -input_direction.y)
	return wish.normalized() if wish.length_squared() > 0.0001 else Vector3.ZERO


## The speed this Bog is asking to travel at, which is also the animator's
## locomotion blend position when it gets there.
##
## **The Elder's boost is applied here and nowhere else** (D-040). This is the
## one point every stance already comes out of, so walking, sprinting and
## crouching all scale by the same factor and none of them can be forgotten —
## multiplying `RUN_SPEED` at three call sites is how a sprinting Elder ends up
## faster and a crouching one ends up exactly as slow as everybody else.
##
## One thing the animator cannot follow it to: the locomotion blend space's
## fastest point *is* `RUN_SPEED`, with the `Run` clip's playback rate baked into
## it when the graph is built. So a boosted Elder runs at 7.3 m/s with its feet
## planted for 5.4 of it — up to a third of a skate, for twenty seconds, on the
## one Bog in the match wearing a robe that already says it is not ordinary.
## Rebuilding the blend space to follow a dial would be a graph that changes
## shape mid-match, which is a much worse trade.
func target_speed() -> float:
	var sprinting := wants_sprint and not (AIM_WALKS and is_drawing())
	var speed := CROUCH_SPEED if is_crouching() \
		else (RUN_SPEED if sprinting else WALK_SPEED)
	# The draw's cost is a scale like the Elder's and the carrier's, and it is
	# applied here for the same reason they are: one place, every stance. The
	# fists' gain and the slash's cost join the same product and cannot both
	# apply — a holstered Bog has no sword to slash with — so the two are two
	# factors rather than a branch (the feel round).
	return speed * elder_scale(Net.config.elder_speed_multiplier) * carrier_scale() \
		* lerpf(1.0, DRAW_SPEED_SCALE, draw_fraction()) \
		* (FISTS_SPEED_SCALE if is_holstered() else 1.0) \
		* (SLASH_SPEED_SCALE if is_slashing() else 1.0)


## `capture_carrier_speed` while this Bog carries a letter in Capture B·O·G, and
## 1.0 otherwise (D-051). Read off `MatchState`'s hold row, which exists on every
## peer, so the owner that moves the Bog and every copy that watches it agree.
## Multiplied with the Elder's boost rather than instead of it: an Elder carrying
## a card is a faster Elder and a slower carrier, both at once.
func carrier_scale() -> float:
	if Net.config.win_condition != MatchConfig.WinCondition.CAPTURE \
			or not MatchState.is_holding_letter(peer_id):
		return 1.0
	return Net.config.capture_carrier_speed


## How fast this Bog leaves the ground, in metres per second.
##
## Its own function purely so the Elder's boost has one place to be applied,
## the same way `target_speed` gives the three ground speeds one place. The dive
## is deliberately **not** boosted: `DIVE_UP_VELOCITY` is added on top of
## whatever the body is already doing, so a boosted jump already carries a
## boosted dive, and scaling it as well would multiply the same factor in twice
## — which is exactly how a modest-looking dial clears a wall nobody meant it to.
func jump_velocity() -> float:
	return JUMP_VELOCITY * elder_scale(Net.config.elder_jump_multiplier)


## How high a leap that left the ground at `launch` m/s gets, in metres.
##
## Static, and public, because the *lobby* needs it: `elder_jump_multiplier` is a
## multiplier on velocity and height goes as its square, so a slider that read
## "+25%" would be telling a host the wrong thing about the number they are
## dragging. The Match panel shows the apex instead, and it asks this rather than
## carrying an arithmetic copy of it — a 1.69 typed into a UI file is a number
## that goes quietly wrong the day gravity or `JUMP_VELOCITY` moves.
##
## The plain project gravity, not the 1.35x `_apply_gravity` uses on the way
## down: the extra pull only applies while `velocity.y` is negative, which is
## after the apex this is about.
static func apex_for(launch: float) -> float:
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))
	return launch * launch / (2.0 * maxf(gravity, 0.01))


## `multiplier` while this Bog is the Elder, and 1.0 otherwise.
##
## `elder_robe != null` **is** the flag — see `set_elder`. There is no second
## boolean to disagree with it and no call into `MatchState` either: the robe is
## put on by `_do_set_elder`, which runs on every peer, so the wardrobe and the
## rules are already the same statement. That matters here more than anywhere,
## because movement is client-authoritative (D-004) and this is read on the
## machine that owns the Bog rather than on the host.
func elder_scale(multiplier: float) -> float:
	return multiplier if elder_robe != null else 1.0


## One key, two moves. On the ground (or inside coyote time) this is an ordinary
## jump and goes through the buffer, so a press a frame early still fires on
## touchdown. Already airborne with the air jump unspent, it is the dive, and
## that has to happen *now* rather than being buffered — a dive that fired when
## you landed would be the opposite of what was asked for.
func request_jump() -> void:
	if _can_dive():
		_dive()
		return
	_jump_buffered = JUMP_BUFFER


## The dive is available once per airtime, and only from a real airtime:
## `_coyote` is still running for the twelfth of a second after walking off a
## ledge and is zeroed by a jump, so requiring it spent means the second press of
## a double-tap on flat ground jumps first and dives second, never dives twice.
func _can_dive() -> bool:
	if not alive or _air_jump_spent or is_pulled():
		return false
	return not is_on_floor() and _coyote <= 0.0


func _dive() -> void:
	_air_jump_spent = true
	_jump_buffered = 0.0
	# Where you are asking to go, or where you are looking if you are asking for
	# nothing. A dive with no direction at all would be a very expensive hop.
	var direction := _wish_direction()
	if direction.length_squared() < 0.0001:
		direction = facing()
	velocity.x = direction.x * DIVE_FORWARD_SPEED
	velocity.z = direction.z * DIVE_FORWARD_SPEED
	# `maxf` and not `+=`: diving out of a fall should still lift, and a dive off
	# the top of a jump should not stack its way into orbit.
	velocity.y = maxf(velocity.y, 0.0) + DIVE_UP_VELOCITY
	sync_dive_serial += 1
	dived.emit()


func _handle_jump() -> void:
	if _jump_buffered <= 0.0 or _coyote <= 0.0:
		return
	if is_crouching() and not _has_headroom():
		return
	# Refused, not consumed: the buffer keeps running, so a jump pressed during
	# the roll fires on the frame the lock ends rather than being swallowed.
	if is_rolling():
		return
	_jump_buffered = 0.0
	_coyote = 0.0
	var from_slide := is_sliding()
	if from_slide:
		_end_slide()
		_slide_jump()
	elif _landing_grace > 0.0:
		# The hop's gain and the slide's are the same kind of reward and a Bog
		# may not have both: a slide begun on a landing tick opens the grace as
		# well (`_detect_landing`), and stacking them would make the strongest
		# move in the game a crouch pressed on touchdown.
		_hop_gain()
	_landing_grace = 0.0
	velocity.y = jump_velocity() * (SLIDE_JUMP_IMPULSE_SCALE if from_slide else 1.0)
	# Before the emit, so anything listening already sees the new value. The
	# animator does not use the signal — it is local-only — but it does watch
	# this counter, on every peer.
	sync_jump_serial += 1
	# And a second counter for the kind of take-off, bumped in the same tick as
	# the first and read beside it: the leap clip a slide jump scrubs is not the
	# one a running jump scrubs, and which of the two it is has to reach the
	# seven animators that did not run this function (D-098's serial pattern).
	if from_slide:
		sync_slide_jump_serial += 1
	jumped.emit()


## The horizontal half of a slide jump. Along the way the slide was already
## going — the slide committed to that direction when it started, and
## `SLIDE_FRICTION` has only shortened the vector since, never turned it — so
## this is a boost and not a steer, and a player who wants to go somewhere else
## has to end the slide and turn like everybody else.
func _slide_jump() -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var direction := horizontal.normalized() if horizontal.length() > 0.01 else facing()
	var speed := maxf(horizontal.length(), SLIDE_SPEED) * SLIDE_JUMP_SPEED_SCALE
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed


func _detect_landing(grounded_before: bool) -> void:
	var grounded_now := is_on_floor()
	if grounded_now and not grounded_before and _fall_speed > 3.0:
		landed.emit(_fall_speed)
	# A landing that ends an airtime the dive was spent in is a roll landing, and
	# `_air_jump_spent` is the only record of that — so it has to be read before
	# the line below gives the dive back. The airtime has to clear
	# ROLL_MIN_AIRTIME as well, because that is the same question the animator
	# asks before playing the roll, and the two have to answer it alike: a dive
	# into a wall two frames after take-off gets neither the lock nor the roll.
	if grounded_now and not grounded_before and _air_jump_spent \
			and _airtime >= ROLL_MIN_AIRTIME and ROLL_LOCK > 0.0:
		_roll_lock = ROLL_LOCK
	# After the roll decision, so a dive landing never gets the grace: the roll
	# already owns that ground time, and a dive hop chained into a speed hop is
	# exactly what the lock is there to stop.
	if grounded_now and not grounded_before and _airtime >= HOP_MIN_AIRTIME \
			and not is_rolling():
		_landing_grace = LANDING_GRACE
	# A landing with crouch held is a slide, and it has to begin on **this**
	# tick (the feel round). `_handle_slide` would start it on the next one,
	# which is a physics tick later than the animator's first look at a
	# grounded Bog — so the landing one-shot would have already been fired and
	# the slide would fade in over the top of a stumble it was supposed to
	# replace. Started here, `BogAnimator._close_airtime` finds a Bog that is
	# already sliding and declines to land it at all.
	#
	# After the roll and the grace deliberately: a dive landing is a roll and
	# `_can_slide` refuses one, and the grace that opens here is the grace
	# `_handle_jump` will not pay out on a slide jump.
	if grounded_now and not grounded_before and _can_slide():
		_begin_slide()
	# Touching anything at all gives the dive back, including a ledge caught on
	# the way down. Tying it to `landed` instead would leave a Bog that stepped
	# gently off a rock unable to dive for the rest of the match.
	if grounded_now:
		_air_jump_spent = false
	_was_grounded = grounded_now


## **The body faces where the camera faces** (`docs/PLAN_CAMERA.md`). The mouse
## turns the Bog; the stick moves it relative to that facing.
##
## This used to turn the body toward its own *velocity* and only point it at the
## camera while a weapon was up, which is the story-game rig — Zelda, Uncharted —
## and the freedom the owner asked to have taken away. Turning it round costs the
## animator nothing: its three locomotion planes are already body-relative
## (D-066), so a backpedal and a strafe land on the clips drawn for them without
## a line changing, and `BACK_SPEED_SCALE` (D-098) stops mattering only while
## aiming and starts mattering always.
##
## Four states hold the heading instead, and the mouse still turns the *camera*
## through all of them. Each is a commitment already paid for:
##
## - **A spin** (D-068). The advance was committed at the click and the clip
##   turns the *skeleton* through a whole revolution on top of whatever this yaw
##   is; letting the camera drag the body round underneath it would slide the Bog
##   one way while it was drawn going another, and would hand a player a way to
##   re-point a swing they had already bought. The clip's own rotation is not
##   affected — it is inside the skeleton, which is why `BogCombat` reads the
##   blade off the bone attachment rather than off this yaw.
## - **A roll out of a dive**, which already refuses steering in
##   `_handle_movement` for the same reason: the tumble is the price of the dive.
## - **A slide**, which is a momentum move: the body faces the way it is actually
##   travelling, and swings back onto the camera at `TURN_SPEED` when it ends.
## - **An emote**, which is Fortnite exactly — the camera orbits the dancer and
##   the dance keeps its own heading.
##
## `TURN_SPEED` is 14 rad/s, about 800 deg/s. For a drag that is effectively
## instant; for a flick it is a frame or two behind, which reads as weight rather
## than as delay.
##
## **The one thing that is not welded: a Bog that is only looking around**
## (`YAW_SLACK`, `SLACK_CLOSE_RATE`). The rework shipped with the body on the
## camera at every instant, and named the cost itself — a standing Bog that
## looks about slides its feet, because there are no turn-in-place clips here to
## hide the turn with. The owner played it and asked for Fortnite's answer:
## *"if they are standing still, not moving at all and just moving the camera,
## then let them get it a little further around before it starts moving the
## character, not all the way just further, and then if they start moving,
## smooth it back to inside the previous clamp."*
##
## So the view is allowed 60 degrees either side of a standing body before it
## drags it, and that freedom is handed back over a quarter of a second as soon
## as the Bog does anything. "Anything" is the list below, and every entry is
## there because it is a moment the player is pointing the Bog at something
## rather than looking at it: a key down, real speed under the feet, the aim
## button, a drawn bow, a wind-up or a cast in flight, and being off the floor
## (the slack is a standing posture, and a Bog in the air that lands facing 60
## degrees off its own camera is the bug the slack would otherwise buy).
##
## Two properties are worth naming because they are what makes it feel like a
## shoulder rather than a dead zone. Past the edge the body is dragged to sit
## *on* the edge, so the slack travels round with the view instead of being a
## fixed arc the view escapes from. And the slack closes as a rate, so what the
## player sees on the first step of a walk is the Bog squaring up — one motion
## over 0.26 s, slower than `TURN_SPEED` and therefore visible as intent, where
## zeroing the slack outright would be a 60-degree flick in an eighth of that.
func _face(delta: float) -> void:
	if is_spinning() or is_rolling() or is_emoting():
		return
	if _animator == null:
		_animator = get_node_or_null("AnimationTree") as BogAnimator
	# Ordered so the cheap tests short-circuit the node question, and so that
	# each clause is one reason the Bog is not merely looking around.
	var idle := is_on_floor() and input_direction == Vector2.ZERO \
		and not wants_aim and not is_sliding() and not is_drawing() \
		and Vector2(velocity.x, velocity.z).length() < IDLE_SPEED \
		and (_animator == null or not _animator.is_throwing())
	if idle:
		_yaw_slack = YAW_SLACK
	else:
		_yaw_slack = move_toward(_yaw_slack, 0.0, SLACK_CLOSE_RATE * delta)
	var desired := yaw_towards(-_view_basis.z)
	if is_sliding():
		# A slide that has run down to nothing has no heading left to read, so
		# it keeps the one it had rather than snapping onto the view mid-slide.
		var horizontal := Vector3(velocity.x, 0.0, velocity.z)
		desired = yaw_towards(horizontal) if horizontal.length() > 0.35 else body_yaw
	else:
		# The slack in one line: the view, pulled back toward the body by as
		# much of the gap between them as the slack covers. Inside the slack
		# that is the whole gap, so `desired` comes out as `body_yaw` and the
		# body holds; past it, what is left over is exactly how far outside the
		# edge the view has gone, so the body is asked for the edge and nothing
		# more. At a slack of zero it is `desired` untouched, which is the
		# welded rig the rework shipped. `wrapf` because the gap is an angle
		# and +179 to -179 degrees is two degrees apart, not 358.
		desired -= clampf(wrapf(desired - body_yaw, -PI, PI), -_yaw_slack, _yaw_slack)
	body_yaw = rotate_toward(body_yaw, desired, TURN_SPEED * delta)
	_model_root.rotation.y = body_yaw


## Yaw that points this node's forward (-Z, Godot's convention) along `direction`.
## The Bog mesh itself is authored facing +Z and is turned 180 degrees inside
## `bog.tscn` to compensate, so `body_yaw` always means "the way the Bog looks".
static func yaw_towards(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## Unit vector the Bog is facing.
func facing() -> Vector3:
	return Vector3(-sin(body_yaw), 0.0, -cos(body_yaw))


# ------------------------------------------------------------------ shape ---

func _apply_capsule(height: float) -> void:
	# CapsuleShape3D.height is the full height including both hemispheres, and
	# the shape is centred on its origin, so it has to be lifted by half.
	_capsule.height = maxf(height, CAPSULE_RADIUS * 2.0 + 0.01)
	_capsule.radius = CAPSULE_RADIUS
	_collision.position.y = _capsule.height * 0.5


## The middle of this Bog's collision capsule, in world space.
func body_centre() -> Vector3:
	return _collision.global_position


## The point on this Bog's capsule *axis* nearest to `point`: the segment between
## the centres of its two hemispheres, in world space, at whatever height the
## stance has made it this frame.
func body_axis_nearest(point: Vector3) -> Vector3:
	var centre := _collision.global_position
	var up := _collision.global_basis.y.normalized()
	var half := maxf(0.0, _capsule.height * 0.5 - _capsule.radius)
	return centre + up * clampf((point - centre).dot(up), -half, half)


## How far `point` is from the surface of this Bog's collision capsule, and zero
## from inside it. What the Elder's blast radius is measured against (D-053):
## the body, not its feet or its middle, so a crouched Bog is a smaller target
## for it exactly as it is for a spear.
func distance_to_body(point: Vector3) -> float:
	return maxf(0.0, point.distance_to(body_axis_nearest(point)) - _capsule.radius)


## The capsule height the two stance blends currently ask for. Two nested
## lerps and not one three-way blend: the crouch blend takes standing down to
## CROUCH_HEIGHT, and the slide blend takes whatever that produced down to
## SLIDE_HEIGHT. So a slide entered from a run (crouch blend still 0) and one
## entered from a crouch (crouch blend already 1) both end up prone, and both
## the way in and the way out are smooth — including the moment a slide ends
## with crouch still held, which is a 0.6 m change of target and would be a
## visible capsule pop if it were a switch instead of a blend.
func pose_height() -> float:
	return lerpf(lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch_blend),
		SLIDE_HEIGHT, _slide_blend)


func _has_headroom() -> bool:
	var space := get_world_3d().direct_space_state
	# Started at the middle of the capsule the body currently has, so the ray
	# always begins inside the Bog. Starting it at a fixed CROUCH_HEIGHT * 0.5
	# was the same point by accident and is not any more: while sliding the
	# capsule is only SLIDE_HEIGHT tall, and a start point above its top could
	# begin inside the very overhang it is asking about and report clear.
	var from := global_position + Vector3.UP * (pose_height() * 0.5)
	var query := PhysicsRayQueryParameters3D.create(
		from, global_position + Vector3.UP * (STAND_HEIGHT + 0.12))
	query.collision_mask = LAYER_WORLD | LAYER_DEPLOYABLE
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


## Height of the eyes, used to aim the camera and to spawn projectiles. It
## follows the same blend as the capsule, so the camera drops with the body
## through a crouch and lies down with it through a slide.
func eye_height() -> float:
	return pose_height() * 0.86


# --------------------------------------------------------------- networking ---

func _publish() -> void:
	sync_position = global_position
	sync_yaw = body_yaw
	sync_velocity = velocity
	sync_crouching = is_crouching()
	sync_sliding = is_sliding()
	sync_grounded = is_on_floor()
	sync_draw = draw
	sync_aim_pitch = aim_pitch_local
	sync_life = life


## Remote Bogs are not simulated — running physics for them would fight the
## authoritative position and produce jitter. They are eased toward what the
## network last reported, fast enough to stay honest and slow enough to hide
## packet spacing.
##
## **Except when what the network last reported was a different life.** A
## snapshot from the life before is a corpse's position arriving after the
## revive, and a snapshot from the life after is the owner arriving before the
## `_do_respawn` that tells this copy it is alive; both are about a body this
## copy is not, and the copy holds still until the two agree. The first case is
## the bug (see `life`). The second is a Bog that stays hidden on its corpse a
## round trip longer, which is exactly what it is on every other screen anyway.
func _follow_network(delta: float) -> void:
	if sync_life != life:
		velocity = Vector3.ZERO
		return
	var distance := global_position.distance_to(sync_position)
	if distance > 6.0:
		# Too far to smooth: a teleport, a respawn, or a dropped burst.
		global_position = sync_position
	else:
		global_position = global_position.lerp(sync_position, clampf(18.0 * delta, 0.0, 1.0))
	velocity = sync_velocity
	body_yaw = rotate_toward(body_yaw, sync_yaw, TURN_SPEED * delta)
	_model_root.rotation.y = body_yaw
	_crouch_blend = move_toward(_crouch_blend, 1.0 if sync_crouching else 0.0,
		CROUCH_TRANSITION * delta)
	# The pose follows the same flag on a Bog this machine does not own. The
	# pre-arm is not replicated and does not need to be: what it buys is the
	# frames between touchdown and a slide, and a remote Bog's slide arrives on
	# `sync_sliding` with the animator's own fade under it either way.
	_crouch_pose = move_toward(_crouch_pose, 1.0 if sync_crouching else 0.0,
		CROUCH_TRANSITION * delta)
	# The same two blends the owner runs, off the replicated flags, so a remote
	# Bog is as hittable as the one whose screen it is being played on. The
	# combat range's dummies are remote Bogs.
	_slide_blend = move_toward(_slide_blend, 1.0 if sync_sliding else 0.0,
		CROUCH_TRANSITION * delta)
	_apply_capsule(pose_height())


# ------------------------------------------------------------ life & death ---

func is_invulnerable() -> bool:
	return Time.get_ticks_msec() * 0.001 < invulnerable_until


func grant_invulnerability(seconds: float) -> void:
	invulnerable_until = Time.get_ticks_msec() * 0.001 + seconds


## The host's word on what is left of this Bog, applied on every peer (D-062).
##
## The single place `health` is written, and the single place the plate is told
## about it, so the bar over a Bog's head cannot be drawing a different number
## from the one the host is about to kill it on. Clamped rather than trusted:
## on every machine but the host's this value arrived over a wire.
func set_health(value: float) -> void:
	# Taking a hit ends the emote, and this is the one line in the game that
	# knows a hit landed on anybody: `MatchState._do_damage` runs on every peer
	# and comes through here, so the dancer stops on the machine it is being
	# watched from as well as on its own. A heal is not a hit, hence the drop.
	if value < health and emoting:
		var combat := _combat()
		if combat != null:
			combat.stop_emote()
	health = clampf(value, 0.0, MAX_HEALTH)
	if nameplate != null and is_instance_valid(nameplate):
		nameplate.set_health(health, MAX_HEALTH)


## 1 -> 0, for anything drawing a bar out of it.
func health_fraction() -> float:
	return clampf(health / MAX_HEALTH, 0.0, 1.0)


## Server-side. Kills this Bog and tells everyone.
func kill(killer_id: int, cause: Cause = Cause.UNKNOWN) -> void:
	if not alive:
		return
	alive = false
	# Zeroed here rather than by a message of its own. `MatchState._apply_death`
	# runs on every peer, so every copy of this Bog reaches this line on the
	# death that emptied the bar — a kill costs no health packet at all, and a
	# void death, which never had a damage number behind it, still leaves the
	# bar and the body saying the same thing.
	set_health(0.0)
	velocity = Vector3.ZERO
	# On every peer, like the health above and for the same reason: a Bog killed
	# half way through a swing has to stop holding a sword everywhere at once,
	# and `is_spinning()` is what `BogCombat` draws that sword from (D-068).
	end_spin()
	died.emit(killer_id, cause)


## How many shafts one Bog can be carrying at once, oldest pushed out first.
##
## There has to be a cap now that a shaft can stand in a Bog who lives (D-062):
## the list is emptied by a corpse or by a respawn, and a Bog that keeps getting
## shot and keeps not dying reaches neither. Four is a porcupine and reads as
## one; it is also two more than anybody survives today, so the cap is a bound
## on the absurd rather than a rule anyone plays around.
const MAX_EMBEDDED_SHAFTS := 4

## Spears and arrows standing in this Bog. Each entry is
## `{"spear": Node3D, "bone": String}`, in the order they arrived.
##
## Until D-062 this was a queue of *hidden* shafts waiting for a corpse, because
## the only hit there was killed you. Now a hit that leaves you standing puts a
## visible shaft in you that rides the skeleton — the projectile does the riding
## itself, see `SpearProjectile._stick_in` — and this list is simply the record
## of what is in the body, so that whoever has to deal with it next can.
##
## Exactly two things ever deal with it. `BogRagdoll` takes the lot while it is
## building a corpse and hangs each shaft off the bone it went through, and a
## respawn throws away whatever is left, which is a death that produced no
## corpse (the void) or a body that was never killed at all.
var _pending_spears: Array[Dictionary] = []


## Put a shaft in this Bog. It stays until the corpse takes it or the Bog
## respawns — see `MAX_EMBEDDED_SHAFTS` for the one case that is neither.
func embed_spear(spear: Node3D, bone: String) -> void:
	_pending_spears.append({"spear": spear, "bone": bone})
	while _pending_spears.size() > MAX_EMBEDDED_SHAFTS:
		var oldest: Dictionary = _pending_spears.pop_front()
		var shaft: Node3D = oldest["spear"]
		if is_instance_valid(shaft):
			shaft.queue_free()


## Hand every parked spear to the caller and forget them.
func take_embedded_spears() -> Array[Dictionary]:
	var taken := _pending_spears
	_pending_spears = []
	return taken


func _drop_pending_spears() -> void:
	for entry: Dictionary in _pending_spears:
		var spear: Node3D = entry["spear"]
		if is_instance_valid(spear):
			spear.queue_free()
	_pending_spears.clear()


## Put this Bog back on its feet at `spawn`, in life number `life_number`.
##
## `MatchState` passes the host's count — the Bog's deaths so far — on every
## peer, so all copies of one Bog name the same life (D-043). Anything that
## revives a Bog outside a match (the testbeds, the menu backdrop) can leave it
## out: the Bog then stays in whatever life it was in, and its own snapshots,
## seeded below, still agree with it.
func revive_at(spawn: Transform3D, life_number: int = -1) -> void:
	_drop_pending_spears()
	alive = true
	# A life begins full, on every peer, with nothing sent. `revive_at` is
	# already called on all of them by `_create_bog` and `_do_respawn`, so the
	# bar over a respawned Bog's head is full everywhere for the same reason its
	# position is right everywhere — and a health packet that crossed a respawn
	# in flight cannot leave somebody standing on a pad with 12 health.
	set_health(MAX_HEALTH)
	if life_number >= 0:
		life = life_number
	velocity = Vector3.ZERO
	global_position = spawn.origin
	body_yaw = spawn.basis.get_euler().y
	_model_root.rotation.y = body_yaw
	_slide_time = 0.0
	_crouch_blend = 0.0
	_crouch_pose = 0.0
	_slide_blend = 0.0
	_magnet_until = 0.0
	_air_jump_spent = false
	_jump_buffered = 0.0
	_airtime = 0.0
	_roll_lock = 0.0
	_landing_grace = 0.0
	# On every peer, because `revive_at` runs on every peer: a Bog that came back
	# still spinning would have a sword in its fists on a spawn pad (D-068), and
	# on its own machine it would spend the rest of the swing sliding off the pad
	# at a speed it earned in its last life.
	end_spin()
	_was_spinning = false
	# And the chain, for the same sentence one weapon-state further (the feel
	# round): a Bog that respawned mid-chain would come back at 0.85 speed with
	# a sword in its fists that `has_sword()` says it does not have.
	end_slash()
	_apply_capsule(STAND_HEIGHT)
	# The replicated fields are seeded here, field by field, and deliberately
	# *not* by calling `_publish()`. `_publish` ends with
	# `sync_grounded = is_on_floor()`, which is only a true statement on the
	# peer that owns this Bog: a remote copy never calls `move_and_slide`, so
	# its `is_on_floor()` is permanently false. Worse, the value it writes never
	# changes afterwards — the owner was standing before it died and is standing
	# now, true to true — so ON_CHANGE replication has nothing to correct, and
	# every other client keeps the respawned Bog in the airborne pose for the
	# rest of the round. Spawn pads are on the ground, so this says so outright;
	# the owner's first real `_publish` follows one physics tick later.
	sync_position = spawn.origin
	sync_yaw = body_yaw
	sync_velocity = Vector3.ZERO
	sync_crouching = false
	sync_sliding = false
	sync_grounded = true
	# A respawning Bog is not drawing anything. Seeded here with the rest rather
	# than left to the next `_publish`, for the reason the block above exists: a
	# remote Bog that came back mid-draw would hold a half-drawn bow until its
	# owner's first snapshot arrived.
	draw = -1.0
	sync_draw = -1.0
	# And a respawning Bog has its weapon back out. Seeded here with the draw
	# and for its reason — a remote copy that came back holstered would stand on
	# a spawn pad empty-handed until its owner's first snapshot arrived — and
	# written on every peer rather than only the owner, because every peer runs
	# `revive_at` and they all reach the same answer (the feel round).
	sync_holstered = false
	sync_life = life
	respawned.emit()
