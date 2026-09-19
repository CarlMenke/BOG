extends SceneTree
## Write the body's mesh as Godot imports it -- positions, UVs, triangles, in
## the game's metres -- to `build/body_ref.glb`, so a Python tool can know the
## body's UV layout without reading FBX. `tools/bake_skin.py` needs it: a skin
## whose Tripo download is a *remeshed* sculpt has its paint baked onto the
## body's own layout by nearest surface point, and the body is the target.
## Development tool, not shipped; the output is untracked and remade on demand.
##
##   Godot --headless --path . --script tools/export_body_ref.gd

const BODY := "res://art/bog/BOG.fbx"
const OUT := "res://build/body_ref.glb"


func _initialize() -> void:
	var body := (load(BODY) as PackedScene).instantiate()
	root.add_child(body)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(body, state)
	if err != OK:
		push_error("export_body_ref: append_from_scene failed (%d)" % err)
		quit(1)
		return
	err = doc.write_to_filesystem(state, OUT)
	if err != OK:
		push_error("export_body_ref: write failed (%d)" % err)
		quit(1)
		return
	print("export_body_ref: wrote %s" % OUT)
	quit()
