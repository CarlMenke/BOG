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

## The hitmarker: four short diagonals that snap in on a landed hit and fade.
## Purely visual — `MatchState` already plays the sound, and doubling it up
## would be two hitmarkers for one hit. Deliberately untouched by the removal
## above: a hitmarker is feedback for something that has already happened, not a
## gauge for something that has not.
##
## **Made to land rather than made louder** (D-122). The first version was two
## pixels wide, fading from the frame it appeared in, and in a fight it was
## simply not seen. What was missing was never size or brightness: it was an
## *arrival*. So the arms are three pixels, and the mark lands 40% oversize and
## pulls to its true size over `MARK_SNAP`, at full alpha, before any of it
## fades. Seventy milliseconds is two frames at 30 fps and ten at 144, which is
## long enough to be a movement at any frame rate and short enough that nobody
## can say what it did — the eye reports a snap, which is the point.
const MARK_INNER := 9.0
const MARK_OUTER := 17.0
const MARK_THICKNESS := 3.0
const MARK_FADE := 0.45
const MARK_SNAP := 0.07
const MARK_SNAP_SCALE := 1.4

## Hidden entirely while dead or spectating. Set by the HUD.
var armed: bool = true

var _mark: float = 0.0
## What the last `strike` asked for. Held rather than passed to `_draw`, which
## takes no arguments, and reset by nothing: a finished mark is invisible, so a
## stale tint cannot be seen.
var _mark_tint: Color = Color(1, 1, 1)
var _mark_life: float = MARK_FADE
## Whether the last `strike` was a kill, which is the only thing that changes
## the *shape*: the arms start at the centre instead of outside the gap.
var _mark_kill: bool = false


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


## Flash the hitmarker.
##
## **Now called on every landed hit, not only on a kill** (D-116). The sound has
## fired on every hit since D-062 — the victim may be sixty metres away and
## behind a tree, still standing, and without it the only difference between a
## hit and a miss is a bar four pixels tall — and the picture was the half that
## never caught up. A hitmarker that fires in your ears and not in your eyes was
## an omission rather than a design.
##
## The tint is what says *which*: the Bog's own yellow for a hit somebody walked
## away from, white for one they did not, amber for one of the practice range's
## boards. A range board and a hit on a Bog are the same shape, because they are
## the same event with a different victim.
##
## A **kill is the one thing that changes the shape** (D-122), because it is the
## one thing that is not just another hit: the four arms reach in through the
## centre gap and meet, so the mark is a whole X rather than four corners of
## one, and it is held 0.6 s rather than 0.45. Colour alone had to carry that
## before, and colour alone is what a player looking at a Bog in front of a
## sunset is least able to read. `kill` is a flag rather than a second function
## so the one call site that is neither — `flash_hit`, for the range's boards —
## keeps working by saying nothing.
func strike(tint: Color = Color(1, 1, 1), life: float = MARK_FADE,
		kill: bool = false) -> void:
	_mark_tint = tint
	_mark_life = maxf(life, 0.01)
	_mark_kill = kill
	_mark = _mark_life
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
		# Two animations, one after the other rather than mixed: the mark snaps
		# to size at full alpha, and only then starts to go. Running the fade
		# over the whole life instead would have the mark already dimming while
		# it is still arriving, which is exactly how the first version managed
		# to be invisible.
		var elapsed := _mark_life - _mark
		var burst := lerpf(MARK_SNAP_SCALE, 1.0,
			clampf(elapsed / MARK_SNAP, 0.0, 1.0))
		var alpha := minf(1.0, _mark / maxf(_mark_life - MARK_SNAP, 0.01))
		var colour := UIPalette.faded(_mark_tint, alpha)
		# A kill's arms start at the centre, so the four of them draw one X
		# across the aim point; a hit's stand off it and leave the gap clear.
		var inner := (0.0 if _mark_kill else MARK_INNER) * burst
		var outer := MARK_OUTER * burst
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_line(centre + corner * inner, centre + corner * outer,
				colour, MARK_THICKNESS)
