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
## earning one, or that the last Gub standing wins — those live entirely in
## `MatchState` and, until this existed, had never been run with more than one
## live player. Every scenario drives the same host-side API a real match drives
## (`report_kill`, the clock, the respawn tick), so a rule that passes here is a
## rule that works in a match.
##
## Gubs are deliberately never spawned. These scenarios are about the
## bookkeeping, so the arena is registered with an empty spawn list and
## `_create_gub` is left to fail quietly for peers that do not exist.

const PEERS := [1, 901, 902, 903]

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	print("match_rules: starting")
	_run_kill_limit()
	_run_friendly_fire_off()
	_run_friendly_fire_on()
	_run_team_kill_limit()
	_run_lives_elimination()
	_run_time_limit()
	_run_void_credit()
	_run_spawn_protection()
	_run_config_validation()

	print("match_rules: %d checks, %d failures" % [_checks, _failures])
	print("match_rules: %s" % ("PASS" if _failures == 0 else "FAIL"))
	# Free the Gubs the scenarios spawned before quitting: Godot reports
	# anything still in the tree at exit as a leak, and a harness that prints
	# PASS above a wall of warnings teaches people to ignore warnings.
	# queue_free lands at the end of a frame and the corpses and spears take
	# another to unwind, hence the wait.
	#
	# A dozen or so still get reported and always will — they are the `preload`
	# constants on the item and audio scripts, which are alive for as long as
	# the scripts are. Nothing here can release those, so the count never quite
	# reaches zero.
	MatchState.reset()
	for i in 4:
		await get_tree().process_frame
	get_tree().quit(1 if _failures > 0 else 0)


# ------------------------------------------------------------------ harness ---

## Put `Net` and `MatchState` into a running match with `count` fake players.
## Teams are assigned round-robin, so team scenarios get two of each.
func _begin(count: int, configure: Callable) -> void:
	MatchState.reset()
	Net.start_offline()
	Net.players.clear()
	for i in count:
		Net.players[PEERS[i]] = {
			"name": "P%d" % i, "team": i % 2, "ready": true,
		}
	Net.roster_changed.emit()
	# Every scenario starts from a clean, fast config. Spawn protection in
	# particular has to be switched off explicitly: it defaults to two seconds,
	# these scenarios run in microseconds, and a protected Gub correctly refuses
	# to die — which looked exactly like the scoring being broken the first time
	# this harness was run. `_run_spawn_protection` turns it back on deliberately.
	Net.config.spawn_protection = 0.0
	Net.config.warmup_time = 0.0
	Net.config.respawn_delay = 0.0
	configure.call(Net.config)
	# Registering the arena is what starts a match.
	MatchState.register_arena(self, [] as Array[Transform3D])
	# Warmup is skipped rather than waited out: these scenarios are about the
	# rules, not the countdown.
	MatchState.phase = MatchState.Phase.PLAYING


func _kill(victim: int, killer: int) -> void:
	MatchState.report_kill(victim, killer, Gub.Cause.SPEAR,
		Vector3.ZERO, Vector3.FORWARD, "Spine1")


## Bring a dead player back without needing a Gub or a respawn timer.
func _revive(peer_id: int) -> void:
	MatchState.stats[peer_id]["alive"] = true
	MatchState.stats[peer_id]["respawn_at"] = 0.0


func _check(what: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got == want:
		return
	_failures += 1
	print("  FAIL  %s: got %s, wanted %s" % [what, str(got), str(want)])


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


## Is this Gub actually wearing the cloth, as opposed to merely being listed as
## the Elder? Two claims, and the interesting bug is the one where they
## disagree — a Gub that is the Elder in the rules and a plain Gub on screen is
## the worst outcome available, because the robe is the only warning anyone gets.
func _wearing_robe(peer_id: int) -> bool:
	var gub: Gub = MatchState.gubs.get(peer_id)
	if not is_instance_valid(gub) or gub.elder_robe == null:
		return false
	return gub.elder_robe.is_worn()


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


## A Gub's combat node and its hand, or null if that Gub never got one.
##
## Every other scenario here is pure bookkeeping and touches neither. The hold
## needs both, because "you cannot throw, and the card is in the hand where the
## spear was" is half the mechanic and it lives on the Gub — and the half most
## likely to rot, since a hand driven by anything other than `has_spear()` looks
## right until the frame it does not (D-035).
func _combat(peer_id: int) -> GubCombat:
	var gub: Gub = MatchState.gubs.get(peer_id)
	if not is_instance_valid(gub):
		return null
	return gub.get_node_or_null("Combat") as GubCombat


func _hand(peer_id: int) -> HeldSpear:
	var gub: Gub = MatchState.gubs.get(peer_id)
	return gub.held_spear if is_instance_valid(gub) else null


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
	_scenario("lives, last Gub standing")
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
	_scenario("free-for-all, collect G·U·B")
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

	# The one thing on a stats row a death does not touch. Everything a Gub was
	# carrying goes; the letters stay.
	_kill(901, 902)
	_check("letters survive a death", MatchState.letter_count(901), 1)
	_revive(901)

	MatchState.award_letter(901, MatchState.LETTER_U)
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


func _run_team_letters() -> void:
	_scenario("teams, letters do not pool")
	var finished := {}
	# `_begin` assigns teams round-robin over PEERS, so 1 and 902 are team 0.
	_begin(4, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.TEAMS
		c.team_count = 2
		c.win_condition = MatchConfig.WinCondition.LETTERS
		c.kill_limit = 50
		c.time_limit = 0)
	MatchState.match_finished.connect(func(s: Dictionary) -> void:
		finished.merge(s, true), CONNECT_ONE_SHOT)

	# G in one team-mate's hand, U and B in the other's. Between them team 0
	# holds all three and has won nothing: the card game's ending is one hand
	# with the whole word in it, and pooling would make a four-player team a
	# near-certainty against a two-player one.
	MatchState.award_letter(1, MatchState.LETTER_G)
	MatchState.award_letter(902, MatchState.LETTER_U)
	MatchState.award_letter(902, MatchState.LETTER_B)
	_check("a team holding all three between them has not won",
		MatchState.phase, MatchState.Phase.PLAYING)

	MatchState.award_letter(902, MatchState.LETTER_G)
	_check("one hand with all three ends it",
		MatchState.phase, MatchState.Phase.POST_MATCH)
	_check("reason", finished.get("reason"), "letters")
	_check("the collector leads", _leader(finished), 902)
	_check("their team-mate kept their own letter",
		MatchState.letters_for(1), MatchState.LETTER_G)


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
	_check("the Gub is holding it up", MatchState.is_holding_letter(901), true)
	_check("and it is the letter that was on the card",
		MatchState.letter_hold_letter(901), MatchState.LETTER_G)
	_check("with the clock running",
		MatchState.letter_hold_remaining(901) > 9.0, true)

	# The hand and the gate, which are not allowed to disagree. Both read
	# `has_spear()`, so a Gub that looks armed is armed and one holding a card
	# is not — that is the whole tell the mechanic is built on.
	var combat := _combat(901)
	var hand := _hand(901)
	_check("the Gub has a combat node", combat != null, true)
	_check("and a hand to put the card in", hand != null, true)
	if combat != null and hand != null:
		_check("no spear while holding", combat.has_spear(), false)
		_check("the shaft leaves the hand", hand.is_carried(), false)
		_check("and the card is in it", hand.has_letter(), true)

	# One hold at a time. A second card is not consumed, not queued, and not
	# refused to anybody else — it is simply still there.
	var second := _drop_card(MatchState.LETTER_U)
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
	# side. 902 is still holding U.
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
		_newest_card_letter(), MatchState.LETTER_U)
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
	var instant := _drop_card(MatchState.LETTER_U)
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
	MatchState.award_letter(1, MatchState.LETTER_U)
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

	# The robe is a drop like any other: it lies there and the first living Gub
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
		Pickup.Kind.MUSHROOM, 0, Vector3.ZERO), 901)
	if combat != null:
		_check("an Elder still picks up mushrooms", combat.mushroom_count(), 1)

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

	# **The boosts** (D-040). Read off `Gub` rather than off the config, because
	# the thing worth checking is that the multiplier reached the one point every
	# stance comes out of — a boost applied to `RUN_SPEED` alone is a walking
	# Elder that moves at exactly everybody else's pace, and the difference
	# between those two bugs and no bug at all is invisible from the dial.
	var body: Gub = MatchState.gubs.get(901)
	if body != null:
		_near("the Elder walks faster", body.target_speed(),
			Gub.WALK_SPEED * Net.config.elder_speed_multiplier)
		body.wants_sprint = true
		_near("and sprints faster by the same factor", body.target_speed(),
			Gub.RUN_SPEED * Net.config.elder_speed_multiplier)
		body.wants_sprint = false
		_near("and jumps harder", body.jump_velocity(),
			Gub.JUMP_VELOCITY * Net.config.elder_jump_multiplier)
	# The apex, which is the number that actually decides whether a boost puts a
	# player somewhere a map did not plan for — and it is not the number on the
	# slider, because height goes as the square of launch velocity. Pinned here
	# rather than left in a comment: the shipping 1.25 is +56% of height, and
	# that is the fact anybody retuning this dial has to be handed.
	_near("a plain jump tops out at 1.69 m",
		snappedf(Gub.apex_for(Gub.JUMP_VELOCITY), 0.01), 1.69)
	_near("the shipping 1.25x boost tops out at 2.64",
		snappedf(Gub.apex_for(Gub.JUMP_VELOCITY * 1.25), 0.01), 2.64)

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

	# **Expiry is not a death.** Everything the Gub had before the robe is still
	# there after it: the letter it earned mid-scenario and the mushroom it
	# picked up. That is the half of this most likely to rot, because the
	# obvious way to write the teardown is to reuse the death path.
	var pickups := MatchState._pickups.size()
	var letters_before := MatchState.letters_for(901)
	var stock_before := combat.mushroom_count() if combat != null else -1
	_expire_elder(901)
	_check("the robe burns out on its own", MatchState.is_elder(901), false)
	_check("and comes off the body", _wearing_robe(901), false)
	_check("and puts nothing back on the ground",
		MatchState._pickups.size(), pickups)
	_check("expiry is not a death", MatchState.is_alive(901), true)
	_check("it keeps its letters", MatchState.letters_for(901), letters_before)
	if combat != null and hand != null:
		_check("and its carried stock", combat.mushroom_count(), stock_before)
		_check("the spear comes back", combat.has_spear(), true)
		_check("and the bolt is gone", combat.has_lightning(), false)
		_check("with the shaft back in the fist", hand.is_carried(), true)
	if body != null:
		_near("and it moves like a Gub again", body.target_speed(), Gub.WALK_SPEED)
		_near("and jumps like one", body.jump_velocity(), Gub.JUMP_VELOCITY)

	# **The void still kills, and it is the only thing that does.** Spawn
	# protection carves the same hole for the same reason: a Gub that cannot die
	# to the void falls past the bottom of the island for ever, alive and
	# unreachable. Without this the invincibility above is a soft-lock waiting
	# for somebody to walk off a ledge.
	MatchState.claim_pickup(_drop_robe(), 901)
	_check("a second robe is claimable", MatchState.is_elder(901), true)
	MatchState.report_kill(901, 901, Gub.Cause.VOID, Vector3.ZERO, Vector3.DOWN, "")
	_check("the void kills an Elder", MatchState.is_alive(901), false)
	_check("and takes the robe with it", MatchState.is_elder(901), false)
	_check("and off the body", _wearing_robe(901), false)

	_revive(901)
	MatchState._do_respawn(901, Transform3D.IDENTITY)
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
	MatchState.report_kill(901, 901, Gub.Cause.VOID, Vector3.ZERO, Vector3.DOWN, "")
	_check("a fall costs a death", MatchState.deaths(901), 1)
	_check("and pays nobody", MatchState.kills(901), 0)
	_revive(901)

	# Lured off the edge: `note_attack` is what carries the credit across.
	MatchState.note_attack(901, 902)
	MatchState.report_kill(901, 902, Gub.Cause.VOID, Vector3.ZERO, Vector3.DOWN, "")
	_check("the lurer is credited", MatchState.kills(902), 1)


func _run_spawn_protection() -> void:
	_scenario("spawn protection")
	_begin(3, func(c: MatchConfig) -> void:
		c.mode = MatchConfig.Mode.FREE_FOR_ALL
		c.win_condition = MatchConfig.WinCondition.KILL_LIMIT
		c.kill_limit = 50
		c.time_limit = 0
		c.spawn_protection = 5.0)

	# A Gub that has just spawned is solid but unkillable, so spawning face to
	# face with someone holding a spear is survivable.
	var victim: Gub = MatchState.gubs.get(901)
	_check("a Gub exists to protect", is_instance_valid(victim), true)
	_check("and starts protected", victim.is_invulnerable(), true)
	_kill(901, 1)
	_check("a spear cannot kill it", MatchState.is_alive(901), true)
	_check("and earns nothing", MatchState.kills(1), 0)

	# Falling off the island is not something protection should save you from,
	# or a protected Gub could sit in the void forever.
	MatchState.report_kill(901, 901, Gub.Cause.VOID, Vector3.ZERO, Vector3.DOWN, "")
	_check("but the void still takes it", MatchState.is_alive(901), false)

	# Once protection lapses the same spear lands.
	_revive(901)
	victim.invulnerable_until = 0.0
	_kill(901, 1)
	_check("and it dies once protection lapses", MatchState.is_alive(901), false)
	_check("paying the killer", MatchState.kills(1), 1)


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

	# Regression guard: lure_fuse defaulted to 0.35 while its own range started
	# at 0.5, so every fresh config was silently raised and the declared default
	# was never the value anyone played with.
	var fresh := MatchConfig.new()
	var default_fuse := fresh.lure_fuse
	fresh.apply_dict({})
	_check("every default survives its own clamp", fresh.lure_fuse, default_fuse)

	# Whatever a host sets must arrive unchanged at the far end.
	var host := MatchConfig.new()
	host.mode = MatchConfig.Mode.TEAMS
	host.kill_limit = 23
	host.friendly_fire = true
	host.map_seed = 987654
	host.map = MapCatalog.ids()[MapCatalog.ids().size() - 1]
	host.lure_radius = 12.5
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
	_check("floats survive", arrived.lure_radius, host.lure_radius)

	var copy := host.duplicate_config()
	_check("duplicate_config matches", copy.to_dict(), host.to_dict())
