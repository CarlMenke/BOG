extends Node3D
## Stand somewhere on Highsun Grounds and look at it. Development tool, not
## shipped.
##
## The same tool as `tools/quarry_views.gd` and for the same reason: eye-height
## shots of a built map, from where a player actually stands, because a map that
## reads from a photographer's tripod and not from 1.45 m is a map nobody will
## ever see the good version of.
##
## **It builds the range's items itself**, which is the one thing this has that
## the quarry's does not. `RangeMap` adds a `RangeDirector` after `super()`, and
## that director waits for `MatchState.Phase.PLAYING` before it stands anything
## on the markers — so a plain render of `range.tscn` shows the deck with eight
## invisible markers on it and no racks, no wells and no refill stone. That is
## why the rack move (D-161) could not be judged from `tools/preview_map.tscn`'s
## `pad0..pad7` views: those frames are honest about the geometry and silent
## about the furniture. `RangeItems.build()` is a static call with no phase
## requirement in it, so calling it directly puts the racks and the wells on
## their markers without a match running. The pickups the wells mint still need
## a host and a phase, so a well renders as its pedestal with an empty top,
## which is the right amount of lie for a framing check.
##
## Usage:
##   Godot --path . --resolution 1600x900 --script tools/snapshot.gd -- \
##       res://tools/range_views.tscn out.png 45 <view>
##
## Views: see `SHOTS`.

const MAP := "res://scenes/world/maps/range.tscn"
const ITEMS_SCRIPT := "res://scripts/world/range/range_items.gd"
## A Bog's eye, off `Bog` rather than typed.
const EYE := 1.45

## Each shot as (where the camera stands, what it looks at, field of view). The
## `y` of each is measured from whatever the camera is standing on — 0 for the
## bog, 1.2 for the lodge deck — and `EYE` is added.
const SHOTS := {
	# The shot the rack move exists to pass: standing on spawn pad 1, the
	# second of the front row, looking south-east down the deck. Both rows of
	# fittings are in frame — the racks on the east wall dead ahead, the wells
	# and the signboard along the west wall on the right — and the question it
	# answers is whether a player who has just spawned can see what there is to
	# take without hunting for it.
	"pad": [Vector3(-3.25, 1.2, 37.0), Vector3(11.0, 1.9, 42.0), 78.0],
	# The same deck from the other side, standing on the outer west pad. The
	# wells are an arm's length to the right and the racks are across the hall.
	"pad_west": [Vector3(-9.75, 1.2, 44.0), Vector3(11.0, 1.9, 39.0), 78.0],
	# Down the length of the hall from the open front, which is how the deck is
	# read walking back in off the apron. **Not on x = 0**: `_build_lodge` puts
	# a roof post there, and the first version of this shot was the inside of
	# one.
	"hall": [Vector3(2.7, 1.2, 34.8), Vector3(2.7, 2.0, 46.0), 75.0],
	# Both rows in one frame, which nothing standing on the deck can do: the
	# hall is 24 m across, so from anywhere inside it one wall or the other is
	# past 70 degrees off the nose. This backs off onto the apron and looks in
	# under the eave — racks on the left, wells and the signboard on the right,
	# both about 45 degrees out.
	"deck": [Vector3(0.0, 0.0, 27.0), Vector3(0.0, 2.0, 40.0), 80.0],
	# Standing on the outer east pad of the front row — the pad the racks are
	# nearest to — turned to face them. Two metres, which is what "in reach"
	# means here.
	"pad_east": [Vector3(9.75, 1.2, 37.0), Vector3(11.1, 1.9, 40.5), 78.0],
	# Up against the east wall at the bow rack, the distance a player stands at
	# when the walk-over fires.
	"racks": [Vector3(8.6, 1.2, 40.5), Vector3(11.1, 2.0, 40.8), 70.0],
	# And the west wall's row, from the same distance.
	"wells": [Vector3(-8.2, 1.2, 40.5), Vector3(-10.75, 1.8, 40.5), 70.0],
	# The apron the two rows left, from the middle of it looking back at the
	# lodge — the frame that says whether the ground in front of the hall reads
	# as open or as empty.
	"apron": [Vector3(0.0, 0.0, 26.0), Vector3(-2.0, 3.0, 40.0), 80.0],
	# The apron's west end, where the three racks used to stand.
	"apron_west": [Vector3(-20.0, 0.0, 28.0), Vector3(-30.0, 2.0, 33.0), 80.0],
}


## What a Bog is, physically, for the `probe` view. Off `Bog` rather than typed,
## for `preview_map`'s reason: a change to the character's size should fail this
## instead of quietly invalidating it.
const CAPSULE_RADIUS := Bog.CAPSULE_RADIUS
const CAPSULE_HEIGHT := Bog.STAND_HEIGHT
const CAPSULE_LIFT := 0.775
const LAYER_WORLD := 1
const LAYER_PLAYER := 2

var _probe := false
var _map: Node = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var view := "pad"
	if args.size() >= 4:
		view = String(args[3])
	# `probe` is not a camera. It stands a Bog-shaped capsule on all eight pads
	# and prints what the lodge's furniture does to it, which is the half of
	# "the racks moved indoors" (D-161) that a picture cannot answer: a rack's
	# uprights are a runtime `StaticBody3D` on the world layer and its swap
	# trigger is an `Area3D` on the player layer, and neither of those is in the
	# collision bake `tools/preview_map.tscn` checks the pads against. A pad
	# that is inside a rack, or close enough that spawning hands you a weapon,
	# would pass every existing check on this map.
	if view == "probe":
		_probe = true
		view = "pad"
	if not SHOTS.has(view):
		push_error("range_views: no view %s; have %s" % [view, SHOTS.keys()])
		view = "pad"
	var shot: Array = SHOTS[view]

	var packed := load(MAP) as PackedScene
	if packed == null:
		push_error("range_views: could not load %s" % MAP)
		return
	var map := packed.instantiate()
	# Named as `arena.gd` names it, so the map's own build log line reads the
	# same here as it does in a match.
	map.name = "Map"
	add_child(map)
	_map = map

	# The furniture. Guarded by path rather than by class for the reason
	# `RangeDirector` is: this tool should still render a map if unit 4's file
	# is not on disk, and say so rather than fail to compile.
	var items := load(ITEMS_SCRIPT)
	if items == null:
		push_warning("range_views: no %s — rendering the map without its items"
			% ITEMS_SCRIPT)
	else:
		var built: Node = items.build(map)
		if _probe:
			_arm_triggers(built)

	var at: Vector3 = shot[0]
	var aim: Vector3 = shot[1]
	var camera := Camera3D.new()
	camera.position = at + Vector3.UP * EYE
	camera.fov = float(shot[2])
	camera.near = 0.05
	camera.far = 400.0
	camera.look_at_from_position(camera.position, aim, Vector3.UP)
	add_child(camera)
	camera.make_current()
	print("range_views: %s from %v looking at %v" % [view, camera.position, aim])


## Put the item triggers on a layer, so a shape query can find them at all.
##
## **The reason the first version of the probe passed everything and measured
## nothing.** A `WeaponRack` is an `Area3D` with `collision_layer = 0` and
## `collision_mask = Pickup.LAYER_PLAYER`: it *watches* the player layer and
## sits on no layer itself, which is right — nothing in the game ever needs to
## query for a rack, the rack does the looking. But a shape query filters by the
## layer of the thing it is looking for, so `collide_with_areas` against a
## layer-0 area finds nothing, always, and reports it as clearance. Eight pads
## came back "arms 0 racks" before a single number in that line was true.
##
## So the probe puts them on the player layer for the length of its own run.
## Nothing in the game does this and nothing should: it is a measuring tool
## borrowing a layer, on a copy of the map that exists for one render.
func _arm_triggers(root: Node) -> void:
	if root == null:
		return
	for child: Node in root.get_children():
		var area := child as Area3D
		if area != null:
			area.collision_layer = LAYER_PLAYER


## Stand a Bog on every pad and say what the lodge's furniture does to it.
##
## Three questions, and they are different questions. *Is the pad blocked* asks
## whether the capsule overlaps a solid — a rack upright or a well pedestal, both
## of which are runtime bodies on the world layer. *Does the pad arm a rack* asks
## whether the capsule overlaps a `WeaponRack`'s trigger `Area3D`, which is
## 1.1 m deep and wider than the frame it belongs to: a pad inside one hands a
## player a weapon for standing still on the frame they spawn, which is not what
## "you equip where you spawn" was supposed to mean. *How much daylight* is the
## margin on the second, and it is the number to watch — the geometry is clear
## either way, but a pad moved half a metre east would not be.
##
## Waits for the broadphase like `preview_map` does: a query from `_ready` runs
## before anything static is in it and reports a beautifully empty world.
func _physics_process(_delta: float) -> void:
	if not _probe or Engine.get_physics_frames() < 3:
		return
	_probe = false
	var map := _map as StaticMap
	if map == null:
		push_error("range_views: the map's root is not a StaticMap")
		return

	var space := get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT

	var solids := PhysicsShapeQueryParameters3D.new()
	solids.shape = capsule
	solids.collision_mask = LAYER_WORLD
	var triggers := PhysicsShapeQueryParameters3D.new()
	triggers.shape = capsule
	triggers.collision_mask = LAYER_PLAYER
	triggers.collide_with_areas = true
	triggers.collide_with_bodies = false

	var fittings: Array[Node3D] = []
	for group_name: String in ["Racks", "Wells"]:
		var group := map.get_node_or_null(group_name) as Node3D
		if group == null:
			continue
		for marker: Node in group.get_children():
			if marker is Node3D:
				fittings.append(marker)

	var failures := 0
	var pads := map.spawn_points()
	for i: int in pads.size():
		var at: Vector3 = pads[i].origin
		var centre := at + Vector3.UP * CAPSULE_LIFT
		solids.transform = Transform3D(Basis.IDENTITY, centre)
		triggers.transform = Transform3D(Basis.IDENTITY, centre)
		var blocked := space.intersect_shape(solids, 4)
		var armed := space.intersect_shape(triggers, 4)

		# The nearest fitting by marker, so the number means something to read
		# against the table in `range_map.gd` rather than being the distance to
		# whichever collision shape happened to be nearest.
		var nearest := INF
		var which := "-"
		for marker: Node3D in fittings:
			var flat := Vector2(marker.global_position.x - at.x,
				marker.global_position.z - at.z)
			var gap := flat.length() - CAPSULE_RADIUS
			if gap < nearest:
				nearest = gap
				which = marker.name
		if not blocked.is_empty() or not armed.is_empty():
			failures += 1
		print("  pad %d  %s  blocked by %d  arms %d rack(s)  nearest %s at %.2f m" % [
			i, _vec(at), blocked.size(), armed.size(), which, nearest])

	failures += _probe_reach(map, space, capsule)
	print("range_views: probe %s (%d pad(s) blocked or armed, or rack(s) out of reach)"
		% ["PASS" if failures == 0 else "FAIL", failures])


## Can a Bog standing on the deck actually work a rack against a wall?
##
## The half of D-161 that is not about the pads. A `WeaponRack` is a walk-over
## `Area3D` and not a ray or a prompt — there is no interact action bound in
## this project, see `weapon_rack.gd` — so "does the interaction still reach"
## is the question of whether there is a band of floor in front of the frame
## that a Bog-shaped capsule fits in and that overlaps the trigger. Against a
## wall there might not have been: the frame's own uprights are solid, the
## trigger is only 1.1 m deep, and a rack pushed too close to the timber would
## leave the whole of its trigger inside the part of the deck a capsule cannot
## stand in.
##
## So this walks out from each rack's readable face in ten-centimetre steps and
## prints the first standable distance and the last one that still arms the
## swap. The wall cannot block it — the wall is behind the rack — and the
## third-person camera is in the same band looking the other way, at the open
## deck.
func _probe_reach(map: StaticMap, space: PhysicsDirectSpaceState3D,
		capsule: CapsuleShape3D) -> int:
	var group := map.get_node_or_null("Racks") as Node3D
	if group == null:
		return 0
	var solids := PhysicsShapeQueryParameters3D.new()
	solids.shape = capsule
	solids.collision_mask = LAYER_WORLD
	var triggers := PhysicsShapeQueryParameters3D.new()
	triggers.shape = capsule
	triggers.collision_mask = LAYER_PLAYER
	triggers.collide_with_areas = true
	triggers.collide_with_bodies = false

	var failures := 0
	for marker: Node in group.get_children():
		var at := marker as Marker3D
		if at == null:
			continue
		# The readable face, off the built transform rather than off the yaw
		# constant, so this still measures the right side of the rack if
		# somebody turns it round.
		var face := at.global_transform.basis.z.normalized()
		var nearest := -1.0
		var furthest := -1.0
		for step: int in 20:
			var out := 0.1 + 0.1 * float(step)
			var centre := at.global_position + face * out + Vector3.UP * CAPSULE_LIFT
			solids.transform = Transform3D(Basis.IDENTITY, centre)
			triggers.transform = Transform3D(Basis.IDENTITY, centre)
			if not space.intersect_shape(solids, 1).is_empty():
				continue
			if space.intersect_shape(triggers, 1).is_empty():
				continue
			if nearest < 0.0:
				nearest = out
			furthest = out
		if nearest < 0.0:
			failures += 1
			print("  %s  NO standable spot in front of it arms the swap" % at.name)
		else:
			print("  %s  arms the swap from %.1f to %.1f m out (%.1f m band)"
				% [at.name, nearest, furthest, furthest - nearest])
	return failures


func _vec(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
