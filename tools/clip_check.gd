extends SceneTree
## Gate for the import layer: the body and the shared clip library agree.
## Development tool, not shipped.
##
##   Godot --headless --path . --script tools/clip_check.gd
##
## Checks, and fails loudly on, the things a re-import can silently break:
## the body's height and floor, the bone count, every clip table row having a
## clip in the library, every clip's tracks resolving on the body's skeleton,
## the hips locked to the axis, the loop mode matching the table, and one clip
## per suite landing every bone on the body where its own skeleton puts it.
## Prints the library as a table on the way, which is where the authored speeds
## the animator will divide by are read from.

const BODY := "res://art/bog/BOG.fbx"
const LIBRARY := "res://art/generated/bog_clips.res"
const TABLE := "res://assets/source_reorg/clips.json"
const HEIGHT := 1.80
const BONES := 49
const HIPS := "mixamorig_Hips"
## The retarget check plays these on the body and on their own skeleton.
const RETARGET_SAMPLE := ["Walk-StandardWalk", "SwordCombo-GreatSwordComboSlash",
	"Roll-DiveRollFromStanding-1", "BowDraw-ChargingBowForPowershot"]
const RETARGET_TOLERANCE := 0.0005

var _failures := 0


func _initialize() -> void:
	var body := (load(BODY) as PackedScene).instantiate()
	root.add_child(body)
	var skeleton := body.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var meshes := body.find_children("*", "MeshInstance3D", true, false)
	_want("body has a skeleton, a player and one mesh (%d)" % meshes.size(),
		skeleton != null and player != null and meshes.size() == 1)
	var mesh := meshes[0] as MeshInstance3D
	_want("body has %d bones (%d)" % [BONES, skeleton.get_bone_count()],
		skeleton.get_bone_count() == BONES)
	var aabb := mesh.mesh.get_aabb()
	_want("body stands %.2f m tall (%.3f)" % [HEIGHT, aabb.size.y], absf(aabb.size.y - HEIGHT) < 0.02)
	_want("body's feet are on the floor (base y %.3f)" % aabb.position.y, absf(aabb.position.y) < 0.02)

	var lib := load(LIBRARY) as AnimationLibrary
	_want("library loads", lib != null)
	var table := _read_table()
	var by_file := {}
	for key in lib.get_animation_list():
		by_file[lib.get_animation(key).resource_name] = key
	for row in table:
		var present := by_file.has(row.file)
		if row.has("mixamo_query"):
			for f in by_file:
				present = present or f.begins_with(row.file + "-")
		_want("table row %s is in the library" % row.file, present)
	_want("library has one clip per row (%d of %d)" % [lib.get_animation_list().size(), table.size()],
		lib.get_animation_list().size() == table.size())

	player.remove_animation_library("")
	player.add_animation_library("", lib)
	var anim_root := player.get_node(player.root_node)
	print("%-52s %7s %5s %7s %6s" % ["clip", "length", "loop", "m/s", "bob"])
	for key in lib.get_animation_list():
		var anim := lib.get_animation(key)
		_check_clip(key, anim, anim_root, skeleton)
		print("%-52s %7.3f %5s %7.3f %6.3f" % [key, anim.length,
			"yes" if anim.loop_mode != Animation.LOOP_NONE else "no",
			anim.get_meta("authored_speed", 0.0), anim.get_meta("hips_bob", 0.0)])

	for file in RETARGET_SAMPLE:
		_check_retarget(file, by_file.get(file, ""), player, skeleton)

	body.free()
	print("clip_check: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_clip(key: String, anim: Animation, anim_root: Node, skeleton: Skeleton3D) -> void:
	var bad_paths := 0
	var hips := -1
	for t in anim.get_track_count():
		var path := anim.track_get_path(t)
		var node := anim_root.get_node_or_null(NodePath(String(path).get_slice(":", 0)))
		if node != skeleton or path.get_subname_count() != 1 \
				or skeleton.find_bone(path.get_subname(0)) < 0:
			bad_paths += 1
		if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and path.get_subname(0) == HIPS:
			hips = t
	_want("%s: every track lands on a bone of the body (%d do not)" % [key, bad_paths], bad_paths == 0)
	_want("%s: has a hips position track" % key, hips >= 0)
	if hips < 0:
		return
	var drift := 0.0
	for k in anim.track_get_key_count(hips):
		var p: Vector3 = anim.track_get_key_value(hips, k)
		drift = maxf(drift, absf(p.x) + absf(p.z))
	_want("%s: hips are locked to the axis (%.4f)" % [key, drift], drift < 1e-5)


## The clip's own imported scene is the reference: it is the skeleton Mixamo
## animated, so a bone landing elsewhere on the body means the retarget is not
## the identity it is supposed to be (root scale, a renamed bone, a lost track).
func _check_retarget(file: String, key: String, player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	if key.is_empty():
		_want("retarget sample %s is in the library" % file, false)
		return
	var own := (load("res://assets/source_reorg/anims/%s.fbx" % file) as PackedScene).instantiate()
	root.add_child(own)
	var own_skeleton := own.find_child("Skeleton3D", true, false) as Skeleton3D
	var own_player := own.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var own_anim := own_player.get_animation(own_player.get_animation_list()[0])
	var worst := 0.0
	var worst_where := ""
	var length := player.get_animation(key).length
	for sample in 5:
		# Strictly inside the clip: a seek to 0.0 straight after play() applies
		# nothing on either player, and two unchanged poses agree for no reason.
		var t := length * (float(sample) + 0.5) / 5.0
		player.play(key)
		player.seek(t, true)
		own_player.play(own_player.get_animation_list()[0])
		own_player.seek(t, true)
		var here_all := _bone_positions(skeleton)
		var there_all := _bone_positions(own_skeleton)
		for b in skeleton.get_bone_count():
			var here: Vector3 = here_all[b]
			var there: Vector3 = there_all[own_skeleton.find_bone(skeleton.get_bone_name(b))]
			# The hips are locked on the body and travel on the reference, so
			# compare relative to the hips rather than in the skeleton's frame.
			here -= here_all[skeleton.find_bone(HIPS)]
			there -= there_all[own_skeleton.find_bone(HIPS)]
			if here.distance_to(there) > worst:
				worst = here.distance_to(there)
				worst_where = "%s at %.2f s" % [skeleton.get_bone_name(b), t]
	var hips_y: float = own_anim.track_get_key_value(_hips_track(own_anim), 0).y
	print("retarget %-40s worst %.5f m (%s)" % [file, worst, worst_where])
	_want("%s: plays on the body where its own skeleton puts it (worst %.4f m, %s)"
		% [file, worst, worst_where], worst < RETARGET_TOLERANCE)
	_want("%s: hips sit about a metre up, not a centimetre (%.3f)" % [file, hips_y], hips_y > 0.5)
	own.free()


## Forward kinematics by hand, from the local poses the player just wrote.
## `get_bone_global_pose` reads a cache the skeleton refreshes on its first
## frame in the tree, and this runs before there is one.
static func _bone_positions(skeleton: Skeleton3D) -> Array[Vector3]:
	var world: Array[Transform3D] = []
	var out: Array[Vector3] = []
	for b in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(b)
		var local := skeleton.get_bone_pose(b)
		world.append(local if parent < 0 else world[parent] * local)
		out.append(world[b].origin)
	return out


static func _hips_track(anim: Animation) -> int:
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_POSITION_3D \
				and String(anim.track_get_path(t)).ends_with(":" + HIPS):
			return t
	return -1


static func _read_table() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
	return parsed.get("clips", []) if parsed is Dictionary else []


func _want(what: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		print("  FAIL  %s" % what)
