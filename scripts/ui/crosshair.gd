class_name Crosshair
extends Control
## The reticle. Only the reticle (PLAN 3.4, 6.1).
##
## It used to answer "am I dangerous right now" as well: an amber ring closed
## around the ticks as the spear grew back. **That ring is gone, and it is the
## second version of it to be thrown away rather than a third to be fixed**
## (D-036). The recharge fraction it fed is gone with it, so nothing drawn here
## is tied to a timer in any form.
##
## The reason is the 0.71 s windup. A ring that measured only the recharge sat
## full through the windup and then dropped, which read as a stall; a ring that
## measured the whole cycle swept from the click, which read as a spear that was
## already gone. Both are honest about a different half of the throw and neither
## is honest about the throw, and the thing sitting under your aim is the worst
## place in the game to put a number that needs interpreting.
##
## The honest indicator already exists and is better: **the spear in the Bog's
## own hand.** `held_gear.gd` is driven straight off the same
## `BogCombat.has_spear()` the throw is gated on, which since D-035 covers the
## recharge and a letter hold in one expression. One truth, drawn where everyone
## — including the Bog facing you — can already see it.
##
## What is left is armed or not, and that is kept because it is not a timer and
## never was: it says whether there is a living Bog behind this crosshair at
## all. Alive, the ticks are the Bog's own yellow and the centre is a filled
## dot; dead or spectating, they go grey and the centre empties, because a
## crosshair with nothing behind it invites you to aim.
##
## Drawn rather than assembled from textures because every part of it is a
## rectangle or an arc, and because a crosshair that has to stay crisp at any
## window size is better off as vectors than as a sprite someone has to re-export.

## Distance from the centre to the inner end of each tick, and how long the
## ticks are. Kept small: the aim point is the gap, and a wide crosshair on an
## instant-kill weapon encourages people to aim with the wrong pixel.
const GAP := 6.0
const TICK := 8.0
const THICKNESS := 2.0
const DOT_RADIUS := 1.7

## The hitmarker: four short diagonals that snap in on a kill and fade. Purely
## visual — `MatchState` already plays the sound, and doubling it up would be
## two hitmarkers for one kill. Deliberately untouched by the removal above: a
## hitmarker is feedback for something that has already happened, not a gauge
## for something that has not.
const MARK_INNER := 9.0
const MARK_OUTER := 17.0
const MARK_FADE := 0.4

## Hidden entirely while dead or spectating. Set by the HUD.
var armed: bool = true

var _mark: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## Called by the HUD every frame. Repaints only when something changed, because
## this is a `_draw` on top of a running game — and with the ring gone that is
## now almost never, where it used to be every frame of every recharge.
func set_state(is_armed: bool) -> void:
	if is_armed == armed:
		return
	armed = is_armed
	queue_redraw()


## Flash the hitmarker. Called when this client's Bog gets a kill.
func strike() -> void:
	_mark = MARK_FADE
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_mark = maxf(0.0, _mark - delta)
	if _mark <= 0.0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var tint := UIPalette.BOG if armed else UIPalette.faded(UIPalette.TEXT, 0.5)

	# Four ticks. The vertical pair is drawn the same length as the horizontal
	# one; a "T" crosshair reads as broken rather than as deliberate at this size.
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(centre + direction * GAP, centre + direction * (GAP + TICK),
			tint, THICKNESS)

	if armed:
		draw_circle(centre, DOT_RADIUS, tint)

	if _mark > 0.0:
		var alpha := _mark / MARK_FADE
		var colour := UIPalette.faded(Color(1, 1, 1), alpha)
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_line(centre + corner * MARK_INNER, centre + corner * MARK_OUTER,
				colour, 2.0)
