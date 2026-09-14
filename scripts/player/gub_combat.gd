class_name GubCombat
extends Node
## The things a Gub can do to another Gub: throw a spear, plant a mushroom to
## hide behind, and lob a lure that drags people out from behind theirs — or, if
## it is the Elder, throw lightning instead of the spear.
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
## spear's 0.50 — and the *same clip* is played fast enough to have got there, at
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
# is 2.833 s, the animator plays the 1.067-1.900 s window of it, and tracking
# the `RightHand` bone against the hips through the built clip puts the hand
# 0.80 m above them and drawn back at 1.433 and 0.718 m in front of them at
# 1.567 — the furthest forward it ever gets. That extension is the release, and
# the window is played at whatever rate lands it half a second after the click,
# which on this clip is 1.0 (D-063). The hand is quickest at 1.600, on the way
# *down*, and a spear leaving then would read as a slam rather than a throw.
#
# Deriving it from the window and the rate is the point: whoever moves either
# of those without opening this file cannot leave the spear and the hand
# disagreeing, which is the bug D-025 exists because of.
#
# The throw OneShot's 0.08 s fade-in needs no allowance on top: the window opens
# on the quiet frame between the approach and the wind-up, so the blend is
# finished before anything the eye is following has started.

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

## How far the Elder's bolt reaches.
##
## Hitscan with no travel time and no drop would be a map-wide delete at any
## range you can see, so there has to be a number, and this one is *derived from
## the spear* rather than picked: it is the distance at which a flat spear throw
## stops being a flat spear throw. A spear leaves at 42 m/s and falls at 8 m/s²
## (`SpearProjectile.SPEED`/`DROP`), so over 28 m it is in the air 0.67 s and
## drops 1.78 m — one Gub's height, near enough exactly. Inside 28 m you point
## at a Gub and hit it; past it the throw becomes a judgement about arc, which
## is where D-014 says the skill in this fight lives.
##
## So the Elder owns exactly the band where the spear is a point-and-click
## weapon, and beyond it the spear is still the better tool — which is the
## shape a power-up should have. On Rust (42 x 64 m) that is most of a fight and
## not the length of the yard; on the island it is a clearing.
const LIGHTNING_RANGE := 28.0

## What a spear does to a Gub, and what a bolt does (D-062).
##
## Both are `Gub.MAX_HEALTH` — a full body — and both are written as that
## constant rather than as the number 100, which is the entire mechanism
## protecting the one-shot. A spear takes everything a Gub can have, so it kills
## a Gub at full health and it kills one at 3 health, and no arithmetic anywhere
## can make it do otherwise. Type 100 here instead and the promise survives only
## until somebody changes what a full Gub is worth.
##
## The bolt is the same for now, and deliberately so: D-053 chose "the blast is
## a kill or it is nothing — there is no falloff, because there is no health in
## this game for a falloff to take away". There is one now, and falloff is
## suddenly possible — but the Elder is a twenty-second power-up that already
## cannot die, and a bolt that only wounds is a different weapon, to be decided
## with a playtest behind it rather than on the way past.
const SPEAR_DAMAGE := Gub.MAX_HEALTH
const LIGHTNING_DAMAGE := Gub.MAX_HEALTH

## How hard a bolt throws the body, as the velocity handed to `report_damage`.
##
## The ragdoll turns a blow into motion at `GubRagdoll.IMPACT_TRANSFER` = 0.15,
## so a flat spear arriving at its full 42 m/s gives a corpse about 6.3 m/s.
## This is a little over twice that, which is the difference between a body
## knocked over and a body *thrown* — and the brief for this weapon is that it
## should be seen from the other side of the map.
const LIGHTNING_IMPULSE := 90.0

## How far back along the bolt the blast's line-of-sight rays start from, so a
## ray fired from a point *on* a wall or on the ground does not begin inside the
## surface it is testing against and report itself blocked.
const BLAST_LOS_BACKOFF := 0.1

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
var _lightning_ready_at: float = 0.0
var _mushroom_ready_at: float = 0.0
var _lure_ready_at: float = 0.0

## Host-side, authoritative. Never trusted from the wire.
var _server_spear_ready_at: float = 0.0
var _server_lightning_ready_at: float = 0.0
var _server_mushroom_ready_at: float = 0.0
var _server_lure_ready_at: float = 0.0

## What this Gub is carrying. Unbounded on purpose: there is no cap, no slot
## limit and no inventory screen, because the only decision worth having here is
## "spend it or keep it" and a cap would add "throw one away" to that for no
## gain. Starts at zero on spawn and on every respawn — see `reset`.
##
## Predictive, like the cooldowns above: spending decrements immediately so the
## HUD moves on the click, and the host's `_do_*` broadcast carries the real
## remainder and corrects it. Every peer keeps this for every Gub, which costs
## two ints and means a spectator's HUD is right about the Gub it is watching.
var _mushrooms: int = 0
var _lures: int = 0

## Host-side, authoritative. The only counts that can actually spend anything.
var _server_mushrooms: int = 0
var _server_lures: int = 0

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
	# Every peer's copy of every Gub listens, not just the local one: the whole
	# point of the hold is that it is visible across the clearing (D-035), and
	# what makes it visible is this Gub's hand on *your* screen. The connection
	# dies with the node, so there is nothing to undo on a respawn or a leave.
	MatchState.letter_hold_changed.connect(_on_letter_hold_changed)
	# And the same for the robe, for the same reason: the crackle around an
	# Elder's fist is the tell that the most dangerous Gub in the clearing is
	# loaded, and it has to be on *your* screen, not only on theirs (D-038).
	MatchState.elder_changed.connect(_on_elder_changed)


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
	_tick_hand()
	_tick_charge()
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


func lightning_cooldown() -> float:
	return maxf(0.0, _lightning_ready_at - _now())


## Seconds until another mushroom may be placed. Not a cooldown on the *ability*
## — there is nothing to recharge — only on how fast the stack can be emptied.
func mushroom_use_cooldown() -> float:
	return maxf(0.0, _mushroom_ready_at - _now())


func lure_use_cooldown() -> float:
	return maxf(0.0, _lure_ready_at - _now())


## How many this Gub is carrying. Zero is the normal state at the start of a
## life, so the HUD has to render an empty slot as ordinary rather than broken.
func mushroom_count() -> int:
	return _mushrooms


func lure_count() -> int:
	return _lures


## Whether there is a spear to throw. **The one gate**: the throw asks it, the
## host asks it before it will honour a request, the aim marker asks it, and the
## hand is drawn from it. Anything that wants to take a Gub's spear away adds a
## clause here and gets all four for free.
##
## A letter hold is the second such clause (D-035). A Gub holding a card up
## cannot throw, and the reason is not a rule bolted on next to this one — it is
## that the hand the spear would come out of has a letter in it.
func has_spear() -> bool:
	return not is_elder() and spear_cooldown() <= 0.0 and not is_holding_letter()


## Is this Gub the Elder? Asked of `MatchState` every time rather than mirrored
## into a field here, for exactly the reason `is_holding_letter` is: the robe is
## match state, the host owns it, and a copy in this file would be a second
## opinion about who is dangerous.
func is_elder() -> bool:
	return _gub != null and MatchState.is_elder(_gub.peer_id)


## The Elder's gate, and the mirror image of `has_spear()` in every way that
## matters: the cast asks it, the host asks it before it will honour a request,
## and the hand is drawn from it.
##
## It shares the *hold* half of the spear's gate deliberately (D-038). An Elder
## mid-letter-hold cannot fire, because otherwise the hold stops being a
## vulnerability for exactly the player who most needs to have one — and the
## hand it would come out of is holding a card.
##
## It does **not** share the recharge half. They are different clocks on purpose:
## a spear can be dodged, a bolt cannot, so the bolt waits longer
## (`MatchConfig.lightning_cooldown`).
func has_lightning() -> bool:
	return is_elder() and lightning_cooldown() <= 0.0 and not is_holding_letter()


## Is this Gub in the middle of a letter hold?
##
## Asked of `MatchState` every time rather than mirrored into a field here, and
## that is the whole design. The hold is owned by the host, replicated to every
## peer, and ticked in exactly one place; a copy in this file would be a second
## clock, and a second clock is how a Gub ends up with a card in its hand and a
## spear it is allowed to throw. There is no local prediction of a hold for the
## same reason — the letter is the prize and the host is the only thing that
## hands it out.
func is_holding_letter() -> bool:
	return _gub != null and MatchState.is_holding_letter(_gub.peer_id)


## The whole spear cycle: the windup you have already committed to, plus the
## recharge that follows it. What the click spends, so a second click during the
## windup is refused. Nothing on the HUD divides by it any more: the spear tile
## times the recharge alone, from the release, and says nothing during the
## windup (D-054) — this denominator was the ring that swept from the click.
func spear_cycle() -> float:
	return GubAnimator.THROW_RELEASE_TIME + _config.spear_recharge


func lightning_cycle() -> float:
	return _config.lightning_delay + _config.lightning_cooldown


## How fast the `Throw` clip is played for this Gub's windup.
##
## The spear's own 1.0 for an ordinary Gub — the clip's authored speed, since
## D-063 windowed it to land its release on the half second it is wanted at. For
## an Elder, whatever puts that same release on `lightning_delay` (D-040): 2.5x
## at the default 0.2 s, where it was 5.67x on the old clip. Derived from the dial every time it is asked
## rather than cached, so a host who drags the delay mid-match does not leave one
## Gub throwing at the old rate for the rest of its life.
##
## Asked by `_play_windup` on every peer, not only the caster's, which is the
## reason it is a function of replicated state alone: the rate never travels, so
## it can never travel *wrong*.
func windup_rate() -> float:
	if not is_elder():
		return GubAnimator.THROW_RATE
	return GubAnimator.throw_rate_for_release(_config.lightning_delay)


## How long after the click this Gub's throw actually leaves the hand.
##
## For the spear this is `GubAnimator.THROW_RELEASE_TIME` and always has been.
## For an Elder it is the dial — except at the very bottom of the dial's range,
## where `windup_rate()` has hit `THROW_RATE_MAX` and the arm cannot be sped up
## any further. There the bolt leads the hand rather than the hand being made to
## catch an impossible number, which at a delay of zero is the setting's whole
## point. Everywhere above about 0.14 s the two are the same number.
func release_delay() -> float:
	return _config.lightning_delay if is_elder() else GubAnimator.THROW_RELEASE_TIME


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
	# Tested from the Gub's own depth outwards: nothing behind the thrower can be
	# thrown at, and the wall that pushed the camera in is behind it (D-045).
	var query := PhysicsRayQueryParameters3D.create(
		origin + direction * float(ray.get("clear_of", 0.0)),
		origin + direction * MAX_AIM_DISTANCE)
	query.collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_DEPLOYABLE
	query.exclude = [_gub.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return origin + direction * MAX_AIM_DISTANCE
	var point: Vector3 = hit["position"]
	if origin.distance_to(point) < MIN_AIM_DISTANCE:
		return origin + direction * MIN_AIM_DISTANCE
	return point


## The way the camera is pointing, flattened to horizontal and normalised.
##
## Only meaningful on the Gub's own client — `GubCamera` turns itself off on
## every other copy — so this is called where the input is read and the answer
## travels, never on the host's copy of somebody else's Gub. The fallback to the
## body's facing is the same one `_aim_point` makes and covers the same case: a
## Gub with no rig at all, which is every Gub in `tools/match_rules.gd` and every
## remote Gub everywhere.
func _look_direction() -> Vector3:
	var rig := _gub.get_node_or_null("CameraRig") as GubCamera
	if rig == null:
		return _gub.facing()
	var direction: Vector3 = rig.aim_ray()["direction"]
	var flat := Vector3(direction.x, 0.0, direction.z)
	# Straight down or straight up: there is no horizontal component to take, so
	# fall back rather than normalising a zero.
	if flat.length_squared() < 0.0001:
		return _gub.facing()
	return flat.normalized()


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
	# An Elder gets no ring, and that is not an oversight. The marker answers
	# "where will this land given the drop", and a hitscan bolt has no drop to
	# answer about: it lands exactly on the crosshair. Drawing one anyway would
	# be the HUD promising a ballistic arc for a weapon that has none.
	if rig == null or not rig.is_aiming() or is_elder() 			or not (has_spear() or is_winding_up()):
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
	# The Elder's click runs the same clip through the same windup and comes out
	# the other end as a bolt (D-038). It is branched here rather than at the
	# input so that everything downstream of a click — the animation, the relay
	# to the other peers, the cancel-on-death, the cancel-on-hold — is one piece
	# of code with one set of edge cases.
	if is_elder():
		try_cast_lightning()
		return
	if not has_spear() or is_winding_up():
		return

	_windup_release_at = _now() + GubAnimator.THROW_RELEASE_TIME
	# The input has been spent whether or not the spear has left yet, so the
	# click spends it. A tile that sits lit through half a second of windup only
	# invites the second click that will be refused.
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
	#
	# Walking over a letter card mid-windup cancels it the same way (D-035). The
	# cooldown is handed back, which is not generosity: the host never saw a
	# throw, so its `_server_spear_ready_at` never moved, and leaving the local
	# prediction spent would be this client alone believing in a recharge
	# nothing else has. The spear comes back the moment the hold ends.
	if not _gub.alive or not _gub.is_local() or is_holding_letter():
		if _gub.alive and is_holding_letter():
			_spear_ready_at = 0.0
			cooldowns_changed.emit()
		_windup_release_at = 0.0
		return
	if _now() < _windup_release_at:
		return
	_windup_release_at = 0.0

	var origin := _throw_origin()
	var direction := (_aim_point() - origin).normalized()
	if direction.length_squared() < 0.001:
		return
	# Asked *here* and not at the click, on purpose. Everything else about this
	# throw is decided at the release — the aim is, and that is the whole of
	# D-025 — so a Gub that walked over a robe mid-windup fires the weapon it has
	# now rather than the one it had when it pressed the button. The host asks
	# the same question again on arrival and is the copy that counts.
	#
	# Its *timing* stays the spear's, which is right: the robe arrived after the
	# arm did, the clip is already playing at the spear's rate, and the release is where that
	# arm actually lets go. A bolt out of a spear's windup is a fifth of a second
	# late by the dial and exactly on time by the animation, and the animation is
	# what anybody is looking at.
	if is_elder():
		if Net.is_host:
			_host_cast_lightning(origin, direction)
		else:
			_request_cast_lightning.rpc_id(1, origin, direction)
		return
	if Net.is_host:
		_host_throw_spear(origin, direction)
	else:
		_request_throw_spear.rpc_id(1, origin, direction)


## Start the arm going back, at whichever rate this Gub's weapon needs (D-040).
##
## The rate is worked out here rather than handed in, and that is what keeps the
## Elder's fast windup honest on the seven machines that are only watching: this
## same function is what `_do_throw_windup` calls on every other peer, and it
## reaches the same answer from the same replicated robe and the same replicated
## config. Sending the rate with the relay would have been one more number on
## the wire that could be a different number at the far end.
func _play_windup() -> void:
	var animator := _gub.get_node_or_null("AnimationTree") as GubAnimator
	if animator != null:
		animator.play_throw(windup_rate())


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
	# The authoritative half of the hold gate (D-035). The client refuses to ask
	# while it is holding a card; this is what makes that true of a client that
	# has been modified not to, and the row it reads is the host's own — the
	# only copy of a hold that can be trusted or finished.
	if is_holding_letter():
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

	# The fist empties on the frame the spear leaves it rather than on the next
	# one, which is what `_tick_hand` would otherwise do — a single frame, but
	# the single frame in which everybody watching would see a spear in a hand
	# that has just thrown one.
	_refresh_hand()

	AudioDirector.play_3d_varied(AudioDirector.SPEAR_THROW, origin)
	var spear := SPEAR.launch(_spawn_root(), _gub, origin, direction, Net.is_host)
	spear.struck_gub.connect(_on_spear_struck_gub.bind(spear))
	_gub.threw_spear.emit(origin, direction)


## Put the spear back in the hand when the recharge ends — and take it away if
## something else did.
##
## **A poll rather than a timer, and this is the second one in this file** — see
## `_tick_charge`, which is the same shape for the Elder's crackle and carries
## the same argument. What used to be here was a `SceneTreeTimer` started at the
## moment the throw was made, awaiting `spear_recharge` and then calling
## `_refresh_hand` once:
##
##     await get_tree().create_timer(_config.spear_recharge).timeout
##     _refresh_hand()
##
## which is two clocks measuring one interval. `_spear_ready_at` is a
## `Time.get_ticks_msec()` deadline and a `SceneTreeTimer` is a sum of frame
## deltas; they agree to about a millisecond, and a millisecond the wrong way
## means `has_spear()` is still false on the frame the timer fires. The hand is
## then correctly left empty, by a callback that has already been spent —
## **nothing ever asks again**, and the spear does not come back until the next
## death. That is exactly the "the spear model is not reliably reappearing"
## that was reported, and it is why a race lost by a millisecond reads as a
## whole feature being flaky.
##
## Making the timer *report* rather than *decide* was right and is kept: this
## still asks `_refresh_hand`, which asks `has_spear()`, which is the one gate
## the throw is refused by (D-035, D-036). A letter hold may have started during
## the recharge, and a shaft that put itself back would sit in a fist that is
## supposed to be holding a card. **The bug was the missing retry, not the
## delegation.** So the retry is every frame, off the only clock that decides
## anything, and the `await` is gone rather than kept beside it — two clocks
## measuring one interval is the fault, and leaving one of them in place as an
## optimisation would leave it there to be believed.
##
## Cheap by construction, the same way `_tick_charge` is: one boolean
## comparison, doing nothing at all unless the hand and the gate have come
## apart. That is a handful of times a second across every Gub in the match.
func _tick_hand() -> void:
	if _gub.held_spear == null:
		return
	var want := _wants_shaft()
	if _gub.held_spear.is_carried() == want:
		return
	_refresh_hand()
	cooldowns_changed.emit()
	# Only on the transition into "armed", and only for the Gub whose hand it
	# is: it is a readiness cue for the player, not an event in the world that
	# gives your position away to everyone nearby. The `is_carried() == want`
	# check above is what makes "once" true — the poll runs every frame and this
	# line is only reached on the frame the answer changed.
	#
	# `has_spear()` and not `want`, because `want` is also true through a
	# windup: a chime at the moment the arm goes back would be announcing a
	# spear that is on its way out of the hand rather than back into it. And a
	# Gub mid-letter-hold never reaches here at all, which is the point D-035
	# makes about a cue that lies.
	if want and _gub.alive and _gub.is_local() and has_spear():
		AudioDirector.play_2d(AudioDirector.SPEAR_READY)


## Should this fist be holding a shaft right now?
##
## One expression, asked by the two places that could disagree about it — the
## hand refresh that acts on it and the per-frame poll that notices it has gone
## stale — for exactly the reason `_wants_crackle` is written this way. Two
## copies that drift by one clause is a Gub whose hand is repainted on every
## frame for ever.
##
## The `is_winding_up()` clause is D-025's carve-out: between the click and the
## release the spear has been paid for but has not left, and a hand that emptied
## on the click would be an arm going back with nothing in it. `has_spear()`
## already answers no for an Elder, so the extra `is_elder()` is only about that
## window — an Elder winding a bolt up must not be handed a shaft by it.
func _wants_shaft() -> bool:
	return not is_elder() and not is_holding_letter() \
		and (has_spear() or is_winding_up())


# --------------------------------------------------------------- lightning ---

## The Elder's click. Reached from `try_throw_spear` and shaped exactly like it,
## because it *is* it: the same clip, the same aim read at the same moment
## (D-038).
##
## What is deliberately not here is a charge-up, a beam, a channel or a warning
## ring on the ground.
##
## **The window the target gets is now a fifth of a second, not two thirds of
## one** (D-040). D-038's argument for reusing the release time was that the
## animation is the warning — and it still is, it is just a much shorter one:
## the user played it and asked for "basically no delay", and a weapon that
## announces itself for two thirds of a second is not the weapon they were
## asking for. The clip is sped up to match rather than cut short
## (`windup_rate`), because an arm still on its way back when the bolt leaves is
## the one thing that would read as broken rather than as fast.
func try_cast_lightning() -> void:
	if not has_lightning() or is_winding_up():
		return

	# The dial, not the clip. `_tick_windup` compares against this, and the clip
	# is then sped up to arrive at the same moment — the number leads and the
	# animation follows, which is the opposite way round from the spear and is
	# the whole of what D-040 changed here.
	_windup_release_at = _now() + release_delay()
	# Spent on the click, like the spear's, so a second click during the windup
	# is refused by the gate rather than by nothing.
	_lightning_ready_at = _now() + lightning_cycle()
	cooldowns_changed.emit()

	# The hand is deliberately *not* refreshed here. The crackle stays through
	# the windup exactly as the shaft does — `_refresh_hand` allows both while
	# `is_winding_up()` — because an arm going back with nothing in it is the
	# bug that carve-out exists to prevent, and it would look identical here.
	_play_windup()
	if Net.is_host:
		_host_throw_windup()
	else:
		_request_throw_windup.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_cast_lightning(origin: Vector3, direction: Vector3) -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _gub.peer_id:
		return
	_host_cast_lightning(origin, direction)


## The shot, decided on the host and nowhere else.
##
## Hitscan: a ray, no projectile, no travel time, nothing to lead. Which is also
## why the cooldown is longer than the spear's — see `MatchConfig`.
##
## **Cover works, and that is the reason the bolt comes out of a hand rather
## than out of the sky.** The ray collides with the world and with deployables,
## so a shield mushroom stops it exactly as it stops a spear. A strike from
## above would have been easier to aim and easier to draw, and it would have
## silently broken the one object in this game whose entire definition is "cover
## you cannot be hit through" (D-038).
func _host_cast_lightning(origin: Vector3, direction: Vector3) -> void:
	if not _gub.alive or not is_elder():
		return
	if _now() < _server_lightning_ready_at:
		return
	# The authoritative half of the hold gate, the same one the throw has
	# (D-035): the client refuses to ask while it is holding a card, and this is
	# what makes that true of a client that has been modified not to.
	if is_holding_letter():
		return
	# The client picks the aim, never the spawn point — clamping the origin to
	# somewhere near the Gub is what stops a modified client casting from across
	# the map, and it is the same clamp the spear uses.
	if origin.distance_to(_gub.global_position) > 3.0:
		origin = _throw_origin()
	# A client is free to send a zero, a NaN, or a vector pointing nowhere.
	var aim := direction
	if not aim.is_finite() or aim.length_squared() < 0.0001:
		aim = _gub.facing()
	aim = aim.normalized()
	_server_lightning_ready_at = _now() + _config.lightning_cooldown

	var hit := _lightning_hit(origin, aim)
	var point: Vector3 = hit.get("position", origin + aim * LIGHTNING_RANGE)
	var victim := hit.get("collider") as Gub
	# A surface normal, or nothing when the bolt stopped on a body or on thin
	# air. It decides only whether there is a scorch to draw and which way the
	# sparks come off, and a body is neither scorched nor a wall to bounce from.
	var normal: Vector3 = Vector3.ZERO
	if victim == null and hit.has("normal"):
		normal = hit["normal"]
	# The blast only exists where the bolt *landed* (D-053). A bolt that ran out
	# into the sky or to the end of its range struck nothing, and a sphere of
	# death hanging in mid-air 28 m away is not "hit pretty close", it is a
	# second, invisible weapon. Zero travels as "no ring".
	var radius := _config.lightning_radius if not hit.is_empty() else 0.0

	# The bolt is broadcast before the kill is reported, so that on every peer
	# the light arrives with the body rather than after it. `report_kill` sends
	# its own death message and both are reliable, so the order they are sent in
	# is the order they land in.
	_do_cast_lightning.rpc(origin, point, normal, radius)
	_do_cast_lightning(origin, point, normal, radius)

	if victim != null:
		# Everything about *whether* this hit does anything — spawn protection,
		# friendly fire, a victim who is already dead, an Elder's ward — belongs
		# to `report_damage` and is not second-guessed here. The bolt landed on
		# them either way, which is the truthful picture: a protected Gub was
		# struck and was not hurt.
		MatchState.report_damage(victim.peer_id, _gub.peer_id, LIGHTNING_DAMAGE,
			Gub.Cause.LIGHTNING, point, aim * LIGHTNING_IMPULSE,
			SpearProjectile.nearest_bone(victim, point))

	if radius <= 0.0:
		return
	for other: Gub in _blast_victims(point, point - aim * BLAST_LOS_BACKOFF,
			radius, victim):
		# The same door the direct hit goes through, for the same reasons. The
		# blast is a kill or it is nothing — no falloff with distance from the
		# impact, which was forced when the game had no health in it and is a
		# choice now that it has: see `LIGHTNING_DAMAGE`. Everything inside the
		# ring takes a full body's worth.
		var chest := other.body_axis_nearest(point)
		var shove := chest - point
		if shove.length_squared() < 0.0001:
			shove = aim
		MatchState.report_damage(other.peer_id, _gub.peer_id, LIGHTNING_DAMAGE,
			Gub.Cause.LIGHTNING, chest, shove.normalized() * LIGHTNING_IMPULSE,
			SpearProjectile.nearest_bone(other, point))


## Every living Gub the blast at `point` reaches, other than the caster and the
## one the bolt landed on directly (D-053).
##
## "Reaches" is two things, both required. The *surface* of the Gub's capsule is
## within `radius` of the impact — `Gub.distance_to_body`, so the ring drawn at
## `radius` around the impact is exactly the line a body has to be touching —
## and there is a clear line from the impact to the body through the world and
## through deployables. The second is what keeps cover meaning what D-038 says
## it means: a bolt into the far side of a wall or into a shield mushroom's cap
## does not kill the Gub crouched behind it.
##
## Line of sight is tried to the nearest point on the Gub's axis and then to the
## middle of the capsule, so a body half behind a low ledge is still in the open
## by its chest. Other Gubs are not cover — the ray does not test the player
## layer — because a blast that one body shields another from is a rule nobody
## could read off the screen.
func _blast_victims(point: Vector3, los_from: Vector3, radius: float,
		direct: Gub) -> Array[Gub]:
	var out: Array[Gub] = []
	var space := _gub.get_world_3d().direct_space_state
	for other: Gub in MatchState.gubs.values():
		# Dead Gubs keep their collision (D-043) and are not there to be killed.
		if not is_instance_valid(other) or other == _gub or other == direct \
				or not other.alive:
			continue
		if other.distance_to_body(point) > radius:
			continue
		var targets: Array[Vector3] = [other.body_axis_nearest(point),
			other.body_centre()]
		for target: Vector3 in targets:
			var query := PhysicsRayQueryParameters3D.create(los_from, target)
			query.collision_mask = LAYER_WORLD | LAYER_DEPLOYABLE
			query.collide_with_areas = false
			query.collide_with_bodies = true
			if space.intersect_ray(query).is_empty():
				out.append(other)
				break
	return out


## What the bolt hit, or an empty dictionary for thin air.
##
## Dead Gubs are excluded along with the caster. A Gub that has been killed keeps
## its collision until it respawns — only the body is hidden — so without this a
## corpse's invisible capsule would eat bolts for the length of a respawn delay,
## which is three seconds of a weapon that visibly stops in mid-air.
func _lightning_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	var space := _gub.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * LIGHTNING_RANGE)
	query.collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_DEPLOYABLE
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var skip: Array[RID] = [_gub.get_rid()]
	for other: Gub in MatchState.gubs.values():
		if is_instance_valid(other) and not other.alive:
			skip.append(other.get_rid())
	query.exclude = skip
	return space.intersect_ray(query)


## The bolt, on every machine. Everything visible about this weapon happens
## here; the host's copy of this call is not special in any way except that it
## is the one that already knew the answer.
@rpc("authority", "call_remote", "reliable")
func _do_cast_lightning(origin: Vector3, point: Vector3, normal: Vector3,
		radius: float = 0.0) -> void:
	_lightning_ready_at = _now() + _config.lightning_cooldown
	cooldowns_changed.emit()
	# The fist goes dark on every peer's copy, which is the whole point of the
	# tell: everyone watching an Elder can see that it has just spent its shot.
	_refresh_hand()
	# The radius travels with the bolt rather than being read off each peer's
	# own config, so the ring on every screen is the one the host killed with.
	LightningBolt.strike(_spawn_root(), origin, point, normal, _gub, radius)


## Put the crackle back when the cooldown ends — and take it away if something
## else did.
##
## A **poll rather than a timer**, and that is the whole of why it exists. The
## shaft used to be put back by a `SceneTreeTimer` started at the moment
## `_spear_ready_at` was set, which is two clocks measuring one interval: a
## `Time.get_ticks_msec()` deadline and a sum of frame deltas. They agree to
## within a millisecond, and a millisecond the wrong way means `has_spear()` is
## still false on the frame the timer fires and nothing ever asks again. This
## asks the only clock that decides anything, every frame, and cannot drift from
## it.
##
## That argument was written here first and was right, and the spear went on
## losing the race it describes for a whole session anyway, because it was made
## about the crackle rather than about both. `_tick_hand` is now its twin — the
## same six lines for the shaft — and the two of them are the only things in
## this file that decide what is in a Gub's hand.
##
## Cheap by construction: one boolean comparison, only on Gubs that are the
## Elder, doing nothing at all unless the hand and the gate have come apart.
func _tick_charge() -> void:
	if _gub.held_spear == null or not is_elder():
		return
	var want := _wants_crackle()
	if _gub.held_spear.is_charged() == want:
		return
	_refresh_hand()
	cooldowns_changed.emit()
	# Only the Gub whose hand it is needs to hear this, and only when the hand
	# genuinely lit up: it is a readiness cue for the player, not an event in
	# the world that gives an Elder's position away to everyone nearby. Borrowed
	# rather than invented, like the pickup's — there is no second chime in
	# `audio/sfx/` and SPEAR_READY already means "you can act again".
	if want and _gub.is_local() and has_lightning():
		AudioDirector.play_2d(AudioDirector.SPEAR_READY)


## Should this fist be crackling right now?
##
## One expression, asked by the two places that could disagree about it — the
## hand refresh that acts on it and the per-frame poll that notices it has gone
## stale. They were two copies of the same condition for about ten minutes, and
## two copies that drift by one clause is a Gub whose hand is repainted on every
## frame for ever.
##
## The `is_winding_up()` clause is the same carve-out the shaft gets (D-025):
## between the click and the release the shot has been paid for but has not left,
## and a hand that emptied on the click would be an arm going back with nothing
## in it.
func _wants_crackle() -> bool:
	return is_elder() and not is_holding_letter() 		and (has_lightning() or is_winding_up())


func _on_elder_changed(peer_id: int) -> void:
	if _gub == null or peer_id != _gub.peer_id:
		return
	_refresh_hand()
	cooldowns_changed.emit()


# -------------------------------------------------------------- the hand ---

## Put the right thing in the Gub's right hand.
##
## Every path that can change what is in it ends here — a recharge finishing, a
## respawn, a hold starting or ending — and this asks `has_spear()`, which is
## the same question the throw is gated on. That is the single source of truth
## the spear's own header insists on, now with a second reason in it: the hand
## cannot show a spear the throw would refuse, or a card while the throw is
## allowed, because there is nowhere for a second opinion to live.
##
## The windup is the one carve-out and it is not an exception to the rule: from
## the click to the release the spear is still in the fist and `has_spear()` is
## already false, because the cooldown starts on the click (D-025). The arm
## going back with an empty hand is the bug that clause prevents. It lives in
## `_wants_shaft` beside the rest of the condition rather than inline here, so
## that the poll which notices this has gone stale is asking the same question.
##
## Idempotent and cheap, which is what lets `_tick_hand` call it as often as it
## likes: every path that can change the answer ends here, and so does a frame
## on which nothing changed except that a deadline passed.
func _refresh_hand() -> void:
	if _gub == null or _gub.held_spear == null:
		return
	var holding := is_holding_letter()
	_gub.held_spear.set_carried(_wants_shaft())
	# Runs on every peer's copy of every Gub, which is the point: a Gub ten
	# seconds from a letter has to be readable from across the clearing by the
	# people who might stop it, not only by the player holding the card. The
	# Elder's crackle is the same argument with a shorter fuse.
	_gub.held_spear.set_letter(
		MatchState.letter_hold_letter(_gub.peer_id) if holding else 0)
	_gub.held_spear.set_charged(_wants_crackle())


func _on_letter_hold_changed(peer_id: int) -> void:
	if _gub == null or peer_id != _gub.peer_id:
		return
	_refresh_hand()
	_refresh_carrier_marker()


## The card over the head says the same thing as the card in the fist, from the
## same row and on the same signal, so the two cannot disagree about who is
## holding (D-050). Every end of a hold — banked, killed, a teammate banking the
## same letter, the match ending — arrives here as the row going away.
func _refresh_carrier_marker() -> void:
	if _gub.carrier_marker == null:
		return
	var letter := MatchState.letter_hold_letter(_gub.peer_id)
	_gub.carrier_marker.set_carrying(
		MatchState.letter_name(letter) if letter != 0 else "", Pickup.LETTER_COLOUR)


func _on_spear_struck_gub(victim: Gub, point: Vector3, bone: String,
		spear: SpearProjectile) -> void:
	# Only the host's copy of a spear is allowed to decide anything.
	if not spear.authoritative or not Net.is_host:
		return
	# The full velocity, not a direction: its magnitude is what makes the corpse
	# fly rather than sag, and a spear that has dropped out of a long arc should
	# shove one much less than a flat throw from close range.
	#
	# `SPEAR_DAMAGE` and not a kill: a spear is one shot because of what the
	# number is, not because this line says "die" (D-062).
	MatchState.report_damage(victim.peer_id, _gub.peer_id, SPEAR_DAMAGE,
		Gub.Cause.SPEAR, point, spear.impact_velocity(), bone)


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
