class_name SafariAmbience
extends Node3D
## The things moving over Kopje Crossing: dust off the flats, two dust devils,
## midges over the waterhole, vultures turning over the kopje — and the hooks
## for the ambient loops that will play under them.
##
## The island has `scripts/world/ambience.gd` and this is deliberately not it.
## That file knows about `IslandGenerator`, asks it for a height at a point, and
## builds fireflies and spores for a torch-lit night. A savanna at noon wants
## none of those things and has no height oracle to ask; what it shares with the
## island is the *technique*, and the technique is copied here rather than
## generalised, because a base class that had to serve both would be a base
## class about nothing.
##
## Two things are different in kind, and both come from the hour:
##
##   * **Nothing here glows.** The island's motes are additive and emissive
##     because they are catching torchlight out of a black sky. Over 96 m of
##     sunlit sand an additive particle is invisible, so the dust is
##     alpha-blended and pale, and reads exactly where dust reads in life —
##     against the shaded faces of the rocks, and not against the sky. The one
##     exception is the midges, which are additive on purpose: a swarm of gnats
##     over dark water is nothing but glints.
##   * **Something is alive at a distance.** A savanna with nothing moving in it
##     is a diorama, and the map is too big and too open for particles alone to
##     fix that — you need an animal, and it has to be far enough away and slow
##     enough not to be mistaken for a player. Vultures on a thermal are the
##     answer: 30 m up, one turn every forty seconds, two flocks, and they are
##     the only thing on this map that a `_process` touches.
##
## Budget, stated deliberately because this is an eight-player networked game:
## **four `GPUParticles3D` emitters, 560 particles**, two `MultiMeshInstance3D`
## of eleven bird cards between them, and eleven transform writes a frame. The
## island runs four firefly swarms, 420 spores and a leaf field per tree, so
## this is the same order and rather less of it. Nothing here casts a shadow,
## nothing here has a collider, and nothing here is emitted where a player
## stands: the dust box starts above head height, the devils are placed out in
## the open band away from the pads and the landings, and the midges are over
## water nobody can walk on.
##
## Everything is seeded, like the rest of the map. None of it is
## gameplay-relevant — two clients whose dust was out of step would not be
## playing different games — but it costs nothing to be, and "why is this frame
## different" is a question worth never having to ask. The birds are the one
## exception and they are honest about it: their *flocks* are seeded, their
## phase runs off accumulated frame time, and a bird thirty metres up is not a
## thing anybody aims at.

## Ambient loops, by the bus they belong on.
##
## These are hooks, not assets. The repository ships no audio for this map, and
## `_build_audio` skips a missing file in silence — which is right for an
## optional asset and, as `ambience.gd` found out the hard way, wrong for a
## typo, so the paths here are stated in one place and nowhere else.
##
## What each one is for when it arrives:
##   * `wind` — the bed. High, over the middle of the plateau, effectively
##     unattenuated: 96 m of open ground at noon is never silent.
##   * `insects` — a cicada drone out at the treeline, quiet, so walking toward
##     the rim is audible before it is visible.
##   * `water` — at the waterhole, tightly attenuated, so it is the one place on
##     the map you can find with your ears.
const LOOPS := {
	"wind": "res://audio/ambience/ambient_savanna_wind.wav",
	"insects": "res://audio/ambience/ambient_savanna_insects.wav",
	"water": "res://audio/ambience/ambient_waterhole.wav",
}

# --- dust ----------------------------------------------------------------
## The thermal field. One emitter over the whole plateau, because the thing
## being drawn is not a cloud in a place, it is the air over the map — which is
## also why the count is what it is: 380 motes over a 96 m box thirteen metres
## deep is one every three hundred cubic metres, and at 240 the field was
## honestly invisible from a spawn pad.
const DUST_AMOUNT := 380
const DUST_LIFETIME := 18.0
## Emitted from a box that starts at head height and reaches the top of the
## kopje. Below that it would be in the way; above it there is nothing for it to
## read against.
const DUST_FLOOR := 2.2
const DUST_CEILING := 15.0
const DUST_TINT := Color(0.94, 0.88, 0.74)

## The dust devils. Two, because one is a curiosity and three on a 96 m plateau
## is a weather event.
const DEVIL_AMOUNT := 90
const DEVIL_LIFETIME := 5.5
const DEVIL_HEIGHT := 9.0
const DEVIL_RADIUS := 1.5

## The midges. A tight column over the water and nowhere else.
const MIDGE_AMOUNT := 140
const MIDGE_LIFETIME := 7.0
const MIDGE_TINT := Color(1.0, 0.94, 0.72)

# --- birds ---------------------------------------------------------------
## (centre x, centre z, altitude, turn radius, birds, seconds per turn). The
## signs of the last field are the direction of the turn: the two flocks circle
## opposite ways, which is the cheapest possible way to stop eleven birds
## reading as one mechanism.
const FLOCKS: Array[Dictionary] = [
	{"at": Vector3(0.0, 28.0, 0.0), "radius": 17.0, "birds": 7, "period": 42.0},
	{"at": Vector3(-24.0, 39.0, -13.0), "radius": 26.0, "birds": 4, "period": -68.0},
]
## Wingspan, in metres. A lappet-faced vulture is about 2.7 and at 28 m up that
## is a bird and not a speck.
const WINGSPAN := 2.6
const BIRD_TINT := Color(0.13, 0.11, 0.10)

var _flocks: Array[Dictionary] = []
var _clock := 0.0


## Build every ambience emitter under `parent`.
##
## `devils` is where the dust devils stand, chosen by the map, which is the only
## thing that knows where its landings and its spawn pads are. `reach` is the
## plateau radius; `water` and `water_radius` are the waterhole.
static func build(parent: Node3D, map_seed: int, reach: float, water: Vector2,
		water_radius: float, devils: Array[Vector2]) -> SafariAmbience:
	var root := SafariAmbience.new()
	root.name = "Ambience"
	parent.add_child(root)

	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed ^ 0x415448

	root._build_dust(reach)
	root._build_devils(devils)
	root._build_midges(water, water_radius)
	root._build_birds(rng)
	root._build_audio(reach, water)
	return root


## Eleven birds, one flock at a time. The only per-frame work on this map.
func _process(delta: float) -> void:
	_clock += delta
	for flock: Dictionary in _flocks:
		var multi: MultiMesh = flock["multi"]
		var centre: Vector3 = flock["at"]
		var radius: float = flock["radius"]
		var rate: float = flock["rate"]
		var count: int = multi.instance_count
		for i: int in count:
			# Spread round the ring, and not evenly: birds on a thermal string
			# out, and a perfect ring of seven reads as a fairground.
			var spread: float = flock["spread"][i]
			var angle := _clock * rate + spread
			var at := centre + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			# Bob, so the flock is a spiral rather than a disc.
			at.y += sin(_clock * 0.31 + spread * 1.7) * 1.8
			# Facing along the turn, banked into it, with a slow roll on top so
			# no two birds are ever quite level with each other.
			var heading := angle + (PI * 0.5 if rate > 0.0 else -PI * 0.5)
			var basis := Basis(Vector3.UP, -heading + PI * 0.5)
			var bank := (0.30 if rate > 0.0 else -0.30) + sin(_clock * 0.7 + spread) * 0.12
			basis = basis * Basis(Vector3.FORWARD, bank)
			multi.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * WINGSPAN),
				at))


# -------------------------------------------------------------------- dust ---

## The dust off the flats: a slow field of motes rising and drifting downwind
## over the whole plateau.
##
## This is the layer doing the atmospheric work, and it is the savanna's answer
## to the island's spores. It sits between the camera and every rock on the map,
## so the middle distance is never empty air — and because it is pale and
## alpha-blended rather than additive, it shows against the shaded faces and
## disappears against the sky, which is exactly what dust does.
func _build_dust(reach: float) -> void:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var half := (DUST_CEILING - DUST_FLOOR) * 0.5
	mat.emission_box_extents = Vector3(reach * 0.82, half, reach * 0.82)
	# Downwind and up, matching the sky's own `cloud_wind_azimuth` of 0.78 rad:
	# the clouds and the dust should not disagree about which way the wind is
	# blowing, and on a map this open somebody will notice.
	mat.direction = Vector3(0.71, 0.55, 0.44)
	mat.spread = 38.0
	mat.initial_velocity_min = 0.25
	mat.initial_velocity_max = 1.05
	# A thermal: everything over hot sand is going up, slowly.
	mat.gravity = Vector3(0.22, 0.30, 0.16)
	mat.damping_min = 0.1
	mat.damping_max = 0.45
	# Turbulence is what turns straight-line drift into a wander. It is the
	# single setting that decides whether these read as dust or as snow.
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.40
	mat.turbulence_noise_scale = 1.7
	mat.turbulence_noise_speed = Vector3(0.07, 0.02, 0.05)
	mat.scale_min = 0.45
	mat.scale_max = 1.7
	mat.color_ramp = _fade_ramp(DUST_TINT, 0.30)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.17, 0.17)
	quad.material = _dust_material(DUST_TINT)

	var dust := GPUParticles3D.new()
	dust.name = "Dust"
	dust.draw_pass_1 = quad
	dust.process_material = mat
	dust.amount = DUST_AMOUNT
	dust.lifetime = DUST_LIFETIME
	dust.randomness = 0.9
	# Without a preprocess the field fades up from nothing over eighteen
	# seconds after every scene load, which is exactly the moment a player is
	# deciding what this place looks like.
	dust.preprocess = DUST_LIFETIME
	dust.position = Vector3(0.0, DUST_FLOOR + half, 0.0)
	dust.visibility_aabb = AABB(Vector3(-reach - 8.0, -2.0, -reach - 8.0),
		Vector3(reach * 2.0 + 16.0, DUST_CEILING + 14.0, reach * 2.0 + 16.0))
	add_child(dust)


## The dust devils: two standing columns of sand out on the open band.
##
## The swirl is `tangential_accel` against an upward `gravity` — Godot takes the
## tangential direction from the cross product of those two, so a vertical
## gravity is what makes the spin horizontal, and the lift and the rotation come
## out of the same two settings. The ring emission shape gives the column a hole
## down the middle, which is the difference between a dust devil and a bonfire.
func _build_devils(spots: Array[Vector2]) -> void:
	for i: int in spots.size():
		var mat := ParticleProcessMaterial.new()
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		mat.emission_ring_axis = Vector3.UP
		mat.emission_ring_radius = DEVIL_RADIUS
		mat.emission_ring_inner_radius = DEVIL_RADIUS * 0.45
		mat.emission_ring_height = 0.25
		mat.direction = Vector3.UP
		mat.spread = 12.0
		mat.initial_velocity_min = 1.1
		mat.initial_velocity_max = 2.6
		mat.gravity = Vector3(0.0, 1.1, 0.0)
		mat.tangential_accel_min = 2.4
		mat.tangential_accel_max = 4.6
		# A touch inward, so the column stays a column instead of blowing itself
		# apart into a ring.
		mat.radial_accel_min = -0.45
		mat.radial_accel_max = -0.10
		mat.damping_min = 0.2
		mat.damping_max = 0.7
		mat.scale_min = 0.4
		mat.scale_max = 1.4
		mat.color_ramp = _fade_ramp(DUST_TINT, 0.42)

		var quad := QuadMesh.new()
		quad.size = Vector2(0.22, 0.22)
		quad.material = _dust_material(DUST_TINT)

		var devil := GPUParticles3D.new()
		devil.name = "DustDevil%d" % i
		devil.draw_pass_1 = quad
		devil.process_material = mat
		devil.amount = DEVIL_AMOUNT
		devil.lifetime = DEVIL_LIFETIME
		devil.randomness = 0.8
		devil.preprocess = DEVIL_LIFETIME
		devil.position = Vector3(spots[i].x, 0.15, spots[i].y)
		devil.visibility_aabb = AABB(Vector3(-7.0, -1.0, -7.0),
			Vector3(14.0, DEVIL_HEIGHT + 6.0, 14.0))
		add_child(devil)


## Midges over the waterhole.
##
## The one additive layer on the map, and the one place it belongs: a swarm of
## gnats in sunlight over dark water is nothing but glints, and an alpha-blended
## pale dot over a dark surface would read as falling ash instead. Tight, low,
## and entirely over water nobody can stand on.
func _build_midges(water: Vector2, water_radius: float) -> void:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(water_radius * 0.8, 0.75, water_radius * 0.8)
	mat.direction = Vector3(1.0, 0.25, 0.0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.08
	mat.initial_velocity_max = 0.5
	mat.gravity = Vector3.ZERO
	mat.damping_min = 0.2
	mat.damping_max = 0.8
	mat.turbulence_enabled = true
	# Much harder than the dust. Midges do not drift; they jitter.
	mat.turbulence_noise_strength = 0.9
	mat.turbulence_noise_scale = 3.2
	mat.turbulence_noise_speed = Vector3(0.3, 0.2, 0.25)
	mat.scale_min = 0.5
	mat.scale_max = 1.2
	mat.color_ramp = _fade_ramp(MIDGE_TINT, 1.0)

	var quad := QuadMesh.new()
	# 7 cm. A midge is three millimetres; a *glint* off one against dark water,
	# at the five to fifteen metres this is ever seen from, is not.
	quad.size = Vector2(0.07, 0.07)
	quad.material = _glint_material(MIDGE_TINT, 2.4)

	var midges := GPUParticles3D.new()
	midges.name = "Midges"
	midges.draw_pass_1 = quad
	midges.process_material = mat
	midges.amount = MIDGE_AMOUNT
	midges.lifetime = MIDGE_LIFETIME
	midges.randomness = 0.9
	midges.preprocess = MIDGE_LIFETIME
	midges.position = Vector3(water.x, 1.15, water.y)
	midges.visibility_aabb = AABB(
		Vector3(-water_radius - 3.0, -2.0, -water_radius - 3.0),
		Vector3(water_radius * 2.0 + 6.0, 8.0, water_radius * 2.0 + 6.0))
	add_child(midges)


# ------------------------------------------------------------------- birds ---

## Two flocks of vultures, each one `MultiMeshInstance3D`.
##
## A multimesh rather than a node per bird: eleven birds is eleven transform
## writes into one buffer and one draw call per flock, against eleven draw calls
## and eleven scene-tree updates. At this size neither is expensive, and the
## multimesh is the one that stays cheap if a flock ever grows.
func _build_birds(rng: RandomNumberGenerator) -> void:
	var mesh := _bird_mesh()
	for entry: Dictionary in FLOCKS:
		var count := int(entry["birds"])
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = count

		var spread := PackedFloat32Array()
		for i: int in count:
			# Strung out round the ring rather than spaced round it.
			spread.append(TAU * float(i) / float(count) + rng.randf_range(-0.5, 0.5))

		var node := MultiMeshInstance3D.new()
		node.name = "Vultures%d" % _flocks.size()
		node.multimesh = multi
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var centre: Vector3 = entry["at"]
		var radius := float(entry["radius"])
		# Stated, because the instances move and Godot would otherwise cull the
		# flock against a bounding box computed once, at the origin.
		node.custom_aabb = AABB(
			Vector3(centre.x - radius - 4.0, centre.y - 6.0, centre.z - radius - 4.0),
			Vector3(radius * 2.0 + 8.0, 12.0, radius * 2.0 + 8.0))
		add_child(node)

		_flocks.append({
			"multi": multi,
			"at": Vector3(centre.x, centre.y, centre.z),
			"radius": radius,
			"rate": TAU / float(entry["period"]),
			"spread": spread,
		})
	# One tick's worth, so the first frame rendered is not eleven birds stacked
	# at the same bearing.
	_process(0.0)


## One bird, as four triangles: a shallow V with a nose and a tail.
##
## Not a billboard. A vulture on a thermal is seen from below and from the side
## in the same turn, and a billboard would keep presenting the same silhouette,
## which is the tell that makes cheap birds look cheap. Four triangles is
## cheaper than the quad a billboard would need anyway.
static func _bird_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nose := Vector3(0.0, 0.0, -0.20)
	var tail := Vector3(0.0, 0.0, 0.22)
	# Wings at half a wingspan each, swept back and dihedral up: a soaring bird
	# holds a shallow V, and the V is what makes it read as a bird at range.
	var left := Vector3(-0.5, 0.085, 0.06)
	var right := Vector3(0.5, 0.085, 0.06)
	for tri: Array in [[nose, left, tail], [nose, tail, right]]:
		st.set_normal(Vector3.UP)
		for point: Vector3 in tri:
			st.add_vertex(point)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = BIRD_TINT
	# Two-sided: half of every turn shows the underside.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	st.set_material(mat)
	return st.commit()


# ------------------------------------------------------------------- audio ---

## Ambient audio. **Stubbed on purpose**, exactly as `ambience.gd::_build_audio`
## is and for exactly the same reason: the repository ships no audio, and
## inventing placeholder tones would be worse than silence — they would have to
## be found and deleted later, and in the meantime every playtest would be
## judging mixing decisions made against a sine wave.
##
## What is here is the wiring, so that dropping the files in is the whole job.
## Each loop is a positioned, looping `AudioStreamPlayer3D` on the Ambience bus
## (which `default_bus_layout.tres` already defines and `Settings` already has a
## slider for), and each is skipped in silence while its file is missing.
func _build_audio(reach: float, water: Vector2) -> void:
	var placements := {
		"wind": {"at": Vector3(0.0, 14.0, 0.0), "range": reach * 2.2, "db": -8.0},
		"insects": {"at": Vector3(0.0, 2.0, 0.0), "range": reach * 1.6, "db": -15.0},
		# Tight on purpose: the waterhole is the one landmark on this map you
		# should be able to find with your ears.
		"water": {"at": Vector3(water.x, 0.6, water.y), "range": 14.0, "db": -10.0},
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


# --------------------------------------------------------------- materials ---

## Dust: unshaded, **alpha-blended**, billboarded soft dot. See the header for
## why this is not the island's additive glow — over sunlit sand an additive
## particle is a particle nobody can see.
static func _dust_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Torch.soft_dot()
	mat.albedo_color = tint
	mat.disable_receive_shadows = true
	# Dust is the one thing on this map that should never be sorted behind the
	# rock it is in front of, and never write depth for the next mote.
	mat.no_depth_test = false
	return mat


## Midges: the island's treatment, unaltered, because the island was right about
## what a lit speck over a dark surface wants to be.
static func _glint_material(tint: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Torch.soft_dot()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = energy
	mat.disable_receive_shadows = true
	return mat


## In at birth, out at death, flat in between — so nothing ever pops. `peak` is
## how opaque it gets in the middle, which for dust is the whole art direction:
## at 1.0 the flats look like a house fire.
static func _fade_ramp(tint: Color, peak: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(tint.r, tint.g, tint.b, 0.0))
	gradient.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	gradient.add_point(0.18, Color(tint.r, tint.g, tint.b, peak))
	gradient.add_point(0.75, Color(tint.r, tint.g, tint.b, peak * 0.85))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp
