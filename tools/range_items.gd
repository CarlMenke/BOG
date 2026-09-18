extends Node3D
## Headless proof of unit 4: the item wells, the refill stone and the weapon
## racks.
##
##   "$GODOT" --headless --path . tools/range_items.tscn -- all
##
## **It builds its own markers.** The real `RangeMap` authors `Wells`, `Racks`
## and `Plates`, and unit 3's director is what calls `RangeItems.build` in the
## game — but a check that needed either of those would be a check that fails
## when somebody else's unit is mid-edit, and would not be telling you about
## this unit at all. So the markers here are a copy of `range_map.gd`'s own
## tables, laid out on a bare floor, and what is proven is the contract: given
## markers shaped like that, these nodes appear and behave.
##
## The four things asserted are the four things that could silently not work:
## a well puts an item back after its own delay; the stone raises a Bog to the
## caps; the stone does nothing at all to a Bog that is already full; and a rack
## changes the weapon on the Bog, in its hand and in the roster row that a
## respawn will read.

## The real map's tables, copied. Kept as the same shape rather than imported,
## because importing them would make this tool pass or fail on unit 2's layout
## rather than on unit 4's behaviour.
const WELLS := [
	{"at": Vector2(6.0, 31.0), "kind": "shield"},
	{"at": Vector2(9.0, 31.0), "kind": "magnet"},
	{"at": Vector2(12.0, 31.0), "kind": "potion"},
	{"at": Vector2(15.0, 31.0), "kind": "robe"},
]
const RACKS := [
	{"at": Vector2(-31.0, 31.0), "weapon": "spear"},
	{"at": Vector2(-28.0, 31.0), "weapon": "bow"},
	{"at": Vector2(-25.0, 31.0), "weapon": "sword"},
]
const PLATES := [
	{"at": Vector3(9.0, 0.0, -16.0), "role": "parkour_start"},
	{"at": Vector3(16.5, 5.0, -40.0), "role": "parkour_finish"},
	{"at": Vector3(0.0, 0.0, 40.5), "role": "refill"},
]

const FLOOR_SIZE := 140.0

var _map: Node3D
var _items: Node3D
var _players: Node3D
var _built: Node3D
var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_build_stage()
	_start_session()
	_build_markers()
	_built = RangeItems.build(_map)
	await get_tree().process_frame
	await get_tree().process_frame
	await _run()
	_verdict()


# ------------------------------------------------------------------- stage ---

func _build_stage() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(FLOOR_SIZE, 1.0, FLOOR_SIZE)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	add_child(floor_body)

	_items = Node3D.new()
	_items.name = "SpawnedItems"
	# Without this group every placed pickup is parented to the scene root and
	# the wells can never find their own stock. `MatchState._spawn_root`.
	_items.add_to_group("spawned_items")
	add_child(_items)

	_players = Node3D.new()
	_players.name = "Players"
	add_child(_players)

	_map = Node3D.new()
	_map.name = "Map"
	add_child(_map)


func _start_session() -> void:
	Net.start_offline()
	Net.players[1]["weapon"] = Loadout.Weapon.SPEAR
	Net.roster_changed.emit()
	var config := Net.config
	config.warmup_time = 0.0
	config.spawn_protection = 0.0
	config.respawn_delay = 1.0
	config.time_limit = 0
	config.kill_limit = 0
	var spawns: Array[Transform3D] = []
	for i in 8:
		spawns.append(Transform3D(Basis(), Vector3(float(i) * 3.0 - 10.0, 0.2, 0.0)))
	MatchState.register_arena(_players, spawns)


func _build_markers() -> void:
	var wells := _group("Wells")
	for entry: Dictionary in WELLS:
		var at: Vector2 = entry["at"]
		_marker(wells, "Well_%s" % entry["kind"], Vector3(at.x, 0.0, at.y),
			{"kind": entry["kind"]})
	var racks := _group("Racks")
	for entry: Dictionary in RACKS:
		var at: Vector2 = entry["at"]
		_marker(racks, "Rack_%s" % entry["weapon"], Vector3(at.x, 0.0, at.y),
			{"weapon": entry["weapon"]})
	var plates := _group("Plates")
	for entry: Dictionary in PLATES:
		_marker(plates, "Plate_%s" % entry["role"], entry["at"],
			{"role": entry["role"]})


func _group(node_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	_map.add_child(root)
	return root


func _marker(root: Node3D, node_name: String, at: Vector3, meta: Dictionary) -> void:
	var marker := Marker3D.new()
	marker.name = node_name
	marker.transform = Transform3D(Basis(Vector3.UP, PI), at)
	for key: String in meta:
		marker.set_meta(key, meta[key])
	root.add_child(marker)


# ------------------------------------------------------------------ checks ---

func _run() -> void:
	print("range_items: %d wells, %d racks, %d stone(s) placed"
		% [_count(ItemWell), _count(WeaponRack), _count(RefillStone)])
	_check("every marker became a node",
		_count(ItemWell) == 4 and _count(WeaponRack) == 3 and _count(RefillStone) == 1)
	# The two parkour plates are unit 3's and must have been left alone.
	_check("only the refill plate was claimed", _count(RefillStone) == 1)
	await _check_well()
	await _check_stone()
	await _check_rack()


## A well puts an item back, on its own clock.
func _check_well() -> void:
	var well := _well("shield")
	var robe := _well("robe")
	if well == null or robe == null:
		_check("the shield and robe wells exist", false)
		return
	await _settle(0.6)
	_check("a well stocks itself", well.is_stocked())
	var id: int = well._pickup_id
	_check("the host minted a real pickup id", id > 0)

	# Taken the way a player takes one: the host's award, which is what fires
	# `pickup_taken` and therefore what the well is listening for.
	MatchState.claim_pickup(id, 1)
	await _settle(0.2)
	_check("taking the stock empties the well", not well.is_stocked())

	# The robe's delay is asserted rather than waited out: twenty seconds is the
	# right number for the game and the wrong number for a gate, and what could
	# break is the schedule, not the clock.
	var robe_id: int = robe._pickup_id
	MatchState.claim_pickup(robe_id, 1)
	await _settle(0.2)
	var robe_wait: float = robe._mint_at - robe._clock
	print("range_items: robe well waits %.1f s, shield well %.1f s"
		% [robe_wait, float(ItemWell.DELAY[Pickup.Kind.SHIELD])])
	_check("the robe well waits 20 s", absf(robe_wait - 20.0) < 0.5)

	var delay: float = ItemWell.DELAY[Pickup.Kind.SHIELD]
	await _settle(delay * 0.5)
	_check("the well is still empty half way through the delay", not well.is_stocked())
	await _settle(delay * 0.6 + 0.4)
	var remade := well.is_stocked()
	_check("a well re-minted after its delay", remade)
	if remade:
		print("range_items: a well re-minted %.1f s after it was taken PASS" % delay)

	# Tidy up after the two claims above. They were real awards — that is the
	# point of taking the stock the way a player does — so peer 1 is now holding
	# a shield and wearing the robe, and both would walk into the next check: a
	# Bog that is the Elder has empty hands (`has_spear()` is false for one), so
	# the rack check would be asserting against a body carrying nothing for a
	# reason that has nothing to do with racks.
	MatchState._end_elder(1)
	var bog := MatchState.bogs.get(1) as Bog
	var combat := bog.get_node_or_null("Combat") as BogCombat
	combat.reset()
	await _settle(0.2)


## The stone fills what is missing, and does nothing when nothing is.
func _check_stone() -> void:
	var stone := _first(RefillStone) as RefillStone
	var bog := MatchState.bogs.get(1) as Bog
	if stone == null or bog == null:
		_check("the stone and a Bog exist", false)
		return
	var combat := bog.get_node_or_null("Combat") as BogCombat
	_check("the Bog starts empty", combat.shield_count() == 0
		and combat.magnet_count() == 0 and combat.potion_count() == 0)

	bog.revive_at(Transform3D(Basis(), stone.global_position + Vector3.UP * 0.6))
	await _settle(0.8)
	var got := Vector3i(combat.shield_count(), combat.magnet_count(), combat.potion_count())
	var full := Vector3i(RefillStone.FULL["shields"], RefillStone.FULL["magnets"],
		RefillStone.FULL["potions"])
	_check("the stone fills to the caps", got == full)
	if got == full:
		print("range_items: the refill stone raised 0/0/0 to %d/%d/%d PASS"
			% [got.x, got.y, got.z])

	# Standing there, already full, for longer than the cooldown. Nothing may
	# move — not the counts, and not the cooldown row, which is never started on
	# a no-op.
	_check("the fill started a cooldown for that peer", stone._next_ok.has(1))
	await _settle(RefillStone.COOLDOWN + 0.5)
	var still := Vector3i(combat.shield_count(), combat.magnet_count(), combat.potion_count())
	_check("a full Bog is not topped up again", still == got)
	if still == got:
		print("range_items: a full Bog got nothing and no chime PASS")

	# Off the stone, so the rack check starts from a Bog standing nowhere near
	# it — the two stations must not be able to reach each other.
	bog.revive_at(Transform3D(Basis(), Vector3(0.0, 0.2, -30.0)))
	await _settle(0.4)


## A rack changes the weapon everywhere it is written down.
func _check_rack() -> void:
	var rack := _rack(Loadout.Weapon.BOW)
	var bog := MatchState.bogs.get(1) as Bog
	if rack == null or bog == null:
		_check("the bow rack and a Bog exist", false)
		return
	_check("the Bog starts with a spear", bog.weapon == Loadout.Weapon.SPEAR)
	_check("and a spear in its hand", bog.held_gear.is_carried())

	# **Read inside the overlap, not after it.** The claim is that a rack swap
	# lands within one frame, and the honest way to prove that is to look on the
	# frame the overlap happened rather than to wait and then find it done. The
	# rack connected its own handler in `_ready`, before this one, so by the time
	# this runs `set_weapon` has already returned — everything below is the state
	# on the rack's own physics tick.
	var seen := {}
	rack.body_entered.connect(func(body: Node3D) -> void:
		if body != bog or seen.has("weapon"):
			return
		seen["weapon"] = bog.weapon
		seen["bow"] = bog.held_gear.has_bow()
		seen["shaft"] = bog.held_gear.is_carried()
		seen["roster"] = Net.player_weapon(1))

	bog.revive_at(Transform3D(Basis(), rack.global_position + Vector3.UP * 0.6))
	# A teleport into an area is noticed on a physics tick, not on the frame the
	# transform was written, so this waits for the overlap rather than assuming
	# which tick it lands on. What is asserted is still same-frame: the values
	# were captured inside the signal.
	var waited := 0.0
	while not seen.has("weapon") and waited < 3.0:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
	if not seen.has("weapon"):
		_check("the rack noticed the Bog", false)
		return

	print("range_items: rack -> weapon=%s hand(bow)=%s roster=%s"
		% [Loadout.weapon_name(seen["weapon"]), seen["bow"],
			Loadout.weapon_name(seen["roster"])])
	var swapped: bool = seen["weapon"] == Loadout.Weapon.BOW
	_check("the rack changed the Bog's weapon on the overlap's own frame", swapped)
	_check("the bow was in the hand on that frame", seen["bow"])
	_check("the spear had left the hand", not seen["shaft"])
	_check("the roster row followed", seen["roster"] == Loadout.Weapon.BOW)
	if swapped and seen["bow"] and not seen["shaft"] \
			and seen["roster"] == Loadout.Weapon.BOW:
		print("range_items: a rack swapped spear to bow on the Bog, "
			+ "the hand and the roster within one frame PASS")


# ------------------------------------------------------------------- tools ---

func _well(kind: String) -> ItemWell:
	for node in _built.get_children():
		var well := node as ItemWell
		if well != null and well.kind == ItemWell.kind_from_meta(kind):
			return well
	return null


func _rack(weapon: int) -> WeaponRack:
	for node in _built.get_children():
		var rack := node as WeaponRack
		if rack != null and rack.weapon == weapon:
			return rack
	return null


func _first(type: Variant) -> Node:
	for node in _built.get_children():
		if is_instance_of(node, type):
			return node
	return null


func _count(type: Variant) -> int:
	var found := 0
	for node in _built.get_children():
		if is_instance_of(node, type):
			found += 1
	return found


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		print("range_items: FAIL — %s" % what)


func _verdict() -> void:
	print("range_items: %d checks, %d failures" % [_checks, _failures])
	print("range_items: %s" % ("PASS" if _failures == 0 else "FAIL"))
	get_tree().quit(0 if _failures == 0 else 1)
