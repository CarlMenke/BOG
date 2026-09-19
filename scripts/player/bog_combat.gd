class_name BogCombat
extends Node
## The things a Bog can do to another Bog: throw a spear, plant a shield to
## hide behind, and lob a magnet that drags people out from behind theirs — or, if
## it is the Elder, throw lightning instead of the spear.
##
## Authority split (docs/DECISIONS.md D-004): the owning client decides *when* it
## wants to act and plays its own feedback immediately, but the host decides
## whether the action actually happens. A client that lies about its cooldown
## gets its request dropped — the host keeps its own timers and is the only one
## that broadcasts.
##
## Which is why **this node belongs to the host and not to the Bog around it**.
## `MatchState._create_bog` hands the Bog to its owner and then hands this one
## child back to peer 1, because the `_do_*` broadcasts below are sent by the
## host and Godot checks an `@rpc("authority")` against whoever owns the node it
## arrives at. The `_request_*` calls go the other way and are `any_peer` with a
## sender check, so the owner can still ask. See D-024.
##
## Cooldowns are therefore tracked twice on purpose. The local copy exists so the
## HUD can show a sweeping timer without waiting for a round trip; the host's
## copy is the one that counts. **Carried stock is tracked the same way and for
## the same reason** — the count under the shield glyph has to move on the
## click, not a round trip later, and the host's count is the one that decides
## whether a shield actually appears.
##
## The shield and the magnet are **inventory now, not abilities** (D-032). There
## is no cooldown that refills them: a Bog spawns with neither, picks them up off
## corpses, spends them one at a time and loses whatever is left when it dies.
## `shield_use_delay` and `magnet_use_delay` are all that is left of the old
## timers, and they are a floor on how fast a stack can be emptied rather than a
## refill rate.
##
## **A letter hold takes the spear away and nothing else** (D-035). While
## `MatchState` says this Bog is holding a card up, `has_spear()` is false, the
## card is in the fist where the shaft would be, and the throw is refused on the
## client and again on the host. The shield and the magnet are untouched, and so
## is movement — a Bog running a hold out runs exactly as fast as one that is
## not, which is deliberate and is the user's call.
##
## The spear is the one ability that does *not* happen on the click. A click
## starts the windup animation; the spear leaves the hand
## `BogAnimator.THROW_RELEASE_TIME` later, and the aim is read at that moment
## rather than at the click, so a target that moves while you wind up has to be
## led. See D-025.
##
## **The Elder replaces the spear rather than adding to it** (D-038). For as long
## as `MatchState` says this Bog is the Elder — twenty seconds, since D-040 —
## `has_spear()` is false, the fist holds no shaft, and the same click runs the
## same windup — the branch is taken at the *release*, next to where the aim is
## read, and what comes out is a hitscan bolt instead of a projectile. One
## windup, one release tick, two outcomes: a parallel windup for the Elder would
## be a second copy of the one piece of timing D-025 exists to keep honest.
##
## **The Elder's release is not the spear's** (D-040). The user, having played
## one: *"there should be basically no delay for the lightning."* The bolt leaves
## `MatchConfig.lightning_delay` after the click — 0.2 s by default against the
## spear's 0.50 — and the clip is played fast enough to have got there, at a rate
## derived from the delay by `BogAnimator.cast_rate_for_release`. The windup is
## still one piece of code with one set of edge cases; the only thing that
## branches is which clip runs, how fast it runs, and when its release lands.
##
## **The bow is the third thing on that one path** (D-065). A click is not what
## starts it — a *held key* is — and what comes out the other end is an arrow
## worth anywhere between 20 and 80 depending on how long the key was held. What
## is the same is everything that has ever mattered here: one `is_winding_up`,
## one cancel on death, one cancel on a letter, one place the aim is read, one
## release tick with what is now three outcomes on it. The draw is a windup
## whose release is a decision instead of a deadline, and that is one extra line
## in `_tick_windup` rather than a second copy of it.
##
## **The charge is on the body, not in here** (D-065). `Bog.sync_draw` is a
## replicated float and this file writes it on the owning client and reads it
## nowhere else — because "how far is that bow drawn" is a question the animator
## has to answer about *seven Bogs it does not own*, and a number that lives on
## the combat node would have to be broadcast to be worth anything. D-025's rule
## is that a tell only the attacker can see is not a tell; a bow is the first
## weapon here whose tell is continuous, and a float that replicates is the
## cheapest honest way to make a continuous thing visible.
##
## **The heal potion is the one thing in this file that is not an attack**
## (D-067, amended). It used to be stock spent with a key; it is now drunk where
## it lies, the moment a Bog walks onto the drop, and there is no key and no
## carried bottle between the two. A channel is still a windup whose *point* is
## that it can be taken away: the health arrives over the two seconds rather
## than at the end of them, and being hit still ends it and keeps whatever had
## arrived.
##
## **What the amendment had to move is the interrupt rule.** D-067 charged two
## seconds of standing still for a potion, and that cost cannot survive a drink
## that *starts* on the stride that collected it — the collector is by
## definition moving, so "moving ends it" would cancel every drink on the frame
## it began. The cost moved rather than vanished: a drinking Bog travels at
## `Bog.DRINK_SPEED_SCALE` of its speed and cannot attack (`is_busy()`), so it
## is slow, unarmed and holding 0.30 m of bright purple beside its head for two
## seconds. Only a hit ends a drink early now, which is the one clause D-067
## called the mechanic rather than the tuning.
##
## The other half of the amendment is that the drink is **decided on the host**
## and nowhere else (D-004). There is no keypress left to predict from, so there
## is no local prediction: the host that rules on the pickup is the machine that
## starts the channel, and every peer including the drinker learns about it from
## the same broadcast.
##
## **The great sword is the fourth outcome on that one tick, and the first that
## does not leave the hand** (D-068). A click, a wind-up, a release moment
## measured off the clip — and then, instead of a projectile or a ray, a shape
## resolved in front of the body. What is new is where "in front" comes from:
## `Swing` turns the Bog through a whole revolution inside its own skeleton, so
## at the release the body's facing is nowhere near the blade's and the sweep has
## to be taken off the **bone attachment the sword hangs from**. What is not new
## is anything else: one `is_winding_up`, one cancel on death, one cancel on a
## letter, one release tick, and the damage is `Bog.MAX_HEALTH` — a number, not a
## branch, exactly as the spear's is (D-062).
##
## **The sword is only in the hands while it is being swung** (D-068), which is
## the one thing about it that is not a copy of a line above. There is no sheathe
## clip anywhere in the pack and there is no weapon-select in this game, so a
## carried great sword would be a Bog that had permanently given up its spear.
## It appears on the click and is gone when the spin ends — `Bog.is_spinning()`,
## one clock, on every peer — and for exactly that window `_wants_shaft` and
## `_wants_bow` answer no, which is how a two-handed weapon stays inside "never
## more than one per hand" (D-065).
##
## **The sword got a second attack, and the Bog got a way to have none** (the
## feel round). Three additions, all of them on the machinery above rather than
## beside it:
##
## * **The holster.** `Bog.sync_holstered` is a replicated bool the owner
##   toggles with **H**. While it is true the three weapon gates answer no, so
##   the fists are empty on every screen, and `target_speed()` pays a tenth more
##   for it. What is left is a punch — a fifth outcome on the one release tick,
##   with the sword's four-function relay around it, and a host that checks the
##   attacker's own published holster before it will hurt anybody.
## * **The chain.** The primary click is three slashes of `SwordCombo` at 50
##   each, and the spin D-068 built is the **sprint attack**, fired by the same
##   button at 0.8 of run speed. The chain is a sixth outcome on that same tick;
##   the two clocks it needs live on `Bog` beside the spin's, for D-068's reason
##   exactly — what they decide is what is in the fists and how fast the body
##   travels, on eight machines.
## * **The dance empties the hands.** `_bare_handed()` is the one sentence the
##   holster and the emote share, and the five `_wants_*` ask it once each.
##
## **The clip stopped being shared, and the windup did not** (D-064). Until step
## 5 of `docs/PLAN_COMBAT.md` the Elder played the spear's own `Throw` at
## whatever rate met the delay, which worked while the throw was a baseball
## throw and read as an accident once it became an overhand delivery with a
## run-up. `Cast` is the Elder's own clip now, with its own window, its own
## rate and its own ceiling. What did *not* fork is anything in this file below
## `_play_windup`: one click, one `_windup_release_at`, one release tick, one
## cancel path, one place the aim is read.

signal cooldowns_changed()
## Carried stock changed: spent, picked up, or wiped by a death. Separate from
## `cooldowns_changed` because they move for different reasons and at wildly
## different rates — the counts change a handful of times a match and the
## cooldowns change every frame the HUD asks.
signal inventory_changed()
## One committed use of a weapon: a spear thrown, an arrow loosed, a sword swung,
## a bolt cast. Emitted from the four `_do_*` handlers, which is to say **after**
## the host has accepted the action and on every peer that runs it — so on the
## host it fires exactly once for every use anybody makes, which is what lets a
## counter watch the whole session without a packet of its own.
##
## Deliberately not `Loadout.Weapon`. That enum's ordinal goes on the wire in a
## roster row and its own comment forbids appending anything that is not a
## player's chosen armament; the Elder's lightning is neither chosen nor in it.
## A string also happens to be the key `RangeStats` files the row under, so
## nothing in between has to own a translation table.
signal weapon_launched(weapon: String)

const SPEAR := preload("res://scripts/items/spear_projectile.gd")
const ARROW := preload("res://scripts/items/arrow_projectile.gd")
const SHIELD := preload("res://scenes/items/shield.tscn")
const MAGNET := preload("res://scenes/items/magnet.tscn")

# How long after the click the spear actually leaves the hand is
# `BogAnimator.THROW_RELEASE_TIME`, and not a constant here, because it is a
# fact about the animation and this file only has to agree with it.
#
# It is measured off the clip rather than guessed, and then *derived*: `Throw`
# is 2.833 s, the animator plays the 1.067-1.900 s window of it, and tracking
# the `RightHand` bone against the hips through the built clip puts the hand
# 0.80 m above them and drawn back at 1.433 and 0.718 m in front of them at
# 1.567 — the furthest forward it ever gets. That extension is the release, and
# the window is played at whatever rate lands it half a second after the click,
# which on this clip is 1.0 (D-063). The hand is quickest at 1.600, on the way
# *down*, and a spear leaving then would read as a slam rather than a throw.
#
# Deriving it from the window and the rate is the point: whoever moves either
# of those without opening this file cannot leave the spear and the hand
# disagreeing, which is the bug D-025 exists because of.
#
# The throw OneShot's 0.08 s fade-in needs no allowance on top: the window opens
# on the quiet frame between the approach and the wind-up, so the blend is
# finished before anything the eye is following has started.

## Where the throw leaves the hand, relative to the Bog. The spear is aimed at
## whatever the crosshair is over, not simply pushed along the camera's forward
## axis, so what you point at is what you hit even up close.
const THROW_OFFSET := Vector3(0.34, 0.0, 0.0)
## Anything nearer than this is treated as "straight ahead"; without it, aiming
## at a wall a metre away would make the Bog throw at its own feet.
const MIN_AIM_DISTANCE := 3.0
const MAX_AIM_DISTANCE := 220.0

## How far in front the shield is planted.
const SHIELD_DISTANCE := 2.1

## How much a shot has to drop before it stops being point-and-click.
##
## **One Bog's height**, and the number itself is unchanged from the comment
## that used to sit under `LIGHTNING_RANGE := 28.0`: *"over 28 m it is in the
## air 0.67 s and drops 1.78 m — one Bog's height, near enough exactly."* That
## sentence was the derivation and 28 was its answer, written down. What D-065
## changed is which end is the constant.
##
## It is the visible Bog — the 1.80 m rig `art/bog/BOG.fbx` imports at (D-095) — and
## not `Bog.STAND_HEIGHT`'s 1.55 m collision capsule, because what a player
## aims at is the Bog they can see. Keeping the original figure also keeps the
## arithmetic checkable: `flat_band(SpearProjectile.SPEED, SpearProjectile.DROP)`
## still comes out at 28.0, which is the whole proof that nothing was quietly
## re-tuned on the way past.
const FLAT_BAND_DROP := 1.78


## How far a shot at `speed` falling at `drop` stays flat, in metres.
##
## `d = speed · sqrt(2 · FLAT_BAND_DROP / drop)`, which is the time to fall one
## Bog multiplied by the distance covered in it. Inside it you point at a body
## and hit it; past it the shot becomes a judgement about arc, which is where
## D-014 says the skill in this fight lives.
##
## Static and public because it is the one sentence three weapons are compared
## by, and every one of the three should be able to be asked:
##
##     spear       42 m/s,  8 m/s²    28.0 m
##     bow, snap   18 m/s, 16 m/s²     8.5 m
##     bow, full   60 m/s,  5 m/s²    50.6 m
##
## `maxf` on the drop because it is a lobby dial with a floor of 0.5 and this
## would otherwise be a division by zero the day somebody removes the floor.
static func flat_band(speed: float, drop: float) -> float:
	return speed * sqrt(2.0 * FLAT_BAND_DROP / maxf(drop, 0.01))


## How far the Elder's bolt reaches.
##
## **It answers the comment that used to be here rather than deleting it**
## (D-065). That comment said: hitscan with no travel time and no drop would be
## a map-wide delete at any range you can see, so there has to be a number; the
## number is not picked, it is the distance at which a flat *spear* throw stops
## being flat; and the Elder therefore owns exactly the band where the spear is
## point-and-click, while beyond it the spear is still the better tool — which
## is the shape a power-up should have.
##
## Every word of that survives. What stopped being true is that the spear is the
## weapon that defines the band. **The bow's full draw is now the flattest thing
## in the game** — 60 m/s against 42, falling at 5 against 8 — so leaving this
## at 28 would have left the Elder owning a band the bow already owned better,
## which is a power-up that is a downgrade inside 50 m. The user's call was that
## the Elder's range rises to match, and nothing comes down to compensate:
## playtest it (`docs/PLAN_COMBAT.md`).
##
## So it is the same arithmetic on a different weapon, and it is a **function**
## rather than a constant because the bow's speed and drop are lobby dials now.
## A host who flattens the bow flattens the Elder with it, on every peer, off
## replicated config — and a typed 50.6 sitting beside two sliders that move it
## is exactly the kind of number D-063 and D-064 spent their records turning
## back into derivations.
##
## What it costs: 50.6 m at the defaults against 28. On Rust (42 x 64 m) that is
## a long shot rather than most of a fight; on Lantern Wharf and Halcyon Wake no
## sightline is that long anyway (D-056, D-057); on the island it was already a
## clearing and still is.
func lightning_range() -> float:
	return flat_band(_config.bow_speed_full, _config.bow_drop_full)

## What a spear does to a Bog, and what a bolt does (D-062).
##
## Both are `Bog.MAX_HEALTH` — a full body — and both are written as that
## constant rather than as the number 100, which is the entire mechanism
## protecting the one-shot. A spear takes everything a Bog can have, so it kills
## a Bog at full health and it kills one at 3 health, and no arithmetic anywhere
## can make it do otherwise. Type 100 here instead and the promise survives only
## until somebody changes what a full Bog is worth.
##
## The bolt is the same for now, and deliberately so: D-053 chose "the blast is
## a kill or it is nothing — there is no falloff, because there is no health in
## this game for a falloff to take away". There is one now, and falloff is
## suddenly possible — but the Elder is a twenty-second power-up that already
## cannot die, and a bolt that only wounds is a different weapon, to be decided
## with a playtest behind it rather than on the way past.
const SPEAR_DAMAGE := Bog.MAX_HEALTH
const LIGHTNING_DAMAGE := Bog.MAX_HEALTH

## What a great sword does to a Bog (D-068). The same constant again, for the
## same reason, and this weapon is the clearest case of it: a melee attack that
## sometimes leaves somebody alive at arm's length is a worse read than one that
## misses, and the whole balance of this weapon is meant to live in the 1.867 s
## it commits you to and the reach it buys — not in an arithmetic race the victim
## cannot see. Written as `Bog.MAX_HEALTH` so that no dial the host can reach
## makes a connected swing anything other than a kill.
const SWORD_DAMAGE := Bog.MAX_HEALTH

## How hard a swing throws the body, as the velocity handed to `report_damage`.
##
## Between the spear's and the bolt's, and read off the same constant: the
## ragdoll turns a blow into motion at `BogRagdoll.IMPACT_TRANSFER` = 0.15, so a
## flat spear arriving at its full 42 m/s gives a corpse about 6.3 m/s and the
## bolt's 90 is a body *thrown*. 60 is about 9 m/s of corpse — more than a
## thrown spear, because this one arrived on the end of a two-handed swing from a
## body that was already moving, and less than lightning, because the point of
## the bolt's number is that it is seen from across the map and the point of this
## one is that it is seen from two metres.
const SWORD_IMPULSE := 60.0

## How wide the sweep is, in degrees either side of the blade (D-068).
##
## **Not a lobby dial, and that is deliberate**: `sword_reach` is the balance
## number and this is the *shape* of the attack, which should mean the same thing
## in every lobby. 75 degrees either side is a 150 degree sweep, which is
## generous and is meant to be — the blade genuinely passes through every bearing
## during the spin, so the honest reading of this clip would be a full circle.
##
## A full circle is what it is not, and the reason is the only reason: a swing
## has to be able to **miss**. A 360 degree sweep is a nova that kills the Bog
## standing behind you as reliably as the one you aimed at, which would make the
## one weapon in the game with a 1.867 s commitment the one weapon you never have
## to aim. 150 leaves a third of the compass safe, which is enough for a defender
## to be *behind* a swing and enough for an attacker to have chosen wrong.
const SWORD_ARC := 75.0

## How far the blade has to have turned between two frames before its direction
## of travel is believed, in degrees (D-168). The bone attachment is read out of
## a pose written in the idle frame, so a frame in which the clip did not
## advance reads as a blade that turned a hundredth of a degree the wrong way —
## and the swipe would flip its sweep on it. A quarter of a degree is well under
## what `SwordSpin` covers in a frame (222 deg/s is 3.7) and well over the noise.
const BLADE_SENSE_MIN := 0.25

## What one slash of the chain does to a Bog (the feel round).
##
## **The first attack in this game that is not a one-shot, and that is the
## point.** `SWORD_DAMAGE` is `Bog.MAX_HEALTH` and stays that way for the spin,
## because a committed 1.867 s animation that sometimes leaves somebody alive is
## a worse read than one that misses. A slash costs a quarter of a second and
## keeps you moving, so it cannot be worth a body: at exactly half of
## `Bog.MAX_HEALTH` two connected slashes kill and one does not, which is the
## shortest sentence a player can learn about a new weapon.
##
## Written off `MAX_HEALTH` rather than as 50 for `SWORD_DAMAGE`'s reason one
## step along: "two slashes kill" is the whole mechanic, and typing the number
## would leave that promise true only until somebody changes what a full Bog is
## worth.
const SLASH_DAMAGE := Bog.MAX_HEALTH * 0.5

## How much further than the dial a slash reaches, in metres, and how far it
## carries you (the feel round). One number and not two: the reach is longer
## *because* the body steps into the cut, so the metres the step buys are the
## metres the sweep is allowed to claim, and a step that changed without the
## reach following would be a blade that visibly arrives and does nothing.
const SLASH_STEP := 0.35

## How long after a slash's own window closes a second click still chains, in
## seconds (the feel round). A sixth of a second is about a tenth of the whole
## chain and is roughly a frame of human reaction either side of the beat: long
## enough that a player who is trying to chain does, short enough that a chain
## is a rhythm rather than a queue.
const SLASH_CHAIN_GRACE := 0.15

## How many slashes a chain may run to. `BogAnimator.SLASH_COUNT`, because the
## clip is what decides: `SwordCombo` carries three, and a fourth click has
## nothing to play.
const SLASH_MAX := BogAnimator.SLASH_COUNT

## How hard a slash throws the body, as the velocity handed to `report_damage`.
##
## Between the fist's and the spin's, and in the same proportion as the damage:
## the spin's 60 arrives on the end of a whole revolution from a body that had
## committed to it, and this is one arm's cut from a body that is still walking.
## 36 is about 5.4 m/s of corpse, which is a stagger rather than a flight —
## right for a blow that is meant to be followed by a second one, because a
## victim thrown across the clearing by the first slash cannot be reached by it.
const SLASH_IMPULSE := 36.0

## How fast a Bog has to be going, as a fraction of `Bog.RUN_SPEED`, for a click
## to fire the spin instead of a slash (the feel round).
##
## **The one branch in this file that is taken on a speed**, and it is taken on
## a speed precisely so that it needs no key of its own. D-070's whole argument
## is that a player has one weapon and should have one button; the great sword
## now has two attacks, and the honest way to choose between them is the thing
## the player is already doing with the other hand. 0.8 of run is over any walk,
## over any crouch and over anything a Bog reaches by being shoved, so the only
## way to reach it is to hold sprint and mean it.
##
## **The host does not check it**, and that is a decision rather than an
## oversight. `_host_swing_sword` has never asked how fast the swinger was going
## because the spin has never had a condition to check; what the host would have
## to judge it against is `sync_velocity`, which is a tick or two old and was
## sampled before the click, so an honest player whose packet was late would be
## refused the attack they had already paid 1.867 s of animation for. What a
## modified client gains by lying is the committed spin instead of the mobile
## chain, at the same reach, having stood still — which is a worse attack
## everywhere except against a victim who was standing still too.
const SPRINT_ATTACK_SPEED := 0.8

## What a punch does to a Bog (the feel round).
##
## **A fifth of a body, which is the only number in this file that is small on
## purpose.** Fists are what a Bog has when it has put its weapon away, so what
## they are worth has to be read against what putting it away costs: the spear,
## the bow and the sword are all gone for as long as the weapon is down, and
## what is bought is a tenth of a metre a second and a hand free to punch with.
## Twenty means five punches to kill a full Bog and two to finish one a weapon
## already hurt, which is the second half of a fight rather than a way to start
## one.
const PUNCH_DAMAGE := 20.0

## How far a punch reaches, in metres from the puncher's body centre to the
## *surface* of whatever it catches — `sword_reach`'s measurement on a much
## shorter arm. 1.1 m is a fist at the end of a Bog's own reach and nothing
## more: it is deliberately inside the great sword's 1.43 and inside the 1.78 a
## slash gets, so that walking up to a swordsman with your hands up is a losing
## trade at every distance.
const PUNCH_REACH := 1.1

## How wide a punch sweeps, in degrees either side of the fist. Narrower than
## the sword's 75 for the reason the sword's is wide: a spinning blade genuinely
## passes through every bearing, and a fist goes exactly where it is pointed.
## Fifty degrees is a hundred-degree front, which is about what a Bog can see
## without turning and is forgiving enough that a moving target does not slip
## the punch on a rounding.
const PUNCH_ARC := 50.0

## The whole punch, click to click, in seconds — the wind-up you have committed
## to plus what is left. **A constant and not a dial**, unlike every weapon's
## recharge: the fist is not balance, it is what is left when the balance has
## been put away, and a host who could tune it would be tuning the one thing in
## the game that every loadout shares.
const PUNCH_CYCLE := 0.5

## How hard a punch throws the body. A quarter of the sword's, which is about
## 1.4 m/s of corpse — a body that sits down rather than one that is knocked
## anywhere. A punch that flung people would be a better tool for moving an
## enemy than any weapon in the game.
const PUNCH_IMPULSE := 15.0

## How hard a bolt throws the body, as the velocity handed to `report_damage`.
##
## The ragdoll turns a blow into motion at `BogRagdoll.IMPACT_TRANSFER` = 0.15,
## so a flat spear arriving at its full 42 m/s gives a corpse about 6.3 m/s.
## This is a little over twice that, which is the difference between a body
## knocked over and a body *thrown* — and the brief for this weapon is that it
## should be seen from the other side of the map.
const LIGHTNING_IMPULSE := 90.0

## How far back along the bolt the blast's line-of-sight rays start from, so a
## ray fired from a point *on* a wall or on the ground does not begin inside the
## surface it is testing against and report itself blocked.
const BLAST_LOS_BACKOFF := 0.1

## Launch speed of the magnet. With MAGNET_GRAVITY this sets the furthest it can be
## thrown at all — `s^2 / g`, about 22 m on the flat, which is a deliberate
## limit: the magnet is a tool for pulling someone out of nearby cover, not for
## reaching across the island.
const MAGNET_SPEED := 22.0
## Must match `Magnet.GRAVITY`, which integrates the flight. The arc is solved
## here and flown there, so if these disagree the magnet lands somewhere other
## than where the thrower aimed.
const MAGNET_GRAVITY := 22.0

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_DEPLOYABLE := 8

var _bog: Bog
var _config: MatchConfig

## Local, predictive. Drives the HUD.
var _spear_ready_at: float = 0.0
var _bow_ready_at: float = 0.0
var _sword_ready_at: float = 0.0
var _punch_ready_at: float = 0.0
var _lightning_ready_at: float = 0.0
var _shield_ready_at: float = 0.0
var _magnet_ready_at: float = 0.0

## Host-side, authoritative. Never trusted from the wire.
var _server_spear_ready_at: float = 0.0
var _server_bow_ready_at: float = 0.0
var _server_sword_ready_at: float = 0.0
var _server_punch_ready_at: float = 0.0
var _server_lightning_ready_at: float = 0.0
var _server_shield_ready_at: float = 0.0
var _server_magnet_ready_at: float = 0.0

## What this Bog is carrying. Unbounded on purpose: there is no cap, no slot
## limit and no inventory screen, because the only decision worth having here is
## "spend it or keep it" and a cap would add "throw one away" to that for no
## gain. Starts at zero on spawn and on every respawn — see `reset`.
##
## Predictive, like the cooldowns above: spending decrements immediately so the
## HUD moves on the click, and the host's `_do_*` broadcast carries the real
## remainder and corrects it. Every peer keeps this for every Bog, which costs
## two ints and means a spectator's HUD is right about the Bog it is watching.
var _shields: int = 0
var _magnets: int = 0
var _potions: int = 0

## Host-side, authoritative. The only counts that can actually spend anything.
var _server_shields: int = 0
var _server_magnets: int = 0
var _server_potions: int = 0

var _active_shields: Array[Node] = []

## The ring on the ground while aiming. Local, cosmetic, and made on first use
## rather than in `_ready`, because seven of every eight Bogs in a match are
## somebody else's and must never build one.
var _aim_marker: AimMarker = null

## When the thing currently being wound up leaves the hand, or 0 for "nothing
## on its way out". Only ever set on the attacking client: the host is told
## about a shot when it happens, not while it is being aimed.
var _windup_release_at: float = 0.0

## When this Bog started drawing its bow, or 0 for "not drawing" (D-065).
##
## The other half of `is_winding_up`, and the half with no deadline in it: a
## draw ends when the player lets go, which is a decision and not a time. Local
## to the drawing client, like `_windup_release_at`; what every *other* peer
## reads is `Bog.sync_draw`, which this is the source of.
var _draw_started_at: float = 0.0

## Is the thing on its way out of this windup a **sword swing** (D-068)?
##
## The sword's `_loose_charge`, and the same field for the same reason: the
## release tick has four outcomes on it now and something has to say which one
## this is. It is a boolean rather than a number because a swing has no charge —
## what it carries instead is read off the skeleton at the release, which is
## where the blade is and not where any field is.
##
## Local to the swinging client, like `_windup_release_at`. What every *other*
## peer reads is `Bog.is_spinning()`, which outlasts this by the length of the
## follow-through and is what the sword in the fists is drawn from.
var _swinging: bool = false

## Is the thing on its way out of this windup a **punch** (the feel round)?
##
## `_swinging`'s twin, and a sixth outcome on the one release tick rather than a
## path of its own — the same argument D-025, D-038, D-064 and D-068 each made
## in turn: one click, one deadline, one tick, one cancel path, and the branch
## taken at the end of it.
var _punching: bool = false

## Which slash of the chain this Bog is in, 1-based, or 0 for "no chain open"
## (the feel round).
##
## **The decision, not the clock.** The clocks are `Bog`'s — `is_slashing()` for
## the window the blade is out in and `in_chain()` for the window a second click
## is taken in — because both of those have to answer on eight machines, and
## this is the one thing only the swinging client needs: which slash the *next*
## click would be. It is cleared by `_tick_slash` when the body says the chain
## has closed, which is the same tick the recharge starts counting from.
var _slash_index: int = 0

## Host-side, authoritative: the same two facts about the chain the host is
## willing to believe. A client can ask for slash 3 whenever it likes; it gets
## one only if the host saw slashes 1 and 2 and the window it opened is still
## open.
var _server_slash_index: int = 0
var _server_slash_until: float = 0.0

## Which way the blade is travelling, +1 for a sweep to its own left, and the
## last bearing it was seen at (D-168). Only the swipe reads them.
##
## **Kept on every peer and measured rather than sent**, which is the one thing
## about the swipe that is not the host's: every machine plays the same clip, so
## every machine can watch the attachment turn and none of them needs to be told
## which way. Sending it would be a field on the wire carrying news the receiver
## already has, and it would arrive a round trip after the frame it describes.
## Sampled only while a blade is actually out — see `_tick_blade_sweep`.
var _blade_seen: Vector3 = Vector3.ZERO
var _blade_sense: float = 1.0

## How far the string was back when it was let go, or **-1 for "no arrow on its
## way"**.
##
## This is the whole of the bow's presence on the release tick: one field,
## carrying one number, latched at the moment the key came up and spent one
## frame later. Out of band rather than a boolean beside a float, for the reason
## `Bog.sync_draw` is: "loosing at 0% draw" and "not loosing" are two states and
## two fields could disagree about which one this is.
var _loose_charge: float = -1.0

## Host-side. The furthest this Bog's bow has been seen to be drawn during the
## draw that is running now, off the replicated float rather than off anything a
## client says about it — see `_host_loose_arrow`, which clamps a claim to it.
var _server_draw_peak: float = 0.0
var _server_drawing: bool = false

## When this Bog started drinking, or 0 for "not drinking" (D-067).
##
## **Kept on every peer**, unlike `_windup_release_at` and `_draw_started_at`,
## and that is the difference between a windup and a channel. A windup is half a
## second the attacker's own machine can time on its own; a channel is two
## seconds during which everybody watching has to see an arm holding a bottle
## up, and the arm has to come down at the right moment on all eight screens.
## So the clock runs everywhere, off `_do_drink_potion`, and the animation is
## driven from it rather than from a packet per frame.
var _channel_at: float = 0.0
## How long the channel that is running now is, latched when it started.
##
## Read from `MatchConfig.heal_channel` once rather than every tick, because the
## *animation* was fired at a rate derived from it and a clip already playing
## cannot be re-timed. A host who drags the slider mid-match moves the next
## drink, not the one in somebody's hand.
var _channel_seconds: float = 0.0
## Host-side. The only clock that heals anybody.
var _server_channel_at: float = 0.0
var _server_channel_seconds: float = 0.0
## How much of `heal_amount` this channel has actually delivered. The whole of
## "an interrupted drink keeps what had arrived" is this float: the heal is
## handed over in slices, and a channel that ends early simply stops asking for
## more (D-067).
var _server_channel_healed: float = 0.0


func _ready() -> void:
	_bog = get_parent() as Bog
	if _bog == null:
		push_error("BogCombat expects to be a child of a Bog")
		return
	_config = Net.config
	# Every peer's copy of every Bog listens, not just the local one: the whole
	# point of the hold is that it is visible across the clearing (D-035), and
	# what makes it visible is this Bog's hand on *your* screen. The connection
	# dies with the node, so there is nothing to undo on a respawn or a leave.
	MatchState.letter_hold_changed.connect(_on_letter_hold_changed)
	# And the same for the robe, for the same reason: the crackle around an
	# Elder's fist is the tell that the most dangerous Bog in the clearing is
	# loaded, and it has to be on *your* screen, not only on theirs (D-038).
	MatchState.elder_changed.connect(_on_elder_changed)
	# A life starting is the one moment the hand has to be drawn and cannot be
	# drawn from here: children are readied before their parent, so `held_gear`
	# does not exist yet when this runs (D-069). `revive_at` is what `_create_bog`
	# and `_do_respawn` both end with, on every peer, and it already emits — so
	# the hand is right on the frame the body appears rather than on the next
	# one.
	#
	# It was the next one until the weapon became a choice, and it did not
	# matter: `HeldGear` builds its spear visible, every Bog had a spear, and
	# `_tick_hand` tidied the rest a frame later. Now two Bogs in three spawn
	# holding the wrong thing, and one frame of that is one frame of a bow Bog
	# with a shaft in its fist on eight screens.
	_bog.respawned.connect(_refresh_hand)


func _now() -> float:
	return Time.get_ticks_msec() * 0.001


# -------------------------------------------------------------------- input ---

func _process(_delta: float) -> void:
	if _bog == null:
		return
	# Before the guards below, not after: a Bog that dies or is respawned in the
	# middle of a windup has a throw to *cancel*, and the guards are exactly the
	# conditions under which it has to be cancelled.
	_tick_windup()
	# Before the hand, because the hand is drawn off it: `_tick_draw` is what
	# puts the charge on the body, and on every peer it is what hands the same
	# number to the bowstring's blend shape.
	_tick_draw()
	# Before the guards below and on every peer, like `_tick_windup`: a drink is
	# the one thing here that is *running* on seven machines that did not start
	# it, and the arm has to come down on all of them.
	_tick_channel()
	# Before the hand and before the input poll below: closing a lapsed chain is
	# what decides whether the next click is a fourth slash or a fresh first
	# one, and what takes the great sword out of the fists on the frame the
	# window shuts rather than on the next.
	_tick_slash()
	# On every peer and before the hand, for `_tick_slash`'s reason one step
	# along: the blade whose turn this samples is in the fists the line below
	# paints, and the sample has to be taken on the frame it describes.
	_tick_blade_sweep()
	_tick_hand()
	_tick_charge()
	refresh_emote()
	if not _bog.is_local() or not _bog.alive:
		_stow_aim_marker()
		return
	if SceneFlow.cursor_is_free():
		_stow_aim_marker()
		return
	_tick_aim_marker()
	# **One button for every weapon** (D-070). `throw_spear`, `draw_bow` and
	# `swing_sword` were three actions on three keys, which was three things to
	# learn for a game in which a player has exactly one weapon — and two of the
	# three were on keys nobody would find. They are one `primary_attack` on the
	# left mouse button, which is where the spear already was, so the default
	# pick plays the match it played yesterday.
	#
	# **The press and the release are both polled, unconditionally, and neither
	# asks what this Bog is carrying.** That is D-069's property held onto: *"the
	# input poll asks all three actions unconditionally while the `try_`
	# functions refuse themselves"*, and it survives consolidation because the
	# three weapons disagree about *which edge* they fire on rather than about
	# whether they may be asked.
	#
	# The press starts a throw, a cast, a swing **or** a draw. All three `try_`
	# functions below are called and at most one accepts, because `carries()`
	# makes the three gates mutually exclusive and `is_busy()` covers the rest —
	# and the Elder's cast is a fourth outcome reached *inside*
	# `try_throw_spear`, which is where D-038 put it and not a fourth call here.
	# The release ends a draw and is `release_draw`'s own no-op for every Bog
	# that was not drawing (`_draw_started_at <= 0.0`). So the branch on the
	# loadout that "one action, two meanings" seemed to need does not exist:
	# **the gates are the branch**, in the place every other reason a weapon says
	# no already lives, and this poll asks two questions where it asked four.
	#
	# Two more calls since the feel round and not one more branch: a holstered
	# Bog's gates all say no, so `try_punch` is the fifth thing that refuses
	# itself, and `try_sword_attack` is the great sword's two attacks choosing
	# between themselves off the speed the body is already travelling at rather
	# than off a second key. The property D-069 asked for — the poll asks
	# everything unconditionally and the gates are the branch — is untouched.
	if Input.is_action_just_pressed("primary_attack"):
		try_throw_spear()
		try_draw_bow()
		try_sword_attack()
		try_punch()
	# The release goes through `release_draw` rather than being read inside
	# `_tick_windup`, so that a testbed can let go of a string without a keyboard
	# (`tools/combat_range.gd`).
	if Input.is_action_just_released("primary_attack"):
		release_draw()
	if Input.is_action_just_pressed("place_shield"):
		try_place_shield()
	if Input.is_action_just_pressed("throw_magnet"):
		try_throw_magnet()
	# **There is no drink key.** A potion is drunk by walking onto it and the
	# host is what decides that, so there is nothing here to poll — the action
	# is retired in `project.godot` and asserted retired by `hud_range -- keys`,
	# for D-070's reason: a key bound to nothing is worse than a key that is not
	# bound, because the player presses it and the game's silence reads as a bug
	# in the potion.
	# The emote is the one key here that is a toggle rather than a trigger, for
	# the reason it is a loop rather than a one-shot: the player decides when it
	# is over, and the most obvious way to say so is the key that started it.
	# Every other way out of it is in `refresh_emote` and in `Bog._read_input`.
	if Input.is_action_just_pressed("emote"):
		toggle_emote()
	# And so is the holster, for the emote's reason exactly: putting your weapon
	# away is a state the player leaves when they decide to, not something with
	# a duration, so the key that starts it is the key that ends it.
	if Input.is_action_just_pressed("holster"):
		toggle_holster()


func spear_cooldown() -> float:
	return maxf(0.0, _spear_ready_at - _now())


func lightning_cooldown() -> float:
	return maxf(0.0, _lightning_ready_at - _now())


func bow_cooldown() -> float:
	return maxf(0.0, _bow_ready_at - _now())


## How long until the fists can throw another punch. The same shape as the three
## above and the only one with no dial behind it — see `PUNCH_CYCLE`.
func punch_cooldown() -> float:
	return maxf(0.0, _punch_ready_at - _now())


func sword_cooldown() -> float:
	return maxf(0.0, _sword_ready_at - _now())


## Seconds until another shield may be placed. Not a cooldown on the *ability*
## — there is nothing to recharge — only on how fast the stack can be emptied.
func shield_use_cooldown() -> float:
	return maxf(0.0, _shield_ready_at - _now())


func magnet_use_cooldown() -> float:
	return maxf(0.0, _magnet_ready_at - _now())


## How many this Bog is carrying. Zero is the normal state at the start of a
## life, so the HUD has to render an empty slot as ordinary rather than broken.
func shield_count() -> int:
	return _shields


func magnet_count() -> int:
	return _magnets


func potion_count() -> int:
	return _potions


## Is this Bog in the middle of a drink? True on every peer for every Bog, which
## is the point of the clock living on all of them (D-067).
##
## Asked by four things and they want it for four reasons: the drinker, to
## refuse a second drink; every weapon's gate, to refuse an attack out of one;
## the HUD, to dim the tile; and the host, to decide whether there is anything
## to interrupt.
func is_channelling() -> bool:
	return _channel_at > 0.0


## How far through the drink is, 0 to 1. Zero when there is no drink.
##
## Computed from a clock rather than accumulated, for `draw_fraction`'s reason:
## a dropped frame must not leave a channel short.
func channel_fraction() -> float:
	if _channel_at <= 0.0 or _channel_seconds <= 0.0:
		return 0.0
	return clampf((_now() - _channel_at) / _channel_seconds, 0.0, 1.0)


## Did this Bog bring `weapon`? (D-069)
##
## **The fourth clause of the one gate, and deliberately not a fourth gate.**
## `has_spear()`, `has_bow()` and `has_sword()` were already three statements of
## one sentence — "is there a weapon in that hand right now" — with three things
## able to answer no: the Elder replaces your weapon (D-038), a letter hold
## disarms it (D-035), and a drink needs the fist (D-067). A lobby pick is the
## fourth thing that can answer no, so it is one more clause in each of the three
## and not a check anybody has to remember to make somewhere else. Every place
## that already asked `has_spear()` — the throw, the host's second opinion, the
## aim marker, the hand — is gated on the pick for free, which is the property
## `has_spear()`'s own header has insisted on since D-035.
##
## Read off `Bog.weapon`, which is seeded from the roster row when the Bog is
## built and cannot change for the life of it (the pick locks at Start, D-069).
## A null `_bog` answers no rather than defaulting to a spear: a combat node with
## no body has no hands either, and the three cooldown accessors above already
## take that view.
func carries(weapon: int) -> bool:
	return _bog != null and _bog.weapon == weapon


## Whether this Bog could start a drink this instant, potion or no potion.
##
## **The one gate**, the way `has_spear()` is the spear's: the host asks it
## before it will start a channel off a pickup, `Pickup` leaves a bottle on the
## ground when it says no, and `has_potion()` below is this plus stock. Anything
## that should stop a Bog drinking adds a clause here and gets all three.
##
## The clauses, and which of them is inherited and which the auto-drink added:
##
## * **An Elder does not drink.** Inherited (D-067). Damage to one is zero, so
##   there is nothing for a potion to put back, and the robe's own fists are
##   busy with a bolt.
## * **A hand holding a letter card has nothing to raise a bottle with.**
##   Inherited (D-035), the same sentence the spear and the bow already make.
## * **Not already drinking.** Inherited. A second drink started over the first
##   would restart the clock and pay the first one's remainder twice.
## * **Not mid-swing, mid-windup or mid-chain** (`is_busy()`, which folds the
##   channel clause above into itself). New, and it is what stops a pickup
##   quietly eating an attack: the drink is a layer *under* the throw and the
##   slash in the animator's graph (D-068), and a bottle raised inside a windup
##   would take the spear out of the fist on the frame it was due to leave it.
## * **Not already at full health.** New, and it is the "don't waste it" rule:
##   a Bog at 100 walking over a potion leaves it standing. D-067 deliberately
##   refused this clause because it was a *key* that would silently do nothing;
##   with no key there is nothing to be silent about, and the drop staying
##   visibly on the ground is the feedback the keypress could not give.
##
## What is **not** here any more is the movement rule. See the header: a drink
## that starts on the stride that collected it cannot be cancelled by that
## stride. Its absence is also the fix for a real bug — this gate used to ask
## `_channel_broken()`, which compares `Bog.sync_jump_serial` against the serial
## latched *when a channel started*, so on a Bog that had never drunk it
## compared today's jump count against zero and went permanently false the first
## time the player jumped. A potion has been undrinkable after your first jump
## of a life since the serial was introduced.
func can_drink_now() -> bool:
	return _bog != null and _bog.alive and not is_elder() \
		and not is_holding_letter() and not is_busy() \
		and _bog.health < Bog.MAX_HEALTH


## Whether there is a potion in stock that can be drunk right now.
##
## Stock survives the auto-drink for one reason and it is the practice range's:
## `RefillStone` and the harnesses hand potions over directly, and
## `try_drink_potion` is how one of those is spent. Nothing in a match banks a
## potion any more — `MatchState.claim_pickup` grants and spends in the same
## breath (see `host_auto_drink`).
func has_potion() -> bool:
	return _potions > 0 and can_drink_now()


## Whether there is a spear to throw. **The one gate**: the throw asks it, the
## host asks it before it will honour a request, the aim marker asks it, and the
## hand is drawn from it. Anything that wants to take a Bog's spear away adds a
## clause here and gets all four for free.
##
## A letter hold is the second such clause (D-035). A Bog holding a card up
## cannot throw, and the reason is not a rule bolted on next to this one — it is
## that the hand the spear would come out of has a letter in it.
##
## A drink is the **third**, and it is the same sentence again (D-067): a Bog
## with a bottle at its mouth has a fist round the bottle. Put here rather than
## only in `try_throw_spear` precisely so that the *hand* obeys it — a Bog
## raising a drink with a spear still in its fist and a bow still in the other
## one was what the first contact sheet of this feature showed, and the fix is
## the rule this function already is rather than a fourth place that has to
## remember.
## The **fourth** is the lobby pick (D-069), and it is the first clause rather
## than the last because it is the only one that was never true and then false: a
## Bog that chose a bow has no spear for the whole match, so this is a statement
## about what it brought and the other three are statements about what has since
## happened to it. `carries` carries the argument for why it is here.
## The **fifth** is the holster (the feel round), and it is the clause that
## finally makes this function's promise reversible: every other one of the four
## is something that happened *to* this Bog, and this is the player choosing.
## Here rather than only in `try_throw_spear` for the reason the drink is here —
## so that the *hand* obeys it, and a Bog with its weapon away is a Bog with
## nothing in its fists on eight screens rather than one whose throw quietly
## does nothing.
func has_spear() -> bool:
	return carries(Loadout.Weapon.SPEAR) and not is_elder() \
		and spear_cooldown() <= 0.0 \
		and not is_holding_letter() and not is_channelling() \
		and not is_holstered()


## Whether there is a bow to draw, and the exact mirror of `has_spear()`
## (D-065): the draw asks it, the host asks it before it will honour a loose,
## and the left hand is drawn from it. Anything that wants to take a Bog's bow
## away adds a clause here and gets all three for free.
##
## It shares all three of the spear's clauses and for all three of the spear's
## reasons — the drink included, and most obviously of the three: the drinking
## hand *is* the bow hand (`HeldGear.BOW_HAND_BONE`), so a bow that stayed put
## through a channel would be a longbow held at the lips. An
## Elder has lightning *instead of* its weapons, not as well as them (D-038) —
## two hands full of bow would be the tell for the most dangerous Bog in the
## match saying the wrong thing. And a letter hold disarms the bow exactly as it
## disarms the spear, which is the decisions table's own call and is not a rule
## bolted on beside this one: it is that the hand the arrow would be drawn with
## has a card in it.
##
## What it does **not** share is the recharge. `bow_recharge` is its own dial and
## is much shorter than the spear's, because a spear is a guaranteed kill and an
## arrow is not.
## It shares the lobby pick too (D-069), which is the newest of the four and the
## one that makes this function mean something it never did: before it, every Bog
## in the match had a bow and the only question was whether it was ready. Now the
## common answer is no, for the same reason the common answer to `has_spear()`
## is.
func has_bow() -> bool:
	return carries(Loadout.Weapon.BOW) and not is_elder() \
		and bow_cooldown() <= 0.0 \
		and not is_holding_letter() and not is_channelling() \
		and not is_holstered()


## Whether there is a great sword to swing, and the third mirror of `has_spear()`
## (D-068): the swing asks it, the host asks it before it will honour a request,
## and the fists are drawn from it.
##
## It shares all three of the spear's clauses and for all three of the spear's
## reasons — the Elder has lightning *instead of* its weapons (D-038), a letter
## hold disarms it exactly as it disarms the spear and the bow (D-035, and the
## decisions table's own call), and a Bog with a bottle at its mouth has both
## fists busy, which for a two-handed weapon is the most obviously true of the
## three (D-067).
##
## It does **not** need a clause about the swing that is already running. That is
## `is_busy()`'s job and it is where the three `try_` functions ask it, so this
## can stay what its two siblings are: a statement about whether this Bog has the
## weapon at all.
## Which, since D-069, is a question with a real answer: the lobby pick is the
## fourth clause here as it is on the two above, and it is what finally makes the
## sword a *weapon* rather than a fourth thing every Bog happened to have. See
## `_wants_sword` for the visible half of that — a great sword is carried now,
## because a Bog that chose one has genuinely given up its spear, which is the
## exact condition D-068 said it did not have.
func has_sword() -> bool:
	return _sword_in_hand() and sword_cooldown() <= 0.0


## Everything `has_sword()` asks except the recharge (the feel round).
##
## The chain is why this exists. A slash pushes `_sword_ready_at` out to the end
## of the window the *next* click would be taken in, so that the recharge runs
## between chains rather than between slashes — which means `has_sword()` is
## false for the whole of a chain, and the second click cannot be gated on it.
## Splitting the sentence in two is what keeps there being one list of reasons a
## Bog has no sword: the chain asks this, a fresh attack asks this *and* the
## clock, and neither carries a copy of the other's clauses.
func _sword_in_hand() -> bool:
	return carries(Loadout.Weapon.SWORD) and not is_elder() \
		and not is_holding_letter() and not is_channelling() \
		and not is_holstered()


## Has this Bog put its weapon away (the feel round)? Off the replicated bool on
## the body, so one road for the Bog you are driving and the seven you watch.
func is_holstered() -> bool:
	return _bog != null and _bog.is_holstered()


## May this Bog put its weapon away, or take it back out, right now?
##
## `can_emote()`'s shape and most of its list, because it is the same kind of
## question — a state the player asks for, refused while the body is already in
## the middle of something. Alive, not busy (a windup, a channel, a spin or a
## chain), not drawing, not holding a card, not dancing.
##
## **The letter is the one that is not obvious.** A Bog holding a card already
## has no weapon and no fists (D-035), so holstering would be a key that does
## nothing visible and un-holstering a promise the hold is about to break. The
## draw is the same sentence with a string in it.
##
## It is deliberately **not** a per-frame refresh the way `refresh_emote` is.
## An emote is something you are doing and every reason it may not start is a
## reason it may not continue; a holster is something you *are*, and a punch —
## which makes `is_busy()` true for a quarter of a second — must not put the
## weapon back in your hands half way through itself.
func can_holster() -> bool:
	return _bog != null and _bog.alive and not is_busy() \
		and not _bog.is_drawing() and not is_holding_letter() \
		and not is_emoting()


## The key. A toggle, for the emote's reason: the player decides when the hands
## come back up.
##
## The write is straight into the replicated field and it is the owner's alone —
## `_bog.is_local()` rather than a `_relay_*` — which is the whole reason this
## is a `sync_` bool and the emote is an event. There is nothing to cross-fade
## between and nothing that is wrong for a sixtieth of a second: a late packet
## arrives at the value the owner is still at, and a dropped one is corrected by
## the next change rather than leaving somebody stuck.
##
## `refresh_hand()` and not `_refresh_hand()`: the shoulders move with the
## fists. The carry pose is the pick's, and a Bog that put its sword away while
## its shoulders stayed in a swordsman's stance is exactly the disagreement that
## forwarder exists to prevent.
func toggle_holster() -> void:
	if _bog == null or not _bog.is_local() or not can_holster():
		return
	_bog.sync_holstered = not _bog.sync_holstered
	refresh_hand()
	cooldowns_changed.emit()


## Should both fists be empty whatever this Bog is carrying (the feel round)?
##
## The one sentence the five `_wants_*` share, and the reason it is one function
## rather than two clauses repeated five times: a holster and an emote are two
## different decisions with exactly one consequence in common, and a sixth thing
## that empties the hands should be one line here rather than five edits.
##
## The emote's half is D-105 finished: the dance is a whole-body pose and a
## great sword hanging off a twerking Bog's fists was the one thing about it
## that read as a bug rather than as a joke. The prop comes back when the dance
## ends, off `_tick_hand`'s poll, without anything having to remember.
func _bare_handed() -> bool:
	return is_holstered() or is_emoting()


## Is this Bog in the middle of a swing? True on every peer for every Bog, which
## is the point of the clock living on the body (D-068).
##
## **One clock, and it is `Bog`'s.** The swing is the one attack here whose
## visible life outlasts its own release: the blade connects at 1.067 s and the
## body goes on spinning to 1.867, and for the whole of that the sword has to be
## in the fists on eight screens and the spear has to be out of them. A second
## deadline in this file would be a second opinion about that, on machines that
## have no other way to tell — so the clock `Bog._handle_movement` steers by is
## the same one the hand is drawn from, and `_begin_swing` starts it everywhere.
func is_swinging() -> bool:
	return _bog != null and _bog.is_spinning()


## Is a slash's blade actually out? The chain's `is_swinging()`, off the chain's
## own clock on the body and true on every peer for the same reason.
func is_slashing() -> bool:
	return _bog != null and _bog.is_slashing()


## Is a slash chain open — a blade out, or inside the grace a second click would
## continue it in? The window `_wants_sword` keeps the great sword in the fists
## for, and the window `is_busy()` refuses everything else during.
func in_chain() -> bool:
	return _bog != null and _bog.in_chain()


## Is this Bog the Elder? Asked of `MatchState` every time rather than mirrored
## into a field here, for exactly the reason `is_holding_letter` is: the robe is
## match state, the host owns it, and a copy in this file would be a second
## opinion about who is dangerous.
func is_elder() -> bool:
	return _bog != null and MatchState.is_elder(_bog.peer_id)


## The Elder's gate, and the mirror image of `has_spear()` in every way that
## matters: the cast asks it, the host asks it before it will honour a request,
## and the hand is drawn from it.
##
## It shares the *hold* half of the spear's gate deliberately (D-038). An Elder
## mid-letter-hold cannot fire, because otherwise the hold stops being a
## vulnerability for exactly the player who most needs to have one — and the
## hand it would come out of is holding a card.
##
## It does **not** share the recharge half. They are different clocks on purpose:
## a spear can be dodged, a bolt cannot, so the bolt waits longer
## (`MatchConfig.lightning_cooldown`).
func has_lightning() -> bool:
	return is_elder() and lightning_cooldown() <= 0.0 and not is_holding_letter()


## Is this Bog in the middle of a letter hold?
##
## Asked of `MatchState` every time rather than mirrored into a field here, and
## that is the whole design. The hold is owned by the host, replicated to every
## peer, and ticked in exactly one place; a copy in this file would be a second
## clock, and a second clock is how a Bog ends up with a card in its hand and a
## spear it is allowed to throw. There is no local prediction of a hold for the
## same reason — the letter is the prize and the host is the only thing that
## hands it out.
func is_holding_letter() -> bool:
	return _bog != null and MatchState.is_holding_letter(_bog.peer_id)


## The whole spear cycle: the windup you have already committed to, plus the
## recharge that follows it. What the click spends, so a second click during the
## windup is refused. Nothing on the HUD divides by it any more: the spear tile
## times the recharge alone, from the release, and says nothing during the
## windup (D-054) — this denominator was the ring that swept from the click.
func spear_cycle() -> float:
	return BogAnimator.THROW_RELEASE_TIME + _config.spear_recharge


## The whole bow cycle, and it is the one that is not a constant plus a dial:
## how long a shot takes depends on how far the archer chose to draw, and the
## only honest answer for "the tile is empty for this long" is the longest one.
## So the HUD is told about a full draw, which is what a player who is watching
## the tile rather than the string is about to pay.
func bow_cycle() -> float:
	return _config.bow_draw_time + BogAnimator.BOW_RELEASE_TIME + _config.bow_recharge


func lightning_cycle() -> float:
	return _config.lightning_delay + _config.lightning_cooldown


## The whole sword cycle: the windup you have already committed to, plus the
## recharge that follows it (D-068).
##
## Shaped like `spear_cycle()`, and what it is the cycle **of** is now the spin
## alone: a slash chain spends the recharge through `_open_slash`, from the end
## of the chain rather than from a release. `BogAnimator.SWING_RELEASE_TIME` is
## 1.067 s and `sword_recharge` is 0.500 since the feel round, so this comes out
## at 1.567 against the clip's own 1.867 — under it, which means the spin's
## earliest second click is still the tick the spin ends, gated by
## `is_spinning()` rather than by the dial. The relationship the dial's default
## used to encode (0.800, so that the two coincided exactly) is now the chain's
## to hold, and the dial was dropped to fit it.
##
## Which is the whole of the chain. `Bog._tick_timers` opens `LANDING_GRACE` on
## the frame a spin finishes, so a player who clicks on that tick keeps the speed
## the last swing built and adds to it, and a player who is late loses it to the
## ground in a couple of ticks — the same window, off the same field, that D-052
## gives a bunny hop. Drag the dial up and the chain gets harder until it is
## impossible; drag it down and a swing can be cut short by the next one, which
## costs the part of the advance that had not happened yet. Both are the right
## way round and neither needs a second rule.
func sword_cycle() -> float:
	return BogAnimator.SWING_RELEASE_TIME + _config.sword_recharge


## How fast this Bog's windup clip is played.
##
## The spear's own 1.0 for an ordinary Bog — `Throw`'s authored speed, since
## D-063 windowed it to land its release on the half second it is wanted at. For
## an Elder, whatever puts `Cast`'s release on `lightning_delay` (D-040, D-064):
## 2.58x at the default 0.2 s. Derived from the dial every time it is asked
## rather than cached, so a host who drags the delay mid-match does not leave one
## Bog throwing at the old rate for the rest of its life.
##
## The two branches are rates over *different windows* and are not comparable as
## numbers: 1.0 is 0.500 s of the throw and 2.58 is 0.516 s of the cast squeezed
## into 0.2. What they have in common is the only thing that matters here, which
## is that each one is derived from its own clip's window and its own release.
##
## Asked by `_play_windup` on every peer, not only the caster's, which is the
## reason it is a function of replicated state alone: the rate never travels, so
## it can never travel *wrong*.
func windup_rate() -> float:
	if not is_elder():
		return BogAnimator.THROW_RATE
	return BogAnimator.cast_rate_for_release(_config.lightning_delay)


## How long after the click this Bog's throw actually leaves the hand.
##
## For the spear this is `BogAnimator.THROW_RELEASE_TIME` and always has been.
## For an Elder it is the dial — except at the very bottom of the dial's range,
## where `windup_rate()` has hit `BogAnimator.CAST_RATE_MAX` and the arm cannot
## be sped up any further. There the bolt leads the hand rather than the hand
## being made to catch an impossible number, which at a delay of zero is the
## setting's whole point. Everywhere above 0.14 s the two are the same number.
func release_delay() -> float:
	return _config.lightning_delay if is_elder() else BogAnimator.THROW_RELEASE_TIME


## True between the click and the release, for any of the three (D-065). The
## thing being thrown is still in the hand through this window, which is the
## point of it.
##
## It has two terms now and not three, because the bow's *loose* is already a
## `_windup_release_at`: a draw sets `_draw_started_at`, letting go clears it and
## sets the deadline, and there is never a frame that is neither. What asks this
## is "may a second attack start", and the answer through all of it is no.
func is_winding_up() -> bool:
	return _windup_release_at > 0.0 or _draw_started_at > 0.0


## May this Bog start anything at all? One expression, asked by the three `try_`
## functions, for the reason `_wants_shaft` is one expression: three copies of
## "am I already doing something" that differ by a clause is a Bog that can
## throw a spear half way through a drink.
##
## It is separate from `is_winding_up()` rather than folded into it because that
## function has a second caller with a different question — `_tick_windup` asks
## it as "is there a release on its way", and a channel has no release for it to
## find (D-067).
## It has a third term since D-068, and it is the one that is not a windup: a
## swing's *commitment* runs 0.800 s past its own release, and everything this
## function is asked by — the throw, the draw, the drink and the next swing — has
## to be refused for the whole of it. Otherwise a player buys a 1.867 s
## animation, gets the kill at 1.067, and spends the rest of it throwing spears
## out of a body that is visibly mid-spin.
## It has a fourth term since the feel round, and it is the spin's argument at a
## quarter of the scale: a slash chain is a window in which the great sword is
## in the fists and a second slash is the only thing that may happen, so the
## throw, the draw, the drink, the emote and the holster are all refused for the
## whole of it. The chain's own follow-up click is asked *before* this function
## (`try_sword_attack`), which is the same carve-out `_open_slash` needs and the
## only one there is.
func is_busy() -> bool:
	return is_winding_up() or is_channelling() or is_swinging() or in_chain()


## True while a *throw* is between its click and its release — the spear's or
## the Elder's, and never the bow's.
##
## Asked separately from `is_winding_up` by the three places whose question is
## really "is the right fist holding something it has paid for but not yet let
## go of" (D-025's carve-out), and by the aim ring. A drawing Bog has an arrow
## in that fist and not a shaft, so answering yes for it would put two things in
## one hand — which is the rule this whole node exists to keep.
func _is_throw_windup() -> bool:
	return _windup_release_at > 0.0 and _loose_charge < 0.0 and not _swinging \
		and not _punching and _slash_index == 0


## True from the moment the string starts back to the moment the arrow leaves.
## The local half of it; every other peer reads `Bog.is_drawing()`, which is
## what the hand and the animator are actually drawn from.
func _bow_in_use() -> bool:
	return _draw_started_at > 0.0 or _loose_charge >= 0.0


## How far this Bog's own bow is drawn, 0 to 1, and 0 when it is not drawing.
##
## The one place the charge is computed, and it is computed from a clock rather
## than accumulated, so a dropped frame cannot leave a draw short. Nothing else
## reads this: `_tick_draw` puts the answer on the body and everything —
## including this client's own animator, its own bowstring and its own arrow's
## damage — reads it back from there. One number, one road (D-065).
func draw_fraction() -> float:
	if _draw_started_at <= 0.0:
		return 0.0
	return clampf((_now() - _draw_started_at) / maxf(_config.bow_draw_time, 0.01),
		0.0, 1.0)


# ------------------------------------------------------------------- aiming ---

## The point the crosshair is over, or a point far along the view ray if it is
## over nothing. This is what makes a throw land where the reticle is instead of
## parallel to it.
##
## Under the PvP rig the crosshair is not an approximation of the shot, it *is*
## the shot (D-174): `aim_ray` is the actual `Camera3D`'s own origin and forward,
## wherever scenery has pulled it, so screen centre and the spear agree by
## construction rather than by a correction. D-045's unobstructed ray, and the
## reticle turn-in and rate limit that had to be built on top of it (D-088), are
## both gone. `camera_range`'s `aim` verdict reaches into this function, rather
## than a copy of it, precisely because this is the one a throw reads.
func _aim_point() -> Vector3:
	var rig := _bog.get_node_or_null("CameraRig") as BogCamera
	if rig == null:
		return _bog.global_position + _bog.facing() * 30.0
	var ray := rig.aim_ray()
	var origin: Vector3 = ray["origin"]
	var direction: Vector3 = ray["direction"]

	var space := _bog.get_world_3d().direct_space_state
	# Tested from the Bog's own depth outwards: nothing behind the thrower can be
	# thrown at, and the wall that pushed the lens in is behind it. `clear_of` is
	# the lens's own distance from the pivot now, which is why this survived the
	# shot moving onto the lens (D-174; D-025 by another route).
	var query := PhysicsRayQueryParameters3D.create(
		origin + direction * float(ray.get("clear_of", 0.0)),
		origin + direction * MAX_AIM_DISTANCE)
	query.collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_DEPLOYABLE
	query.exclude = [_bog.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return origin + direction * MAX_AIM_DISTANCE
	var point: Vector3 = hit["position"]
	if origin.distance_to(point) < MIN_AIM_DISTANCE:
		return origin + direction * MIN_AIM_DISTANCE
	return point


## The way the camera is pointing, flattened to horizontal and normalised.
##
## Only meaningful on the Bog's own client — `BogCamera` turns itself off on
## every other copy — so this is called where the input is read and the answer
## travels, never on the host's copy of somebody else's Bog. The fallback to the
## body's facing is the same one `_aim_point` makes and covers the same case: a
## Bog with no rig at all, which is every Bog in `tools/match_rules.gd` and every
## remote Bog everywhere.
func _look_direction() -> Vector3:
	var rig := _bog.get_node_or_null("CameraRig") as BogCamera
	if rig == null:
		return _bog.facing()
	var direction: Vector3 = rig.aim_ray()["direction"]
	var flat := Vector3(direction.x, 0.0, direction.z)
	# Straight down or straight up: there is no horizontal component to take, so
	# fall back rather than normalising a zero.
	if flat.length_squared() < 0.0001:
		return _bog.facing()
	return flat.normalized()


func _throw_origin() -> Vector3:
	var basis := Basis(Vector3.UP, _bog.body_yaw)
	return _bog.global_position + Vector3.UP * _bog.eye_height() \
		+ basis * THROW_OFFSET


# ------------------------------------------------------- the drop indicator ---

## Keep the landing ring in step with where the Bog is pointing.
##
## Only while aiming, and only with a spear to throw — including the half second
## you are winding one up, because through the windup the aim is still live and
## is exactly what the release is about to read. A ring under an empty hand
## would be a promise the cooldown is not keeping.
##
## Deliberately gated on the aim button rather than shown all the time. Spears
## drop, and judging that drop is where a lot of the skill in the fight lives
## (D-014, D-025); a marker on screen at all times turns the throw from a thing
## you read into a thing you line up. Holding the button is the price of the
## answer, and it costs you the wider field of view while you ask.
func _tick_aim_marker() -> void:
	var rig := _bog.get_node_or_null("CameraRig") as BogCamera
	# An Elder gets no ring, and that is not an oversight. The marker answers
	# "where will this land given the drop", and a hitscan bolt has no drop to
	# answer about: it lands exactly on the crosshair. Drawing one anyway would
	# be the HUD promising a ballistic arc for a weapon that has none.
	# A drawing Bog gets no ring either, and for a sharper version of the
	# Elder's reason (D-065). The ring answers "where will this land given the
	# drop" — and for a bow that answer *slides outward as you charge*, because
	# the drop is a function of the draw. A ring that crept toward the horizon
	# while the string came back would be a charge meter drawn on the ground:
	# the tell done as UI, which is the one thing the user ruled out and which
	# D-036 threw off the crosshair. The string is the meter.
	if rig == null or not rig.is_aiming() or is_elder() \
			or not (has_spear() or _is_throw_windup()):
		_stow_aim_marker()
		return
	if _aim_marker == null:
		_aim_marker = AimMarker.new()
		_aim_marker.name = "AimMarker"
		# Hung off the Bog so it is freed with it and hidden with it, but the
		# marker is `top_level`, so the body walking and turning underneath does
		# not drag the ring around with it.
		_bog.add_child(_aim_marker)

	# The same two calls the release makes, in the same order, so the ring is
	# answering the question the throw is actually going to be asked.
	var origin := _throw_origin()
	var direction := (_aim_point() - origin).normalized()
	if direction.length_squared() < 0.001:
		_stow_aim_marker()
		return
	_aim_marker.aim(origin, direction, _bog.get_rid())


func _stow_aim_marker() -> void:
	if _aim_marker != null:
		_aim_marker.stow()


# ------------------------------------------------------------------- spear ---

## A click starts the throw; it does not make it. The arm goes back now and the
## spear leaves the hand `BogAnimator.THROW_RELEASE_TIME` later, at which point
## the aim is sampled and the host is asked. Nothing about *where* the spear
## goes is decided here, which is the whole change: a target that walks during
## your windup has to be led.
func try_throw_spear() -> void:
	# The Elder's click runs the same clip through the same windup and comes out
	# the other end as a bolt (D-038). It is branched here rather than at the
	# input so that everything downstream of a click — the animation, the relay
	# to the other peers, the cancel-on-death, the cancel-on-hold — is one piece
	# of code with one set of edge cases.
	if is_elder():
		try_cast_lightning()
		return
	if not has_spear() or is_busy():
		return

	_windup_release_at = _now() + BogAnimator.THROW_RELEASE_TIME
	# The input has been spent whether or not the spear has left yet, so the
	# click spends it. A tile that sits lit through half a second of windup only
	# invites the second click that will be refused.
	_spear_ready_at = _now() + spear_cycle()
	cooldowns_changed.emit()

	# Everyone else has to see the arm come back too, or the windup is a tell
	# only the thrower gets. The thrower plays it here and the host relays it to
	# the rest, because a client cannot address the other peers itself (D-024).
	_play_windup()
	if Net.is_host:
		_host_throw_windup()
	else:
		_request_throw_windup.rpc_id(1)


## The release. Runs on the throwing client only, one THROW_RELEASE_TIME after
## the click, and is the first moment anything about the aim is read.
func _tick_windup() -> void:
	if not is_winding_up():
		return
	# Dead, respawned, or no longer ours: the throw is off. The windup animation
	# is already playing and is left alone — it is cosmetic and fades out on its
	# own — but no spear comes out of it.
	#
	# Walking over a letter card mid-windup cancels it the same way (D-035). The
	# cooldown is handed back, which is not generosity: the host never saw a
	# throw, so its `_server_spear_ready_at` never moved, and leaving the local
	# prediction spent would be this client alone believing in a recharge
	# nothing else has. The spear comes back the moment the hold ends.
	if not _bog.alive or not _bog.is_local() or is_holding_letter():
		if _bog.alive and is_holding_letter():
			_spear_ready_at = 0.0
			_bow_ready_at = 0.0
			_sword_ready_at = 0.0
			_punch_ready_at = 0.0
			cooldowns_changed.emit()
		_windup_release_at = 0.0
		# A swing abandoned rather than landed, and the blade simply does not
		# connect: the same sentence again, one weapon further (D-068). The
		# *spin* is deliberately not cancelled with it — `Bog` owns that clock
		# and the body is already travelling; a Bog that stopped dead in the
		# middle of a swing because it walked onto a letter card would be the
		# animation and the physics disagreeing in the most visible way there
		# is. What it loses is the kill, which is what a cancel is.
		_swinging = false
		# A slash abandoned rather than landed, and a punch likewise: the same
		# sentence again, two outcomes further (the feel round). The chain's
		# clocks on the body are deliberately left to run out on their own, for
		# the spin's reason — `Bog` owns them, the animation is already playing
		# on eight machines, and a blade that vanished mid-cut because its owner
		# walked onto a letter card would be the drawing and the state
		# disagreeing in the most visible way there is.
		_punching = false
		# A punch cancelled hands its cooldown back with the spear's, above:
		# the host never saw one, so a spent local prediction would be this
		# client alone believing in a recharge nothing else has.
		# A draw abandoned rather than loosed, and the arrow is simply not
		# there: the same sentence the spear's cancel has said since D-025, one
		# field further. `_tick_draw` takes the charge off the body on the same
		# frame, so every peer's copy of this Bog stops drawing at once.
		_draw_started_at = 0.0
		_loose_charge = -1.0
		return
	# **The one line the bow adds to this function.** A draw is a windup with no
	# deadline in it — it ends when the player lets go, which happens in
	# `release_draw` — so until then there is nothing here to have arrived. Put
	# the other way round: everything below this line is the release tick, and
	# the bow reaches it by the same door as the other two.
	if _draw_started_at > 0.0:
		return
	if _now() < _windup_release_at:
		return
	_windup_release_at = 0.0

	# **The fourth outcome, and the only one that does not ask where the
	# crosshair is** (D-068). It is asked before the aim is read rather than
	# after, and that is the statement: three weapons leave this hand and go
	# where the camera is pointing, and the fourth is already out there. The
	# blade's own direction is what a swing is aimed by, it is on the skeleton,
	# and `_blade_direction` is the one place it is read.
	#
	# Being first also means a swing cannot be lost to the degenerate-aim guard
	# below, which returns without firing anything when the crosshair and the
	# throwing hand are on top of each other. That guard is right for a spear and
	# would be a silently dropped attack here.
	if _swinging:
		_swinging = false
		var blade := _blade_direction()
		if Net.is_host:
			_host_swing_sword(blade)
		else:
			_request_swing_sword.rpc_id(1, blade)
		return

	# **The fifth outcome and the sixth, and neither asks where the crosshair
	# is either** (the feel round). Both are beside the swing rather than under
	# it because they are the same kind of thing — a shape resolved in front of
	# a body — and both are ahead of the degenerate-aim guard below for the
	# reason the swing is: that guard is right for a thrown spear and would be a
	# silently dropped melee attack here.
	#
	# What they do *not* share with the swing is where "in front" comes from.
	# `SwordSpin` turns the body through a revolution inside its own skeleton,
	# so its direction has to be read off the bone attachment; a slash and a
	# punch are drawn going the way the body is already facing, and the player
	# has had the stick and the camera all the way through. So the answer is
	# `facing()` — read *here*, at the release, which is D-025's rule and means
	# a Bog that turned during its own wind-up cuts where it is looking now.
	if _slash_index > 0:
		var index := _slash_index
		var slash_aim := _bog.facing()
		if Net.is_host:
			_host_slash(index, slash_aim)
		else:
			_request_slash.rpc_id(1, index, slash_aim)
		return
	if _punching:
		_punching = false
		var fist := _bog.facing()
		if Net.is_host:
			_host_punch(fist)
		else:
			_request_punch.rpc_id(1, fist)
		return

	var origin := _throw_origin()
	var direction := (_aim_point() - origin).normalized()
	if direction.length_squared() < 0.001:
		_loose_charge = -1.0
		return
	# Asked *here* and not at the click, on purpose. Everything else about this
	# throw is decided at the release — the aim is, and that is the whole of
	# D-025 — so a Bog that walked over a robe mid-windup fires the weapon it has
	# now rather than the one it had when it pressed the button. The host asks
	# the same question again on arrival and is the copy that counts.
	#
	# Its *timing* stays the spear's, which is right: the robe arrived after the
	# arm did, the throw clip is already playing at the spear's rate, and the
	# release is where that arm actually lets go. A bolt out of a spear's windup
	# is a fifth of a second late by the dial and exactly on time by the
	# animation, and the animation is what anybody is looking at. Since D-064 it
	# is also a bolt out of a *throw* rather than out of a cast, and the mirror
	# of that is a spear out of a cast, when a robe burns out inside the fifth
	# of a second between an Elder's click and its release. Both are the same
	# trade and it is the right way round: the weapon is whichever one this Bog
	# has now, and the animation is the one the eye has already been following
	# for a fifth of a second. Restarting the clip here to match the weapon
	# would be a hand that snaps back to its side and starts again, which is a
	# worse lie than an arm finishing a motion its owner has changed its mind
	# about.
	# The third outcome, and it is here rather than in a path of its own for the
	# reason the second one is (D-025, D-038, D-064): the aim above it was read
	# once, the cancels above it were asked once, and a bow that wanted its own
	# copy of those would be a second set of the same four edge cases.
	#
	# It is asked *first* because it is the only one of the three that already
	# knows which weapon it is. An arrow that is one frame from leaving cannot
	# become a bolt because a robe arrived — the string has already gone, and
	# the shot was paid for at the draw. The other two go on branching at the
	# release exactly as they did, and for the reason written below.
	if _loose_charge >= 0.0:
		var charge := _loose_charge
		_loose_charge = -1.0
		if Net.is_host:
			_host_loose_arrow(origin, direction, charge)
		else:
			_request_loose_arrow.rpc_id(1, origin, direction, charge)
		return
	if is_elder():
		if Net.is_host:
			_host_cast_lightning(origin, direction)
		else:
			_request_cast_lightning.rpc_id(1, origin, direction)
		return
	if Net.is_host:
		_host_throw_spear(origin, direction)
	else:
		_request_throw_spear.rpc_id(1, origin, direction)


## Start the arm going, with whichever clip and whichever rate this Bog's weapon
## needs (D-040, D-064).
##
## Both are worked out here rather than handed in, and that is what keeps the
## Elder's fast windup honest on the seven machines that are only watching: this
## same function is what `_do_throw_windup` calls on every other peer, and it
## reaches the same answer from the same replicated robe and the same replicated
## config. Sending the rate with the relay would have been one more number on
## the wire that could be a different number at the far end — and sending the
## *clip* would be the same mistake with a worse failure, a Bog throwing a spear
## it does not have.
##
## This one branch is the whole of the fork. Everything downstream of it — the
## release tick, the aim, the cancel on death and on a letter, the cooldown —
## is the single piece of code D-025 and D-038 exist to keep single.
func _play_windup() -> void:
	var animator := _bog.get_node_or_null("AnimationTree") as BogAnimator
	if animator == null:
		return
	if is_elder():
		animator.play_cast(windup_rate())
	else:
		animator.play_throw(windup_rate())


# ------------------------------------------------------------------ emote ---

## True while this Bog is dancing. The state itself is `Bog.emoting`, because
## the body is where the two things it changes are written; this node owns the
## *decisions* about it — when it may start, every way it ends, and the relay
## that puts the same answer on the other seven machines.
func is_emoting() -> bool:
	return _bog != null and _bog.emoting


## May this Bog start dancing? Alive, on the ground, not standing a letter down
## into a pouch, and not already mid-action — which is `is_busy()` plus the one
## that is not a windup, a draw held down. Deliberately **not** gated on a
## cooldown or on the weapon: an emote costs nothing and every Bog has one.
##
## **A carry is not a hold, and that is D-157.** This asked
## `is_holding_letter()`, which is both kinds of hold at once, so a Bog running
## a card to a vault could not taunt anybody — which is the one moment in the
## match a player most wants to. `Bog.is_capturing()` is the timed half alone:
## there the hands are genuinely busy, one arm raised over a pouch with a letter
## sinking into it (D-131), and a body that danced out from under that
## performance would be showing two things at once. A carry is a card in the
## fist and a run, and the card stays in the fist through the dance — the fist
## is where "this one has the letter" reads from (D-050), so it is the one thing
## `_bare_handed()` does not empty.
func can_emote() -> bool:
	return _bog != null and _bog.alive and _bog.is_on_floor() \
		and not is_busy() and not _bog.is_drawing() and not _bog.is_capturing() \
		and not _bog.is_crouching() and not _bog.is_spinning()


## The key. A toggle, and the only caller of the two below that a player has.
func toggle_emote() -> void:
	if is_emoting():
		stop_emote()
	elif can_emote():
		start_emote()


## Start dancing here and ask for it to be started everywhere. Same shape as the
## throw's wind-up and for the same reason (D-024): a client cannot address the
## other peers itself, so it plays its own copy now and the host relays.
func start_emote() -> void:
	if _bog == null or is_emoting():
		return
	_bog.emoting = true
	_relay_emote(true)


## Stop dancing, everywhere. **The one exit**, called by the key, by
## `refresh_emote` below and by the two places in `Bog` that see a reason the
## body knows about first — a movement input and a hit. It is safe to call on a
## Bog that is not dancing, which is what lets all of those be unconditional.
func stop_emote() -> void:
	if _bog == null or not _bog.emoting:
		return
	_bog.emoting = false
	_relay_emote(false)


## Tell the other seven, **from the owner only**.
##
## The two above are called on every peer, not just the dancer's: a hit ends an
## emote and `Bog.set_health` runs everywhere, so every copy of a Bog that just
## took one clears its own flag on the same frame. That is a prediction and it
## is welcome — it is the same answer the relay is about to carry. What must not
## happen is eight machines all asking the host to broadcast it: a client would
## be refused (`_request_emote` checks the sender owns the Bog) and the host
## would be speaking for a player it is not, so the ask is the owner's alone and
## everybody else waits for `_do_emote` to confirm what it already guessed.
func _relay_emote(on: bool) -> void:
	if not _bog.is_local():
		return
	if Net.is_host:
		_host_emote(on)
	else:
		_request_emote.rpc_id(1, on)


## Every way an emote ends that is not a keypress and not something `Bog` sees
## first, asked once a frame on the owning client.
##
## **One refresh path and no flags.** The alternative was a `stop_emote()` in
## each of the eight functions that can end it — the throw, the swing, the draw,
## the cast, the drink, the pick-up, the jump and the death — which is eight
## places to forget, and D-025's whole lesson about the wind-up's cancels is
## that a list of them belongs in one function. So this asks `can_emote()` again:
## everything that may not *start* an emote may not let one continue either, and
## the two lists cannot drift apart because they are one list.
func refresh_emote() -> void:
	if _bog == null or not _bog.emoting:
		return
	# The owner decides and the relay carries it. A remote copy that stopped
	# itself on its own idea of `is_busy()` would stop on a frame nobody else
	# stopped on, which is the desync the relay exists to avoid.
	if not _bog.is_local():
		return
	if not can_emote():
		stop_emote()


@rpc("any_peer", "call_remote", "reliable")
func _request_emote(on: bool) -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _bog.peer_id:
		return
	_host_emote(on)


## Deliberately not gated on anything but life, exactly as the throw's wind-up
## relay is not gated on the host's cooldown: this is cosmetic, the owner has
## already decided, and a host that second-guessed it would show seven people a
## Bog that is not doing what its player is looking at.
func _host_emote(on: bool) -> void:
	if _bog == null or not _bog.alive:
		return
	_do_emote.rpc(on)
	_do_emote(on)


@rpc("authority", "call_remote", "reliable")
func _do_emote(on: bool) -> void:
	# The dancer already set its own flag on the keypress. Setting it again when
	# the host's relay lands would restart nothing — it is a bool — but it would
	# also undo a stop the player made half a round trip in, so the owner is
	# skipped here the way it is skipped in `_do_throw_windup`.
	if _bog == null or _bog.is_local():
		return
	_bog.emoting = on


@rpc("any_peer", "call_remote", "reliable")
func _request_throw_windup() -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _bog.peer_id:
		return
	_host_throw_windup()


## Deliberately not gated on the host's cooldown. This is a cosmetic tell, and
## refusing it would only hide the wind-up from everyone while the throw that
## follows is checked properly anyway; a Bog that winds up and produces no spear
## is a truthful picture of a client that asked for a throw it could not have.
func _host_throw_windup() -> void:
	if not _bog.alive:
		return
	_do_throw_windup.rpc()
	_do_throw_windup()


@rpc("authority", "call_remote", "reliable")
func _do_throw_windup() -> void:
	# The thrower already played this on its own click. Playing it again when the
	# host's relay lands would restart the arm half a round trip in and leave the
	# animation running behind the spear it is supposed to be launching.
	if _bog == null or _bog.is_local():
		return
	_play_windup()


@rpc("any_peer", "call_remote", "reliable")
func _request_throw_spear(origin: Vector3, direction: Vector3) -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _bog.peer_id:
		return
	_host_throw_spear(origin, direction)


func _host_throw_spear(origin: Vector3, direction: Vector3) -> void:
	if not _bog.alive or _now() < _server_spear_ready_at:
		return
	# The authoritative half of the hold gate (D-035). The client refuses to ask
	# while it is holding a card; this is what makes that true of a client that
	# has been modified not to, and the row it reads is the host's own — the
	# only copy of a hold that can be trusted or finished.
	if is_holding_letter():
		return
	# The client picks the aim, but not the spawn point: clamping the origin to
	# somewhere near the Bog stops a modified client throwing from across the map.
	if origin.distance_to(_bog.global_position) > 3.0:
		origin = _throw_origin()
	_server_spear_ready_at = _now() + _config.spear_recharge
	_do_throw_spear.rpc(origin, direction.normalized())
	_do_throw_spear(origin, direction.normalized())


## The release, on every machine. No `play_throw()` here any more: the windup
## started the animation THROW_RELEASE_TIME ago on every peer and firing the
## OneShot again would snap the arm back to the start of the throw at the exact
## moment the spear leaves it.
@rpc("authority", "call_remote", "reliable")
func _do_throw_spear(origin: Vector3, direction: Vector3) -> void:
	_spear_ready_at = _now() + _config.spear_recharge
	cooldowns_changed.emit()

	# The fist empties on the frame the spear leaves it rather than on the next
	# one, which is what `_tick_hand` would otherwise do — a single frame, but
	# the single frame in which everybody watching would see a spear in a hand
	# that has just thrown one.
	_refresh_hand()

	AudioDirector.play_3d_varied(AudioDirector.SPEAR_THROW, origin)
	var spear := SPEAR.launch(_spawn_root(), _bog, origin, direction, Net.is_host)
	spear.struck_bog.connect(_on_spear_struck_bog.bind(spear))
	_bog.threw_spear.emit(origin, direction)
	weapon_launched.emit("spear")


## Put the spear back in the hand when the recharge ends — and take it away if
## something else did.
##
## **A poll rather than a timer, and this is the second one in this file** — see
## `_tick_charge`, which is the same shape for the Elder's crackle and carries
## the same argument. What used to be here was a `SceneTreeTimer` started at the
## moment the throw was made, awaiting `spear_recharge` and then calling
## `_refresh_hand` once:
##
##     await get_tree().create_timer(_config.spear_recharge).timeout
##     _refresh_hand()
##
## which is two clocks measuring one interval. `_spear_ready_at` is a
## `Time.get_ticks_msec()` deadline and a `SceneTreeTimer` is a sum of frame
## deltas; they agree to about a millisecond, and a millisecond the wrong way
## means `has_spear()` is still false on the frame the timer fires. The hand is
## then correctly left empty, by a callback that has already been spent —
## **nothing ever asks again**, and the spear does not come back until the next
## death. That is exactly the "the spear model is not reliably reappearing"
## that was reported, and it is why a race lost by a millisecond reads as a
## whole feature being flaky.
##
## Making the timer *report* rather than *decide* was right and is kept: this
## still asks `_refresh_hand`, which asks `has_spear()`, which is the one gate
## the throw is refused by (D-035, D-036). A letter hold may have started during
## the recharge, and a shaft that put itself back would sit in a fist that is
## supposed to be holding a card. **The bug was the missing retry, not the
## delegation.** So the retry is every frame, off the only clock that decides
## anything, and the `await` is gone rather than kept beside it — two clocks
## measuring one interval is the fault, and leaving one of them in place as an
## optimisation would leave it there to be believed.
##
## Cheap by construction, the same way `_tick_charge` is: one boolean
## comparison, doing nothing at all unless the hand and the gate have come
## apart. That is a handful of times a second across every Bog in the match.
func _tick_hand() -> void:
	if _bog.held_gear == null:
		return
	var want := _wants_shaft()
	# Four questions and not one, because the hands came apart (D-065) and then
	# a fourth thing started appearing in one of them (D-068): a bow that should
	# be there and is not is the same bug as a shaft that should be there and is
	# not, and the poll that catches one has to catch all four or it is a poll
	# with a hole in it. Still one comparison each, still doing nothing at all on
	# the frames nothing has changed.
	#
	# The sword is the one of the four whose answer changes on a clock nobody
	# sent a message about — `Bog.is_spinning()` simply runs out — so it is the
	# one this poll is load-bearing for rather than merely tidy about.
	if _bog.held_gear.is_carried() == want \
			and _bog.held_gear.has_bow() == _wants_bow() \
			and _bog.held_gear.has_arrow() == _wants_arrow() \
			and _bog.held_gear.has_sword() == _wants_sword() \
			and _bog.held_gear.has_potion() == _wants_potion():
		return
	_refresh_hand()
	cooldowns_changed.emit()
	# Only on the transition into "armed", and only for the Bog whose hand it
	# is: it is a readiness cue for the player, not an event in the world that
	# gives your position away to everyone nearby. The `is_carried() == want`
	# check above is what makes "once" true — the poll runs every frame and this
	# line is only reached on the frame the answer changed.
	#
	# The gate and not `want`, because `want` is also true through a windup: a
	# chime at the moment the arm goes back would be announcing a spear that is
	# on its way out of the hand rather than back into it. And a Bog
	# mid-letter-hold never reaches here at all, which is the point D-035 makes
	# about a cue that lies.
	#
	# `_weapon_ready()` and not `has_spear()` since D-069. It used to be the
	# spear's alone because every Bog had a spear and the other two were extras;
	# now two players in three never carry one, and a readiness cue that only
	# fires for a third of the lobby is a cue that has quietly been deleted for
	# the rest of it. Exactly one of the three can be true at a time, so this is
	# still one chime on the one frame the answer changed.
	if _bog.alive and _bog.is_local() and _weapon_ready():
		AudioDirector.play_2d(AudioDirector.SPEAR_READY)


## Has this Bog's own weapon — whichever one it picked — just become available?
##
## The loadout makes the three gates mutually exclusive (`carries` is true of at
## most one), so this is a disjunction that can never be ambiguous: it is "is the
## weapon I brought in my hand", asked without the caller having to know which
## one that is.
func _weapon_ready() -> bool:
	return has_spear() or has_bow() or has_sword()


## Should this fist be holding a shaft right now?
##
## One expression, asked by the two places that could disagree about it — the
## hand refresh that acts on it and the per-frame poll that notices it has gone
## stale — for exactly the reason `_wants_crackle` is written this way. Two
## copies that drift by one clause is a Bog whose hand is repainted on every
## frame for ever.
##
## The `is_winding_up()` clause is D-025's carve-out: between the click and the
## release the spear has been paid for but has not left, and a hand that emptied
## on the click would be an arm going back with nothing in it. `has_spear()`
## already answers no for an Elder, so the extra `is_elder()` is only about that
## window — an Elder winding a bolt up must not be handed a shaft by it.
func _wants_shaft() -> bool:
	return not is_elder() and not is_holding_letter() and not _bog.is_drawing() \
		and not is_swinging() and not _bare_handed() \
		and (has_spear() or _is_throw_windup())


# --------------------------------------------------------------------- bow ---

## How much of a draw a client is allowed to claim beyond what the host saw.
##
## The charge travels with the loose, because the client is the only machine
## that knows when a key came up — so like the throw's origin it is **checked
## rather than believed**. The host watches the same replicated float everybody
## else does (`_watch_draw`) and clamps the claim to the furthest it saw the
## string go, plus this.
##
## It is not slack in the mechanic, it is slack in the *measuring*. `sync_draw`
## is ON_CHANGE and arrives when it arrives; the host's last sample of an honest
## draw is a tick or two behind the value that client loosed at, and clamping to
## exactly what arrived would shave every shot in the game by whatever the
## network happened to cost. A tenth of a draw is six ticks at the default draw
## time, which is several times any plausible lag and is worth, at the top of
## the curve, about six damage. What it cannot do is let a client claim a full
## draw it never made: that is the whole 1.0, and it is ten times this.
const DRAW_CLAIM_GRACE := 0.1


## Start drawing. **The one attack in this file that is not started by a click**
## (D-065), and the one that spends nothing to start.
##
## `try_throw_spear` pays its cooldown on the click, because the input has been
## spent whether or not the spear has left. A draw has not been spent: it can be
## held, judged, and let go for a worse shot or abandoned entirely when the
## target walks behind a tree, and every one of those is a decision the player
## should be able to make for free. So the recharge starts at the *loose*
## (`release_draw`) and what the draw costs is the only currency this weapon
## actually trades in, which is standing still in the open with a tell on you.
func try_draw_bow() -> void:
	if not has_bow() or is_busy():
		return
	_draw_started_at = _now()
	# The arrow appears in the fist on this frame rather than the next, which is
	# what `_tick_hand`'s poll would otherwise do — a single frame, but the
	# single frame in which everybody watching would see a string coming back
	# with nothing on it.
	_refresh_hand()
	cooldowns_changed.emit()


## Let go of the string.
##
## Everything this decides it decides *now* and hands to the release tick one
## frame later: the charge is latched here because the key came up here, and
## `BogAnimator.BOW_RELEASE_TIME` is the one frame between the fingers opening
## and the arrow being gone. Where it goes is still read at the release, like
## every other weapon's, and is still read in exactly one place (D-025).
##
## Called from `_process` on the key-up, and by `tools/combat_range.gd`, which
## is why it is a function rather than an `Input` read inside `_tick_windup`: a
## headless harness has to be able to let go of a string.
func release_draw() -> void:
	if _draw_started_at <= 0.0:
		return
	_loose_charge = draw_fraction()
	_draw_started_at = 0.0
	_windup_release_at = _now() + BogAnimator.BOW_RELEASE_TIME
	# Spent here and not at the draw, for the reason in `try_draw_bow`. The
	# local prediction covers the release as well as the recharge so the tile
	# does not blink lit for one frame between the two.
	_bow_ready_at = _now() + BogAnimator.BOW_RELEASE_TIME + _config.bow_recharge
	cooldowns_changed.emit()


## Put the charge on the body, hand it to the bowstring, and — on the host —
## remember how far this Bog was actually seen to draw.
##
## **A poll, and the third one in this file**, beside `_tick_hand` and
## `_tick_charge`, for the reason both of those are: there is exactly one clock
## in a draw and it is `_draw_started_at`; anything that kept a second copy
## ticking alongside it would be a second opinion about a number eight machines
## have to agree on.
##
## The two halves go in opposite directions and that is the whole design. The
## owner *writes* `Bog.draw`, because the key it is holding is knowledge only it
## has. Everything else — this Bog's own animator, this Bog's own bowstring, the
## seven other people's copies of both — *reads* `Bog.draw_fraction()`, which
## answers off the replicated value on a copy the local player does not own. One
## number, one direction, and no path by which what an archer sees in its hands
## can differ from what the clearing sees in them (D-025).
func _tick_draw() -> void:
	if _bog.held_gear == null:
		return
	if _bog.is_local():
		# -1 for "not drawing", which is `Bog.sync_draw`'s out-of-band value and
		# is why there is no second flag here to disagree with this float. The
		# frame between letting go and the arrow leaving is *not* a draw: the
		# string has gone, so it snaps back to brace and the loose fires off the
		# same edge on every peer (`BogAnimator._track_draw`).
		_bog.draw = draw_fraction() if _draw_started_at > 0.0 else -1.0
	_bog.held_gear.set_draw(_bog.draw_fraction())
	if Net.is_host:
		_watch_draw()


## Host-side: how far this Bog has been seen to draw, so that a loose can be
## checked against something rather than taken on trust.
##
## Off `Bog.is_drawing()`, which on the host's copy of a remote Bog is the
## replicated float and on its own is the local one — so this is one piece of
## code for the host's own shots and for everybody else's, which is the same
## property `windup_rate` has and for the same reason.
func _watch_draw() -> void:
	var drawing := _bog.is_drawing()
	if drawing and not _server_drawing:
		_server_draw_peak = 0.0
	if drawing:
		_server_draw_peak = maxf(_server_draw_peak, _bog.draw_fraction())
	_server_drawing = drawing


@rpc("any_peer", "call_remote", "reliable")
func _request_loose_arrow(origin: Vector3, direction: Vector3, charge: float) -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _bog.peer_id:
		return
	_host_loose_arrow(origin, direction, charge)


## The shot, decided on the host and nowhere else.
##
## Three things are checked and not believed, and they are the same three the
## throw and the cast check: the recharge, the gates, and the origin. The fourth
## is the bow's own and is the reason this weapon needed a host-side field at
## all — **the charge**. A client that sent 1.0 the instant it pressed the key
## would have a free 80-damage snap shot, which is the one thing a lobby dial
## could never be blamed for, so the claim is clamped to the draw this machine
## watched happen (`_watch_draw`, `DRAW_CLAIM_GRACE`).
func _host_loose_arrow(origin: Vector3, direction: Vector3, charge: float) -> void:
	if not _bog.alive or _now() < _server_bow_ready_at:
		return
	# The authoritative half of the two gates the client already refused itself
	# on (D-035, D-038): a Bog holding a card up has no hand free to draw with,
	# and an Elder has lightning instead of a bow. Both read the host's own
	# rows, which are the only copies that can be trusted.
	if is_holding_letter() or is_elder():
		return
	if origin.distance_to(_bog.global_position) > 3.0:
		origin = _throw_origin()
	var aim := direction
	if not aim.is_finite() or aim.length_squared() < 0.0001:
		aim = _bog.facing()
	aim = aim.normalized()
	var drawn := clampf(charge, 0.0, minf(1.0, _server_draw_peak + DRAW_CLAIM_GRACE))
	_server_draw_peak = 0.0
	_server_drawing = false
	_server_bow_ready_at = _now() + _config.bow_recharge
	# The *charge* travels and the damage does not, which is the same choice
	# `_play_windup` makes about the rate: every peer works the numbers out for
	# itself from one replicated float and one replicated config, so there is
	# nothing on the wire that could arrive as a different number at the far
	# end. Only the host's copy of the arrow ever reports what it did.
	_do_loose_arrow.rpc(origin, aim, drawn)
	_do_loose_arrow(origin, aim, drawn)


## The loose, on every machine.
##
## There is no `play_loose()` here and that is not an omission — the loose
## animation fires off the *replicated draw ending*, in `BogAnimator`, the way a
## remote Bog's dive fires off a serial (D-026). A message would be a second way
## to start the same animation, arriving at a different time from the float that
## put the string back at brace.
@rpc("authority", "call_remote", "reliable")
func _do_loose_arrow(origin: Vector3, direction: Vector3, charge: float) -> void:
	_bow_ready_at = _now() + _config.bow_recharge
	cooldowns_changed.emit()
	# The nocked arrow goes on the frame the real one appears, exactly as the
	# shaft does, so nobody ever sees two arrows.
	_refresh_hand()

	# The loose, and almost none of it is the string: the arrow takes the
	# energy and what is heard is the limbs arriving at brace (`bow_loose` in
	# `tools/make_sfx.py`).
	#
	# `play_3d` and not `play_3d_varied`, because **the charge is the
	# variation**. A fuller draw is a tighter string, a harder limb return and
	# a louder loose, and that is a number every peer already agrees on — it
	# travelled with this RPC, for the same reason the damage did not — where
	# `play_3d_varied` would have each machine pick its own random spread for
	# the same shot. A snap shot is a dull knock and a full draw cracks.
	AudioDirector.play_3d(AudioDirector.BOW_LOOSE, origin,
		0.92 + 0.16 * charge, -5.0 + 5.0 * charge)
	var arrow := ARROW.loose(_spawn_root(), _bog, origin, direction, charge,
		_config, Net.is_host)
	arrow.struck_bog.connect(_on_arrow_struck_bog.bind(arrow))
	weapon_launched.emit("bow")


func _on_arrow_struck_bog(victim: Bog, point: Vector3, bone: String,
		arrow: ArrowProjectile) -> void:
	# Only the host's copy of an arrow is allowed to decide anything.
	if not arrow.authoritative or not Net.is_host:
		return
	# `arrow.damage` and not a constant, which is the whole difference between
	# this weapon and the spear next door: `SPEAR_DAMAGE` is a whole Bog written
	# as `Bog.MAX_HEALTH` so that no dial can soften it, and this is a number
	# eight sliders can move (D-062, D-065). Both go through the same door.
	MatchState.report_damage(victim.peer_id, _bog.peer_id, arrow.damage,
		Bog.Cause.ARROW, point, arrow.impact_velocity(), bone)


## Should the left fist be holding a bow right now?
##
## `_wants_shaft`'s twin, and shorter for one reason: nothing else is ever in
## this hand, so there is no "or a card, or a crackle" to be exclusive with. The
## windup carve-out is D-025's, one weapon further along — a bow has to stay in
## the hand through the draw *and* through the frame between the loose and the
## arrow, and `is_drawing()` is asked of the **body** rather than of the local
## `_bow_in_use()` so that it is true on every peer's copy and not only on the
## archer's.
func _wants_bow() -> bool:
	return not is_elder() and not is_holding_letter() and not is_swinging() \
		and not _bare_handed() and (has_bow() or _bog.is_drawing())


## Should the right fist have an arrow nocked in it?
##
## Only while the string is actually back, which is what makes it a tell worth
## having: a Bog carrying a bow with no arrow on it is a Bog that cannot shoot
## you this second. Off the replicated draw, like the bow above.
func _wants_arrow() -> bool:
	return not is_elder() and not is_holding_letter() and not _bare_handed() \
		and _bog.is_drawing()


## Should the bow fist be holding a bottle right now (D-075)?
##
## `_wants_bow`'s twin in the same hand, and the two are exact opposites through
## a channel: a drink is the one thing that empties this fist, so it is also the
## one thing that fills it. `is_channelling()` is the whole of it, because that
## flag is already the answer to every question this one could ask separately —
## it runs on every peer's copy of every Bog (D-067), it goes false the instant
## the bottle is empty or the drink is broken, and `_end_channel` calls
## `_refresh_hand` on that frame rather than on the next (D-069).
##
## The other two clauses are the hand rule rather than the gate, and they are
## the same two `_wants_bow` carries. They are also, strictly, already true:
## `_host_drink_potion` refuses an Elder and a letter-holder, and picking a card
## up mid-drink breaks the channel. They are written out anyway, because the
## four `_wants_*` above are four statements of one sentence about what may be
## in a fist, and a fifth that quietly relied on somebody else having checked
## would be the one that is wrong the day the channel gate moves.
func _wants_potion() -> bool:
	return not is_elder() and not is_holding_letter() and not _bare_handed() \
		and is_channelling()


## Should the bow fist be holding the loot pouch right now (the letters round)?
##
## `_wants_potion`'s sibling in this fist and its exact mirror image: that one
## is *not holding a letter and channelling*, this one is *holding a letter and
## being timed*, so the two can never both be true and the exclusivity is a
## property of the sentences rather than of anything remembering to check.
##
## **`is_timed` is the whole of the second clause, and it is the line that
## separates the two letters games.** A Capture B·O·G carry is the same hold row
## with `ends_at = INF` — nothing is counting down, the card is being *run*
## somewhere — and that Bog keeps the card up in its fist exactly as it has
## since D-035. A timed capture is the one with a clock, and it is the one the
## owner asked for a performance for: *"players might incorrectly assume you can
## punch, so make it so they are actually doing something with their hands —
## capturing."* So the pouch, the raised arm (`BogAnimator`) and the floating
## letter (`CaptureRig`) all hang off this one question, asked of `MatchState`
## every time for `is_holding_letter`'s reason — the host owns the clock and a
## copy here would be a second one.
##
## **It is the one `_wants_*` here with no `_bare_handed()` clause, and that is
## deliberate rather than an omission.** The other five carry it because a
## holster and an emote are two ways of saying "this Bog is not holding its
## weapon", and a great sword hanging off a twerking Bog reads as a bug
## (D-105). A pouch is not a weapon: there is nothing to put away, because a
## letter hold has already disarmed this Bog (D-035), and the sack is the
## *destination* of a descent that is still running — `CaptureRig` aims the
## shrinking letter at `pouch_mouth_global()` whatever the hands are doing, so
## taking the pouch away mid-capture would leave a card sinking into thin air
## at the hip. A dancing Bog with a sack is a joke; a dancing Bog swallowing a
## letter with nothing there is a broken effect.
func _wants_pouch() -> bool:
	return is_holding_letter() and MatchState.letter_hold_is_timed(_bog.peer_id)


## Should the fists be holding a great sword right now (D-068, D-069)?
##
## `_wants_shaft`'s fourth sibling, and since D-069 the closest of the four to
## it: **the great sword is carried.** It was not, and the reason it was not is
## written into D-068 in as many words — "there is no weapon-select in this game,
## so a carried great sword would be a Bog that had permanently given up its
## spear". There is a weapon-select now, and a Bog that picked the sword *has*
## permanently given up its spear. The premise is gone, so the exception is.
##
## It matters more than tidiness. `HeldGear`'s own header says what empty hands
## mean: *"seeing an empty pair of them across the clearing is how you know it is
## safe to approach"*. A swordsman with nothing in its fists is a melee one-shot
## wearing the one tell this game reserves for harmless, which is the worst lie
## the hand could tell — and a carried sword is also the whole of the user's
## *"your character should only show the weapon you have selected"* for one of
## the three picks.
##
## `has_sword() or is_swinging()`, which is the shaft's `has_spear() or
## _is_throw_windup()` with the sword's own carve-out: the click spends the
## cooldown, so `has_sword()` goes false the instant the swing starts and
## `is_spinning()` is what keeps the blade in the fists through the 1.867 s the
## clip runs. After it the recharge is still running and the hands are genuinely
## empty, exactly as they are between a throw and the spear growing back.
##
## The other two clauses are the hand rule rather than the gate: an Elder has
## lightning instead of its weapons and a fist holding a letter card is not
## holding a hilt. They can both become true *during* a swing, and when they do
## the sword goes out of the fists on the same frame the blade stops connecting
## (`_tick_windup`) while the body goes on spinning, which is exactly the right
## three things to happen.
## The chain adds `in_chain()` beside `is_swinging()` and it is the same
## carve-out a third time (the feel round): a slash spends the recharge the
## moment it starts, so `has_sword()` goes false for the whole chain and the
## body's own chain clock is what keeps the blade in the fists — through the
## slashes *and* through the grace between them, because a great sword that
## blinked out for a sixth of a second while its owner decided whether to swing
## again would be the hand disagreeing with the weapon once per click.
func _wants_sword() -> bool:
	return not is_elder() and not is_holding_letter() and not _bare_handed() \
		and (has_sword() or is_swinging() or in_chain())


# -------------------------------------------------------- the great sword ---

## A click starts the swing; it does not land it (D-068). The body commits to a
## direction and an advance now, the blade connects
## `BogAnimator.SWING_RELEASE_TIME` later, and what it connects *with* is read
## off the skeleton at that moment rather than off the body's facing at this one
## — which on this clip are more than a hundred degrees apart.
##
## Shaped like `try_throw_spear` down to the order of the lines, because it is
## the same machinery: the click spends the cooldown whether or not the swing
## lands, the attacker plays its own feedback immediately, and the host relays it
## to everyone else because a client cannot address the other peers (D-024).
##
## The one line that is not the throw's is `_begin_swing`, and it is not a second
## windup — it is the *commitment*: the sword into the fists, the clip into the
## graph and the advance into the body, all three on every machine, all three off
## the same call.
##
## **Since the feel round this is the sprint attack rather than the click.** It
## is reached from `try_sword_attack` when the body is already travelling at
## `SPRINT_ATTACK_SPEED` of run, and a standing click gets the slash chain
## instead. Nothing inside it changed, and the name did not either: the spin is
## a whole mechanic with its reach fitted to its clip and three harness modes
## asking for it by name, and renaming it would have been a rename dressed up as
## a design.
func try_swing_sword() -> void:
	if not has_sword() or is_busy():
		return

	_windup_release_at = _now() + BogAnimator.SWING_RELEASE_TIME
	_swinging = true
	# The input has been spent whether or not the blade finds anybody, so the
	# click spends it — `try_throw_spear`'s reason, and a stronger one here,
	# because the swing is 1.867 s of animation nobody can interrupt.
	_sword_ready_at = _now() + sword_cycle()
	cooldowns_changed.emit()

	_begin_swing()
	if Net.is_host:
		_host_swing_windup()
	else:
		_request_swing_windup.rpc_id(1)


## Start the clip, the clock and the advance on this machine (D-068).
##
## `_begin_channel`'s twin, and it is the same shape for the same reason: this is
## the one attack in this file whose visible life is longer than its own release,
## so every peer has to run it rather than being told about each frame of it. The
## clock is `Bog`'s (`begin_spin`), which is what `is_swinging()` reads and what
## the sword in the fists is drawn from; the clip is fired at its authored rate,
## which no dial moves; and the advance is latched by `Bog` on the owning client
## only, because movement is client-authoritative (D-004).
##
## `_refresh_hand` on this frame rather than on the next, which is what
## `_tick_hand`'s poll would otherwise do: a single frame, but the single frame
## in which everybody watching would see a Bog start a two-handed swing holding a
## spear.
func _begin_swing() -> void:
	if _bog == null:
		return
	_bog.begin_spin(BogAnimator.SWING_SECONDS, BogAnimator.SWING_ADVANCE)
	var animator := _bog.get_node_or_null("AnimationTree") as BogAnimator
	if animator != null:
		animator.play_swing()
	# The whoosh belongs to the swing and not to the hit, so it is fired here
	# rather than in `_do_swing_sword` — for the same reason the clip is. This
	# is the one function every peer runs at **clip time zero**, and
	# `SWORD_SWING` is 1.867 s of blade built to be loudest 1.067 s in, which
	# is `SWING_RELEASE_TIME`, which is where the build measures peak hand
	# speed, which is where a sword cuts. Fired at the landing instead it
	# would start where it was meant to peak.
	#
	# Pitch is deliberately left alone: `play_3d_varied`'s 12% spread would
	# slide that peak up to a tenth of a second off the blade, and a whoosh
	# that peaks somewhere the blade is not reads as a different swing.
	AudioDirector.play_3d(AudioDirector.SWORD_SWING, _bog.global_position)
	_refresh_hand()
	cooldowns_changed.emit()


## Which way the blade is pointing, flattened, at the instant it connects
## (D-068).
##
## **The one place the sweep's direction is read, and it is read off the bone
## attachment.** `Swing` turns the body through a whole revolution *inside the
## skeleton* — `lock_root_motion` does nothing to yaw and `align_facing` applies
## one constant rotation — so `_bog.facing()` at this moment is roughly where the
## player was pointing when they clicked and the sword is somewhere else
## entirely. A sweep along the body's own basis would be a sweep at nothing,
## every time, and it would look correct in every code review.
##
## From the Bog's axis to the **point**, and not along the blade from guard to
## point, because what the arc is centred on is the body: `_sword_victims` asks
## "is this Bog within the reach, in the direction the blade is out in", and the
## direction the blade is *out in* is where its far end is relative to the body
## that is holding it.
##
## `HeldGear.sword_blade()` is what reads the attachment, and D-066's trap is why
## it has to: `Skeleton3D.get_bone_global_pose()` does not see a
## `SkeletonModifier3D`, so a bone pose read from here is the pose before `BogAim`
## touched the torso. `BoneAttachment3D` updates off `skeleton_updated`, which
## fires after the modifier stack, so the attachment is the only reading that
## agrees with what the player can see.
func _blade_direction() -> Vector3:
	if _bog == null:
		return Vector3.FORWARD
	if _bog.held_gear == null:
		return _bog.facing()
	var blade: Array = _bog.held_gear.sword_blade()
	var point: Vector3 = blade[0]
	var out := point - _bog.global_position
	out.y = 0.0
	# Straight up or straight down through the body's own axis: there is no
	# horizontal component to take, so fall back rather than normalising a zero.
	# The same guard `_look_direction` makes, about the same impossibility.
	if out.length_squared() < 0.0001:
		return _bog.facing()
	return out.normalized()


## Watch the blade turn, so the swipe can be drawn the way it went (D-168).
##
## One reading a frame and only while a blade is out, which is `_tick_charge`'s
## shape: a poll on the one thing that can answer, rather than a field somebody
## has to remember to set. The sense is *latched* — it survives to the next
## attack — because the frame the hit lands on is occasionally a frame in which
## the pose did not advance, and a swipe that fell back to "left" on those would
## be a swipe that sometimes ran backwards through its own arc.
##
## Every stage of the chain gets its own answer for free, which is the whole
## reason this is measured rather than tabled: `SwordCombo` was drawn as one
## continuous motion, so slash 2 starts where slash 1's follow-through left the
## blade and the three cuts do not all go the same way. A table of directions
## per slash would be a second copy of that, and it would rot the first time the
## clip's markers moved.
func _tick_blade_sweep() -> void:
	if _bog == null or not (is_swinging() or is_slashing()):
		_blade_seen = Vector3.ZERO
		return
	var out := _blade_direction()
	if _blade_seen != Vector3.ZERO:
		var turned := _blade_seen.signed_angle_to(out, Vector3.UP)
		if absf(rad_to_deg(turned)) >= BLADE_SENSE_MIN:
			_blade_sense = signf(turned)
	_blade_seen = out


## Draw the sector the host just hit with (D-168).
##
## **The one place the hit's geometry becomes a picture, and it is handed the
## same locals the hit was decided from.** `reach` and `arc` are the two
## arguments `_sword_victims` was called with, so the fan on screen cannot be a
## different shape from the swing that produced it — there is no second set of
## constants to keep in step.
##
## The one conversion is `Bog.CAPSULE_RADIUS`, and it belongs here rather than
## in `SwordSwipe` because it is a fact about the *rule*: the reach is measured
## to a body's surface (`Bog.distance_to_body`), so the locus of places a Bog
## can be *standing* and still die is the dial plus its own radius. That is the
## question a player is asking when they look at this — "does that one die if I
## swing now" — and drawing the dial instead would draw a fan that is a body's
## width short of the kills it is a claim about.
##
## Run on every peer from the `_do_*` handlers, so everybody watching sees where
## your sword kills and not only you.
func _show_swipe(centre: Vector3, blade: Vector3, reach: float,
		arc: float) -> void:
	SwordSwipe.sweep(_spawn_root(), centre, blade,
		reach + Bog.CAPSULE_RADIUS, arc, _blade_sense)


@rpc("any_peer", "call_remote", "reliable")
func _request_swing_windup() -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _bog.peer_id:
		return
	_host_swing_windup()


## Deliberately not gated on the host's cooldown, exactly as `_host_throw_windup`
## is not. This is the tell — a great sword appearing in a Bog's fists and a body
## winding into a spin — and refusing it would only hide it from everyone while
## the hit that follows is checked properly anyway.
func _host_swing_windup() -> void:
	if not _bog.alive:
		return
	_do_swing_windup.rpc()
	_do_swing_windup()


@rpc("authority", "call_remote", "reliable")
func _do_swing_windup() -> void:
	# The swinger already did this on its own click. Doing it again when the
	# host's relay lands would restart the clip and the clock half a round trip
	# in, which on a 1.867 s commitment is a Bog visibly rewinding.
	if _bog == null or _bog.is_local():
		return
	_begin_swing()


@rpc("any_peer", "call_remote", "reliable")
func _request_swing_sword(blade: Vector3) -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _bog.peer_id:
		return
	_host_swing_sword(blade)


## The hit, decided on the host and nowhere else (D-068).
##
## Three things are checked and not believed and they are the throw's three: the
## recharge, the gates, and — in place of the origin — the **blade**. The
## direction travels because the client is the only machine whose copy of this
## Bog is at the release frame *now*: every peer plays the same clip, but the
## host's copy started when the relay landed and under any lag is a tick or two
## behind, and this clip sweeps 415 degrees, so "a tick or two behind" is tens of
## degrees of blade. Reading it here would be more wrong more often than trusting
## it, which is the same trade `DRAW_CLAIM_GRACE` records for the bow: slack in
## the *measuring*, not in the mechanic.
##
## What a modified client can do with it is choose which way its own swing points
## after committing to the advance — inside a 150 degree arc it was going to have
## anyway, at 1.4 m, having spent a second of undodgeable animation to get there.
## What it cannot do is choose *who dies*: everything past this line is the
## host's own geometry.
func _host_swing_sword(blade: Vector3) -> void:
	if not _bog.alive or _now() < _server_sword_ready_at:
		return
	# The authoritative half of the two gates the client already refused itself
	# on (D-035, D-038), off the host's own rows, which are the only copies that
	# can be trusted or finished.
	if is_holding_letter() or is_elder():
		return
	var aim := Vector3(blade.x, 0.0, blade.z)
	if not aim.is_finite() or aim.length_squared() < 0.0001:
		aim = _bog.facing()
	aim = aim.normalized()
	_server_sword_ready_at = _now() + _config.sword_recharge

	var centre := _bog.body_centre()
	var victims := _sword_victims(aim)
	# Broadcast before the damage is reported, so that on every peer the swing
	# lands with the body rather than after it — the same ordering
	# `_host_cast_lightning` keeps for the same reason, and both are reliable so
	# the order they are sent in is the order they arrive in.
	_do_swing_sword.rpc(centre, aim, not victims.is_empty())
	_do_swing_sword(centre, aim, not victims.is_empty())

	for other: Bog in victims:
		# The same door everything else goes through, and the same number the
		# spear uses. Whether this hit does anything — spawn protection,
		# friendly fire, a Bog already dead, an Elder's ward — belongs to
		# `report_damage` and is not second-guessed here (D-062).
		var chest := other.body_axis_nearest(centre)
		MatchState.report_damage(other.peer_id, _bog.peer_id, SWORD_DAMAGE,
			Bog.Cause.SWORD, chest, aim * SWORD_IMPULSE,
			SpearProjectile.nearest_bone(other, chest))

	_swing_range_targets(centre, aim)


## The practice range's boards and gong, caught by the same swing.
##
## **The one place a weapon reaches something that is not a Bog and has to be
## told about it.** A spear or an arrow asks the question itself, off the
## collider its own sweep returned, and needs nobody's help; the sword has no
## projectile and its geometry is the host's alone (D-068), so this is the only
## attack whose reaction has to travel.
##
## The two tests are `_sword_victims`' own, deliberately: the same `reach`, the
## same `SWORD_ARC`, read from the same locals, so a board and a Bog standing in
## the same place are both hit or both missed. What is added is the target's own
## radius, because a 1.4 m plank is not a point and a swing that clipped its edge
## should count. No line-of-sight test, unlike a Bog's: a board is not something
## another board can hide behind, and the range has nothing to shield with.
##
## Guarded on the map rather than on the group being empty, so that outside a
## practice map this is one boolean and not a tree walk per swing. Off `_config`
## rather than `MatchState.config()`, because that is the copy the rest of this
## function already reads its reach out of — one source, and no singleton hop on
## a path that runs on every swing in the game.
## The reach, the cause and the arc are handed in for `_sword_victims`' reason,
## and the `cause` is what the board is told hit it: a plank knocked by a fist
## should say so, and `RangeTarget` keeps no list of what may hit it.
func _swing_range_targets(centre: Vector3, aim: Vector3, reach: float = -1.0,
		cause: int = Bog.Cause.SWORD, arc: float = SWORD_ARC) -> void:
	if _config == null or not _config.is_practice():
		return
	if reach < 0.0:
		reach = maxf(_config.sword_reach, 0.01)
	var limit := cos(deg_to_rad(arc))
	for target: Node in get_tree().get_nodes_in_group("range_targets"):
		var body := target as Node3D
		if body == null or not body.has_method("range_hit"):
			continue
		var to := body.global_position - centre
		var radius := 0.0
		if body.has_method("hit_radius"):
			radius = float(body.call("hit_radius"))
		if to.length() > reach + radius:
			continue
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length_squared() > 0.0001 and flat.normalized().dot(aim) < limit:
			continue
		# Broadcast and then run locally, the ordering every other host-decided
		# reaction in this file keeps.
		body.call("range_hit_broadcast", body.global_position, _bog.peer_id,
			cause)


## Every living Bog the swing catches (D-068).
##
## Two tests, both required, and one of them is the same line `_blast_victims`
## uses. The *surface* of the Bog's capsule is within `sword_reach` of the
## swinger's own body centre — `Bog.distance_to_body`, so a crouched Bog is a
## smaller target for a sword exactly as it is for a spear and for the blast —
## and the bearing to it is inside `SWORD_ARC` of the blade.
##
## Line of sight is the third, and it is here for the reason it is there: a
## shield is cover, and a blade swung at somebody standing behind a barricade
## has to hit the boards. Tested from the swinger's chest to the nearest point on
## the victim's own axis, through the world and through deployables and not
## through other Bogs — a body that one body shields another from is a rule
## nobody could read off the screen.
##
## The swinger is excluded and so is every dead Bog: corpses keep their collision
## until they respawn (D-043), and a swing that killed a corpse would be three
## seconds of a weapon hitting things that are already down.
## Since the feel round it takes the reach and the arc rather than reading the
## dial itself, because there are three melee shapes now and only one geometry:
## the spin at the dial, a slash at the dial plus its step, and a fist at 1.1 m
## inside a narrower front. Three callers and one function, which is the whole
## reason a slash cannot quietly acquire a different line-of-sight rule or a
## different way of excluding corpses than the swing it came from.
func _sword_victims(blade: Vector3, reach: float = -1.0,
		arc: float = SWORD_ARC) -> Array[Bog]:
	var out: Array[Bog] = []
	if reach < 0.0:
		reach = maxf(_config.sword_reach, 0.01)
	var limit := cos(deg_to_rad(arc))
	var centre := _bog.body_centre()
	var space := _bog.get_world_3d().direct_space_state
	for other: Bog in MatchState.bogs.values():
		if not is_instance_valid(other) or other == _bog or not other.alive:
			continue
		if other.distance_to_body(centre) > reach:
			continue
		var target := other.body_axis_nearest(centre)
		var toward := Vector3(target.x - centre.x, 0.0, target.z - centre.z)
		# A Bog standing on top of this one has no bearing to be inside an arc,
		# and is close enough to be hit by anything: the arc test is skipped
		# rather than answered with the normalisation of a zero.
		if toward.length_squared() > 0.0001 \
				and toward.normalized().dot(blade) < limit:
			continue
		var query := PhysicsRayQueryParameters3D.create(centre, target)
		query.collision_mask = LAYER_WORLD | LAYER_DEPLOYABLE
		query.collide_with_areas = false
		query.collide_with_bodies = true
		if space.intersect_ray(query).is_empty():
			out.append(other)
	return out


## The swing landing, on every machine. There is no `play_swing()` here: the clip
## started `SWING_RELEASE_TIME` ago on every peer and firing the one-shot again
## would snap the body back to the start of the spin on the exact frame the blade
## goes through somebody.
##
## `connected` travels rather than being worked out per peer, because it is the
## host's answer and nobody else has one — the whole point of the geometry being
## the host's. It decides one thing: whether the blade went through a body,
## which is the only feedback this weapon has (D-036 and D-054 keep it off the
## crosshair).
##
## The whoosh is **not** decided here and is not sent. It belongs to the swing
## rather than to the hit, so `_begin_swing` fires it on every peer at clip time
## zero and a swing through air is simply that whoosh with nothing on the end of
## it — which is also the only thing a miss should sound like.
##
## The blade is no longer ignored here and that is D-168: it and `point` are the
## two things the host's sector was built from, so every peer can draw the sector
## rather than be told what it looked like. The reach is read locally off
## `_config`, which is the same replicated dial the host measured with — sending
## it would be a third copy of a number every machine already has.
@rpc("authority", "call_remote", "reliable")
func _do_swing_sword(point: Vector3, blade: Vector3, connected: bool) -> void:
	_sword_ready_at = _now() + _config.sword_recharge
	cooldowns_changed.emit()
	_show_swipe(point, blade, maxf(_config.sword_reach, 0.01), SWORD_ARC)
	if connected:
		AudioDirector.play_3d_varied(AudioDirector.SWORD_HIT_BODY, point)
	# Here and not in `_begin_swing`, which is where a swing *starts*. The windup
	# is deliberately ungated (`_host_swing_windup` says so) so that the tell
	# plays even for a swing the host is about to refuse on the recharge, a
	# letter hold or the Elder — and counting those would be counting shots that
	# can never land. This is the accepted swing, which is what the other three
	# `_do_*` handlers emit for as well.
	weapon_launched.emit("sword")


# ---------------------------------------------------------- the slash chain ---

## The great sword's click, and the one place its two attacks choose between
## themselves (the feel round).
##
## D-068 bought one attack with a 1.867 s commitment on it, and a season of
## playing it said the same thing every time: the weapon is either a kill or a
## second and a half of standing in the open having missed. So the click is now
## a **chain of three slashes** — 50 each, a quarter of a second each, the stick
## and the camera and the jump all still yours — and the spin it used to be is
## still there, as the **sprint attack**: get to 0.8 of run speed and the same
## button fires the same committed revolution for the same 100.
##
## **`try_swing_sword` is untouched below and is now the sprint attack's own
## door.** That is deliberate and not an accident of refactoring: the spin is a
## whole mechanic with a decision record, a reach fitted to its clip and three
## harness modes measuring it, and every one of those asks for it by name.
##
## The chain's follow-up click is taken *before* `is_busy()`, which is the only
## carve-out in this function: `in_chain()` is one of that function's own terms,
## so a chained click would otherwise be refused by the very state it continues.
## What it is not allowed to skip is the **wind-up** — a click before this
## slash's blade has passed is refused, so a player cannot cancel their own hit
## by being early, and the window a chain is actually taken in runs from the
## connect to `end_N` plus `SLASH_CHAIN_GRACE`.
func try_sword_attack() -> void:
	if _bog == null or not _bog.alive:
		return
	if _slash_index > 0:
		# Mid-chain. The three terms of `is_busy()` that are not the chain
		# itself, asked one at a time rather than through it.
		if is_winding_up() or is_channelling() or is_swinging():
			return
		if not _sword_in_hand() or not in_chain() or _slash_index >= SLASH_MAX:
			return
		_open_slash(_slash_index + 1)
		return
	if not has_sword() or is_busy():
		return
	if _bog.ground_speed() >= Bog.RUN_SPEED * SPRINT_ATTACK_SPEED:
		try_swing_sword()
		return
	_open_slash(1)


## Start slash `index` here and ask for it everywhere (the feel round).
##
## `try_swing_sword`'s shape with one number moved: the click spends the
## recharge, and what it spends it *to* is the end of the chain rather than the
## end of this slash. `_sword_ready_at` is pushed to the far side of the window
## the next click would be taken in, so `has_sword()` is false for the whole
## chain — which is exactly right, because inside a chain the only legal attack
## is the next slash and `try_sword_attack` above asks a different question for
## it. A chain that ends early simply leaves the deadline where the last slash
## put it, so the recharge genuinely runs **between chains** and never between
## slashes, which is what `sword_recharge`'s new default is sized for.
func _open_slash(index: int) -> void:
	_slash_index = index
	_windup_release_at = _now() + BogAnimator.slash_release(index)
	_sword_ready_at = _now() + BogAnimator.slash_seconds(index) \
		+ SLASH_CHAIN_GRACE + _config.sword_recharge
	cooldowns_changed.emit()

	_begin_slash(index)
	if Net.is_host:
		_host_slash_windup(index)
	else:
		_request_slash_windup.rpc_id(1, index)


## Put slash `index` on this machine: the clip, the two clocks and the step
## (the feel round). `_begin_swing`'s twin, and it is relayed exactly as that
## one is — **an event with the slash number on it, not a replicated field.**
##
## The alternative considered was a `sync_slash_serial` bumped per slash with
## the index packed into it. It would work, and it is the wrong tool twice
## over: the swing already relays its wind-up as an event because that is what a
## cross-faded one-shot needs (D-105 makes the same argument about the emote),
## and a chain is a *sequence of events* rather than a continuous quantity
## anybody has to sample. A serial would be a second road carrying the same
## news, and the index would have to be packed into an int to keep the two from
## arriving apart. The relay is reliable and ordered, so slash 2 cannot land
## before slash 1, which is the only ordering property this needs.
##
## `_refresh_hand` on this frame rather than on the next, for `_begin_swing`'s
## reason: one frame, but the frame in which everybody watching would see a Bog
## start a slash with a spear's carry pose still on its shoulders.
func _begin_slash(index: int) -> void:
	if _bog == null:
		return
	_bog.begin_slash(BogAnimator.slash_seconds(index),
		BogAnimator.slash_seconds(index) + SLASH_CHAIN_GRACE, SLASH_STEP)
	var animator := _bog.get_node_or_null("AnimationTree") as BogAnimator
	if animator != null:
		animator.play_slash(index)
	# `play_3d_varied` where the spin uses `play_3d`, and the spin's own comment
	# is why: its pitch is held because the whoosh is built to peak where the
	# blade is, and three slashes inside a second with identical pitch would be
	# the one place in this game a sound reads as a loop rather than as a fight.
	AudioDirector.play_3d_varied(AudioDirector.SWORD_SWING, _bog.global_position)
	_refresh_hand()
	cooldowns_changed.emit()


## Close the chain on the tick the body says it is over. The owner's
## bookkeeping only: the clocks that matter to anybody else are `Bog`'s and run
## out by themselves.
func _tick_slash() -> void:
	if _slash_index == 0 or in_chain():
		return
	_slash_index = 0
	cooldowns_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_slash_windup(index: int) -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _bog.peer_id:
		return
	_host_slash_windup(index)


## Ungated like the swing's wind-up and for its reason: this is the tell, and
## hiding it from everybody would only mean a blade nobody saw coming for a hit
## that is checked properly anyway.
func _host_slash_windup(index: int) -> void:
	if not _bog.alive:
		return
	var slash := clampi(index, 1, SLASH_MAX)
	_do_slash_windup.rpc(slash)
	_do_slash_windup(slash)


@rpc("authority", "call_remote", "reliable")
func _do_slash_windup(index: int) -> void:
	# The swinger already did this on its own click; doing it again half a round
	# trip later would restart the clip mid-cut.
	if _bog == null or _bog.is_local():
		return
	_begin_slash(clampi(index, 1, SLASH_MAX))


@rpc("any_peer", "call_remote", "reliable")
func _request_slash(index: int, aim: Vector3) -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _bog.peer_id:
		return
	_host_slash(index, aim)


## The slash's hit, decided on the host and nowhere else — `_host_swing_sword`
## with three things different (the feel round).
##
## **The chain is checked and not believed.** A client sends which slash it
## thinks it is on; the host keeps its own index and its own window, and accepts
## a number only if it is the next one and the window it opened is still open.
## So a modified client cannot send slash 3 three times, and cannot open a chain
## it has not paid the recharge for. What it can do is choose *when* inside its
## own window, which is the same slack `DRAW_CLAIM_GRACE` records for the bow.
##
## The reach is the dial **plus the step**, because the body moved: a slash that
## measured its victims from where the Bog was standing when the clip started
## would refuse the hit the animation visibly lands.
func _host_slash(index: int, aim: Vector3) -> void:
	# `_sword_in_hand()` rather than the two clauses `_host_swing_sword` spells
	# out, because it is the same list and one more: the pick, the robe, the
	# card, the bottle and the holster, off the host's own rows and the owner's
	# own replicated bool, which are the only copies that can be trusted.
	if not _bog.alive or not _sword_in_hand():
		return
	if not _host_chain_open(index):
		return
	var slash := clampi(index, 1, SLASH_MAX)
	_server_slash_index = slash
	_server_slash_until = _now() + BogAnimator.slash_seconds(slash) + SLASH_CHAIN_GRACE
	_server_sword_ready_at = _server_slash_until + _config.sword_recharge

	var blade := Vector3(aim.x, 0.0, aim.z)
	if not blade.is_finite() or blade.length_squared() < 0.0001:
		blade = _bog.facing()
	blade = blade.normalized()

	var centre := _bog.body_centre()
	var reach := slash_reach()
	var victims := _sword_victims(blade, reach)
	# Broadcast before the damage is reported, the ordering every host-decided
	# reaction in this file keeps.
	_do_slash.rpc(centre, blade, not victims.is_empty())
	_do_slash(centre, blade, not victims.is_empty())

	for other: Bog in victims:
		var chest := other.body_axis_nearest(centre)
		MatchState.report_damage(other.peer_id, _bog.peer_id, SLASH_DAMAGE,
			Bog.Cause.SWORD, chest, blade * SLASH_IMPULSE,
			SpearProjectile.nearest_bone(other, chest))

	_swing_range_targets(centre, blade, reach, Bog.Cause.SWORD)


## May the host accept `index` as the next slash? The chain's gate, on the
## host's own clocks. A lapsed window is cleared here rather than on a timer,
## because nothing needs to know it lapsed until somebody asks.
func _host_chain_open(index: int) -> bool:
	if _now() > _server_slash_until:
		_server_slash_index = 0
	if _server_slash_index == 0:
		return index == 1 and _now() >= _server_sword_ready_at
	return index == _server_slash_index + 1 and index <= SLASH_MAX


## How far a slash reaches: the dial plus the step it takes to get there. One
## function so the host's geometry, the range targets and any harness reading it
## all say the same number.
func slash_reach() -> float:
	return maxf(_config.sword_reach, 0.01) + SLASH_STEP


## The slash landing, on every machine. No `play_slash` here: the clip started
## `slash_release(index)` ago on every peer and firing it again would snap the
## blade back to the start of the cut on the frame it goes through somebody.
##
## The blade travels here since D-168 for the swing's reason, and the reach is
## `slash_reach()` rather than the dial: a slash claims the metres its step buys
## it, so a fan drawn at the dial would be a fan 0.35 m short of the cut it is
## a picture of.
@rpc("authority", "call_remote", "reliable")
func _do_slash(point: Vector3, blade: Vector3, connected: bool) -> void:
	_show_swipe(point, blade, slash_reach(), SWORD_ARC)
	if connected:
		AudioDirector.play_3d_varied(AudioDirector.SWORD_HIT_BODY, point)
	weapon_launched.emit("sword")


# ------------------------------------------------------------------- fists ---

## The punch: a click with your weapon put away (the feel round).
##
## Shaped like `try_swing_sword` down to the order of the lines, because it is
## the same machinery a sixth time — the click spends the cooldown whether or
## not the fist finds anybody, the puncher plays its own feedback immediately,
## and the host relays it because a client cannot address the other peers
## (D-024).
##
## The gate is one clause and it is the holster: `is_holstered()` is already
## everything this needs to ask, because holstering is refused while dead, mid
## wind-up, drawing, dancing or holding a card, and every one of those would
## have been a clause here. `is_busy()` is asked as well and only covers what
## can *start* after the key: a punch already thrown.
func try_punch() -> void:
	if _bog == null or not _bog.alive or not is_holstered():
		return
	if is_busy() or punch_cooldown() > 0.0:
		return

	_windup_release_at = _now() + BogAnimator.PUNCH_RELEASE_TIME
	_punching = true
	_punch_ready_at = _now() + PUNCH_CYCLE
	cooldowns_changed.emit()

	_begin_punch()
	if Net.is_host:
		_host_punch_windup()
	else:
		_request_punch_windup.rpc_id(1)


## The arm going — the whole body, since D-158, when it is thrown standing — on
## this machine. There is no hand to repaint, because a punching Bog is
## holstered and both fists are already empty and stay that way; and no clock on
## the body either, because the shot ends when the clip ends and the speed is
## never scaled, which is the whole of what "you keep moving and turning at full
## speed" means. `BogAnimator.play_punch` is the one line that knows how much
## body this one gets, and it decides off the legs it can already see.
func _begin_punch() -> void:
	if _bog == null:
		return
	var animator := _bog.get_node_or_null("AnimationTree") as BogAnimator
	if animator != null:
		animator.play_punch()


@rpc("any_peer", "call_remote", "reliable")
func _request_punch_windup() -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _bog.peer_id:
		return
	_host_punch_windup()


func _host_punch_windup() -> void:
	if not _bog.alive:
		return
	_do_punch_windup.rpc()
	_do_punch_windup()


@rpc("authority", "call_remote", "reliable")
func _do_punch_windup() -> void:
	if _bog == null or _bog.is_local():
		return
	_begin_punch()


@rpc("any_peer", "call_remote", "reliable")
func _request_punch(aim: Vector3) -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _bog.peer_id:
		return
	_host_punch(aim)


## The punch's hit, decided on the host and nowhere else.
##
## **The host checks that the attacker actually has its weapon away**, which is
## the one gate this attack has and the only thing a client could lie about that
## would be worth anything: a Bog that punched with its spear still out would be
## a free 20 damage beside a weapon it had not spent. `sync_holstered` is the
## owner's own replicated bool, so the host is reading the same field every
## other peer draws the empty fists from, a tick or two old — which is slack in
## the measuring and cannot be slack in the mechanic, because the value the host
## reads is the value the *client* published rather than one it claims now.
func _host_punch(aim: Vector3) -> void:
	if not _bog.alive or is_holding_letter() or not is_holstered():
		return
	if _now() < _server_punch_ready_at:
		return
	_server_punch_ready_at = _now() + PUNCH_CYCLE

	var fist := Vector3(aim.x, 0.0, aim.z)
	if not fist.is_finite() or fist.length_squared() < 0.0001:
		fist = _bog.facing()
	fist = fist.normalized()

	var centre := _bog.body_centre()
	var victims := _sword_victims(fist, PUNCH_REACH, PUNCH_ARC)
	_do_punch.rpc(centre, not victims.is_empty())
	_do_punch(centre, not victims.is_empty())

	for other: Bog in victims:
		var chest := other.body_axis_nearest(centre)
		MatchState.report_damage(other.peer_id, _bog.peer_id, PUNCH_DAMAGE,
			Bog.Cause.FIST, chest, fist * PUNCH_IMPULSE,
			SpearProjectile.nearest_bone(other, chest))

	# A board, the gong and a dummy's target all answer `range_hit`, and a fist
	# is a thing that hits them: the practice range should let you thump the
	# gong with your hands (D-116). The *stats* panel ignores it, because
	# `RangeStats.BY_CAUSE` has no row for a fist and `weapon_for` answers with
	# nothing — which is the right way round, since what that panel counts is
	# practice with a weapon.
	_swing_range_targets(centre, fist, PUNCH_REACH, Bog.Cause.FIST, PUNCH_ARC)


## The punch landing, on every machine. `FIST_HIT` rather than the sword's hit,
## which is what this borrowed while the fist had no clip of its own (D-149):
## a punch is a fifth of a body and has to sound like one.
@rpc("authority", "call_remote", "reliable")
func _do_punch(point: Vector3, connected: bool) -> void:
	if connected:
		AudioDirector.play_3d_varied(AudioDirector.FIST_HIT, point)
	# Its own name on the signal, so the range's launch/hit bookkeeping can tell
	# a fist from a weapon — and `RangeStats.WEAPONS` deliberately has no "fist"
	# row, so `record_launch` drops it on the floor.
	weapon_launched.emit("fist")


# --------------------------------------------------------------- lightning ---

## The Elder's click. Reached from `try_throw_spear` and shaped exactly like it,
## because it *is* it: the same clip, the same aim read at the same moment
## (D-038).
##
## What is deliberately not here is a charge-up, a beam, a channel or a warning
## ring on the ground.
##
## **The window the target gets is now a fifth of a second, not two thirds of
## one** (D-040). D-038's argument for reusing the release time was that the
## animation is the warning — and it still is, it is just a much shorter one:
## the user played it and asked for "basically no delay", and a weapon that
## announces itself for two thirds of a second is not the weapon they were
## asking for. The clip is sped up to match rather than cut short
## (`windup_rate`), because an arm still on its way out when the bolt leaves is
## the one thing that would read as broken rather than as fast. Since D-064 it
## is the Elder's own `Cast` being sped up rather than the spear's `Throw`.
func try_cast_lightning() -> void:
	if not has_lightning() or is_busy():
		return

	# The dial, not the clip. `_tick_windup` compares against this, and the clip
	# is then sped up to arrive at the same moment — the number leads and the
	# animation follows, which is the opposite way round from the spear and is
	# the whole of what D-040 changed here.
	_windup_release_at = _now() + release_delay()
	# Spent on the click, like the spear's, so a second click during the windup
	# is refused by the gate rather than by nothing.
	_lightning_ready_at = _now() + lightning_cycle()
	cooldowns_changed.emit()

	# The hand is deliberately *not* refreshed here. The crackle stays through
	# the windup exactly as the shaft does — `_refresh_hand` allows both while
	# `is_winding_up()` — because an arm going back with nothing in it is the
	# bug that carve-out exists to prevent, and it would look identical here.
	_play_windup()
	if Net.is_host:
		_host_throw_windup()
	else:
		_request_throw_windup.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_cast_lightning(origin: Vector3, direction: Vector3) -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _bog.peer_id:
		return
	_host_cast_lightning(origin, direction)


## The shot, decided on the host and nowhere else.
##
## Hitscan: a ray, no projectile, no travel time, nothing to lead. Which is also
## why the cooldown is longer than the spear's — see `MatchConfig`.
##
## **Cover works, and that is the reason the bolt comes out of a hand rather
## than out of the sky.** The ray collides with the world and with deployables,
## so a shield stops it exactly as it stops a spear. A strike from
## above would have been easier to aim and easier to draw, and it would have
## silently broken the one object in this game whose entire definition is "cover
## you cannot be hit through" (D-038).
func _host_cast_lightning(origin: Vector3, direction: Vector3) -> void:
	if not _bog.alive or not is_elder():
		return
	if _now() < _server_lightning_ready_at:
		return
	# The authoritative half of the hold gate, the same one the throw has
	# (D-035): the client refuses to ask while it is holding a card, and this is
	# what makes that true of a client that has been modified not to.
	if is_holding_letter():
		return
	# The client picks the aim, never the spawn point — clamping the origin to
	# somewhere near the Bog is what stops a modified client casting from across
	# the map, and it is the same clamp the spear uses.
	if origin.distance_to(_bog.global_position) > 3.0:
		origin = _throw_origin()
	# A client is free to send a zero, a NaN, or a vector pointing nowhere.
	var aim := direction
	if not aim.is_finite() or aim.length_squared() < 0.0001:
		aim = _bog.facing()
	aim = aim.normalized()
	_server_lightning_ready_at = _now() + _config.lightning_cooldown

	var hit := _lightning_hit(origin, aim)
	var point: Vector3 = hit.get("position", origin + aim * lightning_range())
	var victim := hit.get("collider") as Bog
	# A surface normal, or nothing when the bolt stopped on a body or on thin
	# air. It decides only whether there is a scorch to draw and which way the
	# sparks come off, and a body is neither scorched nor a wall to bounce from.
	var normal: Vector3 = Vector3.ZERO
	if victim == null and hit.has("normal"):
		normal = hit["normal"]
	# The blast only exists where the bolt *landed* (D-053). A bolt that ran out
	# into the sky or to the end of its range struck nothing, and a sphere of
	# death hanging in mid-air 28 m away is not "hit pretty close", it is a
	# second, invisible weapon. Zero travels as "no ring".
	var radius := _config.lightning_radius if not hit.is_empty() else 0.0

	# The bolt is broadcast before the kill is reported, so that on every peer
	# the light arrives with the body rather than after it. `report_kill` sends
	# its own death message and both are reliable, so the order they are sent in
	# is the order they land in.
	_do_cast_lightning.rpc(origin, point, normal, radius)
	_do_cast_lightning(origin, point, normal, radius)

	if victim != null:
		# Everything about *whether* this hit does anything — spawn protection,
		# friendly fire, a victim who is already dead, an Elder's ward — belongs
		# to `report_damage` and is not second-guessed here. The bolt landed on
		# them either way, which is the truthful picture: a protected Bog was
		# struck and was not hurt.
		MatchState.report_damage(victim.peer_id, _bog.peer_id, LIGHTNING_DAMAGE,
			Bog.Cause.LIGHTNING, point, aim * LIGHTNING_IMPULSE,
			SpearProjectile.nearest_bone(victim, point))

	if radius <= 0.0:
		return
	for other: Bog in _blast_victims(point, point - aim * BLAST_LOS_BACKOFF,
			radius, victim):
		# The same door the direct hit goes through, for the same reasons. The
		# blast is a kill or it is nothing — no falloff with distance from the
		# impact, which was forced when the game had no health in it and is a
		# choice now that it has: see `LIGHTNING_DAMAGE`. Everything inside the
		# ring takes a full body's worth.
		var chest := other.body_axis_nearest(point)
		var shove := chest - point
		if shove.length_squared() < 0.0001:
			shove = aim
		MatchState.report_damage(other.peer_id, _bog.peer_id, LIGHTNING_DAMAGE,
			Bog.Cause.LIGHTNING, chest, shove.normalized() * LIGHTNING_IMPULSE,
			SpearProjectile.nearest_bone(other, point))


## Every living Bog the blast at `point` reaches, other than the caster and the
## one the bolt landed on directly (D-053).
##
## "Reaches" is two things, both required. The *surface* of the Bog's capsule is
## within `radius` of the impact — `Bog.distance_to_body`, so the ring drawn at
## `radius` around the impact is exactly the line a body has to be touching —
## and there is a clear line from the impact to the body through the world and
## through deployables. The second is what keeps cover meaning what D-038 says
## it means: a bolt into the far side of a wall or into a planted shield
## does not kill the Bog crouched behind it.
##
## Line of sight is tried to the nearest point on the Bog's axis and then to the
## middle of the capsule, so a body half behind a low ledge is still in the open
## by its chest. Other Bogs are not cover — the ray does not test the player
## layer — because a blast that one body shields another from is a rule nobody
## could read off the screen.
func _blast_victims(point: Vector3, los_from: Vector3, radius: float,
		direct: Bog) -> Array[Bog]:
	var out: Array[Bog] = []
	var space := _bog.get_world_3d().direct_space_state
	for other: Bog in MatchState.bogs.values():
		# Dead Bogs keep their collision (D-043) and are not there to be killed.
		if not is_instance_valid(other) or other == _bog or other == direct \
				or not other.alive:
			continue
		if other.distance_to_body(point) > radius:
			continue
		var targets: Array[Vector3] = [other.body_axis_nearest(point),
			other.body_centre()]
		for target: Vector3 in targets:
			var query := PhysicsRayQueryParameters3D.create(los_from, target)
			query.collision_mask = LAYER_WORLD | LAYER_DEPLOYABLE
			query.collide_with_areas = false
			query.collide_with_bodies = true
			if space.intersect_ray(query).is_empty():
				out.append(other)
				break
	return out


## What the bolt hit, or an empty dictionary for thin air.
##
## Dead Bogs are excluded along with the caster. A Bog that has been killed keeps
## its collision until it respawns — only the body is hidden — so without this a
## corpse's invisible capsule would eat bolts for the length of a respawn delay,
## which is three seconds of a weapon that visibly stops in mid-air.
func _lightning_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	var space := _bog.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * lightning_range())
	query.collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_DEPLOYABLE
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var skip: Array[RID] = [_bog.get_rid()]
	for other: Bog in MatchState.bogs.values():
		if is_instance_valid(other) and not other.alive:
			skip.append(other.get_rid())
	query.exclude = skip
	return space.intersect_ray(query)


## The bolt, on every machine. Everything visible about this weapon happens
## here; the host's copy of this call is not special in any way except that it
## is the one that already knew the answer.
@rpc("authority", "call_remote", "reliable")
func _do_cast_lightning(origin: Vector3, point: Vector3, normal: Vector3,
		radius: float = 0.0) -> void:
	_lightning_ready_at = _now() + _config.lightning_cooldown
	cooldowns_changed.emit()
	# The fist goes dark on every peer's copy, which is the whole point of the
	# tell: everyone watching an Elder can see that it has just spent its shot.
	_refresh_hand()
	# The radius travels with the bolt rather than being read off each peer's
	# own config, so the ring on every screen is the one the host killed with.
	LightningBolt.strike(_spawn_root(), origin, point, normal, _bog, radius)
	weapon_launched.emit("lightning")


## Put the crackle back when the cooldown ends — and take it away if something
## else did.
##
## A **poll rather than a timer**, and that is the whole of why it exists. The
## shaft used to be put back by a `SceneTreeTimer` started at the moment
## `_spear_ready_at` was set, which is two clocks measuring one interval: a
## `Time.get_ticks_msec()` deadline and a sum of frame deltas. They agree to
## within a millisecond, and a millisecond the wrong way means `has_spear()` is
## still false on the frame the timer fires and nothing ever asks again. This
## asks the only clock that decides anything, every frame, and cannot drift from
## it.
##
## That argument was written here first and was right, and the spear went on
## losing the race it describes for a whole session anyway, because it was made
## about the crackle rather than about both. `_tick_hand` is now its twin — the
## same six lines for the shaft — and the two of them are the only things in
## this file that decide what is in a Bog's hand.
##
## Cheap by construction: one boolean comparison, only on Bogs that are the
## Elder, doing nothing at all unless the hand and the gate have come apart.
func _tick_charge() -> void:
	if _bog.held_gear == null or not is_elder():
		return
	var want := _wants_crackle()
	if _bog.held_gear.is_charged() == want:
		return
	_refresh_hand()
	cooldowns_changed.emit()
	# Only the Bog whose hand it is needs to hear this, and only when the hand
	# genuinely lit up: it is a readiness cue for the player, not an event in
	# the world that gives an Elder's position away to everyone nearby. Borrowed
	# rather than invented, like the pickup's — there is no second chime in
	# `audio/sfx/` and SPEAR_READY already means "you can act again".
	if want and _bog.is_local() and has_lightning():
		AudioDirector.play_2d(AudioDirector.SPEAR_READY)


## Should this fist be crackling right now?
##
## One expression, asked by the two places that could disagree about it — the
## hand refresh that acts on it and the per-frame poll that notices it has gone
## stale. They were two copies of the same condition for about ten minutes, and
## two copies that drift by one clause is a Bog whose hand is repainted on every
## frame for ever.
##
## The `is_winding_up()` clause is the same carve-out the shaft gets (D-025):
## between the click and the release the shot has been paid for but has not left,
## and a hand that emptied on the click would be an arm going back with nothing
## in it.
func _wants_crackle() -> bool:
	return is_elder() and not is_holding_letter() \
		and (has_lightning() or _is_throw_windup())


func _on_elder_changed(peer_id: int) -> void:
	if _bog == null or peer_id != _bog.peer_id:
		return
	_refresh_hand()
	cooldowns_changed.emit()


# -------------------------------------------------------------- the hand ---

## Put the right thing in the Bog's right hand.
##
## Every path that can change what is in it ends here — a recharge finishing, a
## respawn, a hold starting or ending — and this asks `has_spear()`, which is
## the same question the throw is gated on. That is the single source of truth
## the spear's own header insists on, now with a second reason in it: the hand
## cannot show a spear the throw would refuse, or a card while the throw is
## allowed, because there is nowhere for a second opinion to live.
##
## The windup is the one carve-out and it is not an exception to the rule: from
## the click to the release the spear is still in the fist and `has_spear()` is
## already false, because the cooldown starts on the click (D-025). The arm
## going back with an empty hand is the bug that clause prevents. It lives in
## `_wants_shaft` beside the rest of the condition rather than inline here, so
## that the poll which notices this has gone stale is asking the same question.
##
## Idempotent and cheap, which is what lets `_tick_hand` call it as often as it
## likes: every path that can change the answer ends here, and so does a frame
## on which nothing changed except that a deadline passed.
## `_refresh_hand` for callers outside this node.
##
## Exactly one exists: `BogBackdrop`, which changes `Bog.weapon` on a ring Bog
## when the lobby roster moves and then has to ask for the hand to be redrawn.
## In a match nothing needs it — `Bog.weapon` is fixed before the body is built
## and every other thing that can change a hand already ends at `_refresh_hand`
## from inside here.
##
## A one-line forwarder rather than making `_refresh_hand` public, so that the
## underscore keeps meaning what it means in this file: the hand is this node's
## business, and the one outside caller is asking rather than reaching.
##
## It re-points the **carry pose** as well since D-070, and that is not a second
## job — it is the same job one node down. `BogBackdrop` changes `Bog.weapon` on
## a ring Bog as the lobby's caret moves, and a Bog whose fists had swapped to a
## great sword while its shoulders stayed in an archer's stance is exactly the
## disagreement this forwarder exists to prevent on the other side of the
## skeleton. In a match neither half is ever called twice: the pick locks at
## Start (D-069) and `BogAnimator._ready` has already asked.
func refresh_hand() -> void:
	_refresh_hand()
	if _bog == null:
		return
	var animator := _bog.get_node_or_null("AnimationTree") as BogAnimator
	if animator != null:
		animator.set_carry_pose()


func _refresh_hand() -> void:
	if _bog == null or _bog.held_gear == null:
		return
	var holding := is_holding_letter()
	_bog.held_gear.set_carried(_wants_shaft())
	# The left fist and the right, set together and every time, which is what
	# makes "one thing per hand" a property of this one function rather than a
	# rule spread over two files (D-065). `HeldGear` decides nothing.
	_bog.held_gear.set_bow(_wants_bow())
	_bog.held_gear.set_arrow(_wants_arrow())
	# The fourth, set here with the other three and every time, which is what
	# keeps "a great sword is two-handed" a property of this one function rather
	# than a rule spread over two files (D-065, D-068): the same call that puts
	# the sword in the right fist is the call that takes the bow out of the left.
	_bog.held_gear.set_sword(_wants_sword())
	# And the **fifth**, which is the bow fist's other object (D-075). It is
	# the line that makes "a drink empties both hands" visible rather than
	# merely true: `_wants_bow()` has answered no through a channel since
	# D-067, and until this there was nothing to put in the hand it emptied.
	# Decided here with the other four and in the same breath, so a bottle
	# and a bow can no more be out together than a bow and a great sword.
	_bog.held_gear.set_potion(_wants_potion())
	# And the **sixth**, which is the bow fist's third object (the letters
	# round). Decided here with the other five and in the same breath, so a
	# pouch, a bottle and a bow can no more be out together than a bow and a
	# great sword can — and so that the one function that says what a capture
	# looks like in the hands says both halves of it: a sack in the left, and
	# the right emptied for the card the `CaptureRig` floats above it.
	_bog.held_gear.set_pouch(_wants_pouch())
	# Runs on every peer's copy of every Bog, which is the point: a Bog ten
	# seconds from a letter has to be readable from across the clearing by the
	# people who might stop it, not only by the player holding the card. The
	# Elder's crackle is the same argument with a shorter fuse.
	#
	# **A carry only, since the letters round.** There is one letters game with
	# two flavours, and the hold row is the same row in both: `ends_at = INF` is
	# a Capture B·O·G card being *run* to a vault, and a finite one is a timed
	# capture. A carry keeps the card up in the fist exactly as it has since
	# D-035 — the Bog is sprinting across a map with a prize and the fist is
	# where that reads from. A timed capture does not, because the card is the
	# thing descending into the pouch and a Bog holding two of them would be
	# two answers to one question. The condition is `_wants_pouch()`'s own,
	# negated, and it is in this function for D-065's reason: one place decides
	# what is in a hand.
	var card_in_fist := holding and not MatchState.letter_hold_is_timed(_bog.peer_id)
	_bog.held_gear.set_letter(
		MatchState.letter_hold_letter(_bog.peer_id) if card_in_fist else 0)
	_bog.held_gear.set_charged(_wants_crackle())


func _on_letter_hold_changed(peer_id: int) -> void:
	if _bog == null or peer_id != _bog.peer_id:
		return
	_refresh_hand()
	_refresh_carrier_marker()


## The card over the head says the same thing as the card in the fist, from the
## same row and on the same signal, so the two cannot disagree about who is
## holding (D-050). Every end of a hold — banked, killed, a teammate banking the
## same letter, the match ending — arrives here as the row going away.
func _refresh_carrier_marker() -> void:
	if _bog.carrier_marker == null:
		return
	var letter := MatchState.letter_hold_letter(_bog.peer_id)
	_bog.carrier_marker.set_carrying(
		MatchState.letter_name(letter) if letter != 0 else "", Pickup.LETTER_COLOUR)


func _on_spear_struck_bog(victim: Bog, point: Vector3, bone: String,
		spear: SpearProjectile) -> void:
	# Only the host's copy of a spear is allowed to decide anything.
	if not spear.authoritative or not Net.is_host:
		return
	# The full velocity, not a direction: its magnitude is what makes the corpse
	# fly rather than sag, and a spear that has dropped out of a long arc should
	# shove one much less than a flat throw from close range.
	#
	# `SPEAR_DAMAGE` and not a kill: a spear is one shot because of what the
	# number is, not because this line says "die" (D-062).
	MatchState.report_damage(victim.peer_id, _bog.peer_id, SPEAR_DAMAGE,
		Bog.Cause.SPEAR, point, spear.impact_velocity(), bone)


# --------------------------------------------------------------- inventory ---

## Host only. Called by `MatchState.claim_pickup` when this Bog walks over a
## drop, and by the testbeds, which are the only other thing in the build that
## can put an item in a hand (see the note in `tools/combat_range.gd`).
##
## The host counts and the host says so. A client cannot reach this: the whole
## point of `Combat` belonging to peer 1 on every machine (D-024) is that the
## `_do_*` broadcast below is refused unless it came from the host.
func grant_shield(count: int = 1) -> void:
	if not Net.is_host or count <= 0:
		return
	_server_shields += count
	_broadcast_inventory()


func grant_magnet(count: int = 1) -> void:
	if not Net.is_host or count <= 0:
		return
	_server_magnets += count
	_broadcast_inventory()


func grant_potion(count: int = 1) -> void:
	if not Net.is_host or count <= 0:
		return
	_server_potions += count
	_broadcast_inventory()


func _broadcast_inventory() -> void:
	_do_set_inventory.rpc(_server_shields, _server_magnets, _server_potions)
	_do_set_inventory(_server_shields, _server_magnets, _server_potions)


## The host's word on what this Bog is holding, on every peer. Also what
## corrects a predictive decrement that the host refused — a client that spent a
## shield it did not have gets its count put back here rather than being left
## one short for the rest of its life.
@rpc("authority", "call_remote", "reliable")
func _do_set_inventory(shields: int, magnets: int, potions: int) -> void:
	if _shields == shields and _magnets == magnets and _potions == potions:
		return
	_shields = shields
	_magnets = magnets
	_potions = potions
	inventory_changed.emit()


# ---------------------------------------------------------------- shield ---

## Spend one shield, if there is one to spend.
##
## The *direction* travels with the request, which is new and is the whole
## reason this signature changed. A shield now goes where the camera is
## looking rather than where the body happens to be pointed, and the camera is
## the one thing about a Bog the host does not have: `BogCamera` shuts itself
## down on every copy but the owner's, so the host's copy of a remote Bog's rig
## has never moved. Asking it would plant every client's shield due north.
##
## So the client sends the look, exactly as `_request_throw_spear` sends the aim,
## and the host still runs both validation rays on it. What a modified client can
## do with this is choose a direction — which it could already do by turning —
## and no more: it cannot plant through a wall, over a cliff, or further than
## SHIELD_DISTANCE away.
func try_place_shield() -> void:
	if _shields <= 0 or shield_use_cooldown() > 0.0:
		return
	var look := _look_direction()
	_shield_ready_at = _now() + _config.shield_use_delay
	# Spent on the click. If the host refuses it, `_do_set_inventory` puts it
	# back; leaving the count up until the round trip lands is what lets a held
	# key spend the same shield twice.
	_shields -= 1
	inventory_changed.emit()
	cooldowns_changed.emit()
	if Net.is_host:
		_host_place_shield(look)
	else:
		_request_shield.rpc_id(1, look)


@rpc("any_peer", "call_remote", "reliable")
func _request_shield(look: Vector3) -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _bog.peer_id:
		return
	_host_place_shield(look)


func _host_place_shield(look: Vector3) -> void:
	if not _bog.alive:
		return
	if _server_shields <= 0 or _now() < _server_shield_ready_at:
		# The asker has already decremented its own count, so tell it what the
		# truth is. Without this a refused placement is a shield that quietly
		# disappears out of the stack and never comes back.
		_broadcast_inventory()
		return
	# Flattened and normalised here rather than trusted: a client is free to
	# send a zero, a NaN, or a vector pointing at the sky.
	var flat := Vector3(look.x, 0.0, look.z)
	if flat.length_squared() < 0.0001:
		flat = _bog.facing()
	flat = flat.normalized()

	var spot := _shield_spot(flat)
	if spot == Vector3.INF:
		# Nowhere to put it — a wall, or a ledge. Refused, and refunded: the
		# alternative is losing a shield to a cliff edge you could not see.
		_broadcast_inventory()
		return
	_server_shields -= 1
	_server_shield_ready_at = _now() + _config.shield_use_delay
	# The camera's yaw, not the body's, so the boards face the way you were
	# looking. Planting one while strafing used to turn it side-on to you, and
	# a wall turned side-on is not cover at all — see `Shield.plant`, which
	# takes this yaw exactly and adds nothing random to it.
	var yaw := Bog.yaw_towards(flat)
	_do_place_shield.rpc(spot, yaw, _server_shields)
	_do_place_shield(spot, yaw, _server_shields)


## Find the ground just in front of the Bog, along `forward`. Returns
## `Vector3.INF` when there is nowhere sensible — at a cliff edge, or with a wall
## in the way — so that a shield is never planted in mid-air over the void.
##
## Both rays are unchanged from when this placed along the body's facing. They
## are what keeps a shield off a ledge and out of a wall, they never depended
## on which direction was handed in, and they are the half of this the host is
## really here for.
func _shield_spot(forward: Vector3) -> Vector3:
	var space := _bog.get_world_3d().direct_space_state
	var ahead := _bog.global_position + forward * SHIELD_DISTANCE \
		+ Vector3.UP * 0.9

	var blocked := PhysicsRayQueryParameters3D.create(
		_bog.global_position + Vector3.UP * 0.9, ahead)
	blocked.collision_mask = LAYER_WORLD | LAYER_DEPLOYABLE
	blocked.exclude = [_bog.get_rid()]
	if not space.intersect_ray(blocked).is_empty():
		return Vector3.INF

	var down := PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3.DOWN * 3.5)
	down.collision_mask = LAYER_WORLD
	var ground := space.intersect_ray(down)
	if ground.is_empty():
		return Vector3.INF
	return ground["position"]


@rpc("authority", "call_remote", "reliable")
func _do_place_shield(spot: Vector3, yaw: float, remaining: int) -> void:
	_shield_ready_at = _now() + _config.shield_use_delay
	cooldowns_changed.emit()
	# The host's remainder, which is what makes the predictive decrement above
	# safe: whatever the client guessed, this is the number.
	if _shields != remaining:
		_shields = remaining
		inventory_changed.emit()

	_prune_shields()
	# Planting past the cap retires your oldest, rather than refusing — a
	# refused ability with a spent cooldown is the most annoying outcome.
	while _active_shields.size() >= _config.shield_max_active:
		var oldest: Node = _active_shields.pop_front()
		if is_instance_valid(oldest):
			oldest.call("wither")

	var shield := SHIELD.instantiate()
	_spawn_root().add_child(shield)
	shield.call("plant", spot, yaw, _config.shield_lifetime, _bog.peer_id)
	_active_shields.append(shield)


func _prune_shields() -> void:
	_active_shields = _active_shields.filter(func(m): return is_instance_valid(m))


# -------------------------------------------------------------------- magnet ---

## The magnet is thrown at a *point*, not along a direction, because it is slow
## enough for gravity to matter: fired flat at the crosshair it dropped after
## about five metres regardless of where you were aiming, which made it
## impossible to place. The host solves the arc that actually lands on the aim
## point — see `_lob_velocity`.
func try_throw_magnet() -> void:
	if _magnets <= 0 or magnet_use_cooldown() > 0.0:
		return
	var origin := _throw_origin()
	var target := _aim_point()
	_magnet_ready_at = _now() + _config.magnet_use_delay
	_magnets -= 1
	inventory_changed.emit()
	cooldowns_changed.emit()
	if Net.is_host:
		_host_throw_magnet(origin, target)
	else:
		_request_magnet.rpc_id(1, origin, target)


@rpc("any_peer", "call_remote", "reliable")
func _request_magnet(origin: Vector3, target: Vector3) -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _bog.peer_id:
		return
	_host_throw_magnet(origin, target)


func _host_throw_magnet(origin: Vector3, target: Vector3) -> void:
	if not _bog.alive:
		return
	if _server_magnets <= 0 or _now() < _server_magnet_ready_at:
		# Same as the shield: a refusal has to put the asker's count back.
		_broadcast_inventory()
		return
	if origin.distance_to(_bog.global_position) > 3.0:
		origin = _throw_origin()
	_server_magnets -= 1
	_server_magnet_ready_at = _now() + _config.magnet_use_delay
	# The client chooses a point; the host chooses the velocity. Sending a
	# velocity over the wire instead would let a modified client fling a magnet at
	# any speed it liked.
	var velocity := _lob_velocity(origin, target)
	_do_throw_magnet.rpc(origin, velocity, _server_magnets)
	_do_throw_magnet(origin, velocity, _server_magnets)


## Launch velocity that carries a projectile of speed `MAGNET_SPEED` from `from`
## to `to` under `MAGNET_GRAVITY`.
##
## Of the two arcs that hit any reachable point, this picks the flatter one: it
## arrives sooner and reads as a thrown object rather than a mortar shell. If
## the point is out of range there is no solution at all, and the throw falls
## back to 45 degrees — the angle that goes furthest — aimed the right way, so
## an over-ambitious throw still travels as far as it possibly can instead of
## dropping at the thrower's feet.
func _lob_velocity(from: Vector3, to: Vector3) -> Vector3:
	var delta := to - from
	var flat := Vector3(delta.x, 0.0, delta.z)
	var distance := flat.length()
	if distance < 0.05:
		return Vector3.UP * MAGNET_SPEED
	var forward := flat / distance

	var speed_sq := MAGNET_SPEED * MAGNET_SPEED
	# Solving `y = x·tanθ − g·x² / (2·s²·cos²θ)` for θ gives this discriminant;
	# negative means no launch angle at this speed reaches the point.
	var discriminant := speed_sq * speed_sq - MAGNET_GRAVITY * (
		MAGNET_GRAVITY * distance * distance + 2.0 * delta.y * speed_sq)
	if discriminant < 0.0:
		return (forward + Vector3.UP).normalized() * MAGNET_SPEED

	var angle := atan2(speed_sq - sqrt(discriminant), MAGNET_GRAVITY * distance)
	return (forward * cos(angle) + Vector3.UP * sin(angle)) * MAGNET_SPEED


@rpc("authority", "call_remote", "reliable")
func _do_throw_magnet(origin: Vector3, velocity: Vector3, remaining: int) -> void:
	_magnet_ready_at = _now() + _config.magnet_use_delay
	cooldowns_changed.emit()
	if _magnets != remaining:
		_magnets = remaining
		inventory_changed.emit()

	var animator := _bog.get_node_or_null("AnimationTree") as BogAnimator
	if animator != null:
		animator.play_throw()

	var magnet := MAGNET.instantiate()
	_spawn_root().add_child(magnet)
	AudioDirector.play_3d_varied(AudioDirector.MAGNET_THROW, origin)
	magnet.call("launch_from", origin, velocity, _bog.peer_id, _config)


# ------------------------------------------------------------------ potion ---

## How often health actually travels during a channel, in seconds.
##
## The heal is **continuous** — what you are owed at any instant is
## `heal_amount` times how far through the drink you are — and this is only how
## often that number is *sent*. Every frame would be 120 reliable RPCs per
## two-second drink for a bar that moves 0.67 of a point at a time; a fifth of a
## second is ten, each worth four health at the defaults, which is a bar that
## climbs visibly and a wire that does not notice.
##
## It is not a quantum of healing. A channel that ends between two slices pays
## out the difference on its way out (`_deliver_channel`), so what an
## interruption keeps is the fraction of the drink that had actually happened
## and not the last slice that happened to have been posted.
const CHANNEL_HEAL_TICK := 0.2


## Host only. A potion was walked onto: drink it where it lies.
##
## Returns whether a channel actually started, and the answer is the pickup's:
## `MatchState.claim_pickup` consumes the drop when this says true and **leaves
## it standing on the ground** when it says false, which is the letter card's
## rule one item over (D-035) and the reason the refusal has to travel back out
## of here rather than being swallowed.
##
## **The stock is deliberately not touched.** A potion off the ground is granted
## and spent in the same breath, so the count it would go through is the count it
## comes back to, and writing both halves out would only be a frame in which the
## HUD could have shown a bottle nobody is carrying. `_do_drink_potion` still
## carries `_server_potions` so a peer that had drifted is corrected by the same
## message that starts its arm.
##
## **No local prediction, unlike every other spend in this file.** There is no
## keypress to predict from: the host rules on the overlap and the drinker hears
## about its own drink from the same broadcast every other peer does. That costs
## the collector half a round trip of arm, and buys the thing a keypress could
## not — that no client can start a channel at all, which is what makes the
## refusals above rules rather than requests.
func host_auto_drink() -> bool:
	if not Net.is_host or _bog == null or not _bog.alive:
		return false
	if _server_channel_at > 0.0 or not can_drink_now():
		return false
	_server_channel_at = _now()
	_server_channel_seconds = maxf(_config.heal_channel, 0.01)
	_server_channel_healed = 0.0
	_do_drink_potion.rpc(_server_potions)
	_do_drink_potion(_server_potions)
	return true


## Spend one potion out of stock, if there is one and this is a moment for it.
##
## Nothing in a match reaches this any more — a match's potions are drunk off
## the ground by `host_auto_drink` above. What still does is the practice
## range's `RefillStone` stock and the harnesses, which is why the stock path is
## kept rather than deleted: it is the one way a potion that was *handed* to a
## Bog is spent.
##
## Host-decided like the pickup, and for the pickup's reason: with no keypress
## there is nothing to predict, so a non-host caller simply asks and waits.
func try_drink_potion() -> void:
	if not has_potion():
		return
	if Net.is_host:
		_host_drink_potion()
	else:
		_request_drink_potion.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_drink_potion() -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _bog.peer_id:
		return
	_host_drink_potion()


## The authoritative half. Every clause `can_drink_now` names, on the host's own
## copy of the state, plus the one only the host can check — that this Bog is
## not already drinking, which is what stops a modified client spamming the
## request into a continuous heal.
func _host_drink_potion() -> void:
	if not _bog.alive:
		return
	if _server_potions <= 0 or _server_channel_at > 0.0 or not can_drink_now():
		return
	_server_potions -= 1
	_server_channel_at = _now()
	_server_channel_seconds = maxf(_config.heal_channel, 0.01)
	_server_channel_healed = 0.0
	_do_drink_potion.rpc(_server_potions)
	_do_drink_potion(_server_potions)


## The drink, on every peer, and the **only** thing that starts an arm.
##
## It runs on the drinker too, which is the one line that changed when the key
## went away: there is no longer a local half that got there first, so skipping
## the owning client here would be the one machine that never plays the clip —
## and a drink nobody can see on their own Bog is exactly the bug this step was
## sent to fix.
@rpc("authority", "call_remote", "reliable")
func _do_drink_potion(remaining: int) -> void:
	if _potions != remaining:
		_potions = remaining
		inventory_changed.emit()
	_begin_channel()


## Stop drinking, on every peer. The host's word, and the only thing that can
## end a channel early on somebody else's screen.
@rpc("authority", "call_remote", "reliable")
func _do_stop_drink() -> void:
	_end_channel()


## The owning client telling the host it has stopped — it moved, or jumped, and
## it knew before the host's next snapshot of its velocity did.
##
## An optimisation and not the rule. The host reaches the same conclusion off
## `sync_velocity` a tick or two later on its own, which is what makes this safe
## to accept from a client at all: the only thing a modified one can do with it
## is stop its own drink early, and the potion is already spent.
@rpc("any_peer", "call_remote", "reliable")
func _request_stop_drink() -> void:
	if not Net.is_host or multiplayer.get_remote_sender_id() != _bog.peer_id:
		return
	host_break_channel()


## Host only. End whatever channel is running and pay out what it had earned.
##
## Public because two of the three things that break a drink are decided in
## `MatchState` and not here — a landed hit, and a letter card picked up
## mid-drink — and neither of them should have to know how a channel is stopped.
## The third, moving, is noticed by `_tick_channel` below.
func host_break_channel() -> void:
	if not Net.is_host or _server_channel_at <= 0.0:
		return
	_deliver_channel(_channel_progress())
	_server_channel_at = 0.0
	_stop_channel_everywhere()


func _stop_channel_everywhere() -> void:
	_do_stop_drink.rpc()
	_do_stop_drink()


## Start the arm and the clock on this machine.
func _begin_channel() -> void:
	if _bog == null:
		return
	_channel_at = _now()
	_channel_seconds = maxf(_config.heal_channel, 0.01)
	# Every peer runs this, the drinker included: with the key gone there is no
	# local half that got here first, so this is the only place an arm starts.
	_bog.drinking = true
	var animator := _bog.get_node_or_null("AnimationTree") as BogAnimator
	if animator != null:
		animator.play_drink(BogAnimator.drink_rate_for_channel(_channel_seconds))
	# Both fists, now rather than on the next frame's `_tick_hand`. D-067 put
	# `not is_channelling()` in `has_spear()` precisely so that the *hand* obeys
	# a drink, and a poll a frame behind is a frame of the bottle coming up with
	# the weapon still in the fist — which is the picture that decision was
	# written against. The same call on the way back down, in `_end_channel`.
	_refresh_hand()
	cooldowns_changed.emit()


## Put the bottle down on this machine. Idempotent — the host broadcasts a stop
## for a channel that several peers may already have run out on their own.
func _end_channel() -> void:
	if _channel_at <= 0.0:
		return
	_channel_at = 0.0
	_channel_seconds = 0.0
	if _bog != null:
		# Before the animator and before the hand: the speed penalty is the
		# thing the player feels, and a frame of it left on after the bottle
		# came down is a frame of a Bog that cannot work out why it is slow.
		_bog.drinking = false
		var animator := _bog.get_node_or_null("AnimationTree") as BogAnimator
		if animator != null:
			animator.stop_drink()
	# The other half of `_begin_channel`'s call: the weapon goes back into the
	# fist on the frame the bottle leaves the lips, not the one after it.
	_refresh_hand()
	cooldowns_changed.emit()


## Is there any reason the channel that is running should not still be?
##
## Everything here is replicated, so the host and the drinker reach the same
## answer from the same state — the property `MatchState.damage_refusal` is
## written for, and for the same reason. Being hit is not in it: that is decided
## at the one door every hit comes through and arrives as `host_break_channel`.
##
## **It is two clauses now and it used to be four**, and the two that went are
## the amendment to D-067 (see the header). *Moving* went because a drink now
## begins on the stride that walked onto the bottle, so a speed rule would
## cancel every drink in the game on its first frame; *jumping* went with it,
## because it was only ever the speed rule's blind spot — pressing jump barely
## moves a Bog horizontally — and on its own it would mean a player who hopped
## over a drop got nothing for it. What is left is the pair that are about the
## body rather than about its velocity: a dead Bog is not drinking, and a hand
## that has just closed on a letter card has nothing to hold a bottle with
## (D-035).
##
## **Airborne is deliberately absent.** The drink is a layer filtered to Spine1
## and up, so it works in the air by construction, and there is no grounded
## check anywhere in this file for this to become the first of. Crouching is
## absent for the same reason: the drink layers over it untouched.
func _channel_broken() -> bool:
	if _bog == null or not _bog.alive:
		return true
	return is_holding_letter()


## How far through the *host's* channel we are, 0 to 1.
func _channel_progress() -> float:
	if _server_channel_at <= 0.0:
		return 0.0
	return clampf((_now() - _server_channel_at) / _server_channel_seconds, 0.0, 1.0)


## Hand over however much of the potion has been earned by `progress` and not
## yet sent. Host only.
##
## `_server_channel_healed` counts what was **asked for**, not what landed: a
## Bog eight from full that drinks forty is healed eight, and the other
## thirty-two are still spent. Counting what landed instead would leave a
## potion's remainder waiting to be delivered to a Bog that is already full,
## which is a heal arriving the moment somebody hits it.
func _deliver_channel(progress: float) -> void:
	var wanted := _config.heal_amount * progress
	if wanted <= _server_channel_healed:
		return
	var slice := wanted - _server_channel_healed
	_server_channel_healed = wanted
	MatchState.report_heal(_bog.peer_id, slice)


## The channel, every frame, on every peer (D-067).
##
## Three layers, in this order and for these reasons. The **host's** clock is
## first, because it is the only one that heals anybody and this tick's slice
## has to have been paid before anything below can end the drink. Then **every**
## peer's own clock, which runs out on its own so that a drink that simply
## finished costs no packet at all. Then the **drinker's** prediction of its own
## cancel, so the arm comes down on the frame the key went down rather than a
## round trip later.
func _tick_channel() -> void:
	if Net.is_host and _server_channel_at > 0.0:
		_tick_host_channel()
	if _channel_at <= 0.0:
		return
	if _bog == null or not _bog.alive or _now() - _channel_at >= _channel_seconds:
		_end_channel()
		return
	if _bog.is_local() and _channel_broken():
		_end_channel()
		# The host is told, unless this *is* the host, whose own
		# `_tick_host_channel` above reached the same conclusion this frame.
		if not Net.is_host:
			_request_stop_drink.rpc_id(1)


func _tick_host_channel() -> void:
	var progress := _channel_progress()
	if progress >= 1.0:
		_deliver_channel(1.0)
		_server_channel_at = 0.0
		return
	if _channel_broken():
		host_break_channel()
		return
	# Between the ends, health travels on the slice boundary rather than every
	# frame — see CHANNEL_HEAL_TICK.
	var steps := floorf((_now() - _server_channel_at) / CHANNEL_HEAL_TICK)
	_deliver_channel(minf(1.0, steps * CHANNEL_HEAL_TICK / _server_channel_seconds))


## The host telling this Bog's own client that a magnet has caught it.
##
## The pull has to be applied by the victim's client because movement is
## client-authoritative and the host cannot simply move a body it does not own
## (D-004). `Magnet` decides *who*; this is *where the answer is delivered*, and it
## is delivered here rather than on the magnet that fired it because an RPC is
## addressed by node **path**. A magnet has no path two machines agree on: every
## peer builds its own copy into `spawned_items`, and the moment a second one is
## in the air Godot disambiguates the duplicate name with a counter local to that
## process. `Players/Bog_<peer>/Combat` is a name both ends already have, and it
## is owned by the host, which is what makes "authority" the right mode for it.
@rpc("authority", "call_remote", "reliable")
func apply_magnet_pull(centre: Vector3, strength: float, duration: float) -> void:
	if _bog != null:
		_bog.apply_magnet(centre, strength, duration)


# ------------------------------------------------------------------- shared ---

## Everything a Bog spawns goes into one container so the arena can clear the
## lot between rounds without hunting through the scene tree.
func _spawn_root() -> Node:
	var root := get_tree().get_first_node_in_group("spawned_items")
	return root if root != null else get_tree().current_scene


## Called when a round restarts: wipe cooldowns so nobody starts a round unarmed,
## and wipe the carried stock so nobody starts one armed with anything else. A
## throw that was still winding up when the round ended is dropped with them —
## respawning with a spear already half thrown is nobody's idea of a fresh start.
##
## **Everything you were carrying is lost on death** (D-032). Letters are not —
## those live on `MatchState.stats` and are permanent progress for the match —
## but shields, magnets and potions go back to zero, which is what makes a life worth
## keeping once you have gathered a few and what stops the leader compounding.
##
## Runs on every peer, from `MatchState._do_respawn`, so the host's copies are
## zeroed by the same call that zeroes everyone's. No broadcast needed, and
## sending one would race the respawn that caused it.
## Put down whatever the old weapon was half way through doing. Runs on every
## peer, from `MatchState._do_set_weapon` when a range rack changes `Bog.weapon`
## under a Bog that is still standing (D-115).
##
## **`reset()`'s weapon half, and deliberately not `reset()` itself.** That
## function also zeroes `_shields`, `_magnets` and `_potions`, because it is the
## death path and everything carried is lost on death (D-032). A rack is not a
## death: a Bog that walked past one and found its pockets emptied would have
## been punished for practising, which is the opposite of what the rack is for.
## So this is the same list with the stock, the Elder's clock and the two
## ability cooldowns left alone — those belong to the Bog, not to the weapon it
## happens to be holding.
##
## It does **not** redraw the hand. The one caller asks `refresh_hand()` on the
## next line, which repaints both fists *and* re-points the carry pose; doing
## half of it here would be the second opinion about what is in a fist that
## `_refresh_hand`'s header refuses to have.
func clear_weapon_state() -> void:
	# The spear, with the windup that may have been half way back. The shaft
	# itself is put back by the `refresh_hand` that follows, off `has_spear()`.
	_windup_release_at = 0.0
	_spear_ready_at = 0.0
	_server_spear_ready_at = 0.0
	# The bow, with the draw. `_bog.draw` is cleared out of band for the reason
	# `reset` gives one screen down: this runs on every peer, and a remote Bog
	# whose owner has not published since would otherwise hold a half-drawn bow
	# it no longer has.
	_bow_ready_at = 0.0
	_draw_started_at = 0.0
	_loose_charge = -1.0
	_server_bow_ready_at = 0.0
	_server_draw_peak = 0.0
	_server_drawing = false
	# The sword, with the swing. `Bog.is_spinning()` runs itself out, so the
	# flag is all there is to clear here — and the chain's two clocks run
	# themselves out beside it, so the chain is its index and its deadlines.
	_swinging = false
	_sword_ready_at = 0.0
	_server_sword_ready_at = 0.0
	_slash_index = 0
	_server_slash_index = 0
	_server_slash_until = 0.0
	# And the fists, which are the one thing here that survives a weapon
	# changing under a Bog: a rack does not put your hands away.
	_punching = false
	_punch_ready_at = 0.0
	_server_punch_ready_at = 0.0
	if _bog != null:
		_bog.draw = -1.0
	cooldowns_changed.emit()


func reset() -> void:
	_windup_release_at = 0.0
	_spear_ready_at = 0.0
	# Zeroed with the rest, and it costs nothing: a respawning Bog is never the
	# Elder. The reason changed under this line with D-040 and the conclusion did
	# not — it used to be that dying took the robe away, and now it is that the
	# only death an Elder can have is the void, which ends the robe on the way
	# down. A stale deadline here would only matter on the day *that* stops being
	# true, which is exactly when nobody would think to look.
	_lightning_ready_at = 0.0
	# The bow, with the draw that may have been half way back when the round
	# ended. `_bog.draw` is put back out of band here as well as in
	# `Bog.revive_at`, because `reset` runs on every peer from `_do_respawn` and
	# a remote Bog whose owner has not published yet would otherwise hold a
	# half-drawn bow for a round trip.
	_bow_ready_at = 0.0
	_draw_started_at = 0.0
	_loose_charge = -1.0
	# The sword, with the swing that may have been half way round when the round
	# ended. `Bog.revive_at` ends the spin itself, on every peer and for the same
	# reason it puts `draw` back out of band there — so this is only the flag and
	# the two deadlines, and the fists are emptied by the `_refresh_hand` at the
	# bottom of this function like everything else.
	_swinging = false
	_sword_ready_at = 0.0
	_server_sword_ready_at = 0.0
	# The chain and the fists go with them, and `Bog.revive_at` ends both of the
	# chain's clocks on every peer for the reason it ends the spin's — a Bog
	# that came back mid-chain would stand on a spawn pad at 0.85 speed with a
	# blade in its fists (the feel round).
	_slash_index = 0
	_server_slash_index = 0
	_server_slash_until = 0.0
	_punching = false
	_punch_ready_at = 0.0
	_server_punch_ready_at = 0.0
	_server_bow_ready_at = 0.0
	_server_draw_peak = 0.0
	_server_drawing = false
	if _bog != null:
		_bog.draw = -1.0
	_shield_ready_at = 0.0
	_magnet_ready_at = 0.0
	_server_spear_ready_at = 0.0
	_server_lightning_ready_at = 0.0
	_server_shield_ready_at = 0.0
	_server_magnet_ready_at = 0.0
	_shields = 0
	_magnets = 0
	_server_shields = 0
	_server_magnets = 0
	# The potion goes back to zero with the other two: it is carried stock, so
	# it is lost on death like everything else that is (D-032, D-067). The
	# channel goes with it, on every peer, because `reset` runs everywhere from
	# `_do_respawn` — a Bog coming back onto a spawn pad still holding a bottle
	# up would be the clearest possible way to show that a clock survived a
	# death it should not have.
	_potions = 0
	_server_potions = 0
	_end_channel()
	_server_channel_at = 0.0
	_server_channel_seconds = 0.0
	_server_channel_healed = 0.0
	_prune_shields()
	# Through `_refresh_hand` rather than straight at the spear, so a respawn
	# cannot hand back a shaft to a Bog the host still has a letter hold open
	# for. In practice a death ends the hold first (D-035) — but a respawn that
	# quietly disagreed with the gate would be the hardest kind of bug to see,
	# because everything about it looks right except that the throw does
	# nothing.
	_refresh_hand()
	cooldowns_changed.emit()
	inventory_changed.emit()
