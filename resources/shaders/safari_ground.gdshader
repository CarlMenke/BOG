shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

// The sand of Kopje Crossing, and the plain it stands over.
//
// This is the biggest surface in the game: a 96 m plateau with nothing on most
// of it, seen at a grazing angle from eye height on a spawn pad, which is the
// only framing a player ever has. It was one `NoiseTexture2D` between two very
// similar sands on a 10 m tile, and from a pad that is a flat brown floor —
// the tile is too small to be a landscape feature and too large to be grain, so
// it falls between the two and reads as nothing at all.
//
// Three scales instead, and they are chosen against the distances a player
// actually looks over rather than against how the texture looks flat on:
//
//   * `patch_metres` at ~38 m — the size of a drift, a pan, a burnt patch. This
//     is the only scale big enough to be seen from the summit, and it is what
//     stops 96 m of ground reading as one colour.
//   * `mottle_metres` at ~4 m — the scale of scuffed ground. This is the one
//     doing the work at the ten-to-thirty metres a fight happens over.
//   * `grain_metres` at ~0.5 m — brightness only, no hue. Under your feet it is
//     texture; at twenty metres the mipmap has averaged it to nothing, which is
//     exactly right, because at twenty metres you cannot see grains of sand
//     either.
//
// It also draws the wet ring at the waterhole, which is a uniform and not a
// piece of geometry: `damp_centre` darkens the sand toward the water and takes
// the roughness down with it, so the shore is damp rather than being a decal
// lying on top of dry sand. That is one `length()` per fragment against a ring
// mesh, an extra draw call and a sorting decision.
//
// The same shader dresses the plain beyond the cliff, with the three scales and
// the palette moved: the land below has to be obviously the same land, and just
// as obviously a long way off.
//
// `cull_disabled` is not laziness. The two meshes this runs on are wound
// opposite ways — `_build_ground` builds the plateau as a fan wound `[0, b, a]`
// so that the face you stand on is the front one, and Godot's `PlaneMesh`
// under the cliff is wound the other way — so `cull_back` renders one of them
// and drops the other, and the symptom is the whole plateau vanishing and the
// plain showing through where the ground should be. Neither surface is ever
// seen from underneath, and between them they are a hundred triangles.

uniform sampler2D sand_noise : filter_linear_mipmap, repeat_enable;

// Darkest, middle and palest sand. Kept inside the map's existing palette —
// `safari_env.tres` measured its exposure against ground this colour, and a
// brighter sand is a re-measure.
// These are the *product* the old material actually put on screen: it was an
// `albedo_color` of (0.80, 0.68, 0.44) multiplied by a texture ramped between
// (0.72, 0.58, 0.36) and (0.90, 0.80, 0.56), so the sand on the plateau ran
// from about (0.58, 0.39, 0.16) to (0.72, 0.54, 0.25). Stated here directly,
// with the range opened out at both ends rather than moved — `safari_env.tres`
// measured its exposure against ground this colour and a brighter sand is a
// re-measure.
uniform vec3 sand_deep : source_color = vec3(0.50, 0.33, 0.15);
uniform vec3 sand_mid : source_color = vec3(0.65, 0.47, 0.22);
uniform vec3 sand_pale : source_color = vec3(0.78, 0.63, 0.34);

uniform float patch_metres : hint_range(4.0, 400.0) = 38.0;
uniform float mottle_metres : hint_range(0.5, 40.0) = 4.3;
uniform float grain_metres : hint_range(0.05, 4.0) = 0.52;
// How much of the brightness the finest scale is allowed to move. Small: it is
// grain, not gravel.
uniform float grain_depth : hint_range(0.0, 0.4) = 0.09;
// Pushes the mix toward the pale end. The map is meant to be the brightest
// thing in the game.
uniform float bleach : hint_range(-0.3, 0.3) = 0.04;

// The wet ring at the waterhole. Radius is where the damp *ends*; it fades in
// from there to the waterline.
uniform vec2 damp_centre = vec2(-25.0, 23.0);
uniform float damp_radius : hint_range(0.0, 40.0) = 13.5;
uniform float damp_edge : hint_range(0.5, 20.0) = 6.0;
uniform vec3 damp_color : source_color = vec3(0.34, 0.26, 0.16);
uniform float damp_strength : hint_range(0.0, 1.0) = 0.8;

uniform float roughness_dry : hint_range(0.0, 1.0) = 1.0;
uniform float roughness_damp : hint_range(0.0, 1.0) = 0.45;

varying vec3 world_pos;


void vertex() {
	// `world_vertex_coords`, so the ground is textured by where it *is* rather
	// than by the UVs the fan happens to carry. The plateau is a 96-vertex fan
	// around one centre point; anything keyed on its UVs pinwheels.
	world_pos = VERTEX;
}


void fragment() {
	vec2 p = world_pos.xz;
	float patch = texture(sand_noise, p / patch_metres).r;
	float mottle = texture(sand_noise, p / mottle_metres + vec2(0.37, 0.71)).r;
	float grain = texture(sand_noise, p / grain_metres + vec2(0.11, 0.53)).r;

	// Weighted toward the big scale, because that is the one that has to survive
	// being looked at from 60 m away.
	float v = clamp(patch * 0.64 + mottle * 0.36 + bleach, 0.0, 1.0);
	vec3 col = v < 0.5
		? mix(sand_deep, sand_mid, v * 2.0)
		: mix(sand_mid, sand_pale, (v - 0.5) * 2.0);
	// Grain moves brightness only. A hue shift at half a metre is gravel.
	col *= 1.0 + (grain - 0.5) * 2.0 * grain_depth;

	float damp = 1.0 - smoothstep(damp_radius - damp_edge, damp_radius,
		length(p - damp_centre));
	damp *= damp;

	ALBEDO = mix(col, damp_color, damp * damp_strength);
	ROUGHNESS = mix(roughness_dry, roughness_damp, damp);
	SPECULAR = 0.35;
	METALLIC = 0.0;
}
