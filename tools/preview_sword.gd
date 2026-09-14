extends Node3D
## The great sword in the hands, across the swing. Development tool, not shipped.
##
## Two jobs, and they are the same job read twice: the numbers that put both
## fists on the hilt, and the picture that shows what the swing actually is.
##
##   # the derivation, headless, printed — paste the three lines it ends with
##   Godot --headless --path . --script tools/snapshot.gd -- \
##       res://tools/preview_sword.tscn out/none.png 4 measure
##
##   # the sheet: seven Gubs across the swing, each set back by the distance the
##   # advance has carried it, with a compass under every one
##   Godot --path . --resolution 2400x1100 --script tools/snapshot.gd -- \
##       res://tools/preview_sword.tscn out/sword_swing.png 25
##
## **Why this exists rather than `tools/preview_bow.tscn` with a sword in it.**
## The same reason that one exists rather than `preview_grip`: there is an
## equation here and it has one answer. A spear in a fist only has to miss the
## Gub's own skin; a bow's string has to meet the drawing fingers; a great sword
## is **two-handed**, and the hilt has to reach from the fist that holds it to
## the fist that joins it, through a clip that is throwing both of them about. So
## the fit is solved rather than nudged.
##
## **Why the sheet is here and not `preview_anim.tscn`.** That tool stands one
## Gub per sampled moment in an evenly spaced row, which is exactly wrong for
## this clip: the two things worth looking at are the **rotation** (350° of it)
## and the **advance** (1.712 m of it), and an evenly spaced row hides the second
## and gives no reference for the first. Here the row carries the advance on one
## axis and a compass ring under every body carries the rotation, so the sheet is
## the swing's ground track rather than a flip-book of poses (D-068).

const GUB := preload("res://scenes/player/gub.tscn")

## How many samples the derivation is checked at across the window. Seventeen is
## every sixteenth of the swing, fine enough to catch a wrist that rotates
## through the spin — the one way the fists could leave the straight line the fit
## assumes.
const CHECKS := 17

## How far apart the solved hilt is allowed to be from the fists it is fitted to,
## in metres, before `measure` calls it a failure.
##
## The bow's equivalent is exact because a string is a straight line between two
## points that only move along it. Two fists on a hilt are not: measured, they
## are **0.096 m apart where the rear hand chokes up and 0.231 m at full
## extension**, a spread of 0.135 m, so no rigid hilt can sit in both of them at
## once and the only question worth asking is whether the pommel stays *in* the
## rear fist. This is therefore the size of the mitten rather than a residual to
## drive to zero: the `RightHand`-weighted skin spans 0.17 m across (see
## `HeldGear.GRIP_OFFSET`), and the worst sample comes out at 0.150 m.
const FIT_TOLERANCE := 0.16

## How far below the floor the point of the blade may reach through the swing.
##
## The spear's own grip was tuned to "both ends stay at least 0.15 m up" and the
## carried bow was held to the same (D-066), and neither of those numbers can be
## asked of this prop: a sword is *swung*, and `Swing` brings the blade down and
## round through an arc whose whole point is that it passes through the space a
## body stands in. A grip that kept the point above the grass would be a grip
## that had lifted the sword out of its own swing.
##
## So this is built the way `PACKS`'s own `floor_limit` is — "just under what its
## source authors, which is what makes it a check rather than a wish". The point
## reaches **-0.437 m at 1.226 s**, a sixth of a second after the cut, as the
## follow-through carries a 1.047 m blade past the knee of a 1.80 m body. Half a
## metre is under that and nowhere near a grip that has come loose.
const BLADE_CLEARANCE_MIN := -0.50

@export var samples: int = 7

## How far apart the sheet stands its Gubs across the frame, in metres. Layout
## only — the *other* axis is the one that carries the advance, and this one
## simply has to be wider than a Gub with a 1.26 m sword going round it.
const SHEET_SPREAD := 1.9

## The frame, in metres. A 1.26 m sword swung overhead by a 1.80 m Gub needs a
## taller box than the bow's.
const FRAME_LOW := -0.2
const FRAME_HIGH := 3.4
const FRAME_MIN := 3.6
const FRAME_MARGIN := 2.4

## How high the camera stands, in degrees. Dead front horizontally, because the
## spread axis has to lie flat across the frame — and lifted, because the *other*
## axis is the advance and at zero elevation a distance into the screen is a
## distance nobody can see. `tools/preview_clips.py` lifts its own camera to 24°
## the moment it draws a floor compass and says why; this is the same argument
## about the same picture, with a ground track in it as well.
const VIEW_ELEVATION := 34.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[3] if args.size() > 3 else "sheet"
	if args.size() > 4:
		samples = maxi(2, int(args[4]))
	if mode == "measure":
		_measure()
		get_tree().quit()
		return
	_sheet()


# ------------------------------------------------------------- the numbers ---

## Solve the grip, print it, and say how far off it is at every sample.
func _measure() -> void:
	var gub := _bare_gub()
	var skeleton := gub.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := gub.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var right := skeleton.find_bone(HeldGear.HAND_BONE)
	var left := skeleton.find_bone(HeldGear.BOW_HAND_BONE)
	if right < 0 or left < 0:
		print("preview_sword: rig has no %s / %s"
			% [HeldGear.HAND_BONE, HeldGear.BOW_HAND_BONE])
		return

	# The joining hand, in the gripping hand's own frame, at every sample. The
	# sword is rigid in the right fist, so this is the only space in which "where
	# does the hilt have to reach" has a fixed answer.
	var joined: Array[Vector3] = []
	var apart: Array[float] = []
	for i in CHECKS:
		_pose(player, skeleton, _sample_time(i, CHECKS))
		var r := skeleton.get_bone_global_pose(right)
		var l := skeleton.get_bone_global_pose(left)
		joined.append(r.affine_inverse() * l.origin)
		apart.append(r.origin.distance_to(l.origin))

	var mean := Vector3.ZERO
	for p: Vector3 in joined:
		mean += p
	mean /= float(CHECKS)
	var hilt := mean.normalized()
	var span := HeldGear.SWORD_REAR_HAND - HeldGear.SWORD_FORE_HAND
	var model_scale := mean.length() / span

	# The roll. Every rotation about the hilt puts both fists in the same place,
	# so the fists cannot decide which way the edge points — the hand does. The
	# blade's flat is the model's X, and it is squared up against the hilt from
	# "across the palm", which is `RightHand`'s own local X (see `GRIP_OFFSET`'s
	# note on this rig's axes): a sword's edge is square to the knuckles.
	var across := Vector3.RIGHT
	var x := (across - hilt * across.dot(hilt)).normalized()
	var basis := Basis(x, hilt, x.cross(hilt))
	var palm := HeldGear.fist_offset()
	var offset := palm - hilt * (model_scale * HeldGear.SWORD_FORE_HAND)

	print("preview_sword: the great sword")
	print("  the two fists are %.3f..%.3f m apart across the swing (mean %.3f)"
		% [_lowest(apart), _highest(apart), mean.length()])
	print("  the model's hilt spans %.3f from fore hand to rear, so it is %.3f x "
		% [span, model_scale] + "its authored size")
	print("  which is a sword %.3f m point to pommel, %.3f m of it blade"
		% [HeldGear.SWORD_LENGTH * model_scale, HeldGear.SWORD_GUARD * model_scale])
	print("  worst miss over %d samples of the window:" % CHECKS)
	var worst := 0.0
	for i in CHECKS:
		var rear: Vector3 = offset + basis \
			* (Vector3(0.0, HeldGear.SWORD_REAR_HAND, 0.0) * model_scale)
		var miss := rear.distance_to(joined[i])
		worst = maxf(worst, miss)
		print("    %.3f s   pommel at %v   joining fist at %v   %.4f m apart"
			% [_sample_time(i, CHECKS), rear, joined[i], miss])
	print("  worst %.4f m against a %.2f m tolerance — fit %s"
		% [worst, FIT_TOLERANCE, "PASS" if worst <= FIT_TOLERANCE else "FAIL"])
	print("    const SWORD_SCALE := %.4f" % model_scale)
	print("    const SWORD_GRIP_OFFSET := Vector3(%.4f, %.4f, %.4f)"
		% [offset.x, offset.y, offset.z])
	var euler := basis.get_euler() * (180.0 / PI)
	print("    const SWORD_GRIP_ROTATION := Vector3(%.3f, %.3f, %.3f)"
		% [euler.x, euler.y, euler.z])

	_report_blade(gub, skeleton, player,
		Transform3D(basis.scaled(Vector3.ONE * model_scale), offset), model_scale)


## Where the blade actually goes, with the grip that was just solved (D-068).
##
## Two things, and the second is the one the reach is built on. How low the point
## gets, which is the sword's version of the carried bow's limb-tip table; and
## **how far from the Gub the point reaches at the release**, which is the
## measurement `MatchConfig.sword_reach` has to agree with. The second is printed
## here and asserted in the game by `tools/combat_range.tscn -- sword`, so the
## dial and the animation are checked against each other from both ends.
##
## The transform is composed by hand rather than read off
## `HeldGear.sword_blade()`, which is what the *game* reads (D-066: a
## `BoneAttachment3D` is the only thing that sees the modifier stack). There is
## no modifier stack in a bare Gub and no physics frame for an attachment to
## update in, so a reading taken through one here is the first frame's pose
## seventeen times over — it was, before this line.
func _report_blade(gub: Gub, skeleton: Skeleton3D, player: AnimationPlayer,
		grip: Transform3D, model_scale: float) -> void:
	var hand := skeleton.find_bone(HeldGear.HAND_BONE)
	var lowest := INF
	var lowest_at := 0.0
	var release := 0.0
	var furthest := 0.0
	var furthest_at := 0.0
	# Four times the fit's sample count, because this is looking for two extremes
	# rather than fitting a line through the middle, and an extreme found on a
	# coarse grid is an extreme underestimated.
	for i in CHECKS * 4:
		var time := _sample_time(i, CHECKS * 4)
		_pose(player, skeleton, time)
		var at := gub.global_transform * skeleton.global_transform \
			* skeleton.get_bone_global_pose(hand) * grip
		var point := at.origin
		if point.y < lowest:
			lowest = point.y
			lowest_at = time
		# The reach is horizontal, because the sweep is: a Gub is caught by where
		# the blade is *on the ground plane*, not by how high it is.
		var flat := Vector3(point.x - gub.global_position.x, 0.0,
			point.z - gub.global_position.z).length()
		if flat > furthest:
			furthest = flat
			furthest_at = time
		if absf(time - GubAnimator.SWING_RELEASE_IN_CLIP) < 0.015:
			release = flat
	print("preview_sword: the blade (%.3f m of it, at x%.3f)"
		% [HeldGear.SWORD_GUARD * model_scale, model_scale])
	print("  lowest point %+.3f m at %.3f s" % [lowest, lowest_at])
	print("  furthest out %.3f m at %.3f s" % [furthest, furthest_at])
	print("  at the release (%.3f s) the point is %.3f m from the Gub's own axis"
		% [GubAnimator.SWING_RELEASE_IN_CLIP, release])
	print("  plus %.3f m of advance = %.3f m of ground a swing threatens"
		% [Gub.SPIN_ADVANCE, release + Gub.SPIN_ADVANCE])
	if lowest >= BLADE_CLEARANCE_MIN:
		print("preview_sword: the point dips to %+.3f m against a %+.3f m limit "
			% [lowest, BLADE_CLEARANCE_MIN] + "— blade PASS")
	else:
		print("preview_sword: blade FAIL — the point reaches %+.3f m, past the "
			% lowest + "%+.3f m limit" % BLADE_CLEARANCE_MIN)


func _lowest(values: Array[float]) -> float:
	var out := INF
	for v: float in values:
		out = minf(out, v)
	return out


func _highest(values: Array[float]) -> float:
	var out := -INF
	for v: float in values:
		out = maxf(out, v)
	return out


## The clip second of sample `i` of `count`, across the window `GubAnimator`
## plays — asked of the animator's own constants, so a window that moves moves
## this tool with it.
func _sample_time(i: int, count: int) -> float:
	return lerpf(GubAnimator.SWING_CLIP_START, GubAnimator.SWING_CLIP_END,
		float(i) / float(maxi(count - 1, 1)))


## Put the skeleton in the pose the game would hold at this moment of the swing.
##
## `seek` and then a forced pose update, because an `AnimationPlayer` only writes
## into the skeleton when it is processed and this reads it back in the same
## call.
func _pose(player: AnimationPlayer, skeleton: Skeleton3D, time: float) -> void:
	player.play("Swing")
	player.seek(time, true, true)
	player.pause()
	skeleton.force_update_all_bone_transforms()


# ------------------------------------------------------------- the picture ---

## The swing as a ground track (D-068).
##
## One Gub per sampled moment, laid out on **two axes that mean two different
## things**, which is the whole design of this sheet. Across the frame the Gubs
## are simply spread out, `SHEET_SPREAD` apart, so that seven bodies can be
## looked at without standing in each other — that axis is a contact sheet's and
## carries no meaning. *Into* the frame each one is set back by the distance the
## advance has actually carried it by that moment — `Gub.SPIN_ADVANCE` times the
## fraction of the window elapsed, which is exactly what `Gub._handle_movement`
## produces — so the row climbs the screen as a staircase whose rise is the real
## 1.712 m, measurable against the chalk it is standing on.
##
## The first attempt put the Gubs at their true positions on *both* axes and was
## unreadable: 1.712 m over seven bodies is a quarter of a metre a step, which is
## seven Gubs in a heap. That the advance is small compared to a Gub is the fact
## which made that picture worthless and is also why the advance is worth having
## at all, so this sheet separates the two questions instead of asking one axis
## to answer both.
##
## Under every body a compass ring with a spoke down its hip line, because the
## other half of what this clip is cannot be read off a silhouette either: the
## body turns through 350° and the spoke is what turns "the shoulders look
## twisted" into an angle. `tools/preview_clips.py` draws the same ring on the
## raw FBX for the same reason.
func _sheet() -> void:
	# Across the frame, and into it. The advance runs along -Z because that is
	# where an untouched Gub node faces, which is the direction `Gub.facing()`
	# hands `begin_spin` at the click.
	var row := Vector3.RIGHT
	var travel := Vector3.FORWARD

	# Which sample gets the RELEASE stamp: the nearest one, chosen up front.
	# Marking "whichever sample is within half a step of 1.067 s" marks nothing
	# at seven samples, because 1.067 falls 0.137 s from one and 0.170 s from
	# the next and the step is 0.311 — so the picture silently lost the one
	# moment it most has to point at.
	var marked := 0
	for i in samples:
		if absf(_sample_time(i, samples) - GubAnimator.SWING_RELEASE_IN_CLIP) \
				< absf(_sample_time(marked, samples) - GubAnimator.SWING_RELEASE_IN_CLIP):
			marked = i

	_ground(row, travel)
	for i in samples:
		var time := _sample_time(i, samples)
		var reached := Gub.SPIN_ADVANCE * float(i) / float(maxi(samples - 1, 1))
		var gub := _bare_gub()
		gub.position = row * (float(i) - float(samples - 1) * 0.5) * SHEET_SPREAD \
			+ travel * reached
		var player := gub.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var skeleton := gub.find_child("Skeleton3D", true, false) as Skeleton3D
		_pose(player, skeleton, time)
		gub.held_gear.set_sword(true)
		# Nothing else in either hand, which is what the game shows through a
		# swing and is also the one thing in frame that could be mistaken for a
		# blade (`GubCombat._wants_shaft`, `_wants_bow`).
		gub.held_gear.set_carried(false)
		gub.held_gear.set_bow(false)

		_compass(gub, skeleton)
		var mark := i == marked
		var stamp := Label3D.new()
		stamp.text = "%.2f s\n%.2f m%s" % [time, reached,
			"\nRELEASE" if mark else ""]
		stamp.font_size = 52
		stamp.pixel_size = 0.0016
		stamp.modulate = Color(1.0, 0.78, 0.30) if mark else Color.WHITE
		stamp.position = Vector3(0.0, 2.80, 0.0)
		stamp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		gub.add_child(stamp)

	_build_stage()


## A ring on the floor under one Gub with a spoke down its hip line, which is
## what turns "the shoulders look twisted" into "the body is 214° round".
##
## The hip line and not the node's yaw: the whole point of this clip is that the
## rotation lives *inside the skeleton*, so a compass drawn off `body_yaw` would
## be a compass that never moved — which is the same fact `GubCombat` has to read
## the blade off the bone attachment for.
func _compass(gub: Gub, skeleton: Skeleton3D) -> void:
	var left := skeleton.find_bone("LeftUpLeg")
	var right := skeleton.find_bone("RightUpLeg")
	if left < 0 or right < 0:
		return
	var a := skeleton.get_bone_global_pose(left).origin
	var b := skeleton.get_bone_global_pose(right).origin
	var side := b - a
	var yaw := atan2(-side.z, -side.x)

	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.95, 0.72, 0.25)
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.60
	torus.outer_radius = 0.66
	ring.mesh = torus
	ring.position = Vector3(0.0, 0.03, 0.0)
	ring.material_override = paint
	gub.add_child(ring)

	# Outside the ring rather than across it. A spoke drawn from the centre is a
	# spoke under the Gub's own legs, which is where the first version of this
	# sheet put it and why the first version showed seven identical rings.
	var spoke := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.55, 0.02, 0.13)
	spoke.mesh = bar
	spoke.material_override = paint
	spoke.position = Vector3(cos(yaw) * 0.93, 0.04, sin(yaw) * 0.93)
	spoke.rotation.y = -yaw
	gub.add_child(spoke)


## The ground the advance is read against: a chalk line across the travel
## direction every half metre, plus one on `Gub.SPIN_ADVANCE` itself, so the
## staircase can be measured off the picture and not merely seen in it.
func _ground(row: Vector3, travel: Vector3) -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	ground.mesh = plane
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.20, 0.23, 0.21)
	ground.material_override = dirt
	add_child(ground)

	var width := SHEET_SPREAD * float(samples) + 0.6
	var marks: Array[float] = [0.0, 0.5, 1.0, 1.5, Gub.SPIN_ADVANCE]
	for i in marks.size():
		var at: float = marks[i]
		var last := i == marks.size() - 1
		var chalk := StandardMaterial3D.new()
		chalk.albedo_color = Color(0.95, 0.72, 0.25) if last \
			else Color(0.50, 0.56, 0.51)
		chalk.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var mark := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(width, 0.01, 0.08 if last else 0.04)
		mark.mesh = bar
		mark.material_override = chalk
		mark.position = travel * at + Vector3(0.0, 0.015, 0.0)
		add_child(mark)

		var tag := Label3D.new()
		tag.text = "%.3f m — the advance" % at if last else "%.1f m" % at
		tag.font_size = 44
		tag.pixel_size = 0.0016
		tag.modulate = chalk.albedo_color
		tag.position = travel * at + row * (width * 0.5 + 0.5) \
			+ Vector3(0.0, 0.10, 0.0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(tag)


## A Gub with nothing driving it: no camera, no plate, no animation tree and no
## combat node, so the only thing posing this skeleton is this file. Leaving
## `Combat` in would have it repaint the hands off a swing gate that knows
## nothing about a preview scene, on the frame after every pose.
func _bare_gub() -> Gub:
	var gub := GUB.instantiate() as Gub
	add_child(gub)
	gub.set_physics_process(false)
	for spare in ["CameraRig", "Nameplate", "AnimationTree", "Combat"]:
		var node := gub.get_node_or_null(spare)
		if node != null:
			node.queue_free()
	return gub


func _build_stage() -> void:
	var label := Label3D.new()
	label.text = "Swing %.3f-%.3f s   release %.3f s   advance %.3f m   sword x%.3f, %.2f m" % [
		GubAnimator.SWING_CLIP_START, GubAnimator.SWING_CLIP_END,
		GubAnimator.SWING_RELEASE_IN_CLIP, Gub.SPIN_ADVANCE, HeldGear.SWORD_SCALE,
		HeldGear.SWORD_LENGTH * HeldGear.SWORD_SCALE]
	label.font_size = 72
	label.pixel_size = 0.0013
	label.position = Vector3(0.0, 3.75, Gub.SPIN_ADVANCE * -0.5)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 25, 0)
	key.light_energy = 2.4
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -160, 0)
	fill.light_energy = 0.7
	fill.light_color = Color(0.6, 0.75, 1.0)
	add_child(fill)

	# Orthographic, for `preview_anim.gd`'s reason: under perspective the end
	# Gubs of a wide row are seen from a different side than the middle one, so
	# the same pose looks like a different pose in every sample. It matters twice
	# here, because the other axis is a distance being measured off the picture:
	# under perspective the far end of the staircase would be smaller than the
	# near end and the chalk lines would not be parallel.
	#
	# Dead front, and lifted: the elevation is what turns the advance into
	# something visible at all. At VIEW_ELEVATION a metre of travel is
	# sin(VIEW_ELEVATION) of a metre up the screen, which over 1.712 m is most of
	# a Gub's own height — enough to read against the chalk, and not so much that
	# the row climbs out of frame.
	var elevation := deg_to_rad(VIEW_ELEVATION)
	var eye := Vector3(0.0, sin(elevation), cos(elevation))
	var view := get_viewport().get_visible_rect().size
	var aspect: float = view.x / maxf(view.y, 1.0)
	var wide := (SHEET_SPREAD * float(samples - 1) + FRAME_MARGIN * 2.0) / aspect
	var target := Vector3(0.0, (FRAME_LOW + FRAME_HIGH) * 0.5,
		Gub.SPIN_ADVANCE * -0.5)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(FRAME_MIN, wide)
	cam.near = 0.05
	cam.far = 200.0
	add_child(cam)
	cam.look_at_from_position(target + eye * 40.0, target, Vector3.UP)
	cam.make_current()
