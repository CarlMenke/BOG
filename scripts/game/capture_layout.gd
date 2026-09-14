class_name CaptureLayout
extends RefCounted
## Where the bases and the three letters are in a Capture G·U·B match (D-051).
##
## **A map can say, and every map that does not gets a fallback.** A hand-made
## map declares its objectives on its `StaticMap` root (see `static_map.gd`):
## a `Bases` node with one `Marker3D` per team, in team order, and a `Letters`
## node with three `Marker3D`s in G, U, B order. Nothing on disk declares either
## yet, so today every map — the island, Rust and Kopje Crossing — is played on
## the fallback below, which is a **placeholder** until a map built for this
## mode exists:
##
## - **Bases.** The spawn pads are split by bearing around their own centroid
##   into one contiguous arc per team, choosing the rotation of the split that
##   keeps each arc tightest. A team's base is the pad in its arc nearest the
##   arc's centroid — a pad rather than the centroid itself, because a pad is
##   the one point on any map already proven standable, and a centroid can be
##   inside a shipping container.
## - **Letters.** On the line through the middle of the two first bases: G at
##   the midpoint, U and B either side of it across the axis between the bases,
##   so all three are equidistant from the two bases. Each is then settled onto
##   real ground with head room above it (`settle`), searching outward in rings
##   when the ideal point is inside something.
##
## **Team spawns follow the bases**, declared or not: every pad belongs to the
## nearest base, and a Gub in this mode respawns on one of its own team's pads
## (`MatchState._spawn_pool`). A team the pads cannot be shared with spawns
## anywhere, rather than nowhere.
##
## Pure data and static queries, no nodes. Planned on every peer from the same
## pads and the same config, so every peer draws the bases in the same place
## without a message; only the host settles the letters, because only the host
## spawns them.

## Base radius when the map does not state one. About four metres: big enough
## to run into without stopping, small enough that a base is a place and not a
## half of the map.
const DEFAULT_BASE_RADIUS := 4.0
## How far above or below a base's marker a carrier can be and still be in it.
## A flat disc would bank a carrier on the catwalk over somebody's base, or on
## the ground under a platform base.
const BASE_HEIGHT := 3.0

## A Gub's collision, taken from `Gub` rather than typed, for the head-room test.
const CAPSULE_LIFT := 0.775
const LAYER_WORLD := 1
## A surface steeper than this is a wall to put a card against, not a floor.
const MIN_FLOOR_NORMAL := 0.7
## How many surfaces one column is peeled through, top down, before giving up.
const MAX_LAYERS := 10
## Rings searched outward from an ideal letter point that is inside something.
const SEARCH_STEP := 2.0
const SEARCH_RINGS := 5
const SEARCH_BEARINGS := 8
## Two pads this close in bearing to the middle of their arc are a tie.
const TIE_BEARING := 0.2
## The first search only takes floors this close to the bases' height, so a card
## goes on the ground beside a rock stack rather than on top of it. Only when
## nothing near enough exists anywhere in the search does a higher floor do.
const NEAR_HEIGHT := 1.5
## How close two settled cards may be.
const MIN_APART := 4.0

## One point per team, in team order.
var bases: Array[Vector3] = []
var base_radius: float = DEFAULT_BASE_RADIUS
## For each spawn pad, in pad order, the team whose base it is nearest.
var pad_team: Array[int] = []
## Three unsettled points, G, U, B.
var letters: Array[Vector3] = []
## Whether the map stated these, or the fallback made them up.
var bases_declared: bool = false
var letters_declared: bool = false


## Plan a layout. `declared_bases` and `declared_letters` come from the map and
## are used only when there are enough of them (a base per team, three letters);
## anything short of that falls back whole, with a warning, because a map that
## declared two bases for a four-team lobby has not said where the other two go.
static func plan(spawns: Array[Transform3D], team_count: int,
		declared_bases: Array[Vector3] = [], declared_letters: Array[Vector3] = [],
		radius: float = DEFAULT_BASE_RADIUS) -> CaptureLayout:
	var layout := CaptureLayout.new()
	layout.base_radius = radius if radius > 0.0 else DEFAULT_BASE_RADIUS
	var teams := maxi(1, team_count)

	if declared_bases.size() >= teams:
		layout.bases_declared = true
		for i in teams:
			layout.bases.append(declared_bases[i])
	else:
		if not declared_bases.is_empty():
			push_warning("CaptureLayout: the map declares %d bases for %d teams; "
				% [declared_bases.size(), teams] + "using the fallback")
		layout.bases = fallback_bases(spawns, teams)

	# Pads belong to the arc their fallback base came out of, so a team gets its
	# fair share of them; to a declared base, the nearest.
	if layout.bases_declared:
		for pad: Transform3D in spawns:
			layout.pad_team.append(layout.nearest_base(pad.origin))
	else:
		layout.pad_team.resize(spawns.size())
		layout.pad_team.fill(MatchConfig.TEAM_NONE)
		var groups := split_pads(spawns, teams)
		for team in groups.size():
			for index: int in groups[team]:
				layout.pad_team[index] = team

	if declared_letters.size() >= 3:
		layout.letters_declared = true
		for i in 3:
			layout.letters.append(declared_letters[i])
	else:
		if not declared_letters.is_empty():
			push_warning("CaptureLayout: the map declares %d letter points, not 3; "
				% declared_letters.size() + "using the fallback")
		layout.letters = fallback_letters(layout.bases, spawns)
	return layout


## The team whose base `point` is horizontally nearest, or `TEAM_NONE`.
func nearest_base(point: Vector3) -> int:
	var best := MatchConfig.TEAM_NONE
	var best_distance := INF
	for team in bases.size():
		var d := _flat(point).distance_to(_flat(bases[team]))
		if d < best_distance:
			best_distance = d
			best = team
	return best


## Whether `point` is inside `team`'s base: within the radius across the ground
## and within `BASE_HEIGHT` of the base's own height.
func in_base(team: int, point: Vector3) -> bool:
	if team < 0 or team >= bases.size():
		return false
	var base := bases[team]
	return _flat(point).distance_to(_flat(base)) <= base_radius \
		and absf(point.y - base.y) <= BASE_HEIGHT


## The spawn pads split into one contiguous arc per team, as lists of pad
## indices in team order. See the header.
static func split_pads(spawns: Array[Transform3D], teams: int) -> Array:
	var best_groups: Array = []
	if spawns.is_empty():
		return best_groups
	var centre := Vector3.ZERO
	for pad: Transform3D in spawns:
		centre += pad.origin
	centre /= float(spawns.size())

	# Pads in bearing order around their centroid.
	var order := range(spawns.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return _bearing(spawns[a].origin, centre) < _bearing(spawns[b].origin, centre))

	var count := order.size()
	var best_spread := INF
	for start in count:
		var groups: Array = []
		for team in teams:
			groups.append([])
		for k in count:
			# Contiguous arcs of (as near as possible) equal size.
			var team := mini(teams - 1, int(float(k * teams) / float(count)))
			groups[team].append(order[(start + k) % count])
		var spread := 0.0
		for group: Array in groups:
			var points: Array = group.map(func(i: int) -> Vector3: return spawns[i].origin)
			var mid := _mean(points)
			for p: Vector3 in points:
				spread += _flat(p).distance_squared_to(_flat(mid))
		if spread < best_spread - 0.001:
			best_spread = spread
			best_groups = groups
	return best_groups


## One base per team out of the spawn pads alone: the pad in each team's arc
## nearest that arc's centroid. See the header.
static func fallback_bases(spawns: Array[Transform3D], teams: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if spawns.is_empty():
		return out
	var groups := split_pads(spawns, teams)
	for team in teams:
		var group: Array = groups[team]
		if group.is_empty():
			# More teams than pads: share one rather than have no base at all.
			out.append(spawns[team % spawns.size()].origin)
			continue
		var points: Array = group.map(func(i: int) -> Vector3: return spawns[i].origin)
		# The pad nearest the middle of the arc by bearing. An arc of four has
		# two pads equally near its middle, and taking the one anticlockwise of
		# it on *every* arc is what keeps the bases opposite each other on an
		# even ring: taking the nearer by distance let the island's two bases
		# come out 135 degrees apart instead of 180.
		var centre := _mean(spawns.map(func(t: Transform3D) -> Vector3: return t.origin))
		var middle := _bearing(_mean(points), centre)
		var chosen: Vector3 = points[0]
		var chosen_off := INF
		var chosen_signed := -INF
		for p: Vector3 in points:
			var signed := angle_difference(middle, _bearing(p, centre))
			var off := absf(signed)
			if off < chosen_off - TIE_BEARING \
					or (absf(off - chosen_off) <= TIE_BEARING and signed > chosen_signed):
				chosen = p
				chosen_off = minf(off, chosen_off)
				chosen_signed = signed
		out.append(chosen)
	return out


## Three neutral points between the first two bases. See the header.
static func fallback_letters(base_points: Array[Vector3],
		spawns: Array[Transform3D]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if base_points.size() < 2:
		# One team, or no pads at all: the middle of whatever there is.
		var middle := Vector3.ZERO
		if not spawns.is_empty():
			for pad: Transform3D in spawns:
				middle += pad.origin
			middle /= float(spawns.size())
		for i in 3:
			out.append(middle + Vector3(3.0 * float(i - 1), 0.0, 0.0))
		return out
	var a := base_points[0]
	var b := base_points[1]
	var mid := (a + b) * 0.5
	var axis := _flat(b - a)
	var across := Vector3(-axis.z, 0.0, axis.x).normalized()
	if across == Vector3.ZERO:
		across = Vector3.RIGHT
	# A third of the way to either base across the axis, kept between 4 and 10 m:
	# far enough apart that one carrier cannot sweep two, close enough that the
	# middle is one fight.
	var spread := clampf(axis.length() * 0.3, 4.0, 10.0)
	out.append(mid)
	out.append(mid + across * spread)
	out.append(mid - across * spread)
	return out


## Every letter point settled onto real ground, in G, U, B order. `space` null
## means there is no world to ask (a rules harness), and the points come back as
## planned.
func settle_letters(space: PhysicsDirectSpaceState3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var reference := 0.0
	for base: Vector3 in bases:
		reference += base.y
	reference = reference / float(bases.size()) if not bases.is_empty() else 0.0
	for point: Vector3 in letters:
		# Each card keeps clear of the ones already placed: two ideal points
		# either side of a rock stack can otherwise both be pushed round it onto
		# the same patch of floor.
		out.append(settle(space, point, point.y if letters_declared else reference, out))
	return out


## A standable spot at or near `point`: a floor under it, not too steep, with a
## Gub's worth of room above it, as close to `reference_y` in height as the
## column allows. Searches rings outward when the point itself fails, and
## returns `point` untouched when nothing anywhere nearby passes — a card in a
## strange place is a smaller problem than no card.
static func settle(space: PhysicsDirectSpaceState3D, point: Vector3,
		reference_y: float, avoid: Array[Vector3] = []) -> Vector3:
	if space == null:
		return point
	for near_only: bool in [true, false]:
		for ring in SEARCH_RINGS + 1:
			var tries := 1 if ring == 0 else SEARCH_BEARINGS
			for i in tries:
				var bearing := TAU * float(i) / float(tries)
				var at := point + Vector3(cos(bearing), 0.0, sin(bearing)) * SEARCH_STEP * ring
				var found := _ground(space, at, reference_y)
				if found == Vector3.INF \
						or (near_only and absf(found.y - reference_y) > NEAR_HEIGHT):
					continue
				if avoid.any(func(other: Vector3) -> bool:
						return other.distance_to(found) < MIN_APART):
					continue
				return found
	push_warning("CaptureLayout: nowhere to stand near %s; leaving the card there" % point)
	return point


## Peel one column top down and keep the best floor in it.
static func _ground(space: PhysicsDirectSpaceState3D, at: Vector3,
		reference_y: float) -> Vector3:
	var top := reference_y + 25.0
	var bottom := reference_y - 25.0
	var from := Vector3(at.x, top, at.z)
	var best := Vector3.INF
	for layer in MAX_LAYERS:
		var ray := PhysicsRayQueryParameters3D.create(from, Vector3(at.x, bottom, at.z))
		ray.collision_mask = LAYER_WORLD
		ray.hit_back_faces = false
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			break
		var p: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		if normal.y >= MIN_FLOOR_NORMAL and has_headroom(space, p):
			if best == Vector3.INF or absf(p.y - reference_y) < absf(best.y - reference_y):
				best = p
		from = p + Vector3.DOWN * 0.05
	return best


## Whether a Gub standing at `foot` fits there.
static func has_headroom(space: PhysicsDirectSpaceState3D, foot: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = Gub.CAPSULE_RADIUS
	capsule.height = Gub.STAND_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	# A few centimetres up, so the floor the capsule is standing on is not
	# itself counted as something in the way.
	query.transform = Transform3D(Basis.IDENTITY, foot + Vector3.UP * (CAPSULE_LIFT + 0.12))
	query.collision_mask = LAYER_WORLD
	return space.intersect_shape(query, 1).is_empty()


static func _bearing(p: Vector3, centre: Vector3) -> float:
	return atan2(p.z - centre.z, p.x - centre.x)


static func _mean(points: Array) -> Vector3:
	var sum := Vector3.ZERO
	for p: Vector3 in points:
		sum += p
	return sum / float(maxi(1, points.size()))


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
