shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled,
	fog_disabled, specular_disabled;

// Heat shimmer — the air over a hot surface, bending what is behind it.
//
// This is the one effect on Rust that belongs to no other map in the game. The
// island is a cold night, the wharf is dusk, the yacht is a sea breeze and the
// savanna is dawn; Rust is the only place where the *ground itself* is hot
// enough to do something to the light coming off it, and that shimmer is most
// of what a photograph of a mid-afternoon industrial yard actually looks like.
//
// It is a screen-space refraction, not a particle: each panel reads the frame
// behind it, offsets the read by a couple of pixels along a wandering field,
// and blends the result back over itself. Two rules keep it from becoming a
// readability bug, which is what heat haze in a shooter usually is:
//
//   * **`strength` is in screen-UV units at the panel's own alpha**, and it is
//     set low enough that a Gub seen through a panel moves by a couple of
//     pixels, not by a silhouette's width. A target that dissolves is a bug;
//     a target whose edge crawls is weather.
//   * **The panels stand over surfaces, not over lanes.** They are placed
//     against the yard's walls and along the container roof line — the places
//     the eye reads as distance — and never across the open ground a fight
//     happens on. `rust_map.gd`'s `SHIMMER` table is where that is decided.
//
// The panel is Y-billboarded in `vertex()`: it turns to face the camera about
// the world up axis but never tips, because hot air rises straight and a panel
// that pitched with the camera would visibly swing when a player looked down.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
/// Peak screen-UV displacement, at the middle of a panel. 0.003 is about four
/// pixels at 1280 wide and eight at 2560, which is the range where an edge
/// crawls and a silhouette does not move.
///
/// Measured cost, from two renders of pad 0 with the panels built and not:
/// they change 0.20% of the frame by more than one step out of 255, and the
/// change is a lift of about 27% on the darkest pixels behind them and nothing
/// at all above about mid grey. That lift is the panel blending the screen back
/// over itself and is not perfectly transparent; at this alpha it reads as the
/// haze it is meant to be rather than as a pane.
uniform float strength : hint_range(0.0, 0.03) = 0.003;
/// How fast the wobble field climbs, in panel-heights per second. Rising air
/// over hot ground moves slowly; this is deliberately under 1.
uniform float rise : hint_range(0.0, 3.0) = 0.55;
/// Cells of wobble across the panel. More is finer and reads as further away.
uniform float cells : hint_range(1.0, 24.0) = 7.0;
/// How much of the panel's height is the fade-out at the top. Hot air thins as
/// it climbs, and a panel with a hard top edge reads as a pane of glass.
uniform float fade_top : hint_range(0.05, 1.0) = 0.62;


void vertex() {
	// Billboard about world up only. The two camera-right and camera-forward
	// axes come out of the inverse view matrix; the model's own second column
	// is kept, so the panel's height and its up direction are whatever
	// `rust_map.gd` gave it.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], MODEL_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}


void fragment() {
	// Two sine fields crossed at different rates. Cheaper than a noise texture
	// and, at this amplitude, indistinguishable from one — the eye is reading
	// motion here, not pattern.
	vec2 p = UV * cells;
	float t = TIME;
	float climb = t * rise;
	float a = sin((p.x + 0.35 * p.y) * 6.2831 + t * 2.3) * cos((p.y - climb) * 4.9 - t * 1.1);
	float b = sin((p.x - p.y * 0.7) * 3.7 - t * 1.6) * sin((p.y - climb * 0.8) * 7.3);

	// Soft everywhere: no edge of the quad may ever be visible as an edge.
	float across = smoothstep(0.0, 0.22, UV.x) * smoothstep(1.0, 0.78, UV.x);
	float up = smoothstep(0.0, 0.10, UV.y) * smoothstep(1.0, 1.0 - fade_top, UV.y);
	float mask = across * up * COLOR.a;

	vec2 offset = vec2(a, b * 0.6) * strength * mask;
	ALBEDO = textureLod(screen_tex, SCREEN_UV + offset, 0.0).rgb;
	ALPHA = mask;
}
