extends Node
## Numbers about the generated island that a screenshot cannot give you.
## Development tool, not shipped.
##
## A render says whether Whisperbloom Hollow looks right. It does not say whether
## a fifth of the walkable surface is too steep to run up, whether two spawn pads
## are eight metres apart, or how many triangles the scatter actually cost. This
## prints all of that, for one seed or for a sweep of them — because the map is a
## function of `Net.config.map_seed` (D-007) and "it works on the default seed"
## is not the same claim as "it works".
##
## Usage:
##   Godot --headless --path . tools/island_report.tscn -- [seed] [count]
##
## A scene rather than a `--script` main loop, for the reason `match_rules.gd`
## gives: the spawn ring is solved by `Arena`, and `Arena` names `Net`, which a
## script main loop cannot resolve at compile time.

const DEFAULT_SEED := 20260904

## The forest D-055 asked for, as bands every reported seed has to land in, so
## `tools/smoke_test.sh` can hold the map to it. The user's words were "reduce the
## amount of trees by 60% and make them all on average way taller, double the
## height": before, 29 living trees placed at a mean of 7.4 m. Bands rather than
## exact numbers because both are functions of the seed.
const TREES_PLACED := Vector2i(10, 14)
const TREE_HEIGHT := Vector2(12.0, 18.0)
## The capture bases were 18.8 m apart on the old ring (D-051), and two pads
## could come to rest 3.8 m from each other.
const BASES_APART := 25.0
const PADS_APART := 5.5

var _failures: int = 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var first: int = int(args[0]) if args.size() >= 1 else DEFAULT_SEED
	var count: int = maxi(1, int(args[1])) if args.size() >= 2 else 1

	for i in count:
		_report(first + i * 977)
	print("island_report: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit()


func _report(map_seed: int) -> void:
	var island := IslandGenerator.new(map_seed)
	print("\n===== seed %d" % map_seed)
	print("  extent %.1f m across, %d landmasses" % [island.extent() * 2.0,
		island.landmasses.size()])
	for mass: IslandGenerator.Landmass in island.landmasses:
		print("    %-12s centre %6.1f,%6.1f  radius %.1f  base_y %+.1f  depth %.1f" % [
			mass.name, mass.centre.x, mass.centre.y, mass.base_radius,
			mass.base_height, mass.depth])

	_sample_surface(island)
	_mesh_stats(island)
	_layout(island, map_seed)


## Everything `arena.gd` stands on the terrain, in its order: landmarks, the
## spawn ring, the scatter. Built here without a scene tree, so the numbers a
## change to the forest is judged by — how many trees actually went down, how
## tall they are, how far apart the capture bases came out — are a headless
## second rather than a render and a squint.
func _layout(island: IslandGenerator, map_seed: int) -> void:
	# The spawn ring is solved off the match config's seed, not an argument.
	Net.config.map_seed = map_seed
	var holder := Node3D.new()
	var landmarks := Landmarks.new(island, map_seed)
	landmarks.build(holder)

	var arena := Arena.new()
	arena.island = island
	arena.landmarks = landmarks
	arena._build_spawn_points()

	var scatter := PropScatter.new(island, map_seed, landmarks.keepouts)
	scatter.scatter(holder)

	var heights := scatter.tree_heights
	var total := 0.0
	var tallest := 0.0
	var shortest := INF
	for h: float in heights:
		total += h
		tallest = maxf(tallest, h)
		shortest = minf(shortest, h)
	var mean := total / maxf(1.0, float(heights.size()))
	var canopy := 0.0
	for point: Vector3 in scatter.canopy_points:
		canopy += point.y
	canopy /= maxf(1.0, float(scatter.canopy_points.size()))

	var closest := INF
	var spawns := arena.spawn_points
	for i in spawns.size():
		for j in range(i + 1, spawns.size()):
			closest = minf(closest, spawns[i].origin.distance_to(spawns[j].origin))
	var layout := CaptureLayout.plan(spawns, 2)
	var apart := Vector2(layout.bases[0].x, layout.bases[0].z).distance_to(
		Vector2(layout.bases[1].x, layout.bases[1].z))

	print("  props    %d instances (~%dk triangles), %d torch spots" % [
		scatter.instances, scatter.triangles / 1000, landmarks.torch_spots.size()])
	print("  scatter  %s" % scatter.counts)
	print("  trees    %d placed of %d asked, height mean %.1f m (%.1f to %.1f), canopy y %.1f" % [
		heights.size(), int(PropScatter.SPARSE_LAYERS[0]["count"]), mean,
		shortest if heights.size() > 0 else 0.0, tallest, canopy])
	print("  spawns   %d pads, closest pair %.1f m; capture bases %.1f m apart" % [
		spawns.size(), closest, apart])

	_verdict("main island radius %.1f m" % island.landmasses[0].base_radius,
		is_equal_approx(island.landmasses[0].base_radius, IslandGenerator.MAIN_RADIUS))
	_verdict("%d trees placed, in %d-%d" % [heights.size(), TREES_PLACED.x, TREES_PLACED.y],
		heights.size() >= TREES_PLACED.x and heights.size() <= TREES_PLACED.y)
	_verdict("mean tree height %.1f m, in %.0f-%.0f" % [mean, TREE_HEIGHT.x, TREE_HEIGHT.y],
		mean >= TREE_HEIGHT.x and mean <= TREE_HEIGHT.y)
	_verdict("capture bases %.1f m apart, over %.0f" % [apart, BASES_APART], apart > BASES_APART)
	_verdict("no two pads within %.1f m" % PADS_APART, closest >= PADS_APART)

	arena.free()
	holder.free()


func _verdict(label: String, ok: bool) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", label])
	if not ok:
		_failures += 1


## Walk a grid over the whole map and describe the ground: how high it goes, how
## steep it gets, and how much of it a Gub could actually run on.
func _sample_surface(island: IslandGenerator) -> void:
	var reach := island.extent()
	var step := 0.5
	var land := 0
	var walkable := 0
	var steep := 0
	var lowest := INF
	var highest := -INF
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var x := -reach
	while x <= reach:
		var z := -reach
		while z <= reach:
			var h := island.height_at(x, z)
			if h > IslandGenerator.NO_LAND:
				land += 1
				lowest = minf(lowest, h)
				highest = maxf(highest, h)
				min_x = minf(min_x, x)
				max_x = maxf(max_x, x)
				min_z = minf(min_z, z)
				max_z = maxf(max_z, z)
				# tan(45°) = 1.0 is Godot's default floor_max_angle, so anything
				# past it is a wall as far as a CharacterBody3D is concerned.
				var slope := island.slope_at(x, z)
				if slope < 0.7:
					walkable += 1
				elif slope >= 1.0:
					steep += 1
			z += step
		x += step

	var area := float(land) * step * step
	# The span that matters is the real footprint, not the bounding disc: the
	# fog in `arena_env.tres` was tuned against "40-60 m across" (D-009), and an
	# off-centre islet inflates a disc radius without widening the map.
	print("  footprint %.1f x %.1f m  area %.0f m²  y from %+.2f to %+.2f (range %.2f)" % [
		max_x - min_x, max_z - min_z, area, lowest, highest, highest - lowest])
	print("  slope    %.1f%% comfortable (<35°), %.2f%% unwalkable (>=45°)" % [
		100.0 * float(walkable) / maxf(1.0, float(land)),
		100.0 * float(steep) / maxf(1.0, float(land))])


func _mesh_stats(island: IslandGenerator) -> void:
	var root := Node3D.new()
	island.build_into(root)
	var tris := 0
	var verts := 0
	for chunk in root.get_children():
		var visual := chunk.get_node_or_null("Terrain") as MeshInstance3D
		if visual == null:
			continue
		for s in visual.mesh.get_surface_count():
			var arrays := visual.mesh.surface_get_arrays(s)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			verts += points.size()
			# The faceted underside carries no index buffer at all, so its
			# triangle count is its vertex count over three.
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			tris += (int((indices as PackedInt32Array).size()) if indices != null
				else points.size()) / 3
	print("  terrain  %d triangles, %d vertices" % [tris, verts])

	# Which way the top surface faces. Getting this wrong is not a subtle bug and
	# it is not a visible one either: a terrain whose normals point down is lit
	# by the *lower* hemisphere of the sky — the void colour — so it renders
	# pure black while every prop standing on it lights normally, and it looks
	# for all the world like a fog problem.
	var terrain := (root.get_child(0) as Node3D).get_node("Terrain") as MeshInstance3D
	for surface in terrain.mesh.get_surface_count():
		var arrays := terrain.mesh.surface_get_arrays(surface)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var up := 0
		for i in normals.size():
			if normals[i].y > 0.0:
				up += 1
		if normals.size() == 0:
			continue
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var mean := Color(0, 0, 0)
		for c: Color in colours:
			mean += c
		if colours.size() > 0:
			mean /= float(colours.size())
		print("  surface %d: %d/%d normals up; v1 %v n %v; %d colours, mean %s" % [
			surface, up, normals.size(), points[1], normals[1], colours.size(),
			mean.to_html(false)])
		var mat := terrain.mesh.surface_get_material(surface) as StandardMaterial3D
		print("           material albedo %s vertex_color_as_albedo=%s format=%d" % [
			mat.albedo_color.to_html(false), mat.vertex_color_use_as_albedo,
			terrain.mesh.surface_get_format(surface)])
	root.free()
