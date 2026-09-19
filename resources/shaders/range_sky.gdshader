shader_type sky;

// The sky over Highsun Grounds. It was written for a golden hour and it now
// carries a lit morning: the shader only declares the knobs and their
// fallbacks, and **all the tuning lives in `range_sky.tres`**, which is where
// the dusk-to-day move was made. The defaults below are the dusk ones and are
// left that way deliberately — they are what a scene opened without its
// resource falls back to, and a fallback that has drifted is a fallback nobody
// can read the history off.
//
// Started as a fork of `safari_sky.gdshader` (D-061) and kept the half of it
// that was right: the graded backdrop, the aureole, the cirrus sheet
// and the `LIGHT0` follow that pins the disc to this map's own Sun. Kopje owns
// `safari_sky.gdshader` and the Hollow owns `enchanted_sky.gdshader`; neither
// is edited from here.
//
// ## Why the cumulus are not marched, and this is the whole of the file
//
// Kopje's clouds are a **marched heightfield**: a column standing on a flat
// base at a stated altitude, walked front-to-back along the view ray. That is
// the correct model for a noon sky, where you look *up* at 20 to 60 degrees and
// the ray crosses the layer quickly. It was tried here at length and it cannot
// make a cotton-candy sunset, for a reason that is arithmetic rather than
// taste.
//
// A standing Bog's eye sees 0 to 37.5 degrees of sky (75 degree vertical FOV,
// camera level). For a ray at elevation θ to climb a whole column the march has
// to run to `top / sin θ`; for there to be sky *between* two clouds its
// horizontal travel through the layer, `tower / tan θ`, has to stay under about
// one noise tile. At 17.5 degrees that is 3.2 tower-heights. So the tile has to
// be at least three times the tower — and a tile that big is most of the
// visible sky, so the whole composition is one or two cells of the hash. It was
// measured at a 2200 m tower: tiles of 3000 and 3800 m came back as a
// continuous veil, 11000 m put one cloud across half the frame, and the best
// case, 7000 m, gave two or three shelves with a straight diagonal top edge.
// **A slab seen edge-on can only ever give shelves**, and no setting of
// coverage, swell or step density changes that.
//
// So the cumulus here are **not in the world at all**. They are a stylised 2D
// field painted on the dome, which is how a hand-painted sky does it and how
// every stylised game with a ground-level camera does it:
//
//   the projection   `dir.xz / (dir.y + k)`. A plane projection (`dir.xz /
//                    dir.y`, which is what a slab is) sends the scale to
//                    infinity at the horizon and smears everything into
//                    horizontal streaks — the same failure by a different road.
//                    The `+ k` is a paraboloid-ish dome: at k = 0.35 a puff at
//                    8 degrees of elevation is 2.3x the size of the same puff
//                    at the zenith rather than 7x, so a cloud keeps its shape
//                    all the way down to the treeline and still reads as being
//                    further away.
//   the silhouette   domain-warped fbm with two **billow** octaves on top
//                    (`1 - |2n - 1|`, which folds the noise about its middle and
//                    so has creases where plain fbm has smooth minima). The warp
//                    is what stops the puffs being round blobs and the billow is
//                    what gives them cauliflower edges. A soft threshold turns
//                    the field into alpha.
//   the light        two extra taps of the same field: one a short step
//                    **toward the sun**, one a short step **outward from the
//                    zenith**, which on this projection is downward on screen.
//                    Where stepping toward the sun leaves the cloud the point is
//                    a sun-facing shoulder and goes peach to white; where it
//                    goes deeper in, the point is behind something and goes
//                    periwinkle. Where stepping downward leaves the cloud, the
//                    point is a belly. That is a real self-shadow and a real
//                    underside out of a field with no third dimension in it.
//   the rim          `a * (1 - a)` peaks exactly on the silhouette edge; gated
//                    on the sun-facing term it lights the sunward edge only,
//                    which under a low sun is most of what a cumulus is. Under
//                    a high one it is not, which is why `range_sky.tres` turns
//                    `puff_rim` down and `puff_belly` up.
//
// ## Cost, and why it is full resolution
//
// There is no march, so `use_quarter_res_pass` is gone with it and the field is
// evaluated per screen pixel. One evaluation is two 1-octave warp taps, a
// 3-octave fbm and two billow octaves — 7 `value_noise`, 28 `hash12`. Three
// evaluations per layer (centre, sunward, downward) and two layers is **168
// `hash12` per pixel**, about 620 M per frame at 2560x1440. The marched version
// it replaces was 640 per *marched* pixel at quarter resolution, 295 M per
// frame, so this is a little over twice the arithmetic and four times the
// resolution — the edges are actual edges rather than a 640x360 buffer
// magnified four times, which is where the last version's softness came from.
// The radiance cubemap pass drops to one octave and one layer; the ambient term
// only ever wanted the low-frequency colour.
//
// Every colour below carries the `source_color` hint, so a value set from
// `range_sky.tres` is sRGB and converted on the way in while a default written
// *here* is taken as linear. `range_sky.tres` sets every one of them, so the
// defaults are a fallback for a shader opened on its own — do not read a colour
// off this file and expect it on screen.

group_uniforms gradient;
uniform vec3 zenith_color : source_color = vec3(0.1274, 0.1589, 0.3564);
uniform vec3 horizon_color : source_color = vec3(0.9647, 0.3564, 0.1274);
uniform float horizon_falloff : hint_range(0.2, 3.0) = 0.60;
// The rose band. `mid_height` is how far up the dome its centre sits, measured
// in the same `pow(up, horizon_falloff)` coordinate the ramp above runs in, so
// changing the falloff does not slide the band out from under the colour it was
// placed against. `mid_width` is how far it reaches either side before it is
// gone. Twilight runs apricot, then rose, then periwinkle; two stops put the
// rose at the skyline or overhead and never in between.
uniform vec3 mid_color : source_color = vec3(0.8714, 0.2500, 0.2500);
uniform float mid_height : hint_range(0.0, 1.0) = 0.30;
uniform float mid_width : hint_range(0.02, 1.0) = 0.42;
uniform float mid_energy : hint_range(0.0, 1.0) = 0.75;
// The lower hemisphere, and it is not scenery: `range_env.tres` takes 100% of
// its ambient from this dome, so the bottom half of it is the only light
// reaching anything that faces down — the lodge roof over the eight spawn pads
// most of all.
uniform vec3 ground_horizon_color : source_color = vec3(0.5776, 0.4287, 0.2159);
uniform vec3 ground_bottom_color : source_color = vec3(0.1746, 0.1096, 0.0508);
uniform float ground_falloff : hint_range(0.02, 1.0) = 0.16;
uniform float sky_energy : hint_range(0.0, 4.0) = 1.0;

group_uniforms haze;
uniform vec3 haze_color : source_color = vec3(0.8714, 0.8388, 0.7305);
uniform float haze_energy : hint_range(0.0, 2.0) = 0.62;
uniform float haze_band : hint_range(0.02, 0.8) = 0.20;
uniform float haze_power : hint_range(0.5, 8.0) = 2.6;

group_uniforms sun;
// `sun_follow_light` pins the disc and the glory to this map's own `Sun`, so
// what you see in the sky and where the shadows point cannot disagree — and
// **that claim is now checked rather than asserted**. It was asserted for a
// whole pass while the two were sixty degrees apart, because the `Sun` node's
// `Transform3D` had been written as basis columns when a `.tscn` stores rows.
// The sky was right and the light was wrong, the disc followed the light
// faithfully to the wrong place, and no render said so. See
// `range_map._check_sun_and_sky`, which prints the built node's elevation and
// bearing into the build log for the gate to read.
//
// `sun_direction` below is the fallback for when there is no
// `DirectionalLight3D`, and it is kept equal to the Sun's own +Z on purpose:
// the same check compares them.
uniform vec3 sun_direction = vec3(0.49384, 0.15643, -0.85537);
uniform bool sun_follow_light = true;
uniform vec3 sun_color : source_color = vec3(1.0, 0.4793, 0.1468);
uniform float sun_energy : hint_range(0.0, 60.0) = 9.0;
uniform float sun_angular_size : hint_range(0.004, 0.08) = 0.021;
uniform vec3 sun_aureole_color : source_color = vec3(1.0, 0.3763, 0.1046);
uniform float sun_aureole_energy : hint_range(0.0, 4.0) = 0.85;
uniform float sun_aureole_falloff : hint_range(4.0, 600.0) = 100.0;
// The wide one: the whole sun half of the sky is paler than the other half, and
// that asymmetry is most of what stops a gradient reading as a gradient.
uniform float sun_wash : hint_range(0.0, 1.0) = 0.28;

group_uniforms puffs;
// The lit shoulder, the midtone and the shadow. `puff_shadow_color` is the
// belly *and* the far side: at this hour a cumulus out of the sun is lit by the
// violet half of the sky, so its shadow is lavender and not a darker peach.
uniform vec3 puff_sun_color : source_color = vec3(1.0, 0.7379, 0.5029);
uniform vec3 puff_body_color : source_color = vec3(0.9387, 0.3372, 0.3050);
uniform vec3 puff_shadow_color : source_color = vec3(0.1274, 0.1096, 0.3564);
uniform vec3 puff_rim_color : source_color = vec3(1.0, 0.6376, 0.3050);
uniform float puff_energy : hint_range(0.2, 4.0) = 1.4;
// Where the field has to rise to before there is any cloud. This is the map of
// the sky: raise it and the puffs are fewer and further apart.
uniform float puff_coverage : hint_range(0.0, 1.0) = 0.36;
// How wide the alpha ramp at the edge is, in field units. Small is a cut-out;
// large is fog. Cauliflower lives at about a twentieth.
uniform float puff_softness : hint_range(0.005, 0.30) = 0.045;
// Dome units per noise tile. Bigger is more, smaller puffs.
uniform float puff_scale : hint_range(0.2, 8.0) = 1.8;
// The `k` in `dir.xz / (dir.y + k)`. See the header: 0 is a plane projection and
// smears at the horizon, 1 is a hemisphere and flattens the perspective out.
uniform float puff_dome_k : hint_range(0.05, 1.0) = 0.35;
uniform float puff_warp : hint_range(0.0, 2.0) = 0.55;
uniform float puff_warp_scale : hint_range(0.1, 4.0) = 0.65;
// How much of the folded (billow) octaves goes into the silhouette. This is the
// cauliflower knob.
uniform float puff_billow : hint_range(0.0, 1.5) = 0.55;
// How far the shading taps step, in dome units, and how hard their answer is
// read. The light step wants to be about a tenth of a puff; the belly step a
// little more, because an underside is a broader feature than a shoulder.
uniform float puff_light_step : hint_range(0.005, 0.5) = 0.055;
uniform float puff_light : hint_range(0.0, 20.0) = 6.0;
uniform float puff_belly_step : hint_range(0.005, 0.5) = 0.10;
uniform float puff_belly : hint_range(0.0, 1.5) = 0.75;
uniform float puff_rim : hint_range(0.0, 6.0) = 2.0;
uniform float puff_opacity : hint_range(0.0, 1.0) = 1.0;
// Dome units per second. The dome is about 2 units across the visible sky, so
// 0.004 crosses it in about eight minutes.
uniform float puff_drift = 0.004;
uniform float puff_drift_azimuth : hint_range(-3.15, 3.15) = 0.78;
// Which patch of the field is overhead. The field is a fixed function of
// direction and time and the camera sits at its origin, so without this the
// weather is whatever the hash does near (0, 0) and the only other way to change
// it is `puff_scale`, which changes the clouds as well as which ones you get.
uniform vec2 puff_offset = vec2(0.0);
// Below this the puffs dissolve into the haze rather than ending on a line.
uniform float puff_horizon_fade : hint_range(0.0, 0.5) = 0.13;

group_uniforms puffs_small;
// The second layer: the same field at a smaller scale and a different patch,
// which is the scatter of small fair-weather cumulus between and below the big
// ones. Two cheap layers are what give a sky depth; one layer at any coverage
// is one size of cloud everywhere.
uniform float puff2_scale : hint_range(0.0, 6.0) = 2.6;
uniform float puff2_coverage : hint_range(-0.3, 0.3) = 0.03;
uniform vec2 puff2_offset = vec2(0.0);
uniform float puff2_opacity : hint_range(0.0, 1.0) = 0.85;

group_uniforms cirrus;
uniform vec3 cirrus_color : source_color = vec3(1.0, 0.5149, 0.4564);
uniform float cirrus_opacity : hint_range(0.0, 1.0) = 0.10;
uniform float cirrus_coverage : hint_range(0.0, 1.0) = 0.60;
uniform float cirrus_size_m : hint_range(500.0, 20000.0) = 7000.0;
uniform float cirrus_height_m : hint_range(2000.0, 14000.0) = 8000.0;
uniform float cirrus_wind = 26.0;
uniform float cirrus_azimuth : hint_range(-3.15, 3.15) = 1.15;
uniform float cirrus_parallax : hint_range(0.0, 0.02) = 0.0016;


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

float fbm(vec2 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		sum += amp * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return sum;
}

// The noise folded about its middle. Plain value noise has smooth minima and so
// makes rolling hills; folded, the minima become creases and the maxima become
// rounded lobes, which is the difference between a hill and a cauliflower.
float billow(vec2 p) {
	return 1.0 - abs(value_noise(p) * 2.0 - 1.0);
}

vec3 sun_dir() {
	vec3 d = sun_direction;
	if (sun_follow_light && LIGHT0_ENABLED) {
		d = LIGHT0_DIRECTION;
	}
	return normalize(d);
}

// The dome. See the header for why there is a `+ k` in the denominator.
vec2 dome(vec3 dir) {
	return dir.xz / (dir.y + puff_dome_k);
}

// The silhouette field. One evaluation: two 1-octave warp taps, a 3-octave fbm
// and two folded octaves.
float puff_field(vec2 q, int octaves) {
	vec2 w = vec2(fbm(q * puff_warp_scale, 1),
		fbm(q * puff_warp_scale + vec2(31.7, 11.3), 1));
	q += (w - vec2(0.25)) * puff_warp;
	float f = fbm(q, octaves);
	if (octaves > 1) {
		f += (billow(q * 2.3) - 0.5) * puff_billow;
		f += (billow(q * 4.9) - 0.5) * puff_billow * 0.45;
	}
	return f;
}

// One layer of puffs, shaded. Returns premultiplied: .rgb is what to lay over
// the sky, .a is how much of it to cover.
vec4 puff_layer(vec3 dir, vec3 sd, float t, float scale, vec2 off, float cov_bias,
		float opacity, int octaves) {
	if (dir.y <= 0.0) {
		return vec4(0.0);
	}
	vec2 wind = vec2(cos(puff_drift_azimuth), sin(puff_drift_azimuth)) * puff_drift;
	vec2 q = dome(dir) * scale + off + puff_offset + wind * t;
	float cov = puff_coverage + cov_bias;

	float f0 = puff_field(q, octaves);
	float a = smoothstep(cov, cov + puff_softness, f0) * opacity;
	if (a <= 0.002) {
		return vec4(0.0);
	}

	// Toward the sun, on the dome. The sun is nine degrees up, so its light
	// arrives along its compass bearing and a constant 2D direction is both
	// right and stable; a per-pixel direction to the disc would swim.
	vec2 towards = normalize(sd.xz + vec2(1e-4, 0.0));
	float fs = puff_field(q + towards * puff_light_step * scale, octaves);
	// Positive where stepping toward the sun leaves the cloud — a sun-facing
	// shoulder. Negative where it goes further in — behind something.
	float lit = clamp((f0 - fs) * puff_light, -1.0, 1.0);

	// Outward from the zenith is downward on screen, so this is the underside.
	vec2 outward = normalize(q - off - puff_offset - wind * t + vec2(1e-4, 0.0));
	float fb = puff_field(q + outward * puff_belly_step * scale, octaves);
	float under = clamp((f0 - fb) * puff_light, 0.0, 1.0);

	// Wide ramps on purpose. Narrow ones turn the two taps into a stencil with a
	// hard line across every puff; a cumulus has a terminator, not an edge.
	vec3 col = mix(puff_shadow_color, puff_body_color, smoothstep(-0.75, 0.30, lit));
	col = mix(col, puff_sun_color, smoothstep(0.05, 0.95, lit));
	col = mix(col, puff_shadow_color, under * puff_belly);

	// The rim: `a * (1 - a)` peaks on the silhouette edge and nowhere else.
	float rim = a * (1.0 - a) * 4.0 * max(lit, 0.0);
	col += puff_rim_color * rim * puff_rim;

	float fade = smoothstep(0.0, puff_horizon_fade, dir.y);
	a *= fade;
	return vec4(col * puff_energy * a, a);
}


// One high, thin, fast sheet. Stretched hard on one axis, which is the whole of
// what makes a cirrus a cirrus. A plane projection is exactly right for this
// and wrong for a cumulus, for the reason the header gives.
vec4 cirrus(vec3 dir, vec3 cam, float t, int octaves) {
	if (dir.y < 0.0) {
		return vec4(0.0);
	}
	vec2 wind = vec2(cos(cirrus_azimuth), sin(cirrus_azimuth)) * cirrus_wind;
	float up = max(dir.y, 0.035);
	vec2 uv = (dir.xz * (cirrus_height_m / up) + wind * t) / cirrus_size_m
		+ cam.xz * cirrus_parallax;
	float n = fbm(uv * vec2(0.30, 2.4), octaves);
	float cover = smoothstep(cirrus_coverage, cirrus_coverage + 0.22, n) * cirrus_opacity;
	cover *= smoothstep(0.02, 0.30, dir.y);
	return vec4(cirrus_color * cover, cover);
}


void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sd = sun_dir();
	float toward = max(dot(dir, sd), 0.0);
	// The cubemap pass feeds the ambient term, which only ever wanted the
	// low-frequency colour, so it drops to one octave and one layer.
	int octaves = AT_CUBEMAP_PASS ? 1 : 3;

	// --- graded backdrop ---------------------------------------------------
	float up = clamp(dir.y, 0.0, 1.0);
	float down = clamp(-dir.y, 0.0, 1.0);
	float ramp = pow(up, horizon_falloff);
	vec3 col = mix(horizon_color, zenith_color, ramp);
	// The rose band, laid over the two-stop ramp rather than into it: a third
	// `mix` in the chain would have moved the zenith with it.
	col = mix(col, mid_color,
		mid_energy * (1.0 - smoothstep(0.0, mid_width, abs(ramp - mid_height))));
	// The ground half. See `ground_horizon_color`: this is the map's fill light
	// and not scenery.
	col = mix(col, mix(ground_horizon_color, ground_bottom_color,
		pow(down, ground_falloff)), smoothstep(0.0, 0.02, down));

	// The warm skyline, brightest where the sun is.
	float band = 1.0 - clamp(abs(dir.y) / haze_band, 0.0, 1.0);
	col = mix(col, haze_color, pow(band, haze_power) * haze_energy
		* (0.75 + 0.45 * toward));

	// --- sun ---------------------------------------------------------------
	col += sun_aureole_color * pow(toward, sun_aureole_falloff) * sun_aureole_energy;
	col += sun_aureole_color * pow(toward, 7.0) * sun_aureole_energy * sun_wash;
	float ang = acos(clamp(dot(dir, sd), -1.0, 1.0));
	float disc = 1.0 - smoothstep(sun_angular_size * 0.86, sun_angular_size * 1.08, ang);
	col += sun_color * sun_energy * disc;

	// --- cirrus, then the puffs over it ------------------------------------
	vec4 high = cirrus(dir, POSITION, TIME, max(octaves, 1));
	col = col * (1.0 - high.a) + high.rgb;

	vec4 big = puff_layer(dir, sd, TIME, puff_scale, vec2(0.0), 0.0,
		puff_opacity, octaves);
	col = col * (1.0 - big.a) + big.rgb;
	if (!AT_CUBEMAP_PASS && puff2_opacity > 0.001) {
		vec4 small = puff_layer(dir, sd, TIME, puff2_scale, puff2_offset,
			puff2_coverage, puff2_opacity, octaves);
		col = col * (1.0 - small.a) + small.rgb;
	}

	COLOR = col * sky_energy;
}
