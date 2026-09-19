extends Node
## The lobby weapon pick, end to end (D-069). Development tool, not shipped.
## Runs headless in a couple of seconds.
##
##   Godot --headless --path . tools/weapon_select.tscn
##
## A scene and not a `--script` main loop, for `match_rules.gd`'s reason: a
## script main loop is compiled before the autoloads are registered, so `Net`
## and `MatchState` are not resolvable identifiers at parse time.
##
## **What this covers and what `match_rules` covers.** The pick has two halves
## and they fail in different places. Here is the half that is a *roster row*:
## where the weapon lives, who is allowed to change it, what a rebroadcast
## carries, what Start does to it and what a rematch does not. `match_rules`
## has the half that is a *Bog*: the gate, the hand, and the three overrides that
## take a weapon away again. Neither would notice the other's bugs.
##
## What it asserts:
##
##   roster — the default is the spear, including for a row written by something
##            that predates this; a request goes through the host and comes back
##            on the row; and a nonsense ordinal is refused into the default.
##   lock   — a pick is free while people are joining and fixed the moment the
##            host presses Start; a rematch keeps it; coming back to the lobby
##            makes it free again.
##   lobby  — the real scene: the Weapon and Character page opens from the
##            header and takes the lobby's place while it is up, the panels fold
##            to their own headings on their own toggles and open at the
##            defaults the lobby ships with, the config is not shown to a client
##            at all, the page's buttons pick, and they go dead while a match is
##            running. **And the skin grid beside them**, which is the same
##            feature with a second owner: a pick round-trips through the roster
##            in free-for-all, a pick in Teams moves the *team's* body and every
##            member of the team wears it, a skin another team holds is a
##            disabled tile and a refused request, and the Bog standing in the
##            ring is wearing whatever the grid says. And the ring stands in the
##            gap between the two columns rather than behind them.
##   ring   — `BogBackdrop.set_roster` puts three different weapons in three
##            **remote** Bogs' hands, which is the lobby half of "your character
##            should only show the weapon you have selected".

const LOBBY_SCENE := preload("res://scenes/ui/lobby.tscn")

## Stand-in peers, clear of ENet's range, of the combat range's 900s and of the
## backdrop's 8100s.
const PEERS := [1, 951, 952]

## The band of screen the ring has to stand in, in base-viewport pixels.
##
## The lobby is a left column (the roster and the chat, out to x 504) and a
## right rail (the match, from x 1116), and the ring is what is between them.
## This used to be a *clearance* check — the skin strip lived over the Bogs'
## heads and had to leave their nameplates alone — and it is a *containment*
## check now that the pickers have moved to a page of their own: a Bog or a
## nameplate outside this band is standing behind the furniture, which is the
## one way this layout can quietly come apart. `BogBackdrop.FRAMING` has the
## arithmetic that puts them here.
##
## 400 and 1140 rather than 504 and 1116: the two panels are translucent and a
## nameplate that grazes one is still hard to read, so the band is drawn a
## Bog's shoulder inside each of them.
const BAND_LEFT := 400.0
const BAND_RIGHT := 1140.0

## And below the header, which ends at 96.
const BAND_TOP := 100.0

var _failures: int = 0
var _checks: int = 0
## The weapon this machine had picked before the harness started.
##
## `Net.set_weapon` writes the pick through to `Settings` — that is the
## shipping behaviour and is what brings a weapon back across a reconnect —
## and this file drives it dozens of times. Every checkout of this project
## shares one `user://settings.cfg`, because Godot keys user data on the
## project *name* (see `tools/net_loopback.gd`), so a gate run that did not
## put this back would quietly change the weapon the next real game starts
## with. `tools/ui_range.gd` makes the same point about a public address.
var _saved_weapon: int = Loadout.DEFAULT
## And the skin, for the same reason: `Net.set_skin` writes a free-for-all pick
## through to `Settings["skin"]` exactly as `set_weapon` writes the weapon.
var _saved_skin: int = Skins.DEFAULT


func _ready() -> void:
	print("weapon_select: starting")
	_saved_weapon = Settings.chosen_weapon()
	_saved_skin = Settings.chosen_skin()
	# A harness that cannot reach the thing it is testing must not print PASS.
	# See `match_rules.gd`, which learned this the hard way.
	if Net == null or MatchState == null:
		print("weapon_select: FAIL — an autoload is missing; see the errors above")
		get_tree().quit(1)
		return
	_run_roster()
	_run_lock()
	await _run_lobby()
	await _run_ring()

	print("weapon_select: %d checks, %d failures" % [_checks, _failures])
	print("weapon_select: %s" % ("PASS" if _failures == 0 else "FAIL"))
	Settings.set_value("weapon", _saved_weapon)
	Settings.set_value("skin", _saved_skin)
	Net.leave_lobby(Net.Leave.LOCAL_REQUEST, "", false)
	for i in 3:
		await get_tree().process_frame
	get_tree().quit(1 if _failures > 0 else 0)


# ------------------------------------------------------------------ harness ---

func _check(what: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got == want:
		return
	_failures += 1
	print("  FAIL  %s: got %s, wanted %s" % [what, str(got), str(want)])



func _scenario(scenario_name: String) -> void:
	print("-- %s" % scenario_name)


## An offline session with three players in it. Offline is host-for-real as far
## as every branch below is concerned (see `Net.start_offline`), so the request
## path these checks drive is the shipping one: `set_weapon` calls the handler
## directly on the host exactly as it does when hosting over a socket.
func _begin() -> void:
	MatchState.reset()
	Net.start_offline()
	Net.players.clear()
	for i in PEERS.size():
		Net.players[PEERS[i]] = {
			"name": "P%d" % i, "team": 0, "ready": true,
			"weapon": Loadout.DEFAULT,
		}
	Net.roster_changed.emit()


# ---------------------------------------------------------------- scenarios ---

func _run_roster() -> void:
	_scenario("a weapon is one more key in the roster row")
	var before := _failures
	_begin()

	_check("a fresh row is a spear", Net.player_weapon(1), Loadout.Weapon.SPEAR)
	_check("and so is a row that never heard of weapons",
		Net.player_weapon(9999), Loadout.Weapon.SPEAR)

	# A row written by something that predates this — every harness in `tools/`
	# does exactly this, and so would a peer on an older build. The key is simply
	# absent, and absent has to read as the default or the lobby is full of Bogs
	# holding nothing.
	Net.players[952] = {"name": "Old", "team": 0, "ready": true}
	_check("a row with no weapon key at all reads as a spear",
		Net.player_weapon(952), Loadout.Weapon.SPEAR)

	# The request path. The host is the one that writes the row, here as over a
	# socket: `set_weapon` on a host calls its own handler rather than asking
	# peer 1 to do something, which is peer 1 (D-004, and the comment over the
	# roster mutations in `net.gd`).
	Net.set_weapon(Loadout.Weapon.BOW)
	_check("the host's own pick lands on its row",
		Net.player_weapon(1), Loadout.Weapon.BOW)
	_check("and nobody else's row moved",
		Net.player_weapon(951), Loadout.Weapon.SPEAR)

	# What a lying client can and cannot get. There is no restriction to break —
	# all three are always available to everyone — so the only thing out here is
	# an ordinal that is not one of them, and it must not end up in the row.
	#
	# Driven through `_request_weapon`, the door a client's packet actually
	# arrives at, and with ints because that is the only thing that *can* arrive:
	# the parameter is typed, so Godot refuses a packet carrying anything else
	# before this file is reached. `Loadout.sanitize` is asserted against the rest
	# separately below, because it is also what reads a roster row and a
	# `settings.cfg`, neither of which the engine type-checks for anybody.
	for bogus: int in [3, -1, 99999, 7]:
		Net._request_weapon(bogus)
		_check("a bogus weapon %d is refused into the default" % bogus,
			Net.player_weapon(1), Loadout.Weapon.SPEAR)
		Net.set_weapon(Loadout.Weapon.BOW)
	for junk: Variant in ["sword", null, [], {}, Vector2.ZERO]:
		_check("and %s sanitizes to a spear" % str(junk),
			Loadout.sanitize(junk), Loadout.Weapon.SPEAR)
	_check("while 1.0 is still the bow it looks like",
		Loadout.sanitize(1.0), Loadout.Weapon.BOW)

	# The whole roster goes out on every change, so what a client receives is the
	# dictionary itself. Round-trip it the way `_sync_roster` does.
	var wire := Net.players.duplicate(true)
	_check("the weapon travels with the row", wire[1].get("weapon"),
		Loadout.Weapon.BOW)

	_check("a leaver takes their pick with them", Net.players.erase(951), true)
	_check("and a rejoin is a fresh row", Net.player_weapon(951),
		Loadout.Weapon.SPEAR)
	print("weapon_select: roster %s" % ("PASS" if _failures == before else "FAIL"))


func _run_lock() -> void:
	_scenario("a mid-match pick queues for the next spawn and survives a rematch")
	var before := _failures
	_begin()

	Net.set_weapon(Loadout.Weapon.SWORD)
	Net.players[951]["weapon"] = Loadout.Weapon.BOW
	_check("free to change while people are still joining",
		Net.player_weapon(1), Loadout.Weapon.SWORD)

	# Start. `request_match_start` is what the host's button calls, and
	# `_begin_match` inside it is what sets `match_running` on every peer.
	Net.config.mode = MatchConfig.Mode.FREE_FOR_ALL
	Net.request_match_start()
	_check("the match is running", Net.match_running, true)

	# **The lock-in is a queue now** (D-069's successor). What survives of it is
	# that the weapon in a living Bog's hands never moves: a pick sent during a
	# match lands in `next_weapon` and is cashed in by `MatchState` at the next
	# spawn. Both halves are asserted, because a queue that quietly wrote through
	# to `weapon` would look exactly like a pass until somebody watched a sword
	# turn into a spear mid-swing.
	Net.set_weapon(Loadout.Weapon.SPEAR)
	_check("a pick sent after Start leaves the hands alone",
		Net.player_weapon(1), Loadout.Weapon.SWORD)
	_check("and queues instead", Net.pending_weapon(1), Loadout.Weapon.SPEAR)
	# And through the RPC handler directly, which is the door a client's packet
	# actually arrives at — `set_weapon` above is the local half.
	Net._request_weapon(Loadout.Weapon.BOW)
	_check("a later pick replaces the queued one",
		Net.pending_weapon(1), Loadout.Weapon.BOW)
	_check("still without touching the hands",
		Net.player_weapon(1), Loadout.Weapon.SWORD)
	# Asking for what you are already holding is the way back out, and it is the
	# host that knows it.
	Net._request_weapon(Loadout.Weapon.SWORD)
	_check("asking for the held weapon cancels the queue",
		Net.pending_weapon(1), Net.NO_PENDING)
	# A bogus ordinal is still a spear, queued rather than held.
	Net._request_weapon(99)
	_check("a bogus mid-match ordinal queues the default",
		Net.pending_weapon(1), Loadout.Weapon.SPEAR)
	Net._request_weapon(Loadout.Weapon.BOW)

	# A rematch is the same match again — same roster, same teams (D-048), and
	# for the same reason the same weapons. It deals nothing and changes nothing.
	for round_number in 3:
		Net.request_rematch()
		_check("rematch %d keeps the host's sword" % (round_number + 1),
			Net.player_weapon(1), Loadout.Weapon.SWORD)
		_check("rematch %d keeps the other Bog's bow" % (round_number + 1),
			Net.player_weapon(951), Loadout.Weapon.BOW)
		_check("and the match is still running", Net.match_running, true)
		_check("and the queued bow is still queued",
			Net.pending_weapon(1), Loadout.Weapon.BOW)

	# Everybody home. A queue that never got a respawn to land on is settled on
	# the way back rather than dropped, so what a player carries into the lobby
	# is the last thing they actually chose.
	Net.request_return_to_lobby()
	_check("back in the lobby, nothing is queued any more",
		Net.pending_weapon(1), Net.NO_PENDING)
	_check("and the pick they never lived to use is the one on the row",
		Net.player_weapon(1), Loadout.Weapon.BOW)
	_check("and the other Bog, who queued nothing, kept its bow",
		Net.player_weapon(951), Loadout.Weapon.BOW)
	Net.set_weapon(Loadout.Weapon.SWORD)
	_check("a lobby pick lands on the row at once",
		Net.player_weapon(1), Loadout.Weapon.SWORD)
	_check("and clears any queue with it", Net.pending_weapon(1),
		Net.NO_PENDING)
	print("weapon_select: lock %s" % ("PASS" if _failures == before else "FAIL"))


func _run_lobby() -> void:
	_scenario("the strip is always on and the panels fold on their own")
	var before := _failures
	_begin()
	Net.set_weapon(Loadout.Weapon.SPEAR)

	var lobby := LOBBY_SCENE.instantiate()
	add_child(lobby)
	await get_tree().process_frame

	var stack := lobby.get_node_or_null("%PanelStack") as Control
	var rail := lobby.get_node_or_null("%RightRail") as Control
	var page := lobby.get_node_or_null("%CharacterPage") as Control
	var open_page := lobby.get_node_or_null("%CharacterButton") as Button
	var leave := lobby.get_node_or_null("%LeaveButton") as Button
	var row := lobby.get_node_or_null("%WeaponRow") as Control
	var picker := lobby.get_node_or_null("%WeaponPicker") as HBoxContainer
	var players := lobby.get_node_or_null("%Players") as Control
	var roster_list := lobby.get_node_or_null("%Scroll") as Control
	var players_fold := lobby.get_node_or_null("%PlayersFold") as Button
	var count := lobby.get_node_or_null("%PlayerCount") as Label
	var settings := lobby.get_node_or_null("%MatchSettings") as MatchSettingsPanel
	var chat := lobby.get_node_or_null("%Chat") as ChatPanel
	var ring := lobby.get_node_or_null("%Backdrop") as BogBackdrop
	_check("the lobby has a panel stack", stack != null, true)
	_check("a match rail", rail != null, true)
	_check("a Weapon and Character page", page != null, true)
	_check("a button that opens it", open_page != null, true)
	_check("a weapon row on it", row != null, true)
	_check("a strip", picker != null, true)
	_check("a roster panel that folds", players_fold != null, true)
	_check("a match panel", settings != null, true)
	_check("and a chat panel", chat != null, true)
	if stack == null or rail == null or page == null or open_page == null \
			or leave == null or row == null or picker == null or players == null \
			or roster_list == null or players_fold == null or count == null \
			or settings == null or chat == null:
		print("weapon_select: lobby FAIL - the scene is missing controls")
		_failures += 1
		lobby.queue_free()
		return

	# **The lobby opens on the lobby.** D-069's header swapped the panels for
	# the picker and back; the picker is a page of its own now and the lobby is
	# complete without it, which is the thing most likely to be undone by
	# accident — a lobby that opens on the picker is a lobby nobody reads.
	_check("the panels are up", stack.visible, true)
	_check("and the rail with them", rail.visible, true)
	_check("the page is not", page.visible, false)
	_check("with nothing left to swap between",
		lobby.get_node_or_null("%CollapseButton"), null)
	_check("one button per weapon", picker.get_child_count(), Loadout.all().size())

	# The defaults, which are the answer to "what is on this screen the moment it
	# opens".
	var config_rows := settings.get_node("%Scroll") as Control
	_check("the roster opens open", roster_list.visible, true)
	_check("with its count on show", count.visible, true)
	_check("and says who is here", count.text,
		"%d / %d" % [Net.player_count(), Net.config.max_players])
	_check("the config opens open", settings.visible, true)
	_check("with its rows out", config_rows.visible, true)

	# The count follows the list, which is what makes the heading worth having
	# whether the list is out or away: `_refresh` rebuilds both or neither.
	Net.players[953] = {"name": "Late", "team": 0, "ready": true,
		"weapon": Loadout.DEFAULT}
	Net.roster_changed.emit()
	await get_tree().process_frame
	_check("a join moves the count", count.text,
		"%d / %d" % [Net.player_count(), Net.config.max_players])

	# Both toggles, through the real controls. A fold is a boolean the one
	# `_refresh` reads, so pressing the button is what proves the button is wired
	# to the boolean.
	players_fold.pressed.emit()
	await get_tree().process_frame
	_check("the toggle folds the roster away", roster_list.visible, false)
	_check("shrinking to its heading rather than leaving an empty box",
		players.size_flags_horizontal, int(Control.SIZE_SHRINK_BEGIN))
	# Downward, so a folded panel keeps its heading where the heading was rather
	# than floating in the middle of a column of glass.
	_check("and dropping to the foot of its slot rather than sitting on a waist",
		players.size_flags_vertical, int(Control.SIZE_SHRINK_END))
	players_fold.pressed.emit()
	await get_tree().process_frame
	_check("and the toggle brings it back", roster_list.visible, true)
	_check("claiming its share of the column again",
		players.size_flags_horizontal, int(Control.SIZE_EXPAND_FILL))

	settings.fold_requested.emit()
	await get_tree().process_frame
	_check("the config folds too", config_rows.visible, false)
	_check("to its heading", settings.size_flags_horizontal,
		int(Control.SIZE_SHRINK_BEGIN))
	_check("at the foot of the stack", settings.size_flags_vertical,
		int(Control.SIZE_SHRINK_END))
	settings.fold_requested.emit()
	await get_tree().process_frame
	_check("and comes back", config_rows.visible, true)

	# **Chat is a panel now, not a line of input.** It was `reveal_on_focus` —
	# heading and log hidden until the caret arrived — because it shared a
	# horizontal bar with two other panels and a chat nobody had written in was
	# a tall empty box in the third of the screen the ring stands in. It has the
	# bottom of its own column now, so it is simply open, and `ChatPanel`'s
	# plain mode is what that is. What has not changed is the half that is about
	# *sending*, which is below.
	var chat_log := chat.get_node("%Log") as Control
	var chat_heading := chat.get_node("%Heading") as Control
	var chat_input := chat.get_node("%Input") as LineEdit
	_check("chat is open without being asked", chat_log.visible, true)
	_check("with its heading", chat_heading.visible, true)
	_check("and the box under it", chat_input.visible, true)
	chat_input.grab_focus()
	await get_tree().process_frame
	# **Sending does not put the caret down**, unlike the in-match panel, so a
	# player writing two lines does not have to click back in between them.
	chat_input.text = "who has the sword"
	chat_input.text_submitted.emit("who has the sword")
	await get_tree().process_frame
	_check("sending keeps the caret in the box", chat_input.has_focus(), true)
	_check("so the log is still up to be read", chat_log.visible, true)
	_check("and the box is empty for the next line", chat_input.text, "")
	chat_input.release_focus()
	await get_tree().process_frame
	_check("and putting the caret down leaves the log where it was",
		chat_log.visible, true)

	# ---------------------------------------------- the ring stands in the gap ---
	#
	# **The ring must stand between the two columns.** This used to be the other
	# way round — the skin strip lived over the Bogs' heads and had to clear
	# their nameplates — and the question survives the move with its sign
	# flipped: the ring is laid out in 3D and the panels are laid out in the
	# scene at fixed offsets, so the two only meet on screen and nothing but a
	# measurement can say whether they collide. `_ring_box` projects the
	# backdrop's own Bogs and their own nameplates through the backdrop's own
	# camera, in base-viewport pixels, and all of it has to land inside the band.
	#
	# Taken with the lobby's **fullest** roster and again with a five-Bog one,
	# because the arc's ends do not move with the count but the spacing does, and
	# a five-Bog ring stands nearer the camera.
	#
	# **Before the page is ever opened**, which is not tidiness: opening it walks
	# the camera in to one Bog over 0.6 s, and a measurement taken while that
	# tween is in flight is a measurement of a camera on its way somewhere. The
	# band only means anything from the lobby's own framing, so it is asked for
	# while that is the framing the lens is actually at.
	#
	# The stand-ins are renamed to the longest name the range uses, because it is
	# the *nameplate* that sets the width — an eleven-character name is 1.3 m of
	# world, wider than the Bog under it.
	var was_roster := Net.players.duplicate(true)
	var swelled := Net.players.duplicate(true)
	for peer: int in swelled:
		swelled[peer]["name"] = "Bramblewick"
	for extra in 8:
		if swelled.size() >= 8:
			break
		swelled[960 + extra] = {"name": "Bramblewick", "team": 0, "ready": true,
			"weapon": Loadout.DEFAULT, "skin": Skins.DEFAULT}
	Net.players = swelled
	Net.roster_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var box := _ring_box(ring)
	print("  ring of %d: x %.1f..%.1f, plate top %.1f"
		% [int(box["bogs"]), box["left"], box["right"], box["plate"]])
	_check("the fullest ring stands clear of the roster column",
		box["left"] >= BAND_LEFT, true)
	_check("and clear of the match rail", box["right"] <= BAND_RIGHT, true)
	_check("with its names below the header", box["plate"] >= BAND_TOP, true)

	while Net.players.size() > 5:
		Net.players.erase(Net.peer_ids().back())
	Net.roster_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var box5 := _ring_box(ring)
	print("  ring of %d: x %.1f..%.1f, plate top %.1f"
		% [int(box5["bogs"]), box5["left"], box5["right"], box5["plate"]])
	_check("and a smaller ring, which stands nearer the camera, does too",
		box5["left"] >= BAND_LEFT and box5["right"] <= BAND_RIGHT, true)
	_check("with its names below the header as well", box5["plate"] >= BAND_TOP, true)

	Net.players = was_roster
	Net.roster_changed.emit()
	await get_tree().process_frame

	# ------------------------------------------- the Weapon and Character page ---
	#
	# Everything from here is on it, so it is opened through its real button —
	# the boolean behind it is private, and a control that is not *visible in the
	# tree* cannot take focus, which the arrow-key half of the strip below
	# depends on.
	open_page.pressed.emit()
	await get_tree().process_frame
	_check("the header's button opens the page", page.visible, true)
	_check("and the panels get out of the way", stack.visible, false)
	_check("the rail with them", rail.visible, false)
	_check("the button that opened it goes too", open_page.visible, false)
	_check("and LEAVE becomes BACK", leave.text.contains("BACK"), true)

	# Which one is lit has to be read off the roster, not off whatever was
	# pressed last: the lobby renders what came back from the host and nothing
	# else, which is the property its header is built on.
	_check("the spear is the one lit",
		(picker.get_child(Loadout.Weapon.SPEAR) as Button).button_pressed, true)

	(picker.get_child(Loadout.Weapon.SWORD) as Button).pressed.emit()
	await get_tree().process_frame
	_check("pressing a button asks for that weapon",
		Net.player_weapon(1), Loadout.Weapon.SWORD)
	_check("and the strip comes back showing it",
		(picker.get_child(Loadout.Weapon.SWORD) as Button).button_pressed, true)
	_check("with only one lit",
		(picker.get_child(Loadout.Weapon.SPEAR) as Button).button_pressed, false)

	# Focus is the other way in, and it is the same request. A controller or the
	# arrow keys move focus, so a strip that only answered clicks would be a
	# picker half the lobby could not use. `grab_focus` and not a bare
	# `focus_entered.emit()`, because the caret actually has to move: what the next
	# check is about is what happens to it afterwards.
	(picker.get_child(Loadout.Weapon.BOW) as Button).grab_focus()
	await get_tree().process_frame
	_check("moving onto a button picks it too",
		Net.player_weapon(1), Loadout.Weapon.BOW)
	# **And the caret survives the rebuild the pick just caused.** Every roster
	# change frees and rebuilds these three buttons, including the one this
	# player's own pick produced - so without the hand-off in
	# `_rebuild_weapon_picker`, choosing a weapon with the arrow keys would be the
	# last thing the arrow keys ever did.
	_check("and the caret stays on the strip",
		(picker.get_child(Loadout.Weapon.BOW) as Button).has_focus(), true)
	_check("on the weapon that is picked",
		(picker.get_child(Loadout.Weapon.SWORD) as Button).has_focus(), false)

	# ------------------------------------------------------------ the skins ---
	#
	# The grid beside the weapon strip, and the half of this feature the weapon
	# never had: a second owner. In free-for-all a skin is a roster key and reads
	# exactly like a weapon. In Teams it belongs to the **team** - any member may
	# change it, everyone on it wears it, and no two teams may have the same one.
	var skin_row := lobby.get_node_or_null("%SkinRow") as Control
	var skins := lobby.get_node_or_null("%SkinPicker") as GridContainer
	var caption := lobby.get_node_or_null("%SkinCaption") as Label
	_check("the lobby has a skin row", skin_row != null, true)
	_check("a skin grid", skins != null, true)
	_check("a caption above it", caption != null, true)
	if skin_row == null or skins == null or caption == null or ring == null:
		print("weapon_select: lobby FAIL - the scene has no skin grid")
		_failures += 1
		lobby.queue_free()
		return
	_check("the grid is on the page beside the weapon strip, not instead of it",
		skin_row.visible and row.visible, true)
	# Three columns, which is what makes the cell 120 px wide in a 380 px column
	# rather than the 40 px swatch it was when it lived over the ring (D-109).
	_check("in three columns", skins.columns, 3)
	_check("one cell per pickable skin", skins.get_child_count(), Skins.NAMES.size())
	# Fourteen: the plain body and the thirteen of D-108. The eleven of D-126
	# are parked (D-128) and must stay out until their downloads are redone on
	# the body's own mesh. The number is pinned so that a name added or dropped
	# by accident is a red gate, not a quiet change to the grid.
	_check("fourteen of them", Skins.NAMES.size(), 14)
	# The folders under `art/skins/` that are not a pick: the worked example,
	# the Elder's robe, the shirt on its way and the parked batch. A list that
	# grew one of those by accident would put a garment on a strip of bodies,
	# or a registered face back on the ring.
	_check("and the worked example is not one of them",
		Skins.NAMES.has("example"), false)
	_check("nor the shirt", Skins.NAMES.has("shirt"), false)
	for parked: String in Skins.PARKED:
		_check("nor the parked %s" % parked, Skins.NAMES.has(parked), false)
	_check("nor is the Elder's robe", Skins.NAMES.has("elder"), false)
	_check("the plain body is the first and the default",
		Skins.NAMES[Skins.DEFAULT], "bog")

	# Free-for-all: the round trip, through the real tile, into the roster row
	# and back out onto the strip.
	_check("the plain body is the one lit",
		_skin_tile(skins, Skins.DEFAULT).button_pressed, true)
	_check("and the caption says whose it is and which it is",
		caption.text, "YOUR SKIN · BOG")
	var muck := Skins.NAMES.find("muck")
	_skin_tile(skins, muck).pressed.emit()
	await get_tree().process_frame
	_check("pressing a tile asks for that skin", Net.player_skin(1), muck)
	_check("and it is the body that player is wearing", Net.skin_for(1), muck)
	_check("the strip comes back showing it",
		_skin_tile(skins, muck).button_pressed, true)
	_check("with only one lit",
		_skin_tile(skins, Skins.DEFAULT).button_pressed, false)
	_check("and nobody else's body moved", Net.skin_for(951), Skins.DEFAULT)
	# **The ring is wearing it**, which is the whole reason a skin is a roster
	# key and not a local variable: eight Bogs' picks, not one. A second frame,
	# for `_run_ring`'s reason.
	await get_tree().process_frame
	var ring_bogs: Array = ring.get("_bogs")
	_check("the backdrop stood Bogs up", ring_bogs.size() >= 2, true)
	if ring_bogs.size() >= 2:
		_check("the ring's own Bog wears the pick",
			_worn(ring_bogs[0]), Skins.texture_of(muck))
		_check("and the Bog beside it does not",
			_worn(ring_bogs[1]) == Skins.texture_of(muck), false)

	# Teams. The same strip, a different owner.
	var teamed := Net.config.duplicate_config()
	teamed.mode = MatchConfig.Mode.TEAMS
	teamed.team_count = 2
	Net.update_config(teamed)
	Net.players[1]["team"] = 0
	Net.players[951]["team"] = 1
	Net.players[952]["team"] = 0
	Net.roster_changed.emit()
	await get_tree().process_frame
	_check("in Teams the team column means a body", Net.teams_decided(), true)
	_check("team 1 starts on the plain body", Net.team_skin(0), Skins.DEFAULT)
	_check("team 2 on the next skin along", Net.team_skin(1), 1)
	_check("so two teams never start alike",
		Net.team_skin(0) == Net.team_skin(1), false)
	_check("the caption says whose skin the row changes",
		caption.text.begins_with("TEAM 1'S SKIN"), true)
	_check("and it names the team's body, not the player's own pick",
		caption.text, "TEAM 1'S SKIN · BOG")
	_check("with the rule about who may press it in a tooltip, not a second line",
		caption.tooltip_text, "Anyone on the team can change it.")
	_check("the lit tile is the team's, not the player's",
		_skin_tile(skins, Net.team_skin(0)).button_pressed, true)
	_check("and the player's own free-for-all pick is not lit",
		_skin_tile(skins, muck).button_pressed, false)
	# **The other team's skin is a disabled tile**, which is where the rule is
	# drawn before it is ever enforced.
	_check("a skin the other team holds is a disabled swatch",
		_skin_tile(skins, 1).disabled, true)
	_check("while a free one is not", _skin_tile(skins, muck).disabled, false)

	var slag := Skins.NAMES.find("slag")
	_skin_tile(skins, slag).pressed.emit()
	await get_tree().process_frame
	_check("a pick in Teams moves the team's body", Net.team_skin(0), slag)
	_check("and leaves the player's own row alone", Net.player_skin(1), muck)
	_check("the one who pressed it is wearing it", Net.skin_for(1), slag)
	_check("and so is a teammate who did not", Net.skin_for(952), slag)
	_check("while the other team is not", Net.skin_for(951), 1)

	# **The host refuses a skin another team holds**, whatever the strip did or
	# did not let anybody press. Driven through `_request_skin`, the door a
	# client's packet actually arrives at.
	Net._request_skin(1)
	_check("a request for the other team's skin is refused",
		Net.team_skin(0), slag)
	_check("and the other team still has it", Net.team_skin(1), 1)
	_check("no two teams ever share one", _skins_are_unique(), true)

	# A team switch is a change of clothes, with nothing sent: the body comes
	# from the team, so joining a team is putting on its shirt.
	Net.set_team(1)
	await get_tree().process_frame
	_check("switching team switches body", Net.skin_for(1), 1)
	_check("and the swatch the old team holds is now the disabled one",
		_skin_tile(skins, slag).disabled, true)
	_check("with the new team's lit", _skin_tile(skins, 1).button_pressed, true)
	_check("the caption follows", caption.text.begins_with("TEAM 2'S SKIN"), true)

	# Home again, so the checks after this read the screen they expect.
	var ffa := Net.config.duplicate_config()
	ffa.mode = MatchConfig.Mode.FREE_FOR_ALL
	Net.update_config(ffa)
	Net.roster_changed.emit()
	await get_tree().process_frame
	_check("back in free-for-all the player's own pick is theirs again",
		Net.skin_for(1), muck)
	_check("and the caption is back to yours", caption.text, "YOUR SKIN · MUCK")

	# **The names live in the caption now**, because fourteen of them under
	# fourteen swatches was fourteen lines of type across the Bogs' faces. So a
	# swatch has no label of its own, and pointing at one — or arrowing onto it —
	# is how its name is read. Naming is not picking: the roster must not move.
	for swatch: Node in skins.get_children():
		_check("a swatch carries no name of its own",
			(swatch as Button).text, "")
	_skin_tile(skins, Skins.NAMES.find("void")).mouse_entered.emit()
	_check("pointing at a swatch names it", caption.text, "YOUR SKIN · VOID")
	_check("and changes nothing", Net.skin_for(1), muck)
	_skin_tile(skins, Skins.NAMES.find("void")).mouse_exited.emit()
	_check("leaving it says what is being worn again",
		caption.text, "YOUR SKIN · MUCK")
	# The caret does the same, which is the whole of the keyboard's access to a
	# name now that the swatches have none.
	_skin_tile(skins, Skins.NAMES.find("gilt")).focus_entered.emit()
	_check("the caret names a swatch too", caption.text, "YOUR SKIN · GILT")
	_check("and still does not pick it", Net.skin_for(1), muck)
	_skin_tile(skins, Skins.NAMES.find("gilt")).focus_exited.emit()

	# The strip goes dead rather than lying about what it can do, once a match is
	# running. `match_running` is set by hand here and not by pressing Start,
	# because pressing Start is also what walks this scene into the arena - the
	# lobby would be gone before there was a strip to look at. What is set is
	# exactly what `_begin_match` sets and nothing else.
	Net.match_running = true
	Net.roster_changed.emit()
	await get_tree().process_frame
	_check("a running match disables every button",
		(picker.get_child(0) as Button).disabled, true)
	_check("and every skin swatch with them",
		_skin_tile(skins, Skins.DEFAULT).disabled, true)
	_check("with the caption saying so", caption.text.begins_with("LOCKED"), true)
	_skin_tile(skins, Skins.NAMES.find("void")).pressed.emit()
	_check("a swatch pressed after Start does nothing", Net.player_skin(1),
		Skins.NAMES.find("muck"))
	(picker.get_child(Loadout.Weapon.SPEAR) as Button).pressed.emit()
	_check("and a press does nothing", Net.player_weapon(1), Loadout.Weapon.BOW)
	Net.match_running = false
	Net.roster_changed.emit()
	await get_tree().process_frame
	_check("and back in the lobby they are live again",
		(picker.get_child(0) as Button).disabled, false)
	_check("the swatches too", _skin_tile(skins, Skins.DEFAULT).disabled, false)

	# Escape backs out of one thing at a time, and the button says which. On the
	# page it closes the page; on the lobby it would end the session, which is
	# why only the first half is driven here — the harness is standing in that
	# session. The two share `_on_leave`, so proving the button is proving the
	# key.
	_check("the page is up for this", lobby.get("_character_open"), true)
	leave.pressed.emit()
	await get_tree().process_frame
	_check("BACK closes the page rather than the session", Net.in_session, true)
	_check("and the lobby is back", stack.visible, true)
	_check("with LEAVE meaning leave again", leave.text.contains("LEAVE"), true)

	# **And the page cannot outlive your own roster row.** A host who kicks you
	# arrives as a roster without you in it; the page would otherwise stay up
	# with the camera aimed at whoever inherited your slot.
	open_page.pressed.emit()
	await get_tree().process_frame
	_check("the page opens again", lobby.get("_character_open"), true)
	var mine: Dictionary = Net.players[1]
	Net.players.erase(1)
	Net.roster_changed.emit()
	await get_tree().process_frame
	_check("losing your own row closes it", lobby.get("_character_open"), false)
	Net.players[1] = mine
	Net.roster_changed.emit()
	await get_tree().process_frame

	lobby.queue_free()
	await get_tree().process_frame

	# And the client's view of the same screen. Editing the config has been
	# host-gated since the panel was written, so a client's copy was forty dead
	# dials taking the widest column on the screen; it is not shown at all now.
	# The page and the roster count are - a client picks a weapon and a body and
	# counts the room exactly as the host does.
	Net.is_host = false
	Net.roster_changed.emit()
	var client := LOBBY_SCENE.instantiate()
	add_child(client)
	await get_tree().process_frame
	var client_settings := client.get_node_or_null("%MatchSettings") as Control
	var client_button := client.get_node_or_null("%CharacterButton") as Button
	var client_row := client.get_node_or_null("%WeaponRow") as Control
	var client_skins := client.get_node_or_null("%SkinRow") as Control
	var client_ready := client.get_node_or_null("%ReadyButton") as Button
	var client_start := client.get_node_or_null("%StartButton") as Button
	var client_count := client.get_node_or_null("%PlayerCount") as Label
	var client_list := client.get_node_or_null("%Scroll") as Control
	if client_settings == null or client_button == null or client_row == null \
			or client_ready == null or client_start == null \
			or client_count == null or client_list == null:
		print("weapon_select: lobby FAIL - the client scene is missing controls")
		_failures += 1
	else:
		_check("a client is not shown the config at all",
			client_settings.visible, false)
		# The rail is the one place a client's screen differs, and it differs by
		# what is at the foot of it: READY UP instead of START MATCH.
		_check("it gets READY UP at the foot of the rail", client_ready.visible, true)
		_check("and not the host's START MATCH", client_start.visible, false)
		_check("but still gets the way in to the page",
			client_button.visible, true)
		_check("with the weapon strip on it", client_row.visible, true)
		_check("and the skin grid beside that",
			client_skins != null and client_skins.visible, true)
		_check("and still gets the roster count", client_count.visible, true)
		_check("out, exactly as the host's is", client_list.visible, true)
	client.queue_free()
	Net.is_host = true
	await get_tree().process_frame
	print("weapon_select: lobby %s" % ("PASS" if _failures == before else "FAIL"))


func _run_ring() -> void:
	_scenario("the ring carries what the roster says")
	var before := _failures
	var backdrop := BogBackdrop.new()
	add_child(backdrop)
	backdrop.set_roster([
		{"name": "Spearer", "team": MatchConfig.TEAM_NONE,
			"weapon": Loadout.Weapon.SPEAR},
		{"name": "Archer", "team": MatchConfig.TEAM_NONE,
			"weapon": Loadout.Weapon.BOW},
		{"name": "Swinger", "team": MatchConfig.TEAM_NONE,
			"weapon": Loadout.Weapon.SWORD},
	])
	# Two frames: `_tick_hand` is a per-frame poll and the animator's carry tilt
	# is written from `_process`, so the hands settle on the frame after the
	# roster lands rather than inside `set_roster`.
	await get_tree().process_frame
	await get_tree().process_frame

	var bogs: Array = backdrop.get("_bogs")
	_check("the ring stood up three Bogs", bogs.size(), 3)
	if bogs.size() < 3:
		print("weapon_select: ring FAIL — the backdrop is empty")
		_failures += 1
		return

	# **Remote Bogs, which is the point of the ring** (see `BogBackdrop`'s
	# header). If the hand were drawn from anything the owning client knows and
	# nobody else does, these three would all be empty.
	for bog: Bog in bogs:
		_check("%s is a remote Bog" % bog.display_name, bog.is_local(), false)

	var want := [Loadout.Weapon.SPEAR, Loadout.Weapon.BOW, Loadout.Weapon.SWORD]
	for i in 3:
		var bog: Bog = bogs[i]
		var hand: HeldGear = bog.held_gear
		_check("%s was handed the weapon it picked" % bog.display_name,
			bog.weapon, want[i])
		# And **stands** in the weapon it picked (D-070). The pose is the other
		# half of "your character should only show the weapon you have selected":
		# a Bog holding a great sword in an archer's stance is showing two.
		#
		# Read off the graph's own parameter rather than off `Loadout`, so this
		# is "what the animator is playing" and not "what the table says it
		# should be" — the second would agree with itself whatever the graph had
		# been built with.
		_check("%s stands in its own carry pose" % bog.display_name,
			_carry_pose(bog), Loadout.CARRY_CLIPS[want[i]])
		_check("%s: a shaft?" % bog.display_name, hand.is_carried(),
			want[i] == Loadout.Weapon.SPEAR)
		_check("%s: a bow?" % bog.display_name, hand.has_bow(),
			want[i] == Loadout.Weapon.BOW)
		_check("%s: a great sword?" % bog.display_name, hand.has_sword(),
			want[i] == Loadout.Weapon.SWORD)
		# Never an arrow: nothing in the lobby is drawing.
		_check("%s: no arrow" % bog.display_name, hand.has_arrow(), false)

	# And a change of mind moves it, which is the path a player arrowing through
	# the strip takes — `set_roster` on every roster change, the same call that
	# repaints a team (D-046).
	backdrop.set_roster([
		{"name": "Spearer", "team": MatchConfig.TEAM_NONE,
			"weapon": Loadout.Weapon.SWORD},
		{"name": "Archer", "team": MatchConfig.TEAM_NONE,
			"weapon": Loadout.Weapon.SPEAR},
		{"name": "Swinger", "team": MatchConfig.TEAM_NONE,
			"weapon": Loadout.Weapon.BOW},
	])
	await get_tree().process_frame
	await get_tree().process_frame
	_check("swapping a pick swaps the hand",
		(bogs[0] as Bog).held_gear.has_sword(), true)
	_check("and takes the old one out of it",
		(bogs[0] as Bog).held_gear.is_carried(), false)
	_check("the archer puts its bow down",
		(bogs[1] as Bog).held_gear.has_bow(), false)
	_check("and picks up a shaft", (bogs[1] as Bog).held_gear.is_carried(), true)
	# The pose follows the prop, on the same frame and through the same call
	# (D-070). `BogBackdrop._equip` sets `Bog.weapon` and asks
	# `BogCombat.refresh_hand()`, which repaints the fists *and* re-points the
	# carry layer — two halves of one answer, so there is no frame on which a
	# ring Bog is holding one weapon and standing in another's stance.
	_check("the swordsman's stance came with it",
		_carry_pose(bogs[0] as Bog),
		Loadout.CARRY_CLIPS[Loadout.Weapon.SWORD])
	_check("and the archer's went back",
		_carry_pose(bogs[1] as Bog),
		Loadout.CARRY_CLIPS[Loadout.Weapon.SPEAR])

	backdrop.queue_free()
	print("weapon_select: ring %s" % ("PASS" if _failures == before else "FAIL"))


## Which clip this Bog's carry layer is actually playing, off the animator's own
## `carry_pick` (D-070).
##
## The `transition_request` parameter is write-only in the sense that matters —
## it reports "" once the transition has been taken — so this reads
## `current_state`, which is the input name the node settled on, and maps it back
## through `Loadout.CARRY_CLIPS`. The names are ordinals (`BogAnimator`'s own
## `_carry_input`) rather than clip names precisely because two weapons share a
## clip, so the round trip has to go through the table.
func _carry_pose(bog: Bog) -> String:
	var animator := bog.get_node_or_null("AnimationTree") as BogAnimator
	if animator == null:
		return "<no animator>"
	var state := String(animator.get("parameters/carry_pick/current_state"))
	for i in Loadout.CARRY_CLIPS.size():
		if state == "w%d" % i:
			return Loadout.CARRY_CLIPS[i]
	return "<%s>" % state


## One swatch off the skin strip. The strip is built in `Skins.all()` order, so
## a skin index is a child index -- which is also what makes "only one is lit" a
## thing this file can ask.
func _skin_tile(grid: Container, skin: int) -> Button:
	return grid.get_child(skin) as Button


## The texture a Bog's body is actually drawn with, read off the material the
## renderer will use rather than off whatever was handed to `wear_skin` -- the
## rule `tools/team_tint.gd` reads a tint by, and for its reason: what is
## asserted has to be what ends up on the screen.
func _worn(bog: Bog) -> Variant:
	if bog == null or bog.body_mesh == null:
		return "<no body>"
	var material := bog.body_mesh.get_active_material(0) as BaseMaterial3D
	if material == null:
		return "<not a standard material>"
	return material.albedo_texture


## Whether every team is in a different body. The invariant the whole Teams half
## rests on, asked of the array rather than of the path that maintains it.
func _skins_are_unique() -> bool:
	var seen := {}
	for team in Net.config.team_count:
		var skin := Net.team_skin(team)
		if seen.has(skin):
			return false
		seen[skin] = true
	return true


## The box the ring occupies on screen, in base-viewport pixels: how far left
## and right the Bogs and their nameplates reach, and how high the highest
## nameplate and the highest head go.
##
## Projected rather than guessed. The panels are laid out in the scene at fixed
## offsets and the ring is laid out in 3D at a distance that depends on how many
## Bogs are in it, so the only place the two are comparable is the screen, and
## the only honest way to compare them is to ask the camera.
##
## The **nameplate is included in the width**, and it is usually what sets it:
## an eleven-character name is 1.3 m of world, wider than the Bog under it, and
## a name half behind the match rail is the failure this is looking for.
func _ring_box(ring: BogBackdrop) -> Dictionary:
	var camera := ring.get("_camera") as Camera3D
	var bogs: Array = ring.get("_bogs")
	var plate_top := INF
	var head_top := INF
	var left := INF
	var right := -INF
	var counted := 0
	for bog: Bog in bogs:
		if not bog.visible:
			continue
		counted += 1
		if bog.body_mesh != null:
			head_top = minf(head_top, _screen_top(camera, bog.body_mesh))
		# **The body's width comes from the capsule, not from the mesh.** A
		# skinned mesh's `get_aabb()` is the bind pose inflated by a skinning
		# margin, and on this body it reaches far enough toward the lens that
		# one of its corners projects a thousand pixels off the side of the
		# screen — a number about the bounding volume and not about the Bog.
		# `Bog.CAPSULE_RADIUS` is what the game itself calls this Bog's width,
		# so it is what the measurement uses, swept across the camera's own
		# right at head height and at the feet.
		var side := _camera_right(camera) * Bog.CAPSULE_RADIUS
		for foot: float in [0.0, Bog.STAND_HEIGHT]:
			var centre := bog.global_position + Vector3.UP * foot
			for edge: Vector3 in [centre - side, centre + side]:
				var at := _project(camera, edge).x
				left = minf(left, at)
				right = maxf(right, at)
		var plate := bog.get_node_or_null("Nameplate")
		if plate == null:
			continue
		for node: Node in plate.find_children("", "Label3D", true, false):
			plate_top = minf(plate_top, _label_top(camera, node as Label3D))
			var text_span := _label_span(camera, node as Label3D)
			left = minf(left, text_span.x)
			right = maxf(right, text_span.y)
	return {"plate": plate_top, "head": head_top,
		"left": left, "right": right, "bogs": counted}


## The leftmost and rightmost **base viewport** columns a nameplate covers, as
## `(left, right)`.
##
## A billboarded `Label3D` reports a cube whose every axis is the text's
## diagonal, which `_label_top` has to correct for vertically. Horizontally it
## needs no correction worth making — a name is an order of magnitude wider than
## it is tall, so the diagonal and the width agree to within a centimetre — and
## the box is small enough and far enough from the lens that projecting its
## corners is honest, which is exactly what is *not* true of a skinned body's
## AABB (see `_ring_box`).
func _label_span(camera: Camera3D, label: Label3D) -> Vector2:
	if camera == null or label == null:
		return Vector2(INF, -INF)
	var box := label.get_aabb()
	var to_world := label.global_transform
	var span := Vector2(INF, -INF)
	for corner in 8:
		var at := _project(camera, to_world * box.get_endpoint(corner)).x
		span = Vector2(minf(span.x, at), maxf(span.y, at))
	return span


## The camera's own right, in world space: what "sideways on screen" means from
## where it is standing.
func _camera_right(camera: Camera3D) -> Vector3:
	if camera == null:
		return Vector3.RIGHT
	return camera.global_transform.basis.x.normalized()


## The top edge of a nameplate, in base-viewport rows.
##
## **Not `get_aabb()`.** A billboarded `Label3D` reports a *cube* — every axis
## the length of the text's diagonal, so that culling is right from any angle —
## which for a long name puts its "top" 18 cm above where any ink is and would
## have this check measuring a box nobody can see. The text's own world height
## is `font_size * pixel_size` (`Nameplate`'s header says as much: about 0.21 m),
## centred on the node, with the outline standing off it. That is the edge a
## player sees, so that is the edge the strip has to clear.
func _label_top(camera: Camera3D, label: Label3D) -> float:
	if camera == null or label == null:
		return INF
	var half := (label.font_size * 0.5 + label.outline_size) * label.pixel_size
	return _project(camera, label.global_position + Vector3.UP * half).y


## The topmost row of the **base viewport** this instance covers: every corner
## of its world-space box through the camera, smallest y wins (screen y grows
## downward).
##
## The projection is built here rather than taken from
## `Camera3D.unproject_position`, and that is not fussiness. `unproject_position`
## answers in the pixels of the window the harness happens to have, and a
## headless run has a **1600x1600** one — so the honest-looking call returns a
## number in a viewport that does not exist and that nothing in the scene is
## laid out against. The row's offsets are in base-viewport units, so the ring
## has to be measured in them too, whatever window is open.
func _screen_top(camera: Camera3D, what: VisualInstance3D) -> float:
	if camera == null or what == null:
		return INF
	var box := what.get_aabb()
	var to_world := what.global_transform
	var top := INF
	for corner in 8:
		top = minf(top, _project(camera, to_world * box.get_endpoint(corner)).y)
	return top


## The viewport every `Control` offset in this project is written in.
func _base_viewport() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1600)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 900)))


## One world point in base-viewport pixels.
##
## The projection is built here rather than taken from
## `Camera3D.unproject_position`, and that is not fussiness. `unproject_position`
## answers in the pixels of the window the harness happens to have, and a
## headless run has a **1600x1600** one -- so the honest-looking call returns a
## number in a viewport that does not exist and that nothing in the scene is
## laid out against. Every `Control` offset in this project is written in base
## viewport units, so the ring has to be measured in them too, whatever window
## is open.
func _project(camera: Camera3D, point: Vector3) -> Vector2:
	var base := _base_viewport()
	var projection := Projection.create_perspective(camera.fov, base.x / base.y,
		camera.near, camera.far, camera.keep_aspect == Camera3D.KEEP_WIDTH)
	var view := camera.global_transform.affine_inverse() * point
	var clip := projection * Vector4(view.x, view.y, view.z, 1.0)
	if clip.w <= 0.0:
		return Vector2(INF, INF)  # behind the lens; it is on nobody's screen
	return Vector2((clip.x / clip.w * 0.5 + 0.5) * base.x,
		(0.5 - clip.y / clip.w * 0.5) * base.y)
