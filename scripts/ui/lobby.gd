extends Node3D
## The room everyone waits in (PLAN 1.4): who is here, what the match will be,
## and the code that gets your friends in.
##
## Like the menu, the root is a `Node3D` — the roster is not only a list of
## names, it is a ring of real Bogs standing round the fire behind the panels,
## wearing the same nameplates you will be reading across the island in a
## minute (PLAN 1.5). The list and the ring are driven from the same
## `Net.players` dictionary, so they cannot disagree.
##
## Nothing here is authoritative. Every mutation is a request to `Net`, which is
## host-authoritative and rebroadcasts the whole roster; this screen only ever
## renders what came back. That is why `_refresh` is safe to call from every
## signal that could possibly have changed anything.
##
## **Two screens, and the second one is a page.** The lobby proper is a right
## rail (the match, and the two things you press at the end of it), a left
## column (who is here, and what they are saying) and the ring between them.
## Choosing a weapon and a body is not on it: that is the **Weapon and
## Character** page, opened from the header, and while it is open the camera
## walks in to a portrait of your own Bog and everything but the invite chip
## gets out of the way.
##
## Which is a surface that swaps — the thing D-069 took *out* of this file. The
## difference is what is on the two sides of the swap and what it costs to be on
## the wrong one. D-069's toggle hid the weapon strip behind the panels and the
## panels behind the strip, so a player who wanted to read the match settings
## and change their weapon had to keep pressing a button to see the other half
## of one screen. This swap is the other way up: the lobby is complete on its
## own — nothing on it is hidden by the page — and the page is a thing you go to
## once, do, and come back from, like the settings dialog over the menu. It also
## buys the thing neither layout had: at eight metres a Bog is 90 px tall, and
## "what do I look like" was being asked of a picture too small to answer it.
##
## **Independent panels, one refresh.** Each panel still folds on its own — the
## config is the host's and starts open, the roster starts open too now that the
## left column is a column rather than a third of a bar, and chat is a panel
## rather than a line of input for the same reason.
##
## What D-069 decided and this keeps is the **mechanism**: a fold is a *view
## state that `_refresh` reads*, never a second update path. There are three
## booleans now, the page's among them, `_refresh_surface` is still one of the
## calls `_refresh` already makes, and it is still the only thing in this file
## that writes `visible` on a panel, a rail or the page. A roster change
## arriving while the page is open redraws the page and the roster together and
## cannot leave one behind — which is exactly what makes "somebody joins while
## you are choosing a skin" a case nobody had to remember. The alternative is
## what the comment over `_refresh` has always said it is.
##
## The one fold this file does *not* own is the chat's, and the reason is worth
## stating: that panel's state is **where the caret is**, which the engine is
## already authoritative about. A boolean here mirroring it would be a copy that
## is wrong the first time focus moves by a route this file did not predict.

## Rows for players who have not arrived yet. Showing the empty seats is how a
## host knows at a glance whether they still have room, without doing arithmetic
## against a number in the settings panel.
const SHOW_EMPTY_SLOTS := true

## How tall the prop is on a weapon button.
##
## 84 under D-069, when the strip had the whole screen because the panels had
## been folded away to make room for it; 56 when the strip had to live in the
## 92 px band of sky between the header and an eight-Bog ring's topmost
## nameplate. It has neither constraint now — the strip is on a page of its own,
## along the foot, with nothing above it but the portrait — and 56 stays anyway.
##
## It stays because D-076's argument for it never depended on the band: a prop
## is on these buttons so that the thing a player picks here and the thing they
## see in the corner of the screen for the next ten minutes are **one picture**
## rather than two descriptions of it, and the ability bar's tile is the size it
## is. Growing this one would make the picker's picture and the HUD's picture
## disagree about what a spear looks like, which is the whole thing the shared
## bake exists to prevent.
##
## The prop is **beside** the name rather than above it, which is where the band
## put it and where it is staying: side by side the row is as tall as the icon
## and no taller, and three wide flat buttons along the foot of a portrait read
## as a shelf of weapons rather than as three towers.
const WEAPON_ICON := 56

## A skin cell, and the face inside it.
##
## **120, and the size is the feature.** For two decisions this was a 40 px
## swatch, because it lived on one line above the ring and the ring's nameplates
## came down to 170 px — fourteen of them 4 apart came to 668 px of the 1488
## between the margins, and anything taller covered the faces the strip was
## choosing between (D-109 has the measurements). That constraint is gone: the
## grid is on its own page, in the right third, with the portrait it is choosing
## for beside it rather than behind it. So the tile is now big enough to be a
## picture of a body instead of a coloured pip, which is what the owner asked
## for and what a 40 px swatch of a 2048² texture could never be.
##
## **Three columns of them.** Fourteen skins is five rows of three (the last
## short), 3 x 120 + 2 x 10 = **380 px** wide and 5 x 120 + 4 x 10 = **640 px**
## tall, in a column that is 380 wide and 756 tall at the base viewport — so it
## fits without scrolling today and the `ScrollContainer` it sits in is what
## makes a fifteenth skin, or a shorter window, somebody else's problem rather
## than a redesign (it was nine rows and scrolled for the hours the second batch
## was pickable, D-126/D-128). Four columns would have been 510 px of a 1600 px
## screen and left the portrait nowhere to stand; two would have scrolled at
## fourteen.
##
## `SKIN_THUMB` is the picture and it is the **whole** cell, not an inset one.
## The old swatch inset its face by 2 px so the button's own stylebox showed all
## round it as a rim; the thumbnails are cut out against transparency now
## (`tools/skin_thumbs.gd`), so the button's surface shows *through* the picture
## everywhere the Bog is not — which is the same affordance, in the whole cell
## rather than in a 2 px frame, and it is what makes hover and focus legible on
## a tile this size.
const SKIN_TILE := Vector2(120, 120)
const SKIN_THUMB := 120

## The glyph on a fold toggle. Down means "this is open and pressing me shuts
## it"; right means the opposite. One pair, on all three toggles, because three
## panels that fold differently is three things to learn.
const FOLD_OPEN := "▾"
const FOLD_SHUT := "▸"

@onready var _backdrop: BogBackdrop = %Backdrop
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _player_count: Label = %PlayerCount
@onready var _code_label: Label = %CodeLabel
@onready var _code_caption: Label = %CodeCaption
@onready var _copy_button: Button = %CopyButton
@onready var _chat: ChatPanel = %Chat
@onready var _team_picker: HBoxContainer = %TeamPicker
@onready var _team_row: Control = %TeamRow
@onready var _ready_button: Button = %ReadyButton
@onready var _start_button: Button = %StartButton
@onready var _gate_hint: Label = %GateHint
@onready var _leave_button: Button = %LeaveButton
@onready var _title: Label = %Title
@onready var _character_button: Button = %CharacterButton
@onready var _character_page: Control = %CharacterPage
@onready var _panel_stack: Control = %PanelStack
@onready var _right_rail: Control = %RightRail
@onready var _players_panel: Control = %Players
@onready var _players_scroll: Control = %Scroll
@onready var _players_fold: Button = %PlayersFold
@onready var _settings: MatchSettingsPanel = %MatchSettings
@onready var _weapon_row: Control = %WeaponRow
@onready var _weapon_picker: HBoxContainer = %WeaponPicker
@onready var _weapon_blurb: Label = %WeaponBlurb
@onready var _skin_row: Control = %SkinRow
@onready var _skin_picker: GridContainer = %SkinPicker
@onready var _skin_caption: Label = %SkinCaption

## The roster as it was on the previous refresh, so joins and leaves can be
## announced in chat. `Net` broadcasts the whole roster rather than a diff, so
## the diff has to be taken here or not at all.
var _known_peers: Array = []
var _copy_reset: SceneTreeTimer = null
## Which panels are unfolded. Read by `_refresh_surface`, written by the two
## toggles, and by nothing else.
##
## The roster starts **open**. It started folded while the three panels shared
## one bar along the foot and a full list was a third of the screen's width
## spent on eight short rows; the left column is a column now, 480 px wide and
## full height, and the eight rows fit in the top 380 of it with the chat at the
## bottom and the ring standing in the gap between them. A panel that opens
## folded in a layout with room for it open is a click the player has to make
## every time they arrive. The config starts **open** too, because the host
## opened this lobby in order to set it.
var _players_open: bool = true
var _config_open: bool = true
## Whether the Weapon and Character page is up. The third view state, read by
## `_refresh_surface` exactly as the two folds are, written by the header button
## and by `_on_leave`, and by nothing else.
##
## It is the only one of the three that anything outside this file can see,
## because opening the page also walks the backdrop camera in — so the boolean
## and `BogBackdrop.focus_on_local` are written on adjacent lines in
## `_set_character_page` and nowhere else.
var _character_open: bool = false
## Set while `_rebuild_weapon_picker` is writing the strip's buttons, so the
## focus and toggle signals that causes are not read back as picks. The match
## settings panel keeps an `_applying` flag for exactly this reason and this is
## the same trap: `grab_focus` on the button for the weapon you already have
## emits `focus_entered`, which would ask for it again on every single refresh.
var _writing_picker: bool = false
## Which skin the caption is naming because the pointer or the caret is on its
## swatch, or -1 for "nobody is pointing at anything, say what is being worn".
##
## A *view* state, like the two folds above it, and read by exactly one function
## (`_write_skin_caption`). It is not routed through `_refresh` for the one
## reason a fold is: refreshing rebuilds the strip, and rebuilding the strip
## frees the swatch the pointer is sitting on.
var _named_skin: int = -1


func _ready() -> void:
	SceneFlow.release_cursor("lobby")

	# Reaching the lobby without a session means something tore the session down
	# between the menu handing off and this scene loading. There is nothing to
	# show, so go back rather than render an empty room.
	if not Net.in_session:
		UIState.post_notice("Lobby closed", "The session ended before the lobby opened.")
		SceneFlow.go_to_menu()
		return

	# One connection, not two. The header's first button is LEAVE on the lobby
	# and BACK on the page, and the spec for it is "the same button, relabelled
	# and rewired" — but rewiring a signal on a view change is a second place
	# for the two states to disagree, and the failure is a button that leaves
	# the session when the player meant to close a picker. `_on_leave` reads the
	# one boolean instead.
	_leave_button.pressed.connect(_on_leave)
	_character_button.pressed.connect(_on_character)
	_players_fold.pressed.connect(_on_players_fold)
	_settings.fold_requested.connect(_on_config_fold)
	_copy_button.pressed.connect(_on_copy)
	_ready_button.toggled.connect(_on_ready_toggled)
	_start_button.pressed.connect(_on_start)
	_chat.submitted.connect(Net.send_chat)

	Net.roster_changed.connect(_refresh)
	Net.config_changed.connect(_refresh)
	Net.chat_received.connect(_on_chat)
	Net.left_lobby.connect(_on_left_lobby)
	Net.join_failed.connect(_on_join_failed)
	Net.match_start_requested.connect(_on_match_start)
	# A rematch is a match start for anybody who is already in here (D-044).
	# The host's REMATCH is pressed on a results screen, but a client's results
	# screen has a BACK TO LOBBY button and nothing else, so by the time the
	# broadcast lands some of the lobby is usually standing in this scene. Only
	# the HUD used to listen, so they were left here while the host waited out
	# `ARENA_READY_TIMEOUT` and then started without them.
	Net.rematch_requested.connect(_on_match_start)

	# `human_ids` throughout this file, never `peer_ids`: the practice range
	# puts dummies on the roster and the lobby is a list of people (D-112).
	_known_peers = Net.human_ids()
	_chat.add_system("Welcome to the hollow. Say hello.")
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	# One key, one meaning: **back out of where you are**. On the lobby that is
	# the session; on the Weapon and Character page it is the page. D-069 took
	# this branch out because the surface it backed out of had been taken out
	# with it; there is a surface again, and a page you can only leave by finding
	# a button in the header is a page the one key everybody presses does nothing
	# on.
	#
	# Which is `_on_leave`'s branch, not a second one here, so there is exactly
	# one answer to "what does going back mean right now" and the button and the
	# key both read it.
	#
	# The one place Escape still means something else is inside the chat box, and
	# `ChatPanel` takes it there, on the focused control, before it ever reaches
	# this handler.
	_on_leave()


# ------------------------------------------------------------------ refresh ---

## One function for the whole screen. Every signal that could have changed
## anything calls this, because the alternative — a targeted updater per signal —
## is a dozen partial refreshes and one of them is always missing a case.
func _refresh() -> void:
	# The page is a portrait of **your own** Bog, so it cannot outlive your row.
	# A host who kicks you, or a session that ends under you, arrives here as a
	# roster without you in it; the page would otherwise stay up with the camera
	# aimed at whoever inherited your slot. Closed here rather than in a handler
	# on one of the ways it can happen, because there are several and this is the
	# place they all come through.
	if _character_open and not Net.has_player(Net.local_id()):
		_set_character_page(false)
	_announce_roster_changes()
	_rebuild_player_list()
	_rebuild_team_picker()
	_rebuild_weapon_picker()
	_rebuild_skin_picker()
	_refresh_invite()
	_refresh_actions()
	_refresh_surface()
	_backdrop.set_roster(_backdrop_entries())


func _backdrop_entries() -> Array:
	var entries: Array = []
	var teams := _teams_are_picked()
	for peer_id: int in Net.human_ids():
		entries.append({
			"name": Net.player_name(peer_id),
			"team": Net.player_team(peer_id) if teams else MatchConfig.TEAM_NONE,
			# Straight from the roster, with no "is it mine" branch: the ring
			# shows eight people's picks and not one, which is the whole reason
			# the weapon went into the roster row rather than into a local
			# variable somewhere (D-069).
			"weapon": Net.player_weapon(peer_id),
			# And the body, from the same place and for the same reason — with
			# the one difference that in Teams "the same place" is the *team's*
			# entry rather than this row's, which is `Net.skin_for`'s whole job.
			# The ring is where a team finds out what it looks like: one member
			# presses a tile and four Bogs change together.
			"skin": Net.skin_for(peer_id),
			# Which of these is the person at this keyboard, so the backdrop can
			# aim the Weapon and Character page's camera at the right slot. A
			# column of the roster like the three above it, for their reason: the
			# ring is driven from the roster and nothing else, and the backdrop
			# Bogs carry peer ids that are in no roster at all, so asking `Net`
			# out there would find nothing to answer with.
			"local": peer_id == Net.local_id(),
		})
	return entries


func _announce_roster_changes() -> void:
	var now := Net.human_ids()
	for peer_id: int in now:
		if not _known_peers.has(peer_id):
			_chat.add_system("%s joined." % Net.player_name(peer_id))
	for peer_id: int in _known_peers:
		if not now.has(peer_id):
			# The name is gone from the roster by now, so this can only ever say
			# that somebody left. Better than a stale name that might be wrong.
			_chat.add_system("A Bog left the lobby.")
	_known_peers = now


func _rebuild_player_list() -> void:
	for child in _player_list.get_children():
		child.queue_free()

	var teams := _teams_are_picked()
	for peer_id: int in Net.human_ids():
		_player_list.add_child(_player_row(peer_id, teams))
	if SHOW_EMPTY_SLOTS:
		for i in maxi(0, Net.config.max_players - Net.player_count()):
			_player_list.add_child(_empty_row())

	_player_count.text = "%d / %d" % [Net.player_count(), Net.config.max_players]


func _player_row(peer_id: int, teams: bool) -> Control:
	var row := PanelContainer.new()
	row.theme_type_variation = "RowPanel"
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	row.add_child(box)

	# A bar rather than a dot: it reads as a team stripe down the row at a
	# glance, and in free-for-all it quietly becomes the "this is you" marker.
	var stripe := ColorRect.new()
	stripe.custom_minimum_size = Vector2(4, 20)
	stripe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if teams:
		stripe.color = UIPalette.team_colour(Net.player_team(peer_id))
	else:
		stripe.color = UIPalette.BOG if peer_id == Net.local_id() else UIPalette.LINE_STRONG
	box.add_child(stripe)

	var name_label := Label.new()
	name_label.text = Net.player_name(peer_id)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if peer_id == Net.local_id():
		name_label.add_theme_color_override("font_color", UIPalette.BOG)
	box.add_child(name_label)

	if peer_id == 1:
		var host_tag := Label.new()
		host_tag.theme_type_variation = "TinyLabel"
		host_tag.text = "HOST"
		host_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(host_tag)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	# What they are bringing, in the row as well as in the ring (D-069). The ring
	# is the better read and is the reason the feature is shaped the way it is,
	# but eight Bogs at four metres is not a list you can scan — and "who else
	# took the sword" is a question a player asks before they ready up.
	var weapon := Label.new()
	weapon.theme_type_variation = "TinyLabel"
	weapon.text = Loadout.weapon_name(Net.player_weapon(peer_id)).to_upper()
	weapon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(weapon)

	var status := Label.new()
	status.theme_type_variation = "SmallLabel"
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The host is never "not ready" — `Net.can_start_match` does not ask, since
	# the host is the one pressing Start.
	if peer_id == 1:
		status.text = ""
	elif Net.is_ready(peer_id):
		status.text = "READY"
		status.add_theme_color_override("font_color", UIPalette.GOOD)
	else:
		status.text = "WAITING"
	box.add_child(status)
	return row


func _empty_row() -> Control:
	var row := PanelContainer.new()
	row.theme_type_variation = "RowPanel"
	row.modulate = Color(1, 1, 1, 0.35)
	var label := Label.new()
	label.theme_type_variation = "SmallLabel"
	label.text = "Empty"
	row.add_child(label)
	return row


## Whether the roster's team column means anything in the lobby right now.
##
## Under random teams it does not: whatever it holds — the joiner's default, or
## the deal from the match everyone just came back from — is overwritten when
## Start is pressed. Painting it into the stripes and the backdrop would show a
## line-up nobody is going to play in, so the lobby draws those neutral and says
## the teams are dealt at start instead (D-048).
func _teams_are_picked() -> bool:
	return Net.config.mode == MatchConfig.Mode.TEAMS and not Net.config.random_teams


## One button per team, tinted with the colour that team's nameplates will use.
## Rebuilt rather than hidden when the team count changes, because the host can
## move it from two to eight while people are looking at it.
func _rebuild_team_picker() -> void:
	for child in _team_picker.get_children():
		child.queue_free()
	var teams := Net.config.mode == MatchConfig.Mode.TEAMS
	_team_row.visible = teams
	if not teams:
		return
	if Net.config.random_teams:
		# No buttons to press, because there is no choice to make. One line in
		# their place, in the same row, so the question "which team am I on?"
		# is answered where it is asked.
		var dealt := Label.new()
		dealt.theme_type_variation = "SmallLabel"
		dealt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dealt.text = "Random — %d teams dealt when the match starts" % Net.config.team_count
		_team_picker.add_child(dealt)
		return

	var mine := Net.player_team(Net.local_id())
	for team in Net.config.team_count:
		var button := Button.new()
		button.text = "Team %d" % (team + 1)
		button.custom_minimum_size.x = 104
		button.toggle_mode = true
		button.button_pressed = team == mine
		button.add_theme_color_override("font_color", UIPalette.team_colour(team))
		button.add_theme_color_override("font_hover_color", UIPalette.team_colour(team))
		button.add_theme_color_override("font_pressed_color", UIPalette.team_colour(team))
		button.pressed.connect(func() -> void: Net.set_team(team))
		_team_picker.add_child(button)


# ------------------------------------------------------------------ weapons ---

## One button per weapon, built exactly the way the team picker above is —
## because it is the same kind of control and it must behave like one (D-069).
##
## **Along the foot of the Weapon and Character page**, under the portrait of
## the Bog whose hands the pick lands in. D-069 hid it behind a header toggle
## that swapped it for the whole panel stack and D-107 pulled it out into a
## permanent strip over the ring, on the grounds that a weapon you have to go
## and find is a weapon most players never change. Both were arguments about
## *how far away the picture of the consequence was*, and the page settles it
## the other way: the consequence is now a metre-high Bog holding the thing,
## which is a better answer than a 56 px prop on a strip could ever be. The
## header button is one press from anywhere in the lobby, and the ring still
## carries everybody's pick on the screen you land on.
## Untinted, unlike the team picker: a team button wears its team colour because
## the colour *is* the answer, and a weapon has no colour to be.
##
## **Plain `Button`s in an `HBoxContainer`, which is the whole of the input
## work.** The lobby has never handled a key event of its own: every control on
## it is a focusable `Control` and Godot's `ui_left` / `ui_right` / `ui_accept`
## walk them, which is why the team picker works on a keyboard without a line of
## code about keyboards. Inventing a strip out of `TextureRect`s and an
## `_unhandled_input` would have been three new ways to be inconsistent with the
## rest of the screen. So the strip is buttons, and `ui_focus_next` reaches them
## from the rest of the lobby by tree order.
##
## Two ways to pick, and both are the *same* request. A click picks. Moving onto
## a button with the arrow keys or a stick also picks, which is the decision's
## own *"the Bog swaps weapons live as you move through it"* — a strip you have
## to arrow onto and then confirm would make the ring's Bog a preview of
## something that had not happened, and the point of the ring is that it shows
## what the roster says.
##
## Rebuilt rather than updated, like the team picker, so there is one code path
## and no partial one. `_writing_picker` is what keeps the rebuild from reading
## its own signals back as picks.
func _rebuild_weapon_picker() -> void:
	_writing_picker = true
	# Detached *and* freed, which the other two rebuilds in this file do not
	# bother with and this one has to. `queue_free` alone lands at the end of the
	# frame, so until then `get_children()` still returns the old buttons — and
	# unlike the player list and the team picker, this strip is read back
	# immediately, by the focus hand-off below. Without the detach, a rebuild
	# hands the caret to a button that is already on its way out.
	var had_focus := false
	for child in _weapon_picker.get_children():
		had_focus = had_focus or child.has_focus()
		_weapon_picker.remove_child(child)
		child.queue_free()

	var mine := Net.player_weapon(Net.local_id())
	var locked := Net.match_running
	for weapon: int in Loadout.all():
		var button := Button.new()
		button.text = Loadout.NAMES[weapon].to_upper()
		# The prop itself, above its name (D-076). The same baked photograph the
		# ability bar's first square wears, so the thing a player picks here and
		# the thing they see in the corner of the screen for the next ten minutes
		# are one picture rather than two descriptions of it. Three words on three
		# identical grey buttons is a list; three props is a choice.
		button.icon = AbilitySlot.art_for_weapon(weapon)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_constant_override("icon_max_width", WEAPON_ICON)
		button.add_theme_constant_override("h_separation", 10)
		button.custom_minimum_size = Vector2(196, WEAPON_ICON + 16)
		button.toggle_mode = true
		button.button_pressed = weapon == mine
		# The pick is fixed once the host presses Start, alongside the map and
		# the teams (D-069). The host refuses a request sent anyway; this is so
		# that a player who is still in here when a rematch goes out is told why
		# the buttons stopped answering rather than pressing one that does
		# nothing.
		button.disabled = locked
		button.pressed.connect(_on_weapon_chosen.bind(weapon))
		button.focus_entered.connect(_on_weapon_chosen.bind(weapon))
		_weapon_picker.add_child(button)

	_weapon_blurb.text = "The pick is locked once the match starts." if locked \
		else Loadout.blurb(mine)
	# Give the caret back to the strip if it was on it. Every roster change
	# rebuilds these three buttons — including the change *this player's own pick*
	# causes — so without this, choosing a weapon with the arrow keys would be the
	# last thing the arrow keys ever did: the button holding focus is freed a
	# frame later and focus goes nowhere.
	if had_focus:
		_focus_pick()
	_writing_picker = false


## Put the caret on the weapon that is currently picked.
##
## Only ever called with `_writing_picker` set, because `grab_focus` emits
## `focus_entered` and that signal is also a pick.
func _focus_pick() -> void:
	for child in _weapon_picker.get_children():
		var button := child as Button
		if button != null and button.button_pressed and not button.disabled:
			button.grab_focus()
			return


# -------------------------------------------------------------------- skins ---

## One cell per skin in a three-column grid down the right third of the Weapon
## and Character page, rebuilt from the roster the way everything else on this
## screen is.
##
## **Beside the body, not in front of it.** D-109 spent a page measuring this
## strip against the ring's nameplates because it was a picker standing in the
## same 1600 px the faces it was choosing between were standing in. On the page
## the two share the screen instead: the portrait holds the left, held there by
## `BogBackdrop`'s own arithmetic, and the grid holds the right 380 px. Nothing
## is measured against a nameplate any more, and the cell went 40 -> 120 because
## the only thing that was ever holding it at 40 was that argument.
##
## **The names are still in the caption.** Fourteen names under fourteen cells
## is fourteen lines of type in a column that has room for exactly three, and
## the caption is where "whose skin is this row changing" already has to be
## said. So it reads `YOUR SKIN · TOAD`, and follows the pointer or the caret
## onto whatever cell it is over — which is how a name is discovered without
## printing all fourteen at once.
##
## **Which question the strip is asking depends on the mode**, and the caption is
## also where that is said. In free-for-all a swatch changes *your* body and is a
## weapon pick in every respect. In Teams it changes *your team's* body —
## everyone on it, at once, and any member of the team may press it — because a
## skin is what a team looks like across the island and that is not a thing one
## player owns. The roster reads the same either way: `Net.skin_for` is the one
## function that knows, and the ring behind the strip shows the answer.
##
## **A skin another team holds is a disabled swatch with that team's colour on
## its rim.** Two teams in one body is the single thing this feature exists to
## prevent, and the host refuses the request — but a strip that let you press it
## and then quietly did nothing would make the host look broken. So the rule is
## drawn where it is about to be enforced, in the colour of the team enforcing
## it, which also answers "who has the toad, then?" without a second control.
##
## **Pressing picks; focus does not**, which is the one place this strip parts
## company with the weapon strip above it (D-069: "the Bog swaps weapons live as
## you move through it"). Two reasons, and both are about what a pick costs. A
## weapon is three buttons and your own hands; a skin is fourteen swatches, so
## arrowing from one end to the other would be fourteen requests and fourteen
## whole-roster broadcasts. And in Teams it is not your body being changed — the
## arrow keys would repaint four teammates fourteen times on the way past. What
## the caret *does* do is name the swatch it lands on, in the caption, so a
## keyboard reads the strip exactly as a pointer does.
func _rebuild_skin_picker() -> void:
	_writing_picker = true
	# Detached as well as freed, for `_rebuild_weapon_picker`'s reason: the focus
	# hand-off below reads the children back immediately, and `queue_free` alone
	# leaves the old swatches in `get_children()` until the end of the frame.
	var had_focus := false
	for child in _skin_picker.get_children():
		had_focus = had_focus or (child as Control).has_focus()
		_skin_picker.remove_child(child)
		child.queue_free()
	# Whatever the pointer was over is being freed with it.
	_named_skin = -1

	var teams := Net.teams_decided()
	var my_team := Net.player_team(Net.local_id())
	var mine := Net.skin_for(Net.local_id())
	var locked := Net.match_running
	for skin: int in Skins.all():
		# Which team is standing on this skin, if it is not mine. `-1` is "free".
		var held_by := -1
		if teams:
			for team in Net.config.team_count:
				if team != my_team and Net.team_skin(team) == skin:
					held_by = team
					break
		_skin_picker.add_child(_skin_swatch(skin, skin == mine, held_by, locked))

	_write_skin_caption()
	if had_focus:
		_focus_skin()
	_writing_picker = false


## The line beside the strip: whose body this row changes, and which one is being
## looked at.
##
## Its own function because it is written from two places that are not each
## other — the rebuild above, and the pointer or the caret moving across the
## swatches. A hover must not rebuild the strip (it would free the swatch the
## pointer is on, mid-hover), and a rebuild must not forget what is being
## pointed at. Nothing else in here writes this label.
func _write_skin_caption() -> void:
	var teams := Net.teams_decided()
	var my_team := Net.player_team(Net.local_id())
	# The swatch under the pointer or the caret, or failing that the body that is
	# actually being worn — so the line is never blank and never a guess.
	var shown := _named_skin if _named_skin >= 0 else Net.skin_for(Net.local_id())
	var whose := "YOUR SKIN"
	if Net.match_running:
		whose = "LOCKED"
	elif teams:
		whose = "TEAM %d'S SKIN" % (my_team + 1)
	_skin_caption.text = "%s · %s" % [whose, Skins.label(shown).to_upper()]

	# In that team's own colour — the same colour as their stripe in the roster
	# and their nameplates in the match, so "Team 2" here and "Team 2" out there
	# are one thing.
	if teams and not Net.match_running:
		_skin_caption.add_theme_color_override("font_color",
			UIPalette.team_colour(my_team))
	else:
		_skin_caption.remove_theme_color_override("font_color")

	# The sentence that used to be a second line on the strip. It is a rule about
	# who may press these, which is exactly what a tooltip on the thing that says
	# whose they are is for — and it costs the ring nothing.
	if Net.match_running:
		_skin_caption.tooltip_text = \
			"Locked from the start of the match until everyone is back in the lobby."
	elif teams:
		_skin_caption.tooltip_text = "Anyone on the team can change it."
	else:
		_skin_caption.tooltip_text = "Your own body. In Teams the skin is the team's."


## One cell: a 120 px cut-out of a Bog in a 120 px toggle button.
##
## The picture is a child rather than the button's `icon` so that the button's
## *own* stylebox is what the player sees behind it — 4% white at rest, 8%
## hovered, the accent wash pressed, and a focus ring when the caret is on it.
## The thumbnails are transparent outside the Bog, so that surface reads through
## the whole cell rather than as a 2 px rim, which is what a picker at this size
## needs: at 40 px a rim was the only thing there was room for, and at 120 px a
## rim around a 2048² body is a hairline nobody sees.
##
## **The three rims this file draws, and what each says.** The theme's button
## states cover "you are pointing at it" and "the caret is here"; what they
## cannot say is *whose body this is*, because that is roster state rather than
## input state. So: a **2 px accent border** on the skin being worn — the
## theme's pressed state is an 18% wash, which is legible on a bare button and
## invisible under a full-bleed photograph — and a **2 px team border** on one
## another team holds (D-109), in that team's own colour, which answers "who has
## the toad, then?" without a second control. No border is "free".
##
## The border carries no content margin, so a chosen cell and a plain one hold
## their picture at exactly the same size; a 2 px inset that appeared when you
## picked something would read as the tile flinching.
func _skin_swatch(skin: int, chosen: bool, held_by: int, locked: bool) -> Button:
	var swatch := Button.new()
	swatch.toggle_mode = true
	swatch.button_pressed = chosen
	swatch.custom_minimum_size = SKIN_TILE
	swatch.disabled = locked or held_by >= 0
	swatch.tooltip_text = "Team %d has this one" % (held_by + 1) if held_by >= 0 \
		else Skins.label(skin)
	swatch.pressed.connect(_on_skin_chosen.bind(skin))
	# Naming, not picking. `focus_entered` is deliberately *not* a request here
	# (see the header); all either of these does is move the name in the caption.
	swatch.mouse_entered.connect(_on_skin_named.bind(skin))
	swatch.focus_entered.connect(_on_skin_named.bind(skin))
	swatch.mouse_exited.connect(_on_skin_unnamed.bind(skin))
	swatch.focus_exited.connect(_on_skin_unnamed.bind(skin))

	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	var rim := Color(0, 0, 0, 0)
	if held_by >= 0:
		rim = UIPalette.team_colour(held_by)
	elif chosen:
		rim = UIPalette.AMBER
	if rim.a > 0.0:
		var border := StyleBoxFlat.new()
		border.bg_color = Color(0, 0, 0, 0)
		border.set_border_width_all(2)
		border.border_color = rim
		border.set_corner_radius_all(UIPalette.RADIUS)
		border.content_margin_left = 0
		border.content_margin_right = 0
		border.content_margin_top = 0
		border.content_margin_bottom = 0
		frame.add_theme_stylebox_override("panel", border)
	swatch.add_child(frame)

	var picture := TextureRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture = Skins.thumb_of(skin)
	picture.custom_minimum_size = Vector2(SKIN_THUMB, SKIN_THUMB)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Godot dims a disabled button's own text and nothing else, so a swatch made
	# of child controls would sit there at full brightness looking pressable. The
	# picture is dimmed by hand, which is also the difference between "taken" and
	# "locked": a held skin is dim behind a coloured rim, a locked one is just dim.
	# D-109 asks for 40% on a tile another team holds, and 0.42 is what that has
	# always been.
	if swatch.disabled:
		picture.modulate = Color(1, 1, 1, 0.42)
	frame.add_child(picture)
	return swatch


## The pointer or the caret arrived on a swatch: say its name in the caption.
func _on_skin_named(skin: int) -> void:
	if _named_skin == skin:
		return
	_named_skin = skin
	_write_skin_caption()


## ...and left it. Guarded on which swatch, because the pointer leaving one and
## entering the next arrives in that order and would otherwise blank the line
## every time it crossed a gap.
func _on_skin_unnamed(skin: int) -> void:
	if _named_skin != skin:
		return
	_named_skin = -1
	_write_skin_caption()


## Put the caret on the skin that is currently worn. `_focus_pick`'s twin, and
## safe for the same reason — except that here `grab_focus` is not also a pick,
## so this one is only about not dropping the caret through a rebuild.
func _focus_skin() -> void:
	for child in _skin_picker.get_children():
		var button := child as Button
		if button != null and button.button_pressed and not button.disabled:
			button.grab_focus()
			return


## Ask for a skin — for yourself in free-for-all, for your team in Teams.
##
## `_on_weapon_chosen`'s two guards, plus nothing: the "you already have it"
## guard is what keeps a rebuild's own `button_pressed` writes off the wire, and
## a swatch another team holds is disabled rather than checked here, because the
## authority on that is the host and this screen only ever renders what came back
## from it.
func _on_skin_chosen(skin: int) -> void:
	if _writing_picker or Net.match_running:
		return
	if skin == Net.skin_for(Net.local_id()):
		return
	Net.set_skin(skin)


## Lay out the screen: which of the two it is, who is folded, and what a client
## is not shown at all.
##
## The only place in this file that writes `visible` on a panel, a rail or the
## page, which is the whole of what D-069 decided about this screen and the part
## of that entry every revision has kept. Called from `_refresh`, so a roster
## change arriving mid-fold, or while the page is up, redraws all of it.
func _refresh_surface() -> void:
	# The page first, because everything under it is on screen or not according
	# to this one boolean. "Everything else hides except the invite chip": the
	# chip stays because the answer to "what is the code again" is the one thing
	# somebody is going to be asked for while they are in here doing something
	# else, and a page you have to leave to read it out is a page you leave.
	_character_page.visible = _character_open
	_panel_stack.visible = not _character_open
	_right_rail.visible = not _character_open
	# The button that opens the page is not on the page. It would be a control
	# whose only meaning is "you are already here".
	_character_button.visible = not _character_open
	# The header says which of the two screens this is, in the one place a
	# screen's name has ever been written on it, and the first button says what
	# going back does. Between them there is no state to be lost in, which is
	# what D-069 wanted from the Escape branch it could not keep.
	_title.text = "WEAPON AND CHARACTER" if _character_open else "LOBBY"
	_leave_button.text = "‹   BACK" if _character_open else "‹   LEAVE"

	_fold(_players_panel, _players_scroll, _players_open)
	_players_fold.text = FOLD_OPEN if _players_open else FOLD_SHUT

	# **Hidden from a client, not greyed out.** Editing has been host-gated since
	# this panel was written, so a client's copy was forty rows of dials that did
	# nothing, taking the widest column of the lobby to say "the host decides" —
	# which is a sentence, not a panel. The host still sees it, and still sees it
	# open, because setting it up is what they came here to do.
	#
	# What it costs is the client's read of the config, and that is a real loss:
	# `summary()` said in one line what match this was going to be. The gate hint
	# and the chat are where that has to come from until something puts it back.
	_settings.visible = Net.is_host
	_settings.set_folded(not _config_open)
	# `set_folded` writes `SIZE_FILL` on the open panel, which was right when the
	# stack was a fixed-height bar handing out width, and is wrong in a rail that
	# hands out **height**: FILL without EXPAND means "take your minimum", and the
	# panel's minimum is its heading — so the config would have opened as a card
	# the height of one line with the Start button floating under it. The rail
	# asks for the opposite and asks for it here, where the fold is read, rather
	# than by changing a shared panel's idea of what folding means.
	if _config_open:
		_settings.size_flags_vertical = Control.SIZE_EXPAND_FILL


## Fold one panel down to its heading, or let it back out.
##
## Taking the size flags with the fold is the half that is easy to forget and is
## the difference between a heading and a heading floating in a full-height
## sheet of glass: a container hands out its spare space to whatever asks for a
## share, so a folded panel has to stop asking.
##
## **It shrinks downward and leftward.** Both flags are written, because this
## same function is read by two containers that run in different directions: the
## left column is a `VBoxContainer` (so vertical is the one that matters, and
## `SHRINK_END` keeps a folded roster's heading where the heading was) and the
## right rail's panel is handed its width the same way. Writing only the axis
## the current layout cares about is how a fold stops working the next time a
## column becomes a row.
static func _fold(panel: Control, body: Control, open: bool) -> void:
	body.visible = open
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if open \
		else Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_FILL if open \
		else Control.SIZE_SHRINK_END


## The two toggles. Both do the same two things, and the second is the point:
## flip the boolean, then let the one refresh draw the consequence.
func _on_players_fold() -> void:
	_players_open = not _players_open
	_refresh()


func _on_config_fold() -> void:
	_config_open = not _config_open
	_refresh()


## The header's second button, and Escape's and BACK's shared answer.
##
## Flip the boolean and walk the camera; the one refresh draws the rest. The
## camera call lives here rather than in `_refresh_surface` for the one reason a
## fold's does not: `_refresh_surface` runs on every roster change, every config
## broadcast and every chat line, and asking for a 0.6 s tween forty times a
## minute would be a camera that never arrived. Opening the page is an *event*;
## being on it is a state.
func _set_character_page(open: bool) -> void:
	if _character_open == open:
		return
	_character_open = open
	_backdrop.focus_on_local(open)


func _on_character() -> void:
	_set_character_page(true)
	_refresh()


## Ask for a weapon, unless this is the rebuild talking to itself or the answer
## is already what the roster says.
##
## The second guard is what makes `focus_entered` safe to wire: arrowing onto the
## button for the weapon you already have is not a change, and a request per
## focus event would be a packet every time the strip was redrawn.
func _on_weapon_chosen(weapon: int) -> void:
	if _writing_picker or Net.match_running:
		return
	if weapon == Net.player_weapon(Net.local_id()):
		return
	Net.set_weapon(weapon)


func _refresh_invite() -> void:
	if Net.is_offline:
		# There is no socket, so there is no endpoint to encode. Saying so beats
		# printing a code that dials this machine's own LAN address and fails.
		_code_caption.text = "OFFLINE SESSION"
		_code_label.text = "no code"
		_copy_button.disabled = true
		return
	if not Net.is_host:
		# The code encodes the *host's* address; a client generating one from
		# its own IP would hand out a code that points at itself.
		_code_caption.text = "CONNECTED TO"
		_code_label.text = String(Settings.get_value("last_invite_code")).to_upper()
		_copy_button.disabled = false
		return
	# A public address that was typed and could not be used fails silently
	# otherwise: the fallback code is perfectly well-formed, it just does not
	# leave the building, and the host finds out when their friends cannot
	# join. So the problem takes the caption's place rather than sitting
	# beside it — there is one line here and this is the more urgent thing
	# for it to say.
	var problem := Net.invite_problem()
	if problem.is_empty():
		_code_caption.text = "%s INVITE CODE" % Net.invite_scope()
	else:
		_code_caption.text = problem
	_code_label.text = Net.invite_code()
	_copy_button.disabled = false


func _refresh_actions() -> void:
	var host := Net.is_host
	_start_button.visible = host
	_ready_button.visible = not host

	if not host:
		var am_ready := Net.is_ready(Net.local_id())
		_ready_button.set_pressed_no_signal(am_ready)
		_ready_button.text = "READY" if am_ready else "READY UP"
		# The primary fill is the thing to press next, so it moves off the
		# button once it has been pressed.
		_ready_button.theme_type_variation = &"Button" if am_ready else &"PrimaryButton"
		_gate_hint.text = "Waiting for the host to start." if am_ready \
			else "Ready up when you are set."
		return

	var can_start := Net.can_start_match()
	_start_button.disabled = not can_start
	_gate_hint.text = "" if can_start else _why_not_startable()


## Say what is blocking the start, in the order the host can fix it. A disabled
## button with no explanation is the single most common lobby complaint there
## is.
func _why_not_startable() -> String:
	if Net.player_count() < MatchConfig.MIN_PLAYERS:
		return "Nobody is here yet."
	for peer_id: int in Net.human_ids():
		if peer_id != 1 and not Net.is_ready(peer_id):
			return "Waiting on %s." % Net.player_name(peer_id)
	if Net.config.mode == MatchConfig.Mode.TEAMS:
		if Net.config.random_teams:
			return "Random teams need at least two Bogs." if Net.player_count() < 2 else ""
		var occupied := {}
		for peer_id: int in Net.human_ids():
			occupied[Net.player_team(peer_id)] = true
		if occupied.size() < 2:
			return "Everyone is on the same team."
	return ""


# ------------------------------------------------------------------ actions ---

func _on_copy() -> void:
	DisplayServer.clipboard_set(_code_label.text)
	_copy_button.text = "Copied"
	# A copy button that never acknowledges the copy gets pressed four times.
	if _copy_reset != null and _copy_reset.timeout.is_connected(_reset_copy_label):
		_copy_reset.timeout.disconnect(_reset_copy_label)
	_copy_reset = get_tree().create_timer(1.6)
	_copy_reset.timeout.connect(_reset_copy_label)


func _reset_copy_label() -> void:
	_copy_reset = null
	if is_instance_valid(_copy_button):
		_copy_button.text = "Copy"


func _on_ready_toggled(pressed: bool) -> void:
	Net.set_ready(pressed)


func _on_start() -> void:
	# The arena is built by another part of the project and may not exist yet.
	# Checking beats letting `SceneFlow` fail into a black screen with an error
	# only the console will ever see.
	if not ResourceLoader.exists(SceneFlow.ARENA):
		_gate_hint.text = "The island is not built yet (%s is missing)." % SceneFlow.ARENA
		return
	Net.request_match_start()


func _on_match_start() -> void:
	if not ResourceLoader.exists(SceneFlow.ARENA):
		UIState.post_notice("No island",
			"The host started a match, but this build has no arena scene yet.")
		SceneFlow.go_to_menu()
		return
	SceneFlow.go_to_arena()


func _on_leave() -> void:
	# **Back out of one thing at a time.** On the Weapon and Character page this
	# button says BACK and Escape means the same, and both come here: the page
	# closes and the lobby comes back with the camera walking out to the ring.
	# Only from the lobby itself does going back end the session — which is the
	# property that makes it safe for one key and one button to mean "back"
	# everywhere on this screen.
	if _character_open:
		_set_character_page(false)
		_refresh()
		return
	# Announce nothing: the player chose this, so the menu has no news for them.
	Net.leave_lobby(Net.Leave.LOCAL_REQUEST, "", false)
	SceneFlow.go_to_menu()


func _on_chat(peer_id: int, text: String) -> void:
	_chat.add_message(peer_id, text)


func _on_left_lobby(reason: Net.Leave, message: String) -> void:
	var described := UIState.describe_leave(reason, message)
	UIState.post_notice(String(described["title"]), String(described["body"]))
	SceneFlow.go_to_menu()


func _on_join_failed(message: String) -> void:
	UIState.post_notice("Disconnected", message)
	SceneFlow.go_to_menu()
