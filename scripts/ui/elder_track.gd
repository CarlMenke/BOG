class_name ElderTrack
extends Control
## How much of the Elder is left (D-040).
##
## Twenty seconds of not being able to die, with nothing on screen saying how
## many are left, is exactly the problem the letter hold had and it gets exactly
## the same answer: a bar and a number, for the local player only, nowhere near
## the crosshair.
##
## **Nowhere near the crosshair is a rule, not a layout preference** (D-036).
## The recharge ring around the reticle was deleted rather than fixed a third
## time, and a countdown put back in its place would be that decision reversed
## by the next feature that happened to need a timer. This sits in the same
## column the letter track does, under the same argument: the middle of the
## screen is for aiming.
##
## **Only its wearer sees it.** Everybody else already has the robe, which is a
## purple wizard in the middle of a clearing and is deliberately in-world
## (D-038). What other players are not given is the *clock* — "he has four
## seconds left" is a thing to be judged from how long the robe has been on
## screen, not read off a HUD, and handing it out would make hiding from an
## Elder a matter of arithmetic rather than nerve.
##
## It **drains**, which is the opposite of what the letter hold's lamp does and
## is the point. D-036's "nothing on this HUD drains any more" was about
## cooldowns: a ring that empties while you wait to be allowed to act again,
## which is a worse way of saying "not yet". This is a thing you have and are
## losing, and a bar that filled up as it ran out would be describing the wrong
## event.

## The bar. Wide enough to make one second out of twenty a visible step (11 px
## at the default duration) and short enough to sit above three ability tiles
## without becoming the thing you look at.
const BAR := Vector2(224.0, 10.0)
const CAPTION_SIZE := 15
const CAPTION_GAP := 5.0
const HEIGHT := 32.0

## The robe's violet, which is what the player is actually wearing and what the
## ward flash uses. It is the one element on this HUD that is not amber, gold or
## white, and that is deliberate: the Elder is the one state in this game that
## is not an ordinary Gub, and the bar saying so without being read is worth
## more than palette consistency.
const ROBE := Color(0.72, 0.52, 1.00)

## Under this many seconds the bar and the number go amber, the same warning the
## match clock gives in its last thirty. The last three seconds of invincibility
## are the ones worth being told about — that is the window in which "push on"
## becomes "get behind something".
const WARNING := 3.0

## Seconds still on the robe. Never 0 while it is on — see `set_state`, and see
## `LetterTrack` for the same rule and the same reason.
var _seconds: int = 0
## How much is left, 1 -> 0. The bar drains with it.
var _fraction: float = 0.0
var _worn: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(BAR.x, HEIGHT)


## Everything this control draws, pushed by the HUD. `worn` false means there is
## no robe and the other two are ignored.
##
## The seconds shown never reach zero while the robe is on, for the reason
## `LetterTrack.set_state` spells out: a client's copy of the clock can expire a
## round trip before the host's does, and a "0" over a Gub that is still
## visibly the Elder reads as the HUD having stopped rather than as the last
## moment of a countdown.
func set_state(worn: bool, remaining: float, total: float) -> void:
	var fraction := 0.0
	var seconds := 0
	if worn:
		fraction = clampf(remaining / maxf(0.01, total), 0.0, 1.0)
		seconds = maxi(1, ceili(remaining))
	if worn == _worn and seconds == _seconds and is_equal_approx(fraction, _fraction):
		return
	_worn = worn
	_seconds = seconds
	_fraction = fraction
	queue_redraw()


func _draw() -> void:
	if not _worn:
		return
	var tint := UIPalette.AMBER if _seconds <= WARNING else ROBE
	var left := (size.x - BAR.x) * 0.5

	var text := "ELDER  ·  %d s" % _seconds
	var font := get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		CAPTION_SIZE).x
	draw_string(font, Vector2((size.x - width) * 0.5, CAPTION_SIZE), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, tint)

	# Drawn as a full trough with the remainder on top, rather than as a bar
	# that shrinks: the trough is what makes a quarter of a bar read as a
	# quarter rather than as a short bar.
	var trough := Rect2(Vector2(left, CAPTION_SIZE + CAPTION_GAP), BAR)
	draw_rect(trough, Color(0.02, 0.027, 0.04, 0.62), true)
	draw_rect(Rect2(trough.position, Vector2(BAR.x * _fraction, BAR.y)),
		UIPalette.faded(tint, 0.85), true)
	draw_rect(trough, UIPalette.faded(tint, 0.55), false, 1.5)
