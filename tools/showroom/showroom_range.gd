extends Node
## Photographs a real BOG screen wearing a candidate theme. Development tool for
## the UI showroom, not shipped, and nothing here changes the game.
##
##     "$GODOT" --path . --resolution 1600x900 --script tools/snapshot.gd -- \
##         res://tools/showroom/showroom_range.tscn out.png 40 <mode> <variant> [layout]
##
## Modes are `tools/ui_range.gd`'s and `tools/hud_range.gd`'s own — anything
## starting with `hud` goes to the HUD range, everything else to the UI range —
## and the inner range reads the same argument list, so this wrapper adds exactly
## one thing: the theme swap.
##
## The swap is a brute force walk of the whole tree every idle frame rather than
## a one-shot in `_ready`, and that is deliberate. The ranges instance their
## screens across several frames (the menu awaits a frame before opening the
## settings panel; the HUD range stands a whole combat range up first), so a
## single pass would dress half a screen. The walk is idempotent — it only writes
## to a `Control` whose `theme` is set and is not already the candidate — and it
## runs perhaps thirty times before `snapshot.gd` takes the shot on physics tick
## 40, which costs nothing worth measuring at this size.
##
## `class_name` is avoided on purpose. A `class_name` under `tools/` only enters
## the project's global class cache after an editor scan, and this tool is meant
## to be runnable on a fresh clone from bash alone, so the two halves of the
## showroom are preloaded by path instead.
##
## What this cannot restyle: anything drawn from `UIPalette` constants directly
## rather than through the `Theme` — the crosshair, the cooldown sweeps, the kill
## feed tints, the nameplates, and the wordmark's underline bar. Those stay in
## today's colours in every shot. Accepted: this is a showroom for the theme.

const UI_RANGE := preload("res://tools/ui_range.tscn")
const HUD_RANGE := preload("res://tools/hud_range.tscn")
const ShowroomThemeScript := preload("res://tools/showroom/showroom_theme.gd")
const ShowroomStylesScript := preload("res://tools/showroom/showroom_styles.gd")
const ShowroomLayoutsScript := preload("res://tools/showroom/showroom_layouts.gd")

## Which screen each mode puts on the camera, for the layout half. The theme half
## does not need to know -- it walks every `Control` in the tree -- but a layout
## recipe is written against one screen's node names and has to be handed that
## screen and nothing else.
const SCREEN_FOR := {
	"settings": "settings",
	"lobby": "lobby",
	"hud": "hud",
	"menu": "menu",
}

var _variant: String = "current"
var _layout: String = "current"
var _screen: String = "menu"
var _candidate: Theme = null
var _dressed: int = 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "menu"
	if args.size() >= 4:
		mode = args[3]
	if args.size() >= 5:
		_variant = args[4]
	if args.size() >= 6:
		_layout = args[5]

	# Checked in this order so `settings_network` is the settings screen and
	# `lobby_full` the lobby, rather than both falling through to the default.
	for prefix: String in SCREEN_FOR:
		if mode.begins_with(prefix):
			_screen = SCREEN_FOR[prefix]
			break

	if _variant != "current":
		var style: Dictionary = ShowroomStylesScript.get_style(_variant)
		if style.is_empty():
			push_error("showroom: unknown variant '%s'; known: %s"
				% [_variant, ", ".join(ShowroomStylesScript.names())])
		_candidate = ShowroomThemeScript.build(style)

	print("showroom: mode=%s variant=%s layout=%s (screen %s)"
		% [mode, _variant, _layout, _screen])
	# The inner range reads the same `OS.get_cmdline_user_args()` this did, so it
	# needs nothing passed to it; it sets itself up from index 3 in its `_ready`.
	add_child((HUD_RANGE if mode.begins_with("hud") else UI_RANGE).instantiate())


func _process(_delta: float) -> void:
	_dress()
	# After the dressing, not before: two of the settings recipes rebuild a
	# stylebox out of whatever the panel is currently getting from its theme, so
	# they have to run on a frame where that theme is already the candidate.
	_lay_out()


## Re-apply the layout recipe, every frame, for the reason the theme walk is
## every frame and one more: `lobby.gd` re-lays its own panels out whenever the
## roster changes, so a one-shot would be undone somewhere around frame ten. The
## recipes are idempotent, so this costs a handful of anchor writes and a few
## `get_parent()` comparisons.
func _lay_out() -> void:
	if _layout.is_empty() or _layout == "current":
		return
	var screen := _screen_root()
	if screen == null:
		return
	ShowroomLayoutsScript.apply(_screen, _layout, screen)


## The node a recipe is written against, found in the tree the inner range
## built. `settings` is the one that is not a scene of its own: it is the panel
## the menu carries, which the range opens a frame after instancing the menu.
func _screen_root() -> Node:
	var root := get_tree().root
	match _screen:
		"lobby": return _named(root, "Lobby")
		"hud": return _named(root, "HUD")
		"settings":
			var menu := _named(root, "MainMenu")
			return menu.get_node_or_null("%Settings") if menu != null else null
		_: return _named(root, "MainMenu")


static func _named(root: Node, node_name: String) -> Node:
	var hits := root.find_children(node_name, "", true, false)
	return hits[0] if hits.size() > 0 else null


func _dress() -> void:
	if _candidate == null:
		return
	var root := get_tree().root
	for control: Control in root.find_children("*", "Control", true, false):
		if control.theme != null and control.theme != _candidate:
			control.theme = _candidate
			_dressed += 1
	for window: Window in root.find_children("*", "Window", true, false):
		if window.theme != null and window.theme != _candidate:
			window.theme = _candidate
			_dressed += 1
	if _dressed > 0:
		print("showroom: dressed %d node(s) in '%s'" % [_dressed, _variant])
		_dressed = 0
