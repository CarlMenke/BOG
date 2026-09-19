extends Node3D
## Photograph every map in the catalog for the lobby's carousel. Development
## tool, not shipped.
##
##     "$GODOT" --path . --resolution 960x540 tools/map_thumbs.tscn
##     "$GODOT" --path . --resolution 960x540 tools/map_thumbs.tscn -- quarry
##     "$GODOT" --path . --resolution 960x540 tools/map_thumbs.tscn -- quarry candidates
##     "$GODOT" --headless --path . --import      # ...then let Godot see them
##
## One shot per map into `art/generated/map_thumbs/<id>.png` at 480x270, which
## is the picture the Map section of the lobby's Match panel scrolls through
## (D-162). A bare map id bakes that one map and nothing else, so re-taking a
## picture after a map is rebuilt is a one-argument run.
##
## **The real map, through `arena.tscn`.** This does not load a map scene the
## way `tools/preview_map.gd` does: it sets `Net.config.map` and instances the
## arena, which is the one path that builds either kind of map — Whisperbloom
## Hollow does not exist until `arena.gd` grows it from the seed (D-007), and a
## carousel with six photographs and a blank where the island should be is the
## obvious way this tool could have been written and would have been wrong. The
## HUD comes out first, for `preview_island.gd`'s reason: it takes the mouse in
## its own `_ready`.
##
## **The camera is authored per map and relative to the map's own box.** A row
## on the `MapCatalog` entry gives a compass bearing, a pitch, a zoom and how
## far up the map to look — never a world coordinate — so a rebuilt map
## (`quarry` is being redrawn as this lands) is re-photographed from the same
## perspective rather than from a point that used to be over its rim. The
## distance that fits the map in the frame is solved from the bounds and the
## lens. `MapCatalog.THUMB_CAMERA` is the default every row starts from.
##
## `candidates` renders a sweep of bearings and pitches into `out/` instead of
## writing a thumb, which is how the rows below were chosen.
##
## Not headless, for `tools/snapshot.gd`'s reason: the headless driver uses the
## dummy rasteriser and produces no image. A window appears for a few seconds.

const ARENA := preload("res://scenes/world/arena.tscn")

## The tile the carousel draws. 16:9, because a map is a landscape and the
## lobby's rail is 460 px wide: at `MatchSettingsPanel.MAP_THUMB` (272 px) this
## is a little over 1.7x, the margin `skin_thumbs.gd` keeps for the same reason
## — a thumbnail that survives a bigger cell later.
const OUT_SIZE := Vector2i(480, 270)

## Physics ticks between adding an arena and taking its picture. The island is
## built inside `_ready`, so this is not the build — it is the sky shader, the
## GPU particles and the first shadow pass, all of which `tools/snapshot.gd`
## gives a scene 30 to 60 of for the same reason.
const WARMUP := 48

## And the ticks given to the *first* map, on top of the above. The renderer
## compiles this project's sky and terrain shaders once, on whichever map is
## photographed first, and that map came out flat and unshadowed when every map
## was given the same warmup.
const FIRST_EXTRA := 40

## The bearings and pitches `candidates` sweeps, in degrees.
const CANDIDATE_YAWS := [35.0, 125.0, 215.0, 305.0]
const CANDIDATE_PITCHES := [-22.0, -38.0]

var _wanted: Array[String] = []
var _candidates: bool = false
var _camera: Camera3D
var _arena: Node3D
var _written: int = 0


func _ready() -> void:
	var ids := MapCatalog.ids()
	for arg: String in OS.get_cmdline_user_args():
		if arg == "candidates":
			_candidates = true
		elif ids.has(arg):
			_wanted.append(arg)
	if _wanted.is_empty():
		_wanted = ids

	_camera = Camera3D.new()
	_camera.far = 800.0
	add_child(_camera)
	_camera.make_current()

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://art/generated/map_thumbs"))
	if _candidates:
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path("res://out"))
	_run()


func _run() -> void:
	var first := true
	for id: String in _wanted:
		if not await _build(id, first):
			get_tree().quit(1)
			return
		first = false
		if _candidates:
			await _shoot_candidates(id)
		else:
			if not await _shoot(id, MapCatalog.thumb_camera(id),
					MapCatalog.thumb_path(id)):
				get_tree().quit(1)
				return
			_written += 1
		_teardown()
		await get_tree().process_frame

	print("map_thumbs: wrote %d of %d thumbs at %dx%d"
		% [_written, MapCatalog.ids().size(), OUT_SIZE.x, OUT_SIZE.y])
	print("map_thumbs: %s" % ("PASS" if _candidates or _written == _wanted.size()
		else "FAIL"))
	get_tree().quit(0)


## Build one map through the real arena and let it settle.
func _build(id: String, first: bool) -> bool:
	Net.config.map = id
	var arena := ARENA.instantiate() as Node3D
	# Before `add_child`, so the HUD never runs a `_ready` and never takes the
	# cursor — `tools/preview_island.gd` takes the same line for the same reason.
	var hud := arena.get_node_or_null("HUD")
	if hud != null:
		arena.remove_child(hud)
		hud.free()
	add_child(arena)
	_arena = arena
	# Re-made current after every build: a map that brings a camera of its own
	# would otherwise take the shot from wherever that camera stands.
	_camera.make_current()

	var settle := WARMUP + (FIRST_EXTRA if first else 0)
	var until := Engine.get_physics_frames() + settle
	while Engine.get_physics_frames() < until:
		await get_tree().process_frame
	return true


func _teardown() -> void:
	if _arena != null:
		remove_child(_arena)
		# `free`, not `queue_free`: the next map is instanced on the next line and
		# two arenas in the tree at once is two skies, two suns and two worlds of
		# fog over one shot.
		_arena.free()
		_arena = null


## Aim the camera at one map and write the picture.
func _shoot(id: String, row: Dictionary, path: String) -> bool:
	_aim(row)
	await get_tree().process_frame
	RenderingServer.force_draw()
	var frame := get_viewport().get_texture().get_image()
	if frame == null:
		push_error("map_thumbs: the viewport produced no image for %s" % id)
		return false
	frame.resize(OUT_SIZE.x, OUT_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var err := frame.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("map_thumbs: could not write %s (error %d)" % [path, err])
		return false
	print("map_thumbs: %-8s -> %s  (yaw %.0f, pitch %.0f, zoom %.2f)"
		% [id, path, row["yaw"], row["pitch"], row["zoom"]])
	return true


## The sweep the authored rows were picked from.
func _shoot_candidates(id: String) -> void:
	var row := MapCatalog.thumb_camera(id)
	for yaw: float in CANDIDATE_YAWS:
		for pitch: float in CANDIDATE_PITCHES:
			var candidate := row.duplicate()
			candidate["yaw"] = yaw
			candidate["pitch"] = pitch
			var path := "res://out/thumb_%s_y%03d_p%02d.png" % [id, int(yaw),
				int(absf(pitch))]
			await _shoot(id, candidate, path)


## Where the camera stands for one map, from the map's own bounding box and the
## row's bearing, pitch, zoom and look-at height.
##
## Solved rather than typed, so a map that is rebuilt (or merely re-dressed) is
## photographed from the same *perspective* rather than from a point that used
## to be over its rim. The distance is the one that fits the map's half-span in
## the lens at the pitch being used; `zoom` above 1 stands further back.
func _aim(row: Dictionary) -> void:
	var box := _bounds()
	var centre := box.get_center()
	var at := Vector3(centre.x, box.position.y + box.size.y * float(row["look_at"]),
		centre.z)
	var span := maxf(box.size.x, box.size.z) * 0.5
	_camera.fov = float(row["fov"])
	var reach := span / tan(deg_to_rad(_camera.fov * 0.5)) * float(row["zoom"])
	var yaw := deg_to_rad(float(row["yaw"]))
	var pitch := deg_to_rad(float(row["pitch"]))
	var back := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	_camera.look_at_from_position(at + back * reach, at, Vector3.UP)


## The world-space box the framing is solved against: **where the match is
## played**, not where the geometry reaches.
##
## `preview_map.gd` measures the meshes, which is the right answer for "did this
## import" and the wrong one here — Lantern Wharf's town beyond its wall and the
## quarry's rim columns are dressing, and a frame built to hold them puts the
## yard in the middle distance behind a foreground of the things that are not
## the map. The spawn pads are the map a player is in, and every map has eight
## of them by `preview_map`'s own check.
##
## The hollow has no static map to ask, so it is its own extent (D-007).
const SPAWN_MARGIN := 0.22


func _bounds() -> AABB:
	var map := _arena.get_node_or_null("Map") as StaticMap
	if map == null:
		var island: IslandGenerator = _arena.get("island")
		var extent := 30.0 if island == null else island.extent()
		return AABB(Vector3(-extent, -2.0, -extent),
			Vector3(extent * 2.0, 14.0, extent * 2.0))
	var pads := map.spawn_points()
	if pads.is_empty():
		return AABB(Vector3(-30, 0, -30), Vector3(60, 14, 60))
	var box := AABB(pads[0].origin, Vector3.ZERO)
	for pad: Transform3D in pads:
		box = box.expand(pad.origin)
	return box.grow(maxf(box.size.x, box.size.z) * SPAWN_MARGIN)
