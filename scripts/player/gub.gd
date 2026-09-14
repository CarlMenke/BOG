class_name Gub
extends CharacterBody3D
## A player character.
##
## One of these exists per peer in a match. The peer it belongs to owns it:
## `set_multiplayer_authority(peer_id)` is called on spawn, that peer runs the
## movement code, and a `MultiplayerSynchronizer` pushes the result to everyone
## else (see docs/DECISIONS.md D-004). Remote Gubs run no input and no gravity —
## they only smooth toward what the network last said.
##
## Movement speeds here are gameplay choices, and the animation is made to fit
## them rather than the other way round. Each locomotion clip was authored at
## its own ground speed (`AUTHORED_*` below, measured out of the root motion the
## asset pipeline strips — see D-008), and `GubAnimator` plays each one back at
## `game speed / authored speed`, so the feet stay planted at whichever of these
## speeds the clip is assigned to. Change a speed here and the playback rate
## follows; there is no shared factor to keep in step any more.

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
enum Cause { SPEAR, FALL, VOID, UNKNOWN, LIGHTNING, ARROW }

## Full health, and the unit every damage number in the game is written in
## (D-062). A Gub starts each life on exactly this and is dead at zero.
##
## It is a constant and **not a lobby dial**, which is the whole reason the
## spear can keep its promise. `GubCombat.SPEAR_DAMAGE` is this same constant,
## so "a spear always kills" is a number rather than a branch: a spear takes a
## whole body's worth, so it kills a Gub on 100 and it kills a Gub on 3, and no
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
const TINT_SHADER := preload("res://resources/shaders/gub_team_tint.gdshader")
## The body mesh's node name inside `gub.glb`, as `tools/build_gub.py` writes it.
const BODY_MESH_NAME := "Gub"

## The ground speed each locomotion clip was authored at, in metres per second,
## measured on the finished 1.80 m rig by `tools/build_gub.py` (hips travel over
## the cycle, divided by the cycle's *interval* count and not its frame count —
## a one-frame error there is a 1.3% skate). `GubAnimator` divides the game
## speeds below by these to get each clip's playback rate.
const AUTHORED_WALK := 1.079
const AUTHORED_RUN := 4.314
const AUTHORED_CROUCH_WALK := 1.273

## How fast the Gub actually moves. Chosen for how the game plays, not for what
## the clips were made at: walking is brisk, sprinting is nearly twice that, and
## crouching is slow enough that choosing it costs you something. Each of these
## is a blend point in the animator's locomotion space, so a Gub travelling at
## exactly one of them is running exactly one clip at a rate that plants its
## feet; in between, two cycles are blended.
const WALK_SPEED := 2.3
const RUN_SPEED := 5.4
const CROUCH_SPEED := 1.6

## Gravity is 24 m/s² (project setting), which is deliberately about 2.4x real:
## it keeps jumps short and readable rather than floaty. 9.0 m/s of launch under
## that gravity is a 1.69 m apex — just under the Gub's own height.
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
## The cap, as a multiple of the Gub's current target speed. The thing to tune
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
## floor flickering under a Gub running over bumps is not a string of landings.
const HOP_MIN_AIRTIME := 0.2
## The hop only pays if you are already moving at near your target speed, and
## pressing within ~45 degrees of the way you are going.
const HOP_MIN_SPEED := 0.9
const HOP_ALIGNMENT := 0.7

## The dive: jump again while already in the air and the Gub commits to a leap
## along whichever way it is trying to go. Once per airtime — that is what makes
## it a decision rather than free flight. The animator shows it with the
## `JumpTwo` clip, scrubbed by where the body is in its arc, and lands it with
## that clip's ground roll; see `GubAnimator`.
##
## The forward speed is deliberately well above RUN_SPEED: a dive that moved you
## no faster than running would be a worse way of running. Air friction is
## almost nothing (AIR_FRICTION 1.5), so this is very close to how fast the Gub
## is still travelling when it lands.
const DIVE_FORWARD_SPEED := 9.5
## Modest on purpose. The dive is meant to carry you *across* a gap, not over the
## treeline: at 24 m/s² this is 0.6 m of extra height on its own, and enough to
## keep the Gub in the air long enough for the leap to read.
const DIVE_UP_VELOCITY := 5.4

## A jump pressed this long after walking off an edge still counts.
const COYOTE_TIME := 0.12
## A jump pressed this long before landing fires on touchdown.
const JUMP_BUFFER := 0.14

## The slide. Its duration is set by the clip and not by taste: `Slide` puts the
## hips on the floor from 0.43 s and keeps them there until 1.13 s, so a slide
## the physics ends at 1.0 s ends while the body is still down, and the
## animator's fade-out lands on the clip's own stand-up. A slide that outlasted
## the low part of the clip would stand the Gub up and keep it sliding.
const SLIDE_SPEED := 4.0
const SLIDE_DURATION := 1.0
const SLIDE_FRICTION := 2.8
## Sliding has to be worth doing and worth stopping: you must already be moving
## near a run to enter one, and you cannot re-enter immediately.
const SLIDE_ENTRY_SPEED := RUN_SPEED * 0.7
const SLIDE_COOLDOWN := 0.9

## After landing from a dive the Gub is committed to its roll: movement input is
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
## (`_tick_timers`), so a Gub that rolls off a ledge gets its air control and
## AIR_FRICTION back at once instead of falling deaf to the stick with
## ROLL_FRICTION dragging on it.
##
## Set to 0.0 to turn the rule off completely: every use of it is guarded, so at
## zero the landing behaves exactly as it did before the rule existed.
const ROLL_LOCK := 0.45
## And only an airtime that lasted at least this long is rolled out of. The
## animator declines to play its roll one-shot below the same threshold —
## `GubAnimator.LAND_MIN_AIRTIME` *is* this constant — so without the guard here
## a dive that clipped the ground after a tenth of a second would take movement
## away for 0.45 s with no roll animation to explain it: the Gub would stand in
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
## one outside its own hitbox: a crouching Gub could not be speared in the
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
## 0.73 m through it (measured). A sliding Gub is therefore genuinely a low
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

## Lure. Once caught, the Gub is dragged toward the crystal until it is inside
## LURE_GRIP metres, then pinned there for the rest of the hold. Jumping is
## blocked for the duration — the lure is meant to feel like being grabbed, and
## an escape hatch would make it never worth throwing.
const LURE_GRIP := 1.1
const LURE_MAX_SPEED := 11.0
const LURE_PIN_DAMP := 26.0

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
## two dives in a row have to be two dives on every screen. `GubAnimator` watches
## it, so remote Gubs fire the dive from the same value their own client wrote.
@export var sync_dive_serial: int = 0
## How far this Gub's bow is drawn, or **-1 for "not drawing"** (D-065).
##
## One float and not a float beside a flag, which is the whole of why the charge
## can be trusted on somebody else's screen. A bow that is 40% drawn and a bow
## that is not being drawn at all are two states, and with two fields they are
## two packets that can arrive in either order — so for one tick a Gub would be
## "not drawing, 40%" or "drawing, 0%", and both of those are a pose. Out of
## band is the cheapest way to say "neither": `draw_fraction` reads 0 from it
## and `is_drawing` reads false, off the one number, on every peer.
##
## Written by the owner like every other `sync_*` field here. The charge is not
## health — it is an input the player is holding down, and the peer holding it
## is the only one that can know. What the *host* does with it is check it: the
## claim that arrives with a loose is clamped to the draw it has been watching
## (`GubCombat._host_loose_arrow`), exactly as a throw's origin is clamped to
## somewhere near the Gub.
##
## ON_CHANGE, so a Gub standing about sends nothing and a drawing one sends a
## float a tick. That is the price of the tell and it is the smallest price
## there is: no serial, no start time, no clock to keep in step — a peer that
## misses a packet is corrected by the next one and is wrong about a pose for a
## sixtieth of a second.
@export var sync_draw: float = -1.0
## Bumped once per ordinary jump, for the same reason and read the same way.
## Nothing has to *fire* on a jump — the animator scrubs the jump clip by where
## the body is in its arc, and leaving the ground with a positive vertical
## velocity is already the whole story — but the serial says which kind of
## airtime this is, which is what decides between the landing absorb and the
## dive roll. It also arrives on time when `sync_grounded` does not: a remote
## Gub whose grounded flag is a tick late still starts its airtime on the frame
## the jump happened.
@export var sync_jump_serial: int = 0
## Which life of this Gub the snapshot it rides in was taken in. See `life`.
##
## Replicated ALWAYS, in the same packet as `sync_position`, and that is the
## whole point of it: a counter on its own reliable channel would arrive on a
## different schedule from the position it is meant to vouch for, and the pair
## has to be judged together or not at all.
@export var sync_life: int = 0

## Which life this copy of the Gub is in. Set only by `revive_at`, from a number
## the host hands out (D-043) — never counted up locally, so every peer's copy
## of one Gub agrees about it however many times a testbed revives it by hand.
##
## `_follow_network` ignores any snapshot whose `sync_life` is not this. That is
## the fix for a player coming back from a death holding what they died on: the
## host revives its copy of a remote Gub at the pad, but the owner's client is
## still dead until the reliable `_do_respawn` reaches it, and every snapshot it
## sends in the meantime says "I am lying on my corpse". Followed, those put the
## host's live copy back on its own loot for a round trip, and the `Pickup`
## there handed it over. They carry the life before, so now they are refused.
var life: int = 0

var display_name: String = "Gub"
## Everything in the Gub's two hands. Hidden and shown off the one gate in
## `GubCombat`.
var held_gear: HeldGear
## The local half of `sync_draw`, written by `GubCombat` on the owning client
## only and published from `_publish` like every other owner-authored value.
## -1 while nothing is being drawn.
var draw: float = -1.0
## The robe, while this Gub is the Elder (D-038), and null the rest of the time
## — which is almost always. Built on demand rather than in `_ready` like the
## spear, because seven of every eight Gubs in a match will never wear one and a
## hidden second skinned mesh on every rig is 4,352 triangles of nothing.
var elder_robe: ElderRobe
## The gold card over this Gub's head while it carries a letter, for everyone
## but its owner (D-050). Switched by whoever decides what is carried.
var carrier_marker: CarrierMarker
var team: int = MatchConfig.TEAM_NONE
## The body's own skinned mesh out of `gub.glb`, found once in `_ready` before
## anything else is hung off the skeleton — so never the spear, and never the
## robe (D-046). Null only on a rig a re-import has broken.
var body_mesh: MeshInstance3D
## This Gub's copy of the team-colour material, made the first time it is
## tinted and reused after that. Null on a Gub that has never been on a team.
var _tint_material: ShaderMaterial
var alive: bool = true
## What is left of this Gub, from `MAX_HEALTH` down to zero (D-062).
##
## **The host owns this number and every copy of it is a copy of the host's.**
## It is deliberately not one of the `sync_*` fields above: those are written by
## the peer that *owns* the Gub, and health is the one thing about a body its
## owner does not get a vote on. It travels instead on
## `MatchState._do_damage`, an `@rpc("authority")` from peer 1, the same road
## every other host decision takes (D-004, D-024).
##
## It lives on the body rather than in the `stats` row beside kills and deaths,
## and there is only one of it. The row is the match's ledger — what a player
## has scored and how many lives they have left, kept across deaths — while
## health belongs to the Gub standing in the world: it is what the bar over its
## head draws, it dies with the body and it comes back with `revive_at`. A
## second copy in the row would be a copy waiting to disagree with this one.
var health: float = MAX_HEALTH
## Set while the round is starting or just after a respawn; blocks damage.
var invulnerable_until: float = 0.0

## Movement intent for this frame. Filled from the keyboard in `_read_input`
## when this Gub is the local one, and set directly by the testbeds that script
## a Gub through a pose — see `reads_local_input`.
var input_direction: Vector2 = Vector2.ZERO
var wants_sprint: bool = false
var wants_crouch: bool = false
## False on a Gub whose movement is being driven by something other than the
## player: `tools/sandbox.gd` walks one through scripted poses for a snapshot,
## and reading an empty keyboard over the top of that would zero it every frame.
var reads_local_input: bool = true
var body_yaw: float = 0.0

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
## How long the Gub has been off the ground, in seconds, reset on touchdown.
## Read by `_detect_landing` to decide whether an airtime was long enough to be
## worth rolling out of — see ROLL_MIN_AIRTIME.
var _airtime: float = 0.0
var _crouch_blend: float = 0.0
## How prone the body is, on top of the crouch blend. See `pose_height`.
var _slide_blend: float = 0.0
var _was_grounded: bool = true
var _fall_speed: float = 0.0
## Set by the camera each frame; movement is relative to where you are looking.
var _view_basis: Basis = Basis.IDENTITY
## While aiming or throwing the body faces the camera instead of the direction
## of travel, so a thrown spear goes where the crosshair is.
var _face_view: bool = false

var _lure_centre: Vector3 = Vector3.ZERO
var _lure_strength: float = 0.0
var _lure_until: float = 0.0

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
	# Slide along walls rather than sticking to them; a Gub that catches on
	# scenery during a fight feels broken even when it is technically correct.
	wall_min_slide_angle = deg_to_rad(12.0)

	add_to_group("gubs")
	body_yaw = rotation.y
	sync_position = global_position
	sync_yaw = body_yaw
	_apply_capsule(STAND_HEIGHT)
	body_mesh = _find_body_mesh()
	_equip_spear()
	_build_carrier_marker()


## The mesh `build_gub.py` calls "Gub", under the skeleton. Looked for by name
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
## Free-for-all is TEAM_NONE, and so is every Gub in it: the nameplate goes
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
## per Gub and only its colour moves after that.
func set_team_tint(new_team: int) -> void:
	if body_mesh == null:
		return
	if new_team < 0:
		body_mesh.set_surface_override_material(0, null)
		return
	if _tint_material == null:
		_tint_material = make_tint_material(body_mesh.mesh.surface_get_material(0))
	_tint_material.set_shader_parameter("team_colour", Nameplate.colour_for_team(new_team))
	body_mesh.set_surface_override_material(0, _tint_material)


## The team-colour shader, carrying over what the imported body material sets so
## a tinted Gub is lit exactly like a yellow one. Static so the corpse can build
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


## The colour this Gub's body is currently drawn in, read back off the material
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


## Put the Elder's robe on this Gub, or take it off again.
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
	# FADE_OUT seconds before the arena is freed. Every Gub still in the tree is
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


## Called by the camera rig each frame so movement is relative to the view.
func set_view_basis(basis: Basis, face_view: bool) -> void:
	_view_basis = basis
	_face_view = face_view


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
	if is_lured():
		_handle_lure(delta)
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

## The keyboard half of a Gub. The mouse half lives in `GubCamera`, and the
## ability keys in `GubCombat`, which reads them exactly like this.
##
## This belongs on the Gub rather than on whatever scene is hosting it. It used
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
		return
	input_direction = Input.get_vector("move_left", "move_right",
		"move_forward", "move_back")
	wants_sprint = Input.is_action_pressed("sprint")
	wants_crouch = Input.is_action_pressed("crouch")
	if Input.is_action_just_pressed("jump"):
		request_jump()


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
	# of the roll. Nothing else can consume the buffer meanwhile — the Gub is on
	# the floor, so `_coyote` is full and `_handle_jump` is the only reader.
	if not is_rolling():
		_jump_buffered = maxf(0.0, _jump_buffered - delta)
	_slide_cooldown = maxf(0.0, _slide_cooldown - delta)
	# The roll is a ground move. Leave the floor mid-roll — a dive that lands on
	# a ledge and carries over its edge — and the lock ends there, or the fall
	# would have no air control and ROLL_FRICTION instead of AIR_FRICTION.
	_roll_lock = maxf(0.0, _roll_lock - delta) if is_on_floor() else 0.0
	_landing_grace = maxf(0.0, _landing_grace - delta) if is_on_floor() else 0.0


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))
	# Falling faster than rising makes a jump feel decisive rather than floaty.
	if velocity.y < 0.0:
		gravity *= 1.35
	velocity.y -= gravity * delta
	velocity.y = maxf(velocity.y, -60.0)


func _handle_crouch(delta: float) -> void:
	var target := 1.0 if (wants_crouch or is_sliding()) and is_on_floor() else 0.0
	if target < 0.5 and _crouch_blend > 0.0 and not _has_headroom():
		target = 1.0  # something overhead; stay down
	_crouch_blend = move_toward(_crouch_blend, target, CROUCH_TRANSITION * delta)
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

	# Not while rolling out of a dive: a dive lands well above SLIDE_ENTRY_SPEED,
	# so without this a held crouch turns every dive landing into a slide, on top
	# of a roll that is already playing.
	var can_slide := wants_crouch and wants_sprint and is_on_floor() \
		and _slide_cooldown <= 0.0 and not is_rolling() \
		and Vector3(velocity.x, 0.0, velocity.z).length() >= SLIDE_ENTRY_SPEED
	if can_slide:
		_begin_slide()


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


## Remote Gubs never call `move_and_slide` and never run the slide timer, so on
## anything but the owning client these read the replicated flags instead. Left
## as `is_on_floor()` and `_slide_time`, a remote Gub is permanently airborne and
## never sliding, and the animator plays the Jump clip at everyone else forever.
func is_sliding() -> bool:
	return _slide_time > 0.0 if is_local() else sync_sliding


func is_grounded() -> bool:
	return is_on_floor() if is_local() else sync_grounded


## Is this Gub drawing a bow, and how far?
##
## Local value on your own Gub, the replicated one on everybody else's — the
## same shape `is_crouching` and `is_sliding` have, and the reason this pair is
## written this way rather than as something the animator asks `GubCombat` for.
## `GubCombat` on a remote Gub belongs to the host and has no idea what that
## player is holding down; this field does, on every machine (D-065).
func is_drawing() -> bool:
	return (draw if is_local() else sync_draw) >= 0.0


## 0 at brace, 1 at full draw, and 0 for a Gub that is not drawing at all — so
## `GubAnimator.draw_time` can be handed it unconditionally and lands on the
## first frame of the window.
func draw_fraction() -> float:
	return maxf(draw if is_local() else sync_draw, 0.0)


func is_crouching() -> bool:
	return _crouch_blend > 0.5


## Vertical speed, in metres per second, for anything that reads the arc rather
## than simulating it — the animator scrubs both jump clips by this and records
## a dive's launch speed from it.
##
## Locally it is just `velocity.y`. On a remote Gub it is the replicated value
## and *not* the copy in `velocity`, which is one physics tick staler: the
## synchronizer applies an incoming packet during idle processing, in the same
## pass `GubAnimator._process` runs in, and `_follow_network` only copies
## `sync_velocity` into `velocity` on the next physics tick. On the one frame
## that matters — the frame a dive's serial arrives, when the launch speed is
## read once and used for the whole leap — reading `velocity` there gives the
## speed the body had *before* it dived.
func vertical_speed() -> float:
	return velocity.y if is_local() else sync_velocity.y


## True through the ROLL_LOCK window after landing from a dive. Local only —
## nothing on a remote Gub reads it, because a remote Gub is not simulated and
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

	var wish := _wish_direction()
	var speed := target_speed()
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
## Only speed between target and the cap: anything faster (a lure's fling, a
## robe coming off mid-air) bleeds down the ordinary way until it reaches the
## cap, so nothing is clamped in one frame. Only while pushing forward-ish — let
## go of the stick, or pull back, and the Gub slows as it always did. Only in
## the air or inside the landing grace — a Gub running on the ground is at its
## target in a couple of ticks. And not in a dive's airtime: the dive has its
## own tuned speed and roll (D-026), and keeping 9.5 m/s all the way to the
## floor would lengthen every dive rather than reward a hop.
func _keeps_momentum(horizontal: Vector3, wish: Vector3, speed: float) -> bool:
	if wish.length_squared() < 0.001 or _air_jump_spent:
		return false
	if is_on_floor() and _landing_grace <= 0.0:
		return false
	var moving := horizontal.length()
	return moving > speed and moving <= hop_speed_cap() + 0.001 \
		and wish.dot(horizontal) > 0.0


## The fastest a Gub can carry by hopping, in m/s: HOP_SPEED_CAP of whatever it
## is asking to travel at now, so the Elder and the capture carrier scale it.
func hop_speed_cap() -> float:
	return target_speed() * HOP_SPEED_CAP


## A jump fired inside the landing grace, pointed the way the Gub is already
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


## Called on the caught Gub's own client, because movement is client-authoritative
## and the host cannot simply move the body itself.
func apply_lure(centre: Vector3, strength: float, duration: float) -> void:
	_lure_centre = centre
	_lure_strength = strength
	_lure_until = Time.get_ticks_msec() * 0.001 + duration
	if is_sliding():
		_end_slide()


func is_lured() -> bool:
	return Time.get_ticks_msec() * 0.001 < _lure_until


func _handle_lure(delta: float) -> void:
	var to_centre := _lure_centre - (global_position + Vector3.UP * 0.6)
	var distance := to_centre.length()
	if distance > LURE_GRIP:
		velocity += to_centre.normalized() * _lure_strength * delta
		# Cap it, or a long pull accelerates the Gub into the crystal hard enough
		# to launch it off the far side of the island.
		var horizontal := Vector3(velocity.x, 0.0, velocity.z)
		if horizontal.length() > LURE_MAX_SPEED:
			horizontal = horizontal.normalized() * LURE_MAX_SPEED
			velocity.x = horizontal.x
			velocity.z = horizontal.z
		return
	# Arrived: pinned until the hold expires.
	velocity.x = move_toward(velocity.x, 0.0, LURE_PIN_DAMP * delta)
	velocity.z = move_toward(velocity.z, 0.0, LURE_PIN_DAMP * delta)


func _wish_direction() -> Vector3:
	if input_direction.length_squared() < 0.0001:
		return Vector3.ZERO
	var forward := -_view_basis.z
	var right := _view_basis.x
	forward.y = 0.0
	right.y = 0.0
	var wish := (right * input_direction.x + forward * -input_direction.y)
	return wish.normalized() if wish.length_squared() > 0.0001 else Vector3.ZERO


## The speed this Gub is asking to travel at, which is also the animator's
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
## one Gub in the match wearing a robe that already says it is not ordinary.
## Rebuilding the blend space to follow a dial would be a graph that changes
## shape mid-match, which is a much worse trade.
func target_speed() -> float:
	var speed := CROUCH_SPEED if is_crouching() \
		else (RUN_SPEED if wants_sprint else WALK_SPEED)
	return speed * elder_scale(Net.config.elder_speed_multiplier) * carrier_scale()


## `capture_carrier_speed` while this Gub carries a letter in Capture G·U·B, and
## 1.0 otherwise (D-051). Read off `MatchState`'s hold row, which exists on every
## peer, so the owner that moves the Gub and every copy that watches it agree.
## Multiplied with the Elder's boost rather than instead of it: an Elder carrying
## a card is a faster Elder and a slower carrier, both at once.
func carrier_scale() -> float:
	if Net.config.win_condition != MatchConfig.WinCondition.CAPTURE \
			or not MatchState.is_holding_letter(peer_id):
		return 1.0
	return Net.config.capture_carrier_speed


## How fast this Gub leaves the ground, in metres per second.
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


## `multiplier` while this Gub is the Elder, and 1.0 otherwise.
##
## `elder_robe != null` **is** the flag — see `set_elder`. There is no second
## boolean to disagree with it and no call into `MatchState` either: the robe is
## put on by `_do_set_elder`, which runs on every peer, so the wardrobe and the
## rules are already the same statement. That matters here more than anywhere,
## because movement is client-authoritative (D-004) and this is read on the
## machine that owns the Gub rather than on the host.
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
	if not alive or _air_jump_spent or is_lured():
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
	if is_sliding():
		_end_slide()
	if _landing_grace > 0.0:
		_hop_gain()
	_landing_grace = 0.0
	velocity.y = jump_velocity()
	# Before the emit, so anything listening already sees the new value. The
	# animator does not use the signal — it is local-only — but it does watch
	# this counter, on every peer.
	sync_jump_serial += 1
	jumped.emit()


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
	# Touching anything at all gives the dive back, including a ledge caught on
	# the way down. Tying it to `landed` instead would leave a Gub that stepped
	# gently off a rock unable to dive for the rest of the match.
	if grounded_now:
		_air_jump_spent = false
	_was_grounded = grounded_now


func _face(delta: float) -> void:
	var desired := body_yaw
	if _face_view:
		desired = yaw_towards(-_view_basis.z)
	else:
		var horizontal := Vector3(velocity.x, 0.0, velocity.z)
		if horizontal.length() > 0.35:
			desired = yaw_towards(horizontal)
	body_yaw = rotate_toward(body_yaw, desired, TURN_SPEED * delta)
	_model_root.rotation.y = body_yaw


## Yaw that points this node's forward (-Z, Godot's convention) along `direction`.
## The Gub mesh itself is authored facing +Z and is turned 180 degrees inside
## `gub.tscn` to compensate, so `body_yaw` always means "the way the Gub looks".
static func yaw_towards(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## Unit vector the Gub is facing.
func facing() -> Vector3:
	return Vector3(-sin(body_yaw), 0.0, -cos(body_yaw))


# ------------------------------------------------------------------ shape ---

func _apply_capsule(height: float) -> void:
	# CapsuleShape3D.height is the full height including both hemispheres, and
	# the shape is centred on its origin, so it has to be lifted by half.
	_capsule.height = maxf(height, CAPSULE_RADIUS * 2.0 + 0.01)
	_capsule.radius = CAPSULE_RADIUS
	_collision.position.y = _capsule.height * 0.5


## The middle of this Gub's collision capsule, in world space.
func body_centre() -> Vector3:
	return _collision.global_position


## The point on this Gub's capsule *axis* nearest to `point`: the segment between
## the centres of its two hemispheres, in world space, at whatever height the
## stance has made it this frame.
func body_axis_nearest(point: Vector3) -> Vector3:
	var centre := _collision.global_position
	var up := _collision.global_basis.y.normalized()
	var half := maxf(0.0, _capsule.height * 0.5 - _capsule.radius)
	return centre + up * clampf((point - centre).dot(up), -half, half)


## How far `point` is from the surface of this Gub's collision capsule, and zero
## from inside it. What the Elder's blast radius is measured against (D-053):
## the body, not its feet or its middle, so a crouched Gub is a smaller target
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
	# always begins inside the Gub. Starting it at a fixed CROUCH_HEIGHT * 0.5
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
	sync_life = life


## Remote Gubs are not simulated — running physics for them would fight the
## authoritative position and produce jitter. They are eased toward what the
## network last reported, fast enough to stay honest and slow enough to hide
## packet spacing.
##
## **Except when what the network last reported was a different life.** A
## snapshot from the life before is a corpse's position arriving after the
## revive, and a snapshot from the life after is the owner arriving before the
## `_do_respawn` that tells this copy it is alive; both are about a body this
## copy is not, and the copy holds still until the two agree. The first case is
## the bug (see `life`). The second is a Gub that stays hidden on its corpse a
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
	# The same two blends the owner runs, off the replicated flags, so a remote
	# Gub is as hittable as the one whose screen it is being played on. The
	# combat range's dummies are remote Gubs.
	_slide_blend = move_toward(_slide_blend, 1.0 if sync_sliding else 0.0,
		CROUCH_TRANSITION * delta)
	_apply_capsule(pose_height())


# ------------------------------------------------------------ life & death ---

func is_invulnerable() -> bool:
	return Time.get_ticks_msec() * 0.001 < invulnerable_until


func grant_invulnerability(seconds: float) -> void:
	invulnerable_until = Time.get_ticks_msec() * 0.001 + seconds


## The host's word on what is left of this Gub, applied on every peer (D-062).
##
## The single place `health` is written, and the single place the plate is told
## about it, so the bar over a Gub's head cannot be drawing a different number
## from the one the host is about to kill it on. Clamped rather than trusted:
## on every machine but the host's this value arrived over a wire.
func set_health(value: float) -> void:
	health = clampf(value, 0.0, MAX_HEALTH)
	if nameplate != null and is_instance_valid(nameplate):
		nameplate.set_health(health, MAX_HEALTH)


## 1 -> 0, for anything drawing a bar out of it.
func health_fraction() -> float:
	return clampf(health / MAX_HEALTH, 0.0, 1.0)


## Server-side. Kills this Gub and tells everyone.
func kill(killer_id: int, cause: Cause = Cause.UNKNOWN) -> void:
	if not alive:
		return
	alive = false
	# Zeroed here rather than by a message of its own. `MatchState._apply_death`
	# runs on every peer, so every copy of this Gub reaches this line on the
	# death that emptied the bar — a kill costs no health packet at all, and a
	# void death, which never had a damage number behind it, still leaves the
	# bar and the body saying the same thing.
	set_health(0.0)
	velocity = Vector3.ZERO
	died.emit(killer_id, cause)


## How many shafts one Gub can be carrying at once, oldest pushed out first.
##
## There has to be a cap now that a shaft can stand in a Gub who lives (D-062):
## the list is emptied by a corpse or by a respawn, and a Gub that keeps getting
## shot and keeps not dying reaches neither. Four is a porcupine and reads as
## one; it is also two more than anybody survives today, so the cap is a bound
## on the absurd rather than a rule anyone plays around.
const MAX_EMBEDDED_SHAFTS := 4

## Spears and arrows standing in this Gub. Each entry is
## `{"spear": Node3D, "bone": String}`, in the order they arrived.
##
## Until D-062 this was a queue of *hidden* shafts waiting for a corpse, because
## the only hit there was killed you. Now a hit that leaves you standing puts a
## visible shaft in you that rides the skeleton — the projectile does the riding
## itself, see `SpearProjectile._stick_in` — and this list is simply the record
## of what is in the body, so that whoever has to deal with it next can.
##
## Exactly two things ever deal with it. `GubRagdoll` takes the lot while it is
## building a corpse and hangs each shaft off the bone it went through, and a
## respawn throws away whatever is left, which is a death that produced no
## corpse (the void) or a body that was never killed at all.
var _pending_spears: Array[Dictionary] = []


## Put a shaft in this Gub. It stays until the corpse takes it or the Gub
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


## Put this Gub back on its feet at `spawn`, in life number `life_number`.
##
## `MatchState` passes the host's count — the Gub's deaths so far — on every
## peer, so all copies of one Gub name the same life (D-043). Anything that
## revives a Gub outside a match (the testbeds, the menu backdrop) can leave it
## out: the Gub then stays in whatever life it was in, and its own snapshots,
## seeded below, still agree with it.
func revive_at(spawn: Transform3D, life_number: int = -1) -> void:
	_drop_pending_spears()
	alive = true
	# A life begins full, on every peer, with nothing sent. `revive_at` is
	# already called on all of them by `_create_gub` and `_do_respawn`, so the
	# bar over a respawned Gub's head is full everywhere for the same reason its
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
	_slide_blend = 0.0
	_lure_until = 0.0
	_air_jump_spent = false
	_jump_buffered = 0.0
	_airtime = 0.0
	_roll_lock = 0.0
	_landing_grace = 0.0
	_apply_capsule(STAND_HEIGHT)
	# The replicated fields are seeded here, field by field, and deliberately
	# *not* by calling `_publish()`. `_publish` ends with
	# `sync_grounded = is_on_floor()`, which is only a true statement on the
	# peer that owns this Gub: a remote copy never calls `move_and_slide`, so
	# its `is_on_floor()` is permanently false. Worse, the value it writes never
	# changes afterwards — the owner was standing before it died and is standing
	# now, true to true — so ON_CHANGE replication has nothing to correct, and
	# every other client keeps the respawned Gub in the airborne pose for the
	# rest of the round. Spawn pads are on the ground, so this says so outright;
	# the owner's first real `_publish` follows one physics tick later.
	sync_position = spawn.origin
	sync_yaw = body_yaw
	sync_velocity = Vector3.ZERO
	sync_crouching = false
	sync_sliding = false
	sync_grounded = true
	# A respawning Gub is not drawing anything. Seeded here with the rest rather
	# than left to the next `_publish`, for the reason the block above exists: a
	# remote Gub that came back mid-draw would hold a half-drawn bow until its
	# owner's first snapshot arrived.
	draw = -1.0
	sync_draw = -1.0
	sync_life = life
	respawned.emit()
