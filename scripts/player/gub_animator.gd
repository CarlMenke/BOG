class_name GubAnimator
extends AnimationTree
## Drives the Gub's skeleton from the state of the `Gub` body above it.
##
## **Ground poses come from speed, air poses come from the arc, events are
## one-shots.** Nothing in this tree runs a clock that is not either (a) a
## looping locomotion cycle, (b) a OneShot that restarts every time it is fired,
## or (c) a node that is scrubbed to an absolute time every frame. That is not a
## style preference: an `AnimationNodeAnimation` sitting in a blend runs its own
## clock from the moment the tree starts whether or not anything is listening,
## reaches its last frame, and stops there for the rest of the round (D-026).
## Every clip in here is one of those three kinds, so that bug cannot be written
## into this graph without deleting one of them first.
##
## The graph, left to right:
##
##     stand      BlendSpace2D   nine points over the body-relative velocity
##     crouch     BlendSpace1D   CrouchIdle @ 0 | CrouchWalk @ CROUCH_SPEED
##     stance     Blend2         stand / crouch, by how crouched
##     air_one    Animation(JumpOne) behind air_one_seek, scrubbed by the arc
##     air_two    Animation(JumpTwo) behind air_two_seek, scrubbed by the arc
##     air        Blend2         air_one / air_two, 1 if this airtime is a dive
##     grounded   Blend2         stance / air, by how airborne
##     slide      OneShot        the low part of Slide, full body
##     land       OneShot        JumpOne's touchdown and absorb, full body
##     roll       OneShot        JumpTwo's ground roll, full body
##     draw_clip  Animation(Draw) behind draw_seek, scrubbed by the charge
##     draw       Blend2         the draw pose over everything, upper body only
##     loose      OneShot        Loose, upper body only
##     cast       OneShot        Cast at the Elder's own rate, upper body only
##     throw      OneShot        Throw at THROW_RATE, filtered to the upper body
##     swing      OneShot        Swing at SWING_RATE, **full body**
##     output   <- swing
##
## The two windups are two one-shots and not one one-shot with a choice of clip,
## for the reason the four above it are four: a one-shot owns a clip, a window
## and a pair of fades, and the throw and the cast agree on none of the three
## (D-064). What they are not is two *timings* — `GubCombat` fires exactly one of
## them per click and has one release tick for both, which is the thing D-025
## and D-038 exist to keep single.
##
## **The draw is not a one-shot at all, and that is the whole of D-065.** A bow
## is held, for as long as the archer holds it, and how far it is held is a
## number the *opponent* has to be able to read. So it is the third kind of node
## in this graph's opening paragraph — a clip scrubbed to an absolute time every
## frame — and the time it is scrubbed to is `draw_time(charge)`, exactly as the
## two jump clips are scrubbed to `arc_time(vy)`. There is no clock anywhere in
## it, which is what makes it replicate for the price of one float: every peer
## reaches the same pose from the same charge, and a Gub that is half drawn is
## half drawn on all eight screens.
##
## **The swing is the only attack in this graph that is not a layer, and it is
## not one because it cannot be** (D-068). The great sword's clip turns the body
## through a whole revolution and carries it 1.712 m; a mask that kept the legs
## on the locomotion plane would leave a Gub spinning from the waist up over a
## run cycle pointing somewhere else, and there is no line to draw the mask at
## because the rotation is in the pelvis. So it is a full-body OneShot at the top
## of the tree, and everything under it — the plane, the crouch, the air scrub,
## the landing — is replaced for as long as it runs. That is also the whole of
## "the sword works in the air": the air pose is one of the things it replaces,
## which costs nothing and is why there is no second clip for the airborne case.
##
## **`stand` is a plane and not a line, which is the whole of D-066.** A Gub
## aiming holds its facing at the crosshair (`Gub._face_view`) and moves
## wherever the keys say, so "how fast" stopped being enough to pick a pose
## with: a Gub running sideways at 5.4 m/s and a Gub running forward at 5.4 m/s
## used to be the same blend position and the same forward run cycle, with the
## feet skating through the whole of the difference. The position is now the
## velocity **in the body's own frame** — x to its right, y forward — and the
## nine points are Idle, a walk and a run in each of the four directions.
##
## Both blend positions are in **game** metres per second, not in clip units:
## each locomotion node carries its own playback rate (`game speed / authored
## speed`) in a custom timeline, so a Gub travelling at exactly one of the three
## speeds is playing exactly one clip at exactly the rate that keeps its feet on
## the floor. There is no global TimeScale to keep in step with anything.
##
## One code path for the Gub you are driving and the seven you are watching:
## everything read here comes either from a `Gub` accessor that already answers
## with replicated values on a remote Gub (`is_grounded`, `is_sliding`,
## `is_crouching`, `vertical_speed`, `velocity`) or from a replicated serial
## counter (`sync_jump_serial`, `sync_dive_serial`).

# ------------------------------------------------------------------- clips ---

## Every clip this graph names. Checked once in `_ready`, because a rebuild that
## renames or drops one would otherwise show up as a Gub that simply never
## moves, with nothing in the log.
const REQUIRED_CLIPS: Array[String] = [
	"Idle", "Walk", "Run", "CrouchIdle", "CrouchWalk",
	"JumpOne", "JumpTwo", "Slide", "Throw", "Cast", "Draw", "Loose",
	"StrafeLeft", "StrafeRight", "StrafeWalkLeft", "StrafeWalkRight",
	"RunBack", "WalkBack", "Drink", "Swing",
]

# -------------------------------------------------------- the airborne arc ---

## The two jump clips are far longer in the air than any jump the physics
## actually makes — JumpOne spends 0.34 s of clip off the ground against a
## 0.70 s round trip at JUMP_VELOCITY — so neither is played on a clock. They
## are *indexed by where the body is in its arc*: `phase` 0 is leaving the
## ground, 0.5 is the apex, 1 is about to land, and these three clip times are
## the poses that belong at those three moments.
##
## The two clips are treated differently because the pipeline treats their
## vertical motion differently (`VERTICAL_RISE_KEPT` in `tools/build_gub.py`),
## and each set of times below is measured on the clip as it is actually built.
##
## JumpOne is a vertical hop, and its pelvis rise *is* the ballistic motion the
## physics capsule already performs, so the pipeline pins the hips at their
## first key. With the pelvis not moving, the tell for "high in the air" is how
## far the feet are tucked up under it: the toes are 0.14 m *below* rest at
## 0.58 s (legs still extended in the push-off), peak 0.17 m above it at 0.83 s,
## and are back on the ground by 0.97 s. So the apex pose is the 0.83 s tuck and
## not the 0.75 s the hips top out at in the raw clip.
##
## START is 0.68 and not 0.60 for the same reason the apex moved: 0.58-0.65 is
## the push-off, and with the pelvis pinned those extended legs reach 0.141 m
## under the floor (deepest at 0.583 s, measured by the build's own floor
## check). The physics take-off is instantaneous — the capsule is already
## leaving at JUMP_VELOCITY on the frame the jump is pressed — so there is
## nothing for a wind-up pose to be in step with, and phase 0 may as well be
## the first frame that is clear of the ground.
const JUMP_ONE_START := 0.68
const JUMP_ONE_APEX := 0.83
const JUMP_ONE_END := 0.95

## JumpTwo is a front somersault, and its hips rise is *not* something the
## capsule duplicates — the clip's pelvis has to be up there or the inverted
## body's head and hands go through the floor. So the pipeline keeps the rise in
## full, and the clip is once again self-consistent: hips top out 0.618 m above
## standing at 0.900 s, the hands take the ground at 1.183 s and stay down to
## 1.833, and the feet come through at 1.530.
##
## Which puts the apex pose back where the hips say it is. (It was moved to
## 1.10 s while the pelvis was pinned, to hurry past the frames that sank
## furthest below the floor; nothing sinks now while the body is airborne, so
## the honest reading is the right one.) The window ends at 1.48, a frame or two
## before the feet arrive, and the roll one-shot takes it from there.
const JUMP_TWO_START := 0.58
const JUMP_TWO_APEX := 0.90
const JUMP_TWO_END := 1.48

# ------------------------------------------------------------- the windows ---

## The slide. `Slide` drops the hips from 0.69 m to 0.17 m by 0.50 s, holds them
## there to 1.13 s and is standing again by 1.70; the window is the whole of
## that. `Gub.SLIDE_DURATION` (1.0 s) ends the physical slide at 1.10 s of clip,
## just as the hips start to rise, and SLIDE_FADE_OUT covers the stand-up.
const SLIDE_CLIP_START := 0.10
const SLIDE_CLIP_END := 1.70

## The landing absorb, taken out of JumpOne: touchdown at 0.95 and the dip
## bottoms out with the hips at 0.43 m around 1.28. JUMP_ONE_END and this share
## the 0.95 boundary on purpose — the scrub hands over to the one-shot at the
## frame the feet touch.
##
## The window runs to 1.45 rather than 1.35 because Godot fades a one-shot out
## *inside* its window and not after it: with the end at 1.35 the LAND_FADE_OUT
## 0.20 s of blend started at 1.15, so the absorb was already being pulled back
## toward the locomotion pose before it had reached its deepest frame, and the
## dip that is the whole point of the clip never fully arrived. 1.45 gives the
## bottom of the absorb the frames it needs and still leaves the stand-up to the
## fade rather than playing it out.
const LAND_CLIP_START := 0.95
const LAND_CLIP_END := 1.45

## The dive's ground roll, out of JumpTwo: the feet come down through 1.48, the
## hips are on the floor (0.12 m) from 1.53 to 1.77, and the body is standing
## again by 2.25. Ends at 2.10 for the same reason the landing does.
##
## Starts at 1.62 and not at the 1.48 the air scrub hands over at, on purpose.
## The roll is authored below the floor: those hips keys sit *under* the clip's
## first key, which the pipeline's vertical rule never lifts (see
## `tools/build_gub.py`), and from 1.48 to ~1.60 the skin is 0.15-0.25 m under
## the plane — the most sunk stretch of the whole clip. From 1.62 it is within
## 0.10 m and closing. The cost is the first two frames of the tumble, which a
## touchdown — an impact, with a 0.05 s fade-in — hides anyway.
const ROLL_CLIP_START := 1.62
const ROLL_CLIP_END := 2.10

## The throw. `Throw` is `2_Spear_Suite/SpearThrowLonger`, 2.833 s of run-up,
## overhand delivery and a long hunched recovery (D-063). Only 1.067-1.900 is
## the throw.
##
## The first second of it is an approach the game can never show: the clip
## covers 2.842 m and `lock_root_motion` clamps every one of those metres away,
## so a window that opened any earlier would be a Gub sprinting on the spot into
## its own wind-up. The window opens instead on the quiet frame between the
## approach and the wind-up — the throwing arm hanging level with the hips, its
## furthest-forward swing spent — so the OneShot's 0.08 s fade-in is finished
## before the arm starts back and there is nothing to snap out of.
##
## It closes at 1.900, which is 0.333 s past the release and further than it
## looks: Godot fades a one-shot out *inside* its window (see LAND_CLIP_END), so
## THROW_FADE_OUT's 0.22 s runs from 1.680 and what is actually held at full
## weight ends a tenth of a second after the spear has gone. That is deliberate.
## The clip's deepest forward pitch is 1.700-1.780 and its recovery hunches the
## chest for the whole of the second after that; the fade is what the
## follow-through hands over to, instead of the graph playing out a lunge the
## physics body has nowhere to go with.
const THROW_CLIP_START := 1.067
const THROW_CLIP_END := 1.90

## Where in `Throw` the spear leaves the hand, in the clip's own seconds.
##
## Measured, not chosen — and by a different rule from the clip this replaced.
## Tracking `RightHand` against `Hips` on the *built* asset
## (`tools/hand_track.gd`), the hand is drawn back and 0.80 m above the hips at
## 1.433, whips over the shoulder, and reaches 0.718 m in front of the hips at
## 1.567: the furthest forward it ever gets, and the last frame before it starts
## back toward the body. `tools/build_gub.py` prints that same 1.567 at the end
## of every build, which is what makes this a number that can be checked.
##
## The old clip's release was its peak hand speed, 0.05 s *before* its full
## extension, because a baseball throw's hand is fastest on the way out. This
## one is fastest at 1.600, 10.2 m/s, on the way *down* — the hand is already
## 0.11 m back toward the body by then and dropping past the hip. Letting go
## there would read as a slam. So on this clip the rule that picks the frame is
## full extension, and the speed peak is what says which side of it to be on.
const THROW_RELEASE_IN_CLIP := 1.567

## The part of the clip that actually has to have happened by the time the thing
## in the hand leaves it, in the clip's own seconds. 0.500 s of arm.
##
## Named rather than left inline because there are now three questions asked
## about it and they are inverses of each other: "how long does this take at a
## given rate", "what rate makes it take a given time", and — since D-063 — what
## rate the spear's own throw is played at. All three are below, and all three
## have to be reading the same window or the release lands somewhere the arm is
## not (D-040).
const THROW_WINDOW := THROW_RELEASE_IN_CLIP - THROW_CLIP_START

## How long after the click the spear is *asked* to leave the hand, in real
## seconds. The one number in this block that is a decision rather than a
## measurement: the playtest that got D-025's windup called its 0.71 s a delay
## ("there is a short delay from clicking fire to when it actually throws"), and
## half a second is what was asked for instead.
const THROW_RELEASE_TARGET := 0.5

## The rate the window is played at. Derived from the ask above rather than
## typed beside it, so that a window which moves moves the rate with it and
## leaves the release where it was promised (D-025, D-063). This is still the
## one clip in the graph whose rate is not derived from a ground speed, so it
## still gets its own TimeScale node.
##
## It comes out at **1.0**, and that is the argument for this clip rather than a
## coincidence to be tidied away: the delivery takes exactly the half second it
## is wanted in, so what the player sees is the throw as it was drawn, at the
## speed it was drawn at. The clip this replaced needed 1.6x to fit 1.133 s of
## arm into 0.71 s, and the way to make an illegible release legible was never
## going to be to play it faster still.
const THROW_RATE := THROW_WINDOW / THROW_RELEASE_TARGET

## The shortest any throw may be squeezed into, whatever is asked of it.
##
## It exists for one setting: `lightning_delay` of 0, which is legal and means
## "the bolt leaves on the frame of the click". A rate derived from a delay of
## zero is a division by zero, and a rate of several hundred is a frame of
## nothing followed by an arm already back at its side. 0.14 s is about as short
## as a throw can be and still read as one; below it the ceiling does the
## clamping and the bolt simply leads the hand, which at that setting is what
## was asked for.
##
## Written as the floor and not as the rate, which is the change D-063 made
## here. The ceiling used to be a typed 8.0 that *meant* 0.14 s, on a window of
## 1.133 s; on this 0.500 s window the same 8.0 would have quietly become
## 0.06 s of arm, three and a half frames of it, with nothing anywhere saying
## the number had stopped meaning what its own comment said. The thing worth
## carrying across a change of clip is the one with the argument attached.
##
## The floor stays here and the **ceiling moved to the cast** (D-064), which is
## where the only thing that was ever squeezed by it went. The spear is played
## at THROW_RATE and at nothing else, so a ceiling over the throw's own window
## was a clamp no setting in this game could reach; what asks to be sped up is
## the Elder, and since it stopped borrowing this clip its ceiling has to come
## off the clip it does play. The number itself is a fact about the eye rather
## than about either clip, which is why one of it serves both.
const THROW_RELEASE_MIN := 0.14

## How long after `play_throw()` the spear actually leaves the hand, in real
## seconds. `GubCombat` reads this, and it is derived rather than typed so that
## moving the window or the rate cannot leave the spear and the hand disagreeing
## (D-025 is what that costs). = (1.567 - 1.067) / 1.0.
##
## Derived *through the rate* rather than aliased to `THROW_RELEASE_TARGET`,
## which would be the same number today and the wrong number the day somebody
## pins the rate by hand: the rate is what the graph actually plays, so this has
## to be whatever that rate produces. Written this way the ask above is the
## thing that visibly stops being met, instead of this quietly lying.
const THROW_RELEASE_TIME := THROW_WINDOW / THROW_RATE


# ----------------------------------------------------------------- the bow ---

## The draw, and the two frames of `Draw` the charge is stretched between.
##
## `Draw` is `3_Bow_Suite/StandingDrawArrow.fbx`, 1.017 s of reach, nock and
## pull. **Only the pull is the charge**, and where it starts was measured the
## way every other window in this file was: tracking `RightHand` against `Hips`
## on the built asset, the drawing hand comes down off the shoulder at over
## 4 m/s, arrives at the bow at **0.567 s doing 0.29 m/s** — the slowest frame
## between the reach and the pull — and then draws back at a steady 0.95 m/s to
## the end of the clip. 0.567 is the arrow meeting the string.
##
## The 0.567 s before it is a Gub taking an arrow out of a quiver, and it cannot
## be in the charge however good it looks. A bow is **carried**: charge zero has
## to be a nocked bow at brace, or a snap shot fires an arrow the Gub is still
## reaching for, and the string has nothing to be drawn from. What covers the
## raise instead is the blend — `DRAW_BLEND_SPEED` brings this layer up over
## a twelfth of a second out of whatever the body was already doing.
##
## There is no END here to match the other windows' pairs, because this clip is
## never played: `DRAW_CLIP_FULL` is where the charge *stops*, and the clip runs
## out one frame later anyway.
const DRAW_CLIP_START := 0.567
const DRAW_CLIP_FULL := 1.0167

## How fast the draw layer comes up over the body, in blend per second.
##
## Faster than the stance and slower than nothing: the pose has to be *there*
## early, because the charge is already running and a layer still fading in at
## 30% charge is a tell arriving late. A twelfth of a second, which is about the
## length of the raise this blend is standing in for.
const DRAW_BLEND_SPEED := 12.0

## The loose. `Loose` is `3_Bow_Suite/StandingAimRecoil.fbx`, 0.683 s, and it
## opens on the fully drawn pose — its first frame is the frame `Draw` ends on,
## which is what lets the one hand over to the other without a seam.
##
## **0.167 is the last frame the hand is on the string.** Tracked the same way:
## the drawing hand creeps back at about a metre a second for the first tenth of
## a second (the final squeeze), slows to **0.54 m/s at 0.167**, and is doing
## **8.06 m/s at 0.183** — off the string and flying back past the ear. Two
## frames, one of them the loose.
##
## 0.450 closes it, and that is the fade-out's number rather than the clip's.
## Godot fades a one-shot out *inside* its window (see LAND_CLIP_END), so
## LOOSE_FADE_OUT's 0.18 s runs from 0.270 — a tenth of a second after the arrow
## has gone, which is the property the throw's and the cast's ends were both
## picked for. What the fade takes over from is the bow arm coming down, which
## starts at about 0.36 and is a recovery a Gub still holding a bow has no use
## for.
const LOOSE_CLIP_START := 0.167
const LOOSE_CLIP_END := 0.45

## Where in `Loose` the string leaves the fingers, in the clip's own seconds.
##
## Measured on the built asset with `tools/hand_track.gd`, hip-relative, and by
## **D-025's original rule** — peak hand speed — which is the fourth clip in
## this file and the second time that rule has been the right one. It is not a
## judgement call here the way it was on the throw and the cast: 0.54 m/s to
## 8.06 m/s between two adjacent frames is not a peak to be picked out of a
## curve, it is a discontinuity. A string either has the fingers on it or does
## not.
const LOOSE_RELEASE_IN_CLIP := 0.183

## How long after the string is let go the arrow actually leaves, in real
## seconds. **One frame**, and that is the answer rather than an approximation
## of zero.
##
## Derived from the two constants above for the reason `THROW_RELEASE_TIME` is
## derived from its own pair: whoever moves the window cannot leave the arrow
## and the hand disagreeing. What is different is how small it comes out, and
## that is the bow rather than a shortcut — **the windup already happened**. A
## spear waits half a second because the arm has to travel; an Elder's bolt
## waits a fifth because the dial says so; a bow has been drawn, in the open,
## for as long as its archer chose, and there is nothing left for a delay to
## announce. The charge was the announcement (D-065).
##
## There is deliberately no rate to divide by. The throw has one because it was
## windowed to hit half a second and the cast has one because a lobby dial moves
## it; nothing asks this clip to be anything but the speed a string is.
const BOW_RELEASE_TIME := LOOSE_RELEASE_IN_CLIP - LOOSE_CLIP_START

## The loose comes in faster than any other one-shot here and leaves at the
## throw's pace. In, because the pose it is blending out of is the draw's own
## last frame — the same pose, so there is nothing to protect and everything to
## gain from the string being gone on the frame it goes. Out, for the
## arithmetic under LOOSE_CLIP_END.
const LOOSE_FADE_IN := 0.04
const LOOSE_FADE_OUT := 0.18


## Where in `Draw` a bow drawn `charge` of the way sits, in the clip's own
## seconds.
##
## The bow's `arc_time`, and deliberately the same shape: a pose picked by a
## continuous quantity the world already knows, rather than a clip run on a
## clock nobody else can see. `arc_time` reads the body's place in its arc off
## the vertical velocity; this reads the draw off a float that replicates
## (`Gub.draw_fraction`). Both are correct on the seven Gubs you are watching
## for exactly the same reason, and neither can freeze (D-026).
static func draw_time(charge: float) -> float:
	return lerpf(DRAW_CLIP_START, DRAW_CLIP_FULL, clampf(charge, 0.0, 1.0))


# ---------------------------------------------------------------- the cast ---

## The Elder's cast. `Cast` is `4_Elder_Suite/Standing1HMagicAttack1.fbx`,
## 2.283 s and in place — it travels 0.000 m end to end and never gets more than
## 0.124 m from where it started, so unlike every other one-shot in this graph
## there is no run-up for the window to have to open after (D-064).
##
## It is its own clip and not the spear's at a higher rate, which is the whole
## of step 5 of `docs/PLAN_COMBAT.md`. D-063 left the Elder riding
## `SpearThrowLonger`'s window at 2.5x and said plainly that it read only
## because the robe is a cone: what a bolt's windup actually showed was the hat
## dipping and the hand snapping forward with the crackle in it. That is still
## all the robe lets through — so the argument for this clip is not that the old
## one looked broken, it is that the arm under the hat is now doing a cast
## instead of a throw, and the hand the crackle sits in ends up **out in front
## and stopped** rather than swung down past the hip.
##
## 0.467 is the quiet frame. The clip opens with the arm swinging back and out
## to the right, and at 0.467 that swing is spent: the hand is moving at
## 0.58 m/s, the slowest it gets anywhere between the first frame and the
## follow-through, and it is the last frame before it starts to rise into the
## cock. So CAST_FADE_IN has something still to blend out of, which is the
## choice D-063 made on the throw and for the same reason.
##
## 1.600 closes it, 0.617 s of clip past the release, and that is the fade-out's
## number rather than the clip's. Godot fades a one-shot out *inside* its window
## (see LAND_CLIP_END), so at the default delay's 2.58x the window is 0.439 s of
## real time and CAST_FADE_OUT's 0.14 s runs from 0.299 — a tenth of a second
## after the bolt has gone, which is the property the throw's own end was picked
## for. What the fade takes over from is the unwind: the arm holds the point to
## 1.13 and the body then turns back out from under it, which is a recovery a
## standing physics body has nowhere to go with.
const CAST_CLIP_START := 0.467
const CAST_CLIP_END := 1.60

## Where in `Cast` the bolt leaves the hand, in the clip's own seconds.
##
## Measured on the built asset with `tools/hand_track.gd`, hip-relative, and by
## a **third** rule — neither the peak hand speed D-025 took on the old throw
## nor the full forward extension D-063 took on the new one. Both of those are
## wrong here, and this clip says so rather loudly:
##
## - **Peak speed is 0.783 s**, 5.97 m/s, and at that frame the hand is 0.157 m
##   in front of the hips: barely past its own belly, arm still folded. A bolt
##   leaving there comes out of the Gub rather than out of the hand.
## - **Furthest forward is 1.333 s**, and it is an artefact. The hand stops
##   moving at 0.98 and is then *held* out in front while the body unwinds
##   beneath it — so the hip-relative reach goes on creeping outward to 0.558 m
##   a third of a second after the cast is over, on an arm travelling 0.2 m/s.
##   D-063's rule, asked of this clip, picks the recovery.
##
## What this clip is, is a **throw that stops**: the hand is cocked behind the
## hip line at 0.700, whipped forward, and by 0.983 it has stopped going forward
## at all (its forward component crosses zero there) and fallen under a metre a
## second (0.90). Two independent readings of one frame, and that frame is where
## the motion ends and the pose begins. Everything after it is a point being
## held, which is what a caster does once the thing has left.
const CAST_RELEASE_IN_CLIP := 0.983

## The part of the cast that has to have happened by the time the bolt leaves,
## in the clip's own seconds. 0.516 s of arm: a wind-up into the cock at 0.700
## and a 0.283 s whip out of it.
const CAST_WINDOW := CAST_RELEASE_IN_CLIP - CAST_CLIP_START

## The shortest the cast may ever be squeezed into, and the ceiling that makes a
## `MatchConfig.lightning_delay` of 0 a setting rather than a division by zero.
##
## The floor is THROW_RELEASE_MIN's 0.14 s, and it is deliberately the same
## number rather than a second copy of it: how briefly an arm can move and still
## be seen to move is a fact about the eye and not about which clip is playing.
## What is not the same is what it buys, which is the reason the ceiling moved
## here at all — 0.14 s of a 0.516 s cast is **3.69x**, against the 3.57x the
## same floor bought on the spear's 0.500 s window. At that rate the wind-up
## plays in 0.063 s and the whip in 0.077 s, and the bolt leads the hand by
## however far under 0.14 s the dial has been dragged, which at zero is exactly
## what that setting asked for.
const CAST_RELEASE_MIN := THROW_RELEASE_MIN
const CAST_RATE_MAX := CAST_WINDOW / CAST_RELEASE_MIN


## The playback rate that puts the cast's release exactly `seconds` after the
## click.
##
## The Elder's bolt leaves `MatchConfig.lightning_delay` after the click rather
## than at the spear's 0.50 s (D-040), and firing at 0.2 s while an arm authored
## to take 0.516 s of clip is still on its way out would look broken — so the
## clip is sped up to meet the number instead of the number being fitted to the
## clip. At the default 0.2 that is 0.516 / 0.2 = **2.58x**, and the Elder is
## the only thing in the game that ever asks.
##
## Derived here rather than typed next to the delay for the reason
## `THROW_RELEASE_TIME` is derived: a hard-coded 2.58 beside a dial that can be
## dragged to 0.5 is a hand that arrives a third of a second after the bolt it
## is supposed to be throwing, and nothing anywhere would say so.
static func cast_rate_for_release(seconds: float) -> float:
	# Below the ceiling's own release time there is nothing left to scale, so
	# this returns the ceiling rather than dividing by something at or near zero.
	if seconds <= CAST_WINDOW / CAST_RATE_MAX:
		return CAST_RATE_MAX
	return CAST_WINDOW / seconds


## The inverse: when the cast's release actually lands for a clip played at
## `rate`. Only differs from what was asked for once `cast_rate_for_release` has
## hit its ceiling, which is the one place the two can disagree and the one
## place the disagreement is intended.
static func cast_release_for_rate(rate: float) -> float:
	return CAST_WINDOW / maxf(rate, 0.01)

# ----------------------------------------------------------- the great sword --

## The swing. `Swing` is `7_GreatSword_Suite/GreatSwordHighSpinAttack.fbx`,
## 1.867 s of spinning advance: the body turns away from the target, comes round
## through a whole revolution — 350° of spread by the hip line, overshooting past
## 415° mid-swing — and arrives 1.712 m from where it started (D-068).
##
## **The window is the whole clip, and this is the only one-shot here that can
## say that.** The throw opens 1.067 s in because the second before it is an
## approach `lock_root_motion` would have the Gub run on the spot; the cast
## closes 0.6 s early because its recovery is a body unwinding that a standing
## `CharacterBody3D` has nowhere to go with; the drink is a gesture with a
## minute of stillness round it. This clip has none of those, because its
## recovery **is** the advance — the body is still travelling through the whole
## of the last third — and the metres are the reach. Cut the window short and
## `Gub.SPIN_ADVANCE` is a distance the animation no longer covers, which is the
## feet skating for whatever was cut.
##
## So both ends are the clip's own, and the fade-out lives inside the second
## half of the follow-through: Godot fades a one-shot out *inside* its window
## (see LAND_CLIP_END), so SWING_FADE_OUT's 0.25 s runs from 1.617 — half a
## second after the blade has gone through, and over the frames where the body
## is coming back square. That is what hands the legs back to the locomotion
## plane while the Gub is still moving, which is the right way round: a swing
## that ended by planting both feet would stop a Gub that is supposed to be
## carrying its speed into the next one.
const SWING_CLIP_START := 0.0
const SWING_CLIP_END := 1.8667

## Where in `Swing` the blade goes through, in the clip's own seconds.
##
## Measured on the built asset, and by **D-025's original rule** — peak hand
## speed — which is the fifth clip in this file to be cut and the second time
## that rule has been the right one. It is not a judgement call here the way it
## was on the throw and the cast, and the reason is the weapon rather than the
## measurement: a spear leaves a hand at full extension because that is where the
## fingers open, a caster's hand stops and holds, and a **sword cuts where the
## blade is fastest**. There is nowhere else on a swing for the contact to be.
##
## `tools/build_gub.py` prints the same 1.067 at the end of every build —
##
##     Swing       length 1.867  peak hand speed 1.067 (6.86 m/s), furthest forward 1.650
##
## — which is what makes this a number that can be checked rather than believed.
## The "furthest forward" column is 1.650 and is the same artefact the cast's
## own record describes: the hand is carried out and round by a pelvis that is
## still turning, so hip-relative reach goes on creeping for half a second after
## the cut. D-063's rule, asked of this clip, picks the follow-through.
##
## `tools/combat_range.tscn -- sword` checks it from the other side and off a
## different quantity again — the **sword's own tip**, read through the bone
## attachment, in the game, with the composed pose and the modifier stack in it.
## The tick the hit resolves on has to be the tick that tip is moving fastest.
const SWING_RELEASE_IN_CLIP := 1.067

## The part of the clip that has to have happened by the time the blade connects.
## 1.067 s of wind-up and swing, which is a little over twice the spear's 0.500
## and is the whole of "slow windup, big damage, no defence".
const SWING_WINDOW := SWING_RELEASE_IN_CLIP - SWING_CLIP_START

## The rate the swing is played at.
##
## **One, and stated rather than derived, which is the third answer this file
## has given to the same question.** The throw's rate is derived from a release
## the playtest asked for; the cast's is derived from a lobby dial; the loose has
## no rate at all because "a string is as fast as a string". This is that last
## sentence about a different weapon: the weight of a great sword *is* the 1.867
## seconds, and speeding the clip up is the one change that would stop a heavy
## melee reading as heavy. Nothing asks it to be anything else, so there is no
## ask for a rate to be derived from.
##
## It is still a named constant with the two numbers below divided by it, for
## D-025's reason: pin a different rate here and the release time and the
## commitment both follow, instead of one of them quietly lying.
const SWING_RATE := 1.0

## How long after `play_swing()` the blade actually connects, in real seconds.
## `GubCombat` reads this, and it is derived through the rate rather than typed
## so that moving the window or the rate cannot leave the hit and the blade
## disagreeing (D-025). = (1.067 - 0.0) / 1.0.
const SWING_RELEASE_TIME := SWING_WINDOW / SWING_RATE

## How long the whole swing takes, in real seconds — the click to the last frame.
##
## The other half of `Gub.SPIN_ADVANCE`: the body covers those 1.712 m over
## exactly this, so the two together are the 0.917 m/s the clip's feet were drawn
## cycling against. It is also the length of the commitment — no steering, no
## second attack, no defence — which is what the weapon trades its one-shot kill
## for, and it is what `GubCombat.sword_cycle()` is measured against.
const SWING_SECONDS := (SWING_CLIP_END - SWING_CLIP_START) / SWING_RATE

## The swing comes in faster than the throw and leaves slower than anything else
## here. In, because what it is blending out of is a full-body pose being
## replaced by a full-body pose and there is nothing to protect — the first
## frames of the clip are the body already turning. Out, for the arithmetic
## under SWING_CLIP_END.
const SWING_FADE_IN := 0.06
const SWING_FADE_OUT := 0.25

# --------------------------------------------------------------- the drink ---

## The window of `Drink` the channel is played over, in the clip's own seconds.
##
## `Drink` is `6_Utility/Drinking.fbx`, 6.117 s, and most of it is a Gub
## standing still: 1.35 s of idle before the bottle comes up and 2.2 s of it
## after the arm goes down. What is left is the gesture, and **both ends of it
## are measured**. `tools/build_gub.py` tracks the *drinking* hand — the left
## one; the right hangs at the side for the whole clip and never moves 12 cm —
## and prints where it starts and where it stops:
##
##     Drink  length 6.117  drinking hand moves 1.367..3.933, highest 0.600 m at 2.633
##
## 2.633 is the bottle at the lips, 0.600 m above the hips with the head thrown
## back. `tools/hand_track.gd` reads the same three numbers off the built asset,
## which is what makes them checkable rather than believed — the same property
## D-063 wanted for the throw's release.
##
## The window is those two moments plus a margin at each end, and **each margin
## is its own fade**. At the default channel the rate is 1.47x (below), so
## DRINK_FADE_IN's 0.07 s is 0.103 s of clip — the 0.100 s of stillness the
## window opens with — and DRINK_FADE_OUT's 0.18 s is 0.264 s of clip, near
## enough the 0.267 s of stillness it closes with. So the blend out of whatever
## the body was doing is finished on the frame the arm starts up, and the blend
## back into it begins on the frame the arm has stopped. Nothing the eye follows
## is ever at partial weight.
##
## A host who drags the channel shorter plays this faster and the two fades eat
## into the gesture by the difference; longer, and a little stillness is held at
## each end. Both are the right way round, and neither can move the *length* of
## the drink, which is the whole point of the next constant.
const DRINK_CLIP_START := 1.267
const DRINK_CLIP_END := 4.20

## The part of the clip the channel is spread over. 2.933 s of arm.
##
## Named rather than left inline for the reason THROW_WINDOW is: it is asked
## for by the rate below, and a window that moves has to move the rate with it
## or the drink stops taking the time it is supposed to take.
const DRINK_WINDOW := DRINK_CLIP_END - DRINK_CLIP_START

## The playback rate that makes the drink take exactly `seconds` — the length of
## the channel.
##
## **The channel is the constant and the rate follows it**, which is the same
## shape D-063 and D-064 gave the throw and the cast: the clip is fitted to the
## number the mechanic is built on rather than the number being fitted to the
## clip. `MatchConfig.heal_channel` is 2.0 s by default, so this is
## 2.933 / 2.0 = **1.47x** — a drink that is a little brisker than it was
## animated and reads as one. Derived every time it is asked, off the dial, so a
## host who drags the channel mid-match does not leave one Gub drinking at the
## old speed for the rest of its life.
##
## **There is no ceiling on it, unlike the cast's**, and that is a statement
## rather than an omission. `CAST_RATE_MAX` exists because
## `MatchConfig.lightning_delay` may legally be zero and a rate derived from
## zero is a division by it. A channel of zero is not legal and never will be:
## `heal_channel` floors at 0.5 s, and an instant heal is precisely the thing
## the decision behind this feature rejected (D-067) — standing on a fresh
## corpse would be the strongest play in the game. The dial's own floor is
## therefore the ceiling, and it buys 5.9x, which is a gulp. The `maxf` below is
## against a caller passing nonsense, not against a setting.
static func drink_rate_for_channel(seconds: float) -> float:
	return DRINK_WINDOW / maxf(seconds, 0.01)


## Fade times, in and out, for the four one-shots. The slide comes in fast and
## leaves slowly because its exit *is* the stand-up; the landings come in almost
## instantly because a touchdown is an impact.
const SLIDE_FADE_IN := 0.08
const SLIDE_FADE_OUT := 0.30
const LAND_FADE_IN := 0.05
const LAND_FADE_OUT := 0.20
const ROLL_FADE_IN := 0.05
const ROLL_FADE_OUT := 0.25
const THROW_FADE_IN := 0.08
const THROW_FADE_OUT := 0.22
## The cast comes in and leaves faster than the throw, because at the default
## delay it is playing at 2.58x where the throw plays at 1.0. 0.06 s of
## real-time fade-in is 0.155 s of this clip and finishes at 0.622 — clear of
## the cock at 0.700, and so clear of everything the eye is about to follow;
## the throw's own 0.08 would land at 0.673 and blend through the first frames
## of the whip. The fade-out is 0.14 for the arithmetic under CAST_CLIP_END.
const CAST_FADE_IN := 0.06
const CAST_FADE_OUT := 0.14
## The drink's two, and each one is a margin in DRINK_CLIP_START/END rather than
## a number picked for feel — see the block above for the arithmetic. It comes
## in faster than the throw and leaves slower, which is the shape of the thing:
## a bottle going up is a decision and wants to be seen starting, and an arm
## coming down out of a drink has nowhere in particular to be.
const DRINK_FADE_IN := 0.07
const DRINK_FADE_OUT := 0.18

# ------------------------------------------------------------------ blends ---

## How fast the visual state catches up with the physical one, in units of blend
## per second. Crouch is a near-instant read. Take-off is faster than landing on
## purpose: leaving the ground is a decision and should look like one, while
## arriving wants to settle rather than snap — and the landing one-shot is
## covering the same frames anyway.
const STANCE_BLEND_SPEED := 10.0
const AIRBORNE_RISE_SPEED := 14.0
const AIRBORNE_FALL_SPEED := 10.0
const DIVE_BLEND_SPEED := 12.0

## An airtime shorter than this fires no landing one-shot. Stepping off a kerb,
## or the single frame `is_on_floor()` sometimes drops on a slope, is not a
## landing worth absorbing, and a 0.05 s absorb fired every few strides down a
## rocky slope is a visible stutter.
##
## It is `Gub.ROLL_MIN_AIRTIME` rather than its own number because the body uses
## the same threshold to decide whether to hold the player still through the
## roll (ROLL_LOCK). Two copies of that number could drift apart into the two
## states nobody wants: a roll animation with the controls live under it, or
## 0.45 s of dead controls with no roll to show for them.
const LAND_MIN_AIRTIME := Gub.ROLL_MIN_AIRTIME

# ----------------------------------------------------------- the throw mask --

## Bones the spear throw is allowed to move. Everything from the middle spine
## down keeps whatever the locomotion, the air scrub or the slide is producing,
## which is what makes the throw a *layer* rather than a state: you can throw at
## a dead run. Hips and Spine are deliberately not here — the throw's own
## rotation of them would fight the run cycle's weight shift.
##
## The finger and `*_End` tips carry no tracks in the exported clips (the
## exporter drops constant channels, D-023), so filtering them is a no-op
## today; they are listed because they are part of the arm, and a future rebuild
## that animates a grip should not need this list edited to work.
const UPPER_BODY_BONES: Array[String] = [
	"Spine1", "Spine2", "Neck", "Head", "HeadTop_End",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"LeftHandThumb1", "LeftHandThumb2", "LeftHandThumb3", "LeftHandThumb4",
	"LeftHandIndex1", "LeftHandIndex2", "LeftHandIndex3", "LeftHandIndex4",
	"LeftHandMiddle1", "LeftHandMiddle2", "LeftHandMiddle3", "LeftHandMiddle4",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"RightHandThumb1", "RightHandThumb2", "RightHandThumb3", "RightHandThumb4",
	"RightHandIndex1", "RightHandIndex2", "RightHandIndex3", "RightHandIndex4",
	"RightHandMiddle1", "RightHandMiddle2", "RightHandMiddle3", "RightHandMiddle4",
]

# -------------------------------------------------------------- parameters ---

## The locomotion plane's position, which is a `Vector2` of game m/s in the
## body's own frame — not the scalar it was before D-066. Renamed as well as
## retyped, so anything still setting the old name fails loudly rather than
## handing a float to a node that wants a vector.
const P_STAND_MOVE := "parameters/stand/blend_position"
const P_CROUCH_SPEED := "parameters/crouch/blend_position"
const P_STANCE := "parameters/stance/blend_amount"
const P_AIR_ONE_SEEK := "parameters/air_one_seek/seek_request"
const P_AIR_TWO_SEEK := "parameters/air_two_seek/seek_request"
const P_DIVE := "parameters/air/blend_amount"
const P_AIRBORNE := "parameters/grounded/blend_amount"
const P_SLIDE := "parameters/slide/request"
const P_SLIDE_ACTIVE := "parameters/slide/active"
const P_LAND := "parameters/land/request"
const P_ROLL := "parameters/roll/request"
const P_THROW := "parameters/throw/request"
const P_THROW_ACTIVE := "parameters/throw/active"
const P_THROW_RATE := "parameters/throw_rate/scale"
const P_DRAW := "parameters/draw/blend_amount"
const P_DRAW_SEEK := "parameters/draw_seek/seek_request"
const P_LOOSE := "parameters/loose/request"
const P_LOOSE_ACTIVE := "parameters/loose/active"
const P_CAST := "parameters/cast/request"
const P_CAST_ACTIVE := "parameters/cast/active"
const P_CAST_RATE := "parameters/cast_rate/scale"
const P_DRINK := "parameters/drink/request"
const P_DRINK_ACTIVE := "parameters/drink/active"
const P_DRINK_RATE := "parameters/drink_rate/scale"
const P_SWING := "parameters/swing/request"
const P_SWING_ACTIVE := "parameters/swing/active"
const P_SWING_RATE := "parameters/swing_rate/scale"

var _body: Gub
var _skeleton_path: String = ""

## Smoothed blend positions, so nothing in the tree steps.
var _stance: float = 0.0
var _airborne: float = 0.0
var _dive_blend: float = 0.0
## How far the draw layer is over the body. Not the charge — the charge is the
## *seek*, and this is only whether the bow pose is being shown at all. Two
## numbers because they answer two questions, exactly as `_airborne` and
## `arc_time` do.
var _draw_blend: float = 0.0
## How far the *aim* is over the body, which is a third number beside those two
## and answers a third question (D-066). `draw_time` is where the string is,
## `_draw_blend` is whether the bow pose is being shown, and this is whether the
## torso is turned to the crosshair.
##
## It is not `_draw_blend`, and the difference is the loose. The draw layer's
## weight starts falling on the frame the string goes, and for the length of the
## `Loose` one-shot after that the Gub is still holding an archer's pose out of
## a *different* node — so a torso driven by `_draw_blend` would unwind through
## the recoil and take the bow off the target on the one frame the shot is
## being watched. This holds while either is running.
var _aim_blend: float = 0.0
## The torso modifier, installed in `_ready` rather than declared in `gub.tscn`
## because the skeleton it hangs off lives inside the imported `art/generated/
## gub.glb` and reaching into an instanced scene from a `.tscn` means marking
## its children editable — a large, silent commitment to a node layout the
## pipeline regenerates. `HeldGear` puts its two `BoneAttachment3D`s on the same
## skeleton the same way and for the same reason.
var _aim: GubAim

## What this animator believes about the body. `_grounded` and `_sliding` are
## kept rather than read fresh because the interesting thing about both is the
## frame they *change*.
var _grounded: bool = true
var _sliding: bool = false
## Whether this Gub was drawing a bow last frame. Kept for the same reason
## `_sliding` is: the interesting thing about a draw is the frame it *ends*.
var _drawing: bool = false

## The current airtime. `_airtime_open` is false while the Gub is standing on
## something and nothing is expected to land.
var _airtime_open: bool = false
var _airtime: float = 0.0
var _dived: bool = false
## The upward speed the dive was launched at, which is the scale the dive's arc
## phase is measured against. Seeded with the floor the dive itself enforces.
var _dive_launch: float = Gub.DIVE_UP_VELOCITY

## Last values of the replicated counters this animator has acted on. Seeded
## from the body in `_ready`, so a Gub that spawns into a match already several
## dives old does not open with one.
var _dive_serial: int = 0
var _jump_serial: int = 0


func _ready() -> void:
	_body = get_parent() as Gub
	if _body == null:
		push_error("GubAnimator expects to be a child of a Gub")
		return

	var player := get_node_or_null(anim_player) as AnimationPlayer
	if player == null:
		push_error("GubAnimator: anim_player does not resolve to an AnimationPlayer")
		return
	var missing := _missing_clips(player)
	if not missing.is_empty():
		push_error("GubAnimator: art/generated/gub.glb is missing clips: %s"
			% ", ".join(missing))
		return

	_skeleton_path = _find_skeleton_track_prefix(player)
	tree_root = _build_graph(player)
	active = true

	# After the graph, because the modifier reads this node's own blend weight
	# and a modifier installed on a tree that is not running yet would spend its
	# first frames asking an animator with no graph in it what it was doing.
	var skeleton := _body.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		push_warning("GubAnimator: no Skeleton3D under this Gub; the torso "
			+ "will not aim")
	else:
		_aim = GubAim.install(skeleton, _body, self)

	# A parameter and not a property, so it can only be set once the graph is
	# installed. There is deliberately no matching line for the cast: it has no
	# authored speed to open on, `play_cast` has no default rate for the same
	# reason, and a number put here would be one the dial had never been asked
	# about, sitting where it could be played.
	set(P_THROW_RATE, THROW_RATE)
	# The swing's own authored speed, for the throw's reason: it has one, and
	# unlike the cast and the drink no dial anywhere moves it (D-068).
	set(P_SWING_RATE, SWING_RATE)

	_grounded = _body.is_grounded()
	_dive_serial = _body.sync_dive_serial
	_jump_serial = _body.sync_jump_serial
	# A Gub that dies in mid-air is put back on the ground somewhere else, and it
	# did not land to get there: without this, the teleport reads as a touchdown
	# and every respawn out of a fall opens with a landing absorb.
	_body.respawned.connect(_forget_airtime)
	# Standing, whatever the body says. A Gub is spawned onto the ground, and a
	# remote one is spawned before anything has replicated to it — `sync_grounded`
	# defaults to false, and opening on the air pose is what had every dummy in
	# `tools/combat_range.tscn` and every Gub in the lobby splayed out mid-leap.
	# If it really is falling, AIRBORNE_RISE_SPEED covers the gap in 0.07 s.
	_airborne = 0.0


## Track paths inside the imported clips look like `Armature/Skeleton3D:Hips`.
## The prefix is read off an actual track rather than hard-coded, so renaming a
## node inside the source `.glb` does not silently disable the throw filter —
## which would fail by throwing with the whole body, at a run, and look like a
## blend problem.
func _find_skeleton_track_prefix(player: AnimationPlayer) -> String:
	for clip_name in player.get_animation_list():
		var clip := player.get_animation(clip_name)
		for i in clip.get_track_count():
			var path := String(clip.track_get_path(i))
			if path.contains(":"):
				return path.get_slice(":", 0)
	push_warning("GubAnimator: no skeleton tracks found; throw will play full-body")
	return ""


func _missing_clips(player: AnimationPlayer) -> PackedStringArray:
	var missing := PackedStringArray()
	for clip_name in REQUIRED_CLIPS:
		if not player.has_animation(clip_name):
			missing.append(clip_name)
	return missing


# ------------------------------------------------------------------ graph ---

func _build_graph(player: AnimationPlayer) -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()

	tree.add_node("stand", _locomotion(player), Vector2(0, 0))

	var crouch := AnimationNodeBlendSpace1D.new()
	crouch.min_space = 0.0
	crouch.max_space = Gub.CROUCH_SPEED
	crouch.sync = true
	crouch.add_blend_point(_cycle(player, "CrouchIdle", 0.0, 0.0), 0.0, -1, "still")
	crouch.add_blend_point(
		_cycle(player, "CrouchWalk", Gub.CROUCH_SPEED, Gub.AUTHORED_CROUCH_WALK),
		Gub.CROUCH_SPEED, -1, "walk")
	tree.add_node("crouch", crouch, Vector2(0, 220))

	tree.add_node("stance", _blend2(), Vector2(280, 100))

	tree.add_node("air_one", _scrubbed("JumpOne"), Vector2(0, 420))
	tree.add_node("air_one_seek", AnimationNodeTimeSeek.new(), Vector2(200, 420))
	tree.add_node("air_two", _scrubbed("JumpTwo"), Vector2(0, 560))
	tree.add_node("air_two_seek", AnimationNodeTimeSeek.new(), Vector2(200, 560))
	tree.add_node("air", _blend2(), Vector2(400, 490))

	tree.add_node("grounded", _blend2(), Vector2(560, 280))

	tree.add_node("slide_clip", _window("Slide", SLIDE_CLIP_START, SLIDE_CLIP_END),
		Vector2(560, 700))
	tree.add_node("slide", _shot(SLIDE_FADE_IN, SLIDE_FADE_OUT), Vector2(760, 320))
	tree.add_node("land_clip", _window("JumpOne", LAND_CLIP_START, LAND_CLIP_END),
		Vector2(760, 700))
	tree.add_node("land", _shot(LAND_FADE_IN, LAND_FADE_OUT), Vector2(960, 360))
	tree.add_node("roll_clip", _window("JumpTwo", ROLL_CLIP_START, ROLL_CLIP_END),
		Vector2(960, 700))
	tree.add_node("roll", _shot(ROLL_FADE_IN, ROLL_FADE_OUT), Vector2(1160, 400))
	tree.add_node("drink_clip", _window("Drink", DRINK_CLIP_START, DRINK_CLIP_END),
		Vector2(560, 1000))
	tree.add_node("drink_rate", AnimationNodeTimeScale.new(), Vector2(740, 1000))
	tree.add_node("drink", _upper_body_shot(DRINK_FADE_IN, DRINK_FADE_OUT),
		Vector2(960, 460))
	tree.add_node("draw_clip", _scrubbed("Draw"), Vector2(760, 860))
	tree.add_node("draw_seek", AnimationNodeTimeSeek.new(), Vector2(940, 860))
	tree.add_node("draw", _upper_body_blend(), Vector2(1160, 460))
	tree.add_node("loose_clip", _window("Loose", LOOSE_CLIP_START, LOOSE_CLIP_END),
		Vector2(1160, 1000))
	tree.add_node("loose", _upper_body_shot(LOOSE_FADE_IN, LOOSE_FADE_OUT),
		Vector2(1360, 500))
	tree.add_node("cast_clip", _window("Cast", CAST_CLIP_START, CAST_CLIP_END),
		Vector2(1160, 860))
	tree.add_node("cast_rate", AnimationNodeTimeScale.new(), Vector2(1340, 860))
	tree.add_node("cast", _upper_body_shot(CAST_FADE_IN, CAST_FADE_OUT),
		Vector2(1360, 560))
	tree.add_node("throw_clip", _window("Throw", THROW_CLIP_START, THROW_CLIP_END),
		Vector2(1160, 700))
	tree.add_node("throw_rate", AnimationNodeTimeScale.new(), Vector2(1340, 700))
	tree.add_node("throw", _upper_body_shot(THROW_FADE_IN, THROW_FADE_OUT),
		Vector2(1560, 440))
	tree.add_node("swing_clip", _window("Swing", SWING_CLIP_START, SWING_CLIP_END),
		Vector2(1560, 700))
	tree.add_node("swing_rate", AnimationNodeTimeScale.new(), Vector2(1740, 700))
	# `_shot` and not `_upper_body_shot`, and it is the only attack in this graph
	# that is not filtered (D-068). A 365° body spin is not maskable: the
	# rotation is in the pelvis, which is outside UPPER_BODY_BONES by design
	# (D-029), so a filtered version of this clip would turn a Gub's chest
	# through a revolution while its hips went on facing the crosshair. Full body
	# is also what makes the airborne case free — the air pose is one of the
	# things being replaced.
	tree.add_node("swing", _shot(SWING_FADE_IN, SWING_FADE_OUT), Vector2(1760, 380))

	tree.connect_node("stance", 0, "stand")
	tree.connect_node("stance", 1, "crouch")
	tree.connect_node("air_one_seek", 0, "air_one")
	tree.connect_node("air_two_seek", 0, "air_two")
	tree.connect_node("air", 0, "air_one_seek")
	tree.connect_node("air", 1, "air_two_seek")
	tree.connect_node("grounded", 0, "stance")
	tree.connect_node("grounded", 1, "air")
	tree.connect_node("slide", 0, "grounded")
	tree.connect_node("slide", 1, "slide_clip")
	tree.connect_node("land", 0, "slide")
	tree.connect_node("land", 1, "land_clip")
	tree.connect_node("roll", 0, "land")
	tree.connect_node("roll", 1, "roll_clip")
	tree.connect_node("drink_rate", 0, "drink_clip")
	# The drink is the **bottom** of the four layered one-shots, and that is the
	# one place its order is decided (D-067). Nothing can start a drink while an
	# attack is running and nothing can start an attack while a drink is running
	# — `GubCombat` gates both ways — so the only overlap there can be is the
	# drink's own 0.18 s fade-out, which a cancelled channel leaves running while
	# the Gub is free to act again on the same frame. In that window what the
	# player has just done has to win over what they have just stopped doing, and
	# every weapon above this line is what they have just done.
	tree.connect_node("drink", 0, "roll")
	tree.connect_node("drink", 1, "drink_rate")
	tree.connect_node("draw_seek", 0, "draw_clip")
	tree.connect_node("draw", 0, "drink")
	tree.connect_node("draw", 1, "draw_seek")
	tree.connect_node("loose", 0, "draw")
	tree.connect_node("loose", 1, "loose_clip")
	tree.connect_node("cast_rate", 0, "cast_clip")
	# The draw and its loose sit *under* the two windups, and the order is the
	# same argument the throw-over-cast order is (D-064): only one of the three
	# can be running, the gates see to that, and the one that must win a tie is
	# the one whose weapon is in the hand on the frame the tie happens. A Gub
	# that stops being the Elder has a spear again immediately; a Gub that starts
	# a throw was not drawing a bow a frame ago.
	tree.connect_node("cast", 0, "loose")
	tree.connect_node("cast", 1, "cast_rate")
	tree.connect_node("throw_rate", 0, "throw_clip")
	# The throw sits *over* the cast rather than beside it, and the order is not
	# arbitrary even though only one of the two is ever fired per click: a Gub
	# that stops being the Elder is holding a spear again on the same frame
	# (D-038), so the shot that must win a tie is the spear's.
	tree.connect_node("throw", 0, "cast")
	tree.connect_node("throw", 1, "throw_rate")
	tree.connect_node("swing_rate", 0, "swing_clip")
	# The swing sits **over** everything, which is the one place in this graph
	# where the order is forced rather than argued (D-068). The four nodes under
	# it are layers filtered to the upper body; this is a whole pose. A full-body
	# shot underneath a masked one would have the mask's clip win on every bone
	# the mask names, so a swing fired a frame after a throw would spin the legs
	# and keep the arms throwing. Nothing can start a swing during any of them
	# and nothing can start any of them during a swing — `GubCombat` gates both
	# ways — so the only overlap there can be is a fade, and in a fade the thing
	# the player has just committed 1.867 s to has to win.
	tree.connect_node("swing", 0, "throw")
	tree.connect_node("swing", 1, "swing_rate")
	tree.connect_node("output", 0, "swing")
	return tree


## The nine-point locomotion plane (D-066).
##
## Positions are the Gub's velocity **in its own frame**, x to its right and y
## forward, in game metres per second; every point plays its own clip at the
## rate that plants its feet at its own position. Idle sits at the origin at
## rate 1.
##
## The triangles are written out rather than left to `auto_triangles`, and that
## is not distrust of Delaunay — it is that every one of these nine points lies
## on one of the two axes, so a third of the triples in the set are exactly
## collinear and which of them survive a degenerate triangulation is not
## something this graph should be finding out at runtime. Twelve triangles, four
## quadrants of three: the inner wedge from Idle out to the two walks, and the
## outer trapezoid between the two walks and the two runs, split on the diagonal
## from the forward-or-back walk to the sideways run.
##
## The shape of it is a **diamond** and not a square — there are no diagonal
## clips to put at its corners — so the two rings are `|x| + |y| = WALK_SPEED`
## and `|x| + |y| = RUN_SPEED`, and a velocity handed in raw would be on the
## wrong ring at every bearing except along an axis. `_body_relative` is where
## that is dealt with, and the paragraph over it is the measurement of why.
##
## What the shape costs, said out loud: a full-speed diagonal is a half-and-half
## blend of two run cycles rather than a clip of its own, so what cannot be said
## in this space is "diagonally, but slowly" differently from "diagonally, flat
## out" in the outermost ring — both land on the same hull edge and differ only
## in where along it. Closing that is four more clips nobody has.
func _locomotion(player: AnimationPlayer) -> AnimationNodeBlendSpace2D:
	var stand := AnimationNodeBlendSpace2D.new()
	stand.min_space = Vector2(-Gub.RUN_SPEED, -Gub.RUN_SPEED)
	stand.max_space = Vector2(Gub.RUN_SPEED, Gub.RUN_SPEED)
	stand.x_label = "right"
	stand.y_label = "forward"
	stand.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	# Before the points, so nothing is triangulated on the way in and then
	# thrown away: the twelve below are the whole of it.
	stand.auto_triangles = false
	# Every point keeps running whether or not it carries any weight. See
	# `_blend2` for why, and note that it matters most here: without it the Run
	# point sits on frame 0 for the whole match until the first sprint, and that
	# sprint cross-fades a *static* run frame into a mid-stride walk. With nine
	# points instead of three there are eight cycles waiting to be entered for
	# the first time rather than two.
	stand.sync = true

	var walk := Gub.WALK_SPEED
	var run := Gub.RUN_SPEED
	# The order is the triangle table's: origin, then forward, back, right, left,
	# walk before run in each.
	stand.add_blend_point(_cycle(player, "Idle", 0.0, 0.0), Vector2.ZERO, -1, "idle")
	stand.add_blend_point(_cycle(player, "Walk", walk, Gub.AUTHORED_WALK),
		Vector2(0.0, walk), -1, "walk")
	stand.add_blend_point(_cycle(player, "Run", run, Gub.AUTHORED_RUN),
		Vector2(0.0, run), -1, "run")
	stand.add_blend_point(_cycle(player, "WalkBack", walk, Gub.AUTHORED_WALK_BACK),
		Vector2(0.0, -walk), -1, "walk back")
	stand.add_blend_point(_cycle(player, "RunBack", run, Gub.AUTHORED_RUN_BACK),
		Vector2(0.0, -run), -1, "run back")
	stand.add_blend_point(
		_cycle(player, "StrafeWalkRight", walk, Gub.AUTHORED_STRAFE_WALK_RIGHT),
		Vector2(walk, 0.0), -1, "walk right")
	stand.add_blend_point(
		_cycle(player, "StrafeRight", run, Gub.AUTHORED_STRAFE_RIGHT),
		Vector2(run, 0.0), -1, "run right")
	stand.add_blend_point(
		_cycle(player, "StrafeWalkLeft", walk, Gub.AUTHORED_STRAFE_WALK_LEFT),
		Vector2(-walk, 0.0), -1, "walk left")
	stand.add_blend_point(
		_cycle(player, "StrafeLeft", run, Gub.AUTHORED_STRAFE_LEFT),
		Vector2(-run, 0.0), -1, "run left")

	for quadrant: Array in LOCOMOTION_QUADRANTS:
		var near: int = quadrant[0]     # the walk on the forward/back axis
		var far: int = quadrant[1]      # the run on the same axis
		var side_near: int = quadrant[2]  # the walk on the sideways axis
		var side_far: int = quadrant[3]   # the run on the same axis
		stand.add_triangle(IDLE_POINT, near, side_near)
		stand.add_triangle(near, side_near, side_far)
		stand.add_triangle(near, side_far, far)
	return stand


## The order `_locomotion` adds its blend points in, so the triangle table below
## can name them.
const IDLE_POINT := 0

## The four quadrants of the locomotion plane, each as
## [forward-or-back walk, the run beside it, sideways walk, the run beside it].
## Point indices into the order `_locomotion` adds them in.
const LOCOMOTION_QUADRANTS: Array = [
	[1, 2, 5, 6],   # forward-right
	[1, 2, 7, 8],   # forward-left
	[3, 4, 5, 6],   # back-right
	[3, 4, 7, 8],   # back-left
]


## A two-way blend whose *unweighted* side keeps running.
##
## That is what `sync` buys, and it is not a nicety. With `sync` at its default
## false, Godot freezes any input a blend node is not currently listening to:
## measured on this graph, after 1.5 s of walking the `stand` space reported
## `run/current_position` 0.0000 while the walk point was mid-stride, and the
## whole `crouch` space sat on frame 0 the entire time. So every entry into a
## cycle that had not been weighted yet — the first sprint of a round, the first
## crouch — cross-faded a *static* frame into a moving one over 4 frames, which
## is a foot scissor and then a pop as the frozen clip finally starts. Blending
## two cycles that are both mid-stride is at worst a phase mismatch; blending
## against a still frame is a visible fault, and it was the transition
## complaint this rework exists to answer.
##
## The three OneShots need `sync` for a related but different reason — keeping
## the branch *underneath* them alive while they play; see `_shot`.
func _blend2() -> AnimationNodeBlend2:
	var blend := AnimationNodeBlend2.new()
	blend.sync = true
	return blend


## One looping locomotion cycle, played at exactly the rate that keeps its feet
## planted at the game speed its blend point sits at.
##
## The rate lives in a custom timeline: `stretch_time_scale` makes the node play
## its clip in `timeline_length` seconds instead of its own length, so
## `length / rate` seconds of timeline is a playback rate of `rate`. Pass a
## speed of 0 for the two standing poses, which have no rate to match.
##
## `loop_mode` is set here rather than trusted from the asset. With
## `use_custom_timeline` on, the node's own loop mode wins, which means the
## thing that guarantees a run cycle cycles is this graph and not a flag in a
## `.import` file that a rebuild could drop.
func _cycle(player: AnimationPlayer, clip: String, game_speed: float,
		authored_speed: float) -> AnimationNodeAnimation:
	var rate := 1.0
	if authored_speed > 0.0 and game_speed > 0.0:
		rate = game_speed / authored_speed
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	node.use_custom_timeline = true
	node.start_offset = 0.0
	node.timeline_length = player.get_animation(clip).length / rate
	node.stretch_time_scale = true
	node.loop_mode = Animation.LOOP_LINEAR
	return node


## A window of a clip, played once at authored speed and held on its last frame.
##
## `stretch_time_scale` has to be **false** here. True gives you a playback rate
## but throws the window's far end away: the node plays from `start_offset` to
## the clip's own end at `clip length / timeline_length`, so a 1.6 s window into
## a 3.8 s clip would run on for another 1.7 s of clip nobody asked for. That is
## why the throw's rate is a separate TimeScale node and not a stretched window.
func _window(clip: String, from: float, to: float) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	node.use_custom_timeline = true
	node.start_offset = from
	node.timeline_length = to - from
	node.stretch_time_scale = false
	node.loop_mode = Animation.LOOP_NONE
	return node


## A clip with no timeline of its own, because something else says what time it
## is every frame. Both air poses are these, and the seeks they are given are
## therefore in the clip's own seconds.
##
## `loop_mode` is stated for the reader and does nothing: a node's loop mode is
## only consulted when it has a custom timeline, so these two take the clip's,
## which the pipeline exports as LOOP_NONE. It would not matter either way —
## a seek past the end clamps.
func _scrubbed(clip: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	node.use_custom_timeline = false
	node.loop_mode = Animation.LOOP_NONE
	return node


func _shot(fade_in: float, fade_out: float) -> AnimationNodeOneShot:
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = fade_in
	shot.fadeout_time = fade_out
	# Blend, not add: these are whole poses, not offsets from whatever the body
	# was already doing.
	shot.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
	# Keeps the branch *underneath* running while this shot is at full weight.
	# Measured, because it is not obvious: with `sync` at its default false and
	# no filter, Godot stops a zero-weight input dead — a 2 s one-shot advanced
	# its own input 0 by 0.00 s. With `sync` true it advanced by the full 2.00 s.
	# So without this a run cycle would freeze for the length of every landing
	# absorb and come back a third of a stride behind the feet it is supposed to
	# be planting. (A *filtered* shot keeps its input 0 alive either way, because
	# the tracks outside the filter still carry weight — so the throw would work
	# without this and the three full-body shots would not.)
	shot.sync = true
	return shot


## The draw is a layer for the same reason the two windups are, and it is a
## `Blend2` rather than a OneShot because it is *held*: a one-shot has a length
## and this has a duration nobody knows until the archer lets go. Filtered to
## the same bones, so the legs go on running, walking or hanging in the air
## under a Gub at full draw — which is the whole of "every attack works in the
## air" for this weapon and costs nothing (D-065).
##
## `sync` comes from `_blend2` and matters here for its usual reason: the branch
## underneath has to keep running while the draw is at full weight, or a Gub
## that draws for a second comes out of it a second behind its own feet.
func _upper_body_blend() -> AnimationNodeBlend2:
	var blend := _blend2()
	if _skeleton_path.is_empty():
		return blend
	blend.filter_enabled = true
	for bone in UPPER_BODY_BONES:
		blend.set_filter_path(NodePath("%s:%s" % [_skeleton_path, bone]), true)
	return blend


## The throw, the cast and the drink are layers, not states, and the filter is
## what makes them so: only `UPPER_BODY_BONES` take the clip, and the legs stay
## in whatever the blend below is producing. Which is also the whole of "you can
## drink in the air" (D-067): the legs keep the air-arc pose under a Gub raising
## a bottle, and it cost nothing to arrange. Which is most of why the Elder can be given a
## clip that turns its whole body through 106 deg without the legs going
## anywhere — Hips and Spine are outside the filter (D-029), so the pelvis keeps
## facing the crosshair and what arrives is the cast from the middle spine up.
func _upper_body_shot(fade_in: float, fade_out: float) -> AnimationNodeOneShot:
	var shot := _shot(fade_in, fade_out)
	if _skeleton_path.is_empty():
		return shot
	shot.filter_enabled = true
	for bone in UPPER_BODY_BONES:
		shot.set_filter_path(NodePath("%s:%s" % [_skeleton_path, bone]), true)
	return shot


# ------------------------------------------------------------------ update ---

func _process(delta: float) -> void:
	if _body == null or tree_root == null:
		return

	var flat := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	set(P_STAND_MOVE, _body_relative(flat))
	set(P_CROUCH_SPEED, clampf(flat.length(), 0.0, Gub.CROUCH_SPEED))

	_track_airtime(delta)
	_track_slide()
	_track_draw()
	_scrub_air()

	_stance = move_toward(_stance, 1.0 if _body.is_crouching() else 0.0,
		STANCE_BLEND_SPEED * delta)
	var airborne_target := 0.0 if _grounded else 1.0
	var airborne_speed := AIRBORNE_RISE_SPEED if airborne_target > _airborne \
		else AIRBORNE_FALL_SPEED
	_airborne = move_toward(_airborne, airborne_target, airborne_speed * delta)
	# Moved toward 0 while grounded rather than snapped on touchdown: the dive
	# pose has to be allowed to fade out of the air branch instead of turning
	# into the jump pose on the frame the feet land.
	var dive_target := 1.0 if (_dived and not _grounded) else 0.0
	_dive_blend = move_toward(_dive_blend, dive_target, DIVE_BLEND_SPEED * delta)

	# The draw, every frame, on every peer's copy of every Gub — which is the
	# point of it. `draw_fraction()` answers off the replicated float on a remote
	# Gub and off the local one on your own, exactly as `is_crouching` does, so
	# there is one code path for the archer and for the seven people who need to
	# see how far back that string is (D-065).
	_draw_blend = move_toward(_draw_blend, 1.0 if _body.is_drawing() else 0.0,
		DRAW_BLEND_SPEED * delta)
	set(P_DRAW_SEEK, draw_time(_body.draw_fraction()))
	set(P_DRAW, _draw_blend)
	# The same speed in as the draw pose itself, so the torso arrives with the
	# bow rather than after it, and the same speed out — which through a loose
	# starts a fifth of a second later than the draw's does. See `_aim_blend`.
	var aiming := _body.is_drawing() or bool(get(P_LOOSE_ACTIVE))
	_aim_blend = move_toward(_aim_blend, 1.0 if aiming else 0.0,
		DRAW_BLEND_SPEED * delta)
	# The carried bow's tilt comes off the same weight, and it is set from here
	# rather than from `GubCombat._tick_draw` beside the string for a reason
	# that is about what the number *is*: the string is bent by the charge,
	# which is the player's input, and the bow is tilted by how far the arm has
	# come up, which is this graph's own blend and is not knowable anywhere else
	# (D-066). It runs on every peer's copy of every Gub, so a remote archer
	# brings its bow up out of the carry exactly as the local one does.
	if _body.held_gear != null:
		_body.held_gear.set_carry(1.0 - _aim_blend)

	set(P_STANCE, _stance)
	set(P_AIRBORNE, _airborne)
	set(P_DIVE, _dive_blend)


## A horizontal world velocity turned into a position in the locomotion plane
## (D-066): x to the Gub's right, y forward.
##
## Off `body_yaw` and not off the node's transform: `_model_root` is turned by
## the same yaw but the Gub mesh is authored facing +Z and counter-rotated 180°
## inside `gub.tscn`, so reading a basis here would be reading that
## compensation as well. `facing()` is the accessor that already means "the way
## the Gub looks" on both sides of that, and it answers off the replicated yaw
## on a remote Gub — which is the whole reason the sideways pose arrives on
## seven other screens for nothing.
##
## **It is not simply the velocity, and the difference is the shape of the
## space.** There are four clips on the compass and none on the diagonals, so
## the plane's rings are **diamonds** rather than circles: the four walk points
## are the corners of `|x| + |y| = WALK_SPEED` and the four runs the corners of
## `|x| + |y| = RUN_SPEED`. A velocity written in straight is therefore on the
## wrong ring everywhere except on an axis — a Gub walking diagonally at 2.3 m/s
## lands 3.25 out on the L1 measure, which is past the walk ring entirely and
## into the band where the *run* cycles carry weight. Measured, that was the
## worst skate anywhere in the space: 1.20 of body speed on a walk diagonal,
## against 0.15 walking straight forward, with run clips blended into a walk.
##
## So the vector is rescaled to put its **L1 norm at its own speed**, which
## leaves the direction alone and moves the point onto the ring that means that
## speed. Every ring is then a constant-speed ring at every bearing, which is
## what the blend points were placed to mean.
##
## The component clamp that survives is for the Elder: a boosted Gub runs at
## 7.3 m/s (D-040) and there is no clip out there, so it sits on the run ring
## and plays the run cycles slightly slow, which is the trade `Gub.target_speed`
## already documents for the one-dimensional space.
func _body_relative(flat: Vector3) -> Vector2:
	var forward := _body.facing()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var move := Vector2(flat.dot(right), flat.dot(forward))
	var manhattan := absf(move.x) + absf(move.y)
	if manhattan > 0.0001:
		move *= move.length() / manhattan
	return Vector2(
		clampf(move.x, -Gub.RUN_SPEED, Gub.RUN_SPEED),
		clampf(move.y, -Gub.RUN_SPEED, Gub.RUN_SPEED))


## Where the body is in its arc, turned into an absolute clip time.
##
## `phase` is 0 leaving the ground, 0.5 at the apex and 1 about to land, and it
## is read off the vertical velocity rather than off a stopwatch — which is what
## makes a fall work with no extra clip. A Gub that walks off a ledge has vy of
## about 0, so it starts at phase 0.5 (the apex pose) and falls through to the
## pre-landing pose; one that is falling faster than it could ever have launched
## holds phase 1.
static func arc_time(vy: float, launch: float, from: float, apex: float,
		to: float) -> float:
	var phase := clampf(0.5 * (1.0 - vy / maxf(launch, 0.01)), 0.0, 1.0)
	if phase < 0.5:
		return lerpf(from, apex, phase / 0.5)
	return lerpf(apex, to, (phase - 0.5) / 0.5)


## Both air clips are told what time it is every frame, whether or not anything
## is looking at them. A `TimeSeek` at zero weight still takes its request — the
## branch is processed regardless, which is the same fact that made D-026
## possible — so the pose is already correct on the frame the airborne blend
## starts to come up, and there is no take-off event to miss.
##
## On the ground, vertical velocity stops being a phase: `move_and_slide` zeroes
## it on touchdown, and `vy == 0` means *apex*. Read literally that snaps both
## air poses back to the top of the leap on the one frame the airborne blend is
## still most of the picture — a 0.48 m hip pop and a 0.10 m foot pop, measured.
## So a grounded Gub holds the about-to-land pose instead, which is also the pose
## the landing one-shots pick the body up from, so the hand-over is continuous.
func _scrub_air() -> void:
	if _grounded:
		set(P_AIR_ONE_SEEK, JUMP_ONE_END)
		set(P_AIR_TWO_SEEK, JUMP_TWO_END)
		return
	# `vertical_speed()` and not `velocity.y`: on a remote Gub the replicated
	# value is a physics tick fresher than the copy in `velocity`. See `Gub`.
	var vy := _body.vertical_speed()
	# `jump_velocity()` rather than the constant, because the Elder's boost
	# multiplies it (D-040). Against a fixed 9.0 a Gub that left the ground at
	# 11.25 spends the first fifth of its climb clamped to the take-off pose and
	# reaches the apex pose a fifth of a metre early — the arc is a *ratio*, so
	# it has to be measured against the speed this leap actually started at. It
	# is live rather than recorded on take-off for the same reason
	# `elder_scale` is: the robe is on every peer's copy of the Gub, so a remote
	# one is scrubbed by the same number as the local one.
	set(P_AIR_ONE_SEEK, arc_time(vy, _body.jump_velocity(),
		JUMP_ONE_START, JUMP_ONE_APEX, JUMP_ONE_END))
	set(P_AIR_TWO_SEEK, arc_time(vy, _dive_launch,
		JUMP_TWO_START, JUMP_TWO_APEX, JUMP_TWO_END))


## Airtimes, from the two replicated serials and the grounded flag.
func _track_airtime(delta: float) -> void:
	# The serials are the only news that cannot arrive late, so they open the
	# airtime and the grounded flag only confirms it.
	if _body.sync_jump_serial != _jump_serial:
		_jump_serial = _body.sync_jump_serial
		_open_airtime(false)
	if _body.sync_dive_serial != _dive_serial:
		_dive_serial = _body.sync_dive_serial
		_open_airtime(true)

	var grounded := _body.is_grounded()
	if grounded != _grounded:
		_grounded = grounded
		if grounded:
			_close_airtime()
		elif not _airtime_open:
			# No serial: walked off a ledge, or was knocked off one.
			_open_airtime(false)
	if not _grounded and _airtime_open:
		_airtime += delta


## Start tracking a fresh airtime. A jump clears the dive flag because a new
## jump is a new airtime; a dive sets it, and records the speed its arc is
## measured against — `Gub._dive` has already added DIVE_UP_VELOCITY to the
## vertical velocity by the time this sees it.
##
## The launch speed is read exactly once, on the frame the serial changes, and
## the whole leap is then measured against it — so this is the one reader in the
## file that cannot afford a stale value, and it asks `vertical_speed()` for the
## replicated one. Read off `velocity` instead, a remote dive out of a rising
## jump scaled its arc against the *pre-dive* climb: phase stuck at 0 (the
## take-off pose) for the first third of the leap and hit 1 (feet down, about to
## land) while the body was still over a metre up.
func _open_airtime(dived: bool) -> void:
	_airtime_open = true
	_airtime = 0.0
	if dived:
		_dived = true
		_dive_launch = maxf(_body.vertical_speed(), Gub.DIVE_UP_VELOCITY)
	else:
		_dived = false


## Touchdown. Fire the roll if the airtime was a dive, the absorb if it was not,
## and nothing at all if the feet were barely off the ground.
##
## `_dived` is deliberately not cleared here — `_process` fades the dive pose out
## of the air branch while grounded, and the next take-off clears the flag.
func _close_airtime() -> void:
	if _airtime_open and _airtime >= LAND_MIN_AIRTIME:
		set(P_ROLL if _dived else P_LAND,
			AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_airtime_open = false
	_airtime = 0.0


## Drop the airtime without landing it. `_grounded` is deliberately left alone:
## `revive_at` moves the body without running `move_and_slide`, so `is_on_floor()`
## is not yet true at the spawn point, and believing it would put the Gub into
## the air pose for the first few frames of its new life.
func _forget_airtime() -> void:
	_airtime_open = false
	_airtime = 0.0
	_dived = false
	_jump_serial = _body.sync_jump_serial
	_dive_serial = _body.sync_dive_serial


## The loose, fired off the frame the replicated draw ends (D-065).
##
## **No message starts this animation**, which is the whole of why a remote
## Gub's bow snaps on the same frame as the string it is attached to. The draw
## is a float on the body; when it goes out of band the string is gone; so every
## peer reaches the same conclusion from the same number on the same frame, and
## there is no relay that could arrive at a different one. That is D-026's
## "remote Gubs see it because a number changed, not because a message arrived",
## which is the same argument that made the jump serials serials.
##
## **A cancelled draw fires it too**, and that is kept rather than guarded
## against: walking onto a letter card mid-draw takes the bow away (D-035) and
## what the hands then do is let go of a string with nothing on it. The pack
## this clip came from was shopped for with "ideally a dry-fire or a recover" in
## the list and did not have one; this is that, for free, on the one occasion
## the game needs it.
func _track_draw() -> void:
	var drawing := _body.is_drawing()
	if drawing == _drawing:
		return
	_drawing = drawing
	if not drawing:
		play_loose()


## The slide is the one event with an end as well as a beginning: the clip is
## 1.6 s long and the physical slide can be cut short by a wall, a ledge or the
## speed dropping, so it is faded out rather than left to finish.
func _track_slide() -> void:
	var sliding := _body.is_sliding()
	if sliding == _sliding:
		return
	_sliding = sliding
	if sliding:
		set(P_SLIDE, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	elif bool(get(P_SLIDE_ACTIVE)):
		set(P_SLIDE, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


# -------------------------------------------------------------- public API ---

## Fire the throw animation. Called on every peer, so remote Gubs visibly throw,
## and re-firing mid-throw restarts it from the top of the window.
##
## `rate` is the one thing about this clip that is not fixed, because the Elder's
## release is not fixed: a bolt that leaves 0.2 s after the click needs the arm
## to have got there by 0.2 s (D-040). It is set on the TimeScale node *before*
## the one-shot is fired, so the very first frame of the throw is already playing
## at the rate the release was derived from — set afterwards, the fade-in would
## run at whatever the last thrower left behind.
##
## The default is the spear's, so every existing caller is unchanged and a Gub
## that stops being the Elder mid-match throws at the authored speed again
## without anything having to remember to put it back.
func play_throw(rate: float = THROW_RATE) -> void:
	if tree_root == null:
		return
	set(P_THROW_RATE, maxf(rate, 0.01))
	set(P_THROW, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Fire the Elder's cast. The same call as `play_throw` on the other one-shot,
## and made by the same line of `GubCombat._play_windup` on every peer (D-064).
##
## There is no default rate, and that is the statement: the throw has an
## authored speed of its own and the cast does not. Every cast there will ever
## be is played at whatever `cast_rate_for_release` makes of
## `MatchConfig.lightning_delay`, so a default here would only be a number
## waiting to be played when somebody forgets to ask the dial.
func play_cast(rate: float) -> void:
	if tree_root == null:
		return
	set(P_CAST_RATE, maxf(rate, 0.01))
	set(P_CAST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Fire the loose. Called on every peer on the frame the string is let go, and
## re-firing mid-loose restarts it, which is what a second shot out of a fast
## recharge should do.
##
## No rate, and for the opposite reason `play_cast` has none: the cast has no
## authored speed to fall back on, and this one has nothing that wants it to be
## anything else. A string is as fast as a string.
func play_loose() -> void:
	if tree_root == null:
		return
	set(P_LOOSE, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Start the drink, at whatever rate makes it take the channel's own length
## (D-067). Called on every peer by `GubCombat._do_drink_potion`, the same way
## `_play_windup` is, so the rate is worked out on each machine from the same
## replicated dial rather than being sent.
##
## No default rate, for `play_cast`'s reason: the channel is a lobby dial and a
## default here would be a number waiting to be played the day somebody forgets
## to ask it.
func play_drink(rate: float) -> void:
	if tree_root == null:
		return
	set(P_DRINK_RATE, maxf(rate, 0.01))
	set(P_DRINK, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Put the bottle down early. The one one-shot in this file that is ever
## *stopped* rather than left to run out, because it is the one whose length is
## a promise the player can break: a channel interrupted at 0.4 s has to look
## interrupted, and an arm that went on lifting a bottle to a mouth nobody was
## drinking from any more would be the clearest possible lie.
##
## FADE_OUT and not ABORT: abort cuts the layer's weight on the frame, which is
## an arm teleporting back to the Gub's side. The fade is DRINK_FADE_OUT, the
## same 0.18 s a finished drink leaves over, so a cancelled drink and a
## completed one hand back to the body the same way and only the pose they hand
## back from differs.
func stop_drink() -> void:
	if tree_root == null:
		return
	set(P_DRINK, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


## Fire the great sword's swing. Called on every peer by
## `GubCombat._begin_swing`, the same way `_play_windup` is, so a remote Gub
## visibly spins — and re-firing mid-swing restarts it from the top of the
## window, which is what a chained swing out of a short recharge should do
## (D-068).
##
## `rate` is SWING_RATE and there is no caller that passes anything else; it is a
## parameter at all so that the graph is playing whatever the release time was
## derived from rather than whatever was left on the node, which is the mistake
## `play_throw`'s own comment describes.
func play_swing(rate: float = SWING_RATE) -> void:
	if tree_root == null:
		return
	set(P_SWING_RATE, maxf(rate, 0.01))
	set(P_SWING, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## True from the moment a windup is fired until its fade-out has finished, or
## while a bow is being drawn — the throw's, the Elder's cast, or the draw,
## because what asks is the camera and what the camera wants to know is whether
## this Gub is in the middle of an attack it should be kept facing the crosshair
## through. One question, three answers.
##
## The draw is the answer that had to be added by hand rather than falling out
## of an `active` flag, because it is the one attack with no one-shot in it: a
## `Blend2` has no "is it running", only a weight, and a weight that is on its
## way down is a Gub whose shot has already gone. So it asks the body, which is
## the same thing `_process` scrubs the pose from.
##
## **The swing is deliberately not one of the answers either** (D-068), and for
## a harder reason than the drink's. It *is* an attack, and the camera would
## dearly like to keep the body on the crosshair through it — but the swing
## commits its direction at the click and `Gub._handle_movement` then drives the
## body along it for 1.867 s. A yaw that went on tracking the view would slide a
## Gub one way while it was drawn going another, and would hand a player a way to
## re-point an advance they had already paid for. `Gub._face` refuses the turn
## from its end as well, so this answering yes would only be the camera asking
## for something it could not have.
##
## **The drink is deliberately not one of the answers** (D-067). It is the one
## layered thing here that is not an attack, so there is nothing for the camera
## to keep pointed at a crosshair: a Gub drinking is not aiming at anybody, and
## turning its body onto the reticle for two seconds would make the one action
## in the game that means "I am not fighting" look exactly like the three that
## mean the opposite.
func is_throwing() -> bool:
	if tree_root == null:
		return false
	if _body != null and _body.is_drawing():
		return true
	return bool(get(P_THROW_ACTIVE)) or bool(get(P_CAST_ACTIVE)) \
		or bool(get(P_LOOSE_ACTIVE))


## How far the torso is turned to the crosshair, 0 to 1 (D-066). Read by
## `GubAim`, which is the only thing that asks.
##
## A weight and not a boolean, for the same reason `_airborne` is: a bow coming
## up over a run is a torso coming round over the same twelfth of a second, and
## a modifier switched on would be a shoulder snapping through ninety degrees on
## one frame.
func aim_blend() -> float:
	return _aim_blend


## Airborne, in an airtime a dive was spent in.
func is_diving() -> bool:
	return _dived and not _grounded
