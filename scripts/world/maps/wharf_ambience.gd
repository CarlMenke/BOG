class_name WharfAmbience
extends RefCounted
## The things moving in the air over Lantern Wharf: sea mist off the water,
## insects churning in the floodlight beams, gulls over the harbour — and the
## hooks for the ambient loops that will play under them (4.9).
##
## Whisperbloom Hollow's `Ambience` is the model for all of this and it is not
## reused, because almost nothing about it transfers: its emitters are placed
## against a height oracle on a 50 m island, and this map is a 36 m slab of
## concrete with a known floor at y = 0, so a shared version would be all
## special case and no shared body. What is copied is the *shape* — a static
## builder, one `GPUParticles3D` per idea, every emitter preprocessed so the
## first frame a player sees is a settled one, and audio that is wired and
## silent rather than synthesised.
##
## The whole budget, deliberately, because an eight-player networked game pays
## for every one of these on every client:
##
##   moths     4 emitters x 26 = 104 particles, one per floodlight beam
##   midges    5 emitters x 20 = 100 particles, one per lit festoon
##   mist      1 emitter  x 30 = 30 large, very faint billboards
##   gulls     1 emitter  x  9 = 9 silhouettes over the north water
##   fog       1 FogVolume, a 49 m box 1.8 m tall
##
## 143 particles against the island's 800-odd, and one of them is a fog volume
## rather than geometry. The difference is that this map is 36 m across and the
## island is 50: every particle here is always in frame and always near the
## camera, so the right count is the one where a swarm still reads as a swarm
## and not one more.
##
## Everything seeded, like the rest of the game, and for the reason
## `ambience.gd` gives: none of it is gameplay-relevant, it costs nothing to be
## deterministic, and "why is this frame different" is a question worth never
## having to ask.

## Ambient loops (4.9), by the bus they belong on. **Stubbed on purpose**, the
## same way the island's are: the repository ships no audio, and a synthesised
## placeholder would have to be found and deleted later while every playtest in
## between judged the mix against a sine wave. The wiring is the whole job; each
## is skipped in silence while its file is missing.
##
## What this map wants when the audio arrives:
##
##   `ambient_harbour.wav`  the bed. Water slapping a quay wall, a hull working
##                          against its fenders, a halyard, gulls a long way
##                          off. At the middle of the yard, effectively
##                          unattenuated, so it is under everything.
##   `ambient_lamp_hum.wav` a sodium ballast. Placed at each of the four lamp
##                          heads with a short range, so walking into a corner
##                          of the yard is audible before it is visible — the
##                          job the island's `wind` loop does over the rim, done
##                          by the thing this map has instead of wind.
##   `ambient_quay_water.wav` the water itself, slack and close: a swell working
##                          under a quay wall and sucking back out of it. Placed
##                          twice, outside the north and south walls at the
##                          water's edge, so the sea has a *direction* — which
##                          on a map symmetric to a fault is one of the few
##                          orientation cues a player standing still can get,
##                          and the only one he can get with his eyes shut.
##   `ambient_rigging.wav`  the coaster at the north quay: a halyard against a
##                          mast, a fender creaking, a hull moving on its lines.
##                          One emitter at the ship, quiet and far, which is the
##                          sound equivalent of the silhouette over the wall.
const LOOPS := {
	"harbour": "res://audio/ambience/ambient_harbour.wav",
	"lamp": "res://audio/ambience/ambient_lamp_hum.wav",
	"water": "res://audio/ambience/ambient_quay_water.wav",
	"rigging": "res://audio/ambience/ambient_rigging.wav",
}

## How tall the mist volume is, and how fast its density halves going up.
##
## A Bog is 1.55 m tall and this map's whole argument is that you can see one at
## 25 m; mist at chest height would be a fog bank with a fair-fight problem in
## it. The box is 1.8 m tall so its top face is never a visible edge, but the
## falloff leaves about a tenth of the ground density at a Bog's shoulders and
## effectively none at his head.
## How tall the mist volume's *box* is, and how fast its density halves going up
## inside it.
##
## The box has to be far taller than the mist, which is the one thing that was
## not obvious. At 1.8 m its top face was at exactly eye height, and a player
## looking a few degrees down walked around behind a dead-straight horizontal
## line across the middle of the screen — the edge of the box, seen end-on.
## Six metres puts that edge above every framing anybody has, and the falloff
## is what actually decides where the mist stops: halving every 0.55 m leaves a
## fifth of the ground density at a Bog's eyes and a two-hundredth at four
## metres, so the mist is ankle-deep whatever the box says.
const MIST_TOP := 6.0
const MIST_FALLOFF := 1.25


## Build every ambience emitter under `parent`.
##
## `lamp_heads` and `aim_at` are where the map actually put its floodlights,
## passed in rather than recomputed here: the moths belong to the beams, and the
## honest answer to "where are the beams" is "wherever `_build_floodlights` put
## them".
## `lantern_pools` are the sag points of the lit festoons, handed over by
## `WharfMap._build_lanterns` so the midges can be hung in them without this
## file having to know what a catenary is. It defaults to empty because the
## midges are the only thing that reads it, and a map that has no festoons
## should get no midges rather than an error.
static func build(parent: Node3D, half: float, lamp_heads: Array[Vector3],
		aim_at: Array[Vector3], lantern_pools: Array[Vector3] = []) -> void:
	var root := Node3D.new()
	root.name = "Ambience"
	parent.add_child(root)

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x1A47E2

	_build_mist(root, half)
	_build_moths(root, lamp_heads, aim_at, rng)
	_build_gulls(root, half, rng)
	_build_midges(root, lantern_pools, rng)
	_build_audio(root, lamp_heads, half)


# ------------------------------------------------------------------ midges ---

## Harbour midges under the festoons: the warm counterpart to the moths in the
## floodlight beams, and the thing that makes a hanging bulb read as a hanging
## bulb rather than as an emissive sphere.
##
## One emitter per lit string — five of them, twenty particles each — against
## the moths' four by twenty-six. They are deliberately *smaller, warmer and
## slower* than the moths: a moth in a sodium cone is a flicker of grey at four
## metres a second, and a midge under a festoon is a slow orange speck. Sharing
## the moths' emitter would have been cheaper by five nodes and wrong by both.
##
## The whole cost of this file is now 243 particles against the island's 800,
## and every one of these five sits inside a light pool that already exists, so
## nothing here adds a draw the map was not already paying for.
static func _build_midges(parent: Node3D, pools: Array[Vector3],
		rng: RandomNumberGenerator) -> void:
	for i: int in pools.size():
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = 1.5
		process.direction = Vector3(0.0, 1.0, 0.0)
		process.spread = 180.0
		process.initial_velocity_min = 0.08
		process.initial_velocity_max = 0.45
		# A shade of lift, so the swarm hangs under the bulb instead of raining
		# out of it. Midges over water do exactly this.
		process.gravity = Vector3(0.0, 0.05, 0.0)
		process.damping_min = 0.25
		process.damping_max = 0.8
		process.turbulence_enabled = true
		process.turbulence_noise_strength = 0.65
		process.turbulence_noise_scale = 2.6
		process.scale_min = 0.5
		process.scale_max = 1.0
		process.color_ramp = _fade_ramp(Color(1.0, 0.76, 0.42), 0.55)

		var quad := QuadMesh.new()
		quad.size = Vector2(0.075, 0.075)
		quad.material = _glow_material(Color(1.0, 0.74, 0.40), 2.4)

		var midges := GPUParticles3D.new()
		midges.name = "Midges%d" % i
		midges.draw_pass_1 = quad
		midges.process_material = process
		midges.amount = 20
		midges.lifetime = 7.0
		midges.randomness = 1.0
		# Preprocessed a full lifetime, like every other emitter here, so the
		# first frame a player sees is a settled swarm and not a puff.
		midges.preprocess = 7.0
		midges.position = pools[i] + Vector3(0.0, -0.9, 0.0)
		midges.rotation.y = rng.randf_range(0.0, TAU)
		midges.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
		parent.add_child(midges)


# -------------------------------------------------------------------- mist ---

## Sea mist, in two parts that do different jobs.
##
## The **FogVolume** is the one that matters. It is a box of extra volumetric
## density lying on the yard floor, and because it is volumetric it is *lit*:
## the four floodlight cones come down through it and land in it, so the bottom
## metre of every beam thickens and pools instead of stopping dead at the
## concrete. That is the effect that says "this air has water in it", and no
## number of billboards produces it.
##
## The **billboards** are the other half, and they are only there for motion. A
## fog volume is perfectly still; thirty faint sheets drifting east across the
## yard at a third of a metre a second are what stop the mist reading as a
## property of the map rather than as weather coming in off the water. They are
## unshaded and very faint on purpose — at alpha 0.05, thirty of them stacked
## edge-on still do not add up to anything a Bog can hide behind, and the light
## interaction is the fog volume's job, not theirs.
static func _build_mist(parent: Node3D, half: float) -> void:
	var fog := FogVolume.new()
	fog.name = "SeaMist"
	fog.size = Vector3(half * 2.25, MIST_TOP, half * 2.25)
	fog.position = Vector3(0.0, MIST_TOP * 0.5 - 0.35, 0.0)
	var material := FogMaterial.new()
	# On top of the environment's 0.016, so about 0.05 at ankle height — the
	# island's density, in a layer a player's eyes are never in.
	material.density = 0.008
	material.albedo = Color(0.78, 0.82, 0.88)
	material.emission = Color(0.0, 0.0, 0.0)
	material.height_falloff = MIST_FALLOFF
	# Softens the box's four vertical faces, so the mist does not end in a
	# straight line along the wall feet.
	material.edge_fade = 0.35
	fog.material = material
	parent.add_child(fog)

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(half * 1.15, 0.35, half * 1.15)
	# Out of the west, the way the weather and the last of the sun are.
	process.direction = Vector3(0.92, 0.05, 0.38)
	process.spread = 25.0
	process.initial_velocity_min = 0.18
	process.initial_velocity_max = 0.42
	process.gravity = Vector3(0.0, 0.015, 0.0)
	process.damping_min = 0.0
	process.damping_max = 0.05
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.12
	process.turbulence_noise_scale = 3.2
	process.turbulence_noise_speed = Vector3(0.05, 0.01, 0.04)
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -3.0
	process.angular_velocity_max = 3.0
	process.scale_min = 0.8
	process.scale_max = 1.9
	process.color_ramp = _fade_ramp(Color(0.80, 0.84, 0.90), 0.05)

	var quad := QuadMesh.new()
	quad.size = Vector2(5.2, 2.2)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Mix, not add. Additive mist over a dark yard is smoke lit from inside.
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Torch.soft_dot()
	mat.albedo_color = Color(0.82, 0.86, 0.92)
	mat.disable_receive_shadows = true
	# Sheets at ankle height would sort-flicker against each other every time
	# the camera turned; without depth writes they simply accumulate.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = mat

	var mist := GPUParticles3D.new()
	mist.name = "MistSheets"
	mist.draw_pass_1 = quad
	mist.process_material = process
	mist.amount = 30
	mist.lifetime = 26.0
	mist.randomness = 0.9
	mist.preprocess = 26.0
	mist.position = Vector3(-half * 0.55, 0.55, -half * 0.3)
	mist.visibility_aabb = AABB(Vector3(-half * 2.0, -2.0, -half * 2.0),
		Vector3(half * 4.0, 10.0, half * 4.0))
	parent.add_child(mist)


# ------------------------------------------------------------------- moths ---

## Insects in the beams.
##
## This is the detail the map is named for. A sodium lamp on a dock at dusk has
## a cloud of moths and midges churning under it, and nothing else in this
## game's vocabulary says "a warm light in cold wet air" as economically: the
## particles are additive dots that only exist where the beam is, so the swarm
## *is* the beam, drawn by the things flying in it.
##
## Each swarm sits on its beam's axis a few metres down from the head, which is
## where the cone is still tight enough that twenty-six insects read as a cloud
## rather than as grit. Lifetime is short and turbulence is high — a moth's
## flight is a sequence of mistakes, and the settings that make the island's
## fireflies wander gently are exactly wrong here.
static func _build_moths(parent: Node3D, heads: Array[Vector3], aim_at: Array[Vector3],
		rng: RandomNumberGenerator) -> void:
	for i: int in heads.size():
		var head: Vector3 = heads[i]
		var aim: Vector3 = aim_at[i] if i < aim_at.size() else Vector3.ZERO
		var along := (aim - head).normalized()

		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = 1.9
		process.direction = Vector3(0.0, 1.0, 0.0)
		process.spread = 180.0
		process.initial_velocity_min = 0.4
		process.initial_velocity_max = 1.6
		# A hair of lift, so the cloud creeps back up toward the lamp it is
		# trying to reach instead of settling out of the beam.
		process.gravity = Vector3(0.0, 0.25, 0.0)
		process.damping_min = 0.8
		process.damping_max = 2.4
		process.turbulence_enabled = true
		process.turbulence_noise_strength = 1.9
		process.turbulence_noise_scale = 4.5
		process.turbulence_noise_speed = Vector3(0.9, 0.7, 0.8)
		process.scale_min = 0.45
		process.scale_max = 1.0
		process.color_ramp = _fade_ramp(Color(1.0, 0.86, 0.62), 1.0)

		var quad := QuadMesh.new()
		quad.size = Vector2(0.075, 0.075)
		quad.material = _glow_material(Color(1.0, 0.88, 0.66), 5.0)

		var swarm := GPUParticles3D.new()
		swarm.name = "Moths%d" % i
		swarm.draw_pass_1 = quad
		swarm.process_material = process
		swarm.amount = 26
		swarm.lifetime = 3.4
		swarm.randomness = 0.95
		swarm.preprocess = 3.4
		swarm.position = head + along * 4.5
		swarm.rotation.y = rng.randf_range(0.0, TAU)
		swarm.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
		parent.add_child(swarm)


# ------------------------------------------------------------------- gulls ---

## Gulls over the north water, and the only living thing on this map that is not
## an insect.
##
## They are silhouettes — unshaded, near-black, no emission — because at dusk at
## forty metres that is exactly what a gull is. They fly high enough to clear
## the wall from the middle of the yard (a 7.8 m wall at 18 m puts the top of
## what a standing Bog can see at about 20 degrees, which forty metres out is
## fifteen metres up) and they glide rather than flap, because a flapping
## billboard needs an animated texture and a gliding one does not.
static func _build_gulls(parent: Node3D, half: float, rng: RandomNumberGenerator) -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(26.0, 5.0, 10.0)
	process.direction = Vector3(1.0, 0.0, 0.25)
	process.spread = 40.0
	process.initial_velocity_min = 1.4
	process.initial_velocity_max = 3.2
	process.gravity = Vector3(0.0, -0.02, 0.0)
	process.damping_min = 0.0
	process.damping_max = 0.15
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.5
	process.turbulence_noise_scale = 1.1
	process.scale_min = 0.7
	process.scale_max = 1.3
	process.color_ramp = _fade_ramp(Color(0.10, 0.10, 0.13), 0.85)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.28)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Torch.soft_dot()
	mat.albedo_color = Color(0.09, 0.09, 0.12)
	mat.disable_receive_shadows = true
	quad.material = mat

	var gulls := GPUParticles3D.new()
	gulls.name = "Gulls"
	gulls.draw_pass_1 = quad
	gulls.process_material = process
	gulls.amount = 9
	gulls.lifetime = 34.0
	gulls.randomness = 0.9
	gulls.preprocess = 34.0
	gulls.position = Vector3(-8.0, 24.0, -(half + 22.0))
	gulls.rotation.y = rng.randf_range(0.0, 0.4)
	gulls.visibility_aabb = AABB(Vector3(-70, -20, -40), Vector3(140, 50, 80))
	parent.add_child(gulls)


# ------------------------------------------------------------------- audio ---

## Positioned, looping, on the Ambience bus, skipped in silence when the file is
## not on disk — `ambience.gd::_build_audio` exactly, including the lesson in
## its header: name the files the audio branch will actually commit, because a
## typo here ships a map with no sound and nothing that says so.
static func _build_audio(parent: Node3D, heads: Array[Vector3], half: float) -> void:
	var bed: String = LOOPS["harbour"]
	if ResourceLoader.exists(bed):
		var stream := load(bed) as AudioStream
		if stream != null:
			var player := AudioStreamPlayer3D.new()
			player.name = "Ambient_harbour"
			player.stream = stream
			player.bus = "Ambience"
			player.unit_size = 60.0
			player.volume_db = -6.0
			player.autoplay = true
			player.position = Vector3(0.0, 3.0, 0.0)
			parent.add_child(player)

	var hum: String = LOOPS["lamp"]
	if not ResourceLoader.exists(hum):
		return
	var hum_stream := load(hum) as AudioStream
	if hum_stream == null:
		return
	for i: int in heads.size():
		var player := AudioStreamPlayer3D.new()
		player.name = "Ambient_lamp%d" % i
		player.stream = hum_stream
		player.bus = "Ambience"
		# Short, so a lamp is a place rather than a layer of the mix.
		player.unit_size = 9.0
		player.volume_db = -16.0
		player.autoplay = true
		player.position = heads[i]
		parent.add_child(player)

	_loop_at(parent, "water", "Ambient_waterN", Vector3(0.0, -1.0, -(half + 9.0)), 34.0, -10.0)
	_loop_at(parent, "water", "Ambient_waterS", Vector3(0.0, -1.0, half + 9.0), 34.0, -10.0)
	# At the coaster, which `wharf_map.gd` puts 40.8 m off the north quay.
	_loop_at(parent, "rigging", "Ambient_rigging", Vector3(10.8, 8.0, -40.8), 22.0, -19.0)


## One positioned loop, or nothing at all if its file is not on disk.
##
## Added rather than folded into the two players above, because those two are
## each doing something particular — the bed is unattenuated and the hum is
## one per lamp head — and this is the plain case that the water and the rigging
## both are. Three copies of the same eight lines was the alternative.
static func _loop_at(parent: Node3D, key: String, named: String, at: Vector3,
		unit_size: float, volume_db: float) -> void:
	var path: String = LOOPS[key]
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.name = named
	player.stream = stream
	player.bus = "Ambience"
	player.unit_size = unit_size
	player.volume_db = volume_db
	player.autoplay = true
	player.position = at
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


## In at birth, out at death, flat in between and capped at `peak` — so nothing
## ever pops, and a sheet of mist never gets more opaque than it was told to.
static func _fade_ramp(tint: Color, peak: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(tint.r, tint.g, tint.b, 0.0))
	gradient.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	gradient.add_point(0.18, Color(tint.r, tint.g, tint.b, peak))
	gradient.add_point(0.78, Color(tint.r, tint.g, tint.b, peak * 0.92))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp
