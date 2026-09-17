extends SceneTree
## Render the lobby picker's tile for every pickable skin. Development tool,
## not shipped.
##
##     "$GODOT" --path . --resolution 512x512 --script tools/skin_thumbs.gd
##     "$GODOT" --path . --resolution 512x512 --script tools/skin_thumbs.gd -- muck rime
##     "$GODOT" --headless --path . --import      # ...then let Godot see them
##
## One BOG, standing in `Idle`, photographed once per skin into
## `art/skins/<name>/thumb.png` at 128². `bog` — the plain body, no texture —
## gets one too: it is a pickable skin (`Skins.NAMES[0]`) and the picker needs a
## tile for it.
##
## **Its own script rather than a step in `tools/extract_skins.py`.** That script
## is Python and Pillow and never opens Godot; a thumbnail is a *render* of the
## body wearing the texture, through the same importer, the same material and
## the same lights the game uses, which is a thing only Godot can do. Extraction
## and photography are two tools because they need two programs — run
## `extract_skins.py` when a `.glb` changes and this when the picker's look does.
##
## **The crop is the camera, not a rectangle in an image editor.** The head is
## found by asking the skeleton where `mixamorig_Head` is in this pose, and an
## orthographic camera is put in front of it with a fixed extent in *metres*, so
## every skin is framed identically by construction and re-running this after a
## re-rig follows the body rather than going stale. The square is cut out of the
## middle of whatever viewport it was given, so the `--resolution` above only has
## to be square-ish and at least 128 tall.
##
## Not headless, for `tools/snapshot.gd`'s reason: the headless driver uses the
## dummy rasteriser and produces no image. A small window appears for a second.

const BODY := "res://art/bog/BOG.fbx"
const LIBRARY := "res://art/generated/bog_clips.res"

## The pose. The Bog's own guard — the clip the ring stands in — so a tile is a
## picture of what the player is about to look like rather than of a T-pose.
const CLIP := "Idle"

## The tile the lobby draws (`Lobby.SKIN_THUMB` is 64, so 128 is a tile at 2x
## and a thumbnail that survives a bigger one later).
const OUT_SIZE := 128

## How much of the world the square holds, in metres, and where its middle sits
## relative to the head bone. Measured on this sculpt, whose head bone sits at
## 1.096 m and whose crown is a little under 1.38: 0.52 m of frame centred 5 cm
## *above* the bone leaves three centimetres of air over the crown and cuts
## across the chest, which is the head and shoulders the tile wants. The first
## try framed 0.62 m from 0.14 m *below* the bone, sliced the crown off and gave
## a third of the tile to a belly.
const FRAME := 0.52
const FRAME_DROP := -0.05
const HEAD_BONE := "mixamorig_Head"

## Behind the Bog. Near-black rather than transparent: the tile sits on the
## lobby's own glass and a cut-out would show the glade through the Bog's ears.
const BACKDROP := Color(0.055, 0.062, 0.078)

## Frames to let the scene settle before the first shot — shader compilation and
## the skeleton's first pose. After that one frame per skin is enough, because
## nothing changes but a texture on a material that is already resident.
const WARMUP := 24

var _started: bool = false


func _initialize() -> void:
	Engine.max_fps = int(ProjectSettings.get_setting(
		"physics/common/physics_ticks_per_second", 60))


func _process(_delta: float) -> bool:
	if _started:
		return false
	if Engine.get_physics_frames() < WARMUP:
		return false
	_started = true
	# Fired rather than awaited: `_process` must go on returning a bool every
	# frame while the shots are taken, so the run ends by calling `quit` itself.
	_run()
	return false


func _run() -> void:
	var wanted := _wanted_skins()
	if wanted.is_empty():
		push_error("skin_thumbs: no such skin (have %s)" % ", ".join(Skins.NAMES))
		quit(1)
		return

	var stage := _stage()
	if stage.is_empty():
		quit(1)
		return
	var mesh: MeshInstance3D = stage["mesh"]
	var imported := mesh.mesh.surface_get_material(0) as BaseMaterial3D
	# Let the stage settle before the first shot. `WARMUP` counted the frames
	# before the scene existed; these are the ones it takes the renderer to see
	# the camera, the lights and the environment that were just added to the
	# tree. Without them the first skin in the list — and only the first — comes
	# out as a black tile with a sliver of Bog in it.
	for _settle in 8:
		await process_frame

	var written := 0
	for skin: int in wanted:
		var texture := Skins.texture_of(skin)
		# The same two lines `Bog.wear_skin` runs: a duplicate of the imported
		# material with the skin in its albedo slot, or the imported material
		# itself for the plain body. Not a call into `Bog`, because there is no
		# `Bog` here — this is the raw import, which is what `preview_bog.gd`
		# photographs too.
		if texture == null:
			mesh.set_surface_override_material(0, null)
		else:
			var worn := imported.duplicate() as BaseMaterial3D
			worn.albedo_texture = texture
			mesh.set_surface_override_material(0, worn)
		await process_frame
		RenderingServer.force_draw()
		var shot := root.get_texture().get_image()
		if shot == null:
			push_error("skin_thumbs: the viewport produced no image")
			quit(1)
			return
		var path := "res://art/skins/%s/thumb.png" % Skins.NAMES[skin]
		var err := _square(shot).save_png(ProjectSettings.globalize_path(path))
		if err != OK:
			push_error("skin_thumbs: could not write %s (error %d)" % [path, err])
			quit(1)
			return
		print("skin_thumbs: %-8s -> %s" % [Skins.NAMES[skin], path])
		written += 1

	print("skin_thumbs: wrote %d of %d tiles at %d px" % [written, Skins.NAMES.size(), OUT_SIZE])
	quit(0)


## The skins named on the command line, or all of them.
func _wanted_skins() -> Array[int]:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return Skins.all()
	var out: Array[int] = []
	for arg: String in args:
		var index := Skins.NAMES.find(arg.strip_edges().to_lower())
		if index >= 0:
			out.append(index)
	return out


## The body in its pose, the lights, the backdrop and the camera. Returns the
## mesh whose material the run swaps, or `{}` if the body could not be built.
func _stage() -> Dictionary:
	var scene := load(BODY) as PackedScene
	var library := load(LIBRARY) as AnimationLibrary
	if scene == null or library == null:
		push_error("skin_thumbs: %s or %s is missing" % [BODY, LIBRARY])
		return {}
	if not library.has_animation(CLIP):
		push_error("skin_thumbs: the library has no '%s'" % CLIP)
		return {}

	var body := scene.instantiate() as Node3D
	root.add_child(body)
	var player := body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.remove_animation_library("")
	player.add_animation_library("", library)
	player.play(CLIP)
	player.seek(0.0, true)
	player.pause()

	var mesh := body.find_child("Bog", true, false) as MeshInstance3D
	var skeleton := body.find_child("Skeleton3D", true, false) as Skeleton3D
	if mesh == null or skeleton == null:
		push_error("skin_thumbs: %s has no Bog mesh or no Skeleton3D" % BODY)
		return {}

	# Where the head actually is, in this pose, on this rig. Asked rather than
	# assumed, so a re-rig or a change of clip re-aims the camera by itself.
	var bone := skeleton.find_bone(HEAD_BONE)
	if bone < 0:
		push_error("skin_thumbs: no bone '%s' on this skeleton" % HEAD_BONE)
		return {}
	var head := (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
	print("skin_thumbs: %s at %.3f, %.3f, %.3f" % [HEAD_BONE, head.x, head.y, head.z])

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-24, -34, 0)
	key.light_energy = 2.4
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, 150, 0)
	fill.light_energy = 0.7
	fill.light_color = Color(0.62, 0.76, 1.0)
	root.add_child(fill)

	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKDROP
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.66)
	env.ambient_light_energy = 0.55
	world.environment = env
	root.add_child(world)

	# Orthographic and level, `preview_bog.gd`'s rule: every tile is the same
	# projection from the same angle, so fourteen of them in a row read as one
	# set rather than as fourteen photographs.
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = FRAME
	cam.near = 0.05
	cam.far = 40.0
	cam.position = Vector3(head.x, head.y - FRAME_DROP, head.z + 12.0)
	root.add_child(cam)
	cam.make_current()
	return {"mesh": mesh}


## The middle square of the shot, at `OUT_SIZE`.
##
## The camera keeps its height, so the square cut out of the middle is exactly
## `FRAME` metres on both sides whatever window this was given — which is what
## lets the invocation be sloppy about `--resolution` and the tiles still match.
func _square(shot: Image) -> Image:
	var side := mini(shot.get_width(), shot.get_height())
	var cut := shot.get_region(Rect2i(
		(shot.get_width() - side) / 2, (shot.get_height() - side) / 2, side, side))
	cut.resize(OUT_SIZE, OUT_SIZE, Image.INTERPOLATE_LANCZOS)
	return cut
