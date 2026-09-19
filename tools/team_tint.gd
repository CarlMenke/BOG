extends Node3D
## Bogs in team colours (D-046): the check, and the picture. Development tool,
## not shipped.
##
## Headless, it is the check, and quits itself on tick 12:
##
##   Godot --headless --path . tools/team_tint.tscn
##
## Through the snapshot it is the lineup — one Bog per team colour, a
## free-for-all Bog in the imported yellow, and a tinted Bog wearing the robe:
##
##   Godot --path . --resolution 1800x640 --script tools/snapshot.gd -- \
##       res://tools/team_tint.tscn out/team_tint.png 40 [studio|dusk|noon]
##
## What it asserts, all off the material the renderer will actually draw with
## (`get_active_material`), never off what the script meant to set:
##
##   teams    — every Bog's body is in exactly its team's nameplate colour.
##   ffa      — a TEAM_NONE Bog is back on the imported material, including one
##              that was on a team a moment ago.
##   robe     — the Elder's robe is on its own purple material, while the body
##              under it stays in the team colour.
##   corpse   — a ragdoll of a tinted Bog is still in that colour, and a ragdoll
##              of a yellow one is still yellow — clothes and all.
##   garment  — a skin's clothes (D-163) go on the rig, come off again when the
##              skin changes, take the team's colour unlike the robe, and are on
##              the corpse of the Bog that died in them.
##   lobby    — `BogBackdrop.set_roster` repaints a Bog whose team changed, the
##              path a player switching team in the lobby takes. Headless only:
##              the backdrop brings its own camera and glade.

const BOG := preload("res://scenes/player/bog.tscn")
const TEAMS := 8
const SPACING := 1.05
const CHECK_TICK := 12
const ELDER_TEAM := 0
## The skin whose folder holds clothes (D-163), and the team the Bog wearing
## them stands on. Found by name rather than typed as an index, because
## `Skins.NAMES` is appended to.
const GARMENT_SKIN := "shirt"
const GARMENT_TEAM := 2

## Whisperbloom and Rust, from the same shipped resources `preview_elder.gd`
## renders its robe under, so the colours are judged in the maps' own light.
const ISLAND_ENV := "res://resources/config/arena_env.tres"
const RUST_ENV := "res://resources/config/rust_env.tres"

var _light: String = "studio"
var _team_bogs: Array[Bog] = []
var _ffa_bog: Bog
var _elder: Bog
var _dressed: Bog
var _ticks: int = 0
var _failed: bool = false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg in ["studio", "dusk", "noon"]:
			_light = arg
	_build_light()
	_ground()

	var count := TEAMS + 3
	var x := -SPACING * float(count - 1) * 0.5
	for team in TEAMS:
		var bog := _make_bog("Team %d" % (team + 1), x)
		bog.set_team_tint(team)
		_team_bogs.append(bog)
		x += SPACING
	_ffa_bog = _make_bog("Free-for-all", x)
	# On a team first, then off it: the neutral case has to put the imported
	# material *back*, not merely never have replaced it.
	_ffa_bog.set_team_tint(3)
	_ffa_bog.set_team_tint(MatchConfig.TEAM_NONE)
	x += SPACING
	_elder = _make_bog("Elder, Team %d" % (ELDER_TEAM + 1), x)
	_elder.set_team_tint(ELDER_TEAM)
	_elder.set_elder(true)
	x += SPACING
	# The garment skin, dressed and *then* tinted, which is the order both call
	# sites do it in (`MatchState._create_bog`, `BogBackdrop._apply_slot`) and
	# therefore the order the clothes have to pick the colour up in.
	_dressed = _make_bog("Shirt, Team %d" % (GARMENT_TEAM + 1), x)
	_wear(_dressed, GARMENT_SKIN)
	_dressed.set_team_tint(GARMENT_TEAM)

	var cam := Camera3D.new()
	cam.fov = 24.0
	cam.near = 0.05
	cam.far = 300.0
	add_child(cam)
	# Half a metre further back than it stood for ten, because the lineup gained
	# the dressed Bog and the one on each end was touching the frame.
	cam.look_at_from_position(Vector3(0.0, 1.3, 12.6), Vector3(0.0, 0.95, 0.0), Vector3.UP)
	cam.make_current()


func _make_bog(label: String, x: float) -> Bog:
	var bog := BOG.instantiate() as Bog
	bog.name = label.replace(" ", "_").replace(",", "")
	bog.display_name = label
	# Remote before it enters the tree, as `BogBackdrop` does it, so its rig does
	# not take the viewport.
	bog.peer_id = 8900 + get_tree().get_nodes_in_group("bogs").size()
	bog.set_multiplayer_authority(bog.peer_id)
	add_child(bog)
	bog.revive_at(Transform3D(Basis(Vector3.UP, Bog.yaw_towards(Vector3.BACK)), Vector3(x, 0.0, 0.0)))
	bog.sync_grounded = true
	bog.sync_velocity = Vector3.ZERO
	var plate := bog.get_node_or_null("Nameplate") as Nameplate
	if plate != null:
		plate.set_display_name(label)
	return bog


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _ticks != CHECK_TICK:
		return
	_check_teams()
	_check_ffa()
	_check_robe()
	_check_garment()
	_check_corpses()
	if DisplayServer.get_name() == "headless":
		_check_lobby()
		print("team_tint: %s" % ("FAIL" if _failed else "PASS"))
		get_tree().quit(1 if _failed else 0)
	else:
		print("team_tint: %s" % ("FAIL" if _failed else "PASS"))


func _check_teams() -> void:
	var bad := []
	for team in _team_bogs.size():
		var want := Nameplate.colour_for_team(team)
		var got: Variant = Bog.tint_of(_team_bogs[team].body_mesh)
		if not (got is Color and (got as Color).is_equal_approx(want)):
			bad.append("team %d wants %s, body is %s" % [team, want, got])
	_verdict("teams", bad.is_empty(), "; ".join(bad))


func _check_ffa() -> void:
	var mesh := _ffa_bog.body_mesh
	var ok := mesh != null and Bog.tint_of(mesh) == null \
		and mesh.get_active_material(0) == mesh.mesh.surface_get_material(0)
	_verdict("ffa", ok, "active material %s" % (mesh.get_active_material(0) if mesh else null))


func _check_robe() -> void:
	var skeleton := _elder.find_child("Skeleton3D", true, false) as Skeleton3D
	var cloth := skeleton.get_node_or_null(ElderRobe.MESH_NAME) as MeshInstance3D \
		if skeleton != null else null
	if cloth == null or _elder.elder_robe == null or not _elder.elder_robe.is_worn():
		_verdict("robe", false, "the Elder is not wearing a robe")
		return
	var robe_material := cloth.get_active_material(0)
	var untouched := Bog.tint_of(cloth) == null \
		and robe_material == cloth.mesh.surface_get_material(0)
	var body: Variant = Bog.tint_of(_elder.body_mesh)
	var body_ok := body is Color \
		and (body as Color).is_equal_approx(Nameplate.colour_for_team(ELDER_TEAM))
	_verdict("robe", untouched and body_ok and cloth != _elder.body_mesh,
		"robe material %s, body tint %s" % [robe_material, body])


## A skin's clothes: on the rig, in the team's colour, off again when the skin
## changes, and on the corpse.
##
## The robe's check above is the same shape with the opposite verdict on the
## colour, and the pair is the point: the Elder's purple is a rule about a Bog
## and must never take a team's colour, while a shirt is that player's body and
## must.
func _check_garment() -> void:
	var cloth := _cloth_of(_dressed)
	if cloth == null or _dressed.skin_garment == null \
			or not _dressed.skin_garment.is_worn():
		_verdict("garment", false, "the shirt is not on the rig")
		return
	var got: Variant = Bog.tint_of(cloth)
	var tinted := got is Color \
		and (got as Color).is_equal_approx(Nameplate.colour_for_team(GARMENT_TEAM))

	# Picked again (D-144), out of shot: the old clothes have to come off, and
	# they have to come off the *skeleton*, not merely be forgotten by the Bog.
	var changer := _make_bog("Changer", 0.0)
	# Stood well behind the lineup rather than nudged out of it afterwards: a
	# Bog is placed by `revive_at`, which writes `sync_position` too, and a
	# position set over the top of that is a position the next tick undoes.
	changer.revive_at(Transform3D(Basis(), Vector3(0.0, 0.0, -60.0)))
	_wear(changer, GARMENT_SKIN)
	var dressed_first := _cloth_of(changer) != null
	_wear(changer, "muck")
	# The rig is bare in the *same frame*, not on a queued free a frame later:
	# see `SkinGarment.doff`.
	var bare := changer.skin_garment == null
	var stripped := _cloth_of(changer) == null

	_verdict("garment", tinted and cloth != _dressed.body_mesh \
		and dressed_first and bare and stripped,
		"cloth tint %s, dressed on pick %s, undressed on the next %s/%s"
			% [got, dressed_first, bare, stripped])


## The garment mesh on a Bog's skeleton, or null if there is none on it.
## Asked of the rig rather than of `Bog.skin_garment` on purpose: what the two
## disagree about is the bug.
func _cloth_of(bog: Bog) -> MeshInstance3D:
	var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return null
	return skeleton.get_node_or_null(SkinGarment.MESH_NAME) as MeshInstance3D


## One skin onto one Bog, the way `MatchState._create_bog` does it.
func _wear(bog: Bog, skin_name: String) -> void:
	var skin := Skins.NAMES.find(skin_name)
	bog.wear_skin(Skins.texture_of(skin), Skins.roughness_of(skin),
		Skins.emission_of(skin), Skins.garment_of(skin))


func _check_corpses() -> void:
	var team := 5
	var source := _team_bogs[team]
	var corpse := BogRagdoll.spawn_from(source, self, Vector3(0.0, 0.0, -2.0), "mixamorig_Spine1")
	var body := _corpse_body(corpse)
	var got: Variant = Bog.tint_of(body)
	var tinted := got is Color and (got as Color).is_equal_approx(Nameplate.colour_for_team(team))

	var plain := BogRagdoll.spawn_from(_ffa_bog, self, Vector3(0.0, 0.0, -2.0), "mixamorig_Spine1")
	var plain_body := _corpse_body(plain)
	var yellow := plain_body != null and Bog.tint_of(plain_body) == null \
		and plain_body.get_active_material(0) is BaseMaterial3D

	# And a corpse of the Bog in the shirt keeps the shirt (D-163), in the colour
	# it died in. The clothes are a second copy off the same scene rather than
	# the live mesh re-parented, so what is checked is that the corpse has one at
	# all and that it is painted like the body beside it.
	var dead_dressed := BogRagdoll.spawn_from(_dressed, self, Vector3(0.0, 0.0, -2.0),
		"mixamorig_Spine1")
	var shroud := _corpse_mesh(dead_dressed, SkinGarment.MESH_NAME)
	var shroud_tint: Variant = Bog.tint_of(shroud)
	var clothed := shroud != null and shroud_tint is Color \
		and (shroud_tint as Color).is_equal_approx(Nameplate.colour_for_team(GARMENT_TEAM))

	# Out of the picture: they are the proof, not the subject.
	corpse.position.z -= 40.0
	plain.position.z -= 40.0
	dead_dressed.position.z -= 40.0
	_verdict("corpse", tinted and yellow and clothed,
		"tinted corpse %s, plain corpse %s, dressed corpse %s" % [got,
			plain_body.get_active_material(0) if plain_body else null, shroud_tint])


func _corpse_body(corpse: BogRagdoll) -> MeshInstance3D:
	return _corpse_mesh(corpse, Bog.BODY_MESH_NAME)


func _corpse_mesh(corpse: BogRagdoll, mesh_name: String) -> MeshInstance3D:
	for mesh in corpse.find_children("*", "MeshInstance3D", true, false):
		if mesh.name == mesh_name:
			return mesh
	return null


func _check_lobby() -> void:
	var backdrop := BogBackdrop.new()
	add_child(backdrop)
	backdrop.set_roster([{"name": "A", "team": 0}, {"name": "B", "team": 1}])
	var bogs: Array = backdrop.get("_bogs")
	if bogs.size() < 2:
		_verdict("lobby", false, "the backdrop stood up %d Bogs, not 2" % bogs.size())
		return
	var first := _tint_matches(bogs[0], 0) and _tint_matches(bogs[1], 1)
	# A switches to team 4, B leaves teams altogether.
	backdrop.set_roster([{"name": "A", "team": 3}, {"name": "B", "team": MatchConfig.TEAM_NONE}])
	var second := _tint_matches(bogs[0], 3) and Bog.tint_of((bogs[1] as Bog).body_mesh) == null
	_verdict("lobby", first and second, "first roster %s, after the switch %s" % [first, second])


func _tint_matches(bog: Bog, team: int) -> bool:
	var got: Variant = Bog.tint_of(bog.body_mesh)
	return got is Color and (got as Color).is_equal_approx(Nameplate.colour_for_team(team))


func _verdict(name: String, ok: bool, detail: String) -> void:
	if ok:
		print("team_tint: %s PASS" % name)
	else:
		_failed = true
		print("team_tint: %s FAIL — %s" % [name, detail])


# ------------------------------------------------------------- furnishings ---

func _ground() -> void:
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(40.0, 40.0)
	plane.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.19, 0.19)
	mat.roughness = 0.95
	plane.material_override = mat
	add_child(plane)


func _build_light() -> void:
	var world := WorldEnvironment.new()
	add_child(world)
	match _light:
		"dusk":
			world.environment = load(ISLAND_ENV) as Environment
			var moon := DirectionalLight3D.new()
			add_child(moon)
			moon.look_at_from_position(Vector3(-0.42, 0.38, 0.82) * 80.0, Vector3.ZERO, Vector3.UP)
			moon.light_color = Color(0.62, 0.72, 1.0)
			moon.light_energy = 0.30
			var torch := OmniLight3D.new()
			add_child(torch)
			torch.position = Vector3(0.0, 2.2, 3.0)
			torch.light_color = Color(1.0, 0.63, 0.30)
			torch.light_energy = 2.6
			torch.omni_range = 10.5
			torch.omni_attenuation = 1.7
		"noon":
			world.environment = load(RUST_ENV) as Environment
			var sun := DirectionalLight3D.new()
			add_child(sun)
			sun.transform = Transform3D(Basis(
				Vector3(0.62926, 0.0, -0.77722),
				Vector3(-0.59535, 0.64285, -0.48201),
				Vector3(0.4996, 0.766, 0.4045)), Vector3(-1.0, 24.0, -5.0))
			sun.light_color = Color(1.0, 0.94, 0.85)
			sun.light_energy = 1.35
			sun.shadow_enabled = true
		_:
			var env := Environment.new()
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.13, 0.13, 0.15)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.55, 0.57, 0.66)
			env.ambient_light_energy = 0.32
			env.tonemap_mode = Environment.TONE_MAPPER_ACES
			env.tonemap_white = 6.0
			world.environment = env
			var key := DirectionalLight3D.new()
			key.rotation_degrees = Vector3(-34.0, -20.0, 0.0)
			key.light_energy = 1.55
			key.shadow_enabled = true
			add_child(key)
			var fill := DirectionalLight3D.new()
			fill.rotation_degrees = Vector3(-12.0, 160.0, 0.0)
			fill.light_energy = 0.6
			fill.light_color = Color(0.62, 0.76, 1.0)
			add_child(fill)
