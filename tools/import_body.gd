@tool
extends EditorScenePostImport
## The BOG's body, as Godot imports it from `art/bog/BOG.fbx` (D-095), made
## into the scene the game instances: the one mesh named `Bog` so
## `Bog.BODY_MESH_NAME` finds it, and the shared clip library
## `art/generated/bog_clips.res` put on the body's AnimationPlayer in place of
## Mixamo's T-pose, so every tool and scene that instances the body has every
## clip without adding anything (D-098). A skin is a texture or a mesh on this
## same skeleton and inherits the lot.

const LIBRARY := "res://art/generated/bog_clips.res"
const MESH_NAME := "Bog"


func _post_import(scene: Node) -> Object:
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		push_error("import_body: expected one mesh on the body, found %d" % meshes.size())
	else:
		meshes[0].name = MESH_NAME

	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		push_error("import_body: the body has no AnimationPlayer")
		return scene
	if not ResourceLoader.exists(LIBRARY):
		push_warning("import_body: %s is not built yet; import the clips and re-import the body" % LIBRARY)
		return scene
	for lib_name in player.get_animation_library_list():
		player.remove_animation_library(lib_name)
	player.add_animation_library("", load(LIBRARY))
	print("import_body: mesh '%s', %d clips from %s" % [MESH_NAME, player.get_animation_list().size(), LIBRARY])
	return scene
