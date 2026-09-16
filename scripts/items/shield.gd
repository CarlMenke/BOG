class_name Shield
extends StaticBody3D
## A wooden barricade a Bog plants in front of itself to hide behind.
##
## It is solid to spears and to Bogs alike, which is the whole point: it stops a
## throw *and* it stops you walking through your own cover, so committing to one
## costs you mobility. It is not destructible — a spear thrown into it sticks and
## is simply spent. Making cover breakable would turn every fight into whoever
## has more spears, and the spear recharge is already the scarcity dial.
##
## Placement is validated by `BogCombat._shield_spot`, so by the time one of
## these exists it is standing on real ground.

const MODEL := preload("res://art/generated/shield.glb")

const LAYER_DEPLOYABLE := 8
## Blocks nothing itself — it is static. The Bog and the spear both include the
## deployable layer in their masks, which is what makes it cover.
const MASK_NONE := 0

## Shields go up rather than fade in. A shield that is not solid the instant
## you press the button is a shield that gets you killed, so the collision is
## live immediately and only the visual grows.
const GROW_TIME := 0.28
const WITHER_TIME := 0.45

## How big a planted shield is, on top of the 1.0 `nodes/root_scale` in
## `shield.glb.import` — which is 1.0 deliberately, because the mushroom this
## replaced carried 1.25 there and that hidden quarter is what D-034 and D-039
## spent two rounds untangling. One number, in one place, and the model's own
## metre is the metre.
##
## **One scale, not two, because a shield is a wall and not a canopy.** The
## mushroom needed `WIDE` and `TALL` apart because its cover hung off a stalk,
## so height decided *where* the cover was and width decided how much of it
## there was; raise one and the cap floated over the head of the Bog behind it.
## A slab has no such joint. Its cover is its silhouette, it starts at the
## ground, and scaling it uniformly moves the top edge and nothing else.
##
## 1.75 is the mushroom's top edge (D-039), kept on purpose: it is the height
## that leaves the antennae of the 1.80 m Bog model showing over cover while
## putting the hitbox — 1.55 m of it (`Bog.STAND_HEIGHT`) — entirely behind.
## The file is 1.0 m tall, so the scale is simply the height in metres, the same
## arrangement the magnet's two scales landed on in D-078.
const MODEL_SCALE := 1.75

## Half a turn, because the model's two faces are not interchangeable.
##
## The prop is a barricade of horizontal planks: its **+Z** face is the
## weathered, mossed, sunlit outside, and its **-Z** face is the frame — two
## stiles and a V of diagonal bracing meeting at the foot. Godot's forward is
## -Z and `plant` points this node's forward at whatever the planter was looking
## at, so without this the planter would be staring at the mossy side and the
## enemy at the carpentry.
const MODEL_YAW := PI

## The collision: **one box**, measured off the decimated mesh at `MODEL_SCALE`
## by slicing it, rather than derived from anything.
##
## `art/generated/shield.glb` at 1.75 runs x -0.613..+0.614, y 0.002..1.749,
## z -0.158..+0.160 — 1.226 x 1.746 x 0.319 m, centred on x 0.000 and z 0.001,
## so it needs no offset inside itself the way the mushroom's leaning cluster
## did. Sliced into quarter-metre bands the width never varies by more than a
## centimetre either side of 1.20 and the depth is the rails at each end:
##
##   0.00-0.25   1.207 wide   0.317 deep   the bottom rail and the ground spike
##   0.25-0.50   1.206        0.225        planks
##   0.50-0.75   1.179        0.254        planks
##   0.75-1.00   1.189        0.236        planks
##   1.00-1.25   1.215        0.263        planks
##   1.25-1.50   1.200        0.232        planks
##   1.50-1.75   1.204        0.319        the top rail
##
## `BOX_WIDTH` and `BOX_HEIGHT` are the full extents rounded up to the
## centimetre, so the box circumscribes the mesh by 2 mm and 4 mm and there is
## nothing sticking out of it to be shot through.
##
## **The box is solid and the prop is not**, and that is the one deliberate
## disagreement here. Between each pair of planks is a slot two or three
## centimetres tall that you can see daylight through. Modelling those — a box
## per plank — would put six letterboxes up the middle of a thing whose entire
## job is to have no way through it, which is D-039's gap between the stem and
## the cap all over again and at six times the count. Of the two ways to be
## wrong, a spear that stops against a slot you could have threaded reads as a
## spear hitting a barricade; one that comes through a gap you cannot aim at
## reads as the game being broken.
##
## `BOX_DEPTH` is the measured 0.319 rounded up, and it clears the 0.25 m floor
## this shape was given without the floor ever having to bite. The floor is
## there because a wall thin enough to be stepped through in one tick is not a
## wall: `SpearProjectile._sweep` rays the segment between two ticks so a spear
## cannot tunnel at any thickness, but a `CharacterBody3D` is depenetrated out of
## whatever it is already inside, and at `Bog.WALK_SPEED` a Bog covers 3.8 cm in
## a tick. 0.25 is a comfortable multiple of that; 0.32 is the prop.
##
## Change `MODEL_SCALE` and re-run `tools/combat_range.tscn cover`, which prints
## the blocked width at every height a Bog occupies.
const BOX_WIDTH := 1.23
const BOX_HEIGHT := 1.75
const BOX_DEPTH := 0.32

var owner_peer_id: int = 0

var _model: Node3D
var _lifetime: float = 25.0
var _age: float = 0.0
var _withering: bool = false


func plant(spot: Vector3, yaw: float, lifetime: float, planted_by: int) -> void:
	owner_peer_id = planted_by
	_lifetime = lifetime
	global_position = spot
	# The planter's yaw exactly, with none of the mushroom's ±0.5 rad of
	# scatter. A mushroom is a thing that grew there and wants to look like it
	# grew at an angle; a shield is a thing somebody put down, and a wall turned
	# a few degrees off the line you meant is a wall you get shot past. A row of
	# them all facing the same way is a shield wall, which is the right picture.
	rotation.y = yaw

	collision_layer = LAYER_DEPLOYABLE
	collision_mask = MASK_NONE
	_build_collision()

	_model = MODEL.instantiate() as Node3D
	add_child(_model)
	_model.rotation.y = MODEL_YAW
	# Both ends of the eruption are fractions of the finished size, so the shape
	# of the animation is untouched by the scale — a taller shield still comes
	# out of the ground the same way.
	_model.scale = _model_scale(Vector3(0.15, 0.02, 0.15))
	var grow := create_tween()
	grow.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	grow.tween_property(_model, "scale", _model_scale(Vector3.ONE), GROW_TIME)
	AudioDirector.play_3d_varied(AudioDirector.SHIELD_DEPLOY, global_position)


## The finished scale of a fraction of the model. One line and one constant now
## that wide and tall are the same number, but it is still written once so that
## the eruption and the wither cannot drift apart.
func _model_scale(fraction: Vector3) -> Vector3:
	return fraction * MODEL_SCALE


func _build_collision() -> void:
	var slab := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BOX_WIDTH, BOX_HEIGHT, BOX_DEPTH)
	slab.shape = box
	# A `BoxShape3D` is centred on its origin and the mesh stands on the ground,
	# so the box is lifted by half its height to sit on the same ground.
	slab.position = Vector3(0.0, BOX_HEIGHT * 0.5, 0.0)
	add_child(slab)


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
	# spear that visibly passed through a sinking board.
	collision_layer = 0
	if _model == null:
		queue_free()
		return
	var shrink := create_tween()
	shrink.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	shrink.tween_property(_model, "scale", _model_scale(Vector3(0.1, 0.01, 0.1)),
		WITHER_TIME)
	shrink.tween_callback(queue_free)


func seconds_left() -> float:
	return maxf(0.0, _lifetime - _age)
