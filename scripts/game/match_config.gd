class_name MatchConfig
extends Resource
## Everything about a match that the host can dial in from the lobby.
##
## The host owns the authoritative copy. It is pushed to clients as a plain
## Dictionary (see `to_dict`/`apply_dict`) rather than as a Resource, because
## sending Resources over RPC means allowing object decoding on the wire — an
## easy way to hand a malicious peer arbitrary object construction. A flat
## dictionary of primitives, validated on arrival, has no such hole.

enum Mode {
	FREE_FOR_ALL,
	TEAMS,
}

## Appended to, never reordered. The ordinal is what travels in `to_dict`, so
## inserting a condition in the middle would silently turn every older peer's
## "last Gub standing" into something else.
enum WinCondition {
	KILL_LIMIT,   ## first to N kills
	LIVES,        ## last Gub (or team) standing
	TIME_ONLY,    ## highest score when the clock runs out
	LETTERS,      ## first to hold G, U and B — the Gubs card game's own ending
	CAPTURE,      ## capture the flag with the three letters: carry each home (D-051)
}

const MIN_PLAYERS := 1
const MAX_PLAYERS := 8
const TEAM_NONE := -1

@export var mode: Mode = Mode.FREE_FOR_ALL
@export var win_condition: WinCondition = WinCondition.KILL_LIMIT
@export_range(1, 8) var team_count: int = 2

## Scoring limits. Only the one matching `win_condition` is enforced, but all
## are kept so toggling the condition in the lobby does not lose your settings.
@export_range(1, 50) var kill_limit: int = 15
@export_range(1, 15) var lives: int = 3
## Seconds. Zero means no time limit (invalid for TIME_ONLY).
@export_range(0, 3600) var time_limit: int = 600

@export var friendly_fire: bool = false

## Teams mode only. When set, nobody picks a team: the host shuffles the roster
## and deals it round-robin across `team_count` the moment Start is pressed, so
## no two teams differ by more than one Gub (D-048). Teams are dealt by
## `Net.request_match_start` and nowhere else — a rematch keeps the teams that
## were dealt, and only a fresh start from the lobby deals again.
@export var random_teams: bool = false
@export_range(0.0, 10.0) var respawn_delay: float = 3.0
@export_range(0.0, 10.0) var spawn_protection: float = 2.0
@export_range(0.0, 30.0) var warmup_time: float = 5.0

## Spears are the only weapon and always instant-kill, so the recharge time is
## the single most important balance dial in the game: it sets how often a Gub
## can commit to an attack, and therefore how punishing a miss is.
@export_range(0.5, 15.0) var spear_recharge: float = 3.0

## Not a cooldown, and deliberately not named like one. Mushrooms and lures are
## carried stock now (D-032) — there is nothing to recharge, so this is only a
## floor on how fast a stack can be spent. Without it a Gub who has just walked
## over four mushroom drops empties all four into the same square metre on one
## frame, which is neither cover nor a decision.
@export_range(0.1, 10.0) var mushroom_use_delay: float = 1.5
@export_range(2.0, 120.0) var mushroom_lifetime: float = 25.0
@export_range(1, 5) var mushroom_max_active: int = 2

@export_range(0.1, 10.0) var lure_use_delay: float = 2.0
@export_range(2.0, 25.0) var lure_radius: float = 9.0
@export_range(0.2, 5.0) var lure_hold: float = 1.4
@export_range(1.0, 60.0) var lure_pull_strength: float = 18.0
## The delay between the lure landing and the pull firing — the window in which
## seeing it land is worth anything. This defaulted to 0.35 while its own range
## started at 0.5, so `_clamp_all` silently raised every fresh config to 0.5 and
## the declared default was never the value anyone actually played with. The
## range wins: half a second is already a short fuse.
@export_range(0.5, 5.0) var lure_fuse: float = 0.5

## How often a death drops a letter card instead of an ability, in the letters
## win condition only. Everything else that falls out of a corpse is a mushroom
## or a lure, split evenly.
##
## A lobby dial rather than a constant, because the honest arithmetic says this
## default is probably too stingy and nobody should need a rebuild to find out.
## Duplicates are wasted (D-033), so collecting three distinct letters is the
## coupon-collector problem: 3·(1 + 1/2 + 1/3) ≈ 5.5 cards *into one pair of
## hands*, and in a contested lobby most cards land in someone else's. At 0.08
## that is hundreds of deaths. The number the user asked for is the number that
## ships; the slider is how it gets corrected in five seconds instead of a
## release.
@export_range(0.0, 1.0) var letter_drop_chance: float = 0.08

## How long a Gub has to hold a letter card up before the letter is actually
## theirs. Touching the card starts the hold; finishing it is what scores
## (D-035).
##
## This is the whole tension of the letters mode and it is a dial rather than a
## constant for the same reason `letter_drop_chance` is: ten seconds standing
## still in the open is a long time, and the first real lobby is the only thing
## that can say whether it is too long.
##
## **Zero is legal and means "grant it on touch"** — the mode without the hold,
## which is what it was before, and the setting to reach for if the hold turns
## out to be miserable. It is taken as a special case rather than as a hold that
## expires immediately, because a one-frame hold is one frame with the spear out
## of the hand: a visible flicker for a setting whose entire point is that there
## is nothing to see.
@export_range(0.0, 30.0) var letter_hold_time: float = 10.0

## **Capture G·U·B** (D-051): how long a letter dropped by a dead carrier lies
## where it fell before it goes home to its spawn. Anyone may pick it up in that
## time, the carrier's own team included.
##
## A dial because it is the one number that decides what a kill on a carrier is
## worth. Short, and killing a carrier near your base is a full reset; long, and
## a card dropped in no man's land becomes the fight. Fifteen seconds is a little
## more than a respawn plus a sprint back, so the dead carrier's team has a real
## chance to recover it.
@export_range(3.0, 60.0) var capture_return_time: float = 15.0

## What a Gub carrying a letter in Capture G·U·B multiplies its ground speed by.
## Below one on purpose: a carrier who outruns everybody to their base is a
## carrier nobody gets to fight. Applied at `Gub.target_speed`, the same single
## point the Elder's boost is, so the two multiply rather than one hiding the
## other.
@export_range(0.5, 1.2) var capture_carrier_speed: float = 0.9

## How often a death drops the Elder's robe, **in every mode**.
##
## Unlike `letter_drop_chance` above, this is not gated on a win condition. The
## Elder is not a scoring mechanic — it is a weapon, and a weapon that only
## exists in one of four modes is a weapon nobody learns. So the robe rolls out
## of the same corpse in a kill-limit match as in a letters one (D-038).
##
## Rarer than either ability by a wide margin, because it is strictly stronger
## than anything else that drops: 2% of deaths against the mushroom and lure's
## ~49% each. In a ten-minute free-for-all that is one or two robes, which is
## the intent — an Elder should be an event, not a phase everyone passes
## through.
##
## **It was 5% and came down to meet what the Elder became** (D-040). Five per
## cent was set for an Elder that was a modest upgrade held until somebody
## killed you: a stronger weapon, on a five-second recharge, that died like
## anything else. What the dial now hands out is twenty seconds during which a
## Gub cannot be killed at all, moves a third faster, and fires a one-shot
## weapon about once a second. Arriving several times a match, that is not an
## event; it is the match. The user has been told this happened and the slider
## is right here if they want it back.
@export_range(0.0, 1.0) var elder_drop_chance: float = 0.02

## How long after the click the Elder's bolt actually leaves the hand.
##
## The user, having played it: *"There should be basically no delay for the
## lightning, right when you press then it should shoot maybe .2 seconds
## after."* **This supersedes the release-time half of D-038**, which fired the
## bolt at the `Throw` clip's own 0.71 s release because the same clip was being
## reused. The clip stays; it is played faster to meet this number instead —
## `GubAnimator.throw_rate_for_release` derives the rate, so the arm and the
## bolt cannot drift apart (D-040).
##
## **Zero is legal and means "on the frame of the click"**, which is why the
## range starts there rather than at something safely small. The clip still
## plays, at `GubAnimator.THROW_RATE_MAX`, and the bolt leads the hand by about
## a seventh of a second — which at that setting is precisely what was asked
## for.
@export_range(0.0, 2.0) var lightning_delay: float = 0.2

## The Elder's recharge.
##
## **Was 5.0, and the argument for it is superseded** (D-040). D-038 charged the
## bolt a long wait because it is hitscan and cannot be dodged, and that is
## still true — but the Elder is no longer a weapon somebody carries until they
## die. It is a twenty-second window, and a window that fires four times is a
## different thing from one that fires twenty. The user: *"it should recharge
## faster, way faster."* At 1.0 the tile blinks rather than sweeps, which D-036
## says is fine and honest.
##
## The floor is 0.2 rather than 0.5 because the delay above can be set to zero:
## at 0.2 a bolt a second is five bolts a second, which is the fastest this
## weapon can be made and is a setting the lobby is allowed to try.
@export_range(0.2, 10.0) var lightning_cooldown: float = 1.0

## How far from where the bolt lands it still kills, in metres, measured to the
## surface of a Gub's collision capsule (D-053).
##
## The user: *"the lightning should have an aoe (small blast radius) so that if
## you hit pretty close it still hits them, this should still be a one shot
## kill, but not too far."* So it is a hard edge with no falloff — inside it is
## the same kill a direct hit is, outside it is nothing — and 1.5 m is about two
## Gub-widths of forgiveness either side of the body, which forgives a bolt into
## the ground at somebody's feet and does not forgive one into the next room.
## The blast needs a clear line from the impact to the body, so a wall or a
## shield mushroom is still cover; it only exists where the bolt hit something;
## and it goes through `report_kill` like every other death, so an Elder is
## warded against it exactly as against a direct hit (D-040).
##
## **Zero is legal** and is the bolt as it was before: a direct hit or nothing.
@export_range(0.0, 4.0) var lightning_radius: float = 1.5

## How long the robe lasts before it burns out, in seconds.
##
## **This supersedes D-038's "the Elder lasts until it dies".** With
## invincibility, death is no longer the exit — a Gub that cannot be killed and
## is the Elder until it is killed is the Elder for the rest of the match. So
## the clock is the exit, it is owned by the host exactly as a letter hold is,
## and when it runs out the robe is consumed, the model reverts and the Gub is
## ordinary again.
##
## Expiry is **not** a death: the letters and the carried mushrooms and lures a
## Gub had before the robe are still there afterwards. Nothing about the twenty
## seconds is meant to cost you what you already had.
@export_range(1.0, 120.0) var elder_duration: float = 20.0

## What the Elder multiplies `Gub.RUN_SPEED`, `WALK_SPEED` and `CROUCH_SPEED` by.
##
## A multiplier on the existing constants rather than a second set of speeds, so
## there is still exactly one place that says how fast a Gub moves and the
## Elder is a factor applied to it. It is applied at `Gub.target_speed()`, which
## is the single point every stance already comes out of — walking, sprinting
## and crouching all scale together and none of them can be forgotten.
@export_range(1.0, 3.0) var elder_speed_multiplier: float = 1.35

## What the Elder multiplies `Gub.JUMP_VELOCITY` by.
##
## **It is a multiplier on launch velocity, and height goes as its square.** At
## 1.25 the jump apex goes from 1.69 m to 2.64 m — 56% higher, not 25% — and a
## dive off the top of one reaches 3.25 m instead of 2.30 m. That is deliberately
## recorded here rather than left for somebody to rediscover, because it is the
## dial on this whole feature most likely to put a player somewhere a map did
## not plan for, and the number that matters is not the one on the slider.
@export_range(1.0, 3.0) var elder_jump_multiplier: float = 1.25

@export_range(MIN_PLAYERS, MAX_PLAYERS) var max_players: int = MAX_PLAYERS

## Which map the match is played on: an id from `MapCatalog`, not a scene path,
## so a config that names a map this build has never heard of is a value to
## sanitise rather than a `load()` of whatever a peer sent. It travels with the
## roster exactly as `map_seed` does, because every peer has to know which map
## it is building before `arena.tscn` loads.
@export var map: String = MapCatalog.DEFAULT

## Seed for the island generator. Every client builds the map from this, so it
## must be identical everywhere — it is replicated with the rest of the config.
## Only means anything for a procedural map; a static one ignores it.
@export var map_seed: int = 20260904


const _FIELDS := [
	"mode", "win_condition", "team_count", "kill_limit", "lives", "time_limit",
	"friendly_fire", "random_teams", "respawn_delay", "spawn_protection", "warmup_time",
	"spear_recharge", "mushroom_use_delay", "mushroom_lifetime", "mushroom_max_active",
	"lure_use_delay", "lure_radius", "lure_hold", "lure_pull_strength", "lure_fuse",
	"letter_drop_chance", "letter_hold_time",
	"capture_return_time", "capture_carrier_speed",
	"elder_drop_chance", "lightning_delay", "lightning_cooldown", "lightning_radius",
	"elder_duration", "elder_speed_multiplier", "elder_jump_multiplier",
	"max_players", "map", "map_seed",
]


func to_dict() -> Dictionary:
	var out := {}
	for field: String in _FIELDS:
		out[field] = get(field)
	return out


## Copy values in from an untrusted dictionary, clamped to the ranges declared
## above. Unknown keys are ignored and missing keys keep their current value.
func apply_dict(data: Dictionary) -> void:
	for field: String in _FIELDS:
		if not data.has(field):
			continue
		var incoming: Variant = data[field]
		var current: Variant = get(field)
		if typeof(incoming) != typeof(current):
			# Ints and floats are interchangeable often enough to be worth coercing.
			if typeof(current) == TYPE_FLOAT and typeof(incoming) == TYPE_INT:
				incoming = float(incoming)
			elif typeof(current) == TYPE_INT and typeof(incoming) == TYPE_FLOAT:
				incoming = int(incoming)
			else:
				continue
		set(field, incoming)
	_clamp_all()


func duplicate_config() -> MatchConfig:
	var copy := MatchConfig.new()
	copy.apply_dict(to_dict())
	return copy


func _clamp_all() -> void:
	mode = clampi(mode, 0, Mode.size() - 1) as Mode
	win_condition = clampi(win_condition, 0, WinCondition.size() - 1) as WinCondition
	team_count = clampi(team_count, 2, 8)
	kill_limit = clampi(kill_limit, 1, 50)
	lives = clampi(lives, 1, 15)
	time_limit = clampi(time_limit, 0, 3600)
	respawn_delay = clampf(respawn_delay, 0.0, 10.0)
	spawn_protection = clampf(spawn_protection, 0.0, 10.0)
	warmup_time = clampf(warmup_time, 0.0, 30.0)
	spear_recharge = clampf(spear_recharge, 0.5, 15.0)
	mushroom_use_delay = clampf(mushroom_use_delay, 0.1, 10.0)
	mushroom_lifetime = clampf(mushroom_lifetime, 2.0, 120.0)
	mushroom_max_active = clampi(mushroom_max_active, 1, 5)
	lure_use_delay = clampf(lure_use_delay, 0.1, 10.0)
	lure_radius = clampf(lure_radius, 2.0, 25.0)
	lure_hold = clampf(lure_hold, 0.2, 5.0)
	lure_pull_strength = clampf(lure_pull_strength, 1.0, 60.0)
	lure_fuse = clampf(lure_fuse, 0.5, 5.0)
	letter_drop_chance = clampf(letter_drop_chance, 0.0, 1.0)
	# Zero survives this on purpose — it is the "grant on touch" setting, not a
	# value to be raised into a hold nobody asked for.
	letter_hold_time = clampf(letter_hold_time, 0.0, 30.0)
	capture_return_time = clampf(capture_return_time, 3.0, 60.0)
	capture_carrier_speed = clampf(capture_carrier_speed, 0.5, 1.2)
	elder_drop_chance = clampf(elder_drop_chance, 0.0, 1.0)
	# Zero survives this on purpose, like `letter_hold_time` above: it is the
	# "fires on the frame of the click" setting, not a slider dragged off the
	# end of its range.
	lightning_delay = clampf(lightning_delay, 0.0, 2.0)
	lightning_cooldown = clampf(lightning_cooldown, 0.2, 10.0)
	lightning_radius = clampf(lightning_radius, 0.0, 4.0)
	elder_duration = clampf(elder_duration, 1.0, 120.0)
	elder_speed_multiplier = clampf(elder_speed_multiplier, 1.0, 3.0)
	elder_jump_multiplier = clampf(elder_jump_multiplier, 1.0, 3.0)
	max_players = clampi(max_players, MIN_PLAYERS, MAX_PLAYERS)
	# An id nobody recognises is either a peer from a build that has a map this
	# one does not, or garbage. Both want the same answer: the map every build
	# has. Anything else means `arena.gd` reaching for a scene that is not there,
	# mid-`_ready`, with no way to recover.
	if not MapCatalog.is_valid(map):
		map = MapCatalog.DEFAULT
	# Capture G·U·B is a Teams mode by nature: a base belongs to a team, and a
	# free-for-all has eight people and no bases (D-051). Forced here rather
	# than refused, so every path into a config — the lobby, a peer's
	# dictionary, a harness — comes out playable. The lobby does the reverse
	# half itself: picking Free-for-all while this is selected moves the
	# condition back to the kill limit (`MatchSettingsPanel._push`).
	if win_condition == WinCondition.CAPTURE:
		mode = Mode.TEAMS
	# TIME_ONLY with no clock would never end.
	if win_condition == WinCondition.TIME_ONLY and time_limit <= 0:
		time_limit = 600


## Whether a win condition is scored in G·U·B letters — the lamps, the letters
## column and the letter-first ranking. True for both letter modes, which differ
## in how a letter is *earned* (a hold, or a carry home) and not in what it
## counts toward. The loot roll deliberately does not ask this: only LETTERS
## drops cards out of corpses (D-051).
static func scores_letters(condition: int) -> bool:
	return condition == WinCondition.LETTERS or condition == WinCondition.CAPTURE


## Human-readable one-liner for the lobby header.
func summary() -> String:
	var parts: Array[String] = []
	parts.append("Free-for-all" if mode == Mode.FREE_FOR_ALL else "%d Teams" % team_count)
	match win_condition:
		WinCondition.KILL_LIMIT:
			parts.append("%d kills" % kill_limit)
		WinCondition.LIVES:
			parts.append("%d lives" % lives)
		WinCondition.TIME_ONLY:
			parts.append("timed")
		WinCondition.LETTERS:
			parts.append("Collect G·U·B")
		WinCondition.CAPTURE:
			parts.append("Capture G·U·B")
	if time_limit > 0:
		parts.append("%d:%02d" % [time_limit / 60, time_limit % 60])
	if mode == Mode.TEAMS and random_teams:
		parts.append("random teams")
	if mode == Mode.TEAMS and friendly_fire:
		parts.append("friendly fire")
	return "  ·  ".join(parts)
