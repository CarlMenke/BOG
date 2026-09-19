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
## "last Bog standing" into something else.
enum WinCondition {
	KILL_LIMIT,   ## first to N kills
	LIVES,        ## last Bog (or team) standing
	TIME_ONLY,    ## highest score when the clock runs out
	LETTERS,      ## first to hold B, O and G — one hand, the way the card game ends
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
## no two teams differ by more than one Bog (D-048). Teams are dealt by
## `Net.request_match_start` and nowhere else — a rematch keeps the teams that
## were dealt, and only a fresh start from the lobby deals again.
@export var random_teams: bool = false
@export_range(0.0, 10.0) var respawn_delay: float = 3.0
@export_range(0.0, 10.0) var spawn_protection: float = 2.0
@export_range(0.0, 30.0) var warmup_time: float = 5.0

## Spears are the only weapon and always instant-kill, so the recharge time is
## the single most important balance dial in the game: it sets how often a Bog
## can commit to an attack, and therefore how punishing a miss is.
@export_range(0.5, 15.0) var spear_recharge: float = 3.0

# ------------------------------------------------------------------- the bow ---
#
# The first damage dials in the game (D-062 said the bow would bring them, and
# said why there is still no `starting_health` beside them: 100 is the unit
# these are written in, not a setting).
#
# Eight of them, in four pairs, and every pair is the same pair — what a snap
# shot does and what a full draw does. Everything between is the charge, and
# **nothing between is a dial**, because the shape of the curve is a design
# decision with an argument behind it and the ends are balance. See
# `ArrowProjectile` for the two interpolations and why one of them is not
# linear.

## How long the string takes to come all the way back.
##
## The whole of what a full draw *costs*, and therefore the number that decides
## whether the bow is a sniper rifle or a shotgun. A second is a long time to
## stand still in the open with a tell on you, which is the trade this weapon
## is: the spear's 0.50 s windup is paid after the decision and this is paid
## before it, in public, and can be abandoned at any point for a worse shot.
@export_range(0.2, 4.0) var bow_draw_time: float = 1.0

## How long after a shot before the next arrow can be nocked.
##
## Shorter than `spear_recharge` by a wide margin, and it has to be: a spear is
## a guaranteed kill and an arrow at full draw is four fifths of one. What makes
## the two comparable is the draw — a full-power bow shot is 1.0 + 1.2 s of
## commitment against the spear's 0.5 + 3.0, and the bow spends most of its own
## in a pose everybody can see.
@export_range(0.2, 15.0) var bow_recharge: float = 1.2

## What an arrow does, at no draw and at a full one (D-065).
##
## 20 to 80 is the user's own range. What is worth reading off the two numbers
## is the pair they sit either side of: `Nameplate`'s health bands are amber at
## 50 and red at 25 (D-062), so a full draw takes a healthy Bog from green to
## red in one and a snap shot does not quite finish one that is already there.
## Both are deliberate and both are why the bow is not simply a faster spear.
##
## Neither is `Bog.MAX_HEALTH`, and that is the line between this weapon and the
## spear: `BogCombat.SPEAR_DAMAGE` is a whole body written as the constant, so
## no dial can make the spear a two-shot. These are numbers, so every dial here
## can make the bow anything at all — which is the point of them.
@export_range(1.0, 100.0) var bow_damage_snap: float = 20.0
@export_range(1.0, 100.0) var bow_damage_full: float = 80.0

## How fast an arrow leaves, at no draw and at a full one, in m/s.
##
## Against the spear's 42. A snap shot is slower than a thrown stick and a full
## draw is half again faster, which is the whole spread the charge buys and is
## deliberately extreme: the two ends have to be different *weapons*, not the
## same weapon with a bonus.
@export_range(5.0, 120.0) var bow_speed_snap: float = 18.0
@export_range(5.0, 120.0) var bow_speed_full: float = 60.0

## How fast an arrow falls, at no draw and at a full one, in m/s².
##
## Against the spear's 8. **The drop goes the other way from the speed**, and
## that is not physics — a real arrow falls at g whatever the bow did. It is the
## same exaggeration `SpearProjectile.DROP` already makes in the other
## direction (a third of world gravity, so that a throw has an arc worth
## reading), applied twice here so that the two ends of the charge are two
## trajectories rather than one trajectory at two speeds. At the defaults a snap
## shot is point-and-click to 8 m and a full draw to 50 (`BogCombat.flat_band`),
## which is the widest spread of any weapon in the game and is meant to be.
##
## The floor is 0.5 rather than 0: `flat_band` divides by this, and a drop of
## zero is a hitscan weapon with a flight time, which is not an arrow.
@export_range(0.5, 40.0) var bow_drop_snap: float = 16.0
@export_range(0.5, 40.0) var bow_drop_full: float = 5.0

## Not a cooldown, and deliberately not named like one. Shields and magnets are
## carried stock now (D-032) — there is nothing to recharge, so this is only a
## floor on how fast a stack can be spent. Without it a Bog who has just walked
## over four shield drops empties all four into the same square metre on one
## frame, which is neither cover nor a decision.
## How long after a great sword's attack before another may be asked for, in
## seconds (D-068, and the feel round).
##
## **0.800 was what was left of the spin's clip; 0.500 is what is left between
## chains.** The old default put the earliest second click on the exact tick the
## spin ended — `BogAnimator.SWING_SECONDS` 1.867 less `SWING_RELEASE_TIME`
## 1.067 — which is what made the sword chainable at all, and it was a number
## about one attack that no longer is the common one. The click is a three-slash
## chain now and this dial runs **between chains**, from the far side of the
## window a follow-up slash is taken in: a whole chain is about a second of
## blade and half a second of nothing, which is a rhythm rather than a
## commitment.
##
## The spin keeps every property it had. It is the sprint attack now
## (`BogCombat.SPRINT_ATTACK_SPEED`), it still spends `sword_cycle()` on the
## click, and at 0.500 that cycle is 1.567 against a 1.867 s clip — so the
## earliest second spin is still the tick the first one's spin ends, gated by
## `Bog.is_spinning()` instead of by this. `Bog` opens `LANDING_GRACE` on that
## frame, so a player who clicks then keeps the speed the last swing built and a
## player who is late loses it — the same window a bunny hop gets, off the same
## field (D-052), and `tools/combat_range.tscn -- chain` still measures it.
##
## Dragged up, chains get further apart and then stop overlapping the momentum
## window. Dragged down, a chain can be started again before the last one's
## blade has settled. Both are the right way round and neither needs a second
## rule.
@export_range(0.0, 10.0) var sword_recharge: float = 0.5

## How far a great sword reaches, in metres from the swinging Bog's own body
## centre to the *surface* of whatever it catches (D-068).
##
## **Measured with the animation rather than typed beside it.** At the release
## frame the point of the blade is 1.433 m from the Bog's own axis — that is
## `tools/preview_sword.tscn -- measure`, off a sword whose size is itself a
## measurement of how far apart the two fists are in `Swing` — and this is that
## number. `tools/combat_range.tscn -- sword` reads it again in a running match,
## through the bone attachment, and fails if the two have come apart, so the dial
## and the clip are checked against each other from both ends.
##
## What a player actually feels is **this plus the advance**: the body covers
## `Bog.SPIN_ADVANCE`'s 1.712 m during the swing, so a swing started 3.1 m away
## connects. That is the whole of what the spinning clip was chosen for, and it
## is why the two numbers have to move together — shorten the window and the
## advance shrinks while this stays where it was.
##
## It is a lobby dial because it is the balance number: the sword is a one-shot
## by construction (`BogCombat.SWORD_DAMAGE`), so the only things a host can
## trade are how long it commits you for and how far it reaches. The arc is
## deliberately *not* a dial — see `BogCombat.SWORD_ARC`.
@export_range(0.5, 6.0) var sword_reach: float = 1.43

@export_range(0.1, 10.0) var shield_use_delay: float = 1.5
@export_range(2.0, 120.0) var shield_lifetime: float = 25.0
@export_range(1, 5) var shield_max_active: int = 2

@export_range(0.1, 10.0) var magnet_use_delay: float = 2.0
@export_range(2.0, 25.0) var magnet_radius: float = 9.0
@export_range(0.2, 5.0) var magnet_hold: float = 1.4
@export_range(1.0, 60.0) var magnet_pull_strength: float = 18.0
## The delay between the magnet landing and the pull firing — the window in which
## seeing it land is worth anything. This defaulted to 0.35 while its own range
## started at 0.5, so `_clamp_all` silently raised every fresh config to 0.5 and
## the declared default was never the value anyone actually played with. The
## range wins: half a second is already a short fuse.
@export_range(0.5, 5.0) var magnet_fuse: float = 0.5

## **The capture time**: how long a Bog stands with a letter card before the
## letter is actually theirs, in the Free-for-all flavour of B·O·G. Touching the
## card starts the capture; finishing it is what scores (D-035).
##
## There is no drop-chance dial beside it any more, and that is what this number
## now has to carry on its own. A letter no longer rolls out of a corpse at some
## percentage: exactly one card is out at any moment, the next death puts the
## next letter down, and so the only question left about a card is what it costs
## to keep one. This is that question, which is why it is still a dial — ten
## seconds standing still in the open is a long time, and the first real lobby is
## the only thing that can say whether it is too long.
##
## Teams does not read it. That flavour is Capture B·O·G, where a card is carried
## rather than stood with, and what ends a carry is a vault and not a clock.
##
## **Zero is legal and means "grant it on touch"** — the mode without the hold,
## which is what it was before, and the setting to reach for if the hold turns
## out to be miserable. It is taken as a special case rather than as a hold that
## expires immediately, because a one-frame hold is one frame with the spear out
## of the hand: a visible flicker for a setting whose entire point is that there
## is nothing to see.
@export_range(0.0, 30.0) var letter_hold_time: float = 10.0

## **Capture B·O·G** (D-051): how long a letter dropped by a dead carrier lies
## where it fell before it goes home to its spawn. Anyone may pick it up in that
## time, the carrier's own team included.
##
## A dial because it is the one number that decides what a kill on a carrier is
## worth. Short, and killing a carrier near your base is a full reset; long, and
## a card dropped in no man's land becomes the fight. Fifteen seconds is a little
## more than a respawn plus a sprint back, so the dead carrier's team has a real
## chance to recover it.
@export_range(3.0, 60.0) var capture_return_time: float = 15.0

## How long a thief has to stand on an enemy vault to lift a banked card out of
## it (D-092).
##
## A dial, and a short one, because it is the whole of what makes a vault a place
## worth defending. At one second a bank is a formality and a lone attacker
## empties it on the way past; at five, a defender who is anywhere nearby always
## arrives in time and nothing is ever stolen. Three is about a sprint from the
## bottom of a ramp, which is the distance the maps put between a base's door and
## its vault.
@export_range(1.0, 5.0) var capture_steal_time: float = 3.0

## What a Bog carrying a letter in Capture B·O·G multiplies its ground speed by.
## Below one on purpose: a carrier who outruns everybody to their base is a
## carrier nobody gets to fight. Applied at `Bog.target_speed`, the same single
## point the Elder's boost is, so the two multiply rather than one hiding the
## other.
@export_range(0.5, 1.2) var capture_carrier_speed: float = 0.9

## How often a death drops the Elder's robe, **in every mode**.
##
## Unlike the letter card, this is not gated on a win condition. The
## Elder is not a scoring mechanic — it is a weapon, and a weapon that only
## exists in one of four modes is a weapon nobody learns. So the robe rolls out
## of the same corpse in a kill-limit match as in a letters one (D-038).
##
## Rarer than either ability by a wide margin, because it is strictly stronger
## than anything else that drops: 2% of deaths against the shield and magnet's
## ~49% each. In a ten-minute free-for-all that is one or two robes, which is
## the intent — an Elder should be an event, not a phase everyone passes
## through.
##
## **It was 5% and came down to meet what the Elder became** (D-040). Five per
## cent was set for an Elder that was a modest upgrade held until somebody
## killed you: a stronger weapon, on a five-second recharge, that died like
## anything else. What the dial now hands out is twenty seconds during which a
## Bog cannot be killed at all, moves a third faster, and fires a one-shot
## weapon about once a second. Arriving several times a match, that is not an
## event; it is the match. The user has been told this happened and the slider
## is right here if they want it back.
@export_range(0.0, 1.0) var elder_drop_chance: float = 0.02

## How often a death drops a heal potion (D-067).
##
## **Taken off the top of the drop table like the letter and the robe**, rather
## than the remainder being split three ways instead of two. That is the whole
## reason this field exists: with the potion as a third share of what is left,
## the shield and the magnet would have gone from ~49% of drops each to ~30%
## each, and nothing in the lobby would have said so. Off the top, the default
## below reproduces exactly that three-way split — and a host who wants the old
## economy back drags one slider instead of editing a table.
##
## 30% and not 2% because a potion is not a robe. It is the most ordinary thing
## that can fall out of a corpse: it is worth `heal_amount` and two seconds of
## standing still, and a match where you see one every twenty deaths is a match
## in which nobody ever learns that healing exists. The three common drops are
## deliberately near enough equal — 30/30/30 against the letter's 8 and the
## robe's 2 — because which of the three you get should be the interesting part
## and not whether you got anything.
@export_range(0.0, 1.0) var potion_drop_chance: float = 0.30

## What one heal potion is worth, in the units of `Bog.MAX_HEALTH`.
##
## 40 of a body's 100, which is two snap arrows or half a full draw. The number
## is picked off the two bands the nameplate draws (D-062): a potion takes a Bog
## from anywhere in the red below 25 to well inside the green above 50, so
## drinking one is always the difference between "the next arrow kills me" and
## "it does not" — and it is never a reset, because 40 cannot refill a Bog that
## has been properly hurt.
##
## **This is the balance dial for healing and the only one.** Whether an
## interrupted channel refunds the potion is not a setting and deliberately so
## (D-067): it is what the mechanic *is*, in the same way `Bog.MAX_HEALTH` is
## the unit rather than a slider (D-062).
@export_range(5.0, 100.0) var heal_amount: float = 40.0

## How long drinking one takes, in seconds.
##
## **Channelled, not instant, and this is the number that makes it so** (D-067).
## An instant heal on pickup makes standing on a fresh corpse the strongest play
## in the game and removes every decision from healing; two seconds of standing
## still creates the "drink now or run" question that is the whole point. The
## health arrives *over* it rather than at the end of it, so a channel broken
## half way through is worth half a potion.
##
## `BogAnimator.drink_rate_for_channel` plays the drink clip at whatever rate
## makes it take exactly this long, so a host who drags this slider moves the
## animation with it and cannot leave a Bog standing still with its arms down
## for a second after the bottle is empty.
##
## The floor is 0.5 and not 0.0. Zero is the setting this whole feature exists
## to refuse, and unlike `lightning_delay` — where zero means something real and
## is guarded by a rate ceiling — there is nothing on the other side of it
## except the mechanic the decision rejected.
@export_range(0.5, 6.0) var heal_channel: float = 2.0

## How long after the click the Elder's bolt actually leaves the hand.
##
## The user, having played it: *"There should be basically no delay for the
## lightning, right when you press then it should shoot maybe .2 seconds
## after."* **This supersedes the release-time half of D-038**, which fired the
## bolt at the `Throw` clip's own release — 0.71 s then, 0.50 s since D-063 —
## because the same clip was being reused. The Elder has its own `Cast` clip
## since D-064, and it is played faster to meet this number rather than this
## number being fitted to it — `BogAnimator.cast_rate_for_release` derives the
## rate, so the arm and the bolt cannot drift apart (D-040).
##
## **Zero is legal and means "on the frame of the click"**, which is why the
## range starts there rather than at something safely small. The clip still
## plays, at `BogAnimator.CAST_RATE_MAX`, and the bolt leads the hand by about
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
## surface of a Bog's collision capsule (D-053).
##
## The user: *"the lightning should have an aoe (small blast radius) so that if
## you hit pretty close it still hits them, this should still be a one shot
## kill, but not too far."* So it is a hard edge with no falloff — inside it is
## the same kill a direct hit is, outside it is nothing — and 1.5 m is about two
## Bog-widths of forgiveness either side of the body, which forgives a bolt into
## the ground at somebody's feet and does not forgive one into the next room.
## The blast needs a clear line from the impact to the body, so a wall or a
## shield is still cover; it only exists where the bolt hit something;
## and it goes through `report_kill` like every other death, so an Elder is
## warded against it exactly as against a direct hit (D-040).
##
## **Zero is legal** and is the bolt as it was before: a direct hit or nothing.
@export_range(0.0, 4.0) var lightning_radius: float = 1.5

## How long the robe lasts before it burns out, in seconds.
##
## **This supersedes D-038's "the Elder lasts until it dies".** With
## invincibility, death is no longer the exit — a Bog that cannot be killed and
## is the Elder until it is killed is the Elder for the rest of the match. So
## the clock is the exit, it is owned by the host exactly as a letter hold is,
## and when it runs out the robe is consumed, the model reverts and the Bog is
## ordinary again.
##
## Expiry is **not** a death: the letters and the carried shields and magnets a
## Bog had before the robe are still there afterwards. Nothing about the twenty
## seconds is meant to cost you what you already had.
@export_range(1.0, 120.0) var elder_duration: float = 20.0

## What the Elder multiplies `Bog.RUN_SPEED`, `WALK_SPEED` and `CROUCH_SPEED` by.
##
## A multiplier on the existing constants rather than a second set of speeds, so
## there is still exactly one place that says how fast a Bog moves and the
## Elder is a factor applied to it. It is applied at `Bog.target_speed()`, which
## is the single point every stance already comes out of — walking, sprinting
## and crouching all scale together and none of them can be forgotten.
@export_range(1.0, 3.0) var elder_speed_multiplier: float = 1.35

## What the Elder multiplies `Bog.JUMP_VELOCITY` by.
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
	"spear_recharge",
	"bow_draw_time", "bow_recharge", "bow_damage_snap", "bow_damage_full",
	"bow_speed_snap", "bow_speed_full", "bow_drop_snap", "bow_drop_full",
	"sword_recharge", "sword_reach",
	"shield_use_delay", "shield_lifetime", "shield_max_active",
	"magnet_use_delay", "magnet_radius", "magnet_hold",
	"magnet_pull_strength", "magnet_fuse",
	"letter_hold_time",
	"capture_return_time", "capture_steal_time", "capture_carrier_speed",
	"elder_drop_chance", "lightning_delay", "lightning_cooldown", "lightning_radius",
	"potion_drop_chance", "heal_amount", "heal_channel",
	"elder_duration", "elder_speed_multiplier", "elder_jump_multiplier",
	"max_players", "map", "map_seed",
]


## Every field a config is made of, in the order it travels. Public since D-076,
## because the lobby's clipboard capture has to enumerate "what a config is" and
## the only correct answer is this list: it is what `to_dict` sends, so a setting
## that is not in it is a setting nobody else ever sees, and a capture built from
## a hand-written list would be complete on the day it was written and silently
## short by one on the day the next dial lands.
static func fields() -> PackedStringArray:
	return PackedStringArray(_FIELDS)


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
	bow_draw_time = clampf(bow_draw_time, 0.2, 4.0)
	bow_recharge = clampf(bow_recharge, 0.2, 15.0)
	# Each to its own range and **no cross-checks between the pairs**. A host who
	# wants a bow that hits harder the *less* it is drawn can have one: it is a
	# lerp either way round, nothing downstream divides by the difference, and a
	# clamp that quietly swapped two sliders the host had just dragged would be a
	# lobby arguing with the person using it.
	bow_damage_snap = clampf(bow_damage_snap, 1.0, 100.0)
	bow_damage_full = clampf(bow_damage_full, 1.0, 100.0)
	bow_speed_snap = clampf(bow_speed_snap, 5.0, 120.0)
	bow_speed_full = clampf(bow_speed_full, 5.0, 120.0)
	bow_drop_snap = clampf(bow_drop_snap, 0.5, 40.0)
	bow_drop_full = clampf(bow_drop_full, 0.5, 40.0)
	sword_recharge = clampf(sword_recharge, 0.0, 10.0)
	sword_reach = clampf(sword_reach, 0.5, 6.0)
	shield_use_delay = clampf(shield_use_delay, 0.1, 10.0)
	shield_lifetime = clampf(shield_lifetime, 2.0, 120.0)
	shield_max_active = clampi(shield_max_active, 1, 5)
	magnet_use_delay = clampf(magnet_use_delay, 0.1, 10.0)
	magnet_radius = clampf(magnet_radius, 2.0, 25.0)
	magnet_hold = clampf(magnet_hold, 0.2, 5.0)
	magnet_pull_strength = clampf(magnet_pull_strength, 1.0, 60.0)
	magnet_fuse = clampf(magnet_fuse, 0.5, 5.0)
	# Zero survives this on purpose — it is the "grant on touch" setting, not a
	# value to be raised into a capture nobody asked for.
	letter_hold_time = clampf(letter_hold_time, 0.0, 30.0)
	capture_return_time = clampf(capture_return_time, 3.0, 60.0)
	capture_steal_time = clampf(capture_steal_time, 1.0, 5.0)
	capture_carrier_speed = clampf(capture_carrier_speed, 0.5, 1.2)
	elder_drop_chance = clampf(elder_drop_chance, 0.0, 1.0)
	potion_drop_chance = clampf(potion_drop_chance, 0.0, 1.0)
	heal_amount = clampf(heal_amount, 5.0, 100.0)
	# The floor is 0.5 and means it: a channel of zero is an instant heal, which
	# is the thing D-067 exists to refuse. Unlike `lightning_delay` below there
	# is no "on the frame of the click" setting here to be preserved.
	heal_channel = clampf(heal_channel, 0.5, 6.0)
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
	# **There is one letters game, called B·O·G, and the mode decides its
	# flavour.** Free-for-all is the collect race (D-033, D-035): one card out at
	# a time, captured by standing with it. Teams is capture-the-flag (D-051,
	# D-092): three cards at home points, carried into a vault. They are two
	# ordinals because they are two sets of rules on the wire and the enum is
	# append-only — but they are not two things a host picks between, which is
	# why the lobby offers a single **B·O·G** entry and this decides which
	# ordinal it means.
	#
	# Both halves are here rather than one here and one in the lobby. The panel
	# used to own the Capture→Free-for-all direction (`MatchSettingsPanel._push`)
	# because this function cannot tell which field was just changed — and it
	# still cannot, but it no longer needs to: whichever of the two moved, the
	# mode is the answer, so there is one rule instead of two halves that have to
	# be kept facing each other. Every path into a config — the lobby, a peer's
	# dictionary, a harness — comes out playable and comes out the same.
	if win_condition == WinCondition.LETTERS and mode == Mode.TEAMS:
		win_condition = WinCondition.CAPTURE
	elif win_condition == WinCondition.CAPTURE and mode == Mode.FREE_FOR_ALL:
		win_condition = WinCondition.LETTERS
	# TIME_ONLY with no clock would never end.
	if win_condition == WinCondition.TIME_ONLY and time_limit <= 0:
		time_limit = 600


# ------------------------------------------------------------- practice ---
#
# **Practice is a property of the map, not a mode** (D-112). The range is a row
# in `MapCatalog` with `"practice": true` on it, chosen from the same picker as
# every other map, and the five rules below follow from standing on it.
#
# They are read *through* rather than written *in*, and that is the whole design
# of this block. Mutating the config when the range is picked — setting
# `time_limit = 0` and `respawn_delay = 1.0` on the host's own resource — would
# destroy the numbers the host spent a lobby dialling in, and putting them back
# when they pick Rust again means remembering what they were: a second copy of
# the config, an undo stack, or a host who quietly loses their settings to a
# minute in the range. None of those is worth having when the alternative is
# five one-line accessors.
#
# `map` already travels in `_FIELDS`, so every peer computes the same answers
# from the same row with nothing new on the wire.
#
# Everything *else* about a practice match is unchanged on purpose: the kill
# feed still runs (it is feedback), damage and death are the real ones, and the
# drop table rolls exactly as it does anywhere else. What practice removes is
# only what makes a match a match — the clock, the win check, and the two
# delays that exist to make dying cost something.

## How long a Bog is down for in the range. Long enough to see the ragdoll land,
## short enough that nobody counts it.
const PRACTICE_RESPAWN := 1.0


## Whether this match is being played somewhere nothing is at stake.
func is_practice() -> bool:
	return MapCatalog.is_practice(map)


## No warmup. Standing still for five seconds is a thing a match does so that
## everyone starts together; a range has nobody to start together with.
func effective_warmup_time() -> float:
	return 0.0 if is_practice() else warmup_time


## No clock. Zero is already "no time limit" everywhere that reads it
## (`MatchState._tick_clock` returns on it), so this needs no second branch.
func effective_time_limit() -> int:
	return 0 if is_practice() else time_limit


## No spawn protection. It exists to stop a spawn camp, and the thing you are
## practising on is a dummy that does not camp — while two seconds of
## invulnerability after every death is two seconds in which the range lies to
## you about whether your own shots land.
func effective_spawn_protection() -> float:
	return 0.0 if is_practice() else spawn_protection


## A second, not three. See `PRACTICE_RESPAWN`.
func effective_respawn_delay() -> float:
	return PRACTICE_RESPAWN if is_practice() else respawn_delay


## Whether a win condition is scored in B·O·G letters — the lamps, the letters
## column and the letter-first ranking. True for both letter modes, which differ
## in how a letter is *earned* (a hold, or a carry home) and not in what it
## counts toward. The loot roll deliberately does not ask this: only LETTERS
## drops cards out of corpses (D-051).
static func scores_letters(condition: int) -> bool:
	return condition == WinCondition.LETTERS or condition == WinCondition.CAPTURE


## The same question asked in the word the game now uses for it: **is this
## B·O·G?** One game, two flavours, two ordinals on the wire — and everything
## outside the rules themselves (the guide line, the minimap, the tutorial, the
## HUD) wants the game and not the flavour. An alias rather than a rename
## because `scores_letters` says something true about scoring that the lamps and
## the ranking still ask, and one of the two names being the other's body means
## they can never drift apart.
static func is_bog(condition: int) -> bool:
	return scores_letters(condition)


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
		# One name for one game. The flavour is the mode, and the mode is
		# already the first thing this line prints — "Free-for-all  ·  B·O·G"
		# and "2 Teams  ·  B·O·G" say which of the two it is without the
		# summary having to name it twice.
		WinCondition.LETTERS, WinCondition.CAPTURE:
			parts.append("B·O·G")
	if time_limit > 0:
		parts.append("%d:%02d" % [time_limit / 60, time_limit % 60])
	if mode == Mode.TEAMS and random_teams:
		parts.append("random teams")
	if mode == Mode.TEAMS and friendly_fire:
		parts.append("friendly fire")
	return "  ·  ".join(parts)
