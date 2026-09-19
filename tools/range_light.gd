extends Node3D
## Stand where a player stands on Highsun Grounds and look at the *light*.
## Development tool, not shipped.
##
## `tools/range_views.gd` is the framing tool — it answers "can a player who has
## just spawned see the racks", and every one of its shots is inside the lodge or
## on the apron in front of it. That is the right question for D-161 and the
## wrong one for the light: the range is ninety metres long and the thing the
## owner complained about (*"the suns lights is too strong … the whole scene
## reads orange"*, D-169) is what the open bog and a body standing out on it look
## like, which no shot of the deck shows.
##
## So this is four framings and nothing else, each one a question about the
## light rather than about the furniture:
##
##   spawn    on the front row of pads, under the lodge roof, looking straight
##            down the bow lane. **The one the ticket names.** It has the sun's
##            half of the sky in the top-right corner, the unlit underside of the
##            roof across the top, sixty metres of open peat, and the horizon —
##            every surface the key reaches and every one it does not, in one
##            frame.
##   lane     the middle throwing lane's firing mark, at the strafer 15 m out.
##            A body at a readable distance against open ground: this is where
##            the body luma comes from.
##   lodge    from the back of the hall looking out of the open front. The
##            interior-versus-field test — with the racks and the wells indoors
##            (D-161) the hall is the one enclosed room on the map, and a room
##            lit only by ambient under a brightened sky reads as a black box cut
##            into a white field.
##   long45   the bow lane's firing mark at the 45 m dummy, which is D-119's
##            question — *does the scene read at forty-five metres* — asked of
##            the light rather than of the geometry.
##
## **It stands real bodies on the map's own stations**, for `range_views`'
## reason turned to a different end: `RangeDirector` only places dummies once
## `MatchState` reaches `PLAYING`, so a plain render of `range.tscn` is a bog
## with nothing standing on it and there is no body in frame to read a luma off.
## These are `bog.tscn` instances on the `DummyStations` markers the map builds,
## registered as bots exactly the way `RangeDummies.spawn` registers one, so each
## wears the dummy skin and the shader the game puts on it. They do not move —
## nothing replicates to them and nothing needs to, because a photograph of the
## light does not care what a strafer is doing.
##
## Usage:
##   Godot --path . --resolution 1600x900 --script tools/snapshot.gd -- \
##       res://tools/range_light.tscn out.png 45 <view>
##
## Views: spawn, lane, lodge, long45.
##
## The numbers come off the PNGs afterwards, not out of here — a median over a
## patch of open peat, a mean luma over a patch of a body, the same patches
## before and after a change. That is how D-135 measured the sun it raised and
## how D-136 measured the moon it added, and a tool that printed its own verdict
## would only be a third place for the patch rectangles to go stale.

const MAP := "res://scenes/world/maps/range.tscn"
const ITEMS_SCRIPT := "res://scripts/world/range/range_items.gd"
const BOG := preload("res://scenes/player/bog.tscn")
## A Bog's eye, off `Bog` rather than typed.
const EYE := 1.45
## The game's own lens (`bog_camera.gd`), because a shot at any other field of
## view is a shot of a place nobody stands in.
const FOV := 75.0

## Which zones get a body stood on their stations. The lanes and the bow lane
## are what the four framings look at; the melee pit, the yard clump and the
## parkour course are off frame in all four and cost a skeleton each.
const BODY_ZONES := ["lanes", "long", "gallery"]

## Each shot as (where the camera stands, what it looks at). The `y` of the
## first is measured from whatever the camera is standing on — 0 out on the bog,
## `RangeMap.DECK` on the lodge deck — and `EYE` is added.
##
## Written against `RangeMap`'s own constants wherever one exists, so a lane that
## moves takes its camera with it. The two that are not derived are the lodge's
## `x` — 2.7, which is `range_views.hall`'s number and is off the centre line
## because `_build_lodge` puts a roof post on it — and the aim heights, which are
## a Bog's chest and are a framing choice rather than a fact about the map.
static func shots() -> Dictionary:
	var lane_x := -23.0  # the middle lane's centre, from `LANE_LINES`.
	return {
		"spawn": [
			Vector3(RangeMap.PAD_X[1], RangeMap.DECK + RangeMap.PAD_LIFT,
				RangeMap.PAD_Z[0]),
			Vector3(0.0, 1.2, RangeMap.LONG_FIRING_Z - RangeMap.LONG_DUMMY),
		],
		"lane": [
			Vector3(lane_x, 0.0, RangeMap.LANE_FIRING_Z),
			Vector3(lane_x, 1.2, RangeMap.LANE_FIRING_Z - RangeMap.LANE_DUMMIES[1]),
		],
		"lodge": [
			Vector3(2.7, RangeMap.DECK, RangeMap.LODGE_Z.y - 1.0),
			Vector3(2.0, 1.6, RangeMap.LODGE_Z.x - 14.0),
		],
		"long45": [
			Vector3(0.0, 0.0, RangeMap.LONG_FIRING_Z),
			Vector3(0.0, 1.1, RangeMap.LONG_FIRING_Z - RangeMap.LONG_DUMMY),
		],
	}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var view := "spawn"
	# Found by matching a known name rather than at a fixed index, for
	# `preview_capture`'s reason: through `snapshot.gd` the user args start
	# `scene png ticks`, and run as a plain scene they do not.
	for arg: String in args:
		if shots().has(arg):
			view = arg

	# A session, because a `Bog` reads its name, its team and its skin off
	# `Net.players` and builds a default grey body without a row.
	Net.start_offline()

	var packed := load(MAP) as PackedScene
	if packed == null:
		push_error("range_light: could not load %s" % MAP)
		return
	var map := packed.instantiate()
	# Named as `arena.gd` names it, so the map's own build log line — the one
	# carrying the sun's elevation and bearing — reads the same here as it does
	# in a match.
	map.name = "Map"
	add_child(map)

	# The racks, the wells and the refill stone. Indoors since D-161, so they are
	# most of what the `lodge` framing is looking at.
	var items := load(ITEMS_SCRIPT)
	if items == null:
		push_warning("range_light: no %s — rendering the map without its items"
			% ITEMS_SCRIPT)
	else:
		items.build(map)

	var bodies := _stand_bodies(map)

	var shot: Array = shots()[view]
	var camera := Camera3D.new()
	camera.position = (shot[0] as Vector3) + Vector3.UP * EYE
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 400.0
	camera.look_at_from_position(camera.position, shot[1] as Vector3, Vector3.UP)
	add_child(camera)
	camera.make_current()
	print("range_light: %s from %v looking at %v, %d bodies"
		% [view, camera.position, shot[1], bodies])


## A body on every station in `BODY_ZONES`, registered the way a dummy is.
##
## The roster row goes in before the body for `RangeDummies.spawn`'s reason —
## `Bog` reads the row when it is added to the tree, and a body added first is a
## body wearing the default skin for ever — and the authority is set before
## `add_child` for `preview_capture`'s: a node's authority is read on entry.
##
## `sync_grounded` has to be set by hand. Nothing replicates to these, and a
## remote Bog left un-grounded plays the fall clip for ever, which is a
## photograph of the light with ten bodies in it falling out of the sky.
func _stand_bodies(map: Node) -> int:
	var root := map.get_node_or_null("DummyStations") as Node3D
	if root == null:
		push_warning("range_light: the map built no DummyStations")
		return 0
	var skin := Skins.NAMES.find(RangeDummies.SKIN)
	var stood := 0
	for marker: Node in root.get_children():
		var at := marker as Marker3D
		if at == null or not BODY_ZONES.has(String(at.get_meta("zone", ""))):
			continue
		if not bool(at.get_meta("live", true)):
			continue
		var id := Net.BOT_BASE + stood
		Net.add_bot(id, {
			"name": "Light %d" % stood, "team": MatchConfig.TEAM_NONE,
			"ready": true, "dummy": true, "weapon": Loadout.DEFAULT,
			"skin": skin,
		})
		var body := BOG.instantiate() as Bog
		body.name = "LightBody%d" % stood
		body.peer_id = id
		body.set_multiplayer_authority(id)
		add_child(body)
		# Both halves: a remote Bog lerps its own position toward `sync_position`
		# every tick, so a body placed only by `global_position` walks back to
		# the origin over the warm-up frames.
		var spot := at.global_transform
		body.global_position = spot.origin
		body.sync_position = spot.origin
		body.sync_yaw = Bog.yaw_towards(-spot.basis.z)
		body.body_yaw = body.sync_yaw
		body.sync_velocity = Vector3.ZERO
		body.sync_grounded = true
		stood += 1
	return stood
