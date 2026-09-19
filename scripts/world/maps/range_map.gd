class_name RangeMap
extends StaticMap
## Highsun Grounds — the practice range (D-113).
##
## A cleared bog under a high sun where the Elders train: a lodge at the south
## end, the lanes and the yards laid out north of it, and nothing but void off
## the north and east edges. It is the seventh built map and it is built the way
## the other six are (D-042, D-056, D-082) — `const` tables, geometry before
## `super()`, dressing after, no random draw anywhere, so every peer builds the
## same bog by construction rather than by a shared seed.
##
## It was **Glowworm Grounds** while it was a bog at night, and the name went
## with the hour. The sun is thirty-two degrees up now, so a place named for the
## only things that glowed in the dark is a place named for something nobody can
## see. The glowworms themselves stay: they are the drifting motes in
## `range_ambience.gd`, which is air rather than furniture.
##
## It is also the first map that is not an arena. There are no two fair halves
## here and no sightline budget: a range exists to give you a sixty-metre bow
## lane, a gong at the spear's flat twenty-eight, and a dummy standing on a
## distance its own table put it on. What it is held to instead is the jump arc
## and the marker contract, and both are checked (§ the gate, below).
##
## Two things in this file are **not** unit 2's to remove, and the gate fails if
## they go:
##
##   the spawns       eight inward-facing `Marker3D`s under `Spawns`, built
##                    before `super()`. Unit 2 moves them onto the lodge deck;
##                    it does not delete the node.
##   `RangeDummies`   added after `super()`. It is what `MatchState.spawn_for`
##                    is driven by and what units 3, 4 and 5 all reach through
##                    `RangeDummies.instance`. A range without it is a range
##                    with no targets in it, and nothing else would notice.
##
## The build order is every other built map's and the rule is the same:
## everything added **before** `super()` is swept into world-space trimesh
## collision, everything after it is dressing that nothing can collide with.
##
## ## Every height in here is derived
##
## `Bog.eye_height()` is `pose_height() * 0.86`, so a standing Bog's eyes are at
## **1.33 m** and a crouching one's (`CROUCH_HEIGHT` 1.35) at **1.16 m**. That
## is the whole of the cover grammar:
##
##   1.25  `COVER`. Waist high. A crouching Bog is hidden behind it and a
##         standing one is not, ten centimetres of crown showing as the tell a
##         pop-up dummy wants. Also under `parkour_report.GROUND_HOP` (1.30), so
##         it is a step and never a barrier.
##   1.80  `BACKSTOP`. Over standing eyes and over the hop's 1.69 m of rise; a
##         leap lifts 2.30 m, so you can get on top of one. The two gallery
##         backstops are the only things on the map at this height, and a
##         backstop is a thing that stops a missed shot rather than a thing that
##         divides a lane. It was `FENCE` while the lanes had fences in them,
##         and it is renamed because nothing on this map fences anything now.
##   3.00  `LEDGE`. Past the leap, inside the one-tick dive (4.23 m) — so from
##         flat ground it is dive-only, and the 1.2 m kerb against its face is
##         the honest route up.
##   4.50  `UNJUMPABLE`. Flat ground buys 3.5 m under `parkour_report`'s
##         `GROUND_BIG`, but that number is a model of a player who has to *aim*
##         a dive at a lip. The physical maximum is the dive's own apex, 4.23 m,
##         and that is what the off-limits check uses. A wall nobody may ever
##         stand on has to clear the second number, not the first: 4.0 failed.
##   5.60  the lodge eave, because the deck is 1.2 m up and 1.2 + 4.23 is 5.43.
##
## ## The zones
##
## Nine, each its own table and its own `Node3D`:
##
##   lodge     a 24 x 12 m deck 1.2 m up under a hall roof, the eight pads on
##             it, two ramps down to the apron. The apron in front of it is the
##             hub: racks west, wells east, every zone entered off it.
##   lanes     three throwing lanes, 6 m wide, 32 m long, read off what stands
##             in them rather than off anything between them: dummies at
##             8 / 15 / 22 m, boards at 8 and 22, one pop-up cover block each,
##             and the gong at 28 m on the middle lane.
##   long      the bow lane. 12 m wide, 60 m long, a dummy at 45 m and a board
##             at 30. Nothing else stands in it, which is the point of it.
##   gallery   three waist walls at 12 / 16 / 20 m with pop-up dummies behind
##             them and strafers on the open ground between.
##   melee     a 10 m pit sunk 1.5 m with one ramp in, circlers and a rusher.
##   yard      open ground for the abilities: a clump of five for the magnet, a
##             3 m ledge to pull one off, two walls to plant a shield behind.
##   parkour   nineteen landings sized off the arc: hop steps, a momentum
##             runway, a crouch tunnel, three leap pillars, a dive wall with a
##             switchback beside it, and a summit that overlooks the lot.
##   void      the north and east lips. A railing with one signposted gap, and
##             nothing under it: `void_height` is -12, which is 0.86 s of fall.
##   capture   bases and cards, so Capture B·O·G on the range practises the real
##             layout rather than the fallback (D-051).
##
## ## The markers are the contract
##
## Units 3, 4 and 5 were written against the marker groups below before this
## map existed: `Spawns`, `Bases`, `Letters`, `DummyStations`, `Wells`, `Racks`,
## `Signs`, `Targets`, `Plates`, `Boards`. Facing is a marker's own -Z, as
## `Spawns` already is;
## `global_transform` is what `RangeDummies.spawn(station, brain, meta)` takes.
## Every `meta` value is a **string**, never an enum ordinal, so the map does
## not depend on `Pickup.Kind`'s or `Loadout.Weapon`'s numbering. The build log
## prints the census and the gate greps it, so a marker dropped by a later edit
## fails a check rather than a playtest.

# ---------------------------------------------------------------- the world ---

## The ground, as (west, east) and (north, south). North is -z, as on the wharf.
## 60 x 90 m of bog inside a 70 x 100 m footprint once the bank and the rim are
## counted.
const WEST := -34.0
const EAST := 26.0
const NORTH := -44.0
const SOUTH := 46.0
## How thick the peat is. Nothing stands on its underside; this is a name for a
## seam, so the void below reads as a cut edge rather than as paper.
const PEAT_THICK := 0.8

## The cover grammar, derived in the header. Nothing in this file states a
## height that is not one of these or built out of them.
const COVER := 1.25
const BACKSTOP := 1.80
const LEDGE := 3.00
const UNJUMPABLE := 4.50
const DECK := 1.20
const EAVE := 5.60
const RIDGE := 7.40
const BANK := 8.00

## The landing lip every other built map takes off an inscribed radius.
const LIP := 0.15

# ------------------------------------------------------------------- lodge ---

## The deck: 24 x 12 m, 1.2 m up, at the south end. Its width is not a taste
## decision — `preview_map.PAD_SEPARATION` is 6 m and eight pads have to fit on
## it, which two rows of four at 6.5 m across and 7 m apart do and nothing
## narrower does.
const LODGE_X := Vector2(-12.0, 12.0)
const LODGE_Z := Vector2(34.0, 46.0)
## The two ramps down to the apron, by their centre x. 1.2 m over 4 m is 16.7
## degrees, well inside `floor_max_angle`.
const RAMP_X: PackedFloat32Array = [-6.0, 6.0]
const RAMP_WIDTH := 4.0
const RAMP_RUN := 4.0

## The pads. Two rows, and every pairwise gap clears `PAD_SEPARATION`: 6.5 m
## along a row, 7.0 m between the rows, 9.5 m on the diagonal.
const PAD_X: PackedFloat32Array = [-9.75, -3.25, 3.25, 9.75]
const PAD_Z: PackedFloat32Array = [37.0, 44.0]
const PAD_LIFT := 0.12
## How far a pad is turned off due north, outward, so the deck fans. The bounds
## centre is about (-4, +1), which is 9-18 degrees off north from every pad, and
## `preview_map` allows 60.
const PAD_FAN := deg_to_rad(10.0)

# ------------------------------------------------------------------- lanes ---

## The three throwing lanes, as the four lines that divide them: 6 m apart, so
## the lanes are 6 m wide and there is no dead metre between them. **Nothing is
## built on these lines any more** — see `_build_lanes`. They are the arithmetic
## every lane's centre, cover block, dummy and board is derived from, and a lane
## is read off the things standing in it.
const LANE_LINES: PackedFloat32Array = [-32.0, -26.0, -20.0, -14.0]
## Where a thrower stands, and how long a lane runs.
const LANE_FIRING_Z := 26.0
const LANE_LENGTH := 32.0
## Where the dummies stand, and where the boards do.
const LANE_DUMMIES: PackedFloat32Array = [8.0, 15.0, 22.0]
const LANE_BOARDS: PackedFloat32Array = [8.0, 22.0]
## The gong: the spear's flat range, on the middle lane.
const GONG_RANGE := 28.0
## How far off the lane's centre line a board stands, so it never hides the
## dummy at the same distance.
const BOARD_OFFSET := 1.8

# ---------------------------------------------------------------- long lane ---

## The bow lane, on the map's spine. 60 m, which is past the full draw's 50.6.
const LONG_LINES: PackedFloat32Array = [-6.0, 6.0]
const LONG_FIRING_Z := 30.0
const LONG_LENGTH := 60.0
const LONG_DUMMY := 45.0
const LONG_BOARD := 30.0

# ----------------------------------------------------------------- gallery ---

## Where a shooter stands, and the three waist walls, as (centre, half-length)
## on x with the distance out from the mark. 12, 16 and 20 m, which is the band
## the scope asks for.
const GALLERY_MARK := Vector2(15.0, 26.0)
const GALLERY_WALLS: Array[Dictionary] = [
	{"x": 12.0, "range": 12.0, "length": 6.0},
	{"x": 19.0, "range": 16.0, "length": 6.0},
	{"x": 13.0, "range": 20.0, "length": 6.0},
]
const WALL_THICK := 0.5
## The two backstops behind the gallery, at `BACKSTOP`, so a missed shot stops
## somewhere rather than sailing into the void.
const GALLERY_BACKSTOPS: Array[Vector2] = [Vector2(9.0, 15.0), Vector2(17.0, 23.0)]
const GALLERY_BACK_Z := 3.0

# ------------------------------------------------------------------- melee ---

## The pit: a 10 m square sunk 1.5 m, with one ramp in from the west. Square
## rather than round because the collision is what matters and the kit rocks in
## the corners are what make it read as a ring.
const PIT_X := Vector2(11.0, 21.0)
const PIT_Z := Vector2(-12.0, -2.0)
const PIT_FLOOR := -1.5
## The ramp: 1.5 m over 3.2 m is 25.1 degrees, the same grade as the quarry's
## haul roads, and the only climbable slope a Bog with no step-up has.
const PIT_RAMP_Z := Vector2(-8.0, -4.0)
const PIT_RAMP_RUN := 3.2
## Four kerbs on the lip, the pit's only cover.
const PIT_KERBS: Array[Vector2] = [
	Vector2(9.5, -4.0), Vector2(22.5, -6.0), Vector2(14.0, -0.5), Vector2(18.0, -13.5),
]
const KERB := Vector2(2.4, 0.9)

# --------------------------------------------------------------------- yard ---

## The ability yard. The clump is five standing Bogs 2.5 m apart — one magnet
## thrown into the middle of it should catch more than one.
const CLUMP_AT := Vector2(-21.0, -26.0)
const CLUMP_GAP := 2.5
## The 3 m ledge and the 1.2 m kerb against its south face. See the header:
## three metres is dive-only from the flat, so the kerb is the route.
const YARD_LEDGE_X := Vector2(-31.0, -25.0)
const YARD_LEDGE_Z := Vector2(-37.0, -33.0)
const YARD_KERB_AT := Vector2(-28.0, -32.0)
const YARD_KERB := Vector2(1.5, 1.5)
const YARD_KERB_TOP := 1.20
## Two walls to plant a shield behind.
const SHIELD_WALLS: Array[Vector2] = [Vector2(-16.0, -14.0), Vector2(-11.0, -19.0)]
const SHIELD_WALL := Vector2(4.0, 0.5)

# ------------------------------------------------------------------ parkour ---

## Every landing on the course, and every gap in it, sized off the arc
## `parkour_report` rebuilds from `bog.gd`: at run speed a hop crosses 3.72 m of
## capsule gap and lifts 1.69 m, a leap crosses 7.66 and lifts 2.30, and the
## one-tick dive crosses 10.43 and lifts 4.23. The numbers in the comments are
## the *capsule* gap the checker computes, not the centre distance.
##
## `size` is the footprint, `top` the surface. Radius is inscribed less `LIP`.
const PARKOUR: Array[Dictionary] = [
	# The momentum runway: five at one height, 4 m apart (2.62 m of gap), so it
	# is hops all the way and the bunny hop just makes it comfortable.
	{"at": Vector2(9.0, -18.0), "size": Vector2(1.6, 1.6), "top": 1.2, "label": "runway 1"},
	{"at": Vector2(9.0, -22.0), "size": Vector2(1.6, 1.6), "top": 1.2, "label": "runway 2"},
	{"at": Vector2(9.0, -26.0), "size": Vector2(1.6, 1.6), "top": 1.2, "label": "runway 3"},
	{"at": Vector2(9.0, -30.0), "size": Vector2(1.6, 1.6), "top": 1.2, "label": "runway 4"},
	{"at": Vector2(9.0, -34.0), "size": Vector2(1.6, 1.6), "top": 1.2, "label": "runway 5"},
	# The crouch tunnel's roof. The opening under it is 1.45 m, which a 1.55 m
	# Bog does not fit through and a 1.35 m crouched one does — the one place on
	# the map where the crouch is not optional.
	{"at": Vector2(9.0, -37.5), "size": Vector2(3.0, 4.0), "top": 2.05, "label": "tunnel"},
	# Hop steps: 0.6 m of rise every 3 m (1.22 m of gap), the gentlest thing on
	# the course and the way up to the pillars.
	{"at": Vector2(14.0, -18.0), "size": Vector2(2.0, 2.0), "top": 0.6, "label": "step 1"},
	{"at": Vector2(14.0, -21.0), "size": Vector2(2.0, 2.0), "top": 1.2, "label": "step 2"},
	{"at": Vector2(14.0, -24.0), "size": Vector2(2.0, 2.0), "top": 1.8, "label": "step 3"},
	{"at": Vector2(14.0, -27.0), "size": Vector2(2.0, 2.0), "top": 2.4, "label": "step 4"},
	{"at": Vector2(14.0, -30.0), "size": Vector2(2.0, 2.0), "top": 3.0, "label": "step 5"},
	# Three pillars at one height, out on the east side over the void lip. Step 5
	# to P1 is 5.52 m of gap and P1 to either of the others is 5.82 — all past
	# the hop's 3.72 and inside the leap's 7.66, so the leap is the only way
	# round the outside. Step 5 straight to P3 is the diagonal, 8.99 m of gap:
	# past the leap, inside the dive's 10.43. That is one of the two shortcuts.
	{"at": Vector2(21.5, -30.0), "size": Vector2(2.4, 2.4), "top": 3.0, "label": "pillar 1"},
	{"at": Vector2(21.5, -38.0), "size": Vector2(2.4, 2.4), "top": 3.0, "label": "pillar 2"},
	{"at": Vector2(21.5, -22.0), "size": Vector2(2.4, 2.4), "top": 3.0, "label": "pillar 3"},
	# The dive wall, below the steps in the same column. From the plinth the
	# ledge is 3.6 m of rise, which is over the leap's 2.30 and under the dive's
	# 4.23, so it is the one-tick dive and nothing else. The switchback beside it
	# is what stops that being a locked door: `parkour_report` walks hops and
	# leaps only, and a map whose only way somewhere is a frame-perfect dive
	# fails it, rightly.
	{"at": Vector2(14.0, -33.5), "size": Vector2(2.0, 2.0), "top": 0.5, "label": "plinth"},
	{"at": Vector2(14.0, -36.5), "size": Vector2(3.0, 3.0), "top": 4.0, "label": "dive wall"},
	{"at": Vector2(17.5, -36.5), "size": Vector2(1.8, 1.8), "top": 1.8, "label": "switchback 1"},
	{"at": Vector2(17.5, -33.5), "size": Vector2(1.8, 1.8), "top": 3.2, "label": "switchback 2"},
	# The prize. A leap off pillar 2 (1.05 m of gap, 2.1 m of rise) or a hop off
	# the dive wall, and it looks back down the whole range.
	{"at": Vector2(18.0, -40.0), "size": Vector2(4.0, 4.0), "top": 5.0, "label": "summit"},
]
## The crouch tunnel's clear opening. 1.45 m, between `Bog.CROUCH_HEIGHT` (1.35)
## and `Bog.STAND_HEIGHT` (1.55), which is the whole point of it.
const TUNNEL_CLEAR := 1.45
const TUNNEL_PIER := 0.5

# --------------------------------------------------------------------- void ---

## The lips. North the whole width, east the whole length, and one signposted
## gap you are meant to walk off on purpose.
const RAIL_TOP := 1.0
const RAIL_POST := 0.12
const RAIL_STEP := 3.0
const VOID_GAP_X := Vector2(-12.0, -8.0)

# ------------------------------------------------------------------ capture ---

## Bases and cards (D-051). The bases are symmetric about x = 0 and that is not
## decoration: the eight pads are symmetric about x = 0 too, and
## `CaptureLayout` gives each pad to its nearest base — off-centre bases would
## split a deck of eight into five and three, or worse, by a handful of
## centimetres. Symmetric, they split four and four by construction, which is
## what `playthrough`'s "team N has pads to spawn on" is asking.
const BASE_AT: Array[Vector2] = [Vector2(-20.0, 30.0), Vector2(20.0, 30.0)]
## B in the bow lane, O out in the ability yard, G between the gallery and the
## pit. All three on open floor with head room, all three well outside both
## bases, and no two within 3 m of each other — `playthrough` checks all of it.
const LETTER_AT: Array[Vector2] = [
	Vector2(0.0, 10.0), Vector2(-24.0, -18.0), Vector2(20.0, 2.0),
]

# ------------------------------------------------------------------ fittings ---

## The weapon racks, west apron, in the order the loadout lists them.
const RACKS: Array[Dictionary] = [
	{"at": Vector2(-31.0, 31.0), "weapon": "spear"},
	{"at": Vector2(-28.0, 31.0), "weapon": "bow"},
	{"at": Vector2(-25.0, 31.0), "weapon": "sword"},
]
## The item wells, east apron.
const WELLS: Array[Dictionary] = [
	{"at": Vector2(6.0, 31.0), "kind": "shield"},
	{"at": Vector2(9.0, 31.0), "kind": "magnet"},
	{"at": Vector2(12.0, 31.0), "kind": "potion"},
	{"at": Vector2(15.0, 31.0), "kind": "robe"},
]
## The one sign left on the range, and the only control on it.
##
## There were six stations: glowing signposts you walked into that cycled a
## zone's dummies through a ring of behaviours, reset a zone, or reset the
## stats. They are gone, and what replaced them is nothing — **a zone's
## behaviour is now authored here and never changes**. The argument is that a
## range is a place you go to practise one thing, and a control that changes
## what the lanes are doing is a control that has to be found, understood and
## then put back before the lane means what the post beside it says it means.
## Authored, the west lane is always three standing bodies at 8, 15 and 22 m and
## you can walk to it and throw, and what a lane is doing is what it was doing
## the last time you stood in it.
##
## The stats reset survives, because it is the one switch that is about *you*
## rather than about the range, and it is now a plain timber signboard on the
## lodge deck: a post, a board, carved letters and an `Area3D`. No light and no
## chime — the feedback is the panel in the corner of the HUD going to
## zero, which is the thing you were looking at when you decided to reset it.
const SIGNBOARD := {"at": Vector3(-11.0, DECK, 40.5), "action": "reset_stats",
	"zone": "lodge"}
## The post, and the board on it: 2.0 m of post, a board 1.6 m across between
## 1.10 and 1.75 m up it, facing **east** into the middle of the deck rather
## than north down the range, because everybody on this deck is about to walk
## north and a sign facing the same way is a sign nobody reads.
const SIGN_POST := 2.0
const SIGN_WIDTH := 1.6
const SIGN_BOARD := Vector2(1.10, 1.75)
const SIGN_YAW := -PI * 0.5

## Dummy stations, in the order they are authored. **Every one of them is live.**
##
## Four of these used to be authored `live: false` — ground proved flat, clear
## of a landing radius and 4 m clear of a pad, with nobody on it, waiting for a
## station to mint a body onto it. With the stations gone there is nothing left
## to mint them, and a reserved position nobody can ever reach is a coordinate
## in a table rather than a target on a range. So the yard's jumper and
## wanderer, the west lane's deep mark and the parkour summit all stand up at
## build time with everything else: twenty-seven markers, twenty-seven dummies.
const DUMMIES: Array[Dictionary] = [
	# The gallery, the pit and the clump. The lanes and the bow lane are
	# generated from their own tables below, because their positions are the
	# distance marks and writing them twice is how they drift.
	{"at": Vector3(12.0, 0.0, 13.0), "brain": "popup", "zone": "gallery", "range": 13.0},
	{"at": Vector3(19.0, 0.0, 9.0), "brain": "popup", "zone": "gallery", "range": 17.0},
	{"at": Vector3(13.0, 0.0, 5.0), "brain": "popup", "zone": "gallery", "range": 21.0},
	{"at": Vector3(16.0, 0.0, 12.0), "brain": "strafe", "zone": "gallery", "range": 14.0},
	{"at": Vector3(21.0, 0.0, 6.0), "brain": "strafe", "zone": "gallery", "range": 20.0},
	{"at": Vector3(13.0, PIT_FLOOR, -5.0), "brain": "circler", "zone": "melee", "range": 0.0},
	{"at": Vector3(19.0, PIT_FLOOR, -9.0), "brain": "circler", "zone": "melee", "range": 0.0},
	{"at": Vector3(16.0, PIT_FLOOR, -7.0), "brain": "rusher", "zone": "melee", "range": 0.0},
	# The two in the yard that want room rather than a mark: a jumper out on the
	# open ground and a wanderer working the space between the clump and the
	# shield walls.
	{"at": Vector3(-14.0, 0.0, -30.0), "brain": "jumper", "zone": "yard", "range": 0.0},
	{"at": Vector3(-26.0, 0.0, -18.0), "brain": "wanderer", "zone": "yard", "range": 0.0},
	# The deep mark on the west lane, at the spear's flat 28 m — the same range
	# the gong hangs at on the middle lane, so the two lanes ask the same
	# question of a throw and answer it differently. `stand`, because the west
	# lane is the still lane: see `_build_dummy_markers`.
	{"at": Vector3(-29.0, 0.0, -2.0), "brain": "stand", "zone": "lanes", "range": 28.0,
		"lane": "w"},
	# And a body on the summit, for anyone practising a shot down onto the
	# course — or up at it.
	{"at": Vector3(19.5, 5.0, -40.0), "brain": "stand", "zone": "parkour", "range": 0.0},
]

## The plates unit 3 arms, and the boards unit 5 writes on.
const PLATES: Array[Dictionary] = [
	{"at": Vector3(9.0, 0.0, -16.0), "role": "parkour_start", "zone": "parkour"},
	{"at": Vector3(16.5, 5.0, -40.0), "role": "parkour_finish", "zone": "parkour"},
	{"at": Vector3(0.0, DECK, 40.5), "role": "refill", "zone": "lodge"},
]
const BOARDS: Array[Dictionary] = [
	{"at": Vector3(-5.0, DECK + 1.4, 45.4), "kind": "stats"},
	{"at": Vector3(5.0, DECK + 1.4, 45.4), "kind": "best_time"},
]

# ------------------------------------------------------------------ torches ---

## Torches. Ten, of which three cast — the island runs about fourteen with
## roughly half casting on a smaller map, and the cost that matters is the
## shadow map, not the light. `phase` decorrelates the flicker.
const TORCHES: Array[Dictionary] = [
	{"at": Vector2(-7.5, 33.0), "shadows": true},
	{"at": Vector2(7.5, 33.0), "shadows": true},
	{"at": Vector2(-32.0, 26.0), "shadows": false},
	{"at": Vector2(-20.0, 26.0), "shadows": false},
	{"at": Vector2(-6.0, 30.0), "shadows": false},
	{"at": Vector2(15.0, 27.5), "shadows": false},
	{"at": Vector2(9.5, -1.0), "shadows": false},
	{"at": Vector2(9.0, -15.5), "shadows": true},
	{"at": Vector2(-14.0, -17.5), "shadows": false},
	{"at": Vector2(-10.0, -43.0), "shadows": false},
]

## There were twenty-four glowworm lanterns on this map — unshaded emissive
## spheres on the tops of the distance posts — and they are gone with the posts.
## **A bare unshaded primitive is not a prop.** The rule the range now keeps is
## written up in the decision record with this change: anything a player looks
## at, walks past or shoots is a textured, themed object that belongs to the
## place, built out of this map's three materials; unshaded emissive geometry is
## for *effects* — a torch flame, a burst, the ambience's drifting motes — and
## never for objects. A glowing ball on a stick reads as a placeholder somebody
## forgot to replace, it breaks the timber-stone-peat grammar everything else on
## the range keeps, and on a map whose whole job is teaching you to read a
## distance it is the brightest thing in frame and it is teaching nothing.

## Props, out of the Stylized Nature MegaKit. Dressing, so none of it is
## collision, and none of it stands in a lane, inside a landing radius or within
## four metres of a pad.
const REED_MODELS: PackedStringArray = [
	"Grass_Wispy_Tall", "Grass_Common_Tall", "Grass_Wispy_Short",
]
const BLOOM_MODELS: PackedStringArray = [
	"Fern_1", "Mushroom_Laetiporus", "Plant_7", "Bush_Common",
]
const SNAG_MODELS: PackedStringArray = [
	"DeadTree_1", "DeadTree_2", "DeadTree_3", "DeadTree_4", "DeadTree_5",
]
const PEBBLE_MODELS: PackedStringArray = [
	"Pebble_Round_1", "Pebble_Round_3", "Pebble_Square_2",
]
const PROP_SEED := 0x610B

# ------------------------------------------------------------------- state ---

## What the build made, for the log line and for the gate to grep.
var zones: int = 0
var dummy_markers: int = 0
var dummies_live: int = 0

var _ground_st: SurfaceTool
var _timber_st: SurfaceTool
var _stone_st: SurfaceTool
var _peat_material: StandardMaterial3D
var _timber_material: StandardMaterial3D
var _stone_material: StandardMaterial3D


func _ready() -> void:
	var started := Time.get_ticks_msec()
	_build_materials()

	_ground_st = _begin()
	_timber_st = _begin()
	_stone_st = _begin()

	_build_ground()
	_build_lodge()
	_build_lanes()
	_build_long_lane()
	_build_gallery()
	_build_melee()
	_build_yard()
	_build_parkour()
	_build_void_edge()

	var solid := _group("Grounds")
	_commit(solid, "Peat", _ground_st, _peat_material)
	_commit(solid, "Timber", _timber_st, _timber_material)
	_commit(solid, "Stone", _stone_st, _stone_material)

	_build_spawns()
	_build_markers()

	print("%s: %d zones, %d landings, %d off limits in %d ms" % [
		name, zones, platforms.size(), off_limits.size(),
		Time.get_ticks_msec() - started])
	# The marker contract, in one line, because units 3, 4 and 5 code against it
	# before this map exists and a contract nothing asserts is one that rots.
	print("%s: %d dummies (%d live, %d reserved), %d wells, %d racks, %d signboard(s), "
		% [name, dummy_markers, dummies_live, dummy_markers - dummies_live,
			_count("Wells"), _count("Racks"), _count("Signs")]
		+ "%d targets, %d plates, %d boards" % [
			_count("Targets"), _count("Plates"), _count("Boards")])

	_check_sun_and_sky()

	# Everything above this line becomes collision. Everything below it does not.
	super()

	# ------------------------------------------------------- after super ---
	# Dressing and behaviour. Nothing below this line is collision.
	var dressing := _group("Dressing")
	_build_torches(dressing)
	_build_props(dressing)
	RangeAmbience.build(_group("Air"), Vector2(WEST, EAST), Vector2(NORTH, SOUTH))

	# The targets. See the header: this line is not unit 2's to remove.
	var dummies := RangeDummies.new()
	dummies.name = "Dummies"
	add_child(dummies)

	# And the thing that reads the markers above and stands everything on them:
	# brains on the `DummyStations`, signposts on the `Stations`, the parkour
	# clock on the `Plates`, and — through its own guarded hooks — the wells,
	# racks and refill stone on the `Wells`/`Racks`, and the boards and the gong
	# on the `Targets`. It waits for `PLAYING` by itself, so the order of
	# these two lines is not load-bearing; what is load-bearing is that both are
	# after `super()`, because neither is collision.
	add_child(RangeDirector.new())


## Where the sun actually ended up, printed out of the built scene.
##
## This map claims, in `range.tscn` and in `range_env.tres`, that the sun is
## thirty-two degrees up on a bearing thirty degrees east of north, and every
## argument about where the shadows fall is made from those two numbers. The
## elevation moved from nine to thirty-two when the owner asked for the sun
## higher in the air; the **bearing did not move**, because thirty degrees east
## of north is the one thing on this map that is load-bearing about the light
## (see `range.tscn`): every lane runs due north, and a sun on a lane's axis is
## a sun in the archer's sight. It was wrong for
## a whole pass and nothing noticed: the `Sun` node's `Transform3D` was written
## as the basis's three **columns**, and a `.tscn` stores its three **rows**, so
## the built light was 7.8 degrees up on a bearing thirty degrees *west* — sixty
## degrees from the map's own design, with the 8 m west bank throwing a
## fifty-eight-metre shadow east-south-east across the range instead of off the
## map. The renders looked plausible, because a sunset looks like a sunset from
## either side.
##
## The error was invisible for as long as this map had a moon due north, where
## the matrix is symmetric and a transpose is itself, and it appeared the moment
## the sun moved off the meridian. So the numbers come back out of the scene
## rather than being trusted: `SUN_ELEVATION` and `SUN_BEARING` are what the
## transform is derived from, this reads the transform back, and the gate greps
## the line.
const SUN_ELEVATION := 32.0
const SUN_BEARING := 30.0

func _check_sun_and_sky() -> void:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return
	# A DirectionalLight3D shines along its own -Z, so the sun is at +Z.
	var toward := sun.global_transform.basis.z.normalized()
	var elevation := rad_to_deg(asin(clampf(toward.y, -1.0, 1.0)))
	# North is -z on this map and east is +x, as it is on the wharf.
	var bearing := rad_to_deg(atan2(toward.x, -toward.z))
	var off := absf(elevation - SUN_ELEVATION) + absf(bearing - SUN_BEARING)
	print("%s: sun %.1f deg up, bearing %.1f deg E of N (%.1f off design)"
		% [name, elevation, bearing, off])

	# And the sky's fallback direction, which is what gets used if this scene is
	# ever opened without its light. It is kept equal to the Sun's own +Z.
	var world := get_node_or_null("Environment") as WorldEnvironment
	if world == null or world.environment == null or world.environment.sky == null:
		return
	var material := world.environment.sky.sky_material as ShaderMaterial
	if material == null:
		return
	var stated: Variant = material.get_shader_parameter("sun_direction")
	if stated is Vector3:
		print("%s: sky fallback %.1f deg from the Sun" % [
			name, rad_to_deg(toward.angle_to((stated as Vector3).normalized()))])


# ------------------------------------------------------------------ ground ---

## The bog, as a picture frame round the melee pit.
##
## Four slabs rather than one, for the reason Twin Quarry's floor gives: the
## number that says where the floor is cannot also be the number that says where
## the hole in it is. The pit's own floor and faces go in with the pit.
##
## The peat stops at its own edge on the north and east and there is nothing
## under it — that is what the void is. West and south it runs under the banks,
## which is what stops those being edges too.
func _build_ground() -> void:
	_slab(_ground_st, Vector2(WEST, NORTH), Vector2(PIT_X.x, SOUTH), -PEAT_THICK, 0.0)
	_slab(_ground_st, Vector2(PIT_X.y, NORTH), Vector2(EAST, SOUTH), -PEAT_THICK, 0.0)
	_slab(_ground_st, Vector2(PIT_X.x, NORTH), Vector2(PIT_X.y, PIT_Z.x), -PEAT_THICK, 0.0)
	_slab(_ground_st, Vector2(PIT_X.x, PIT_Z.y), Vector2(PIT_X.y, SOUTH), -PEAT_THICK, 0.0)

	# The west bank, and **eight metres of it rather than six**, which the report
	# had to teach me. Six is over every jump from flat ground and over every
	# jump from a 1.25 m block, and it is *not* over a one-tick dive off the 3 m
	# magnet ledge standing eight metres from it: at 3.1 m of rise the dive
	# crosses 8.14 m of capsule gap, and the ledge was inside that. Raising the
	# bank costs nothing and moving the ledge would have moved the only piece of
	# the ability yard whose whole job is being eight metres from something. At
	# 8 m the rise off the ledge is 5.1 and off the summit — the highest landing
	# on the map, and fifty metres away — is 3.1, so nothing reaches it and
	# `off_limits` is how the report says so rather than my saying so.
	_slab(_ground_st, Vector2(WEST, NORTH), Vector2(WEST + 1.5, SOUTH), 0.0, BANK)
	for z: float in [-30.0, 0.0, 30.0]:
		off_limits.append(Platform.new(Vector3(WEST + 0.75, BANK, z), 0.6, "bank",
			"west bank %+.0f" % z))

	# The south banks, flanking the lodge, so the only way out of the south end
	# is through the hall. Four metres is over everything from flat ground, and
	# the nearest landing to either of them is thirty metres away.
	for side: Vector2 in [Vector2(WEST, LODGE_X.x), Vector2(LODGE_X.y, EAST)]:
		_slab(_ground_st, Vector2(side.x, SOUTH - 2.0), Vector2(side.y, SOUTH),
			0.0, UNJUMPABLE)
		off_limits.append(Platform.new(
			Vector3((side.x + side.y) * 0.5, UNJUMPABLE, SOUTH - 1.0), 0.85, "bank",
			"south bank %+.0f" % ((side.x + side.y) * 0.5)))
	zones += 1


# ------------------------------------------------------------------- lodge ---

## The hall: a deck, a back wall, six posts, a pitched roof and two ramps.
##
## The deck is **not a declared landing** and that is deliberate.
## `parkour_report.SPAWN_PLATFORM_KEEPOUT` fails any landing within 3.5 m of a
## pad, and it is right to: the check exists to keep cover off a pad. But the
## deck *is* the pads' floor, the way the wharf's concrete is its pads' floor
## and is declared nowhere either. What is declared is the roof, in
## `off_limits`: from the deck the one-tick dive lifts 4.23 m, so the eave at
## 5.6 m needs 4.4 and does not get it.
func _build_lodge() -> void:
	_slab(_timber_st, Vector2(LODGE_X.x, LODGE_Z.x), Vector2(LODGE_X.y, LODGE_Z.y),
		0.0, DECK)
	# The back wall, and two returns down the sides, so the hall is a room.
	_slab(_timber_st, Vector2(LODGE_X.x, LODGE_Z.y - 0.6), Vector2(LODGE_X.y, LODGE_Z.y),
		DECK, EAVE)
	for x: float in [LODGE_X.x, LODGE_X.y - 0.6]:
		_slab(_timber_st, Vector2(x, LODGE_Z.x + 2.0), Vector2(x + 0.6, LODGE_Z.y),
			DECK, EAVE)

	# Six posts down the open front, and the roof on them.
	for x: float in [-11.0, -5.5, 0.0, 5.5, 11.0]:
		_slab(_timber_st, Vector2(x - 0.2, LODGE_Z.x + 0.2),
			Vector2(x + 0.2, LODGE_Z.x + 0.6), DECK, EAVE)
	# A 30 degree pitch: two slabs meeting on the ridge. Not a landing anybody
	# reaches, and the report is told so below.
	for side: int in 2:
		var lo := LODGE_X.x if side == 0 else 0.0
		var hi := 0.0 if side == 0 else LODGE_X.y
		_ramp(_timber_st, Vector2(lo, LODGE_Z.x), Vector2(hi, LODGE_Z.y),
			EAVE if side == 0 else RIDGE, RIDGE if side == 0 else EAVE, "x", 0.35)
	off_limits.append(Platform.new(Vector3(0.0, RIDGE, 40.0), 1.0, "lodge", "lodge ridge"))
	for x: float in [LODGE_X.x, LODGE_X.y]:
		off_limits.append(Platform.new(Vector3(x, EAVE, 40.0), 1.0, "lodge",
			"lodge eave %+.0f" % x))

	# The two ways down. 1.2 m over 4 m is 16.7 degrees.
	for x: float in RAMP_X:
		_ramp(_timber_st, Vector2(x - RAMP_WIDTH * 0.5, LODGE_Z.x - RAMP_RUN),
			Vector2(x + RAMP_WIDTH * 0.5, LODGE_Z.x), 0.0, DECK, "z", 0.3)

	# The stats signboard, in the timber with the rest of the lodge and therefore
	# solid: a sign you walk *through* is a sign that was never there. The board
	# lies in the z/y plane because the post faces east (`SIGN_YAW`).
	var sign: Vector3 = SIGNBOARD["at"]
	_slab(_timber_st, Vector2(sign.x - 0.09, sign.z - 0.09),
		Vector2(sign.x + 0.09, sign.z + 0.09), sign.y, sign.y + SIGN_POST)
	_slab(_timber_st, Vector2(sign.x - 0.06, sign.z - SIGN_WIDTH * 0.5),
		Vector2(sign.x + 0.06, sign.z + SIGN_WIDTH * 0.5),
		sign.y + SIGN_BOARD.x, sign.y + SIGN_BOARD.y)
	zones += 1


# ------------------------------------------------------------------- lanes ---

## Three throwing lanes, and **nothing built on the lines that divide them**.
##
## There were four lines of 2.2 m timber posts every five metres with a 0.60 m
## rail running the length of each, and the whole of that is off the map. The
## owner asked for the fences gone, and eight lines of timber running 32 m north
## from a firing line is a fence however low you argue the rail down to: the
## divider was already `FENCE` once and already lost that argument to a render,
## and this is the same argument won properly. What the posts were *for*
## survives in what stands **in** a lane — a dummy on its mark, a board beside
## it, a cover block half a metre in front of the pop-up — which is the honest
## way to read a distance anyway. A dummy at fifteen metres is the thing you are
## aiming at; a post beside it is a thing you are aiming past.
##
## So this builds one thing, the cover, at `COVER`: waist high, measured against
## a crouching Bog's eyes, there to hide a pop-up rather than to mark a lane.
## That is the line this change draws — cover and backstop are the map's grammar
## and stay; a divider is a fence and goes.
func _build_lanes() -> void:
	# One waist-high block per lane, half a metre short of the 15 m dummy, so
	# the pop-up brain has something to pop up from.
	for i: int in 3:
		var centre := _lane_centre(i)
		var at := Vector2(centre, LANE_FIRING_Z - 14.3)
		_block(_stone_st, at, Vector2(2.5, 0.8), COVER, "lanes", "lane %d cover" % i)
	zones += 1


## The bow lane, on the spine. Nothing stands in it at all: the point of sixty
## metres is that it is sixty metres of nothing, and with the twenty-six posts
## and the two rails off its lines that is now literally true.
##
## It builds no geometry and it is still a function, because the bow lane is
## still a **zone**: its dummy at 45 m, its board at 30 and the strip
## `_prop_allowed` keeps the reed out of are all derived from `LONG_LINES` and
## `LONG_FIRING_Z`, and the ninth zone is a place on this map whether or not
## anything is standing on it. Dropping the call would quietly say the bow lane
## had stopped existing.
func _build_long_lane() -> void:
	zones += 1


# ----------------------------------------------------------------- gallery ---

func _build_gallery() -> void:
	for entry: Dictionary in GALLERY_WALLS:
		var x := float(entry["x"])
		var length := float(entry["length"])
		var z := GALLERY_MARK.y - float(entry["range"])
		_block(_stone_st, Vector2(x, z), Vector2(length, WALL_THICK), COVER,
			"gallery", "wall %.0f m" % float(entry["range"]))
	for span: Vector2 in GALLERY_BACKSTOPS:
		var mid := (span.x + span.y) * 0.5
		_block(_stone_st, Vector2(mid, GALLERY_BACK_Z), Vector2(span.y - span.x, WALL_THICK),
			BACKSTOP, "gallery", "backstop %+.0f" % mid)
	zones += 1


# ------------------------------------------------------------------- melee ---

## The pit: a hole in the picture frame, a floor 1.5 m down, four faces and one
## ramp in. `void_height` is -12, so the pit floor has ten and a half metres
## under it — nobody dies by walking into the melee ring.
func _build_melee() -> void:
	_slab(_ground_st, PIT_X, PIT_Z, PIT_FLOOR - PEAT_THICK, PIT_FLOOR)
	# The four faces, with the ramp's mouth left out of the west one.
	_slab(_stone_st, Vector2(PIT_X.x, PIT_Z.x), Vector2(PIT_X.x + 0.4, PIT_RAMP_Z.x),
		PIT_FLOOR, 0.0)
	_slab(_stone_st, Vector2(PIT_X.x, PIT_RAMP_Z.y), Vector2(PIT_X.x + 0.4, PIT_Z.y),
		PIT_FLOOR, 0.0)
	_slab(_stone_st, Vector2(PIT_X.y - 0.4, PIT_Z.x), Vector2(PIT_X.y, PIT_Z.y),
		PIT_FLOOR, 0.0)
	for z: float in [PIT_Z.x, PIT_Z.y - 0.4]:
		_slab(_stone_st, Vector2(PIT_X.x, z), Vector2(PIT_X.y, z + 0.4), PIT_FLOOR, 0.0)
	# The way in. 1.5 m over 3.2 is 25.1 degrees.
	_ramp(_stone_st, Vector2(PIT_X.x, PIT_RAMP_Z.x),
		Vector2(PIT_X.x + PIT_RAMP_RUN, PIT_RAMP_Z.y), 0.0, PIT_FLOOR, "x", 0.3)

	for at: Vector2 in PIT_KERBS:
		var size := KERB if absf(at.y + 7.0) > 4.0 else Vector2(KERB.y, KERB.x)
		_block(_stone_st, at, size, COVER, "melee", "kerb %+.0f,%+.0f" % [at.x, at.y])
	zones += 1


# -------------------------------------------------------------------- yard ---

## The ability yard. Three metres of ledge with a 1.2 m kerb against its face,
## which is the whole argument: from the flat, 3 m is over the leap (1.9 m of
## ground rise) and only the one-tick dive (3.5), so the ledge would be
## *stranded* in the reachability walk — which walks hops and leaps only — with
## nothing but a dive to it. Off the kerb it is 1.8 m of rise and a leap lifts
## 2.30, so the route exists and the dive is a shortcut.
func _build_yard() -> void:
	_slab(_stone_st, Vector2(YARD_LEDGE_X.x, YARD_LEDGE_Z.x),
		Vector2(YARD_LEDGE_X.y, YARD_LEDGE_Z.y), 0.0, LEDGE)
	platforms.append(Platform.new(
		Vector3((YARD_LEDGE_X.x + YARD_LEDGE_X.y) * 0.5, LEDGE,
			(YARD_LEDGE_Z.x + YARD_LEDGE_Z.y) * 0.5),
		minf(YARD_LEDGE_X.y - YARD_LEDGE_X.x, YARD_LEDGE_Z.y - YARD_LEDGE_Z.x) * 0.5 - LIP,
		"yard", "magnet ledge"))
	_block(_stone_st, YARD_KERB_AT, YARD_KERB, YARD_KERB_TOP, "yard", "ledge kerb")
	for at: Vector2 in SHIELD_WALLS:
		_block(_stone_st, at, SHIELD_WALL, COVER, "yard",
			"shield mark %+.0f,%+.0f" % [at.x, at.y])
	zones += 1


# ----------------------------------------------------------------- parkour ---

func _build_parkour() -> void:
	for entry: Dictionary in PARKOUR:
		var at: Vector2 = entry["at"]
		var size: Vector2 = entry["size"]
		var top := float(entry["top"])
		var label := String(entry["label"])
		if label == "tunnel":
			# The roof stands on two piers with the opening between them, so the
			# thing you crouch through is a hole in the collision and not a
			# texture. Its top is a landing like anything else.
			for side: int in 2:
				var x := at.x - size.x * 0.5 if side == 0 else at.x + size.x * 0.5 - TUNNEL_PIER
				_slab(_stone_st, Vector2(x, at.y - size.y * 0.5),
					Vector2(x + TUNNEL_PIER, at.y + size.y * 0.5), 0.0, TUNNEL_CLEAR)
			_slab(_stone_st, Vector2(at.x - size.x * 0.5, at.y - size.y * 0.5),
				Vector2(at.x + size.x * 0.5, at.y + size.y * 0.5), TUNNEL_CLEAR, top)
			platforms.append(Platform.new(Vector3(at.x, top, at.y),
				minf(size.x, size.y) * 0.5 - LIP, "parkour", label))
			continue
		_block(_stone_st, at, size, top, "parkour", label)
	zones += 1


# -------------------------------------------------------------------- void ---

## The lips. A railing you can see over and cannot stand on — the rail is 0.08 m
## across and a Bog's capsule is 0.38 with a sphere on the bottom of it, so the
## contact is an edge and it slides off, which is the line `wharf_map` drew
## between a drum lid and a guard rail.
##
## And one four-metre gap, signposted, because "I fell off the island" is a
## thing worth being able to learn on purpose.
func _build_void_edge() -> void:
	var x := WEST + 2.0
	while x < EAST:
		if x < VOID_GAP_X.x or x > VOID_GAP_X.y:
			_post(_timber_st, Vector2(x, NORTH + 0.3), 0.06, RAIL_TOP)
		x += RAIL_STEP
	for span: Vector2 in [Vector2(WEST + 2.0, VOID_GAP_X.x), Vector2(VOID_GAP_X.y, EAST)]:
		for rail: float in [0.45, 0.9]:
			_slab(_timber_st, Vector2(span.x, NORTH + 0.26), Vector2(span.y, NORTH + 0.34),
				rail - 0.04, rail)
	# The signpost at the gap: a post and a board, so the hole in the rail is a
	# decision and not an oversight.
	_post(_timber_st, Vector2(VOID_GAP_X.x - 0.6, NORTH + 0.3), 0.1, 2.0)
	_slab(_timber_st, Vector2(VOID_GAP_X.x - 1.3, NORTH + 0.25),
		Vector2(VOID_GAP_X.x + 0.1, NORTH + 0.35), 1.5, 2.0)

	var z := NORTH + RAIL_STEP
	while z < SOUTH:
		_post(_timber_st, Vector2(EAST - 0.3, z), 0.06, RAIL_TOP)
		z += RAIL_STEP
	for rail: float in [0.45, 0.9]:
		_slab(_timber_st, Vector2(EAST - 0.34, NORTH), Vector2(EAST - 0.26, SOUTH),
			rail - 0.04, rail)
	zones += 1


# ------------------------------------------------------------------ spawns ---

## Eight pads on the deck, two rows of four, every one facing north up the
## range. See `PAD_X`: the spacing is what `preview_map.PAD_SEPARATION` allows
## and the deck's width follows from it rather than the other way round.
func _build_spawns() -> void:
	var root := _marker_root("Spawns")
	var index := 0
	for z: float in PAD_Z:
		for x: float in PAD_X:
			var pad := Marker3D.new()
			pad.name = "Spawn%d" % index
			# Fanned outward off due north, so eight Bogs on one deck are not
			# eight parallel stares. The bounds centre is north of every pad, so
			# ten degrees is nowhere near the sixty the check allows.
			var yaw := PAD_FAN * signf(x)
			pad.transform = Transform3D(Basis(Vector3.UP, yaw),
				Vector3(x, DECK + PAD_LIFT, z))
			root.add_child(pad)
			index += 1


# ----------------------------------------------------------------- markers ---

## Everything units 3, 4 and 5 hang off. See the header for the contract.
func _build_markers() -> void:
	var bases := _marker_root("Bases")
	for team: int in BASE_AT.size():
		var at: Vector2 = BASE_AT[team]
		_marker(bases, "Team%d" % (team + 1), Vector3(at.x, 0.0, at.y), PI,
			{"zone": "capture"})
	var letters := _marker_root("Letters")
	for i: int in 3:
		var at: Vector2 = LETTER_AT[i]
		_marker(letters, ["B", "O", "G"][i], Vector3(at.x, 0.0, at.y), 0.0,
			{"zone": "capture"})

	var racks := _marker_root("Racks")
	for entry: Dictionary in RACKS:
		var at: Vector2 = entry["at"]
		_marker(racks, "Rack_%s" % entry["weapon"], Vector3(at.x, 0.0, at.y), PI,
			{"weapon": entry["weapon"], "zone": "lodge"})

	var wells := _marker_root("Wells")
	for entry: Dictionary in WELLS:
		var at: Vector2 = entry["at"]
		_marker(wells, "Well_%s" % entry["kind"], Vector3(at.x, 0.0, at.y), PI,
			{"kind": entry["kind"], "zone": "lodge"})

	var signs := _marker_root("Signs")
	_marker(signs, "Sign_%s_%s" % [SIGNBOARD["zone"], SIGNBOARD["action"]],
		SIGNBOARD["at"], SIGN_YAW,
		{"action": SIGNBOARD["action"], "zone": SIGNBOARD["zone"]})

	var plates := _marker_root("Plates")
	for entry: Dictionary in PLATES:
		_marker(plates, "Plate_%s" % entry["role"], entry["at"], PI,
			{"role": entry["role"], "zone": entry["zone"]})

	var boards := _marker_root("Boards")
	for entry: Dictionary in BOARDS:
		# On the back wall, facing north down the deck at the people on it.
		_marker(boards, "Board_%s" % entry["kind"], entry["at"], 0.0,
			{"kind": entry["kind"], "zone": "lodge"})

	_build_target_markers()
	_build_dummy_markers()


## The boards and the gong. A board stands `BOARD_OFFSET` off its lane's centre
## line so it never hides the dummy at the same distance.
##
## There was a ninth target here, `Target_orb_launcher`: a housing at the far
## end of the bow lane that threw unshaded emissive spheres on a parabola across
## it. It is gone, with the two scripts behind it. It was the one thing on the
## range you shot at that was not a thing — see the note above `TORCHES`.
func _build_target_markers() -> void:
	var root := _marker_root("Targets")
	for i: int in 3:
		var centre := _lane_centre(i)
		for mark: float in LANE_BOARDS:
			_marker(root, "Target_board_small_%d_%d" % [i, int(mark)],
				Vector3(centre + BOARD_OFFSET, 0.0, LANE_FIRING_Z - mark), PI,
				{"kind": "board_small", "zone": "lanes", "range_m": mark,
					"lane": "wme"[i]})
	_marker(root, "Target_gong", Vector3(_lane_centre(1), 0.0, LANE_FIRING_Z - GONG_RANGE),
		PI, {"kind": "gong", "zone": "lanes", "range_m": GONG_RANGE, "lane": "m"})
	_marker(root, "Target_board_large",
		Vector3(2.5, 0.0, LONG_FIRING_Z - LONG_BOARD), PI,
		{"kind": "board_large", "zone": "long", "range_m": LONG_BOARD})


## The dummy stations. The lanes' and the bow lane's are generated off the same
## distance tables the posts are, because a dummy that does not stand on the
## mark its post claims is the one lie a range must not tell.
func _build_dummy_markers() -> void:
	# `DummyStations`, not `Dummies`, and that is not a preference. Unit 1's
	# `RangeDummies` node — the registry every brain in unit 3 reaches through —
	# is itself added as a child called `Dummies`, and `playthrough.gd` asserts
	# `map.get_node("Dummies") is RangeDummies`. A marker group of the same name
	# wins the lookup, the assert fails, and Godot quietly renames the loser.
	# The station is not the dummy anyway: this group is where a dummy *stands*,
	# and half of them have no dummy on them at all.
	var root := _marker_root("DummyStations")
	# **One behaviour per lane, authored here and fixed.** With the stations gone
	# a zone's mix is a property of the place, so the three throwing lanes are
	# three lessons standing side by side and you pick one by walking to it:
	#
	#   lane 1 (west)   `stand` at 8, 15, 22 and 28 m. The still lane — the one
	#                   you range-find on, and the one you take a new weapon to.
	#   lane 2 (middle)  `strafe` at all three marks. The lead lane; the gong at
	#                   28 m is at the end of it. Each strafer shuttles 2.4 m
	#                   either side of the lane's centre line, which is the
	#                   brain's own default for this zone and keeps the capsule
	#                   well inside a 6 m lane.
	#   lane 3 (east)   `patrol` at 8 and 22 m — a walk with a pause at each end,
	#                   which is a timing problem rather than a lead one — and a
	#                   `popup` at 15 m, which is the one mark on the map with a
	#                   1.25 m cover block half a metre in front of it.
	#
	# Written as a lookup rather than as three copies of the loop, because the
	# lane index and the distance mark are the two things that must not drift
	# from the posts they are generated beside.
	var lane_brains: Array[Dictionary] = [
		{8.0: "stand", 15.0: "stand", 22.0: "stand"},
		{8.0: "strafe", 15.0: "strafe", 22.0: "strafe"},
		{8.0: "patrol", 15.0: "popup", 22.0: "patrol"},
	]
	for i: int in 3:
		var centre := _lane_centre(i)
		for mark: float in LANE_DUMMIES:
			_dummy(root, Vector3(centre, 0.0, LANE_FIRING_Z - mark), PI,
				{"brain": String(lane_brains[i].get(mark, "stand")), "zone": "lanes",
					"range_m": mark, "lane": "wme"[i]})
	_dummy(root, Vector3(0.0, 0.0, LONG_FIRING_Z - LONG_DUMMY), PI,
		{"brain": "stand", "zone": "long", "range_m": LONG_DUMMY, "lane": ""})
	# The magnet clump: five in a plus, `CLUMP_GAP` apart, so one magnet thrown
	# into the middle of it is inside the grip radius of more than one of them.
	# Generated rather than written out for the reason the lanes are — the shape
	# is the point, and five coordinates that can drift out of a plus are five
	# coordinates that will.
	for offset: Vector2 in [Vector2.ZERO, Vector2(-CLUMP_GAP, 0.0),
			Vector2(CLUMP_GAP, 0.0), Vector2(0.0, -CLUMP_GAP), Vector2(0.0, CLUMP_GAP)]:
		var spot := CLUMP_AT + offset
		_dummy(root, Vector3(spot.x, 0.0, spot.y), PI,
			{"brain": "stand", "zone": "yard", "range_m": 0.0, "lane": ""})
	for entry: Dictionary in DUMMIES:
		var at: Vector3 = entry["at"]
		var yaw := PI
		if String(entry["zone"]) == "melee":
			# A pit dummy faces the middle of the ring, not the south.
			yaw = Bog.yaw_towards(
				(Vector3(16.0, at.y, -7.0) - at).normalized() * Vector3(1.0, 0.0, 1.0))
		_dummy(root, at, yaw, {
			"brain": entry["brain"], "zone": entry["zone"],
			"range_m": float(entry["range"]), "lane": String(entry.get("lane", "")),
			"live": bool(entry.get("live", true))})


func _dummy(root: Node3D, at: Vector3, yaw: float, meta: Dictionary) -> void:
	var live := bool(meta.get("live", true))
	meta["live"] = live
	var name_of := "Dummy_%s_%d" % [meta["zone"], dummy_markers]
	_marker(root, name_of, at, yaw, meta)
	dummy_markers += 1
	if live:
		dummies_live += 1


func _marker(root: Node3D, node_name: String, at: Vector3, yaw: float,
		meta: Dictionary) -> void:
	var marker := Marker3D.new()
	marker.name = node_name
	marker.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	for key: String in meta:
		marker.set_meta(key, meta[key])
	root.add_child(marker)


func _marker_root(node_name: String) -> Node3D:
	var root := get_node_or_null(node_name) as Node3D
	if root == null:
		root = Node3D.new()
		root.name = node_name
		add_child(root)
	return root


func _count(node_name: String) -> int:
	var root := get_node_or_null(node_name)
	return 0 if root == null else root.get_child_count()


static func _lane_centre(index: int) -> float:
	return (LANE_LINES[index] + LANE_LINES[index + 1]) * 0.5


# ---------------------------------------------------------------- dressing ---

func _build_torches(parent: Node3D) -> void:
	var group := _group("Torches", parent)
	for i: int in TORCHES.size():
		var entry: Dictionary = TORCHES[i]
		var at: Vector2 = entry["at"]
		# The phase is the index times an irrational-ish step, as the island's
		# is, so no two torches ever pulse together.
		var torch := Torch.create(float(i) * 0.6180339887 * TAU, bool(entry["shadows"]))
		torch.name = "Torch%d" % i
		torch.position = Vector3(at.x, 0.0, at.y)
		group.add_child(torch)


## Reed, bloom, snag and pebble out of the MegaKit, in MultiMeshes. Dressing, so
## none of it is collision; and nothing goes in a lane, in a landing's radius or
## within four metres of a pad, which `_prop_allowed` is the whole of.
func _build_props(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = PROP_SEED
	var batch: Dictionary = {}
	for i: int in 900:
		var at := Vector2(rng.randf_range(WEST + 2.5, EAST - 1.0),
			rng.randf_range(NORTH + 1.0, SOUTH - 2.5))
		if not _prop_allowed(at):
			continue
		var models := REED_MODELS if rng.randf() < 0.65 else BLOOM_MODELS
		var model := models[rng.randi() % models.size()]
		var scale := rng.randf_range(0.7, 1.35)
		var xform := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(scale, scale * rng.randf_range(0.9, 1.5), scale)),
			Vector3(at.x, 0.0, at.y))
		var into: Array = batch.get(model, [])
		into.append(xform)
		batch[model] = into

	# Pebbles along the parkour, so the course reads as a thing somebody laid
	# out rather than as slabs in a bog.
	for entry: Dictionary in PARKOUR:
		var at: Vector2 = entry["at"]
		for k: int in 3:
			var spot := at + Vector2(rng.randf_range(-2.2, 2.2), rng.randf_range(-2.2, 2.2))
			if not _prop_allowed(spot):
				continue
			var model := PEBBLE_MODELS[rng.randi() % PEBBLE_MODELS.size()]
			var into: Array = batch.get(model, [])
			into.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU),
				Vector3(spot.x, 0.0, spot.y)))
			batch[model] = into

	var props := _group("Props", parent)
	for model: String in batch:
		_scattered(props, model, batch[model], false)

	# And the snags: dead trees along the west bank and out past the void lips,
	# where being tall is the only thing that matters. Backdrop, so
	# `preview_map` keeps framing the bog rather than the horizon (D-057).
	var far: Dictionary = {}
	for i: int in 34:
		var edge := rng.randi() % 3
		var at := Vector2(WEST - rng.randf_range(2.0, 22.0),
			rng.randf_range(NORTH - 4.0, SOUTH)) if edge == 0 \
			else Vector2(rng.randf_range(WEST - 10.0, EAST + 22.0),
				NORTH - rng.randf_range(4.0, 26.0)) if edge == 1 \
			else Vector2(EAST + rng.randf_range(4.0, 26.0),
				rng.randf_range(NORTH, SOUTH))
		var model := SNAG_MODELS[rng.randi() % SNAG_MODELS.size()]
		var scale := rng.randf_range(1.1, 2.1)
		var into: Array = far.get(model, [])
		into.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(scale, scale * rng.randf_range(1.2, 1.9), scale)),
			Vector3(at.x, -0.6, at.y)))
		far[model] = into
	# **And they cast no shadow**, which they used to. Under an 11-degree moon due
	# north they stood north of the map and shadowed away from it. Under a sun
	# north-north-east they stand *up-sun* of it, and a shadow is 1.60 times the
	# height of the thing casting it at 32 degrees (it was 6.31 at nine): a
	# fifteen-metre snag four metres past the north lip still lays twenty-four
	# metres of darkness south-south-west onto the range, and thirty-four of them
	# lay it in bands. Raising the sun shortened the problem and did not solve it,
	# which is why this line stays. The top-down render is what showed it — two
	# thirds of the bog under the shadow of trees that are not even on the map at
	# nine degrees, the north end of it at thirty-two. It is the same argument
	# `range.tscn` makes about the west bank's azimuth, applied to dressing:
	# scenery outside the play space does not get to decide the light inside it.
	# The cost is the shafts these threw through the volumetric fog, which were
	# lovely and which a range cannot pay for in readable ground.
	var horizon := _group("Horizon", parent)
	horizon.add_to_group(BACKDROP_GROUP)
	for model: String in far:
		var node := _scattered(horizon, model, far[model], false)
		if node != null:
			node.add_to_group(BACKDROP_GROUP)


## Nowhere a prop may stand: in a lane, on a landing, on the apron's fittings,
## on the deck, in the pit, or within four metres of a pad.
func _prop_allowed(at: Vector2) -> bool:
	if at.x > LANE_LINES[0] - 0.6 and at.x < LANE_LINES[3] + 0.6 \
			and at.y < LANE_FIRING_Z + 1.0 and at.y > LANE_FIRING_Z - LANE_LENGTH - 1.0:
		return false
	if at.x > LONG_LINES[0] - 0.6 and at.x < LONG_LINES[1] + 0.6 \
			and at.y < LONG_FIRING_Z + 1.0 and at.y > LONG_FIRING_Z - LONG_LENGTH - 1.0:
		return false
	if at.x > PIT_X.x - 1.0 and at.x < PIT_X.y + 1.0 \
			and at.y > PIT_Z.x - 1.0 and at.y < PIT_Z.y + 1.0:
		return false
	if at.x > LODGE_X.x - 5.0 and at.x < LODGE_X.y + 5.0 and at.y > LODGE_Z.x - 6.0:
		return false
	if at.y > LANE_FIRING_Z - 1.0 and at.y < LODGE_Z.x:
		return false   # the apron: racks, wells, stations and the walking line
	for platform: Platform in platforms:
		if at.distance_to(Vector2(platform.centre.x, platform.centre.z)) \
				< platform.radius + 1.2:
			return false
	for spot: Vector2 in [GALLERY_MARK, CLUMP_AT]:
		if at.distance_to(spot) < 4.0:
			return false
	return true


func _scattered(parent: Node3D, model: String, transforms: Array,
		shadows: bool) -> MultiMeshInstance3D:
	var mesh := PropScatter.load_kit_mesh(model)
	if mesh == null or transforms.is_empty():
		return null
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
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


# ------------------------------------------------------------------ shapes ---

## A box, and the landing records on top of it, in one call — so a piece of
## cover cannot be built without the checker hearing about it. That is the rule
## D-084 states: every flat top a Bog's capsule can find a floor on is a
## declared `Platform`, because undeclared standable geometry is invisible to
## `parkour_report` and that is the failure it exists to prevent.
func _block(st: SurfaceTool, at: Vector2, size: Vector2, top: float,
		zone: String, label: String) -> void:
	_slab(st, at - size * 0.5, at + size * 0.5, 0.0, top)
	var inscribed := minf(size.x, size.y) * 0.5 - LIP
	if size.x > size.y * 2.5:
		# A long wall gets a record at each end: one circle in the middle of a
		# six-metre wall would call its two ends unlandable, which is the
		# argument `wharf_map.LANDING_OFFSET` makes about a container.
		for end: int in 2:
			var x := at.x + (size.x * 0.5 - inscribed - LIP) * (1.0 if end == 0 else -1.0)
			platforms.append(Platform.new(Vector3(x, top, at.y), inscribed, zone,
				"%s %s" % [label, "ab"[end]]))
		return
	platforms.append(Platform.new(Vector3(at.x, top, at.y), inscribed, zone, label))


## One axis-aligned box, in world space, from (lo, base) to (hi, top).
func _slab(st: SurfaceTool, lo: Vector2, hi: Vector2, base: float, top: float) -> void:
	var a := Vector3(lo.x, base, lo.y)
	var b := Vector3(hi.x, base, lo.y)
	var c := Vector3(hi.x, base, hi.y)
	var d := Vector3(lo.x, base, hi.y)
	var e := Vector3(lo.x, top, lo.y)
	var f := Vector3(hi.x, top, lo.y)
	var g := Vector3(hi.x, top, hi.y)
	var h := Vector3(lo.x, top, hi.y)
	# Godot winds a **front** face clockwise as seen from the front. The four
	# sides below came out that way by writing them top-left round; the top and
	# the bottom did not, and the first top-down render of this map was a black
	# rectangle with the melee pit glowing in it because every horizontal face on
	# the map was being culled. Nothing else noticed: collision is a trimesh with
	# `backface_collision` on (`static_map.gd`), so the parkour report walked a
	# floor that could not be seen and passed. That is the whole argument for
	# photographing a map as well as checking it.
	_quad(st, e, f, g, h, Vector3.UP)
	_quad(st, d, c, b, a, Vector3.DOWN)
	_quad(st, e, f, b, a, Vector3.FORWARD)
	_quad(st, g, h, d, c, Vector3.BACK)
	_quad(st, h, e, a, d, Vector3.LEFT)
	_quad(st, f, g, c, b, Vector3.RIGHT)


## A prism whose top slopes along one axis. The only climbable slope a Bog has,
## since it has no step-up (D-057, D-082).
func _ramp(st: SurfaceTool, lo: Vector2, hi: Vector2, low_y: float, high_y: float,
		along: String, thickness: float) -> void:
	var steps := 8
	for i: int in steps:
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var y0 := lerpf(low_y, high_y, t0)
		var y1 := lerpf(low_y, high_y, t1)
		var floor_y := minf(y0, y1) - thickness
		if along == "x":
			_slab(st, Vector2(lerpf(lo.x, hi.x, t0), lo.y),
				Vector2(lerpf(lo.x, hi.x, t1), hi.y), floor_y, maxf(y0, y1))
		else:
			_slab(st, Vector2(lo.x, lerpf(lo.y, hi.y, t0)),
				Vector2(hi.x, lerpf(lo.y, hi.y, t1)), floor_y, maxf(y0, y1))


## A square post. Square rather than round because it is eight triangles instead
## of forty-eight, and there were eighty of them on this map before the lane
## posts came off. The forty-eight left are the void railing's and the one
## signpost at its gap, and the reason still holds: a post is a stick, not a
## lathe job.
func _post(st: SurfaceTool, at: Vector2, half: float, height: float) -> void:
	_slab(st, at - Vector2(half, half), at + Vector2(half, half), 0.0, height)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		normal: Vector3) -> void:
	# UVs in metres off the two axes the face is not flat in, so one material
	# tiles across the whole map without a per-piece scale.
	var uvs := [_uv(a, normal), _uv(b, normal), _uv(c, normal), _uv(d, normal)]
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		for k: int in 3:
			var index: int = tri[k]
			st.set_normal(normal)
			st.set_uv(uvs[index])
			st.add_vertex([a, b, c, d][index])


static func _uv(at: Vector3, normal: Vector3) -> Vector2:
	if absf(normal.y) > 0.5:
		return Vector2(at.x, at.z) * 0.5
	if absf(normal.x) > 0.5:
		return Vector2(at.z, -at.y) * 0.5
	return Vector2(at.x, -at.y) * 0.5


func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _commit(parent: Node3D, named: String, st: SurfaceTool,
		material: Material) -> void:
	st.generate_tangents()
	var node := MeshInstance3D.new()
	node.name = named
	node.mesh = st.commit()
	node.material_override = material
	parent.add_child(node)


func _group(named: String, under: Node3D = null) -> Node3D:
	var node := Node3D.new()
	node.name = named
	(under if under != null else self).add_child(node)
	return node


# --------------------------------------------------------------- materials ---

## Three, and they are the map's whole palette: wet peat, tarred timber and the
## pale cut stone the Elders line a training ground with. The atmosphere is in
## the sky, the fog and the torches (D-058); a range whose materials are doing
## the work is a range you cannot see the distance marks on.
##
## **Every one of these is about twice as bright as the island's ground, and
## that is measured rather than preferred.** The first pass used the Hollow's
## own values — peat at 0.085 albedo under a 0.30 moon — and the render came
## back with the bottom half of the frame at literal black: the moon read
## beautifully and the ground under it did not exist. On
## the island that is correct, because torches are the key light (D-009) and the
## island is 50 m across, so everything that matters is inside a torch pool. A
## torch pool is 10.5 m and this map is 90 m long: nine tenths of the ground
## here has no torch anywhere near it, and a range whose ground you cannot see
## is not a range. So the peat is a wet brown you can read a 1.25 m block
## against, and the sun does the work — see `range.tscn`'s `Sun`.
func _build_materials() -> void:
	_peat_material = _matte(Color(0.21, 0.165, 0.125), 0.96, 0x9E01, 0.9)
	_timber_material = _matte(Color(0.23, 0.175, 0.125), 0.9, 0x9E02, 3.5)
	_stone_material = _matte(Color(0.52, 0.53, 0.47), 0.82, 0x9E03, 2.2)


func _matte(tint: Color, rough: float, seed: int, frequency: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = rough
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.uv1_scale = Vector3.ONE
	# Grain, so a sixty-metre lane of one colour still has somewhere for the eye
	# to land. A noise texture rather than an image: nothing here needs a photo.
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = frequency * 0.01
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.as_normal_map = true
	texture.bump_strength = 1.6
	material.normal_enabled = true
	material.normal_texture = texture
	material.normal_scale = 0.55
	return material
