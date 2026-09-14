shader_type sky;
render_mode use_quarter_res_pass;

// The sky over Rust: a measured photograph with weather put back into it.
//
// The island's sky is painted from nothing — `enchanted_sky.gdshader` invents a
// zenith, a horizon, stars, a moon and an aurora, and it is right to, because
// nothing on Whisperbloom Hollow is photographic. Rust is the opposite: the
// arena is a bought `.glb` with fifty-one photographed textures on it, and the
// thing that made it read as an asset pack under a default sun was that its sky
// was a two-colour ramp while its containers were photographs. So the base here
// is a real 2k CC0 HDR panorama (`assets/hdri/kiara_6_afternoon_2k.hdr`, and see
// the `SOURCES.md` beside it), which also becomes the ambient and the reflection
// term — so every shaded face on the map is lit by the same sky the player is
// looking at, rather than by a guess.
//
// A photograph does not move, and a sky that does not move is the whole reason
// a static dome can end up feeling *more* like a backdrop than the gradient it
// replaced. So three things are drawn over it, and all three are the same
// weather: **dust**.
//
//   haze     a warm band hugging the horizon whose depth breathes over about
//            two minutes. This is the layer doing most of the work — it is what
//            "airless" looks like from inside, and it is what the map's own
//            distance fog is matched to.
//   streaks  thin dust cirrus, drifting on a flat dome so it converges toward
//            the horizon. Ninety seconds to cross, which is the island's number
//            and the right one: slower than that and nobody sees it move,
//            faster and it reads as a screensaver.
//   corona   the aerosol glow round the sun. The panorama's own sun disc is
//            clipped white (the capture is 24 EV and the sun is past the top of
//            it), so the warmth that should surround it has to be put back.
//
// The dome is turned by `sky_yaw_degrees` rather than the map being turned to
// suit it. `rust.tscn`'s `Sun` was authored over the north-west corner so that
// "every container still has a lit face and a dark one", and that judgement is
// worth keeping; what changed is the hour, not the compass. So the panorama's
// own sun — measured at azimuth -138.03 degrees, elevation 36.46 — is rotated
// on to the map's authored azimuth of +51, and the `Sun` node's elevation is
// dropped from 50 to the panorama's 36.46. After that the shadows on the ground
// and the bright spot in the sky are the same sun, which is not something a
// gradient sky ever had to be true about.

// The panorama. No `source_color`: the `.hdr` imports as linear float data and
// the sRGB decode that hint asks for would be a second gamma on top.
uniform sampler2D panorama : filter_linear, hint_default_black;
uniform float panorama_energy : hint_range(0.0, 4.0) = 1.0;
/// Degrees of yaw applied to the dome. Positive turns the panorama's content
/// anticlockwise seen from above, which is to say it *increases* the map-space
/// azimuth of everything in it.
uniform float sky_yaw_degrees : hint_range(-180.0, 180.0) = 0.0;
/// Where the panorama's own sun is, in the panorama's own unrotated frame.
/// Measured off the file, not read off the web page — see `SOURCES.md`.
uniform vec3 sun_panorama_dir = vec3(-0.53784, 0.59423, -0.59801);
uniform float sky_energy : hint_range(0.0, 4.0) = 1.0;

// --- haze ------------------------------------------------------------------
// Declared in LINEAR space, like `enchanted_sky.gdshader`'s, so the defaults
// here and the sRGB values the `.tres` writes back through `source_color` agree.
uniform vec3 haze_color : source_color = vec3(0.5647, 0.4397, 0.2874);
uniform float haze_energy : hint_range(0.0, 2.0) = 0.55;
/// How far up the dome the haze reaches, as a fraction of the way to the zenith.
uniform float haze_height : hint_range(0.02, 1.0) = 0.22;
/// How much of the haze's depth is the slow breathing rather than a constant.
uniform float haze_breath : hint_range(0.0, 1.0) = 0.35;
uniform float haze_breath_speed : hint_range(0.0, 0.2) = 0.008;

// --- dust streaks ----------------------------------------------------------
uniform vec3 streak_color : source_color = vec3(0.6795, 0.6105, 0.4970);
uniform vec3 streak_lit_color : source_color = vec3(1.0, 0.9387, 0.7605);
uniform float streak_opacity : hint_range(0.0, 1.0) = 0.30;
uniform float streak_coverage : hint_range(0.0, 1.0) = 0.52;
uniform float streak_scale : hint_range(0.2, 8.0) = 1.15;
uniform float streak_speed : hint_range(0.0, 0.2) = 0.011;
uniform float streak_horizon_fade : hint_range(0.0, 0.6) = 0.10;
/// The streaks sit on a finite dome, so crossing the 64 m yard slides them a
/// hair. Small, but it is the difference between a dome and a ceiling.
uniform float streak_parallax : hint_range(0.0, 0.01) = 0.0009;

// --- sun corona ------------------------------------------------------------
uniform vec3 corona_color : source_color = vec3(1.0, 0.7605, 0.4397);
uniform float corona_energy : hint_range(0.0, 8.0) = 1.6;
/// Two lobes: a tight one that is the glare off the disc, and a wide one that
/// is the whole quarter of the sky going pale because the air is full of dust.
uniform float corona_tight : hint_range(4.0, 800.0) = 240.0;
uniform float corona_wide : hint_range(1.0, 40.0) = 5.5;
uniform float corona_wide_mix : hint_range(0.0, 1.0) = 0.22;


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

/// Turn `v` about the world up axis. Compass bearing — `atan(v.x, v.z)` — comes
/// out *decreased* by `a`, which is the identity the yaw above is solved from.
vec3 rot_y(vec3 v, float a) {
	float s = sin(a);
	float c = cos(a);
	return vec3(c * v.x - s * v.z, v.y, s * v.x + c * v.z);
}

vec2 panorama_uv(vec3 d) {
	// Godot's own panorama mapping, from `sky.glsl`: u round from atan(x, z),
	// v down from acos(y). Matching it exactly is what lets the measured sun
	// direction in `SOURCES.md` mean anything.
	float u = atan(d.x, d.z) / (2.0 * PI);
	return vec2(fract(u), acos(clamp(d.y, -1.0, 1.0)) / PI);
}

/// The drifting dust cirrus, premultiplied: `.rgb` is what to add, `.a` is how
/// much of the sky behind it to cover. Composites as `sky * (1 - a) + rgb`.
vec4 streaks(vec3 dir, vec3 sun, vec3 cam_pos, float time, int octaves) {
	// Flat-dome projection, so a streak overhead is short and one near the
	// horizon is stretched out to nothing — which is what makes a layer of
	// cloud read as a layer rather than as wallpaper.
	float dome = max(dir.y + 0.12, 0.05);
	vec2 uv = dir.xz / dome * streak_scale;
	uv += cam_pos.xz * streak_parallax;
	uv += vec2(time * streak_speed, time * streak_speed * 0.35);
	// Squashed hard on one axis: dust cirrus is drawn out along the wind, and
	// round fbm blobs would read as cumulus over a desert, which is wrong
	// weather for a map whose whole argument is that the air is dry.
	vec2 wuv = uv * vec2(0.30, 2.4);
	float n = fbm(wuv, octaves);
	float erode = fbm(wuv * 3.1 - vec2(time * streak_speed * 2.2, 0.0), max(octaves - 1, 1));
	n = n * 1.3 - erode * 0.55;
	float cover = smoothstep(streak_coverage, streak_coverage + 0.22, n);
	cover *= smoothstep(streak_horizon_fade * 0.15, streak_horizon_fade + 0.20, dir.y);
	// Thinner overhead: the zenith is the one part of this sky that is a deep
	// clean blue, and it is the only colour on the map that is not dust.
	cover *= 1.0 - 0.55 * smoothstep(0.55, 1.0, dir.y);
	cover *= streak_opacity;

	float sun_cos = max(dot(dir, sun), 0.0);
	vec3 lit = mix(streak_color, streak_lit_color, pow(sun_cos, 4.0));
	return vec4(lit * cover, cover);
}


void sky() {
	vec3 dir = normalize(EYEDIR);
	float yaw = radians(sky_yaw_degrees);
	// The dome is turned one way and the sun that lives in it the other, so the
	// corona and the photograph's own glare are always the same object.
	vec3 sun = normalize(rot_y(sun_panorama_dir, yaw));

	if (AT_QUARTER_RES_PASS) {
		// Three octaves at a quarter of the screen, which is still cheaper than
		// one octave at full res, and quarter-res blur is free art direction on
		// something that is meant to be suspended dust.
		vec4 s = streaks(dir, sun, POSITION, TIME, 3);
		COLOR = s.rgb;
		ALPHA = s.a;
	} else {
		vec3 col = texture(panorama, panorama_uv(rot_y(dir, -yaw))).rgb * panorama_energy;

		// --- haze ----------------------------------------------------------
		// A band hugging the horizon, above and below it, that lifts the sky
		// toward a warm grey and takes the contrast out of the far mountains
		// the panorama has in it. The breathing is one slow noise walk, not a
		// sine: a sine has a period the eye finds and then stops believing.
		float band = exp(-max(abs(dir.y), 0.0) / max(haze_height, 0.001));
		float breath = fbm(vec2(TIME * haze_breath_speed, 4.2), 2);
		band *= mix(1.0, 0.45 + 1.1 * breath, haze_breath);
		col = mix(col, haze_color * haze_energy * 3.0, clamp(band * haze_energy, 0.0, 0.92));

		// --- corona --------------------------------------------------------
		float sun_cos = max(dot(dir, sun), 0.0);
		float tight = pow(sun_cos, corona_tight);
		float wide = pow(sun_cos, corona_wide);
		col += corona_color * corona_energy * (tight + wide * corona_wide_mix);

		// --- dust streaks from the quarter-res buffer -----------------------
		// The cubemap pass has no sub-res buffer to read, so it recomputes a
		// one-octave version; the ambient term only wants the low-frequency
		// colour out of this anyway.
		vec4 s = QUARTER_RES_COLOR;
		if (AT_CUBEMAP_PASS) {
			s = streaks(dir, sun, POSITION, TIME, 1);
		}
		col = col * (1.0 - s.a) + s.rgb;

		COLOR = col * sky_energy;
	}
}
