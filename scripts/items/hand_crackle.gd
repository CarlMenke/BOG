class_name HandCrackle
extends Node3D
## Energy arcing around the Elder's empty fist while the bolt is ready.
##
## This exists to keep one sentence true. The spear's whole virtue is that an
## empty hand says "harmless" from across a clearing (see the header of
## `held_spear.gd`, and D-036, which deleted the HUD's recharge ring precisely
## because the hand already said it better). An Elder has no spear — so without
## this, every Elder's hand would be empty all the time and the one readable
## thing about an armed opponent would be gone for the most dangerous player in
## the match.
##
## So the Elder's hand **crackles when the lightning is ready and is bare while
## it recharges**, which is the same read at the same distance, with no HUD
## element and no number (D-038).
##
## It is the bolt's own geometry in miniature — `LightningBolt.jagged` builds
## both — because the tell and the thing it is promising have to be recognisably
## the same substance. What is *not* shared is the cost: this is alive for as
## long as an Elder stands around, potentially minutes at a time and on up to
## eight Gubs, where a bolt is alive for a fifth of a second. Hence three short
## arcs rather than eighteen-segment strokes with branches, one small light
## instead of two enormous ones, and a redraw cadence half the bolt's.

## How many arcs are alive at once, and how long each one lives before it is
## replaced by a fresh one somewhere else around the fist. Staggered rather than
## redrawn together: three arcs all flicking at the same instant reads as a
## strobe, where three on their own clocks reads as something unstable.
const ARCS := 3
const ARC_LIFE := 0.09
## How far from the hand's own origin the arcs reach. Small — this is a fist, and
## the whole effect has to sit in the volume `held_spear.gd` measured as clear of
## the Gub's skin in every carried clip.
const RADIUS := 0.16
const ARC_SEGMENTS := 4
const ARC_JITTER := 0.30
const ARC_WIDTH := 0.022

## The bolt's own violet, and driven the same way: the brightness is on the
## material because a vertex colour cannot carry a value over 1 (see
## `LightningBolt.CORE_ENERGY`).
const COLOUR := Color(0.80, 0.62, 1.00)
const ENERGY := 2.4

## A small light, because that is what actually carries. The lesson is D-035's,
## learned on the letter card: a glyph in a gold fist at twenty metres is a gold
## smudge on a gold body, and what reads at that range is that the Gub is *lit*.
## Dimmer and shorter-ranged than the card's 1.8 over 4 m, because unlike a hold
## this is the Elder's resting state and it is meant to be a hum rather than a
## lamp.
const LIGHT_ENERGY := 1.1
const LIGHT_RANGE := 2.6
## How far the light breathes either side of that. Nothing in this game pulses,
## and it is worth one exception: a perfectly steady glow reads as a material
## property of the Gub, and a wandering one reads as something being held in.
const PULSE_DEPTH := 0.28
const PULSE_SPEED := 7.0

var _mesh: ImmediateMesh
var _stroke: MeshInstance3D
var _material: StandardMaterial3D
var _light: OmniLight3D
var _age: float = 0.0
var _next_redraw: float = 0.0


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_material.disable_receive_shadows = true
	_material.albedo_color = Color(COLOUR.r * ENERGY, COLOUR.g * ENERGY,
		COLOUR.b * ENERGY, 1.0)

	_stroke = MeshInstance3D.new()
	_stroke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh = ImmediateMesh.new()
	_stroke.mesh = _mesh
	_stroke.material_override = _material
	add_child(_stroke)

	_light = OmniLight3D.new()
	_light.light_color = COLOUR
	_light.light_energy = LIGHT_ENERGY
	_light.omni_range = LIGHT_RANGE
	_light.shadow_enabled = false
	add_child(_light)
	_redraw()


func _process(delta: float) -> void:
	_age += delta
	_light.light_energy = LIGHT_ENERGY \
		* (1.0 + PULSE_DEPTH * sin(_age * PULSE_SPEED))
	if _age >= _next_redraw:
		_next_redraw = _age + ARC_LIFE / float(ARCS)
		_redraw()


## Rebuild the arcs, in the hand's own local space so they ride the fist through
## every clip without anything here having to follow a bone.
##
## Deliberately *not* camera-facing, unlike the bolt: at this size the ribbons
## are two centimetres across and the cost of solving a facing per vertex buys
## nothing you could see. They are drawn double-sided, so an arc seen edge-on
## simply thins rather than vanishing.
func _redraw() -> void:
	_mesh.clear_surfaces()
	for i in ARCS:
		var from := _around()
		var to := _around()
		if from.distance_to(to) < RADIUS * 0.5:
			continue
		var path := LightningBolt.jagged(from, to, ARC_SEGMENTS, ARC_JITTER)
		_ribbon(path)


## A point on a small sphere around the fist.
func _around() -> Vector3:
	return Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)).normalized() * RADIUS


func _ribbon(path: PackedVector3Array) -> void:
	if path.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in path.size():
		var point := path[i]
		var along: Vector3 = path[i + 1] - point if i < path.size() - 1 \
			else point - path[i - 1]
		if along.length_squared() < 0.000001:
			continue
		var side := along.normalized().cross(Vector3.UP)
		if side.length_squared() < 0.000001:
			side = along.normalized().cross(Vector3.RIGHT)
		side = side.normalized() * ARC_WIDTH
		# Brightest in the middle of each arc and out at both ends, which is
		# what stops three straight segments reading as a wireframe.
		var t := sin(PI * float(i) / float(maxi(path.size() - 1, 1)))
		var tint := Color(1.0, 1.0, 1.0, t)
		_mesh.surface_set_color(tint)
		_mesh.surface_add_vertex(point + side)
		_mesh.surface_set_color(tint)
		_mesh.surface_add_vertex(point - side)
	_mesh.surface_end()
