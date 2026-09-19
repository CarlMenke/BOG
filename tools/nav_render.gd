extends Control
## What the guide line actually has to work with, drawn from above. Development
## tool, not shipped.
##
##   Godot --path . --resolution 1000x1000 --script tools/snapshot.gd -- \
##       res://tools/nav_render.tscn out.png <ticks> [map]
##
## `tools/nav_check.gd` counts the bake and `tools/parkour_report.gd` counts the
## jumps; neither of them can show you a *route*, and a route is the only thing
## the guide line is. The bug this was written for (D-167) passed the census —
## fourteen links on Kopje Crossing, printed, green — while every one of those
## links ended at the world origin, which is a thing that takes one look at a
## plan of the map to see and no amount of counting to notice.
##
## So: one map, stood up in the real arena exactly as `nav_check` does it, and
## then a plan view of the three layers the line is made of.
##
##   the wash    `NavBake.outline_image()`, the walkable ground, the same
##               texture the minimap draws.
##   the links   every `JumpLinks` link, amber for a leap and blue for a drop,
##               with a pip on the end it arrives at.
##   the line    the first spawn pad to the last, put through `GuidePath` — so
##               it is smoothed, resampled and arced over its jumps, the same
##               polyline `GuideLine` builds a ribbon around in a match.
##
## Everything is printed before the render, so this is also a headless census.

const ARENA_SCENE := preload("res://scenes/world/arena.tscn")

const BAKE_TIMEOUT := 90.0
## Enough calls of `GuidePath.solve` at a coarse delta for the shown line to
## finish chasing the solved one: it closes at 12 m/s, and no map is 90 m across.
const SETTLE_STEPS := 30
const SETTLE_DELTA := 0.25

## A border of pixels round the plan, so a link leaving the navmesh's own extent
## — every drop does, by the length of the drop — is still inside the picture.
const MARGIN := 48.0

const PAPER := Color(0.05, 0.055, 0.065)
const GROUND := Color(0.42, 0.44, 0.48, 0.55)
const LEAP := UIPalette.GUIDE_LOOSE
const DROP := UIPalette.GUIDE_ALLY
const ROUTE := Color(1.0, 1.0, 1.0)

var _arena: Arena = null
var _nav: NavBake = null
var _wash: ImageTexture = null
var _links := PackedVector3Array()
var _route := PackedVector3Array()
var _title: String = ""
var _bounds := AABB()


func _ready() -> void:
	Net.start_offline()
	Net.set_name_local("You")
	var args := Array(OS.get_cmdline_user_args()).filter(
		func(a: String) -> bool: return MapCatalog.is_valid(a))
	await _build(String(args[0]) if not args.is_empty() else MapCatalog.ids()[0])
	queue_redraw()


func _build(id: String) -> void:
	var config := Net.config
	config.win_condition = MatchConfig.WinCondition.LETTERS
	config.mode = MatchConfig.Mode.FREE_FOR_ALL
	config.map = id
	config.warmup_time = 0.2
	config.spawn_protection = 0.0
	config.time_limit = 0
	Net.roster_changed.emit()

	_arena = ARENA_SCENE.instantiate() as Arena
	# Onto the root, not beside this node: the plan is drawn on a `CanvasLayer`
	# above the match's own HUD — which is the only way to see it, the arena
	# bringing a camera and a full screen of savanna with it — and a 3D arena
	# does not belong under a canvas.
	await get_tree().process_frame
	get_tree().root.add_child(_arena)
	_nav = _arena.get_node_or_null("NavBake") as NavBake
	if _nav == null:
		push_error("nav_render: the arena added no NavBake")
		return
	var deadline := Time.get_ticks_msec() + int(BAKE_TIMEOUT * 1000.0)
	while not _nav.is_ready():
		if Time.get_ticks_msec() > deadline:
			push_error("nav_render: %s did not bake inside %.0f s" % [id, BAKE_TIMEOUT])
			return
		await get_tree().physics_frame

	_bounds = _nav.bounds()
	_links = _nav.link_points()
	var image := _nav.outline_image()
	if image != null and image.get_width() > 1:
		_wash = ImageTexture.create_from_image(image)

	var pads := _arena.spawn_points
	var leaps := 0
	if pads.size() >= 2:
		_route = _guide_line(pads[0].origin, pads[pads.size() - 1].origin)
		leaps = GuidePath.link_segments(_nav.find_path(
			pads[0].origin, pads[pads.size() - 1].origin), _links)
	_title = "%s — %d polygons, %d links, %.0f x %.0f m, pad 1 to pad %d over %d jumps" % [
		id, _nav.polygon_count(), _nav.link_count(), _bounds.size.x, _bounds.size.z,
		pads.size(), leaps]
	print("nav_render: %s" % _title)


## The route as the player is shown it, not as the server answers it: the same
## `GuidePath` the HUD owns, settled far enough that the chase has caught up.
func _guide_line(from: Vector3, to: Vector3) -> PackedVector3Array:
	var path := GuidePath.new("render", "letter", ROUTE)
	for i in SETTLE_STEPS:
		path.solve(SETTLE_DELTA, from, to, _nav)
	return path.points


# ------------------------------------------------------------------- drawing ---

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	if _bounds.size.x <= 0.0:
		return
	if _wash != null:
		draw_texture_rect(_wash, Rect2(_to_pixel(_bounds.position),
			_to_pixel(_bounds.position + _bounds.size) - _to_pixel(_bounds.position)),
			false, GROUND)

	var i := 0
	while i + 1 < _links.size():
		var a := _to_pixel(_links[i])
		var b := _to_pixel(_links[i + 1])
		var colour := DROP if _links[i + 1].y < _links[i].y - 0.3 else LEAP
		draw_line(a, b, colour, 2.0, true)
		draw_circle(b, 3.0, colour)
		i += 2

	for k in range(_route.size() - 1):
		draw_line(_to_pixel(_route[k]), _to_pixel(_route[k + 1]), ROUTE, 3.0, true)
	if _route.size() >= 2:
		draw_circle(_to_pixel(_route[0]), 7.0, ROUTE)
		draw_circle(_to_pixel(_route[_route.size() - 1]), 7.0, UIPalette.GUIDE_LOOSE)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(MARGIN * 0.4, MARGIN * 0.6), _title,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, ROUTE)


## World XZ to pixels, north-up, the long side fitted inside the margins — the
## same way round as `NavBake.outline_image()`, so the wash and the lines agree
## without either of them being flipped.
func _to_pixel(point: Vector3) -> Vector2:
	var span := maxf(maxf(_bounds.size.x, _bounds.size.z), 0.01)
	var scale := (minf(size.x, size.y) - MARGIN * 2.0) / span
	var centre := _bounds.position + _bounds.size * 0.5
	return size * 0.5 + Vector2(point.x - centre.x, point.z - centre.z) * scale
