class_name AbilitySlot
extends Control
## One square in the ability bar: what it is, which key fires it, and whether
## pressing that key right now will do anything (PLAN 6.1).
##
## The glyphs are drawn rather than imported. There is no icon set in this
## project and there is not going to be one for three shapes that are a spear, a
## mushroom and a lure — a stick with a point on it, a cap on a stem, and a ball
## with spikes are half a dozen `draw_` calls each, they stay crisp at any
## window size, and they tint with the slot's state for free.
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
## * `set_stock` — the mushroom, the lure and the heal potion. They are carried
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
## (D-069). The first slot on the bar is whichever weapon this Gub actually
## brought, the way it has always been the bolt for an Elder — so a bow player
## reads their own recharge off it instead of watching a spear tile that will
## never light.
enum Kind { SPEAR, MUSHROOM, LURE, LIGHTNING, POTION, BOW, SWORD }

const SIZE := 62.0
const RADIUS := 5.0

## Where the carried count sits: bottom-left, which is the one corner of the
## square that no glyph reaches into and that the key cap — bottom-right — does
## not want. Measured against all three shapes, whose leftmost extents at this
## height are the mushroom cap at x=16 and the lure's lower spikes at x=24.
const COUNT_FONT_SIZE := 22
const COUNT_LEFT := 6.0
const COUNT_BASELINE := 57.0

## The recharge readout. The number sits over the centre of the glyph, which is
## the one place on the square the eye already goes to, and is outlined because
## it is drawn over a glyph and a fill and has to read against both.
const TIMER_FONT_SIZE := 22
const TIMER_OUTLINE := 8
const TIMER_BASELINE := 35.0
## How much of the Gub's yellow the recovered part of the fill carries. Enough to
## see the wedge from the corner of the eye, little enough that the dark glyph
## under it still reads as "not yet".
const SWEEP_ALPHA := 0.26

@export var kind: Kind = Kind.SPEAR
## The input action this slot fires, used for the key cap.
@export var action: String = "throw_spear"
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

@onready var _cap: Label = %KeyCap
@onready var _name: Label = %Name


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)
	_cap.text = SettingsPanel.primary_key(action)
	_name.text = label_text


## Make this slot stand for something else.
##
## The key cap is left alone unless `next_action` says otherwise, and the two
## cases are the difference between the Elder and a loadout. An Elder's bolt is
## fired by **the same button the spear was**, which is the point of it replacing
## the spear rather than being a fourth thing to learn — so that call passes no
## action and the cap does not move. A bow and a great sword are fired by their
## own keys (`draw_bow`, `swing_sword`), so the tile that stands for one has to
## carry that key or it is telling a player to press the wrong thing (D-069).
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
## (`mushroom_use_delay`, `lure_use_delay`) and only dims the slot — it never
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

	draw_rect(box, Color(0.02, 0.027, 0.04, 0.62), true)
	# The border is the state at a glance from the corner of the eye; the count
	# is the detail you look at when you are deciding whether to spend one.
	draw_rect(box, UIPalette.faded(tint, 0.85 if _lit else 0.5), false, 1.5)
	if _total > 0.0:
		_draw_sweep(recharge_progress())
	_draw_glyph(tint)
	if _total > 0.0:
		_draw_timer()

	if _count >= 0:
		_draw_count()


## Three levels, not two, and the third is the one D-032 made an everyday sight:
## an empty slot. It is knocked back further than a slot merely waiting out its
## use-delay, because "you have none" and "not for another second" are different
## answers, and a player who cannot tell them apart keeps pressing the key.
func _tint() -> Color:
	if _count == 0:
		return UIPalette.faded(UIPalette.TEXT, 0.16)
	if _lit:
		return UIPalette.GUB
	return UIPalette.faded(UIPalette.TEXT, 0.34)


## Deliberately does *not* dim with the use-delay. How many you are carrying is
## a fact about your pack and it is the thing this slot exists to tell you; the
## border and the glyph carry the delay instead. At zero the number dims with
## everything else, because there the count and the state are the same news.
func _draw_count() -> void:
	var colour := UIPalette.TEXT if _count > 0 \
		else UIPalette.faded(UIPalette.TEXT, 0.30)
	draw_string(get_theme_default_font(), Vector2(COUNT_LEFT, COUNT_BASELINE),
		str(_count), HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT_SIZE, colour)


## The recovered part of the recharge as a wedge of the square, clockwise from
## twelve o'clock. Traced out to the square's edge rather than drawn as a circle,
## so at nearly-full it fills the corners too instead of leaving four dark
## triangles that read as "not quite".
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
		points.append(c + dir * (half / maxf(absf(dir.x), absf(dir.y))))
	draw_colored_polygon(points, UIPalette.faded(UIPalette.GUB, SWEEP_ALPHA))


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
		Kind.MUSHROOM:
			draw_rect(Rect2(c + Vector2(-3, -1), Vector2(6, 14)), tint, true)
			# The cap is a fan rather than a half-circle primitive so it can be
			# a shallow dome instead of a semicircle.
			var cap := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				var angle := PI + t * PI
				cap.append(c + Vector2(cos(angle) * 15.0, sin(angle) * 11.0 - 1.0))
			cap.append(c + Vector2(15, -1))
			draw_colored_polygon(cap, tint)
		Kind.LURE:
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
