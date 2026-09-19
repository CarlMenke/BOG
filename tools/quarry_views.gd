extends Node3D
## Stand somewhere in Twin Quarry and look at it. Development tool, not shipped.
##
## `tools/preview_map.tscn` renders the eight spawn pads and a top-down, which
## is the right set for "are the pads standable" and the wrong set for "does
## this place look like anything". The views below are the ones a person would
## walk to: inside the tunnel, at each mouth, on a catwalk over the shaft, on
## each base's wall, and the long diagonal each team opens on.
##
## The camera is put at a Bog's **eye height** — 1.45 m, which is what the
## sightline scans use — rather than at a comfortable photographer's height, for
## the reason the whole tool exists: a map that reads at 3 m and not at 1.45 is
## a map nobody will ever see the good version of.
##
## Usage:
##   Godot --path . --resolution 1600x900 --script tools/snapshot.gd -- \
##       res://tools/quarry_views.tscn out.png 45 <view>
##
## Views: see `SHOTS`.

const MAP := "res://scenes/world/maps/quarry.tscn"
## A Bog's eye, off `Bog` rather than typed.
const EYE := 1.45

## Each shot as (where the camera stands, what it looks at, field of view). The
## `y` of each is measured from whatever the camera is standing on — 0 for the
## pit floor, 4 for a bench top, and so on — and `EYE` is added.
const SHOTS := {
	# Into the tunnel's south mouth, from where a Bog coming up the west lane
	# first sees it.
	"mouth_s": [Vector3(-17.8, 0.0, 2.0), Vector3(-17.8, 1.2, 14.0), 70.0],
	# Inside, at the bend, looking back out of the south leg.
	"adit_bend": [Vector3(-17.8, 0.0, 17.5), Vector3(-17.8, 1.2, 8.0), 70.0],
	# Inside, at the bend, looking out of the east leg.
	"adit_east": [Vector3(-18.3, 0.0, 17.8), Vector3(-6.0, 1.2, 17.8), 70.0],
	# Out at the east mouth, from the north band.
	"mouth_e": [Vector3(-3.0, 0.0, 17.8), Vector3(-14.0, 1.4, 17.8), 70.0],
	# On the north catwalk, half way over the hole, looking at the monolith.
	"catwalk": [Vector3(-6.0, 0.0, 5.0), Vector3(2.0, 4.0, 1.0), 72.0],
	# On the pit floor at the shaft's south-east lip, where the U card is.
	"lip": [Vector3(9.5, 0.0, -9.5), Vector3(-2.0, 2.0, 2.0), 75.0],
	# Team 1's base, from its own wall, looking out over the pit.
	"base1": [Vector3(-16.0, 4.0, -16.0), Vector3(2.0, 1.0, 2.0), 75.0],
	# Team 1's base, from the floor at the foot of its east ramp, looking in.
	"base1_foot": [Vector3(-2.0, 0.0, -22.5), Vector3(-17.0, 4.5, -22.5), 70.0],
	# Team 2's base, the same two, so the pair can be compared side by side.
	"base2": [Vector3(16.0, 4.0, 16.0), Vector3(-2.0, 1.0, -2.0), 75.0],
	"base2_foot": [Vector3(2.0, 0.0, 22.5), Vector3(17.0, 4.5, 22.5), 70.0],
	# Standing on the top terrace with the B card, looking down the map.
	"terrace": [Vector3(21.0, 4.5, -21.0), Vector3(0.0, 2.0, 2.0), 75.0],
	# Mid, on the floor between the shaft and the south band.
	"mid": [Vector3(0.0, 0.0, -12.0), Vector3(-6.0, 3.0, 8.0), 75.0],
	# On the spoil bench's top, over the tunnel, looking across the pit.
	"bench_top": [Vector3(-14.0, 4.5, 13.0), Vector3(6.0, 1.0, -6.0), 75.0],
	# The long one: from one base's wall toward the other, which is the line
	# the monolith and the two diagonal columns exist to close.
	#
	# **On the wall's top, at 5.8, not on the bench at 4.** At the bench height
	# the camera stood at (-12, 5.45), which is *inside* the 0.9 m wall — the
	# shot was the inside of a solid for as long as this tool has existed, and
	# the visuals pass only noticed because the wall grew a coloured band and
	# the frame turned blue. `BENCH_TOP + WALL_HEIGHT` is where a Bog perched on
	# the wall actually stands, which is what the comment always claimed.
	"diagonal": [Vector3(-11.95, 5.8, -16.0), Vector3(17.75, 4.0, 17.75), 60.0],

	# --- added by the visuals pass -------------------------------------------
	# Straight down the shaft from the south-west lip: the drop, the ledge, the
	# monolith's foot and the train on the bottom. The one shot that says how
	# far there is to fall.
	# **Not on the diagonal.** (-8.6, -8.6) is inside the "diagonal lip" column,
	# which spans -12.5 to -7.9 in both axes; the first version of this shot was
	# the inside of ten metres of rock. This stands on the strip of floor
	# between the hole's west lip and the west berm.
	"shaft": [Vector3(-8.4, 0.0, -3.0), Vector3(0.5, -13.0, 0.5), 78.0],
	# The skyline over the west rim, from the middle of the pit floor: the
	# plant, the conveyor, the crusher and the masts, which is everything the
	# visuals pass put above the cliff.
	"plant": [Vector3(-2.0, 0.0, 2.0), Vector3(-26.0, 15.0, 1.0), 62.0],
	# A player's opening frame: spawn pad 0, at eye height, facing the middle.
	"spawn": [Vector3(-3.5, 0.0, -17.0), Vector3(2.0, 2.0, 6.0), 75.0],
	# The foot of the west cliff, looking along it — the shot that judges the
	# drill ribs, the bench marks and the scree at the toe.
	"cliff": [Vector3(-20.0, 0.0, -2.0), Vector3(-23.0, 6.0, 14.0), 70.0],
	# Team 1's base seen from the pit floor at the far end of the west lane,
	# which is the range team identity has to read at.
	"base1_far": [Vector3(-2.0, 0.0, -2.0), Vector3(-18.0, 5.4, -18.0), 62.0],
}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var view := "mid"
	if args.size() >= 4:
		view = String(args[3])
	if not SHOTS.has(view):
		push_error("quarry_views: no view %s; have %s" % [view, SHOTS.keys()])
		view = "mid"
	var shot: Array = SHOTS[view]

	var packed := load(MAP) as PackedScene
	if packed == null:
		push_error("quarry_views: could not load %s" % MAP)
		return
	add_child(packed.instantiate())

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
	print("quarry_views: %s from %v looking at %v" % [view, camera.position, aim])
