extends Node3D
## The bow in the hand, across the charge. Development tool, not shipped.
##
## Two jobs, and they are the same job read twice: the numbers that make the
## string meet the fingers, and the picture that shows it does.
##
##   # the derivation, headless, printed — paste the three lines it ends with
##   Godot --headless --path . --script tools/snapshot.gd -- ##       res://tools/preview_bow.tscn out/none.png 4 measure
##
##   # the sheet: six Gubs across the draw, string bending under the charge
##   Godot --path . --resolution 2400x800 --script tools/snapshot.gd -- ##       res://tools/preview_bow.tscn out/bow_draw.png 25
##
## **Why this exists rather than `tools/preview_grip.tscn` with a bow in it.**
## That tool sweeps a grip by eye and prints nothing, which is the right answer
## for a spear: a shaft in a fist only has to miss the Gub's own skin, and there
## is no equation for "looks like it is being held". A bow has a *string*, and
## the string's nocking point has to be where the drawing fingers are at every
## charge level — which is an equation with exactly one answer, so the tool that
## fits it should solve it rather than let somebody nudge three numbers until it
## looks close. `measure` is that solve; the sheet is the check on it (D-065).
##
## It also cannot be `preview_grip`, because half of what has to be looked at is
## the **blend shape**: the string only bends because `HeldGear.set_draw` is
## being handed the same float that scrubs the pose, and a sheet that posed the
## body without pulling the string would certify a bow that never moves.

const GUB := preload("res://scenes/player/gub.tscn")

## Model-space landmarks, in the props' own units, measured off the built GLBs.
##
## The bow's string sits at `STRING_REST_Y` on the model's X axis and is pulled
## along -Y; the arrow's nock is at -X with the shaft axis offset from the model
## origin, because the source mesh was not modelled down its own centre line.
## Both live on `HeldGear` where the grips that use them are — asked of it here
## rather than restated, so the tool and the game cannot disagree about where
## the string is.
const ARROW_NOCK := Vector3(-0.5, 0.0888, -0.0286)

@export var samples: int = 6
@export var spacing: float = 1.35

## The frame, in metres. A drawn bow is 1.5 m of prop held at chest height, so
## this is taller than `preview_grip`'s: the limb tips go well above the head
## and below the waist and both of them have to be in the picture.
const FRAME_LOW := 0.10
const FRAME_HIGH := 2.35
const FRAME_MIN := 2.4
const FRAME_MARGIN := 1.4

## Where the camera stands, in degrees around the Gub, overridable as the third
## argument.
##
## Zero, which is the one angle in `preview_grip.gd`'s own comment that it calls
## useless — and it is the right one here for the opposite reason. That tool is
## judging which way a shaft points out of a fist, so dead front flattens the
## only axis it cares about; this one is judging a **draw**, and the draw runs
## across the Gub from the bow fist to the string fist. Dead front is the angle
## that lays that line flat across the frame, at full width, at every charge.
## Pass 90 for the other question — the string's V seen along the arrow, which
## is the picture that shows the blend shape rather than the pose.
const VIEW_AZIMUTH := 0.0

var _azimuth: float = VIEW_AZIMUTH
const VIEW_ELEVATION := 8.0

## How many charge levels the derivation is checked at. Eleven is every tenth,
## which is fine enough to catch a wrist that rotates through the draw — the one
## way the fingers could leave the straight line the fit assumes.
const CHECKS := 11


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[3] if args.size() > 3 else "sheet"
	if args.size() > 4:
		samples = maxi(2, int(args[4]))
	if args.size() > 5:
		_azimuth = float(args[5])
	if mode == "measure":
		_measure()
		get_tree().quit()
		return
	_sheet()


# ------------------------------------------------------------- the numbers ---

## Solve the grip, print it, and say how far off it is at every charge level.
func _measure() -> void:
	var gub := _bare_gub()
	var skeleton := gub.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := gub.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var left := skeleton.find_bone(HeldGear.BOW_HAND_BONE)
	var right := skeleton.find_bone(HeldGear.HAND_BONE)
	if left < 0 or right < 0:
		print("preview_bow: rig has no %s / %s" % [HeldGear.BOW_HAND_BONE, HeldGear.HAND_BONE])
		return

	# The drawing hand, in the bow hand's own frame, at every charge level. The
	# bow is rigid in the left fist, so this is the only space in which the
	# question "where does the string have to reach" has a fixed answer.
	var drawn: Array[Vector3] = []
	var reach: Array[float] = []
	for i in CHECKS:
		var charge := float(i) / float(CHECKS - 1)
		_pose(player, skeleton, charge)
		var l := skeleton.get_bone_global_pose(left)
		var r := skeleton.get_bone_global_pose(right)
		drawn.append(l.affine_inverse() * r.origin)
		reach.append(l.origin.distance_to(r.origin))

	var p0: Vector3 = drawn[0]
	var p1: Vector3 = drawn[CHECKS - 1]
	var travel := p1 - p0
	var d := travel.normalized()
	var model_scale := travel.length() / HeldGear.NOCK_TRAVEL

	# The limb axis is vertical, which is the one thing about a bow's roll that
	# the string cannot decide: every rotation about the draw direction puts the
	# nocking point in the same place. So it is taken from the world, brought
	# into the fist's frame at the frame that matters, and squared up against
	# the draw direction.
	_pose(player, skeleton, 1.0)
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(left)
	var up_local := hand.basis.inverse() * Vector3.UP
	var y := -d
	var x := (up_local - y * up_local.dot(y)).normalized()
	var basis := Basis(x, y, x.cross(y))
	var offset := p0 + d * (model_scale * HeldGear.STRING_REST_Y)

	print("preview_bow: the bow")
	print("  hands %.3f m apart at brace, %.3f m at full draw (travel %.3f m)"
		% [reach[0], reach[CHECKS - 1], travel.length()])
	print("  the model draws %.4f m, so it is %.3f x its authored size"
		% [HeldGear.NOCK_TRAVEL, model_scale])
	print("  which is a bow %.3f m tip to tip" % (0.986 * model_scale))
	print("  worst miss over %d charge levels:" % CHECKS)
	var worst := 0.0
	for i in CHECKS:
		var charge := float(i) / float(CHECKS - 1)
		var nock := offset + basis * (Vector3(0.0, HeldGear.STRING_REST_Y
			- HeldGear.NOCK_TRAVEL * charge, 0.0) * model_scale)
		var miss := nock.distance_to(drawn[i])
		worst = maxf(worst, miss)
		print("    charge %.1f   string at %v   fingers at %v   %.4f m apart"
			% [charge, nock, drawn[i], miss])
	print("  worst %.4f m" % worst)
	print("    const BOW_SCALE := %.4f" % model_scale)
	print("    const BOW_GRIP_OFFSET := Vector3(%.4f, %.4f, %.4f)"
		% [offset.x, offset.y, offset.z])
	var euler := basis.get_euler() * (180.0 / PI)
	print("    const BOW_GRIP_ROTATION := Vector3(%.3f, %.3f, %.3f)"
		% [euler.x, euler.y, euler.z])

	# The arrow, in the *other* fist and by the same argument: it is aimed down
	# the line between the two hands, which is the line the bow is about to send
	# it along, and slid so its nock is in the fingers rather than its middle.
	_pose(player, skeleton, 1.0)
	var lt := skeleton.get_bone_global_pose(left)
	var rt := skeleton.get_bone_global_pose(right)
	var q := rt.affine_inverse() * lt.origin
	var shaft := q.normalized()
	var length := q.length() + HeldGear.ARROW_OVERHANG
	var right_world := skeleton.global_transform * rt
	var a_up := right_world.basis.inverse() * Vector3.UP
	var a_z := (a_up - shaft * a_up.dot(shaft)).normalized()
	var a_basis := Basis(shaft, a_z.cross(shaft), a_z)
	var a_offset := -(a_basis * (ARROW_NOCK * length))
	_report_carry(gub, player, skeleton)

	print("preview_bow: the arrow")
	print("  %.3f m of draw plus %.2f m of overhang = %.3f m of arrow"
		% [q.length(), HeldGear.ARROW_OVERHANG, length])
	print("    const ARROW_SCALE := %.4f" % length)
	print("    const ARROW_GRIP_OFFSET := Vector3(%.4f, %.4f, %.4f)"
		% [a_offset.x, a_offset.y, a_offset.z])
	var a_euler := a_basis.get_euler() * (180.0 / PI)
	print("    const ARROW_GRIP_ROTATION := Vector3(%.3f, %.3f, %.3f)"
		% [a_euler.x, a_euler.y, a_euler.z])


## How low the carried bow hangs in every clip a Gub walks around in.
##
## The same table `HeldGear`'s header keeps for the spear and for the same
## reason: a prop rigidly attached to a hand goes wherever that hand goes, and
## the one thing it must not do is plough the grass. A bow is much the worse
## case — 1.71 m of it against the spear's 1.24, and held near its middle rather
## than 55% of the way up — so the number is worth having rather than guessing.
##
## Measured off the model's own limb tips through the bone, not off a bounding
## box: the mesh runs +-0.5 along its local X and the two ends are what touch.
func _report_carry(gub: Gub, player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var hand := skeleton.find_bone(HeldGear.BOW_HAND_BONE)
	print("preview_bow: the carry, lowest limb tip above the floor")
	for clip: String in ["Idle", "Walk", "Run", "CrouchIdle", "CrouchWalk"]:
		if not player.has_animation(clip):
			continue
		var length := player.get_animation(clip).length
		var lowest := INF
		var at := 0.0
		for i in 24:
			var time := length * float(i) / 24.0
			player.play(clip)
			player.seek(time, true, true)
			player.pause()
			skeleton.force_update_all_bone_transforms()
			var grip := gub.global_transform * skeleton.global_transform 				* skeleton.get_bone_global_pose(hand) 				* Transform3D(Basis.from_euler(HeldGear.BOW_GRIP_ROTATION * (PI / 180.0)),
					HeldGear.BOW_GRIP_OFFSET)
			for end: float in [-0.5, 0.5]:
				var tip: Vector3 = grip * (Vector3(end, 0.0, 0.0) * HeldGear.BOW_SCALE)
				if tip.y < lowest:
					lowest = tip.y
					at = time
		print("  %-11s lowest tip %+.3f m at %.2f s" % [clip, lowest, at])


## Put the skeleton in the pose the game would hold at this charge.
##
## Through the same two constants `GubAnimator` scrubs with, so a window that
## moves moves this tool with it. `advance` and then a forced pose update,
## because an `AnimationPlayer` only writes into the skeleton when it is
## processed and this reads it back in the same call.
func _pose(player: AnimationPlayer, skeleton: Skeleton3D, charge: float) -> void:
	player.play("Draw")
	player.seek(GubAnimator.draw_time(charge), true, true)
	player.pause()
	skeleton.force_update_all_bone_transforms()


# ------------------------------------------------------------- the picture ---

func _sheet() -> void:
	var azimuth := deg_to_rad(_azimuth)
	var elevation := deg_to_rad(VIEW_ELEVATION)
	var eye := Vector3(sin(azimuth) * cos(elevation), sin(elevation),
		-cos(azimuth) * cos(elevation))
	# The row runs along the camera's own right vector, not world X, or the end
	# Gubs of an oblique row hide each other. See `preview_grip.gd`, which
	# learned this the hard way.
	var row := -Vector3(cos(azimuth), 0.0, sin(azimuth))

	for i in samples:
		var charge := float(i) / float(samples - 1)
		var gub := _bare_gub()
		gub.position = row * (float(i) - float(samples - 1) * 0.5) * spacing
		var player := gub.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var skeleton := gub.find_child("Skeleton3D", true, false) as Skeleton3D
		_pose(player, skeleton, charge)
		# The half of this the numbers cannot show: the string is only bent
		# because the same float that picked the pose was handed to the morph.
		gub.held_gear.set_bow(true)
		gub.held_gear.set_arrow(true)
		gub.held_gear.set_draw(charge)

		var stamp := Label3D.new()
		stamp.text = "%d%%" % roundi(charge * 100.0)
		stamp.font_size = 64
		stamp.pixel_size = 0.0016
		stamp.position = Vector3(0.0, 2.20, 0.0)
		stamp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		gub.add_child(stamp)

	_build_stage(eye)


## A Gub with nothing driving it: no camera, no plate, no animation tree and no
## combat node, so the only thing posing this skeleton is this file. Leaving
## `Combat` in would have it repaint the hands off a throw gate that knows
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


func _build_stage(eye: Vector3) -> void:
	var label := Label3D.new()
	label.text = "Draw %.3f-%.3f s, indexed by charge   bow x%.3f   arrow %.2f m" % [
		GubAnimator.DRAW_CLIP_START, GubAnimator.DRAW_CLIP_FULL,
		HeldGear.BOW_SCALE, HeldGear.ARROW_SCALE]
	label.font_size = 72
	label.pixel_size = 0.0013
	label.position = Vector3(0, 2.55, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 25, 0)
	key.light_energy = 2.4
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -160, 0)
	fill.light_energy = 0.7
	fill.light_color = Color(0.6, 0.75, 1.0)
	add_child(fill)

	# Orthographic, for `preview_anim.gd`'s reason: under perspective the end
	# Gubs of a wide row are seen from a different side than the middle one, so
	# the same grip looks like a different grip in every sample.
	var view := get_viewport().get_visible_rect().size
	var aspect: float = view.x / maxf(view.y, 1.0)
	var wide := (spacing * float(samples - 1) + FRAME_MARGIN) / aspect
	var target := Vector3(0.0, (FRAME_LOW + FRAME_HIGH) * 0.5, 0.0)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(FRAME_MIN, wide)
	cam.near = 0.05
	cam.far = 100.0
	add_child(cam)
	cam.look_at_from_position(target + eye * 20.0, target, Vector3.UP)
	cam.make_current()
