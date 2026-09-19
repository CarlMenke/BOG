extends Node
## The FPS readout, checked rather than looked at (D-148). Development tool, not
## shipped.
##
##   Godot --headless --path . tools/fps_readout.tscn
##
## A scene and not a `--script`, for `grip_poses.gd`'s reason: the thing under
## test is `SceneFlow`'s child and reads `Settings`, and a `SceneTree` script
## runs with no autoloads at all.
##
## Four claims, which together are the ticket: the setting is off out of the box,
## the readout exists wherever `SceneFlow` is, it follows the setting in both
## directions with a real number in it, and a render tool's `suppress()` beats
## the setting — which is what keeps the counter out of every `preview_*` shot on
## a machine whose owner left it switched on.
##
## It writes `user://settings.cfg` on the way through, because `Settings` saves
## on every change and there is no way to move a setting without moving the file.
## The value it found is put back before it quits.

## Long enough for `FpsCounter.REFRESH` to elapse and the label to be written.
const SETTLE := 0.8

var _failures: int = 0


func _ready() -> void:
	_run()


func _run() -> void:
	var original: Variant = Settings.get_value("show_fps")

	if Settings.DEFAULTS.get("show_fps") != false:
		_fail("show_fps does not default to off")

	var counter := SceneFlow.get_node_or_null("FpsCounter") as FpsCounter
	if counter == null:
		_fail("SceneFlow has no FpsCounter")
		_done()
		return

	Settings.set_value("show_fps", false)
	await get_tree().create_timer(SETTLE).timeout
	if counter.visible:
		_fail("the readout is on screen with the setting off")

	Settings.set_value("show_fps", true)
	await get_tree().create_timer(SETTLE).timeout
	if not counter.visible:
		_fail("the readout is hidden with the setting on")
	var shown := counter.text
	var regex := RegEx.create_from_string("^\\d+ FPS$")
	if regex.search(shown) == null:
		_fail("the readout says %s, not a frame rate" % [shown if not shown.is_empty() else "nothing"])
	print("fps_readout: reads \"%s\"" % shown)

	# The file, not just the value in memory: what a player switched on has to
	# still be on the next time the game starts.
	Settings.load_from_disk()
	if not bool(Settings.get_value("show_fps")):
		_fail("settings.cfg did not keep show_fps")

	# What `tools/snapshot.gd` does before it renders anything, written the same
	# way round: the flag is set on `Engine`, not on the class.
	Engine.set_meta(FpsCounter.SUPPRESS_META, true)
	await get_tree().create_timer(SETTLE).timeout
	if counter.visible:
		_fail("a suppressed readout is still on screen")
	Engine.remove_meta(FpsCounter.SUPPRESS_META)

	Settings.set_value("show_fps", original)
	_done()


func _fail(why: String) -> void:
	_failures += 1
	print("  FAIL  %s" % why)


func _done() -> void:
	print("fps_readout: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)
