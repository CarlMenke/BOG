extends RangeBrain
## Orbits the middle of the melee pit at running speed, facing inward.
##
## The sword's target. A great sword's arc is 75 degrees and advances 1.7 m, so
## what it is hard to hit is not something far away but something whose bearing
## is changing while you swing — and an orbit is the only motion where the range
## stays constant and the bearing never stops moving. Two of them, going
## opposite ways (the sign comes off the seeded RNG), so the pit is never a
## single rhythm to time.
##
## ## Where the middle is
##
## Not a constant, and not asked of the map: the marker's **own facing** is what
## says where the centre of the ring is. `range_map.gd` yaws every melee dummy
## with `Bog.yaw_towards(pit_centre - at)`, so a pit dummy's -Z already points at
## the middle — which means the centre is `radius` metres straight ahead of it,
## and the two authored circlers sit exactly 3.606 m out. Reading it off the
## marker rather than copying the pit's coordinates into this file is the
## difference between a dummy that circles the pit and a dummy that circles the
## place the pit used to be.
##
## It faces the centre rather than its heading, which puts it on the run ring of
## the locomotion plane sideways-on — the strafe clip, at speed, which is what
## something circling you actually looks like.

var _angle: float = 0.0
var _spin: float = 1.0


func reset() -> void:
	super()
	_angle = 0.0
	_spin = 1.0 if _rng.randf() < 0.5 else -1.0


func radius() -> float:
	return maxf(param("radius", 3.6), 0.5)


## The point it goes round: `radius` along the marker's own -Z. See the header.
func centre() -> Vector3:
	return _station.origin + forward() * radius()


func drive(bog: Bog, delta: float) -> void:
	_t += delta
	var r := radius()
	# Angular speed from linear speed, so the orbit is always run-paced whatever
	# the radius is. A fixed omega would make a wide ring supersonic.
	_angle += _spin * (Bog.RUN_SPEED / r) * delta
	var middle := centre()
	# Angle zero is the station itself, so a reset puts it back on its mark.
	var start := _station.origin - middle
	start.y = 0.0
	var offset := start.rotated(Vector3.UP, _angle)
	var pos := middle + offset
	# The tangent, in the direction of travel: the orbit's own derivative, which
	# is the radius turned a quarter turn and scaled by the spin's sign.
	var velocity := offset.normalized().rotated(Vector3.UP, PI * 0.5) \
		* Bog.RUN_SPEED * _spin
	velocity.y = 0.0
	pos.y = ground_y(bog, pos)
	go(bog, pos, yaw_to(pos, middle), velocity, true)
