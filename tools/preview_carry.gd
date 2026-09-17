extends Node3D
## The carry layer: what a Bog's weapon does while it is only being carried.
## Development tool, not shipped.
##
##   # the tables — every weapon, every carried clip, headless, printed
##   Godot --headless --path . --script tools/snapshot.gd -- \
##       res://tools/preview_carry.tscn out/none.png 4 measure
##
##   # is the great sword's grip still the grip its own clips solve for (D-073)
##   Godot --headless --path . --script tools/snapshot.gd -- \
##       res://tools/preview_carry.tscn out/none.png 4 hilt
##
##   # the sheet: one weapon in Idle, Walk and Run, with and without the layer
##   Godot --path . --resolution 2400x900 --script tools/snapshot.gd -- \
##       res://tools/preview_carry.tscn out/carry_spear.png 25 sheet spear
##
##   # the fist, close, with the spear gripped at each palm z given (D-074)
##   Godot --path . --resolution 2400x900 --script tools/snapshot.gd -- \
##       res://tools/preview_carry.tscn out/carry_spear_palm.png 25 \
##       fist -0.04 -0.01
##
##   # the bottle's whole fit: the drinking fist, the two rotations, the scale
##   Godot --headless --path . --script tools/snapshot.gd -- \
##       res://tools/preview_carry.tscn out/none.png 4 potion
##
##   # the bottle in the hand across the channel, close or whole-body (D-075)
##   Godot --path . --resolution 2400x900 --script tools/snapshot.gd -- \
##       res://tools/preview_carry.tscn out/carry_potion_palm.png 25 drink fist
##   # ... and the same with a scale, a grip fraction and an outward offset
##   #     swept:  ... 25 drink fist 0.30 0.65 0.05
##
##   # the same three from overhead, which is where a bearing is an angle
##   Godot --path . --resolution 2400x900 --script tools/snapshot.gd -- \
##       res://tools/preview_carry.tscn out/carry_sword_bearings.png 25 \
##       elevations sword plan
##
## **One tool for three props, which is the opposite of how this repo has done
## it so far** — `preview_grip`, `preview_bow` and `preview_sword` are three
## files because the three fits are three different equations. This is one file
## because the carry is one *mechanism* (D-070): a filtered layer over the
## locomotion plane, at weight 1 whenever the weapon is in the hand and nothing
## else is happening to it. Three copies of that would be three chances for the
## layer this measures to stop being the layer the game composes.
##
## **The composition is done by hand and it is exactly what the graph does.**
## `carry` is an `AnimationNodeBlend2` filtered to `BogAnimator.UPPER_BODY_BONES`
## at weight 1, so every bone in that list takes its local pose from the carry
## clip and every other bone keeps whatever the plane below is producing. `_pose`
## below reproduces that a bone at a time, rather than standing an
## `AnimationTree` up: a tree needs frames to settle and a blend weight to be
## driven, and this reads the skeleton back inside the same call it wrote it in.

const BOG := preload("res://scenes/player/bog.tscn")

## How many samples of each locomotion clip. The same 24 `preview_bow` and
## `preview_sword` take, so the tables below can be read against the ones in
## D-066 and D-069 without a footnote about the grid.
const SAMPLES := 24

## Where in the carry clip the layer is sampled.
##
## **The carry clips loop and the layer plays them at rate 1**, so there is no
## single frame to measure — the pose breathes. Every sample of a locomotion
## clip is therefore paired with its *own* moment of the carry clip, walked
## across the whole loop, so a table row is the worst of the two cycles beating
## against each other rather than the worst of one held against one frame of the
## other. That is the case the game actually produces: nothing keeps the two
## cycles in phase and nothing should.
const CARRY_SAMPLES := 12

## How far above the floor the lowest end of a carried weapon has to stay.
##
## The spear's own grip was tuned to "both ends now stay at least 0.15 m up in
## every ground clip" (D-065), the carried bow was held to the same (D-066) and
## so was the carried sword (D-069). One floor for all three, because it is a
## fact about how tall grass is and not about which prop is in the fist.
const CARRY_MIN := 0.15

## How close a carried weapon may come to the Bog's own skin, in metres.
##
## D-065 measured the spear against the real skinned mesh and reported "the
## tightest is the throw follow-through at 6 cm"; every *carried* clip in that
## table is 0.11 m or better. This is the floor under those, and it is a floor
## rather than the measured best because a pose is allowed to be tighter than
## `Idle` was as long as nothing is actually inside the Bog.
##
## **It was zero between D-099 and the spear's own carry clip, and it decides
## again now.** D-099 disarmed it and said so in writing: every idle in the
## rebuilt library hung the arms against the body — `BreathingIdle`'s fist rests
## on the hip — so a prop in that fist sat against the trunk, and this
## measurement (the nearest skin vertex to the prop's axis) read 0.000 for a
## shaft lying *along* the belly exactly as it would for one *through* it. It
## could not tell the two apart, so it stopped deciding and the sheets were the
## judge. What D-099 said would give it back its meaning was "a carry clip that
## holds the fist away from the body — one row in `clips.json`", and that row is
## `SpearCarry`: the fist is up beside the head and the shaft leaves it in open
## air. So the threshold is D-074's own 0.06 again, and the spear's grip is
## solved against it rather than beside it.
##
## **The spear only, like `LEVEL_MAX` and `PALM_MAX`**, and for the same reason
## rather than a new one: the spear is the weapon whose shaft passes the body,
## and it is the only one that got a carry pose built around the prop. The bow
## still hangs off a fist beside the thigh and reads 0.004 m to the nearest skin
## vertex in every clip, which is a bow resting against a leg and not a bow
## inside one — the same measurement that could not tell the two apart before,
## on a pose nothing has changed. Its column is printed and decides nothing.
## `hilt`'s `carried` already asks the great sword the harder version of this.
const SKIN_MIN := 0.06

## How far off horizontal the **spear's** shaft may lie, in degrees, in any clip
## a Bog carries it through.
##
## **This exists because a prose claim about a grip went stale twice in two
## steps, in the same way both times** (D-072). D-065 promised "both ends stay at
## least 0.15 m up in every ground clip" and it was true of the six clips that
## existed; D-066 added six more and nobody re-ran the spear, so `StrafeWalkRight`
## shipped with the butt 0.012 m off the floor until D-070 found it. D-070 then
## promised "within 5 degrees of horizontal in all twelve clips" and it was true
## on the day; D-071 remirrored the four strafes one commit later and nobody
## re-ran the spear, so the sentence said 5 and the rig did 14.
##
## The two floors above never went stale, and the difference is the whole reason
## this constant is here: **they were checks and the flatness was a comment.** A
## clip that arrives, changes or is remirrored now fails the gate on the frame it
## lands instead of being found two steps later by somebody measuring something
## else. That is worth more than the grip the number describes.
##
## Thirty rather than the twenty-five the shipped grip measures, because a
## threshold is a promise with room in it and not a restatement of today's run —
## five degrees is narrower than any clip change that has actually happened here
## and wider than the noise in a 24-sample mean.
##
## **The spear only.** The bow's two ends are limb tips with no business end, so
## its elevation is a number to sort rows by and nothing else (`_prop_ends` says
## so); the great sword is carried hilt-up at the waist and reads +42 in `Drink`
## by design. "Lies level" is a claim about the one prop that is a line with a
## point on the end of it.
const LEVEL_MAX := 30.0

## How far the spear's shaft may pass from the centre of the Bog's own fist, in
## metres, in the pose it is carried in.
##
## **This is the number the user found by eye and no check could have told them**
## (D-074). The complaint was *"the spear visually is just outside the hand, it
## doesnt appear to be in the palm... it appears as if its attached to the back
## of the hand"*, and `HeldGear.GRIP_PALM` read 0.076 m — against a mitten that
## is 0.132 m thick, so the shaft's own axis passed **outside the fist
## altogether** while every other number on this page said PASS.
##
## It went unnoticed because the only thing the palm point had ever been checked
## against was the `mixamorig_RightHand`-weighted skin **at rest**, which is the wrist and
## not the fist: the three finger chains carry 918 of the mitten's 1,030
## vertices, and the hand a carried spear is held in is a closed one that the
## rest pose does not show. So this measures the whole mitten — `FIST_BONES`, the
## hand and every finger bone under it — skinned in the carry pose and averaged,
## which is a *fist* rather than a bone.
##
## 0.066 is half the mitten's own thickness across the palm, so the threshold is
## "the shaft's axis is inside the hand" and nothing more opinionated than that.
## The shipped grip reads 0.050 m; D-072's, which is the grip this check was
## written about, reads 0.076 and fails it.
##
## **The spear only**, for the same reason `LEVEL_MAX` is: the bow hangs off a
## fist by one limb and the great sword is held by two, and `hilt`'s `carried`
## already asks the sword the harder version of this question.
const PALM_MAX := 0.066

## Every bone the mitten hangs off: the hand and the three finger chains under
## it. All of them are in `BogAnimator.UPPER_BODY_BONES`, which is what makes the
## fist a single measurement rather than twelve — the carry clip owns the whole
## chain, so where the fist is *in the hand's own frame* is the carry clip's
## alone and the locomotion underneath cannot move it.
const FIST_BONES := ["mixamorig_RightHand",
	"mixamorig_RightHandThumb1", "mixamorig_RightHandThumb2", "mixamorig_RightHandThumb3", "mixamorig_RightHandThumb4",
	"mixamorig_RightHandIndex1", "mixamorig_RightHandIndex2", "mixamorig_RightHandIndex3", "mixamorig_RightHandIndex4",
	"mixamorig_RightHandMiddle1", "mixamorig_RightHandMiddle2", "mixamorig_RightHandMiddle3",
	"mixamorig_RightHandMiddle4"]

## The **left** mitten, which is the bow fist and is the hand a Bog drinks with
## (D-067, D-075). `FIST_BONES` one hand over, letter for letter, because the
## question `bottle` asks about the bottle is the question `palm` asks about the
## shaft and a second list that had drifted by one finger would be a second
## opinion about where this hand is.
const LEFT_FIST_BONES := ["mixamorig_LeftHand",
	"mixamorig_LeftHandThumb1", "mixamorig_LeftHandThumb2", "mixamorig_LeftHandThumb3", "mixamorig_LeftHandThumb4",
	"mixamorig_LeftHandIndex1", "mixamorig_LeftHandIndex2", "mixamorig_LeftHandIndex3", "mixamorig_LeftHandIndex4",
	"mixamorig_LeftHandMiddle1", "mixamorig_LeftHandMiddle2", "mixamorig_LeftHandMiddle3",
	"mixamorig_LeftHandMiddle4"]

## The head alone, out of `TRUNK_BONES`, cached for the table `-- potion`
## prints and for nothing else — which is worth a paragraph, because it is the
## one number here that was measured, looked at, and then deliberately **not**
## made a check (D-075).
##
## The obvious second clause for a bottle is *does the lip reach the mouth*: a
## grip can sit perfectly in a fist and still be a mime, which is D-074's own
## lesson one hand over, and `POTION_SCALE` is exactly the lever that would
## break it. Measured, it does not discriminate. The drinking hand is at the
## face by the middle of the clip and a Bog's head is a 0.40 m blob, so the lip
## comes within 0.015 m of it at **every** scale from 0.20 to 0.50 — 0.010 at
## the shipped 0.30 and 0.006 at half a metre of bottle. A threshold that
## passes every value of the lever it is supposed to police is not a threshold,
## which is D-074's own sentence about `PALM_MAX` turned on a candidate of its
## own: *a threshold whose own motivating case still passes is not a
## threshold.*
##
## So the scale is judged by eye off `out/carry_potion_palm.png`, the table is
## printed so that judgement has its evidence beside it, and this file does not
## pretend to cover it.
const HEAD_BONES := ["mixamorig_Head", "mixamorig_HeadTop_End"]

## How many moments of the drink window `bottle` and the sheets sample.
##
## More than `CARRY_SAMPLES`' twelve, because this window is not a loop that
## breathes — it is a gesture with a beginning, a middle and an end, and the
## three parts want telling apart. Twenty-five is one sample every 0.12 s of
## clip, which resolves the 0.7 s the head is back into six of them.
const DRINK_SAMPLES := 25

## Which moments of the channel the two drink sheets stand a Bog at, as
## fractions of the window.
##
## The whole-body sheet takes six evenly, which at the default two-second
## channel is one every 0.4 s and resolves the arm going up, the head going
## back and the arm coming down into separate pictures. The close one takes
## **three**, and 0.55 rather than 0.50 for the middle of them, because the
## clip does not arrive at the lips halfway — it arrives at 55% and stays
## there, which is the swallow D-067 had to teach `measure_clip` about.
const DRINK_BODY_FRACTIONS := [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
const DRINK_FIST_FRACTIONS := [0.0, 0.55, 1.0]

## Where the close drink sheet stands, in degrees round the Bog.
##
## Not `FIST_AZIMUTH` mirrored, which is what it started as and is what D-074's
## argument would predict. That sheet is seen from **behind** the shoulder
## because a shaft crossing a fist in the screen plane cannot be told from one
## passing through it, and the palm normal has to lie across the screen first.
## A bottle is not a line through a fist, it is a volume beside one, and the
## question it raises is the other kind — *is any of it inside the Bog* — which
## is answered from the **front** quarter, where the body's own silhouette is
## behind the bottle rather than in front of it. Rendered from behind the
## shoulder the bottle is occluded by the mitten at both ends of the window and
## the sheet says nothing; from -25 it is the whole argument.
const DRINK_AZIMUTH := -25.0

## Every clip a Bog carries a weapon *around* in.
##
## `preview_bow._carried_clips` and `preview_sword.CARRY_SKIP`'s list, kept
## letter for letter so that the before/after in D-070 is a comparison and not a
## re-measurement on a different set. The attack clips are excluded because a
## weapon being used is not a weapon being carried.
##
## **The jumps and the slide are excluded because a floor check means nothing in
## them**, which is why those two tools excluded them and is worth saying out
## loud now that `--all` will show them. A leaping Bog is not standing on the
## plane this measures against, and `Slide` puts its hips at 0.165 m by design —
## so a prop held at the waist is *supposed* to be near the ground there. Asked
## anyway, every weapon reads below zero in `Slide` both with the layer and
## without it (the spear -0.406 -> -0.477, the bow -0.470 -> -0.430, the sword
## -0.079 -> -0.075), which is a thing this game has always done and not a thing
## D-070 did. The jumps the layer genuinely improves: the spear's worst goes
## -0.534 -> +0.190 and the sword's -0.701 -> -0.160, because the arms stop
## being thrown about by a somersault.
## The clips a spear or a bow is carried around in (D-099): the plain plane,
## the crouch plane and the air loop. Everything else the animator names is a
## one-shot, a scrub, the archer's own plane (a bow is *up* there, not carried)
## or the great sword's, which has its own list below.
const CARRIED := ["Idle", "Walk", "Run", "WalkBack", "RunBack",
	"StrafeWalkLeft", "StrafeWalkRight", "StrafeLeft", "StrafeRight",
	"CrouchIdle", "CrouchWalk", "CrouchWalkBack", "CrouchStrafeLeft", "CrouchStrafeRight",
	"AirLoop"]
## The clips a great sword is carried in: its own plane, whose idle is its
## carry pose (D-098). `SwordCarry` is the layer clip as well, so it is both.
const SWORD_CARRIED := ["SwordCarry", "SwordWalk", "SwordRun", "SwordWalkBack", "SwordRunBack",
	"SwordStrafeWalkLeft", "SwordStrafeWalkRight", "SwordStrafeLeft", "SwordStrafeRight"]

## The three carried clips the sheet draws, and the order it draws them in.
const SHEET_CLIPS := ["Idle", "Walk", "Run"]

const FRAME_LOW := -0.2
const FRAME_HIGH := 2.5
const FRAME_MIN := 2.9
const FRAME_MARGIN := 2.2
const VIEW_AZIMUTH := 35.0
const VIEW_ELEVATION := 14.0
const SHEET_SPREAD := 1.7
## Slots of empty floor between the un-layered half of the sheet and the layered
## half, so the eye is told where the comparison is rather than having to count.
const SHEET_GAP := 0.8
## How far apart `elevations` stands its row. Wider than `SHEET_SPREAD`, because
## that sheet is seen obliquely and this one head-on with 1.24 m of shaft lying
## across every body.
const ELEVATION_SPREAD := 2.4
## How the `fist` mode is framed (D-074). Behind the Bog's right shoulder rather
## than in front of it, and 0.9 m of Bog per column rather than 1.7, because that
## sheet is about a body and this one is about a hand.
const FIST_AZIMUTH := 125.0
const FIST_ELEVATION := 15.0
const FIST_SPREAD := 0.9
## The window each fist gets, in metres — the frame is this plus however far
## apart the row stands, so adding a column widens the sheet instead of shrinking
## every hand in it.
const FIST_FRAME := 0.55

@export var samples: int = SAMPLES

## The skinned body, cached: `[Vector3 rest position, PackedInt32Array bones,
## PackedFloat32Array weights]` per vertex, plus the bind poses. Built once and
## skinned at every pose, because the alternative is reading a 5,000-vertex
## surface out of the mesh twenty-four times a clip.
var _skin_rest: PackedVector3Array = PackedVector3Array()
var _skin_bones: PackedInt32Array = PackedInt32Array()
var _skin_weights: PackedFloat32Array = PackedFloat32Array()
## Bone influences per vertex, read off the mesh in `_build_skin`.
var _stride := 4
var _skin_binds: Array[Transform3D] = []
var _skin_bone_of_bind: PackedInt32Array = PackedInt32Array()

## The spear hand's own mitten, cached the same way and in the same pass — the
## hand and every finger bone under it, which `_build_skin` keeps separately
## because `TRUNK_BONES` deliberately throws the arms away.
var _fist_rest: PackedVector3Array = PackedVector3Array()
var _fist_bones: PackedInt32Array = PackedInt32Array()
var _fist_weights: PackedFloat32Array = PackedFloat32Array()

## The **drinking** hand's mitten and the head, cached in the same pass and
## for the same reason (D-075). The left fist is where the bottle goes and
## the head is what it has to arrive at; neither is in `TRUNK_BONES` or in
## `FIST_BONES`, so neither existed until a prop was put in the other hand.
var _left_rest: PackedVector3Array = PackedVector3Array()
var _left_bones: PackedInt32Array = PackedInt32Array()
var _left_weights: PackedFloat32Array = PackedFloat32Array()
var _head_rest: PackedVector3Array = PackedVector3Array()
var _head_bones: PackedInt32Array = PackedInt32Array()
var _head_weights: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[3] if args.size() > 3 else "measure"
	if mode == "measure":
		_measure(args.size() > 4 and args[4] == "--all")
		get_tree().quit()
		return
	if mode == "poses":
		_poses()
		get_tree().quit()
		return
	if mode == "potion":
		_potion()
		get_tree().quit()
		return
	if mode == "drink":
		_drink(args[4] if args.size() > 4 else "fist",
			Vector3(float(args[5]), float(args[6]),
			float(args[7]) if args.size() > 7 else 0.0) if args.size() > 6
			else Vector3.ZERO)
		return
	if mode == "hilt":
		_hilt()
		get_tree().quit()
		return
	if mode == "solve":
		_solve(args[4] if args.size() > 4 else "spear",
			args[5] if args.size() > 5 else "",
			args[6] if args.size() > 6 else "",
			args[7] if args.size() > 7 else "")
		get_tree().quit()
		return
	if mode == "sweep":
		_sweep(args[4] if args.size() > 4 else "spear",
			args[5] if args.size() > 5 else "",
			float(args[6]) if args.size() > 6 else SWEEP_DEGREES,
			args[7] if args.size() > 7 else "")
		get_tree().quit()
		return
	if mode == "fist":
		var zs: Array[float] = []
		for i in range(4, args.size()):
			zs.append(float(args[i]))
		_fist(zs)
		return
	if mode == "elevations":
		_elevations(args[4] if args.size() > 4 else "spear",
			args[5] if args.size() > 5 else "side")
		return
	if mode == "candidates":
		_candidates(args.slice(4))
		return
	_sheet(args[4] if args.size() > 4 else "spear",
		args[5] if args.size() > 5 else "",
		args[6] if args.size() > 6 else "")


# ------------------------------------------------------------- the numbers ---

func _measure(everything: bool) -> void:
	var bog := _bare_bog()
	var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := bog.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_build_skin(bog, skeleton)
	var clips := _carried_clips(player, everything)
	var failures := 0

	var spear_level := 0.0
	for weapon: int in [Loadout.Weapon.SPEAR, Loadout.Weapon.BOW,
			Loadout.Weapon.SWORD]:
		var row := _report(bog, skeleton, player,
			_carried_clips(player, everything, weapon), weapon)
		failures += int(row[0])
		if weapon == Loadout.Weapon.SPEAR:
			spear_level = row[1]

	failures += _report_card(bog, skeleton, player, clips)
	failures += _report_palm(skeleton, player)
	failures += _report_bottle(skeleton, player)

	# The spear lies level, and this is the line that keeps that a fact rather
	# than a sentence somebody wrote on a day it was true (`LEVEL_MAX` says why).
	if spear_level <= LEVEL_MAX:
		print("preview_carry: the spear's shaft is never more than %.0f deg off "
			% spear_level + "horizontal in a carried clip, against %.0f allowed "
			% LEVEL_MAX + "— level PASS")
	else:
		print("preview_carry: level FAIL — the spear's shaft reaches %.0f deg "
			% spear_level + "off horizontal in a carried clip, against %.0f "
			% LEVEL_MAX + "allowed. A clip has changed under the grip: re-solve "
			+ "it with `-- solve spear Idle` rather than widening this.")
		failures += 1

	# `GRIP_OFFSET` is a `const` that has to equal a function of `GRIP_ROTATION`,
	# because GDScript cannot call a static to initialise a constant (see its
	# header). This is what keeps the two in step: change the rotation without
	# pasting the new offset and the gate says so, rather than the shaft quietly
	# stopping passing through the palm.
	var derived := HeldGear.grip_offset(HeldGear.GRIP_ROTATION)
	var drift := derived.distance_to(HeldGear.GRIP_OFFSET)
	# The bottle's is the same constant one hand over and carries a scale as
	# well as a rotation (D-075), so it is the one of the two that goes
	# stale if somebody decides the potion looked chunky. One verdict for
	# both, because they are one statement: a derivation written down as a
	# number has to still equal the function it came from.
	var potion := HeldGear.potion_offset()
	var potion_drift := potion.distance_to(HeldGear.POTION_GRIP_OFFSET)
	if drift <= DERIVED_MAX and potion_drift <= DERIVED_MAX:
		print("preview_carry: GRIP_OFFSET is %v, %.4f m off its own derivation, "
			% [HeldGear.GRIP_OFFSET, drift] + "and POTION_GRIP_OFFSET is %v, "
			% HeldGear.POTION_GRIP_OFFSET + "%.4f m off its own — derived PASS"
			% potion_drift)
	else:
		print("preview_carry: derived FAIL — GRIP_OFFSET is %v against "
			% HeldGear.GRIP_OFFSET + "grip_offset(GRIP_ROTATION) %v (%.4f m "
			% [derived, drift] + "apart), and POTION_GRIP_OFFSET is %v against "
			% HeldGear.POTION_GRIP_OFFSET + "potion_offset() %v (%.4f m apart)"
			% [potion, potion_drift])
		failures += 1

	if failures == 0:
		print("preview_carry: every weapon clears %+.2f m of floor in every carried "
			% CARRY_MIN + "clip, and the spear %+.2f m of trunk — carry PASS" % SKIN_MIN)
	else:
		print("preview_carry: carry FAIL — %d rows are out" % failures)


## One weapon's table: the prop as the game actually composes it, and — for the
## comparison D-070 is — the same grip with the carry layer taken away.
##
## The right-hand column is what ships and is what the verdict is taken from.
## The left one is the same rigid attachment on the locomotion's own bare arms,
## which is what every carried prop in this game was before this step, and it is
## here so that the layer's contribution is a number in the log rather than a
## claim in a record.
## Returns `[rows that are out, the worst elevation off horizontal]`, because
## `_measure` asserts on the second for the spear and there is no cheap way to
## ask again — every row of this table costs 24 poses and a 3,587-vertex skin
## scan, so the number leaves with the verdict rather than being re-measured.
func _report(bog: Bog, skeleton: Skeleton3D, player: AnimationPlayer,
		clips: Array[String], weapon: int) -> Array:
	var carry := Loadout.carry_clip(weapon)
	print("preview_carry: %s, carried over %s"
		% [Loadout.weapon_name(weapon), "nothing" if carry.is_empty() else carry])
	print("  %-16s %22s %22s %s"
		% ["", "no carry layer", "as shipped", "nearest trunk"])
	var failures := 0
	var skin_floor := SKIN_MIN if weapon == Loadout.Weapon.SPEAR else 0.0
	var worst_off := INF
	var worst_on := INF
	var skin := INF
	var level := 0.0
	for clip: String in clips:
		var off := _clearance(bog, skeleton, player, clip, "", weapon)
		var on := _clearance(bog, skeleton, player, clip, carry, weapon)
		worst_off = minf(worst_off, off[0])
		worst_on = minf(worst_on, on[0])
		skin = minf(skin, on[2])
		level = maxf(level, absf(on[1]))
		var line := "  %-16s %+9.3f m %+7.0f deg %+9.3f m %+7.0f deg     %.3f m" \
			% [clip, off[0], off[1], on[0], on[1], on[2]]
		if on[0] < CARRY_MIN or on[2] < skin_floor:
			line += "  <-- out"
			failures += 1
		print(line)
	print("  worst lowest end %+.3f m as shipped, %+.3f m without the layer; "
		% [worst_on, worst_off] + "nearest trunk %.3f m; furthest off "
		% skin + "horizontal %.0f deg" % level)
	return [failures, level]


## The letter card, which rides the spear's grip and therefore moved when the
## grip did (D-035, D-070).
##
## **Measured with the layer off, which is the pose it is actually held in.** A
## letter hold disarms a Bog — `has_spear()` says so and has since D-035 — so
## there is no weapon for a carry pose to be the pose of, `BogAnimator._armed()`
## answers no, and the arms go back to whatever the locomotion plane is doing.
## The card then sits `CARD_ALONG_SHAFT` along the *virtual* shaft out of that
## hand, which after D-070 points across the body where it used to point up the
## forearm.
##
## D-035 measured "the card's lowest centre is 0.44 m and its half-height is
## 0.21 m, so the bottom of the letter stays 23 cm up" and wrote the number into
## a comment. It was a comment about a grip that has since moved eighty degrees,
## which is exactly the kind of number that should have been a check — so here it
## is as one.
func _report_card(bog: Bog, skeleton: Skeleton3D, player: AnimationPlayer,
		clips: Array[String]) -> int:
	var hand := skeleton.find_bone(HeldGear.HAND_BONE)
	var half := 0.5 * Pickup.LETTER_HEIGHT * HeldGear.CARD_SCALE
	var lowest := INF
	var lowest_in := ""
	for clip: String in clips:
		var length := player.get_animation(clip).length
		for i in samples:
			_pose(player, skeleton, clip, length * float(i) / float(samples),
				"", 0.0)
			var at := bog.global_transform * skeleton.global_transform \
				* skeleton.get_bone_global_pose(hand) * HeldGear.card_offset()
			if at.y < lowest:
				lowest = at.y
				lowest_in = clip
	var bottom := lowest - half
	if bottom >= 0.0:
		print("preview_carry: the letter card's lowest centre is %.3f m (%s) "
			% [lowest, lowest_in] + "and its half-height %.3f, so the bottom of "
			% half + "it is %.3f m up — card PASS" % bottom)
		return 0
	print("preview_carry: card FAIL — the letter card's lowest centre is %.3f m "
		% lowest + "in %s and its half-height %.3f, so %.3f m of it is in the "
		% [lowest_in, half, -bottom] + "ground")
	return 1


## The shaft against the **hand**, which is the one thing every table above
## measures around rather than at (D-074).
##
## Everything else on this page asks where the spear is relative to the Bog's
## body, its floor or the horizon. None of that can see the complaint the user
## actually raised — *"it doesnt appear to be in the palm... it appears as if its
## attached to the back of the hand"* — because a shaft riding the knuckles is
## exactly as far from the trunk, exactly as level and exactly as high off the
## grass as one in the fist. It is a different question and it needs its own
## number: how far the shaft's axis passes from the centre of the mitten, in the
## hand's own frame.
##
## **Measured in the carried `Idle`, and that is the whole pose.** Every bone the
## mitten hangs off is in `UPPER_BODY_BONES` (`FIST_BONES` says so), so the fist's
## shape *in the hand's own frame* belongs to the carry clip and nothing the
## locomotion plane does can move it — the same thing that makes the trunk column
## of every table above read one number in all twelve clips. Twelve moments of
## the carry loop are sampled anyway, because the clip breathes, and the worst is
## the one reported.
##
## The spear only: `PALM_MAX` says why.
func _report_palm(skeleton: Skeleton3D, player: AnimationPlayer) -> int:
	if _fist_rest.is_empty():
		push_warning("preview_carry: no hand mesh; the palm is not measured")
		return 0
	var carry := Loadout.carry_clip(Loadout.Weapon.SPEAR)
	var hand := skeleton.find_bone(HeldGear.HAND_BONE)
	var dir := HeldGear.shaft_direction()
	var length := player.get_animation(carry).length
	var worst := 0.0
	var at_worst := Vector3.ZERO
	for i in CARRY_SAMPLES:
		_pose(player, skeleton, "Idle", 0.0, carry,
			length * float(i) / float(CARRY_SAMPLES))
		var centre := _fist_centre(skeleton, hand, _fist_rest,
			_fist_bones, _fist_weights)
		# Perpendicular to the shaft, because sliding the grip *along* the shaft
		# is `GRIP_FRACTION`'s business and is not what is being asked here.
		var to_fist := centre - HeldGear.GRIP_PALM
		var off := (to_fist - dir * to_fist.dot(dir)).length()
		if off > worst:
			worst = off
			at_worst = centre
	if worst <= PALM_MAX:
		print("preview_carry: the spear's shaft passes %.3f m from the centre "
			% worst + "of the fist, which is at %v in the hand's own frame, "
			% at_worst + "against %.3f allowed — palm PASS" % PALM_MAX)
		return 0
	print("preview_carry: palm FAIL — the spear's shaft passes %.3f m from the "
		% worst + "centre of the fist (%v in the hand's own frame) against "
		% at_worst + "%.3f allowed, so it is riding the outside of the hand rather "
		% PALM_MAX + "than sitting in it. Move `HeldGear.GRIP_PALM`, which is "
		+ "what that constant is for, and re-read the trunk column above for "
		+ "what it cost.")
	return 1


## Where the middle of the spear hand is, in hand-local metres, at whatever pose
## the skeleton is currently in — the mitten skinned by the formula the GPU runs
## and averaged, which is `_nearest_skin`'s method asked for a centre instead of
## a minimum.
func _fist_centre(skeleton: Skeleton3D, hand: int,
		rest: PackedVector3Array, of_bone: PackedInt32Array,
		share: PackedFloat32Array) -> Vector3:
	var bones: Array[Transform3D] = []
	for i in _skin_binds.size():
		var bone := _skin_bone_of_bind[i]
		bones.append(Transform3D.IDENTITY if bone < 0
			else skeleton.get_bone_global_pose(bone) * _skin_binds[i])
	var to_hand := skeleton.get_bone_global_pose(hand).affine_inverse()
	var sum := Vector3.ZERO
	for v in rest.size():
		var out := Vector3.ZERO
		for j in _stride:
			var w := share[v * _stride + j]
			if w <= 0.0:
				continue
			var bind := of_bone[v * _stride + j]
			if bind < 0 or bind >= bones.size():
				continue
			out += (bones[bind] * rest[v]) * w
		sum += to_hand * out
	return sum / float(maxi(rest.size(), 1))



## The bottle against the **left** hand, which is `_report_palm`'s question
## asked of the one prop in this game that is not a weapon (D-075).
##
## The same number and the same method: how far the bottle's axis passes from
## the centre of the mitten, in the hand's own frame, measured off the whole
## mitten rather than off the `mixamorig_LeftHand`-weighted skin at rest. D-074's finding
## is not about the spear, it is about hands — 918 of the right mitten's 1,030
## vertices hang off the finger chains and the left one's 1,073 do the same, so
## a bone's own vertices are the wrist either way.
##
## **Sampled across the whole drink window and reported at its worst**, because
## a bottle has to be in the hand for the whole two seconds and not only at the
## lips. It costs nothing: every bone the mitten hangs off is in
## `UPPER_BODY_BONES` and the drink layer owns all of them, so the fist's shape
## in the hand's own frame is the clip's alone and moves 0.0002 m across the
## window — the same fact that makes the trunk column of every table above read
## one number in all twelve clips.
##
## The pose is `Drink` layered over `Idle`, which is what the graph composes: a
## `OneShot` filtered to `UPPER_BODY_BONES` over whatever the locomotion plane
## is doing, at weight 1 (D-067). `Idle` underneath because a Bog that is
## moving is a Bog that is not drinking — `CHANNEL_MOVE_SPEED` says so — which
## makes this the one measurement on this page with nothing to average over.
##
## **What it does not check is `POTION_SCALE`**, and `HEAD_BONES` carries why.
func _report_bottle(skeleton: Skeleton3D, player: AnimationPlayer) -> int:
	if _left_rest.is_empty():
		push_warning("preview_carry: no left hand mesh; the bottle is not measured")
		return 0
	var hand := skeleton.find_bone(HeldGear.BOW_HAND_BONE)
	var dir := HeldGear.potion_direction()
	var worst := 0.0
	var at_worst := Vector3.ZERO
	for i in DRINK_SAMPLES:
		_pose(player, skeleton, "Idle", 0.0, "Drink", _drink_time(i))
		var centre := _fist_centre(skeleton, hand, _left_rest, _left_bones,
			_left_weights)
		# Perpendicular to the bottle, because sliding the grip *along* it is
		# `POTION_GRIP_FRACTION`'s business and is not what is being asked.
		var to_fist := centre - HeldGear.POTION_PALM
		var off := (to_fist - dir * to_fist.dot(dir)).length()
		if off > worst:
			worst = off
			at_worst = centre
	if worst <= PALM_MAX:
		print("preview_carry: the bottle's axis passes %.3f m from the centre "
			% worst + "of the drinking fist, which is at %v in the hand's own "
			% at_worst + "frame, against %.3f allowed — bottle PASS" % PALM_MAX)
		return 0
	print("preview_carry: bottle FAIL — the bottle's axis passes %.3f m from "
		% worst + "the centre of the drinking fist (%v in the hand's own frame) "
		% at_worst + "against %.3f allowed, so it is beside the hand rather than "
		% PALM_MAX + "in it. Move `HeldGear.POTION_PALM`, which is what that "
		+ "constant is for, and re-run `-- potion` for the centre it should be.")
	return 1


## Which moment of the drink window sample `i` is, in the clip's own seconds.
##
## The **window** and not the clip, because the clip is 6.117 s of which
## `BogAnimator` plays 2.933 (D-067): the 1.267 s of stillness before the arm
## starts and the 1.917 s after it stops are frames no player ever sees, and a
## bottle measured through them would be measured mostly against a Bog standing
## still with its arms down.
func _drink_time(i: int) -> float:
	return BogAnimator.DRINK_CLIP_START \
		+ (BogAnimator.DRINK_CLIP_END - BogAnimator.DRINK_CLIP_START) \
		* float(i) / float(maxi(DRINK_SAMPLES - 1, 1))


## How near a world point comes to the Bog's own skinned head.
##
## `_nearest_skin`'s method with two differences and both are the question:
## `HEAD_BONES` rather than the trunk, and one point rather than a segment. The
## thing being asked is whether the bottle's **lip** arrived at the face, and a
## segment would be answered by whichever part of the bottle happened to be
## nearest the chin.
func _nearest_head(skeleton: Skeleton3D, p: Vector3) -> float:
	if _head_rest.is_empty() or _skin_binds.is_empty():
		return INF
	var bones: Array[Transform3D] = []
	for i in _skin_binds.size():
		var bone := _skin_bone_of_bind[i]
		bones.append(Transform3D.IDENTITY if bone < 0
			else skeleton.get_bone_global_pose(bone) * _skin_binds[i])
	var nearest := INF
	for v in _head_rest.size():
		var out := Vector3.ZERO
		for j in _stride:
			var w := _head_weights[v * _stride + j]
			if w <= 0.0:
				continue
			var bind := _head_bones[v * _stride + j]
			if bind < 0 or bind >= bones.size():
				continue
			out += (bones[bind] * _head_rest[v]) * w
		nearest = minf(nearest, p.distance_to(skeleton.global_transform * out))
	return nearest

## The lowest end of `weapon`'s prop above the floor through one locomotion
## clip, the mean elevation of its long axis, and how near it gets to the Bog's
## own skin — as `[metres, degrees, metres]`.
##
## `carry` empty means the layer is off, which is the pose the game shipped
## before D-070 and is the left-hand column of every table above.
func _clearance(bog: Bog, skeleton: Skeleton3D, player: AnimationPlayer,
		clip: String, carry: String, weapon: int,
		tune: Vector3 = Vector3.INF) -> Array:
	var hand := skeleton.find_bone(_hand_bone(weapon))
	var length := player.get_animation(clip).length
	var carry_length := 0.0
	if not carry.is_empty():
		carry_length = player.get_animation(carry).length
	var off_hand := skeleton.find_bone(HeldGear.BOW_HAND_BONE
		if weapon != Loadout.Weapon.BOW else HeldGear.HAND_BONE)
	var lowest := INF
	var nearest := INF
	var reach := INF
	var elevation := 0.0
	# Where the business end points round the Bog, summed as a **vector** rather
	# than as degrees (D-073): a bearing is an angle on a circle, and 24 samples
	# either side of the -180/+180 seam average to zero if they are added as
	# numbers. Every other column here is a min or a scalar mean and can be.
	var bearing := Vector2.ZERO
	var count := 0
	for i in samples:
		var time := length * float(i) / float(samples)
		var carry_time := 0.0
		if carry_length > 0.0:
			carry_time = carry_length \
				* float(i % CARRY_SAMPLES) / float(CARRY_SAMPLES)
		_pose(player, skeleton, clip, time, carry, carry_time)
		var grip := bog.global_transform * skeleton.global_transform \
			* skeleton.get_bone_global_pose(hand) * _prop_transform(weapon, tune)
		var ends := _prop_ends(weapon)
		var a: Vector3 = grip * ends[0]
		var b: Vector3 = grip * ends[1]
		var body := _prop_body(weapon)
		var ba: Vector3 = grip * body[0]
		var bb: Vector3 = grip * body[1]
		lowest = minf(lowest, minf(a.y, b.y))
		elevation += rad_to_deg(asin(clampf((b.y - a.y)
			/ maxf(a.distance_to(b), 0.0001), -1.0, 1.0)))
		bearing += Vector2(b.x - a.x, b.z - a.z).normalized()
		count += 1
		nearest = minf(nearest, _nearest_skin(bog, skeleton, ba, bb))
		# How near the *other* fist comes to the weapon, which is the question
		# "does this pose look like it is holding the thing": a two-handed carry
		# whose second hand closes on air is worse than no carry pose at all.
		var second := bog.global_transform * skeleton.global_transform 			* skeleton.get_bone_global_pose(off_hand)
		reach = minf(reach, _point_to_segment(second.origin, a, b))
	return [lowest, elevation / float(maxi(count, 1)), nearest, reach,
		rad_to_deg(atan2(bearing.x, -bearing.y))]


## Where this weapon's prop sits in its hand, and which two points of it can
## touch grass — the model's own two ends, off its own axis rather than off a
## bounding box, which is what `preview_sword._carry_clearance` measures and for
## the same reason.
func _prop_transform(weapon: int, tune: Vector3 = Vector3.INF) -> Transform3D:
	match weapon:
		Loadout.Weapon.BOW:
			# The bow's lever is a **tilt** out of a grip an equation solved
			# against `Draw`, so `tune`'s first two components are that tilt.
			var tilt := HeldGear.CARRY_TILT if tune == Vector3.INF \
				else Vector2(tune.x, tune.y)
			return Transform3D(HeldGear.bow_basis(tilt)
				.scaled(Vector3.ONE * HeldGear.BOW_SCALE),
				HeldGear.BOW_GRIP_OFFSET)
		Loadout.Weapon.SWORD:
			# The sword's is the **grip**, since D-070 took its tilt away: the
			# carry pose is a clip drawn holding this prop, so the question a
			# sweep can still ask is whether the solved grip itself is wrong, not
			# whether something should be rotated out of it.
			if tune == Vector3.INF:
				return HeldGear.sword_transform()
			# **The offset follows the rotation** (D-073). It did not until then,
			# and every cell of a `sweep sword` table printed before that was a
			# sword sliding out of the palm rather than turning in it —
			# `HeldGear.sword_offset`'s header says how that happened. The scale
			# is held at the shipped one on purpose: it *is* the reach (D-068),
			# and a sweep that moved it would be sweeping the weapon's range
			# along with its angle.
			return HeldGear.sword_transform(HeldGear.SWORD_SCALE,
				HeldGear.sword_offset(tune), tune)
		_:
			# The spear has no tilt and never had one: its lever is the grip, and
			# `HeldGear.spear_transform` is the derivation that carries the butt
			# along with it so the shaft goes on passing through the palm.
			return HeldGear.spear_transform(
				HeldGear.GRIP_ROTATION if tune == Vector3.INF else tune)


## The two ends, in the prop's own model units. The second is the **pointing**
## end, so the elevation above comes out positive when the business end is up:
## a spear's tip, a sword's pommel (its model runs point-to-pommel, so the point
## is the origin), and for the bow the two limb tips, which have no business end
## and whose elevation is therefore only a number to sort rows by.
func _prop_ends(weapon: int) -> Array:
	match weapon:
		Loadout.Weapon.BOW:
			# The model runs +-0.5 along its own X and the scale is already in
			# the basis `_prop_transform` built, which is the one place this
			# differs from `preview_bow._carry_clearance`: that tool multiplies
			# BOW_SCALE back in because it composes an unscaled basis by hand.
			return [Vector3(0.5, 0.0, 0.0), Vector3(-0.5, 0.0, 0.0)]
		Loadout.Weapon.SWORD:
			return [Vector3(0.0, HeldGear.SWORD_LENGTH, 0.0), Vector3.ZERO]
		_:
			return [Vector3.ZERO, Vector3(0.0, HeldGear.SHAFT_LENGTH, 0.0)]


## The part of the prop that has to miss the Bog, in model units — which is not
## always the part that has to miss the floor.
##
## For a spear and a bow it is the whole thing: a shaft is gripped in its middle
## and a bow hangs off a fist, and every centimetre of either is out in the air
## where it can cross a face. A great sword is **held by its hilt in two fists at
## the waist**, so the top sixth of that model is inside the hands by
## construction and measuring it against the belly it is pressed to reports 4 cm
## and means nothing. What can be wrong is the **blade**, which is the same
## segment `HeldGear.sword_blade()` resolves a hit against — point to crossguard
## — and is the part of the weapon that is not in a hand.
func _prop_body(weapon: int) -> Array:
	if weapon == Loadout.Weapon.SWORD:
		return [Vector3.ZERO, Vector3(0.0, HeldGear.SWORD_GUARD, 0.0)]
	return _prop_ends(weapon)


func _hand_bone(weapon: int) -> String:
	return HeldGear.BOW_HAND_BONE if weapon == Loadout.Weapon.BOW \
		else HeldGear.HAND_BONE


## Put the skeleton in the pose the graph would compose: `clip` at `time` under
## a `carry` layer at weight 1, filtered to `BogAnimator.UPPER_BODY_BONES`.
##
## Two passes, because that is what a filtered blend is: the layer's local poses
## are read first, then the plane is posed, then the layer's bones are written
## over it. Writing straight into the skeleton is exactly what the `Blend2` does
## — a filter at weight 1 is "this input owns these tracks" — and doing it here
## rather than through an `AnimationTree` is what lets the answer be read back in
## the same call.
func _pose(player: AnimationPlayer, skeleton: Skeleton3D, clip: String,
		time: float, carry: String, carry_time: float) -> void:
	var over: Array = []
	if not carry.is_empty():
		player.play(carry)
		player.seek(carry_time, true, true)
		player.pause()
		for bone: String in BogAnimator.UPPER_BODY_BONES:
			var idx := skeleton.find_bone(bone)
			if idx < 0:
				continue
			over.append([idx, skeleton.get_bone_pose_position(idx),
				skeleton.get_bone_pose_rotation(idx),
				skeleton.get_bone_pose_scale(idx)])
	player.play(clip)
	player.seek(time, true, true)
	player.pause()
	for row: Array in over:
		skeleton.set_bone_pose_position(row[0], row[1])
		skeleton.set_bone_pose_rotation(row[0], row[2])
		skeleton.set_bone_pose_scale(row[0], row[3])
	skeleton.force_update_all_bone_transforms()


# ---------------------------------------------------------------- the sweep ---

## How far either side of a candidate the sweep looks, and in how many steps.
const SWEEP_DEGREES := 10.0
const SWEEP_STEPS := 9

## Sweep the one lever each weapon has, **with the carry layer on**, and print
## what it buys (D-070).
##
## This is `preview_bow._sweep_carry` and `preview_sword._sweep_carry` asked a
## different question, and the difference is the whole point of the layer. Those
## two sweep a tilt against **twelve different hand orientations**, because a
## rigid grip on a fist the locomotion throws about is a compromise across every
## clip at once — D-065 said so in as many words: *"the hand's world orientation
## differs by more than 100 deg between a raised guard and a hanging arm, so a
## grip that stands the shaft up in one lays it over in the other."* With the
## layer on, every clip's upper body is the **same** pose, so there is one
## orientation to solve for and the sweep has a peak instead of a plateau
## somebody had to settle on.
##
## The spear's lever is its **grip**, not a tilt: it has never had a tilt and
## does not get one here. What moves is `GRIP_ROTATION` itself, with
## `HeldGear.grip_offset` carrying the butt along so the shaft goes on passing
## through the palm.
func _sweep(weapon_name: String, carry_override: String = "",
		span: float = SWEEP_DEGREES, base_override: String = "") -> void:
	var weapon := Loadout.sanitize(Loadout.from_name(weapon_name))
	var bog := _bare_bog()
	var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := bog.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_build_skin(bog, skeleton)
	var clips := _carried_clips(player, false)
	var carry := Loadout.carry_clip(weapon)
	if not carry_override.is_empty():
		carry = "" if carry_override == "none" else carry_override
	# The lever this sweep is centred on, overridable so that a *superseded* one
	# can be re-measured against the same yardstick as the one that replaced it.
	# The before/after tables in D-070 are that: `-- sweep spear none 0
	# -12,0,-15` re-runs D-065's own grip, with no layer, through this tool's
	# floor and trunk checks, so the two halves of the comparison are one
	# measurement rather than two written down years apart.
	var base := _base_tune(weapon)
	if not base_override.is_empty():
		var parts := base_override.split(",")
		base = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

	print("preview_carry: sweeping %s over %d carried clips, layer %s"
		% [Loadout.weapon_name(weapon), clips.size(),
			"off" if carry.is_empty() else "on (%s)" % carry])
	print("  each cell: worst lowest end / worst trunk / Idle elevation / "
		+ "Idle off-hand reach")
	for axis in 3:
		if weapon != Loadout.Weapon.SPEAR and axis == 2:
			continue
		var line := ""
		for step in SWEEP_STEPS:
			var tune := base
			var nudge := float(step - (SWEEP_STEPS - 1) / 2) * span
			tune[axis] += nudge
			var worst := INF
			var skin := INF
			for clip: String in clips:
				var row := _clearance(bog, skeleton, player, clip, carry,
					weapon, tune)
				worst = minf(worst, row[0])
				skin = minf(skin, row[2])
			var idle := _clearance(bog, skeleton, player, "Idle", carry,
				weapon, tune)
			line += " %+6.3f/%.2f/%+04.0f/%.2f" % [worst, skin, idle[1], idle[3]]
		var reach := float((SWEEP_STEPS - 1) / 2) * span
		print("  axis %d, %+.0f to %+.0f in %.0fs:%s"
			% [axis, base[axis] - reach, base[axis] + reach, span, line])


## What the sweep is centred on, and what `_prop_transform` means by `tune` for
## this weapon: a grip rotation for the spear and the sword, a carry tilt in
## x and y for the bow. Two shapes because the two weapons whose carry clip was
## drawn around their own prop have nothing to tilt (D-070).
func _base_tune(weapon: int) -> Vector3:
	match weapon:
		Loadout.Weapon.BOW:
			return Vector3(HeldGear.CARRY_TILT.x, HeldGear.CARRY_TILT.y, 0.0)
		Loadout.Weapon.SWORD:
			return HeldGear.SWORD_GRIP_ROTATION
		_:
			return HeldGear.GRIP_ROTATION


# ----------------------------------------------------------- what a pose is ---

## What a candidate carry clip does with the two fists, in the Bog's own frame —
## where they are, how far apart, and which way the line between them points
## (D-070).
##
## Printed rather than looked at, because every question this step had to settle
## about a **borrowed** pose is one of these numbers. How high the gripping fist
## is says whether a shaft pointing forward would have its butt inside the torso;
## how far apart the fists are says whether a two-handed carry is available at
## all; and the bearing and elevation of the line between them is the one shaft
## direction a two-handed pose has no freedom about — `preview_sword`'s own
## equation, asked of an idle instead of a swing.
##
## What it said, and what `Loadout.CARRY_CLIPS` was chosen on:
##
##   clip          right fist            left fist        apart   brng   elev
##   Idle          +0.15,+0.98,-0.30   -0.51,+1.01,-0.10  0.691   -107     +3
##   BowCarry      +0.39,+0.67,+0.03   -0.53,+0.69,+0.02  0.919    -89     +2
##   SwordCarry    +0.01,+0.74,-0.33   -0.14,+0.69,-0.17  0.224   -137    -15
##
## `Idle` is the boxer's guard: the gripping fist is at 0.98 m, beside a head
## that is half a metre of blob, and the fists are 0.69 m apart. `BowCarry` drops
## both arms and puts the right fist **at the right hip**, out at x +0.39, which
## is exactly where a javelin is really carried. `SwordCarry` brings both fists
## together in front at waist height, 0.22 m apart, which is the only one of the
## three that is a two-handed grip at all.
func _poses() -> void:
	var bog := _bare_bog()
	var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := bog.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var right := skeleton.find_bone(HeldGear.HAND_BONE)
	var left := skeleton.find_bone(HeldGear.BOW_HAND_BONE)
	print("preview_carry: what each candidate pose does with the fists")
	print("  %-14s %22s %22s %7s %7s %7s"
		% ["clip", "right fist", "left fist", "apart", "brng", "elev"])
	for clip: String in ["Idle", "BowCarry", "SwordCarry", "CrouchIdle"]:
		if not player.has_animation(clip):
			continue
		var length := player.get_animation(clip).length
		var r := Vector3.ZERO
		var l := Vector3.ZERO
		for i in CARRY_SAMPLES:
			_pose(player, skeleton, clip, 0.0, clip,
				length * float(i) / float(CARRY_SAMPLES))
			var to_body := bog.global_transform * skeleton.global_transform
			r += to_body * skeleton.get_bone_global_pose(right).origin
			l += to_body * skeleton.get_bone_global_pose(left).origin
		r /= float(CARRY_SAMPLES)
		l /= float(CARRY_SAMPLES)
		var line := l - r
		var flat := Vector2(line.x, -line.z).length()
		print("  %-14s %22s %22s %7.3f %+7.0f %+7.0f"
			% [clip, "%+.2f,%+.2f,%+.2f" % [r.x, r.y, r.z],
				"%+.2f,%+.2f,%+.2f" % [l.x, l.y, l.z], line.length(),
				rad_to_deg(atan2(line.x, -line.z)),
				rad_to_deg(atan2(line.y, maxf(flat, 0.0001)))])


## The hilt line, in the gripping fist's own frame, in the **swing** and in the
## **carry** — and how far apart the two are (D-073).
##
## This is `preview_sword._measure`'s equation asked of both clips instead of one.
## A great sword is two-handed, so the direction it has to lie in is not a
## choice: it is the line from the fist that holds it to the fist that joins it,
## `hand^-1 * left.origin`, which `preview_sword` solves against `Swing` and which
## the carry pose answers differently because it is a different pose.
##
## **Under the layer the answer is one number, not twelve.** Every bone of both
## arms is in `BogAnimator.UPPER_BODY_BONES` and they all hang off `mixamorig_Spine1`, so
## the carry clip owns the whole chain and the left fist's position *in the right
## fist's frame* is the carry clip's alone — the locomotion underneath moves both
## fists together and cancels out. That is why a carried grip can be fitted
## exactly while the swing's can only be fitted on average.
func _hilt() -> void:
	var bog := _bare_bog()
	var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := bog.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var swing := _hilt_in_swing(player, skeleton)
	var carry := _hilt_in_carry(player, skeleton, "SwordCarry")
	print("preview_carry: the great sword's hilt line, fist to fist, in the right fist's frame")
	print("  %-22s %24s %8s %9s" % ["fitted against", "mean P(t)", "apart", "scale"])
	for row: Array in [["Swing (D-068, shipped)", swing], ["SwordCarry (carried)", carry]]:
		var p: Vector3 = row[1]
		print("  %-22s %24s %7.3f m %8.4f"
			% [row[0], "%+.4f,%+.4f,%+.4f" % [p.x, p.y, p.z], p.length(),
				p.length() / (HeldGear.SWORD_REAR_HAND - HeldGear.SWORD_FORE_HAND)])
	print("  the two hilt lines are %.1f deg apart"
		% rad_to_deg(swing.normalized().angle_to(carry.normalized())))
	_hilt_spread(bog, skeleton, player, [
		["Swing fit (shipped)", HeldGear.sword_transform()],
		["SwordCarry fit", _sword_grip_from(carry)]])
	_hilt_verdict(swing, carry)


## Whether the shipped grip is still the grip its own clips solve for (D-073).
##
## **This is `derived PASS` for the great sword, and it is the check the last
## four steps of this session kept needing and not having.** D-066 added six
## clips and left the spear's floor stale; D-070 found it. D-071 remirrored the
## strafes and left the spear's flatness stale; D-072 found it, and made the
## flatness a check. Every one of those is the same fault: *a fit against a clip
## set that has since changed*, discovered two steps later by somebody measuring
## something else.
##
## The spear's version compares one constant against a function of another. The
## sword's has to go further, because its three constants are not a function of
## each other — they are a function of **`Swing`**, through the seventeen poses
## `preview_sword -- measure` averages. So this re-runs that solve and compares.
## It costs seventeen poses and no skin scan, which is why it can live in a mode
## the gate already pays for.
##
## Three ways to fail, and they are three different accidents:
##
##   fit       `Swing` or the window `BogAnimator` plays of it has moved, so the
##             constants describe a clip that is no longer there. Re-run
##             `preview_sword -- measure` and paste its three lines.
##   derived   somebody re-aimed `SWORD_GRIP_ROTATION` and left
##             `SWORD_GRIP_OFFSET` at its old value, which is exactly what D-072
##             caught one prop over. Paste `sword_offset()`.
##   carried   the **carry** pose's fists no longer close on this sword's hilt.
##             That one cannot be fixed by pasting anything — see D-073.
func _hilt_verdict(swing: Vector3, carry: Vector3) -> void:
	var solved := _sword_grip_from(swing)
	var scale: float = solved.basis.get_scale().x
	var rotation := solved.basis.orthonormalized().get_euler() * (180.0 / PI)
	var turn := absf(rad_to_deg(Basis.from_euler(rotation * (PI / 180.0))
		.get_rotation_quaternion().angle_to(
			Basis.from_euler(HeldGear.SWORD_GRIP_ROTATION * (PI / 180.0))
				.get_rotation_quaternion())))
	var grew := absf(scale - HeldGear.SWORD_SCALE)
	if turn <= FIT_DEGREES and grew <= FIT_SCALE:
		print("preview_carry: Swing still solves SWORD_SCALE %.4f and a grip "
			% scale + "%.1f deg off the shipped one — fit PASS" % turn)
	else:
		print("preview_carry: fit FAIL — Swing now solves SWORD_SCALE %.4f and "
			% scale + "a grip %.1f deg off SWORD_GRIP_ROTATION. The clip has "
			% turn + "moved under the constants: re-run `preview_sword -- "
			+ "measure` and paste its three lines.")
		_failed += 1

	var derived := HeldGear.sword_offset()
	var drift := derived.distance_to(HeldGear.SWORD_GRIP_OFFSET)
	if drift <= DERIVED_MAX:
		print("preview_carry: SWORD_GRIP_OFFSET is %v, %.4f m off its own "
			% [HeldGear.SWORD_GRIP_OFFSET, drift] + "derivation — derived PASS")
	else:
		print("preview_carry: derived FAIL — SWORD_GRIP_OFFSET is %v and "
			% HeldGear.SWORD_GRIP_OFFSET + "sword_offset() is %v, %.4f m apart"
			% [derived, drift])
		_failed += 1

	# How far past the pommel the joining fist closes, in the pose the sword is
	# *carried* in. `preview_sword.FIT_TOLERANCE` is the yardstick and its header
	# says what it is: the size of the mitten, 0.16 m of `mixamorig_RightHand`-weighted
	# skin, rather than a residual to drive to zero.
	var pommel := HeldGear.sword_direction() \
		* (HeldGear.SWORD_SCALE * HeldGear.SWORD_REAR_HAND) \
		+ HeldGear.sword_offset()
	var miss := pommel.distance_to(carry)
	if miss <= FIT_TOLERANCE:
		print("preview_carry: in SwordCarry the joining fist closes %.3f m past "
			% miss + "the pommel, against %.2f of mitten — carried PASS"
			% FIT_TOLERANCE)
	else:
		print("preview_carry: carried FAIL — in SwordCarry the joining fist "
			+ "closes %.3f m past the pommel, against %.2f of mitten. The carry "
			% [miss, FIT_TOLERANCE] + "pose and the sword's size disagree; see "
			+ "D-073 before changing either, because the size is the reach.")
		_failed += 1

	if _failed == 0:
		print("preview_carry: the great sword's grip is still the one its own "
			+ "clips solve for — hilt PASS")
	else:
		print("preview_carry: hilt FAIL — %d of the three are out" % _failed)


## Rows that are out, so `hilt` can end with one verdict line the gate greps for
## without the three checks above having to hand a count back through two
## returns.
var _failed: int = 0

## How far the re-solved grip may sit from the shipped one before `fit` calls it
## a different grip: a degree of rotation and a thousandth of scale. Tight,
## because nothing is *supposed* to move this — it is not a tolerance on a fit,
## it is a tolerance on arithmetic being re-run on the same clip.
const FIT_DEGREES := 1.0
const FIT_SCALE := 0.001

## How far `SWORD_GRIP_OFFSET` may sit from `sword_offset()`. The spear's own
## 0.0005 m, for the spear's own reason: these are two spellings of one number
## and the gap is rounding in the paste.
const DERIVED_MAX := 0.0005

## How far past the pommel a joining fist may close. `preview_sword`'s own
## `FIT_TOLERANCE`, copied rather than imported for the reason `_bare_bog` is a
## copy: the number means "the size of this rig's mitten" and a tool that
## measured a different prop with a silently shared constant would be worse than
## two tools that disagree loudly.
const FIT_TOLERANCE := 0.22


## Where the blade actually points, in the Bog's own frame, under the carry
## layer — averaged over the carry clip's loop, in `Idle`.
##
## The angle above is the one the *fit* is wrong by; this is the one a **player**
## sees, and they are not the same question. Bearing is degrees round from the
## Bog's forward, positive to its right, of the direction the point sticks out
## in; elevation is degrees above horizontal; "off fists" is how far the blade's
## own axis lies from the line between the two fists, which is the one a
## re-fitted grip can move.
func _hilt_spread(bog: Bog, skeleton: Skeleton3D, player: AnimationPlayer,
		grips: Array) -> void:
	var hand := skeleton.find_bone(HeldGear.HAND_BONE)
	var off_hand := skeleton.find_bone(HeldGear.BOW_HAND_BONE)
	var length := player.get_animation("SwordCarry").length
	print("  %-22s %8s %8s %10s" % ["the point, in Idle", "bearing", "elev",
		"off fists"])
	for row: Array in grips:
		var grip: Transform3D = row[1]
		var point := Vector3.ZERO
		var off := 0.0
		for i in CARRY_SAMPLES:
			_pose(player, skeleton, "Idle", 0.0, "SwordCarry",
				length * float(i) / float(CARRY_SAMPLES))
			var pose := skeleton.get_bone_global_pose(hand)
			var at := bog.global_transform * skeleton.global_transform * pose * grip
			# Guard to point, which is the way the blade sticks out of the fists.
			point += at.origin - at * Vector3(0.0, HeldGear.SWORD_GUARD, 0.0)
			var fists := (pose.basis.orthonormalized().inverse()
				* (skeleton.get_bone_global_pose(off_hand).origin
					- pose.origin)).normalized()
			off += rad_to_deg((grip.basis.orthonormalized() * Vector3.UP)
				.angle_to(fists))
		point /= float(CARRY_SAMPLES)
		var flat := Vector2(point.x, -point.z).length()
		print("  %-22s %+7.0f %+8.0f %9.1f" % [row[0],
			rad_to_deg(atan2(point.x, -point.z)),
			rad_to_deg(atan2(point.y, maxf(flat, 0.0001))),
			off / float(CARRY_SAMPLES)])


## The great sword's whole grip, given the hilt line it has to lie along —
## `preview_sword._measure`'s last three lines as a function, so that the swing's
## fit and the carry's are produced by one piece of arithmetic rather than two.
static func _sword_grip_from(mean: Vector3) -> Transform3D:
	var hilt := mean.normalized()
	var span := HeldGear.SWORD_REAR_HAND - HeldGear.SWORD_FORE_HAND
	var model_scale := mean.length() / span
	var across := Vector3.RIGHT
	var x := (across - hilt * across.dot(hilt)).normalized()
	var basis := Basis(x, hilt, x.cross(hilt))
	var euler := basis.get_euler() * (180.0 / PI)
	return Transform3D(basis.scaled(Vector3.ONE * model_scale),
		HeldGear.sword_offset(euler, model_scale))


## The joining fist in the gripping fist's frame, averaged across the window of
## `Swing` the animator plays — `preview_sword._measure`'s own `mean P(t)`,
## re-derived here off the animator's constants so a window that moves moves both.
func _hilt_in_swing(player: AnimationPlayer, skeleton: Skeleton3D) -> Vector3:
	var right := skeleton.find_bone(HeldGear.HAND_BONE)
	var left := skeleton.find_bone(HeldGear.BOW_HAND_BONE)
	var mean := Vector3.ZERO
	for i in SWING_CHECKS:
		var time := lerpf(BogAnimator.SWING_CLIP_START, BogAnimator.SWING_CLIP_END,
			float(i) / float(SWING_CHECKS - 1))
		_pose(player, skeleton, "SwordSpin", time, "", 0.0)
		var fist := skeleton.get_bone_global_pose(right).affine_inverse()
		mean += fist * skeleton.get_bone_global_pose(left).origin
	return mean / float(SWING_CHECKS)


## The same, under a carry layer — averaged across the carry clip's own loop,
## because the pose breathes even though the locomotion under it cancels.
func _hilt_in_carry(player: AnimationPlayer, skeleton: Skeleton3D,
		carry: String) -> Vector3:
	var right := skeleton.find_bone(HeldGear.HAND_BONE)
	var left := skeleton.find_bone(HeldGear.BOW_HAND_BONE)
	var length := player.get_animation(carry).length
	var mean := Vector3.ZERO
	for i in CARRY_SAMPLES:
		_pose(player, skeleton, "Idle", 0.0, carry,
			length * float(i) / float(CARRY_SAMPLES))
		var fist := skeleton.get_bone_global_pose(right).affine_inverse()
		mean += fist * skeleton.get_bone_global_pose(left).origin
	return mean / float(CARRY_SAMPLES)


## How many samples of the swing the hilt fit averages. `preview_sword.CHECKS`,
## kept the same so the two tools' `mean P(t)` is the same number.
const SWING_CHECKS := 17


# ---------------------------------------------------------------- the solve ---

## How many bearings round the Bog the solve tries, and what elevations.
const SOLVE_BEARINGS := 24
const SOLVE_ELEVATIONS := [0.0, 10.0, 20.0]

## The same for the great sword, which is a different question (D-073). A spear
## is asked to lie flat, so the band that matters is the one just off horizontal;
## a carried sword's own pose already holds the blade at +38, and what is being
## asked of it is where a blade *may* point without going through the Bog or into
## the grass. So the band is the whole upper half, in twenty-degree steps.
const SWORD_ELEVATIONS := [0.0, 20.0, 40.0, 60.0, 80.0]

## Aim the shaft where it is wanted and read the grip back off it, rather than
## nudging three Euler angles until the picture looks right (D-070).
##
## **This is the spear's version of the equation `preview_bow` and
## `preview_sword` solve**, and until the carry layer existed it could not be
## written. A grip is one rigid rotation in the hand's frame; the *direction the
## shaft points in the world* is that rotation composed with the hand's own
## orientation, which before D-070 was a different orientation in every clip —
## so there was no "the" direction to solve for and `preview_grip.tscn` existed
## because looking was the only thing left. With the layer holding the upper body
## in one pose across the whole locomotion plane there is exactly one hand
## orientation, and "lay the shaft flat" becomes an equation:
##
##     d       the direction the shaft is wanted in, in the Bog's own frame —
##             `elevation` degrees above horizontal at `bearing` degrees round
##             from forward toward the Bog's right
##     hand    the gripping hand's basis in that frame, under the carry layer
##     R.Y     hand^-1 * d, because the shaft is the grip's own +Y
##     R.X/Z   any orthonormal pair completing it — a shaft is a cylinder and
##             nothing about it decides the roll
##     offset  `HeldGear.grip_offset(R)`, which slides the butt back down through
##             the palm so the fist stays 55% of the way up the shaft
##
## What the sweep below is for is the *other* half, which no equation answers:
## where round the Bog a flat shaft may point without going through the Bog. So
## every bearing is solved and then **scored against the real skinned trunk**,
## which is D-065's own method and the reason its table is believable.
func _solve(weapon_name: String, carry_override: String = "",
		elevations_override: String = "", bearings_override: String = "") -> void:
	var weapon := Loadout.sanitize(Loadout.from_name(weapon_name))
	# The great sword takes its own band (`SWORD_ELEVATIONS` says why), and any
	# weapon takes a comma-separated one from the command line — which is how
	# D-072 ran its 288 candidates and had to edit a constant to do it.
	var elevations: Array = SOLVE_ELEVATIONS
	if weapon == Loadout.Weapon.SWORD:
		elevations = SWORD_ELEVATIONS
	if not elevations_override.is_empty():
		elevations = []
		for part: String in elevations_override.split(","):
			elevations.append(float(part))
	# And the bearings, the same way, because the 15 deg grid is a scan and the
	# band a decision is finally taken in is narrower than one step of it. The
	# spear's re-pick needed 5 deg between -25 and +25 to find the lowest
	# elevation that clears at a forward bearing.
	var bearings: Array[float] = []
	if bearings_override.is_empty():
		for b in SOLVE_BEARINGS:
			bearings.append(360.0 * float(b) / float(SOLVE_BEARINGS) - 180.0)
	else:
		for part: String in bearings_override.split(","):
			bearings.append(float(part))
	var bog := _bare_bog()
	var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := bog.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_build_skin(bog, skeleton)
	var clips := _carried_clips(player, false)
	var carry := Loadout.carry_clip(weapon)
	if not carry_override.is_empty():
		carry = "" if carry_override == "none" else carry_override

	print("preview_carry: solving %s's grip over %d carried clips, layer %s"
		% [Loadout.weapon_name(weapon), clips.size(),
			"off" if carry.is_empty() else "on (%s)" % carry])
	print("  %5s %5s  %-26s %8s %8s %7s %7s"
		% ["elev", "brng", "GRIP_ROTATION", "floor", "trunk", "Idle", "flattest"]
		+ "  2nd fist")
	for elevation: float in elevations:
		for bearing: float in bearings:
			var grip := _grip_for(bog, skeleton, player, carry, elevation,
				bearing, weapon)
			var worst := INF
			var skin := INF
			var idle := 0.0
			var off_hand := 0.0
			var lowest_elev := 0.0
			for clip: String in clips:
				var row := _clearance(bog, skeleton, player, clip, carry,
					weapon, grip)
				worst = minf(worst, row[0])
				skin = minf(skin, row[2])
				lowest_elev = maxf(lowest_elev, absf(row[1]))
				if clip == "Idle":
					idle = row[1]
					off_hand = row[3]
			var ok := worst >= CARRY_MIN and skin >= SKIN_MIN
			print("  %+5.0f %+5.0f  Vector3(%7.2f,%8.2f,%8.2f) %+7.3f m %7.3f m %+6.0f %+6.0f %6.2f%s"
				% [elevation, bearing, grip.x, grip.y, grip.z, worst, skin,
					idle, lowest_elev, off_hand, "   <= OK" if ok else ""])


## The grip rotation that points the **business end** `elevation` degrees up at
## `bearing` degrees round from the Bog's forward, under the carry layer.
##
## Read at one representative frame — the carry clip's own first key over `Idle`
## — because that is what "under the layer" means: `UPPER_BODY_BONES` takes its
## pose from the carry clip, so the hand's orientation is the carry clip's and
## the plane underneath only moves the hips and the spine it rides on. The scores
## in `_solve` are what check that the remaining variation is small enough; this
## only has to pick a candidate.
##
## **The grip's +Y is not the business end for every prop** (D-073). The spear's
## model runs butt-to-tip, so aiming +Y aims the tip; the great sword's runs
## **point-to-pommel**, so aiming +Y at a bearing would aim the *pommel* there
## and put the blade out the back. Asked the wrong way round, `solve sword` reads
## as a perfectly plausible table in which every row is 180 degrees wrong.
func _grip_for(bog: Bog, skeleton: Skeleton3D, player: AnimationPlayer,
		carry: String, elevation: float, bearing: float,
		weapon: int = Loadout.Weapon.SPEAR) -> Vector3:
	_pose(player, skeleton, "Idle", 0.0, carry, 0.0)
	var hand := skeleton.find_bone(HeldGear.HAND_BONE)
	var to_world := (bog.global_transform * skeleton.global_transform
		* skeleton.get_bone_global_pose(hand)).basis.orthonormalized()
	# The Bog's own frame: -Z is forward for an untouched node, +X its right.
	var e := deg_to_rad(elevation)
	var a := deg_to_rad(bearing)
	var want := Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e))
	if weapon == Loadout.Weapon.SWORD:
		want = -want
	var axis := (to_world.inverse() * want).normalized()
	# Any orthonormal pair completing it. `RIGHT` unless the shaft is already
	# along it, which would make the cross product meaningless.
	var along_right := absf(axis.dot(Vector3.RIGHT)) < 0.9
	var seed := Vector3.RIGHT if along_right else Vector3.FORWARD
	var x := (seed - axis * seed.dot(axis)).normalized()
	return Basis(x, axis, x.cross(axis)).get_euler() * (180.0 / PI)


# ---------------------------------------------------------------- the skin ---

## The bones a carried weapon must not go through.
##
## **The trunk and the head, and deliberately not the arms** — which is D-065's
## own rule, in its own words: *"every head- and torso-weighted vertex"*. It is
## not a simplification. The grip is defined as a point *inside the palm*
## (`GRIP_OFFSET`'s derivation puts the shaft 5 cm off the wrist bone's axis
## because "a hand holds a stick in its palm rather than through its own bones"),
## so the nearest hand vertex to any of these three props is a couple of
## millimetres away **by construction**. Measured against the whole body every
## row of this table reads 0.001-0.042 m and says nothing; measured against the
## body the shaft has to miss, it is the number D-065 tuned the spear on.
##
## The legs are out for a weaker version of the same reason and one stronger one:
## a shaft's butt swings past a thigh in every walk cycle that has ever been
## drawn, and the thing the floor check above already measures is whether the
## same end is in the grass.
const TRUNK_BONES := ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head",
	"mixamorig_HeadTop_End"]

## How much of a vertex has to be weighted to the trunk before it counts as
## trunk. A half, so every vertex belongs to exactly one side of the line and
## the seam where a shoulder becomes an arm is not counted twice.
const TRUNK_SHARE := 0.5


## The Bog's own body, skinned, so that "does the shaft go through the head" is a
## measurement rather than a look at a contact sheet (D-065 scored its grip this
## way and the table in `HeldGear.GRIP_OFFSET` is that score).
##
## Read once. Godot's skinning is `bone_global_pose * bind_pose * v` summed over
## the four influences, which is what `_nearest_skin` below does — the same
## formula the GPU runs, so this is the body a player sees and not an
## approximation of it. Only the trunk survives the read; see `TRUNK_BONES`.
func _build_skin(bog: Bog, skeleton: Skeleton3D) -> void:
	var mesh_node := bog.body_mesh
	if mesh_node == null or mesh_node.mesh == null or mesh_node.skin == null:
		push_warning("preview_carry: no skinned body mesh; skin is not measured")
		return
	var skin := mesh_node.skin
	var trunk := {}
	var fist := {}
	var left := {}
	var head := {}
	for i in skin.get_bind_count():
		_skin_binds.append(skin.get_bind_pose(i))
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(i))
		_skin_bone_of_bind.append(bone)
		if bone >= 0 and skeleton.get_bone_name(bone) in TRUNK_BONES:
			trunk[i] = true
		if bone >= 0 and skeleton.get_bone_name(bone) in FIST_BONES:
			fist[i] = true
		if bone >= 0 and skeleton.get_bone_name(bone) in LEFT_FIST_BONES:
			left[i] = true
		if bone >= 0 and skeleton.get_bone_name(bone) in HEAD_BONES:
			head[i] = true

	var arrays := mesh_node.mesh.surface_get_arrays(0)
	var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	# Four influences per vertex on the old body, eight on `BOG.fbx` (D-099):
	# the stride is the mesh's, not this file's.
	_stride = bones.size() / rest.size()
	for v in rest.size():
		var share := 0.0
		var in_fist := 0.0
		var in_left := 0.0
		var in_head := 0.0
		for j in _stride:
			if trunk.has(bones[v * _stride + j]):
				share += weights[v * _stride + j]
			if fist.has(bones[v * _stride + j]):
				in_fist += weights[v * _stride + j]
			if left.has(bones[v * _stride + j]):
				in_left += weights[v * _stride + j]
			if head.has(bones[v * _stride + j]):
				in_head += weights[v * _stride + j]
		# The same half-share rule and for the same reason: a vertex belongs to
		# one side of the wrist, so the seam is not counted twice.
		if in_fist >= TRUNK_SHARE:
			_fist_rest.append(rest[v])
			for j in _stride:
				_fist_bones.append(bones[v * _stride + j])
				_fist_weights.append(weights[v * _stride + j])
		# The same half-share again, twice, which is what keeps the drinking
		# fist and the head measured by the rule the trunk and the spear
		# hand are measured by rather than by a second one (D-075).
		if in_left >= TRUNK_SHARE:
			_left_rest.append(rest[v])
			for j in _stride:
				_left_bones.append(bones[v * _stride + j])
				_left_weights.append(weights[v * _stride + j])
		if in_head >= TRUNK_SHARE:
			_head_rest.append(rest[v])
			for j in _stride:
				_head_bones.append(bones[v * _stride + j])
				_head_weights.append(weights[v * _stride + j])
		if share < TRUNK_SHARE:
			continue
		_skin_rest.append(rest[v])
		for j in _stride:
			_skin_bones.append(bones[v * _stride + j])
			_skin_weights.append(weights[v * _stride + j])
	print("preview_carry: %d of %d vertices are trunk or head, and %d are the "
		% [_skin_rest.size(), rest.size(), _fist_rest.size()] + "spear hand, "
		+ "%d the drinking hand and %d the head alone"
		% [_left_rest.size(), _head_rest.size()])


## How near the segment `a`..`b` comes to the skinned body, in metres.
##
## Every vertex, at every sample, which is 5,295 points per sample and is the
## reason `measure` is a headless mode rather than something the gate runs on
## every clip in the game. It is also the only honest answer: a Bog's head is a
## 0.5 m blob and the three ellipsoids the first pass of D-065 stood in for it
## with are precisely what under-measured it.
func _nearest_skin(bog: Bog, skeleton: Skeleton3D, a: Vector3, b: Vector3) -> float:
	if _skin_rest.is_empty() or _skin_binds.is_empty():
		return INF
	var bones: Array[Transform3D] = []
	for i in _skin_binds.size():
		var bone := _skin_bone_of_bind[i]
		if bone < 0:
			bones.append(Transform3D.IDENTITY)
		else:
			bones.append(skeleton.get_bone_global_pose(bone) * _skin_binds[i])
	var to_world := bog.global_transform * skeleton.global_transform
	var nearest := INF
	for v in _skin_rest.size():
		var rest := _skin_rest[v]
		var out := Vector3.ZERO
		for j in _stride:
			var w := _skin_weights[v * _stride + j]
			if w <= 0.0:
				continue
			var bind := _skin_bones[v * _stride + j]
			if bind < 0 or bind >= bones.size():
				continue
			out += (bones[bind] * rest) * w
		var p := to_world * out
		nearest = minf(nearest, _point_to_segment(p, a, b))
	return nearest


static func _point_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ----------------------------------------------------------------- shared ---

func _carried_clips(player: AnimationPlayer, everything: bool,
		weapon: int = Loadout.Weapon.SPEAR) -> Array[String]:
	var out: Array[String] = []
	var wanted: Array = BogAnimator.REQUIRED_CLIPS if everything 		else (SWORD_CARRIED if weapon == Loadout.Weapon.SWORD else CARRIED)
	for clip: String in wanted:
		if player.has_animation(clip):
			out.append(clip)
	return out


## A Bog with nothing on it that could move a bone or fall through the floor.
## `preview_sword._bare_bog`'s twin, and deliberately a copy of it rather than a
## shared helper in a fourth file: the list of nodes a measurement tool has to
## take off a Bog is the kind of thing that ought to fail loudly in one tool when
## the scene changes, not quietly in three.
func _bare_bog() -> Bog:
	var bog := BOG.instantiate() as Bog
	add_child(bog)
	bog.set_physics_process(false)
	for spare in ["CameraRig", "Nameplate", "AnimationTree"]:
		var node := bog.get_node_or_null(spare)
		if node != null:
			node.queue_free()
	return bog


# ------------------------------------------------------------- the picture ---

## One weapon, in Idle, Walk and Run, with the layer off on the top row and on
## underneath. Two rows of three, because the argument D-070 makes is a
## comparison and a sheet of only the new pose cannot make it.
func _sheet(weapon_name: String, carry_override: String = "",
		tune_text: String = "") -> void:
	var weapon := Loadout.sanitize(Loadout.from_name(weapon_name))
	var carry := Loadout.carry_clip(weapon)
	if not carry_override.is_empty():
		carry = "" if carry_override == "none" else carry_override
	var tune := Vector3.INF
	if not tune_text.is_empty():
		var parts := tune_text.split(",")
		tune = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	var azimuth := deg_to_rad(VIEW_AZIMUTH)
	var elevation := deg_to_rad(VIEW_ELEVATION)
	var eye := Vector3(sin(azimuth) * cos(elevation), sin(elevation),
		-cos(azimuth) * cos(elevation))
	var row := -Vector3(cos(azimuth), 0.0, sin(azimuth))

	var columns := SHEET_CLIPS.size()
	for i in columns * 2:
		var layered := i >= columns
		var clip: String = SHEET_CLIPS[i % columns]
		var bog := _bare_bog()
		var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
		var player := bog.find_child("AnimationPlayer", true, false) as AnimationPlayer
		# One row of six and not two rows of three, with a gap in the middle.
		# Two rows were tried first and are unreadable at this camera: the back
		# row stands *behind* the front one at an oblique angle, so half of every
		# comparison is occluded by the thing it is being compared with.
		var slot := float(i) + (SHEET_GAP if layered else 0.0)
		bog.position = row * (slot - (float(columns * 2 - 1) + SHEET_GAP) * 0.5) \
			* SHEET_SPREAD
		bog.weapon = weapon
		_show(bog, weapon)
		# The worst frame of the clip rather than a lucky one — the same sample
		# the table reports, asked for its time instead of its height, which is
		# `preview_bow`'s own rule for this picture.
		var at := _worst_moment(bog, skeleton, player, clip,
			carry if layered else "", weapon, tune)
		_pose(player, skeleton, clip, at[0], carry if layered else "", at[1])
		if tune != Vector3.INF and weapon == Loadout.Weapon.SPEAR:
			bog.held_gear.set_grip(HeldGear.grip_offset(tune), tune)

		var stamp := Label3D.new()
		stamp.text = "%s%s" % [clip, "  + carry" if layered else ""]
		stamp.font_size = 56
		stamp.pixel_size = 0.0016
		stamp.position = Vector3(0.0, 2.30, 0.0)
		stamp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bog.add_child(stamp)

	_build_stage(eye)


## Three candidate spear grips, from the front and from the side, over the three
## clips a carried shaft is seen in most.
##
##   Godot --path . --resolution 2400x1200 --script tools/snapshot.gd -- ##       res://tools/preview_carry.tscn out/candidates.png 25 candidates ##       16.35,0,40.11 16.51,0,33.73 16.01,0,27.54
##
## **The picture the numbers cannot take.** `-- solve` scores a bearing on three
## clearances and `-- measure` asserts them, and a grip can pass all three and
## still read as a stick held beside the head rather than a javelin about to be
## thrown — which is what happened to the first re-solve over `SpearCarry`, and
## is why this mode exists. The two questions it is built to answer are the two
## a single camera cannot: **from the front, does the shaft cross the head?**
## and **from the side, is the tip ahead of the head?**
##
## Both in one frame, and the trick is the lift rather than a second row behind
## the first. The camera is orthographic and dead in front, so a band placed
## further away renders exactly on top of the near one (`_sheet`'s own comment
## found this the hard way at an oblique angle); the side band is raised into the
## air instead and yawed a right angle, and `_sheet_centre` keeps both in shot.
## Feet off the floor is a lie this sheet can afford, because every clearance
## that is measured against the floor is measured in `-- measure` and not here.
func _candidates(args: Array) -> void:
	var tunes: Array[Vector3] = []
	for arg: String in args:
		var parts := arg.split(",")
		if parts.size() == 3:
			tunes.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	if tunes.is_empty():
		tunes.append(HeldGear.GRIP_ROTATION)
	var weapon := Loadout.Weapon.SPEAR
	var carry := Loadout.carry_clip(weapon)
	var clips: Array[String] = [carry, "Walk", "Run"]
	var columns := tunes.size() * clips.size()
	_sheet_width = float(columns) * CANDIDATE_SPREAD
	_sheet_centre = CANDIDATE_LIFT * 0.5

	for band in 2:
		for i in columns:
			var tune: Vector3 = tunes[i / clips.size()]
			var clip: String = clips[i % clips.size()]
			var bog := _bare_bog()
			var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
			var player := bog.find_child("AnimationPlayer", true, false) as AnimationPlayer
			bog.position = Vector3(
				(float(i) - float(columns - 1) * 0.5) * CANDIDATE_SPREAD,
				CANDIDATE_LIFT if band == 1 else 0.0, 0.0)
			# The side band is the same Bog turned a right angle, so its own
			# forward runs across the screen and "is the tip ahead of the head"
			# is a question about left and right rather than about depth.
			if band == 1:
				bog.rotate_y(deg_to_rad(90.0))
			bog.weapon = weapon
			_show(bog, weapon)
			var at := _worst_moment(bog, skeleton, player, clip, carry, weapon, tune)
			_pose(player, skeleton, clip, at[0], carry, at[1])
			bog.held_gear.set_grip(HeldGear.grip_offset(tune), tune)

			var stamp := Label3D.new()
			stamp.text = "%s  %s
%.2f, %.2f, %.2f" 				% ["side" if band == 1 else "front", clip, tune.x, tune.y, tune.z]
			stamp.font_size = 40
			stamp.pixel_size = 0.0016
			stamp.position = Vector3(0.0, 2.10, 0.0)
			stamp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			bog.add_child(stamp)

	# Dead in front, and barely above the horizon: a head silhouette is only a
	# silhouette from eye level, and the whole front row is a silhouette test.
	_build_stage(Vector3(0.0, 0.06, -1.0).normalized())


## How far apart the candidate sheet stands its bodies, and how far it lifts the
## side band. A Bog is 1.80 m and a shaft 1.24 m, so 1.9 m of spacing keeps a
## shaft out of its neighbour and clears a raised tip. Tighter than `_sheet`'s
## 1.7 because nine bodies in a 16:9 frame is the whole budget, and a shaft that
## overlaps its neighbour costs less here than a head too small to read.
const CANDIDATE_SPREAD := 1.2
const CANDIDATE_LIFT := 2.2

## The fist, close enough to see whether the shaft is in it (D-074).
##
## **The one judgement on this page that is not a number's to make.** The user
## can see that a spear is riding the back of a hand and `palm` can now say so in
## millimetres, but "does this read as a Bog holding a spear" is settled by
## looking, and a sheet framed on a whole body puts the fist twenty pixels
## across. So: one Bog per palm z asked for, all in the carried `Idle`, framed on
## the hand.
##
## Seen from **behind the Bog's right shoulder**, which is not the sheet's own
## camera and is chosen for the same kind of reason `elevations plan` is. From
## the front the shaft crosses the fist in the screen plane and passing in front
## of the hand looks the same as passing through it; from behind the shoulder the
## palm normal lies across the screen, so the shaft either overlaps the mitten or
## has daylight between it and the mitten, and that is the whole question.
func _fist(zs: Array[float]) -> void:
	if zs.is_empty():
		zs = [HeldGear.GRIP_PALM.z]
	var azimuth := deg_to_rad(FIST_AZIMUTH)
	var elevation := deg_to_rad(FIST_ELEVATION)
	var eye := Vector3(sin(azimuth) * cos(elevation), sin(elevation),
		-cos(azimuth) * cos(elevation))
	var row := -Vector3(cos(azimuth), 0.0, sin(azimuth))
	var carry := Loadout.carry_clip(Loadout.Weapon.SPEAR)
	var centre := Vector3.ZERO

	for i in zs.size():
		var bog := _bare_bog()
		var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
		var player := bog.find_child("AnimationPlayer", true, false) as AnimationPlayer
		bog.position = row * (float(i) - float(zs.size() - 1) * 0.5) * FIST_SPREAD
		bog.weapon = Loadout.Weapon.SPEAR
		_show(bog, Loadout.Weapon.SPEAR)
		_pose(player, skeleton, "Idle", 0.0, carry, 0.0)
		# The grip derived from the palm point being asked about, exactly as
		# `HeldGear` would derive it — the rotation is held, because this picture
		# is about one component of one vector and nothing else.
		var palm := Vector3(HeldGear.GRIP_PALM.x, HeldGear.GRIP_PALM.y, zs[i])
		bog.held_gear.set_grip(palm - HeldGear.shaft_direction()
			* (HeldGear.GRIP_FRACTION * HeldGear.SHAFT_LENGTH),
			HeldGear.GRIP_ROTATION)
		var hand := skeleton.find_bone(HeldGear.HAND_BONE)
		# `Skeleton3D.global_transform` already carries the Bog's own placement,
		# so this is the world hand and not the hand times the Bog twice — which
		# matters here and does not in the tables above, where the Bog is at the
		# origin and the doubling is the identity.
		var at := skeleton.global_transform * skeleton.get_bone_global_pose(hand)
		centre += at * _fist_middle(skeleton, hand)

		var stamp := Label3D.new()
		stamp.text = "palm z %+.3f%s" % [zs[i],
			"  (shipped)" if is_equal_approx(zs[i], HeldGear.GRIP_PALM.z) else ""]
		stamp.font_size = 44
		stamp.pixel_size = 0.0004
		# Hung in the world above the hand rather than parented to the Bog: the
		# Bog carries a scale, and a label placed in its local space lands a
		# metre off. Over the top of whatever is in front of it as well, because
		# at this range the head is between the camera and the hand.
		stamp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		stamp.no_depth_test = true
		add_child(stamp)
		stamp.global_position = at.origin + Vector3(0.0, FIST_FRAME * 0.5, 0.0)
	centre /= float(zs.size())

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	light.light_energy = 1.2
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.14, 0.16, 0.18)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.55)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = float(zs.size() - 1) * FIST_SPREAD + FIST_FRAME
	add_child(camera)
	camera.look_at_from_position(centre + eye * 10.0, centre, Vector3.UP)


## `_fist_centre` without the skin cache, for the picture: the same average, read
## off whatever the skeleton is posed as, built on demand because `fist` is a
## render mode and does not run `_build_skin`.
func _fist_middle(skeleton: Skeleton3D, hand: int) -> Vector3:
	if _fist_rest.is_empty():
		var bog := get_child(0) as Bog
		_build_skin(bog, skeleton)
	return _fist_centre(skeleton, hand, _fist_rest, _fist_bones,
		_fist_weights)


## The elevation table as a picture: one Bog per carried clip, in a row, with
## what its weapon's long axis is doing stamped under it (D-070).
##
## The claim the spear's whole grip rests on is *"within 5 degrees of horizontal
## in every clip"*, and a column of numbers is a poor way to be believed about a
## thing the eye is going to judge anyway. Dead side-on, so an angle off
## horizontal is an angle on the screen and the reader can put a ruler on it —
## which is the opposite of `_sheet`'s oblique camera, and for the opposite
## reason: that sheet is about a pose and this one is about a line.
## `view` is `"plan"` for the same row seen from **above** (D-073), which is a
## different claim and needs a different camera. A spear's grip is judged by
## whether the shaft lies flat, so its picture is side-on and its stamp is an
## elevation. The great sword's complaint was *"coming out of the hands at a 35
## ish degree angle to the characters right"* — an angle round the Bog, not above
## the horizon — and side-on that is the one component you cannot see, because a
## blade swung out to the right leaves the screen plane and only looks short.
## From overhead it is an angle on the screen and a protractor settles it.
func _elevations(weapon_name: String, view: String = "side") -> void:
	var weapon := Loadout.sanitize(Loadout.from_name(weapon_name))
	var plan := view == "plan"
	var carry := Loadout.carry_clip(weapon)
	# The row runs across the frame and the camera stands **in front**, which is
	# forced rather than chosen: the shaft lies across the Bog's body, along its
	# own left-right axis, so a camera on that axis sees it end-on as a dot. Seen
	# from the front the shaft is a line at full length and its angle off
	# horizontal is the angle on the screen, which is the one thing this picture
	# is for. Laid along the same axis at `SHEET_SPREAD` the shafts would nearly
	# touch, so this row is wider.
	var row := Vector3.RIGHT
	var bog0 := _bare_bog()
	var probe := bog0.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clips := _carried_clips(probe, false)
	bog0.queue_free()
	# Three clips from overhead rather than twelve, and it is not a preference:
	# seen from above a Bog is a metre across, so a twelve-wide row is framed on
	# twenty metres and every body in it is too small to put a protractor on. The
	# side-on row gets away with twelve because a 1.24 m shaft lying across the
	# body is most of a column. `SHEET_CLIPS` is the same three the before/after
	# sheet draws, which is the comparison this one is read beside.
	if plan:
		clips = []
		for clip: String in SHEET_CLIPS:
			clips.append(clip)

	for i in clips.size():
		var clip: String = clips[i]
		var bog := _bare_bog()
		var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
		var player := bog.find_child("AnimationPlayer", true, false) as AnimationPlayer
		bog.position = row * (float(i) - float(clips.size() - 1) * 0.5) \
			* (ELEVATION_SPREAD if plan else SHEET_SPREAD)
		bog.weapon = weapon
		_show(bog, weapon)
		var at := _worst_moment(bog, skeleton, player, clip, carry, weapon)
		_pose(player, skeleton, clip, at[0], carry, at[1])
		var measured := _clearance(bog, skeleton, player, clip, carry, weapon)

		var stamp := Label3D.new()
		stamp.text = "%s\n%+.0f deg  %+.2f m" % [clip, measured[1], measured[0]]
		if plan:
			stamp.text = "%s\n%+.0f deg right" % [clip, measured[4]]
		stamp.font_size = 52
		stamp.pixel_size = 0.0016
		stamp.position = Vector3(0.0, 2.30, 0.0)
		stamp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bog.add_child(stamp)

	# Dead side-on and near enough level: the whole point is that a horizontal
	# shaft draws a horizontal line on the screen, and any elevation at all tilts
	# it visibly. Three degrees of lift rather than none, so the floor is a band
	# under the feet instead of an invisible edge-on plane — which is the other
	# number every stamp carries.
	#
	# From overhead the same argument runs one axis over, and the camera's own
	# "up" has to become the Bog's **forward**: looking straight down, `UP` is
	# parallel to the view and `look_at_from_position` has no frame to build. With
	# `FORWARD` as up, the Bog's forward points up the screen, so a blade at +44°
	# draws a line 44° clockwise off vertical and the stamp is the protractor.
	_sheet_columns = clips.size()
	if plan:
		_build_stage(Vector3.UP, Vector3.FORWARD)
		return
	_build_stage(Vector3(0.0, 0.05, -1.0).normalized())


## How many bodies the stage has to frame. The sheet knows its own width from
## `SHEET_CLIPS`; the elevation row does not, so it says.
var _sheet_width: float = 0.0
var _sheet_columns: int = 0
## How far up the frame's centre sits, for the one sheet that has two bands of
## Bogs rather than one row (`_candidates`). The camera is orthographic and dead
## in front, so a second row *behind* the first would render on top of it; the
## second band is lifted into the air instead and this is what keeps both in
## shot.
var _sheet_centre: float = 0.0


## The moment in `clip` at which this weapon hangs lowest, as
## `[clip second, carry-clip second]` — so the sheet shows the frame the table's
## number came from.
func _worst_moment(bog: Bog, skeleton: Skeleton3D, player: AnimationPlayer,
		clip: String, carry: String, weapon: int,
		tune: Vector3 = Vector3.INF) -> Array:
	var hand := skeleton.find_bone(_hand_bone(weapon))
	var length := player.get_animation(clip).length
	var carry_length := 0.0
	if not carry.is_empty():
		carry_length = player.get_animation(carry).length
	var lowest := INF
	var best := [0.0, 0.0]
	for i in samples:
		var time := length * float(i) / float(samples)
		var carry_time := 0.0
		if carry_length > 0.0:
			carry_time = carry_length \
				* float(i % CARRY_SAMPLES) / float(CARRY_SAMPLES)
		_pose(player, skeleton, clip, time, carry, carry_time)
		var grip := bog.global_transform * skeleton.global_transform \
			* skeleton.get_bone_global_pose(hand) * _prop_transform(weapon, tune)
		for end: Vector3 in _prop_ends(weapon):
			var p: Vector3 = grip * end
			if p.y < lowest:
				lowest = p.y
				best = [time, carry_time]
	return best


## Put this weapon in the hand and take the other two out — the same exclusion
## `BogCombat._refresh_hand` enforces, done by hand because there is no combat
## node on a bare Bog.
func _show(bog: Bog, weapon: int) -> void:
	bog.held_gear.set_carried(weapon == Loadout.Weapon.SPEAR)
	bog.held_gear.set_bow(weapon == Loadout.Weapon.BOW)
	bog.held_gear.set_sword(weapon == Loadout.Weapon.SWORD)
	bog.held_gear.set_arrow(false)
	# The bow's carry tilt **on**, because it is what ships (D-070 kept it and
	# says why in `HeldGear.CARRY_TILT`); `set_carry(1.0)` is the value
	# `BogAnimator` holds for a bow nobody is drawing. The sword has no tilt any
	# more and the spear never had one, so those two are whatever their grip says.
	bog.held_gear.set_carry(1.0)


func _build_stage(eye: Vector3, up: Vector3 = Vector3.UP) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	light.light_energy = 1.2
	add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.14, 0.16, 0.18)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.55)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)

	# Framed on the **width** of the row rather than the height of a Bog, which
	# is the one thing this sheet needs that `preview_bow`'s and
	# `preview_sword`'s do not: six bodies plus a gap is ten metres across and a
	# camera sized to a 1.8 m Bog crops four of them off the ends. `KEEP_WIDTH`
	# makes `size` mean the horizontal extent, so the frame follows the layout
	# instead of a number somebody would have to keep in step with it.
	var width := (float(SHEET_CLIPS.size() * 2 - 1) + SHEET_GAP) * SHEET_SPREAD
	if _sheet_columns > 0:
		width = float(_sheet_columns) * ELEVATION_SPREAD
	# And an outright override, for the one sheet whose row is neither the
	# comparison's six-plus-a-gap nor the elevation row's wide slots (D-075).
	if _sheet_width > 0.0:
		width = _sheet_width
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = maxf(FRAME_MIN, width + FRAME_MARGIN)
	add_child(camera)
	var centre := Vector3(0.0, (FRAME_LOW + FRAME_HIGH) * 0.5 + _sheet_centre, 0.0)
	camera.look_at_from_position(centre + eye * 14.0, centre, up)

	# The floor, because every number in the tables above is a height above it
	# and a picture of a weapon in grass needs the grass line in it.
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.30, 0.18)
	floor_mesh.material_override = mat
	add_child(floor_mesh)


# --------------------------------------------------------------- the drink ---

## The bottle's whole fit, printed: the palm point, the two rotations worth
## arguing about, what each does across the window, and the scale (D-075).
##
## `-- solve`'s opposite number for a prop that is not carried. `_solve` sweeps
## 24 bearings by 3 elevations and scores each against the floor and the trunk,
## because a carried weapon may point anywhere round a Bog and the question is
## which of those directions is not occupied by the Bog. A bottle has no such
## freedom: it is held for 2.9 s of one clip whose hand does one thing, so there
## are not 288 candidates, there are **two** — stand the bottle up at the start
## of the drink, or stand it up at the lips — and the whole of the argument is
## which of the two the rest of the clip then does something sensible with.
##
## So this prints both, in full, across the window. It is a table rather than a
## verdict for D-072's reason: the answer is obvious once the two are beside
## each other and is not obvious before, and a tool that printed only the winner
## would be asking to be believed.
func _potion() -> void:
	var bog := _bare_bog()
	var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := bog.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_build_skin(bog, skeleton)
	var hand := skeleton.find_bone(HeldGear.BOW_HAND_BONE)

	# The palm point, which is the measurement and not a choice: the centre of
	# the mitten, in the hand's own frame, in the pose the bottle is held in.
	var centre := Vector3.ZERO
	var spread := 0.0
	var first := Vector3.ZERO
	for i in DRINK_SAMPLES:
		_pose(player, skeleton, "Idle", 0.0, "Drink", _drink_time(i))
		var at := _fist_centre(skeleton, hand, _left_rest, _left_bones,
			_left_weights)
		if i == 0:
			first = at
		spread = maxf(spread, at.distance_to(first))
		centre += at
	centre /= float(DRINK_SAMPLES)
	print("preview_carry: the drinking fist's centre is %v in the hand's own "
		% centre + "frame and moves %.4f m across the whole window; "
		% spread + "POTION_PALM is %v" % HeldGear.POTION_PALM)
	# The spear's point, carried over unmoved, which is the thing D-068's rule
	# would have had this prop do and is why D-075 says it cannot.
	var shared := HeldGear.fist_offset()
	var to_shared := centre - shared
	var along := HeldGear.potion_direction()
	print("  `fist_offset()` is %v, which is %.3f m from that centre (%.3f m "
		% [shared, centre.distance_to(shared),
			(to_shared - along * to_shared.dot(along)).length()]
		+ "off the bottle's axis) against %.3f allowed" % PALM_MAX)

	print("  %-22s %-28s" % ["fitted at", "POTION_GRIP_ROTATION"]
		+ "  the bottle's tilt off horizontal, across the window")
	for spec: Array in [["the window opens", BogAnimator.DRINK_CLIP_START],
			["the lips", _lips_time(player, skeleton)]]:
		var rot := _upright_at(bog, skeleton, player, float(spec[1]))
		var line := ""
		for i in 13:
			_pose(player, skeleton, "Idle", 0.0, "Drink",
				BogAnimator.DRINK_CLIP_START
				+ (BogAnimator.DRINK_CLIP_END - BogAnimator.DRINK_CLIP_START)
				* float(i) / 12.0)
			line += "%+4.0f " % _bottle_tilt(skeleton, hand, rot)
		print("  %-22s Vector3(%7.2f,%8.2f,%8.2f)  %s"
			% [spec[0], rot.x, rot.y, rot.z, line])

	# Which way is **out of the Bog**, in the hand's own frame, at the frame
	# the window opens on: horizontally away from `mixamorig_Spine1`, with the component
	# along the bottle projected out because sliding a prop along its own axis
	# is the grip fraction's business. It is the axis the palm point is fitted
	# along (`HeldGear.POTION_PALM` says what it bought), derived rather than
	# guessed at, because the drinking hand is at a different attitude from the
	# spear hand and "the palm normal" is not the same direction twice.
	#
	# **Printed and not scored**, which is this mode's one honest limitation.
	# The thing five centimetres out of the fist buys is that the bottle is not
	# inside the Bog's stomach, and the measurement that ought to say so —
	# `_nearest_skin` against the trunk — cannot: the drink puts a bottle at a
	# face on purpose, so the minimum over the window is nearly zero at every
	# offset and says nothing about the half of it that happens at the hip.
	# `-- drink fist <scale> <fraction> <out>` renders the comparison instead,
	# and D-075 has the three pictures.
	_pose(player, skeleton, "Idle", 0.0, "Drink", BogAnimator.DRINK_CLIP_START)
	var spine := skeleton.get_bone_global_pose(
		skeleton.find_bone("mixamorig_Spine1")).origin
	var hand_at := skeleton.get_bone_global_pose(hand)
	var out_world := hand_at.origin - spine
	out_world.y = 0.0
	var outward := hand_at.basis.orthonormalized().inverse() \
		* out_world.normalized()
	outward = (outward - along * outward.dot(along)).normalized()
	var out_by := HeldGear.POTION_PALM - centre
	print("  out of the Bog is %v in the hand's own frame, and POTION_PALM is "
		% outward + "%.3f m along it — %.3f m of %.3f allowed"
		% [out_by.dot(outward), (out_by - along * out_by.dot(along)).length(),
		PALM_MAX])

	# The scale, which is the one lever no check on this page can see;
	# `HEAD_BONES` carries the measurement that says why.
	print("  %6s %8s %8s %9s %9s" % ["scale", "tall", "belly", "neck", "lip to face"])
	for model_scale: float in [0.20, 0.24, 0.26, 0.30, 0.34, 0.40, 0.50]:
		var lip := HeldGear.potion_transform(model_scale) \
			* Vector3(0.0, HeldGear.POTION_HEIGHT, 0.0)
		var near := INF
		for i in DRINK_SAMPLES:
			_pose(player, skeleton, "Idle", 0.0, "Drink", _drink_time(i))
			near = minf(near, _nearest_head(skeleton,
				skeleton.global_transform
				* skeleton.get_bone_global_pose(hand) * lip))
		print("  %6.2f %8.3f %8.3f %9.3f %9.3f%s"
			% [model_scale, model_scale * HeldGear.POTION_HEIGHT,
				model_scale * 0.652, model_scale * 0.322, near,
				"   <= shipped" if is_equal_approx(model_scale,
					HeldGear.POTION_SCALE) else ""])

	print("  POTION_GRIP_OFFSET := Vector3(%.4f, %.4f, %.4f)"
		% [HeldGear.potion_offset().x, HeldGear.potion_offset().y,
			HeldGear.potion_offset().z])


## The grip rotation that stands the bottle up in the world at `at` seconds of
## the drink clip.
##
## `_grip_for`'s shape with the sweep taken out of it: read the hand's world
## basis at one moment of the layered pose, ask which hand-local direction is
## world up there, and complete an orthonormal frame round it. The roll is free
## for the reason `HeldGear.POTION_GRIP_ROTATION` gives — the bottle is a
## surface of revolution — so any completion will do and the seed is the same
## one `_grip_for` uses.
func _upright_at(bog: Bog, skeleton: Skeleton3D, player: AnimationPlayer,
		at: float) -> Vector3:
	_pose(player, skeleton, "Idle", 0.0, "Drink", at)
	var to_world := (bog.global_transform * skeleton.global_transform
		* skeleton.get_bone_global_pose(skeleton.find_bone(
			HeldGear.BOW_HAND_BONE))).basis.orthonormalized()
	var axis := (to_world.inverse() * Vector3.UP).normalized()
	var seed := Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < 0.9 \
		else Vector3.FORWARD
	var x := (seed - axis * seed.dot(axis)).normalized()
	return Basis(x, axis, x.cross(axis)).get_euler() * (180.0 / PI)


## Which moment of the window the bottle is at the Bog's mouth — the sample at
## which the drinking hand is highest, which is D-067's own detector and finds
## the same 2.6-3.0 s three other tools do.
func _lips_time(player: AnimationPlayer, skeleton: Skeleton3D) -> float:
	var hand := skeleton.find_bone(HeldGear.BOW_HAND_BONE)
	var best := -INF
	var at := BogAnimator.DRINK_CLIP_START
	for i in DRINK_SAMPLES:
		var t := _drink_time(i)
		_pose(player, skeleton, "Idle", 0.0, "Drink", t)
		var y := (skeleton.global_transform
			* skeleton.get_bone_global_pose(hand)).origin.y
		if y > best:
			best = y
			at = t
	return at


## How far off horizontal the bottle's own axis lies, in the pose the skeleton
## is currently in: +90 is standing up, -90 is pouring straight down.
func _bottle_tilt(skeleton: Skeleton3D, hand: int,
		rotation_degrees: Vector3) -> float:
	var grip := HeldGear.potion_transform(HeldGear.POTION_SCALE, rotation_degrees)
	var world := skeleton.global_transform \
		* skeleton.get_bone_global_pose(hand) * grip
	var base: Vector3 = world * Vector3.ZERO
	var lip: Vector3 = world * Vector3(0.0, HeldGear.POTION_HEIGHT, 0.0)
	return rad_to_deg(asin(clampf((lip - base).normalized().y, -1.0, 1.0)))


## The bottle in the hand, through the drink (D-075).
##
## Two framings, and the brief is that both are needed — which is the pair D-074
## landed on one hand over. `fist` is close on the mitten, because "is the
## bottle in the hand" is a question about twenty centimetres of Bog; `body` is
## the whole Bog, because "does this read as drinking" is a question about all
## of it and about the empty other fist in particular.
##
## **The close one lines the fists up and lets the bodies fall where they
## like.** That is the one liberty this sheet takes and it is worth stating: the
## drinking hand travels 0.6 m across the window, so a row of Bogs planted on
## one floor puts their fists on a diagonal and a frame tight enough to see any
## of them contains one. Each Bog is translated so its own hand lands on the row
## line instead. Nothing about the grip is changed by translating a whole body,
## which is exactly why it is safe to do — what is being judged is a hand-local
## transform. It is three columns rather than six for the same reason it is
## close: at `FIST_SPREAD` six fists are a five-metre frame and each mitten is a
## hundred pixels, and the three that carry the argument are the bottle upright
## at the side, the bottle at the lips, and the bottle upright again.
##
## From the Bog's front-left quarter and **not** from behind the shoulder,
## which is where this parts company with `_fist`; `DRINK_AZIMUTH` carries the
## argument.
##
## **`Combat` is taken off these Bogs and that is not tidiness.** `_tick_hand`
## polls four — five, now — questions every frame and repaints any hand that
## disagrees with its gates, and `is_channelling()` is false on a Bog nobody is
## driving. Left on, it takes the bottle back out of the fist and puts the
## default weapon in it somewhere around the twentieth warmup frame, which is
## before the shutter. Every other picture on this page gets away with leaving
## it: they set `bog.weapon` and then show that weapon, so the poll agrees with
## them. This is the first mode whose hand the poll would disagree with, and it
## is the first one that has to say so.
func _drink(view: String, tune: Vector3 = Vector3.ZERO) -> void:
	var close := view != "body"
	var fractions: Array = DRINK_BODY_FRACTIONS
	if close:
		fractions = DRINK_FIST_FRACTIONS
	var azimuth := deg_to_rad(DRINK_AZIMUTH if close else VIEW_AZIMUTH)
	var elevation := deg_to_rad(FIST_ELEVATION if close else VIEW_ELEVATION)
	var eye := Vector3(sin(azimuth) * cos(elevation), sin(elevation),
		-cos(azimuth) * cos(elevation))
	var row := -Vector3(cos(azimuth), 0.0, sin(azimuth))
	var spread: float = FIST_SPREAD if close else SHEET_SPREAD
	var centre := Vector3.ZERO

	for i in fractions.size():
		var bog := _bare_bog()
		var combat := bog.get_node_or_null("Combat")
		if combat != null:
			combat.queue_free()
		var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
		var player := bog.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var fraction: float = fractions[i]
		var t := BogAnimator.DRINK_CLIP_START + fraction 			* (BogAnimator.DRINK_CLIP_END - BogAnimator.DRINK_CLIP_START)
		# Nothing in the fists but the bottle, which is D-067's "the drink
		# empties both hands" as a picture: `_show` with no weapon is exactly
		# what `_refresh_hand` produces for a channelling Bog.
		_show(bog, -1)
		# `set_potion_grip` is the escape hatch the constants were swept
		# through before they were pasted: `tune` is a scale and a grip
		# fraction, and zero means whatever ships.
		if tune != Vector3.ZERO:
			var dir := HeldGear.potion_direction()
			var spine := skeleton.get_bone_global_pose(
				skeleton.find_bone("mixamorig_Spine1")).origin
			var hand_at := skeleton.get_bone_global_pose(
				skeleton.find_bone(HeldGear.BOW_HAND_BONE))
			var out_world := hand_at.origin - spine
			out_world.y = 0.0
			var outward := hand_at.basis.orthonormalized().inverse() \
				* out_world.normalized()
			outward = (outward - dir * outward.dot(dir)).normalized()
			var palm := HeldGear.POTION_PALM + outward * tune.z
			bog.held_gear.set_potion_grip(tune.x,
				palm - dir * (tune.y * HeldGear.POTION_HEIGHT
					* tune.x), HeldGear.POTION_GRIP_ROTATION)
		bog.held_gear.set_potion(true)
		_pose(player, skeleton, "Idle", 0.0, "Drink", t)
		var slot := row * (float(i) - float(fractions.size() - 1) * 0.5) * spread
		# `Skeleton3D.global_transform` already carries the Bog's own placement,
		# so this is the world hand and not the hand times the Bog twice — the
		# bug D-074 found the first time a mode stood Bogs in a row.
		var hand := (skeleton.global_transform * skeleton.get_bone_global_pose(
			skeleton.find_bone(HeldGear.BOW_HAND_BONE))).origin
		bog.position = slot - (hand if close else Vector3.ZERO)
		hand = slot if close else hand + slot
		centre += hand if close else Vector3(slot.x, 1.1, slot.z)

		var stamp := Label3D.new()
		stamp.text = "%.0f%% of the drink" % (fraction * 100.0)
		stamp.font_size = 44 if close else 56
		stamp.pixel_size = 0.0004 if close else 0.0016
		stamp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		stamp.no_depth_test = close
		if close:
			# Hung in the world rather than parented, because the Bog carries a
			# scale and a label placed in its local space lands a metre off.
			add_child(stamp)
			stamp.global_position = hand + Vector3(0.0, FIST_FRAME * 0.6, 0.0)
		else:
			bog.add_child(stamp)
			stamp.position = Vector3(0.0, 2.30, 0.0)
	centre /= float(fractions.size())

	if not close:
		_sheet_width = float(fractions.size() - 1) * spread
		_build_stage(eye)
		return

	var light := DirectionalLight3D.new()
	# Mirrored with the camera: the key light has to come from the side the
	# bottle is on or the mitten shades the one thing this picture is about.
	light.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	light.light_energy = 1.2
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.14, 0.16, 0.18)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.55)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = float(fractions.size() - 1) * spread + FIST_FRAME
	add_child(camera)
	camera.look_at_from_position(centre + eye * 10.0, centre, Vector3.UP)
