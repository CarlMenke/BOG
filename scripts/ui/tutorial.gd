class_name Tutorial
extends CanvasLayer
## HOW TO PLAY: six cards that teach B·O·G in about forty seconds (the letters
## round).
##
## The owner asked for *"a quick click through with animations"*, and the
## animation is the whole of the argument. B·O·G has four rules that are all
## about **motion** — a letter falls out of a corpse, a line bends round a wall
## toward it, a card sinks into a pouch over ten seconds, a colour tells you
## whether to chase or to cover — and every one of them is a sentence you have
## to read twice and a picture you understand once. So each card is a loop of
## three or four seconds drawn from primitives, and the words under it are a
## caption on something already happening rather than the thing itself.
##
## **Drawn, not authored.** Six little scenes of dots, glyphs and dashed lines
## would be six scene files, six sets of AnimationPlayers and six places for the
## gold to drift away from `Pickup.LETTER_COLOUR`. They are instead one `_draw`
## driven by one clock, reading the same `UIPalette` the HUD does — so the gold
## in card 1 is the gold on the ground, the red and blue in card 4 are the guide
## line's own, and the circle in card 5 is the minimap's geometry rather than a
## drawing of it.
##
## **Once per machine, and always available.** `maybe_auto_open` shows it the
## first time somebody sits in a lobby set to B·O·G and never again (`Settings`
## keeps the flag, which is the same place the name and the last weapon live);
## HOW TO PLAY on the main menu is how anybody asks for it back. Closing is what
## marks it seen, so a player who Escapes out of it on card one is not shown it
## again — they have decided, and a tutorial that reappears is a tutorial people
## learn to dismiss without reading.
##
## Self-contained on its own `CanvasLayer` at 20, above the HUD's 8 and the
## capture sheet's 10 and below `SceneFlow`'s fade at 128, so the menu and the
## lobby can each instance it by path and call `open()` without knowing a thing
## about what is underneath.

signal closed()

## Named, like every other cursor hold, so closing this inside the lobby does
## not hand the mouse back to a screen that still wants it.
const CURSOR_REASON := "tutorial"

## The six. `loop` is how long one figure takes to say what it has to say and
## start again; the text is the caption, and the drawing is the lesson.
##
## One string literal per body rather than a wrapped concatenation, and the long
## lines are the price: a `const` has to be a constant expression, and a table
## the whole feature is indexed by is the wrong place to find out how far this
## engine's constant folding goes.
const CARDS: Array[Dictionary] = [
	{
		"title": "A LETTER FALLS",
		"loop": 3.4,
		"body": "Every death drops the next letter — B, then O, then G. Only one is ever out at a time.",
	},
	{
		"title": "FOLLOW THE LINE",
		"loop": 4.0,
		"body": "A dashed line shows the fastest way there, jumps and all. Gold: nobody has it — go take it.",
	},
	{
		"title": "CAPTURE IT",
		"loop": 4.2,
		"body": "Walk into the letter to start capturing. You're unarmed for the whole capture; the letter sinks into your pouch, and when it lands it's yours.",
	},
	{
		"title": "RED AND BLUE",
		"loop": 4.4,
		"body": "Red: an enemy has it — kill them and it drops. Blue: a teammate has it — go cover them.",
	},
	{
		"title": "THE MINIMAP",
		"loop": 6.0,
		"body": "Top right: you, your team, loose letters, and only the enemies who carry one.",
	},
	{
		"title": "SPELL IT",
		"loop": 4.0,
		"body": "Hold all three and you win. In Teams the letters live at your base: carry each one home to your vault, and guard it — the other team can steal it back.",
	},
]

## Dash geometry for every dashed line in here, and the speed they scroll at.
## The same 1.2 m dash with a 0.5 duty the guide line's shader uses, read at the
## figure's own scale: about twenty pixels to the metre, so a dash is 24 px.
const DASH := 24.0
const DASH_GAP := 24.0
const DASH_SPEED := 46.0
const DASH_WIDTH := 3.0
## The dashed walker's two safeties (see `_dashed`): the smallest advance a
## step may make, in pixels, and the most steps one segment may take — a 700 px
## figure at a 48 px period needs about thirty.
const MIN_DASH_STEP := 0.25
const MAX_DASH_STEPS := 512

## A Bog in these figures. Big enough to carry an arm and a pouch on card 3.
const BOG_DOT := 11.0
## The pouch's wool, lifted out of `PouchMesh`'s own colour. The 3D sack is
## `(0.45, 0.36, 0.27)` under arena light; flat on a near-black card that is a
## brown nobody can find, so the figure uses the colour the material *reads* as
## rather than the number it is made of.
const POUCH_WOOL := Color(0.58, 0.47, 0.35)
const POUCH_CORD := Color(0.72, 0.62, 0.44)

## The pip strip under the figure.
const PIP_RADIUS := 4.0
const PIP_GAP := 16.0

@onready var _scrim: ColorRect = %Scrim
@onready var _title: Label = %Title
@onready var _figure: Control = %Figure
@onready var _body: Label = %Body
@onready var _pips: Control = %Pips
@onready var _back: Button = %BackButton
@onready var _next: Button = %NextButton

## Which card is up, 0-based.
var _card: int = 0
## Seconds since this card was opened. Reset on every step, so a figure always
## starts at the beginning of its loop rather than half way through the last
## card's.
var _clock: float = 0.0


func _ready() -> void:
	layer = 20
	visible = false
	set_process(false)
	set_process_unhandled_input(false)
	# The scrim is lighter than `ScrimPanel`'s 0.86 on purpose: this is a
	# tutorial about a game, and the game — the fire, the lobby, the Bogs — is
	# the thing it is teaching you to look at. 0.6 keeps it legible behind.
	_scrim.color = UIPalette.at(UIPalette.VOID, 0.6)
	_body.add_theme_font_size_override("font_size", UIPalette.FONT_BODY)
	_figure.draw.connect(_draw_figure)
	_pips.draw.connect(_draw_pips)
	_back.pressed.connect(_step.bind(-1))
	_next.pressed.connect(_on_next)
	_apply_card()


## Show the cards. `card` is for `tools/hud_range.gd`, which photographs one of
## them and cannot press NEXT twice to get there.
func open(card: int = 0) -> void:
	_card = clampi(card, 0, CARDS.size() - 1)
	_clock = 0.0
	_apply_card()
	visible = true
	set_process(true)
	set_process_unhandled_input(true)
	SceneFlow.release_cursor(CURSOR_REASON)
	_next.grab_focus()


## Closing is what marks it read — see the class note. Safe to call on a panel
## that is already shut, because Escape reaches more than one thing.
func close() -> void:
	if not visible:
		return
	visible = false
	set_process(false)
	set_process_unhandled_input(false)
	Settings.set_value("tutorial_seen", true)
	SceneFlow.recapture_cursor(CURSOR_REASON)
	closed.emit()


## Open once per machine, ever. The lobby calls this when it opens on a B·O·G
## config and again if the config becomes one; both are the same first time.
func maybe_auto_open() -> void:
	if bool(Settings.get_value("tutorial_seen")):
		return
	open()


## Where the six figures get their time from. One clock for the whole panel
## rather than one per card: only the visible card draws, and a figure that had
## been running invisibly for a minute would open mid-gesture.
func _process(delta: float) -> void:
	_clock += delta
	_figure.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


# ------------------------------------------------------------------- cards ---

func _on_next() -> void:
	if _card >= CARDS.size() - 1:
		close()
		return
	_step(1)


func _step(by: int) -> void:
	var wanted := clampi(_card + by, 0, CARDS.size() - 1)
	if wanted == _card:
		return
	_card = wanted
	_clock = 0.0
	_apply_card()


func _apply_card() -> void:
	var card: Dictionary = CARDS[_card]
	_title.text = "%d · %s" % [_card + 1, card["title"]]
	_body.text = String(card["body"])
	_back.disabled = _card == 0
	# The last card's button says DONE rather than NEXT, because a NEXT with
	# nothing after it is the one place a click-through can feel broken.
	_next.text = "DONE" if _card == CARDS.size() - 1 else "NEXT"
	_figure.queue_redraw()
	_pips.queue_redraw()


func _draw_pips() -> void:
	var width := CARDS.size() * PIP_RADIUS * 2.0 + (CARDS.size() - 1) * PIP_GAP
	var left := (_pips.size.x - width) * 0.5 + PIP_RADIUS
	var middle := _pips.size.y * 0.5
	for i in CARDS.size():
		var at := Vector2(left + i * (PIP_RADIUS * 2.0 + PIP_GAP), middle)
		if i == _card:
			_pips.draw_circle(at, PIP_RADIUS, UIPalette.AMBER)
		else:
			_pips.draw_circle(at, PIP_RADIUS - 1.0,
				UIPalette.faded(UIPalette.TEXT, 0.22))


# ----------------------------------------------------------------- figures ---

func _draw_figure() -> void:
	var size := _figure.size
	_figure.draw_rect(Rect2(Vector2.ZERO, size), UIPalette.RAISED, true)
	var loop := float(CARDS[_card]["loop"])
	var u := fmod(_clock, loop)
	match _card:
		0:
			_figure_letter_falls(size, u)
		1:
			_figure_follow_line(size, u)
		2:
			_figure_capture(size, u)
		3:
			_figure_red_and_blue(size, u, loop)
		4:
			_figure_minimap(size, u, loop)
		_:
			_figure_spell_it(size, u)


## **1 — a letter falls.** A Bog goes down, and the next letter of the cycle
## comes up out of it. Which letter it is advances every loop, so the picture
## says "B, then O, then G" without anybody reading the caption.
func _figure_letter_falls(size: Vector2, u: float) -> void:
	var ground := size.y * 0.76
	_figure.draw_line(Vector2(size.x * 0.12, ground), Vector2(size.x * 0.88, ground),
		UIPalette.LINE, 1.5, true)

	var which := int(_clock / float(CARDS[0]["loop"])) % MatchState.LETTERS.size()
	_cycle_strip(Vector2(size.x * 0.12, size.y * 0.22), which)

	# The fall: the dot squashes onto the floor and dims, which is the whole of
	# a death at this scale — a corpse is a Bog that has stopped being upright.
	var fall := _ease_out(clampf((u - 0.35) / 0.45, 0.0, 1.0))
	var body := Vector2(size.x * 0.46, ground - BOG_DOT - 2.0 + fall * 8.0)
	_figure.draw_set_transform(body, 0.0, Vector2(1.0 + fall * 0.55, 1.0 - fall * 0.55))
	_figure.draw_circle(Vector2.ZERO, BOG_DOT,
		UIPalette.faded(UIPalette.TEXT, 1.0 - fall * 0.55))
	_figure.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var rise := _ease_out(clampf((u - 0.75) / 0.55, 0.0, 1.0))
	if rise <= 0.0:
		return
	var bob := sin((u - 0.75) * 3.4) * 3.0 * rise
	var at := Vector2(size.x * 0.46, ground - 22.0 - rise * 56.0 + bob)
	_glyph(at, MatchState.letter_name(MatchState.LETTERS[which]),
		UIPalette.faded(UIPalette.GUIDE_LOOSE, rise), 42)


## B → O → G, with the one that is out now in gold. Small, in the corner of the
## figure, because it is the rule and the falling Bog is the example.
func _cycle_strip(at: Vector2, which: int) -> void:
	var step := 26.0
	for i in MatchState.LETTERS.size():
		var tint := UIPalette.GUIDE_LOOSE if i == which \
			else UIPalette.faded(UIPalette.TEXT, 0.22)
		_glyph(at + Vector2(i * step, 0.0),
			MatchState.letter_name(MatchState.LETTERS[i]), tint, 18)
		if i < MatchState.LETTERS.size() - 1:
			_figure.draw_line(at + Vector2(i * step + 9.0, -4.0),
				at + Vector2(i * step + 17.0, -4.0),
				UIPalette.faded(UIPalette.TEXT, 0.22), 1.0, true)


## **2 — follow the line.** The one thing a straight arrow could not say: the
## line goes *round* things, because it is a path and not a bearing.
func _figure_follow_line(size: Vector2, _u: float) -> void:
	var you := Vector2(size.x * 0.14, size.y * 0.74)
	var target := Vector2(size.x * 0.86, size.y * 0.34)
	var block := Rect2(Vector2(size.x * 0.44, size.y * 0.40),
		Vector2(size.x * 0.13, size.y * 0.42))
	_figure.draw_rect(block, UIPalette.RAISED_STRONG, true)
	_figure.draw_rect(block, UIPalette.LINE, false, 1.0)

	var path := PackedVector2Array([
		you,
		Vector2(block.position.x - 20.0, you.y),
		Vector2(block.position.x - 20.0, block.position.y - 20.0),
		Vector2(block.end.x + 20.0, block.position.y - 20.0),
		target + Vector2(-14.0, 6.0),
	])
	_dashed(path, UIPalette.GUIDE_LOOSE, _clock * DASH_SPEED)

	_figure.draw_circle(you, BOG_DOT, UIPalette.TEXT)
	_caption(you + Vector2(0.0, BOG_DOT + 16.0), "YOU")
	_glyph(target, "B", UIPalette.GUIDE_LOOSE, 36)


## **3 — capture it.** The performance Group C built, flattened: the right arm
## up, the card coming down out of it, the pouch on the left hip, and the HUD
## lamp beside filling from the bottom with the same fraction — so the thing in
## the world and the thing in the corner of the screen are taught as one event
## rather than as two.
func _figure_capture(size: Vector2, u: float) -> void:
	var span := 3.0
	var f := clampf(u / span, 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, f)
	var body := Vector2(size.x * 0.40, size.y * 0.62)
	var hand := body + Vector2(28.0, -46.0)
	var pouch := body + Vector2(-26.0, 10.0)

	_figure.draw_line(body + Vector2(6.0, -6.0), hand, UIPalette.TEXT, 3.0, true)
	_figure.draw_circle(body, BOG_DOT, UIPalette.TEXT)
	_figure.draw_line(body + Vector2(-6.0, -4.0), pouch + Vector2(2.0, -4.0),
		UIPalette.TEXT, 3.0, true)
	_pouch(pouch)

	var from := hand + Vector2(0.0, -30.0)
	var to := pouch + Vector2(0.0, -2.0)
	var at := from.lerp(to, eased) + Vector2(0.0, sin(u * 2.6) * 4.0 * (1.0 - f))
	_glyph(at, "O", UIPalette.GUIDE_LOOSE, int(roundf(lerpf(44.0, 14.0, eased))))

	# The lamp, drawn at `LetterTrack`'s own proportions and filling from the
	# bottom for `LetterTrack`'s own reason: a thing you are earning fills, and
	# nothing on this HUD drains any more (D-036).
	var cell := Rect2(Vector2(size.x * 0.76, size.y * 0.32), Vector2(48.0, 56.0))
	_figure.draw_rect(cell, Color(0.02, 0.027, 0.04, 0.62), true)
	var risen := cell.size.y * f
	_figure.draw_rect(Rect2(cell.position + Vector2(0.0, cell.size.y - risen),
		Vector2(cell.size.x, risen)), UIPalette.faded(UIPalette.AMBER, 0.30), true)
	_figure.draw_rect(cell, UIPalette.faded(UIPalette.AMBER, 0.85), false, 1.5)
	_glyph(cell.get_center(), "O", UIPalette.AMBER, 26)
	# Never zero while the clock is running, which is `LetterTrack`'s own rule:
	# a "0" over a Bog that still cannot throw reads as the game having stopped.
	var caption := "YOURS"
	if f < 1.0:
		caption = "%d s" % maxi(1, ceili(span - u))
	_caption(Vector2(cell.get_center().x, cell.end.y + 20.0), caption)

	if f < 1.0:
		return
	_burst(to, 1.0 - clampf((u - span) / 0.8, 0.0, 1.0))


## **4 — red and blue.** Two lines, one at a time, crossfading on a cosine so
## the loop has no seam. Both targets stay drawn: what changes is which one the
## line is going to, because the lesson is the colour and not the geometry.
func _figure_red_and_blue(size: Vector2, u: float, loop: float) -> void:
	var you := Vector2(size.x * 0.14, size.y * 0.52)
	var enemy := Vector2(size.x * 0.82, size.y * 0.28)
	var mate := Vector2(size.x * 0.82, size.y * 0.78)
	# 0 at the start and end of the loop, 1 in the middle, and flat at both ends
	# so each colour is up long enough to be read.
	var blend := smoothstep(0.25, 0.75, 0.5 - 0.5 * cos(TAU * u / loop))

	var phase := _clock * DASH_SPEED
	_dashed(PackedVector2Array([you, Vector2(size.x * 0.48, size.y * 0.34), enemy]),
		UIPalette.faded(UIPalette.GUIDE_ENEMY, 1.0 - blend), phase)
	_dashed(PackedVector2Array([you, Vector2(size.x * 0.48, size.y * 0.70), mate]),
		UIPalette.faded(UIPalette.GUIDE_ALLY, blend), phase)

	_figure.draw_circle(you, BOG_DOT, UIPalette.TEXT)
	_caption(you + Vector2(0.0, BOG_DOT + 16.0), "YOU")
	_carrier(enemy, "O", UIPalette.GUIDE_ENEMY, "ENEMY")
	_carrier(mate, "O", UIPalette.GUIDE_ALLY, "TEAMMATE")


## A blip holding a card: the dot, the glyph beside it, and what it is.
func _carrier(at: Vector2, glyph: String, colour: Color, label: String) -> void:
	_figure.draw_circle(at, BOG_DOT, colour)
	_glyph(at + Vector2(BOG_DOT + 13.0, 0.0), glyph, colour, 24)
	_caption(at + Vector2(0.0, BOG_DOT + 16.0), label)


## **5 — the minimap.** The corner of the screen, at four times the size and
## drawn from the same numbers `Minimap` draws it from, so a player finds the
## thing they were shown rather than a diagram of it.
func _figure_minimap(size: Vector2, u: float, loop: float) -> void:
	var centre := Vector2(size.x * 0.5, size.y * 0.5)
	var radius := minf(size.y * 0.44, size.x * 0.24)
	_figure.draw_circle(centre, radius, UIPalette.PANEL)
	_figure.draw_arc(centre, radius - 1.0, 0.0, TAU, 48, UIPalette.LINE_STRONG, 2.0, true)
	_figure.draw_line(centre + Vector2(0.0, -radius + 2.0),
		centre + Vector2(0.0, -radius + 11.0), UIPalette.LINE_STRONG, 2.0, true)
	_caption(centre + Vector2(0.0, -radius + 26.0), "N")

	# A gentle drift rather than a spin: the map a player is about to use turns
	# with their own head, and a figure that span would be teaching a compass.
	var drift := sin(TAU * u / loop) * 0.22
	var mates := [Vector2(-0.46, 0.30), Vector2(0.24, 0.52)]
	for offset: Vector2 in mates:
		_figure.draw_circle(centre + offset.rotated(drift) * radius, 5.0,
			UIPalette.team_colour(0))
	_glyph(centre + Vector2(0.44, -0.44).rotated(drift) * radius, "G",
		UIPalette.GUIDE_LOOSE, 22)
	var carrier := centre + Vector2(-0.30, -0.52).rotated(drift) * radius
	_figure.draw_circle(carrier, 5.5, UIPalette.GUIDE_ENEMY)
	_glyph(carrier + Vector2(14.0, 0.0), "B", UIPalette.GUIDE_ENEMY, 20)

	_figure.draw_colored_polygon(PackedVector2Array([
		centre + Vector2(0.0, -8.0),
		centre + Vector2(-6.0, 5.0),
		centre + Vector2(6.0, 5.0),
	]), UIPalette.TEXT)

	# The two things on that circle that are *not* drawn, said in words, because
	# an absence cannot be animated.
	_caption(Vector2(size.x * 0.20, size.y * 0.84), "NO ENEMY WITHOUT A LETTER")


## **6 — spell it.** Both halves of the win, on one timeline: the three lamps
## light in order on the left, and on the right a teammate walks a card home to
## the vault and the third lamp lights as it lands.
func _figure_spell_it(size: Vector2, u: float) -> void:
	var cell := Vector2(50.0, 60.0)
	var gap := 14.0
	var row := cell.x * 3.0 + gap * 2.0
	var left := size.x * 0.30 - row * 0.5
	var top := size.y * 0.5 - cell.y * 0.5
	var all_lit := u > 2.3
	var glow := 0.0
	if all_lit:
		glow = 0.5 + 0.5 * sin((u - 2.3) * 5.0)
	for i in MatchState.LETTERS.size():
		var rect := Rect2(Vector2(left + i * (cell.x + gap), top), cell)
		var lit := u > 0.5 + i * 0.8
		_lamp(rect, MatchState.letter_name(MatchState.LETTERS[i]), lit, glow)

	var vault := Vector2(size.x * 0.80, size.y * 0.5)
	var start := Vector2(size.x * 0.58, size.y * 0.80)
	_figure.draw_arc(vault, 26.0, 0.0, TAU, 32, UIPalette.team_colour(0), 2.0, true)
	_caption(vault + Vector2(0.0, 46.0), "YOUR VAULT")
	_dashed(PackedVector2Array([start, vault]), UIPalette.faded(UIPalette.GUIDE_ALLY, 0.85),
		_clock * DASH_SPEED)
	var walk := clampf(u / 2.1, 0.0, 1.0)
	if walk < 1.0:
		var at := start.lerp(vault, _ease_out(walk))
		_figure.draw_circle(at, 7.0, UIPalette.GUIDE_ALLY)
		_glyph(at + Vector2(15.0, 0.0), "G", UIPalette.GUIDE_ALLY, 18)
	else:
		_glyph(vault, "G", UIPalette.GUIDE_LOOSE, 26)


## One lamp, at `LetterTrack`'s proportions: knocked back hard when it is unlit,
## because two of three dark boxes is the normal state and a row of near-equal
## boxes is a thing you count rather than see.
func _lamp(rect: Rect2, glyph: String, lit: bool, glow: float) -> void:
	_figure.draw_rect(rect, Color(0.02, 0.027, 0.04, 0.62), true)
	var tint := UIPalette.faded(UIPalette.TEXT, 0.24)
	var border := UIPalette.faded(UIPalette.TEXT, 0.18)
	if lit:
		_figure.draw_rect(rect, UIPalette.faded(UIPalette.BOG, 0.12 + 0.14 * glow), true)
		tint = UIPalette.BOG
		border = UIPalette.faded(UIPalette.BOG, 0.85)
	_figure.draw_rect(rect, border, false, 1.5)
	_glyph(rect.get_center(), glyph, tint, 30)


# ------------------------------------------------------------- the pencils ---

## A dashed polyline whose dashes scroll toward the far end, which is the guide
## line's own idiom and the reason the line reads as a direction rather than as
## a rope. `phase` is pixels travelled.
func _dashed(points: PackedVector2Array, colour: Color, phase: float) -> void:
	if colour.a <= 0.01:
		return
	var period := DASH + DASH_GAP
	var travelled := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		if length <= 0.001:
			continue
		var direction := (b - a) / length
		var walked := 0.0
		var guard := 0
		while walked < length and guard < MAX_DASH_STEPS:
			guard += 1
			var into := fposmod(travelled + walked - phase, period)
			var step: float
			if into < DASH:
				var run := minf(DASH - into, length - walked)
				_figure.draw_line(a + direction * walked,
					a + direction * (walked + run), colour, DASH_WIDTH, true)
				step = run
			else:
				step = period - into
			# **Never a step of nothing.** `fposmod` can hand back a value a
			# hair under `period`, and `period - into` is then ~1e-15 — which,
			# added to a hundred pixels of `walked`, changes nothing, and a loop
			# that does not move is a frozen game. This loop froze the lobby on
			# card two for the owner and a friend within minutes of the first
			# build (the letters round); the floor on the step and the guard
			# above are what a drawing loop owes the main thread.
			walked += maxf(step, MIN_DASH_STEP)
		travelled += length


## A capital centred on `at`, with the void behind it. The outline is what makes
## a 20 px letter survive being drawn over a wash of ground, and it is the same
## trick `Minimap` uses for the same reason.
func _glyph(at: Vector2, text: String, colour: Color, font_size: int) -> void:
	var font := _figure.get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var corner := at + Vector2(-width * 0.5, font_size * 0.36)
	_figure.draw_string_outline(font, corner, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, 4, UIPalette.VOID)
	_figure.draw_string(font, corner, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, colour)


## A tiny label centred under something, in the palette's faintest text. These
## are names for the shapes, not sentences — the sentence is under the figure.
func _caption(at: Vector2, text: String) -> void:
	var font := _figure.get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		UIPalette.FONT_TINY).x
	_figure.draw_string(font, at + Vector2(-width * 0.5, 0.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, UIPalette.FONT_TINY, UIPalette.TEXT_FAINT)


## The drawstring sack `PouchMesh` builds in the world, at figure scale: a
## squashed body, a cinch across the mouth, and two cord tails.
func _pouch(at: Vector2) -> void:
	_figure.draw_set_transform(at + Vector2(0.0, 11.0), 0.0, Vector2(1.0, 1.2))
	_figure.draw_circle(Vector2.ZERO, 10.0, POUCH_WOOL)
	_figure.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_figure.draw_line(at + Vector2(-9.0, 0.0), at + Vector2(9.0, 0.0), POUCH_CORD, 2.5, true)
	_figure.draw_line(at + Vector2(-9.0, 0.0), at + Vector2(-14.0, -5.0), POUCH_CORD, 1.5, true)
	_figure.draw_line(at + Vector2(9.0, 0.0), at + Vector2(14.0, -5.0), POUCH_CORD, 1.5, true)


## Group C's sunburst, flattened: fourteen thin gold rays growing out and
## fading. `life` runs 1 to 0.
func _burst(at: Vector2, life: float) -> void:
	if life <= 0.0:
		return
	var reach := lerpf(4.0, 34.0, 1.0 - life)
	var colour := UIPalette.faded(Pickup.LETTER_COLOUR, life)
	for i in 14:
		var direction := Vector2.RIGHT.rotated(TAU * i / 14.0)
		_figure.draw_line(at + direction * (reach * 0.35), at + direction * reach,
			colour, 2.0, true)


## Cubic ease-out. The one curve in here, used wherever something arrives:
## a body hitting the ground, a card coming up out of it, a teammate reaching a
## vault. Things in this game decelerate into place; nothing accelerates out.
static func _ease_out(x: float) -> float:
	var clamped := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - clamped, 3.0)
