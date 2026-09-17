extends Node
## Puts a UI screen into a named state so it can be photographed. Development
## tool, not shipped.
##
## Menus are the one part of the game that cannot be judged by playing for two
## seconds: a lobby with one person in it looks fine and a lobby with eight
## people, two teams and a scrolling chat is a different screen. So this opens a
## real offline session (D-011), writes a plausible roster straight into
## `Net.players` exactly the way `tools/combat_range.gd` does, and instances the
## real scene on top of it. Nothing here reaches past a public API.
##
##     Godot --path . --resolution 1600x900 --script tools/snapshot.gd -- \
##         res://tools/ui_range.tscn out.png 40 <mode>
##
## Modes: menu, menu_join, menu_notice, settings, settings_network,
##        lobby, lobby_full, lobby_teams, lobby_client, lobby_map, lobby_capture,
##        lobby_weapons, lobby_skins, lobby_ffa_skins, lobby_chat, lobby_feel,
##        widths, capture_config.
##
## `widths` and `capture_config` print a verdict and are in the gate (D-076).
## Everything else is a photograph.

const MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const LOBBY_SCENE := preload("res://scenes/ui/lobby.tscn")

## Peer ids for the stand-in roster, well clear of anything ENet hands out and
## of the combat range's 900s.
const FAKE_BASE := 700

## Enough flavour that the list reads as people rather than as Player 1..8, and
## long enough in a couple of cases to prove the rows do not overflow.
const FAKE_NAMES := ["Thistle", "Mossback", "Pipwick", "Bramblewick",
	"Toadflax", "Nettle", "Sorrel"]

## What each mode says in chat, so the log is never an empty box in a
## screenshot. Sender index -1 is the system.
const FAKE_CHAT: Array[Array] = [
	[0, "anyone else getting bodied by pipwick"],
	[2, "skill issue"],
	[1, "im just standing near the shrine and hoping"],
	[0, "reroll the seed, that island had one bridge"],
]

## What each stand-in brings (D-069). Cycled rather than all-spear so that every
## lobby shot is also a shot of the ring carrying three different things, which
## is the half of this feature a list of names cannot show.
const FAKE_WEAPONS := [Loadout.Weapon.BOW, Loadout.Weapon.SWORD,
	Loadout.Weapon.SPEAR, Loadout.Weapon.BOW, Loadout.Weapon.SWORD,
	Loadout.Weapon.SPEAR, Loadout.Weapon.BOW]

## What each stand-in is wearing in `lobby_ffa_skins`, and what the two teams
## wear in `lobby_skins`. Named rather than indexed so the shot's caption and
## this list can be read against each other, and deliberately far apart in the
## picker's order so the lit tile is never next to its neighbour.
##
## Only those two modes deal skins. Every other lobby mode leaves the roster's
## `skin` key alone and photographs a ring of plain Bogs, which keeps the
## reference shots that existed before the picker did comparable with
## themselves — the weapons are cycled everywhere because the ring is the only
## place a weapon can be seen, and a skin is on a strip of its own.
const FAKE_SKINS := ["toad", "rime", "slag", "gilt", "boo", "crag", "muck"]

## The two teams in `lobby_skins`: the local player's, then the other one. Not
## the defaults (team 0 is the plain body) — the shot is about two teams that
## have *chosen*, and about the second one's tile being disabled on the first
## one's strip.
const TEAM_SKINS := ["toad", "rime"]

var _mode: String = "lobby"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 4:
		_mode = args[3]

	match _mode:
		"menu", "menu_join", "menu_notice", "settings", "settings_network":
			_open_menu()
		"lobby_full":
			_open_lobby(7, false, true)
		"lobby_teams":
			_open_lobby(5, true, true)
		"lobby_client":
			_open_lobby(4, false, false)
		"lobby_map", "lobby_capture":
			_open_lobby(3, _mode == "lobby_capture", true)
		"lobby_weapons":
			# Three Bogs and three weapons, so the strip and the ring above it
			# carry one of each. Nothing is folded away for it any more — the
			# strip is on in every lobby shot now, and this mode is what makes
			# sure all three of its buttons are represented in the ring.
			_open_lobby(2, false, true)
		"lobby_skins":
			# Two teams of three, each in its own body, and the local player on
			# one of them — so the strip shows a lit tile, a disabled tile in
			# the other team's colour, and a caption that says whose skin the
			# row is changing.
			_open_lobby(5, true, true)
		"lobby_ffa_skins":
			# Free-for-all, where a skin is one player's own. Six stand-ins in
			# six different bodies, so the ring is six answers at once.
			_open_lobby(6, false, true)
		"lobby_chat":
			# The one panel whose open state is not a stored boolean: the chat
			# unfolds while the caret is in its input box.
			_open_lobby(4, false, true)
		"lobby_feel", "widths", "capture_config":
			_open_lobby(3, false, true)
		_:
			_open_lobby(3, false, true)


# ------------------------------------------------------------------- menus ---

func _open_menu() -> void:
	if _mode == "menu_notice":
		# The state a player lands in when a host closes the lobby out from
		# under them, which is the whole point of PLAN 1.8.
		UIState.post_notice("Lobby closed",
			"The host left, which ends the lobby for everyone.\nStart your own, or get a new code.")
	var menu := MENU_SCENE.instantiate()
	add_child(menu)
	await get_tree().process_frame
	if _mode == "menu_join":
		(menu.get_node("%JoinButton") as Button).pressed.emit()
		(menu.get_node("%CodeEdit") as LineEdit).text = "7K2QM-4XVB9"
	elif _mode == "settings" or _mode == "settings_network":
		var panel := menu.get_node("%Settings") as SettingsPanel
		panel.open()
		if _mode == "settings_network":
			await _show_public_address(panel)


## Put a plausible playit address in the Network row and scroll down to it.
##
## The address is written straight into the control, the way `menu_join` above
## writes a stand-in code, and deliberately *not* through `Settings`: every
## checkout of this project shares one `user://settings.cfg` (Godot keys user
## data on the project name — see `tools/net_loopback.gd`), and a screenshot
## tool has no business leaving a public address in the file the next person
## hosts a real game with. Assigning `text` does not emit `text_changed`, so the
## panel's write-through never fires and nothing is saved.
##
## Its own mode rather than a change to `settings`, because the plain one is the
## top of the panel and stays the reference shot for it.
func _show_public_address(panel: SettingsPanel) -> void:
	var field := panel.find_child("PublicAddress", true, false) as LineEdit
	var note := panel.find_child("PublicAddressNote", true, false) as Label
	var scroll := panel.find_child("Scroll", true, false) as ScrollContainer
	if field == null or note == null or scroll == null:
		push_warning("ui_range: the settings panel has no public-address row")
		return
	field.text = "angry-gub.at.ply.gg:41235"
	# Two frames: the rows are built in `_ready` and the container has not laid
	# them out yet, so scrolling before this asks for a position of zero.
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.ensure_control_visible(note)


# ------------------------------------------------------------------- lobby ---

## `extra` stand-ins besides the local player. `as_host` false leaves the local
## peer looking like a client, which is a visibly different screen: ready toggle
## instead of a start button, and every match setting greyed out.
func _open_lobby(extra: int, teams: bool, as_host: bool) -> void:
	Net.start_offline()
	Net.set_name_local("You")
	if teams:
		Net.config.mode = MatchConfig.Mode.TEAMS
		Net.config.team_count = 2
		Net.players[1]["team"] = 0
	for i in extra:
		Net.players[FAKE_BASE + i] = {
			"name": FAKE_NAMES[i % FAKE_NAMES.size()],
			"team": (i + 1) % 2 if teams else 0,
			# One straggler who has not readied up, so the start button has a
			# reason to be disabled and the gate hint has something to say.
			"ready": i != 1,
			"weapon": FAKE_WEAPONS[i % FAKE_WEAPONS.size()],
		}
	if not as_host:
		# Everything downstream branches on this, so flipping it is the whole
		# of "show me the client's view".
		Net.is_host = false
	Net.roster_changed.emit()

	var lobby := LOBBY_SCENE.instantiate()
	add_child(lobby)
	await get_tree().process_frame
	for line: Array in FAKE_CHAT:
		Net.chat_received.emit(FAKE_BASE + int(line[0]), String(line[1]))
	if _mode == "lobby_map":
		await _show_map_row(lobby)
	elif _mode == "lobby_capture":
		await _show_capture_rules(lobby)
	elif _mode == "lobby_weapons":
		await _dress_weapons()
	elif _mode == "lobby_skins":
		await _dress_team_skins()
	elif _mode == "lobby_ffa_skins":
		await _dress_own_skins()
	elif _mode == "lobby_chat":
		await _open_chat(lobby)
	elif _mode == "lobby_feel" or _mode == "widths":
		await _worst_labels(lobby)
	elif _mode == "capture_config":
		await _capture_config(lobby)


## All three weapons at once, in the strip and in the ring above it.
##
## This used to press the header's collapse button and photograph the picker
## surface D-069 made. There is no such surface: the strip is always on, so what
## is left of the mode is the part that was always doing the work — making sure
## the three buttons and the three pairs of hands behind them are not all
## carrying the same thing.
func _dress_weapons() -> void:
	# The local player takes the third weapon, so the shot carries all three at
	# once: the two stand-ins have a bow and a sword between them.
	#
	# Written straight into the roster row rather than through `Net.set_weapon`,
	# for the reason `_show_public_address` gives about the address field: that
	# call writes the pick through to `Settings`, every checkout shares one
	# `user://settings.cfg`, and a screenshot tool has no business changing the
	# weapon the next real game starts with.
	Net.players[1]["weapon"] = Loadout.Weapon.SPEAR
	Net.roster_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame


## Two teams, two bodies, and the local player standing on one of them.
##
## Written into `Net.team_skins` rather than requested through `Net.set_skin`,
## which is where the host would have put it — the request path is
## `tools/weapon_select.gd`'s business and this file's business is a picture.
## Nothing here reaches `Settings`: a team's skin is never saved locally anyway,
## but the roster's own `skin` key would be, and `_dress_weapons` above says why
## a screenshot tool must not write that file.
func _dress_team_skins() -> void:
	var dealt: Array[int] = []
	for skin_name: String in TEAM_SKINS:
		dealt.append(Skins.NAMES.find(skin_name))
	Net.team_skins = dealt
	Net.roster_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame


## Free-for-all: everybody in their own body, including the local player, so the
## ring is as many answers as there are Bogs and the strip lights exactly one.
func _dress_own_skins() -> void:
	var ids := Net.peer_ids()
	for i in ids.size():
		Net.players[ids[i]]["skin"] = Skins.NAMES.find(FAKE_SKINS[i % FAKE_SKINS.size()])
	Net.roster_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame


## The chat panel with the caret in it, which is the only way it is ever more
## than a line of input.
##
## Focus, not a flag: `ChatPanel` reads `has_focus()` rather than keeping a
## boolean, so a tool that set a boolean would be photographing a state the
## shipping panel cannot be in.
func _open_chat(lobby: Node) -> void:
	var chat := lobby.get_node_or_null("%Chat") as ChatPanel
	var input := chat.find_child("Input", true, false) as LineEdit if chat else null
	if input == null:
		push_warning("ui_range: the lobby chat has no input box")
		return
	input.grab_focus()
	input.text = "who has the sword"
	await get_tree().process_frame
	await get_tree().process_frame


## Capture B·O·G picked, and the panel scrolled to its own rules section
## (D-051), which only exists while that condition is selected.
func _show_capture_rules(lobby: Node) -> void:
	var next := Net.config.duplicate_config()
	next.win_condition = MatchConfig.WinCondition.CAPTURE
	Net.update_config(next)
	var panel := lobby.find_child("MatchSettings", true, false)
	var note := panel.find_child("CaptureRules", true, false) as Control if panel else null
	var scroll := panel.find_child("Scroll", true, false) as ScrollContainer if panel else null
	if note == null or scroll == null:
		push_warning("ui_range: the match panel has no capture rules to scroll to")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.ensure_control_visible(note)


## Scroll the match panel down to the Map section.
##
## Its own mode rather than a change to `lobby`, for the same reason
## `settings_network` is: the top of the panel is the reference shot and moving
## it would mean the mode that has always shown Mode and Limits stops doing so.
##
## The Map row is the only thing in that panel a *host* can change that a
## screenshot would otherwise never see — the panel scrolls, its scrollbar is
## invisible against the theme (a known issue in docs/STATUS.md), and the row
## sits well below the fold at every size the game runs at.
func _show_map_row(lobby: Node) -> void:
	# Searched from the panel, not from the lobby: the player list has a
	# `Scroll` of its own and it comes first in tree order, so a search from the
	# root would tidily scroll the wrong container.
	var panel := lobby.find_child("MatchSettings", true, false)
	if panel == null:
		push_warning("ui_range: the lobby has no match settings panel")
		return
	var row := panel.find_child("MapRow", true, false) as Control
	var scroll := panel.find_child("Scroll", true, false) as ScrollContainer
	if row == null or scroll == null:
		push_warning("ui_range: the match panel has no map row to scroll to")
		return
	# Two frames: the rows are built in `_ready` and the container has not laid
	# them out yet, so scrolling before this asks for a position of zero.
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.ensure_control_visible(row)
	# And then the row under it, so the shot carries the whole section rather
	# than the picker with the seed row sliced off at the bottom edge. The two
	# belong together: which map is chosen is what decides whether there is a
	# seed row at all.
	var rows := row.get_parent()
	var last := rows.get_child(rows.get_child_count() - 1) as Control
	if last != null:
		scroll.ensure_control_visible(last)


# ------------------------------------------------- the worst label there is ---

## The narrowest a slider track is allowed to get, in pixels at the 1600x900
## base viewport. Not a taste number: below about this a 0-1800 range is fewer
## than two hundred pixels of travel, every step is sub-pixel, and the grabber
## is a thumb-width of the row. The bug this catches went the whole way — the
## readout beside the slider set the row's minimum width, so a long enough one
## drove the track to nothing and the setting could not be changed at all.
const MIN_TRACK := 180.0

## Which panel row to photograph in `lobby_feel`: the one whose readout is the
## longest string this panel can produce.
const WORST_FIELD := "bow_drop_full"


## Put every slider in the match panel at the value that makes its own readout
## as wide as it can be, and then measure what is left of the track.
##
## The worst label is not a guess and not a typical one: for every field, this
## walks the slider's own range at the slider's own step and keeps the value
## whose formatted readout is widest **in pixels through the real font**, which
## is the thing that actually squeezes a row. The whole worst set is pushed as
## one config, so the shot is every dial at its own worst at once.
##
## Repeated for each win condition, because `_apply_visibility` hides rows and a
## row that is not laid out has no width to measure — the capture pair only
## exists under Capture, the kill limit only under the kill limit, and so on.
func _worst_labels(lobby: Node) -> void:
	var panel := lobby.find_child("MatchSettings", true, false) as MatchSettingsPanel
	if panel == null:
		push_warning("ui_range: the lobby has no match settings panel")
		return
	await get_tree().process_frame
	await get_tree().process_frame

	# One pass to find the worst value per field, a second to apply them all —
	# two readouts here quote *another* field (the bow's flat band is speed
	# against drop), so the widest string for one of them depends on where the
	# other one is standing.
	var worst := _solve_worst(panel)
	_push_worst(panel, worst)
	await get_tree().process_frame
	await get_tree().process_frame

	if _mode == "lobby_feel":
		var rows := panel.slider_rows()
		for row: Dictionary in rows:
			if String(row["field"]) == WORST_FIELD:
				var scroll := panel.find_child("Scroll", true, false) as ScrollContainer
				if scroll != null:
					scroll.ensure_control_visible(row["row"] as Control)
				break
		await get_tree().process_frame
		return

	# Every condition in turn, so every conditional row gets laid out once.
	var failures := 0
	var measured := 0
	var narrowest := {"field": "", "width": 99999.0, "text": ""}
	for teams: bool in [false, true]:
		for condition: int in range(MatchConfig.WinCondition.size()):
			if condition == MatchConfig.WinCondition.CAPTURE and not teams:
				continue
			var next := Net.config.duplicate_config()
			next.mode = MatchConfig.Mode.TEAMS if teams else MatchConfig.Mode.FREE_FOR_ALL
			next.win_condition = condition as MatchConfig.WinCondition
			Net.update_config(next)
			_push_worst(panel, worst)
			await get_tree().process_frame
			await get_tree().process_frame
			for row: Dictionary in panel.slider_rows():
				var control: Control = row["row"]
				if not control.is_visible_in_tree():
					continue
				var slider: HSlider = row["slider"]
				var width := slider.size.x
				measured += 1
				if width < narrowest["width"]:
					narrowest = {"field": row["field"], "width": width,
						"text": (row["readout"] as Label).text}
				if width < MIN_TRACK:
					failures += 1
					print("widths: %-22s track %6.1f px  readout %s"
						% [row["field"], width, (row["readout"] as Label).text])

	print("widths: %d rows measured across every condition" % measured)
	print("widths: narrowest is %s at %.1f px, showing \"%s\""
		% [narrowest["field"], narrowest["width"], narrowest["text"]])
	print("widths: %s" % ("PASS" if failures == 0 else "FAIL (%d under %.0f px)"
		% [failures, MIN_TRACK]))


## For each slider field, the value whose readout renders widest.
func _solve_worst(panel: MatchSettingsPanel) -> Dictionary:
	var out := {}
	for pass_index in 2:
		for row: Dictionary in panel.slider_rows():
			var slider: HSlider = row["slider"]
			var readout: Label = row["readout"]
			var font := readout.get_theme_font("font")
			var size := readout.get_theme_font_size("font_size")
			var formatter: Callable = row["format"]
			var best := slider.min_value
			var best_width := -1.0
			var step := maxf(slider.step, (slider.max_value - slider.min_value) / 240.0)
			var value := slider.min_value
			while value <= slider.max_value + 0.0001:
				var text: String = formatter.call(value)
				var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
					-1, size).x
				if width > best_width:
					best_width = width
					best = value
				value += step
			out[String(row["field"])] = best
		if pass_index == 0:
			_push_worst(panel, out)
	return out


func _push_worst(panel: MatchSettingsPanel, worst: Dictionary) -> void:
	var next := Net.config.duplicate_config()
	for field: String in worst:
		var current: Variant = next.get(field)
		next.set(field, int(worst[field]) if typeof(current) == TYPE_INT
			else float(worst[field]))
	Net.update_config(next)
	panel.refresh()



# ------------------------------------------------- capturing a config (D-076) ---

## What the check types into the sheet. Two lines in the notes on purpose: the
## transcript indents a note under its own heading and a one-line note would
## never exercise that.
const CAPTURE_NAME := "Sniper night"
const CAPTURE_NOTES := "bow only, long recharge.\nchecking the flat band reads right."


## Open the capture sheet through its real button, type a name and notes into
## the real fields, press the real copy button, and read the clipboard back.
##
## The assertion that matters is **completeness**: every field in
## `MatchConfig.fields()` — what actually travels on the wire — has to have
## produced a line, because a capture that quietly drops a setting is worse than
## no capture at all, and the way it would drop one is by being built from a list
## somebody wrote by hand. So this compares the sheet's own row set against
## `fields()` in both directions, and then checks those rows survived into the
## text on the clipboard.
##
## The clipboard is real: `DisplayServer.clipboard_set` and `clipboard_get`, on
## the same machine, in the same process. It is the one part of this feature that
## cannot be proved by looking at the panel.
func _capture_config(lobby: Node) -> void:
	var panel := lobby.find_child("MatchSettings", true, false) as MatchSettingsPanel
	if panel == null:
		push_warning("ui_range: the lobby has no match settings panel")
		return
	await get_tree().process_frame
	await get_tree().process_frame

	var button := panel.find_child("CaptureButton", true, false) as Button
	if button == null:
		print("capture: FAIL (no capture button in the panel heading)")
		return
	button.pressed.emit()
	await get_tree().process_frame

	var name_field := panel.find_child("CaptureName", true, false) as LineEdit
	var notes_field := panel.find_child("CaptureNotes", true, false) as TextEdit
	var copy := panel.find_child("CaptureCopy", true, false) as Button
	var save := panel.find_child("CaptureSave", true, false) as Button
	if name_field == null or notes_field == null or copy == null or save == null:
		print("capture: FAIL (the sheet is missing a control)")
		return
	name_field.text = CAPTURE_NAME
	notes_field.text = CAPTURE_NOTES
	name_field.text_changed.emit(CAPTURE_NAME)
	await get_tree().process_frame

	var ok := true

	# Completeness, both ways round.
	var wanted := MatchConfig.fields()
	var got := PackedStringArray()
	for row: Dictionary in panel.capture_rows():
		got.append(String(row["field"]))
	var missing := PackedStringArray()
	for field: String in wanted:
		if not got.has(field):
			missing.append(field)
	var extra := PackedStringArray()
	for field: String in got:
		if not wanted.has(field):
			extra.append(field)
	if missing.is_empty() and extra.is_empty() and got.size() == wanted.size():
		print("capture: fields PASS (%d, exactly MatchConfig.fields())" % got.size())
	else:
		ok = false
		print("capture: fields FAIL (missing %s, extra %s, %d of %d)"
			% [missing, extra, got.size(), wanted.size()])

	# The clipboard, for real.
	DisplayServer.clipboard_set("")
	copy.pressed.emit()
	var payload := DisplayServer.clipboard_get()
	if payload.strip_edges().is_empty():
		print("capture: clipboard FAIL (nothing was copied)")
		ok = false
	else:
		var absent := PackedStringArray()
		for row: Dictionary in panel.capture_rows():
			if not payload.contains("  %s: %s" % [row["label"], row["value"]]):
				absent.append(String(row["field"]))
		var headed := payload.begins_with("BOG match config")
		var named := payload.contains(CAPTURE_NAME)
		var noted := payload.contains("bow only, long recharge.") \
			and payload.contains("checking the flat band reads right.")
		if absent.is_empty() and headed and named and noted:
			print("capture: clipboard PASS (%d bytes, %d lines, every field in it)"
				% [payload.length(), payload.split("\n").size()])
		else:
			ok = false
			print("capture: clipboard FAIL (headed %s, named %s, noted %s, absent %s)"
				% [headed, named, noted, absent])
		# Printed in full, because a payload nobody reads is a payload nobody can
		# say is readable — and "reads correctly pasted into chat" is the whole
		# requirement and is not something a substring test can settle.
		print("---- clipboard ----")
		print(payload)
		print("---- end ----")

	# Saved for the session, and applied back.
	UIState.forget_configs()
	save.pressed.emit()
	await get_tree().process_frame
	var saved := UIState.captured_configs()
	if saved.size() == 1 and String(saved[0]["name"]) == CAPTURE_NAME:
		var round_trip := MatchConfig.new()
		round_trip.apply_dict(saved[0]["config"])
		var same := true
		for field: String in wanted:
			if str(round_trip.get(field)) != str(Net.config.get(field)):
				same = false
				print("capture: %s came back as %s, not %s"
					% [field, round_trip.get(field), Net.config.get(field)])
		print("capture: saved %s" % ("PASS" if same else "FAIL"))
		ok = ok and same
	else:
		ok = false
		print("capture: saved FAIL (%d captures)" % saved.size())

	print("capture: %s" % ("PASS" if ok else "FAIL"))
