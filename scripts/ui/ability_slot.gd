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
## **Nothing here sweeps or counts down any more.** A slot used to eat a wedge
## out of itself and print the seconds left; both are gone for the reason the
## crosshair's ring is (D-036). What replaced them is two shapes, and a slot is
## whichever one its caller talks to it in:
##
## * `set_armed` — the spear. Lit or dark and nothing else, because
##   `GubCombat.has_spear()` is one expression covering both the recharge and a
##   letter hold (D-035), and there is nothing in it worth timing against.
## * `set_stock` — the mushroom and the lure. They are carried stock now
##   (D-032), so the count is the readout, and an empty slot is the ordinary
##   state at the start of every life rather than a fault to be alarmed by.
##
## **The first slot changes what it is.** An Elder has no spear — it throws
## lightning instead (D-038) — so the same tile swaps its glyph and its label
## and goes on being binary lit/dark off `has_lightning()`. That decision is the
## whole of D-036 applied to a second weapon: the readiness of the thing in your
## hand is one boolean, and a bar that started drawing a second kind of timer
## for the Elder would be re-importing exactly what that entry deleted.

enum Kind { SPEAR, MUSHROOM, LURE, LIGHTNING }

const SIZE := 62.0
const RADIUS := 5.0

## Where the carried count sits: bottom-left, which is the one corner of the
## square that no glyph reaches into and that the key cap — bottom-right — does
## not want. Measured against all three shapes, whose leftmost extents at this
## height are the mushroom cap at x=16 and the lure's lower spikes at x=24.
const COUNT_FONT_SIZE := 22
const COUNT_LEFT := 6.0
const COUNT_BASELINE := 57.0

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

@onready var _cap: Label = %KeyCap
@onready var _name: Label = %Name


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)
	_cap.text = SettingsPanel.primary_key(action)
	_name.text = label_text


## Make this slot stand for something else. The key cap is deliberately left
## alone: it is read out of the input map for whichever action this slot fires,
## and the Elder's bolt is fired by the same button the spear was — which is the
## point of it replacing the spear rather than being a fourth thing to learn.
func set_kind(next: Kind, next_label: String) -> void:
	if kind == next:
		return
	kind = next
	label_text = next_label
	_name.text = next_label
	queue_redraw()


## The spear: armed or not. No denominator, because nothing is being divided.
func set_armed(is_armed: bool) -> void:
	_apply(-1, is_armed)


## Carried stock. `busy` is the short floor between two placements
## (`mushroom_use_delay`, `lure_use_delay`) and only dims the slot — it never
## draws a number, because it is a cap on how fast a stack can be emptied and
## not a resource anybody plans a fight around.
func set_stock(count: int, busy: bool) -> void:
	_apply(maxi(0, count), count > 0 and not busy)


## Called by the HUD every frame, so it repaints only when something actually
## changed. Both inputs are discrete now, which means that is genuinely rare
## rather than "every frame the number moved a hundredth".
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
	_draw_glyph(tint)

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
