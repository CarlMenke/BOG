class_name NavBake
extends Node3D
## The walkable shape of whatever map is up, baked on this machine for this
## machine — the ground the guide line and the minimap are drawn on.
##
## BOG had no navigation of any kind until the letters round, and it still has
## no AI: nothing walks a path, nothing steers, nothing is chased. What this is
## for is a *drawing*. A player who has never seen Halcyon Wake cannot be told
## "the letter is 40 m that way" and be expected to find the stair; they have to
## be shown the route, and a route is a navmesh.
##
## **Local and cosmetic, like a ragdoll (D-010).** Every peer bakes its own, in
## its own time, off geometry every peer already has; nothing about the bake
## travels on the wire, and the baker taking 40 ms longer on one machine than
## another changes nothing anybody else can see. Nothing here may ever be read
## by a rule — the host decides the match and the host has no navmesh (D-007).
##
## **Why one baker serves seven maps.** Collision is the same shape everywhere:
## `static_map.gd` puts world-space triangles on layer 1 under a single
## `StaticBody3D`, the island's landmass, landmarks and prop scatter each put
## theirs on layer 1 too, and map dressing with no collider — the yacht's sea
## quad, 2.4 km of it — is invisible to a parse that only reads static
## colliders. So the source is stated once as "layer 1, static colliders, from
## the arena down" and no map needs a line of its own.
##
## The one thing that has to be waited for is *when*. A static map builds its
## collision inside its own `_ready`, and the arena adds this node in the same
## frame, so a parse on the first frame would see an empty broadphase and bake
## a navmesh of nothing. Two physics frames, which is the same wait and the same
## reason as `MatchState._try_spawn_capture_letters`.
##
## After the bake, `JumpLinks` adds what a navmesh cannot know — the ledges, the
## gaps and the drops a Bog can cross — and the walkable area is rasterised once
## into an `Image` for the minimap, because asking a `Control` to redraw four
## hundred polygons every frame is not a minimap, it is a profiler entry.

signal baked(msec: int)

## How `Minimap` and anything else finds the arena's baker without a path.
const GROUP := "nav_bake"

## Quarter-metre cells. Fine enough that a 1 m walkway between two containers
## survives the agent-radius erosion with a polygon left in the middle, coarse
## enough that Kopje Crossing's hundred and twenty-three rocks bake in well
## under a second.
const CELL_SIZE := 0.25
const CELL_HEIGHT := 0.2

## The Bog, as the baker sees him. The climb is the interesting one: he has no
## step-up at all — every stair in the game is a ramp — so 0.3 m is a lip he can
## walk over and not an invitation to solve routes up the side of a crate stack.
## The slope is a shade under `floor_max_angle` (52°) so the navmesh never
## promises ground the character controller would slide off.
const AGENT_MAX_CLIMB := 0.3
const AGENT_MAX_SLOPE := 50.0

## Islands smaller than this are noise — the top of a lamp post, the rim of a
## barrel — and a path allowed to end on one is a line pointing at a hat.
const REGION_MIN_SIZE := 2.0
## Long edges are cheap to path over and this mesh is never walked by an agent,
## only drawn, so there is no reason to tessellate it finely.
const EDGE_MAX_LENGTH := 4.0

const LAYER_WORLD := 1

## The minimap's ground layer, in pixels on the map's long side. 512 is one
## texture upload of a quarter of a megabyte, done once per match, and at
## Kopje Crossing's 96 m that is 19 cm to the pixel — finer than the 180 px
## circle the minimap draws it into will ever show.
const OUTLINE_LONG_SIDE := 512

var _navmesh: NavigationMesh
var _region: NavigationRegion3D
var _links: Node3D
var _link_count: int = 0
var _outline: Image
var _bounds: AABB = AABB()
var _baked: bool = false
var _started_msec: int = 0
var _baked_msec: int = 0


func _ready() -> void:
	add_to_group(GROUP)
	_region = NavigationRegion3D.new()
	_region.name = "Region"
	add_child(_region)
	_links = Node3D.new()
	_links.name = "Links"
	add_child(_links)
	# Started, not awaited: `_ready` returns on the frame the arena built it,
	# and the bake catches up a few frames later.
	_bake_when_the_world_is_solid()


## True once there is a navigation map worth asking. Everything that draws off
## this node checks it rather than assuming a bake that may still be running on
## a worker thread.
func is_ready() -> bool:
	return _baked


## The route from `from` to `to`, or empty while the bake is still out. Straight
## through `NavigationServer3D`: there is no agent here to own, and an
## `optimize` of true is what turns the polygon corridor into the funnelled line
## a player would actually walk.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not _baked or not is_inside_tree():
		return PackedVector3Array()
	var map := _map()
	if not map.is_valid():
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(map, from, to, true)


## The walkable area seen from directly above: white where you can stand,
## transparent where you cannot, `bounds()` wide. Rasterised once, after the
## bake — the same `Image` every caller gets, so nobody should write to it.
##
## Row 0 is the low-Z edge of `bounds()` and column 0 the low-X edge, which is
## north-up and the way round a top-down render of the map comes out.
func outline_image() -> Image:
	return _outline


## The world box `outline_image()` covers, taken from the navmesh's own
## vertices — so it is the extent of the *walkable* map and not of its dressing,
## and a minimap scaled by it does not spend two thirds of its circle on sea.
func bounds() -> AABB:
	return _bounds


func link_count() -> int:
	return _link_count


func polygon_count() -> int:
	return _navmesh.get_polygon_count() if _navmesh != null else 0


## Every jump link's two ends, in pairs: `[start, end, start, end, ...]`.
##
## `GuidePath` needs them to tell a leap from a walk — a path crossing a link
## comes back as two ordinary points like every other pair, and drawing a
## straight line through a five-metre gap is how the line tells a player to walk
## off a roof.
func link_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	if _links == null:
		return out
	for child in _links.get_children():
		var link := child as NavigationLink3D
		if link == null:
			continue
		out.append(link.start_position)
		out.append(link.end_position)
	return out


# -------------------------------------------------------------------- bake ---

func _bake_when_the_world_is_solid() -> void:
	# Two physics frames: a static map's `Collision` body is built in its own
	# `_ready`, in the same frame the arena added this node, and a body is only
	# in the broadphase the frame after it is added.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_begin()


func _begin() -> void:
	_started_msec = Time.get_ticks_msec()
	var root := get_parent()
	if root == null:
		root = self

	_navmesh = NavigationMesh.new()
	_navmesh.cell_size = CELL_SIZE
	_navmesh.cell_height = CELL_HEIGHT
	_navmesh.agent_radius = Bog.CAPSULE_RADIUS
	_navmesh.agent_height = Bog.STAND_HEIGHT
	_navmesh.agent_max_climb = AGENT_MAX_CLIMB
	_navmesh.agent_max_slope = AGENT_MAX_SLOPE
	_navmesh.region_min_size = REGION_MIN_SIZE
	_navmesh.edge_max_length = EDGE_MAX_LENGTH
	# Colliders and not meshes, deliberately. A static map's visual meshes carry
	# non-uniform and negative scales that a shape cannot be trusted to inherit
	# (D-031 is the same argument the other way round), and the backdrop group's
	# dressing has no collider at all — so parsing what a spear can hit is both
	# cheaper and more honest than parsing what the camera can see.
	_navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	_navmesh.geometry_collision_mask = LAYER_WORLD
	_navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN

	var source := NavigationMeshSourceGeometryData3D.new()
	# On the main thread, because this walks the scene tree — which is exactly
	# the thing a worker thread may not touch. Only the solve below is threaded.
	NavigationServer3D.parse_source_geometry_data(_navmesh, source, root)
	if not source.has_data():
		push_warning("nav_bake: map '%s' parsed no collision on layer %d; no guide line"
			% [Net.config.map, LAYER_WORLD])
		_finish()
		return
	NavigationServer3D.bake_from_source_geometry_data_async(_navmesh, source, _on_solved)


func _on_solved() -> void:
	if not is_inside_tree():
		return
	_finish()


func _finish() -> void:
	# The navigation map is told the cell size the region was baked at before
	# the region joins it. The server refuses a region whose cells disagree with
	# its map's, and the project states no navigation defaults, so the engine's
	# 0.25 height would silently throw this bake away.
	var map := _map()
	if map.is_valid():
		NavigationServer3D.map_set_cell_size(map, CELL_SIZE)
		NavigationServer3D.map_set_cell_height(map, CELL_HEIGHT)
		# Synchronous iterations for this map. Since 4.4 the server builds a
		# map's iteration on a worker and swaps it in when it is done, and on
		# every map the first `find_path` after `baked` landed a frame before
		# that swap: the region registered, the cell sizes agreeing, and the
		# map still serving the empty iteration it had before the mesh. One
		# region on a map nothing else uses is not a workload worth a thread.
		NavigationServer3D.map_set_use_async_iterations(map, false)
	if _navmesh != null:
		_region.navigation_mesh = _navmesh
	# One physics frame for the region to reach the map; the links below ask the
	# map where the nearest walkable point is, and before the sync the answer is
	# "nowhere".
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	# And then the sync is **forced**, synchronously. Since 4.4 the server builds
	# a map's iteration on a worker and swaps it in when it is done, so a frame
	# or two after the mesh is assigned the map can still be serving the empty
	# iteration it had before — `map_get_closest_point` answered the origin on
	# every map and `map_get_path` nothing, with the region registered and the
	# cell sizes agreeing. `map_force_update` builds the iteration now, on this
	# thread, and returns with the polygons in it.
	if map.is_valid():
		NavigationServer3D.map_force_update(map)

	if _navmesh != null and _navmesh.get_polygon_count() > 0:
		_link_count = JumpLinks.build(_navmesh, get_world_3d().direct_space_state, _links)
	_rasterise()

	# And one more, so the links are on the map too by the time anybody paths —
	# forced again for the same reason as above, now that the links exist.
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	if map.is_valid():
		NavigationServer3D.map_force_update(map)
	_baked = true
	_baked_msec = Time.get_ticks_msec() - _started_msec
	print("nav_bake: %s %d polygons, %d links, %d ms"
		% [Net.config.map, polygon_count(), _link_count, _baked_msec])
	baked.emit(_baked_msec)


func _map() -> RID:
	if not is_inside_tree():
		return RID()
	return get_world_3d().navigation_map


# --------------------------------------------------------------- the image ---

## Flatten the navmesh into one texture the minimap can blit.
##
## A fan per polygon rather than a proper tessellation: navmesh polygons come
## out convex by construction, so a fan from the first vertex covers each one
## exactly, and overlapping fans between neighbouring polygons paint the same
## white twice for no cost worth naming.
func _rasterise() -> void:
	var vertices := PackedVector3Array()
	if _navmesh != null:
		vertices = _navmesh.get_vertices()
	if vertices.is_empty():
		_bounds = AABB()
		_outline = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		_outline.fill(Color(1.0, 1.0, 1.0, 0.0))
		return

	var low := vertices[0]
	var high := vertices[0]
	for vertex: Vector3 in vertices:
		low = low.min(vertex)
		high = high.max(vertex)
	_bounds = AABB(low, high - low)

	var span_x := maxf(_bounds.size.x, 0.01)
	var span_z := maxf(_bounds.size.z, 0.01)
	var longest := maxf(span_x, span_z)
	var width := maxi(1, int(round(float(OUTLINE_LONG_SIDE) * span_x / longest)))
	var height := maxi(1, int(round(float(OUTLINE_LONG_SIDE) * span_z / longest)))
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))

	for index in _navmesh.get_polygon_count():
		var poly := _navmesh.get_polygon(index)
		if poly.size() < 3:
			continue
		var first := _to_pixel(vertices[poly[0]], width, height)
		for k in range(1, poly.size() - 1):
			_triangle(image, first, _to_pixel(vertices[poly[k]], width, height),
				_to_pixel(vertices[poly[k + 1]], width, height))
	_outline = image


func _to_pixel(point: Vector3, width: int, height: int) -> Vector2:
	var u := (point.x - _bounds.position.x) / maxf(_bounds.size.x, 0.01)
	var v := (point.z - _bounds.position.z) / maxf(_bounds.size.z, 0.01)
	return Vector2(u * float(width - 1), v * float(height - 1))


## A filled triangle, by the oldest method there is: walk its bounding box and
## keep the pixels whose barycentric coordinates are all non-negative. A few
## hundred small triangles once per match does not deserve anything cleverer.
static func _triangle(image: Image, a: Vector2, b: Vector2, c: Vector2) -> void:
	var area := (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
	if absf(area) < 0.0001:
		return
	var low_x := maxi(0, int(floor(minf(a.x, minf(b.x, c.x)))))
	var high_x := mini(image.get_width() - 1, int(ceil(maxf(a.x, maxf(b.x, c.x)))))
	var low_y := maxi(0, int(floor(minf(a.y, minf(b.y, c.y)))))
	var high_y := mini(image.get_height() - 1, int(ceil(maxf(a.y, maxf(b.y, c.y)))))
	var white := Color(1.0, 1.0, 1.0, 1.0)
	for y in range(low_y, high_y + 1):
		for x in range(low_x, high_x + 1):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var w0 := ((b.x - a.x) * (p.y - a.y) - (p.x - a.x) * (b.y - a.y)) / area
			var w1 := ((p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)) / area
			if w0 >= 0.0 and w1 >= 0.0 and w0 + w1 <= 1.0:
				image.set_pixel(x, y, white)
