class_name LightningBolt
extends Node3D
## The Elder's bolt, from the hand to whatever it hit. Way over the top, which
## is the requirement and not a flourish (D-038).
##
## The *rule* it is drawn to is the one `SpearTrail` was written to: this is
## light, not a surface. Everything here is unshaded and additively blended, so
## a bolt over Whisperbloom's torch-lit night and a bolt over Rust's noon are
## both brighter than what is behind them, rather than a grey stripe that
## happens to be pale.
##
## **It is an `ImmediateMesh`, not a particle system**, for the reason the spear
## trail gives at length and one more of its own. A stroke of lightning is a
## *continuous* jagged line, and a stream of billboards along one is a dotted
## line of blobs; more to the point, the whole read of the effect is that the
## shape changes every other frame, and re-emitting a particle system at 30 Hz
## costs far more than rebuilding a few hundred vertices. One mesh holds the
## core, the glow and every branch.
##
## Nothing here decides anything. The host has already ruled on the shot by the
## time this exists (`GubCombat._host_cast_lightning`); every peer builds its own
## copy from the same two points and the same verdict, and those are the only
## things that travel. The jitter is deliberately *not* seeded to agree across
## peers — nobody can see two screens at once, and a shared seed would be a
## synchronisation obligation bought for nothing.
##
## ## What it costs
##
## Per bolt, for the fifth of a second it is a bolt:
##
##   * one `ImmediateMesh` — ten surfaces, ~450 vertices, rebuilt 7 times;
##   * two `OmniLight3D`s (the hand and the impact), both dead by 0.16 s;
##   * one `CPUParticles3D` burst of 48 sparks, one-shot, gone by 0.7 s;
##   * one unshaded quad for the scorch, faded out with the sparks.
##
## The lights are the part with a real cost, and they are why the flash is
## *brief* rather than merely bright: two Elders firing at once is four extra
## dynamic lights for a sixth of a second, which is a quarter of what the
## island's fifteen torches cost, for a sixtieth of the time. Neither casts a
## shadow — a shadow-casting point light that exists for six frames is a cubemap
## render for detail nobody can resolve.
##
## The particles are CPU rather than GPU on purpose. Forty-eight of them is
## nothing to simulate, they need no compute dispatch to start, and they emit on
## the *first* frame rather than the second — which matters when the whole
## effect is over in thirteen.

## How long the stroke itself is on screen. Short. A bolt that lingers reads as
## a beam, and what sells lightning is that it is gone before you have finished
## flinching.
const STROKE_LIFE := 0.22
## How long the node survives after that, so the sparks and the scorch can
## finish. Everything visible is faded rather than switched off.
const TOTAL_LIFE := 1.05
## How often the stroke is re-jittered. At 0.03 s that is a new shape roughly
## every other frame at 60 Hz — fast enough to flicker, slow enough that the eye
## reads each shape as a shape rather than as noise.
const REDRAW := 0.03

## How many segments the main stroke is broken into. The jitter is applied at
## the joints, so this is also how *kinked* the bolt is: at 18 over a typical
## fifteen-metre shot the kinks are a metre apart, which is the scale that reads
## as lightning rather than as a wobbly rope.
const SEGMENTS := 18
## Sideways displacement at the joints, as a fraction of the bolt's own length,
## tapering to nothing at both ends. Both ends are pinned on purpose: the bolt
## has to leave the hand and arrive at the thing it killed, and a stroke that
## misses either by half a metre is a stroke that came from nowhere.
const JITTER := 0.055
## The stroke is drawn twice over — a white core inside a fat coloured glow — at
## a constant width. Unlike the spear's trail it does *not* taper: a bolt is as
## thick where it lands as where it left, which is most of what tells the two
## effects apart at a glance.
const CORE_WIDTH := 0.052
const GLOW_WIDTH := 0.190

## How many forks come off the main stroke, how far each reaches as a fraction
## of the distance still to run, and how loose they are. Branches are what make
## a bolt read as lightning rather than as a laser, and they are deliberately
## generous — this is the "over the top" the brief asked for.
const BRANCHES := 4
const BRANCH_REACH := 0.38
const BRANCH_SEGMENTS := 6
const BRANCH_JITTER := 0.16
const BRANCH_WIDTH_SCALE := 0.55
const BRANCH_DIM := 0.7

## White-hot at the centre with a violet fringe. The violet is the Elder's own
## `#2F1D45` robe taken to full value — the bolt has to look like it came out of
## *that* wizard — and the core is almost colourless, because the one thing
## every photograph of lightning agrees on is that the middle of it is white.
const CORE_COLOUR := Color(1.00, 0.98, 1.00)
const GLOW_COLOUR := Color(0.66, 0.48, 1.00)
## How far over white each of those is driven. The blend is additive and the
## environment tonemaps with ACES at a white point of 6.0, so values that sound
## bright do very little through that curve — the same lesson
## `SpearProjectile.GLOW_BOOST` records after 1.25 turned out to be invisible.
##
## It has to live on the **material** rather than on the vertices: a mesh's
## colour array is eight bits a channel, so a vertex colour cannot carry a value
## over 1 at all. The vertices carry the per-frame fade in the alpha and the
## material carries the brightness, which is why there are two materials here
## and not one with the colour baked into the strip.
const CORE_ENERGY := 3.0
const GLOW_ENERGY := 1.6

## The blinding flash, at both ends. Two lights and not one: the hand is what
## says *who* fired and the impact is what says *where it landed*, and in a fight
## those are frequently not on the same screen.
##
## These were four times this to begin with and it was a mistake worth recording,
## because it looked *better* on paper: at 26 over 15 m the impact light blew the
## whole frame to white and took the thing it was supposed to be lighting with
## it. A flash that hides the body being thrown is not a flash, it is a wipe —
## the point of the burst is to make you look at the kill, and the kill has to
## survive being looked at. Checked at `out/lightning.png`.
const FLASH_ENERGY := 14.0
const FLASH_RANGE := 10.0
const MUZZLE_ENERGY := 5.0
const MUZZLE_RANGE := 5.0
const FLASH_COLOUR := Color(0.86, 0.80, 1.00)
## The flash is over well before the stroke is. A light that fades out with the
## bolt reads as a lamp being switched off; one that is gone first reads as a
## detonation the stroke is the after-image of.
const FLASH_LIFE := 0.16

## The impact burst.
##
## `SPARK_SPREAD` is what stops it being one object. Forty-eight additive quads
## all emitted from the same point on the same frame is not a shower of sparks,
## it is a white ball — they only become sparks once they have separated, and at
## sixty frames a second the first three frames are the ones anybody actually
## sees. So they start scattered through a small sphere and leave fast.
const SPARKS := 40
const SPARK_SPEED := 16.0
const SPARK_SPREAD := 0.45
const SPARK_LIFE := 0.7
## Dimmer than the stroke, and much dimmer than it first was. A spark is a
## fleck of the bolt, not a second bolt.
const SPARK_ENERGY := 1.30
## How big one spark is, in metres, as the quad's own size rather than as a
## particle scale. `scale_amount_min/max` was tried first and the sparks came out
## half a metre across regardless of it — so the size lives on the mesh, where it
## is unambiguous, and the particle scale is left doing the one thing it is
## reliable for, which is varying it.
const SPARK_SIZE := 0.16
## The scorch: how wide, and how long before it is gone. It fades with the
## sparks rather than sticking around, because a permanent mark per bolt would
## litter a map that already carries a hundred and fifty drops in a long match.
const SCORCH_RADIUS := 0.85
const SCORCH_LIFE := 0.9
const SCORCH_ALPHA := 0.85

## How hard the impact shakes a camera standing on top of it, and how far away
## it is felt at all. The caster gets its own, smaller kick — firing this should
## feel like holding it, not like being hit by it.
const SHAKE_AT_IMPACT := 1.9
const SHAKE_RADIUS := 16.0
const SHAKE_CASTER := 0.55
## Faster than the default 6.0, because this shake is a single hard slam rather
## than the rolling one a death gives.
const SHAKE_DECAY := 9.0

## How loud the two thunder voices are against each other. The crack carries the
## transient; the roll is pulled down under it, because the balance between them
## is the difference between "that landed near me" and "there is weather
## somewhere" (see `tools/make_sfx.py`).
const CRACK_DB := 4.0
const ROLL_DB := -4.0

var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _next_redraw: float = 0.0

var _mesh: ImmediateMesh
var _stroke: MeshInstance3D
var _core_material: StandardMaterial3D
var _glow_material: StandardMaterial3D
var _flash: OmniLight3D
var _muzzle: OmniLight3D
var _scorch_material: StandardMaterial3D


## Fire one bolt, on this peer, from `from` to `to`.
##
## `normal` is the surface it landed on, or `Vector3.ZERO` when it landed on a
## Gub or on nothing — there is only something to scorch in the first case.
## `caster` is who fired, so the shake can tell "I did that" from "that happened
## next to me".
##
## Every peer calls this with the same arguments from
## `GubCombat._do_cast_lightning`, which is what makes the bolt an event
## everybody saw rather than a private animation on the shooter's machine.
static func strike(parent: Node, from: Vector3, to: Vector3, normal: Vector3,
		caster: Gub) -> LightningBolt:
	var bolt := LightningBolt.new()
	bolt.name = "Bolt_%d" % Time.get_ticks_msec()
	bolt._from = from
	bolt._to = to
	parent.add_child(bolt)
	bolt._build(normal)
	bolt._thunder()
	bolt._shake(caster)
	return bolt


func _build(normal: Vector3) -> void:
	# World space, like `SpearTrail` and for the same reason: the geometry is
	# built from two world points and must not then be transformed again by
	# whatever the spawn container happens to be sitting at.
	top_level = true
	global_transform = Transform3D.IDENTITY

	_core_material = _make_material(CORE_COLOUR, CORE_ENERGY)
	_glow_material = _make_material(GLOW_COLOUR, GLOW_ENERGY)
	_stroke = MeshInstance3D.new()
	_stroke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh = ImmediateMesh.new()
	_stroke.mesh = _mesh
	add_child(_stroke)
	_redraw(1.0)

	_flash = _make_light(_to, FLASH_ENERGY, FLASH_RANGE)
	_muzzle = _make_light(_from, MUZZLE_ENERGY, MUZZLE_RANGE)
	_build_sparks(normal)
	if normal.length_squared() > 0.001:
		_build_scorch(normal)


## Additive, unshaded, double-sided, vertex-coloured. The colour and its
## brightness live here; the vertices carry only the fade — see CORE_ENERGY.
func _make_material(colour: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	# Depth-tested like everything else. A bolt visible through a hill would
	# announce every fight on the map — and worse, it would contradict the rule
	# the whole design of this weapon rests on, which is that cover works.
	material.no_depth_test = false
	material.albedo_color = Color(colour.r * energy, colour.g * energy,
		colour.b * energy, 1.0)
	return material


func _make_light(at: Vector3, energy: float, radius: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = FLASH_COLOUR
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = false
	light.position = at
	add_child(light)
	return light


func _build_sparks(normal: Vector3) -> void:
	var sparks := CPUParticles3D.new()
	sparks.position = _to
	sparks.amount = SPARKS
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.lifetime = SPARK_LIFE
	sparks.local_coords = false
	sparks.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	# Thrown back off a surface when there is one, and thrown everywhere when
	# there is not: a body takes a bolt and the sparks come off it in every
	# direction at once.
	if normal.length_squared() > 0.001:
		sparks.direction = normal
		sparks.spread = 62.0
	else:
		sparks.direction = Vector3.UP
		sparks.spread = 180.0
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = SPARK_SPREAD
	sparks.initial_velocity_min = SPARK_SPEED * 0.45
	sparks.initial_velocity_max = SPARK_SPEED
	sparks.gravity = Vector3.DOWN * 16.0
	sparks.damping_min = 2.0
	sparks.damping_max = 6.0
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.5

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * SPARK_SIZE
	quad.material = _make_material(CORE_COLOUR, SPARK_ENERGY)
	(quad.material as StandardMaterial3D).billboard_mode = \
		BaseMaterial3D.BILLBOARD_ENABLED
	sparks.mesh = quad

	# Sparks cool as they fall: white at the impact, violet on the way down,
	# nothing by the time they would have landed.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.97, 1.0, 1.0))
	ramp.set_color(1, Color(GLOW_COLOUR.r, GLOW_COLOUR.g, GLOW_COLOUR.b, 0.0))
	ramp.add_point(0.35, Color(0.85, 0.72, 1.0, 0.9))
	sparks.color_ramp = ramp
	add_child(sparks)
	sparks.emitting = true


## A violet burn on whatever was hit. Pushed a centimetre off the surface along
## its own normal, because a quad coplanar with the ground is a quad that
## z-fights with it.
func _build_scorch(normal: Vector3) -> void:
	var scorch := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * (SCORCH_RADIUS * 2.0)
	scorch.mesh = quad
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_scorch_material = StandardMaterial3D.new()
	_scorch_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_scorch_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_scorch_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_scorch_material.albedo_color = Color(0.55, 0.40, 0.95, SCORCH_ALPHA)
	scorch.material_override = _scorch_material

	add_child(scorch)
	scorch.global_position = _to + normal * 0.01
	# `look_at` refuses an up vector parallel to what it is aiming along, and a
	# bolt into flat ground is exactly that case.
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	scorch.look_at(scorch.global_position + normal, up)


## Two voices at the impact, 3D so they position properly and pitch-varied so
## two bolts in one fight do not machine-gun.
##
## Both at the impact rather than one at each end, deliberately: thunder is the
## sound of the air the bolt tore, and the loudest part of that is where it
## stopped. The hand gets the muzzle *light* instead, which is the tell that
## belongs there.
func _thunder() -> void:
	AudioDirector.play_3d_varied(AudioDirector.THUNDER_CRACK, _to, 0.10, CRACK_DB)
	AudioDirector.play_3d_varied(AudioDirector.THUNDER_ROLL, _to, 0.14, ROLL_DB)


## Kick the caster's camera, and anyone standing near where it landed.
##
## Only ever this client's own camera — `GubCamera` shuts itself down on every
## copy but the owner's, so shaking somebody else's rig would be shaking a node
## attached to no viewport. This runs on every peer, so between them every
## player who should feel it does.
##
## `GubCamera.shake` already multiplies by the `camera_shake` user setting, so
## somebody who has turned it down gets what they asked for and nothing here has
## to know the setting exists.
func _shake(caster: Gub) -> void:
	var local := MatchState.local_gub()
	if local == null:
		return
	var rig := local.get_node_or_null("CameraRig") as GubCamera
	if rig == null:
		return
	var strength := SHAKE_CASTER if caster != null and caster == local else 0.0
	# Falls off linearly to nothing at SHAKE_RADIUS. The larger of the two wins
	# rather than the two summing, so an Elder who lands one at its own feet is
	# shaken once and hard rather than twice.
	var distance := local.global_position.distance_to(_to)
	if distance < SHAKE_RADIUS:
		strength = maxf(strength, SHAKE_AT_IMPACT * (1.0 - distance / SHAKE_RADIUS))
	if strength > 0.0:
		rig.shake(strength, SHAKE_DECAY)


func _process(delta: float) -> void:
	_age += delta
	if _age >= TOTAL_LIFE:
		queue_free()
		return

	# The stroke: re-jittered on a fixed cadence and faded over its own life, so
	# the last shapes are ghosts of the first. Between redraws it deliberately
	# holds still — that hold is what makes the flicker read as a flicker rather
	# than as a smear.
	if _age < STROKE_LIFE:
		if _age >= _next_redraw:
			_next_redraw = _age + REDRAW
			_redraw(1.0 - pow(_age / STROKE_LIFE, 2.2))
	elif _stroke.visible:
		_stroke.visible = false

	# The flash is the first thing to go, and it goes fast enough to punch.
	if _flash != null:
		var left := 1.0 - clampf(_age / FLASH_LIFE, 0.0, 1.0)
		var curve := left * left
		_flash.light_energy = FLASH_ENERGY * curve
		_muzzle.light_energy = MUZZLE_ENERGY * curve
		if left <= 0.0:
			_flash.queue_free()
			_muzzle.queue_free()
			_flash = null
			_muzzle = null

	if _scorch_material != null:
		var fade := 1.0 - clampf(_age / SCORCH_LIFE, 0.0, 1.0)
		_scorch_material.albedo_color.a = SCORCH_ALPHA * fade * fade


## Repaint the whole stroke at `brightness`: the glow, the core, and the forks.
##
## Drawn glow-first so the core lands on top of it. With an additive blend the
## order does not change the result, but it does change what a reader expects,
## and a bolt whose white middle is drawn last is a bolt whose white middle is
## the thing being drawn.
func _redraw(brightness: float) -> void:
	_mesh.clear_surfaces()
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera != null else _from

	var path := jagged(_from, _to, SEGMENTS, JITTER)
	_ribbon(path, eye, GLOW_WIDTH, _glow_material, brightness)
	_ribbon(path, eye, CORE_WIDTH, _core_material, brightness)

	# Forks leave from a joint partway along and die short, in a direction that
	# is mostly onward and partly sideways — a branch that turns straight back
	# on itself reads as a mistake rather than as a fork.
	if path.size() < 6:
		return
	for i in BRANCHES:
		var start: Vector3 = path[randi_range(2, path.size() - 3)]
		var onward := _to - start
		var reach := onward.length() * BRANCH_REACH
		if reach < 0.4:
			continue
		var sideways := onward.normalized().cross(Vector3.UP)
		if sideways.length_squared() < 0.001:
			sideways = Vector3.RIGHT
		var aim := onward.normalized() \
			+ sideways.normalized() * randf_range(-1.1, 1.1) \
			+ Vector3.UP * randf_range(-0.5, 0.5)
		var fork := jagged(start, start + aim.normalized() * reach,
			BRANCH_SEGMENTS, BRANCH_JITTER)
		_ribbon(fork, eye, GLOW_WIDTH * BRANCH_WIDTH_SCALE, _glow_material,
			brightness * BRANCH_DIM)
		_ribbon(fork, eye, CORE_WIDTH * BRANCH_WIDTH_SCALE, _core_material,
			brightness * BRANCH_DIM)


## A jagged path between two points: `count` segments, displaced sideways at the
## joints by up to `amount` of the whole length, tapering to nothing at both ends
## so the bolt starts in the hand and finishes in the target.
##
## Static and public because the hand's crackle is made of the same stuff
## (`HandCrackle`), and two generators for one look is two things to keep in
## step. The displacement is taken in the plane across the run rather than along
## world axes, so a vertical bolt kinks exactly as much as a horizontal one.
static func jagged(from: Vector3, to: Vector3, count: int,
		amount: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var run := to - from
	var length := run.length()
	if length < 0.001 or count < 2:
		out.push_back(from)
		out.push_back(to)
		return out

	var forward := run / length
	var side := forward.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = forward.cross(Vector3.RIGHT)
	side = side.normalized()
	var other := forward.cross(side).normalized()

	var spread := length * amount
	for i in count + 1:
		var t := float(i) / float(count)
		var point := from + run * t
		# `sin(PI * t)` is zero at both ends and one in the middle. That pinning
		# is the whole reason the bolt looks attached to the hand it left.
		var taper := sin(PI * t)
		point += side * randf_range(-spread, spread) * taper
		point += other * randf_range(-spread, spread) * taper
		out.push_back(point)
	return out


## One camera-facing ribbon along `path`, at a constant width, with `alpha` in
## the vertex colour and the brightness in the material.
##
## Widened across the view like the spear's trail, so the stroke faces the
## camera however it is running.
func _ribbon(path: PackedVector3Array, eye: Vector3, half_width: float,
		material: StandardMaterial3D, alpha: float) -> void:
	if path.size() < 2 or alpha <= 0.0:
		return
	var tint := Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
	for i in path.size():
		var point := path[i]
		var along: Vector3 = path[i + 1] - point if i < path.size() - 1 \
			else point - path[i - 1]
		if along.length_squared() < 0.000001:
			continue
		var side := along.normalized().cross((point - eye).normalized())
		if side.length_squared() < 0.000001:
			continue
		side = side.normalized() * half_width
		_mesh.surface_set_color(tint)
		_mesh.surface_add_vertex(point + side)
		_mesh.surface_set_color(tint)
		_mesh.surface_add_vertex(point - side)
	_mesh.surface_end()
