class_name RangeItems
extends Node
## Puts the practice range's item furniture on the markers unit 2 authored.
##
## One static call and no state. `RangeMap` builds `Wells`, `Racks` and `Plates`
## as groups of `Marker3D`s carrying `meta` that says what each one is — and
## nothing else; a marker is a place and a word, never a scene. This is the file
## that turns those into objects, and it is the only thing in the unit that
## knows the marker contract.
##
## **Called after `super()`**, by unit 3's director. Everything here is
## behaviour and dressing rather than collision: the map's `_ready` sweeps
## everything added *before* `super()` into one world-space trimesh, so an item
## well instanced before it would bake a pedestal into the floor and then build
## a second one on top. The bodies these nodes carry are runtime physics and are
## invisible to both the bake and `tools/parkour_report.gd`, which is correct —
## neither of those is about the props.
##
## **Idempotent.** A second call frees the first call's node and builds again,
## so a station reset, a rebuilt arena or a test that runs twice all end with
## exactly one of everything.

const WELL_SCENE := preload("res://scenes/items/item_well.tscn")
const RACK_SCENE := preload("res://scenes/items/weapon_rack.tscn")
const STONE_SCENE := preload("res://scenes/items/refill_stone.tscn")

## The node everything is parented to, so one `get_node_or_null` finds the lot.
const ROOT_NAME := "Items"

## The `Plates` marker this unit owns. The others on that group are unit 3's
## parkour plates, and a group shared by two units is exactly why the meta says
## which is which rather than the group name doing it.
const REFILL_ROLE := "refill"


## Build every item station on `map` and return the node they live under.
##
## Tolerant of a map with no markers at all — unit 1's placeholder range had
## none, and a tool that wants only the racks can hand over a `Node3D` with one
## group on it. A missing group is nothing to build, not an error.
static func build(map: Node) -> Node3D:
	if map == null:
		return null
	var old := map.get_node_or_null(ROOT_NAME)
	if old != null:
		old.free()
	var root := Node3D.new()
	root.name = ROOT_NAME
	map.add_child(root)

	var wells := _place_wells(map, root)
	var racks := _place_racks(map, root)
	var stones := _place_stones(map, root)
	print("RangeItems: %d wells, %d racks, %d refill stone(s)" % [wells, racks, stones])
	return root


static func _place_wells(map: Node, root: Node3D) -> int:
	var group := map.get_node_or_null("Wells") as Node3D
	if group == null:
		return 0
	var built := 0
	for marker: Node in group.get_children():
		var at := marker as Marker3D
		if at == null:
			continue
		var well := WELL_SCENE.instantiate() as ItemWell
		# Set **before** the node enters the tree, because `_ready` builds the
		# pedestal's colour, its icon and its light out of it — the same reason
		# `MatchState._create_bog` sets a Bog's weapon before `add_child`.
		well.kind = ItemWell.kind_from_meta(_meta(at, "kind", "shield"))
		well.name = at.name
		root.add_child(well)
		well.global_transform = at.global_transform
		built += 1
	return built


static func _place_racks(map: Node, root: Node3D) -> int:
	var group := map.get_node_or_null("Racks") as Node3D
	if group == null:
		return 0
	var built := 0
	for marker: Node in group.get_children():
		var at := marker as Marker3D
		if at == null:
			continue
		var rack := RACK_SCENE.instantiate() as WeaponRack
		rack.weapon = WeaponRack.weapon_from_meta(_meta(at, "weapon", "spear"))
		rack.name = at.name
		root.add_child(rack)
		# The marker's whole transform, so the rack faces the way unit 2 pointed
		# it — a marker's own -Z, which for these is back down the deck at the
		# spawns.
		rack.global_transform = at.global_transform
		built += 1
	return built


static func _place_stones(map: Node, root: Node3D) -> int:
	var group := map.get_node_or_null("Plates") as Node3D
	if group == null:
		return 0
	var built := 0
	for marker: Node in group.get_children():
		var at := marker as Marker3D
		if at == null or _meta(at, "role", "") != REFILL_ROLE:
			continue
		var stone := STONE_SCENE.instantiate() as RefillStone
		stone.name = at.name
		root.add_child(stone)
		stone.global_transform = at.global_transform
		built += 1
	return built


## A marker's `meta`, as a string, with a default.
##
## Defaulted rather than asserted, and warned about rather than crashed on. A
## marker unit 2 adds without its `meta` is a pedestal with the wrong icon on
## it, which somebody notices and fixes; a `SCRIPT ERROR` while the map is
## building is the range failing to load at all.
static func _meta(marker: Marker3D, key: String, fallback: String) -> String:
	if not marker.has_meta(key):
		if fallback != "":
			push_warning("RangeItems: %s has no '%s' meta, using '%s'"
				% [marker.name, key, fallback])
		return fallback
	return str(marker.get_meta(key))
