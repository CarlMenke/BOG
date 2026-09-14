class_name ShieldMushroom
extends StaticBody3D
## A mushroom a Gub plants in front of itself to hide behind.
##
## It is solid to spears and to Gubs alike, which is the whole point: it stops a
## throw *and* it stops you walking through your own cover, so committing to one
## costs you mobility. It is not destructible — a spear thrown into it sticks and
## is simply spent. Making cover breakable would turn every fight into whoever
## has more spears, and the spear recharge is already the scarcity dial.
##
## Placement is validated by `GubCombat._mushroom_spot`, so by the time one of
## these exists it is standing on real ground.

const MODEL := preload("res://art/generated/mushroom.glb")

const LAYER_DEPLOYABLE := 8
## Blocks nothing itself — it is static. The Gub and the spear both include the
## deployable layer in their masks, which is what makes it cover.
const MASK_NONE := 0

## Mushrooms erupt rather than fade in. A shield that is not solid the instant
## you press the button is a shield that gets you killed, so the collision is
## live immediately and only the visual grows.
const GROW_TIME := 0.28
const WITHER_TIME := 0.45

## How big a planted mushroom is, on top of the 1.25 `nodes/root_scale` already
## baked into `mushroom.glb.import`. **Read that sentence twice before changing
## either number**: the importer's scale and this one multiply, so the 1.25 that
## arrived with D-034 did not make the mushroom a quarter bigger than the file,
## it made it a quarter bigger than a file that was already a quarter bigger —
## 1.5625 all told, and a mushroom 2.54 m tall.
##
## **Wide and tall are separate, and that is the whole of the fix** (D-039).
##
## A mushroom is a canopy on a stalk, so its height decides *where* the cover is
## and its width decides *how much* of it there is. Scaling both together to
## make the cap bigger raised the cap, and this asset's cap starts 54% of the way
## up it: at 1.5625 the canopy ran 1.38-2.54 m with nothing but a 0.4-m stalk
## below it, so it hung clean over the head of a Gub whose collision capsule
## stops at 1.55. Cover you stand under is not cover.
##
## So the quarter the user asked for is kept, in the axis it was asked about —
## the cap is 1.86 m across, a quarter wider than before D-034 — and the height
## comes back down to put that cap on a Gub's chest instead of above its head.
## `MODEL_SCALE_TALL` is set so the canopy's underside lands at 0.95 m: low
## enough that a standing Gub is behind it from the chest up and a crouching one
## is behind it entirely, high enough that its top edge at 1.75 m leaves the
## antennae of the 1.80 m model showing over it.
##
## The five collision constants below are a *measurement* of the mushroom these
## two produce, not an arithmetic scaling of them, which is what the previous
## version of this comment claimed they were and is what went wrong. Change
## either scale and re-run `tools/combat_range.tscn cover`, which prints the
## blocked width at every height a Gub occupies.
const MODEL_SCALE_WIDE := 1.25
const MODEL_SCALE_TALL := 0.86

## Where the mushroom actually stands inside its own model, in the imported
## scene's metres.
##
## The `.glb` is a *cluster* — one big mushroom with a couple of small ones
## around its foot — and the big one's axis is nowhere near the file's origin:
## it leans, and at the height of its cap it sits half a metre out along -Z.
## Planted straight, that put the whole canopy 0.63 m to one side of the point
## the ability had checked the ground at, and it put every one of the collision
## cylinders below beside the mushroom rather than inside it.
##
## Measured by slicing the mesh: the cap's section is centred on (0.035, -0.40)
## in raw model units at its widest, which is this once the importer's 1.25 is
## applied. The model is slid back by it in `_model_offset` so that the thing
## you can see stands on the spot you planted it, which is also what puts the
## collision under it without either cylinder needing an offset of its own.
const MODEL_AXIS := Vector3(0.044, 0.0, -0.500)

## Collision is two cylinders rather than the 10k-triangle mesh: a fat cap to
## catch spears and a thin stem so a Gub can stand close and still peek round it.
##
## Every number here was measured off the mesh at the scales above, by slicing
## it horizontally, rather than derived from anything:
##
##   0.00-0.30   the foot and the small mushrooms around it, 1.3-2.1 m across
##   0.30-0.95   the stalk, 0.4-0.9 m across and narrowest just under the cap
##   0.95-1.75   the canopy, an ellipse 1.86 m by 1.42 m at its widest
##
## `CAP_RADIUS` 1.03 therefore *circumscribes* the canopy — 10 cm proud of it
## across the wide axis and 32 cm across the narrow one — and that asymmetry is
## a deliberate choice rather than sloppiness. A cylinder cannot be an ellipse,
## and of the two ways to be wrong, a spear that stops a handspan short of a cap
## reads as a spear hitting a mushroom, while one that passes through a cap you
## are looking at reads as the game being broken. The same argument is why the
## stem stays thin: 0.275 m is inside the stalk everywhere except the neck
## directly under the cap, and the cap is already covering anything aimed there.
##
## `STEM_HEIGHT` is exactly the cap's underside, so the two shapes meet with no
## gap. They used to be 5 cm apart, which is a letterbox at chest height on a
## thing whose entire job is to have no way through it.
const STEM_RADIUS := 0.275
const STEM_HEIGHT := 0.95
const CAP_RADIUS := 1.03
const CAP_HEIGHT := 0.80
const CAP_CENTRE_Y := 1.35

var owner_peer_id: int = 0

var _model: Node3D
var _lifetime: float = 25.0
var _age: float = 0.0
var _withering: bool = false


func plant(spot: Vector3, yaw: float, lifetime: float, planted_by: int) -> void:
	owner_peer_id = planted_by
	_lifetime = lifetime
	global_position = spot
	# A quarter turn of variation so a row of them does not look stamped out.
	rotation.y = yaw + randf_range(-0.5, 0.5)

	collision_layer = LAYER_DEPLOYABLE
	collision_mask = MASK_NONE
	_build_collision()

	_model = MODEL.instantiate() as Node3D
	add_child(_model)
	# Both ends of the eruption are fractions of the finished size, so the shape
	# of the animation is untouched by the two scales — a mushroom a quarter
	# wider still comes out of the ground the same way.
	_model.scale = _model_scale(Vector3(0.15, 0.02, 0.15))
	_model.position = _model_offset(0.15)
	# Position and scale together, in parallel and on one easing curve, because
	# the model is offset inside itself (see `MODEL_AXIS`) and scaling an
	# offset thing moves it. Tween the scale alone and the mushroom does not
	# erupt, it slides half a metre sideways while it grows.
	var grow := create_tween().set_parallel(true)
	grow.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	grow.tween_property(_model, "scale", _model_scale(Vector3.ONE), GROW_TIME)
	grow.tween_property(_model, "position", _model_offset(1.0), GROW_TIME)
	AudioDirector.play_3d_varied(AudioDirector.MUSHROOM_DEPLOY, global_position)


## The finished scale of a fraction of the model, with wide and tall applied
## separately. Written once so that every place the eruption and the wither
## reach for a size gets both axes, rather than three chances to use one.
func _model_scale(fraction: Vector3) -> Vector3:
	return Vector3(fraction.x * MODEL_SCALE_WIDE, fraction.y * MODEL_SCALE_TALL,
		fraction.z * MODEL_SCALE_WIDE)


## Where the model has to sit for the mushroom inside it to stand on this node's
## origin, at a given fraction of full size. Only the horizontal axes move: the
## model already starts at y = 0 and is meant to, since that is the ground.
func _model_offset(fraction: float) -> Vector3:
	return Vector3(-MODEL_AXIS.x, 0.0, -MODEL_AXIS.z) * MODEL_SCALE_WIDE * fraction


func _build_collision() -> void:
	var stem := CollisionShape3D.new()
	var stem_shape := CylinderShape3D.new()
	stem_shape.radius = STEM_RADIUS
	stem_shape.height = STEM_HEIGHT
	stem.shape = stem_shape
	stem.position = Vector3(0.0, STEM_HEIGHT * 0.5, 0.0)
	add_child(stem)

	var cap := CollisionShape3D.new()
	var cap_shape := CylinderShape3D.new()
	cap_shape.radius = CAP_RADIUS
	cap_shape.height = CAP_HEIGHT
	cap.shape = cap_shape
	cap.position = Vector3(0.0, CAP_CENTRE_Y, 0.0)
	add_child(cap)


func _process(delta: float) -> void:
	if _withering:
		return
	_age += delta
	if _age >= _lifetime:
		wither()


## Retract and disappear. Called when the lifetime runs out, when the planter
## exceeds their cap, or when a round ends.
func wither() -> void:
	if _withering:
		return
	_withering = true
	# Stop being cover the moment it starts collapsing, so nobody dies to a
	# spear that visibly passed through a shrinking stalk.
	collision_layer = 0
	if _model == null:
		queue_free()
		return
	var shrink := create_tween().set_parallel(true)
	shrink.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	shrink.tween_property(_model, "scale", _model_scale(Vector3(0.1, 0.01, 0.1)),
		WITHER_TIME)
	shrink.tween_property(_model, "position", _model_offset(0.1), WITHER_TIME)
	# Parallel, so the callback needs a step of its own to land after both
	# rather than at the same moment as them.
	shrink.chain().tween_callback(queue_free)


func seconds_left() -> float:
	return maxf(0.0, _lifetime - _age)
