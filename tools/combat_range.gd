extends Node3D
## Firing range for Phase 3. Development tool, not shipped.
##
## Unlike `tools/sandbox.tscn`, which instantiates one Gub directly to feel the
## movement, this runs the **real match path**: an offline session on `Net`, a
## roster, `MatchState.register_arena`, Gubs spawned by `MatchState._create_gub`,
## and kills reported through `MatchState.report_kill`. Nothing here reaches past
## a public API into the combat code, so if a throw works in this scene it works
## in a match.
##
## The opponents are ordinary Gubs owned by peer ids that will never connect, so
## they are *remote* Gubs to this client: no input, no gravity, no camera. That
## is exactly what a target dummy should be, and it also means this scene is the
## only place the remote-Gub code path gets looked at before eight people do.
##
## Play it:
##   Godot --path . tools/combat_range.tscn
##
## Snapshot it (the mode is the trailing argument, as in the sandbox):
##   Godot --path . --resolution 1280x720 --script tools/snapshot.gd -- \
##       res://tools/combat_range.tscn out.png 110 hit

## Peer ids for the dummies. Well outside anything ENet hands out, so a stray
## real peer can never collide with one.
const DUMMY_BASE := 900

## The same packed scene `GubCombat` plants, so the `cover` mode stands up the
## shipping mushroom rather than a hand-built stand-in that happens to share its
## constants.
const MUSHROOM := preload("res://scenes/items/shield_mushroom.tscn")

## What each mode does.
##
##   flight   — a spear caught in mid-air on its way to a dummy
##   hit      — the same throw, held until the dummy is a corpse
##   arc      — a long throw at the far wall, to see how much a spear drops
##   miss     — a throw into the dirt, to check the spear sticks and stays put
##   aim      — holds the aim button at the far wall and never throws, which is
##              the state the spear's landing ring lives in and the one state no
##              other mode here spends a frame in. It also prints where the ring
##              landed and how far short of the aim point that is, so a run says
##              something even if nobody opens the PNG. Watched from the
##              touchline like everything else — the ring is flat on the ground
##              and from the thrower's own eye it is seen nearly edge-on, so
##              `pov` is worth passing to check exactly that and is the wrong
##              default for a still frame.
##   mushroom — one planted, to check it lands on the ground the right size
##   cover    — the mushroom as *cover*, which is the only thing about it that
##              matters and the one thing nothing has ever checked. It stands a
##              real one up in front of a dummy, prints how wide the collision
##              actually is at every height a Gub occupies, throws a spear at the
##              dummy behind it, withers the mushroom and throws the *same* throw
##              again, and then walks the player into one. Three verdicts, and
##              the second is the reason the first means anything: a spear that
##              never kills anybody would sail through the blocked check.
##   recharge — throws until the spear has grown back a dozen times and requires
##              the shaft to be in the fist at the end of every one of them, then
##              takes it out of the fist by hand while the throw gate still says
##              armed and requires it to come back on its own. The first half is
##              the bug as a player meets it; the second is the property that
##              stops it coming back, checked without having to lose a race on
##              purpose.
##   lure     — a lure lobbed at the middle dummy, held through the pull.
##              Note what this mode can and cannot show: the catch *decision* is
##              the host's and is reported here, but the pull itself is applied
##              on each victim's own client, and these dummies are fake roster
##              entries with no client behind them. So the dummies will be
##              listed as caught and will not visibly move. Only the local Gub
##              can actually be dragged — see `lure_self`.
##   lure_self— a lure dropped at the player's own feet, which is the only way
##              to watch the pull actually move a Gub in a one-client testbed
##   letter   — kills a dummy with the letters condition on and the drop chance
##              forced to 1, puts the card down at the player's feet, and lets
##              the player's own body walk into it. So this is the *whole*
##              collection path — the roll, the `Pickup` area's overlap,
##              `claim_pickup`, the hold — and then it simply stands there, which
##              is the state the mechanic is about: a Gub in the open with a
##              letter up and no spear (D-035). The only mode here whose picture
##              is of a Gub doing nothing, on purpose.
##   cards    — one of each letter set down on the ground in front of the
##              player, which is the picture of the three meshes themselves
##              (D-040). It is the only mode here that reaches past a public API
##              into `MatchState._spawn_drop`, and the reason is the roll: a
##              card's letter is `randi() % 3` and nothing else (D-033), so
##              `letter` above photographs whichever letter came up — and a
##              picture of one random letter is not a picture of the asset.
##              Everything except the choosing is the real thing: real spawn,
##              real `Pickup`, real bob, real spin, real catch volume.
##              They spin from zero at `Pickup.SPIN_SPEED`, so a still is a
##              question of when: tick 363 is one full turn after the drop on
##              tick 20 and catches all three face-on, while the gate's own
##              frame 60 is a quarter of the way round, which is the more
##              honest picture of a letter on the ground and the worse one for
##              reading it.
##   lightning— the whole Elder, end to end: a robe dropped out of a real death
##              with `elder_drop_chance` forced to 1, walked over by the
##              player's own body, and then one bolt at the middle dummy. It is
##              the mode that catches "the bolt does not actually kill
##              anything", which no logic test can: `tools/match_rules.gd`
##              proves the robe makes an Elder and that the cooldown gates a
##              second cast, but it has no world, no geometry and nothing
##              standing fourteen metres away to be hit. This prints its own
##              verdict, because a still frame of a lightning bolt looks
##              identical whether or not anybody died at the end of it.
##   ward     — the other half of the Elder, and the half no logic test can
##              reach: **a real spear, in the air, thrown at a real Elder**
##              (D-040). `tools/match_rules.gd` can assert that `report_kill`
##              refuses the kill; it cannot assert that a shaft launched at a
##              body fourteen metres away arrives, is turned aside, and leaves
##              the Gub standing. The mushroom spent its whole life passing a
##              check that only proved a PNG existed (D-039) — this is that
##              lesson applied to the rule it would hurt most to get wrong.
##
##              Three verdicts out of one run, and the second is what makes the
##              first mean anything: the Elder survives a spear, the robe then
##              **burns out on its own clock** while the run is watching, and the
##              *same* throw at the *same* Gub kills it once the robe is off.
##              Without that control, "did not die" is satisfied by a spear that
##              never left the hand.
##   walk     — holds W for a second and requires the Gub to have gone somewhere.
##              Trivial-looking, and it is here because movement was wired up in
##              this file and in the sandbox and nowhere else, so every testbed
##              could be walked around while the actual game could not.
##   leave    — tears the session down out from under a live Gub and keeps
##              ticking, which is what leaving a match actually does: `Net`
##              nulls the multiplayer peer and `SceneFlow` then fades for 0.22 s
##              before the arena is freed, so every Gub in the tree spends those
##              frames still being processed with no peer to ask.
##   free     — no script; play it yourself
const MODES := ["flight", "hit", "arc", "miss", "aim", "mushroom", "cover",
	"lure", "lure_self", "letter", "cards", "lightning", "ward", "recharge",
	"walk", "leave", "free"]

## How long after the cast the verdict is taken, in physics ticks. The click
## only starts the windup — the bolt leaves at `MatchConfig.lightning_delay`,
## 0.2 s since D-040, which is 12 ticks — and the hitscan resolves on that same
## tick, since there is no projectile to fly.
##
## Left at fifty rather than retuned down with the delay. It was 0.71 s of
## windup plus a margin and is now most of it margin, and a verdict taken *late*
## costs a headless run half a second; one taken early cannot tell "the bolt did
## nothing" from "the bolt has not gone yet", which is the only way this mode can
## lie. If the dial is ever raised past 0.8 s this number has to move with it.
const LIGHTNING_VERDICT_DELAY := 50

## How long after the click a spear's verdict is taken, in physics ticks. Same
## arithmetic as the bolt's above and one more term: the click starts the
## windup, the shaft leaves `GubAnimator.THROW_RELEASE_TIME` (0.71 s, 42.5
## ticks) later, and then it has fourteen metres to cross at 42 m/s — twenty
## ticks. Ninety-five is that plus a margin, and the margin matters more here
## than it looks: the whole point of `cover` is a throw that is *supposed* to
## produce nothing, and a verdict taken too early cannot tell "blocked" from
## "not there yet".
const SPEAR_VERDICT_DELAY := 95

## How far the `walk` mode requires the Gub to travel. A Gub that is not walking
## still drifts a little as it settles onto the ground on the first few frames,
## and this is comfortably clear of that.
const WALK_MIN_DISTANCE := 1.0

## The `cover` mode's ray profile: how high it climbs, how far either side it
## looks, and how finely it samples across. 3 cm across a 3.2 m span is 161 rays
## per height band and 18 bands, which is nothing to fire in one frame and is
## fine enough to see a 5 cm hole between a stem and a cap — which is the shape
## of gap that put this mode here.
const PROFILE_TOP := 2.70
const PROFILE_STEP := 0.15
const PROFILE_HALF_WIDTH := 1.60
const PROFILE_SAMPLE := 0.02

## How much the cap is allowed to let a walking Gub in past the distance the
## geometry says it should be held off at — `CAP_RADIUS + CAPSULE_RADIUS`.
##
## Not a fudge factor. A `CharacterBody3D` pressed into a static cylinder is
## resolved by depenetration rather than by a hard stop, and a capsule's top
## hemisphere is narrower than its waist, so the honest contact distance is a
## centimetre or two inside the sum of the two radii. A quarter of a metre is
## comfortably outside that and still nowhere near the 0.66 m a Gub reached when
## the only thing at its own height was the stem.
const COVER_HOLD_OFF_SLACK := 0.25

## How far to one side of the line of fire the mushroom in the `cover` mode is
## planted.
##
## **Not zero, and this is the most important number in the check.** Lined up
## perfectly, the stem alone blocks the shot — it is 0.55 m of post standing on
## the exact line between the two Gubs — so a dead-centre throw is stopped by a
## mushroom whose cap is a metre above the fight and the check passes while
## proving nothing. It was written that way first and it did pass, which is how
## the real mushroom got here.
##
## Half a metre out is a thirteen-degree difference at `MUSHROOM_DISTANCE`, which
## is what happens when either Gub takes one step, and it is nowhere near the
## edge of a cap 2 m across. Anything that stops the spear there is stopping it
## with the cap, which is the thing being checked.
const COVER_OFFSET := 0.5

## How many throw-and-regrow cycles `recharge` drives before it is satisfied.
##
## Twelve rather than one because the failure it guards is a race between two
## clocks, and a race lost by a millisecond passes a single trial by luck. At
## the 0.15 s recharge this mode sets, a cycle is the 0.71 s windup plus that —
## 52 ticks — so twelve of them is about 630 ticks, which is what the smoke
## gate's warmup count is sized for.
const RECHARGE_CYCLES := 12

## How long the deliberate desync waits for the hand to notice, in physics
## ticks. Half a second is forty times `HAND_SYNC_GRACE` and several times any
## plausible repaint lag: anything still empty-handed at the end of it is not
## slow, it is never coming back.
const DESYNC_PATIENCE := 30

## How long the mushroom under test lives. Far longer than the run, so that
## nothing here is ever accidentally measuring a wither.
const COVER_LIFETIME := 120.0

## How long the `ward` mode's robe lasts, in seconds.
##
## Short, because the mode has to watch it burn out — and **it burns out on its
## own**, through `MatchState._tick_elders` running in a real match loop, rather
## than by the run reaching in and winding the row's deadline back. That is the
## whole difference between this and `match_rules`' `_expire_elder`: the harness
## next door can prove the teardown is correct once something calls it, and only
## this can prove that something does.
##
## Three seconds is long enough for the first spear's full 0.71 s windup and
## 0.33 s of flight to land inside the window with room either side, and short
## enough that the run is over in about six.
const WARD_DURATION := 3.0

## How long the `ward` mode will wait for that to happen before calling it a
## failure, in physics ticks. Generous — three seconds is 180 — and it exists so
## that a robe which never expires ends the run with a verdict rather than
## hanging a headless check for ever.
const WARD_EXPIRY_LIMIT := 420

## How long the player leans on the mushroom in the `solid` half, in physics
## ticks. At `Gub.WALK_SPEED` a Gub covers the `MUSHROOM_DISTANCE` to it in
## under a second, so this is most of a second of actually pushing.
const COVER_WALK_FRAMES := 100

## The silhouette grid in `_hidden_fraction`: 21 slices up a 1.55 m body is one
## every 7 cm, and 11 across a 0.76 m one is one every 7 cm too, so the samples
## are square and neither axis is flattering the answer.
const SILHOUETTE_ROWS := 21
const SILHOUETTE_COLS := 11

## How many frames the hand is allowed to be out of step with the throw gate
## before it counts as a failure.
##
## Not zero, and deliberately: `_refresh_hand` runs in `_process` and the gate
## it reads moves in wall-clock time, so there is always a frame or two in which
## the gate has opened and the hand has not been repainted yet. Four frames at
## 60 Hz is 66 ms — under a tenth of a second, far below anything a player could
## call unreliable, and forever short of the "never" the bug actually produced.
const HAND_SYNC_GRACE := 4

## Every scripted mode is watched from the touchline. The thrower's own camera
## looks *along* the throw, where the spear is a dot behind the Gub's head and a
## parabola is a straight line — the one view that cannot show whether any of
## this works. Pass `pov` as the argument after the mode to use it anyway.
##  mode -> {eye, look, fov}
const VIEWS := {
	"flight": {"eye": Vector3(17.0, 5.5, 2.0), "look": Vector3(0.0, 1.4, 2.0), "fov": 60.0},
	"hit": {"eye": Vector3(11.0, 3.4, -2.0), "look": Vector3(0.0, 1.0, -4.6), "fov": 55.0},
	"arc": {"eye": Vector3(30.0, 10.0, -12.0), "look": Vector3(0.0, 2.5, -12.0), "fov": 62.0},
	"miss": {"eye": Vector3(9.0, 3.0, -9.0), "look": Vector3(0.0, 0.6, -13.0), "fov": 50.0},
	"mushroom": {"eye": Vector3(6.0, 2.6, 9.5), "look": Vector3(0.0, 1.1, 7.2), "fov": 50.0},
	# Square on to the flight and level with the cap, because the whole subject
	# of this one is a spear that stops in mid-air fourteen metres from where it
	# was thrown. Down the throw it is a dot; from above, a stick lying on a
	# mushroom. From the side the shaft is visibly buried in the cap with the
	# dummy standing untouched two metres behind it, which is the picture.
	"cover": {"eye": Vector3(7.6, 2.0, -1.2), "look": Vector3(0.2, 1.25, -4.0), "fov": 42.0},
	"lure": {"eye": Vector3(12.0, 8.0, -3.0), "look": Vector3(-3.0, 1.0, -12.0), "fov": 60.0},
	"lure_self": {"eye": Vector3(9.0, 3.2, 12.0), "look": Vector3(0.0, 1.0, 7.0), "fov": 55.0},
	# Close, and level with the chest rather than looking down: the question
	# this one answers is whether a card in a fist reads as a card in a fist,
	# and from any distance that flatters it every glyph reads fine.
	"letter": {"eye": Vector3(4.0, 1.9, 12.0), "look": Vector3(0.0, 1.5, 9.0), "fov": 45.0},
	# Square on to the row and level with it, because the question is whether
	# three 0.6 m letters read as G, U and B — which is a question about the
	# meshes and not about the Gub, so the player stays behind the camera.
	"cards": {"eye": Vector3(2.2, 1.5, 8.6), "look": Vector3(0.0, 0.75, 6.0), "fov": 45.0},
	# Square on to the bolt and well back from it. The bolt runs the fourteen
	# metres from the player at z=9 to the dummy at z=-5, so the one view that
	# shows it is from the side: down the throw it is a bright dot, and from
	# above it is a line with no target at the end of it. 15 m out at this
	# field of view puts the whole stroke across the frame with the Elder at one
	# end and the body leaving the ground at the other.
	"lightning": {"eye": Vector3(13.0, 3.2, 6.0), "look": Vector3(-0.5, 1.3, 2.0),
		"fov": 58.0},
	# Close in on the Elder rather than on the flight, because the subject here
	# is the *arrival*: a spear stopping at a robe and a violet flash where it
	# stopped, with the Gub still on its feet. Down the throw the ward is behind
	# the shaft; from the side it is the whole picture.
	"ward": {"eye": Vector3(6.5, 2.2, -1.5), "look": Vector3(0.0, 1.2, -5.0),
		"fov": 46.0},
	# High and off to one side, because a ring lying on the ground is seen
	# edge-on from the thrower's own eye and a still frame of that is a line one
	# pixel tall. Pass `pov` after the mode to look down the throw anyway — that
	# is the view the player actually gets, and it is worth checking.
	"aim": {"eye": Vector3(11.0, 8.0, 0.0), "look": Vector3(1.5, 0.2, -13.0), "fov": 55.0},
}

const PLAYER_SPOT := Vector3(0.0, 0.1, 9.0)
const DUMMY_SPOTS: Array[Vector3] = [
	Vector3(0.0, 0.1, -5.0),
	Vector3(-6.0, 0.1, -13.0),
	Vector3(5.5, 0.1, -20.0),
]
## Where the long throw is aimed in `arc` mode: the far wall, well past any
## dummy, so the whole parabola is in frame.
const ARC_TARGET := Vector3(0.0, 1.2, -34.0)
## Where `aim` points. The same far wall, shifted off the centre line on
## purpose: aimed straight down it the spear meets Dummy 1 at fourteen metres
## and the landing ring is drawn on a Gub's chest, which proves the marker works
## on players and shows nothing at all about drop. Offset, the flight has clear
## air all the way down and the ring lands on open dirt, where the gap between
## it and the point being aimed at is the whole picture.
const AIM_TARGET := Vector3(2.5, 1.2, -34.0)
## Where the `recharge` mode points: over the back wall and into the void, so a
## dozen spears in a row leave the hand, expire at `SpearProjectile.MAX_LIFETIME`
## and never once touch anybody. The mode is about the fist the spear comes back
## into, and a dummy dying twelve times would bring a respawn, a corpse and a
## loot roll into a check that has nothing to do with any of them.
const RECHARGE_TARGET := Vector3(0.0, 14.0, -30.0)

var _mode: String = "free"
var _trace: bool = false
var _pov: bool = false
var _frames: int = 0
## Where the `walk` mode started measuring from.
var _walk_from: Vector3 = Vector3.ZERO
var _acted: bool = false
var _items: Node3D
var _players: Node3D
var _aim_at: Vector3 = Vector3.ZERO
## The frame the Elder's bolt was fired on, or 0 for "not yet". The verdict is
## taken relative to this rather than at a fixed frame, because the cast waits
## on the robe being picked up and that is an `Area3D` overlap rather than a
## countdown.
var _cast_at: int = 0
var _fixed_camera: Camera3D

## `cover`'s state machine. It runs on gates rather than on frame numbers
## wherever it can — the second throw waits for the spear to have grown back,
## exactly as `lightning` waits for the robe — so the mode does not quietly
## start failing the day somebody retunes `spear_recharge`.
var _cover_step: int = 0
var _cover_at: int = 0
var _cover_mushroom: Node3D = null
## The closest the walking Gub has come to the axis of the mushroom in its way.
## A minimum rather than a final position, because a Gub pressed into a cylinder
## slides around it: where it *ends up* says nothing, and how far in it ever got
## says everything.
var _cover_closest: float = INF

## `recharge`'s bookkeeping. `_hand_out_of_step` counts consecutive frames on
## which the throw gate said armed and the fist was empty, which is the bug
## stated as a number.
var _recharge_cycles: int = 0
var _recharge_failures: int = 0
var _hand_out_of_step: int = 0
var _worst_out_of_step: int = 0
## Set once the twelve honest cycles are done and the hand has been emptied by
## hand, to see whether anything ever asks again.
var _desync_at: int = 0
var _desync_recovered: int = -1
var _recharge_thrown: int = 0

## `ward`'s state machine, the same shape as `cover`'s and on gates for the same
## reason: the robe is claimed by an `Area3D` overlap and burns out on a
## wall clock, and neither of those is a frame number.
var _ward_step: int = 0
var _ward_at: int = 0


func _ready() -> void:
	# The mode is found by *name* rather than at a fixed index, because this
	# scene is now launched two different ways and they do not agree about where
	# the trailing arguments start. Through `tools/snapshot.gd` the user args are
	# `scene png ticks mode`, so the mode is the fourth; run headless as a plain
	# scene — which is what a check with no picture in it wants — they are just
	# `mode`, and the fourth does not exist. One `find` covers both and cannot be
	# thrown off by a mode being added, which an index can.
	var args := OS.get_cmdline_user_args()
	var at := -1
	for i in args.size():
		if MODES.has(args[i]):
			at = i
			break
	if at >= 0:
		_mode = args[at]
	# A still frame cannot tell "the spear missed" from "the spear hit and the
	# kill was dropped". Add `trace` after the mode to print the flight, or
	# `pov` to watch from the thrower's own camera instead of the touchline.
	var extra: String = args[at + 1] if at >= 0 and args.size() > at + 1 else ""
	_trace = extra == "trace"
	_pov = extra == "pov"

	_build_stage()

	_items = Node3D.new()
	_items.name = "SpawnedItems"
	# `GubCombat._spawn_root` looks for this group; without it every spear and
	# mushroom is parented to the scene root and nothing can be swept up later.
	_items.add_to_group("spawned_items")
	add_child(_items)
	# The lure reports its own catch list unconditionally: unlike a spear, there
	# is no frame in which "who did this pull?" is visible on screen.
	_items.child_entered_tree.connect(_watch_spawned)

	_players = Node3D.new()
	_players.name = "Players"
	add_child(_players)

	_start_session()
	MatchState.player_killed.connect(_on_player_killed)
	MatchState.register_arena(_players, _spawn_points())
	_place_everyone()

	if VIEWS.has(_mode) and not _pov:
		_build_touchline_camera()
	if _mode == "free":
		SceneFlow.recapture_cursor("combat_range")
		_print_controls()


# ---------------------------------------------------------------- session ---

## A one-player host session with no socket, plus however many dummies the mode
## wants written straight into the roster. Faking roster entries is the whole
## trick: `MatchState` spawns a Gub per entry and never asks whether the peer
## behind it is real.
func _start_session() -> void:
	Net.start_offline()
	for i in _dummy_count():
		Net.players[DUMMY_BASE + i] = {
			"name": "Dummy %d" % (i + 1), "team": 0, "ready": true,
		}
	Net.roster_changed.emit()

	var config := Net.config
	# No warmup: a testbed that makes you wait five seconds before it will
	# register a kill is a testbed nobody runs twice.
	config.warmup_time = 0.0
	config.spawn_protection = 0.0
	config.respawn_delay = 3.0
	config.time_limit = 0
	config.kill_limit = 50
	config.spear_recharge = 1.5
	# Short, because this is the one mode whose subject *is* the recharge and it
	# has to run through a dozen of them. The interval being small is also the
	# harder case for the thing being checked: the two clocks that used to
	# measure it have less room to agree by accident.
	if _mode == "recharge":
		config.spear_recharge = 0.15
	# The `ward` mode has to watch a robe burn out inside one run, and twenty
	# real seconds of a config dial is not a check anybody runs twice. The
	# *duration* is shortened and nothing else is: what is being asserted is
	# that the clock ends the robe, not how long the clock is.
	if _mode == "ward":
		config.elder_duration = WARD_DURATION


func _dummy_count() -> int:
	match _mode:
		"lure":
			return 3
		"arc", "miss", "mushroom", "cover", "lure_self", "letter":
			return 1
		# Nobody to shoot at. `recharge` throws a dozen spears over the back
		# wall on purpose (see `RECHARGE_TARGET`) and a dummy in the roster
		# would only be something for one of them to find.
		"recharge":
			return 0
		_:
			return 2


func _spawn_points() -> Array[Transform3D]:
	var out: Array[Transform3D] = [_facing(PLAYER_SPOT, Vector3(0.0, 0.1, 0.0))]
	for spot: Vector3 in DUMMY_SPOTS:
		out.append(_facing(spot, PLAYER_SPOT))
	return out


static func _facing(from: Vector3, towards: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, Gub.yaw_towards(towards - from)), from)


## `MatchState._next_spawn` deliberately shuffles pads so nobody opens on the
## same ledge twice; a testbed wants the opposite. Put everyone back afterwards.
func _place_everyone() -> void:
	var player := MatchState.gubs.get(1) as Gub
	if player != null:
		player.revive_at(_facing(PLAYER_SPOT, Vector3(0.0, 0.1, 0.0)))
	for i in _dummy_count():
		var dummy := MatchState.gubs.get(DUMMY_BASE + i) as Gub
		if dummy != null:
			dummy.revive_at(_facing(DUMMY_SPOTS[i], PLAYER_SPOT))
			_stand_still(dummy)


## Make a dummy read as a remote Gub whose client is publishing "standing on the
## ground, not moving".
##
## A remote Gub takes its whole animation state from replicated fields, and
## nothing replicates for a fake roster entry — so `sync_grounded` sat at its
## default `false` and every dummy played the Jump clip forever, splayed out
## mid-leap in every screenshot this tool has ever produced. That is the same
## class of bug as the real one this testbed found in `GubAnimator`, except here
## the missing publisher is the testbed itself.
func _stand_still(dummy: Gub) -> void:
	dummy.sync_position = dummy.global_position
	dummy.sync_yaw = dummy.body_yaw
	dummy.sync_velocity = Vector3.ZERO
	dummy.sync_grounded = true
	dummy.sync_crouching = false
	dummy.sync_sliding = false


func _on_player_killed(victim_id: int, killer_id: int, cause: int) -> void:
	print("combat_range: %s killed %s (cause %d) at frame %d" % [
		Net.player_name(killer_id), Net.player_name(victim_id), cause, _frames])


# ----------------------------------------------------------------- driving ---

func _physics_process(_delta: float) -> void:
	_frames += 1
	if _trace:
		_trace_frame()
	if _mode == "free":
		# No input reading here any more: `Gub._read_input` does it, for the
		# local Gub, in the game and in this testbed alike. That it only ever
		# happened here is what left the real arena unwalkable.
		return
	if _mode == "walk":
		_drive_walk()
		return
	if _mode == "leave":
		_drive_leave()
		return

	var player := MatchState.gubs.get(1) as Gub
	if player == null:
		return
	var rig := player.get_node_or_null("CameraRig") as GubCamera
	var combat := player.get_node_or_null("Combat") as GubCombat
	if rig == null or combat == null:
		return

	# Re-aim every frame until the moment of the throw. One call lands close and
	# the next few converge, because moving the rig moves the camera it solved
	# from — see `GubCamera.look_at_point`.
	_aim_at = _target_point()
	if not _acted:
		rig.look_at_point(_aim_at)

	# `aim` never throws. It holds the button down and leaves the rig pointed at
	# the wall, which is the state the drop indicator exists in — and the state
	# no other mode here spends a single frame in, because every other mode's
	# job is to get the projectile out of the hand.
	if _mode == "aim":
		Input.action_press("aim")
		_report_aim(combat)
		return

	# Both of these run several actions in sequence rather than one, so they own
	# their own frame counting and never reach the single-shot `_acted` block
	# below. They keep re-aiming above for free, which is what the second half of
	# each of them needs.
	if _mode == "cover":
		_drive_cover(player, combat)
		return
	if _mode == "recharge":
		_drive_recharge(player, combat)
		return
	if _mode == "ward":
		_drive_ward(combat)
		return

	# Not a `return`: the card has to be put down before there is anything to
	# report, and the drop happens in the acted block below like every other
	# mode's action.
	if _mode == "letter":
		_report_letter(combat)

	# Same shape and the same reason: the cards go down in the acted block below,
	# so there is nothing to measure until they are there.
	if _mode == "cards":
		_report_cards()

	# Two actions, not one — the robe has to be on the ground and picked up
	# before there is anything to fire — so the cast lives outside the `_acted`
	# block and waits on the Elder state rather than on a frame number.
	if _mode == "lightning":
		_drive_lightning(combat)

	# Twenty frames is enough for the rig to settle onto the target and for the
	# spawn-frame transforms to have been published.
	#
	# Note what "acted" means for a spear since D-025: the click, not the throw.
	# `GubCombat.try_throw_spear` only starts the windup, and the spear leaves
	# the hand THROW_RELEASE_TIME later — so a mode that waits for a spear has
	# to allow the windup before the projectile even exists, and its whole
	# flight after that. With the new `Throw` clip that is 0.71 s, which at 60
	# ticks a second is 42.5 ticks: frame 20 + 42.5 = tick 63 before the spear
	# is in the air, then 14 m at 42 m/s (0.33 s, 20 ticks) to the dummy, so the
	# kill lands around tick 83. The warmup counts in `tools/smoke_test.sh` are
	# sized for that — 110 for the kill, and the lure's 132 is untouched because
	# the lure leaves on the click.
	if _frames < 20 or _acted:
		return
	_acted = true
	match _mode:
		"mushroom":
			_stock(combat)
			combat.try_place_mushroom()
		"lure", "lure_self":
			_stock(combat)
			combat.try_throw_lure()
		"letter":
			_drop_a_letter()
		"cards":
			_drop_the_alphabet()
		"lightning":
			_drop_a_robe()
		_:
			combat.try_throw_spear()


## Put one letter card down at the player's feet and let them walk into it.
##
## Deliberately *not* handed over the way `_stock` hands over a mushroom. The
## card comes out of a real death, through `MatchState._drop_loot`'s own roll
## with `letter_drop_chance` forced to 1 so it cannot come up a lure, and it is
## claimed by the player's own body entering the `Pickup` area. That makes this
## the only place the whole chain runs in a world with geometry in it — which
## matters because the failure it guards is not a script error: an `Area3D` that
## tries to stop monitoring from inside `body_entered` logs a plain `ERROR` and
## the smoke gate walks straight past it.
##
## The drop lands at the point the blow was struck rather than at the body, so
## the card can be set down in front of the player without moving anybody.
func _drop_a_letter() -> void:
	var player := MatchState.gubs.get(1) as Gub
	if player == null:
		return
	Net.config.win_condition = MatchConfig.WinCondition.LETTERS
	Net.config.letter_drop_chance = 1.0
	# Long enough that the frame is still mid-hold whenever the snapshot lands.
	Net.config.letter_hold_time = 30.0
	MatchState.report_kill(DUMMY_BASE, 1, Gub.Cause.SPEAR,
		player.global_position + player.facing() * 1.2,
		Vector3.FORWARD * 18.0, "Spine1")


## Put one of each letter on the ground, three metres in front of the player.
##
## The one call in this file that reaches into a private. `_drop_a_letter` above
## goes the long way round on purpose — a real death, a real roll — and it gets
## whatever letter `randi() % 3` handed it, which is exactly right for a mode
## about the *hold* and useless for a mode about the three meshes. Naming them
## is the only way to have G, U and B in one frame.
##
## z = 6.0 is three metres ahead of `PLAYER_SPOT`, comfortably outside
## `Pickup.CATCH_RADIUS`, so the player standing there cannot collect one out of
## the shot. The win condition is set first because a letter that drops in a
## kills match is a letter nothing will do anything with.
func _drop_the_alphabet() -> void:
	Net.config.win_condition = MatchConfig.WinCondition.LETTERS
	for i in MatchState.LETTERS.size():
		MatchState._spawn_drop(Pickup.Kind.LETTER, MatchState.LETTERS[i],
			Vector3(-1.2 + 1.2 * i, PLAYER_SPOT.y, 6.0))


## Say how tall the three cards actually stand.
##
## The one thing a still frame of this cannot settle: a letter at half the
## height it should be is still, unmistakably, a letter. So the height is
## measured off the mesh itself — its own AABB times whatever scale it ended up
## with — rather than read back off the constant that put it there, which would
## prove only that the constant equals itself.
func _report_cards() -> void:
	if _frames != 60:
		return
	var cards: Array = MatchState._pickups.values()
	var parts: Array[String] = []
	var reason := ""
	if cards.size() != MatchState.LETTERS.size():
		reason = "%d on the ground, wanted %d" % [cards.size(), MatchState.LETTERS.size()]
	for card: Pickup in cards:
		var glyph := MatchState.letter_name(card.letter)
		var meshes := card.find_children("*", "MeshInstance3D", true, false)
		if meshes.is_empty():
			parts.append("%s no mesh" % glyph)
			reason = "the %s has no mesh under it" % glyph
			continue
		var mesh := meshes[0] as MeshInstance3D
		var tall := mesh.get_aabb().size.y * mesh.global_basis.get_scale().y
		parts.append("%s %.2f m" % [glyph, tall])
		if absf(tall - Pickup.LETTER_HEIGHT) > 0.05:
			reason = "the %s stands %.2f m, wanted %.2f" % [glyph, tall, Pickup.LETTER_HEIGHT]
	var verdict := "cards PASS" if reason.is_empty() else "cards FAIL (%s)" % reason
	print("combat_range: cards on the ground — %s — %s" % [", ".join(parts), verdict])


## Put one Elder robe down at the player's feet and let them walk into it.
##
## The far dummy is the one killed, so the near one is still standing to be shot
## at — and, exactly as `_drop_a_letter` does, the drop is placed at the *blow*
## rather than at the body, so the robe can be set down in front of the player
## without moving anybody.
##
## Through `_drop_loot`'s own roll with `elder_drop_chance` forced to 1, never by
## handing the state over: the roll, the `Pickup` area's overlap,
## `claim_pickup`, `_do_set_elder` and the re-parent of the cloth onto a live
## skeleton are all part of what this mode is for. Only `tools/preview_elder.gd`
## has ever done that attach before, and it does it in a scene with one Gub in
## it and no match running.
func _drop_a_robe() -> void:
	var player := MatchState.gubs.get(1) as Gub
	if player == null:
		return
	Net.config.elder_drop_chance = 1.0
	MatchState.report_kill(DUMMY_BASE + 1, 1, Gub.Cause.SPEAR,
		player.global_position + player.facing() * 1.2,
		Vector3.FORWARD * 18.0, "Spine1")


## Cast once the robe is on, then say whether anybody died.
##
## The verdict is the whole point. A still frame of a bolt looks the same
## whether the Gub at the far end of it fell over or not, and "the spectacle
## works and the weapon does nothing" is precisely the failure a rendered check
## is here to catch.
func _drive_lightning(combat: GubCombat) -> void:
	if _cast_at == 0:
		if not MatchState.is_elder(1) or not combat.has_lightning():
			return
		_cast_at = _frames
		var hand := (MatchState.gubs.get(1) as Gub).held_spear
		print("combat_range: robe claimed on frame %d — Elder, spear %s, crackle %s"
			% [_frames, combat.has_spear(), hand != null and hand.is_charged()])
		# The same call a click makes. `try_throw_spear` is the Elder's cast as
		# well as the Gub's throw — it branches on the robe (D-038) — and going
		# through it rather than at `try_cast_lightning` is what makes this mode
		# exercise the path a player's mouse actually takes.
		combat.try_throw_spear()
		return
	if _frames != _cast_at + LIGHTNING_VERDICT_DELAY:
		return
	var target := MatchState.gubs.get(DUMMY_BASE) as Gub
	if target != null and not target.alive:
		print("combat_range: the bolt killed %s — lightning PASS" % target.display_name)
	else:
		print("combat_range: nothing at the far end died — lightning FAIL")


# -------------------------------------------------------------------- ward ---

## Put the robe on a *dummy* and throw a real spear at it (D-040).
##
## Three verdicts out of one run, in this order and for this reason:
##
##   1. `ward`    — a spear thrown at an Elder must not kill it.
##   2. `expiry`  — the robe must then come off **by itself**, on
##                  `MatchState._tick_elders` running in a real match loop.
##   3. `control` — the *same* throw at the *same* Gub, once the robe is off,
##                  must kill it. Without this the first verdict is worth
##                  nothing: a spear that never left the hand, a dummy that was
##                  already dead, a `report_kill` that never arrived — every one
##                  of those sails through "did not die", and the gate would go
##                  green on invincibility that had been implemented as a
##                  `return` at the top of the throw.
##
## That control is the whole lesson of D-039 restated. The mushroom passed a
## green gate for its entire life while stopping nothing, because the only thing
## anybody had ever asserted about it was that a PNG got written.
##
## The Elder here is a dummy rather than the player, which is the opposite way
## round from the `lightning` mode next door and is the only way to get a real
## spear into the air at one: the player is the only Gub in this scene with a
## camera to aim and a hand to throw from.
func _drive_ward(combat: GubCombat) -> void:
	var dummy := MatchState.gubs.get(DUMMY_BASE) as Gub
	if dummy == null:
		return

	match _ward_step:
		0:
			# Late enough for both Gubs to have settled onto the ground and for
			# the spawn-frame transforms to have been published.
			if _frames < 12:
				return
			_robe_at_the_dummys_feet(dummy)
			_ward_step = 1
		1:
			# On the Elder state and not on a frame count, because what stands
			# between the drop and the robe is an `Area3D` overlap resolving —
			# and because a mode that threw its spear before the robe was on
			# would be checking that a spear kills a Gub, which is the one thing
			# every other mode here already proves.
			if not MatchState.is_elder(DUMMY_BASE):
				return
			# Both claims, printed together: the rules say Elder and the cloth
			# is on the skeleton. A dummy that is the Elder in the bookkeeping
			# and a plain Gub on screen would make the verdict below true for
			# entirely the wrong reason.
			print("combat_range: %s took the robe on frame %d — Elder %s, worn %s, %.1f s left"
				% [dummy.display_name, _frames, MatchState.is_elder(DUMMY_BASE),
					dummy.elder_robe != null and dummy.elder_robe.is_worn(),
					MatchState.elder_remaining(DUMMY_BASE)])
			combat.try_throw_spear()
			_ward_at = _frames
			_ward_step = 2
		2:
			if _frames < _ward_at + SPEAR_VERDICT_DELAY:
				return
			if dummy.alive:
				print("combat_range: the spear did not kill the Elder — ward PASS")
			else:
				print("combat_range: %s died wearing the robe — ward FAIL"
					% dummy.display_name)
			_ward_at = _frames
			_ward_step = 3
		3:
			if not MatchState.is_elder(DUMMY_BASE):
				print("combat_range: the robe burned out on frame %d — its %.1f s were up — expiry PASS"
					% [_frames, WARD_DURATION])
				_ward_step = 4
				return
			if _frames - _ward_at > WARD_EXPIRY_LIMIT:
				print("combat_range: the robe never burned out — expiry FAIL")
				get_tree().quit()
			return
		4:
			# On the throw gate, exactly as `cover`'s control throw is: a
			# hardcoded wait here becomes a throw that never happened the day
			# `spear_recharge` is retuned, and a control that never fires is a
			# control that always passes.
			if not combat.has_spear():
				return
			combat.try_throw_spear()
			_ward_at = _frames
			_ward_step = 5
		5:
			if _frames < _ward_at + SPEAR_VERDICT_DELAY:
				return
			if not dummy.alive:
				print("combat_range: the same throw with the robe gone killed %s — control PASS"
					% dummy.display_name)
			else:
				print("combat_range: nothing was protecting anybody and nobody died — control FAIL")
			get_tree().quit()


## Drop one Elder robe on top of the near dummy and let it walk into its own
## feet.
##
## The far dummy is the one killed, so the near one — the target of every throw
## in this file — is still standing to wear it. Through `_drop_loot`'s own roll
## with `elder_drop_chance` forced to 1, and placed at the **blow** rather than
## at the body, which is the same trick `_drop_a_letter` and `_drop_a_robe` use
## to set an item down somewhere other than where the corpse is.
##
## Collection is then the shipping path and not a hand-over: the `Pickup`'s
## `Area3D` finds the dummy's collision body already inside it on the next
## physics step and calls `MatchState.claim_pickup` itself. A dummy is a remote
## Gub with no client behind it and cannot be walked anywhere, so dropping the
## robe *under* one is the only way to make that overlap happen — and it is
## worth the trouble, because `claim_pickup` called by hand would skip the one
## part of the chain that has ever actually been broken (D-039's note about an
## `Area3D` that cannot stop monitoring from inside `body_entered`).
func _robe_at_the_dummys_feet(dummy: Gub) -> void:
	Net.config.elder_drop_chance = 1.0
	MatchState.report_kill(DUMMY_BASE + 1, 1, Gub.Cause.SPEAR,
		dummy.global_position, Vector3.FORWARD * 18.0, "Spine1")


## Say what the Gub is holding, so a run means something without opening the
## PNG. The two halves that must agree are printed together on purpose: a hold
## with a spear still in the hand is the bug this mode exists to catch.
func _report_letter(combat: GubCombat) -> void:
	if _frames != 60:
		return
	var player := MatchState.gubs.get(1) as Gub
	var hand := player.held_spear if is_instance_valid(player) else null
	print("combat_range: holding %s with %.1f s left — can throw %s, shaft shown %s, card shown %s" % [
		MatchState.letter_name(MatchState.letter_hold_letter(1)),
		MatchState.letter_hold_remaining(1), combat.has_spear(),
		hand != null and hand.is_carried(), hand != null and hand.has_letter()])


# ------------------------------------------------------------------- cover ---

## Stand a mushroom up in front of a dummy, prove it is cover, prove the proof
## means something, and then walk into it.
##
## Three verdicts out of one run, in this order and for this reason:
##
##   1. `cover`   — a spear thrown at a Gub standing behind a mushroom must not
##                  kill it.
##   2. `control` — the *same* throw, after the mushroom has withered, must kill
##                  it. Without this the first verdict is worth nothing: a spear
##                  that had stopped killing anybody at all — a broken launch, a
##                  dummy that was already dead, a `report_kill` that never
##                  arrived — sails straight through "did not die", and the gate
##                  goes green on a mushroom that stops nothing.
##   3. `solid`   — a Gub walking into one is held off at the edge of the cap
##                  instead of wading into the middle of it.
##
## This is the check the mushroom spent its whole life without. The `mushroom`
## mode above asserts `snapshot: wrote`, which proves a PNG exists, and while it
## was passing the collision cap sat 31 cm above the head of the tallest thing
## it was supposed to be hiding, with nothing in a Gub's height band but a
## 0.55 m post. Nothing anywhere ever asked it to stop anything. See D-039.
func _drive_cover(player: Gub, combat: GubCombat) -> void:
	var dummy := MatchState.gubs.get(DUMMY_BASE) as Gub
	if dummy == null:
		return

	match _cover_step:
		0:
			# Late enough for both Gubs to have settled onto the ground, early
			# enough that the mushroom is standing before anything is aimed.
			if _frames < 10:
				return
			_cover_mushroom = _plant_a_mushroom(dummy.global_position, PLAYER_SPOT,
				COVER_OFFSET)
			_cover_step = 1
		1:
			# A frame later, and that is not a stylistic pause. A `StaticBody3D`
			# added to the tree does not exist to the physics server until the
			# next step, so a ray fired on the frame it was planted reports a
			# mushroom 0.00 m wide at every height — which is a convincing
			# picture of exactly the bug being measured, and wrong.
			_report_cover_profile(_cover_mushroom, dummy, player)
			_cover_step = 2
		2:
			if _frames < 20:
				return
			combat.try_throw_spear()
			_cover_at = _frames
			_cover_step = 3
		3:
			if _frames < _cover_at + SPEAR_VERDICT_DELAY:
				return
			if dummy.alive:
				print("combat_range: the spear did not get through — cover PASS")
			else:
				print("combat_range: %s died behind a mushroom — cover FAIL"
					% dummy.display_name)
			# Withered rather than freed: that is what a mushroom does at the
			# end of its life, and it is the path the collision layer is
			# actually cleared on, so the control throw flies through the same
			# hole a real one would.
			if is_instance_valid(_cover_mushroom):
				_cover_mushroom.wither()
			_cover_step = 4
		4:
			# On the gate rather than on a frame number, exactly as `lightning`
			# waits for the robe. A hardcoded wait here would quietly become a
			# throw that never happened the day `spear_recharge` is retuned, and
			# a control that never fires is a control that always passes.
			if not combat.has_spear():
				return
			combat.try_throw_spear()
			_cover_at = _frames
			_cover_step = 5
		5:
			if _frames < _cover_at + SPEAR_VERDICT_DELAY:
				return
			if not dummy.alive:
				print("combat_range: the same throw with the mushroom gone killed %s — control PASS"
					% dummy.display_name)
			else:
				print("combat_range: nothing was blocking and nobody died — control FAIL")
			# And now one in the player's own way, to lean on.
			_cover_mushroom = _plant_a_mushroom(player.global_position,
				player.global_position + player.facing() * 10.0, 0.0)
			Input.action_press("move_forward")
			_cover_at = _frames
			_cover_step = 6
		6:
			_watch_cover_approach(player)
			if _frames < _cover_at + COVER_WALK_FRAMES:
				return
			Input.action_release("move_forward")
			_report_cover_solid()
			get_tree().quit()


## Stand one up the way the ability does: `MUSHROOM_DISTANCE` in front of a Gub,
## along the line to whatever it is taking cover from, on the ground.
##
## Through `ShieldMushroom.plant` and the same packed scene `GubCombat` loads,
## rather than through `try_place_mushroom`, and the difference is worth being
## explicit about because this file's own `_stock` comment is about exactly this
## kind of shortcut. `try_place_mushroom` reads the *player's* camera and can
## only ever put one in front of the player; what this mode needs first is one
## in front of the dummy. Everything past the placement — the collision build,
## the layer, the eruption, the lifetime — is the shipping code either way, and
## the `mushroom` mode next door is the one that walks the placement path.
func _plant_a_mushroom(behind: Vector3, towards: Vector3,
		offset: float) -> ShieldMushroom:
	var forward := towards - behind
	forward.y = 0.0
	forward = forward.normalized()
	var spot := behind + forward * GubCombat.MUSHROOM_DISTANCE 		+ forward.cross(Vector3.UP) * offset
	# The stage is one flat slab at y = 0 (see `_build_ground`), which is what
	# `_mushroom_spot`'s downward ray would find anyway.
	spot.y = 0.0
	var mushroom := MUSHROOM.instantiate() as ShieldMushroom
	_items.add_child(mushroom)
	# Long enough that nothing in this run is ever waiting on a wither it did
	# not ask for; step 2 takes the first one away by hand.
	mushroom.plant(spot, Gub.yaw_towards(-forward), COVER_LIFETIME, 1)
	return mushroom


## How wide the mushroom actually is, height by height, measured with the
## physics rather than read off the constants in `shield_mushroom.gd`.
##
## Rays on the deployable layer alone, so what comes back is the mushroom and
## nothing else — not the ground it stands on and not the Gub behind it. The
## bands run well past the top of the cap on purpose: the failure this was
## written for was a cap that had floated *above* everything it was covering,
## and a profile that stopped at a Gub's head would have shown an empty column
## with no explanation in it.
##
## The last line is the one that answers the question a player would ask. A
## profile says how wide the thing is; what anybody standing behind it cares
## about is how much of *them* it hides, so the silhouette of a standing Gub is
## sampled point by point along the line to a thrower fourteen metres away and
## the share of it that is behind cover is printed as a percentage.
func _report_cover_profile(mushroom: Node3D, target: Gub, thrower: Gub) -> void:
	var space := get_world_3d().direct_space_state
	var axis := mushroom.global_position
	print("combat_range: mushroom collision, measured on layer %d at %.0f cm across."
		% [ShieldMushroom.LAYER_DEPLOYABLE, PROFILE_SAMPLE * 100.0])
	print("              A Gub stands 0.00-%.2f m, crouches to %.2f, has its eyes at %.2f,"
		% [Gub.STAND_HEIGHT, Gub.CROUCH_HEIGHT, thrower.eye_height()])
	print("              and its antennae reach 1.80 m — above the hitbox, and meant to show.")
	var y := PROFILE_STEP
	while y <= PROFILE_TOP:
		var width := _blocked_width(space, axis, y)
		# One # per 10 cm, so the shape of the thing is legible in the log
		# without anybody having to plot the numbers.
		var bar := ""
		for _i in int(round(width * 10.0)):
			bar += "#"
		var note := ""
		if absf(y - Gub.STAND_HEIGHT) < PROFILE_STEP * 0.5:
			note = "   <- the top of a standing Gub"
		print("              y %.2f m  %.2f m wide  %s%s" % [y, width, bar, note])
		y += PROFILE_STEP
	var eye := thrower.global_position + Vector3.UP * thrower.eye_height()
	# Two stances, because they are two different questions and only the first
	# one is flattering. Squarely behind your own cover is what the ability is
	# for; half a metre out of line is what a fight does to you within a second
	# of it starting, and it is the number the cap's *width* has to answer.
	var square := _behind(axis, eye, GubCombat.MUSHROOM_DISTANCE)
	print("              squarely behind it, a standing Gub is %.0f%% hidden from %.1f m"
		% [_hidden_fraction(space, square, eye) * 100.0, eye.distance_to(square)])
	print("              standing %.2f m out of line, as the dummy is, %.0f%%"
		% [COVER_OFFSET, _hidden_fraction(space, target.global_position, eye) * 100.0])


## The spot `MUSHROOM_DISTANCE` behind a mushroom on the line from the thrower:
## where a Gub that planted this thing and did not move would be standing.
func _behind(axis: Vector3, eye: Vector3, distance: float) -> Vector3:
	var away := axis - eye
	away.y = 0.0
	return axis + away.normalized() * distance


## How much of the mushroom is in the way at one height, in metres, found by
## firing a comb of rays straight through it.
func _blocked_width(space: PhysicsDirectSpaceState3D, axis: Vector3, y: float) -> float:
	var blocked := 0
	var dx := -PROFILE_HALF_WIDTH
	while dx <= PROFILE_HALF_WIDTH:
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(axis.x + dx, y, axis.z + 4.0),
			Vector3(axis.x + dx, y, axis.z - 4.0))
		query.collision_mask = ShieldMushroom.LAYER_DEPLOYABLE
		if not space.intersect_ray(query).is_empty():
			blocked += 1
		dx += PROFILE_SAMPLE
	return blocked * PROFILE_SAMPLE


## What share of a standing Gub a thrower cannot see, because the mushroom is in
## the way.
##
## The silhouette is the collision capsule rather than the mesh, because the
## capsule is what a spear can actually hit: a Gub is 1.80 m of model inside
## 1.55 m of hitbox (see `Gub.STAND_HEIGHT`), and the 25 cm of head and antennae
## above it are exactly the part that is *supposed* to be showing over the top of
## cover. The half-widths follow the capsule's real shape, hemispheres included,
## so the samples near the feet and the crown are not counted as though the body
## were a box.
func _hidden_fraction(space: PhysicsDirectSpaceState3D, at: Vector3,
		eye: Vector3) -> float:
	var flat := at - eye
	flat.y = 0.0
	# Across the line of sight, so the samples sweep the silhouette rather than
	# some arbitrary slice through it.
	var across := flat.normalized().cross(Vector3.UP)
	var radius := Gub.CAPSULE_RADIUS
	var samples := 0
	var hidden := 0
	for row in SILHOUETTE_ROWS:
		var y := (row + 0.5) / float(SILHOUETTE_ROWS) * Gub.STAND_HEIGHT
		# The capsule narrows into a hemisphere at each end; anywhere between
		# them it is a cylinder at full width.
		var half := radius
		if y < radius:
			half = sqrt(maxf(0.0, radius * radius - (radius - y) * (radius - y)))
		elif y > Gub.STAND_HEIGHT - radius:
			var above := y - (Gub.STAND_HEIGHT - radius)
			half = sqrt(maxf(0.0, radius * radius - above * above))
		for col in SILHOUETTE_COLS:
			var t := (col + 0.5) / float(SILHOUETTE_COLS) * 2.0 - 1.0
			var point := at + Vector3.UP * y + across * (t * half)
			var query := PhysicsRayQueryParameters3D.create(eye, point)
			query.collision_mask = ShieldMushroom.LAYER_DEPLOYABLE
			samples += 1
			if not space.intersect_ray(query).is_empty():
				hidden += 1
	return float(hidden) / float(samples) if samples > 0 else 0.0


## How close the walking Gub has come to the middle of the mushroom in its way.
##
## A running minimum rather than a final position, because a `CharacterBody3D`
## pressed into a cylinder slides around it: where the Gub ends up says nothing
## about whether it was stopped, and how far in it ever got says everything.
func _watch_cover_approach(player: Gub) -> void:
	if not is_instance_valid(_cover_mushroom):
		return
	var axis := _cover_mushroom.global_position
	_cover_closest = minf(_cover_closest, Vector2(
		player.global_position.x - axis.x,
		player.global_position.z - axis.z).length())


## Was the Gub held off by the cap, or did it walk in under it?
##
## The threshold is derived from the two radii rather than typed in, so it
## follows the constants instead of having to be remembered alongside them.
## What it is really asking is *where* the solid part of the mushroom is: a Gub
## that gets within its own width of the axis has found nothing at its own
## height but the stem, which is the bug this whole mode exists for.
func _report_cover_solid() -> void:
	var hold_off := ShieldMushroom.CAP_RADIUS + Gub.CAPSULE_RADIUS - COVER_HOLD_OFF_SLACK
	if _cover_closest >= hold_off:
		print("combat_range: walked into it and was held %.2f m off the middle (wanted %.2f) — solid PASS"
			% [_cover_closest, hold_off])
	else:
		print("combat_range: walked to %.2f m of the middle of a cap %.2f m across — solid FAIL"
			% [_cover_closest, ShieldMushroom.CAP_RADIUS * 2.0])


# ---------------------------------------------------------------- recharge ---

## Throw until the spear has grown back a dozen times, then take it out of the
## hand and see whether anything ever asks for it again.
##
## Two halves, because the bug has two shapes. The first is the bug as a player
## meets it: throw, wait, and require the shaft to be in the fist at the end of
## every cycle. The second is the *property* that stops it coming back — see
## `_drive_desync`.
##
## The invariant is checked on every frame rather than once a cycle, and stated
## as a count of consecutive frames the hand and the throw gate disagreed for.
## That is what tells one or two frames of ordinary repaint lag apart from a
## shaft that is never coming back, which is the only distinction that matters
## here: "not reliably" is a duration, not a boolean.
func _drive_recharge(player: Gub, combat: GubCombat) -> void:
	var hand := player.held_spear
	if hand == null or _frames < 20:
		return
	if _recharge_cycles >= RECHARGE_CYCLES:
		_drive_desync(combat, hand)
		return

	if combat.has_spear() and not hand.is_carried():
		_hand_out_of_step += 1
		_worst_out_of_step = maxi(_worst_out_of_step, _hand_out_of_step)
	else:
		_hand_out_of_step = 0

	if not combat.has_spear():
		return
	if not hand.is_carried():
		if _hand_out_of_step <= HAND_SYNC_GRACE:
			return
		# Armed for a tenth of a second with an empty fist. Whatever was meant
		# to put the shaft back is not going to — so the cycle is counted as
		# failed, and the shaft is put back *by the testbed* so the run carries
		# on and measures the next eleven instead of stopping at the first.
		_recharge_failures += 1
		print("combat_range: cycle %d — the gate opened %d frames ago and the fist is still empty"
			% [_recharge_cycles + 1, _hand_out_of_step])
		hand.set_carried(true)
		_hand_out_of_step = 0

	# Armed with a spear in hand: one good cycle. The first time round that is
	# only the state a Gub spawns in, so it is not counted as a regrow.
	if _recharge_thrown > 0:
		_recharge_cycles += 1
	_recharge_thrown += 1
	if _recharge_cycles < RECHARGE_CYCLES:
		combat.try_throw_spear()


## The other half, and the deterministic one.
##
## A dozen real cycles will catch the race if this machine happens to lose it,
## and prove nothing whatsoever if it happens to win twelve in a row — which is
## the trouble with checking a race by running it. So the last thing this mode
## does is create, on purpose, the exact state the race leaves behind: the throw
## gate says armed and the fist is empty.
##
## A hand repainted by a one-shot timer has already had its chance and stays
## empty for ever. A hand that is *polled* notices on the next frame. Nothing in
## the game reaches in and does this to itself; this is the fault stated
## directly rather than waited for, and it is the half of this check that cannot
## pass by luck.
func _drive_desync(combat: GubCombat, hand: HeldSpear) -> void:
	if _desync_at == 0:
		if not combat.has_spear() or not hand.is_carried():
			return
		_desync_at = _frames
		hand.set_carried(false)
		return
	if hand.is_carried():
		_desync_recovered = _frames - _desync_at
		_report_recharge()
		get_tree().quit()
		return
	if _frames - _desync_at < DESYNC_PATIENCE:
		return
	_report_recharge()
	get_tree().quit()


func _report_recharge() -> void:
	var came_back := _desync_recovered >= 0 and _desync_recovered <= HAND_SYNC_GRACE
	if _recharge_failures == 0 and came_back:
		print("combat_range: %d regrows, a spear in the fist at the end of every one (worst lag %d frames), and an emptied fist refilled itself in %d — recharge PASS"
			% [_recharge_cycles, _worst_out_of_step, _desync_recovered])
		return
	if _recharge_failures > 0:
		print("combat_range: %d of %d regrows left the fist empty with the gate open — recharge FAIL"
			% [_recharge_failures, _recharge_cycles])
	if not came_back:
		print("combat_range: the fist was emptied with the gate open and %s — recharge FAIL"
			% ("nothing ever put the spear back" if _desync_recovered < 0
				else "it took %d frames to notice" % _desync_recovered))


## Put one mushroom and one lure in the Gub's hands.
##
## This is the testbed supplying by hand something the real game supplies some
## other way, which is the exact shape of every integration bug this project has
## had (D-018, D-019) — so it is worth saying plainly what is *not* being
## checked here. A Gub spawns with nothing now and everything it gets comes off
## a corpse (D-032), so between `MatchState._drop_loot`, the `Pickup` area and
## `MatchState.claim_pickup` there is a whole path from "somebody died" to
## "somebody is holding a mushroom" that this call steps over. `playthrough` is
## what walks it: it kills people in a real arena, which is what makes drops
## spawn at all.
##
## It goes through `grant_mushroom`/`grant_lure` rather than poking a counter,
## so what it hands out arrives the same way a pickup's would — host-side, and
## broadcast.
func _stock(combat: GubCombat) -> void:
	combat.grant_mushroom(1)
	combat.grant_lure(1)


## Say where the ring ended up. A still frame shows a yellow circle on some
## dirt; only a number says whether that dirt is the dirt the ballistics picked,
## and the gap between it and the aim point *is* the drop the testers asked
## about.
func _report_aim(combat: GubCombat) -> void:
	# Late enough that `look_at_point` has converged and the rig has finished
	# easing into the aimed field of view.
	if _frames != 60:
		return
	var marker := combat.get_parent().get_node_or_null("AimMarker") as Node3D
	if marker == null or not marker.visible:
		print("combat_range: aiming at %v — no landing ring" % _aim_at)
		return
	var landing := marker.global_position
	print("combat_range: aiming at %v, spear lands at %v (%.1f m short, %.1f m low)"
		% [_aim_at, landing, _aim_at.distance_to(Vector3(landing.x, _aim_at.y, landing.z)),
			_aim_at.y - landing.y])


func _target_point() -> Vector3:
	match _mode:
		"arc":
			return ARC_TARGET
		"aim":
			return AIM_TARGET
		"recharge":
			return RECHARGE_TARGET
		"miss":
			return Vector3(0.0, 0.05, -14.0)
		"lure":
			return DUMMY_SPOTS[1] + Vector3.UP * 0.2
		"lure_self":
			# Just in front of the player's own feet, so the pull has something
			# to drag and the camera has something to show.
			return PLAYER_SPOT + Vector3(0.0, 0.05, -3.0)
		_:
			var dummy := MatchState.gubs.get(DUMMY_BASE) as Gub
			if dummy == null:
				return Vector3(0.0, 1.0, -5.0)
			return dummy.global_position + Vector3.UP * dummy.eye_height()


## Say what a spear actually hit, which is the one thing a still frame cannot.
func _watch_spawned(node: Node) -> void:
	if node.has_signal("caught"):
		node.connect("caught", func(victim_ids: Array) -> void:
			var names: Array[String] = []
			for id: int in victim_ids:
				names.append(Net.player_name(id))
			print("combat_range: lure caught %d — %s"
				% [victim_ids.size(), ", ".join(names) if names else "nobody"]))
		return
	var spear := node as SpearProjectile
	if spear == null or not _trace:
		return
	spear.struck_gub.connect(func(victim: Gub, point: Vector3, bone: String) -> void:
		print("  >> struck %s at %v (bone %s)" % [victim.display_name, point, bone]))
	spear.struck_world.connect(func(point: Vector3, normal: Vector3) -> void:
		print("  >> struck world at %v normal %v" % [point, normal]))


## Where everything is, once a frame. Deliberately noisy — it is only on when
## `trace` is passed, and it is the difference between "it missed" and "it hit
## and nothing happened".
func _trace_frame() -> void:
	if _frames == 1:
		print("combat_range: mode=%s phase=%d host=%s offline=%s gubs=%d" % [
			_mode, MatchState.phase, Net.is_host, Net.is_offline,
			MatchState.gubs.size()])
		for peer_id: int in MatchState.gubs:
			var gub: Gub = MatchState.gubs[peer_id]
			print("  gub %d %s at %v local=%s alive=%s" % [
				peer_id, gub.display_name, gub.global_position,
				gub.is_local(), gub.alive])
	if _frames == 2:
		print("combat_range: frame 2 phase=%d (want %d = PLAYING) timer=%f" % [
			MatchState.phase, MatchState.Phase.PLAYING, MatchState._phase_timer])
	if not _acted:
		return
	for child in _items.get_children():
		var spear := child as SpearProjectile
		if spear == null:
			print("  f%d %s at %v" % [_frames, child.name, (child as Node3D).global_position])
			continue
		print("  f%d spear at %v stuck=%s auth=%s" % [
			_frames, spear.global_position, spear.is_stuck(), spear.authoritative])


## Pull the peer out from under a live Gub and keep processing it.
##
## `announce` is false so that `left_lobby` does not fire and navigate this
## testbed away: the point is to hold the game in the state it is in during the
## fade, with Gubs still in the tree and `multiplayer.multiplayer_peer` already
## null, and keep ticking them there.
func _drive_leave() -> void:
	if _frames == 30:
		Net.leave_lobby(Net.Leave.LOCAL_REQUEST, "", false)
		return
	if _frames < 90:
		return
	print("combat_range: ticked %d frames after teardown — leave PASS" % 60)
	get_tree().quit()


## Hold W for a second and see whether the Gub went anywhere.
##
## `Input.action_press` is a real press as far as everything downstream is
## concerned, so this exercises the same path a player does: `Gub._read_input`
## reads the action, fills `input_direction`, and `_handle_movement` does the
## rest. Nothing here touches `input_direction` itself — that would test the
## movement code while skipping the wiring that was actually missing.
func _drive_walk() -> void:
	var player := MatchState.gubs.get(1) as Gub
	if player == null:
		return

	# Let it settle onto the ground before the start position is taken.
	if _frames < 20:
		return
	if _frames == 20:
		_walk_from = player.global_position
		Input.action_press("move_forward")
		return
	if _frames < 80:
		return

	Input.action_release("move_forward")
	var travelled := player.global_position.distance_to(_walk_from)
	if travelled >= WALK_MIN_DISTANCE:
		print("combat_range: walked %.2f m — walk PASS" % travelled)
	else:
		print("combat_range: walked %.2f m, wanted %.2f — walk FAIL"
			% [travelled, WALK_MIN_DISTANCE])
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().quit()


func _print_controls() -> void:
	print("combat_range: WASD move, Shift sprint, Ctrl crouch, Space jump,")
	print("              LMB spear, Q mushroom, E lure, RMB aim, Esc quit.")


# ------------------------------------------------------------------ stage ---

func _build_touchline_camera() -> void:
	var view: Dictionary = VIEWS[_mode]
	_fixed_camera = Camera3D.new()
	_fixed_camera.fov = view["fov"]
	_fixed_camera.far = 400.0
	_fixed_camera.look_at_from_position(view["eye"], view["look"], Vector3.UP)
	add_child(_fixed_camera)
	# Claimed after the Gubs exist, so it wins over the local rig's own camera.
	_fixed_camera.make_current()


func _build_stage() -> void:
	_build_ground()
	_build_cover()
	_build_lighting()


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	add_child(body)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(90, 1, 90)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 90)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.15, 0.13)
	mat.roughness = 0.95
	# A metre grid, so a still frame says how far the spear actually went.
	mat.uv1_scale = Vector3(45, 45, 1)
	plane.material = mat
	mesh.mesh = plane
	body.add_child(mesh)


## A back wall and two blocks: something for a long throw to stick into, and
## something to duck behind.
func _build_cover() -> void:
	var layout := [
		{"pos": Vector3(0, 3.0, -36), "size": Vector3(46, 6, 1)},
		{"pos": Vector3(-9, 0.9, -8), "size": Vector3(2.4, 1.8, 2.4)},
		{"pos": Vector3(8, 1.4, -16), "size": Vector3(3, 2.8, 3)},
	]
	for entry: Dictionary in layout:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.position = entry["pos"]
		add_child(body)

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = entry["size"]
		shape.shape = box
		body.add_child(shape)

		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = entry["size"]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.22, 0.25)
		mat.roughness = 0.9
		cube.material = mat
		mesh.mesh = cube
		body.add_child(mesh)


func _build_lighting() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -34, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	add_child(key)

	var env := WorldEnvironment.new()
	env.environment = load("res://resources/config/default_env.tres")
	add_child(env)
