extends Node3D
## Can you actually get up there? Development tool, not shipped.
##
## Kopje Crossing is a hundred and twenty-three rock platforms at heights from
## 0.4 m to 9.5 m, and the only thing that makes it a map rather than a pile is
## that every one of them is reachable from the ground. That is not something a
## render can show and it is certainly not something a coordinate can: the
## question "is this gap crossable" is a question about the Gub's jump arc, and
## the arc is five constants in `gub.gd` and one in `project.godot`.
##
## So this rebuilds the arc from those constants, builds the whole reachability
## graph out of `SafariMap.platforms`, and walks it from the ground. Anything it
## cannot reach is named. It also checks the *physics* against the table — a ray
## down onto layer 1 from every landing and a Gub-sized capsule standing on it —
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
##       res://tools/parkour_report.tscn out.png <ticks> [top|side|iso]
##
## Everything is printed before the render, so this is also a headless check —
## `tools/smoke_test.sh` greps it for `parkour_report: PASS`.

const MAP_SCENE := "res://scenes/world/maps/safari.tscn"

## The movement model, read off `Gub` and `ProjectSettings` rather than typed, so
## a change to the character's jump fails this check instead of quietly
## invalidating every gap on the map.
const RUN := Gub.RUN_SPEED
const JUMP := Gub.JUMP_VELOCITY
const DIVE_FORWARD := Gub.DIVE_FORWARD_SPEED
const DIVE_UP := Gub.DIVE_UP_VELOCITY
## The one number here that is a literal, because it is a literal in
## `Gub._apply_gravity` too: falling is 1.35x as fast as rising, which is what
## makes a jump feel decisive. If that ever becomes a constant, name it here.
const FALL_MULTIPLIER := 1.35

const CAPSULE_RADIUS := Gub.CAPSULE_RADIUS
const CAPSULE_HEIGHT := Gub.STAND_HEIGHT
## Where the capsule's centre sits above the Gub's feet — the offset on the
## `Collision` node in `gub.tscn`. A test at the landing itself would be a
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
## Gub's leading edge has to clear the lip, not its centre.
const EDGE_MARGIN := 0.1
const LANDING_MARGIN := 0.2
const LIP_CLEARANCE := 0.1

## What the ground can be jumped onto from. Flat ground has no edge to take off
## from and no radius, so these are stated rather than derived: 1.3 m is a lip
## you can hop onto from a standing run, 1.9 is one you have to dive for.
const GROUND_HOP := 1.3
const GROUND_LEAP := 1.9
const GROUND_BIG := 3.5

const MIN_PLATFORMS := 110
## Big leaps are shortcuts. A map with none is a map where the dive's full range
## is never worth learning; this is the floor, not a target.
const MIN_BIG_EDGES := 6

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

## The ASCII map's grid, in metres. Two is fine enough to see a spiral step and
## coarse enough that a 96 m plateau fits in a terminal.
const GRID_STEP := 2.0
const GRID_REACH := 36.0

var _view: String = "top"
var _map: StaticMap
var _platforms: Array[SafariMap.Platform] = []
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

	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))
	_apex = JUMP * JUMP / (2.0 * _gravity)
	_dive_apex = _apex + DIVE_UP * DIVE_UP / (2.0 * _gravity)
	# One physics tick after the jump the Gub has risen a little and lost a
	# little speed; the dive then adds its whole upward kick to what is left.
	var tick := 1.0 / float(ProjectSettings.get_setting(
		"physics/common/physics_ticks_per_second", 60))
	var after := (JUMP - _gravity * tick) + DIVE_UP
	_tick_start = JUMP * tick
	_tick_forward = RUN * tick
	_tick_rise = after / _gravity
	_tick_apex = _tick_start + after * after / (2.0 * _gravity)

	var packed := load(MAP_SCENE) as PackedScene
	if packed == null:
		_fail("the map scene loads (%s)" % MAP_SCENE)
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
	if not (_map is SafariMap):
		_fail("the map is a SafariMap and can be asked about its platforms")
		return
	_platforms = (_map as SafariMap).platforms
	_spawns = _map.spawn_points()
	print("parkour_report: %s — %d platforms, %d triangles, %d shapes, built in %d ms" % [
		MAP_SCENE, _platforms.size(), _map.triangles, _map.shapes, _map.build_msec])


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
	_check_spawns()
	_print_height_map()
	_draw()
	_build_camera()

	print("parkour_report: %d checks, %d failures" % [_checks, _failures])
	print("parkour_report: %s" % ("PASS" if _failures == 0 else "FAIL"))


# ------------------------------------------------------------------ counts ---

func _check_counts() -> void:
	_want("there are at least %d platforms (%d)" % [MIN_PLATFORMS, _platforms.size()],
		_platforms.size() >= MIN_PLATFORMS)
	var zones: Dictionary = {}
	for platform: SafariMap.Platform in _platforms:
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
## map that does not exist. The capsule asks whether a Gub actually fits there,
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
	for platform: SafariMap.Platform in _platforms:
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

		shape.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * CAPSULE_LIFT)
		var overlaps := space.intersect_shape(shape, 2)
		if not overlaps.is_empty():
			print("  FAIL  %s (%s) has something standing in it" % [platform.label, _vec(at)])
			blocked += 1

	_want("every landing has the rock the table promises (%d wrong)" % missing, missing == 0)
	_want("a Gub fits on every landing (%d blocked)" % blocked, blocked == 0)


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
## `needed` is the gap the Gub's *capsule* has to fly: take off 0.1 m inside A's
## lip, clear B's lip by its own radius with 0.2 m to spare. `Δy` is compared
## against the reach at one lip-clearance higher than the landing, so a jump that
## would scrape the edge of B on the way in does not count as making it.
func _classify(a: SafariMap.Platform, b: SafariMap.Platform) -> String:
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

	_want("there are big-leap shortcuts (%d, want %d)" % [all["big"], MIN_BIG_EDGES],
		all["big"] >= MIN_BIG_EDGES)

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
			if String(_platforms[j].zone) != "ridge":
				continue
			if String(_edges.get(Vector2i(summit, j), "")) == "leap":
				landings.append(String(_platforms[j].label))
	_want("the summit can dive to the ridge (%s)" % (
		", ".join(landings) if not landings.is_empty() else "nowhere"),
		not landings.is_empty())


# ------------------------------------------------------------------ spawns ---

func _check_spawns() -> void:
	var close: Array[String] = []
	for platform: SafariMap.Platform in _platforms:
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


# ---------------------------------------------------------------- the maps ---

## The layout as a terminal picture: the height of the nearest landing in each
## two-metre cell, as a digit, with '.' for open ground.
##
## The same idea as `preview_map`'s probe grid, and for the same reason — a
## coordinate list is unreadable and a render needs eyes. This is the view that
## makes it obvious at a glance that the kopje is the high ground, that the ridge
## runs along one side and that nothing is stranded out at the rim.
func _print_height_map() -> void:
	var columns := int(GRID_REACH * 2.0 / GRID_STEP) + 1
	print("parkour: landing tops on a %.0f m grid, digits are whole metres, '.' is ground" % GRID_STEP)
	var ruler := "      "
	for c: int in columns:
		ruler += "|" if int(-GRID_REACH + float(c) * GRID_STEP) % 10 == 0 else " "
	print(ruler)
	for r: int in columns:
		var z := -GRID_REACH + float(r) * GRID_STEP
		var row := ""
		for c: int in columns:
			var x := -GRID_REACH + float(c) * GRID_STEP
			row += _cell_glyph(Vector2(x, z))
		print("%5d %s" % [int(z), row])
	print(ruler)


func _cell_glyph(at: Vector2) -> String:
	var best := -1.0
	for platform: SafariMap.Platform in _platforms:
		var centre := Vector2(platform.centre.x, platform.centre.z)
		if at.distance_to(centre) <= maxf(float(platform.radius), GRID_STEP * 0.5):
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

	for platform: SafariMap.Platform in _platforms:
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
	match _view:
		"side":
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 104.0
			camera.look_at_from_position(Vector3(96.0, 12.0, 0.0),
				Vector3(0.0, 6.0, 0.0), Vector3.UP)
		"iso":
			camera.fov = 50.0
			camera.look_at_from_position(Vector3(70.0, 55.0, 70.0),
				Vector3(0.0, 3.0, 0.0), Vector3.UP)
		_:
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 104.0
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
