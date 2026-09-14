shader_type spatial;
render_mode cull_disabled;

// A gull's wingbeat, for Halcyon Wake. Gulls over an anchorage do not flap
// steadily — they beat three or four times and then glide for two or three
// seconds — and that rhythm is the whole reason a bird reads as a bird and not
// as a kite. So the cycle is mostly nothing, with a short burst in it.
//
// One gull is one `MeshInstance3D` with its own copy of this material carrying
// its own `phase`, which is what keeps six birds from flapping in unison for
// six draw calls instead of twelve. The path they fly is in
// `yacht_ambience.gd`; only the wings are here.

uniform float phase : hint_range(0.0, 1.0) = 0.0;
/// Seconds per beat-and-glide cycle, as one over.
uniform float cycles_per_second : hint_range(0.05, 2.0) = 0.31;
/// The fraction of the cycle spent beating; the rest is a glide.
uniform float beating : hint_range(0.05, 1.0) = 0.34;
uniform float beats : hint_range(1.0, 8.0) = 3.0;
uniform float throw_up : hint_range(0.0, 1.0) = 0.34;
uniform vec3 back : source_color = vec3(0.86, 0.87, 0.88);
uniform vec3 tip : source_color = vec3(0.16, 0.17, 0.19);

void vertex() {
	// UV.x is 0 at the port wingtip, 0.5 at the body, 1 at the starboard tip.
	float span = abs(UV.x - 0.5) * 2.0;
	float cycle = fract(TIME * cycles_per_second + phase);
	float flap = 0.0;
	if (cycle < beating) {
		flap = sin(cycle / beating * 6.28318530718 * beats);
	}
	// Squared in span, so the shoulder barely moves and the tip does the work.
	VERTEX.y += flap * span * span * throw_up;
	NORMAL = normalize(NORMAL + vec3(0.0, 0.0, flap * span * 0.5));
}

void fragment() {
	// Dark wingtips. It is two pixels at this range and it is the two pixels
	// that make the shape read as a gull rather than as a white dash.
	float span = abs(UV.x - 0.5) * 2.0;
	ALBEDO = mix(back, tip, smoothstep(0.72, 1.0, span));
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
