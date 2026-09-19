class_name JumpLinks
extends RefCounted
## The holes in the navmesh a Bog can cross anyway.
##
## A baked navmesh knows about ground you can walk on and nothing at all about
## ground you can *jump* to: every ledge, every gap between two containers and
## every drop off a deck comes out as a border with empty space past it, and a
## path solved over that mesh walks all the way round the map rather than take
## a step off a crate. On a parkour map that is not a slightly long route, it is
## the wrong route — the line would teach the player the opposite of how the map
## is played.
##
## So after the bake, every border edge is walked, sampled, and asked two
## questions at each sample:
##
##   is there ground across the gap in front of it?  — a jump.
##   is there ground straight down past this edge?   — a drop.
##
## Both may answer, and a link is two-way only when the leap home also makes
## it: a three-metre drop is one way, a knee-high one is a step you can take
## back.
##
## What can be jumped is `JumpArc`, which is the same arithmetic
## `tools/parkour_report.gd` holds the maps to, so the line never promises a
## leap the checker calls impossible.
##
## Cosmetic, like everything else under `scripts/world/nav`: the links exist on
## one client's navigation map to shape one client's drawn line, they are built
## per peer and never replicated, exactly as a ragdoll is (D-010), and no rule
## reads them (D-007).

## How finely a border is sampled. 1.5 m is a little under the width of the
## narrowest gap worth linking, so no crossable gap is skipped between samples;
## the edge's midpoint is always sampled too, because a short edge — a single
## crate's lip — would otherwise only ever get its own start point.
const SAMPLE_STEP := 1.5

## A border with a wall standing on it is not a ledge. The probe starts a shin's
## height up so it clears the lip of the floor itself, and reaches a stride out.
const WALL_PROBE_UP := 0.3
const WALL_PROBE_LENGTH := 0.6

## A drop is looked for just past the lip, from the same shin height, and as far
## down as a Bog can fall before the landing is the interesting part.
const DROP_OUT := 0.9
const DROP_DEPTH := 14.0
## The floor the ray found has to *be* navmesh, not a windowsill the baker
## refused. Thirty centimetres is the agent's climb.
const DROP_SNAP := 0.3
## A drop is cheap but not free: it is one way, and a route that takes six of
## them to save a corner reads as falling down a mountain.
const DROP_COST := 1.2

## How far across a gap to look, and how finely. Under a metre is not a gap, it
## is navmesh noise at the cell size; six metres is past a big leap on the flat.
const JUMP_MIN := 1.0
const JUMP_MAX := 6.0
const JUMP_STEP := 0.5
## How far the nearest navmesh point may be from where we looked, in plan. The
## sideways slack has to be small, or a probe fired out over a courtyard snaps
## back onto the edge it started from and calls that a jump.
const LAND_SNAP_XZ := 0.4

## Two links whose ends are both within a metre of another's are the same link
## drawn twice — the sampler finds a wide ledge again from every sample along
## it. And a ceiling, because a navigation map carrying thousands of links costs
## more to path over than the path is worth.
const DEDUPE := 1.0
const MAX_LINKS := 800

const LAYER_WORLD := 1


## Build every link `navmesh` needs into `parent`, and say how many.
##
## `parent` must be in the tree at the identity transform: link positions are
## local, the navmesh's vertices are in the region's space, and `NavBake` builds
## the region at identity — so the two are the same numbers and nothing is
## converted. The region must also already be on the navigation map, because the
## jump probe asks the map where the nearest walkable point is and that is only
## an answer after the map has synced.
static func build(navmesh: NavigationMesh, space_state: PhysicsDirectSpaceState3D,
		parent: Node3D) -> int:
	if navmesh == null or space_state == null or parent == null:
		return 0
	if not parent.is_inside_tree():
		return 0
	var map: RID = parent.get_world_3d().navigation_map
	if not map.is_valid():
		return 0

	var vertices := navmesh.get_vertices()
	if vertices.is_empty():
		return 0

	# Every edge, and how many polygons claim it. An edge claimed once is the
	# outside of the walkable world; an edge claimed twice is an interior seam a
	# path can already walk straight across.
	var seen: Dictionary = {}
	var owner_centroid: Dictionary = {}
	for index in navmesh.get_polygon_count():
		var poly := navmesh.get_polygon(index)
		if poly.size() < 3:
			continue
		var centroid := Vector3.ZERO
		for vertex_index: int in poly:
			centroid += vertices[vertex_index]
		centroid /= float(poly.size())
		for i in poly.size():
			var a: int = poly[i]
			var b: int = poly[(i + 1) % poly.size()]
			var key := Vector2i(mini(a, b), maxi(a, b))
			seen[key] = int(seen.get(key, 0)) + 1
			owner_centroid[key] = centroid

	var starts := PackedVector3Array()
	var ends := PackedVector3Array()
	for key: Vector2i in seen:
		if int(seen[key]) != 1:
			continue
		if starts.size() >= MAX_LINKS:
			break
		_walk_border(vertices[key.x], vertices[key.y], owner_centroid[key], map,
			space_state, starts, ends)

	for i in starts.size():
		var link := NavigationLink3D.new()
		link.name = "Link%d" % i
		link.start_position = starts[i]
		link.end_position = ends[i]
		var rise := ends[i].y - starts[i].y
		var flat := Vector2(ends[i].x - starts[i].x, ends[i].z - starts[i].z).length()
		# Two way only when the leap home also makes it: every drop, and every
		# jump up onto something out of reach from above, stays one way.
		link.bidirectional = _reachable(flat, -rise)
		var is_drop := not link.bidirectional and rise < -DROP_SNAP
		link.travel_cost = DROP_COST if is_drop else JumpArc.LEAP_COST
		parent.add_child(link)
	return starts.size()


## Sample one border edge and add whatever a Bog could do from it.
static func _walk_border(from: Vector3, to: Vector3, centroid: Vector3, map: RID,
		space_state: PhysicsDirectSpaceState3D, starts: PackedVector3Array,
		ends: PackedVector3Array) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	# The outward normal: perpendicular to the edge in plan, pointing away from
	# the polygon that owns it. Height is deliberately dropped — a jump is aimed
	# across the map, not along the slope of the lip it leaves.
	var along := to - from
	along.y = 0.0
	if along.length() < 0.001:
		return
	along = along.normalized()
	var outward := Vector3(along.z, 0.0, -along.x)
	if outward.dot((from + to) * 0.5 - centroid) < 0.0:
		outward = -outward

	var offsets: Array[float] = [length * 0.5]
	var walked := 0.0
	while walked <= length:
		offsets.append(walked)
		walked += SAMPLE_STEP

	for offset: float in offsets:
		if starts.size() >= MAX_LINKS:
			return
		_sample(from.lerp(to, clampf(offset / length, 0.0, 1.0)), outward, map,
			space_state, starts, ends)


## Both questions are asked at every sample, and both may answer.
##
## An earlier pass took the drop and stopped, on the grounds that it is the
## cheaper probe — and that is exactly wrong on the maps this is for. Standing
## on a container with a three-metre floor below and the next container an easy
## hop across, the drop answers first and the hop is never found, so the route
## climbs down, walks round and climbs back up: the line teaching the opposite
## of how the map is played. The jump is scanned first so it survives the link
## cap, and the drop is offered beside it; which one is cheaper is a question
## for the pathfinder, which is what `travel_cost` is for.
static func _sample(at: Vector3, outward: Vector3, map: RID,
		space_state: PhysicsDirectSpaceState3D, starts: PackedVector3Array,
		ends: PackedVector3Array) -> void:
	# A wall standing on the border is not a ledge, and most of a navmesh's
	# outline is walls. This one ray is what keeps the link count in the
	# hundreds instead of the tens of thousands.
	var shin := at + Vector3.UP * WALL_PROBE_UP
	if _hits(space_state, shin, shin + outward * WALL_PROBE_LENGTH):
		return
	_try_jump(at, outward, map, starts, ends)
	_try_drop(at, outward, map, space_state, starts, ends)


## Across whatever the gap is. The nearest accepted distance wins and the scan
## stops there: the near lip is what a player aims at, and every longer probe
## from the same sample lands on the same slab further in.
##
## Short probes take care of themselves. A metre out over nothing, the nearest
## navmesh point is the border we are standing on, so the sideways test fails
## by the whole probe distance — no special case needed for "the gap is not a
## gap yet".
static func _try_jump(at: Vector3, outward: Vector3, map: RID,
		starts: PackedVector3Array, ends: PackedVector3Array) -> void:
	var distance := JUMP_MIN
	while distance <= JUMP_MAX + 0.001:
		var probe := at + outward * distance
		var landing := NavigationServer3D.map_get_closest_point(map, probe)
		var sideways := Vector2(landing.x - probe.x, landing.z - probe.z).length()
		if sideways < LAND_SNAP_XZ and _reachable(distance, landing.y - at.y):
			_add(starts, ends, at, landing)
			return
		distance += JUMP_STEP


## Straight off the lip. The floor the ray finds has to be navmesh the baker
## agreed to, or a route would be sent onto a windowsill.
static func _try_drop(at: Vector3, outward: Vector3, map: RID,
		space_state: PhysicsDirectSpaceState3D, starts: PackedVector3Array,
		ends: PackedVector3Array) -> void:
	var over := at + outward * DROP_OUT + Vector3.UP * WALL_PROBE_UP
	var floor_hit := _ray(space_state, over, over + Vector3.DOWN * DROP_DEPTH)
	if floor_hit.is_empty():
		return
	var landing: Vector3 = floor_hit["position"]
	if landing.y >= at.y - DROP_SNAP:
		return
	if NavigationServer3D.map_get_closest_point(map, landing).distance_to(landing) > DROP_SNAP:
		return
	_add(starts, ends, at, landing)


## Can a Bog leap `flat` metres out and `rise` metres up? The capsule's radius
## comes off the gap because the leading edge has to clear the lip and not the
## centre — the same allowance `parkour_report` makes when it classifies a gap.
static func _reachable(flat: float, rise: float) -> bool:
	if rise > JumpArc.apex():
		return false
	var reach := JumpArc.leap_reach(rise)
	return reach >= 0.0 and flat - Bog.CAPSULE_RADIUS <= reach


static func _add(starts: PackedVector3Array, ends: PackedVector3Array,
		from: Vector3, to: Vector3) -> void:
	if starts.size() >= MAX_LINKS:
		return
	for i in starts.size():
		if starts[i].distance_to(from) <= DEDUPE and ends[i].distance_to(to) <= DEDUPE:
			return
		if starts[i].distance_to(to) <= DEDUPE and ends[i].distance_to(from) <= DEDUPE:
			return
	starts.append(from)
	ends.append(to)


static func _ray(space_state: PhysicsDirectSpaceState3D, from: Vector3,
		to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space_state.intersect_ray(query)


static func _hits(space_state: PhysicsDirectSpaceState3D, from: Vector3,
		to: Vector3) -> bool:
	return not _ray(space_state, from, to).is_empty()
