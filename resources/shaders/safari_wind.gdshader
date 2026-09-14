shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

// Ground cover that moves, for Kopje Crossing. Grass, bushes, and anything else
// rooted in the sand that a hot wind would lean on.
//
// This exists for two reasons, and the second one is the one a
// `StandardMaterial3D` could never do.
//
// **It sways.** Three thousand grass tufts on a 96 m plateau are most of the
// ground plane, and three thousand *still* grass tufts are what make a savanna
// read as a model of a savanna. The sway is a vertex displacement keyed on the
// world position of the tuft, so every tuft has its own phase and the field
// moves as a wave crossing the map rather than as one object breathing. No CPU
// work, no per-instance data, no change to the multimesh: the whole thing is
// six lines in `vertex()`, and the cost of a vertex shader on geometry that is
// already being drawn is nothing anyone can measure.
//
// **It dries the grass out.** The MegaKit ships one 512 px `Grass.png` atlas
// and the tufts take their colour from wherever they land in it — some of it
// green, some of it straw. `safari_map.gd` was tinting that with
// `albedo_color`, and a multiply can darken a channel but never remove one, so
// the emerald blades stayed emerald and a dry-season savanna had spring grass
// scattered through it. `dryness` pulls the sample toward its own luminance
// first and *then* tints, which turns green into straw instead of into dark
// green. That is the one knob here that is about the map and not about the
// weather.
//
// Alpha: this is an alpha *scissor*, not alpha blending — `ALPHA_SCISSOR_THRESHOLD`
// keeps the geometry in the opaque pass, which is what lets three thousand
// tufts and forty canopies sort against each other for free and cast the
// shadows they already cast. The grass atlas is fully opaque, so the scissor is
// a no-op on it; the leaf cards are not, which is why it is here at all.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 0.84, 0.42, 1.0);
// 0 keeps the atlas as painted, 1 is a greyscale card wearing `tint`.
uniform float dryness : hint_range(0.0, 1.0) = 0.7;
uniform float roughness_value : hint_range(0.0, 1.0) = 1.0;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.45;

// Metres of lean at the tip, at full gust. A blade of grass bends a hand's
// breadth in a breeze; more than that and it reads as underwater weed.
uniform float sway_metres : hint_range(0.0, 1.0) = 0.16;
// Radians per second of the carrier. 1.1 is a lazy hot-afternoon wind.
uniform float sway_speed : hint_range(0.0, 6.0) = 1.1;
// Metres per radian of phase across the ground: how long the wave crossing the
// field is. 9 m is short enough to see the gust travel across 96 m of plateau
// and long enough that neighbouring tufts still agree with each other.
uniform float sway_wavelength : hint_range(1.0, 60.0) = 9.0;
uniform vec2 sway_direction = vec2(0.82, 0.57);
// How much of the sway is a second, faster, cross-grained flutter. Pure
// sinusoid reads as a metronome.
uniform float sway_flutter : hint_range(0.0, 1.0) = 0.35;
// Metres above the tuft's root at which the lean reaches full. Below it the
// blade is stiffer, which is what keeps the roots planted.
uniform float sway_height : hint_range(0.05, 4.0) = 0.55;


void vertex() {
	// `world_vertex_coords` means VERTEX is already in world space, so the
	// tuft's own position comes out of the model matrix and the wave phase can
	// be read straight off the ground.
	vec3 root = MODEL_MATRIX[3].xyz;
	float along = dot(root.xz, normalize(sway_direction)) / sway_wavelength;
	float phase = TIME * sway_speed - along;
	float gust = sin(phase);
	gust = mix(gust, gust * 0.55 + sin(phase * 2.7 + root.x * 0.9) * 0.45, sway_flutter);
	// Stiff at the root, full at the tip, and never negative — a blade bends,
	// it does not pivot about its middle.
	float lever = clamp((VERTEX.y - root.y) / sway_height, 0.0, 1.0);
	lever *= lever;
	VERTEX.xz += normalize(sway_direction) * gust * sway_metres * lever;
}


void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	// Dry the sample out before tinting. See the header: a multiply cannot take
	// the green out of a green pixel, and this map has no green in it.
	float luma = dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 dried = mix(tex.rgb, vec3(luma), dryness);
	ALBEDO = dried * tint.rgb;
	ALPHA = tex.a * tint.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.2;
}
