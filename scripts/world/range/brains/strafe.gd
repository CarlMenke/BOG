extends RangeBrain
## Shuttles across its mark at running speed, facing you the whole way.
##
## The lead-and-track target. It moves along its marker's own **X** — across the
## line of fire rather than up and down it — so the range to it never changes
## and the only thing being practised is the lead. That is the whole point of
## the behaviour: a target that also changed distance would be teaching two
## things at once and neither of them cleanly.
##
## It runs rather than walks, and it faces the shooter rather than its heading.
## Both are deliberate and both are about the animation: a Bog moving at
## `RUN_SPEED` sideways to its facing lands on the run ring of the locomotion
## plane, which is the strafe clip — the same pose a player sees on somebody
## circling them in a fight. Walking it, or facing it along its own heading,
## would make it play a forward run and look like something jogging past.
##
## The ends are eased over `EASE` rather than reversed on the spot, because an
## instantaneous reversal at 5.4 m/s is a velocity discontinuity the blend plane
## reads as a teleport between two opposite strafes, and the feet skate.

## Seconds of deceleration into each end of the shuttle, and back out.
const EASE := 0.25
## How close to the end counts as arrived. Without it the eased approach is
## asymptotic and the dummy creeps at the turn forever.
const SNAP := 0.06
## The slowest it is allowed to crawl through a turn, as a fraction of its
## speed, so the pause at each end is a beat and not a stop.
const EASE_FLOOR := 0.10

var _x: float = 0.0
var _dir: float = 1.0


func reset() -> void:
	super()
	_x = 0.0
	# Which way it sets off, and where in the shuttle it starts. Two strafers in
	# the gallery would otherwise move as a pair, which reads as one object.
	_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	_x = _rng.randf_range(-0.4, 0.4) * half_width()


## Half the shuttle, in metres. A throwing lane is 6 m between its rope fences,
## so 2.4 keeps the 0.38 m capsule well clear of them; the gallery's dummies
## have open ground between the waist walls and the backstops and get 3.0.
func half_width() -> float:
	return param("width", 2.4 if zone() == "lanes" else 3.0)


func drive(bog: Bog, delta: float) -> void:
	_t += delta
	var half := half_width()
	var speed := Bog.RUN_SPEED
	var remaining := absf(_dir * half - _x)
	# The distance it takes to bleed off, at this speed, over EASE seconds.
	var ease_distance := 0.5 * speed * EASE
	if remaining < ease_distance and ease_distance > 0.0001:
		speed *= maxf(remaining / ease_distance, EASE_FLOOR)
	_x += _dir * speed * delta
	if remaining <= SNAP:
		_x = _dir * half
		_dir = -_dir

	var axis := right()
	var pos := _station.origin + axis * _x
	pos.y = ground_y(bog, pos)
	go(bog, pos, look_yaw(pos), axis * (_dir * speed), true)
