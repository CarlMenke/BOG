class_name QuarryMap
extends StaticMap
## Twin Quarry — a worked-out stone pit with one big hole in the middle, a cut
## bench for each team in opposite corners, and a mine adit bored through the
## spoil in a third. Built in code from layout tables the way Kopje Crossing,
## Lantern Wharf and Halcyon Wake are (D-042, D-056, D-057), and rebuilt in
## place against the quarry asset pack (D-140).
##
## **The footprint has not moved.** 48 m of pit inside an 11 m rim, terraced
## away above that to 32.6 m outside the middle — the same numbers the first
## build shipped, because the owner's verdict on the size was that it was
## right. Everything below is what went *into* that footprint.
##
## # The shape, in one paragraph
##
## A square pit. In the middle of it a shaft sixteen metres deep with a rock
## monolith standing in the shaft — the one thing on this map visible from
## everywhere, and the thing that closes the line between the two bases. Round
## the shaft a floor, and out of that floor four things: **two bases** in
## opposite corners of the main diagonal, one storey up on a cut bench; and, on
## the *other* diagonal, **a spoil bench with a tunnel bored through it** in one
## corner and **three quarry terraces** in the other. Two timber catwalks cross
## the shaft past the monolith. That is three ways from base to base — round the
## north-west, round the south-east, or straight across the hole — and the
## tunnel is a fourth that is a shortcut on the first.
##
## # The two bases are one function called twice
##
## `_build_base` builds a bench, a wall, two haul ramps and their landings from
## one corner coordinate, and `_ready` calls it for each of `turned(BASE_AT)`.
## Every solid in a base therefore exists twice and only once in the source, so
## the two cannot drift apart: **the bases are identical by construction**, not
## by inspection. `tools/quarry_check.gd` re-proves it from the built scene
## anyway, because a base is the one thing on a capture map that has to be
## fair to the centimetre.
##
##   * **Each base is a storey up.** The pad sits on a 4 m cut bench in its own
##     corner. Four metres is over every jump in the Bog's kit — the one-tick
##     dive reaches 4.23 m of rise but only off a take-off edge, and from flat
##     ground `parkour_report` allows 3.5 — so the face of the bench is a wall,
##     not a step.
##   * **Two ways up, and they are the haul ramps.** A ~19 degree ramp climbs to
##     each of the bench's two open faces. The Bog has no step-up, so a ramp is
##     the only climbable slope there is (`floor_max_angle` is 52 degrees).
##   * **A 1.8 m wall round the pad, with three gaps.** A Bog is 1.55 m and its
##     eyes are at 1.45, so you cannot see over it and the 1.69 m jump cannot
##     clear it. You can *leap* onto it, which is the defender's perch. The gaps
##     are the head of each ramp and one drop port, which is an exit and a
##     throwing slot and nothing can come up it.
##
## # Everything else is a 180 degree turn, or sits on the line
##
## The bases stand on the main diagonal, so the map's symmetry is **rotational**:
## team 2's half is team 1's half turned half a turn about the origin. Every
## cover table below is written once for the negative half and placed again
## negated by `turned()`, which is what makes the two halves congruent without
## anybody checking.
##
## The two features that are *not* a pair — the tunnel bench and the terraces —
## both stand on the **perpendicular bisector** of the line between the bases
## (the line x = -z), which is the one place on this map where a thing can be
## asymmetric and still be exactly as far from one base as from the other. The
## tunnel's two mouths are reflections of each other in that line, to the
## centimetre; the three letter cards stand on it as well. So the map is not
## symmetric and is still even, which is what the brief asked for.
##
## # The tunnel
##
## An L-shaped adit through the north-west spoil bench: 4.0 m wide, 3.4 m of
## headroom, in at the bench's south face and out at its east face, with a rail
## run down the middle of it and a cart standing in the corner chamber. Three
## numbers decide the section and none of them is taste — the Bog's capsule is
## 0.38 m across and 1.55 m tall, and `bog_camera.gd` sweeps a sphere behind the
## player's head, so a corridor that fits a Bog and not its camera is a corridor
## the player plays blind. Four metres and three-and-a-half clear it with room.
##
## **The bend is the point.** A straight bore is a 20 m sightline with a man at
## each end of it, which on a map with a long-range bow is a corridor nobody
## enters second. An L has no line through it at all: what you get for taking
## the tunnel is that nothing can see you take it, and what you pay is that you
## cannot see what is waiting at the far mouth either.
##
## All of its collision is **built here, out of boxes** — five rock slabs round
## an L-shaped void and two roof slabs over it — and not taken off the portal
## models, which are dressing hung on the mouths afterward.
##
## # The stone, and what each height means
##
## **The two you can climb are pale ochre cut stone and the two you cannot are
## dark grey raw rock**, which is the only thing telling them apart under a hard
## sky:
##
##   kerbs       1.2 m. Low cover, and the step up — a hop from the floor. The
##               spoil rocks and the minecarts are kerbs too.
##   berms       1.85 m. Shield height: over a Bog's 1.45 m eye, so it breaks a
##               standing line, and under `GROUND_LEAP`, so a Bog can get onto
##               one from flat ground and nothing is stranded. The blocks round
##               the shaft's lip are berms, and a quarry banks exactly this
##               round a hole for exactly this reason.
##   blocks      3.0 m. Hard cover, climbable off a kerb (1.8 m of rise, and a
##               leap lifts 2.30) and out of reach of anything from flat ground.
##   benches     4.0 m (a base) and 4.5 m (the tunnel bench). The high ground.
##   terraces    1.5 / 3.0 / 4.5 m. The south-east corner climbs to the same
##               height as the tunnel bench in three jumpable steps, which is
##               the other half of "even": one bisector corner is solid and has
##               a secret in it, the other is open and has a view.
##   columns     10.2 m of unquarried rock, and the monolith is 12. Out of reach
##               of every jump the Bog has — `off_limits`, and the report fails
##               the build if one can be stood on.
##   the rim     11 m of cliff on all four sides, terraced away above that.
##
## Build order is the other built maps' and the rule is the same: everything
## added before `super()` is swept into world-space collision, everything after
## is dressing. Nothing here is random, so every peer builds the same pit by
## construction rather than by a shared seed.

# ---------------------------------------------------------------- the table ---

## Half the pit's width, to the rim's inner face. The floor runs to `FLOOR_EDGE`
## so the rim has something to stand on. **Unchanged from the first build**: the
## footprint is the one thing this rebuild was told to keep.
const HALF := 24.0
const RIM_THICKNESS := 3.0
const FLOOR_EDGE := HALF + RIM_THICKNESS
## How thick the pit floor is — the number that says where the floor's
## *underside* is, which is the number the shaft rock has to stop at. Nothing
## about the playable surface depends on it; the floor's top is y = 0 either
## way, so this is a name for a seam, not a measurement anybody stands on.
const FLOOR_THICK := 0.6
## The rim's top. Nothing reaches it and nothing is meant to; it is the skyline
## and the reason the pit reads as a hole in the ground rather than a yard.
const RIM_TOP := 11.0
## The benches the cliff climbs in behind that, as (how far out from the rim's
## inner face this tier starts, how high it goes).
const RIM_TIERS: Array[Vector2] = [
	Vector2(0.0, RIM_TOP), Vector2(2.4, 15.0), Vector2(5.6, 18.6),
]

# ------------------------------------------------------------- the big hole ---

## The shaft in the middle of the pit: the next bench down, and the one thing on
## this map that kills you (D-089).
##
## It went from 13 m across to **15**, because the brief for the rebuild is "one
## big hole in the middle" and 13 m in a 48 m pit reads as a well. At 15 it is
## most of a third of the pit's width, which is what a hole has to be before the
## floor round it reads as a *rim* rather than as a yard with a hazard in it.
const HOLE_HALF := 7.5
## How far down you can see before the fog and the dark take it. The floor of
## the lower bench is modelled, because a shaft that ends in nothing reads as a
## texture error rather than as a quarry, but nobody ever stands on it:
## `void_height` is -10, so a Bog is dead six metres before it arrives.
const HOLE_FLOOR := -16.0
## A ledge part way down, so the drop reads as *quarried* — benches and a haul
## road, the same thing the pit above it is — rather than as a lift shaft.
const HOLE_LEDGE := -5.5
const HOLE_LEDGE_WIDTH := 1.6
## How wide the ledge's tread is: the step the lower face is set back by, as
## opposed to `HOLE_LEDGE_WIDTH`, which is how far the *upper* face stands out
## past the hole's edge.
const LEDGE_TREAD := 0.9

## The monolith: a pillar of unquarried rock left standing in the middle of the
## shaft, from the shaft's floor to twelve metres over the pit's.
##
## It is doing the job the Stack did before the hole was cut (D-082, D-089) and
## it is the only shape that can still do it. Under a rotational layout every
## spawn pad has an exact antipode on the other team and the line between them
## runs through the origin — so an open middle is eight guaranteed
## spawn-to-spawn sightlines, plus base to base, and no amount of cover anywhere
## else closes them. A hole closes nothing: two pairs of eyes 1.45 m over a flat
## floor do not care what is underneath the line between them. A **rock in the
## hole** closes all of it and costs the hole nothing, because a quarry that has
## worked round an unworkable core is what a monolith *is*.
##
## Twelve metres, so no jump reaches its top and `off_limits` says so; tapered,
## so it reads as rock left behind rather than as a column somebody cast.
const MONOLITH_TOP := 12.0
const MONOLITH_BASE_HALF := 4.2
const MONOLITH_TOP_HALF := 2.6
## How many stacked slabs the taper is drawn with. Four is enough that the
## silhouette steps rather than slopes, which is what a rock face does.
const MONOLITH_STEPS := 5

## The two timber catwalks over the shaft: the risky way across, and a
## **rotational pair**, so each team has exactly the same one.
##
## Each runs along x, one metre past the hole's lip at each end so it lands on
## real floor, and each has a **gap in it** — a span of planks that fell in —
## that a Bog can only cross on the dive. The gap on one is the gap on the other
## turned half a turn, which is the whole reason there are two: a single walk
## with a single gap is a feature one team meets from the near side and the
## other from the far, and that is a difference nobody can argue is small.
const CATWALK_Z := 5.0
const CATWALK_WIDE := 2.4
const CATWALK_REACH := HOLE_HALF + 1.2
## The deck's underside, so the planks have thickness and a spear can stop in
## them. Its *top* is y = 0, flush with the pit floor it runs out of.
const CATWALK_DROP := 0.4
## The missing span, along x, on the catwalk written for the positive z side.
## `turned()` puts the other one at the negation of both.
const CATWALK_GAP := Vector2(1.0, 3.4)
## The handrail: one side only, on the side away from the monolith, and only
## over the half of the deck the gap is not in. Waist height on a Bog, so it
## reads as a rail and never as cover.
const RAIL_TOP := 0.95

# -------------------------------------------------------------- the bases ---

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
## at the record is not buried in the rock uphill of it (D-057's number).
const RAMP_LIFT := 0.08

# ----------------------------------------------- the north-west spoil bench ---

## The bench the tunnel is bored through: a solid mass of tipped spoil banked
## into the north-west corner, top at `CORNER_TOP`, from the rim's two inner
## faces in to `CORNER_INNER`.
##
## It stands on the bisector — its middle is at (-17, 17), and x = -z — so it is
## exactly as far from one base as from the other, and so is everything in it.
const CORNER_TOP := 4.5
const CORNER_X := Vector2(-HALF, -10.0)
const CORNER_Z := Vector2(10.0, HALF)

## The adit, as the two legs of its L. `A` runs along z at x in `TUNNEL_A_X`,
## from the bench's south face up to `TUNNEL_TURN`; `B` runs along x at z in
## `TUNNEL_B_Z`, from `TUNNEL_TURN` out through the bench's east face. The two
## are reflections of each other in x = -z, which is what makes the mouths
## equidistant from the two bases.
const TUNNEL_WIDE := 4.0
const TUNNEL_TOP := 3.4
const TUNNEL_A_X := Vector2(-19.8, -15.8)
const TUNNEL_B_Z := Vector2(15.8, 19.8)
## The far corner of the chamber where the two legs meet, in each leg's own
## direction of travel: leg A runs z up to here, leg B runs x up to here.
const TUNNEL_TURN := Vector2(-10.0, 19.8)

## The haul ramp up the bench's south face, east of the tunnel mouth: across,
## and where it starts and ends along z. 4.5 m over 10 is 24.2 degrees, which is
## steeper than a base ramp and is meant to be — this is the way onto the high
## ground, not the way into somebody's home.
const CORNER_RAMP_X := Vector2(-13.9, -10.9)
const CORNER_RAMP_Z := Vector2(0.0, 10.0)

# ---------------------------------------------- the south-east terraces ---

## The other bisector corner: three quarry steps climbing to the same 4.5 m the
## tunnel bench reaches, written as (x span, z span, top).
##
## Every step is 1.5 m, which is under the Bog's 1.69 m standing jump, so the
## whole corner is climbable from anywhere on any of its faces and is a dead end
## nowhere. That is the trade against the tunnel: this corner is as high and has
## the same view, and it has no cover on it at all.
const TERRACES: Array[Dictionary] = [
	{"label": "terrace low", "x": Vector2(10.0, HALF), "z": Vector2(-HALF, -10.0),
		"top": 1.5},
	{"label": "terrace mid", "x": Vector2(14.0, HALF), "z": Vector2(-HALF, -14.0),
		"top": 3.0},
	{"label": "terrace high", "x": Vector2(18.0, HALF), "z": Vector2(-HALF, -18.0),
		"top": 4.5},
]

# ------------------------------------------------------ the stone in the pit ---

## Columns are 10.2 m. Not 7.6, which is where they started: the wall round a
## base is a landing 5.8 m up, and the one-tick dive lifts 4.23 m, so anything
## under 10.03 m is a column somebody stands on top of and reads the whole pit
## from. `parkour_report` found that, which is what it is for.
const COLUMN_TOP := 10.2
const COLUMNS: Array[Dictionary] = [
	# The two on the main diagonal, one either side of the monolith, closing
	# what is left of base to base once the rock in the hole has taken the
	# middle. The benches are 12.5 m squares, so the line between their far
	# corners swings well wide of the origin and needs a blocker out here.
	{"label": "diagonal lip", "at": Vector2(-10.2, -10.2), "size": Vector2(4.6, 4.6)},
	# Flush against the rim, like the ramps and for the same reason: anything
	# standing a metre and a half off the cliff leaves a slot behind it, and a
	# slot that runs the length of the pit is a 34 m lane as well as somewhere
	# to get wedged.
	{"label": "flank west", "at": Vector2(-21.5, 2.0), "size": Vector2(5.0, 5.0)},
	{"label": "flank south", "at": Vector2(2.0, -21.5), "size": Vector2(5.0, 5.0)},
]

## Hard cover: 3.0 m, climbable off a kerb and nothing else.
##
## **Every one of them needs a kerb beside it.** From flat ground 3.0 m is only
## a one-tick dive, and the reachability walk refuses to count those, so a block
## with no step is a block the report calls stranded.
const BLOCK_TOP := 3.0
const BLOCKS: Array[Dictionary] = [
	{"label": "west shoulder", "at": Vector2(-20.5, -6.0), "size": Vector2(3.0, 3.0)},
	# Out at -15.5 and not -13: the spoil bench's haul ramp climbs along z at
	# x in [-13.9, -10.9], so a three-metre block centred on -13 is a block
	# built through the middle of one of the two ways onto the high ground.
	{"label": "west mid", "at": Vector2(-15.5, 2.5), "size": Vector2(3.0, 3.0)},
	{"label": "west head", "at": Vector2(-19.5, 7.0), "size": Vector2(3.5, 3.0)},
	{"label": "south shoulder", "at": Vector2(-6.0, -20.5), "size": Vector2(3.0, 3.0)},
	{"label": "south mid", "at": Vector2(2.5, -13.0), "size": Vector2(3.0, 3.0)},
	{"label": "south head", "at": Vector2(7.0, -19.5), "size": Vector2(3.0, 3.5)},
	# The step onto the tunnel bench that is not the haul ramp, flush against
	# its east face. A leap off a 3 m block lifts 2.30, which clears 4.5.
	# Its turn stands on the pit floor south-east of the shaft, which is why it
	# is 14 m up the bench's face and not 12.5: at 12.5 the turn landed on the
	# very spot the U card settles on, and a card on top of a kerb is a card
	# nobody can see.
	{"label": "bench step", "at": Vector2(-8.5, 14.0), "size": Vector2(3.0, 3.0)},
]

## Berms: 1.85 m, the shield-height cover, and every one of them stands on the
## shaft's lip.
##
## They are **hand-placed rather than turned**, and they are the one table here
## that is. Each of the four lines that crosses the hole needs *one* blocker
## along it, not one at each end, so a mirrored table builds eight to do the
## work of four and then jams them against each other. These four sit one to a
## side, clear of both catwalk decks, and the halves are not congruent here —
## which is worth more than a symmetry nobody can see from inside the map.
const BERM_TOP := 1.85
## **The four are written as two rotational pairs and their spans are what the
## pad-to-pad check is closed by.** Every pad on this map has an exact antipode
## on the other team, and four of those eight lines run across the shaft's lip
## rather than through the middle where the monolith is. `parkour_report` found
## all four open the first time these were placed by eye, missing the ones on
## the west and east by under a metre, so the two long berms are 5.4 m rather
## than 3.6 and the two short ones are 4.4 m deep rather than 3.6 — sized to the
## line each has to break and not to the look of the rim.
##
## The long pair is also what takes the map's longest *ground* sightline down:
## a 42 m run from one rim to the other at about x = -4 passed a metre clear of
## the old berm and now crosses it.
const BERMS: Array[Dictionary] = [
	{"label": "berm west", "at": Vector2(-10.6, -2.8), "size": Vector2(3.0, 4.4)},
	{"label": "berm east", "at": Vector2(10.6, 2.8), "size": Vector2(3.0, 4.4)},
	{"label": "berm north", "at": Vector2(4.55, -10.4), "size": Vector2(5.4, 3.0)},
	{"label": "berm south", "at": Vector2(-4.55, 10.4), "size": Vector2(5.4, 3.0)},
]
## Kept under the old name because the props and the footprint sweep read it.
const LIP_TOP := BERM_TOP
const LIP_BLOCKS := BERMS

## Low cover and the step onto a block. Each is laid flush against the block it
## is a step onto — a kerb with a metre of daylight beside a block is a slot a
## Bog gets stuck in, and flush it is a staircase.
const KERB_TOP := 1.2
const KERBS: Array[Dictionary] = [
	{"label": "step west shoulder", "at": Vector2(-20.5, -3.5), "size": Vector2(2.0, 2.0)},
	{"label": "step west mid", "at": Vector2(-15.5, 0.0), "size": Vector2(2.0, 2.0)},
	# Clear of the flank column, which runs out to x = -19 flush against the
	# rim: at -19.5 this kerb was built a metre inside ten metres of rock.
	{"label": "step west head", "at": Vector2(-18.0, 4.5), "size": Vector2(2.0, 2.0)},
	{"label": "step south shoulder", "at": Vector2(-3.5, -20.5), "size": Vector2(2.0, 2.0)},
	# On the block's west face. It was on the shaft side, inside the north berm;
	# then on the rim side, two and a half metres off a spawn pad.
	{"label": "step south mid", "at": Vector2(0.0, -13.0), "size": Vector2(2.0, 2.0)},
	# Clear of the flank column on this axis, and on the rim side of its block
	# rather than the pad side.
	{"label": "step south head", "at": Vector2(7.0, -22.25), "size": Vector2(2.0, 2.0)},
	{"label": "step bench", "at": Vector2(-8.5, 11.25), "size": Vector2(2.5, 2.5)},
	# The two that are not steps: low cover out on their own, on the run down
	# each lane, where a lane would otherwise be 20 m of nothing.
	{"label": "lane west", "at": Vector2(-15.5, -8.0), "size": Vector2(2.4, 2.4)},
	{"label": "lane south", "at": Vector2(-8.0, -15.5), "size": Vector2(2.4, 2.4)},
]

## The letter home points, so the layout and the scene cannot disagree about
## where they are. **All three stand on the bisector** — the line x = -z — which
## is the only place a single card is exactly as far from one base as from the
## other, and is the same line the tunnel and the terraces are built on.
##
##   G  in the tunnel's corner chamber. Nothing can see you pick it up and you
##      cannot see what is waiting at either mouth.
##   U  on the shaft's south-east lip, a metre off a sixteen-metre drop, with
##      two berms and a monolith for company and no roof at all.
##   B  on the top terrace, 4.5 m up in the open, which is the easiest card on
##      the map to reach and the hardest to leave with.
const LETTER_POINTS: Array[Vector2] = [
	Vector2(-17.8, 17.8), Vector2(8.5, -8.5), Vector2(21.0, -21.0),
]

# --------------------------------------------------------------- the stone ---

## The textures. Six CC0 Poly Haven sets in `assets/maps/quarry/`, laid out and
## loaded exactly the way Lantern Wharf's are (`assets/maps/wharf/SOURCES.md`),
## and for the same reason: a pit whose every face is a procedural noise field
## reads as one material lit four ways however carefully the noise is written.
## The rebuild's first pass proved it — 2833 lines of correct layout wearing
## stripes. Photographic albedo, normal and roughness is the only thing that
## makes a sawn limestone face look sawn.
##
## `QUARRY_FACE` is the only 2k set on the map. It is the rock: the rim, the
## shaft, the monolith and every column, which between them are most of every
## frame a player has, and it is a *bedded* photograph — horizontal seams and
## blocky joints — so it does the work of the old drill-line generator without
## being drawn by hand. Everything else is 1k, because everything else is
## either small, far away or underfoot.
const TEX := "res://assets/maps/quarry/"
const QUARRY_FACE := "quarry_wall_02"
const QUARRY_FACE_RES := "2k"
const DRESSED_STONE := "large_sandstone_blocks_01"
const PIT_GRAVEL := "gravel_floor_03"
const SITE_TIMBER := "weathered_planks"
const SITE_IRON := "corrugated_iron_02"
const SITE_RUST := "rusty_metal_02"

## How many metres one tile of each set covers. This is the texel density, and
## it is the difference between rock and wallpaper: `quarry_wall_02` is 2048 px,
## so 5 m a tile is 410 px/m and a player nose to nose with a cliff is looking
## at grain. The dressed set is 1024 px over 2.4 m, which lands its own block
## courses at about 0.8 m — a real ashlar course — so the benches read as
## *built* rather than as a photograph of a wall stretched over a box.
const FACE_TILE := 6.0
const RAW_TILE := 3.6
const DRESSED_TILE := 2.4
const GRAVEL_TILE := 2.0
const ROAD_TILE := 2.6
const TIMBER_TILE := 2.0
const IRON_TILE := 1.6
const RUST_TILE := 1.5

# ----------------------------------------------------------------- colours ---

## **These are multipliers over a photograph now, not colours.** They were flat
## albedos while the textures were generated; a loaded diffuse already carries
## the rock's own colour, so what is left for this table to do is say how much
## light the surface is standing in and which way the dust has coloured it.
## Values over 1 are deliberate and are not a mistake: `quarry_wall_02` is a wet
## brown photographed in shade and the pit is a sun-baked limestone hole, so the
## rim is lifted most of a stop and a half and warmed.
##
## The readability rule from D-082 survives the change and is the reason the two
## rock sets are split the way they are: **cut stone is pale and is what you
## climb; raw stone is dark and is what you cannot.** Cut stone wears the
## dressed sandstone set, raw stone wears the bedded quarry face, and the gap
## between them is now a gap in material as well as in tint.
const STONE_CUT := Color(1.06, 0.98, 0.82)
const STONE_BENCH := Color(0.98, 0.92, 0.78)
const STONE_RIM := Color(1.32, 1.24, 1.08)
const STONE_RAW := Color(1.14, 1.09, 1.00)
## The pit floor and the haul road, over `gravel_floor_03` — a cool grey crushed
## stone, warmed here into limestone waste and darkened on the roads, which are
## the same gravel with a decade of tyres on it.
const FLOOR_GRAVEL := Color(1.38, 1.27, 1.05)
const HAUL_ROAD := Color(0.92, 0.84, 0.72)
const STEEL := Color(0.86, 0.86, 0.90)
const RUST := Color(0.78, 0.42, 0.20)
## The timber the catwalks, the portal frames and the sleepers are cut from.
## `weathered_planks` is photographed almost black, so this is most of two stops
## of lift: sun-bleached pit timber, not a wet fence.
const TIMBER := Color(1.72, 1.52, 1.26)
## Corrugated sheet, on the shelters and the hopper. The photograph is a cold
## galvanised grey; warmed a little so it belongs to the same hour as the rock.
const SHEET_IRON := Color(1.52, 1.44, 1.32)
# Pale, not deep. Water dark enough to read as deep reads as a hole cut in the
# floor instead.
## Damp stone, not water. Three passes at this: a pale blue-grey at roughness
## 0.14 was a mirror disc of sky; darkening it made a hole in the floor; what
## works is the floor's *own* colour taken down a third with a low roughness, so
## a puddle is a patch of limestone that has not dried yet.
const PUDDLE := Color(0.74, 0.70, 0.62)
const LAMP_WARM := Color(1.0, 0.86, 0.62)
## Site paint: the diagonal hazard stripes at the pit lip and on the plant, and
## the sand the gabions and bags are filled with.
const HAZARD_YELLOW := Color(0.46, 0.36, 0.09)
const SANDBAG := Color(1.14, 1.02, 0.80)
## What the pack's cold museum-grey stone is multiplied by to join this pit.
const PACK_STONE := Color(0.96, 0.88, 0.74)
## What the MegaKit's spring-green atlas is multiplied by to make last summer's
## grass. Hard toward red on purpose — see `_dry_material`; a gentle tint over a
## saturated green is still a green.
const DRY_GRASS := Color(1.30, 0.98, 0.42)
const DEAD_SCRUB := Color(1.55, 1.38, 1.10)

# ------------------------------------------------------------------- props ---

## The Stylized Nature MegaKit models the weeds and rubble are drawn from, and
## the one seed every random draw comes out of. Fixed, so every peer scatters
## the same weeds in the same cracks.
const PROP_SEED := 0x51A7B0
const RUBBLE: PackedStringArray = ["Pebble_Round_1", "Pebble_Round_2",
	"Pebble_Round_3", "Pebble_Round_4", "Pebble_Round_5", "Pebble_Square_1",
	"Pebble_Square_2", "Pebble_Square_3", "Pebble_Square_4", "Pebble_Square_6"]
## The three the spoil rocks are cut from, and the one list here that is not
## scattered: a boulder is the only MegaKit model on this map that ends up
## solid, so `SPOIL_ROCKS` picks from it by hand rather than by a draw.
const BOULDERS: PackedStringArray = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"]
## **Dry only.** This list was the forest map's scatter set until the visuals
## pass looked at it: clover, ferns and two big leafy plants, scattered thickly
## round the foot of every face on a map whose whole premise is a sun-baked
## worked-out limestone pit. What grows in a quarry is wispy grass in a crack
## and nothing else, so the lush half is gone and what is left is the two wispy
## tufts plus the short common grass, tinted to straw by `_dry_material` —
## which is the other half of the fix, because the MegaKit's grass shares one
## bright green atlas and no amount of choosing between models escapes it.
const WEEDS: PackedStringArray = ["Grass_Wispy_Short", "Grass_Wispy_Tall",
	"Grass_Common_Short"]
## What used to be `BLOOMS`: bell flowers, a red bush and two big plants ringing
## every puddle. **There are no flowers in this quarry.** The one survivor is
## the common bush, used as dead scrub — same mesh, straw material, and placed
## about a tenth as often as the flowers were.
## `Bush_Common` was the survivor for one render and then went too: the kit's
## bush is an *autumn red* atlas, and a tint is a multiply, so no tint on earth
## turns it grey — it came out a fire-engine splash on a limestone floor. Dead
## scrub is a dead tree at a fifth of its size instead, which is the same shape
## a burnt-out thorn is and is already the right colour.
const SCRUB: PackedStringArray = ["DeadTree_3", "DeadTree_4", "DeadTree_5"]
const SNAGS: PackedStringArray = ["DeadTree_1", "DeadTree_2", "DeadTree_3",
	"DeadTree_4", "DeadTree_5"]

## How the apron round a face is walked, and how far out of it a prop sits.
const APRON_STRIDE := 1.1
const APRON_NEAR := 0.15
const APRON_FAR := 0.85

## Scales, all taken off `PropScatter.DENSE_LAYERS`, which measured them against
## the Bog: `Grass_Common_Tall` is 1.87 m at scale 1 and the Bog is 1.81, so
## grass at 1.0 is a swamp that hides a crouched player.
const RUBBLE_SCALE := Vector2(0.5, 1.0)
const WEED_SCALE := Vector2(0.28, 0.55)
const SCRUB_SCALE := Vector2(0.055, 0.105)
const SNAG_SCALE := Vector2(0.45, 0.85)

## Where the coarse waste was tipped, written once and turned like everything
## else. **These are the only MegaKit props on the map that are solid**, and the
## reason they are a table rather than a scatter is that they are solid.
##
## `model` indexes `BOULDERS`, `yaw` turns the rock so six copies of three meshes
## do not read as three meshes. Every one of them is off both haul ramps, out of
## every doorway, more than ten metres from any spawn pad and clear of every
## block, which is what keeps a Bog's capsule fitting beside it.
const SPOIL_ROCKS: Array[Dictionary] = [
	# Off the south haul ramp, which runs flush against the rim from x = -24 to
	# -21 the whole depth of the west lane: a rock tipped there is a rock in the
	# middle of one of the two ways into a base.
	{"label": "spoil west", "at": Vector2(-18.5, -9.0), "model": 0, "yaw": 0.4},
	# At z = -19 and not -21, which is the same mistake the rail and the first
	# two cart sidings made and is worth writing down once: **each base's two
	# haul ramps run flush against the rim**, from the pit floor at the middle
	# of a side all the way up to the bench, so the three-metre strip of floor
	# inside every cliff on this map is a road climbing to four metres. A rock
	# tipped at -21 is a rock three metres up the east ramp, and the landing
	# record on top of it says a Bog stands at 1.2 m inside solid road.
	{"label": "spoil south", "at": Vector2(-9.5, -19.0), "model": 1, "yaw": 2.1},
	{"label": "spoil lane", "at": Vector2(-16.0, 6.0), "model": 2, "yaw": 3.9},
]
## How wide a spoil rock is across its footprint, and the landing radius its top
## is credited with. The radius is well inside the footprint on purpose: the
## last half metre of a rock is the slope down its side.
const ROCK_SPAN := 2.6
const ROCK_LANDING := 0.7
## The chips round each rock: how many, and how far they spread.
const ROCK_SKIRT := 6
const ROCK_SKIRT_SPREAD := 1.2

## How many dead trees stand on the rim's first terrace.
const SNAG_COUNT := 14

## Standing water, shared by the puddle quads and the bushes that ring them.
## Every one is clear of the two corner masses and of the benches, because a
## puddle whose edge lands on a four-metre face reads as a mistake.
const PUDDLES: Array[Vector2] = [Vector2(-4.0, 21.5), Vector2(-16.0, -2.0),
	Vector2(16.0, 2.0), Vector2(14.0, 6.0), Vector2(-13.0, -4.0),
	Vector2(-6.0, -11.0)]

## The derricks outside the rim: the skyline, and the only thing on the map that
## says what the hole is for. Two of them, on the bisector, so each stands over
## one of the two corner features.
const DERRICK_AT := Vector2(-28.5, 28.5)
const DERRICK_HEIGHT := 21.0

# ------------------------------------------------------- the quarry pack ---

## `art/maps/quarry/` — sixty-five GLB models generated one at a time by Tripo.
## Three things about them decide how they are used here and none is in a
## manifest: **every model is normalised to about one metre** whatever it is
## meant to be, the pivots and facings vary per file, and a good third of the
## pack is ice, crystal, emerald or "futuristic" and is off-theme for a
## sun-baked worked-out stone quarry. `tools/quarry_sheet.tscn` is the contact
## sheet those judgements were made off; the survivors are below and nothing
## else in the pack is referenced.
##
## Every one is **dressing**, hung after `super()`, and every one is scaled by
## this file to a real size against its own bounding box rather than by eye.
## Where a prop is big enough to read as cover it gets a box of code-built
## collision under it at `KERB_TOP`, so a thing that looks like a step is a step
## — see `CART_STANDS`.
const PACK := "res://art/maps/quarry/"
## The pack's mine portals, and **they are not on the playable tunnel**. See
## `_build_timbering` for why. They stand against the rim instead, as two adits
## the pit cut through and abandoned — a rotational pair, one per half, on the
## west and east cliffs where the model's own mound has three metres of rock and
## two terraces behind it and nothing to intrude into.
##
##   at    where the mouth sits, on the rim's inner face.
##   yaw   which way the model's own +x — its opening — is turned to point.
const ADIT_MODELS: Array[Dictionary] = [
	{"model": "stone_mine_tunnel_03", "at": Vector2(-HALF, 6.0), "yaw": 0.0},
	{"model": "stone_mine_tunnel_02", "at": Vector2(HALF, -6.0), "yaw": PI},
]
## How wide one of them is built across its mouth, and how far the mouth stands
## proud of the cliff it is cut into.
const ADIT_WIDE := 5.0
const ADIT_PROUD := 0.35

## The rail. One straight model, laid end to end down the tunnel and out across
## the floor as a `MultiMesh`, because a run of forty sleepered metres is forty
## draw calls otherwise. The model is 0.99 m along its own x and 0.37 across, so
## `RAIL_PITCH` is what one instance covers and `RAIL_GAUGE_SCALE` is what turns
## its 0.37 into a believable narrow gauge.
const RAIL_MODEL := "railway_track_02"
const RAIL_PITCH := 2.2
## Where the rail runs, as polylines on the floor. Each is a list of corners and
## the run is laid along the straight sections between them; the corners
## themselves are left bare, because the pack's corner pieces are chunks of wall
## with a rail on them rather than a curve.
const RAIL_RUNS: Array[Array] = [
	# Down the tunnel: in at the south mouth, round the chamber, out at the
	# east mouth. The two legs are laid separately so neither runs through the
	# other in the corner.
	[Vector2(-17.8, 7.0), Vector2(-17.8, 18.4)],
	[Vector2(-18.6, 17.8), Vector2(-7.5, 17.8)],
	# Out of the east mouth and away along the north band toward the far base.
	[Vector2(-7.0, 17.8), Vector2(9.0, 17.8)],
	# Its rotational twin, so the two halves of the floor carry the same iron.
	[Vector2(7.0, -17.8), Vector2(-9.0, -17.8)],
	# The siding in each lane, where a quarry parks the tubs it is not using.
	# **Nowhere near the rim**, which is where the first two passes put it and
	# both were wrong for the same reason: each base's two haul ramps run flush
	# against the cliff, from the floor all the way to the bench, so the three
	# metres of floor beside every rim on this map is a road — and a rail laid
	# on it is a rail laid up the road nobody may be blocked on, with a cart
	# parked halfway up and buried in the slope.
	[Vector2(-13.5, -2.0), Vector2(-13.5, -10.0)],
	[Vector2(13.5, 2.0), Vector2(13.5, 10.0)],
]

## The minecarts, and the one piece of the pack that is also *map*: a cart is
## about a Bog's chest high, so it reads as cover from across the pit, so it has
## to be cover. Each entry gets a `KERB_TOP` box of code-built collision under
## the art and a `platforms` record on top, exactly the way the spoil rocks do.
##
##   at    where it stands, on the floor.
##   yaw   which way it points, in radians, before the turn.
##   model which of the two plain carts it is.
##   turn  whether the entry is a rotational pair. **Default true, and false is
##         not an oversight.** A cart in the tunnel's corner chamber has no
##         partner, because the turn of that chamber is the inside of the
##         south-east terraces — solid rock three metres up — and a cart placed
##         there is a cart buried in a hill. Everything on the bisector is like
##         this, which is the price of the bisector being where the asymmetry
##         is allowed to live.
const CART_MODELS := {"plain": "mining_cart_01", "wooden": "wooden_minecart_01"}
## What a cart is built to: 1.2 m tall, which is a kerb, and about 1.4 m long,
## which is a real narrow-gauge tub.
const CART_HEIGHT := KERB_TOP
## The collision box hidden inside the cart's body, as half-extents on the
## ground plane. Smaller than the art, because the art's wheels and handles
## stick out and nobody should be stopped by a handle.
const CART_BOX := Vector2(0.58, 0.40)
const CART_STANDS: Array[Dictionary] = [
	# In the tunnel's corner chamber, beside the letter card. On the bisector,
	# so it has no turn — see `turn`, above.
	{"label": "cart chamber", "at": Vector2(-18.9, 18.6), "yaw": 0.0,
		"model": "wooden", "turn": false},
	# Out on the north band, on the rail run, where it is the only cover in
	# eleven metres. Its turn stands on the south band's run.
	{"label": "cart north", "at": Vector2(0.0, 17.8), "yaw": 0.0, "model": "plain"},
	# On the siding in each lane, standing on its own rail.
	{"label": "cart siding", "at": Vector2(-13.5, -6.0), "yaw": PI * 0.5,
		"model": "plain"},
]

## The ore standing about the pit: five rocks off the pack, scattered by table
## rather than by a draw so the two halves get the same stone. Each is built
## about 1.1 m across, which is under a kerb and is **not** collision — an ore
## boulder is a thing to look at, and anything on this map you can stand on is
## declared.
const ORE_MODELS: PackedStringArray = ["iron_ore_rock_01", "mossy_coal_ore_rock_01",
	"mossy_copper_ore_rock_01", "mossy_sulfur_ore_rock_01", "mossy_gold_ore_rock_01"]
const ORE_SPAN := 1.1
## Where the ore sits, as (position, which model). Written once and turned.
const ORE_PILES: Array[Dictionary] = [
	{"at": Vector2(-16.0, -10.0), "model": 0},
	{"at": Vector2(-9.0, -12.0), "model": 1},
	{"at": Vector2(-4.0, -13.5), "model": 2},
	{"at": Vector2(-12.5, -2.0), "model": 3},
	{"at": Vector2(-18.0, -1.0), "model": 4},
	{"at": Vector2(-14.5, 9.0), "model": 1},
]

## The barrels: powder kegs, stacked against a face at each base and in the
## tunnel. 0.95 m tall, which is under everything, and no collision.
const BARREL_MODEL := "wooden_barrel_01"
const BARREL_HEIGHT := 0.95
## Absolute, and **not** a turned table: three of the five stand in the tunnel,
## which is on the bisector and has no partner.
const BARRELS: Array[Vector2] = [
	Vector2(-16.5, 16.6), Vector2(-15.9, 17.3), Vector2(-16.9, 17.5),
	Vector2(-15.2, 8.6), Vector2(-14.6, 9.2),
	Vector2(-12.4, -9.5), Vector2(-11.9, -10.1),
	Vector2(12.4, 9.5), Vector2(11.9, 10.1),
]

## The signs. `mineshaft_sign_01` is a plain timber board and is the only sign
## in the pack with no fantasy on it, so it is the only one used: one at each
## tunnel mouth, on a post, at a Bog's eye height.
const SIGN_MODEL := "mineshaft_sign_01"
const SIGN_WIDE := 1.7
const SIGN_HEIGHT := 2.1
const SIGNS: Array[Dictionary] = [
	{"at": Vector2(-14.6, 9.4), "yaw": 0.0},
	{"at": Vector2(-9.4, 16.8), "yaw": PI * 0.5},
]

## The hoist ropes hanging off the two derricks' booms, so the skyline has
## something in it that moves the eye down into the pit.
const ROPE_MODEL := "steel_rope_01"
## How much of the drop is the model, and how much is the steel fall drawn above
## it. See `_build_ropes` for why the model is not simply asked for all of it.
const ROPE_DROP := 2.6
const ROPE_FALL := 9.0

# ------------------------------------------------------------------- state ---

var columns: int = 0
var blocks: int = 0
var kerbs: int = 0
var rocks: int = 0
var carts: int = 0

var _floor_st: SurfaceTool
## One per team: a base is built out of its own team's brick, so the two benches
## cannot share a mesh the way the rest of the stone does.
var _bench_st: Array[SurfaceTool] = []
var _carved_st: SurfaceTool
var _rim_st: SurfaceTool
var _raw_st: SurfaceTool
var _road_st: SurfaceTool
var _timber_st: SurfaceTool

var _stone_material: StandardMaterial3D
## The same rock as `_stone_material` at a finer tile — see `_build_materials`.
var _raw_material: StandardMaterial3D
var _carved_material: StandardMaterial3D
var _brick_material: StandardMaterial3D
var _floor_material: StandardMaterial3D
var _road_material: StandardMaterial3D
var _steel_material: StandardMaterial3D
var _rust_material: StandardMaterial3D
var _timber_material: StandardMaterial3D
## Corrugated sheet, on the shelters, the hopper and the conveyor hood.
var _iron_material: StandardMaterial3D
## The gabion fill and the sandbags at the bases.
var _sand_material: StandardMaterial3D
var _water_material: StandardMaterial3D
var _lamp_material: StandardMaterial3D
var _rubble_material: StandardMaterial3D
var _spoil_material: StandardMaterial3D

## Where the work lamps ended up, handed to the ambience so the dust in the
## beams belongs to the beams rather than to a second guess at where they are.
var _lamp_heads: Array[Vector3] = []

## The straw-tinted copies of the MegaKit's greenery materials, one per mesh and
## tint. See `_dry_material`: without the cache every multimesh gets its own
## duplicate and the renderer sees a different material on every draw.
var _dry_cache: Dictionary = {}


func _ready() -> void:
	var started := Time.get_ticks_msec()
	_build_materials()

	_floor_st = _begin()
	_bench_st = [_begin(), _begin()]
	_carved_st = _begin()
	_rim_st = _begin()
	_raw_st = _begin()
	_road_st = _begin()
	_timber_st = _begin()

	_build_floor()
	_build_shaft()
	_build_monolith()
	_build_rim()
	for at: Vector2 in turned(BASE_AT):
		_build_base(at)
	_build_corner_bench()
	_build_terraces()
	_build_catwalks()
	_build_pit()
	# **Above the commits, not between them.** These write boxes into
	# `_carved_st`, and a `SurfaceTool` that has already been committed accepts
	# vertices and throws them away: called after `_commit`, as it was, every
	# cart was a kerb that a Bog walked straight through and that
	# `parkour_report` reported as "the rock is at 0.00".
	_build_cart_stands()

	var solid := _group("Quarry")
	_commit(solid, "Floor", _floor_st, _floor_material, FLOOR_GRAVEL)
	for team: int in 2:
		# **Both walls commit with the same tint.** The team colour used to be
		# in this line, and taking it out is the point of the visuals pass:
		# `_build_base_identity` puts it back as paint, banners, a stencil and
		# a tarp, which is where a working site carries a colour and is also
		# where it can be seen from across a pit without the cover it is
		# painted on stopping reading as cover.
		_commit(solid, "Base%d" % (team + 1), _bench_st[team], _brick_material,
			STONE_BENCH)
	_commit(solid, "CarvedStone", _carved_st, _carved_material, STONE_CUT)
	_commit(solid, "Rim", _rim_st, _stone_material, STONE_RIM)
	_commit(solid, "RawStone", _raw_st, _raw_material, STONE_RAW)
	_commit(solid, "HaulRoad", _road_st, _road_material, HAUL_ROAD)
	_commit(solid, "Timber", _timber_st, _timber_material, TIMBER)
	# Above `super()` on purpose: a rock the size of a Bog reads as cover from
	# across the pit, so it is cover. The carts' boxes went in before the
	# commits, above.
	_build_rocks(solid)

	_plan_landings()

	print("%s: %d columns, %d blocks, %d kerbs, %d rocks, %d carts, %d landings, %d off limits in %d ms" % [
		name, columns, blocks, kerbs, rocks, carts, platforms.size(),
		off_limits.size(), Time.get_ticks_msec() - started])

	# Everything above this line becomes collision. Everything below it does not.
	super()

	var dressing := _group("Dressing")
	# **Relief first.** Everything under `_build_relief` sits against a face
	# that is already built, and the things after it — the scatter's aprons, the
	# pack's ore heaps — are placed relative to the same faces. Order does not
	# matter to the renderer; it matters to whoever reads this list and wants to
	# know what is holding what up.
	_build_relief(dressing)
	_build_props(dressing)
	_build_puddles(dressing)
	_build_kerb_paint(dressing)
	_build_derricks(dressing)
	_build_plant(dressing)
	_build_base_identity(dressing)
	_build_lamps(dressing)
	_build_pack(dressing)
	QuarryAmbience.build(self, HALF, HOLE_HALF, _lamp_heads)


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
## is Team 1's, and 1 for its turn. `Bases` in the scene is in team order and
## its first child is the negative corner, so these agree by construction.
static func team_of(at: Vector2) -> int:
	return 0 if at.x + at.y < 0.0 else 1


## A team's brick, derived from the team's own colour rather than picked to look
## like it. `Nameplate.TEAM_COLOURS` is what the plates, the kill feed, the
## scoreboard and `CaptureBase`'s ring on this very bench are all drawn in, so a
## base painted from anywhere else is a base that drifts out of step with them
## the first time that table is edited.
static func brick_for_team(team: int) -> Color:
	return Nameplate.colour_for_team(team).darkened(0.42).lerp(Color(0.44, 0.31, 0.23), 0.40)


## The two factors a half needs, and the one thing about this file that is easy
## to get wrong.
##
## `sign` turns a *magnitude* into a coordinate on this half: `sign * HALF` is
## the rim's inner face, -24 or +24. `flip` turns a *table value*, which is
## already written negative, into one on this half: it is 1 on the half the
## tables were written for and -1 on its turn. Using `sign` on a table value
## puts the ramps on the wrong side of the map.
static func factors(at: Vector2) -> Vector2:
	var sign := signf(at.x)
	return Vector2(sign, -sign)


## The pit floor, and it stops at the rim's inner face rather than running under
## it. A floor that ran on under the cliff would be standable ground the
## sightline scan could find *inside* the rock, with nothing between two such
## points to stop a ray — which is how this map first measured a 46 m sightline
## through solid stone.
##
## Four slabs round the shaft rather than one across the pit: a picture frame,
## so the hole in the middle is a hole in the *collision* and not a hole painted
## on a floor a Bog walks over. **The four are trimmed against each other**;
## north and south run the full width and east and west are cut back to the band
## between them, because two coplanar tops at y = 0 is not a thicker floor, it
## is a depth-buffer tie.
func _build_floor() -> void:
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
## **Two solids may not share a face plane**, and both seams below were one when
## this was first built (D-089). The upper slabs stop at the floor's underside
## so the floor alone owns y = 0; the lower runs are trimmed against each other
## at the corners so the ledge top is one face and not two.
func _build_shaft() -> void:
	var h := HOLE_HALF
	var l := h + HOLE_LEDGE_WIDTH
	for side: int in 4:
		var lo := Vector2(-l, -l) if side < 2 else Vector2(-l, -h)
		var hi := Vector2(l, -h) if side < 2 else Vector2(-h, h)
		if side == 1:
			lo = Vector2(-l, h); hi = Vector2(l, l)
		elif side == 3:
			lo = Vector2(h, -h); hi = Vector2(l, h)
		_slab(_rim_st, lo, hi, HOLE_LEDGE, -FLOOR_THICK)
	var t := LEDGE_TREAD
	for side: int in 4:
		var lo := Vector2(-h, -h) if side < 2 else Vector2(-h, -h + t)
		var hi := Vector2(h, -h + t) if side < 2 else Vector2(-h + t, h - t)
		if side == 1:
			lo = Vector2(-h, h - t); hi = Vector2(h, h)
		elif side == 3:
			lo = Vector2(h - t, -h + t); hi = Vector2(h, h - t)
		_slab(_rim_st, lo, hi, HOLE_FLOOR, HOLE_LEDGE)
	# The floor of it, far below the height a fall has already killed at. Its
	# top is at `HOLE_FLOOR` and the four walls *stand on* that, so the two meet
	# along an edge and not in a plane.
	_slab(_floor_st, Vector2(-h, -h), Vector2(h, h), HOLE_FLOOR - FLOOR_THICK, HOLE_FLOOR)


## The monolith standing in the shaft: five stacked slabs, each a little smaller
## than the one under it, from the shaft floor to twelve metres over the pit's.
##
## Stacked rather than tapered because a taper is a cone and a cone is the one
## shape a quarry never leaves behind — rock comes away in lifts, so a core left
## standing is stepped. It is also what makes it readable as *rock* at forty
## metres against a sky, which a smooth spike is not.
##
## It is `off_limits`: twelve metres is over every jump the Bog has by a factor
## of three, and the report fails the build if that ever stops being true.
func _build_monolith() -> void:
	var span := MONOLITH_TOP - HOLE_FLOOR
	for step: int in MONOLITH_STEPS:
		var low := float(step) / float(MONOLITH_STEPS)
		var high := float(step + 1) / float(MONOLITH_STEPS)
		var half := lerpf(MONOLITH_BASE_HALF, MONOLITH_TOP_HALF, low)
		_slab(_raw_st, Vector2(-half, -half), Vector2(half, half),
			HOLE_FLOOR + span * low, HOLE_FLOOR + span * high)
	off_limits.append(Platform.new(Vector3(0.0, MONOLITH_TOP, 0.0),
		MONOLITH_TOP_HALF - 0.15, "monolith", "monolith"))


## The cliff on all four sides. Built as four overlapping slabs so the corners
## are solid rock rather than four edges meeting on a line, and started below
## the floor so there is no seam along the bottom of it.
##
## The terracing is all **above** `RIM_TOP` and stepped *outward*, so from
## inside the pit the wall is one clean eleven-metre face and the benches behind
## it climb away against the sky. Stepping it inward — which is what a worked
## quarry actually looks like — would put a ledge in the middle of that face,
## and a ledge is a perch.
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
	# anybody stand on.
	var mid := (HALF + out) * 0.5
	var names := ["north", "south", "west", "east"]
	var spots := [Vector2(0.0, -mid), Vector2(0.0, mid), Vector2(-mid, 0.0), Vector2(mid, 0.0)]
	for i: int in 4:
		var at: Vector2 = spots[i]
		off_limits.append(Platform.new(Vector3(at.x, RIM_TOP, at.y),
			RIM_THICKNESS * 0.5 - 0.15, "rim", "rim %s" % names[i]))


# -------------------------------------------------------------- the bases ---

## One base, whole: the bench it stands on, the wall round the pad, the two haul
## ramps into it and every landing record any of them owns.
##
## **This is the function the brief's "two identical bases" is satisfied by.**
## `_ready` calls it once for each of `turned(BASE_AT)`, so a base exists twice
## and is written once — there is no second copy of any number in it to drift.
## A 180 degree turn maps an axis-aligned box to an axis-aligned box, so the
## turned base is congruent to the written one and not merely similar to it.
func _build_base(at: Vector2) -> void:
	var sign := factors(at).x
	var outer := sign * HALF
	var inner := sign * BENCH_INNER
	# **The bench is cut stone and only the wall is brick.** Both were brick
	# until the first look at it: a twelve-metre floor of team-coloured
	# brickwork under a hard sun reads as the bottom of a swimming pool, and it
	# put the loudest surface on the map where a player spends the most time
	# looking straight down. The wall is 1.8 m and vertical, which is where a
	# team colour actually does its job — you see whose base it is from across
	# the pit, in silhouette, and the ground you stand on is the quarry.
	var st: SurfaceTool = _bench_st[team_of(at)]
	_slab(_carved_st, Vector2(minf(outer, inner), minf(outer, inner)),
		Vector2(maxf(outer, inner), maxf(outer, inner)), 0.0, BENCH_TOP)
	_build_wall(at, st)
	_build_ramps(at)
	_plan_base_landings(at)


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
		# **The doorway is widened after the flip, not before it.** Written the
		# other way round — `flip * span.y - DOOR_MARGIN` — the margin lands on
		# whichever end of the span the flip happens to have made the low one,
		# so the door comes out 0.4 m narrower on one base and 0.4 m wider on
		# the other, and the wall run beside it is 0.2 m out of place. That is
		# not a thing anybody sees, and it is exactly the thing
		# `tools/quarry_check.gd` was written to catch: it turned team 1's wall
		# landings half a turn and found team 2's 0.2 m away. Two bases built by
		# one function are only identical if every number in it is applied in a
		# frame the flip has already been taken out of.
		var door := Vector2(minf(flip * span.x, flip * span.y) - DOOR_MARGIN,
			maxf(flip * span.x, flip * span.y) + DOOR_MARGIN)
		var gaps: Array[Vector2] = [door]
		if axis == "x":
			gaps.append(Vector2(minf(flip * PORT.x, flip * PORT.y),
				maxf(flip * PORT.x, flip * PORT.y)))
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
			# arrives at is x — the run itself is in z.
			var fat := Vector2(WALL_THICK * 0.5, 0.0) if axis == "x" \
				else Vector2(0.0, WALL_THICK * 0.5)
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - fat
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + fat
			_slab(st, lo, hi, BENCH_TOP, top)
			# A perch only on the long runs. The two runs meet at the bench's
			# inner corner, so the short one's middle is 1.2 m from the other
			# wall — and a Bog standing there has its capsule inside it. The
			# wall is still built; it simply is not advertised as somewhere to
			# stand, which is honest, because it is not.
			if run.y - run.x < 3.0:
				continue
			var centre := (lo + hi) * 0.5
			platforms.append(Platform.new(Vector3(centre.x, top, centre.y),
				WALL_THICK * 0.5 - 0.15, "wall", "wall %s %s %d" % [side, axis, k]))


## The two haul ramps into one base: a wedge of compacted road, solid underneath
## so there is no gap beside it to get stuck in.
func _build_ramps(at: Vector2) -> void:
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


# ------------------------------------------- the spoil bench and its tunnel ---

## The north-west corner: a mass of tipped spoil with an L-shaped adit bored
## through it, and the haul ramp onto its top.
##
## **The mass is five slabs round the void rather than one slab with a hole in
## it**, because a `SurfaceTool` has no boolean and a trimesh sweep has no
## opinion about interiors: a corridor cut out of a box by subtracting geometry
## that was never built is a corridor you walk through the walls of. So the rock
## is built as the five boxes that are left when the L is taken out of the
## rectangle, plus two roof slabs over the corridor, and the union of those
## seven is exactly the mass minus the tunnel — which is checkable by reading
## the spans, and is.
##
## The corridor's floor is the pit floor: `_build_floor` has already laid y = 0
## right across here, so nothing extra is built and there is no seam under a
## player's feet.
func _build_corner_bench() -> void:
	var ax: Vector2 = TUNNEL_A_X
	var bz: Vector2 = TUNNEL_B_Z
	var x0 := CORNER_X.x
	var x1 := CORNER_X.y
	var z0 := CORNER_Z.x
	var z1 := CORNER_Z.y
	var turn: Vector2 = TUNNEL_TURN

	# West of leg A, the full depth of the bench.
	_slab(_rim_st, Vector2(x0, z0), Vector2(ax.x, z1), 0.0, CORNER_TOP)
	# East of leg A and south of leg B.
	_slab(_rim_st, Vector2(ax.y, z0), Vector2(x1, bz.x), 0.0, CORNER_TOP)
	# North of leg B, spanning everything east of leg A's west wall.
	_slab(_rim_st, Vector2(ax.x, turn.y), Vector2(x1, z1), 0.0, CORNER_TOP)
	# The two roofs, from the corridor's ceiling up to the bench top — **and
	# their undersides**, which is the one face `_slab` does not draw.
	#
	# `_slab` builds a top and four sides and no bottom, which is right for
	# every other solid on this map because every other solid stands on the
	# floor and nobody can get under it. The tunnel is the first thing here with
	# a player *beneath* a slab, and without this the corridor was roofed in
	# collision and open to the sky in the picture: you walked under four metres
	# of rock and watched the clouds go past through it.
	_slab(_rim_st, Vector2(ax.x, z0), Vector2(ax.y, turn.y), TUNNEL_TOP, CORNER_TOP)
	_slab(_rim_st, Vector2(ax.y, bz.x), Vector2(turn.x, bz.y), TUNNEL_TOP, CORNER_TOP)
	_soffit(_rim_st, Vector2(ax.x, z0), Vector2(ax.y, turn.y), TUNNEL_TOP)
	_soffit(_rim_st, Vector2(ax.y, bz.x), Vector2(turn.x, bz.y), TUNNEL_TOP)

	_build_timbering()

	# The haul ramp up the south face, east of the mouth.
	_wedge(_road_st, "z", CORNER_RAMP_X, CORNER_RAMP_Z.x, CORNER_RAMP_Z.y,
		0.0, CORNER_TOP)

	# The bench top, as landings. The corridor is under it and is its own set.
	var keep: Array[Rect2] = []
	_tile(Rect2(Vector2(x0, z0), Vector2(x1 - x0, z1 - z0)), CORNER_TOP,
		"spoil bench", "spoil bench", keep)
	# The ramp, a record every 0.9 m of rise, which is what chains the floor to
	# the bench: the lowest is a hop from flat ground and each is a hop from the
	# one below.
	var mid := (CORNER_RAMP_X.x + CORNER_RAMP_X.y) * 0.5
	var rise := 0.9
	var k := 1
	while rise * float(k) < CORNER_TOP - 0.3:
		var y := rise * float(k)
		var along := lerpf(CORNER_RAMP_Z.x, CORNER_RAMP_Z.y, y / CORNER_TOP)
		platforms.append(Platform.new(Vector3(mid, y + RAMP_LIFT, along),
			RAMP_WIDTH * 0.5 - 0.15, "ramp", "spoil ramp %d" % k))
		k += 1

	# The corridor floor, as landings, so the reachability walk knows the tunnel
	# is a route and not a hole in the graph. One every 3 m down each leg.
	var steps := int((turn.y - z0) / 3.0)
	for i: int in steps:
		var z := lerpf(z0 + 1.5, turn.y - 1.5, float(i) / maxf(1.0, float(steps - 1)))
		platforms.append(Platform.new(Vector3(mid, 0.0, z),
			TUNNEL_WIDE * 0.5 - 0.4, "tunnel", "adit south %d" % i))
	var bmid := (bz.x + bz.y) * 0.5
	steps = int((turn.x - ax.y) / 3.0)
	for i: int in steps:
		var x := lerpf(ax.y + 1.5, turn.x - 1.5, float(i) / maxf(1.0, float(steps - 1)))
		platforms.append(Platform.new(Vector3(x, 0.0, bmid),
			TUNNEL_WIDE * 0.5 - 0.4, "tunnel", "adit east %d" % i))


## The timbering in the adit: a set of props and a cap every few metres down
## each leg, and a heavier one at each mouth.
##
## It is **collision**, deliberately, and it is what the pack's tunnel models are
## not allowed to be. A stone-mouthed portal out of `art/maps/quarry/` is a
## one-metre diorama of a mound with a hole in one end; scaled until its opening
## matches a four-metre corridor the mound behind it is ten metres long, and the
## only place to put ten metres of modelled mound at a mouth is the corridor —
## which is the one place it must not go. That is exactly what the first pass
## did, and standing at the bend you could not see either exit. So the mouths
## are framed here, out of boxes, and the pack's adits stand against the rim
## instead where there is real rock behind them; see `_build_adits`.
##
## The numbers are the corridor's, less what a frame takes: a post is 0.3 m and
## sits with its outer face on the wall plane, so the clear width goes 4.0 to
## 3.4, and a cap is 0.32 m deep, so the clear height under a rib goes 3.4 to
## 3.08. Both are still over what the third-person camera needs (3.0 and 2.8),
## which is the whole reason the corridor was cut oversize to begin with.
func _build_timbering() -> void:
	var ax: Vector2 = TUNNEL_A_X
	var bz: Vector2 = TUNNEL_B_Z
	var post := 0.3
	var cap := 0.32
	# Leg A: ribs across x, spaced down z, the mouth's set heaviest.
	var ribs_a := [CORNER_Z.x + 0.35, 13.2, 16.6]
	for i: int in ribs_a.size():
		var z: float = ribs_a[i]
		var thick := post * (1.4 if i == 0 else 1.0)
		_slab(_timber_st, Vector2(ax.x, z - thick * 0.5),
			Vector2(ax.x + post, z + thick * 0.5), 0.0, TUNNEL_TOP)
		_slab(_timber_st, Vector2(ax.y - post, z - thick * 0.5),
			Vector2(ax.y, z + thick * 0.5), 0.0, TUNNEL_TOP)
		_slab(_timber_st, Vector2(ax.x, z - thick * 0.5),
			Vector2(ax.y, z + thick * 0.5), TUNNEL_TOP - cap, TUNNEL_TOP)
	# Leg B: ribs across z, spaced along x, the east mouth's heaviest.
	var ribs_b := [CORNER_X.y - 0.35, -13.2, -16.6]
	for i: int in ribs_b.size():
		var x: float = ribs_b[i]
		var thick := post * (1.4 if i == 0 else 1.0)
		_slab(_timber_st, Vector2(x - thick * 0.5, bz.x),
			Vector2(x + thick * 0.5, bz.x + post), 0.0, TUNNEL_TOP)
		_slab(_timber_st, Vector2(x - thick * 0.5, bz.y - post),
			Vector2(x + thick * 0.5, bz.y), 0.0, TUNNEL_TOP)
		_slab(_timber_st, Vector2(x - thick * 0.5, bz.x),
			Vector2(x + thick * 0.5, bz.y), TUNNEL_TOP - cap, TUNNEL_TOP)


## The south-east corner: three quarry steps to the same height the spoil bench
## reaches, and nothing on any of them.
##
## Each is a plain slab from the rim's two inner faces inward, so they nest and
## the corner is solid rock underneath rather than three shelves on legs. Every
## riser is 1.5 m, which is under the Bog's 1.69 m standing jump: there is no
## face of this corner you cannot get up, which is the whole difference between
## it and the bench with the tunnel in it.
func _build_terraces() -> void:
	for entry: Dictionary in TERRACES:
		var x: Vector2 = entry["x"]
		var z: Vector2 = entry["z"]
		var top := float(entry["top"])
		_slab(_carved_st, Vector2(x.x, z.x), Vector2(x.y, z.y), 0.0, top)
		# Every step above this one, so a tile on the low terrace is never
		# planned under the rock of the one standing on top of it.
		var keep: Array[Rect2] = []
		for other: Dictionary in TERRACES:
			if float(other["top"]) <= top:
				continue
			var ox: Vector2 = other["x"]
			var oz: Vector2 = other["z"]
			keep.append(Rect2(Vector2(ox.x, oz.x), Vector2(ox.y - ox.x, oz.y - oz.x)))
		_tile(Rect2(Vector2(x.x, z.x), Vector2(x.y - x.x, z.y - z.x)), top,
			"terrace", String(entry["label"]), keep)


## The two catwalks over the shaft, and their rails.
##
## The deck's **top is y = 0**, level with the floor it runs out of, so stepping
## onto one is stepping onto the same ground — there is no lip to trip a Bog at
## a run and no step to break a slide. What makes it a risk is what is under it:
## nothing, for fifteen metres, and `void_height` is -10.
func _build_catwalks() -> void:
	for z: float in [CATWALK_Z, -CATWALK_Z]:
		var flip := signf(z)
		var lo := z - CATWALK_WIDE * 0.5
		var hi := z + CATWALK_WIDE * 0.5
		var gap := Vector2(flip * CATWALK_GAP.x, flip * CATWALK_GAP.y)
		var cut := Vector2(minf(gap.x, gap.y), maxf(gap.x, gap.y))
		var runs: Array[Vector2] = [
			Vector2(-CATWALK_REACH, cut.x), Vector2(cut.y, CATWALK_REACH)]
		for run: Vector2 in runs:
			if run.y - run.x < 0.5:
				continue
			_slab(_timber_st, Vector2(run.x, lo), Vector2(run.y, hi),
				-CATWALK_DROP, 0.0)
			var mid := (run.x + run.y) * 0.5
			platforms.append(Platform.new(Vector3(mid, 0.0, z),
				CATWALK_WIDE * 0.5 - 0.2, "catwalk",
				"catwalk %s %.0f" % [half_of(Vector2(0.0, z)), mid]))
			# The rail, on the outer side — away from the monolith — so the
			# player's eye has the drop on the inside where the fight is.
			var rail_z := hi if z > 0.0 else lo
			var post := 0.14
			_slab(_timber_st, Vector2(run.x, rail_z - post), Vector2(run.y, rail_z),
				RAIL_TOP - 0.16, RAIL_TOP)
			for t: float in [0.12, 0.5, 0.88]:
				var px := lerpf(run.x, run.y, t)
				_slab(_timber_st, Vector2(px - post * 0.5, rail_z - post),
					Vector2(px + post * 0.5, rail_z), 0.0, RAIL_TOP)


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

	for entry: Dictionary in BERMS:
		var at: Vector2 = entry["at"]
		_stand(_carved_st, at, entry["size"], BERM_TOP)
		platforms.append(Platform.new(Vector3(at.x, BERM_TOP, at.y),
			_inscribed(entry["size"]), "berm", String(entry["label"])))
		blocks += 1

	for entry: Dictionary in KERBS:
		for at: Vector2 in turned(entry["at"]):
			_stand(_carved_st, at, entry["size"], KERB_TOP)
			platforms.append(Platform.new(Vector3(at.x, KERB_TOP, at.y),
				_inscribed(entry["size"]), "kerb",
				"%s %s" % [entry["label"], half_of(at)]))
			kerbs += 1


## Where one cart entry stands: both halves of the map, or only the one written.
static func _cart_spots(entry: Dictionary) -> Array[Vector2]:
	if not bool(entry.get("turn", true)):
		var one: Array[Vector2] = [entry["at"]]
		return one
	return turned(entry["at"])


## The spoil rocks, and one of the two kit models on this map a Bog cannot walk
## through.
##
## A quarry's waste is the biggest loose stone in the pit, and at the size the
## MegaKit draws a `Rock_Medium` it reads as cover from right across the floor —
## so it has to *be* cover. They are built here, **above `super()`**, as plain
## `MeshInstance3D`s, because `StaticMap._build_collision` sweeps every
## `MeshInstance3D` under the map into world-space collision and a
## `MultiMeshInstance3D` is a picture.
##
## **Every one is squashed until its top is exactly `KERB_TOP`.** At the
## scatter's own scale a rock stood about 1.5 m — a fourth height on a map whose
## language is a fixed set of them, and a thing to stand on that no table
## mentions. At 1.2 a rock simply *is* a kerb, and is declared like one. It is
## sat on the floor by its own bounding box rather than by eye.
func _build_rocks(parent: Node3D) -> void:
	var group := _group("Spoil", parent)
	for entry: Dictionary in SPOIL_ROCKS:
		var model: String = BOULDERS[int(entry["model"]) % BOULDERS.size()]
		var mesh := PropScatter.load_kit_mesh(model)
		if mesh == null:
			continue
		var box := mesh.get_aabb()
		var wide := ROCK_SPAN / maxf(box.size.x, box.size.z)
		var tall := KERB_TOP / box.size.y
		var pair := turned(entry["at"])
		for k: int in pair.size():
			var at: Vector2 = pair[k]
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


## The block of collision a minecart stands on, and the reason the carts are the
## second thing above the `super()` line.
##
## A cart out of the pack is 1.2 m of solid-looking iron and timber: a player
## who sees one from twenty metres will use it as cover, and a player who walks
## into one and passes through it has learned that this map lies. So each cart
## gets **a box built here, in code, out of `_slab`** — not the trimesh of a
## five-thousand-triangle art asset, which is both forty times the collision and
## a shape with wheels and handles on it that a Bog would snag on.
##
## The box is inside the art, and the art is what you see; the box is 1.16 by
## 0.80 and is what you touch. The landing on top is a kerb like any other, so
## the cart is a step in the map's own height language rather than a fourth one.
func _build_cart_stands() -> void:
	for entry: Dictionary in CART_STANDS:
		var yaw := float(entry["yaw"])
		var spots := _cart_spots(entry)
		for k: int in spots.size():
			var at: Vector2 = spots[k]
			var turn := yaw + PI * float(k)
			# The box is axis-aligned, so a cart turned a quarter swaps its
			# extents rather than rotating a slab this file cannot rotate.
			var along := absf(cos(turn))
			var half := Vector2(
				lerpf(CART_BOX.y, CART_BOX.x, along),
				lerpf(CART_BOX.x, CART_BOX.y, along))
			_slab(_carved_st, at - half, at + half, 0.0, CART_HEIGHT)
			platforms.append(Platform.new(Vector3(at.x, CART_HEIGHT, at.y),
				minf(half.x, half.y) - 0.1, "cart",
				"%s %d" % [entry["label"], k + 1]))
			carts += 1


# ---------------------------------------------------------------- landings ---

## The bench top and the ramps of one base, as the parkour report reads them.
##
## The bench is tiled rather than given one record, because one circle in the
## middle of a twelve-metre floor would call its corners unlandable and would
## also promise rock where the wall stands. The ramps get a record every 0.9 m
## of rise, which is what chains the floor to the bench: the lowest sits at
## 0.9 m and is a hop from flat ground, and each one after it is a hop from the
## one below (D-057's pattern, and the reason a ramp is a route and not a
## cliff).
func _plan_base_landings(at: Vector2) -> void:
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


## The whole map's landing planner, for everything that is not a base. Kept as
## its own call so `_ready` reads as a list of places rather than a list of
## steps.
func _plan_landings() -> void:
	pass


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


## Whether a point on the pit floor is standing on something other than the
## floor — a base bench, the spoil bench, a terrace, or the hole.
##
## Every scatter asks this before it places anything. The apron round the foot
## of the cliff walks all four sides of the pit and two of those sides now run
## behind four-metre masses, so without this the weeds bank against a face that
## is four metres over their heads.
static func _blocked(at: Vector2) -> bool:
	if _in_hole(at):
		return true
	if at.x > CORNER_X.x and at.x < CORNER_X.y \
			and at.y > CORNER_Z.x and at.y < CORNER_Z.y:
		return true
	if at.x > -CORNER_X.y and at.x < -CORNER_X.x \
			and at.y > -CORNER_Z.y and at.y < -CORNER_Z.x:
		return true
	for entry: Dictionary in TERRACES:
		var x: Vector2 = entry["x"]
		var z: Vector2 = entry["z"]
		if at.x > x.x and at.x < x.y and at.y > z.x and at.y < z.y:
			return true
	for base: Vector2 in turned(BASE_AT):
		var sign := factors(base).x
		var lo := minf(sign * HALF, sign * BENCH_INNER)
		var hi := maxf(sign * HALF, sign * BENCH_INNER)
		if at.x > lo and at.x < hi and at.y > lo and at.y < hi:
			return true
	return false


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
	_build_scrub(batch, rng)

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
	# The spoil bench, both halves — it is tipped waste, so it sheds the coarse
	# rubble raw stone does.
	out.append({"rect": Rect2(Vector2(CORNER_X.x, CORNER_Z.x),
		Vector2(CORNER_X.y - CORNER_X.x, CORNER_Z.y - CORNER_Z.x)),
		"top": CORNER_TOP, "raw": true})
	out.append({"rect": Rect2(Vector2(-CORNER_X.y, -CORNER_Z.y),
		Vector2(CORNER_X.y - CORNER_X.x, CORNER_Z.y - CORNER_Z.x)),
		"top": CORNER_TOP, "raw": true})
	for entry: Dictionary in TERRACES:
		var x: Vector2 = entry["x"]
		var z: Vector2 = entry["z"]
		out.append({"rect": Rect2(Vector2(x.x, z.x), Vector2(x.y - x.x, z.y - z.x)),
			"top": float(entry["top"]), "raw": false})
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
			# **Mostly stone.** The first mix was 40/52/8 rubble, weed, bloom
			# and the pit came out fringed in green. A quarry's apron is chips
			# off the face it fell from with a tuft of dry grass every few
			# metres, so rubble takes three quarters of the draw and the scrub
			# is down to one in fifty.
			var pick := rng.randf()
			if pick < (0.86 if raw else 0.74):
				_place(batch, rng, RUBBLE, at, 0.0, RUBBLE_SCALE)
			elif pick < 0.98:
				_place(batch, rng, WEEDS, at, 0.0, WEED_SCALE)
			else:
				_place(batch, rng, SCRUB, at, 0.0, SCRUB_SCALE)


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
func _build_scrub(batch: Dictionary, rng: RandomNumberGenerator) -> void:
	for spot: Vector2 in PUDDLES:
		# Four, not nine, and only one of them is scrub. A puddle in a quarry is
		# a rain pool on a rock floor that will be gone by Thursday; it does not
		# get a flowerbed round it, which is what nine bushes at every one of
		# six puddles was.
		for i: int in 4:
			var bearing := TAU * (float(i) + rng.randf()) / 4.0
			var at := spot + Vector2(cos(bearing), sin(bearing)) * rng.randf_range(2.4, 3.8)
			if absf(at.x) > HALF - 0.5 or absf(at.y) > HALF - 0.5 or _in_hole(at):
				continue
			_place(batch, rng, SCRUB if i == 0 else WEEDS, at, 0.0,
				SCRUB_SCALE if i == 0 else WEED_SCALE)


## One prop into the batch: a model out of `models`, at `at` on the floor (or on
## `floor_y`), yawed at random and scaled somewhere in `scale`.
func _place(batch: Dictionary, rng: RandomNumberGenerator, models: PackedStringArray,
		at: Vector2, tilt: float, scale: Vector2, floor_y: float = 0.0) -> void:
	# Nothing is scattered onto a point that is not the floor it was measured
	# against. A weed placed at y = 0 inside a four-metre bench is a weed
	# buried in rock; one on the rim's terrace is placed at `floor_y` and is
	# exempt, which is what the guard tests.
	if is_zero_approx(floor_y) and _blocked(at):
		return
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
	elif WEEDS.has(model) or SCRUB.has(model):
		# Straw, not spring. See `_dry_material` for why this cannot be done by
		# choosing a different model out of the kit.
		var dried := _dry_material(mesh, DRY_GRASS if WEEDS.has(model) else DEAD_SCRUB)
		if dried != null:
			node.material_override = dried
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
		_lamp_heads.append(lamp.position)
	var node := MeshInstance3D.new()
	node.name = "LampMasts"
	node.mesh = st.commit()
	node.material_override = _steel_material
	parent.add_child(node)
	# Two more in the tunnel, hung off the caps. The adit is lit by its own two
	# mouths and at the bend that is two long throws of daylight meeting in the
	# dark, which is atmospheric and is also a place a player cannot see a Bog
	# standing still. These are what make the corner readable — and they are the
	# only warm light on the map that is not over a base, so they also say from
	# the outside that the hole in the bank goes somewhere.
	for spot: Vector3 in [Vector3(-17.8, TUNNEL_TOP - 0.45, 13.2),
			Vector3(-13.2, TUNNEL_TOP - 0.45, 17.8)]:
		_beam(heads, Transform3D.IDENTITY, spot,
			spot + Vector3(0.0, -0.45, 0.0), 0.34)
		var pit_lamp := OmniLight3D.new()
		pit_lamp.name = "Adit%.0f" % spot.z
		pit_lamp.position = spot + Vector3(0.0, -0.5, 0.0)
		pit_lamp.light_color = LAMP_WARM
		pit_lamp.light_energy = 2.6
		pit_lamp.omni_range = 11.0
		pit_lamp.omni_attenuation = 1.2
		pit_lamp.shadow_enabled = false
		lights.add_child(pit_lamp)
		_lamp_heads.append(pit_lamp.position)

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


## The underside of a slab: one quad at `y` facing down, UV'd in metres like
## everything else.
##
## `_slab` draws a top and four sides and deliberately no bottom — on a map made
## of things standing on a floor, a bottom face is geometry nobody can ever see
## and collision nobody can ever touch. The tunnel roof is the exception and the
## only one: a player walks under it, so it needs a face pointing at him.
func _soffit(st: SurfaceTool, lo: Vector2, hi: Vector2, y: float) -> void:
	_quad(st, Vector3(lo.x, y, lo.y), Vector3(hi.x, y, lo.y),
		Vector3(hi.x, y, hi.y), Vector3(lo.x, y, hi.y), Vector3.DOWN,
		Vector2(hi.x - lo.x, hi.y - lo.y))


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
	# The rim, the shaft walls and the four corner masses: the bedded quarry
	# face, at 2k, triplanar in world space. **Triplanar is not decoration
	# here.** Every one of these is an axis-aligned box built by `_slab`, and a
	# box UV'd per face has a visible seam down every arris where the two
	# mappings meet; world triplanar has no seam and, better, keeps the
	# photograph's own horizontal bedding horizontal on all four sides of a
	# column, which is what a bedded rock actually does.
	_stone_material = _pbr(QUARRY_FACE, QUARRY_FACE_RES, FACE_TILE, true, 0.92)

	# **The same photograph again at half the tile**, for the rock a player is
	# standing on or squeezing past rather than looking at across a pit: the
	# monolith, the three columns and the two corner masses. The rim can afford
	# a six-metre tile because the nearest a Bog gets to it is a metre and a
	# half of haul road; the spoil bench is a fourteen-metre *floor*, and at the
	# rim's density its top came out as four enormous blotches of rock.
	# Two materials, one set of textures, no extra memory.
	_raw_material = _pbr(QUARRY_FACE, QUARRY_FACE_RES, RAW_TILE, true, 0.92)

	# Carved stone: the benches, the blocks, the berms, the kerbs and the
	# terraces — everything a player climbs. It wears the dressed sandstone set
	# rather than the rim's, so D-082's rule is now carried by the *material*
	# and not only by a tint: pale, coursed and obviously worked means you can
	# get on top of it; dark and bedded means you cannot.
	_carved_material = _pbr(DRESSED_STONE, "1k", DRESSED_TILE, true, 0.9)

	# The base walls. **Not brick and not tinted per team any more.** A base was
	# twelve metres of team-coloured brickwork, which read as a test level in a
	# stone pit and which put the team's identity on the one surface that also
	# has to read as cover. It is dressed quarry block now, the same stone as
	# everything else somebody cut, and the team colour moved to where a real
	# site would put it: paint on the coping, banners on the wall, a stencil
	# over the door and a tarp on the shelter — see `_build_base_identity`.
	_brick_material = _pbr(DRESSED_STONE, "1k", DRESSED_TILE * 0.8, false, 0.88)

	# The pit floor. Flat and horizontal, so plain UVs are enough and a third of
	# the map's pixels do not need three texture fetches each.
	_floor_material = _pbr(PIT_GRAVEL, "1k", GRAVEL_TILE, false, 0.98)

	# The haul roads. The same crushed stone, run at a coarser tile and taken
	# down a stop by `HAUL_ROAD`, because a road is gravel with ten years of
	# tyres rolled into it.
	_road_material = _pbr(PIT_GRAVEL, "1k", ROAD_TILE, false, 0.95)

	# The derricks, the masts, the hoist falls and the conveyor frame.
	_steel_material = _pbr(SITE_RUST, "1k", RUST_TILE, true, 0.85)
	_steel_material.metallic = 0.35

	# Hazard paint: the stripes at the pit lip, the ramp edges and the plant.
	# The one material on the map with no photograph in it, on purpose — paint
	# on a site is the thing that is *meant* to be a flat loud colour.
	_rust_material = StandardMaterial3D.new()
	_rust_material.albedo_color = RUST
	_rust_material.roughness = 0.8

	# The catwalks, the sleepers, the portal frames, the hut and the pallets.
	_timber_material = _pbr(SITE_TIMBER, "1k", TIMBER_TILE, false, 0.95)

	# Corrugated sheet on the shelters and the hopper, triplanar so the
	# corrugation runs the same way down every panel of a folded roof.
	_iron_material = _pbr(SITE_IRON, "1k", IRON_TILE, true, 0.72)
	_iron_material.metallic = 0.25

	# **Textured, not a flat colour.** A plain-coloured quad on a photographed
	# gravel floor is a slab of concrete however it is tinted — that is what the
	# rectangles lying about the pit were. Wet gravel is gravel: the floor's own
	# set, darkened and run at a low roughness so the sun catches it.
	_water_material = _pbr(PIT_GRAVEL, "1k", GRAVEL_TILE, false, 0.20)
	_water_material.albedo_color = PUDDLE
	# Damp rather than mirrored. At roughness 0.22 every puddle on a cloudless
	# map is a perfect blue disc of sky lying on a limestone floor, which reads
	# as a hole cut in the ground — the exact failure the `PUDDLE` note warns
	# about, arriving by the back door through the *reflection* instead of the
	# albedo. Half-rough it is a wet patch.
	_water_material.metallic = 0.0

	# The kit's rocks arrive a warm sandstone. Tinted to the pit's own raw stone
	# and roughened, so a pebble reads as a chip off the column it is lying
	# against rather than as a prop from somewhere else.
	_rubble_material = StandardMaterial3D.new()
	_rubble_material.albedo_color = Color(0.44, 0.40, 0.34)
	_rubble_material.roughness = 0.95
	_rubble_material.cull_mode = BaseMaterial3D.CULL_BACK

	# The spoil rocks are the same waste and a shade paler, because they are the
	# only loose stone on the map you can climb and the map's one readability
	# rule is that pale stone is what you climb. Shadows on, unlike the pebbles:
	# a kerb-high rock with no shadow under it floats.
	_spoil_material = StandardMaterial3D.new()
	_spoil_material.albedo_color = Color(0.68, 0.63, 0.51)
	_spoil_material.roughness = 0.92
	_spoil_material.cull_mode = BaseMaterial3D.CULL_BACK

	# Sand: the gabion baskets and the bag walls at the bases. The gravel set
	# run very fine, so a bag reads as a bag of the pit's own waste.
	_sand_material = _pbr(PIT_GRAVEL, "1k", 0.7, true, 1.0)
	_sand_material.albedo_color = SANDBAG

	_lamp_material = StandardMaterial3D.new()
	_lamp_material.albedo_color = LAMP_WARM
	_lamp_material.emission_enabled = true
	_lamp_material.emission = LAMP_WARM
	_lamp_material.emission_energy_multiplier = 5.0


## One Poly Haven set as a `StandardMaterial3D`: diffuse, OpenGL normal and
## roughness, at a stated texel density.
##
## This is the whole of the change the visuals pass made to how this map is
## surfaced, and it is deliberately the same shape as the wharf's loader — three
## JPGs off disk, no shader, no atlas, no per-material code. `metres` is what
## one tile of the photograph covers in the world, which is the only number here
## that has to be *thought* about: too small and the rock is corduroy from
## twenty metres, too large and a player standing at a face is looking at
## magnified blur.
##
## `triplanar` maps in **world** space, which does two things worth having on a
## map made of boxes: it removes the seam at every arris where two per-face UV
## mappings meet, and it makes two boxes standing next to each other share one
## continuous field of rock rather than each restarting the tile at its own
## corner. It costs three texture fetches a pixel instead of one, which is why
## the floor — the largest surface on the map, and the one that is flat — does
## not use it.
func _pbr(set_name: String, res: String, metres: float, triplanar: bool,
		roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = _texture(set_name, "diff", res)
	var normal := _texture(set_name, "nor_gl", res)
	if normal != null:
		material.normal_enabled = true
		material.normal_texture = normal
		material.normal_scale = 1.0
	var rough := _texture(set_name, "rough", res)
	if rough != null:
		material.roughness_texture = rough
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	material.roughness = roughness
	# One tile every `metres`, whether the UVs come off the mesh — `_slab` and
	# `_beam` both write them in metres — or out of world position under
	# triplanar. The two agree by construction, which is why a surface can be
	# moved between the two kinds of material without its grain changing size.
	material.uv1_scale = Vector3.ONE / metres
	if triplanar:
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_triplanar_sharpness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material


## One file out of a set, or null with a warning. Null rather than an error,
## because a missing roughness map is a duller material and is worth noticing,
## and neither is worth refusing to build the map over.
func _texture(set_name: String, channel: String, res: String) -> Texture2D:
	var path := "%s%s_%s_%s.jpg" % [TEX, set_name, channel, res]
	if not ResourceLoader.exists(path):
		push_warning("quarry: no texture %s" % path)
		return null
	return load(path) as Texture2D


## The MegaKit's greenery, tinted to straw.
##
## The kit shares one bright spring-green atlas across every grass, bush and
## fern in it, so choosing different *models* cannot make a dry tuft — the fix
## has to be on the material. A `material_override` of a plain colour would
## throw the alpha cutout away and turn every blade into a solid card, so this
## duplicates the mesh's own material, keeps its texture and its scissor, and
## multiplies the albedo hard toward red: green times this is olive-straw, which
## is what last summer's grass in a limestone crack looks like.
##
## Cached per mesh and tint, because a duplicate per multimesh is a pipeline
## state per draw call for no reason.
func _dry_material(mesh: Mesh, tint: Color) -> Material:
	var key := "%s|%s" % [mesh.get_rid(), tint.to_html()]
	if _dry_cache.has(key):
		return _dry_cache[key]
	var source := mesh.surface_get_material(0)
	if source == null:
		return null
	var dried := source.duplicate() as StandardMaterial3D
	if dried == null:
		return null
	dried.albedo_color = tint
	_dry_cache[key] = dried
	return dried


func _group(named: String, under: Node3D = null) -> Node3D:
	var node := Node3D.new()
	node.name = named
	(under if under != null else self).add_child(node)
	return node


# --------------------------------------------------------- the quarry pack ---

## Everything the map wears out of `art/maps/quarry/`: the two tunnel portals,
## the rail runs, the minecarts, the ore, the barrels, the mouth signs and the
## hoist ropes off the derricks.
##
## **All of it is dressing and none of it is collision.** It is built after
## `super()`, so `StaticMap._build_collision` has already run and cannot see it;
## the two props that are *also* map — the spoil rocks and the carts — had their
## collision built above the line, out of `_slab`, and what happens here is only
## that the art is hung over the boxes that are already there.
##
## **Every model is scaled against its own bounding box**, never by a literal.
## The pack was generated a model at a time and normalised to about a metre
## whatever the thing is, so a scale typed in here would be a guess that reads
## as right for one model and as a toy for the next. `_pack_prop` takes the size
## the thing should be in metres and solves for the rest.
func _build_pack(parent: Node3D) -> void:
	var group := _group("Pack", parent)
	_build_adits(group)
	_build_rails(group)
	_build_carts(group)
	_build_ore(group)
	_build_barrels(group)
	_build_signs(group)
	_build_ropes(group)
	_build_extra_pack(group)


## The two abandoned adits in the rim: the pack's portal models, standing where
## their own mounds have a cliff to be inside.
##
## The model's opening faces its own **+x** — read off the contact sheet's top
## view, where the spur of track runs out that way, rather than guessed — so
## `yaw` turns +x to face into the pit and `proud` pushes the mound back through
## the cliff until only `ADIT_PROUD` of mouth is left outside it.
func _build_adits(parent: Node3D) -> void:
	for entry: Dictionary in ADIT_MODELS:
		var at: Vector2 = entry["at"]
		_pack_prop(parent, String(entry["model"]), Vector3(at.x, 0.0, at.y),
			float(entry["yaw"]), "z", ADIT_WIDE, ADIT_PROUD)


## The rail, as one `MultiMesh` per run.
##
## Forty metres of sleepered track is about twenty instances of one model, and
## twenty `MeshInstance3D`s is twenty draw calls for something nothing touches.
## A multimesh is one, and — as the spoil rocks' note says — a multimesh is also
## a thing `_collect_meshes` cannot see, which is the right answer for iron a
## Bog walks straight over.
##
## The sleepers are sunk two centimetres into the gravel rather than laid on it.
## Track laid exactly on a floor z-fights it along every sleeper, and track laid
## over it floats; two centimetres is under the height of the gravel's own
## normal map and reads as ballast.
func _build_rails(parent: Node3D) -> void:
	var part := _pack_single(RAIL_MODEL)
	if part.is_empty():
		return
	var mesh: Mesh = part["mesh"]
	var box: AABB = part["aabb"]
	var along := RAIL_PITCH / box.size.x
	for run: int in RAIL_RUNS.size():
		var line: Array = RAIL_RUNS[run]
		if line.size() < 2:
			continue
		var from: Vector2 = line[0]
		var to: Vector2 = line[1]
		var span := from.distance_to(to)
		var count := maxi(1, int(span / RAIL_PITCH))
		var step := (to - from) / float(count)
		var yaw := atan2(step.x, step.y) - PI * 0.5
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = count
		var bounds := AABB()
		for i: int in count:
			var at := from + step * (float(i) + 0.5)
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3(along, along, along))
			var xform := Transform3D(basis,
				Vector3(at.x, -box.position.y * along - 0.02, at.y))
			multi.set_instance_transform(i, xform)
			var cell := xform * box
			bounds = cell if i == 0 else bounds.merge(cell)
		var node := MultiMeshInstance3D.new()
		node.name = "Rail%d" % run
		node.multimesh = multi
		node.custom_aabb = bounds
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)


## The carts, hung over the boxes `_build_cart_stands` already put under them.
##
## Built to `CART_HEIGHT` exactly, which is `KERB_TOP`, which is why the box
## underneath is a kerb: the art and the collision are two statements of one
## number rather than two numbers that have to be kept equal.
func _build_carts(parent: Node3D) -> void:
	for entry: Dictionary in CART_STANDS:
		var model := String(CART_MODELS[String(entry["model"])])
		var pair := _cart_spots(entry)
		for k: int in pair.size():
			var at: Vector2 = pair[k]
			_pack_prop(parent, model, Vector3(at.x, 0.0, at.y),
				float(entry["yaw"]) + PI * float(k), "y", CART_HEIGHT)


## The ore standing about the pit. Not cover and not collision: an ore boulder
## is 1.1 m across and the Bog has no step-up, so it is a thing to look at and
## the map says nothing about it in `platforms`.
func _build_ore(parent: Node3D) -> void:
	for entry: Dictionary in ORE_PILES:
		var model := ORE_MODELS[int(entry["model"]) % ORE_MODELS.size()]
		var pair := turned(entry["at"])
		for k: int in pair.size():
			var at: Vector2 = pair[k]
			_pack_prop(parent, model, Vector3(at.x, 0.0, at.y),
				0.7 + 1.9 * float(k), "x", ORE_SPAN)


func _build_barrels(parent: Node3D) -> void:
	for i: int in BARRELS.size():
		var at: Vector2 = BARRELS[i]
		_pack_prop(parent, BARREL_MODEL, Vector3(at.x, 0.0, at.y),
			1.1 * float(i), "y", BARREL_HEIGHT)


## A board on a post at each tunnel mouth, at a Bog's eye height — the one sign
## in the pack with no fantasy written on it.
func _build_signs(parent: Node3D) -> void:
	var st := _begin()
	for entry: Dictionary in SIGNS:
		var at: Vector2 = entry["at"]
		var head := Vector3(at.x, SIGN_HEIGHT, at.y)
		_beam(st, Transform3D.IDENTITY, Vector3(at.x, 0.0, at.y), head, 0.14)
		_pack_prop(parent, SIGN_MODEL, head - Vector3(0.0, 0.45, 0.0),
			float(entry["yaw"]), "x", SIGN_WIDE)
	var node := MeshInstance3D.new()
	node.name = "SignPosts"
	node.mesh = st.commit()
	node.material_override = _timber_material
	parent.add_child(node)


## The hoist hanging off each derrick's boom: a **short** length of the pack's
## cable with a steel fall drawn above it in code.
##
## The pack's rope is a metre of cable normalised like every other model, and
## the first pass simply asked for eleven metres of it. `_pack_prop` scales
## uniformly — it has to, or every prop on this map would be a stretched one —
## so eleven metres of length came with **one metre of thickness**, and what
## hung over the south-east terrace was a cable a Bog could not get its arms
## round, filling the sky above the B card.
##
## So the model is used at the size it is good at: 2.6 m, which reads as the
## last of the fall and the hook block, with the rest of the drop drawn as a
## 0.1 m steel beam from the boom tip down to it. One prop, correctly sized,
## and the long thin thing is the thing this file is already good at making.
func _build_ropes(parent: Node3D) -> void:
	var st := _begin()
	for at: Vector2 in turned(DERRICK_AT):
		var toward := -Vector2(at.x, at.y).normalized()
		var tip := Vector3(at.x, 0.0, at.y) \
			+ Vector3(toward.x, 0.0, toward.y) * 13.0 \
			+ Vector3(0.0, DERRICK_HEIGHT - 3.5, 0.0)
		_beam(st, Transform3D.IDENTITY, tip, tip - Vector3(0.0, ROPE_FALL, 0.0), 0.1)
		# Tinted like the portals. The pack's cable is a bright chrome twist,
		# and hanging over the south-east terrace it read as the one polished
		# object in a quarry — a mirror on a stick against a dusty cliff.
		var hook := _pack_prop(parent, ROPE_MODEL,
			tip - Vector3(0.0, ROPE_FALL + ROPE_DROP, 0.0), 0.0, "y", ROPE_DROP)
		if hook != null:
			_tint_pack(hook, Color(0.52, 0.44, 0.36))
	var node := MeshInstance3D.new()
	node.name = "HoistFalls"
	node.mesh = st.commit()
	node.material_override = _steel_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


## Every material under a pack model, duplicated and multiplied by a tint.
##
## The pack was generated a model at a time and the stone in it is a cold
## museum grey, which is three quarters of a stop paler and a good deal bluer
## than this pit's rock. Dropped on the rim without this, a portal mound reads
## as a lump of somebody else's map sitting on the skyline — which is exactly
## what the first render of `RIM_MOUNDS` showed.
##
## The *materials* are duplicated, not overridden: an override would throw away
## the model's own texture and turn a carved portal into a flat-shaded lump.
## Duplicating keeps every map the generator produced and only touches the one
## number that says how much light comes back off it.
func _tint_pack(node: Node, tint: Color) -> void:
	var found: Array[MeshInstance3D] = []
	_pack_meshes(node, found)
	for mesh: MeshInstance3D in found:
		for surface: int in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface)
			var own := source.duplicate() as StandardMaterial3D if source != null else null
			if own == null:
				continue
			own.albedo_color = own.albedo_color * tint
			mesh.set_surface_override_material(surface, own)


## One model out of the pack, scaled by its own bounding box and stood on the
## ground at `at`.
##
## `fit` names the axis whose size is being set — "x" and "z" are across the
## model, "y" is its height — and `fit_to` is what that axis should measure in
## metres. Everything scales together, so nothing is ever stretched. The model
## is centred on `at` in x and z and sat on `at.y` by the underside of its own
## box, which is the whole reason this function exists: the pack's pivots are
## not on the ground, they are wherever the generator left them, and a prop
## placed by its pivot is a prop half buried or hanging in the air.
## `proud`, when it is given, stops the model being *centred* on `at` along its
## own x and instead puts its **+x extreme** `proud` metres past it, with the
## rest of it running back behind. That is what a portal cut into a cliff needs
## and nothing else here does, which is why it defaults to a number that turns
## it off.
func _pack_prop(parent: Node3D, model: String, at: Vector3, yaw: float,
		fit: String, fit_to: float, proud: float = INF) -> Node3D:
	var packed := _pack_scene(model)
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		return null
	var box := _pack_bounds(node)
	if box.size.length() < 0.0001:
		return null
	var measure := box.size.y if fit == "y" else (box.size.z if fit == "z" else box.size.x)
	if measure < 0.0001:
		return null
	var factor := fit_to / measure
	node.name = "%s_%d" % [model, parent.get_child_count()]
	node.transform = Transform3D(
		Basis(Vector3.UP, yaw).scaled(Vector3(factor, factor, factor)),
		Vector3.ZERO)
	# The box, turned and scaled the way the node now is, so the sit and the
	# centring are done in the frame the model ends up in rather than the one it
	# was authored in.
	var placed := node.transform * box
	node.position = Vector3(at.x - placed.get_center().x, at.y - placed.position.y,
		at.z - placed.get_center().z)
	if proud < INF:
		# The model's own +x, turned the way the node is, and half its length
		# along it: that puts the mouth on `at` rather than the middle.
		var along := (node.transform.basis * Vector3.RIGHT).normalized()
		node.position -= along * (box.size.x * factor * 0.5 - proud)
	parent.add_child(node)
	return node


## The first mesh in a pack model, with its bounding box, for the runs that are
## drawn as a `MultiMesh` and therefore need a `Mesh` rather than a scene.
static func _pack_single(model: String) -> Dictionary:
	var packed := _pack_scene(model)
	if packed == null:
		return {}
	var node := packed.instantiate()
	var found: Array[MeshInstance3D] = []
	_pack_meshes(node, found)
	if found.is_empty():
		node.queue_free()
		return {}
	var first := found[0]
	var mesh := first.mesh
	var box := first.transform * mesh.get_aabb()
	node.queue_free()
	return {"mesh": mesh, "aabb": box}


static func _pack_scene(model: String) -> PackedScene:
	var path := PACK + model + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("quarry: no pack model %s" % path)
		return null
	return load(path) as PackedScene


## Every mesh under a pack model, merged into one box in the model's own frame.
static func _pack_bounds(node: Node) -> AABB:
	var found: Array[MeshInstance3D] = []
	_pack_meshes(node, found)
	var out := AABB()
	for i: int in found.size():
		var mesh: MeshInstance3D = found[i]
		var box := mesh.transform * mesh.mesh.get_aabb()
		out = box if i == 0 else out.merge(box)
	return out


static func _pack_meshes(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		into.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_pack_meshes(child, into)


# ====================================================================== relief
#
# Everything below this line is **visual only**. It is built after `super()`,
# so `StaticMap._build_collision` has already swept the solids and cannot see
# any of it, and every piece of it obeys the same two rules:
#
#   * it sits *against* a collision box, never inside walkable space by more
#     than about ten centimetres, and
#   * it never puts a surface above a walkable top.
#
# That is what lets a map whose layout is locked — every face, every landing and
# every sightline measured and signed off — stop reading as a stack of boxes
# without a single number in the tables above moving. The rock is still eleven
# boxes; it is the drill lines down them, the bench marks across them, the
# broken arris at every top edge and the rubble against every foot that make
# them rock.


## The drill line. A sawn quarry face is cut by a row of boreholes about a foot
## and a half apart, and what is left when the rock between them comes away is a
## wall of vertical half-round channels — the single most recognisable thing
## about a worked face, and the thing the old procedural texture was trying and
## failing to draw. Drawn as geometry instead it survives being seen edge-on,
## casts its own shadow across itself as the sun swings, and costs one strip of
## triangles per rib.
##
## 7 cm proud, which is inside the ten-centimetre budget and is still two hours
## of shadow at this sun angle.
const RIB_PITCH := 1.7
const RIB_WIDE := 0.20
const RIB_PROUD := 0.07

## The bench marks: the horizontal ledge left where one lift of stone was taken
## off the one below. Three of them up an eleven-metre face, none lower than
## 4.6 m — which is above `BENCH_TOP`, so no haul ramp and no bench top has a
## ledge growing out of the cliff beside it.
const BENCH_LINES: Array[float] = [4.6, 7.4, 9.6]
const BENCH_LINE_PROUD := 0.09
const BENCH_LINE_TALL := 0.30

## The broken arris. Every cut block on this map is a box with eight perfect
## 90-degree edges, and nothing in a quarry has one: the top edge of a worked
## stone is chipped back within a week of being cut. This is a 9 cm flare round
## the top of a box, sloping down and *out*, so it is a worn edge rather than a
## chamfer — a chamfer would have to be cut *into* the box, and the box is
## collision.
const ARRIS := 0.09

## The skyline. Blocks of stone left standing on the rim's first bench, which is
## eleven metres up and is the only part of this map that is ever seen against
## the sky. Written as a count and a spread rather than a table because nothing
## depends on where any one of them is — the only requirement is that the top
## edge of the pit stops being a ruled line.
const SKYLINE_COUNT := 96
const SKYLINE_SEED := 0x9C3D11
## How far a skyline block may hang over the lip. 0.3 m, eleven metres above the
## nearest walkable surface, which is a cliff with a loose block on it and not a
## ledge anybody will ever touch.
const SKYLINE_OVERHANG := 0.3


## All of it: the ribs and bench marks down the cliff and the shaft, the broken
## arris round every cut block, the scree against the feet, the blocks on the
## skyline and the spurs off the monolith.
##
## Four meshes, four draw calls. They are split by *material* and not by what
## they are, which is why the ribs on the rim and the ribs in the shaft are one
## node: both are the rim's stone, and a node per feature would be a dozen draw
## calls for scenery.
func _build_relief(parent: Node3D) -> void:
	var group := _group("Relief", parent)
	var face := _begin()
	var raw := _begin()
	var cut := _begin()

	_rim_relief(face)
	_shaft_relief(face)
	_skyline(face)
	_monolith_relief(raw)
	_column_relief(raw)
	_cut_arrises(cut)
	_scree(cut)

	_commit(group, "CliffRelief", face, _stone_material, STONE_RIM)
	_commit(group, "CoreRelief", raw, _raw_material, STONE_RAW)
	_commit(group, "CutRelief", cut, _carved_material, STONE_CUT)


## Drill ribs and bench marks down all four rim faces.
##
## The whole face is ribbed, including the stretches that are buried inside the
## two corner masses, the terraces and the two base benches. Ribs inside rock
## are invisible and cost one strip each; the alternative is four span tables
## that have to be kept in step with five other tables, and a rib that is one
## metre out of step is a rib sticking through a bench.
func _rim_relief(st: SurfaceTool) -> void:
	for side: int in 4:
		var along_x := side < 2
		var sign := -1.0 if side % 2 == 0 else 1.0
		var facing := -sign            # the pit is the other way from the rock
		var wall := sign * HALF
		var steps := int((HALF * 2.0) / RIB_PITCH)
		for i: int in steps:
			var at := lerpf(-HALF, HALF, (float(i) + 0.5) / float(steps))
			var lo := Vector2(at - RIB_WIDE * 0.5, wall)
			var hi := Vector2(at + RIB_WIDE * 0.5, wall + facing * RIB_PROUD)
			if not along_x:
				lo = Vector2(wall, at - RIB_WIDE * 0.5)
				hi = Vector2(wall + facing * RIB_PROUD, at + RIB_WIDE * 0.5)
			_slab(st, Vector2(minf(lo.x, hi.x), minf(lo.y, hi.y)),
				Vector2(maxf(lo.x, hi.x), maxf(lo.y, hi.y)), 0.25, RIM_TOP - 0.2)
		for y: float in BENCH_LINES:
			var lo := Vector2(-HALF, wall)
			var hi := Vector2(HALF, wall + facing * BENCH_LINE_PROUD)
			if not along_x:
				lo = Vector2(wall, -HALF)
				hi = Vector2(wall + facing * BENCH_LINE_PROUD, HALF)
			_slab(st, Vector2(minf(lo.x, hi.x), minf(lo.y, hi.y)),
				Vector2(maxf(lo.x, hi.x), maxf(lo.y, hi.y)), y, y + BENCH_LINE_TALL)


## The same treatment down the shaft, where it matters more than anywhere: the
## hole is the map's one lethal feature and the thing that sells a lethal hole
## is being able to see how *deep* it is. Sixteen metres of smooth box says
## nothing; sixteen metres with four bench marks and a ribbed face down it reads
## as a quarry that kept going.
##
## Everything here is below y = 0 or on a face nobody stands on, so the
## ten-centimetre budget is not even in play — these are 12 cm.
func _shaft_relief(st: SurfaceTool) -> void:
	var h := HOLE_HALF
	for side: int in 4:
		var along_x := side < 2
		var sign := -1.0 if side % 2 == 0 else 1.0
		var wall := sign * h
		var facing := -sign
		var steps := int((h * 2.0) / (RIB_PITCH * 0.8))
		for i: int in steps:
			var at := lerpf(-h, h, (float(i) + 0.5) / float(steps))
			var lo := Vector2(at - RIB_WIDE * 0.5, wall)
			var hi := Vector2(at + RIB_WIDE * 0.5, wall + facing * 0.12)
			if not along_x:
				lo = Vector2(wall, at - RIB_WIDE * 0.5)
				hi = Vector2(wall + facing * 0.12, at + RIB_WIDE * 0.5)
			_slab(st, Vector2(minf(lo.x, hi.x), minf(lo.y, hi.y)),
				Vector2(maxf(lo.x, hi.x), maxf(lo.y, hi.y)),
				HOLE_LEDGE + 0.2, -FLOOR_THICK - 0.05)
		for y: float in [-1.8, -3.6]:
			var lo := Vector2(-h, wall)
			var hi := Vector2(h, wall + facing * 0.16)
			if not along_x:
				lo = Vector2(wall, -h)
				hi = Vector2(wall + facing * 0.16, h)
			_slab(st, Vector2(minf(lo.x, hi.x), minf(lo.y, hi.y)),
				Vector2(maxf(lo.x, hi.x), maxf(lo.y, hi.y)), y, y + 0.22)


## Broken blocks standing on the rim's first bench, eleven metres up.
##
## This is the cheapest big win on the map and the reason it is worth doing:
## from the pit floor the horizon is a ruled line 360 degrees round, and a ruled
## line is the single clearest signal that a place was built out of boxes. Two
## hundred cubic metres of loose stone on top of it, most of it under a metre
## tall, turns the same silhouette into a quarry lip.
##
## Deterministic off `SKYLINE_SEED`, like every other draw on this map, so every
## peer sees the same rock in the same place.
func _skyline(st: SurfaceTool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SKYLINE_SEED
	var shelf := RIM_TIERS[1].x        # how wide tier zero's top is
	for i: int in SKYLINE_COUNT:
		var side := i % 4
		var t := (float(i) + rng.randf()) / float(SKYLINE_COUNT)
		var along := lerpf(-FLOOR_EDGE, FLOOR_EDGE, fposmod(t * 4.13, 1.0))
		# Out from the lip: negative is over it, and the overhang is capped.
		var out := rng.randf_range(-SKYLINE_OVERHANG, shelf - 0.4)
		var size := Vector3(rng.randf_range(0.7, 2.2), rng.randf_range(0.35, 1.9),
			rng.randf_range(0.7, 2.0))
		var near := HALF + out
		var at := Vector2(along, -near - size.z * 0.5) if side == 0 \
			else Vector2(along, near + size.z * 0.5) if side == 1 \
			else Vector2(-near - size.x * 0.5, along) if side == 2 \
			else Vector2(near + size.x * 0.5, along)
		if absf(at.x) > FLOOR_EDGE + 1.0 or absf(at.y) > FLOOR_EDGE + 1.0:
			continue
		# Turned a little off square, because a loose block that is square to
		# the pit is a block somebody placed.
		var frame := Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)),
			Vector3(at.x, RIM_TOP + size.y * 0.5 - 0.1, at.y))
		# Every fourth one is tipped, which is what a block does when the bench
		# under it has been undercut.
		if i % 4 == 0:
			frame.basis = frame.basis * Basis(Vector3.RIGHT, rng.randf_range(0.12, 0.34))
		_box(st, frame, size)


## The monolith: spurs of rock left on its flanks and a cone of waste round its
## foot, sixteen metres down where nobody goes.
##
## It is the centrepiece — it stands in the hole, it closes base to base, and
## it is in every catwalk and lip shot on the list — and as five stacked boxes
## it read as five stacked boxes. The spurs are slabs of the same rock leaning
## against it at each step, which is what is left when a lift comes off a core
## unevenly, and they are what makes the steps read as rock breaking rather than
## as a stair.
func _monolith_relief(st: SurfaceTool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SKYLINE_SEED ^ 0x1D
	var span := MONOLITH_TOP - HOLE_FLOOR
	for step: int in MONOLITH_STEPS:
		var low := float(step) / float(MONOLITH_STEPS)
		var half := lerpf(MONOLITH_BASE_HALF, MONOLITH_TOP_HALF, low)
		var base := HOLE_FLOOR + span * low
		for k: int in 3:
			# **On one of the four faces, at a random point along it** — not on
			# a random *bearing*, which is how the first pass placed them and
			# is why one spur in three hung off a corner in mid-air with the
			# rock it was supposed to be leaning on two metres behind it. The
			# monolith is a stack of square slabs; a flake off it comes away
			# from a face.
			var side := rng.randi() % 4
			var yaw := PI * 0.5 * float(side)
			var out := Vector3(cos(yaw), 0.0, sin(yaw))
			var across := Vector3(-out.z, 0.0, out.x)
			var at := out * (half + 0.16) \
				+ across * rng.randf_range(-half * 0.55, half * 0.55) \
				+ Vector3.UP * (base + rng.randf_range(0.7,
					span / MONOLITH_STEPS - 0.7))
			var frame := Transform3D(Basis(Vector3.UP, -yaw), at)
			frame.basis = frame.basis * Basis(Vector3.FORWARD, rng.randf_range(-0.22, 0.22))
			_box(st, frame, Vector3(rng.randf_range(0.6, 1.5),
				rng.randf_range(0.9, 2.4), 0.42))
	# The waste cone at its foot, on the shaft's own floor.
	_scree_fan(st, Vector3(0.0, HOLE_FLOOR, 0.0), MONOLITH_BASE_HALF + 3.2, 1.6, 14)


## The three columns get the same drill ribs the cliff has, and a low apron of
## chips round their feet.
##
## A column is ten metres of unquarried rock standing in the open with a player
## running round it at arm's length — it is the most closely inspected rock on
## the map after the base bench, and it was four flat faces.
func _column_relief(st: SurfaceTool) -> void:
	for entry: Dictionary in COLUMNS:
		for at: Vector2 in turned(entry["at"]):
			var size: Vector2 = entry["size"]
			var lo := at - size * 0.5
			var hi := at + size * 0.5
			for axis: int in 2:
				var run := size.x if axis == 0 else size.y
				var steps := maxi(2, int(run / (RIB_PITCH * 0.75)))
				for i: int in steps:
					var along := lerpf(-run * 0.5, run * 0.5, (float(i) + 0.5) / float(steps))
					for s: float in [-1.0, 1.0]:
						var c := at + (Vector2(along, s * size.y * 0.5) if axis == 0
							else Vector2(s * size.x * 0.5, along))
						var thin := Vector2(RIB_WIDE * 0.5, RIB_PROUD) if axis == 0 \
							else Vector2(RIB_PROUD, RIB_WIDE * 0.5)
						_slab(st, c - thin, c + thin, 0.3, COLUMN_TOP - 0.15)
			# A bench mark round it at the two heights the cliff has above the
			# benches, so column and cliff read as the same rock worked the same
			# way — which they are.
			for y: float in [4.6, 7.4]:
				_slab(st, lo - Vector2(0.09, 0.09), hi + Vector2(0.09, 0.09),
					y, y + BENCH_LINE_TALL)
			_scree_fan(st, Vector3(at.x, 0.0, at.y),
				maxf(size.x, size.y) * 0.5 + 1.1, 0.14, 10)


## The broken arris round the top of every cut stone on the map, and the low
## aprons of chips at the feet of the things worth having one.
##
## `_arris` is the whole of the first half: one mitred ring of four quads per
## box, sloping down and out, which turns a perfect 90-degree edge into a worn
## one. It is nine centimetres and it changes a surprising amount — a box's top
## edge is the brightest line in any shot of it, and a hard highlight down a
## perfectly straight edge is what "untextured primitive" looks like.
func _cut_arrises(st: SurfaceTool) -> void:
	for table: Array in [BLOCKS, KERBS]:
		var top := BLOCK_TOP if table == BLOCKS else KERB_TOP
		for entry: Dictionary in table:
			for at: Vector2 in turned(entry["at"]):
				var size: Vector2 = entry["size"]
				_arris(st, at - size * 0.5, at + size * 0.5, top, ARRIS)
				_scree_fan(st, Vector3(at.x, 0.0, at.y),
					maxf(size.x, size.y) * 0.5 + 0.8, 0.11, 8)
	for entry: Dictionary in BERMS:
		var size: Vector2 = entry["size"]
		var at: Vector2 = entry["at"]
		_arris(st, at - size * 0.5, at + size * 0.5, BERM_TOP, ARRIS)
	for entry: Dictionary in TERRACES:
		var x: Vector2 = entry["x"]
		var z: Vector2 = entry["z"]
		_arris(st, Vector2(x.x, z.x), Vector2(x.y, z.y), float(entry["top"]), ARRIS)
		# Chips banked along the riser, which is the one face of a terrace a
		# player is ever nose to nose with.
		for i: int in 7:
			var t := (float(i) + 0.5) / 7.0
			_scree_fan(st, Vector3(lerpf(x.x, x.y, t), float(entry["top"]) - 1.5,
				z.x - 0.1), 1.0, 0.12, 7)
	for at: Vector2 in turned(BASE_AT):
		var sign := factors(at).x
		var lo := minf(sign * HALF, sign * BENCH_INNER)
		var hi := maxf(sign * HALF, sign * BENCH_INNER)
		_arris(st, Vector2(lo, lo), Vector2(hi, hi), BENCH_TOP, ARRIS)
	_arris(st, Vector2(CORNER_X.x, CORNER_Z.x), Vector2(CORNER_X.y, CORNER_Z.y),
		CORNER_TOP, ARRIS)
	_arris(st, Vector2(-CORNER_X.y, -CORNER_Z.y), Vector2(-CORNER_X.x, -CORNER_Z.x),
		CORNER_TOP, ARRIS)


## Scree at the feet of the things standing on the pit floor, and the spoil the
## shaft's own ledge carries.
##
## Deliberately thin. The brief for the relief pass is that nothing may stand
## more than about ten centimetres into ground a player runs over, and a real
## talus slope against a four-metre face is a metre high — so what is here is
## the *toe* of one: an 11 to 14 cm fan that a Bog runs straight over and that
## does the one job a talus has to do, which is stop the floor meeting the wall
## along a mathematically straight line.
##
## The two places that get a real heap instead are the shaft ledge and the
## monolith's foot, because nobody can reach either.
func _scree(st: SurfaceTool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SKYLINE_SEED ^ 0x77
	# The ledge five and a half metres down the shaft, seen from every lip and
	# both catwalks and reachable from neither.
	var l := HOLE_HALF + HOLE_LEDGE_WIDTH * 0.5
	for i: int in 16:
		var t := TAU * float(i) / 16.0
		var at := Vector3(cos(t), 0.0, sin(t)) * l
		at = Vector3(clampf(at.x, -l, l), HOLE_LEDGE, clampf(at.z, -l, l))
		_scree_fan(st, at, rng.randf_range(0.8, 1.6), rng.randf_range(0.3, 0.8), 8)
	# Loose slabs on the shaft's lower bench, where the drop bottoms out.
	for i: int in 22:
		var at := Vector3(rng.randf_range(-6.0, 6.0), HOLE_FLOOR,
			rng.randf_range(-6.0, 6.0))
		if absf(at.x) < MONOLITH_BASE_HALF + 1.0 and absf(at.z) < MONOLITH_BASE_HALF + 1.0:
			continue
		var frame := Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), at)
		frame.basis = frame.basis * Basis(Vector3.RIGHT, rng.randf_range(-0.4, 0.4))
		var size := Vector3(rng.randf_range(0.8, 2.4), rng.randf_range(0.2, 0.6),
			rng.randf_range(0.8, 2.4))
		frame.origin.y += size.y * 0.4
		_box(st, frame, size)


# ------------------------------------------------------------------ the site ---

## The plant on the rim: a hopper on legs, the conveyor that feeds it, a crusher
## and a line of lamp masts, standing on the cliff's first bench eleven metres
## up on the two sides the derricks are not on.
##
## **Everything here is outside the pit and above the cliff**, which is the
## whole reason it can exist at all: the layout is locked, nothing may go into
## the playable box, and the skyline is the one place a map like this has spare
## room. It is also the place a player is looking whenever they are not looking
## at their feet — the pit is a forty-eight metre square with an eleven-metre
## wall round it, so the top third of every frame is cliff edge and sky, and
## until this pass there was nothing in it but two derricks and fourteen dead
## trees.
##
## A rotational pair like everything else, so neither team gets the interesting
## half of the skyline.
const PLANT_AT := Vector2(-25.6, 3.0)
const HOPPER_FOOT := RIM_TOP
const HOPPER_TOP := 19.4
const CRUSHER_AT := Vector2(-25.6, -9.0)
## The lamp masts on the lip: how many to a side and how tall. No lights on
## them — the map's light budget is a sun, a bounce, two work lamps and two in
## the adit, which is where Lantern Wharf's four floods put it, and a lamp on
## the skyline eleven metres up and thirty metres away would light nothing a
## player could see it light.
const MAST_COUNT := 5
const MAST_HEIGHT := 5.4


func _build_plant(parent: Node3D) -> void:
	var group := _group("Plant", parent)
	var steel := _begin()
	var sheet := _begin()
	var timber := _begin()
	var block := _begin()
	var paint := _begin()

	for at: Vector2 in turned(PLANT_AT):
		var toward := -Vector2(at.x, at.y).normalized()
		var frame := Transform3D(Basis(Vector3.UP, atan2(toward.x, toward.y)),
			Vector3(at.x, 0.0, at.y))
		_hopper(steel, sheet, frame)
	for at: Vector2 in turned(CRUSHER_AT):
		var toward := -Vector2(at.x, at.y).normalized()
		var frame := Transform3D(Basis(Vector3.UP, atan2(toward.x, toward.y)),
			Vector3(at.x, 0.0, at.y))
		_crusher(steel, sheet, timber, block, frame)
	_lip_masts(steel)
	_lip_hazard(paint)
	_cable_runs(steel)

	_commit(group, "PlantSteel", steel, _steel_material, STEEL)
	_commit(group, "PlantSheet", sheet, _iron_material, SHEET_IRON)
	_commit(group, "PlantTimber", timber, _timber_material, TIMBER)
	_commit(group, "PlantBlock", block, _carved_material, STONE_CUT)
	var stripes := _commit(group, "PitHazard", paint, _rust_material, HAZARD_YELLOW)
	stripes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## One hopper: four splayed legs off the rim bench, a corrugated bin on top of
## them and a chute out of the bottom, with the conveyor that feeds it running
## up from the crusher.
func _hopper(steel: SurfaceTool, sheet: SurfaceTool, frame: Transform3D) -> void:
	var legs := 1.7
	for sx: float in [-legs, legs]:
		for sz: float in [-legs, legs]:
			_beam(steel, frame, Vector3(sx * 1.35, HOPPER_FOOT, sz * 1.35),
				Vector3(sx, HOPPER_TOP - 3.4, sz), 0.24)
	for y: float in [HOPPER_FOOT + 1.6, HOPPER_TOP - 4.2]:
		for corner: Array in [[-legs, -legs, legs, -legs], [legs, -legs, legs, legs],
				[legs, legs, -legs, legs], [-legs, legs, -legs, -legs]]:
			_beam(steel, frame, Vector3(corner[0], y, corner[1]),
				Vector3(corner[2], y, corner[3]), 0.14)
	# The bin. Four sloped sheets and a square top: a hopper is a funnel, and a
	# funnel read against the sky is the one industrial silhouette nobody has to
	# be told the name of.
	var throat := 0.7
	var mouth := 2.3
	var low := HOPPER_TOP - 3.4
	var high := HOPPER_TOP
	for side: int in 4:
		var a := _ring(throat, side, low)
		var b := _ring(throat, side + 1, low)
		var c := _ring(mouth, side + 1, high)
		var d := _ring(mouth, side, high)
		_panel(sheet, frame * a, frame * b, frame * c, frame * d)
	_beam(steel, frame, Vector3(0.0, low, 0.0), Vector3(0.0, low - 1.5, 0.0), 0.8)
	# The conveyor: a boxed frame climbing from the crusher's mouth to the
	# hopper's, with a corrugated hood over the top half of it.
	var head := frame * Vector3(0.0, HOPPER_TOP - 0.6, 0.0)
	var foot := Vector3(lerpf(PLANT_AT.x, CRUSHER_AT.x, 0.96),
		HOPPER_FOOT + 1.2, lerpf(PLANT_AT.y, CRUSHER_AT.y, 0.96))
	if frame.origin.x > 0.0:
		foot = Vector3(-foot.x, foot.y, -foot.z)
	for side: float in [-0.55, 0.55]:
		var across := (head - foot).cross(Vector3.UP).normalized() * side
		_beam(steel, Transform3D.IDENTITY, foot + across, head + across, 0.2)
	_beam(sheet, Transform3D.IDENTITY, foot.lerp(head, 0.3) + Vector3.UP * 0.5,
		head + Vector3.UP * 0.4, 1.3)
	# A trestle under the middle of the run. Without it the conveyor is a box
	# bridging thirteen metres of air between two things a player cannot see
	# the bottom of, which is exactly how it read in the first render.
	var knee := foot.lerp(head, 0.45)
	for s: float in [-0.5, 0.5]:
		var across := (head - foot).cross(Vector3.UP).normalized() * s
		_beam(steel, Transform3D.IDENTITY, Vector3(knee.x + across.x, RIM_TOP,
			knee.z + across.z), knee + across, 0.18)


## A corner of the hopper's square ring at height `y`, walked **anticlockwise
## seen from above** — the order every outward-facing side on this map is wound
## in, so a funnel built out of it faces outward without anybody having to
## reason about it twice.
static func _ring(half: float, side: int, y: float) -> Vector3:
	var corners := [Vector2(-half, -half), Vector2(-half, half),
		Vector2(half, half), Vector2(half, -half)]
	var c: Vector2 = corners[side % 4]
	return Vector3(c.x, y, c.y)


## The crusher house: a squat boxy mass with a corrugated roof, a feed chute and
## a stack of cut blocks on pallets beside it. What the quarry did with the rock
## it took out of the hole, standing where the haul road would have come out.
func _crusher(steel: SurfaceTool, sheet: SurfaceTool, timber: SurfaceTool,
		stone: SurfaceTool, frame: Transform3D) -> void:
	var body := Vector3(4.6, 3.4, 3.2)
	_box(sheet, frame * Transform3D(Basis.IDENTITY,
		Vector3(0.0, RIM_TOP + body.y * 0.5, 0.0)), body)
	# A pitched roof, as two sheets, because a flat-topped box on a skyline is
	# the same box it was before somebody called it a building.
	for s: float in [-1.0, 1.0]:
		var a := Vector3(-body.x * 0.5, RIM_TOP + body.y, s * body.z * 0.5)
		var b := Vector3(body.x * 0.5, RIM_TOP + body.y, s * body.z * 0.5)
		var c := Vector3(body.x * 0.5, RIM_TOP + body.y + 1.0, 0.0)
		var d := Vector3(-body.x * 0.5, RIM_TOP + body.y + 1.0, 0.0)
		_panel(sheet, frame * a, frame * b, frame * c, frame * d)
	for sx: float in [-1.0, 1.0]:
		_beam(steel, frame, Vector3(sx * body.x * 0.5, RIM_TOP, -body.z * 0.7),
			Vector3(sx * body.x * 0.5, RIM_TOP + body.y + 0.6, -body.z * 0.7), 0.18)
	# Two pallets of sawn block, stacked the way a yard stacks them.
	for k: int in 2:
		var at := Vector3(body.x * 0.5 + 1.6 + float(k) * 2.2, RIM_TOP, 1.2)
		_pallet(timber, stone, frame * Transform3D(Basis.IDENTITY, at), 3 - k)


## A pallet with a stack of sawn block on it: the bearers into `timber`, the
## block into `stone`.
##
## Two surfaces and not one. The first pass drew the whole thing into the timber
## mesh to save a draw call, and what stood on the rim was a stack of wooden
## crates — which is a perfectly good prop and is not the one this quarry needs,
## because the entire point of a block stack is that it is the *product*: the
## rock that came out of the hole, cut square and waiting for a lorry.
func _pallet(timber: SurfaceTool, stone: SurfaceTool, frame: Transform3D,
		courses: int) -> void:
	for i: int in 4:
		var z := lerpf(-0.6, 0.6, float(i) / 3.0)
		_beam(timber, frame, Vector3(-0.9, 0.07, z), Vector3(0.9, 0.07, z), 0.14)
	for c: int in courses:
		var y := 0.2 + float(c) * 0.45
		for k: int in 2:
			var x := -0.42 + float(k) * 0.84
			_box(stone, frame * Transform3D(Basis(Vector3.UP, 0.04 * float(c)),
				Vector3(x, y + 0.2, 0.0)), Vector3(0.78, 0.42, 1.3))


## Lamp masts along the pit lip, both sides, turned pairs. Props, not lights.
func _lip_masts(st: SurfaceTool) -> void:
	for i: int in MAST_COUNT:
		var t := (float(i) + 0.5) / float(MAST_COUNT)
		var along := lerpf(-HALF + 3.0, HALF - 3.0, t)
		for pair: Vector2 in turned(Vector2(along, -(HALF + 1.3))):
			var foot := Vector3(pair.x, RIM_TOP, pair.y)
			_beam(st, Transform3D.IDENTITY, foot, foot + Vector3.UP * MAST_HEIGHT, 0.16)
			var lean := Vector3(0.0, MAST_HEIGHT - 0.4, signf(pair.y) * -0.9)
			_beam(st, Transform3D.IDENTITY, foot + Vector3.UP * MAST_HEIGHT,
				foot + lean, 0.12)
		for pair: Vector2 in turned(Vector2(-(HALF + 1.3), along)):
			var foot := Vector3(pair.x, RIM_TOP, pair.y)
			_beam(st, Transform3D.IDENTITY, foot, foot + Vector3.UP * MAST_HEIGHT, 0.16)
			var lean := Vector3(signf(pair.x) * -0.9, MAST_HEIGHT - 0.4, 0.0)
			_beam(st, Transform3D.IDENTITY, foot + Vector3.UP * MAST_HEIGHT,
				foot + lean, 0.12)


## Hazard stripes round the shaft's lip: dashes of yellow paint lying a
## centimetre and a half on the floor, exactly the way `_build_kerb_paint` puts
## paint on a ramp. It is the one thing on this map that says out loud "the hole
## will kill you", it costs one flat quad a dash, and it reads at forty metres.
func _lip_hazard(st: SurfaceTool) -> void:
	var h := HOLE_HALF
	var band := 0.28
	var dash := 0.55
	var steps := int((h * 2.0) / (dash * 2.0))
	for side: int in 4:
		for i: int in steps:
			if i % 2 == 1:
				continue
			var a := lerpf(-h, h, float(i) / float(steps))
			var b := lerpf(-h, h, float(i + 1) / float(steps))
			# **Outside the lip, not inside it.** Written the other way round
			# every dash lay over the void, and what the first render showed was
			# a ring of yellow slabs floating off the edge of the hole with
			# nothing under them.
			var lo := Vector2(a, -h - band) if side == 0 else Vector2(a, h) if side == 1 \
				else Vector2(-h - band, a) if side == 2 else Vector2(h, a)
			var size := Vector2(b - a, band) if side < 2 else Vector2(band, b - a)
			_quad_into(st, Vector3(lo.x, 0.015, lo.y), size, 1.0)


## The cable runs: a span of steel between each derrick and the plant on its own
## side, sagging in the middle. Two beams a run, broken at the sag, which is
## three segments of catenary and is plenty at thirty metres.
func _cable_runs(st: SurfaceTool) -> void:
	for at: Vector2 in turned(DERRICK_AT):
		var mast := Vector3(at.x, DERRICK_HEIGHT - 4.0, at.y)
		# The plant on the derrick's *own* side. `DERRICK_AT.x` and `PLANT_AT.x`
		# are both written negative, so the sign that carries one table's turn
		# onto the other's is negated — without it every cable crosses the pit.
		var s := -signf(at.x)
		var plant := Vector3(-s * PLANT_AT.x, HOPPER_TOP - 2.2, -s * PLANT_AT.y)
		var sag := mast.lerp(plant, 0.5) - Vector3.UP * 2.4
		_beam(st, Transform3D.IDENTITY, mast, sag, 0.07)
		_beam(st, Transform3D.IDENTITY, sag, plant, 0.07)


# --------------------------------------------------------- team identity ---

## What makes a base Team 1's rather than Team 2's, now that the wall is stone.
##
## The wall used to *be* the identity: twelve metres of team-coloured brick, so
## the loudest surface on the map was also the surface a player's nose is
## pressed against for most of a round. It read as a test level, and it is not
## how a working site carries a colour either. A site paints a coping, flies a
## flag, stencils a door and throws a tarp over the shelter, and all four of
## those are readable from across a pit at a glance and none of them is the
## cover itself.
##
## **Both bases get exactly this function.** The only argument that differs
## between the two calls is `at`, and the only value derived from it that is not
## a geometric flip is `Nameplate.colour_for_team` — which is the same table the
## plates, the kill feed, the scoreboard and `CaptureBase`'s ring on this very
## bench are drawn from, so a base can never drift out of step with the ring
## standing in the middle of it.
const COPING_BAND := 0.26
const BANNER_WIDE := 1.5
const BANNER_DROP := 3.1
const FLAG_HEIGHT := 5.2


func _build_base_identity(parent: Node3D) -> void:
	var group := _group("BaseWorks", parent)
	for at: Vector2 in turned(BASE_AT):
		var team := team_of(at)
		var colour := Nameplate.colour_for_team(team)
		var paint := _begin()
		var cloth := _begin()
		var timber := _begin()
		var sheet := _begin()
		var sand := _begin()
		var steel := _begin()
		var block := _begin()

		_base_paint(at, paint)
		_base_banners(at, cloth)
		_base_flags(at, steel, cloth)
		_base_works(at, timber, sheet, sand, cloth, block)

		var side := half_of(at)
		# Darkened. `Nameplate`'s colours are UI colours — they are chosen to
		# read on a scoreboard at full brightness, and a 12 m run of one of them
		# at full saturation in direct sun is a strip light, not paint. Two
		# steps down is site paint on stone and still unmistakably the team's.
		var band := _commit(group, "Coping%s" % side, paint, _rust_material,
			colour.darkened(0.30))
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The cloth is the same paint material darkened: a banner in full sun is
		# the team's colour and a banner is dyed canvas, which is never as clean
		# as paint on stone.
		_commit(group, "Banner%s" % side, cloth, _rust_material, colour.darkened(0.38))
		_commit(group, "Yard%s" % side, timber, _timber_material, TIMBER)
		_commit(group, "Shelter%s" % side, sheet, _iron_material, SHEET_IRON)
		_commit(group, "Bags%s" % side, sand, _sand_material, SANDBAG)
		_commit(group, "Rig%s" % side, steel, _steel_material, STEEL)
		_commit(group, "Block%s" % side, block, _carved_material, STONE_CUT)


## The painted coping: a band down the *outer* face of the wall at its top, and
## a painted reveal down both jambs of each doorway.
##
## Outer face and jambs only, never the wall's top. The top of a long wall run
## is a declared landing (`_build_wall` appends a `Platform` for it), and this
## whole section's rule is that nothing visual goes above a walkable surface —
## two centimetres of paint on a landing is two centimetres of lie about where
## the floor is.
func _base_paint(at: Vector2, st: SurfaceTool) -> void:
	var pair := factors(at)
	var sign := pair.x
	var flip := pair.y
	var inner := sign * BENCH_INNER
	var face := inner + sign * WALL_THICK * 0.5
	var outer := face - sign * WALL_THICK * 0.5     # the face looking at the pit
	var top := BENCH_TOP + WALL_HEIGHT
	var proud := -sign * 0.035
	for entry: Dictionary in RAMPS:
		var axis := String(entry["axis"])
		var span: Vector2 = entry["span"]
		var lo := minf(sign * HALF, inner)
		var hi := maxf(sign * HALF, inner)
		# **The band follows the wall runs, not the wall line.** Run the whole
		# length it was a stripe of team colour hanging in mid-air across every
		# doorway and across the drop port — a floating bar with nothing behind
		# it, which is what the first render of this showed. The run splitting
		# below is `_build_wall`'s, copied rather than shared: that function
		# builds collision and is signed off, and a visuals pass does not get to
		# refactor it.
		var door := Vector2(minf(flip * span.x, flip * span.y) - DOOR_MARGIN,
			maxf(flip * span.x, flip * span.y) + DOOR_MARGIN)
		var gaps: Array[Vector2] = [door]
		if axis == "x":
			gaps.append(Vector2(minf(flip * PORT.x, flip * PORT.y),
				maxf(flip * PORT.x, flip * PORT.y)))
		var cuts: Array[Vector2] = []
		for gap: Vector2 in gaps:
			cuts.append(Vector2(minf(gap.x, gap.y), maxf(gap.x, gap.y)))
		cuts.sort_custom(func(m: Vector2, n: Vector2) -> bool: return m.x < n.x)
		var runs: Array[Vector2] = []
		var cursor := lo
		for cut: Vector2 in cuts:
			if cut.x > cursor:
				runs.append(Vector2(cursor, minf(cut.x, hi)))
			cursor = maxf(cursor, cut.y)
		if cursor < hi:
			runs.append(Vector2(cursor, hi))
		# **Both faces of the wall.** The outer band is what the rest of the
		# map reads the base off; the inner one is what the team standing in it
		# reads, and without it a defender's whole world is stone — the colour
		# is all on the side they cannot see. Two thin slabs, one draw call,
		# and it is the difference between a base and a walled yard.
		var inner_face := face + sign * WALL_THICK * 0.5
		for run: Vector2 in runs:
			if run.y - run.x < 0.4:
				continue
			for side_of: Vector2 in [Vector2(outer, proud),
					Vector2(inner_face, -proud)]:
				var at_face := side_of.x
				var push := side_of.y
				var a := Vector2(at_face, run.x) if axis == "x" \
					else Vector2(run.x, at_face)
				var b := Vector2(at_face + push, run.y) if axis == "x" \
					else Vector2(run.y, at_face + push)
				_slab(st, Vector2(minf(a.x, b.x), minf(a.y, b.y)),
					Vector2(maxf(a.x, b.x), maxf(a.y, b.y)),
					top - COPING_BAND - 0.1, top - 0.1)
		for edge: float in [door.x, door.y]:
			var jamb := 0.06
			var j0 := Vector2(face - sign * WALL_THICK * 0.5, edge - jamb)
			var j1 := Vector2(face + sign * WALL_THICK * 0.5, edge + jamb)
			if axis != "x":
				j0 = Vector2(edge - jamb, face - sign * WALL_THICK * 0.5)
				j1 = Vector2(edge + jamb, face + sign * WALL_THICK * 0.5)
			_slab(st, Vector2(minf(j0.x, j1.x), minf(j0.y, j1.y)),
				Vector2(maxf(j0.x, j1.x), maxf(j0.y, j1.y)), BENCH_TOP, top - 0.02)


## Banners hung down the wall's outer face — the thing a player actually reads
## the base off from across the pit, because a 1.1 by 2.6 m panel of colour at
## five metres up is a bigger signal than a painted line and a smaller one than
## a wall.
##
## Hung *outside* the wall over the bench's four-metre face, so nothing about
## them is anywhere near a surface a Bog stands on.
func _base_banners(at: Vector2, st: SurfaceTool) -> void:
	var pair := factors(at)
	var sign := pair.x
	var inner := sign * BENCH_INNER
	var outer := inner + sign * 0.02
	var top := BENCH_TOP + WALL_HEIGHT - 0.15
	for entry: Dictionary in RAMPS:
		var axis := String(entry["axis"])
		for k: int in 2:
			var along := lerpf(sign * HALF, inner, 0.28 + 0.34 * float(k))
			var a := Vector2(outer, along - BANNER_WIDE * 0.5) if axis == "x" \
				else Vector2(along - BANNER_WIDE * 0.5, outer)
			var b := Vector2(outer - sign * 0.03, along + BANNER_WIDE * 0.5) if axis == "x" \
				else Vector2(along + BANNER_WIDE * 0.5, outer - sign * 0.03)
			_slab(st, Vector2(minf(a.x, b.x), minf(a.y, b.y)),
				Vector2(maxf(a.x, b.x), maxf(a.y, b.y)), top - BANNER_DROP, top)


## Two flagstaffs, in the bench's back corner against the cliff.
##
## The corner is the one square metre of a base nobody stands in — it is where
## the two rim faces meet, behind the pad, with the wall's two runs ending
## somewhere else entirely — which is why the masts are there and not on the
## wall, whose top is a landing.
func _base_flags(at: Vector2, steel: SurfaceTool, cloth: SurfaceTool) -> void:
	var sign := factors(at).x
	for k: int in 2:
		var corner := Vector3(sign * (HALF - 0.5), BENCH_TOP, sign * (HALF - 0.5))
		corner += Vector3(-sign * 1.6 * float(k), 0.0, sign * 1.6 * float(k))
		_beam(steel, Transform3D.IDENTITY, corner,
			corner + Vector3.UP * FLAG_HEIGHT, 0.12)
		var head := corner + Vector3.UP * (FLAG_HEIGHT - 0.2)
		var fly := Vector3(-sign * 1.5, 0.0, -sign * 1.5).normalized() * 1.7
		_panel(cloth, head, head + fly, head + fly - Vector3.UP * 1.0,
			head - Vector3.UP * 1.0)


## The works: the lean-to shelter in the back corner, the gabion baskets in the
## dead corner where the two wall runs meet, and a pallet of cut block.
##
## All three are in corners on purpose. A base bench is a 12.5 m square with a
## capture ring in the middle of it and two doorways to defend, and the one
## thing a visuals pass must not do to it is put scenery where a fight happens.
## The back corner is behind the pad with eleven metres of cliff on two sides;
## the inner corner is the spot `_build_wall` explicitly refuses to advertise as
## a perch because a Bog standing there has its capsule inside the wall.
func _base_works(at: Vector2, timber: SurfaceTool, sheet: SurfaceTool,
		sand: SurfaceTool, cloth: SurfaceTool, block: SurfaceTool) -> void:
	var sign := factors(at).x
	var back := Vector3(sign * (HALF - 2.1), BENCH_TOP, sign * (HALF - 4.6))
	var turn := Basis(Vector3.UP, 0.0 if sign < 0.0 else PI)
	var frame := Transform3D(turn, back)
	# Four posts and a pitched corrugated roof: a site lean-to, 2.6 by 3.4, in
	# the corner of the bench with the cliff at its back.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_beam(timber, frame, Vector3(sx * 1.2, 0.0, sz * 1.6),
				Vector3(sx * 1.2, 2.2, sz * 1.6), 0.16)
	for s: float in [-1.0, 1.0]:
		var a := Vector3(-1.35, 2.2, s * 1.75)
		var b := Vector3(1.35, 2.2, s * 1.75)
		var c := Vector3(1.35, 2.75, 0.0)
		var d := Vector3(-1.35, 2.75, 0.0)
		_panel(sheet, frame * a, frame * b, frame * c, frame * d)
	# The tarp down one side, in the team's colour. The one piece of cloth on
	# the map big enough to read from the far rim.
	_panel(cloth, frame * Vector3(-1.3, 2.15, -1.7), frame * Vector3(1.3, 2.15, -1.7),
		frame * Vector3(1.3, 0.35, -1.78), frame * Vector3(-1.3, 0.35, -1.78))
	_pallet(timber, block, frame * Transform3D(Basis(Vector3.UP, 0.4),
		Vector3(0.0, 0.0, 2.9)), 2)
	# The gabions, in the inner corner where the two wall runs meet.
	# **Inside the bench from the corner, not outside it.** `BENCH_INNER` is the
	# bench's own edge and the four-metre drop is on the other side of it, so
	# the baskets run from `BENCH_INNER + 1.2` *away* from the pit — written the
	# other way round they hang in mid-air over the haul road.
	# **Knee high, not chest high, and three of them.** The first pass stood
	# five 0.9 m baskets in the inner corner and they came out as a black wall
	# straight across the one thing a defender on this bench is looking at — the
	# pit. A gabion revetment is a thing you see over.
	var nook := Vector3(sign * (BENCH_INNER + 1.1), BENCH_TOP, sign * (BENCH_INNER + 1.1))
	for k: int in 2:
		var slot := nook + Vector3(sign * 0.9 * float(k), 0.0, 0.0)
		_box(sand, Transform3D(Basis.IDENTITY, slot + Vector3.UP * 0.30),
			Vector3(0.84, 0.6, 0.84))
	_box(sand, Transform3D(Basis.IDENTITY,
		nook + Vector3(0.0, 0.30, sign * 0.9)), Vector3(0.84, 0.6, 0.84))


# ------------------------------------------------------------ mesh helpers ---

## A box of arbitrary size in an arbitrary frame — the one primitive `_slab`
## could not draw, because `_slab` is axis-aligned and half of the relief pass
## is rock that is *not* square to the pit.
##
## UVs are written in metres across each face like everything else here, which
## matters for the few surfaces that end up on a non-triplanar material and
## costs nothing for the rest.
func _box(st: SurfaceTool, frame: Transform3D, size: Vector3) -> void:
	var half := size * 0.5
	# **Copied from `_beam`, row for row.** Each row is (normal, u, v) and the
	# three are not free: the vertex order below only winds outward when
	# `u.cross(v) == -normal`, which is true of every row here and was false of
	# four rows of the table this replaced.
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
			st.set_uv(Vector2(p.dot(u), p.dot(v)))
			st.add_vertex(frame * p)


## The worn top edge of a box: a mitred ring of four quads sloping down and out
## from the top face.
##
## Mitred, not butted — each quad's outer corners are the box's corners pushed
## out **diagonally**, so the four meet exactly at the corners with no gap and
## no overlap, which is why this is four quads and not four quads plus four
## corner triangles.
func _arris(st: SurfaceTool, lo: Vector2, hi: Vector2, top: float, d: float) -> void:
	# Corner order copied from `_slab`'s top face, so the ring winds the same
	# way the surface it grows out of does.
	var inner := [Vector2(lo.x, hi.y), Vector2(hi.x, hi.y), Vector2(hi.x, lo.y),
		Vector2(lo.x, lo.y)]
	var outer := [Vector2(lo.x - d, hi.y + d), Vector2(hi.x + d, hi.y + d),
		Vector2(hi.x + d, lo.y - d), Vector2(lo.x - d, lo.y - d)]
	for i: int in 4:
		var j := (i + 1) % 4
		var a := Vector3(inner[i].x, top, inner[i].y)
		var b := Vector3(inner[j].x, top, inner[j].y)
		var c := Vector3(outer[j].x, top - d, outer[j].y)
		var e := Vector3(outer[i].x, top - d, outer[i].y)
		# Wound outer-first. The other way round — along the inner edge, then
		# out and down — the ring comes out facing *into* the block, and every
		# worn edge on the map is a hole in the top of a box.
		_quad(st, e, c, b, a, (c - e).cross(b - c).normalized(),
			Vector2(a.distance_to(b), d * 1.42))


## One flat sheet, **drawn from both sides**.
##
## Everything this map builds out of `_slab` and `_beam` is a closed solid, so
## back-face culling is free and the winding never has to be thought about. The
## visuals pass added things that are not solids — a banner, a tarp, a flag, a
## corrugated roof, the sloped wall of a hopper — and every one of them is a
## single quad that somebody looks at from the back. Two windings and two
## normals cost six extra vertices and remove a whole class of bug where a
## surface is simply invisible from the one angle anybody sees it from.
func _panel(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var normal := (b - a).cross(d - a).normalized()
	var span := Vector2(a.distance_to(b), a.distance_to(d))
	_quad(st, a, b, c, d, normal, span)
	_quad(st, d, c, b, a, -normal, span)


## A low fan of chips: a cone of `sides` triangles, `radius` across and `height`
## tall, apex up. Used for scree at the foot of a face and for the waste heaps
## down the shaft, where it is allowed to be a real heap.
func _scree_fan(st: SurfaceTool, at: Vector3, radius: float, height: float,
		sides: int) -> void:
	var apex := at + Vector3.UP * height
	for i: int in sides:
		var a := TAU * float(i) / float(sides)
		var b := TAU * float(i + 1) / float(sides)
		# Each skirt point pulled in or out a little, so the fan is a heap and
		# not a party hat. Deterministic off the angle, not off a generator, so
		# this stays a pure function.
		var ra := radius * (0.72 + 0.28 * absf(sin(a * 3.0 + at.x)))
		var rb := radius * (0.72 + 0.28 * absf(sin(b * 3.0 + at.x)))
		var p := at + Vector3(cos(a) * ra, 0.0, sin(a) * ra)
		var q := at + Vector3(cos(b) * rb, 0.0, sin(b) * rb)
		# A degenerate quad rather than a triangle: `_panel` is the one thing
		# here that does not have to be reasoned about twice, and a heap of
		# chips seen from underneath — which happens at the shaft ledge, looked
		# up at from a catwalk — is worth the second winding.
		_panel(st, p, q, apex, apex)


# =============================================== more of the quarry pack ===
#
# The rebuild used thirteen of the pack's sixty-five models. A good third of
# what is left is ice, crystal, emerald, gold or "futuristic" and stays unused
# for the reason it always did — this is a sun-baked worked-out limestone pit,
# not a fantasy mine — but the rest of the remainder was simply never reached,
# and a contact sheet with eight usable stone portals on it and two of them
# placed is a contact sheet nobody finished reading.
#
# Everything below is **dressing with no collision**, and every one of them is
# put somewhere a Bog cannot be stopped by it: against a cliff face, on the rim
# eleven metres up, or sixteen metres down the shaft on a floor the void height
# kills you six metres above. That last one is the useful discovery of this
# pass — the bottom of the hole is in shot from both catwalks, both lips and
# every terrace, it is lit, and nothing can ever walk on it.


## Blind adits: portals bricked up or boarded over, standing against stretches
## of the rim's inner face that no bench, terrace or corner mass is built
## against. Three more pairs on top of the two the rebuild placed.
##
## The free stretches are worth writing down, because getting one wrong buries
## a portal inside a bench: the south-west quarter of the west face and of the
## south face is Team 1's bench, the north-west corner is the spoil mass
## (x in [-24, -10], z in [10, 24]), the south-east corner is the terraces
## (x in [10, 24], z in [-24, -10]), and each of those has a rotational twin.
## What is left is the middle of each face, roughly -11 to +9, which is where
## these are.
##
## `yaw` turns the model's own +x — its opening — to face into the pit. Rotating
## +x about +y by θ gives (cos θ, 0, -sin θ), so a portal on the west face wants
## 0, one on the east PI, one on the south -PI/2 and one on the north +PI/2.
const BLIND_ADITS: Array[Dictionary] = [
	{"model": "wooden_mine_tunnel_01", "at": Vector2(-HALF, -5.0), "yaw": 0.0,
		"wide": 4.2},
	{"model": "wooden_mine_tunnel_02", "at": Vector2(-5.0, -HALF), "yaw": -PI * 0.5,
		"wide": 4.2},
	{"model": "stone_mine_tunnel_05", "at": Vector2(-HALF, -9.5), "yaw": 0.0,
		"wide": 3.4},
	{"model": "stone_mine_tunnel_06", "at": Vector2(-9.5, -HALF), "yaw": -PI * 0.5,
		"wide": 3.4},
]

## The pack's portal models used as what they mostly are — a mound of stone with
## a hole in it — standing on the rim eleven metres up, where they are silhouette
## and nothing else. Four of them, on the two sides the derricks and the plant
## are not on, at a size nothing in the pit can be compared against.
const RIM_MOUNDS: Array[Dictionary] = [
	{"model": "stone_mine_tunnel_01", "at": Vector2(-13.0, -25.4), "yaw": PI * 0.5,
		"wide": 6.0},
	{"model": "stone_mine_tunnel_04", "at": Vector2(9.0, -25.6), "yaw": PI * 0.5,
		"wide": 5.0},
	{"model": "stone_mine_tunnel_07", "at": Vector2(-25.4, 13.0), "yaw": 0.0,
		"wide": 5.4},
]

## Ladders. Two against the spoil bench's east face, which is the 4.5 m wall a
## player looks at every time they come up the north band, and one down the
## shaft to the ledge — where it is pure storytelling, because the ledge is
## unreachable and always will be.
## **Absolute, and not a turned table.** The first version turned them like
## everything else and the turn of the spoil bench's east face is not a face at
## all — it is the terraces' low step, 1.5 m high — so Team 2's half got two
## four-and-a-half-metre ladders standing in the open against nothing. Where a
## feature has no rotational twin, its dressing has none either; the pair below
## is on the spoil bench, and the pair in the shaft is a real turned pair
## because the shaft is square.
const LADDERS: Array[Dictionary] = [
	{"at": Vector3(-10.0 + LADDER_PROUD, 0.0, 14.0), "yaw": 0.0, "tall": 4.7},
	{"at": Vector3(-10.0 + LADDER_PROUD, 0.0, 20.5), "yaw": 0.0, "tall": 4.7},
	# Down the shaft's west and east walls, from the ledge to the pit floor.
	# Nobody will ever climb them: the ledge is 5.5 m down a hole whose void
	# height kills at 10. They are there because a worked shaft has a way down
	# it, and because they are in shot from both catwalks.
	{"at": Vector3(-HOLE_HALF + LADDER_PROUD, HOLE_LEDGE, 3.4), "yaw": 0.0,
		"tall": HOLE_LEDGE * -1.0 + 0.3},
	{"at": Vector3(HOLE_HALF - LADDER_PROUD, HOLE_LEDGE, -3.4), "yaw": PI,
		"tall": HOLE_LEDGE * -1.0 + 0.3},
]
const LADDER_MODEL := "wooden_ladder_01"
## How far the ladder's stiles stand off the rock they are leaning on. Enough to
## clear the drill ribs, which are 7 cm, and no more.
const LADDER_PROUD := 0.12

## Warning boards at the two catwalk mouths and at the head of each haul ramp.
## `stone_sign_01` is the pack's second board with nothing fantastical on it —
## a plank in a stone frame — so it is the only model joining `mineshaft_sign_01`
## in use.
##
## The catwalk pair is the point of the table: each deck has a span of missing
## planks in it that can only be crossed on the dive, and a player meeting that
## gap at a run with nothing to warn them is a player who finds out about it in
## the air. A board at the mouth is the cheapest way a map has of saying so.
const WARN_MODEL := "stone_sign_01"
const WARN_SIGNS: Array[Dictionary] = [
	{"at": Vector2(9.9, 7.0), "yaw": PI, "height": 1.9},
	{"at": Vector2(-9.9, -7.0), "yaw": 0.0, "height": 1.9},
]

## Extra rail, laid where there is no lane to block: along the rim shelf past
## the plant, and across the bottom of the shaft. Each run names its own model,
## because the pack has eleven straight tracks in four different colours of iron
## and using one for everything is what made forty metres of identical sleepers.
##
##   model  which straight to lay
##   from   the run's start, in world x/z
##   to     its end
##   y      the floor it is laid on
##   pitch  what one instance covers along the run
const EXTRA_RAILS: Array[Dictionary] = [
	# The bottom of the hole. Sixteen metres down, in shot from both catwalks
	# and both lips, and on ground the void height kills a Bog six metres above.
	{"model": "railway_track_01", "from": Vector2(-6.2, 5.6), "to": Vector2(6.2, 5.6),
		"y": HOLE_FLOOR, "pitch": 2.2},
	{"model": "railway_track_01", "from": Vector2(-6.2, -5.6), "to": Vector2(6.2, -5.6),
		"y": HOLE_FLOOR, "pitch": 2.2},
	# The rim shelf, past the crusher and out to the derrick, both halves.
	{"model": "railroad_track_08", "from": Vector2(-25.4, -18.0),
		"to": Vector2(-25.4, 8.0), "y": RIM_TOP, "pitch": 2.2},
	{"model": "railroad_track_08", "from": Vector2(25.4, 18.0),
		"to": Vector2(25.4, -8.0), "y": RIM_TOP, "pitch": 2.2},
	# A short spur off the tunnel's east mouth into the north band's siding,
	# and its turn, in a paler iron than the main run so the two read as track
	# laid at different times.
	{"model": "railway_track_04", "from": Vector2(-13.5, 12.6),
		"to": Vector2(-13.5, 6.0), "y": 0.0, "pitch": 2.2},
	{"model": "railway_track_04", "from": Vector2(13.5, -12.6),
		"to": Vector2(13.5, -6.0), "y": 0.0, "pitch": 2.2},
]

## The trains. Three tubs nose to tail is a train and one tub is a prop, and the
## difference between the two is most of what says this hole was *worked*.
##
## Both trains stand where a cart cannot be cover, which is the whole reason
## they are allowed to exist without the box of collision `CART_STANDS` gives
## every cart on the pit floor: one is at the bottom of the shaft and one is on
## the rim, and a Bog can reach neither.
const TRAINS: Array[Dictionary] = [
	{"model": "mining_cart_01", "at": Vector3(-4.4, HOLE_FLOOR, 5.6), "yaw": PI * 0.5,
		"count": 3, "step": Vector3(2.6, 0.0, 0.0)},
	{"model": "wooden_minecart_01", "at": Vector3(-25.4, RIM_TOP, -14.0),
		"yaw": 0.0, "count": 3, "step": Vector3(0.0, 0.0, 2.6)},
]
## And their turns, so neither half of the skyline is the interesting one.
const TRAIN_HEIGHT := 1.25

## More ore, at the faces that are actually being worked: the foot of each
## column and the toe of the spoil bench, rather than scattered about the open
## floor where the first six went.
const EXTRA_ORE: Array[Dictionary] = [
	{"at": Vector2(-18.6, -3.4), "model": 0},
	{"at": Vector2(-12.0, -17.4), "model": 2},
	{"at": Vector2(-22.4, -9.6), "model": 1},
	{"at": Vector2(-11.2, 11.4), "model": 3},
	{"at": Vector2(-3.2, -22.0), "model": 4},
]
## Powder kegs at the working faces, to match.
const EXTRA_BARRELS: Array[Vector2] = [
	Vector2(-19.2, -4.2), Vector2(-19.8, -3.6),
	Vector2(19.2, 4.2), Vector2(19.8, 3.6),
	Vector2(-2.4, -22.3), Vector2(2.4, 22.3),
]

## **`stone_staircase_01` is deliberately not used.** The brief asked for it on
## an existing ramp if and only if the model's own slope matches the ramp's. It
## does not: the model is an L-shaped chunk of steps turning a corner, not a
## straight flight, and the two ramps it could go on are straight 19.2 and 24.2
## degree wedges. A stair laid over a ramp at the wrong pitch is a stair whose
## treads a player's feet pass through, which is worse than no stair.


## Everything above, hung after `super()` like the rest of the pack.
func _build_extra_pack(parent: Node3D) -> void:
	var group := _group("Works", parent)
	_build_blind_adits(group)
	_build_rim_mounds(group)
	_build_ladders(group)
	_build_warnings(group)
	_build_extra_rails(group)
	_build_trains(group)
	_build_extra_ore(group)


## The blind adits, turned. `ADIT_PROUD` pushes each mound back through the
## cliff until only the mouth is outside it — the same trick `_build_adits`
## uses, and the reason these can stand on a face a Bog runs along.
func _build_blind_adits(parent: Node3D) -> void:
	for entry: Dictionary in BLIND_ADITS:
		var here: Vector2 = entry["at"]
		var yaw := float(entry["yaw"])
		for k: int in 2:
			var at := here if k == 0 else -here
			var node := _pack_prop(parent, String(entry["model"]),
				Vector3(at.x, 0.0, at.y), yaw + PI * float(k), "z",
				float(entry["wide"]), ADIT_PROUD)
			if node != null:
				_tint_pack(node, PACK_STONE)


## Portal mounds on the rim, at a size nothing in the pit can be compared
## against. Turned, like everything else.
func _build_rim_mounds(parent: Node3D) -> void:
	for entry: Dictionary in RIM_MOUNDS:
		var here: Vector2 = entry["at"]
		var yaw := float(entry["yaw"])
		for k: int in 2:
			var at := here if k == 0 else -here
			var node := _pack_prop(parent, String(entry["model"]),
				Vector3(at.x, RIM_TOP - 0.2, at.y), yaw + PI * float(k), "z",
				float(entry["wide"]))
			if node != null:
				# Harder than the adits: these are on the skyline with eleven
				# metres of air under them and nothing beside them to be judged
				# against, so anything paler than the rock reads as a mistake.
				_tint_pack(node, PACK_STONE * Color(0.78, 0.76, 0.72))


## Ladders flat against a face, standing upright rather than leaning.
##
## Upright because `_pack_prop` yaws and scales and does nothing else, and a
## ladder tilted after the fact is a ladder whose foot is no longer on the
## ground it was sat on. A ladder bolted flat to a rock face is a real thing and
## a leaning one that floats is not.
func _build_ladders(parent: Node3D) -> void:
	for entry: Dictionary in LADDERS:
		var node := _pack_prop(parent, LADDER_MODEL, entry["at"],
			float(entry["yaw"]), "y", float(entry["tall"]))
		if node != null:
			_tint_pack(node, PACK_STONE)


## The warning boards, on posts, at the two catwalk mouths.
func _build_warnings(parent: Node3D) -> void:
	var st := _begin()
	for entry: Dictionary in WARN_SIGNS:
		var here: Vector2 = entry["at"]
		var height := float(entry["height"])
		for at: Vector2 in turned(here):
			var head := Vector3(at.x, height, at.y)
			_beam(st, Transform3D.IDENTITY, Vector3(at.x, 0.0, at.y), head, 0.13)
			_pack_prop(parent, WARN_MODEL, head - Vector3(0.0, 0.42, 0.0),
				float(entry["yaw"]) + (0.0 if at == here else PI), "x", 1.4)
	var node := MeshInstance3D.new()
	node.name = "WarningPosts"
	node.mesh = st.commit()
	node.material_override = _timber_material.duplicate()
	(node.material_override as StandardMaterial3D).albedo_color = TIMBER
	parent.add_child(node)


## The extra rail runs, one `MultiMesh` each, the same way `_build_rails` lays
## the main ones.
func _build_extra_rails(parent: Node3D) -> void:
	for run: int in EXTRA_RAILS.size():
		var entry: Dictionary = EXTRA_RAILS[run]
		_rail_run(parent, "Spur%d" % run, String(entry["model"]),
			entry["from"], entry["to"], float(entry["y"]), float(entry["pitch"]))


## One run of a named straight track, laid end to end between two points on a
## named floor.
##
## This is `_build_rails` generalised over the model and the height. It is not
## shared with it: that function is on the collision side of nothing but is
## wired into `RAIL_RUNS`, and a visuals pass that rewrites a working loop to
## save nine lines has bought nine lines with a risk.
func _rail_run(parent: Node3D, named: String, model: String, from: Vector2,
		to: Vector2, y: float, pitch: float) -> void:
	var part := _pack_single(model)
	if part.is_empty():
		return
	var mesh: Mesh = part["mesh"]
	var box: AABB = part["aabb"]
	var along := pitch / box.size.x
	var span := from.distance_to(to)
	var count := maxi(1, int(span / pitch))
	var step := (to - from) / float(count)
	var yaw := atan2(step.x, step.y) - PI * 0.5
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	var bounds := AABB()
	for i: int in count:
		var at := from + step * (float(i) + 0.5)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(along, along, along))
		var xform := Transform3D(basis,
			Vector3(at.x, y - box.position.y * along - 0.02, at.y))
		multi.set_instance_transform(i, xform)
		var cell := xform * box
		bounds = cell if i == 0 else bounds.merge(cell)
	var node := MultiMeshInstance3D.new()
	node.name = named
	node.multimesh = multi
	node.custom_aabb = bounds
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


## The two trains and their turns.
func _build_trains(parent: Node3D) -> void:
	for entry: Dictionary in TRAINS:
		var here: Vector3 = entry["at"]
		var step: Vector3 = entry["step"]
		for k: int in 2:
			var head := here if k == 0 else Vector3(-here.x, here.y, -here.z)
			var walk := step if k == 0 else -step
			for i: int in int(entry["count"]):
				_pack_prop(parent, String(entry["model"]), head + walk * float(i),
					float(entry["yaw"]) + PI * float(k), "y", TRAIN_HEIGHT)


## More ore and more kegs, at the faces being worked.
func _build_extra_ore(parent: Node3D) -> void:
	for entry: Dictionary in EXTRA_ORE:
		var model := ORE_MODELS[int(entry["model"]) % ORE_MODELS.size()]
		var pair := turned(entry["at"])
		for k: int in pair.size():
			var at: Vector2 = pair[k]
			_pack_prop(parent, model, Vector3(at.x, 0.0, at.y),
				1.3 + 2.4 * float(k), "x", ORE_SPAN)
	for i: int in EXTRA_BARRELS.size():
		var at: Vector2 = EXTRA_BARRELS[i]
		_pack_prop(parent, BARREL_MODEL, Vector3(at.x, 0.0, at.y),
			0.9 * float(i), "y", BARREL_HEIGHT)
