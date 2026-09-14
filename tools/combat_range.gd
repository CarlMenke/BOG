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
##   release  — the one thing about the spear that is a *timing* and not a
##              picture, measured rather than asserted (D-025, D-063). One
##              throw, over the back wall like `recharge`'s, and three numbers
##              off it: how long after the click the shaft actually appears in
##              the world, whether the fist was already empty at the instant it
##              did, and how far that instant is from the frame the throwing
##              hand is furthest in front of the hips — which is the frame the
##              release was cut from and the only independent witness to it. A
##              window or a rate that moves without `THROW_RELEASE_TIME` moving
##              with it fails the third of those even when the first two still
##              agree with each other, which is exactly the bug D-025 exists
##              because of and D-040 repeated.
##   cast     — `release`'s question asked of the Elder, which is a different
##              question about the same one tick (D-064). One bolt, and three
##              numbers off it: how long after the click it actually appears,
##              whether the arm had got there when it did, and whether the hand
##              is still going forward at that instant. The third is the one
##              worth having, because `Cast` is a clip whose hand stops half a
##              second before it is furthest in front of the hips — so
##              `release`'s own rule, asked here, would pass on a bolt fired
##              during the recovery.
##   bow      — the whole of the bow, in numbers (D-065). **Two shots and a
##              refusal**, and the two shots are deliberately the two ends of
##              the charge rather than a sample of it: a snap shot let go on the
##              frame after the key went down, and a full draw held past
##              `bow_draw_time`. Each one is measured three ways — what the
##              victim actually lost, and the launch speed and the drop *fitted
##              off the arrow's own positions* rather than read out of the
##              object — and each is checked against `ArrowProjectile`'s own
##              statics at the charge the arrow says it left at. The third
##              verdict is a letter hold refusing the draw: a Gub with a card up
##              cannot start one, the bow is out of its hand while it holds, and
##              both come back when the hold does (D-035).
##
##              What this cannot show is the pose. `draw` is that.
##   draw     — the charge as a **tell**, which is the half of this weapon that
##              is not a number (D-065). The local Gub is drawn to a series of
##              charge levels and a *remote* one is handed the same charges over
##              `Gub.sync_draw`, and the two skeletons have to agree: the
##              drawing hand in the same place relative to the hips, to a
##              centimetre, on a Gub nobody is driving. Then the control that
##              makes that mean anything — the pose at full draw has to be a
##              long way from the pose at brace, or "they agree" is satisfied by
##              two Gubs standing still.
##
##              It also prints where the composed bow is actually pointing, in
##              degrees off the Gub's own facing, which is the one thing a
##              masked layer can silently get wrong (D-029, D-064).
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
##              (D-041). It is the only mode here that reaches past a public API
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
##   blast    — the bolt's blast radius (D-053), measured rather than looked at.
##              The player is made the Elder and fires three bolts straight
##              through `GubCombat._host_cast_lightning` with an exact origin and
##              aim, so where they land is a number and not a camera's opinion:
##              one into the ground between a dummy whose body is
##              `lightning_radius - 0.2` m from the impact and one that is
##              `+ 0.2` m from it (the first must die, the second must not); one
##              into the ground in front of a thin wall with the survivor behind
##              it, inside the radius through the wall (must not die); and one
##              straight into the chest of a second Elder (must not die, D-040).
##              Distances are re-measured at the moment of each cast and printed,
##              so a dummy that drifted is a FAIL and not a lucky PASS. Also
##              round-trips `lightning_radius` through `MatchConfig`. The ring is
##              photographed three ticks after the first bolt:
##              `snapshot.gd -- res://tools/combat_range.tscn out/blast.png 43 blast`
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
##   respawn  — both halves of "everything you carried is lost on death"
##              (D-032, D-038) at the moment a player found them failing: the
##              player dies holding a mushroom, a dummy dies as the Elder holding
##              one too, both corpses are left lying in loot, and both come back.
##              A second after the respawn nobody may be holding anything,
##              wearing anything, or have picked up what they died on.
##
##              The dummy is the half that matters. It is a *remote* Gub, and the
##              bug was a remote Gub's: its owner's client is still dead when the
##              host revives it, and goes on publishing the corpse's position
##              until the respawn reaches it — so for a round trip the host's copy
##              was told to stand on its own loot, alive. No client exists here,
##              so the mode *is* that client, and replays the dead one's last
##              snapshot for `RESPAWN_STALE_TICKS` after the revive (D-043).
##   walk     — holds W for a second and requires the Gub to have gone somewhere.
##              Trivial-looking, and it is here because movement was wired up in
##              this file and in the sandbox and nowhere else, so every testbed
##              could be walked around while the actual game could not.
##   bhop     — runs the local Gub down the range three times, as itself, as the
##              Elder and as a capture carrier, and times its hops (D-052). Each
##              run: sprint, one jump, ten hops pressed on the first ground tick,
##              one hop pressed late, and a dive re-jumped out of its roll. Hop
##              speed has to climb past 1.15x run and stop at the 1.3x cap; the
##              run, the single jump, the late hop and the dive hop may not be
##              faster than run. Prints each run's numbers. Headless, run it with
##              `--fixed-fps 60` so it is not three runs of real time.
##   leave    — tears the session down out from under a live Gub and keeps
##              ticking, which is what leaving a match actually does: `Net`
##              nulls the multiplayer peer and `SceneFlow` then fades for 0.22 s
##              before the arena is freed, so every Gub in the tree spends those
##              frames still being processed with no peer to ask.
##   health   — the damage model end to end (D-062), in numbers rather than in
##              pictures, because health is the one thing in this game that has
##              never been visible on a still frame. Five verdicts out of one
##              run: a hit that takes 35 leaves a Gub standing on 65 and a
##              second hit takes it to 25 (`partial`); a third kills it
##              normally, with a corpse and the kill everyone else hears
##              (`lethal`); the robe rolled off that death makes an Elder, and
##              a hit on one takes **nothing** and still flashes the ward
##              (`elder`); the first dummy comes back on full health
##              (`respawn`); and a real spear thrown at that full-health Gub
##              kills it in one (`spear`). The last is the control in D-039's
##              sense and the one the whole plan turns on — a damage model that
##              quietly made the spear a two-shot would pass every other line
##              here.
##   embed    — a shaft standing in a Gub who is **still alive**, which is what
##              the bow needs and what nothing could do before D-062. A spear
##              is launched by hand, with nothing listening for its hit, so it
##              lands on a dummy that takes no damage at all: it has to stick,
##              stay visible, and *ride* — the dummy is then moved two metres
##              and the shaft has to arrive with it, which is the only way to
##              tell a spear stuck in a body from a spear stuck in the air
##              where the body was (`embed`). The dummy is then killed and the
##              same shaft has to be adopted by the corpse and be hanging off a
##              physical bone of it, with nothing left on the Gub's list
##              (`adopt`).
##   hurt     — the bars over other people's heads (D-062), which is the half of
##              the damage model a number cannot show. Two dummies are hurt by
##              different amounts through the real door — one to 62, one to 18 —
##              and then nothing happens, on purpose: the picture is of two
##              plates, one amber and one red, at the distance a fight actually
##              happens at. `hud_range hud_health` is the same question for your
##              own bar. Nothing is asserted here; `health` does the asserting.
##   strafe   — the feet, in eight directions (D-066). The Gub is held facing
##              one way, as it is while aiming, and driven round the compass at
##              walking and at running speed; every tick the *slower* of its two
##              toes is measured in world space, which is the planted one, and
##              how fast that foot is sliding is the whole of the fault this
##              step exists to remove. Printed as a fraction of the Gub's own
##              ground speed, so 0.0 is a foot nailed down and 2.0 is a foot
##              going backwards as fast as the body is going forwards.
##              `standing PASS` is the sixteen legs of the new plane; `crouch`
##              is the control, and it is a control that is *meant* to be bad —
##              a crouching Gub still has one clip and a one-dimensional space
##              behind it, so its sideways legs have to come out visibly worse
##              than its forward one or this measurement cannot see the thing
##              it is here to see.
##   spine    — the torso, swept (D-066). A full draw is held while the view is
##              taken all the way round the horizon and all the way from
##              `PITCH_MIN` to `PITCH_MAX`, and three things are asked at every
##              step: the composed bow has to be pointing where the crosshair
##              points (`bow`, against the 91° D-065 left behind), the bow has
##              to be *tipped* to the crosshair's own pitch (`pitch`), and then
##              two arrows fired from the same spot at the two ends of the pitch
##              range have to leave from **the same point in space** while going
##              two different ways (`release`). That last is D-025 and D-045
##              asserted rather than assumed: a modifier that moved the release
##              would be a spine that moved a shot.
##   strafing — the picture `strafe` measures. Eight Gubs in a row facing the
##              camera, each running a different bearing at RUN_SPEED, posed
##              entirely out of the `sync_*` fields a real client would have
##              sent. Nothing is asserted; the eye does it.
##   aiming   — the picture `spine` measures. Five Gubs side-on at a full draw,
##              at five pitches from `PITCH_MIN` to `PITCH_MAX`, posed the same
##              way — two replicated floats apiece and nothing else.
##   potion   — the heal potion, end to end (D-067). Six verdicts out of one run,
##              and the order is the usual one of each being the control for the
##              last. `drop` is a real death rolling a real potion and a dummy
##              walking onto it through its own `Area3D`; `channel` is the
##              health arriving **over** the two seconds and not at either end
##              of them — none on the frame of the click, some half way, all of
##              it at the finish; `interrupt` is the recorded rule, a hit
##              through `report_damage` half way in, with the potion spent and
##              the half that had arrived kept; `moved` is the other rule and
##              its edge case, a Gub that runs losing the drink and a Gub
##              *lured* at the same speed keeping it; `death` is D-032, two
##              potions going into the ground; and `config` is the three lobby
##              dials through `to_dict`/`apply_dict` and the clamps.
##   free     — no script; play it yourself
const MODES := ["flight", "hit", "arc", "miss", "aim", "mushroom", "cover",
	"lure", "lure_self", "letter", "cards", "lightning", "blast", "ward", "recharge",
	"release", "cast", "bow", "draw", "strafe", "spine", "strafing", "aiming",
	"respawn", "health", "potion", "embed", "hurt", "walk", "bhop", "leave", "free"]

## How long after the cast the verdict is taken, in physics ticks. The click
## only starts the windup — the bolt leaves at `MatchConfig.lightning_delay`,
## 0.2 s since D-040, which is 12 ticks — and the hitscan resolves on that same
## tick, since there is no projectile to fly.
##
## Left at fifty rather than retuned down with the delay. It was the spear's
## whole windup plus a margin and is now most of it margin, and a verdict taken *late*
## costs a headless run half a second; one taken early cannot tell "the bolt did
## nothing" from "the bolt has not gone yet", which is the only way this mode can
## lie. If the dial is ever raised past 0.8 s this number has to move with it.
const LIGHTNING_VERDICT_DELAY := 50

## `blast`'s geometry. How far either side of the radius the two ground dummies
## stand, measured to the surface of their capsules; the frames the three bolts
## are fired on; and how long after each the verdict is read. The bolts go
## straight through the host's cast with no windup, so the kill lands on the
## cast's own tick and twenty is all margin.
const BLAST_MARGIN := 0.2
const BLAST_CASTS: Array[int] = [40, 70, 100]
const BLAST_VERDICT_DELAY := 20
## Where the first bolt lands, on open ground six metres ahead of the player.
const BLAST_GROUND := Vector3(0.0, 0.0, 3.0)
## Where the second lands: open ground just in front of `BLAST_WALL`, on the
## player's side of it.
const BLAST_BY_WALL := Vector3(5.0, 0.0, 3.0)
## A thin wall 0.35 m behind that impact — thin enough that a body behind it is
## still well inside the radius in a straight line, which is the case line of
## sight exists for. Centre and size.
const BLAST_WALL := Vector3(5.0, 1.1, 2.55)
const BLAST_WALL_SIZE := Vector3(3.0, 2.2, 0.2)
## Where the Elder the third bolt is fired into stands.
const BLAST_ELDER_SPOT := Vector3(-4.0, 0.1, -1.0)

## How long after the click a spear's verdict is taken, in physics ticks. Same
## arithmetic as the bolt's above and one more term: the click starts the
## windup, the shaft leaves `GubAnimator.THROW_RELEASE_TIME` (0.50 s since
## D-063, 30 ticks) later, and then it has fourteen metres to cross at 42 m/s —
## twenty ticks. Ninety-five is that plus a margin, and it is left where it was
## when the release was 0.71 s rather than retuned down with it, for the reason
## `LIGHTNING_VERDICT_DELAY` above is: the margin matters more here than it
## looks, because the whole point of `cover` is a throw that is *supposed* to
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
## the 0.15 s recharge this mode sets, a cycle is the 0.50 s windup plus that —
## 39 ticks — so twelve of them is about 470 ticks, which is what the smoke
## gate's warmup count is sized for. It was 630 while the windup was 0.71 s.
const RECHARGE_CYCLES := 12

## `release`'s patience and its settle, in physics ticks.
##
## The first is how long after the click a shaft that never appears is given
## before the mode gives up and says so — three times `THROW_RELEASE_TIME` at
## the rate this clip is played at, so a release that has merely drifted is
## still measured and reported as a number rather than reported as "no spear".
## The second is how long the hand is tracked past the shaft, and it is there
## because the third verdict is about a *maximum*: the hand has to be seen
## coming back before the frame it was furthest forward on is known. It reaches
## 0.718 m at the release and is 0.11 m back a tenth of a second later
## (`tools/hand_track.gd`), so twelve ticks is comfortably past the turn.
const RELEASE_PATIENCE := 90
const RELEASE_SETTLE := 12

## How far apart the shaft and the arm may be, in physics ticks, before the two
## are called disagreeing. Measured at two, every run; three is one tick of
## headroom over that and nothing more.
##
## Three sounds loose and is not slack: none of it is tolerance for the timing,
## which is asserted separately and to a frame and a half. It is the sum of two
## known offsets, both of them in the measuring rather than in the throw.
##
## *The pose read here is a frame old.* The release fires from
## `GubCombat._tick_windup` in `_process`; the arm is sampled in
## `_physics_process`, which runs before it, off a skeleton the AnimationTree
## last wrote during the previous frame.
##
## *The arm the player sees is not the arm in the clip.* The throw is a layer
## filtered to `GubAnimator.UPPER_BODY_BONES`, so the clip's own forward pitch
## of the hips and lower spine — 19 deg of it at the release — never happens,
## and the hand's reach in front of the hips is 0.51 m here against the clip's
## own 0.718 m. Dropping a moving component moves the maximum: the clip peaks at
## 1.567 s and the composed pose peaks about a frame later.
##
## What this cannot absorb is the fault it is here for. Putting the release back
## where the old clip's was, or anywhere else a plausible mistake would put it,
## is four ticks or more.
const RELEASE_AGREEMENT := 3

## `cast`'s patience, settle and agreement, in physics ticks — the same three
## numbers as `release`'s and none of them the same value, because the thing
## being watched takes a fifth of the time.
##
## The patience is three times the longest the dial can ask for (2.0 s) so that
## a bolt which has merely drifted is still measured. The settle is how long the
## arm is tracked past the bolt, and it is longer than `release`'s twelve
## because what this mode has to see is the hand *stop*: at the default delay
## the whole window is 0.44 s of real time and the hand is still creeping
## outward for a third of it.
const CAST_PATIENCE := 360
const CAST_SETTLE := 30

## How far apart the bolt and the end of the arm's advance may be, in ticks.
##
## The same three as `release`'s and measured the same way: zero or one, every
## run. Three is two ticks of headroom over that and nothing more.
##
## It can be this tight even though the thing it watches is a deceleration
## rather than a peak, because the composed arm turns over hard — 0.016 m on the
## last tick of the whip against 0.013 m back on the next. What it is for is the
## plausible mistake, which is a release put on the frame the hand is furthest
## in front of the hips: that is 0.35 s of clip later, eight ticks at the
## default delay, and fails this by a mile.
const CAST_AGREEMENT := 3

## How much the composed hand has to still be advancing, in metres per tick, for
## the advance to count as unfinished. Two millimetres a tick is 0.12 m/s, well
## under the 0.9 m/s the clip is still doing a tick before its release and well
## over the 0.06 m/s it drifts at while the point is held.
const CAST_ADVANCE_EPSILON := 0.002

## How far the hand has to have come out of the cock before a stop is allowed to
## count as the end of the whip, in metres. See `_drive_cast`.
const CAST_ADVANCE_MIN := 0.10

## Where the bow's two targets stand, and why they are not the same place.
##
## A snap shot leaves at 18 m/s and falls at 16 m/s², so over the 14 m the spear
## modes use it would be 4.85 m into the ground before it arrived — the check
## would be measuring a miss. Five metres is the distance at which an arrow
## aimed at a Gub's eye still lands on its body (0.62 m of drop over 0.28 s),
## which is the whole point being made about this weapon rather than a
## convenience: **a snap shot is a knife**. The full draw keeps the spear modes'
## own fourteen metres, drops 0.14 m getting there, and hits what it was aimed
## at.
const BOW_SNAP_SPOT := Vector3(0.0, 0.1, 4.0)
const BOW_FULL_SPOT := Vector3(0.0, 0.1, -5.0)

## How many ticks of the arrow's flight are fitted, and how much the fit is
## allowed to disagree with `ArrowProjectile`'s own arithmetic.
##
## Six samples is five velocities and four accelerations, which is plenty for a
## body under constant gravity and short enough to be over before the arrow
## reaches anything. The tolerances are small on purpose: this is a fit of an
## exactly-integrated trajectory, not a physics engine's opinion, so the only
## error in it is the half-tick offset between "the velocity over this tick" and
## "the velocity at its start". Three per cent of the speed is nearly two ticks
## of that.
const BOW_FLIGHT_SAMPLES := 6
const BOW_SPEED_TOLERANCE := 0.03
const BOW_DROP_TOLERANCE := 0.05
## How far the damage may be from `ArrowProjectile.damage_for` at the charge the
## arrow says it left at. Half a point, which is rounding and nothing else: the
## two are the same expression asked twice.
const BOW_DAMAGE_TOLERANCE := 0.5
## What counts as a snap shot and what counts as a full draw, as charges. The
## snap is let go on the frame after the key goes down, so it is one tick of
## `bow_draw_time`; the full draw is held past the end of it.
const BOW_SNAP_MAX := 0.05
const BOW_FULL_MIN := 0.99
## How long the mode waits for each arrow to land before giving up, in ticks.
const BOW_HIT_LIMIT := 90

## The charge levels `draw` checks the remote pose at, and how far apart the two
## skeletons may be at any of them, in metres.
##
## A centimetre, which is far tighter than it sounds and is the right number
## anyway: both Gubs are being scrubbed to the same clip time by the same
## function off the same float, so a disagreement is not drift, it is a
## different code path. The one thing that legitimately differs is that a remote
## Gub's blend into the draw layer is driven by the same `DRAW_BLEND_SPEED` from
## a different starting frame, which is why the mode holds each level for
## `DRAW_SETTLE` ticks before reading.
const DRAW_LEVELS: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
const DRAW_TOLERANCE := 0.01
const DRAW_SETTLE := 20
## How far the drawing hand has to travel between brace and full draw for the
## agreement above to mean anything, in metres. Without this, two Gubs standing
## perfectly still agree perfectly.
const DRAW_SPREAD_MIN := 0.20

## How long a full draw takes in the `draw` mode. See `_start_session`.
const DRAW_MODE_DRAW_TIME := 2.0
## Where the remote Gub stands: beside the local one, facing the same way, so
## the two poses can be read off one frame.
const DRAW_DUMMY_SPOT := Vector3(2.4, 0.1, 9.0)

## How long the deliberate desync waits for the hand to notice, in physics
## ticks. Half a second is forty times `HAND_SYNC_GRACE` and several times any
## plausible repaint lag: anything still empty-handed at the end of it is not
## slow, it is never coming back.
const DESYNC_PATIENCE := 30

## Where the `respawn` mode kills its two Gubs. Deliberately *off* every spawn
## pad, and further from each than `Gub._follow_network` smooths across: a Gub
## that dies on a pad is handed that pad straight back, never leaves its loot's
## catch volume and so never enters it either, and the check passes whatever the
## code does. `tools/net_loopback.gd` fell into exactly that on its first run.
const RESPAWN_PLAYER_CORPSE := Vector3(6.0, 0.1, 2.0)
const RESPAWN_DUMMY_CORPSE := Vector3(-5.0, 0.1, 1.0)
## How long the dummy's imaginary client goes on believing it is dead after the
## host has revived it, in physics ticks: 200 ms, an ordinary round trip through
## a playit tunnel. Long enough for the physics server to step the body into a
## `Pickup` area several times over; the old code needed one.
const RESPAWN_STALE_TICKS := 12
## How long after both respawns the verdict is taken: a second, the figure in
## the report, and long enough for any grant a claim would have made to have
## been broadcast and applied.
const RESPAWN_SETTLE_TICKS := 60

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
## Three seconds is long enough for the first spear's full 0.50 s windup and
## 0.33 s of flight to land inside the window with room either side, and short
## enough that the run is over in about six. It had the same room to spare when
## the windup was 0.71 s, which is why the number did not move with it (D-063).
const WARD_DURATION := 3.0

## How long the `ward` mode will wait for that to happen before calling it a
## failure, in physics ticks. Generous — three seconds is 180 — and it exists so
## that a robe which never expires ends the run with a verdict rather than
## hanging a headless check for ever.
const WARD_EXPIRY_LIMIT := 420

## The `health` mode's three hits, in the units of `Gub.MAX_HEALTH`.
##
## 35, then 40, then 25 — three different numbers summing to exactly a hundred,
## which is the point of choosing them. Equal hits would pass against a model
## that ignored the amount entirely and counted hits instead, and a first hit of
## 50 would pass against one that halved whatever it was given. Landing exactly
## on zero also pins the boundary: dead is `health <= 0`, not `health < 0`.
const HEALTH_HITS: Array[float] = [35.0, 40.0, 25.0]
## What the Elder is hit with. Enough to kill a Gub already down to 25 and not
## enough to kill a fresh one, so "the Elder took zero" cannot be confused with
## "the Elder survived because the hit was small".
const HEALTH_ELDER_HIT := 55.0
## Short enough that the mode does not spend three seconds of a headless run
## waiting for one body, long enough that the death, the corpse and the loot
## roll are all well clear of it.
const HEALTH_RESPAWN := 0.8
## How long the mode will wait for that respawn before calling it a failure, in
## physics ticks. The same argument as `WARD_EXPIRY_LIMIT`: a respawn that never
## comes has to end the run with a verdict rather than hang the gate.
const HEALTH_RESPAWN_LIMIT := 240

## `potion`'s numbers (D-067).
##
## The channel is shortened to 1.5 s from the shipped 2.0. What this mode is
## about is the *shape* of the heal and not its length — every assertion below
## is written as a fraction of `heal_channel` — and four drinks at the real
## length would put six seconds of a headless gate on a clock nothing is
## measuring.
const POTION_CHANNEL := 1.5
## How much health is taken off the player before each drink. 60 of a hundred
## leaves 40, which is exactly `heal_amount`, so a full drink lands on 80 with
## nothing clipped by the ceiling — a potion that overflowed would make "all of
## it arrived" and "some of it arrived" the same measurement.
const POTION_WOUND := 60.0
## How far into the channel the interrupting hit lands, as a fraction of it.
## Half, because both halves of the recorded rule have to be visible in the
## answer: a quarter would be hard to tell from the rounding and three quarters
## hard to tell from a completed drink.
const POTION_INTERRUPT_AT := 0.5
## What that hit is worth. Small on purpose — it is there to *interrupt*, and a
## hit big enough to matter would leave the arithmetic underneath arguing about
## damage rather than about how much of a potion survived.
const POTION_INTERRUPT_HIT := 5.0
## How far the health the interrupted drink kept may be from the fraction that
## had arrived. Two points of a forty-point potion, which is three frames of
## channel: the harness reads the fraction off the channel's own clock and the
## host pays out against the same one, so the only slack needed is the tick
## between them.
const POTION_KEPT_TOLERANCE := 2.0
## How far from a boundary a reading has to be before it counts as either side
## of it. Half a point of health.
const POTION_EPSILON := 0.5
## How long the mode lets a body settle into or out of a state, in physics
## ticks. A quarter of a second — long enough for a standing start to pass
## `GubCombat.CHANNEL_MOVE_SPEED` and short enough to be a small fraction of the
## channel it is being measured inside.
const POTION_SETTLE := 15
## Where the lure that must *not* cancel the drink is placed, relative to the
## Gub, and how long it holds. Six metres is well past `Gub.LURE_GRIP`, so the
## pull runs for the whole of it rather than parking the body at the crystal.
const POTION_LURE_FROM := Vector3(0.0, 0.0, -6.0)
const POTION_LURE_HOLD := 1.5
## How long the mode waits for a drop to be collected or a body to come back
## before calling it a failure, in physics ticks. Same argument as
## `HEALTH_RESPAWN_LIMIT`.
const POTION_PATIENCE := 240

## How far the `embed` mode teleports the dummy to prove the shaft rides it, and
## how far the shaft is allowed to be from that move when it gets there.
##
## Two metres because it is far larger than any pose change the idle animation
## can produce in one tick, so a shaft that simply sat where it was cannot pass.
## The tolerance is a fifth of a metre: the shaft is riding an *animated* bone,
## which is still breathing while the body is moved, and demanding an exact
## match would be asserting that the idle clip has no motion in it.
const EMBED_MOVE := Vector3(2.0, 0.0, 0.0)
const EMBED_TOLERANCE := 0.2
## How long the mode waits for the launched spear to cover the fourteen metres
## to the dummy, in physics ticks. The flight is 0.33 s (20 ticks) with no
## windup — the spear is put in the air by hand — so this is mostly margin.
const EMBED_FLIGHT_LIMIT := 60

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
	# Above and behind the survivor, looking back at the first impact, so the
	# ring lies open on the ground with one dummy inside it and one just past
	# its edge — the picture of the rule rather than of the bolt.
	"blast": {"eye": Vector3(3.2, 4.6, -0.4), "look": Vector3(0.0, 0.2, 3.0),
		"fov": 55.0},
	"ward": {"eye": Vector3(6.5, 2.2, -1.5), "look": Vector3(0.0, 1.2, -5.0),
		"fov": 46.0},
	# Close to the near dummy and angled to keep the far one in frame behind it,
	# because the subject is two plates at two different distances: a bar has to
	# be readable at the range a fight happens at, not at the range a screenshot
	# is composed at. The camera is above eye height looking slightly down, which
	# is where a player's camera is (D-045).
	"hurt": {"eye": Vector3(4.2, 2.6, -0.4), "look": Vector3(-2.2, 1.7, -8.0),
		"fov": 50.0},
	# High and off to one side, because a ring lying on the ground is seen
	# edge-on from the thrower's own eye and a still frame of that is a line one
	# pixel tall. Pass `pov` after the mode to look down the throw anyway — that
	# is the view the player actually gets, and it is worth checking.
	"aim": {"eye": Vector3(11.0, 8.0, 0.0), "look": Vector3(1.5, 0.2, -13.0), "fov": 55.0},
	# Side on and close, because the subject is an arm: this mode's verdict is
	# about where the throwing hand is, and a three-quarter view foreshortens
	# exactly the axis being measured. Nothing in the gate photographs it —
	# `preview_grip` is the picture of this — but a mode with no camera entry is
	# a mode nobody can look at when it fails.
	"release": {"eye": Vector3(3.4, 1.6, 9.2), "look": Vector3(0.0, 1.05, 9.0),
		"fov": 50.0},
	# The same shot for the same reason, a little further out and a little
	# higher: the subject is still an arm, but it is an arm inside a robe, and
	# the hat is half of what the cast has left to show with.
	"bow": {"eye": Vector3(4.2, 1.7, 9.6), "look": Vector3(0.0, 1.1, 9.0),
		"fov": 45.0},
	# The two rows of D-066. Far enough back and wide enough to hold eight
	# bodies, and a little above eye level on the strafing row because half of
	# what it is showing is where the feet are.
	"strafing": {"eye": Vector3(0.0, 2.6, 11.5), "look": Vector3(0.0, 0.9, 0.0),
		"fov": 64.0},
	# Dead level with the bow on the aiming row: the subject is an elevation,
	# and a camera looking down on it subtracts its own pitch from the answer.
	"aiming": {"eye": Vector3(0.0, 1.3, 11.0), "look": Vector3(0.0, 1.3, 0.0),
		"fov": 50.0},
	"draw": {"eye": Vector3(1.2, 1.5, 3.4), "look": Vector3(1.2, 1.05, 9.0),
		"fov": 55.0},
	"cast": {"eye": Vector3(3.8, 1.8, 9.4), "look": Vector3(0.0, 1.15, 9.0),
		"fov": 50.0},
	# In *front* of the drinker and off to one side, which is the one place the
	# three views above are not. A drink is a hand coming up to a face and a head
	# going back over it, and side-on the arm crosses the body and disappears
	# into a silhouette that is mostly Gub. Three quarters from the front is
	# where the bottle, the hand and the tipped head are all separately visible
	# — measured the same way, by putting the contact sheet's camera through
	# every angle and keeping the one the gesture reads at (D-067).
	"potion": {"eye": Vector3(2.3, 1.62, 6.9), "look": Vector3(0.0, 1.22, 9.0),
		"fov": 32.0},
}

## The two picture rows (D-066). Both run along +X with the camera in front of
## them; the strafing row faces the camera and the aiming row stands side-on to
## it, because the two things being looked at are a pair of legs and a torso.
const LINEUP_FIRST := Vector3(-8.75, 0.1, 0.0)
const LINEUP_STEP := 2.5
const AIM_LINEUP_FIRST := Vector3(-6.0, 0.1, 0.0)
const AIM_LINEUP_STEP := 3.0
## Five pitches, the two ends and three between. Read out of `GubCamera` rather
## than typed, so a view that is ever allowed to look further up or down takes
## this picture with it.
const AIM_LINEUP_PITCHES: Array[float] = [
	GubCamera.PITCH_MIN, -0.55, 0.0, 0.5, GubCamera.PITCH_MAX,
]

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

## `strafe`'s compass, in the Gub's own input space — `Input.get_vector`'s
## convention, so -y is forward (D-066). Eight legs, and the diagonals are
## deliberately unnormalised because `Gub._wish_direction` normalises what it is
## handed and a testbed that pre-normalised would be testing a path the keyboard
## never takes.
const STRAFE_COMPASS: Array = [
	["forward",     Vector2(0.0, -1.0)],
	["fwd-right",   Vector2(1.0, -1.0)],
	["right",       Vector2(1.0, 0.0)],
	["back-right",  Vector2(1.0, 1.0)],
	["back",        Vector2(0.0, 1.0)],
	["back-left",   Vector2(-1.0, 1.0)],
	["left",        Vector2(-1.0, 0.0)],
	["fwd-left",    Vector2(-1.0, -1.0)],
]

## The three gaits `strafe` walks the compass at. The third is the **control**:
## `crouch` still has a one-dimensional space and a single `CrouchWalk` behind
## it, so it is what every direction looked like before this step, measured by
## the same code on the same frames. Without it "the strafes are fine" would be
## a number with nothing to be fine *against*, and a measurement that could not
## fail is not a measurement (D-039).
const STRAFE_GAITS: Array = [
	["walk", false, false],
	["run", true, false],
	["crouch", false, true],
]

## How long each leg is given to reach its speed, and how long it is then
## measured for, in ticks.
##
## Thirty to settle is generous: `GROUND_ACCELERATION` is 48 m/s², so the body
## is at 5.4 m/s in seven ticks, and the rest is the animator's own blends —
## `STANCE_BLEND_SPEED` and the locomotion cross-fade — arriving. Forty to
## measure is 0.67 s, which is longer than a full cycle of every clip in the
## plane once its playback rate is applied (the slowest is `Walk` at 0.58 s),
## so every leg is averaged over at least one whole stride and no leg is
## averaged over a lucky half of one.
const STRAFE_SETTLE := 30
const STRAFE_SAMPLE := 40

## What counts as a foot on the floor, in metres above the Gub's own feet.
##
## Only used to *report* how much of each leg had a foot down; the skate itself
## is measured off the slower of the two toes whether or not either is planted,
## which is the same number without a threshold in it. The rest pose's toe joint
## sits 0.035 m up, so this is a couple of centimetres of clearance over a foot
## that is flat on the ground.
const STRAFE_PLANT_HEIGHT := 0.08

## How far a planted foot may slide, as a fraction of the Gub's own ground
## speed, averaged over a leg. Two limits, because the plane has two kinds of
## direction in it and one number over both would have to be the looser one.
##
## `STRAFE_STRAIGHT_LIMIT` covers the four bearings a clip was actually
## downloaded for — forward and backward, at both speeds. Those are the legs the
## plane *solves* rather than improves, and they measure 0.15, 0.16, 0.23 and
## 0.28 of body speed. What is left in them is not a fault of the clip: the toe
## pivots through its own roll-off, the two feet swap over mid-stride, and the
## playback rate is a ratio of two measurements. 0.40 is comfortably over that
## and nowhere near the 0.83 and 1.03 the *same two backward legs* measured
## before this step, which is what makes this line one the old build fails.
##
## `STRAFE_LIMIT` covers all sixteen, and its job is the diagonals. 1.25 sits
## between the plane's own worst (1.14, walking back-and-right, where the
## nearest clip is 43° away) and the one-dimensional space's worst (1.36,
## running sideways), so it is a line drawn *between the two builds* rather than
## a rounding of today's number. It is deliberately not tighter: the
## back-diagonal quadrant is the one place these four strafes leave a real hole,
## because they are forward-leaning diagonals themselves, and closing it is
## three downloads rather than a tolerance (D-066).
const STRAFE_STRAIGHT_LIMIT := 0.40
const STRAFE_LIMIT := 1.25

## How much worse the crouch's *worst* bearing has to be than its best, for the
## control to have shown anything.
##
## Three, and it measures 6.7: a crouching Gub is still one clip behind a line,
## so it can only match one direction and the others fall where the geometry
## puts them. (Its best bearing is forward-**left**, not forward, because
## `CrouchWalk` is authored travelling 33.8° to the left — which is its own
## small illustration of the same point.)
const STRAFE_CONTROL_SPREAD := 3.0

## `spine`'s sweep. Eight bearings round the horizon and seven pitches from
## `PITCH_MIN` to `PITCH_MAX`, each held for `SPINE_SETTLE` ticks.
##
## Twenty ticks is a third of a second, and what it is waiting for is the
## **body**, not the modifier: `Gub.TURN_SPEED` is 14 rad/s, so the widest step
## in the yaw sweep (a quarter turn) takes ten ticks to arrive and the rest is
## margin. The torso itself is there in a twelfth of a second.
const SPINE_YAWS := 8
const SPINE_PITCHES := 7
const SPINE_SETTLE := 20

## How far off the crosshair the composed bow may point, in degrees. Two
## numbers, because the sweep asks the question in two conditions.
##
## `SPINE_BOW_LIMIT` is the **bearing** — the bow's line flattened onto the
## ground, which is exactly what D-065 measured at **91°** and what `draw`
## prints every time the gate runs. It is only asked of the level half of the
## sweep, and that is not a dodge: flattening a line that is pointing 69° into
## the ground leaves 36% of it to take a bearing off, so the same centimetre of
## animation wander reads as three times the angle. The quantity is genuinely
## ill-conditioned down there, and the number that is not is the next one.
##
## `SPINE_APART_LIMIT` is the honest three-dimensional angle between the bow and
## the crosshair, asked at every sample. Ten degrees, and most of what it is
## spending is not error but **arm**: `AIM_BONES` turns the chest onto the
## crosshair exactly, and the shoulder, elbow and wrist below it hold whatever
## the draw clip put there, which on this clip is a bow arm carried three to
## five degrees above the line of the chest at every pitch. A tolerance under
## that would be asserting that an archer holds the bow through the middle of
## their own sternum.
const SPINE_BOW_LIMIT := 5.0
const SPINE_APART_LIMIT := 10.0

## How far the bow's own elevation may be from the crosshair's, in degrees. The
## same ten and for the same reason as `SPINE_APART_LIMIT` above — the bow arm
## is not the spine, and what it holds below the chest does not scale with the
## pitch. What this asserts is that the bow **tracks**: it has to move with the
## crosshair over the whole range and stay within ten degrees of it, which is
## the difference between a torso that aims and a torso that does not.
const SPINE_PITCH_LIMIT := 10.0

## How far the bow's elevation has to travel across the pitch sweep for that
## agreement to mean anything, in degrees — the control on the same line. Two
## Gubs holding perfectly level bows agree about everything.
const SPINE_PITCH_SPAN_MIN := 60.0

## How far the release point may move between the two shots `spine` fires from
## one spot, in metres.
##
## A millimetre, and it could be zero: `GubCombat._throw_origin` is built out of
## `global_position`, `eye_height()` and `body_yaw`, and not one of those is on
## the skeleton. What is being asserted is exactly that — that no amount of
## torso turns into a moved shot (D-025, D-045) — so the tolerance is float
## noise and a physics body settling, and nothing else.
const SPINE_RELEASE_TOLERANCE := 0.001

## How long the mode waits for each of its two arrows before giving up, in
## ticks — and it is four thousand of them for a reason worth knowing before
## anybody tightens it.
##
## `GubCombat` measures a draw, a release and a recharge on a **wall clock**
## (`_now()`), while everything in this mode counts physics ticks. Headless with
## `--fixed-fps 60` this scene gets through some thousands of ticks a real
## second, so a 1.2 s recharge is a few thousand ticks here and a few dozen on a
## machine actually rendering at sixty. A patience that is a tick count
## therefore has to be sized for the fast case, and it costs nothing in the slow
## one, because it is only ever reached when something has genuinely gone wrong.
const SPINE_PATIENCE := 4000

var _mode: String = "free"
var _trace: bool = false
var _pov: bool = false
var _frames: int = 0
## Where the `walk` mode started measuring from.
var _walk_from: Vector3 = Vector3.ZERO
var _acted: bool = false

## `bhop`'s state. One subject at a time out of BHOP_SUBJECTS, each walked
## through the steps in `_drive_bhop`; `_bhop_row` collects its numbers.
var _bhop_subject: int = 0
var _bhop_step: int = 0
var _bhop_at: int = 0
var _bhop_hops: int = 0
var _bhop_was_grounded: bool = true
var _bhop_row: Dictionary = {}
var _bhop_failures: int = 0

## `strafe`'s state: which leg of STRAFE_GAITS x STRAFE_COMPASS is running, when
## it started, and the samples taken so far.
var _strafe_leg: int = 0
var _strafe_at: int = 0
var _strafe_skate: Array[float] = []
var _strafe_speed: Array[float] = []
var _strafe_planted: int = 0
## Last tick's toe positions, in world space, so a step is a difference and not
## a velocity somebody has to trust the physics for.
var _strafe_toes: Array[Vector3] = []
## Whether the leg `_strafe_leg` names has been set up yet.
var _strafe_open: bool = false
var _strafe_failures: int = 0
var _strafe_rows: Array[Dictionary] = []

## `spine`'s state. The sweep is one flat list of (yaw, pitch) pairs walked in
## order, then two shots.
var _spine_step: int = 0
var _spine_at: int = 0
var _spine_sample: int = 0
var _spine_rows: Array[Dictionary] = []
var _spine_shots: Array[Dictionary] = []
var _spine_failures: int = 0
## The bow's two shots, step by step, and the flight of whichever one is in the
## air. `_bow_samples` is positions and nothing else — the fit is done at the
## end, so the mode measures the arrow rather than asking it.
var _bow_step: int = 0
var _bow_at: int = 0
var _bow_arrow: ArrowProjectile
var _bow_samples: Array[Vector3] = []
var _bow_health: float = 0.0
var _bow_failures: int = 0

## `draw`'s readings: one row per charge level, local hand against remote hand.
var _draw_step: int = 0
var _draw_at: int = 0
var _draw_rows: Array[Dictionary] = []

var _items: Node3D
var _players: Node3D
var _aim_at: Vector3 = Vector3.ZERO
## The frame the Elder's bolt was fired on, or 0 for "not yet". The verdict is
## taken relative to this rather than at a fixed frame, because the cast waits
## on the robe being picked up and that is an `Area3D` overlap rather than a
## countdown.
var _cast_at: int = 0
## `blast`'s bookkeeping: the distances read at the moment of the current cast,
## and how many verdicts have gone against it.
var _blast_measured: Array[float] = []
var _blast_failures: int = 0
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

## `release`'s bookkeeping: the tick and the millisecond of the click, of the
## shaft appearing, and of the frame the throwing hand was furthest in front of
## the hips — plus whether the fist still had anything in it at the instant the
## shaft existed, which is D-025's promise read at the one moment it is about.
var _release_clicked: int = 0
var _release_clicked_ms: int = 0
var _release_spear_at: int = 0
var _release_spear_ms: int = 0
var _release_fist_full: bool = true
var _release_reach_at: int = 0
var _release_reach: float = -INF
## Looked up once. `find_child` on every tick of a mode that is about
## frame-accurate timing is the wrong kind of cost to add to the thing being
## measured.
## `cast`'s bookkeeping, which is `release`'s plus the one thing that differs:
## the tick the hand stopped advancing, which is this clip's release and is not
## the tick it was furthest forward on.
var _cast_clicked: int = 0
var _cast_clicked_ms: int = 0
var _cast_bolt_at: int = 0
var _cast_bolt_ms: int = 0
var _cast_reach: float = -INF
var _cast_reach_at: int = 0
var _cast_stopped_at: int = 0
var _cast_last_reach: float = -INF
var _cast_advanced: bool = false
var _cast_stopped: bool = false
var _cast_low: float = INF
var _cast_bolt_reach: float = -INF

var _release_skeleton: Skeleton3D
var _release_hand_bone: int = -1
var _release_hips_bone: int = -1

## `ward`'s state machine, the same shape as `cover`'s and on gates for the same
## reason: the robe is claimed by an `Area3D` overlap and burns out on a
## wall clock, and neither of those is a frame number.
var _ward_step: int = 0
var _ward_at: int = 0

## `health`'s state machine, on gates for the same reasons as `ward`'s: a robe
## arrives through an overlap and a respawn arrives on the host's own clock.
##
## `_health_took` is what `MatchState.report_damage` *said* it took, kept beside
## what the body ended up with, because the two are separate claims and a model
## that returned the right number while writing the wrong one would otherwise
## pass. `_wards` counts ward flashes seen in the world (see `_watch_spawned`),
## which is how this mode proves the Elder's feedback survived damage becoming
## a number rather than a refusal.
var _health_step: int = 0
var _health_at: int = 0
var _health_took: float = -1.0
var _health_failures: int = 0
var _wards: int = 0
## The kill this mode was told about, as the rest of the lobby hears it: victim,
## killer and cause off `MatchState.player_killed`, which is the signal the kill
## feed is built on. Empty until something dies.
var _health_kill: Array = []

## `potion`'s state. `_potion_seen` is set on the one frame range in which a
## dropped potion is lying in the world, because "the dummy has one" would also
## be true of a grant that never went through an item; `_potion_owed` is what
## the interrupted drink had earned at the instant it was broken, read off the
## channel's own clock so it can be compared with what the Gub actually kept.
var _potion_step: int = 0
var _potion_at: int = 0
var _potion_seen: bool = false
var _potion_health: float = 0.0
var _potion_mid: float = 0.0
var _potion_owed: float = 0.0
var _potion_stock: int = 0
var _potion_problems: Array[String] = []
var _potion_failures: int = 0
## Ward flashes counted before the Elder was hit, so the verdict is about the
## flash that hit caused and not about any that came before it.
var _wards_before: int = 0
## What went wrong with the verdict currently being built, cleared by each
## verdict as it is printed.
var _health_problems: Array[String] = []

## `embed`'s state machine and the one shaft it is about. Launched by hand with
## nothing listening for its hit, so it damages nobody — this mode is about what
## becomes of the shaft and not about what the hit did.
var _embed_step: int = 0
var _embed_at: int = 0
var _embed_spear: SpearProjectile
var _embed_failures: int = 0
## Where the shaft and the body it is standing in were, immediately before the
## body was moved.
var _embed_spear_was: Vector3 = Vector3.ZERO
var _embed_body_was: Vector3 = Vector3.ZERO

## `respawn`'s state. `_respawn_loot` is every drop lying on either corpse, held
## by reference so the verdict can ask each one whether it was taken.
var _respawn_step: int = 0
var _respawn_at: int = 0
var _respawn_loot: Array[Pickup] = []
## The life the dummy died in, which is what its client's stale snapshots carry,
## and the pad it was revived onto, which is what its fresh ones will.
var _dummy_dead_life: int = 0
var _dummy_pad: Vector3 = Vector3.ZERO
var _dummy_revived_at: int = 0


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
	# The one death in `health` has to roll a robe, so that the Elder half of the
	# run has an Elder in it, and the respawn half has to happen inside the run.
	if _mode == "health":
		config.respawn_delay = HEALTH_RESPAWN
		config.elder_drop_chance = 1.0
		config.letter_drop_chance = 0.0
	# Every death in `potion` has to roll a potion and nothing else, which is
	# what the drop table being **named shares off the top** buys: one slider at
	# 1.0 and the roll has one outcome (D-067). The channel is shortened for the
	# reason POTION_CHANNEL gives, and the respawn has to happen inside the run.
	if _mode == "potion":
		config.respawn_delay = HEALTH_RESPAWN
		config.potion_drop_chance = 1.0
		config.elder_drop_chance = 0.0
		config.letter_drop_chance = 0.0
		config.heal_channel = POTION_CHANNEL
	# The `draw` mode watches a charge *creep*, because what it is comparing is
	# two skeletons at the same instant and a draw that is over in a second is a
	# draw the blends are still settling into. Two seconds is slow enough that
	# every level it samples is a settled pose and short enough that the whole
	# run is over in three.
	if _mode == "draw":
		config.bow_draw_time = DRAW_MODE_DRAW_TIME
	# Three bolts inside one run, and no loot rolled off the one death in it:
	# a robe or a letter dropped at a dummy's feet is a claim nobody asked for.
	if _mode == "blast":
		config.lightning_cooldown = 0.2
		config.lightning_radius = 1.5
		config.elder_drop_chance = 0.0
		config.letter_drop_chance = 0.0


func _dummy_count() -> int:
	match _mode:
		"lure", "blast":
			return 3
		"arc", "miss", "mushroom", "cover", "lure_self", "letter", "respawn":
			return 1
		# Nobody to shoot at. `recharge` throws a dozen spears over the back
		# wall on purpose (see `RECHARGE_TARGET`) and a dummy in the roster
		# would only be something for one of them to find.
		# Nobody to shoot at, and in `strafe`'s case nobody to walk into either:
		# a second Gub standing in the range is a capsule eight of the sixteen
		# legs would run their subject straight through.
		"recharge", "bhop", "release", "cast", "strafe", "spine":
			return 0
		# One per pose in the row. See `_dummy_spot`, which is what puts them
		# somewhere other than the three the shooting modes share.
		"strafing":
			return STRAFE_COMPASS.size()
		"aiming":
			return AIM_LINEUP_PITCHES.size()
		# One each: something to shoot at, and — in `draw` — a *remote* Gub to put
		# a charge on and read the pose back off.
		"bow", "draw":
			return 1
		_:
			return 2


func _spawn_points() -> Array[Transform3D]:
	var out: Array[Transform3D] = [_facing(PLAYER_SPOT, Vector3(0.0, 0.1, 0.0))]
	for i in maxi(_dummy_count(), DUMMY_SPOTS.size()):
		out.append(_facing(_dummy_spot(i), PLAYER_SPOT))
	return out


## Where dummy `i` stands. The three `DUMMY_SPOTS` down the range for every mode
## that shoots at something, and a place in the row for the two that photograph
## one (D-066) — which need more dummies than there are spots and want them in a
## line rather than scattered down the range.
func _dummy_spot(index: int) -> Vector3:
	match _mode:
		"strafing":
			return LINEUP_FIRST + Vector3(LINEUP_STEP * float(index), 0.0, 0.0)
		"aiming":
			return AIM_LINEUP_FIRST + Vector3(AIM_LINEUP_STEP * float(index), 0.0, 0.0)
	return DUMMY_SPOTS[index % DUMMY_SPOTS.size()]


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
			dummy.revive_at(_facing(_dummy_spot(i), PLAYER_SPOT))
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
	# The same signal `HUD._on_player_killed` builds its feed line out of, kept
	# here so `health` can assert that a death by damage is announced exactly as a
	# death by anything else is.
	_health_kill = [victim_id, killer_id, cause]
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
	if _mode == "bhop":
		_drive_bhop()
		return
	if _mode == "leave":
		_drive_leave()
		return
	# Both of these steer the Gub themselves and must not reach the
	# `look_at_point` below: `strafe` needs the view held dead still while the
	# body is driven round it, and `spine` *is* a view sweep, so a re-aim every
	# frame would be the mode fighting itself.
	if _mode == "strafe":
		_drive_strafe()
		return
	if _mode == "spine":
		_drive_spine()
		return
	if _mode == "strafing":
		_drive_lineup(_strafing_rows())
		return
	if _mode == "aiming":
		_drive_lineup(_aiming_rows())
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
	if _mode == "release":
		_drive_release(player, combat)
		return
	if _mode == "cast":
		_drive_cast(player, combat)
		return
	if _mode == "bow":
		_drive_bow(player, combat)
		return
	if _mode == "draw":
		_drive_draw(player, combat)
		return
	if _mode == "ward":
		_drive_ward(combat)
		return
	if _mode == "respawn":
		_drive_respawn(player, combat)
		return
	if _mode == "health":
		_drive_health(combat)
		return
	if _mode == "potion":
		_drive_potion(player, combat)
		return
	if _mode == "embed":
		_drive_embed(player)
		return
	if _mode == "hurt":
		_drive_hurt()
		return
	if _mode == "blast":
		_drive_blast(player, combat)
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
	# flight after that. Since D-063 that is 0.50 s, which at 60 ticks a second
	# is 30 ticks: frame 20 + 30 = tick 50 before the spear is in the air, then
	# 14 m at 42 m/s (0.33 s, 20 ticks) to the dummy, so the kill lands around
	# tick 70. The warmup counts in `tools/smoke_test.sh` are sized for that —
	# 95 for the kill, down from the 110 the 0.71 s release needed, and the
	# lure's 132 is untouched because the lure leaves on the click.
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
		var hand := (MatchState.gubs.get(1) as Gub).held_gear
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


# ------------------------------------------------------------------- blast ---

## See `blast` in the mode list. Each cast is one step: place, measure, fire,
## and twenty ticks later read who is standing.
func _drive_blast(player: Gub, combat: GubCombat) -> void:
	var inside := MatchState.gubs.get(DUMMY_BASE) as Gub
	var outside := MatchState.gubs.get(DUMMY_BASE + 1) as Gub
	var elder := MatchState.gubs.get(DUMMY_BASE + 2) as Gub
	if inside == null or outside == null or elder == null:
		return
	var radius := Net.config.lightning_radius

	if _frames == 12:
		_build_blast_wall()
		MatchState._make_elder(1)
		MatchState._make_elder(DUMMY_BASE + 2)
		# Either side of the first impact, across the line of fire so the bolt
		# reaches the ground between them rather than through one of them.
		_place_at_surface_distance(inside, BLAST_GROUND, Vector3.LEFT,
			radius - BLAST_MARGIN)
		_place_at_surface_distance(outside, BLAST_GROUND, Vector3.RIGHT,
			radius + BLAST_MARGIN)
		elder.global_position = BLAST_ELDER_SPOT
		_stand_still(elder)
		return

	if _frames == BLAST_CASTS[0]:
		_blast_measured = [inside.distance_to_body(BLAST_GROUND),
			outside.distance_to_body(BLAST_GROUND)]
		_blast_cast(combat, BLAST_GROUND)
		return
	if _frames == BLAST_CASTS[0] + BLAST_VERDICT_DELAY:
		var landed := _blast_landed().distance_to(BLAST_GROUND) < 0.05
		if not landed:
			print("combat_range: the first bolt landed at %s, not %s" % [
				_blast_landed(), BLAST_GROUND])
		_blast_verdict("inside", landed and _blast_measured[0] < radius and not inside.alive,
			"%s %.2f m from the impact, radius %.2f — %s" % [inside.display_name,
				_blast_measured[0], radius, "dead" if not inside.alive else "STANDING"])
		_blast_verdict("outside", landed and _blast_measured[1] > radius and outside.alive,
			"%s %.2f m from the impact — %s" % [outside.display_name,
				_blast_measured[1], "standing" if outside.alive else "DEAD"])
		# The survivor goes behind the wall for the second bolt, at the same
		# inside distance the first dummy died at.
		_place_at_surface_distance(outside, BLAST_BY_WALL, Vector3.FORWARD,
			radius - BLAST_MARGIN)
		return

	if _frames == BLAST_CASTS[1]:
		_blast_measured = [outside.distance_to_body(BLAST_BY_WALL)]
		_blast_cast(combat, BLAST_BY_WALL)
		return
	if _frames == BLAST_CASTS[1] + BLAST_VERDICT_DELAY:
		var landed := _blast_landed().distance_to(BLAST_BY_WALL) < 0.05
		var behind := outside.global_position.z < BLAST_WALL.z - BLAST_WALL_SIZE.z * 0.5
		_blast_verdict("wall",
			landed and behind and _blast_measured[0] < radius and outside.alive,
			"%s %.2f m from the impact, behind a wall — %s" % [outside.display_name,
				_blast_measured[0], "standing" if outside.alive else "DEAD"])
		return

	if _frames == BLAST_CASTS[2]:
		_blast_cast(combat, elder.body_centre())
		return
	if _frames == BLAST_CASTS[2] + BLAST_VERDICT_DELAY:
		var struck := elder.distance_to_body(_blast_landed()) < 0.05
		_blast_verdict("elder",
			struck and elder.alive and MatchState.is_elder(DUMMY_BASE + 2),
			"a bolt %s the Elder %s — %s" % [
				"landed square on" if struck else "did NOT land on", elder.display_name,
				"standing" if elder.alive else "DEAD"])
		_blast_verdict("config", _blast_config_round_trips(),
			"lightning_radius survives to_dict/apply_dict and clamps to 0..4")
		if _blast_failures == 0:
			print("combat_range: every blast verdict held — blast PASS")
		else:
			print("combat_range: %d blast verdict(s) failed — blast FAIL" % _blast_failures)


## Fire the Elder's bolt from the player's hand at `target`, through the host's
## own cast. The aim is exact, so the impact is `target` unless the ray meets
## something before it — which `_blast_landed` is there to catch.
func _blast_cast(combat: GubCombat, target: Vector3) -> void:
	if not MatchState.is_elder(1):
		print("combat_range: the player is not the Elder — blast FAIL")
		return
	var origin: Vector3 = combat._throw_origin()
	combat._host_cast_lightning(origin, (target - origin).normalized())
	print("combat_range: bolt fired on frame %d at %s, landed %s"
		% [_frames, target, _blast_landed()])


## Where the newest bolt in the scene stopped, or nowhere near anything if there
## is none.
func _blast_landed() -> Vector3:
	for i in range(_items.get_child_count() - 1, -1, -1):
		var bolt := _items.get_child(i) as LightningBolt
		if bolt != null:
			return bolt._to
	return Vector3.ONE * 1.0e6


func _blast_verdict(label: String, ok: bool, detail: String) -> void:
	if not ok:
		_blast_failures += 1
	print("combat_range: %s — %s %s" % [detail, label, "PASS" if ok else "FAIL"])


## Stand `dummy` on the ground along `away` from `impact`, with the surface of
## its capsule `distance` from it. Solved by stepping on the real measurement
## rather than by formula, so the answer is whatever `Gub.distance_to_body`
## says it is — which is the thing the rule reads.
func _place_at_surface_distance(dummy: Gub, impact: Vector3, away: Vector3,
		distance: float) -> void:
	var along := distance + Gub.CAPSULE_RADIUS
	var ground := Vector3(impact.x, PLAYER_SPOT.y, impact.z)
	for i in 6:
		dummy.global_position = ground + away * along
		along += distance - dummy.distance_to_body(impact)
	dummy.global_position = ground + away * along
	dummy.velocity = Vector3.ZERO
	_stand_still(dummy)


func _build_blast_wall() -> void:
	var body := StaticBody3D.new()
	body.name = "BlastWall"
	body.collision_layer = 1
	body.position = BLAST_WALL
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BLAST_WALL_SIZE
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = BLAST_WALL_SIZE
	mesh.mesh = cube
	body.add_child(mesh)


func _blast_config_round_trips() -> bool:
	var sent := MatchConfig.new()
	sent.lightning_radius = 2.7
	var got := MatchConfig.new()
	got.apply_dict(sent.to_dict())
	var ok := is_equal_approx(got.lightning_radius, 2.7)
	got.apply_dict({"lightning_radius": 9.0})
	ok = ok and is_equal_approx(got.lightning_radius, 4.0)
	got.apply_dict({"lightning_radius": -1.0})
	ok = ok and is_equal_approx(got.lightning_radius, 0.0)
	return ok and is_equal_approx(MatchConfig.new().lightning_radius, 1.5)


# ----------------------------------------------------------------- respawn ---

## Kill a Gub carrying a mushroom and an Elder wearing a robe, leave both lying
## in loot, respawn both, and require empty hands a second later.
##
## Steps, each on a gate rather than a frame number where there is one:
##   0  stock both, robe the dummy, move both off their pads
##   1  kill both where they stand and put loot on both corpses
##   2  wait for both to be revived, playing the dummy's dead client meanwhile
##   3  a second later, the verdict
func _drive_respawn(player: Gub, combat: GubCombat) -> void:
	var dummy := MatchState.gubs.get(DUMMY_BASE) as Gub
	if dummy == null:
		return
	var dummy_combat := dummy.get_node_or_null("Combat") as GubCombat
	# The dummy's client, from the kill on. Dead, or not yet told it has been
	# revived, it publishes the corpse in the life it died in; caught up, it
	# publishes the pad it was revived onto.
	if _respawn_step >= 2:
		_publish_for_dummy(dummy)

	match _respawn_step:
		0:
			if _frames < 20:
				return
			combat.grant_mushroom(1)
			dummy_combat.grant_mushroom(1)
			MatchState._make_elder(DUMMY_BASE)
			player.global_position = RESPAWN_PLAYER_CORPSE
			player.velocity = Vector3.ZERO
			dummy.global_position = RESPAWN_DUMMY_CORPSE
			_stand_still(dummy)
			_respawn_step = 1
			_respawn_at = _frames
		1:
			# Long enough for the robe to be on and the grants to have landed,
			# which is the state the precondition below insists on.
			if _frames - _respawn_at < 10:
				return
			var armed := combat.mushroom_count() == 1 and dummy_combat.mushroom_count() == 1 \
				and MatchState.is_elder(DUMMY_BASE) and dummy.elder_robe != null
			if not armed:
				print("combat_range: nobody was carrying anything to lose — respawn FAIL")
				get_tree().quit()
				return
			_dummy_dead_life = dummy.life
			dummy.respawned.connect(func() -> void:
				_dummy_pad = dummy.global_position
				_dummy_revived_at = _frames, CONNECT_ONE_SHOT)
			# The player to a spear, which rolls its own loot — forced to a robe,
			# so the thing lying on the corpse is the thing the player said they
			# came back wearing. The Elder to the void, because since D-040 that
			# is the only death it has, and a void death drops nothing; its loot
			# is put down by hand through the same `_spawn_drop` a roll uses.
			Net.config.elder_drop_chance = 1.0
			MatchState.report_kill(1, DUMMY_BASE, Gub.Cause.SPEAR,
				player.global_position, Vector3.FORWARD * 18.0, "Spine1")
			MatchState.report_kill(DUMMY_BASE, DUMMY_BASE, Gub.Cause.VOID,
				dummy.global_position, Vector3.DOWN, "")
			var player_spot: Vector3 = MatchState._drop_spot(player.global_position)
			var dummy_spot: Vector3 = MatchState._drop_spot(dummy.global_position)
			MatchState._spawn_drop(Pickup.Kind.MUSHROOM, 0, player_spot)
			MatchState._spawn_drop(Pickup.Kind.MUSHROOM, 0, dummy_spot)
			MatchState._spawn_drop(Pickup.Kind.ELDER_ROBE, 0, dummy_spot)
			for item: Pickup in MatchState._pickups.values():
				if is_instance_valid(item) and not item.is_taken():
					_respawn_loot.append(item)
			if player.alive or dummy.alive or _respawn_loot.size() != 4:
				print("combat_range: expected two corpses and four drops, got %d drops — respawn FAIL"
					% _respawn_loot.size())
				get_tree().quit()
				return
			_respawn_step = 2
		2:
			if not player.alive or not dummy.alive:
				return
			_respawn_step = 3
			_respawn_at = _frames
		3:
			if _frames - _respawn_at < RESPAWN_SETTLE_TICKS:
				return
			_report_respawn(player, combat, dummy, dummy_combat)
			get_tree().quit()


## What the dummy's client would be sending this tick. See `RESPAWN_STALE_TICKS`.
##
## After the revive its snapshots land on every *other* tick, starting with the
## second, and that spacing is not decoration. A snapshot on every tick puts the
## body back on the corpse before the physics server has ever stepped it at the
## pad, so no `Pickup` sees it leave and none sees it come back — the check goes
## green on the bug. Real packets do not arrive once per physics tick, and one
## tick at the pad is all it takes: the body leaves the catch volume, the stale
## snapshot drags it back in, and `body_entered` fires on a Gub that is alive.
func _publish_for_dummy(dummy: Gub) -> void:
	if not dummy.alive:
		dummy.sync_position = RESPAWN_DUMMY_CORPSE
		dummy.sync_life = _dummy_dead_life
		return
	var since := _frames - _dummy_revived_at
	if since < RESPAWN_STALE_TICKS:
		if since % 2 == 1:
			return
		dummy.sync_position = RESPAWN_DUMMY_CORPSE
		dummy.sync_life = _dummy_dead_life
		return
	dummy.sync_position = _dummy_pad
	dummy.sync_life = dummy.life


func _report_respawn(player: Gub, combat: GubCombat, dummy: Gub,
		dummy_combat: GubCombat) -> void:
	var taken := 0
	for item: Pickup in _respawn_loot:
		if not is_instance_valid(item) or item.is_taken():
			taken += 1
	var clear := RESPAWN_PLAYER_CORPSE.distance_to(player.global_position) > 6.0 \
		and RESPAWN_DUMMY_CORPSE.distance_to(_dummy_pad) > 6.0
	var carrying := "player %d mushrooms %d lures %s, dummy %d mushrooms %d lures %s" % [
		combat.mushroom_count(), combat.lure_count(),
		"ELDER" if MatchState.is_elder(1) or player.elder_robe != null else "no robe",
		dummy_combat.mushroom_count(), dummy_combat.lure_count(),
		"ELDER" if MatchState.is_elder(DUMMY_BASE) or dummy.elder_robe != null else "no robe"]
	var empty := combat.mushroom_count() == 0 and combat.lure_count() == 0 \
		and dummy_combat.mushroom_count() == 0 and dummy_combat.lure_count() == 0 \
		and not MatchState.is_elder(1) and not MatchState.is_elder(DUMMY_BASE) \
		and player.elder_robe == null and dummy.elder_robe == null
	if not clear:
		print("combat_range: a Gub was revived on top of its own corpse, so this proves nothing — respawn FAIL")
	elif empty and taken == 0:
		print("combat_range: a second after respawning, %s; %d of %d drops still on the corpses — respawn PASS"
			% [carrying, _respawn_loot.size() - taken, _respawn_loot.size()])
	else:
		print("combat_range: a second after respawning, %s; %d of %d drops picked up off the corpses — respawn FAIL"
			% [carrying, taken, _respawn_loot.size()])


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


# ------------------------------------------------------------------ health ---

## The damage model, end to end and in numbers (D-062). See the `health` entry
## in MODES' notes for the five verdicts and why each is there.
##
## Every hit goes through `MatchState.report_damage` — the real door, on the
## real host, in a real match loop — and nothing here writes a health field or a
## `stats` row by hand. What the harness does supply is the geometry a weapon
## would have supplied: a point on the body, a blow and a bone.
##
## The killing hit is aimed at the **far** dummy's feet rather than at the body
## it kills, which is the same trick `_robe_at_the_dummys_feet` uses: the point
## a death is reported at is where its loot lands, so a robe rolled off the near
## dummy's corpse comes down under the far one and is picked up by it. That is
## how a mode with one death in it gets an Elder to shoot at.
func _drive_health(combat: GubCombat) -> void:
	var near := MatchState.gubs.get(DUMMY_BASE) as Gub
	var far := MatchState.gubs.get(DUMMY_BASE + 1) as Gub
	if near == null or far == null:
		return

	match _health_step:
		0:
			# Late enough for both Gubs to have settled onto the ground and for
			# the spawn-frame transforms to have been published.
			if _frames < 12:
				return
			_health_took = _hit(near, HEALTH_HITS[0])
			_health_step = 1
		1:
			# A frame later than the hit, deliberately: what is read here is
			# what the body is carrying into the next tick, not what the call
			# left behind on its way out.
			var after_one := Gub.MAX_HEALTH - HEALTH_HITS[0]
			_health_expect(near.alive, "the first hit killed it")
			_health_expect(is_equal_approx(near.health, after_one),
				"the body says %.1f and not %.1f" % [near.health, after_one])
			_health_expect(is_equal_approx(MatchState.health_of(DUMMY_BASE), after_one),
				"the host says %.1f" % MatchState.health_of(DUMMY_BASE))
			_health_expect(is_equal_approx(_health_took, HEALTH_HITS[0]),
				"report_damage said it took %.1f" % _health_took)
			_health_expect(_plate_agrees(near),
				"the bar over its head is at %.2f" % _plate_fraction(near))
			_health_took = _hit(near, HEALTH_HITS[1])
			_health_step = 2
		2:
			var after_two := Gub.MAX_HEALTH - HEALTH_HITS[0] - HEALTH_HITS[1]
			_health_expect(near.alive, "the second hit killed it")
			_health_expect(is_equal_approx(near.health, after_two),
				"two hits left %.1f and not %.1f" % [near.health, after_two])
			_health_expect(is_equal_approx(_health_took, HEALTH_HITS[1]),
				"the second hit reported %.1f" % _health_took)
			_health_expect(_plate_agrees(near),
				"the bar over its head is at %.2f" % _plate_fraction(near))
			_health_verdict("partial", "%.0f then %.0f left %s standing on %.0f"
				% [HEALTH_HITS[0], HEALTH_HITS[1], near.display_name, near.health])
			# ...and the third takes it to exactly zero, with the robe it rolls
			# put down under the far dummy.
			_health_took = MatchState.report_damage(DUMMY_BASE, 1, HEALTH_HITS[2],
				Gub.Cause.SPEAR, far.global_position, Vector3.FORWARD * 18.0, "Spine1")
			_health_at = _frames
			_health_step = 3
		3:
			_health_expect(not near.alive, "the last hit left it standing")
			_health_expect(not MatchState.is_alive(DUMMY_BASE),
				"the host still has it alive")
			_health_expect(is_equal_approx(near.health, 0.0),
				"it died on %.1f health" % near.health)
			_health_expect(is_equal_approx(_health_took, HEALTH_HITS[2]),
				"the killing hit reported %.1f" % _health_took)
			_health_expect(_corpses() > 0, "no corpse was made")
			_health_expect(_health_kill == [DUMMY_BASE, 1, Gub.Cause.SPEAR],
				"the lobby was told %s" % [_health_kill])
			_health_verdict("lethal", "the third hit killed %s, %d corpse(s), feed says %s"
				% [near.display_name, _corpses(), _health_kill])
			_health_step = 4
		4:
			# On the Elder state and not on a frame count: what stands between
			# the drop and the robe is an `Area3D` overlap resolving.
			if not MatchState.is_elder(DUMMY_BASE + 1):
				if _frames - _health_at > HEALTH_RESPAWN_LIMIT:
					_health_expect(false, "no robe ever reached %s — there was no Elder to shoot at"
						% far.display_name)
					_health_verdict("elder", "waited %d frames" % HEALTH_RESPAWN_LIMIT)
					_health_finish()
				return
			_wards_before = _wards
			_health_took = _hit(far, HEALTH_ELDER_HIT)
			_health_step = 5
		5:
			_health_expect(is_equal_approx(_health_took, 0.0),
				"the Elder took %.1f" % _health_took)
			_health_expect(far.alive, "the Elder died")
			_health_expect(is_equal_approx(far.health, Gub.MAX_HEALTH),
				"the Elder is down to %.1f" % far.health)
			_health_expect(_wards > _wards_before, "no ward flashed")
			_health_verdict("elder", "%.0f at an Elder took %.0f and flashed %d ward(s)"
				% [HEALTH_ELDER_HIT, _health_took, _wards - _wards_before])
			_health_step = 6
		6:
			if not MatchState.is_alive(DUMMY_BASE):
				if _frames - _health_at > HEALTH_RESPAWN_LIMIT:
					_health_expect(false, "%s never came back" % near.display_name)
					_health_verdict("respawn", "waited %d frames" % HEALTH_RESPAWN_LIMIT)
					_health_finish()
				return
			_health_expect(is_equal_approx(near.health, Gub.MAX_HEALTH),
				"it came back on %.1f" % near.health)
			_health_expect(_plate_agrees(near),
				"its bar came back at %.2f" % _plate_fraction(near))
			_health_verdict("respawn", "%s came back on %.0f of %.0f"
				% [near.display_name, near.health, Gub.MAX_HEALTH])
			# Put it back on its own pad before the control throw. A respawn
			# picks the pad furthest from everybody (`MatchState._next_spawn`),
			# which can be thirty metres away — and a spear thrown thirty metres
			# at a chest is a question about drop, not about damage.
			near.revive_at(_facing(DUMMY_SPOTS[0], PLAYER_SPOT))
			_stand_still(near)
			_health_step = 7
		7:
			if not combat.has_spear():
				return
			combat.try_throw_spear()
			_health_at = _frames
			_health_step = 8
		8:
			if _frames < _health_at + SPEAR_VERDICT_DELAY:
				return
			# The control, in D-039's sense, and the one the whole plan turns
			# on. A damage model that had quietly made the spear a two-shot
			# would pass every other line in this mode.
			_health_expect(not near.alive,
				"%s survived a spear on %.0f health" % [near.display_name, near.health])
			_health_verdict("spear", "one thrown spear at a Gub on full health")
			_health_finish()


## One hit through the real door, at the middle of a body, with a weapon's worth
## of geometry behind it. Returns what the host says it took.
func _hit(victim: Gub, amount: float) -> float:
	return MatchState.report_damage(victim.peer_id, 1, amount, Gub.Cause.SPEAR,
		victim.body_centre(), Vector3.FORWARD * 6.0, "Spine1")


## What the bar over a Gub's head is showing, 1 -> 0, read off the plate itself
## rather than recomputed — the point of asking is that the display path is a
## second copy of the number and either half can be wrong on its own.
func _plate_fraction(gub: Gub) -> float:
	return gub.nameplate._health if gub.nameplate != null else -1.0


func _plate_agrees(gub: Gub) -> bool:
	return is_equal_approx(_plate_fraction(gub), gub.health_fraction())


func _corpses() -> int:
	var found := 0
	for child in _players.get_children():
		if child is GubRagdoll:
			found += 1
	return found


func _health_expect(ok: bool, wrong: String) -> void:
	if not ok:
		_health_problems.append(wrong)


func _health_verdict(label: String, detail: String) -> void:
	if _health_problems.is_empty():
		print("combat_range: %s — %s PASS" % [detail, label])
	else:
		_health_failures += 1
		print("combat_range: %s — %s FAIL (%s)"
			% [detail, label, "; ".join(_health_problems)])
	_health_problems.clear()


func _health_finish() -> void:
	print("combat_range: %d health verdict(s) failed" % _health_failures)
	get_tree().quit()


# ------------------------------------------------------------------ potion ---

## The heal potion, end to end (D-067). See the `potion` entry in MODES' notes
## for the six verdicts and why each is there.
##
## Every number here comes off the real path: the potion is rolled by
## `MatchState._drop_loot` out of a real death, collected by a real `Area3D`
## overlap, drunk through `GubCombat.try_drink_potion` and healed through
## `MatchState.report_heal`. Nothing in this mode writes a health field, a stock
## count or a channel clock by hand.
func _drive_potion(player: Gub, combat: GubCombat) -> void:
	var near := MatchState.gubs.get(DUMMY_BASE) as Gub
	var far := MatchState.gubs.get(DUMMY_BASE + 1) as Gub
	if near == null or far == null:
		return
	var far_combat := far.get_node_or_null("Combat") as GubCombat
	if far_combat == null:
		return

	match _potion_step:
		0:
			if _frames < 12:
				return
			# The death point is the *far* dummy's feet, so what rolls out of the
			# near one's corpse lands under a Gub that can walk into it — the
			# trick `_robe_at_the_dummys_feet` uses, and the only way a dummy
			# with no client behind it ever collects anything.
			MatchState.report_kill(DUMMY_BASE, 1, Gub.Cause.SPEAR,
				far.global_position, Vector3.FORWARD * 18.0, "Spine1")
			_potion_at = _frames
			_potion_step = 1
		1:
			if far_combat.potion_count() <= 0:
				if _frames - _potion_at > POTION_PATIENCE:
					_potion_expect(false,
						"no potion ever reached %s" % far.display_name)
					_potion_verdict("drop", "waited %d frames" % POTION_PATIENCE)
					_potion_finish()
				return
			_potion_expect(_potion_seen, "nothing was ever lying on the ground")
			_potion_verdict("drop", "%s's corpse left a potion and %s walked onto it"
				% [near.display_name, far.display_name])

			# On to the drink. The player is hurt first, because a Gub at full
			# health heals nothing and every number below would be zero.
			_hit(player, POTION_WOUND)
			combat.grant_potion(2)
			_potion_step = 2
		2:
			if not combat.has_potion():
				return
			_potion_health = player.health
			_potion_stock = combat.potion_count()
			combat.try_drink_potion()
			_potion_at = _frames
			_potion_step = 3
		3:
			# One frame after the keypress. **The whole point of the feature is
			# what is asserted here**: the potion has been spent and no health
			# has arrived.
			_potion_expect(combat.is_channelling(), "the drink never started")
			_potion_expect(combat.potion_count() == _potion_stock - 1,
				"the stock went from %d to %d" % [_potion_stock, combat.potion_count()])
			_potion_expect(is_equal_approx(player.health, _potion_health),
				"health jumped to %.1f on the frame of the click" % player.health)
			_potion_step = 4
		4:
			if combat.channel_fraction() < 0.5:
				return
			# Half way: some of it has arrived and not all of it. Two
			# assertions, and each is the other's control — "more than none"
			# catches a heal that only lands at the end, "less than all" catches
			# one that landed at the start.
			_potion_mid = player.health
			_potion_expect(_potion_mid > _potion_health + POTION_EPSILON,
				"half way through, health was still %.1f" % _potion_mid)
			_potion_expect(_potion_mid < _potion_health + Net.config.heal_amount
					- POTION_EPSILON,
				"half way through, the whole potion had already arrived (%.1f)"
					% _potion_mid)
			_potion_step = 5
		5:
			if combat.is_channelling():
				return
			# And the far end: all of it, once, and the arm down.
			var want := _potion_health + Net.config.heal_amount
			_potion_expect(is_equal_approx(player.health, want),
				"the finished drink left %.1f and not %.1f" % [player.health, want])
			_potion_verdict("channel",
				"%.0f health over %.1f s: %.0f at the click, %.0f half way, %.0f at the end"
				% [Net.config.heal_amount, Net.config.heal_channel, _potion_health,
					_potion_mid, player.health])

			# The interrupt. Hurt back down, and drink the second potion.
			_hit(player, POTION_WOUND)
			_potion_health = player.health
			_potion_stock = combat.potion_count()
			combat.try_drink_potion()
			_potion_at = _frames
			_potion_step = 6
		6:
			if combat.channel_fraction() < POTION_INTERRUPT_AT:
				return
			# What the drink is owed at the instant it is broken, read off the
			# *channel's own* clock rather than off a frame count — the host
			# pays out to exactly this fraction on its way out, so a frame
			# counter running beside a millisecond clock would put the tolerance
			# below in the wrong place for a reason that has nothing to do with
			# the mechanic.
			_potion_owed = Net.config.heal_amount * combat.channel_fraction()
			_potion_mid = player.health
			# The recorded rule, through the real door.
			_hit(player, POTION_INTERRUPT_HIT)
			_potion_step = 7
		7:
			var kept := player.health - _potion_health + POTION_INTERRUPT_HIT
			_potion_expect(not combat.is_channelling(),
				"the hit did not end the channel")
			_potion_expect(combat.potion_count() == _potion_stock - 1,
				"the interrupted potion came back: stock is %d of %d"
					% [combat.potion_count(), _potion_stock])
			_potion_expect(kept > POTION_EPSILON,
				"the interrupted drink healed nothing at all")
			_potion_expect(kept < Net.config.heal_amount - POTION_EPSILON,
				"the interrupted drink healed the whole %.1f" % kept)
			_potion_expect(absf(kept - _potion_owed) < POTION_KEPT_TOLERANCE,
				"kept %.1f of the potion where %.1f had arrived" % [kept, _potion_owed])
			_potion_verdict("interrupt",
				"a hit %.0f%% in spent the potion and kept %.1f of %.0f (owed %.1f)"
				% [POTION_INTERRUPT_AT * 100.0, kept, Net.config.heal_amount,
					_potion_owed])

			# Moving. The harness drives the body itself from here, so the Gub
			# stops reading a keyboard that is not there.
			player.reads_local_input = false
			player.input_direction = Vector2.ZERO
			combat.grant_potion(2)
			_potion_step = 8
		8:
			if not combat.has_potion():
				return
			_potion_stock = combat.potion_count()
			combat.try_drink_potion()
			_potion_at = _frames
			_potion_step = 9
		9:
			# Settled into the channel before anything is asked of it, so that
			# "it stopped" cannot be "it never started".
			if _frames - _potion_at < POTION_SETTLE:
				return
			_potion_expect(combat.is_channelling(),
				"the drink was over before the Gub moved")
			player.input_direction = Vector2(0.0, -1.0)
			player.wants_sprint = true
			_potion_at = _frames
			_potion_step = 10
		10:
			if _frames - _potion_at < POTION_SETTLE:
				return
			_potion_expect(not combat.is_channelling(),
				"running at %.1f m/s did not end the channel"
					% _flat_speed(player))
			_potion_expect(_flat_speed(player) > GubCombat.CHANNEL_MOVE_SPEED,
				"the Gub never got moving: %.2f m/s" % _flat_speed(player))
			_potion_expect(combat.potion_count() == _potion_stock - 1,
				"the abandoned potion came back")
			player.input_direction = Vector2.ZERO
			player.wants_sprint = false
			_potion_at = _frames
			_potion_step = 11
		11:
			# Stopped, and standing still again, before the lure control.
			if _flat_speed(player) > GubCombat.CHANNEL_MOVE_SPEED * 0.5:
				return
			_potion_stock = combat.potion_count()
			combat.try_drink_potion()
			_potion_at = _frames
			_potion_step = 12
		12:
			if _frames - _potion_at < POTION_SETTLE:
				return
			_potion_expect(combat.is_channelling(), "the second drink never started")
			# **The control, and the edge case the rule was written for.** A
			# lure drags a Gub without its owner pressing anything, and a rule
			# about displacement rather than about intent would cancel here —
			# which would quietly make the lure the best answer to a drink.
			# `apply_lure` is what a caught Gub's own client receives.
			player.apply_lure(player.global_position + POTION_LURE_FROM,
				Net.config.lure_pull_strength, POTION_LURE_HOLD)
			_potion_at = _frames
			_potion_step = 13
		13:
			if _frames - _potion_at < POTION_SETTLE:
				return
			_potion_expect(combat.is_channelling(),
				"a lure cancelled the drink; it was doing %.2f m/s"
					% _flat_speed(player))
			_potion_expect(_flat_speed(player) > GubCombat.CHANNEL_MOVE_SPEED,
				"the lure never actually moved it: %.2f m/s" % _flat_speed(player))
			_potion_verdict("moved",
				"running ended the channel at %.2f m/s and a lure dragging it at %.2f did not"
				% [GubCombat.CHANNEL_MOVE_SPEED, _flat_speed(player)])
			_potion_step = 14
		14:
			# Everything carried is lost on death (D-032). Two potions on a Gub
			# that is about to die, and a fresh life that has none.
			combat.grant_potion(2)
			_potion_stock = combat.potion_count()
			MatchState.report_kill(1, DUMMY_BASE + 1, Gub.Cause.SPEAR,
				player.body_centre(), Vector3.FORWARD * 6.0, "Spine1")
			_potion_at = _frames
			_potion_step = 15
		15:
			if not MatchState.is_alive(1):
				if _frames - _potion_at > POTION_PATIENCE:
					_potion_expect(false, "%s never came back" % player.display_name)
					_potion_verdict("death", "waited %d frames" % POTION_PATIENCE)
					_potion_finish()
				return
			_potion_expect(_potion_stock >= 2,
				"it only had %d potion(s) to lose" % _potion_stock)
			_potion_expect(combat.potion_count() == 0,
				"it came back carrying %d potion(s)" % combat.potion_count())
			_potion_expect(not combat.is_channelling(),
				"it came back still drinking")
			_potion_verdict("death", "%d potion(s) went into the ground with %s"
				% [_potion_stock, player.display_name])
			_potion_verdict("config", _potion_config_round_trips())
			_potion_finish()


## One drop, one frame after it was built, with its kind filled in.
##
## `potion`'s only use for it is the assertion that a *potion* was lying there:
## "the dummy ended up with one" would be satisfied just as well by a grant that
## never went through an item at all.
func _note_pickup(item: Pickup) -> void:
	if is_instance_valid(item) and item.kind == Pickup.Kind.POTION:
		_potion_seen = true


func _flat_speed(gub: Gub) -> float:
	return Vector3(gub.velocity.x, 0.0, gub.velocity.z).length()


## The three dials this step added, through `to_dict`/`apply_dict` and out the
## far side of the clamps — the round trip a host's slider actually makes. A
## field missing from `MatchConfig._FIELDS` is a setting the host changes and
## nobody else ever sees, which is what this line exists to catch.
func _potion_config_round_trips() -> String:
	var sent := MatchConfig.new()
	sent.heal_amount = 55.0
	sent.heal_channel = 3.5
	sent.potion_drop_chance = 0.42
	var got := MatchConfig.new()
	got.apply_dict(sent.to_dict())
	var problems: Array[String] = []
	if not is_equal_approx(got.heal_amount, 55.0):
		problems.append("heal_amount arrived as %.1f" % got.heal_amount)
	if not is_equal_approx(got.heal_channel, 3.5):
		problems.append("heal_channel arrived as %.2f" % got.heal_channel)
	if not is_equal_approx(got.potion_drop_chance, 0.42):
		problems.append("potion_drop_chance arrived as %.2f" % got.potion_drop_chance)
	# The clamps, at both ends of each, because a dial that survives the trip
	# and then accepts anything is a dial a modified peer can use to turn the
	# channel off — which is the one setting D-067 refuses to have.
	got.apply_dict({"heal_amount": 900.0, "heal_channel": 0.0,
		"potion_drop_chance": 7.0})
	if not is_equal_approx(got.heal_amount, 100.0):
		problems.append("heal_amount clamped to %.1f" % got.heal_amount)
	if not is_equal_approx(got.heal_channel, 0.5):
		problems.append("an instant channel survived as %.2f" % got.heal_channel)
	if not is_equal_approx(got.potion_drop_chance, 1.0):
		problems.append("potion_drop_chance clamped to %.2f" % got.potion_drop_chance)
	got.apply_dict({"heal_amount": -4.0, "heal_channel": -1.0,
		"potion_drop_chance": -1.0})
	if not is_equal_approx(got.heal_amount, 5.0):
		problems.append("heal_amount floored at %.1f" % got.heal_amount)
	if not is_equal_approx(got.heal_channel, 0.5):
		problems.append("heal_channel floored at %.2f" % got.heal_channel)
	if not is_equal_approx(got.potion_drop_chance, 0.0):
		problems.append("potion_drop_chance floored at %.2f" % got.potion_drop_chance)
	_potion_problems.append_array(problems)
	return "heal_amount, heal_channel and potion_drop_chance survive " \
		+ "to_dict/apply_dict and clamp at both ends"


func _potion_expect(ok: bool, wrong: String) -> void:
	if not ok:
		_potion_problems.append(wrong)


func _potion_verdict(label: String, detail: String) -> void:
	if _potion_problems.is_empty():
		print("combat_range: %s — %s PASS" % [detail, label])
	else:
		_potion_failures += 1
		print("combat_range: %s — %s FAIL (%s)"
			% [detail, label, "; ".join(_potion_problems)])
	_potion_problems.clear()


func _potion_finish() -> void:
	print("combat_range: %d potion verdict(s) failed" % _potion_failures)
	get_tree().quit()


# ------------------------------------------------------------------- embed ---

## A shaft standing in a Gub who is still alive, and then in the corpse that Gub
## becomes (D-062). See the `embed` entry in MODES' notes.
##
## The spear is launched by hand rather than thrown, and that is the whole
## design of the mode: `GubCombat` connects its own thrown spears to
## `report_damage`, so a thrown one would kill what it hit and there would be no
## living victim left to ride. Launched here, with nothing listening to
## `struck_gub`, it lands on a Gub who takes no damage at all — which is exactly
## the case every arrow from the bow will be, one step before that bow exists.
func _drive_embed(player: Gub) -> void:
	var near := MatchState.gubs.get(DUMMY_BASE) as Gub
	if near == null:
		return

	match _embed_step:
		0:
			if _frames < 12:
				return
			var origin := player.global_position + Vector3.UP * player.eye_height()
			var target := near.body_centre()
			_embed_spear = SpearProjectile.launch(_items, player, origin,
				(target - origin).normalized(), true)
			_embed_at = _frames
			_embed_step = 1
		1:
			if not is_instance_valid(_embed_spear):
				_embed_failures += 1
				print("combat_range: the shaft was freed in flight — embed FAIL")
				_embed_finish()
				return
			if not _embed_spear.is_stuck():
				if _frames - _embed_at > EMBED_FLIGHT_LIMIT:
					_embed_failures += 1
					print("combat_range: the shaft never reached anybody — embed FAIL")
					_embed_finish()
				return
			# It has arrived. Move the body, and require the shaft to arrive
			# with it: a spear parked in the air where a Gub used to be looks
			# identical to one riding the Gub right up until the Gub moves.
			_embed_spear_was = _embed_spear.global_position
			_embed_body_was = near.global_position
			near.global_position += EMBED_MOVE
			_stand_still(near)
			_embed_at = _frames
			_embed_step = 2
		2:
			# Two ticks, so the skeleton has been posed at the new position and
			# the shaft has had a physics frame to copy it.
			if _frames < _embed_at + 2:
				return
			var moved := _embed_spear.global_position - _embed_spear_was
			var wanted := near.global_position - _embed_body_was
			var slip := (moved - wanted).length()
			var problems: Array[String] = []
			if not near.alive:
				problems.append("the hit killed it")
			if not _embed_spear.visible:
				problems.append("the shaft is invisible")
			if slip > EMBED_TOLERANCE:
				problems.append("the shaft is %.2f m adrift of the body" % slip)
			if _embed_spear.get_parent() != _items:
				problems.append("something re-parented it early")
			if problems.is_empty():
				print("combat_range: %s moved %.2f m with a spear in it and the spear came too, %.3f m adrift — embed PASS"
					% [near.display_name, wanted.length(), slip])
			else:
				_embed_failures += 1
				print("combat_range: embed FAIL (%s)" % "; ".join(problems))
			# Now kill it, and the same shaft has to end up on the corpse.
			MatchState.report_damage(DUMMY_BASE, 1, Gub.MAX_HEALTH, Gub.Cause.SPEAR,
				near.body_centre(), Vector3.FORWARD * 14.0, "Spine1")
			_embed_at = _frames
			_embed_step = 3
		3:
			var after: Array[String] = []
			if not is_instance_valid(_embed_spear):
				after.append("the shaft was freed instead of adopted")
			else:
				if not (_embed_spear.get_parent() is PhysicalBone3D):
					after.append("its parent is %s and not a physical bone"
						% _embed_spear.get_parent())
				if not _embed_spear.visible:
					after.append("it is invisible on the corpse")
			if _corpses() < 1:
				after.append("there is no corpse")
			# Nothing may be left waiting on the Gub: a shaft on an invisible
			# list is the bug `SpearProjectile._glance_off` was written to avoid
			# and the one this whole mechanism could quietly reintroduce.
			if not near.take_embedded_spears().is_empty():
				after.append("the Gub is still holding one on its list")
			if after.is_empty():
				print("combat_range: the corpse took the shaft off the body it was standing in — adopt PASS")
			else:
				_embed_failures += 1
				print("combat_range: adopt FAIL (%s)" % "; ".join(after))
			_embed_finish()


func _embed_finish() -> void:
	print("combat_range: %d embed verdict(s) failed" % _embed_failures)
	get_tree().quit()


## Two hurt dummies and nothing else happening, for a picture of the plates:
##
##     ... --resolution 1600x900 --script tools/snapshot.gd -- ##         res://tools/combat_range.tscn out/health_plates.png 40 hurt
##
## Through `report_damage` rather than by writing the field, so what is
## photographed is the whole path — host, broadcast, `Gub.set_health`, plate —
## and not a bar this file filled in by hand.
func _drive_hurt() -> void:
	if _frames != 12:
		return
	var hurt := [38.0, 82.0]
	for i in hurt.size():
		var dummy := MatchState.gubs.get(DUMMY_BASE + i) as Gub
		if dummy == null:
			continue
		_hit(dummy, hurt[i])
		print("combat_range: %s is on %.0f of %.0f"
			% [dummy.display_name, dummy.health, Gub.MAX_HEALTH])


## Say what the Gub is holding, so a run means something without opening the
## PNG. The two halves that must agree are printed together on purpose: a hold
## with a spear still in the hand is the bug this mode exists to catch.
func _report_letter(combat: GubCombat) -> void:
	if _frames != 60:
		return
	var player := MatchState.gubs.get(1) as Gub
	var hand := player.held_gear if is_instance_valid(player) else null
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
	var hand := player.held_gear
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
func _drive_desync(combat: GubCombat, hand: HeldGear) -> void:
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


# ----------------------------------------------------------------- release ---

## One throw, and the three numbers that say the spear and the arm agree.
##
## Deliberately not a picture. Every other spear mode here ends in a PNG of
## something that either happened or did not; this one ends in a duration, and
## the whole of D-025 is that the duration is the thing that was wrong. It is
## also the only check anywhere that reads the *animation* rather than the
## constant derived from it: `_hand_reach` walks the built skeleton, so a window
## edited in `gub_animator.gd` without `THROW_RELEASE_TIME` following it lands
## the shaft somewhere the hand is not, and says so.
func _drive_release(player: Gub, combat: GubCombat) -> void:
	var hand := player.held_gear
	if hand == null:
		return
	if _release_clicked == 0:
		# Same twenty frames of settling every other mode takes, and the same
		# reason: the rig has to have found the target and the spawn-frame
		# transforms have to have been published.
		if _frames < 20 or not combat.has_spear() or not hand.is_carried():
			return
		_release_clicked = _frames
		_release_clicked_ms = Time.get_ticks_msec()
		_acted = true
		combat.try_throw_spear()
		return

	var reach := _hand_reach(player)
	if _trace:
		print("  f%d (+%d) hand %.3f m in front of the hips"
			% [_frames, _frames - _release_clicked, reach])
	if reach > _release_reach:
		_release_reach = reach
		_release_reach_at = _frames

	if _release_spear_at == 0:
		if _frames - _release_clicked < RELEASE_PATIENCE:
			return
	elif _frames - _release_spear_at < RELEASE_SETTLE:
		return
	_report_release()
	get_tree().quit()


## How far in front of the hips the throwing hand is, in metres.
##
## Off the skeleton's own pose and projected onto the Gub's facing, which is the
## same quantity `tools/hand_track.gd` prints and `tools/build_gub.py` reports
## as "furthest forward" — so the frame this peaks on is the frame
## `GubAnimator.THROW_RELEASE_IN_CLIP` was cut from, arrived at from a different
## direction. Global rather than skeleton-local on purpose: which skeleton axis
## points forward is a fact about how the GLB was exported, and `facing()` is a
## fact about the game.
func _hand_reach(player: Gub) -> float:
	if _release_skeleton == null:
		_release_skeleton = player.find_child("Skeleton3D", true, false) as Skeleton3D
		if _release_skeleton == null:
			return -INF
		_release_hand_bone = _release_skeleton.find_bone("RightHand")
		_release_hips_bone = _release_skeleton.find_bone("Hips")
	if _release_hand_bone < 0 or _release_hips_bone < 0:
		return -INF
	var arm := _release_skeleton.get_bone_global_pose(_release_hand_bone).origin
	var pelvis := _release_skeleton.get_bone_global_pose(_release_hips_bone).origin
	return (_release_skeleton.global_transform.basis * (arm - pelvis)).dot(player.facing())


## One bolt, and the three numbers that say the Elder's hand and its lightning
## agree (D-064).
##
## It is `release` with the weapon swapped, deliberately written next to it and
## deliberately *not* merged with it, because the two modes disagree about the
## only interesting line in either: what "the arm has got there" means. On the
## throw it is a maximum — the hand is furthest in front of the hips at the
## release and on its way back a frame later — and on the cast it is a stop,
## with the hand held out in front for a third of a second afterwards and the
## hip-relative maximum arriving during the recovery, 0.35 s of clip too late.
## One function with a flag in it would have had to carry both rules anyway, and
## the flag is the thing that would rot.
func _drive_cast(player: Gub, combat: GubCombat) -> void:
	if _cast_clicked == 0:
		# The robe is put on by hand rather than dropped and walked over: what
		# this mode is about is one tick of one animation, and `lightning` is
		# the mode that proves the whole loot path.
		if _frames == 12:
			MatchState._make_elder(1)
			return
		# The same twenty frames of settling every other mode takes.
		if _frames < 20 or not combat.has_lightning():
			return
		_cast_clicked = _frames
		_cast_clicked_ms = Time.get_ticks_msec()
		_acted = true
		# Through the ordinary click, not through `try_cast_lightning`: the
		# branch from one to the other is part of what is being checked (D-038).
		combat.try_throw_spear()
		return

	var reach := _hand_reach(player)
	if _trace:
		print("  f%d (+%d) hand %.3f m in front of the hips"
			% [_frames, _frames - _cast_clicked, reach])
	if reach > _cast_reach:
		_cast_reach = reach
		_cast_reach_at = _frames
	# The release this clip actually has: the tick the hand stops going forward,
	# latched at the **first** stop and not at the last.
	#
	# That is not a tidying-up, it is the measurement. Composed in the game the
	# arm cocks back to -0.03 m, whips out to 0.39 m, and then — after the bolt
	# has gone — dips 0.05 m and goes out again to 0.47 m as the clip's recovery
	# unwinds a body whose hips and lower spine the mask never applied. So "the
	# last tick that advanced" is eight ticks past the bolt and is the recovery,
	# which is the same trap in the composed pose that `CAST_RELEASE_IN_CLIP`
	# documents in the clip. The first stop after a real advance is the end of
	# the whip, and it is the one the eye reads.
	#
	# "A real advance" is what CAST_ADVANCE_MIN is for: the whip covers 0.43 m
	# and the largest wobble anywhere else in the window is the 0.05 m dip, so a
	# tenth of a metre is clear of one and nowhere near the other. Without it the
	# very first sample counts as a rise and the first dip after it latches, and
	# this mode measures the wind-up instead of the cast.
	if not _cast_stopped and _cast_last_reach > -INF:
		if reach > _cast_last_reach + CAST_ADVANCE_EPSILON:
			_cast_stopped_at = _frames
			_cast_advanced = reach - _cast_low >= CAST_ADVANCE_MIN
		elif _cast_advanced:
			_cast_stopped = true
	_cast_low = minf(_cast_low, reach)
	_cast_last_reach = reach

	if _cast_bolt_at == 0:
		if _frames - _cast_clicked < CAST_PATIENCE:
			return
	elif _frames - _cast_bolt_at < CAST_SETTLE:
		return
	_report_cast()
	get_tree().quit()


## The bow, end to end and in numbers (D-065).
##
## Three verdicts out of one run, and the order is the order each one is the
## control for the last. `letter` first, because a refusal is the cheapest thing
## to get wrong and the easiest to not notice; then the two shots, which are the
## two *ends* of the charge and not a sample of it — a snap shot let go on the
## frame after the key went down, and a full draw held past `bow_draw_time`.
##
## Each shot is measured three ways and none of them asks the arrow what it
## thinks it is doing. The damage is what the victim actually lost; the speed
## and the drop are **fitted off the arrow's own positions**, six ticks of them,
## and compared against `ArrowProjectile`'s statics at the charge the arrow
## reports it left at. So a curve that quietly went linear, a drop that stopped
## interpolating, or a charge the host clamped to nothing all fail here, and
## they fail with the number they produced printed beside the number they owed.
func _drive_bow(player: Gub, combat: GubCombat) -> void:
	var dummy := MatchState.gubs.get(DUMMY_BASE) as Gub
	if dummy == null:
		return
	var elapsed := _frames - _bow_at

	match _bow_step:
		0:  # settle, as every other mode does, for the rig and the transforms
			if _frames >= 20:
				_bow_next(1)
		1:  # a card in the hand the arrow would be drawn with (D-035)
			MatchState._letter_holds[1] = {"letter": 1, "ends_at": INF}
			MatchState.letter_hold_changed.emit(1)
			_bow_next(2)
		2:
			if elapsed < 4:
				return
			combat.try_draw_bow()
			var refused := not player.is_drawing() and not combat.is_winding_up()
			var disarmed := player.held_gear != null and not player.held_gear.has_bow()
			if refused and disarmed:
				print("combat_range: a letter hold refused the draw and emptied the bow hand — letter PASS")
			else:
				_bow_fail("letter", "the draw was %s and the bow hand was %s"
					% ["refused" if refused else "allowed",
						"empty" if disarmed else "still holding a bow"])
			MatchState._letter_holds.erase(1)
			MatchState.letter_hold_changed.emit(1)
			_bow_next(3)
		3:  # the snap shot: a target close enough that 0.6 m of drop still lands
			if elapsed < 4 or not combat.has_bow():
				return
			dummy.revive_at(_facing(BOW_SNAP_SPOT, PLAYER_SPOT))
			_stand_still(dummy)
			_bow_next(4)
		4:
			if elapsed < 20:
				return
			_bow_health = dummy.health
			combat.try_draw_bow()
			_bow_next(5)
		5:  # let go on the very next frame — one tick of `bow_draw_time`
			combat.release_draw()
			_bow_next(6)
		6:
			if not _bow_collect(dummy):
				return
			_report_bow_shot("snap", dummy, 0.0, BOW_SNAP_MAX)
			_bow_next(7)
		7:  # the full draw, at the range the spear modes use
			if not combat.has_bow():
				return
			dummy.revive_at(_facing(BOW_FULL_SPOT, PLAYER_SPOT))
			_stand_still(dummy)
			_bow_arrow = null
			_bow_samples.clear()
			_bow_next(8)
		8:
			if elapsed < 20:
				return
			_bow_health = dummy.health
			combat.try_draw_bow()
			_bow_next(9)
		9:  # held until the charge says it is full, not until a frame count does
			if player.draw_fraction() < 1.0:
				return
			combat.release_draw()
			_bow_next(10)
		10:
			if not _bow_collect(dummy):
				return
			_report_bow_shot("full", dummy, BOW_FULL_MIN, 1.0)
			if _bow_failures == 0:
				print("combat_range: bow PASS")
			get_tree().quit()


func _bow_next(step: int) -> void:
	_bow_step = step
	_bow_at = _frames


## Gather the arrow's flight and wait for it to land. True when there is
## something to report, whether that is a hit or a timeout.
func _bow_collect(dummy: Gub) -> bool:
	if _bow_arrow != null and is_instance_valid(_bow_arrow) \
			and not _bow_arrow.is_stuck() \
			and _bow_samples.size() < BOW_FLIGHT_SAMPLES:
		_bow_samples.append(_bow_arrow.global_position)
	if dummy.health < _bow_health:
		return true
	return _frames - _bow_at > BOW_HIT_LIMIT


## Speed, drop and flat band, fitted off the positions this mode collected.
##
## Deliberately not read out of the projectile. `ArrowProjectile` holds the two
## numbers it was launched with, and asking it for them would be asserting an
## assignment against itself; what has to be true is that the *flight* those
## numbers produce is the flight the dials describe.
##
## The arithmetic is a body under constant acceleration, so it is exact and not
## a regression: consecutive positions give velocities, consecutive velocities
## give the drop, and the launch speed is the horizontal component (which never
## changes) squared up with the vertical one extrapolated back half a tick to
## the instant of the launch. That half tick is the only approximation in it and
## is why `BOW_SPEED_TOLERANCE` is three per cent rather than nothing.
func _fit_flight() -> Dictionary:
	if _bow_samples.size() < 3:
		return {}
	var dt := get_physics_process_delta_time()
	var horizontal := 0.0
	var vy: Array[float] = []
	for i in range(1, _bow_samples.size()):
		var step: Vector3 = (_bow_samples[i] - _bow_samples[i - 1]) / dt
		horizontal += Vector2(step.x, step.z).length()
		vy.append(step.y)
	horizontal /= float(_bow_samples.size() - 1)
	var drop := 0.0
	for i in range(1, vy.size()):
		drop += (vy[i - 1] - vy[i]) / dt
	drop /= float(maxi(vy.size() - 1, 1))
	var speed := Vector2(horizontal, vy[0] + drop * dt * 0.5).length()
	return {"speed": speed, "drop": drop, "band": GubCombat.flat_band(speed, drop)}


func _report_bow_shot(label: String, dummy: Gub, low: float, high: float) -> void:
	if _bow_arrow == null:
		_bow_fail(label, "no arrow was ever loosed")
		return
	var charge: float = _bow_arrow.charge
	var taken := _bow_health - dummy.health
	var owed := ArrowProjectile.damage_for(charge, Net.config)
	var flight := _fit_flight()
	var fails: Array[String] = []
	if charge < low or charge > high:
		fails.append("the arrow left at %.3f of a draw, wanted %.2f-%.2f"
			% [charge, low, high])
	if taken <= 0.0:
		fails.append("the arrow hit nobody")
	elif absf(taken - owed) > BOW_DAMAGE_TOLERANCE:
		fails.append("it took %.1f where %.1f was owed at that draw" % [taken, owed])
	if flight.is_empty():
		fails.append("the arrow was never in the air long enough to measure")
	else:
		var speed: float = flight["speed"]
		var drop: float = flight["drop"]
		var want_speed := ArrowProjectile.speed_for(charge, Net.config)
		var want_drop := ArrowProjectile.drop_for(charge, Net.config)
		if absf(speed - want_speed) > want_speed * BOW_SPEED_TOLERANCE:
			fails.append("it flew at %.1f m/s where the dial says %.1f"
				% [speed, want_speed])
		if absf(drop - want_drop) > want_drop * BOW_DROP_TOLERANCE:
			fails.append("it fell at %.1f m/s² where the dial says %.1f"
				% [drop, want_drop])
	if fails.is_empty():
		print("combat_range: %s shot at %.0f%% draw took %.0f, flew %.1f m/s falling %.1f m/s² (flat to %.0f m) — %s PASS"
			% [label, charge * 100.0, taken, flight["speed"], flight["drop"],
				flight["band"], label])
		return
	_bow_fail(label, "; ".join(fails))


func _bow_fail(label: String, why: String) -> void:
	_bow_failures += 1
	print("combat_range: %s FAIL — %s" % [label, why])


## The charge as a **tell**, on a Gub nobody is driving (D-065).
##
## This is the half of the bow that `bow` cannot reach. Everything that makes
## the draw a number works on the local Gub by construction — the client that is
## holding the key computes the charge and hands it to its own animator — and
## none of that says a word about the seven Gubs whose charge has to arrive over
## a wire. D-025's rule is that a tell only the attacker can see is not a tell,
## and the only way to check that here is to have a remote Gub in the room.
##
## The dummy is exactly that: a roster entry with no client behind it, so the
## mode *is* its client, and all it publishes is `sync_draw` — the one float the
## real thing would have sent. If the pose arrives, it arrives because that
## float is enough.
##
## What is compared is the **draw length**: the distance from the bow fist to
## the drawing fist. Not the hand's position relative to the hips, which was the
## first attempt and is the wrong quantity — everything below `Spine1` comes
## from the locomotion underneath (D-029), so two Gubs a few frames out of phase
## in the same idle cycle disagree about it without disagreeing about the draw.
## The distance between two bones the layer fully owns is the thing the eye
## actually reads, and it is invariant to every part of this that is not the bow.
func _drive_draw(player: Gub, combat: GubCombat) -> void:
	var dummy := MatchState.gubs.get(DUMMY_BASE) as Gub
	if dummy == null:
		return
	if _draw_step == 0:
		if _frames < 20:
			return
		# Beside the player rather than down the range, because this mode's
		# picture is the two of them together: the Gub you are driving and the
		# Gub you are watching, at the same charge, from the same float.
		dummy.revive_at(_facing(DRAW_DUMMY_SPOT, DRAW_DUMMY_SPOT + Vector3(0.0, 0.0, -10.0)))
		_stand_still(dummy)
		combat.try_draw_bow()
		_draw_step = 1
		_draw_at = _frames
		return

	# The dummy's imaginary client, publishing once a frame. Nothing else about
	# this Gub is ever written: if the pose appears, one float is what did it.
	dummy.sync_draw = player.draw_fraction()

	if _draw_step > DRAW_LEVELS.size():
		return
	var level: float = DRAW_LEVELS[_draw_step - 1]
	if player.draw_fraction() < level or _frames - _draw_at < DRAW_SETTLE:
		return
	_draw_rows.append({
		"charge": player.draw_fraction(),
		"local": _draw_length(player),
		"remote": _draw_length(dummy),
		"aim": _aim_offset(player),
	})
	_draw_step += 1
	if _draw_step <= DRAW_LEVELS.size():
		return
	combat.release_draw()
	_report_draw()
	get_tree().quit()


## How far this Gub's string is back, in metres of skeleton: the gap between the
## two fists. Both bones are above `Spine1` and so both are entirely the draw
## layer's, which is what makes this the one reading that says something about
## the bow and nothing about the legs.
func _draw_length(gub: Gub) -> float:
	var skeleton := gub.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return -1.0
	var left := skeleton.find_bone(HeldGear.BOW_HAND_BONE)
	var right := skeleton.find_bone(HeldGear.HAND_BONE)
	if left < 0 or right < 0:
		return -1.0
	return skeleton.get_bone_global_pose(left).origin.distance_to(
		skeleton.get_bone_global_pose(right).origin)


## Where the composed bow is actually pointing, in degrees off the Gub's own
## facing.
##
## Printed rather than asserted, and it is the number to read if the bow ever
## looks like it is aiming at the wrong thing. A masked layer keeps the clip's
## rotations from `Spine1` up and throws away everything the pelvis was doing
## (D-029), and an archer's stance is most of a right angle between those two
## halves — so how much of that right angle survives into the game is a fact
## about which bones are in `UPPER_BODY_BONES`, not about the clip. D-064
## measured the same thing for the Elder's cast and found the layer had thrown
## away the 106° the pelvis turned through.
##
## It does not decide where an arrow goes. That is read from the camera at the
## release and has never come from the body (D-025, D-045).
func _aim_offset(gub: Gub) -> float:
	var hands := _hand_attachments(gub)
	if hands.is_empty():
		return 0.0
	var along: Vector3 = hands[0].global_position - hands[1].global_position
	var flat := Vector3(along.x, 0.0, along.z)
	if flat.length_squared() < 0.0001:
		return 0.0
	return rad_to_deg(flat.normalized().signed_angle_to(gub.facing(), Vector3.UP))


## The two `BoneAttachment3D`s `HeldGear` hangs the bow and the arrow off, bow
## hand first — or an empty array on a Gub that has not been given gear.
##
## **Read off the attachments and not off `Skeleton3D.get_bone_global_pose`**,
## which is the thing D-066 had to find out the hard way. A `SkeletonModifier3D`
## writes into the pose the skin is built from and the skeleton then restores
## the animation's own pose behind it, so that the next frame starts clean —
## which means a bone pose read from `_physics_process` is the pose *before*
## `GubAim` turned the torso, every time, and a check reading it would have gone
## on reporting 91° at a Gub whose bow was pointing straight down the range.
## `BoneAttachment3D` updates off `skeleton_updated`, which fires after the
## modifier stack, so these two nodes are where the props actually are — which
## is also the only thing a player can see.
func _hand_attachments(gub: Gub) -> Array[Node3D]:
	var skeleton := gub.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return []
	var bow := skeleton.get_node_or_null("BowHand") as Node3D
	var draw_hand := skeleton.get_node_or_null("SpearHand") as Node3D
	if bow == null or draw_hand == null:
		return []
	return [bow, draw_hand]


## Whether `gub.tscn` actually puts a field on the wire.
##
## Off the live node rather than off the file, because what matters is what the
## synchroniser was handed — a property list edited in the scene and a
## synchroniser pointed at a different `SceneReplicationConfig` are two
## different bugs and only this catches both.
func _replicates(field: String) -> bool:
	var gub := MatchState.gubs.get(1) as Gub
	if gub == null:
		return false
	var sync := gub.get_node_or_null("Sync") as MultiplayerSynchronizer
	if sync == null or sync.replication_config == null:
		return false
	for path: NodePath in sync.replication_config.get_properties():
		if String(path).ends_with(":" + field):
			return true
	return false


# ------------------------------------------------- the feet, in eight ways ---

## The foot skate, measured round the compass at three gaits (D-066).
##
## The whole fault this step exists to remove is a clip whose feet are drawn
## travelling one way being played on a body travelling another, and the honest
## measurement of it is not an angle or a speed ratio — it is **how fast the
## foot that is on the ground is sliding along it**. So that is what this takes:
## every tick, both toes in world space, and the slower of the two, which is the
## planted one at every moment of a cycle except the instant they swap.
##
## No plant threshold is in that number, on purpose. A threshold is a place for
## the measurement to disagree with itself when one clip lifts its feet higher
## than another does, and `min(left, right)` needs none — a foot in the air is
## always the faster of the two. The threshold that does exist,
## `STRAFE_PLANT_HEIGHT`, only decorates the report with how much of each leg
## had a foot actually down.
##
## The Gub is held facing one way with `set_view_basis(..., true, ...)`, which
## is the same flag the camera raises while somebody is aiming — so this is not
## an artificial pose, it is the pose this whole weapon set is used in.
func _drive_strafe() -> void:
	var player := MatchState.gubs.get(1) as Gub
	if player == null:
		return
	var rig := player.get_node_or_null("CameraRig")
	if rig != null:
		rig.process_mode = Node.PROCESS_MODE_DISABLED
	player.reads_local_input = false
	# Facing -Z, held there. `face_view` is the aiming flag, so the body does
	# not turn to follow its own velocity and every leg is a genuine strafe.
	player.set_view_basis(Basis.IDENTITY, true, 0.0)

	if _strafe_leg >= STRAFE_GAITS.size() * STRAFE_COMPASS.size():
		_report_strafe()
		get_tree().quit()
		return

	var gait: Array = STRAFE_GAITS[_strafe_leg / STRAFE_COMPASS.size()]
	var heading: Array = STRAFE_COMPASS[_strafe_leg % STRAFE_COMPASS.size()]

	# A flag and not `elapsed == 0`, which is a tick this function is never
	# called on: `_strafe_at` is set to `_frames` as a leg *ends*, and the next
	# call is already a tick later. Written the other way this mode ran every
	# leg from wherever the last one left off, with one set of samples growing
	# across all twenty-four of them — which reads as a body that never reaches
	# its own speed and a foot that slides a little more each leg.
	if not _strafe_open:
		# Back to the middle for every leg, so none inherits the last one's
		# momentum and none of them walks off the floor.
		player.revive_at(Transform3D(Basis.IDENTITY, PLAYER_SPOT))
		_strafe_skate.clear()
		_strafe_speed.clear()
		_strafe_toes.clear()
		_strafe_planted = 0
		_strafe_open = true
		_strafe_at = _frames
	var elapsed := _frames - _strafe_at
	player.input_direction = heading[1]
	player.wants_sprint = gait[1]
	player.wants_crouch = gait[2]

	if elapsed >= STRAFE_SETTLE:
		_sample_strafe(player)
	if elapsed < STRAFE_SETTLE + STRAFE_SAMPLE:
		return

	var speed := 0.0
	for v in _strafe_speed:
		speed += v
	speed /= maxf(float(_strafe_speed.size()), 1.0)
	var skate := 0.0
	var worst := 0.0
	for v in _strafe_skate:
		skate += v
		worst = maxf(worst, v)
	skate /= maxf(float(_strafe_skate.size()), 1.0)
	_strafe_rows.append({
		"gait": gait[0], "heading": heading[0], "speed": speed,
		"skate": skate, "worst": worst,
		"planted": float(_strafe_planted) / maxf(float(_strafe_skate.size()), 1.0),
	})
	_strafe_leg += 1
	_strafe_open = false


## One tick of one leg: both toes in world space, and the slower of the two.
##
## The toes are read off `get_bone_global_pose`, which on a Gub that is not
## drawing is the whole pose — `GubAim` is the only modifier on this skeleton
## and its weight is zero unless a bow is up. (If that ever stops being true,
## this has to move to the attachments the way `_aim_offset` did.)
func _sample_strafe(player: Gub) -> void:
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var here: Array[Vector3] = []
	for bone in ["LeftToeBase", "RightToeBase"]:
		var index := skeleton.find_bone(bone)
		if index < 0:
			return
		here.append(skeleton.global_transform
			* skeleton.get_bone_global_pose(index).origin)
	if _strafe_toes.size() == here.size():
		var dt := get_physics_process_delta_time()
		var slid := INF
		for i in here.size():
			var step: Vector3 = here[i] - _strafe_toes[i]
			slid = minf(slid, Vector2(step.x, step.z).length() / dt)
		_strafe_skate.append(slid)
		_strafe_speed.append(Vector2(player.velocity.x, player.velocity.z).length())
		var lowest := minf(here[0].y, here[1].y) - player.global_position.y
		if lowest <= STRAFE_PLANT_HEIGHT:
			_strafe_planted += 1
	_strafe_toes = here


func _report_strafe() -> void:
	print("  gait    heading      body speed   planted foot slides    worst   "
		+ "fraction   foot down")
	var worst_straight := 0.0
	var straight_where := ""
	var worst_any := 0.0
	var any_where := ""
	var crouch_best := INF
	var crouch_worst := 0.0
	for row: Dictionary in _strafe_rows:
		var speed: float = row["speed"]
		var ratio: float = float(row["skate"]) / maxf(speed, 0.01)
		print("  %-7s %-12s %6.2f m/s   %10.2f m/s %9.2f   %8.2f   %8.0f%%"
			% [row["gait"], row["heading"], speed, row["skate"], row["worst"],
				ratio, float(row["planted"]) * 100.0])
		if row["gait"] == "crouch":
			crouch_best = minf(crouch_best, ratio)
			crouch_worst = maxf(crouch_worst, ratio)
			continue
		var where := "%s %s" % [row["gait"], row["heading"]]
		if ratio > worst_any:
			worst_any = ratio
			any_where = where
		if row["heading"] == "forward" or row["heading"] == "back":
			if ratio > worst_straight:
				worst_straight = ratio
				straight_where = where

	var legs := STRAFE_GAITS.size() * STRAFE_COMPASS.size()
	if _strafe_rows.size() < legs:
		_strafe_fail("straight", "only %d of %d legs were walked"
			% [_strafe_rows.size(), legs])
		return

	# The four bearings with a clip of their own. Before this step the two
	# backward ones were 0.83 and 1.03 — a forward run cycle played on a body
	# going the other way — and they are what this line exists to hold down.
	if worst_straight <= STRAFE_STRAIGHT_LIMIT:
		print("combat_range: forward and backward plant at %.2f of body speed or better (%s) — straight PASS"
			% [worst_straight, straight_where])
	else:
		_strafe_fail("straight", "%s slid %.2f of its own speed, past the %.2f limit"
			% [straight_where, worst_straight, STRAFE_STRAIGHT_LIMIT])

	if worst_any <= STRAFE_LIMIT:
		print("combat_range: sixteen legs round the compass, worst %.2f of body speed (%s) — compass PASS"
			% [worst_any, any_where])
	else:
		_strafe_fail("compass", "%s slid %.2f of its own speed, past the %.2f limit"
			% [any_where, worst_any, STRAFE_LIMIT])

	# The control, and it is one that has to come out *badly*. A crouching Gub
	# is still on one clip behind a one-dimensional space, which is what every
	# direction was before this step; if its bearings do not disagree with each
	# other then this measurement cannot see a skate at all and the sixteen
	# lines above mean nothing (D-039).
	if crouch_worst > crouch_best * STRAFE_CONTROL_SPREAD:
		print("combat_range: the crouch's one clip still spreads %.2f to %.2f across the compass — crouch PASS"
			% [crouch_best, crouch_worst])
	else:
		_strafe_fail("crouch", "the one-clip control spread only %.2f to %.2f, "
			% [crouch_best, crouch_worst]
			+ "so this measurement would not have noticed the fault it is here for")

	if _strafe_failures == 0:
		print("combat_range: strafe PASS")


func _strafe_fail(label: String, why: String) -> void:
	_strafe_failures += 1
	print("combat_range: %s FAIL — %s" % [label, why])


# ------------------------------------------------------------ the pictures ---

## Eight Gubs in a row, each running a different way while facing the camera,
## and five holding a full draw at five different pitches (D-066).
##
## These are the two frames the user judges this step by, and both of them are
## built out of **replicated fields on dummies** rather than by driving one Gub
## and photographing it eight times. That is not a shortcut, it is the sharper
## version of the check: a dummy is a roster entry with no client behind it, so
## the only things these modes write are the handful of `sync_*` floats a real
## client would have sent. If the poses appear, they appear for the reason they
## have to appear on somebody else's screen (D-025, D-065).
func _drive_lineup(rows: Array) -> void:
	# The Gub this testbed normally drives stands in the middle of the range and
	# has nothing to do with either row, so it is simply not in the picture.
	# Hidden rather than moved: the floor ends not far behind the camera, and a
	# subject walked off it to get out of shot is a subject falling into the
	# void through the whole exposure.
	var player := MatchState.gubs.get(1) as Gub
	if player != null:
		player.visible = false
	for i in rows.size():
		var dummy := MatchState.gubs.get(DUMMY_BASE + i) as Gub
		if dummy == null:
			continue
		var row: Dictionary = rows[i]
		var spot: Vector3 = row["spot"]
		dummy.sync_position = spot
		dummy.sync_yaw = Gub.yaw_towards(row["look"] as Vector3)
		dummy.sync_grounded = true
		dummy.sync_crouching = false
		dummy.sync_sliding = false
		dummy.sync_velocity = row["velocity"]
		dummy.sync_draw = row["draw"]
		dummy.sync_aim_pitch = row["pitch"]
		if _frames < 4:
			dummy.revive_at(Transform3D(Basis(Vector3.UP, dummy.sync_yaw), spot))


## The strafing row: the eight compass bearings, every Gub facing the camera, so
## what a column shows is one direction's cycle and what the row shows is how
## differently the plane poses them.
func _strafing_rows() -> Array:
	var rows: Array = []
	for i in STRAFE_COMPASS.size():
		var heading: Vector2 = STRAFE_COMPASS[i][1]
		var spot := LINEUP_FIRST + Vector3(LINEUP_STEP * float(i), 0.0, 0.0)
		# Facing the camera, which is down +Z here, so the row is read the way
		# the keys are: a Gub strafing to *its* left moves to the viewer's right.
		var look := Vector3.BACK
		var forward := -look
		var right := Vector3(-forward.z, 0.0, forward.x)
		var wish := (right * heading.x + forward * -heading.y).normalized()
		rows.append({
			"spot": spot, "look": look, "velocity": wish * Gub.RUN_SPEED,
			"draw": -1.0, "pitch": 0.0,
		})
	return rows


## The aiming row: five full draws at five pitches, every Gub side-on, because
## the whole subject is how far the torso has tipped and a Gub photographed
## head-on has tipped by nothing at all.
func _aiming_rows() -> Array:
	var rows: Array = []
	for i in AIM_LINEUP_PITCHES.size():
		var spot := AIM_LINEUP_FIRST + Vector3(AIM_LINEUP_STEP * float(i), 0.0, 0.0)
		rows.append({
			"spot": spot, "look": Vector3.RIGHT, "velocity": Vector3.ZERO,
			"draw": 1.0, "pitch": AIM_LINEUP_PITCHES[i],
		})
	return rows

# --------------------------------------------------------- the torso, swept --

## The spine that aims, swept through everything a player can point it at
## (D-066).
##
## A full draw is held for the whole of this while the view is walked round the
## horizon and then from `PITCH_MIN` to `PITCH_MAX`. Three things come out of
## it, and the third is the one that had to be asserted rather than believed.
func _drive_spine() -> void:
	var player := MatchState.gubs.get(1) as Gub
	if player == null:
		return
	var rig := player.get_node_or_null("CameraRig") as GubCamera
	var combat := player.get_node_or_null("Combat") as GubCombat
	if rig == null or combat == null:
		return
	player.reads_local_input = false
	player.input_direction = Vector2.ZERO
	var elapsed := _frames - _spine_at
	var samples := SPINE_YAWS + SPINE_PITCHES

	match _spine_step:
		0:  # settle, then draw and hold
			if _frames < 20:
				return
			combat.try_draw_bow()
			_spine_next(1)
		1:  # held until the charge says it is full, not until a frame count does
			if player.draw_fraction() < 1.0:
				return
			_spine_next(2)
		2:  # the sweep
			var pitch := 0.0
			var yaw := 0.0
			if _spine_sample < SPINE_YAWS:
				# Round the horizon at a level view. The body follows, because a
				# drawing Gub faces its own crosshair (`_face_view`), so this is
				# also a test that the correction is a *body-relative* rotation
				# and not a world-space one that happens to work at yaw zero.
				yaw = TAU * float(_spine_sample) / float(SPINE_YAWS)
			else:
				var step := _spine_sample - SPINE_YAWS
				pitch = lerpf(GubCamera.PITCH_MIN, GubCamera.PITCH_MAX,
					float(step) / float(SPINE_PITCHES - 1))
			rig.set_view(yaw, pitch)
			if elapsed < SPINE_SETTLE:
				return
			_spine_rows.append({
				"yaw": yaw, "pitch": pitch,
				"level": _spine_sample < SPINE_YAWS,
				"bow": _aim_offset(player),
				"elevation": _bow_elevation(player),
				"apart": _bow_off_crosshair(player, rig),
			})
			_spine_sample += 1
			_spine_at = _frames
			if _spine_sample >= samples:
				_report_spine_sweep()
				rig.set_view(0.0, GubCamera.PITCH_MIN)
				_spine_next(3)
		3:  # the first of two shots, at the bottom of the pitch range
			if elapsed < SPINE_SETTLE:
				return
			combat.release_draw()
			_spine_next(4)
		4:  # **the view is not touched until that arrow is out.**
			#
			# The aim is read at the *release* and the release is a tick after
			# the key comes up (D-025), so a mode that swung the camera to the
			# other end of the sweep on the frame it let go would have both its
			# shots aimed by the second view — which is exactly what happened,
			# and what it looked like was a release point that never moved for
			# a reason that had nothing to do with the spine.
			if _spine_shots.is_empty() and elapsed < SPINE_PATIENCE:
				return
			rig.set_view(0.0, GubCamera.PITCH_MAX)
			_spine_next(5)
		5:  # let the bow come back, then draw again at the top of the range
			rig.set_view(0.0, GubCamera.PITCH_MAX)
			# Asked every tick until it takes, which is what a player holding
			# the key does. One call on the frame `has_bow` first says yes is a
			# frame earlier than the draw's own gate opens — the client spends
			# `BOW_RELEASE_TIME` *plus* the recharge and the bow reappears on
			# the first of the two — so a single attempt is refused and the
			# second shot silently never happens.
			if not combat.has_bow():
				return
			combat.try_draw_bow()
			if not player.is_drawing():
				return
			_spine_next(6)
		6:
			if player.draw_fraction() < 1.0 or elapsed < SPINE_SETTLE:
				return
			combat.release_draw()
			_spine_next(7)
		7:
			if _spine_shots.size() < 2 and elapsed < SPINE_PATIENCE:
				return
			_report_spine_release()
			if _spine_failures == 0:
				print("combat_range: spine PASS")
			get_tree().quit()


func _spine_next(step: int) -> void:
	_spine_step = step
	_spine_at = _frames


## How far above the horizon the composed bow is pointing, in degrees. The same
## line `_aim_offset` measures the bearing of — the two fists, off the
## attachments the props actually hang from — asked about its rise instead.
func _bow_elevation(gub: Gub) -> float:
	var hands := _hand_attachments(gub)
	if hands.is_empty():
		return 0.0
	var along: Vector3 = hands[0].global_position - hands[1].global_position
	if along.length_squared() < 0.0001:
		return 0.0
	return rad_to_deg(asin(clampf(along.normalized().y, -1.0, 1.0)))


## The angle between the composed bow and the crosshair, in degrees, in three
## dimensions — the one form of the question that is as well conditioned looking
## at the sky as it is looking at the horizon.
##
## The crosshair's own direction comes from `aim_ray`, which is the *unobstructed*
## camera's (D-045) and is the same vector `GubCombat` reads at the release, so
## this compares the bow against the thing the arrow will actually follow rather
## than against the angles the mode happened to ask for.
func _bow_off_crosshair(gub: Gub, rig: GubCamera) -> float:
	var hands := _hand_attachments(gub)
	if hands.is_empty():
		return 0.0
	var along: Vector3 = hands[0].global_position - hands[1].global_position
	if along.length_squared() < 0.0001:
		return 0.0
	return rad_to_deg(along.angle_to(rig.aim_ray()["direction"] as Vector3))


func _report_spine_sweep() -> void:
	var worst_bearing := 0.0
	var worst_apart := 0.0
	var worst_pitch := 0.0
	var low := INF
	var high := -INF
	print("  view yaw   view pitch   bow bearing   bow elevation   off the crosshair")
	for row: Dictionary in _spine_rows:
		var pitch := rad_to_deg(float(row["pitch"]))
		var elevation: float = row["elevation"]
		if row["level"]:
			worst_bearing = maxf(worst_bearing, absf(float(row["bow"])))
		worst_apart = maxf(worst_apart, float(row["apart"]))
		worst_pitch = maxf(worst_pitch, absf(elevation - pitch))
		low = minf(low, elevation)
		high = maxf(high, elevation)
		print("  %+8.0f   %+10.0f   %+11.0f   %+13.0f   %16.0f"
			% [rad_to_deg(float(row["yaw"])), pitch, float(row["bow"]),
				elevation, float(row["apart"])])

	var fails: Array[String] = []
	if worst_bearing > SPINE_BOW_LIMIT:
		fails.append("the bow's bearing was %.0f deg off the crosshair at its worst"
			% worst_bearing)
	if worst_apart > SPINE_APART_LIMIT:
		fails.append("the bow was %.0f deg off the crosshair in space at its worst"
			% worst_apart)
	if fails.is_empty():
		print("combat_range: the bow held %.0f deg of bearing and %.0f deg in space off the crosshair, against D-065's 91 — bow PASS"
			% [worst_bearing, worst_apart])
	else:
		_spine_fail("bow", "; ".join(fails))

	var span := high - low
	fails = []
	if worst_pitch > SPINE_PITCH_LIMIT:
		fails.append("the bow was %.0f deg off the crosshair's own pitch at its worst"
			% worst_pitch)
	# The control on the same line: a torso that never moved would agree with a
	# level crosshair perfectly and disagree with nothing.
	if span < SPINE_PITCH_SPAN_MIN:
		fails.append("the bow only swung through %.0f deg of elevation, so tracking means nothing"
			% span)
	if fails.is_empty():
		print("combat_range: the bow tracked %.0f deg of elevation, within %.0f of the crosshair — pitch PASS"
			% [span, worst_pitch])
	else:
		_spine_fail("pitch", "; ".join(fails))


## Two arrows, from one spot, at the two ends of the pitch range.
##
## What has to be true is that they left from **the same point** and went two
## different ways: the origin is the body's (position, eye height and yaw, none
## of them on the skeleton) and the direction is the camera's, so a torso that
## turned through 123 degrees between the two shots must have moved the second
## and not the first. That is D-025 and D-045 asserted against the thing most
## likely to break them — a modifier that reaches into the pose the release
## would otherwise be taken from.
func _report_spine_release() -> void:
	if _spine_shots.size() < 2:
		_spine_fail("release", "only %d of 2 arrows were ever loosed"
			% _spine_shots.size())
		return
	var a: Dictionary = _spine_shots[0]
	var b: Dictionary = _spine_shots[1]
	var moved: float = (a["origin"] as Vector3).distance_to(b["origin"])
	var turned := rad_to_deg((a["direction"] as Vector3)
		.angle_to(b["direction"] as Vector3))
	var swept := rad_to_deg(GubCamera.PITCH_MAX - GubCamera.PITCH_MIN)
	var fails: Array[String] = []
	if moved > SPINE_RELEASE_TOLERANCE:
		fails.append("the release point moved %.4f m between them" % moved)
	# The control: if the two shots went the same way, "the origin did not move"
	# is satisfied by a mode that never turned the view at all.
	if turned < swept - 5.0:
		fails.append("the two shots only differ by %.0f deg where the sweep was %.0f"
			% [turned, swept])
	if fails.is_empty():
		print("combat_range: two arrows %.0f deg apart left the same point to within %.4f m — release PASS"
			% [turned, moved])
	else:
		_spine_fail("release", "; ".join(fails))


## Where one arrow started and which way it went, taken once the launch has
## finished writing both. See the deferred call that gets here.
func _note_spine_shot(arrow: ArrowProjectile) -> void:
	if not is_instance_valid(arrow):
		return
	_spine_shots.append({
		"origin": arrow.global_position,
		"direction": -arrow.global_transform.basis.z,
	})


func _spine_fail(label: String, why: String) -> void:
	_spine_failures += 1
	print("combat_range: %s FAIL — %s" % [label, why])


func _report_draw() -> void:
	var worst := 0.0
	var low := INF
	var high := -INF
	for row: Dictionary in _draw_rows:
		var apart: float = absf(float(row["local"]) - float(row["remote"]))
		worst = maxf(worst, apart)
		low = minf(low, float(row["local"]))
		high = maxf(high, float(row["local"]))
		print("  charge %.2f   local %.3f m   remote %.3f m   %.4f m apart   bow %+.0f° off facing"
			% [row["charge"], row["local"], row["remote"], apart, row["aim"]])
	var spread := high - low
	var fails: Array[String] = []
	# The one part of this a testbed cannot reach by playing the game. Every Gub
	# here is in one process on an `OfflineMultiplayerPeer`, so `sync_draw` is
	# read straight off the object and the `MultiplayerSynchronizer` never sees
	# it — which means the rows above would pass just as happily on a build that
	# had forgotten to list the field in `gub.tscn`'s replication config, and
	# the bow's tell would be invisible to every real client and to nothing else.
	# So the list is read and asked directly. It is the same class of omission
	# `MatchConfig._FIELDS` has, one layer down.
	if not _replicates("sync_draw"):
		fails.append("sync_draw is not in gub.tscn's replication config, "
			+ "so nothing about the draw would ever leave this machine")
	if _draw_rows.size() < DRAW_LEVELS.size():
		fails.append("only %d of %d charge levels were reached"
			% [_draw_rows.size(), DRAW_LEVELS.size()])
	if worst > DRAW_TOLERANCE:
		fails.append("the remote Gub was %.3f m out at its worst" % worst)
	# The control, in D-039's sense: two Gubs standing still agree perfectly.
	if spread < DRAW_SPREAD_MIN:
		fails.append("the draw only moved the hands %.3f m, so agreeing means nothing"
			% spread)
	if fails.is_empty():
		print("combat_range: a remote Gub drew the same bow, %.4f m out at worst over %.2f m of pull — draw PASS"
			% [worst, spread])
		return
	print("combat_range: draw FAIL — %s" % "; ".join(fails))


func _report_cast() -> void:
	if _cast_bolt_at == 0:
		print("combat_range: clicked on tick %d and no bolt ever appeared — cast FAIL"
			% _cast_clicked)
		return
	var want := Net.config.lightning_delay
	var got := (_cast_bolt_ms - _cast_clicked_ms) * 0.001
	var frame := 1.0 / 60.0
	var apart := absi(_cast_bolt_at - _cast_stopped_at)
	var failures: Array[String] = []
	if absf(got - want) > frame * 1.5:
		failures.append("the bolt is %.0f ms from the %.0f ms the dial asked for"
			% [got * 1000.0, want * 1000.0])
	if apart > CAST_AGREEMENT:
		failures.append("the hand stopped advancing %d tick(s) from the bolt" % apart)
	# The half of it that is about the pose rather than the timing: a bolt that
	# leaves while the arm is still folded up against the body is the failure
	# this whole step exists to prevent, and it is invisible to every other
	# assertion here. Two thirds of the way out is not a tuned threshold — the
	# clip is at 86% of its own final reach on the frame it stops, and the frame
	# the hand is quickest on, which is the release rule this clip was *not*
	# given, is at 23%.
	if _cast_reach > 0.0 and _cast_reach_out() < 0.66:
		failures.append("the hand was only %.0f%% of the way out when the bolt left"
			% (_cast_reach_out() * 100.0))
	if failures.is_empty():
		print("combat_range: bolt at %.0f ms after the click (dial says %.0f), hand %.0f%% out and stopping %d tick(s) away — cast PASS"
			% [got * 1000.0, want * 1000.0, _cast_reach_out() * 100.0, apart])
		return
	print("combat_range: cast FAIL — %s" % "; ".join(failures))


## How far out the composed arm was when the bolt left, as a fraction of the
## furthest it got in this windup. A fraction rather than a distance because the
## distance is a fact about the robe's proportions and the mask, and what is
## being asked is about the *shape* of the motion.
func _cast_reach_out() -> float:
	if _cast_reach <= 0.0:
		return 0.0
	return clampf(_cast_bolt_reach / _cast_reach, 0.0, 1.0)


func _report_release() -> void:
	if _release_spear_at == 0:
		print("combat_range: clicked on tick %d and no spear ever appeared — release FAIL"
			% _release_clicked)
		return
	var want := GubAnimator.THROW_RELEASE_TIME
	var got := (_release_spear_ms - _release_clicked_ms) * 0.001
	var frame := 1.0 / 60.0
	var drift := absf(got - want)
	var apart := absi(_release_spear_at - _release_reach_at)
	var failures: Array[String] = []
	# A frame and a half, and not zero: the release fires on the first `_process`
	# past a millisecond deadline, so it is always late, by up to a frame.
	# Measured at 4 ms over, every run. Anything wider than this would start to
	# hide a window moved by a whole authored key, which at this clip's rate is
	# one frame of real time.
	if drift > frame * 1.5:
		failures.append("the shaft is %.0f ms from the %.0f ms it was promised"
			% [got * 1000.0, want * 1000.0])
	if _release_fist_full:
		failures.append("the fist still had something in it when the shaft appeared")
	if apart > RELEASE_AGREEMENT:
		failures.append("the arm was furthest forward %d ticks from the throw" % apart)
	if failures.is_empty():
		print("combat_range: shaft at %.0f ms after the click (asked for %.0f), fist empty on the same tick, arm furthest forward (%.3f m) %d tick(s) away — release PASS"
			% [got * 1000.0, want * 1000.0, _release_reach, apart])
		return
	print("combat_range: release FAIL — %s" % "; ".join(failures))


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
		"recharge", "release":
			return RECHARGE_TARGET
		"draw":
			# Straight down the range at nothing, so the aim never wanders onto the
			# Gub whose *pose* is the subject of this mode.
			return ARC_TARGET
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
	# The Elder's ward, counted rather than described: `health` needs to know
	# that a hit worth zero still flashed, and a flash is a node appearing in the
	# world for a third of a second (`MatchState._do_ward`).
	if node is WardFlash:
		_wards += 1
		return
	var item := node as Pickup
	if item != null:
		# What kind of drop this is cannot be read here: `MatchState._spawn_pickup`
		# adds the node and *then* calls `Pickup.drop`, which is what sets `kind`.
		# Deferring to the next idle frame is enough, and being collected in the
		# meantime does not change what it was — which matters, because a drop
		# under a dummy's feet is taken by the very next physics step (D-067).
		_note_pickup.call_deferred(item)
		return
	if node.has_signal("caught"):
		node.connect("caught", func(victim_ids: Array) -> void:
			var names: Array[String] = []
			for id: int in victim_ids:
				names.append(Net.player_name(id))
			print("combat_range: lure caught %d — %s"
				% [victim_ids.size(), ", ".join(names) if names else "nobody"]))
		return
	var bolt := node as LightningBolt
	if bolt != null and _mode == "cast" and _cast_bolt_at == 0:
		# The one instant this mode is about. The bolt is hitscan, so the frame
		# it enters the tree *is* the frame it was fired on — there is no flight
		# to subtract — and the arm is read on the same line, which is what makes
		# "the hand had got there" a measurement rather than a belief.
		_cast_bolt_at = _frames
		_cast_bolt_ms = Time.get_ticks_msec()
		var caster := MatchState.gubs.get(1) as Gub
		_cast_bolt_reach = _hand_reach(caster) if caster != null else -INF
	# Caught before the `SpearProjectile` line below, because an arrow *is* one:
	# `ArrowProjectile` extends it (D-065), so every `as SpearProjectile` in this
	# file would match one. Every such cast here is already mode-gated and no mode
	# fires both weapons, but the one that could go wrong silently is this one, so
	# the arrow is taken out of the stream first.
	var arrow := node as ArrowProjectile
	if arrow != null:
		if _mode == "bow" and _bow_arrow == null:
			_bow_arrow = arrow
		if _mode == "spine":
			# Deferred, and that is the whole of it: `SpearProjectile.begin`
			# calls `add_child` **first** and sets the position and the facing
			# after, so this signal arrives at an arrow that is still at the
			# origin pointing down -Z. Read here, both shots looked identical
			# and "the release point did not move" passed on two zeroes. A
			# deferred call is flushed at the end of this physics frame, by
			# which time `begin` has finished and the arrow has not yet had a
			# `_physics_process` of its own to fly in.
			_note_spine_shot.call_deferred(arrow)
		return
	var spear := node as SpearProjectile
	if spear != null and _mode == "release" and _release_spear_at == 0:
		# Read here and nowhere else, because "the fist empties when the spear
		# leaves" is a statement about one instant and this is that instant.
		# `GubCombat._do_throw_spear` empties the hand and *then* launches the
		# shaft, so a fist still holding something on this line is a hand that
		# is lying about how dangerous its owner is (D-025, `HeldGear`).
		var thrower := MatchState.gubs.get(1) as Gub
		_release_spear_at = _frames
		_release_spear_ms = Time.get_ticks_msec()
		_release_fist_full = (thrower != null and thrower.held_gear != null
			and thrower.held_gear.is_carried())
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


## Where every `bhop` run starts and which way it goes: along +X, on a line clear
## of both blocks and the back wall. A Gub that reaches BHOP_WRAP is moved back
## by twice that, velocity and all, so ten Elder hops fit on a 90 m floor.
const BHOP_START := Vector3(-38.0, 0.1, 25.0)
const BHOP_WRAP := 40.0
const BHOP_SUBJECTS := ["gub", "elder", "carrier"]
const BHOP_HOPS := 10
## Ground ticks a late hop waits before pressing: 0.25 s, well past LANDING_GRACE.
const BHOP_LATE_TICKS := 15
## How far over a speed a verdict tolerates, in m/s. Floats, not a feel margin.
const BHOP_EPSILON := 0.02


## Drive the local Gub through timed hops. See the `bhop` entry in MODES' notes.
##
## This writes `input_direction` and the view basis directly rather than pressing
## keys: the `walk` mode already proves the keyboard is wired, and this one is
## about what the movement code does with a press landing on one exact tick,
## which an `Input.action_press` a frame early or late would blur.
func _drive_bhop() -> void:
	var player := MatchState.gubs.get(1) as Gub
	if player == null:
		return
	var rig := player.get_node_or_null("CameraRig")
	if rig != null:
		rig.process_mode = Node.PROCESS_MODE_DISABLED
	player.reads_local_input = false
	player.set_view_basis(Basis(Vector3.UP, -PI / 2.0), false)
	if player.global_position.x > BHOP_WRAP:
		player.global_position.x -= BHOP_WRAP * 2.0

	var grounded := player.is_on_floor()
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var target := player.target_speed()
	var elapsed := _frames - _bhop_at

	match _bhop_step:
		0:  # dress the subject and put it on the start line
			var subject: String = BHOP_SUBJECTS[_bhop_subject]
			player.set_elder(subject == "elder")
			if subject == "carrier":
				Net.config.win_condition = MatchConfig.WinCondition.CAPTURE
				MatchState._letter_holds[1] = {"letter": 1, "ends_at": INF}
			player.revive_at(Transform3D(Basis(Vector3.UP, -PI / 2.0), BHOP_START))
			player.input_direction = Vector2(0.0, -1.0)
			player.wants_sprint = true
			_bhop_row = {"subject": subject, "run": 0.0, "once": 0.0, "hops": 0.0,
				"late": 0.0, "dive_before": 0.0, "dive_after": 0.0}
			_bhop_next(1)
		1:  # sprint on the ground
			if elapsed > 40:
				_bhop_row["run"] = maxf(_bhop_row["run"], speed)
			if elapsed >= 70:
				player.request_jump()
				_bhop_next(2)
		2:  # one plain jump out of a run, and a while on the ground after it
			_bhop_row["once"] = maxf(_bhop_row["once"], speed)
			if grounded and elapsed > 70:
				_bhop_hops = 0
				_bhop_next(3)
		3:  # ten hops, each pressed on the first ground tick
			_bhop_row["hops"] = maxf(_bhop_row["hops"], speed)
			if grounded and (not _bhop_was_grounded or _bhop_hops == 0):
				if _bhop_hops >= BHOP_HOPS:
					_bhop_next(4)
				else:
					player.request_jump()
					_bhop_hops += 1
		4:  # landed from the last timed hop: wait, then hop late
			if elapsed == BHOP_LATE_TICKS:
				player.request_jump()
			elif elapsed > BHOP_LATE_TICKS and not grounded:
				_bhop_row["late"] = maxf(_bhop_row["late"], speed)
				if elapsed > BHOP_LATE_TICKS + 8:
					player.request_jump()  # airborne: this is the dive
					_bhop_next(5)
		5:  # the dive: keep pressing jump from touchdown until it leaves again
			if grounded:
				player.request_jump()
				_bhop_row["dive_before"] = speed
			elif _bhop_was_grounded and _bhop_row["dive_before"] > 0.0:
				_bhop_row["dive_after"] = speed
				_bhop_verdict(target)
				_bhop_subject += 1
				if _bhop_subject >= BHOP_SUBJECTS.size():
					print("combat_range: %s" % ("bhop PASS" if _bhop_failures == 0
						else "bhop FAIL (%d)" % _bhop_failures))
					get_tree().quit()
					return
				_bhop_next(0)
			elif elapsed > 600:
				print("combat_range: bhop %s never came out of its dive — bhop FAIL"
					% _bhop_row["subject"])
				get_tree().quit()
				return
	_bhop_was_grounded = grounded


func _bhop_next(step: int) -> void:
	_bhop_step = step
	_bhop_at = _frames


## One subject's numbers and whether they hold. `target` is its run speed with
## every multiplier in, which is what the cap is a multiple of.
func _bhop_verdict(target: float) -> void:
	var row := _bhop_row
	var cap := target * Gub.HOP_SPEED_CAP
	var problems: Array[String] = []
	if row["run"] > target + BHOP_EPSILON:
		problems.append("running is faster than run speed")
	if row["once"] > target + BHOP_EPSILON:
		problems.append("one jump is faster than run speed")
	if row["hops"] < target * 1.15:
		problems.append("timed hops never reached 1.15x")
	if row["hops"] > cap + BHOP_EPSILON:
		problems.append("timed hops went past the cap")
	if row["late"] > target + BHOP_EPSILON:
		problems.append("a late hop kept its bonus")
	# Against run speed as well: the tick the roll lets go, ordinary ground
	# acceleration is allowed to bring a slow roll back up to target. What must
	# not happen is anything past that.
	if row["dive_after"] > maxf(row["dive_before"], target) + BHOP_EPSILON:
		problems.append("a hop out of a dive roll gained speed")
	_bhop_failures += problems.size()
	print("combat_range: bhop %-7s run %.2f  once %.2f  hops %.2f (%.2fx, cap %.2f)  late %.2f  dive hop %.2f -> %.2f — %s" % [
		row["subject"], row["run"], row["once"], row["hops"], row["hops"] / target,
		cap, row["late"], row["dive_before"], row["dive_after"],
		"ok" if problems.is_empty() else "FAIL: " + ", ".join(problems)])


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
