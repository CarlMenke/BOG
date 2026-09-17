extends Node3D
## The Elder: a Bog, plus `art/skins/elder/robe.tscn` bound onto its own skeleton.
## Development tool, not shipped.
##
##   Godot --path . --resolution 1100x900 --script tools/snapshot.gd -- \
##       res://tools/preview_elder.tscn out/elder.png <ticks> <view> <light> [clip] [from] [to]
##
##   view:   mid | back | far | pair | sheet
##   light:  studio | dusk | afternoon   ("noon" still accepted for afternoon)
##
## `from` and `to` are the sheet's window in the clip's own seconds. `to` was
## always the end of the clip, which is the right default for a cycle and the
## wrong one for a one-shot: the Elder's `Cast` is 2.283 s of which the graph
## plays 0.467-1.600, and five samples of the whole file put one of them in the
## cast and four in a Bog standing about (D-064). Left off, it is the end of the
## clip and the sheet is what it always was.
##
## This scene is not only a camera. **It is the check that the robe binds**, and
## it does the attach exactly the way a game would: load the Bog, find its
## `Skeleton3D` (`bog.gd:_equip_spear` already does `find_child("Skeleton3D",
## true, false)`, and `HeldGear.attach_to` is the precedent for reaching into
## it), take the `MeshInstance3D` out of the Elder scene and re-parent it under
## that skeleton with its `Skin` intact. Nothing copies an animation and nothing
## duplicates a bone. The bind names are printed and resolved against the target
## skeleton on the way past, so a renamed bone fails here with a list
## rather than in game with a robe lying on the floor.
##
## `light` is not decoration either. The brief is a material, and the two places
## it has to survive are Whisperbloom Hollow's torch-lit night and Rust's late
## afternoon.
## Both are built from the *shipped* resources and constants — `arena_env.tres`
## with `arena.gd`'s moon and `torch.gd`'s flame, `rust_env.tres` with the exact
## `Sun` transform out of `rust.tscn` — so what this renders is the light the map
## renders, not an approximation of it that could flatter the purple.
##
## `studio` is the third: a neutral grey room, for judging the cloth itself
## without a map's colour cast on it.

const BOG := "res://art/bog/BOG.fbx"
const ELDER := "res://art/skins/elder/robe.tscn"
const ELDER_MESH := "Elder"

## Whisperbloom, from `scripts/world/arena.gd` and `scripts/world/torch.gd`.
const ISLAND_ENV := "res://resources/config/arena_env.tres"
const MOON_DIRECTION := Vector3(-0.42, 0.38, -0.82)
const MOON_COLOR := Color(0.62, 0.72, 1.0)
const MOON_ENERGY := 0.30
const TORCH_COLOR := Color(1.0, 0.63, 0.30)
const TORCH_ENERGY := 2.6
const TORCH_RANGE := 10.5
const TORCH_ATTENUATION := 1.7

## Rust, from `scenes/world/maps/rust.tscn`. The basis is copied rather than
## re-derived: it is row-major in the `.tscn` and `Transform3D` takes columns, so
## re-typing it is how a sun ends up pointing at the sky.
##
## These are Rust's *late afternoon* — the atmosphere pass (D-059) dropped the sun
## from 50 degrees to 36.46, which is the elevation measured off the HDR panorama
## the map's sky is now made of, and cooled it toward the horizon. Copied again
## rather than read from the scene: this tool renders the Elder against two fixed
## lighting set-ups on purpose, so that two runs a month apart are comparable, and
## loading the map to ask it would make every render depend on the map's edit
## history. The cost of that choice is exactly this — it has to be copied across
## by hand when the scene moves, and it was stale for one commit.
const RUST_ENV := "res://resources/config/rust_env.tres"
const SUN_BASIS := Basis(
	Vector3(0.62932, 0.0, -0.77715),
	Vector3(-0.46178, 0.80429, -0.37397),
	Vector3(0.62505, 0.59423, 0.50616))
const SUN_COLOR := Color(1.0, 0.93, 0.82)
const SUN_ENERGY := 1.35

const FAR_DISTANCE := 20.0
## A long lens on the far shot. The *distance* is what the question is about —
## 20 m is where a silhouette has to be recognised — and a 45-degree lens puts
## a 2 m subject across a ninth of the frame, which is the right answer in game
## and useless on a page somebody is judging a material from. 26 degrees is the
## same 20 m, framed so it can be looked at.
const FAR_FOV := 26.0
const MID_DISTANCE := 4.4
const SHEET_SAMPLES := 5
const SHEET_SPACING := 1.6

var _view: String = "mid"
var _light: String = "studio"
var _clip: String = "Idle"
var _time: float = 0.0
## The far end of the `sheet` window, or -1 for "the end of the clip".
var _until: float = -1.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 4:
		_view = args[3]
	if args.size() >= 5:
		_light = args[4]
	if args.size() >= 6:
		_clip = args[5]
	if args.size() >= 7:
		_time = float(args[6])
	if args.size() >= 8:
		_until = float(args[7])
	print("preview_elder: view=%s light=%s clip=%s from=%.2f to=%s"
		% [_view, _light, _clip, _time,
			"end" if _until < 0.0 else "%.2f" % _until])

	_build_light()
	match _view:
		"sheet":
			_build_sheet()
		"far":
			_build_far()
		"pair":
			_build_pair()
		_:
			_build_single()


# --------------------------------------------------------------- the Elder ---

## A Bog wearing the robe, posed, returned with its own facing worked out.
func _make_elder(clip: String, time: float, verbose: bool) -> Node3D:
	var bog := (load(BOG) as PackedScene).instantiate() as Node3D
	add_child(bog)
	var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		push_error("preview_elder: the Bog has no Skeleton3D")
		return bog

	var wardrobe := (load(ELDER) as PackedScene).instantiate() as Node3D
	var robe := wardrobe.find_child(ELDER_MESH, true, false) as MeshInstance3D
	if robe == null:
		push_error("preview_elder: %s has no MeshInstance3D called '%s'" % [ELDER, ELDER_MESH])
		wardrobe.free()
		return bog

	if verbose:
		_report_bind(skeleton, robe)

	# The attach itself. The mesh keeps its `skin`; `skeleton` is left at the
	# default `NodePath("..")`, which now means the Bog's skeleton, and the
	# transform is cleared because a skinned mesh is drawn in skeleton space and
	# a leftover parent transform is a silent double-move waiting to happen.
	# Godot warns about an owner from another scene the moment the node changes
	# parent, and an owner is of no use to something being re-parented at runtime.
	robe.owner = null
	robe.get_parent().remove_child(robe)
	skeleton.add_child(robe)
	robe.transform = Transform3D.IDENTITY
	robe.skeleton = NodePath("..")
	wardrobe.free()

	_pose(bog, clip, time)
	return bog


func _report_bind(skeleton: Skeleton3D, robe: MeshInstance3D) -> void:
	print("preview_elder: target Skeleton3D has %d bones" % skeleton.get_bone_count())
	var skin := robe.skin
	if skin == null:
		push_error("preview_elder: the robe has no Skin — it cannot bind to anything")
		return
	var names := []
	var unresolved := []
	for i in skin.get_bind_count():
		var bind_name := skin.get_bind_name(i)
		if bind_name == "":
			unresolved.append("bind %d has no name (index %d)" % [i, skin.get_bind_bone(i)])
			continue
		names.append(bind_name)
		if skeleton.find_bone(bind_name) < 0:
			unresolved.append(bind_name)
	print("preview_elder: robe skin has %d binds, by name: %s"
		% [skin.get_bind_count(), ", ".join(names)])
	if unresolved.is_empty():
		print("preview_elder: BIND OK — every bind name resolves against the Bog's skeleton")
	else:
		push_error("preview_elder: BIND FAILED — %s" % ", ".join(unresolved))


func _pose(model: Node3D, clip: String, time: float) -> void:
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null or not player.has_animation(clip):
		push_error("preview_elder: no clip '%s' (has %s)"
			% [clip, ", ".join(player.get_animation_list()) if player else "no player"])
		return
	player.play(clip)
	player.advance(time)
	player.pause()


func _make_bog(clip: String, time: float) -> Node3D:
	var bog := (load(BOG) as PackedScene).instantiate() as Node3D
	add_child(bog)
	_pose(bog, clip, time)
	return bog


## Which way the body is actually pointing, asked of the rig rather than assumed.
##
## The model's own facing depends on how `import_clip.gd` aligned the clips and on
## the 180-degree turn `bog.tscn` puts on the instance, and a preview that
## guessed wrong would frame the back of the head and call it a front view. The
## line between the two hip joints is the one pair of joints that stays put while
## the arms and torso animate — the same measurement `import_clip.gd` aligns the
## clips on — so the facing is derived from it: with up = +Y, a body's left is
## up x forward, so forward is the hip line turned a quarter turn.
func _facing(model: Node3D) -> Vector3:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var left := skeleton.find_bone("mixamorig_LeftUpLeg")
	var right := skeleton.find_bone("mixamorig_RightUpLeg")
	if left < 0 or right < 0:
		return Vector3.BACK
	var a := skeleton.global_transform * skeleton.get_bone_global_pose(left).origin
	var b := skeleton.global_transform * skeleton.get_bone_global_pose(right).origin
	var across := (b - a)
	across.y = 0.0
	if across.length() < 0.01:
		return Vector3.BACK
	across = across.normalized()
	return Vector3(across.z, 0.0, -across.x)


# ------------------------------------------------------------------ views ---

func _build_single() -> void:
	var elder := _make_elder(_clip, _time, true)
	var forward := _facing(elder)
	var side := -forward if _view == "back" else forward
	_ground(12.0)
	_camera(side * MID_DISTANCE + Vector3(0.0, 1.15, 0.0), Vector3(0.0, 1.00, 0.0), 42.0)
	_caption("%s  %s  %s %.2fs" % [_view, _light, _clip, _time], Vector3(0.0, 2.45, 0.0))


func _build_pair() -> void:
	var elder := _make_elder(_clip, _time, true)
	elder.position = Vector3(0.75, 0.0, 0.0)
	var bog := _make_bog(_clip, _time)
	bog.position = Vector3(-0.75, 0.0, 0.0)
	var forward := _facing(elder)
	_ground(12.0)
	_camera(forward * (MID_DISTANCE + 0.9) + Vector3(0.0, 1.2, 0.0),
		Vector3(0.0, 1.0, 0.0), 42.0)
	_caption("Bog / Elder  %s  %s" % [_light, _clip], Vector3(0.0, 2.5, 0.0))


## Both, at the range a silhouette has to carry at. The plain Bog is in frame on
## purpose: "can you see it" is not the question at 20 m, "can you tell which one
## it is" is.
func _build_far() -> void:
	var elder := _make_elder(_clip, _time, true)
	elder.position = Vector3(1.4, 0.0, 0.0)
	var bog := _make_bog(_clip, _time)
	bog.position = Vector3(-1.4, 0.0, 0.0)
	var forward := _facing(elder)
	_ground(70.0)
	_camera(forward * FAR_DISTANCE + Vector3(0.0, 1.6, 0.0), Vector3(0.0, 1.1, 0.0), FAR_FOV)
	_caption("Bog / Elder at %.0f m   (%.0f-degree lens)   %s"
		% [FAR_DISTANCE, FAR_FOV, _light], Vector3(0.0, 2.75, 0.0))


## A contact sheet of one clip, which is where the hem is judged: five Elders
## across the cycle, orthographic so every one of them is seen from the same
## angle, over a ground line the hem either clears or does not.
func _build_sheet() -> void:
	var probe := (load(BOG) as PackedScene).instantiate()
	var player := probe.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var length: float = player.get_animation(_clip).length if player.has_animation(_clip) else 1.0
	probe.free()
	var from: float = _time
	var to: float = length if _until < 0.0 else minf(_until, length)
	var span: float = maxf(to - from, 0.01)

	var x := -SHEET_SPACING * (SHEET_SAMPLES - 1) * 0.5
	var forward := Vector3.BACK
	# The last sample lands *on* `to` when a window was asked for and one step
	# short of it when it was not, which is `tools/preview_bog.gd`'s rule and
	# is there for the same reason: a looping clip's last frame is its first.
	var steps := float(SHEET_SAMPLES if _until < 0.0 else maxi(SHEET_SAMPLES - 1, 1))
	for i in SHEET_SAMPLES:
		var t: float = from + span * float(i) / steps
		var elder := _make_elder(_clip, t, i == 0)
		elder.position = Vector3(x, 0.0, 0.0)
		x += SHEET_SPACING
		if i == 0:
			forward = _facing(elder)
		var stamp := Label3D.new()
		stamp.text = "%.2f" % t
		stamp.font_size = 56
		stamp.pixel_size = 0.0020
		stamp.outline_size = 16
		stamp.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		stamp.position = Vector3(0.0, 2.30, 0.0)
		elder.add_child(stamp)

	_ground_line()
	_caption("%s   %.2f-%.2f s of %.2f   %s" % [_clip, from, to, length, _light],
		Vector3(0.0, 2.62, 0.0))

	var view := get_viewport().get_visible_rect().size
	var aspect: float = view.x / maxf(view.y, 1.0)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(3.4, (SHEET_SPACING * float(SHEET_SAMPLES - 1) + 1.9) / aspect)
	cam.near = 0.05
	cam.far = 120.0
	cam.position = Vector3(0.0, 1.30, 0.0) + forward * 30.0
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.30, 0.0), Vector3.UP)
	cam.make_current()


# ------------------------------------------------------------- furnishings ---

func _camera(from: Vector3, at: Vector3, fov: float) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.near = 0.05
	cam.far = 400.0
	cam.position = from
	add_child(cam)
	cam.look_at(at, Vector3.UP)
	cam.make_current()


func _caption(text: String, where: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 72
	label.pixel_size = 0.0020
	label.position = where
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Outlined, because the same white caption is read against Rust's pale sand
	# sky in one shot and Whisperbloom's black undergrowth in the next.
	label.outline_size = 20
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	add_child(label)


func _ground(size: float) -> void:
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size, size)
	plane.mesh = mesh
	var mat := StandardMaterial3D.new()
	# Deliberately neutral and mid-dark in all three lights: a ground that
	# carried a colour of its own would bounce it into the robe and the material
	# being judged would be partly the floor's.
	mat.albedo_color = Color(0.20, 0.19, 0.19)
	mat.roughness = 0.95
	plane.material_override = mat
	add_child(plane)


func _ground_line() -> void:
	# A bar rather than a plane: the sheet's camera is level and orthographic, so
	# a floor at y = 0 would be exactly edge-on and invisible, and "are the feet
	# planted, does the hem clear the floor" is what the sheet is for.
	var bar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(140.0, 0.02, 0.02)
	bar.mesh = box
	bar.position = Vector3(0.0, 0.0, -0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.44, 0.48)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar.material_override = mat
	add_child(bar)


func _build_light() -> void:
	match _light:
		"dusk":
			_world(ISLAND_ENV)
			# D-009: the sky shader draws the moon at the light's own direction,
			# so this DirectionalLight3D *is* the moon, and it is placed and
			# aimed rather than given a rotation, for the reason `arena.gd` says.
			var moon := DirectionalLight3D.new()
			add_child(moon)
			moon.position = MOON_DIRECTION.normalized() * 80.0
			moon.look_at(Vector3.ZERO, Vector3.UP)
			moon.light_color = MOON_COLOR
			moon.light_energy = MOON_ENERGY
			moon.light_specular = 0.35
			moon.shadow_enabled = true
			moon.directional_shadow_max_distance = 90.0
			# One torch, at the distance a torch actually stands from something
			# you are looking at: `torch.gd`'s light, unflickered so two renders
			# of the same frame agree.
			var torch := OmniLight3D.new()
			add_child(torch)
			torch.position = Vector3(2.6, 1.5, 3.0)
			torch.light_color = TORCH_COLOR
			torch.light_energy = TORCH_ENERGY
			torch.omni_range = TORCH_RANGE
			torch.omni_attenuation = TORCH_ATTENUATION
		# "noon" is kept as an alias: it is what this mode was called for the
		# whole of the Elder's development, and it is in the shell history of
		# everyone who has rendered one.
		"afternoon", "noon":
			_world(RUST_ENV)
			var sun := DirectionalLight3D.new()
			add_child(sun)
			sun.transform = Transform3D(SUN_BASIS, Vector3(-1.0, 24.0, -5.0))
			sun.light_color = SUN_COLOR
			sun.light_energy = SUN_ENERGY
			sun.light_specular = 0.4
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 90.0
			sun.directional_shadow_blend_splits = true
		_:
			_studio()


func _world(path: String) -> void:
	var world := WorldEnvironment.new()
	world.environment = load(path) as Environment
	add_child(world)


func _studio() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.13, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.66)
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	world.environment = env
	add_child(world)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-34.0, -34.0, 0.0)
	key.light_energy = 1.55
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12.0, 148.0, 0.0)
	fill.light_energy = 0.7
	fill.light_color = Color(0.62, 0.76, 1.0)
	add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-8.0, 40.0, 0.0)
	rim.light_energy = 1.1
	rim.light_color = Color(1.0, 0.92, 0.82)
	add_child(rim)
