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
##   # the descent as a sheet: six Bogs, six fractions, from the front
##   Godot --path . --resolution 2400x1000 --script tools/snapshot.gd -- \
##       res://tools/preview_capture.tscn out/capture_sheet.png 90 sheet front
##
##   # the same from the side, which is the view the letter's path is judged in
##   Godot --path . --resolution 2400x1000 --script tools/snapshot.gd -- \
##       res://tools/preview_capture.tscn out/capture_sheet_side.png 90 sheet side
##
##   # the bag swinging and settling: six bags, one fraction, six moments
##   Godot --path . --resolution 2400x1000 --script tools/snapshot.gd -- \
##       res://tools/preview_capture.tscn out/capture_settle.png 90 sheet settle
##
##   # and the same thing as numbers
##   Godot --headless --path . tools/preview_capture.tscn -- swing
##
##   # and the grip offset that carries the mouth a wanted distance out front
##   Godot --headless --path . tools/preview_capture.tscn -- solve
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
## is *not* in the right one, the mouth is below the start, and the letter
## comes down in front of the Bog rather than through it — because those are
## what the performance is, and every one of them is a thing three files have to
## agree about (`BogCombat._refresh_hand`, `HeldGear`, `CaptureRig`).
##
## **The last of those is new and is D-172.** "On the line between them" was a
## check that the lerp had not been written backwards, and it passed for the
## whole of the time the line ran through the Bog's chest. What replaced it
## samples `CaptureRig.descent_point` from end to end and asks two things of
## every sample: that it is above and no further back than the bag, and that it
## never comes nearer the body's own axis than the capsule is wide.
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

## How many points of the descent the two claims about it are asked of. Forty
## intervals over a ten-second hold is a sample every quarter of a second,
## which is finer than the curve has features.
const PATH_SAMPLES := 40

## How near the Bog's own vertical axis the letter may pass, in metres.
## `Bog.CAPSULE_RADIUS`, and deliberately the collision capsule rather than the
## skinned trunk: the capsule is the widest the body is ever claimed to be, so a
## card outside it is outside the Bog under every pose and every skin.
const BODY_CLEAR_MIN := 0.38

## The slack on "above and in front of the bag", in metres. The path *ends* at
## the mouth, so the last sample is level with it and dead on it for forwardness
## — this is the rounding that lets an equality pass.
const BAG_SLACK := 0.02

## Where the sheet stands its six Bogs and what fraction each is frozen at.
## Spread by a little over two body widths, which is `preview_carry`'s own
## `CANDIDATE_SPREAD` reasoning: near enough that one camera holds the row,
## far enough that a letter 0.4 m out in front of one Bog is not in front of
## the next.
const SHEET_FRACTIONS: Array[float] = [0.0, 0.25, 0.5, 0.75, 0.9, 1.0]
const SHEET_SPREAD := 1.6

## Which way the `side` sheet turns its Bogs: a quarter turn right, which by
## `Bog.facing`'s own `(−sin, 0, −cos)` puts the Bog's **left** flank — the one
## the bag hangs on — toward a camera that never moves off world −Z.
const SHEET_SIDE_YAW := -PI * 0.5

## The tick the sheet is photographed on, and how far apart it staggers the six
## bags' knocks.
##
## The sheet has one shutter and the swing is a thing that happens over time, so
## the six columns are nudged at six different moments *before* that shutter:
## the leftmost is hit as the picture is taken and the rightmost was hit five
## steps earlier. Read from left to right the row is one bag swinging and
## settling, which is a still photograph of a motion and is the only kind this
## tool takes. Nine ticks apart covers 0.75 s across the row, which is a swing
## and a half of a 0.50 s spring — enough that the decay is the difference
## between the columns rather than the phase.
##
## The grab must be asked for at this tick — `snapshot.gd`'s third argument.
const SHEET_GRAB_TICK := 90
const SHEET_SWING_STEP := 9

## The swing trace: how long it watches the bag being simply carried before it
## knocks it, how long it watches after, and how often it prints — all in
## ticks. A 0.50 s natural period (`HeldGear.SWAY_STIFFNESS`) means 90 ticks is
## a second and a half, which is three swings and the stillness after them, and
## a second of baseline is more than one breath of the idle.
const SWING_BASELINE_TICKS := 60
const SWING_TICKS := 90
const SWING_EVERY := 5

## What the trace has to see to call it life, in degrees and **over the idle's
## own sway**: the letter landing takes the bag at least this much further over
## than being carried does, and by the end it is back within this much of it.
const SWING_PEAK_MIN := 8.0
const SWING_REST_MAX := 2.5

## Where `-- solve` aims the mouth: this far in front of the Bog's own axis, in
## metres. The bag is carried *out front* (D-172) and an arm is a clip, so what
## this number is is the furthest forward the sack can be taken by an offset
## before it stops looking held — a little over the width of the mitten past
## the wrist, and the rest waits for BOG-17's take.
const CARRY_AHEAD := 0.365

## How much of the pouch has to be out of the grass: the mouth's height less
## the sack's own drop. A floor rather than a target, `preview_carry.CARRY_MIN`'s
## much smaller cousin — a pouch is not a spear and only has to not be buried.
const POUCH_CLEARANCE_MIN := 0.05

var _bog: Bog
## The sheet's six, or the one Bog above on its own. One array so that
## everything after the build reads the same whether there is a row of them or
## not — the alternative is every function below asking which mode it is in.
var _bogs: Array[Bog] = []
## What fraction each of them was stood up at, in step with `_bogs`. Kept
## rather than re-derived every tick, because `settle` stands six Bogs at one
## fraction and a tick that went back to `SHEET_FRACTIONS` would slide five of
## them back down the descent.
var _fractions: Array[float] = []
var _frozen: float = -1.0
var _framing: String = "hand"
## `""`, `sheet`, `swing` or `solve`. The framing and the mode are two words
## rather than one because a sheet is taken from the front *and* from the side,
## and a mode that carried its camera would need two spellings of itself.
var _mode: String = ""
var _ticks: int = 0
var _done: bool = false
var _camera: Camera3D
var _problems: Array[String] = []
## The swing trace: the bag's tilt, in degrees, one sample per `SWING_EVERY`
## ticks after the knock.
var _swing: Array[float] = []
## The same, over the second before the knock: what the bag does while it is
## only being carried, which every number after it is measured against.
var _idle: Array[float] = []
var _swing_from: int = 0


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
		elif arg == "pouch" or arg == "hand" or arg == "whole" \
				or arg == "front" or arg == "side" or arg == "settle":
			_framing = arg
		elif arg == "sheet" or arg == "swing" or arg == "solve":
			_mode = arg
	if _mode == "sheet" and _framing != "side" and _framing != "settle":
		_framing = "front"

	Net.start_offline()
	Net.config.win_condition = MatchConfig.WinCondition.LETTERS
	Net.config.mode = MatchConfig.Mode.FREE_FOR_ALL

	_build_stage()
	if _mode == "sheet":
		var half := float(SHEET_FRACTIONS.size() - 1) * 0.5
		# The row is always spread along world X and always photographed from
		# world −Z, because one camera cannot see round a row it is looking
		# along: the two framings turn the *Bogs* instead. `side` yaws them a
		# quarter turn so the camera gets the left flank — the one the bag is
		# on, and the one the letter's path shows its shape in.
		#
		# Laid out **backwards along X**, because a camera on −Z looking up it
		# has +X on its left: f rises left to right on the sheet, which is the
		# only order anybody reads one in.
		var yaw := 0.0 if _framing == "front" else SHEET_SIDE_YAW
		for column: int in SHEET_FRACTIONS.size():
			# `settle` holds the *fraction* still and lets only the knock vary,
			# because a sheet that moved both would show two things at once and
			# prove neither: there, every column is the frame the letter landed
			# on and the only difference is how long ago the bag was hit.
			var f := 1.0 if _framing == "settle" else SHEET_FRACTIONS[column]
			# Centred on the origin rather than run out from it, so the sheet's
			# cameras are the single Bog's cameras pulled back and nothing has
			# to be re-aimed.
			_stand_bog(PREVIEW_PEER + column, f,
				Vector3((half - float(column)) * SHEET_SPREAD, 0.0, 0.0), yaw)
		# Column zero is the one every number is printed off, and the row is
		# centred on the camera by the stage rather than by moving it.
		_bog = _bogs[0]
	else:
		_bog = _stand_bog(PREVIEW_PEER, _frozen, Vector3.ZERO)

	var frozen_note := (" frozen at f=%.2f" % _frozen) if _frozen >= 0.0 else ""
	var many := (" x%d" % _bogs.size()) if _bogs.size() > 1 else ""
	print("preview_capture: a %.0f s hold on peer %d%s%s"
		% [HOLD_SECONDS, PREVIEW_PEER, many, frozen_note])


## One Bog, standing at `at`, holding a letter `fraction` of the way down.
##
## A **remote** one, and the two lines that make it one are the header's: the
## authority goes on before `add_child`, and the replicated fields are set by
## hand because nobody is ever going to replicate anything to it.
func _stand_bog(peer: int, fraction: float, at: Vector3, yaw: float = 0.0) -> Bog:
	var bog := BOG.instantiate() as Bog
	bog.name = "CaptureBog%d" % peer
	bog.peer_id = peer
	bog.set_multiplayer_authority(peer)
	add_child(bog)
	# A remote Bog takes its whole pose from the replicated fields and nobody
	# is going to replicate anything to this one. `sync_grounded` in particular
	# has to be set by hand: left false, the animator plays the jump clip for
	# ever and the preview is a Bog frozen in mid-leap.
	bog.sync_grounded = true
	bog.sync_velocity = Vector3.ZERO
	bog.global_position = at
	# And `sync_position`, or the row collapses into one Bog: a remote body is
	# pulled toward the replicated position every physics tick, and a scene that
	# only set `global_position` set the half that is overwritten.
	bog.sync_position = at
	bog.sync_yaw = yaw
	bog.body_yaw = yaw
	_bogs.append(bog)
	_fractions.append(fraction)

	_write_hold(peer, fraction)
	# The row is written straight into `MatchState` rather than claimed off a
	# real pickup, which is what `combat_range`'s bow mode does one file over
	# and for the same reason: this scene is about what a hold *looks like* and
	# has no interest in how one is started. The signal is the half that
	# matters — `BogCombat._on_letter_hold_changed` is what puts the pouch in
	# the fist, and a row written without it would be a Bog holding nothing.
	MatchState.letter_hold_changed.emit(peer)
	return bog


func _process(_delta: float) -> void:
	if _camera != null:
		_camera.make_current()


func _physics_process(_delta: float) -> void:
	for column: int in _bogs.size():
		var f := _fractions[column]
		if f >= 0.0:
			# Re-stamped every tick rather than written once, because the
			# fraction is derived from a wall clock that does not stop for a
			# preview: the row is slid forward under it so that
			# `letter_hold_fraction` keeps answering the same number while the
			# descent is photographed.
			_write_hold(_bogs[column].peer_id, f)
	_ticks += 1
	if _ticks < SETTLE_TICKS:
		return
	if not _done:
		_done = true
		_aim()
		_report()
		_swing_from = _ticks
		# The knock is the thing both the trace and the sheet are about: in
		# `swing` one bag is hit and watched, and in `sheet` the six are hit on
		# a stagger so that one shutter catches six phases of the same swing.
		# Both are driven below. Every other mode has nothing left to do — and
		# only when there is no window to photograph, because under
		# `snapshot.gd` the scene has to stay up until the grab and snapshot
		# ends the run itself.
		if _mode != "swing" and _mode != "sheet" \
				and DisplayServer.get_name() == "headless":
			get_tree().quit()
		return

	if _mode == "swing":
		_trace_swing()
	elif _mode == "sheet":
		_stagger_knocks()
		if _ticks > SHEET_GRAB_TICK and DisplayServer.get_name() == "headless":
			get_tree().quit()


## Hit every column's bag at its own moment before the shutter, so the row reads
## left to right as one bag swinging and settling.
func _stagger_knocks() -> void:
	for column: int in _bogs.size():
		var when := SHEET_GRAB_TICK - column * SHEET_SWING_STEP
		if _ticks == when:
			_knock(_bogs[column])


## Knock one Bog's bag the way a letter landing in it does — through
## `CaptureRig`'s own constants, not through a number of this tool's, so the
## sheet shows the swing the game shows.
func _knock(bog: Bog) -> void:
	var gear: HeldGear = bog.held_gear
	var rig: CaptureRig = bog.capture_rig
	if gear == null or rig == null:
		return
	gear.nudge_pouch(rig.landing_push())


## The settle, sampled — and it is sampled against a **baseline**, which is the
## whole shape of this check.
##
## A carried bag is never still: the idle breathes, the fist moves with it, and
## the spring answers, which is the life Carl asked for and is a floor under
## every number here. So the trace watches the bag for a second before anything
## happens to it, keeps the worst of that as what the idle alone is worth, and
## only then knocks it. What it then asks is the ticket's sentence rather than
## an absolute angle: the letter landing moved it *more than the idle does*, it
## came back through the other side, and it fell back to the idle's own life by
## the end.
func _trace_swing() -> void:
	var gear: HeldGear = _bogs[0].held_gear
	var since := _ticks - _swing_from
	if since == SWING_BASELINE_TICKS:
		_knock(_bogs[0])
	if since % SWING_EVERY == 0 and gear != null:
		# One signed number rather than two, because the knock is in the plane
		# the letter came down in: the sideways half is a zero being printed.
		var hang := gear.pouch_hang_degrees().x
		if since < SWING_BASELINE_TICKS:
			_idle.append(hang)
		else:
			_swing.append(hang)
			print("preview_capture: swing  +%.2f s  %+6.2f deg off down" % [
				float(since - SWING_BASELINE_TICKS) / Engine.physics_ticks_per_second,
				hang])
	if since < SWING_BASELINE_TICKS + SWING_TICKS:
		return

	var idle := _worst(_idle, 0)
	var peak := _worst(_swing, 0)
	var late := _worst(_swing, _swing.size() - _swing.size() / 3)
	var crossed := false
	for i: int in range(1, _swing.size()):
		if _swing[i] * _swing[i - 1] < 0.0:
			crossed = true
	print("preview_capture: swing  carried %.2f deg, knocked to %.2f deg, back through %s, ended %.2f deg"
		% [idle, peak, "yes" if crossed else "no", late])
	var problems: Array[String] = []
	if peak < idle + SWING_PEAK_MIN:
		problems.append("the letter barely moved the bag")
	if not crossed:
		problems.append("the bag did not swing back")
	if late > idle + SWING_REST_MAX:
		problems.append("the bag had not settled")
	if problems.is_empty():
		print("preview_capture: swing PASS")
	else:
		print("preview_capture: swing FAIL (%s)" % "; ".join(problems))
	if DisplayServer.get_name() == "headless":
		get_tree().quit()


## The furthest off down the bag got, in degrees, over `samples` from `from` on.
static func _worst(samples: Array[float], from: int) -> float:
	var worst := 0.0
	for i: int in range(maxi(from, 0), samples.size()):
		worst = maxf(worst, absf(samples[i]))
	return worst


func _write_hold(peer: int, fraction: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var f := fraction if fraction >= 0.0 else 0.0
	MatchState._letter_holds[peer] = {
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
	var facing := _bog.facing()
	var start := hand + Vector3.UP * CaptureRig.START_LIFT \
		+ facing * CaptureRig.START_AHEAD
	var bow_hand := gear.bow_hand_transform().origin
	var mouth := gear.pouch_mouth_global()
	var card: Vector3 = rig.letter_global()
	var f := MatchState.letter_hold_fraction(_bog.peer_id)

	print("preview_capture: right hand  (%.3f, %.3f, %.3f)" % [hand.x, hand.y, hand.z])
	print("preview_capture: start       (%.3f, %.3f, %.3f)  +%.2f up, %.2f ahead"
		% [start.x, start.y, start.z, CaptureRig.START_LIFT, CaptureRig.START_AHEAD])
	print("preview_capture: left hand   (%.3f, %.3f, %.3f)"
		% [bow_hand.x, bow_hand.y, bow_hand.z])
	print("preview_capture: pouch mouth (%.3f, %.3f, %.3f)  sack bottom at %.3f"
		% [mouth.x, mouth.y, mouth.z, mouth.y - PouchMesh.drop()])
	print("preview_capture: carried     %.3f m ahead, %.3f m off the body axis"
		% [_ahead(mouth), _off_axis(mouth)])
	if card == Vector3.INF:
		print("preview_capture: letter      — nothing drawn")
	else:
		print("preview_capture: letter      (%.3f, %.3f, %.3f)  f=%.2f  scale %.2f"
			% [card.x, card.y, card.z, f, rig.letter_size()])
	print("preview_capture: descent     %.3f m, start to mouth"
		% start.distance_to(mouth))

	# The whole path, sampled off `CaptureRig.descent_point` — the curve's one
	# home, asked rather than reproduced. Three numbers come out of it: the
	# nearest the card ever comes to the Bog's own axis, the furthest it ever
	# drops below the bag, and the furthest it ever gets behind it.
	var nearest := INF
	var under := 0.0
	var behind := 0.0
	for i: int in PATH_SAMPLES + 1:
		var point := CaptureRig.descent_point(
			float(i) / float(PATH_SAMPLES), start, mouth, facing)
		nearest = minf(nearest, _off_axis(point))
		under = maxf(under, mouth.y - point.y)
		behind = maxf(behind, _ahead(mouth) - _ahead(point))
	print("preview_capture: path        nearest the axis %.3f m, %.3f m under the bag, %.3f m behind it"
		% [nearest, under, behind])

	if _mode == "solve":
		_solve(gear, mouth)

	# The structural claims. Each is a thing two or three files have to agree
	# about, and each has been wrong at least once in some prop's history: a
	# hand holding two objects, a hand holding none, a prop hung off the wrong
	# bone, a lerp between anchors read in the wrong order.
	_want("the pouch is in the left fist", gear.has_pouch())
	_want("and the card is not in the right one", not gear.has_letter())
	_want("the pouch clears the grass",
		mouth.y - PouchMesh.drop() > POUCH_CLEARANCE_MIN)
	_want("the mouth is below the start", mouth.y < start.y)
	# D-172's two, and they are the ticket's own sentence: the letter is above
	# and in front of the bag at every frame, and never inside the body.
	_want("the letter stays above and in front of the bag",
		under <= BAG_SLACK and behind <= BAG_SLACK)
	_want("the letter never enters the body", nearest >= BODY_CLEAR_MIN)
	if card == Vector3.INF:
		_want("the letter is drawn", false)

	if _problems.is_empty():
		print("preview_capture: capture PASS")
	else:
		print("preview_capture: capture FAIL (%s)" % "; ".join(_problems))


func _want(claim: String, held: bool) -> void:
	if not held:
		_problems.append(claim)


## How far `point` is along the way the Bog is looking, from the Bog's own
## origin, in metres. Negative is behind it.
func _ahead(point: Vector3) -> float:
	return (point - _bog.global_position).dot(_bog.facing())


## How far `point` is from the Bog's own vertical axis, horizontally. The
## measurement the body is a capsule for: height does not enter into it,
## because a capsule is the same width all the way up the part a letter passes.
func _off_axis(point: Vector3) -> float:
	var span := point - _bog.global_position
	return Vector2(span.x, span.z).length()


## The grip offset that would carry the mouth `CARRY_AHEAD` in front of the
## body, printed for pasting into `HeldGear.POUCH_GRIP_OFFSET`.
##
## Solved rather than swept, and it is a one-line solve: the offset is a point
## in the hand's frame, so the metres wanted in the world go through the hand's
## own basis and come out as metres in that frame. Nothing here is aesthetic —
## how far forward is worth going is `CARRY_AHEAD`'s comment, and the eye
## settles that off the sheet.
func _solve(gear: HeldGear, mouth: Vector3) -> void:
	var fist := gear.bow_hand_transform()
	var want := mouth + _bog.facing() * (CARRY_AHEAD - _ahead(mouth))
	var offset := fist.affine_inverse() * want
	print("preview_capture: solve       POUCH_GRIP_OFFSET := Vector3(%.3f, %.3f, %.3f)"
		% [offset.x, offset.y, offset.z])
	print("preview_capture: solve       for a mouth %.3f m in front of the body axis"
		% CARRY_AHEAD)


# --------------------------------------------------------------- the stage ---

## Aimed after the settle rather than in `_ready`, because two of the three
## framings are aimed at a **bone**, and on the first frame the attachments
## have not been placed yet.
func _aim() -> void:
	var gear: HeldGear = _bog.held_gear
	var look := Vector3(0.0, 1.2, 0.0)
	var eye := Vector3(1.9, 1.5, 2.4)
	# The row's middle and how wide it is, so one pair of framings serves a
	# single Bog and a sheet of six: a sheet is the same two cameras pulled back
	# far enough to hold the row.
	var span := float(_bogs.size() - 1) * SHEET_SPREAD
	var middle := Vector3.ZERO
	var back := 3.1 + span * 0.45
	var facing := _bog.facing()
	match _framing:
		"hand":
			# Aimed off the Bog's own facing since D-172, not off world axes:
			# the start of the descent moved out in front of the body, and a
			# camera parked on +X +Z was a camera behind the shoulder of it.
			# Half way between the fist and the card it is pulling down, which
			# is further than it was: the start moved 0.40 m out in front of the
			# body, so a frame on the wrist alone now cuts the letter in half.
			look = gear.hand_transform().origin.lerp(
				gear.hand_transform().origin + Vector3.UP * CaptureRig.START_LIFT
				+ facing * CaptureRig.START_AHEAD, 0.5)
			eye = look + facing * 2.6 + facing.cross(Vector3.UP) * 1.3 + Vector3.UP * 0.1
		"pouch":
			look = gear.pouch_mouth_global() + Vector3.DOWN * (PouchMesh.drop() * 0.5)
			eye = look + facing * 0.9 + facing.cross(Vector3.UP) * 0.5 + Vector3.UP * 0.25
		"settle":
			# Down on the bags, because that is the whole subject: six of them
			# at six moments of one swing, and a camera framed on bodies would
			# spend the picture on six identical Bogs.
			look = Vector3(0.0, gear.pouch_mouth_global().y + 0.30, 0.0)
			eye = look + Vector3.FORWARD * (back * 0.95) + Vector3.UP * 0.45
		"front", "side":
			# The height is the descent's own middle rather than the Bog's:
			# what these two cameras are for is the letter, which lives above
			# the head at one end of the hold and at the hip at the other.
			#
			# The **side** is the view the path is actually judged in (D-172):
			# a letter that passes through a Bog does it in the plane the Bog is
			# facing along, and head-on that plane is a line. On a sheet the
			# camera is the same in both and it is the Bogs that turn (see
			# `SHEET_SIDE_YAW`), because a row cannot be photographed end-on.
			look = middle + Vector3.UP * 1.25
			var from := facing
			if _mode == "sheet":
				from = Vector3.FORWARD
			elif _framing == "side":
				from = facing.cross(Vector3.UP)
			eye = look + from * back
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
	# Wide enough for whichever scene this is: a row of six needs floor under
	# all of them, and a floor that stopped half way along would read as a
	# lighting fault rather than as a plane running out.
	var wide := 12.0
	if _mode == "sheet":
		wide += float(SHEET_FRACTIONS.size()) * SHEET_SPREAD * 2.0
	plane.size = Vector2(wide, wide)
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
