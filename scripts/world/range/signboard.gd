class_name RangeSignboard
extends Area3D
## The one control left on the range: a timber board you walk past that zeroes
## your practice stats (D-119).
##
## This file was `station.gd` and it was six glowing signposts — a post, a
## coloured lantern, an `OmniLight3D`, a billboarded `Label3D` and a chime —
## that cycled a zone's dummies through a ring of behaviours, reset a zone, or
## reset the stats. Five of the six are gone with the cycling itself: a zone's
## behaviour is now authored in the map (`range_map.DUMMIES` and the lane
## lookup in `_build_dummy_markers`) and never changes, so the west lane is
## always three standing bodies and you choose a lesson by walking to a
## different lane rather than by reconfiguring the one you are standing in.
##
## What is left is the stats reset, because it is the only switch on the range
## that is about the player rather than about the range, and it is deliberately
## the dullest object on the map:
##
##   no lantern   the twenty-four lantern heads are distance marks. A
##                twenty-fifth that meant something else was the one thing
##                stopping them reading as a scale.
##   no light     an `OmniLight3D` on the lodge deck at dusk is a light on the
##                eight spawn pads, which is four metres away.
##   no chime     the feedback is the stats panel in the corner of the HUD going
##                to zero, which is the thing you were looking at when you
##                decided to reset it. A sound as well would be the range
##                congratulating you for pressing a button.
##
## The post and the board are **not built here** — they are slabs in the lodge's
## own timber surface (`range_map._build_lodge`), so the sign is solid, takes the
## map's material and the map's shadow, and cannot drift from the marker that
## says where it is. This node is the trigger volume and the lettering.
##
## ## Host decides, and that is the whole of the networking
##
## `monitoring` is on for the host and nobody else, exactly as `Pickup` does it.
## `RangeStats` is host-authoritative and broadcasts its own rows, so a host-side
## `reset()` reaches every peer through the counter's own path: there is no RPC
## on this node and none in `RangeDirector` any more.

const LAYER_PLAYER := 2

## How wide you have to be to trip it, and how tall. Generous: this is a thing
## you walk past, and a player who brushed a signboard and got nothing would
## read that as the sign being broken.
const RADIUS := 1.4
const HEIGHT := 2.5
## One second between two triggers from the same player. Long enough that
## standing in front of the board does not zero the stats forty times a second,
## short enough that stepping away and back is a second reset.
const DEBOUNCE := 1.0

## Where the lettering sits on the board, and how far off its face. The board is
## `range_map.SIGN_BOARD` — 1.10 to 1.75 m up the post — so 1.42 is its middle.
const LABEL_Y := 1.42
const LABEL_OUT := 0.075
## Limed letters cut into tarred timber. Not emissive: a sign that glows is a
## lantern, and this map has enough of those.
const LABEL_COLOUR := Color(0.88, 0.83, 0.70)

var zone: String = ""
var action: String = ""

var _last: Dictionary = {}
var _label: Label3D


## Read a `Signs` marker. `action` and `zone` are the map's keys; the marker's
## own -Z is the way the board faces, as every marker group on this map is.
func setup(marker: Marker3D) -> void:
	zone = String(marker.get_meta("zone", "lodge"))
	action = String(marker.get_meta("action", "reset_stats"))
	name = "Sign_%s_%s" % [zone, action]
	transform = marker.transform


func _ready() -> void:
	add_to_group("range_signboards")
	collision_layer = 0
	collision_mask = LAYER_PLAYER
	# The host's overlap is the only one anybody acts on. See the header.
	monitoring = Net.is_host
	monitorable = false
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = RADIUS
	cylinder.height = HEIGHT
	shape.shape = cylinder
	shape.position.y = HEIGHT * 0.5
	add_child(shape)

	_label = Label3D.new()
	_label.text = title()
	_label.modulate = LABEL_COLOUR
	_label.font_size = 56
	_label.pixel_size = 0.0065
	_label.outline_size = 10
	_label.outline_modulate = Color(0.10, 0.07, 0.05, 0.9)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Flat on the board, not billboarded: it is carved into a plank. The board
	# faces the marker's -Z, so the text sits just proud of that face.
	_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_label.position = Vector3(0.0, LABEL_Y, -LABEL_OUT)
	_label.rotation.y = PI
	add_child(_label)

	body_entered.connect(_on_body_entered)


## What the board says.
func title() -> String:
	return "RESET\nSTATS" if action == "reset_stats" else action.to_upper()


func _on_body_entered(body: Node3D) -> void:
	if not Net.is_host:
		return
	var bog := body as Bog
	# A dummy walking past a signboard must not zero somebody's session — the
	# wanderer's whole job is to walk past things.
	if bog == null or not bog.alive or Net.is_dummy(bog.peer_id):
		return
	var now := Time.get_ticks_msec() * 0.001
	if now - float(_last.get(bog.peer_id, -999.0)) < DEBOUNCE:
		return
	_last[bog.peer_id] = now
	fire()


## What the overlap does, separated so a check can ask for it without standing a
## body in a cylinder.
func fire() -> void:
	if RangeDirector.instance == null:
		return
	if action == "reset_stats":
		RangeDirector.instance.reset_stats()
