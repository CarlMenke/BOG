extends Node
## Authoritative match lifecycle: who is alive, who killed whom, who is winning,
## and when it ends. Autoloaded as `MatchState`.
##
## `Net` owns the roster (who is connected and what they are called). This owns
## everything that only exists once a match is running. Keeping them apart means
## a disconnect is handled in exactly one place, and the lobby can be exercised
## with none of this loaded.
##
## Everything here is host-authoritative. Clients receive results and display
## them; they never decide a kill, a respawn or a score. The one thing clients
## do own is their own Gub's movement (docs/DECISIONS.md D-004), which is why
## respawning teleports via an RPC to the owner rather than by the host setting
## a position it does not control.
##
## Everything here asks `Net.local_id()` rather than `multiplayer.get_unique_id()`
## directly. They are the same answer while a session exists, and only the first
## has one when it does not: leaving nulls the peer immediately while `SceneFlow`
## fades for FADE_OUT seconds, and the HUD reaches `local_gub()` three times a
## frame throughout. `Gub.is_local()` carries the same guard for the same reason.

signal phase_changed(phase: Phase)
signal scores_changed()
signal player_killed(victim_id: int, killer_id: int, cause: int)
signal clock_changed(seconds_left: float)
signal match_finished(summary: Dictionary)
signal local_death(respawn_in: float)
signal local_respawn()
## One player's letter set changed. Carries the peer rather than the mask,
## because the mask is already in `stats` by the time this fires and a signal
## that carries state is a second copy of it waiting to disagree.
signal letters_changed(peer_id: int)
## One player has started, finished or lost a letter hold. Carries the peer for
## the same reason `letters_changed` does: the hold itself is already in
## `_letter_holds` when this fires, and a signal that carries a copy of it is a
## copy waiting to disagree.
##
## Fires on **every** peer, not just the holder's, because a Gub standing in the
## open ten seconds from a letter is the whole tension of the mode and has to
## read from across the clearing (D-035).
signal letter_hold_changed(peer_id: int)
## Events, not state, which is why these two carry the letter where the signals
## above refuse to: "Pipwick picked up G" is a thing that *happened*, once, and
## by the next frame the row it came from may already be gone again (D-050).
##
## `letter_picked_up` fires when a card starts a hold — the moment the rest of
## the lobby cares about. A duplicate wasted on touch (D-033, D-049) and a card
## walked over mid-hold start nothing, so neither fires it. `letter_banked`
## fires when a letter is actually awarded, which with a hold time of zero is
## the only one of the two a card produces. Both fire on every peer.
signal letter_picked_up(peer_id: int, letter: int)
signal letter_banked(peer_id: int, letter: int)
## A card taken out of a team's vault by somebody who is not on that team
## (D-068). Separate from `letter_banked` because it is the opposite event and
## the feed has to be able to say so.
signal letter_stolen(peer_id: int, letter: int, from_team: int)
## How far through lifting a card out of an enemy vault somebody is, 0 to 1
## (D-068). Emitted on every peer so a HUD can draw a thief's progress and a
## defender's warning off the same number.
signal steal_progress(peer_id: int, letter: int, done: float)
## Capture G·U·B only (D-051), and events in the same sense as the two above: a
## dead carrier's letter hit the ground, and a letter went home to its spawn —
## after lying dropped too long, or straight away when a carrier died where no
## card could land. Both fire on every peer. `letter_returned` names no peer,
## because nobody did it.
signal letter_dropped(peer_id: int, letter: int)
signal letter_returned(letter: int)
## One player has become, or stopped being, the Elder. Carries the peer for the
## same reason the two above do: `_elders` already holds the answer by the time
## this fires, and a signal carrying a copy of it is a copy waiting to disagree.
##
## Fires on **every** peer. The robe is the tell that says who is dangerous, and
## a tell only its wearer can see is not a tell (D-038).
signal elder_changed(peer_id: int)

enum Phase { IDLE, WARMUP, PLAYING, POST_MATCH }

const GUB_SCENE := preload("res://scenes/player/gub.tscn")
const PICKUP_SCENE := preload("res://scenes/items/pickup.tscn")

## Letters are a three-bit mask on the player's stats row, not a set.
##
## A mask because `stats` is replicated whole, as a Dictionary, on every score
## change — an int costs three bits of that and an `Array[String]` costs an
## allocation per player per push. It is also what the HUD wants: three lamps
## lit or unlit is `mask & LETTER_G`, with no membership test and no ordering to
## get wrong.
const LETTER_G := 1
const LETTER_U := 2
const LETTER_B := 4
## All three. The win condition is one comparison against this.
const LETTER_ALL := LETTER_G | LETTER_U | LETTER_B
## Index order for the uniform roll and for rendering. G, U, B, left to right,
## the way the word reads — which is emphatically *not* an order they have to be
## collected in (D-033).
const LETTERS: Array[int] = [LETTER_G, LETTER_U, LETTER_B]

## How far above the death point the drop's ground query starts, and how far
## down it looks. A Gub dies standing, or mid-ragdoll, or on a slope, so the ray
## starts above head height and is allowed to fall a Gub's height or so before
## giving up — past that the death happened over a drop and an item left there
## would hang in the air.
const DROP_RAY_UP := 1.4
const DROP_RAY_DOWN := 4.0

## Anything below this has left the island and is not coming back. It is the
## *default* floor rather than the only one: -45 is a property of a floating
## island with a deep rocky underside, and a ground-level static map wants its
## floor a few metres down instead. See `set_void_height`.
const VOID_HEIGHT := -45.0
## A fall that ends in the void still counts as a death, but the kill is only
## credited to another player if they were the last to touch you this recently.
const ASSIST_WINDOW := 4.0
## How long the host will wait for every peer to finish building the island
## before starting the match without them. The build is 2-6 seconds and a peer
## that never reports is a peer that has crashed or hung; the match should not
## wait on it for ever. See `register_arena`.
const ARENA_READY_TIMEOUT := 25.0

var phase: Phase = Phase.IDLE
var time_left: float = 0.0
## The floor the arena declared for the map currently loaded. Set by `arena.gd`
## in its `_ready`, before `register_arena`, and reset with everything else.
var void_height: float = VOID_HEIGHT

## peer_id -> {kills, deaths, letters, lives_left, alive, respawn_at,
##             last_attacker, last_attacker_at}
var stats: Dictionary = {}
## peer_id -> Gub
var gubs: Dictionary = {}

var _players_root: Node = null
var _spawn_points: Array[Transform3D] = []
var _spawn_cursor: int = 0
var _phase_timer: float = 0.0
var _finished: bool = false
## peer_id -> true once that peer has built its island and can be spawned into.
var _arena_ready: Dictionary = {}
var _arena_ready_deadline: float = 0.0

## pickup_id -> Pickup, on every peer. The id is what the spawn and the
## collection messages address, because a spawned node's *path* is not something
## two machines agree on — see the header of `scripts/items/pickup.gd`.
var _pickups: Dictionary = {}
## Host only. Never reused within a match, so a collect message can never land
## on the item that replaced the one it was about.
var _next_pickup_id: int = 1

## peer_id -> {letter: int, ends_at: float}, on every peer. A row exists exactly
## while that Gub is holding a card up, which is what `is_holding_letter` asks
## and what `GubCombat` gates the throw on (D-035).
##
## `ends_at` is in local `_now()` seconds on whichever machine wrote it, so the
## host's row and a client's row for the same hold differ by the latency of one
## reliable RPC. That is deliberate and it is the same split the ability
## cooldowns already use: the client's copy exists so the HUD can count down
## without asking, and **only the host's copy can finish a hold**. A client
## whose clock runs out early simply shows zero and waits — `is_holding_letter`
## is the presence of the row, never `remaining <= 0`, so nothing pops back into
## a hand before the host says so.
var _letter_holds: Dictionary = {}

## team -> three-bit mask, on every peer: the letters a team has banked between
## all of its members, which is what a Teams match is won on (D-049). Empty in a
## free-for-all.
##
## **Kept beside `stats` rather than derived from it**, and that is the leaver
## rule. `_on_player_left` erases the leaver's stats row, so a mask OR-ed
## together from rows would lose the G somebody banked the moment they closed
## the game — a team punished for a teammate's connection, and a letter taken out
## of a match that may be a hundred deaths from replacing it. Written only by
## `_sync_letters`, which already carries it to every peer, and cleared only by
## `reset` and a fresh warmup — never by a departure.
var _team_letters: Dictionary = {}

## peer_id -> {ends_at: float}, on every peer, for exactly as long as that Gub
## is the Elder.
##
## A row rather than a bare `true` since D-040, because the robe is now a clock:
## it lasts `elder_duration` seconds and then burns out, where it used to last
## until its wearer was killed. `ends_at` is in local `_now()` seconds on
## whichever machine wrote it, exactly as `_letter_holds` is and with exactly
## the same split — the client's copy exists so the HUD can count down without
## asking, and **only the host's copy can end one**. `is_elder` is the presence
## of the row and never `remaining <= 0`, so a client whose clock runs out early
## shows zero and waits rather than taking a robe off a Gub the host still says
## is wearing one.
##
## A set rather than a field on the `stats` row, and the difference matters.
## `stats` is what a respawn rewrites and what the scoreboard reads; the robe is
## neither a score nor something a life owns. It is closer to a letter hold: a
## thing the host declares, every peer renders, and a clock ends — which is why
## it lives beside `_letter_holds` and is written by the same shape of RPC.
##
## **More than one Elder can exist at once**, and that needs no special handling
## (D-038). Two robes can be on the ground at the same time and both can be
## picked up; two Elders is a fight worth having and an artificial "only one"
## rule would mean a robe that refuses to be collected.
var _elders: Dictionary = {}

## Capture G·U·B (D-051). What the arena's map declared, handed over before
## `register_arena`, and the layout planned from it and the spawn pads. The
## layout exists on every peer, because every peer draws the bases; it is
## planned whatever the win condition, because it costs a loop over eight pads
## and a harness can then inspect it on any map.
var _capture_declared_bases: Array[Vector3] = []
var _capture_declared_letters: Array[Vector3] = []
var _capture_declared_radius: float = CaptureLayout.DEFAULT_BASE_RADIUS
var _capture_layout: CaptureLayout = null
## Host only. letter -> {home: Vector3, pickup: int, carrier: int, return_at: float}.
## Exactly one row per letter once the cards are out: `pickup` is the id of the
## card on the ground (0 while carried), `carrier` the peer holding it (0 while
## on the ground), and `return_at` the host clock at which a dropped card goes
## home (0 while it is at home or carried). Empty until the cards are spawned.
var _capture: Dictionary = {}
## Host only. Set by a warmup in this mode, cleared once the cards are out. The
## cards are settled onto the ground with physics queries, and a map's collision
## is not in the broadphase until the physics has stepped — so they go out a
## couple of physics frames after the arena registered, not from inside it.
var _capture_pending: bool = false
var _arena_physics_frame: int = 0


func _ready() -> void:
	Net.left_lobby.connect(_on_left_lobby)
	Net.player_left.connect(_on_player_left)


func config() -> MatchConfig:
	return Net.config


func _now() -> float:
	return Time.get_ticks_msec() * 0.001


# ------------------------------------------------------------------- arena ---

## Tell the match where the bottom of this map is. Called by `arena.gd` for
## every map — with the island's default for a procedural one, and with the
## scene's own `void_height` for a static one — because `MatchState` is an
## autoload and a floor left over from the last map is a floor that is wrong for
## this one.
func set_void_height(height: float = VOID_HEIGHT) -> void:
	void_height = height


## Called by the arena once its geometry and spawn points exist. Every peer does
## this for itself; only the host acts on it.
func register_arena(players_root: Node, spawn_points: Array[Transform3D]) -> void:
	_players_root = players_root
	_spawn_points = spawn_points
	_capture_layout = CaptureLayout.plan(_spawn_points, config().team_count,
		_capture_declared_bases, _capture_declared_letters, _capture_declared_radius)
	_arena_physics_frame = Engine.get_physics_frames()
	# Deterministic but not identical between matches, so the same person does
	# not always open on the same ledge.
	var rng := RandomNumberGenerator.new()
	rng.seed = config().map_seed
	_spawn_cursor = rng.randi_range(0, maxi(1, _spawn_points.size()) - 1)

	# Do not start the match until every peer has an arena to start it in.
	#
	# The island is *generated*, and that blocks the main thread for two to six
	# seconds on each machine independently. The host used to begin the warmup
	# the moment its own build finished, which meant it spawned Gubs and started
	# replicating their positions while other peers were still building — so the
	# unreliable position updates arrived at a client that had not yet processed
	# the reliable RPC creating the node they address, and every client logged
	# `Node not found: "Arena/Players/Gub_N/Sync"` on every match start.
	#
	# Worse than the noise: `_create_gub` is sent once and never re-sent, so a
	# peer still building when it arrives could miss a spawn permanently and
	# spend the match in an empty arena, including its own body. That never bit
	# because the RPC queues behind the blocking build rather than being dropped
	# — but it was luck, not design.
	#
	# Waiting is also just correct. Nobody can play until everybody can play.
	if Net.is_host:
		_arena_ready[Net.local_id()] = true
		_arena_ready_deadline = _now() + ARENA_READY_TIMEOUT
		_try_begin_warmup()
	else:
		_report_arena_ready.rpc_id(1)


## A client telling the host its island is built and it can be spawned into.
@rpc("any_peer", "call_remote", "reliable")
func _report_arena_ready() -> void:
	if not Net.is_host:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = Net.local_id()
	_arena_ready[peer_id] = true
	_try_begin_warmup()


## Begin once everyone is ready — or once we have waited long enough that a peer
## which has not reported is better treated as gone than as slow.
func _try_begin_warmup() -> void:
	# An arena that is actually standing, not merely the last one registered.
	# `reset` forgets the old players root, but a root can also be on its way out
	# of the tree without anybody having said so, and a warmup begun into it
	# spawns every Gub into a scene about to be freed and leaves the phase at
	# WARMUP — so the arena that registers next returns early here and the
	# match never has a body in it.
	if phase != Phase.IDLE or not _arena_is_standing():
		return
	# Only peers we genuinely have a connection to. `Net.players` is the roster,
	# and the roster is not the same thing: `tools/combat_range.gd`,
	# `tools/hud_range.gd` and `tools/ui_range.gd` all write stand-in entries
	# straight into it for peers that do not exist and never will (D-011), and an
	# offline session has no remote peers at all. Waiting on `Net.peer_ids()`
	# would stall every one of those harnesses for the full timeout.
	var waiting: Array[int] = []
	for peer_id: int in multiplayer.get_peers():
		if not _arena_ready.has(peer_id):
			waiting.append(peer_id)
	if not waiting.is_empty() and _now() < _arena_ready_deadline:
		return
	if not waiting.is_empty():
		push_warning("MatchState: starting without %d peer(s) whose arena never reported"
			% waiting.size())
	_begin_warmup()


func _arena_is_standing() -> bool:
	return is_instance_valid(_players_root) and _players_root.is_inside_tree()


func _on_left_lobby(_reason: int, _message: String) -> void:
	reset()


## Somebody disconnected. Take their Gub out of the world on every machine, and
## take their row out of the scoring, so the match can still end.
##
## The win check has to run again afterwards. In a lives match the leaver may
## have been the only thing standing between someone else and "last Gub
## standing", and without this the match simply never ends — everyone waits on a
## player who closed the game.
func _on_player_left(peer_id: int) -> void:
	var gub: Gub = gubs.get(peer_id)
	# A disconnect is a death, as far as a letter hold is concerned (D-035):
	# nothing is awarded and the card goes back on the ground where the body
	# was. Read before the Gub is freed, because the body is the only thing that
	# knows where "there" is — and if it is already gone, `Vector3.INF` tells
	# `_interrupt_letter_hold` there is nowhere to put the card.
	var last_spot := gub.global_position if is_instance_valid(gub) else Vector3.INF
	if Net.is_host and phase == Phase.PLAYING:
		_interrupt_letter_hold(peer_id, last_spot)
	# And on every peer, host included, the row goes whatever the phase is. A
	# hold belonging to somebody who is no longer in the match is a countdown
	# nothing will ever stop.
	if _letter_holds.erase(peer_id):
		letter_hold_changed.emit(peer_id)
	# The robe goes with them and does not come back. It is one of the three
	# things that end an Elder (D-040) and the only one that is not a clock or a
	# cliff — and unlike the card there is nothing to put on the ground, because
	# a robe is consumed rather than re-dropped (D-038). So the row simply goes,
	# on every peer, host included, whatever the phase. Leaving it would be a
	# twenty-second countdown belonging to somebody who has closed the game, and
	# a `gubs` entry it cannot be taken off.
	if _elders.erase(peer_id):
		elder_changed.emit(peer_id)
	if is_instance_valid(gub):
		gub.queue_free()
	gubs.erase(peer_id)
	stats.erase(peer_id)
	_arena_ready.erase(peer_id)
	scores_changed.emit()
	if Net.is_host and phase == Phase.PLAYING:
		_push_scores()
		_check_win()


func reset() -> void:
	for gub: Gub in gubs.values():
		if is_instance_valid(gub):
			gub.queue_free()
	gubs.clear()
	stats.clear()
	_team_letters.clear()
	# The nodes themselves belong to the arena's `spawned_items` and go with it;
	# this is only the index. Holding freed pickups across a match would make
	# `claim_pickup` chase instance ids that no longer resolve.
	_pickups.clear()
	_next_pickup_id = 1
	_clear_letter_holds()
	_clear_elders()
	_capture.clear()
	_capture_pending = false
	_capture_layout = null
	_capture_declared_bases = []
	_capture_declared_letters = []
	_capture_declared_radius = CaptureLayout.DEFAULT_BASE_RADIUS
	_arena_ready.clear()
	_arena_ready_deadline = 0.0
	# The arena these point into is the one being left, and it is freed on the
	# next scene change. Nothing may spawn into it between here and the next
	# `register_arena`.
	_players_root = null
	_spawn_points = []
	_finished = false
	time_left = 0.0
	void_height = VOID_HEIGHT
	_set_phase(Phase.IDLE)


# ------------------------------------------------------------------ phases ---

func _set_phase(next: Phase) -> void:
	if phase == next:
		return
	phase = next
	phase_changed.emit(phase)


func _begin_warmup() -> void:
	stats.clear()
	_team_letters.clear()
	_capture.clear()
	_capture_pending = is_capture()
	for peer_id: int in Net.peer_ids():
		stats[peer_id] = _new_stats()
	_finished = false
	time_left = float(config().time_limit)
	_phase_timer = config().warmup_time

	_sync_phase.rpc(Phase.WARMUP, _phase_timer, time_left)
	_sync_phase(Phase.WARMUP, _phase_timer, time_left)
	for peer_id: int in Net.peer_ids():
		_spawn_gub(peer_id)
	_push_scores()


func _new_stats() -> Dictionary:
	return {
		"kills": 0,
		"deaths": 0,
		# Kept for the whole match, across every death. Letters are the one
		# thing on this row that a respawn does not touch (D-033).
		"letters": 0,
		"lives_left": config().lives,
		"alive": true,
		"respawn_at": 0.0,
		"last_attacker": 0,
		"last_attacker_at": -999.0,
	}


@rpc("authority", "call_remote", "reliable")
func _sync_phase(next: Phase, phase_seconds: float, clock: float) -> void:
	_phase_timer = phase_seconds
	time_left = clock
	_set_phase(next)
	clock_changed.emit(time_left)


func _process(delta: float) -> void:
	if not Net.is_host:
		return
	if phase == Phase.IDLE:
		# Only reachable while waiting on other peers' arenas; this is what lets
		# `ARENA_READY_TIMEOUT` actually expire rather than waiting for ever on a
		# peer that has crashed mid-build.
		if _arena_ready_deadline > 0.0:
			_try_begin_warmup()
		return

	if _capture_pending and phase != Phase.POST_MATCH:
		_try_spawn_capture_letters()

	if phase == Phase.WARMUP:
		_phase_timer -= delta
		if _phase_timer <= 0.0:
			_sync_phase.rpc(Phase.PLAYING, 0.0, time_left)
			_sync_phase(Phase.PLAYING, 0.0, time_left)
		return

	if phase != Phase.PLAYING:
		return

	_tick_clock(delta)
	_tick_respawns()
	_tick_void()
	_tick_letter_holds()
	_tick_capture()
	_tick_elders()


func _tick_clock(delta: float) -> void:
	if config().time_limit <= 0:
		return
	time_left = maxf(0.0, time_left - delta)
	# Broadcast about once a second rather than every frame; the clock is a
	# display, and everyone counts down locally between updates.
	if int(time_left * 2.0) != int((time_left + delta) * 2.0):
		_sync_clock.rpc(time_left)
		clock_changed.emit(time_left)
	if time_left <= 0.0:
		_finish("time")


@rpc("authority", "call_remote", "unreliable")
func _sync_clock(seconds: float) -> void:
	time_left = seconds
	clock_changed.emit(time_left)


func _tick_respawns() -> void:
	for peer_id: int in stats.keys():
		var entry: Dictionary = stats[peer_id]
		if entry["alive"] or entry["respawn_at"] <= 0.0:
			continue
		if _now() < entry["respawn_at"]:
			continue
		if config().win_condition == MatchConfig.WinCondition.LIVES \
				and entry["lives_left"] <= 0:
			entry["respawn_at"] = 0.0  # eliminated; spectating
			continue
		_respawn(peer_id)


## Falling off the island. Checked on the host for everyone, because a client
## that has fallen is often the one least able to report it.
func _tick_void() -> void:
	for peer_id: int in gubs.keys():
		var gub: Gub = gubs[peer_id]
		if not is_instance_valid(gub) or not gub.alive:
			continue
		if gub.global_position.y > void_height:
			continue
		var entry: Dictionary = stats.get(peer_id, {})
		# If someone lured or spooked you off the edge moments ago, they get it.
		var attacker: int = entry.get("last_attacker", 0)
		var recent: bool = _now() - float(entry.get("last_attacker_at", -999.0)) < ASSIST_WINDOW
		report_kill(peer_id, attacker if recent else peer_id, Gub.Cause.VOID,
			gub.global_position, Vector3.DOWN, "")


# ------------------------------------------------------------------ spawns ---

func _next_spawn(peer_id: int = 0) -> Transform3D:
	var pool := _spawn_pool(peer_id)
	if pool.is_empty():
		return Transform3D.IDENTITY
	# Walk the list rather than picking at random, so two Gubs cannot land on
	# the same pad on the same frame.
	var best := pool[_spawn_cursor % pool.size()]
	_spawn_cursor += 1

	# Prefer a pad with nobody standing near it. Spawning face to face with an
	# armed Gub is the cheapest death in the game.
	var safest := best
	var safest_distance := -1.0
	for i in pool.size():
		var candidate := pool[(_spawn_cursor + i) % pool.size()]
		var nearest := INF
		for gub: Gub in gubs.values():
			if is_instance_valid(gub) and gub.alive:
				nearest = minf(nearest, candidate.origin.distance_to(gub.global_position))
		if nearest > safest_distance:
			safest_distance = nearest
			safest = candidate
		if nearest > 18.0:
			break
	return safest


## The pads `peer_id` may spawn on. Every pad, except in Capture G·U·B, where a
## Gub spawns on the pads nearest its own team's base (D-051) — a carrier's
## teammates come back next to the base they are defending, and nobody opens a
## match standing in the other team's. A team with no pads of its own, and
## `peer_id` 0 (a card with nowhere else to go), use every pad.
func _spawn_pool(peer_id: int) -> Array[Transform3D]:
	if peer_id == 0 or not is_capture() or _capture_layout == null \
			or _capture_layout.pad_team.size() != _spawn_points.size():
		return _spawn_points
	var team := Net.player_team(peer_id)
	var pool: Array[Transform3D] = []
	for i in _spawn_points.size():
		if _capture_layout.pad_team[i] == team:
			pool.append(_spawn_points[i])
	return pool if not pool.is_empty() else _spawn_points


func _spawn_gub(peer_id: int) -> void:
	var spawn := _next_spawn(peer_id)
	var life := _life_of(peer_id)
	_create_gub.rpc(peer_id, spawn, life)
	_create_gub(peer_id, spawn, life)


## Which life a Gub is about to begin, as the host counts it: its deaths so far.
##
## Handed to `Gub.revive_at` on every peer, so that every copy of one Gub agrees
## which life a snapshot belongs to and can refuse one from a life that is over
## (D-043). Deaths rather than a counter of its own, because it is already the
## host's number, it only ever goes up, and every respawn follows exactly one of
## them — so a second count kept beside it could only ever be a chance to
## disagree with it.
func _life_of(peer_id: int) -> int:
	return int(stats.get(peer_id, {}).get("deaths", 0))


@rpc("authority", "call_remote", "reliable")
func _create_gub(peer_id: int, spawn: Transform3D, life: int) -> void:
	if not _arena_is_standing() or gubs.has(peer_id):
		return
	var gub := GUB_SCENE.instantiate() as Gub
	gub.name = "Gub_%d" % peer_id
	gub.peer_id = peer_id
	gub.display_name = Net.player_name(peer_id)
	gub.team = Net.player_team(peer_id)
	# Ownership is set *before* the node enters the tree, which is also what
	# Godot's own spawner pattern does. Set it afterwards and every child whose
	# `_ready` branches on `is_local()` runs once believing it belongs to this
	# client: in particular each remote Gub's camera rig makes itself current, so
	# the last Gub spawned steals the viewport and the player spends the match
	# looking out of somebody else's head.
	gub.set_multiplayer_authority(peer_id)
	# ...with one node held back: `Combat` belongs to the **host** on every
	# machine, including the machine that owns the Gub.
	#
	# The owner decides *when* it wants to throw; the host decides *whether* the
	# throw happened, and the `_do_*` calls that make an ability real are
	# broadcast by peer 1 (D-004, D-024). Godot checks an `@rpc("authority")`
	# against whoever owns the node it *lands on*, so while `Combat` belonged to
	# the client every one of those broadcasts was refused on arrival — on every
	# peer, including the thrower's own. A non-host's spear never left their
	# hand, their mushroom and lure appeared for nobody, and the only thing that
	# still worked was the local cooldown prediction, so it looked like a
	# rendering problem rather than a networking one. The host's own abilities
	# were fine purely because for the host's Gub the owner and the host are the
	# same peer.
	#
	# Non-recursive on purpose. `Combat` has no children today, but the flag is
	# the statement: exactly one node changes hands, and the
	# `MultiplayerSynchronizer` beside it must keep belonging to the peer whose
	# position it publishes.
	var combat := gub.get_node_or_null("Combat")
	if combat != null:
		combat.set_multiplayer_authority(1, false)

	_players_root.add_child(gub)
	# `revive_at` rather than assigning the transform: it also seeds the
	# replicated fields, one by one and by hand. Without that, every other peer's
	# copy starts with `sync_position` at the arena origin and visibly slides in
	# from the middle of the map before the owner's first packet arrives — and
	# `sync_grounded` is worse, because the value a remote copy would compute for
	# itself is permanently false and the owner's never changes, so ON_CHANGE
	# replication has nothing to correct it with. See D-029.
	gub.revive_at(spawn, life)
	gub.grant_invulnerability(config().spawn_protection)

	var shown_team := gub.team if config().mode == MatchConfig.Mode.TEAMS \
		else MatchConfig.TEAM_NONE
	# The body and the plate always agree, including in free-for-all, where both
	# are neutral (D-046).
	gub.set_team_tint(shown_team)
	var plate := gub.get_node_or_null("Nameplate") as Nameplate
	if plate != null:
		plate.set_display_name(gub.display_name)
		plate.set_team(shown_team)
		plate.set_ally(is_teammate(peer_id))
		# You do not need a label telling you your own name.
		plate.visible = peer_id != Net.local_id()

	gubs[peer_id] = gub
	if not stats.has(peer_id):
		stats[peer_id] = _new_stats()


func _respawn(peer_id: int) -> void:
	var spawn := _next_spawn(peer_id)
	var entry: Dictionary = stats[peer_id]
	entry["alive"] = true
	entry["respawn_at"] = 0.0
	entry["last_attacker"] = 0
	# Belt and braces for D-038, and free when there is nothing to do. Nothing
	# that can kill an Elder leaves the robe on today — the void ends it in
	# `report_kill` — but a Gub coming back from a death is the one Gub that
	# certainly should not be wearing one, so it is said here rather than
	# trusted. Through `_end_elder`, before the respawn goes out, so the row and
	# the cloth come off together on every peer and in that order.
	_end_elder(peer_id)
	var life := _life_of(peer_id)
	_do_respawn.rpc(peer_id, spawn, life)
	_do_respawn(peer_id, spawn, life)
	_push_scores()


@rpc("authority", "call_remote", "reliable")
func _do_respawn(peer_id: int, spawn: Transform3D, life: int) -> void:
	var gub: Gub = gubs.get(peer_id)
	if not is_instance_valid(gub):
		return
	gub.visible = true
	gub.revive_at(spawn, life)
	gub.grant_invulnerability(config().spawn_protection)
	var combat := gub.get_node_or_null("Combat") as GubCombat
	if combat != null:
		combat.reset()
	if peer_id == Net.local_id():
		AudioDirector.play_2d(AudioDirector.RESPAWN)
		local_respawn.emit()


# ------------------------------------------------------------------- kills ---

## Host only. The single place a death is decided.
## `blow` is the killing blow's velocity — speed as well as direction, because
## the corpse's flight is the whole feedback for a kill and a spear that has
## dropped out of a long arc should shove a body far less than a flat one.
func report_kill(victim_id: int, killer_id: int, cause: Gub.Cause,
		point: Vector3, blow: Vector3, bone: String) -> void:
	if not Net.is_host or phase != Phase.PLAYING:
		return
	var entry: Dictionary = stats.get(victim_id, {})
	if entry.is_empty() or not entry["alive"]:
		return

	var victim: Gub = gubs.get(victim_id)
	if is_instance_valid(victim) and victim.is_invulnerable() and cause != Gub.Cause.VOID:
		return

	# Friendly fire is off by default, so a team-mate's spear simply stops.
	if killer_id != victim_id and _same_team(killer_id, victim_id) \
			and not config().friendly_fire:
		return

	# **The Elder cannot be killed** (D-040). The user, after playing one:
	# *"they should be invincible, and it should last for 20 seconds rather then
	# until they die."* The two halves are one rule — with nothing able to kill
	# an Elder, "until they die" is "for the rest of the match", so the clock in
	# `_tick_elders` is what the robe now ends on.
	#
	# **The void still kills**, and that carve-out is not a nicety: it is the
	# same one spawn protection makes two lines above, for the same reason. A
	# Gub that cannot die to the void falls past the bottom of the island for
	# ever, alive, unreachable and unrespawnable. So the one thing that can end
	# an Elder early is the map itself.
	#
	# **After the friendly-fire check rather than beside the invulnerability
	# one**, and the ward below is why. A shot stopped because the thrower is on
	# your team was never going to kill you and the robe had nothing to do with
	# it; flashing a ward at it would credit the robe with a save it did not
	# make, on the one peer best placed to be confused about it. What reaches
	# here is a shot that would otherwise have landed.
	if is_elder(victim_id) and cause != Gub.Cause.VOID:
		# Exactly what `note_attack` is for, and this is its clearest case: an
		# attacker who hurt somebody without killing them is credited if the
		# victim goes off the edge shortly afterwards. An Elder shoved by a
		# lightning bolt or lured over a ledge is precisely that, and the void
		# is the only death it has.
		if killer_id != victim_id:
			note_attack(victim_id, killer_id)
		# The one piece of feedback there is. A spear that hits an Elder is
		# turned aside rather than buried (`SpearProjectile._glance_off`), so
		# without this the strongest weapon in the game would simply vanish
		# against the strongest target in it and nobody at either end would know
		# whether the throw had even happened.
		_do_ward.rpc(victim_id, point)
		_do_ward(victim_id, point)
		return

	entry["alive"] = false
	entry["deaths"] += 1
	entry["respawn_at"] = _now() + config().respawn_delay
	if config().win_condition == MatchConfig.WinCondition.LIVES:
		entry["lives_left"] = maxi(0, entry["lives_left"] - 1)

	if killer_id != victim_id and stats.has(killer_id):
		# Killing a team-mate costs you the point rather than earning one.
		var delta := -1 if _same_team(killer_id, victim_id) else 1
		stats[killer_id]["kills"] += delta

	_apply_death.rpc(victim_id, killer_id, cause, point, blow, bone)
	_apply_death(victim_id, killer_id, cause, point, blow, bone)
	# The robe is **consumed**, not dropped, and it is taken off here rather than
	# next to the loot roll on purpose. A letter card lands at the corpse for
	# whoever is standing over it; a robe simply ceases to exist, and the next
	# one arrives only when the drop table rolls another (D-038). That is the
	# opposite of the letter rule and it is deliberate: a robe that changed hands
	# at the corpse would hand the whole reward to whoever won the scramble
	# rather than to whoever won the fight.
	#
	# Since D-040 the only death that can reach this line with a robe on is a
	# void death — everything else was refused above. Which is exactly why the
	# call stays here rather than moving into `_tick_elders` beside the expiry:
	# this is what stops a robe being left attached to a body at the bottom of
	# the map, wearing out a twenty-second clock nobody can see.
	_end_elder(victim_id)
	# Before the loot roll, so that when a carrier is killed the card is the
	# first thing to appear at the corpse rather than the second. Both drop:
	# killing somebody nine seconds into a hold is the best thing that can
	# happen to you in this mode and it should look like it.
	_interrupt_letter_hold(victim_id, point)
	_drop_loot(cause, point)
	_push_scores()
	_check_win()


@rpc("authority", "call_remote", "reliable")
func _apply_death(victim_id: int, killer_id: int, cause: Gub.Cause,
		point: Vector3, blow: Vector3, bone: String) -> void:
	var victim: Gub = gubs.get(victim_id)
	if is_instance_valid(victim):
		victim.kill(killer_id, cause)
		# The corpse is a separate, local, cosmetic thing (D-010).
		if cause != Gub.Cause.VOID:
			# Passed through untouched: the ragdoll owns how a blow becomes
			# motion, and scaling it here as well would mean two files had to
			# agree on how hard a spear hits.
			GubRagdoll.spawn_from(victim, victim.get_parent(), blow, bone)
		victim.visible = false

	if is_instance_valid(victim):
		AudioDirector.play_3d_varied(AudioDirector.DEATH, victim.global_position)

	player_killed.emit(victim_id, killer_id, cause)
	if victim_id == Net.local_id():
		local_death.emit(config().respawn_delay)
		_shake(victim, 1.4)
	elif killer_id == Net.local_id():
		# The hitmarker is the only confirmation a thrower gets that a spear
		# landed: the victim may be sixty metres away and behind a tree, and the
		# spear itself is gone. It is deliberately 2D — it is feedback about
		# your own action, not a sound anyone else could hear.
		AudioDirector.play_2d(AudioDirector.HITMARKER)
		_shake(gubs.get(killer_id), 0.35)


## Kick the camera of one Gub, if that Gub still exists and is the one this
## client is looking through.
func _shake(gub: Gub, strength: float) -> void:
	if not is_instance_valid(gub):
		return
	var rig := gub.get_node_or_null("CameraRig") as GubCamera
	if rig != null:
		rig.shake(strength)


## Note that `attacker` hurt `victim` without killing them, so a subsequent fall
## into the void can still be credited. Host only.
func note_attack(victim_id: int, attacker_id: int) -> void:
	if not Net.is_host or not stats.has(victim_id):
		return
	stats[victim_id]["last_attacker"] = attacker_id
	stats[victim_id]["last_attacker_at"] = _now()


func _same_team(a: int, b: int) -> bool:
	if config().mode != MatchConfig.Mode.TEAMS:
		return false
	return Net.player_team(a) == Net.player_team(b)


# ------------------------------------------------------------------- drops ---

## One item falls out of every death. This is where everything a Gub can gain
## now comes from (D-032): abilities are not granted by a timer any more, so a
## match with nobody dying in it is a match where nobody is armed with anything
## but a spear.
##
## Host only, rolled once, replicated — the roll must not be made per-peer or
## eight machines would each draw a different card for the same corpse.
##
## The dropped item is an **independent roll**, not the victim's carried stock.
## What they were holding is simply lost. Dropping the actual inventory would
## make a player who had hoarded six mushrooms the most profitable thing on the
## map to kill, and the hoard would then bounce between two people who keep
## killing each other — stock has to leave the economy when its owner does, or
## nothing is ever really spent.
##
## Nothing drops for a `VOID` death: the Gub fell off the map, and an item
## spawned where it was is an item that falls too. A self-kill does drop. A
## death is a death, and making suicide the one death that costs the map an item
## is a rule nobody would guess and everybody would notice.
func _drop_loot(cause: Gub.Cause, point: Vector3) -> void:
	if cause == Gub.Cause.VOID:
		return
	var spot := _drop_spot(point)
	if spot == Vector3.INF:
		return

	# **The roll order is letter, then robe, then the remainder split evenly
	# between mushroom and lure**, and it is written down here because it is
	# exactly the kind of thing that silently changes the balance of the game
	# when somebody reorders it for tidiness. The two named chances are taken off
	# the top in that order and what is left is halved; move the robe in front of
	# the letter and a letters match quietly drops fewer cards than the dial in
	# the lobby says it does.
	#
	# Letters only exist as a drop in the mode that scores them; in every other
	# mode that chance is zero. **The robe is not gated on anything** — the Elder
	# is a weapon rather than a scoring mechanic, and a weapon that only exists
	# in one of four modes is a weapon nobody learns (D-038).
	#
	# The last branch reads the dials rather than the enum on purpose: the two
	# halves of the remainder stay halves whatever the first two numbers turn out
	# to be, including a host who has dragged both sliders to the top.
	var letters_on := config().win_condition == MatchConfig.WinCondition.LETTERS
	var letter_chance := config().letter_drop_chance if letters_on else 0.0
	var robe_chance := config().elder_drop_chance
	var remainder := maxf(0.0, 1.0 - letter_chance - robe_chance)
	var roll := randf()
	var kind := Pickup.Kind.LURE
	var letter := 0
	if roll < letter_chance:
		kind = Pickup.Kind.LETTER
		# Uniform over G, U and B, with no reference to anybody's progress
		# (D-033). A card is a card.
		letter = LETTERS[randi() % LETTERS.size()]
	elif roll < letter_chance + robe_chance:
		kind = Pickup.Kind.ELDER_ROBE
	elif roll < letter_chance + robe_chance + remainder * 0.5:
		kind = Pickup.Kind.MUSHROOM

	_spawn_drop(kind, letter, spot)


## Put one item on the ground at `spot`, on every peer, and return the id it was
## given. Host only — `_next_pickup_id` is the host's counter and an id minted
## anywhere else would collide with one the host is about to hand out.
##
## Shared by the loot roll above and by the card a dead carrier drops (D-035),
## which is the whole reason it is its own function: a re-dropped letter has to
## be the same kind of object as a rolled one, indistinguishable to anybody who
## walks over it.
func _spawn_drop(kind: Pickup.Kind, letter: int, spot: Vector3) -> int:
	var id := _next_pickup_id
	_next_pickup_id += 1
	_spawn_pickup.rpc(id, kind, letter, spot)
	_spawn_pickup(id, kind, letter, spot)
	return id


## Settle the death point onto the ground, or `Vector3.INF` if there is none
## under it. The same shape as `GubCombat._mushroom_spot`'s ground query and for
## the same reason: an item floating over a gorge is an item nobody can reach,
## and skipping the drop is a better answer than teasing the lobby with one.
func _drop_spot(point: Vector3) -> Vector3:
	var world := _world()
	if world == null:
		return Vector3.INF
	var from := point + Vector3.UP * DROP_RAY_UP
	var query := PhysicsRayQueryParameters3D.create(
		from, from + Vector3.DOWN * (DROP_RAY_UP + DROP_RAY_DOWN))
	query.collision_mask = 1  # world geometry only
	var hit := world.direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else Vector3.INF


## The 3D world the match is being played in, or null when there is not one.
##
## `tools/match_rules.gd` registers a plain `Node` as its players root on
## purpose — it is about the bookkeeping and never spawns a Gub — so there is no
## space to cast a ray in, and asking for one would be a `SCRIPT ERROR` on every
## kill it scores. A null here means "no world", and the only caller treats that
## as "no drop" rather than as a failure.
func _world() -> World3D:
	var root := _players_root as Node3D
	if root == null or not root.is_inside_tree():
		return null
	return root.get_world_3d()


## Everything a match spawns goes into one container so the arena can sweep it
## between rounds. The same group `GubCombat._spawn_root` looks for, and the
## same fallback.
func _spawn_root() -> Node:
	var root := get_tree().get_first_node_in_group("spawned_items")
	return root if root != null else get_tree().current_scene


## Drop the index rows for items that have already been taken or have rotted.
## They are harmless — every reader guards with `is_instance_valid` — but there
## is one per death for the length of a match, and the same broom `GubCombat`
## sweeps its mushroom list with costs nothing here.
##
## Written as a rebuild rather than `Dictionary.filter`, which Godot 4.7 does
## not have: it exists on Array and not on Dictionary, and reaching for it cost
## an afternoon because the parse error takes the whole `MatchState` autoload
## down with it. Every scenario in `tools/match_rules.gd` then ran against a
## `Nil` singleton, and the harness still printed PASS, because a check that
## never runs is not a check that failed.
func _prune_pickups() -> void:
	var live := {}
	for id: int in _pickups:
		var item: Pickup = _pickups[id]
		if is_instance_valid(item) and not item.is_taken():
			live[id] = item
	_pickups = live


## Build one drop, on every peer, from the values the host rolled.
@rpc("authority", "call_remote", "reliable")
func _spawn_pickup(id: int, kind: int, letter: int, spot: Vector3) -> void:
	var root := _spawn_root()
	if root == null:
		return
	_prune_pickups()

	var pickup := PICKUP_SCENE.instantiate() as Pickup
	root.add_child(pickup)
	pickup.drop(id, kind as Pickup.Kind, letter, spot)
	_pickups[id] = pickup


## A living Gub has walked into a drop. Called by the **host's** copy of the
## pickup, directly — the overlap already happened on the host, so there is
## nothing to request.
##
## This is the one place a drop is awarded, which is what makes "collected once"
## true: two Gubs entering on the same physics frame both arrive here, and the
## second finds the item already taken.
func claim_pickup(pickup_id: int, peer_id: int) -> void:
	if not Net.is_host or phase != Phase.PLAYING:
		return
	var pickup: Pickup = _pickups.get(pickup_id)
	if not is_instance_valid(pickup) or pickup.is_taken():
		return
	if not is_alive(peer_id):
		return

	match pickup.kind:
		Pickup.Kind.LETTER when is_capture():
			# Capture G·U·B (D-051), as amended by the vault (D-068). One letter
			# carried at a time, always.
			if is_holding_letter(peer_id):
				return
			# A card standing in *any* vault is not picked up by walking over it
			# (D-068). Your own team's must not be undone by brushing past it,
			# and an enemy's comes out on a timer rather than on contact —
			# `_tick_steals` owns that, so a thief has to stand still for it and
			# a defender has time to arrive.
			if banked_team_of(pickup.letter) != MatchConfig.TEAM_NONE:
				return
			if scoring_letters(peer_id) & pickup.letter != 0:
				# Loose on the map, and a letter this team already holds. Left
				# exactly where it is, as it always was.
				return
			_begin_capture_carry(peer_id, pickup.letter)
		Pickup.Kind.LETTER:
			# **One hold at a time** (D-035). A card walked over while a hold is
			# already running is left exactly where it is — not consumed, not
			# queued — for this Gub to come back to or for somebody else to
			# reach first. Returning here rather than falling through is what
			# leaves it on the ground.
			if is_holding_letter(peer_id):
				return
			# Otherwise the card is spent whatever happens next: a duplicate
			# grants nothing and vanishes anyway (D-033), and anything else
			# starts the hold that now stands between a card and a letter.
			_begin_letter_hold(peer_id, pickup.letter)
		Pickup.Kind.MUSHROOM:
			_grant_ability(peer_id, "grant_mushroom")
		Pickup.Kind.LURE:
			_grant_ability(peer_id, "grant_lure")
		Pickup.Kind.ELDER_ROBE:
			# No guard for "already the Elder". The robe cannot be picked up by
			# somebody already wearing one, because `_make_elder` is idempotent
			# and the item is spent either way — the same rule a duplicate
			# letter obeys (D-033), and for the same reason: a drop that refuses
			# to be collected is a drop three players take turns walking over.
			_make_elder(peer_id)

	_take_pickup.rpc(pickup_id, peer_id)
	_take_pickup(pickup_id, peer_id)


## Hand one item to a Gub's combat node. Host side only: `GubCombat` owns the
## stock and broadcasts the new count itself, because it is the host's node on
## every machine (D-024) and is therefore the only thing whose word on it the
## other peers will accept.
func _grant_ability(peer_id: int, method: String) -> void:
	var gub: Gub = gubs.get(peer_id)
	if not is_instance_valid(gub):
		return
	var combat := gub.get_node_or_null("Combat") as GubCombat
	if combat != null:
		combat.call(method, 1)


@rpc("authority", "call_remote", "reliable")
func _take_pickup(pickup_id: int, peer_id: int) -> void:
	var pickup: Pickup = _pickups.get(pickup_id)
	_pickups.erase(pickup_id)
	if is_instance_valid(pickup):
		pickup.take(peer_id)


## Take an item off the ground with nobody collecting it, on every peer. The
## host's word that a dropped Capture G·U·B card has lain long enough (D-051);
## it withers where it lies, and the same letter is spawned at home.
@rpc("authority", "call_remote", "reliable")
func _withdraw_pickup(pickup_id: int) -> void:
	var pickup: Pickup = _pickups.get(pickup_id)
	_pickups.erase(pickup_id)
	if is_instance_valid(pickup):
		pickup.wither()


# ----------------------------------------------------------------- letters ---

## Give `peer_id` one letter. Host only. Returns whether it was one they did not
## already hold — false means the card was wasted, which is the rule (D-033) and
## not a failure.
##
## Reached from the end of a hold rather than from the card itself (D-035):
## touching a card starts a countdown and only finishing it arrives here. The
## exception is a `letter_hold_time` of zero, which calls this straight from
## `_begin_letter_hold` because that setting is exactly "no countdown".
func award_letter(peer_id: int, letter: int) -> bool:
	if not Net.is_host or phase != Phase.PLAYING:
		return false
	var entry: Dictionary = stats.get(peer_id, {})
	if entry.is_empty():
		return false
	# Judged against what the *team* holds in Teams (D-049): a G your teammate
	# already banked is a duplicate in your hands too, wasted exactly as D-033
	# wastes one of your own. In a free-for-all this is the player's own mask.
	if scoring_letters(peer_id) & letter != 0:
		return false
	var next := int(entry.get("letters", 0)) | letter
	var team := _pooling_team(peer_id)
	var team_mask := (team_letters(team) | letter) if team != MatchConfig.TEAM_NONE else 0
	_sync_letters.rpc(peer_id, next, team, team_mask, letter)
	_sync_letters(peer_id, next, team, team_mask, letter)
	# A teammate standing still for the letter that was just banked is now
	# standing still for nothing. Ended here, and the card spent rather than
	# re-dropped, for the reason `_begin_letter_hold` refuses to start that hold
	# at all: a ten-second countdown whose reward is "no change" is the most
	# miserable thing in the mode, and a duplicate is consumed on touch (D-033).
	if team != MatchConfig.TEAM_NONE:
		for other: int in _letter_holds.keys():
			if other != peer_id and _pooling_team(other) == team \
					and int(_letter_holds[other]["letter"]) == letter:
				_end_letter_hold(other)
	# `stats` rides along with the score push anyway; pushing here keeps the two
	# from disagreeing for the frame in between.
	_push_scores()
	_check_win()
	return true


## Written on every peer rather than left to ride along on the next
## `_sync_scores`, because a letter is the one score change that has to be
## *felt* the instant it happens — the HUD lamp and the sound hang off this
## signal, and the next score push may be a whole kill away.
##
## The team's pooled mask rides in the same message rather than in a second one,
## so no peer can ever see a player's lamp lit and their team's not (D-049).
## `team` is `TEAM_NONE` outside Teams, and then `team_mask` means nothing.
@rpc("authority", "call_remote", "reliable")
## `letter` is the one just banked, for `letter_banked` — carried rather than
## worked out from the old mask, because a client's copy of the old mask is a
## score push behind often enough to announce the wrong letter.
func _sync_letters(peer_id: int, mask: int, team: int, team_mask: int, letter: int) -> void:
	if team != MatchConfig.TEAM_NONE:
		_team_letters[team] = team_mask
	var entry: Dictionary = stats.get(peer_id, {})
	if not entry.is_empty():
		entry["letters"] = mask
	letters_changed.emit(peer_id)
	scores_changed.emit()
	# `letter` is 0 when this push is a *revoke* — a card taken back out of a
	# vault (D-068). The mask still has to move on every peer, but nothing was
	# banked, so the fanfare the HUD and the sound hang off must not fire.
	if letter != 0:
		letter_banked.emit(peer_id, letter)


## The three-bit mask of letters this player holds. Safe to ask for a peer with
## no row — a spectator, or somebody who left mid-frame — which is what the HUD
## and the scoreboard both do.
func letters_for(peer_id: int) -> int:
	return int(stats.get(peer_id, {}).get("letters", 0))


## The pooled three-bit mask of one team (D-049): every letter any member has
## banked this match, including members who have since left. 0 for a team with
## nothing, for `TEAM_NONE`, and for everybody in a free-for-all.
func team_letters(team: int) -> int:
	return int(_team_letters.get(team, 0))


## The mask a letter is judged against and a match is won on: the player's team's
## pooled mask in Teams, the player's own everywhere else. What a *duplicate*
## means, what the HUD lamps show and what `_check_win` tests all read this, so
## the three cannot disagree about whose letters count.
func scoring_letters(peer_id: int) -> int:
	var team := _pooling_team(peer_id)
	if team != MatchConfig.TEAM_NONE:
		return team_letters(team)
	return letters_for(peer_id)


## The team whose letters `peer_id` pools into, or `TEAM_NONE` when letters are
## not pooled — a free-for-all, or a player with no team in the roster.
func _pooling_team(peer_id: int) -> int:
	if config().mode != MatchConfig.Mode.TEAMS:
		return MatchConfig.TEAM_NONE
	return Net.player_team(peer_id)


func has_all_letters(peer_id: int) -> bool:
	return scoring_letters(peer_id) & LETTER_ALL == LETTER_ALL


## How many distinct letters a team has pooled. What the scoreboard and the
## results screen order teams by under the letters condition.
func team_letter_count(team: int) -> int:
	return _bit_count(team_letters(team))


## How many distinct letters a player holds. The scoreboard sorts on this, and
## "2 of 3" is the only number worth printing beside three lamps.
func letter_count(peer_id: int) -> int:
	return _bit_count(letters_for(peer_id))


static func _bit_count(mask: int) -> int:
	var count := 0
	for bit: int in LETTERS:
		if mask & bit != 0:
			count += 1
	return count


## The character one letter bit stands for. One table, here, so the card lying
## in the world and the lamp on the HUD can never disagree about which bit is
## which.
static func letter_name(letter: int) -> String:
	match letter:
		LETTER_G:
			return "G"
		LETTER_U:
			return "U"
		LETTER_B:
			return "B"
		_:
			return "?"


# -------------------------------------------------------------- the hold ---

## Picking up a card does not give you the letter. It starts a hold: the Gub
## holds the card up for `letter_hold_time` seconds, cannot throw a spear for
## any of them, and only then is the letter actually theirs (D-035).
##
## **It lives here rather than on the Gub** because it is match state. It has to
## survive being watched by seven peers who collected nothing, it ends in
## `award_letter` which is already here, and — the part that matters — the host
## has to be the only machine that can finish one. A hold on `GubCombat` would
## be a countdown running on the client that stands to gain from it.


## Begin the hold a letter card now buys. Host only, and only from
## `claim_pickup`, which has already established that this player is alive, in a
## running match, and not already holding something.
func _begin_letter_hold(peer_id: int, letter: int) -> void:
	var entry: Dictionary = stats.get(peer_id, {})
	if entry.is_empty():
		return
	# A letter you already hold is worth exactly nothing whether you stand still
	# for it or not, so there is nothing to stand still for: the card is
	# consumed on touch, instantly, the way it always was (D-033). Starting a
	# ten-second hold whose reward is "no change" would be the single most
	# miserable thing in the mode.
	#
	# In Teams "already hold" means the team does (D-049): a teammate's banked
	# G makes the next G card a duplicate for everybody on that team.
	if scoring_letters(peer_id) & letter != 0:
		return
	var seconds := config().letter_hold_time
	# Zero means grant on touch, which is a legal setting and a supported one.
	# Taken here rather than by starting a hold that expires on the next tick,
	# because that hold would still be one frame long — one frame of the spear
	# leaving the hand and coming back, for a setting chosen precisely so that
	# there is nothing to watch.
	if seconds <= 0.0:
		award_letter(peer_id, letter)
		return
	_do_begin_hold.rpc(peer_id, letter, seconds)
	_do_begin_hold(peer_id, letter, seconds)


## Host only. Finish the holds whose time is up.
##
## The award is made *after* the row is cleared, in that order and not the other
## way round, so that by the time `letters_changed` reaches the HUD and
## `_check_win` reaches the results screen the player is no longer holding
## anything: the lamp lights and the spear comes back on the same frame.
func _tick_letter_holds() -> void:
	# `.keys()` copies, because completing a hold erases its own row.
	for peer_id: int in _letter_holds.keys():
		# Not only its own: in Teams, banking a letter ends every teammate's hold
		# for the same one (D-049), so a row later in this copy can be gone.
		if not _letter_holds.has(peer_id):
			continue
		var hold: Dictionary = _letter_holds[peer_id]
		if _now() < float(hold["ends_at"]):
			continue
		var letter := int(hold["letter"])
		_end_letter_hold(peer_id)
		award_letter(peer_id, letter)


## A hold that ended without paying out: a death, or a disconnect, which is
## treated identically. Host only.
##
## **The card is not destroyed.** It lands at `at` as a fresh pickup carrying
## the same letter, free for anyone including the Gub that just lost it. At an
## 8% drop rate a letter can be a hundred deaths from being replaced, so a card
## that evaporates every time its carrier is killed is a mode that stops being
## winnable — and "kill the carrier and take the card" is the fight this whole
## mechanic exists to create. Deleting it would leave only the first half.
##
## `Vector3.INF` means there is nowhere to put it — a peer whose Gub was already
## gone by the time the disconnect was noticed — and then, and only then, the
## card is discarded.
func _interrupt_letter_hold(peer_id: int, at: Vector3) -> void:
	if not _letter_holds.has(peer_id):
		return
	var letter := int(_letter_holds[peer_id]["letter"])
	_end_letter_hold(peer_id)
	if is_capture():
		_drop_capture_card(peer_id, letter, at)
		return
	if at == Vector3.INF:
		return
	# The ground under the corpse, or — when there is none — a spawn pad.
	#
	# `_drop_loot` simply skips a drop it cannot settle, and for a mushroom that
	# is right: one more mushroom exists after the next death. A letter does
	# not. So a card that would otherwise be lost over a gorge, or to the void a
	# lured carrier was just knocked into, is put back on a pad instead: the
	# pads are the one set of points on any map that are guaranteed to be
	# standable and reachable, and a card that turns up somewhere slightly
	# arbitrary is a far smaller problem than a letter that leaves the match.
	var spot := _drop_spot(at)
	if spot == Vector3.INF:
		spot = _next_spawn().origin
	_spawn_drop(Pickup.Kind.LETTER, letter, spot)


## Host only. Stop a hold and tell everyone, without deciding why.
func _end_letter_hold(peer_id: int) -> void:
	if not _letter_holds.has(peer_id):
		return
	_do_end_hold.rpc(peer_id)
	_do_end_hold(peer_id)


@rpc("authority", "call_remote", "reliable")
func _do_begin_hold(peer_id: int, letter: int, seconds: float) -> void:
	_letter_holds[peer_id] = {"letter": letter, "ends_at": _now() + seconds}
	letter_hold_changed.emit(peer_id)
	letter_picked_up.emit(peer_id, letter)


@rpc("authority", "call_remote", "reliable")
func _do_end_hold(peer_id: int) -> void:
	if not _letter_holds.erase(peer_id):
		return
	letter_hold_changed.emit(peer_id)


## Drop every hold locally, granting nothing. Used when the match ends and when
## the whole match is torn down — neither is a moment anybody is owed a letter.
func _clear_letter_holds() -> void:
	if _letter_holds.is_empty():
		return
	var were_holding := _letter_holds.keys()
	_letter_holds.clear()
	for peer_id: int in were_holding:
		letter_hold_changed.emit(peer_id)


## Is this Gub holding a card up right now?
##
## The presence of the row, deliberately, and never `remaining > 0`: a client's
## countdown can reach zero a round trip before the host's does, and a hand that
## takes its spear back on that frame would be a hand the host still refuses to
## throw with.
func is_holding_letter(peer_id: int) -> bool:
	return _letter_holds.has(peer_id)


## Seconds left on this Gub's hold, or 0.0 if it is not holding one. Never
## negative, so a HUD can divide by `Net.config.letter_hold_time` and get a
## fraction it can sweep a ring with.
func letter_hold_remaining(peer_id: int) -> float:
	if not _letter_holds.has(peer_id):
		return 0.0
	return maxf(0.0, float(_letter_holds[peer_id]["ends_at"]) - _now())


## Which letter bit is being held up, or 0 if none — one of `LETTER_G/U/B`, so
## `letter_name` turns it straight into the glyph on the card.
func letter_hold_letter(peer_id: int) -> int:
	if not _letter_holds.has(peer_id):
		return 0
	return int(_letter_holds[peer_id]["letter"])


# ---------------------------------------------------------- capture G·U·B ---

## Capture the flag with the three letters (D-051). The user: *"capture the flag
## game mode with the letters, you have to pick up the letter and drop it in
## your base, there are only 3 and dont drop from users dying"*.
##
## **Three cards, spawned once, never rolled.** G, U and B go out at their home
## points when the match starts and there are never more than three: no corpse
## drops a letter in this mode (`_drop_loot` only rolls cards under LETTERS).
##
## **A carry is a hold with no clock.** Touching a card starts a row in
## `_letter_holds` whose deadline is infinity, so everything D-035 and D-050
## built on that row comes for free and cannot disagree: the card in the fist,
## no spear or bolt while carrying, the gold marker over the carrier's head on
## every screen, the "picked up" feed line. What ends it is not a clock but one
## of three things — walking into your own base (banked), dying or leaving
## (dropped), or the match ending.
##
## **Banking** adds the letter to the carrier's team mask through `award_letter`,
## exactly as a finished hold does, and the card goes straight back to its home
## point so both teams can still fight over it. A team whose mask is full wins.
## A team cannot pick up a letter it has already banked; the card is left where
## it is for the other team, so a team that is ahead cannot sit on the letters
## the other team still needs.
##
## **A dead carrier's card drops where they died** and lies there for
## `capture_return_time` seconds, for anybody to take — the carrier's own team
## included — and then goes home. A death with no ground under it (the void, a
## gorge) sends it home at once: a letter must never leave the match, or the
## match can deadlock.


## Called by `arena.gd` before `register_arena`, with whatever the map declared
## (empty for a map that declares nothing, which is every map today).
func set_capture_map(bases: Array[Vector3], letters: Array[Vector3],
		radius: float = CaptureLayout.DEFAULT_BASE_RADIUS) -> void:
	_capture_declared_bases = bases
	_capture_declared_letters = letters
	_capture_declared_radius = radius


func is_capture() -> bool:
	return config().win_condition == MatchConfig.WinCondition.CAPTURE


## The layout planned for the arena currently registered, or null before one is.
func capture_layout() -> CaptureLayout:
	return _capture_layout


## Host only. Where each letter is: "home", "carried" or "dropped", or "" when
## the cards are not out. For harnesses and the HUD; the rules read `_capture`.
func capture_state(letter: int) -> String:
	var entry: Dictionary = _capture.get(letter, {})
	if entry.is_empty():
		return ""
	if int(entry["carrier"]) != 0:
		return "carried"
	return "dropped" if float(entry["return_at"]) > 0.0 else "home"


## Put the three cards out, once the physics can say where the ground is.
func _try_spawn_capture_letters() -> void:
	if _capture_layout == null or not _arena_is_standing():
		return
	# Two physics frames after registering, so a static map's collision, built
	# in its own `_ready`, is in the broadphase before anything asks it for a
	# floor. A world-less harness root has nothing to wait for.
	if _world() != null and Engine.get_physics_frames() < _arena_physics_frame + 2:
		return
	_spawn_capture_letters()


## Host only. Settle the home points and spawn G, U and B on them.
func _spawn_capture_letters() -> void:
	_capture_pending = false
	_capture.clear()
	if _capture_layout == null or _capture_layout.letters.size() < LETTERS.size():
		push_warning("MatchState: no letter points for Capture G·U·B")
		return
	var world := _world()
	var homes := _capture_layout.settle_letters(
		world.direct_space_state if world != null else null)
	for i in LETTERS.size():
		var letter := LETTERS[i]
		_capture[letter] = {"home": homes[i], "pickup": 0, "carrier": 0, "return_at": 0.0}
		_send_capture_home(letter, false)


## Host only. Put `letter` on its home point, withdrawing any copy still lying
## somewhere else, and optionally say so in the feed.
func _send_capture_home(letter: int, announce: bool) -> void:
	var entry: Dictionary = _capture.get(letter, {})
	if entry.is_empty():
		return
	var lying := int(entry["pickup"])
	if lying != 0:
		_withdraw_pickup.rpc(lying)
		_withdraw_pickup(lying)
	entry["carrier"] = 0
	entry["return_at"] = 0.0
	entry["banked_team"] = MatchConfig.TEAM_NONE
	entry["pickup"] = _spawn_drop(Pickup.Kind.LETTER, letter, entry["home"])
	if announce:
		_announce_capture.rpc(0, letter)
		_announce_capture(0, letter)


## Host only, from `claim_pickup`, which has checked that this Gub is alive,
## carrying nothing, and on a team that still needs this letter.
@rpc("authority", "call_remote", "reliable")
func _announce_steal(peer_id: int, letter: int, from_team: int) -> void:
	letter_stolen.emit(peer_id, letter, from_team)


func _begin_capture_carry(peer_id: int, letter: int) -> void:
	var entry: Dictionary = _capture.get(letter, {})
	if not entry.is_empty():
		entry["pickup"] = 0
		entry["carrier"] = peer_id
		entry["return_at"] = 0.0
		# Once it is in a fist it is in nobody's vault, whether it left one by
		# being stolen or was only ever loose (D-068).
		entry["banked_team"] = MatchConfig.TEAM_NONE
	# INF is the whole difference between a carry and a hold: no tick ever
	# finishes it, and `letter_hold_remaining` answers INF for it.
	_do_begin_hold.rpc(peer_id, letter, INF)
	_do_begin_hold(peer_id, letter, INF)


## Host only. A carry ended by a death or a disconnect: the card lands at `at`
## for `capture_return_time`, or goes home now if it cannot land.
func _drop_capture_card(peer_id: int, letter: int, at: Vector3) -> void:
	var entry: Dictionary = _capture.get(letter, {})
	if entry.is_empty():
		return
	var spot := _drop_spot(at) if at != Vector3.INF else Vector3.INF
	if spot == Vector3.INF:
		_send_capture_home(letter, true)
		return
	entry["carrier"] = 0
	entry["pickup"] = _spawn_drop(Pickup.Kind.LETTER, letter, spot)
	entry["return_at"] = _now() + config().capture_return_time
	_announce_capture.rpc(peer_id, letter)
	_announce_capture(peer_id, letter)


## Host only, every frame of a running match. Banks carriers standing in their
## own base and sends home cards that have lain dropped too long.
## Host only: peer -> {"letter", "team", "since"}. How far through lifting a
## card out of an enemy vault each thief is (D-068). Not replicated as a
## dictionary — the progress each client draws comes from `_announce_steal_progress`.
var _steals: Dictionary = {}


## Host only. Everybody standing on a vault that is not theirs, holding nothing,
## with a card actually in it. Standing still for `capture_steal_time` lifts it.
##
## Anything that is not "still standing there, still alive, still empty-handed,
## card still in that vault" drops the attempt — there is no partial progress
## kept, because a thief who can chip away at a vault in half-second visits is a
## thief the defender can never actually stop.
func _tick_steals() -> void:
	if not Net.is_host or phase != Phase.PLAYING or _capture_layout == null:
		return
	var wanted := maxf(0.1, config().capture_steal_time)
	for peer_id: int in gubs.keys():
		var gub: Gub = gubs.get(peer_id)
		var keep := false
		if is_instance_valid(gub) and gub.alive and is_alive(peer_id) 				and not is_holding_letter(peer_id):
			var team := _capture_layout.vault_team(gub.global_position)
			var mine := _pooling_team(peer_id)
			if team != MatchConfig.TEAM_NONE and team != mine:
				var letter := _letter_in_vault(team)
				if letter != 0:
					var row: Dictionary = _steals.get(peer_id, {})
					if int(row.get("letter", 0)) != letter:
						row = {"letter": letter, "team": team, "since": _now()}
						_steals[peer_id] = row
					keep = true
					if _now() - float(row["since"]) >= wanted:
						_steals.erase(peer_id)
						_take_from_vault(peer_id, letter, team)
						continue
		if not keep and _steals.has(peer_id):
			_steals.erase(peer_id)
			_announce_steal_progress.rpc(peer_id, 0, 0.0)
			_announce_steal_progress(peer_id, 0, 0.0)
			continue
		if keep:
			var row: Dictionary = _steals[peer_id]
			var done := clampf((_now() - float(row["since"])) / wanted, 0.0, 1.0)
			_announce_steal_progress.rpc(peer_id, int(row["letter"]), done)
			_announce_steal_progress(peer_id, int(row["letter"]), done)


## The letter standing in `team`'s vault, or 0.
func _letter_in_vault(team: int) -> int:
	for letter: int in _capture:
		if int(_capture[letter].get("banked_team", MatchConfig.TEAM_NONE)) == team:
			return letter
	return 0


## Host only. The steal completes: the bit comes off the robbed team and the
## thief picks the card up in the same breath.
func _take_from_vault(peer_id: int, letter: int, team: int) -> void:
	_revoke_letter(letter, team)
	_announce_steal.rpc(peer_id, letter, team)
	_announce_steal(peer_id, letter, team)
	var entry: Dictionary = _capture.get(letter, {})
	var lying := int(entry.get("pickup", 0))
	if lying != 0:
		_withdraw_pickup.rpc(lying)
		_withdraw_pickup(lying)
	_begin_capture_carry(peer_id, letter)


## How far through a steal `peer_id` is, 0 to 1, for the HUD. 0 when not stealing.
@rpc("authority", "call_remote", "reliable")
func _announce_steal_progress(peer_id: int, letter: int, done: float) -> void:
	steal_progress.emit(peer_id, letter, done)


func _tick_capture() -> void:
	if not is_capture() or _capture_layout == null:
		return
	_tick_steals()
	for peer_id: int in _letter_holds.keys():
		if not _letter_holds.has(peer_id) or phase != Phase.PLAYING:
			continue
		var gub: Gub = gubs.get(peer_id)
		# Alive twice over: the host's row and the body. A dead Gub's body keeps
		# its collision where it fell (D-043), and a carrier killed on the edge of
		# the other team's base must not bank from the ground there.
		if not is_alive(peer_id) or not is_instance_valid(gub) or not gub.alive:
			continue
		# The vault, not the base (D-068). A base is somewhere you are; a vault is
		# something you walk up to and put a card on, and it has to be the same
		# spot an enemy comes to take one off.
		if _capture_layout.in_vault(Net.player_team(peer_id), gub.global_position):
			_bank_capture(peer_id)
	if phase != Phase.PLAYING:
		return
	for letter: int in _capture:
		var entry: Dictionary = _capture[letter]
		var due := float(entry["return_at"])
		if due > 0.0 and _now() >= due:
			_send_capture_home(letter, true)


## Host only. `peer_id` is alive in its own base with a card: score it and send
## the card home. Only its *own* base — the base check above asks for the
## carrier's team and nobody else's, so walking into the enemy's does nothing.
func _bank_capture(peer_id: int) -> void:
	var letter := letter_hold_letter(peer_id)
	if letter == 0:
		return
	var team := _pooling_team(peer_id)
	_end_letter_hold(peer_id)
	award_letter(peer_id, letter)
	# The award may have ended the match; the whistle leaves the cards alone.
	if phase != Phase.PLAYING:
		return
	_store_in_vault(letter, team, peer_id)


## Host only. The banked card is put down **on the team's vault** rather than
## sent back to its home point (D-068), which is the whole of the change: a
## banked letter is now a thing standing somewhere, so everyone can see what a
## team holds without reading the HUD, and somebody else can come and take it.
func _store_in_vault(letter: int, team: int, peer_id: int) -> void:
	var entry: Dictionary = _capture.get(letter, {})
	if entry.is_empty():
		return
	if _capture_layout == null or team < 0 or team >= _capture_layout.vaults.size():
		# No vault to stand it on — a lobby whose layout never planned one. The
		# old behaviour is the safe fallback rather than dropping the card.
		_send_capture_home(letter, false)
		return
	var lying := int(entry["pickup"])
	if lying != 0:
		_withdraw_pickup.rpc(lying)
		_withdraw_pickup(lying)
	entry["carrier"] = 0
	entry["return_at"] = 0.0
	entry["banked_team"] = team
	entry["banked_peer"] = peer_id
	entry["pickup"] = _spawn_drop(Pickup.Kind.LETTER, letter,
		_capture_layout.vaults[team])


## Which team has this letter standing in its vault, or `TEAM_NONE`.
func banked_team_of(letter: int) -> int:
	var entry: Dictionary = _capture.get(letter, {})
	if entry.is_empty():
		return MatchConfig.TEAM_NONE
	return int(entry.get("banked_team", MatchConfig.TEAM_NONE))


## Host only. Take `letter` back off `team`'s mask, because somebody has just
## picked it up out of their vault (D-068).
##
## This is `award_letter` run backwards and it reuses the same push, so there is
## no second replication path to keep in step: the whole mask goes out on
## `_sync_letters` either way. The personal mask that loses the bit is the one
## belonging to whoever banked it — that is what `banked_peer` is recorded for.
func _revoke_letter(letter: int, team: int) -> void:
	if not Net.is_host:
		return
	var entry: Dictionary = _capture.get(letter, {})
	var peer_id := int(entry.get("banked_peer", 0))
	var stat: Dictionary = stats.get(peer_id, {})
	var next := int(stat.get("letters", 0)) & ~letter
	var team_mask := team_letters(team) & ~letter
	_sync_letters.rpc(peer_id, next, team, team_mask, 0)
	_sync_letters(peer_id, next, team, team_mask, 0)
	_push_scores()


## A dropped card or a returned one, told on every peer. `peer_id` 0 is a
## return; anything else is that carrier's card hitting the ground.
@rpc("authority", "call_remote", "reliable")
func _announce_capture(peer_id: int, letter: int) -> void:
	if peer_id == 0:
		letter_returned.emit(letter)
	else:
		letter_dropped.emit(peer_id, letter)


# ---------------------------------------------------------------- the elder ---

## Picking the robe up makes that Gub the Elder **for `elder_duration` seconds**
## (D-040), during which it cannot be killed by anything but the void.
##
## **This supersedes D-038's "until it dies"**, and the two halves are one
## change rather than two: invincibility takes death away as the exit, so
## something else has to be it, and the something else is a clock. What that
## buys is a weapon whose cost is known in advance by everybody in the fight —
## the counter-play to an Elder is no longer killing it, it is surviving it, and
## twenty seconds is a length of time you can decide to spend behind a rock.
##
## It lives here rather than on the Gub for the reasons the letter hold does: it
## is match state, it has to survive being watched by seven peers who picked up
## nothing, and the host has to be the only machine that can grant or end one.
## A flag on `GubCombat` would be a weapon the client that benefits from it gets
## to declare it has — and a *clock* on `GubCombat` would be a countdown running
## on the machine that wants it to run slowly.
##
## Three things end one and they all run the same teardown: the clock
## (`_tick_elders`), a void death (`report_kill`), and a disconnect
## (`_on_player_left`). Nothing else does — not a respawn, not a mushroom, not
## finishing a letter hold.
##
## **Expiry is not a death.** Letters live on the `stats` row and are untouched;
## the mushrooms and lures in `GubCombat` are untouched too, because nothing
## calls `reset()`. A Gub that has just spent twenty seconds as the Elder walks
## away with everything it walked in with, plus its spear back.


## Host only, from `claim_pickup`, which has already established that this
## player is alive and in a running match.
func _make_elder(peer_id: int) -> void:
	if not stats.has(peer_id) or _elders.has(peer_id):
		return
	_do_set_elder.rpc(peer_id, true, config().elder_duration)
	_do_set_elder(peer_id, true, config().elder_duration)


## Host only. The robe is consumed — there is nothing to give back and nothing
## to put on the ground.
func _end_elder(peer_id: int) -> void:
	if not _elders.has(peer_id):
		return
	_do_set_elder.rpc(peer_id, false, 0.0)
	_do_set_elder(peer_id, false, 0.0)


## Host only. Burn out the robes whose time is up.
##
## The same shape as `_tick_letter_holds` and deliberately so: `.keys()` copies,
## because ending a robe erases its own row. There is no award at the end of
## this one — the robe simply stops, which is the whole of what expiry is.
func _tick_elders() -> void:
	for peer_id: int in _elders.keys():
		if _now() >= float(_elders[peer_id]["ends_at"]):
			_end_elder(peer_id)


## The host's word on who is wearing the robe, applied on every peer.
##
## This is both halves at once: the row that the rules read and the cloth that
## the players see. Keeping them in one call is what stops a Gub being the Elder
## in the bookkeeping and a plain Gub on somebody's screen — which would be the
## worst available bug here, because the robe is the only warning anybody gets.
##
## `seconds` is ignored when taking one off, and is deliberately still a
## parameter rather than two RPCs: one message, one decision, one place where
## the robe and the clock behind it are written together.
@rpc("authority", "call_remote", "reliable")
func _do_set_elder(peer_id: int, wearing: bool, seconds: float) -> void:
	if wearing:
		_elders[peer_id] = {"ends_at": _now() + seconds}
	elif not _elders.erase(peer_id):
		return
	var gub: Gub = gubs.get(peer_id)
	if is_instance_valid(gub):
		gub.set_elder(wearing)
	elder_changed.emit(peer_id)


## The robe turning a blow aside, on every peer.
##
## Sent from `report_kill` and only from there, because that is the one place
## that knows a death was refused *and* why. Putting it on the spear instead
## would have covered the spear and left the other Elder's bolt silent, and
## putting it on both would have been two copies of one rule waiting to
## disagree about which hits count.
##
## The point rather than the Gub's position: a spear turned aside at the shin
## and one turned aside at the head should not flash in the same place, and the
## whole job of this is to say *where* the thing that did not kill you hit.
@rpc("authority", "call_remote", "reliable")
func _do_ward(peer_id: int, point: Vector3) -> void:
	var gub: Gub = gubs.get(peer_id)
	WardFlash.burst(_spawn_root(), point)
	# A kick for the Elder only, and a small one. Being shot at and surviving it
	# is information the player wants — an Elder with its back to a fight has no
	# other way to learn there is one — and it is deliberately far below the 1.4
	# a death is worth: this is a nudge, not an event.
	_shake(gub, WardFlash.SHAKE)


## Drop every robe locally. Used when the whole match is torn down — a Gub
## wearing one into the next match would be an Elder nobody earned.
func _clear_elders() -> void:
	if _elders.is_empty():
		return
	var were := _elders.keys()
	_elders.clear()
	for peer_id: int in were:
		var gub: Gub = gubs.get(peer_id)
		if is_instance_valid(gub):
			gub.set_elder(false)
		elder_changed.emit(peer_id)


## Is this Gub the Elder right now? Safe to ask about a peer with no row, which
## is what `GubCombat` does three times a frame for every Gub in the match.
##
## The presence of the row, deliberately, and never `elder_remaining() > 0`: a
## client's countdown can reach zero a round trip before the host's does, and a
## Gub that took its own robe off on that frame would be a Gub the host still
## refuses to let throw a spear.
func is_elder(peer_id: int) -> bool:
	return _elders.has(peer_id)


## Seconds left on this Gub's robe, or 0.0 if it is not wearing one. Never
## negative, so the HUD can divide by `MatchConfig.elder_duration` and get a
## fraction to fill a bar with — the same contract `letter_hold_remaining` has,
## because it is read by the same kind of control for the same reason.
func elder_remaining(peer_id: int) -> float:
	if not _elders.has(peer_id):
		return 0.0
	return maxf(0.0, float(_elders[peer_id]["ends_at"]) - _now())


# ------------------------------------------------------------------ scores ---

func _push_scores() -> void:
	_sync_scores.rpc(stats)
	scores_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_scores(incoming: Dictionary) -> void:
	stats = incoming
	scores_changed.emit()


func kills(peer_id: int) -> int:
	return stats.get(peer_id, {}).get("kills", 0)


func deaths(peer_id: int) -> int:
	return stats.get(peer_id, {}).get("deaths", 0)


func lives_left(peer_id: int) -> int:
	return stats.get(peer_id, {}).get("lives_left", 0)


func is_alive(peer_id: int) -> bool:
	return stats.get(peer_id, {}).get("alive", false)


func team_score(team: int) -> int:
	var total := 0
	for peer_id: int in stats:
		if Net.player_team(peer_id) == team:
			total += kills(peer_id)
	return total


## Peers sorted best-first, for the scoreboard and the results screen.
##
## "Best" is whatever the match is actually about. Under LETTERS that is the
## letter count, because the winner is the player holding three of them and a
## board that ranks the match by kills would put somebody else at the top of the
## results screen the moment the match they won ends. Kills stay the tiebreak
## under letters, and deaths stay the tiebreak under everything.
func ranking() -> Array:
	var ids := stats.keys()
	var by_letters := MatchConfig.scores_letters(config().win_condition)
	ids.sort_custom(func(a, b):
		if by_letters and letter_count(a) != letter_count(b):
			return letter_count(a) > letter_count(b)
		if kills(a) != kills(b):
			return kills(a) > kills(b)
		return deaths(a) < deaths(b))
	return ids


# ---------------------------------------------------------------- win check ---

func _check_win() -> void:
	match config().win_condition:
		MatchConfig.WinCondition.KILL_LIMIT:
			for peer_id: int in stats:
				if _score_for(peer_id) >= config().kill_limit:
					_finish("limit")
					return
		MatchConfig.WinCondition.LIVES:
			var standing := _still_standing()
			if standing.size() <= 1 and stats.size() > 1:
				_finish("elimination")
		MatchConfig.WinCondition.TIME_ONLY:
			pass
		MatchConfig.WinCondition.LETTERS:
			# This comment used to say a team whose three members hold G, U and
			# B between them had won nothing, because the card game ends on one
			# hand with the whole word in it. Playtesting said otherwise — the
			# user's note was that spelling should be scored per team — and
			# D-049 reverses it: in Teams the letters pool, so the test is the
			# team's mask. The worry the old rule answered, a big team beating a
			# small one on arithmetic, is now the lobby's to answer — random teams
			# are dealt even (D-048) — rather than the letters' to refuse to add up.
			#
			# A team's mask survives its members leaving (see `_team_letters`),
			# which is why this scans teams rather than the rows in `stats`.
			if config().mode == MatchConfig.Mode.TEAMS:
				for team: int in _team_letters:
					if team_letters(team) & LETTER_ALL == LETTER_ALL:
						_finish("letters")
						return
				return
			for peer_id: int in stats:
				if has_all_letters(peer_id):
					_finish("letters")
					return
		MatchConfig.WinCondition.CAPTURE:
			# The same test as a Teams letters match, because it is the same
			# pooled mask (D-049) filled a different way (D-051). The config
			# forces Teams for this condition, so there is no per-player branch
			# to fall back to.
			for team: int in _team_letters:
				if team_letters(team) & LETTER_ALL == LETTER_ALL:
					_finish("capture")
					return


## In teams, a kill counts toward the team's total, so the limit is a team limit.
func _score_for(peer_id: int) -> int:
	if config().mode == MatchConfig.Mode.TEAMS:
		return team_score(Net.player_team(peer_id))
	return kills(peer_id)


func _still_standing() -> Array:
	var out := []
	for peer_id: int in stats:
		if stats[peer_id]["lives_left"] > 0 or stats[peer_id]["alive"]:
			out.append(peer_id)
	return out


func _finish(reason: String) -> void:
	if _finished:
		return
	_finished = true
	var summary := {
		"reason": reason,
		"ranking": ranking(),
		"stats": stats,
		"mode": config().mode,
		# Carried for the same reason `mode` is, and it is a read for the
		# results screen and nothing else: that screen is driven entirely from
		# this snapshot rather than from live state (its header says why), and
		# without the condition in here it cannot tell a letters match from any
		# other one and would have to guess from the rows.
		"win_condition": config().win_condition,
	}
	if config().mode == MatchConfig.Mode.TEAMS:
		var scores := {}
		for team in config().team_count:
			scores[team] = team_score(team)
		summary["team_scores"] = scores
		# The pooled masks, so the results screen can crown the team that
		# spelled it rather than the team with the most kills, and can draw the
		# team's letters when the member who banked one has already left (D-049).
		if MatchConfig.scores_letters(config().win_condition):
			var pooled := {}
			for team in config().team_count:
				pooled[team] = team_letters(team)
			summary["team_letters"] = pooled

	_sync_phase.rpc(Phase.POST_MATCH, 0.0, time_left)
	_sync_phase(Phase.POST_MATCH, 0.0, time_left)
	_sync_finish.rpc(summary)
	_sync_finish(summary)


@rpc("authority", "call_remote", "reliable")
func _sync_finish(summary: Dictionary) -> void:
	_set_phase(Phase.POST_MATCH)
	# A hold still running when the whistle goes grants nothing (D-035). The
	# match is over; nobody is owed the last two seconds of it. Cleared on every
	# peer rather than left to expire, so the results screen is not shown over a
	# Gub still counting down to a letter it can never have.
	_clear_letter_holds()
	_stop_publishing()
	match_finished.emit(summary)


## Every Gub on this machine stops sending its position, on every peer, the
## moment the match is over.
##
## What ends a match is one reliable message; what follows it is every peer
## freeing its Gubs, and not at the same moment — the host on its own REMATCH,
## a client when that broadcast reaches it, a client that walks itself to the
## lobby whenever it likes. A `MultiplayerSynchronizer` still publishing at a
## peer that has already freed its copy costs that peer two engine errors per
## packet: *Node not found* and *Failed to get cached node* (D-044). A client
## sitting in the lobby while the host read the results logged them sixty times
## a second, and every rematch logged a burst on the host.
##
## So the senders stop first, here, while every copy still exists. Nothing is
## lost: the results screen covers the arena, and a rematch builds new Gubs whose
## synchronizers start public again.
func _stop_publishing() -> void:
	for gub: Gub in gubs.values():
		if not is_instance_valid(gub):
			continue
		var sync := gub.get_node_or_null("Sync") as MultiplayerSynchronizer
		if sync != null:
			sync.public_visibility = false


## Every Gub still standing, best-scoring first, optionally excluding one peer.
##
## This is the spectator's channel list (PLAN 6.5). Ordering it by score rather
## than by peer id means the first thing a dead player is shown is whoever is
## currently winning, which is the most interesting camera in the match and the
## one they would have picked.
func living_gubs(exclude_id: int = 0) -> Array[Gub]:
	var out: Array[Gub] = []
	for peer_id: int in ranking():
		if peer_id == exclude_id:
			continue
		var gub: Gub = gubs.get(peer_id)
		if is_instance_valid(gub) and gub.alive:
			out.append(gub)
	return out


## Whether `peer_id` is on the same team as the player on *this* machine, which
## is what lets a teammate's nameplate through the scenery (D-047). Never true in
## free-for-all, and never true of yourself.
##
## Read off the roster rather than off the local Gub, so a teammate who spawns
## before this player's own body exists is still recognised as one. Teams are
## fixed for the length of a match — a pick only moves in the lobby — so the
## answer given at spawn holds until the next spawn asks again.
func is_teammate(peer_id: int) -> bool:
	var me := Net.local_id()
	if config().mode != MatchConfig.Mode.TEAMS or peer_id == me:
		return false
	var mine := Net.player_team(me)
	return mine >= 0 and Net.player_team(peer_id) == mine


## The Gub this client is driving, or null while dead or spectating.
func local_gub() -> Gub:
	var gub: Gub = gubs.get(Net.local_id())
	return gub if is_instance_valid(gub) else null
