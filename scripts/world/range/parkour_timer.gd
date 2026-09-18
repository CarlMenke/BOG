class_name ParkourTimer
extends Node3D
## The course's clock: two plates, a stopwatch per player, and a best for the
## session (D-114).
##
## Two `Area3D`s on the map's `parkour_start` and `parkour_finish` markers,
## host-monitored like a `Pickup` and like a station. Timing is per peer, so
## four people can be running the course at once without sharing a clock, and
## the best is kept per peer for as long as the arena stands.
##
## ## Restarting is entering the start again
##
## A player who falls off the fourth pillar walks back to the start plate.
## Refusing the second entry because a run is already live would mean the only
## way to retry is to finish the run you have already lost, which is not a rule
## anybody would guess and not one worth teaching. So the start plate always
## (re)arms.
##
## ## A cancelled run is a negative time
##
## Falling into the void, or being killed by anything else mid-run, drops the
## run and reports it through `run_finished` with **negative seconds**. Not a
## second signal: unit 5's readout has one thing to connect to and one rule to
## know, and `Cause.VOID` — the only death this course actually produces —
## needs no case of its own. A run that ends any other way is a run that ended.

const LAYER_PLAYER := 2

## The plates are things you run over at speed, so the trigger is wider than the
## timber and tall enough to catch a Bog mid-hop.
const PLATE_RADIUS := 1.4
const PLATE_HEIGHT := 2.4
const PLATE_SIZE := Vector3(2.4, 0.12, 2.4)
const START_COLOUR := Color(0.55, 0.95, 0.70)
const FINISH_COLOUR := Color(1.00, 0.84, 0.36)

## How often a live run is broadcast. Ten a second: a readout counting in
## hundredths reads as smooth at this rate, and it is a twelfth of the packets a
## per-frame relay would send.
const TICK := 0.1

signal run_tick(peer_id: int, seconds: float)
signal run_finished(peer_id: int, seconds: float, best: float)

## peer id -> the millisecond the run started on. Host only.
var _live: Dictionary = {}
## peer id -> best seconds this session, on every peer (the finish is relayed).
var _best: Dictionary = {}
var _since_tick: float = 0.0


func _ready() -> void:
	add_to_group("range_parkour")
	# Any death, not only the void one: a rusher that shoves you off a pillar
	# does not kill you, but a fall to the bog below is `Cause.VOID` and
	# anything else that kills you mid-run has also ended it.
	MatchState.player_killed.connect(_on_player_killed)


## Build a plate from one of unit 2's `Plates` markers. `refill` is unit 4's and
## is refused here **by role**, not by position, so the apron's third plate can
## never become the timer's by being moved.
func add_plate(marker: Marker3D) -> bool:
	var role := String(marker.get_meta("role", ""))
	if role != "parkour_start" and role != "parkour_finish":
		return false
	var area := Area3D.new()
	area.name = "Plate_%s" % role
	area.transform = marker.transform
	area.collision_layer = 0
	area.collision_mask = LAYER_PLAYER
	area.monitoring = Net.is_host
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = PLATE_RADIUS
	cylinder.height = PLATE_HEIGHT
	shape.shape = cylinder
	shape.position.y = PLATE_HEIGHT * 0.5
	area.add_child(shape)

	var plank := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = PLATE_SIZE
	plank.mesh = box
	plank.position.y = PLATE_SIZE.y * 0.5
	var material := StandardMaterial3D.new()
	var colour: Color = START_COLOUR if role == "parkour_start" else FINISH_COLOUR
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 1.6
	plank.material_override = material
	area.add_child(plank)

	var started := role == "parkour_start"
	area.body_entered.connect(func(body: Node3D) -> void: _on_plate(body, started))
	add_child(area)
	return true


func best_of(peer_id: int) -> float:
	return float(_best.get(peer_id, 0.0))


func is_running(peer_id: int) -> bool:
	return _live.has(peer_id)


func seconds_of(peer_id: int) -> float:
	if not _live.has(peer_id):
		return 0.0
	return (Time.get_ticks_msec() - int(_live[peer_id])) * 0.001


func _on_plate(body: Node3D, is_start: bool) -> void:
	if not Net.is_host:
		return
	var bog := body as Bog
	if bog == null or not bog.alive or Net.is_dummy(bog.peer_id):
		return
	if is_start:
		_live[bog.peer_id] = Time.get_ticks_msec()
		AudioDirector.play_3d(AudioDirector.RANGE_PLATE, bog.global_position)
		return
	if not _live.has(bog.peer_id):
		# Walked onto the summit from somewhere that was not the course.
		return
	var seconds := (Time.get_ticks_msec() - int(_live[bog.peer_id])) * 0.001
	_live.erase(bog.peer_id)
	var previous := float(_best.get(bog.peer_id, 0.0))
	var best: float = seconds if previous <= 0.0 or seconds < previous else previous
	_finish.rpc(bog.peer_id, seconds, best)
	_finish(bog.peer_id, seconds, best)


func _on_player_killed(victim_id: int, _killer_id: int, _cause: int) -> void:
	if not Net.is_host or not _live.has(victim_id):
		return
	_live.erase(victim_id)
	var best := float(_best.get(victim_id, 0.0))
	_finish.rpc(victim_id, -1.0, best)
	_finish(victim_id, -1.0, best)


## The result, on every peer. The best is sent rather than recomputed, so a
## client that joined halfway through still agrees about the board.
@rpc("authority", "call_remote", "reliable")
func _finish(peer_id: int, seconds: float, best: float) -> void:
	if best > 0.0:
		_best[peer_id] = best
	run_finished.emit(peer_id, seconds, best)
	if seconds > 0.0:
		var bog := MatchState.bogs.get(peer_id) as Bog
		if is_instance_valid(bog):
			AudioDirector.play_3d(AudioDirector.RANGE_PLATE, bog.global_position, 1.35)


@rpc("authority", "call_remote", "unreliable")
func _tick(peer_id: int, seconds: float) -> void:
	run_tick.emit(peer_id, seconds)


func _physics_process(delta: float) -> void:
	if not Net.is_host or _live.is_empty():
		return
	_since_tick += delta
	if _since_tick < TICK:
		return
	_since_tick = 0.0
	for peer_id: int in _live:
		var seconds := (Time.get_ticks_msec() - int(_live[peer_id])) * 0.001
		_tick.rpc(peer_id, seconds)
		_tick(peer_id, seconds)
