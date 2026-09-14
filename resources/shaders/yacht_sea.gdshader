shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// The Mediterranean, at anchor, on a clear morning. Halcyon Wake's sea is most
// of what a player can see from three of its four decks, and it is also the
// void — over the side is a death — so it has two jobs that pull in opposite
// directions: be the most beautiful thing on the map, and look like it will
// kill you.
//
// Everything here is analytic. There is no water normal map, and that is a
// decision rather than an omission: neither CC0 library this project can reach
// ships an ocean normal set, and a tiling normal texture on a plane 2.8 km
// across announces its repeat somewhere between the rail and the horizon no
// matter how it is scrolled. Seven sine waves cost less than two texture
// fetches, never repeat, carry their own exact derivatives, and — the part that
// matters most — can be *faded by distance*, which is the whole trick behind
// the sun track (see `slope variance`, below).
//
// Cost: three waves in the vertex shader over an 18,432-triangle grid, four
// more per fragment, one exp for the sun track, one hash for the sparkle. One
// draw call, one material, no transparency, no sorting, no texture memory.

// --------------------------------------------------------------- the swell ---

// Where the sun is, handed in from the `Sun` node by `yacht_map.gd` rather than
// read from LIGHT0. The map may grow a second light — it has: a fill bounced
// off the water — and the order Godot registers directional lights in is not a
// thing to hang the sun track on.
uniform vec3 sun_direction = vec3(0.62, 0.62, -0.48);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.86);

// The swell runs from the bow aft, because a yacht at anchor lies to her cable
// head to wind and everything else on this map that moves in the wind — the
// ensign, the burgee — agrees with it. Amplitudes are small on purpose: this is
// a perfect morning, not a passage. Total crest-to-trough is about half a metre.
uniform float swell_scale : hint_range(0.0, 3.0) = 1.0;
// Displacement is faded to nothing between these radii so the grid's rim and
// the flat skirt beyond it meet with no crack. Both meshes run this shader, so
// both compute the identical fade and agree on the shared vertices exactly.
uniform float swell_fade_near = 100.0;
uniform float swell_fade_far = 118.0;

// --------------------------------------------------------------- the colour ---

// Straight down: no reflection reaches the eye, so this is the water's own
// colour, and the water is 40 m deep. Toward the horizon the same water is a
// Mediterranean blue because almost all of what comes back is sky.
uniform vec3 deep_color : source_color = vec3(0.012, 0.055, 0.082);
uniform vec3 far_color : source_color = vec3(0.09, 0.32, 0.44);
uniform float depth_curve : hint_range(0.1, 3.0) = 0.62;
// Very low-frequency variation in the body colour. Real open water is never one
// colour: this is depth and the shadows of cloud far off, and it is the
// difference between a sea and a sheet of blue.
uniform float mottle_strength : hint_range(0.0, 1.0) = 0.22;

// ---------------------------------------------------------- slope variance ---

// Past a few tens of metres the ripples that make the glitter are smaller than
// a pixel. Keeping the normals would alias into a crawling mess; dropping them
// and leaving the surface flat would kill the sun track, which is the single
// thing that most says "water". So the normal detail fades out with distance
// and its lost slope variance is handed to roughness instead, which is what
// broadens one hard highlight into a track that runs to the horizon.
uniform float detail_fade = 0.009;
uniform float roughness_near : hint_range(0.0, 1.0) = 0.045;
uniform float roughness_far : hint_range(0.0, 1.0) = 0.30;

// The sun track proper, as Cox and Munk wrote it: the slope distribution of a
// wind-roughened sea is a gaussian, and the track is that gaussian seen about
// the mirror direction. It stretches toward the horizon for free, because the
// flatter the view angle the less slope a facet needs to put the sun in your
// eye. One `exp`.
uniform float track_variance : hint_range(0.002, 0.2) = 0.016;
uniform float track_energy : hint_range(0.0, 20.0) = 4.0;
// Near the camera the track should break into individual facets rather than
// read as a painted streak.
uniform float sparkle : hint_range(0.0, 3.0) = 1.15;

// ------------------------------------------------------------ the waterline ---

// The hull's footprint at the waterline, repeated from `YachtMap` so the foam
// and the shadow under the boat can be a distance field instead of geometry.
// The old foam was a flat ring of triangles laid on a flat sea; the moment the
// sea got a swell it would have been a ring of triangles floating over one.
uniform float wl_beam = 5.9;
uniform float wl_bow_z = -31.0;
uniform float wl_taper_z = -8.0;
uniform float wl_stern_z = 26.0;
uniform float foam_width : hint_range(0.0, 4.0) = 1.15;
uniform float foam_energy : hint_range(0.0, 2.0) = 1.05;
// How far out from the hull the water goes dark. This is the boat's body under
// the surface — forty metres of nothing below that — and it is the one cue that
// says the sea has a downward as well as an outward.
uniform float hull_shade_reach : hint_range(0.0, 20.0) = 7.5;
uniform float hull_shade : hint_range(0.0, 1.0) = 0.55;

const float G = 9.81;

varying vec3 world;

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

// One long-crested deep-water wave, as (height, dh/dx, dh/dz). The phase speed
// is the real one — c = sqrt(g / k) — so the long swell outruns the chop by the
// factor it does at sea, which is most of why a sum of sines reads as water at
// all rather than as a vibrating tablecloth.
vec3 wave(vec2 p, vec2 dir, float len, float amp, float t) {
	float k = 6.28318530718 / len;
	float c = sqrt(G / k);
	float ph = k * dot(dir, p) - k * c * t;
	float s = sin(ph);
	float co = cos(ph);
	return vec3(amp * s, amp * k * co * dir.x, amp * k * co * dir.y);
}

// The three components big enough to be worth moving vertices for.
vec3 swell(vec2 p, float t) {
	vec3 a = wave(p, normalize(vec2(0.18, 0.98)), 26.0, 0.235, t);
	a += wave(p, normalize(vec2(-0.40, 0.92)), 15.0, 0.125, t);
	a += wave(p, normalize(vec2(0.64, 0.77)), 8.6, 0.060, t);
	return a;
}

// Four more, small enough that only their slope matters. They are warped by the
// swell's own height, so the chop bends over the back of each roller instead of
// marching across it on its own grid.
vec3 chop(vec2 p, float warp, float t) {
	vec2 q = p + vec2(warp * 1.6, warp * -1.1);
	vec3 a = wave(q, normalize(vec2(0.31, 0.95)), 4.60, 0.0240, t);
	a += wave(q, normalize(vec2(-0.87, 0.49)), 2.90, 0.0160, t);
	a += wave(q, normalize(vec2(0.95, -0.31)), 1.70, 0.0090, t);
	a += wave(q, normalize(vec2(-0.21, -0.98)), 0.95, 0.0046, t);
	return a;
}

float swell_fade(vec2 p) {
	float r = max(abs(p.x), abs(p.y));
	return 1.0 - smoothstep(swell_fade_near, swell_fade_far, r);
}

// Half the hull's width at the waterline, and then a 2D signed distance to that
// footprint. `YachtMap.waterline_half_width` is the same curve.
float wl_half(float z) {
	if (z >= wl_taper_z) {
		return wl_beam;
	}
	float t = (wl_taper_z - z) / (wl_taper_z - wl_bow_z);
	if (t >= 1.0) {
		return 0.0;
	}
	return wl_beam * (1.0 - t * t);
}

float hull_distance(vec2 p) {
	float z = clamp(p.y, wl_bow_z, wl_stern_z);
	float dx = abs(p.x) - wl_half(z);
	float dz = max(p.y - wl_stern_z, wl_bow_z - p.y);
	return length(max(vec2(dx, dz), vec2(0.0))) + min(max(dx, dz), 0.0);
}


// The sea mesh is built in world coordinates under a node at the origin
// (`YachtMap._build_sea`), so the model matrix is the identity and `VERTEX` is
// already a world position. Saying so here saves an `inverse(MODEL_MATRIX)` per
// vertex on the largest mesh in the map.
void vertex() {
	float fade = swell_fade(VERTEX.xz) * swell_scale;
	vec3 s = swell(VERTEX.xz, TIME) * fade;
	VERTEX.y += s.x;
	world = VERTEX;
	NORMAL = normalize(vec3(-s.y, 1.0, -s.z));
}


void fragment() {
	vec2 p = world.xz;
	// `VERTEX` in a fragment shader is the view-space position, so its length is
	// the distance from the eye — which is the number the whole detail/roughness
	// trade below is keyed on.
	float dist = length(VERTEX);
	vec3 view_dir = normalize(INV_VIEW_MATRIX[3].xyz - world);

	// --- normal --------------------------------------------------------------
	float fade = swell_fade(p) * swell_scale;
	vec3 s = swell(p, TIME) * fade;
	float detail = exp(-dist * detail_fade);
	vec3 c = chop(p, s.x, TIME) * detail;
	vec3 n = normalize(vec3(-(s.y + c.y), 1.0, -(s.z + c.z)));

	// --- body colour ---------------------------------------------------------
	float down = clamp(dot(n, view_dir), 0.0, 1.0);
	float mottle = value_noise(p * 0.0045) * 0.6 + value_noise(p * 0.017) * 0.4;
	vec3 body = mix(far_color, deep_color, pow(down, depth_curve));
	body *= mix(1.0 - mottle_strength, 1.0 + mottle_strength * 0.35, mottle);

	// --- the boat in the water ----------------------------------------------
	float hd = hull_distance(p);
	body *= mix(1.0, 1.0 - hull_shade, smoothstep(hull_shade_reach, -0.5, hd));

	// Foam where the swell works against the topsides. It lives on the water,
	// so it rides the swell for nothing, and it breathes with the wave height
	// at the hull instead of being a painted ring.
	float lap = 0.55 + 0.45 * sin(p.y * 0.9 + TIME * 1.7 + s.x * 9.0);
	float noise = 0.45 + 0.85 * value_noise(p * 1.3 + vec2(0.0, TIME * 0.35));
	float foam = smoothstep(foam_width * (0.7 + 0.6 * lap), 0.0, hd) * noise;
	foam *= smoothstep(-0.9, 0.2, hd) * foam_energy;

	// --- the sun track -------------------------------------------------------
	// Cox and Munk, in three lines: the slope distribution of a wind-roughened
	// sea is a gaussian, and the sun track is that gaussian seen about the mirror
	// direction. It runs to the horizon for nothing, because out there one degree
	// of view angle covers hundreds of metres of sea and every one of them gets a
	// chance to hold a facet at the right angle.
	vec3 half_v = normalize(sun_direction + view_dir);
	float ct = max(dot(n, half_v), 1e-3);
	float tan2 = (1.0 - ct * ct) / (ct * ct);
	float track = exp(-tan2 / track_variance);
	// Glitter at your feet is dimmer than glitter half a mile off — which is why
	// the track runs *away* from you, and why standing on the flybridge and
	// looking down-sun is the best view on this map.
	track *= mix(0.22, 1.0, pow(1.0 - down, 2.5));
	// Close in it has to be a thousand separate facets. Far off there is nothing
	// left to break it with, and the eye expects a sheet out there anyway.
	float g = value_noise(p * 5.3 + vec2(TIME * 0.7, TIME * 0.42));
	track *= mix(1.0, g * g * 2.6, clamp(sparkle * detail, 0.0, 1.0));
	track *= clamp(dot(n, sun_direction), 0.0, 1.0);

	ALBEDO = mix(body, vec3(0.90, 0.95, 0.97), clamp(foam, 0.0, 1.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// The variance the fading detail took away, handed to roughness. Foam is
	// rough by nature and must not mirror anything.
	ROUGHNESS = mix(roughness_far, roughness_near, detail) + foam * 0.6;
	METALLIC = 0.0;
	SPECULAR = 0.55;
	EMISSION = sun_color * track * track_energy * (1.0 - clamp(foam, 0.0, 1.0));
}
