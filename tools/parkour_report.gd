extends Node3D
## Can you actually get up there? Development tool, not shipped.
##
## Kopje Crossing is a hundred and twenty-three rock platforms at heights from
## 0.4 m to 9.5 m, and the only thing that makes it a map rather than a pile is
## that every one of them is reachable from the ground. That is not something a
## render can show and it is certainly not something a coordinate can: the
## question "is this gap crossable" is a question about the Bog's jump arc, and
## the arc is five constants in `bog.gd` and one in `project.godot`.
##
## So this rebuilds the arc from those constants, builds the whole reachability
## graph out of the map's `StaticMap.platforms`, and walks it from the ground. Anything it
## cannot reach is named. It also checks the *physics* against the table — a ray
## down onto layer 1 from every landing and a Bog-sized capsule standing on it —
## because the table is what the graph believes and the trimesh is what a player
## will actually meet, and a slab that is 30 cm lower than its record says is a
## gap that is 30 cm longer than the checker thinks.
##
## Three ways across a gap, named after what the player does:
##
##   hop   jump at run speed.
##   leap  jump, then spend the dive at the apex. The staple.
##   big   jump, then spend the dive on the very next tick — the dive is legal
##         from the tick after the jump because the jump zeroes `_coyote`. Longer
##         and much harder to aim, so the layout uses these as shortcuts and
##         never as the only way to somewhere.
##
## Usage:
##   Godot --path . --resolution 1000x1000 --script tools/snapshot.gd -- \
##       res://tools/parkour_report.tscn out.png <ticks> [top|side|iso] [map=res://map.tscn]
##
## Kopje Crossing unless `map=` names another built map. What each map is held
## to — how many landings, whether it needs dive shortcuts, how long a sightline
## it allows — is in `EXPECT`, because a rock garden and a box yard want
## different numbers and one threshold in a shared tool would be wrong for one
## of them (the same argument D-042 made about `preview_map`'s sightline).
##
## Everything is printed before the render, so this is also a headless check —
## `tools/smoke_test.sh` greps it for `parkour_report: PASS`.

const DEFAULT_MAP := "res://scenes/world/maps/safari.tscn"

## Per map, by scene path:
##
##   min_platforms   fewer landings than this and the table did not build
##   min_big_edges   how many big-dive shortcuts the layout must offer
##   summit_zone     if set, the landing labelled "summit" must leap to a
##                   landing in this zone (Kopje Crossing's prize, D-042)
##   sightline       if above zero, the longest line between two Bogs' eyes
##                   standing on the ground may not be longer than this
##   roof_sightline  the same, with at least one of the two on a landing
##   reach           half the width of the square the ASCII map and the top
##                   camera frame, in metres
##   grid            the ASCII map's cell, in metres
##   overboard       if true, the map stands on nothing: every edge of the
##                   ground has nothing under it past the rail down to the
##                   void, and the void is under the lowest landing (D-057)
const EXPECT := {
	"res://scenes/world/maps/safari.tscn": {
		"min_platforms": 110, "min_big_edges": 6, "summit_zone": "ridge",
		"sightline": 0.0, "roof_sightline": 0.0, "reach": 36.0, "grid": 2.0,
	},
	"res://scenes/world/maps/wharf.tscn": {
		"min_platforms": 20, "min_big_edges": 0, "summit_zone": "",
		"sightline": 25.0, "roof_sightline": 26.0, "reach": 20.0, "grid": 1.0,
	},
	"res://scenes/world/maps/yacht.tscn": {
		"min_platforms": 60, "min_big_edges": 0, "summit_zone": "",
		"sightline": 21.0, "roof_sightline": 38.0, "reach": 37.0, "grid": 2.0,
		"overboard": true,
	},
}

## The sightline scan's grid, and where on a Bog the line runs between. Eye to
## eye is the fair question: a Bog who can see another's eyes can be seen back.
const SIGHT_STEP := 2.0
const EYE := 1.45

## How far past the edge of the deck the overboard check looks for anything to
## land on: a rail's thickness and a stride out. And how far under the lowest
## floor the void may sit — a fall of more than a few metres into water is a
## Bog waiting to be told it is dead.
const OVERBOARD := 1.0
const VOID_DEPTH := 5.0

## The movement model, read off `Bog` and `ProjectSettings` rather than typed, so
## a change to the character's jump fails this check instead of quietly
## invalidating every gap on the map.
const RUN := Bog.RUN_SPEED
const JUMP := Bog.JUMP_VELOCITY
const DIVE_FORWARD := Bog.DIVE_FORWARD_SPEED
const DIVE_UP := Bog.DIVE_UP_VELOCITY
## The one number here that is a literal, because it is a literal in
## `Bog._apply_gravity` too: falling is 1.35x as fast as rising, which is what
## makes a jump feel decisive. If that ever becomes a constant, name it here.
const FALL_MULTIPLIER := 1.35

const CAPSULE_RADIUS := Bog.CAPSULE_RADIUS
const CAPSULE_HEIGHT := Bog.STAND_HEIGHT
## Where the capsule's centre sits above the Bog's feet — the offset on the
## `Collision` node in `bog.tscn`. A test at the landing itself would be a
## capsule buried half a metre in the rock and would fail on every platform.
const CAPSULE_LIFT := 0.775

const LAYER_WORLD := 1

## How far the ray is allowed to disagree with the table before the platform is
## called wrong. A slab is placed by its top, so this should be millimetres; 0.30
## is wide enough to allow for the lip of a rounded kit mesh and narrow enough
## that a slab resting on the wrong pillar fails.
const TOP_TOLERANCE := 0.30
const RAY_ABOVE := 2.0
const RAY_BELOW := 1.5

## Take off from 0.1 m inside the near edge and land with 0.1 m of the far lip to
## spare — a landing that needs the very edge of the slab is a landing that
## works in a checker and not in a match. The 0.38 is the capsule's radius: the
## Bog's leading edge has to clear the lip, not its centre.
const EDGE_MARGIN := 0.1
const LANDING_MARGIN := 0.2
const LIP_CLEARANCE := 0.1

## What the ground can be jumped onto from. Flat ground has no edge to take off
## from and no radius, so these are stated rather than derived: 1.3 m is a lip
## you can hop onto from a standing run, 1.9 is one you have to dive for.
const GROUND_HOP := 1.3
const GROUND_LEAP := 1.9
const GROUND_BIG := 3.5

## (`min_platforms` and `min_big_edges` are in `EXPECT`. Big leaps are
## shortcuts: on Kopje Crossing a map with none is a map where the dive's full
## range is never worth learning, so there it is a floor, not a target.)

const SPAWN_PLATFORM_KEEPOUT := 3.5
const SPAWN_TRUNK_KEEPOUT := 4.0

## The route the tree is counted along: hops cost 1 and a leap costs a little
## over two of them.
##
## This is a model of the player and not of the geometry, and it has to be one:
## a plain breadth-first walk minimises the *number* of jumps, which on a map
## this dense means it reaches for the longest edge available every time and
## reports a map made almost entirely of leaps. Weighting a leap above two hops
## says the opposite and truer thing — you hop while hopping will do, and you
## commit to a dive when it will not — and the tree that comes out is the route
## a player actually finds.
const LEAP_COST := 2.25

const VIEWS := ["top", "side", "iso"]

## The ASCII map's grid is `EXPECT`'s `grid`: two metres is fine enough to see a
## spiral step and coarse enough that a 96 m plateau fits in a terminal, and a
## 36 m box yard wants one.

var _view: String = "top"
var _map_path: String = DEFAULT_MAP
var _expect: Dictionary = {}
var _grid_step: float = 2.0
var _map: StaticMap
var _platforms: Array[StaticMap.Platform] = []
var _spawns: Array[Transform3D] = []
var _edges: Dictionary = {}      ## Vector2i(from, to) -> "hop" | "leap" | "big"
var _tree: Dictionary = {}       ## to -> Vector2i(from, class index) as Vector2i
var _checks: int = 0
var _failures: int = 0
var _reported: bool = false

## Derived once from the constants above. `_apex` is how high the jump gets,
## `_dive_apex` how high a jump plus a dive at the apex gets, `_tick_apex` how
## high a jump plus a dive one tick later gets.
var _gravity: float = 24.0
var _apex: float = 0.0
var _dive_apex: float = 0.0
var _tick_apex: float = 0.0
var _tick_start: float = 0.0
var _tick_forward: float = 0.0
var _tick_rise: float = 0.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if VIEWS.has(arg):
			_view = arg
		elif arg.begins_with("map="):
			_map_path = arg.trim_prefix("map=")
	_expect = EXPECT.get(_map_path, EXPECT[DEFAULT_MAP])
	_grid_step = float(_expect["grid"])

	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))
	_apex = JUMP * JUMP / (2.0 * _gravity)
	_dive_apex = _apex + DIVE_UP * DIVE_UP / (2.0 * _gravity)
	# One physics tick after the jump the Bog has risen a little and lost a
	# little speed; the dive then adds its whole upward kick to what is left.
	var tick := 1.0 / float(ProjectSettings.get_setting(
		"physics/common/physics_ticks_per_second", 60))
	var after := (JUMP - _gravity * tick) + DIVE_UP
	_tick_start = JUMP * tick
	_tick_forward = RUN * tick
	_tick_rise = after / _gravity
	_tick_apex = _tick_start + after * after / (2.0 * _gravity)

	var packed := load(_map_path) as PackedScene
	if packed == null:
		_fail("the map scene loads (%s)" % _map_path)
		return
	var instanced := packed.instantiate()
	# Renamed exactly as `arena.gd` renames it, so the map's own build log line
	# says the same thing here as it does in a match.
	instanced.name = "Map"
	add_child(instanced)
	_map = instanced as StaticMap
	if _map == null:
		_fail("the map's root is a StaticMap")
		return
	if _map.platforms.is_empty():
		_fail("the map declares its platforms")
		return
	_platforms = _map.platforms
	_spawns = _map.spawn_points()
	print("parkour_report: %s — %d platforms, %d triangles, %d shapes, built in %d ms" % [
		_map_path, _platforms.size(), _map.triangles, _map.shapes, _map.build_msec])


## Everything below needs the map's static body to be in the broadphase, and
## that does not happen until the physics has ticked at least once.
func _physics_process(_delta: float) -> void:
	if _reported:
		return
	if Engine.get_physics_frames() < 3:
		return
	_reported = true

	_check_counts()
	_check_physics()
	_build_graph()
	_check_reachability()
	_check_off_limits()
	_check_spawns()
	_check_sightlines()
	_check_overboard()
	_print_height_map()
	_draw()
	_build_camera()

	print("parkour_report: %d checks, %d failures" % [_checks, _failures])
	print("parkour_report: %s" % ("PASS" if _failures == 0 else "FAIL"))


# ------------------------------------------------------------------ counts ---

func _check_counts() -> void:
	var min_platforms := int(_expect["min_platforms"])
	_want("there are at least %d platforms (%d)" % [min_platforms, _platforms.size()],
		_platforms.size() >= min_platforms)
	var zones: Dictionary = {}
	for platform: StaticMap.Platform in _platforms:
		zones[platform.zone] = int(zones.get(platform.zone, 0)) + 1
	var parts: Array[String] = []
	for zone: String in zones:
		parts.append("%s %d" % [zone, int(zones[zone])])
	print("  zones: %s" % ", ".join(parts))
	_want("the geometry was swept (%d triangles into %d shapes)" % [
		_map.triangles, _map.shapes], _map.triangles > 0 and _map.shapes > 0)


# ----------------------------------------------------------------- physics ---

## The trimesh agrees with the table.
##
## Two questions, and they fail differently. The ray asks whether the *top* of
## the rock is where the record says it is — a slab placed by the wrong pillar,
## or a record written from the wrong scale, and the graph is reasoning about a
## map that does not exist. The capsule asks whether a Bog actually fits there,
## which is the question a neighbouring slab overlapping this one answers no to.
func _check_physics() -> void:
	var space := get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	var shape := PhysicsShapeQueryParameters3D.new()
	shape.shape = capsule
	shape.collision_mask = LAYER_WORLD

	var missing := 0
	var blocked := 0
	for platform: StaticMap.Platform in _platforms:
		var at: Vector3 = platform.centre
		var ray := PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * RAY_ABOVE, at - Vector3.UP * RAY_BELOW)
		ray.collision_mask = LAYER_WORLD
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			print("  FAIL  %s (%s) has no floor under its own centre" % [
				platform.label, _vec(at)])
			missing += 1
		elif absf(float(hit["position"].y) - at.y) > TOP_TOLERANCE:
			print("  FAIL  %s (%s) — the rock is at %.2f, the table says %.2f" % [
				platform.label, _vec(at), float(hit["position"].y), at.y])
			missing += 1

		# Two centimetres up, so the slab the capsule stands on is not itself the
		# thing in the way: exactly touching, a top whose height does not round
		# cleanly in float32 reads as an overlap (D-057 met it on 2.2 m and 7.5 m
		# steps, and a 3.2 m deck beside them passed).
		shape.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (CAPSULE_LIFT + 0.02))
		var overlaps := space.intersect_shape(shape, 2)
		if not overlaps.is_empty():
			print("  FAIL  %s (%s) has something standing in it" % [platform.label, _vec(at)])
			blocked += 1

	_want("every landing has the rock the table promises (%d wrong)" % missing, missing == 0)
	_want("a Bog fits on every landing (%d blocked)" % blocked, blocked == 0)


# ------------------------------------------------------------------- graph ---

## Every ordered pair of landings, classified by the cheapest jump that crosses
## it. Ground is node `size()`: it has no edge to take off from and no radius, so
## it is handled by the three heights above rather than by the edge rule.
func _build_graph() -> void:
	var count := _platforms.size()
	for i: int in count:
		for j: int in count:
			if i == j:
				continue
			var jump := _classify(_platforms[i], _platforms[j])
			if jump != "":
				_edges[Vector2i(i, j)] = jump
	for j: int in count:
		var top: float = _platforms[j].centre.y
		if top <= GROUND_HOP:
			_edges[Vector2i(count, j)] = "hop"
		elif top <= GROUND_LEAP:
			_edges[Vector2i(count, j)] = "leap"
		elif top <= GROUND_BIG:
			_edges[Vector2i(count, j)] = "big"


## What it takes to get from A to B, or "" for nothing.
##
## `needed` is the gap the Bog's *capsule* has to fly: take off 0.1 m inside A's
## lip, clear B's lip by its own radius with 0.2 m to spare. `Δy` is compared
## against the reach at one lip-clearance higher than the landing, so a jump that
## would scrape the edge of B on the way in does not count as making it.
func _classify(a: StaticMap.Platform, b: StaticMap.Platform) -> String:
	var gap := Vector2(a.centre.x, a.centre.z).distance_to(Vector2(b.centre.x, b.centre.z))
	var needed := gap - (a.radius - EDGE_MARGIN) - b.radius - CAPSULE_RADIUS + LANDING_MARGIN
	var rise: float = b.centre.y - a.centre.y + LIP_CLEARANCE
	if needed <= _hop_reach(rise):
		return "hop"
	if needed <= _leap_reach(rise):
		return "leap"
	if needed <= _big_reach(rise):
		return "big"
	return ""


## A jump at run speed. Up under gravity, down under 1.35x gravity, and no
## horizontal acceleration worth modelling — air control is weak on purpose and
## the arc is what the layout was spaced against.
func _hop_reach(rise: float) -> float:
	if rise > _apex:
		return -1.0
	var up := JUMP / _gravity
	var down := sqrt(2.0 * (_apex - rise) / (FALL_MULTIPLIER * _gravity))
	return RUN * (up + down)


## Jump, then dive at the apex: run speed until the top of the jump, then the
## dive sets the horizontal speed outright and adds its own upward kick.
func _leap_reach(rise: float) -> float:
	if rise > _dive_apex:
		return -1.0
	var up := DIVE_UP / _gravity
	var down := sqrt(2.0 * (_dive_apex - rise) / (FALL_MULTIPLIER * _gravity))
	return RUN * (JUMP / _gravity) + DIVE_FORWARD * (up + down)


## Jump and dive on the very next tick, which is the earliest the dive is legal.
## Nearly the whole of the jump's upward speed is still there for the dive to add
## to, which is why this goes half as far again as a leap does.
func _big_reach(rise: float) -> float:
	if rise > _tick_apex:
		return -1.0
	var down := sqrt(2.0 * (_tick_apex - rise) / (FALL_MULTIPLIER * _gravity))
	return _tick_forward + DIVE_FORWARD * (_tick_rise + down)


# ------------------------------------------------------------ reachability ---

## Walk the graph from the ground over hops and leaps only, and say what it cost
## to get to everything.
##
## Big leaps are deliberately not walked. They are shortcuts: a map where the
## only way onto the summit is a dive timed to a single physics tick is a map
## with a locked door in it.
func _check_reachability() -> void:
	var count := _platforms.size()
	var cost: Array[float] = []
	cost.resize(count + 1)
	cost.fill(INF)
	cost[count] = 0.0

	# Small enough that a linear scan for the cheapest open node is cheaper than
	# a heap would be, and a great deal easier to read.
	var open: Array[int] = [count]
	while not open.is_empty():
		var best := 0
		for k: int in open.size():
			if cost[open[k]] < cost[open[best]]:
				best = k
		var here: int = open[best]
		open.remove_at(best)
		for j: int in count:
			var jump: String = String(_edges.get(Vector2i(here, j), ""))
			if jump == "" or jump == "big":
				continue
			var step := cost[here] + (1.0 if jump == "hop" else LEAP_COST)
			if step < cost[j] - 0.0001:
				cost[j] = step
				_tree[j] = Vector2i(here, 0 if jump == "hop" else 1)
				if not open.has(j):
					open.append(j)

	var stranded: Array[String] = []
	for j: int in count:
		if cost[j] == INF:
			stranded.append("%s (%s)" % [_platforms[j].label, _vec(_platforms[j].centre)])
	for what: String in stranded:
		print("  FAIL  nothing reaches %s with hops and leaps" % what)
	_want("every landing is reachable from the ground (%d stranded)" % stranded.size(),
		stranded.is_empty())

	var all := {"hop": 0, "leap": 0, "big": 0}
	for key: Vector2i in _edges:
		all[String(_edges[key])] += 1
	var tree_hops := 0
	var tree_leaps := 0
	for j: int in _tree:
		if (_tree[j] as Vector2i).y == 0:
			tree_hops += 1
		else:
			tree_leaps += 1
	var tree_total := maxi(tree_hops + tree_leaps, 1)
	print("  routes: %d hops (%.0f%%), %d leaps (%.0f%%) along the tree" % [
		tree_hops, 100.0 * float(tree_hops) / float(tree_total),
		tree_leaps, 100.0 * float(tree_leaps) / float(tree_total)])
	print("  edges:  %d hop, %d leap, %d big in the whole graph" % [
		all["hop"], all["leap"], all["big"]])

	var min_big := int(_expect["min_big_edges"])
	if min_big > 0:
		_want("there are big-leap shortcuts (%d, want %d)" % [all["big"], min_big],
			all["big"] >= min_big)

	var summit_zone := String(_expect["summit_zone"])
	if summit_zone == "":
		return

	# The summit is the map's prize and it has to be a place you can leave in a
	# hurry. A dive off the top that lands on the ridge or a saddle is what makes
	# holding it a decision rather than a corner to hide in.
	var summit := -1
	for i: int in count:
		if String(_platforms[i].label) == "summit":
			summit = i
	var landings: Array[String] = []
	if summit >= 0:
		for j: int in count:
			if String(_platforms[j].zone) != summit_zone:
				continue
			if String(_edges.get(Vector2i(summit, j), "")) == "leap":
				landings.append(String(_platforms[j].label))
	_want("the summit can dive to the %s (%s)" % [summit_zone,
		", ".join(landings) if not landings.is_empty() else "nowhere"],
		not landings.is_empty())


# ------------------------------------------------------------------ spawns ---

func _check_spawns() -> void:
	var close: Array[String] = []
	for platform: StaticMap.Platform in _platforms:
		for pad: Transform3D in _spawns:
			var gap := Vector2(platform.centre.x, platform.centre.z).distance_to(
				Vector2(pad.origin.x, pad.origin.z))
			if gap < SPAWN_PLATFORM_KEEPOUT:
				close.append("%s is %.1f m from a pad" % [platform.label, gap])
	for what: String in close:
		print("  FAIL  %s" % what)
	_want("no landing crowds a spawn pad (%d do)" % close.size(), close.is_empty())

	# Trunks are cylinders, and the only thing the dressing puts on layer 1. A
	# tree in front of a pad is a player who spawns looking at bark.
	var trunks := 0
	var crowding := 0
	for node in _cylinders(_map):
		trunks += 1
		var at := node.global_transform.origin
		for pad: Transform3D in _spawns:
			if Vector2(at.x, at.z).distance_to(Vector2(pad.origin.x, pad.origin.z)) \
					< SPAWN_TRUNK_KEEPOUT:
				crowding += 1
	_want("no trunk crowds a spawn pad (%d trunks, %d too close)" % [trunks, crowding],
		crowding == 0)


func _cylinders(from: Node) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	var node := from as CollisionShape3D
	if node != null and node.shape is CylinderShape3D:
		out.append(node)
	for child in from.get_children():
		out.append_array(_cylinders(child))
	return out


# --------------------------------------------------------------- off limits ---

## Nothing reaches a top the map has declared off limits — not a hop, not a
## leap, and not the one-tick dive the reachability walk deliberately ignores.
##
## Reachability asks "can you get everywhere you should"; this asks the other
## question, "can you get somewhere you should not". On a box yard the answer
## that matters is the top of a tall stack: from up there the whole map is a
## shooting gallery, and a stack you can reach with a dive nobody practises is a
## stack somebody will practise.
func _check_off_limits() -> void:
	var perches := _map.off_limits
	if perches.is_empty():
		return
	var reached: Array[String] = []
	for perch: StaticMap.Platform in perches:
		# From the ground there is no gap to cross, only a height to clear.
		if perch.centre.y + LIP_CLEARANCE <= _tick_apex:
			reached.append("%s from the ground" % perch.label)
			continue
		for platform: StaticMap.Platform in _platforms:
			var jump := _classify(platform, perch)
			if jump != "":
				reached.append("%s by a %s off %s" % [perch.label, jump, platform.label])
				break
	for what: String in reached:
		print("  FAIL  a Bog can reach %s" % what)
	_want("no jump reaches an off-limits top (%d tops, highest dive %.2f m, %d reached)" % [
		perches.size(), _tick_apex, reached.size()], reached.is_empty())


# -------------------------------------------------------------- sightlines ---

## How far one Bog can see another, eye to eye, on this map.
##
## Only for a map that states a limit. Every standable point on a two-metre grid
## of the ground, and every landing, is an eye 1.45 m up; every pair of eyes
## that can see each other through layer 1 is a sightline, and the longest is
## the number. Ground to ground is what the aisles allow; anything involving a
## landing is what climbing buys, and a landing that sees across the whole map
## is a camping perch whatever the aisles do.
##
## Also asked, when the map declares two bases: whether any spawn pad can see a
## pad that belongs to the other base. A player killed from the other team's
## spawn before their first step has not played the round.
func _check_sightlines() -> void:
	var limit := float(_expect["sightline"])
	if limit <= 0.0:
		return
	var roof_limit := float(_expect["roof_sightline"])
	var space := get_world_3d().direct_space_state
	var ground := _ground_points(space)
	var roofs: Array[Vector3] = []
	for platform: StaticMap.Platform in _platforms:
		roofs.append(platform.centre)
	var everywhere: Array[Vector3] = ground + roofs

	var worst_ground := _longest_sight(space, ground, ground)
	var worst_roof := _longest_sight(space, roofs, everywhere)
	print("  sightline: %d ground points, %d landings" % [ground.size(), roofs.size()])
	print("  sightline: ground to ground %.1f m, %s to %s" % [float(worst_ground[0]),
		_vec(worst_ground[1]), _vec(worst_ground[2])])
	print("  sightline: from a landing %.1f m, %s to %s" % [float(worst_roof[0]),
		_vec(worst_roof[1]), _vec(worst_roof[2])])
	_want("no ground sightline is longer than %.0f m (%.1f)" % [limit, float(worst_ground[0])],
		float(worst_ground[0]) <= limit)
	_want("no sightline from a landing is longer than %.0f m (%.1f)" % [roof_limit,
		float(worst_roof[0])], float(worst_roof[0]) <= roof_limit)

	var bases := _map.base_points()
	if bases.size() != 2:
		return
	var seen: Array[String] = []
	for i: int in _spawns.size():
		for j: int in range(i + 1, _spawns.size()):
			var a := _spawns[i].origin
			var b := _spawns[j].origin
			if _nearest(bases, a) == _nearest(bases, b):
				continue
			if _sees(space, a, b):
				seen.append("pad %d sees pad %d (%.1f m)" % [i, j, a.distance_to(b)])
	for what: String in seen:
		print("  FAIL  %s" % what)
	_want("no spawn pad sees the other base's pads (%d do)" % seen.size(), seen.is_empty())


## Every standable point of the ground on the sightline grid: a floor within
## 0.6 m of y = 0 with a Bog's worth of room over it.
func _ground_points(space: PhysicsDirectSpaceState3D) -> Array[Vector3]:
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	var fits := PhysicsShapeQueryParameters3D.new()
	fits.shape = capsule
	fits.collision_mask = LAYER_WORLD
	var ground: Array[Vector3] = []
	var reach := float(_expect["reach"])
	var x := -reach + SIGHT_STEP * 0.5
	while x < reach:
		var z := -reach + SIGHT_STEP * 0.5
		while z < reach:
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x, 0.6, z), Vector3(x, -0.6, z))
			ray.collision_mask = LAYER_WORLD
			var hit := space.intersect_ray(ray)
			if not hit.is_empty():
				var foot: Vector3 = hit["position"]
				fits.transform = Transform3D(Basis.IDENTITY,
					foot + Vector3.UP * (CAPSULE_LIFT + 0.05))
				if space.intersect_shape(fits, 1).is_empty():
					ground.append(foot)
			z += SIGHT_STEP
		x += SIGHT_STEP
	return ground


# --------------------------------------------------------------- overboard ---

## Over the side is the void, from everywhere. Only for a map that says it
## stands on nothing (a yacht on the sea, D-057).
##
## Two questions. Off both ends of every row of the ground grid — marched out
## to where the deck ends — a column `OVERBOARD` metres further out has nothing
## in it from above the rail down past the void:
## no hull flare, no fender, no ledge a falling Bog lands on and stands up from.
## And the void is under every landing, and not so far under the lowest one
## that a Bog falls for longer than a moment before the match calls it.
func _check_overboard() -> void:
	if not bool(_expect.get("overboard", false)):
		return
	var space := get_world_3d().direct_space_state
	var ground := _ground_points(space)
	# The outermost standable point of each row of the grid, each side.
	var rows: Dictionary = {}
	for foot: Vector3 in ground:
		var key := roundi(foot.z * 10.0)
		var row: Array = rows.get(key, [foot, foot])
		if foot.x < (row[0] as Vector3).x:
			row[0] = foot
		if foot.x > (row[1] as Vector3).x:
			row[1] = foot
		rows[key] = row
	var edges := 0
	var caught: Array[String] = []
	for key: int in rows:
		for k: int in 2:
			var foot: Vector3 = rows[key][k]
			var side := -1.0 if k == 0 else 1.0
			# March out to where the deck itself ends, under anything standing
			# at its edge, and then a rail's thickness and a margin past it.
			var x := foot.x
			while absf(x) < float(_expect["reach"]):
				var probe := PhysicsRayQueryParameters3D.create(Vector3(x, 0.6, foot.z),
					Vector3(x, -0.6, foot.z))
				probe.collision_mask = LAYER_WORLD
				if space.intersect_ray(probe).is_empty():
					break
				x += side * 0.25
			var out := Vector3(x + side * OVERBOARD, foot.y, foot.z)
			var ray := PhysicsRayQueryParameters3D.create(out + Vector3.UP * 2.0,
				Vector3(out.x, _map.void_height - 1.0, out.z))
			ray.collision_mask = LAYER_WORLD
			var hit := space.intersect_ray(ray)
			edges += 1
			if not hit.is_empty():
				caught.append("%s over the side of %s" % [_vec(hit["position"]), _vec(foot)])
	for what: String in caught:
		print("  FAIL  something to land on at %s" % what)
	_want("over every edge of the deck is nothing but the void (%d edges, %d caught)" % [
		edges, caught.size()], edges > 0 and caught.is_empty())

	var lowest := INF
	for platform: StaticMap.Platform in _platforms:
		lowest = minf(lowest, platform.centre.y)
	lowest = minf(lowest, 0.0)
	_want("the void (%.1f) is under the lowest floor (%.1f) and within %.0f m of it" % [
		_map.void_height, lowest, VOID_DEPTH],
		_map.void_height < lowest - 1.0 and _map.void_height > lowest - VOID_DEPTH)


## [length, from, to] of the longest clear eye-to-eye line from any point in
## `from` to any point in `to`.
func _longest_sight(space: PhysicsDirectSpaceState3D, from: Array[Vector3],
		to: Array[Vector3]) -> Array:
	var best: Array = [0.0, Vector3.ZERO, Vector3.ZERO]
	for a: Vector3 in from:
		for b: Vector3 in to:
			var length := a.distance_to(b)
			if length <= float(best[0]):
				continue
			if _sees(space, a, b):
				best = [length, a, b]
	return best


func _sees(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(a + Vector3.UP * EYE, b + Vector3.UP * EYE)
	ray.collision_mask = LAYER_WORLD
	ray.hit_back_faces = true
	return space.intersect_ray(ray).is_empty()


func _nearest(points: Array[Vector3], to: Vector3) -> int:
	var best := 0
	for i: int in points.size():
		if Vector2(points[i].x, points[i].z).distance_to(Vector2(to.x, to.z)) \
				< Vector2(points[best].x, points[best].z).distance_to(Vector2(to.x, to.z)):
			best = i
	return best


# ---------------------------------------------------------------- the maps ---

## The layout as a terminal picture: the height of the nearest landing in each
## two-metre cell, as a digit, with '.' for open ground.
##
## The same idea as `preview_map`'s probe grid, and for the same reason — a
## coordinate list is unreadable and a render needs eyes. This is the view that
## makes it obvious at a glance that the kopje is the high ground, that the ridge
## runs along one side and that nothing is stranded out at the rim.
func _print_height_map() -> void:
	var reach := float(_expect["reach"])
	var columns := int(reach * 2.0 / _grid_step) + 1
	print("parkour: landing tops on a %.0f m grid, digits are whole metres, '.' is ground" % _grid_step)
	var ruler := "      "
	for c: int in columns:
		ruler += "|" if int(-reach + float(c) * _grid_step) % 10 == 0 else " "
	print(ruler)
	for r: int in columns:
		var z := -reach + float(r) * _grid_step
		var row := ""
		for c: int in columns:
			var x := -reach + float(c) * _grid_step
			row += _cell_glyph(Vector2(x, z))
		print("%5d %s" % [int(z), row])
	print(ruler)


func _cell_glyph(at: Vector2) -> String:
	var best := -1.0
	for platform: StaticMap.Platform in _platforms:
		var centre := Vector2(platform.centre.x, platform.centre.z)
		if at.distance_to(centre) <= maxf(float(platform.radius), _grid_step * 0.5):
			best = maxf(best, float(platform.centre.y))
	if best < 0.0:
		return "."
	return "0123456789"[clampi(int(round(best)), 0, 9)]


# ----------------------------------------------------------------- drawing ---

## A disc on every landing, coloured by how high it is, and a line along every
## edge of the route tree. Unshaded and drawn on top of the geometry: the point
## of the picture is the graph, and a disc hidden behind a boulder says nothing.
func _draw() -> void:
	var group := Node3D.new()
	group.name = "Graph"
	add_child(group)

	for platform: StaticMap.Platform in _platforms:
		var disc := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = float(platform.radius)
		cylinder.bottom_radius = float(platform.radius)
		cylinder.height = 0.06
		cylinder.radial_segments = 14
		disc.mesh = cylinder
		disc.material_override = _flat(_height_tint(float(platform.centre.y)))
		disc.position = platform.centre + Vector3.UP * 0.08
		group.add_child(disc)

	var tints := {0: Color(0.2, 1.0, 0.3), 1: Color(1.0, 0.9, 0.2)}
	for j: int in _tree:
		var link: Vector2i = _tree[j]
		if link.x >= _platforms.size():
			continue  # off the ground: there is no line to draw
		var from: Vector3 = _platforms[link.x].centre + Vector3.UP * 0.35
		var to: Vector3 = _platforms[j].centre + Vector3.UP * 0.35
		group.add_child(_link(from, to, tints[link.y]))

	# Every big leap in the graph would be five hundred lines of spaghetti, so
	# only the long ones are drawn: those are the shortcuts the layout is meant
	# to have, and seeing where they are is the point.
	for key: Vector2i in _edges:
		if String(_edges[key]) != "big" or key.x >= _platforms.size():
			continue
		var from: Vector3 = _platforms[key.x].centre
		var to: Vector3 = _platforms[key.y].centre
		if Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z)) < 7.5:
			continue
		group.add_child(_link(from + Vector3.UP * 0.2, to + Vector3.UP * 0.2,
			Color(1.0, 0.25, 0.2)))


func _link(from: Vector3, to: Vector3, tint: Color) -> MeshInstance3D:
	var span := to - from
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.09, 0.09, maxf(span.length(), 0.01))
	node.mesh = box
	node.material_override = _flat(tint)
	node.look_at_from_position(from + span * 0.5, to, Vector3.UP)
	return node


func _height_tint(y: float) -> Color:
	return Color(0.15, 0.35, 0.95).lerp(Color(0.95, 0.2, 0.15), clampf(y / 10.0, 0.0, 1.0))


func _flat(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	material.no_depth_test = true
	return material


func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.far = 400.0
	add_child(camera)
	# Framed off the map's own reach: Kopje Crossing's 36 m is 104 m of frame.
	var scale := float(_expect["reach"]) / 36.0
	match _view:
		"side":
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 104.0 * scale
			camera.look_at_from_position(Vector3(96.0, 12.0, 0.0) * scale,
				Vector3(0.0, 6.0, 0.0) * scale, Vector3.UP)
		"iso":
			camera.fov = 50.0
			camera.look_at_from_position(Vector3(70.0, 55.0, 70.0) * scale,
				Vector3(0.0, 3.0, 0.0), Vector3.UP)
		_:
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 104.0 * scale
			# `Vector3.UP` is degenerate for a camera already looking along it,
			# so -Z is the up vector instead, which also puts the ridge at the
			# top of the picture.
			camera.look_at_from_position(Vector3(0.0, 60.0, 0.0), Vector3.ZERO,
				Vector3.FORWARD)
	camera.make_current()


# ----------------------------------------------------------------- harness ---

func _want(what: String, ok: bool) -> bool:
	_checks += 1
	if not ok:
		_failures += 1
		print("  FAIL  %s" % what)
	else:
		print("  ok    %s" % what)
	return ok


func _fail(what: String) -> void:
	_reported = true
	_checks += 1
	_failures += 1
	print("  FAIL  %s" % what)
	print("parkour_report: %d checks, %d failures" % [_checks, _failures])
	print("parkour_report: FAIL")


func _vec(v: Vector3) -> String:
	return "%.1f, %.1f, %.1f" % [v.x, v.y, v.z]
