class_name RangeTarget
extends StaticBody3D
## A ringed wooden board on a stake: the range's basic non-Bog target, and the
## base the gong takes its plumbing from.
##
## **Damage lands only on Bogs, and it still does.** `MatchState.report_damage`
## is the one door, keyed by `peer_id`, and nothing here goes through it. A board
## has no health; it has *rings*, and what it owes you is a number, a knock and a
## sound. So a projectile asks the thing it struck one question before it asks
## whether it is a body — `collider.has_method("range_hit")` — and anything that
## answers is a target.
##
## A duck-typed method check rather than a cast against this class, deliberately:
## what a board and a gong share is a contract, not an implementation, and a
## station or a later map should be able to answer it without inheriting a
## plank. What *is* inherited here is only the plumbing that must not be written
## three times — the group, the radius, the one RPC, and the host-side scoring
## call. The behaviour is the subclass's.
##
## ### What travels, and what does not
##
## Nothing, for a projectile hit. Spear and arrow flight is pure ballistics from
## a replicated launch, so every peer's own copy strikes this board at the same
## point on the same physics tick and can knock it, ring it and score it
## locally. The sword is the exception — its geometry is the host's alone
## (D-068) — and `range_hit_broadcast` is the one path that sends anything.

## Metres across, by kind. A `board_small` is a lane target at 8 and 22 m; the
## `board_large` is the bow lane's, out at 30 m, and is bigger because a board
## you cannot see is not a target, it is a rumour.
const WIDTH := {"board_small": 0.9, "board_large": 1.4}
const THICKNESS := 0.07
## Height of the board's centre above its marker. Chest height on a 1.80 m Bog,
## so a flat shot at a board and a flat shot at a dummy are the same shot.
const CENTRE_HEIGHT := 1.30

## The three rings, as a fraction of the board's radius, and what each is worth.
## Read outward: inside 0.36 is the bull.
const RINGS: Array[Dictionary] = [
	{"upto": 0.36, "points": 3, "colour": Color(1.00, 0.84, 0.26)},
	{"upto": 0.76, "points": 2, "colour": Color(0.92, 0.44, 0.24)},
	{"upto": 1.01, "points": 1, "colour": Color(0.86, 0.82, 0.74)},
]

## How far the plank swings on a hit, at full strength, and how it comes back.
## Out fast and back slowly, because that is what being struck looks like; a
## symmetrical tween reads as a machine resetting.
const KNOCK_DEGREES := 18.0
const KNOCK_OUT := 0.10
const KNOCK_BACK := 0.35

const GROUP := "range_targets"
const LAYER_WORLD := 1

var kind: String = "board_small"
## Metres out from the firing line, off the marker's `range_m` meta. Printed in
## the floating text and used for nothing else — the *shot's* distance is
## measured from the shooter, which is not the same number once somebody walks
## down the lane.
var declared_range: float = 0.0

var _hinge: Node3D
var _knock: Tween
var _width: float = 0.9


# ------------------------------------------------------------ construction ---

## Build every target the map's `Targets` marker group declares.
##
## Unit 2 authors the markers and unit 6 calls this; the shapes it reads are
## that file's contract, printed by `range_map._ready` so it cannot rot
## silently: `Target_<kind>_<n>`, meta `kind` / `zone` / `range_m`, facing down
## the marker's own -Z at the people shooting.
static func build_all(map: Node3D, into: Node) -> int:
	var markers := map.get_node_or_null("Targets")
	if markers == null:
		return 0
	var built := 0
	for marker: Node in markers.get_children():
		var spot := marker as Marker3D
		if spot == null:
			continue
		var made := _from_marker(spot, into)
		if made != null:
			built += 1
	return built


static func _from_marker(marker: Marker3D, into: Node) -> Node3D:
	var kind_of := String(marker.get_meta("kind", ""))
	var made: Node3D = null
	match kind_of:
		"board_small", "board_large":
			made = RangeTarget.new()
		"gong":
			made = Gong.new()
		_:
			return null
	made.name = marker.name
	into.add_child(made)
	made.global_transform = marker.global_transform
	if made.has_method("setup_from_meta"):
		made.call("setup_from_meta", kind_of,
			float(marker.get_meta("range_m", 0.0)))
	return made


## Called once, straight after the transform is set. Split out of `_ready` so a
## test can stand a board up without a marker and still choose its kind.
func setup_from_meta(kind_of: String, range_m: float) -> void:
	kind = kind_of
	declared_range = range_m
	_width = float(WIDTH.get(kind_of, WIDTH["board_small"]))
	_build()


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = LAYER_WORLD
	# Blocks nothing itself. It is a thing that gets hit, not a thing that
	# pushes — the same argument `Shield.MASK_NONE` makes.
	collision_mask = 0
	if _hinge == null:
		_build()


## How wide a thing this is, for the sword's reach test. The board's own radius
## rather than a bounding sphere: a swing that clipped the edge of a 1.4 m plank
## counts, and a swing 1.4 m past it does not.
func hit_radius() -> float:
	return _width * 0.5


func _build() -> void:
	if _hinge != null:
		return
	_width = float(WIDTH.get(kind, WIDTH["board_small"]))

	var stake := MeshInstance3D.new()
	stake.name = "Stake"
	var post := CylinderMesh.new()
	post.top_radius = 0.055
	post.bottom_radius = 0.07
	post.height = CENTRE_HEIGHT
	post.radial_segments = 8
	stake.mesh = post
	stake.material_override = _timber()
	stake.position = Vector3(0.0, CENTRE_HEIGHT * 0.5, 0.0)
	add_child(stake)

	# The plank hangs off a hinge at the top of the stake, so the knock is a
	# rotation about a real pivot rather than the whole target sliding. The
	# collision rides the hinge with it: a board that has just been knocked back
	# is genuinely further away for the next shot, which is the point of it
	# moving at all.
	_hinge = Node3D.new()
	_hinge.name = "Hinge"
	_hinge.position = Vector3(0.0, CENTRE_HEIGHT, 0.0)
	add_child(_hinge)

	var face := MeshInstance3D.new()
	face.name = "Face"
	var disc := CylinderMesh.new()
	disc.top_radius = _width * 0.5
	disc.bottom_radius = _width * 0.5
	disc.height = THICKNESS
	disc.radial_segments = 24
	face.mesh = disc
	face.material_override = _timber()
	# The cylinder's axis is Y; the board faces the shooter, which is the
	# marker's own -Z. Turning it about X lays the disc into the XY plane.
	face.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_hinge.add_child(face)

	# Rings, front face only, each a hair proud of the last so they do not
	# z-fight. Emissive and unshaded: this is a bog at night and a target nobody
	# can see is not a target.
	var proud := THICKNESS * 0.5 + 0.004
	for i: int in RINGS.size():
		var ring: Dictionary = RINGS[RINGS.size() - 1 - i]
		var mesh := CylinderMesh.new()
		var radius: float = _width * 0.5 * minf(float(ring["upto"]), 1.0)
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = 0.004
		mesh.radial_segments = 24
		var paint := MeshInstance3D.new()
		paint.name = "Ring%d" % int(ring["points"])
		paint.mesh = mesh
		paint.material_override = _ring_material(ring["colour"])
		paint.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		paint.position = Vector3(0.0, 0.0, -(proud + 0.004 * i))
		paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hinge.add_child(paint)

	# **A direct child of the body, not of the hinge.** Godot only registers a
	# `CollisionShape3D` that is an immediate child of its `CollisionObject3D`;
	# one nested under an intermediate `Node3D` is silently ignored and the body
	# has no collision at all — which is a target nothing can hit and nothing
	# reports, because a projectile's sweep simply never returns it.
	#
	# So the knock is **cosmetic**: the plank swings and the hitbox does not.
	# That is the better answer anyway. A board that physically retreated would
	# put the next shot at a different range than the post beside it claims, and
	# a practice range whose distances move is a practice range that lies.
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(_width, _width, THICKNESS)
	shape.shape = box
	shape.position = Vector3(0.0, CENTRE_HEIGHT, 0.0)
	add_child(shape)


func _timber() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.24, 0.16)
	material.roughness = 0.92
	return material


func _ring_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 0.6
	material.roughness = 0.85
	return material


# -------------------------------------------------------------- being hit ---

## A spear, an arrow or a sword landed on this board.
##
## Runs on **every** peer for a projectile (each machine's own copy of the shaft
## got here on its own), and on every peer for a sword because
## `range_hit_broadcast` sent it. Only the host scores.
func range_hit(point: Vector3, by_peer: int, cause: int) -> void:
	var ring := ring_at(point)
	var points: int = ring["points"]
	var strength := clampf(float(points) / 3.0, 0.5, 1.0)
	_swing(KNOCK_DEGREES * strength)
	AudioDirector.play_3d_varied(AudioDirector.RANGE_BOARD, point)
	_announce(point, by_peer, "+%d" % points, ring["colour"])
	if Net.is_host and RangeStats.instance != null:
		RangeStats.instance.record_target_hit(by_peer, cause, points,
			RangeStats.shot_distance(by_peer, point))


## Host only, and only the sword uses it: broadcast the hit, then take it here.
##
## The ordering is every other host-decided reaction's in this codebase — send
## first, act second — so that on every peer the board moves with the swing
## rather than after it.
func range_hit_broadcast(point: Vector3, by_peer: int, cause: int) -> void:
	if not Net.is_host:
		return
	_do_range_hit.rpc(point, by_peer, cause)
	_do_range_hit(point, by_peer, cause)


@rpc("authority", "call_remote", "reliable")
func _do_range_hit(point: Vector3, by_peer: int, cause: int) -> void:
	range_hit(point, by_peer, cause)


## Which ring a world point landed in.
##
## Measured against the **hitbox**, which is the thing the shaft actually went
## through, and which does not move — see the collision note in `_build`. Taking
## it off the swinging plank would mean a board mid-knock scored a shot by where
## it had been thrown to rather than by where it was aimed.
func ring_at(point: Vector3) -> Dictionary:
	var local := to_local(point)
	var radius := maxf(_width * 0.5, 0.0001)
	var from_centre := Vector2(local.x, local.y - CENTRE_HEIGHT).length() / radius
	for ring: Dictionary in RINGS:
		if from_centre <= float(ring["upto"]):
			return ring
	return RINGS[RINGS.size() - 1]


## Knock the plank back and let it come home. One tween, killed and restarted
## per hit, so a burst of arrows does not stack into a spin.
func _swing(degrees: float) -> void:
	if _hinge == null:
		return
	if _knock != null and _knock.is_valid():
		_knock.kill()
	_knock = create_tween()
	_knock.tween_property(_hinge, "rotation_degrees:x", -degrees, KNOCK_OUT) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_knock.tween_property(_hinge, "rotation_degrees:x", 0.0, KNOCK_BACK) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The floating text, and the marker flash, for the one player who did it.
##
## `by_peer` and not "everybody", because this is feedback about *your* shot.
## Eight people practising on one lane would otherwise each see eight numbers.
func _announce(point: Vector3, by_peer: int, body: String, tint: Color) -> void:
	if by_peer != Net.local_id():
		return
	var shot := RangeStats.shot_distance(by_peer, point)
	var sub := "" if shot < 0.0 else "%.0f m" % shot
	HitNumber.pop(_text_root(), point, body, tint, sub)
	# Nothing else plays a hitmarker for a non-Bog target — `MatchState` only
	# speaks for hits on Bogs — so unlike `hit_landed` this one is ours to fire.
	AudioDirector.play_2d(AudioDirector.HITMARKER)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("flash_hit"):
		hud.call("flash_hit", UIPalette.AMBER)


func _text_root() -> Node:
	var root := get_tree().get_first_node_in_group("spawned_items")
	return root if root != null else self
