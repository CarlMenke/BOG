class_name LetterTrack
extends Control
## G, U and B — the three you need, and the one you are standing still for
## (PLAN 6.1, D-033, D-035).
##
## Only ever on screen under the two letter conditions, LETTERS and CAPTURE. The HUD hides the whole
## control in every other mode, so nothing else about the bottom of the screen
## changes for a match that has no letters in it.
##
## **Three lamps and one countdown in one control, not two**, because they are
## one story: the card in your fist is the lamp you are in the middle of
## lighting, and drawing the hold *on that lamp* says which letter it is worth
## without naming it twice. Two separate widgets would each have to name the
## letter, and two names for one card can disagree — which is the whole reason
## `MatchState.letter_name` is a single static table the world card reads too.
##
## **The hold is the one timer left anywhere on this HUD, and that is
## deliberate** (D-036). It is not the recharge ring wearing a different hat: a
## hold is a single ten-second commitment rather than a rhythm you throw on,
## there is no windup for it to be misread against, and it is nowhere near your
## aim. A Gub that cannot throw for ten seconds with nothing on screen saying
## how much longer is a Gub whose player thinks the game has broken.
##
## Nobody else's hold appears here. The lit card in their fist is the tell and
## it is an in-world one on purpose — the announcement is meant to be made to
## the clearing, not to a corner of your screen.

## One lamp. Taller than wide so a single capital fills it rather than floating
## in it, and small enough that three of them plus the caption sit above the
## ability bar without crowding it.
const CELL := Vector2(38.0, 44.0)
const CELL_GAP := 10.0
const GLYPH_SIZE := 26

## The caption sits under the row, and the row is measured from the top, so this
## is the whole height of the control.
const CAPTION_TOP := 50.0
const CAPTION_SIZE := 15
const HEIGHT := 70.0

## The unlit lamp is knocked back hard. Two of these are the normal state for
## most of a match and a row of three near-equal boxes would make "which have I
## got" a thing you count rather than a thing you see.
const UNLIT_GLYPH := 0.24
const UNLIT_BORDER := 0.18
## The wash behind a letter you already own, so a won lamp reads as filled and
## not merely as brighter.
const LIT_WASH := 0.12

## The three-bit mask, straight from `MatchState.scoring_letters` — your own in
## a free-for-all, your team's pooled one in Teams (D-049).
var _letters: int = 0
## Whether `_letters` is a team's pooled mask. Said under the lamps, because a
## lamp lit by a letter you never touched reads as a bug unless it is labelled.
var _team: bool = false
## Which bit is being held up, or 0. Presence of a letter here is presence of a
## hold — `letter_hold_letter` is derived from the row's existence rather than
## from its clock, which is what stops a client whose countdown ran out a round
## trip early from showing a lamp the host has not lit (D-035).
var _hold_letter: int = 0
## How much of the hold is done, 0 → 1. The lamp fills with it.
var _hold_fill: float = 0.0
## Whole seconds still to stand there. Never 0 while a hold is running — see
## `set_state`.
var _hold_seconds: int = 0
## Capture G·U·B (D-051): the card up is a carry with no clock, so the lamp is
## full and the caption says where to take it rather than how long is left.
var _carrying: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(CELL.x * 3.0 + CELL_GAP * 2.0, HEIGHT)


## Everything this control draws, pushed by the HUD. `remaining` and `total` are
## seconds; `hold_letter` of 0 means no card is up and the other two are ignored.
##
## The seconds shown never reach zero while a hold is running. A client's copy
## of the clock can expire a round trip before the host's does, and "0" sitting
## over a Gub that still cannot throw reads as the game having stopped
## responding — where "1" reads as the last moment of a wait, which is what it
## is. `ceili` gives that for free everywhere except the exact end, and `maxi`
## covers the end.
func set_state(letters: int, hold_letter: int, remaining: float, total: float,
		team: bool = false, carrying: bool = false) -> void:
	var fill := 0.0
	var seconds := 0
	if hold_letter != 0 and carrying:
		fill = 1.0
	elif hold_letter != 0:
		fill = clampf(1.0 - remaining / maxf(0.01, total), 0.0, 1.0)
		seconds = maxi(1, ceili(remaining))
	if letters == _letters and hold_letter == _hold_letter and team == _team \
			and carrying == _carrying \
			and seconds == _hold_seconds and is_equal_approx(fill, _hold_fill):
		return
	_letters = letters
	_team = team
	_carrying = carrying
	_hold_letter = hold_letter
	_hold_fill = fill
	_hold_seconds = seconds
	queue_redraw()


func _draw() -> void:
	var row := CELL.x * 3.0 + CELL_GAP * 2.0
	var left := (size.x - row) * 0.5
	var index := 0
	for bit: int in MatchState.LETTERS:
		_draw_lamp(Rect2(Vector2(left + index * (CELL.x + CELL_GAP), 0.0), CELL), bit)
		index += 1
	if _hold_letter != 0:
		_draw_caption()
	elif _team:
		_draw_team_caption()


## One lamp, in whichever of its three states it is in. The hold is tested
## before the mask on purpose: the two cannot both be true today — a card for a
## letter you already hold is consumed on touch and never starts a hold (D-033)
## — and if that ever changes, the live thing is the one worth drawing.
func _draw_lamp(rect: Rect2, bit: int) -> void:
	draw_rect(rect, Color(0.02, 0.027, 0.04, 0.62), true)

	var tint := UIPalette.faded(UIPalette.TEXT, UNLIT_GLYPH)
	var border := UIPalette.faded(UIPalette.TEXT, UNLIT_BORDER)
	if bit == _hold_letter:
		# Filling from the bottom, which is the direction a thing being *earned*
		# fills — the opposite of a cooldown wedge draining from twelve o'clock,
		# and the difference is the point. Nothing on this HUD drains any more.
		var risen := rect.size.y * _hold_fill
		draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y - risen),
			Vector2(rect.size.x, risen)), UIPalette.faded(UIPalette.AMBER, 0.30), true)
		tint = UIPalette.AMBER
		border = UIPalette.faded(UIPalette.AMBER, 0.85)
	elif _letters & bit != 0:
		draw_rect(rect, UIPalette.faded(UIPalette.GUB, LIT_WASH), true)
		tint = UIPalette.GUB
		border = UIPalette.faded(UIPalette.GUB, 0.85)
	draw_rect(rect, border, false, 1.5)

	# `MatchState.letter_name` rather than a table of our own, so the lamp and
	# the card lying in the grass can never disagree about which bit is which.
	var glyph := MatchState.letter_name(bit)
	var font := get_theme_default_font()
	var width := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, GLYPH_SIZE).x
	draw_string(font, rect.position + Vector2((rect.size.x - width) * 0.5,
		rect.size.y * 0.5 + GLYPH_SIZE * 0.38), glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1, GLYPH_SIZE, tint)


## The exact number of seconds, under a bar that is only approximate. Both, and
## not one or the other: the bar is what you catch without looking and the
## number is what you need when you are deciding whether to run for cover.
func _draw_caption() -> void:
	var text := "HOLDING %s  ·  %d s" % [MatchState.letter_name(_hold_letter), _hold_seconds]
	if _carrying:
		text = "CARRYING %s  ·  TO YOUR BASE" % MatchState.letter_name(_hold_letter)
	var font := get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x
	draw_string(font, Vector2((size.x - width) * 0.5, CAPTION_TOP + CAPTION_SIZE),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, UIPalette.AMBER)


## "TEAM LETTERS" under the lamps in Teams, when no hold is using the caption
## line. The hold's own caption wins that line: while you are holding, the card
## in your fist is the thing to read, and the lamps have not changed meaning.
func _draw_team_caption() -> void:
	var text := "TEAM LETTERS"
	var font := get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x
	draw_string(font, Vector2((size.x - width) * 0.5, CAPTION_TOP + CAPTION_SIZE),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, UIPalette.TEXT_DIM)
