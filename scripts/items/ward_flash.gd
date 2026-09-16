class_name WardFlash
extends Node3D
## What a spear looks like when it fails to kill the Elder (D-040).
##
## An Elder cannot be killed, and `MatchState.report_kill` is where that is
## decided — but a rule enforced silently is a rule nobody in the fight can
## learn. Without something here the strongest weapon in the game hits the
## strongest target in it and simply stops existing: the thrower sees no
## hitmarker, the Elder sees nothing at all, and the honest reading of that from
## either end is "the spear went through them" or "the game dropped it".
##
## So the robe is *seen* to turn it aside, at the point it was turned aside at.
##
## Drawn to the same rule `LightningBolt` and `SpearTrail` are: this is light,
## not a surface, so it is unshaded and additively blended and is therefore
## brighter than the night forest and than Rust's noon. It is deliberately the
## robe's violet rather than the bolt's white-violet — the thing that stopped the
## spear is the robe, and the one effect it must never be mistaken for is a bolt
## going off in somebody's chest.
##
## Cheap by construction, because it fires on *every* refused hit and an Elder
## under fire from three people is three of these a second: one sphere with one
## material, one shadowless light, no particles, and the whole thing is gone in
## a quarter of a second. That is a third of a bolt's cost for a sixth of its
## life.

## How long the whole effect lasts. Short on purpose — a ward that lingers reads
## as a shield that is *up*, and the Elder has no shield. This is an impact.
const LIFE := 0.26

## The shell, which expands as it fades.
##
## **Both numbers came down after looking at it**, which is the same correction
## the bolt's flash needed (D-038) and the same mistake underneath: an additive
## sphere on a dark map is far brighter and far bigger than its numbers suggest.
## At 0.22 -> 0.62 the ball was 1.24 m across against a 1.55 m Bog — it covered
## the body from the hem to the hat and read as a *shield bubble*, which is
## precisely the one thing this effect must not say. The Elder has no shield;
## it has a robe that turns one spear aside.
##
## 0.12 -> 0.40 is 0.8 m across at its widest, about the width of the Bog's own
## capsule, so what is on screen is a hit on a body with the body still visible
## around it.
const RADIUS_FROM := 0.12
const RADIUS_TO := 0.40

## The robe's own purple, brightened until it carries at range. Additive
## material colour is albedo x energy, exactly as `LightningBolt._make_material`
## does it, with the per-frame fade carried on the alpha instead.
const COLOUR := Color(0.72, 0.45, 1.00)
const ENERGY := 2.4

## The light is what actually reads from across a clearing — D-035's lesson
## about the letter card, and D-038's about the crackling fist: at twenty metres
## a small violet shell on a purple robe is a smudge on a robe, and what carries
## is that the Bog was *lit* for a moment. Shadowless, like every other
## short-lived light in this game.
const LIGHT_ENERGY := 4.5
const LIGHT_RANGE := 5.0

## How hard the Elder's own camera is kicked. Read by `MatchState._do_ward`.
## A twentieth of a lightning strike and a quarter of a spear kill: being shot
## at and surviving it is worth knowing about and is not worth being knocked
## about by, especially at a rate of several a second.
const SHAKE := 0.30

var _shell: MeshInstance3D
var _material: StandardMaterial3D
var _light: OmniLight3D
var _sphere: SphereMesh
var _age: float = 0.0


## Flash once, on this peer, at `at`.
##
## Every peer calls this with the same argument from `MatchState._do_ward`,
## which is what makes it an event everybody saw rather than a private animation
## on the machine of whoever threw the spear.
static func burst(parent: Node, at: Vector3) -> WardFlash:
	if parent == null:
		return null
	var ward := WardFlash.new()
	ward.name = "Ward_%d" % Time.get_ticks_msec()
	parent.add_child(ward)
	ward._build(at)
	# The sound of something hard stopping against something harder, which is
	# what happened. Borrowed rather than invented: `SPEAR_HIT_WORLD` already
	# means exactly "that spear is not going any further", and a new voice here
	# would be a fourth impact sound for players to learn for one situation.
	AudioDirector.play_3d_varied(AudioDirector.SPEAR_HIT_WORLD, at, 0.18, -2.0)
	return ward


func _build(at: Vector3) -> void:
	# World space, like the bolt and the trail and for the same reason: it is
	# built from a world point and must not then be moved again by whatever the
	# spawn container happens to be sitting at.
	top_level = true
	global_transform = Transform3D.IDENTITY

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.disable_receive_shadows = true
	# Depth-tested, exactly as the bolt is: a ward visible through a hill would
	# announce every fight on the map, and would contradict the rule this whole
	# weapon rests on, which is that cover works.
	_material.no_depth_test = false
	_material.albedo_color = Color(COLOUR.r * ENERGY, COLOUR.g * ENERGY,
		COLOUR.b * ENERGY, 1.0)

	# Coarse on purpose. It is on screen for a quarter of a second, additively
	# blended and expanding, and nobody has ever counted the rings on one.
	_sphere = SphereMesh.new()
	_sphere.radial_segments = 12
	_sphere.rings = 6
	_sphere.radius = RADIUS_FROM
	_sphere.height = RADIUS_FROM * 2.0

	_shell = MeshInstance3D.new()
	_shell.mesh = _sphere
	_shell.material_override = _material
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shell)
	_shell.global_position = at

	_light = OmniLight3D.new()
	_light.light_color = COLOUR
	_light.light_energy = LIGHT_ENERGY
	_light.omni_range = LIGHT_RANGE
	_light.shadow_enabled = false
	add_child(_light)
	_light.global_position = at


func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / LIFE, 0.0, 1.0)
	if t >= 1.0:
		queue_free()
		return
	# Grows fast and slows down — the shape of an impact rather than of a
	# balloon. `ease` with a negative exponent is the out-curve.
	var grown := ease(t, 0.35)
	var radius := lerpf(RADIUS_FROM, RADIUS_TO, grown)
	_sphere.radius = radius
	_sphere.height = radius * 2.0
	# Squared, so the flash is over well before the shell has finished
	# expanding. A shell that fades linearly with its own growth reads as a
	# bubble being inflated; this reads as something being struck.
	var fade := (1.0 - t) * (1.0 - t)
	_material.albedo_color.a = fade
	_light.light_energy = LIGHT_ENERGY * fade
