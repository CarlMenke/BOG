extends SceneTree
## Refit the Elder's robe and hat to the BOG's skeleton, without Blender
## (D-099). Development tool, not shipped.
##
##   Godot --headless --path . --script tools/refit_robe.gd
##
## Reads the robe geometry the old Blender build (`tools/build_elder.py`,
## D-037) fitted to this sculpt, scales it from the old body's height to
## the new one's, gives every vertex fresh weights against the **new**
## skeleton's rest pose by the same rule the Blender build used — the spine
## chain blended by height, a thigh share growing toward the hem and split
## left and right, the hat rigid to the head — and writes the result as the
## first skin in `art/skins/` (design item 11): a mesh bound to
## `art/bog/BOG.fbx`'s skeleton by bone name, with its own material, that
## `ElderRobe.don` drops onto a BOG's `Skeleton3D` and every clip in the
## library then moves for free.
##
## The old weights are read only to tell the hat from the robe: the hat was
## rigid to `Head` and stays so. Everything else is re-derived, because the
## auto-rig put its bones 8–10 cm from where the Gub's were (D-095, D-098) and
## weights assigned by the old joints' heights would sit a bone off.

## **Both inputs were retired at D-101**, with the old pipeline; the output
## below is committed, and to re-run this the two files are in git history at
## commit 1045d3a (`art/generated/elder.glb`, `art/generated/bog.glb`).
const OLD_ROBE := "res://art/generated/elder.glb"
const OLD_MESH := "Elder"
const OLD_BODY := "res://art/generated/bog.glb"
const BODY := "res://art/bog/BOG.fbx"
const OUT_DIR := "res://art/skins/elder/"
const OUT_MESH := OUT_DIR + "robe.res"
const OUT_MATERIAL := OUT_DIR + "robe_material.tres"
const OUT_SCENE := OUT_DIR + "robe.tscn"
const BASECOLOR := OUT_DIR + "elder_basecolor.png"
const EMISSIVE := OUT_DIR + "elder_emissive.png"

## The rule `build_elder.py` skinned the skirt by: this much of the hem goes
## to the thighs, growing from the hips down, split by which side of the
## body's axis a vertex sits, over this much of a half-width.
const LEG_SHARE_MAX := 0.35
const LEG_SPLIT_HALF := 0.16
## A vertex the old build weighted this much to the head is the hat.
const HAT_SHARE := 0.99
const SPINE_CHAIN := ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1",
	"mixamorig_Spine2", "mixamorig_Neck"]


func _initialize() -> void:
	var old := (load(OLD_ROBE) as PackedScene).instantiate()
	var old_mesh := old.find_child(OLD_MESH, true, false) as MeshInstance3D
	var old_body := (load(OLD_BODY) as PackedScene).instantiate()
	var new_body := (load(BODY) as PackedScene).instantiate()
	var skeleton := new_body.find_child("Skeleton3D", true, false) as Skeleton3D
	if old_mesh == null or skeleton == null:
		push_error("refit_robe: need %s's '%s' and %s's Skeleton3D" % [OLD_ROBE, OLD_MESH, BODY])
		quit(1)
		return

	var old_height: float = (old_body.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh.get_aabb().size.y
	var new_height: float = (new_body.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh.get_aabb().size.y
	var scale := new_height / old_height
	print("refit_robe: old body %.3f m, new body %.3f m, robe scaled x%.4f" % [old_height, new_height, scale])

	var arrays := old_mesh.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var old_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var old_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var old_stride: int = old_bones.size() / verts.size()
	var old_skin := old_mesh.skin
	var old_head := -1
	for i in old_skin.get_bind_count():
		if old_skin.get_bind_name(i) == "Head":
			old_head = i

	# The joints the robe hangs off, at their heights on the new rig.
	var joint_y := {}
	for bone in SPINE_CHAIN + ["mixamorig_Head", "mixamorig_LeftUpLeg", "mixamorig_RightUpLeg"]:
		var idx := skeleton.find_bone(bone)
		if idx < 0:
			push_error("refit_robe: the body has no %s" % bone)
			quit(1)
			return
		joint_y[bone] = skeleton.get_bone_global_rest(idx).origin.y
	var hips_y: float = joint_y["mixamorig_Hips"]
	var hem_y := INF
	for v in verts:
		hem_y = minf(hem_y, v.y * scale)
	var axis_x: float = skeleton.get_bone_global_rest(skeleton.find_bone("mixamorig_Hips")).origin.x

	# The new skin: one bind per bone the robe uses, by name, at the inverse of
	# the new rest — which is what makes the mesh land exactly where it was
	# modelled while the body stands still, and follow the bones when it moves.
	var skin := Skin.new()
	var bind_of := {}
	for bone in SPINE_CHAIN + ["mixamorig_Head", "mixamorig_LeftUpLeg", "mixamorig_RightUpLeg"]:
		bind_of[bone] = skin.get_bind_count()
		skin.add_named_bind(bone, skeleton.get_bone_global_rest(skeleton.find_bone(bone)).affine_inverse())

	var scaled := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var hat := 0
	for v in verts.size():
		var p := verts[v] * scale
		scaled.append(p)
		var head_share := 0.0
		for j in old_stride:
			if old_bones[v * old_stride + j] == old_head:
				head_share += old_weights[v * old_stride + j]
		var w := {}
		if head_share >= HAT_SHARE:
			w[bind_of["mixamorig_Head"]] = 1.0
			hat += 1
		else:
			w = _robe_weights(p, joint_y, hips_y, hem_y, axis_x, bind_of)
		_append_four(bones, weights, w)
	print("refit_robe: %d vertices, %d of them the hat; hem at %.3f m, hips at %.3f m" % [verts.size(), hat, hem_y, hips_y])

	arrays[Mesh.ARRAY_VERTEX] = scaled
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# The material is the old one's, re-pointed at the textures in this folder
	# so the skin is a folder that stands on its own (design item 11).
	var material := (old_mesh.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.albedo_texture = load(BASECOLOR)
	material.emission_texture = load(EMISSIVE)
	material.resource_name = "elder_robe"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(material, OUT_MATERIAL)
	material.take_over_path(OUT_MATERIAL)
	mesh.surface_set_material(0, material)
	_save(mesh, OUT_MESH)
	mesh.take_over_path(OUT_MESH)

	# A root with the mesh under it, as the old scene was, because `ElderRobe`
	# and the pickup take the mesh *out* of the scene by name.
	var root_node := Node3D.new()
	root_node.name = "ElderRobe"
	var instance := MeshInstance3D.new()
	instance.name = OLD_MESH
	instance.mesh = mesh
	instance.skin = skin
	root_node.add_child(instance)
	instance.owner = root_node
	var packed := PackedScene.new()
	packed.pack(root_node)
	_save(packed, OUT_SCENE)
	print("refit_robe: wrote %s, %s and %s" % [OUT_MESH, OUT_MATERIAL, OUT_SCENE])
	quit()


## `build_elder.py`'s `robe_weights`, on the new joints: the two spine joints
## either side of this height, plus the thigh share below the hips.
func _robe_weights(p: Vector3, joint_y: Dictionary, hips_y: float, hem_y: float,
		axis_x: float, bind_of: Dictionary) -> Dictionary:
	var w := {}
	var chain := SPINE_CHAIN
	if p.y <= joint_y[chain[0]]:
		w[bind_of[chain[0]]] = 1.0
	elif p.y >= joint_y[chain[chain.size() - 1]]:
		w[bind_of[chain[chain.size() - 1]]] = 1.0
	else:
		for i in range(1, chain.size()):
			var y0: float = joint_y[chain[i - 1]]
			var y1: float = joint_y[chain[i]]
			if p.y <= y1:
				var t := clampf((p.y - y0) / maxf(y1 - y0, 1e-6), 0.0, 1.0)
				if t > 0.0:
					w[bind_of[chain[i]]] = t
				if t < 1.0:
					w[bind_of[chain[i - 1]]] = 1.0 - t
				break
	if p.y < hips_y:
		var share := LEG_SHARE_MAX * smoothstep(0.0, 1.0, (hips_y - p.y) / maxf(hips_y - hem_y, 1e-6))
		var side := clampf((p.x - axis_x) / LEG_SPLIT_HALF, -1.0, 1.0)
		for k in w:
			w[k] *= 1.0 - share
		w[bind_of["mixamorig_LeftUpLeg"]] = share * (1.0 + side) * 0.5
		w[bind_of["mixamorig_RightUpLeg"]] = share * (1.0 - side) * 0.5
	return w


## Four influences per vertex, the heaviest first, renormalised.
static func _append_four(bones: PackedInt32Array, weights: PackedFloat32Array, w: Dictionary) -> void:
	var pairs := []
	for k in w:
		if w[k] > 1e-4:
			pairs.append([k, w[k]])
	pairs.sort_custom(func(a, b): return a[1] > b[1])
	pairs = pairs.slice(0, 4)
	var total := 0.0
	for pair in pairs:
		total += pair[1]
	for i in 4:
		if i < pairs.size():
			bones.append(pairs[i][0])
			weights.append(pairs[i][1] / total)
		else:
			bones.append(0)
			weights.append(0.0)


static func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("refit_robe: could not save %s (%d)" % [path, err])
