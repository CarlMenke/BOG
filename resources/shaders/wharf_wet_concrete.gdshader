shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// The yard floor of Lantern Wharf: real concrete, wetted down at runtime.
//
// The three maps sampled here are a CC0 Poly Haven set (see
// `assets/maps/wharf/SOURCES.md`) and they are dry, even, photographed in
// daylight concrete. What makes this a dock at dusk is the rain that stopped an
// hour ago, and none of that is in the photographs — so it is put back here,
// in the fragment shader, where it costs no load time and no texture memory:
//
//   * a seeded low-frequency mask picks out where the water has pooled. Value
//     noise in **world space**, so two clients see the same puddles in the same
//     places by construction rather than by agreeing on a seed, and so a puddle
//     does not slide when the floor quad is moved;
//   * inside a puddle the roughness drops from concrete's 0.7-ish to near a
//     mirror, which is what lets the environment's SSR find the lamp heads and
//     draw the long vertical smear under each one;
//   * the albedo darkens, because wet concrete is dark concrete;
//   * the photographic normal is flattened toward the water's own surface — a
//     puddle does not have the aggregate of the concrete under it standing
//     proud of it;
//   * and two crossed waves ripple that surface. This is the cheapest moving
//     thing on the map and one of the most valuable: a still mirror reads as a
//     bug, and a mirror that breathes reads as weather.
//
// Everything outside the puddles is damp rather than dry — `damp` multiplies
// the whole roughness map down — because a yard where only the puddles are wet
// reads as a dry yard with holes in it.
//
// Budget: one extra texture fetch over a StandardMaterial3D (three maps rather
// than two), plus twelve hashes of value noise and two sines, on a surface that
// is at most half the screen. It replaces a `NoiseTexture2D` that was being
// generated at load.

group_uniforms surface;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.62, 0.62, 0.64);
uniform float normal_depth : hint_range(0.0, 3.0) = 0.85;
// How many metres of floor one tile of the maps covers. The mesh's UVs are
// already in metres over the tile, so this is a second, finer detail pass over
// the same data rather than a re-scale of it.
uniform float detail_tiles : hint_range(1.0, 16.0) = 5.0;
uniform float detail_mix : hint_range(0.0, 1.0) = 0.35;

group_uniforms wet;
// Metres across one puddle field cell. 7 m is a little wider than an aisle, so
// the pools sit *in* aisles rather than tiling with the containers.
uniform float puddle_scale : hint_range(1.0, 30.0) = 7.0;
uniform float puddle_coverage : hint_range(0.0, 1.0) = 0.46;
uniform float puddle_edge : hint_range(0.01, 0.4) = 0.13;
uniform float wet_roughness : hint_range(0.0, 0.4) = 0.045;
uniform float wet_darken : hint_range(0.0, 1.0) = 0.55;
// Everything is damp, not only the pools.
uniform float damp : hint_range(0.2, 1.0) = 0.74;
uniform float ripple_strength : hint_range(0.0, 0.3) = 0.045;
uniform float ripple_speed : hint_range(0.0, 2.0) = 0.42;
uniform vec3 water_tint : source_color = vec3(0.34, 0.37, 0.42);


float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Three octaves. Two is a blobby field with no small pools in it; four costs a
// third more hashes for detail that is under the resolution of a puddle edge.
float fbm(vec2 p) {
	float sum = 0.5 * value_noise(p);
	p = p * 2.07 + vec2(11.3, 4.9);
	sum += 0.3 * value_noise(p);
	p = p * 2.03 + vec2(7.1, 19.7);
	sum += 0.2 * value_noise(p);
	return sum;
}


void fragment() {
	vec2 uv = UV;
	vec2 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;

	// Two samples of the same set at different rates, mixed. One tile of a 2k
	// map over 6 m is plenty of grain up close and a visible repeat at twenty
	// metres; a second pass at a fifth of the size breaks that repeat up for
	// one extra fetch.
	vec3 base = texture(albedo_tex, uv).rgb;
	vec3 fine = texture(albedo_tex, uv * detail_tiles + vec2(0.37, 0.61)).rgb;
	vec3 albedo = mix(base, base * (0.5 + fine), detail_mix) * tint;

	float rough = texture(rough_tex, uv).r;
	vec3 map_n = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	map_n.xy *= normal_depth;

	// --- the water ----------------------------------------------------------
	float field = fbm(world / puddle_scale);
	float puddle = smoothstep(puddle_coverage, puddle_coverage + puddle_edge, field);

	// Two crossed waves, incommensurate rates, tiny amplitude. This is the
	// whole of the animation on this surface.
	float t = TIME * ripple_speed;
	vec2 ripple = vec2(
		sin(world.x * 3.1 + world.y * 1.7 + t * 1.9) + 0.6 * sin(world.y * 6.7 - t * 2.7),
		cos(world.y * 2.9 - world.x * 1.3 + t * 1.6) + 0.6 * cos(world.x * 7.1 + t * 2.3));
	vec3 water_n = normalize(vec3(ripple * ripple_strength, 1.0));

	ALBEDO = mix(albedo, albedo * (1.0 - wet_darken) + water_tint * 0.12, puddle);
	ROUGHNESS = mix(rough * damp, wet_roughness, puddle);
	// Water is a dielectric with a low F0, but it is also the only thing here
	// bright enough to carry a lamp head across twenty metres of floor, so the
	// specular stays at the default rather than being talked down.
	NORMAL_MAP = normalize(mix(map_n, water_n, puddle)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
