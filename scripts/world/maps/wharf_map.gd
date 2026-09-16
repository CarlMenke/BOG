class_name WharfMap
extends StaticMap
## Lantern Wharf — a walled box yard at dusk, small, dense and symmetric on
## purpose, built in code from layout tables the way Kopje Crossing is (D-042).
##
## It is the opposite map to the savanna. Kopje Crossing is 96 m of long
## sightlines and a hundred and twenty climbs; this is 36 m square, walled in by
## container stacks three high, with two bases facing each other across a grid
## of painted boxes that never lets you see more than about twenty metres. The
## shape is borrowed from the small symmetric two-base box maps other shooters
## are known for; the geometry, the props and the name are this game's own
## (D-056).
##
## Three kinds of thing stand in the yard, and each has one job:
##
##   crates      1.2 m. Low cover, and the step up — a hop from the ground.
##   singles     one container, 2.6 m. Hard cover you can climb onto from a
##               crate, which is all the verticality the map has. Four of the
##               six are **open**: doors swung back and hollow inside, so the
##               cover is also a six-metre covered corridor you run through.
##   towers      three containers, 7.8 m, and the perimeter walls. The things
##               that cut sightlines, and out of reach of every jump in the
##               Gub's kit, the one-tick dive included — `tools/parkour_report`
##               fails the build if one can be reached (`off_limits`).
##
## And the works: a forklift, painted drums, pallets and pipe stock, all of it
## **solid** and all of it built before `super()`, because a box at chest height
## that a spear flies through is the one lie this map must not tell (D-060).
##
## There is no two-high stack anywhere, and that is deliberate. The dive off a
## jump reaches 4.2 m of rise, so a 5.2 m stack beside a 2.6 m single is a stack
## somebody climbs, and from 5.2 m every single roof on the map is in view.
##
## The north half is written out in the tables and the south half is its mirror
## across z = 0, so neither team has an edge. Entries on z = 0 are placed once.
##
## Build order is Kopje Crossing's and the rule is the same: everything added
## before `super()` is swept into collision — the boxes, the crates and the works
## — and everything after is dressing: the floor paint, the door bars, the cranes
## over the wall, the floodlights, the Factory Kit plant and the town outside.
## Nothing on this map is random, so every peer builds the same yard by
## construction rather than by a shared seed.

# ---------------------------------------------------------------- the table ---

## Half the yard's width. The walls' inner faces stand on these lines.
const HALF := 18.0

## A container, as length x height x width. A Gub is 1.55 m tall, so a single
## box is a head and a half over one and a crate is chest height.
const BOX_LENGTH := 6.0
const BOX_HEIGHT := 2.6
const BOX_WIDTH := 2.4
const CRATE := Vector3(1.5, 1.2, 1.5)

## How far into a single's length each of its two landing records sits. The
## parkour report reads a landing as a circle; one circle in the middle of a 6 m
## box would call its two ends unlandable.
const LANDING_OFFSET := 1.95
## Inscribed landing radius of a box's top: half its width less 0.15 m of lip.
const BOX_LANDING := BOX_WIDTH * 0.5 - 0.15
const CRATE_LANDING := CRATE.x * 0.5 - 0.15

## The walls: container stacks laid along each side, three high, centred on
## these offsets along the side. Seven boxes of 6 m is 42 m, so the corners
## overlap and no corner shows daylight.
const WALL_TIERS := 3
const WALL_CENTRES: PackedFloat32Array = [-18.0, -12.0, -6.0, 0.0, 6.0, 12.0, 18.0]
## Wall boxes that carry a fourth tier, by (side, index). Not reachable either —
## it is higher than a tier that already is not — and it gives the skyline over
## the wall a broken edge instead of a ruler.
const WALL_EXTRA: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, 5), Vector2i(2, 3),
	Vector2i(3, 3)]

## Every box inside the yard, north half. `at` is the centre on (x, z), `axis`
## the direction the box's length runs in, `tiers` 1 for a single and 3 for a
## tower, and `paint` indexes `PAINTS` bottom tier first. `open` hollows a
## single out into a corridor — see `_open_container_mesh` for what that costs.
##
## The layout was searched for rather than drawn, and then read and trimmed by
## hand: a 36 m square has 51 m diagonals, and the only way to keep every line
## under 25 m is to put something tall across most of them. The two things that
## decided it are in the comments below. See D-056 for the search.
const BOXES: Array[Dictionary] = [
	# The base bay: two towers out from the back wall either side of the base,
	# so the strip along the back wall — the one line on the map nobody can
	# avoid crossing — is three rooms and not a 34 m lane.
	{"label": "bay west", "at": Vector2(-4.5, -15.0), "axis": "z", "tiers": 3, "paint": [1, 6, 0]},
	{"label": "bay east", "at": Vector2(4.5, -15.0), "axis": "z", "tiers": 3, "paint": [0, 5, 2]},
	# The spine in front of the base, so the far base never sees into this one.
	{"label": "spine", "at": Vector2(0.0, -9.0), "axis": "z", "tiers": 3, "paint": [3, 2, 4]},
	# The two climbable boxes on each side's approach, and the two you can run
	# *through*: these four (with their mirrors) are the map's open containers.
	# They are the ones hollowed out rather than four new boxes somewhere else
	# because their footprints came out of D-056's search and hollowing changes
	# no footprint at all — the yard a Gub walks round is the yard that was
	# searched for, to the centimetre. What changes is that the east-west aisle
	# at z = ±7.5 now has a door in it. See `_open_container_mesh` for why these
	# two and not the flank singles, which are the only thing standing between
	# the north wall and the south wall at x = ±11.5.
	{"label": "yard west", "at": Vector2(-7.0, -7.5), "axis": "x", "tiers": 1, "paint": [2],
		"open": true},
	{"label": "yard east", "at": Vector2(7.0, -7.5), "axis": "x", "tiers": 1, "paint": [1],
		"open": true},
	# Against the side walls, closing the corners' diagonals.
	{"label": "wall west", "at": Vector2(-15.0, -6.0), "axis": "x", "tiers": 3, "paint": [5, 4, 3]},
	{"label": "wall east", "at": Vector2(15.0, -6.0), "axis": "x", "tiers": 3, "paint": [4, 1, 6]},
	# The middle: four towers round a crossroads, with G standing in it.
	{"label": "centre west", "at": Vector2(-4.0, -3.0), "axis": "x", "tiers": 3, "paint": [6, 0, 1]},
	{"label": "centre east", "at": Vector2(4.0, -3.0), "axis": "x", "tiers": 3, "paint": [2, 3, 0]},
	# On the centre line, each placed once: the climbable boxes beside U and B.
	{"label": "flank west", "at": Vector2(-11.5, 0.0), "axis": "z", "tiers": 1, "paint": [0]},
	{"label": "flank east", "at": Vector2(11.5, 0.0), "axis": "z", "tiers": 1, "paint": [5]},
]

## Crates, north half, as (x, z). Same mirror rule as the boxes. Each is laid
## flush against something: a crate with a gap under a metre beside a box is a
## slot a Gub gets stuck in, and flush it is a step.
const CRATES: Array[Vector2] = [
	# The steps onto the yard boxes, from the base side.
	Vector2(-8.0, -9.45), Vector2(8.0, -9.45),
	# Low cover in the base bay, against the foot of the spine.
	Vector2(0.0, -12.75),
	# The steps onto the flank boxes, from the middle.
	Vector2(-9.55, 0.0), Vector2(9.55, 0.0),
]

## Painted steel, bright on purpose. Rust is a yard of rusted brown boxes under a
## noon sun; this one is a yard of red, blue, yellow and green boxes under
## floodlights, and at dusk it is the paint that tells one aisle from the next.
const PAINTS: Array[Color] = [
	Color(0.70, 0.14, 0.11),   # 0 signal red
	Color(0.11, 0.30, 0.62),   # 1 harbour blue
	Color(0.86, 0.60, 0.10),   # 2 hazard yellow
	Color(0.14, 0.46, 0.30),   # 3 dock green
	Color(0.86, 0.36, 0.09),   # 4 tangerine
	Color(0.08, 0.48, 0.52),   # 5 teal
	Color(0.80, 0.76, 0.68),   # 6 cream
]

## The floodlights: one mast on each corner of the wall, lamp head this high over
## the yard floor, each aimed at a point this far in from its corner. Aimed short
## of the middle so the four pools overlap in the middle and every base gets two.
const MAST_TOP := 13.5
const MAST_AIM := 13.0
const FLOOD_COLOUR := Color(1.0, 0.80, 0.52)
const FLOOD_ENERGY := 5.0
const FLOOD_RANGE := 42.0
const FLOOD_ANGLE := 48.0

## The cranes standing outside the north and south walls. Scenery only.
const CRANE_Z := 27.0
const CRANE_SPAN := 16.0
const CRANE_HEIGHT := 18.0

## How far the floor runs: to the outer face of the walls and no further, so
## from above the yard ends where its walls do. There is no way off it, and
## `void_height` is a safety net rather than a rule anyone meets.
const FLOOR_EDGE := HALF + BOX_WIDTH
## Wall boxes are the palette darkened this much. The walls are the edge of the
## map, not part of the fight, and a boundary as bright as the cover in front of
## it is a map where the cover does not stand out.
const WALL_SHADE := 0.62

# ------------------------------------------------------------- the works ---

## The machinery standing on the concrete: a forklift at each loading bay, drums
## against the walls and the spine, pallets and pipe stock. **All of it is built
## before `super()` and is therefore collision**, and that is the whole reason it
## is allowed to exist at all.
##
## D-060 put the Factory Kit up the walls and flat on the floor and left the
## aisles empty, under a rule it stated in one line: nothing between 0.3 m and
## 2.4 m anywhere a Gub can walk, unless it is real. A forklift is 2.5 m to the
## top of its guard and a drum is 0.9 m — both of them are exactly the height at
## which a player decides whether to duck — so the only honest way to put them in
## an aisle is to make them solid. They are, so they are cover, and cover shortens
## sightlines rather than lengthening them: every one of these is a new blocker
## standing where there used to be air, which is why the ground number can only
## have got better. What they *do* add is new places to stand, and every one of
## those is declared below, because undeclared standable geometry is invisible to
## `parkour_report` and that is the failure D-042 and D-056 exist to prevent.
##
## The rule these shapes are built to, and it is geometry rather than an
## assertion: **every flat top a Gub's capsule can find a floor on is a declared
## `Platform`.** A drum lid is 0.60 m across and declared; a guard rail is 0.08 m
## across, which is narrower than the sphere on the bottom of the capsule, so the
## contact there is an edge and a Gub slides off it. Nothing on any of these
## props is in between, and that is a thing the shapes were adjusted to make true
## rather than a thing they happened to be — see `FORKLIFT_DECK`.

## The forklift, as a table, north half, mirrored across z = 0 like everything
## else. `at` is the middle of the machine on the ground; it is built facing its
## own -x and `yaw` turns it. One per end, flush against the outboard end of the
## bay tower, in the loading bay the floor paint already marks (D-060).
const FORKLIFTS: Array[Dictionary] = [
	{"at": Vector2(-4.50, -11.35), "yaw": 0.0},
]

## The forklift's one landing, local to the machine so the mirror gets it for
## free: the deck that runs from the driver's feet back over the counterweight,
## **1.20 m up, which is a crate**. That is the whole of the machine you can
## stand on, and it took a measurement to settle rather than a preference.
##
## The first forklift had a plated overhead guard at 2.60 m — a single
## container's roof — declared as a second landing. It measured a 30.4 m
## eye-to-eye line diagonally across the yard, against a limit of 26, and moving
## the machine 40 cm east took the same perch to 18.2 m. A 2.6 m perch in this
## yard is not a little over or a little under: it is over the top of every
## single and every crate on the map, and whether it sees eleven metres or
## thirty-one is decided by whether one tower happens to be in the way. D-056
## refused to ship a roof number that passed by three centimetres for exactly
## that reason, and a perch that swings twelve metres over forty is worse.
##
## So the guard is an open frame — four posts and the rails across their tops —
## and the highest flat thing on the machine is a 0.08 m rail. A Gub's capsule is
## 0.38 m across and its underside is a sphere: on a face narrower than a few
## centimetres it meets an *edge*, the contact normal is not up, and it slides
## off. That is the line between the drum lids below (0.60 m across, declared,
## stood on all day) and these rails, and it is geometry rather than an opinion.
const FORKLIFT_DECK := Vector3(0.60, 1.20, 0.0)
const FORKLIFT_DECK_LANDING := 0.50

## Drums. `at` is the barrel's centre on the floor, `lying` puts it on its side
## along `along`, and `paint` indexes `PAINTS`. Upright is 0.90 m to a flat lid
## and on its side it is 0.60 m to the curve of the shell; **both are declared**,
## because a Gub can stand on either and a 0.15 m landing record is cheap next to
## a perch the checker has never heard of.
##
## Every group stands half a metre off the steel it leans against rather than
## flush: `parkour_report` stands a 0.38 m capsule on each landing, and a drum
## pushed right up against a container is a drum whose own landing fails the
## check with the container standing in it.
const BARREL_RADIUS := 0.30
const BARREL_HEIGHT := 0.90
const BARREL_LANDING := 0.15
const BARRELS: Array[Dictionary] = [
	# Against the west and east faces of the spine, in the two aisles either side
	# of the base's back stop.
	{"at": Vector2(-1.70, -8.40), "paint": 1},
	{"at": Vector2(-1.70, -7.68), "paint": 0},
	{"at": Vector2(-1.70, -9.40), "paint": 3, "lying": "z"},
	{"at": Vector2(1.70, -8.40), "paint": 3},
	{"at": Vector2(1.70, -7.68), "paint": 2},
	{"at": Vector2(1.70, -9.40), "paint": 0, "lying": "z"},
	# Against the outboard faces of the two wall towers.
	{"at": Vector2(-16.00, -7.70), "paint": 0},
	{"at": Vector2(-15.28, -7.70), "paint": 5},
	{"at": Vector2(-14.20, -7.70), "paint": 1, "lying": "x"},
	{"at": Vector2(16.00, -7.70), "paint": 2},
	{"at": Vector2(15.28, -7.70), "paint": 0},
	{"at": Vector2(14.20, -7.70), "paint": 5, "lying": "x"},
	# Stacked off the yard crates, in the open aisle between them and the base.
	{"at": Vector2(-8.00, -10.70), "paint": 4},
	{"at": Vector2(-8.72, -10.70), "paint": 0},
	{"at": Vector2(-9.90, -10.70), "paint": 2, "lying": "x"},
	{"at": Vector2(8.00, -10.70), "paint": 0},
	{"at": Vector2(8.72, -10.70), "paint": 3},
	{"at": Vector2(9.90, -10.70), "paint": 4, "lying": "x"},
]
## **None of these lean on a perimeter wall, and that is measured rather than
## stylistic.** A drum is a 0.9 m perch with its eyes at 2.35 m, which is over the
## crates and under the singles — harmless in the middle of the yard, where every
## one of these measures 13-18 m. Half a metre off the back wall it is something
## else: the sightline scan samples the ground on a 2 m grid whose outermost row
## is 1 m inside the steel, so a drum against the wall is a standing place
## *further out than the map has ever been measured at*, on the one axis where a
## 36 m yard has 36 m to give. The first draft put six of them there and took two
## existing crate tops from 25.0 m to 27.4 m. They came back inside instead.

## Pallets, stacked two high, and bundles of pipe stock lying on the concrete.
## Both are **28 cm** tall, which is under D-060's own 0.3 m line: they are floor
## furniture you stride over, not cover, so they get collision (a stack you walk
## through is as much of a lie as a crate you shoot through) and no landing
## record, because standing on one puts a Gub's eyes 28 cm up.
const PALLET := Vector3(1.20, 0.14, 0.80)
const PALLETS: Array[Vector2] = [
	Vector2(-9.0, -5.7), Vector2(9.0, -5.7),
	Vector2(-14.5, -2.2), Vector2(14.5, -2.2),
	Vector2(-2.0, -10.2), Vector2(2.0, -10.2),
]
## Five tubes side by side, `PIPE_STOCK_LENGTH` long, laid along z.
const PIPE_STOCK_RADIUS := 0.14
const PIPE_STOCK_LENGTH := 4.0
const PIPE_STOCK: Array[Vector2] = [
	Vector2(-6.40, -15.0), Vector2(6.40, -15.0),
]

# ------------------------------------------------------------- the city ---

## Kenney's City Kit (Industrial), used for one thing only: the town the wharf
## stands in. Every piece of it is **outside the perimeter wall**, after
## `super()` and therefore never collision, and in `StaticMap.BACKDROP_GROUP` so
## `tools/preview_map.gd` still frames a 36 m yard and not a 180 m skyline
## (D-057 added that group for the yacht's sea and this is the same job).
##
## The kit is a diorama kit — `building-a` is 1.47 m tall in its own file — so
## everything here is scaled by an order of magnitude. That is not a bodge: the
## number that matters is the angle a building subtends over a 7.8 m wall seen
## from the middle of the yard, and at 50-90 m out nothing under about 20 m of
## height clears the wall at all. A skyline that does not clear the wall is a
## skyline nobody in a match will ever see.
const CITY_SEED := 0xC17A
## The grid the town is laid out on, how far a piece may wander off its cell, and
## how many cells are left empty so a town reads as blocks and gaps rather than
## as wallpaper.
##
## **The stand-off is the number that matters and it is not the one you would
## guess.** A block at 10-16x is 20-35 m across, so a rule that only asks where
## its *origin* is puts half a building inside the yard: the first draft allowed
## cells from 22 m out and dropped two enormous grey slabs over the west wall.
## The near ring is therefore 44 m out, which is where a 35 m building's near
## face is still 26 m clear of a wall that stands at 20.4 m.
const CITY_STRIDE := 14.0
const CITY_REACH := 112.0
const CITY_JITTER := 4.2
const CITY_GAPS := 0.34
const CITY_NEAR := 44.0
## The crane lane is wider than the cranes, for the same footprint reason: a
## building centred 34 m off the centre line still has its near face clear of the
## legs at x = -12 to 4.
const CITY_CRANE_X := 34.0
const CITY_CRANE_Z := 72.0
## Scale, as a range. 10x makes `building-a` 15 m and 16x makes `building-l` 31 m.
const CITY_SCALE := Vector2(10.0, 16.0)
## What the town is made of, the common pieces repeated so blocks read as blocks.
const CITY_MODELS: PackedStringArray = ["building-a", "building-b", "building-c",
	"building-d", "building-e", "building-f", "building-g", "building-l",
	"building-m", "building-n", "building-q", "building-r", "building-t",
	"building-a", "building-g", "building-r", "building-e",
	"chimney-large", "chimney-medium", "detail-tank-large", "detail-tank",
	"water-tower", "windmill", "windmill-low"]

## The apron outside the west and east walls: low stacks of the kit's own
## containers, at a scale that makes them the same 6 x 2.6 x 2.4 box the yard is
## built of, so the yard reads as a corner of something bigger rather than as a
## box with nothing behind it. Two and three high, which over a 7.8 m wall is a
## broken lip of colour and nothing more.
const CITY_CONTAINER_SCALE := 1.97
const CITY_CONTAINERS: Array[Vector3] = [
	Vector3(-24.0, -12.0, 3.0), Vector3(-24.0, -4.0, 2.0), Vector3(-24.0, 5.0, 3.0),
	Vector3(-30.0, -8.0, 2.0), Vector3(-30.0, 1.0, 3.0), Vector3(-30.0, 10.0, 2.0),
	Vector3(24.0, 12.0, 3.0), Vector3(24.0, 4.0, 2.0), Vector3(24.0, -5.0, 3.0),
	Vector3(30.0, 8.0, 2.0), Vector3(30.0, -1.0, 3.0), Vector3(30.0, -10.0, 2.0),
]

# ------------------------------------------------------------ the plant ---

## Kenney's Factory Kit, bolted to the walls and painted on the floor (D-060).
##
## The containers are not made of this and cannot be: the kit has no container in
## it, and more to the point the boxes *are* the map — the layout was searched
## against a 25 m sightline and a jump that must not reach a tower top (D-056),
## so their geometry is not dressing and is not up for redecorating. What the kit
## adds is the plant around them, which the map previously only implied.
##
## **Everything here is either above head height or flat on the ground**, and
## that rule is doing more work on this map than it did on the quarry. Lantern
## Wharf is a box yard whose whole grammar is "this is cover, that is not" — a
## crate is 1.2 m and hides you, a single is 2.6 m and hides you, and both are
## solid. A 1.5 m machine standing in an aisle that a spear flies straight
## through is a lie the player finds out about by dying, so there is nothing here
## between 0.3 m and 2.4 m anywhere a Gub can walk.
##
## Pipes run at 3.2 m and 4.4 m up the inner wall faces; machinery stands on the
## wall tops at 7.8 m, where `parkour_report` has already proved nobody can get;
## and the floor gets arrows and markings a centimetre thick.
const PLANT_SEED := 0xFAC7

## The pipe runs: one per side per height, as a span along the wall in metres.
## Kit pieces are exactly 1 m, so a run is `ceil(length)` pieces laid end to end
## and the joins land on whole metres by construction.
const PIPE_HEIGHTS: PackedFloat32Array = [3.2, 4.4]
const PIPE_INSET := 0.62
const PIPE_RUNS: Array[Vector2] = [
	Vector2(-16.0, -4.0), Vector2(2.0, 15.0),
]
## One piece in this many is a valve or a bump rather than a plain length, so a
## run reads as plumbing instead of as a tube.
const PIPE_FITTING_EVERY := 5

## What stands on top of the perimeter wall, at `BOX_HEIGHT * WALL_TIERS`. Out of
## reach of every jump in the game — that is a thing the gate proves, not a thing
## this comment claims — so it can be as tall and as solid-looking as it likes.
const SKYLINE: PackedStringArray = ["hopper-square", "hopper-round", "machine",
	"machine-window", "machine-fortified", "scanner-high", "cog-a", "cog-c",
	"piston-round", "robot-arm-a"]
const SKYLINE_STRIDE := 6.0
const SKYLINE_SCALE := Vector2(0.9, 1.5)

## Flat on the floor, a centimetre up, casting nothing. These are the only kit
## pieces a Gub ever walks over, and every one of them is a decal in all but
## name.
const FLOOR_MARKS: PackedStringArray = ["indicator-special-arrow",
	"indicator-special-lines", "indicator-special-area", "indicator-special-cross"]
## Panels bolted to the wall faces beside each base, at head height and flat
## against the steel.
const PANELS: PackedStringArray = ["screen-panel-wide", "screen-panel-small",
	"screen-flat", "screen-wide", "lever-double", "lever-single"]
const PANEL_HEIGHT := 2.5

# ------------------------------------------------------------------ state ---

## Box counts, for the build log and the decision record.
var singles: int = 0
var towers: int = 0
var crates: int = 0
var wall_boxes: int = 0
var open_boxes: int = 0
var barrels: int = 0

var _mesh_cache: Dictionary = {}
var _paint_materials: Array[StandardMaterial3D] = []
var _wall_materials: Array[StandardMaterial3D] = []
var _crate_material: StandardMaterial3D
var _floor_material: StandardMaterial3D
var _paint_line: StandardMaterial3D
var _steel: StandardMaterial3D
var _lamp: StandardMaterial3D
var _forklift_paint: StandardMaterial3D
var _timber: StandardMaterial3D


func _ready() -> void:
	var started := Time.get_ticks_msec()
	_build_materials()

	_build_floor(_group("Floor"))
	_build_walls(_group("Walls"))
	_build_yard(_group("Yard"))
	_build_works(_group("Works"))

	print("%s: %d singles (%d open), %d towers, %d crates, %d barrels, %d wall boxes, "
		% [name, singles, open_boxes, towers, crates, barrels, wall_boxes]
		+ "%d landings in %d ms" % [platforms.size(), Time.get_ticks_msec() - started])

	# Everything above this line becomes collision. Everything below it does not.
	super()

	var dressing := _group("Dressing")
	_build_paint(dressing)
	_build_door_bars(dressing)
	_build_cranes(dressing)
	_build_floodlights(dressing)
	_build_plant(dressing)
	_build_city(dressing)


# ------------------------------------------------------------------ layout ---

## Both halves of a table entry: the one written, and its mirror across z = 0
## unless it stands on that line.
static func mirrored(at: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = [at]
	if absf(at.y) > 0.001:
		out.append(Vector2(at.x, -at.y))
	return out


func _build_floor(parent: Node3D) -> void:
	var node := MeshInstance3D.new()
	node.name = "Yard"
	node.mesh = _quad(Vector2(FLOOR_EDGE, FLOOR_EDGE) * 2.0, 6.0)
	node.material_override = _floor_material
	parent.add_child(node)


## Seven boxes a side, three high, along all four sides.
##
## Side 0 is north (z = -), 1 south, 2 west (x = -), 3 east. The paint walks the
## palette at a stride that no two neighbouring boxes, above or beside, share.
func _build_walls(parent: Node3D) -> void:
	var offset := HALF + BOX_WIDTH * 0.5
	for side: int in 4:
		for i: int in WALL_CENTRES.size():
			var along := WALL_CENTRES[i]
			var at := Vector2(along, -offset) if side == 0 \
				else Vector2(along, offset) if side == 1 \
				else Vector2(-offset, along) if side == 2 \
				else Vector2(offset, along)
			var axis := "x" if side < 2 else "z"
			var tiers := WALL_TIERS + (1 if WALL_EXTRA.has(Vector2i(side, i)) else 0)
			for tier: int in tiers:
				var paint := (side * 3 + i * 2 + tier * 5) % PAINTS.size()
				_box(parent, at, axis, tier, paint, true)
				wall_boxes += 1
			var top := BOX_HEIGHT * float(tiers)
			off_limits.append(Platform.new(Vector3(at.x, top, at.y), BOX_LANDING, "wall",
				"wall %d.%d" % [side, i]))


func _build_yard(parent: Node3D) -> void:
	for entry: Dictionary in BOXES:
		var tiers := int(entry["tiers"])
		var paints: Array = entry["paint"]
		var axis := String(entry["axis"])
		var open := bool(entry.get("open", false))
		for at: Vector2 in mirrored(entry["at"]):
			var side := "N" if at.y < -0.001 else "S" if at.y > 0.001 else "C"
			var label := "%s %s" % [entry["label"], side]
			for tier: int in tiers:
				_box(parent, at, axis, tier, int(paints[tier % paints.size()]), false, open)
			if open:
				open_boxes += 1
			var along := Vector2(LANDING_OFFSET, 0.0) if axis == "x" \
				else Vector2(0.0, LANDING_OFFSET)
			var top := BOX_HEIGHT * float(tiers)
			for end: int in 2:
				var spot := at + along * (1.0 if end == 0 else -1.0)
				var record := Platform.new(Vector3(spot.x, top, spot.y), BOX_LANDING,
					"tower" if tiers > 1 else "single", "%s %s" % [label, "ab"[end]])
				if tiers > 1:
					off_limits.append(record)
				else:
					platforms.append(record)
			if tiers > 1:
				towers += 1
			else:
				singles += 1

	for spot: Vector2 in CRATES:
		for at: Vector2 in mirrored(spot):
			var node := MeshInstance3D.new()
			node.mesh = _crate_mesh()
			node.material_override = _crate_material
			node.position = Vector3(at.x, 0.0, at.y)
			parent.add_child(node)
			platforms.append(Platform.new(Vector3(at.x, CRATE.y, at.y), CRATE_LANDING,
				"crate", "crate %+.1f,%+.1f" % [at.x, at.y]))
			crates += 1


## One container: a box with its own UVs, standing on `tier` others. `open` swaps
## the solid shell for the hollow one with its doors swung back.
func _box(parent: Node3D, at: Vector2, axis: String, tier: int, paint: int,
		wall: bool = false, open: bool = false) -> void:
	var node := MeshInstance3D.new()
	node.mesh = _open_container_mesh() if open else _container_mesh()
	node.material_override = (_wall_materials if wall else _paint_materials)[paint]
	var yaw := 0.0 if axis == "x" else PI * 0.5
	node.transform = Transform3D(Basis(Vector3.UP, yaw),
		Vector3(at.x, BOX_HEIGHT * float(tier), at.y))
	parent.add_child(node)


# ------------------------------------------------------------- the works ---

## Everything standing on the concrete that is not a container, built here and
## therefore swept into collision by `super()` a few lines later.
##
## Read the comment on `FORKLIFTS` above for why this is the only place it could
## go. The short version is D-060's rule: on a map whose whole grammar is "this
## is cover and that is not", a body-height prop is either solid or it is a lie,
## and a forklift is very much body height.
func _build_works(parent: Node3D) -> void:
	for entry: Dictionary in FORKLIFTS:
		var copies := mirrored(entry["at"])
		for i: int in copies.size():
			# Mirroring a position across z = 0 mirrors the heading with it, which
			# for a rotation about the vertical means negating the yaw. A forklift
			# facing west stays facing west; one facing north would face south.
			_forklift(parent, copies[i], float(entry["yaw"]) * (1.0 if i == 0 else -1.0))

	for entry: Dictionary in BARRELS:
		var lying := String(entry.get("lying", ""))
		for at: Vector2 in mirrored(entry["at"]):
			_barrel(parent, at, lying, int(entry["paint"]))

	for spot: Vector2 in PALLETS:
		for at: Vector2 in mirrored(spot):
			_prop(parent, _pallet_mesh(), _timber, at, 0.0)

	for spot: Vector2 in PIPE_STOCK:
		for at: Vector2 in mirrored(spot):
			_prop(parent, _pipe_stock_mesh(), _steel, at, 0.0)


## One cached mesh, dropped on the floor at `at` and turned by `yaw`.
func _prop(parent: Node3D, mesh: Mesh, material: StandardMaterial3D, at: Vector2,
		yaw: float) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, 0.0, at.y))
	parent.add_child(node)


## A forklift, and its two landing records.
##
## The machine is two meshes rather than one because it is two colours, and both
## are cached: the map builds two of these and there is no reason to lay out the
## same forty boxes twice. The landings are in machine space and pushed through
## the same transform as the geometry, so the mirrored copy's records cannot
## drift away from its steel — which is exactly the bug `parkour_report`'s ray
## test exists to catch, and there is no reason to hand it one to catch.
func _forklift(parent: Node3D, at: Vector2, yaw: float) -> void:
	var xform := Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, 0.0, at.y))
	var node := MeshInstance3D.new()
	node.name = "Forklift"
	node.mesh = _forklift_mesh(true)
	node.material_override = _forklift_paint
	node.transform = xform
	parent.add_child(node)
	var steel := MeshInstance3D.new()
	steel.name = "ForkliftSteel"
	steel.mesh = _forklift_mesh(false)
	steel.material_override = _steel
	steel.transform = xform
	parent.add_child(steel)

	platforms.append(Platform.new(xform * FORKLIFT_DECK, FORKLIFT_DECK_LANDING,
		"forklift", "forklift %+.0f deck" % at.y))


## One drum, upright or on its side, and the landing on top of it.
##
## The lid of an upright drum is 0.30 m across and a Gub's capsule is 0.38 m: it
## does not *fit* on the lid, it balances on it, and it balances perfectly well
## because the contact is the bottom of a capsule against a flat face pointing
## straight up. That is a place to stand, so it is a `Platform` with a 0.15 m
## landing radius, and the parkour graph can decide for itself that nothing worth
## reaching is reachable from it.
func _barrel(parent: Node3D, at: Vector2, lying: String, paint: int) -> void:
	var xform := Transform3D.IDENTITY
	var top := BARREL_HEIGHT
	if lying == "z":
		# Turned onto its side about x, so the shell's axis lies along z, then
		# lifted onto its own radius and slid back by half its length so the
		# table's `at` is still the middle of the drum and not its end cap.
		xform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5),
			Vector3(at.x, BARREL_RADIUS, at.y + BARREL_HEIGHT * 0.5))
		top = BARREL_RADIUS * 2.0
	elif lying == "x":
		xform = Transform3D(Basis(Vector3.BACK, -PI * 0.5),
			Vector3(at.x - BARREL_HEIGHT * 0.5, BARREL_RADIUS, at.y))
		top = BARREL_RADIUS * 2.0
	else:
		xform = Transform3D(Basis.IDENTITY, Vector3(at.x, 0.0, at.y))

	var node := MeshInstance3D.new()
	node.mesh = _barrel_mesh()
	node.material_override = _paint_materials[paint % _paint_materials.size()]
	node.transform = xform
	parent.add_child(node)
	platforms.append(Platform.new(Vector3(at.x, top, at.y), BARREL_LANDING, "barrel",
		"drum %+.1f,%+.1f" % [at.x, at.y]))
	barrels += 1


# ---------------------------------------------------------------- dressing ---

## Floor paint: a yellow line a metre in from every wall, and a loading bay
## marked round each base. Decals rather than texture, a centimetre up and casting no
## shadow, so the concrete's noise tile does not have to know where the bases are.
func _build_paint(parent: Node3D) -> void:
	var inset := HALF - 1.0
	var width := 0.14
	for flip: float in [-1.0, 1.0]:
		_stripe(parent, Vector3(0.0, 0.0, flip * inset), Vector2(inset * 2.0, width))
		_stripe(parent, Vector3(flip * inset, 0.0, 0.0), Vector2(width, inset * 2.0))
	var bases := base_points()
	for base: Vector3 in bases:
		# The bay between the two towers, which is 6.6 m across.
		var half := Vector2(3.0, 2.5)
		for flip: float in [-1.0, 1.0]:
			_stripe(parent, base + Vector3(0.0, 0.0, flip * half.y), Vector2(half.x * 2.0, width))
			_stripe(parent, base + Vector3(flip * half.x, 0.0, 0.0), Vector2(width, half.y * 2.0))


func _stripe(parent: Node3D, centre: Vector3, size: Vector2) -> void:
	var node := MeshInstance3D.new()
	node.mesh = _quad(size, 1.0)
	node.material_override = _paint_line
	node.position = Vector3(centre.x, 0.012, centre.z)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


## Four locking bars down one end of every yard box. Twelve triangles each and
## the single cheapest thing that makes a painted box read as a container.
##
## The open containers are skipped here: their doors are hanging back against
## their own sides, with the bars modelled on the leaves, and those are part of
## the shell and therefore part of the collision. A closed door is dressing; an
## open one is something you can walk into the back of.
func _build_door_bars(parent: Node3D) -> void:
	var bars := SurfaceTool.new()
	bars.begin(Mesh.PRIMITIVE_TRIANGLES)
	for entry: Dictionary in BOXES:
		if bool(entry.get("open", false)):
			continue
		var axis := String(entry["axis"])
		for at: Vector2 in mirrored(entry["at"]):
			for tier: int in int(entry["tiers"]):
				# The door end faces the middle of the map along the box's axis.
				# Local +x is world +x on an x box and world -z on a z box.
				var end := (-1.0 if at.x > 0.0 else 1.0) if axis == "x" \
					else (1.0 if at.y > 0.0 else -1.0)
				for k: int in 4:
					var across := (float(k) - 1.5) * 0.52
					var centre := Vector3(end * (BOX_LENGTH * 0.5 + 0.03),
						BOX_HEIGHT * float(tier) + BOX_HEIGHT * 0.5, across)
					var xform := Transform3D(Basis(Vector3.UP, 0.0 if axis == "x" else PI * 0.5),
						Vector3(at.x, 0.0, at.y))
					_add_box(bars, xform, centre, Vector3(0.05, BOX_HEIGHT - 0.3, 0.06))
	var node := MeshInstance3D.new()
	node.name = "DoorBars"
	node.mesh = bars.commit()
	node.material_override = _steel
	parent.add_child(node)


## A quay crane beyond the north and south walls: a portal on four legs, a boom
## running out over the water away from the yard, and the A-frame and stays
## that hold the boom up. It is the skyline — what says "dock" from the middle of
## the yard, where the walls hide everything else — and it is drawn in the one
## shape nobody mistakes for anything else: the first version was a portal and
## a boom pointing into the yard, and from the ground it read as a gate.
func _build_cranes(parent: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var legs := CRANE_SPAN * 0.5
	for flip: float in [-1.0, 1.0]:
		# Built facing -z (the north crane) and turned round for the south one.
		var frame := Transform3D(Basis(Vector3.UP, 0.0 if flip < 0.0 else PI),
			Vector3(-4.0 * flip, 0.0, CRANE_Z * flip))
		for x: float in [-legs, legs]:
			for z: float in [-3.0, 3.0]:
				_add_box(st, frame, Vector3(x, (CRANE_HEIGHT - 8.0) * 0.5, z),
					Vector3(0.8, CRANE_HEIGHT + 8.0, 0.8))
			_add_box(st, frame, Vector3(x, CRANE_HEIGHT, 0.0), Vector3(0.8, 0.8, 6.8))
		for z: float in [-3.0, 3.0]:
			_add_box(st, frame, Vector3(0.0, CRANE_HEIGHT * 0.55, z),
				Vector3(CRANE_SPAN + 0.8, 0.7, 0.7))
			_add_box(st, frame, Vector3(0.0, CRANE_HEIGHT, z), Vector3(CRANE_SPAN + 0.8, 0.9, 0.9))
		# The boom: 8 m back over the wall, 16 m out over the water.
		var boom_y := CRANE_HEIGHT + 1.4
		var inner := Vector3(0.0, boom_y, 8.0)
		var outer := Vector3(0.0, boom_y, -16.0)
		_add_box(st, frame, Vector3(0.0, boom_y, -4.0), Vector3(1.6, 1.2, 24.0))
		var apex := Vector3(0.0, CRANE_HEIGHT + 9.0, 1.0)
		for x: float in [-1.6, 1.6]:
			_add_beam(st, frame, Vector3(x, CRANE_HEIGHT, 3.0), apex + Vector3(x * 0.3, 0, 0), 0.5)
			_add_beam(st, frame, Vector3(x, CRANE_HEIGHT, -3.0), apex + Vector3(x * 0.3, 0, 0), 0.5)
		_add_beam(st, frame, apex, outer + Vector3.UP * 0.6, 0.25)
		_add_beam(st, frame, apex, inner + Vector3.UP * 0.6, 0.25)
		# The cab, hanging under the boom just outside the portal.
		_add_box(st, frame, Vector3(1.4, CRANE_HEIGHT - 0.6, -5.0), Vector3(2.4, 2.0, 2.4))
	var node := MeshInstance3D.new()
	node.name = "Cranes"
	node.mesh = st.commit()
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.72, 0.52, 0.16)
	paint.metallic = 0.4
	paint.roughness = 0.55
	node.material_override = paint
	parent.add_child(node)


## A mast on each corner of the wall, a lamp head on it, and a spot aimed into
## the yard. No shadows from these: four shadowed spots is four more shadow
## atlases for a map whose sun already casts, and at dusk the long sun shadows
## are the ones that give the boxes their shape.
func _build_floodlights(parent: Node3D) -> void:
	var lights := _group("Lights", parent)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heads := SurfaceTool.new()
	heads.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corner := HALF + BOX_WIDTH * 0.5
	var wall_top := BOX_HEIGHT * float(WALL_TIERS)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var foot := Vector3(sx * corner, wall_top, sz * corner)
			var mast_height := MAST_TOP - wall_top
			_add_box(st, Transform3D.IDENTITY, foot + Vector3.UP * mast_height * 0.5,
				Vector3(0.3, mast_height, 0.3))
			var head := Vector3(foot.x, MAST_TOP, foot.z)
			var aim := Vector3(sx * (corner - MAST_AIM), 0.0, sz * (corner - MAST_AIM))
			var facing := Basis.looking_at(aim - head, Vector3.UP)
			_add_box(heads, Transform3D(facing, head), Vector3(0.0, 0.0, -0.1),
				Vector3(1.6, 0.9, 0.25))

			var spot := SpotLight3D.new()
			spot.name = "Flood%s%s" % ["W" if sx < 0.0 else "E", "N" if sz < 0.0 else "S"]
			spot.light_color = FLOOD_COLOUR
			spot.light_energy = FLOOD_ENERGY
			spot.spot_range = FLOOD_RANGE
			spot.spot_angle = FLOOD_ANGLE
			spot.spot_attenuation = 0.6
			spot.shadow_enabled = false
			lights.add_child(spot)
			spot.look_at_from_position(head + (aim - head).normalized() * 0.4, aim, Vector3.UP)
	var masts := MeshInstance3D.new()
	masts.name = "Masts"
	masts.mesh = st.commit()
	masts.material_override = _steel
	parent.add_child(masts)
	var lamps := MeshInstance3D.new()
	lamps.name = "LampHeads"
	lamps.mesh = heads.commit()
	lamps.material_override = _lamp
	lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(lamps)


# ------------------------------------------------------------- the plant ---

## Everything bolted on out of the Factory Kit. See the constants above for the
## one rule it all obeys: above head height, or flat on the ground.
func _build_plant(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = PLANT_SEED
	var batch: Dictionary = {}

	for side: int in 4:
		_pipe_runs(batch, rng, side)
		_skyline(batch, rng, side)
	_panels(batch, rng)
	_floor_marks(batch, rng)

	var plant := _group("Plant", parent)
	for model: String in batch:
		_bolted(plant, model, batch[model])


## The inward normal and the along-the-wall tangent for one side of the yard.
## Side 0 is north (z negative), 1 south, 2 west (x negative), 3 east — the same
## numbering `_build_walls` uses, because two different meanings of "side 2" in
## one file is a bug waiting for whoever edits the second one.
static func _side_axes(side: int) -> Array[Vector2]:
	var inward := Vector2(0.0, 1.0) if side == 0 else Vector2(0.0, -1.0) if side == 1 \
		else Vector2(1.0, 0.0) if side == 2 else Vector2(-1.0, 0.0)
	var along := Vector2(1.0, 0.0) if side < 2 else Vector2(0.0, 1.0)
	return [inward, along]


## A point on a wall's inner face: `along` metres down the side, `inset` in from
## the steel, `height` up.
static func _on_wall(side: int, along: float, inset: float) -> Vector2:
	var axes := _side_axes(side)
	var face := -axes[0] * HALF
	return face + axes[0] * inset + axes[1] * along


## Two runs of pipe up each wall, at each height in `PIPE_HEIGHTS`. Pieces are
## 1 m, so a run of n metres is n pieces and every joint lands on a whole metre.
func _pipe_runs(batch: Dictionary, rng: RandomNumberGenerator, side: int) -> void:
	var axes := _side_axes(side)
	# The pipe model runs along its own local x; turn it to lie along the wall.
	var yaw := atan2(axes[1].x, axes[1].y) + PI * 0.5
	for height: float in PIPE_HEIGHTS:
		for run: Vector2 in PIPE_RUNS:
			var length := int(run.y - run.x)
			for k: int in length:
				var along := run.x + float(k) + 0.5
				var at := _on_wall(side, along, PIPE_INSET)
				var model := "pipe-large"
				if k > 0 and k < length - 1 and k % PIPE_FITTING_EVERY == 0:
					model = "pipe-large-valve" if rng.randf() < 0.5 else "pipe-large-bump"
				elif k == 0 or k == length - 1:
					model = "pipe-large-side"
				_bolt(batch, model, Vector3(at.x, height, at.y), yaw, 1.0)


## Machinery along the top of the perimeter wall. `parkour_report` proves no jump
## in the game reaches a wall top, so this is the one place on the map where
## something can be put that is neither cover nor an obstacle.
func _skyline(batch: Dictionary, rng: RandomNumberGenerator, side: int) -> void:
	var axes := _side_axes(side)
	var top := BOX_HEIGHT * float(WALL_TIERS)
	var yaw := atan2(axes[0].x, axes[0].y)
	var along := -HALF + SKYLINE_STRIDE * 0.5
	while along < HALF:
		var at := _on_wall(side, along, -BOX_WIDTH * 0.5)
		var model := SKYLINE[rng.randi() % SKYLINE.size()]
		_bolt(batch, model, Vector3(at.x, top, at.y),
			yaw + rng.randf_range(-0.2, 0.2), rng.randf_range(SKYLINE_SCALE.x, SKYLINE_SCALE.y))
		along += SKYLINE_STRIDE


## Control panels on the wall face behind each base, flat against the steel at
## head height. They are the one thing on the map that marks a base from inside
## it — the floor paint marks it from above, which is not where anybody is.
func _panels(batch: Dictionary, rng: RandomNumberGenerator) -> void:
	for base: Vector3 in base_points():
		var side := 0 if base.z < 0.0 else 1
		var axes := _side_axes(side)
		var yaw := atan2(axes[0].x, axes[0].y)
		for k: int in 5:
			var along := base.x + (float(k) - 2.0) * 1.6
			var at := _on_wall(side, along, 0.18)
			_bolt(batch, PANELS[rng.randi() % PANELS.size()],
				Vector3(at.x, PANEL_HEIGHT + rng.randf_range(-0.25, 0.25), at.y), yaw, 1.0)


## Markings on the concrete: an arrow on the approach to each base and a scatter
## of lines and hatching down the two long aisles. A centimetre up and casting
## nothing, exactly like the painted stripes they sit among.
func _floor_marks(batch: Dictionary, rng: RandomNumberGenerator) -> void:
	for base: Vector3 in base_points():
		var toward := -signf(base.z)
		for k: int in 3:
			_bolt(batch, "indicator-special-arrow",
				Vector3(base.x, 0.014, base.z - toward * (2.6 + float(k) * 2.2)),
				0.0 if toward < 0.0 else PI, 1.0)
	for spot: Vector2 in [Vector2(-11.5, -4.5), Vector2(11.5, 4.5), Vector2(-4.5, 11.5),
			Vector2(4.5, -11.5), Vector2(-15.5, 9.5), Vector2(15.5, -9.5)]:
		_bolt(batch, FLOOR_MARKS[rng.randi() % FLOOR_MARKS.size()],
			Vector3(spot.x, 0.013, spot.y), rng.randf_range(0.0, TAU), 1.0)


# --------------------------------------------------------------- the city ---

## The town outside the wall (the City Kit; see `CITY_MODELS` above).
##
## Lantern Wharf is a 36 m box with a 7.8 m wall round it, and until now the only
## things over that wall were two quay cranes and whatever the sky was doing.
## From the middle of the yard that reads as a box with nothing behind it. This
## puts a working town out there instead: blocks of building, chimneys, tanks, a
## water tower and a couple of windmills, on a 12 m grid from the wall out to
## 96 m, with the near apron stacked with the kit's own containers.
##
## Three rules, and they are what keep this scenery rather than map:
##
## - **Nothing is inside the wall and nothing is collision.** It is all built
##   after `super()`, and every piece is in `StaticMap.BACKDROP_GROUP`, so
##   `preview_map` frames the yard rather than the county (D-057).
## - **Nothing casts.** The sun here is 17 degrees up; a 30 m chimney 60 m out
##   would lay a shadow straight across the yard and across the boxes whose own
##   long shadows are the thing that gives them shape at this hour.
## - **Nothing goes where the cranes are.** The two quay cranes reach from
##   z = ±19 out to z = ±43 over a 16 m span, and a building standing in one is
##   the one thing on this map a player would actually notice was wrong.
func _build_city(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = CITY_SEED
	var batch: Dictionary = {}

	var x := -CITY_REACH
	while x <= CITY_REACH:
		var z := -CITY_REACH
		while z <= CITY_REACH:
			var at := Vector2(x + rng.randf_range(-CITY_JITTER, CITY_JITTER),
				z + rng.randf_range(-CITY_JITTER, CITY_JITTER))
			var model := CITY_MODELS[rng.randi() % CITY_MODELS.size()]
			# The draw happens whether the spot is used or not, so that adding or
			# removing one rule does not reshuffle the whole town.
			var yaw := float(rng.randi() % 4) * PI * 0.5 + rng.randf_range(-0.12, 0.12)
			var scale := rng.randf_range(CITY_SCALE.x, CITY_SCALE.y)
			var gap := rng.randf() < CITY_GAPS
			if not gap and _town_allows(at):
				_bolt(batch, model, Vector3(at.x, 0.0, at.y), yaw, scale)
			z += CITY_STRIDE
		x += CITY_STRIDE

	for stack: Vector3 in CITY_CONTAINERS:
		for tier: int in int(stack.z):
			var yaw := PI * 0.5 if absf(stack.x) > absf(stack.y) else 0.0
			_bolt(batch, "shipping-container-%s" % "abc"[(tier + int(stack.y)) % 3],
				Vector3(stack.x, BOX_HEIGHT * float(tier), stack.y),
				yaw, CITY_CONTAINER_SCALE)

	var town := _group("City", parent)
	for model: String in batch:
		_bolted(town, model, batch[model], true)


## Is this a spot the town may stand on? Both rules are about the *footprint* a
## piece will have once it is scaled, not about where its origin sits — see
## `CITY_NEAR` for the draft that got that wrong.
static func _town_allows(at: Vector2) -> bool:
	if absf(at.x) < CITY_NEAR and absf(at.y) < CITY_NEAR:
		return false  # the yard, its walls, and the apron the containers sit on
	if absf(at.x) < CITY_CRANE_X and absf(at.y) < CITY_CRANE_Z:
		return false  # the lane the two quay cranes reach down
	return true


## One kit piece into the batch.
func _bolt(batch: Dictionary, model: String, at: Vector3, yaw: float, scale: float) -> void:
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
	var list: Array = batch.get(model, [])
	list.append(Transform3D(basis, at))
	batch[model] = list


## One `MultiMeshInstance3D` per model, for the same reasons Twin Quarry does it
## (D-058): a node per prop is a draw call per prop for scenery nothing touches,
## and a multimesh is something `StaticMap`'s collision sweep cannot pick up by
## accident, because that only collects `MeshInstance3D`.
## `city` picks the kit and, with it, everything about how the piece is treated:
## a City Kit piece is a backdrop, which means no shadow and out of
## `preview_map`'s bounds.
func _bolted(parent: Node3D, model: String, transforms: Array, city: bool = false) -> void:
	var mesh := PropScatter.load_city_mesh(model) if city \
		else PropScatter.load_factory_mesh(model)
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
	# Only the skyline casts. The dusk sun is low, so a pipe on a wall face
	# throws a shadow the length of the yard for no gain, and the floor marks are
	# flat on the ground where a shadow would only be acne.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if \
		(SKYLINE.has(model) and not city) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if city:
		node.add_to_group(BACKDROP_GROUP)
	parent.add_child(node)


# ------------------------------------------------------------------ meshes ---

## A container: 6 x 2.6 x 2.4 with its foot at the origin and its length on x.
##
## Built rather than a `BoxMesh`, for the UVs. A `BoxMesh` lays its six faces out
## in a 3x2 atlas, which puts the ribs of the corrugation on the wrong axis on
## half the faces and stretches them on the rest. Here every face is mapped in
## metres along the ground and 0-1 up the box, so the ribs are vertical and
## evenly spaced on every side and the top and bottom rails of the texture land
## on the top and bottom edges of every face.
func _container_mesh() -> Mesh:
	if _mesh_cache.has("container"):
		return _mesh_cache["container"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var l := BOX_LENGTH * 0.5
	var h := BOX_HEIGHT
	var w := BOX_WIDTH * 0.5
	var rib := 2.4
	# Long sides.
	_face(st, Vector3(-l, 0, w), Vector3(l, 0, w), Vector3(l, h, w), Vector3(-l, h, w),
		Vector3.BACK, BOX_LENGTH / rib)
	_face(st, Vector3(l, 0, -w), Vector3(-l, 0, -w), Vector3(-l, h, -w), Vector3(l, h, -w),
		Vector3.FORWARD, BOX_LENGTH / rib)
	# Ends.
	_face(st, Vector3(l, 0, w), Vector3(l, 0, -w), Vector3(l, h, -w), Vector3(l, h, w),
		Vector3.RIGHT, BOX_WIDTH / rib)
	_face(st, Vector3(-l, 0, -w), Vector3(-l, 0, w), Vector3(-l, h, w), Vector3(-l, h, -w),
		Vector3.LEFT, BOX_WIDTH / rib)
	# Top and bottom.
	_face(st, Vector3(-l, h, w), Vector3(l, h, w), Vector3(l, h, -w), Vector3(-l, h, -w),
		Vector3.UP, BOX_LENGTH / rib)
	_face(st, Vector3(-l, 0, -w), Vector3(l, 0, -w), Vector3(l, 0, w), Vector3(-l, 0, w),
		Vector3.DOWN, BOX_LENGTH / rib)
	st.generate_tangents()
	var mesh := st.commit()
	_mesh_cache["container"] = mesh
	return mesh


## The same container with its doors swung back and nothing inside it: two side
## skins, a roof, and four door leaves lying flat against the long sides.
##
## **It is open at both ends on purpose, and that is the whole design decision.**
## A hollow 6 x 2.4 m box on a 36 m map is a room, and a room is a very strong
## thing to give somebody. Open at one end it is a pocket: a Gub inside has one
## way out, everybody outside knows where that is, and a single spear thrown
## through the door kills whoever is in there with nowhere to go — which on a map
## where the spear has a blast radius is not a fight, it is a bin. Open at both
## ends it is a corridor instead. You can be chased through it, you can be met
## coming out of it, and holding it costs you the other door. That is the same
## bargain every other piece of cover on this map offers and it is the reason
## these are through-routes.
##
## What a through-route costs is a hole, and a hole is a sightline. That is why
## the four open ones are the `yard` singles at (±7, ±7.5) and not the `flank`
## singles at (±11.5, 0): the flanks are the *only* thing standing between the
## north wall and the south wall along x = ±11.5, and a corridor through one
## would open a 36 m lane down the side of the map. The yard singles run east-west
## and both of their mouths look at something close — the spine tower 2.8 m off
## one end, the west wall and its tower off the other — so the longest line a Gub
## can thread through one is about 17 m, and `parkour_report` casts every one of
## them on every build rather than taking that on trust.
##
## The shell:
##
## - The **interior floor is the yard's own concrete**. There is no floor slab and
##   no sill, so running in is running, not a step, and — the part that matters —
##   the inside of an open container is not a new standable height. It is y = 0,
##   which the sightline scan was already sampling everywhere else.
## - The **roof is still 2.6 m** and the two landing records on it are the ones
##   the table has always written for a single. Nothing about getting on top of
##   this box changed.
## - The walls are 0.10 m thick with the interior faces modelled. `StaticMap`
##   bakes trimesh collision with `backface_collision` on (D-031), so an interior
##   face stops a Gub from the inside as firmly as the outside face stops one from
##   the aisle — there is no "inside" and "outside" to a triangle here, which is
##   the one property that makes a hollow box out of six flat quads work at all.
## - The **door leaves are part of the shell**, so they are collision too. They
##   stand 3.5 cm proud of the sides, which is why they are hung on the two
##   metres of each side nearest the mouth and not down its middle: the crates
##   that are the step onto this box are flush against the long faces in between.
func _open_container_mesh() -> Mesh:
	if _mesh_cache.has("open"):
		return _mesh_cache["open"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var l := BOX_LENGTH * 0.5
	var h := BOX_HEIGHT
	var w := BOX_WIDTH * 0.5
	var t := 0.10          # side wall
	var iw := w - t        # inner face of a side wall
	var ih := h - t        # the ceiling
	var rib := 2.4
	var along := BOX_LENGTH / rib
	var across := BOX_WIDTH / rib
	# Outer skins and the roof, mapped exactly as the solid box is so a closed
	# container and an open one standing beside each other carry the same ribs.
	_face(st, Vector3(-l, 0, w), Vector3(l, 0, w), Vector3(l, h, w), Vector3(-l, h, w),
		Vector3.BACK, along)
	_face(st, Vector3(l, 0, -w), Vector3(-l, 0, -w), Vector3(-l, h, -w), Vector3(l, h, -w),
		Vector3.FORWARD, along)
	_face(st, Vector3(-l, h, w), Vector3(l, h, w), Vector3(l, h, -w), Vector3(-l, h, -w),
		Vector3.UP, along)
	# The inside: two wall faces looking in at each other, and a ceiling.
	_face(st, Vector3(l, 0, iw), Vector3(-l, 0, iw), Vector3(-l, h, iw), Vector3(l, h, iw),
		Vector3.FORWARD, along)
	_face(st, Vector3(-l, 0, -iw), Vector3(l, 0, -iw), Vector3(l, h, -iw), Vector3(-l, h, -iw),
		Vector3.BACK, along)
	_face(st, Vector3(-l, ih, -w), Vector3(l, ih, -w), Vector3(l, ih, w), Vector3(-l, ih, w),
		Vector3.DOWN, along)
	# The cut edges at the two mouths: the thickness of each wall and of the roof.
	# The floor is not capped, because there is nothing under this box to see it
	# from and the concrete is already there.
	_face(st, Vector3(l, 0, w), Vector3(l, 0, iw), Vector3(l, h, iw), Vector3(l, h, w),
		Vector3.RIGHT, across)
	_face(st, Vector3(l, 0, -iw), Vector3(l, 0, -w), Vector3(l, h, -w), Vector3(l, h, -iw),
		Vector3.RIGHT, across)
	_face(st, Vector3(l, ih, iw), Vector3(l, ih, -iw), Vector3(l, h, -iw), Vector3(l, h, iw),
		Vector3.RIGHT, across)
	_face(st, Vector3(-l, 0, -w), Vector3(-l, 0, -iw), Vector3(-l, h, -iw), Vector3(-l, h, -w),
		Vector3.LEFT, across)
	_face(st, Vector3(-l, 0, iw), Vector3(-l, 0, w), Vector3(-l, h, w), Vector3(-l, h, iw),
		Vector3.LEFT, across)
	_face(st, Vector3(-l, ih, -iw), Vector3(-l, ih, iw), Vector3(-l, h, iw), Vector3(-l, h, -iw),
		Vector3.LEFT, across)
	# Four door leaves, swung right back against the sides, with a locking bar on
	# each: the bars the closed boxes wear on their door end (`_build_door_bars`),
	# here where the door actually is.
	for end: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			var leaf := Vector3(end * (l - 0.60), 1.30, side * (w + 0.035))
			_uv_box(st, leaf, Vector3(1.20, 2.40, 0.07))
			for k: int in 2:
				_uv_box(st, leaf + Vector3((float(k) - 0.5) * 0.46, 0.0, side * 0.06),
					Vector3(0.05, 2.20, 0.05))
	st.generate_tangents()
	var mesh := st.commit()
	_mesh_cache["open"] = mesh
	return mesh


## The forklift, in two halves by colour: `painted` is the bodywork, and the rest
## is the mast, the guard, the forks and the wheels in steel.
##
## Boxes and cylinders, like the cranes (`_build_cranes`) and for the same reason
## — this map's props are this game's own (D-056) and neither kit in the project
## has a forklift in it. It is built facing its own -x with the origin on the
## ground between the wheels, so `FORKLIFT_DECK` above is just a point in this
## drawing.
##
## The shape is held to one rule, stated with `FORKLIFT_DECK`: the only flat top
## on the machine a Gub can stand on is the 1.20 m deck, and that is declared.
## Everything else is either under the deck, narrower than a capsule can find a
## floor on, or both.
func _forklift_mesh(painted: bool) -> Mesh:
	var key := "forklift_paint" if painted else "forklift_steel"
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var id := Transform3D.IDENTITY
	if painted:
		# The deck: the driver's floor, the seat and the counterweight as one
		# unbroken 1.20 m slab, which is the machine's only landing. It is one
		# block rather than a floor pan with a seat on it because a well between
		# them would be a place to stand that no record could describe — the
		# capsule would not fit in it, and "the checker refuses it" is a worse
		# answer than "there is nothing there".
		_add_box(st, id, Vector3(0.625, 0.74, 0.0), Vector3(2.15, 0.92, 1.30))
		# The toe plate forward of the deck, 0.68 m and too short to stand on: a
		# capsule over it overlaps the deck behind, which is higher.
		_add_box(st, id, Vector3(-0.70, 0.48, 0.0), Vector3(0.50, 0.40, 1.30))
		# The seat back, 0.10 m thick, so the deck reads as somewhere a person
		# sits rather than as a flatbed.
		_add_box(st, id, Vector3(-0.35, 1.40, 0.0), Vector3(0.10, 0.40, 0.64))
	else:
		# The overhead guard: four posts off the deck with two rails along their
		# tops and two across. Nothing is plated — see `FORKLIFT_DECK` for the
		# measurement that decided that, and for why an 0.08 m rail is not a
		# place a Gub stands.
		for px: float in [-0.40, 0.45]:
			for pz: float in [-0.55, 0.55]:
				_add_box(st, id, Vector3(px, 1.81, pz), Vector3(0.10, 1.22, 0.10))
		for rz: float in [-0.55, 0.55]:
			_add_box(st, id, Vector3(0.025, 2.46, rz), Vector3(0.95, 0.08, 0.08))
		# The cross rails stay forward of the landing: one over it and the
		# landing is a landing `parkour_report` will not let the map keep.
		for rx: float in [-0.40, 0.10]:
			_add_box(st, id, Vector3(rx, 2.46, 0.0), Vector3(0.08, 0.08, 1.18))
		# The mast: two channels 3.2 m up with a head beam across them, the
		# carriage at the bottom of them, and the forks off the carriage.
		for mz: float in [-0.45, 0.45]:
			_add_box(st, id, Vector3(-1.05, 1.60, mz), Vector3(0.32, 3.20, 0.12))
		_add_box(st, id, Vector3(-1.05, 3.14, 0.0), Vector3(0.32, 0.12, 1.02))
		_add_box(st, id, Vector3(-1.05, 0.55, 0.0), Vector3(0.26, 0.50, 1.00))
		for fz: float in [-0.32, 0.32]:
			_add_box(st, id, Vector3(-1.60, 0.13, fz), Vector3(0.95, 0.10, 0.18))
		# Four wheels, tucked inside the chassis so the machine is 1.3 m wide and
		# the table's clearances are the clearances.
		for wx: float in [-0.55, 1.20]:
			for ws: float in [-1.0, 1.0]:
				_add_cylinder(st, id, Vector3(wx, 0.30, ws * 0.40), Vector3.BACK * ws,
					0.30, 0.24, 12)
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


## A drum: a 0.6 m cylinder with two rolling rims, standing on its own base at
## the origin so the same mesh turned on its side is a drum lying down.
func _barrel_mesh() -> Mesh:
	if _mesh_cache.has("barrel"):
		return _mesh_cache["barrel"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var id := Transform3D.IDENTITY
	_add_cylinder(st, id, Vector3.ZERO, Vector3.UP, BARREL_RADIUS, BARREL_HEIGHT, 16)
	for y: float in [0.22, 0.56]:
		_add_cylinder(st, id, Vector3(0.0, y, 0.0), Vector3.UP, BARREL_RADIUS + 0.025, 0.06, 16)
	var mesh := st.commit()
	_mesh_cache["barrel"] = mesh
	return mesh


## Two pallets, stacked. 28 cm to the top deck, which is under D-060's 0.3 m line
## for a thing a Gub walks over rather than round.
func _pallet_mesh() -> Mesh:
	if _mesh_cache.has("pallet"):
		return _mesh_cache["pallet"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var id := Transform3D.IDENTITY
	for level: int in 2:
		var base := float(level) * PALLET.y
		for bx: float in [-0.5, 0.0, 0.5]:
			_add_box(st, id, Vector3(bx * PALLET.x, base + 0.048, 0.0),
				Vector3(0.14, 0.096, PALLET.z))
		_add_box(st, id, Vector3(0.0, base + 0.118, 0.0),
			Vector3(PALLET.x, 0.044, PALLET.z))
	var mesh := st.commit()
	_mesh_cache["pallet"] = mesh
	return mesh


## Five tubes lying side by side along z. Same height as the pallets and the same
## argument for it.
func _pipe_stock_mesh() -> Mesh:
	if _mesh_cache.has("stock"):
		return _mesh_cache["stock"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k: int in 5:
		_add_cylinder(st, Transform3D.IDENTITY,
			Vector3((float(k) - 2.0) * (PIPE_STOCK_RADIUS * 2.0 + 0.02),
				PIPE_STOCK_RADIUS, -PIPE_STOCK_LENGTH * 0.5),
			Vector3.BACK, PIPE_STOCK_RADIUS, PIPE_STOCK_LENGTH, 10)
	var mesh := st.commit()
	_mesh_cache["stock"] = mesh
	return mesh


func _crate_mesh() -> Mesh:
	if _mesh_cache.has("crate"):
		return _mesh_cache["crate"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := CRATE.x * 0.5
	var y := CRATE.y
	var z := CRATE.z * 0.5
	_face(st, Vector3(-x, 0, z), Vector3(x, 0, z), Vector3(x, y, z), Vector3(-x, y, z), Vector3.BACK, 1.0)
	_face(st, Vector3(x, 0, -z), Vector3(-x, 0, -z), Vector3(-x, y, -z), Vector3(x, y, -z), Vector3.FORWARD, 1.0)
	_face(st, Vector3(x, 0, z), Vector3(x, 0, -z), Vector3(x, y, -z), Vector3(x, y, z), Vector3.RIGHT, 1.0)
	_face(st, Vector3(-x, 0, -z), Vector3(-x, 0, z), Vector3(-x, y, z), Vector3(-x, y, -z), Vector3.LEFT, 1.0)
	_face(st, Vector3(-x, y, z), Vector3(x, y, z), Vector3(x, y, -z), Vector3(-x, y, -z), Vector3.UP, 1.0)
	st.generate_tangents()
	var mesh := st.commit()
	_mesh_cache["crate"] = mesh
	return mesh


## One quad, wound so its front face is the one `normal` points out of, with u
## running 0..`u_span` from a to b and v `v_span`..0 from a to d.
func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3,
		u_span: float, v_span: float = 1.0) -> void:
	var uv := [Vector2(0.0, v_span), Vector2(u_span, v_span), Vector2(u_span, 0.0), Vector2(0.0, 0.0)]
	var corners := [a, b, c, d]
	# Godot's front faces are clockwise seen from the front, so the counter-
	# clockwise a-b-c-d above goes in as a-c-b and a-d-c.
	for index: int in [0, 2, 1, 0, 3, 2]:
		st.set_normal(normal)
		st.set_uv(uv[index])
		st.add_vertex(corners[index])


## An axis-aligned box of `size` centred on `centre`, with the container's own UVs
## on it — metres along the ribs and 0-1 up.
##
## `_add_box` below would be shorter, but it writes no UVs at all, and a
## `SurfaceTool` takes its vertex format from the first vertex it is given: mixing
## the two in one surface is a mesh whose second half has no texture coordinates.
## The door leaves live on the same surface as the container's skin, so they are
## built with this.
func _uv_box(st: SurfaceTool, centre: Vector3, size: Vector3) -> void:
	var a := centre - size * 0.5
	var b := centre + size * 0.5
	var rib := 2.4
	_face(st, Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z),
		Vector3(a.x, b.y, b.z), Vector3.BACK, size.x / rib)
	_face(st, Vector3(b.x, a.y, a.z), Vector3(a.x, a.y, a.z), Vector3(a.x, b.y, a.z),
		Vector3(b.x, b.y, a.z), Vector3.FORWARD, size.x / rib)
	_face(st, Vector3(b.x, a.y, b.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z),
		Vector3(b.x, b.y, b.z), Vector3.RIGHT, size.z / rib)
	_face(st, Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, b.z), Vector3(a.x, b.y, b.z),
		Vector3(a.x, b.y, a.z), Vector3.LEFT, size.z / rib)
	_face(st, Vector3(a.x, b.y, b.z), Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, a.z),
		Vector3(a.x, b.y, a.z), Vector3.UP, size.x / rib)
	_face(st, Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z),
		Vector3(a.x, a.y, b.z), Vector3.DOWN, size.x / rib)


## A capped cylinder standing on `base` — the centre of its bottom cap — running
## `height` along `axis`, in `xform`'s frame. Untextured, like `_add_box`.
##
## The winding rule is `_add_box`'s: a triangle's vertices go in clockwise seen
## from outside, so `cross(b - a, c - b)` points *against* the outward normal.
## Godot's front faces are clockwise and the collision sweep bakes both sides
## anyway, but a barrel wound inside out is a barrel that is black at dusk.
func _add_cylinder(st: SurfaceTool, xform: Transform3D, base: Vector3, axis: Vector3,
		radius: float, height: float, segments: int = 14) -> void:
	var up := axis.normalized()
	var seed_axis := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var u := (seed_axis - up * up.dot(seed_axis)).normalized()
	var v := up.cross(u)
	var top := base + up * height
	var rim: Array[Vector3] = []
	for i: int in segments:
		var angle := TAU * float(i) / float(segments)
		rim.append((u * cos(angle) + v * sin(angle)) * radius)
	for i: int in segments:
		var p0: Vector3 = rim[i]
		var p1: Vector3 = rim[(i + 1) % segments]
		var normal := (xform.basis * (p0 + p1).normalized()).normalized()
		for p: Vector3 in [base + p0, top + p0, top + p1, base + p0, top + p1, base + p1]:
			st.set_normal(normal)
			st.add_vertex(xform * p)
		var cap_up := (xform.basis * up).normalized()
		for p: Vector3 in [top, top + p1, top + p0]:
			st.set_normal(cap_up)
			st.add_vertex(xform * p)
		for p: Vector3 in [base, base + p0, base + p1]:
			st.set_normal(-cap_up)
			st.add_vertex(xform * p)


## An axis-aligned box of `size` centred on `centre`, in `xform`'s frame, into a
## SurfaceTool that is being used for untextured dressing.
func _add_box(st: SurfaceTool, xform: Transform3D, centre: Vector3, size: Vector3) -> void:
	var half := size * 0.5
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
		var mid := centre + n * half
		var du := u * half
		var dv := v * half
		var a := mid - du - dv
		var b := mid + du - dv
		var c := mid + du + dv
		var d := mid - du + dv
		var world_n := (xform.basis * n).normalized()
		# u x v is -n on every face above, so a-b-c is clockwise from the front,
		# which is Godot's front face.
		for p: Vector3 in [a, b, c, a, c, d]:
			st.set_normal(world_n)
			st.add_vertex(xform * p)


## A box stretched from `from` to `to`, `thickness` square, in `xform`'s frame.
func _add_beam(st: SurfaceTool, xform: Transform3D, from: Vector3, to: Vector3,
		thickness: float) -> void:
	var span := to - from
	var up := Vector3.UP if absf(span.normalized().y) < 0.95 else Vector3.RIGHT
	var along := Transform3D(Basis.looking_at(span, up), (from + to) * 0.5)
	_add_box(st, xform * along, Vector3.ZERO, Vector3(thickness, thickness, span.length()))


## A flat quad on y = 0, `size` across, UVs in metres over `tile`.
func _quad(size: Vector2, tile: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	_face(st, Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz),
		Vector3.UP, size.x / tile, size.y / tile)
	return st.commit()


# --------------------------------------------------------------- materials ---

func _build_materials() -> void:
	var ribs := _rib_images()
	var albedo := ImageTexture.create_from_image(ribs[0])
	var normal := ImageTexture.create_from_image(ribs[1])
	for paint: Color in PAINTS:
		var material := StandardMaterial3D.new()
		material.albedo_color = paint
		material.albedo_texture = albedo
		material.normal_enabled = true
		material.normal_texture = normal
		material.normal_scale = 0.9
		material.roughness = 0.5
		material.metallic = 0.3
		material.cull_mode = BaseMaterial3D.CULL_BACK
		_paint_materials.append(material)
		var muted := material.duplicate() as StandardMaterial3D
		muted.albedo_color = Color(paint.darkened(1.0 - WALL_SHADE)).lerp(
			Color(0.22, 0.22, 0.25), 0.25)
		_wall_materials.append(muted)

	_crate_material = StandardMaterial3D.new()
	_crate_material.albedo_color = Color(0.78, 0.60, 0.40)
	_crate_material.albedo_texture = ImageTexture.create_from_image(_plank_image())
	_crate_material.roughness = 0.85
	_crate_material.cull_mode = BaseMaterial3D.CULL_BACK

	_floor_material = StandardMaterial3D.new()
	_floor_material.albedo_texture = _concrete_texture()
	# A wet dock: rough enough not to mirror anything, smooth enough that the
	# floodlights lay a sheen across it.
	_floor_material.roughness = 0.42
	_floor_material.cull_mode = BaseMaterial3D.CULL_BACK

	_paint_line = StandardMaterial3D.new()
	_paint_line.albedo_color = Color(0.92, 0.78, 0.22)
	_paint_line.roughness = 0.6

	_steel = StandardMaterial3D.new()
	_steel.albedo_color = Color(0.32, 0.33, 0.35)
	_steel.metallic = 0.6
	_steel.roughness = 0.45

	# The forklift is the one machine in the yard and it is the one colour nothing
	# else on the map is: the palette's hazard yellow, but lifted and glossier, so
	# that under the sodium floods it reads as a vehicle rather than as another
	# painted box in an aisle full of painted boxes.
	_forklift_paint = StandardMaterial3D.new()
	_forklift_paint.albedo_color = Color(0.92, 0.66, 0.08)
	_forklift_paint.metallic = 0.35
	_forklift_paint.roughness = 0.38

	_timber = StandardMaterial3D.new()
	_timber.albedo_color = Color(0.60, 0.46, 0.31)
	_timber.roughness = 0.9

	_lamp = StandardMaterial3D.new()
	_lamp.albedo_color = FLOOD_COLOUR
	_lamp.emission_enabled = true
	_lamp.emission = FLOOD_COLOUR
	_lamp.emission_energy_multiplier = 6.0


## The corrugation, as an albedo and a normal map, 256 x 64. Eight ribs across
## the texture, which is 2.4 m of box, so a rib every 30 cm; a dark rail along
## the top and bottom four rows. Computed, not loaded, so there is nothing to
## import and nothing that is anybody else's.
func _rib_images() -> Array[Image]:
	var width := 256
	var height := 64
	var albedo := Image.create(width, height, false, Image.FORMAT_RGB8)
	var normal := Image.create(width, height, false, Image.FORMAT_RGB8)
	for x: int in width:
		var phase := TAU * 8.0 * float(x) / float(width)
		var ridge := 0.5 + 0.5 * sin(phase)
		var slope := cos(phase) * 0.55
		for y: int in height:
			var rail := y < 4 or y >= height - 4
			var shade := 0.55 if rail else 0.80 + 0.20 * ridge
			# A little grime settling toward the bottom of each face.
			if not rail:
				shade *= lerpf(1.0, 0.86, float(y) / float(height))
			albedo.set_pixel(x, y, Color(shade, shade, shade))
			var n := Vector3(0.0 if rail else slope, 0.0, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	albedo.generate_mipmaps()
	normal.generate_mipmaps()
	var out: Array[Image] = [albedo, normal]
	return out


## Five planks with dark seams between them.
func _plank_image() -> Image:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y: int in size:
		var seam := y % 13 == 0
		for x: int in size:
			var grain := 0.88 + 0.08 * sin(float(x) * 0.35 + float(y / 13) * 1.7)
			var shade := 0.45 if seam else grain
			image.set_pixel(x, y, Color(shade, shade, shade))
	image.generate_mipmaps()
	return image


## Wet concrete: two greys of noise, one tile every six metres.
func _concrete_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.03
	noise.fractal_octaves = 4
	noise.seed = 0x3A4F
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.17, 0.18, 0.21))
	ramp.set_color(1, Color(0.36, 0.37, 0.40))
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
