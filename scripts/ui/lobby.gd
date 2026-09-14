extends Node3D
## The room everyone waits in (PLAN 1.4): who is here, what the match will be,
## and the code that gets your friends in.
##
## Like the menu, the root is a `Node3D` — the roster is not only a list of
## names, it is a ring of real Gubs standing round the fire behind the panels,
## wearing the same nameplates you will be reading across the island in a
## minute (PLAN 1.5). The list and the ring are driven from the same
## `Net.players` dictionary, so they cannot disagree.
##
## Nothing here is authoritative. Every mutation is a request to `Net`, which is
## host-authoritative and rebroadcasts the whole roster; this screen only ever
## renders what came back. That is why `_refresh` is safe to call from every
## signal that could possibly have changed anything.
##
## **Two surfaces, one refresh** (D-069). The panel stack collapses to reveal the
## glade behind it with a weapon strip under the ring, because choosing a weapon
## and reading a lobby are two different things to be looking at — the user's own
## *"menu select should be different then the weapon select"*. The collapse is a
## **view state that `_refresh` reads**, not a second update path: `_picking` is
## one boolean, `_refresh_surface` is one of the five calls `_refresh` already
## makes, and nothing anywhere else touches `visible` on either surface. The
## alternative is what the comment over `_refresh` has always said it is.

## Rows for players who have not arrived yet. Showing the empty seats is how a
## host knows at a glance whether they still have room, without doing arithmetic
## against a number in the settings panel.
const SHOW_EMPTY_SLOTS := true

@onready var _backdrop: GubBackdrop = %Backdrop
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
@onready var _collapse_button: Button = %CollapseButton
@onready var _weapon_row: Control = %WeaponRow
@onready var _weapon_picker: HBoxContainer = %WeaponPicker
@onready var _weapon_blurb: Label = %WeaponBlurb

## The roster as it was on the previous refresh, so joins and leaves can be
## announced in chat. `Net` broadcasts the whole roster rather than a diff, so
## the diff has to be taken here or not at all.
var _known_peers: Array = []
var _copy_reset: SceneTreeTimer = null
## Which surface is showing: the panels, or the glade with the weapon strip in
## front of it (D-069). Read by `_refresh_surface` and written by one button.
var _picking: bool = false
## Set while `_rebuild_weapon_picker` is writing the strip's buttons, so the
## focus and toggle signals that causes are not read back as picks. The match
## settings panel keeps an `_applying` flag for exactly this reason and this is
## the same trap: `grab_focus` on the button for the weapon you already have
## emits `focus_entered`, which would ask for it again on every single refresh.
var _writing_picker: bool = false


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
	_collapse_button.pressed.connect(_on_collapse)
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
	# Escape backs out one surface at a time (D-069). With the picker open it
	# closes the picker; from the menu it leaves the lobby. The alternative — one
	# key that always leaves — makes the collapse a place you can fall out of the
	# session from, and the collapsed lobby is where a player is *least* sure
	# which screen they are on.
	if _picking:
		_on_collapse()
		return
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
			_chat.add_system("A Gub left the lobby.")
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
		stripe.color = UIPalette.GUB if peer_id == Net.local_id() else UIPalette.LINE_STRONG
	box.add_child(stripe)

	var name_label := Label.new()
	name_label.text = Net.player_name(peer_id)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if peer_id == Net.local_id():
		name_label.add_theme_color_override("font_color", UIPalette.GUB)
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
	# but eight Gubs at four metres is not a list you can scan — and "who else
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
## own *"the Gub swaps weapons live as you move through it"* — a strip you have
## to arrow onto and then confirm would make the ring's Gub a preview of
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
	# immediately: by the focus hand-off below and by `_on_collapse`. Without the
	# detach, the second collapse of a session grabs focus on a button that is
	# already on its way out.
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
		button.custom_minimum_size.x = 168
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
## Only ever called with `_writing_picker` set or from `_on_collapse`, because
## `grab_focus` emits `focus_entered` and that signal is also a pick.
func _focus_pick() -> void:
	for child in _weapon_picker.get_children():
		var button := child as Button
		if button != null and button.button_pressed and not button.disabled:
			button.grab_focus()
			return


## Show the panels, or show the glade and the strip (D-069).
##
## The whole of the collapse, and it is three lines because the two surfaces are
## two nodes and the state is one boolean. Called only from `_refresh`, so a
## roster change that arrives while the picker is open redraws the picker and the
## surface together and cannot leave one of them behind.
func _refresh_surface() -> void:
	_panel_stack.visible = not _picking
	_weapon_row.visible = _picking
	_collapse_button.text = "MENU   ▴" if _picking else "WEAPON   ▾"


func _on_collapse() -> void:
	_picking = not _picking
	_refresh()
	if not _picking:
		return
	# Put the caret where the eye is. Every other screen in the game that opens a
	# surface grabs focus on the thing you are most likely to press (the menu on
	# HOST, the pause menu on RESUME, the results screen on REMATCH), and without
	# it an arrow key in the collapsed lobby would move focus inside panels that
	# are no longer on screen.
	#
	# Guarded, because `grab_focus` emits `focus_entered` and this file reads that
	# as a pick: opening the picker must not ask for the weapon you already have.
	_writing_picker = true
	_focus_pick()
	_writing_picker = false


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
			return "Random teams need at least two Gubs." if Net.player_count() < 2 else ""
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
