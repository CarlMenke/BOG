extends Node3D
## Drives every practice-range behaviour in an empty room and checks what it did.
##
##   bash: "$GODOT" --headless --path . tools/range_brains.tscn
##
## The fixture is the map's markers contract in miniature — a `DummyStations`
## group with one live marker per behaviour and one `live: false` marker nobody
## should stand on, a `Signs` group with the one signboard the range has left,
## and a `Plates` group whose third plate is the refill stone that belongs to
## unit 4 and must be ignored. Everything else on the range (the geometry, the
## wells, the boards) is somebody else's check; what this one asserts is that a
## brain put a body where it said it would, that it published the fields the
## animator reads, and that the signboard and a plate did their one thing.
##
## Written as one `await`-driven script rather than a state machine in
## `_physics_process`, because every assertion here is "let this run for N ticks
## and then look", and that is a sentence in a coroutine and a table of counters
## anywhere else.

const TICK := 1.0 / 60.0

## The kerb under the standing dummy. Its marker is authored at y = 0, so a
## brain that trusted its station's height would stand 0.35 m inside the stone
## and a brain that casts a ray stands on it. That is the whole test.
const KERB_TOP := 0.35

## Where each behaviour is tried, and in which of the map's zones — real zone
## names, because a brain's per-zone defaults are keyed on them.
const STATIONS := [
	{"brain": "stand", "zone": "lanes", "at": Vector3(0.0, KERB_TOP, 0.0)},
	{"brain": "strafe", "zone": "gallery", "at": Vector3(10.0, 0.0, 0.0)},
	{"brain": "patrol", "zone": "lanes", "at": Vector3(20.0, 0.0, 0.0)},
	{"brain": "popup", "zone": "gallery", "at": Vector3(30.0, 0.0, 0.0)},
	{"brain": "jumper", "zone": "yard", "at": Vector3(40.0, 0.0, 0.0)},
	{"brain": "rusher", "zone": "melee", "at": Vector3(0.0, 0.0, 20.0)},
	{"brain": "wanderer", "zone": "yard", "at": Vector3(20.0, 0.0, 20.0)},
	# Faces +Z, so its orbit centre is 3.6 m that way. See `circler.gd`.
	{"brain": "circler", "zone": "melee", "at": Vector3(40.0, 0.0, 20.0), "yaw": PI},
]
## A marker authored `live: false`. The map itself no longer authors any — with
## the stations gone nothing would ever mint a body onto one — but the director
## still has to skip one rather than spawn it, and this is what says so.
const RESERVED := {"brain": "stand", "zone": "parkour", "at": Vector3(50.0, 0.0, 0.0)}

const PLATE_START := Vector3(60.0, 0.0, 0.0)
const PLATE_FINISH := Vector3(60.0, 0.0, 10.0)
const PLATE_REFILL := Vector3(60.0, 0.0, 20.0)

const PARK := Vector3(-20.0, 0.0, -20.0)

var _players: Node3D
var _items: Node3D
var _dummies: RangeDummies
var _director: RangeDirector
var _ids: Dictionary = {}
var _checks: int = 0
var _failures: int = 0
var _finished: Array = []
var _ticks: Array = []


func _ready() -> void:
	_build_room()
	_build_markers()

	_items = Node3D.new()
	_items.name = "SpawnedItems"
	_items.add_to_group("spawned_items")
	add_child(_items)
	_players = Node3D.new()
	_players.name = "Players"
	add_child(_players)

	Net.start_offline()
	var config := Net.config
	# This tool *is* the range, and saying so is what stops the match ending
	# under it: `_check_win` returns at once on a practice map, and the one
	# death in the parkour check — the only human on the roster falling into the
	# void — would otherwise be the last man standing and put the phase into
	# POST_MATCH, after which nothing else drives anything.
	config.map = MapCatalog.PRACTICE
	config.warmup_time = 0.0
	config.spawn_protection = 0.0
	config.respawn_delay = 60.0
	config.time_limit = 0
	config.kill_limit = 0
	MatchState.register_arena(_players, [_facing(PARK, Vector3.ZERO)])

	await _until_playing()
	_dummies = RangeDummies.new()
	_dummies.name = "Dummies"
	add_child(_dummies)
	_director = RangeDirector.new()
	add_child(_director)
	await _frames(4)
	for id: int in _dummies.ids():
		_ids[_dummies.brain_of(id)] = id

	await _check_spawn()
	await _check_ground_and_stand()
	await _check_strafe()
	await _check_patrol()
	await _check_popup()
	await _check_jumper()
	await _check_wanderer()
	await _check_circler()
	await _check_rusher()
	await _check_signboard()
	await _check_parkour()
	await _check_real_map()

	print("range_brains: %d checks, %d failures" % [_checks, _failures])
	print("range_brains: %s" % ("PASS" if _failures == 0 else "FAIL"))
	get_tree().quit(0 if _failures == 0 else 1)


# -------------------------------------------------------------- the fixture ---

func _build_room() -> void:
	_slab("Floor", Vector3(0.0, -0.5, 10.0), Vector3(200.0, 1.0, 120.0))
	# The kerb the standing dummy has to find with a ray. See `KERB_TOP`.
	_slab("Kerb", Vector3(0.0, KERB_TOP * 0.5, 0.0), Vector3(3.0, KERB_TOP, 3.0))


func _slab(node_name: String, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.position = at
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)


func _build_markers() -> void:
	var dummies := _group("DummyStations")
	for entry: Dictionary in STATIONS:
		_marker(dummies, "Dummy_%s" % entry["brain"], entry["at"],
			float(entry.get("yaw", 0.0)),
			{"brain": entry["brain"], "zone": entry["zone"], "live": true,
				"range_m": 0.0, "lane": ""})
	_marker(dummies, "Dummy_reserved", RESERVED["at"], 0.0,
		{"brain": RESERVED["brain"], "zone": RESERVED["zone"], "live": false,
			"range_m": 0.0, "lane": ""})

	var signs := _group("Signs")
	_marker(signs, "Sign_lodge_reset_stats", Vector3(8.0, 0.0, -8.0), 0.0,
		{"action": "reset_stats", "zone": "lodge"})

	var plates := _group("Plates")
	_marker(plates, "Plate_parkour_start", PLATE_START, 0.0,
		{"role": "parkour_start", "zone": "parkour"})
	_marker(plates, "Plate_parkour_finish", PLATE_FINISH, 0.0,
		{"role": "parkour_finish", "zone": "parkour"})
	_marker(plates, "Plate_refill", PLATE_REFILL, 0.0,
		{"role": "refill", "zone": "lodge"})


func _group(node_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	add_child(root)
	return root


func _marker(root: Node3D, node_name: String, at: Vector3, yaw: float,
		meta: Dictionary) -> void:
	var marker := Marker3D.new()
	marker.name = node_name
	marker.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	for key: String in meta:
		marker.set_meta(key, meta[key])
	root.add_child(marker)


static func _facing(from: Vector3, towards: Vector3) -> Transform3D:
	var flat := (towards - from) * Vector3(1.0, 0.0, 1.0)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	return Transform3D(Basis(Vector3.UP, Bog.yaw_towards(flat.normalized())), from)


# ------------------------------------------------------------------ the runs ---

func _check_spawn() -> void:
	var mark := _open("spawn")
	_ok("spawned one Bog per live behaviour", _dummies.ids().size() == STATIONS.size())
	for entry: Dictionary in STATIONS:
		_ok("%s exists" % entry["brain"], _ids.has(entry["brain"]))
	_ok("the live: false marker minted nobody",
		_director.dummies_in("parkour").is_empty())
	_ok("the signboard was built", _director.signboard_count() == 1)
	var bog := _bog("stand")
	_ok("a dummy is a remote Bog on the host", bog != null and not bog.is_local())
	_close("spawn", mark)


func _check_ground_and_stand() -> void:
	var mark := _open("stand")
	var bog := _bog("stand")
	var start := bog.global_position
	await _frames(60)
	_ok("stand found the kerb by ray, not its station's height",
		absf(bog.global_position.y - KERB_TOP) < 0.02)
	_ok("stand did not wander", bog.global_position.distance_to(start) < 0.01)
	_ok("stand publishes grounded", bog.sync_grounded)
	_ok("stand publishes a still velocity", bog.sync_velocity.is_zero_approx())
	_ok("body and snapshot agree",
		bog.global_position.distance_to(bog.sync_position) < 0.0001)

	# It turns to look at somebody who walks past.
	var player := _player()
	player.global_position = Vector3(6.0, KERB_TOP, 0.0)
	await _frames(20)
	var want := Bog.yaw_towards(Vector3.RIGHT)
	_ok("stand faces the nearest human",
		absf(angle_difference(bog.sync_yaw, want)) < 0.05)
	player.global_position = PARK
	await _frames(20)
	_close("stand", mark)


func _check_strafe() -> void:
	var mark := _open("strafe")
	var bog := _bog("strafe")
	var brain := _dummies.runner_of(_ids["strafe"])
	var half: float = brain.call("half_width")
	var crossings := 0
	# The last side it was *definitely* on. Sampled only outside a dead band
	# around the mark, or the tick it steps over zero — 0.09 m at 5.4 m/s — is
	# recorded as a side of its own and no crossing is ever seen.
	var side := 0.0
	var peak := 0.0
	var wandered := 0.0
	for i in 240:
		await _tick()
		var offset := bog.global_position.x - 10.0
		wandered = maxf(wandered, absf(bog.global_position.z))
		peak = maxf(peak, bog.sync_velocity.length())
		if absf(offset) > 0.2:
			if side != 0.0 and signf(offset) != side:
				crossings += 1
			side = signf(offset)
		if absf(offset) > half + 0.1:
			_fail("strafe left its lane at %.2f m" % offset)
			break
	_ok("strafe stayed inside its lane", true)
	_ok("strafe crossed its mark at least twice", crossings >= 2)
	_ok("strafe reached running speed", peak >= Bog.RUN_SPEED - 0.1)
	_ok("strafe stayed on its axis", wandered < 0.01)
	_ok("strafe publishes its velocity",
		bog.sync_velocity.distance_to(bog.velocity) < 0.0001)
	_close("strafe", mark)


func _check_patrol() -> void:
	var mark := _open("patrol")
	var bog := _bog("patrol")
	var low := 99.0
	var high := -99.0
	var fastest := 0.0
	var paused := 0
	for i in 300:
		await _tick()
		var offset := bog.global_position.x - 20.0
		low = minf(low, offset)
		high = maxf(high, offset)
		fastest = maxf(fastest, bog.sync_velocity.length())
		if bog.sync_velocity.is_zero_approx():
			paused += 1
	var brain := _dummies.runner_of(_ids["patrol"])
	var half: float = brain.call("half_length")
	_ok("patrol walked its whole beat", high - low > half * 1.5)
	_ok("patrol stayed on its beat", low >= -half - 0.05 and high <= half + 0.05)
	_ok("patrol walked, never ran", fastest <= Bog.WALK_SPEED + 0.05)
	_ok("patrol paused at its ends", paused > 30)
	_close("patrol", mark)


func _check_popup() -> void:
	var mark := _open("popup")
	var bog := _bog("popup")
	var brain := _dummies.runner_of(_ids["popup"])
	var up := 0
	var total := 0
	var deepest := 0.0
	var airborne := 0
	for i in 420:
		await _tick()
		total += 1
		if bog.global_position.y >= -0.01:
			up += 1
		deepest = minf(deepest, bog.global_position.y)
		if not bog.sync_grounded:
			airborne += 1
	var share := float(up) / float(total)
	_ok("popup is up between 40%% and 60%% of the time (%.0f%%)" % (share * 100.0),
		share > 0.40 and share < 0.60)
	# Capsule top when down: `CROUCH_HEIGHT` above the feet. It must clear the
	# floor, which is what makes it unshootable rather than nearly so.
	_ok("popup's whole capsule is under the floor when down",
		deepest + Bog.CROUCH_HEIGHT < -0.1)
	_ok("popup's nameplate is under the floor too", deepest + 2.2 < 0.0)
	_ok("popup never opens an airtime", airborne == 0)
	_ok("popup crouches while it is down", brain.call("is_up") or bog.sync_crouching)
	_close("popup", mark)


func _check_jumper() -> void:
	var mark := _open("jumper")
	var bog := _bog("jumper")
	# It has been jumping since it spawned, so the serial is already well past
	# zero: what is asserted is the number of bumps *during this window*.
	var first := bog.sync_jump_serial
	var serial := first
	var jumps := 0
	var apex := 0.0
	var air := 0.0
	var longest := 0.0
	var landed_at := 0.0
	var ground := bog.global_position.y
	for i in 480:
		await _tick()
		if bog.sync_jump_serial != serial:
			serial = bog.sync_jump_serial
			jumps += 1
			air = 0.0
		if not bog.sync_grounded:
			air += TICK
			apex = maxf(apex, bog.global_position.y - ground)
		elif air > 0.0:
			longest = maxf(longest, air)
			landed_at = bog.global_position.y
			air = 0.0
	_ok("jumper jumped more than once (%d)" % jumps, jumps >= 2)
	_ok("jumper's apex is the game's own 1.69 m (%.3f)" % apex,
		absf(apex - Bog.apex_for(Bog.JUMP_VELOCITY)) < 0.02)
	_ok("jumper's airtime is the game's own 0.698 s (%.3f)" % longest,
		longest > 0.60 and longest < 0.72)
	_ok("jumper landed on the height it left (%.4f)" % landed_at,
		absf(landed_at - ground) < 0.001)
	_ok("jumper bumped the jump serial once per jump", jumps == serial - first)
	_close("jumper", mark)


func _check_wanderer() -> void:
	var mark := _open("wanderer")
	var bog := _bog("wanderer")
	var brain := _dummies.runner_of(_ids["wanderer"])
	var radius: float = brain.call("radius")
	var centre := Vector3(20.0, 0.0, 20.0)
	var seen: Array[Vector3] = []
	var strayed := false
	var fastest := 0.0
	for i in 600:
		await _tick()
		var flat := bog.global_position - centre
		flat.y = 0.0
		if flat.length() > radius + 0.05:
			strayed = true
		fastest = maxf(fastest, bog.sync_velocity.length())
		if bog.sync_velocity.is_zero_approx():
			var here := bog.global_position
			var fresh := true
			for spot: Vector3 in seen:
				if spot.distance_to(here) < 0.5:
					fresh = false
			if fresh:
				seen.append(here)
	_ok("wanderer stayed in its zone", not strayed)
	_ok("wanderer walked, never ran", fastest <= Bog.WALK_SPEED + 0.05)
	_ok("wanderer visited three or more places (%d)" % seen.size(), seen.size() >= 3)
	_close("wanderer", mark)


func _check_circler() -> void:
	var mark := _open("circler")
	var bog := _bog("circler")
	var brain := _dummies.runner_of(_ids["circler"])
	var centre: Vector3 = brain.call("centre")
	var radius: float = brain.call("radius")
	var drift := 0.0
	var facing := 0.0
	var turned := 0.0
	var was := 0.0
	var started := false
	for i in 240:
		await _tick()
		var flat := bog.global_position - centre
		flat.y = 0.0
		drift = maxf(drift, absf(flat.length() - radius))
		var want := Bog.yaw_towards((centre - bog.global_position).normalized() \
			* Vector3(1.0, 0.0, 1.0))
		facing = maxf(facing, absf(angle_difference(bog.sync_yaw, want)))
		# Accumulated per tick, because four seconds at 1.5 rad/s is most of two
		# whole turns and the difference between the first bearing and the last
		# is whatever is left over after the wrap.
		var bearing := atan2(flat.z, flat.x)
		if started:
			turned += absf(angle_difference(was, bearing))
		was = bearing
		started = true
	_ok("circler held its radius (%.3f m of drift)" % drift, drift < 0.15)
	_ok("circler faced the middle (%.3f rad)" % facing, facing < 0.1)
	_ok("circler went round (%.1f rad)" % turned, turned > 3.0)
	_ok("circler ran", bog.sync_velocity.length() > Bog.RUN_SPEED - 0.1)
	_close("circler", mark)


func _check_rusher() -> void:
	var mark := _open("rusher")
	var bog := _bog("rusher")
	var brain := _dummies.runner_of(_ids["rusher"])
	var centre := Vector3(0.0, 0.0, 20.0)
	var radius: float = brain.call("radius")
	var player := _player()
	player.global_position = Vector3(3.0, 0.0, 21.0)

	var closest := 99.0
	# The *first* hold. A player who stands in the pit is rushed again and again
	# — chase, hold, retreat, cooldown, chase — so a total over four seconds is
	# a count of how many runs fitted, which is not what is being asserted.
	var held := 0.0
	var holding := false
	var done := false
	var strayed := 0.0
	for i in 240:
		await _tick()
		closest = minf(closest, bog.global_position.distance_to(player.global_position))
		var in_hold := String(brain.call("state_name")) == "hold"
		if in_hold and not done:
			holding = true
			held += TICK
		elif holding:
			done = true
			holding = false
		var flat := bog.global_position - centre
		flat.y = 0.0
		strayed = maxf(strayed, flat.length())
	_ok("rusher closed to two metres (%.2f)" % closest, closest <= 2.4)
	_ok("rusher held for about a second (%.2f)" % held, held >= 0.9 and held <= 1.3)
	_ok("rusher never left its zone (%.2f of %.2f)" % [strayed, radius],
		strayed <= radius + 0.05)

	# Walk away: it goes home rather than following.
	player.global_position = PARK
	for i in 300:
		await _tick()
	_ok("rusher went back to its station",
		bog.global_position.distance_to(centre) < 0.3)
	_ok("rusher is idle again", String(brain.call("state_name")) == "idle")
	_close("rusher", mark)


## The stats signboard, and the one property that matters about it: it is the
## only thing on the range you can walk into that does anything, and what it
## does is call the counter rather than touch a dummy.
##
## This replaces a check of six stations, a behaviour ring, a debounce, a lamp
## colour and a reserved position that a station minted a body onto. All of that
## is gone: a zone's behaviour is authored in the map and never changes, so the
## thing that used to be worth asserting — that cycling *rotated* a zone's mix
## instead of flattening it — no longer has anything to be wrong about.
func _check_signboard() -> void:
	var mark := _open("signboard")
	_ok("the range built exactly one signboard", _director.signboard_count() == 1)
	var sign := _director.signboard_at(0)
	_ok("it is the stats reset", sign != null and sign.action == "reset_stats")

	# Nothing on the range cycles any more, so a body walking past the sign must
	# leave every brain exactly as the map authored it.
	var before: Dictionary = {}
	for id: int in _dummies.ids():
		before[id] = _dummies.brain_of(id)
	var player := _player()
	player.global_position = sign.global_position
	await _frames(8)
	player.global_position = PARK
	await _frames(4)
	var moved := 0
	for id: int in before:
		if _dummies.brain_of(id) != before[id]:
			moved += 1
	_ok("walking into the sign changed nobody's brain", moved == 0)

	# `reset_stats` with no `RangeStats` in the tree must be a no-op, not a
	# crash: this file runs long before that node is in a scene.
	sign.fire()
	await _frames(2)
	_ok("reset_stats survived there being no counter in the tree", true)

	# And the reserved marker really is empty — the director skips `live: false`
	# now instead of holding it for a station to mint.
	_ok("a live: false marker stood nobody up",
		_director.dummies_in("parkour").is_empty())
	_close("signboard", mark)


func _check_parkour() -> void:
	var mark := _open("parkour")
	var timer := _director.parkour()
	_ok("a parkour clock was built", timer != null)
	_ok("the refill plate is not the timer's", timer.get_child_count() == 2)
	timer.run_finished.connect(func(peer: int, seconds: float, best: float) -> void:
		_finished.append([peer, seconds, best]))
	timer.run_tick.connect(func(peer: int, seconds: float) -> void:
		_ticks.append([peer, seconds]))

	var player := _player()
	player.global_position = PLATE_START
	await _frames(8)
	_ok("the start plate armed a run", timer.is_running(1))
	await _frames(40)
	_ok("a live run ticks for the readout", _ticks.size() >= 3)
	player.global_position = PLATE_FINISH
	await _frames(8)
	_ok("the finish plate reported a run", _finished.size() == 1)
	var run: Array = _finished[0] if _finished.size() > 0 else [0, 0.0, 0.0]
	_ok("the run has a positive time (%.2f s)" % float(run[1]), float(run[1]) > 0.0)
	_ok("the run is the best so far", is_equal_approx(float(run[1]), float(run[2])))

	# A fall cancels: negative seconds, and the best survives.
	player.global_position = PLATE_START
	await _frames(8)
	_ok("the start plate re-armed", timer.is_running(1))
	MatchState.report_kill(1, 1, Bog.Cause.VOID, player.global_position,
		Vector3.DOWN, "")
	await _frames(6)
	_ok("a death cancelled the run", _finished.size() == 2
		and float(_finished[1][1]) < 0.0)
	_ok("the best time survived the fall", float(_finished[1][2]) > 0.0)
	_close("parkour", mark)


## The last check, and the only one that is not a fixture: unit 2's actual map,
## with a director parented to it, so the marker group names and meta keys this
## unit reads are proven against the file that writes them rather than against a
## copy of it in this tool. The one line that does this in the game —
## `add_child(RangeDirector.new())` in `range_map.gd` — is unit 6's to land, so
## until it does this is where the real map and the real director first meet.
##
## It runs last because the map brings its own `RangeDummies`, which takes over
## `RangeDummies.instance`, and because twenty-three more Bogs is not a thing to
## do in the middle of measuring a jump.
func _check_real_map() -> void:
	var mark := _open("map")
	var scene: PackedScene = load("res://scenes/world/maps/range.tscn")
	_ok("the range map loads", scene != null)
	if scene == null:
		_close("map", mark)
		return
	var map := scene.instantiate()
	add_child(map)
	await _frames(6)
	for group: String in [RangeDirector.GROUP_DUMMIES, RangeDirector.GROUP_SIGNS,
			RangeDirector.GROUP_PLATES]:
		_ok("the map has a %s group" % group, map.get_node_or_null(group) != null)

	var director := RangeDirector.new()
	map.add_child(director)
	await _frames(12)
	var live := 0
	for zone: String in ["lodge", "lanes", "long", "gallery", "melee", "yard",
			"parkour", "void"]:
		live += (director.dummies_in(zone) as Array).size()
	_ok("the map's live dummies all stood up (%d)" % live, live == 27)
	_ok("its one signboard was built", director.signboard_count() == 1)
	_ok("its parkour clock found two plates",
		director.parkour() != null and director.parkour().get_child_count() == 2)
	# Every brain the map authors has to be one this unit can actually build.
	var known := RangeBrain.names()
	var strangers := 0
	for zone: String in ["lanes", "long", "gallery", "melee", "yard"]:
		for id: int in director.dummies_in(zone):
			if not known.has(RangeDummies.instance.brain_of(id)):
				strangers += 1
	_ok("every brain the map asks for exists", strangers == 0)
	await _frames(30)
	var placed := 0
	for zone: String in ["lanes", "gallery", "melee", "yard", "long"]:
		for id: int in director.dummies_in(zone):
			var bog := RangeDummies.instance.bog_of(id)
			if is_instance_valid(bog) 					and bog.global_position.distance_to(bog.sync_position) < 0.001:
				placed += 1
	# Twenty-six and not twenty-seven: the summit's stander is in `parkour`,
	# which is not one of the five zones this loop walks.
	_ok("every dummy on the real map is being driven (%d)" % placed, placed == 26)
	_close("map", mark)


# ------------------------------------------------------------------- helpers ---

func _bog(brain: String) -> Bog:
	return _dummies.bog_of(int(_ids.get(brain, 0)))


func _player() -> Bog:
	var bog := MatchState.bogs.get(1) as Bog
	if bog != null:
		bog.reads_local_input = false
	return bog


## Open a section. Its PASS line is only printed if nothing inside it failed,
## which is the whole point of a per-section line: `also "..." "jumper PASS"` in
## the gate has to be a claim about the jumper and not about the run.
func _open(_what: String) -> int:
	return _failures


func _close(what: String, before: int) -> void:
	print("range_brains: %s %s" % [what, "PASS" if _failures == before else "FAIL"])


func _ok(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		print("range_brains: FAIL — %s" % what)


func _fail(why: String) -> void:
	_checks += 1
	_failures += 1
	print("range_brains: FAIL — %s" % why)


func _tick() -> void:
	await get_tree().physics_frame


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _until_playing() -> void:
	var waited := 0
	while MatchState.phase != MatchState.Phase.PLAYING and waited < 600:
		waited += 1
		await get_tree().physics_frame
	if MatchState.phase != MatchState.Phase.PLAYING:
		_fail("the match never reached PLAYING")
