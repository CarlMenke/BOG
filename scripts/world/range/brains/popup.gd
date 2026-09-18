extends RangeBrain
## Drops out of sight behind its cover and comes back up on a clock.
##
## ## Why it sinks, and does not crouch
##
## The obvious mechanism is a crouch behind a low wall, and it does not survive
## the numbers. A Bog stands `STAND_HEIGHT` 1.55 m and crouches `CROUCH_HEIGHT`
## 1.35 m; the range's gallery walls and its lane cover blocks are **1.25 m**.
## Crouching hides twenty centimetres of a target behind a wall that was already
## too short, and what is left is a head and shoulders — which is not "in cover",
## it is "a smaller target", and the two teach opposite lessons.
##
## So it goes down a hole. `SINK` metres straight down, under the bog slab,
## which is solid collision on the world layer for the whole of the range: every
## projectile ray from a firing line has to cross the floor to reach it, and the
## great sword's 1.7 m advance does not span 2.6 m of vertical. Down is
## genuinely unhittable rather than nearly unhittable, and up is an ordinary
## standing Bog that everything in the game can kill.
##
## **2.6 m and not 1.6** is the nameplate's doing. A `Nameplate` floats about
## 2.1 m over a Bog's feet, its visibility is not one of the replicated fields,
## and this brain runs on the host only — so a shallower hole leaves a name
## hanging over the grass with nothing under it on every client, and there is no
## host-side fix for that. Sinking past the plate is the fix.
##
## ## Why it does not animate as a jump
##
## The ramp publishes `grounded = true` and a velocity of **zero** throughout,
## so `BogAnimator._track_airtime` never opens an airtime and the dummy rises
## and falls in its idle pose. Publishing the real vertical velocity would be
## honest about the motion and wrong about the picture: a Bog rising at 7 m/s
## with its feet off the floor is the leap clip, and a pop-up target that leaps
## out of the ground is a different game.

## How far down. See the header.
const SINK := 2.6
## Seconds of travel each way. Long enough to be seen starting, short enough
## that the window to shoot is the window that was advertised.
const RAMP := 0.35
## The share of the cycle it spends up.
const UP_SHARE := 0.55


var _period: float = 3.0


func reset() -> void:
	super()
	_period = maxf(param("period", 3.0) + _rng.randf_range(-0.5, 0.5), 1.2)
	# A stagger, so the gallery's three do not surface as a chorus line.
	_t = _rng.randf() * cycle()


func sink() -> float:
	return param("sink", SINK)


func ramp() -> float:
	return param("ramp", RAMP)


## One whole up-down, ramps included.
func cycle() -> float:
	return _period + 2.0 * ramp()


## How far below its mark the dummy is, `phase` seconds into a cycle. Written as
## one function of time rather than a state machine because every part of it is
## an interpolation and the boundaries have to agree exactly — a state machine
## here is four places to get the same lerp slightly wrong.
func depth(phase: float) -> float:
	var r := ramp()
	var up_hold := _period * UP_SHARE
	var deep := sink()
	if phase < r:
		return lerpf(deep, 0.0, phase / r)
	phase -= r
	if phase < up_hold:
		return 0.0
	phase -= up_hold
	if phase < r:
		return lerpf(0.0, deep, phase / r)
	return deep


func drive(bog: Bog, delta: float) -> void:
	_t += delta
	var below := depth(fmod(_t, cycle()))
	var pos := _station.origin
	pos.y = ground_y(bog, pos) - below
	# Crouched while it is anywhere but fully up: nobody sees the pose down
	# there, but the capsule is `CROUCH_HEIGHT` rather than `STAND_HEIGHT` and a
	# shorter thing in a hole is a thing whose hat cannot poke through the floor.
	go(bog, pos, look_yaw(pos), Vector3.ZERO, true, below > 0.01)


## Up and shootable, for the gate and for a station's readout.
func is_up() -> bool:
	return depth(fmod(_t, cycle())) <= 0.01
