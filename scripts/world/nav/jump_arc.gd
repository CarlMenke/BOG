class_name JumpArc
extends RefCounted
## The Bog's jump, as arithmetic — the one place that knows how far it can get.
##
## This model was written inside `tools/parkour_report.gd`, where it answered a
## checker's question: can a Bog cross this gap. The guide line asks the same
## question from the other end — *which* gaps may a route cross, and what shape
## does the leap draw in the air — and two copies of a parabola is how a map
## checker and a route drawn on screen end up disagreeing about what the player
## can do. So the arc moved here and the report reads it (D-098: one home per
## concern).
##
## Everything is derived from `Bog`'s constants and project gravity rather than
## typed, so a change to the character's jump moves the checker, the navmesh's
## jump links and the drawn arc together, or fails the gate.
##
## Three ways across a gap, named after what the player does:
##
##   hop   jump at run speed.
##   leap  jump, then spend the dive at the apex. The staple.
##   big   jump, then spend the dive on the very next tick, which is the
##         earliest it is legal. Longer and much harder to aim.
##
## Nothing here is gameplay. It is read by a development tool, by the navmesh's
## link builder and by a cosmetic line drawn on one client (D-007: nothing that
## can change the outcome of a match may be decided per client).

const RUN := Bog.RUN_SPEED
const JUMP := Bog.JUMP_VELOCITY
const DIVE_FORWARD := Bog.DIVE_FORWARD_SPEED
const DIVE_UP := Bog.DIVE_UP_VELOCITY
## The one number here that is a literal, because it is a literal in
## `Bog._apply_gravity` too: falling is 1.35x as fast as rising, which is what
## makes a jump feel decisive. If that ever becomes a constant, name it here.
const FALL_MULTIPLIER := 1.35

## What a leap is worth against a hop when a route is costed. A plain
## breadth-first walk minimises the *number* of jumps, which reaches for the
## longest edge available every time; weighting a leap above two hops says the
## truer thing — you hop while hopping will do, and you commit to a dive when it
## will not. `tools/parkour_report.gd` costs its reachability tree with it and
## `JumpLinks` puts it on every jump link, so a path and a checker agree about
## which way round the map is cheaper.
const LEAP_COST := 2.25

## Derived once, on first use rather than at class load, because
## `ProjectSettings` is the authority on gravity and a static initialiser is not
## a place to depend on boot order.
static var _derived: bool = false
static var _gravity: float = 24.0
static var _apex: float = 0.0
static var _dive_apex: float = 0.0
static var _tick_apex: float = 0.0
static var _tick_start: float = 0.0
static var _tick_forward: float = 0.0
static var _tick_rise: float = 0.0


## Gravity, as the project states it.
static func gravity() -> float:
	_derive()
	return _gravity


## How high a plain jump gets.
static func apex() -> float:
	_derive()
	return _apex


## How high a jump plus a dive spent at the apex gets.
static func dive_apex() -> float:
	_derive()
	return _dive_apex


## How high a jump plus a dive one physics tick later gets — the highest a Bog
## can put itself, and therefore the number an off-limits perch is held against.
static func tick_apex() -> float:
	_derive()
	return _tick_apex


## A jump at run speed. Up under gravity, down under 1.35x gravity, and no
## horizontal acceleration worth modelling — air control is weak on purpose and
## the arc is what the layouts were spaced against. `-1.0` for a rise the jump
## cannot clear at all, which is not a distance and must never be compared as
## one without the caller meaning it.
static func hop_reach(rise: float) -> float:
	_derive()
	if rise > _apex:
		return -1.0
	var up := JUMP / _gravity
	var down := sqrt(2.0 * (_apex - rise) / (FALL_MULTIPLIER * _gravity))
	return RUN * (up + down)


## Jump, then dive at the apex: run speed until the top of the jump, then the
## dive sets the horizontal speed outright and adds its own upward kick.
static func leap_reach(rise: float) -> float:
	_derive()
	if rise > _dive_apex:
		return -1.0
	var up := DIVE_UP / _gravity
	var down := sqrt(2.0 * (_dive_apex - rise) / (FALL_MULTIPLIER * _gravity))
	return RUN * (JUMP / _gravity) + DIVE_FORWARD * (up + down)


## Jump and dive on the very next tick, which is the earliest the dive is legal
## — the jump zeroes `_coyote`. Nearly the whole of the jump's upward speed is
## still there for the dive to add to, which is why this goes half as far again
## as a leap does.
static func big_reach(rise: float) -> float:
	_derive()
	if rise > _tick_apex:
		return -1.0
	var down := sqrt(2.0 * (_tick_apex - rise) / (FALL_MULTIPLIER * _gravity))
	return _tick_forward + DIVE_FORWARD * (_tick_rise + down)


## The shape a jump draws in the air, as `count` points from `from` to `to`.
##
## Not the true trajectory: the true one is two parabolas glued at the apex
## (rising under gravity, falling under 1.35x it) and it does not in general
## pass through the landing point at all, because a player aims a jump and this
## is being asked to *draw* one that has already been decided. So it is a single
## parabola pinned to both ends whose summit is a hop's apex above whichever end
## is higher — which is what the jump looks like from the side, and reads at a
## glance as "you leave the ground here and land there".
##
## The sag term is solved rather than guessed: with `y(t) = y0 + rise·t +
## 4s·t(1−t)`, the curve's maximum is `y0 + b²/(16s)` for `b = rise + 4s`, and
## the positive root of that against the wanted summit is the `s` below. The
## smaller root is the degenerate straight line.
static func arc_points(from: Vector3, to: Vector3, count: int) -> PackedVector3Array:
	_derive()
	var out := PackedVector3Array()
	var steps := maxi(count, 2)
	var rise := to.y - from.y
	var height := maxf(from.y, to.y) + _apex - from.y
	# `height` is always at least a hop's apex above `rise`, so the root is real.
	var sag := (2.0 * height - rise) * 0.25 + sqrt(maxf(height * (height - rise), 0.0)) * 0.5
	out.resize(steps)
	for i in steps:
		var t := float(i) / float(steps - 1)
		var point := from.lerp(to, t)
		point.y = from.y + rise * t + 4.0 * sag * t * (1.0 - t)
		out[i] = point
	return out


static func _derive() -> void:
	if _derived:
		return
	_derived = true
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
