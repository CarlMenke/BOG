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
##               Gub's kit, the one-tick dive included — `tools/parkour_report`
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
## floor paint, the door bars, the cranes over the wall, the floodlights.
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
var _floor_material: StandardMaterial3D
var _paint_line: StandardMaterial3D
var _steel: StandardMaterial3D
var _lamp: StandardMaterial3D


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
	_build_floodlights(dressing)


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
