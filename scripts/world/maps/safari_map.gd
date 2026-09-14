class_name SafariMap
extends StaticMap
## Kopje Crossing — a sun-baked savanna plateau, built in code from a layout
## table rather than imported from a `.glb`.
##
## Rust is a bought arena: a pile of triangles that `static_map.gd` wraps
## collision around (D-031). This map is the other kind of hand-made map. Every
## rock in it is a piece of the Quaternius MegaKit, placed by the table below,
## which means the map is *readable* — a gap that plays badly is a number in a
## table and not a re-export — and it means the whole thing is a hundred
## kilobytes of script instead of forty megabytes of mesh.
##
## It is parkour first. There are about 120 landing surfaces between 0.4 m and
## 9.5 m, and the distance between any two of them was chosen against the Gub's
## own movement constants rather than by eye: a `hop` is a jump at run speed, a
## `leap` is a jump with the dive spent at the apex, and a `big` is a jump with
## the dive spent on the very next tick. `tools/parkour_report.gd` rebuilds that
## graph from this map's `platforms` list and fails a build where anything is
## unreachable — so "you cannot get up there" is a check and not a complaint.
##
## Build order matters and is the one thing to be careful of when editing:
##
##   1. the ground, the cliff skirt and every platform are built,
##   2. `super()` runs — `StaticMap._ready()` sweeps every `MeshInstance3D`
##      under this node into world-space trimesh collision on layer 1,
##   3. *then* the dressing goes in.
##
## Anything added before `super()` is collision. Anything added after it is
## scenery. Trees are added after and carry their own cylinder trunk colliders
## (exactly `PropScatter._add_collider`'s trunk path), because a trimesh of a
## thousand leaf cards is a thousand triangles a spear has to be tested against
## to be stopped by a leaf. Grass, bushes, pebbles and the waterhole get no
## collider at all.
##
## Everything random here comes from one `RandomNumberGenerator` seeded with a
## constant, consumed in a fixed order. That is not a style preference: the
## platforms *are* the collision, every peer builds this map independently, and
## two peers that disagree about where a rock is disagree about where the floor
## is.

# ---------------------------------------------------------------- the table ---

## One landing surface, as the parkour checker reads it.
##
## `radius` is the *inscribed* radius of the slab's footprint, less 0.15 m of
## lip — the circle you can be sure is solid under your feet whichever way the
## slab is yawed. Using half the diagonal instead would promise ground at the
## corners of a rectangle, which is exactly where a landing goes wrong.
class Platform extends RefCounted:
	var centre: Vector3   ## x, the top surface's y, z — where a Gub stands
	var radius: float     ## inscribed landing radius of the scaled footprint
	var zone: String      ## "kopje", "ridge", "termites", …
	var label: String     ## "spiral 3", "ridge 5", "nest" — named in failures

	func _init(at: Vector3, landing_radius: float, in_zone: String, called: String) -> void:
		centre = at
		radius = landing_radius
		zone = in_zone
		label = called


const KIT := "res://assets/Stylized_Nature_MegaKitStandard/glTF/%s.gltf"
const DESERT_DIFFUSE := "res://assets/Stylized_Nature_MegaKitStandard/glTF/Rocks_Desert_Diffuse.png"
## The kit's leaf cards come twice: a `_C` texture painted in the tree's own
## colour, which is what the meshes point at, and an uncoloured white one with
## the same alpha. Only the white one can be tinted. `albedo_color` multiplies,
## and a multiply can darken a colour or pull a channel down but never put back
## a channel the texture does not have — the twisted tree's `_C` leaves are
## (169, 23, 23), so every tint of them is a darker red, and the common tree's
## are (88, 123, 0), so every tint of those is a green. The canopies below take
## the white cards and get their colour entirely from the palette.
const LEAVES_NORMAL_WHITE := "res://assets/Stylized_Nature_MegaKitStandard/glTF/Leaves_NormalTree.png"
const LEAVES_TWISTED_WHITE := "res://assets/Stylized_Nature_MegaKitStandard/glTF/Leaves_TwistedTree.png"

## The one seed. See the header: every peer builds this map, so every peer has
## to draw the same numbers in the same order.
const SEED := 0x5AFA21

## The plateau is a superellipse `|x/48|^6 + |z/48|^6 <= 1`: 96 m across on the
## axes, 85 m across the diagonals, and no corners for a player to be cornered
## in. A circle would have read as an arena; a square would have read as Rust.
const PLATEAU_RADIUS := 48.0
const PLATEAU_POWER := 6.0
const RIM_SEGMENTS := 96
## How far the rim falls before the geometry stops. `void_height` is -14 in the
## scene, so a Gub that walks off the edge is dead a metre below the bottom of
## the cliff rather than falling past it for five seconds.
const CLIFF_DEPTH := 9.0

## The square every landing sits inside. Outside it is open savanna: spawns,
## acacias, boulders and the long sightlines that make a thrown spear worth
## aiming. A platform out there would be cover in the one place the map wants
## none.
const CITY := 34.0

## Where the waterhole is, and how big. The disc is decoration — it is added
## after `super()` and has no collision — but the grass and the mesas are kept
## out of it, so the number lives here rather than inside `_build_waterhole`.
const WATER_CENTRE := Vector2(-25.0, 23.0)
const WATER_RADIUS := 7.5

# --- the kopje -----------------------------------------------------------
## The spiral: ten steps, each 0.85 m above the last, walking a full turn
## anticlockwise around the core at a radius that closes by 5 cm a step.
##
## Bearings are `bearing(b, r) = Vector2(cos b, sin b) * r` on (x, z) — one
## helper, used everywhere, so "250 degrees" means the same thing in every zone.
## Note that under it 225 degrees points at (-7.8, -7.8), toward the dead
## forest, and *not* at the waterhole as §4 of the spec guessed. Rotating the
## spiral to face the waterhole was tried and abandoned: it is the same rotation
## that carries steps 8 and 9 away from the shoulders, and the step 8 -> shoulder
## and step 9 -> shoulder hops are what make the last two steps climbable at all.
## The waterhole reaches the kopje by its own mesa line onto step 3 instead,
## which is what §4.5 asks for anyway.
const SPIRAL_BASE_BEARING := 225.0
const SPIRAL_STEPS := 10
const SPIRAL_RADIUS := 11.0
const SPIRAL_CLOSE := 0.05
const SPIRAL_RISE := 0.85
const SPIRAL_FIRST_TOP := 1.2
## Steps 3 and 7 are pushed 2.6 m further out, which turns the gap into and out
## of each of them into a ~4.5 m leap. A spiral of ten identical hops is a
## staircase; two rungs you have to dive for is a climb.
const SPIRAL_LEAP_STEPS: PackedInt32Array = [3, 7]
const SPIRAL_LEAP_PUSH := 2.6

const SUMMIT_TOP := 9.5
const SHOULDER_TOP := 8.9
const SHOULDER_RADIUS := 5.8
const SHOULDER_BEARINGS: PackedFloat32Array = [250.0, 290.0]

## Decorative, and deliberately without landing records: these are the lumps the
## spiral is wrapped around. Their rounded tops are partly walkable at 5-7 m and
## that is fine — they are a shortcut nobody can plan a route through.
const KOPJE_CORE: Array[Dictionary] = [
	{"model": "Rock_Medium_1", "at": Vector3(0.5, -1.4, -0.5), "scale": Vector3(4.2, 3.6, 4.2)},
	{"model": "Rock_Medium_3", "at": Vector3(-4.0, -1.6, 3.0), "scale": Vector3(3.4, 3.0, 3.4)},
	{"model": "Rock_Medium_2", "at": Vector3(4.2, -1.0, 3.6), "scale": Vector3(3.2, 2.8, 3.2)},
]

# --- the ridge -----------------------------------------------------------
## Eight blocks along z = -24, the map's running route and the thing the summit
## dives at. The 8 m spacings are ~2.7 m hops and the two 10 m ones are ~4.7 m
## leaps, so the ridge reads as a run with two commitments in it.
const RIDGE_Z := -24.0
const RIDGE_X: PackedFloat32Array = [-29.0, -21.0, -13.0, -3.0, 5.0, 13.0, 23.0, 31.0]
const RIDGE_TOP: PackedFloat32Array = [4.8, 5.4, 5.0, 5.6, 4.7, 5.3, 5.1, 5.5]
## Written out rather than drawn from the RNG. The jitter exists so the ridge is
## not a ruler; a table of eight numbers says that in one line and keeps the
## platform layout completely independent of the order the dressing draws in.
const RIDGE_JITTER_Z: PackedFloat32Array = [0.45, -0.6, 0.3, -0.55, 0.5, -0.35, 0.6, -0.45]

## Stairs off each end of the ridge, as (x, z, top).
const RIDGE_STAIRS: Array[Vector3] = [
	Vector3(-33.0, -19.0, 3.8), Vector3(-34.0, -14.0, 2.6), Vector3(-33.0, -9.0, 1.3),
	Vector3(33.0, -19.0, 3.8), Vector3(34.0, -14.0, 2.6), Vector3(33.0, -9.0, 1.3),
]

## The saddles, and the one place this layout moved a long way from the spec.
##
## They were written at z = -17.5, where they are a good ridge-to-kopje link and
## 18.5 m from the summit. A leap off the summit reaches 10.5 m of *gap* at that
## drop and the edge rule wants 13.6, so no dive off the summit could ever land
## on one — and §4.2's "make at least one summit->ridge/saddle edge a leap" was
## unsatisfiable. The arithmetic also says no saddle position satisfies both
## roles at once: the summit needs one within 15.5 m of the origin, the nearest
## ridge block needs one within 10.7 m of z = -24, and those two discs do not
## meet. So the saddles moved 3.5 m inward to the furthest z that keeps the
## summit dive, and the saddle-to-ridge link became a big-leap shortcut. The
## ridge keeps its own way up from the ground at both ends.
const SADDLE_Z := -14.0
const SADDLE_X := 6.0
const SADDLE_TOP := 4.4

# --- the termite fields --------------------------------------------------
## A 4x4 grid minus the two off-diagonal corners, climbing 0.6 m a step from the
## low corner nearest the east connector to the high corner beside the ridge.
##
## The columns are at 5 m rather than the spec's 5.3 and start at x = 30 rather
## than 34: the spec's x = 34 column stands exactly where the ridge's east
## stairs do, and two zones cannot occupy the same three metres. Shifting the
## field west keeps every mound inside the stated x band of [15, 34].
const TERMITE_X: PackedFloat32Array = [30.0, 25.0, 20.0, 15.0]
const TERMITE_Z: PackedFloat32Array = [-4.0, -9.3, -14.6, -19.9]
const TERMITE_BASE_TOP := 1.4
const TERMITE_RISE := 0.6
## The two corners that are left out, as (column, row).
const TERMITE_SKIP: Array[Vector2i] = [Vector2i(3, 0), Vector2i(0, 3)]
## One pair pulled 0.7 m closer, which is what turns that climb into a hop. At
## the plain 5.3 m pitch every uphill link in the field is a leap, and a field of
## nothing but leaps is exhausting to cross.
const TERMITE_NUDGE := Vector2i(2, 1)
const TERMITE_NUDGE_BY := Vector2(0.5, 0.5)
const TERMITE_CAPS: PackedStringArray = [
	"RockPath_Round_Small_1", "RockPath_Round_Small_2", "RockPath_Round_Small_3"]

# --- the baobab ----------------------------------------------------------
const BAOBAB_CENTRE := Vector2(26.0, 22.0)
const BAOBAB_STEPS := 8
const BAOBAB_RADIUS := 6.2
const BAOBAB_CLOSE := 0.1
const BAOBAB_RISE := 0.9
const BAOBAB_FIRST_TOP := 1.2
## (x, z, top). Leap targets off the top of the spiral, and the launch points at
## the east and south connectors.
const BAOBAB_BRANCHES: Array[Vector3] = [
	Vector3(33.0, 14.0, 6.6), Vector3(18.0, 28.0, 7.2),
]
## (x, z, top). Two entries out of the south-east corner, curving in to the foot
## of the spiral.
const BAOBAB_APPROACH: Array[Vector3] = [
	Vector3(34.0, 25.0, 0.8), Vector3(33.5, 30.0, 0.6), Vector3(29.6, 32.6, 0.9),
	Vector3(25.2, 31.8, 1.2), Vector3(21.2, 29.8, 1.5), Vector3(19.6, 26.2, 1.8),
]

# --- the waterhole -------------------------------------------------------
## The beginner area: a shallow S of stepping stones across the water at ankle
## height, a shore climb that never asks for more than a hop, and a mesa line out
## of it that ends in the one leap that puts you on the kopje.
const STONE_FROM := Vector2(-32.0, 27.0)
const STONE_TO := Vector2(-19.0, 18.0)
const STONE_COUNT := 7
const STONE_SWAY := 0.9
const STONE_FIRST_TOP := 0.35
const STONE_RISE := 0.058

const SHORE_COUNT := 6
const SHORE_RADIUS := 10.2
const SHORE_FIRST_BEARING := -118.0
const SHORE_BEARING_STEP := 12.0
const SHORE_FIRST_TOP := 1.4
const SHORE_RISE := 0.28

## The mesa line runs from the shore to within one dive of spiral step 3. It is
## 3 m shorter than the spec's (-17, 17) -> (-11, 9) and ends further south: five
## 4.4 x 3.3 m mesas need 15 m of line to stand in without overlapping, and the
## last one has to be between 7.6 and 11.3 m from step 3 for that last edge to
## classify as the leap §4.5 asks for rather than as a hop.
const WH_MESA_FROM := Vector2(-15.2, 16.6)
const WH_MESA_TO := Vector2(-12.2, 4.6)
const WH_MESA_COUNT := 5
const WH_MESA_FIRST_TOP := 3.0
const WH_MESA_RISE := 0.4
const WH_MESA_YAW := -14.0

# --- the dead forest -----------------------------------------------------
## Three ladders out of the z = -5 edge, each with two gaps widened to a leap, all
## three converging on the crow's nest. The nest's own footprint is 4.9 x 4.8 m,
## which is why the middle ladder swings around it rather than through it.
const DEAD_LADDERS: Array[Array] = [
	[Vector3(-31.0, -4.6, 1.2), Vector3(-30.4, -10.8, 2.2), Vector3(-30.8, -14.3, 3.2),
		Vector3(-30.2, -20.4, 4.2), Vector3(-27.4, -19.6, 5.2)],
	[Vector3(-25.0, -4.6, 1.2), Vector3(-25.4, -8.0, 2.2), Vector3(-26.6, -14.3, 3.2),
		Vector3(-21.5, -17.7, 4.2), Vector3(-22.4, -20.4, 5.2)],
	[Vector3(-16.4, -5.0, 1.2), Vector3(-16.7, -8.4, 2.2), Vector3(-17.0, -11.8, 3.2),
		Vector3(-17.4, -17.8, 4.2), Vector3(-19.4, -20.4, 5.2), Vector3(-20.2, -14.4, 6.0)],
]
const NEST := Vector3(-24.0, -16.0, 6.8)

## The dead trees, as model, scale, x, z. They are placed at the spec's
## coordinates and then pushed out of any landing they would stand in — see
## `_clear_of_platforms`. A trunk collider on a slab is a slab you cannot land
## on, and it looks like nothing at all in a render.
const DEAD_TREES: Array[Dictionary] = [
	{"model": "DeadTree_5", "scale": 1.15, "at": Vector2(-31.0, -8.0)},
	{"model": "DeadTree_3", "scale": 1.20, "at": Vector2(-22.0, -17.0)},
	{"model": "DeadTree_1", "scale": 1.10, "at": Vector2(-17.0, -7.0)},
	{"model": "DeadTree_4", "scale": 1.00, "at": Vector2(-28.0, -15.0)},
	{"model": "DeadTree_2", "scale": 1.05, "at": Vector2(-24.0, -5.0)},
]

# --- the connectors ------------------------------------------------------
## Three runs around the outside of the city, each (x, z, top), so a player who
## spawns behind a zone can travel without dropping to the ground every time.
const CONNECTOR_EAST: Array[Vector3] = [
	Vector3(33.0, -2.0, 2.2), Vector3(33.0, 4.0, 2.8), Vector3(33.0, 9.0, 2.4),
	Vector3(34.0, 19.0, 3.0)]
const CONNECTOR_SOUTH: Array[Vector3] = [
	Vector3(14.0, 33.0, 1.6), Vector3(6.0, 33.0, 2.4), Vector3(-3.0, 33.0, 2.0),
	Vector3(-12.0, 33.0, 2.6)]
const CONNECTOR_WEST: Array[Vector3] = [
	Vector3(-33.0, 14.0, 1.8), Vector3(-34.0, 8.0, 2.4), Vector3(-33.0, 2.0, 2.8),
	Vector3(-34.0, -4.0, 2.0)]

## Three stones apiece, from each of the three big zones in toward the nearest
## spiral step. The spec asks for 8.5-9.5 m between centres; the gap between a
## zone's inner edge and the spiral it aims at is 11-19 m, so a three-stone chain
## at that spacing would have to span 34 m and would land outside the map. They
## are spaced to fit the gap instead, which makes most of these links hops.
const DIAGONAL_CHAINS: Array[Dictionary] = [
	{"label": "chain T", "stones": [Vector3(21.5, -0.5, 3.4), Vector3(17.0, 1.8, 4.6),
		Vector3(13.8, 4.6, 5.6)]},
	{"label": "chain B", "stones": [Vector3(18.6, 19.4, 3.6), Vector3(13.6, 15.4, 4.6),
		Vector3(10.0, 11.0, 5.2)]},
	{"label": "chain D", "stones": [Vector3(-17.0, -2.0, 2.6), Vector3(-13.6, -6.0, 3.2),
		Vector3(-10.5, -10.5, 3.4)]},
]

## Cover for the long walk in, halfway in bearing between one spawn and the next.
const LONE_BEARING_STEP := 45.0
## Radii differ per rock, and the one at 45 degrees is pushed all the way out to
## 41: the baobab's spiral and its approach stones own that bearing from 34 m to
## 45 m, and a lone rock at 37.5 stood on top of a spiral step's pillar.
const LONE_RADIUS: PackedFloat32Array = [39.0, 41.0, 40.0, 41.0, 41.0, 37.0, 39.5, 38.5]
const LONE_TOP: PackedFloat32Array = [1.0, 1.3, 1.6, 1.2, 1.5, 1.1, 1.4, 1.45]

# --- dressing ------------------------------------------------------------
const ACACIA_MODELS: PackedStringArray = [
	"CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"]
const BAOBAB_MODELS: PackedStringArray = [
	"TwistedTree_1", "TwistedTree_2", "TwistedTree_3", "TwistedTree_4", "TwistedTree_5"]
const BOULDER_MODELS: PackedStringArray = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"]
const GRASS_MODELS: PackedStringArray = [
	"Grass_Wispy_Short", "Grass_Common_Short", "Grass_Wispy_Tall"]
const GRASS_WEIGHTS: PackedFloat32Array = [0.45, 0.35, 0.20]
const PEBBLE_MODELS: PackedStringArray = [
	"Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3", "Pebble_Square_1",
	"Pebble_Square_2", "Pebble_Square_4"]

## Canopy colours, applied to white leaf cards so they are the colour and not a
## filter over one (see `LEAVES_NORMAL_WHITE`). Dry-season olive-gold for the
## acacias, a touch greener for the baobab so the one landmark tree stands apart
## from the forty around it, and the bushes duller and darker than either so they
## sit down in the grass.
const ACACIA_TINT := Color(0.74, 0.66, 0.30)
const BAOBAB_TINT := Color(0.62, 0.62, 0.30)
const BUSH_TINT := Color(0.58, 0.50, 0.26)

const RIM_ACACIAS := 26
const BAND_ACACIAS := 10
const CITY_ACACIAS := 4
const SMALL_BAOBABS := 3
const BAND_BOULDERS := 24
const CITY_BOULDERS := 10
const BUSHES := 40
const PEBBLES := 250
const FLOWERS := 10

const GRASS_CELL := 1.1
const GRASS_JITTER := 0.42
const GRASS_CHANCE_BAND := 0.90
const GRASS_CHANCE_CITY := 0.35

## Dart throws allowed per prop a scattered layer asks for. Generous because the
## rejection tests are cheap, and because the alternative is a layer whose count
## quietly depends on how lucky the seed was — `prop_scatter.gd` carries the same
## constant and the same story about why.
const PLACEMENT_ATTEMPTS := 40

## Nothing with a collider goes within this of a spawn pad. A player whose first
## frame is the inside of a tree has already lost the round.
const SPAWN_KEEPOUT := 4.0
const SPAWN_TREE_KEEPOUT := 5.0
## And nothing with a trunk goes this close to a landing. A tree growing through
## a slab is a slab nobody can stand on, and `parkour_report` fails the build
## over it rather than letting it be found by somebody standing on a rock.
const TREE_PLATFORM_KEEPOUT := 4.0

## Trunk radii at scale 1, by kind. These are the numbers `PropScatter` would
## use; the acacia is a squashed `CommonTree`, so its trunk is a little wider
## than the kit's own 0.44.
const TRUNK_ACACIA := 0.5
const TRUNK_BAOBAB := 1.7
const TRUNK_SMALL_BAOBAB := 0.9
const TRUNK_DEAD := 0.45
const TRUNK_FRACTION := 0.62

# ------------------------------------------------------------------ state ---

## Every landing on the map, in build order. Filled before `super()` so the
## checker and the collision sweep are looking at the same map.
var platforms: Array[Platform] = []
## Where the pads are, read off the `Spawns` markers. The dressing dodges these;
## the platform positions are authored, so the checker asserts those instead.
var spawn_keepouts: Array[Vector3] = []
## zone -> how many landings. "The map feels empty on the west side" is an
## opinion; "the dead forest placed 17" is a number.
var zone_counts: Dictionary = {}
## How many props the dressing put down, by layer, for the build log.
var dressing_counts: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _mesh_cache: Dictionary = {}

var _rock_material: StandardMaterial3D
var _path_material: StandardMaterial3D
var _ground_material: StandardMaterial3D
var _grass_material: StandardMaterial3D
var _bush_material: StandardMaterial3D
var _acacia_leaf: StandardMaterial3D
var _baobab_leaf: StandardMaterial3D
var _water_material: StandardMaterial3D

## Everything with a collider that the dressing has already put down, as
## (x, z, radius). Grass and pebbles test against it so nothing sprouts out of
## the middle of a trunk.
var _occupied: Array[Vector3] = []


func _ready() -> void:
	var started := Time.get_ticks_msec()
	_rng.seed = SEED
	_build_materials()
	_read_spawns()

	var terrain := _group("Terrain")
	_build_ground(terrain)
	_build_cliff(terrain)

	_build_kopje(_group("Kopje"))
	_build_ridge(_group("Ridge"))
	_build_termites(_group("Termites"))
	_build_baobab(_group("Baobab"))
	_build_waterhole(_group("Waterhole"))
	_build_deadforest(_group("DeadForest"))
	_build_connectors(_group("Connectors"))

	var laid := Time.get_ticks_msec() - started
	print("%s: %d platforms in %d ms — %s" % [name, platforms.size(), laid, _zone_line()])

	# Everything above this line becomes collision. Everything below it does not.
	super()

	_build_dressing(_group("Dressing"))
	print("%s: dressing — %s" % [name, _dressing_line()])


# ------------------------------------------------------------------ ground ---

## The plateau: a superellipse fan, flat at y = 0.
##
## `|x/48|^6 + |z/48|^6 <= 1` is 96 m across on the axes and 85 m across the
## diagonals, which is the shape a plateau weathers into and, more usefully, a
## shape with no corner for a player to be driven into. The rim radius at a
## bearing is solved rather than sampled so the cliff below can reuse it and the
## two meet exactly.
func _build_ground(parent: Node3D) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	vertices.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	uvs.append(Vector2.ZERO)
	for i: int in RIM_SEGMENTS:
		var at := _rim_point(TAU * float(i) / float(RIM_SEGMENTS))
		vertices.append(Vector3(at.x, 0.0, at.y))
		normals.append(Vector3.UP)
		# One texture repeat every 8 m. The ground material's `uv1_scale` then
		# stretches the noise on top of that to a ~10 m tile.
		uvs.append(at / 8.0)
	for i: int in RIM_SEGMENTS:
		var a := 1 + i
		var b := 1 + (i + 1) % RIM_SEGMENTS
		# Wound so the visible face is the one you stand on. Godot takes the
		# front face from the winding, and a plateau facing downward is a map
		# that renders as a hole with a cliff around it.
		indices.append_array([0, b, a])

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var node := MeshInstance3D.new()
	node.name = "Plateau"
	node.mesh = mesh
	node.material_override = _ground_material
	parent.add_child(node)


## The cliff the plateau stands on: the rim extruded straight down, facing out.
##
## It is nine metres of rock that exists so the edge of the map is an edge and
## not a hole. It is swept into the collision along with everything else, which
## is what stops a Gub sliding down the outside of it; `void_height` at -14 is
## five metres below the bottom of it.
func _build_cliff(parent: Node3D) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for i: int in RIM_SEGMENTS:
		var angle := TAU * float(i) / float(RIM_SEGMENTS)
		var at := _rim_point(angle)
		# Outward, and in the plane: the rim is not a circle, so the outward
		# direction is the normalised position and not the bearing.
		var out := Vector3(at.x, 0.0, at.y).normalized()
		vertices.append(Vector3(at.x, 0.0, at.y))
		vertices.append(Vector3(at.x, -CLIFF_DEPTH, at.y))
		normals.append(out)
		normals.append(out)
		var along := float(i) * 2.0
		uvs.append(Vector2(along, 0.0))
		uvs.append(Vector2(along, CLIFF_DEPTH / 4.0))
	for i: int in RIM_SEGMENTS:
		var a := i * 2
		var b := i * 2 + 1
		var c := ((i + 1) % RIM_SEGMENTS) * 2
		var d := ((i + 1) % RIM_SEGMENTS) * 2 + 1
		indices.append_array([a, b, c, c, b, d])

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var node := MeshInstance3D.new()
	node.name = "Cliff"
	node.mesh = mesh
	node.material_override = _rock_material
	parent.add_child(node)


## Where the rim is at this bearing, solved out of the superellipse.
func _rim_point(angle: float) -> Vector2:
	var c := absf(cos(angle))
	var s := absf(sin(angle))
	var shrink := pow(pow(c, PLATEAU_POWER) + pow(s, PLATEAU_POWER), 1.0 / PLATEAU_POWER)
	var radius := PLATEAU_RADIUS / maxf(shrink, 0.0001)
	return Vector2(cos(angle), sin(angle)) * radius


# ------------------------------------------------------------------- kopje ---

func _build_kopje(parent: Node3D) -> void:
	for entry: Dictionary in KOPJE_CORE:
		_boulder(parent, String(entry["model"]), entry["at"], entry["scale"],
			_rng.randf_range(0.0, TAU))

	# The summit sits on a pillar of its own rather than on the core, so its
	# height is a number in this file and not whatever the boulders happened to
	# stack to.
	_piece(parent, "Rock_Medium_2", Vector3.ZERO, Vector3(2.0, 5.0, 2.0),
		_rng.randf_range(0.0, TAU), _rock_material)
	_slab(parent, "kopje", "summit", "RockPath_Round_Wide", Vector2.ZERO, SUMMIT_TOP,
		Vector3(2.8, 2.2, 2.8), 0.0, false)

	for i: int in SHOULDER_BEARINGS.size():
		var b := SHOULDER_BEARINGS[i]
		_slab(parent, "kopje", "shoulder %d" % i, "RockPath_Square_Wide",
			bearing(b, SHOULDER_RADIUS), SHOULDER_TOP, Vector3(2.0, 1.6, 2.0), -b)

	for i: int in SPIRAL_STEPS:
		var b := SPIRAL_BASE_BEARING - 36.0 * float(i)
		var r := SPIRAL_RADIUS - SPIRAL_CLOSE * float(i)
		if SPIRAL_LEAP_STEPS.has(i):
			r += SPIRAL_LEAP_PUSH
		_slab(parent, "kopje", "spiral %d" % i, "RockPath_Square_Wide", bearing(b, r),
			SPIRAL_FIRST_TOP + SPIRAL_RISE * float(i), Vector3(2.0, 1.6, 2.0), -b)


# ------------------------------------------------------------------- ridge ---

func _build_ridge(parent: Node3D) -> void:
	for i: int in RIDGE_X.size():
		_mesa(parent, "ridge", "ridge %d" % i,
			Vector2(RIDGE_X[i], RIDGE_Z + RIDGE_JITTER_Z[i]), RIDGE_TOP[i],
			Vector2(2.4, 1.7), 0.0)
	for entry: Vector3 in RIDGE_STAIRS:
		_slab(parent, "ridge", "stair %+.0f,%+.0f" % [entry.x, entry.y],
			"RockPath_Square_Wide", Vector2(entry.x, entry.y), entry.z,
			Vector3(2.0, 1.6, 2.0), 0.0)
	_slab(parent, "ridge", "saddle W", "RockPath_Square_Wide",
		Vector2(-SADDLE_X, SADDLE_Z), SADDLE_TOP, Vector3(2.2, 1.6, 2.2), 20.0)
	_slab(parent, "ridge", "saddle E", "RockPath_Square_Wide",
		Vector2(SADDLE_X, SADDLE_Z), SADDLE_TOP, Vector3(2.2, 1.6, 2.2), -20.0)


# ---------------------------------------------------------------- termites ---

## Fourteen mounds on a jittered grid, each a squashed boulder with a small flat
## cap. The caps are small on purpose: the field is the one place on the map
## where the landing is the hard part rather than the gap.
func _build_termites(parent: Node3D) -> void:
	var n := 0
	for i: int in TERMITE_X.size():
		for j: int in TERMITE_Z.size():
			if TERMITE_SKIP.has(Vector2i(i, j)):
				continue
			var at := Vector2(TERMITE_X[i], TERMITE_Z[j])
			if Vector2i(i, j) == TERMITE_NUDGE:
				at += TERMITE_NUDGE_BY
			var top := TERMITE_BASE_TOP + TERMITE_RISE * float(i + j)
			_mound(parent, "termites", "mound %d%d" % [i, j], at, top,
				TERMITE_CAPS[n % TERMITE_CAPS.size()], 37.0 * float(n))
			n += 1


# ------------------------------------------------------------------ baobab ---

func _build_baobab(parent: Node3D) -> void:
	for i: int in BAOBAB_STEPS:
		var b := 180.0 + 45.0 * float(i)
		var at := BAOBAB_CENTRE + bearing(b, BAOBAB_RADIUS - BAOBAB_CLOSE * float(i))
		_slab(parent, "baobab", "bao spiral %d" % i, "RockPath_Square_Thin", at,
			BAOBAB_FIRST_TOP + BAOBAB_RISE * float(i), Vector3(1.8, 1.5, 1.8), -b)
	var yaws: PackedFloat32Array = [20.0, -35.0]
	for i: int in BAOBAB_BRANCHES.size():
		var entry := BAOBAB_BRANCHES[i]
		_slab(parent, "baobab", "branch %s" % ("E" if i == 0 else "S"),
			"RockPath_Square_Wide", Vector2(entry.x, entry.y), entry.z,
			Vector3(2.2, 1.6, 2.2), yaws[i])
	for i: int in BAOBAB_APPROACH.size():
		var entry := BAOBAB_APPROACH[i]
		_slab(parent, "baobab", "approach %d" % i, "RockPath_Round_Wide",
			Vector2(entry.x, entry.y), entry.z, Vector3(1.6, 1.8, 1.6), 23.0 * float(i))


# --------------------------------------------------------------- waterhole ---

func _build_waterhole(parent: Node3D) -> void:
	var span := STONE_TO - STONE_FROM
	var across := Vector2(-span.y, span.x).normalized()
	for i: int in STONE_COUNT:
		var t := float(i) / float(STONE_COUNT - 1)
		var at := STONE_FROM + span * t + across * (STONE_SWAY * sin(TAU * t))
		var top := STONE_FIRST_TOP + STONE_RISE * float(i)
		# The standard pillar rather than a hand-placed lump: it is sized off the
		# slab's own underside, so the rock stops inside the stone instead of
		# poking a boulder up through the one place a Gub has to stand.
		_slab(parent, "waterhole", "stone %d" % i, TERMITE_CAPS[i % TERMITE_CAPS.size()],
			at, top, Vector3(1.7, 2.0, 1.7), 41.0 * float(i))

	for i: int in SHORE_COUNT:
		var b := SHORE_FIRST_BEARING + SHORE_BEARING_STEP * float(i)
		var at := WATER_CENTRE + bearing(b, SHORE_RADIUS)
		var top := SHORE_FIRST_TOP + SHORE_RISE * float(i)
		# A whole boulder with a flat stone laid on it, rather than a slab on a
		# pillar: the shore should look like the ground coming up out of the
		# water and not like six more platforms.
		var boulder := "Rock_Medium_1" if i % 2 == 0 else "Rock_Medium_3"
		var box := _kit(boulder).get_aabb()
		var lift := (top - 0.12) / box.end.y
		# Kept under about 5 m across. A `Rock_Medium_3` at 1.9 is six and a half
		# metres wide and sprawls far enough to swallow the stepping stone next
		# to it, which the physics check catches as a landing with the wrong rock
		# under it.
		var spread := 1.3 + 0.06 * float(i)
		_piece(parent, boulder, Vector3(at.x, 0.0, at.y), Vector3(spread, lift, spread),
			_rng.randf_range(0.0, TAU), _rock_material)
		_slab(parent, "waterhole", "shore %d" % i, "RockPath_Round_Thin", at, top,
			Vector3(1.6, 1.6, 1.6), 90.0 - b, false)

	var mesa_span := WH_MESA_TO - WH_MESA_FROM
	for i: int in WH_MESA_COUNT:
		var t := float(i) / float(WH_MESA_COUNT - 1)
		_mesa(parent, "waterhole", "wh mesa %d" % i, WH_MESA_FROM + mesa_span * t,
			WH_MESA_FIRST_TOP + WH_MESA_RISE * float(i), Vector2(2.0, 1.5), WH_MESA_YAW)


# -------------------------------------------------------------- deadforest ---

func _build_deadforest(parent: Node3D) -> void:
	for li: int in DEAD_LADDERS.size():
		var rungs: Array = DEAD_LADDERS[li]
		for ri: int in rungs.size():
			var rung: Vector3 = rungs[ri]
			_slab(parent, "deadforest", "ladder %d.%d" % [li, ri], "RockPath_Square_Thin",
				Vector2(rung.x, rung.y), rung.z, Vector3(1.7, 1.5, 1.7),
				17.0 * float(li + 1) + 11.0 * float(ri))
	_slab(parent, "deadforest", "nest", "RockPath_Square_Wide", Vector2(NEST.x, NEST.y),
		NEST.z, Vector3(2.4, 1.8, 2.4), 12.0)


# -------------------------------------------------------------- connectors ---

func _build_connectors(parent: Node3D) -> void:
	var runs := {"east": CONNECTOR_EAST, "south": CONNECTOR_SOUTH, "west": CONNECTOR_WEST}
	for side: String in runs:
		var stones: Array = runs[side]
		for i: int in stones.size():
			var entry: Vector3 = stones[i]
			_slab(parent, "connector", "%s %d" % [side, i], "RockPath_Round_Wide",
				Vector2(entry.x, entry.y), entry.z, Vector3(2.0, 1.8, 2.0),
				19.0 * float(i))
	for chain: Dictionary in DIAGONAL_CHAINS:
		var stones: Array = chain["stones"]
		for i: int in stones.size():
			var entry: Vector3 = stones[i]
			_slab(parent, "connector", "%s.%d" % [chain["label"], i],
				"RockPath_Round_Wide", Vector2(entry.x, entry.y), entry.z,
				Vector3(2.0, 1.8, 2.0), 31.0 * float(i))
	for k: int in LONE_RADIUS.size():
		_slab(parent, "lone", "lone %d" % k, "RockPath_Square_Wide",
			bearing(LONE_BEARING_STEP * float(k), LONE_RADIUS[k]), LONE_TOP[k],
			Vector3(2.0, 1.6, 2.0), 30.0 * float(k))


# ---------------------------------------------------------------- dressing ---

## Everything that is not collision, in a fixed order so the RNG draws the same
## numbers on every peer. Called *after* `super()`, so none of it is swept.
func _build_dressing(parent: Node3D) -> void:
	_build_water(parent)
	_build_trees(parent)
	_build_boulders(parent)
	_build_bushes(parent)
	_build_grass(parent)
	_build_pebbles(parent)
	_build_flowers(parent)


func _build_water(parent: Node3D) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = WATER_RADIUS
	disc.bottom_radius = WATER_RADIUS
	disc.height = 0.04
	disc.radial_segments = 48
	disc.rings = 1
	var node := MeshInstance3D.new()
	node.name = "Waterhole"
	node.mesh = disc
	node.material_override = _water_material
	node.position = Vector3(WATER_CENTRE.x, 0.02, WATER_CENTRE.y)
	# No collider, and no shadow: it is two centimetres of blue, and a shadow map
	# entry for it would only ever darken the sand under itself.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


## Acacias on the rim and in the band, the one real baobab over its spiral, and
## the dead forest's five snags.
##
## The acacia is a `CommonTree` squashed: 1.8-2.1 wide and barely taller than it
## was, which is what turns a European broadleaf into a flat-topped thorn. It is
## the single cheapest thing in this file and it does most of the work of making
## the map read as savanna.
func _build_trees(parent: Node3D) -> void:
	var group := _group("Trees", parent)
	var placed := 0

	# Thrown at a bearing rather than placed on one, and thrown again if the
	# throw lands on a spawn pad or on top of the last tree. `PropScatter`
	# learned this the hard way: a layer that gives up after one attempt places
	# whatever the seed happened to allow, and "the rim looks patchy" is then a
	# property of the seed rather than of the table.
	for i: int in RIM_ACACIAS:
		var base := TAU * float(i) / float(RIM_ACACIAS)
		for attempt: int in PLACEMENT_ATTEMPTS:
			var angle := base + _rng.randf_range(-0.05, 0.05) * float(attempt)
			var at := _rim_point(angle) * _rng.randf_range(0.93, 0.97)
			if not _spawn_clear(at, SPAWN_TREE_KEEPOUT) or _crowded(at, 9.0):
				continue
			if _nearest_platform(at) < TREE_PLATFORM_KEEPOUT:
				continue
			_acacia(group, at)
			placed += 1
			break

	for i: int in BAND_ACACIAS:
		for attempt: int in PLACEMENT_ATTEMPTS:
			var at := _band_point(36.0, 43.0)
			if not _spawn_clear(at, SPAWN_TREE_KEEPOUT) or _crowded(at, 6.0):
				continue
			if _nearest_platform(at) < TREE_PLATFORM_KEEPOUT:
				continue
			_acacia(group, at)
			placed += 1
			break

	for i: int in CITY_ACACIAS:
		for attempt: int in PLACEMENT_ATTEMPTS:
			var at := _band_point(8.0, 30.0)
			if _nearest_platform(at) < 6.0 or _crowded(at, 8.0):
				continue
			_acacia(group, at)
			placed += 1
			break
	dressing_counts["Acacias"] = placed

	# The baobab itself. It is the only tree on the map with a landing wrapped
	# around it, so it is placed by coordinate rather than scattered.
	var trunk := _tree(group, "TwistedTree_2", Vector2(26.0, 22.0), 1.25,
		deg_to_rad(40.0), TRUNK_BAOBAB, _baobab_leaf)
	_occupied.append(Vector3(26.0, 22.0, TRUNK_BAOBAB * 1.25))
	if trunk == null:
		push_warning("SafariMap: the baobab did not load")

	var small := 0
	for i: int in SMALL_BAOBABS:
		for attempt: int in PLACEMENT_ATTEMPTS:
			var at := _band_point(36.0, 43.0)
			if not _spawn_clear(at, SPAWN_TREE_KEEPOUT) or _crowded(at, 7.0):
				continue
			if _nearest_platform(at) < TREE_PLATFORM_KEEPOUT + 1.5:
				continue
			var model := BAOBAB_MODELS[_rng.randi_range(0, BAOBAB_MODELS.size() - 1)]
			_tree(group, model, at, _rng.randf_range(0.40, 0.5),
				_rng.randf_range(0.0, TAU), TRUNK_SMALL_BAOBAB, _baobab_leaf)
			small += 1
			break
	dressing_counts["SmallBaobabs"] = small

	var dead := 0
	for entry: Dictionary in DEAD_TREES:
		var wanted: Vector2 = entry["at"]
		var scale := float(entry["scale"])
		# Pushed out of any landing it would stand in. The spec's coordinates
		# were written before the ladders were, and a trunk collider standing on
		# a slab is a slab nobody can use.
		var at := _clear_of_platforms(wanted, TRUNK_DEAD * scale + 0.5)
		_tree(group, String(entry["model"]), at, scale, _rng.randf_range(0.0, TAU),
			TRUNK_DEAD, null)
		dead += 1
	dressing_counts["DeadTrees"] = dead


## Cover on the ground, and the only dressing besides the trees that a spear
## cannot pass. Convex hulls rather than trimeshes, exactly as `PropScatter`
## does it: the simplified hull of a boulder is a dozen planes.
func _build_boulders(parent: Node3D) -> void:
	var group := _group("Boulders", parent)
	var placed := 0
	for i: int in BAND_BOULDERS + CITY_BOULDERS:
		for attempt: int in PLACEMENT_ATTEMPTS:
			var at := _band_point(36.0, 44.0) if i < BAND_BOULDERS else _band_point(6.0, 32.0)
			if not _spawn_clear(at, SPAWN_KEEPOUT):
				continue
			# Four metres off any landing: a boulder beside a platform is cover,
			# a boulder against one is a step nobody meant to build.
			if _nearest_platform(at) < 4.0 or _crowded(at, 5.0):
				continue
			var model := BOULDER_MODELS[_rng.randi_range(0, BOULDER_MODELS.size() - 1)]
			var size := _rng.randf_range(0.7, 1.3)
			var node := _piece(group, model, Vector3(at.x, -0.25 * size, at.y),
				Vector3(size, size * _rng.randf_range(0.8, 1.15), size),
				_rng.randf_range(0.0, TAU), _rock_material)
			if node == null:
				continue
			_convex_body(group, node)
			_occupied.append(Vector3(at.x, at.y, 2.0 * size))
			placed += 1
			break
	dressing_counts["Boulders"] = placed


func _build_bushes(parent: Node3D) -> void:
	var group := _group("Bushes", parent)
	var mesh := _kit("Bush_Common")
	if mesh == null:
		return
	var transforms: Array[Transform3D] = []
	for i: int in BUSHES:
		for attempt: int in PLACEMENT_ATTEMPTS:
			var at := _band_point(30.0, 45.0)
			if not _spawn_clear(at, SPAWN_KEEPOUT) or _nearest_platform(at) < 2.5:
				continue
			if not _on_plateau(at) or _in_water(at):
				continue
			var size := _rng.randf_range(0.5, 0.9)
			var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
			transforms.append(Transform3D(basis, Vector3(at.x, -0.12 * size, at.y)))
			break
	_multimesh(group, "Bush_Common", transforms, true, _bush_material)
	dressing_counts["Bushes"] = transforms.size()


## Grass, stratified over the whole plateau and thinned inside the city.
##
## Thinned rather than excluded: knee-high grass between the platforms is most of
## what stops the city reading as a rock garden, but grass everywhere would hide
## a crouched Gub at three metres, which on a map with an instant-kill projectile
## is a gameplay change and not a look.
func _build_grass(parent: Node3D) -> void:
	var group := _group("Grass", parent)
	var buckets: Dictionary = {}
	for model: String in GRASS_MODELS:
		buckets[model] = [] as Array[Transform3D]

	var steps := int(ceil(PLATEAU_RADIUS * 2.0 / GRASS_CELL))
	for ix: int in steps:
		for iz: int in steps:
			var base := Vector2(
				-PLATEAU_RADIUS + (float(ix) + 0.5) * GRASS_CELL,
				-PLATEAU_RADIUS + (float(iz) + 0.5) * GRASS_CELL)
			var at := base + Vector2(
				_rng.randf_range(-GRASS_CELL, GRASS_CELL) * GRASS_JITTER,
				_rng.randf_range(-GRASS_CELL, GRASS_CELL) * GRASS_JITTER)
			var inside_city := absf(at.x) <= CITY and absf(at.y) <= CITY
			if _rng.randf() > (GRASS_CHANCE_CITY if inside_city else GRASS_CHANCE_BAND):
				continue
			if not _on_plateau(at) or _in_water(at):
				continue
			if _nearest_platform_gap(at) < 1.0 or _crowded(at, 0.0):
				continue
			var model := _weighted(GRASS_MODELS, GRASS_WEIGHTS)
			var size := _rng.randf_range(0.5, 0.9)
			var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
			buckets[model].append(Transform3D(basis, Vector3(at.x, -0.06 * size, at.y)))

	var placed := 0
	for model: String in buckets:
		var transforms: Array[Transform3D] = buckets[model]
		_multimesh(group, model, transforms, false, _grass_material)
		placed += transforms.size()
	dressing_counts["Grass"] = placed


func _build_pebbles(parent: Node3D) -> void:
	var group := _group("Pebbles", parent)
	var buckets: Dictionary = {}
	for model: String in PEBBLE_MODELS:
		buckets[model] = [] as Array[Transform3D]
	var placed := 0
	for i: int in PEBBLES:
		var at := _band_point(4.0, 46.0)
		if not _on_plateau(at) or _in_water(at):
			continue
		if _nearest_platform_gap(at) < 0.4:
			continue
		var model := PEBBLE_MODELS[_rng.randi_range(0, PEBBLE_MODELS.size() - 1)]
		var size := _rng.randf_range(0.45, 1.1)
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
		buckets[model].append(Transform3D(basis, Vector3(at.x, -0.05 * size, at.y)))
		placed += 1
	for model: String in buckets:
		_multimesh(group, model, buckets[model], false, _rock_material)
	dressing_counts["Pebbles"] = placed


## The only green on the map, and only right at the water. A savanna is golden;
## a handful of flowers on the one wet patch is what says so.
func _build_flowers(parent: Node3D) -> void:
	var group := _group("Flowers", parent)
	var transforms: Array[Transform3D] = []
	for i: int in FLOWERS:
		var angle := TAU * float(i) / float(FLOWERS) + _rng.randf_range(-0.2, 0.2)
		var at := WATER_CENTRE + Vector2(cos(angle), sin(angle)) \
			* _rng.randf_range(WATER_RADIUS + 0.3, WATER_RADIUS + 2.2)
		if _nearest_platform_gap(at) < 0.6:
			continue
		var size := _rng.randf_range(0.4, 0.7)
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
		transforms.append(Transform3D(basis, Vector3(at.x, -0.04, at.y)))
	_multimesh(group, "Flower_3_Group", transforms, false, null)
	dressing_counts["Flowers"] = transforms.size()


# -------------------------------------------------------------- primitives ---

## One landing: a flat kit slab, a pillar under it, and a `Platform` record.
##
## The slab is positioned by its *top*, which is the only number the layout
## tables state, because the top is what a Gub stands on and everything else
## about the slab is a consequence of the mesh it was cut from.
func _slab(parent: Node3D, zone: String, label: String, model: String, at: Vector2,
		top: float, size: Vector3, yaw_deg: float, pillar: bool = true) -> Platform:
	var mesh := _kit(model)
	if mesh == null:
		return null
	var box := mesh.get_aabb()
	var placed_y := top - box.end.y * size.y
	_piece(parent, model, Vector3(at.x, placed_y, at.y), size, deg_to_rad(yaw_deg),
		_path_material)

	var footprint := Vector2(box.size.x * size.x, box.size.z * size.z)
	if pillar:
		_pillar(parent, at, placed_y + box.position.y * size.y, footprint)

	var landing := minf(footprint.x, footprint.y) * 0.5 - 0.15
	var record := Platform.new(Vector3(at.x, top, at.y), landing, zone, label)
	platforms.append(record)
	zone_counts[zone] = int(zone_counts.get(zone, 0)) + 1
	return record


## A boulder stretched into a column under a slab, with its rounded top poking
## 0.15 m up into the slab so there is never a seam of daylight between the two.
func _pillar(parent: Node3D, at: Vector2, underside: float, footprint: Vector2) -> void:
	var mesh := _kit("Rock_Medium_2")
	if mesh == null:
		return
	var box := mesh.get_aabb()
	var tall := (underside + 0.15) / box.end.y
	# Under about a foot there is nothing to hold up and a squashed boulder reads
	# as a lump of scree, which is what the ground-level slabs want anyway.
	if tall <= 0.12:
		return
	# The slab overhangs the pillar by 0.4-0.8 m a side, so the landing reads as
	# a shelf rather than as a plinth.
	var wide := maxf(footprint.x - 1.2, 0.9) / box.size.x
	var deep := maxf(footprint.y - 1.2, 0.9) / box.size.z
	_piece(parent, "Rock_Medium_2", Vector3(at.x, 0.0, at.y), Vector3(wide, tall, deep),
		_rng.randf_range(0.0, TAU), _rock_material)


## A block with a flat top: a stretched boulder wearing a slab. The ridge is
## eight of these and the waterhole's climb is five narrower ones.
func _mesa(parent: Node3D, zone: String, label: String, at: Vector2, top: float,
		size: Vector2, yaw_deg: float) -> Platform:
	var mesh := _kit("Rock_Medium_1")
	if mesh == null:
		return null
	var box := mesh.get_aabb()
	_piece(parent, "Rock_Medium_1", Vector3(at.x, 0.0, at.y),
		Vector3(size.x, top / box.end.y * 1.02, size.y), _rng.randf_range(0.0, TAU),
		_rock_material)
	# The slab is the ridge block's (2.6, 1.9) scaled by however much this mesa's
	# body was, so a narrow mesa gets a narrow top and the overhang stays even.
	return _slab(parent, zone, label, "RockPath_Square_Wide", at, top,
		Vector3(2.6 * size.x / 2.4, 1.5, 1.9 * size.y / 1.7), yaw_deg, false)


## A termite mound: a tall thin boulder with a small round cap. The cap is the
## landing and it is about 1.5 m across, which is what makes the field a test of
## aim rather than of nerve.
func _mound(parent: Node3D, zone: String, label: String, at: Vector2, top: float,
		cap: String, yaw_deg: float) -> Platform:
	var cap_mesh := _kit(cap)
	var body := _kit("Rock_Medium_3")
	if cap_mesh == null or body == null:
		return null
	var cap_y := top - cap_mesh.get_aabb().end.y * 1.6
	_piece(parent, "Rock_Medium_3", Vector3(at.x, 0.0, at.y),
		Vector3(0.75, (cap_y + 0.12) / body.get_aabb().end.y, 0.75),
		_rng.randf_range(0.0, TAU), _rock_material)
	return _slab(parent, zone, label, cap, at, top, Vector3(1.5, 1.6, 1.5), yaw_deg, false)


func _boulder(parent: Node3D, model: String, at: Vector3, size: Vector3, yaw: float) -> void:
	_piece(parent, model, at, size, yaw, _rock_material)


## One kit mesh in the world. Every piece of geometry on this map goes through
## here, which is also where the material override is applied — the base class
## only fixes the mesh's *own* material, so a duplicate has to be told to cull
## its back faces itself.
func _piece(parent: Node3D, model: String, at: Vector3, size: Vector3, yaw: float,
		material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := _kit(model)
	if mesh == null:
		return null
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(size), at)
	if material != null:
		for surface: int in mesh.get_surface_count():
			node.set_surface_override_material(surface, material)
	parent.add_child(node)
	return node


## A tree: the mesh, and a cylinder where the trunk is. Exactly
## `PropScatter._add_collider`'s trunk path — a cylinder 62% of the tree's height
## on layer 1 — because cover has to be reliable, and a tree you can walk through
## but not shoot through is worse than no tree at all.
func _tree(parent: Node3D, model: String, at: Vector2, size: float, yaw: float,
		trunk_radius: float, leaf: StandardMaterial3D) -> MeshInstance3D:
	var mesh := _kit(model)
	if mesh == null:
		return null
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size),
		Vector3(at.x, -0.22 * size, at.y))
	if leaf != null:
		for surface: int in mesh.get_surface_count():
			var source := mesh.surface_get_material(surface)
			if source != null and String(source.resource_name).contains("Leaves"):
				node.set_surface_override_material(surface, leaf)
	parent.add_child(node)

	var height := mesh.get_aabb().size.y * size * TRUNK_FRACTION
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.position = Vector3(at.x, 0.0, at.y)
	var cylinder := CylinderShape3D.new()
	cylinder.radius = trunk_radius * size
	cylinder.height = height
	var shape := CollisionShape3D.new()
	shape.shape = cylinder
	shape.position = Vector3.UP * height * 0.5
	body.add_child(shape)
	parent.add_child(body)
	_occupied.append(Vector3(at.x, at.y, trunk_radius * size + 0.6))
	return node


func _acacia(parent: Node3D, at: Vector2) -> void:
	var model := ACACIA_MODELS[_rng.randi_range(0, ACACIA_MODELS.size() - 1)]
	var wide := _rng.randf_range(1.8, 2.1)
	var mesh := _kit(model)
	if mesh == null:
		return
	var node := MeshInstance3D.new()
	node.mesh = mesh
	# Wide and barely taller: the squash is the whole disguise.
	var size := Vector3(wide, _rng.randf_range(1.05, 1.25), wide * _rng.randf_range(0.94, 1.06))
	node.transform = Transform3D(
		Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(size),
		Vector3(at.x, -0.24, at.y))
	for surface: int in mesh.get_surface_count():
		var source := mesh.surface_get_material(surface)
		if source != null and String(source.resource_name).contains("Leaves"):
			node.set_surface_override_material(surface, _acacia_leaf)
	parent.add_child(node)

	var height := mesh.get_aabb().size.y * size.y * TRUNK_FRACTION
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.position = Vector3(at.x, 0.0, at.y)
	var cylinder := CylinderShape3D.new()
	cylinder.radius = TRUNK_ACACIA * wide * 0.5
	cylinder.height = height
	var shape := CollisionShape3D.new()
	shape.shape = cylinder
	shape.position = Vector3.UP * height * 0.5
	body.add_child(shape)
	parent.add_child(body)
	_occupied.append(Vector3(at.x, at.y, TRUNK_ACACIA * wide * 0.5 + 0.8))


func _convex_body(parent: Node3D, from: MeshInstance3D) -> void:
	var convex := from.mesh.create_convex_shape(true, true)
	if convex == null:
		return
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.transform = from.transform
	var shape := CollisionShape3D.new()
	shape.shape = convex
	body.add_child(shape)
	parent.add_child(body)


func _multimesh(parent: Node3D, model: String, transforms: Array[Transform3D],
		shadows: bool, material: StandardMaterial3D) -> void:
	if transforms.is_empty():
		return
	var mesh := _kit(model)
	if mesh == null:
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
	node.name = model
	node.multimesh = multi
	node.custom_aabb = bounds
	if material != null:
		node.material_override = material
	node.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	parent.add_child(node)


# --------------------------------------------------------------- materials ---

## The palette. Everything starts as a duplicate of the kit's own material, so
## the textures that make a rock look like a rock are kept and only the tint
## changes — a savanna is the same kit under a different sun, not a different kit.
func _build_materials() -> void:
	_rock_material = _kit_material("Rock_Medium_1", 0)
	if _rock_material != null:
		_rock_material.albedo_texture = load(DESERT_DIFFUSE)
		_rock_material.albedo_color = Color(1.0, 0.93, 0.84)

	_path_material = _kit_material("RockPath_Square_Wide", 0)
	if _path_material != null:
		_path_material.albedo_color = Color(1.0, 0.86, 0.66)

	_grass_material = _kit_material("Grass_Wispy_Short", 0)
	if _grass_material != null:
		_grass_material.albedo_color = Color(1.0, 0.84, 0.42)
		# Grass cards are two-sided by nature: culling one face of a billboard
		# is a blade that disappears when you walk around it.
		_grass_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# The bush is the twisted tree's leaf card on a small mesh, so it had the
	# same red problem as the baobab and gets the same fix.
	_bush_material = _kit_material("Bush_Common", 0)
	if _bush_material != null:
		_bush_material.albedo_texture = load(LEAVES_TWISTED_WHITE)
		_bush_material.albedo_color = BUSH_TINT
		_bush_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_acacia_leaf = _leaf_material("CommonTree_1")
	if _acacia_leaf != null:
		_acacia_leaf.albedo_texture = load(LEAVES_NORMAL_WHITE)
		_acacia_leaf.albedo_color = ACACIA_TINT
	_baobab_leaf = _leaf_material("TwistedTree_2")
	if _baobab_leaf != null:
		_baobab_leaf.albedo_texture = load(LEAVES_TWISTED_WHITE)
		_baobab_leaf.albedo_color = BAOBAB_TINT

	_ground_material = StandardMaterial3D.new()
	_ground_material.albedo_color = Color(0.80, 0.68, 0.44)
	_ground_material.albedo_texture = _ground_texture()
	# One noise tile every ten metres. The UVs are already xz/8, so 0.8 of that
	# is a ten-metre period — big enough to break the flatness up, small enough
	# that the repeat is not a pattern anyone can see from the summit.
	_ground_material.uv1_scale = Vector3(0.8, 0.8, 1.0)
	_ground_material.roughness = 1.0
	_ground_material.cull_mode = BaseMaterial3D.CULL_BACK

	_water_material = StandardMaterial3D.new()
	_water_material.albedo_color = Color(0.20, 0.48, 0.70, 0.82)
	_water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_material.roughness = 0.05
	_water_material.metallic = 0.1
	_water_material.cull_mode = BaseMaterial3D.CULL_BACK


## Sand, as a noise texture rather than a flat colour. A 96 m plateau of one
## albedo reads as a floor tile from the summit; one octave of noise between two
## sands is all it takes for it to read as ground.
func _ground_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05
	noise.seed = SEED
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.72, 0.58, 0.36))
	ramp.set_color(1, Color(0.90, 0.80, 0.56))
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.seamless = true
	texture.width = 512
	texture.height = 512
	texture.color_ramp = ramp
	return texture


func _kit_material(model: String, surface: int) -> StandardMaterial3D:
	var mesh := _kit(model)
	if mesh == null:
		return null
	var source := mesh.surface_get_material(surface) as StandardMaterial3D
	var copy := (source.duplicate() if source != null else StandardMaterial3D.new()) as StandardMaterial3D
	# The base class turns culling back on for the materials the *meshes* carry.
	# An override is not one of those, so it has to say so here or every slab on
	# the map is rasterised twice.
	copy.cull_mode = BaseMaterial3D.CULL_BACK
	return copy


func _leaf_material(model: String) -> StandardMaterial3D:
	var mesh := _kit(model)
	if mesh == null:
		return null
	for surface: int in mesh.get_surface_count():
		var source := mesh.surface_get_material(surface) as StandardMaterial3D
		if source != null and String(source.resource_name).contains("Leaves"):
			var copy := source.duplicate() as StandardMaterial3D
			copy.cull_mode = BaseMaterial3D.CULL_DISABLED
			return copy
	return null


# ------------------------------------------------------------------- tests ---

## Push a point out of every landing it stands inside, and hand back where it
## ended up. Used for the dressing, which is placed by coordinate or by dart
## throw and must never end up on top of a platform.
func _clear_of_platforms(at: Vector2, keep: float) -> Vector2:
	var here := at
	for attempt: int in 24:
		var worst: Platform = null
		var worst_gap := 0.0
		for platform: Platform in platforms:
			var centre := Vector2(platform.centre.x, platform.centre.z)
			var want := platform.radius + keep
			var gap := want - here.distance_to(centre)
			if gap > worst_gap:
				worst = platform
				worst_gap = gap
		if worst == null:
			return here
		var centre := Vector2(worst.centre.x, worst.centre.z)
		var away := here - centre
		if away.length() < 0.0001:
			away = Vector2.RIGHT
		here += away.normalized() * (worst_gap + 0.05)
	return here


## How far this point is from the nearest platform's *centre*.
func _nearest_platform(at: Vector2) -> float:
	var best := INF
	for platform: Platform in platforms:
		best = minf(best, at.distance_to(Vector2(platform.centre.x, platform.centre.z)))
	return best


## How far this point is from the nearest platform's *edge*. Negative means it
## is standing on one.
func _nearest_platform_gap(at: Vector2) -> float:
	var best := INF
	for platform: Platform in platforms:
		var d := at.distance_to(Vector2(platform.centre.x, platform.centre.z)) - platform.radius
		best = minf(best, d)
	return best


func _spawn_clear(at: Vector2, keep: float) -> bool:
	for pad: Vector3 in spawn_keepouts:
		if at.distance_to(Vector2(pad.x, pad.z)) < keep:
			return false
	return true


func _crowded(at: Vector2, gap: float) -> bool:
	for taken: Vector3 in _occupied:
		if at.distance_to(Vector2(taken.x, taken.y)) < maxf(gap, taken.z):
			return true
	return false


func _in_water(at: Vector2) -> bool:
	return at.distance_to(WATER_CENTRE) < WATER_RADIUS + 0.4


func _on_plateau(at: Vector2) -> bool:
	if at.length() < 0.001:
		return true
	var rim := _rim_point(atan2(at.y, at.x))
	return at.length() <= rim.length() - 1.0


## A dart throw into the ring between two radii, thrown so the area is even.
func _band_point(inner: float, outer: float) -> Vector2:
	var angle := _rng.randf_range(0.0, TAU)
	var r := sqrt(_rng.randf_range(inner * inner, outer * outer))
	return Vector2(cos(angle), sin(angle)) * r


func _weighted(models: PackedStringArray, weights: PackedFloat32Array) -> String:
	var roll := _rng.randf()
	var running := 0.0
	for i: int in models.size():
		running += weights[i]
		if roll <= running:
			return models[i]
	return models[models.size() - 1]


# ----------------------------------------------------------------- harness ---

## The one bearing helper. `bearing(b, r)` is `(cos b, sin b) * r` on (x, z),
## with b in degrees — so 0 is +x, 90 is +z, and every zone in the table above
## means the same thing by "250 degrees".
static func bearing(degrees: float, radius: float) -> Vector2:
	var angle := deg_to_rad(degrees)
	return Vector2(cos(angle), sin(angle)) * radius


func _kit(model: String) -> Mesh:
	if _mesh_cache.has(model):
		return _mesh_cache[model]
	var mesh := PropScatter.load_kit_mesh(model)
	_mesh_cache[model] = mesh
	return mesh


func _group(named: String, under: Node3D = null) -> Node3D:
	var node := Node3D.new()
	node.name = named
	(under if under != null else self).add_child(node)
	return node


## The pads, read off the markers the scene carries. Local rather than global on
## purpose: the dressing is placed in the map's own frame, and the map is at the
## origin in the arena and in every preview.
func _read_spawns() -> void:
	var root := get_node_or_null("Spawns")
	if root == null:
		return
	for child in root.get_children():
		var marker := child as Marker3D
		if marker != null:
			spawn_keepouts.append(marker.position)


func _zone_line() -> String:
	var parts: Array[String] = []
	for zone: String in zone_counts:
		parts.append("%s %d" % [zone, int(zone_counts[zone])])
	return ", ".join(parts)


func _dressing_line() -> String:
	var parts: Array[String] = []
	for layer: String in dressing_counts:
		parts.append("%s %d" % [layer, int(dressing_counts[layer])])
	return ", ".join(parts)
