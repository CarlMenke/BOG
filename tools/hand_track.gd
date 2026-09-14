extends SceneTree
## Track one bone through one clip and print where it is, sample by sample.
## Development tool, not shipped.
##
##   Godot --headless --path . --script tools/hand_track.gd -- [clip] [bone] [step]
##
## Defaults to `Throw`, `RightHand`, 1/60 s. Each line is the clip time, the
## bone's position relative to `Hips` in the skeleton's own frame, and the
## bone's speed over the last step in m/s. The numbers this exists to find are
## the ones the throw is built on: where the arm is drawn furthest back (the
## pose a full charge holds), where the hand is moving fastest (the release),
## and how long the swing between them lasts.
##
## One clip time per processed frame rather than a loop inside `_initialize`:
## an `AnimationPlayer` only writes its pose into the skeleton when the tree
## processes it, so a seek followed by a read in the same call sees the rest
## pose every time. The player is held at `speed_scale` 0 so the frame's own
## delta does not move it off the time it was asked for.
##
## Printed rather than judged, so the same run answers the next question too.

const GUB := "res://art/generated/gub.glb"

var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _bone: int = -1
var _hips: int = -1
var _clip: String = "Throw"
var _step: float = 1.0 / 60.0
var _length: float = 0.0
## The clip time the pose currently in the skeleton belongs to, or -1 before
## the first seek has been processed.
var _shown: float = -1.0
var _next: float = 0.0
var _previous: Vector3 = Vector3.INF
var _failed: bool = false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_clip = args[0] if args.size() > 0 else "Throw"
	var bone_name := args[1] if args.size() > 1 else "RightHand"
	_step = float(args[2]) if args.size() > 2 else 1.0 / 60.0

	var scene := load(GUB) as PackedScene
	if scene == null:
		push_error("hand_track: cannot load %s" % GUB)
		_failed = true
		return
	var model := scene.instantiate()
	root.add_child(model)
	_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _player == null or _skeleton == null or not _player.has_animation(_clip):
		push_error("hand_track: no AnimationPlayer/Skeleton3D, or no clip '%s'" % _clip)
		_failed = true
		return
	_bone = _skeleton.find_bone(bone_name)
	_hips = _skeleton.find_bone("Hips")
	if _bone < 0 or _hips < 0:
		push_error("hand_track: rig has no '%s' or no 'Hips'" % bone_name)
		_failed = true
		return

	_length = _player.get_animation(_clip).length
	print("hand_track: %s / %s, %.3f s, step %.4f" % [_clip, bone_name, _length, _step])
	print("time\tx\ty\tz\tspeed")
	_player.play(_clip)
	_player.speed_scale = 0.0


func _process(_delta: float) -> bool:
	if _failed:
		return true
	if _shown >= 0.0:
		var hand := _skeleton.get_bone_global_pose(_bone).origin
		var pelvis := _skeleton.get_bone_global_pose(_hips).origin
		var rel := hand - pelvis
		var speed := 0.0 if _previous == Vector3.INF else (hand - _previous).length() / _step
		print("%.3f\t%.3f\t%.3f\t%.3f\t%.2f" % [_shown, rel.x, rel.y, rel.z, speed])
		_previous = hand
	if _next > _length + 0.0001:
		return true
	_player.seek(_next, true)
	_shown = _next
	_next += _step
	return false
