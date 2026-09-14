shader_type spatial;
render_mode cull_disabled;

// Cloth in wind, for the ensign at Halcyon Wake's transom and the burgee at her
// masthead. A yacht at anchor lies head to wind, and a flag is the only honest
// way to say which way the wind is going on a map where nothing else can move:
// the swell in `yacht_sea.gdshader` runs bow to stern, and so does this.
//
// The mesh is a flat quad subdivided along its length, held at UV.x = 0 (the
// hoist) and free at UV.x = 1 (the fly). The travelling wave is squared in u so
// the hoist is pinned and the fly cracks — which is what the eye reads as cloth
// rather than as a waving rectangle — and a second, slower wave on a different
// axis stops the whole thing from being one flat ripple.
//
// Cost: two sines per vertex on two flags of 48 vertices each. It is free, and
// it is the cheapest motion on this map.

uniform float flap_speed : hint_range(0.0, 20.0) = 5.5;
uniform float flap_amount : hint_range(0.0, 1.0) = 0.16;
uniform float droop : hint_range(0.0, 1.0) = 0.10;
uniform sampler2D pattern : source_color, filter_linear_mipmap;
/// The flag's length in metres, so the wave's slope — and therefore its normal
/// — comes out right whatever size the flag is.
uniform float flag_length = 1.6;

void vertex() {
	float u = UV.x;
	float grip = u * u;
	float phase = u * 11.0 - TIME * flap_speed;
	VERTEX.z += sin(phase) * flap_amount * grip;
	VERTEX.y += sin(u * 7.0 - TIME * flap_speed * 0.77) * flap_amount * 0.45 * grip;
	// A flag never flies level: it falls away from the staff under its own
	// weight, more the further out you go.
	VERTEX.y -= droop * grip;
	// The normal has to follow the wave or the cloth lights like a sheet of
	// card. The quad is built in its own XY plane facing +Z, so the only slope
	// that matters is d(z)/d(x).
	float slope = cos(phase) * flap_amount * 11.0 * grip / max(flag_length, 0.01);
	NORMAL = normalize(vec3(-slope, 0.0, 1.0));
}

void fragment() {
	vec4 c = texture(pattern, UV);
	ALBEDO = c.rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
}
