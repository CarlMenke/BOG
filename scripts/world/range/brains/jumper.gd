extends RangeBrain
## Stands on its mark and jumps, on a clock, in the game's own arc.
##
## ## The arc is solved, not integrated
##
## A dummy has no gravity — nothing calls `move_and_slide` on it — so this brain
## has to produce the arc itself, and the tempting way to do that is to carry a
## `vy`, subtract gravity from it every tick and clamp at the floor. That drifts,
## and it drifts **one way**: floating-point error and a fixed timestep both
## overshoot the landing, a clamp can only push the dummy back up, and the tick
## it lands on is a tick whose fall was longer than it should have been. Over a
## session in the ability yard that is a dummy standing progressively deeper in
## the bog.
##
## So the whole arc is a closed form of the time since take-off, against the
## numbers `bog.gd` actually uses:
##
##   rise   `JUMP_VELOCITY` 9.0 under the project's gravity 24        0.375 s
##   apex   `Bog.apex_for(9.0)` — asked, never retyped                1.6875 m
##   fall   the same drop under `_apply_gravity`'s 1.35x on the way   0.3227 s
##          down, which is why the fall is faster than the rise
##   total                                                            0.6977 s
##
## and the landing height **is** the launch height by construction rather than
## by a clamp. The published `vy` is that curve's own derivative, which matters
## for more than honesty: `BogAnimator._scrub_air` reads `vertical_speed()` and
## scrubs the leap clip by where the body is between its `lift`, `apex` and
## `land` markers, so a driven jump and a played jump are the same pose at the
## same height.
##
## ## The take-off
##
## `jumped` is passed on the launch tick, which bumps `sync_jump_serial`. The
## grounded flag going false would open an airtime on its own — the animator has
## a branch for walking off a ledge — but a serial cannot collapse when two
## jumps land inside one dropped packet, and it is what the real Bog publishes.
## Because the horizontal velocity is zero the animator picks the standing
## take-off one-shot and the air loop rather than the running leap, which is
## correct: this is a Bog jumping on the spot.

var _period: float = 2.5
## Seconds into the current airtime, or -1 while it is waiting on the ground.
var _air: float = -1.0
var _launch_y: float = 0.0


func reset() -> void:
	super()
	_period = maxf(param("period", 2.5) + _rng.randf_range(-0.6, 0.6), 0.9)
	_air = -1.0


static func gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))


## How long the rise takes. `Bog.JUMP_VELOCITY` and the project's gravity, asked
## rather than written down, so this moves the day either of them does.
static func rise_time() -> float:
	return Bog.JUMP_VELOCITY / maxf(gravity(), 0.01)


static func fall_time() -> float:
	return sqrt(2.0 * Bog.apex_for(Bog.JUMP_VELOCITY) / maxf(gravity() * 1.35, 0.01))


static func air_time() -> float:
	return rise_time() + fall_time()


## Height above the launch point, and the vertical speed there, `t` seconds into
## the arc. Returned together because they are one curve and a caller that had
## to ask twice could ask at two different times.
static func arc(t: float) -> Vector2:
	var g := gravity()
	var up := rise_time()
	if t <= up:
		return Vector2(Bog.JUMP_VELOCITY * t - 0.5 * g * t * t, Bog.JUMP_VELOCITY - g * t)
	var down := t - up
	var gd := g * 1.35
	return Vector2(Bog.apex_for(Bog.JUMP_VELOCITY) - 0.5 * gd * down * down, -gd * down)


func drive(bog: Bog, delta: float) -> void:
	_t += delta
	var pos := _station.origin
	var jumped := false

	if _air < 0.0:
		# On the ground, waiting. The floor is sampled here and held for the
		# whole flight, so the arc is measured against the ground it left even
		# if the ray would find something else mid-air.
		_launch_y = ground_y(bog, pos)
		pos.y = _launch_y
		if _t >= _period:
			_air = 0.0
			jumped = true
			_t = 0.0
		else:
			go(bog, pos, look_yaw(pos), Vector3.ZERO, true)
			return

	_air += delta
	if _air >= air_time():
		# Down, exactly where it left. Not "close enough and clamped".
		_air = -1.0
		_t = 0.0
		pos.y = _launch_y
		go(bog, pos, look_yaw(pos), Vector3.ZERO, true)
		return

	var here := arc(_air)
	pos.y = _launch_y + here.x
	go(bog, pos, look_yaw(pos), Vector3(0.0, here.y, 0.0), false, false, jumped)


func is_airborne() -> bool:
	return _air >= 0.0
