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

## The health bar (D-062), and everything about it is chosen so that it is the
## **same plate** rather than a second system: it hangs under the name, it takes
## the plate's scale, it fades with the plate's distance fade, and it is drawn
## through walls for a teammate and only for a teammate, exactly as the name is
## (D-047). Health is combat information about a specific body, and the body is
## already the thing that carries it.
##
## In metres at the plate's base scale. 0.66 m against a 1.55 m Gub is a bar a
## little wider than its shoulders and a little narrower than a seven-letter
## name — measured against a rendered frame rather than reasoned about, because
## the first guess (0.52, "about shoulder width") came out visibly meaner than
## the name above it and read as a detail rather than as a gauge. Wide enough
## that the difference between 70 and 40 is a glance rather than a measurement,
## narrow enough that a crowd of them is not a wall of bars.
##
## A fixed width and not the name's, unlike `ALLY_BAR_HEIGHT`'s team stripe: a
## player called `Jo` and a player called `Wolfsbane` are hurt by the same
## amount, and two bars that mean the same thing have to be the same size.
const HEALTH_BAR := Vector2(0.66, 0.07)
## Below the text, as a fraction of the label's height — under the team stripe
## when there is one, so the two never share a row.
const HEALTH_BAR_DROP := 0.66
const HEALTH_BAR_DROP_ALLY := 1.05
## Behind the fill, so a bar at 12% still has a full-width shape to be read
## against. Without it a nearly-dead Gub's bar is a speck, and a speck reads as
## "no bar" — which is what a Gub at *full* health looks like, so the two states
## furthest apart in the game would look the same.
##
## The empty part is the fill's own colour dimmed to `HEALTH_BACK_DIM` rather
## than a neutral grey: it keeps the hue, so the shape stays visible over a
## sunlit patch of sand as well as over dark forest, and a bar that has just
## gone red is red across its whole length before it is read at all.
##
## `HEALTH_EDGE` is the same argument the name's outline makes (`OUTLINE_SIZE`,
## which is deliberately thick) — a dark border a fraction of the bar's height
## proud of it on every side, so the bar has an edge against whatever is behind
## the Gub. Without it the whole thing disappears into a dark tree line, which
## is exactly where these fights happen.
const HEALTH_BACK_DIM := 0.22
const HEALTH_EDGE := Color(0.02, 0.03, 0.04, 0.92)
## How far the dark border stands proud of the bar, as a fraction of its height.
const HEALTH_EDGE_MARGIN := 0.30
## Green down to `HEALTH_HURT_AT`, amber down to `HEALTH_LOW_AT`, red under it.
## Bands rather than a gradient: a colour that slides continuously is a colour
## nobody can name, and "he's on red" is a thing a player says out loud. The
## numbers are the two decisions in a fight — at 50 a spear is still one shot and
## nothing has changed, at 25 an arrow from any draw at all will finish them.
const HEALTH_GOOD := Color(0.38, 0.86, 0.42)
const HEALTH_HURT := Color(1.00, 0.68, 0.24)
const HEALTH_LOW := Color(1.00, 0.32, 0.26)
const HEALTH_HURT_AT := 0.5
const HEALTH_LOW_AT := 0.25

var _label: Label3D
var _bar: MeshInstance3D
## The health bar's own little rig: a node turned to face the camera every
## frame, with the backing and the fill as flat children of it.
##
## Turned, rather than each quad billboarded by its material the way the team
## stripe is, because the fill has to grow **from the left edge** and a
## billboarded quad has no left edge to measure from — its material spins it
## about its own origin, so a quad offset sideways to keep its left edge still
## would slide along a fixed world direction and the bar would empty toward the
## north-west. One node holding the camera's basis gives both quads a shared
## screen-space x, and the offset is then arithmetic.
var _health_root: Node3D
var _health_edge: MeshInstance3D
var _health_back: MeshInstance3D
var _health_fill: MeshInstance3D
var _camera: Camera3D
var _text: String = "Gub"
var _colour: Color = NEUTRAL_COLOUR
var _ally: bool = false
## 1 -> 0. Starts full, which is also the state in which nothing is drawn.
var _health: float = 1.0


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
	_build_health_bar()
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
		_place_health(1.0)
		return
	var alpha := 1.0 - clampf(inverse_lerp(FADE_START, FADE_END, distance), 0.0, 1.0)
	_label.modulate = Color(_colour, alpha)
	_label.outline_modulate = Color(0.02, 0.03, 0.04, 0.85 * alpha)
	_label.visible = alpha > 0.01
	# The bar fades with the name and disappears with it. An enemy's health at
	# 30 m is the same information as an enemy's name at 30 m — worth nothing,
	# and the silhouette already said somebody is over there.
	_place_health(alpha)


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


## Where the health bar is this frame, how wide the fill is, and what colour it
## has come out (D-062). Called once per frame from `_process`, after the label
## has been sized, because the bar takes its scale from the label's.
##
## `alpha` is the plate's own distance fade, 1 for a teammate.
func _place_health(alpha: float) -> void:
	if _health_root == null:
		return
	# **Only a hurt Gub has a bar.** A row of full bars over a lobby says
	# nothing and hides the one that matters; a bar appearing is itself the
	# information, and it is how a player notices that the Gub they are chasing
	# has already been in a fight.
	_health_root.visible = _health < 1.0 and _label.visible and alpha > 0.01
	if not _health_root.visible:
		return
	var grow := _label.pixel_size / PIXEL_SIZE
	var drop := FONT_SIZE * _label.pixel_size \
		* (HEALTH_BAR_DROP_ALLY if _ally else HEALTH_BAR_DROP)
	# The camera's own basis, so screen-right is the bar's x and the fill can be
	# offset along it. The drop is world-down rather than screen-down: the bar
	# belongs under the name in the world, and the camera does not roll.
	_health_root.global_transform = Transform3D(_camera.global_basis,
		global_position + Vector3.DOWN * drop)

	var width := HEALTH_BAR.x * grow
	var height := HEALTH_BAR.y * grow
	var margin := height * HEALTH_EDGE_MARGIN
	(_health_edge.mesh as QuadMesh).size = Vector2(width + margin * 2.0,
		height + margin * 2.0)
	(_health_back.mesh as QuadMesh).size = Vector2(width, height)
	# Never thinner than it is tall while there is anything left: a fill of two
	# pixels reads as an empty bar, and "empty" is the one state this cannot
	# show — the Gub would be a corpse and the plate would be gone with it.
	var fill := maxf(width * _health, height)
	(_health_fill.mesh as QuadMesh).size = Vector2(fill, height)
	# Left-aligned: the fill keeps its left edge and loses its right one, which
	# is the only direction a bar is allowed to empty in.
	_health_fill.position = Vector3(-(width - fill) * 0.5, 0.0, 0.004)

	var colour := HEALTH_GOOD
	if _health < HEALTH_LOW_AT:
		colour = HEALTH_LOW
	elif _health < HEALTH_HURT_AT:
		colour = HEALTH_HURT
	(_health_fill.material_override as StandardMaterial3D).albedo_color = \
		Color(colour, alpha)
	(_health_back.material_override as StandardMaterial3D).albedo_color = \
		Color(colour * HEALTH_BACK_DIM, 0.85 * alpha)
	(_health_edge.material_override as StandardMaterial3D).albedo_color = \
		Color(HEALTH_EDGE, HEALTH_EDGE.a * alpha)


## What the host says is left of this Gub, as a fraction. Pushed by `Gub` from
## its own `set_health` and from nowhere else, so the bar and the number the
## host is about to kill it on are the same number (D-062).
func set_health(current: float, maximum: float) -> void:
	_health = clampf(current / maxf(0.01, maximum), 0.0, 1.0)


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
	# The same wallhack rule the name is under, applied to the bar for the same
	# reason (D-047): a teammate's health through a rock is help, an enemy's is
	# a cheat. `_place_health` does the rest every frame.
	if _health_back != null:
		for quad: MeshInstance3D in [_health_edge, _health_back, _health_fill]:
			(quad.material_override as StandardMaterial3D).no_depth_test = _ally


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


## The health bar: a camera-facing root, a dark border, a dimmed backing and the
## fill in front of them. Built for every plate and shown only on a Gub that has
## been hurt.
##
## Each quad carries its own unshaded material rather than a shared copy: they
## all differ every frame — the fill's colour, the backing's dimmed copy of it,
## the border's alpha — and a shared material would be a mutable global
## recoloured by whichever Gub happened to be drawn last.
func _build_health_bar() -> void:
	_health_root = Node3D.new()
	_health_root.name = "HealthBar"
	_health_root.visible = false
	add_child(_health_root)
	_health_edge = _health_quad("HealthEdge", HEALTH_EDGE, 1)
	_health_back = _health_quad("HealthBack", HEALTH_GOOD * HEALTH_BACK_DIM, 2)
	_health_fill = _health_quad("HealthFill", HEALTH_GOOD, 3)
	_health_root.add_child(_health_edge)
	_health_root.add_child(_health_back)
	_health_root.add_child(_health_fill)
	# Stacked toward the camera in the order they are drawn, a couple of
	# millimetres apart: enough for the depth buffer, not enough to be seen from
	# an angle. The fill's own offset is set every frame by `_place_health`.
	_health_back.position = Vector3(0.0, 0.0, 0.002)


## One flat quad of the bar. `priority` puts the three of them in a fixed order
## for the renderer — border, backing, fill — which is what the couple of
## millimetres of z between them says in space as well: enough for the depth
## buffer, not enough to be seen from an angle.
func _health_quad(node_name: String, colour: Color, priority: int) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = colour
	material.render_priority = priority
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = QuadMesh.new()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _text_width() -> float:
	var font := _label.font if _label.font != null else ThemeDB.fallback_font
	return font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
