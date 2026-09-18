extends RangeBrain
## Runs at whoever comes near, stands in their face for a second, and walks back.
##
## The one dummy that reacts, and the reason the scope could cut "dummies that
## shoot back" without the melee pit becoming a room full of statues. It never
## attacks and never touches you: what it teaches is the *timing* of something
## closing — how long a great sword's spin takes against a body arriving at
## 5.4 m/s, and how much of a spear's flight time you have left when it is
## already inside fifteen metres.
##
## ## It cannot leave its zone
##
## Every tick, the position is projected back inside `radius` of the station and
## the outward component of the velocity is dropped. Clamping the *position*
## rather than refusing to chase is what makes it unconditional: a player who
## sprints away does not tow the dummy out of the pit and across the range, and
## there is no case — a target lost mid-stride, a chase that started legally and
## ended outside — where the rule has to be re-argued. The map's one rusher
## stands at the exact centre of the melee pit, which is 10 m across, so 4.6 m
## is the pit floor less a capsule: it can reach anywhere inside the ring and
## can never climb the revetment.
##
## ## The states
##
## `IDLE` waits for a living human inside `look` and inside the zone. `CHASE`
## runs flat at them until it is `REACH` from their body, loses them, or runs
## out of `CHASE_MAX`. `HOLD` stands and stares for `HOLD_TIME`. `RETREAT` walks
## home at `WALK_SPEED` — walking, because a dummy that sprinted back to its mark
## would read as a second attack run — and `COOLDOWN` keeps it there for half a
## second so it cannot re-trigger on the same player standing where they were.
##
## **A chase is dropped the moment the target leaves.** Not when the six-second
## timer runs out: a target that has walked out of the pit is gone, and a rusher
## that kept running at them would spend those six seconds pressed against the
## inside of its own fence, which looks exactly like a dummy that has broken.
## The drop is at `LOSE` times `look` rather than at `look` itself, so somebody
## standing right on the edge does not switch it on and off every other frame.

enum State { IDLE, CHASE, HOLD, RETREAT }

## How close it gets. Two metres is inside a great sword's 1.7 m advance and
## well inside a spear's arm, which is the distance being taught.
const REACH := 2.0
const HOLD_TIME := 1.0
## The longest a chase may run before it gives up and walks home. Stops a rusher
## whose target is standing on the lip of the pit from jogging on the spot for
## the rest of the session.
const CHASE_MAX := 6.0
const COOLDOWN := 0.5
const HOME := 0.3
## How far past `look` a target may get before the chase is dropped. Hysteresis,
## so the edge of the acquisition range is not a place a rusher flickers.
const LOSE := 1.5

var _state: State = State.IDLE
var _state_t: float = 0.0
var _target: int = 0


func reset() -> void:
	super()
	_state = State.IDLE
	_state_t = 0.0
	_target = 0


func radius() -> float:
	return param("radius", 4.6 if zone() == "melee" else 10.0)


func look() -> float:
	return param("look", 12.0 if zone() == "melee" else 25.0)


func _to(state: State) -> void:
	_state = state
	_state_t = 0.0


func drive(bog: Bog, delta: float) -> void:
	_t += delta
	_state_t += delta
	var centre := _station.origin
	var limit := radius()
	var pos := bog.global_position
	var velocity := Vector3.ZERO
	var yaw := station_yaw()

	var target := MatchState.bogs.get(_target) as Bog
	if target != null and (not target.alive or Net.is_dummy(target.peer_id)):
		target = null

	match _state:
		State.IDLE:
			pos = centre
			yaw = look_yaw(pos, look())
			if _state_t >= COOLDOWN:
				var found := nearest_human(centre, look())
				# Inside the zone with a little grace, or the pit's rusher would
				# set off after somebody walking past on the rim.
				if found != null and _flat(found.global_position - centre).length() <= limit + 3.0:
					_target = found.peer_id
					_to(State.CHASE)
		State.CHASE:
			if target == null or _lost(target, centre, limit):
				_target = 0
				_to(State.RETREAT)
			else:
				var toward := _flat(target.global_position - pos)
				yaw = yaw_to(pos, target.global_position)
				var gap := target.distance_to_body(bog.body_centre())
				if gap <= REACH or _state_t >= CHASE_MAX:
					_to(State.HOLD)
				elif toward.length() > 0.001:
					velocity = toward.normalized() * Bog.RUN_SPEED
					pos += velocity * delta
		State.HOLD:
			yaw = yaw_to(pos, target.global_position) if target != null else yaw
			if target == null or _state_t >= HOLD_TIME:
				_to(State.RETREAT)
		State.RETREAT:
			var home := _flat(centre - pos)
			yaw = station_yaw()
			if home.length() <= HOME:
				pos = centre
				_target = 0
				_to(State.IDLE)
			else:
				yaw = Bog.yaw_towards(home.normalized())
				velocity = home.normalized() * Bog.WALK_SPEED
				pos += velocity * delta

	# The fence, applied to every state and every exit. See the header.
	var out := _flat(pos - centre)
	if out.length() > limit:
		pos = centre + out.normalized() * limit
		var outward := velocity.dot(out.normalized())
		if outward > 0.0:
			velocity -= out.normalized() * outward

	pos.y = ground_y(bog, pos)
	go(bog, pos, yaw, velocity, true)


## Has the target left? Either it is further from this dummy than it could have
## been acquired from, or it has left the zone the dummy is fenced into — and
## chasing something you cannot reach is the one thing the fence cannot fix.
func _lost(target: Bog, centre: Vector3, limit: float) -> bool:
	if _flat(target.global_position - centre).length() > limit + 3.0:
		return true
	return _flat(target.global_position - _station.origin).length() > look() * LOSE


func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v


func state_name() -> String:
	return ["idle", "chase", "hold", "retreat"][_state]
