class_name ShowroomStyles
extends RefCounted
## The seven candidate looks, as dictionaries `ShowroomTheme.build()` reads.
## Development tool for the UI showroom, not shipped.
##
## Each style carries only what it changes; everything else falls through to
## `ShowroomTheme.defaults()`, which is today's `UIPalette`/`UITheme`. `current`
## is the empty style and is never built — the range keeps the baked theme for
## it, so the baseline shot comes out of the same pipeline as the candidates.


static func names() -> PackedStringArray:
	return PackedStringArray([
		"current", "hearth", "toybox", "storybook", "arcade", "quiet",
		"terminal", "swampglow",
	])


static func get_style(name: String) -> Dictionary:
	match name:
		"hearth": return _hearth()
		"toybox": return _toybox()
		"storybook": return _storybook()
		"arcade": return _arcade()
		"quiet": return _quiet()
		"terminal": return _terminal()
		"swampglow": return _swampglow()
	return {}


## The current look, warmed up. Panels tinted toward moss and umber instead of
## navy, rounder, heavier edges, and section labels untracked so they read as
## tight caps rather than as a spaced-out legend.
static func _hearth() -> Dictionary:
	return {
		"display_faces": PackedStringArray([
			"Segoe UI Variable Display Semibold", "Segoe UI Semibold", "Segoe UI",
		]),
		"display_weight": 600,
		"body_faces": PackedStringArray(["Segoe UI Variable Text", "Segoe UI"]),
		"tracking": 0,

		"void": Color(0.03, 0.035, 0.025),
		"panel": Color(0.07, 0.075, 0.05, 0.92),
		"raised": Color(0.11, 0.115, 0.08, 0.9),
		"raised_strong": Color(0.14, 0.145, 0.1),
		"line": Color(0.85, 0.75, 0.5, 0.18),
		"line_strong": Color(0.9, 0.8, 0.55, 0.35),
		"text": Color(0.96, 0.93, 0.86),
		"text_dim": Color(0.72, 0.68, 0.58),
		"text_faint": Color(0.52, 0.49, 0.42),
		"accent": Color(1.0, 0.66, 0.28),
		"accent_dim": Color(0.75, 0.48, 0.2),
		"accent_glow": Color(1.0, 0.76, 0.42),
		"you": Color(1.0, 0.84, 0.26),
		"you_dim": Color(0.62, 0.52, 0.18),
		"input_fill": Color(0.03, 0.035, 0.025, 0.85),
		"popup_fill": Color(0.06, 0.065, 0.045, 0.99),
		"nav_font_color": Color(0.72, 0.68, 0.58),

		"radius": 10,
		"border": 1,
		"pad_x": 24,
		"pad_y": 12,
		"shadow_size": 12,
		"shadow_color": Color(0, 0, 0, 0.35),
		"shadow_offset": Vector2(0, 4),
		"shadow_at_rest": true,
		"nav_style": "bar",
		"primary_style": "fill",
		"panel_border": true,
	}


## Party-game energy: fat rounded opaque cards with a dark outline and a hard
## offset shadow. Godot draws a stylebox shadow only when `shadow_size > 0`, so
## the hard drop is size 1 with a large offset rather than size 0.
static func _toybox() -> Dictionary:
	return {
		"display_faces": PackedStringArray(["Segoe UI Black", "Arial Black", "Segoe UI"]),
		"display_weight": 900,
		"body_faces": PackedStringArray(["Segoe UI Semibold", "Segoe UI"]),
		"body_weight": 600,

		"font_tiny": 15,
		"font_small": 17,
		"font_body": 20,
		"font_lead": 26,
		"font_head": 34,
		"font_display": 56,

		"void": Color(0.06, 0.11, 0.07),
		"panel": Color(0.11, 0.2, 0.13, 1.0),
		"raised": Color(0.16, 0.27, 0.18, 1.0),
		"raised_strong": Color(0.2, 0.33, 0.22),
		"line": Color(0.03, 0.07, 0.04, 1.0),
		"line_strong": Color(0.02, 0.05, 0.03, 1.0),
		"text": Color(0.99, 0.97, 0.9),
		"text_dim": Color(0.8, 0.85, 0.75),
		"text_faint": Color(0.6, 0.68, 0.58),
		"text_on_accent": Color(0.12, 0.09, 0.02),
		"accent": Color(1.0, 0.78, 0.2),
		"accent_dim": Color(0.85, 0.62, 0.12),
		"accent_glow": Color(1.0, 0.88, 0.4),
		"you": Color(0.62, 0.95, 0.35),
		"you_dim": Color(0.4, 0.65, 0.22),
		"danger": Color(1.0, 0.4, 0.35),
		"good": Color(0.62, 0.95, 0.35),
		"nav_font_color": Color(0.8, 0.85, 0.75),

		"radius": 16,
		"border": 3,
		"pad_x": 26,
		"pad_y": 14,
		"shadow_size": 1,
		"shadow_offset": Vector2(0, 5),
		"shadow_color": Color(0.02, 0.05, 0.03, 1.0),
		"shadow_at_rest": true,
		"nav_style": "pill",
		"primary_style": "fill_you",
		"panel_border": true,
		"hud_panel_alpha": 0.85,
		"input_fill": Color(0.06, 0.12, 0.08, 1.0),
		"popup_fill": Color(0.11, 0.2, 0.13, 1.0),
	}


## The only light option: opaque cream cards, brown ink, a moss accent, serif
## heads. The wordmark and the nav sit on the 3D scene rather than on a panel,
## so those two keep light colours while everything on a card is ink.
static func _storybook() -> Dictionary:
	return {
		"display_faces": PackedStringArray(["Constantia", "Georgia", "Cambria"]),
		"display_weight": 700,
		"body_faces": PackedStringArray(["Constantia", "Georgia"]),
		"body_weight": 400,
		"tracking": 2,

		"font_tiny": 14,
		"font_small": 16,
		"font_body": 19,
		"font_lead": 24,
		"font_head": 32,
		"font_display": 52,

		"void": Color(0.12, 0.1, 0.07),
		"panel": Color(0.93, 0.88, 0.76, 0.97),
		"raised": Color(0.88, 0.82, 0.68, 1.0),
		"raised_strong": Color(0.84, 0.77, 0.62),
		"line": Color(0.35, 0.25, 0.12, 0.45),
		"line_strong": Color(0.3, 0.2, 0.1, 0.8),
		"text": Color(0.18, 0.12, 0.06),
		"text_dim": Color(0.4, 0.32, 0.2),
		"text_faint": Color(0.55, 0.47, 0.35),
		"text_on_accent": Color(0.96, 0.93, 0.85),
		"accent": Color(0.36, 0.52, 0.2),
		"accent_dim": Color(0.28, 0.4, 0.15),
		"accent_glow": Color(0.45, 0.62, 0.26),
		"you": Color(0.8, 0.58, 0.1),
		"you_dim": Color(0.6, 0.42, 0.08),
		"danger": Color(0.7, 0.2, 0.15),
		"good": Color(0.36, 0.52, 0.2),

		"radius": 3,
		"border": 2,
		"pad_x": 22,
		"pad_y": 11,
		"shadow_size": 8,
		"shadow_color": Color(0, 0, 0, 0.4),
		"shadow_offset": Vector2(0, 3),
		"shadow_at_rest": true,
		"nav_style": "underline",
		"primary_style": "fill",
		"panel_border": true,
		"hud_panel_alpha": 0.9,
		"input_fill": Color(0.98, 0.95, 0.88, 1.0),
		"popup_fill": Color(0.95, 0.9, 0.8, 1.0),

		# The two things that are not on parchment: the wordmark (already `you`)
		# and the nav list, both of which sit over the live 3D backdrop.
		"nav_font_color": Color(0.95, 0.92, 0.85),
		"nav_font_hover_color": Color(0.8, 0.58, 0.1),
	}


## Competitive shooter: near-black, zero radius, skewed buttons, one acid
## accent, condensed caps.
static func _arcade() -> Dictionary:
	return {
		"display_faces": PackedStringArray([
			"Bahnschrift SemiBold Condensed", "Bahnschrift Condensed", "Bahnschrift",
		]),
		"display_weight": 600,
		"body_faces": PackedStringArray([
			"Bahnschrift SemiCondensed", "Bahnschrift", "Segoe UI",
		]),
		# Windows hands Godot the family "Bahnschrift" and nothing else, so the
		# Condensed and SemiCondensed instances are asked for by width here.
		"display_stretch": 75,
		"body_stretch": 87,
		"tracking": 4,

		"font_tiny": 14,
		"font_small": 17,
		"font_body": 20,
		"font_lead": 26,
		"font_head": 36,
		"font_display": 64,

		"void": Color(0.02, 0.02, 0.02),
		"panel": Color(0.05, 0.05, 0.055, 0.94),
		"raised": Color(0.1, 0.1, 0.11, 0.95),
		"raised_strong": Color(0.14, 0.14, 0.15),
		"line": Color(1, 1, 1, 0.14),
		"line_strong": Color(1, 1, 1, 0.35),
		"text": Color(0.98, 0.98, 0.98),
		"text_dim": Color(0.7, 0.7, 0.72),
		"text_faint": Color(0.48, 0.48, 0.5),
		"text_on_accent": Color(0.05, 0.05, 0.02),
		"accent": Color(0.85, 1.0, 0.1),
		"accent_dim": Color(0.6, 0.72, 0.08),
		"accent_glow": Color(0.93, 1.0, 0.4),
		"you": Color(0.85, 1.0, 0.1),
		"you_dim": Color(0.6, 0.72, 0.08),
		"danger": Color(1.0, 0.2, 0.3),
		"good": Color(0.3, 1.0, 0.5),
		"nav_font_color": Color(0.7, 0.7, 0.72),

		"radius": 0,
		"border": 1,
		"pad_x": 26,
		"pad_y": 12,
		"skew": Vector2(0.18, 0),
		"shadow_size": 0,
		"nav_style": "bar",
		"nav_bar_width": 6,
		"nav_hover_fill": Color(0.85, 1.0, 0.1, 0.12),
		"primary_style": "fill",
		"panel_border": true,
		"hud_panel_alpha": 0.7,
		"input_fill": Color(0.02, 0.02, 0.02, 0.9),
		"popup_fill": Color(0.05, 0.05, 0.055, 0.99),
	}


## Editorial: air and typography. Panels are barely-there tints with no border,
## the text field is a rule rather than a box, and the nav underlines.
static func _quiet() -> Dictionary:
	return {
		"display_faces": PackedStringArray([
			"Segoe UI Variable Display Light", "Segoe UI Light", "Segoe UI",
		]),
		"display_weight": 300,
		"body_faces": PackedStringArray(["Segoe UI Variable Text", "Segoe UI"]),
		"tracking": 6,
		"tracking_display": 8,

		"font_tiny": 13,
		"font_small": 15,
		"font_body": 18,
		"font_lead": 24,
		"font_head": 34,
		"font_display": 72,

		"void": Color(0.02, 0.025, 0.03),
		"panel": Color(0.02, 0.025, 0.03, 0.72),
		"raised": Color(1, 1, 1, 0.04),
		"raised_strong": Color(1, 1, 1, 0.08),
		"line": Color(1, 1, 1, 0.12),
		"line_strong": Color(1, 1, 1, 0.3),
		"text": Color(0.94, 0.94, 0.92),
		"text_dim": Color(0.66, 0.66, 0.64),
		"text_faint": Color(0.44, 0.44, 0.42),
		"text_on_accent": Color(0.05, 0.05, 0.04),
		"accent": Color(1.0, 0.84, 0.26),
		"accent_dim": Color(0.7, 0.58, 0.18),
		"accent_glow": Color(1.0, 0.9, 0.5),
		"you": Color(1.0, 0.84, 0.26),
		"you_dim": Color(0.7, 0.58, 0.18),
		"danger": Color(1.0, 0.4, 0.36),
		"good": Color(0.5, 0.88, 0.55),
		"nav_font_color": Color(0.66, 0.66, 0.64),

		# **Radius 10, and not everywhere** (the owner's "some border radiuses
		# here and there to smooth things out"). 10 is what `radius` buys:
		# every panel (CardPanel, RowPanel, HudPanel, PopupMenu), every button
		# (Button, PrimaryButton, GhostButton, OptionButton) and the focus ring.
		#
		# The two things it deliberately does *not* reach are the two shapes
		# that are a rule rather than a box, because a corner radius on a
		# bottom-border-only stylebox rounds nothing and would only be a lie in
		# the dictionary: the nav underline (`_nav_underline` builds at 0) and
		# the text field (`input_style` "underline"). The field keeps its rule
		# and gains `input_underline_fill` instead — `raised`, which in this
		# style is white at 0.04 — behind the text at radius 10, so it reads as
		# a soft field with a lit edge rather than as a bare line under nothing.
		"radius": 10,
		"border": 0,
		"pad_x": 20,
		"pad_y": 10,
		"shadow_size": 0,
		"nav_style": "underline",
		"primary_style": "outline",
		"panel_border": false,
		"hud_panel_alpha": 0.4,
		"input_style": "underline",
		"input_fill": Color(0, 0, 0, 0),
		"input_underline_fill": Color(1, 1, 1, 0.04),
		"input_underline_radius": 10,
		# The grabber is 4 rather than the `mini(3, radius)` every other style
		# takes: a 10 px corner on a 10 px tall grabber is a capsule, and 3 on a
		# UI that has just gone round everywhere reads as the one square thing.
		"slider_radius": 4,
		"popup_fill": Color(0.04, 0.045, 0.05, 0.99),
	}


## Brutalist monospace: hard 2px light borders on black, phosphor green, and
## buttons that invert on hover.
static func _terminal() -> Dictionary:
	return {
		"display_faces": PackedStringArray([
			"Cascadia Mono SemiBold", "Cascadia Mono", "Consolas",
		]),
		"display_weight": 600,
		"body_faces": PackedStringArray(["Cascadia Mono", "Consolas"]),
		"tracking": 0,

		"font_tiny": 13,
		"font_small": 15,
		"font_body": 17,
		"font_lead": 21,
		"font_head": 28,
		"font_display": 48,

		"void": Color(0, 0, 0),
		"panel": Color(0, 0, 0, 0.92),
		"raised": Color(0.07, 0.08, 0.07, 1.0),
		"raised_strong": Color(0.12, 0.13, 0.12),
		"line": Color(0.85, 0.9, 0.85, 0.6),
		"line_strong": Color(0.95, 1.0, 0.95, 0.95),
		"text": Color(0.9, 0.95, 0.88),
		"text_dim": Color(0.6, 0.7, 0.6),
		"text_faint": Color(0.4, 0.48, 0.4),
		"text_on_accent": Color(0, 0, 0),
		"accent": Color(0.5, 1.0, 0.45),
		"accent_dim": Color(0.35, 0.7, 0.32),
		"accent_glow": Color(0.7, 1.0, 0.65),
		"you": Color(1.0, 0.8, 0.2),
		"you_dim": Color(0.65, 0.5, 0.12),
		"danger": Color(1.0, 0.3, 0.25),
		"good": Color(0.5, 1.0, 0.45),
		"nav_font_color": Color(0.6, 0.7, 0.6),

		"radius": 0,
		"border": 2,
		"pad_x": 20,
		"pad_y": 9,
		"shadow_size": 0,
		"skew": Vector2.ZERO,
		"nav_style": "box",
		"primary_style": "fill",
		"invert_hover": true,
		"panel_border": true,
		"hud_panel_alpha": 0.85,
		"input_fill": Color(0, 0, 0, 0.9),
		"popup_fill": Color(0, 0, 0, 0.98),
	}


## Bioluminescent bog: teal-green glass with a soft outer glow on the edges you
## can touch. A `StyleBoxFlat` shadow with zero offset is a glow, and it is kept
## off `RowPanel` and `HudPanel` on purpose — a glow on every roster row is mud.
static func _swampglow() -> Dictionary:
	return {
		"display_faces": PackedStringArray([
			"Bahnschrift SemiBold", "Bahnschrift", "Segoe UI Semibold",
		]),
		"display_weight": 600,
		"body_faces": PackedStringArray(["Segoe UI Variable Text", "Segoe UI"]),
		"tracking": 3,

		"void": Color(0.015, 0.04, 0.035),
		"panel": Color(0.02, 0.08, 0.07, 0.86),
		"raised": Color(0.04, 0.13, 0.11, 0.9),
		"raised_strong": Color(0.06, 0.17, 0.15),
		"line": Color(0.4, 1.0, 0.75, 0.2),
		"line_strong": Color(0.45, 1.0, 0.8, 0.45),
		"text": Color(0.88, 0.98, 0.94),
		"text_dim": Color(0.58, 0.76, 0.7),
		"text_faint": Color(0.4, 0.55, 0.5),
		"text_on_accent": Color(0.02, 0.08, 0.06),
		"accent": Color(0.45, 1.0, 0.75),
		"accent_dim": Color(0.3, 0.7, 0.52),
		"accent_glow": Color(0.65, 1.0, 0.85),
		"you": Color(0.95, 1.0, 0.45),
		"you_dim": Color(0.6, 0.65, 0.25),
		"danger": Color(1.0, 0.35, 0.6),
		"good": Color(0.45, 1.0, 0.75),
		"nav_font_color": Color(0.58, 0.76, 0.7),

		"radius": 6,
		"border": 1,
		"pad_x": 22,
		"pad_y": 11,
		"shadow_size": 6,
		"shadow_color": Color(0.45, 1.0, 0.75, 0.25),
		"shadow_offset": Vector2.ZERO,
		"shadow_at_rest": false,
		"nav_style": "bar",
		"primary_style": "fill",
		"panel_border": true,
		"hud_panel_alpha": 0.55,
		"input_fill": Color(0.015, 0.05, 0.045, 0.85),
		"popup_fill": Color(0.03, 0.1, 0.09, 0.99),
	}
