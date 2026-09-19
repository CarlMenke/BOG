class_name GuidePath
extends RefCounted
## One target's route, from the raw navmesh corridor to the polyline that gets
## drawn — and the state that keeps it from twitching.
##
## `NavigationServer3D.map_get_path` answers with a funnelled corridor: a
## handful of points, hard corners, and every jump link crossed as a straight
## segment through thin air. Drawn as it comes it looks like a debug overlay,
## and worse, it *lies* — the straight bit over the gap reads as "walk here".
## So each route is put through the same four steps every time:
##
##   1. the segments that are really jumps become `JumpArc` parabolas, and are
##      locked against every smoother downstream;
##   2. everything else is Chaikin-smoothed twice, which rounds the funnel's
##      corners into something a runner would take;
##   3. the whole thing is resampled at a fixed spacing, because the ribbon's
##      dashes are measured in metres along it and uneven points make uneven
##      dashes;
##   4. it is lifted off the floor, so it is a line over the ground and not a
##      line inside it.
##
## Then the two pieces of hysteresis that make it feel calm rather than
## reactive. **In space**: the shown polyline chases the solved one at 12 m/s
## instead of being replaced, so a repath that finds a different way round a
## container sweeps across instead of snapping. **In distance**: a line shorter
## than 2 m fades out and does not come back until 3 m, so standing beside the
## letter does not strobe the ribbon on and off.
##
## Cosmetic and per-client, like everything else under `scripts/world/nav`
## (D-010); no rule reads a metre of it (D-007).

## How often a route is re-solved, and how far a target may walk before it is
## re-solved early. A fifth of a second is four or five frames of a chase and is
## invisible once the smoothing is in front of it.
const REPATH_INTERVAL := 0.2
const TARGET_MOVED := 0.5

## How close a path segment's two ends must be to a link's two ends before the
## segment is called a jump. Half a metre: the funnel puts its corner on the
## link's own position, and the slack is for the lift and the agent radius.
const LINK_SNAP := 0.5
## Points in a drawn jump. Nine is smooth at the six metres a big leap covers
## and cheap at the one metre a hop does.
const ARC_POINTS := 9

const RESAMPLE := 0.35
const LIFT := 0.35
## Ribbons are capped rather than allowed to grow with the map: 400 points is
## 140 m of line at the resample spacing, which is further than any map is
## across, and it bounds the per-frame mesh rebuild honestly.
const MAX_POINTS := 400

const SMOOTH_SPEED := 12.0
## Below this a shown point has not really moved, and the mesh does not need
## rebuilding this frame.
const MOVED_EPSILON := 0.004

const FADE_OUT_UNDER := 2.0
const FADE_IN_OVER := 3.0
const FADE_TIME := 0.25

## How close a second line must stay to the nearest one to count as sharing its
## trunk. Wider than the ribbon, narrower than a doorway.
const PREFIX_SHARE := 0.6

var key: String = ""
var kind: String = ""
var colour: Color = Color.WHITE
var target: Vector3 = Vector3.ZERO

## Metres of route, after smoothing. What the targets are sorted by.
var length: float = 0.0
## 0..1, the hysteresis fade.
var fade: float = 1.0
## What the renderer should draw: the whole shown polyline for the nearest
## target, and only the divergent tail for the others.
var points := PackedVector3Array()
## Did any drawn point move this frame? The mesh rebuild is skipped when not.
var moved: bool = false

var _solved := PackedVector3Array()
var _shown := PackedVector3Array()
var _clock: float = 0.0
var _pathed_to: Vector3 = Vector3.INF
var _has_route: bool = false
var _fade_goal: float = 1.0


func _init(target_key: String, target_kind: String, target_colour: Color) -> void:
	key = target_key
	kind = target_kind
	colour = target_colour


## Bring this route up to date for one frame.
##
## The head and the tail are re-anchored every frame rather than only on a
## repath: between repaths the player is running and the target may be running
## too, and a ribbon whose first point is a fifth of a second behind the
## camera's feet is a ribbon that visibly trails the player.
func solve(delta: float, from: Vector3, to: Vector3, bake: NavBake) -> void:
	target = to
	_clock -= delta
	if not _has_route or _clock <= 0.0 or to.distance_to(_pathed_to) > TARGET_MOVED:
		_clock = REPATH_INTERVAL
		_route(from, to, bake)
	var count := _solved.size()
	if count >= 2:
		_solved[0] = from + Vector3.UP * LIFT
		_solved[count - 1] = to + Vector3.UP * LIFT
	_advance(delta)
	length = polyline_length(_shown)
	_settle_fade(delta)
	points = _shown


## The whole shown polyline, trunk included — what the other lines measure
## themselves against.
func shown() -> PackedVector3Array:
	return _shown


## Share `nearest`'s trunk: draw only from where this route stops agreeing with
## it. Both polylines are resampled at the same spacing from the same head, so
## comparing them index for index is comparing the same distance along each —
## which is both the right question and an O(n) one.
func trim_to(nearest: GuidePath) -> void:
	points = _shown
	if nearest == null or nearest == self:
		return
	var trunk := nearest.shown()
	var cut := 0
	var count := mini(_shown.size(), trunk.size())
	while cut < count and _shown[cut].distance_to(trunk[cut]) <= PREFIX_SHARE:
		cut += 1
	if cut <= 1:
		return
	# One point back up the trunk, so the tail grows out of the shared line
	# instead of starting in mid-air beside it.
	points = _shown.slice(cut - 1)


# ------------------------------------------------------------------- route ---

func _route(from: Vector3, to: Vector3, bake: NavBake) -> void:
	_pathed_to = to
	_has_route = true

	var raw := PackedVector3Array()
	if bake != null:
		raw = bake.find_path(from, to)
	# Before the bake lands, and for a target standing somewhere the navmesh
	# does not reach, the straight line is the honest answer: it is still the
	# right bearing, and a missing line reads as a broken game.
	if raw.size() < 2:
		raw = PackedVector3Array([from, to])

	var links := bake.link_points() if bake != null else PackedVector3Array()
	var pts := PackedVector3Array()
	var locked := PackedByteArray()
	pts.append(raw[0])
	locked.append(0)
	for i in range(raw.size() - 1):
		var a := raw[i]
		var b := raw[i + 1]
		if is_link_segment(a, b, links):
			# Both ends of the jump are locked, so the smoother below leaves the
			# parabola exactly where `JumpArc` put it.
			locked[locked.size() - 1] = 1
			var arc := JumpArc.arc_points(a, b, ARC_POINTS)
			for k in range(1, arc.size()):
				pts.append(arc[k])
				locked.append(1)
		else:
			pts.append(b)
			locked.append(0)

	for _pass in 2:
		var smoothed := _chaikin(pts, locked)
		pts = smoothed[0]
		locked = smoothed[1]

	_solved = _resample(pts)
	for i in _solved.size():
		_solved[i] = _solved[i] + Vector3.UP * LIFT


## Corner cutting, twice, except across a jump. The locked test is on the
## *segment*: a segment with a locked point at each end is inside an arc and is
## copied through untouched, and the duplicate points that leaves at the joins
## are eaten by the resample.
static func _chaikin(pts: PackedVector3Array, locked: PackedByteArray) -> Array:
	if pts.size() < 3:
		return [pts, locked]
	var out := PackedVector3Array()
	var out_locked := PackedByteArray()
	out.append(pts[0])
	out_locked.append(locked[0])
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		if locked[i] == 1 and locked[i + 1] == 1:
			out.append(a)
			out_locked.append(1)
			out.append(b)
			out_locked.append(1)
		else:
			out.append(a.lerp(b, 0.25))
			out_locked.append(locked[i])
			out.append(a.lerp(b, 0.75))
			out_locked.append(locked[i + 1])
	out.append(pts[pts.size() - 1])
	out_locked.append(locked[locked.size() - 1])
	return [out, out_locked]


## Even spacing, and never more than `MAX_POINTS` of them: past that the spacing
## is widened rather than the tail being cut off, because half a line pointing
## at nothing is worse than a slightly coarser one.
static func _resample(pts: PackedVector3Array) -> PackedVector3Array:
	var total := polyline_length(pts)
	var out := PackedVector3Array()
	if pts.size() < 2 or total <= 0.0001:
		return pts
	var spacing := maxf(RESAMPLE, total / float(MAX_POINTS - 1))
	var walked := 0.0
	var next := 0.0
	out.append(pts[0])
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var step := a.distance_to(b)
		if step <= 0.0001:
			continue
		while next + spacing <= walked + step:
			next += spacing
			out.append(a.lerp(b, (next - walked) / step))
		walked += step
	# The tail is pinned rather than appended blindly: a resample that happened
	# to land on the last point would otherwise leave two points on top of each
	# other, and a zero-length segment has no tangent for the ribbon to face the
	# camera with.
	var last := pts[pts.size() - 1]
	if out[out.size() - 1].distance_to(last) > 0.01:
		out.append(last)
	else:
		out[out.size() - 1] = last
	return out


# --------------------------------------------------------------- smoothing ---

## Chase the solved route rather than snapping onto it. Point `i` of the shown
## line is the same fraction along it as point `i` of the solved one, which is
## what makes "move toward" mean "sweep across" and not "slide along".
func _advance(delta: float) -> void:
	moved = false
	if _solved.size() < 2:
		_shown = _solved.duplicate()
		moved = true
		return
	if _shown.size() != _solved.size():
		_shown = _refit(_shown, _solved.size()) if _shown.size() >= 2 else _solved.duplicate()
		moved = true
	var step := SMOOTH_SPEED * delta
	for i in _solved.size():
		var was := _shown[i]
		var now := was.move_toward(_solved[i], step)
		if not moved and was.distance_to(now) > MOVED_EPSILON:
			moved = true
		_shown[i] = now


## Re-space a polyline onto `count` points by arc fraction, so a route that has
## just gained or lost points still has somewhere to chase from.
static func _refit(poly: PackedVector3Array, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(count)
	for i in count:
		out[i] = sample_at_fraction(poly, float(i) / float(count - 1))
	return out


func _settle_fade(delta: float) -> void:
	if length < FADE_OUT_UNDER:
		_fade_goal = 0.0
	elif length > FADE_IN_OVER:
		_fade_goal = 1.0
	fade = move_toward(fade, _fade_goal, delta / FADE_TIME)


# ------------------------------------------------------------------ shared ---

## Is this pair of path points a jump link being crossed? Both orders, because
## a two-way link is walked from either end.
static func is_link_segment(a: Vector3, b: Vector3,
		link_points: PackedVector3Array) -> bool:
	var i := 0
	while i + 1 < link_points.size():
		var start := link_points[i]
		var end := link_points[i + 1]
		if a.distance_to(start) <= LINK_SNAP and b.distance_to(end) <= LINK_SNAP:
			return true
		if a.distance_to(end) <= LINK_SNAP and b.distance_to(start) <= LINK_SNAP:
			return true
		i += 2
	return false


## How many of `path`'s segments are jumps. `tools/nav_check.gd` prints it: a
## map whose routes take no links at all is a map whose parkour the line is
## walking round.
static func link_segments(path: PackedVector3Array,
		link_points: PackedVector3Array) -> int:
	var count := 0
	for i in range(path.size() - 1):
		if is_link_segment(path[i], path[i + 1], link_points):
			count += 1
	return count


static func polyline_length(poly: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(poly.size() - 1):
		total += poly[i].distance_to(poly[i + 1])
	return total


## The point a given fraction of the way along a polyline, by arc length.
static func sample_at_fraction(poly: PackedVector3Array, fraction: float) -> Vector3:
	if poly.is_empty():
		return Vector3.ZERO
	if poly.size() == 1:
		return poly[0]
	var want := polyline_length(poly) * clampf(fraction, 0.0, 1.0)
	var walked := 0.0
	for i in range(poly.size() - 1):
		var step := poly[i].distance_to(poly[i + 1])
		if walked + step >= want and step > 0.0001:
			return poly[i].lerp(poly[i + 1], (want - walked) / step)
		walked += step
	return poly[poly.size() - 1]
