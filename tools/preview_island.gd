extends Node3D
## Fixed-camera viewer for Whisperbloom Hollow. Development tool, not shipped.
##
## The island is generated (D-007), so there is no editor viewport to judge it
## in — the map does not exist until something runs `arena.gd`. This scene is
## that something: it loads the **real** `scenes/world/arena.tscn`, never a
## simplified copy, and then frames it from a named camera.
##
## Every framing is solved from the arena's own data (`island.extent()`,
## `landmarks.torch_spots`, the spawn ring) rather than from typed coordinates,
## so the shots keep pointing at the shrine after somebody moves the shrine.
##
## Add `match` as a second argument to run the **real match path** as well: an
## offline session on `Net`, a fake roster, and Bogs spawned by `MatchState`
## through `register_arena`. That is the check that matters — it is the
## difference between "the island renders" and "the island is a level".
##
## Usage:
##   Godot --path . --resolution 1280x720 --script tools/snapshot.gd -- \
##       res://tools/preview_island.tscn out.png <ticks> <view> [match]
##
##   views: wide  under  eye  eye0..eye7  shrine  grove  arch  bridge  spawns
##          hollow  top  canopy  tree
##
## `top` is straight down and orthographic, with the fog off — it is a plan of
## the map, not a picture of it. `canopy` is a third-person camera's height
## under the tree nearest pad 0, looking at the middle; `tree` is that same tree
## from nine metres, to judge its proportions against the Bog-sized things
## around it.

const ARENA := preload("res://scenes/world/arena.tscn")

## Peer ids for the stand-in players, well outside anything ENet hands out —
## the same trick `tools/combat_range.gd` uses (D-011).
const DUMMY_BASE := 900
const DUMMY_COUNT := 5

const VIEWS := ["wide", "under", "eye", "shrine", "grove", "arch", "bridge",
	"spawns", "hollow", "top", "canopy", "tree",
	"eye0", "eye1", "eye2", "eye3", "eye4", "eye5", "eye6", "eye7"]

## Lighting diagnostics. The map is lit almost entirely by ambient and torches,
## which makes "this surface is black" ambiguous between four different causes —
## no ambient reaching it, inverted normals, shadow acne, or an albedo that is
## simply too dark. These flags take one suspect out of the picture at a time.
const FLAGS := {
	"noshadow": "turn the moon's shadows off",
	"noon": "moon at daylight energy, to see the geometry plainly",
	"nofog": "volumetric fog off, so surfaces are judged unmediated",
	"flatterrain": "terrain in flat unshaded magenta, to see where it actually is",
	"notorch": "every torch light off, leaving only the moon and the sky ambient",
	"hud": "keep the match HUD, to judge it over the real map rather than a testbed",
}

var _view: String = "wide"
var _run_match: bool = false
var _flags: Dictionary = {}
var _arena: Arena
var _frames: int = 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for arg: String in args:
		if VIEWS.has(arg):
			_view = arg
		elif arg == "match":
			_run_match = true
		elif FLAGS.has(arg):
			_flags[arg] = true

	# The session has to exist before the arena's `_ready` runs, because that is
	# where `register_arena` is called and where the host starts the warmup.
	if _run_match:
		_start_session()
	# A plan view through forty metres of volumetric fog, lit by a moon at a
	# tenth of daylight, is a dark blot. It is a plan, so it is lit like one.
	if _view == "top":
		_flags["nofog"] = true
		_flags["noon"] = true

	_arena = ARENA.instantiate() as Arena
	# This tool exists to judge the island, and a crosshair and a kill feed over
	# the shot are in the way of that — so the HUD comes out unless `hud` asks
	# for it, which is the only way to see the two together.
	#
	# `free()` rather than `queue_free()`, and before `add_child` rather than
	# after: the HUD takes the mouse in its own `_ready` (that is its job — see
	# `hud.gd`), and a node that never enters the tree never runs one. Deferring
	# it would capture the cursor for a frame in the middle of a screenshot.
	if not _flags.has("hud"):
		var hud := _arena.get_node_or_null("HUD")
		if hud != null:
			_arena.remove_child(hud)
			hud.free()
	add_child(_arena)

	_apply_diagnostics()
	_build_camera()
	if _run_match:
		_report_roster()


## Reach into the built arena and switch things off. Only ever runs when a flag
## was passed, so the default render is always the real one.
func _apply_diagnostics() -> void:
	if _flags.is_empty():
		return
	var moon := _arena.get_node_or_null("Moon") as DirectionalLight3D
	if moon != null:
		if _flags.has("noshadow"):
			moon.shadow_enabled = false
		if _flags.has("noon"):
			moon.light_energy = 3.0
			moon.light_color = Color(1, 1, 1)
	if _flags.has("notorch"):
		for torch in _arena.get_node("Torches").get_children():
			(torch.get_node("Light") as OmniLight3D).visible = false
	if _flags.has("flatterrain"):
		var flat := StandardMaterial3D.new()
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flat.albedo_color = Color(1.0, 0.0, 0.7)
		for chunk in _arena.get_node("Terrain").get_children():
			(chunk.get_node("Terrain") as MeshInstance3D).material_override = flat
	if _flags.has("nofog"):
		var world := _arena.get_node_or_null("Environment") as WorldEnvironment
		if world != null:
			# Duplicated, so a diagnostic run can never write through to the
			# shared `arena_env.tres` on disk.
			world.environment = world.environment.duplicate()
			world.environment.volumetric_fog_enabled = false
	print("preview_island: diagnostics %s" % ", ".join(_flags.keys()))


func _start_session() -> void:
	Net.start_offline()
	for i in DUMMY_COUNT:
		Net.players[DUMMY_BASE + i] = {
			"name": "Bog %d" % (i + 1), "team": 0, "ready": true,
		}
	Net.roster_changed.emit()
	var config := Net.config
	config.warmup_time = 0.0
	config.spawn_protection = 0.0
	config.time_limit = 0


# ------------------------------------------------------------------ framing ---

## Solve this view's camera from what the arena actually built.
func _build_camera() -> void:
	var framing := _framing()
	var camera := Camera3D.new()
	add_child(camera)
	camera.fov = framing["fov"]
	camera.far = 500.0
	if framing.has("ortho"):
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = framing["ortho"]
	camera.look_at_from_position(framing["eye"], framing["look"], Vector3.UP)
	# Claimed after the arena — and after any Bog — so it wins the viewport over
	# a `BogCamera` that has made itself current.
	camera.make_current()


func _framing() -> Dictionary:
	var island := _arena.island
	var reach := island.extent()
	var shrine := _ground(island.knoll_centre)
	var grove := _ground(Landmarks.GROVE_CENTRE)
	var centre := _ground(Vector2.ZERO)

	if _view.begins_with("eye") and _view.length() == 4:
		var index := int(_view.substr(3)) % _arena.spawn_points.size()
		var from := _arena.spawn_points[index].origin + Vector3.UP * 1.55
		return {"eye": from, "look": centre + Vector3.UP * 1.2, "fov": 75.0}

	match _view:
		"top":
			# Up is -Z on screen. `look_at` cannot aim straight down with Y as
			# up, so the eye is nudged a millimetre south of the centre.
			return {"eye": Vector3(0.0, 80.0, 0.001), "look": Vector3.ZERO,
				"fov": 60.0, "ortho": reach * 2.1}
		"canopy", "tree":
			var trunk := _tree_near_pad()
			var inward := Vector3(-trunk.x, 0.0, -trunk.z).normalized()
			if _view == "canopy":
				# Where a third-person camera hangs: about two metres up and a
				# couple back from a Bog standing at the trunk.
				return {"eye": trunk + inward * 2.0 + Vector3.UP * 2.2,
					"look": centre + Vector3.UP * 1.2, "fov": 75.0}
			var side := inward.cross(Vector3.UP)
			return {"eye": trunk + (inward + side * 0.6).normalized() * 9.0 + Vector3.UP * 1.6,
				"look": trunk + Vector3.UP * 4.0, "fov": 70.0}
		"under":
			# From below and outside: the only view that shows the rocky root,
			# which is half of what makes this read as a *floating* island.
			return {"eye": Vector3(reach * 0.9, -20.0, reach * 1.1),
				"look": Vector3(0.0, -6.0, 0.0), "fov": 62.0}
		"eye":
			# Standing on the first spawn pad, looking across the map. This is
			# the only framing in the list a player will ever actually have.
			var pad := _arena.spawn_points[0].origin + Vector3.UP * 1.55
			return {"eye": pad, "look": centre + Vector3.UP * 1.2, "fov": 75.0}
		"shrine":
			return {"eye": shrine + Vector3(9.0, 1.2, 9.5),
				"look": shrine + Vector3.UP * 2.0, "fov": 55.0}
		"grove":
			return {"eye": grove + Vector3(7.5, 2.4, 6.5),
				"look": grove + Vector3.UP * 1.6, "fov": 58.0}
		"arch":
			var arch := _ground(Vector2(cos(Landmarks.EAST_BEARING - 0.55),
				sin(Landmarks.EAST_BEARING - 0.55))
				* (island.landmasses[0].rim_radius(Landmarks.EAST_BEARING - 0.55) - 6.5))
			var inward := (centre - arch).normalized()
			return {"eye": arch - inward * 11.0 + Vector3.UP * 2.2,
				"look": arch + Vector3.UP * 2.6, "fov": 60.0}
		"bridge":
			var islet := island.landmasses[1]
			var anchor := _ground(Vector2(cos(Landmarks.EAST_BEARING),
				sin(Landmarks.EAST_BEARING))
				* (island.landmasses[0].rim_radius(Landmarks.EAST_BEARING) - 6.0))
			var far := _ground(islet.centre)
			return {"eye": anchor + Vector3.UP * 2.0,
				"look": far + Vector3.UP * 1.4, "fov": 68.0}
		"spawns":
			# High and steep, so all eight pads and the ground between them are
			# in one frame and the spread can be judged rather than trusted.
			# Kept as close as that allows: the volumetric fog is tuned for
			# distances *on* a 40-60 m island (D-009), and a camera forty metres
			# off the map renders almost pure haze.
			return {"eye": Vector3(0.0, reach * 0.72, reach * 0.34),
				"look": centre, "fov": 72.0}
		"hollow":
			# Scaled with the layout, or the camera on the 23 m island is buried
			# in the far shoulder, which moved out on to where it used to stand.
			var back := 13.0 * IslandGenerator.LAYOUT_SCALE
			return {"eye": centre + Vector3(back, 3.0, back),
				"look": centre + Vector3.UP * 1.0, "fov": 70.0}
		_:
			# `wide`: the establishing shot. Low enough that the horizon and the
			# island's underside are both in frame, which is where the sky and
			# the silhouette have to work together — and no further out than the
			# fog can see through, for the reason given under `spawns`.
			return {"eye": Vector3(-reach * 0.52, 9.0, reach * 0.78),
				"look": Vector3(0.0, -2.5, 0.0), "fov": 62.0}


## The foot of the scattered tree nearest spawn pad 0. The canopy point sits
## straight above the trunk, so its x and z are the trunk's.
func _tree_near_pad() -> Vector3:
	var pad := _arena.spawn_points[0].origin
	var best := Vector3.ZERO
	var best_distance := INF
	for point: Vector3 in _arena.scatter.canopy_points:
		var distance := Vector2(point.x, point.z).distance_to(Vector2(pad.x, pad.z))
		if distance < best_distance:
			best_distance = distance
			best = point
	return _ground(Vector2(best.x, best.z))


func _ground(at: Vector2) -> Vector3:
	var here := _arena.island.surface_point(at.x, at.y)
	return here if here.y > IslandGenerator.NO_LAND else Vector3(at.x, 0.0, at.y)


# ------------------------------------------------------------------- match ---

func _report_roster() -> void:
	print("preview_island: phase=%d bogs=%d spawns=%d" % [
		MatchState.phase, MatchState.bogs.size(), _arena.spawn_points.size()])
	var closest := INF
	for i in _arena.spawn_points.size():
		var origin := _arena.spawn_points[i].origin
		for j in range(i + 1, _arena.spawn_points.size()):
			closest = minf(closest, origin.distance_to(_arena.spawn_points[j].origin))
		print("  spawn %d at %v (ground %.2f, slope %.2f, inset %.1f)" % [
			i, origin, _arena.island.height_at(origin.x, origin.z),
			_arena.island.slope_at(origin.x, origin.z),
			_arena.island.inset_at(origin.x, origin.z)])
	# Two pads closer together than this and a full lobby opens the match inside
	# each other's spear range with spawn protection as the only thing in the way.
	print("  closest pair %.1f m" % closest)


## Every Bog's height above the ground it should be standing on. The one thing a
## still frame cannot tell you is whether the Bogs are *falling* — at spawn they
## are a few centimetres up by design, and by tick 30 they should have settled.
## A Bog still descending here is a Bog on its way to `VOID_HEIGHT`.
func _physics_process(_delta: float) -> void:
	_frames += 1
	if not _run_match or (_frames != 5 and _frames != 60 and _frames != 150):
		return
	for peer_id: int in MatchState.bogs:
		var bog: Bog = MatchState.bogs[peer_id]
		if not is_instance_valid(bog):
			continue
		var ground := _arena.island.height_at(bog.global_position.x, bog.global_position.z)
		print("  f%-4d %-8s y=%+.2f ground=%+.2f  above=%+.2f grounded=%s" % [
			_frames, bog.display_name, bog.global_position.y, ground,
			bog.global_position.y - ground, bog.is_on_floor()])
