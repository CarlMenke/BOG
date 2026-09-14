extends Node
## A real Capture G·U·B match standing up on a real map, checked and then
## photographed from behind a base (D-051). Development tool, not shipped.
##
##   Godot --headless --path . tools/capture_preview.tscn -- [map id]
##   Godot --path . --resolution 1600x900 --script tools/snapshot.gd -- \
##       res://tools/capture_preview.tscn out/capture_base.png 150 [map id]
##
## `match_rules` proves the rules in a box with a floor; `playthrough` proves the
## layout is sound on every map. Neither builds the arena *in this mode*, which
## is the only way to see what a player sees: `arena.gd` drawing a ring in each
## team's colour, the host settling three cards onto the map a couple of physics
## frames in, and each Gub spawning on its own team's pads. So this instances
## the real `arena.tscn` in an offline session with a Teams roster and checks
## all three, then — when there is a window — puts a camera behind Team 1's
## base looking at the middle of the map.
##
## The map is Kopje Crossing unless another id is given.

const ARENA_SCENE := preload("res://scenes/world/arena.tscn")
const FAKE_BASE := 600
const FAKE_NAMES := ["Thistle", "Mossback", "Pipwick"]
const TIMEOUT_TICKS := 1200

var _map: String = "safari"
var _arena: Arena
var _camera: Camera3D
var _ticks: int = 0
var _done: bool = false
var _failures: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if MapCatalog.is_valid(arg):
			_map = arg
	Engine.max_fps = int(ProjectSettings.get_setting(
		"physics/common/physics_ticks_per_second", 60))

	Net.start_offline()
	Net.set_name_local("You")
	var config := Net.config
	config.win_condition = MatchConfig.WinCondition.CAPTURE
	config.mode = MatchConfig.Mode.TEAMS
	config.team_count = 2
	config.map = _map
	config.warmup_time = 0.2
	config.spawn_protection = 0.0
	config.time_limit = 0
	Net.players[1]["team"] = 0
	for i in FAKE_NAMES.size():
		Net.players[FAKE_BASE + i] = {"name": FAKE_NAMES[i], "team": (i + 1) % 2,
			"ready": true}
	Net.roster_changed.emit()

	_arena = ARENA_SCENE.instantiate() as Arena
	add_child(_arena)
	print("capture_preview: arena for '%s' is up" % _map)


func _process(_delta: float) -> void:
	if _camera != null:
		_camera.make_current()


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _done:
		return
	if MatchState.phase != MatchState.Phase.PLAYING or MatchState._capture.size() < 3:
		if _ticks > TIMEOUT_TICKS:
			_want("the match reached PLAYING with three cards out", false)
			_finish()
		return
	_done = true
	_check()
	_frame()
	_finish()


func _check() -> void:
	var layout := MatchState.capture_layout()
	var bases := _arena.get_node_or_null("CaptureBases")
	_want("the arena drew the bases", bases != null and bases.get_child_count() == 2)
	var cards := 0
	for id: int in MatchState._pickups:
		var item: Pickup = MatchState._pickups[id]
		if is_instance_valid(item) and item.kind == Pickup.Kind.LETTER:
			cards += 1
	_want("three letter cards are on the map (%d)" % cards, cards == 3)
	for letter: int in MatchState.LETTERS:
		_want("%s is at home" % MatchState.letter_name(letter),
			MatchState.capture_state(letter) == "home")
	# Every Gub on a pad of its own team's.
	for peer_id: int in MatchState.gubs:
		var gub: Gub = MatchState.gubs[peer_id]
		var team := Net.player_team(peer_id)
		var nearest := -1
		var best := INF
		for i in _arena.spawn_points.size():
			var d := _arena.spawn_points[i].origin.distance_to(gub.global_position)
			if d < best:
				best = d
				nearest = i
		_want("%s spawned on a team %d pad" % [Net.player_name(peer_id), team + 1],
			nearest >= 0 and layout.pad_team[nearest] == team)


## Behind and well above Team 1's base, looking down over it at the middle —
## high enough to clear the trees a map plants round its spawn pads.
func _frame() -> void:
	var layout := MatchState.capture_layout()
	if layout == null or layout.bases.size() < 2:
		return
	var base := layout.bases[0]
	var middle := (layout.bases[0] + layout.bases[1]) * 0.5
	var away := Vector3(base.x - middle.x, 0.0, base.z - middle.z).normalized()
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.far = 500.0
	add_child(_camera)
	_camera.look_at_from_position(base + away * 9.0 + Vector3.UP * 13.0,
		base + Vector3.UP * 1.0 - away * 6.0, Vector3.UP)
	_camera.make_current()


func _want(what: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		print("  FAIL  %s" % what)


func _finish() -> void:
	print("capture_preview: %s" % ("PASS" if _failures == 0 else "FAIL"))
	if DisplayServer.get_name() == "headless":
		MatchState.reset()
		get_tree().quit(1 if _failures > 0 else 0)
