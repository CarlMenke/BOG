extends Node
## One frozen grip pose per hand per prop, stolen off the clips that already
## draw it (the letters round). Development tool, not shipped.
##
##   Godot --headless --path . tools/grip_poses.tscn
##
## A scene and not a `--script`, unlike `clip_check.gd`: it reads its tables off
## `BogAnimator`, whose dependency chain (`HeldGear` → `Pickup` → `Net`) names
## the autoloads, and a `SceneTree` script runs without them and cannot compile
## it. `invite_codes.tscn` is the same shape for the same reason.
##
## **Run it after the import**, and **commit what it writes.** What it reads,
## `art/generated/bog_clips.res`, is written by `tools/import_clip.gd` during
## the import pass, so a run before that reads yesterday's library; what it
## writes, `art/generated/grip_poses.res`, is loaded by `BogAnimator` at
## runtime, so a checkout without it is a Bog whose fingers stay in whatever
## pose the body clip left them in. Neither file is derived at load time by
## anything else and neither is gitignored.
##
## The owner: *"one grip pose per prop, not per clip; the finger bones get a
## single frozen pose while the prop is held, layered over whatever the body
## clip is doing … author it once by stealing it from a clip where the hand is
## closed."* This is the stealing, and it is a build step rather than a
## hand-authored resource for D-095's reason read one more time: the pose is a
## *measurement of a clip*, so a re-imported clip has to be able to re-measure
## it without anybody opening a modelling tool.
##
## Five poses, because the hand rule is "one thing per hand" (D-065) and the
## two hands do not hold the same things: the right closes on a shaft, a hilt
## or an arrow and is otherwise open; the left hooks a bow, closes on a potion
## or a pouch, and is otherwise open. Which poses each hand has is
## `BogAnimator.GRIP_POSES`, and the twelve bones of a mitten are
## `BogAnimator.finger_bones()` — read from there rather than re-typed here, so
## this cannot write a pose the layer never asks for, miss one it does, or lose
## a digit the rig grows (D-098).

const LIBRARY := "res://art/generated/bog_clips.res"
const OUT := BogAnimator.GRIP_LIBRARY

## How long a pose is, in seconds. A single key at 0.0 in a looping clip is a
## constant whatever the length, so this is only "short enough that nothing can
## be tempted to scrub it": the layer plays these the way it plays a carry
## idle, and there is nothing inside one to reach.
const POSE_LENGTH := 0.05

## Half a second into a looping carry idle. Past the first frame, which is the
## one frame of a Mixamo take most likely to be still holding the rest pose,
## and inside the shortest carry clip in the library several times over.
const CARRY_SAMPLE := 0.5

## The articulated joints of a three-digit mitten: three per finger. The three
## `*4` fingertip leaves carry no track in any clip and are not counted.
const MIN_TRACKS := 9


## Where one pose is stolen from, as [clip role, time in the clip], and empty
## for a pose nothing here knows how to make.
##
## The fist is `SwordCarry`'s at *both* hands: the great sword is the one prop
## held in two closed fists, so a single clip authors both sides of a closed
## hand and the two measure the same closure by construction. The hook is
## `BowCarry`'s left, the only hand in the library wrapped round a riser
## instead of round a shaft. The open hand is `Idle`'s first frame, which is
## the Bog's own resting hand and the pose all of these relax back into.
static func _source(pose: String) -> Array:
	if pose == BogAnimator.GRIP_FIST:
		return ["SwordCarry", CARRY_SAMPLE]
	if pose == BogAnimator.GRIP_HOOK:
		return ["BowCarry", CARRY_SAMPLE]
	if pose == BogAnimator.GRIP_OPEN:
		return ["Idle", 0.0]
	return []


var _failures := 0
## Which hands have already had their untracked leaves noted, so the note is
## printed once per hand rather than once per pose.
var _noted_missing := {}


func _ready() -> void:
	var lib := load(LIBRARY) as AnimationLibrary
	if lib == null:
		_fail("the clip library %s does not load" % LIBRARY)
		_done()
		return

	# The prefix the body's own tracks are written under, read off a track
	# rather than typed, exactly as `BogAnimator._find_skeleton_track_prefix`
	# reads it: these poses are played through the same AnimationPlayer, and a
	# pose whose paths did not match the clips' would land on nothing at all
	# and do it quietly.
	var prefix := _track_prefix(lib)
	if prefix.is_empty():
		_fail("no skeleton tracks in %s to read the path prefix off" % LIBRARY)
		_done()
		return

	var out := AnimationLibrary.new()
	var tracks := -1
	var poses := 0
	# The open hand of each side, kept to measure the closed ones against: a
	# mitten whose fingers never move would otherwise write five identical
	# poses and pass. `open` is first in `GRIP_POSES` for this and for the
	# graph's own reason, so it is always in here by the time it is wanted.
	var open_hand := {}
	print("%-12s %-12s %7s %7s %10s" % ["pose", "from", "at", "tracks", "off open"])
	for side: String in BogAnimator.GRIP_POSES:
		var bones := BogAnimator.finger_bones(side)
		if bones.size() != BogAnimator.FINGER_BONES_PER_HAND:
			_fail("the %s hand has %d finger bones, not %d"
				% [side, bones.size(), BogAnimator.FINGER_BONES_PER_HAND])
			continue
		for pose: String in BogAnimator.GRIP_POSES[side]:
			var source := _source(pose)
			if source.is_empty():
				_fail("no source clip for the '%s' pose" % pose)
				continue
			var role: String = source[0]
			if not lib.has_animation(role):
				_fail("the clip library has no '%s', which '%s' is stolen from"
					% [role, BogAnimator.grip_pose_name(pose, side)])
				continue
			var src := lib.get_animation(role)
			# A clip shorter than the sample time is not a failure — it is a
			# shorter take of the same idle — but the time it was actually read
			# at is printed, because the last frame of a loop is the first one.
			var at := minf(float(source[1]), src.length)
			var sampled := _sample(src, prefix, bones, at)
			var used: Array[String] = sampled["bones"]
			var rotations: Array[Quaternion] = sampled["rotations"]
			# The `*4` bones are the mitten's fingertip leaves and Mixamo writes
			# no track for a leaf: three per hand come back empty on every clip
			# in the library, and a pose that skips them loses nothing — a leaf
			# has no child to turn. Fewer than the nine articulated joints is a
			# different thing, and fails.
			if rotations.size() < MIN_TRACKS:
				_fail("'%s' has rotation tracks for only %d of the %s hand's finger bones"
					% [role, rotations.size(), side])
				continue
			if not sampled["missing"].is_empty() and not _noted_missing.has(side):
				_noted_missing[side] = true
				print("  note  %s hand: no track for %s (fingertip leaves, skipped)"
					% [side, ", ".join(sampled["missing"])])
			var pose_name := BogAnimator.grip_pose_name(pose, side)
			out.add_animation(pose_name, _pose(prefix, used, rotations, pose_name))
			poses += 1
			tracks = rotations.size() if tracks < 0 else tracks
			if pose == BogAnimator.GRIP_OPEN:
				open_hand[side] = rotations
			print("%-12s %-12s %7.3f %7d %10s" % [pose_name, role, at, rotations.size(),
				"--" if pose == BogAnimator.GRIP_OPEN
				else "%.1f deg" % _mean_degrees(rotations, open_hand.get(side, []))])

	if _failures == 0:
		var err := ResourceSaver.save(out, OUT)
		if err != OK:
			_fail("could not save %s (%d)" % [OUT, err])
		else:
			print("grip_poses: wrote %s — commit it" % OUT)
	print("grip_poses: %d poses, %d tracks each" % [poses, maxi(tracks, 0)])
	_done()


## The `<skeleton path>` every track in the library is written under, which is
## `Skeleton3D` on today's body.
static func _track_prefix(lib: AnimationLibrary) -> String:
	for key in lib.get_animation_list():
		var anim := lib.get_animation(key)
		for t in anim.get_track_count():
			var path := String(anim.track_get_path(t))
			if path.contains(":"):
				return path.get_slice(":", 0)
	return ""


## One hand's rotations out of `src` at `at`: `bones` and `rotations` in step,
## for the bones the clip carries a rotation track for, and `missing` naming the
## ones it does not (the fingertip leaves, on every Mixamo take).
static func _sample(src: Animation, prefix: String, bones: Array[String],
		at: float) -> Dictionary:
	var used: Array[String] = []
	var rotations: Array[Quaternion] = []
	var missing: Array[String] = []
	for bone in bones:
		var track := src.find_track(NodePath("%s:%s" % [prefix, bone]),
			Animation.TYPE_ROTATION_3D)
		if track < 0:
			missing.append(bone.trim_prefix("mixamorig_"))
			continue
		used.append(bone)
		rotations.append(src.rotation_track_interpolate(track, at))
	return {"bones": used, "rotations": rotations, "missing": missing}


## One pose: one rotation track per articulated finger joint, a single key each, on the same bone
## paths the body's own clips use. Looping and not a one-frame `LOOP_NONE`,
## because an `AnimationNodeAnimation` that reaches its last frame stops there
## for the rest of the round (D-026) and the layer above this has to hold the
## pose for as long as the prop is held.
static func _pose(prefix: String, bones: Array[String], rotations: Array[Quaternion],
		pose_name: String) -> Animation:
	var anim := Animation.new()
	anim.resource_name = pose_name
	anim.length = POSE_LENGTH
	anim.loop_mode = Animation.LOOP_LINEAR
	for i in bones.size():
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath("%s:%s" % [prefix, bones[i]]))
		anim.rotation_track_insert_key(track, 0.0, rotations[i])
	return anim


## How far one pose is from another, averaged over the hand, in degrees. The
## number that says the fingers in these clips actually move.
static func _mean_degrees(a: Array, b: Array) -> float:
	if a.size() != b.size() or a.is_empty():
		return 0.0
	var total := 0.0
	for i in a.size():
		var one: Quaternion = a[i]
		total += rad_to_deg(one.angle_to(b[i]))
	return total / float(a.size())


func _fail(why: String) -> void:
	_failures += 1
	print("  FAIL  %s" % why)


func _done() -> void:
	print("grip_poses: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)
