class_name RangeBrain
extends RefCounted
## What drives one practice dummy: the base class, the registry, and the four
## things every behaviour in this folder needs (D-114).
##
## ## A brain places a dummy; it does not push one
##
## The single fact this whole folder is shaped by: a dummy Bog is `is_local()
## == false` on **every** peer, the host included, because `MatchState._create_bog`
## hands only its `Sync` node to peer 1 and leaves the body authored by a peer
## that does not exist. `Bog._physics_process` therefore takes its first branch,
## `_follow_network`, and returns. `move_and_slide` never runs for a dummy.
## `_apply_gravity` never runs for a dummy. There is no floor contact, no
## collision response, no gravity and no friction anywhere near one.
##
## So a behaviour cannot steer — it has nothing to steer *with*. Every brain
## here is a position as a function of time, written through the one door
## `RangeDummies.drive_to`, which sets the body and its snapshot together. That
## is less general than a steering force and very much easier to be right
## about: a strafer's lane is an interval rather than an emergent property of a
## push and a wall, and a jumper's arc lands where it started because it is
## solved rather than accumulated.
##
## ## The four things
##
##   `ground_y`   where the floor is, by ray. Not the station's own height: the
##                melee pit's floor is at -1.5 m, the parkour summit at +5.0,
##                the yard's ledge at +3.0, and a patrol crosses a ramp. One
##                rule that works on all of them beats a constant that works in
##                the lanes.
##   `look_yaw`   the nearest living **human** Bog, or the marker's own facing.
##                A target, not a step — `_follow_network` eases `body_yaw`
##                toward `sync_yaw` at `TURN_SPEED` on every peer already, so a
##                brain that smoothed its own yaw would be smoothing twice.
##   `param`      a number off the marker's meta, or this behaviour's default
##                for the zone it is standing in. Unit 2 authors `brain`,
##                `zone`, `live`, `range_m` and `lane` and nothing else, so
##                today every parameter comes from the default — but the lookup
##                is here so a key can be added to a marker later without a
##                code change.
##   `go`         `drive_to`, with this brain's id already in hand.
##
## ## Seeded, per dummy
##
## `_rng` is seeded from the zone and the peer id, so the same range twice gives
## the same wander, the same jitter and the same orbit direction. Brains run on
## the host **only** — clients never call `drive` — so this is repeatability for
## the gate and for a player learning a pattern, not agreement between peers.

## The world layer, from `project.godot`. Ground rays are cast against this and
## nothing else, so a dummy can never come to rest standing on another dummy's
## capsule (which is on the player layer).
const LAYER_WORLD := 1

## How far above and below itself a brain looks for the floor. 1.2 m up clears
## the lip of a kerb a dummy is standing against; 3.0 m down reaches from a
## marker authored a little above its slab and stops well short of the storey
## below on the parkour course.
const GROUND_UP := 1.2
const GROUND_DOWN := 3.0
## How far a dummy must move before its floor is worth asking about again. A
## standing dummy therefore casts one ray per life and a circler one per tick.
const GROUND_RESAMPLE := 0.05

## Name to script. Paths and not `preload`s, and that is load-bearing: every
## file below `extends RangeBrain`, so preloading them here would be a parse-time
## cycle that GDScript refuses. Resolved once each, by `load`, which is cached
## after the first call.
const SCRIPTS := {
	"stand": "res://scripts/world/range/brains/stand.gd",
	"strafe": "res://scripts/world/range/brains/strafe.gd",
	"patrol": "res://scripts/world/range/brains/patrol.gd",
	"popup": "res://scripts/world/range/brains/popup.gd",
	"jumper": "res://scripts/world/range/brains/jumper.gd",
	"rusher": "res://scripts/world/range/brains/rusher.gd",
	"wanderer": "res://scripts/world/range/brains/wanderer.gd",
	"circler": "res://scripts/world/range/brains/circler.gd",
}

## Every behaviour the range knows, in the order a station cycles them.
static func names() -> PackedStringArray:
	return PackedStringArray(SCRIPTS.keys())


var _dummies: RangeDummies
var _id: int = 0
## Where this dummy stands, and what it comes back to. The marker's own
## `global_transform`, so its **-Z is the way it faces** — the same convention
## `Spawns` has used since the first static map.
var _station: Transform3D = Transform3D.IDENTITY
var _meta: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## Seconds this behaviour has been running since the last `reset`.
var _t: float = 0.0

var _ground: float = 0.0
var _ground_known: bool = false
var _ground_at := Vector2.ZERO


## Build the brain called `name`, already wired to its dummy. An unknown name is
## a Bog that stands still, which is a perfectly good target and never an error:
## a station cycling a zone that has no strafer in it should not take the range
## down.
static func make(name: String, cfg: Dictionary) -> RangeBrain:
	var path: String = SCRIPTS.get(name, SCRIPTS["stand"])
	var script: GDScript = load(path)
	var brain: RangeBrain = script.new()
	brain._setup(cfg)
	return brain


## `cfg` is `RangeDummies._make_brain`'s: the registry, the id, the station and
## the marker's meta. Nothing here reaches for a singleton or knows which map it
## is standing on.
func _setup(cfg: Dictionary) -> void:
	_dummies = cfg.get("dummies")
	_id = int(cfg.get("id", 0))
	_station = cfg.get("station", Transform3D.IDENTITY)
	_meta = cfg.get("meta", {})
	_rng.seed = hash(zone()) * 1000 + _id
	reset()


## One physics tick. Host only. Overridden by every behaviour; the base class
## stands still, which is what `stand` is.
func drive(bog: Bog, _delta: float) -> void:
	hold(bog)


## Back to the beginning: a station resetting its zone, or a dummy that has just
## respawned on its station after being shot. Subclasses extend this and must
## call `super()`.
func reset() -> void:
	_t = 0.0
	_ground_known = false


# ------------------------------------------------------------------ the map ---

func zone() -> String:
	return String(_meta.get("zone", ""))


## A number the marker declared, or this behaviour's default. See the header for
## why the lookup exists when nothing authors these keys yet.
func param(key: String, fallback: float) -> float:
	return float(_meta.get(key, fallback))


## The marker's facing, flat: its own -Z.
func forward() -> Vector3:
	var out := -_station.basis.z
	out.y = 0.0
	return out.normalized() if out.length_squared() > 0.0001 else Vector3.FORWARD


## The marker's right, flat. A strafer shuttles along this.
func right() -> Vector3:
	var out := _station.basis.x
	out.y = 0.0
	return out.normalized() if out.length_squared() > 0.0001 else Vector3.RIGHT


func station_yaw() -> float:
	return Bog.yaw_towards(forward())


# ------------------------------------------------------------------- ground ---

## The floor under `at`, by ray, cached until the dummy has moved
## `GROUND_RESAMPLE`. Falls back to the last good answer — and, before there is
## one, to the station's own height, which is right everywhere the map is flat
## and is only ever a starting guess.
func ground_y(bog: Bog, at: Vector3) -> float:
	var here := Vector2(at.x, at.z)
	if _ground_known and here.distance_to(_ground_at) < GROUND_RESAMPLE:
		return _ground
	var space := bog.get_world_3d().direct_space_state
	var from := Vector3(at.x, at.y + GROUND_UP, at.z)
	var to := Vector3(at.x, at.y - GROUND_DOWN, at.z)
	var query := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		# Over the void, or past the end of a ledge. Keeping the last good
		# height is what stops a wanderer that clipped a corner from falling
		# through the world for the rest of the session.
		if not _ground_known:
			_ground = _station.origin.y
			_ground_known = true
			_ground_at = here
		return _ground
	_ground = (hit["position"] as Vector3).y
	_ground_known = true
	_ground_at = here
	return _ground


# ------------------------------------------------------------------ looking ---

## The nearest living **human** Bog within `look`, as a yaw; the marker's own
## facing when there is nobody to look at. Dummies are skipped, or a clump of
## five would spend the match staring at each other.
func look_yaw(from: Vector3, look: float = 30.0) -> float:
	var target := nearest_human(from, look)
	if target == null:
		return station_yaw()
	return yaw_to(from, target.global_position)


func nearest_human(from: Vector3, look: float = 30.0) -> Bog:
	var best: Bog = null
	var best_distance := look
	for bog: Bog in MatchState.living_bogs():
		if Net.is_dummy(bog.peer_id):
			continue
		var flat := bog.global_position - from
		flat.y = 0.0
		var distance := flat.length()
		if distance < best_distance:
			best_distance = distance
			best = bog
	return best


## The yaw that faces `to` from `from`, flat. Keeps the current station yaw when
## the two are on top of each other, rather than snapping to an arbitrary one.
func yaw_to(from: Vector3, to: Vector3) -> float:
	var flat := to - from
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return station_yaw()
	return Bog.yaw_towards(flat.normalized())


# ------------------------------------------------------------------- moving ---

## The one way a behaviour reaches the world.
func go(bog: Bog, pos: Vector3, yaw: float, vel: Vector3, grounded: bool = true,
		crouching: bool = false, jumped: bool = false) -> void:
	if _dummies == null:
		return
	_dummies.drive_to(bog, pos, yaw, vel, grounded, crouching, jumped)


## Stand exactly on the station, upright and still, facing whoever is nearest.
func hold(bog: Bog) -> void:
	var pos := _station.origin
	pos.y = ground_y(bog, pos)
	go(bog, pos, look_yaw(pos), Vector3.ZERO, true)
