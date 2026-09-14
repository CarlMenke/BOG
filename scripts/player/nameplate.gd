class_name Nameplate
extends Node3D
## The floating name above a Gub's head.
##
## Every Gub looks identical — the name is the *only* way to tell who you are
## looking at, in the lobby and in the match. So it is treated as gameplay
## information, not decoration: always legible, never hidden by the crowd, and
## occluded by scenery so it cannot be used to see through a rock.
##
## The plate lives in the world, at the world's scale: it shrinks with distance
## like everything else. It used to be `fixed_size`, which pinned it to a
## constant number of screen pixels — that reads as correct in a screenshot and
## wrong in motion, because a name across the island stayed exactly as large as
## the one on the Gub beside you, so the crowd came out as a wall of identical
## floating text with the players somewhere behind it. Perspective is the cue
## that says which name belongs to which body, and it was the one thing being
## thrown away.

## The label's world size is `FONT_SIZE * PIXEL_SIZE` tall, which works out at
## about 0.21 m — a Gub is 1.55 m, so a six-letter name is roughly the width of
## its shoulders and sits like a label on the model rather than over it.
##
## The two numbers are not interchangeable even though only their product sets
## the size: `FONT_SIZE` is the resolution the glyphs are rasterised at, so it
## is deliberately large and `PIXEL_SIZE` small. Halving `FONT_SIZE` and
## doubling `PIXEL_SIZE` would give a plate of exactly the same size made of
## half as many pixels, and it would go to mush the moment anyone plays above
## 1080p.
const FONT_SIZE := 64
const PIXEL_SIZE := 0.0033
## Thick enough to survive being shrunk. The outline is what keeps a name off a
## sunlit patch of grass, and at range it is most of what is left of the plate.
const OUTLINE_SIZE := 14

## Beyond this the plate fades out.
##
## These came down with the plate. At a fixed screen size the old 34-46 m was
## honest — the text was as big out there as it was in your face, so it was
## still worth drawing. In perspective a name at 34 m is four or five pixels
## tall and is no longer a name, it is a smear that says "somebody is over
## there", which is information the Gub's own silhouette already gives you for
## free. Fading it out at the distance it stops being readable is the same
## decision the old numbers made, applied to a plate that now has a size.
const FADE_START := 20.0
const FADE_END := 28.0

const TEAM_COLOURS: Array[Color] = [
	Color(0.42, 0.72, 1.00),   # blue
	Color(1.00, 0.48, 0.42),   # red
	Color(0.56, 0.90, 0.52),   # green
	Color(0.96, 0.78, 0.36),   # amber
	Color(0.80, 0.58, 0.98),   # violet
	Color(0.44, 0.92, 0.88),   # teal
	Color(0.98, 0.62, 0.83),   # pink
	Color(0.78, 0.78, 0.82),   # grey
]

const NEUTRAL_COLOUR := Color(0.94, 0.95, 0.97)

## A teammate's plate (D-047) is the one exception to everything above, and it
## is an exception on purpose. "Who is on my side and where are they" is not
## something a player should have to earn by line of sight: the answer never
## changes during a match, and a teammate you cannot find is a teammate you
## cannot help. So a teammate's name is drawn through the scenery, never fades,
## and stops shrinking once it reaches the size it has at `ALLY_HOLD_FROM`, so
## it is still a *name* across the island rather than a smear.
##
## Enemies are untouched — occluded and faded exactly as before. Nothing about
## this reaches a Gub on another team, which is the whole reason it is allowed.
##
## A little larger than an enemy's plate up close, and it keeps its size with
## distance where an enemy's does not, so the two read differently before the
## colour is even looked at. The bar under the name is the second cue, for the
## case colour alone does not carry — two teams whose colours sit close, or a
## player who does not see the difference between them.
const ALLY_SCALE := 1.2
const ALLY_HOLD_FROM := 11.0
const ALLY_OUTLINE_SIZE := 18
const ALLY_BAR_HEIGHT := 0.035
## Below the text, as a fraction of the label's height.
const ALLY_BAR_DROP := 0.62

var _label: Label3D
var _bar: MeshInstance3D
var _camera: Camera3D
var _text: String = "Gub"
var _colour: Color = NEUTRAL_COLOUR
var _ally: bool = false


func _ready() -> void:
	_label = Label3D.new()
	# Turned to face the camera, but not scaled to it: the plate keeps its world
	# size and shrinks and grows with the Gub it belongs to.
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = false
	_label.font_size = FONT_SIZE
	_label.outline_size = OUTLINE_SIZE
	_label.outline_modulate = Color(0.02, 0.03, 0.04, 0.85)
	_label.pixel_size = PIXEL_SIZE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Occluded by the world like anything else: a nameplate visible through a
	# boulder is a wallhack you handed out for free. `_refresh` lifts this for a
	# teammate's plate and for nobody else (D-047).
	_label.no_depth_test = false
	_label.shaded = false
	_label.double_sided = true
	_label.render_priority = 1
	add_child(_label)
	_build_bar()
	_refresh()


func _process(_delta: float) -> void:
	if _label == null:
		return
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return
	var distance := global_position.distance_to(_camera.global_position)
	if _ally:
		_hold_size(distance)
		return
	var alpha := 1.0 - clampf(inverse_lerp(FADE_START, FADE_END, distance), 0.0, 1.0)
	_label.modulate = Color(_colour, alpha)
	_label.outline_modulate = Color(0.02, 0.03, 0.04, 0.85 * alpha)
	_label.visible = alpha > 0.01


## A teammate's plate at full strength at any range, scaled up past
## `ALLY_HOLD_FROM` so its height on screen stops falling.
func _hold_size(distance: float) -> void:
	var grow := maxf(1.0, distance / ALLY_HOLD_FROM)
	var pixel := PIXEL_SIZE * ALLY_SCALE * grow
	_label.pixel_size = pixel
	_label.modulate = _colour
	_label.outline_modulate = Color(0.02, 0.03, 0.04, 0.95)
	_label.visible = true
	var height := FONT_SIZE * pixel
	var width := _text_width() * pixel
	(_bar.mesh as QuadMesh).size = Vector2(width * 0.8, ALLY_BAR_HEIGHT * ALLY_SCALE * grow)
	_bar.position = Vector3(0.0, -height * ALLY_BAR_DROP, 0.0)


func set_display_name(value: String) -> void:
	_text = value
	_refresh()


## `team` of `MatchConfig.TEAM_NONE` uses the neutral colour, which is what
## free-for-all wants: everyone is a threat, so nobody is colour-coded.
func set_team(team: int) -> void:
	_colour = NEUTRAL_COLOUR if team < 0 else TEAM_COLOURS[team % TEAM_COLOURS.size()]
	_refresh()


## Whether this plate belongs to a teammate of the player looking at it, which
## is decided by `MatchState` per peer — the same Gub is a teammate on one
## screen and an enemy on the next. See `ALLY_SCALE` and D-047.
func set_ally(value: bool) -> void:
	_ally = value
	_refresh()


func is_ally() -> bool:
	return _ally


static func colour_for_team(team: int) -> Color:
	return NEUTRAL_COLOUR if team < 0 else TEAM_COLOURS[team % TEAM_COLOURS.size()]


func _refresh() -> void:
	if _label == null:
		return
	_label.text = _text
	_label.modulate = _colour
	# Drawn over the scenery for a teammate only. An enemy's plate stays in the
	# depth test, which is what stops it being a wallhack.
	_label.no_depth_test = _ally
	_label.outline_size = ALLY_OUTLINE_SIZE if _ally else OUTLINE_SIZE
	_label.pixel_size = PIXEL_SIZE * ALLY_SCALE if _ally else PIXEL_SIZE
	_bar.visible = _ally
	(_bar.material_override as StandardMaterial3D).albedo_color = _colour


## The team-coloured bar under a teammate's name. Built for every plate and
## shown only on an ally's, so a plate that changes sides needs nothing new.
func _build_bar() -> void:
	var quad := QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 1
	_bar = MeshInstance3D.new()
	_bar.name = "AllyBar"
	_bar.mesh = quad
	_bar.material_override = material
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.visible = false
	add_child(_bar)


func _text_width() -> float:
	var font := _label.font if _label.font != null else ThemeDB.fallback_font
	return font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
