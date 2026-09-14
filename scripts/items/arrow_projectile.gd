class_name ArrowProjectile
extends SpearProjectile
## An arrow in flight, and the three numbers the draw decided (D-065).
##
## It is a `SpearProjectile` with four things swapped — a different mesh, a
## launch speed and a drop taken off the charge instead of out of a constant,
## and a damage number that is **not** a whole Gub. Everything else is inherited
## and is deliberately not re-stated here: the hand-stepped flight, the segment
## sweep that stops a 60 m/s shaft tunnelling through a body, the glow, the
## trail, and the three endings in `_stick_in` — the victim lives and the shaft
## rides their skeleton, the victim dies and the corpse adopts it, the victim
## falls into the void and it gives up.
##
## That last one is why this class is nine lines of override and not a second
## projectile. D-062 built the ride *for this weapon*, and said so: "a Gub with
## three arrows in it and a short bar is the best read in the game". The parent
## was already the right shape; what it needed was to stop assuming the shaft
## was worth a hundred, which it never actually did — damage has always belonged
## to the caller.
##
## **Every peer builds its own copy from the same launch**, exactly as for a
## spear, and the charge travels as part of that launch rather than being
## re-derived from each peer's idea of how long a button was held. The flight is
## pure ballistics with no randomness, so all eight agree on where the arrow is
## without a single position packet.

const ARROW := preload("res://art/generated/arrow.glb")

## How the 20-to-80 is spread across the draw.
##
## `damage = snap + (full - snap) · charge^CURVE`, and the exponent is the whole
## of "weighted toward the end of the draw" (the decisions table in
## `docs/PLAN_COMBAT.md`). What it buys, exactly: the fraction of the gain that
## arrives in the last third of the draw is `1 - (2/3)^CURVE`, which at 3 is
## **70%**. A half-drawn bow does 27 of the 80 and a two-thirds-drawn one does
## 38 — both genuinely bad, which is the point.
##
## **Three rather than two, and two is the physical answer.** An arrow's energy
## goes as the square of its speed, the speed is linear in the draw here, so
## damage proportional to energy would be `charge²` — which puts 56% in the last
## third and is "a bit more at the end" rather than "most of it at the end". The
## user asked for the second one. So this is a design number sitting one step
## past a physical one, which is worth saying out loud rather than letting
## somebody later "correct" it to 2 and quietly halve the reward for a full
## draw.
##
## Not a lobby dial, unlike the eight numbers it interpolates between. The ends
## are balance and a host can have them; the shape is the mechanic, and a slider
## that turns a skill curve into a straight line is not a setting anybody could
## reason about from the lobby.
const DAMAGE_CURVE := 3.0

## How far the charge was pulled when this arrow left, 0 to 1. Carried on the
## arrow rather than looked up, because by the time it lands the archer may be
## drawing the next one.
var charge: float = 0.0
## What it does to a Gub it hits. Worked out once, on every peer, from the
## charge and the config — both of which are replicated — so the number cannot
## travel and cannot travel wrong. Only the host's copy reports it.
var damage: float = 0.0


## Loose an arrow. `direction` is expected to be normalised, `charge` clamped.
static func loose(parent: Node, archer: Gub, origin: Vector3, direction: Vector3,
		draw: float, config: MatchConfig, is_authoritative: bool) -> ArrowProjectile:
	var arrow := ArrowProjectile.new()
	arrow.charge = clampf(draw, 0.0, 1.0)
	arrow.damage = damage_for(arrow.charge, config)
	arrow._speed = speed_for(arrow.charge, config)
	arrow._drop = drop_for(arrow.charge, config)
	arrow.begin(parent, archer, origin, direction, is_authoritative)
	return arrow


## What an arrow drawn this far is worth, in `Gub.MAX_HEALTH`'s units.
##
## Static and public because four things ask it and they must all get the same
## answer: the arrow itself, the HUD that could one day show it, the combat
## range that asserts it, and `tools/match_rules.gd`, which checks the curve's
## shape without needing a world to fire into.
static func damage_for(draw: float, config: MatchConfig) -> float:
	var t := clampf(draw, 0.0, 1.0)
	return lerpf(config.bow_damage_snap, config.bow_damage_full,
		pow(t, DAMAGE_CURVE))


## How fast it leaves, in m/s. **Linear in the draw**, where the damage is not,
## and the two are different on purpose: speed is a fact about the bow (a limb
## bent twice as far pushes about twice as hard) and the damage curve is a
## decision about the fight.
static func speed_for(draw: float, config: MatchConfig) -> float:
	return lerpf(config.bow_speed_snap, config.bow_speed_full,
		clampf(draw, 0.0, 1.0))


## How fast it falls, in m/s². Linear, and the *other way up* — see the dials.
static func drop_for(draw: float, config: MatchConfig) -> float:
	return lerpf(config.bow_drop_snap, config.bow_drop_full,
		clampf(draw, 0.0, 1.0))


func _shaft_name() -> String:
	return "Arrow"


func _model_scene() -> PackedScene:
	return ARROW


## The mesh runs along its own +X with the head at +X, and a projectile flies
## along -Z, so a quarter turn about Y brings the head round to the front.
func _model_rotation() -> Vector3:
	return Vector3(0.0, 90.0, 0.0)


## ...and then the head is slid onto this node's origin, which is the point the
## flight sweep actually tests.
##
## The offset is not simply half a length, because the shaft is **not modelled
## down its own centre line**: measured off the built GLB the nock sits at
## `(-0.5, 0.0888, -0.0286)` in model units, so the two cross-axis terms are
## what keep the arrow on the line it is being swept along rather than 9 cm
## above it. Put a spear's `(0, 0, half)` here instead and every arrow in the
## game flies parallel to its own collision.
##
## The rotation above sends model `(x, y, z)` to `(z, y, -x)`, so the head at
## `(+0.5, 0.0888, -0.0286)` lands at `(-0.0286, 0.0888, -0.5)` and this is the
## negative of it, scaled.
func _model_offset() -> Vector3:
	return Vector3(0.0286, -0.0888, 0.5) * _model_scale()


## The same length it was in the fist. `HeldGear.ARROW_SCALE` is derived from
## how far apart the Gub's hands actually come across the draw, so asking it
## here is what makes the arrow that leaves the bow the arrow that was nocked in
## it rather than a second, differently sized one.
func _model_scale() -> float:
	return HeldGear.ARROW_SCALE
