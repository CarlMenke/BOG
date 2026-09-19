class_name RangeDirector
extends Node
## Reads the range's markers and stands everything on them (D-112).
##
## Unit 2 authors the place and its `Marker3D`s; unit 1 owns the dummy registry;
## units 4 and 5 own the items and the targets. This is the one thing that walks
## the marker groups and hands each of them to whoever owns it — dummies to
## `RangeDummies`, the stats signboard and the parkour plates to this unit's own
## nodes, wells and racks to `RangeItems` if it is on disk.
##
## It is added by a single line in `range_map.gd` (unit 6's, beside unit 1's
## `RangeDummies`), and by `tools/range_brains.gd` directly, which is how this
## unit's gate runs without waiting on that line.
##
## ## Everything waits for PLAYING
##
## `MatchState.spawn_for` needs a standing arena and `claim_pickup` refuses
## outside `Phase.PLAYING`. The range reaches PLAYING immediately — a practice
## map has no warmup — so this is a wait of a frame or two rather than a delay,
## and it is the same wait `RangeDummies` already makes for the same reason.
##
## ## There is nothing on the wire any more
##
## This file used to carry an RPC and an index: six signposts you walked into
## that rotated a zone's dummies through a ring of behaviours, and a broadcast
## so every peer's lamp agreed about what a zone was doing. All of it is gone
## with the stations (see `range_map.SIGNBOARD`): a zone's behaviour is authored
## in the map's `DummyStations` meta and never changes, so there is no state to
## agree about and no message to send. What is left is a build, a set of
## readers, and one host-side call the stats signboard makes into `RangeStats`,
## which does its own broadcasting.

## Marker groups, as `range_map.gd` authors them. `DummyStations` and **not**
## `Dummies`: unit 1's registry node is itself called `Dummies` and
## `playthrough.gd` asserts on that, so the marker group had to be the one to
## move. The marker is not the dummy anyway — it is where one stands.
const GROUP_DUMMIES := "DummyStations"
## One marker, the stats signboard on the lodge deck. It was `Stations` with six
## in it.
const GROUP_SIGNS := "Signs"
const GROUP_PLATES := "Plates"

## Unit 4's wells and racks. Reached by path rather than by class, so this unit
## and its gate run whether or not that file has landed yet.
const ITEMS_SCRIPT := "res://scripts/world/range/range_items.gd"

## Unit 5's counter, boards and gong. Same guard and the same shape as the
## items above, deliberately: one convention for "a unit hangs itself off the
## map's markers", not two.
const STATS_SCRIPT := "res://scripts/world/range/range_stats.gd"

static var instance: RangeDirector = null

## zone -> array of live dummy peer ids.
var _zones: Dictionary = {}
var _signs: Array[RangeSignboard] = []
var _timer: ParkourTimer = null
var _built: bool = false


func _init() -> void:
	name = "RangeDirector"


func _ready() -> void:
	instance = self
	add_to_group("range_director")
	if MatchState.phase == MatchState.Phase.PLAYING:
		_build()
	else:
		MatchState.phase_changed.connect(_on_phase_changed)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _on_phase_changed(phase: int) -> void:
	if phase == MatchState.Phase.PLAYING:
		_build()


## The map this director is standing on. Its parent, because that is where the
## one `add_child` line puts it; the group is the fallback for a tool that
## parents it somewhere else.
func map_root() -> Node:
	var parent := get_parent()
	if parent != null and parent.has_node(GROUP_DUMMIES):
		return parent
	return get_tree().get_first_node_in_group("range_map")


func _build() -> void:
	if _built:
		return
	_built = true
	var map := map_root()
	if map == null:
		push_error("RangeDirector: no map to read markers from")
		return
	_build_dummies(map)
	_build_signs(map)
	_build_plates(map)
	_build_items(map)
	_build_stats(map)
	print("range: %d live dummies in %d zones, %d signboards, %s" % [
		_live_count(), _zones.size(), _signs.size(),
		"a parkour clock" if _timer != null else "no plates"])


func _build_dummies(map: Node) -> void:
	var root := map.get_node_or_null(GROUP_DUMMIES)
	if root == null:
		return
	for child in root.get_children():
		var marker := child as Marker3D
		if marker == null:
			continue
		var meta := _meta_of(marker)
		var zone := String(meta.get("zone", ""))
		var brain := String(meta.get("brain", "stand"))
		# `live: false` used to mean a proven place to stand that a station would
		# mint a body onto. With the stations gone nothing ever would, so the map
		# authors every marker live and this is only a guard for a tool that
		# builds its own fixture.
		if not bool(meta.get("live", true)):
			continue
		_spawn(zone, marker.global_transform, brain, meta)


func _spawn(zone: String, at: Transform3D, brain: String, meta: Dictionary) -> int:
	if RangeDummies.instance == null:
		return 0
	var id := RangeDummies.instance.spawn(at, brain, meta)
	if id > 0:
		if not _zones.has(zone):
			_zones[zone] = []
		_zones[zone].append(id)
	return id


func _build_signs(map: Node) -> void:
	var root := map.get_node_or_null(GROUP_SIGNS)
	if root == null:
		return
	for child in root.get_children():
		var marker := child as Marker3D
		if marker == null:
			continue
		var sign := RangeSignboard.new()
		sign.setup(marker)
		_signs.append(sign)
		add_child(sign)


func _build_plates(map: Node) -> void:
	var root := map.get_node_or_null(GROUP_PLATES)
	if root == null:
		return
	var timer := ParkourTimer.new()
	timer.name = "ParkourTimer"
	add_child(timer)
	var plates := 0
	for child in root.get_children():
		var marker := child as Marker3D
		if marker != null and timer.add_plate(marker):
			plates += 1
	if plates == 0:
		timer.queue_free()
		return
	_timer = timer


## Unit 4's wells, racks and refill stone. Guarded rather than called, so this
## unit's gate is green whether or not that file exists at the moment it runs.
func _build_items(map: Node) -> void:
	if not ResourceLoader.exists(ITEMS_SCRIPT):
		return
	var script: GDScript = load(ITEMS_SCRIPT)
	if script != null and script.has_method("build"):
		script.build(map)


## Unit 5's targets and the stats counter. Guarded exactly as `_build_items` is,
## and after it, so the boards on the lodge wall go up once the map is furnished.
func _build_stats(map: Node) -> void:
	if not ResourceLoader.exists(STATS_SCRIPT):
		return
	var script: GDScript = load(STATS_SCRIPT)
	if script != null and script.has_method("build"):
		script.build(map)


## Unit 5's counters. A stub by design: reached through the group rather than
## the class, and checked for the method, so this lands and runs before that
## file exists.
func reset_stats() -> void:
	var stats := get_tree().get_first_node_in_group("range_stats")
	if stats != null and stats.has_method("reset"):
		stats.call("reset")


func _meta_of(marker: Marker3D) -> Dictionary:
	var out: Dictionary = {}
	for key: String in marker.get_meta_list():
		out[key] = marker.get_meta(key)
	return out


# ------------------------------------------------------------------ readers ---

func dummies_in(zone: String) -> Array:
	return _zones.get(zone, [])


func signboard_count() -> int:
	return _signs.size()


func signboard_at(index: int) -> RangeSignboard:
	return _signs[index] if index >= 0 and index < _signs.size() else null


func parkour() -> ParkourTimer:
	return _timer


func _live_count() -> int:
	var total := 0
	for zone: String in _zones:
		total += (_zones[zone] as Array).size()
	return total
