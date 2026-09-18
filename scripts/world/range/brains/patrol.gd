extends RangeBrain
## Walks a short beat across its mark, stops at each end, and turns.
##
## The strafer's slow cousin, and a different lesson. A strafer runs and faces
## you, so it is a lead problem; a patroller **walks and faces its heading**, so
## it is a timing problem — you learn the pause at the end of the beat, which is
## the free shot, and the moment it turns, which is the one you have to lead
## into. A sentry that never stopped would be a strafer at half speed and worth
## nothing extra.
##
## Facing its travel is what puts it on the forward walk of the locomotion
## plane, so it reads as something going somewhere rather than something
## sidestepping. During the pause it turns to the shooter, because a dummy
## standing still with its back to the range is a dummy nobody can tell is
## still alive.

## Seconds stood at each end of the beat.
const PAUSE := 0.6
const SNAP := 0.05

var _x: float = 0.0
var _dir: float = 1.0
var _waiting: float = 0.0


func reset() -> void:
	super()
	_x = 0.0
	_waiting = 0.0
	_dir = 1.0 if _rng.randf() < 0.5 else -1.0


## Half the beat. The one patrol the map authors stands in a 6 m throwing lane
## at the 28 m mark, so 2.2 keeps the capsule 0.4 m off the rope; anywhere else
## it gets a 6 m beat.
func half_length() -> float:
	return param("length", 2.2 if zone() == "lanes" else 3.0)


func drive(bog: Bog, delta: float) -> void:
	_t += delta
	var half := half_length()
	var axis := right()
	var speed := Bog.WALK_SPEED
	var velocity := Vector3.ZERO

	if _waiting > 0.0:
		_waiting -= delta
	else:
		_x += _dir * speed * delta
		velocity = axis * (_dir * speed)
		if absf(_dir * half - _x) <= SNAP or absf(_x) >= half:
			_x = _dir * half
			_dir = -_dir
			_waiting = PAUSE
			velocity = Vector3.ZERO

	var pos := _station.origin + axis * _x
	pos.y = ground_y(bog, pos)
	# Heading while it walks, the shooter while it stands.
	var yaw := look_yaw(pos) if velocity.is_zero_approx() \
		else Bog.yaw_towards(velocity.normalized())
	go(bog, pos, yaw, velocity, true)
