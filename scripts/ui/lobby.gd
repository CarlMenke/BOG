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
## **Independent panels, one refresh.** D-069 made the screen two surfaces that
## swapped: the header folded the whole panel stack away to show the weapon
## strip. It does not any more. The strip is always on, over the ring, and each
## of the three panels folds on its own — the config is the host's and starts
## open, the roster starts folded to its count, and chat is a line of input
## until somebody puts the caret in it.
##
## What D-069 decided and this keeps is the **mechanism**: a fold is a *view
## state that `_refresh` reads*, never a second update path. There are two
## booleans now instead of one, `_refresh_surface` is still one of the calls
## `_refresh` already makes, and it is still the only thing in this file that
## writes `visible` on anything in the stack. A roster change arriving while a
## panel is folded redraws the fold and the roster together and cannot leave one
## behind. The alternative is what the comment over `_refresh` has always said
## it is.
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
## been folded away to make room for it. It has to share now, and what it shares
## with is the sky: the strip lives in the 92 px band between the header and the
## topmost nameplate of an eight-Bog ring, and this number is what decides
## whether it fits there.
##
## **Above the Bogs, and above means above.** The first try put it in the wider
## band between the ring's feet and the panels, which cut four Bogs off at the
## chest and covered the very weapons in their hands -- the thing the ring is on
## screen to show, and the reason the pick is worth making. Over their heads
## there is nothing but sky and the empty middle of the header bar.
##
## The prop moved from **above** the name to **beside** it, which is what bought
## the picture back. D-076 put it above because that was free when the strip
## owned the screen; stacked, an icon costs its own height plus the caption's,
## and getting the row under 120 px that way meant a 32 px prop — a picture too
## small to be the thing a player is choosing from, which is the one thing D-076
## asked of it. Side by side the row is as tall as the icon and no taller, so
## 56 px of prop fits in a band that 32 px did not.
##
## The `YOUR WEAPON` caption over the strip went with the same squeeze and is
## not missed. It was a dim grey line laid across whichever Bog was standing
## behind the middle of the ring, to say what three props, three names and one
## amber-lit button already say — which is exactly the "professionalise means
## add" move D-076 spent a page arguing against.
##
## **The band the strip sits in now starts at 10, not 44**, and the 56 survived
## that. The skin strip needs 40 px under the blurb and the ring's nameplates
## come down to 170 (see `SKIN_TILE`), which left 149 px for a weapon block that
## is 105 — so the whole stack moved up rather than the prop getting smaller.
## Shrinking it was the other way to find the room and it is the one D-076
## argued out of the project: a 32 px prop is a picture too small to be the thing
## a player is choosing from.
const WEAPON_ICON := 56

## A skin swatch, and the face inside it.
##
## **The size is set by what is behind the strip, not by what is in it.** The
## ring is what the lobby is on screen for, and a picker standing in front of the
## faces it is choosing between is the wrong way round — so the row takes the sky
## between the weapon blurb and the top of the ring, and nothing below it.
##
## Measured, through the backdrop's own camera, in base-viewport rows, by
## `tools/weapon_select.gd` on every run:
##
##   ring     highest nameplate    highest head
##   eight          170.2              182.6
##   five           169.5              183.8
##
## The row ends at **159**, which clears the lower of those by 10.5 px. It is a
## tight band and it is tight in both directions: the weapon block above it is
## 105 px of button and blurb, so the whole top band — weapons, blurb, skins —
## runs 10 to 159 and there is nowhere for a fourth thing to go. That is why the
## weapon strip moved up from 44: not taste, arithmetic. Anything that grows the
## weapon prop, the blurb or a swatch comes out of the 10.5.
##
## **The first cut was a 84x92 tile with the skin's name under it**, in a band at
## 150-272, and it stood in front of the ring: in an eight-Bog lobby it covered
## every plate and crowded the heads, which is the thing D-069 moved the weapon
## strip above the Bogs to avoid. What went was the per-tile name. The caption
## beside the strip says it instead, for whichever swatch the pointer or the
## caret is on — one name, where the eye already is, instead of fourteen laid
## across the Bogs' faces.
##
## `SKIN_TILE` is the swatch's *minimum*; the theme's button margins make it 44
## wide in practice, so fourteen of them 4 apart come to 668 px in the 1488
## between the margins, and **the strip does not scroll and must not have to.** A
## horizontally scrolling strip was the fallback if they would not fit, and it
## would have put some of the fourteen behind a gesture on the one screen where
## "what can I be?" is the whole question being asked.
##
## The face is inset 2 px so that the button's own stylebox shows all round it,
## which is where "lit", "hovered" and "the caret is here" come from without this
## file drawing any of them.
const SKIN_TILE := Vector2(40, 40)
const SKIN_THUMB := 36

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
@onready var _panel_stack: Control = %PanelStack
@onready var _players_panel: Control = %Players
@onready var _players_scroll: Control = %Scroll
@onready var _players_fold: Button = %PlayersFold
@onready var _settings: MatchSettingsPanel = %MatchSettings
@onready var _weapon_row: Control = %WeaponRow
@onready var _weapon_picker: HBoxContainer = %WeaponPicker
@onready var _weapon_blurb: Label = %WeaponBlurb
@onready var _skin_row: Control = %SkinRow
@onready var _skin_picker: HBoxContainer = %SkinPicker
@onready var _skin_caption: Label = %SkinCaption

## The roster as it was on the previous refresh, so joins and leaves can be
## announced in chat. `Net` broadcasts the whole roster rather than a diff, so
## the diff has to be taken here or not at all.
var _known_peers: Array = []
var _copy_reset: SceneTreeTimer = null
## Which panels are unfolded. Read by `_refresh_surface`, written by the two
## toggles, and by nothing else.
##
## The roster starts **folded**, because the heading already answers the
## question it is usually asked — "is everyone here yet" is `7 / 8`, and the
## count keeps counting while the list is away. The config starts **open**,
## because the host opened this lobby in order to set it. A default that hid
## both would be a screen that opens with nothing on it.
var _players_open: bool = false
var _config_open: bool = true
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

	_leave_button.pressed.connect(_on_leave)
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

	_known_peers = Net.peer_ids()
	_chat.add_system("Welcome to the hollow. Say hello.")
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	# One key, one meaning: leave. D-069 gave Escape a "back out of the picker"
	# branch because the picker was a surface you could be lost on — the panels
	# were gone and it was not obvious which screen you were looking at. There is
	# no such surface now; the strip and the panels are on screen together, and a
	# fold leaves its own heading behind. Nothing is left to back out of.
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
	for peer_id: int in Net.peer_ids():
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
		})
	return entries


func _announce_roster_changes() -> void:
	var now := Net.peer_ids()
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
	for peer_id: int in Net.peer_ids():
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
## **Always on screen**, over the ring, between the Bogs' feet and the top of
## the panels. D-069 hid it behind a header toggle that swapped it for the whole
## panel stack; a weapon you have to go and find is a weapon most players never
## change, and the ring right above the strip is the thing that makes the pick
## worth making.
## Untinted, unlike that one: a team button wears its team colour because the
## colour *is* the answer, and a weapon has no colour to be.
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

## One swatch per skin on one short line under the weapon blurb, rebuilt from the
## roster the way everything else on this screen is.
##
## **One line, above the ring, and nothing below it.** The lobby is a room full
## of real Bogs and the strip is a picker *for* them; a picker standing in front
## of the faces it is choosing between is the wrong way round. So the row is a
## caption and fourteen small swatches, 40 px tall in total, ending 10.5 px above
## the highest thing an eight-Bog ring puts on screen (`SKIN_TILE` has the
## measurements, and `tools/weapon_select.gd` takes them again on every run).
##
## **The names moved into the caption.** Fourteen names under fourteen swatches
## is fourteen lines of type laid across the Bogs; one name, beside the strip,
## where the eye already is, is the same information in the place it is being
## asked for. So the caption reads `YOUR SKIN · TOAD`, and follows the pointer or
## the caret onto whatever swatch it is over — which is how a name is discovered
## without printing all fourteen at once.
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


## One swatch: a 40 px face in a 44 px toggle button.
##
## The picture is a child rather than the button's `icon` so that the 2 px all
## round is the button's *own* stylebox showing through — which is where "lit",
## "hovered" and "the caret is here" come from without this file drawing any of
## them. It takes no mouse input, so the button underneath is still the whole
## swatch as far as a click, the caret and the theme are concerned.
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

	# The rim, inside the button's own frame: this one says "somebody else's",
	# and the button's states say "yours" and "the caret is here".
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	if held_by >= 0:
		var border := StyleBoxFlat.new()
		border.bg_color = Color(0, 0, 0, 0)
		border.set_border_width_all(2)
		border.border_color = UIPalette.team_colour(held_by)
		border.set_corner_radius_all(UIPalette.RADIUS)
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


## Lay out the stack: who is folded, and what a client is not shown at all.
##
## The only place in this file that writes `visible` on anything in the stack,
## which is the whole of what D-069 decided about this screen and the only part
## of that entry this revision keeps intact. Called from `_refresh`, so a roster
## change arriving mid-fold redraws both.
##
## The strip is not in here: it is always on.
func _refresh_surface() -> void:
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


## Fold one panel down to its heading, or let it back out.
##
## Taking the size flags with the fold is the half that is easy to forget and is
## the difference between a heading and a heading floating in a full-height
## sheet of glass: the stack is an `HBoxContainer` handing out the width by
## stretch ratio, so a folded panel has to stop asking for a share of it.
##
## **It shrinks downward.** The stack's box grows up from the footer now, and a
## folded panel sits at the bottom of it, so folding everything leaves a line of
## headings along the foot of the screen with whole Bogs standing above it --
## rather than a bar across their waists with an empty glade underneath, which
## is what `SHRINK_BEGIN` gave and is the one thing a client saw.
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
	for peer_id: int in Net.peer_ids():
		if peer_id != 1 and not Net.is_ready(peer_id):
			return "Waiting on %s." % Net.player_name(peer_id)
	if Net.config.mode == MatchConfig.Mode.TEAMS:
		if Net.config.random_teams:
			return "Random teams need at least two Bogs." if Net.player_count() < 2 else ""
		var occupied := {}
		for peer_id: int in Net.peer_ids():
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
