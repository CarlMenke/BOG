class_name RustMap
extends StaticMap
## Rust — the bought drilling yard, and the atmosphere built around it.
##
## This is the odd one of the four static maps. Kopje Crossing, Lantern Wharf
## and Halcyon Wake are *built*: their scripts lay out a hundred and some
## meshes from tables and then call `super()` to sweep them into collision.
## Rust's geometry is a 96,301-triangle `.glb` that `rust.tscn` instances
## whole, and which is never edited (D-029, D-030, D-031) — so this script
## builds no geometry at all and `super()` is the *first* line of `_ready()`
## rather than the middle one.
##
## The rule the other three share still holds and is the only structural rule
## here: **everything below `super()` is dressing and is never collision.**
## `StaticMap._ready()` has already walked the subtree and baked every triangle
## it found into world-space trimesh shapes by the time the first line of this
## file's own work runs, so nothing added afterwards can be stood on, shot,
## walked into or landed on. That is what makes it safe to hang sixty metres of
## refinery off the side of a map whose spawn pads are checked by a gate.
##
## What is added, and why this map and no other:
##
##   backdrop   The yard used to visibly end at its own fence. A tank farm, a
##              cracking column, a flare stack, three derricks, a line of pylons
##              and four buttes, out between 110 and 460 m, say that this is one
##              corner of an oilfield rather than the whole world. All of it is
##              in `StaticMap.BACKDROP_GROUP`, so `tools/preview_map.gd` still
##              frames the 43 x 64 m yard and not the 900 m basin (D-057).
##   air        Wind-blown grit near the ground and a slow dust field over the
##              whole yard. The map is "hot and airless" and airless is a thing
##              you can only show by putting something *in* the air.
##   shimmer    Heat haze off the hot surfaces, as screen-space refraction
##              panels. Belongs to no other map in the game: the island is a
##              cold night, the wharf is dusk, the yacht is a sea breeze.
##   light      A flare that burns and flickers on the horizon, and two sodium
##              lamps on the yard that are still on because nobody came back to
##              switch them off. The sun is white-hot and everything it touches
##              is blue-grey steel; these are the only warm accents in the map.
##   ground     Decals — oil under the pump gear, spill round the barrels, tyre
##              tracks across the open ground. The caliche is the largest flat
##              area in every frame and it had nothing on it.
##   audio      The wiring for two ambient loops, following
##              `scripts/world/ambience.gd::_build_audio` exactly.
##
## Everything with a random number in it is seeded from `SEED`, and every
## particle emitter carries `use_fixed_seed`, so two clients looking at the same
## corner of the yard see the same grit in the air. None of it is gameplay, but
## "why is this frame different" is a question worth never having to ask, and it
## is free to be sure of.

# ------------------------------------------------------------------ the map ---

## The main walkable plane, measured with `tools/preview_map.gd probe` — the
## yard is not at y = 0, it is a metre and three quarters up the `.glb`'s own
## ground mesh, and every pad in `rust.tscn` sits 0.12 m above it.
const FLOOR := 1.73
## The middle of the yard on the ground plane, which is where `preview_map`
## puts its camera target and what every pad faces.
const YARD_CENTRE := Vector2(-0.8, -5.0)
## Half the yard across, and how far it runs. From the `.glb`'s bounds:
## x -22.4 .. 20.8, z -37.1 .. 27.1.
const YARD_HALF_X := 21.5
const YARD_Z_MIN := -37.0
const YARD_Z_MAX := 26.0

## The compass bearing the sun comes from, in degrees, matching `rust.tscn`'s
## `Sun` exactly: `atan2(x, z)` of the direction *toward* it. Everything in this
## file that needs to know where the light is — the wind, the grit's drift, the
## side of the yard the shimmer stands on — reads it from here rather than
## guessing, so moving the sun moves them all together.
const SUN_BEARING := 51.0
## Where the wind comes from. Across the sun rather than along it, because grit
## blowing straight down the light path is grit you cannot see; lit from the
## side it is what the light is *for*.
const WIND_BEARING := SUN_BEARING - 62.0

## One seed for the whole map's dressing. Not gameplay — see the header.
const SEED := 0x52555354  # "RUST"

# ----------------------------------------------------------------- backdrop ---

## The world past the walls, as (kind, bearing, distance, height) and a label.
##
## `bearing` is a compass angle in degrees — `atan2(x, z)`, the same convention
## `rust.tscn`'s `Sun` and `rust_sky.tres`'s yaw use — and `distance` is metres
## from `YARD_CENTRE`. `height` is metres above the desert floor, which is taken
## as `FLOOR` because everything here is far enough away that a metre of ground
## either way is invisible.
##
## The heights are large and they have to be. The `.glb` rings the yard with a
## berm that tops out at 12.6 m, and from eye height on a pad that berm is about
## seventeen degrees up; anything at 150 m that is shorter than fifty metres is
## simply behind it. So this is a table of tall thin things, which is also what
## an oilfield looks like — the tanks are the one squat entry and they are the
## closest, at 118 m, for exactly that reason.
##
## Bearings are spread round three quarters of the circle rather than all of it.
## The south-east quarter is left empty on purpose: it is the one direction the
## yard opens out in, and a horizon with something in every direction reads as a
## diorama with a painted wall round it, which is the problem this table exists
## to fix.
const BACKDROP: Array[Dictionary] = [
	# The tank farm: five squat storage tanks with a rim walkway, close enough
	# to clear the berm and read as objects rather than as silhouettes.
	{"kind": "tanks", "bearing": 104.0, "distance": 118.0, "height": 19.0, "label": "tank farm"},
	# The refinery proper: a cracking column and its two smaller stacks, the
	# tallest thing on the horizon after the flare.
	{"kind": "column", "bearing": 126.0, "distance": 168.0, "height": 58.0, "label": "cracker"},
	# The flare. Its flame is built separately, in `_build_flare`, because it is
	# the one thing out here that moves and has a light on it.
	{"kind": "flare", "bearing": 113.0, "distance": 152.0, "height": 64.0, "label": "flare stack"},
	# Three more derricks, so this yard's tower is one of a field of them and
	# not a monument. Deliberately different heights and distances: a row of
	# equal towers reads as a fence.
	{"kind": "derrick", "bearing": -34.0, "distance": 132.0, "height": 46.0, "label": "derrick N"},
	{"kind": "derrick", "bearing": -97.0, "distance": 176.0, "height": 41.0, "label": "derrick W"},
	{"kind": "derrick", "bearing": 171.0, "distance": 214.0, "height": 38.0, "label": "derrick S"},
	# The buttes: the basin's far wall, behind everything else. The panorama has
	# its own mountains further out still, so these are a middle layer — and a
	# middle layer is the whole of what makes a horizon read as distance rather
	# than as a backdrop.
	{"kind": "butte", "bearing": -148.0, "distance": 340.0, "height": 74.0, "label": "butte NW"},
	{"kind": "butte", "bearing": -62.0, "distance": 415.0, "height": 96.0, "label": "butte W"},
	{"kind": "butte", "bearing": 44.0, "distance": 300.0, "height": 62.0, "label": "butte NE"},
	{"kind": "butte", "bearing": 150.0, "distance": 380.0, "height": 88.0, "label": "butte S"},
]

## The transmission line: towers on one bearing, marching away. Distances rather
## than a count and a step, so the near end can be dense and the far end sparse
## the way a line disappearing over a rise actually looks.
const PYLON_BEARING := -66.0
const PYLON_DISTANCES: PackedFloat32Array = [124.0, 178.0, 244.0, 322.0, 412.0]
const PYLON_HEIGHT := 44.0

## Everything out there is the same dust-bleached grey-brown, lit by the same
## sun and sitting in the same fog. Three tints rather than one so the layers
## separate: steel is nearest, concrete is the tanks, rock is the buttes.
const BACKDROP_STEEL := Color(0.34, 0.31, 0.28)
const BACKDROP_CONCRETE := Color(0.44, 0.41, 0.36)
const BACKDROP_ROCK := Color(0.52, 0.42, 0.33)

# ---------------------------------------------------------------------- air ---

## Grit: what the wind picks up off the yard floor. Low, quick, and lit from the
## side. 240 over a 43 x 64 m yard is one every eleven square metres, which
## sounds thin and is not — they are moving, and a moving mote is worth a dozen
## still ones.
const GRIT_COUNT := 240
const GRIT_LIFETIME := 7.0
const GRIT_TOP := 3.4

## Dust: the slow high field, up past the container stacks and into the tower.
## This is the layer that gives the middle distance something to be, the same
## job the island's 420 spores do (`ambience.gd`), and the count is deliberately
## the same because the volume is comparable.
const DUST_COUNT := 420
const DUST_LIFETIME := 24.0
const DUST_TOP := 20.0

## Smoke off the flare. Far away, so it can be few and large.
const FLARE_SMOKE_COUNT := 44

## Three emitters at 240 + 420 + 44 is 704 particles, against Whisperbloom
## Hollow's 192 fireflies + 420 spores + 60 leaves = 672. Same order, and this
## map has no scatter, no torches and no generated terrain to pay for.

# ------------------------------------------------------------------ shimmer ---

## Heat haze panels, as (x, y, z, width, height). `y` is the *bottom* edge.
##
## Every one of these stands against something the eye reads as far away — the
## container walls at the two ends of the yard, the roof line down each side,
## and the tower's own structure — and none of them stands across the open
## ground in the middle where a fight happens. That is the whole readability
## rule for this effect: a Bog seen *through* shimmer at 30 m has its edge
## crawl, which is weather; a Bog seen through shimmer at 8 m would dissolve,
## which is a bug. Panels are also all above 3.4 m, which is over a Bog's head
## (a Bog is 1.55 m) — so nothing at eye level in the yard is ever behind one.
const SHIMMER: Array[Dictionary] = [
	# Over the north wall, at the far end of the longest sightline on the map.
	{"at": Vector3(-6.0, 5.2, -33.0), "size": Vector2(26.0, 5.0)},
	{"at": Vector3(12.0, 5.0, -31.0), "size": Vector2(18.0, 4.5)},
	# Down the east and west roof lines.
	{"at": Vector3(18.5, 4.6, -12.0), "size": Vector2(22.0, 4.0)},
	{"at": Vector3(-19.5, 4.6, -16.0), "size": Vector2(22.0, 4.0)},
	# The south end, over the low wall and the open ground beyond it.
	{"at": Vector3(-4.0, 4.4, 20.0), "size": Vector2(24.0, 4.5)},
	# And off the drilling tower itself, which is the hottest steel in the yard
	# and the thing every pad is pointed at.
	{"at": Vector3(-5.0, 13.0, -7.0), "size": Vector2(20.0, 9.0)},
]

# ------------------------------------------------------------------- lights ---

## The flare's flame, at the top of its stack. Everything about it is big
## because it is 152 m away: a flame you could see from a yard at that range is
## several metres of burning gas.
const FLARE_FLAME_HEIGHT := 9.0
const FLARE_FLAME_WIDTH := 3.4
const FLARE_COLOUR := Color(1.0, 0.52, 0.16)
const FLARE_LIGHT_ENERGY := 26.0
const FLARE_LIGHT_RANGE := 60.0

## The two sodium lamps still burning in the yard, as (position, aim).
##
## They are on structure the `.glb` already has — the west tower's platform and
## the north gantry — read off the imported node bounds rather than guessed, so
## neither is a lamp floating in mid-air. Sodium because it is the one lamp
## colour that is unmistakably *not* daylight: 2000 K against the sun's 5500,
## which under a sky this blue reads as orange from across the map.
##
## No shadows on either. The sun already casts, and at this hour its long
## shadows are what give the containers their shape; two more shadow atlases for
## two fill lights would be most of a millisecond for nothing anybody looks at.
const LAMPS: Array[Dictionary] = [
	{"at": Vector3(-13.4, 10.4, 9.4), "aim": Vector3(-8.0, FLOOR, 4.0), "label": "west tower"},
	{"at": Vector3(-0.3, 10.6, -14.9), "aim": Vector3(-2.0, FLOOR, -19.0), "label": "north gantry"},
]
const LAMP_COLOUR := Color(1.0, 0.56, 0.14)
const LAMP_ENERGY := 7.0
const LAMP_RANGE := 15.0

# ------------------------------------------------------------------- ground ---

## Ground decals, as (kind, x, z, size, yaw). `size` is metres across; a decal
## is square unless the kind says otherwise. Projected straight down on to
## whatever the `.glb` has there, which is the point of using a `Decal` at all:
## it marks bought geometry without editing a triangle of it, and it survives
## the next re-import of the `.glb` because it is not in the `.glb`.
##
## Placed on open floor that `tools/preview_map.gd probe` reports as the main
## plane, so none of them is draped over a container or a barrel.
const DECALS: Array[Dictionary] = [
	{"kind": "oil", "at": Vector2(-3.0, -18.0), "size": 5.5, "yaw": 0.4},
	{"kind": "oil", "at": Vector2(7.5, -21.0), "size": 4.0, "yaw": 1.9},
	{"kind": "oil", "at": Vector2(-15.5, -22.0), "size": 3.2, "yaw": 2.7},
	{"kind": "oil", "at": Vector2(4.0, 6.0), "size": 6.0, "yaw": 1.1},
	{"kind": "oil", "at": Vector2(-9.0, 12.0), "size": 3.6, "yaw": 0.2},
	{"kind": "oil", "at": Vector2(13.0, -3.0), "size": 4.4, "yaw": 2.2},
	{"kind": "oil", "at": Vector2(-17.0, -9.0), "size": 3.0, "yaw": 0.9},
	# Tyre tracks: long and thin, laid along the two lanes anything on wheels
	# would have used — up the middle of the yard and across the south end.
	{"kind": "tracks", "at": Vector2(-1.0, -12.0), "size": 22.0, "yaw": 0.06},
	{"kind": "tracks", "at": Vector2(0.0, 9.0), "size": 20.0, "yaw": 1.62},
	{"kind": "tracks", "at": Vector2(-14.0, -2.0), "size": 18.0, "yaw": 0.10},
	{"kind": "tracks", "at": Vector2(9.0, -14.0), "size": 16.0, "yaw": 1.45},
]
## How far a decal reaches down from the height it is placed at. Tall enough to
## find the floor under an uneven `.glb`, short enough not to wrap round the
## foot of a barrel.
const DECAL_DEPTH := 1.6
## Ground decals stop being drawn past this, with a margin to fade over. At 60 m
## a 4 m stain is a smudge and drawing it is a clustered-decal slot spent on
## nothing.
const DECAL_FADE_BEGIN := 46.0
const DECAL_FADE_LENGTH := 14.0

# -------------------------------------------------------------------- audio ---

## Ambient loops, by the bus they belong on — the same wiring, node for node, as
## `ambience.gd::_build_audio`, and for the same reason: each is placed as a
## positioned looping `AudioStreamPlayer3D` on the Ambience bus and each is
## skipped **in silence** when its file is not on disk.
##
## `ambient_wind.wav` is the one the repository already has, and it is the right
## bed for a dry basin — it is the same wind whether it is blowing over an
## island rim or a container yard. The second path is named and is not there
## yet: what this map wants under the wind is loose steel — a door banging, a
## net in the wind, the tower ticking as it cools. Naming it is how it gets
## made. Nothing is synthesised to stand in for it; a placeholder tone would
## have to be found and deleted later, and in the meantime every playtest would
## be judging a mixing decision made against a sine wave.
const LOOPS := {
	"wind": "res://audio/ambience/ambient_wind.wav",
	"yard": "res://audio/ambience/ambient_rust_yard.wav",
}

# -------------------------------------------------------------------- state ---

## What the build actually did, for the log line and the decision record.
var backdrop_pieces: int = 0
var backdrop_triangles: int = 0
var particles: int = 0
var decals: int = 0
var lights: int = 0

var _flare_light: OmniLight3D
var _flare_flame: MeshInstance3D
var _flare_material: StandardMaterial3D
var _clock: float = 0.0


func _ready() -> void:
	# `super()` FIRST, and it is the whole of the collision build: the `.glb`
	# `rust.tscn` instances is already in the subtree, and `StaticMap._ready()`
	# sweeps it into world-space trimesh shapes on layer 1 and puts back the
	# back-face culling the importer turned off. Nothing this file adds is
	# above this line, so nothing this file adds is collision.
	super()

	var started := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	var dressing := _group("Dressing")
	_build_backdrop(dressing, rng)
	_build_flare(dressing)
	_build_air(dressing)
	_build_shimmer(dressing)
	_build_lamps(dressing)
	_build_decals(dressing, rng)
	_build_audio(dressing)

	print("%s: %d backdrop pieces (%d triangles), %d particles, %d decals, "
		% [name, backdrop_pieces, backdrop_triangles, particles, decals]
		+ "%d lights in %d ms" % [lights, Time.get_ticks_msec() - started])


## The flare, and only the flare. Time-driven rather than random so every client
## sees the same flame at the same moment without anything being sent about it.
func _process(delta: float) -> void:
	if _flare_light == null:
		return
	_clock += delta
	# Three incommensurate rates. A single sine has a period the eye finds in
	# about four seconds and stops believing; three do not line up again inside
	# a match.
	var flicker := 0.70 + 0.30 * (0.52 * sin(_clock * 5.3) + 0.30 * sin(_clock * 11.7)
		+ 0.18 * sin(_clock * 2.3))
	_flare_light.light_energy = FLARE_LIGHT_ENERGY * flicker
	_flare_material.emission_energy_multiplier = 9.0 * flicker
	# The flame leans and stretches rather than pulsing on the spot: gas flares
	# are bent over by their own wind and the length is what changes.
	_flare_flame.scale = Vector3(1.0, 0.82 + 0.34 * flicker, 1.0)
	_flare_flame.rotation.z = 0.16 * sin(_clock * 1.7) + 0.07 * sin(_clock * 6.1)


# ----------------------------------------------------------------- backdrop ---

## The oilfield this yard is a corner of.
##
## One `SurfaceTool` for all of it, committed as a single `MeshInstance3D` with
## vertex colours: ten structures, five pylons and four buttes come out as one
## draw call. None of it casts a shadow — the sun's shadow range is 90 m and the
## nearest of these is at 118 — and all of it is in `BACKDROP_GROUP` so
## `preview_map` keeps framing the yard.
func _build_backdrop(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for entry: Dictionary in BACKDROP:
		var at := _bearing_point(float(entry["bearing"]), float(entry["distance"]))
		var height := float(entry["height"])
		match String(entry["kind"]):
			"tanks":
				_tank_farm(st, at, height, rng)
			"column":
				_cracking_column(st, at, height)
			"flare":
				_lattice(st, at, height, 5.5, 2.2, BACKDROP_STEEL)
			"derrick":
				_lattice(st, at, height, 7.0, 2.4, BACKDROP_STEEL)
			"butte":
				_butte(st, at, height, rng)
		backdrop_pieces += 1

	for distance: float in PYLON_DISTANCES:
		_pylon(st, _bearing_point(PYLON_BEARING, distance), PYLON_HEIGHT)
		backdrop_pieces += 1

	var mesh := st.commit()
	backdrop_triangles = mesh.get_faces().size() / 3

	var node := MeshInstance3D.new()
	node.name = "Backdrop"
	node.mesh = mesh
	node.material_override = _backdrop_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_to_group(BACKDROP_GROUP)
	parent.add_child(node)


func _backdrop_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.92
	material.metallic = 0.0
	# Specular off entirely. A dry silhouette at 150 m through 41% fog has no
	# highlight on it, and a highlight out there would read as a light source.
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material


## Five storage tanks, a low bund wall round them, and a walkway rim on each.
func _tank_farm(st: SurfaceTool, at: Vector2, height: float,
		rng: RandomNumberGenerator) -> void:
	var spots: Array[Vector2] = [
		Vector2(-30.0, -14.0), Vector2(0.0, -18.0), Vector2(30.0, -12.0),
		Vector2(-16.0, 16.0), Vector2(18.0, 14.0),
	]
	for spot: Vector2 in spots:
		var radius := rng.randf_range(11.0, 14.5)
		var tall := height * rng.randf_range(0.82, 1.12)
		var foot := Vector3(at.x + spot.x, FLOOR, at.y + spot.y)
		_cylinder(st, foot, radius, tall, 16, BACKDROP_CONCRETE)
		# The rim walkway: a thin ring a touch proud of the shell, which is the
		# one detail that stops a cylinder reading as a tin can.
		_cylinder(st, foot + Vector3.UP * (tall - 0.9), radius + 0.7, 0.9, 16,
			BACKDROP_STEEL)
	# The bund: the low wall that catches a tank when it splits.
	_box(st, Vector3(at.x, FLOOR, at.y), Vector3(78.0, 2.8, 46.0),
		BACKDROP_CONCRETE.darkened(0.26))


## A cracking column and the two smaller stacks beside it, tied together with
## horizontal gantries. The tallest thing on the horizon after the flare.
func _cracking_column(st: SurfaceTool, at: Vector2, height: float) -> void:
	var main := Vector3(at.x, FLOOR, at.y)
	_cylinder(st, main, 4.6, height, 12, BACKDROP_CONCRETE)
	_cylinder(st, main + Vector3.UP * height, 2.0, 5.0, 8, BACKDROP_STEEL)
	var stacks: Array[Vector3] = [
		Vector3(-14.0, 0.0, 6.0), Vector3(13.0, 0.0, -5.0), Vector3(22.0, 0.0, 9.0),
	]
	var shrink := [0.66, 0.78, 0.52]
	for i: int in stacks.size():
		var foot := main + stacks[i]
		var tall := height * float(shrink[i])
		_cylinder(st, foot, 3.0, tall, 10, BACKDROP_CONCRETE.darkened(0.12))
		# A gantry back to the column at two thirds height, so the group reads
		# as one plant rather than three unrelated pipes.
		_beam(st, foot + Vector3.UP * tall * 0.66, main + Vector3.UP * tall * 0.66, 0.9,
			BACKDROP_STEEL)
	# The structure under it all, which is what says "refinery" and not "silo".
	_box(st, main + Vector3(4.0, 0.0, 2.0), Vector3(38.0, 12.0, 24.0),
		BACKDROP_STEEL.lightened(0.04))


## A four-legged lattice mast, tapering, with cross-bracing — the shape of every
## drilling derrick and flare stack ever built, and the shape of the one this
## map already has standing in the middle of it.
##
## Eight bays up the height. The bracing is what makes it read as lattice rather
## than as a pylon-shaped box, and at 130 m it is exactly at the edge of what the
## eye resolves, which is the right place for it to be.
func _lattice(st: SurfaceTool, at: Vector2, height: float, base: float, top: float,
		tint: Color) -> void:
	var bays := 8
	var foot := Vector3(at.x, FLOOR, at.y)
	for bay: int in bays:
		var y0 := height * float(bay) / float(bays)
		var y1 := height * float(bay + 1) / float(bays)
		var h0 := lerpf(base, top, float(bay) / float(bays)) * 0.5
		var h1 := lerpf(base, top, float(bay + 1) / float(bays)) * 0.5
		var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1),
			Vector2(-1, 1)]
		for i: int in 4:
			var c: Vector2 = corners[i]
			var d: Vector2 = corners[(i + 1) % 4]
			var a := foot + Vector3(c.x * h0, y0, c.y * h0)
			var b := foot + Vector3(c.x * h1, y1, c.y * h1)
			# The leg.
			_beam(st, a, b, 0.55, tint)
			# One diagonal per face per bay, alternating direction so the
			# bracing zig-zags up the tower instead of spiralling.
			var e := foot + Vector3(d.x * h0, y0, d.y * h0)
			var f := foot + Vector3(d.x * h1, y1, d.y * h1)
			if bay % 2 == 0:
				_beam(st, a, f, 0.34, tint)
			else:
				_beam(st, e, b, 0.34, tint)
			# The ring at the top of the bay.
			_beam(st, b, f, 0.34, tint)


## A transmission tower: two legs splayed out to a waist, a body, and three
## cross-arms. Drawn small and simple — at 124 m and beyond the only thing that
## survives is the silhouette, and the silhouette is the cross-arms.
func _pylon(st: SurfaceTool, at: Vector2, height: float) -> void:
	var foot := Vector3(at.x, FLOOR, at.y)
	var waist := height * 0.45
	var spread := height * 0.18
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_beam(st, foot + Vector3(sx * spread, 0.0, sz * spread),
				foot + Vector3(sx * 1.6, waist, sz * 1.6), 0.5, BACKDROP_STEEL)
			_beam(st, foot + Vector3(sx * 1.6, waist, sz * 1.6),
				foot + Vector3(sx * 1.1, height, sz * 1.1), 0.4, BACKDROP_STEEL)
	# Three cross-arms, the lowest widest, and a peak above them.
	var arms := [Vector2(waist + 4.0, 11.0), Vector2(waist + 12.0, 9.0),
		Vector2(height - 3.0, 7.0)]
	for arm: Vector2 in arms:
		_beam(st, foot + Vector3(-arm.y, arm.x, 0.0), foot + Vector3(arm.y, arm.x, 0.0),
			0.45, BACKDROP_STEEL)
	_beam(st, foot + Vector3(0.0, height, 0.0), foot + Vector3(0.0, height + 4.0, 0.0),
		0.35, BACKDROP_STEEL)


## A mesa: a slab with a flat top, a fluted cliff and a talus skirt at its foot.
##
## Built from a ring of radii rather than a box, so no two are the same shape,
## and the top is *flat* — that is the whole difference between a mesa and a
## hill, and this basin is full of the first kind. The `.glb` has its own low
## buttes round the yard at 30 m; these stand behind them at 300 to 415, with
## the panorama's real mountains behind those again.
func _butte(st: SurfaceTool, at: Vector2, height: float, rng: RandomNumberGenerator) -> void:
	var segments := 22
	var radius := height * rng.randf_range(1.5, 2.4)
	var foot := Vector3(at.x, FLOOR - 4.0, at.y)
	var top := Color(BACKDROP_ROCK).lightened(0.10)
	var cliff := Color(BACKDROP_ROCK).darkened(0.06)
	var talus := Color(BACKDROP_ROCK).lightened(0.18)

	var out := PackedFloat32Array()
	for i: int in segments:
		# Fluting: a low-frequency wobble on the plan, which is what a weathered
		# cliff face does and what keeps the silhouette from being a drum.
		var t := TAU * float(i) / float(segments)
		out.append(radius * (0.78 + 0.22 * sin(t * 3.0 + rng.randf() * 0.3)
			+ 0.10 * sin(t * 7.0)))

	for i: int in segments:
		var j := (i + 1) % segments
		var a := TAU * float(i) / float(segments)
		var b := TAU * float(j) / float(segments)
		var ra := out[i]
		var rb := out[j]
		var pa := foot + Vector3(cos(a) * ra, 0.0, sin(a) * ra)
		var pb := foot + Vector3(cos(b) * rb, 0.0, sin(b) * rb)
		var ta := foot + Vector3(cos(a) * ra * 0.74, height, sin(a) * ra * 0.74)
		var tb := foot + Vector3(cos(b) * rb * 0.74, height, sin(b) * rb * 0.74)
		# The talus skirt: a wider, shallower cone at the bottom third.
		var sa := foot + Vector3(cos(a) * ra * 1.35, -1.0, sin(a) * ra * 1.35)
		var sb := foot + Vector3(cos(b) * rb * 1.35, -1.0, sin(b) * rb * 1.35)
		_quad(st, sa, sb, pb, pa, talus)
		_quad(st, pa, pb, tb, ta, cliff)
		_tri(st, ta, tb, foot + Vector3.UP * height, top)


## Where a bearing and a distance land, on the yard's own ground plane.
## `atan2(x, z)` is the convention the sun, the sky's yaw and this table all
## share, so a bearing written in one of them means the same thing in the others.
func _bearing_point(bearing: float, distance: float) -> Vector2:
	var a := deg_to_rad(bearing)
	return YARD_CENTRE + Vector2(sin(a), cos(a)) * distance


# -------------------------------------------------------------------- flare ---

## The flame on top of the flare stack, its light, and its smoke.
##
## This is the warm accent the map had none of. Everything in the yard is
## blue-grey steel and bleached caliche under a white sun; one orange thing on
## the horizon, moving, is worth more to the eye than any amount of colour
## correction — and it is fiction the map has already earned, because there is a
## drilling tower standing in the middle of it.
##
## One light for it, unshadowed, at 152 m. It lights nothing in the yard at that
## range and is not meant to; what it does is put a halo on its own stack and
## give the glow pass something to bloom, which is what makes a small emissive
## quad at that distance read as a fire rather than as a sticker.
func _build_flare(parent: Node3D) -> void:
	var entry := _backdrop_entry("flare")
	if entry.is_empty():
		return
	var at := _bearing_point(float(entry["bearing"]), float(entry["distance"]))
	var tip := Vector3(at.x, FLOOR + float(entry["height"]), at.y)

	_flare_material = StandardMaterial3D.new()
	_flare_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flare_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flare_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flare_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flare_material.billboard_keep_scale = true
	_flare_material.albedo_texture = Torch.soft_dot()
	_flare_material.albedo_color = FLARE_COLOUR
	_flare_material.emission_enabled = true
	_flare_material.emission = FLARE_COLOUR
	_flare_material.emission_energy_multiplier = 9.0
	_flare_material.disable_receive_shadows = true

	var quad := QuadMesh.new()
	quad.size = Vector2(FLARE_FLAME_WIDTH, FLARE_FLAME_HEIGHT)
	# The pivot at the bottom of the flame, so stretching it lengthens the
	# tongue upward instead of growing it out of the stack in both directions.
	quad.center_offset = Vector3(0.0, FLARE_FLAME_HEIGHT * 0.5, 0.0)
	quad.material = _flare_material

	_flare_flame = MeshInstance3D.new()
	_flare_flame.name = "FlareFlame"
	_flare_flame.mesh = quad
	_flare_flame.position = tip
	_flare_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flare_flame.add_to_group(BACKDROP_GROUP)
	parent.add_child(_flare_flame)

	_flare_light = OmniLight3D.new()
	_flare_light.name = "FlareLight"
	_flare_light.light_color = FLARE_COLOUR
	_flare_light.light_energy = FLARE_LIGHT_ENERGY
	_flare_light.omni_range = FLARE_LIGHT_RANGE
	_flare_light.omni_attenuation = 1.4
	_flare_light.shadow_enabled = false
	_flare_light.position = tip + Vector3.UP * FLARE_FLAME_HEIGHT * 0.4
	parent.add_child(_flare_light)
	lights += 1

	_build_flare_smoke(parent, tip)


## The plume. Thin, dark and leaning downwind — a flare that burns clean has no
## smoke at all, and a flare on an abandoned field does not burn clean.
func _build_flare_smoke(parent: Node3D, tip: Vector3) -> void:
	var wind := deg_to_rad(WIND_BEARING)
	var drift := Vector3(-sin(wind), 0.0, -cos(wind))

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 2.0
	process.direction = Vector3.UP + drift * 0.8
	process.spread = 18.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 6.5
	process.gravity = drift * 2.4 + Vector3.UP * 0.6
	process.damping_min = 0.4
	process.damping_max = 1.0
	process.scale_min = 4.0
	process.scale_max = 11.0
	process.color_ramp = _fade_ramp(Color(0.30, 0.27, 0.25), 0.34)

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = _soft_material(Color(0.32, 0.29, 0.27), 0.0)

	var smoke := GPUParticles3D.new()
	smoke.name = "FlareSmoke"
	smoke.draw_pass_1 = quad
	smoke.process_material = process
	smoke.amount = FLARE_SMOKE_COUNT
	smoke.lifetime = 16.0
	smoke.randomness = 0.8
	smoke.preprocess = 16.0
	smoke.use_fixed_seed = true
	smoke.seed = SEED ^ 0x5A0C
	smoke.position = tip + Vector3.UP * FLARE_FLAME_HEIGHT
	smoke.visibility_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 90, 120))
	smoke.add_to_group(BACKDROP_GROUP)
	parent.add_child(smoke)
	particles += FLARE_SMOKE_COUNT


func _backdrop_entry(kind: String) -> Dictionary:
	for entry: Dictionary in BACKDROP:
		if String(entry["kind"]) == kind:
			return entry
	return {}


# ---------------------------------------------------------------------- air ---

## Grit low down and dust high up: the two things moving over the yard.
##
## Neither is anywhere a player walks, because neither is anywhere at all — they
## are particles with no collision and no physics, and the only thing to be
## careful of is how much of the screen they cover. Both are small, both are
## dim, and the dust's alpha peaks at a third; the test is that a Bog silhouette
## at 20 m is exactly as readable through them as without them, and it is.
func _build_air(parent: Node3D) -> void:
	var wind := deg_to_rad(WIND_BEARING)
	# The direction the wind *goes*, which is the reciprocal of where it is from.
	var drift := Vector3(-sin(wind), 0.0, -cos(wind))
	var span_x := YARD_HALF_X
	var span_z := (YARD_Z_MAX - YARD_Z_MIN) * 0.5
	var middle := Vector3(YARD_CENTRE.x, 0.0, (YARD_Z_MAX + YARD_Z_MIN) * 0.5)

	# --- grit ---------------------------------------------------------------
	# Fast, low and lit from the side. Turbulence is what turns straight-line
	# drift into something blowing rather than something falling sideways —
	# it is the single setting that decides whether these read as wind or as
	# snow, which is the same lesson `ambience.gd` learned on the fireflies.
	var grit := ParticleProcessMaterial.new()
	grit.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	grit.emission_box_extents = Vector3(span_x, (GRIT_TOP - 0.2) * 0.5, span_z)
	grit.direction = drift + Vector3.UP * 0.12
	grit.spread = 26.0
	grit.initial_velocity_min = 1.1
	grit.initial_velocity_max = 2.9
	# A whisper of lift, because grit that only travels sideways stays in a
	# plane and reads as a texture scrolling across the screen.
	grit.gravity = drift * 0.5 + Vector3(0.0, 0.10, 0.0)
	grit.damping_min = 0.05
	grit.damping_max = 0.35
	grit.turbulence_enabled = true
	grit.turbulence_noise_strength = 0.62
	grit.turbulence_noise_scale = 1.9
	grit.turbulence_noise_speed = Vector3(0.22, 0.05, 0.14)
	grit.scale_min = 0.45
	grit.scale_max = 1.15
	grit.color_ramp = _fade_ramp(Color(0.92, 0.80, 0.60), 0.85)
	_emitter(parent, "Grit", grit, Color(0.95, 0.84, 0.64), 1.5, Vector2(0.055, 0.055),
		GRIT_COUNT, GRIT_LIFETIME, middle + Vector3.UP * (FLOOR + GRIT_TOP * 0.5 + 0.1),
		0x6712, span_x, span_z, GRIT_TOP + 6.0)

	# --- dust ---------------------------------------------------------------
	# Slow, high and barely there. This is the layer that gives the middle
	# distance something to be: it catches the low sun at every depth, so the
	# volumetric shafts between the containers have something in front of and
	# behind them instead of being a gradient on nothing.
	var dust := ParticleProcessMaterial.new()
	dust.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(span_x * 1.05, DUST_TOP * 0.5, span_z * 1.05)
	dust.direction = drift * 0.6 + Vector3(0.0, 1.0, 0.0)
	dust.spread = 60.0
	dust.initial_velocity_min = 0.10
	dust.initial_velocity_max = 0.45
	dust.gravity = drift * 0.18 + Vector3(0.0, 0.05, 0.0)
	dust.damping_min = 0.05
	dust.damping_max = 0.25
	dust.turbulence_enabled = true
	dust.turbulence_noise_strength = 0.26
	dust.turbulence_noise_scale = 2.2
	dust.scale_min = 0.30
	dust.scale_max = 1.0
	dust.color_ramp = _fade_ramp(Color(0.96, 0.88, 0.72), 0.36)
	_emitter(parent, "Dust", dust, Color(0.96, 0.89, 0.74), 0.9, Vector2(0.085, 0.085),
		DUST_COUNT, DUST_LIFETIME, middle + Vector3.UP * (FLOOR + DUST_TOP * 0.5),
		0x11D7, span_x * 1.1, span_z * 1.1, DUST_TOP + 12.0)


func _emitter(parent: Node3D, called: String, process: ParticleProcessMaterial,
		tint: Color, glow: float, size: Vector2, amount: int, lifetime: float,
		at: Vector3, salt: int, reach_x: float, reach_z: float, reach_y: float) -> void:
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = _soft_material(tint, glow)

	var node := GPUParticles3D.new()
	node.name = called
	node.draw_pass_1 = quad
	node.process_material = process
	node.amount = amount
	node.lifetime = lifetime
	node.randomness = 0.9
	# Without a preprocess the field fades up from nothing over a whole
	# lifetime after every scene load, which is exactly the moment a player is
	# deciding what this place looks like.
	node.preprocess = lifetime
	# Seeded, so two clients see the same grit in the same place. Free, and it
	# means "why is this frame different" is never a question about the air.
	node.use_fixed_seed = true
	node.seed = SEED ^ salt
	node.position = at
	node.visibility_aabb = AABB(Vector3(-reach_x - 8.0, -reach_y * 0.6, -reach_z - 8.0),
		Vector3(reach_x * 2.0 + 16.0, reach_y * 1.6, reach_z * 2.0 + 16.0))
	parent.add_child(node)
	particles += amount


# ------------------------------------------------------------------ shimmer ---

## The heat haze panels. See `SHIMMER` above for where they may and may not go.
##
## Six transparent quads, each one screen-texture read. They are Y-billboarded
## in the shader rather than here, so a panel is the same panel from every pad
## and there is no per-frame work on the CPU for any of them.
func _build_shimmer(parent: Node3D) -> void:
	var shader := load("res://resources/shaders/rust_heat.gdshader") as Shader
	if shader == null:
		return
	var material := ShaderMaterial.new()
	material.shader = shader

	var group := _group("Shimmer", parent)
	for i: int in SHIMMER.size():
		var entry: Dictionary = SHIMMER[i]
		var size: Vector2 = entry["size"]
		var quad := QuadMesh.new()
		quad.size = size
		# Pivot at the bottom edge, so `at.y` is where the panel starts and the
		# table reads as "this high off that surface".
		quad.center_offset = Vector3(0.0, size.y * 0.5, 0.0)
		quad.material = material

		var node := MeshInstance3D.new()
		node.name = "Shimmer%d" % i
		node.mesh = quad
		node.position = entry["at"]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# In `BACKDROP_GROUP` for the same reason the refinery is: a panel of
		# hot air is not the map's extent. Without this the widest of them —
		# 22 m of quad standing against the west wall — pushes the bounds
		# `tools/preview_map.gd` frames from out to 30 m, which moves the
		# "middle of the map" every pad is measured against.
		node.add_to_group(BACKDROP_GROUP)
		group.add_child(node)


# ------------------------------------------------------------------- lights ---

## The two sodium lamps, each with a head to be seen and a light to be seen by.
func _build_lamps(parent: Node3D) -> void:
	var group := _group("Lights", parent)
	var head := StandardMaterial3D.new()
	head.albedo_color = LAMP_COLOUR
	head.emission_enabled = true
	head.emission = LAMP_COLOUR
	# Over the glow threshold (2.0 in `rust_env.tres`) by enough that the head
	# blooms a little even against a sunlit wall behind it.
	head.emission_energy_multiplier = 7.0
	head.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for entry: Dictionary in LAMPS:
		var at: Vector3 = entry["at"]
		var aim: Vector3 = entry["aim"]

		var light := OmniLight3D.new()
		light.name = "Lamp_%s" % String(entry["label"]).replace(" ", "_")
		light.light_color = LAMP_COLOUR
		light.light_energy = LAMP_ENERGY
		light.omni_range = LAMP_RANGE
		light.omni_attenuation = 1.6
		light.shadow_enabled = false
		light.position = at
		group.add_child(light)
		lights += 1

		# The fixture: a short arm out of whatever it is bolted to and a
		# lamp-shaped box on the end, pitched toward what it lights.
		var shade := MeshInstance3D.new()
		shade.name = "%s_head" % light.name
		var box := BoxMesh.new()
		box.size = Vector3(0.55, 0.22, 0.55)
		shade.mesh = box
		shade.material_override = head
		shade.position = at
		shade.look_at_from_position(at, aim, Vector3.UP)
		shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(shade)


# ------------------------------------------------------------------- ground ---

## Stains and tracks on the caliche.
##
## `Decal` nodes rather than geometry or a material change, and that is the
## whole reason this is possible at all: a decal projects on to the `.glb`
## without touching a triangle of it, so none of this is lost the next time
## `tools/prepare_map.py` re-exports the map. They are also not collision and
## could not be — a `Decal` has no shape.
##
## Both textures are computed here rather than loaded, the way
## `wharf_map.gd` computes its corrugation: there is nothing to import, nothing
## to licence and nothing that is anybody else's.
func _build_decals(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var group := _group("Ground", parent)
	var oil := ImageTexture.create_from_image(_oil_image(rng))
	var tracks := ImageTexture.create_from_image(_track_image())

	for entry: Dictionary in DECALS:
		var kind := String(entry["kind"])
		var at: Vector2 = entry["at"]
		var across := float(entry["size"])

		var decal := Decal.new()
		decal.name = "%s_%+.0f_%+.0f" % [kind, at.x, at.y]
		if kind == "tracks":
			decal.texture_albedo = tracks
			# Long and thin, laid along its own yaw.
			decal.size = Vector3(across, DECAL_DEPTH, 3.0)
			decal.albedo_mix = 0.55
			decal.modulate = Color(0.46, 0.41, 0.35)
		else:
			decal.texture_albedo = oil
			decal.size = Vector3(across, DECAL_DEPTH, across)
			decal.albedo_mix = 0.88
			decal.modulate = Color(0.10, 0.09, 0.08)
		decal.upper_fade = 0.2
		decal.lower_fade = 0.6
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = DECAL_FADE_BEGIN
		decal.distance_fade_length = DECAL_FADE_LENGTH
		# Half the projection box above the floor and half below it, so a stain
		# finds the ground whether the `.glb` is a centimetre high or low there.
		decal.position = Vector3(at.x, FLOOR + DECAL_DEPTH * 0.35, at.y)
		decal.rotation.y = float(entry["yaw"])
		group.add_child(decal)
		decals += 1


## An oil stain: a dark blob with a ragged edge and a lighter halo where it has
## soaked out into the dust. Alpha carries the shape; the colour is flat, because
## `modulate` on the decal is what decides how black it is.
func _oil_image(rng: RandomNumberGenerator) -> Image:
	var size := 128
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.022
	noise.fractal_octaves = 4
	noise.seed = SEED ^ int(rng.randi() & 0xFFFF)
	for y: int in size:
		for x: int in size:
			var p := Vector2(float(x), float(y)) / float(size) * 2.0 - Vector2.ONE
			# A radial falloff warped by noise. Straight noise gives lichen;
			# noise pushing a disc's edge about gives a puddle.
			var warp := noise.get_noise_2d(float(x), float(y)) * 0.42
			var d := clampf(p.length() + warp, 0.0, 1.4)
			var core := smoothstep(0.86, 0.32, d)
			var halo := smoothstep(1.0, 0.55, d) * 0.35
			image.set_pixel(x, y, Color(0.5, 0.5, 0.5, clampf(core + halo, 0.0, 1.0)))
	image.generate_mipmaps()
	return image


## Tyre tracks: two parallel bands of tread across the texture, fading out at
## both ends so a track never stops in a straight line.
func _track_image() -> Image:
	var width := 256
	var height := 64
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for y: int in height:
		var v := float(y) / float(height)
		# Two wheels, a third of the way in from each edge.
		var wheel := maxf(smoothstep(0.16, 0.26, v) * smoothstep(0.40, 0.30, v),
			smoothstep(0.60, 0.70, v) * smoothstep(0.84, 0.74, v))
		for x: int in width:
			var u := float(x) / float(width)
			# The tread pattern: a chevron every 6 cm of a 3 m decal.
			var tread := 0.55 + 0.45 * sin(u * TAU * 34.0 + v * 9.0)
			var ends := smoothstep(0.0, 0.12, u) * smoothstep(1.0, 0.86, u)
			var a := wheel * ends * tread * 0.8
			image.set_pixel(x, y, Color(0.5, 0.5, 0.5, clampf(a, 0.0, 1.0)))
	image.generate_mipmaps()
	return image


# -------------------------------------------------------------------- audio ---

## PLAN 4.9 — ambient audio, wired exactly as `ambience.gd::_build_audio` wires
## the island's: positioned, looping, on the `Ambience` bus that
## `default_bus_layout.tres` already defines and that `Settings`/`AudioDirector`
## already have a slider for, and **skipped in silence** when the file is not on
## disk.
##
## The island shipped with no ambience at all for a while because its paths were
## guessed on one branch while the audio was committed on another, and a silent
## skip is right for an optional asset and wrong for a typo. So `wind` names a
## file that is really there, and `yard` names one that is not yet — see `LOOPS`.
func _build_audio(parent: Node3D) -> void:
	var middle := Vector3(YARD_CENTRE.x, FLOOR, (YARD_Z_MAX + YARD_Z_MIN) * 0.5)
	var placements := {
		# The bed, over the middle of the yard, effectively unattenuated.
		"wind": {"at": middle + Vector3.UP * 9.0, "range": 70.0, "db": -8.0},
		# The steel, at the foot of the drilling tower, close enough to fall off
		# with distance so that walking toward the tower is audible before it is
		# visible.
		"yard": {"at": Vector3(-5.0, FLOOR + 3.0, -7.0), "range": 26.0, "db": -10.0},
	}
	for key: String in LOOPS:
		var path: String = LOOPS[key]
		if not ResourceLoader.exists(path):
			continue
		var stream := load(path) as AudioStream
		if stream == null:
			continue
		var placement: Dictionary = placements[key]
		var player := AudioStreamPlayer3D.new()
		player.name = "Ambient_%s" % key
		player.stream = stream
		player.bus = "Ambience"
		player.unit_size = placement["range"]
		player.volume_db = placement["db"]
		player.autoplay = true
		player.position = placement["at"]
		parent.add_child(player)


# --------------------------------------------------------------- primitives ---

## An unshaded, additive, billboarded soft dot — the same treatment the island's
## particles and the torch flame use, and the same generated texture, so there
## is exactly one of it in memory.
func _soft_material(tint: Color, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if glow <= 0.0 \
		else BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = Torch.soft_dot()
	material.albedo_color = tint
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = tint
		material.emission_energy_multiplier = glow
	material.disable_receive_shadows = true
	return material


## In at birth, out at death, flat in between, with a ceiling on how opaque it
## ever gets — so nothing pops and nothing ever covers a target.
func _fade_ramp(tint: Color, peak: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(tint.r, tint.g, tint.b, 0.0))
	gradient.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	gradient.add_point(0.14, Color(tint.r, tint.g, tint.b, peak))
	gradient.add_point(0.78, Color(tint.r, tint.g, tint.b, peak * 0.85))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


## One flat-shaded quad, wound so `a-b-c-d` counter-clockwise from the front
## comes out as Godot's clockwise front faces.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		tint: Color) -> void:
	_tri(st, a, b, c, tint)
	_tri(st, a, c, d, tint)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 1e-9:
		return
	normal = normal.normalized()
	for p: Vector3 in [a, b, c]:
		st.set_color(tint)
		st.set_normal(normal)
		st.add_vertex(p)


## An axis-aligned box standing on `foot`, `size` across and tall.
func _box(st: SurfaceTool, foot: Vector3, size: Vector3, tint: Color) -> void:
	var h := Vector3(size.x, 0.0, size.z) * 0.5
	var lo := foot - h
	var hi := foot + h + Vector3(0.0, size.y, 0.0)
	var corners := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z),
		Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	var faces := [[4, 5, 6, 7], [1, 0, 3, 2], [0, 1, 5, 4], [2, 3, 7, 6],
		[1, 2, 6, 5], [3, 0, 4, 7]]
	for face: Array in faces:
		_quad(st, corners[face[0]], corners[face[1]], corners[face[2]],
			corners[face[3]], tint)


## A closed cylinder standing on `foot`, capped flat.
func _cylinder(st: SurfaceTool, foot: Vector3, radius: float, height: float,
		segments: int, tint: Color) -> void:
	var top := foot + Vector3.UP * height
	var cap := Color(tint).lightened(0.12)
	for i: int in segments:
		var a := TAU * float(i) / float(segments)
		var b := TAU * float(i + 1) / float(segments)
		var pa := Vector3(cos(a), 0.0, sin(a)) * radius
		var pb := Vector3(cos(b), 0.0, sin(b)) * radius
		_quad(st, foot + pa, foot + pb, top + pb, top + pa, tint)
		_tri(st, top, top + pa, top + pb, cap)


## A box stretched from `from` to `to`, `thickness` square. The one primitive
## every lattice, gantry and cross-arm out on the horizon is made of.
func _beam(st: SurfaceTool, from: Vector3, to: Vector3, thickness: float,
		tint: Color) -> void:
	var span := to - from
	if span.length_squared() < 1e-6:
		return
	var forward := span.normalized()
	var up := Vector3.UP if absf(forward.y) < 0.95 else Vector3.RIGHT
	var right := up.cross(forward).normalized()
	var over := forward.cross(right)
	var h := thickness * 0.5
	var corners: Array[Vector3] = []
	for end: Vector3 in [from, to]:
		corners.append(end - right * h - over * h)
		corners.append(end + right * h - over * h)
		corners.append(end + right * h + over * h)
		corners.append(end - right * h + over * h)
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5],
		[2, 3, 7, 6], [3, 0, 4, 7]]
	for face: Array in faces:
		_quad(st, corners[face[0]], corners[face[1]], corners[face[2]],
			corners[face[3]], tint)


func _group(named: String, under: Node3D = null) -> Node3D:
	var node := Node3D.new()
	node.name = named
	(under if under != null else self).add_child(node)
	return node
