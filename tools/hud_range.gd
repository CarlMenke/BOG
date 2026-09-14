extends Node
## The HUD over a real running match, in whatever state needs looking at.
## Development tool, not shipped.
##
## PLAN 4 has not happened yet, so there is no island to play the HUD over. This
## instances `tools/combat_range.tscn` — which already stands up a genuine
## offline match with a local Gub, spawned opponents and a working camera — and
## hangs `scenes/ui/hud.tscn` on top of it, exactly the way the arena is meant
## to. Every number the HUD shows therefore comes from the real `MatchState`,
## and only the *events* are staged.
##
## Extra names are written straight into `Net.players` and extra rows straight
## into `MatchState.stats`. Those are the same public dictionaries
## `combat_range` writes its dummies into: a scoreboard is not worth looking at
## with two rows in it, and no part of this reaches past an API the game uses.
##
##     Godot --path . --resolution 1600x900 --script tools/snapshot.gd -- \
##         res://tools/hud_range.tscn out.png 110 <mode>
##
## Modes: hud, hud_teams, hud_cooldown, hud_letters, hud_hold, hud_elder,
##        killfeed, scoreboard, scoreboard_letters, pause, results,
##        results_letters, dead, spectate,
##        hud_letters_teams, scoreboard_letters_teams, results_letters_teams,
##        reload_timer.
##
## `reload_timer` is the one mode here that prints a verdict and sits in the
## gate (D-054). It throws a real spear and reads the spear tile every frame of
## the throw: nothing through the windup, a sweep and a number matching the real
## recharge after the release, both gone the frame the spear is back, and a
## crosshair with no ring anywhere in it throughout. Its PASS needs about 260
## ticks; a picture of the tile mid-recharge is the same mode at 130:
##
##     ... --resolution 1600x900 --script tools/snapshot.gd -- \
##         res://tools/hud_range.tscn out/reload_timer.png 130 reload_timer
##
## The three `*_letters_teams` modes are the letters pictures under Teams, where
## the lamps, a team row on the scoreboard and a team row on the results table
## all show a team's pooled letters rather than one player's (D-049).
##
## The `hud*` ones and `scoreboard_letters` are what the D-036 pass was judged
## on. `hud_hold` is the slow one on purpose: it collects a real card through
## the real pickup path and then stands there, so its shot has to be taken a few
## seconds in to catch the hold part-way rather than at the very start of it —
## and `hud_elder` is slow for the same reason and takes the same care: it
## claims a real robe off a real death so the countdown it draws is the host's
## own clock (D-040), and its shot wants to land a few seconds in so the bar is
## part-drained rather than full.

const RANGE_SCENE := preload("res://tools/combat_range.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")

## Well clear of the combat range's own 900s.
const EXTRA_BASE := 640
const EXTRA := [
	{"name": "Pipwick", "kills": 9, "deaths": 3},
	{"name": "Bramblewick", "kills": 6, "deaths": 5},
	{"name": "Mossback", "kills": 4, "deaths": 7},
	{"name": "Toadflax", "kills": 2, "deaths": 8},
	{"name": "Nettle", "kills": 1, "deaths": 9},
]

## Every mode whose picture is of the letters condition. Listed once because
## four separate things have to agree about it — the win condition, the roster's
## letter masks, the local player's own, and the results summary — and a mode
## that set three of the four would look right and prove nothing.
const LETTER_MODES := ["hud_letters", "hud_hold", "scoreboard_letters",
	"results_letters", "hud_letters_teams", "scoreboard_letters_teams",
	"results_letters_teams"]
## The letters modes played as Teams. A subset of `LETTER_MODES`, never a
## separate list, so a Teams picture cannot forget to be a letters one.
const TEAM_LETTER_MODES := ["hud_letters_teams", "scoreboard_letters_teams",
	"results_letters_teams"]

## `reload_timer`'s recharge, and how far the printed seconds may sit from the
## real remaining time. A tenth is the task's own tolerance and is also what the
## tile's rounding (tenths, always up) can cost.
const RELOAD_RECHARGE := 3.0
const RELOAD_TOLERANCE := 0.105
## Anything on the crosshair with one of these in its name would be the ring
## coming back under another label (D-036).
const RING_WORDS := ["ring", "recharge", "cooldown", "progress", "fraction", "cycle"]

var _mode: String = "hud"
var _reload_failures: PackedStringArray = []
var _hud: CanvasLayer


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 4:
		_mode = args[3]

	# The range starts the session in its own `_ready`, so it has to be in the
	# tree before anything below can touch the roster.
	add_child(RANGE_SCENE.instantiate())
	_hud = HUD_SCENE.instantiate()
	add_child(_hud)

	await get_tree().process_frame
	await get_tree().process_frame
	_stage()


func _stage() -> void:
	# The combat range turns the clock off, which is right for a firing range
	# and useless for photographing a HUD whose top-centre element is a clock.
	Net.config.time_limit = 600
	MatchState.time_left = 247.0
	Net.config.kill_limit = 15
	if _mode == "hud_teams" or TEAM_LETTER_MODES.has(_mode):
		Net.config.mode = MatchConfig.Mode.TEAMS
		Net.config.team_count = 2
	if _mode == "hud_cooldown":
		# Long enough that the recharge is still running when the snapshot is
		# taken; the range's own 1.5 s is over before then. Since D-054 the dark
		# tile also carries its recharge fill and seconds; `reload_timer` is the
		# mode that measures them.
		Net.config.spear_recharge = 6.0
	if LETTER_MODES.has(_mode):
		Net.config.win_condition = MatchConfig.WinCondition.LETTERS
	if _mode == "spectate":
		Net.config.win_condition = MatchConfig.WinCondition.LIVES
		Net.config.lives = 3
	if _mode == "reload_timer":
		# The shipping three, set rather than inherited from the range's 1.5.
		Net.config.spear_recharge = RELOAD_RECHARGE
	if _mode == "hud_elder":
		# The shipping twenty, so the picture is of the bar a player actually
		# sees rather than of one this file invented a length for.
		Net.config.elder_duration = 20.0
	_populate_roster()
	# Every mode but one. `hud_cooldown` is the bar with *nothing* available —
	# spear recharging, both stacks at zero — which is not a corner case but
	# what a Gub looks like for the first minute of every life since D-032, and
	# the one shot that proves an empty slot reads as empty rather than as
	# broken. The full bar is covered by `hud` and the mixed case by `hud_hold`.
	if _mode != "hud_cooldown":
		_stock_the_bar()

	match _mode:
		"killfeed", "scoreboard", "scoreboard_letters", "results", "results_letters", \
				"scoreboard_letters_teams", "results_letters_teams":
			_stage_kills()
		"hud_cooldown":
			_stage_throw()
		"hud_hold":
			_stage_kills()
			_stage_hold()
		"hud_elder":
			_stage_kills()
			_stage_elder()
		"reload_timer":
			_stage_kills()
			_run_reload_timer()
		"dead":
			_stage_kills()
			var dying: Dictionary = MatchState.stats.get(1, {})
			dying["alive"] = false
			MatchState.local_death.emit(Net.config.respawn_delay)
		"spectate":
			_stage_kills()
			var mine: Dictionary = MatchState.stats.get(1, {})
			mine["lives_left"] = 0
			mine["alive"] = false
			MatchState.local_death.emit(0.0)
		_:
			_stage_kills()

	MatchState.scores_changed.emit()

	match _mode:
		"scoreboard", "scoreboard_letters", "scoreboard_letters_teams":
			(_hud.get_node("%Scoreboard") as Scoreboard).open()
		"pause":
			(_hud.get_node("%PauseMenu") as PauseMenu).open()
		"results", "results_letters", "results_letters_teams":
			(_hud.get_node("%Results") as ResultsScreen).show_summary(_summary())


## Names and scores for people who are not actually here, so the scoreboard and
## the score line have something to rank.
func _populate_roster() -> void:
	var teams := Net.config.mode == MatchConfig.Mode.TEAMS
	if teams:
		Net.players[1]["team"] = 0
	for i in EXTRA.size():
		var peer_id := EXTRA_BASE + i
		Net.players[peer_id] = {
			"name": EXTRA[i]["name"], "team": i % 2 if teams else 0, "ready": true,
		}
		MatchState.stats[peer_id] = {
			"kills": EXTRA[i]["kills"], "deaths": EXTRA[i]["deaths"],
			"lives_left": Net.config.lives, "alive": i != 3,
			"respawn_at": 0.0, "last_attacker": 0, "last_attacker_at": -999.0,
		}
	# The local Gub needs a score of its own or every screen shows a zero.
	var mine: Dictionary = MatchState.stats.get(1, {})
	if not mine.is_empty():
		mine["kills"] = 7
		mine["deaths"] = 4
	if TEAM_LETTER_MODES.has(_mode):
		_deal_team_letters(mine)
	elif LETTER_MODES.has(_mode):
		_deal_letters(mine)
	Net.roster_changed.emit()


## Hand out G/U/B masks, so the lamps, the scoreboard column and the results
## table have a spread to draw instead of six empty rows.
##
## Deliberately not "everybody has two". The interesting read on all three of
## those screens is *which* letters somebody is missing, so the roster is built
## so that is the only thing telling two of them apart: the two players on two
## letters are not on the same two.
##
## **A completed set is only dealt to the results mode**, and that is a scar.
## Dealt to every letters mode, it took the *live* ones down with it: the first
## real kill in `hud_hold` ran `_check_win`, which found a row holding G, U and
## B and quite correctly ended the match — so the mode that exists to photograph
## a hold photographed the results screen instead. A staged roster is still real
## state, and the win check does not care that a tool wrote it.
func _deal_letters(mine: Dictionary) -> void:
	var deal := [MatchState.LETTER_U | MatchState.LETTER_B,
		MatchState.LETTER_G | MatchState.LETTER_B,
		MatchState.LETTER_U, 0, MatchState.LETTER_G]
	if _mode == "results_letters":
		deal[0] = MatchState.LETTER_G | MatchState.LETTER_U | MatchState.LETTER_B
	for i in EXTRA.size():
		var row: Dictionary = MatchState.stats.get(EXTRA_BASE + i, {})
		if not row.is_empty():
			row["letters"] = deal[i]
	if mine.is_empty():
		return
	# `hud_hold` starts from nothing, and has to. A card is `randi() % 3` with no
	# idea who is about to walk into it (D-033), and one for a letter you already
	# hold is consumed on touch without starting a hold — so a local player
	# already holding two would fail to produce the picture two times in three,
	# and would do it silently.
	mine["letters"] = 0 if _mode == "hud_hold" \
		else MatchState.LETTER_G | MatchState.LETTER_U


## The Teams deal. The local player (team 0) and the extras alternate teams, so
## team 0 is you, Pipwick, Mossback and Nettle, and team 1 is Bramblewick and
## Toadflax. Within a team no two rows share a letter — a teammate's letter is a
## duplicate and would never have been banked (D-049) — so the pooled masks are
## exactly the OR of the rows, and they are written into `_team_letters` the way
## `_sync_letters` would have written them.
##
## Team 0 pools to G·U and is one B short: the picture worth taking is a team
## lamp lit by a letter the local player never touched. Only the results mode
## completes the word, for the scar `_deal_letters` records.
func _deal_team_letters(mine: Dictionary) -> void:
	var deal := [0, MatchState.LETTER_B, MatchState.LETTER_U, 0, 0]
	if _mode == "results_letters_teams":
		deal[0] = MatchState.LETTER_B
	for i in EXTRA.size():
		var row: Dictionary = MatchState.stats.get(EXTRA_BASE + i, {})
		if not row.is_empty():
			row["letters"] = deal[i]
	if not mine.is_empty():
		mine["letters"] = MatchState.LETTER_G
	MatchState._team_letters.clear()
	for peer_id: int in MatchState.stats:
		var team := Net.player_team(peer_id)
		MatchState._team_letters[team] = MatchState.team_letters(team) \
			| MatchState.letters_for(peer_id)


## A feed with one row in it proves nothing. Emitted rather than reported so
## the causes can be mixed — a spear kill, a fall, and one involving the local
## player, which is the row that has to stand out.
func _stage_kills() -> void:
	MatchState.player_killed.emit(EXTRA_BASE + 3, EXTRA_BASE, Gub.Cause.SPEAR)
	MatchState.player_killed.emit(EXTRA_BASE + 1, EXTRA_BASE + 1, Gub.Cause.VOID)
	MatchState.player_killed.emit(EXTRA_BASE + 2, 1, Gub.Cause.SPEAR)
	MatchState.player_killed.emit(1, EXTRA_BASE, Gub.Cause.SPEAR)


## Throw a real spear, so the spear tile is dark because a real `GubCombat` says
## so rather than because this tool set a flag.
func _stage_throw() -> void:
	var combat := _local_combat()
	if combat != null:
		combat.try_throw_spear()


## Two mushrooms and one lure into the local Gub's pack.
##
## Not decoration. A Gub spawns carrying nothing (D-032), so without this every
## reference shot of the ability bar is two empty slots — a real state, and the
## least informative one to photograph. Handed over exactly the way
## `tools/combat_range.gd` hands one over: through the host-only `grant_*` the
## pickup path itself calls, so the counts on screen arrived the way a player's
## would.
func _stock_the_bar() -> void:
	var combat := _local_combat()
	if combat == null:
		return
	combat.grant_mushroom(2)
	combat.grant_lure(1)


## Collect a letter card for real, and then stand there holding it.
##
## The card comes out of an actual death with `letter_drop_chance` forced to 1
## so the roll cannot come up a mushroom, and it is claimed by the player's own
## body walking into the `Pickup` area. That is the same chain
## `tools/combat_range.gd letter` exercises, and it is why neither of them
## writes into `MatchState._letter_holds` by hand: a hold staged directly would
## draw identically and would prove nothing about the thing being drawn.
func _stage_hold() -> void:
	var player := MatchState.local_gub()
	var victim := _a_dummy()
	if player == null or victim == 0:
		return
	if MatchState.phase != MatchState.Phase.PLAYING:
		push_warning("hud_range: nothing to hold — the match has not started yet")
		return
	Net.config.letter_drop_chance = 1.0
	# The drop lands where the blow struck rather than at the body, so the card
	# can be put down in front of the player without moving anybody.
	MatchState.report_kill(victim, Net.local_id(), Gub.Cause.SPEAR,
		player.global_position + player.facing() * 1.2, Vector3.FORWARD * 18.0, "Spine1")


## Put the robe on the local Gub, for real, and then stand there wearing it.
##
## The same argument `_stage_hold` makes, one feature along: the robe comes out
## of an actual death with `elder_drop_chance` forced to 1 and is claimed by the
## player's own body walking into the `Pickup` area, so the countdown the HUD
## draws is `MatchState`'s own host-owned clock rather than a number staged into
## `_elders` by hand. A bar filled directly would draw identically and would
## prove nothing about the thing being drawn — which is the whole of D-039.
##
## It also happens to be the one picture that shows the ability bar's first tile
## as a *bolt*: an Elder has no spear (D-038), and until now nothing in this file
## had ever put one on screen.
func _stage_elder() -> void:
	var player := MatchState.local_gub()
	var victim := _a_dummy()
	if player == null or victim == 0:
		return
	if MatchState.phase != MatchState.Phase.PLAYING:
		push_warning("hud_range: nothing to wear — the match has not started yet")
		return
	Net.config.elder_drop_chance = 1.0
	MatchState.report_kill(victim, Net.local_id(), Gub.Cause.SPEAR,
		player.global_position + player.facing() * 1.2, Vector3.FORWARD * 18.0, "Spine1")


## The spear tile's recharge readout, measured over one real throw (D-054).
##
## Read off the tile itself -- `recharge_progress()` and `recharge_text()` are
## what `_draw` draws -- rather than recomputed from `GubCombat`, because the
## thing under test is the HUD's choice of *when* to hand the tile a timer, and
## recomputing it here would be testing a copy of that choice.
func _run_reload_timer() -> void:
	var slot := _hud.get_node("%SpearSlot") as AbilitySlot
	var crosshair := _hud.get_node("%Crosshair") as Crosshair
	var combat := _local_combat()
	if slot == null or crosshair == null or combat == null:
		print("hud_range: no spear tile, crosshair or local Gub - reload_timer FAIL")
		return
	_check_formatting()
	_check_crosshair(crosshair, "before the throw")

	var wait := 0
	while not combat.has_spear() and wait < 120:
		await RenderingServer.frame_pre_draw
		wait += 1
	await RenderingServer.frame_pre_draw
	await RenderingServer.frame_pre_draw
	_expect(combat.has_spear(), "no spear to throw after %d frames" % wait)
	_expect_no_timer(slot, "ready")

	combat.try_throw_spear()
	_expect(combat.is_winding_up(), "the click did not start a windup")
	var windup_frames := 0
	while combat.is_winding_up() and windup_frames < 120:
		await RenderingServer.frame_pre_draw
		# Read just before the frame is drawn, so after the HUD's `_process` and
		# the throw's own: what is checked is what is about to be on screen.
		if combat.is_winding_up():
			_expect_no_timer(slot, "windup frame %d" % windup_frames)
			_check_crosshair(crosshair, "windup frame %d" % windup_frames)
		windup_frames += 1
	var released_at := Time.get_ticks_msec() * 0.001
	_expect(windup_frames > 10, "the windup lasted only %d frames" % windup_frames)

	var samples := 0
	var saw_mid := false
	while not combat.has_spear() and samples < 600:
		await RenderingServer.frame_pre_draw
		samples += 1
		if combat.has_spear():
			break
		var remaining := combat.spear_cooldown()
		var progress := slot.recharge_progress()
		var text := slot.recharge_text()
		if samples % 20 == 0:
			_check_crosshair(crosshair, "recharge frame %d" % samples)
		# The first frame after the release is the HUD's first look at it.
		if samples < 2 or remaining <= 0.0:
			continue
		var elapsed := Time.get_ticks_msec() * 0.001 - released_at
		if not saw_mid and elapsed >= RELOAD_RECHARGE * 0.5:
			saw_mid = true
			_expect(progress > 0.0 and progress < 1.0,
				"mid-recharge sweep is %.3f, not between 0 and 1" % progress)
			_expect(absf(progress - (1.0 - remaining / RELOAD_RECHARGE)) < 0.05,
				"sweep %.3f against %.2f s left of %.1f" % [progress, remaining, RELOAD_RECHARGE])
			_expect(text.is_valid_float() and absf(float(text) - remaining) <= RELOAD_TOLERANCE,
				"mid-recharge the tile reads \"%s\" with %.2f s left" % [text, remaining])
			_expect(absf(float(text) - (RELOAD_RECHARGE - elapsed)) <= RELOAD_TOLERANCE + 0.05,
				"the tile reads \"%s\" %.2f s after the release of a %.1f s recharge" % [
					text, elapsed, RELOAD_RECHARGE])
			print("hud_range: %.2f s after the release the tile reads \"%s\" over a %.2f sweep (%.2f s left)" % [
				elapsed, text, progress, remaining])
		# Every frame, not only the middle one: the number must never be missing
		# or off the real remaining time while the spear is away.
		elif not text.is_valid_float() or absf(float(text) - remaining) > RELOAD_TOLERANCE:
			_expect(false, "recharge frame %d: tile reads \"%s\" with %.2f s left" % [
				samples, text, remaining])
	_expect(saw_mid, "never sampled the middle of the recharge")
	_expect(combat.has_spear(), "the spear never came back")
	await RenderingServer.frame_pre_draw
	_expect_no_timer(slot, "spear back")
	_check_crosshair(crosshair, "spear back")

	if _reload_failures.is_empty():
		print("hud_range: %d windup frames with no timer, recharge timed, gone when back - reload_timer PASS" % windup_frames)
	else:
		for failure in _reload_failures:
			print("hud_range: %s" % failure)
		print("hud_range: %d reload check(s) failed - reload_timer FAIL" % _reload_failures.size())


## The number's format, on a tile of its own that never enters the tree, so the
## live one under test is not touched. Tenths below ten seconds rounded up, whole
## seconds above, nothing at all when armed or given no total.
func _check_formatting() -> void:
	var tile := (load("res://scenes/ui/ability_slot.tscn") as PackedScene).instantiate() as AbilitySlot
	var cases := [
		[false, 1.41, 3.0, "1.5"], [false, 0.01, 3.0, "0.1"], [false, 2.0, 3.0, "2.0"],
		[false, 12.3, 15.0, "13"], [false, 9.97, 15.0, "10"], [true, 1.0, 3.0, ""],
		[false, 1.0, 0.0, ""], [false, 0.0, 3.0, ""],
	]
	for case: Array in cases:
		tile.set_armed(case[0], case[1], case[2])
		_expect(tile.recharge_text() == case[3], "set_armed(%s, %s, %s) reads \"%s\", want \"%s\"" % [
			case[0], case[1], case[2], tile.recharge_text(), case[3]])
	tile.free()


func _expect_no_timer(slot: AbilitySlot, when: String) -> void:
	_expect(slot.recharge_progress() < 0.0 and slot.recharge_text().is_empty(),
		"%s: tile shows sweep %.3f and \"%s\"" % [when, slot.recharge_progress(), slot.recharge_text()])


## The crosshair's whole surface: no property and no method whose name is a
## ring's, and `set_state` still takes the one boolean and nothing to divide.
func _check_crosshair(crosshair: Crosshair, when: String) -> void:
	var script := crosshair.get_script() as Script
	for entry: Dictionary in script.get_script_property_list() + script.get_script_method_list():
		var name_lower := String(entry["name"]).to_lower()
		for word: String in RING_WORDS:
			if name_lower.contains(word):
				_expect(false, "%s: the crosshair has \"%s\"" % [when, entry["name"]])
		if entry["name"] == "set_state" and entry.has("args"):
			_expect((entry["args"] as Array).size() == 1,
				"%s: Crosshair.set_state takes %d arguments" % [when, (entry["args"] as Array).size()])


func _expect(ok: bool, failure: String) -> void:
	if not ok and not _reload_failures.has(failure):
		_reload_failures.append(failure)


## Somebody for the local Gub to kill. Found rather than named: the combat range
## owns those peer ids, and a copy of the number in this file would be a second
## place to change the day it moves.
func _a_dummy() -> int:
	for peer_id: int in MatchState.gubs:
		if peer_id != Net.local_id():
			return peer_id
	return 0


func _local_combat() -> GubCombat:
	var gub := MatchState.local_gub()
	if gub == null:
		return null
	return gub.get_node_or_null("Combat") as GubCombat


func _summary() -> Dictionary:
	return {
		"reason": "letters" if LETTER_MODES.has(_mode) else "limit",
		"ranking": MatchState.ranking(),
		"stats": MatchState.stats,
		"mode": Net.config.mode,
		# What the results screen branches its letters column on, so a staged
		# summary has to carry it exactly as `MatchState._finish` does.
		"win_condition": Net.config.win_condition,
		"team_scores": {0: MatchState.team_score(0), 1: MatchState.team_score(1)},
		"team_letters": {0: MatchState.team_letters(0), 1: MatchState.team_letters(1)},
	}
