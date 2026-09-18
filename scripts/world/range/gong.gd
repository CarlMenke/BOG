class_name Gong
extends RangeTarget
## The bronze disc at 28 m on the middle lane.
##
## **28 m is not decoration.** It is the spear's measured flat band — the range
## at which a thrown spear is still travelling flat enough to aim straight at
## what you want to hit — so the gong is the one target on the range that
## teaches a number rather than a skill. Hit it without arcing and you have
## found the edge of the spear's honest range.
##
## It scores, but it does not *say* it scores: the floating text is the distance
## of the shot, large, and there is no "+2" on it. The points go in the stats
## row like anything else. A range readout that also shouts a score reads as a
## scoreboard, and what this is for is the number.

## Metres across. Big enough to be a fair target at 28 m and small enough that
## hitting it is worth something.
const DIAMETER := 1.6
const RIM := 0.09
## Its centre, above the marker. A little higher than a board: a gong hangs.
const HANG_HEIGHT := 1.80

const POINTS := 2

## A gong swings further and settles slower than a plank on a stake. It is
## hanging, not pinned.
const GONG_KNOCK := 26.0
const GONG_BACK := 0.60

## Pitch and loudness by **distance**, not by impact speed.
##
## Impact speed is the physically obvious input and `range_hit` does not carry
## it; widening the contract for one target's audio would put a parameter on
## every target for ever. So the gong is voiced by the thing it exists to teach.
## `RANGE_GONG` is written to stay clean over about a fifth either way, which is
## what this span asks of it.
const PITCH_NEAR := 0.86
const PITCH_SPAN := 0.28
const PITCH_FULL_AT := 40.0
const DB_NEAR := -6.0
const DB_SPAN := 5.0

var _disc: MeshInstance3D


func setup_from_meta(kind_of: String, range_m: float) -> void:
	kind = kind_of
	declared_range = range_m
	_build_gong()


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = LAYER_WORLD
	collision_mask = 0
	if _disc == null:
		_build_gong()


func hit_radius() -> float:
	return DIAMETER * 0.5


func _build_gong() -> void:
	if _disc != null:
		return

	# Two uprights and a cross beam, so the disc reads as hung rather than as
	# floating at chest height.
	for side: float in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		leg.name = "Leg%d" % int(side)
		var post := CylinderMesh.new()
		post.top_radius = 0.06
		post.bottom_radius = 0.08
		post.height = HANG_HEIGHT + DIAMETER * 0.5
		post.radial_segments = 8
		leg.mesh = post
		leg.material_override = _timber()
		leg.position = Vector3(side * (DIAMETER * 0.5 + 0.22),
			(HANG_HEIGHT + DIAMETER * 0.5) * 0.5, 0.0)
		add_child(leg)

	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var bar := BoxMesh.new()
	bar.size = Vector3(DIAMETER + 0.72, 0.11, 0.11)
	beam.mesh = bar
	beam.material_override = _timber()
	beam.position = Vector3(0.0, HANG_HEIGHT + DIAMETER * 0.5, 0.0)
	add_child(beam)

	_hinge = Node3D.new()
	_hinge.name = "Hinge"
	# Pivots at the beam, so the disc swings from where it is actually hung.
	_hinge.position = Vector3(0.0, HANG_HEIGHT + DIAMETER * 0.5, 0.0)
	add_child(_hinge)

	_disc = MeshInstance3D.new()
	_disc.name = "Disc"
	var plate := CylinderMesh.new()
	plate.top_radius = DIAMETER * 0.5
	plate.bottom_radius = DIAMETER * 0.5
	plate.height = RIM
	plate.radial_segments = 32
	_disc.mesh = plate
	_disc.material_override = _bronze()
	_disc.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_disc.position = Vector3(0.0, -DIAMETER * 0.5, 0.0)
	_hinge.add_child(_disc)

	# A raised boss in the middle, which is where a gong is meant to be struck
	# and the only part of one that is not flat.
	var boss := MeshInstance3D.new()
	boss.name = "Boss"
	var dome := SphereMesh.new()
	dome.radius = DIAMETER * 0.17
	dome.height = DIAMETER * 0.17
	dome.radial_segments = 16
	dome.rings = 6
	boss.mesh = dome
	boss.material_override = _bronze()
	boss.position = Vector3(0.0, -DIAMETER * 0.5, -RIM * 0.5)
	_hinge.add_child(boss)

	# Direct child of the body, for the reason `RangeTarget._build` gives at
	# length: a shape under the hinge is a shape Godot never registers, and the
	# gong would be a disc nothing could hit. `HANG_HEIGHT` is the disc's centre
	# — the hinge sits a radius above it, at the beam.
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(DIAMETER, DIAMETER, RIM)
	shape.shape = box
	shape.position = Vector3(0.0, HANG_HEIGHT, 0.0)
	add_child(shape)


func _bronze() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.68, 0.50, 0.20)
	material.metallic = 0.85
	material.roughness = 0.35
	material.emission_enabled = true
	material.emission = Color(0.50, 0.34, 0.12)
	material.emission_energy_multiplier = 0.35
	return material


func range_hit(point: Vector3, by_peer: int, cause: int) -> void:
	var shot := RangeStats.shot_distance(by_peer, point)
	# The declared range is the fallback, and it is the honest one: if the
	# shooter's Bog cannot be found, the distance the *gong* stands at is still
	# a true fact about this hit, where a zero would not be.
	var voiced := shot if shot >= 0.0 else declared_range
	var t := clampf(voiced / PITCH_FULL_AT, 0.0, 1.0)

	_swing(GONG_KNOCK)
	AudioDirector.play_3d(AudioDirector.RANGE_GONG, point,
		PITCH_NEAR + PITCH_SPAN * t, DB_NEAR + DB_SPAN * t)

	if by_peer == Net.local_id():
		# The distance, large, and no score. See the header.
		HitNumber.pop(_text_root(), point, "%.0f m" % voiced, UIPalette.AMBER)
		AudioDirector.play_2d(AudioDirector.HITMARKER)
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("flash_hit"):
			hud.call("flash_hit", UIPalette.AMBER)

	if Net.is_host and RangeStats.instance != null:
		RangeStats.instance.record_target_hit(by_peer, cause, POINTS, shot)


## A gong swings from a beam, so it comes home slower than a plank does.
func _swing(degrees: float) -> void:
	if _hinge == null:
		return
	if _knock != null and _knock.is_valid():
		_knock.kill()
	_knock = create_tween()
	_knock.tween_property(_hinge, "rotation_degrees:x", -degrees, KNOCK_OUT) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_knock.tween_property(_hinge, "rotation_degrees:x", 0.0, GONG_BACK) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
