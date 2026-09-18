class_name ShowroomTheme
extends RefCounted
## Builds a candidate `Theme` from a style dictionary. Development tool for the
## UI showroom, not shipped, and nothing here touches the game's own theme.
##
## This is `scripts/ui/ui_theme.gd` with every hardcoded value pulled out into
## the dictionary `ShowroomStyles` hands it, so seven very different looks can be
## photographed on the real screens without seven copies of the builder. The
## structure is deliberately the same file in the same order — labels, panels,
## buttons, inputs, toggles, sliders, scrollbars, misc — so the two can be read
## side by side and a knob traced back to the line it replaced.
##
##     var theme: Theme = ShowroomTheme.build(ShowroomStyles.get_style("hearth"))
##
## Every knob has a default equal to today's value, so a style dictionary only
## carries what it changes.


## Today's values, from `UIPalette` and `UITheme`. A style is these, overwritten.
##
## Not a `const` because half of it is `Color`/`Vector2`/`PackedStringArray`
## construction and a function is one less thing to be clever about.
static func defaults() -> Dictionary:
	return {
		# ------------------------------------------------------------ fonts --
		"display_faces": PackedStringArray([
			"Bahnschrift", "Segoe UI Variable Display", "Segoe UI Semibold", "Segoe UI",
		]),
		"body_faces": PackedStringArray([
			"Segoe UI Variable Text", "Segoe UI", "Noto Sans",
		]),
		"display_weight": 400,
		"body_weight": 400,
		"display_italic": false,
		# Width, not weight: Bahnschrift's Condensed and SemiCondensed are named
		# instances of one variable family, and Windows only ever reports the
		# family, so `arcade` gets its condensed caps from here rather than from
		# a face name the OS has never heard of.
		"display_stretch": 100,
		"body_stretch": 100,
		# `spacing_glyph` on the tracked face. Section labels use this;
		# `tracking_display` defaults to it and the wordmark uses that.
		"tracking": 3,

		# ------------------------------------------------------------ sizes --
		"font_tiny": 14,
		"font_small": 16,
		"font_body": 19,
		"font_lead": 23,
		"font_head": 30,
		"font_display": 44,

		# ---------------------------------------------------------- colours --
		"void": Color(0.024, 0.031, 0.047),
		"panel": Color(0.043, 0.055, 0.078, 0.90),
		"raised": Color(0.078, 0.098, 0.133, 0.85),
		"raised_strong": Color(0.094, 0.118, 0.157, 1.0),
		"line": Color(0.55, 0.66, 0.80, 0.16),
		"line_strong": Color(0.62, 0.74, 0.88, 0.30),
		"text": Color(0.90, 0.94, 0.98),
		"text_dim": Color(0.58, 0.65, 0.73),
		"text_faint": Color(0.42, 0.48, 0.56),
		"text_on_accent": Color(0.05, 0.04, 0.02),
		"accent": Color(1.00, 0.64, 0.26),
		"accent_dim": Color(0.72, 0.45, 0.18),
		"accent_glow": Color(1.00, 0.72, 0.38),
		"you": Color(1.00, 0.84, 0.26),
		"you_dim": Color(0.62, 0.52, 0.18),
		"danger": Color(1.00, 0.36, 0.30),
		"good": Color(0.48, 0.87, 0.51),

		# ------------------------------------------------------------ shape --
		"radius": 4,
		"border": 1,
		"pad_x": 22,
		"pad_y": 11,
		"card_pad": 20,
		"shadow_size": 0,
		"shadow_color": Color(0, 0, 0, 0.35),
		"shadow_offset": Vector2.ZERO,
		# Whether the shadow is also drawn on controls at rest. False means it is
		# a glow on the things you are touching (swampglow); true means it is a
		# drop shadow the card and the button carry all the time.
		"shadow_at_rest": false,
		"skew": Vector2.ZERO,
		"panel_border": true,
		"hud_panel_alpha": 0.55,

		# -------------------------------------------------------- behaviour --
		"nav_style": "bar",
		"nav_bar_width": 4,
		"nav_hover_fill": Color(0.10, 0.11, 0.13, 0.75),
		"nav_font_color": Color(0.58, 0.65, 0.73),  # text_dim, unless overridden
		"nav_font_hover_color": Color(0, 0, 0, 0),  # transparent = use `you`
		"primary_style": "fill",
		"input_style": "box",
		"input_fill": Color(0.02, 0.027, 0.04, 0.85),
		# Only read when `input_style` is "underline": the wash drawn behind the
		# text so a rule-only field is still a field. Transparent at radius 0 is
		# the bare rule every style but `quiet` still wants.
		"input_underline_fill": Color(0, 0, 0, 0),
		"input_underline_radius": 0,
		"popup_fill": Color(0.035, 0.045, 0.062, 0.99),
		# Terminal's buttons: hover fills with `text` and prints in `void`.
		"invert_hover": false,
	}


## The one entry point.
static func build(style: Dictionary) -> Theme:
	var s := defaults()
	for key: Variant in style:
		s[key] = style[key]

	var theme := Theme.new()
	theme.resource_name = "BOG UI showroom candidate"

	var body := _system_font(s["body_faces"], s["body_weight"], false, s["body_stretch"])
	var display := _system_font(s["display_faces"], s["display_weight"], s["display_italic"],
		s["display_stretch"])
	var tracked := _tracked(display, s["tracking"])
	var tracked_display := _tracked(display, s.get("tracking_display", s["tracking"]))

	theme.default_font = body
	theme.default_font_size = s["font_body"]

	_labels(theme, s, display, tracked, tracked_display)
	_panels(theme, s)
	_buttons(theme, s, display)
	_inputs(theme, s, body)
	_toggles(theme, s, body)
	_sliders(theme, s)
	_scrollbars(theme, s)
	_misc(theme, s, body)
	return theme


# ------------------------------------------------------------------ pieces ---

static func _system_font(faces: PackedStringArray, weight: int, italic: bool,
		stretch: int = 100) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = faces
	font.allow_system_fallback = true
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.font_weight = weight
	font.font_italic = italic
	font.font_stretch = stretch
	return font


static func _tracked(base: Font, spacing: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = base
	v.spacing_glyph = spacing
	return v


static func _flat(bg: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	return box


static func _bordered(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := _flat(bg, radius)
	box.border_color = border
	box.set_border_width_all(width)
	return box


static func _pad(box: StyleBoxFlat, horizontal: int, vertical: int) -> StyleBoxFlat:
	box.content_margin_left = horizontal
	box.content_margin_right = horizontal
	box.content_margin_top = vertical
	box.content_margin_bottom = vertical
	return box


## Godot draws a `StyleBoxFlat`'s shadow only when `shadow_size > 0`, so a style
## that wants a hard offset drop rather than a soft one asks for size 1 and a
## large offset.
static func _shadow(box: StyleBoxFlat, s: Dictionary) -> StyleBoxFlat:
	var size: int = s["shadow_size"]
	if size > 0:
		box.shadow_size = size
		box.shadow_color = s["shadow_color"]
		box.shadow_offset = s["shadow_offset"]
	return box


static func _skew(box: StyleBoxFlat, s: Dictionary) -> StyleBoxFlat:
	box.skew = s["skew"]
	return box


static func _alpha(colour: Color, a: float) -> Color:
	return Color(colour.r, colour.g, colour.b, a)


# ------------------------------------------------------------------ labels ---

static func _labels(theme: Theme, s: Dictionary, display: Font, tracked: Font,
		tracked_display: Font) -> void:
	theme.set_color("font_color", "Label", s["text"])
	theme.set_font_size("font_size", "Label", s["font_body"])

	_label(theme, "Display", tracked_display, s["font_display"], s["you"])
	_label(theme, "Head", display, s["font_head"], s["text"])
	_label(theme, "Lead", display, s["font_lead"], s["text"])
	_label(theme, "Section", tracked, s["font_tiny"], s.get("section_color", s["text_faint"]))
	_label(theme, "Dim", null, s["font_body"], s["text_dim"])
	_label(theme, "Small", null, s["font_small"], s["text_dim"])
	_label(theme, "Tiny", null, s["font_tiny"], s.get("tiny_color", s["text_faint"]))
	_label(theme, "Accent", display, s["font_body"], s["accent"])
	_label(theme, "Value", display, s["font_small"], s["accent"])
	_label(theme, "Readout", display, s["font_head"], s["text"])


static func _label(theme: Theme, name: String, font: Font, size: int, colour: Color) -> void:
	var type := name + "Label"
	theme.set_type_variation(type, "Label")
	if font != null:
		theme.set_font("font", type, font)
	theme.set_font_size("font_size", type, size)
	theme.set_color("font_color", type, colour)


# ------------------------------------------------------------------ panels ---

static func _panel_box(s: Dictionary) -> StyleBoxFlat:
	if s["panel_border"] and int(s["border"]) > 0:
		return _bordered(s["panel"], s["line"], s["border"], s["radius"])
	return _flat(s["panel"], s["radius"])


static func _panels(theme: Theme, s: Dictionary) -> void:
	theme.set_stylebox("panel", "Panel", _panel_box(s))
	theme.set_stylebox("panel", "PanelContainer", _panel_box(s))

	# The card is the one panel that carries the style's shadow — a glow on a
	# roster row or on the kill feed is mud, which is why RowPanel and HudPanel
	# below are built without one.
	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel",
		_shadow(_pad(_panel_box(s), s["card_pad"], s["card_pad"]), s))

	# Deliberately tight: a full eight-player roster has to fit the lobby's list
	# without a scroll bar.
	theme.set_type_variation("RowPanel", "PanelContainer")
	theme.set_stylebox("panel", "RowPanel", _pad(_flat(s["raised"], s["radius"]), 14, 5))

	theme.set_type_variation("HudPanel", "PanelContainer")
	theme.set_stylebox("panel", "HudPanel",
		_pad(_flat(_alpha(s["void"], s["hud_panel_alpha"]), s["radius"]), 14, 8))

	theme.set_type_variation("ScrimPanel", "PanelContainer")
	var scrim: Color = s["void"]
	theme.set_stylebox("panel", "ScrimPanel",
		_flat(Color(scrim.r * 0.35, scrim.g * 0.35, scrim.b * 0.35, 0.86), 0))


# ----------------------------------------------------------------- buttons ---

static func _buttons(theme: Theme, s: Dictionary, display: Font) -> void:
	theme.set_font("font", "Button", display)
	theme.set_font_size("font_size", "Button", s["font_body"])
	theme.set_color("font_color", "Button", s["text"])
	theme.set_color("font_hover_color", "Button",
		s["void"] if s["invert_hover"] else s["accent_glow"])
	theme.set_color("font_pressed_color", "Button",
		s["void"] if s["invert_hover"] else s["accent"])
	theme.set_color("font_focus_color", "Button", s["text"])
	theme.set_color("font_disabled_color", "Button", s["text_faint"])

	var normal := _bordered(s["raised"], s["line"], s["border"], s["radius"])
	_pad(_skew(normal, s), s["pad_x"], s["pad_y"])
	if s["shadow_at_rest"]:
		_shadow(normal, s)
	theme.set_stylebox("normal", "Button", normal)

	var hover_bg: Color = s["text"] if s["invert_hover"] else s["raised_strong"]
	var hover_edge: Color = s["text"] if s["invert_hover"] else s["accent_dim"]
	var hover := _bordered(hover_bg, hover_edge, s["border"], s["radius"])
	_pad(_skew(hover, s), s["pad_x"], s["pad_y"])
	_shadow(hover, s)
	theme.set_stylebox("hover", "Button", hover)

	var pressed_bg: Color = s["accent"] if s["invert_hover"] \
		else _alpha((s["raised_strong"] as Color).lerp(s["accent"], 0.22), 0.98)
	var pressed := _bordered(pressed_bg, s["accent"], s["border"], s["radius"])
	_pad(_skew(pressed, s), s["pad_x"], s["pad_y"])
	_shadow(pressed, s)
	theme.set_stylebox("pressed", "Button", pressed)

	var disabled := _bordered(_alpha(s["void"], 0.7), _alpha(s["line"], 0.5),
		s["border"], s["radius"])
	theme.set_stylebox("disabled", "Button",
		_pad(_skew(disabled, s), s["pad_x"], s["pad_y"]))

	# One focus ring for the whole UI, drawn outside the control so gaining
	# focus never shifts the layout.
	theme.set_stylebox("focus", "Button", _focus_ring(s))

	_primary(theme, s)
	_nav(theme, s)

	# Ghost: borderless, for anything secondary.
	theme.set_type_variation("GhostButton", "Button")
	theme.set_font_size("font_size", "GhostButton", s["font_small"])
	theme.set_color("font_color", "GhostButton", s["text_dim"])
	var clear := Color(0, 0, 0, 0)
	theme.set_stylebox("normal", "GhostButton", _pad(_flat(clear, s["radius"]), 12, 7))
	theme.set_stylebox("hover", "GhostButton",
		_pad(_flat(_alpha(s["raised_strong"], 0.8), s["radius"]), 12, 7))
	theme.set_stylebox("pressed", "GhostButton",
		_pad(_flat(_alpha((s["raised_strong"] as Color).lerp(s["accent"], 0.22), 0.9),
			s["radius"]), 12, 7))
	theme.set_stylebox("disabled", "GhostButton", _pad(_flat(clear, s["radius"]), 12, 7))

	# Danger: red only on hover, because a permanently red button among grey
	# ones draws the eye to the one action nobody is hunting for.
	var danger: Color = s["danger"]
	theme.set_type_variation("DangerButton", "Button")
	theme.set_color("font_hover_color", "DangerButton", danger)
	theme.set_color("font_pressed_color", "DangerButton", danger)
	var d_hover := _bordered(_alpha(Color(danger.r, danger.g, danger.b).darkened(0.82), 0.95),
		danger.darkened(0.35), s["border"], s["radius"])
	theme.set_stylebox("hover", "DangerButton",
		_shadow(_pad(_skew(d_hover, s), s["pad_x"], s["pad_y"]), s))
	var d_pressed := _bordered(_alpha(Color(danger.r, danger.g, danger.b).darkened(0.76), 0.98),
		danger, s["border"], s["radius"])
	theme.set_stylebox("pressed", "DangerButton",
		_pad(_skew(d_pressed, s), s["pad_x"], s["pad_y"]))


## Primary: at most one per screen, and the only solid accent fill in the UI.
static func _primary(theme: Theme, s: Dictionary) -> void:
	theme.set_type_variation("PrimaryButton", "Button")
	var px: int = int(s["pad_x"]) + 4
	var py: int = int(s["pad_y"]) + 1
	var style: String = s["primary_style"]
	var fill: Color = s["you"] if style == "fill_you" else s["accent"]
	var glow: Color = s["you"] if style == "fill_you" else s["accent_glow"]
	var dim: Color = s["you_dim"] if style == "fill_you" else s["accent_dim"]

	if style == "outline":
		# Transparent with an accent rule, inverting to a filled block on hover.
		theme.set_color("font_color", "PrimaryButton", s["accent"])
		theme.set_color("font_hover_color", "PrimaryButton", s["text_on_accent"])
		theme.set_color("font_pressed_color", "PrimaryButton", s["text_on_accent"])
		var out_normal := _bordered(Color(0, 0, 0, 0), s["accent"], 2, s["radius"])
		theme.set_stylebox("normal", "PrimaryButton",
			_pad(_skew(out_normal, s), px, py))
		var out_hover := _bordered(s["accent"], s["accent"], 2, s["radius"])
		theme.set_stylebox("hover", "PrimaryButton",
			_shadow(_pad(_skew(out_hover, s), px, py), s))
		var out_pressed := _bordered(dim, dim, 2, s["radius"])
		theme.set_stylebox("pressed", "PrimaryButton",
			_pad(_skew(out_pressed, s), px, py))
	else:
		theme.set_color("font_color", "PrimaryButton", s["text_on_accent"])
		theme.set_color("font_hover_color", "PrimaryButton", s["text_on_accent"])
		theme.set_color("font_pressed_color", "PrimaryButton", s["text_on_accent"])
		theme.set_stylebox("normal", "PrimaryButton",
			_shadow(_pad(_skew(_flat(fill, s["radius"]), s), px, py), s))
		theme.set_stylebox("hover", "PrimaryButton",
			_shadow(_pad(_skew(_flat(glow, s["radius"]), s), px, py), s))
		theme.set_stylebox("pressed", "PrimaryButton",
			_pad(_skew(_flat(dim, s["radius"]), s), px, py))

	theme.set_color("font_disabled_color", "PrimaryButton", s["text_faint"])
	var off := _bordered(_alpha(s["void"], 0.8), _alpha(s["line"], 0.6), s["border"], s["radius"])
	theme.set_stylebox("disabled", "PrimaryButton", _pad(_skew(off, s), px, py))


## Nav: the main menu's own list. Four shapes, one per style family.
static func _nav(theme: Theme, s: Dictionary) -> void:
	theme.set_type_variation("NavButton", "Button")
	theme.set_font_size("font_size", "NavButton", s["font_lead"])
	var hover_text: Color = s["nav_font_hover_color"]
	if hover_text.a <= 0.0:
		hover_text = s["you"]
	theme.set_color("font_color", "NavButton", s["nav_font_color"])
	theme.set_color("font_hover_color", "NavButton", hover_text)
	theme.set_color("font_pressed_color", "NavButton", s["accent"])
	theme.set_color("font_focus_color", "NavButton", hover_text)

	var clear := Color(0, 0, 0, 0)
	var style: String = s["nav_style"]
	match style:
		"underline":
			theme.set_stylebox("normal", "NavButton", _nav_underline(s, clear, 0))
			theme.set_stylebox("hover", "NavButton", _nav_underline(s, s["accent"], 2))
			theme.set_stylebox("pressed", "NavButton", _nav_underline(s, s["you"], 2))
			theme.set_stylebox("focus", "NavButton", _nav_underline(s, s["accent_dim"], 2))
			theme.set_stylebox("disabled", "NavButton", _nav_underline(s, clear, 0))
		"box":
			var edge: Color = s["line_strong"] if s["invert_hover"] else s["line"]
			theme.set_stylebox("normal", "NavButton",
				_pad(_bordered(clear, edge, s["border"], s["radius"]), 22, 13))
			var hb: Color = s["text"] if s["invert_hover"] else s["raised_strong"]
			var he: Color = s["text"] if s["invert_hover"] else s["accent"]
			theme.set_color("font_hover_color", "NavButton",
				s["void"] if s["invert_hover"] else hover_text)
			theme.set_color("font_focus_color", "NavButton",
				s["void"] if s["invert_hover"] else hover_text)
			theme.set_stylebox("hover", "NavButton",
				_pad(_bordered(hb, he, s["border"], s["radius"]), 22, 13))
			theme.set_stylebox("pressed", "NavButton",
				_pad(_bordered(s["accent"], s["accent"], s["border"], s["radius"]), 22, 13))
			theme.set_color("font_pressed_color", "NavButton", s["text_on_accent"])
			theme.set_stylebox("focus", "NavButton",
				_pad(_bordered(hb, he, s["border"], s["radius"]), 22, 13))
			theme.set_stylebox("disabled", "NavButton",
				_pad(_bordered(clear, _alpha(edge, 0.4), s["border"], s["radius"]), 22, 13))
		"pill":
			theme.set_stylebox("normal", "NavButton", _pad(_flat(clear, 999), 26, 13))
			theme.set_stylebox("hover", "NavButton", _pad(_flat(s["raised_strong"], 999), 26, 13))
			theme.set_stylebox("pressed", "NavButton",
				_pad(_flat(_alpha((s["raised_strong"] as Color).lerp(s["accent"], 0.3), 1.0),
					999), 26, 13))
			theme.set_stylebox("focus", "NavButton",
				_pad(_flat(_alpha(s["raised"], 0.8), 999), 26, 13))
			theme.set_stylebox("disabled", "NavButton", _pad(_flat(clear, 999), 26, 13))
		_:
			# "bar": no box at all until you touch it, then a thick accent bar
			# down the left edge, so the row you are on reads from the corner of
			# the eye.
			theme.set_stylebox("normal", "NavButton", _nav_bar(s, clear, clear))
			theme.set_stylebox("hover", "NavButton",
				_nav_bar(s, s["nav_hover_fill"], s["accent"]))
			theme.set_stylebox("pressed", "NavButton",
				_nav_bar(s, _alpha((s["raised_strong"] as Color).lerp(s["accent"], 0.3), 0.9),
					s["you"]))
			# Scaled rather than set: today's focus fill is four fifths of the
			# hover fill's alpha, and a style whose hover is a 12% wash (arcade)
			# wants four fifths of *that*, not a flat 0.6 that would make the
			# focused row louder than the hovered one.
			var hover_fill: Color = s["nav_hover_fill"]
			theme.set_stylebox("focus", "NavButton",
				_nav_bar(s, _alpha(hover_fill, hover_fill.a * 0.8), s["accent_dim"]))
			theme.set_stylebox("disabled", "NavButton", _nav_bar(s, clear, clear))


static func _nav_bar(s: Dictionary, bg: Color, bar: Color) -> StyleBoxFlat:
	var box := _flat(bg, 2)
	box.border_color = bar
	box.border_width_left = s["nav_bar_width"]
	return _pad(box, 22, 13)


static func _nav_underline(s: Dictionary, rule: Color, width: int) -> StyleBoxFlat:
	var box := _flat(Color(0, 0, 0, 0), 0)
	box.border_color = rule
	box.border_width_bottom = width
	return _pad(box, 6, 13)


static func _focus_ring(s: Dictionary) -> StyleBoxFlat:
	var box := _flat(Color(0, 0, 0, 0), s["radius"])
	box.draw_center = false
	box.border_color = s["accent"]
	box.set_border_width_all(1)
	box.set_expand_margin_all(2)
	return box


# ------------------------------------------------------------------ inputs ---

static func _input_box(s: Dictionary, fill: Color, edge: Color) -> StyleBoxFlat:
	# Never skewed: a slanted text field is a typo waiting to happen.
	if s["input_style"] == "underline":
		var rule := _flat(s["input_underline_fill"], int(s["input_underline_radius"]))
		rule.border_color = edge
		rule.border_width_bottom = 1
		return _pad(rule, 2, 10)
	return _pad(_bordered(fill, edge, maxi(1, int(s["border"])), s["radius"]), 14, 10)


static func _inputs(theme: Theme, s: Dictionary, body: Font) -> void:
	theme.set_font("font", "LineEdit", body)
	theme.set_font_size("font_size", "LineEdit", s["font_body"])
	theme.set_color("font_color", "LineEdit", s["text"])
	theme.set_color("font_placeholder_color", "LineEdit", s["text_faint"])
	theme.set_color("font_uneditable_color", "LineEdit", s["text_dim"])
	theme.set_color("caret_color", "LineEdit", s["accent"])
	theme.set_color("selection_color", "LineEdit", _alpha(s["accent"], 0.28))
	theme.set_stylebox("normal", "LineEdit", _input_box(s, s["input_fill"], s["line_strong"]))
	theme.set_stylebox("focus", "LineEdit",
		_shadow(_input_box(s, s["input_fill"], s["accent"]), s))
	theme.set_stylebox("read_only", "LineEdit",
		_input_box(s, _alpha(s["input_fill"], 0.5), _alpha(s["line"], 0.5)))

	theme.set_font_size("font_size", "OptionButton", s["font_small"])
	theme.set_color("font_color", "OptionButton", s["text"])
	theme.set_color("font_hover_color", "OptionButton", s["accent_glow"])
	theme.set_color("font_disabled_color", "OptionButton", s["text_faint"])
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var tint: Color = s["accent_dim"] if state == "hover" else s["line"]
		var box := _bordered(s["input_fill"], tint, maxi(1, int(s["border"])), s["radius"])
		_pad(_skew(box, s), 14, 8)
		if state == "hover" or s["shadow_at_rest"]:
			_shadow(box, s)
		theme.set_stylebox(state, "OptionButton", box)
	theme.set_stylebox("focus", "OptionButton", _focus_ring(s))

	theme.set_stylebox("panel", "PopupMenu",
		_bordered(s["popup_fill"], s["line_strong"], maxi(1, int(s["border"])), s["radius"]))
	theme.set_stylebox("hover", "PopupMenu",
		_flat(_alpha((s["raised_strong"] as Color).lerp(s["accent"], 0.3), 1.0), s["radius"]))
	theme.set_color("font_color", "PopupMenu", s["text"])
	theme.set_color("font_hover_color", "PopupMenu", s["accent_glow"])
	theme.set_font_size("font_size", "PopupMenu", s["font_small"])


static func _toggles(theme: Theme, s: Dictionary, body: Font) -> void:
	for type: String in ["CheckButton", "CheckBox"]:
		theme.set_font("font", type, body)
		theme.set_font_size("font_size", type, s["font_small"])
		theme.set_color("font_color", type, s["text_dim"])
		theme.set_color("font_hover_color", type, s["text"])
		theme.set_color("font_pressed_color", type, s["you"])
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			theme.set_stylebox(state, type, _pad(_flat(Color(0, 0, 0, 0), s["radius"]), 4, 6))
		theme.set_stylebox("focus", type, _focus_ring(s))


static func _sliders(theme: Theme, s: Dictionary) -> void:
	var track := _flat(_alpha(s["input_fill"], 0.9), mini(3, int(s["radius"])))
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	theme.set_stylebox("slider", "HSlider", track)
	# The filled part of the track. `mini(3, radius)` unless a style says
	# otherwise: a bar this short reads as a capsule long before it reaches the
	# radius a panel wants, so it is capped rather than shared.
	var grabber: int = int(s.get("slider_radius", mini(3, int(s["radius"]))))
	theme.set_stylebox("grabber_area", "HSlider", _flat(s["accent_dim"], grabber))
	theme.set_stylebox("grabber_area_highlight", "HSlider",
		_flat(s["accent"], grabber))


## **A scroll bar with no width is a panel that does not say it scrolls** (D-076).
## `BAR` is the width the content margins buy: a `StyleBoxFlat` with no margins
## has a minimum size of zero, and a `ScrollBar`'s thickness is exactly that.
static func _scrollbars(theme: Theme, s: Dictionary) -> void:
	const BAR := 5
	var r: int = mini(3, int(s["radius"]))
	for type: String in ["VScrollBar", "HScrollBar"]:
		var horizontal := type == "HScrollBar"
		var pad_x := 0 if horizontal else BAR
		var pad_y := BAR if horizontal else 0
		theme.set_stylebox("scroll", type,
			_pad(_flat(_alpha(s["void"], 0.55), r), pad_x, pad_y))
		theme.set_stylebox("grabber", type,
			_pad(_flat(_alpha(s["line_strong"], 0.75), r), pad_x, pad_y))
		theme.set_stylebox("grabber_highlight", type,
			_pad(_flat(s["accent_dim"], r), pad_x, pad_y))
		theme.set_stylebox("grabber_pressed", type,
			_pad(_flat(s["accent"], r), pad_x, pad_y))


static func _misc(theme: Theme, s: Dictionary, body: Font) -> void:
	theme.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	theme.set_font("normal_font", "RichTextLabel", body)
	theme.set_font_size("normal_font_size", "RichTextLabel", s["font_small"])
	theme.set_color("default_color", "RichTextLabel", s["text_dim"])
	theme.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	theme.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())

	var rule := _flat(s["line"], 0)
	rule.content_margin_top = 1
	theme.set_stylebox("separator", "HSeparator", rule)
	theme.set_constant("separation", "HSeparator", 1)

	theme.set_stylebox("background", "ProgressBar", _flat(_alpha(s["void"], 0.9), 2))
	theme.set_stylebox("fill", "ProgressBar", _flat(s["accent"], 2))
	theme.set_color("font_color", "ProgressBar", s["text_dim"])
	theme.set_font_size("font_size", "ProgressBar", s["font_tiny"])
