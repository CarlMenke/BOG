extends Node3D
## Where the nameplate hangs against the head it is supposed to be above
## (D-150). Development tool, not shipped.
##
##   # the table — every pose, headless, printed, with a verdict
##   Godot --headless --path . tools/preview_plate.tscn
##
##   # the clip that crosses, plate and all: the run jump
##   Godot --path . --resolution 2400x800 --script tools/snapshot.gd -- \
##       res://tools/preview_plate.tscn out/plate_runjump.png 20 sheet RunJump
##
##   # and the dive, which is the one the ticket named and the one that turns
##   # out not to need the lift at all
##   Godot --path . --resolution 2400x800 --script tools/snapshot.gd -- \
##       res://tools/preview_plate.tscn out/plate_dive.png 20 sheet Roll 0.60 1.20
##
## The table needs no render and so goes straight to the scene rather than
## through `tools/snapshot.gd`, the way `team_plates` and `weapon_select` do.
##
## **A real `bog.tscn` with its real `Nameplate` on it**, and not a Label3D over
## a posed skeleton, because the whole of what is being checked is the plate's
## own per-frame arithmetic. The `AnimationTree` is taken away and the body's own
## `AnimationPlayer` is seeked instead — `preview_carry._bare_bog`'s trick, one
## node less — so a pose is a clip and a time rather than a blend state that has
## to be driven into existence.
##
## The measurement is the one the plate makes: `Bog.head_centre()` plus
## `Bog.HEAD_RADIUS` is the crown of the skull, `Nameplate.name_bottom()` is the
## lowest ink of the name, and the gap between them is what a player sees as
## daylight. It is taken a frame **after** the pose is set, so what is read is
## the plate's own `_process` doing its job and not this file reproducing it.

const BOG := preload("res://scenes/player/bog.tscn")

## How many moments of each clip are sampled. Twelve is `preview_carry`'s number
## for a cycle that breathes, and a dive's apex is one frame in a second of
## clip — coarser than this and the sheet and the table stop being about the
## same moment.
const SAMPLES := 12
## How many of them the sheet draws. Fewer, because a row of twelve Bogs in one
## frame is twelve Bogs too small to see a plate over.
const SHEET_SAMPLES := 8

## The clips a body leaves the ground in, which is the whole reason this check
## exists: everything that separates the model from the capsule is in here.
const AIR_CLIPS := ["Roll", "JumpStart", "AirLoop", "RunJump", "SlideJump",
	"Land", "LandHard", "Slide"]
## The clips it does not, which are here as the control. A plate that lifted in
## any of these would be a plate that moves while a Bog is standing about, and
## the lobby's own band checks (`tools/ui_range.tscn`) are measured on the
## resting height.
const GROUND_CLIPS := ["Idle", "Walk", "Run", "CrouchIdle", "CrouchWalk",
	"Throw", "SwordCombo", "Drink", "Twerk", "BowAim"]

const FRAME_LOW := -0.2
const FRAME_HIGH := 2.9
const FRAME_MIN := 3.2
const FRAME_MARGIN := 1.2
@export var spacing: float = 1.6

var _bog: Bog
var _plate: Nameplate
var _player: AnimationPlayer


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[3] if args.size() > 3 else "measure"
	if mode == "sheet":
		_sheet(args[4] if args.size() > 4 else "Roll",
			float(args[5]) if args.size() > 5 else 0.0,
			float(args[6]) if args.size() > 6 else -1.0)
		return
	await _measure()
	get_tree().quit()


# --------------------------------------------------------------- the table ---

func _measure() -> void:
	print("preview_plate: the head against the name it is under, %d moments a clip"
		% SAMPLES)
	print("  %-14s %8s %8s %8s %8s" % ["clip", "crown", "name", "gap", "lift"])
	var worst := INF
	var worst_in := ""
	var resting := 0.0
	for clip: String in AIR_CLIPS + GROUND_CLIPS:
		# A Bog of its own per clip, and it is not tidiness: the lift falls back
		# over `Nameplate.LIFT_FALL` rather than snapping down, so a plate carried
		# on from the clip before would report a lift the clip it is filed under
		# never asked for. One clip, one body, one history.
		_stand_one()
		if not _player.has_animation(clip):
			push_warning("preview_plate: no clip '%s'" % clip)
			continue
		var row := await _row(clip)
		_bog.queue_free()
		if clip == "Idle":
			resting = row[3]
		if row[2] < worst:
			worst = row[2]
			worst_in = clip
		print("  %-14s %8.3f %8.3f %8.3f %8.3f" % [clip, row[0], row[1], row[2], row[3]])

	# The name never crosses the head. Zero and not a margin, because the margin
	# is `Nameplate.HEAD_GAP`'s job and stating it twice would be two opinions
	# about the same daylight — this asks the question a player asks, which is
	# whether the skull is through the lettering.
	if worst < 0.0:
		print("preview_plate: plate FAIL — the crown of the head is %.3f m into "
			% -worst + "the name in %s. `Nameplate.HEAD_GAP` is the lever."
			% worst_in)
	else:
		print("preview_plate: the name clears the crown of the head by %.3f m at "
			% worst + "its tightest (%s), in every sampled moment of %d clips "
			% [worst_in, AIR_CLIPS.size() + GROUND_CLIPS.size()] + "— plate PASS")

	# And it does not move while nothing is happening. The lobby's ring is
	# measured on the resting height (`tools/ui_range.tscn`, D-118), so a lift
	# that crept in at Idle would be this change quietly re-framing three panels.
	if is_zero_approx(resting):
		print("preview_plate: the plate is at its scene height in Idle (lift "
			+ "%.3f m) — resting PASS" % resting)
	else:
		print("preview_plate: resting FAIL — the plate sits %.3f m above its "
			% resting + "scene height in Idle, so every framing measured against "
			+ "it has moved.")


## One clip's row: `[crown, name bottom, worst gap, worst lift]`, the crown and
## the name taken at the moment the gap is tightest.
func _row(clip: String) -> Array:
	var length := _player.get_animation(clip).length
	var out := [0.0, 0.0, INF, 0.0]
	for i in SAMPLES:
		await _pose(clip, length * float(i) / float(SAMPLES))
		var crown := _crown()
		var bottom := _plate.name_bottom()
		out[3] = maxf(out[3], _plate.head_lift())
		if bottom - crown < out[2]:
			out = [crown, bottom, bottom - crown, out[3]]
	return out


## The top of the skull in this Bog's own frame — `Bog.head_centre()` and the
## half-height the headshot is resolved against, which is the pair the plate
## itself reads. Measured off the Bog's origin and not off the world, so a row
## is a fact about the body rather than about where this tool stood it.
func _crown() -> float:
	return _bog.head_centre().y + Bog.HEAD_RADIUS - _bog.global_position.y


# ------------------------------------------------------------- the picture ---

## One row of Bogs, each at its own moment of `clip`, plate and all. `to` below
## zero means the whole clip.
func _sheet(clip: String, from: float, to: float) -> void:
	var length := 0.0
	var x := -spacing * float(SHEET_SAMPLES - 1) * 0.5
	for i in SHEET_SAMPLES:
		var bog := _stand(Vector3(x, 0.0, 0.0), "Bog%d" % i)
		x += spacing
		var player := bog.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if not player.has_animation(clip):
			push_error("preview_plate: no clip '%s'" % clip)
			return
		length = player.get_animation(clip).length
		var span := (length if to < 0.0 else to) - from
		player.play(clip)
		player.seek(from + span * float(i) / float(maxi(SHEET_SAMPLES - 1, 1)), true, true)
		player.pause()

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -30, 0)
	key.light_energy = 2.4
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 150, 0)
	fill.light_energy = 0.6
	fill.light_color = Color(0.6, 0.75, 1.0)
	add_child(fill)
	_ground()

	# Orthographic and level, for `preview_bog`'s reason — every sample is seen
	# from the same angle — but stood **8 m** back and not twenty: the plate
	# fades out from `Nameplate.FADE_START` and a camera parked past it would
	# photograph a row of Bogs with no names over them.
	var view := get_viewport().get_visible_rect().size
	var aspect: float = view.x / maxf(view.y, 1.0)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(FRAME_MIN,
		(spacing * float(SHEET_SAMPLES - 1) + FRAME_MARGIN) / aspect)
	cam.near = 0.05
	cam.far = 100.0
	cam.position = Vector3(0.0, (FRAME_LOW + FRAME_HIGH) * 0.5, 8.0)
	add_child(cam)
	cam.make_current()


func _ground() -> void:
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(60.0, 60.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.20, 0.22, 0.24)
	plane.mesh = mesh
	plane.material_override = material
	add_child(plane)


# ----------------------------------------------------------------- the rig ---

## A `bog.tscn` with its plate, its physics off and its animation graph gone.
## `preview_carry._bare_bog` frees the plate and keeps the tree; this is the
## other half of the same trick.
func _stand(at: Vector3, display: String) -> Bog:
	var bog := BOG.instantiate() as Bog
	add_child(bog)
	bog.position = at
	bog.set_physics_process(false)
	for spare in ["CameraRig", "AnimationTree"]:
		var node := bog.get_node_or_null(spare)
		if node == null:
			continue
		# Switched off before it is dropped, and that order is the whole thing:
		# `queue_free` is deferred, so a graph freed and then left to the end of
		# the frame gets one more turn at the player this tool has just seeked —
		# and every pose comes out as whatever the tree's idle state is.
		var tree := node as AnimationTree
		if tree != null:
			tree.active = false
		node.queue_free()
	var plate := bog.get_node_or_null("Nameplate") as Nameplate
	plate.set_display_name(display)
	return bog


func _stand_one() -> void:
	_bog = _stand(Vector3.ZERO, "Bog")
	_plate = _bog.get_node_or_null("Nameplate") as Nameplate
	_player = _bog.find_child("AnimationPlayer", true, false) as AnimationPlayer


## Put the body at `time` of `clip` and let a frame pass, so the plate has run
## its own `_process` over the pose before anything is read off it.
func _pose(clip: String, time: float) -> void:
	_player.play(clip)
	_player.seek(time, true, true)
	_player.pause()
	await get_tree().process_frame
