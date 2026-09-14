class_name YachtMap
extends StaticMap
## Halcyon Wake — a superyacht at anchor on open water on a bright morning,
## built in code from layout tables the way Kopje Crossing and Lantern Wharf are
## (D-042, D-056, D-057).
##
## It is the map that goes *up*. Kopje Crossing is a rock garden you climb and
## Lantern Wharf is a yard you run through; this is four decks stacked on one
## hull, and the fight is about who holds which deck:
##
##   main deck     y = 0. The foredeck with the tender on it (Team 1's base),
##                 two side walkways under the upper deck's overhang, an open
##                 salon cut straight through the deckhouse, and the aft deck
##                 (Team 2's base) with the swim platform a metre below it.
##   upper deck    y = 3.2. A forward balcony, two side walkways and an aft
##                 terrace round the upper deckhouse.
##   sun deck      y = 6.2. Loungers, a hot tub, and G.
##   flybridge     y = 8.8. The small open top, under the mast.
##
## **Every deck has two ways up and one of them is always a walk.** The Gub has
## no step-up, so a staircase is a ramp in the collision (`floor_max_angle` is
## 52 degrees and every ramp here is under 30) and a flight of treads in the
## render. The other way up is a stack of hop steps, each a metre or so, so a
## player who knows the map climbs faster than one who takes the stairs:
##
##   main  -> upper   twin stairs up from the aft deck; hop steps at the
##                    deckhouse's forward face, off the foredeck.
##   upper -> sun     a stair up the middle of the aft terrace; hop steps at the
##                    upper deckhouse's forward face, off the balcony.
##   sun   -> fly     hop steps either side at the flybridge's aft face.
##
## `tools/parkour_report.gd` walks the Gub's real jump arc over every landing
## declared here and fails the build if any deck is stranded, and proves the
## mast is out of reach of every jump including the one-tick dive.
##
## **The water is the void.** The hull stands on nothing: there is no collision
## below the waterline and no floor anywhere off the side, and `void_height`
## sits half a metre under the water's surface, so a Gub that goes over the
## rail disappears into the sea and dies there. The report checks that from
## every edge of the deck.
##
## Build order is the other built maps': everything added before `super()` is
## swept into collision, everything after is dressing. Nothing is random, so
## every peer builds the same yacht by construction.
##
## The dressing is most of this file now, and it is what makes the map a place
## rather than a model on a table (the atmosphere pass). In build order:
##
##   windows      dark glass bands round every deckhouse and a row of hull
##                lights along the owner's deck.
##   treads       the stairs' picture; their collision is a smooth ramp.
##   details      the radar, the hot tub's water, the sheer line.
##   sea          `_build_sea`, and it is the whole map. A displaced grid out to
##                120 m with `yacht_sea.gdshader` on it: three sine waves in the
##                vertex shader, four more per fragment, a Cox-Munk sun track
##                that runs to the horizon, and the hull's foam and the shadow
##                of her underwater body as a distance field rather than as
##                geometry. 18,432 triangles, one draw call, no textures.
##   anchorage    `_build_horizon`. Three headlands at three distances on the
##                port side and three other boats at anchor, so that being 8.8 m
##                up on the flybridge shows you somewhere and not a gradient.
##                About 900 triangles, all of it in `BACKDROP_GROUP`.
##   wind         `_build_wind`. The ensign at the transom, the burgee at the
##                masthead, and the cable leading forward off the stem into the
##                water. Everything that moves in the wind agrees with the
##                swell's direction, because a yacht at anchor lies head to it.
##   ambience     `YachtAmbience`. Six gulls on six circles, steam off the hot
##                tub, and the audio hooks.
##
## Everything above costs, in total: one extra draw call for the sea, one for
## the anchorage, one for the rigging, two for the flags, six for the gulls, one
## particle system of 32, and one more directional light with no shadow map.

# ------------------------------------------------------------------ levels ---

## The four deck heights and the swim platform, top of floor.
const MAIN_Y := 0.0
const UPPER_Y := 3.2
const SUN_Y := 6.2
const FLY_Y := 8.8
const SWIM_Y := -1.0
## The sea's surface. `void_height` in `yacht.tscn` is half a metre under it.
const WATER_Y := -3.0

## A deck slab's thickness. The deckhouse under it stops this far short of the
## deck above, so the salon's ceiling is the slab's underside.
const SLAB := 0.3

# -------------------------------------------------------------------- hull ---

## The hull runs bow (-z) to stern (+z). Its deck is `BEAM` either side of the
## centreline from `TAPER_Z` aft to the transom, and narrows to a point at
## `BOW_Z` along `1 - t^BOW_SHAPE`, which is full and round at the shoulder and
## fine at the stem.
const BOW_Z := -36.0
const TAPER_Z := -8.0
const STERN_Z := 26.0
const BEAM := 6.5
const BOW_SHAPE := 2.2
## The waterline is narrower than the deck and its stem further aft, which is
## what gives the bow its rake and the topsides their flare. Below it the hull
## closes to a keel nobody sees.
const WATERLINE_BEAM := 5.9
const WATERLINE_BOW_Z := -31.0
const BOOT_Y := -1.9
const KEEL_Y := -4.2
## The main deck's bulwark: a metre of solid hull above the deck all the way
## round, rising half a metre more toward the stem, and this thick.
const BULWARK := 1.0
const BULWARK_SHEER := 0.5
const BULWARK_T := 0.15

# ---------------------------------------------------------------- the table ---

## Rects are Rect2(x, z, width along x, depth along z) on the deck plan.

## The main deckhouse: a forward block and an aft block with the salon open
## between them, full width and both sides, so the one indoor space on the map
## is nine metres across, six deep and open to the sky at both ends.
const HOUSE_FORE := Rect2(-4.5, -10.0, 9.0, 6.5)
const HOUSE_AFT := Rect2(-4.5, 2.5, 9.0, 9.5)
## The upper deck, over both blocks and the salon and a metre out over each main
## walkway.
const UPPER_DECK := Rect2(-5.5, -10.0, 11.0, 22.0)
## The pillar either side of the salon that fills the main walkway for two
## metres. It holds the upper deck up, and it is what stops the walkway being a
## 45 m lane from the foredeck to the aft deck: the way past is a step into the
## salon and back out.
const WALK_PILLAR_Z := Vector2(-1.5, 0.5)
## The upper deckhouse and the sun deck on it, which overhangs it a metre each
## side and three metres aft over the terrace.
const UPPER_HOUSE := Rect2(-3.5, -6.0, 7.0, 9.0)
const SUN_DECK := Rect2(-4.5, -6.0, 9.0, 12.0)
## The flybridge: a house on the sun deck whose roof is the top deck.
const FLYBRIDGE := Rect2(-2.5, -4.0, 5.0, 3.5)
## The mast on the flybridge. Its yard and its top are `off_limits`: from 8.8 m
## the dive reaches 13.03 m, and the yard is at 13.4.
const MAST_AT := Vector2(0.0, -3.5)
const MAST_TOP := 14.2
const MAST_YARD := 13.4

## Hop steps, as (rect, top). Written for the starboard side and mirrored across
## x = 0. Each is flush against the thing it is a step onto, and each rise is
## 1.0-1.3 m, which is a hop — the jump clears 1.69 m.
const STEPS: Array[Dictionary] = [
	# Foredeck to the upper deck's forward balcony.
	{"label": "fore step 1", "rect": Rect2(1.2, -13.2, 1.6, 1.6), "base": MAIN_Y, "top": 1.1},
	{"label": "fore step 2", "rect": Rect2(1.2, -11.6, 1.6, 1.6), "base": MAIN_Y, "top": 2.2},
	# Balcony to the sun deck, sideways along the upper deckhouse's face.
	{"label": "balcony step 1", "rect": Rect2(2.4, -7.6, 1.6, 1.6), "base": UPPER_Y, "top": 4.3},
	{"label": "balcony step 2", "rect": Rect2(0.8, -7.6, 1.6, 1.6), "base": UPPER_Y, "top": 5.3},
	# Sun deck to the flybridge.
	{"label": "fly step", "rect": Rect2(1.0, -0.5, 1.4, 1.4), "base": SUN_Y, "top": 7.5},
]

## Stairs, as a ramp from `foot` (z at `base`) up to `head` (z at `top`) across
## `x`. `mirror` stairs are written for starboard and built both sides.
const STAIRS: Array[Dictionary] = [
	# Aft deck to the aft terrace, one each side of the aft deckhouse's door.
	{"label": "aft stair", "x": Vector2(1.5, 3.5), "foot": 18.5, "head": 12.0,
		"base": MAIN_Y, "top": UPPER_Y, "mirror": true},
	# Aft terrace to the sun deck, up the middle.
	{"label": "terrace stair", "x": Vector2(-0.9, 0.9), "foot": 11.5, "head": 6.0,
		"base": UPPER_Y, "top": SUN_Y, "mirror": false},
]
## One tread every this much rise, in the render.
const TREAD_RISE := 0.2

## Rails: Rect2(from x, from z, run along x, run along z) at a deck's height, a metre tall, with the
## gaps where a stair or a step arrives left out. Collision, all of them — a rail
## is what stops a Gub backing off a deck in the middle of a fight. Jumping over
## one is a hop, so going overboard on purpose is always possible.
const RAILS: Array[Dictionary] = [
	{"y": UPPER_Y, "runs": [
		# Forward edge, with the fore steps' gaps.
		Rect2(-5.5, -10.0, 2.7, 0.0), Rect2(-1.2, -10.0, 2.4, 0.0), Rect2(2.8, -10.0, 2.7, 0.0),
		# Sides.
		Rect2(-5.5, -10.0, 0.0, 22.0), Rect2(5.5, -10.0, 0.0, 22.0),
		# Aft edge, with the aft stairs' gaps.
		Rect2(-5.5, 12.0, 2.0, 0.0), Rect2(-1.5, 12.0, 3.0, 0.0), Rect2(3.5, 12.0, 2.0, 0.0),
	]},
	{"y": SUN_Y, "runs": [
		Rect2(-4.5, -6.0, 2.1, 0.0), Rect2(-0.8, -6.0, 1.6, 0.0), Rect2(2.4, -6.0, 2.1, 0.0),
		Rect2(-4.5, -6.0, 0.0, 12.0), Rect2(4.5, -6.0, 0.0, 12.0),
		Rect2(-4.5, 6.0, 3.6, 0.0), Rect2(0.9, 6.0, 3.6, 0.0),
	]},
	{"y": FLY_Y, "runs": [
		Rect2(-2.5, -4.0, 5.0, 0.0),
		Rect2(-2.5, -4.0, 0.0, 3.5), Rect2(2.5, -4.0, 0.0, 3.5),
		Rect2(-1.0, -0.5, 2.0, 0.0),
	]},
	# The transom, either side of the steps down to the swim platform.
	{"y": MAIN_Y, "runs": [
		Rect2(-BEAM + BULWARK_T, STERN_Z, BEAM - BULWARK_T - 3.0, 0.0),
		Rect2(3.0, STERN_Z, BEAM - BULWARK_T - 3.0, 0.0),
	]},
]
const RAIL_HEIGHT := 1.0
const RAIL_T := 0.1

## The swim platform, a metre under the aft deck, and the step down onto it.
## No rail: it is the one edge of the yacht that is meant to be walked off.
const SWIM_PLATFORM := Rect2(-5.0, 26.0, 10.0, 3.8)
const SWIM_STEP := Rect2(-3.0, 26.0, 6.0, 0.9)

## Things on the decks that are cover, as (rect, base, height). Low ones are
## crouch cover; the tender and the crane pedestals are tall enough to break a
## line at eye height, which is what they are there for.
const FURNITURE: Array[Dictionary] = [
	# The tender on its chocks on the foredeck. Blocks the long line down the
	# middle of the bow, and it is a perch you can leap onto.
	{"label": "tender", "rect": Rect2(-1.1, -33.0, 2.2, 5.0), "base": MAIN_Y, "top": 1.9,
		"kind": "tender", "landing": true},
	# The salon's bar, between U and B.
	{"label": "bar", "rect": Rect2(-1.25, -1.05, 2.5, 1.1), "base": MAIN_Y, "top": 1.0,
		"kind": "bar"},
	# The aft deck's bar against the aft deckhouse, between the stairs.
	{"label": "aft bar", "rect": Rect2(-1.5, 12.0, 3.0, 1.0), "base": MAIN_Y, "top": 1.1,
		"kind": "bar"},
	# The aft deck's sofa.
	{"label": "aft sofa", "rect": Rect2(-2.2, 22.4, 4.4, 0.9), "base": MAIN_Y, "top": 0.8,
		"kind": "cushion"},
	# Crane pedestals at the aft end of each main walkway, which is the second
	# thing that keeps the walkway from being a lane.
	{"label": "crane W", "rect": Rect2(-6.35, 21.0, 1.45, 1.5), "base": MAIN_Y, "top": 2.4,
		"kind": "white"},
	{"label": "crane E", "rect": Rect2(4.9, 21.0, 1.45, 1.5), "base": MAIN_Y, "top": 2.4,
		"kind": "white"},
	# On the sun deck: the sun pad in the starboard aft corner.
	{"label": "sun pad", "rect": Rect2(2.35, 3.85, 2.0, 2.0), "base": SUN_Y, "top": SUN_Y + 0.45,
		"kind": "cushion", "landing": true},
]
## The hot tub in the port aft corner of the sun deck. A cylinder, landable.
const TUB_AT := Vector2(-3.25, 4.75)
const TUB_RADIUS := 1.1
const TUB_HEIGHT := 0.55

## How far apart the landing records on an open deck are. A deck is not one
## landing: the report reads a landing as a circle, and a circle big enough to
## cover a deck promises floor over the side of it.
const TILE := 2.2
const TILE_RADIUS := 1.0
## A landing record is kept this far clear of anything standing on its deck, so a
## Gub-sized capsule fits on every one of them.
const TILE_CLEAR := 0.55

## Stair landings sit this far over the ramp's surface, so the report's capsule
## at the record is not buried in the slope uphill of it: 0.38 m of capsule
## radius on a 30 degree slope needs 0.06.
const RAMP_LIFT := 0.08

# ------------------------------------------------------------------ colours ---

const HULL_WHITE := Color(0.93, 0.93, 0.91)
const BULWARK_WHITE := Color(0.88, 0.89, 0.88)
const BOOT_NAVY := Color(0.06, 0.12, 0.24)
const ANTIFOUL := Color(0.30, 0.08, 0.07)
const HOUSE_WHITE := Color(0.95, 0.95, 0.93)
const CUSHION := Color(0.86, 0.82, 0.72)
const CUSHION_ACCENT := Color(0.10, 0.28, 0.46)
const BAR_WOOD := Color(0.42, 0.26, 0.15)
const TENDER_COVER := Color(0.12, 0.22, 0.36)

# ------------------------------------------------------------------ state ---

var _paint: StandardMaterial3D
var _teak: StandardMaterial3D
var _glass: StandardMaterial3D
var _window: StandardMaterial3D
var _chrome: StandardMaterial3D
var _land: StandardMaterial3D
var _water_material: ShaderMaterial

var _hull_st: SurfaceTool
var _house_st: SurfaceTool
var _deck_st: SurfaceTool
var _glass_st: SurfaceTool
var _chrome_st: SurfaceTool
var _ramp_st: SurfaceTool


func _ready() -> void:
	var started := Time.get_ticks_msec()
	_build_materials()
	_hull_st = _begin()
	_house_st = _begin()
	_deck_st = _begin()
	_glass_st = _begin()
	_chrome_st = _begin()
	_ramp_st = _begin()

	_build_hull()
	_build_decks()
	_build_steps()
	_build_stairs()
	_build_rails()
	_build_furniture()
	_build_mast()
	_declare_landings()

	var solid := _group("Yacht")
	_commit(solid, "Hull", _hull_st, _paint)
	_commit(solid, "Superstructure", _house_st, _paint)
	_commit(solid, "Decks", _deck_st, _teak)
	_commit(solid, "RailGlass", _glass_st, _glass)
	_commit(solid, "Chrome", _chrome_st, _chrome)
	# The stairs' collision is a smooth ramp and their picture is a flight of
	# treads, so the ramp is swept into collision and never drawn.
	var ramps := _commit(solid, "StairRamps", _ramp_st, _paint)
	ramps.visible = false

	print("%s: %d landings, %d off limits in %d ms" % [name, platforms.size(), off_limits.size(),
		Time.get_ticks_msec() - started])

	# Everything above this line becomes collision. Everything below it does not.
	super()

	var dressing := _group("Dressing")
	_build_treads(dressing)
	_build_windows(dressing)
	_build_details(dressing)
	_build_sea(dressing)
	_build_horizon(dressing)
	_build_wind(dressing)
	YachtAmbience.build(dressing)


# ------------------------------------------------------------------- hull ---

## Half the deck's width at `z`.
static func deck_half_width(z: float) -> float:
	if z >= TAPER_Z:
		return BEAM
	var t := clampf((TAPER_Z - z) / (TAPER_Z - BOW_Z), 0.0, 1.0)
	return BEAM * (1.0 - pow(t, BOW_SHAPE))


static func waterline_half_width(z: float) -> float:
	if z >= TAPER_Z:
		return WATERLINE_BEAM
	var t := (TAPER_Z - z) / (TAPER_Z - WATERLINE_BOW_Z)
	if t >= 1.0:
		return 0.0
	return WATERLINE_BEAM * (1.0 - pow(t, 2.0))


static func bulwark_top(z: float) -> float:
	var t := clampf((TAPER_Z - z) / (TAPER_Z - BOW_Z), 0.0, 1.0)
	return BULWARK + BULWARK_SHEER * t * t


## The hull as a loft of cross-sections from the stem to the transom: keel,
## waterline, boot top, deck edge, bulwark top, and the bulwark's inside face
## back down to the deck, which is laid between the two inside faces.
func _build_hull() -> void:
	var stations: Array[float] = []
	var z := BOW_Z
	while z < TAPER_Z:
		stations.append(z)
		z += 1.0
	z = TAPER_Z
	while z < STERN_Z:
		stations.append(z)
		z += 4.0
	stations.append(STERN_Z)

	for i: int in stations.size() - 1:
		var za := stations[i]
		var zb := stations[i + 1]
		var a := _section(za)
		var b := _section(zb)
		for side: float in [-1.0, 1.0]:
			# Outside of the hull, keel to bulwark top.
			var colours: Array[Color] = [ANTIFOUL, BOOT_NAVY, HULL_WHITE, BULWARK_WHITE]
			for k: int in 4:
				var p0 := _at(a[k], za, side)
				var p1 := _at(a[k + 1], za, side)
				var p2 := _at(b[k + 1], zb, side)
				var p3 := _at(b[k], zb, side)
				var mid := (p0 + p1 + p2 + p3) * 0.25
				_quad(_hull_st, p0, p1, p2, p3, mid - Vector3(0.0, -1.5, mid.z), colours[k])
			# The bulwark's cap and its inside face.
			var top_a := _at(a[4], za, side)
			var top_b := _at(b[4], zb, side)
			var in_a := _at(a[5], za, side)
			var in_b := _at(b[5], zb, side)
			_quad(_hull_st, top_a, in_a, in_b, top_b, Vector3.UP, BULWARK_WHITE)
			var foot_a := _at(a[6], za, side)
			var foot_b := _at(b[6], zb, side)
			_quad(_hull_st, in_a, foot_a, foot_b, in_b, Vector3(-side, 0.0, 0.0), BULWARK_WHITE)
		# The deck, between the bulwarks' inside feet.
		var fa: Vector2 = a[6]
		var fb: Vector2 = b[6]
		_quad(_deck_st, Vector3(-fa.x, MAIN_Y, za), Vector3(fa.x, MAIN_Y, za),
			Vector3(fb.x, MAIN_Y, zb), Vector3(-fb.x, MAIN_Y, zb), Vector3.UP, Color.WHITE)

	# The transom: the last section, closed, facing aft.
	var s := _section(STERN_Z)
	for side: float in [-1.0, 1.0]:
		for k: int in 4:
			var p0 := _at(s[k], STERN_Z, side)
			var p1 := _at(s[k + 1], STERN_Z, side)
			var c := Vector3(0.0, p0.y, STERN_Z)
			var d := Vector3(0.0, p1.y, STERN_Z)
			_quad(_hull_st, p0, p1, d, c, Vector3.BACK,
				[ANTIFOUL, BOOT_NAVY, HULL_WHITE, BULWARK_WHITE][k])
		# The bulwark's thickness across the transom's top.
		var top := _at(s[4], STERN_Z, side)
		var inner := _at(s[5], STERN_Z, side)
		var foot := _at(s[6], STERN_Z, side)
		_quad(_hull_st, top, inner, foot, Vector3(top.x, MAIN_Y, STERN_Z), Vector3.BACK,
			BULWARK_WHITE)

	# The swim platform and its step, off the transom.
	_box(_house_st, Vector3(SWIM_PLATFORM.position.x, SWIM_Y - 0.4, SWIM_PLATFORM.position.y),
		Vector3(SWIM_PLATFORM.end.x, SWIM_Y, SWIM_PLATFORM.end.y), HULL_WHITE, _deck_st)
	_box(_house_st, Vector3(SWIM_STEP.position.x, SWIM_Y, SWIM_STEP.position.y),
		Vector3(SWIM_STEP.end.x, SWIM_Y + 0.5, SWIM_STEP.end.y), HULL_WHITE, _deck_st)


## One cross-section at `z`, starboard half, as (x, y): keel, waterline, boot
## top, deck edge, bulwark top, bulwark inside top, bulwark inside foot.
func _section(z: float) -> Array[Vector2]:
	var deck := deck_half_width(z)
	var water := waterline_half_width(z)
	var inner := maxf(deck - BULWARK_T, deck * 0.4)
	var top := bulwark_top(z)
	var out: Array[Vector2] = [
		Vector2(0.0, KEEL_Y),
		Vector2(water, WATER_Y - 0.4),
		Vector2(lerpf(water, deck, 0.6), BOOT_Y),
		Vector2(deck, MAIN_Y),
		Vector2(deck, top),
		Vector2(inner, top),
		Vector2(inner, MAIN_Y),
	]
	return out


static func _at(p: Vector2, z: float, side: float) -> Vector3:
	return Vector3(p.x * side, p.y, z)


# ------------------------------------------------------------------- decks ---

func _build_decks() -> void:
	# The main deckhouse, in two blocks with the salon between.
	for house: Rect2 in [HOUSE_FORE, HOUSE_AFT]:
		_box(_house_st, Vector3(house.position.x, MAIN_Y, house.position.y),
			Vector3(house.end.x, UPPER_Y - SLAB, house.end.y), HOUSE_WHITE)
	# The walkway pillars either side of the salon.
	for side: float in [-1.0, 1.0]:
		var inner := HOUSE_FORE.end.x
		var outer := BEAM - BULWARK_T
		_box(_house_st, Vector3(minf(inner * side, outer * side), MAIN_Y, WALK_PILLAR_Z.x),
			Vector3(maxf(inner * side, outer * side), UPPER_Y, WALK_PILLAR_Z.y), HOUSE_WHITE)
	_slab(UPPER_DECK, UPPER_Y)

	_box(_house_st, Vector3(UPPER_HOUSE.position.x, UPPER_Y, UPPER_HOUSE.position.y),
		Vector3(UPPER_HOUSE.end.x, SUN_Y - SLAB, UPPER_HOUSE.end.y), HOUSE_WHITE)
	_slab(SUN_DECK, SUN_Y)

	_box(_house_st, Vector3(FLYBRIDGE.position.x, SUN_Y, FLYBRIDGE.position.y),
		Vector3(FLYBRIDGE.end.x, FLY_Y, FLYBRIDGE.end.y), HOUSE_WHITE, _deck_st)


## A deck slab: teak on top, white under and round the edge.
func _slab(rect: Rect2, top: float) -> void:
	_box(_house_st, Vector3(rect.position.x, top - SLAB, rect.position.y),
		Vector3(rect.end.x, top, rect.end.y), HOUSE_WHITE, _deck_st)


func _build_steps() -> void:
	for entry: Dictionary in STEPS:
		for rect: Rect2 in _mirror_rect(entry["rect"]):
			_box(_house_st, Vector3(rect.position.x, float(entry["base"]), rect.position.y),
				Vector3(rect.end.x, float(entry["top"]), rect.end.y), HOUSE_WHITE, _deck_st)


## Each stair is a wedge in collision: a sloped top from the foot to the head
## and solid underneath, so there is no gap under it to get stuck in.
func _build_stairs() -> void:
	for entry: Dictionary in STAIRS:
		for span: Vector2 in _stair_spans(entry):
			var foot := float(entry["foot"])
			var head := float(entry["head"])
			var base := float(entry["base"])
			var top := float(entry["top"])
			var fl := Vector3(span.x, base, foot)
			var fr := Vector3(span.y, base, foot)
			var hl := Vector3(span.x, top, head)
			var hr := Vector3(span.y, top, head)
			var bl := Vector3(span.x, base, head)
			var br := Vector3(span.y, base, head)
			var toward_head := signf(head - foot)
			_quad(_ramp_st, fl, fr, hr, hl, Vector3(0.0, 1.0, -toward_head), Color.WHITE)
			_quad(_ramp_st, bl, br, hr, hl, Vector3(0.0, 0.0, toward_head), Color.WHITE)
			_quad(_ramp_st, fl, fr, br, bl, Vector3.DOWN, Color.WHITE)
			_tri(_ramp_st, fl, bl, hl, Vector3.LEFT, Color.WHITE)
			_tri(_ramp_st, fr, br, hr, Vector3.RIGHT, Color.WHITE)


func _stair_spans(entry: Dictionary) -> Array[Vector2]:
	var x: Vector2 = entry["x"]
	var out: Array[Vector2] = [x]
	if bool(entry["mirror"]):
		out.append(Vector2(-x.y, -x.x))
	return out


func _build_rails() -> void:
	for deck: Dictionary in RAILS:
		var y := float(deck["y"])
		for run: Rect2 in deck["runs"]:
			var from := Vector2(run.position.x, run.position.y)
			var to := from + run.size
			_rail(from, to, y)


## A rail from `from` to `to` on the deck plan: a white kick plate, a glass
## panel and a chrome cap, all collision, set just inside the deck's edge.
func _rail(from: Vector2, to: Vector2, y: float) -> void:
	var along_x := absf(to.x - from.x) > absf(to.y - from.y)
	var lo := Vector2(minf(from.x, to.x), minf(from.y, to.y))
	var hi := Vector2(maxf(from.x, to.x), maxf(from.y, to.y))
	# Pull the rail inside the deck: toward the centreline on a side rail, toward
	# the deck's middle on an end rail.
	if along_x:
		var inward := -signf(lo.y - _deck_centre_z(y)) if absf(lo.y - _deck_centre_z(y)) > 0.01 else 1.0
		var z0 := lo.y if inward > 0.0 else lo.y - RAIL_T
		lo = Vector2(lo.x, z0)
		hi = Vector2(hi.x, z0 + RAIL_T)
	else:
		var inward_x := -signf(lo.x)
		var x0 := lo.x if inward_x > 0.0 else lo.x - RAIL_T
		lo = Vector2(x0, lo.y)
		hi = Vector2(x0 + RAIL_T, hi.y)
	_box(_house_st, Vector3(lo.x, y, lo.y), Vector3(hi.x, y + 0.22, hi.y), HOUSE_WHITE)
	var inset := 0.02
	_box(_glass_st, Vector3(lo.x + inset, y + 0.22, lo.y + inset),
		Vector3(hi.x - inset, y + RAIL_HEIGHT - 0.06, hi.y - inset), Color.WHITE)
	_box(_chrome_st, Vector3(lo.x - 0.01, y + RAIL_HEIGHT - 0.06, lo.y - 0.01),
		Vector3(hi.x + 0.01, y + RAIL_HEIGHT, hi.y + 0.01), Color.WHITE)


func _deck_centre_z(y: float) -> float:
	if is_equal_approx(y, UPPER_Y):
		return UPPER_DECK.get_center().y
	if is_equal_approx(y, SUN_Y):
		return SUN_DECK.get_center().y
	if is_equal_approx(y, FLY_Y):
		return FLYBRIDGE.get_center().y
	return 0.0


func _build_furniture() -> void:
	for entry: Dictionary in FURNITURE:
		var rect: Rect2 = entry["rect"]
		var base := float(entry["base"])
		var top := float(entry["top"])
		match String(entry["kind"]):
			"tender":
				# A white hull to the gunwale and a navy cover over it.
				var gunwale := base + 1.25
				_box(_house_st, Vector3(rect.position.x, base, rect.position.y),
					Vector3(rect.end.x, gunwale, rect.end.y), HULL_WHITE)
				_box(_house_st, Vector3(rect.position.x + 0.08, gunwale, rect.position.y + 0.08),
					Vector3(rect.end.x - 0.08, top, rect.end.y - 0.08), TENDER_COVER)
			"bar":
				_box(_house_st, Vector3(rect.position.x, base, rect.position.y),
					Vector3(rect.end.x, top - 0.06, rect.end.y), BAR_WOOD)
				_box(_chrome_st, Vector3(rect.position.x - 0.03, top - 0.06, rect.position.y - 0.03),
					Vector3(rect.end.x + 0.03, top, rect.end.y + 0.03), Color.WHITE)
			"cushion":
				_box(_house_st, Vector3(rect.position.x, base, rect.position.y),
					Vector3(rect.end.x, top - 0.2, rect.end.y), HOUSE_WHITE)
				_box(_house_st, Vector3(rect.position.x + 0.05, top - 0.2, rect.position.y + 0.05),
					Vector3(rect.end.x - 0.05, top, rect.end.y - 0.05), CUSHION)
			_:
				_box(_house_st, Vector3(rect.position.x, base, rect.position.y),
					Vector3(rect.end.x, top, rect.end.y), HOUSE_WHITE)

	# The hot tub: a white drum; its water is dressing, laid on the lid.
	var sides := 20
	var tub_top := SUN_Y + TUB_HEIGHT
	for i: int in sides:
		var a := TAU * float(i) / float(sides)
		var b := TAU * float(i + 1) / float(sides)
		var pa := Vector3(TUB_AT.x + cos(a) * TUB_RADIUS, 0.0, TUB_AT.y + sin(a) * TUB_RADIUS)
		var pb := Vector3(TUB_AT.x + cos(b) * TUB_RADIUS, 0.0, TUB_AT.y + sin(b) * TUB_RADIUS)
		var mid := (pa + pb) * 0.5 - Vector3(TUB_AT.x, 0.0, TUB_AT.y)
		_quad(_house_st, pa + Vector3.UP * SUN_Y, pb + Vector3.UP * SUN_Y,
			pb + Vector3.UP * tub_top, pa + Vector3.UP * tub_top, mid, HOUSE_WHITE)
		_tri(_house_st, Vector3(TUB_AT.x, tub_top, TUB_AT.y), pa + Vector3.UP * tub_top,
			pb + Vector3.UP * tub_top, Vector3.UP, HOUSE_WHITE)


## The mast on the flybridge, with a yard across it. Collision, and off limits.
func _build_mast() -> void:
	var m := Vector3(MAST_AT.x, 0.0, MAST_AT.y)
	_box(_chrome_st, m + Vector3(-0.15, FLY_Y, -0.15), m + Vector3(0.15, MAST_TOP, 0.15),
		Color.WHITE)
	_box(_chrome_st, m + Vector3(-1.6, MAST_YARD - 0.16, -0.12), m + Vector3(1.6, MAST_YARD, 0.12),
		Color.WHITE)
	off_limits.append(Platform.new(m + Vector3.UP * MAST_TOP, 0.15, "mast", "mast top"))
	off_limits.append(Platform.new(m + Vector3.UP * MAST_YARD, 0.3, "mast", "mast yard"))


# ---------------------------------------------------------------- landings ---

## Every place the parkour report should know a Gub can stand, above the main
## deck. The main deck itself is the report's ground.
func _declare_landings() -> void:
	# Open decks, tiled.
	var upper_blocks: Array[Rect2] = [UPPER_HOUSE]
	var sun_blocks: Array[Rect2] = [FLYBRIDGE, Rect2(TUB_AT.x - TUB_RADIUS, TUB_AT.y - TUB_RADIUS,
		TUB_RADIUS * 2.0, TUB_RADIUS * 2.0)]
	var fly_blocks: Array[Rect2] = [Rect2(MAST_AT.x - 0.15, MAST_AT.y - 0.15, 0.3, 0.3)]
	for entry: Dictionary in STEPS:
		for rect: Rect2 in _mirror_rect(entry["rect"]):
			if is_equal_approx(float(entry["base"]), UPPER_Y):
				upper_blocks.append(rect)
			elif is_equal_approx(float(entry["base"]), SUN_Y):
				sun_blocks.append(rect)
	for entry: Dictionary in STAIRS:
		for span: Vector2 in _stair_spans(entry):
			var r := Rect2(span.x, minf(float(entry["foot"]), float(entry["head"])),
				span.y - span.x, absf(float(entry["foot"]) - float(entry["head"])))
			if is_equal_approx(float(entry["base"]), UPPER_Y):
				upper_blocks.append(r)
	for entry: Dictionary in FURNITURE:
		if is_equal_approx(float(entry["base"]), SUN_Y):
			sun_blocks.append(entry["rect"])
	_tile(UPPER_DECK, UPPER_Y, "upper", upper_blocks)
	_tile(SUN_DECK, SUN_Y, "sun", sun_blocks)
	_tile(FLYBRIDGE, FLY_Y, "fly", fly_blocks)
	_tile(SWIM_PLATFORM.grow_side(SIDE_TOP, -SWIM_STEP.size.y), SWIM_Y, "swim", [])

	for entry: Dictionary in STEPS:
		for rect: Rect2 in _mirror_rect(entry["rect"]):
			var side := "W" if rect.get_center().x < 0.0 else "E"
			platforms.append(Platform.new(
				Vector3(rect.get_center().x, float(entry["top"]), rect.get_center().y),
				minf(rect.size.x, rect.size.y) * 0.5 - 0.15, "step",
				"%s %s" % [entry["label"], side]))

	# Stairs: a landing every 0.9 m of rise, on the ramp's centreline.
	for entry: Dictionary in STAIRS:
		for span: Vector2 in _stair_spans(entry):
			var base := float(entry["base"])
			var top := float(entry["top"])
			var foot := float(entry["foot"])
			var head := float(entry["head"])
			var x := (span.x + span.y) * 0.5
			var side := "" if not bool(entry["mirror"]) else (" W" if x < 0.0 else " E")
			var rise := 0.9
			var k := 1
			while base + rise * float(k) < top - 0.3:
				var y := base + rise * float(k)
				var z := lerpf(foot, head, (y - base) / (top - base))
				platforms.append(Platform.new(Vector3(x, y + RAMP_LIFT, z),
					(span.y - span.x) * 0.5 - 0.15, "stair", "%s%s %d" % [entry["label"], side, k]))
				k += 1

	for entry: Dictionary in FURNITURE:
		if not entry.get("landing", false):
			continue
		var rect: Rect2 = entry["rect"]
		platforms.append(Platform.new(Vector3(rect.get_center().x, float(entry["top"]),
			rect.get_center().y), minf(rect.size.x, rect.size.y) * 0.5 - 0.15, "furniture",
			String(entry["label"])))
	platforms.append(Platform.new(Vector3(TUB_AT.x, SUN_Y + TUB_HEIGHT, TUB_AT.y),
		TUB_RADIUS * 0.7 - 0.15, "furniture", "hot tub"))


## Landing records on a grid over one open deck, skipping any a Gub would not
## fit at because something stands there, each with the radius of floor it can
## promise before an edge or a thing on the deck.
func _tile(region: Rect2, y: float, zone: String, blocks: Array) -> void:
	var nx := maxi(1, roundi(region.size.x / TILE))
	var nz := maxi(1, roundi(region.size.y / TILE))
	for i: int in nx:
		for j: int in nz:
			var p := Vector2(region.position.x + (float(i) + 0.5) * region.size.x / float(nx),
				region.position.y + (float(j) + 0.5) * region.size.y / float(nz))
			var room := minf(minf(p.x - region.position.x, region.end.x - p.x),
				minf(p.y - region.position.y, region.end.y - p.y))
			var clear := true
			for block: Rect2 in blocks:
				var d := _rect_distance(block, p)
				if d < TILE_CLEAR:
					clear = false
					break
				room = minf(room, d)
			if not clear:
				continue
			platforms.append(Platform.new(Vector3(p.x, y, p.y), clampf(room - 0.15, 0.4, TILE_RADIUS),
				zone, "%s %d,%d" % [zone, i, j]))


static func _rect_distance(rect: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - p.x, 0.0), p.x - rect.end.x)
	var dz := maxf(maxf(rect.position.y - p.y, 0.0), p.y - rect.end.y)
	return sqrt(dx * dx + dz * dz)


static func _mirror_rect(rect: Rect2) -> Array[Rect2]:
	return [rect, Rect2(-rect.end.x, rect.position.y, rect.size.x, rect.size.y)]


# ---------------------------------------------------------------- dressing ---

## The stairs as a flight of treads, each nosing on the collision ramp's slope.
func _build_treads(parent: Node3D) -> void:
	var treads := _begin()
	var tops := _begin()
	for entry: Dictionary in STAIRS:
		for span: Vector2 in _stair_spans(entry):
			var base := float(entry["base"])
			var top := float(entry["top"])
			var foot := float(entry["foot"])
			var head := float(entry["head"])
			var count := roundi((top - base) / TREAD_RISE)
			for k: int in count:
				var y := base + (top - base) * float(k + 1) / float(count)
				# The nose half a tread below the ramp, the back half above.
				var z_nose := lerpf(foot, head, (y - base - TREAD_RISE * 0.5) / (top - base))
				var z0 := minf(z_nose, head)
				var z1 := maxf(z_nose, head)
				_box(treads, Vector3(span.x, base, z0), Vector3(span.y, y, z1), HOUSE_WHITE, tops)
	_commit(parent, "StairTreads", treads, _paint)
	_commit(parent, "StairTeak", tops, _teak)


## Dark glass bands round every deckhouse, a few centimetres proud of the wall.
func _build_windows(parent: Node3D) -> void:
	var st := _begin()
	var proud := 0.03
	for house: Rect2 in [HOUSE_FORE, HOUSE_AFT]:
		_band(st, house, MAIN_Y + 0.9, UPPER_Y - SLAB - 0.35, proud, 0.6)
	_band(st, UPPER_HOUSE, UPPER_Y + 0.8, SUN_Y - SLAB - 0.35, proud, 0.5)
	_band(st, FLYBRIDGE, SUN_Y + 1.1, FLY_Y - 0.35, proud, 0.4)
	# A row of hull windows along the owner's deck, below the main deck.
	for side: float in [-1.0, 1.0]:
		var z := -6.0
		while z < 22.0:
			var y0 := -1.25
			var y1 := -0.65
			var x0 := lerpf(lerpf(WATERLINE_BEAM, BEAM, 0.6), BEAM, (y0 - BOOT_Y) / (MAIN_Y - BOOT_Y)) + proud
			var x1 := lerpf(lerpf(WATERLINE_BEAM, BEAM, 0.6), BEAM, (y1 - BOOT_Y) / (MAIN_Y - BOOT_Y)) + proud
			_quad(st, Vector3(x0 * side, y0, z), Vector3(x0 * side, y0, z + 2.6),
				Vector3(x1 * side, y1, z + 2.6), Vector3(x1 * side, y1, z),
				Vector3(side, 0.0, 0.0), Color.WHITE)
			z += 3.4
	var node := _commit(parent, "Windows", st, _window)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _band(st: SurfaceTool, rect: Rect2, y0: float, y1: float, proud: float, inset: float) -> void:
	var x0 := rect.position.x - proud
	var x1 := rect.end.x + proud
	var z0 := rect.position.y - proud
	var z1 := rect.end.y + proud
	var a := rect.position.y + inset
	var b := rect.end.y - inset
	_quad(st, Vector3(x0, y0, a), Vector3(x0, y0, b), Vector3(x0, y1, b), Vector3(x0, y1, a),
		Vector3.LEFT, Color.WHITE)
	_quad(st, Vector3(x1, y0, a), Vector3(x1, y0, b), Vector3(x1, y1, b), Vector3(x1, y1, a),
		Vector3.RIGHT, Color.WHITE)
	var c := rect.position.x + inset
	var d := rect.end.x - inset
	_quad(st, Vector3(c, y0, z0), Vector3(d, y0, z0), Vector3(d, y1, z0), Vector3(c, y1, z0),
		Vector3.FORWARD, Color.WHITE)
	_quad(st, Vector3(c, y0, z1), Vector3(d, y0, z1), Vector3(d, y1, z1), Vector3(c, y1, z1),
		Vector3.BACK, Color.WHITE)


## The radar on the mast, the hot tub's water, cushions on the salon sofas, and a
## navy sheer line along the hull at deck level.
func _build_details(parent: Node3D) -> void:
	var st := _begin()
	var m := Vector3(MAST_AT.x, 0.0, MAST_AT.y)
	# Radar: a flat bar on a drum, on the yard.
	_box(st, m + Vector3(-0.35, MAST_YARD, -0.35), m + Vector3(0.35, MAST_YARD + 0.3, 0.35),
		HOUSE_WHITE)
	_box(st, m + Vector3(-1.2, MAST_YARD + 0.3, -0.1), m + Vector3(1.2, MAST_YARD + 0.42, 0.1),
		HOUSE_WHITE)
	# A navy line along the hull just below the deck edge.
	for side: float in [-1.0, 1.0]:
		var z := BOW_Z + 2.0
		while z < STERN_Z:
			var step := 1.0 if z < TAPER_Z else 4.0
			var z2 := minf(z + step, STERN_Z)
			var wa := deck_half_width(z) + 0.02
			var wb := deck_half_width(z2) + 0.02
			_quad(st, Vector3(wa * side, -0.35, z), Vector3(wb * side, -0.35, z2),
				Vector3(wb * side, -0.15, z2), Vector3(wa * side, -0.15, z),
				Vector3(side, 0.0, 0.0), BOOT_NAVY)
			z = z2
	_commit(parent, "Details", st, _paint)

	var water := MeshInstance3D.new()
	water.name = "HotTubWater"
	var disc := CylinderMesh.new()
	disc.top_radius = TUB_RADIUS - 0.12
	disc.bottom_radius = TUB_RADIUS - 0.12
	disc.height = 0.02
	disc.radial_segments = 20
	water.mesh = disc
	water.position = Vector3(TUB_AT.x, SUN_Y + TUB_HEIGHT + 0.012, TUB_AT.y)
	var tub_water := StandardMaterial3D.new()
	tub_water.albedo_color = Color(0.13, 0.52, 0.60)
	tub_water.roughness = 0.04
	tub_water.emission_enabled = true
	tub_water.emission = Color(0.08, 0.34, 0.42)
	tub_water.emission_energy_multiplier = 0.12
	water.material_override = tub_water
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(water)


## The sea, and it is the biggest thing on the map by a long way: a displaced
## grid `SEA_REACH` metres out from the yacht in every direction, and a flat
## skirt from the grid's rim to the horizon. Not collision — nothing built after
## `super()` is — and in `StaticMap.BACKDROP_GROUP` so `preview_map` frames the
## yacht and not the ocean.
##
## Why a grid at all. The sea used to be a `PlaneMesh`: two triangles, a
## scrolling noise normal, and the single thing most wrong with this map. A
## yacht on a flat pane of colour is a model on a table, and normal-mapping does
## not fix it, because the eye reads *silhouette* before it reads shading — the
## horizon has to have crests in it and the rail has to have water moving past
## it. So the surface moves for real out to where a wave is smaller than a
## pixel, and past that the shader's slope-for-roughness trade takes over
## (`yacht_sea.gdshader`).
##
## The budget, deliberately: 96 x 96 cells is 18,432 triangles, welded, one draw
## call, one material, opaque, casting no shadow, with no transparency, no
## sorting and no texture memory at all. The yacht above it is 2,225 triangles,
## so the sea is eight times the map — the right ratio for a map whose subject
## is the sea. Three sine waves per vertex and four per fragment; the old plane
## sampled two normal textures per fragment, so the pixel cost is a wash and the
## vertex cost is new.
const SEA_REACH := 120.0
const SEA_CELL := 2.5
## Where the sea ends, under the fog. At `fog_density` 0.0025 three per cent of
## the light from 1.4 km away survives, so the skirt's rim is the fog's colour
## to within a rounding error and the horizon has no seam in it.
const SEA_HORIZON := 1400.0


func _build_sea(parent: Node3D) -> void:
	var st := _begin()
	var cells := int(round(SEA_REACH * 2.0 / SEA_CELL))
	for i: int in cells:
		var x0 := -SEA_REACH + float(i) * SEA_CELL
		var x1 := x0 + SEA_CELL
		for j: int in cells:
			var z0 := -SEA_REACH + float(j) * SEA_CELL
			var z1 := z0 + SEA_CELL
			_quad(st, Vector3(x0, WATER_Y, z0), Vector3(x1, WATER_Y, z0),
				Vector3(x1, WATER_Y, z1), Vector3(x0, WATER_Y, z1), Vector3.UP, Color.WHITE)
	# The skirt: four trapezoids out to the horizon. The shader fades the swell
	# to exactly nothing before the grid's rim, so these meet it flat — the rim
	# has 97 vertices along each edge and the skirt has two, and there is still
	# no crack, because every one of those 97 is at `WATER_Y` by then.
	for side: int in 4:
		var turn := float(side) * TAU * 0.25
		var co := cos(turn)
		var si := sin(turn)
		var out: Array[Vector3] = []
		for q: Vector2 in [Vector2(-SEA_HORIZON, -SEA_HORIZON), Vector2(SEA_HORIZON, -SEA_HORIZON),
				Vector2(SEA_REACH, -SEA_REACH), Vector2(-SEA_REACH, -SEA_REACH)]:
			out.append(Vector3(q.x * co - q.y * si, WATER_Y, q.x * si + q.y * co))
		_quad(st, out[0], out[1], out[2], out[3], Vector3.UP, Color.WHITE)
	# Welded. Every cell corner is shared by four quads with the same normal,
	# colour and planar UV, so indexing cuts the vertex count — and the wave
	# maths that runs on each one — by very nearly four.
	st.index()
	var sea := _commit(parent, "Sea", st, _water_material)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.add_to_group(BACKDROP_GROUP)



# ----------------------------------------------------------------- horizon ---

## The anchorage. Halcyon Wake is not in the middle of an ocean — she is lying a
## few hundred metres off a headland with the sun coming over her starboard bow,
## and until now the map said that nowhere: the sea faded into fog and the world
## stopped. From 8.8 m up on the flybridge that is the whole difference between
## a view and a backdrop, and this map is *about* being 8.8 m up.
##
## Three masses of land at three distances, overlapping in bearing, and the
## aerial perspective does the rest of the work: at 430 m the fog leaves a third
## of the hill's own colour, at 900 m a tenth, so the near headland is a solid
## grey-violet and the far range is barely a stain on the haze — and the eye
## reads the gap between them as miles. That is also why they are not one ridge.
##
## Bearings are degrees anticlockwise from the starboard beam: 0 is +x, 90 is
## the stern, 180 is port, 270 is the bow. All of this land is on the port side
## and across the stern, because the sun bears 322 and the sector its track runs
## out through has to stay empty water. That view — the flybridge, down-sun,
## nothing out there at all — is the best thing on the map and a hill in it
## would be vandalism.
##
## None of it is collision. It is added after `super()` and it is in
## `BACKDROP_GROUP`, so `preview_map` still frames the yacht and
## `parkour_report`'s overboard check still finds nothing but void over the
## side — that check asks the physics server, and the physics server has never
## heard of any of this.
const COAST: Array[Dictionary] = [
	{"label": "near head", "from": 116.0, "to": 216.0, "radius": 330.0, "peak": 44.0,
		"phase": 0.0, "tint": Color(0.085, 0.080, 0.085)},
	{"label": "middle ground", "from": 92.0, "to": 176.0, "radius": 560.0, "peak": 74.0,
		"phase": 2.1, "tint": Color(0.125, 0.120, 0.135)},
	{"label": "far range", "from": 152.0, "to": 254.0, "radius": 880.0, "peak": 122.0,
		"phase": 4.3, "tint": Color(0.20, 0.19, 0.22)},
]

## Other people, at anchor, in the open water the coast leaves. Three, at three
## distances, because one boat on a horizon is a prop and three is a place where
## boats go: a sloop close enough to read as a boat, a gulet far enough to be a
## shape, and a coaster far enough to be a smudge. The sloop's mast is the point
## of her — a vertical line is the one thing a sea horizon has none of, and the
## eye goes straight to it.
##
## `at` is (x, z) in metres and `heading` is degrees. They lie every way but the
## same way, which is what an anchorage looks like and a marina does not.
const VESSELS: Array[Dictionary] = [
	{"label": "sloop", "at": Vector2(-98.0, -128.0), "heading": -14.0, "length": 12.5,
		"beam": 3.6, "freeboard": 1.5, "house": 0.85, "mast": 16.5,
		"hull": Color(0.88, 0.88, 0.86)},
	{"label": "gulet", "at": Vector2(196.0, 176.0), "heading": 22.0, "length": 22.0,
		"beam": 5.6, "freeboard": 2.2, "house": 2.4, "mast": 0.0,
		"hull": Color(0.86, 0.85, 0.82)},
	{"label": "coaster", "at": Vector2(-320.0, 540.0), "heading": -62.0, "length": 52.0,
		"beam": 9.5, "freeboard": 4.6, "house": 6.0, "mast": 0.0,
		"hull": Color(0.40, 0.42, 0.44)},
]


func _build_horizon(parent: Node3D) -> void:
	var st := _begin()
	for entry: Dictionary in COAST:
		_coastline(st, entry)
	for entry: Dictionary in VESSELS:
		_vessel(st, entry)
	var node := _commit(parent, "Anchorage", st, _land)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_to_group(BACKDROP_GROUP)


## One headland, as a curtain of quads from the water up to a skyline. The
## skyline is a half-sine with two harmonics on it, so it has a summit, a
## shoulder and a saddle rather than being a smooth hump — which is the whole
## difference between a hill and a pile.
func _coastline(st: SurfaceTool, entry: Dictionary) -> void:
	var steps := 80
	var from := deg_to_rad(float(entry["from"]))
	var to := deg_to_rad(float(entry["to"]))
	var radius := float(entry["radius"])
	var peak := float(entry["peak"])
	var phase := float(entry["phase"])
	var tint: Color = entry["tint"]
	var prev_foot := Vector3.ZERO
	var prev_top := Vector3.ZERO
	for i: int in steps + 1:
		var t := float(i) / float(steps)
		var ang := lerpf(from, to, t)
		var r := radius * (1.0 + 0.09 * sin(t * TAU * 1.7 + phase))
		var foot := Vector3(cos(ang) * r, WATER_Y, sin(ang) * r)
		var top := foot + Vector3.UP * (peak * _coast_height(t, phase))
		if i > 0:
			var outward := -(foot + prev_foot) * 0.5
			outward.y = 0.0
			# The ridge is the *dark* part and the foot is the washed-out one:
			# at this distance the haze pools at sea level, so a coast reads as
			# a defined skyline standing on nothing. Doing it the other way
			# round — which is the instinct, because the sun is up there — turns
			# every headland into a meringue.
			_haze_quad(st, prev_foot, foot, top, prev_top, outward.normalized(),
				tint.lightened(0.30), tint)
		prev_foot = foot
		prev_top = top


## A quad whose bottom edge is one colour and whose top edge is another, wound
## to face `outward`. Only the coast needs this, and only because the gradient
## from haze at the waterline to rock at the ridge is the whole of what makes a
## distant headland read as land.
static func _haze_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		outward: Vector3, low: Color, high: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return
	var flip := n.dot(outward) > 0.0
	var normal := n.normalized() * (1.0 if flip else -1.0)
	var order: Array = [[a, low], [c, high], [b, low], [a, low], [d, high], [c, high]] if flip 		else [[a, low], [b, low], [c, high], [a, low], [c, high], [d, high]]
	for item: Array in order:
		st.set_color(item[1])
		st.set_normal(normal)
		st.set_uv(Vector2((item[0] as Vector3).x, (item[0] as Vector3).y) * 0.01)
		st.add_vertex(item[0])


static func _coast_height(t: float, phase: float) -> float:
	var bump := pow(sin(PI * clampf(t, 0.0, 1.0)), 0.45)
	var ridges := 0.55 + 0.45 * sin(t * TAU * 2.3 + phase)
	var detail := 0.74 + 0.26 * sin(t * TAU * 6.1 + phase * 1.7)
	var crags := 0.88 + 0.12 * sin(t * TAU * 13.7 + phase * 2.9)
	return bump * ridges * detail * crags


## One other boat: a hull with a pointed stem, a deckhouse, and a mast if she is
## the kind that has one.
func _vessel(st: SurfaceTool, entry: Dictionary) -> void:
	var at: Vector2 = entry["at"]
	var yaw := deg_to_rad(float(entry["heading"]))
	var length := float(entry["length"])
	var beam := float(entry["beam"])
	var top := WATER_Y + float(entry["freeboard"])
	var hull: Color = entry["hull"]
	var centre := Vector3(at.x, 0.0, at.y)
	# Plan outline, bow at -z: stem, two shoulders, two quarters.
	var plan: Array[Vector2] = [
		Vector2(0.0, -length * 0.5),
		Vector2(beam * 0.5, -length * 0.18),
		Vector2(beam * 0.5, length * 0.5),
		Vector2(-beam * 0.5, length * 0.5),
		Vector2(-beam * 0.5, -length * 0.18),
	]
	_prism(st, centre, yaw, plan, WATER_Y, top, hull)
	var house := float(entry["house"])
	if house > 0.0:
		var hl := length * 0.15
		var hb := beam * 0.31
		_prism(st, centre, yaw, [Vector2(-hb, -hl), Vector2(hb, -hl), Vector2(hb, hl),
			Vector2(-hb, hl)], top, top + house, hull.darkened(0.08))
	var mast := float(entry["mast"])
	if mast > 0.0:
		var t := 0.13
		_prism(st, centre, yaw, [Vector2(-t, -t), Vector2(t, -t), Vector2(t, t),
			Vector2(-t, t)], top, top + mast, Color(0.82, 0.82, 0.80))
		# A boom, because a bare stick reads as an aerial and a stick with a
		# boom on it reads as a boat that sails.
		_prism(st, centre, yaw, [Vector2(-0.09, 0.0), Vector2(0.09, 0.0),
			Vector2(0.09, length * 0.3), Vector2(-0.09, length * 0.3)],
			top + mast * 0.12, top + mast * 0.12 + 0.18, Color(0.82, 0.82, 0.80))


## An extruded plan outline, turned by `yaw` about `centre`: the shape every
## distant boat and deckhouse here is made of.
func _prism(st: SurfaceTool, centre: Vector3, yaw: float, plan: Array, base: float,
		top: float, colour: Color) -> void:
	var ring: Array[Vector3] = []
	for p: Vector2 in plan:
		ring.append(_turn(centre, yaw, p))
	for i: int in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var outward := (a + b) * 0.5 - centre
		outward.y = 0.0
		if outward.length_squared() < 1e-8:
			outward = Vector3.RIGHT
		_quad(st, Vector3(a.x, base, a.z), Vector3(b.x, base, b.z),
			Vector3(b.x, top, b.z), Vector3(a.x, top, a.z), outward.normalized(), colour)
	var cap := Vector3(0.0, 0.0, 0.0)
	for p: Vector3 in ring:
		cap += p
	cap /= float(ring.size())
	for i: int in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		_tri(st, Vector3(cap.x, top, cap.z), Vector3(a.x, top, a.z), Vector3(b.x, top, b.z),
			Vector3.UP, colour.lightened(0.06))


static func _turn(centre: Vector3, yaw: float, local: Vector2) -> Vector3:
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector3(centre.x + local.x * c - local.y * s, 0.0,
		centre.z + local.x * s + local.y * c)


# -------------------------------------------------------------------- wind ---

## Everything on a yacht at anchor that moves, moves in the wind, and all of it
## has to agree. She lies head to her cable, so: the swell in
## `yacht_sea.gdshader` runs bow to stern, the ensign at the transom streams
## aft, the burgee at the masthead streams aft, and the cable leads forward off
## the stem into the water. Get one of those backwards and the whole scene stops
## being a place.
##
## The ensign is also the only saturated warm colour on a map made entirely of
## white, blue and teak, and it flies over Team 2's base — so from four decks up
## it doubles as the thing that says which end of the boat you are looking at.
const ENSIGN_AT := Vector3(4.8, 1.0, 25.9)
const ENSIGN_STAFF := 2.4
const ENSIGN_SIZE := Vector2(1.9, 1.15)
const BURGEE_SIZE := Vector2(1.0, 0.42)
## Where the cable leaves the bow and where it goes into the water.
const CABLE_HAWSE := Vector3(0.55, 1.30, -35.4)
const CABLE_ENTRY := Vector3(-7.5, WATER_Y, -52.0)


func _build_wind(parent: Node3D) -> void:
	var st := _begin()
	# The ensign staff, raked aft the way one always is.
	var rake := deg_to_rad(18.0)
	var head := ENSIGN_AT + Vector3(0.0, cos(rake) * ENSIGN_STAFF, sin(rake) * ENSIGN_STAFF)
	_strut(st, ENSIGN_AT, head, 0.045, Color(0.86, 0.86, 0.84))
	# The cable, as a catenary of short links from the hawse into the water. It
	# is the one prop that says *at anchor* rather than *adrift*, and it gives
	# the sea somewhere to be entered rather than only looked at.
	var links := 18
	var prev := CABLE_HAWSE
	for k: int in links:
		var t := float(k + 1) / float(links)
		var p := CABLE_HAWSE.lerp(CABLE_ENTRY, t)
		p.y -= 0.8 * sin(PI * t)
		_strut(st, prev, p, 0.055, Color(0.22, 0.22, 0.23))
		prev = p
	var rig := _commit(parent, "Rigging", st, _paint)
	rig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_flag(parent, "Ensign", head + Vector3(0.0, -0.10, 0.05), ENSIGN_SIZE,
		_flag_image(Color(0.62, 0.09, 0.12), Color(0.06, 0.10, 0.22), Color(0.94, 0.90, 0.78)),
		5.2, 0.13)
	_flag(parent, "Burgee", Vector3(MAST_AT.x + 0.16, MAST_TOP - 0.3, MAST_AT.y),
		BURGEE_SIZE,
		_flag_image(Color(0.62, 0.09, 0.12), Color(0.94, 0.90, 0.78), Color(0.06, 0.10, 0.22)),
		7.4, 0.09)


## One flag: a quad subdivided along its length, hoisted at its left edge and
## flying aft. 66 vertices each, and the wave that moves them is in
## `yacht_cloth.gdshader`. UVs are set by hand here rather than taken from
## `_planar_uv`, because the shader needs to know where the hoist is.
func _flag(parent: Node3D, called: String, hoist: Vector3, size: Vector2, pattern: Texture2D,
		speed: float, amount: float) -> void:
	var st := _begin()
	var spans := 11
	for i: int in spans:
		var u0 := float(i) / float(spans)
		var u1 := float(i + 1) / float(spans)
		var x0 := u0 * size.x
		var x1 := u1 * size.x
		for corner: Array in [[x0, 0.0, u0, 1.0], [x1, size.y, u1, 0.0], [x1, 0.0, u1, 1.0],
				[x0, 0.0, u0, 1.0], [x0, size.y, u0, 0.0], [x1, size.y, u1, 0.0]]:
			st.set_color(Color.WHITE)
			st.set_normal(Vector3.BACK)
			st.set_uv(Vector2(corner[2], corner[3]))
			st.add_vertex(Vector3(corner[0], corner[1] - size.y, 0.0))
	var material := ShaderMaterial.new()
	material.shader = CLOTH_SHADER
	material.set_shader_parameter("pattern", pattern)
	material.set_shader_parameter("flap_speed", speed)
	material.set_shader_parameter("flap_amount", amount)
	material.set_shader_parameter("flag_length", size.x)
	material.set_shader_parameter("droop", size.x * 0.07)
	var node := _commit(parent, called, st, material)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The cloth's own x runs from the hoist to the fly, so the mesh is turned to
	# lie fore-and-aft and hung at the head of its staff.
	node.position = hoist
	node.rotation.y = -PI * 0.5


## A square-section strut from `a` to `b`. The ensign staff and every link of
## the cable are the same shape at different scales.
func _strut(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, colour: Color) -> void:
	var along := b - a
	if along.length_squared() < 1e-8:
		return
	var dir := along.normalized()
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	side = side.normalized() * radius
	var up := dir.cross(side).normalized() * radius
	var corners: Array[Vector3] = [side + up, side - up, -side - up, -side + up]
	for i: int in 4:
		var c0 := corners[i]
		var c1 := corners[(i + 1) % 4]
		var mid := (c0 + c1) * 0.5
		_quad(st, a + c0, b + c0, b + c1, a + c1, mid.normalized(), colour)


## A flag's cloth, as a small image: a field, a canton in the upper hoist and a
## band across the fly. Generated rather than painted, so there is nothing to
## import, nothing to lose, and no real country's ensign to get wrong.
static func _flag_image(field: Color, canton: Color, mark: Color) -> ImageTexture:
	var w := 64
	var h := 40
	var image := Image.create(w, h, false, Image.FORMAT_RGB8)
	for x: int in w:
		for y: int in h:
			var c := field
			if x < w / 3 and y < h / 2:
				c = canton
			elif absi(y - h / 2) < 3 and x > w / 3:
				c = mark
			# A little shading toward the hoist, so the cloth does not read flat
			# even before the wave gets to it.
			image.set_pixel(x, y, c.darkened(0.12 * (1.0 - float(x) / float(w))))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


# ------------------------------------------------------------------ meshes ---

func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _commit(parent: Node3D, called: String, st: SurfaceTool, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = called
	st.generate_tangents()
	node.mesh = st.commit()
	node.material_override = material
	parent.add_child(node)
	return node


## An axis-aligned box from `lo` to `hi`. Its top goes into `top` when given
## (the teak), everything else into `st` in `colour`.
func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, colour: Color, top: SurfaceTool = null) -> void:
	var a := Vector3(lo.x, lo.y, lo.z)
	var b := Vector3(hi.x, lo.y, lo.z)
	var c := Vector3(hi.x, lo.y, hi.z)
	var d := Vector3(lo.x, lo.y, hi.z)
	var e := Vector3(lo.x, hi.y, lo.z)
	var f := Vector3(hi.x, hi.y, lo.z)
	var g := Vector3(hi.x, hi.y, hi.z)
	var h := Vector3(lo.x, hi.y, hi.z)
	_quad(top if top != null else st, e, f, g, h, Vector3.UP, colour)
	_quad(st, a, b, c, d, Vector3.DOWN, colour)
	_quad(st, a, b, f, e, Vector3.FORWARD, colour)
	_quad(st, d, c, g, h, Vector3.BACK, colour)
	_quad(st, a, d, h, e, Vector3.LEFT, colour)
	_quad(st, b, c, g, f, Vector3.RIGHT, colour)


## A quad a-b-c-d (in order round its edge, either way), wound to face
## `outward`, flat shaded, with UVs projected in metres off its dominant axis.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3,
		colour: Color) -> void:
	_tri(st, a, b, c, outward, colour)
	_tri(st, a, c, d, outward, colour)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3,
		colour: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return
	# Godot's front face is clockwise seen from the front, so a triangle whose
	# right-hand normal points outward goes in backwards.
	var flip := n.dot(outward) > 0.0
	var normal := n.normalized() * (1.0 if flip else -1.0)
	for p: Vector3 in ([a, c, b] if flip else [a, b, c]):
		st.set_color(colour)
		st.set_normal(normal)
		st.set_uv(_planar_uv(p, normal))
		st.add_vertex(p)


static func _planar_uv(p: Vector3, normal: Vector3) -> Vector2:
	var n := normal.abs()
	if n.y >= n.x and n.y >= n.z:
		return Vector2(p.x, p.z) / 1.2
	if n.x >= n.z:
		return Vector2(p.z, -p.y) / 1.2
	return Vector2(p.x, -p.y) / 1.2


func _group(named: String, under: Node3D = null) -> Node3D:
	var node := Node3D.new()
	node.name = named
	(under if under != null else self).add_child(node)
	return node


# --------------------------------------------------------------- materials ---

## The sea's shader, in its own file rather than in a string constant here. It
## is 150 lines of commented GLSL and it is the single largest art decision on
## this map; a `const WATER_SHADER := """…"""` is where a shader goes to stop
## being read.
const SEA_SHADER := preload("res://resources/shaders/yacht_sea.gdshader")
## The flags' shader. Two sines a vertex over 132 vertices; it is the cheapest
## motion on the map and the only one a player can see from inside the salon.
const CLOTH_SHADER := preload("res://resources/shaders/yacht_cloth.gdshader")
## Teak, from Poly Haven (CC0; `assets/maps/yacht/SOURCES.md`). The grain is
## photographed and the plank layout is generated, and `_teak_image` multiplies
## one into the other at load — see there for why that is one texture and not
## two materials.
const TEAK_GRAIN := preload("res://assets/maps/yacht/teak_veneer_diff_1k.jpg")
const TEAK_NORMAL := preload("res://assets/maps/yacht/teak_veneer_nor_gl_1k.jpg")
const TEAK_ROUGH := preload("res://assets/maps/yacht/teak_veneer_rough_1k.jpg")


func _build_materials() -> void:
	# Painted gelcoat: everything white, navy and oxide on the yacht is vertex
	# colour on this one material.
	_paint = StandardMaterial3D.new()
	_paint.vertex_color_use_as_albedo = true
	_paint.roughness = 0.32
	_paint.metallic = 0.0
	_paint.clearcoat_enabled = true
	_paint.clearcoat = 0.4
	_paint.cull_mode = BaseMaterial3D.CULL_BACK

	var deck := _teak_maps()
	_teak = StandardMaterial3D.new()
	_teak.albedo_color = Color(0.80, 0.77, 0.70)
	_teak.albedo_texture = deck[0]
	_teak.normal_enabled = true
	_teak.normal_texture = deck[1]
	_teak.normal_scale = 1.0
	_teak.roughness = 0.92
	_teak.roughness_texture = TEAK_ROUGH
	_teak.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	_teak.uv1_scale = Vector3(1.2 / TEAK_TILE, 1.2 / TEAK_TILE, 1.0)
	_teak.cull_mode = BaseMaterial3D.CULL_BACK

	_glass = StandardMaterial3D.new()
	_glass.albedo_color = Color(0.70, 0.82, 0.86, 0.20)
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.roughness = 0.05
	_glass.metallic = 0.3
	_glass.cull_mode = BaseMaterial3D.CULL_DISABLED

	_window = StandardMaterial3D.new()
	_window.albedo_color = Color(0.10, 0.17, 0.24)
	_window.roughness = 0.1
	_window.metallic = 0.35

	# Land eight hundred metres off, and the boats between here and it. Matte,
	# lit, and left to the fog: at this distance the fog is nine tenths of the
	# colour, so what this material is actually for is holding the *slope*
	# shading that tells a headland from a cut-out.
	_land = StandardMaterial3D.new()
	_land.vertex_color_use_as_albedo = true
	_land.roughness = 1.0
	_land.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_land.cull_mode = BaseMaterial3D.CULL_BACK

	_chrome = StandardMaterial3D.new()
	_chrome.albedo_color = Color(0.78, 0.80, 0.82)
	_chrome.metallic = 0.9
	_chrome.roughness = 0.22

	# The sea. `sun_direction` is read off the `Sun` node rather than from
	# LIGHT0 in the shader, because this map now has two directional lights — the
	# sun and the fill bounced off the water — and the order Godot registers them
	# in is not a thing to hang the sun track on.
	_water_material = ShaderMaterial.new()
	_water_material.shader = SEA_SHADER
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		_water_material.set_shader_parameter("sun_direction",
			sun.global_transform.basis.z.normalized())
		_water_material.set_shader_parameter("sun_color", sun.light_color)
	# The hull's waterline, so the shader can draw the foam and the shadow of the
	# boat's underwater body as a distance field instead of as geometry.
	_water_material.set_shader_parameter("wl_beam", WATERLINE_BEAM)
	_water_material.set_shader_parameter("wl_bow_z", WATERLINE_BOW_Z)
	_water_material.set_shader_parameter("wl_taper_z", TAPER_Z)
	_water_material.set_shader_parameter("wl_stern_z", STERN_Z)


## The deck. Photographed teak grain from Poly Haven, the plank layout from
## arithmetic, and the two multiplied into one texture at load rather than
## carried as two materials — because the grain has to tile at about two metres
## and the caulking has to land exactly every 150 mm, and a
## `StandardMaterial3D` cannot give two textures two different scales.
##
## The seams go into the **normal** map as well as the albedo, and that is the
## half that earns the download. The sun is 38 degrees up: a 3 mm groove every
## 150 mm across forty metres of deck throws a line of shadow along the whole
## of it, and a deck with lines of shadow in it reads as laid planks instead of
## as printed wallpaper. The old procedural deck had the lines and no groove,
## which is why it looked like lino from anywhere but straight down.
##
## 2.4 m to a tile so the photographed grain repeats every 2.4 m rather than
## every 1.2 — `_planar_uv` projects one UV unit per 1.2 m, so `uv1_scale` is a
## half. 512 px is 213 px/m, which puts four pixels across a caulk seam.
const TEAK_TILE := 2.4
const TEAK_PLANKS := 16
const TEAK_RES := 512
## How wide the groove is, in pixels of the baked texture, and how deep it
## leans the normal.
const TEAK_SEAM := 0.9
const TEAK_GROOVE := 0.34


## Both deck maps in one pass, because they share the plank arithmetic: albedo
## with the caulking multiplied into the grain, and a normal with the grooves
## added to it. Returns [albedo, normal].
func _teak_maps() -> Array:
	var res := TEAK_RES
	var grain := _texture_image(TEAK_GRAIN, res)
	var bumps := _texture_image(TEAK_NORMAL, res)
	var albedo := Image.create(res, res, true, Image.FORMAT_RGB8)
	var normal := Image.create(res, res, true, Image.FORMAT_RGB8)
	var plank := res / TEAK_PLANKS
	for x: int in res:
		var row := x / plank
		var into := x % plank
		# Pixels to the nearest seam, and which way the groove leans there.
		var edge := float(mini(into, plank - 1 - into))
		var groove := clampf(1.0 - edge / TEAK_SEAM, 0.0, 1.0)
		var lean := groove * (1.0 if into < plank / 2 else -1.0)
		for y: int in res:
			# One butt joint per plank, staggered along the deck the way a real
			# one is so the joints never line up across it.
			var butt := absf(float((y + row * 97) % res) - float(res) * 0.5)
			var joint := clampf(1.0 - butt / 1.6, 0.0, 1.0)
			var dark := maxf(groove, joint)
			var base := grain.get_pixel(x, y) if grain != null else Color(0.72, 0.55, 0.36)
			albedo.set_pixel(x, y, base.lerp(Color(0.135, 0.125, 0.115), dark * 0.88))
			var n := bumps.get_pixel(x, y) if bumps != null else Color(0.5, 0.5, 1.0)
			normal.set_pixel(x, y, Color(
				clampf(n.r + lean * TEAK_GROOVE * 0.5, 0.0, 1.0),
				clampf(n.g - joint * TEAK_GROOVE * 0.25, 0.0, 1.0),
				n.b))
	albedo.generate_mipmaps()
	normal.generate_mipmaps()
	return [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(normal)]


## An imported texture as a plain RGB8 image at `res`, or null if the import
## did not produce one — in which case `_teak_maps` falls back to flat colour
## and a flat normal and the deck is the deck it was before the download.
static func _texture_image(texture: Texture2D, res: int) -> Image:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null:
		return null
	image = image.duplicate() as Image
	if image.is_compressed():
		if image.decompress() != OK:
			return null
	image.convert(Image.FORMAT_RGB8)
	image.resize(res, res, Image.INTERPOLATE_LANCZOS)
	return image
