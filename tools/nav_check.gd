extends Node
## Does every map bake a navmesh you can actually get across? Development tool,
## not shipped.
##
##   Godot --headless --path . tools/nav_check.tscn
##
## The guide line is only as good as the ground under it, and the ground is
## baked at runtime on each client from whatever collision the map happens to
## have put on layer 1 (`scripts/world/nav/nav_bake.gd`). That is a good deal
## of trust placed in seven maps built by four different means — a `.glb` with
## world-space trimesh cells, three layout tables, an island grown from a seed
## — and the failure mode is silent: a map that bakes eleven polygons draws a
## straight line through a wall and nobody notices until a player follows one
## off a deck.
##
## So this stands up every map in `MapCatalog`, in a real offline session with
## the real `arena.tscn`, waits for the bake, and asks three things of each:
##
##   census   it prints what came out — polygons, links, milliseconds — so a
##            map whose count collapses after a layout change is visible in the
##            gate's log rather than in a match.
##   floor    at least `MIN_POLYGONS` polygons. Fifty is far below the smallest
##            real map and far above what a failed parse produces, which is
##            nought.
##   route    a path from the first spawn pad to the last. Two pads on the same
##            map with no route between them is the one failure that makes the
##            line worse than nothing.
##
## The path's length and how many jump links it used are printed too: a map
## whose route takes no links at all is a map whose parkour the line is walking
## round, which is worth seeing even though it is not a failure.
##
## Nothing here is a rule and nothing here is replicated — the navmesh is local
## and cosmetic, like a ragdoll (D-010), and the host decides the match without
## one (D-007). This checks a drawing.

const ARENA_SCENE := preload("res://scenes/world/arena.tscn")

## Below this the parse found nothing worth baking. Rust is the smallest arena
## in the game and its walkable floor is hundreds of polygons at a quarter-metre
## cell, so fifty is a floor and not a target.
const MIN_POLYGONS := 50

## And below this the link builder found nothing. Every map in the game has
## ledges, kerbs or a deck to drop off — the smallest honest count of the seven
## is the range's, and eight is well under it and far above the nought a
## builder reading an unsynced navigation map produces (D-167).
const MIN_LINKS := 8

## Wall clock, not frames: the island is one blocking build frame of unknown
## length and the bake itself runs on a worker thread, so counting frames would
## be counting the wrong thing (the same point D-012 makes about the snapshot
## tool's warmup).
const BAKE_TIMEOUT := 90.0

## How many physics frames past `baked` a route may take to appear before that
## is a failure. Generous, because what it guards against is a map with no
## route, not a slow frame.
const ROUTE_FRAMES := 30

var _checks: int = 0
var _failures: int = 0
var _maps: int = 0
var _links_total: int = 0
var _links_at_origin: int = 0


func _ready() -> void:
	Net.start_offline()
	Net.set_name_local("You")
	# One map by name after a `--`, for a fast look at a single bake; every map
	# otherwise, which is what the gate asks for.
	var only: Array = Array(OS.get_cmdline_user_args()).filter(
		func(a: String) -> bool: return MapCatalog.is_valid(a))
	for id: String in MapCatalog.ids():
		if only.is_empty() or only.has(id):
			await _run_map(id)
	# One line the gate can grep for the whole of D-167, because the per-map
	# assertions only speak when they fail and "no link ends at the origin" is a
	# thing that has to be said out loud to stay true.
	print("nav_check: %d maps, %d links, %d at the world origin"
		% [_maps, _links_total, _links_at_origin])
	print("nav_check: %s" % ("FAIL" if _failures > 0 else "PASS"))
	get_tree().quit(1 if _failures > 0 else 0)


## One map, from an empty tree to an empty tree.
##
## The arena is the shipped scene and the session is a real offline host, which
## is what makes this a check and not a rehearsal: `arena.gd` picks its branch
## off `Net.config.map` exactly as it does in a match, and `NavBake` is added
## by the same line of the same function.
func _run_map(id: String) -> void:
	var config := Net.config
	# Free-for-all B·O·G, so the guide line is alive on the same frames the
	# navmesh is — this is the only headless run that builds `GuideLine` at all.
	config.win_condition = MatchConfig.WinCondition.LETTERS
	config.mode = MatchConfig.Mode.FREE_FOR_ALL
	config.map = id
	config.warmup_time = 0.2
	config.spawn_protection = 0.0
	config.time_limit = 0
	Net.roster_changed.emit()

	var arena := ARENA_SCENE.instantiate() as Arena
	add_child(arena)

	var nav := arena.get_node_or_null("NavBake") as NavBake
	if not _want("%s: the arena added a NavBake" % id, nav != null):
		await _teardown(arena)
		return
	var baked := await _await_bake(nav, id)
	if not baked:
		await _teardown(arena)
		return

	var polygons := nav.polygon_count()
	var links := nav.link_count()
	var pads := arena.spawn_points
	var route := PackedVector3Array()
	if pads.size() >= 2:
		# A route is asked for a few frames running rather than once: the map's
		# iteration that carries the polygons can land a frame or two after
		# `baked`, and this check is about whether a route *exists*, not about
		# which frame it first appears on. The frame it took is printed.
		var map := arena.get_world_3d().navigation_map
		var waited := 0
		while route.size() < 2 and waited < ROUTE_FRAMES:
			route = nav.find_path(pads[0].origin, pads[pads.size() - 1].origin)
			if route.size() >= 2:
				break
			waited += 1
			await get_tree().physics_frame
		print("nav_check: %s map iteration %d, %d region(s), route after %d extra frame(s), closest to pad 1 %s" % [
			id, NavigationServer3D.map_get_iteration_id(map),
			NavigationServer3D.map_get_regions(map).size(), waited,
			NavigationServer3D.map_get_closest_point(map, pads[0].origin)])
	var link_points := nav.link_points()
	var at_origin := 0
	for point: Vector3 in link_points:
		if point.length() < 0.01:
			at_origin += 1
	_maps += 1
	_links_total += links
	_links_at_origin += at_origin
	var jumps := GuidePath.link_segments(route, link_points)
	var bounds := nav.bounds()
	print("nav_check: %s %d polygons, %d links, %.0f x %.0f m; pad 1 to pad %d is %.1f m over %d jumps, %.2f ms a query"
		% [id, polygons, links, bounds.size.x, bounds.size.z, pads.size(),
			GuidePath.polyline_length(route), jumps, _query_msec(nav, pads)])

	_want("%s: at least %d navmesh polygons (%d)" % [id, MIN_POLYGONS, polygons],
		polygons >= MIN_POLYGONS)
	_want("%s: two spawn pads to path between (%d)" % [id, pads.size()], pads.size() >= 2)
	_want("%s: a route from the first pad to the last (%d points)" % [id, route.size()],
		route.size() >= 2)
	# The links, and the one failure that looks like success. Until D-167 every
	# link on every map ended at the world origin, because the builder asked an
	# unsynced navigation map where the ground was and (0, 0, 0) is what an
	# unsynced map answers — a census of "14 links" and a gate of green while the
	# line went over nothing. A link end within a centimetre of the origin is
	# that, and no map here has walkable ground there anyway.
	_want("%s: no link end sits at the world origin (%d of %d)"
		% [id, at_origin, link_points.size()], at_origin == 0)
	_want("%s: at least %d jump links (%d)" % [id, MIN_LINKS, links], links >= MIN_LINKS)
	# The cap is a ceiling on what one navigation map should carry, not a budget
	# to spend: a bake that reaches it has stopped part way through the border
	# edges, so which half of the map got links is whatever order they came out
	# of a dictionary in.
	_want("%s: the link cap was not reached (%d of %d)" % [id, links, JumpLinks.MAX_LINKS],
		links < JumpLinks.MAX_LINKS)
	_want("%s: the outline image was rasterised" % id,
		nav.outline_image() != null and nav.outline_image().get_width() > 1)
	await _teardown(arena)


## What one guide-line path costs, averaged over every ordered pair of spawn
## pads. Printed rather than asserted: the links are what make a query expensive
## — a navigation map carrying hundreds of them is the point of D-167 — and the
## number wanted is "a fraction of a millisecond", against a `GuideLine` that
## re-solves a few times a second on one client.
func _query_msec(nav: NavBake, pads: Array[Transform3D]) -> float:
	if pads.size() < 2:
		return 0.0
	var queries := 0
	var started := Time.get_ticks_usec()
	for from: Transform3D in pads:
		for to: Transform3D in pads:
			if from == to:
				continue
			nav.find_path(from.origin, to.origin)
			queries += 1
	return float(Time.get_ticks_usec() - started) / (1000.0 * float(maxi(queries, 1)))


func _await_bake(nav: NavBake, id: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(BAKE_TIMEOUT * 1000.0)
	while not nav.is_ready():
		if Time.get_ticks_msec() > deadline:
			return _want("%s: the navmesh baked inside %.0f s" % [id, BAKE_TIMEOUT], false)
		await get_tree().physics_frame
	return true


## Every map shares one `World3D` and therefore one navigation map, so the
## previous arena's region and links have to be gone — and *synced* gone —
## before the next bake asks the map where the nearest walkable point is.
## Physics frames rather than process frames for exactly that reason.
func _teardown(arena: Node) -> void:
	MatchState.reset()
	if arena != null:
		arena.queue_free()
	for i in 6:
		await get_tree().physics_frame


func _want(what: String, ok: bool) -> bool:
	_checks += 1
	if ok:
		return true
	_failures += 1
	print("  FAIL  %s" % what)
	return false
