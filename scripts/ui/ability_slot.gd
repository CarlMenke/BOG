class_name AbilitySlot
extends Control
## One square in the ability bar: what it is, which key fires it, and whether
## pressing that key right now will do anything (PLAN 6.1).
##
## **The tile is a photograph of the thing** (D-076, on the user's own
## *"use screen shots of the actual assets instead of icons"*). Every subject on
## this bar is already a built `.glb`, and a drawn glyph of a prop the player is
## about to hold is a second, worse description of it that has to be kept in
## step by hand. `tools/bake_tiles.gd` photographs all seven under one camera,
## one light rig and one framing rule, and commits the result to
## `resources/ui/tiles/`; see that file's header for the rule and why it is not
## "fit the bounding box".
##
## **The drawn glyphs are kept, as the fallback and for the bolt.** Lightning is
## the one thing on this bar with no asset to photograph — it is a bolt, not a
## prop — so it keeps the polygon it has always been drawn as, and a tile whose
## PNG is missing falls back to its own glyph rather than to an empty square.
## Which means this file still holds a complete drawn set, and a fresh clone
## before its first import still has a readable ability bar.
##
## **State is the brightness, and since D-118 only the brightness.** A drawn
## glyph could be tinted to the slot's colour for free; a photograph cannot, and
## painting one amber would throw away the only thing it is there for. So the
## three levels D-036 settled — empty, waiting, ready — are carried by how
## brightly the photograph is lit: full for a tile you can press, knocked back
## for one you cannot, knocked back further for one you have none of.
##
## They used to be carried by a 1.5 px amber border as well, which D-036 called
## "the state at a glance from the corner of the eye". The Quiet theme took every
## border in the UI away and left four strokes that mean something, and an outline
## drawn around four tiles that are *always* on screen is not one of them: with
## nothing else on the HUD outlined, four yellow boxes in the corner became the
## loudest thing in the frame, and they said "ready" in the same yellow the tile
## says "this is you" in everywhere else. A lit photograph on a dark plate is the
## same three levels with nothing drawn around them.
##
## The key cap is read out of the input map rather than typed in, so a slot can
## never claim Q while the action is bound to something else.
##
## **The first slot times its recharge; nothing else here does** (D-054, which
## amends D-036). A slot used to eat a wedge out of itself and print the seconds
## left, and D-036 took both away with the crosshair's ring. The ring stays gone.
## The tile got half of it back, on the user's word, and on the condition that
## makes it honest where the ring never was: the clock starts at the *release*,
## not at the click. Through the windup the tile is dark and says nothing, which
## is true — the spear is still in the hand and nothing is growing back yet.
## A slot is whichever of these its caller talks to it in:
##
## * `set_armed` — the spear, or the Elder's bolt. Lit or dark, plus, while the
##   weapon is genuinely growing back, a fill that climbs clockwise from twelve
##   o'clock and the seconds left printed over the glyph. The caller decides
##   when that is; this file only draws what it is handed.
## * `set_stock` — the shield, the magnet and the heal potion. They are carried
##   stock (D-032, D-067), so the count is the readout, and an empty slot is the
##   ordinary state at the start of every life rather than a fault to be alarmed
##   by. The potion's `busy` is its channel rather than a use-delay, which is
##   the same news said about a different clock: the tile is dark for the two
##   seconds the drink is running and the count has already come down.
##
## **The first slot changes what it is.** An Elder has no spear — it throws
## lightning instead (D-038) — so the same tile swaps its glyph and its label
## and gets the same treatment off the bolt's own clock. One tile in one place
## on the bar that timed one weapon and not the other would be two rules for one
## square.

## Appended to, never reordered: the ordinal is what `hud.tscn` stores in each
## slot's exported `kind`, and inserting one in the middle would silently turn
## every tile in the scene into a different tile.
## The five glyphs this square can draw, plus the two the weapon select added
## (D-069). The first slot on the bar is whichever weapon this Bog actually
## brought, the way it has always been the bolt for an Elder — so a bow player
## reads their own recharge off it instead of watching a spear tile that will
## never light.
enum Kind { SPEAR, SHIELD, MAGNET, LIGHTNING, POTION, BOW, SWORD }

const SIZE := 62.0
## The tile's corner, and the corner of everything drawn inside it: the plate,
## the foot, the photograph's mask and the recharge sweep all use this one
## number, so the square has exactly one silhouette. Eight rather than the
## theme's ten because this is a 62 px square and not a panel — ten on a tile
## this small eats the corners the count and the key cap sit in.
const RADIUS := 8.0

## The plate the photograph sits on. Near-black at 0.35, which is the same
## reading the rest of the Quiet HUD gives: a dimming of the arena rather than a
## surface painted over it. It was 0.62 and, with the border gone, that much
## opacity made a square of night sky in the corner of a lit map.
const PLATE := Color(0.02, 0.025, 0.03, 0.35)

## Which photograph each kind wears. Keyed by `Kind` so a tile that changes what
## it stands for (D-069, and the Elder since D-038) changes its picture with it,
## and missing an entry is how the bolt keeps its drawn glyph.
const TILE_ART := {
	Kind.SPEAR: "res://resources/ui/tiles/spear.png",
	Kind.SHIELD: "res://resources/ui/tiles/shield.png",
	Kind.MAGNET: "res://resources/ui/tiles/magnet.png",
	Kind.POTION: "res://resources/ui/tiles/heal_potion.png",
	Kind.BOW: "res://resources/ui/tiles/bow.png",
	Kind.SWORD: "res://resources/ui/tiles/greatsword.png",
}

## Which photograph a *weapon* wears, so the lobby's picker and the first square
## on the bar show the same prop. A table indexed by a weapon rather than a
## `match`, which is D-069's rule and the reason `Loadout.CARRY_CLIPS` is one
## too: nothing should have to branch on which weapon a Bog brought.
const WEAPON_KIND := {
	Loadout.Weapon.SPEAR: Kind.SPEAR,
	Loadout.Weapon.BOW: Kind.BOW,
	Loadout.Weapon.SWORD: Kind.SWORD,
}

## How much of the tile the photograph is drawn into. The bake already framed
## the prop inside its own square (`bake_tiles.INK`), so this is only the margin
## that keeps it off the border and out of the two corners the count and the key
## cap live in.
const ART_INSET := 3.0

## What a photograph is dimmed to in each of the three states D-036 settled.
## Ready is untouched; waiting is knocked back but still legible as the thing it
## is; empty is knocked back further, because "you have none" and "not for
## another second" are different answers and a player who cannot tell them apart
## keeps pressing the key.
const ART_READY := 1.0
const ART_WAITING := 0.46
const ART_EMPTY := 0.20

## The strip along the bottom of the tile that the carried count and the key cap
## sit on. A drawn glyph could be kept clear of those two corners by hand — the
## note on `COUNT_LEFT` below is the record of somebody doing exactly that — and
## a photograph cannot, because it is framed by a rule rather than by a
## draughtsman. So the tile gets a foot: a veil, not a bar, dark enough that a
## white "2" and a grey "Q" read over weathered planks and thin enough that the
## prop still runs behind it.
const FOOT_HEIGHT := 19.0
const FOOT_TINT := Color(0.02, 0.027, 0.04, 0.70)

## Where the carried count sits: bottom-left, which is the one corner of the
## square that no glyph reaches into and that the key cap — bottom-right — does
## not want. Measured against all three shapes, whose leftmost extents at this
## height are the shield's left stile at x=17 and the crystal's lower spikes at
## x=24 — drawn glyphs, from before the tiles became photographs (D-076).
const COUNT_FONT_SIZE := 22
const COUNT_LEFT := 6.0
const COUNT_BASELINE := 57.0

## The recharge readout. The number sits over the centre of the glyph, which is
## the one place on the square the eye already goes to, and is outlined because
## it is drawn over a glyph and a fill and has to read against both.
const TIMER_FONT_SIZE := 22
const TIMER_OUTLINE := 8
const TIMER_BASELINE := 35.0
## How much of the Bog's yellow the recovered part of the fill carries. Enough to
## see the wedge from the corner of the eye, little enough that the dark glyph
## under it still reads as "not yet".
const SWEEP_ALPHA := 0.26

@export var kind: Kind = Kind.SPEAR
## The input action this slot fires, used for the key cap.
@export var action: String = "primary_attack"
@export var label_text: String = "Spear"

## How many are being carried, or -1 for a slot with no stock to report. The
## spear is the only one of those: it is the thing you always have (D-032), so a
## permanent "1" on it would be a number that never moved and therefore never
## got read.
var _count: int = -1
## Usable this instant. For the spear that is `has_spear()`; for stock it is
## "there is at least one and the use-delay has passed".
var _lit: bool = true
## Seconds until the weapon is back, and what that is out of. Both zero means
## "no timer to draw" — ready, winding up, or dark for some other reason (a
## letter hold) that this clock does not measure.
var _remaining: float = 0.0
var _total: float = 0.0
## Is the weapon this tile stands for put away (the feel round)?
##
## A third readiness state on the photograph, and it is the one D-036 already
## has words for: "you have none" and "not for another second" are different
## answers, and "you put it away" is a third — so it borrows `ART_EMPTY`, which
## is the shade this bar uses for *nothing to spend*, rather than the recharge's
## `ART_WAITING`. A player who sees the waiting shade waits; a player who sees
## this one has to do something, and what they have to do is on the key cap.
var _stowed: bool = false

@onready var _cap: Label = %KeyCap
@onready var _name: Label = %Name


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)
	_cap.text = SettingsPanel.primary_key(action)
	_name.text = label_text


## Make this slot stand for something else.
##
## The key cap is left alone unless `next_action` says otherwise, and since
## D-070 **no caller says otherwise**. The parameter survives rather than being
## deleted, and that is the interesting part of this comment.
##
## D-069 added it because a bow was fired by `draw_bow` and a sword by
## `swing_sword`, so a tile that stood for one had to carry that key or it was
## telling a player to press the wrong thing. All four weapons are one
## `primary_attack` now, so every tile this bar can show — spear, bow, great
## sword, and the Elder's bolt, which was already on the spear's own button —
## says LMB, and the cap never moves for anybody.
##
## It stays because the *rule* it encodes is still the rule: a caller that
## changes what a tile fires must change what the tile says it is fired with. The
## day a fifth thing arrives on a key of its own, the tile is already honest.
##
## Read out of the input map rather than typed in, exactly as `_ready` does it,
## so a rebound key moves both.
func set_kind(next: Kind, next_label: String,
		next_action: String = "") -> void:
	if kind == next:
		return
	kind = next
	label_text = next_label
	_name.text = next_label
	if not next_action.is_empty():
		action = next_action
		_cap.text = SettingsPanel.primary_key(action)
	queue_redraw()


## The spear or the bolt: armed or not, and — only while it is growing back —
## how long that has left out of how long it takes. Leave both at zero for "no
## timer": the HUD does exactly that through a windup and through a hold.
func set_armed(is_armed: bool, remaining: float = 0.0, total: float = 0.0) -> void:
	if is_armed or remaining <= 0.0 or total <= 0.0:
		remaining = 0.0
		total = 0.0
	remaining = minf(remaining, total)
	if not is_equal_approx(remaining, _remaining) or total != _total:
		_remaining = remaining
		_total = total
		queue_redraw()
	_apply(-1, is_armed)


## Is the weapon on this tile put away, and which key brings it back (the feel
## round)?
##
## The two are one call because they are one statement. A tile that dimmed
## without changing its cap would be telling a player their weapon is gone and
## leaving them pressing the button that used to fire it; a cap that changed
## without the tile dimming would be a key with no reason on it. This is the one
## caller `set_kind`'s `next_action` parameter was kept alive for, and it obeys
## that function's rule exactly: what fires the tile changed, so what the tile
## says it is fired with changed with it.
##
## Read out of the input map rather than typed, so a rebound H moves both.
func set_stowed(stowed: bool, next_action: String) -> void:
	if next_action != action:
		action = next_action
		_cap.text = SettingsPanel.primary_key(next_action)
		queue_redraw()
	if stowed == _stowed:
		return
	_stowed = stowed
	queue_redraw()


## Fraction of the recharge already done, 0..1, or -1 while no timer is shown.
## Read by `tools/hud_range.gd`, which is why it exists as a function rather than
## as arithmetic inside `_draw`.
func recharge_progress() -> float:
	if _total <= 0.0:
		return -1.0
	return clampf(1.0 - _remaining / _total, 0.0, 1.0)


## The seconds as drawn, or "" while no timer is shown. Tenths under ten
## seconds, whole seconds above, and always rounded *up*: a tile reading "0.0"
## over a spear that is not back yet would be a lie by a rounding.
func recharge_text() -> String:
	if _total <= 0.0:
		return ""
	if _remaining < 9.95:
		return "%.1f" % (ceilf(_remaining * 10.0 - 0.0001) / 10.0)
	return "%d" % int(ceilf(_remaining))


## Carried stock. `busy` is the short floor between two placements
## (`shield_use_delay`, `magnet_use_delay`) and only dims the slot — it never
## draws a number, because it is a cap on how fast a stack can be emptied and
## not a resource anybody plans a fight around.
func set_stock(count: int, busy: bool) -> void:
	_apply(maxi(0, count), count > 0 and not busy)


## Called by the HUD every frame, so it repaints only when something actually
## changed. Count and lit are discrete, so on its own that is genuinely rare; the
## one tile with a recharge running repaints every frame of it in `set_armed`,
## because there the number really does move every frame.
func _apply(count: int, lit: bool) -> void:
	if count == _count and lit == _lit:
		return
	_count = count
	_lit = lit
	queue_redraw()


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
	var tint := _tint()

	# No border. The plate, the sweep, the photograph and the foot all end on the
	# same 8 px corner instead, which is what makes the tile a shape rather than
	# a rectangle with a drawing in it.
	draw_style_box(_plate(), box)
	if _total > 0.0:
		_draw_sweep(recharge_progress())
	var photographed := _draw_art()
	if not photographed:
		_draw_glyph(tint)
	else:
		draw_style_box(_foot(), Rect2(0.0, SIZE - FOOT_HEIGHT, SIZE, FOOT_HEIGHT))
	if _total > 0.0:
		_draw_timer()

	if _count >= 0:
		_draw_count()


## The plate and the foot, built once for the whole bar. Both are `StyleBoxFlat`
## rather than `draw_rect` because `draw_rect` has no corner and a rounded box
## drawn as a polygon has no antialiasing — at 62 px with an 8 px radius the
## stair-stepping on a bare polygon is plainly visible against the arena.
##
## Static, because seven tiles drawing two identical boxes every frame of a
## recharge is seven times the garbage for one picture.
static var _plate_box: StyleBoxFlat = null
static var _foot_box: StyleBoxFlat = null


static func _plate() -> StyleBoxFlat:
	if _plate_box == null:
		_plate_box = StyleBoxFlat.new()
		_plate_box.bg_color = PLATE
		_plate_box.set_corner_radius_all(int(RADIUS))
		_plate_box.corner_detail = 8
		_plate_box.anti_aliasing = true
	return _plate_box


## The foot is square along the top, where it meets the photograph, and takes
## the tile's own corner along the bottom, where it *is* the tile's edge.
static func _foot() -> StyleBoxFlat:
	if _foot_box == null:
		_foot_box = StyleBoxFlat.new()
		_foot_box.bg_color = FOOT_TINT
		_foot_box.corner_radius_top_left = 0
		_foot_box.corner_radius_top_right = 0
		_foot_box.corner_radius_bottom_left = int(RADIUS)
		_foot_box.corner_radius_bottom_right = int(RADIUS)
		_foot_box.corner_detail = 8
		_foot_box.anti_aliasing = true
	return _foot_box


## The outline of the tile as a polygon, clockwise from the top-left corner's
## arc. Used to mask the photograph, so a picture that runs to the edge of its
## square is cut by the same corner the plate under it has.
##
## `uvs` come back in the same order, in 0..1 over the *art* rect rather than
## over the tile, because that is the rect the texture is stretched across.
static func _rounded_points(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var centres := [
		rect.position + Vector2(r, r),
		rect.position + Vector2(rect.size.x - r, r),
		rect.end - Vector2(r, r),
		rect.position + Vector2(r, rect.size.y - r),
	]
	for corner in 4:
		var start := PI + float(corner) * PI * 0.5
		for step in 5:
			var angle := start + PI * 0.5 * float(step) / 4.0
			points.append(centres[corner] + Vector2(cos(angle), sin(angle)) * r)
	return points


## The photograph, at the brightness its state calls for. Returns false for a
## kind with no picture — the bolt, or a build whose tiles have not been
## imported — so `_draw` can fall through to the drawn glyph.
##
## Loaded on the first draw rather than in `_ready`, and held in a static cache,
## because four slots on the bar and three more in the lobby's weapon strip all
## want the same handful of textures and `ResourceLoader` is the only thing that
## should be deciding how many copies of a PNG exist.
func _draw_art() -> bool:
	var texture := _art()
	if texture == null:
		return false
	var shade := ART_READY
	if _count == 0 or _stowed:
		shade = ART_EMPTY
	elif not _lit:
		shade = ART_WAITING
	# Drawn through the tile's own corner rather than as a plain rect. Every
	# prop baked so far is framed clear of its corners, so today this masks
	# nothing; it is here because the plate under it *is* rounded, and the day a
	# tile is baked with a background — or with a shaft running to the edge —
	# the picture would hang out past the shape by 3 px on the diagonal and read
	# as a printing error.
	var rect := Rect2(Vector2(ART_INSET, ART_INSET),
		Vector2(SIZE, SIZE) - Vector2(ART_INSET, ART_INSET) * 2.0)
	var points := _rounded_points(rect, RADIUS - ART_INSET)
	var uvs := PackedVector2Array()
	for point in points:
		uvs.append((point - rect.position) / rect.size)
	draw_colored_polygon(points, Color(shade, shade, shade, 1.0), uvs, texture)
	return true


static var _art_cache: Dictionary = {}


static func _art_for(kind: Kind) -> Texture2D:
	if _art_cache.has(kind):
		return _art_cache[kind]
	var texture: Texture2D = null
	if TILE_ART.has(kind) and ResourceLoader.exists(TILE_ART[kind]):
		texture = load(TILE_ART[kind]) as Texture2D
	_art_cache[kind] = texture
	return texture


func _art() -> Texture2D:
	return _art_for(kind)


## The photograph for a weapon, for anything that shows a weapon and is not a
## slot — the lobby's picker strip. Public so the lobby does not have to know
## what a `Kind` is.
static func art_for_weapon(weapon: Variant) -> Texture2D:
	return _art_for(WEAPON_KIND.get(Loadout.sanitize(weapon), Kind.SPEAR))


## Three levels, not two, and the third is the one D-032 made an everyday sight:
## an empty slot. It is knocked back further than a slot merely waiting out its
## use-delay, because "you have none" and "not for another second" are different
## answers, and a player who cannot tell them apart keeps pressing the key.
func _tint() -> Color:
	if _count == 0:
		return UIPalette.faded(UIPalette.TEXT, 0.16)
	if _lit:
		return UIPalette.BOG
	return UIPalette.faded(UIPalette.TEXT, 0.34)


## Deliberately does *not* dim with the use-delay. How many you are carrying is
## a fact about your pack and it is the thing this slot exists to tell you; the
## photograph's brightness carries the delay instead. At zero the number dims with
## everything else, because there the count and the state are the same news.
func _draw_count() -> void:
	var colour := UIPalette.TEXT if _count > 0 \
		else UIPalette.faded(UIPalette.TEXT, 0.30)
	draw_string(get_theme_default_font(), Vector2(COUNT_LEFT, COUNT_BASELINE),
		str(_count), HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT_SIZE, colour)


## The recovered part of the recharge as a wedge of the tile, clockwise from
## twelve o'clock. Traced out to the tile's edge rather than drawn as a circle,
## so at nearly-full it fills the corners too instead of leaving four dark
## triangles that read as "not quite".
##
## "The tile's edge" is now the rounded one (D-118). It used to be the square,
## which is the same thing while the tile was a square and a 3 px spur of yellow
## sticking out of each corner the moment the tile was not.
func _draw_sweep(progress: float) -> void:
	if progress <= 0.0:
		return
	var half := SIZE * 0.5
	var c := Vector2(half, half)
	var points := PackedVector2Array([c])
	var steps := maxi(2, int(ceil(progress * 90.0)))
	for i in steps + 1:
		var angle := -PI * 0.5 + TAU * progress * float(i) / float(steps)
		var dir := Vector2(cos(angle), sin(angle))
		points.append(c + dir * _edge_distance(dir))
	draw_colored_polygon(points, UIPalette.faded(UIPalette.BOG, SWEEP_ALPHA))


## How far the tile's outline is from its centre along `dir` (a unit vector).
##
## Solved rather than sampled, because the sweep asks for up to ninety of these
## every frame of a recharge. Two cases: the ray leaves through a flat edge,
## which is the old `half / max(|x|, |y|)`; or it leaves through a corner arc,
## where the tile's outline is a circle of radius `RADIUS` centred `half -
## RADIUS` along both axes, and the distance is the positive root of
## `|t·dir - centre| = RADIUS`.
static func _edge_distance(dir: Vector2) -> float:
	var half := SIZE * 0.5
	var inner := half - RADIUS
	var ax := absf(dir.x)
	var ay := absf(dir.y)
	if ax > 0.0:
		var t := half / ax
		if t * ay <= inner:
			return t
	if ay > 0.0:
		var t := half / ay
		if t * ax <= inner:
			return t
	# `dir` is a unit vector, so the quadratic's leading coefficient is 1 and
	# the discriminant cannot go negative inside the corner wedge.
	var sum := ax + ay
	return inner * sum + sqrt(maxf(0.0,
		inner * inner * (sum * sum - 2.0) + RADIUS * RADIUS))


func _draw_timer() -> void:
	var font := get_theme_default_font()
	var text := recharge_text()
	var at := Vector2(0.0, TIMER_BASELINE)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, SIZE,
		TIMER_FONT_SIZE, TIMER_OUTLINE, Color(0.0, 0.0, 0.0, 1.0))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, SIZE,
		TIMER_FONT_SIZE, UIPalette.TEXT)


func _draw_glyph(tint: Color) -> void:
	var c := Vector2(SIZE, SIZE) * 0.5 - Vector2(0, 4)
	match kind:
		Kind.SPEAR:
			# A shaft on the diagonal with a head on the top end. Drawn on the
			# diagonal because a vertical line in a square reads as a divider.
			var tail := c + Vector2(-11, 12)
			var neck := c + Vector2(7, -6)
			var tip := c + Vector2(12, -13)
			draw_line(tail, neck, tint, 2.4)
			draw_colored_polygon(PackedVector2Array([
				tip, neck + Vector2(-4.5, -1.0), neck + Vector2(1.0, 4.5)]), tint)
		Kind.SHIELD:
			# A barricade of horizontal boards on two uprights, which is what
			# the prop is: five planks with daylight between them and a stile
			# down each edge. The dome-on-a-stalk that used to be drawn here
			# was a mushroom and stopped being true of anything the day the
			# model was swapped (D-079). Only ever seen if `shield.png` is
			# missing — the tile a player looks at is the photograph.
			for i in 5:
				var plank := -14.0 + float(i) * 6.0
				draw_rect(Rect2(c + Vector2(-14, plank), Vector2(28, 4.5)),
					tint, true)
			draw_rect(Rect2(c + Vector2(-12, -14), Vector2(3.5, 28)), tint, true)
			draw_rect(Rect2(c + Vector2(8.5, -14), Vector2(3.5, 28)), tint, true)
		Kind.MAGNET:
			# A starburst, which was drawn for the crystal and is left alone for
			# the magnet (D-078): both props are round things that pull, and
			# six lines out of a disc is the one shape that says so. Only ever
			# seen if `magnet.png` is missing — the tile a player looks at is
			# the photograph.
			draw_circle(c + Vector2(0, 2), 7.0, tint)
			for i in 6:
				var angle := TAU * float(i) / 6.0
				var dir := Vector2(cos(angle), sin(angle))
				draw_line(c + Vector2(0, 2) + dir * 8.0,
					c + Vector2(0, 2) + dir * 13.0, tint, 2.0)
		Kind.POTION:
			# A round-bottomed flask with a short neck and a stopper: two
			# straight sides down from the shoulders, a fan for the belly, and a
			# cap across the top. Drawn as an outline with a filled stopper
			# rather than as a solid, so it reads as *glass* beside three solid
			# glyphs — the one thing on this bar that is a container.
			var neck := 5.0
			var belly := PackedVector2Array([c + Vector2(-neck, -7)])
			for i in 17:
				var t := float(i) / 16.0
				var angle := PI * (1.0 - t)
				belly.append(c + Vector2(-cos(angle) * 11.0, sin(angle) * 10.0 + 1.0))
			belly.append(c + Vector2(neck, -7))
			draw_polyline(belly, tint, 2.0)
			draw_line(c + Vector2(-neck, -7), c + Vector2(-neck, -12), tint, 2.0)
			draw_line(c + Vector2(neck, -7), c + Vector2(neck, -12), tint, 2.0)
			draw_rect(Rect2(c + Vector2(-neck - 2, -16), Vector2(neck * 2 + 4, 4)),
				tint, true)
		Kind.BOW:
			# A limb bowing left with its string straight down the right, which
			# is the one silhouette a bow has that nothing else on this bar
			# could be. The arrow is left off deliberately: the tile says
			# whether the *weapon* is ready, and a drawn arrow on a dark tile
			# would be the tile claiming a nocked shot it does not have.
			var limb := PackedVector2Array()
			for i in 17:
				var t := float(i) / 16.0
				# Three-quarters of a circle's worth of arc, opening right, so
				# the tips turn back toward the string the way real limbs do.
				var angle := PI * (-0.42 + t * 0.84)
				limb.append(c + Vector2(cos(angle) * 15.0 - 5.0,
					sin(angle) * 15.0))
			draw_polyline(limb, tint, 2.4)
			draw_line(limb[0], limb[limb.size() - 1], tint, 1.6)
		Kind.SWORD:
			# On the diagonal for the spear's reason — a vertical line in a
			# square reads as a divider — and heavier than the spear's shaft,
			# because the one thing a great sword is beside a spear is *broad*.
			# Crossguard across the grip, a dot for the pommel, and the blade
			# runs past both of them to a point.
			var butt := c + Vector2(-11, 13)
			var grip := c + Vector2(-6, 8)
			var point := c + Vector2(13, -14)
			var along := (point - butt).normalized()
			var across := Vector2(-along.y, along.x)
			draw_line(butt, point - along * 4.0, tint, 4.0)
			draw_colored_polygon(PackedVector2Array([
				point, point - along * 6.0 + across * 3.4,
				point - along * 6.0 - across * 3.4]), tint)
			draw_line(grip + across * 7.0, grip - across * 7.0, tint, 2.4)
			draw_circle(butt, 2.6, tint)
		Kind.LIGHTNING:
			# The classic jagged bolt, as one filled polygon rather than a
			# polyline, so it keeps its weight at the same size the spear's
			# shaft has and does not thin out to a scribble. Six points: down
			# the left edge, across the waist, down to the tip, and back.
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(3, -14),
				c + Vector2(-9, 2),
				c + Vector2(-1, 2),
				c + Vector2(-4, 15),
				c + Vector2(9, -3),
				c + Vector2(1, -3)]), tint)
