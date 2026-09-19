class_name GuideLine
extends Node3D
## The dashed ribbon on the ground that says where the letter is.
##
## A player dropped into Halcyon Wake for the first time cannot be told the
## letter is forty metres aft and be expected to find the companionway. The line
## is the answer, and it has to be the answer at a glance: gold means nobody has
## it, red means somebody does and you should go and kill them, blue means it is
## your team's business.
##
## **It is a drawing and nothing else** (D-010). Every peer resolves its own
## targets, bakes its own navmesh and smooths its own ribbon; nothing about it
## is replicated, nothing about it is read by a rule, and two clients drawing
## slightly different curves is a difference nobody can see (D-007).
##
## The work is split three ways so no one file is doing two jobs (D-098):
## `GuideTargets` answers *what* to point at, `GuidePath` turns a target into a
## polyline and keeps it calm, and this file turns polylines into meshes. What
## is here, therefore, is entirely about pixels:
##
## - **Camera-facing strips.** A tube would be honest geometry and worse to
##   look at; a flat ribbon 12 cm wide, twisted to face the lens at every point,
##   is what reads as a painted line from every angle.
## - **Two passes.** In front of the world at 0.85, and through it at 0.18 —
##   the same trick the carrier marker and the nameplates use (`no_depth_test`
##   with a render priority), because a route that vanishes behind the first
##   container is a route that only works on open ground.
## - **Three lines at most, sharing a trunk.** Three cards in Capture B·O·G
##   means three routes that all leave the player's feet the same way; drawn
##   whole they are one thick gold rope for the first twenty metres. The nearest
##   draws whole and the others draw only where they stop agreeing with it, at
##   half width.
##
## The per-frame cost is deliberately bounded: routes are re-solved five times a
## second, not every frame; a mesh is rebuilt only when its points or the camera
## actually moved; and a line is at most `GuidePath.MAX_POINTS` points long.

const SHADER := preload("res://resources/shaders/guide_line.gdshader")

## The shader's own render mode, and the same thing with the depth test off. A
## `ShaderMaterial` cannot switch a render mode the way `StandardMaterial3D`
## switches `no_depth_test`, and the x-ray pass needs exactly one word changed,
## so the second shader is made by editing the first's source once at startup.
## Both strings must match `resources/shaders/guide_line.gdshader` exactly.
const DEPTH_MODE := "render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;"
const XRAY_MODE := "render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, depth_test_disabled;"

## Ribbon width. Twelve centimetres is a third of the Bog's shoulders: wide
## enough to read at thirty metres, narrow enough not to cover the floor it is
## drawn on.
const WIDTH := 0.12
const SOLID_ALPHA := 0.85
const XRAY_ALPHA := 0.18
## The x-ray pass draws first so the solid one lies over it where both are
## visible; otherwise the ghost line washes out the real one.
const SOLID_PRIORITY := 1
const XRAY_PRIORITY := 0

## Three, because Capture B·O·G has three cards and a fourth line has never had
## anything to say.
const MAX_LINES := 3
## A branch off the shared trunk is thinner and dimmer, so the nearest target
## stays obviously the nearest.
const BRANCH_WIDTH := 0.5
const BRANCH_ALPHA := 0.5

## The ribbon ramps up over the first metre and a half out of the player's feet
## — a line that starts at full width under the camera looks like it is growing
## out of the player's chin — and back down over the last half metre so it lands
## on the target rather than stopping at it.
const HEAD_FADE := 1.5
const TAIL_FADE := 0.5

## How far the camera has to move before the strips must be re-twisted.
const CAMERA_EPSILON := 0.01

var _paths: Dictionary = {}          ## key -> GuidePath
var _slots: Array[Dictionary] = []   ## the meshes, reused between targets
var _solid: ShaderMaterial
var _xray_shader: Shader
var _bake: NavBake
var _last_eye: Vector3 = Vector3.INF
var _last_forward: Vector3 = Vector3.ZERO


func _ready() -> void:
	_xray_shader = _make_xray_shader()
	for i in MAX_LINES:
		_slots.append(_build_slot(i))
	set_process(true)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var targets := GuideTargets.resolve()
	var me := MatchState.bogs.get(Net.local_id()) as Bog
	if camera == null or targets.is_empty() or me == null or not is_instance_valid(me):
		_paths.clear()
		_hide_from(0)
		return

	if _bake == null or not is_instance_valid(_bake):
		_bake = get_tree().get_first_node_in_group(NavBake.GROUP) as NavBake

	var from := me.global_position
	var live: Array[GuidePath] = []
	var keys: Dictionary = {}
	for target: Dictionary in targets:
		var key := String(target["key"])
		keys[key] = true
		var path: GuidePath = _paths.get(key)
		if path == null:
			path = GuidePath.new(key, String(target["kind"]), target["colour"])
			_paths[key] = path
		path.colour = target["colour"]
		path.kind = String(target["kind"])
		path.solve(delta, from, target["pos"], _bake)
		live.append(path)

	# Targets come and go — a card is taken, a carrier dies — and a route left
	# in the table would keep being smoothed for a thing that is not there.
	for key: String in _paths.keys():
		if not keys.has(key):
			_paths.erase(key)

	# Nearest first: it is the one that draws whole, and the one every other
	# line measures its trunk against.
	live.sort_custom(func(a: GuidePath, b: GuidePath) -> bool: return a.length < b.length)
	var shown := mini(live.size(), MAX_LINES)
	for i in shown:
		live[i].trim_to(null if i == 0 else live[0])

	var eye := camera.global_position
	var forward := -camera.global_transform.basis.z
	var camera_moved := eye.distance_to(_last_eye) > CAMERA_EPSILON \
		or forward.distance_to(_last_forward) > CAMERA_EPSILON * 0.2
	_last_eye = eye
	_last_forward = forward

	for i in shown:
		_draw(i, live[i], i > 0, camera, camera_moved)
	_hide_from(shown)


# ------------------------------------------------------------------ pixels ---

func _draw(slot_index: int, path: GuidePath, branch: bool, camera: Camera3D,
		camera_moved: bool) -> void:
	var slot: Dictionary = _slots[slot_index]
	var root: Node3D = slot["root"]
	var points: PackedVector3Array = path.points
	if points.size() < 2 or path.fade <= 0.005:
		root.visible = false
		slot["key"] = ""
		return
	root.visible = true

	var width := WIDTH * (BRANCH_WIDTH if branch else 1.0)
	var changed: bool = path.moved or camera_moved \
		or String(slot["key"]) != path.key or int(slot["points"]) != points.size() \
		or not is_equal_approx(float(slot["width"]), width)
	if changed:
		_strip(slot["mesh"], points, width, camera.global_position)
		slot["key"] = path.key
		slot["points"] = points.size()
		slot["width"] = width

	var fade := path.fade * (BRANCH_ALPHA if branch else 1.0)
	var colour := Vector3(path.colour.r, path.colour.g, path.colour.b)
	for material: ShaderMaterial in [slot["solid"], slot["xray"]]:
		material.set_shader_parameter("line_colour", colour)
		material.set_shader_parameter("fade", fade)


## One camera-facing triangle strip along `points`.
##
## The side vector at each point is the path's own tangent crossed with the line
## of sight, so the ribbon stays edge-on to nothing and face-on to the lens all
## the way along — including over a jump arc, where the path is briefly
## vertical and a fixed up-vector would turn the ribbon into a knife edge.
func _strip(mesh: ImmediateMesh, points: PackedVector3Array, width: float,
		eye: Vector3) -> void:
	mesh.clear_surfaces()
	var total := GuidePath.polyline_length(points)
	if points.size() < 2 or total <= 0.01:
		return
	var half := width * 0.5
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var walked := 0.0
	for i in points.size():
		var point := points[i]
		if i > 0:
			walked += point.distance_to(points[i - 1])
		var side := _tangent(points, i).cross(eye - point)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		side = side.normalized() * half
		# The vertex alpha is the whole of the head and tail fade; the shader
		# multiplies it by the dashes and by the line's own opacity.
		var alpha := smoothstep(0.0, HEAD_FADE, walked) \
			* smoothstep(0.0, TAIL_FADE, total - walked)
		var tint := Color(1.0, 1.0, 1.0, alpha)
		mesh.surface_set_color(tint)
		mesh.surface_set_uv(Vector2(walked, 0.0))
		mesh.surface_add_vertex(point - side)
		mesh.surface_set_color(tint)
		mesh.surface_set_uv(Vector2(walked, 1.0))
		mesh.surface_add_vertex(point + side)
	mesh.surface_end()


static func _tangent(points: PackedVector3Array, index: int) -> Vector3:
	var before := points[maxi(index - 1, 0)]
	var after := points[mini(index + 1, points.size() - 1)]
	var tangent := after - before
	if tangent.length_squared() < 0.000001:
		return Vector3.FORWARD
	return tangent.normalized()


func _hide_from(index: int) -> void:
	for i in range(index, _slots.size()):
		var slot: Dictionary = _slots[i]
		var root: Node3D = slot["root"]
		root.visible = false
		slot["key"] = ""


# ------------------------------------------------------------------- setup ---

func _build_slot(index: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Line%d" % index
	root.visible = false
	add_child(root)

	# One mesh, two instances: the geometry is identical and only the material
	# differs, so building the strip twice would be paying twice for the same
	# hundred vertices.
	var mesh := ImmediateMesh.new()
	var solid := _material(SHADER, SOLID_ALPHA, SOLID_PRIORITY)
	var xray := _material(_xray_shader, XRAY_ALPHA, XRAY_PRIORITY)
	return {
		"root": root,
		"mesh": mesh,
		"solid": solid,
		"xray": xray,
		"key": "",
		"points": 0,
		"width": 0.0,
		"solid_node": _instance(root, "Solid", mesh, solid),
		"xray_node": _instance(root, "Xray", mesh, xray),
	}


func _instance(root: Node3D, node_name: String, mesh: ImmediateMesh,
		material: ShaderMaterial) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The strip is rebuilt in world space every time it changes, so the node
	# must not also carry a transform: `extra_cull_margin` keeps a line whose
	# own origin is behind the camera from being culled with it.
	node.extra_cull_margin = 64.0
	root.add_child(node)
	return node


static func _material(shader: Shader, alpha: float, priority: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("line_alpha", alpha)
	material.render_priority = priority
	return material


## The through-wall twin of the shader on disk. One word of render mode, added
## in code because a render mode is compiled into the shader and a material
## cannot override it.
func _make_xray_shader() -> Shader:
	var shader := Shader.new()
	var code := SHADER.code
	if not code.contains(DEPTH_MODE):
		# Said out loud rather than drawn wrong: without the edit the second
		# pass is an exact copy of the first and the line simply stops at walls.
		push_warning("guide_line: the shader's render mode has been reworded; "
			+ "the x-ray pass will be depth tested until GuideLine.DEPTH_MODE matches")
		shader.code = code
		return shader
	shader.code = code.replace(DEPTH_MODE, XRAY_MODE)
	return shader
