extends Node
## The HUD over a real running match, in whatever state needs looking at.
## Development tool, not shipped.
##
## PLAN 4 has not happened yet, so there is no island to play the HUD over. This
## instances `tools/combat_range.tscn` — which already stands up a genuine
## offline match with a local Bog, spawned opponents and a working camera — and
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
## Modes: hud, hud_teams, hud_cooldown, hud_health, hud_letters, hud_hold,
##        hud_elder, killfeed, scoreboard, scoreboard_letters, pause, results,
##        results_letters, dead, spectate,
##        hud_letters_teams, scoreboard_letters_teams, results_letters_teams,
##        reload_timer, weapon_tiles, controls, minimap, tutorial,
##        range, range_kill.
##
## `hud_health` is your own health bar part-empty (D-062). `hud` has it full,
## which is the state it spends most of a match in and the least interesting one
## to look at: the question this mode answers is whether a number sitting on an
## amber bar is legible, and whether the bar reads as *yours* where it sits in
## the column rather than as another cooldown.
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
## `weapon_tiles` is the second mode here that prints a verdict and sits in the
## gate (D-069). The first square on the ability bar is whichever weapon the
## local Bog actually brought — it has always swapped to a bolt for an Elder, and
## now it swaps for a lobby pick too — so this stands the same HUD up three times
## with three loadouts and requires the glyph, the caption **and the key cap** to
## follow. The cap is the half that is easy to get wrong and impossible to see in
## a screenshot of one loadout: a bolt is fired by the spear's own button and a
## bow is not, so a tile that kept the spear's cap would be telling an archer to
## press the wrong thing. Its shot is the three tiles as a player sees them:
##
##     ... --resolution 1600x900 --script tools/snapshot.gd -- \
##         res://tools/hud_range.tscn out/weapon_tiles.png 40 weapon_tiles
##
## `minimap` and `tutorial` are the letters round's two verdict modes and both
## are pictures worth having as well. `minimap` stages the corner map's three
## kinds of blip at measured bearings — a loose card twelve metres north-east, an
## enemy carrying one eighteen west, a teammate eight south — and reads the count
## of each back off `Minimap.debug_counts()` rather than off the photograph, so
## the thing asserted is what the map *found* and not what a compression
## artefact left behind. `tutorial` proves the once-per-machine flag both ways
## and then stands the panel up on its third card, which is the busiest of the
## six:
##
##     ... --resolution 1600x900 --script tools/snapshot.gd -- \
##         res://tools/hud_range.tscn out/tutorial.png 60 tutorial
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
const TUTORIAL_SCENE := preload("res://scenes/ui/tutorial.tscn")

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
	"results_letters_teams", "minimap"]
## The letters modes played as Teams. A subset of `LETTER_MODES`, never a
## separate list, so a Teams picture cannot forget to be a letters one.
##
## `minimap` is in here for a reason that is not a picture: a teammate only
## exists in Teams — `Net.player_team` is `TEAM_NONE` for everyone in a
## free-for-all, and the map draws an ally dot on nobody — so the one mode whose
## verdict counts allies has to be played as a team game to have any.
const TEAM_LETTER_MODES := ["hud_letters_teams", "scoreboard_letters_teams",
	"results_letters_teams", "minimap"]

## Where the minimap mode puts its three blips, relative to the local Bog.
## Bearings first and distances second: what the map has to get right is that a
## card to the north-east draws up and to the right of you when you are facing
## north, and all three are well inside `Minimap.RANGE_M` so a miscount cannot
## be blamed on the rim.
const MINIMAP_CARD := Vector3(8.49, 0.0, -8.49)
const MINIMAP_THIEF := Vector3(-18.0, 0.0, 0.0)
const MINIMAP_MATE := Vector3(0.0, 0.0, 8.0)
## The card the loose blip carries and the one the thief is holding. Two
## different letters, so a map that drew one blip twice would read as a PASS on
## the counts and a FAIL on the picture.
const MINIMAP_LOOSE_LETTER := MatchState.LETTER_B
const MINIMAP_HELD_LETTER := MatchState.LETTER_O

## Which card the `tutorial` mode photographs. The third — the capture
## performance — because it is the only one of the six with a pouch, a sunburst
## and a HUD lamp in it, so a frame of it exercises every primitive the other
## five are drawn from.
const TUTORIAL_CARD := 2

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
	if _mode == "range" or _mode == "range_kill":
		# The panel is on only in the range, and the HUD asks the catalog rather
		# than being told — so the map is the whole of the staging.
		Net.config.map = MapCatalog.PRACTICE
	if _mode == "hud_elder":
		# The shipping twenty, so the picture is of the bar a player actually
		# sees rather than of one this file invented a length for.
		Net.config.elder_duration = 20.0
	_populate_roster()
	# Every mode but one. `hud_cooldown` is the bar with *nothing* available —
	# spear recharging, both stacks at zero — which is not a corner case but
	# what a Bog looks like for the first minute of every life since D-032, and
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
		"hud_health":
			_stage_kills()
			_stage_hurt()
		"reload_timer":
			_stage_kills()
			_run_reload_timer()
		"weapon_tiles":
			_stage_kills()
			_run_weapon_tiles()
		"controls":
			_stage_kills()
			_run_controls()
		"minimap":
			_stage_kills()
			_run_minimap()
		"tutorial":
			_stage_kills()
			_run_tutorial()
		"range", "range_kill":
			_stage_kills()
			_run_range()
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
	# The local Bog needs a score of its own or every screen shows a zero.
	var mine: Dictionary = MatchState.stats.get(1, {})
	if not mine.is_empty():
		mine["kills"] = 7
		mine["deaths"] = 4
	if TEAM_LETTER_MODES.has(_mode):
		_deal_team_letters(mine)
	elif LETTER_MODES.has(_mode):
		_deal_letters(mine)
	Net.roster_changed.emit()


## Hand out B/O/G masks, so the lamps, the scoreboard column and the results
## table have a spread to draw instead of six empty rows.
##
## Deliberately not "everybody has two". The interesting read on all three of
## those screens is *which* letters somebody is missing, so the roster is built
## so that is the only thing telling two of them apart: the two players on two
## letters are not on the same two.
##
## **A completed set is only dealt to the results mode**, and that is a scar.
## Dealt to every letters mode, it took the *live* ones down with it: the first
## real kill in `hud_hold` ran `_check_win`, which found a row holding B, O and
## G and quite correctly ended the match — so the mode that exists to photograph
## a hold photographed the results screen instead. A staged roster is still real
## state, and the win check does not care that a tool wrote it.
func _deal_letters(mine: Dictionary) -> void:
	var deal := [MatchState.LETTER_O | MatchState.LETTER_B,
		MatchState.LETTER_G | MatchState.LETTER_B,
		MatchState.LETTER_O, 0, MatchState.LETTER_G]
	if _mode == "results_letters":
		deal[0] = MatchState.LETTER_B | MatchState.LETTER_O | MatchState.LETTER_G
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
		else MatchState.LETTER_G | MatchState.LETTER_O


## The Teams deal. The local player (team 0) and the extras alternate teams, so
## team 0 is you, Pipwick, Mossback and Nettle, and team 1 is Bramblewick and
## Toadflax. Within a team no two rows share a letter — a teammate's letter is a
## duplicate and would never have been banked (D-049) — so the pooled masks are
## exactly the OR of the rows, and they are written into `_team_letters` the way
## `_sync_letters` would have written them.
##
## Team 0 pools to O·G and is one B short: the picture worth taking is a team
## lamp lit by a letter the local player never touched. Only the results mode
## completes the word, for the scar `_deal_letters` records.
func _deal_team_letters(mine: Dictionary) -> void:
	var deal := [0, MatchState.LETTER_B, MatchState.LETTER_O, 0, 0]
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
	MatchState.player_killed.emit(EXTRA_BASE + 3, EXTRA_BASE, Bog.Cause.SPEAR)
	MatchState.player_killed.emit(EXTRA_BASE + 1, EXTRA_BASE + 1, Bog.Cause.VOID)
	MatchState.player_killed.emit(EXTRA_BASE + 2, 1, Bog.Cause.SPEAR)
	MatchState.player_killed.emit(1, EXTRA_BASE, Bog.Cause.SPEAR)


## Throw a real spear, so the spear tile is dark because a real `BogCombat` says
## so rather than because this tool set a flag.
func _stage_throw() -> void:
	var combat := _local_combat()
	if combat != null:
		combat.try_throw_spear()


## Two shields and one magnet into the local Bog's pack.
##
## Not decoration. A Bog spawns carrying nothing (D-032), so without this every
## reference shot of the ability bar is two empty slots — a real state, and the
## least informative one to photograph. Handed over exactly the way
## `tools/combat_range.gd` hands one over: through the host-only `grant_*` the
## pickup path itself calls, so the counts on screen arrived the way a player's
## would.
func _stock_the_bar() -> void:
	var combat := _local_combat()
	if combat == null:
		return
	combat.grant_shield(2)
	combat.grant_magnet(1)
	# And a potion, so the fourth tile is photographed carrying something too
	# (D-067). One rather than two: the stock numbers on the bar should differ
	# from each other, or a reference shot cannot show that each tile reads its
	# own count.
	combat.grant_potion(1)


## Collect a letter card for real, and then stand there holding it.
##
## The card comes out of an actual death and is claimed by the player's own body
## walking into the `Pickup` area. That is the same chain
## `tools/combat_range.gd letter` exercises, and it is why neither of them
## writes into `MatchState._letter_holds` by hand: a hold staged directly would
## draw identically and would prove nothing about the thing being drawn.
##
## **There is no dial to force any more** (the letters round). This used to set
## `letter_drop_chance` to 1 so the roll could not come up a shield; the roll is
## gone with the field, because a death in a LETTERS match with no letter in
## play now drops the next one as the *whole* drop. The first kill here is
## therefore a certainty rather than a very likely thing, which is a better
## harness for free.
func _stage_hold() -> void:
	var player := MatchState.local_bog()
	var victim := _a_dummy()
	if player == null or victim == 0:
		return
	if MatchState.phase != MatchState.Phase.PLAYING:
		push_warning("hud_range: nothing to hold — the match has not started yet")
		return
	# The drop lands where the blow struck rather than at the body, so the card
	# can be put down in front of the player without moving anybody.
	MatchState.report_kill(victim, Net.local_id(), Bog.Cause.SPEAR,
		player.global_position + player.facing() * 1.2, Vector3.FORWARD * 18.0, "mixamorig_Spine1")


## Take a bite out of the local player, for real, so the health bar has
## something to draw (D-062).
##
## Through `MatchState.report_damage` like any weapon, rather than by writing
## `Bog.health` — the same argument `_stage_hold` and `_stage_elder` make. A
## number staged directly would draw identically and would prove nothing about
## the thing being drawn, and this way the picture also shows what the *plates*
## do, since the damage lands on the dummies as well.
##
## 62 down to 38 puts the bar in its amber band with a two-digit number on it,
## which is the case worth looking at: green is unmistakable and red is nearly
## empty, and the middle is where legibility is actually decided.
func _stage_hurt() -> void:
	var player := MatchState.local_bog()
	if player == null or MatchState.phase != MatchState.Phase.PLAYING:
		return
	MatchState.report_damage(1, EXTRA_BASE, 62.0, Bog.Cause.SPEAR,
		player.body_centre(), Vector3.FORWARD * 6.0, "mixamorig_Spine1")
	# ...and the range's dummies hurt by different amounts, so the plates in the
	# same frame are not all one colour. Found by walking `MatchState.bogs`
	# rather than by naming the range's own peer ids, which are its business.
	var hurt := [38.0, 82.0]
	var at := 0
	for peer_id: int in MatchState.bogs:
		if peer_id == Net.local_id() or at >= hurt.size():
			continue
		var dummy := MatchState.bogs[peer_id] as Bog
		if dummy == null or not dummy.alive:
			continue
		MatchState.report_damage(peer_id, 1, hurt[at], Bog.Cause.SPEAR,
			dummy.body_centre(), Vector3.FORWARD * 6.0, "mixamorig_Spine1")
		at += 1


## Put the robe on the local Bog, for real, and then stand there wearing it.
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
	var player := MatchState.local_bog()
	var victim := _a_dummy()
	if player == null or victim == 0:
		return
	if MatchState.phase != MatchState.Phase.PLAYING:
		push_warning("hud_range: nothing to wear — the match has not started yet")
		return
	Net.config.elder_drop_chance = 1.0
	MatchState.report_kill(victim, Net.local_id(), Bog.Cause.SPEAR,
		player.global_position + player.facing() * 1.2, Vector3.FORWARD * 18.0, "mixamorig_Spine1")


## The spear tile's recharge readout, measured over one real throw (D-054).
##
## Read off the tile itself -- `recharge_progress()` and `recharge_text()` are
## what `_draw` draws -- rather than recomputed from `BogCombat`, because the
## thing under test is the HUD's choice of *when* to hand the tile a timer, and
## recomputing it here would be testing a copy of that choice.
## The first tile is the weapon this Bog picked (D-069).
##
## Three loadouts through the one HUD, because the tile is not rebuilt per
## weapon — `AbilitySlot.set_kind` mutates the square that is already there, and
## the thing most likely to rot is a field it forgets to move. So this drives the
## real refresh by changing `Bog.weapon` under it, the way the lobby's pick does
## before the body is ever built, and reads the square back.
##
## The Elder is checked last and is the reason the key cap is asserted at all: it
## is the one kind that must *keep* the spear's button, so a `set_kind` that
## updated the cap unconditionally would break it and a check that only looked at
## glyphs would not notice.
# ----------------------------------------------------------- the input map ---

## Actions a player is expected to press in a match, and what they must be bound
## to. `""` means "this check does not care which key, only that it is not
## somebody else's".
##
## `primary_attack` is named because it is the one D-070 created and the one the
## whole weapon set now depends on; the rest are named because a clash is only
## interesting between two things a player might press in the same second.
const CONTROL_BINDINGS := {
	"primary_attack": "LMB",
	"aim": "RMB",
	"drink_potion": "F",
	"place_shield": "Q",
	"throw_magnet": "E",
	"respawn": "R",
	"jump": "",
	"sprint": "",
	"crouch": "",
	"scoreboard": "",
	"chat": "",
}

## Actions that were deleted by D-070 and must stay deleted. An action left in
## the map with nothing polling it is a key that does nothing, which is worse
## than a key that is not bound: a player presses it, and the game's silence is
## indistinguishable from a bug in the weapon.
const CONTROL_RETIRED := ["throw_spear", "draw_bow", "swing_sword"]


## The input map, checked rather than read (D-070).
##
## **This mode exists because of a bug nobody saw.** D-068 put `swing_sword` on
## physical keycode 82 and `respawn` was already there — the potion step had
## specifically steered away from `R` for that reason a step earlier — so for two
## decision records the sword and the respawn were the same key, and nothing
## anywhere could say so. A binding table is data; a clash between two rows of it
## is arithmetic; and the reason it was invisible is only that nobody was doing
## the arithmetic.
##
## Three things, in the order they would go wrong:
##
## * every action the settings panel's controls reference names exists, because
##   `SettingsPanel.primary_key` answers "Unbound" for one that does not and a
##   reference page full of "Unbound" is a page nobody reads twice;
## * no two of them share a key, which is the check that was missing;
## * and the three actions D-070 retired are gone rather than orphaned.
func _run_controls() -> void:
	# **The project's map, not this machine's.** Since the key-binding round,
	# `Settings` puts the player's saved binds on the live `InputMap` at startup
	# — so without this line the check below would be marking somebody's own
	# choices, and a player who deliberately put two things on one key would
	# fail a gate about the defaults on their own machine.
	InputMap.load_from_project_settings()
	var failures := PackedStringArray()
	var owner_of := {}

	for action: String in SettingsPanel.CONTROL_REFERENCE.map(
			func(row: Array) -> String: return row[1]):
		if not InputMap.has_action(action):
			failures.append("the controls reference names %s, which is not in "
				% action + "the input map")

	for action: String in CONTROL_BINDINGS:
		if not InputMap.has_action(action):
			failures.append("%s is not in the input map at all" % action)
			continue
		var want: String = CONTROL_BINDINGS[action]
		var got := SettingsPanel.primary_key(action)
		if not want.is_empty() and got != want:
			failures.append("%s is on %s, wanted %s" % [action, got, want])
		print("  %-16s %s" % [action, got])

	# **Every action this project declares, not only the ones named above**, and
	# every *event* of each rather than the first. The table above is a list of
	# things this check has an opinion about; a clash is interesting between any
	# two keys a player can press, including the pair nobody thought to list —
	# which is exactly the pair that went wrong. `ui_*` is Godot's own and is
	# meant to overlap (Space is `ui_accept` and is also `jump`).
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			var key := _control_key(event)
			if key.is_empty():
				continue
			if owner_of.has(key):
				failures.append("%s and %s are both on %s"
					% [owner_of[key], action, key])
			else:
				owner_of[key] = String(action)

	for action: String in CONTROL_RETIRED:
		if InputMap.has_action(action):
			failures.append("%s is still in the input map; D-070 retired it"
				% action)

	for line: String in failures:
		print("hud_range: %s" % line)
	print("hud_range: %d bindings, %d shared keys — controls %s"
		% [owner_of.size(), failures.size(),
			"PASS" if failures.is_empty() else "FAIL"])


## One event as a comparable string, or "" for an event this check has no
## opinion about. Physical keycodes and mouse buttons only, which is everything
## `project.godot` actually binds.
func _control_key(event: InputEvent) -> String:
	if event is InputEventKey:
		return "key %d" % (event as InputEventKey).physical_keycode
	if event is InputEventMouseButton:
		return "mouse %d" % (event as InputEventMouseButton).button_index
	return ""


# ----------------------------------------------------------------- the map ---

## The corner map, **counted rather than photographed** (the letters round).
##
## Three blips of three different kinds are staged at three measured bearings
## and the verdict is read off `Minimap.debug_counts()`. Read off the map's own
## gather and not off the picture on purpose: the thing that can go wrong here
## is a rule — an enemy with no letter drawn, an ally drawn in a free-for-all,
## a card counted that is past the rim — and every one of those is a *number*
## that a 180 px circle scaled into a screenshot cannot be interrogated for.
## The picture is still worth taking, and this mode takes one; it just is not
## what the gate is asserting.
##
## Played as Teams, because a teammate does not exist in a free-for-all — see
## `TEAM_LETTER_MODES`.
func _run_minimap() -> void:
	var map := _hud.get_node_or_null("%Minimap") as Minimap
	var player := MatchState.local_bog()
	if map == null or player == null:
		print("hud_range: no minimap or local Bog - minimap FAIL")
		return
	var crew := _dummies()
	if crew.size() < 2:
		print("hud_range: %d dummy Bogs on the range, the map needs 2 - minimap FAIL"
			% crew.size())
		return

	var my_team := Net.player_team(Net.local_id())
	var origin := player.global_position
	var mate: int = crew[0]
	var thief: int = crew[1]
	Net.players[mate]["team"] = my_team
	Net.players[thief]["team"] = 1 - my_team
	Net.roster_changed.emit()
	_stand(mate, origin + MINIMAP_MATE)
	_stand(thief, origin + MINIMAP_THIEF)
	# A real hold row through the real local apply, so `letter_carriers()` and
	# `letter_hold_letter()` answer exactly the way they do in a match.
	MatchState._do_begin_hold(thief, MINIMAP_HELD_LETTER, Net.config.letter_hold_time)
	# And one card on the ground, put there by hand. For once that is the
	# honest way round and it is worth saying why, because everything else in
	# this file goes the long way: `place_pickup` refuses a letter by design (a
	# card from outside the drop table is D-033's economy broken by a map), the
	# *map* is what is under test, and a blip cannot tell how its card arrived.
	# A **hold** is the one thing this file still will not stage by hand,
	# because a hold has a clock and a clock is a thing that can be wrong.
	MatchState._spawn_drop(Pickup.Kind.LETTER, MINIMAP_LOOSE_LETTER,
		origin + MINIMAP_CARD)

	await RenderingServer.frame_pre_draw
	await RenderingServer.frame_pre_draw
	map.refresh()
	var counts := map.debug_counts()

	var failures := PackedStringArray()
	for row: Array in [["allies", 1], ["letters", 1], ["carriers", 1]]:
		if int(counts.get(row[0], -1)) != int(row[1]):
			failures.append("%s read %d, wanted %d"
				% [row[0], int(counts.get(row[0], -1)), int(row[1])])
	if not map.visible:
		failures.append("the map is hidden in a B·O·G match")
	if not MatchConfig.is_bog(Net.config.win_condition):
		failures.append("the win condition is not B·O·G")
	for line: String in failures:
		print("  " + line)
	print("hud_range: minimap allies=%d letters=%d carriers=%d %s"
		% [int(counts.get("allies", -1)), int(counts.get("letters", -1)),
			int(counts.get("carriers", -1)),
			"PASS" if failures.is_empty() else "FAIL"])


## Stand a dummy on a spot and leave it there.
##
## The velocity goes with the position: a Bog teleported sideways keeps last
## frame's momentum and walks off its bearing while the shot is being composed,
## which is the one way a staged geometry can drift between the count and the
## photograph.
func _stand(peer_id: int, at: Vector3) -> void:
	var bog: Bog = MatchState.bogs.get(peer_id)
	if not is_instance_valid(bog):
		return
	bog.global_position = at
	bog.velocity = Vector3.ZERO


## Every living Bog on the range but the player's own, in peer order. Found
## rather than named, for `_a_dummy`'s reason: the combat range owns those ids
## and a copy of them in this file is a second place to change.
func _dummies() -> Array[int]:
	var out: Array[int] = []
	for peer_id: int in MatchState.bogs:
		if peer_id == Net.local_id():
			continue
		var bog: Bog = MatchState.bogs[peer_id]
		if is_instance_valid(bog) and bog.alive:
			out.append(peer_id)
	out.sort()
	return out


# ------------------------------------------------------------ the tutorial ---

## HOW TO PLAY, opened over a running match (the letters round).
##
## The verdict is about the **flag** and not about the drawing. Six cards of
## dots and dashed lines either look right or do not, and that is a question for
## a screenshot; what no picture can show is whether the thing opens itself once
## and then never again, which is the half of this feature that decides whether
## anybody ever reads it. So `maybe_auto_open` is driven three times — unseen,
## closed, seen — and the panel is only stood up for the camera afterwards.
##
## `tutorial_seen` is **put back** at the end. `Settings` writes to disk on
## every change and the gate runs on somebody's own machine: a check that left
## the flag true would have quietly decided that the owner never sees the thing
## it is checking.
func _run_tutorial() -> void:
	var panel := TUTORIAL_SCENE.instantiate() as Tutorial
	if panel == null:
		print("hud_range: tutorial.tscn is not a Tutorial - tutorial FAIL")
		return
	add_child(panel)

	var failures := PackedStringArray()
	if Tutorial.CARDS.size() != 6:
		failures.append("there are %d cards, wanted 6" % Tutorial.CARDS.size())

	var was: Variant = Settings.get_value("tutorial_seen")
	Settings.set_value("tutorial_seen", false)
	panel.maybe_auto_open()
	await RenderingServer.frame_pre_draw
	if not panel.visible:
		failures.append("maybe_auto_open left an unseen tutorial shut")
	panel.close()
	if not bool(Settings.get_value("tutorial_seen")):
		failures.append("closing the tutorial did not mark it seen")
	panel.maybe_auto_open()
	if panel.visible:
		failures.append("maybe_auto_open reopened a tutorial that was already seen")
	Settings.set_value("tutorial_seen", was)

	panel.open(TUTORIAL_CARD)
	await RenderingServer.frame_pre_draw
	await RenderingServer.frame_pre_draw
	if not panel.visible:
		failures.append("open() left the panel hidden")
	var title := panel.get_node_or_null("%Title") as Label
	var wanted := String(Tutorial.CARDS[TUTORIAL_CARD]["title"])
	if title == null or not title.text.contains(wanted):
		failures.append("card %d is titled \"%s\", wanted %s" % [TUTORIAL_CARD + 1,
			"nothing" if title == null else title.text, wanted])

	# **Every card is drawn**, one frame each, before the verdict. The first
	# build shipped with this mode photographing card three only, and card two
	# — the one with the scrolling dashed line — froze the lobby for the owner
	# and a friend within minutes: a drawing loop whose step rounded to nothing.
	# A card that never reaches its own `_draw` in the gate is a card nobody has
	# looked at, so each one is opened, drawn, and its title read back.
	for card in Tutorial.CARDS.size():
		panel.open(card)
		await RenderingServer.frame_pre_draw
		await RenderingServer.frame_pre_draw
		var card_title := panel.get_node_or_null("%Title") as Label
		var card_wanted := String(Tutorial.CARDS[card]["title"])
		if card_title == null or not card_title.text.contains(card_wanted):
			failures.append("card %d drew as \"%s\", wanted %s" % [card + 1,
				"nothing" if card_title == null else card_title.text, card_wanted])
	panel.open(TUTORIAL_CARD)
	await RenderingServer.frame_pre_draw

	for line: String in failures:
		print("  " + line)
	if not failures.is_empty():
		print("hud_range: tutorial FAIL")
		return
	print("hud_range: every one of the %d cards drew" % Tutorial.CARDS.size())
	print("hud_range: %d cards, shown once and reopenable, standing on card %d"
		% [Tutorial.CARDS.size(), TUTORIAL_CARD + 1])
	print("hud_range: tutorial PASS")


func _run_weapon_tiles() -> void:
	var slot := _hud.get_node("%SpearSlot") as AbilitySlot
	var combat := _local_combat()
	var bog: Bog = MatchState.bogs.get(1)
	if slot == null or combat == null or not is_instance_valid(bog):
		print("hud_range: no weapon tile or local Bog - weapon_tiles FAIL")
		return

	var failures := PackedStringArray()
	var want := [
		[Loadout.Weapon.SPEAR, AbilitySlot.Kind.SPEAR, "Spear", "primary_attack"],
		[Loadout.Weapon.BOW, AbilitySlot.Kind.BOW, "Bow", "primary_attack"],
		[Loadout.Weapon.SWORD, AbilitySlot.Kind.SWORD, "Sword", "primary_attack"],
	]
	for row: Array in want:
		bog.weapon = row[0]
		combat.refresh_hand()
		combat.cooldowns_changed.emit()
		await RenderingServer.frame_pre_draw
		if slot.kind != row[1]:
			failures.append("%s: glyph is %d, wanted %d"
				% [row[2], slot.kind, row[1]])
		if slot.label_text != row[2]:
			failures.append("%s: caption says %s" % [row[2], slot.label_text])
		if slot.action != row[3]:
			failures.append("%s: key cap fires %s, wanted %s"
				% [row[2], slot.action, row[3]])
		print("  %-6s glyph %d, caption %s, key %s"
			% [row[2], slot.kind, slot.label_text,
				SettingsPanel.primary_key(slot.action)])

	# And the Elder, which replaces whatever you picked (D-038) and keeps the
	# spear's own button doing it.
	MatchState._do_set_elder(1, true, 20.0)
	combat.cooldowns_changed.emit()
	await RenderingServer.frame_pre_draw
	if slot.kind != AbilitySlot.Kind.LIGHTNING:
		failures.append("an Elder's tile is %d, wanted the bolt" % slot.kind)
	if slot.action != "primary_attack":
		failures.append("an Elder's bolt fires %s, wanted primary_attack"
			% slot.action)
	print("  %-6s glyph %d, caption %s, key %s"
		% ["Elder", slot.kind, slot.label_text,
			SettingsPanel.primary_key(slot.action)])
	MatchState._do_set_elder(1, false, 0.0)

	# Back to the sword the loop left it on, so the picture this mode also takes
	# is of a weapon a player can pick rather than of a robe that has just burned
	# out.
	bog.weapon = Loadout.Weapon.SWORD
	combat.cooldowns_changed.emit()

	if failures.is_empty():
		print("hud_range: the tile follows the pick - weapon_tiles PASS")
	else:
		for line: String in failures:
			print("  " + line)
		print("hud_range: weapon_tiles FAIL")


func _run_reload_timer() -> void:
	var slot := _hud.get_node("%SpearSlot") as AbilitySlot
	var crosshair := _hud.get_node("%Crosshair") as Crosshair
	var combat := _local_combat()
	if slot == null or crosshair == null or combat == null:
		print("hud_range: no spear tile, crosshair or local Bog - reload_timer FAIL")
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


## Somebody for the local Bog to kill. Found rather than named: the combat range
## owns those peer ids, and a copy of the number in this file would be a second
## place to change the day it moves.
func _a_dummy() -> int:
	for peer_id: int in MatchState.bogs:
		if peer_id != Net.local_id():
			return peer_id
	return 0


func _local_combat() -> BogCombat:
	var bog := MatchState.local_bog()
	if bog == null:
		return null
	return bog.get_node_or_null("Combat") as BogCombat


## The practice range's corner readout, with a session's shooting already in it.
##
## A hand-written table rather than a staged firefight, for the reason every
## other mode here stages its numbers: what this photographs is the *panel*, and
## a picture whose contents depend on whether a spear happened to land is a
## picture that changes between runs. The rows are chosen to exercise every
## column — a weapon with a good ratio, one with a bad one, one with almost no
## shots, a long best hit and a live streak.
##
## It also fires one `hit_landed`, so the crosshair's mark is mid-flash in the
## frame. That is the one piece of feedback in this unit that no still frame
## would otherwise catch.
func _run_range() -> void:
	var stats := RangeStats.new()
	stats.name = "Stats"
	add_child(stats)

	var me := Net.local_id()
	var crosshair := _hud.get_node_or_null("%Crosshair") as Crosshair
	var panel := _hud.get_node_or_null("%RangeStats") as RangeStatsPanel
	if panel == null or crosshair == null:
		print("hud_range: no range panel or crosshair - range FAIL")
		return

	# **The wiring, proven before the picture is staged.** One real `hit_landed`
	# through the HUD's own handler: it has to reach the crosshair, and it has to
	# reach the counter and be filed under the bow, because the cause was an
	# arrow. Then the table is wiped and written by hand, so what is
	# photographed does not depend on it.
	MatchState.hit_landed.emit(me, _a_dummy(), 38.0, Bog.Cause.ARROW,
		Vector3.ZERO, "mixamorig_Spine1")
	var took_the_mark := crosshair.is_processing()
	var counted := int(stats.row(me, "bow")["hits"]) == 1
	stats.reset()
	for entry: Dictionary in [
		{"weapon": "spear", "launches": 12, "hits": 9, "kills": 6,
			"longest": 41.2, "streak": 4},
		{"weapon": "bow", "launches": 20, "hits": 11, "kills": 3,
			"longest": 52.8, "streak": 0},
		{"weapon": "sword", "launches": 6, "hits": 4, "kills": 2,
			"longest": 1.4, "streak": 2},
	]:
		for i: int in int(entry["launches"]):
			stats.record_launch(me, String(entry["weapon"]))
		for i: int in int(entry["hits"]):
			stats.record_hit(me, String(entry["weapon"]), 0.0)
		for i: int in int(entry["kills"]):
			stats.record_kill(me, String(entry["weapon"]))
		var row := stats.row(me, String(entry["weapon"]))
		# Set outright rather than replayed: `longest` is a max over real
		# distances and the streak is a running count, and neither is worth
		# faking a firefight to produce.
		row["longest"] = float(entry["longest"])
		row["streak"] = int(entry["streak"])
	stats.rows_changed.emit()

	if _hud.has_method("refresh_range_panel"):
		_hud.call("refresh_range_panel")

	# Held open for the photograph, and only for the photograph. The real mark
	# is 0.45 s and this frame is taken about 1.8 s in, so a picture of the live
	# one is not a thing that exists — the assertion above is what proves it
	# fires, and this is what puts it in the frame.
	#
	# `range_kill` is the same staging with the kill mark instead: white, and
	# the whole X rather than four corners of one. Two modes rather than one
	# picture with both, because the marks are drawn on the same four pixels and
	# a photograph of them overlaid would show neither. The long life also parks
	# both past the 70 ms snap, so what is photographed is the mark at rest —
	# the size it holds for the other 0.38 s, not the 1.4x it arrives at.
	if _mode == "range_kill":
		crosshair.strike(Color(1, 1, 1), 30.0, true)
	else:
		crosshair.strike(UIPalette.BOG, 30.0)

	var failures: PackedStringArray = []
	if not took_the_mark:
		failures.append("a landed hit did not reach the crosshair")
	if not counted:
		failures.append("a landed hit was not filed under the bow")
	if not panel.visible:
		failures.append("the panel is hidden on a practice map")
	if Net.config.map != MapCatalog.PRACTICE:
		failures.append("the map is not the range")
	var used := stats.weapons_used(me)
	var wanted: Array[String] = ["spear", "bow", "sword"]
	if used != wanted:
		failures.append("weapons_used read %s, wanted %s" % [str(used), str(wanted)])
	var spear_row := stats.row(me, "spear")
	if not is_equal_approx(RangeStats.accuracy(spear_row), 0.75):
		failures.append("spear accuracy read %.2f, wanted 0.75"
			% RangeStats.accuracy(spear_row))
	# The panel is a grid of five cells per weapon used, built on `rows_changed`.
	var cells := 0
	for child: Node in panel.find_children("", "GridContainer", true, false):
		cells = (child as GridContainer).get_child_count()
	if cells != used.size() * 5:
		failures.append("the panel drew %d cells for %d weapons"
			% [cells, used.size()])

	for weapon: String in used:
		var row := stats.row(me, weapon)
		print("  %-6s %d/%d  %d%%  %.1f m  x%d" % [weapon.to_upper(),
			int(row["hits"]), int(row["launches"]),
			roundi(RangeStats.accuracy(row) * 100.0),
			float(row["longest"]), int(row["streak"])])

	if failures.is_empty():
		print("hud_range: the range panel shows %d weapon rows over a live mark"
			% used.size())
		print("hud_range: range PASS")
	else:
		for line: String in failures:
			print("  " + line)
		print("hud_range: range FAIL")


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
