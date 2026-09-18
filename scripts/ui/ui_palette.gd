class_name UIPalette
extends RefCounted
## The colours and metrics every BOG screen is built from.
##
## These live in a class of their own rather than inside the theme because the
## HUD draws several things — the crosshair, the cooldown sweeps, the kill feed
## tints — with `_draw` and `draw_arc`, which a `Theme` cannot reach. One list of
## colours keeps a hand-drawn crosshair and a themed button the same family.
##
## The scheme is **Quiet**: the screen is the game, and the UI is the caption
## under it. Backgrounds are near-black and the surfaces on top of them are not
## colours at all but white at four, eight, twelve and thirty per cent — so a
## panel over the forest is the forest, dimmed, and a panel over the arena is
## the arena, dimmed, without either one being repainted navy. Nothing is
## bordered by default; a shape is read from its fill and its typography.
##
## **There is one accent, and it is the Bog's own yellow.** The scheme used to
## carry two — torch amber for "you can touch this" and Bog yellow for "this is
## you" — and on a real screen they were one colour with a slightly different
## mood, which meant neither of them said anything. `AMBER` and `BOG` are now
## the same `Color`, kept as two names only because twelve scripts read them and
## the distinction is still worth *saying* at the call site: `BOG` where the
## thing is the player, `AMBER` where the thing is interactive. Anything else on
## screen is white, dim white, or fainter white — so the single yellow is always
## the answer to "where am I, and what can I press".

# ------------------------------------------------------------------ ground ---

## The floor. Near-black with the faintest cool cast left in it, close enough to
## the project's `default_clear_color` that a fade to black and a fade to the
## menu are the same gesture.
const VOID := Color(0.02, 0.025, 0.03)
## Panel glass. Deliberately translucent: the lobby and the menu both have live
## 3D behind them and a solid panel would throw that away.
const PANEL := Color(0.02, 0.025, 0.03, 0.72)
## A surface sitting on another surface — a row inside a list, a settings field,
## a button at rest. White at a few per cent rather than a lighter blue-grey, so
## it lifts off *whatever* is behind it instead of only off one background.
const RAISED := Color(1.0, 1.0, 1.0, 0.04)
const RAISED_STRONG := Color(1.0, 1.0, 1.0, 0.08)
## Hairlines. Low alpha on purpose: at 1600x900 a 1 px border at full strength
## reads as a wireframe, not as an edge. `LINE_STRONG` is the one that is meant
## to be seen — the rule under a text field, a scroll bar's grabber.
const LINE := Color(1.0, 1.0, 1.0, 0.12)
const LINE_STRONG := Color(1.0, 1.0, 1.0, 0.30)

# -------------------------------------------------------------------- text ---

## Warm white, a shade off the surfaces above so the type never glares.
const TEXT := Color(0.94, 0.94, 0.92)
const TEXT_DIM := Color(0.66, 0.66, 0.64)
const TEXT_FAINT := Color(0.44, 0.44, 0.42)
const TEXT_ON_ACCENT := Color(0.05, 0.05, 0.04)

# ------------------------------------------------------------------ accent ---

## The one accent. `AMBER` and `BOG` are deliberately the same colour (see the
## header): hover, focus, the selected thing, the live clock, your own row, your
## own name, "ready". If it is yellow, it is either you or something you can do.
const AMBER := Color(1.00, 0.84, 0.26)
const AMBER_DIM := Color(0.70, 0.58, 0.18)
const AMBER_GLOW := Color(1.00, 0.90, 0.50)
const BOG := AMBER
const BOG_DIM := AMBER_DIM

## The only two other colours in the UI, and both of them are a verdict rather
## than a decoration: you are hurt, or you are winning.
const DANGER := Color(1.00, 0.40, 0.36)
const GOOD := Color(0.50, 0.88, 0.55)

# ------------------------------------------------------------------ scales ---

## Authored against the 1600x900 base viewport; `canvas_items` stretch scales
## the whole lot from there, so these are the only sizes that ever need tuning.
##
## Every step is a shade smaller than the scheme it replaced except the last:
## the wordmark goes 44 -> 72. A quiet UI has to earn its one loud thing, and
## the loud thing is the word BOG.
const FONT_TINY := 13
const FONT_SMALL := 15
const FONT_BODY := 18
const FONT_LEAD := 24
const FONT_HEAD := 34
const FONT_DISPLAY := 72

## Corner radius, everywhere a box is a box. The two shapes that ignore it are
## the two that are a rule rather than a box — the nav underline and a slider's
## grabber — because a corner radius on a one-sided border rounds nothing.
const RADIUS := 10
const GAP := 12
const PAD := 20


## Team tint, shared with the nameplate above the Bog's head so a row in the
## lobby and a name over a head are unmistakably the same player.
static func team_colour(team: int) -> Color:
	return Nameplate.colour_for_team(team)


## `m:ss`, or `mm:ss` past ten minutes. Negative clamps to zero rather than
## printing a minus, because a clock that has run out reads as 0:00 everywhere.
static func clock(seconds: float) -> String:
	var total := int(maxf(0.0, seconds) + 0.5)
	return "%d:%02d" % [total / 60, total % 60]


## Fade a colour toward nothing without touching its hue, for pips, ghosted
## rows and anything that dims rather than changes meaning.
static func faded(colour: Color, alpha: float) -> Color:
	return Color(colour.r, colour.g, colour.b, colour.a * alpha)


## The same colour at a stated alpha rather than a scaled one. The surfaces in
## this scheme are white at an alpha, so "the accent at 18%" is a wash you reach
## for constantly and `faded` — which multiplies — cannot express.
static func at(colour: Color, alpha: float) -> Color:
	return Color(colour.r, colour.g, colour.b, alpha)
