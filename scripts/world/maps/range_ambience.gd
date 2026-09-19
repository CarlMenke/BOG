class_name RangeAmbience
extends RefCounted
## The things moving in the air over Highsun Grounds: the drifting glowworm
## motes, marsh gas coming up off the peat, a layer of mist lying in the bottom
## of the bog — and the two ambient loops the repository already has.
##
## The map used to be named for the glowworms and is not any more (the sun is
## up), and they stay anyway, unchanged, because they were never furniture.
## **This is the one place on the range where an unshaded emissive quad is the
## right answer**: these are *effects* — soft dots with no silhouette, no
## collision and nothing to aim at — and an effect is allowed to be light with
## no object under it. What is not allowed is an object that is only light: see
## the note above `range_map.TORCHES` for the rule and the twenty-four lantern
## spheres it cost.
##
## `WharfAmbience` is the model, not `Ambience`, and for the reason the wharf
## gives about the island: the hollow's emitters are placed against a height
## oracle, and this map is a flat slab with a known floor at y = 0, so a shared
## version would be all special case and no shared body. What is copied is the
## *shape* — a static builder, one `GPUParticles3D` per idea, every emitter
## preprocessed so the first frame a player sees is a settled one, and audio
## that is wired rather than invented.
##
## The whole budget, deliberately, because an eight-player networked game pays
## for every one of these on every client — and this map is already paying for
## twenty-three dummy Bogs, which is where the frame actually goes:
##
##   glowworms  4 emitters x 40 = 160 particles, over the four open yards
##   marsh gas  1 emitter  x 24 = 24 slow rising motes
##   fog        1 FogVolume, a 62 x 92 m box 1.6 m tall
##
## 184 particles against the island's 800-odd and the wharf's 143. The island
## can afford more because it is 50 m across and half its particles are always
## off screen; this map is 90 m long and a player is usually looking down the
## length of it, so the right count is the one where a swarm still reads as a
## swarm over a lane and not as grit on the lens.
##
## Everything seeded, like the rest of the game, and for the reason
## `ambience.gd` gives: none of it is gameplay-relevant, it costs nothing to be
## deterministic, and "why is this frame different" is a question worth never
## having to ask.

## The ambient loops, and **both of these files already exist**. That is the
## whole of the rule here: `tools/make_sfx.py` belongs to units 3-5 this round,
## so this map ships with the beds the island already synthesised rather than
## with two names that resolve to nothing. The island shipped silent for exactly
## that reason once (see `ambience.gd`'s note on `LOOPS`), and a slot that would
## need a new file is left out rather than stubbed.
##
##   `ambient_forest.wav`  the bed. It is a night forest, and this is a bog in
##                         one — the same wet, close, insect-thick air, and the
##                         same map that Whisperbloom Hollow is a clearing in.
##                         At the middle of the range, effectively unattenuated,
##                         so it is under everything.
##   `ambient_wind.wav`    at the void lips. The island uses it over the rim,
##                         which is the same place: the one edge of the map
##                         where there is nothing between you and the open air,
##                         and the one place on this map worth hearing before
##                         you see it.
const LOOPS := {
	"forest": "res://audio/ambience/ambient_forest.wav",
	"wind": "res://audio/ambience/ambient_wind.wav",
}

## How tall the mist lies and how fast it thins going up.
##
## A Bog is 1.55 m and its eyes are at 1.33, and this map's whole argument is
## that you can read a dummy at forty-five metres. So the mist has to be a thing
## you look *over*: 1.6 m of box with the density halving every 1.1 m puts
## almost all of it under a standing Bog's chin. What it buys is the bottom of
## every torch pool thickening into the peat instead of stopping dead at it, and
## the 1.25 m cover blocks standing out of something.
const MIST_TOP := 1.6
const MIST_FALLOFF := 1.1

## Where the glowworms swarm: the open ground of the four yards, in map space.
## Four loose swarms rather than one map-wide cloud, which is the island's
## argument and holds here for the same reason — 160 particles spread over 5,400
## square metres is one every six metres, and that reads as dust.
const SWARMS: Array[Vector3] = [
	Vector3(-21.0, -26.0, 9.0),   # the ability yard, over the clump
	Vector3(16.0, -7.0, 6.0),     # the melee pit
	Vector3(15.0, -32.0, 8.0),    # the parkour course
	Vector3(-23.0, 6.0, 9.0),     # the throwing lanes, half way down
]
const SWARM_COUNT := 40
const GLOW_TINT := Color(0.68, 1.0, 0.56)


## Build every emitter under `parent`. `across` is (west, east) and `along` is
## (north, south), straight off `RangeMap`, so the mist covers the map the map
## actually built rather than one this file remembers.
static func build(parent: Node3D, across: Vector2, along: Vector2) -> void:
	var root := Node3D.new()
	root.name = "Ambience"
	parent.add_child(root)

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x610BA1

	var middle := Vector3((across.x + across.y) * 0.5, 0.0, (along.x + along.y) * 0.5)
	var size := Vector2(across.y - across.x, along.y - along.x)

	_build_mist(root, middle, size)
	_build_glowworms(root, rng)
	_build_marsh_gas(root, middle, size, rng)
	_build_audio(root, middle, along)


# -------------------------------------------------------------------- mist ---

## The layer of bog air, as a `FogVolume` and nothing else.
##
## No drifting billboards here, which is the one place this departs from the
## wharf. The wharf needs them because its mist is *weather coming in off the
## water* and a fog volume is perfectly still; this map's is standing air over
## wet peat, which really is still, and thirty sheets drifting across a sixty
## metre shooting lane would be thirty things between a player and the target he
## is trying to read. The motion budget goes to the glowworms instead, which are
## the thing the place is named for.
static func _build_mist(parent: Node3D, middle: Vector3, size: Vector2) -> void:
	var fog := FogVolume.new()
	fog.name = "BogMist"
	fog.size = Vector3(size.x + 2.0, MIST_TOP, size.y + 2.0)
	fog.position = middle + Vector3(0.0, MIST_TOP * 0.5 - 0.3, 0.0)
	var material := FogMaterial.new()
	# On top of the environment's own 0.0035. **0.012, down from 0.020, and warm
	# rather than green**: at night this sat under a cold blue moon and was
	# invisible until you looked along it; under a nine-degree sun a fog volume
	# is lit, and at 0.020 in a warm sky the bottom metre of the map came back
	# as a milky sheet with the lane rails inside it. Thinner, and the colour of
	# the light that is actually falling on it.
	material.density = 0.012
	material.albedo = Color(0.86, 0.74, 0.62)
	material.emission = Color(0.0, 0.0, 0.0)
	material.height_falloff = MIST_FALLOFF
	# Softens the box's four vertical faces, so the bog does not end in a
	# straight line across the peat.
	material.edge_fade = 0.4
	fog.material = material
	parent.add_child(fog)


# -------------------------------------------------------------- glowworms ---

## The glowworms. The island's fireflies, slowed down and pulled to the ground.
##
## A firefly over Whisperbloom Hollow blinks and wanders at head height; a
## glowworm is a larva in wet moss that does not go anywhere and does not blink
## — it just glows, for hours. So these sit low (0.3 to 1.6 m), drift at a
## third of the speed, and their ramp fades in and out over a long lifetime
## instead of pulsing. The blink is what would make them read as insects, and
## an insect is a thing you look at rather than a thing you see the bog through.
static func _build_glowworms(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	quad.material = _glow_material(GLOW_TINT, 3.2)

	for i: int in SWARMS.size():
		var swarm: Vector3 = SWARMS[i]
		var spread := swarm.z
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = Vector3(spread, 0.65, spread)
		process.direction = Vector3(1.0, 0.1, 0.0)
		process.spread = 180.0
		process.initial_velocity_min = 0.02
		process.initial_velocity_max = 0.14
		process.gravity = Vector3.ZERO
		process.damping_min = 0.0
		process.damping_max = 0.08
		process.turbulence_enabled = true
		process.turbulence_noise_strength = 0.05
		process.turbulence_noise_scale = 2.0
		process.turbulence_noise_speed = Vector3(0.02, 0.01, 0.02)
		process.scale_min = 0.5
		process.scale_max = 1.4
		process.color_ramp = _fade_ramp(GLOW_TINT, 0.95)

		var worms := GPUParticles3D.new()
		worms.name = "Motes%d" % i
		worms.draw_pass_1 = quad
		worms.process_material = process
		worms.amount = SWARM_COUNT
		worms.lifetime = 18.0
		worms.randomness = 1.0
		# Settled before the first frame anybody sees, so a match never opens on
		# a swarm mid-fade.
		worms.preprocess = 18.0
		worms.position = Vector3(swarm.x, 0.95, swarm.y)
		worms.visibility_aabb = AABB(
			Vector3(-spread * 1.4, -1.5, -spread * 1.4),
			Vector3(spread * 2.8, 5.0, spread * 2.8))
		# Seeded per swarm so two clients see the same bog, for the reason the
		# rest of the game is seeded: it costs nothing.
		worms.seed = int(rng.randi())
		worms.use_fixed_seed = true
		parent.add_child(worms)


# ------------------------------------------------------------- marsh gas ---

## Marsh gas: two dozen motes coming up off the peat, slowly, and going out.
##
## The one thing in here that moves vertically, and it is what stops the mist
## layer reading as a flat sheet laid over the map — something has to be coming
## out of the ground for the ground to be a bog.
static func _build_marsh_gas(parent: Node3D, middle: Vector3, size: Vector2,
		rng: RandomNumberGenerator) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	quad.material = _glow_material(Color(0.50, 0.72, 0.60), 1.1)

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(size.x * 0.46, 0.2, size.y * 0.46)
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = 0.18
	process.initial_velocity_max = 0.45
	process.gravity = Vector3(0.0, 0.02, 0.0)
	process.damping_min = 0.02
	process.damping_max = 0.12
	process.scale_min = 0.6
	process.scale_max = 1.8
	process.color_ramp = _fade_ramp(Color(0.50, 0.72, 0.60), 0.30)

	var gas := GPUParticles3D.new()
	gas.name = "MarshGas"
	gas.draw_pass_1 = quad
	gas.process_material = process
	gas.amount = 24
	gas.lifetime = 14.0
	gas.randomness = 1.0
	gas.preprocess = 14.0
	gas.position = middle + Vector3(0.0, 0.3, 0.0)
	gas.visibility_aabb = AABB(Vector3(-size.x * 0.6, -1.0, -size.y * 0.6),
		Vector3(size.x * 1.2, 12.0, size.y * 1.2))
	gas.seed = int(rng.randi())
	gas.use_fixed_seed = true
	parent.add_child(gas)


# ------------------------------------------------------------------ audio ---

## The two beds, both of them files that already exist. See `LOOPS`.
##
## Each is skipped in silence if its file is missing, which is right for an
## optional asset — but neither is optional here, and if one ever goes the map
## goes quiet rather than erroring, which is the same bargain every other map
## on the list has made.
static func _build_audio(parent: Node3D, middle: Vector3, along: Vector2) -> void:
	var bed: String = LOOPS["forest"]
	if ResourceLoader.exists(bed):
		var stream := load(bed) as AudioStream
		if stream != null:
			var player := AudioStreamPlayer3D.new()
			player.name = "Ambient_forest"
			player.stream = stream
			player.bus = "Ambience"
			# Wide, so it is the air rather than a place in it.
			player.unit_size = 70.0
			player.volume_db = -7.0
			player.autoplay = true
			player.position = middle + Vector3(0.0, 3.0, 0.0)
			parent.add_child(player)

	var wind: String = LOOPS["wind"]
	if not ResourceLoader.exists(wind):
		return
	var wind_stream := load(wind) as AudioStream
	if wind_stream == null:
		return
	# Two, on the north lip, a third of the way in from each end — so walking
	# toward the void is audible before the railing is visible, which is the job
	# the island's wind does over its rim.
	for x: float in [-18.0, 10.0]:
		var player := AudioStreamPlayer3D.new()
		player.name = "Ambient_wind%+.0f" % x
		player.stream = wind_stream
		player.bus = "Ambience"
		# Short, so the lip is a place and not a layer of the mix.
		player.unit_size = 16.0
		player.volume_db = -14.0
		player.autoplay = true
		player.position = Vector3(x, 1.5, along.x + 1.0)
		parent.add_child(player)


# -------------------------------------------------------------- materials ---

## Unshaded, additive, billboarded soft dot, on the texture every flame and
## firefly in the game already shares — so there is one of it in memory.
static func _glow_material(tint: Color, energy: float) -> StandardMaterial3D:
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


## In at birth, out at death, flat in between and capped at `peak`, so nothing
## ever pops. A glowworm's long flat middle is the point of it: it is a light
## that stays on, not one that blinks.
static func _fade_ramp(tint: Color, peak: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(tint.r, tint.g, tint.b, 0.0))
	gradient.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	gradient.add_point(0.15, Color(tint.r, tint.g, tint.b, peak))
	gradient.add_point(0.82, Color(tint.r, tint.g, tint.b, peak * 0.95))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp
