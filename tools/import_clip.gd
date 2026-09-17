@tool
extends EditorScenePostImport
## One Mixamo clip in, one game-ready Animation out. Runs inside Godot's own
## importer on every `assets/source_reorg/anims/*.fbx` (set as `import_script/path`
## in each file's `.import`), so a re-import *is* the build: there is no Blender
## and no separate build step.
##
## For the clip it is handed, this
##   1. records the authored travel of the hips (distance and bearing over the
##      clip, and the speed that implies), as metadata on the Animation;
##   2. locks the hips to the skeleton's vertical axis, so the clip plays in
##      place and the physics body does the moving;
##   3. sets the loop mode from the clip table;
##   4. saves it to `art/generated/clips/<file>.res` and files it in the shared
##      library `art/generated/bog_clips.res` under its role.
##
## The clip table, `assets/source_reorg/clips.json`, is the single source of
## truth for what a file is: its role, whether it loops. A file the table does
## not know is imported but not shipped, and says so.
##
## Every clip was fetched on the BOG's own Mixamo rig, so its skeleton is the
## body's skeleton bone for bone and the tracks retarget by name with no map
## (verified 2026-09-16, `assets/source_reorg/README.md`).

const TABLE := "res://assets/source_reorg/clips.json"
const CLIP_DIR := "res://art/generated/clips/"
const LIBRARY := "res://art/generated/bog_clips.res"
const HIPS := "mixamorig_Hips"


func _post_import(scene: Node) -> Object:
	var file := get_source_file().get_file().get_basename()
	var table := _read_table()
	var row := _row_for(file, table)
	if row.is_empty():
		push_warning("import_clip: %s is not in clips.json; imported, not shipped" % file)
		return scene

	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null or player.get_animation_list().size() != 1:
		push_error("import_clip: %s should carry exactly one animation" % file)
		return scene
	var anim := player.get_animation(player.get_animation_list()[0]).duplicate(true) as Animation

	var hips := _hips_track(anim)
	if hips < 0:
		push_error("import_clip: %s has no %s position track" % [file, HIPS])
		return scene

	# Travel is first key to last, on the ground plane. For a cycle that is one
	# stride's worth, and travel over length is the speed the animator was
	# walking at when it was authored — the number the animator divides the game
	# speed by so the feet plant (D-029).
	var keys := anim.track_get_key_count(hips)
	var first: Vector3 = anim.track_get_key_value(hips, 0)
	var last: Vector3 = anim.track_get_key_value(hips, keys - 1)
	var travel := Vector3(last.x - first.x, 0.0, last.z - first.z)
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
	anim.resource_name = file
	anim.set_meta("role", row.get("role", ""))
	anim.set_meta("travel", travel)
	anim.set_meta("authored_speed", travel.length() / anim.length if anim.length > 0.0 else 0.0)
	anim.set_meta("hips_bob", high - low)
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
	print("import_clip: %-56s %6.3f s  travel %.3f m  %.3f m/s  bob %.3f  %s" % [
		file, anim.length, travel.length(), anim.get_meta("authored_speed"),
		high - low, "loop" if anim.loop_mode != Animation.LOOP_NONE else "once"])
	return scene


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


static func _hips_track(anim: Animation) -> int:
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_POSITION_3D \
				and String(anim.track_get_path(t)).ends_with(":" + HIPS):
			return t
	return -1
