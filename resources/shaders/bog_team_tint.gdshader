shader_type spatial;
// The Bog's body in a team's colour (D-046). Applied by `Bog.set_team_tint` as a
// surface override on the body mesh only; the Elder's robe keeps its own purple.
//
// A recolour, not a multiply. The body texture is a saturated yellow, and
// yellow times blue is olive and yellow times violet is brown, so a plain
// `albedo_color` tint cannot give most of the eight team colours at all. What
// this does instead is find the yellow skin in the texture (by hue and
// saturation, so the eye whites, the pupils and the dark patches are left alone)
// and replace its colour with the team's while keeping its brightness, so the
// painted shading and the lighting still read.
//
// Everything else copies the imported `StandardMaterial3D` in `bog.glb`: its
// roughness, its double-sided cull, and its emission, which is the same texture
// multiplied by a grey. `depth_draw_always` is for the corpse: a ragdoll fades
// through `GeometryInstance3D.transparency`, which forces the transparent pass,
// and a body that stops writing depth in that pass is seen through to its own
// insides (see `bog_ragdoll.gd`). On an opaque draw it changes nothing.
render_mode cull_disabled, depth_draw_always, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 team_colour : source_color = vec3(1.0);
// How much of the yellow is replaced. 1.0 in game; kept as a dial for renders.
uniform float strength : hint_range(0.0, 1.0) = 1.0;
// Linear brightness, as the largest channel, that maps to exactly `team_colour`;
// darker and lighter texels scale around it, which is what keeps the painted
// shading. 0.9 sits near the brightest of the body's yellow, so a tinted Bog
// comes out about as bright as a yellow one. 0.72 was tried first and every team
// read a step paler and more washed-out than the Bog it replaced.
uniform float reference_value = 0.9;
uniform float roughness = 0.9;
uniform float specular = 0.5;
uniform vec3 emission : source_color = vec3(0.4236);
uniform float emission_energy = 1.0;
// The two optional maps a skin folder may carry beside its `basecolor.png`
// (D-154): Tripo ships a metallic-roughness with its retextures and can ship an
// emissive, and CHIP's glaze, OOZE's wet slime and VOLT's circuitry are those
// maps or they are nothing. Both default to the value that makes them
// *disappear* — white multiplies the roughness by one, black adds no glow — so
// a skin with no maps, and the plain body, are lit exactly as before.
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D emission_texture : source_color, hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
// The glow's brightness, the dial `KHR_materials_emissive_strength` would have
// been if the extractor carried it. Past the environment's 1.45 glow threshold
// (D-138) a bright texel of the map blooms.
uniform float emission_texture_energy = 1.0;

vec3 recolour(vec3 texel) {
	float hi = max(texel.r, max(texel.g, texel.b));
	float lo = min(texel.r, min(texel.g, texel.b));
	float saturation = hi > 1e-4 ? (hi - lo) / hi : 0.0;
	// Hue in degrees, only as far as telling yellow-orange from everything else.
	float hue = 0.0;
	float chroma = hi - lo;
	if (chroma > 1e-4) {
		if (hi == texel.r) {
			hue = 60.0 * mod((texel.g - texel.b) / chroma, 6.0);
		} else if (hi == texel.g) {
			hue = 60.0 * ((texel.b - texel.r) / chroma + 2.0);
		} else {
			hue = 60.0 * ((texel.r - texel.g) / chroma + 4.0);
		}
	}
	float skin = smoothstep(0.35, 0.6, saturation)
		* smoothstep(15.0, 30.0, hue) * (1.0 - smoothstep(75.0, 95.0, hue));
	vec3 tinted = team_colour * (hi / reference_value);
	return mix(texel, tinted, skin * strength);
}

void fragment() {
	vec3 base = recolour(texture(albedo_texture, UV).rgb);
	ALBEDO = base;
	// Red, not green: the extractor has already pulled glTF's green channel out
	// into a grey PNG, which is what `BaseMaterial3D` reads on red as well, so
	// the two paths onto this body read the same file the same way.
	ROUGHNESS = roughness * texture(roughness_texture, UV).r;
	METALLIC = 0.0;
	SPECULAR = specular;
	EMISSION = base * emission * emission_energy
		+ texture(emission_texture, UV).rgb * emission_texture_energy;
}
