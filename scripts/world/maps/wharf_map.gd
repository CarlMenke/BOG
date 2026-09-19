class_name WharfMap
extends StaticMap
## Lantern Wharf — a walled box yard at dusk, small, dense and symmetric on
## purpose, built in code from layout tables the way Kopje Crossing is (D-042).
##
## It is the opposite map to the savanna. Kopje Crossing is 96 m of long
## sightlines and a hundred and twenty climbs; this is 43.2 m square, walled in by
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
##               Bog's kit, the one-tick dive included — `tools/parkour_report`
##               fails the build if one can be reached (`off_limits`).
##
## And the works: a forklift, painted drums, pallets and pipe stock, all of it
## **solid** and all of it built before `super()`, because a box at chest height
## that a spear flies through is the one lie this map must not tell (D-084).
##
## There is no two-high stack anywhere, and that is deliberate. The dive off a
## jump reaches 4.2 m of rise, so a 5.2 m stack beside a 2.6 m single is a stack
## somebody climbs, and from 5.2 m every single roof on the map is in view.
##
## The north half is written out in the tables and the south half is its mirror
## across z = 0, so neither team has an edge. Entries on z = 0 are placed once.
##
## Build order is Kopje Crossing's and the rule is the same: everything added
## before `super()` is swept into collision, everything after is dressing — the
## floor paint, the door bars, the cranes over the wall, the floodlights, the
## port beyond them and everything in the air. Nothing on this map is random, so
## every peer builds the same yard by construction rather than by a shared seed.
##
## ## The hour
##
## The yard shipped as a dusk map that was not one. The sun sat 17 degrees up at
## 0.9 energy, which is a mid-afternoon; the four floodlights were 5-energy spots
## under it with nothing left to do; the air between them was a vacuum; the
## floor was a noise tile that a comment called wet; and the walls ended at
## their own outer face, so a wharf was a room. The atmosphere pass changed all
## of that and none of the geometry — every metre of collision, every landing,
## every sightline and every pad is exactly where it was, because all of those
## are built above the `super()` call and everything below that line is dressing
## that nothing can collide with.
##
## What the hour is now: twenty minutes of usable light left, the sun already
## behind the west stacks, the floods just warm, and the tide bringing mist up
## the mole. Five layers do it, in the order they matter:
##
##   the floor    real concrete (`wharf_wet_concrete.gdshader`) wetted down at
##                runtime — pools that ripple, near-mirror inside them, and the
##                environment's SSR to put the lamp heads in them. Half of every
##                frame on this map is floor.
##   the beams    the floods are *sources* now rather than lights: visible cones
##                in volumetric fog, a glare billboard each, a sodium breath,
##                and moths churning in them.
##   the air      a FogVolume of sea mist lying in the bottom 1.8 m, with thirty
##                sheets drifting through it (`wharf_ambience.gd`).
##   the port     forty-odd stacks, a ship, a shed, five gantries and a
##                lighthouse outside the walls — all of it tall, because tall is
##                the only thing a Bog inside a 7.8 m wall can see.
##   the sky      `wharf_sky.tres` on the island's shader: a sun disc that
##                follows this map's `Sun`, cloud that drifts, the first stars.
##
## One number governs the whole of the port. From eye height (1.45 m) in the
## middle of the yard the top of the near wall is 6.35 m up at 21.6 m out, so
## anything beyond the wall has to clear `1.45 + 0.294 * distance` to exist at
## all. That is 12 m at 36 m out and 18 m at 56 m, and it is why everything in
## `_build_port` is tall and nothing in it is detailed. The slope was 0.353
## before the 1.2x pass: a wider yard is a *flatter* cone out of it, so the port
## had to move out with the walls or it would have grown in frame rather than
## staying put — which is why every coordinate in it is scaled too.
##
## ## The works
##
## Everything above `super()` is collision, and since the works went in that is
## more than boxes: two forklifts, three dozen drums, pallets and pipe stock, and
## **four of the single containers hollowed through** so the east-west aisle has
## rooms you can be chased into and out of. All of it is solid, because on a map
## whose grammar is *this is cover and that is not* a body-high prop a spear
## flies through is a lie the player finds out about by dying.
##
## The Factory Kit plant — pipes up the wall faces, machinery along the wall
## tops, panels and floor markings — is dressing, below the line, and obeys the
## stricter version of that rule: nothing between 0.3 m and 2.4 m anywhere a Bog
## can walk. There is no town of mine outside the wall; `_build_port` is the
## answer to that question and a better one.

# ---------------------------------------------------------------- the table ---

## Half the yard's width. The walls' inner faces stand on these lines.
##
## ## The 1.2x pass
##
## The yard was 36 m square and is 43.2 m square. One number did it — `HALF`
## went 18 -> 21.6 — and every position in every table below was multiplied by
## the same 1.2, because the thing the owner likes about this map is its
## *layout*, and a layout is a set of ratios. Scaling positions and leaving
## sizes alone keeps every ratio between two pieces of cover identical and
## widens only the air between them, which is exactly the ask: more room in the
## lanes, the same rhythm of cover.
##
## Two classes of exception, both of them deliberate and both of them recorded
## at the table that needed them:
##
##   flush contacts   a crate laid against a container, a tower laid against the
##                    perimeter wall, a forklift parked against a tower end.
##                    These were flush before and 1.2 x a position is not flush
##                    any more — it leaves a 0.4-0.6 m slot, which is narrower
##                    than a Bog (0.76 m across) and is therefore the exact
##                    thing the `CRATES` comment has always forbidden. Each of
##                    these was re-derived from the steel it touches instead of
##                    scaled, so it is flush again by construction.
##   prop sizes       a crate stays a crate, a drum stays a drum, a container
##                    stays 6 x 2.6 x 2.4. Nothing below scales a *size*.
##
## What that buys, in the numbers that decide how the map plays: the centre
## crossroads opens from 3.6 m to 4.8 m, the base bay from 6.6 m to 8.4 m, and
## the perimeter lane behind the wall towers from 5.3 m to 6.6 m. Every gap is
## still a gap a Bog walks through and none of them became a lane you can cross
## unseen, because the towers that cut those lines grew apart with them.
const HALF := 21.6

## What the 1.2x pass multiplied, kept as a constant so the arithmetic in the
## tables below can be checked rather than trusted. Nothing reads it at runtime
## — every table holds its finished number, because a table of `-4.5 * SPREAD`
## is a table you cannot read a layout out of.
const SPREAD := 1.2

## A container, as length x height x width. A Bog is 1.55 m tall, so a single
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
## these offsets along the side.
##
## A container is 6 m and does not scale, so this table is the one place the
## 1.2x pass could not simply multiply: the side is 48 m of outer face now
## (`FLOOR_EDGE * 2`), which is eight boxes end to end rather than seven, and
## eight boxes have no member on the centre line. That is fine and it is checked
## — the list is still symmetric about 0, so neither team gets the odd one.
##
## Eight of 6 m is exactly 48 m and the corners are covered twice over anyway:
## the north wall's end box occupies x in [-24, -18] at z in [-24, -21.6], and
## the west wall's end box occupies z in [-24, -18] at x in [-24, -21.6], so the
## 2.4 m corner square is filled by both and no corner shows daylight.
const WALL_TIERS := 3
const WALL_CENTRES: PackedFloat32Array = [-21.0, -15.0, -9.0, -3.0, 3.0, 9.0, 15.0, 21.0]
## Wall boxes that carry a fourth tier, by (side, index). Not reachable either —
## it is higher than a tier that already is not — and it gives the skyline over
## the wall a broken edge instead of a ruler.
## Indices re-pointed for the eight-box wall: the same four broken places, one
## in from each end on the north side and one either side of the middle on the
## two flanks.
const WALL_EXTRA: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, 6), Vector2i(2, 3),
	Vector2i(3, 4)]

## Every box inside the yard, north half. `at` is the centre on (x, z), `axis`
## the direction the box's length runs in, `tiers` 1 for a single and 3 for a
## tower, and `paint` indexes `PAINTS` bottom tier first. `open` hollows a
## single out into a corridor — see `_open_container_mesh` for what that costs.
##
## The layout was searched for rather than drawn, and then read and trimmed by
## hand: a 43.2 m square has 61 m diagonals, and the only way to keep every line
## under 25 m is to put something tall across most of them. The 1.2x pass kept
## that true by moving the blockers apart with the square rather than leaving
## them standing in a bigger room — see `HALF`. The two things that
## decided it are in the comments below. See D-056 for the search.
const BOXES: Array[Dictionary] = [
	# The base bay: two towers out from the back wall either side of the base,
	# so the strip along the back wall — the one line on the map nobody can
	# avoid crossing — is three rooms and not a 34 m lane.
	#
	# x scaled (-4.5 -> -5.4); z re-derived rather than scaled, because these two
	# were flush against the back wall and 1.2 x -15 is -18, which stands them
	# 0.6 m off it. Flush is -21.6 + 3 = -18.6, and flush is what the bay needs:
	# a 0.6 m slot between a tower and the perimeter is a place a Bog gets stuck
	# behind his own base.
	{"label": "bay west", "at": Vector2(-5.4, -18.6), "axis": "z", "tiers": 3, "paint": [1, 6, 0]},
	{"label": "bay east", "at": Vector2(5.4, -18.6), "axis": "z", "tiers": 3, "paint": [0, 5, 2]},
	# The spine in front of the base, so the far base never sees into this one.
	#
	# **Not scaled: abutted.** This is the entry the 1.2x pass got wrong twice
	# and it is worth writing down why. A container is 6 m and does not grow, so
	# the spine and the bay towers, which met end to end at z = -12 in the 36 m
	# yard, stopped meeting when both were multiplied: the bay towers went flush
	# to a wall 3.6 m further out and the spine only moved 1.8, which left a
	# 1.8 m band of clear z running the full width of the map behind the base.
	# `parkour_report` found it immediately — a 39 m ground line, wall to wall,
	# against a budget of 25.
	#
	# The contiguous run from the back wall to the east-west aisle is not a
	# coincidence of the old numbers; it is the thing that makes the back strip
	# three rooms instead of a lane, which is the first sentence of the bay's
	# comment above. So the spine is placed by its *contacts*: outer end on the
	# bay towers' inner ends (-15.6), which puts its centre on -12.6, and the
	# yard boxes below moved out to -9.6 to keep their own overlap with its
	# inner end. Every abutment the searched layout had, it still has.
	{"label": "spine", "at": Vector2(0.0, -12.6), "axis": "z", "tiers": 3, "paint": [3, 2, 4]},
	# The two climbable boxes on each side's approach, and the two you can run
	# *through*: these four (with their mirrors) are the map's open containers.
	# They are the ones hollowed out rather than four new boxes somewhere else
	# because their footprints came out of D-056's search and hollowing changes
	# no footprint at all — the yard a Gub walks round is the yard that was
	# searched for, to the centimetre. What changes is that the east-west aisle
	# at z = ±7.5 now has a door in it. See `_open_container_mesh` for why these
	# two and not the flank singles, which are the only thing standing between
	# the north wall and the south wall at x = ±11.5.
	# z is -9.6 rather than the scaled -9.0, so the spine's inner end still
	# overlaps these by 1.2 m — see the spine's comment.
	{"label": "yard west", "at": Vector2(-8.4, -9.6), "axis": "x", "tiers": 1, "paint": [2],
		"open": true},
	{"label": "yard east", "at": Vector2(8.4, -9.6), "axis": "x", "tiers": 1, "paint": [1],
		"open": true},
	# Against the side walls, closing the corners' diagonals. x re-derived rather
	# than scaled for the same flush reason the bay towers were: these lie along
	# the side wall and -15 * 1.2 is -18, which is 0.6 m off the steel at -21.6.
	{"label": "wall west", "at": Vector2(-18.6, -7.2), "axis": "x", "tiers": 3, "paint": [5, 4, 3]},
	{"label": "wall east", "at": Vector2(18.6, -7.2), "axis": "x", "tiers": 3, "paint": [4, 1, 6]},
	# The middle: four towers round a crossroads, with B standing in it. The
	# crossroads is 4.8 m across now rather than 3.6 — the biggest single gain of
	# the 1.2x pass, and the right place for it, because the middle is where four
	# lanes meet and three and a half metres of it was always tight.
	{"label": "centre west", "at": Vector2(-4.8, -3.6), "axis": "x", "tiers": 3, "paint": [6, 0, 1]},
	{"label": "centre east", "at": Vector2(4.8, -3.6), "axis": "x", "tiers": 3, "paint": [2, 3, 0]},
	# On the centre line, each placed once: the climbable boxes beside O and G.
	{"label": "flank west", "at": Vector2(-13.8, 0.0), "axis": "z", "tiers": 1, "paint": [0]},
	{"label": "flank east", "at": Vector2(13.8, 0.0), "axis": "z", "tiers": 1, "paint": [5]},
]

## Crates, north half, as (x, z). Same mirror rule as the boxes. Each is laid
## flush against something: a crate with a gap under a metre beside a box is a
## slot a Bog gets stuck in, and flush it is a step.
##
## **Not scaled — re-derived.** Every one of these touches a box, and a box did
## not change size, so the only honest way to move a crate is to put it back
## against the face of the thing it leans on after that thing moved. 1.2 x each
## of these leaves a 0.2-0.5 m slot, which is the exact failure the paragraph
## above forbids.
const CRATES: Array[Vector2] = [
	# The steps onto the yard boxes, from the base side. The yard boxes lie at
	# z = -9.6 and are 2.4 m across, so their base-side face is at -10.8 and a
	# 1.5 m crate flush against it is centred on -11.55. Along the box's length
	# the 1.0 m offset the old table had *did* scale, to 1.2.
	Vector2(-9.6, -11.55), Vector2(9.6, -11.55),
	# Low cover in the base bay, against the foot of the spine (z face -15.6).
	# The spine's abutment put this squarely between the bay towers now, which
	# is where the comment always said it was.
	Vector2(0.0, -16.35),
	# The steps onto the flank boxes, from the middle (x face -12.6).
	Vector2(-11.85, 0.0), Vector2(11.85, 0.0),
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
##
## Energy went from 5.0 to 7.5 and the sun went from 0.9 to 0.55 at the same
## time, which is the whole of the hour change in two numbers: the floods used
## to be a decoration under a daylight key and they are the key now.
## The 1.2x pass moved the corners out 3.6 m and left the masts the same height,
## because a mast is a real object and a taller one is a different map's mast.
## What had to follow is the *aim* and the *reach*: `MAST_AIM` is measured in
## from the corner, so aiming at the same fraction of the yard means
## 22.8 - 7.4 rather than 19.2 - 6.2; the head-to-pool distance goes 22.8 m to
## 25.6 m, so the range is 50 rather than 42; and the pool has to be 1.2 x wider
## at 1.12 x the distance, which is 36 degrees rather than 34. Energy went 7.5
## to 8.4 for the extra throw — a shade under the 1.2 the distance took, because
## `spot_attenuation` is 1.0 and the pools are wider as well as further.
const MAST_TOP := 13.5
const MAST_AIM := 15.4
const FLOOD_COLOUR := Color(1.0, 0.80, 0.52)
const FLOOD_ENERGY := 8.4
const FLOOD_RANGE := 50.0
const FLOOD_ANGLE := 36.0
## How hard each flood pushes into the volumetric fog, as a multiple of what it
## pushes into geometry. The island's torches run 2.0 for an omni.
##
## This number and `FLOOD_ANGLE` were found together, and the search is worth
## recording because the first several answers were wrong. At the 48-degree
## half-angle the map shipped with, the cone's upper edge is horizontal and its
## lower edge is 72 degrees below it: that is not a beam, it is light from a
## corner, and no amount of fog energy makes it read as a shaft — at 16 it
## produced a hard-edged wall of lit fog across half the frame and still no
## cone. Narrowing to 26 gave a real beam and left the corner pockets, which are
## spawn pads, at 1.5% of their pixels crushed. 34 degrees with 2.6 of fog
## energy is where both hold: pools with dark between them rather than an even
## wash, and nothing a player spawns in that reads as a hole.
const FLOOD_FOG := 2.6
## How far the lamps breathe, as a fraction of `FLOOD_ENERGY`, and how wide the
## glare billboard on each head is.
##
## Four per cent, against a torch's sixteen. A sodium lamp is not a fire: it
## does not flicker, it *hums*, and the honest visual of a hum is a ballast beat
## you notice only when you are looking straight at the lamp. Anything more and
## the yard's lighting starts pulsing, which on a map where a lit floor is cover
## information would be a gameplay change dressed as a mood.
const FLOOD_BREATH := 0.04
const FLOOD_GLARE := 2.6

## The two ages of lamp in the yard, assigned so that the map's **rotational**
## symmetry is kept. The yard mirrors across z = 0 for the teams, but the four
## corners are a 180-degree rotation of each other — north-west maps onto
## south-east, north-east onto south-west — so a pair of lamps on one diagonal
## may differ from the pair on the other without either team getting the better
## corner. The older pair is a hair pinker and a hair down on output, which is
## what a sodium lamp near the end of its life actually does, and it is the one
## thing on the map that tells you which diagonal you are standing on.
const FLOOD_FRESH := Color(1.0, 0.82, 0.55)
const FLOOD_TIRED := Color(1.0, 0.68, 0.40)
const FLOOD_TIRED_ENERGY := 0.88

# ------------------------------------------------------------ the lanterns ---

## **The thing the map is called after, and did not have.**
##
## Lantern Wharf shipped lit by four sodium floods and nothing else. That is a
## container terminal at night; it is not a lantern wharf, and standing in the
## middle of the yard there was no object anywhere in frame that the name
## referred to. The forest map has the opposite problem solved — Whisperbloom
## Hollow's torches are its key light, its warm colour, its sound source and its
## storytelling all at once (`torch.gd`) — and the festoons are this map's
## answer in its own language: not a fire on a post, but a working harbour's
## strings of bulbs slung between whatever is tall enough to take them.
##
## Three rules govern every string, and all three are about not touching the
## game:
##
##   height       a cable is anchored at `FESTOON_ANCHOR` on a tower top or a
##                wall top and sags by at most `FESTOON_SAG`, which puts its
##                lowest bulb at 6.2 m. The highest thing a Bog reaches is a
##                4.23 m dive off the ground (`parkour_report`), or 6.83 m off a
##                single's roof — so a player *can* pass through the lowest
##                strings, exactly as he can through the wall pipes the plant
##                already hangs at 3.2 m. None of it is collision and none of it
##                is cover, and the alternative — strings at 9 m — is festoon
##                lighting nobody can see the bulbs of.
##   anchors      towers and wall tops only. Both are `off_limits`, so a cable
##                end is never somewhere a player stands, and neither the anchor
##                posts nor the cables need a landing record.
##   symmetry     written for the north half and mirrored, like everything else.
##                Entries with both ends on z = 0 are placed once.
##
## `from` and `to` are plan positions; the height comes from `FESTOON_ANCHOR`.
const FESTOON_ANCHOR := 8.6
const FESTOON_SAG := 2.4
## Segments per string, and therefore bulbs per string less one. Ten is where a
## 20 m parabola stops looking like a chain of straight lines; it is also thirty
## triangles of cable, which at fourteen strings is nothing.
const FESTOON_SEGMENTS := 10
const FESTOON_BULB := 0.13
const FESTOON_WARM := Color(1.0, 0.72, 0.38)
const FESTOONS: Array[Dictionary] = [
	# Over the base, between the two bay towers: the one string every player
	# sees every time he spawns, and the reason a base reads as somewhere
	# somebody works rather than as a painted square.
	{"from": Vector2(-5.4, -18.6), "to": Vector2(5.4, -18.6)},
	# The two long runs down the base approach, wall to spine. These carry the
	# lamps — see `FESTOON_LIT`.
	{"from": Vector2(-21.6, -13.2), "to": Vector2(0.0, -12.6)},
	{"from": Vector2(21.6, -13.2), "to": Vector2(0.0, -12.6)},
	# Across each flank, from the side wall to the middle towers, so the two
	# long side lanes have something overhead as well as beside them.
	{"from": Vector2(-18.6, -7.2), "to": Vector2(-4.8, -3.6)},
	{"from": Vector2(18.6, -7.2), "to": Vector2(4.8, -3.6)},
	# Corner to corner over each corner pocket, which is where a spawning Bog
	# is looking when the match starts.
	{"from": Vector2(-21.6, -19.2), "to": Vector2(-14.4, -21.6)},
	{"from": Vector2(21.6, -19.2), "to": Vector2(14.4, -21.6)},
	# On the centre line, placed once: the long one, wall to wall over B. At
	# 43 m it is the single longest object on the map and the only thing that
	# ties the two halves together overhead.
	{"from": Vector2(-21.6, 0.0), "to": Vector2(21.6, 0.0)},
]
## Which festoons get a real light at their lowest point, by index into
## `FESTOONS`. **Three entries, five lights** — the base approaches and the
## flank runs are mirrored pairs, the centre run is not.
##
## Five shadowless omnis against four shadow-casting spots, and the ratio is the
## point. `torch.gd` states the discipline: a light is worth having only where
## there is unlit ground for it to own. The floods pool in the four corners and
## meet weakly in the middle, so these five sit in the three places the floods
## do not reach — over each base approach and over B — at a third of a flood's
## energy and a fifth of its reach, adding pools rather than raising the floor.
## None of them casts: a shadow map for a 2.4-energy bulb 6 m up would double
## the map's shadow cost to darken ground the floods have already lit.
const FESTOON_LIT: Array[int] = [1, 3, 7]
const LANTERN_ENERGY := 2.4
const LANTERN_RANGE := 11.0
const LANTERN_FOG := 1.4
## How hard a lantern breathes, against a flood's four per cent.
##
## Twelve, between the flood's hum and a torch's sixteen, and a different *kind*
## of movement: a festoon on a quay moves because the cable moves, so the sway
## is slow and the whole string dips together rather than each bulb flickering
## on its own. One sine per string, not one per bulb.
const LANTERN_BREATH := 0.12

# ----------------------------------------------------------- the quay gear ---

## The harbour's working gear, and where it is allowed to be.
##
## This is the list the wharf did not have and the forest did: `prop_scatter.gd`
## lays four layers of undergrowth on Whisperbloom Hollow and `landmarks.gd`
## puts a dozen one-off built things in it, and the yard had containers, drums
## and pallets. What it gets here is nets, tarps, floats, tyre fenders, rope
## coils, fish crates and mooring bitts.
##
## **Every one of them obeys D-084's rule and then one more.** D-084 says
## nothing between 0.3 m and 2.4 m anywhere a Bog can walk unless it is real
## collision. All of this is dressing, built under `super()`, so it lives in one
## of exactly three places:
##
##   on the floor    under 0.30 m, which is floor furniture you stride over —
##                   the rope coils, at 0.16 m.
##   on a wall face  within 0.35 m of the steel and above 2.6 m — the nets,
##                   tarps, floats and fenders. A wall face is not somewhere a
##                   player's capsule can be.
##   out of reach    on a wall top at 7.8 m, which `parkour_report` proves
##                   nothing reaches — the fish crates, the bitts and the gulls.
##
## Nothing is tucked into an aisle at chest height, because on this map that is
## the one lie that gets somebody killed.
const NET_TOP := 6.6
const NET_BOTTOM := 2.9
const FENDER_HEIGHT := 3.4
const FLOAT_HEIGHT := 4.6
## Where along each wall the gear hangs, as a distance along the side from its
## middle. Written once and used on all four sides, which is what keeps the
## dressing as symmetric as the geometry under it.
const GEAR_ALONG: PackedFloat32Array = [-19.0, -14.4, -9.8, -5.2, -0.6, 4.0, 8.6, 13.2, 17.8]
const ROPE_COIL_RADIUS := 0.46
const ROPE_COIL_HEIGHT := 0.16
## Rope coils, north half, mirrored. Each is laid at the foot of something that
## is already there, in the dead corner a Bog walks round rather than through.
const ROPE_COILS: Array[Vector2] = [
	Vector2(-7.4, -16.8), Vector2(7.4, -16.8),
	Vector2(-2.6, -8.4), Vector2(2.6, -8.4),
	Vector2(-12.6, -11.2), Vector2(12.6, -11.2),
	Vector2(-20.4, -12.4), Vector2(20.4, -12.4),
	Vector2(-16.4, -2.2), Vector2(16.4, -2.2),
]

## The stencils. A container yard's containers carry numbers, and the yard's had
## none — which at ten metres is the difference between a shipping container and
## a painted box. Sprayed on the steel three centimetres proud and **never below
## 2.6 m**: the bottom tier of every box on this map is the tier a player reads
## as cover, and nothing is allowed to decorate it in case a decoration ever
## reads as a doorway.
const STENCIL_SIZE := Vector2(1.5, 0.45)
const STENCIL_PROUD := 0.03
## The alphabet, five wide and seven tall, one string per row, top row first.
##
## Written out rather than generated. The first pass took the glyphs off a
## seeded integer — five random bits a row — on the theory that nobody reads a
## container number from the floor of a yard. What that actually produced was
## *noise*: 1.7 m of grey confetti on the side of every box, which the eye reads
## as damage rather than as paint, and which at fifteen metres is the only thing
## in frame with no structure in it. Real glyphs cost sixteen lines of table and
## read as a number at every distance the map has, because letters are mostly
## vertical strokes and vertical strokes survive a mipmap.
const STENCIL_GLYPHS: Array[PackedStringArray] = [
	["01110", "10001", "10011", "10101", "11001", "10001", "01110"],  # 0
	["00100", "01100", "00100", "00100", "00100", "00100", "01110"],  # 1
	["01110", "10001", "00001", "00010", "00100", "01000", "11111"],  # 2
	["11111", "00010", "00100", "00010", "00001", "10001", "01110"],  # 3
	["00010", "00110", "01010", "10010", "11111", "00010", "00010"],  # 4
	["11111", "10000", "11110", "00001", "00001", "10001", "01110"],  # 5
	["00110", "01000", "10000", "11110", "10001", "10001", "01110"],  # 6
	["11111", "00001", "00010", "00100", "01000", "01000", "01000"],  # 7
	["01110", "10001", "10001", "01110", "10001", "10001", "01110"],  # 8
	["01110", "10001", "10001", "01111", "00001", "00010", "01100"],  # 9
	["01110", "10001", "10001", "11111", "10001", "10001", "10001"],  # A
	["11110", "10001", "11110", "10001", "10001", "10001", "11110"],  # B
	["01110", "10001", "10000", "10000", "10000", "10001", "01110"],  # C
	["01110", "10001", "10000", "10111", "10001", "10001", "01111"],  # G
	["10001", "10001", "10001", "11111", "10001", "10001", "10001"],  # H
	["10001", "10001", "10001", "10001", "10001", "10001", "01110"],  # U
]

## The cranes standing outside the north and south walls. Scenery only.
const CRANE_Z := 32.4
const CRANE_SPAN := 16.0
const CRANE_HEIGHT := 18.0

# ------------------------------------------------------------------- the port ---

## The rest of the port, outside the walls. None of it is collision, none of it
## is in the sightline scan (which raycasts layer 1, and this is on no layer at
## all), and all of it is in `StaticMap.BACKDROP_GROUP` so `preview_map` keeps
## framing the 43.2 m yard rather than the 600 m harbour round it (D-057).
##
## The rule everything here obeys: **clear `1.45 + 0.294 * distance`, or do not
## bother**. A yard of beautifully detailed dockside at 6 m tall and 40 m out is
## six hundred triangles nobody will ever see over the wall.

## Stack rows, as distance out from the yard's own wall line. Three rows a side,
## east and west, so the yard reads as one block of a much bigger terminal.
const PORT_ROWS: PackedFloat32Array = [34.8, 42.6, 50.4]
## Where along z each row puts a stack, and how many containers high it is. The
## heights are written out rather than randomised because a broken skyline is
## the whole job of this table and a random one is broken in the wrong places —
## these rise away from the yard, so the near row never hides the far one.
const PORT_Z: PackedFloat32Array = [-26.4, -13.2, 0.0, 13.2, 26.4]
const PORT_TIERS: Array[int] = [5, 6, 4, 6, 5, 6, 5, 7, 5, 6, 4, 6, 5, 6, 7]

## The quay lamps: other people's floodlights, on masts too far away to light
## anything of ours. Points of sodium over the wall tops, and the cheapest depth
## cue on the map — an emissive head on a stick, no light attached, so eleven of
## them cost eleven quads and nothing else. `(x, z, height)`.
## `(x, z)` scaled with the yard; the heights are not, because a lamp post is a
## real object and the wall it has to clear did not get taller.
const QUAY_LAMPS: Array[Vector3] = [
	Vector3(-31.2, -37.2, 17.0), Vector3(31.2, -37.2, 19.0),
	Vector3(-31.2, 37.2, 19.0), Vector3(31.2, 37.2, 17.0),
	Vector3(-45.6, -31.2, 21.0), Vector3(45.6, 31.2, 21.0),
	Vector3(-56.4, 7.2, 20.0), Vector3(56.4, -7.2, 20.0),
	Vector3(-16.8, -56.4, 22.0), Vector3(19.2, 57.6, 22.0),
	Vector3(48.0, -52.8, 18.0),
]

## The moored coaster off the north quay and the transit shed off the south one.
## They are deliberately different shapes: this map is symmetric to a fault by
## design, and two identical silhouettes over the two walls would have taken
## away the one orientation cue a player gets from standing still.
## Both the standoff and the length scale: these two are curtains as much as
## they are shapes — they are what stops the sky reaching the wall top over each
## end — and a curtain that stays 46 m wide while the wall it hangs behind grows
## to 48 stops being one.
const SHIP_AT := Vector3(10.8, 0.0, -40.8)
const SHIP_LENGTH := 55.2
const SHED_AT := Vector3(-8.4, 0.0, 39.6)
const SHED_LENGTH := 69.6

## The harbour light, north-east over the water, and how long its lamp takes to
## come round. Eight seconds is a real character for a harbour-mouth light and
## it is also about as slow as a sweep can be before a player stops connecting
## the beam overhead with the tower it came from.
const BEACON_AT := Vector3(39.6, 0.0, -50.4)
const BEACON_HEIGHT := 25.0
const BEACON_PERIOD := 8.0

## How far out the water and the apron run. Past the fog, so the edge of the
## world is never an edge.
const HARBOUR_EDGE := 320.0
const WATER_Y := -1.4

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
## D-084 put the Factory Kit up the walls and flat on the floor and left the
## aisles empty, under a rule it stated in one line: nothing between 0.3 m and
## 2.4 m anywhere a Bog can walk, unless it is real. A forklift is 2.5 m to the
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
## assertion: **every flat top a Bog's capsule can find a floor on is a declared
## `Platform`.** A drum lid is 0.60 m across and declared; a guard rail is 0.08 m
## across, which is narrower than the sphere on the bottom of the capsule, so the
## contact there is an edge and a Bog slides off it. Nothing on any of these
## props is in between, and that is a thing the shapes were adjusted to make true
## rather than a thing they happened to be — see `FORKLIFT_DECK`.

## The forklift, as a table, north half, mirrored across z = 0 like everything
## else. `at` is the middle of the machine on the ground; it is built facing its
## own -x and `yaw` turns it. One per end, flush against the outboard end of the
## bay tower, in the loading bay the floor paint already marks (D-084).
##
## x scaled; z re-derived, because "flush against the outboard end of the bay
## tower" is a contact and not a coordinate. The tower's outboard end is at
## z = -15.6 now, and the machine sat 0.65 m clear of it before.
const FORKLIFTS: Array[Dictionary] = [
	{"at": Vector2(-5.40, -14.95), "yaw": 0.0},
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
## and the highest flat thing on the machine is a 0.08 m rail. A Bog's capsule is
## 0.38 m across and its underside is a sphere: on a face narrower than a few
## centimetres it meets an *edge*, the contact normal is not up, and it slides
## off. That is the line between the drum lids below (0.60 m across, declared,
## stood on all day) and these rails, and it is geometry rather than an opinion.
const FORKLIFT_DECK := Vector3(0.60, 1.20, 0.0)
const FORKLIFT_DECK_LANDING := 0.50

## Drums. `at` is the barrel's centre on the floor, `lying` puts it on its side
## along `along`, and `paint` indexes `PAINTS`. Upright is 0.90 m to a flat lid
## and on its side it is 0.60 m to the curve of the shell; **both are declared**,
## because a Bog can stand on either and a 0.15 m landing record is cheap next to
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
	# The spine is still 2.4 m across, so the 1.7 m standoff is unchanged; only
	# the spine's own z moved, and these moved with it.
	{"at": Vector2(-1.70, -12.00), "paint": 1},
	{"at": Vector2(-1.70, -11.28), "paint": 0},
	{"at": Vector2(-1.70, -13.00), "paint": 3, "lying": "z"},
	{"at": Vector2(1.70, -12.00), "paint": 3},
	{"at": Vector2(1.70, -11.28), "paint": 2},
	{"at": Vector2(1.70, -13.00), "paint": 0, "lying": "z"},
	# Against the outboard faces of the two wall towers, which are at z = -8.4
	# now; the half-metre standoff the comment below insists on is unchanged.
	{"at": Vector2(-19.80, -8.90), "paint": 0},
	{"at": Vector2(-18.94, -8.90), "paint": 5},
	{"at": Vector2(-17.64, -8.90), "paint": 1, "lying": "x"},
	{"at": Vector2(19.80, -8.90), "paint": 2},
	{"at": Vector2(18.94, -8.90), "paint": 0},
	{"at": Vector2(17.64, -8.90), "paint": 5, "lying": "x"},
	# Stacked off the yard crates, in the open aisle between them and the base.
	# The crates are at z = -11.55 and 1.5 m deep, so their base-side face is at
	# -12.3 and the half-metre standoff puts these on -12.8.
	{"at": Vector2(-9.60, -12.80), "paint": 4},
	{"at": Vector2(-10.32, -12.80), "paint": 0},
	{"at": Vector2(-11.50, -12.80), "paint": 2, "lying": "x"},
	{"at": Vector2(9.60, -12.80), "paint": 0},
	{"at": Vector2(10.32, -12.80), "paint": 3},
	{"at": Vector2(11.50, -12.80), "paint": 4, "lying": "x"},
]
## **None of these lean on a perimeter wall, and that is measured rather than
## stylistic.** A drum is a 0.9 m perch with its eyes at 2.35 m, which is over the
## crates and under the singles — harmless in the middle of the yard, where every
## one of these measures 13-18 m. Half a metre off the back wall it is something
## else: the sightline scan samples the ground on a 2 m grid whose outermost row
## is 1 m inside the steel, so a drum against the wall is a standing place
## *further out than the map has ever been measured at*, on the one axis where a
## 43.2 m yard has 43.2 m to give. The first draft put six of them there and took two
## existing crate tops from 25.0 m to 27.4 m. They came back inside instead.

## Pallets, stacked two high, and bundles of pipe stock lying on the concrete.
## Both are **28 cm** tall, which is under D-084's own 0.3 m line: they are floor
## furniture you stride over, not cover, so they get collision (a stack you walk
## through is as much of a lie as a crate you shoot through) and no landing
## record, because standing on one puts a Bog's eyes 28 cm up.
const PALLET := Vector3(1.20, 0.14, 0.80)
## Scaled outright: nothing here leans on anything, so 1.2 x is the answer.
const PALLETS: Array[Vector2] = [
	Vector2(-10.8, -6.84), Vector2(10.8, -6.84),
	Vector2(-17.4, -2.64), Vector2(17.4, -2.64),
	Vector2(-2.4, -12.24), Vector2(2.4, -12.24),
]
## Five tubes side by side, `PIPE_STOCK_LENGTH` long, laid along z.
const PIPE_STOCK_RADIUS := 0.14
const PIPE_STOCK_LENGTH := 4.0
## Tucked into the corner where the bay tower meets the back wall. z scaled;
## x re-derived off the tower's 1.2 m half-width, because the bundle is 2.68 m
## across and has to lie *beside* the tower rather than through it.
##
## It went through it before, by 64 cm, and had done since the works went in —
## the tower face was at x = -5.7 and the outermost of the five tubes reached
## -5.06. Nobody had looked at that corner from inside it. The 1.2x pass moved
## both and would have reproduced the same overlap exactly if x had been scaled,
## so it is measured now: 6.6 of tower face plus 1.34 of half-bundle is 7.94,
## and 7.95 leaves a centimetre so the two surfaces never argue about depth.
const PIPE_STOCK: Array[Vector2] = [
	Vector2(-7.95, -18.0), Vector2(7.95, -18.0),
]

# ------------------------------------------------------------ the plant ---

## Kenney's Factory Kit, bolted to the walls and painted on the floor (D-084).
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
## between 0.3 m and 2.4 m anywhere a Bog can walk.
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
## Rounded to whole metres after the 1.2x pass rather than scaled exactly, so
## the "one piece per metre" invariant above survives: 14 and 16 pieces.
const PIPE_RUNS: Array[Vector2] = [
	Vector2(-19.0, -5.0), Vector2(2.0, 18.0),
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
## pieces a Bog ever walks over, and every one of them is a decal in all but
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
## Dressing counts, for the same reason the box counts exist: the build log is
## the only place a headless run can say what it actually put in the yard, and
## "the nets are missing" is otherwise a thing you find out by looking.
var festoons: int = 0
var bulbs: int = 0
var gear: int = 0
var stencils: int = 0

var _mesh_cache: Dictionary = {}
var _paint_materials: Array[StandardMaterial3D] = []
var _wall_materials: Array[StandardMaterial3D] = []
var _crate_material: StandardMaterial3D
var _floor_material: ShaderMaterial
var _paint_line: StandardMaterial3D
var _steel: StandardMaterial3D
var _lamp: StandardMaterial3D
var _forklift_paint: StandardMaterial3D
var _timber: StandardMaterial3D
## The dressing's own materials. All of them are shared across every instance of
## the thing they paint — seven props, seven materials, no per-instance
## duplication anywhere — which is what makes the quay gear seven draw calls.
var _rope: StandardMaterial3D
var _canvas: StandardMaterial3D
var _net_material: StandardMaterial3D
var _float_material: StandardMaterial3D
var _rubber: StandardMaterial3D
var _bulb_material: StandardMaterial3D
var _stencil_materials: Array[StandardMaterial3D] = []

## What `_process` animates, and nothing else. Three small arrays rather than
## four `Node3D` subclasses: everything that moves on this map moves off one
## clock and one sine, and a class per lamp would be four scene-tree nodes
## paying `_process` each to do a multiply.
var _time: float = 0.0
var _floods: Array[SpotLight3D] = []
var _flood_base: PackedFloat32Array = PackedFloat32Array()
var _glare: Array[StandardMaterial3D] = []
## The festoon lamps, on the same clock as everything else. They are held as a
## flat array for the reason the floods are: the whole animation is one multiply
## per lamp per frame and a node class each would buy nothing but five more
## `_process` calls.
var _lanterns: Array[OmniLight3D] = []
var _beacon: Node3D


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
	var lamps := _build_floodlights(dressing)
	# The lanterns the map is named after, and the harbour's working gear. Both
	# go on after the floods because both are read against them: a festoon bulb
	# is warm *compared to* sodium, and a net hung on a wall face is only worth
	# hanging where a flood will rake it.
	var pools := _build_lanterns(dressing)
	_build_quay_gear(dressing)
	_build_stencils(dressing)
	# The plant goes on before the port does: it is bolted to the walls the port
	# stands behind, and reading the file in build order should read outward.
	_build_plant(dressing)
	_build_port(_group("Port"))
	WharfAmbience.build(_group("Air"), HALF, lamps[0], lamps[1], pools)

	print("%s: %d festoons, %d bulbs, %d lanterns, %d gear, %d stencils"
		% [name, festoons, bulbs, _lanterns.size(), gear, stencils])


## Everything on this map that moves, on one clock.
##
## Two things, and both of them are small on purpose. The lamps breathe at four
## per cent, which is a hum rather than a flicker (see `FLOOD_BREATH`); the
## harbour light comes round once every eight seconds, twenty-one metres over
## the yard floor, where it grazes the top tier of the walls and the fog above
## head height and never touches a player or the ground he is standing on.
##
## `_time` accumulates from this node's first frame, exactly as `torch.gd` does,
## which means two clients that loaded a second apart are a second out of phase
## on the sweep. That is the same bound the island's torches already live with
## and it is deliberate: neither is gameplay-relevant, and the alternative — a
## shared match clock threaded through every map's dressing — would be a
## networking dependency bought for a lighthouse.
func _process(delta: float) -> void:
	_time += delta
	for i: int in _floods.size():
		# Two incommensurate rates, so four lamps never beat together.
		var breath := 1.0 \
			+ FLOOD_BREATH * 0.62 * sin(_time * 0.83 + float(i) * 2.11) \
			+ FLOOD_BREATH * 0.38 * sin(_time * 3.71 + float(i) * 1.27)
		_floods[i].light_energy = _flood_base[i] * breath
		_glare[i].emission_energy_multiplier = 7.0 * breath
	# The festoons sway rather than flicker — one slow sine per string, at a
	# rate that shares no common factor with the floods' two, so the yard never
	# pulses as a whole. See `LANTERN_BREATH`.
	for i: int in _lanterns.size():
		_lanterns[i].light_energy = LANTERN_ENERGY * (1.0
			+ LANTERN_BREATH * sin(_time * 0.47 + float(i) * 1.83))
	if _beacon != null:
		_beacon.rotation.y = fmod(_time * TAU / BEACON_PERIOD, TAU)


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
## go. The short version is D-084's rule: on a map whose whole grammar is "this
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
## The lid of an upright drum is 0.30 m across and a Bog's capsule is 0.38 m: it
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
		# The bay between the two towers, which is 8.4 m across since the 1.2x
		# pass. The marking scaled with it and still sits inside the steel.
		var half := Vector2(3.6, 3.0)
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
## the yard.
##
## They were lights that happened to glow. They are sources now, which took five
## things and no new geometry to speak of:
##
##   fog energy    `light_volumetric_fog_energy`, so each spot lights the
##                 volumetric fog it passes through instead of only the floor it
##                 lands on. Largest effect per line on the whole map, and it
##                 only works because the fog is on (see `wharf_env.tres`).
##   shadows       **these used to cast none**, and the comment that said so was
##                 right about the cost and wrong about the trade. Four more
##                 shadow atlases is real, but this map is 1,714 triangles and
##                 43.2 m square — the four maps are the cheapest shadow casters
##                 in the game — and without them the volumetric beams pass
##                 straight through solid containers, which is the one artefact
##                 that makes a lit fog look like a bug. `shadow_opacity` is
##                 0.8 rather than 1.0: a dock at dusk has bounce off wet
##                 concrete that this renderer is not solving for, and 0.8 is
##                 where the lanes stopped crushing.
##   glare         an additive billboard on each head, over the environment's
##                 2.0 glow threshold so the bloom is the lamp's and nothing
##                 else's. A bare emissive box at 40 m is four pixels of orange;
##                 a 2.6 m soft dot behind it is a lamp you can see from the
##                 far wall.
##   a breath      four per cent of a hum, in `_process`.
##   two ages      one diagonal of lamps a little pinker and a little down, and
##                 the yard's only asymmetry (see `FLOOD_TIRED`).
##
## Returns `[heads, aims]` so `WharfAmbience` can put the moths in the beams
## without recomputing where the beams are.
func _build_floodlights(parent: Node3D) -> Array:
	var lights := _group("Lights", parent)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heads := SurfaceTool.new()
	heads.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corner := HALF + BOX_WIDTH * 0.5
	var wall_top := BOX_HEIGHT * float(WALL_TIERS)
	var head_points: Array[Vector3] = []
	var aim_points: Array[Vector3] = []
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
			head_points.append(head)
			aim_points.append(aim)

			# The tired diagonal is north-west and south-east, which is the same
			# pair under the map's 180-degree symmetry.
			var tired := sx * sz > 0.0
			var colour := FLOOD_TIRED if tired else FLOOD_FRESH
			var energy := FLOOD_ENERGY * (FLOOD_TIRED_ENERGY if tired else 1.0)

			var spot := SpotLight3D.new()
			spot.name = "Flood%s%s" % ["W" if sx < 0.0 else "E", "N" if sz < 0.0 else "S"]
			spot.light_color = colour
			spot.light_energy = energy
			spot.spot_range = FLOOD_RANGE
			spot.spot_angle = FLOOD_ANGLE
			spot.spot_attenuation = 1.0
			# Sodium on wet concrete is the map's whole look; a flood that does
			# not glint off the standing water is a flood that is not there.
			spot.light_specular = 1.0
			spot.light_volumetric_fog_energy = FLOOD_FOG
			spot.shadow_enabled = true
			spot.shadow_bias = 0.035
			spot.shadow_normal_bias = 1.4
			spot.shadow_opacity = 0.8
			lights.add_child(spot)
			spot.look_at_from_position(head + (aim - head).normalized() * 0.4, aim, Vector3.UP)
			_floods.append(spot)
			_flood_base.append(energy)

			# The glare. Its own node and its own material per lamp, because the
			# breath is per lamp and a shared material would beat in unison.
			var glow := StandardMaterial3D.new()
			glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			glow.billboard_keep_scale = true
			glow.albedo_texture = Torch.soft_dot()
			glow.albedo_color = colour
			glow.emission_enabled = true
			glow.emission = colour
			glow.emission_energy_multiplier = 7.0
			glow.disable_receive_shadows = true
			# No depth write: the glare is light in the air in front of the
			# lamp, not a disc hanging off it.
			glow.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			var quad := QuadMesh.new()
			quad.size = Vector2(FLOOD_GLARE, FLOOD_GLARE)
			quad.material = glow
			var flare := MeshInstance3D.new()
			flare.name = "%sGlare" % spot.name
			flare.mesh = quad
			flare.position = head + (aim - head).normalized() * 0.5
			flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(flare)
			_glare.append(glow)

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
	return [head_points, aim_points]


# ------------------------------------------------------------ the lanterns ---

## The festoons, the bulbs on them and the five lamps that hang off them.
##
## Cost, because on a map this small the budget is the design: one cable mesh
## (fourteen strings of ten segments, about nine hundred triangles of thin
## beam), one `MultiMesh` of a hundred and fifty-four bulbs sharing one unshaded
## emissive material, one anchor-post mesh, and five `OmniLight3D` that cast
## nothing. Three draw calls and five clustered lights for the whole of the
## thing the map is named after.
##
## Returns the lit sag points so `WharfAmbience` can hang its midges in them
## without recomputing a parabola — the same contract `_build_floodlights` has
## with the moths.
func _build_lanterns(parent: Node3D) -> Array[Vector3]:
	var cables := SurfaceTool.new()
	cables.begin(Mesh.PRIMITIVE_TRIANGLES)
	var posts := SurfaceTool.new()
	posts.begin(Mesh.PRIMITIVE_TRIANGLES)
	var beads: Array[Transform3D] = []
	var pools: Array[Vector3] = []
	var lights := _group("Lanterns", parent)
	var anchored: Dictionary = {}

	for i: int in FESTOONS.size():
		var entry: Dictionary = FESTOONS[i]
		var a: Vector2 = entry["from"]
		var b: Vector2 = entry["to"]
		# A run with both ends on the centre line is placed once; anything else
		# is placed twice, like every other table on this map.
		var runs: Array = [[a, b]]
		if absf(a.y) > 0.001 or absf(b.y) > 0.001:
			runs.append([Vector2(a.x, -a.y), Vector2(b.x, -b.y)])
		for run: Array in runs:
			var sag := _festoon(cables, beads, run[0], run[1])
			festoons += 1
			for end: Vector2 in run:
				# One post per anchor, and only one: five strings meet on the
				# spine tops and a post per string would be a bundle of sticks.
				var key := "%.1f,%.1f" % [end.x, end.y]
				if not anchored.has(key):
					anchored[key] = true
					_add_box(posts, Transform3D.IDENTITY,
						Vector3(end.x, FESTOON_ANCHOR - 0.4, end.y), Vector3(0.12, 0.8, 0.12))
			if FESTOON_LIT.has(i):
				pools.append(sag)
				_lantern_lamp(lights, sag)

	var cable := MeshInstance3D.new()
	cable.name = "FestoonCables"
	cable.mesh = cables.commit()
	cable.material_override = _rope
	cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(cable)

	var stems := MeshInstance3D.new()
	stems.name = "FestoonPosts"
	stems.mesh = posts.commit()
	stems.material_override = _steel
	stems.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(stems)

	_scatter(parent, "FestoonBulbs", _bulb_mesh(), _bulb_material, beads)
	bulbs = beads.size()
	return pools


## One string: the cable as `FESTOON_SEGMENTS` beams along a parabola, a bulb at
## every joint, and the lowest point handed back.
##
## A parabola rather than a real catenary. Over a span this short the two curves
## differ by centimetres, a catenary needs a solve per string to find its
## parameter, and the thing a player reads is the *sag*, which is a number this
## way and a consequence the other way.
func _festoon(cables: SurfaceTool, bulbs: Array[Transform3D], a: Vector2, b: Vector2) -> Vector3:
	var from := Vector3(a.x, FESTOON_ANCHOR, a.y)
	var to := Vector3(b.x, FESTOON_ANCHOR, b.y)
	# Longer strings sag further, up to the cap: a 43 m run with a 10 m run's
	# sag is a washing line, and the same sag on a 6 m run is a skipping rope.
	var drop := minf(FESTOON_SAG, FESTOON_SAG * from.distance_to(to) / 18.0)
	var previous := from
	for k: int in FESTOON_SEGMENTS:
		var t := float(k + 1) / float(FESTOON_SEGMENTS)
		var point := from.lerp(to, t)
		# 4 * t * (1 - t) is 1 at the middle and 0 at both ends.
		point.y -= drop * 4.0 * t * (1.0 - t)
		_add_beam(cables, Transform3D.IDENTITY, previous, point, 0.035)
		if k < FESTOON_SEGMENTS - 1:
			bulbs.append(Transform3D(Basis.IDENTITY, point + Vector3.DOWN * FESTOON_BULB))
		previous = point
	return from.lerp(to, 0.5) - Vector3.UP * drop


## One lamp under one string, and its entry in the breath.
func _lantern_lamp(parent: Node3D, at: Vector3) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "Lantern%d" % _lanterns.size()
	lamp.position = at + Vector3.DOWN * 0.2
	lamp.light_color = FESTOON_WARM
	lamp.light_energy = LANTERN_ENERGY
	lamp.omni_range = LANTERN_RANGE
	# Squared falloff, which is what an unshaded bulb in the open actually does
	# and what keeps the pool small enough to have an edge.
	lamp.omni_attenuation = 1.6
	lamp.light_volumetric_fog_energy = LANTERN_FOG
	lamp.light_specular = 0.7
	lamp.shadow_enabled = false
	parent.add_child(lamp)
	_lanterns.append(lamp)


# ----------------------------------------------------------- the quay gear ---

## Nets, tarps, floats, fenders, rope coils, fish crates and bitts.
##
## Read the `NET_TOP` comment for the rule all of it obeys. What is worth saying
## here is the shape of the build: everything is gathered into per-model arrays
## of transforms and handed to `_scatter`, so seven kinds of prop laid two
## hundred and forty times cost seven draw calls — the same trick `_bolted` uses
## for the Factory Kit, with this map's own meshes instead of a kit's.
func _build_quay_gear(parent: Node3D) -> void:
	var quay := _group("QuayGear", parent)
	var nets: Array[Transform3D] = []
	var tarps: Array[Transform3D] = []
	var floats: Array[Transform3D] = []
	var fenders: Array[Transform3D] = []
	var crates: Array[Transform3D] = []
	var bitts: Array[Transform3D] = []
	var birds: Array[Transform3D] = []
	var coils: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = PLANT_SEED ^ 0x5EA

	var wall_top := BOX_HEIGHT * float(WALL_TIERS)
	for side: int in 4:
		var axes := _side_axes(side)
		var inward: Vector2 = axes[0]
		var yaw := atan2(inward.x, inward.y)
		for k: int in GEAR_ALONG.size():
			var along := GEAR_ALONG[k]
			# The pieces are dealt out by (side + k) so no two neighbours on a
			# wall are the same thing and the four sides are not four copies.
			var deal := (side * 2 + k) % 4
			var face := _on_wall(side, along, 0.0)
			if deal == 0:
				nets.append(Transform3D(Basis(Vector3.UP, yaw).scaled(
					Vector3(rng.randf_range(0.85, 1.25), 1.0, 1.0)),
					Vector3(face.x, (NET_TOP + NET_BOTTOM) * 0.5, face.y)
						+ Vector3(inward.x, 0.0, inward.y) * 0.16))
			elif deal == 1:
				for m: int in 3:
					var at := _on_wall(side, along + (float(m) - 1.0) * 0.9, 0.0)
					fenders.append(Transform3D(Basis(Vector3.UP, yaw),
						Vector3(at.x, FENDER_HEIGHT - rng.randf_range(0.0, 0.5), at.y)
							+ Vector3(inward.x, 0.0, inward.y) * 0.3))
			elif deal == 2:
				for m: int in 4:
					var at := _on_wall(side, along + (float(m) - 1.5) * 0.66, 0.0)
					floats.append(Transform3D(Basis(Vector3.UP, yaw).scaled(
						Vector3.ONE * rng.randf_range(0.75, 1.15)),
						Vector3(at.x, FLOAT_HEIGHT - rng.randf_range(0.0, 0.7), at.y)
							+ Vector3(inward.x, 0.0, inward.y) * 0.28))
			else:
				tarps.append(Transform3D(Basis(Vector3.UP, yaw),
					Vector3(face.x, NET_BOTTOM + 1.7, face.y)
						+ Vector3(inward.x, 0.0, inward.y) * 0.14))

			# On the wall top, out of every jump in the game: a stack of fish
			# crates, a mooring bitt, or a gull sitting where the light is.
			var top := _on_wall(side, along + 2.4, -BOX_WIDTH * 0.25)
			var perch := (side + k) % 3
			if perch == 0:
				for m: int in rng.randi_range(2, 4):
					crates.append(Transform3D(
						Basis(Vector3.UP, yaw + rng.randf_range(-0.3, 0.3)),
						Vector3(top.x + rng.randf_range(-0.2, 0.2),
							wall_top + 0.22 + float(m) * 0.44,
							top.y + rng.randf_range(-0.2, 0.2))))
			elif perch == 1:
				bitts.append(Transform3D(Basis(Vector3.UP, yaw),
					Vector3(top.x, wall_top, top.y)))
			else:
				birds.append(Transform3D(Basis(Vector3.UP,
					yaw + rng.randf_range(-0.6, 0.6)),
					Vector3(top.x, wall_top + 0.12, top.y)))

	for spot: Vector2 in ROPE_COILS:
		for at: Vector2 in mirrored(spot):
			coils.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)),
				Vector3(at.x, 0.0, at.y)))

	_scatter(quay, "Nets", _net_mesh(), _net_material, nets)
	_scatter(quay, "Tarps", _tarp_mesh(), _canvas, tarps)
	_scatter(quay, "Floats", _float_mesh(), _float_material, floats)
	_scatter(quay, "Fenders", _fender_mesh(), _rubber, fenders)
	_scatter(quay, "FishCrates", _fish_crate_mesh(), _crate_material, crates, true)
	_scatter(quay, "Bitts", _bitt_mesh(), _steel, bitts, true)
	_scatter(quay, "Gulls", _gull_mesh(), _canvas, birds, true)
	_scatter(quay, "RopeCoils", _rope_coil_mesh(), _rope, coils)
	gear = nets.size() + tarps.size() + floats.size() + fenders.size() 		+ crates.size() + bitts.size() + birds.size() + coils.size()


# ------------------------------------------------------------- the stencils ---

## Sprayed marks on the steel: a box number on every yard box above the first
## tier, and a scatter of the same on the perimeter.
##
## Four materials rather than four meshes. Every stencil is the same quad; the
## glyphs are four generated textures and the material picks which one, so the
## whole set is four `MultiMesh` nodes over one 1.7 x 0.9 m plane.
func _build_stencils(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = PLANT_SEED ^ 0x57E4
	# Four typed lists rather than `Array[Array] = [[], [], [], []]`, which
	# builds four *untyped* inner arrays and hands `_scatter` something its
	# `Array[Transform3D]` parameter refuses at runtime.
	var batches: Array = []
	for i: int in 4:
		var list: Array[Transform3D] = []
		batches.append(list)

	for entry: Dictionary in BOXES:
		var tiers := int(entry["tiers"])
		if tiers < 2:
			# A single is 2.6 m to its roof and its whole face is the tier a
			# player reads as cover. Nothing is sprayed on it.
			continue
		var axis := String(entry["axis"])
		for at: Vector2 in mirrored(entry["at"]):
			for tier: int in range(1, tiers):
				# The long face, on whichever side of the box faces out of the
				# yard's middle, so the mark is on the wall of the aisle rather
				# than on the side a player has his back to.
				var out := 1.0 if (at.x if axis == "z" else at.y) >= 0.0 else -1.0
				var normal := Vector2(out, 0.0) if axis == "z" else Vector2(0.0, out)
				var yaw := atan2(normal.x, normal.y)
				var offset := Vector2(normal.x, normal.y) * (BOX_WIDTH * 0.5 + STENCIL_PROUD)
				var spot := Vector3(at.x + offset.x,
					BOX_HEIGHT * float(tier) + BOX_HEIGHT * 0.55, at.y + offset.y)
				batches[rng.randi() % 4].append(Transform3D(Basis(Vector3.UP, yaw), spot))

	# A dozen more round the perimeter, on the second and third tiers only, so
	# the wall reads as stacked cargo rather than as a fence.
	for side: int in 4:
		var axes := _side_axes(side)
		var yaw := atan2(axes[0].x, axes[0].y)
		for k: int in 5:
			var along := lerpf(-HALF + 4.0, HALF - 4.0, float(k) / 4.0)
			var at := _on_wall(side, along, -STENCIL_PROUD)
			var tier := 1 + (side + k) % 2
			batches[(side + k) % 4].append(Transform3D(Basis(Vector3.UP, yaw),
				Vector3(at.x, BOX_HEIGHT * float(tier) + BOX_HEIGHT * 0.55, at.y)))

	var marks := _group("Stencils", parent)
	for i: int in 4:
		_scatter(marks, "Stencil%d" % i, _stencil_mesh(), _stencil_materials[i], batches[i])
		stencils += (batches[i] as Array).size()


## One `MultiMeshInstance3D` for a mesh this file made itself.
##
## `_bolted` does this for the Factory Kit and takes a model name; this takes a
## mesh, because everything the quay gear and the lanterns are made of is built
## here rather than loaded. Same two reasons for using a multimesh at all: one
## draw call for two hundred props, and `StaticMap`'s collision sweep collects
## `MeshInstance3D` and therefore cannot pick any of this up by accident.
func _scatter(parent: Node3D, named: String, mesh: Mesh, material: Material,
		transforms: Array[Transform3D], shadows: bool = false) -> void:
	if transforms.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	var bounds := AABB()
	for i: int in transforms.size():
		multi.set_instance_transform(i, transforms[i])
		var box := transforms[i] * mesh.get_aabb()
		bounds = box if i == 0 else bounds.merge(box)
	var node := MultiMeshInstance3D.new()
	node.name = named
	node.multimesh = multi
	node.material_override = material
	node.custom_aabb = bounds
	# Almost none of it casts, for the plant's reason: the sun is 8 degrees up,
	# so a net on a wall face throws a shadow the length of the yard. What does
	# cast is what stands on the wall tops and is therefore part of the skyline.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)



# ------------------------------------------------------------------- the port ---

## Everything outside the walls: the rest of the terminal, the water, a ship, a
## shed, five more gantries and the harbour light.
##
## A 43.2 m box that ends at its own wall is a room. What makes it a wharf is that
## there is more of it over the top of the wall — and, crucially, that the more
## of it is *lit*, because at this hour the only thing that carries across a
## hundred metres of sea air is a lamp. So the port is mostly two things: dark
## shapes that break the skyline, and eleven points of sodium behind them.
##
## The whole of it is three meshes and two planes — one dark-steel surface for
## every silhouette, one emissive surface for every distant lamp head, one
## water quad, one apron quad, one beacon — so a hundred and forty pieces of
## dockside cost five draw calls. All of it non-colliding (it is built after
## `super()`) and all of it in `BACKDROP_GROUP`.
func _build_port(parent: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lit := SurfaceTool.new()
	lit.begin(Mesh.PRIMITIVE_TRIANGLES)

	_port_stacks(st)
	_port_gantries(st)
	_port_ship(st, lit)
	_port_shed(st)
	_port_lamps(st, lit)
	_port_craft(st, lit)
	_port_town(st, lit)
	_port_water(parent)

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.30, 0.31, 0.36)
	steel.vertex_color_use_as_albedo = true
	steel.roughness = 0.72
	steel.metallic = 0.25
	steel.cull_mode = BaseMaterial3D.CULL_BACK
	var shapes := MeshInstance3D.new()
	shapes.name = "PortShapes"
	shapes.mesh = st.commit()
	shapes.material_override = steel
	# Nothing out here casts. The sun is 8 degrees up and a 42 m stack would
	# throw a shadow across the whole yard from outside it, which is a lighting
	# decision made by scenery.
	shapes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shapes.add_to_group(BACKDROP_GROUP)
	parent.add_child(shapes)

	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = true
	glow.albedo_color = Color(1.0, 0.74, 0.42)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.74, 0.42)
	glow.emission_energy_multiplier = 5.0
	var beads := MeshInstance3D.new()
	beads.name = "PortLamps"
	beads.mesh = lit.commit()
	beads.material_override = glow
	beads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beads.add_to_group(BACKDROP_GROUP)
	parent.add_child(beads)

	_port_beacon(parent)


## The small craft lying along the two quays: four fishing boats, each a hull,
## a wheelhouse, a mast and a light at the top of it.
##
## They are the one thing out here that is *not* enormous, and they are here for
## the scale rather than the silhouette. Everything else in `_build_port` obeys
## the "clear 1.45 + 0.294 * distance" rule by being twenty metres tall, which
## means the whole backdrop is one size — and a skyline in which every object is
## huge has no size in it at all. A 9 m boat with a 12 m mast is just tall
## enough for its masthead light to clear the wall from the middle of the yard,
## so what a player sees is a point of light low down among the big shapes, and
## that point is what tells him the big shapes are far away.
##
## They are moored in two pairs, one at each end, and they are four different
## lengths on purpose: a rank of identical hulls is a car park.
func _port_craft(st: SurfaceTool, lit: SurfaceTool) -> void:
	var hull := Color(0.16, 0.18, 0.22)
	var house := Color(0.54, 0.52, 0.47)
	var berths := [
		Vector3(-26.0, 0.0, -28.0), Vector3(-15.0, 0.0, -30.5),
		Vector3(24.0, 0.0, 29.0), Vector3(13.0, 0.0, 31.5),
	]
	for i: int in berths.size():
		var at: Vector3 = berths[i]
		var frame := Transform3D(Basis(Vector3.UP, 0.10 * float(i) - 0.15), at)
		var length := 9.0 + 1.6 * float(i % 3)
		_add_box(st, frame, Vector3(0.0, -0.3, 0.0), Vector3(length, 2.6, 3.2), hull)
		# The gunwale, a paler band, which is what stops a hull at this size
		# from reading as a lying-down crate.
		_add_box(st, frame, Vector3(0.0, 1.1, 0.0), Vector3(length - 0.6, 0.4, 3.5),
			Color(0.46, 0.40, 0.30))
		_add_box(st, frame, Vector3(-length * 0.22, 2.4, 0.0), Vector3(2.8, 2.4, 2.6), house)
		var mast := 11.0 + 1.5 * float(i % 2)
		_add_box(st, frame, Vector3(length * 0.1, mast * 0.5 + 1.0, 0.0),
			Vector3(0.28, mast, 0.28), house)
		# Two booms, angled down from the mast head, which is the shape that
		# says "fishing boat" at sixty metres and costs twelve triangles.
		for side: float in [-1.0, 1.0]:
			_add_beam(st, frame, Vector3(length * 0.1, mast, 0.0),
				Vector3(length * 0.1 - 1.0, 3.2, side * 4.2), 0.16, house)
		_add_box(lit, frame, Vector3(length * 0.1, mast + 0.6, 0.0),
			Vector3(0.5, 0.5, 0.5), Color(1.0, 0.80, 0.50))


## The far shore: a headland of dark blocks with windows burning in it, 150 m
## out and never any closer.
##
## This is the map's horizon, and it is the last layer the yard was missing. The
## port stops at about 80 m, and past that the fog and the sky met on nothing —
## which is fine at dusk and much better with a town in it, because a light two
## hundred metres away over water is the single cheapest thing that makes a
## harbour feel like it has somewhere to go.
##
## Everything here is a box of a couple of hundred triangles in total, in the
## two surfaces the port already commits, and it is beyond the fog's far edge so
## it is always seen through the full depth of it.
func _port_town(st: SurfaceTool, lit: SurfaceTool) -> void:
	var stone := Color(0.13, 0.13, 0.17)
	var window := Color(1.0, 0.78, 0.44)
	var rng := RandomNumberGenerator.new()
	rng.seed = PLANT_SEED ^ 0x7014
	for side: float in [-1.0, 1.0]:
		var reach := 150.0 * side
		# A ridge behind the town, so the town has something to stand against.
		_add_box(st, Transform3D(Basis(Vector3.UP, 0.2 * side), Vector3(30.0 * side, 0.0, reach * 1.35)),
			Vector3(0.0, 16.0, 0.0), Vector3(420.0, 32.0, 40.0), Color(0.09, 0.09, 0.12))
		for i: int in 16:
			var along := lerpf(-170.0, 170.0, float(i) / 15.0) + rng.randf_range(-8.0, 8.0)
			var tall := rng.randf_range(9.0, 26.0)
			var wide := rng.randf_range(10.0, 22.0)
			var at := Vector3(along, tall * 0.5, reach + rng.randf_range(-12.0, 12.0))
			_add_box(st, Transform3D.IDENTITY, at, Vector3(wide, tall, 14.0), stone)
			# Two or three lit windows per block, as small emissive plates on
			# the face that looks at the yard.
			for k: int in rng.randi_range(2, 3):
				var height := rng.randf_range(0.25, 0.8) * tall
				_add_box(lit, Transform3D.IDENTITY,
					Vector3(at.x + rng.randf_range(-wide * 0.3, wide * 0.3), height,
						at.z - 7.2 * side),
					Vector3(2.2, 1.6, 0.4), window)


## Three rows of stacks either side, rising away from the yard.
func _port_stacks(st: SurfaceTool) -> void:
	var shades := [Color(0.34, 0.20, 0.19), Color(0.18, 0.22, 0.32),
		Color(0.32, 0.29, 0.20), Color(0.20, 0.28, 0.24), Color(0.30, 0.26, 0.25)]
	var n := 0
	for sx: float in [-1.0, 1.0]:
		for row: int in PORT_ROWS.size():
			for i: int in PORT_Z.size():
				var tiers: int = PORT_TIERS[n % PORT_TIERS.size()]
				n += 1
				var height := BOX_HEIGHT * float(tiers)
				var at := Vector3(sx * PORT_ROWS[row], height * 0.5, PORT_Z[i])
				# Length on z, so a row reads as a row rather than as a fence.
				_add_box(st, Transform3D.IDENTITY, at, Vector3(4.8, height, 10.6),
					shades[n % shades.size()].darkened(0.10 * float(row)))


## Five more gantries, further out and lower in the frame than the two the map
## already had, so the two near cranes stop being the only things in the sky.
func _port_gantries(st: SurfaceTool) -> void:
	var places := [
		Vector3(-28.8, 0.0, -60.0), Vector3(26.4, 0.0, -74.4),
		Vector3(-36.0, 0.0, 62.4), Vector3(16.8, 0.0, 79.2),
		Vector3(67.2, 0.0, 21.6),
	]
	var colour := Color(0.26, 0.24, 0.26)
	for i: int in places.size():
		var at: Vector3 = places[i]
		var yaw := 0.0 if absf(at.z) > absf(at.x) else PI * 0.5
		var frame := Transform3D(Basis(Vector3.UP, yaw), at)
		var tall := 24.0 + 3.0 * float(i % 3)
		var span := 11.0
		for x: float in [-span, span]:
			_add_box(st, frame, Vector3(x, tall * 0.5, 0.0), Vector3(1.1, tall, 1.1), colour)
		_add_box(st, frame, Vector3(0.0, tall, 0.0), Vector3(span * 2.0, 1.3, 1.6), colour)
		# The boom, out over the water away from us and angled up, which is how
		# a crane parks.
		_add_beam(st, frame, Vector3(0.0, tall + 1.0, 0.0),
			Vector3(0.0, tall + 9.0, -19.0), 1.0, colour)
		_add_box(st, frame, Vector3(0.0, tall + 5.0, 0.0), Vector3(1.0, 9.0, 1.0), colour)


## The coaster lying at the north quay: hull, deckhouse, funnel, two masts with
## their steaming lights burning. 34 m out from the middle of the yard, which is
## the closest anything can be and still be a ship rather than a wall.
func _port_ship(st: SurfaceTool, lit: SurfaceTool) -> void:
	var frame := Transform3D(Basis(Vector3.UP, 0.04), SHIP_AT)
	var hull := Color(0.20, 0.13, 0.12)
	var house := Color(0.62, 0.60, 0.56)
	var half := SHIP_LENGTH * 0.5
	_add_box(st, frame, Vector3(0.0, 2.6, 0.0), Vector3(SHIP_LENGTH, 8.0, 8.4), hull)
	# The boot topping: a paler band at the waterline, which is the one detail
	# that stops a hull reading as a shipping container lying down.
	_add_box(st, frame, Vector3(0.0, -0.6, 0.0), Vector3(SHIP_LENGTH - 1.0, 1.6, 8.8),
		Color(0.34, 0.28, 0.20))
	# Bow and stern, cut down so the profile is not a brick.
	_add_box(st, frame, Vector3(half - 1.0, 4.4, 0.0), Vector3(6.0, 4.0, 5.6), hull)
	# The accommodation block, aft, and the funnel over it.
	_add_box(st, frame, Vector3(-half + 7.0, 10.0, 0.0), Vector3(9.0, 11.0, 8.0), house)
	_add_box(st, frame, Vector3(-half + 5.0, 17.5, 0.0), Vector3(4.2, 5.0, 5.2),
		Color(0.30, 0.16, 0.13))
	for m: float in [-1.0, 1.0]:
		var x := m * (half - 9.0)
		_add_box(st, frame, Vector3(x, 12.0, 0.0), Vector3(0.6, 24.0, 0.6), house)
		_add_box(st, frame, Vector3(x, 15.0, 0.0), Vector3(5.0, 0.4, 0.4), house)
		# The masthead light itself.
		_add_box(lit, frame, Vector3(x, 24.2, 0.0), Vector3(0.7, 0.7, 0.7),
			Color(1.0, 0.36, 0.26))
	# Four deck lights along the rail, which is what a ship working cargo at
	# dusk actually looks like from a quay.
	for i: int in 4:
		var x := lerpf(-half + 14.0, half - 6.0, float(i) / 3.0)
		_add_box(st, frame, Vector3(x, 6.0, 4.4), Vector3(0.3, 7.0, 0.3), house)
		_add_box(lit, frame, Vector3(x, 9.4, 4.4), Vector3(0.9, 0.5, 0.9),
			Color(1.0, 0.86, 0.62))


## The transit shed at the south quay: a long ridged roof and two silos.
## Deliberately a different shape from the ship — this map is symmetric to a
## fault, and the two things over the two end walls are the only way a player
## standing still can tell which half he is in.
func _port_shed(st: SurfaceTool) -> void:
	var frame := Transform3D(Basis(Vector3.UP, -0.03), SHED_AT)
	var wall := Color(0.30, 0.30, 0.33)
	var roof := Color(0.22, 0.23, 0.27)
	_add_box(st, frame, Vector3(0.0, 6.0, 0.0), Vector3(SHED_LENGTH, 12.0, 16.0), wall)
	# The ridge, as two slabs leaning together.
	for side: float in [-1.0, 1.0]:
		var lean := Transform3D(Basis(Vector3.BACK, side * 0.38), Vector3.ZERO)
		_add_box(st, frame * lean, Vector3(0.0, 13.6, side * 4.3),
			Vector3(SHED_LENGTH + 1.0, 0.6, 9.4), roof)
	# Ventilators along the ridge, which is the silhouette detail that reads at
	# thirty metres when nothing else on a shed does.
	for i: int in 7:
		var x := lerpf(-SHED_LENGTH * 0.42, SHED_LENGTH * 0.42, float(i) / 6.0)
		_add_box(st, frame, Vector3(x, 16.4, 0.0), Vector3(1.4, 1.4, 1.4), roof)
	for side: float in [-1.0, 1.0]:
		var at := Vector3(SHED_LENGTH * 0.5 + 7.0, 9.0, side * 6.5)
		_add_box(st, frame, at, Vector3(8.4, 18.0, 8.4), Color(0.35, 0.34, 0.31))
		_add_box(st, frame, at + Vector3(0.0, 9.6, 0.0), Vector3(6.0, 1.6, 6.0), roof)


## The quay lamps. A mast and an emissive head, eleven times, no light attached
## to any of them — they are 26 to 50 m outside the yard and a real light at
## that range would spend a shadow atlas and a froxel pass to add nothing a
## player can see by.
func _port_lamps(st: SurfaceTool, lit: SurfaceTool) -> void:
	for i: int in QUAY_LAMPS.size():
		var lamp: Vector3 = QUAY_LAMPS[i]
		var at := Vector3(lamp.x, 0.0, lamp.y)
		var top: float = lamp.z
		_add_box(st, Transform3D.IDENTITY, at + Vector3.UP * top * 0.5,
			Vector3(0.36, top, 0.36), Color(0.26, 0.26, 0.29))
		_add_box(st, Transform3D.IDENTITY, at + Vector3(0.0, top, 0.0),
			Vector3(2.6, 0.3, 0.5), Color(0.26, 0.26, 0.29))
		for side: float in [-0.9, 0.9]:
			_add_box(lit, Transform3D.IDENTITY, at + Vector3(side, top - 0.35, 0.0),
				Vector3(0.75, 0.32, 0.6), Color(1.0, 0.72, 0.40))


## The water either side of the mole, and the apron under everything else.
##
## Neither is visible from the yard floor — a 7.8 m wall sees to nothing lower
## than 12 m at thirty metres out — and both are here anyway, for two reasons.
## The apron is what the port's own shapes stand on, so the stacks do not float
## over the sky's ground colour in the top view the smoke test renders. The
## water is the environment's reflection probe source and the sky's ground
## term: it is 0.08 roughness, so from anywhere above the wall it is a mirror of
## the dusk, and that is what tints the underside of the fog blue instead of
## brown.
func _port_water(parent: Node3D) -> void:
	var apron := MeshInstance3D.new()
	apron.name = "Apron"
	apron.mesh = _quad(Vector2(HARBOUR_EDGE, HARBOUR_EDGE) * 2.0, 8.0)
	apron.position = Vector3(0.0, -0.02, 0.0)
	var tarmac := StandardMaterial3D.new()
	tarmac.albedo_color = Color(0.10, 0.10, 0.12)
	tarmac.roughness = 0.85
	apron.material_override = tarmac
	apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	apron.add_to_group(BACKDROP_GROUP)
	parent.add_child(apron)

	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.045, 0.06, 0.09)
	water.roughness = 0.08
	water.metallic = 0.1
	for side: float in [-1.0, 1.0]:
		var sea := MeshInstance3D.new()
		sea.name = "Water%s" % ["N" if side < 0.0 else "S"]
		sea.mesh = _quad(Vector2(HARBOUR_EDGE * 2.0, HARBOUR_EDGE - 24.0), 20.0)
		sea.position = Vector3(0.0, WATER_Y, side * (24.0 + (HARBOUR_EDGE - 24.0) * 0.5))
		sea.material_override = water
		sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sea.add_to_group(BACKDROP_GROUP)
		parent.add_child(sea)


## The harbour light: a tapered tower with a lantern room on it, and a lamp that
## comes round every eight seconds.
##
## The sweep is the one thing in this map's sky that a player will watch. It is
## a spot with no shadows, aimed flat out of a lantern 21.5 m up, and it is
## deliberately *above* the fight: at that height and that pitch the beam grazes
## the top tier of the walls and the fog over head height and reaches no part of
## the yard a Bog can stand on. A sweeping light that lit players would be a
## lighting change on a timer, which on a competitive map is a rule.
##
## Its volumetric fog energy is high — the beam is 40 m of thin air away and the
## only reason it exists is to be *visible* as a shaft, not to illuminate.
func _port_beacon(parent: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.52, 0.50, 0.48)
	var trim := Color(0.34, 0.14, 0.12)
	# Four courses, each narrower than the one under it: a taper in four steps
	# reads as a lighthouse and costs 48 triangles.
	for i: int in 4:
		var low := float(i) * BEACON_HEIGHT * 0.21
		var wide := lerpf(5.4, 3.2, float(i) / 3.0)
		_add_box(st, Transform3D.IDENTITY, BEACON_AT + Vector3.UP * (low + BEACON_HEIGHT * 0.105),
			Vector3(wide, BEACON_HEIGHT * 0.21, wide), stone if i % 2 == 0 else trim)
	var gallery := BEACON_AT + Vector3.UP * (BEACON_HEIGHT * 0.84 + 0.3)
	_add_box(st, Transform3D.IDENTITY, gallery, Vector3(5.0, 0.6, 5.0), trim)
	# Four corner posts and a cap, not a solid block: the lamp sits between
	# them. The first version was a closed lantern room with the light inside
	# it, which from outside is a lighthouse that is switched off.
	for cx: float in [-1.5, 1.5]:
		for cz: float in [-1.5, 1.5]:
			_add_box(st, Transform3D.IDENTITY, gallery + Vector3(cx, 2.4, cz),
				Vector3(0.35, 4.2, 0.35), trim)
	_add_box(st, Transform3D.IDENTITY, gallery + Vector3.UP * 4.9, Vector3(4.4, 0.8, 4.4), trim)
	_add_box(st, Transform3D.IDENTITY, gallery + Vector3.UP * 5.8, Vector3(1.4, 1.2, 1.4), stone)
	var tower := MeshInstance3D.new()
	tower.name = "BeaconTower"
	tower.mesh = st.commit()
	var shell := StandardMaterial3D.new()
	shell.vertex_color_use_as_albedo = true
	shell.roughness = 0.8
	tower.material_override = shell
	tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tower.add_to_group(BACKDROP_GROUP)
	parent.add_child(tower)

	_beacon = Node3D.new()
	_beacon.name = "Beacon"
	_beacon.position = gallery + Vector3.UP * 2.3
	parent.add_child(_beacon)

	var lantern := MeshInstance3D.new()
	lantern.name = "Lantern"
	var bulb := SphereMesh.new()
	bulb.radius = 0.9
	bulb.height = 1.8
	bulb.radial_segments = 10
	bulb.rings = 6
	lantern.mesh = bulb
	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.albedo_color = Color(1.0, 0.94, 0.80)
	hot.emission_enabled = true
	hot.emission = Color(1.0, 0.88, 0.66)
	hot.emission_energy_multiplier = 9.0
	lantern.material_override = hot
	lantern.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lantern.add_to_group(BACKDROP_GROUP)
	_beacon.add_child(lantern)

	var sweep := SpotLight3D.new()
	sweep.name = "Sweep"
	sweep.light_color = Color(1.0, 0.90, 0.72)
	sweep.light_energy = 16.0
	sweep.spot_range = 150.0
	sweep.spot_angle = 6.0
	sweep.spot_attenuation = 0.25
	sweep.light_specular = 0.0
	sweep.light_volumetric_fog_energy = 14.0
	sweep.shadow_enabled = false
	# Aimed a degree and a half below the horizontal, which over 60 m of reach
	# drops the beam from 21.5 m to about 20 m at the near wall — still four
	# metres clear of the highest thing anybody stands on.
	sweep.rotation = Vector3(-0.026, 0.0, 0.0)
	_beacon.add_child(sweep)


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
	for spot: Vector2 in [Vector2(-13.8, -5.4), Vector2(13.8, 5.4), Vector2(-5.4, 13.8),
			Vector2(5.4, -13.8), Vector2(-18.6, 11.4), Vector2(18.6, -11.4)]:
		_bolt(batch, FLOOR_MARKS[rng.randi() % FLOOR_MARKS.size()],
			Vector3(spot.x, 0.013, spot.y), rng.randf_range(0.0, TAU), 1.0)


# --------------------------------------------------------------- the city ---

## One kit piece into the batch.
func _bolt(batch: Dictionary, model: String, at: Vector3, yaw: float, scale: float) -> void:
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
	var list: Array = batch.get(model, [])
	list.append(Transform3D(basis, at))
	batch[model] = list


## One `MultiMeshInstance3D` per model, for the same reasons Twin Quarry does it
## (D-082): a node per prop is a draw call per prop for scenery nothing touches,
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
## thing to give somebody. Open at one end it is a pocket: a Bog inside has one
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
##   face stops a Bog from the inside as firmly as the outside face stops one from
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
## on the machine a Bog can stand on is the 1.20 m deck, and that is declared.
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
		# place a Bog stands.
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


## Two pallets, stacked. 28 cm to the top deck, which is under D-084's 0.3 m line
## for a thing a Bog walks over rather than round.
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


## A vertical plane, `size` metres across and tall, facing its own +z and
## centred on its own origin.
##
## The dressing's workhorse: a net, a tarp and a stencil are all this quad with
## a different texture on them, which is why there is one of it and not three.
## `_quad` is the horizontal cousin and cannot be reused — it lies in the ground
## plane, and every one of these hangs on a wall.
func _panel_mesh(key: String, size: Vector2) -> Mesh:
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	_face(st, Vector3(-hx, -hy, 0.0), Vector3(hx, -hy, 0.0), Vector3(hx, hy, 0.0),
		Vector3(-hx, hy, 0.0), Vector3.BACK, 1.0)
	st.generate_tangents()
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


func _net_mesh() -> Mesh:
	return _panel_mesh("net", Vector2(2.8, NET_TOP - NET_BOTTOM))


func _tarp_mesh() -> Mesh:
	return _panel_mesh("tarp", Vector2(3.2, 2.2))


func _stencil_mesh() -> Mesh:
	return _panel_mesh("stencil", STENCIL_SIZE)


## A festoon bulb. Six segments and four rings, because it is 13 cm across and
## at that size the silhouette is a dot however many triangles it has.
func _bulb_mesh() -> Mesh:
	if _mesh_cache.has("bulb"):
		return _mesh_cache["bulb"]
	var bulb := SphereMesh.new()
	bulb.radius = FESTOON_BULB * 0.5
	bulb.height = FESTOON_BULB
	bulb.radial_segments = 6
	bulb.rings = 4
	_mesh_cache["bulb"] = bulb
	return bulb


## A net float: a ball on the end of nothing, hung on a wall face.
func _float_mesh() -> Mesh:
	if _mesh_cache.has("float"):
		return _mesh_cache["float"]
	var ball := SphereMesh.new()
	ball.radius = 0.24
	ball.height = 0.48
	ball.radial_segments = 8
	ball.rings = 5
	_mesh_cache["float"] = ball
	return ball


## A tyre fender, as a ring of eight short boxes in its own xy plane.
##
## Built rather than a `TorusMesh` for one reason: a torus lies in the ground
## plane with its axis up, and a fender hangs on a wall with its axis pointing
## out of it. A primitive cannot be rotated, so the alternative is a rotation
## baked into two hundred instance transforms, and this is one mesh instead.
func _fender_mesh() -> Mesh:
	if _mesh_cache.has("fender"):
		return _mesh_cache["fender"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k: int in 8:
		var angle := TAU * float(k) / 8.0
		var spoke := Transform3D(Basis(Vector3.BACK, angle), Vector3.ZERO)
		_add_box(st, spoke, Vector3(0.0, 0.29, 0.0), Vector3(0.24, 0.16, 0.20))
	var mesh := st.commit()
	_mesh_cache["fender"] = mesh
	return mesh


## A fish crate: a shallow timber box, centred on its own origin.
func _fish_crate_mesh() -> Mesh:
	if _mesh_cache.has("fish"):
		return _mesh_cache["fish"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_uv_box(st, Vector3(0.0, 0.0, 0.0), Vector3(0.62, 0.42, 0.46))
	st.generate_tangents()
	var mesh := st.commit()
	_mesh_cache["fish"] = mesh
	return mesh


## A mooring bitt: a post with a collar and a cap, standing on its own origin.
func _bitt_mesh() -> Mesh:
	if _mesh_cache.has("bitt"):
		return _mesh_cache["bitt"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_cylinder(st, Transform3D.IDENTITY, Vector3.ZERO, Vector3.UP, 0.17, 0.62, 10)
	_add_cylinder(st, Transform3D.IDENTITY, Vector3(0.0, 0.58, 0.0), Vector3.UP, 0.25, 0.14, 10)
	var mesh := st.commit()
	_mesh_cache["bitt"] = mesh
	return mesh


## A gull, at 28 cm and from four boxes. It is on a wall top 7.8 m up and 20 m
## away; what it has to be is a pale comma on a dark edge, and it is.
func _gull_mesh() -> Mesh:
	if _mesh_cache.has("gull"):
		return _mesh_cache["gull"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box(st, Transform3D.IDENTITY, Vector3(0.0, 0.10, 0.0), Vector3(0.26, 0.15, 0.13))
	_add_box(st, Transform3D.IDENTITY, Vector3(0.09, 0.21, 0.0), Vector3(0.10, 0.11, 0.09))
	_add_box(st, Transform3D.IDENTITY, Vector3(-0.15, 0.11, 0.0), Vector3(0.14, 0.05, 0.07))
	var mesh := st.commit()
	_mesh_cache["gull"] = mesh
	return mesh


## A coil of rope on the concrete: two concentric rings of short blocks, 16 cm
## tall, which is under D-084's 0.3 m line and therefore something a Bog walks
## over rather than something he has to believe is cover.
func _rope_coil_mesh() -> Mesh:
	if _mesh_cache.has("coil"):
		return _mesh_cache["coil"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring: int in 2:
		var radius := ROPE_COIL_RADIUS * (1.0 if ring == 0 else 0.58)
		var count := 14 if ring == 0 else 9
		for k: int in count:
			var angle := TAU * float(k) / float(count)
			var spoke := Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
			_add_box(st, spoke, Vector3(radius, ROPE_COIL_HEIGHT * 0.5, 0.0),
				Vector3(0.15, ROPE_COIL_HEIGHT, radius * 0.9))
	var mesh := st.commit()
	_mesh_cache["coil"] = mesh
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
##
## The colour goes in as a vertex attribute and defaults to white, so the
## surfaces that do not want it (the masts, the door bars, the cranes — all of
## them a single `material_override` with `vertex_color_use_as_albedo` off)
## carry four bytes a vertex they ignore, and the port gets a hundred and forty
## differently shaded shapes out of one draw call. A SurfaceTool's vertex format
## is fixed for a whole surface, so this has to be set on every vertex or on
## none of them; white on every vertex is the cheaper of the two rules to keep.
func _add_box(st: SurfaceTool, xform: Transform3D, centre: Vector3, size: Vector3,
		tint: Color = Color.WHITE) -> void:
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
			st.set_color(tint)
			st.set_normal(world_n)
			st.add_vertex(xform * p)


## A box stretched from `from` to `to`, `thickness` square, in `xform`'s frame.
func _add_beam(st: SurfaceTool, xform: Transform3D, from: Vector3, to: Vector3,
		thickness: float, tint: Color = Color.WHITE) -> void:
	var span := to - from
	var up := Vector3.UP if absf(span.normalized().y) < 0.95 else Vector3.RIGHT
	var along := Transform3D(Basis.looking_at(span, up), (from + to) * 0.5)
	_add_box(st, xform * along, Vector3.ZERO, Vector3(thickness, thickness, span.length()), tint)


## A flat quad on y = 0, `size` across, UVs in metres over `tile`.
##
## Tangents, which it did not have. The floor's material is a normal-mapped
## shader now, and a normal map on a mesh with no tangent frame is not a subtle
## bug — the whole surface lights as though every pit in the concrete faced the
## same way. The paint stripes use the same helper and do not need them; four
## vertices of tangent is not worth a second function.
func _quad(size: Vector2, tile: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	_face(st, Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz),
		Vector3.UP, size.x / tile, size.y / tile)
	st.generate_tangents()
	return st.commit()


# --------------------------------------------------------------- materials ---

func _build_materials() -> void:
	var ribs := _rib_images()
	var albedo := ImageTexture.create_from_image(ribs[0])
	var normal := ImageTexture.create_from_image(ribs[1])
	# Rust as a roughness map, not as a colour. The paint palette is gameplay —
	# at dusk it is what tells one aisle from the next — so nothing is allowed
	# to muddy it. What a photograph of corrosion *can* do without touching the
	# palette is break up the specular: painted steel that has been on a dock
	# for ten years is glossy where the paint held and flat where it did not,
	# and a single roughness value across a 6 m panel is the one cue that says
	# "plastic" from any distance. One 1k greyscale, shared by all fourteen
	# materials. (`assets/maps/wharf/SOURCES.md`, CC0.)
	var corrosion := load("res://assets/maps/wharf/rust_coarse_01_diff_1k.jpg") as Texture2D
	for paint: Color in PAINTS:
		var material := StandardMaterial3D.new()
		material.albedo_color = paint
		material.albedo_texture = albedo
		material.normal_enabled = true
		material.normal_texture = normal
		material.normal_scale = 0.9
		# Godot multiplies the roughness scalar by the texture, so the scalar is
		# the *ceiling* and the map only ever takes roughness away. The red
		# channel of a rust photograph runs about 0.55 to 0.95, which lands the
		# panels between 0.5 and 0.85 — old paint, with the odd polished patch
		# where something has rubbed against it. The green channel, tried first,
		# runs half that and turned the whole yard into wet plastic.
		material.roughness = 0.9
		material.metallic = 0.3
		if corrosion != null:
			material.roughness_texture = corrosion
			material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
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

	# The floor. Half of every frame on this map, and the thing the whole hour
	# turns on — so it is the one surface here that is photographed rather than
	# computed, and the one that gets a shader of its own.
	#
	# It was a two-grey `NoiseTexture2D` at roughness 0.42, described in a
	# comment as a wet dock and rendering as a dry purple carpet: an even
	# roughness cannot pool, and noise has no aggregate in it. What replaced it
	# is a CC0 Poly Haven concrete set (see `assets/maps/wharf/SOURCES.md`) with
	# `wharf_wet_concrete.gdshader` over the top, which puts the rain back —
	# seeded pools in world space, near-mirror roughness inside them for the
	# environment's SSR to find the lamp heads with, and two crossed waves so
	# the reflections move.
	_floor_material = ShaderMaterial.new()
	_floor_material.shader = load("res://resources/shaders/wharf_wet_concrete.gdshader")
	_floor_material.set_shader_parameter("albedo_tex",
		load("res://assets/maps/wharf/brushed_concrete_2_diff_2k.jpg"))
	_floor_material.set_shader_parameter("normal_tex",
		load("res://assets/maps/wharf/brushed_concrete_2_nor_gl_2k.jpg"))
	_floor_material.set_shader_parameter("rough_tex",
		load("res://assets/maps/wharf/brushed_concrete_2_rough_2k.jpg"))
	# The photograph is a warm mid-grey shot in daylight. Dockside concrete at
	# dusk is colder and a third darker, and the tint is where that is said
	# rather than in the exposure, which has a whole map to get right.
	_floor_material.set_shader_parameter("tint", Color(0.44, 0.47, 0.53))

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

	# The lamp heads. Nine times over, which is well clear of the environment's
	# 2.0 glow threshold, so these four faces and the eleven quay lamps behind
	# them are the only things on the map allowed to bloom.
	_lamp = StandardMaterial3D.new()
	_lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp.albedo_color = FLOOD_COLOUR
	_lamp.emission_enabled = true
	_lamp.emission = FLOOD_COLOUR
	_lamp.emission_energy_multiplier = 9.0

	_build_gear_materials()


## The dressing's palette, all seven of it.
##
## Two things are worth saying about this set rather than about any one of them.
##
## The first is that it is **seven materials for two hundred and forty props**,
## because every one of them is shared by every instance through `_scatter` and
## nothing here is ever duplicated per object. The only material on this map
## that is per-object is a floodlight's glare, and that one has a comment saying
## why.
##
## The second is grime, which is where the wharf was thinnest against the
## forest. Whisperbloom Hollow varies its ground four ways and tints every
## scattered prop; the yard had fourteen container paints and a concrete. What
## the gear adds is the other end of the range — hemp, wet canvas, perished
## rubber, salt-bleached timber — none of which is saturated and none of which
## is the same roughness, so under one sodium key they separate from the steel
## by *material* rather than by colour, which is the only way left on a map
## whose colour is gameplay (see `PAINTS`).
func _build_gear_materials() -> void:
	_rope = StandardMaterial3D.new()
	_rope.albedo_color = Color(0.50, 0.43, 0.30)
	_rope.roughness = 0.98

	_canvas = StandardMaterial3D.new()
	_canvas.albedo_color = Color(0.66, 0.64, 0.58)
	_canvas.roughness = 0.88
	# A tarp is a sheet and a gull is a bird: both are seen from whichever side
	# the player happens to be on, and a one-sided quad is invisible from half
	# the yard.
	_canvas.cull_mode = BaseMaterial3D.CULL_DISABLED

	_net_material = StandardMaterial3D.new()
	_net_material.albedo_color = Color(0.42, 0.46, 0.40)
	_net_material.albedo_texture = ImageTexture.create_from_image(_net_image())
	# Scissor rather than blended alpha. A net is 90 per cent holes, and a
	# hundred and forty blended quads hanging on the walls of a 43 m yard is a
	# hundred and forty unsorted transparent surfaces in front of a volumetric
	# fog; scissor puts the whole thing back in the opaque pass for nothing.
	_net_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_net_material.alpha_scissor_threshold = 0.5
	_net_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_net_material.roughness = 0.95

	_float_material = StandardMaterial3D.new()
	_float_material.albedo_color = Color(0.78, 0.33, 0.10)
	_float_material.roughness = 0.55

	_rubber = StandardMaterial3D.new()
	_rubber.albedo_color = Color(0.07, 0.07, 0.08)
	_rubber.roughness = 0.94

	# The bulbs. Unshaded and six times over, which clears the environment's
	# 2.0 glow threshold, so a festoon blooms the way the lamp heads do — and
	# that bloom is most of what makes a 13 cm sphere read as a light at 30 m.
	_bulb_material = StandardMaterial3D.new()
	_bulb_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bulb_material.albedo_color = FESTOON_WARM
	_bulb_material.emission_enabled = true
	_bulb_material.emission = FESTOON_WARM
	_bulb_material.emission_energy_multiplier = 6.0
	_bulb_material.disable_receive_shadows = true

	for i: int in 4:
		var stencil := StandardMaterial3D.new()
		stencil.albedo_texture = ImageTexture.create_from_image(_stencil_image(i))
		# Sprayed paint that has been on a box for years: never white, and a
		# different tired off-white per variant so four marks on one wall do not
		# read as four copies.
		stencil.albedo_color = Color(0.86, 0.84, 0.78).darkened(0.06 * float(i))
		stencil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		stencil.alpha_scissor_threshold = 0.5
		stencil.roughness = 0.82
		# Mirrored in u, and this is the one line in the file that had to be
		# found by looking at a render rather than by arithmetic. `_panel_mesh`
		# runs its u from local -x to +x, exactly as `_face` does everywhere
		# else in this file — and a viewer standing in front of a +z-facing
		# quad has local +x on his *left*, so the lettering came out backwards.
		# Nothing else that uses that quad noticed, because a net and a tarp are
		# both symmetric; a container number is the first texture on this map
		# with a handedness.
		stencil.uv1_scale = Vector3(-1.0, 1.0, 1.0)
		_stencil_materials.append(stencil)


## The netting, as a 64 x 64 alpha lattice: an 8-pixel mesh with 2-pixel twine.
## Computed rather than loaded, like the corrugation, so there is nothing to
## import and nothing that is anybody else's.
func _net_image() -> Image:
	var size := 64
	var image := Image.create(size, size, true, Image.FORMAT_RGBA8)
	for y: int in size:
		for x: int in size:
			var twine := (x % 8) < 2 or (y % 8) < 2
			# A little slack in the weave, so the lattice is not a graph paper.
			var wobble := int(1.5 + 1.5 * sin(float(y) * 0.5))
			if ((x + wobble) % 8) < 2:
				twine = true
			var shade := 0.55 + 0.45 * float((x + y) % 3) / 2.0
			image.set_pixel(x, y, Color(shade, shade, shade, 1.0 if twine else 0.0))
	image.generate_mipmaps()
	return image


## One stencil: six glyphs out of `STENCIL_GLYPHS` in a row, 192 x 56, alpha
## where the paint is and nothing anywhere else.
##
## Six because that is what a container carries — four letters of owner code and
## a couple of digits — and because six in 1.5 m makes each letter 25 cm, which
## is the size a real one is painted at.
##
## The paint is eaten into rather than solid. A stencil that has been on a box
## in salt air for ten years is missing about a fifth of itself, and the cheapest
## honest version of that is to drop scattered pixels out of the glyph with the
## same seeded generator that chose it — no second texture, no blend, and it
## survives the mipmap as a slightly thinner letter, which is exactly what it
## should look like from across the yard.
func _stencil_image(variant: int) -> Image:
	var cells := 6
	var cell_w := 32
	var width := cells * cell_w
	var height := 56
	var image := Image.create(width, height, true, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = PLANT_SEED * 31 + variant
	var chosen: Array[PackedStringArray] = []
	for cell: int in cells:
		chosen.append(STENCIL_GLYPHS[rng.randi() % STENCIL_GLYPHS.size()])
	var clear := Color(1.0, 1.0, 1.0, 0.0)
	for y: int in height:
		for x: int in width:
			var cell := x / cell_w
			# A 4-pixel gutter each side of every cell, so two letters never
			# touch once the texture is filtered down.
			var gx := (x - cell * cell_w - 4) * 5 / (cell_w - 8)
			var gy := (y - 6) * 7 / (height - 12)
			if gx < 0 or gx >= 5 or gy < 0 or gy >= 7:
				image.set_pixel(x, y, clear)
				continue
			var row: String = chosen[cell][gy]
			var on := row[gx] == "1" and rng.randf() > 0.13
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0 if on else 0.0))
	image.generate_mipmaps()
	return image


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


func _group(named: String, under: Node3D = null) -> Node3D:
	var node := Node3D.new()
	node.name = named
	(under if under != null else self).add_child(node)
	return node
