extends SceneTree
## Make a recolour skin out of the body's own texture (D-100). Development
## tool, not shipped.
##
##   Godot --headless --path . --script tools/make_recolour.gd -- <name> <hue> [size]
##
## Reads `art/bog/BOG_0.png`, finds the yellow skin in it by the same hue and
## saturation window `resources/shaders/bog_team_tint.gdshader` uses to find
## it at draw time, turns that skin's hue by `hue` degrees, and writes
## `art/skins/<name>/basecolor.png` at `size` (default 2048, because the
## body's 4096² is 12 MB and a recolour does not need it). Everything the
## shader leaves alone — eyes, teeth, the dark patches — is left alone here
## too, so the team tint still finds the skin on a recoloured body.

const SOURCE := "res://art/bog/BOG_0.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("make_recolour: <name> <hue degrees> [size]")
		quit(1)
		return
	var skin_name: String = args[0]
	var turn := float(args[1])
	var size := int(args[2]) if args.size() > 2 else 2048
	var image := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if image == null:
		push_error("make_recolour: cannot read %s" % SOURCE)
		quit(1)
		return
	image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)
	var turned := 0
	for y in size:
		for x in size:
			var c := image.get_pixel(x, y)
			var skin := _skin(c)
			if skin <= 0.0:
				continue
			var shifted := Color.from_hsv(fmod(c.h + turn / 360.0 + 1.0, 1.0), c.s, c.v, c.a)
			image.set_pixel(x, y, c.lerp(shifted, skin))
			turned += 1
	var dir := "res://art/skins/%s/" % skin_name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var out := dir + "basecolor.png"
	var err := image.save_png(ProjectSettings.globalize_path(out))
	print("make_recolour: %s, %d of %d texels turned %+.0f°, %s" % [out, turned, size * size, turn,
		"ok" if err == OK else "error %d" % err])
	quit(0 if err == OK else 1)


## The shader's `skin` factor: saturated, and yellow-orange in hue.
static func _skin(c: Color) -> float:
	var hi := maxf(c.r, maxf(c.g, c.b))
	var lo := minf(c.r, minf(c.g, c.b))
	var saturation := (hi - lo) / hi if hi > 1e-4 else 0.0
	var hue := c.h * 360.0
	return smoothstep(0.35, 0.6, saturation) * smoothstep(15.0, 30.0, hue) * (1.0 - smoothstep(75.0, 95.0, hue))
