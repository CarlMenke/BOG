class_name QuarryAmbience
extends RefCounted
## The things moving in the air over Twin Quarry: rock dust lifting off the
## benches, heat coming off a pale floor at noon, dust hanging in the shaft, and
## the birds that live on an eleven-metre cliff nobody has worked for years —
## with the hooks for the ambient loops that will play under them.
##
## `wharf_ambience.gd` is the model and it is not reused, because almost nothing
## about it transfers: its emitters belong to floodlight beams over wet concrete
## at dusk, and this is dry stone in hard sun with a hole in the middle. What is
## copied is the **shape** — a static builder, one `GPUParticles3D` per idea,
## every emitter preprocessed so the first frame a player sees is a settled one,
## audio wired and silent rather than synthesised, and every seed fixed so two
## machines show the same pit.
##
## The whole budget, deliberately, because an eight-player networked game pays
## for every one of these on every client:
##
##   dust      1 emitter x 44 motes drifting across the pit floor
##   shaft     1 emitter x 22 large faint sheets rising out of the hole
##   devils    2 emitters x 18 each, the little spinners a hot floor throws
##   crows     1 emitter x 7 silhouettes over the rim
##   haze      1 FogVolume, a 54 m box 7 m tall, and a second one in the shaft
##
## 109 particles and two fog volumes. Fewer than the wharf's, and the reason is
## the sun: at noon under a hard key every particle is *lit*, so a mote reads
## from thirty metres where a wharf midge at dusk did not, and the count that
## makes a haze read as a haze is correspondingly smaller.
##
## **Nothing here is collision and nothing here is gameplay.** It is all added
## after `StaticMap`'s `super()` by `QuarryMap._ready`, which is the same line
## every other map's atmosphere lives below.

## Ambient loops, by the bus they belong on. **Stubbed on purpose**, the same
## way the island's and the wharf's are: the repository ships no audio, and a
## synthesised placeholder would have to be found and deleted later while every
## playtest in between judged the mix against a sine wave. The wiring is the
## whole job; each is skipped in silence while its file is missing.
##
## What this map wants when the audio arrives:
##
##   `ambient_quarry.wav`   the bed. A wide dry outdoor room, wind over stone,
##                          a bird a long way off, nothing wet. At the middle
##                          of the pit, effectively unattenuated, so it is
##                          under everything.
##   `ambient_rim_wind.wav` the wind itself, and the only thing on this map that
##                          tells you which way you are facing with your eyes
##                          shut. Four emitters, one over the middle of each
##                          rim, so walking toward a cliff is audible before it
##                          is visible.
##   `ambient_shaft.wav`    what comes *up* out of the hole: a low hollow draw,
##                          the sound a big void makes. One emitter on the lip
##                          with a short range, so the hazard has a voice and
##                          you hear it before you walk off the edge — which on
##                          a map where the hole is the only thing that kills
##                          you for free is worth a whole emitter.
##   `ambient_plant.wav`    the crusher somewhere beyond the rim, still running
##                          or still being remembered: a slow distant knocking.
##                          Placed at one derrick, quiet and far, which is the
##                          sound equivalent of the silhouette over the cliff.
const LOOPS := {
	"quarry": "res://audio/ambience/ambient_quarry.wav",
	"wind": "res://audio/ambience/ambient_rim_wind.wav",
	"shaft": "res://audio/ambience/ambient_shaft.wav",
	"plant": "res://audio/ambience/ambient_plant.wav",
}

## How tall the heat-haze box is, and how fast its density halves going up.
##
## The box has to be far taller than the haze, which is the lesson the wharf
## paid for: at eye height its top face is a dead-straight horizontal line
## across the middle of the screen. Seven metres puts that edge over every
## framing anybody has, and the falloff is what decides where the haze actually
## stops — halving every 1.6 m leaves about a third of the ground density at a
## Bog's eyes and a twentieth at the top of a base wall.
const HAZE_TOP := 7.0
const HAZE_FALLOFF := 0.44
## The haze's own density, on top of whatever the environment already has. Low,
## because this is a hard-sun map and the whole point of hard sun is that you
## can see across it: the haze is there to put air between a Bog and the far
## cliff, not to hide one at twenty metres.
const HAZE_DENSITY := 0.0055
## Dust in the shaft is the opposite: thick, because a sixteen-metre hole that
## you can see the bottom of is not a hazard, it is a basement.
const SHAFT_DENSITY := 0.055


## Build every ambience emitter under `parent`.
##
## `half` is the pit's half-width and `hole` the shaft's, both passed in rather
## than re-derived: the dust belongs to the floor the map actually built and the
## shaft plume belongs to the hole it actually cut. `lamp_heads` is where
## `QuarryMap._build_lamps` put the two work lamps, so the motes that churn in a
## beam belong to the beam.
static func build(parent: Node3D, half: float, hole: float,
		lamp_heads: Array[Vector3]) -> void:
	var root := Node3D.new()
	root.name = "Ambience"
	parent.add_child(root)

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x51A7D0

	_build_haze(root, half, hole)
	_build_dust(root, half)
	_build_shaft_plume(root, hole)
	_build_devils(root, half, rng)
	_build_crows(root, half, rng)
	_build_lamp_motes(root, lamp_heads)
	_build_audio(root, half, hole)


# -------------------------------------------------------------------- haze ---

## Two fog volumes: the shimmer over the whole pit, and the dark hanging in the
## shaft.
##
## They are separate volumes and not one gradient, because they are two
## different facts. The pit's haze is *air over hot stone* — thin, warm-tinted,
## and it has to leave a Bog readable at thirty metres or the map's whole
## sightline argument stops being true. The shaft's is *dust in a hole nobody
## has been down in years* — thick, cold, and it exists precisely so the bottom
## of the drop is not visible, because a hazard you can see the floor of is a
## hazard players misjudge in the one direction that kills them.
static func _build_haze(parent: Node3D, half: float, hole: float) -> void:
	var haze := FogVolume.new()
	haze.name = "HeatHaze"
	haze.size = Vector3(half * 2.25, HAZE_TOP, half * 2.25)
	haze.position = Vector3(0.0, HAZE_TOP * 0.5 - 0.4, 0.0)
	var warm := FogMaterial.new()
	warm.density = HAZE_DENSITY
	# Warm and pale: the colour of the light coming off a limestone floor, which
	# is what the air over a quarry at noon is actually full of.
	warm.albedo = Color(0.96, 0.90, 0.78)
	warm.emission = Color(0.0, 0.0, 0.0)
	warm.height_falloff = HAZE_FALLOFF
	warm.edge_fade = 0.4
	haze.material = warm
	parent.add_child(haze)

	var dark := FogVolume.new()
	dark.name = "ShaftDust"
	# Sat inside the hole and a little narrower than it, so the volume's four
	# vertical faces are never seen against the shaft's walls — the edge of a
	# fog box against a flat rock face is the one place the box shows.
	dark.size = Vector3(hole * 1.85, 13.0, hole * 1.85)
	dark.position = Vector3(0.0, -7.5, 0.0)
	var cold := FogMaterial.new()
	cold.density = SHAFT_DENSITY
	cold.albedo = Color(0.52, 0.53, 0.56)
	cold.height_falloff = -0.28
	cold.edge_fade = 0.5
	dark.material = cold
	parent.add_child(dark)


# -------------------------------------------------------------------- dust ---

## Rock dust drifting across the floor, out of the west with the wind.
##
## This is the detail the hour is carried by. Nothing else in the vocabulary
## says "dry, hot, and nobody has been here in a while" as cheaply as lit dust
## moving slowly in one direction: the motes are additive, so they only exist
## where the sun reaches, which means the shaded side of every block is a place
## the dust visibly stops. That is a free readability cue on a map whose whole
## language is which lumps of stone you can climb.
static func _build_dust(parent: Node3D, half: float) -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(half * 1.05, 2.4, half * 1.05)
	process.direction = Vector3(0.94, 0.16, 0.3)
	process.spread = 22.0
	process.initial_velocity_min = 0.25
	process.initial_velocity_max = 0.75
	# Up, not down: dust that settles is dust, dust that rises is heat, and the
	# whole claim of this map's weather is that the floor is hot.
	process.gravity = Vector3(0.0, 0.09, 0.0)
	process.damping_min = 0.0
	process.damping_max = 0.06
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.2
	process.turbulence_noise_scale = 2.6
	process.turbulence_noise_speed = Vector3(0.07, 0.02, 0.05)
	process.scale_min = 0.05
	process.scale_max = 0.16
	process.color_ramp = _fade_ramp(Color(1.0, 0.94, 0.78), 0.55)

	var motes := GPUParticles3D.new()
	motes.name = "RockDust"
	motes.draw_pass_1 = _dot(0.34)
	motes.process_material = process
	motes.amount = 44
	motes.lifetime = 18.0
	motes.randomness = 0.85
	motes.preprocess = 18.0
	motes.position = Vector3(-half * 0.5, 2.2, 0.0)
	motes.visibility_aabb = AABB(Vector3(-half * 1.6, -2.0, -half * 1.6),
		Vector3(half * 3.2, 14.0, half * 3.2))
	parent.add_child(motes)


## What comes up out of the hole: big, slow, very faint sheets rising off the
## shaft's lip, so the drop has something coming out of it rather than being a
## black square painted on the floor.
static func _build_shaft_plume(parent: Node3D, hole: float) -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(hole * 0.85, 2.0, hole * 0.85)
	process.direction = Vector3(0.3, 1.0, 0.1)
	process.spread = 30.0
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 0.9
	process.gravity = Vector3(0.0, 0.16, 0.0)
	process.damping_min = 0.1
	process.damping_max = 0.4
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -5.0
	process.angular_velocity_max = 5.0
	process.scale_min = 1.1
	process.scale_max = 2.6
	process.color_ramp = _fade_ramp(Color(0.86, 0.84, 0.80), 0.055)

	var quad := QuadMesh.new()
	quad.size = Vector2(3.4, 3.4)
	quad.material = _sheet_material(Color(0.88, 0.86, 0.82))

	var plume := GPUParticles3D.new()
	plume.name = "ShaftPlume"
	plume.draw_pass_1 = quad
	plume.process_material = process
	plume.amount = 22
	plume.lifetime = 16.0
	plume.randomness = 0.9
	plume.preprocess = 16.0
	plume.position = Vector3(0.0, -3.0, 0.0)
	plume.visibility_aabb = AABB(Vector3(-hole * 3.0, -18.0, -hole * 3.0),
		Vector3(hole * 6.0, 30.0, hole * 6.0))
	parent.add_child(plume)


## The two dust devils: the little spinners a flat hot floor throws, one in each
## of the bands the layout leaves widest.
##
## They are a **rotational pair**, like everything else on this map that is not
## on the bisector, and for once that is not a fairness argument — it is that
## the pit is symmetric under a half turn and an atmosphere that is not looks
## like a mistake from exactly one of the two bases.
static func _build_devils(parent: Node3D, half: float, rng: RandomNumberGenerator) -> void:
	var spots := [Vector2(-half * 0.62, half * 0.18), Vector2(half * 0.62, -half * 0.18)]
	for i: int in spots.size():
		var spot: Vector2 = spots[i]
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		process.emission_ring_axis = Vector3.UP
		process.emission_ring_radius = 1.5
		process.emission_ring_inner_radius = 0.5
		process.emission_ring_height = 0.4
		process.direction = Vector3(0.0, 1.0, 0.0)
		process.spread = 12.0
		process.initial_velocity_min = 1.2
		process.initial_velocity_max = 2.6
		# The spin: a tangential force round the up axis is what makes a column
		# of dust a devil instead of a puff.
		process.tangential_accel_min = 2.2
		process.tangential_accel_max = 4.4
		process.radial_accel_min = -0.5
		process.radial_accel_max = 0.2
		process.gravity = Vector3(0.35, 0.2, 0.12)
		process.damping_min = 0.2
		process.damping_max = 0.7
		process.scale_min = 0.08
		process.scale_max = 0.24
		process.color_ramp = _fade_ramp(Color(0.98, 0.92, 0.76), 0.34)

		var devil := GPUParticles3D.new()
		devil.name = "DustDevil%d" % i
		devil.draw_pass_1 = _dot(0.4)
		devil.process_material = process
		devil.amount = 18
		devil.lifetime = 5.0 + rng.randf() * 1.5
		devil.randomness = 0.8
		devil.preprocess = 6.0
		devil.position = Vector3(spot.x, 0.25, spot.y)
		devil.visibility_aabb = AABB(Vector3(-9.0, -1.0, -9.0), Vector3(18.0, 14.0, 18.0))
		parent.add_child(devil)


## Crows over the rim. Seven, which is enough to read as birds and few enough
## that nobody counts them, circling well outside the pit so they are never
## mistaken for something a spear should be thrown at.
static func _build_crows(parent: Node3D, half: float, rng: RandomNumberGenerator) -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(half * 1.2, 4.0, half * 1.2)
	process.direction = Vector3(-0.7, 0.05, 0.71)
	process.spread = 30.0
	process.initial_velocity_min = 2.4
	process.initial_velocity_max = 4.2
	process.gravity = Vector3(0.0, 0.0, 0.0)
	process.damping_min = 0.0
	process.damping_max = 0.1
	process.scale_min = 0.5
	process.scale_max = 1.0
	process.color_ramp = _fade_ramp(Color(0.10, 0.10, 0.12), 0.85)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.3)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Torch.soft_dot()
	mat.albedo_color = Color(0.10, 0.10, 0.12)
	mat.disable_receive_shadows = true
	quad.material = mat

	var crows := GPUParticles3D.new()
	crows.name = "Crows"
	crows.draw_pass_1 = quad
	crows.process_material = process
	crows.amount = 7
	crows.lifetime = 22.0
	crows.randomness = 0.9
	crows.preprocess = 18.0 + rng.randf()
	crows.position = Vector3(0.0, 26.0, 0.0)
	crows.visibility_aabb = AABB(Vector3(-half * 2.2, 10.0, -half * 2.2),
		Vector3(half * 4.4, 30.0, half * 4.4))
	parent.add_child(crows)


## The dust churning under each work lamp. Two emitters, because the map has two
## lamps and they are the only warm light in it; the swarm *is* the beam, drawn
## by the things floating in it.
static func _build_lamp_motes(parent: Node3D, heads: Array[Vector3]) -> void:
	for i: int in heads.size():
		var head: Vector3 = heads[i]
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = 1.7
		process.direction = Vector3(0.0, -1.0, 0.0)
		process.spread = 180.0
		process.initial_velocity_min = 0.15
		process.initial_velocity_max = 0.6
		process.gravity = Vector3(0.05, -0.1, 0.0)
		process.damping_min = 0.4
		process.damping_max = 1.2
		process.scale_min = 0.04
		process.scale_max = 0.12
		process.color_ramp = _fade_ramp(Color(1.0, 0.88, 0.64), 0.6)

		var motes := GPUParticles3D.new()
		motes.name = "LampMotes%d" % i
		motes.draw_pass_1 = _dot(0.28)
		motes.process_material = process
		motes.amount = 16
		motes.lifetime = 7.0
		motes.randomness = 0.8
		motes.preprocess = 7.0
		motes.position = head + Vector3(0.0, -1.4, 0.0)
		motes.visibility_aabb = AABB(Vector3(-5.0, -5.0, -5.0), Vector3(10.0, 10.0, 10.0))
		parent.add_child(motes)


# ------------------------------------------------------------------- audio ---

static func _build_audio(parent: Node3D, half: float, hole: float) -> void:
	_loop_at(parent, "quarry", "Ambient_quarry", Vector3(0.0, 3.0, 0.0), 60.0, -6.0)
	# One per rim, so the pit has four corners you can hear.
	var edge := half + 2.0
	_loop_at(parent, "wind", "Ambient_windN", Vector3(0.0, 9.0, -edge), 26.0, -14.0)
	_loop_at(parent, "wind", "Ambient_windS", Vector3(0.0, 9.0, edge), 26.0, -14.0)
	_loop_at(parent, "wind", "Ambient_windW", Vector3(-edge, 9.0, 0.0), 26.0, -14.0)
	_loop_at(parent, "wind", "Ambient_windE", Vector3(edge, 9.0, 0.0), 26.0, -14.0)
	# On the lip, not down the hole: the point is to be heard by somebody
	# standing next to the drop, which is exactly where it is dangerous to be.
	_loop_at(parent, "shaft", "Ambient_shaft", Vector3(0.0, -1.0, 0.0),
		hole + 5.0, -11.0)
	_loop_at(parent, "plant", "Ambient_plant", Vector3(-34.0, 12.0, 34.0), 30.0, -20.0)


## One positioned loop, or nothing at all if its file is not on disk.
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


# --------------------------------------------------------------- materials ---

## A billboarded additive dot of `size` metres, on the texture every flame,
## firefly and midge in the game already shares — so there is one of it in
## memory whatever else is on screen.
static func _dot(size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Torch.soft_dot()
	mat.disable_receive_shadows = true
	quad.material = mat
	return quad


## A big soft sheet, mixed rather than added. Additive dust over a pale floor in
## sunlight blows out to white; mix leaves it as air.
static func _sheet_material(tint: Color) -> StandardMaterial3D:
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
	# Sheets over a hole would sort-flicker against each other every time the
	# camera turned; without depth writes they simply accumulate.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat


## In at birth, out at death, flat in between and capped at `peak` — so nothing
## ever pops, and a sheet of dust never gets more opaque than it was told to.
static func _fade_ramp(tint: Color, peak: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(tint.r, tint.g, tint.b, 0.0))
	gradient.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	gradient.add_point(0.18, Color(tint.r, tint.g, tint.b, peak))
	gradient.add_point(0.78, Color(tint.r, tint.g, tint.b, peak * 0.92))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp
