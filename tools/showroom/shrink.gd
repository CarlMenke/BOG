extends SceneTree
## The fallback for `tools/showroom/shrink.py` on a checkout without Pillow.
## Development tool, not shipped.
##
##     Godot --headless --path . --script tools/showroom/shrink.gd -- <out> [web]
##
## Same job, and the same two shapes of source directory:
##
##   <out>/<variant>/<mode>.png  ->  <web>/<variant>__<mode>.jpg
##   <out>/<name>.png            ->  <web>/<name>.jpg
##
## `<web>` defaults to `<out>/web`.

const WIDTH := 1600
const QUALITY := 0.85


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() >= 1 else "tools/showroom/out"
	var web: String = args[1] if args.size() >= 2 else out.path_join("web")
	DirAccess.make_dir_recursive_absolute(web)

	var written := 0
	var dir := DirAccess.open(out)
	if dir == null:
		push_error("shrink: cannot open %s" % out)
		quit(1)
		return

	for variant: String in dir.get_directories():
		if variant == "web" or variant == "logs":
			continue
		var inner := DirAccess.open(out.path_join(variant))
		if inner == null:
			continue
		for file: String in inner.get_files():
			written += _shrink(out.path_join(variant).path_join(file),
				web, "%s__%s" % [variant, file.get_basename()])

	# The flat shape: `out` is itself a folder of PNGs, which is what the layout
	# showroom writes. One of the two loops always finds nothing.
	for file: String in dir.get_files():
		written += _shrink(out.path_join(file), web, file.get_basename())

	print("shrink: wrote %d jpg into %s" % [written, web])
	quit(0)


## One PNG, if that is what it is. Returns how many were written, so the callers
## above can add it up without a branch of their own.
func _shrink(source: String, web: String, stem: String) -> int:
	if not source.ends_with(".png"):
		return 0
	var image := Image.load_from_file(source)
	if image == null:
		push_error("shrink: could not read %s" % source)
		return 0
	var height := int(round(image.get_height() * float(WIDTH) / image.get_width()))
	image.resize(WIDTH, height, Image.INTERPOLATE_LANCZOS)
	var target := web.path_join("%s.jpg" % stem)
	if image.save_jpg(target, QUALITY) != OK:
		push_error("shrink: could not write %s" % target)
		return 0
	return 1


func _process(_delta: float) -> bool:
	return true
