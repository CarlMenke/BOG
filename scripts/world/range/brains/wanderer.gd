extends RangeBrain
## Walks to a random spot near its mark, stands about, and picks another.
##
## The unpredictable target, and the only one whose next move cannot be read off
## its last one. Everything else in this folder is periodic — a strafer's beat, a
## pop-up's clock, a jumper's rhythm — and periodic targets are learned rather
## than tracked. This one has to be tracked.
##
## Random, but **seeded from the zone and the peer id**, so the same dummy walks
## the same walk on every run of the range and on every run of the gate. That is
## the difference between a target that is unpredictable and a test that is
## flaky; `_rng` is set up once in `RangeBrain._setup` and never reseeded.
##
## It faces its heading while it walks and the nearest player while it stands,
## for the patrol's reason: something moving should look like it is going
## somewhere, and something stopped should look like it noticed you.

const ARRIVE := 0.25

var _goal := Vector3.ZERO
var _waiting: float = 0.0


func reset() -> void:
	super()
	_goal = _station.origin
	_waiting = _rng.randf_range(0.0, 1.0)


func radius() -> float:
	return param("radius", 6.0)


## A point inside the circle, uniformly by **area** — `sqrt` on the radius, not a
## plain `randf`, or two thirds of the walks end up in the middle third of the
## zone and the dummy never visits its own edge.
func _pick() -> Vector3:
	var bearing := _rng.randf() * TAU
	var distance := sqrt(_rng.randf()) * radius()
	return _station.origin + Vector3(cos(bearing), 0.0, sin(bearing)) * distance


func drive(bog: Bog, delta: float) -> void:
	_t += delta
	var pos := bog.global_position
	var velocity := Vector3.ZERO
	var yaw := station_yaw()

	if _waiting > 0.0:
		_waiting -= delta
		yaw = look_yaw(pos)
	else:
		var toward := _goal - pos
		toward.y = 0.0
		if toward.length() <= ARRIVE:
			_goal = _pick()
			_waiting = _rng.randf_range(0.5, 2.0)
			yaw = look_yaw(pos)
		else:
			velocity = toward.normalized() * Bog.WALK_SPEED
			yaw = Bog.yaw_towards(velocity.normalized())
			pos += velocity * delta

	# Belt and braces on the zone: the goal is always inside it, so this can
	# only bite if something else moved the body — a respawn, or a magnet.
	var out := pos - _station.origin
	out.y = 0.0
	if out.length() > radius():
		pos = _station.origin + out.normalized() * radius()

	pos.y = ground_y(bog, pos)
	go(bog, pos, yaw, velocity, true)
