class_name CarrierMarker
extends Node3D
## A gold card over the head of a Bog that is carrying something the whole
## lobby needs to know about, drawn through the scenery for everyone (D-050).
##
## Today that is a letter hold: from the moment a Bog touches a card until it
## banks the letter, dies or the match ends, every screen — both teams, and
## everyone in a free-for-all — sees a card with the letter on it hanging over
## that Bog, through walls, at any range. The lit card in the fist (D-035) is
## still there; this is the part of the tell that does not need line of sight.
##
## **Knows nothing about letters.** It is a glyph and a colour, switched on and
## off by whoever decides that a Bog is a carrier — `BogCombat` for a letter
## hold. The next thing that is carried (a capture-the-flag letter) turns on the
## same marker with `set_carrying`, so "somebody over there has the thing" reads
## the same way in every mode.
##
## **Not a nameplate, and deliberately not like one.** A teammate's name is also
## drawn through walls (D-047), and two floating through-wall reads that look
## alike would merge into one. So this is a filled gold card with a dark glyph on
## it and no text beside it — a shape, where a plate is lettering with an outline
## — and it sits above the plate, clear of even a teammate's enlarged one.
##
## **Hidden over your own Bog.** You know you are carrying; the HUD lamps say so
## and count the seconds, and a gold card parked above your head in the middle of
## your own view would be in the way of the fight the hold starts.
##
## **Hidden over a corpse**, from the frame `alive` drops. The host ends the hold
## a round trip later and that is what actually turns the marker off, but a card
## floating over a Bog already mid-ragdoll for that round trip says the wrong
## thing about who has it.

## World size of the card up close. At the distance it starts holding its size
## (`HOLD_FROM`) a 0.52 m card is about 33 px tall on a 1080p screen, which is
## a readable letter and a hair bigger than a plate's name there.
const CARD_SIZE := Vector2(0.40, 0.52)
## The dark border around the card, which is what keeps gold readable against a
## sunlit sky or a sand-coloured rock.
const BORDER := 0.05
const INK := Color(0.05, 0.04, 0.02)
const FONT_SIZE := 96
## The glyph's height as a fraction of the card's.
const GLYPH_FILL := 0.72

## Past this distance the marker scales with distance, so its height on screen
## stops falling. The same distance a teammate's plate uses, deliberately: the
## plate below grows at exactly the same rate, so the gap between them holds.
const HOLD_FROM := Nameplate.ALLY_HOLD_FROM
## Height of the card's centre above this node, at `grow` 1. This node sits where
## the nameplate does; the tallest plate there is a teammate's, whose top is
## half its label height above centre. The card's bottom clears that by `GAP`.
const GAP := 0.08
const CARD_LIFT := \
	Nameplate.FONT_SIZE * Nameplate.PIXEL_SIZE * Nameplate.ALLY_SCALE * 0.5 \
	+ GAP + (CARD_SIZE.y + BORDER * 2.0) * 0.5

var _glyph: String = ""
var _colour: Color = Color(1.00, 0.84, 0.26)
var _bog: Bog
var _camera: Camera3D
var _back: MeshInstance3D
var _card: MeshInstance3D
var _label: Label3D


func _ready() -> void:
	_bog = get_parent() as Bog
	_back = _quad("Border", INK, 2)
	_card = _quad("Card", _colour, 3)
	_label = Label3D.new()
	_label.name = "Glyph"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = FONT_SIZE
	_label.outline_size = 0
	_label.modulate = INK
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.no_depth_test = true
	_label.shaded = false
	_label.double_sided = true
	_label.render_priority = 4
	add_child(_label)
	_apply()


## Show the marker with `glyph` on the card, in `colour`; an empty glyph takes it
## away. Idempotent, so a driver can call it on every change it hears about.
func set_carrying(glyph: String, colour: Color = Color(1.00, 0.84, 0.26)) -> void:
	_glyph = glyph
	_colour = colour
	_apply()


func is_carrying() -> bool:
	return _glyph != ""


func glyph() -> String:
	return _glyph


## Whether the marker is actually up on this screen — carrying, alive, and not
## the local player's own Bog. What the checks ask.
func is_shown() -> bool:
	return visible and _card != null and _card.visible


func _process(_delta: float) -> void:
	if not is_carrying() or _card == null:
		return
	var shown := _bog == null or (_bog.alive and _bog.peer_id != Net.local_id())
	visible = shown
	if not shown:
		return
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return
	_layout(maxf(1.0, global_position.distance_to(_camera.global_position) / HOLD_FROM))


func _apply() -> void:
	if _card == null:
		return
	visible = is_carrying()
	_back.visible = is_carrying()
	_card.visible = is_carrying()
	_label.visible = is_carrying()
	_label.text = _glyph
	(_card.material_override as StandardMaterial3D).albedo_color = _colour
	_layout(1.0)
	set_process(is_carrying())


func _layout(grow: float) -> void:
	var lift := Vector3(0.0, CARD_LIFT * grow, 0.0)
	(_card.mesh as QuadMesh).size = CARD_SIZE * grow
	(_back.mesh as QuadMesh).size = (CARD_SIZE + Vector2.ONE * BORDER * 2.0) * grow
	_card.position = lift
	_back.position = lift
	_label.position = lift
	_label.pixel_size = CARD_SIZE.y * GLYPH_FILL * grow / FONT_SIZE


func _quad(node_name: String, colour: Color, priority: int) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = colour
	material.render_priority = priority
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = QuadMesh.new()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.visible = false
	add_child(mesh)
	return mesh
