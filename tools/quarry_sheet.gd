extends Node3D
## A contact sheet of the quarry asset pack. Development tool, not shipped.
##
## `art/maps/quarry/` holds sixty-five GLB models that were generated one at a
## time by an AI tool, which means three things no manifest records: every model
## is normalised to roughly one metre across whatever it is meant to be, the
## pivots and facings vary from file to file, and several are near-duplicates of
## each other. None of that can be read out of a filename, and a map built on
## guesses about it is a map full of floating, sideways, wrongly-sized props.
##
## So this lays the pack out in a grid, one model per cell, each sitting on a
## tile with its own name written under it and a **1.55 m red post** beside it —
## a Bog, to scale. Two views: `front` looks along -Z so facing is readable, and
## `top` looks straight down so footprint is. Render it, look at it, choose.
##
## Usage:
##   Godot --path . --resolution 1800x1200 --script tools/snapshot.gd -- \
##       res://tools/quarry_sheet.tscn out.png 20 <page> [front|top]
##
## `page` is 0-based and each page is `COLS x ROWS` models.

const PACK := "res://art/maps/quarry/"
## The shortlist, rendered by passing page `-1`: the models that survived the
## first look at the whole pack and are candidates for a sun-baked worked-out
## stone quarry. Everything icy, glowing, futuristic, crystal or emerald is out
## by theme, and the L-shaped "track" chunks are out because they are a corner
## of a wall with a rail on it rather than a rail.
const PICK: PackedStringArray = [
	"stone_mine_tunnel_02", "stone_mine_tunnel_03", "stone_mine_tunnel_06",
	"stone_mine_tunnel_07", "wooden_mine_tunnel_01", "wooden_mine_tunnel_02",
	"mine_tunnel_02", "overgrown_mine_entrance_01",
	"railway_track_02", "railway_track_04", "railroad_track_08",
	"railroad_track_04", "railroad_track_07", "railroad_tracks_01",
	"mining_cart_01", "wooden_minecart_01",
	"iron_ore_rock_01", "mossy_coal_ore_rock_01", "mossy_copper_ore_rock_01",
	"mossy_sulfur_ore_rock_01", "mossy_gold_ore_rock_01",
	"mineshaft_sign_01", "stone_sign_01", "wooden_barrel_01",
	"wooden_ladder_01", "steel_rope_01", "stone_staircase_01",
	"railway_track_corner_01",
]
const COLS := 4
const ROWS := 3
const CELL := 3.0
## A Bog, so every cell carries the only measurement that matters.
const BOG_HEIGHT := 1.55


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var page := 0
	var view := "front"
	if args.size() >= 4:
		page = int(args[3])
	if args.size() >= 6:
		# `-1 <view> <n>`: the nth page of the shortlist.
		page = -1 - int(args[5])
	if args.size() >= 5:
		view = String(args[4])

	var files := _pack_files()
	if page < 0:
		files = PackedStringArray()
		for named: String in PICK:
			files.append(PACK + named + ".glb")
		page = -1 - page
	var per := COLS * ROWS
	var from := page * per
	print("quarry_sheet: %d models, page %d of %d, view %s" % [
		files.size(), page, (files.size() + per - 1) / per, view])

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	light.light_energy = 1.5
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.19)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.78)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)

	for i: int in per:
		var index := from + i
		if index >= files.size():
			break
		var col := i % COLS
		var row := i / COLS
		var at := Vector3(float(col) * CELL, 0.0, float(row) * CELL)
		_cell(files[index], at, view)

	var width := float(COLS) * CELL
	var depth := float(ROWS) * CELL
	var middle := Vector3(width * 0.5 - CELL * 0.5, 0.0, depth * 0.5 - CELL * 0.5)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = width + 0.6
	if view == "top":
		camera.position = middle + Vector3(0.0, 20.0, 0.01)
		camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	else:
		camera.position = middle + Vector3(0.0, 9.0, 16.0)
		camera.rotation_degrees = Vector3(-26.0, 0.0, 0.0)
	camera.far = 200.0
	add_child(camera)
	camera.make_current()


## One model on its tile, with its name and a Bog-height post beside it.
func _cell(path: String, at: Vector3, view: String) -> void:
	var packed := load(path) as PackedScene
	var label := path.get_file().get_basename()
	var holder := Node3D.new()
	holder.name = label
	holder.position = at
	add_child(holder)

	var tile := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(CELL - 0.2, 0.04, CELL - 0.2)
	tile.mesh = plane
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.30, 0.31, 0.33)
	tile.material_override = grey
	tile.position = Vector3(0.0, -0.02, 0.0)
	holder.add_child(tile)

	var post := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.06, BOG_HEIGHT, 0.06)
	post.mesh = bar
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.16, 0.14)
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	post.material_override = red
	post.position = Vector3(CELL * 0.5 - 0.35, BOG_HEIGHT * 0.5, CELL * 0.5 - 0.35)
	holder.add_child(post)

	var text := Label3D.new()
	text.text = label
	text.font_size = 96
	text.pixel_size = 0.0030
	text.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	text.modulate = Color(1, 1, 1)
	text.outline_size = 24
	if view == "top":
		text.position = Vector3(0.0, 2.0, CELL * 0.5 - 0.25)
		text.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	else:
		text.position = Vector3(0.0, 0.05, CELL * 0.5 - 0.1)
		text.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	holder.add_child(text)

	if packed == null:
		push_warning("quarry_sheet: could not load %s" % path)
		return
	var model := packed.instantiate()
	holder.add_child(model)
	# Sat on its tile by its own bounding box, never by eye — the whole point of
	# the sheet is that the pivots are not where you would guess.
	var box := _aabb(model)
	if box.size.length() > 0.0:
		model.position = Vector3(-box.get_center().x, -box.position.y,
			-box.get_center().z)
		print("  %-38s size %.2f x %.2f x %.2f  pivot %.2f,%.2f,%.2f" % [
			label, box.size.x, box.size.y, box.size.z,
			box.position.x, box.position.y, box.position.z])


static func _aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mesh: MeshInstance3D in _meshes(node):
		var box := mesh.get_aabb()
		box = mesh.transform * box
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child: Node in node.get_children():
		out.append_array(_meshes(child))
	return out


static func _pack_files() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(PACK)
	if dir == null:
		push_error("quarry_sheet: no %s" % PACK)
		return out
	for file: String in dir.get_files():
		if file.ends_with(".glb"):
			out.append(PACK + file)
	out.sort()
	return out
