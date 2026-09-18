class_name RangeStats
extends Node
## What you have actually been hitting: throws, hits, accuracy, kills, longest
## hit and current streak, per player per weapon, for this session.
##
## Host-authoritative and broadcast whole. Every peer holds the same table and
## reads its own row out of it, which is what lets the HUD panel and the lodge
## board be two views of one number rather than two counters that drift.
##
## ### Where the numbers come from
##
## Three sources, and none of them is a new packet:
##
## - **Launches** — `BogCombat.weapon_launched`, emitted from the four `_do_*`
##   handlers. Those are the *committed* actions, run on every peer by the
##   authority that decided them, so the host sees every throw, loose, swing and
##   cast anybody makes and nobody else counts. Rejected: watching nodes appear
##   under `spawned_items`, which cannot see a sword swing at all and cannot
##   attribute an arrow to a peer without reaching inside it.
## - **Hits and kills** — `MatchState.hit_landed` and `player_killed`, which
##   already fire on every peer.
## - **Target hits** — the boards, the gong and the orbs, straight into
##   `record_target_hit`. They count into the same weapon row as a hit on a Bog:
##   a throw is a throw.
##
## ### The one lag, stated rather than hidden
##
## A streak is landed shots in a row. Nothing in the world can observe a shaft
## that simply never hit anything — it flies, it sticks in a hill, and no signal
## fires — so a miss is noticed when the **next** shot is fired. The alternative
## was a lifetime hook on every arrow for a number on a practice board.

signal rows_changed()

static var instance: RangeStats

const WEAPONS: Array[String] = ["spear", "bow", "sword", "lightning"]

## Weapon key by `Bog.Cause`. The bow's cause is `ARROW` and its row is "bow",
## because a player practises a *weapon* and the arrow is what it fires.
const BY_CAUSE := {
	Bog.Cause.SPEAR: "spear",
	Bog.Cause.ARROW: "bow",
	Bog.Cause.SWORD: "sword",
	Bog.Cause.LIGHTNING: "lightning",
}

## At most this often, and only when something moved. The whole table rather
## than deltas — the argument `MatchState._sync_scores` makes, for the same
## reason: a peer that drops a delta is permanently wrong, and a peer that drops
## a snapshot is corrected by the next one.
const BROADCAST_HZ := 4.0

## How often the registry re-walks `MatchState.bogs` looking for a `BogCombat`
## it has not connected yet. A poll rather than a hook, so that nothing in unit
## 1's files has to know this exists — and respawns mint a new Bog node every
## life, so there is always something new to find.
const SWEEP := 1.0

var rows: Dictionary = {}

var _dirty: bool = false
var _since_send: float = 0.0
var _since_sweep: float = 0.0
## Peer ids whose last launch has not yet been answered by a hit. One int per
## peer per weapon; see the header on the lag this buys.
var _pending: Dictionary = {}


# ------------------------------------------------------------- the fitting ---

## Stand the range's targets, its counter and its lodge boards up on a built
## map. **The one line unit 6 adds to `range_map._ready`, after `super()` and
## beside the `Dummies` line.**
##
## Here rather than in `range_target.gd` because the order matters and one
## function should own it: the counter has to exist before a target can score
## into it, and the boards have to exist before the counter's first broadcast.
## The shape `RangeDirector` already loads unit 4's items through — a static
## `build(map)` on a known script path, called behind a `ResourceLoader.exists`
## guard so the director runs whether or not this unit is on disk. Provided
## under that exact name so wiring this in is the same three lines as
## `_build_items`, rather than a second convention for the same job.
static func build(map: Node) -> void:
	install(map as Node3D)


## As above, but hands back the counter it made. Used by anything that wants to
## keep hold of it; `build` is the one the director calls.
static func install(map: Node3D) -> RangeStats:
	if map == null:
		return null
	var stats := RangeStats.new()
	stats.name = "Stats"
	map.add_child(stats)

	var targets := Node3D.new()
	targets.name = "TargetBodies"
	map.add_child(targets)
	var built := RangeTarget.build_all(map, targets)

	var boards := map.get_node_or_null("Boards")
	if boards != null:
		for marker: Node in boards.get_children():
			var spot := marker as Marker3D
			if spot != null:
				stats.build_board(spot)

	print("%s: %d targets standing, stats on %d board(s)"
		% [map.name, built, 0 if boards == null else boards.get_child_count()])
	return stats


func _ready() -> void:
	instance = self
	add_to_group("range_stats")
	MatchState.hit_landed.connect(_on_hit_landed)
	MatchState.player_killed.connect(_on_player_killed)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	_since_sweep += delta
	if _since_sweep >= SWEEP:
		_since_sweep = 0.0
		_sweep_for_combats()

	if not Net.is_host or not _dirty:
		return
	_since_send += delta
	if _since_send < 1.0 / BROADCAST_HZ:
		return
	_since_send = 0.0
	_dirty = false
	_sync_rows.rpc(rows)


# ------------------------------------------------------------- the counting ---

## Find every `BogCombat` that has not been wired up yet.
##
## `is_connected` rather than a set of ids, because the thing that must not be
## connected twice is the *signal*, and that is the object that can answer.
func _sweep_for_combats() -> void:
	for bog: Variant in MatchState.bogs.values():
		var body := bog as Bog
		if not is_instance_valid(body):
			continue
		# `get_node_or_null` and an explicit cast rather than `Bog.combat()`:
		# this file is reached from `BogCombat`'s own signal, so inferring a
		# type off that accessor is a cycle the parser refuses.
		var combat := body.get_node_or_null("Combat") as BogCombat
		if combat == null:
			continue
		if combat.weapon_launched.is_connected(_on_weapon_launched):
			continue
		combat.weapon_launched.connect(_on_weapon_launched.bind(body.peer_id))


func _on_weapon_launched(weapon: String, peer_id: int) -> void:
	record_launch(peer_id, weapon)


func _on_hit_landed(attacker_id: int, _victim_id: int, _amount: float,
		cause: int, point: Vector3, _bone: String) -> void:
	record_hit(attacker_id, weapon_for(cause), shot_distance(attacker_id, point))


func _on_player_killed(victim_id: int, killer_id: int, cause: int) -> void:
	if killer_id == victim_id:
		return
	record_kill(killer_id, weapon_for(cause))


## Host only. A weapon was used.
func record_launch(peer_id: int, weapon: String) -> void:
	if not Net.is_host or not WEAPONS.has(weapon):
		return
	var row := _row(peer_id, weapon)
	# A launch arriving while the previous one is still unanswered is a miss,
	# and it is the only way a miss can be seen at all.
	var key := "%d/%s" % [peer_id, weapon]
	if int(_pending.get(key, 0)) > 0:
		row["streak"] = 0
	_pending[key] = int(_pending.get(key, 0)) + 1
	row["launches"] = int(row["launches"]) + 1
	_touch()


## Host only. A weapon landed on a Bog.
func record_hit(peer_id: int, weapon: String, distance: float) -> void:
	if not Net.is_host or not WEAPONS.has(weapon):
		return
	_credit(peer_id, weapon, distance)


## Host only. A weapon landed on a board, the gong or an orb. The same row as a
## hit on a Bog, plus the points the target is worth.
func record_target_hit(peer_id: int, cause: int, points: int,
		distance: float) -> void:
	if not Net.is_host:
		return
	var weapon := weapon_for(cause)
	if not WEAPONS.has(weapon):
		return
	var row := _credit(peer_id, weapon, distance)
	row["points"] = int(row["points"]) + points


func _credit(peer_id: int, weapon: String, distance: float) -> Dictionary:
	var row := _row(peer_id, weapon)
	row["hits"] = int(row["hits"]) + 1
	row["streak"] = int(row["streak"]) + 1
	row["best_streak"] = maxi(int(row["best_streak"]), int(row["streak"]))
	if distance >= 0.0:
		row["longest"] = maxf(float(row["longest"]), distance)
	var key := "%d/%s" % [peer_id, weapon]
	_pending[key] = maxi(0, int(_pending.get(key, 0)) - 1)
	_touch()
	return row


## Host only. A weapon finished somebody.
func record_kill(peer_id: int, weapon: String) -> void:
	if not Net.is_host or not WEAPONS.has(weapon):
		return
	var row := _row(peer_id, weapon)
	row["kills"] = int(row["kills"]) + 1
	_touch()


## Wipe every row. Unit 3's reset station calls this; the host broadcasts at
## once rather than waiting for the throttle, because a reset you can see not
## happening is worse than no reset button.
func reset() -> void:
	if not Net.is_host:
		return
	rows.clear()
	_pending.clear()
	_dirty = false
	_since_send = 0.0
	_sync_rows.rpc(rows)
	rows_changed.emit()


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_rows(incoming: Dictionary) -> void:
	rows = incoming
	rows_changed.emit()


func _touch() -> void:
	_dirty = true
	rows_changed.emit()


func _row(peer_id: int, weapon: String) -> Dictionary:
	if not rows.has(peer_id):
		rows[peer_id] = {}
	var mine: Dictionary = rows[peer_id]
	if not mine.has(weapon):
		mine[weapon] = {"launches": 0, "hits": 0, "kills": 0, "points": 0,
			"longest": 0.0, "streak": 0, "best_streak": 0}
	return mine[weapon]


# --------------------------------------------------------------- reading it ---

## One player's row for one weapon, or an empty one. Never `null`, so a caller
## can format without asking first.
func row(peer_id: int, weapon: String) -> Dictionary:
	var mine: Dictionary = rows.get(peer_id, {})
	return mine.get(weapon, {"launches": 0, "hits": 0, "kills": 0, "points": 0,
		"longest": 0.0, "streak": 0, "best_streak": 0})


## Every weapon this player has actually used, in the canonical order. An empty
## row is not shown: a panel listing four weapons when you have fired one is
## three lines of nothing.
func weapons_used(peer_id: int) -> Array[String]:
	var out: Array[String] = []
	for weapon: String in WEAPONS:
		if int(row(peer_id, weapon)["launches"]) > 0:
			out.append(weapon)
	return out


static func accuracy(of_row: Dictionary) -> float:
	var launches := int(of_row.get("launches", 0))
	if launches <= 0:
		return 0.0
	return float(of_row.get("hits", 0)) / float(launches)


static func weapon_for(cause: int) -> String:
	return String(BY_CAUSE.get(cause, ""))


## How far the shot was, measured from the shooter's Bog at the moment it landed.
##
## **The shooter may be dead.** A corpse keeps its node until it respawns
## (D-043), so this usually still resolves; when it does not, it returns -1.0 and
## every caller omits the distance rather than printing a zero. A readout that is
## occasionally absent is a readout; one that is occasionally wrong is a lie you
## cannot spot.
static func shot_distance(peer_id: int, point: Vector3) -> float:
	var shooter: Bog = MatchState.bogs.get(peer_id)
	if not is_instance_valid(shooter):
		return -1.0
	return shooter.global_position.distance_to(point)


# -------------------------------------------------------------- the plank ---

## Hang a readout on one of the lodge's `Boards` markers.
##
## Two kinds, off the marker's own `kind` meta: `stats` gets the table, and
## `best_time` gets unit 3's parkour line. Both are `Label3D`s on a plank rather
## than a viewport texture, because the text has to be legible at 6 m in a dark
## bog and a 3D label is the only thing on this map that already is.
func build_board(marker: Marker3D) -> Node3D:
	var kind := String(marker.get_meta("kind", "stats"))
	var plank := Node3D.new()
	plank.name = "Board_%s_face" % kind
	marker.add_child(plank)

	var title := _plank_label(plank, kind.to_upper().replace("_", " "),
		UIPalette.AMBER, 0.0, 1.15)
	title.name = "Title"
	for i: int in 6:
		var line := _plank_label(plank, "", UIPalette.TEXT, -0.22 * (i + 1), 1.0)
		line.name = "Line%d" % i

	if kind == "stats":
		rows_changed.connect(_refresh_board.bind(plank))
		_refresh_board(plank)
	else:
		_set_line(plank, 0, "no run yet", UIPalette.TEXT_DIM)
	return plank


func _plank_label(parent: Node3D, body: String, tint: Color, drop: float,
		scale_of: float) -> Label3D:
	var label := Label3D.new()
	label.text = body
	label.font_size = 48
	label.pixel_size = 0.0034 * scale_of
	label.outline_size = 12
	label.modulate = tint
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.position = Vector3(0.0, drop, 0.02)
	label.shaded = false
	label.double_sided = false
	parent.add_child(label)
	return label


func _set_line(plank: Node3D, index: int, body: String, tint: Color) -> void:
	var label := plank.get_node_or_null("Line%d" % index) as Label3D
	if label == null:
		return
	label.text = body
	label.modulate = tint


## The top rows across everybody practising, best accuracy first. A shared
## session's board should say who is shooting well, and in a solo range that is
## simply your own four lines.
func _refresh_board(plank: Node3D) -> void:
	if not is_instance_valid(plank):
		return
	var lines: Array[Dictionary] = []
	for peer_id: Variant in rows:
		for weapon: String in WEAPONS:
			var entry := row(int(peer_id), weapon)
			if int(entry["launches"]) <= 0:
				continue
			lines.append({"peer": int(peer_id), "weapon": weapon,
				"acc": accuracy(entry), "row": entry})
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["acc"]) > float(b["acc"]))

	for i: int in 6:
		if i >= lines.size():
			_set_line(plank, i, "", UIPalette.TEXT)
			continue
		var line: Dictionary = lines[i]
		var entry: Dictionary = line["row"]
		_set_line(plank, i, "%s  %s  %d/%d  %d%%" % [
			Net.player_name(int(line["peer"])),
			String(line["weapon"]).to_upper(),
			int(entry["hits"]), int(entry["launches"]),
			roundi(float(line["acc"]) * 100.0)], UIPalette.TEXT)
