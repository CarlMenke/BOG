extends RefCounted
## Alternative *layouts* of the real BOG screens, for the showroom. Development
## tool, not shipped, and nothing here changes the game.
##
##     ShowroomLayouts.apply("menu", "card", main_menu_node)
##
## The sibling of `showroom_theme.gd`: that one asks "what should this UI look
## like", this one asks "where should the pieces be". Both photograph the real
## scenes rather than a mock, so what comes out of the camera is what shipping
## the arrangement would actually give.
##
## **Recipes mutate the live tree and are re-applied every frame.** That is not
## laziness, it is the only thing that works here: `lobby.gd` re-lays its panel
## stack out of `_refresh` whenever the roster changes, `_refresh_surface`
## rewrites size flags on the two folding panels, and `_rebuild_weapon_picker`
## frees and rebuilds the strip's buttons. A one-shot in `_ready` would be undone
## a few frames later by a script doing its job. So every recipe is written to be
## idempotent — reparent only if the parent is wrong, create a container only if
## it is missing, and set anchors unconditionally because setting them twice
## costs nothing.
##
## **Nothing is ever deleted.** A control that was on screen before is still on
## screen afterwards, somewhere; that is the acceptance test the owner will apply
## by eye, and it is also what keeps a recipe honest — "this is better" has to
## mean "with all of it", not "with the awkward half hidden".
##
## Two mechanisms are worth naming because they are not obvious:
##
## *Reparenting keeps `%Name` working.* `unique_name_in_owner` is registered on
## the **owner**, and every move here is within one owner's subtree, so the name
## is released on exit and re-acquired on enter by the engine itself. `_move`
## re-asserts the flag anyway, because a `%` lookup that silently stops resolving
## is the failure mode that would be hardest to see in a screenshot.
##
## *Turning a box on its side means building a new box.* `BoxContainer` carries
## the `vertical` flag, but `VBoxContainer` and `HBoxContainer` refuse to change
## it — "Can't change orientation of VBoxContainer", from the engine, once per
## frame. So `_transpose` creates the container of the other class and moves the
## children across, and it does that **every frame**, because one of the two
## boxes it is used on (`WeaponPicker`) has its children freed and rebuilt by
## `lobby.gd` on every roster change. Children that arrive back in the old box
## are moved again, and anything left over in the new one from the previous
## rebuild is freed with it — otherwise the strip grows a copy of itself every
## time somebody joins.


## Every layout this file knows, per screen. `render_layouts.sh` reads the same
## list by hand; this one is what `apply` validates against, so a typo in the
## shell script is a loud error rather than a silently unchanged screenshot.
const LAYOUTS := {
	"menu": ["current", "centred", "bottombar", "rightcolumn", "card"],
	"lobby": ["current", "rightrail", "bottomdock", "leftrail", "columns"],
	"settings": ["current", "sheet", "page", "tabs"],
	"hud": ["current", "corners", "rightstack", "compact"],
}

## Size-flag shorthand, because these read as noise at the call site.
const BEGIN := Control.SIZE_SHRINK_BEGIN
const FILL := Control.SIZE_FILL
const GROW := Control.SIZE_EXPAND_FILL
const MIDDLE := Control.SIZE_SHRINK_CENTER
const END := Control.SIZE_SHRINK_END


static func names(screen: String) -> Array:
	return LAYOUTS.get(screen, [])


## The one entry point. Safe to call every frame, and safe to call before the
## screen has finished building itself — every lookup is null-guarded, so a
## recipe applied to a half-built tree simply does the part it can find.
static func apply(screen: String, layout: String, root: Node) -> void:
	if root == null or layout.is_empty() or layout == "current":
		return
	if not LAYOUTS.has(screen):
		push_error("showroom: unknown screen '%s'" % screen)
		return
	if not (LAYOUTS[screen] as Array).has(layout):
		push_error("showroom: unknown %s layout '%s'; known: %s"
			% [screen, layout, ", ".join(PackedStringArray(LAYOUTS[screen]))])
		return
	match screen:
		"menu": _menu(layout, root)
		"lobby": _lobby(layout, root)
		"settings": _settings(layout, root)
		"hud": _hud(layout, root)


# ------------------------------------------------------------------- tools ---

## First descendant with this name, searched by name rather than by path because
## a recipe that has already run has moved some of these.
static func _find(parent: Node, node_name: String) -> Node:
	if parent == null:
		return null
	if parent.name == node_name:
		return parent
	var hits := parent.find_children(node_name, "", true, false)
	return hits[0] if hits.size() > 0 else null


static func _c(parent: Node, node_name: String) -> Control:
	return _find(parent, node_name) as Control


## A `%Name` lookup off the screen root, which is how the screen's own script
## reaches these and therefore the one that has to keep working.
static func _u(root: Node, node_name: String) -> Control:
	if root == null:
		return null
	return root.get_node_or_null("%%%s" % node_name) as Control


## Anchor a control by anchors + offsets in the 1600x900 base space.
##
## The grow directions come off the anchors rather than being passed in, and
## that is not tidiness: a control pinned to the top whose content is taller than
## the box it was given grows **upward** under the default `GROW_BOTH` and walks
## off the top of the screen. That is exactly what the HUD's top bar did the
## first time -- a shrink-wrapped `RichTextLabel` turned out to be 294 px tall
## and took the clock with it, off the top edge and out of the photograph.
static func _rect(c: Control, anchors: Rect2, offsets: Rect2) -> void:
	if c == null:
		return
	c.anchor_left = anchors.position.x
	c.anchor_top = anchors.position.y
	c.anchor_right = anchors.end.x
	c.anchor_bottom = anchors.end.y
	c.offset_left = offsets.position.x
	c.offset_top = offsets.position.y
	c.offset_right = offsets.end.x
	c.offset_bottom = offsets.end.y
	c.grow_horizontal = _grow(anchors.position.x, anchors.end.x)
	c.grow_vertical = _grow(anchors.position.y, anchors.end.y)


## Which way a fixed-size box spills: away from the edge it is pinned to, and
## both ways when it is pinned to neither or to both.
static func _grow(low: float, high: float) -> int:
	if not is_equal_approx(low, high):
		return Control.GROW_DIRECTION_BOTH
	if is_zero_approx(low):
		return Control.GROW_DIRECTION_END
	if is_equal_approx(low, 1.0):
		return Control.GROW_DIRECTION_BEGIN
	return Control.GROW_DIRECTION_BOTH


## Anchor presets, as `Rect2(anchor_left, anchor_top, width, height)` in anchor
## space. Named so the call sites read as English.
const TOP_LEFT := Rect2(0, 0, 0, 0)
const TOP_RIGHT := Rect2(1, 0, 0, 0)
const LEFT_EDGE := Rect2(0, 0, 0, 1)
const RIGHT_EDGE := Rect2(1, 0, 0, 1)
const BOTTOM_LEFT := Rect2(0, 1, 0, 0)
const BOTTOM_RIGHT := Rect2(1, 1, 0, 0)
const BOTTOM_WIDE := Rect2(0, 1, 1, 0)
const BOTTOM_CENTRE := Rect2(0.5, 1, 0, 0)
const RIGHT_MIDDLE := Rect2(1, 0.5, 0, 0)
const LEFT_MIDDLE := Rect2(0, 0.5, 0, 0)
const FULL := Rect2(0, 0, 1, 1)
const TOP_WIDE := Rect2(0, 0, 1, 0)


static func _box(left: float, top: float, right: float, bottom: float) -> Rect2:
	return Rect2(left, top, right - left, bottom - top)


## Move a node, keeping its owner and its `%Name` registration.
##
## The engine already re-acquires a unique name on re-entering the tree, so the
## re-assertion below is belt and braces — but a `%` lookup that quietly stops
## resolving would show up as a script error forty frames later, nowhere near
## the move that caused it, so it is worth the two lines.
static func _move(node: Node, parent: Node, index: int = -1) -> void:
	if node == null or parent == null or node == parent:
		return
	if node.get_parent() == parent:
		if index >= 0 and node.get_index() != index:
			parent.move_child(node, mini(index, parent.get_child_count() - 1))
		return
	var keeper := node.owner
	var unique: bool = node.unique_name_in_owner
	node.get_parent().remove_child(node)
	parent.add_child(node)
	if keeper != null and keeper != node and keeper.is_ancestor_of(node):
		node.owner = keeper
	if unique:
		node.unique_name_in_owner = false
		node.unique_name_in_owner = true
	if index >= 0:
		parent.move_child(node, mini(index, parent.get_child_count() - 1))


## A container this recipe needs and the scene does not have. Created once;
## found by name on every frame after that.
static func _new_node(parent: Node, node_name: String, kind: String) -> Node:
	if parent == null:
		return null
	var existing := parent.get_node_or_null(NodePath(node_name))
	if existing != null:
		return existing
	var node: Node
	match kind:
		"hbox": node = HBoxContainer.new()
		"vbox": node = VBoxContainer.new()
		"panel": node = PanelContainer.new()
		"margin": node = MarginContainer.new()
		"vsep": node = VSeparator.new()
		_: node = Control.new()
	node.name = node_name
	parent.add_child(node)
	return node


## An expanding gap inside a box container.
static func _spacer(parent: Node, node_name: String) -> Control:
	var gap := _new_node(parent, node_name, "control") as Control
	if gap != null:
		gap.size_flags_horizontal = GROW
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


## The other half of a box, for a recipe that wants a column laid out as a row or
## the other way round.
##
## Godot will not flip a `VBoxContainer`, so this makes the sibling class next to
## it and keeps the children in step with it on every frame. `source` is left in
## place and empty: nothing here deletes a node, and a script that rebuilds its
## children rebuilds them into the box it has always known about, from where the
## next frame collects them.
static func _transpose(source: Control, parent: Node, node_name: String,
		vertical: bool) -> BoxContainer:
	if source == null or parent == null:
		return null
	var box := _new_node(parent, node_name, "vbox" if vertical else "hbox") as BoxContainer
	if source.get_child_count() > 0:
		# A fresh batch has landed in the original. Whatever is in the transposed
		# copy is the batch before it, and the script that made it has already
		# forgotten it, so it goes.
		for stale in box.get_children():
			if stale.get_meta("showroom_transposed", false):
				box.remove_child(stale)
				stale.queue_free()
		for child in source.get_children():
			child.set_meta("showroom_transposed", true)
			_move(child, box)
	return box


## Hold the roster open.
##
## `lobby.gd` starts it folded, and is right to: the heading already answers "is
## everyone here yet" and the count keeps counting while the list is away. A
## recipe that gives the panel a column of its own is the one arrangement where
## that default is wrong -- a full-height sheet of glass with one heading in it.
##
## Both halves are needed. The boolean is what `_refresh_surface` reads the next
## time the roster changes; the visibility and the glyph are what hold between
## those refreshes, which are not every frame.
static func _unfold_roster(lobby: Node, scroll: Control, fold: Control) -> void:
	lobby.set("_players_open", true)
	_show(scroll, true)
	_flags(scroll, GROW, GROW)
	if fold is Button:
		(fold as Button).text = "▾"


## Unfold the lobby's chat.
##
## `ChatPanel` in `reveal_on_focus` mode is a line edit until the caret is in it
## (`_apply_reveal`), which is right in the shipping lobby and useless in a
## photograph of a recipe that gives the panel a height: a 220 px box with one
## input box stretched down it says nothing about where chat should live. The
## range already pushes four real lines into the log, so this shows them.
static func _unfold_chat(chat: Control) -> void:
	if chat == null:
		return
	_show(_c(chat, "Heading"), true)
	_show(_c(chat, "Log"), true)
	chat.size_flags_vertical = FILL


## Give the score line a width, because it does not have one of its own.
##
## `ScoreLine` is a `RichTextLabel` whose text is `[center]...[/center]`, so the
## HUD centres it by writing bbcode rather than by anchoring anything — which
## means "left-align it" is "make its box no wider than its text", not a property
## to flip. A `RichTextLabel` reports a minimum width of **1**, though, so
## `SHRINK_BEGIN` alone gives it a one-character column 294 px tall. 240 is wide
## enough for the longest score this HUD writes and narrow enough that the
## centring inside it reads as the corner.
static func _shrink_score(score: Control) -> void:
	if score == null:
		return
	score.custom_minimum_size.x = 240
	score.size_flags_horizontal = BEGIN


static func _flags(c: Control, horizontal: int, vertical: int = -1) -> void:
	if c == null:
		return
	c.size_flags_horizontal = horizontal
	if vertical >= 0:
		c.size_flags_vertical = vertical


static func _align(c: Control, value: int) -> void:
	if c != null and c is BoxContainer:
		(c as BoxContainer).alignment = value


static func _separation(c: Control, value: int) -> void:
	if c != null:
		c.add_theme_constant_override("separation", value)


static func _show(c: Control, shown: bool) -> void:
	if c != null:
		c.visible = shown


## Height a control would like to be, for the recipes that say "to content".
static func _content_height(c: Control) -> float:
	return maxf(c.get_combined_minimum_size().y, 1.0) if c != null else 0.0


## A copy of the stylebox this control is currently getting from the theme, with
## the override cleared first so the copy always tracks the *candidate* theme
## rather than whatever this function put there on the previous frame.
static func _restyle(c: Control, item: String, type: String) -> StyleBoxFlat:
	if c == null:
		return null
	c.remove_theme_stylebox_override(item)
	var base := c.get_theme_stylebox(item, type) as StyleBoxFlat
	if base == null:
		return null
	return base.duplicate() as StyleBoxFlat


# -------------------------------------------------------------------- menu ---
#
# Tree: MainMenu/UI/Root/{SideScrim, FootScrim, Column/Stack{Wordmark{Title,
# Rule,Tagline}, GapA, NameBlock{NameCaption,NameEdit}, GapB, Nav{HostButton,
# JoinButton, JoinPanel/Row{CodeEdit,ConnectButton}, SettingsButton, QuitButton},
# GapC, Notice}, Version, Settings}
#
# `main_menu.gd` hides `JoinPanel` and `Notice` in `_ready`, so both are carried
# by these recipes without ever being visible in a `menu` shot. They are moved
# with the rest rather than left behind: the arrangement has to be the one that
# would hold when the join row opens, not only the one that looks tidy shut.

static func _menu(layout: String, menu: Node) -> void:
	var ui := menu.get_node_or_null("UI/Root") as Control
	if ui == null:
		return
	var column := _c(ui, "Column")
	var stack := _c(ui, "Stack")
	var wordmark := _c(ui, "Wordmark")
	var title := _c(wordmark, "Title")
	var rule := _c(wordmark, "Rule")
	var tagline := _c(wordmark, "Tagline")
	var name_block := _c(ui, "NameBlock")
	var caption := _c(name_block, "NameCaption")
	var name_edit := _u(menu, "NameEdit")
	var nav := _c(ui, "Nav")
	var join_panel := _u(menu, "JoinPanel")
	var notice := _u(menu, "Notice")
	var version := _u(menu, "Version")
	var side_scrim := _c(ui, "SideScrim")
	var foot_scrim := _c(ui, "FootScrim")
	var gap_b := _c(ui, "GapB")
	var buttons: Array[Control] = []
	for named: String in ["HostButton", "JoinButton", "PracticeButton",
			"SettingsButton", "QuitButton"]:
		var button := _u(menu, named)
		if button != null:
			buttons.append(button)

	match layout:
		"centred":
			# The Column takes the whole screen and the Stack is centred in it,
			# so the wordmark and the nav share one axis down the middle.
			_rect(column, FULL, _box(0, 0, 0, 0))
			column.add_theme_constant_override("margin_left", 0)
			column.add_theme_constant_override("margin_right", 0)
			_align(stack, BoxContainer.ALIGNMENT_BEGIN)
			column.add_theme_constant_override("margin_top", 150)
			for child in stack.get_children():
				_flags(child as Control, MIDDLE)
			_flags(wordmark, MIDDLE)
			if title != null:
				title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			if tagline != null:
				tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_flags(rule, MIDDLE)
			for button in buttons:
				(button as Button).alignment = HORIZONTAL_ALIGNMENT_CENTER
			_flags(nav, MIDDLE)
			_flags(join_panel, MIDDLE)
			_flags(notice, MIDDLE)

			# "Nav starts at ~55% of the height", solved rather than guessed:
			# the gap above it is nudged toward the answer once per frame and is
			# there within a handful of them. A hardcoded number would be right
			# for one font and wrong for the next.
			if gap_b != null and nav != null and ui.size.y > 0.0:
				var want := ui.size.y * 0.55
				var have := nav.global_position.y
				gap_b.custom_minimum_size.y = clampf(
					gap_b.custom_minimum_size.y + (want - have), 0.0, 420.0)

			# The name field leaves the column for the corner it would have in a
			# game that asks for it once.
			_move(name_block, ui)
			_rect(name_block, BOTTOM_LEFT, _box(40, -120, 340, -30))
			if name_edit != null:
				name_edit.custom_minimum_size.x = 0
			_rect(version, BOTTOM_RIGHT, _box(-280, -56, -40, -30))
			if version != null:
				version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

		"bottombar":
			# The wordmark keeps the corner it has; everything you can press
			# moves to one bar along the foot, which is where a controller UI
			# would put it.
			column.add_theme_constant_override("margin_top", 120)
			_align(stack, BoxContainer.ALIGNMENT_BEGIN)
			_rect(column, LEFT_EDGE, _box(112, 0, 760, 0))

			# The nav list becomes the bar: the same five buttons in a box that
			# runs the other way. `%HostButton` and friends keep resolving,
			# because a unique name belongs to the owner and not to the parent.
			var bar := _transpose(nav, ui, "NavBar", false)
			_rect(bar, BOTTOM_WIDE, _box(40, -136, -40, -48))
			_separation(bar, 36)
			_align(bar, BoxContainer.ALIGNMENT_BEGIN)
			_show(nav, false)
			# The name field is the left end of that bar, compact, and the two
			# gaps either side of the buttons are what centre them in the rest of
			# it rather than leaving them jammed against the field.
			_move(name_block, bar, 0)
			_move(_spacer(bar, "BarGapA"), bar, 1)
			_spacer(bar, "BarGapB")
			name_block.custom_minimum_size.x = 260
			_flags(name_block, FILL, MIDDLE)
			if name_edit != null:
				name_edit.custom_minimum_size.x = 0
			for button in buttons:
				_flags(button, FILL, MIDDLE)
			_flags(join_panel, FILL, MIDDLE)

			_rect(version, BOTTOM_RIGHT, _box(-280, -178, -40, -152))
			if version != null:
				version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_show(side_scrim, false)
			_show(foot_scrim, true)

		"rightcolumn":
			# The mirror. Everything that was ragged-right is ragged-left, which
			# is the half of this that is easy to leave out and the half that
			# makes it read as a design rather than as a column that slid.
			_rect(column, RIGHT_EDGE, _box(-688, 0, -40, 0))
			if title != null:
				title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			if tagline != null:
				tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			if caption != null:
				caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_flags(rule, END)
			_flags(nav, END)
			_flags(name_block, END)
			_flags(notice, END)
			for button in buttons:
				(button as Button).alignment = HORIZONTAL_ALIGNMENT_RIGHT
			if side_scrim is TextureRect:
				(side_scrim as TextureRect).flip_h = true
			_rect(version, BOTTOM_LEFT, _box(40, -56, 280, -30))
			if version != null:
				version.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

		"card":
			# One card, left of centre, with the backdrop free on the right.
			var card := _new_node(ui, "LayoutCard", "panel") as PanelContainer
			card.theme_type_variation = &"CardPanel"
			var pad := _new_node(card, "LayoutCardPad", "margin") as MarginContainer
			for side: String in ["left", "right", "top", "bottom"]:
				pad.add_theme_constant_override("margin_" + side, 28)
			_move(stack, pad)
			_align(stack, BoxContainer.ALIGNMENT_CENTER)
			# 460 of card is 364 of content once the CardPanel's own padding and
			# the margin above are paid for, so the two 420-wide minimums in the
			# scene have to come off or the card is wider than it was asked for.
			nav.custom_minimum_size.x = 0
			if name_edit != null:
				name_edit.custom_minimum_size.x = 0
			# Without this the field shrinks to the width of the word in it: the
			# scene pins the block to SHRINK_BEGIN because it was a 420 px field
			# in a 648 px column, and inside a card it has to fill instead.
			_flags(name_block, FILL)
			_flags(nav, FILL)
			_separation(nav, 10)
			for button in buttons:
				button.theme_type_variation = &"Button"
				(button as Button).alignment = HORIZONTAL_ALIGNMENT_LEFT
				_flags(button, FILL)
			var height := _content_height(card)
			_rect(card, LEFT_MIDDLE, _box(48, -height * 0.5, 508, height * 0.5))
			_show(side_scrim, false)
			_show(foot_scrim, false)


# ------------------------------------------------------------------- lobby ---
#
# Tree: Lobby/UI/Root/{TopScrim, FootScrim, Header{LeaveButton,Title,Spacer,
# InviteChip}, PanelStack{Players, MatchSettings, Chat}, WeaponRow{WeaponPicker,
# WeaponBlurb}, SkinRow{SkinCaption,SkinPicker}, Footer{TeamRow, Spacer,
# GateHint, ReadyButton, StartButton}}
#
# `lobby.gd` fights back, which is why every one of these is re-applied per
# frame: `_refresh_surface` rewrites the size flags on Players and MatchSettings
# on every roster change, and `_rebuild_weapon_picker` frees and rebuilds the
# strip's buttons.
#
# In `lobby_full` the range opens a seven-player free-for-all as the host, so
# `TeamRow` is hidden (no teams) and `ReadyButton` is hidden (the host starts,
# it does not ready up). Both are placed by these recipes anyway, and both are
# invisible in the shots for reasons that are the screen's, not the layout's.

static func _lobby(layout: String, lobby: Node) -> void:
	var ui := lobby.get_node_or_null("UI/Root") as Control
	if ui == null:
		return
	var players := _u(lobby, "Players")
	var settings := _u(lobby, "MatchSettings")
	var chat := _u(lobby, "Chat")
	var weapon_row := _u(lobby, "WeaponRow")
	var weapon_picker := _u(lobby, "WeaponPicker")
	var weapon_blurb := _u(lobby, "WeaponBlurb")
	var skin_row := _u(lobby, "SkinRow")
	var footer := _c(ui, "Footer")
	var team_row := _u(lobby, "TeamRow")
	var gate_hint := _u(lobby, "GateHint")
	var ready_button := _u(lobby, "ReadyButton")
	var start_button := _u(lobby, "StartButton")
	var players_scroll := _u(lobby, "Scroll")
	var players_fold := _u(lobby, "PlayersFold")

	match layout:
		"rightrail":
			# One tall column on the right holds the config and the two things
			# you press at the end of it, so the right edge is "the match" and
			# the left is "who is here".
			var rail := _new_node(ui, "RightRail", "vbox") as VBoxContainer
			_separation(rail, 16)
			_rect(rail, RIGHT_EDGE, _box(-464, 96, -24, -24))
			_move(settings, rail, 0)
			# Re-asserted per frame against `_refresh_surface`, which sets this
			# back to FILL whenever the roster changes.
			_flags(settings, GROW, GROW)
			var actions := _new_node(rail, "RailActions", "vbox") as VBoxContainer
			_separation(actions, 10)
			_flags(actions, FILL, END)
			_move(gate_hint, actions, 0)
			_move(ready_button, actions, 1)
			_move(start_button, actions, 2)
			_flags(gate_hint, FILL)
			_flags(ready_button, FILL)
			_flags(start_button, FILL)

			_move(players, ui)
			_rect(players, TOP_LEFT, _box(24, 96, 344, 96 + _content_height(players)))
			_move(chat, ui)
			_unfold_chat(chat)
			_rect(chat, BOTTOM_LEFT, _box(24, -244, 504, -24))

			# The two strips stack centred in the width left of the rail, and
			# sit **above** the chat rather than beside it. Beside it does not
			# exist: the skin strip is a caption plus fourteen 44 px swatches,
			# 890 px of row, and the band between the chat and the rail is 632.
			_move(weapon_row, ui)
			_move(skin_row, ui)
			_rect(weapon_row, BOTTOM_LEFT, _box(24, -426, 1112, -312))
			_rect(skin_row, BOTTOM_LEFT, _box(24, -300, 1112, -254))
			_align(weapon_row, BoxContainer.ALIGNMENT_END)

		"bottomdock":
			# Everything you choose from is one dock along the foot; the panels
			# you read take the top and the right.
			var dock := _new_node(ui, "BottomDock", "hbox") as HBoxContainer
			_separation(dock, 18)
			_rect(dock, BOTTOM_WIDE, _box(24, -204, -24, -24))

			# **Two lines of picks, not one.** The recipe asked for skins, then
			# weapons, then the actions, left to right along one bar; that bar
			# wants 1944 px and the screen has 1552. The skin strip alone is 890
			# and cannot be made narrower without taking swatches off it, so it
			# takes a line of its own with the weapons under it, and the dock is
			# still one dock: picks at the left, actions at the right.
			var picks := _new_node(dock, "DockPicks", "vbox") as VBoxContainer
			_separation(picks, 6)
			_move(picks, dock, 0)
			_move(skin_row, picks, 0)
			_move(weapon_row, picks, 1)
			_align(skin_row, BoxContainer.ALIGNMENT_BEGIN)
			_align(weapon_row, BoxContainer.ALIGNMENT_BEGIN)
			_align(weapon_picker, BoxContainer.ALIGNMENT_BEGIN)
			if weapon_blurb != null:
				weapon_blurb.theme_type_variation = &"TinyLabel"
				(weapon_blurb as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

			_move(_spacer(dock, "DockGap"), dock, 1)
			_move(team_row, dock, 2)
			_move(gate_hint, dock, 3)
			_move(ready_button, dock, 4)
			_move(start_button, dock, 5)
			for child in dock.get_children():
				_flags(child as Control, (child as Control).size_flags_horizontal, MIDDLE)

			_move(settings, ui)
			_rect(settings, TOP_LEFT, _box(24, 96, 544, 476))
			_move(players, ui)
			_rect(players, TOP_LEFT, _box(566, 96, 886, 96 + _content_height(players)))
			_move(chat, ui)
			_unfold_chat(chat)
			_rect(chat, RIGHT_MIDDLE, _box(-444, -130, -24, 130))

		"leftrail":
			# The mirror of `rightrail` with a different job for the right edge:
			# the weapon strip stands up on its end there, which is the one
			# arrangement that lets the three props be big and out of the ring's
			# way at the same time.
			_move(settings, ui)
			_rect(settings, LEFT_EDGE, _box(24, 96, 464, -24))
			_flags(settings, GROW, GROW)

			_move(weapon_row, ui)
			var column := _transpose(weapon_picker, weapon_row, "WeaponColumn", true)
			_move(column, weapon_row, 0)
			_separation(column, 10)
			_align(column, BoxContainer.ALIGNMENT_CENTER)
			_show(weapon_picker, false)
			_align(weapon_row, BoxContainer.ALIGNMENT_CENTER)
			var tall := _content_height(weapon_row)
			# 276 rather than 236: the blurb under the three buttons is a single
			# unwrapped line and it is wider than they are.
			_rect(weapon_row, RIGHT_MIDDLE, _box(-300, -tall * 0.5, -24, tall * 0.5))

			_move(skin_row, ui)
			_rect(skin_row, TOP_WIDE, _box(488, 120, -56, 166))

			# Side by side, centred in the space right of the rail, and clear of
			# the footer rather than under it.
			_move(players, ui)
			_unfold_roster(lobby, players_scroll, players_fold)
			_rect(players, BOTTOM_LEFT, _box(600, -320, 1020, -100))
			_move(chat, ui)
			_unfold_chat(chat)
			_rect(chat, BOTTOM_LEFT, _box(1044, -320, 1464, -100))
			_rect(footer, BOTTOM_WIDE, _box(56, -90, -56, -26))

		"columns":
			# Two full-height columns with the room between them for the ring,
			# the strips and the things you press.
			# The columns start at 172 rather than 96: the skin strip is 890 px
			# wide and the gap between two 340/440 columns is 772, so the strips
			# keep the top band and the columns start under them.
			_move(players, ui)
			_rect(players, LEFT_EDGE, _box(24, 172, 364, -24))
			_flags(players, GROW, GROW)
			_unfold_roster(lobby, players_scroll, players_fold)

			_move(settings, ui)
			_rect(settings, RIGHT_EDGE, _box(-464, 172, -24, -24))
			_flags(settings, GROW, GROW)

			_move(chat, ui)
			_unfold_chat(chat)
			_rect(chat, BOTTOM_CENTRE, _box(-280, -224, 280, -24))
			_rect(footer, BOTTOM_CENTRE, _box(-380, -300, 380, -240))
			_align(footer, BoxContainer.ALIGNMENT_CENTER)
			var spacer := _c(footer, "Spacer")
			_flags(spacer, BEGIN)
			if spacer != null:
				spacer.custom_minimum_size.x = 0


# ---------------------------------------------------------------- settings ---
#
# Tree: SettingsPanel/{Scrim, Center/Card/Body{Header{Title,Spacer,CloseButton},
# Rule, Scroll/Gutter/Sections, Rule2, Footer{ResetButton,Spacer,DoneButton}}}

static func _settings(layout: String, panel: Node) -> void:
	var centre := panel.get_node_or_null("Center") as Control
	var card := panel.get_node_or_null("Center/Card") as PanelContainer
	if centre == null or card == null:
		return
	var scrim := panel.get_node_or_null("Scrim") as Control
	var body := _c(card, "Body")
	var header := _c(body, "Header")
	var title := _c(header, "Title")
	var scroll := _c(body, "Scroll")
	var sections := _u(panel, "Sections")
	var footer := _c(body, "Footer")
	var close := _u(panel, "CloseButton")

	match layout:
		"sheet":
			# A drawer off the right edge rather than a box in the middle: the
			# menu behind it stays legible, which is what a settings panel that
			# is one keypress deep should look like.
			_rect(centre, RIGHT_EDGE, _box(-620, 0, 0, 0))
			card.custom_minimum_size = Vector2(620, 900)
			var box := _restyle(card, "panel", "CardPanel")
			if box != null:
				box.corner_radius_top_left = 16
				box.corner_radius_bottom_left = 16
				box.corner_radius_top_right = 0
				box.corner_radius_bottom_right = 0
				card.add_theme_stylebox_override("panel", box)

		"page":
			# No box at all. The scrim does the separating and the type does the
			# rest, which is the `quiet` style's own argument taken to its end.
			_rect(centre, FULL, _box(0, 0, 0, 0))
			card.custom_minimum_size = Vector2(960, 860)
			card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			var dark := _restyle(scrim, "panel", "ScrimPanel")
			if dark != null:
				dark.bg_color.a = 0.92
				scrim.add_theme_stylebox_override("panel", dark)
			if title != null:
				title.theme_type_variation = &"DisplayLabel"
			# The close button is the screen's, not the column's.
			_move(close, panel)
			_rect(close, TOP_RIGHT, _box(-96, 30, -34, 74))
			_align(footer, BoxContainer.ALIGNMENT_END)
			var spacer := _c(footer, "Spacer")
			_flags(spacer, BEGIN)
			if spacer != null:
				spacer.custom_minimum_size.x = 0
			_flags(scroll, GROW, GROW)

		"tabs":
			# A section list down the left of one wider card. Static on purpose:
			# the question the shot answers is whether the shape is worth
			# wiring, not whether this file can wire it.
			card.custom_minimum_size = Vector2(1100, 680)
			var row := _new_node(body, "TabsRow", "hbox") as HBoxContainer
			_separation(row, 20)
			_flags(row, GROW, GROW)
			var at := 2
			if scroll != null and scroll.get_parent() == body:
				at = scroll.get_index()
			_move(row, body, at)
			var list := _new_node(row, "TabList", "vbox") as VBoxContainer
			list.custom_minimum_size.x = 220
			_flags(list, FILL, GROW)
			_separation(list, 4)
			_new_node(row, "TabRule", "vsep")
			_move(scroll, row, 2)
			_flags(scroll, GROW, GROW)
			_build_tabs(list, sections)


## One GhostButton per `SectionLabel` in the built settings list, the first of
## them shown as the one you are on. Built once — the labels do not change.
static func _build_tabs(list: VBoxContainer, sections: Control) -> void:
	if list == null or sections == null or list.get_child_count() > 0:
		return
	var first := true
	for child in sections.get_children():
		var label := child as Label
		if label == null or label.theme_type_variation != &"SectionLabel":
			continue
		var button := Button.new()
		button.name = "Tab" + label.text.capitalize()
		button.text = label.text
		button.theme_type_variation = &"GhostButton"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = first
		button.size_flags_horizontal = Control.SIZE_FILL
		list.add_child(button)
		first = false


# --------------------------------------------------------------------- hud ---
#
# Tree: HUD/Root/{TopBar{Clock,ScoreLine,TeamChip,LetterCall}, KillFeed,
# Crosshair, Banner, SpectateLabel, BottomRight{Elder,Letters,Lives,Health,
# Abilities}, Chat}
#
# The health bar is not in `hud.tscn`: `hud.gd::_build_health` makes it and drops
# it into that column immediately above the ability tiles, so it is found by name
# and treated as part of it, which is what it is.
#
# The column was `BottomCentre` when these recipes were written and photographed,
# and **the game has since taken `rightstack`** (D-118) — so the node is named
# for the corner it is actually in. These recipes are kept as the record of what
# was compared, and `rightstack` is now a description of the shipped HUD rather
# than a proposal.

static func _hud(layout: String, hud: Node) -> void:
	var ui := hud.get_node_or_null("Root") as Control
	if ui == null:
		return
	var top_bar := _c(ui, "TopBar")
	var clock := _u(hud, "Clock")
	var score := _u(hud, "ScoreLine")
	var kill_feed := _u(hud, "KillFeed")
	var bottom := _c(ui, "BottomRight")
	var lives := _u(hud, "Lives")
	var abilities := _u(hud, "Abilities")
	var health := _c(ui, "Health")
	var chat := _u(hud, "Chat")


	match layout:
		"corners":
			# Everything about you in one corner, everything about everyone else
			# in the others, and the middle of the screen left for aiming.
			_rect(bottom, BOTTOM_LEFT, _box(32, -268, 472, -32))
			_align(lives, BoxContainer.ALIGNMENT_BEGIN)
			_align(abilities, BoxContainer.ALIGNMENT_BEGIN)
			_flags(health, BEGIN)

			_rect(top_bar, TOP_LEFT, _box(32, 24, 552, 112))
			if clock != null:
				clock.add_theme_font_size_override("font_size", 36)
				(clock as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				_flags(clock, BEGIN)
			_shrink_score(score)

			_rect(chat, BOTTOM_RIGHT, _box(-456, -252, -34, -32))

		"rightstack":
			# The clock stays where a clock goes. Your own bar and tiles move to
			# the hand that is on the mouse, and the feed takes the empty left.
			_rect(bottom, BOTTOM_RIGHT, _box(-472, -268, -32, -32))
			_align(lives, BoxContainer.ALIGNMENT_END)
			_align(abilities, BoxContainer.ALIGNMENT_END)
			_flags(health, END)

			_rect(kill_feed, BOTTOM_LEFT, _box(32, -438, 518, -260))
			_align(kill_feed, BoxContainer.ALIGNMENT_END)
			if kill_feed != null:
				for row in kill_feed.get_children():
					_flags(row as Control, BEGIN)

		"compact":
			# One row at the foot instead of a column: bar, then tiles.
			#
			# **The bar and the tiles, and only those two.** The column also
			# carries the Elder countdown and the letter track, which draw
			# nothing most of a match and still ask for 224 px each; dragged into
			# the row they would push the visible half a hundred pixels off
			# centre with dead space. They keep the column, which keeps its
			# bottom-centre anchor directly above the new row.
			var row := _new_node(ui, "CompactRow", "hbox") as HBoxContainer
			_align(row, BoxContainer.ALIGNMENT_CENTER)
			_separation(row, 18)
			_rect(row, BOTTOM_CENTRE, _box(-420, -116, 420, -28))
			_move(health, row, 0)
			_move(abilities, row, 1)
			if health != null:
				health.custom_minimum_size.x = 220
				_flags(health, MIDDLE, MIDDLE)
			_flags(abilities, MIDDLE, MIDDLE)
			_rect(bottom, BOTTOM_CENTRE, _box(-220, -300, 220, -124))
			_align(bottom, BoxContainer.ALIGNMENT_END)
			_flags(lives, MIDDLE, MIDDLE)

			# Clock and score on one line, in the corner.
			var clock_row := _new_node(top_bar, "ClockRow", "hbox") as HBoxContainer
			_separation(clock_row, 14)
			_move(clock_row, top_bar, 0)
			_move(clock, clock_row, 0)
			_move(score, clock_row, 1)
			_flags(clock, BEGIN, MIDDLE)
			_shrink_score(score)
			_flags(score, BEGIN, MIDDLE)
			if clock != null:
				clock.add_theme_font_size_override("font_size", 36)
				(clock as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			_rect(top_bar, TOP_LEFT, _box(32, 24, 552, 112))

			# The feed keeps its corner and loses a size. A font override on the
			# column does not reach a Label that asks the theme itself, so the
			# rows are walked.
			if kill_feed != null:
				var tiny := kill_feed.get_theme_font_size("font_size", "TinyLabel")
				for node in kill_feed.find_children("*", "Label", true, false):
					(node as Label).add_theme_font_size_override("font_size", tiny)
