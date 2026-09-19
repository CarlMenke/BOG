class_name Minimap
extends Control
## The corner map for a B·O·G match: you, your team, the letters, and nothing
## else (the letters round).
##
## **It is on in B·O·G and in nothing else**, and that is the whole of its
## justification. A minimap in a kill-limit deathmatch is a radar, and a radar
## takes the fight out of the clearing and puts it in the corner of the screen:
## you stop looking for a Bog and start looking for a dot. B·O·G is the one mode
## where the thing you are chasing is not a player — it is a card that has to be
## found on a map you have played six times and still cannot picture — and a
## letter that nobody can find is a mode that stalls. So this answers exactly
## that question and refuses every other one: **an enemy with no letter is not
## drawn.** Someone hunting you is still something you have to hear and see.
##
## **Heading-up rather than north-up.** A north-up map has to be read (where am
## I facing, therefore which way is that dot) and a heading-up one is looked at
## (the dot is over there, so run that way). The cost is that the ground under
## it spins, which is why the ground is barely there — a wash of the walkable
## area at eight per cent, enough to say "there is floor between us" and not
## enough to be a picture you try to navigate by.
##
## Three controls stacked, because a disc has to be cut out of a square:
## `_clip` draws an opaque disc that is never seen — it is `CLIP_CHILDREN_ONLY`,
## so its own paint is the stencil and only its child survives it — and `_world`
## draws the rotating map inside that stencil. The stencil is drawn opaque
## rather than in `PANEL` for the reason a stencil is drawn at all: the mask's
## alpha multiplies its children's, so a 0.72 disc would quietly take a quarter
## off every blip. The translucent disc a player actually sees is painted by
## *this* control, under the stack, and the rim and the north tick by `_rim`
## over it — a parent's own `_draw` lands under its children and there is no
## other way to get a line on top of them.
##
## Nothing here replicates and nothing here is authoritative: it reads
## `MatchState` the way the rest of the HUD does, once per frame, and every
## count it draws is available to `tools/hud_range.gd` through `debug_counts()`
## so the harness can assert what is on screen without photographing it.

## The map's own square. Matches the node in `hud.tscn`; set here as well so the
## control has a size in a harness that hangs one on a bare `Control`.
const SIZE := 180.0
## Metres from you to the rim. Thirty is a little over the distance a Bog covers
## in four seconds of sprinting, which makes "on the map" and "reachable before
## anything changes" the same statement. Wider and the blips crowd the middle;
## narrower and a letter is off the edge for most of the run to it.
const RANGE_M := 30.0
## The group `NavBake` puts itself in. Looked up by group and called by name
## rather than typed, on purpose: the HUD has no business holding a class from
## the world layer, and a build whose nav bake is missing or still baking has to
## degrade to a map with no ground rather than to a parse error.
const NAV_GROUP := "nav_bake"

const RIM_WIDTH := 2.0
const RIM_SEGMENTS := 64
## A teammate is five pixels across, which is the smallest dot that still has a
## colour rather than being a grey speck. A carrier is bigger because it is the
## one blip you are meant to act on.
const ALLY_DOT := 2.5
const CARRIER_DOT := 3.5
## The letter itself, not a dot with a letter next to it: a card lying in the
## grass is the most legible thing this map can draw, so it is drawn as the
## glyph. Eleven pixels with a void outline behind it, which is what "bold"
## means over a wash of ground — a heavier face would still lose to the terrain.
const GLYPH_SIZE := 11
const GLYPH_OUTLINE := 4
## The gap between a carrier's dot and the letter beside it.
const GLYPH_GAP := 3.0
## A team's vault in Capture: a ring rather than a dot, because it is a place
## you go to rather than a thing that moves.
const VAULT_RING := 7.0
const VAULT_RING_WIDTH := 1.5
## The north tick's length inward from the rim, and the N beside it.
const NORTH_TICK := 7.0
const NORTH_LABEL := 13
## Your own arrow. Always at the centre and always pointing up, because the map
## turns under you and not the other way round.
const YOU_HALF_WIDTH := 5.0
const YOU_NOSE := 7.0
const YOU_TAIL := 4.0

## The stencil, its child, and the line over the top. Built in `_ready` rather
## than authored in `hud.tscn`: three nested full-rect controls whose only
## content is a `_draw` are three nodes nobody can read in a scene file, and two
## of them exist purely to make a circle out of a square.
var _clip: Control
var _world: Control
var _rim: Control

## The walkable area, rasterised once when `NavBake` says it has baked. Null
## before then, and then the map is blips over an empty disc — which is the
## honest picture, and better than a wrong one drawn from a half-built mesh.
var _outline: ImageTexture = null
var _outline_bounds: AABB = AABB()
var _nav: Node = null

## Radians the world is turned by so the camera's forward points up the screen.
var _heading: float = 0.0
## Where you are, in world XZ. The camera's own position while spectating, so
## the map keeps working for a dead player watching somebody else.
var _origin: Vector2 = Vector2.ZERO
## What the last `refresh` found, in draw order. Each entry is
## `{at: Vector2 (world XZ), dot: Color, radius: float, glyph: String,
## tint: Color}`; `radius <= 0.0` draws no dot and an empty `glyph` no letter,
## so one list covers a plain teammate, a carrier and a loose card.
var _blips: Array[Dictionary] = []
## `{at: Vector2, colour: Color}` per team vault, drawn under everything else.
var _rings: Array[Dictionary] = []

var _allies: int = 0
var _letters: int = 0
var _carriers: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)

	_clip = Control.new()
	_clip.name = "Clip"
	_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_clip.draw.connect(_draw_stencil)
	add_child(_clip)

	_world = Control.new()
	_world.name = "World"
	_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.draw.connect(_draw_world)
	_clip.add_child(_world)

	_rim = Control.new()
	_rim.name = "Rim"
	_rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rim.draw.connect(_draw_rim)
	add_child(_rim)

	# The backdrop and the stencil are the two layers `refresh` does not touch —
	# they depend on nothing but the size — so the size is what redraws them.
	resized.connect(_on_resized)


## Read the world and mark the two moving layers dirty. Called once a frame by
## the HUD while the map is visible, and by `tools/hud_range.gd` before it reads
## `debug_counts()`.
##
## **The gather is here and not in `_draw`**, which is the one structural choice
## worth defending: a harness has to be able to ask what the map found without a
## frame ever being rendered — a headless run draws nothing at all — and a count
## computed inside `_draw` would be a count that only exists in a screenshot.
func refresh() -> void:
	_adopt_nav()
	_blips.clear()
	_rings.clear()
	_allies = 0
	_letters = 0
	_carriers = 0

	var camera := get_viewport().get_camera_3d()
	if camera != null:
		# The camera looks down its own -Z. Turn the world so that direction is
		# up the screen: the forward flattened to XZ has to land on (0, -1).
		var forward := -camera.global_transform.basis.z
		if absf(forward.x) > 0.0001 or absf(forward.z) > 0.0001:
			_heading = -PI * 0.5 - atan2(forward.z, forward.x)
		_origin = Vector2(camera.global_position.x, camera.global_position.z)

	var me := Net.local_id()
	var mine: Bog = MatchState.bogs.get(me)
	if is_instance_valid(mine):
		_origin = Vector2(mine.global_position.x, mine.global_position.z)

	_gather_vaults()
	_gather_bogs(me)
	_gather_letters()

	_world.queue_redraw()
	_rim.queue_redraw()


## What the last `refresh` put on the map, for `tools/hud_range.gd`.
##
## `allies` counts teammates drawn, `carriers` everyone drawn holding a card
## (either side), `letters` loose cards drawn. A teammate carrying one is in two
## of those, because it is two facts and the harness asserts them separately.
## Everything counted is inside `RANGE_M` — what is off the edge is not on the
## map, and a count that included it would be asserting something invisible.
func debug_counts() -> Dictionary:
	return {"allies": _allies, "letters": _letters, "carriers": _carriers}


func _on_resized() -> void:
	queue_redraw()
	_clip.queue_redraw()
	_rim.queue_redraw()


# ----------------------------------------------------------------- the nav ---

func _adopt_nav() -> void:
	if _nav != null and is_instance_valid(_nav):
		return
	_nav = get_tree().get_first_node_in_group(NAV_GROUP)
	if _nav == null:
		return
	if _nav.has_signal("baked") and not _nav.is_connected("baked", _on_nav_baked):
		_nav.connect("baked", _on_nav_baked)
	# A HUD built after the bake finished — a testbed, or a player who joined
	# late — would otherwise wait forever for a signal that has already been
	# emitted. Asking costs one call on the frame the node is first seen.
	if _nav.has_method("is_ready") and bool(_nav.call("is_ready")):
		_on_nav_baked(0)


## Converted once, and only once: `ImageTexture.create_from_image` walks every
## pixel, and the walkable area does not change during a match.
func _on_nav_baked(_msec: int) -> void:
	if _outline != null or _nav == null or not is_instance_valid(_nav):
		return
	if not _nav.has_method("outline_image") or not _nav.has_method("bounds"):
		return
	var image: Image = _nav.call("outline_image")
	if image == null or image.is_empty():
		return
	_outline = ImageTexture.create_from_image(image)
	_outline_bounds = _nav.call("bounds")
	_world.queue_redraw()


# ---------------------------------------------------------------- the blips ---

func _gather_vaults() -> void:
	if not MatchState.is_capture():
		return
	var layout := MatchState.capture_layout()
	if layout == null:
		return
	for team in layout.vaults.size():
		var vault: Vector3 = layout.vaults[team]
		var at := Vector2(vault.x, vault.z)
		# A ring is allowed to hang over the rim, because half a ring still says
		# "your vault is that way" and the clip cuts it cleanly.
		if not _in_range(at, VAULT_RING / _pixels_per_metre()):
			continue
		_rings.append({"at": at, "colour": UIPalette.team_colour(team)})


## Everybody but you. Three cases and one of them is "draw nothing", which is
## the rule this whole control is built around (see the class note).
func _gather_bogs(me: int) -> void:
	var teams := Net.config.mode == MatchConfig.Mode.TEAMS
	var my_team := Net.player_team(me)
	var carriers := MatchState.letter_carriers()
	for peer_id: int in MatchState.bogs:
		if peer_id == me:
			continue
		var bog: Bog = MatchState.bogs[peer_id]
		# Alive twice over, the way `_tick_capture` asks it: a dead Bog's body
		# keeps its collision and its position where it fell (D-043), so the
		# host's row and the body have to agree before a dot is drawn.
		if not is_instance_valid(bog) or not bog.alive or not MatchState.is_alive(peer_id):
			continue
		var at := Vector2(bog.global_position.x, bog.global_position.z)
		if not _in_range(at):
			continue
		var friendly := teams and Net.player_team(peer_id) == my_team
		var letter := MatchState.letter_hold_letter(peer_id) if carriers.has(peer_id) else 0
		if letter == 0:
			if not friendly:
				continue
			_blips.append({"at": at, "dot": UIPalette.team_colour(my_team),
				"radius": ALLY_DOT, "glyph": "", "tint": UIPalette.TEXT})
			_allies += 1
			continue
		# A carrier is the one blip that is both a person and a letter, so it is
		# drawn as both: the dot says where to run and the glyph says which card
		# is going to fall out of them (D-050 puts the same marker over the head
		# in-world, and this is that marker seen from above).
		var colour := UIPalette.GUIDE_ALLY if friendly else UIPalette.GUIDE_ENEMY
		_blips.append({"at": at, "dot": colour, "radius": CARRIER_DOT,
			"glyph": MatchState.letter_name(letter), "tint": colour})
		_carriers += 1
		if friendly:
			_allies += 1


## Every live untaken card, vault cards included — a letter standing in a team's
## vault is exactly the thing somebody is about to come and steal, so leaving it
## off the map would hide the mode's whole second half.
func _gather_letters() -> void:
	for pickup: Pickup in MatchState.loose_letter_pickups():
		if not is_instance_valid(pickup):
			continue
		var at := Vector2(pickup.global_position.x, pickup.global_position.z)
		if not _in_range(at):
			continue
		_blips.append({"at": at, "dot": Color(0, 0, 0, 0), "radius": 0.0,
			"glyph": MatchState.letter_name(pickup.letter),
			"tint": UIPalette.GUIDE_LOOSE})
		_letters += 1


# ---------------------------------------------------------------- the paint ---

## The disc a player sees: drawn by this control, so it lands *under* the
## stencilled stack rather than over it.
func _draw() -> void:
	draw_circle(size * 0.5, _radius(), UIPalette.PANEL)


## Never seen. `CLIP_CHILDREN_ONLY` uses what this paints as a mask and throws
## the paint away, and the mask has to be opaque — its alpha multiplies the
## alpha of everything inside it.
func _draw_stencil() -> void:
	_clip.draw_circle(_clip.size * 0.5, _radius(), Color(1, 1, 1, 1))


func _draw_world() -> void:
	var centre := _world.size * 0.5
	var zoom := _pixels_per_metre()
	_draw_ground(centre, zoom)

	for ring: Dictionary in _rings:
		_world.draw_arc(_to_screen(ring["at"], centre, zoom), VAULT_RING,
			0.0, TAU, 24, ring["colour"], VAULT_RING_WIDTH, true)

	var font := get_theme_default_font()
	for blip: Dictionary in _blips:
		var point := _to_screen(blip["at"], centre, zoom)
		var radius := float(blip["radius"])
		if radius > 0.0:
			_world.draw_circle(point, radius, blip["dot"])
		var glyph := String(blip["glyph"])
		if glyph.is_empty():
			continue
		var width := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, GLYPH_SIZE).x
		# A dot puts its letter beside it; a loose card is the letter, so it is
		# centred on its own position.
		var at := point + Vector2(-width * 0.5, GLYPH_SIZE * 0.38)
		if radius > 0.0:
			at = point + Vector2(radius + GLYPH_GAP, GLYPH_SIZE * 0.38)
		_world.draw_string_outline(font, at, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1,
			GLYPH_SIZE, GLYPH_OUTLINE, UIPalette.VOID)
		_world.draw_string(font, at, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1,
			GLYPH_SIZE, blip["tint"])

	# You, last, because the one blip that is never anywhere else must never be
	# under anything: a triangle rather than a dot, pointing up the screen,
	# which is the only mark on this map whose shape carries information.
	_world.draw_colored_polygon(PackedVector2Array([
		centre + Vector2(0.0, -YOU_NOSE),
		centre + Vector2(-YOU_HALF_WIDTH, YOU_TAIL),
		centre + Vector2(YOU_HALF_WIDTH, YOU_TAIL),
	]), UIPalette.TEXT)


## The walkable area, mapped from `NavBake.bounds()` and turned with everything
## else.
##
## Built as a matrix rather than as `draw_set_transform`'s angle-and-scale,
## because the image's two axes are not the same number of metres per pixel
## unless the map happens to be square, and a single scale would stretch every
## map that is not.
func _draw_ground(centre: Vector2, zoom: float) -> void:
	if _outline == null:
		return
	var image_size := _outline.get_size()
	if image_size.x <= 0.0 or image_size.y <= 0.0:
		return
	if _outline_bounds.size.x <= 0.0 or _outline_bounds.size.z <= 0.0:
		return
	var per_px := Vector2(_outline_bounds.size.x / image_size.x,
		_outline_bounds.size.z / image_size.y) * zoom
	var corner := Vector2(_outline_bounds.position.x, _outline_bounds.position.z)
	var mapping := Transform2D(
		Vector2(per_px.x, 0.0).rotated(_heading),
		Vector2(0.0, per_px.y).rotated(_heading),
		_to_screen(corner, centre, zoom))
	_world.draw_set_transform_matrix(mapping)
	_world.draw_texture_rect(_outline, Rect2(Vector2.ZERO, image_size), false,
		UIPalette.RAISED_STRONG)
	_world.draw_set_transform_matrix(Transform2D.IDENTITY)


## The rim and the one thing on this map that is not relative to you: north.
## Without it a heading-up map has no way of telling you that you have turned
## around, which is the one thing a map is for when you are lost.
func _draw_rim() -> void:
	var centre := _rim.size * 0.5
	var radius := _radius()
	_rim.draw_arc(centre, radius - RIM_WIDTH * 0.5, 0.0, TAU, RIM_SEGMENTS,
		UIPalette.LINE_STRONG, RIM_WIDTH, true)
	var north := Vector2(0.0, -1.0).rotated(_heading)
	_rim.draw_line(centre + north * (radius - RIM_WIDTH),
		centre + north * (radius - RIM_WIDTH - NORTH_TICK),
		UIPalette.LINE_STRONG, RIM_WIDTH, true)
	var font := get_theme_default_font()
	var width := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, NORTH_LABEL).x
	var label := centre + north * (radius - RIM_WIDTH - NORTH_TICK - 6.0) \
		+ Vector2(-width * 0.5, NORTH_LABEL * 0.38)
	_rim.draw_string_outline(font, label, "N", HORIZONTAL_ALIGNMENT_LEFT, -1,
		NORTH_LABEL, GLYPH_OUTLINE, UIPalette.VOID)
	_rim.draw_string(font, label, "N", HORIZONTAL_ALIGNMENT_LEFT, -1,
		NORTH_LABEL, UIPalette.TEXT_DIM)


# ----------------------------------------------------------------- the maths ---

func _radius() -> float:
	return minf(size.x, size.y) * 0.5


## Never zero. A control asked for its scale before the first layout pass has
## no size yet, and the vault test divides by this — an infinity there would
## put every vault on a map that is not on screen anyway.
func _pixels_per_metre() -> float:
	return maxf(_radius(), 1.0) / RANGE_M


## One world XZ point, turned by the heading and scaled to the disc.
func _to_screen(at: Vector2, centre: Vector2, zoom: float) -> Vector2:
	return centre + (at - _origin).rotated(_heading) * zoom


func _in_range(at: Vector2, slack: float = 0.0) -> bool:
	return _origin.distance_squared_to(at) <= (RANGE_M + slack) * (RANGE_M + slack)
