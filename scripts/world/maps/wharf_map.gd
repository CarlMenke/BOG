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
##               crate, which is all the verticality the map has.
##   towers      three containers, 7.8 m, and the perimeter walls. The things
##               that cut sightlines, and out of reach of every jump in the
##               Bog's kit, the one-tick dive included — `tools/parkour_report`
##               fails the build if one can be reached (`off_limits`).
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
## middle of the yard the top of the near wall is 6.35 m up at 18 m out, so
## anything beyond the wall has to clear `1.45 + 0.353 * distance` to exist at
## all. That is 12 m at 30 m out and 18 m at 47 m, and it is why everything in
## `_build_port` is tall and nothing in it is detailed.

# ---------------------------------------------------------------- the table ---

## Half the yard's width. The walls' inner faces stand on these lines.
const HALF := 18.0

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
## tower, and `paint` indexes `PAINTS` bottom tier first.
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
	# The two climbable boxes on each side's approach.
	{"label": "yard west", "at": Vector2(-7.0, -7.5), "axis": "x", "tiers": 1, "paint": [2]},
	{"label": "yard east", "at": Vector2(7.0, -7.5), "axis": "x", "tiers": 1, "paint": [1]},
	# Against the side walls, closing the corners' diagonals.
	{"label": "wall west", "at": Vector2(-15.0, -6.0), "axis": "x", "tiers": 3, "paint": [5, 4, 3]},
	{"label": "wall east", "at": Vector2(15.0, -6.0), "axis": "x", "tiers": 3, "paint": [4, 1, 6]},
	# The middle: four towers round a crossroads, with B standing in it.
	{"label": "centre west", "at": Vector2(-4.0, -3.0), "axis": "x", "tiers": 3, "paint": [6, 0, 1]},
	{"label": "centre east", "at": Vector2(4.0, -3.0), "axis": "x", "tiers": 3, "paint": [2, 3, 0]},
	# On the centre line, each placed once: the climbable boxes beside O and G.
	{"label": "flank west", "at": Vector2(-11.5, 0.0), "axis": "z", "tiers": 1, "paint": [0]},
	{"label": "flank east", "at": Vector2(11.5, 0.0), "axis": "z", "tiers": 1, "paint": [5]},
]

## Crates, north half, as (x, z). Same mirror rule as the boxes. Each is laid
## flush against something: a crate with a gap under a metre beside a box is a
## slot a Bog gets stuck in, and flush it is a step.
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
##
## Energy went from 5.0 to 7.5 and the sun went from 0.9 to 0.55 at the same
## time, which is the whole of the hour change in two numbers: the floods used
## to be a decoration under a daylight key and they are the key now.
const MAST_TOP := 13.5
const MAST_AIM := 13.0
const FLOOD_COLOUR := Color(1.0, 0.80, 0.52)
const FLOOD_ENERGY := 7.5
const FLOOD_RANGE := 42.0
const FLOOD_ANGLE := 34.0
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

## The cranes standing outside the north and south walls. Scenery only.
const CRANE_Z := 27.0
const CRANE_SPAN := 16.0
const CRANE_HEIGHT := 18.0

# ------------------------------------------------------------------- the port ---

## The rest of the port, outside the walls. None of it is collision, none of it
## is in the sightline scan (which raycasts layer 1, and this is on no layer at
## all), and all of it is in `StaticMap.BACKDROP_GROUP` so `preview_map` keeps
## framing the 36 m yard rather than the 600 m harbour round it (D-057).
##
## The rule everything here obeys: **clear `1.45 + 0.353 * distance`, or do not
## bother**. A yard of beautifully detailed dockside at 6 m tall and 40 m out is
## six hundred triangles nobody will ever see over the wall.

## Stack rows, as distance out from the yard's own wall line. Three rows a side,
## east and west, so the yard reads as one block of a much bigger terminal.
const PORT_ROWS: PackedFloat32Array = [29.0, 35.5, 42.0]
## Where along z each row puts a stack, and how many containers high it is. The
## heights are written out rather than randomised because a broken skyline is
## the whole job of this table and a random one is broken in the wrong places —
## these rise away from the yard, so the near row never hides the far one.
const PORT_Z: PackedFloat32Array = [-22.0, -11.0, 0.0, 11.0, 22.0]
const PORT_TIERS: Array[int] = [5, 6, 4, 6, 5, 6, 5, 7, 5, 6, 4, 6, 5, 6, 7]

## The quay lamps: other people's floodlights, on masts too far away to light
## anything of ours. Points of sodium over the wall tops, and the cheapest depth
## cue on the map — an emissive head on a stick, no light attached, so eleven of
## them cost eleven quads and nothing else. `(x, z, height)`.
const QUAY_LAMPS: Array[Vector3] = [
	Vector3(-26.0, -31.0, 17.0), Vector3(26.0, -31.0, 19.0),
	Vector3(-26.0, 31.0, 19.0), Vector3(26.0, 31.0, 17.0),
	Vector3(-38.0, -26.0, 21.0), Vector3(38.0, 26.0, 21.0),
	Vector3(-47.0, 6.0, 20.0), Vector3(47.0, -6.0, 20.0),
	Vector3(-14.0, -47.0, 22.0), Vector3(16.0, 48.0, 22.0),
	Vector3(40.0, -44.0, 18.0),
]

## The moored coaster off the north quay and the transit shed off the south one.
## They are deliberately different shapes: this map is symmetric to a fault by
## design, and two identical silhouettes over the two walls would have taken
## away the one orientation cue a player gets from standing still.
const SHIP_AT := Vector3(9.0, 0.0, -34.0)
const SHIP_LENGTH := 46.0
const SHED_AT := Vector3(-7.0, 0.0, 33.0)
const SHED_LENGTH := 58.0

## The harbour light, north-east over the water, and how long its lamp takes to
## come round. Eight seconds is a real character for a harbour-mouth light and
## it is also about as slow as a sweep can be before a player stops connecting
## the beam overhead with the tower it came from.
const BEACON_AT := Vector3(33.0, 0.0, -42.0)
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

# ------------------------------------------------------------------ state ---

## Box counts, for the build log and the decision record.
var singles: int = 0
var towers: int = 0
var crates: int = 0
var wall_boxes: int = 0

var _mesh_cache: Dictionary = {}
var _paint_materials: Array[StandardMaterial3D] = []
var _wall_materials: Array[StandardMaterial3D] = []
var _crate_material: StandardMaterial3D
var _floor_material: ShaderMaterial
var _paint_line: StandardMaterial3D
var _steel: StandardMaterial3D
var _lamp: StandardMaterial3D

## What `_process` animates, and nothing else. Three small arrays rather than
## four `Node3D` subclasses: everything that moves on this map moves off one
## clock and one sine, and a class per lamp would be four scene-tree nodes
## paying `_process` each to do a multiply.
var _time: float = 0.0
var _floods: Array[SpotLight3D] = []
var _flood_base: PackedFloat32Array = PackedFloat32Array()
var _glare: Array[StandardMaterial3D] = []
var _beacon: Node3D


func _ready() -> void:
	var started := Time.get_ticks_msec()
	_build_materials()

	_build_floor(_group("Floor"))
	_build_walls(_group("Walls"))
	_build_yard(_group("Yard"))

	print("%s: %d singles, %d towers, %d crates, %d wall boxes, %d landings in %d ms" % [
		name, singles, towers, crates, wall_boxes, platforms.size(),
		Time.get_ticks_msec() - started])

	# Everything above this line becomes collision. Everything below it does not.
	super()

	var dressing := _group("Dressing")
	_build_paint(dressing)
	_build_door_bars(dressing)
	_build_cranes(dressing)
	var lamps := _build_floodlights(dressing)
	_build_port(_group("Port"))
	WharfAmbience.build(_group("Air"), HALF, lamps[0], lamps[1])


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
		for at: Vector2 in mirrored(entry["at"]):
			var side := "N" if at.y < -0.001 else "S" if at.y > 0.001 else "C"
			var label := "%s %s" % [entry["label"], side]
			for tier: int in tiers:
				_box(parent, at, axis, tier, int(paints[tier % paints.size()]))
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


## One container: a box with its own UVs, standing on `tier` others.
func _box(parent: Node3D, at: Vector2, axis: String, tier: int, paint: int,
		wall: bool = false) -> void:
	var node := MeshInstance3D.new()
	node.mesh = _container_mesh()
	node.material_override = (_wall_materials if wall else _paint_materials)[paint]
	var yaw := 0.0 if axis == "x" else PI * 0.5
	node.transform = Transform3D(Basis(Vector3.UP, yaw),
		Vector3(at.x, BOX_HEIGHT * float(tier), at.y))
	parent.add_child(node)


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
func _build_door_bars(parent: Node3D) -> void:
	var bars := SurfaceTool.new()
	bars.begin(Mesh.PRIMITIVE_TRIANGLES)
	for entry: Dictionary in BOXES:
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
##                 36 m square — the four maps are the cheapest shadow casters
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


# ------------------------------------------------------------------- the port ---

## Everything outside the walls: the rest of the terminal, the water, a ship, a
## shed, five more gantries and the harbour light.
##
## A 36 m box that ends at its own wall is a room. What makes it a wharf is that
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
		Vector3(-24.0, 0.0, -50.0), Vector3(22.0, 0.0, -62.0),
		Vector3(-30.0, 0.0, 52.0), Vector3(14.0, 0.0, 66.0),
		Vector3(56.0, 0.0, 18.0),
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

	# The lamp heads. Nine times over, which is well clear of the environment's
	# 2.0 glow threshold, so these four faces and the eleven quay lamps behind
	# them are the only things on the map allowed to bloom.
	_lamp = StandardMaterial3D.new()
	_lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp.albedo_color = FLOOD_COLOUR
	_lamp.emission_enabled = true
	_lamp.emission = FLOOD_COLOUR
	_lamp.emission_energy_multiplier = 9.0


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
