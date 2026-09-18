class_name RangeDummies
extends Node
## The practice range's targets: real Bogs, on real roster rows, that the host
## holds the strings of (D-112).
##
## Damage in this game lands on exactly one kind of thing — `MatchState.bogs`,
## keyed by peer id, and every weapon either casts for `Bog` or picks out of
## `living_bogs()`. So a target that a spear, an arrow, a sword swing, a magnet
## and a lightning bolt all treat correctly is not a new class of object; it is
## a `Bog`. Anything else would mean five weapons learning about a sixth kind of
## collider, and the range would then be testing that code path rather than the
## one the game ships.
##
## What makes it a dummy rather than a player is three things and no more:
##
##   the row     `Net.players[900+n]` carries `"dummy": true`, and every screen
##               built out of the roster walks `Net.human_ids()` instead. See
##               the block above `BOT_BASE` in `net.gd` for why it is a roster
##               row at all.
##   the anchor  `MatchState.set_respawn_anchor` puts it back at its station
##               rather than on a spawn pad, so a target that is killed comes
##               back where it was standing.
##   the strings `Sync`'s multiplayer authority is the host's, so this node can
##               move it and every client sees it move. `MatchState._create_bog`
##               does that; the long comment there is the argument for why it is
##               that one node and not the whole Bog.
##
## ## Driving one
##
## A brain is a `RangeBrain` — a small object with `drive(bog, delta)`, built
## from a name by `RangeBrain.make` — and it reaches the world through exactly
## one function, `drive_to`. Brains do not touch `sync_*` fields and do not call
## `move_and_slide`: the first is how two brains end up disagreeing about which
## of the eleven replicated fields matter, and the second is a physics step on a
## body whose transform is already being written, which fights itself.
##
## Unit 1 ships the base class and the still-standing default; unit 3 fills in
## the behaviours behind `RangeBrain.make`, and nothing here changes when it
## does.
##
## `drive_to` writes the body and the snapshot **together**, and that pairing is
## the whole contract. The host's collision capsule has to be where the dummy is
## drawn on everybody else's screen, or a shot that looks like a hit is a miss;
## and the snapshot has to say `grounded` and `crouching` honestly or the
## animator plays the wrong clip forever — which is exactly the bug
## `tools/combat_range.gd:_stand_still` was written to work around, and the
## reason that function exists is that nothing until now published for a dummy
## at all.
##
## ## Host only
##
## `spawn`, `set_brain` and the per-tick drive are all host-side. Clients learn
## of a dummy the way they learn of a player: a roster broadcast, then
## `_create_bog`. They never run a brain, and nothing here is replicated on its
## own account — the Bog's own synchronizer carries all of it.

## The body every dummy wears: pale, cold, and not one of the fourteen a player
## is likely to have picked, so "that is a target" and "that is a person" are
## one glance apart across a dark bog.
const SKIN := "rime"

## The one instance, for unit 3's stations and unit 4's wells to find without
## threading a reference through the map. Null outside a practice arena, which
## is the honest answer — there are no dummies anywhere else.
static var instance: RangeDummies = null

## dummy peer id ->
## `{"station": Transform3D, "brain": String, "meta": Dictionary, "runner": RangeBrain}`.
##
## `meta` is whatever the map's marker declared about this dummy — which lane it
## is in, how far it strafes, which way it faces — and it is carried here rather
## than read off the marker later because the marker belongs to unit 2's scene
## and a brain must not have to go looking through it.
var _rows: Dictionary = {}
## Brains that could not run yet because the match had not started. See `spawn`.
var _pending: Array[Dictionary] = []


func _ready() -> void:
	instance = self
	add_to_group("range_dummies")
	# After the Bogs, so that what this writes in a frame is what stands at the
	# end of it. `Bog._physics_process` runs `_follow_network` for a dummy on
	# every peer including the host, easing `global_position` toward
	# `sync_position`; since `drive_to` sets both to the same value the order is
	# academic, but "the driver has the last word" is the rule that stays true
	# if a brain ever writes only one of them.
	process_physics_priority = 10
	# A dummy can only be put in the world once there is a match to put it in:
	# `MatchState.spawn_for` needs a standing arena, and `claim_pickup` — which
	# is what makes an item well work at all — refuses outside `PLAYING`. The
	# range reaches `PLAYING` immediately (no warmup on a practice map), so this
	# is a wait of a frame or two rather than a real delay.
	MatchState.phase_changed.connect(_on_phase_changed)


func _exit_tree() -> void:
	if instance == self:
		instance = null
	# The rows outlive this node otherwise: `Net.players` belongs to the
	# session and the arena is only a scene inside it. `leave_lobby` clears the
	# whole roster, so this matters for the case where a range arena is torn
	# down without the session ending.
	for id: int in _rows.keys():
		MatchState.clear_respawn_anchor(id)
		Net.remove_bot(id)
	_rows.clear()


## Host only. Stand a new dummy at `station`, running `brain`, and return its
## peer id — or 0 off the host.
##
## The roster row goes out **before** the body, and that order is the one thing
## about this function that is not obvious. `MatchState._create_bog` reads the
## name, the team, the weapon and the skin off `Net.players` on whichever peer
## it lands on; a client that got the spawn first would build a dummy called
## "Bog" wearing the default body, and nothing would ever correct it because
## `_create_bog` is sent once. Both calls are reliable on the default channel,
## so ENet delivers them in the order they were sent — the same guarantee D-069
## leans on for the weapon and D-048 for teams.
func spawn(station: Transform3D, brain: String, meta: Dictionary = {}) -> int:
	if not Net.is_host:
		return 0
	# `Net.BOT_BASE` read through the autoload rather than copied into a `const`
	# here: a second spelling of 900 is a second thing to get wrong, and a
	# `const` cannot reach an autoload's constant at parse time anyway.
	var id := Net.BOT_BASE + _rows.size()
	# `_rows.size()` can repeat an id if one was retired, so walk past anything
	# taken. Bounded by the roster, which cannot be large.
	while Net.has_player(id):
		id += 1
	_rows[id] = {"station": station, "brain": brain, "meta": meta.duplicate(),
		"runner": null}
	_rows[id]["runner"] = _make_brain(id, brain)

	Net.add_bot(id, {
		"name": "Dummy %d" % (_rows.size()),
		# Never on a team. A dummy in somebody's colours is a target that reads
		# as a teammate, and with friendly fire off it would be a target that
		# cannot be shot at all.
		"team": MatchConfig.TEAM_NONE,
		# Nothing waits on a dummy to be ready; this is here so that a row which
		# somehow reached `can_start_match` could not block Start.
		"ready": true,
		"dummy": true,
		"weapon": Loadout.DEFAULT,
		"skin": Skins.NAMES.find(SKIN),
	})

	if MatchState.phase == MatchState.Phase.PLAYING:
		MatchState.spawn_for(id, station)
	else:
		_pending.append({"id": id, "station": station})
	return id


## Host only. Swap which brain drives `id`. What a station does when you walk
## into it (unit 3).
##
## The brain is **rebuilt**, not just renamed: a behaviour owns its own phase —
## where a patroller is along its leg, how far a strafer has drifted — and
## keeping the old object while changing the label would leave a circler running
## a jumper's state. `RangeBrain.make` is the one place a name becomes an
## object, here and in `spawn`.
func set_brain(id: int, name: String) -> void:
	if not _rows.has(id):
		return
	_rows[id]["brain"] = name
	_rows[id]["runner"] = _make_brain(id, name)


## What the map declared about this dummy. Empty for one spawned without any.
func meta_of(id: int) -> Dictionary:
	return _rows.get(id, {}).get("meta", {})


## The live brain driving `id`, or null. Unit 3's stations reach for this to
## call `reset()` on a zone.
func runner_of(id: int) -> RangeBrain:
	return _rows.get(id, {}).get("runner")


## Everything a behaviour needs to do its job without reaching for a singleton
## or knowing which map it is standing on.
func _make_brain(id: int, name: String) -> RangeBrain:
	return RangeBrain.make(name, {
		"dummies": self,
		"id": id,
		"station": station_of(id),
		"meta": meta_of(id),
	})


## Where `id` stands and comes back to. Identity if it is not one of ours, which
## is the same answer `_next_spawn` would give for a peer with no anchor.
func station_of(id: int) -> Transform3D:
	return _rows.get(id, {}).get("station", Transform3D.IDENTITY)


func brain_of(id: int) -> String:
	return String(_rows.get(id, {}).get("brain", ""))


func bog_of(id: int) -> Bog:
	return MatchState.bogs.get(id) as Bog


func ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in _rows:
		out.append(id)
	out.sort()
	return out


## **The one writer of a dummy's replicated state.** Brains call this and
## nothing else; see the header.
##
## Body and snapshot in one call, because they are one fact: where this dummy
## is. Writing `global_position` alone would move the host's collision capsule
## and leave every client's copy standing where it was; writing `sync_position`
## alone would move the picture and leave the thing spears actually hit behind,
## dragged along a frame later by `_follow_network`'s lerp. Both together is the
## only version that is true on every screen at once.
##
## `grounded` and `crouching` are not decoration. A remote Bog's animator reads
## the replicated flags rather than `is_on_floor()`, which is permanently false
## for a body nothing calls `move_and_slide` on — so a dummy whose `sync_grounded`
## is left at its default plays the jump clip for ever, splayed out in the air.
## That is the exact bug `tools/combat_range.gd:_stand_still` exists to paper
## over, and this is the general form of the fix.
## `jumped` is the one thing here that is an **event** rather than a state, and
## it is why it cannot be inferred from `grounded` going false. `sync_grounded`
## and `sync_jump_serial` are both ON_CHANGE fields, so two take-offs inside one
## dropped-and-recovered packet arrive as a single "not grounded any more" — the
## animator's take-off one-shot fires once and the second jump is a Bog that
## rises without ever leaving the ground pose. A serial that only counts up
## cannot collapse that way, which is exactly why `Bog.request_jump` keeps one
## and why the dive beside it does too (D-029's argument, one field over).
func drive_to(bog: Bog, pos: Vector3, yaw: float, vel: Vector3, grounded: bool,
		crouching: bool = false, jumped: bool = false) -> void:
	if not is_instance_valid(bog):
		return
	bog.global_position = pos
	bog.body_yaw = yaw
	bog.velocity = vel
	bog.sync_position = pos
	bog.sync_yaw = yaw
	bog.sync_velocity = vel
	bog.sync_grounded = grounded
	bog.sync_crouching = crouching
	bog.sync_sliding = false
	if jumped:
		bog.sync_jump_serial += 1


## Stand `bog` exactly where it is, upright and still, and say so on the wire.
## What a dummy with no brain does, and what unit 3's `stand` brain is.
func hold_still(bog: Bog) -> void:
	if is_instance_valid(bog):
		drive_to(bog, bog.global_position, bog.body_yaw, Vector3.ZERO, true)


func _on_phase_changed(phase: int) -> void:
	if phase != MatchState.Phase.PLAYING or not Net.is_host:
		return
	for entry: Dictionary in _pending:
		MatchState.spawn_for(int(entry["id"]), entry["station"])
	_pending.clear()


func _physics_process(delta: float) -> void:
	# Host only, and that is the whole of the networking here: the host decides
	# where a dummy is, writes it through `drive_to`, and the Bog's own
	# synchronizer carries it. A client running a brain would be a second
	# opinion about a body it does not own.
	if not Net.is_host or MatchState.phase != MatchState.Phase.PLAYING:
		return
	for id: int in _rows:
		var bog := bog_of(id)
		if not is_instance_valid(bog) or not bog.alive:
			continue
		var brain: RangeBrain = _rows[id]["runner"]
		if brain == null:
			hold_still(bog)
			continue
		brain.drive(bog, delta)
