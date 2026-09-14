shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// The waterhole on Kopje Crossing.
//
// It was a `StandardMaterial3D` at roughness 0.05 with a little metallic on it,
// which on a map lit by one hard noon sun made a fifteen-metre mirror: in every
// render it came out as a sheet of white ice lying in the sand. Two things were
// wrong with that and both are fixed here.
//
// **A waterhole is not clean.** It is the last water on a plateau in the dry
// season, it is shallow, it is trodden, and what you see in it is mostly the
// mud under it. So the colour is a depth blend — silt at the edge, a deeper
// green-brown toward the middle — and the sky only comes back off it at a
// grazing angle, through a Fresnel term, the way it does off real water.
//
// **A waterhole moves.** It is the only surface on the map that is allowed to,
// and on a map whose whole problem was stillness that matters more than it
// looks like it should. Two noise fields scrolling across each other at
// different speeds and angles perturb the normal; that is the entire animation
// and it costs two texture fetches.
//
// Cost: one 15 m disc of 48 segments, drawn once, alpha-blended, no shadow, no
// collider, no screen texture. It is the cheapest thing in this pass.

uniform sampler2D ripple_noise : filter_linear_mipmap, repeat_enable;

// Silt at the rim, water at the middle, and how fast one becomes the other.
uniform vec4 shallow_color : source_color = vec4(0.42, 0.36, 0.22, 0.72);
uniform vec4 deep_color : source_color = vec4(0.13, 0.20, 0.17, 0.93);
uniform float edge_metres : hint_range(0.1, 12.0) = 3.4;
uniform float radius_metres : hint_range(1.0, 40.0) = 7.5;
// Where the disc is, in world metres. Read from the world position rather than
// from UVs because a `CylinderMesh` cap does not carry the UVs this wants.
uniform vec2 centre_xz = vec2(-25.0, 23.0);

// What the sky puts back. Keyed off the Fresnel term, so it is a sheen at the
// far rim and almost nothing under your feet — which is what stops it reading
// as a mirror lying flat in the sand.
uniform vec4 sheen_color : source_color = vec4(0.72, 0.80, 0.90, 1.0);
uniform float sheen : hint_range(0.0, 2.0) = 0.85;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.4;

// Metres per noise tile, and metres per second of scroll, for the two fields.
uniform float ripple_size_a : hint_range(0.2, 20.0) = 3.1;
uniform float ripple_size_b : hint_range(0.2, 20.0) = 1.35;
uniform vec2 ripple_drift_a = vec2(0.09, 0.05);
uniform vec2 ripple_drift_b = vec2(-0.06, 0.11);
uniform float ripple_strength : hint_range(0.0, 2.0) = 0.55;

varying vec3 world_pos;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


// Central-difference normal out of two scrolling scalar fields. Cheaper than a
// normal map and it needs no texture but the one noise tile.
vec3 ripple_normal(vec2 p, float t) {
	vec2 ua = p / ripple_size_a + ripple_drift_a * t;
	vec2 ub = p / ripple_size_b + ripple_drift_b * t;
	float e = 0.02;
	float h = texture(ripple_noise, ua).r + texture(ripple_noise, ub).r * 0.6;
	float hx = texture(ripple_noise, ua + vec2(e, 0.0)).r
		+ texture(ripple_noise, ub + vec2(e, 0.0)).r * 0.6;
	float hz = texture(ripple_noise, ua + vec2(0.0, e)).r
		+ texture(ripple_noise, ub + vec2(0.0, e)).r * 0.6;
	return normalize(vec3((h - hx) * ripple_strength, 0.12, (h - hz) * ripple_strength));
}


void fragment() {
	// Distance from the middle of the disc, in metres.
	float r = length(world_pos.xz - centre_xz);
	float depth = clamp((radius_metres - r) / edge_metres, 0.0, 1.0);
	// Squared, so the silt ring hugs the shore rather than reaching halfway in.
	depth *= depth;

	vec3 n = ripple_normal(world_pos.xz, TIME);
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(n, 0.0)).xyz, 0.75));

	vec4 body = mix(shallow_color, deep_color, depth);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0),
		fresnel_power);

	ALBEDO = body.rgb;
	ALPHA = body.a;
	ROUGHNESS = mix(0.55, 0.22, depth);
	SPECULAR = 0.6;
	METALLIC = 0.0;
	// The sky, back off the surface, only where you are looking across it.
	EMISSION = sheen_color.rgb * fres * sheen * depth;
}
