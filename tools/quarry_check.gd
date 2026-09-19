extends SceneTree
## Is Twin Quarry *even*? Development tool, not shipped.
##
## The map is deliberately not symmetric — the north-west corner is a solid
## spoil bench with a tunnel through it and the south-east is three open
## terraces — so "look at it, the halves match" is not an argument that can be
## made about this map the way it can about Lantern Wharf. What replaces it is
## four measurements, each of which is the thing a player would actually
## complain about:
##
##   **bases**    the two bases are built by one function called twice, so they
##                have to be congruent. This re-derives it from the *built
##                scene* rather than from the source: every declared landing in
##                each base's corner is turned half a turn about the origin and
##                has to land on one of the other base's, to the millimetre. A
##                refactor that accidentally gives one base an extra step fails
##                here and nowhere else.
##   **runs**     the flag run. For each letter, the distance a carrier covers
##                from that card to base 1 and to base 2, walked as a polyline
##                through the map's own route graph rather than as a straight
##                line — a straight line through a monolith is not a run. The
##                two have to agree within `RUN_TOLERANCE`.
##   **ground**   every spawn pad has floor under it and a Bog-shaped capsule
##                fits standing on it, in the physics the match will use. This
##                overlaps `preview_map`'s check and is kept because it is two
##                lines and because this tool is the one somebody runs after
##                moving a pad.
##   **letters**  every letter home point has floor under it too, at the height
##                the scene claims, because a card that settles two metres
##                under a terrace is a card nobody can pick up.
##
## A `SceneTree` script rather than a scene, like `snapshot.gd` and unlike the
## map previews: it renders nothing, so it wants the dummy rasteriser and a
## process that ends when the numbers are printed.
##
## Usage:
##   Godot --headless --path . --script tools/quarry_check.gd
##
## Prints a line per measurement and `quarry_check: PASS` or `FAIL`.

const MAP := "res://scenes/world/maps/quarry.tscn"
const LAYER_WORLD := 1

## What a Bog is, physically. Taken from `Bog` rather than typed, so a change to
## the character's size fails this check instead of quietly invalidating it.
const CAPSULE_RADIUS := Bog.CAPSULE_RADIUS
const CAPSULE_HEIGHT := Bog.STAND_HEIGHT
## Where the capsule's centre sits above the Bog's origin — the offset on the
## `Collision` node in `bog.tscn`.
const CAPSULE_LIFT := 0.775

## How far below a pad a floor is allowed to be before the pad counts as hanging
## in the air. The markers are lifted 0.12 m, so this is a wide margin.
const FLOOR_REACH := 2.5
const FLOOR_LIFT := 2.0

## How far two landings may be apart and still be called the same landing turned
## half a turn. A millimetre: these are the same numbers negated, so anything
## bigger than float noise is a real difference.
const CONGRUENT := 0.001

## How far apart the two teams' runs to one card may be, as a fraction. Three
## per cent of a thirty-metre run is under a metre, which is inside the distance
## a player covers deciding which way to go.
const RUN_TOLERANCE := 0.03

## Where team 1's base is, and how far out from it counts as "near the base"
## for the cover count. Twenty metres is a little over the distance a thrown
## spear covers, which is the radius a defender actually contests.
const BASE := Vector2(-17.75, -17.75)
const COVER_REACH := 20.0
## How many more pieces of cover one team may have than the other. Two, because
## a map that is asymmetric on purpose will never come out dead level and a
## difference of one block at twenty metres is not something a player can feel.
const COVER_SLACK := 2.0

## The waypoints a carrier is assumed to move between: every one is a place the
## route graph actually bends, and the edges below say which are joined. A
## straight line is the wrong measure on a map with a hole and a monolith in the
## middle of it, and a full navmesh is the wrong tool for four numbers.
const WAYPOINTS := {
	"base1": Vector2(-17.75, -17.75),
	"base2": Vector2(17.75, 17.75),
	# The foot of each base's two haul ramps.
	"r1w": Vector2(-22.5, 0.0), "r1s": Vector2(0.0, -22.5),
	"r2e": Vector2(22.5, 0.0), "r2n": Vector2(0.0, 22.5),
	# The four bands, at their middles. **These four are on the axes and at one
	# radius on purpose.** The graph has to be closed under the reflection the
	# map's bisector features are built on — x = -z, which maps (x, z) to
	# (-z, -x) — or the run to a card that *is* on the bisector comes out
	# different for the two teams because of where the waypoints were typed,
	# which is a bug in this file being reported as a bug in the map. It was:
	# the first pass had "west" at (-20, 4) and "north" at (0, 18.5) and
	# measured G as 7.7% unfair.
	"west": Vector2(-20.5, 0.0), "north": Vector2(0.0, 20.5),
	"east": Vector2(20.5, 0.0), "south": Vector2(0.0, -20.5),
	# The tunnel: its two mouths and the chamber between them.
	"adit_s": Vector2(-17.8, 9.4), "adit_c": Vector2(-17.8, 17.8),
	"adit_e": Vector2(-9.4, 17.8),
	# The shaft's lip, one corner each, and the two catwalk ends.
	"lip_nw": Vector2(-9.5, 9.5), "lip_se": Vector2(9.5, -9.5),
	"walk_w": Vector2(-8.7, 5.0), "walk_e": Vector2(8.7, 5.0),
	"walk_w2": Vector2(-8.7, -5.0), "walk_e2": Vector2(8.7, -5.0),
	# The terraces, at the card and at the way onto them.
	"terr_foot": Vector2(11.0, -11.0), "terr_top": Vector2(21.0, -21.0),
}
## Which waypoints are joined, and therefore what a carrier may walk. Every edge
## here is a stretch of ground with nothing in the way of it taller than a Bog
## can climb; the cost of an edge is its length.
const EDGES: Array[Array] = [
	["base1", "r1w"], ["base1", "r1s"],
	["base2", "r2e"], ["base2", "r2n"],
	["r1w", "west"], ["r1s", "south"], ["r2e", "east"], ["r2n", "north"],
	# The tunnel, and its two mouths onto the two bands it joins.
	["west", "adit_s"], ["adit_s", "adit_c"],
	["adit_c", "adit_e"], ["adit_e", "north"],
	# Round the outside of the spoil bench rather than through it.
	["west", "lip_nw"], ["lip_nw", "north"],
	["south", "lip_se"], ["lip_se", "east"],
	# Across the hole, both catwalks.
	["lip_nw", "walk_w"], ["walk_w", "walk_e"], ["walk_e", "east"],
	["lip_se", "walk_e2"], ["walk_e2", "walk_w2"], ["walk_w2", "west"],
	# Up onto the terraces from the pit floor.
	["lip_se", "terr_foot"], ["east", "terr_foot"], ["terr_foot", "terr_top"],
	["south", "terr_foot"],
]

var _map: StaticMap
var _checks: int = 0
var _failures: int = 0


## How many physics ticks to let run before anything is asked to stand on the
## map. The collision bodies are added during `_ready`; they are not in the
## space until the server has stepped.
const SETTLE := 4

var _ticks: int = 0
var _done: bool = false


func _initialize() -> void:
	Engine.max_fps = int(ProjectSettings.get_setting(
		"physics/common/physics_ticks_per_second", 60))
	var packed := load(MAP) as PackedScene
	if packed == null:
		push_error("quarry_check: could not load %s" % MAP)
		_done = true
		return
	_map = packed.instantiate() as StaticMap
	root.add_child(_map)


func _process(_delta: float) -> bool:
	if _done:
		return true
	_ticks += 1
	if _ticks < SETTLE:
		return false
	_done = true
	_run()
	return true


func _run() -> void:
	_check_bases()
	_check_runs()
	_check_cover()
	_check_ground()
	_check_letters()

	print("quarry_check: %d checks, %d failures" % [_checks, _failures])
	print("quarry_check: %s" % ("PASS" if _failures == 0 else "FAIL"))


func _say(ok: bool, line: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s %s" % ["    " if ok else "FAIL", line])


# ------------------------------------------------------------------- bases ---

## Every landing in one base's corner, turned half a turn, has to be a landing
## in the other's.
##
## The comparison is on the *declared* records rather than on the geometry,
## which is the right level: `platforms` is what the parkour report, the capture
## layout and every other consumer believes about this map, so two bases that
## are congruent in stone and not in records are two bases that play the same
## and are checked differently — which is worse than an honest asymmetry.
func _check_bases() -> void:
	var one: Array[Vector3] = []
	var two: Array[Vector3] = []
	# `Platform` is an inner class of `StaticMap`, so it has no global name and
	# the loop variable stays untyped; `position` is read off it either way.
	for pad in _map.platforms:
		var at: Vector3 = pad.centre
		if _in_base(at, -1.0):
			one.append(at)
		elif _in_base(at, 1.0):
			two.append(at)
	_say(one.size() == two.size(),
		"base landings: team 1 has %d, team 2 has %d" % [one.size(), two.size()])
	var worst := 0.0
	for at: Vector3 in one:
		var want := Vector3(-at.x, at.y, -at.z)
		var near := INF
		for other: Vector3 in two:
			near = minf(near, want.distance_to(other))
		worst = maxf(worst, near)
	_say(worst <= CONGRUENT,
		"base landings congruent under a half turn: worst gap %.4f m" % worst)


## Whether a landing belongs to the base on the half `sign` names.
##
## A base is three things and this has to catch all of them and nothing else:
## the 12.5 m bench square in the corner, the wall standing on it, and the two
## haul ramps — which run **flush against the cliff**, from the pit floor at the
## middle of a side all the way up to the bench. So the test is "in the corner
## square, or in one of the two three-metre strips along the rim that the ramps
## occupy", and the strips stop at the middle of the map so the far team's ramp
## is not counted as this one's.
static func _in_base(at: Vector3, sign: float) -> bool:
	var x := sign * at.x
	var z := sign * at.z
	var inner := QuarryMap.BENCH_INNER
	if x >= inner and z >= inner:
		return true
	var strip := QuarryMap.HALF - QuarryMap.RAMP_WIDTH
	if z >= strip and x >= -0.5:
		return true
	return x >= strip and z >= -0.5


# ------------------------------------------------------------------- cover ---

## How much there is to hide behind, and how much high ground there is, within
## reach of each base.
##
## This is the half of "even" the route graph cannot speak to, and it is read
## straight off `platforms` — the built map's own declaration of what can be
## stood on — rather than off anything typed in this file. Two bases with equal
## flag runs and nine blocks outside one of them and two outside the other are
## not an even map, and nothing else here would notice.
func _check_cover() -> void:
	var near := [0, 0]
	var high := [0, 0]
	for pad in _map.platforms:
		var at: Vector3 = pad.centre
		var zone: String = pad.zone
		# A base's own bench, wall and ramps are the base, not cover outside it.
		if zone == "bench" or zone == "wall" or zone == "ramp":
			continue
		for team: int in 2:
			var base := BASE * (1.0 if team == 0 else -1.0)
			var d := Vector2(at.x, at.z).distance_to(base)
			if d <= COVER_REACH:
				near[team] += 1
				if at.y >= 2.5:
					high[team] += 1
	_say(absf(float(near[0] - near[1])) <= COVER_SLACK,
		"cover within %.0f m of a base: team 1 %d, team 2 %d" % [
			COVER_REACH, near[0], near[1]])
	_say(absf(float(high[0] - high[1])) <= COVER_SLACK,
		"high ground within %.0f m of a base: team 1 %d, team 2 %d" % [
			COVER_REACH, high[0], high[1]])


# -------------------------------------------------------------------- runs ---

## The flag run to each card, for each team, walked through `EDGES`.
func _check_runs() -> void:
	var letters := _map.letter_points()
	var names := ["G", "U", "B"]
	for i: int in letters.size():
		var card := Vector2(letters[i].x, letters[i].z)
		var near := _nearest(card)
		var one := _walk(near, "base1") + card.distance_to(WAYPOINTS[near])
		var two := _walk(near, "base2") + card.distance_to(WAYPOINTS[near])
		var spread := absf(one - two) / maxf(1.0, minf(one, two))
		_say(spread <= RUN_TOLERANCE,
			"%s run: team 1 %.1f m, team 2 %.1f m, %.1f%% apart (via %s)" % [
				names[i] if i < names.size() else str(i), one, two,
				spread * 100.0, near])


## The waypoint a card is picked up at: the nearest one, which is the honest
## answer as long as every card is actually placed on a route.
static func _nearest(at: Vector2) -> String:
	var best := ""
	var near := INF
	for key: String in WAYPOINTS:
		var d: float = at.distance_to(WAYPOINTS[key])
		if d < near:
			near = d
			best = key
	return best


## Dijkstra over `EDGES`, in metres. Small enough that the naive version is the
## right one: twenty-two nodes and twenty-seven edges.
static func _walk(from: String, to: String) -> float:
	var cost := {}
	for key: String in WAYPOINTS:
		cost[key] = INF
	cost[from] = 0.0
	var open: Array[String] = [from]
	while not open.is_empty():
		open.sort_custom(func(a: String, b: String) -> bool: return cost[a] < cost[b])
		var here: String = open.pop_front()
		for edge: Array in EDGES:
			for side: int in 2:
				if String(edge[side]) != here:
					continue
				var there := String(edge[1 - side])
				var step: float = WAYPOINTS[here].distance_to(WAYPOINTS[there])
				if cost[here] + step < cost[there] - 0.0001:
					cost[there] = cost[here] + step
					open.append(there)
	return float(cost[to])


# ------------------------------------------------------------------ ground ---

## Every spawn pad: a ray down that has to find a floor, and a Bog-sized capsule
## that has to fit where the Bog will stand.
func _check_ground() -> void:
	var space := _map.get_world_3d().direct_space_state
	var spawns := _map.spawn_points()
	_say(spawns.size() == 8, "spawn pads: %d" % spawns.size())
	for i: int in spawns.size():
		var at := spawns[i].origin
		var down := PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * FLOOR_LIFT, at + Vector3.DOWN * FLOOR_REACH)
		down.collision_mask = LAYER_WORLD
		var hit := space.intersect_ray(down)
		if hit.is_empty():
			_say(false, "pad %d at %v: no floor under it" % [i, at])
			continue
		var floor_y: float = (hit["position"] as Vector3).y
		var shape := PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = CAPSULE_RADIUS
		capsule.height = CAPSULE_HEIGHT
		shape.shape = capsule
		# Five centimetres over the floor the ray found. A capsule whose bottom
		# is exactly on the floor plane reports a touch on every pad, which is
		# what this check did on seven of eight before the clearance was added.
		shape.transform = Transform3D(Basis.IDENTITY,
			Vector3(at.x, floor_y + CAPSULE_LIFT + 0.05, at.z))
		shape.collision_mask = LAYER_WORLD
		var stuck := space.intersect_shape(shape, 1)
		_say(stuck.is_empty() and absf(at.y - floor_y) < FLOOR_REACH,
			"pad %d at (%.1f, %.1f): floor %.2f, capsule %s" % [
				i, at.x, at.z, floor_y, "clear" if stuck.is_empty() else "BURIED"])


## Every letter home point, the same way: a card that settles inside a terrace
## is a card nobody picks up.
func _check_letters() -> void:
	var space := _map.get_world_3d().direct_space_state
	var letters := _map.letter_points()
	for i: int in letters.size():
		var at := letters[i]
		var down := PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * 3.0, at + Vector3.DOWN * 3.0)
		down.collision_mask = LAYER_WORLD
		var hit := space.intersect_ray(down)
		if hit.is_empty():
			_say(false, "letter %d at %v: no floor" % [i, at])
			continue
		var floor_y: float = (hit["position"] as Vector3).y
		var on := "?"
		var body: Variant = hit["collider"]
		if body is Node:
			on = (body as Node).name
		_say(absf(floor_y - at.y) < 0.6,
			"letter %d at (%.1f, %.1f): declared y %.2f, floor %.2f on %s" % [
				i, at.x, at.z, at.y, floor_y, on])
