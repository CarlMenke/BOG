class_name SwordSwipe
extends MeshInstance3D
## The wind a great sword leaves where it just killed (D-168).
##
## **This is the hit volume, drawn.** `BogCombat._sword_victims` is a horizontal
## sector — every Bog whose capsule surface is inside the reach and whose bearing
## is inside the arc — and two players who could not see it read it as "a
## rectangle in front of me", so a target a little to the side survived a swing
## that looked like it connected. What is on screen here is the *same sector*,
## built from the same two numbers the host measured its victims with, handed in
## at the call that reports the hit. There is no second geometry to drift: move
## `SWORD_ARC` or the reach dial and this moves with it on the same frame.
##
## An `ImmediateMesh` annulus sector rather than particles or a shader on a
## pre-made fan, for `SpearTrail`'s reason one weapon along: the shape is
## different on every swing — the reach is a lobby dial that runs to 6.0, and a
## slash's is that plus its step — so a mesh that was authored once would be a
## mesh that is the wrong size in most lobbies. Sixty-two vertices and one draw
## call is cheaper than either, and the fan is gone in a third of a second.
##
## Built in world space (`top_level`) and frozen where the blade was. The spin
## carries the body another 0.8 m *after* the cut, so a fan parented to the
## swinger would slide off the ground it is a claim about.

## How long the whole thing is on screen. A third of a second: long enough for a
## bystander to see which way the blade went, short enough that it is a *swipe*
## and not a zone painted on the floor. Everything about this effect is trying
## not to be a targeting decal.
const LIFE := 0.34

## What fraction of that life the leading edge takes to cross the arc. The rest
## is the fade. Under half, so the wind is through before it starts going out —
## a fan that faded while it was still opening reads as a bubble, which is the
## correction `WardFlash` needed for the same reason.
const SWEEP := 0.42

## How far behind the leading edge the wind still carries, in degrees, and what
## is left of it behind that. The trail is what makes it read as something
## passing through rather than a wedge switching on; the floor is why the whole
## footprint is still legible once the edge has gone by, which is the half of
## this that answers the ticket.
const TRAIL := 55.0
const TAIL := 0.30

## Brightness at the outer rim and at the hub, before the fade. The rim is the
## brighter of the two on purpose: the outer edge is the line a player is being
## asked to learn, and the middle of the sweep is ground they already know is
## dangerous. Nothing here goes near 1.0 — an additive fan at full alpha on a
## torchlit map is the neon pie this effect exists to not be, and the first
## render at 0.46 was exactly that: a sheet of paper lying on the fight.
const RIM_ALPHA := 0.26
const HUB_ALPHA := 0.05

## How far the wind stands up off the sweep at the rim, in metres, and how
## bright it is where it leaves it.
##
## **The half of this effect the swinger can actually see**, and it is here
## because of a render: the fan is drawn in the plane the hit is measured in,
## which is horizontal, and from a third-person camera a metre and a half up
## that plane is nearly edge-on — a bright sliver and nothing else. Seen from
## above, which is a bystander's view of somebody else's swing, the fan reads
## perfectly and the curtain is a rim of haze on it. Seen from your own
## shoulder, the curtain is the whole thing. Both are the same arc.
##
## Waist-high rather than head-high: this is air being pushed, and a wall that
## reached a Bog's eyes would hide the body the swing is about.
const CURTAIN := 0.80
const CURTAIN_ALPHA := 0.22

## Where the fan starts, in metres from the swinger's own axis. The swinger's
## capsule, near enough: a sector drawn from a mathematical point has a bright
## singularity at the Bog's own feet and reads as something coming *out of* it.
const HUB_RADIUS := 0.40

## How fine the rim is. Four degrees is 38 quads across a 150 degree sweep and
## is under a pixel of chord at any range this is looked at.
const SEGMENT := 4.0

## Pale and warm, which is the rule every other piece of light in this game is
## drawn to (`SpearTrail`, the crosshair, the torches). Cooler than the spear's
## streak by a little, because this is air being moved rather than iron flying,
## and desaturated far enough that it survives Highsun's white noon as well as
## the night forest.
const COLOUR := Color(0.94, 0.96, 1.0)

## The sector, as it was handed over: the blade it is centred on, the outer
## radius in metres from the swinger's axis, and the half-angle in degrees
## either side. Together with the node's own position that is the whole
## footprint, and it is public so it can be *read back*:
## `tools/combat_range.gd -- sword` fails if the radius or the arc has drifted
## from the numbers the host hit with, and measures its two edge dummies against
## this blade rather than against one it sampled itself — "what you see is what
## hits" is only a claim if the thing on screen is what the verdict is taken
## from.
var blade: Vector3 = Vector3.FORWARD
var outer_radius: float = 0.0
var half_arc: float = 0.0

var _mesh: ImmediateMesh
var _sense: float = 1.0
var _age: float = 0.0


## Draw one swipe, on this peer.
##
## `outer` is the distance from the swinger's axis at which a **body** stops
## dying, not the dial: the hit measures to the capsule's surface, so the dial
## plus a Bog's radius is the locus of standing positions a swing catches. That
## conversion is `BogCombat._show_swipe`'s, in the file that owns the rule; what
## arrives here is already a footprint.
##
## `sense` is which way the blade is travelling, +1 for a sweep to the blade's
## left. It is measured off the bone attachment on whichever machine is drawing
## this, because every peer is playing the same clip and none of them needs to
## be told.
static func sweep(parent: Node, centre: Vector3, along: Vector3, outer: float,
		arc: float, sense: float) -> SwordSwipe:
	if parent == null or outer <= HUB_RADIUS or arc <= 0.0:
		return null
	var flat := Vector3(along.x, 0.0, along.z)
	if not flat.is_finite() or flat.length_squared() < 0.0001:
		return null
	var swipe := SwordSwipe.new()
	swipe.name = "Swipe_%d" % Time.get_ticks_msec()
	swipe.outer_radius = outer
	swipe.half_arc = arc
	swipe.blade = flat.normalized()
	swipe._sense = 1.0 if sense >= 0.0 else -1.0
	# The harness finds it here rather than by walking the spawn root, which is
	# also full of spears, shields and magnets.
	swipe.add_to_group("sword_swipes")
	parent.add_child(swipe)
	swipe.global_position = centre
	swipe._rebuild()
	return swipe


func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	material_override = _make_material()


## Additive, unshaded and two-sided, the rule `SpearTrail`, `LightningBolt` and
## `WardFlash` are all drawn to: this is light and not a surface. Depth-tested,
## so a swipe on the far side of a barricade is hidden by it — the hit is, and a
## fan visible through cover would promise a kill the line-of-sight test refuses.
func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	material.no_depth_test = false
	material.albedo_color = Color(COLOUR.r, COLOUR.g, COLOUR.b, 1.0)
	return material


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	_rebuild()


## The fan at this instant, as two strips off one set of bearings: the sweep
## itself, lying in the plane the hit is measured in, and the curtain standing
## up off its rim. Rebuilt per frame rather than animated in a shader because
## the leading edge is the whole effect and this is a hundred and fifty
## vertices — a shader would be a second place the arc is written down, which is
## the one thing D-168 is trying not to have.
func _rebuild() -> void:
	if _mesh == null:
		return
	_mesh.clear_surfaces()
	var t := clampf(_age / LIFE, 0.0, 1.0)
	# Where the leading edge is, in degrees off the blade, signed the way the
	# blade is actually turning. It crosses the whole sweep and then sits on the
	# far edge while the fan goes out.
	var head := _sense * lerpf(-half_arc, half_arc, clampf(t / SWEEP, 0.0, 1.0))
	# Out after the sweep, squared, so it is gone well before it would start to
	# look like a decal.
	var fade := 1.0
	if t > SWEEP:
		var out := (t - SWEEP) / maxf(1.0 - SWEEP, 0.01)
		fade = (1.0 - out) * (1.0 - out)

	var steps := maxi(int(ceil(half_arc * 2.0 / SEGMENT)), 4)
	var bearings := PackedFloat32Array()
	var weights := PackedFloat32Array()
	for i in steps + 1:
		var degrees := lerpf(-half_arc, half_arc, float(i) / float(steps))
		# Nothing ahead of the blade yet; behind it the wind thins out to TAIL
		# over TRAIL degrees and stays there, which is the footprint.
		var behind := (head - degrees) * _sense
		bearings.append(degrees)
		weights.append(0.0 if behind < 0.0
			else clampf(1.0 - behind / TRAIL, TAIL, 1.0) * fade)

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in bearings.size():
		var out := blade.rotated(Vector3.UP, deg_to_rad(bearings[i]))
		_edge(out * outer_radius, weights[i] * RIM_ALPHA)
		_edge(out * HUB_RADIUS, weights[i] * HUB_ALPHA)
	_mesh.surface_end()

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in bearings.size():
		var out := blade.rotated(Vector3.UP, deg_to_rad(bearings[i])) * outer_radius
		_edge(out, weights[i] * CURTAIN_ALPHA)
		_edge(out + Vector3.UP * CURTAIN, 0.0)
	_mesh.surface_end()


func _edge(offset: Vector3, alpha: float) -> void:
	_mesh.surface_set_color(Color(COLOUR.r, COLOUR.g, COLOUR.b, maxf(alpha, 0.0)))
	_mesh.surface_add_vertex(offset)
