extends Node3D
## The practice range's targets and its stats counter, proven headless.
##
##   Godot --headless --path . tools/range_targets.tscn
##
## Like `tools/combat_range.gd` this runs the **real** paths: an offline session
## on `Net`, real `SpearProjectile`s and `ArrowProjectile`s swept through a real
## physics space into real `RangeTarget`s, and a real `RangeStats` counting off
## the same signals it counts off in a match. Nothing here reaches past a public
## API, so a board that scores here scores in the range.
##
## Five verdicts, and the fourth is the reason the first three mean anything: a
## counter that never saw a miss would pass an accuracy check by accident.

const SPEAR := preload("res://scripts/items/spear_projectile.gd")

## Where the shooting happens. A flat floor and nothing else: this file is about
## the targets, and unit 2's map is proven by its own report.
const FLOOR := Vector2(90.0, 90.0)

## The gong's distance, which is the spear's measured flat band and the whole
## reason the thing is standing there. Asserted rather than assumed, because if
## this number and `range_map.GONG_RANGE` ever part company the target stops
## teaching what it is for.
const GONG_AT := 28.0

## Comfortably past `KNOCK_OUT + KNOCK_BACK`, so a board is back at rest before
## the next shot and each hit is measured on its own swing.
const KNOCK_SETTLE := 0.7

## Where a Bog's hand is when it throws. Only the gong check needs it, and it
## needs it to be a real number rather than zero: a spear launched from the
## floor is a spear that ploughs into the floor.
const THROW_HEIGHT := 1.6

var _items: Node3D
var _stats: RangeStats
## A real Bog, because a spear needs a thrower: `begin` reads `peer_id` off it
## and the sweep excludes its RID. Registered in `MatchState.bogs` as well, so
## `RangeStats.shot_distance` can find it and the distance readouts are measured
## rather than invented.
var _thrower: Bog
var _failures: PackedStringArray = []
var _checks: int = 0


func _ready() -> void:
	_build_world()
	Net.start_offline()
	Net.config.map = "range"
	MatchState.register_arena(self, [Transform3D.IDENTITY])
	await get_tree().physics_frame

	_stats = RangeStats.new()
	_stats.name = "Stats"
	add_child(_stats)

	_thrower = MatchState.BOG_SCENE.instantiate() as Bog
	_thrower.name = "Thrower"
	_thrower.peer_id = 1
	_thrower.reads_local_input = false
	add_child(_thrower)
	_thrower.global_position = Vector3.ZERO
	MatchState.bogs[1] = _thrower
	await get_tree().physics_frame
	await get_tree().physics_frame

	await _run_board()
	await _run_gong()
	await _run_orb()
	_run_stats()
	_run_reset()

	_report()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _build_world() -> void:
	_items = Node3D.new()
	_items.name = "Items"
	_items.add_to_group("spawned_items")
	add_child(_items)

	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(FLOOR.x, 1.0, FLOOR.y)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	add_child(floor_body)


# ------------------------------------------------------------------ board ---

## Three shots at one board, aimed at each ring by radius, and the plank has to
## move for every one of them.
func _run_board() -> void:
	var board := _stand(RangeTarget.new(), "board_large",
		Vector3(0.0, 0.0, -20.0), 30.0)
	await get_tree().physics_frame

	var scored: Array[int] = []
	var knocked := 0
	var width: float = RangeTarget.WIDTH["board_large"]
	# The centre of each ring band, as a fraction of the radius: inside the
	# bull, between the two lines, and outside the second.
	for fraction: float in [0.0, 0.55, 0.9]:
		var at := board.global_position \
			+ Vector3(fraction * width * 0.5, RangeTarget.CENTRE_HEIGHT, 0.0)
		var ring := board.ring_at(at)
		scored.append(int(ring["points"]))
		board.range_hit(at, 1, Bog.Cause.SPEAR)
		# Three frames, not one. A `Tween` made this frame does not step until
		# the next idle frame and the one after that is the first with a real
		# delta in it, so sampling immediately reads the pose it started from.
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		if absf(board.get_node("Hinge").rotation_degrees.x) > 0.0001:
			knocked += 1
		# Long enough for the knock and the return to finish, so the next hit
		# starts from rest and measures its own swing.
		await get_tree().create_timer(KNOCK_SETTLE).timeout

	_expect(scored == [3, 2, 1],
		"board rings scored %s, wanted [3, 2, 1]" % str(scored))
	_expect(knocked == 3, "the plank moved on %d of 3 hits" % knocked)
	if scored == [3, 2, 1] and knocked == 3:
		print("range_targets: board scored 3, 2, 1 by ring")
	board.queue_free()


# ------------------------------------------------------------------- gong ---

## A real spear, thrown flat, into a real gong 28 m away. The one check here
## that goes through the projectile's own sweep rather than calling `range_hit`
## by hand — which is the half that proves the hook in `_resolve` is reached.
func _run_gong() -> void:
	var gong := _stand(Gong.new(), "gong", Vector3(0.0, 0.0, -GONG_AT), GONG_AT)
	await get_tree().physics_frame

	var rang := false
	var struck_at := 0.0
	# Thrown from a Bog's own throwing height at the gong's centre, with the
	# elevation worked out from the projectile's **own** constants rather than
	# typed in — so if anybody ever retunes the spear this check re-aims itself
	# instead of quietly starting to miss.
	#
	# 28 m is flat for a *fight* (the spear drops 1.78 m over it, which is inside
	# a body) and is not flat for a 1.6 m disc, which is the whole reason the
	# aim has to be computed.
	var origin := Vector3(0.0, THROW_HEIGHT, 0.0)
	# `HANG_HEIGHT` is the disc's *centre*: the hinge sits at the beam, a radius
	# higher, and the disc hangs back down to it. Aiming a radius lower than
	# this is aiming at the bottom rim, which is a miss by half a metre.
	var target := gong.global_position + Vector3(0.0, Gong.HANG_HEIGHT, 0.0)
	var spear: SpearProjectile = SPEAR.launch(_items, _thrower, origin,
		_aim_at(origin, target), true)

	for tick: int in 180:
		await get_tree().physics_frame
		if not is_instance_valid(spear):
			break
		if spear.is_stuck():
			rang = true
			struck_at = origin.distance_to(spear.global_position)
			break

	_expect(rang, "the spear never reached the gong")
	_expect(absf(struck_at - GONG_AT) < 1.2,
		"the spear stuck %.2f m out, wanted about %.1f" % [struck_at, GONG_AT])
	if rang and absf(struck_at - GONG_AT) < 1.2:
		print("range_targets: the gong rang at %.1f m" % GONG_AT)
	if is_instance_valid(spear):
		spear.queue_free()
	gong.queue_free()


# -------------------------------------------------------------------- orb ---

## An orb burst, and the thing that makes it different from a board: it frees
## itself, and the shaft has to go with it rather than hang in mid-air.
func _run_orb() -> void:
	var orb := GlowOrb.launch(_items, Transform3D(Basis(), Vector3(0.0, 3.0, 0.0)),
		1234, 60.0)
	await get_tree().physics_frame
	var before := _items.get_child_count()

	orb.range_hit(orb.global_position, 1, Bog.Cause.ARROW)
	_expect(orb.is_queued_for_deletion(),
		"the orb survived being hit and should not have")
	await get_tree().process_frame
	await get_tree().process_frame

	var alive := false
	for child: Node in _items.get_children():
		if child is GlowOrb and not child.is_queued_for_deletion():
			alive = true
	_expect(not alive, "an orb was still standing after it burst")
	_expect(_items.get_child_count() >= before,
		"the burst left nothing behind at all")
	if not alive:
		print("range_targets: an orb burst and left nothing behind")


# ------------------------------------------------------------------ stats ---

## A throw, a hit and a kill, then a throw that hits nothing.
##
## The miss is the point. A counter that only ever sees hits reports 100%
## whatever it does, so the check that matters is the one where the number has
## to come *down* — and the miss is seen the way the range sees it, on the next
## launch, which is the one lag this design has and does not hide.
func _run_stats() -> void:
	_stats.reset()
	_stats.record_launch(1, "spear")
	_stats.record_hit(1, "spear", 18.0)
	_stats.record_kill(1, "spear")

	var row := _stats.row(1, "spear")
	var accurate := is_equal_approx(RangeStats.accuracy(row), 1.0)
	_expect(int(row["launches"]) == 1, "launches read %d, wanted 1" % int(row["launches"]))
	_expect(int(row["hits"]) == 1, "hits read %d, wanted 1" % int(row["hits"]))
	_expect(int(row["kills"]) == 1, "kills read %d, wanted 1" % int(row["kills"]))
	_expect(accurate, "accuracy read %.2f, wanted 1.00" % RangeStats.accuracy(row))
	_expect(is_equal_approx(float(row["longest"]), 18.0),
		"longest read %.1f, wanted 18.0" % float(row["longest"]))
	_expect(int(row["streak"]) == 1, "streak read %d, wanted 1" % int(row["streak"]))
	if int(row["launches"]) == 1 and int(row["hits"]) == 1 \
			and int(row["kills"]) == 1 and accurate:
		print("range_targets: 1 throw, 1 hit, 1 kill, accuracy 100%")

	# The miss: a second throw that lands on nothing, then a third, which is
	# when the streak is allowed to notice.
	_stats.record_launch(1, "spear")
	_stats.record_launch(1, "spear")
	row = _stats.row(1, "spear")
	var half := RangeStats.accuracy(row)
	_expect(absf(half - (1.0 / 3.0)) < 0.001,
		"accuracy after two misses read %.3f, wanted 0.333" % half)
	_expect(int(row["streak"]) == 0,
		"the streak survived a miss and read %d" % int(row["streak"]))
	# A hit on a board counts into the same weapon row as a hit on a Bog.
	_stats.record_target_hit(1, Bog.Cause.SPEAR, 3, 24.0)
	row = _stats.row(1, "spear")
	_expect(int(row["points"]) == 3, "board points read %d, wanted 3" % int(row["points"]))
	_expect(is_equal_approx(float(row["longest"]), 24.0),
		"longest did not follow the board hit: %.1f" % float(row["longest"]))
	if int(row["points"]) == 3:
		print("range_targets: a board hit files under the weapon that threw it")


func _run_reset() -> void:
	_stats.reset()
	var row := _stats.row(1, "spear")
	var zeroed := int(row["launches"]) == 0 and int(row["hits"]) == 0 \
		and int(row["kills"]) == 0 and int(row["streak"]) == 0 \
		and is_equal_approx(float(row["longest"]), 0.0)
	_expect(zeroed, "reset left something behind: %s" % str(row))
	_expect(_stats.rows.is_empty(), "reset left %d row(s)" % _stats.rows.size())
	if zeroed and _stats.rows.is_empty():
		print("range_targets: reset zeroed every row")


# ------------------------------------------------------------------ plumbing ---

## The direction to throw in to put a spear through `target` from `origin`.
##
## Worked out from `SpearProjectile`'s own `SPEED` and `DROP`, so this file
## never carries a copy of the ballistics it is testing: time of flight from the
## horizontal distance, then the vertical speed that lands the shaft on the mark
## after it has fallen for that long.
func _aim_at(origin: Vector3, target: Vector3) -> Vector3:
	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	var span := flat.length()
	if span < 0.01:
		return Vector3.FORWARD
	var flight := span / SpearProjectile.SPEED
	var climb := ((target.y - origin.y)
		+ 0.5 * SpearProjectile.DROP * flight * flight) / flight
	return (flat.normalized() * SpearProjectile.SPEED
		+ Vector3.UP * climb).normalized()


func _stand(target: RangeTarget, kind: String, at: Vector3,
		range_m: float) -> RangeTarget:
	target.name = "Target_%s" % kind
	add_child(target)
	target.global_position = at
	target.setup_from_meta(kind, range_m)
	return target


func _expect(ok: bool, failure: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(failure)


## The count and then the bare verdict, on two lines, because that is what every
## other headless tool in this folder prints and what the gate greps for: an
## `expect` of `range_targets: PASS` cannot match a line that also carries a
## check count, and a gate row that had to quote the count would go red the day
## somebody adds a check.
func _report() -> void:
	print("range_targets: %d checks, %d failures" % [_checks, _failures.size()])
	for line: String in _failures:
		print("  " + line)
	print("range_targets: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
