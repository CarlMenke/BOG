class_name FpsCounter
extends Label
## The frame-rate readout, in the top-left corner, off unless somebody asked for
## it (D-148).
##
## It hangs off `SceneFlow` rather than off the HUD because the question it
## answers — "is this machine keeping up" — is asked in a match, in the lobby and
## on the menu, and `SceneFlow` is the one node that is on screen for all three.
## One counter, in one place, that can only be wrong once.
##
## Remembered in `settings.cfg` as `show_fps`, like every other per-machine
## display choice, and off by default: it is a diagnostic, not part of what the
## game looks like.

## How often the number is rewritten. A readout that changes sixty times a
## second cannot be read; twice a second still shows a stutter as a dip.
const REFRESH := 0.5

## Engine metadata a render tool sets to keep the readout out of a shot. A
## preview or gate render has to look the same on every machine and
## `settings.cfg` is per-machine, so `tools/snapshot.gd` sets this and no
## `preview_*` render carries the readout however this player last left the
## toggle (D-148).
##
## Metadata rather than a static on this class, and the string is written out
## again over there rather than read from here: `snapshot.gd` is a `--script`
## main loop, compiled before the autoloads are registered, so naming
## `FpsCounter` in it pulls `Settings` into that compile and the whole tool
## fails to load. It did, once, which is why this is a string.
const SUPPRESS_META := "bog_no_fps_readout"

## Seconds since the number was last written. Starts at `REFRESH` so the first
## visible frame has a number on it rather than a blank corner.
var _elapsed: float = REFRESH


func _ready() -> void:
	name = "FpsCounter"
	# Top left: the one corner a match leaves empty — the clock is centred, the
	# minimap is top right, the kill feed and chat are bottom left and the
	# ability bar is bottom right.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(16.0, 6.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The pause menu pauses the tree, and a frame rate that stops being measured
	# the moment the game is paused is a number nobody can read off a still
	# screen. `SceneFlow` runs on `PROCESS_MODE_ALWAYS` for the same reason.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_font_size_override("font_size", 14)
	add_theme_color_override("font_color", UIPalette.TEXT_DIM)
	# A shadow rather than a panel behind it: this sits over sky, grass and menu
	# glass in turn, and a plate for it would be a box in the corner of every
	# screen in the game.
	add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.65))
	add_theme_constant_override("shadow_offset_x", 1)
	add_theme_constant_override("shadow_offset_y", 1)
	text = ""
	visible = wanted()


func _process(delta: float) -> void:
	# Asked every frame rather than wired to `Settings.changed`: the suppression
	# is metadata a tool can set after this node was built, so there is an answer
	# here that no signal carries. Both halves are a dictionary lookup.
	visible = wanted()
	if not visible:
		_elapsed = REFRESH
		return
	_elapsed += delta
	if _elapsed < REFRESH:
		return
	_elapsed = 0.0
	text = "%d FPS" % Engine.get_frames_per_second()


## Whether the readout belongs on screen at all.
func wanted() -> bool:
	return not Engine.has_meta(SUPPRESS_META) and bool(Settings.get_value("show_fps"))
