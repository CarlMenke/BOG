extends Node3D
## Contact sheet of the BOG playing clips from the shared library: one row per
## clip, one BOG per sampled moment, so a clip can be judged from a single
## snapshot and two candidates for the same role can be judged side by side.
## Development tool, not shipped.
##
##   Godot --path . --resolution 1600x700 --script tools/snapshot.gd -- \
##       res://tools/preview_bog.tscn out.png 30 Walk-StandardWalk [from] [to]
##   Godot --path . --resolution 1600x1400 --script tools/snapshot.gd -- \
##       res://tools/preview_bog.tscn out.png 30 Run-StandardRunning,Run-RunningForward-1
##
## Clip keys are the library's: a role (`Walk`) once it has one clip, the file
## name while it still has candidates. Several keys separated by commas stack
## as rows. `from`/`to` narrow every row to a window of the clip in seconds.
## A trailing `skin=<name>` dresses every BOG in `art/skins/<name>/basecolor.png`
## (D-100).
##
## This is `preview_bog.gd` for the rebuilt body: the body is
## `art/bog/BOG.fbx` and the clips come from `art/generated/bog_clips.res`,
## swapped in for the body's own T-pose library the way the animator does it.

@export var samples: int = 6
@export var spacing: float = 1.4
@export var row_height: float = 2.7

const FRAME_LOW := -0.3
const FRAME_HIGH := 2.6
const FRAME_MIN := 3.2
const FRAME_MARGIN := 1.5
const BODY := "res://art/bog/BOG.fbx"
const LIBRARY := "res://art/generated/bog_clips.res"


func _ready() -> void:
	var args := PackedStringArray()
	var skin: Texture2D = null
	for a in OS.get_cmdline_user_args():
		if a.begins_with("skin="):
			skin = load("res://art/skins/%s/basecolor.png" % a.trim_prefix("skin="))
		else:
			args.append(a)
	var keys: PackedStringArray = args[3].split(",", false) if args.size() >= 4 else PackedStringArray(["Idle"])
	var scene := load(BODY) as PackedScene
	var library := load(LIBRARY) as AnimationLibrary
	for key in keys:
		if not library.has_animation(key):
			push_error("preview_bog: library has no clip '%s' (has %s)"
				% [key, ", ".join(library.get_animation_list())])
			return

	var rows := keys.size()
	for r in rows:
		var key := keys[r]
		var anim := library.get_animation(key)
		var length := anim.length
		var from: float = float(args[4]) if args.size() >= 5 else 0.0
		# The last sample lands *on* `to` when a window is asked for, and one
		# step short of the end when it is not: a looping clip's last frame is
		# its first.
		var to: float = float(args[5]) if args.size() >= 6 else length
		var span := maxf(to - from, 0.0)
		var step := span / float(samples if args.size() < 6 else maxi(samples - 1, 1))
		var y := row_height * (float(rows - 1) * 0.5 - float(r))
		var x := -spacing * (samples - 1) * 0.5
		for i in samples:
			var n := scene.instantiate() as Node3D
			add_child(n)
			n.position = Vector3(x, y, 0)
			x += spacing
			var ap := n.find_child("AnimationPlayer", true, false) as AnimationPlayer
			ap.remove_animation_library("")
			ap.add_animation_library("", library)
			if skin != null:
				var body := n.find_child("Bog", true, false) as MeshInstance3D
				var worn := body.mesh.surface_get_material(0).duplicate() as BaseMaterial3D
				worn.albedo_texture = skin
				body.set_surface_override_material(0, worn)
			ap.play(key)
			ap.seek(from + step * float(i), true)
			ap.pause()
			var stamp := Label3D.new()
			stamp.text = "%.2f" % (from + step * float(i))
			stamp.font_size = 64
			stamp.pixel_size = 0.0018
			stamp.position = Vector3(0.0, 1.95, 0.0)
			n.add_child(stamp)
		var label := Label3D.new()
		label.text = "%s   (%.2fs, %.2f m/s%s)" % [key, length,
			anim.get_meta("authored_speed", 0.0),
			", loop" if anim.loop_mode != Animation.LOOP_NONE else ""]
		label.font_size = 96
		label.pixel_size = 0.0022
		label.position = Vector3(0, y + 2.35, 0)
		add_child(label)
		_ground(y)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-38, -30, 0)
	key_light.light_energy = 2.4
	add_child(key_light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 150, 0)
	fill.light_energy = 0.6
	fill.light_color = Color(0.6, 0.75, 1.0)
	add_child(fill)

	# Orthographic and level, so every sample is seen from the same angle and
	# the floor is a line the feet either touch or do not (the rule `preview_anim.gd` had, before D-101 retired it).
	var view := get_viewport().get_visible_rect().size
	var aspect: float = view.x / maxf(view.y, 1.0)
	var wide := (spacing * float(samples - 1) + FRAME_MARGIN) / aspect
	var tall := FRAME_HIGH - FRAME_LOW + row_height * float(rows - 1)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(maxf(FRAME_MIN, wide), tall)
	cam.near = 0.05
	cam.far = 100.0
	cam.position = Vector3(0, (FRAME_LOW + FRAME_HIGH) * 0.5, 20.0)
	add_child(cam)
	cam.make_current()


## A 2 cm bar at the row's floor, behind the BOGs, so a hovering foot shows the
## line underneath it.
func _ground(y: float) -> void:
	var ground := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(120.0, 0.02, 0.02)
	ground.mesh = bar
	ground.position = Vector3(0.0, y, -0.8)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.38, 0.42)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground.material_override = mat
	add_child(ground)
