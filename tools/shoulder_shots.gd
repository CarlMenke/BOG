extends SceneTree
## The aiming shoulder, seen from the Bog's own camera. Development tool, not
## shipped, and not in the gate: it answers a question a person has to look at.
##
##   Godot --path . --resolution 1280x720 --script tools/shoulder_shots.gd -- \
##       out/shot.png 60 aim pov
##
## Like `tools/snapshot.gd`, and it runs the combat range the same way (the mode
## and `pov` are read out of these same arguments by `combat_range.gd` itself) —
## with two differences, and they are the whole reason this is a second file.
## It holds the aim button down from the first frame, so the picture is the
## aiming rig and not the resting one, which no mode of the range does for a
## still frame. And it paints a crosshair at screen centre, which under the
## camera's fourth rule is exactly where the shot goes — so what the renders can
## be compared for is how much of the Bog is standing in front of it.
##
## `aim pov` is a spear cocked and `draw pov` at 60 ticks is a bow at full
## draw. D-159 picked `SHOULDER_AIMING` off four of these.

const DEFAULT_WARMUP := 60

var _target: Node = null
var _out_path: String = "out/shoulder.png"
var _warmup: int = DEFAULT_WARMUP
var _failed: bool = false


func _initialize() -> void:
	Engine.max_fps = int(ProjectSettings.get_setting(
		"physics/common/physics_ticks_per_second", 60))
	Engine.set_meta("bog_no_fps_readout", true)

	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("shoulder_shots.gd: expected <out.png> <ticks> [range args]")
		_failed = true
		return
	_out_path = args[0]
	_warmup = maxi(1, int(args[1]))

	var packed := load("res://tools/combat_range.tscn") as PackedScene
	if packed == null:
		push_error("shoulder_shots.gd: could not load the combat range")
		_failed = true
		return
	_target = packed.instantiate()
	root.add_child(_target)
	Input.action_press("aim")
	print("shoulder_shots: rendering %s at tick %d" % [_out_path, _warmup])


func _process(_delta: float) -> bool:
	if _failed:
		return true
	Input.action_press("aim")
	if Engine.get_physics_frames() < _warmup:
		return false

	await process_frame
	RenderingServer.force_draw()
	var image := root.get_texture().get_image()
	if image == null:
		push_error("shoulder_shots: viewport produced no image")
		return true
	_paint_crosshair(image)
	var err := image.save_png(_out_path)
	if err != OK:
		push_error("shoulder_shots: could not write %s (error %d)" % [_out_path, err])
	else:
		print("shoulder_shots: wrote %s (%dx%d)" % [
			_out_path, image.get_width(), image.get_height()])
	return true


func _paint_crosshair(image: Image) -> void:
	var cx := image.get_width() / 2
	var cy := image.get_height() / 2
	for d in range(-14, 15):
		if absi(d) < 4:
			continue
		image.set_pixel(cx + d, cy, Color.RED)
		image.set_pixel(cx, cy + d, Color.RED)
