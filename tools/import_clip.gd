@tool
extends EditorScenePostImport
## One Mixamo clip in, one game-ready Animation out. Runs inside Godot's own
## importer on every `assets/source/anims/*.fbx` (set as `import_script/path`
## in each file's `.import`), so a re-import *is* the build: there is no Blender
## and no separate build step (D-095).
##
## For the clip it is handed, this
##   1. records the authored travel of the hips (distance and bearing over the
##      clip, and the speed that implies), as metadata on the Animation;
##   2. turns the clip onto the body's forward the way its table row says
##      (`face`: square the hip line, square the chest line, or leave the
##      authored frame alone), by yawing the hips' keys (D-097);
##   2a. squares the top of the body over its own hips when the row says
##      `untwist`, by counter-rotating `Spine1` and `Neck` about the body's
##      vertical -- the part of a stance the `face` yaw cannot reach, and the
##      only part of it an upper-body layer copies;
##   3. locks the hips to the skeleton's vertical axis, so the clip plays in
##      place and the physics body does the moving;
##   4. sets the loop mode and writes the event markers from the clip table;
##   5. saves it to `art/generated/clips/<file>.res` and files it in the shared
##      library `art/generated/bog_clips.res` under its role;
##   6. builds any clip the table says is this one's reflection (`mirror_of`,
##      D-071) and files that the same way — a mirrored row has no file of its
##      own, so the two halves of an axis are one motion by construction.
##
## The clip table, `assets/source/clips.json`, is the single source of
## truth for what a file is: its role, whether it loops, how it faces, where
## its events are. A file the table does not know is imported but not shipped,
## and says so.
##
## Every clip was fetched on the BOG's own Mixamo rig, so its skeleton is the
## body's skeleton bone for bone and the tracks retarget by name with no map
## (verified 2026-09-16, `assets/source/README.md`).

const TABLE := "res://assets/source/clips.json"
const CLIP_DIR := "res://art/generated/clips/"
const LIBRARY := "res://art/generated/bog_clips.res"
const HIPS := "mixamorig_Hips"
## The two lines a clip's facing is read off, as (left bone, right bone).
const LINES := {
	"hips": ["mixamorig_LeftUpLeg", "mixamorig_RightUpLeg"],
	"chest": ["mixamorig_LeftShoulder", "mixamorig_RightShoulder"],
}
const FACING_SAMPLES := 12
## The two joints `untwist` turns, and what each of them carries. The layered
## chain is `Spine1` to `Spine2` to `Neck` to `Head`, plus the arms off
## `Spine2`, and it bends at two places that can turn independently: the chest
## (the shoulder line, and the arms with it) and the head on top of it. One
## correction cannot square both -- an archer idle is square at the shoulders
## and looking sixty degrees off -- so `untwist` is two, the chest's at the
## first bone of the chain and the head's at the first bone above the
## shoulders.
const UNTWIST_CHEST := "mixamorig_Spine1"
const UNTWIST_HEAD := "mixamorig_Neck"
const HEAD := "mixamorig_Head"


func _post_import(scene: Node) -> Object:
	var file := get_source_file().get_file().get_basename()
	var table := _read_table()
	var row := _row_for(file, table)
	if row.is_empty():
		push_warning("import_clip: %s is not in clips.json; imported, not shipped" % file)
		return scene

	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := scene.find_child("Skeleton3D", true, false) as Skeleton3D
	if player == null or skeleton == null or player.get_animation_list().size() != 1:
		push_error("import_clip: %s should carry one animation and one skeleton" % file)
		return scene
	var anim := player.get_animation(player.get_animation_list()[0]).duplicate(true) as Animation

	var tracks := _tracks_by_bone(anim)
	if not tracks.has(HIPS) or tracks[HIPS].pos < 0 or tracks[HIPS].rot < 0:
		push_error("import_clip: %s has no %s tracks" % [file, HIPS])
		return scene
	var hips: int = tracks[HIPS].pos

	# Travel is first key to last, on the ground plane. For a cycle that is one
	# stride's worth, and travel over length is the speed the animator was
	# walking at when it was authored — the number the animator divides the game
	# speed by so the feet plant (D-029).
	var keys := anim.track_get_key_count(hips)
	var first: Vector3 = anim.track_get_key_value(hips, 0)
	var last: Vector3 = anim.track_get_key_value(hips, keys - 1)
	var travel := Vector3(last.x - first.x, 0.0, last.z - first.z)

	# Facing. Mixamo authors the world's forward and lets the actor's stance
	# turn, so a clip's hip line can sit 40° off the rest pose while its travel
	# is dead straight. Yawing the hips' keys turns the whole body; the table
	# says which line to square, per family (D-097).
	var fix_deg := 0.0
	var face: String = row.get("face", "hips")
	if LINES.has(face):
		fix_deg = -_line_yaw(anim, skeleton, tracks, LINES[face])
		var fix := Quaternion(Vector3.UP, deg_to_rad(fix_deg))
		var rot: int = tracks[HIPS].rot
		for k in anim.track_get_key_count(rot):
			anim.track_set_key_value(rot, k, fix * (anim.track_get_key_value(rot, k) as Quaternion))
		travel = fix * travel

	# The twist. `face` turns the hips and everything above them together, so it
	# cannot change how far the chest and the head are turned off the *hips* --
	# that lives in the spine chain's own local rotations, which is exactly what
	# an upper-body layer copies and nothing of what it leaves behind. A carry
	# clip authored side-on therefore lands its turned chest and its looking-away
	# head on top of every base pose the legs are in. Squaring it here means the
	# clip owns its posture and neither the animator nor the aim code has to.
	#
	# Only for a layer that sits over a *square* base: the carry layer does (the
	# plain plane faces the crosshair), the draw layer over the archer's plane
	# does not, and untwisting that one would point the head out sideways.
	var twist := Vector2.ZERO
	if row.get("untwist", false):
		twist = _twist_yaw(anim, skeleton, tracks)
		_untwist(anim, skeleton, tracks, UNTWIST_CHEST, twist.x, file)
		_untwist(anim, skeleton, tracks, UNTWIST_HEAD, twist.y, file)

	var low := INF
	var high := -INF
	for k in keys:
		var p: Vector3 = anim.track_get_key_value(hips, k)
		low = minf(low, p.y)
		high = maxf(high, p.y)
		# Lock to the axis, not to the first key: a clip authored a hand's width
		# off centre would otherwise play a hand's width off the capsule.
		anim.track_set_key_value(hips, k, Vector3(0.0, p.y, 0.0))

	anim.loop_mode = Animation.LOOP_LINEAR if row.get("loop", false) else Animation.LOOP_NONE
	for marker in row.get("markers", {}):
		var at := float(row.markers[marker])
		if at < 0.0 or at > anim.length:
			push_error("import_clip: %s marker '%s' at %.3f is outside 0..%.3f" % [file, marker, at, anim.length])
			continue
		anim.add_marker(marker, at)

	anim.resource_name = file
	anim.set_meta("role", row.get("role", ""))
	anim.set_meta("travel", travel)
	anim.set_meta("authored_speed", travel.length() / anim.length if anim.length > 0.0 else 0.0)
	anim.set_meta("bearing", rad_to_deg(Vector3.FORWARD.signed_angle_to(-travel, Vector3.UP)) if travel.length() > 0.05 else 0.0)
	anim.set_meta("hips_bob", high - low)
	anim.set_meta("facing_fix", fix_deg)
	anim.set_meta("untwist", twist)
	anim.set_meta("start_offset", Vector3(first.x, 0.0, first.z))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CLIP_DIR))
	var clip_path := CLIP_DIR + file + ".res"
	var err := ResourceSaver.save(anim, clip_path)
	if err != OK:
		push_error("import_clip: could not save %s (%d)" % [clip_path, err])
		return scene
	# Saving does not give the resource its path; taking it over does, and that
	# is what makes the library reference the file rather than swallow a copy.
	anim.take_over_path(clip_path)
	_file_in_library(file, table, anim)
	print("import_clip: %-52s %6.3f s  %.3f m/s  bob %.3f  face %+6.1f°  twist %+5.1f/%+5.1f°  %d markers  %s" % [
		file, anim.length, anim.get_meta("authored_speed"), high - low, fix_deg,
		twist.x, twist.y,
		anim.get_marker_names().size(), "loop" if anim.loop_mode != Animation.LOOP_NONE else "once"])

	# And any clip the table says is this one's reflection (D-071, D-098). A
	# mirrored row has no FBX of its own, so it is built here, off the clip that
	# has just been saved and after everything that was done to it — the two
	# halves of an axis are then the same move by construction instead of by
	# download, and a re-import of the source rebuilds both together.
	for other: Dictionary in table.rows.values():
		if String(other.get("mirror_of", "")) == String(row.get("role", "")):
			_mirror_into(other, anim, skeleton, table)
	return scene


# ------------------------------------------------------------------ mirror ---

## Build the row's clip as the left-to-right reflection of `source`, and file it
## exactly as a downloaded one (D-071 named this `mirror_of` and D-098 asked for
## it here). Mixamo has no true lateral *right* clip and never will — its strafe
## families are authored round a chest turned to the actor's own right, so every
## right strafe in every pack is a -37 to -47 degree diagonal while its left twin
## ranges from +27 to +126 (D-071 measured three downloads to find that out).
## A pole that has to mean -90 is therefore built, not fetched.
##
## The plane is the rig's own sagittal plane, fitted rather than assumed: the
## normal is the **rest** body line the row's `face` names, so a rest pose that
## is rebuilt moves the reflection with it rather than leaving it measuring
## against a remembered axis.
##
## Which line, and not always the hips, is the whole of why the mirror lands
## square. The BOG's rest shoulder line sits 0.4° off square to its rest hip
## line — a real asymmetry in the mesh, not a measurement — so a strafe squared
## on its chest and then reflected in the *hip* plane comes back 0.8° off the
## chest, which is inside `clip_check`'s one degree and only just. Reflected in
## the plane its own `face` rule squares to, a squared clip reflects to a
## squared clip exactly, and the travel bearing reflects exactly with it.
##
## The reflection is taken in world space and pushed back down into the tracks,
## rather than negated key by key in each bone's own frame. A bone's keys are in
## its parent's frame and the left and right rests are reflections of each other
## rather than copies, so a per-key negation is only correct on a rig whose every
## joint frame happens to be mirror-symmetric; forward kinematics out, reflect,
## and inverse-kinematics back in is correct on any rig and costs one FK pass per
## distinct key time.
func _mirror_into(row: Dictionary, source: Animation, skeleton: Skeleton3D,
		table: Dictionary) -> void:
	var file: String = row.get("file", "")
	var anim := source.duplicate(true) as Animation
	var tracks := _tracks_by_bone(anim)
	var rest := _positions(source, skeleton, tracks, -1.0)
	var line: Array = LINES.get(row.get("face", "hips"), LINES.hips)
	var plane := _flat(rest[skeleton.find_bone(line[0])] - rest[skeleton.find_bone(line[1])])
	var reflect := _reflection(plane)
	# Which bone each bone takes its pose from: its twin across the plane, or
	# itself for the spine, the head and the hips.
	var twin := PackedInt32Array()
	for b in skeleton.get_bone_count():
		var other := skeleton.find_bone(_twin_bone(skeleton.get_bone_name(b)))
		twin.append(other if other >= 0 else b)

	# One forward-kinematics pass per distinct key time, shared by every track
	# that has a key there — which on a Mixamo clip is all of them, because the
	# export is baked at one rate.
	var posed := {}
	for bone: String in tracks:
		var b := skeleton.find_bone(bone)
		if b < 0:
			continue
		var parent := skeleton.get_bone_parent(b)
		for kind: String in ["pos", "rot"]:
			var track: int = tracks[bone][kind]
			if track < 0:
				continue
			for k in anim.track_get_key_count(track):
				var t := anim.track_get_key_time(track, k)
				if not posed.has(t):
					posed[t] = _world(source, skeleton, tracks, t)
				var world: Array[Transform3D] = posed[t]
				var here := _reflect(world[twin[b]], reflect)
				var local := here if parent < 0 \
					else _reflect(world[twin[parent]], reflect).affine_inverse() * here
				if kind == "pos":
					anim.track_set_key_value(track, k, local.origin)
				else:
					anim.track_set_key_value(track, k, local.basis.get_rotation_quaternion())

	# A reflection swaps which foot is which, and that is not only a renaming:
	# **every Mixamo cycle starts on a right-foot plant** (D-097 measured it on
	# 22 of 24), so a reflected one starts on a left-foot plant and is half a
	# stride out of phase with every other cycle in its plane. The blend space
	# feels that on the diagonals, where a strafe is mixed with a walk or a run:
	# the walk-forward-right leg slid 0.37 of body speed against the downloaded
	# right strafe and 0.94 against an unrolled reflection of the left one.
	#
	# So the reflection is rolled round its own loop until it starts on a right
	# plant again, and where that is, is derived rather than typed: the mirror's
	# right foot *is* the source's left, so the roll is the source's own
	# `step_left`. Sampled rather than re-timed key by key, because the importer
	# does not leave every track on one grid and the roll has to leave a closed
	# loop behind it whatever grid it found.
	_roll(anim, _step_roll(source))

	# The row's own loop and markers, not the source's: after the reflection and
	# the roll the feet have traded places and moved, and the table is where that
	# is written down (D-097).
	for marker in anim.get_marker_names():
		anim.remove_marker(marker)
	anim.loop_mode = Animation.LOOP_LINEAR if row.get("loop", false) else Animation.LOOP_NONE
	for marker in row.get("markers", {}):
		var at := float(row.markers[marker])
		if at < 0.0 or at > anim.length:
			push_error("import_clip: %s marker '%s' at %.3f is outside 0..%.3f" % [file, marker, at, anim.length])
			continue
		anim.add_marker(marker, at)

	var travel: Vector3 = reflect * (source.get_meta("travel", Vector3.ZERO) as Vector3)
	anim.resource_name = file
	anim.set_meta("role", row.get("role", ""))
	anim.set_meta("travel", travel)
	anim.set_meta("authored_speed", source.get_meta("authored_speed", 0.0))
	anim.set_meta("bearing", rad_to_deg(Vector3.FORWARD.signed_angle_to(-travel, Vector3.UP)) if travel.length() > 0.05 else 0.0)
	anim.set_meta("hips_bob", source.get_meta("hips_bob", 0.0))
	anim.set_meta("facing_fix", -float(source.get_meta("facing_fix", 0.0)))
	anim.set_meta("untwist", -(source.get_meta("untwist", Vector2.ZERO) as Vector2))
	anim.set_meta("start_offset", reflect * (source.get_meta("start_offset", Vector3.ZERO) as Vector3))

	var clip_path := CLIP_DIR + file + ".res"
	var err := ResourceSaver.save(anim, clip_path)
	if err != OK:
		push_error("import_clip: could not save %s (%d)" % [clip_path, err])
		return
	anim.take_over_path(clip_path)
	_file_in_library(file, table, anim)
	print("import_clip: %-52s %6.3f s  %.3f m/s  bob %.3f  mirror of %-18s %d markers  %s" % [
		file, anim.length, anim.get_meta("authored_speed"), anim.get_meta("hips_bob"),
		source.get_meta("role", ""), anim.get_marker_names().size(),
		"loop" if anim.loop_mode != Animation.LOOP_NONE else "once"])


## The matrix that reflects in the plane through the origin with unit normal
## `n`: `I - 2nn'`. Improper, so a rotation conjugated by it — `M B M` — comes
## back proper, which is what makes `_reflect` a rigid transform again.
static func _reflection(n: Vector3) -> Basis:
	return Basis(
		Vector3(1.0 - 2.0 * n.x * n.x, -2.0 * n.x * n.y, -2.0 * n.x * n.z),
		Vector3(-2.0 * n.y * n.x, 1.0 - 2.0 * n.y * n.y, -2.0 * n.y * n.z),
		Vector3(-2.0 * n.z * n.x, -2.0 * n.z * n.y, 1.0 - 2.0 * n.z * n.z))


## How far a reflection of `source` has to be rolled to start on a right-foot
## plant again: the source's own `step_left`. Zero for anything that is not a
## marked locomotion cycle, which is the honest answer — there is no stride to
## be out of phase with.
static func _step_roll(source: Animation) -> float:
	if source.loop_mode == Animation.LOOP_NONE or not source.has_marker("step_left"):
		return 0.0
	return source.get_marker_time("step_left")


## Turn a looping clip `by` seconds round its own loop, in place: what was at
## `by` is at 0 afterwards.
##
## Every key is resampled rather than re-timed, and two extra samples are taken
## at 0 and at the length. Re-timing alone would be enough on a clip whose
## tracks all sit on one grid with a closing key, and the importer's own key
## reduction means not every clip is one (`StrafeWalkLeft` has 33 hip keys in
## 0.933 s and its last does not repeat its first). Sampling costs nothing here
## — the values come off the track the engine is about to throw away — and it
## leaves a closed loop behind whatever it found, because the sample at the
## length and the sample at 0 are the same instant of the cycle.
static func _roll(anim: Animation, by: float) -> void:
	var length := anim.length
	if by <= 0.0 or length <= 0.0:
		return
	for t in anim.get_track_count():
		var kind := anim.track_get_type(t)
		if kind != Animation.TYPE_POSITION_3D and kind != Animation.TYPE_ROTATION_3D:
			continue
		var times := PackedFloat32Array([0.0, length])
		for k in anim.track_get_key_count(t):
			times.append(fposmod(anim.track_get_key_time(t, k) - by, length))
		times.sort()
		# Every value before any key is removed: once the keys are gone there is
		# nothing left to interpolate.
		var values := []
		for s in times:
			var at := fposmod(s + by, length)
			values.append(anim.position_track_interpolate(t, at) if kind == Animation.TYPE_POSITION_3D
				else anim.rotation_track_interpolate(t, at))
		for k in range(anim.track_get_key_count(t) - 1, -1, -1):
			anim.track_remove_key(t, k)
		for i in times.size():
			if i > 0 and times[i] - times[i - 1] < 1e-5:
				continue
			anim.track_insert_key(t, times[i], values[i])


static func _reflect(t: Transform3D, m: Basis) -> Transform3D:
	return Transform3D((m * t.basis * m).orthonormalized(), m * t.origin)


## A bone's twin across the plane, by the way Mixamo spells the side, and the
## bone's own name when it has no twin.
static func _twin_bone(bone: String) -> String:
	if bone.contains("Left"):
		return bone.replace("Left", "Right")
	if bone.contains("Right"):
		return bone.replace("Right", "Left")
	return bone


## Mean yaw of a body line (left bone to right bone) over the clip, in degrees
## off the same line in the rest pose, + to the BOG's left. Forward kinematics
## from the tracks themselves: nothing here is in a scene tree yet.
static func _line_yaw(anim: Animation, skeleton: Skeleton3D, tracks: Dictionary, line: Array) -> float:
	var left := skeleton.find_bone(line[0])
	var right := skeleton.find_bone(line[1])
	var rest := _positions(anim, skeleton, tracks, -1.0)
	var rest_line := _flat(rest[left] - rest[right])
	var mean := Vector3.ZERO
	for i in FACING_SAMPLES:
		var pos := _positions(anim, skeleton, tracks, anim.length * (float(i) + 0.5) / FACING_SAMPLES)
		mean += _flat(pos[left] - pos[right])
	return rad_to_deg(rest_line.signed_angle_to(_flat(mean), Vector3.UP))


## How far the chest is turned off the hips, and the head off the chest, as the
## mean over the clip in degrees, + to the BOG's left: `(chest, head)`. Both are
## zero in the rest pose, so the pair is what `untwist` has to take away.
##
## A plain mean of two subtracted yaws rather than a mean of vectors, because the
## quantity is a difference of angles and not an angle; every clip this is asked
## of sits well inside a right angle of square, where the two are the same
## number.
static func _twist_yaw(anim: Animation, skeleton: Skeleton3D, tracks: Dictionary) -> Vector2:
	var hip := [skeleton.find_bone(LINES.hips[0]), skeleton.find_bone(LINES.hips[1])]
	var chest := [skeleton.find_bone(LINES.chest[0]), skeleton.find_bone(LINES.chest[1])]
	var head := skeleton.find_bone(HEAD)
	var rest := _world(anim, skeleton, tracks, -1.0)
	var rest_hip := _flat(rest[hip[0]].origin - rest[hip[1]].origin)
	var rest_chest := _flat(rest[chest[0]].origin - rest[chest[1]].origin)
	var rest_head: Basis = rest[head].basis
	var sum := Vector2.ZERO
	for i in FACING_SAMPLES:
		var w := _world(anim, skeleton, tracks, anim.length * (float(i) + 0.5) / FACING_SAMPLES)
		var hip_yaw := rad_to_deg(rest_hip.signed_angle_to(_flat(w[hip[0]].origin - w[hip[1]].origin), Vector3.UP))
		var chest_yaw := rad_to_deg(rest_chest.signed_angle_to(_flat(w[chest[0]].origin - w[chest[1]].origin), Vector3.UP))
		# The head has no second bone that is not straight above it, so its turn is
		# read off its own basis rather than off a pair of points.
		var turn: Basis = w[head].basis * rest_head.inverse()
		var head_yaw := rad_to_deg(Vector3.RIGHT.signed_angle_to(_flat(turn * Vector3.RIGHT), Vector3.UP))
		sum += Vector2(chest_yaw - hip_yaw, head_yaw - chest_yaw)
	return sum / FACING_SAMPLES


## Turn one bone of the spine chain `degrees` back about the body's vertical, on
## every key it has, the way the facing yaw turns the hips.
##
## A bone's keys are in its **parent's** frame, so a constant `Q` applied to them
## turns the bone in the world by `P * Q * P^-1` — a rotation about `P * axis`.
## For that to be the world's up, the axis has to be the world's up seen from the
## parent, and the parent to use is the one the clip actually holds: the mean
## over the clip of `P^-1 * up`. The rest pose's own was tried first and left 7
## and 9 degrees on the two carry idles, because a standing Bog leans its spine
## about ten degrees forward and a turn about a leaning axis is not a yaw.
##
## Two consequences worth naming. The hips' own yaw drops out — `P^-1 * up` is
## unchanged by any rotation of `P` about up — so a clip left side-on by
## `face: none` takes the same constant as a squared one, and the chest's
## correction does not disturb the head's axis either, which is why these two
## are one pass and not a solve.
static func _untwist(anim: Animation, skeleton: Skeleton3D, tracks: Dictionary,
		bone: String, degrees: float, file: String) -> void:
	if not tracks.has(bone) or tracks[bone].rot < 0:
		push_error("import_clip: %s has no %s rotation track to untwist" % [file, bone])
		return
	var parent := skeleton.get_bone_parent(skeleton.find_bone(bone))
	var axis := Vector3.ZERO
	for i in FACING_SAMPLES:
		var w := _world(anim, skeleton, tracks, anim.length * (float(i) + 0.5) / FACING_SAMPLES)
		axis += (w[parent].basis as Basis).inverse() * Vector3.UP
	axis = axis.normalized()
	var fix := Quaternion(axis, deg_to_rad(-degrees))
	var rot: int = tracks[bone].rot
	for k in anim.track_get_key_count(rot):
		anim.track_set_key_value(rot, k, fix * (anim.track_get_key_value(rot, k) as Quaternion))


## Every bone's position at time `t`, or in the rest pose when `t` is negative.
static func _positions(anim: Animation, skeleton: Skeleton3D, tracks: Dictionary, t: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for w in _world(anim, skeleton, tracks, t):
		out.append(w.origin)
	return out


## Every bone's world transform at time `t`, or in the rest pose when `t` is
## negative. Forward kinematics from the tracks themselves: nothing is in a scene
## tree during an import, so the skeleton's own global-pose cache is cold.
static func _world(anim: Animation, skeleton: Skeleton3D, tracks: Dictionary, t: float) -> Array[Transform3D]:
	var world: Array[Transform3D] = []
	for b in skeleton.get_bone_count():
		var local := skeleton.get_bone_rest(b)
		var name := skeleton.get_bone_name(b)
		if t >= 0.0 and tracks.has(name):
			if tracks[name].pos >= 0:
				local.origin = anim.position_track_interpolate(tracks[name].pos, t)
			if tracks[name].rot >= 0:
				local.basis = Basis(anim.rotation_track_interpolate(tracks[name].rot, t))
		var parent := skeleton.get_bone_parent(b)
		world.append(local if parent < 0 else world[parent] * local)
	return world


static func _tracks_by_bone(anim: Animation) -> Dictionary:
	var out := {}
	for t in anim.get_track_count():
		var path := anim.track_get_path(t)
		if path.get_subname_count() != 1:
			continue
		var bone := path.get_subname(0)
		if not out.has(bone):
			out[bone] = {"pos": -1, "rot": -1}
		match anim.track_get_type(t):
			Animation.TYPE_POSITION_3D: out[bone].pos = t
			Animation.TYPE_ROTATION_3D: out[bone].rot = t
	return out


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()


## The library is keyed by role once a role has one file, and by file while it
## still has candidates, so the animator can ask for `Run` and a preview can
## still tell `Run-StandardRunning` from `Run-RunningForward-1`. Entries whose
## clip file has gone are dropped, so deleting a candidate is enough.
func _file_in_library(file: String, table: Dictionary, anim: Animation) -> void:
	var lib: AnimationLibrary = load(LIBRARY) if ResourceLoader.exists(LIBRARY) else null
	if lib == null:
		lib = AnimationLibrary.new()
	for key in lib.get_animation_list():
		var held := lib.get_animation(key)
		var gone := held == null or not FileAccess.file_exists(held.resource_path)
		if gone or held.resource_path == anim.resource_path:
			lib.remove_animation(key)
	lib.add_animation(_library_key(file, table), anim)
	var err := ResourceSaver.save(lib, LIBRARY)
	if err != OK:
		push_error("import_clip: could not save %s (%d)" % [LIBRARY, err])


static func _library_key(file: String, table: Dictionary) -> String:
	var row := _row_for(file, table)
	var role: String = row.get("role", file)
	if table.per_role.get(role, 0) != 1:
		return file
	# A search row (`mixamo_query`) is one row for however many takes are on
	# disk, so the table cannot count its candidates; the directory can.
	if row.has("mixamo_query") and _candidates_on_disk(row["file"]) > 1:
		return file
	return role


## How many fetched takes a search row has in `assets/source/anims/`.
static func _candidates_on_disk(prefix: String) -> int:
	var n := 0
	for name in DirAccess.get_files_at("res://assets/source/anims"):
		if name.get_extension() == "fbx" and (name.get_basename() == prefix or name.begins_with(prefix + "-")):
			n += 1
	return n


## A row fetched by search (`mixamo_query`) lands as `<file>-<Mixamo name>`, so
## its file is a prefix of the file on disk rather than the whole of it.
static func _row_for(file: String, table: Dictionary) -> Dictionary:
	if table.rows.has(file):
		return table.rows[file]
	for row in table.rows.values():
		if row.has("mixamo_query") and file.begins_with(row["file"] + "-"):
			return row
	return {}


static func _read_table() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
	var rows := {}
	var per_role := {}
	if parsed is Dictionary:
		for row in parsed.get("clips", []):
			rows[row["file"]] = row
			per_role[row.get("role", "")] = per_role.get(row.get("role", ""), 0) + 1
	return {"rows": rows, "per_role": per_role}
