extends Node3D
## Teammates' nameplates through walls, enemies' not, and the HUD saying which
## team you are on (D-047). Development tool, not shipped.
##
## Headless, it is the check, and quits itself on tick `CHECK_TICK`:
##
##   Godot --headless --path . tools/team_plates.tscn            # teams
##   Godot --headless --path . tools/team_plates.tscn -- ffa     # free-for-all
##
## Through the snapshot it is the picture — the local Bog's own camera, a wall
## fifteen metres out, a teammate and an enemy forty metres behind it and one of
## each in the open in front of it:
##
##   Godot --path . --resolution 1600x900 --script tools/snapshot.gd -- \
##       res://tools/team_plates.tscn out/team_plates.png 40
##
## The real match path, as `combat_range` runs it: an offline session, a roster
## written into `Net.players`, `MatchState.register_arena`, and Bogs spawned by
## `MatchState._create_bog` — so the plates are set up by the code a match uses,
## not by this file.
##
## What it asserts (teams):
##   wall     — the wall really is between the camera and the far pair, by ray,
##              so "visible through a wall" is not being claimed of open air.
##   ally     — the far teammate's plate is drawn without the depth test, is
##              visible and at full alpha at forty metres.
##   enemy    — the far enemy's plate is still depth-tested and faded out: the
##              same plate it was before D-047.
##   hud      — the HUD's team chip is up, says TEAM 1, in team 1's colour.
## And in free-for-all:
##   ffa      — no plate is an ally or ignores the depth test; the far ones are
##              faded, the near ones at full alpha in the neutral colour; and
##              the team chip is hidden.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")

const CHECK_TICK := 30

const ME := 1
## Well clear of the combat range's 900s and the HUD range's 640s.
const NEAR_ALLY := 720
const NEAR_ENEMY := 721
const FAR_ALLY := 722
const FAR_ENEMY := 723

const MY_SPOT := Vector3(0.0, 0.1, 0.0)
const WALL_Z := -15.0
const SPOTS := {
	NEAR_ALLY: Vector3(-2.5, 0.1, -8.0),
	NEAR_ENEMY: Vector3(2.5, 0.1, -8.0),
	FAR_ALLY: Vector3(-3.0, 0.1, -40.0),
	FAR_ENEMY: Vector3(3.0, 0.1, -40.0),
}

var _ffa: bool = false
var _players: Node3D
var _hud: HUD
var _ticks: int = 0
var _failed: bool = false


func _ready() -> void:
	_ffa = OS.get_cmdline_user_args().has("ffa")
	_build_stage()

	_players = Node3D.new()
	_players.name = "Players"
	add_child(_players)

	Net.start_offline()
	var config := Net.config
	config.mode = MatchConfig.Mode.FREE_FOR_ALL if _ffa else MatchConfig.Mode.TEAMS
	config.team_count = 2
	config.warmup_time = 0.0
	config.spawn_protection = 0.0
	config.time_limit = 0
	Net.players[ME]["name"] = "You"
	Net.players[ME]["team"] = 0
	Net.players[NEAR_ALLY] = {"name": "Fernwhistle", "team": 0, "ready": true}
	Net.players[NEAR_ENEMY] = {"name": "Thornbeak", "team": 1, "ready": true}
	Net.players[FAR_ALLY] = {"name": "Pipwick", "team": 0, "ready": true}
	Net.players[FAR_ENEMY] = {"name": "Nettle", "team": 1, "ready": true}
	Net.roster_changed.emit()

	var pads: Array[Transform3D] = [_facing(MY_SPOT, Vector3(0.0, 0.1, -40.0))]
	for peer_id: int in SPOTS:
		pads.append(_facing(SPOTS[peer_id], MY_SPOT))
	MatchState.register_arena(_players, pads)
	_place_everyone()

	_hud = HUD_SCENE.instantiate() as HUD
	add_child(_hud)


func _physics_process(_delta: float) -> void:
	_ticks += 1
	# Pads are shuffled by `_next_spawn`; `_ready` put everyone back on their own
	# and this says it once more after the first physics step has run.
	if _ticks == 1:
		_place_everyone()
	if _ticks != CHECK_TICK:
		return
	if _ffa:
		_check_ffa()
	else:
		_check_wall()
		_check_ally()
		_check_enemy()
		_check_hud()
	print("team_plates: %s" % ("FAIL" if _failed else "PASS"))
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _failed else 0)


# ----------------------------------------------------------------- verdicts ---

func _check_wall() -> void:
	var camera := get_viewport().get_camera_3d()
	var plate := _plate(FAR_ALLY)
	if camera == null or plate == null:
		_verdict("wall", false, "camera %s, plate %s" % [camera, plate])
		return
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, plate.global_position)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var blocked := not hit.is_empty() and absf((hit["position"] as Vector3).z - WALL_Z) < 1.0
	_verdict("wall", blocked, "ray from %s to %s hit %s" % [
		camera.global_position, plate.global_position, hit.get("position")])


func _check_ally() -> void:
	var plate := _plate(FAR_ALLY)
	var label := _label(plate)
	if label == null:
		_verdict("ally", false, "no plate")
		return
	var distance := _distance(plate)
	var ok := plate.is_ally() and label.no_depth_test and label.is_visible_in_tree() \
		and is_equal_approx(label.modulate.a, 1.0) and distance > 35.0 \
		and label.modulate.is_equal_approx(Nameplate.colour_for_team(0)) \
		and (plate.get_node("AllyBar") as Node3D).visible
	_verdict("ally", ok, "ally %s, no_depth_test %s, visible %s, alpha %.2f, colour %s, at %.1f m" % [
		plate.is_ally(), label.no_depth_test, label.is_visible_in_tree(), label.modulate.a,
		label.modulate, distance])
	# The near one too: an ally is an ally at any range.
	var near := _plate(NEAR_ALLY)
	_verdict("near ally", near != null and near.is_ally() and _label(near).no_depth_test,
		"near teammate's plate is not marked as one")


func _check_enemy() -> void:
	var failures := []
	for peer_id in [FAR_ENEMY, NEAR_ENEMY]:
		var plate := _plate(peer_id)
		var label := _label(plate)
		if label == null:
			failures.append("%d has no plate" % peer_id)
			continue
		if plate.is_ally() or label.no_depth_test or (plate.get_node("AllyBar") as Node3D).visible:
			failures.append("%d is drawn as an ally" % peer_id)
		var faded := not label.visible
		var far := _distance(plate) > Nameplate.FADE_END
		if far != faded:
			failures.append("%d at %.1f m has visible=%s" % [peer_id, _distance(plate), label.visible])
	_verdict("enemy", failures.is_empty(), "; ".join(failures))


func _check_hud() -> void:
	var chip := _hud.get_node("%TeamChip") as Control
	var label := _hud.get_node("%TeamLabel") as Label
	var colour := label.get_theme_color("font_color")
	var ok := chip.visible and label.text == "TEAM 1" \
		and colour.is_equal_approx(UIPalette.team_colour(0))
	_verdict("hud", ok, "chip visible %s, text '%s', colour %s" % [chip.visible, label.text, colour])


func _check_ffa() -> void:
	var failures := []
	for peer_id: int in SPOTS:
		var plate := _plate(peer_id)
		var label := _label(plate)
		if label == null:
			failures.append("%d has no plate" % peer_id)
			continue
		if plate.is_ally() or label.no_depth_test:
			failures.append("%d is drawn as an ally" % peer_id)
		var far := _distance(plate) > Nameplate.FADE_END
		if far == label.visible:
			failures.append("%d at %.1f m has visible=%s" % [peer_id, _distance(plate), label.visible])
		if not far and not label.modulate.is_equal_approx(Nameplate.NEUTRAL_COLOUR):
			failures.append("%d is %s, not neutral" % [peer_id, label.modulate])
		if not is_equal_approx(label.pixel_size, Nameplate.PIXEL_SIZE):
			failures.append("%d has pixel size %f" % [peer_id, label.pixel_size])
	var chip := _hud.get_node("%TeamChip") as Control
	if chip.visible:
		failures.append("the team chip is up in free-for-all")
	_verdict("ffa", failures.is_empty(), "; ".join(failures))


func _verdict(name: String, ok: bool, detail: String) -> void:
	if ok:
		print("team_plates: %s PASS" % name)
	else:
		_failed = true
		print("team_plates: %s FAIL — %s" % [name, detail])


# ------------------------------------------------------------------ helpers ---

func _plate(peer_id: int) -> Nameplate:
	var bog := MatchState.bogs.get(peer_id) as Bog
	return bog.get_node_or_null("Nameplate") as Nameplate if bog != null else null


func _label(plate: Nameplate) -> Label3D:
	if plate == null:
		return null
	for child in plate.get_children():
		if child is Label3D:
			return child
	return null


func _distance(plate: Nameplate) -> float:
	var camera := get_viewport().get_camera_3d()
	return plate.global_position.distance_to(camera.global_position) if camera != null else -1.0


func _place_everyone() -> void:
	var me := MatchState.bogs.get(ME) as Bog
	if me != null:
		me.revive_at(_facing(MY_SPOT, Vector3(0.0, 0.1, -40.0)))
	for peer_id: int in SPOTS:
		var bog := MatchState.bogs.get(peer_id) as Bog
		if bog == null:
			continue
		bog.revive_at(_facing(SPOTS[peer_id], MY_SPOT))
		bog.sync_position = bog.global_position
		bog.sync_yaw = bog.body_yaw
		bog.sync_velocity = Vector3.ZERO
		bog.sync_grounded = true
		bog.sync_crouching = false
		bog.sync_sliding = false


static func _facing(from: Vector3, towards: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, Bog.yaw_towards(towards - from)), from)


func _build_stage() -> void:
	_box(Vector3(0, -0.5, -20), Vector3(90, 1, 90), Color(0.13, 0.15, 0.13))
	_box(Vector3(0, 3.0, WALL_Z), Vector3(30, 6, 1), Color(0.24, 0.25, 0.28))

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -34, 0)
	key.light_energy = 1.4
	add_child(key)
	var env := WorldEnvironment.new()
	env.environment = load("res://resources/config/default_env.tres")
	add_child(env)


func _box(at: Vector3, size: Vector3, colour: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = at
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.9
	cube.material = mat
	mesh.mesh = cube
	body.add_child(mesh)
