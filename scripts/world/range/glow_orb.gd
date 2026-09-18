class_name GlowOrb
extends RangeTarget
## A glowworm drifting across the far end of the long lane, for tracking
## practice with the bow.
##
## The only target that moves, and the only one that dies of being hit. Both of
## those are what makes it worth having: a board teaches where your arrow goes
## and an orb teaches where it will be.
##
## **Built from a seed, not from packets.** The launcher sends a seed, an origin
## and a launch time; every peer builds the same parabola from them and runs it
## off its own clock. That is the spear's argument (pure ballistics from a
## replicated launch, so nothing about the flight has to travel) applied to
## something that was never a spear, and it means an orb costs one small
## reliable message every four seconds rather than a position per tick.
##
## It frees itself on being hit, which is also how it tells the projectile that
## struck it what to do: a target that survives keeps the shaft, a target that
## dies takes the shaft with it. See `SpearProjectile._resolve`.

const RADIUS := 0.35
const POINTS := 5

## The arc, in the launcher's local frame: down the lane on -Z, rising to a peak
## and back, with a sideways drift so the same lane is never the same shot.
const FLIGHT := 6.0
const RISE_MIN := 4.0
const RISE_MAX := 7.0
const DRIFT := 3.0

const COLOUR := Color(0.58, 1.00, 0.62)
const LIGHT_RANGE := 6.0
const LIGHT_ENERGY := 2.4

## The burst. An expanding unshaded shell and a light that dies with it — the
## shape `WardFlash` uses, for the reason it uses it: it is on screen for a
## quarter of a second and nobody has ever counted the rings on one.
const BURST_LIFE := 0.28
const BURST_FROM := RADIUS
const BURST_TO := 1.5

var _length: float = 60.0
var _age: float = 0.0
var _from: Vector3 = Vector3.ZERO
var _along: Vector3 = Vector3.FORWARD
var _across: Vector3 = Vector3.RIGHT
var _rise: float = 5.0
var _drift: float = 0.0
var _burst: bool = false

var _mesh: MeshInstance3D
var _light: OmniLight3D


## Every peer calls this with the same three arguments, and gets the same orb.
static func launch(parent: Node, at: Transform3D, seed_value: int,
		lane_length: float) -> GlowOrb:
	if parent == null:
		return null
	var orb := GlowOrb.new()
	orb.name = "GlowOrb_%d" % seed_value
	parent.add_child(orb)
	orb._begin(at, seed_value, lane_length)
	return orb


func _begin(at: Transform3D, seed_value: int, lane_length: float) -> void:
	_length = lane_length
	_from = at.origin
	# Down the launcher's own -Z, which is the way every marker on this map
	# faces: at the people shooting.
	_along = -at.basis.z.normalized()
	_across = at.basis.x.normalized()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_rise = rng.randf_range(RISE_MIN, RISE_MAX)
	_drift = rng.randf_range(-DRIFT, DRIFT)

	global_position = _from
	_shape_up()


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = LAYER_WORLD
	collision_mask = 0
	if _mesh == null:
		_shape_up()


func hit_radius() -> float:
	return RADIUS


func _shape_up() -> void:
	if _mesh != null:
		return
	_mesh = MeshInstance3D.new()
	_mesh.name = "Glow"
	var ball := SphereMesh.new()
	ball.radius = RADIUS
	ball.height = RADIUS * 2.0
	ball.radial_segments = 16
	ball.rings = 8
	_mesh.mesh = ball
	_mesh.material_override = _glow_material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

	_light = OmniLight3D.new()
	_light.name = "Lamp"
	_light.light_color = COLOUR
	_light.light_energy = LIGHT_ENERGY
	_light.omni_range = LIGHT_RANGE
	_light.shadow_enabled = false
	add_child(_light)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var ball_shape := SphereShape3D.new()
	ball_shape.radius = RADIUS
	shape.shape = ball_shape
	add_child(shape)


func _glow_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = COLOUR
	material.emission_enabled = true
	material.emission = COLOUR
	material.emission_energy_multiplier = 3.0
	material.disable_receive_shadows = true
	return material


func _physics_process(delta: float) -> void:
	if _burst:
		return
	_age += delta
	var t := _age / FLIGHT
	if t >= 1.0:
		# The end of the arc. It fades rather than vanishing, on every peer, off
		# its own clock — nobody has to be told an orb ran out of lane.
		_fade_out()
		return
	global_position = _from \
		+ _along * (_length * t) \
		+ _across * (_drift * sin(t * PI)) \
		+ Vector3.UP * (_rise * sin(t * PI))


func range_hit(point: Vector3, by_peer: int, cause: int) -> void:
	if _burst:
		return
	_burst = true
	_pop(point)
	if by_peer == Net.local_id():
		HitNumber.pop(_text_root(), point, "+%d" % POINTS, COLOUR)
		AudioDirector.play_2d(AudioDirector.HITMARKER)
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("flash_hit"):
			hud.call("flash_hit", UIPalette.AMBER)
	if Net.is_host and RangeStats.instance != null:
		RangeStats.instance.record_target_hit(by_peer, cause, POINTS,
			RangeStats.shot_distance(by_peer, point))
	# Deferred, so the object is still perfectly alive for the projectile's own
	# handler, which is about to ask whether it survived. `SpearProjectile`
	# reads `is_queued_for_deletion`, which is true from this call onward.
	queue_free()


## The burst, parented to the world rather than to the orb: the orb is about to
## be freed and its children would go with it.
func _pop(at: Vector3) -> void:
	AudioDirector.play_3d_varied(AudioDirector.RANGE_ORB, at)
	var root := _text_root()
	if root == null:
		return
	var shell := OrbBurst.new()
	shell.name = "OrbBurst"
	root.add_child(shell)
	shell.begin(at)


## Ran out of lane. Not a hit, not scored, and no sound: an orb nobody shot
## should leave as quietly as it arrived.
func _fade_out() -> void:
	_burst = true
	queue_free()


## The expanding shell. An inner class rather than a fourth file, because it is
## nine lines of animation that only this target ever asks for.
class OrbBurst:
	extends Node3D

	var _age: float = 0.0
	var _mesh: MeshInstance3D
	var _light: OmniLight3D
	var _material: StandardMaterial3D
	var _sphere: SphereMesh

	func begin(at: Vector3) -> void:
		top_level = true
		global_transform = Transform3D.IDENTITY

		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.disable_receive_shadows = true
		_material.albedo_color = GlowOrb.COLOUR

		_sphere = SphereMesh.new()
		_sphere.radial_segments = 12
		_sphere.rings = 6
		_sphere.radius = GlowOrb.BURST_FROM
		_sphere.height = GlowOrb.BURST_FROM * 2.0

		_mesh = MeshInstance3D.new()
		_mesh.mesh = _sphere
		_mesh.material_override = _material
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh)
		_mesh.global_position = at

		_light = OmniLight3D.new()
		_light.light_color = GlowOrb.COLOUR
		_light.light_energy = GlowOrb.LIGHT_ENERGY * 2.0
		_light.omni_range = GlowOrb.LIGHT_RANGE
		_light.shadow_enabled = false
		add_child(_light)
		_light.global_position = at

	func _process(delta: float) -> void:
		_age += delta
		var t := clampf(_age / GlowOrb.BURST_LIFE, 0.0, 1.0)
		if t >= 1.0:
			queue_free()
			return
		var radius: float = lerpf(GlowOrb.BURST_FROM, GlowOrb.BURST_TO, t)
		_sphere.radius = radius
		_sphere.height = radius * 2.0
		_material.albedo_color = UIPalette.faded(GlowOrb.COLOUR, 1.0 - t)
		_light.light_energy = GlowOrb.LIGHT_ENERGY * 2.0 * (1.0 - t)
