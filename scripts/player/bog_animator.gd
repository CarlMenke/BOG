class_name BogAnimator
extends AnimationTree
## Drives the BOG's skeleton from the state of the `Bog` body above it, out of
## the shared clip library and the markers on its clips (D-098).
##
## **Ground poses come from speed, air poses come from the arc, events are
## one-shots.** Nothing in this tree runs a clock that is not either (a) a
## looping locomotion cycle, (b) a OneShot that restarts every time it is fired,
## or (c) a node that is scrubbed to an absolute time every frame. An
## `AnimationNodeAnimation` sitting in a blend runs its own clock from the moment
## the tree starts whether or not anything is listening, reaches its last frame
## and stops there for the rest of the round (D-026); every clip in here is one
## of the three kinds, so that bug cannot be written into this graph without
## deleting one of them first.
##
## **This file carries no clip time and no authored speed.** Every event it
## needs — where the spear leaves the hand, where the string goes, where the
## blade comes through, where a dive leaves the ground and where its roll ends —
## is a marker on the clip, placed once against the clip itself (D-097), and
## every playback rate is the game's speed over the clip's own `authored_speed`
## metadata (D-095). Changing a clip means re-importing it; it never means
## re-measuring this file.
##
## The graph, bottom to top:
##
##     stand      BlendSpace2D   nine points over the body-relative velocity
##     sword      BlendSpace2D   the great sword's own nine, while it is carried
##     aim        BlendSpace2D   the archer's five, while the bow is up
##     loco       Transition     which of the three, by weapon and by aiming
##     crouch     BlendSpace2D   the crouch's five, over the same velocity
##     stance     Blend2         loco / crouch, by how crouched
##     air_loop   Animation(AirLoop), a cycle: the airborne pose of a fall or a standing jump
##     leap       Animation(RunJump) behind leap_seek, scrubbed by the arc of a running jump
##     slide_leap Animation(SlideJump) behind slide_leap_seek, the same for a slide jump
##     leap_kind  Blend2         leap / slide_leap, by which take-off this was
##     air_kind   Blend2         air_loop / leap_kind
##     dive_clip  Animation(Roll) behind dive_seek, scrubbed by the arc of a dive
##     air        Blend2         air_kind / dive
##     grounded   Blend2         stance / air, by how airborne
##     takeoff    OneShot        JumpStart, full body, on a standing jump
##     slide      OneShot        Slide between its `down` and `up`, full body
##     land       OneShot        Land, full body: a light touchdown
##     land_hard  OneShot        LandHard's absorb, full body: a heavy one
##     roll       OneShot        Roll from its `land` to its `up`, full body
##     carry_pick Transition     SpearCarry / BowCarry / SwordCarry / Idle, by the lobby pick or the holster
##     carry      Blend2         the carry pose over the plane, upper body only
##     draw_clip  Animation(BowReload) behind draw_seek, scrubbed by the charge
##     draw       Blend2         the pull over the aim plane, upper body only
##     loose      OneShot        BowLoose, upper body only
##     drink      OneShot        Drink between `raise` and `done`, upper body, at the channel's rate
##     cast       OneShot        Cast from `windup` past `release`, upper body, at the dial's rate
##     throw      OneShot        Throw from `windup` past `release`, upper body, at THROW_RATE
##     punch      OneShot        Punch past its `hit`, upper body, at PUNCH_RATE
##     slash_pick Transition     SwordCombo's three windows, one per slash
##     slash      OneShot        the picked window, upper body, over the sword plane
##     swing      OneShot        SwordSpin, **full body**
##     emote      Blend2         swing / Twerk, **full body**, by how emoting
##     output   <- emote
##
## Three planes and a switch where there was one plane and a carry layer: the
## great sword set and the archer set each have their own walks, runs and
## strafes, and a BOG carrying two metres of blade or holding a bow up walks
## the way those clips walk (design item 5). The carry layer survives for the
## one weapon whose carry is only an upper-body pose, the bow at rest.
##
## The jump is three pieces (design item 7). A standing jump fires the take-off
## one-shot and hangs in the air loop; a running jump is the leap clip scrubbed
## by the arc, exactly as the dive is the roll clip scrubbed by its own; and a
## touchdown fires the light landing, the heavy one if the body came down fast,
## or the roll if the airtime was a dive.
##
## One code path for the BOG you are driving and the seven you are watching:
## everything read here comes either from a `Bog` accessor that already answers
## with replicated values on a remote BOG (`is_grounded`, `is_sliding`,
## `is_crouching`, `is_drawing`, `vertical_speed`, `velocity`) or from a
## replicated serial counter (`sync_jump_serial`, `sync_dive_serial`,
## `sync_slide_jump_serial`).

# ------------------------------------------------------------- the library ---

## Where every clip this graph plays lives (D-095). The body's own
## AnimationPlayer carries the same library, put there by `tools/import_body.gd`;
## this handle is for the static readers below, which run before any body
## exists.
const LIBRARY := "res://art/generated/bog_clips.res"
static var _library: AnimationLibrary = load(LIBRARY)

## Every clip this graph names, by role. Checked once in `_ready`, because a
## re-import that dropped one would otherwise show up as a BOG that never moves.
const REQUIRED_CLIPS: Array[String] = [
	"Idle", "Walk", "Run", "WalkBack", "RunBack",
	"StrafeWalkLeft", "StrafeWalkRight", "StrafeLeft", "StrafeRight",
	"CrouchIdle", "CrouchWalk", "CrouchWalkBack", "CrouchStrafeLeft", "CrouchStrafeRight",
	"SwordCarry", "SwordWalk", "SwordRun", "SwordWalkBack", "SwordRunBack",
	"SwordStrafeWalkLeft", "SwordStrafeWalkRight", "SwordStrafeLeft", "SwordStrafeRight",
	"BowCarry", "BowAim", "BowAimWalk", "BowAimWalkBack", "BowAimStrafeLeft", "BowAimStrafeRight",
	"BowDraw", "BowReload", "BowLoose",
	"JumpStart", "AirLoop", "RunJump", "Land", "LandHard", "Roll", "Slide",
	"Throw", "Cast", "SwordSpin", "SwordCombo", "Drink",
	"SpearCarry", "Twerk",
]

## The slide jump's clip, and the clip it borrows until that one exists. **Not**
## in `REQUIRED_CLIPS`: see `clip_or`. `RunJump` is the honest stand-in — it is
## the other leap scrubbed by the same arc between the same three markers, so
## the move is complete and only its drawing is provisional.
const SLIDE_JUMP_ROLE := "SlideJump"
const SLIDE_JUMP_FALLBACK := "RunJump"

## The punch's clip, and the clip it borrows until that one exists. **Not** in
## `REQUIRED_CLIPS` either, for `SLIDE_JUMP_ROLE`'s reason exactly: the move is
## designed, wired and playable, and the take that draws it has not been picked
## off Mixamo yet (`assets/source/clips.json` carries the row and the query).
##
## `Cast` is the stand-in the feel round chose, and it is an honest one: a
## one-handed forward thrust from the shoulder, which is what a punch is, with a
## `release` marker sitting exactly where a `hit` marker would go. That last
## part is why the marker's *name* is resolved beside the role below — the
## fallback's event is called something else, and a punch that read `hit` off
## `Cast` would `push_error` once a frame.
const PUNCH_ROLE := "Punch"
const PUNCH_FALLBACK := "Cast"


## A clip by role, from the library. Loud on a missing one, because every
## caller below has already decided the clip exists.
static func clip(role: String) -> Animation:
	var anim := _library.get_animation(role) if _library != null and _library.has_animation(role) else null
	if anim == null:
		push_error("BogAnimator: the clip library has no '%s'" % role)
	return anim


## The role to *play* for `role`, which is `role` itself when the library has
## it and `fallback` when it does not. Returns a role name and not an
## `Animation`, because that is what the graph is built out of.
##
## The one crack in "every clip this graph names is in `REQUIRED_CLIPS`", and it
## is deliberate: a move can be designed, wired and shipped before the take that
## draws it has been picked off Mixamo (`assets/source/clips.json` carries the
## row and the query). A missing *required* clip is a BOG that never moves and
## has to fail the gate; a missing optional one is a move that plays somebody
## else's clip until the FBX lands, and the only thing it owes anybody is to say
## so — once, at `_ready`, never per frame.
static func clip_or(role: String, fallback: String) -> String:
	return role if _library != null and _library.has_animation(role) else fallback


## A marker's time on a clip, in the clip's own seconds (D-097). The one way
## this file learns where anything happens.
static func marker(role: String, event: String) -> float:
	var anim := clip(role)
	if anim == null or not anim.has_marker(event):
		push_error("BogAnimator: '%s' has no '%s' marker" % [role, event])
		return 0.0
	return anim.get_marker_time(event)


static func clip_length(role: String) -> float:
	var anim := clip(role)
	return anim.length if anim != null else 0.0


## The speed a cycle was authored travelling at, in m/s (D-095). The number
## every locomotion rate divides the game's speed by so the feet plant.
static func authored_speed(role: String) -> float:
	var anim := clip(role)
	return float(anim.get_meta("authored_speed", 0.0)) if anim != null else 0.0

# -------------------------------------------------------------- the throw ---

## The longest a wind-up may be asked to take, in real seconds. The one number
## in this block that is a decision rather than a measurement.
##
## **It is a cap now and it used to be a target.** D-063 asked for half a second
## flat, because D-025's wind-up was being called a delay and the clip it was
## measured on wound up in 0.70 s. The spear's throw is its own clip since the
## rebuild — a one-arm overhead throw whose wind-up *is* the read: the arm goes
## back, over and through, and squeezing that into half a second plays it at
## 1.25x and loses the part the eye is waiting for. So the ask is the clip's own
## window, and this is only the ceiling under which that ask is honoured: the
## rate below comes out at exactly 1.0 for any clip that winds up inside 0.9 s,
## and only a slower clip than that is hurried.
const THROW_RELEASE_MAX := 0.9

## How long after the click the spear is *asked* to leave the hand, in real
## seconds: the clip's own authored window, up to the cap above. Derived rather
## than typed, so re-timing the markers re-times the throw and the rate stays 1.0
## (D-097 puts the markers on the clip; nothing here carries a clip time).
static var THROW_RELEASE_TARGET: float = minf(
	marker("Throw", "release") - marker("Throw", "windup"), THROW_RELEASE_MAX)

## The shortest any windup may be squeezed into, whatever is asked of it. It
## exists for `lightning_delay` of 0, which is legal: a rate derived from a
## delay of zero is a division by zero. 0.14 s is about as short as an arm can
## move and still be seen to move (D-063).
const THROW_RELEASE_MIN := 0.14

## How much of a clip is kept after the thing has left the hand, in the clip's
## seconds, before the one-shot's fade takes over. A third of a second of
## follow-through is what D-063 found reads as a throw rather than a stop.
const FOLLOW_THROUGH := 0.333

## The throw's window is from its `windup` marker — the frame the arm turns and
## starts back up — to a third of a second past its `release`. THROW_WINDOW is
## the part that has to have happened by the time the spear leaves, and the rate
## is derived from the ask above rather than typed beside it, so a window that
## moves moves the rate with it and leaves the release where it was promised
## (D-025, D-063). THROW_RELEASE_TIME is derived *through* the rate, so the ask
## is what visibly stops being met if somebody pins the rate by hand.
##
## With the ask now the window itself, THROW_RATE is **1.0** and the throw plays
## at the speed it was authored at; the chain is kept whole rather than collapsed
## to a constant because the cap is real, and a clip that winds up slower than
## THROW_RELEASE_MAX still comes out hurried by exactly the ratio that says so.
static var THROW_CLIP_START: float = marker("Throw", "windup")
static var THROW_RELEASE_IN_CLIP: float = marker("Throw", "release")
static var THROW_WINDOW: float = THROW_RELEASE_IN_CLIP - THROW_CLIP_START
static var THROW_CLIP_END: float = minf(marker("Throw", "release") + FOLLOW_THROUGH, clip_length("Throw"))
static var THROW_RATE: float = THROW_WINDOW / THROW_RELEASE_TARGET
static var THROW_RELEASE_TIME: float = THROW_WINDOW / THROW_RATE

# ---------------------------------------------------------------- the cast ---

## The Elder's cast: from its `windup` marker — the cocked frame before the
## thrust — to a third of a second past its `release`, played at whatever rate
## puts the release on `MatchConfig.lightning_delay` (D-064).
static var CAST_CLIP_START: float = marker("Cast", "windup")
static var CAST_WINDOW: float = marker("Cast", "release") - CAST_CLIP_START
static var CAST_CLIP_END: float = minf(marker("Cast", "release") + FOLLOW_THROUGH, clip_length("Cast"))
const CAST_RELEASE_MIN := THROW_RELEASE_MIN
static var CAST_RATE_MAX: float = CAST_WINDOW / CAST_RELEASE_MIN


## The playback rate that puts the cast's release exactly `seconds` after the
## click. Below the ceiling's own release time there is nothing left to scale,
## so this returns the ceiling rather than dividing by something near zero.
static func cast_rate_for_release(seconds: float) -> float:
	if seconds <= CAST_WINDOW / CAST_RATE_MAX:
		return CAST_RATE_MAX
	return CAST_WINDOW / seconds


## The inverse: when the cast's release actually lands for a clip played at
## `rate`. Only differs from what was asked once the ceiling has been hit.
static func cast_release_for_rate(rate: float) -> float:
	return CAST_WINDOW / maxf(rate, 0.01)

# ----------------------------------------------------------------- the bow ---

## The draw is the pull, and the pull is in `BowReload` (D-098). `BowDraw` is
## a 3.8 s hold at full draw and `BowAim` is the same pose again, so between
## them the charge would show nothing; `BowReload` brings the arrow from the
## quiver to the string at its `nock` marker and then draws it to the cheek
## over its last half second, and that half second is the charge. The draw
## layer scrubs it between `nock` and the end by `Bog.draw_fraction()`, over
## the aim plane, exactly as the two jump clips are scrubbed by `arc_time`:
## a pose picked by a float the world already knows, so every peer reaches the
## same pose from the same charge (D-065).
static var DRAW_CLIP_START: float = marker("BowReload", "nock")
static var DRAW_CLIP_FULL: float = clip_length("BowReload")


## Where in the pull a bow drawn `charge` of the way sits.
static func draw_time(charge: float) -> float:
	return lerpf(DRAW_CLIP_START, DRAW_CLIP_FULL, clampf(charge, 0.0, 1.0))


## The loose opens one frame before the string goes, so the pose it blends out
## of is the draw's own, and runs to the end of the clip; the fade-out is what
## hands the bow arm back. BOW_RELEASE_TIME is how long after `play_loose()` the
## arrow leaves: one frame, and that is the answer rather than an approximation
## of zero — the windup already happened (D-065).
const LOOSE_LEAD := 1.0 / 30.0
static var LOOSE_CLIP_START: float = maxf(marker("BowLoose", "release") - LOOSE_LEAD, 0.0)
static var LOOSE_CLIP_END: float = clip_length("BowLoose")
static var BOW_RELEASE_TIME: float = marker("BowLoose", "release") - LOOSE_CLIP_START

# ----------------------------------------------------------- the great sword --

## The swing is the whole of `SwordSpin` at the rate it was drawn at (D-068):
## the weight of a great sword *is* its 1.87 s, and nothing asks it to be
## anything else. The blade goes through at the `hit` marker; the advance the
## body makes over the clip is the clip's own authored travel, which
## `Bog.begin_spin` covers over SWING_SECONDS so the feet stay planted.
const SWING_RATE := 1.0
static var SWING_CLIP_START: float = 0.0
static var SWING_CLIP_END: float = clip_length("SwordSpin")
static var SWING_RELEASE_IN_CLIP: float = marker("SwordSpin", "hit")
static var SWING_WINDOW: float = SWING_RELEASE_IN_CLIP - SWING_CLIP_START
static var SWING_RELEASE_TIME: float = SWING_WINDOW / SWING_RATE
static var SWING_SECONDS: float = (SWING_CLIP_END - SWING_CLIP_START) / SWING_RATE
static var SWING_ADVANCE: float = (clip("SwordSpin").get_meta("travel", Vector3.ZERO) as Vector3).length()

# ----------------------------------------------------------- the slash chain --

## How many slashes `SwordCombo` carries, and therefore how long a chain can be
## (the feel round). Three, because the clip is three: `swing_1/hit_1/end_1`
## through `_3`. Read as a count and not typed at the call sites, so a clip
## re-cut with a fourth slash is a marker change and a number here.
const SLASH_COUNT := 3

## Where each slash begins, connects and ends, in the clip's own seconds
## (D-097). One window per slash out of one clip, which is what makes the chain
## a chain rather than three clips that happen to follow each other: the three
## poses were drawn as one continuous motion, so slash 2 starts where slash 1's
## follow-through left the blade.
static var SLASH_START: PackedFloat32Array = _slash_marks("swing")
static var SLASH_HIT: PackedFloat32Array = _slash_marks("hit")
static var SLASH_END: PackedFloat32Array = _slash_marks("end")


## The three times one of `swing`/`hit`/`end` sits at, indexed 0..2 for slashes
## 1..3. A static helper rather than three hand-written triples, because the
## whole of D-097 is that a marker moving must move everything derived from it
## and nothing else.
static func _slash_marks(event: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in SLASH_COUNT:
		out.append(marker("SwordCombo", "%s_%d" % [event, i + 1]))
	return out


## How long after the click slash `index` (1-based) connects, in real seconds.
## The clip is played at its authored speed — a great sword's weight is its
## timing, which is `SWING_RATE`'s argument one clip along — so this is simply
## the distance between two markers.
static func slash_release(index: int) -> float:
	var i := clampi(index - 1, 0, SLASH_COUNT - 1)
	return SLASH_HIT[i] - SLASH_START[i]


## How long slash `index` (1-based) runs for, in real seconds: its own window,
## which is also how long the body is held to `Bog.SLASH_SPEED_SCALE` and how
## long the one-shot has before the next click may cut it short.
static func slash_seconds(index: int) -> float:
	var i := clampi(index - 1, 0, SLASH_COUNT - 1)
	return SLASH_END[i] - SLASH_START[i]

# ----------------------------------------------------------------- the fist --

## The longest a punch may be asked to take to land, in real seconds.
## `THROW_RELEASE_MAX`'s sibling and a much shorter number, because it is
## holding a different promise: a punch is the attack you have when you have put
## your weapon away, so what it trades for its 20 damage is that it is *fast*.
## Half of `BogCombat.PUNCH_CYCLE`, so the fist connects in the first half of
## the cycle and recovers in the second.
const PUNCH_RELEASE_MAX := 0.25

## Which clip the punch is actually drawn with, and which marker on it is the
## connect. Resolved once, statically, because the thing they are about is the
## library and there is one of those (`_slide_jump_role` is the same resolution
## on an instance, and only because the graph node it feeds is built per body).
static var PUNCH_PLAYS: String = clip_or(PUNCH_ROLE, PUNCH_FALLBACK)
static var PUNCH_HIT_EVENT: String = "hit" if PUNCH_PLAYS == PUNCH_ROLE else "release"
## Where the window opens. Zero on the real clip, whose first frame is the fist
## already going; the stand-in opens on a standing idle, so it opens at its own
## `windup` instead — the one line in this block that knows it is a stand-in.
static var PUNCH_CLIP_START: float = 0.0 if PUNCH_PLAYS == PUNCH_ROLE \
	else marker(PUNCH_FALLBACK, "windup")
static var PUNCH_HIT_IN_CLIP: float = marker(PUNCH_PLAYS, PUNCH_HIT_EVENT)
static var PUNCH_WINDOW: float = PUNCH_HIT_IN_CLIP - PUNCH_CLIP_START
static var PUNCH_CLIP_END: float = minf(PUNCH_HIT_IN_CLIP + FOLLOW_THROUGH,
	clip_length(PUNCH_PLAYS))
## When the fist connects, and the rate that puts it there — the throw's chain
## exactly (D-025, D-063): the ask is the clip's own window up to the cap, the
## rate is derived from the ask, and the release is derived back through the
## rate so that pinning the rate by hand is what visibly breaks rather than the
## promise. A clip that winds up inside the cap plays at 1.0.
static var PUNCH_RELEASE_TIME: float = minf(PUNCH_WINDOW, PUNCH_RELEASE_MAX)
static var PUNCH_RATE: float = PUNCH_WINDOW / maxf(PUNCH_RELEASE_TIME, 0.01)

# --------------------------------------------------------------- the drink ---

## The drink is its `raise` to its `done` — the bottle up, at the lips, and
## down — played at whatever rate makes that take the channel's own length
## (D-067). The two `DRINK_CLIP_*` names are what the grip tools ask for.
static var DRINK_CLIP_START: float = marker("Drink", "raise")
static var DRINK_CLIP_END: float = marker("Drink", "done")
static var DRINK_WINDOW: float = DRINK_CLIP_END - DRINK_CLIP_START


## The playback rate that makes the drink take exactly `seconds`. No ceiling,
## unlike the cast's: `heal_channel` floors at 0.5 s, and the `maxf` is
## against a caller passing nonsense, not against a setting.
static func drink_rate_for_channel(seconds: float) -> float:
	return DRINK_WINDOW / maxf(seconds, 0.01)

# ------------------------------------------------------------ the landings ---

## A touchdown faster than this fires the heavy landing instead of the light
## one, in m/s downward. A jump at JUMP_VELOCITY comes back at about 9; a fall
## from two and a half metres under this gravity arrives at 11.
const HARD_LANDING_SPEED := 11.0

## How much of the heavy landing's absorb is played past its `absorb` marker
## before the fade takes over, in the clip's seconds. The clip goes on to put
## both hands on the ground for a second, which a body the player can already
## move again has no use for.
const HARD_ABSORB_HOLD := 0.3

## An airtime shorter than this fires no landing one-shot. It is
## `Bog.ROLL_MIN_AIRTIME` because the body uses the same threshold to decide
## whether to hold the player still through the roll, and two copies of that
## number could drift into a roll with the controls live under it.
const LAND_MIN_AIRTIME := Bog.ROLL_MIN_AIRTIME

## Fade times, in and out, for the one-shots. The slide comes in fast and
## leaves slowly because its exit *is* the stand-up; the landings come in almost
## instantly because a touchdown is an impact; the loose comes in fastest of all
## because the pose it blends out of is the draw's own.
const TAKEOFF_FADE_IN := 0.03
const TAKEOFF_FADE_OUT := 0.12
const SLIDE_FADE_IN := 0.08
const SLIDE_FADE_OUT := 0.30
const LAND_FADE_IN := 0.05
const LAND_FADE_OUT := 0.20
const ROLL_FADE_IN := 0.05
const ROLL_FADE_OUT := 0.25
const THROW_FADE_IN := 0.08
const THROW_FADE_OUT := 0.22
const CAST_FADE_IN := 0.06
const CAST_FADE_OUT := 0.14
const LOOSE_FADE_IN := 0.04
const LOOSE_FADE_OUT := 0.18
const SWING_FADE_IN := 0.06
const SWING_FADE_OUT := 0.25
## The slash comes in and out faster than the spin, and that is the difference
## between the two attacks stated as two numbers: the spin is a body committing
## for 1.867 s and the slash is an arm, over in a quarter of one. A 0.06 s fade
## on a 0.266 s window would be a quarter of the slash spent arriving.
const SLASH_FADE_IN := 0.03
const SLASH_FADE_OUT := 0.12
## The punch's, and the same argument: a fist is the fastest thing in this file.
const PUNCH_FADE_IN := 0.03
const PUNCH_FADE_OUT := 0.14
const DRINK_FADE_IN := 0.07
const DRINK_FADE_OUT := 0.18

# ------------------------------------------------------------------ blends ---

## How fast the visual state catches up with the physical one, in blend per
## second. Crouch is a near-instant read. Take-off is faster than landing on
## purpose: leaving the ground is a decision and should look like one, while
## arriving wants to settle rather than snap.
const STANCE_BLEND_SPEED := 10.0
const AIRBORNE_RISE_SPEED := 14.0
const AIRBORNE_FALL_SPEED := 10.0
const DIVE_BLEND_SPEED := 12.0
const LEAP_BLEND_SPEED := 12.0
## How fast the carry layer comes up (D-070), the draw pose and the aim
## (D-066): a draw has to be *there* early because the charge is already
## running; a carry has nowhere to be.
const CARRY_BLEND_SPEED := 5.0
const DRAW_BLEND_SPEED := 12.0
## The cross-fade between the three ground planes, in seconds: a bow coming
## up, a bow going down. Short enough that the aim pose arrives with the
## charge, long enough that the feet do not scissor.
const PLANE_XFADE := 0.15

## How fast the emote comes in and goes out, in blend per second — the plane
## cross-fade, read as a rate, because it is the same kind of move: a whole body
## changing what it is doing, with both feet on the ground, and no event inside
## either pose that has to land on a frame. A OneShot would have been the wrong
## node for it: `Twerk` loops until the player stops it, and a one-shot that is
## never allowed to finish is the clock D-026 exists to keep out of this graph.
const EMOTE_BLEND_SPEED := 1.0 / PLANE_XFADE

# ----------------------------------------------------------- the upper body --

## Bones the layered one-shots and blends are allowed to move: everything from
## the middle spine up. Hips and Spine are deliberately not here — a layer's own
## rotation of them would fight the run cycle's weight shift (D-029), and the
## torso is turned onto the crosshair by `BogAim` instead (D-066).
const UPPER_BODY_BONES: Array[String] = [
	"mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head", "mixamorig_HeadTop_End",
	"mixamorig_LeftShoulder", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand",
	"mixamorig_LeftHandThumb1", "mixamorig_LeftHandThumb2", "mixamorig_LeftHandThumb3", "mixamorig_LeftHandThumb4",
	"mixamorig_LeftHandIndex1", "mixamorig_LeftHandIndex2", "mixamorig_LeftHandIndex3", "mixamorig_LeftHandIndex4",
	"mixamorig_LeftHandMiddle1", "mixamorig_LeftHandMiddle2", "mixamorig_LeftHandMiddle3", "mixamorig_LeftHandMiddle4",
	"mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand",
	"mixamorig_RightHandThumb1", "mixamorig_RightHandThumb2", "mixamorig_RightHandThumb3", "mixamorig_RightHandThumb4",
	"mixamorig_RightHandIndex1", "mixamorig_RightHandIndex2", "mixamorig_RightHandIndex3", "mixamorig_RightHandIndex4",
	"mixamorig_RightHandMiddle1", "mixamorig_RightHandMiddle2", "mixamorig_RightHandMiddle3", "mixamorig_RightHandMiddle4",
]

# -------------------------------------------------------------- parameters ---

const P_STAND_MOVE := "parameters/stand/blend_position"
const P_SWORD_MOVE := "parameters/sword/blend_position"
const P_AIM_MOVE := "parameters/aim/blend_position"
const P_CROUCH_MOVE := "parameters/crouch/blend_position"
const P_LOCO := "parameters/loco/transition_request"
const P_STANCE := "parameters/stance/blend_amount"
const P_LEAP_SEEK := "parameters/leap_seek/seek_request"
const P_SLIDE_LEAP_SEEK := "parameters/slide_leap_seek/seek_request"
const P_DIVE_SEEK := "parameters/dive_seek/seek_request"
const P_LEAP := "parameters/air_kind/blend_amount"
const P_SLIDE_LEAP := "parameters/leap_kind/blend_amount"
const P_DIVE := "parameters/air/blend_amount"
const P_AIRBORNE := "parameters/grounded/blend_amount"
const P_TAKEOFF := "parameters/takeoff/request"
const P_SLIDE := "parameters/slide/request"
const P_SLIDE_ACTIVE := "parameters/slide/active"
const P_LAND := "parameters/land/request"
const P_LAND_ACTIVE := "parameters/land/active"
const P_LAND_HARD := "parameters/land_hard/request"
const P_LAND_HARD_ACTIVE := "parameters/land_hard/active"
const P_ROLL := "parameters/roll/request"
const P_CARRY := "parameters/carry/blend_amount"
const P_CARRY_PICK := "parameters/carry_pick/transition_request"
const P_DRAW := "parameters/draw/blend_amount"
const P_DRAW_SEEK := "parameters/draw_seek/seek_request"
const P_LOOSE := "parameters/loose/request"
const P_LOOSE_ACTIVE := "parameters/loose/active"
const P_DRINK := "parameters/drink/request"
const P_DRINK_ACTIVE := "parameters/drink/active"
const P_DRINK_RATE := "parameters/drink_rate/scale"
const P_CAST := "parameters/cast/request"
const P_CAST_ACTIVE := "parameters/cast/active"
const P_CAST_RATE := "parameters/cast_rate/scale"
const P_THROW := "parameters/throw/request"
const P_THROW_ACTIVE := "parameters/throw/active"
const P_THROW_RATE := "parameters/throw_rate/scale"
const P_PUNCH := "parameters/punch/request"
const P_PUNCH_ACTIVE := "parameters/punch/active"
const P_PUNCH_RATE := "parameters/punch_rate/scale"
const P_SLASH := "parameters/slash/request"
const P_SLASH_ACTIVE := "parameters/slash/active"
const P_SLASH_PICK := "parameters/slash_pick/transition_request"
const P_SWING := "parameters/swing/request"
const P_SWING_ACTIVE := "parameters/swing/active"
const P_SWING_RATE := "parameters/swing_rate/scale"
const P_EMOTE := "parameters/emote/blend_amount"

## The carry pose a holstered Bog stands in, and the name of the extra
## `carry_pick` input that plays it (the feel round).
##
## A fourth input beside the three weapons rather than a fourth *weapon*: the
## holster is a state a Bog is in and not something it brought, and
## `Loadout.CARRY_CLIPS` is indexed by the pick. `Idle` is the Bog's own
## boxer's guard — the pose D-072 went looking for a spear in and found hands
## resting against the body, which is exactly the pose for somebody carrying
## nothing.
##
## It is drawn at weight zero almost always, because `_armed()` is false while
## the fists are empty and the carry layer fades out under it. It is here so
## that the layer has something honest to hold if anything ever raises it, and
## so that `carry_pick` never has to point at a weapon a Bog has put away.
const CARRY_FISTS := "fists"

## The three ground planes' input names on the `loco` transition.
const LOCO_STAND := "stand"
const LOCO_SWORD := "sword"
const LOCO_AIM := "aim"

var _body: Bog
var _skeleton_path: String = ""

## Smoothed blend weights, so nothing in the tree steps.
var _stance: float = 0.0
var _airborne: float = 0.0
var _dive_blend: float = 0.0
var _leap_blend: float = 0.0
## How far the pull is over the body. Not the charge — the charge is the
## *seek*, and this is only whether the bow pose is being shown at all.
var _draw_blend: float = 0.0
## How far the carry pose is over the body (D-070). The same number
## `HeldGear.set_carry` is handed for the bow's tilt.
var _carry_blend: float = 0.0
## How much of the emote is showing, 0 to 1. Moved toward `Bog.is_emoting()`,
## which answers off the flag the relay writes on every peer, so the eight
## machines watching blend the same dance in over the same 0.15 s.
var _emote_blend: float = 0.0
## How far the *aim* is over the body (D-066): whether the torso is turned to
## the crosshair. Holds through the loose, which `_draw_blend` does not.
var _aim_blend: float = 0.0
## The torso modifier, installed in `_ready` on the skeleton inside the
## imported body.
var _aim: BogAim
## Which ground plane `loco` was last pointed at.
var _current_plane: String = ""

## What this animator believes about the body; kept because the interesting
## thing about each is the frame it *changes*.
var _grounded: bool = true
var _sliding: bool = false
var _drawing: bool = false

## The current airtime.
var _airtime_open: bool = false
var _airtime: float = 0.0
var _dived: bool = false
## Whether this airtime is a running jump (the leap clip) rather than a standing
## one (the take-off and the air loop).
var _leaping: bool = false
## And whether the leap it is, is the slide jump's rather than the run's. A
## second flag beside `_leaping` and not a third state, because everything
## about the air branch is the same either way — it is one clip swapped for
## another under the same scrub.
var _slide_leaping: bool = false
var _slide_leap_blend: float = 0.0
## The fastest the body fell during this airtime, in m/s downward, which is
## what says whether the touchdown was heavy.
var _fall_speed: float = 0.0
## The upward speed the dive was launched at, the scale its arc is measured
## against. Seeded with the floor the dive itself enforces.
var _dive_launch: float = Bog.DIVE_UP_VELOCITY

## Last values of the replicated counters this animator has acted on.
var _dive_serial: int = 0
var _jump_serial: int = 0
var _slide_jump_serial: int = 0

## Which clip the slide jump is actually drawn with on this body: its own, or
## `RunJump` while its own does not exist yet. Resolved once in `_ready`.
var _slide_jump_role: String = SLIDE_JUMP_FALLBACK
## Whether this run has already said so. Static, because the thing it is about
## is the library and there is one of those.
static var _slide_jump_warned: bool = false
## And whether this run has said so about the punch. Static for the same reason.
static var _punch_warned: bool = false


func _ready() -> void:
	_body = get_parent() as Bog
	if _body == null:
		push_error("BogAnimator expects to be a child of a Bog")
		return

	var player := get_node_or_null(anim_player) as AnimationPlayer
	if player == null:
		push_error("BogAnimator: anim_player does not resolve to an AnimationPlayer")
		return
	var missing := _missing_clips(player)
	if not missing.is_empty():
		push_error("BogAnimator: the body's clip library is missing: %s" % ", ".join(missing))
		return

	# Before the graph, which is built out of it. Warned about once per run and
	# not once per BOG: eight bodies spawn in a match and the news is about the
	# library, not about any of them.
	_slide_jump_role = clip_or(SLIDE_JUMP_ROLE, SLIDE_JUMP_FALLBACK)
	if _slide_jump_role != SLIDE_JUMP_ROLE and not _slide_jump_warned:
		_slide_jump_warned = true
		push_warning("BogAnimator: no '%s' clip yet; the slide jump is drawn with '%s'"
			% [SLIDE_JUMP_ROLE, _slide_jump_role])
	# And the punch's, said once for the same reason and off a role that was
	# already resolved statically — the warning is about this run, not about
	# this body.
	if PUNCH_PLAYS != PUNCH_ROLE and not _punch_warned:
		_punch_warned = true
		push_warning("BogAnimator: no '%s' clip yet; the punch is drawn with '%s'"
			% [PUNCH_ROLE, PUNCH_PLAYS])

	_skeleton_path = _find_skeleton_track_prefix(player)
	tree_root = _build_graph(player)
	active = true

	# After the graph, because the modifier reads this node's own blend weight.
	var skeleton := _body.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		push_warning("BogAnimator: no Skeleton3D under this Bog; the torso will not aim")
	else:
		_aim = BogAim.install(skeleton, _body, self)

	set(P_THROW_RATE, THROW_RATE)
	set(P_SWING_RATE, SWING_RATE)
	set(P_PUNCH_RATE, PUNCH_RATE)
	set(P_SLASH_PICK, _slash_input(1))
	set(P_DRAW_SEEK, DRAW_CLIP_START)
	set_carry_pose()
	_point_plane(LOCO_STAND)

	_grounded = _body.is_grounded()
	_dive_serial = _body.sync_dive_serial
	_jump_serial = _body.sync_jump_serial
	_slide_jump_serial = _body.sync_slide_jump_serial
	_body.respawned.connect(_forget_airtime)
	# Standing, whatever the body says: a remote BOG is spawned before anything
	# has replicated to it, and opening on the air pose is every dummy in the
	# range splayed out mid-leap.
	_airborne = 0.0


## Track paths inside the clips look like `Skeleton3D:mixamorig_Hips`. The
## prefix is read off an actual track rather than hard-coded, so renaming the
## node inside the body does not silently disable the upper-body filters.
func _find_skeleton_track_prefix(player: AnimationPlayer) -> String:
	for clip_name in player.get_animation_list():
		var anim := player.get_animation(clip_name)
		for i in anim.get_track_count():
			var path := String(anim.track_get_path(i))
			if path.contains(":"):
				return path.get_slice(":", 0)
	push_warning("BogAnimator: no skeleton tracks found; layers will play full-body")
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
	var walk := Bog.WALK_SPEED
	var run := Bog.RUN_SPEED
	var back_walk := walk * Bog.BACK_SPEED_SCALE
	var back_run := run * Bog.BACK_SPEED_SCALE
	var crouch := Bog.CROUCH_SPEED

	# The three ground planes. Every point plays its clip at the rate that
	# plants its feet at the game speed its position means (D-066), and the
	# backward points sit at the capped backward speed so a backpedal lands on
	# its own clip rather than short of it (D-098).
	tree.add_node("stand", _plane(player, [
		["Idle", Vector2.ZERO], ["Walk", Vector2(0, walk)], ["Run", Vector2(0, run)],
		["WalkBack", Vector2(0, -back_walk)], ["RunBack", Vector2(0, -back_run)],
		["StrafeWalkRight", Vector2(walk, 0)], ["StrafeRight", Vector2(run, 0)],
		["StrafeWalkLeft", Vector2(-walk, 0)], ["StrafeLeft", Vector2(-run, 0)],
	]), Vector2(0, 0))
	tree.add_node("sword", _plane(player, [
		["SwordCarry", Vector2.ZERO], ["SwordWalk", Vector2(0, walk)], ["SwordRun", Vector2(0, run)],
		["SwordWalkBack", Vector2(0, -back_walk)], ["SwordRunBack", Vector2(0, -back_run)],
		["SwordStrafeWalkRight", Vector2(walk, 0)], ["SwordStrafeRight", Vector2(run, 0)],
		["SwordStrafeWalkLeft", Vector2(-walk, 0)], ["SwordStrafeLeft", Vector2(-run, 0)],
	]), Vector2(0, 160))
	# The archer set has walks and no runs, and the body is held to a walk while
	# the bow is up (`Bog.AIM_WALKS`), so its ring is the walk ring. A full draw
	# is slower still (`Bog.DRAW_SPEED_SCALE`, the feel round) and there is no
	# clip for that: under the walk ring the plane blends toward its own idle,
	# `BowAim`, which is the pose a bow held at full draw should be creeping in.
	tree.add_node("aim", _plane(player, [
		["BowAim", Vector2.ZERO], ["BowAimWalk", Vector2(0, walk)],
		["BowAimWalkBack", Vector2(0, -back_walk)],
		["BowAimStrafeRight", Vector2(walk, 0)], ["BowAimStrafeLeft", Vector2(-walk, 0)],
	]), Vector2(0, 320))
	tree.add_node("loco", _loco_pick(), Vector2(260, 160))

	tree.add_node("crouch", _plane(player, [
		["CrouchIdle", Vector2.ZERO], ["CrouchWalk", Vector2(0, crouch)],
		["CrouchWalkBack", Vector2(0, -crouch)],
		["CrouchStrafeRight", Vector2(crouch, 0)], ["CrouchStrafeLeft", Vector2(-crouch, 0)],
	]), Vector2(0, 480))
	tree.add_node("stance", _blend2(), Vector2(480, 300))

	tree.add_node("air_loop", _cycle(player, "AirLoop", 0.0), Vector2(0, 640))
	tree.add_node("leap", _scrubbed("RunJump"), Vector2(0, 760))
	tree.add_node("leap_seek", AnimationNodeTimeSeek.new(), Vector2(200, 760))
	# The slide jump's own leap, scrubbed by its own arc off the same three
	# markers (the feel round). A second node rather than one node whose
	# `animation` is swapped at take-off: a clip changed under a running graph
	# is a pose that jumps on the frame it changes, and both of these are told
	# what time it is every frame whether or not anything is looking (see
	# `_scrub_air`), which is the whole reason the air poses never pop.
	tree.add_node("slide_leap", _scrubbed(_slide_jump_role), Vector2(0, 700))
	tree.add_node("slide_leap_seek", AnimationNodeTimeSeek.new(), Vector2(200, 700))
	tree.add_node("leap_kind", _blend2(), Vector2(300, 730))
	tree.add_node("air_kind", _blend2(), Vector2(400, 700))
	tree.add_node("dive_clip", _scrubbed("Roll"), Vector2(0, 880))
	tree.add_node("dive_seek", AnimationNodeTimeSeek.new(), Vector2(200, 880))
	tree.add_node("air", _blend2(), Vector2(600, 790))
	tree.add_node("grounded", _blend2(), Vector2(760, 500))

	tree.add_node("takeoff_clip", _window("JumpStart", 0.0, clip_length("JumpStart")), Vector2(760, 1000))
	tree.add_node("takeoff", _shot(TAKEOFF_FADE_IN, TAKEOFF_FADE_OUT), Vector2(960, 520))
	tree.add_node("slide_clip", _window("Slide", marker("Slide", "down"), marker("Slide", "up")),
		Vector2(960, 1000))
	tree.add_node("slide", _shot(SLIDE_FADE_IN, SLIDE_FADE_OUT), Vector2(1160, 540))
	tree.add_node("land_clip", _window("Land", 0.0, clip_length("Land")), Vector2(1160, 1000))
	tree.add_node("land", _shot(LAND_FADE_IN, LAND_FADE_OUT), Vector2(1360, 560))
	tree.add_node("land_hard_clip", _window("LandHard", marker("LandHard", "impact"),
		minf(marker("LandHard", "absorb") + HARD_ABSORB_HOLD, marker("LandHard", "up"))), Vector2(1360, 1000))
	tree.add_node("land_hard", _shot(LAND_FADE_IN, LAND_FADE_OUT), Vector2(1560, 580))
	tree.add_node("roll_clip", _window("Roll", marker("Roll", "land"), marker("Roll", "up")),
		Vector2(1560, 1000))
	tree.add_node("roll", _shot(ROLL_FADE_IN, ROLL_FADE_OUT), Vector2(1760, 600))

	# One clip node per weapon and a Transition to pick between them (D-070).
	for i in Loadout.CARRY_CLIPS.size():
		tree.add_node(_carry_input(i), _cycle(player, Loadout.CARRY_CLIPS[i], 0.0),
			Vector2(1760, 1100 + 120 * i))
	tree.add_node(CARRY_FISTS, _cycle(player, "Idle", 0.0),
		Vector2(1760, 1100 + 120 * Loadout.CARRY_CLIPS.size()))
	tree.add_node("carry_pick", _carry_pick(), Vector2(1960, 1160))
	tree.add_node("carry", _upper_body_blend(), Vector2(1960, 620))
	tree.add_node("draw_clip", _scrubbed("BowReload"), Vector2(1960, 1000))
	tree.add_node("draw_seek", AnimationNodeTimeSeek.new(), Vector2(2140, 1000))
	tree.add_node("draw", _upper_body_blend(), Vector2(2160, 640))
	tree.add_node("loose_clip", _window("BowLoose", LOOSE_CLIP_START, LOOSE_CLIP_END), Vector2(2160, 1000))
	tree.add_node("loose", _upper_body_shot(LOOSE_FADE_IN, LOOSE_FADE_OUT), Vector2(2360, 660))
	tree.add_node("drink_clip", _window("Drink", DRINK_CLIP_START, DRINK_CLIP_END), Vector2(2360, 1000))
	tree.add_node("drink_rate", AnimationNodeTimeScale.new(), Vector2(2540, 1000))
	tree.add_node("drink", _upper_body_shot(DRINK_FADE_IN, DRINK_FADE_OUT), Vector2(2560, 680))
	tree.add_node("cast_clip", _window("Cast", CAST_CLIP_START, CAST_CLIP_END), Vector2(2560, 1000))
	tree.add_node("cast_rate", AnimationNodeTimeScale.new(), Vector2(2740, 1000))
	tree.add_node("cast", _upper_body_shot(CAST_FADE_IN, CAST_FADE_OUT), Vector2(2760, 700))
	tree.add_node("throw_clip", _window("Throw", THROW_CLIP_START, THROW_CLIP_END), Vector2(2760, 1000))
	tree.add_node("throw_rate", AnimationNodeTimeScale.new(), Vector2(2940, 1000))
	tree.add_node("throw", _upper_body_shot(THROW_FADE_IN, THROW_FADE_OUT), Vector2(2960, 720))
	# The fist, layered like the throw and for a sharper version of its reason
	# (the feel round): a punch is what you have when you have put the weapon
	# away, and the whole of what it buys is that you keep moving and turning at
	# full speed while you throw it. A full-body shot would be a Bog that stops
	# to punch, which is the sword's trade and not this one.
	tree.add_node("punch_clip", _window(PUNCH_PLAYS, PUNCH_CLIP_START, PUNCH_CLIP_END),
		Vector2(2960, 1120))
	tree.add_node("punch_rate", AnimationNodeTimeScale.new(), Vector2(3140, 1120))
	tree.add_node("punch", _upper_body_shot(PUNCH_FADE_IN, PUNCH_FADE_OUT), Vector2(3160, 730))
	# The slash chain: three windows of one clip and a `Transition` to say which
	# one is being played, feeding one upper-body OneShot (the feel round).
	#
	# A Transition and not three OneShots, because "which slash is this" is not
	# three independent events that could overlap — it is one blade, in one of
	# three places along one motion — and three shots would be three fade-outs
	# racing each other on the frame a chain steps. Zero cross-fade on the pick
	# for `carry_pick`'s reason: the selection is made on the frame the one-shot
	# is fired and the shot's own fade is what the eye sees.
	#
	# Upper body, over whatever the legs are doing, which is the entire
	# difference from the spin below it: a slash keeps the stick, the turn and
	# the jump, so the legs must stay in the locomotion plane. The spin cannot —
	# it turns the pelvis through a revolution and a mask cannot draw a line at
	# it (D-068) — and that is why the two attacks are two nodes rather than one
	# with a flag.
	for i in SLASH_COUNT:
		tree.add_node(_slash_input(i + 1),
			_window("SwordCombo", SLASH_START[i], SLASH_END[i]),
			Vector2(2960, 1240 + 120 * i))
	tree.add_node("slash_pick", _slash_pick(), Vector2(3140, 1300))
	tree.add_node("slash", _upper_body_shot(SLASH_FADE_IN, SLASH_FADE_OUT), Vector2(3160, 735))
	tree.add_node("swing_clip", _window("SwordSpin", SWING_CLIP_START, SWING_CLIP_END), Vector2(2960, 1000))
	tree.add_node("swing_rate", AnimationNodeTimeScale.new(), Vector2(3140, 1000))
	# Full body, the only attack that is (D-068): the spin turns the pelvis
	# through a revolution and a mask cannot draw a line at it.
	tree.add_node("swing", _shot(SWING_FADE_IN, SWING_FADE_OUT), Vector2(3160, 740))
	tree.add_node("twerk_clip", _cycle(player, "Twerk", 0.0), Vector2(3160, 1000))
	tree.add_node("emote", _blend2(), Vector2(3360, 780))

	tree.connect_node("loco", 0, "stand")
	tree.connect_node("loco", 1, "sword")
	tree.connect_node("loco", 2, "aim")
	tree.connect_node("stance", 0, "loco")
	tree.connect_node("stance", 1, "crouch")
	tree.connect_node("leap_seek", 0, "leap")
	tree.connect_node("slide_leap_seek", 0, "slide_leap")
	tree.connect_node("leap_kind", 0, "leap_seek")
	tree.connect_node("leap_kind", 1, "slide_leap_seek")
	tree.connect_node("air_kind", 0, "air_loop")
	tree.connect_node("air_kind", 1, "leap_kind")
	tree.connect_node("dive_seek", 0, "dive_clip")
	tree.connect_node("air", 0, "air_kind")
	tree.connect_node("air", 1, "dive_seek")
	tree.connect_node("grounded", 0, "stance")
	tree.connect_node("grounded", 1, "air")
	tree.connect_node("takeoff", 0, "grounded")
	tree.connect_node("takeoff", 1, "takeoff_clip")
	tree.connect_node("slide", 0, "takeoff")
	tree.connect_node("slide", 1, "slide_clip")
	tree.connect_node("land", 0, "slide")
	tree.connect_node("land", 1, "land_clip")
	tree.connect_node("land_hard", 0, "land")
	tree.connect_node("land_hard", 1, "land_hard_clip")
	tree.connect_node("roll", 0, "land_hard")
	tree.connect_node("roll", 1, "roll_clip")
	# The carry pose is the weakest claim in the graph and sits under every
	# layer: it is what the arms do when nothing else is happening (D-070). The
	# drink is the lowest of the layered one-shots (D-067); the draw and its
	# loose sit under the two windups, and the throw over the cast, for the
	# same argument each time — the thing that must win a tie is the one whose
	# weapon is in the hand on the frame the tie happens (D-064).
	for i in Loadout.CARRY_CLIPS.size():
		tree.connect_node("carry_pick", i, _carry_input(i))
	tree.connect_node("carry_pick", Loadout.CARRY_CLIPS.size(), CARRY_FISTS)
	tree.connect_node("carry", 0, "roll")
	tree.connect_node("carry", 1, "carry_pick")
	tree.connect_node("draw_seek", 0, "draw_clip")
	tree.connect_node("draw", 0, "carry")
	tree.connect_node("draw", 1, "draw_seek")
	tree.connect_node("loose", 0, "draw")
	tree.connect_node("loose", 1, "loose_clip")
	tree.connect_node("drink_rate", 0, "drink_clip")
	tree.connect_node("drink", 0, "loose")
	tree.connect_node("drink", 1, "drink_rate")
	tree.connect_node("cast_rate", 0, "cast_clip")
	tree.connect_node("cast", 0, "drink")
	tree.connect_node("cast", 1, "cast_rate")
	tree.connect_node("throw_rate", 0, "throw_clip")
	tree.connect_node("throw", 0, "cast")
	tree.connect_node("throw", 1, "throw_rate")
	tree.connect_node("punch_rate", 0, "punch_clip")
	tree.connect_node("punch", 0, "throw")
	tree.connect_node("punch", 1, "punch_rate")
	for i in SLASH_COUNT:
		tree.connect_node("slash_pick", i, _slash_input(i + 1))
	# The punch and the slash cannot both be running — a fist is what a
	# holstered Bog has and a slash is what a drawn great sword does — so their
	# order between themselves settles no tie and is simply the order they were
	# written in.
	tree.connect_node("slash", 0, "punch")
	tree.connect_node("slash", 1, "slash_pick")
	tree.connect_node("swing_rate", 0, "swing_clip")
	# The swing sits over everything: a full-body shot under a masked one would
	# have the mask's clip win on every bone the mask names (D-068). That still
	# holds over the slash, and it is also the right priority: the sprint attack
	# is the committed one, so a spin that somehow overlapped a slash should be
	# the thing on screen.
	tree.connect_node("swing", 0, "slash")
	tree.connect_node("swing", 1, "swing_rate")
	# The emote sits over even the swing, and it is the only node in this graph
	# allowed to: it is a full-body pose the player asked for, and every other
	# state in here ends it rather than competing with it
	# (`BogCombat.refresh_emote` is the whole list), so there is no tie left for
	# it to win. It is a Blend2 and not a OneShot because `Twerk` loops until it
	# is told to stop.
	tree.connect_node("emote", 0, "swing")
	tree.connect_node("emote", 1, "twerk_clip")
	tree.connect_node("output", 0, "emote")
	return tree


## A locomotion plane (D-066): the first point is the idle at the origin, then
## forward, back, right, left, walk before run where both exist. Positions are
## the BOG's velocity in its own frame, x to its right and y forward, in game
## m/s; every point plays its clip at the rate that plants its feet there.
##
## The triangles are written out rather than left to `auto_triangles`: every
## point lies on one of the two axes, so a third of the triples are exactly
## collinear and which survive a degenerate Delaunay is not something this
## graph should find out at runtime. Nine points are four quadrants of three;
## five are a fan of four.
func _plane(player: AnimationPlayer, points: Array) -> AnimationNodeBlendSpace2D:
	var space := AnimationNodeBlendSpace2D.new()
	space.min_space = Vector2(-Bog.RUN_SPEED, -Bog.RUN_SPEED)
	space.max_space = Vector2(Bog.RUN_SPEED, Bog.RUN_SPEED)
	space.x_label = "right"
	space.y_label = "forward"
	space.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	space.auto_triangles = false
	# Every point keeps running whether or not it carries weight: see `_blend2`.
	space.sync = true
	for point: Array in points:
		var pos: Vector2 = point[1]
		space.add_blend_point(_cycle(player, point[0], pos.length()), pos, -1, point[0])
	if points.size() == 9:
		for quadrant: Array in LOCOMOTION_QUADRANTS:
			space.add_triangle(0, quadrant[0], quadrant[2])
			space.add_triangle(quadrant[0], quadrant[2], quadrant[3])
			space.add_triangle(quadrant[0], quadrant[3], quadrant[1])
	elif points.size() == 5:
		for pair: Array in [[1, 3], [3, 2], [2, 4], [4, 1]]:
			space.add_triangle(0, pair[0], pair[1])
	else:
		push_error("BogAnimator: a plane has %d points; nine or five" % points.size())
	return space


## The four quadrants of a nine-point plane, each as [forward-or-back walk,
## the run beside it, sideways walk, the run beside it], as indices into the
## order the points are added in: idle, walk, run, walk back, run back, walk
## right, run right, walk left, run left.
const LOCOMOTION_QUADRANTS: Array = [
	[1, 2, 5, 6],   # forward-right
	[1, 2, 7, 8],   # forward-left
	[3, 4, 5, 6],   # back-right
	[3, 4, 7, 8],   # back-left
]


## Which ground plane the legs are on. A `Transition` and not a blend: half a
## sword walk blended into half an archer's sidestep is a pose nobody stands in.
## The cross-fade is what keeps a bow coming up from popping the feet.
func _loco_pick() -> AnimationNodeTransition:
	var pick := AnimationNodeTransition.new()
	pick.xfade_time = PLANE_XFADE
	pick.allow_transition_to_self = false
	pick.input_count = 3
	pick.sync = true
	for i in 3:
		pick.set_input_name(i, [LOCO_STAND, LOCO_SWORD, LOCO_AIM][i])
		pick.set("input_%d/auto_advance" % i, false)
		pick.set("input_%d/reset" % i, false)
	return pick


## A two-way blend whose *unweighted* side keeps running. With `sync` at its
## default false Godot freezes any input a blend is not listening to, and the
## first sprint of a round cross-fades a *static* run frame into a mid-stride
## walk (D-029).
func _blend2() -> AnimationNodeBlend2:
	var blend := AnimationNodeBlend2.new()
	blend.sync = true
	return blend


## One looping cycle, played at exactly the rate that keeps its feet planted
## at the game speed its blend point sits at: `game_speed` over the clip's own
## `authored_speed` (D-095). A speed of 0 is a standing pose at rate 1.
##
## The rate lives in a custom timeline: `stretch_time_scale` makes the node play
## its clip in `timeline_length` seconds instead of its own. `loop_mode` is set
## here rather than trusted from the clip, because with a custom timeline the
## node's own loop mode wins.
func _cycle(player: AnimationPlayer, role: String, game_speed: float) -> AnimationNodeAnimation:
	var rate := 1.0
	var authored := authored_speed(role)
	if authored > 0.0 and game_speed > 0.0:
		rate = game_speed / authored
	var node := AnimationNodeAnimation.new()
	node.animation = role
	node.use_custom_timeline = true
	node.start_offset = 0.0
	node.timeline_length = player.get_animation(role).length / rate
	node.stretch_time_scale = true
	node.loop_mode = Animation.LOOP_LINEAR
	return node


## A window of a clip, played once at authored speed and held on its last
## frame. `stretch_time_scale` has to be **false** here: true would throw the
## window's far end away, which is why every rate on a one-shot is a separate
## TimeScale node.
func _window(role: String, from: float, to: float) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = role
	node.use_custom_timeline = true
	node.start_offset = from
	node.timeline_length = maxf(to - from, 1.0 / 30.0)
	node.stretch_time_scale = false
	node.loop_mode = Animation.LOOP_NONE
	return node


## A clip with no timeline of its own, because something else says what time
## it is every frame: the two air scrubs and the draw pose.
func _scrubbed(role: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = role
	node.use_custom_timeline = false
	node.loop_mode = Animation.LOOP_NONE
	return node


func _shot(fade_in: float, fade_out: float) -> AnimationNodeOneShot:
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = fade_in
	shot.fadeout_time = fade_out
	shot.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
	# Keeps the branch *underneath* running while this shot is at full weight;
	# without it a run cycle freezes for the length of every landing absorb.
	shot.sync = true
	return shot


## The carry poses and the node that picks between them (D-070): a
## `Transition`, because "which weapon did this player bring" is not a
## quantity. Zero cross-fade, because the pick is made before the body exists;
## the lobby ring is the one caller that changes it on a standing BOG, and
## there a hard cut is right.
func _carry_pick() -> AnimationNodeTransition:
	var pick := AnimationNodeTransition.new()
	pick.xfade_time = 0.0
	pick.allow_transition_to_self = false
	# One more than the weapons: the last input is the holstered Bog's own
	# hands. See CARRY_FISTS.
	pick.input_count = Loadout.CARRY_CLIPS.size() + 1
	pick.sync = true
	for i in Loadout.CARRY_CLIPS.size():
		pick.set_input_name(i, _carry_input(i))
		pick.set("input_%d/auto_advance" % i, false)
		pick.set("input_%d/reset" % i, false)
	var fists := Loadout.CARRY_CLIPS.size()
	pick.set_input_name(fists, CARRY_FISTS)
	pick.set("input_%d/auto_advance" % fists, false)
	pick.set("input_%d/reset" % fists, false)
	return pick


## The input name `carry_pick` knows a weapon by: the ordinal, because two
## weapons may share a clip.
static func _carry_input(weapon: int) -> String:
	return "w%d" % weapon


## The input name `slash_pick` knows a slash by, 1-based like the markers it is
## windowed from (`swing_1`, `hit_1`, `end_1`), so a name in a debugger reads as
## the same slash the clip calls it.
static func _slash_input(index: int) -> String:
	return "s%d" % index


## Which slash of the chain is being played. A `Transition` for `_loco_pick`'s
## reason inverted: half of slash 1 blended into half of slash 3 is not a pose,
## and unlike the ground planes there is nothing to cross-fade *between*
## because the shot above is faded in and out as a whole.
func _slash_pick() -> AnimationNodeTransition:
	var pick := AnimationNodeTransition.new()
	pick.xfade_time = 0.0
	pick.allow_transition_to_self = false
	pick.input_count = SLASH_COUNT
	pick.sync = true
	for i in SLASH_COUNT:
		pick.set_input_name(i, _slash_input(i + 1))
		pick.set("input_%d/auto_advance" % i, false)
		pick.set("input_%d/reset" % i, false)
	return pick


## A held layer, filtered to the upper body: the carry pose and the drawn bow.
func _upper_body_blend() -> AnimationNodeBlend2:
	var blend := _blend2()
	if _skeleton_path.is_empty():
		return blend
	blend.filter_enabled = true
	for bone in UPPER_BODY_BONES:
		blend.set_filter_path(NodePath("%s:%s" % [_skeleton_path, bone]), true)
	return blend


## A one-shot that is a layer, not a state: only `UPPER_BODY_BONES` take the
## clip and the legs stay in whatever the blend below is producing, which is
## the whole of "you can throw at a dead run" and "you can drink in the air".
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
	var move := _body_relative(flat)
	set(P_STAND_MOVE, move)
	set(P_SWORD_MOVE, move)
	set(P_AIM_MOVE, move)
	set(P_CROUCH_MOVE, Vector2(
		clampf(move.x, -Bog.CROUCH_SPEED, Bog.CROUCH_SPEED),
		clampf(move.y, -Bog.CROUCH_SPEED, Bog.CROUCH_SPEED)))

	_track_airtime(delta)
	_track_slide()
	_track_draw()
	_scrub_air()

	# `crouch_pose()` and not `is_crouching()`: the rule is grounded-only and
	# the pose is not (the feel round), and this tree wants the pose — a crouch
	# held through a fall arrives on the floor already tucked, which is what a
	# landing slide fades in out of.
	_stance = move_toward(_stance, _body.crouch_pose(), STANCE_BLEND_SPEED * delta)
	var airborne_target := 0.0 if _grounded else 1.0
	var airborne_speed := AIRBORNE_RISE_SPEED if airborne_target > _airborne \
		else AIRBORNE_FALL_SPEED
	_airborne = move_toward(_airborne, airborne_target, airborne_speed * delta)
	# Moved toward 0 while grounded rather than snapped on touchdown, so the
	# dive and leap poses fade out of the air branch instead of turning into the
	# air loop on the frame the feet land.
	_dive_blend = move_toward(_dive_blend, 1.0 if (_dived and not _grounded) else 0.0,
		DIVE_BLEND_SPEED * delta)
	_leap_blend = move_toward(_leap_blend, 1.0 if (_leaping and not _grounded) else 0.0,
		LEAP_BLEND_SPEED * delta)

	# The bow. `is_drawing()` and `draw_fraction()` answer off the replicated
	# float on a remote BOG, so there is one code path for the archer and for
	# the seven people who need to see how far back that string is (D-065).
	# The pose is the aim plane under the legs and the drawn bow over the arms,
	# weighted by the charge; the torso turns to the crosshair through the
	# loose as well, which the charge does not (D-066).
	var drawing := _body.is_drawing()
	_draw_blend = move_toward(_draw_blend, 1.0 if drawing else 0.0, DRAW_BLEND_SPEED * delta)
	set(P_DRAW_SEEK, draw_time(_body.draw_fraction()))
	set(P_DRAW, _draw_blend)
	var aiming := drawing or bool(get(P_LOOSE_ACTIVE))
	_aim_blend = move_toward(_aim_blend, 1.0 if aiming else 0.0, DRAW_BLEND_SPEED * delta)

	# Which plane the legs are on: the archer's while the bow is up, the great
	# sword's while one is carried, the plain one otherwise.
	var plane := LOCO_STAND
	if aiming:
		plane = LOCO_AIM
	elif _armed() and _body.held_gear.has_sword():
		plane = LOCO_SWORD
	_point_plane(plane)

	# One number for the carry pose and for the prop's own lever (D-070). The
	# sword's carry is its own plane now, so its layer stays down.
	var carrying := 1.0 - _aim_blend
	if _body.is_spinning() or not _armed() or plane == LOCO_SWORD:
		carrying = 0.0
	_carry_blend = move_toward(_carry_blend, carrying, CARRY_BLEND_SPEED * delta)
	set(P_CARRY, _carry_blend)
	if _body.held_gear != null:
		_body.held_gear.set_carry(1.0 - _aim_blend if _armed() and not _body.is_spinning() else 0.0)

	# The emote. One flag, written by `BogCombat` on every peer, read here
	# exactly as the crouch and the draw are: a target of 0 or 1 and a move
	# toward it. Nothing else in this file knows the emote exists.
	_emote_blend = move_toward(_emote_blend, 1.0 if _body.is_emoting() else 0.0,
		EMOTE_BLEND_SPEED * delta)
	set(P_EMOTE, _emote_blend)

	set(P_STANCE, _stance)
	set(P_AIRBORNE, _airborne)
	set(P_DIVE, _dive_blend)
	set(P_LEAP, _leap_blend)
	set(P_SLIDE_LEAP, _slide_leap_blend)


func _point_plane(plane: String) -> void:
	if plane == _current_plane:
		return
	_current_plane = plane
	set(P_LOCO, plane)


## A horizontal world velocity turned into a position in the locomotion planes
## (D-066): x to the BOG's right, y forward, off `facing()`, which answers off
## the replicated yaw on a remote BOG.
##
## Rescaled so its **L1 norm is its own speed**: there are no diagonal clips,
## so a plane's rings are diamonds, and a velocity written in straight lands on
## the wrong ring at every bearing off an axis (measured at 1.20 of body speed
## skate on a walk diagonal against 0.15 straight on). The component clamp is
## for the Elder's boost, which runs faster than any clip.
func _body_relative(flat: Vector3) -> Vector2:
	var forward := _body.facing()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var move := Vector2(flat.dot(right), flat.dot(forward))
	var manhattan := absf(move.x) + absf(move.y)
	if manhattan > 0.0001:
		move *= move.length() / manhattan
	return Vector2(
		clampf(move.x, -Bog.RUN_SPEED, Bog.RUN_SPEED),
		clampf(move.y, -Bog.RUN_SPEED, Bog.RUN_SPEED))


## Where the body is in its arc, turned into an absolute clip time. `phase` is
## 0 leaving the ground, 0.5 at the apex and 1 about to land, read off the
## vertical velocity rather than a stopwatch — which is what makes a fall work
## with no extra clip: a BOG that walks off a ledge has vy of about 0, starts
## at the apex pose and falls through to the pre-landing pose.
static func arc_time(vy: float, launch: float, from: float, apex: float,
		to: float) -> float:
	var phase := clampf(0.5 * (1.0 - vy / maxf(launch, 0.01)), 0.0, 1.0)
	if phase < 0.5:
		return lerpf(from, apex, phase / 0.5)
	return lerpf(apex, to, (phase - 0.5) / 0.5)


## Both scrubbed air clips are told what time it is every frame, whether or
## not anything is looking at them, so the pose is already right on the frame
## the airborne blend starts to come up. On the ground `vy == 0` would read as
## apex and snap the pose back to the top of the leap on the landing frame
## (a 0.48 m hip pop, measured, D-029), so a grounded BOG holds the
## about-to-land pose instead, which is also the pose the landing one-shots
## pick the body up from.
func _scrub_air() -> void:
	if _grounded:
		set(P_LEAP_SEEK, marker("RunJump", "land"))
		set(P_SLIDE_LEAP_SEEK, marker(_slide_jump_role, "land"))
		set(P_DIVE_SEEK, marker("Roll", "land"))
		return
	# `vertical_speed()` and not `velocity.y`: on a remote BOG the replicated
	# value is a physics tick fresher. `jump_velocity()` rather than the
	# constant, because the Elder's boost multiplies it (D-040).
	var vy := _body.vertical_speed()
	_fall_speed = maxf(_fall_speed, -vy)
	set(P_LEAP_SEEK, arc_time(vy, _body.jump_velocity(),
		marker("RunJump", "lift"), marker("RunJump", "apex"), marker("RunJump", "land")))
	# The same arc against the launch speed a slide jump actually leaves at,
	# which is the ordinary one scaled (`Bog.SLIDE_JUMP_IMPULSE_SCALE`): read
	# against the unscaled jump this clip would reach its apex early and hang
	# there for the extra twelfth of a second the boost buys.
	set(P_SLIDE_LEAP_SEEK, arc_time(vy, _body.jump_velocity() * Bog.SLIDE_JUMP_IMPULSE_SCALE,
		marker(_slide_jump_role, "lift"), marker(_slide_jump_role, "apex"),
		marker(_slide_jump_role, "land")))
	set(P_DIVE_SEEK, arc_time(vy, _dive_launch,
		marker("Roll", "dive"), marker("Roll", "apex"), marker("Roll", "land")))


## Airtimes, from the two replicated serials and the grounded flag. The serials
## are the only news that cannot arrive late, so they open the airtime and the
## grounded flag only confirms it.
func _track_airtime(delta: float) -> void:
	# Read before the jump serial and not after it: a slide jump bumps both in
	# one physics tick and they arrive in one packet, so by the time either is
	# looked at both are new, and `_open_airtime` has to be told which kind of
	# take-off this was on the frame it opens.
	var slide_jumped := _body.sync_slide_jump_serial != _slide_jump_serial
	_slide_jump_serial = _body.sync_slide_jump_serial
	if _body.sync_jump_serial != _jump_serial:
		_jump_serial = _body.sync_jump_serial
		_open_airtime(false, slide_jumped)
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
## jump is a new airtime; a dive sets it and records the speed its arc is
## measured against — read off `vertical_speed()` for the replicated value.
##
## A jump from a run is the leap clip scrubbed by its arc; a jump from a stand
## fires the take-off one-shot and hangs in the air loop. The line between them
## is the walk speed, because that is where the leap's own run-up starts to
## look like the legs under it.
func _open_airtime(dived: bool, slide_jumped: bool = false) -> void:
	_airtime_open = true
	_airtime = 0.0
	_fall_speed = 0.0
	if dived:
		_dived = true
		_leaping = false
		_slide_leaping = false
		_dive_launch = maxf(_body.vertical_speed(), Bog.DIVE_UP_VELOCITY)
		return
	_dived = false
	var flat := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	# A slide jump is a leap whatever the stick was doing: it leaves at
	# `SLIDE_SPEED * 1.2` at the very least, which is over the walk this line
	# draws for everybody else anyway, and there is no version of it that is a
	# standing hop.
	_slide_leaping = slide_jumped
	_leaping = slide_jumped or flat.length() >= Bog.WALK_SPEED
	# Set rather than moved toward, and it is safe exactly here: the leap branch
	# carries no weight on the frame an airtime opens (`_leap_blend` is 0 and
	# rises over a twelfth of a second), so nothing is on screen to pop.
	_slide_leap_blend = 1.0 if _slide_leaping else 0.0
	if not _leaping:
		set(P_TAKEOFF, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Touchdown. The roll if the airtime was a dive, the heavy landing if the body
## came down fast, the light one otherwise, and nothing at all if the feet were
## barely off the ground.
func _close_airtime() -> void:
	if _airtime_open and _airtime >= LAND_MIN_AIRTIME:
		var shot := P_LAND
		if _dived:
			shot = P_ROLL
		elif _fall_speed >= HARD_LANDING_SPEED:
			shot = P_LAND_HARD
		elif _body.is_sliding():
			# A landing that is already a slide has its landing animation: the
			# slide's own one-shot, fired the same frame by `_track_slide` and
			# faded in over the air pose the crouch pre-armed (the feel round).
			# `Land` on top of it would be an absorb the body is not doing.
			#
			# Under the roll and the hard landing, and that order is the whole
			# rule: a dive still rolls out, and a body that came down at 11 m/s
			# still hits the floor like it — a slide cannot be used to walk away
			# from a fall the game has already decided was heavy.
			shot = ""
		if not shot.is_empty():
			set(shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_airtime_open = false
	_airtime = 0.0


## Drop the airtime without landing it: `revive_at` moves the body without
## running `move_and_slide`, and believing the teleport would open a new life
## with a landing absorb.
func _forget_airtime() -> void:
	_airtime_open = false
	_airtime = 0.0
	_dived = false
	_leaping = false
	_slide_leaping = false
	_slide_leap_blend = 0.0
	_jump_serial = _body.sync_jump_serial
	_dive_serial = _body.sync_dive_serial
	_slide_jump_serial = _body.sync_slide_jump_serial


## The loose, fired off the frame the replicated draw ends (D-065): no message
## starts it, so a remote BOG's bow snaps on the same frame as its string. A
## cancelled draw fires it too, which is the dry-fire the game needs on the
## one occasion it needs one.
func _track_draw() -> void:
	var drawing := _body.is_drawing()
	if drawing == _drawing:
		return
	_drawing = drawing
	if not drawing:
		play_loose()


## The slide is the one event with an end as well as a beginning: the physical
## slide can be cut short, so it is faded out rather than left to finish.
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

## Fire the throw. Called on every peer, so remote BOGs visibly throw. `rate`
## is set on the TimeScale node *before* the one-shot is fired, so the first
## frame is already playing at the rate the release was derived from.
func play_throw(rate: float = THROW_RATE) -> void:
	if tree_root == null:
		return
	set(P_THROW_RATE, maxf(rate, 0.01))
	set(P_THROW, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Fire the Elder's cast, at whatever rate `cast_rate_for_release` made of the
## dial. No default, because a cast has no authored speed to fall back on.
func play_cast(rate: float) -> void:
	if tree_root == null:
		return
	set(P_CAST_RATE, maxf(rate, 0.01))
	set(P_CAST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Fire the loose. No rate: a string is as fast as a string.
func play_loose() -> void:
	if tree_root == null:
		return
	set(P_LOOSE, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Start the drink, at whatever rate makes it take the channel's own length.
func play_drink(rate: float) -> void:
	if tree_root == null:
		return
	set(P_DRINK_RATE, maxf(rate, 0.01))
	set(P_DRINK, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Put the bottle down early: a channel interrupted has to look interrupted.
## FADE_OUT and not ABORT, so a cancelled drink hands back the way a finished
## one does.
func stop_drink() -> void:
	if tree_root == null:
		return
	set(P_DRINK, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


## Fire the great sword's swing. Re-firing mid-swing restarts it, which is what
## a chained swing out of a short recharge should do (D-068).
func play_swing(rate: float = SWING_RATE) -> void:
	if tree_root == null:
		return
	set(P_SWING_RATE, maxf(rate, 0.01))
	set(P_SWING, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Fire one slash of the chain, 1-based. Called on every peer, so a Bog you are
## watching slashes when its own player clicked.
##
## The pick is set **before** the shot is fired, exactly as every rate in this
## file is, and for the same reason: the first frame has to already be the right
## window. Re-firing while a slash is still running is what a chained click
## does, and restarting the shot is the correct answer to it — the blade of
## slash N+1 starts where the clip drew it starting, not where slash N's
## follow-through had got to.
func play_slash(index: int) -> void:
	if tree_root == null:
		return
	set(P_SLASH_PICK, _slash_input(clampi(index, 1, SLASH_COUNT)))
	set(P_SLASH, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Throw the fist. No rate: `PUNCH_RATE` is what the release was derived through
## and nothing moves it, so it is set once in `_ready` like the draw's seek.
func play_punch() -> void:
	if tree_root == null:
		return
	set(P_PUNCH, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## True from the moment a windup is fired until its fade-out has finished, or
## while a bow is being drawn: what asks is the camera, and what it wants to
## know is whether this BOG is in the middle of an attack it should be kept
## facing the crosshair through. The swing is deliberately not one of the
## answers (its direction is committed at the click) and neither is the drink.
func is_throwing() -> bool:
	if tree_root == null:
		return false
	if _body != null and _body.is_drawing():
		return true
	return bool(get(P_THROW_ACTIVE)) or bool(get(P_CAST_ACTIVE)) \
		or bool(get(P_LOOSE_ACTIVE))


## How far the torso is turned to the crosshair, 0 to 1 (D-066). Read by
## `BogAim`.
func aim_blend() -> float:
	return _aim_blend


## Is there actually a weapon in this BOG's hands (D-070)? Asked of the hands
## and not of `BogCombat`'s gates: `_refresh_hand` is the one place that
## decides what is in a fist, on every peer.
func _armed() -> bool:
	var gear := _body.held_gear
	return gear != null and (gear.is_carried() or gear.has_bow() or gear.has_sword())


## Point the carry layer at this BOG's own weapon (D-070). Called from `_ready`,
## and by `BogCombat.refresh_hand` for the lobby ring, where the pick can move.
## A holstered Bog points at its own hands instead, which is the one thing about
## this pick that is a *state* rather than the lobby's choice (the feel round).
## `BogCombat.refresh_hand` is what asks on the frame the key is pressed, so the
## shoulders and the fists change their mind together.
func set_carry_pose() -> void:
	if tree_root == null or _body == null:
		return
	if _body.is_holstered():
		set(P_CARRY_PICK, CARRY_FISTS)
		return
	set(P_CARRY_PICK, _carry_input(Loadout.sanitize(_body.weapon)))


## Airborne, in an airtime a dive was spent in.
func is_diving() -> bool:
	return _dived and not _grounded
