extends Node3D
## The capture performance, stood up on one Bog and measured.
## Development tool, not shipped.
##
##   # the numbers, headless, no picture: the two anchors and the descent
##   Godot --headless --path . tools/preview_capture.tscn
##
##   # the same with the clock frozen half way down
##   Godot --headless --path . tools/preview_capture.tscn -- f=0.5
##
##   # the look: the right fist, the raised arm and the card above it
##   Godot --path . --resolution 1600x900 --script tools/snapshot.gd -- \
##       res://tools/preview_capture.tscn out/capture_hand.png 40 f=0.5
##
##   # and the other end of it, the pouch at the hip
##   Godot --path . --resolution 1600x900 --script tools/snapshot.gd -- \
##       res://tools/preview_capture.tscn out/capture_pouch.png 40 f=0.9 pouch
##
## **Why a tool at all.** `HeldGear.POUCH_GRIP_OFFSET` and
## `POUCH_GRIP_ROTATION` are the only grip constants in this repo that were
## written down rather than solved, and they say so in their own comments: the
## pouch is a new prop in a fist whose one measured palm point was taken for a
## bottle in a different pose. Nothing here solves them either — a sack hanging
## off a hip has no equation the way a shaft crossing a trunk does — so what
## this does instead is the honest half: it prints where every part of the
## performance actually ended up, in world metres, beside a picture of it, so
## the offsets can be read off a render and pasted back.
##
## **It is also the check.** The verdict is about the things that are
## structural rather than aesthetic — the pouch is in the left fist, the card
## is *not* in the right one, the mouth is below the raised hand, and the
## letter is on the line between them — because those four are what the
## performance is, and every one of them is a thing three files have to agree
## about (`BogCombat._refresh_hand`, `HeldGear`, `CaptureRig`).
##
## The Bog is a **remote** one: its authority is a peer that will never
## connect, set before `add_child` exactly as `BogBackdrop._make_bog` does it,
## because a Bog that believes it is the local player makes its own camera
## current in `_ready` and this scene's camera is never seen again.

const BOG := preload("res://scenes/player/bog.tscn")

## The Bog's peer, and the key the hold row is written under. Not 1, and that
## is the whole of the paragraph above: 1 is the local peer in an offline
## session, and a Bog with local authority takes the viewport.
const PREVIEW_PEER := 700

## The hold this scene stands up: ten seconds, which is
## `MatchConfig.letter_hold_time`'s own default order of magnitude and long
## enough that an unfrozen run walks the whole descent in front of a window.
const HOLD_SECONDS := 10.0

## How long to let the rig settle before anything is measured, in physics
## ticks. The bone attachments need a frame, the animation tree needs a few to
## bring the capture layer up at `CAPTURE_BLEND_SPEED`, and the card is built
## on the first frame the hold is seen. Half a second covers all three with
## room over.
const SETTLE_TICKS := 30

## How far off the straight line between the two anchors the card may be and
## still count as descending. The bob is `CaptureRig.BOB_HEIGHT` at its
## fullest, so anything inside a couple of finger-widths of that is the float
## and anything outside it is a broken lerp.
const ON_LINE_MAX := 0.15

## How much of the pouch has to be out of the grass: the mouth's height less
## the sack's own drop. A floor rather than a target, `preview_carry.CARRY_MIN`'s
## much smaller cousin — a pouch is not a spear and only has to not be buried.
const POUCH_CLEARANCE_MIN := 0.05

var _bog: Bog
var _frozen: float = -1.0
var _framing: String = "hand"
var _ticks: int = 0
var _done: bool = false
var _camera: Camera3D
var _problems: Array[String] = []


func _ready() -> void:
	Engine.max_fps = int(ProjectSettings.get_setting(
		"physics/common/physics_ticks_per_second", 60))
	# Found by *prefix* rather than at a fixed index, `combat_range._ready`'s
	# own reasoning: through `snapshot.gd` the user args are
	# `scene png ticks ...` and run as a plain scene they are just the extras,
	# and the two do not agree about where the trailing arguments start.
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("f="):
			_frozen = clampf(float(arg.substr(2)), 0.0, 1.0)
		elif arg == "pouch" or arg == "hand" or arg == "whole":
			_framing = arg

	Net.start_offline()
	Net.config.win_condition = MatchConfig.WinCondition.LETTERS
	Net.config.mode = MatchConfig.Mode.FREE_FOR_ALL

	_build_stage()
	_bog = BOG.instantiate() as Bog
	_bog.name = "CaptureBog"
	_bog.peer_id = PREVIEW_PEER
	# Before `add_child`, always — see the header.
	_bog.set_multiplayer_authority(PREVIEW_PEER)
	add_child(_bog)
	# A remote Bog takes its whole pose from the replicated fields and nobody
	# is going to replicate anything to this one. `sync_grounded` in particular
	# has to be set by hand: left false, the animator plays the jump clip for
	# ever and the preview is a Bog frozen in mid-leap.
	_bog.sync_grounded = true
	_bog.sync_velocity = Vector3.ZERO
	_bog.global_position = Vector3.ZERO

	_write_hold()
	# The row is written straight into `MatchState` rather than claimed off a
	# real pickup, which is what `combat_range`'s bow mode does one file over
	# and for the same reason: this scene is about what a hold *looks like* and
	# has no interest in how one is started. The signal is the half that
	# matters — `BogCombat._on_letter_hold_changed` is what puts the pouch in
	# the fist, and a row written without it would be a Bog holding nothing.
	MatchState.letter_hold_changed.emit(PREVIEW_PEER)
	var frozen_note := (" frozen at f=%.2f" % _frozen) if _frozen >= 0.0 else ""
	print("preview_capture: a %.0f s hold on peer %d%s"
		% [HOLD_SECONDS, PREVIEW_PEER, frozen_note])


func _process(_delta: float) -> void:
	if _camera != null:
		_camera.make_current()


func _physics_process(_delta: float) -> void:
	if _frozen >= 0.0:
		# Re-stamped every tick rather than written once, because the fraction
		# is derived from a wall clock that does not stop for a preview: the
		# row is slid forward under it so that `letter_hold_fraction` keeps
		# answering the same number while the descent is photographed.
		_write_hold()
	_ticks += 1
	if _done or _ticks < SETTLE_TICKS:
		return
	_done = true
	_aim()
	_report()
	# Only when there is no window to photograph. Under `snapshot.gd` this
	# scene has to stay up until the grab, and snapshot ends the run itself;
	# run headless as a plain scene, nothing else ever will.
	if DisplayServer.get_name() == "headless":
		get_tree().quit()


func _write_hold() -> void:
	var now := Time.get_ticks_msec() * 0.001
	var f := _frozen if _frozen >= 0.0 else 0.0
	MatchState._letter_holds[PREVIEW_PEER] = {
		"letter": MatchState.LETTER_B,
		"ends_at": now + HOLD_SECONDS * (1.0 - f),
		"started_at": now - HOLD_SECONDS * f,
		"seconds": HOLD_SECONDS,
	}


# ------------------------------------------------------------- the numbers ---

## Every part of the performance, in world metres, and then the verdict.
##
## Printed as positions rather than as offsets on purpose. An offset is only
## meaningful against the pose it was taken in, which is the lesson D-074 cost
## an afternoon to learn; a world position beside a render of the same frame is
## a thing anybody can check with their eyes.
func _report() -> void:
	# Typed by hand for the reason `BogAnimator` types `capturing`: `Bog` is
	# in a reference cycle, and on a cold cache an inference off it can fail
	# before the class has finished parsing — which took this tool's own
	# script down, left the scene with nothing to call `quit`, and hung the
	# gate on this check for a quarter of an hour.
	var gear: HeldGear = _bog.held_gear
	var rig: CaptureRig = _bog.capture_rig
	if gear == null or rig == null:
		print("preview_capture: the Bog has no gear or no rig — capture FAIL")
		return

	var hand := gear.hand_transform().origin
	var anchor := hand + Vector3.UP * CaptureRig.HAND_LIFT
	var bow_hand := gear.bow_hand_transform().origin
	var mouth := gear.pouch_mouth_global()
	var card: Vector3 = rig.letter_global()
	var f := MatchState.letter_hold_fraction(PREVIEW_PEER)

	print("preview_capture: right hand  (%.3f, %.3f, %.3f)" % [hand.x, hand.y, hand.z])
	print("preview_capture: anchor      (%.3f, %.3f, %.3f)  +%.2f above it"
		% [anchor.x, anchor.y, anchor.z, CaptureRig.HAND_LIFT])
	print("preview_capture: left hand   (%.3f, %.3f, %.3f)"
		% [bow_hand.x, bow_hand.y, bow_hand.z])
	print("preview_capture: pouch mouth (%.3f, %.3f, %.3f)  sack bottom at %.3f"
		% [mouth.x, mouth.y, mouth.z, mouth.y - PouchMesh.drop()])
	if card == Vector3.INF:
		print("preview_capture: letter      — nothing drawn")
	else:
		print("preview_capture: letter      (%.3f, %.3f, %.3f)  f=%.2f  scale %.2f"
			% [card.x, card.y, card.z, f, rig.letter_size()])
	print("preview_capture: descent     %.3f m, hand to mouth"
		% anchor.distance_to(mouth))

	# The four structural claims. Each is a thing two or three files have to
	# agree about, and each has been wrong at least once in some other prop's
	# history: a hand holding two objects, a hand holding none, a prop hung off
	# the wrong bone, a lerp between anchors read in the wrong order.
	_want("the pouch is in the left fist", gear.has_pouch())
	_want("and the card is not in the right one", not gear.has_letter())
	_want("the pouch clears the grass",
		mouth.y - PouchMesh.drop() > POUCH_CLEARANCE_MIN)
	_want("the mouth is below the raised hand", mouth.y < anchor.y)
	if card != Vector3.INF:
		_want("the letter is on the line between them",
			_off_line(card, anchor, mouth) < ON_LINE_MAX)
	else:
		_want("the letter is drawn", false)

	if _problems.is_empty():
		print("preview_capture: capture PASS")
	else:
		print("preview_capture: capture FAIL (%s)" % "; ".join(_problems))


func _want(claim: String, held: bool) -> void:
	if not held:
		_problems.append(claim)


## How far `point` sits off the segment from `a` to `b`, in metres.
static func _off_line(point: Vector3, a: Vector3, b: Vector3) -> float:
	var span := b - a
	var length := span.length()
	if length < 0.001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(span) / (length * length), 0.0, 1.0)
	return point.distance_to(a + span * t)


# --------------------------------------------------------------- the stage ---

## Aimed after the settle rather than in `_ready`, because two of the three
## framings are aimed at a **bone**, and on the first frame the attachments
## have not been placed yet.
func _aim() -> void:
	var gear: HeldGear = _bog.held_gear
	var look := Vector3(0.0, 1.2, 0.0)
	var eye := Vector3(1.9, 1.5, 2.4)
	match _framing:
		"hand":
			look = gear.hand_transform().origin + Vector3.UP * (CaptureRig.HAND_LIFT * 0.5)
			eye = look + Vector3(1.1, 0.15, 1.5)
		"pouch":
			look = gear.pouch_mouth_global() + Vector3.DOWN * (PouchMesh.drop() * 0.5)
			eye = look + Vector3(0.9, 0.25, 1.2)
	_camera.look_at_from_position(eye, look, Vector3.UP)


func _build_stage() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	light.light_energy = 1.2
	add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.14, 0.16, 0.18)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.55)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)

	# The floor is here for the same reason `preview_carry`'s is: every height
	# printed above is a height above it, and a picture of a sack at a hip
	# needs the grass line in it to be worth anything.
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.30, 0.18)
	floor_mesh.material_override = mat
	add_child(floor_mesh)

	_camera = Camera3D.new()
	_camera.fov = 45.0
	add_child(_camera)
	_camera.look_at_from_position(Vector3(1.9, 1.5, 2.4), Vector3(0.0, 1.2, 0.0),
		Vector3.UP)
