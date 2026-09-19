class_name Sunburst
extends Node3D
## The gold flash a captured letter lands in.
##
## The owner, on the end of a capture: *"when it hits 0, a short small gold
## array of sunburst, along with a sound."* That is the whole brief and the two
## adjectives in it are the design: **short**, because the payout is the letter
## arriving and not a firework, and **small**, because it goes off at a Bog's
## hip and anything bigger reads as an explosion on the player rather than as a
## prize being taken.
##
## It is `WardFlash`'s sibling and is drawn to the same rule: this is light and
## not a surface, so it is unshaded and additively blended and is therefore
## brighter than a night forest and than Rust's noon. What makes it a *burst*
## rather than a flash is that it has spokes — a ball of light at a hip is a
## hit taken, and a star is a thing given.
##
## **Everything in it is the letter's own gold** (`Pickup.LETTER_COLOUR`),
## which is the one colour in this game that already means "the prize". A
## second gold here would be a second thing to keep in step the first time the
## cards are re-tinted.
##
## Cheap by construction: one `ImmediateMesh` of fourteen triangles rebuilt per
## frame, one shadowless light, no particles, and the whole thing is gone in
## about a third of a second. It fires at most once per letter per player.

## How long the whole burst lasts. Two thirds again of `WardFlash.LIFE` and for
## the opposite reason: a ward is an impact and is over before it is read,
## while this is the confirmation that ten seconds of standing in the open just
## paid off, and it has to survive being glanced at.
const LIFE := 0.35

## The rays, and their span. They grow out of almost nothing to a length that
## is about a Bog's forearm — big enough to be a star at the hip, small enough
## that it never touches the head or the ground.
const RAYS := 14
const LENGTH_FROM := 0.05
const LENGTH_TO := 0.60

## How wide a ray is at its base, in metres, and how far out from the centre it
## starts. Thin, because a fat spoke is a petal: what this has to look like is
## light leaving a point, and the width is the only thing that decides between
## the two.
const RAY_WIDTH := 0.02
const RAY_INNER := 0.03

## Every other ray is drawn short. Fourteen spokes of one length is a wheel —
## a cog, in silhouette — and the alternation is the whole of what makes it
## scan as a starburst instead. The number is a ratio rather than a second
## length so the two sets grow together.
const SHORT_RAY := 0.62

## The flash under the rays. It is what actually carries from across the
## clearing, which is D-035's lesson about the letter card and D-038's about
## the crackling fist repeated a third time: at twenty metres the spokes are a
## smudge and what is seen is that the Bog was lit gold for a moment.
const LIGHT_ENERGY := 4.0
const LIGHT_RANGE := 4.5

## Additive material colour is albedo x energy, exactly as `WardFlash` and
## `LightningBolt._make_material` do it, with the per-frame fade carried on the
## alpha instead.
const ENERGY := 2.2

var _mesh: ImmediateMesh
var _instance: MeshInstance3D
var _material: StandardMaterial3D
var _light: OmniLight3D
var _at: Vector3 = Vector3.ZERO
var _age: float = 0.0


## Burst once, on this peer, at `at`.
##
## Every peer builds one of these from the same replicated event —
## `MatchState.letter_banked` or `letter_stolen`, both of which arrive
## everywhere — which is what makes the capture a thing the whole lobby saw
## rather than a private animation on the machine of whoever was holding the
## card. `WardFlash.burst`'s shape exactly, and deliberately: two effects with
## the same life should be fired the same way.
##
## It makes **no sound of its own**. The chime belongs to the caller
## (`CaptureRig`), because a bank and a steal are the same burst with two
## different reasons and only the caller knows which one this is.
static func fire(parent: Node, at: Vector3) -> Sunburst:
	if parent == null:
		return null
	var burst := Sunburst.new()
	burst.name = "Sunburst_%d" % Time.get_ticks_msec()
	parent.add_child(burst)
	burst._build(at)
	return burst


func _build(at: Vector3) -> void:
	# World space, like the ward and the bolt and the trail: it is built from a
	# world point and must not then be moved again by whatever the Bog it hung
	# off happens to do next. A capture ends with the player still running.
	top_level = true
	global_transform = Transform3D.IDENTITY
	_at = at

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.disable_receive_shadows = true
	# Depth-tested, exactly as the ward is: a burst visible through a hill
	# would announce every capture on the map, and the guide line and the
	# minimap are the things that are allowed to do that.
	_material.no_depth_test = false
	var gold := Pickup.LETTER_COLOUR
	_material.albedo_color = Color(gold.r * ENERGY, gold.g * ENERGY,
		gold.b * ENERGY, 1.0)

	_mesh = ImmediateMesh.new()
	_instance = MeshInstance3D.new()
	_instance.mesh = _mesh
	_instance.material_override = _material
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_instance)
	_instance.global_position = at

	_light = OmniLight3D.new()
	_light.light_color = gold
	_light.light_energy = LIGHT_ENERGY
	_light.omni_range = LIGHT_RANGE
	_light.shadow_enabled = false
	add_child(_light)
	_light.global_position = at

	_draw_rays(LENGTH_FROM)


func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / LIFE, 0.0, 1.0)
	if t >= 1.0:
		queue_free()
		return
	# Out fast and then slowing, the ward's own curve: light leaves a point at
	# speed, and a star that grows linearly reads as one being drawn.
	_draw_rays(lerpf(LENGTH_FROM, LENGTH_TO, ease(t, 0.35)))
	# Squared, so the burst is over well before the spokes have finished
	# growing. Linear and it reads as a wheel being inflated.
	var fade := (1.0 - t) * (1.0 - t)
	_material.albedo_color.a = fade
	_light.light_energy = LIGHT_ENERGY * fade


## Fourteen triangles in this node's own XY plane, turned to face the camera.
##
## **Flat and billboarded rather than a three-dimensional array of spikes**,
## and that is the one real choice in this file. Spokes distributed over a
## sphere are a sea urchin: from any single viewpoint half of them point at the
## lens and are a dot, so the star is never the shape it was built as. A flat
## star turned to the viewer is the shape *every* viewer sees, which is what
## "a small gold array of sunburst" has to mean on eight screens at once.
##
## Rebuilt every frame rather than scaled, because the rays alternate length
## and a uniform scale would grow the short ones at the same rate as the long
## ones — the alternation is the read, so it has to survive the growth.
func _draw_rays(length: float) -> void:
	var face := Basis.IDENTITY
	var camera: Camera3D = null
	if is_inside_tree():
		camera = get_viewport().get_camera_3d()
	if camera != null:
		# Aim the star's own −Z at the lens. `looking_at` takes the direction
		# to face; a headless run has no camera and keeps identity, which is
		# what the checks measure against.
		var to_lens := camera.global_position - _at
		if to_lens.length_squared() > 0.0001:
			# `looking_at` errors on an up vector colinear with the direction,
			# which a camera straight overhead is. One swap rather than a
			# clamp, because the star has no roll worth preserving.
			var up := Vector3.UP if absf(to_lens.normalized().y) < 0.99 \
				else Vector3.FORWARD
			face = Basis.looking_at(to_lens, up)

	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RAYS:
		var angle := TAU * float(i) / float(RAYS)
		var spoke := face * Vector3(cos(angle), sin(angle), 0.0)
		var across := face * Vector3(-sin(angle), cos(angle), 0.0)
		var reach := length * (1.0 if i % 2 == 0 else SHORT_RAY)
		var base := spoke * RAY_INNER
		_mesh.surface_add_vertex(base + across * (RAY_WIDTH * 0.5))
		_mesh.surface_add_vertex(base - across * (RAY_WIDTH * 0.5))
		_mesh.surface_add_vertex(spoke * (RAY_INNER + reach))
	_mesh.surface_end()
