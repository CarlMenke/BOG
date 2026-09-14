shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Heat shimmer for Kopje Crossing, and the one thing on this map that no other
// map in the game would ever want.
//
// The map is 96 m of pale sand at noon. Sand at noon does one thing you can see
// from anywhere: the air over it boils, and everything behind it wobbles. That
// is a screen-space refraction, and screen-space refraction is exactly the kind
// of effect that ruins a competitive shooter — a Gub silhouette that wobbles is
// a Gub you cannot lead a spear onto. So the whole design of this is about
// **where it is allowed to be**, not about how it looks.
//
// It lives on a cylinder of radius `SHIMMER_RADIUS` — 120 m — standing outside
// the plateau, whose rim is at 48 m and whose furthest spawn pad is at 44 m.
// Every player, every prop and every spear in the match is therefore *in front
// of* this band from every camera on the map, and the depth test rejects the
// band wherever any of them stands. The only things behind it are the sky and
// the distant ranges, which is exactly what should be wobbling.
//
// It is also confined to a band of altitude around the horizon line, because
// that is where a shimmer is: the layer of hot air is a couple of metres deep
// and you see it stacked up along a shallow sightline, never overhead.
//
// Cost: one open cylinder, 48 segments, two triangles a segment, alpha-blended,
// no shadow, no depth write, one screen-texture fetch and one noise fetch per
// fragment. It covers a thin strip of the frame and nothing else.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D shimmer_noise : filter_linear_mipmap, repeat_enable;

// Screen-space displacement at full strength, as a fraction of the viewport.
// 0.004 is about five pixels at 1280x720 — a wobble you notice on a skyline and
// could not measure on a silhouette even if one were ever behind it.
uniform float shimmer_amount : hint_range(0.0, 0.03) = 0.0042;
// Metres per noise tile on the band, and how fast the cells boil and rise.
uniform float cell_size : hint_range(0.5, 40.0) = 7.0;
uniform float rise_speed : hint_range(0.0, 2.0) = 0.42;
uniform float boil_speed : hint_range(0.0, 2.0) = 0.22;
// The altitude band, in metres either side of `band_centre`, over which the
// shimmer fades in and out. Heat haze hugs the ground.
uniform float band_centre = 1.0;
uniform float band_half = 7.0;
// A touch of the hot air's own colour, added where the shimmer is strongest, so
// the horizon over the sand is a shade paler than the horizon over the rock.
uniform vec4 glare_color : source_color = vec4(0.95, 0.90, 0.78, 1.0);
uniform float glare : hint_range(0.0, 0.6) = 0.10;

varying vec3 world_pos;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	// Fade out above and below the hot layer. Smooth at both ends, or the band
	// announces itself as a rectangle of wobble with a hard edge on it.
	float band = 1.0 - clamp(abs(world_pos.y - band_centre) / band_half, 0.0, 1.0);
	band = band * band;
	if (band <= 0.001) {
		discard;
	}

	// Two noise samples crossing each other: one rising, one boiling in place.
	// Rising alone reads as rain running down a window.
	vec2 p = vec2(atan(world_pos.z, world_pos.x) * 40.0, world_pos.y) / cell_size;
	float a = texture(shimmer_noise, p + vec2(0.0, -TIME * rise_speed)).r - 0.5;
	float b = texture(shimmer_noise, p * 2.3 + vec2(TIME * boil_speed, 0.0)).r - 0.5;
	// Mostly vertical displacement, because a column of rising air shears what
	// is behind it up and down far more than side to side.
	vec2 push = vec2(a * 0.35, a + b * 0.7) * shimmer_amount * band;

	vec2 uv = clamp(SCREEN_UV + push, vec2(0.0), vec2(1.0));
	ALBEDO = texture(screen_texture, uv).rgb;
	ALBEDO = mix(ALBEDO, glare_color.rgb, glare * band);
	// Fully opaque where it is doing anything at all — it is a copy of the
	// screen, so "opaque" here only means "this copy, displaced" — and fully
	// transparent at the edges of the band so it never draws an outline.
	ALPHA = smoothstep(0.0, 0.25, band);
}
