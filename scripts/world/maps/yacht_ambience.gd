class_name YachtAmbience
extends Node3D
## The things that move over Halcyon Wake that are not the sea or the flags:
## gulls working the anchorage, steam off the hot tub, and the hooks for the
## ambient loops (D-057).
##
## Whisperbloom Hollow's `ambience.gd` is the model for all of this and the
## audio wiring below follows it exactly — named paths, the `Ambience` bus,
## skipped in silence when the file is not on disk. What is *not* copied is the
## particle-swarm approach to the moving layer, and the reason is worth writing
## down: the island's fireflies work because a firefly has no shape and no
## course, so five hundred of them wandering is exactly right. A gull has both.
## Six birds on six circles, each banked into its turn and each beating out of
## step with the others, read as gulls; six hundred particles would read as ash.
##
## So the gulls are six `MeshInstance3D`s moved by this node in `_process`,
## which is six transform writes a frame and six draw calls, and their wings are
## a vertex shader (`yacht_gull.gdshader`) rather than six more nodes.
##
## Determinism, on the same terms as the island's: every course, radius, height
## and wing phase here is a constant, so two clients build the same flock in the
## same places facing the same way. Where they are *along* their circles after
## ten minutes depends on frame timing and will drift by a few degrees between
## peers, which is not a thing any player can observe and not a thing any rule
## reads.

## Ambient loops, by the bus they belong on — the same shape as
## `Ambience.LOOPS`, and the same rule: a missing file is skipped in silence
## rather than substituted. The island shipped with no ambience at all because
## these paths were guessed on a branch that never saw the audio, so these are
## checked against what is actually in `audio/ambience/` today:
## `ambient_wind.wav` is there and will play; the other two are the two beds
## this map wants and does not have yet, and naming them is the whole of what is
## needed when they arrive.
##
##   sea    the bed: water working along the topsides, at the waterline,
##          effectively unattenuated anywhere on board.
##   wind   over the flybridge, so climbing gets louder as well as higher.
##   gulls  out over the anchorage, quiet and off to port, where the birds are.
const LOOPS := {
	"sea": "res://audio/ambience/ambient_sea.wav",
	"wind": "res://audio/ambience/ambient_wind.wav",
	"gulls": "res://audio/ambience/ambient_gulls.wav",
}

const GULL_SHADER := preload("res://resources/shaders/yacht_gull.gdshader")

## Six gulls, on six circles. `centre` is the circle's middle on the deck plan
## and every one of them is offset to one side or the other, so the birds spend
## their time over water rather than over the decks: a gull crossing between two
## Bogs at 20 m up is a fraction of a pixel, but a gull crossing between them at
## 6 m would be a bug, and the cheapest way to never have that argument is to
## keep the flock outboard.
##
## Periods are deliberately mutually prime-ish — 37, 44, 29, 53, 41, 61 seconds
## — so the flock never falls into a pattern a player could time.
const GULLS: Array[Dictionary] = [
	{"centre": Vector2(-26.0, -14.0), "radius": 21.0, "height": 19.5, "period": 37.0,
		"phase": 0.00, "wing": 0.15, "size": 0.80, "bob": 1.1},
	{"centre": Vector2(24.0, 6.0), "radius": 26.0, "height": 23.0, "period": -44.0,
		"phase": 0.37, "wing": 0.62, "size": 0.72, "bob": 1.5},
	{"centre": Vector2(-19.0, 22.0), "radius": 17.0, "height": 16.5, "period": 29.0,
		"phase": 0.71, "wing": 0.28, "size": 0.86, "bob": 0.8},
	{"centre": Vector2(8.0, -34.0), "radius": 24.0, "height": 26.0, "period": -53.0,
		"phase": 0.13, "wing": 0.88, "size": 0.66, "bob": 1.8},
	{"centre": Vector2(31.0, 28.0), "radius": 33.0, "height": 21.0, "period": 41.0,
		"phase": 0.55, "wing": 0.41, "size": 0.78, "bob": 1.3},
	{"centre": Vector2(-36.0, 4.0), "radius": 29.0, "height": 30.0, "period": 61.0,
		"phase": 0.92, "wing": 0.07, "size": 0.62, "bob": 2.2},
]

## How far a gull leans into its turn. Real ones lean more than this; at this
## size anything more reads as a bird falling out of the sky.
const GULL_BANK := 0.30

## The hot tub, from `YachtMap`. Kept here as numbers rather than read off the
## map so that this file can be looked at on its own, and small enough that the
## duplication is cheaper than the coupling.
const TUB_AT := Vector3(-3.25, 6.75, 4.75)

var _birds: Array[Node3D] = []
var _clock: float = 0.0


static func build(parent: Node3D) -> void:
	var root := YachtAmbience.new()
	root.name = "Ambience"
	parent.add_child(root)


func _ready() -> void:
	_build_gulls()
	_build_steam()
	_build_audio()


func _process(delta: float) -> void:
	_clock += delta
	for i: int in _birds.size():
		var entry: Dictionary = GULLS[i]
		var centre: Vector2 = entry["centre"]
		var period := float(entry["period"])
		var turn := TAU * (_clock / period + float(entry["phase"]))
		var radius := float(entry["radius"])
		var at := Vector3(centre.x + cos(turn) * radius,
			float(entry["height"]) + sin(turn * 1.7) * float(entry["bob"]),
			centre.y + sin(turn) * radius)
		# The tangent of the circle, which is where a bird on it is pointing.
		var heading := signf(period) * Vector3(-sin(turn), 0.0, cos(turn))
		var bird := _birds[i]
		bird.position = at
		bird.basis = Basis.looking_at(heading, Vector3.UP)
		bird.rotate_object_local(Vector3.FORWARD, -signf(period) * GULL_BANK)


# ------------------------------------------------------------------- gulls ---

func _build_gulls() -> void:
	var mesh := _gull_mesh()
	for entry: Dictionary in GULLS:
		var bird := MeshInstance3D.new()
		bird.name = "Gull%d" % _birds.size()
		bird.mesh = mesh
		bird.scale = Vector3.ONE * float(entry["size"])
		# Twenty metres up over open water, casting a shadow onto nothing that
		# anybody will ever look at, inside a 90 m shadow range that is already
		# carrying four decks.
		bird.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = GULL_SHADER
		material.set_shader_parameter("phase", float(entry["wing"]))
		bird.material_override = material
		add_child(bird)
		_birds.append(bird)


## One gull: a swept wing either side of a body, four triangles and a spar. The
## UV runs 0 at the port wingtip to 1 at the starboard one, because that is what
## `yacht_gull.gdshader` beats against.
static func _gull_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Wing plan, starboard half, as (span out, offset aft): the leading edge
	# sweeps back and the trailing edge sweeps back harder, so the tip is a
	# point rather than a paddle.
	var stations: Array[Vector3] = [
		Vector3(0.10, -0.16, 0.20),
		Vector3(0.42, -0.04, 0.16),
		Vector3(0.78, 0.14, 0.09),
		Vector3(1.00, 0.30, 0.02),
	]
	for side: float in [-1.0, 1.0]:
		for i: int in stations.size() - 1:
			var a: Vector3 = stations[i]
			var b: Vector3 = stations[i + 1]
			_wing_quad(st, side, a, b)
	# The body, as a narrow diamond fore and aft of the shoulders.
	for side: float in [-1.0, 1.0]:
		_gull_tri(st, side, Vector3(0.0, -0.34, 0.0), Vector3(0.10 * side, -0.16, 0.06),
			Vector3(0.0, 0.26, 0.0))
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


static func _wing_quad(st: SurfaceTool, side: float, a: Vector3, b: Vector3) -> void:
	var corners: Array[Vector3] = [
		Vector3(a.x * side, 0.0, a.y),
		Vector3(b.x * side, 0.0, b.y),
		Vector3(b.x * side, 0.0, b.y + b.z),
		Vector3(a.x * side, 0.0, a.y + a.z),
	]
	var uvs: Array[float] = [a.x, b.x, b.x, a.x]
	for k: int in [0, 1, 2, 0, 2, 3]:
		st.set_uv(Vector2(0.5 + 0.5 * side * uvs[k], 0.5))
		st.set_normal(Vector3.UP)
		st.add_vertex(corners[k])


static func _gull_tri(st: SurfaceTool, side: float, a: Vector3, b: Vector3,
		c: Vector3) -> void:
	for p: Vector3 in [a, b, c]:
		st.set_uv(Vector2(0.5 + 0.5 * side * absf(p.x) * 4.0, 0.5))
		st.set_normal(Vector3.UP)
		st.add_vertex(p)


# ------------------------------------------------------------------- steam ---

## Steam off the hot tub. Thirty-two particles, one emitter, and the only
## particle system on the map.
##
## It is here because it is the one thing on a yacht at anchor on a cool morning
## that gives off anything at all, and because the sun deck — which is where G
## sits, and therefore where the fight goes — had nothing in the air over it.
##
## It is kept deliberately thin. The tub is a declared landing: a Bog can stand
## in it, and a plume that hid one would be a bug and not a mood. 0.9 m tall,
## alpha well under a tenth, and drifting downwind so it clears the tub rather
## than sitting on it.
func _build_steam() -> void:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	mat.emission_sphere_radius = 0.95
	mat.direction = Vector3(0.0, 1.0, 0.35)
	mat.spread = 24.0
	mat.initial_velocity_min = 0.12
	mat.initial_velocity_max = 0.34
	mat.gravity = Vector3(0.0, 0.18, 0.55)
	mat.damping_min = 0.15
	mat.damping_max = 0.45
	mat.scale_min = 0.6
	mat.scale_max = 1.5
	mat.scale_over_velocity_min = 0.0
	mat.color_ramp = _steam_ramp()

	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.34)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	look.billboard_keep_scale = true
	look.vertex_color_use_as_albedo = true
	look.albedo_texture = Torch.soft_dot()
	look.albedo_color = Color(0.96, 0.98, 1.0, 1.0)
	look.disable_receive_shadows = true
	quad.material = look

	var steam := GPUParticles3D.new()
	steam.name = "TubSteam"
	steam.draw_pass_1 = quad
	steam.process_material = mat
	steam.amount = 32
	steam.lifetime = 3.4
	steam.randomness = 0.8
	# Without a preprocess the plume grows out of nothing over three seconds
	# after every load, which is exactly the moment somebody decides what this
	# place looks like.
	steam.preprocess = 3.4
	steam.position = TUB_AT
	steam.visibility_aabb = AABB(Vector3(-2.0, -0.5, -2.0), Vector3(4.0, 3.0, 5.0))
	steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(steam)


## In fast, out slowly, and never above a tenth of an alpha.
static func _steam_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.18, Color(1.0, 1.0, 1.0, 0.13))
	gradient.add_point(0.55, Color(1.0, 1.0, 1.0, 0.075))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


# ------------------------------------------------------------------- audio ---

## PLAN 4.9 — ambient audio, wired exactly as `Ambience._build_audio` wires the
## island's: a positioned, looping `AudioStreamPlayer3D` per bed on the Ambience
## bus, each skipped in silence while its file is missing. No placeholder tones
## are synthesised here and none should be: a playtest that judges the mix
## against a sine wave is worse than a playtest in silence.
func _build_audio() -> void:
	var placements := {
		"sea": {"at": Vector3(0.0, -2.0, 0.0), "range": 70.0, "db": -7.0},
		"wind": {"at": Vector3(0.0, 13.0, -2.0), "range": 55.0, "db": -13.0},
		"gulls": {"at": Vector3(-26.0, 20.0, 4.0), "range": 80.0, "db": -18.0},
	}
	for key: String in LOOPS:
		var path: String = LOOPS[key]
		if not ResourceLoader.exists(path):
			continue
		var stream := load(path) as AudioStream
		if stream == null:
			continue
		var placement: Dictionary = placements[key]
		var player := AudioStreamPlayer3D.new()
		player.name = "Ambient_%s" % key
		player.stream = stream
		player.bus = "Ambience"
		player.unit_size = placement["range"]
		player.volume_db = placement["db"]
		player.autoplay = true
		player.position = placement["at"]
		add_child(player)
