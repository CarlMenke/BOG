extends Node3D
## A letter picked up is announced in the feed, and its carrier is marked over
## its head through walls for everyone (D-050). Development tool, not shipped.
##
## Headless, it is the check, and quits itself on tick `DONE_TICK`:
##
##   Godot --headless --path . tools/letter_carriers.tscn            # teams
##   Godot --headless --path . tools/letter_carriers.tscn -- ffa     # free-for-all
##
## Through the snapshot it is the picture — the local Bog's own camera, a wall
## fifteen metres out, two carriers forty metres behind it, and the feed:
##
##   Godot --path . --resolution 1600x900 --script tools/snapshot.gd -- \
##       res://tools/letter_carriers.tscn out/letter_carriers.png 45
##
## The real match path, as `team_plates` runs it: an offline host, a roster in
## `Net.players`, Bogs spawned by `MatchState._create_bog`, the real HUD, and
## cards put on the ground by `_spawn_drop` and walked into through
## `claim_pickup` — so the feed rows and the markers come from the signals a
## match fires, not from this file calling the feed.
##
## **Teams here is Teams *plus the collect race*, which the lobby no longer
## offers**, and that is deliberate rather than stale. Since the letters round
## there is one B·O·G whose flavour the mode picks, so a Teams match a player
## can start is Capture (`MatchConfig._clamp_all`) — but the clamp only runs on
## a config that arrives through `apply_dict`, and this file writes `Net.config`
## straight, exactly as `match_rules` does. What that buys is the one thing a
## Capture carry cannot show: a **timed** hold with teammates in the room, which
## is where the duplicate rule (D-049) and the countdown marker (D-050) both
## live. Both are live code — Capture reaches the first through `award_letter`
## — and this is the only harness that watches either of them on a screen.
##
## The `ffa` run is the shipping Free-for-all flavour and needs no such note.
##
## What it asserts (both modes):
##   duplicate — a card for a letter already banked is consumed on touch, starts
##               no hold, adds no feed row and raises no marker.
##   feed      — a card that starts a hold adds "Name picked up G" at the top of
##               the feed; banking adds "Name banked B".
##   wall      — the wall really is between the camera and the far carriers.
##   marker    — both far carriers (one of them an enemy in Teams) have a marker
##               up with their letter, drawn without the depth test and above
##               the nameplate; the local player's own hold marks nothing on
##               this screen.
##   bank      — after a hold is banked, that Bog's marker is gone.
##   death     — after a carrier is killed, that Bog's marker is gone.
##   rows      — the feed never holds more than `KillFeed.MAX_ROWS`.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")

const PICKUP_TICK := 10
const MARKER_TICK := 30
const BANK_TICK := 60
const DEATH_TICK := 70
const DONE_TICK := 160

const ME := 1
## Clear of team_plates' 720s, the combat range's 900s and the HUD range's 640s.
const NEAR_ENEMY := 760
const FAR_ALLY := 761
const FAR_ENEMY := 762

const MY_SPOT := Vector3(0.0, 0.1, 0.0)
const WALL_Z := -15.0
const SPOTS := {
	NEAR_ENEMY: Vector3(3.0, 0.1, -7.0),
	FAR_ALLY: Vector3(-3.0, 0.1, -40.0),
	FAR_ENEMY: Vector3(3.0, 0.1, -40.0),
}

var _ffa: bool = false
var _players: Node3D
var _hud: HUD
var _feed: KillFeed
var _ticks: int = 0
var _failed: bool = false


func _ready() -> void:
	_ffa = OS.get_cmdline_user_args().has("ffa")
	# Where `MatchState` puts the cards. Its fallback is the current scene, and
	# under `snapshot.gd` there is none, so without this every card in the
	# rendered run silently fails to exist.
	add_to_group("spawned_items")
	_build_stage()

	_players = Node3D.new()
	_players.name = "Players"
	add_child(_players)

	Net.start_offline()
	var config := Net.config
	config.mode = MatchConfig.Mode.FREE_FOR_ALL if _ffa else MatchConfig.Mode.TEAMS
	config.team_count = 2
	config.win_condition = MatchConfig.WinCondition.LETTERS
	config.letter_hold_time = 10.0
	config.warmup_time = 0.0
	config.spawn_protection = 0.0
	config.time_limit = 0
	Net.players[ME]["name"] = "You"
	Net.players[ME]["team"] = 0
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
	_feed = _hud.get_node("%KillFeed") as KillFeed


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _ticks == 1:
		_place_everyone()
	match _ticks:
		PICKUP_TICK:
			MatchState.phase = MatchState.Phase.PLAYING
			_pick_up()
		MARKER_TICK:
			_check_wall()
			_check_markers()
		BANK_TICK:
			_bank()
		BANK_TICK + 5:
			_check_gone(FAR_ALLY, "bank")
		DEATH_TICK:
			_kill_carrier()
		DEATH_TICK + 5:
			_check_gone(FAR_ENEMY, "death")
		DONE_TICK:
			_verdict("rows", _feed.get_child_count() <= KillFeed.MAX_ROWS,
				"%d rows" % _feed.get_child_count())
			print("letter_carriers: %s%s" % ["ffa " if _ffa else "", "FAIL" if _failed else "PASS"])
			if DisplayServer.get_name() == "headless":
				get_tree().quit(1 if _failed else 0)


# ------------------------------------------------------------------ sequence ---

func _pick_up() -> void:
	# Whatever a warmup left in the feed goes first, detached at once so the row
	# counts below are counts of this sequence.
	for child in _feed.get_children():
		_feed.remove_child(child)
		child.free()

	# Thornbeak banks B outright, which is a feed row of its own...
	MatchState.award_letter(NEAR_ENEMY, MatchState.LETTER_B)
	_verdict("feed banked", _top_row() == "Thornbeak banked B",
		"top row is '%s'" % _top_row())

	# ...and then walks over a second B, which is a duplicate: wasted on touch.
	#
	# `before` is read *after* the card lands and before it is claimed: a card
	# appearing is news of its own since the letters round (`letter_appeared`
	# puts "B appeared" in the feed), and what this row count is about is the
	# duplicate — the touch that consumes it has to add nothing.
	var dupe := MatchState._spawn_drop(Pickup.Kind.LETTER, MatchState.LETTER_B, SPOTS[NEAR_ENEMY])
	var before := _feed.get_child_count()
	MatchState.claim_pickup(dupe, NEAR_ENEMY)
	var bog := MatchState.bogs[NEAR_ENEMY] as Bog
	_verdict("duplicate", not MatchState._pickups.has(dupe)
		and not MatchState.is_holding_letter(NEAR_ENEMY)
		and _feed.get_child_count() == before and not bog.carrier_marker.is_carrying(),
		"card live %s, holding %s, rows %d -> %d, marker %s" % [
			MatchState._pickups.has(dupe), MatchState.is_holding_letter(NEAR_ENEMY),
			before, _feed.get_child_count(), bog.carrier_marker.is_carrying()])

	_claim(FAR_ENEMY, MatchState.LETTER_G)
	_verdict("feed picked up", _top_row() == "Nettle picked up G",
		"top row is '%s'" % _top_row())
	_claim(FAR_ALLY, MatchState.LETTER_O)
	_verdict("feed second pickup", _top_row() == "Pipwick picked up O",
		"top row is '%s'" % _top_row())
	_claim(ME, MatchState.LETTER_G)


func _claim(peer_id: int, letter: int) -> void:
	var card := MatchState._spawn_drop(Pickup.Kind.LETTER, letter, SPOTS.get(peer_id, MY_SPOT))
	MatchState.claim_pickup(card, peer_id)


## Wind the hold's clock back and let the host's own tick bank it, as
## `match_rules` does, rather than calling `award_letter` beside it.
func _bank() -> void:
	MatchState._letter_holds[FAR_ALLY]["ends_at"] = 0.0
	MatchState._tick_letter_holds()
	_verdict("feed bank", _top_row() == "Pipwick banked O", "top row is '%s'" % _top_row())


func _kill_carrier() -> void:
	var bog := MatchState.bogs[FAR_ENEMY] as Bog
	MatchState.report_kill(FAR_ENEMY, ME, Bog.Cause.SPEAR, bog.global_position + Vector3.UP,
		Vector3(0, 0, 8), "")


# ----------------------------------------------------------------- verdicts ---

func _check_wall() -> void:
	var camera := get_viewport().get_camera_3d()
	var bog := MatchState.bogs.get(FAR_ENEMY) as Bog
	if camera == null or bog == null:
		_verdict("wall", false, "camera %s, bog %s" % [camera, bog])
		return
	var target := bog.carrier_marker.global_position
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, target)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var blocked := not hit.is_empty() and absf((hit["position"] as Vector3).z - WALL_Z) < 1.0
	_verdict("wall", blocked, "ray to %s hit %s" % [target, hit.get("position")])


func _check_markers() -> void:
	var failures := []
	for pair: Array in [[FAR_ENEMY, "G"], [FAR_ALLY, "O"]]:
		var bog := MatchState.bogs.get(pair[0]) as Bog
		var marker := bog.carrier_marker if bog != null else null
		if marker == null:
			failures.append("%d has no marker" % pair[0])
			continue
		if not marker.is_shown() or marker.glyph() != pair[1]:
			failures.append("%d shown %s glyph '%s'" % [pair[0], marker.is_shown(), marker.glyph()])
		for child in marker.get_children():
			var through := false
			if child is Label3D:
				through = (child as Label3D).no_depth_test
			elif child is MeshInstance3D:
				through = ((child as MeshInstance3D).material_override as StandardMaterial3D).no_depth_test
			if not through:
				failures.append("%d's %s is depth-tested" % [pair[0], child.name])
		# Above the name, not over it: the card's bottom clears a teammate
		# plate's top, which is the tallest a plate gets at that range.
		var plate := bog.get_node("Nameplate") as Node3D
		var card := marker.get_node("Border") as MeshInstance3D
		var bottom := card.global_position.y - (card.mesh as QuadMesh).size.y * 0.5
		var plate_top := plate.global_position.y \
			+ Nameplate.FONT_SIZE * Nameplate.PIXEL_SIZE * Nameplate.ALLY_SCALE * 0.5 \
			* maxf(1.0, _distance(plate) / Nameplate.ALLY_HOLD_FROM)
		if bottom <= plate_top:
			failures.append("%d's card bottom %.2f is under the plate top %.2f" % [
				pair[0], bottom, plate_top])
	var mine := (MatchState.bogs[ME] as Bog).carrier_marker
	if not MatchState.is_holding_letter(ME) or not mine.is_carrying() or mine.is_shown():
		failures.append("own marker: holding %s carrying %s shown %s" % [
			MatchState.is_holding_letter(ME), mine.is_carrying(), mine.is_shown()])
	_verdict("marker", failures.is_empty(), "; ".join(failures))


func _check_gone(peer_id: int, verdict_name: String) -> void:
	var bog := MatchState.bogs.get(peer_id) as Bog
	var marker := bog.carrier_marker
	_verdict(verdict_name, not MatchState.is_holding_letter(peer_id)
		and not marker.is_carrying() and not marker.is_shown(),
		"holding %s, carrying %s, shown %s" % [
			MatchState.is_holding_letter(peer_id), marker.is_carrying(), marker.is_shown()])


func _verdict(verdict_name: String, ok: bool, detail: String) -> void:
	if ok:
		print("letter_carriers: %s PASS" % verdict_name)
	else:
		_failed = true
		print("letter_carriers: %s FAIL — %s" % [verdict_name, detail])


# ------------------------------------------------------------------ helpers ---

## The newest feed row as words, joined the way a player reads them.
func _top_row() -> String:
	if _feed.get_child_count() == 0:
		return ""
	var words := []
	for label in _feed.get_child(0).find_children("*", "Label", true, false):
		words.append((label as Label).text)
	return " ".join(words)


func _distance(node: Node3D) -> float:
	var camera := get_viewport().get_camera_3d()
	return node.global_position.distance_to(camera.global_position) if camera != null else 0.0


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
