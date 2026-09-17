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
##   3. locks the hips to the skeleton's vertical axis, so the clip plays in
##      place and the physics body does the moving;
##   4. sets the loop mode and writes the event markers from the clip table;
##   5. saves it to `art/generated/clips/<file>.res` and files it in the shared
##      library `art/generated/bog_clips.res` under its role.
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
	print("import_clip: %-52s %6.3f s  %.3f m/s  bob %.3f  face %+6.1f°  %d markers  %s" % [
		file, anim.length, anim.get_meta("authored_speed"), high - low, fix_deg,
		anim.get_marker_names().size(), "loop" if anim.loop_mode != Animation.LOOP_NONE else "once"])
	return scene


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


## Every bone's position at time `t`, or in the rest pose when `t` is negative.
static func _positions(anim: Animation, skeleton: Skeleton3D, tracks: Dictionary, t: float) -> Array[Vector3]:
	var world: Array[Transform3D] = []
	var out: Array[Vector3] = []
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
		out.append(world[b].origin)
	return out


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
	var role: String = _row_for(file, table).get("role", file)
	return role if table.per_role.get(role, 0) == 1 else file


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
