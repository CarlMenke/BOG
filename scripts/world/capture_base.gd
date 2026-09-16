class_name CaptureBase
extends Node3D
## A team's base in Capture B·O·G, drawn in the team's colour so a carrier knows
## where to run from across the map (D-051).
##
## Three parts, all cosmetic — the rule is `CaptureLayout.in_base`, and nothing
## here collides with anything:
##
## - **a band** round the edge of the base, a short glowing wall that fades
##   upward, so the edge reads on a slope where a flat ring would sink into the
##   hill on one side and float on the other;
## - **a column of light** up the middle, faint and tall, which is what reads
##   from the far side of the map over a container or a rock;
## - **a floor wash** inside the ring and a team-coloured light on the ground.
##
## Built on every peer by `arena.gd` from the layout every peer plans
## identically, so nothing about it is replicated.

const BAND_HEIGHT := 0.9
const COLUMN_HEIGHT := 14.0
const COLUMN_RADIUS := 0.55

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float strength = 1.0;
uniform float falloff = 2.0;
void fragment() {
	// UV.y runs 0 at the top of a CylinderMesh's side to 1 at the bottom.
	float fade = pow(clamp(UV.y, 0.0, 1.0), falloff);
	ALBEDO = tint.rgb * strength;
	ALPHA = fade * tint.a;
}
"""

static var _shader: Shader


static func create(team: int, radius: float) -> CaptureBase:
	var base := CaptureBase.new()
	base.name = "Base%d" % (team + 1)
	var colour := UIPalette.team_colour(team)

	var band := MeshInstance3D.new()
	band.name = "Band"
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = radius
	band_mesh.bottom_radius = radius
	band_mesh.height = BAND_HEIGHT
	band_mesh.cap_top = false
	band_mesh.cap_bottom = false
	band_mesh.radial_segments = 48
	band.mesh = band_mesh
	band.material_override = _glow(colour, 1.6, 1.5)
	# Sunk a little, so the band starts under the ground on a gentle slope
	# rather than hovering above it.
	band.position = Vector3(0.0, BAND_HEIGHT * 0.5 - 0.15, 0.0)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.add_child(band)

	var column := MeshInstance3D.new()
	column.name = "Column"
	var column_mesh := CylinderMesh.new()
	column_mesh.top_radius = COLUMN_RADIUS * 0.6
	column_mesh.bottom_radius = COLUMN_RADIUS
	column_mesh.height = COLUMN_HEIGHT
	column_mesh.cap_top = false
	column_mesh.cap_bottom = false
	column.mesh = column_mesh
	column.material_override = _glow(colour, 0.9, 1.2)
	column.position = Vector3(0.0, COLUMN_HEIGHT * 0.5, 0.0)
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.add_child(column)

	var wash := MeshInstance3D.new()
	wash.name = "Wash"
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.02
	disc.radial_segments = 48
	wash.mesh = disc
	var flat := StandardMaterial3D.new()
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flat.albedo_color = Color(colour, 0.16)
	flat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wash.material_override = flat
	wash.position = Vector3(0.0, 0.04, 0.0)
	wash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.add_child(wash)

	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = colour
	light.light_energy = 2.2
	light.omni_range = radius * 2.0
	light.position = Vector3(0.0, 1.2, 0.0)
	base.add_child(light)
	return base


static func _glow(colour: Color, strength: float, falloff: float) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("tint", Color(colour, 0.85))
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("falloff", falloff)
	return material
