extends SceneTree
## Every clip in the shared library as numbers, so candidates for a role can
## be compared on the things a blend cares about before anyone looks at a
## sheet (D-066 measured the same quantities on the old build). Development
## tool, not shipped.
##
##   Godot --headless --path . --script tools/clip_measure.gd [-- role ...]
##
## Per clip: length, loop, authored speed, hip bob; the hips' mean height and
## the torso's mean pitch (Hips→Neck off vertical); how far the hip line and
## the chest line are turned from the rest pose (+ to the BOG's left); how far
## the chest line is turned from the *hip* line, mean and range, which is the
## twist a clip carries in its own spine and the only part of a stance the
## `face` yaw cannot reach, because that yaw turns the hips and the chest
## together — an upper-body layer copies exactly that twist and nothing else;
## the bearing of the authored travel off the body's forward (+ to the left); and
## the loop seam (the largest bone jump from the last frame back to the
## first, relative to the hips). It also names clips whose poses are identical,
## because Mixamo lists the same motion under more than one id.

const BODY := "res://art/bog/BOG.fbx"
const LIBRARY := "res://art/generated/bog_clips.res"
const SAMPLES := 12

var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _rest_left: Vector3
var _rest_forward: Vector3
var _rest_chest: Vector3


func _initialize() -> void:
	var body := (load(BODY) as PackedScene).instantiate()
	root.add_child(body)
	_skeleton = body.find_child("Skeleton3D", true, false)
	_player = body.find_child("AnimationPlayer", true, false)
	var lib := load(LIBRARY) as AnimationLibrary
	_player.remove_animation_library("")
	_player.add_animation_library("", lib)

	var rest := _positions(true)
	_rest_left = _flat(rest[_b("LeftUpLeg")] - rest[_b("RightUpLeg")])
	_rest_chest = _flat(rest[_b("LeftShoulder")] - rest[_b("RightShoulder")])
	_rest_forward = _rest_left.cross(Vector3.UP).normalized()

	var only := OS.get_cmdline_user_args()
	var keys := lib.get_animation_list()
	keys.sort()
	print("%-46s %6s %4s %6s %5s %5s %6s %6s %6s %6s %6s %7s %6s" % ["clip", "len", "loop", "m/s", "bob",
		"hips", "pitch", "hipyaw", "chest", "twist", "range", "bearing", "seam"])
	var signatures := {}
	for key in keys:
		var anim := lib.get_animation(key)
		if not only.is_empty() and not only.has(String(anim.get_meta("role", key))) and not only.has(key):
			continue
		var hips := 0.0
		var pitch := 0.0
		var hip_yaw := 0.0
		var chest_yaw := 0.0
		var twist := 0.0
		var twist_low := INF
		var twist_high := -INF
		var sig := PackedFloat32Array()
		for i in SAMPLES:
			var t := anim.length * (float(i) + 0.5) / float(SAMPLES)
			var pos := _pose_at(key, t)
			hips += pos[_b("Hips")].y
			var spine := pos[_b("Neck")] - pos[_b("Hips")]
			pitch += rad_to_deg(spine.angle_to(Vector3.UP))
			var hip_line := _flat(pos[_b("LeftUpLeg")] - pos[_b("RightUpLeg")])
			var chest_line := _flat(pos[_b("LeftShoulder")] - pos[_b("RightShoulder")])
			hip_yaw += _yaw(hip_line, _rest_left)
			chest_yaw += _yaw(chest_line, _rest_chest)
			# The chest over the hips, on this frame: the shoulder line against the
			# hip line, with the rest pose's own offset between the two lines taken
			# out. A whole-body yaw moves both and cancels here, which is why this
			# and not `chest` is the number a layered clip is judged on.
			var t_i := _yaw(chest_line, _rest_chest) - _yaw(hip_line, _rest_left)
			twist += t_i
			twist_low = minf(twist_low, t_i)
			twist_high = maxf(twist_high, t_i)
			for bone in ["LeftArm", "RightUpLeg", "Spine", "Head"]:
				var p := (pos[_b(bone)] - pos[_b("Hips")]).snapped(Vector3.ONE * 0.001)
				sig.append_array([p.x, p.y, p.z])
		var first := _pose_at(key, 1.0 / 60.0)
		var last := _pose_at(key, anim.length - 1.0 / 60.0)
		var seam := 0.0
		for b in _skeleton.get_bone_count():
			seam = maxf(seam, (first[b] - first[0]).distance_to(last[b] - last[0]))
		var travel: Vector3 = anim.get_meta("travel", Vector3.ZERO)
		var bearing := _yaw(_flat(travel), _rest_forward) if travel.length() > 0.05 else 0.0
		print("%-46s %6.3f %4s %6.3f %5.3f %6.3f %5.1f %6.1f %6.1f %6.1f %6.1f %7.1f %6.3f" % [key, anim.length,
			"yes" if anim.loop_mode != Animation.LOOP_NONE else "no",
			anim.get_meta("authored_speed", 0.0), anim.get_meta("hips_bob", 0.0),
			hips / SAMPLES, pitch / SAMPLES, hip_yaw / SAMPLES, chest_yaw / SAMPLES,
			twist / SAMPLES, twist_high - twist_low, bearing, seam])
		var h := sig.to_byte_array().hex_encode().md5_text()
		signatures[h] = signatures.get(h, []) + [key]
	for h in signatures:
		if signatures[h].size() > 1:
			print("identical poses: %s" % ", ".join(signatures[h]))
	quit()


func _pose_at(key: String, t: float) -> Array[Vector3]:
	_player.play(key)
	_player.seek(maxf(t, 0.0001), true)
	return _positions(false)


## Forward kinematics by hand, from the local poses the player just wrote —
## `get_bone_global_pose` is a cache that fills on the first frame in the
## tree, and this runs before there is one (D-095).
func _positions(rest: bool) -> Array[Vector3]:
	var world: Array[Transform3D] = []
	var out: Array[Vector3] = []
	for b in _skeleton.get_bone_count():
		var parent := _skeleton.get_bone_parent(b)
		var local := _skeleton.get_bone_rest(b) if rest else _skeleton.get_bone_pose(b)
		world.append(local if parent < 0 else world[parent] * local)
		out.append(world[b].origin)
	return out


func _b(short: String) -> int:
	return _skeleton.find_bone("mixamorig_" + short)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()


## Signed degrees from `reference` to `v` about the up axis, + to the left,
## given that the rest pose's left is the reference for the hip line.
static func _yaw(v: Vector3, reference: Vector3) -> float:
	return rad_to_deg(reference.signed_angle_to(v, Vector3.UP))
