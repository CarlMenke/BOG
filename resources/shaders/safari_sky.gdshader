shader_type sky;
render_mode use_quarter_res_pass;

// Noon sky for Kopje Crossing.
//
// Started as `enchanted_sky.gdshader` and kept its architecture — the
// quarter-res pass for the soft low-frequency half, the hash/value-noise/fbm
// kernel, the `LIGHT0` follow so the disc sits on the map's own Sun — and threw
// out everything that belongs to a night: stars, the galactic band, the aurora,
// the moon phase and the mare. What replaced them is the one thing a savanna
// sky has and the island's does not, which is **towering cumulus**.
//
// Why a copy rather than the island's shader with different numbers: the
// island's clouds are a single flat dome layer with the noise domain squashed
// 0.45 x 1.8, which is exactly right for wisps and cannot make a tower. Nor can
// any number of flat layers stacked on each other: a ray five degrees above the
// horizon climbs a kilometre and a half over a hundred and sixty kilometres of
// ground, so each plane samples a completely unrelated patch of noise and the
// result is a horizontal smear. That was built first and it is exactly what it
// looked like.
//
// What is here instead is a **column field, marched**. Cloud is a heightfield:
// over every point on the ground stands a column on one flat base at
// `cloud_base_m`, as tall as the noise there rises above `cloud_coverage`. The
// march walks the view ray through that layer and asks at each step whether it
// is inside a column. Near the horizon it grazes the *sides* of distant towers,
// which is why they stand up instead of lying down; overhead it cuts through
// their tops. Flat bases, boiling tops and vertical silhouettes all fall out of
// the heightfield instead of being painted on.
//
// Cost. The march is quarter-res only; the full-res pass reads the composited
// buffer and never evaluates a single octave of noise. Ten steps at three
// octaves plus a shadow tap is about forty value-noise lookups per quarter-res
// pixel, and at 1280x720 that is 320x180 pixels of it. The radiance cubemap
// pass has no sub-res buffer to read, so it recomputes at four steps and one
// octave — the ambient term only ever wanted the low-frequency colour.
//
// Every colour below carries the `source_color` hint, which means a value set
// from `safari_sky.tres` is sRGB and converted on the way in, while a default
// written *here* is taken as linear. `safari_sky.tres` sets every one of them,
// so the defaults below are a fallback for a shader opened on its own and
// nothing else — do not read a colour off this file and expect it on screen.

group_uniforms gradient;
// The upper hemisphere. Deep at the zenith because there are 96 m of pale sand
// under it and the map needs one cold thing to measure the heat against.
uniform vec3 zenith_color : source_color = vec3(0.0648, 0.2232, 0.7305);
uniform vec3 horizon_color : source_color = vec3(0.7605, 0.6795, 0.4970);
uniform float horizon_falloff : hint_range(0.2, 3.0) = 0.60;
// The lower hemisphere, and the reason this shader cannot just be a gradient
// with clouds painted on it: `safari_env.tres` takes its ambient light from the
// sky, so the bottom half of this dome *is* the bounce light off the sand. It
// was pale in the `ProceduralSkyMaterial` this replaced for exactly that
// reason — with a darker ground half the shaded side of every rock goes blue,
// which is the one thing that stops a savanna reading as hot — and it is the
// same pale here, to within a rounding error, so the map's measured exposure
// did not have to move.
uniform vec3 ground_horizon_color : source_color = vec3(0.5776, 0.4287, 0.2159);
uniform vec3 ground_bottom_color : source_color = vec3(0.1746, 0.1096, 0.0508);
uniform float ground_falloff : hint_range(0.02, 1.0) = 0.16;
uniform float sky_energy : hint_range(0.0, 4.0) = 1.0;

group_uniforms haze;
// The hot band. Not fog — `safari_env.tres` owns the fog that sits on the map —
// but the white-out where 40 km of heated air stacks up on the skyline, which
// is what the distant ranges have to fade into for the drop off the cliff to
// go anywhere.
uniform vec3 haze_color : source_color = vec3(0.8714, 0.8388, 0.7305);
uniform float haze_energy : hint_range(0.0, 2.0) = 0.62;
uniform float haze_band : hint_range(0.02, 0.8) = 0.20;
uniform float haze_power : hint_range(0.5, 8.0) = 2.6;

group_uniforms sun;
// Used only when `sun_follow_light` is off or there is no DirectionalLight3D.
uniform vec3 sun_direction = vec3(0.31, 0.899, 0.31);
uniform bool sun_follow_light = true;
uniform vec3 sun_color : source_color = vec3(1.0, 0.9387, 0.7605);
uniform float sun_energy : hint_range(0.0, 60.0) = 22.0;
// 0.0093 rad is the real sun. A hair wider, because at 64 degrees of elevation
// the disc is only ever glimpsed and a half-degree dot reads as a dead pixel.
uniform float sun_angular_size : hint_range(0.004, 0.08) = 0.016;
uniform vec3 sun_aureole_color : source_color = vec3(1.0, 0.8714, 0.6376);
uniform float sun_aureole_energy : hint_range(0.0, 4.0) = 0.85;
uniform float sun_aureole_falloff : hint_range(4.0, 600.0) = 190.0;
// The wide one: the whole sun half of the sky is paler than the other half, and
// that asymmetry is most of what stops a gradient reading as a gradient.
uniform float sun_wash : hint_range(0.0, 1.0) = 0.30;

group_uniforms cumulus;
uniform vec3 cloud_sun_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_body_color : source_color = vec3(0.7305, 0.7681, 0.8714);
uniform vec3 cloud_base_color : source_color = vec3(0.1620, 0.1845, 0.2918);
// Where the field has to rise to before there is any cloud at all. This is the
// map of the sky: raise it and the towers are fewer and further apart.
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.44;
// Metres of cloud per unit of field above `cloud_coverage`. The tower — the
// difference between a 300 m fair-weather puff and a two-kilometre anvil.
uniform float cloud_tower_m : hint_range(200.0, 6000.0) = 2600.0;
// How far above `cloud_coverage` the field has to climb for a column to reach
// its full height. Small and every cloud is a spike, because the column height
// is then proportional to a noise peak; large and the field saturates, most of
// the mass reaches most of the way up, and the silhouette domes over. A cumulus
// is a dome, so this is large.
uniform float cloud_swell : hint_range(0.02, 0.6) = 0.26;
uniform float cloud_softness : hint_range(0.005, 0.3) = 0.055;
// Multiplies the three cloud colours. The sunlit shoulder of a cumulus at noon
// is brighter than white paper and has to be over 1.0 to survive the filmic
// tonemap in `safari_env.tres` as white rather than as grey.
uniform float cloud_energy : hint_range(0.2, 4.0) = 1.7;
// Per-step opacity. Ten steps all inside a column reach 0.98 at 0.32.
uniform float cloud_step_density : hint_range(0.05, 1.0) = 0.32;
// Metres. A fair-weather cumulus base over a hot plain sits around a kilometre
// up, and it is flat because that is the height the rising air reaches
// saturation at — every cloud in the sky shares it, which is most of what makes
// a sky like this read as one weather system rather than as scattered props.
uniform float cloud_base_m : hint_range(200.0, 3000.0) = 980.0;
// Metres across one noise tile — the width of a cloud, near enough. 2200 m puts
// four or five towers across the visible sky, which is about how many you can
// count in a photograph of this weather.
uniform float cloud_size_m : hint_range(200.0, 12000.0) = 2200.0;
// Metres per second of drift. 7 m/s is a real trade wind and takes a tower
// about four minutes to cross the sky: slow enough to be weather, fast enough
// that a player waiting out a respawn can see it happen.
uniform float cloud_wind = 7.0;
uniform float cloud_wind_azimuth : hint_range(-3.15, 3.15) = 0.78;
uniform float cloud_shadow : hint_range(0.0, 1.0) = 0.7;
// How far out to keep marching, in metres. Past this the layer has gone under
// the horizon and the lookups are only making aliasing.
uniform float cloud_reach_m : hint_range(4000.0, 200000.0) = 60000.0;
uniform float cloud_horizon_fade : hint_range(0.0, 0.5) = 0.02;

group_uniforms cirrus;
uniform vec3 cirrus_color : source_color = vec3(1.0, 0.9911, 0.9387);
uniform float cirrus_opacity : hint_range(0.0, 1.0) = 0.26;
uniform float cirrus_coverage : hint_range(0.0, 1.0) = 0.54;
uniform float cirrus_size_m : hint_range(500.0, 20000.0) = 7000.0;
uniform float cirrus_height_m : hint_range(2000.0, 14000.0) = 8000.0;
uniform float cirrus_wind = 26.0;
uniform float cirrus_azimuth : hint_range(-3.15, 3.15) = 1.15;

// Clouds sit on a finite slab, so crossing 96 m of plateau should slide them a
// hair. It is a small number and it is the difference between a sky painted on
// the inside of a ball and a sky with somewhere to be.
uniform float cloud_parallax : hint_range(0.0, 0.02) = 0.0016;


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

vec3 sun_dir() {
	vec3 d = sun_direction;
	if (sun_follow_light && LIGHT0_ENABLED) {
		d = LIGHT0_DIRECTION;
	}
	return normalize(d);
}

// Where a ray pointed at `dir` punches through a horizontal plane `metres` up,
// in noise tiles, with the wind and the parallax already in it. Only the cirrus
// uses this: a cirrus sheet really is one flat layer, so the plane projection
// that ruins a cumulus is exactly right for it.
vec2 sheet_uv(vec3 dir, vec3 cam, float metres, float size, vec2 wind, float t) {
	float up = max(dir.y, 0.035);
	vec2 hit = dir.xz * (metres / up);
	return (hit + wind * t) / size + cam.xz * cloud_parallax;
}


// The cumulus layer, marched through as a heightfield of columns. See the
// header for why it is not a stack of planes.
//
// Returns premultiplied: .rgb is what to add over the sky, .a is how much of it
// to cover.
vec4 cumulus(vec3 dir, vec3 cam, float t, int octaves, int steps) {
	// Below the horizon there is nothing: the layer is over the plain, not under
	// it, and the plain is what the bottom of this dome is pretending to be.
	if (dir.y <= 0.001) {
		return vec4(0.0);
	}
	vec3 sd = sun_dir();
	vec2 wind = vec2(cos(cloud_wind_azimuth), sin(cloud_wind_azimuth)) * cloud_wind;
	vec2 drift = (wind * t) / cloud_size_m + cam.xz * cloud_parallax;
	// A third of a cloud-width toward the sun, for the self-shadow tap.
	vec2 toward_sun = normalize(sd.xz + vec2(0.0001, 0.0)) * 0.30;

	// The stretch of the ray that is inside the layer. Near the horizon that is
	// tens of kilometres of it, which is the whole point — and also why it has to
	// be capped, or the far end of the march samples a hundred noise tiles inside
	// one pixel and turns into static.
	float top_m = cloud_base_m + cloud_tower_m;
	float near_t = cloud_base_m / dir.y;
	float far_t = min(top_m / dir.y, cloud_reach_m);
	if (far_t <= near_t) {
		return vec4(0.0);
	}
	// Geometric spacing, so the steps bunch up where the cloud is near and the
	// detail is, and stretch out where it is a smudge on the skyline anyway.
	float ratio = far_t / near_t;
	// Dither the march, or the steps show as concentric shells across every
	// tower — twelve of them, and perfectly visible. The offset is hashed from
	// the *direction*, not from the screen, so the dither is nailed to the sky
	// and does not crawl when the camera turns; the quarter-res pass then
	// resolves it as grain rather than as banding.
	// Only most of a step: at a full step the dither itself shows, because the
	// quarter-res buffer is magnified four times on the way back up and what was
	// grain at 320x180 is a speckled fringe at 1280x720.
	float jitter = 0.5 + (hash12(dir.xy * 1837.0 + dir.zz * 971.0) - 0.5) * 0.8;

	vec3 acc_rgb = vec3(0.0);
	float acc_a = 0.0;

	for (int i = 0; i < steps; i++) {
		float f = (float(i) + jitter) / float(steps);
		float dist = near_t * pow(ratio, f);
		vec3 p = dir * dist;
		vec2 uv = p.xz / cloud_size_m + drift;

		// Detail falls off with distance, and it has to. A step twenty
		// kilometres out crosses several noise tiles inside one quarter-res
		// pixel, and the high-frequency erode term there is not detail, it is
		// static — it was the speckled fringe on every far cloud. So the erode
		// fades out and the coverage edge softens as the march runs away, which
		// is also, conveniently, what distance does to a cloud.
		float lod = clamp(1.0 - dist / cloud_reach_m, 0.0, 1.0);
		float soft = cloud_softness * (1.0 + (1.0 - lod) * 1.6);

		float n = fbm(uv, octaves);
		// A faster second field eaten out of the first. Without it the columns
		// close into circles; with it they tatter, which is what a cumulus edge
		// does as it mixes with the dry air around it.
		float erode = fbm(uv * 2.7 + vec2(t * 0.004, 0.0), max(octaves - 1, 1));
		n = n * 1.30 - erode * 0.42 * lod;

		// How tall the column standing here is, and how far up it this step is.
		// See `cloud_swell`: the field is saturated and then curved, so the mass
		// domes over instead of coming to a point.
		float swell = smoothstep(cloud_coverage, cloud_coverage + cloud_swell, n);
		float lift = pow(swell, 0.6) * cloud_tower_m;
		float local = (p.y - cloud_base_m) / max(lift, 1.0);
		if (local < 0.0 || local > 1.0) {
			continue;
		}
		// Hard at the base, because a cumulus base is a flat shelf and reads as
		// one, and soft at the top, where it is boiling.
		float d = smoothstep(cloud_coverage, cloud_coverage + soft, n);
		d *= smoothstep(1.0, 0.70, local);
		d *= cloud_step_density;
		if (d <= 0.0) {
			continue;
		}

		// Shading. Height in the column is most of it — the top of a cumulus is
		// white and its base is a grey-blue shelf — and one tap toward the sun
		// says whether this bit is standing in the shade of the bit beside it.
		float occl = smoothstep(cloud_coverage, cloud_coverage + soft,
			fbm(uv + toward_sun, max(octaves - 1, 1)) * 1.30);
		vec3 col = mix(cloud_base_color, cloud_body_color, smoothstep(0.0, 0.5, local));
		col = mix(col, cloud_sun_color, smoothstep(0.38, 0.95, local));
		col = mix(col, col * (1.0 - cloud_shadow * 0.55), occl * cloud_shadow);

		acc_rgb += col * cloud_energy * d * (1.0 - acc_a);
		acc_a += d * (1.0 - acc_a);
	}

	// Silver lining: the thin edge of a cloud in front of the sun is brighter
	// than the sun-facing face of a thick one. Keyed on how *little* alpha there
	// is, so it only ever lights the rim.
	float toward = max(dot(dir, sd), 0.0);
	acc_rgb += cloud_sun_color * cloud_energy * pow(toward, 5.0)
		* (1.0 - acc_a) * acc_a * 1.6;

	float fade = smoothstep(0.0, cloud_horizon_fade + 0.03, dir.y);
	return vec4(acc_rgb * fade, acc_a * fade);
}


// One high, thin, fast sheet. Stretched hard on one axis, which is the whole of
// what makes a cirrus a cirrus.
vec4 cirrus(vec3 dir, vec3 cam, float t, int octaves) {
	if (dir.y < 0.0) {
		return vec4(0.0);
	}
	vec2 wind = vec2(cos(cirrus_azimuth), sin(cirrus_azimuth)) * cirrus_wind;
	vec2 uv = sheet_uv(dir, cam, cirrus_height_m, cirrus_size_m, wind, t);
	float n = fbm(uv * vec2(0.30, 2.4), octaves);
	float cover = smoothstep(cirrus_coverage, cirrus_coverage + 0.22, n) * cirrus_opacity;
	cover *= smoothstep(0.02, 0.30, dir.y);
	return vec4(cirrus_color * cover, cover);
}


void sky() {
	vec3 dir = normalize(EYEDIR);

	// Godot forbids an early `return` from sky(), so the two passes are an
	// if/else rather than a guard clause.
	if (AT_QUARTER_RES_PASS) {
		vec4 high = cirrus(dir, POSITION, TIME, 3);
		vec4 low = cumulus(dir, POSITION, TIME, 3, 12);
		// Cirrus is above the cumulus, so the cumulus covers it.
		vec3 rgb = low.rgb + high.rgb * (1.0 - low.a);
		float a = low.a + high.a * (1.0 - low.a);
		COLOR = rgb;
		ALPHA = a;
	} else {
		// --- graded backdrop -----------------------------------------------
		float up = clamp(dir.y, 0.0, 1.0);
		float down = clamp(-dir.y, 0.0, 1.0);
		vec3 col = mix(horizon_color, zenith_color, pow(up, horizon_falloff));
		// The sand half. See `ground_horizon_color`: this is the map's bounce
		// light and not scenery.
		col = mix(col, mix(ground_horizon_color, ground_bottom_color,
			pow(down, ground_falloff)), smoothstep(0.0, 0.02, down));

		vec3 sd = sun_dir();
		float toward = max(dot(dir, sd), 0.0);

		// The hot skyline, brightest where the sun is.
		float band = 1.0 - clamp(abs(dir.y) / haze_band, 0.0, 1.0);
		col = mix(col, haze_color, pow(band, haze_power) * haze_energy
			* (0.75 + 0.45 * toward));

		// --- sun -----------------------------------------------------------
		// Aureole under the disc, so the disc sits inside its own glare.
		col += sun_aureole_color * pow(toward, sun_aureole_falloff) * sun_aureole_energy;
		col += sun_aureole_color * pow(toward, 7.0) * sun_aureole_energy * sun_wash;

		float ang = acos(clamp(dot(dir, sd), -1.0, 1.0));
		float disc = 1.0 - smoothstep(sun_angular_size * 0.86, sun_angular_size * 1.08, ang);
		col += sun_color * sun_energy * disc;

		// --- clouds from the quarter-res buffer -----------------------------
		// The cubemap pass has no sub-res buffer to read, so it recomputes a
		// two-slice, one-octave version. That is enough for the ambient term,
		// which only ever wanted to know that there is something pale up there.
		vec4 v = QUARTER_RES_COLOR;
		if (AT_CUBEMAP_PASS) {
			vec4 high = cirrus(dir, POSITION, TIME, 1);
			vec4 low = cumulus(dir, POSITION, TIME, 1, 4);
			v = vec4(low.rgb + high.rgb * (1.0 - low.a), low.a + high.a * (1.0 - low.a));
		}
		col = col * (1.0 - v.a) + v.rgb;

		COLOR = col * sky_energy;
	}
}
