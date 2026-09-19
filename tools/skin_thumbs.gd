extends SceneTree
## Render the lobby picker's tile for every pickable skin. Development tool,
## not shipped.
##
##     "$GODOT" --path . --resolution 512x512 --script tools/skin_thumbs.gd
##     "$GODOT" --path . --resolution 512x512 --script tools/skin_thumbs.gd -- muck rime
##     "$GODOT" --headless --path . --import      # ...then let Godot see them
##
## One BOG, standing in `Idle`, photographed once per skin into
## `art/skins/<name>/thumb.png` at 256², **cut out against transparency**.
## `bog` — the plain body, no texture — gets one too: it is a pickable skin
## (`Skins.NAMES[0]`) and the picker needs a tile for it.
##
## **256 and transparent, because the picker grew.** The tile was 128² on a
## near-black card, which was right while it was a 40 px swatch on a strip: at
## that size a cut-out would have shown the glade through the Bog's ears, and
## 128 was already three times the pixels the strip drew. The Weapon and
## Character page draws it at **120 px** in a three-column grid on its own
## surface, so the two premises both went: 128 is no longer comfortably above
## the drawn size on a high-DPI window, and a rectangle of near-black is now the
## largest thing in the cell rather than a hairline behind a face. Transparent,
## the lobby's own button stylebox is the background — which is what makes
## hover, focus and "this is the one you are wearing" legible on a tile made
## almost entirely of photograph.
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
## orthographic camera is put in front of it with an extent in *metres*, so
## every skin is framed identically by construction and re-running this after a
## re-rig follows the body rather than going stale.
##
## **And the extent is measured too, not typed.** It used to be a pair of hand
## tuned constants — 0.52 m of frame, 5 cm above the head bone — arrived at by
## looking at the result, and the result was a tile with both antennae sliced
## off at the top.
##
## Antennae are not on the skeleton: this is a Mixamo rig and they are weighted
## to the head, so there is no bone to ask. So the tip is measured **off a
## photograph of the Bog**: one wide probe shot is taken through this same
## camera and the silhouette's own alpha is scanned for its highest lit row —
## and for its widest lit column *above the waist*, which is the other half of
## "both antennae fully in frame" and the half a height alone cannot answer.
##
## The mesh's own `get_aabb()` was the obvious alternative and it is not wrong:
## it reports a top at 1.799 against the photograph's **1.778**, two centimetres
## of skinning margin. It is not used for two reasons that both matter more than
## the two centimetres. It answers the wrong question about *width* — the AABB
## holds the whole body, so its x extent is the elbows of the Idle guard, which
## are below the crop and would widen every tile for nothing. And two
## centimetres of slack at the top of the frame is two centimetres of slack
## taken off the bottom of a square, which is the waist line the crop is named
## after. The measurement is exact and costs one frame.
##
## The shot is taken in a **square `SubViewport`** rather than out of the middle
## of the window: transparency is a property of a viewport, not of a camera, and
## a square one also means the `--resolution` above is only there to give the
## process a window to live in.
##
## Not headless, for `tools/snapshot.gd`'s reason: the headless driver uses the
## dummy rasteriser and produces no image. A small window appears for a second.

const BODY := "res://art/bog/BOG.fbx"
const LIBRARY := "res://art/generated/bog_clips.res"

## The pose. The Bog's own guard — the clip the ring stands in — so a tile is a
## picture of what the player is about to look like rather than of a T-pose.
const CLIP := "Idle"

## The tile the lobby draws (`Lobby.SKIN_THUMB` is 120, so this is a little over
## 2x and a thumbnail that survives a bigger cell later).
const OUT_SIZE := 256

## The square the shot is taken in, before the resize down to `OUT_SIZE`. Bigger
## than the tile so the Lanczos step has something to work with, and square so
## the orthographic camera's height and width are the same number of metres.
const SHOT_SIZE := 512

## The bones the framing is taken from. `mixamorig_Head` aims the camera
## sideways (the body is not symmetrical about the world origin once it is
## posed); `mixamorig_Hips` is the waist and is the bottom of the frame.
const HEAD_BONE := "mixamorig_Head"
const WAIST_BONE := "mixamorig_Hips"

## Air above the antenna tips, in metres. Small, because the tips are the
## silhouette the tile is recognised by and pushing them into the middle of the
## square would be spending the picture on sky.
const HEAD_AIR := 0.035

## And air either side of the widest thing above the waist, per side, in metres.
## The frame is square, so this only ever *grows* it — on this sculpt the
## waist-to-tips height wins and this is slack.
const SIDE_AIR := 0.03

## The narrowest the frame is allowed to be, in metres, whatever the
## measurement says. A guard rather than a setting: if a future clip tucks the
## head down, the measured waist-to-tips height could come out small enough to
## crop the shoulders out of a square, and a tile that is all face does not read
## as a *body* at a glance.
const FRAME_FLOOR := 0.70

## The probe. A deliberately over-wide square, centred well above the waist, in
## which the Bog is guaranteed to be entirely visible whatever the clip is
## doing — so the alpha scan is measuring the body and never the frame's own
## edge. Nothing is written from this shot; it exists to be measured.
const PROBE_FRAME := 2.4
const PROBE_CENTRE := 1.0


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
	var shot: SubViewport = stage["viewport"]
	var camera: Camera3D = stage["camera"]
	var imported := mesh.mesh.surface_get_material(0) as BaseMaterial3D
	# Let the stage settle before the first shot. `WARMUP` counted the frames
	# before the scene existed; these are the ones it takes the renderer to see
	# the camera, the lights and the environment that were just added to the
	# tree. Without them the first skin in the list — and only the first — comes
	# out as a black tile with a sliver of Bog in it.
	for _settle in 8:
		await process_frame

	# The silhouette is the mesh's, not the texture's, so the probe is taken
	# once with whatever is on the body and every skin after it is framed from
	# that one measurement.
	if not await _frame_up(shot, camera, float(stage["waist"])):
		quit(1)
		return

	var skeleton: Skeleton3D = stage["skeleton"]
	var written := 0
	for skin: int in wanted:
		# The clothes, if this skin has any (D-163), through the same
		# `SkinGarment.attach` the game dons them with — so a garment skin's tile
		# is a picture of the thing the picker is offering rather than of the
		# naked body underneath it. Hung on and taken off inside the loop: one
		# run writes every tile, and a shirt left on would dress every skin after
		# it in the list.
		var garment := Skins.garment_of(skin)
		var cloth := SkinGarment.attach(skeleton, garment) if garment != null else null
		var texture := Skins.texture_of(skin)
		# The same few lines `Bog.wear_skin` runs: a duplicate of the imported
		# material with the skin in its albedo slot, or the imported material
		# itself for the plain body. Not a call into `Bog`, because there is no
		# `Bog` here — this is the raw import, which is what `preview_bog.gd`
		# photographs too.
		if texture == null:
			mesh.set_surface_override_material(0, null)
		else:
			var worn := imported.duplicate() as BaseMaterial3D
			worn.albedo_texture = texture
			# And its maps, if the folder has any (D-154), so a glossy skin's
			# tile is glossy the way the body in the arena is.
			var rough := Skins.roughness_of(skin)
			if rough != null:
				worn.roughness_texture = rough
			var glow := Skins.emission_of(skin)
			if glow != null:
				worn.emission_texture = glow
			mesh.set_surface_override_material(0, worn)
		await process_frame
		RenderingServer.force_draw()
		var frame := shot.get_texture().get_image()
		if frame == null:
			push_error("skin_thumbs: the viewport produced no image")
			quit(1)
			return
		var path := "res://art/skins/%s/thumb.png" % Skins.NAMES[skin]
		var err := _square(frame).save_png(ProjectSettings.globalize_path(path))
		if err != OK:
			push_error("skin_thumbs: could not write %s (error %d)" % [path, err])
			quit(1)
			return
		print("skin_thumbs: %-8s -> %s%s"
			% [Skins.NAMES[skin], path, " (dressed)" if cloth != null else ""])
		written += 1
		if cloth != null:
			# `free`, not `queue_free`: the next tile is photographed on the very
			# next frame and a queued node is still on the rig for it.
			cloth.get_parent().remove_child(cloth)
			cloth.free()

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

	# Its own square, transparent viewport. `own_world_3d` so the lights and the
	# environment below belong to it and to nothing else, and `UPDATE_ALWAYS`
	# because the run draws a frame per skin and a viewport set to update once
	# would hand back the same picture fifteen times.
	var shot := SubViewport.new()
	shot.size = Vector2i(SHOT_SIZE, SHOT_SIZE)
	shot.transparent_bg = true
	shot.own_world_3d = true
	shot.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(shot)

	var body := scene.instantiate() as Node3D
	shot.add_child(body)
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

	# Where the head and the waist actually are, in this pose, on this rig. Asked
	# rather than assumed, so a re-rig or a change of clip re-aims the camera by
	# itself.
	var head_at: Variant = _bone_origin(skeleton, HEAD_BONE)
	var waist_at: Variant = _bone_origin(skeleton, WAIST_BONE)
	if head_at == null or waist_at == null:
		return {}
	var head: Vector3 = head_at
	var waist: Vector3 = waist_at

	print("skin_thumbs: %s at y %.3f, %s at y %.3f"
		% [HEAD_BONE, head.y, WAIST_BONE, waist.y])

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-24, -34, 0)
	key.light_energy = 2.4
	shot.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, 150, 0)
	fill.light_energy = 0.7
	fill.light_color = Color(0.62, 0.76, 1.0)
	shot.add_child(fill)

	var world := WorldEnvironment.new()
	var env := Environment.new()
	# **No background of its own.** `BG_CLEAR_COLOR` over a `transparent_bg`
	# viewport is what leaves the Bog cut out; painting a colour here would
	# quietly fill the alpha back in and the transparency would only look like
	# it was working until the tile was put on a lit surface.
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.66)
	env.ambient_light_energy = 0.55
	world.environment = env
	shot.add_child(world)

	# Orthographic and level, `preview_bog.gd`'s rule: every tile is the same
	# projection from the same angle, so fifteen of them in a row read as one
	# set rather than as fifteen photographs.
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	# The probe framing. `_frame_up` replaces both of these once it has looked at
	# what came out.
	cam.size = PROBE_FRAME
	cam.near = 0.05
	cam.far = 40.0
	cam.position = Vector3(head.x, PROBE_CENTRE, head.z + 12.0)
	shot.add_child(cam)
	cam.make_current()
	return {"mesh": mesh, "skeleton": skeleton, "viewport": shot, "camera": cam,
		"waist": waist.y}


## Take the probe shot, read the Bog's silhouette out of it, and set the camera
## to the framing that measurement asks for. Returns false if nothing was drawn.
##
## The scan is two questions of one image. **How high does the ink go** — the
## first row from the top with any alpha in it — which is the antenna tips and
## is the top of the frame. And **how wide is the ink above the waist**, which
## is the shoulders or the antennae's own spread, whichever is broader, and is
## the only thing that could make a square frame built from the height too
## narrow. Rows below the waist are skipped on purpose: the Idle pose is a
## boxer's guard and the elbows are the widest part of this body, a hand's width
## outside the shoulders and entirely below the crop.
func _frame_up(shot: SubViewport, cam: Camera3D, waist_y: float) -> bool:
	await process_frame
	RenderingServer.force_draw()
	var probe := shot.get_texture().get_image()
	if probe == null:
		push_error("skin_thumbs: the probe viewport produced no image")
		return false
	var wide := probe.get_width()
	var tall := probe.get_height()
	# The waist, as a row of this image. Everything above it is what the width
	# question is asked of; the elbows of the Idle guard are below it and are the
	# widest part of this body.
	var waist_row := clampi(int(round(
		(0.5 - (waist_y - cam.position.y) / PROBE_FRAME) * float(tall))), 1, tall)
	# `get_used_rect` is the alpha scan, in C++ rather than in a quarter of a
	# million `get_pixel` calls, and it is exactly the question being asked: the
	# smallest rectangle holding every pixel that is not fully transparent.
	var whole := probe.get_used_rect()
	var above := probe.get_region(Rect2i(0, 0, wide, waist_row)).get_used_rect()
	if whole.size.y <= 0 or above.size.x <= 0:
		push_error("skin_thumbs: the probe shot is empty — nothing was drawn")
		return false

	var tip := cam.position.y + (0.5 - float(whole.position.y) / float(tall)) * PROBE_FRAME
	var x_left := cam.position.x + (float(above.position.x) / float(wide) - 0.5) * PROBE_FRAME
	var x_right := cam.position.x + (float(above.end.x) / float(wide) - 0.5) * PROBE_FRAME
	var half := maxf(cam.position.x - x_left, x_right - cam.position.x)
	var top := tip + HEAD_AIR
	var frame := maxf(maxf(top - waist_y, 2.0 * (half + SIDE_AIR)), FRAME_FLOOR)
	cam.size = frame
	cam.position.y = (top + waist_y) * 0.5
	print("skin_thumbs: antenna tips at y %.3f, half-width above the waist %.3f"
		% [tip, half])
	print("skin_thumbs: frame %.3f m, centred at y %.3f (floor is %.2f)"
		% [frame, cam.position.y, FRAME_FLOOR])
	await process_frame
	return true


## One bone's world-space origin in the pose the stage is standing in, or null
## with an error if this rig has no such bone.
func _bone_origin(skeleton: Skeleton3D, bone_name: String) -> Variant:
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		push_error("skin_thumbs: no bone '%s' on this skeleton" % bone_name)
		return null
	return (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin


## The middle square of the shot, at `OUT_SIZE`.
##
## The `SubViewport` is already square, so the crop is a no-op and what is left
## is the resize — it is kept as a crop anyway because the camera keeps its
## *height*, and the day somebody gives the viewport a wider shape this is the
## line that stops fifteen tiles from being framed two different ways.
func _square(shot: Image) -> Image:
	var side := mini(shot.get_width(), shot.get_height())
	var cut := shot.get_region(Rect2i(
		(shot.get_width() - side) / 2, (shot.get_height() - side) / 2, side, side))
	cut.resize(OUT_SIZE, OUT_SIZE, Image.INTERPOLATE_LANCZOS)
	return cut
