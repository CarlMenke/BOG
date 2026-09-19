shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// The dashed ribbon that points at the letter.
//
// The strip itself is built on the CPU by `scripts/world/nav/guide_line.gd` —
// camera-facing quads along the smoothed path — and it arrives here with two
// things baked into its vertices: UV.x is **metres travelled along the route**,
// and the vertex colour's alpha is the head and tail fade, so the line grows
// out of the player's feet instead of starting at a hard edge under the camera.
//
// Everything else is here, because it is all a function of that one coordinate.
// Dashes are cut in metres rather than in UV, which is why a long route and a
// short one have the same dash and not the same number of dashes; they scroll
// toward the target, which is the whole reason the line reads as a direction
// and not as a decoration.
//
// Unshaded and depth-write-off on purpose: this is a HUD element that happens
// to live in the world, and a torch changing its colour would make it look like
// something you could pick up.
//
// **Two passes share this shader.** The depth-tested one is this file as it
// stands; the x-ray pass behind walls is the same code with
// `depth_test_disabled` added to the render mode, which a material cannot
// switch at runtime — `guide_line.gd` makes it by editing the line above. If
// that render-mode line is ever reworded, reword its copy there too.

uniform vec3 line_colour : source_color = vec3(1.0, 0.84, 0.26);
/// The pass's own opacity: 0.85 in front of the world, 0.18 through it.
uniform float line_alpha : hint_range(0.0, 1.0) = 0.85;
/// The whole line's fade — hysteresis near the target, and half for a branch
/// that has left the shared trunk.
uniform float fade : hint_range(0.0, 1.0) = 1.0;

/// Metres of dash and how much of one is lit. 1.2 m at a run is about three
/// dashes a second going past, which reads as movement without flickering.
uniform float dash_length : hint_range(0.2, 6.0) = 1.2;
uniform float dash_duty : hint_range(0.05, 1.0) = 0.5;
/// Metres per second the pattern travels, toward the target.
uniform float scroll_speed = 2.5;
/// How far a dash takes to turn on, in metres. Hard edges alias badly at the
/// grazing angles a line on the ground is mostly seen at.
uniform float soft_edge : hint_range(0.0, 0.5) = 0.08;

void fragment() {
	float pattern = fract((UV.x - TIME * scroll_speed) / dash_length);
	// The soft edge is stated in metres and used in pattern units, so a change
	// to `dash_length` does not also change how sharp the dashes are.
	float edge = clamp(soft_edge / dash_length, 0.001, 0.45);
	float lit = smoothstep(0.0, edge, pattern)
		* (1.0 - smoothstep(dash_duty - edge, dash_duty, pattern));
	ALBEDO = line_colour;
	ALPHA = clamp(COLOR.a * lit * line_alpha * fade, 0.0, 1.0);
}
