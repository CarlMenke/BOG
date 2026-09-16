class_name QuarryMap
extends StaticMap
## Twin Quarry — a worked-out stone pit with a cut bench in opposite corners,
## built in code from layout tables the way Kopje Crossing, Lantern Wharf and
## Halcyon Wake are (D-042, D-056, D-057).
##
## This is the first map designed for **Capture B·O·G** rather than adapted to
## it (D-082), and the brief decided the shape:
##
##   * **Each team's base is a storey up.** The base pad sits on a 4 m cut bench
##     in its own corner of the pit. Four metres is over every jump in the Bog's
##     kit — the one-tick dive reaches 4.23 m of rise but only off a take-off
##     edge, and from flat ground `parkour_report` allows 3.5 — so the face of
##     the bench is a wall, not a step.
##   * **Two ways up, and they are the haul ramps.** A 25 degree ramp climbs to
##     each of the bench's two open faces. The Bog has no step-up, so a ramp is
##     the only climbable slope there is (`floor_max_angle` is 52 degrees) and
##     stairs on this map would be the yacht's trick for nothing.
##   * **A low wall round the pad, with a few doorways.** 1.8 m of cut stone: a
##     Bog is 1.55 m and its eyes are at 1.45, so you cannot see over it and you
##     cannot jump it either (the jump reaches 1.69). You can *leap* onto it,
##     which is the defender's perch and is meant to be. Three gaps: the head of
##     each ramp, and one drop port that is an exit and a throwing slot, because
##     the 4 m back down is one way.
##
## **The symmetry is rotational, not mirrored.** Team 2's half is Team 1's half
## turned 180 degrees about the origin — every coordinate in the tables below is
## written once and placed again negated. A map mirrored across a line puts both
## bases on that line and hands them a lane straight down it that no amount of
## cover closes without also closing the flag off; turning the layout instead
## puts the bases on a diagonal, where one rock in the middle closes it. It is
## as fair — the two halves are congruent — and it costs nothing but a
## handedness the Bog does not have. What it does cost is the middle: see the
## Stack, under `COLUMNS`.
##
## Four kinds of stone stand in the pit, and each has one job. **The two you can
## climb are the pale ochre cut stone and the two you cannot are dark grey raw
## rock**, which is the only thing telling them apart under a flat sky:
##
##   kerbs       1.2 m. Low cover, and the step up — a hop from the floor. The
##               spoil rocks are kerbs too: see `SPOIL_ROCKS`.
##   blocks      3.0 m. Hard cover, climbable off a kerb (1.8 m of rise, and a
##               leap lifts 2.30) and out of reach of anything from flat ground.
##               It was 2.6 until the pit was widened: at 48 m across, the extra
##               40 cm is what stops a Bog on a bench corner seeing clean over
##               every block on the map.
##   columns     10.2 m of unquarried rock. What cuts the long lines, and out of
##               reach of every jump the Bog has — `off_limits`, and the report
##               fails the build if one can be stood on.
##   the rim     11 m of cliff on all four sides, terraced away above that. The
##               edge of the map, and `off_limits` for the same reason.
##
## Build order is the other built maps' and the rule is the same: everything
## added before `super()` is swept into world-space collision, everything after
## is dressing — the puddles, the derricks over the rim, the kerb paint and the
## two work lamps. The spoil rocks are the one piece of the *kit* that lives
## above the line, because a rock that looks like cover has to be cover; see
## `_build_rocks`. Nothing here is random, so every peer builds the same pit by
## construction rather than by a shared seed.

# ---------------------------------------------------------------- the table ---

## Half the pit's width, to the rim's inner face. The floor runs to `FLOOR_EDGE`
## so the rim has something to stand on.
const HALF := 24.0
const RIM_THICKNESS := 3.0
const FLOOR_EDGE := HALF + RIM_THICKNESS
## How thick the pit floor is. It used to be a bare `-0.6` typed into the three
## places that needed it, and that is exactly how the shaft came to be built
## through it: the number that says where the floor's *underside* is, is the
## number the shaft rock has to stop at, and a literal cannot say so. Nothing
## about the playable surface depends on it — the floor's top is y = 0 either
## way — so this is a name for a seam, not a measurement anybody stands on.
const FLOOR_THICK := 0.6
## The rim's top. Nothing reaches it and nothing is meant to; it is the skyline
## and the reason the pit reads as a hole in the ground rather than a yard.
const RIM_TOP := 11.0
## The benches the cliff climbs in behind that, as (how far out from the rim's
## inner face this tier starts, how high it goes). The first is the wall of the
## pit itself; the rest are only ever seen over it.
const RIM_TIERS: Array[Vector2] = [
	Vector2(0.0, RIM_TOP), Vector2(2.4, 15.0), Vector2(5.6, 18.6),
]

## The shaft in the middle of the pit: the next bench down, and the one thing on
## this map that kills you (D-089).
##
## It stands exactly where the Stack did, and it is the Stack's opposite in every
## way that matters. That rock was load-bearing — under a rotational layout every
## spawn pad's line to its antipode runs through the origin, and one rock at the
## origin closed all of them plus base to base. A hole closes nothing: a straight
## line between two pairs of eyes 1.45 m over a flat floor does not care what is
## underneath it. So the sightlines the Stack was holding are now held by the
## blocks round the shaft's lip, and the two that cannot be — bench to bench —
## are open, and the limits say so.
const HOLE_HALF := 6.5
## How far down you can see before the fog and the dark take it. The floor of the
## lower bench is modelled, because a shaft that ends in nothing reads as a
## texture error rather than as a quarry, but nobody ever stands on it:
## `void_height` is -10, so a Bog is dead six metres before it arrives.
const HOLE_FLOOR := -16.0
## A ledge part way down, so the drop reads as *quarried* — benches and a haul
## road, the same thing the pit above it is — rather than as a lift shaft.
const HOLE_LEDGE := -5.5
const HOLE_LEDGE_WIDTH := 1.6
## How wide the ledge's tread is — the step the lower face is set back by, as
## opposed to `HOLE_LEDGE_WIDTH`, which is how far the *upper* face stands out
## past the hole's edge. It was a bare 0.9 typed four times into `_build_shaft`,
## which is how the four runs ended up overlapping at the corners: a number that
## has to be subtracted at both ends of two of them cannot be a literal at one
## end of all four.
const LEDGE_TREAD := 0.9

## The bench each base stands on: a solid corner of cut stone, top at
## `BENCH_TOP`, from the rim's inner faces in to `BENCH_INNER` — 12.5 m square.
const BENCH_TOP := 4.0
const BENCH_INNER := 11.5
## Where the base marker sits: the middle of the bench, on its floor.
const BASE_AT := Vector2(-17.75, -17.75)

## The wall round the pad. 1.8 m so a standing Bog cannot see over it and the
## 1.69 m jump cannot clear it; 0.9 m thick so its top is a landing a Bog fits
## on, which is what makes the leap onto it worth having.
const WALL_HEIGHT := 1.8
const WALL_THICK := 0.9

## The two haul ramps, as the span across the ramp and where it starts and ends
## along its own axis. Both climb `BENCH_TOP` over 11.5 m, which is 19.2 degrees.
##
##   axis   "x" for the ramp that climbs along x (its head is the bench's east
##          face), "z" for the one that climbs along z (the south face).
##   span   the ramp's two edges across its axis — also the doorway's width in
##          the wall it arrives at.
##   foot   where it meets the pit floor; `head` where it meets the bench.
##
## Both ramps run flush against the rim rather than a little off it. A 1.5 m gap
## behind a ramp is a slot a Bog gets stuck in, and four of them end to end are a
## lane down the pit's own edge that nothing breaks.
const RAMP_WIDTH := 3.0
const RAMPS: Array[Dictionary] = [
	{"label": "east ramp", "axis": "x", "span": Vector2(-24.0, -21.0),
		"foot": 0.0, "head": -BENCH_INNER},
	{"label": "south ramp", "axis": "z", "span": Vector2(-24.0, -21.0),
		"foot": 0.0, "head": -BENCH_INNER},
]
## How much wider than the ramp the doorway in the wall is, each side. A doorway
## exactly as wide as the ramp is one a Bog clips the jamb of at a run.
const DOOR_MARGIN := 0.2
## The drop port: the gap in the east wall that is not a way in. A Bog can walk
## out of it and fall four metres, and throw through it standing still, and
## nothing can come up it.
const PORT := Vector2(-15.5, -13.9)

## Landings on the bench, and how far one is kept from the wall and from a pad.
const TILE := 2.5
const TILE_RADIUS := 1.1
const TILE_CLEAR := 0.6
## Stair-and-ramp landings sit this far over the slope, so the report's capsule
## at the record is not buried in the rock uphill of it (D-057's number, and the
## same 25-ish degrees).
const RAMP_LIFT := 0.08

## The stone standing in the pit, written once for the half at negative
## coordinates and placed again turned 180 degrees about the origin. `at` is the
## centre on (x, z) and `size` the footprint; the height comes from the kind.
##
## **The Stack is at the origin, and it has to be.** Under a rotational layout
## every spawn pad has an exact antipode on the other team, and the line between
## a point and its antipode passes through the origin — so an open middle is
## eight guaranteed spawn-to-spawn sightlines and no amount of cover anywhere
## else closes them. Thirteen metres of unquarried rock in the centre closes
## all eight at once, and both diagonals with them. It was nine while the pit
## was 42 m across; widening the pit to 48 m opened a base-to-base line round
## the side of it, because the thing a rock in the middle has to block is a
## line between two corners 50 m apart and that line swings wide. It is also the map's landmark:
## the one thing visible from everywhere, which is what a pit of same-coloured
## stone otherwise has none of.
##
## That is why **G is not at the middle**. It stands on the other diagonal —
## the perpendicular bisector of the line between the bases — which is the only
## place a single card can be exactly as far from one base as from the other.
## U and B are a rotational pair instead: each is near one team and its partner
## is the same distance from the other, so the pair is fair even though neither
## card is.
##
## Columns are 10.2 m. Not 7.6, which is where they started: the wall round a
## base is a landing 5.8 m up, and the one-tick dive lifts 4.23 m, so anything
## under 10.03 m is a column somebody stands on top of and reads the whole pit
## from. `parkour_report` found that, which is what it is for.
const COLUMN_TOP := 10.2
const COLUMNS: Array[Dictionary] = [
	# Eight metres across the map's axis rather than four, and that width is doing
	# a specific job: **all four spawn-to-spawn lines now cross these two rocks**
	# rather than the blocks on the shaft's lip. Pad-to-pad is a hard check, so
	# something has to close it; putting that duty out here on a pair of rocks the
	# map already had frees the hole's rim to be placed by eye (D-091).
	{"label": "axis west", "at": Vector2(-15.5, 0.0), "size": Vector2(4.0, 8.0)},
	{"label": "axis north", "at": Vector2(0.0, -15.5), "size": Vector2(8.0, 4.0)},
	# There used to be a pair here, on the diagonal between the bases, closing
	# base to base either side of the Stack. Both are gone with it (D-089): the
	# shaft's lip runs from the hole's edge out to 9.7 m and the bench begins at
	# 11.5, so there is no longer any room on that diagonal to stand a column in,
	# and nothing left for it to close — bench sees bench across the hole now, by
	# the decision that put the hole there.
	# Flush against the rim, like the ramps and for the same reason: anything
	# standing a metre and a half off the cliff leaves a slot behind it, and a
	# slot that runs the length of the pit is a 34 m lane as well as somewhere
	# to get wedged.
	{"label": "flank west", "at": Vector2(-21.5, 9.0), "size": Vector2(5.0, 5.0)},
	{"label": "flank north", "at": Vector2(9.0, -21.5), "size": Vector2(5.0, 5.0)},
]

## Hard cover: 2.6 m, climbable off a kerb and nothing else.
## The four blocks on the shaft's lip, and **these are not a mirrored table**.
##
## Every other piece of stone on this map is written once and placed twice by
## `turned()`, which is what keeps the two halves congruent — and round a hole it
## is exactly the wrong tool. Each of the four spawn-to-spawn lines needs *one*
## blocker somewhere along it, not one at each end, so a mirrored table builds
## eight blocks to do the work of four and then jams them against each other and
## against the cover that was already there. It did: ten blocks round the rim,
## two pairs of them interpenetrating.
##
## So these four are hand-placed, one on each side of the hole, each sitting
## where one of the four lines crosses the lip. The halves are no longer
## congruent here and that is the trade: a hazard you can walk into from most of
## its perimeter is worth more than a symmetry nobody can see from inside the map
## (D-091).
##
## They are **1.85 m**, which is the one height that needs nothing else beside it.
## 3.0 m is a dive from flat ground, so it would have to carry a kerb to climb
## from — four more objects on a rim meant to be nearly bare. Putting them out of
## reach instead means clearing a dive off the 3 m cover nearby, which is 7.2 m,
## and a 7 m tower on each edge is a wall round the hole. 1.85 m is under
## `GROUND_LEAP`, so a Bog can leap straight onto one from the floor and nothing
## is stranded; and it is over the 1.45 m eye, so it still breaks a standing
## line. A quarry puts a low berm round a shaft for the same reason.
const LIP_TOP := 1.85
const LIP_BLOCKS: Array[Dictionary] = [
	{"label": "lip north", "at": Vector2(2.9, -8.2), "size": Vector2(3.4, 3.0)},
	{"label": "lip south", "at": Vector2(-3.6, 8.2), "size": Vector2(2.8, 3.0)},
	{"label": "lip west", "at": Vector2(-8.2, 3.3), "size": Vector2(3.0, 3.6)},
	{"label": "lip east", "at": Vector2(8.2, -0.4), "size": Vector2(3.0, 2.6)},
]

## Hard cover, and **every one of them needs a kerb beside it**. From flat ground
## 3.0 m is only a one-tick dive, and the reachability walk refuses to count
## those, so a block with no step is a block the report calls stranded.
const BLOCK_TOP := 3.0
const BLOCKS: Array[Dictionary] = [
	{"label": "approach west", "at": Vector2(-12.5, -6.5), "size": Vector2(3.0, 3.0)},
	{"label": "approach north", "at": Vector2(-6.5, -12.5), "size": Vector2(3.0, 3.0)},
	# Three that used to be 10 m columns. At that height and at this spacing the
	# pit was a canyon maze: the third-person camera spent the whole match
	# against a wall, and a Bog could not see its own feet from a spawn pad.
	# Three metres blocks a standing Bog's eyes exactly as well — the sightline
	# scan runs at 1.45 m — and lets the camera, and the player, up over it.
	{"label": "quarter west", "at": Vector2(-6.5, 12.5), "size": Vector2(4.0, 4.0)},
	{"label": "quarter north", "at": Vector2(12.5, -6.5), "size": Vector2(4.0, 4.0)},
	{"label": "outer west", "at": Vector2(-13.5, 13.5), "size": Vector2(4.0, 4.0)},
	# Across the strip in front of the far team's bench, which is the one lane a
	# 48 m pit leaves open along its own edge.
	{"label": "rim face", "at": Vector2(-13.0, 19.75), "size": Vector2(3.0, 3.0)},
	{"label": "letter shoulder", "at": Vector2(-17.5, 6.5), "size": Vector2(3.0, 3.0)},
	{"label": "letter pocket", "at": Vector2(-8.0, 16.5), "size": Vector2(3.0, 3.0)},
	{"label": "rim shoulder", "at": Vector2(-19.0, 16.0), "size": Vector2(3.0, 3.0)},
]

## Low cover and the step onto a block. Each is laid flush against the block it
## is a step onto — a kerb with a metre of daylight beside a block is a slot a
## Bog gets stuck in, and flush it is a staircase.
const KERB_TOP := 1.2
const KERBS: Array[Dictionary] = [
	{"label": "step west", "at": Vector2(-10.0, -6.5), "size": Vector2(2.0, 2.0)},
	{"label": "step north", "at": Vector2(-6.5, -10.0), "size": Vector2(2.0, 2.0)},
	{"label": "quarter step west", "at": Vector2(-6.5, 9.5), "size": Vector2(2.0, 2.0)},
	{"label": "quarter step north", "at": Vector2(9.5, -6.5), "size": Vector2(2.0, 2.0)},
	{"label": "outer step", "at": Vector2(-16.5, 13.5), "size": Vector2(2.0, 2.0)},
	{"label": "rim face step", "at": Vector2(-13.0, 17.25), "size": Vector2(2.0, 2.0)},
	{"label": "letter step", "at": Vector2(-17.5, 9.0), "size": Vector2(2.0, 2.0)},
	{"label": "pocket step", "at": Vector2(-10.5, 16.5), "size": Vector2(2.0, 2.0)},
	{"label": "rim step", "at": Vector2(-19.0, 13.5), "size": Vector2(2.0, 2.0)},
	# The one that is not a step: low cover out on its own in the far corner,
	# on the run between U's half of the map and the far base.
	{"label": "corner step", "at": Vector2(-16.0, 20.5), "size": Vector2(2.0, 2.0)},
]

## The letter home points, so the layout and the scene cannot disagree about
## where they are. G in the chamber at the middle, U and B on the other diagonal
## — the one the four heart columns leave open — each exactly as far from one
## base as from the other, which is only true because the bases sit on the main
## diagonal.
const LETTER_POINTS: Array[Vector2] = [
	Vector2(-9.5, 9.5), Vector2(11.5, -3.5), Vector2(-11.5, 3.5),
]

# ----------------------------------------------------------------- colours ---

## Limestone, cut and weathered. The pit is one rock and the shades are what the
## working did to it: a sawn face is pale and clean, a floor is dusted and
## stained, and a column nobody has touched is darker and greener at the top.
## A sawn face is pale ochre and a column nobody has touched is grey-brown, and
## the gap between them is the whole of the map's readability: under a flat sky
## there are no shadows to tell one lump of stone from another, so the *kind* of
## stone has to. Cut stone is what you climb and hide behind; raw stone is what
## you cannot.
const STONE_CUT := Color(0.66, 0.60, 0.48)
const STONE_BENCH := Color(0.60, 0.55, 0.44)
const STONE_RIM := Color(0.48, 0.45, 0.39)
const STONE_RAW := Color(0.47, 0.45, 0.41)
## The pit floor. Gravel is not one colour and the first pass treated it as one:
## a two-stop noise ramp reads as damp cardboard at any distance a Bog is
## actually standing. `_gravel_images()` draws individual stones instead, so this
## is only the tint over the top of them.
const FLOOR_GRAVEL := Color(0.62, 0.59, 0.53)
const HAUL_ROAD := Color(0.31, 0.29, 0.27)
const STEEL := Color(0.34, 0.34, 0.36)
const RUST := Color(0.48, 0.28, 0.16)
# Pale, not deep. A flat sky has nothing bright in it to reflect, so water dark
# enough to read as deep reads as a hole cut in the floor instead.
const PUDDLE := Color(0.40, 0.44, 0.47)
const LAMP_WARM := Color(1.0, 0.86, 0.62)

# ------------------------------------------------------------------- props ---

## The Stylized Nature MegaKit models the dressing is drawn from, and the one
## seed every random draw in it comes out of. Fixed, so every peer scatters the
## same weeds in the same cracks — the props change nothing about the fight, but
## a map that looks different on two machines is a map two people cannot talk
## about.
const PROP_SEED := 0x51A7B0
const RUBBLE: PackedStringArray = ["Pebble_Round_1", "Pebble_Round_2",
	"Pebble_Round_3", "Pebble_Round_4", "Pebble_Round_5", "Pebble_Square_1",
	"Pebble_Square_2", "Pebble_Square_3", "Pebble_Square_4", "Pebble_Square_6"]
## The three the spoil rocks are cut from, and the one list here that is not
## scattered: a boulder is the only kit model on this map that ends up solid, so
## `SPOIL_ROCKS` picks from it by hand rather than by a draw.
const BOULDERS: PackedStringArray = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"]
const WEEDS: PackedStringArray = ["Grass_Common_Short", "Grass_Common_Tall",
	"Grass_Wispy_Short", "Grass_Wispy_Tall", "Clover_1", "Clover_2", "Fern_1",
	"Plant_1", "Plant_7"]
const BLOOMS: PackedStringArray = ["Bush_Common", "Bush_Common_Flowers",
	"Flower_3_Group", "Flower_4_Group", "Plant_1_Big", "Plant_7_Big"]
const SNAGS: PackedStringArray = ["DeadTree_1", "DeadTree_2", "DeadTree_3",
	"DeadTree_4", "DeadTree_5"]

## How the apron round a face is walked, and how far out of it a prop sits. Near
## is against the stone; far is about a Bog's width off it, which is as far as
## debris reads as having come off that face rather than been dropped.
const APRON_STRIDE := 1.1
const APRON_NEAR := 0.15
const APRON_FAR := 0.85

## Scales, all taken off `PropScatter.DENSE_LAYERS`, which measured them against
## the Bog: `Grass_Common_Tall` is 1.87 m at scale 1 and the Bog is 1.81, so
## grass at 1.0 is a swamp that hides a crouched player.
const RUBBLE_SCALE := Vector2(0.7, 1.6)
const WEED_SCALE := Vector2(0.28, 0.55)
const BLOOM_SCALE := Vector2(0.30, 0.62)
const SNAG_SCALE := Vector2(0.45, 0.85)

## Where the coarse waste was tipped: four rocks banked into the corner the
## layout leaves empty, written once and turned like everything else. **These
## are the only props on the map that are solid**, and the reason they are a
## table rather than a scatter is that they are solid — see `_build_rocks`.
##
## `model` indexes `BOULDERS`, `yaw` turns the rock so four copies of three
## meshes do not read as three meshes. Every one of them is off both haul ramps,
## out of every doorway, more than ten metres from any spawn pad, and more than
## two metres from the centre of any other landing, which is what keeps a Bog's
## capsule fitting on the kerb next door.
const SPOIL_ROCKS: Array[Dictionary] = [
	{"label": "spoil deep", "at": Vector2(-21.6, 20.0), "model": 0, "yaw": 0.4},
	{"label": "spoil corner", "at": Vector2(-21.6, 22.6), "model": 1, "yaw": 2.1},
	{"label": "spoil bank", "at": Vector2(-18.8, 22.6), "model": 2, "yaw": 3.9},
	{"label": "spoil rim", "at": Vector2(-14.8, 22.8), "model": 0, "yaw": 5.2},
]
## How wide a spoil rock is across its footprint, and the landing radius its top
## is credited with. The radius is well inside the footprint on purpose: the last
## half metre of a rock is the slope down its side, not somewhere to stand.
const ROCK_SPAN := 2.6
const ROCK_LANDING := 0.7
## The chips round each rock: how many, and how far they spread. Passable, like
## every other pebble on the map.
const ROCK_SKIRT := 6
const ROCK_SKIRT_SPREAD := 1.2

## How many dead trees stand on the rim's first terrace.
const SNAG_COUNT := 14

## Standing water, shared by the puddle quads and the bushes that ring them.
## The one at (8.5, 8.5) used to sit at (8.5, 8.5) with its edge landing exactly
## on the shaft lip at 6.5 — water ending flush with a sixteen-metre drop, which
## reads as a mistake whether or not it flickers (it did not; it is a decal with
## nothing coplanar under it). Moved out where the floor it lies on continues
## past it.
const PUDDLES: Array[Vector2] = [Vector2(-10.0, 19.5), Vector2(19.0, -10.0),
	Vector2(-20.0, -5.0), Vector2(20.0, 5.0), Vector2(11.5, 11.5)]

## The derricks outside the rim: the skyline, and the only thing on the map that
## says what the hole is for. Two of them, on the diagonal the bases are not on.
const DERRICK_AT := Vector2(-28.5, 28.5)
const DERRICK_HEIGHT := 21.0

# ------------------------------------------------------------------- state ---

var columns: int = 0
var blocks: int = 0
var kerbs: int = 0
var rocks: int = 0

var _floor_st: SurfaceTool
## One per team: a base is built out of its own team's brick, so the two benches
## cannot share a mesh the way the rest of the stone does.
var _bench_st: Array[SurfaceTool] = []
var _carved_st: SurfaceTool
var _rim_st: SurfaceTool
var _raw_st: SurfaceTool
var _road_st: SurfaceTool

var _stone_material: StandardMaterial3D
var _carved_material: StandardMaterial3D
var _brick_material: StandardMaterial3D
var _floor_material: StandardMaterial3D
var _road_material: StandardMaterial3D
var _steel_material: StandardMaterial3D
var _rust_material: StandardMaterial3D
var _water_material: StandardMaterial3D
var _lamp_material: StandardMaterial3D
var _rubble_material: StandardMaterial3D
var _spoil_material: StandardMaterial3D


func _ready() -> void:
	var started := Time.get_ticks_msec()
	_build_materials()

	_floor_st = _begin()
	_bench_st = [_begin(), _begin()]
	_carved_st = _begin()
	_rim_st = _begin()
	_raw_st = _begin()
	_road_st = _begin()

	_build_floor()
	_build_shaft()
	_build_rim()
	_build_benches()
	_build_ramps()
	_build_pit()

	var solid := _group("Quarry")
	_commit(solid, "Floor", _floor_st, _floor_material, FLOOR_GRAVEL)
	for team: int in 2:
		_commit(solid, "Base%d" % (team + 1), _bench_st[team], _brick_material,
			brick_for_team(team))
	_commit(solid, "CarvedStone", _carved_st, _carved_material, STONE_CUT)
	_commit(solid, "Rim", _rim_st, _stone_material, STONE_RIM)
	_commit(solid, "RawStone", _raw_st, _stone_material, STONE_RAW)
	_commit(solid, "HaulRoad", _road_st, _road_material, HAUL_ROAD)
	# Above `super()` on purpose, and the one kit model that is: see below.
	_build_rocks(solid)

	_plan_landings()

	print("%s: %d columns, %d blocks, %d kerbs, %d rocks, %d landings, %d off limits in %d ms" % [
		name, columns, blocks, kerbs, rocks, platforms.size(), off_limits.size(),
		Time.get_ticks_msec() - started])

	# Everything above this line becomes collision. Everything below it does not.
	super()

	var dressing := _group("Dressing")
	_build_props(dressing)
	_build_puddles(dressing)
	_build_kerb_paint(dressing)
	_build_derricks(dressing)
	_build_lamps(dressing)


# ------------------------------------------------------------------ layout ---

## Both halves of a table entry: the one written, and the same point turned 180
## degrees about the origin, unless it stands on the origin.
static func turned(at: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = [at]
	if at.length_squared() > 0.0001:
		out.append(-at)
	return out


## Which team's half a point is in: 1 for the half written in the tables (the
## negative corner), 2 for its turn. Used only for labels.
static func half_of(at: Vector2) -> String:
	return "1" if at.x + at.y < 0.0 else "2"


## The same thing as an index: 0 for the half the tables are written for, which
## is Team 1's, and 1 for its turn. `Bases` in the scene is in team order and its
## first child is the negative corner, so these agree by construction.
static func team_of(at: Vector2) -> int:
	return 0 if at.x + at.y < 0.0 else 1


## A team's brick, derived from the team's own colour rather than picked to look
## like it. `Nameplate.TEAM_COLOURS` is what the plates, the kill feed, the
## scoreboard and `CaptureBase`'s ring on this very bench are all drawn in, so a
## base painted from anywhere else is a base that drifts out of step with them
## the first time that table is edited.
##
## The UI colours are bright because they have to read at a glance on a dark
## panel; brick has to read under an overcast at forty metres without turning the
## pit into a toy. So the team colour is darkened and pulled a little toward
## fired clay, which lands Team 1 on a Staffordshire blue and Team 2 on a plain
## red — both unmistakably their own team, neither of them a sweet wrapper.
static func brick_for_team(team: int) -> Color:
	return Nameplate.colour_for_team(team).darkened(0.40).lerp(Color(0.34, 0.22, 0.17), 0.30)


## The two factors a half needs, and the one thing about this file that is easy
## to get wrong.
##
## `sign` turns a *magnitude* into a coordinate on this half: `sign * HALF` is
## the rim's inner face, -21 or +21. `flip` turns a *table value*, which is
## already written negative, into one on this half: it is 1 on the half the
## tables were written for and -1 on its turn. Using `sign` on a table value
## puts the ramps on the wrong side of the map, which is exactly what it did.
static func factors(at: Vector2) -> Vector2:
	var sign := signf(at.x)
	return Vector2(sign, -sign)


## The pit floor, and it stops at the rim's inner face rather than running under
## it. A floor that ran on under the cliff would be standable ground the
## sightline scan could find *inside* the rock, with nothing between two such
## points to stop a ray — which is how this map first measured a 46 m sightline
## through solid stone.
func _build_floor() -> void:
	# Four slabs round the shaft rather than one across the pit. A picture frame,
	# so the hole in the middle is a hole in the *collision* and not a hole
	# painted on a floor a Bog walks over.
	#
	# **The four are trimmed against each other, and that is the pattern.** North
	# and south run the full width; east and west are cut back to the band
	# between them. Four slabs each running full width would double-cover the
	# corners, and two coplanar tops at y = 0 is not a thicker floor, it is a
	# depth-buffer tie — which is the failure `_build_shaft` had against *this*
	# frame and still had against itself round the ledge (D-089, and the entry
	# that carries this fix).
	var h := HOLE_HALF
	var base := -FLOOR_THICK
	_slab(_floor_st, Vector2(-HALF, -HALF), Vector2(HALF, -h), base, 0.0)
	_slab(_floor_st, Vector2(-HALF, h), Vector2(HALF, HALF), base, 0.0)
	_slab(_floor_st, Vector2(-HALF, -h), Vector2(-h, h), base, 0.0)
	_slab(_floor_st, Vector2(h, -h), Vector2(HALF, h), base, 0.0)


## The shaft: four walls down to a floor nobody reaches, with a bench ledge
## running round it part way so the drop reads as a worked quarry rather than as
## a lift shaft. All of it collision — a spear into the shaft wall stops there,
## and a Bog cannot walk out through the side of the hole.
##
## **Two solids may not share a face plane, and both of the seams below were one
## when this was first built.** A depth buffer has no opinion about which of two
## surfaces at exactly the same depth is in front, so it picks per fragment, out
## of float noise that changes with the camera — the striping the shaft was
## reported for. Worse here than usual because the two surfaces were not even the
## same rock: the floor is gravel and the shaft is dressed rim stone (D-089), so
## the fight was between two visibly different textures.
##
##   * **The apron.** The upper slabs used to run from the hole edge out to
##     `HOLE_LEDGE_WIDTH` beyond it *and up to y = 0* — and `_build_floor` has
##     already covered every metre from the hole edge outward at that same y = 0.
##     A 1.6 m ring of the pit floor was therefore two tops in one plane, and the
##     stone usually won, which is why the hole looked as though it had a stone
##     apron nobody put there. The rock now stops at the floor's underside, so
##     the floor alone owns y = 0 and owns the top `FLOOR_THICK` of the wall with
##     it. Nothing moves: the same rock is in the same place, 0.6 m of it is
##     simply no longer built inside the floor that was already there.
##   * **The ledge corners.** The lower slabs were written as four full-width
##     runs, so each corner of the ledge was covered by two of them and the ledge
##     top at `HOLE_LEDGE` was two coplanar faces, 0.9 m square, at all four
##     corners. Same material, so it read as shimmer rather than as striping, but
##     it is the same tie. They are trimmed against each other now, exactly the
##     way the floor frame above them is.
##
## What is left is a real hole: open from y = 0 down, walls solid so a spear
## stops in them and nobody walks out through the side, and a floor at
## `HOLE_FLOOR` that nobody reaches because `void_height` is -10.
func _build_shaft() -> void:
	var h := HOLE_HALF
	var l := h + HOLE_LEDGE_WIDTH
	# The upper face, from the floor's underside down to the ledge, cut back so
	# the ledge stands proud of it. Four slabs; north and south run the full
	# width and east and west are trimmed to the band between them, so the
	# corners are covered once.
	for side: int in 4:
		var lo := Vector2(-l, -l) if side < 2 else Vector2(-l, -h)
		var hi := Vector2(l, -h) if side < 2 else Vector2(-h, h)
		if side == 1:
			lo = Vector2(-l, h); hi = Vector2(l, l)
		elif side == 3:
			lo = Vector2(h, -h); hi = Vector2(l, h)
		# The rock between the pit floor and the ledge is solid, so the ledge is
		# a step in a face rather than a shelf on a pole.
		_slab(_rim_st, lo, hi, HOLE_LEDGE, -FLOOR_THICK)
	# The lower face, from the ledge down to the floor of the bench below. Same
	# trimming, and it is the whole of the ledge-corner fix: the two runs that
	# used to span `-h` to `h` now stop `LEDGE_TREAD` short at each end, which is
	# precisely where the other two already are.
	var t := LEDGE_TREAD
	for side: int in 4:
		var lo := Vector2(-h, -h) if side < 2 else Vector2(-h, -h + t)
		var hi := Vector2(h, -h + t) if side < 2 else Vector2(-h + t, h - t)
		if side == 1:
			lo = Vector2(-h, h - t); hi = Vector2(h, h)
		elif side == 3:
			lo = Vector2(h - t, -h + t); hi = Vector2(h, h - t)
		_slab(_rim_st, lo, hi, HOLE_FLOOR, HOLE_LEDGE)
	# And the floor of it, far below the height a fall has already killed at. Its
	# top is at `HOLE_FLOOR` and the four walls *stand on* that — they start
	# there rather than running through it — so the two meet along an edge and
	# not in a plane, which is the same rule as everything above.
	_slab(_floor_st, Vector2(-h, -h), Vector2(h, h), HOLE_FLOOR - FLOOR_THICK, HOLE_FLOOR)


## The cliff on all four sides. Built as four overlapping slabs so the corners
## are solid rock rather than four edges meeting on a line, and started below
## the floor so there is no seam along the bottom of it.
##
## The terracing is all **above** `RIM_TOP` and stepped *outward*, so from
## inside the pit the wall is one clean eleven-metre face and the benches behind
## it climb away against the sky. Stepping it inward instead — which is what a
## worked quarry actually looks like — would put a ledge somewhere in the
## middle of that face, and a ledge is a perch: the report would then have to
## prove nothing reaches it, and a 2.6 m block anywhere near the wall would.
func _build_rim() -> void:
	var out := FLOOR_EDGE
	for tier: int in RIM_TIERS.size():
		var step: Vector2 = RIM_TIERS[tier]
		var inner := HALF + step.x
		var top := step.y
		var base := -FLOOR_THICK if tier == 0 else float(RIM_TIERS[tier - 1].y)
		var far := out + step.x
		_slab(_rim_st, Vector2(-far, -far), Vector2(far, -inner), base, top)
		_slab(_rim_st, Vector2(-far, inner), Vector2(far, far), base, top)
		_slab(_rim_st, Vector2(-far, -inner), Vector2(-inner, inner), base, top)
		_slab(_rim_st, Vector2(inner, -inner), Vector2(far, inner), base, top)
	# Four tops, one per side, so the report has something to refuse to let
	# anybody stand on. The rim is 11 m and nothing comes near it, but a map
	# that does not say so is a map where a later column could.
	var mid := (HALF + out) * 0.5
	var names := ["north", "south", "west", "east"]
	var spots := [Vector2(0.0, -mid), Vector2(0.0, mid), Vector2(-mid, 0.0), Vector2(mid, 0.0)]
	for i: int in 4:
		var at: Vector2 = spots[i]
		off_limits.append(Platform.new(Vector3(at.x, RIM_TOP, at.y),
			RIM_THICKNESS * 0.5 - 0.15, "rim", "rim %s" % names[i]))


## One bench per team: a solid corner of cut stone from the rim's inner faces in
## to `BENCH_INNER`, and the wall round the pad on top of it.
func _build_benches() -> void:
	for at: Vector2 in turned(BASE_AT):
		var sign := factors(at).x
		var outer := sign * HALF
		var inner := sign * BENCH_INNER
		var st: SurfaceTool = _bench_st[team_of(at)]
		_slab(st, Vector2(minf(outer, inner), minf(outer, inner)),
			Vector2(maxf(outer, inner), maxf(outer, inner)), 0.0, BENCH_TOP)
		_build_wall(at, st)


## The wall round one pad: two runs of it, on the bench's two open faces, with
## the ramp doorways and the drop port cut out of them.
##
## The other two faces of the bench are the rim, which is seven metres taller
## than any wall would be.
func _build_wall(at: Vector2, st: SurfaceTool) -> void:
	var pair := factors(at)
	var sign := pair.x
	var flip := pair.y
	var inner := sign * BENCH_INNER
	var back := sign * HALF
	# Inward from the bench's inner face, which is toward the back corner.
	var face := inner + sign * WALL_THICK * 0.5      # the wall's centreline
	var top := BENCH_TOP + WALL_HEIGHT
	var side := half_of(at)

	for entry: Dictionary in RAMPS:
		var axis := String(entry["axis"])
		var span: Vector2 = entry["span"]
		var gaps: Array[Vector2] = [Vector2(flip * span.y - DOOR_MARGIN,
			flip * span.x + DOOR_MARGIN)]
		if axis == "x":
			gaps.append(Vector2(flip * PORT.y, flip * PORT.x))
		# Runs along the wall, from the back corner to the inner corner, with
		# every gap taken out of them in order.
		var from := back
		var to := inner
		var cuts: Array[Vector2] = []
		for gap: Vector2 in gaps:
			cuts.append(Vector2(minf(gap.x, gap.y), maxf(gap.x, gap.y)))
		cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var runs: Array[Vector2] = []
		var cursor := minf(from, to)
		var end := maxf(from, to)
		for cut: Vector2 in cuts:
			if cut.x > cursor:
				runs.append(Vector2(cursor, minf(cut.x, end)))
			cursor = maxf(cursor, cut.y)
		if cursor < end:
			runs.append(Vector2(cursor, end))

		for k: int in runs.size():
			var run: Vector2 = runs[k]
			if run.y - run.x < 0.4:
				continue
			# An "x" ramp arrives at the face that faces along x, so the wall it
			# breaks runs along z, and the other way round.
			var a := Vector2(face, run.x) if axis == "x" else Vector2(run.x, face)
			var b := Vector2(face, run.y) if axis == "x" else Vector2(run.y, face)
			# The thickness goes across the run, which for a wall an "x" ramp
			# arrives at is x — the run itself is in z. Putting it on the other
			# component builds a wall with no width at all, and a landing on top
			# of nothing.
			var fat := Vector2(WALL_THICK * 0.5, 0.0) if axis == "x" \
				else Vector2(0.0, WALL_THICK * 0.5)
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - fat
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + fat
			_slab(st, lo, hi, BENCH_TOP, top)
			var centre := (lo + hi) * 0.5
			platforms.append(Platform.new(Vector3(centre.x, top, centre.y),
				WALL_THICK * 0.5 - 0.15, "wall", "wall %s %s %d" % [side, axis, k]))


## The two haul ramps into each base: a wedge of compacted road, solid
## underneath so there is no gap beside it to get stuck in.
func _build_ramps() -> void:
	for at: Vector2 in turned(BASE_AT):
		var flip := factors(at).y
		for entry: Dictionary in RAMPS:
			var axis := String(entry["axis"])
			var span: Vector2 = entry["span"]
			var lo := flip * minf(span.x, span.y)
			var hi := flip * maxf(span.x, span.y)
			var across := Vector2(minf(lo, hi), maxf(lo, hi))
			var foot := flip * float(entry["foot"])
			var head := flip * float(entry["head"])
			_wedge(_road_st, axis, across, foot, head, 0.0, BENCH_TOP)


func _build_pit() -> void:
	for entry: Dictionary in COLUMNS:
		for at: Vector2 in turned(entry["at"]):
			_stand(_raw_st, at, entry["size"], COLUMN_TOP)
			off_limits.append(Platform.new(Vector3(at.x, COLUMN_TOP, at.y),
				_inscribed(entry["size"]), "column",
				"%s %s" % [entry["label"], half_of(at)]))
			columns += 1

	for entry: Dictionary in BLOCKS:
		for at: Vector2 in turned(entry["at"]):
			_stand(_carved_st, at, entry["size"], BLOCK_TOP)
			platforms.append(Platform.new(Vector3(at.x, BLOCK_TOP, at.y),
				_inscribed(entry["size"]), "block",
				"%s %s" % [entry["label"], half_of(at)]))
			blocks += 1

	for entry: Dictionary in LIP_BLOCKS:
		var at: Vector2 = entry["at"]
		_stand(_carved_st, at, entry["size"], LIP_TOP)
		platforms.append(Platform.new(Vector3(at.x, LIP_TOP, at.y),
			_inscribed(entry["size"]), "lip", String(entry["label"])))
		blocks += 1

	for entry: Dictionary in KERBS:
		for at: Vector2 in turned(entry["at"]):
			_stand(_carved_st, at, entry["size"], KERB_TOP)
			platforms.append(Platform.new(Vector3(at.x, KERB_TOP, at.y),
				_inscribed(entry["size"]), "kerb",
				"%s %s" % [entry["label"], half_of(at)]))
			kerbs += 1


## The spoil rocks, and the only thing the Stylized Nature MegaKit puts on this
## map that a Bog cannot walk through.
##
## A quarry's waste is the biggest loose stone in the pit, and at the size the
## kit draws a `Rock_Medium` it reads as cover from right across the floor — so
## it has to *be* cover. It was not: the rocks were drawn as a
## `MultiMeshInstance3D` with the rest of the dressing, and a multimesh is a
## picture. You walked into one and stood inside it.
##
## So they are built here, **above `super()`**, as plain `MeshInstance3D`s. That
## is the whole fix: `StaticMap._build_collision` sweeps every `MeshInstance3D`
## under the map into world-space trimesh collision, so a rock built on this
## side of the line is real stone and one built below it is a hologram. It is
## the same rule the slabs obey and it costs no new machinery — Kopje Crossing
## hangs a convex hull off each of its boulders instead (`safari_map.gd`'s
## `_convex_body`) because its rocks are dressing that happens to be solid,
## where these are map.
##
## **Every one is squashed until its top is exactly `KERB_TOP`.** Left at the
## scale the scatter used, a rock stood about 1.5 m — a fourth height on a map
## whose entire language is three of them (1.2 kerb, 3.0 block, 10.2 column),
## and a thing a Bog can stand on that no table mentions, which is the failure
## D-042 and D-082 both exist to prevent. At 1.2 a rock simply *is* a kerb: low
## cover, one hop from flat ground so the reachability walk never calls it
## stranded, and declared in `platforms` like every other kerb on the map.
## It is sat on the floor by its own bounding box rather than by eye, so the
## record underneath is true to the millimetre and the report's ray agrees.
##
## **And it is tinted to the cut stone, not the raw.** The map says pale ochre
## is what you climb and dark grey is what you cannot; a rock you can hop onto
## has to be on the pale side of that even though the spoil it came from is the
## same rock as the columns. The pebbles round its foot stay the raw tint,
## because nobody is climbing a pebble.
func _build_rocks(parent: Node3D) -> void:
	var group := _group("Spoil", parent)
	for entry: Dictionary in SPOIL_ROCKS:
		var model: String = BOULDERS[int(entry["model"]) % BOULDERS.size()]
		var mesh := PropScatter.load_kit_mesh(model)
		if mesh == null:
			continue
		var box := mesh.get_aabb()
		# Wide from the footprint, tall from the height rule, so three meshes of
		# three different sizes all come out one kerb high and one span across.
		var wide := ROCK_SPAN / maxf(box.size.x, box.size.z)
		var tall := KERB_TOP / box.size.y
		var pair := turned(entry["at"])
		for k: int in pair.size():
			var at: Vector2 = pair[k]
			# Turned half a turn on the far half, like everything else here.
			var yaw := float(entry["yaw"]) + PI * float(k)
			var node := MeshInstance3D.new()
			node.name = "%s %d" % [entry["label"], k + 1]
			node.mesh = mesh
			node.transform = Transform3D(
				Basis(Vector3.UP, yaw).scaled(Vector3(wide, tall, wide)),
				Vector3(at.x, -box.position.y * tall, at.y))
			for surface: int in mesh.get_surface_count():
				node.set_surface_override_material(surface, _spoil_material)
			group.add_child(node)
			platforms.append(Platform.new(Vector3(at.x, KERB_TOP, at.y),
				ROCK_LANDING, "spoil", "%s %d" % [entry["label"], k + 1]))
			rocks += 1


# ---------------------------------------------------------------- landings ---

## The bench tops and the ramps, as the parkour report reads them.
##
## The bench is tiled rather than given one record, because one circle in the
## middle of a twelve-metre floor would call its corners unlandable and would
## also promise rock where the wall stands. The ramps get a record every 0.9 m
## of rise, which is what chains the floor to the bench: the lowest sits at
## 0.9 m and is a hop from flat ground, and each one after it is a hop from the
## one below (D-057's pattern, and the reason a ramp is a route and not a
## cliff).
func _plan_landings() -> void:
	for at: Vector2 in turned(BASE_AT):
		var pair := factors(at)
		var sign := pair.x
		var flip := pair.y
		var side := half_of(at)
		var lo := minf(sign * HALF, sign * BENCH_INNER)
		var hi := maxf(sign * HALF, sign * BENCH_INNER)
		var keep: Array[Rect2] = []
		# The wall's own footprint, so no bench landing sits inside it.
		var face := sign * BENCH_INNER + sign * WALL_THICK
		keep.append(Rect2(Vector2(minf(face, sign * BENCH_INNER), lo),
			Vector2(WALL_THICK, hi - lo)))
		keep.append(Rect2(Vector2(lo, minf(face, sign * BENCH_INNER)),
			Vector2(hi - lo, WALL_THICK)))
		_tile(Rect2(Vector2(lo, lo), Vector2(hi - lo, hi - lo)), BENCH_TOP,
			"bench", "bench %s" % side, keep)

		for entry: Dictionary in RAMPS:
			var axis := String(entry["axis"])
			var span: Vector2 = entry["span"]
			var mid := flip * (span.x + span.y) * 0.5
			var foot := flip * float(entry["foot"])
			var head := flip * float(entry["head"])
			var rise := 0.9
			var k := 1
			while rise * float(k) < BENCH_TOP - 0.3:
				var y := rise * float(k)
				var along := lerpf(foot, head, y / BENCH_TOP)
				var spot := Vector2(along, mid) if axis == "x" else Vector2(mid, along)
				platforms.append(Platform.new(Vector3(spot.x, y + RAMP_LIFT, spot.y),
					RAMP_WIDTH * 0.5 - 0.15, "ramp",
					"%s %s %d" % [entry["label"], side, k]))
				k += 1


## A grid of landings over `region`, skipping anything inside `keep` and
## shrinking a record's radius to whatever room it actually has.
func _tile(region: Rect2, y: float, zone: String, label: String,
		keep: Array[Rect2]) -> void:
	var nx := maxi(1, roundi(region.size.x / TILE))
	var nz := maxi(1, roundi(region.size.y / TILE))
	for i: int in nx:
		for j: int in nz:
			var p := Vector2(region.position.x + (float(i) + 0.5) * region.size.x / float(nx),
				region.position.y + (float(j) + 0.5) * region.size.y / float(nz))
			var room := minf(minf(p.x - region.position.x, region.end.x - p.x),
				minf(p.y - region.position.y, region.end.y - p.y))
			var clear := true
			for block: Rect2 in keep:
				var d := _rect_distance(block, p)
				if d < TILE_CLEAR:
					clear = false
					break
				room = minf(room, d)
			if not clear:
				continue
			platforms.append(Platform.new(Vector3(p.x, y, p.y),
				clampf(room - 0.15, 0.4, TILE_RADIUS), zone, "%s %d,%d" % [label, i, j]))


static func _rect_distance(rect: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - p.x, 0.0), p.x - rect.end.x)
	var dz := maxf(maxf(rect.position.y - p.y, 0.0), p.y - rect.end.y)
	return sqrt(dx * dx + dz * dz)


## The inscribed landing radius of a footprint, less the 0.15 m of lip every
## other built map takes off.
static func _inscribed(size: Vector2) -> float:
	return minf(size.x, size.y) * 0.5 - 0.15


# ---------------------------------------------------------------- dressing ---

## Everything growing in or fallen onto the pit, out of the Stylized Nature
## MegaKit — rubble, weeds, flowering bushes, spoil heaps and the dead trees on
## the rim.
##
## **This is where the map gets its colour.** Cut limestone, raw rock and a grey
## sky are three shades of the same thing, and the first build of the quarry read
## as one material lit four ways. The kit is a *nature* pack, which at first
## looked like the wrong pack for a hole full of stone — until the obvious thing:
## a quarry nobody has worked for a few years is being taken back by weeds. So
## the green comes out of the cracks, and it is the only saturated colour on the
## map besides the two work lamps.
##
## **None of *this* is collision, and that is now a decision rather than an
## accident.** Everything below is added after `super()` and drawn as a
## `MultiMeshInstance3D`, which `StaticMap._collect_meshes` does not even look
## at — it collects `MeshInstance3D` — so moving these lines above the `super()`
## call would still not make them solid. The spoil rocks, which *are* solid, are
## built by `_build_rocks` before the line instead.
##
## The rule is: **anything a player could mistake for cover has to be solid, and
## anything obviously not cover may be walked through.** That splits the kit
## cleanly.
##
##   * **Vegetation stays passable** — grass, clover, ferns, the flowering
##     bushes round the puddles. Walking through a weed is what a weed is for,
##     and a bush you bounce off is a bush that lies about being cover.
##   * **Rubble stays passable**, which is the one that needed thinking about. A
##     pebble is 0.4 m and the Bog has no step-up: a 0.2 m stair tread is a wall
##     to it (D-057), so a solid pebble is not an obstacle, it is something you
##     stub yourself on every few metres for no gain. And at 0.4 m nobody is
##     hiding behind one, so it is ground texture and is drawn as ground texture.
##   * **The dead trees on the rim stay passable** because they are eleven
##     metres up on a terrace nothing reaches; solid or not, no Bog will ever
##     touch one.
##   * **The spoil rocks are solid**, and they are the whole reason this list
##     exists. See `_build_rocks`.
##
## **It all hugs a face.** Nothing is free-standing out on the floor, because a
## bush in the middle of an aisle reads as cover and is not, and on a map whose
## whole language is "pale stone you climb, dark stone you cannot" a prop that
## looks like cover is a lie. Debris and weeds collect at the foot of a cut face
## in life as well, so the honest placement is also the useful one.
func _build_props(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = PROP_SEED
	var batch: Dictionary = {}

	for solid: Dictionary in _solid_footprints():
		var rect: Rect2 = solid["rect"]
		# A tall face sheds more and shelters more than a kerb does.
		var density := 0.95 if float(solid["top"]) > BLOCK_TOP else 0.7
		_apron(batch, rng, rect, density, bool(solid["raw"]))

	# The shaft's four lip blocks, which are not in `_solid_footprints()` because
	# they are not a `turned()` table. Weeds bank against them like anything else.
	for entry: Dictionary in LIP_BLOCKS:
		var lip: Vector2 = entry["at"]
		var span: Vector2 = entry["size"]
		_apron(batch, rng, Rect2(lip - span * 0.5, span), 0.8, false)

	# The foot of the cliff, all four sides, walked as one loop.
	_apron(batch, rng, Rect2(Vector2(-HALF, -HALF), Vector2(HALF, HALF) * 2.0),
		0.8, true)

	_build_spoil(batch, rng)
	_build_snags(batch, rng)
	_build_blooms(batch, rng)

	var props := _group("Props", parent)
	for model: String in batch:
		_scattered(props, model, batch[model])


## Every solid thing standing on the pit floor, as a footprint and a top. The
## tables are the truth, so this reads them rather than keeping a second list
## filled in during the build — a list that could go stale is the only way the
## props and the rock they are meant to be piled against can disagree.
func _solid_footprints() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for table: Array in [COLUMNS, BLOCKS, KERBS]:
		var top := COLUMN_TOP if table == COLUMNS else \
			(BLOCK_TOP if table == BLOCKS else KERB_TOP)
		for entry: Dictionary in table:
			for at: Vector2 in turned(entry["at"]):
				var size: Vector2 = entry["size"]
				out.append({"rect": Rect2(at - size * 0.5, size), "top": top,
					"raw": table == COLUMNS})
	for at: Vector2 in turned(BASE_AT):
		var sign := factors(at).x
		var lo := minf(sign * HALF, sign * BENCH_INNER)
		var hi := maxf(sign * HALF, sign * BENCH_INNER)
		out.append({"rect": Rect2(Vector2(lo, lo), Vector2(hi - lo, hi - lo)),
			"top": BENCH_TOP, "raw": false})
	return out


## Whether a point is over the shaft, with a margin so nothing perches on the very
## lip either. The props were written when the middle of this map was solid rock
## (D-082); the hole came later (D-089), and every scatter that used to land on
## stone there now lands on nothing — which is what the shrubs and pebbles left
## hanging in mid-air over the edge were. Every placement asks this first.
static func _in_hole(at: Vector2) -> bool:
	var edge := HOLE_HALF + 0.5
	return absf(at.x) < edge and absf(at.y) < edge


## Rubble and weeds round the outside of one footprint. Walks the perimeter at a
## stride and offers each step a prop, set just outside the face and turned at
## random; `raw` stone sheds coarser waste than a sawn block does.
func _apron(batch: Dictionary, rng: RandomNumberGenerator, rect: Rect2,
		density: float, raw: bool) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)]
	for i: int in 4:
		var from: Vector2 = corners[i]
		var to: Vector2 = corners[(i + 1) % 4]
		var run := from.distance_to(to)
		var steps := maxi(1, int(run / APRON_STRIDE))
		var along := (to - from) / float(steps)
		# Outward is away from the middle of the rect, which for an axis-aligned
		# box is the run turned a quarter and pointed away from the centre.
		var out := Vector2(along.y, -along.x).normalized()
		if (from + to) * 0.5 + out * 0.1 - rect.get_center() == Vector2.ZERO:
			out = -out
		if ((from + to) * 0.5 - rect.get_center()).dot(out) < 0.0:
			out = -out
		for k: int in steps:
			if rng.randf() > density:
				continue
			var at := from + along * (float(k) + rng.randf())
			at += out * rng.randf_range(APRON_NEAR, APRON_FAR)
			if absf(at.x) > HALF - 0.3 or absf(at.y) > HALF - 0.3 or _in_hole(at):
				continue
			var pick := rng.randf()
			if pick < (0.55 if raw else 0.40):
				_place(batch, rng, RUBBLE, at, 0.0, RUBBLE_SCALE)
			elif pick < 0.92:
				_place(batch, rng, WEEDS, at, 0.0, WEED_SCALE)
			else:
				_place(batch, rng, BLOOMS, at, 0.0, BLOOM_SCALE)


## The chips banked round each spoil rock: waste off the same heap, and the only
## part of a heap that is still a picture.
##
## The rocks used to be here too, scattered by a normal draw round two heap
## centres. That was fine while they were scenery and is not fine now they are
## stone: one of those centres sat 1.4 m from a spawn pad, and a scatter is how a
## rock ends up inside a haul ramp or standing on somebody's landing. So the
## rocks moved out to `SPOIL_ROCKS`, which is a table like every other position
## on this map, and what is left here is the rubble that makes four placed rocks
## read as a tip rather than as four rocks.
func _build_spoil(batch: Dictionary, rng: RandomNumberGenerator) -> void:
	for entry: Dictionary in SPOIL_ROCKS:
		for at: Vector2 in turned(entry["at"]):
			for i: int in ROCK_SKIRT:
				var spot := at + Vector2(rng.randfn(0.0, ROCK_SKIRT_SPREAD),
					rng.randfn(0.0, ROCK_SKIRT_SPREAD))
				if absf(spot.x) > HALF - 0.4 or absf(spot.y) > HALF - 0.4 or _in_hole(spot):
					continue
				_place(batch, rng, RUBBLE, spot, 0.0, RUBBLE_SCALE)


## Dead trees along the rim's first terrace, eleven metres up. Nothing on this
## map is taller than the cliff except the derricks, so the skyline is the only
## place a silhouette reads at all — and a bare trunk over the edge of a pit says
## "abandoned" faster than anything down in it can.
func _build_snags(batch: Dictionary, rng: RandomNumberGenerator) -> void:
	var edge := HALF + RIM_TIERS[1].x * 0.5
	for i: int in SNAG_COUNT:
		var t := (float(i) + 0.5) / float(SNAG_COUNT)
		var side := i % 4
		var along := lerpf(-edge, edge, fposmod(t * 3.7, 1.0))
		var at := Vector2(along, -edge) if side == 0 \
			else Vector2(along, edge) if side == 1 \
			else Vector2(-edge, along) if side == 2 \
			else Vector2(edge, along)
		_place(batch, rng, SNAGS, at, 0.0, SNAG_SCALE, RIM_TOP)


## A fringe of flowering bushes round every puddle. Water is the one place on a
## stone floor that grows anything without a crack to do it in.
func _build_blooms(batch: Dictionary, rng: RandomNumberGenerator) -> void:
	for spot: Vector2 in PUDDLES:
		for i: int in 9:
			var bearing := TAU * (float(i) + rng.randf()) / 9.0
			var at := spot + Vector2(cos(bearing), sin(bearing)) * rng.randf_range(2.6, 3.8)
			if absf(at.x) > HALF - 0.5 or absf(at.y) > HALF - 0.5 or _in_hole(at):
				continue
			_place(batch, rng, BLOOMS if i % 3 == 0 else WEEDS, at, 0.0,
				BLOOM_SCALE if i % 3 == 0 else WEED_SCALE)


## One prop into the batch: a model out of `models`, at `at` on the floor (or on
## `floor_y`), yawed at random and scaled somewhere in `scale`.
func _place(batch: Dictionary, rng: RandomNumberGenerator, models: PackedStringArray,
		at: Vector2, tilt: float, scale: Vector2, floor_y: float = 0.0) -> void:
	var model := models[rng.randi() % models.size()]
	var size := rng.randf_range(scale.x, scale.y)
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
	if not is_zero_approx(tilt):
		basis = Basis(Vector3.RIGHT, tilt) * basis
	basis = basis.scaled(Vector3(size, size, size))
	var list: Array = batch.get(model, [])
	list.append(Transform3D(basis, Vector3(at.x, floor_y, at.y)))
	batch[model] = list


## One `MultiMeshInstance3D` per model. A `MeshInstance3D` per prop would be
## eight hundred nodes and eight hundred draw calls for scenery nothing collides
## with — and, since the sweep collects `MeshInstance3D`, eight hundred pebbles
## of trimesh collision the moment anybody moved the `super()` call. A multimesh
## cannot be swept, which is exactly why the spoil rocks are not drawn with one.
func _scattered(parent: Node3D, model: String, transforms: Array) -> void:
	var mesh := PropScatter.load_kit_mesh(model)
	if mesh == null or transforms.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	var bounds := AABB()
	for i: int in transforms.size():
		var xform: Transform3D = transforms[i]
		multi.set_instance_transform(i, xform)
		var box := xform * mesh.get_aabb()
		bounds = box if i == 0 else bounds.merge(box)
	var node := MultiMeshInstance3D.new()
	node.name = model
	node.multimesh = multi
	node.custom_aabb = bounds
	# Shadows only from the things tall enough to cast one worth having. A
	# pebble's shadow under an overcast is a pixel of noise in every cascade, and
	# the only prop left up here big enough to matter is a dead tree.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if \
		SNAGS.has(model) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if RUBBLE.has(model):
		# Quarry waste is the same rock as the faces it fell off, so it is
		# tinted to the pit rather than left the kit's own warm sandstone.
		node.material_override = _rubble_material
	parent.add_child(node)


## Standing water in the low corners, where a worked pit always has it. Flat
## quads a centimetre over the floor, casting nothing: the floor is level, so
## this is the only thing that says which parts of it are the bottom.
func _build_puddles(parent: Node3D) -> void:
	var st := _begin()
	for spot: Vector2 in PUDDLES:
		var size := Vector2(5.5, 4.0) if absf(spot.x) > absf(spot.y) else Vector2(4.0, 5.5)
		_quad_into(st, Vector3(spot.x - size.x * 0.5, 0.012, spot.y - size.y * 0.5),
			size, 3.0)
	var node := MeshInstance3D.new()
	node.name = "Puddles"
	node.mesh = st.commit()
	node.material_override = _water_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


## A painted edge down both sides of every haul ramp, and a bar across the head
## of each. A ramp the same colour as the floor it rises out of is a ramp people
## run past; the paint is what makes the two ways up read as the two ways up.
func _build_kerb_paint(parent: Node3D) -> void:
	var st := _begin()
	for at: Vector2 in turned(BASE_AT):
		var flip := factors(at).y
		for entry: Dictionary in RAMPS:
			var axis := String(entry["axis"])
			var span: Vector2 = entry["span"]
			var foot := flip * float(entry["foot"])
			var head := flip * float(entry["head"])
			for edge: float in [span.x, span.y]:
				var across := flip * edge
				var a := minf(foot, head)
				var b := maxf(foot, head)
				var steps := 14
				for k: int in steps:
					var t0 := float(k) / float(steps)
					var t1 := float(k + 1) / float(steps)
					if k % 2 == 1:
						continue
					var p0 := lerpf(a, b, t0)
					var p1 := lerpf(a, b, t1)
					var y0 := _ramp_height(p0, foot, head)
					var y1 := _ramp_height(p1, foot, head)
					var lo := Vector3(p0, y0 + 0.02, across - 0.16) if axis == "x" \
						else Vector3(across - 0.16, y0 + 0.02, p0)
					var hi := Vector3(p1, y1 + 0.02, across + 0.16) if axis == "x" \
						else Vector3(across + 0.16, y1 + 0.02, p1)
					_strip(st, lo, hi, axis == "x")
	var node := MeshInstance3D.new()
	node.name = "RampPaint"
	node.mesh = st.commit()
	node.material_override = _rust_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


func _ramp_height(along: float, foot: float, head: float) -> float:
	return clampf((along - foot) / (head - foot), 0.0, 1.0) * BENCH_TOP


## Two derricks standing outside the rim on the diagonal the bases are not on: a
## lattice mast, a boom out over the pit and the stays that hold it. It is the
## only thing visible over an eleven-metre cliff, and it is what says the hole
## was dug rather than found.
func _build_derricks(parent: Node3D) -> void:
	var st := _begin()
	for at: Vector2 in turned(DERRICK_AT):
		var toward := -Vector2(at.x, at.y).normalized()
		var frame := Transform3D(Basis(Vector3.UP, atan2(toward.x, toward.y)),
			Vector3(at.x, 0.0, at.y))
		var legs := 2.2
		for sx: float in [-legs, legs]:
			for sz: float in [-legs, legs]:
				_beam(st, frame, Vector3(sx, 0.0, sz),
					Vector3(sx * 0.25, DERRICK_HEIGHT, sz * 0.25), 0.5)
		for rung: int in 6:
			var y := DERRICK_HEIGHT * float(rung + 1) / 7.0
			var w := lerpf(legs, legs * 0.25, float(rung + 1) / 7.0)
			for corner: Array in [[-w, -w, w, -w], [w, -w, w, w], [w, w, -w, w],
					[-w, w, -w, -w]]:
				_beam(st, frame, Vector3(corner[0], y, corner[1]),
					Vector3(corner[2], y, corner[3]), 0.22)
		var top := Vector3(0.0, DERRICK_HEIGHT, 0.0)
		var tip := Vector3(0.0, DERRICK_HEIGHT - 3.5, 13.0)
		_beam(st, frame, top, tip, 0.45)
		_beam(st, frame, top + Vector3(0.0, -6.0, 0.0), tip, 0.25)
		_beam(st, frame, top, Vector3(0.0, 2.0, -7.0), 0.25)
	var node := MeshInstance3D.new()
	node.name = "Derricks"
	node.mesh = st.commit()
	node.material_override = _steel_material
	parent.add_child(node)


## One work lamp over each base, on a short mast against the rim behind it. Two
## lights on the whole map: the sky is doing the rest, and at this hour a base
## that does not have a warm point in it is a base you cannot pick out of a grey
## pit from the far corner.
func _build_lamps(parent: Node3D) -> void:
	var lights := _group("Lights", parent)
	var st := _begin()
	var heads := _begin()
	for at: Vector2 in turned(BASE_AT):
		var sign := factors(at).x
		var mast := Vector3(sign * (HALF - 0.8), BENCH_TOP, sign * (HALF - 0.8))
		_beam(st, Transform3D.IDENTITY, mast, mast + Vector3.UP * 4.2, 0.28)
		var head := mast + Vector3.UP * 4.2
		_beam(heads, Transform3D.IDENTITY, head,
			head + Vector3(-sign * 0.9, -0.5, -sign * 0.9), 0.7)
		var lamp := OmniLight3D.new()
		lamp.name = "Work%s" % half_of(at)
		lamp.position = head + Vector3(-sign * 0.6, -0.3, -sign * 0.6)
		lamp.light_color = LAMP_WARM
		lamp.light_energy = 3.2
		lamp.omni_range = 22.0
		lamp.omni_attenuation = 1.4
		lamp.shadow_enabled = false
		lights.add_child(lamp)
	var node := MeshInstance3D.new()
	node.name = "LampMasts"
	node.mesh = st.commit()
	node.material_override = _steel_material
	parent.add_child(node)
	var glow := MeshInstance3D.new()
	glow.name = "LampHeads"
	glow.mesh = heads.commit()
	glow.material_override = _lamp_material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(glow)


# ------------------------------------------------------------------ meshes ---

func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _commit(parent: Node3D, named: String, st: SurfaceTool,
		material: StandardMaterial3D, tint: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = named
	node.mesh = st.commit()
	var own := material.duplicate() as StandardMaterial3D
	own.albedo_color = tint
	node.material_override = own
	parent.add_child(node)
	return node


## An axis-aligned slab from (lo.x, base, lo.y) to (hi.x, top, hi.y), UV'd in
## metres so one stone texture tiles over everything at the same scale whatever
## the slab's size.
func _slab(st: SurfaceTool, lo: Vector2, hi: Vector2, base: float, top: float) -> void:
	var a := Vector3(lo.x, base, lo.y)
	var b := Vector3(hi.x, top, hi.y)
	# Top. The corners go anticlockwise *seen from above*, which is the order
	# `_quad` turns into Godot's clockwise-from-the-front winding. Reversed, the
	# top of every slab is culled away from a camera looking down at it and
	# invisible to any ray with `hit_back_faces` off — which is the query
	# `CaptureLayout` settles the letter cards with, so the cards ended up
	# wherever the search gave up.
	_quad(st, Vector3(a.x, b.y, b.z), Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, a.z),
		Vector3(a.x, b.y, a.z), Vector3.UP, Vector2(b.x - a.x, b.z - a.z))
	# Sides, wound so the outward face is the front one.
	_quad(st, Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z),
		Vector3(a.x, b.y, b.z), Vector3.BACK, Vector2(b.x - a.x, b.y - a.y))
	_quad(st, Vector3(b.x, a.y, a.z), Vector3(a.x, a.y, a.z), Vector3(a.x, b.y, a.z),
		Vector3(b.x, b.y, a.z), Vector3.FORWARD, Vector2(b.x - a.x, b.y - a.y))
	_quad(st, Vector3(b.x, a.y, b.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z),
		Vector3(b.x, b.y, b.z), Vector3.RIGHT, Vector2(b.z - a.z, b.y - a.y))
	_quad(st, Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, b.z), Vector3(a.x, b.y, b.z),
		Vector3(a.x, b.y, a.z), Vector3.LEFT, Vector2(b.z - a.z, b.y - a.y))


## A block standing on the floor, given its centre and footprint.
func _stand(st: SurfaceTool, at: Vector2, size: Vector2, top: float) -> void:
	_slab(st, at - size * 0.5, at + size * 0.5, 0.0, top)


## A ramp: a wedge whose top climbs from `base` at `foot` to `top` at `head`
## along `axis`, solid to the floor underneath.
##
## **Every corner order below is written for one handedness, and the swap above
## them is what supplies it.** This is the same failure `_slab`'s top face
## already carries a note about, arrived at from the other direction: there the
## four corners were simply typed the wrong way round, here they are typed one
## way and *mean* two, because `_at` does not build the same frame for both
## axes. An `"x"` ramp lays (along, across) onto (x, z) and a `"z"` ramp lays it
## onto (z, x), and swapping a pair of components reverses handedness — so one
## fixed corner order is front-facing on one axis and back-facing on the other,
## and with `cull_mode = CULL_BACK` on the road material that is a ramp you see
## straight through and still walk up, because collision is a triangle soup and
## does not care which way a triangle faces. The climb direction flips it a
## second time: `head` is at -11.5 on the half the tables are written for and at
## +11.5 on its turn (`factors`), which mirrors the solid along its own axis. So
## the parity that matters is both together, and `frame * toward` is it —
## exactly one of each base's two ramps came out inside-out, which is what was
## reported.
##
## Ordering `lo` and `hi` by that parity rather than reversing four corner lists
## by hand is the fix, because it is one decision instead of five that have to
## agree: swapping which edge of the span is called `lo` reverses the winding of
## **every** face at once, and the five faces below are wound coherently with
## each other (each shared edge is walked in opposite directions by the two
## faces that own it), so getting one of them right gets all five right. It
## changes no position, no span and no triangle — `lo` and `hi` are the same two
## numbers either way round — so the swept collision is identical, which D-058
## requires: these ramps are the only two ways into a base.
func _wedge(st: SurfaceTool, axis: String, across: Vector2, foot: float, head: float,
		base: float, top: float) -> void:
	var toward := signf(head - foot)
	# +1 where (across x along) points up, -1 where it points down: the sign of
	# the handedness `_at` builds for this axis. `"x"` maps across to z and along
	# to x, and z cross x is up; `"z"` maps them the other way, and x cross z is
	# down.
	var frame := 1.0 if axis == "x" else -1.0
	var lo := across.x
	var hi := across.y
	if toward * frame < 0.0:
		var swapped := lo
		lo = hi
		hi = swapped
	var fl := _at(axis, foot, lo, base)
	var fr := _at(axis, foot, hi, base)
	var hl := _at(axis, head, lo, top)
	var hr := _at(axis, head, hi, top)
	var bl := _at(axis, head, lo, base)
	var br := _at(axis, head, hi, base)

	# Metres, for the UVs, so the road grit is the same size on a ramp as it is
	# on the floor the ramp rises out of. The sloped face is `slope` long and not
	# `run` long, which is the difference between the texture running up the
	# climb and being squeezed 6 per cent into it.
	var run := absf(head - foot)
	var rise := top - base
	var wide := absf(across.y - across.x)
	var slope := sqrt(run * run + rise * rise)

	# The real surface normal, off the rise and the run. It used to be a
	# hard-coded 45 degrees — `Vector3(-toward, 1, 0)` — on a slope that is 19.2,
	# so the one face on this map a player spends time looking down was lit as
	# though it were twice as steep as it is.
	var up := _at(axis, -toward * rise, 0.0, run).normalized()
	# Out of the head, along the ramp's own axis: the riser stands at `head` and
	# the solid is behind it.
	var into := _at(axis, toward, 0.0, 0.0)
	# From the `lo` edge toward the `hi` one — derived from the span rather than
	# assumed, because the swap above may have exchanged them. This is the other
	# half of what was wrong: both side triangles were handed `Vector3.LEFT`
	# (a copy-paste — the two branches of the ternary were the same vector), so
	# on an `"x"` ramp, whose sides face ±z, the shader was given a normal lying
	# *in* the face instead of out of it, and the two flanks lit as though they
	# were edges.
	var flank := _at(axis, 0.0, signf(hi - lo), 0.0)

	_quad(st, fl, fr, hr, hl, up, Vector2(wide, slope))
	# The riser at the head, and the underside, so the wedge is a closed solid.
	# These two were not wound with the sloped top — they were written the other
	# way round from it — so every ramp had two of its five faces inside-out,
	# and which two depended on the parity above. Nobody ever saw it: the riser
	# is buried in the bench's face and the underside lies on the pit floor. A
	# solid that is only right where somebody happens to be looking is right by
	# luck, and the luck ran out on the two sloped tops.
	_quad(st, bl, hl, hr, br, into, Vector2(rise, wide))
	_quad(st, fl, bl, br, fr, Vector3.DOWN, Vector2(run, wide))
	# The two flanks, walked so each shares its three edges with the top, the
	# riser and the underside in the opposite direction to them.
	_tri(st, fl, hl, bl, -flank, _at(axis, 1.0, 0.0, 0.0))
	_tri(st, fr, br, hr, flank, _at(axis, 1.0, 0.0, 0.0))


## A point on a ramp: `along` down its axis, `across` the other way, `y` up.
##
## The two arms swap a pair of components, so they are not the same frame turned
## — they are mirror images of each other. Everything that winds a face out of
## points from here has to know that; see `_wedge`.
static func _at(axis: String, along: float, across: float, y: float) -> Vector3:
	return Vector3(along, y, across) if axis == "x" else Vector3(across, y, along)


## One quad, wound clockwise from the front, UV'd in metres over `span`.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		normal: Vector3, span: Vector2) -> void:
	var uv := [Vector2(0.0, span.y), Vector2(span.x, span.y), Vector2(span.x, 0.0),
		Vector2(0.0, 0.0)]
	var corners := [a, b, c, d]
	for index: int in [0, 2, 1, 0, 3, 2]:
		st.set_normal(normal)
		st.set_uv(uv[index])
		st.add_vertex(corners[index])


## One triangle on a vertical face, wound anticlockwise seen from the front like
## `_quad`'s corners, and UV'd in metres: across the face along `u_axis`, up it
## in y.
##
## `u_axis` is named rather than guessed. This used to read `p.x + p.z`, which on
## a face of constant x or constant z does come out as metres — the constant
## simply offsets the texture — but it only does so by accident of these faces
## being axis-aligned, and it says nothing about which way across the face the
## texture runs. Naming the direction makes it the same kind of UV `_quad` and
## `_slab` lay down, which is what keeps one grain size over the whole pit.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3,
		u_axis: Vector3) -> void:
	for p: Vector3 in [a, c, b]:
		st.set_normal(normal)
		st.set_uv(Vector2(p.dot(u_axis), p.y))
		st.add_vertex(p)


## A flat quad on y, `size` across, starting at `at`, UV'd over `tile` metres.
func _quad_into(st: SurfaceTool, at: Vector3, size: Vector2, tile: float) -> void:
	var a := at
	var b := at + Vector3(size.x, 0.0, 0.0)
	var c := at + Vector3(size.x, 0.0, size.y)
	var d := at + Vector3(0.0, 0.0, size.y)
	_quad(st, d, c, b, a, Vector3.UP, size / tile)


## One dash of paint lying on a ramp, between two opposite corners — `lo` is the
## low end of both the dash's span and its width, `hi` the high end of both — and
## `along_x` says which of the two the slope runs down.
##
## **The height has to follow the slope, not the width**, and it did not. The old
## corners took y from whichever end supplied x or z, which put one long edge of
## a 0.32 m dash at the uphill height and the other at the downhill one: a
## rectangle 32 cm wide with 29 cm of twist in it, standing up out of the road
## like a fin. That is what the rust-coloured chevrons up both haul ramps were —
## not a texture at all, but four hundred little flaps of geometry seen
## side-on. Taking y from the *along* end instead makes each dash flat on the
## stone, which is what a painted line is.
##
## The normal comes off the corners rather than being `Vector3.UP`, for the same
## reason `_wedge`'s does: the dash lies on a 19.2 degree slope and a dash lit
## as though it were level reads as a sticker rather than as paint.
func _strip(st: SurfaceTool, lo: Vector3, hi: Vector3, along_x: bool) -> void:
	var a := lo
	var b := Vector3(lo.x, lo.y if along_x else hi.y, hi.z)
	var c := hi
	var d := Vector3(hi.x, hi.y if along_x else lo.y, lo.z)
	_quad(st, a, b, c, d, (b - a).cross(c - a).normalized(), Vector2(1.0, 1.0))


## A box stretched from `from` to `to`, `thickness` square, in `xform`'s frame.
func _beam(st: SurfaceTool, xform: Transform3D, from: Vector3, to: Vector3,
		thickness: float) -> void:
	var span := to - from
	if span.length() < 0.001:
		return
	var up := Vector3.UP if absf(span.normalized().y) < 0.95 else Vector3.RIGHT
	var along := Transform3D(Basis.looking_at(span, up), (from + to) * 0.5)
	var frame := xform * along
	var half := Vector3(thickness, thickness, span.length()) * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP],
		[Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP],
		[Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
	]
	for face: Array in faces:
		var n: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var mid := n * half
		var du := u * half
		var dv := v * half
		var world_n := (frame.basis * n).normalized()
		for p: Vector3 in [mid - du - dv, mid + du - dv, mid + du + dv,
				mid - du - dv, mid + du + dv, mid - du + dv]:
			st.set_normal(world_n)
			st.set_uv(Vector2(p.x + p.z, p.y))
			st.add_vertex(frame * p)


# --------------------------------------------------------------- materials ---

func _build_materials() -> void:
	var cut := _stone_images()
	_stone_material = StandardMaterial3D.new()
	_stone_material.albedo_texture = ImageTexture.create_from_image(cut[0])
	_stone_material.normal_enabled = true
	_stone_material.normal_texture = ImageTexture.create_from_image(cut[1])
	_stone_material.normal_scale = 0.8
	_stone_material.roughness = 0.88
	# One tile every four metres. At two it read as bathroom tiling: the drill
	# channels and the lift seams both landed on a half-metre pitch, and two grids
	# at the same spacing at right angles is a grid, not a rock face.
	_stone_material.uv1_scale = Vector3(0.25, 0.25, 0.25)
	_stone_material.cull_mode = BaseMaterial3D.CULL_BACK

	# Carved stone: the blocks and kerbs standing in the pit, and the one surface
	# a player is nose to nose with while taking cover. It gets its own texture
	# rather than sharing the rim's, because the rim is a sawn wall two hundred
	# metres of drill line long and a block is a dressed lump somebody worked all
	# the way round — tooled, chamfered and chipped at the arrises. Same ochre, so
	# D-082's readability rule still holds: pale means you can climb it.
	var carved := _carved_images()
	_carved_material = StandardMaterial3D.new()
	_carved_material.albedo_texture = ImageTexture.create_from_image(carved[0])
	_carved_material.normal_enabled = true
	_carved_material.normal_texture = ImageTexture.create_from_image(carved[1])
	_carved_material.normal_scale = 1.0
	_carved_material.roughness = 0.9
	# One tile a metre: a block is 3 m and a kerb 2 m, so the tooling repeats two
	# or three times across a face rather than being stretched over it.
	_carved_material.uv1_scale = Vector3(1.0, 1.0, 1.0)
	_carved_material.cull_mode = BaseMaterial3D.CULL_BACK

	# Brick, tinted per team at commit time by `brick_for_team`.
	var brick := _brick_images()
	_brick_material = StandardMaterial3D.new()
	_brick_material.albedo_texture = ImageTexture.create_from_image(brick[0])
	_brick_material.normal_enabled = true
	_brick_material.normal_texture = ImageTexture.create_from_image(brick[1])
	_brick_material.normal_scale = 1.1
	_brick_material.roughness = 0.82
	# One tile a metre, which is four bricks across and twelve courses up — real
	# brick sizes, so the bench reads as built rather than as wallpaper.
	_brick_material.uv1_scale = Vector3(1.0, 1.0, 1.0)
	_brick_material.cull_mode = BaseMaterial3D.CULL_BACK

	var gravel := _gravel_images()
	_floor_material = StandardMaterial3D.new()
	_floor_material.albedo_texture = ImageTexture.create_from_image(gravel[0])
	_floor_material.normal_enabled = true
	_floor_material.normal_texture = ImageTexture.create_from_image(gravel[1])
	_floor_material.normal_scale = 0.7
	_floor_material.roughness = 0.96
	# Half a metre a tile. Gravel is the one surface whose grain has a real size —
	# a stone is a few centimetres — and stretching the tile is what made the
	# first floor read as damp cardboard.
	_floor_material.uv1_scale = Vector3(2.0, 2.0, 2.0)
	_floor_material.cull_mode = BaseMaterial3D.CULL_BACK

	_road_material = StandardMaterial3D.new()
	_road_material.albedo_texture = _grit_texture(0x2C19, 0.09)
	_road_material.roughness = 0.9
	_road_material.uv1_scale = Vector3(0.3, 0.3, 0.3)
	_road_material.cull_mode = BaseMaterial3D.CULL_BACK

	_steel_material = StandardMaterial3D.new()
	_steel_material.albedo_color = STEEL
	_steel_material.metallic = 0.6
	_steel_material.roughness = 0.5

	_rust_material = StandardMaterial3D.new()
	_rust_material.albedo_color = RUST
	_rust_material.roughness = 0.8

	_water_material = StandardMaterial3D.new()
	_water_material.albedo_color = PUDDLE
	_water_material.metallic = 0.15
	_water_material.roughness = 0.14

	# The kit's rocks arrive a warm sandstone. Tinted to the pit's own raw stone
	# and roughened, so a pebble reads as a chip off the column it is lying
	# against rather than as a prop from somewhere else.
	_rubble_material = StandardMaterial3D.new()
	_rubble_material.albedo_color = Color(0.52, 0.49, 0.44)
	_rubble_material.roughness = 0.95
	_rubble_material.cull_mode = BaseMaterial3D.CULL_BACK

	# The spoil rocks are the same waste and a shade paler, because they are the
	# only loose stone on the map you can climb and the map's one readability
	# rule is that pale stone is what you climb. Shadows on, unlike the pebbles:
	# a kerb-high rock with no shadow under it floats.
	_spoil_material = StandardMaterial3D.new()
	_spoil_material.albedo_color = STONE_CUT
	_spoil_material.roughness = 0.92
	_spoil_material.cull_mode = BaseMaterial3D.CULL_BACK

	_lamp_material = StandardMaterial3D.new()
	_lamp_material.albedo_color = LAMP_WARM
	_lamp_material.emission_enabled = true
	_lamp_material.emission = LAMP_WARM
	_lamp_material.emission_energy_multiplier = 5.0


## Cut limestone, as an albedo and a normal map, 256 x 256.
##
## What makes a quarry face read as a quarry face is the **drill line**: the
## half-round channels a row of boreholes leaves down a sawn wall, every 30 cm
## or so, which is why it is the one thing here that is not noise. The rest is
## two octaves of value noise for the grain and a darker horizontal seam every
## metre, where one lift of stone was taken off the one below.
##
## Computed rather than loaded, like the wharf's corrugation: there is nothing
## to import, nothing that is anybody else's, and it costs about 20 ms.
func _stone_images() -> Array[Image]:
	var size := 256
	var albedo := Image.create(size, size, false, Image.FORMAT_RGB8)
	var normal := Image.create(size, size, false, Image.FORMAT_RGB8)
	var grain := FastNoiseLite.new()
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grain.frequency = 0.045
	grain.fractal_octaves = 3
	grain.seed = 0x51A7
	# Eight drill channels over the texture, which is 2 m of wall at the uv
	# scale above: a borehole every 25 cm.
	var drills := 8.0
	for x: int in size:
		var phase := TAU * drills * float(x) / float(size)
		# A channel, not a wave: mostly flat wall with a scoop cut out of it.
		var scoop := maxf(0.0, cos(phase))
		var slope := -sin(phase) * scoop * 0.9
		for y: int in size:
			var lift := absf(fposmod(float(y), float(size) / 4.0) - float(size) / 8.0) \
				/ (float(size) / 8.0)
			var seam := 1.0 if lift > 0.06 else 0.62
			var shade := (0.98 - 0.40 * scoop) * seam
			shade *= 0.86 + 0.28 * (grain.get_noise_2d(float(x), float(y)) * 0.5 + 0.5)
			albedo.set_pixel(x, y, Color(shade, shade, shade))
			var n := Vector3(slope, 0.0, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	albedo.generate_mipmaps()
	normal.generate_mipmaps()
	var out: Array[Image] = [albedo, normal]
	return out


## Real gravel: individual stones, not a noise ramp.
##
## The first floor was two greys of simplex over a four-metre tile, and at the
## height a Bog's eye actually is it read as damp cardboard — there was no stone
## in it, only a stain. Gravel has a *grain size*: a chipping is a few
## centimetres, and any texture that does not resolve one is a photograph of a
## car park taken from an aeroplane.
##
## So this draws the stones. `TYPE_CELLULAR` returning `RETURN_CELL_VALUE` hands
## back a different constant per Worley cell, which is one pebble; that value
## picks the stone's own lightness and a little of its hue off a warm-to-cool
## spread, so no two neighbours match. `RETURN_DISTANCE` over the same cells
## gives the gap between stones, which darkens into the dust packed between them
## and drives the normal map, so the light catches the edge of every chipping.
## Two octaves of fine value noise on top is the grit that fills the gaps.
func _gravel_images() -> Array[Image]:
	var size := 512
	var albedo := Image.create(size, size, false, Image.FORMAT_RGB8)
	var normal := Image.create(size, size, false, Image.FORMAT_RGB8)

	var cells := FastNoiseLite.new()
	cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	cells.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	cells.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	cells.frequency = 0.075
	cells.seed = 0x51A7

	var gaps := FastNoiseLite.new()
	gaps.noise_type = FastNoiseLite.TYPE_CELLULAR
	gaps.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	gaps.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	gaps.frequency = 0.075
	gaps.seed = 0x51A7

	var grit := FastNoiseLite.new()
	grit.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grit.frequency = 0.35
	grit.fractal_octaves = 2
	grit.seed = 0x2C19

	# Sampled one pixel apart to slope the normal, so the relief comes off the
	# same field the albedo does rather than being invented separately.
	var height := PackedFloat32Array()
	height.resize(size * size)
	for y: int in size:
		for x: int in size:
			var d := gaps.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var g := grit.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			height[y * size + x] = clampf(1.0 - d, 0.0, 1.0) * 0.85 + g * 0.15

	for y: int in size:
		for x: int in size:
			var stone := cells.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var h := height[y * size + x]
			# The stone's own tone, then the dust in the gap between stones.
			var shade := lerpf(0.52, 1.0, stone)
			shade = lerpf(shade * 0.52, shade, smoothstep(0.0, 0.45, h))
			# A little warmth on the paler chippings, cooler in the shadowed gaps,
			# because a floor of one hue is the thing being fixed here.
			var warm := lerpf(0.88, 1.06, stone)
			albedo.set_pixel(x, y, Color(
				clampf(shade * warm, 0.0, 1.0),
				clampf(shade * lerpf(0.94, 1.0, stone), 0.0, 1.0),
				clampf(shade * lerpf(1.02, 0.90, stone), 0.0, 1.0)))

			var hx: float = height[y * size + posmod(x + 1, size)]
			var hy: float = height[posmod(y + 1, size) * size + x]
			var n := Vector3((h - hx) * 2.4, (h - hy) * 2.4, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))

	albedo.generate_mipmaps()
	normal.generate_mipmaps()
	var out: Array[Image] = [albedo, normal]
	return out


## Dressed stone: a block somebody worked all the way round, as opposed to the
## sawn wall the rim is.
##
## The difference that matters is the *direction of the tooling*. A drill line is
## vertical and mechanical, which is right for a face a machine cut; a dressed
## block is gone over by hand, so its marks run diagonally, cross each other, and
## stop at a chamfer around the edge of the face. Drawing the chamfer into the
## texture is what stops a 3 m cube reading as a texture-mapped cube: the arris
## catches the light all the way round whatever the lighting is doing.
func _carved_images() -> Array[Image]:
	var size := 256
	var albedo := Image.create(size, size, false, Image.FORMAT_RGB8)
	var normal := Image.create(size, size, false, Image.FORMAT_RGB8)

	var tooth := FastNoiseLite.new()
	tooth.noise_type = FastNoiseLite.TYPE_SIMPLEX
	tooth.frequency = 0.09
	tooth.fractal_octaves = 2
	tooth.seed = 0x0C1A
	# Stretched hard along one diagonal, which is what turns noise into strokes.
	var chip := FastNoiseLite.new()
	chip.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	chip.frequency = 0.22
	chip.fractal_octaves = 3
	chip.seed = 0x7E3D

	var height := PackedFloat32Array()
	height.resize(size * size)
	var edge := float(size) * 0.055
	for y: int in size:
		for x: int in size:
			var u := float(x)
			var v := float(y)
			# Two crossing sets of strokes, each sampled along its own diagonal.
			var a := tooth.get_noise_2d((u + v) * 0.5, (u - v) * 3.0)
			var b := tooth.get_noise_2d((u - v) * 0.5 + 400.0, (u + v) * 3.0)
			var h := 0.5 + 0.26 * a + 0.18 * b
			h += 0.10 * chip.get_noise_2d(u, v)
			# The chamfer: a margin round all four sides that falls away.
			var near := minf(minf(u, float(size - 1) - u), minf(v, float(size - 1) - v))
			if near < edge:
				h -= (1.0 - near / edge) * 0.55
			height[y * size + x] = clampf(h, 0.0, 1.0)

	for y: int in size:
		for x: int in size:
			var h := height[y * size + x]
			var shade := 0.72 + 0.34 * h
			albedo.set_pixel(x, y, Color(shade, shade, shade))
			var hx: float = height[y * size + posmod(x + 1, size)]
			var hy: float = height[posmod(y + 1, size) * size + x]
			var n := Vector3((h - hx) * 3.0, (h - hy) * 3.0, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))

	albedo.generate_mipmaps()
	normal.generate_mipmaps()
	var out: Array[Image] = [albedo, normal]
	return out


## Brick, in running bond, one metre to the tile: four stretchers across and
## twelve courses up, which is a 250 x 83 mm brick and a real one.
##
## The mortar is cut *into* the height field rather than painted on, so it reads
## as a recessed joint under the normal map instead of as a grid drawn on a flat
## wall — which is the difference between brickwork and a brick-coloured box.
## Every brick gets its own lightness off a hash of its course and position, and
## the bench is 4 m tall, so without that variation the eye finds the tile
## immediately.
func _brick_images() -> Array[Image]:
	var size := 256
	var albedo := Image.create(size, size, false, Image.FORMAT_RGB8)
	var normal := Image.create(size, size, false, Image.FORMAT_RGB8)
	var courses := 12
	var across := 4
	var mortar := 0.055           # of a course, each side of a joint
	var grain := FastNoiseLite.new()
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grain.frequency = 0.18
	grain.fractal_octaves = 3
	grain.seed = 0xB12C

	var height := PackedFloat32Array()
	height.resize(size * size)
	var tone := PackedFloat32Array()
	tone.resize(size * size)
	for y: int in size:
		var v := float(y) / float(size) * float(courses)
		var course := int(floor(v))
		var in_course := v - float(course)
		# Running bond: every other course slides half a brick along.
		var shift := 0.5 if course % 2 == 1 else 0.0
		for x: int in size:
			var u := float(x) / float(size) * float(across) + shift
			var brick := int(floor(u))
			var in_brick := u - float(brick)
			var joint := in_course < mortar or in_course > 1.0 - mortar \
				or in_brick < mortar * 0.5 or in_brick > 1.0 - mortar * 0.5
			var h := 0.28 if joint else 1.0
			# Each brick its own face, slightly dished, plus a little grain.
			if not joint:
				var dish := 1.0 - 0.10 * (absf(in_brick - 0.5) + absf(in_course - 0.5))
				h *= dish
				h += 0.05 * grain.get_noise_2d(float(x), float(y))
			height[y * size + x] = clampf(h, 0.0, 1.0)
			var id := float(((brick * 73856093) ^ (course * 19349663)) % 1000) / 1000.0
			tone[y * size + x] = 0.62 if joint else lerpf(0.78, 1.08, absf(id))

	for y: int in size:
		for x: int in size:
			var h := height[y * size + x]
			var shade: float = tone[y * size + x] * (0.80 + 0.28 * h)
			albedo.set_pixel(x, y, Color(clampf(shade, 0.0, 1.0),
				clampf(shade, 0.0, 1.0), clampf(shade, 0.0, 1.0)))
			var hx: float = height[y * size + posmod(x + 1, size)]
			var hy: float = height[posmod(y + 1, size) * size + x]
			var n := Vector3((h - hx) * 3.4, (h - hy) * 3.4, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))

	albedo.generate_mipmaps()
	normal.generate_mipmaps()
	var out: Array[Image] = [albedo, normal]
	return out


## Crushed stone underfoot: noise between two greys, seamless, one tile every
## four metres at the uv scale the materials set.
func _grit_texture(seed: int, frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 4
	noise.seed = seed
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.44, 0.42, 0.38))
	ramp.set_color(1, Color(0.92, 0.90, 0.85))
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.seamless = true
	texture.width = 512
	texture.height = 512
	texture.color_ramp = ramp
	return texture


func _group(named: String, under: Node3D = null) -> Node3D:
	var node := Node3D.new()
	node.name = named
	(under if under != null else self).add_child(node)
	return node
