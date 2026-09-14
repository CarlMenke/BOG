class_name GubCombat
extends Node
## The three things a Gub can do to another Gub: throw a spear, plant a mushroom
## to hide behind, and lob a lure that drags people out from behind theirs.
##
## Authority split (docs/DECISIONS.md D-004): the owning client decides *when* it
## wants to act and plays its own feedback immediately, but the host decides
## whether the action actually happens. A client that lies about its cooldown
## gets its request dropped — the host keeps its own timers and is the only one
## that broadcasts.
##
## Which is why **this node belongs to the host and not to the Gub around it**.
## `MatchState._create_gub` hands the Gub to its owner and then hands this one
## child back to peer 1, because the `_do_*` broadcasts below are sent by the
## host and Godot checks an `@rpc("authority")` against whoever owns the node it
## arrives at. The `_request_*` calls go the other way and are `any_peer` with a
## sender check, so the owner can still ask. See D-024.
##
## Cooldowns are therefore tracked twice on purpose. The local copy exists so the
## HUD can show a sweeping timer without waiting for a round trip; the host's
## copy is the one that counts. **Carried stock is tracked the same way and for
## the same reason** — the count under the mushroom glyph has to move on the
## click, not a round trip later, and the host's count is the one that decides
## whether a mushroom actually appears.
##
## The mushroom and the lure are **inventory now, not abilities** (D-032). There
## is no cooldown that refills them: a Gub spawns with neither, picks them up off
## corpses, spends them one at a time and loses whatever is left when it dies.
## `mushroom_use_delay` and `lure_use_delay` are all that is left of the old
## timers, and they are a floor on how fast a stack can be emptied rather than a
## refill rate.
##
## **A letter hold takes the spear away and nothing else** (D-035). While
## `MatchState` says this Gub is holding a card up, `has_spear()` is false, the
## card is in the fist where the shaft would be, and the throw is refused on the
## client and again on the host. The mushroom and the lure are untouched, and so
## is movement — a Gub running a hold out runs exactly as fast as one that is
## not, which is deliberate and is the user's call.
##
## The spear is the one ability that does *not* happen on the click. A click
## starts the windup animation; the spear leaves the hand
## `GubAnimator.THROW_RELEASE_TIME` later, and the aim is read at that moment
## rather than at the click, so a target that moves while you wind up has to be
## led. See D-025.
##
## **The Elder replaces the spear rather than adding to it** (D-038). For as long
## as `MatchState` says this Gub is the Elder — twenty seconds, since D-040 —
## `has_spear()` is false, the fist holds no shaft, and the same click runs the
## same `Throw` clip through the
## same windup — the branch is taken at the *release*, next to where the aim is
## read, and what comes out is a hitscan bolt instead of a projectile. One
## windup, one release tick, two outcomes: a parallel windup for the Elder would
## be a second copy of the one piece of timing D-025 exists to keep honest.
##
## **The Elder's release is not the spear's** (D-040). The user, having played
## one: *"there should be basically no delay for the lightning."* The bolt leaves
## `MatchConfig.lightning_delay` after the click — 0.2 s by default against the
## spear's 0.71 — and the *same clip* is played fast enough to have got there, at
## a rate derived from the delay by `GubAnimator.throw_rate_for_release`. The
## windup is still one piece of code with one set of edge cases; the only thing
## that branches is how fast it runs and when its release lands.

signal cooldowns_changed()
## Carried stock changed: spent, picked up, or wiped by a death. Separate from
## `cooldowns_changed` because they move for different reasons and at wildly
## different rates — the counts change a handful of times a match and the
## cooldowns change every frame the HUD asks.
signal inventory_changed()

const SPEAR := preload("res://scripts/items/spear_projectile.gd")
const MUSHROOM := preload("res://scenes/items/shield_mushroom.tscn")
const LURE := preload("res://scenes/items/lure.tscn")

# How long after the click the spear actually leaves the hand is
# `GubAnimator.THROW_RELEASE_TIME`, and not a constant here, because it is a
# fact about the animation and this file only has to agree with it.
#
# It is measured off the clip rather than guessed, and then *derived*: `Throw`
# is 3.83 s, the animator plays the 0.50-2.10 s window of it at 1.6x, and
# tracking the `RightHand` bone through the clip gives a peak speed of 9.9 m/s
# at 1.625 s, with the hand crossing in front of the body at 1.60 and reaching
# furthest forward at 1.68. A thrown object separates at peak forward hand
# speed, so the release is 1.633 s of clip — 0.71 s of real time after the
# click at that rate. By 1.68 the hand is decelerating and letting go there
# would read as a push rather than a throw.
#
# Deriving it from the window and the rate is the point: whoever moves either
# of those without opening this file cannot leave the spear and the hand
# disagreeing, which is the bug D-025 exists because of.
#
# The throw OneShot's 0.08 s fade-in needs no allowance on top: the clip's arm
# does not start moving until 0.55 s, so the blend is long finished before
# anything the eye is following depends on it.

## Where the throw leaves the hand, relative to the Gub. The spear is aimed at
## whatever the crosshair is over, not simply pushed along the camera's forward
## axis, so what you point at is what you hit even up close.
const THROW_OFFSET := Vector3(0.34, 0.0, 0.0)
## Anything nearer than this is treated as "straight ahead"; without it, aiming
## at a wall a metre away would make the Gub throw at its own feet.
const MIN_AIM_DISTANCE := 3.0
const MAX_AIM_DISTANCE := 220.0

## How far in front the mushroom is planted.
const MUSHROOM_DISTANCE := 2.1

## Launch speed of the lure. With LURE_GRAVITY this sets the furthest it can be
## thrown at all — `s^2 / g`, about 22 m on the flat, which is a deliberate
## limit: the lure is a tool for pulling someone out of nearby cover, not for
## reaching across the island.
const LURE_SPEED := 22.0
## Must match `Lure.GRAVITY`, which integrates the flight. The arc is solved
## here and flown there, so if these disagree the lure lands somewhere other
## than where the thrower aimed.
const LURE_GRAVITY := 22.0

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_DEPLOYABLE := 8

var _gub: Gub
var _config: MatchConfig

## Local, predictive. Drives the HUD.
var _spear_ready_at: float = 0.0
var _mushroom_ready_at: float = 0.0
var _lure_ready_at: float = 0.0

## Host-side, authoritative. Never trusted from the wire.
var _server_spear_ready_at: float = 0.0
var _server_mushroom_ready_at: float = 0.0
var _server_lure_ready_at: float = 0.0

var _active_mushrooms: Array[Node] = []

## The ring on the ground while aiming. Local, cosmetic, and made on first use
## rather than in `_ready`, because seven of every eight Gubs in a match are
## somebody else's and must never build one.
var _aim_marker: AimMarker = null

## When the spear currently being wound up leaves the hand, or 0 for "no throw
## in progress". Only ever set on the throwing client: the host is told about
## the throw when it happens, not while it is being aimed.
var _windup_release_at: float = 0.0


func _ready() -> void:
	_gub = get_parent() as Gub
	if _gub == null:
		push_error("GubCombat expects to be a child of a Gub")
		return
	_config = Net.config


func _now() -> float:
	return Time.get_ticks_msec() * 0.001


# -------------------------------------------------------------------- input ---

func _process(_delta: float) -> void:
	if _gub == null:
		return
	# Before the guards below, not after: a Gub that dies or is respawned in the
	# middle of a windup has a throw to *cancel*, and the guards are exactly the
	# conditions under which it has to be cancelled.
	_tick_windup()
	if not _gub.is_local() or not _gub.alive:
		_stow_aim_marker()
		return
	if SceneFlow.cursor_is_free():
		_stow_aim_marker()
		return
	_tick_aim_marker()
	if Input.is_action_just_pressed("throw_spear"):
		try_throw_spear()
	if Input.is_action_just_pressed("place_mushroom"):
		try_place_mushroom()
	if Input.is_action_just_pressed("throw_lure"):
		try_throw_lure()


func spear_cooldown() -> float:
	return maxf(0.0, _spear_ready_at - _now())


func mushroom_cooldown() -> float:
	return maxf(0.0, _mushroom_ready_at - _now())


func lure_cooldown() -> float:
	return maxf(0.0, _lure_ready_at - _now())


func has_spear() -> bool:
	return spear_cooldown() <= 0.0


## The whole spear cycle: the windup you have already committed to, plus the
## recharge that follows it. The HUD divides by this rather than by the recharge
## alone, so the ring sweeps from the click instead of sitting full through the
## windup and then jumping down when the spear finally goes.
func spear_cycle() -> float:
	return GubAnimator.THROW_RELEASE_TIME + _config.spear_recharge


## True between the click and the release. The held spear is still in the hand
## through this window, which is the point of it.
func is_winding_up() -> bool:
	return _windup_release_at > 0.0


# ------------------------------------------------------------------- aiming ---

## The point the crosshair is over, or a point far along the view ray if it is
## over nothing. This is what makes a throw land where the reticle is instead of
## parallel to it.
func _aim_point() -> Vector3:
	var rig := _gub.get_node_or_null("CameraRig") as GubCamera
	if rig == null:
		return _gub.global_position + _gub.facing() * 30.0
	var ray := rig.aim_ray()
	var origin: Vector3 = ray["origin"]
	var direction: Vector3 = ray["direction"]

	var space := _gub.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * MAX_AIM_DISTANCE)
	query.collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_DEPLOYABLE
	query.exclude = [_gub.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return origin + direction * MAX_AIM_DISTANCE
	var point: Vector3 = hit["position"]
	if origin.distance_to(point) < MIN_AIM_DISTANCE:
		return origin + direction * MIN_AIM_DISTANCE
	return point


func _throw_origin() -> Vector3:
	var basis := Basis(Vector3.UP, _gub.body_yaw)
	return _gub.global_position + Vector3.UP * _gub.eye_height() \
		+ basis * THROW_OFFSET


# ------------------------------------------------------- the drop indicator ---

## Keep the landing ring in step with where the Gub is pointing.
##
## Only while aiming, and only with a spear to throw — including the half second
## you are winding one up, because through the windup the aim is still live and
## is exactly what the release is about to read. A ring under an empty hand
## would be a promise the cooldown is not keeping.
##
## Deliberately gated on the aim button rather than shown all the time. Spears
## drop, and judging that drop is where a lot of the skill in the fight lives
## (D-014, D-025); a marker on screen at all times turns the throw from a thing
## you read into a thing you line up. Holding the button is the price of the
## answer, and it costs you the wider field of view while you ask.
func _tick_aim_marker() -> void:
	var rig := _gub.get_node_or_null("CameraRig") as GubCamera
	if rig == null or not rig.is_aiming() or not (has_spear() or is_winding_up()):
		_stow_aim_marker()
		return
	if _aim_marker == null:
		_aim_marker = AimMarker.new()
		_aim_marker.name = "AimMarker"
		# Hung off the Gub so it is freed with it and hidden with it, but the
		# marker is `top_level`, so the body walking and turning underneath does
		# not drag the ring around with it.
		_gub.add_child(_aim_marker)

	# The same two calls the release makes, in the same order, so the ring is
	# answering the question the throw is actually going to be asked.
	var origin := _throw_origin()
	var direction := (_aim_point() - origin).normalized()
	if direction.length_squared() < 0.001:
		_stow_aim_marker()
		return
	_aim_marker.aim(origin, direction, _gub.get_rid())


func _stow_aim_marker() -> void:
	if _aim_marker != null:
		_aim_marker.stow()


# ------------------------------------------------------------------- spear ---

## A click starts the throw; it does not make it. The arm goes back now and the
## spear leaves the hand `GubAnimator.THROW_RELEASE_TIME` later, at which point
## the aim is sampled and the host is asked. Nothing about *where* the spear
## goes is decided here, which is the whole change: a target that walks during
## your windup has to be led.
func try_throw_spear() -> void:
	if spear_cooldown() > 0.0 or is_winding_up():
		return

	_windup_release_at = _now() + GubAnimator.THROW_RELEASE_TIME
	# The input has been spent whether or not the spear has left yet, so the ring
	# starts sweeping on the click. A crosshair that sits ready through half a
	# second of windup only invites the second click that will be refused.
	_spear_ready_at = _now() + spear_cycle()
	cooldowns_changed.emit()

	# Everyone else has to see the arm come back too, or the windup is a tell
	# only the thrower gets. The thrower plays it here and the host relays it to
	# the rest, because a client cannot address the other peers itself (D-024).
	_play_windup()
	if Net.is_host:
		_host_throw_windup()
	else:
		_request_throw_windup.rpc_id(1)


## The release. Runs on the throwing client only, one THROW_RELEASE_TIME after
## the click, and is the first moment anything about the aim is read.
func _tick_windup() -> void:
	if _windup_release_at <= 0.0:
		return
	# Dead, respawned, or no longer ours: the throw is off. The windup animation
	# is already playing and is left alone — it is cosmetic and fades out on its
	# own — but no spear comes out of it.
	if not _gub.alive or not _gub.is_local():
		_windup_release_at = 0.0
		return
	if _now() < _windup_release_at:
		return
	_windup_release_at = 0.0

	var origin := _throw_origin()
	var direction := (_aim_point() - origin).normalized()
	if direction.length_squared() < 0.001:
		return
	if Net.is_host:
		_host_throw_spear(origin, direction)
	else:
		_request_throw_spear.rpc_id(1, origin, direction)


func _play_windup() -> void:
	var animator := _gub.get_node_or_null("AnimationTree") as GubAnimator
	if animator != null:
		animator.play_throw()


@rpc("any_peer", "call_remote", "reliable")
func _request_throw_windup() -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _gub.peer_id:
		return
	_host_throw_windup()


## Deliberately not gated on the host's cooldown. This is a cosmetic tell, and
## refusing it would only hide the wind-up from everyone while the throw that
## follows is checked properly anyway; a Gub that winds up and produces no spear
## is a truthful picture of a client that asked for a throw it could not have.
func _host_throw_windup() -> void:
	if not _gub.alive:
		return
	_do_throw_windup.rpc()
	_do_throw_windup()


@rpc("authority", "call_remote", "reliable")
func _do_throw_windup() -> void:
	# The thrower already played this on its own click. Playing it again when the
	# host's relay lands would restart the arm half a round trip in and leave the
	# animation running behind the spear it is supposed to be launching.
	if _gub == null or _gub.is_local():
		return
	_play_windup()


@rpc("any_peer", "call_remote", "reliable")
func _request_throw_spear(origin: Vector3, direction: Vector3) -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _gub.peer_id:
		return
	_host_throw_spear(origin, direction)


func _host_throw_spear(origin: Vector3, direction: Vector3) -> void:
	if not _gub.alive or _now() < _server_spear_ready_at:
		return
	# The client picks the aim, but not the spawn point: clamping the origin to
	# somewhere near the Gub stops a modified client throwing from across the map.
	if origin.distance_to(_gub.global_position) > 3.0:
		origin = _throw_origin()
	_server_spear_ready_at = _now() + _config.spear_recharge
	_do_throw_spear.rpc(origin, direction.normalized())
	_do_throw_spear(origin, direction.normalized())


## The release, on every machine. No `play_throw()` here any more: the windup
## started the animation THROW_RELEASE_TIME ago on every peer and firing the
## OneShot again would snap the arm back to the start of the throw at the exact
## moment the spear leaves it.
@rpc("authority", "call_remote", "reliable")
func _do_throw_spear(origin: Vector3, direction: Vector3) -> void:
	_spear_ready_at = _now() + _config.spear_recharge
	cooldowns_changed.emit()

	if _gub.held_spear != null:
		_gub.held_spear.set_carried(false)
		_regrow_spear()

	AudioDirector.play_3d_varied(AudioDirector.SPEAR_THROW, origin)
	var spear := SPEAR.launch(_spawn_root(), _gub, origin, direction, Net.is_host)
	spear.struck_gub.connect(_on_spear_struck_gub.bind(spear))
	_gub.threw_spear.emit(origin, direction)


## The spear grows back in the hand when the cooldown ends. An empty hand is how
## other players read that you are harmless, so the timing has to be honest.
func _regrow_spear() -> void:
	await get_tree().create_timer(_config.spear_recharge).timeout
	if is_instance_valid(_gub) and _gub.held_spear != null:
		_gub.held_spear.set_carried(true)
		cooldowns_changed.emit()
		# Only the Gub whose hand it is needs to hear this — it is a readiness
		# cue for the player, not an event in the world that gives your
		# position away to everyone nearby.
		if _gub.is_local():
			AudioDirector.play_2d(AudioDirector.SPEAR_READY)


func _on_spear_struck_gub(victim: Gub, point: Vector3, bone: String,
		spear: SpearProjectile) -> void:
	# Only the host's copy of a spear is allowed to decide anything.
	if not spear.authoritative or not Net.is_host:
		return
	# The full velocity, not a direction: its magnitude is what makes the corpse
	# fly rather than sag, and a spear that has dropped out of a long arc should
	# shove one much less than a flat throw from close range.
	MatchState.report_kill(victim.peer_id, _gub.peer_id, Gub.Cause.SPEAR,
		point, spear.impact_velocity(), bone)


# --------------------------------------------------------------- inventory ---

## Host only. Called by `MatchState.claim_pickup` when this Gub walks over a
## drop, and by the testbeds, which are the only other thing in the build that
## can put an item in a hand (see the note in `tools/combat_range.gd`).
##
## The host counts and the host says so. A client cannot reach this: the whole
## point of `Combat` belonging to peer 1 on every machine (D-024) is that the
## `_do_*` broadcast below is refused unless it came from the host.
func grant_mushroom(count: int = 1) -> void:
	if not Net.is_host or count <= 0:
		return
	_server_mushrooms += count
	_broadcast_inventory()


func grant_lure(count: int = 1) -> void:
	if not Net.is_host or count <= 0:
		return
	_server_lures += count
	_broadcast_inventory()


func _broadcast_inventory() -> void:
	_do_set_inventory.rpc(_server_mushrooms, _server_lures)
	_do_set_inventory(_server_mushrooms, _server_lures)


## The host's word on what this Gub is holding, on every peer. Also what
## corrects a predictive decrement that the host refused — a client that spent a
## mushroom it did not have gets its count put back here rather than being left
## one short for the rest of its life.
@rpc("authority", "call_remote", "reliable")
func _do_set_inventory(mushrooms: int, lures: int) -> void:
	if _mushrooms == mushrooms and _lures == lures:
		return
	_mushrooms = mushrooms
	_lures = lures
	inventory_changed.emit()


# ---------------------------------------------------------------- mushroom ---

## Spend one mushroom, if there is one to spend.
##
## The *direction* travels with the request, which is new and is the whole
## reason this signature changed. A mushroom now goes where the camera is
## looking rather than where the body happens to be pointed, and the camera is
## the one thing about a Gub the host does not have: `GubCamera` shuts itself
## down on every copy but the owner's, so the host's copy of a remote Gub's rig
## has never moved. Asking it would plant every client's mushroom due north.
##
## So the client sends the look, exactly as `_request_throw_spear` sends the aim,
## and the host still runs both validation rays on it. What a modified client can
## do with this is choose a direction — which it could already do by turning —
## and no more: it cannot plant through a wall, over a cliff, or further than
## MUSHROOM_DISTANCE away.
func try_place_mushroom() -> void:
	if _mushrooms <= 0 or mushroom_use_cooldown() > 0.0:
		return
	var look := _look_direction()
	_mushroom_ready_at = _now() + _config.mushroom_use_delay
	# Spent on the click. If the host refuses it, `_do_set_inventory` puts it
	# back; leaving the count up until the round trip lands is what lets a held
	# key spend the same mushroom twice.
	_mushrooms -= 1
	inventory_changed.emit()
	cooldowns_changed.emit()
	if Net.is_host:
		_host_place_mushroom(look)
	else:
		_request_mushroom.rpc_id(1, look)


@rpc("any_peer", "call_remote", "reliable")
func _request_mushroom(look: Vector3) -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _gub.peer_id:
		return
	_host_place_mushroom(look)


func _host_place_mushroom(look: Vector3) -> void:
	if not _gub.alive:
		return
	if _server_mushrooms <= 0 or _now() < _server_mushroom_ready_at:
		# The asker has already decremented its own count, so tell it what the
		# truth is. Without this a refused placement is a mushroom that quietly
		# disappears out of the stack and never comes back.
		_broadcast_inventory()
		return
	# Flattened and normalised here rather than trusted: a client is free to
	# send a zero, a NaN, or a vector pointing at the sky.
	var flat := Vector3(look.x, 0.0, look.z)
	if flat.length_squared() < 0.0001:
		flat = _gub.facing()
	flat = flat.normalized()

	var spot := _mushroom_spot(flat)
	if spot == Vector3.INF:
		# Nowhere to put it — a wall, or a ledge. Refused, and refunded: the
		# alternative is losing a mushroom to a cliff edge you could not see.
		_broadcast_inventory()
		return
	_server_mushrooms -= 1
	_server_mushroom_ready_at = _now() + _config.mushroom_use_delay
	# The camera's yaw, not the body's, so the cap faces the way you were
	# looking. Planting one while strafing used to turn it side-on to you.
	var yaw := Gub.yaw_towards(flat)
	_do_place_mushroom.rpc(spot, yaw, _server_mushrooms)
	_do_place_mushroom(spot, yaw, _server_mushrooms)


## Find the ground just in front of the Gub, along `forward`. Returns
## `Vector3.INF` when there is nowhere sensible — at a cliff edge, or with a wall
## in the way — so that a mushroom is never planted in mid-air over the void.
##
## Both rays are unchanged from when this placed along the body's facing. They
## are what keeps a mushroom off a ledge and out of a wall, they never depended
## on which direction was handed in, and they are the half of this the host is
## really here for.
func _mushroom_spot(forward: Vector3) -> Vector3:
	var space := _gub.get_world_3d().direct_space_state
	var ahead := _gub.global_position + forward * MUSHROOM_DISTANCE \
		+ Vector3.UP * 0.9

	var blocked := PhysicsRayQueryParameters3D.create(
		_gub.global_position + Vector3.UP * 0.9, ahead)
	blocked.collision_mask = LAYER_WORLD | LAYER_DEPLOYABLE
	blocked.exclude = [_gub.get_rid()]
	if not space.intersect_ray(blocked).is_empty():
		return Vector3.INF

	var down := PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3.DOWN * 3.5)
	down.collision_mask = LAYER_WORLD
	var ground := space.intersect_ray(down)
	if ground.is_empty():
		return Vector3.INF
	return ground["position"]


@rpc("authority", "call_remote", "reliable")
func _do_place_mushroom(spot: Vector3, yaw: float, remaining: int) -> void:
	_mushroom_ready_at = _now() + _config.mushroom_use_delay
	cooldowns_changed.emit()
	# The host's remainder, which is what makes the predictive decrement above
	# safe: whatever the client guessed, this is the number.
	if _mushrooms != remaining:
		_mushrooms = remaining
		inventory_changed.emit()

	_prune_mushrooms()
	# Planting past the cap retires your oldest, rather than refusing — a
	# refused ability with a spent cooldown is the most annoying outcome.
	while _active_mushrooms.size() >= _config.mushroom_max_active:
		var oldest: Node = _active_mushrooms.pop_front()
		if is_instance_valid(oldest):
			oldest.call("wither")

	var mushroom := MUSHROOM.instantiate()
	_spawn_root().add_child(mushroom)
	mushroom.call("plant", spot, yaw, _config.mushroom_lifetime, _gub.peer_id)
	_active_mushrooms.append(mushroom)


func _prune_mushrooms() -> void:
	_active_mushrooms = _active_mushrooms.filter(func(m): return is_instance_valid(m))


# -------------------------------------------------------------------- lure ---

## The lure is thrown at a *point*, not along a direction, because it is slow
## enough for gravity to matter: fired flat at the crosshair it dropped after
## about five metres regardless of where you were aiming, which made it
## impossible to place. The host solves the arc that actually lands on the aim
## point — see `_lob_velocity`.
func try_throw_lure() -> void:
	if _lures <= 0 or lure_use_cooldown() > 0.0:
		return
	var origin := _throw_origin()
	var target := _aim_point()
	_lure_ready_at = _now() + _config.lure_use_delay
	_lures -= 1
	inventory_changed.emit()
	cooldowns_changed.emit()
	if Net.is_host:
		_host_throw_lure(origin, target)
	else:
		_request_lure.rpc_id(1, origin, target)


@rpc("any_peer", "call_remote", "reliable")
func _request_lure(origin: Vector3, target: Vector3) -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _gub.peer_id:
		return
	_host_throw_lure(origin, target)


func _host_throw_lure(origin: Vector3, target: Vector3) -> void:
	if not _gub.alive:
		return
	if _server_lures <= 0 or _now() < _server_lure_ready_at:
		# Same as the mushroom: a refusal has to put the asker's count back.
		_broadcast_inventory()
		return
	if origin.distance_to(_gub.global_position) > 3.0:
		origin = _throw_origin()
	_server_lures -= 1
	_server_lure_ready_at = _now() + _config.lure_use_delay
	# The client chooses a point; the host chooses the velocity. Sending a
	# velocity over the wire instead would let a modified client fling a lure at
	# any speed it liked.
	var velocity := _lob_velocity(origin, target)
	_do_throw_lure.rpc(origin, velocity, _server_lures)
	_do_throw_lure(origin, velocity, _server_lures)


## Launch velocity that carries a projectile of speed `LURE_SPEED` from `from`
## to `to` under `LURE_GRAVITY`.
##
## Of the two arcs that hit any reachable point, this picks the flatter one: it
## arrives sooner and reads as a thrown object rather than a mortar shell. If
## the point is out of range there is no solution at all, and the throw falls
## back to 45 degrees — the angle that goes furthest — aimed the right way, so
## an over-ambitious throw still travels as far as it possibly can instead of
## dropping at the thrower's feet.
func _lob_velocity(from: Vector3, to: Vector3) -> Vector3:
	var delta := to - from
	var flat := Vector3(delta.x, 0.0, delta.z)
	var distance := flat.length()
	if distance < 0.05:
		return Vector3.UP * LURE_SPEED
	var forward := flat / distance

	var speed_sq := LURE_SPEED * LURE_SPEED
	# Solving `y = x·tanθ − g·x² / (2·s²·cos²θ)` for θ gives this discriminant;
	# negative means no launch angle at this speed reaches the point.
	var discriminant := speed_sq * speed_sq - LURE_GRAVITY * (
		LURE_GRAVITY * distance * distance + 2.0 * delta.y * speed_sq)
	if discriminant < 0.0:
		return (forward + Vector3.UP).normalized() * LURE_SPEED

	var angle := atan2(speed_sq - sqrt(discriminant), LURE_GRAVITY * distance)
	return (forward * cos(angle) + Vector3.UP * sin(angle)) * LURE_SPEED


@rpc("authority", "call_remote", "reliable")
func _do_throw_lure(origin: Vector3, velocity: Vector3, remaining: int) -> void:
	_lure_ready_at = _now() + _config.lure_use_delay
	cooldowns_changed.emit()
	if _lures != remaining:
		_lures = remaining
		inventory_changed.emit()

	var animator := _gub.get_node_or_null("AnimationTree") as GubAnimator
	if animator != null:
		animator.play_throw()

	var lure := LURE.instantiate()
	_spawn_root().add_child(lure)
	AudioDirector.play_3d_varied(AudioDirector.LURE_THROW, origin)
	lure.call("launch_from", origin, velocity, _gub.peer_id, _config)


## The host telling this Gub's own client that a lure has caught it.
##
## The pull has to be applied by the victim's client because movement is
## client-authoritative and the host cannot simply move a body it does not own
## (D-004). `Lure` decides *who*; this is *where the answer is delivered*, and it
## is delivered here rather than on the lure that fired it because an RPC is
## addressed by node **path**. A lure has no path two machines agree on: every
## peer builds its own copy into `spawned_items`, and the moment a second one is
## in the air Godot disambiguates the duplicate name with a counter local to that
## process. `Players/Gub_<peer>/Combat` is a name both ends already have, and it
## is owned by the host, which is what makes "authority" the right mode for it.
@rpc("authority", "call_remote", "reliable")
func apply_lure_pull(centre: Vector3, strength: float, duration: float) -> void:
	if _gub != null:
		_gub.apply_lure(centre, strength, duration)


# ------------------------------------------------------------------- shared ---

## Everything a Gub spawns goes into one container so the arena can clear the
## lot between rounds without hunting through the scene tree.
func _spawn_root() -> Node:
	var root := get_tree().get_first_node_in_group("spawned_items")
	return root if root != null else get_tree().current_scene


## Called when a round restarts: wipe cooldowns so nobody starts a round unarmed,
## and wipe the carried stock so nobody starts one armed with anything else. A
## throw that was still winding up when the round ended is dropped with them —
## respawning with a spear already half thrown is nobody's idea of a fresh start.
##
## **Everything you were carrying is lost on death** (D-032). Letters are not —
## those live on `MatchState.stats` and are permanent progress for the match —
## but mushrooms and lures go back to zero, which is what makes a life worth
## keeping once you have gathered a few and what stops the leader compounding.
##
## Runs on every peer, from `MatchState._do_respawn`, so the host's copies are
## zeroed by the same call that zeroes everyone's. No broadcast needed, and
## sending one would race the respawn that caused it.
func reset() -> void:
	_windup_release_at = 0.0
	_spear_ready_at = 0.0
	# Zeroed with the rest, and it costs nothing: a respawning Gub is never the
	# Elder. The reason changed under this line with D-040 and the conclusion did
	# not — it used to be that dying took the robe away, and now it is that the
	# only death an Elder can have is the void, which ends the robe on the way
	# down. A stale deadline here would only matter on the day *that* stops being
	# true, which is exactly when nobody would think to look.
	_lightning_ready_at = 0.0
	_mushroom_ready_at = 0.0
	_lure_ready_at = 0.0
	_server_spear_ready_at = 0.0
	_server_lightning_ready_at = 0.0
	_server_mushroom_ready_at = 0.0
	_server_lure_ready_at = 0.0
	_mushrooms = 0
	_lures = 0
	_server_mushrooms = 0
	_server_lures = 0
	_prune_mushrooms()
	# Through `_refresh_hand` rather than straight at the spear, so a respawn
	# cannot hand back a shaft to a Gub the host still has a letter hold open
	# for. In practice a death ends the hold first (D-035) — but a respawn that
	# quietly disagreed with the gate would be the hardest kind of bug to see,
	# because everything about it looks right except that the throw does
	# nothing.
	_refresh_hand()
	cooldowns_changed.emit()
	inventory_changed.emit()
