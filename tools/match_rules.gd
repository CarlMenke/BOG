extends Node
## Exercises the match rules end to end and asserts the outcomes.
## Development tool, not shipped. Runs headless in a couple of seconds.
##
##   Godot --headless --path . tools/match_rules.tscn
##
## Note this runs as a *scene*, not as a `--script` main loop. A script main
## loop is compiled before the autoloads are registered, so `MatchState` and
## `Net` are not resolvable identifiers at parse time and the whole file fails
## to compile — which is also why `snapshot.gd` only ever loads scenes by path.
##
## `combat_range` proves a spear can kill someone. It cannot prove that fifteen
## kills ends a match, that a friendly-fire kill costs a point instead of
## earning one, or that the last Bog standing wins — those live entirely in
## `MatchState` and, until this existed, had never been run with more than one
## live player. Every scenario drives the same host-side API a real match drives
## (`report_kill`, the clock, the respawn tick), so a rule that passes here is a
## rule that works in a match.
##
## Bogs are deliberately never spawned. These scenarios are about the
## bookkeeping, so the arena is registered with an empty spawn list and
## `_create_bog` is left to fail quietly for peers that do not exist.

const PEERS := [1, 901, 902, 903]

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	print("match_rules: starting")
	# A harness that cannot reach the thing it is testing must not print PASS.
	#
	# When `match_state.gd` fails to parse, Godot logs the error, declines to
	# instantiate the autoload, and carries on running. Every `MatchState.x`
	# below then resolves against `Nil`: each scenario errors out somewhere
	# before its first `_check`, nothing is ever asked, and the tally at the
	# bottom prints "0 failures" over a completely dead run. The smoke gate does
	# catch the SCRIPT ERRORs — but this file should not be claiming PASS in the
	# same breath, and it did, once, for a `Dictionary.filter()` that Godot 4.7
	# does not have.
	if MatchState == null or Net == null:
		print("match_rules: FAIL — an autoload is missing; see the errors above")
		get_tree().quit(1)
		return
	_run_kill_limit()
	_run_friendly_fire_off()
	_run_friendly_fire_on()
	_run_team_kill_limit()
	_run_lives_elimination()
	_run_letters()
	_run_team_letters()
	_run_team_letters_leaver()
	_run_team_letter_hold()
	_run_letter_hold()
	_run_letter_hold_disconnect()
	_run_elder()
	_run_time_limit()
	_run_void_credit()
	_run_spawn_protection()
	_run_random_teams()
	_run_loadout()
	await _run_capture()
	_run_capture_layout()
	_run_capture_lobby()
	_run_config_validation()

	print("match_rules: %d checks, %d failures" % [_checks, _failures])
	print("match_rules: %s" % ("PASS" if _failures == 0 else "FAIL"))
	# Free the Bogs the scenarios spawned before quitting: Godot reports
	# anything still in the tree at exit as a leak, and a harness that prints
	# PASS above a wall of warnings teaches people to ignore warnings.
	# queue_free lands at the end of a frame and the corpses and spears take
	# another to unwind, hence the wait.
	#
	# Two dozen or so still get reported and always will — they are the
	# `preload` constants on the item and audio scripts plus the voices the
	# audio pool is still holding, all of which are alive for as long as the
	# scripts are. Nothing here can release those, so the count never quite
	# reaches zero, and it went up when the Elder scenario started firing
	# thunder at things — and again at D-040, when every spear that fails to
	# kill an Elder started sounding a ward off its robe.
	MatchState.reset()
	for i in 4:
		await get_tree().process_frame
	get_tree().quit(1 if _failures > 0 else 0)


# ------------------------------------------------------------------ harness ---

## Put `Net` and `MatchState` into a running match with `count` fake players.
## Teams are assigned round-robin, so team scenarios get two of each.
func _begin(count: int, configure: Callable, root: Node = null,
		weapons: Array = []) -> void:
	MatchState.reset()
	Net.start_offline()
	Net.players.clear()
	for i in count:
		Net.players[PEERS[i]] = {
			"name": "P%d" % i, "team": i % 2, "ready": true,
			# Spears all round unless a scenario says otherwise, which is what
			# every scenario above this one was written against and what a lobby
			# that never opens the picker plays (D-069). `_run_loadout` is the
			# one that deals three different weapons.
			"weapon": weapons[i] if i < weapons.size() else Loadout.DEFAULT,
		}
	Net.roster_changed.emit()
	# Every scenario starts from a clean, fast config. Spawn protection in
	# particular has to be switched off explicitly: it defaults to two seconds,
	# these scenarios run in microseconds, and a protected Bog correctly refuses
	# to die — which looked exactly like the scoring being broken the first time
	# this harness was run. `_run_spawn_protection` turns it back on deliberately.
	Net.config.spawn_protection = 0.0
	Net.config.warmup_time = 0.0
	Net.config.respawn_delay = 0.0
	configure.call(Net.config)
	# Registering the arena is what starts a match.
	MatchState.register_arena(root if root != null else self, [] as Array[Transform3D])
	# Warmup is skipped rather than waited out: these scenarios are about the
	# rules, not the countdown.
	MatchState.phase = MatchState.Phase.PLAYING


func _kill(victim: int, killer: int) -> void:
	MatchState.report_kill(victim, killer, Bog.Cause.SPEAR,
		Vector3.ZERO, Vector3.FORWARD, "Spine1")


## Bring a dead player back without needing a Bog or a respawn timer.
func _revive(peer_id: int) -> void:
	MatchState.stats[peer_id]["alive"] = true
	MatchState.stats[peer_id]["respawn_at"] = 0.0


func _check(what: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got == want:
		return
	_failures += 1
	print("  FAIL  %s: got %s, wanted %s" % [what, str(got), str(want)])


## The same, for a float that is the result of arithmetic rather than a value
## that was stored. `WALK_SPEED * elder_speed_multiplier` computed on both sides
## of a comparison happens to be bit-identical today and would stop being so the
## moment either side grew a term, which is a failing check about nothing.
func _near(what: String, got: float, want: float) -> void:
	_checks += 1
	if absf(got - want) < 0.0001:
		return
	_failures += 1
	print("  FAIL  %s: got %f, wanted %f" % [what, got, want])


func _scenario(scenario_name: String) -> void:
	print("-- %s" % scenario_name)


## First entry of a summary array, or -1 if the match never finished. Reading
## `[0]` directly turns one failed assertion into a crash that hides the rest.
func _leader(summary: Dictionary) -> int:
	var order: Array = summary.get("ranking", [])
	return int(order[0]) if not order.is_empty() else -1


## Put one letter card on the ground the way a death would, and hand back the id
## a collector would address it by.
##
## Through `_spawn_drop` rather than by building a `Pickup` here, because the
## rules being checked below are about what `claim_pickup` does with a real
## entry in the real index — a stand-in would prove the harness agrees with
## itself. `_drop_loot` cannot be used: it needs a world to cast its ground ray
## in and these scenarios deliberately have none.
func _drop_card(letter: int) -> int:
	return MatchState._spawn_drop(Pickup.Kind.LETTER, letter, Vector3.ZERO)


## Put one Elder robe on the ground, the same way and for the same reason.
##
## `_drop_loot`'s roll cannot be used here either — it needs a world to cast its
## ground ray in and these scenarios have none. What the *roll* does is checked
## where it can be: `tools/combat_range.tscn lightning` kills a dummy with
## `elder_drop_chance` forced to 1 and walks the player's own body into what
## falls out, which is the whole chain in a world with geometry in it.
func _drop_robe() -> int:
	return MatchState._spawn_drop(Pickup.Kind.ELDER_ROBE, 0, Vector3.ZERO)


## Is this Bog actually wearing the cloth, as opposed to merely being listed as
## the Elder? Two claims, and the interesting bug is the one where they
## disagree — a Bog that is the Elder in the rules and a plain Bog on screen is
## the worst outcome available, because the robe is the only warning anyone gets.
func _wearing_robe(peer_id: int) -> bool:
	var bog: Bog = MatchState.bogs.get(peer_id)
	if not is_instance_valid(bog) or bog.elder_robe == null:
		return false
	return bog.elder_robe.is_worn()


## Fire one bolt the way the host fires one, straight at `_host_cast_lightning`.
##
## Aimed at nothing in particular: there is no geometry in these scenarios, so
## the ray finds thin air and no one dies. That is deliberate — what is being
## checked here is the *gating*, and "the bolt kills what it hits" is
## `tools/combat_range.tscn lightning`'s job, in a scene that has a target
## standing in it.
func _cast(peer_id: int) -> void:
	var combat := _combat(peer_id)
	if combat != null:
		combat._host_cast_lightning(Vector3.ZERO, Vector3.FORWARD)


## Bolts and ward flashes free themselves after a second; a harness that quits in
## four frames has to take them away itself, or Godot reports every one of them
## as a leak and a PASS printed over a wall of warnings teaches people to ignore
## warnings.
##
## Both kinds, because both are spawned into `MatchState._spawn_root()`, which
## in a harness with no `spawned_items` group is this node. A ward flash is what
## a spear turned aside by a robe leaves behind (D-040), and the Elder scenario
## now makes several.
func _sweep_effects() -> void:
	for child in get_children():
		if child is LightningBolt or child is WardFlash:
			child.free()


## Is that card still lying there to be walked over? A collected card is erased
## from the index; a card that was passed over is not. This is the difference
## between "consumed" and "left alone", which is the whole duplicate-versus-busy
## distinction (D-035).
func _card_live(pickup_id: int) -> bool:
	return MatchState._pickups.has(pickup_id)


## The letter on the newest card in the world — the one a death or a disconnect
## has just put back. Ids only ever go up within a match, so the highest is the
## most recent.
func _newest_card_letter() -> int:
	var newest := 0
	var letter := 0
	for id: int in MatchState._pickups:
		if id >= newest:
			newest = id
			letter = MatchState._pickups[id].letter
	return letter


## A Bog's combat node and its hand, or null if that Bog never got one.
##
## Every other scenario here is pure bookkeeping and touches neither. The hold
## needs both, because "you cannot throw, and the card is in the hand where the
## spear was" is half the mechanic and it lives on the Bog — and the half most
## likely to rot, since a hand driven by anything other than `has_spear()` looks
## right until the frame it does not (D-035).
func _combat(peer_id: int) -> BogCombat:
	var bog: Bog = MatchState.bogs.get(peer_id)
	if not is_instance_valid(bog):
		return null
	return bog.get_node_or_null("Combat") as BogCombat


func _hand(peer_id: int) -> HeldGear:
	var bog: Bog = MatchState.bogs.get(peer_id)
	return bog.held_gear if is_instance_valid(bog) else null


## Run a hold's clock down to zero and let the host finish it, rather than
## making the harness sit through ten real seconds of a config dial.
func _expire_hold(peer_id: int) -> void:
	MatchState._letter_holds[peer_id]["ends_at"] = 0.0
	MatchState._tick_letter_holds()


## The same for a robe (D-040), and deliberately the same shape: wind the row's
## deadline back and let the host's own tick be the thing that notices.
##
## Winding the clock rather than calling `_end_elder` directly is the point.
## `_end_elder` is also what a void death and a disconnect call, so a check that
## used it would pass with `_tick_elders` deleted entirely — and "the robe burns
## out on its own" would then be a claim about a function nothing runs.
func _expire_elder(peer_id: int) -> void:
	MatchState._elders[peer_id]["ends_at"] = 0.0
	MatchState._tick_elders()


# ---------------------------------------------------------------- scenarios ---

func _run_kill_limit() -> void:
	_scenario("free-for-all, kill limit")
	var finished := {}
	_begin(3, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.FREE_FOR_ALL
		c.win_condition = MatchConfig.WinCondition.KILL_LIMIT
		c.kill_limit = 3
		c.time_limit = 0)
	MatchState.match_finished.connect(func(s: Dictionary) -> void:
		finished.merge(s, true), CONNECT_ONE_SHOT)

	for i in 2:
		_kill(901, 1)
		_revive(901)
	_check("not finished at 2 of 3", MatchState.phase, MatchState.Phase.PLAYING)
	_check("killer has 2", MatchState.kills(1), 2)
	_check("victim has 2 deaths", MatchState.deaths(901), 2)

	_kill(901, 1)
	_check("finished at the limit", MatchState.phase, MatchState.Phase.POST_MATCH)
	_check("reason", finished.get("reason"), "limit")
	_check("winner leads the ranking", _leader(finished), 1)

	# A kill after the whistle must not count.
	_kill(902, 1)
	_check("no scoring after the match ends", MatchState.kills(1), 3)


func _run_friendly_fire_off() -> void:
	_scenario("teams, friendly fire off")
	_begin(4, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.TEAMS
		c.team_count = 2
		c.win_condition = MatchConfig.WinCondition.KILL_LIMIT
		c.kill_limit = 50
		c.friendly_fire = false
		c.time_limit = 0)
	# Peers 1 and 902 are team 0; 901 and 903 are team 1.
	_kill(902, 1)
	_check("team-mate survives", MatchState.is_alive(902), true)
	_check("no death recorded", MatchState.deaths(902), 0)
	_check("no point awarded", MatchState.kills(1), 0)

	_kill(901, 1)
	_check("an enemy still dies", MatchState.is_alive(901), false)
	_check("and still scores", MatchState.kills(1), 1)


func _run_friendly_fire_on() -> void:
	_scenario("teams, friendly fire on")
	_begin(4, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.TEAMS
		c.team_count = 2
		c.win_condition = MatchConfig.WinCondition.KILL_LIMIT
		c.kill_limit = 50
		c.friendly_fire = true
		c.time_limit = 0)
	_kill(902, 1)
	_check("team-mate dies", MatchState.is_alive(902), false)
	_check("and it costs a point", MatchState.kills(1), -1)


func _run_team_kill_limit() -> void:
	_scenario("teams, the limit is a team total")
	var finished := {}
	_begin(4, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.TEAMS
		c.team_count = 2
		c.win_condition = MatchConfig.WinCondition.KILL_LIMIT
		c.kill_limit = 3
		c.friendly_fire = false
		c.time_limit = 0)
	MatchState.match_finished.connect(func(s: Dictionary) -> void:
		finished.merge(s, true), CONNECT_ONE_SHOT)

	# Two kills by one team-mate and one by the other reaches a team limit of 3
	# that neither player reaches alone — the whole point of the mode.
	_kill(901, 1)
	_revive(901)
	_kill(903, 1)
	_revive(903)
	_check("still playing at 2", MatchState.phase, MatchState.Phase.PLAYING)
	_kill(901, 902)
	_check("team score", MatchState.team_score(0), 3)
	_check("finished on the team total", MatchState.phase, MatchState.Phase.POST_MATCH)
	_check("team scores in the summary",
		(finished.get("team_scores", {}) as Dictionary).get(0), 3)


func _run_lives_elimination() -> void:
	_scenario("lives, last Bog standing")
	var finished := {}
	_begin(3, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.FREE_FOR_ALL
		c.win_condition = MatchConfig.WinCondition.LIVES
		c.lives = 2
		c.kill_limit = 50
		c.time_limit = 0)
	MatchState.match_finished.connect(func(s: Dictionary) -> void:
		finished.merge(s, true), CONNECT_ONE_SHOT)

	_check("everyone starts with 2 lives", MatchState.lives_left(901), 2)
	_kill(901, 1)
	_check("a death costs a life", MatchState.lives_left(901), 1)
	_revive(901)
	_kill(901, 1)
	_check("out of lives", MatchState.lives_left(901), 0)
	_check("still playing, one rival left", MatchState.phase, MatchState.Phase.PLAYING)

	_kill(902, 1)
	_revive(902)
	_kill(902, 1)
	_check("finished when only one is left", MatchState.phase, MatchState.Phase.POST_MATCH)
	_check("reason", finished.get("reason"), "elimination")
	_check("survivor leads", _leader(finished), 1)

	# An eliminated player must not come back when the respawn timer matures.
	MatchState.stats[901]["respawn_at"] = 0.001
	MatchState.phase = MatchState.Phase.PLAYING
	MatchState._tick_respawns()
	_check("eliminated players stay out", MatchState.is_alive(901), false)


func _run_letters() -> void:
	_scenario("free-for-all, collect B·O·G")
	var finished := {}
	_begin(3, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.FREE_FOR_ALL
		c.win_condition = MatchConfig.WinCondition.LETTERS
		c.kill_limit = 50
		c.time_limit = 0)
	MatchState.match_finished.connect(func(s: Dictionary) -> void:
		finished.merge(s, true), CONNECT_ONE_SHOT)

	_check("everyone starts empty-handed", MatchState.letters_for(901), 0)
	_check("a card is taken", MatchState.award_letter(901, MatchState.LETTER_G), true)
	_check("and is held", MatchState.letter_count(901), 1)

	# Duplicates are wasted, deliberately (D-033). The award *fails* and the
	# caller throws the card away anyway — `MatchState.claim_pickup` ignores this
	# answer on purpose, so the check is that it is false and that nothing moved.
	_check("a duplicate grants nothing",
		MatchState.award_letter(901, MatchState.LETTER_G), false)
	_check("and leaves the set alone", MatchState.letter_count(901), 1)
	_check("and does not turn into a letter they needed",
		MatchState.letters_for(901), MatchState.LETTER_G)

	# The one thing on a stats row a death does not touch. Everything a Bog was
	# carrying goes; the letters stay.
	_kill(901, 902)
	_check("letters survive a death", MatchState.letter_count(901), 1)
	_revive(901)

	MatchState.award_letter(901, MatchState.LETTER_O)
	_check("two of three is not a win", MatchState.phase, MatchState.Phase.PLAYING)
	MatchState.award_letter(901, MatchState.LETTER_B)
	_check("three of three ends it", MatchState.phase, MatchState.Phase.POST_MATCH)
	_check("reason", finished.get("reason"), "letters")
	# The ranking is sorted by letters under this condition, not by kills — 902
	# has the only kill in this scenario and must not be top of the results.
	_check("the collector leads", _leader(finished), 901)

	# Nothing is awarded after the whistle, the same rule kills obey.
	_check("no letters after the match ends",
		MatchState.award_letter(902, MatchState.LETTER_G), false)


func _team_letters_config(c: MatchConfig) -> void:
	c.mode = MatchConfig.Mode.TEAMS
	c.team_count = 2
	c.win_condition = MatchConfig.WinCondition.LETTERS
	c.kill_limit = 50
	c.time_limit = 0


func _run_team_letters() -> void:
	_scenario("teams, letters pool")
	var finished := {}
	# `_begin` assigns teams round-robin over PEERS, so 1 and 902 are team 0 and
	# 901 and 903 are team 1.
	_begin(4, _team_letters_config)
	MatchState.match_finished.connect(func(s: Dictionary) -> void:
		finished.merge(s, true), CONNECT_ONE_SHOT)

	# The same three letters split across two teams spell nothing (D-049): G
	# and O on team 0, B on team 1. Pooling is within a team, never across.
	MatchState.award_letter(1, MatchState.LETTER_G)
	MatchState.award_letter(902, MatchState.LETTER_O)
	MatchState.award_letter(901, MatchState.LETTER_B)
	_check("B·O·G split across two teams has not won",
		MatchState.phase, MatchState.Phase.PLAYING)
	_check("team 0 pools its two members' letters",
		MatchState.team_letters(0), MatchState.LETTER_G | MatchState.LETTER_O)
	_check("team 1 holds only its own",
		MatchState.team_letters(1), MatchState.LETTER_B)
	_check("a player's lamps are the team's",
		MatchState.scoring_letters(1), MatchState.LETTER_G | MatchState.LETTER_O)
	_check("while their own row keeps what they banked",
		MatchState.letters_for(1), MatchState.LETTER_G)

	# Duplicates are judged against the team (D-033, per team since D-049): a G
	# already banked by a teammate is wasted in the other teammate's hands.
	_check("a teammate's letter is a duplicate",
		MatchState.award_letter(902, MatchState.LETTER_G), false)
	_check("and moves nothing on the team",
		MatchState.team_letters(0), MatchState.LETTER_G | MatchState.LETTER_O)
	_check("or on the player",
		MatchState.letters_for(902), MatchState.LETTER_O)
	# But the other team's letters are not theirs, so it is not a duplicate there.
	_check("the other team can still take a G",
		MatchState.award_letter(903, MatchState.LETTER_G), true)

	# Three teammates-worth of hands, one word: 902 banks the B team 0 was
	# missing, and team 0 wins without anybody holding all three.
	MatchState.award_letter(902, MatchState.LETTER_B)
	_check("B·O·G between teammates ends it",
		MatchState.phase, MatchState.Phase.POST_MATCH)
	_check("reason", finished.get("reason"), "letters")
	_check("nobody holds all three alone",
		MatchState.letters_for(1) != MatchState.LETTER_ALL
		and MatchState.letters_for(902) != MatchState.LETTER_ALL, true)
	var pooled: Dictionary = finished.get("team_letters", {})
	_check("the summary carries the winning team's word",
		int(pooled.get(0, 0)), MatchState.LETTER_ALL)
	_check("and the losing team's hand",
		int(pooled.get(1, 0)), MatchState.LETTER_B | MatchState.LETTER_G)


func _run_team_letters_leaver() -> void:
	_scenario("teams, a leaver's letters stay with the team")
	var finished := {}
	_begin(4, _team_letters_config)
	MatchState.match_finished.connect(func(s: Dictionary) -> void:
		finished.merge(s, true), CONNECT_ONE_SHOT)

	MatchState.award_letter(902, MatchState.LETTER_G)
	MatchState.award_letter(902, MatchState.LETTER_O)
	MatchState._on_player_left(902)
	_check("the leaver's row is gone", MatchState.stats.has(902), false)
	_check("but their letters are still the team's",
		MatchState.team_letters(0), MatchState.LETTER_G | MatchState.LETTER_O)
	_check("the leaver's G is still a duplicate for the team",
		MatchState.award_letter(1, MatchState.LETTER_G), false)
	MatchState.award_letter(1, MatchState.LETTER_B)
	_check("and finishing the word on top of them wins",
		MatchState.phase, MatchState.Phase.POST_MATCH)
	_check("reason", finished.get("reason"), "letters")

	# A new match starts from nothing, whoever left the last one.
	MatchState.reset()
	_check("reset clears the team's letters", MatchState.team_letters(0), 0)


func _run_team_letter_hold() -> void:
	_scenario("teams, a hold for a letter the team already has")
	_begin(4, func(c: MatchConfig) -> void:
		_team_letters_config(c)
		c.letter_hold_time = 10.0)

	# A card for a letter a teammate already banked is consumed on touch and
	# starts no hold, exactly as one for your own letter does.
	MatchState.award_letter(1, MatchState.LETTER_G)
	var dupe := _drop_card(MatchState.LETTER_G)
	MatchState.claim_pickup(dupe, 902)
	_check("a team duplicate is consumed on touch", _card_live(dupe), false)
	_check("and starts no hold", MatchState.is_holding_letter(902), false)

	# Two teammates standing still for the same letter: the first to finish
	# banks it and the other one's hold is over, not ten seconds of nothing.
	var first := _drop_card(MatchState.LETTER_O)
	var second := _drop_card(MatchState.LETTER_O)
	MatchState.claim_pickup(first, 1)
	MatchState.claim_pickup(second, 902)
	var enemy := _drop_card(MatchState.LETTER_O)
	MatchState.claim_pickup(enemy, 901)
	_check("both teammates are holding O",
		MatchState.is_holding_letter(1) and MatchState.is_holding_letter(902), true)
	_expire_hold(1)
	_check("the first to finish banks it",
		MatchState.team_letters(0), MatchState.LETTER_G | MatchState.LETTER_O)
	_check("and the teammate's hold for it ends", MatchState.is_holding_letter(902), false)
	_check("while the other team's hold for O carries on",
		MatchState.is_holding_letter(901), true)


func _run_letter_hold() -> void:
	_scenario("holding a letter up for it")
	var finished := {}
	_begin(3, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.FREE_FOR_ALL
		c.win_condition = MatchConfig.WinCondition.LETTERS
		c.kill_limit = 50
		c.time_limit = 0
		c.letter_hold_time = 10.0)
	MatchState.match_finished.connect(func(s: Dictionary) -> void:
		finished.merge(s, true), CONNECT_ONE_SHOT)

	# Touching a card buys a countdown, not a letter (D-035).
	var first := _drop_card(MatchState.LETTER_G)
	MatchState.claim_pickup(first, 901)
	_check("the card is taken off the ground", _card_live(first), false)
	_check("but the letter is not granted", MatchState.letters_for(901), 0)
	_check("the Bog is holding it up", MatchState.is_holding_letter(901), true)
	_check("and it is the letter that was on the card",
		MatchState.letter_hold_letter(901), MatchState.LETTER_G)
	_check("with the clock running",
		MatchState.letter_hold_remaining(901) > 9.0, true)

	# The hand and the gate, which are not allowed to disagree. Both read
	# `has_spear()`, so a Bog that looks armed is armed and one holding a card
	# is not — that is the whole tell the mechanic is built on.
	var combat := _combat(901)
	var hand := _hand(901)
	_check("the Bog has a combat node", combat != null, true)
	_check("and a hand to put the card in", hand != null, true)
	if combat != null and hand != null:
		_check("no spear while holding", combat.has_spear(), false)
		_check("the shaft leaves the hand", hand.is_carried(), false)
		_check("and the card is in it", hand.has_letter(), true)

	# One hold at a time. A second card is not consumed, not queued, and not
	# refused to anybody else — it is simply still there.
	var second := _drop_card(MatchState.LETTER_O)
	MatchState.claim_pickup(second, 901)
	_check("a second card is left where it lies", _card_live(second), true)
	_check("and does not replace the hold in progress",
		MatchState.letter_hold_letter(901), MatchState.LETTER_G)
	MatchState.claim_pickup(second, 902)
	_check("somebody else can walk over it", _card_live(second), false)
	_check("and start their own hold", MatchState.is_holding_letter(902), true)

	# The payout, which is the only thing that scores.
	_expire_hold(901)
	_check("a finished hold grants the letter",
		MatchState.letters_for(901), MatchState.LETTER_G)
	_check("and hands the spear back", MatchState.is_holding_letter(901), false)
	_check("and leaves nothing counting down",
		MatchState.letter_hold_remaining(901), 0.0)
	if combat != null and hand != null:
		_check("the spear comes back", combat.has_spear(), true)
		_check("into the hand", hand.is_carried(), true)
		_check("and the card is gone from it", hand.has_letter(), false)

	# Dying nine seconds in is the whole point of the mechanic, from the other
	# side. 902 is still holding O.
	var before := MatchState._pickups.size()
	_kill(902, 901)
	_check("dying mid-hold grants nothing", MatchState.letters_for(902), 0)
	_check("and ends the hold", MatchState.is_holding_letter(902), false)
	# Not destroyed. At an 8% drop rate a deleted letter can be a hundred deaths
	# from being replaced, and "kill the carrier and take the card" is the fight
	# the hold exists to create.
	_check("and puts the card back in circulation",
		MatchState._pickups.size(), before + 1)
	_check("carrying the letter that was being held",
		_newest_card_letter(), MatchState.LETTER_O)
	_revive(902)

	# A letter you already hold is worth nothing whether you stand still for it
	# or not, so there is nothing to stand still for (D-033).
	var dupe := _drop_card(MatchState.LETTER_G)
	MatchState.claim_pickup(dupe, 901)
	_check("a duplicate is consumed on touch", _card_live(dupe), false)
	_check("and starts no hold", MatchState.is_holding_letter(901), false)
	_check("and grants nothing", MatchState.letter_count(901), 1)

	# Zero is a real setting — the mode without the hold — and it must not go
	# through a hold that lasts one frame.
	Net.config.letter_hold_time = 0.0
	var instant := _drop_card(MatchState.LETTER_O)
	MatchState.claim_pickup(instant, 901)
	_check("a zero hold grants on touch", MatchState.letter_count(901), 2)
	_check("without ever starting one", MatchState.is_holding_letter(901), false)

	# The whistle beats the clock. Nobody is owed the last two seconds of a
	# match somebody else has already won.
	Net.config.letter_hold_time = 10.0
	var last := _drop_card(MatchState.LETTER_B)
	MatchState.claim_pickup(last, 901)
	_check("one letter short and holding the third",
		MatchState.is_holding_letter(901), true)
	MatchState.award_letter(1, MatchState.LETTER_G)
	MatchState.award_letter(1, MatchState.LETTER_O)
	MatchState.award_letter(1, MatchState.LETTER_B)
	_check("somebody else completes the word first",
		MatchState.phase, MatchState.Phase.POST_MATCH)
	_check("reason", finished.get("reason"), "letters")
	_check("the hold ends with the match", MatchState.is_holding_letter(901), false)
	_check("granting nothing",
		MatchState.letters_for(901) & MatchState.LETTER_B, 0)


func _run_letter_hold_disconnect() -> void:
	_scenario("a hold ended by a disconnect")
	_begin(3, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.FREE_FOR_ALL
		c.win_condition = MatchConfig.WinCondition.LETTERS
		c.kill_limit = 50
		c.time_limit = 0
		c.letter_hold_time = 10.0)

	var card := _drop_card(MatchState.LETTER_B)
	MatchState.claim_pickup(card, 902)
	_check("the leaver was holding one", MatchState.is_holding_letter(902), true)

	# Closing the game mid-hold is a death, exactly. The alternative — a hold
	# that survives its owner — is a card that never comes back.
	var before := MatchState._pickups.size()
	MatchState._on_player_left(902)
	_check("the hold goes with them", MatchState.is_holding_letter(902), false)
	_check("and the card does not", MatchState._pickups.size(), before + 1)
	_check("it is the same letter", _newest_card_letter(), MatchState.LETTER_B)


func _run_elder() -> void:
	_scenario("the Elder: a robe, a bolt, a clock and no way to be killed")
	_begin(3, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.FREE_FOR_ALL
		c.win_condition = MatchConfig.WinCondition.KILL_LIMIT
		c.kill_limit = 50
		c.time_limit = 0
		c.letter_hold_time = 10.0
		c.lightning_cooldown = 5.0
		# Set rather than left at their defaults, and all four deliberately
		# *unlike* them: a check against a multiplier that happens to be 1.0
		# passes whether or not anything applies it, and a duration read off the
		# same dial the code reads would agree with a clock that was never
		# started. These are the numbers this scenario asserts against, and they
		# are not the numbers that ship.
		c.elder_duration = 45.0
		c.elder_speed_multiplier = 1.5
		c.elder_jump_multiplier = 1.4
		c.lightning_delay = 0.3)

	# The robe is a drop like any other: it lies there and the first living Bog
	# to walk over it takes it.
	var robe := _drop_robe()
	_check("nobody starts as the Elder", MatchState.is_elder(901), false)
	MatchState.claim_pickup(robe, 901)
	_check("the robe is taken off the ground", _card_live(robe), false)
	_check("and its finder is the Elder", MatchState.is_elder(901), true)
	# The rules and the cloth, which are not allowed to disagree.
	_check("who is actually wearing it", _wearing_robe(901), true)
	_check("and nobody else became one", MatchState.is_elder(902), false)

	# The hand. An Elder has no spear at all — not a spear on cooldown, not a
	# spear it is not allowed to throw: `has_spear()` is false for as long as it
	# is the Elder, and the fist is empty of shaft and full of energy instead.
	var combat := _combat(901)
	var hand := _hand(901)
	_check("the Elder has a combat node", combat != null, true)
	if combat != null and hand != null:
		_check("an Elder has no spear", combat.has_spear(), false)
		_check("and no shaft in its hand", hand.is_carried(), false)
		_check("it has lightning instead", combat.has_lightning(), true)
		_check("and the hand crackles to say so", hand.is_charged(), true)

	# It still collects everything else. The robe replaces the spear and
	# nothing else (D-038).
	MatchState.claim_pickup(MatchState._spawn_drop(
		Pickup.Kind.SHIELD, 0, Vector3.ZERO), 901)
	if combat != null:
		_check("an Elder still picks up shields", combat.shield_count(), 1)

	# The cooldown gates a second cast, and it is the host's copy that does it —
	# `_cast` goes straight at `_host_cast_lightning`, which is the only thing
	# in the game that can actually fire one.
	_cast(901)
	if combat != null:
		_check("firing spends the shot", combat.has_lightning(), false)
		_check("and the hand goes dark", hand.is_charged(), false)
		var before := combat._server_lightning_ready_at
		_cast(901)
		_check("a second cast inside the cooldown is refused",
			combat._server_lightning_ready_at, before)
		# Wind both clocks back rather than sitting through five real seconds of
		# a config dial, exactly as `_expire_hold` does for the letter.
		combat._server_lightning_ready_at = 0.0
		combat._lightning_ready_at = 0.0
		_check("and it comes back when the cooldown ends",
			combat.has_lightning(), true)

	# A letter hold takes the bolt away exactly as it takes the spear away
	# (D-035). Without this the hold stops being a vulnerability for precisely
	# the player who most needs to have one.
	Net.config.win_condition = MatchConfig.WinCondition.LETTERS
	var card := _drop_card(MatchState.LETTER_G)
	MatchState.claim_pickup(card, 901)
	_check("an Elder can pick up a letter", MatchState.is_holding_letter(901), true)
	if combat != null and hand != null:
		_check("and cannot fire while holding it", combat.has_lightning(), false)
		_check("the crackle goes with it", hand.is_charged(), false)
		_check("and the card is in the hand instead", hand.has_letter(), true)
		var held_at := combat._server_lightning_ready_at
		_cast(901)
		_check("the host refuses a cast mid-hold",
			combat._server_lightning_ready_at, held_at)
	_expire_hold(901)
	_check("finishing the hold still scores", MatchState.letters_for(901),
		MatchState.LETTER_G)
	if combat != null and hand != null:
		_check("and hands the bolt back, not a spear", combat.has_lightning(), true)
		_check("with the spear still gone", combat.has_spear(), false)
		_check("and the crackle back in the fist", hand.is_charged(), true)
	Net.config.win_condition = MatchConfig.WinCondition.KILL_LIMIT

	# **The boosts** (D-040). Read off `Bog` rather than off the config, because
	# the thing worth checking is that the multiplier reached the one point every
	# stance comes out of — a boost applied to `RUN_SPEED` alone is a walking
	# Elder that moves at exactly everybody else's pace, and the difference
	# between those two bugs and no bug at all is invisible from the dial.
	var body: Bog = MatchState.bogs.get(901)
	if body != null:
		_near("the Elder walks faster", body.target_speed(),
			Bog.WALK_SPEED * Net.config.elder_speed_multiplier)
		body.wants_sprint = true
		_near("and sprints faster by the same factor", body.target_speed(),
			Bog.RUN_SPEED * Net.config.elder_speed_multiplier)
		body.wants_sprint = false
		_near("and jumps harder", body.jump_velocity(),
			Bog.JUMP_VELOCITY * Net.config.elder_jump_multiplier)
	# The apex, which is the number that actually decides whether a boost puts a
	# player somewhere a map did not plan for — and it is not the number on the
	# slider, because height goes as the square of launch velocity. Pinned here
	# rather than left in a comment: the shipping 1.25 is +56% of height, and
	# that is the fact anybody retuning this dial has to be handed.
	_near("a plain jump tops out at 1.69 m",
		snappedf(Bog.apex_for(Bog.JUMP_VELOCITY), 0.01), 1.69)
	_near("the shipping 1.25x boost tops out at 2.64",
		snappedf(Bog.apex_for(Bog.JUMP_VELOCITY * 1.25), 0.01), 2.64)

	# **An Elder cannot be killed.** This supersedes D-038's "dying consumes the
	# robe": with nothing able to kill one, death is no longer the exit and the
	# clock below is (D-040).
	#
	# Checked here *and* against a real spear in `tools/combat_range.tscn
	# lightning`, which is the one that matters. This asserts the rule where the
	# rule lives; that one asserts it where a player meets it, with a real shaft
	# in the air and a real `report_kill` at the end of it. D-039 is the standing
	# lesson about why the second is not optional.
	var deaths := MatchState.deaths(901)
	var killer_kills := MatchState.kills(902)
	_kill(901, 902)
	_check("a spear does not kill the Elder", MatchState.is_alive(901), true)
	_check("it is still the Elder", MatchState.is_elder(901), true)
	_check("and the robe is still on", _wearing_robe(901), true)
	_check("nobody is credited with the kill", MatchState.kills(902), killer_kills)
	_check("and it costs no death", MatchState.deaths(901), deaths)
	# The one thing a refused hit does leave behind, and it is not cosmetic: an
	# Elder shoved off a ledge by a bolt that did not kill it is a void death
	# somebody earned.
	_check("but the attacker is remembered for the void",
		MatchState.stats[901]["last_attacker"], 902)

	# **The clock is the exit.** The host owns it, exactly as it owns a letter
	# hold, and every peer counts the same row down.
	_check("the robe is on a clock", MatchState.elder_remaining(901) > 0.0, true)
	_check("and it is not longer than the dial",
		MatchState.elder_remaining(901) <= Net.config.elder_duration, true)

	# **Expiry is not a death.** Everything the Bog had before the robe is still
	# there after it: the letter it earned mid-scenario and the shield it
	# picked up. That is the half of this most likely to rot, because the
	# obvious way to write the teardown is to reuse the death path.
	var pickups := MatchState._pickups.size()
	var letters_before := MatchState.letters_for(901)
	var stock_before := combat.shield_count() if combat != null else -1
	_expire_elder(901)
	_check("the robe burns out on its own", MatchState.is_elder(901), false)
	_check("and comes off the body", _wearing_robe(901), false)
	_check("and puts nothing back on the ground",
		MatchState._pickups.size(), pickups)
	_check("expiry is not a death", MatchState.is_alive(901), true)
	_check("it keeps its letters", MatchState.letters_for(901), letters_before)
	if combat != null and hand != null:
		_check("and its carried stock", combat.shield_count(), stock_before)
		_check("the spear comes back", combat.has_spear(), true)
		_check("and the bolt is gone", combat.has_lightning(), false)
		_check("with the shaft back in the fist", hand.is_carried(), true)
	if body != null:
		_near("and it moves like a Bog again", body.target_speed(), Bog.WALK_SPEED)
		_near("and jumps like one", body.jump_velocity(), Bog.JUMP_VELOCITY)

	# **The void still kills, and it is the only thing that does.** Spawn
	# protection carves the same hole for the same reason: a Bog that cannot die
	# to the void falls past the bottom of the island for ever, alive and
	# unreachable. Without this the invincibility above is a soft-lock waiting
	# for somebody to walk off a ledge.
	MatchState.claim_pickup(_drop_robe(), 901)
	_check("a second robe is claimable", MatchState.is_elder(901), true)
	MatchState.report_kill(901, 901, Bog.Cause.VOID, Vector3.ZERO, Vector3.DOWN, "")
	_check("the void kills an Elder", MatchState.is_alive(901), false)
	_check("and takes the robe with it", MatchState.is_elder(901), false)
	_check("and off the body", _wearing_robe(901), false)

	_revive(901)
	MatchState._do_respawn(901, Transform3D.IDENTITY, MatchState.deaths(901))
	_check("respawning does not give it back", MatchState.is_elder(901), false)
	if combat != null:
		_check("and the spear is back", combat.has_spear(), true)
		_check("with no lightning", combat.has_lightning(), false)

	# Two robes, two Elders. There is deliberately no "only one" rule: a robe
	# that refused to be picked up would be the most conspicuous object on the
	# map, permanently.
	MatchState.claim_pickup(_drop_robe(), 901)
	MatchState.claim_pickup(_drop_robe(), 902)
	_check("two Elders can exist at once",
		MatchState.is_elder(901) and MatchState.is_elder(902), true)
	_check("both wearing one",
		_wearing_robe(901) and _wearing_robe(902), true)
	# And two clocks, not one. `_tick_elders` walks a copy of the keys and ends
	# only the rows that are up, so one robe burning out must leave the other
	# alone — the bug here would be a loop that erased while iterating, which in
	# GDScript skips a row rather than erroring.
	_expire_elder(901)
	_check("one robe burning out leaves the other", MatchState.is_elder(902), true)
	_check("and only the expired one came off", MatchState.is_elder(901), false)

	# A disconnect is the third and last way one ends — and unlike a letter card
	# there is nothing to put back, so the world gains nothing.
	pickups = MatchState._pickups.size()
	MatchState._on_player_left(902)
	_check("a leaver stops being the Elder", MatchState.is_elder(902), false)
	_check("and leaves no robe behind", MatchState._pickups.size(), pickups)

	_sweep_effects()


## The lobby pick, where it actually lands: on a Bog, in a match (D-069).
##
## `tools/weapon_select.tscn` has the other half — the roster row, the request
## path, the lock and the rematch. This is the half that only exists once a body
## has been built from that row: `MatchState._create_bog` seeds `Bog.weapon` off
## the roster, `BogCombat` gates its three `has_*` on it, and the three things
## that could already take a weapon away have to go on doing exactly that.
##
## Why it is here and not there: these are real Bogs with real combat nodes and
## real hands, spawned by the host through `register_arena`, and this file is
## already the one place that stands those up (see `_combat` and `_hand`).
func _run_loadout() -> void:
	_scenario("three Bogs, three weapons")
	_begin(3, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.FREE_FOR_ALL
		c.win_condition = MatchConfig.WinCondition.KILL_LIMIT
		c.kill_limit = 50
		c.time_limit = 0
		c.letter_hold_time = 10.0
		# Deliberately unlike each other and unlike the defaults, so that a gate
		# reading the wrong clock is visible rather than accidentally right.
		c.spear_recharge = 3.0
		c.bow_recharge = 1.0
		c.sword_recharge = 6.0,
		null, [Loadout.Weapon.SPEAR, Loadout.Weapon.BOW, Loadout.Weapon.SWORD])

	var want := {1: Loadout.Weapon.SPEAR, 901: Loadout.Weapon.BOW,
		902: Loadout.Weapon.SWORD}
	for peer_id: int in want:
		var bog: Bog = MatchState.bogs.get(peer_id)
		_check("%d got a Bog" % peer_id, is_instance_valid(bog), true)
		if not is_instance_valid(bog):
			continue
		# Seeded from this peer's own copy of the roster by `_create_bog`, beside
		# the name and the team, which is why no replication was needed for it.
		_check("%d's Bog carries what the roster says" % peer_id,
			bog.weapon, want[peer_id])

		var combat := _combat(peer_id)
		var hand := _hand(peer_id)
		_check("%d has a combat node" % peer_id, combat != null, true)
		if combat == null or hand == null:
			continue
		# **The gate, and there is still only one of it.** Each of the three is
		# the same sentence with a different weapon in it, and the loadout is one
		# more clause on all three rather than a fourth thing to ask.
		_check("%d: a spear?" % peer_id, combat.has_spear(),
			want[peer_id] == Loadout.Weapon.SPEAR)
		_check("%d: a bow?" % peer_id, combat.has_bow(),
			want[peer_id] == Loadout.Weapon.BOW)
		_check("%d: a great sword?" % peer_id, combat.has_sword(),
			want[peer_id] == Loadout.Weapon.SWORD)
		# And the hand, which is drawn from the gate and may not disagree with
		# it. This is the user's *"only show the weapon you have selected"*.
		_check("%d: a shaft in the fist?" % peer_id, hand.is_carried(),
			want[peer_id] == Loadout.Weapon.SPEAR)
		_check("%d: a bow in the other one?" % peer_id, hand.has_bow(),
			want[peer_id] == Loadout.Weapon.BOW)
		_check("%d: a hilt in both?" % peer_id, hand.has_sword(),
			want[peer_id] == Loadout.Weapon.SWORD)
		_check("%d: no arrow until it draws" % peer_id, hand.has_arrow(), false)
		_check("%d: no letter" % peer_id, hand.has_letter(), false)
		_check("%d: no crackle" % peer_id, hand.is_charged(), false)

	# **Three cooldowns, and a Bog only spends one of them.** The other two go on
	# ticking and must not be able to reach into a hand they have nothing to do
	# with — which is the thing that would quietly come apart if the gate had
	# been written as a `match` on the weapon somewhere else.
	var archer := _combat(901)
	if archer != null:
		archer._spear_ready_at = archer._now() + 1000.0
		archer._sword_ready_at = archer._now() + 1000.0
		archer._refresh_hand()
		_check("a spear recharge the archer is not using changes nothing",
			archer.has_bow(), true)
		_check("and leaves the bow in the hand", _hand(901).has_bow(), true)
		_check("while the spear it does not have stays absent",
			archer.has_spear(), false)

	# The three overrides, unchanged and re-verified rather than reasoned about.
	#
	# A letter hold disarms whatever you picked (D-035). It was the spear's rule
	# and then the bow's; it is now one rule over three weapons, and it is the
	# same clause in the same three functions.
	var card := _drop_card(MatchState.LETTER_G)
	MatchState.claim_pickup(card, 902)
	var swordsman := _combat(902)
	_check("a hold disarms the swordsman", swordsman.has_sword(), false)
	_check("and takes the sword out of the fists", _hand(902).has_sword(), false)
	_check("putting the card there instead", _hand(902).has_letter(), true)
	_expire_hold(902)
	_check("and the sword comes back when the hold ends",
		swordsman.has_sword(), true)
	_check("into the fists", _hand(902).has_sword(), true)

	# The Elder replaces whatever you picked (D-038), which before this step was
	# a sentence about the spear and is now a sentence about all three.
	MatchState.claim_pickup(_drop_robe(), 901)
	_check("the archer is the Elder", MatchState.is_elder(901), true)
	_check("an Elder has no bow", archer.has_bow(), false)
	_check("nor a spear it never had", archer.has_spear(), false)
	_check("nor a sword it never had", archer.has_sword(), false)
	_check("the bow leaves the hand", _hand(901).has_bow(), false)
	_check("and lightning is there instead", archer.has_lightning(), true)
	_check("with the fist crackling to say so", _hand(901).is_charged(), true)
	_expire_elder(901)
	_check("and the bow comes back when the robe burns out",
		archer.has_bow(), true)
	_check("into the hand it left", _hand(901).has_bow(), true)

	# A drink empties both fists (D-067). The most obviously true of the three
	# for a two-handed weapon, and the one that had to be re-checked against a
	# sword that is now *carried* rather than appearing for the length of a swing.
	swordsman.grant_potion(1)
	swordsman._server_potions = 1
	swordsman._host_drink_potion()
	_check("the swordsman is drinking", swordsman.is_channelling(), true)
	_check("and has no sword while it does", swordsman.has_sword(), false)
	_check("with nothing in either fist", _hand(902).has_sword(), false)
	swordsman._do_stop_drink()
	swordsman._refresh_hand()
	_check("the sword comes back when the bottle goes down",
		swordsman.has_sword(), true)

	# And the default: a row that never touched the picker plays the match it
	# always played. This is the promise the whole step rests on.
	_begin(2, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.FREE_FOR_ALL
		c.win_condition = MatchConfig.WinCondition.KILL_LIMIT
		c.kill_limit = 50
		c.time_limit = 0)
	Net.players[1].erase("weapon")
	var plain := _combat(1)
	if plain != null:
		MatchState.bogs[1].weapon = Net.player_weapon(1)
		plain._refresh_hand()
		_check("a row with no weapon on it is a spear Bog",
			plain.has_spear(), true)
		_check("with a shaft in its fist", _hand(1).is_carried(), true)
		_check("and neither of the other two", plain.has_bow(), false)
		_check("nor the third", plain.has_sword(), false)


func _run_time_limit() -> void:
	_scenario("the clock")
	var finished := {}
	_begin(3, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.FREE_FOR_ALL
		c.win_condition = MatchConfig.WinCondition.TIME_ONLY
		c.kill_limit = 50
		c.time_limit = 10)
	MatchState.match_finished.connect(func(s: Dictionary) -> void:
		finished.merge(s, true), CONNECT_ONE_SHOT)

	_kill(901, 902)
	_check("clock is running", MatchState.time_left > 0.0, true)
	MatchState._tick_clock(9.0)
	_check("still playing with a second left", MatchState.phase, MatchState.Phase.PLAYING)
	MatchState._tick_clock(2.0)
	_check("clock stops at zero", MatchState.time_left, 0.0)
	_check("finished on time", MatchState.phase, MatchState.Phase.POST_MATCH)
	_check("reason", finished.get("reason"), "time")
	_check("the leader wins on points", _leader(finished), 902)


func _run_void_credit() -> void:
	_scenario("falling off the island")
	_begin(3, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.FREE_FOR_ALL
		c.win_condition = MatchConfig.WinCondition.KILL_LIMIT
		c.kill_limit = 50
		c.time_limit = 0)

	# Nobody touched them: the fall is their own doing, and costs them a death
	# without paying anyone.
	MatchState.report_kill(901, 901, Bog.Cause.VOID, Vector3.ZERO, Vector3.DOWN, "")
	_check("a fall costs a death", MatchState.deaths(901), 1)
	_check("and pays nobody", MatchState.kills(901), 0)
	_revive(901)

	# Pulled off the edge: `note_attack` is what carries the credit across.
	MatchState.note_attack(901, 902)
	MatchState.report_kill(901, 902, Bog.Cause.VOID, Vector3.ZERO, Vector3.DOWN, "")
	_check("the thrower is credited", MatchState.kills(902), 1)


func _run_spawn_protection() -> void:
	_scenario("spawn protection")
	_begin(3, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.FREE_FOR_ALL
		c.win_condition = MatchConfig.WinCondition.KILL_LIMIT
		c.kill_limit = 50
		c.time_limit = 0
		c.spawn_protection = 5.0)

	# A Bog that has just spawned is solid but unkillable, so spawning face to
	# face with someone holding a spear is survivable.
	var victim: Bog = MatchState.bogs.get(901)
	_check("a Bog exists to protect", is_instance_valid(victim), true)
	_check("and starts protected", victim.is_invulnerable(), true)
	_kill(901, 1)
	_check("a spear cannot kill it", MatchState.is_alive(901), true)
	_check("and earns nothing", MatchState.kills(1), 0)

	# Falling off the island is not something protection should save you from,
	# or a protected Bog could sit in the void forever.
	MatchState.report_kill(901, 901, Bog.Cause.VOID, Vector3.ZERO, Vector3.DOWN, "")
	_check("but the void still takes it", MatchState.is_alive(901), false)

	# Once protection lapses the same spear lands.
	_revive(901)
	victim.invulnerable_until = 0.0
	_kill(901, 1)
	_check("and it dies once protection lapses", MatchState.is_alive(901), false)
	_check("paying the killer", MatchState.kills(1), 1)


## Random teams (D-048): the deal is balanced, it lands on real teams, it is
## what Start does and not what a rematch does, and a new start from the lobby
## deals again.
func _run_random_teams() -> void:
	_scenario("random teams")
	MatchState.reset()
	# Many deals rather than one, because a shuffle that happens to come out
	# balanced once proves nothing about the dealing.
	for shape: Array in [[7, 2], [5, 3], [8, 8], [2, 5], [1, 2], [8, 3]]:
		var count: int = shape[0]
		var teams: int = shape[1]
		var ids: Array = []
		for i in count:
			ids.append(1 if i == 0 else 900 + i)
		for trial in 25:
			var dealt := Net.deal_teams(ids, teams)
			_check("%d into %d: everyone is dealt" % [count, teams],
				dealt.size(), count)
			var sizes := PackedInt32Array()
			sizes.resize(teams)
			sizes.fill(0)
			var valid := true
			for peer_id: Variant in ids:
				var team: int = dealt.get(peer_id, MatchConfig.TEAM_NONE)
				if team < 0 or team >= teams:
					valid = false
				else:
					sizes[team] += 1
			_check("%d into %d: everyone is on a real team" % [count, teams], valid, true)
			var low: int = sizes[0]
			var high: int = sizes[0]
			for n in sizes:
				low = mini(low, n)
				high = maxi(high, n)
			_check("%d into %d: team sizes within one (%s)" % [count, teams, str(sizes)],
				high - low <= 1, true)

	# Now through the shipping path: a seven-Bog lobby, host pressing Start.
	Net.start_offline()
	for i in range(1, 7):
		Net.players[900 + i] = {"name": "R%d" % i, "team": 0, "ready": true}
	Net.config.mode = MatchConfig.Mode.TEAMS
	Net.config.team_count = 2
	Net.config.random_teams = true
	# Everyone is on team 0, which a hand-picked lobby refuses to start. A random
	# one is about to be dealt, so only the head count is asked.
	_check("random teams can start with everyone on one team",
		Net.can_start_match(), true)
	Net.set_team(1)
	_check("a team pick is refused under random teams", Net.player_team(1), 0)

	Net.request_match_start()
	_check("the match is running", Net.match_running, true)
	var at_start := _teams_digest()
	var counts := [0, 0]
	for peer_id: int in Net.peer_ids():
		counts[Net.player_team(peer_id)] += 1
	_check("Start dealt seven Bogs four and three", [mini(counts[0], counts[1]),
		maxi(counts[0], counts[1])], [3, 4])

	# The user's call: a rematch keeps the teams as dealt.
	for i in 5:
		Net.request_rematch()
		_check("rematch %d keeps the dealt teams" % (i + 1), _teams_digest(), at_start)

	# Back in the lobby they still stand — nothing deals until Start is pressed.
	Net.request_return_to_lobby()
	_check("returning to the lobby keeps them too", _teams_digest(), at_start)

	# And a fresh start deals again. One deal of seven into two repeats the last
	# with probability 1/35, so a new line-up within twenty starts is certain in
	# every sense but the pedantic one.
	var redealt := false
	for i in 20:
		Net.request_return_to_lobby()
		Net.request_match_start()
		if _teams_digest() != at_start:
			redealt = true
			break
	_check("a new start from the lobby deals again", redealt, true)

	# Off, Start leaves hand-picked teams exactly as they were.
	Net.request_return_to_lobby()
	Net.config.random_teams = false
	for peer_id: int in Net.peer_ids():
		Net.players[peer_id]["team"] = 1 if peer_id % 2 == 0 else 0
	var picked := _teams_digest()
	Net.request_match_start()
	_check("without random teams, Start deals nothing", _teams_digest(), picked)
	Net.request_return_to_lobby()
	Net.config = MatchConfig.new()


func _teams_digest() -> Array:
	var out: Array = []
	for peer_id: int in Net.peer_ids():
		out.append([peer_id, Net.player_team(peer_id)])
	return out


## Capture B·O·G (D-051), in a world with a floor in it.
##
## Every other letters scenario here has no geometry, and that is fine for them;
## this one cannot do without. A dead carrier's card lands on *the ground under
## the death point*, the cards go out onto ground the physics has settled, and a
## death over nothing has to send the card home instead — none of which can be
## told apart from "the card went home" with no floor to land on. So the arena is
## a Node3D with one big box under it, and the scenario waits two physics frames
## for the box to be in the broadphase, exactly as a real map's collision is.
const CAPTURE_BASES: Array[Vector3] = [Vector3(0, 0, -30), Vector3(0, 0, 30)]
const CAPTURE_HOMES: Array[Vector3] = [Vector3(-14, 0, 0), Vector3(14, 0, 0), Vector3(0, 0, 14)]
const CAPTURE_DEATH := Vector3(10, 0, -8)
const CAPTURE_DEATH_2 := Vector3(-9, 0, 9)


func _capture_world() -> Node3D:
	var world := Node3D.new()
	world.name = "CaptureWorld"
	add_child(world)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, -0.5, 0.0)
	world.add_child(body)
	return world


func _capture_card(letter: int) -> int:
	return int(MatchState._capture.get(letter, {}).get("pickup", 0))


func _letter_cards() -> Array[Pickup]:
	var out: Array[Pickup] = []
	for id: int in MatchState._pickups:
		var item: Pickup = MatchState._pickups[id]
		if is_instance_valid(item) and item.kind == Pickup.Kind.LETTER:
			out.append(item)
	return out


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


## Put a Bog somewhere and let the host's own tick look at it, synchronously, so
## no frame in between can move a remote Bog back towards its last snapshot.
func _stand(peer_id: int, at: Vector3) -> void:
	var bog: Bog = MatchState.bogs.get(peer_id)
	if is_instance_valid(bog):
		bog.global_position = at
	MatchState._tick_capture()


## Stand on a vault long enough to lift the card out of it. The clock is faked
## the same way the return timer's is, by pushing the attempt's start back — a
## real wait would put `capture_steal_time` seconds into the suite per steal.
func _steal(peer_id: int, at: Vector3) -> void:
	_stand(peer_id, at)
	if MatchState._steals.has(peer_id):
		MatchState._steals[peer_id]["since"] -= 99.0
	MatchState._tick_capture()


func _run_capture() -> void:
	_scenario("capture B·O·G: three cards, carried home, dropped and returned")
	var world := _capture_world()
	var finished := {}
	var dropped: Array = []
	var returned: Array = []
	_begin(4, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.TEAMS
		c.team_count = 2
		c.win_condition = MatchConfig.WinCondition.CAPTURE
		c.kill_limit = 50
		c.time_limit = 0
		# The two chances forced to the top, so a letter out of a corpse would be
		# certain if the loot roll ever handed one out in this mode.
		c.letter_drop_chance = 1.0
		c.elder_drop_chance = 0.0
		# Not the defaults, so a check against them proves the dial was read.
		c.capture_return_time = 12.0
		c.capture_carrier_speed = 0.8
		MatchState.set_capture_map(CAPTURE_BASES, CAPTURE_HOMES, 4.0), world)
	MatchState.match_finished.connect(func(summary: Dictionary) -> void:
		finished.merge(summary, true), CONNECT_ONE_SHOT)
	var on_drop := func(peer_id: int, letter: int) -> void: dropped.append([peer_id, letter])
	var on_return := func(letter: int) -> void: returned.append(letter)
	MatchState.letter_dropped.connect(on_drop)
	MatchState.letter_returned.connect(on_return)

	# The cards go out on their own, a couple of physics frames in.
	# Frames rather than a fixed count of physics ticks: the first frames after
	# load can run several physics steps inside one process frame, and it is the
	# host's `_process` that puts the cards out.
	for i in 60:
		if MatchState._capture.size() == 3:
			break
		await get_tree().process_frame
	var cards := _letter_cards()
	_check("three letters are out at the start", cards.size(), 3)
	_check("one row per letter", MatchState._capture.size(), 3)
	for i in MatchState.LETTERS.size():
		var letter := MatchState.LETTERS[i]
		var card: Pickup = MatchState._pickups.get(_capture_card(letter))
		_check("%s is at home" % MatchState.letter_name(letter),
			MatchState.capture_state(letter), "home")
		_check("%s's card is the right letter" % MatchState.letter_name(letter),
			card.letter if card != null else 0, letter)
		_check("%s's card is on its home point" % MatchState.letter_name(letter),
			card != null and _flat_distance(card.global_position, CAPTURE_HOMES[i]) < 0.01,
			true)

	# No card ever comes out of a corpse in this mode, even at 100%.
	var before := MatchState._pickups.size()
	MatchState.report_kill(903, 1, Bog.Cause.SPEAR, CAPTURE_DEATH_2, Vector3.FORWARD, "Spine1")
	_check("a death still drops loot", MatchState._pickups.size(), before + 1)
	_check("but never a letter", _letter_cards().size(), 3)
	_revive(903)

	# Pick up. Peer 1 is team 0, whose base is CAPTURE_BASES[0].
	var b_card := _capture_card(MatchState.LETTER_B)
	MatchState.claim_pickup(b_card, 1)
	_check("touching a card makes a carrier", MatchState.is_holding_letter(1), true)
	_check("of that letter", MatchState.letter_hold_letter(1), MatchState.LETTER_B)
	_check("the card leaves the ground", _card_live(b_card), false)
	_check("the letter is carried", MatchState.capture_state(MatchState.LETTER_B), "carried")
	_check("a carry has no clock", is_inf(MatchState.letter_hold_remaining(1)), true)
	_check("and scores nothing yet", MatchState.team_letters(0), 0)
	var combat := _combat(1)
	if combat != null:
		_check("a carrier cannot throw", combat.has_spear(), false)
	var body: Bog = MatchState.bogs.get(1)
	if body != null:
		_near("a carrier walks at the carrier speed", body.target_speed(),
			Bog.WALK_SPEED * 0.8)
	# One at a time.
	var o_card := _capture_card(MatchState.LETTER_O)
	MatchState.claim_pickup(o_card, 1)
	_check("a carrier leaves a second card where it is", _card_live(o_card), true)
	# Still nothing after the carry has run far longer than any hold.
	MatchState._tick_letter_holds()
	_check("no clock ends a carry", MatchState.is_holding_letter(1), true)

	# The wrong vault.
	var layout := MatchState.capture_layout()
	var vault_0: Vector3 = layout.vaults[0]
	var vault_1: Vector3 = layout.vaults[1]
	_stand(1, vault_1)
	_check("walking into the enemy vault banks nothing", MatchState.team_letters(0), 0)
	_check("and the carrier still has it", MatchState.is_holding_letter(1), true)
	_check("and neither does the enemy team", MatchState.team_letters(1), 0)

	# The base is no longer the trigger — the vault inside it is (D-068). Standing
	# in your own base but away from the vault has to bank nothing, or the vault
	# is decoration.
	_stand(1, CAPTURE_BASES[0])
	_check("your own base alone banks nothing", MatchState.team_letters(0), 0)
	_check("and the carry is still running", MatchState.is_holding_letter(1), true)

	# The right one.
	_stand(1, vault_0)
	_check("walking into your own vault banks it", MatchState.team_letters(0),
		MatchState.LETTER_B)
	_check("the banker's own row keeps it", MatchState.letters_for(1), MatchState.LETTER_B)
	_check("and the carry ends", MatchState.is_holding_letter(1), false)
	_check("the card stays in the vault", MatchState.capture_state(MatchState.LETTER_B),
		"home")
	_check("and the vault is the team's", MatchState.banked_team_of(MatchState.LETTER_B), 0)
	var g_again: Pickup = MatchState._pickups.get(_capture_card(MatchState.LETTER_B))
	_check("as a real card standing on the vault",
		g_again != null and _flat_distance(g_again.global_position, vault_0) < 0.01,
		true)

	# Your own bank is not a pickup. Walking over it must not undo it.
	MatchState.claim_pickup(1, _capture_card(MatchState.LETTER_B))
	_check("a team cannot pick its own banked card back up",
		MatchState.is_holding_letter(1), false)
	_check("and it still has the letter", MatchState.team_letters(0), MatchState.LETTER_B)

	# Walking over an enemy vault does nothing on its own — the card comes out on
	# a timer, not on contact (D-068). This is the assertion that proves the
	# timer exists at all.
	MatchState.claim_pickup(901, _capture_card(MatchState.LETTER_B))
	_check("touching an enemy vault does not lift the card",
		MatchState.is_holding_letter(901), false)
	_stand(901, vault_0)
	_check("and standing on it for an instant does not either",
		MatchState.is_holding_letter(901), false)
	_check("the robbed team still has it mid-steal", MatchState.team_letters(0),
		MatchState.LETTER_B)
	# Stepping off drops the attempt rather than banking the progress.
	_stand(901, CAPTURE_DEATH)
	_check("stepping off the vault abandons the steal",
		MatchState._steals.has(901), false)

	# The steal. Peer 901 is on team 1, and takes G out of team 0's vault. The
	# signal is captured because the HUD's banner hangs off it (D-069), and a
	# theft nobody is told about is the mode's loudest event going unannounced.
	var thefts: Array = []
	var on_theft := func(who: int, what: int, from_team: int) -> void:
		thefts.append([who, what, from_team])
	MatchState.letter_stolen.connect(on_theft)
	_steal(901, vault_0)
	_check("the theft is announced once", thefts.size(), 1)
	_check("naming the thief", thefts[0][0] if thefts.size() > 0 else 0, 901)
	_check("the letter", thefts[0][1] if thefts.size() > 0 else 0, MatchState.LETTER_G)
	_check("and the robbed team", thefts[0][2] if thefts.size() > 0 else -9, 0)
	MatchState.letter_stolen.disconnect(on_theft)
	_check("an enemy takes the card out of the vault",
		MatchState.is_holding_letter(901), true)
	_check("and the robbed team loses the letter", MatchState.team_letters(0), 0)
	_check("the banker's own row loses it too", MatchState.letters_for(1), 0)
	_check("the thief has not scored it yet", MatchState.team_letters(1), 0)
	_check("and it is in nobody's vault",
		MatchState.banked_team_of(MatchState.LETTER_B), MatchConfig.TEAM_NONE)

	# Carried into the thief's own vault, it is a straight transfer.
	_stand(901, vault_1)
	_check("the thief banks it in their own vault", MatchState.team_letters(1),
		MatchState.LETTER_B)
	_check("and the robbed team still has nothing", MatchState.team_letters(0), 0)

	# And back again: a team may steal back what it just lost, with no cooldown.
	_steal(1, vault_1)
	_check("the robbed team can steal it straight back",
		MatchState.is_holding_letter(1), true)
	_check("which takes it off the thief", MatchState.team_letters(1), 0)
	_stand(1, vault_0)
	_check("and banking it again restores it", MatchState.team_letters(0),
		MatchState.LETTER_B)
	_check("still three letters in the world", _letter_cards().size(), 3)
	_check("and the match goes on", MatchState.phase, MatchState.Phase.PLAYING)
	_stand(1, Vector3.ZERO)

	# A team cannot pick up a letter it has already banked; the other team can.
	var b_id := _capture_card(MatchState.LETTER_B)
	MatchState.claim_pickup(b_id, 902)
	_check("a team leaves its own banked letter on the ground", _card_live(b_id), true)
	_check("and its player carries nothing", MatchState.is_holding_letter(902), false)

	# A carrier dies: the card drops where they died.
	MatchState.claim_pickup(_capture_card(MatchState.LETTER_O), 901)
	_check("the other team picks up O", MatchState.letter_hold_letter(901),
		MatchState.LETTER_O)
	MatchState.report_kill(901, 1, Bog.Cause.SPEAR, CAPTURE_DEATH, Vector3.FORWARD, "Spine1")
	_check("a dead carrier carries nothing", MatchState.is_holding_letter(901), false)
	_check("the card is dropped", MatchState.capture_state(MatchState.LETTER_O), "dropped")
	var lying: Pickup = MatchState._pickups.get(_capture_card(MatchState.LETTER_O))
	_check("there is a card on the ground", lying != null, true)
	if lying != null:
		_check("at the death point", _flat_distance(lying.global_position, CAPTURE_DEATH) < 0.01,
			true)
		_near("on the floor under it", lying.global_position.y, Pickup.HOVER)
		_check("carrying O", lying.letter, MatchState.LETTER_O)
	# Within a tenth of a second: the host's clock has moved on by however long
	# the lines since the death took.
	_check("and it goes home after the configured time", absf(
		float(MatchState._capture[MatchState.LETTER_O]["return_at"]) - MatchState._now() - 12.0)
		< 0.1, true)
	_check("the drop is told", dropped, [[901, MatchState.LETTER_O]])
	_check("the loot roll still gave no letter", _letter_cards().size(), 3)
	_revive(901)

	# Anybody can recover it before then — here the team that killed the carrier.
	var dropped_id := _capture_card(MatchState.LETTER_O)
	MatchState._tick_capture()
	_check("nothing returns early", MatchState.capture_state(MatchState.LETTER_O), "dropped")
	MatchState.claim_pickup(dropped_id, 902)
	_check("an enemy picks up the dropped card", MatchState.letter_hold_letter(902),
		MatchState.LETTER_O)
	_check("which clears its return", MatchState.capture_state(MatchState.LETTER_O), "carried")

	# And drops it again; this time nobody reaches it.
	MatchState.report_kill(902, 901, Bog.Cause.SPEAR, CAPTURE_DEATH_2, Vector3.FORWARD, "Spine1")
	var second_drop := _capture_card(MatchState.LETTER_O)
	_check("dropped a second time", MatchState.capture_state(MatchState.LETTER_O), "dropped")
	MatchState._capture[MatchState.LETTER_O]["return_at"] = 0.001
	MatchState._tick_capture()
	_check("a card left lying goes home on its own clock",
		MatchState.capture_state(MatchState.LETTER_O), "home")
	_check("the dropped copy is gone", _card_live(second_drop), false)
	var o_home: Pickup = MatchState._pickups.get(_capture_card(MatchState.LETTER_O))
	_check("and a card is back on O's home point",
		o_home != null and _flat_distance(o_home.global_position, CAPTURE_HOMES[1]) < 0.01, true)
	_check("the return is told", returned, [MatchState.LETTER_O])
	_check("never more than three", _letter_cards().size(), 3)
	_revive(902)

	# A carrier who falls into the void: nowhere to land, so the card goes home.
	MatchState.claim_pickup(_capture_card(MatchState.LETTER_G), 903)
	MatchState.report_kill(903, 903, Bog.Cause.VOID, Vector3(0, -200, 0), Vector3.DOWN, "")
	_check("a card lost to the void goes straight home",
		MatchState.capture_state(MatchState.LETTER_G), "home")
	_check("still three", _letter_cards().size(), 3)
	_revive(903)

	# Team 0 banks the other two, and wins.
	MatchState.claim_pickup(_capture_card(MatchState.LETTER_O), 1)
	_stand(1, MatchState.capture_layout().vaults[0])
	_stand(1, Vector3.ZERO)
	_check("two banked", MatchState.team_letters(0),
		MatchState.LETTER_B | MatchState.LETTER_O)
	_check("not over at two", MatchState.phase, MatchState.Phase.PLAYING)
	# 902's row says alive (`_revive` wrote it) but its body is still the one
	# that died: a Bog's body keeps its collision where it fell (D-043), and the
	# body is what stands in a base. That must not bank.
	MatchState.claim_pickup(_capture_card(MatchState.LETTER_G), 902)
	_stand(902, MatchState.capture_layout().vaults[0])
	_check("a carrier whose body is dead banks nothing", MatchState.team_letters(0),
		MatchState.LETTER_B | MatchState.LETTER_O)
	_check("and keeps carrying", MatchState.is_holding_letter(902), true)
	# Once the body is back, the same carry in the same base banks.
	MatchState._respawn(902)
	_stand(902, MatchState.capture_layout().vaults[0])
	_check("banking all three wins", MatchState.phase, MatchState.Phase.POST_MATCH)
	_check("reason", finished.get("reason"), "capture")
	_check("the summary carries the team's letters",
		int(finished.get("team_letters", {}).get(0, 0)), MatchState.LETTER_ALL)
	_check("and the ranking leads with the banker",
		MatchState.letter_count(1) >= MatchState.letter_count(901), true)

	# A rematch starts from nothing.
	MatchState.letter_dropped.disconnect(on_drop)
	MatchState.letter_returned.disconnect(on_return)
	MatchState.reset()
	_check("reset forgets the cards", MatchState._capture.is_empty(), true)
	_check("and the team's letters", MatchState.team_letters(0), 0)
	_check("and the layout", MatchState.capture_layout(), null)
	Net.config.win_condition = MatchConfig.WinCondition.KILL_LIMIT
	for child in get_children():
		if child is Pickup:
			child.queue_free()
	world.queue_free()
	await get_tree().process_frame


## The layout on its own: the fallback out of a ring of spawn pads, and a map's
## declared points taking over from it.
func _run_capture_layout() -> void:
	_scenario("capture B·O·G: bases and letters out of the spawn pads")
	var pads: Array[Transform3D] = []
	for i in 8:
		var bearing := TAU * float(i) / 8.0 + 0.2
		pads.append(Transform3D(Basis.IDENTITY,
			Vector3(cos(bearing) * 20.0, 1.0, sin(bearing) * 20.0)))
	var layout := CaptureLayout.plan(pads, 2)
	_check("one base per team", layout.bases.size(), 2)
	_check("from the fallback", layout.bases_declared, false)
	_check("the bases are pads", pads.any(func(p: Transform3D) -> bool:
		return p.origin == layout.bases[0]) and pads.any(func(p: Transform3D) -> bool:
		return p.origin == layout.bases[1]), true)
	_check("far apart", layout.bases[0].distance_to(layout.bases[1]) > 25.0, true)
	var per_team := [0, 0]
	for team: int in layout.pad_team:
		per_team[team] += 1
	_check("the pads split evenly between the bases", per_team, [4, 4])
	_check("three letter points", layout.letters.size(), 3)
	for point: Vector3 in layout.letters:
		var a := _flat_distance(point, layout.bases[0])
		var b := _flat_distance(point, layout.bases[1])
		_near("a letter point is as far from one base as the other", a, b)
		_check("and outside both", a > layout.base_radius, true)
	_check("in base: inside the radius", layout.in_base(0, layout.bases[0] + Vector3(3, 0, 0)), true)
	_check("in base: outside it", layout.in_base(0, layout.bases[0] + Vector3(5, 0, 0)), false)
	_check("in base: on a ledge far above it",
		layout.in_base(0, layout.bases[0] + Vector3(0, 6, 0)), false)
	_check("in base: never the other team's", layout.in_base(1, layout.bases[0]), false)

	var three := CaptureLayout.plan(pads, 3)
	_check("three teams, three bases", three.bases.size(), 3)

	var declared := CaptureLayout.plan(pads, 2, CAPTURE_BASES, CAPTURE_HOMES, 6.0)
	_check("a map's bases are used", declared.bases, CAPTURE_BASES)
	_check("and said to be", declared.bases_declared, true)
	_check("a map's letters are used", declared.letters, CAPTURE_HOMES)
	_check("a map's radius is used", declared.base_radius, 6.0)
	_check("pads go to the nearest declared base",
		declared.pad_team[0], declared.nearest_base(pads[0].origin))
	var short := CaptureLayout.plan(pads, 3, CAPTURE_BASES, [] as Array[Vector3])
	_check("too few declared bases falls back whole", short.bases_declared, false)
	_check("with a base for every team", short.bases.size(), 3)


## Free-for-all and Capture B·O·G, both ways round.
func _run_capture_lobby() -> void:
	_scenario("capture B·O·G is a Teams mode")
	var config := MatchConfig.new()
	config.apply_dict({"mode": MatchConfig.Mode.FREE_FOR_ALL,
		"win_condition": MatchConfig.WinCondition.CAPTURE})
	_check("choosing capture turns Teams on", config.mode, MatchConfig.Mode.TEAMS)
	_check("and keeps capture", config.win_condition, MatchConfig.WinCondition.CAPTURE)

	# The lobby panel's own push, through the host's real `update_config`.
	MatchState.reset()
	Net.start_offline()
	var fresh := MatchConfig.new()
	fresh.win_condition = MatchConfig.WinCondition.CAPTURE
	Net.update_config(fresh)
	_check("the host's config is Teams under capture", Net.config.mode, MatchConfig.Mode.TEAMS)
	var panel := load("res://scenes/ui/match_settings.tscn").instantiate() as MatchSettingsPanel
	add_child(panel)
	var section := panel.find_child("CaptureRules", true, false) as Control
	_check("the lobby has a capture rules section", section != null, true)
	if section != null:
		_check("shown under capture", section.visible, true)
	var return_row: Control = panel._fields["capture_return_time"]["row"]
	_check("with the return-time dial showing", return_row.visible, true)
	panel._push("mode", MatchConfig.Mode.FREE_FOR_ALL)
	_check("picking Free-for-all gives a free-for-all", Net.config.mode,
		MatchConfig.Mode.FREE_FOR_ALL)
	_check("on the kill limit", Net.config.win_condition, MatchConfig.WinCondition.KILL_LIMIT)
	if section != null:
		_check("and the capture section hides", section.visible, false)
	_check("and so does its dial", return_row.visible, false)
	panel.free()
	Net.update_config(MatchConfig.new())

	# The two dials travel.
	var host := MatchConfig.new()
	host.capture_return_time = 33.0
	host.capture_carrier_speed = 0.75
	var arrived := MatchConfig.new()
	arrived.apply_dict(host.to_dict())
	_check("the return time survives the trip", arrived.capture_return_time, 33.0)
	_check("the carrier speed survives the trip", arrived.capture_carrier_speed, 0.75)
	_check("both are in the replicated key list",
		host.to_dict().has("capture_return_time") and host.to_dict().has("capture_carrier_speed"),
		true)
	arrived.apply_dict({"capture_return_time": 9000.0, "capture_carrier_speed": 40.0})
	_check("an absurd return time is clamped", arrived.capture_return_time, 60.0)
	_check("an absurd carrier speed is clamped", arrived.capture_carrier_speed, 1.2)
	arrived.apply_dict({"capture_return_time": 0.0, "capture_carrier_speed": 0.0})
	_check("a zero return time is clamped", arrived.capture_return_time, 3.0)
	_check("a stationary carrier is clamped", arrived.capture_carrier_speed, 0.5)
	arrived.apply_dict({"win_condition": MatchConfig.WinCondition.CAPTURE + 1})
	_check("a condition past capture is clamped to it", arrived.win_condition,
		MatchConfig.WinCondition.CAPTURE)


func _run_config_validation() -> void:
	_scenario("config arriving off the wire")
	# `apply_dict` is the deserialiser for host-controlled match settings, so
	# everything it reads is attacker-controlled on a client. It is the one
	# place in this codebase where a hostile peer gets to set a value directly,
	# which is why it clamps rather than trusts — see the header of
	# match_config.gd for why a Dictionary crosses the wire and not a Resource.
	var config := MatchConfig.new()

	config.apply_dict({"kill_limit": 9999, "lives": -40, "team_count": 500})
	_check("an absurd kill limit is clamped", config.kill_limit, 50)
	_check("a negative life count is clamped", config.lives, 1)
	_check("team count is clamped", config.team_count, 8)

	# An out-of-range enum would index past the end of whatever switches on it.
	config.apply_dict({"mode": 9999, "win_condition": -3})
	_check("mode stays a real mode", config.mode, MatchConfig.Mode.TEAMS)
	_check("win condition stays real", config.win_condition,
		MatchConfig.WinCondition.KILL_LIMIT)

	# Wrong types are dropped, not coerced into nonsense.
	var before := config.spear_recharge
	config.apply_dict({"spear_recharge": "very fast", "friendly_fire": "yes"})
	_check("a string cannot become a float", config.spear_recharge, before)
	_check("a string cannot become a bool", config.friendly_fire, false)

	# Ints and floats are interchangeable often enough to be worth coercing.
	config.apply_dict({"spear_recharge": 4})
	_check("an int becomes a float", config.spear_recharge, 4.0)

	config.apply_dict({"not_a_field": 12, "kill_limit": 7})
	_check("unknown keys are ignored", config.kill_limit, 7)

	var kept := config.lives
	config.apply_dict({"kill_limit": 8})
	_check("missing keys keep their value", config.lives, kept)

	# A timed match with no clock would never end.
	config.apply_dict({"win_condition": MatchConfig.WinCondition.TIME_ONLY,
		"time_limit": 0})
	_check("a timed match gets a clock", config.time_limit > 0, true)

	# The map is the one field that is a *key into a table* rather than a number
	# with a range, and an id this build has never heard of would send
	# `arena.gd` looking for a scene that is not there, mid-`_ready`, with no
	# way to recover. So it clamps the same way everything else does.
	config.apply_dict({"map": "a map that does not exist"})
	_check("an unknown map falls back to the default", config.map,
		MapCatalog.DEFAULT)
	_check("and the default is a real map", MapCatalog.is_valid(config.map), true)
	config.apply_dict({"map": 7})
	_check("a number cannot become a map", config.map, MapCatalog.DEFAULT)
	for id: String in MapCatalog.ids():
		config.apply_dict({"map": id})
		_check("the catalog's own id '%s' survives" % id, config.map, id)

	# The Elder dials travel like everything else, and a field missing from
	# `_FIELDS` is a setting the host changes in the lobby and nobody else ever
	# sees — which is invisible until somebody wonders why the Elder is rarer on
	# their machine than on the host's, or why it lasted twice as long on theirs.
	config.apply_dict({"elder_drop_chance": 4.0, "lightning_cooldown": 0.0,
		"elder_duration": 900.0, "elder_speed_multiplier": 40.0,
		"elder_jump_multiplier": -2.0})
	_check("an impossible robe chance is clamped", config.elder_drop_chance, 1.0)
	_check("a zero lightning cooldown is clamped", config.lightning_cooldown, 0.2)
	_check("a match-long robe is clamped", config.elder_duration, 120.0)
	# A boost below 1.0 would make the Elder *slower* than everybody else, which
	# is not a setting anybody is asking for and is exactly what a hostile peer
	# would send to pin one in place.
	_check("an absurd speed boost is clamped", config.elder_speed_multiplier, 3.0)
	_check("a negative jump boost is clamped", config.elder_jump_multiplier, 1.0)
	# Zero is legal here, the way it is for the letter hold: it means the bolt
	# leaves on the frame of the click (D-040). A clamp that quietly raised it
	# would be a declared setting nobody could actually select.
	config.apply_dict({"lightning_delay": 0.0})
	_check("a zero lightning delay survives", config.lightning_delay, 0.0)
	config.apply_dict({"lightning_delay": 90.0})
	_check("and an absurd one is clamped", config.lightning_delay, 2.0)

	# The Elder's clip is sped up to put its own release on whatever the delay
	# says (D-040, D-064), and both directions of that arithmetic are asserted
	# here rather than left to be noticed as an arm that finishes after the bolt
	# has gone.
	_near("0.2 s of delay is a 2.58x cast",
		BogAnimator.cast_rate_for_release(0.2), BogAnimator.CAST_WINDOW / 0.2)
	_near("and that rate releases at 0.2 s again",
		BogAnimator.cast_release_for_rate(
			BogAnimator.cast_rate_for_release(0.2)), 0.2)
	# The two windups are two clips with two windows since D-064, and this is
	# the line that fails if one of them is ever quietly wired to the other's:
	# the cast's window is 0.516 s against the throw's 0.500, so a cast played
	# at the throw's rate lands 16 ms late and a throw played at the cast's
	# lands early, and nothing else in this file would notice either.
	_check("the two windups are not the same window",
		is_equal_approx(BogAnimator.CAST_WINDOW, BogAnimator.THROW_WINDOW), false)
	_near("the spear's own rate still releases at 0.50",
		BogAnimator.THROW_WINDOW / BogAnimator.THROW_RATE,
		BogAnimator.THROW_RELEASE_TIME)
	# The half second the user asked for, asserted against the literal rather
	# than against the constant it is derived from — which is the only way this
	# line can ever fail. `THROW_RELEASE_TIME` is `THROW_WINDOW / THROW_RATE` and
	# the rate is `THROW_WINDOW / THROW_RELEASE_TARGET`, so the two agree by
	# construction and will go on agreeing at any number at all; what this
	# catches is the day somebody pins the rate by hand and the promise quietly
	# stops being half a second. `tools/combat_range.gd`'s `release` mode is the
	# other half, and the half that measures rather than asserts.
	_near("and that is the half second the throw was asked for",
		BogAnimator.THROW_RELEASE_TIME, 0.5)
	# The setting that would otherwise be a division by zero.
	_near("a zero delay saturates rather than dividing by zero",
		BogAnimator.cast_rate_for_release(0.0), BogAnimator.CAST_RATE_MAX)
	_check("and the clip still plays at a finite rate",
		is_finite(BogAnimator.cast_rate_for_release(0.0)), true)
	# And what that ceiling *means*, which is the half of it that can rot: it is
	# 0.14 s of arm off the cast's own window, and the day somebody moves the
	# window without moving the floor this is the line that says the ceiling has
	# stopped meaning what its comment says (D-063's lesson, applied to the clip
	# that inherited the ceiling).
	_near("and the ceiling is still the floor it says it is",
		BogAnimator.cast_release_for_rate(BogAnimator.CAST_RATE_MAX),
		BogAnimator.CAST_RELEASE_MIN)

	# ------------------------------------------------------------- the bow ---
	#
	# All of the bow that does not need a world (D-065). The charge curve, the
	# two flights, the clamps, and the one number that used to be a constant and
	# is now derived from two lobby dials. `tools/combat_range.gd`'s `bow` mode
	# is the other half, and the half that measures rather than asserts.
	config.apply_dict({"bow_drop_snap": 0.0, "bow_draw_time": 90.0})
	# Not clamped to zero, and this is the one bow clamp with an argument rather
	# than a range behind it: `BogCombat.flat_band` divides by the drop, and a
	# drop of zero is a hitscan weapon with a flight time, which is not an arrow.
	_check("a weightless arrow is clamped off zero", config.bow_drop_snap, 0.5)
	_check("an absurd draw time is clamped", config.bow_draw_time, 4.0)

	var bow := MatchConfig.new()
	# The two ends of the charge are the dials themselves and nothing in
	# between, which is what makes the eight sliders mean what they say.
	_near("a snap shot does exactly the snap dial",
		ArrowProjectile.damage_for(0.0, bow), bow.bow_damage_snap)
	_near("a full draw does exactly the full dial",
		ArrowProjectile.damage_for(1.0, bow), bow.bow_damage_full)
	_near("a snap shot leaves at exactly the snap speed",
		ArrowProjectile.speed_for(0.0, bow), bow.bow_speed_snap)
	_near("a full draw leaves at exactly the full speed",
		ArrowProjectile.speed_for(1.0, bow), bow.bow_speed_full)
	_near("a snap shot falls at exactly the snap drop",
		ArrowProjectile.drop_for(0.0, bow), bow.bow_drop_snap)
	_near("a full draw falls at exactly the full drop",
		ArrowProjectile.drop_for(1.0, bow), bow.bow_drop_full)
	# Past the ends, both ways: a charge is clamped before it is interpolated,
	# so a client that claimed 3.0 and got past the host's own clamp would still
	# only ever buy a full draw.
	_near("an over-claimed draw is still only a full one",
		ArrowProjectile.damage_for(9.0, bow), bow.bow_damage_full)
	_near("and a negative one is still only a snap shot",
		ArrowProjectile.damage_for(-9.0, bow), bow.bow_damage_snap)

	# **Weighted toward the end of the draw**, which is the decision the curve
	# carries and the one thing about this weapon a linear lerp would quietly
	# undo. Asserted as the *shape* rather than as the exponent, so it goes on
	# meaning something if the exponent is ever re-derived: two thirds of the
	# way through a draw has to have bought under a third of the damage, and the
	# last third of the draw has to carry 1 - (2/3)^3 of it.
	var two_thirds := (ArrowProjectile.damage_for(2.0 / 3.0, bow) - bow.bow_damage_snap) \
		/ (bow.bow_damage_full - bow.bow_damage_snap)
	_check("two thirds of a draw is under a third of the damage",
		two_thirds < 0.34, true)
	_near("and the last third of it carries the rest",
		1.0 - two_thirds, 1.0 - pow(2.0 / 3.0, ArrowProjectile.DAMAGE_CURVE))

	# The re-derivation, and the proof that it is the same arithmetic it always
	# was: `BogCombat.LIGHTNING_RANGE` was a typed 28.0 whose comment derived it
	# from the spear, and `flat_band` is that comment. Asked of the spear's own
	# two constants it still comes out at 28, which is the line that fails if
	# anybody ever "tidies" `FLAT_BAND_DROP` into a Bog's collision height.
	_check("the spear's flat band is still the 28 m the Elder's range was",
		absf(BogCombat.flat_band(SpearProjectile.SPEED, SpearProjectile.DROP) - 28.0)
			< 0.05, true)
	# And what the re-derivation is *for*: a full draw is the flattest thing in
	# the game and a snap shot is the least flat, so the Elder's range now rises
	# to the top of the bow's band rather than sitting inside it.
	var spear_band := BogCombat.flat_band(SpearProjectile.SPEED, SpearProjectile.DROP)
	_check("a full draw is flatter than a spear",
		BogCombat.flat_band(bow.bow_speed_full, bow.bow_drop_full) > spear_band, true)
	_check("and a snap shot is not",
		BogCombat.flat_band(bow.bow_speed_snap, bow.bow_drop_snap) < spear_band, true)

	# Regression guard: magnet_fuse defaulted to 0.35 while its own range started
	# at 0.5, so every fresh config was silently raised and the declared default
	# was never the value anyone played with.
	var fresh := MatchConfig.new()
	var default_fuse := fresh.magnet_fuse
	fresh.apply_dict({})
	_check("every default survives its own clamp", fresh.magnet_fuse, default_fuse)

	# Whatever a host sets must arrive unchanged at the far end.
	var host := MatchConfig.new()
	host.mode = MatchConfig.Mode.TEAMS
	host.kill_limit = 23
	host.friendly_fire = true
	host.map_seed = 987654
	host.map = MapCatalog.ids()[MapCatalog.ids().size() - 1]
	host.magnet_radius = 12.5
	host.random_teams = true
	# All eight bow dials, because a field left out of `_FIELDS` is a setting
	# the host drags and nobody else ever sees — and eight of them arrived at
	# once (D-065). Every one is given a value nothing else in this file uses,
	# so a field that quietly fell back to its default is a failure and not a
	# coincidence.
	host.bow_draw_time = 1.35
	host.bow_recharge = 2.15
	host.bow_damage_snap = 17.0
	host.bow_damage_full = 71.0
	host.bow_speed_snap = 23.0
	host.bow_speed_full = 57.0
	host.bow_drop_snap = 13.5
	host.bow_drop_full = 6.5
	var arrived := MatchConfig.new()
	arrived.apply_dict(host.to_dict())
	_check("mode survives the trip", arrived.mode, host.mode)
	_check("kill limit survives", arrived.kill_limit, host.kill_limit)
	_check("friendly fire survives", arrived.friendly_fire, host.friendly_fire)
	_check("the map seed survives", arrived.map_seed, host.map_seed)
	# The host picks the map in the lobby, so it has to reach every client the
	# same way the seed does — the whole roster is looking at one arena.
	_check("the map survives", arrived.map, host.map)
	_check("and the map is in the replicated key list",
		host.to_dict().has("map"), true)
	_check("floats survive", arrived.magnet_radius, host.magnet_radius)
	for field: String in ["bow_draw_time", "bow_recharge", "bow_damage_snap",
			"bow_damage_full", "bow_speed_snap", "bow_speed_full",
			"bow_drop_snap", "bow_drop_full"]:
		_check("%s survives the trip" % field, arrived.get(field), host.get(field))
		_check("and %s is in the replicated key list" % field,
			host.to_dict().has(field), true)
	# A lobby toggle left out of `_FIELDS` is one the host sees and nobody else
	# does: every client's picker would stay live while the host dealt anyway.
	_check("random teams survives", arrived.random_teams, true)
	_check("and it is in the replicated key list",
		host.to_dict().has("random_teams"), true)
	config.apply_dict({"random_teams": "yes"})
	_check("a string cannot become random teams", config.random_teams, false)

	var copy := host.duplicate_config()
	_check("duplicate_config matches", copy.to_dict(), host.to_dict())
