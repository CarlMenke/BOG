class_name HeldGear
extends Node3D
## Everything a Gub is carrying, pinned to the bones of its two hands.
##
## A Gub always has a weapon visible unless it is on cooldown or disarmed,
## because what is in the hands is the whole read on whether an opponent is
## dangerous right now: seeing an empty pair of them across the clearing is how
## you know it is safe to approach. That makes this cosmetic node
## gameplay-critical, so it is driven straight off the same gates the attacks
## are refused by rather than by any timer of its own.
##
## **It owns the hands, and the rule is one thing per hand** (D-065). It was
## "one thing, in the fist", and a bow broke that: a bow is held in the left and
## its arrow is drawn by the right, which is two things and is not two things in
## one hand. So the rule generalised rather than forking — there are two
## `BoneAttachment3D`s and every carried object hangs off exactly one of them:
##
##   right hand   the spear shaft; a letter card, during a hold (D-035); the
##                Elder's crackle, which is what an Elder has instead of a
##                spear (D-038); the nocked arrow, while the bow is drawn; or
##                the great sword, for the length of a swing (D-068)
##   left hand    the bow
##
## **A great sword is two-handed and still hangs off one attachment** (D-068).
## The rule is one *object* per hand, not one hand per object: the sword is
## gripped by the right fist and the left goes to it in the animation, which
## costs nothing here because the left hand is a bone the clip already moves.
## What the rule does buy is the exclusion — the sword and the bow cannot be out
## together, because `GubCombat._wants_bow` says so in the same place it says
## everything else about that hand, and not because two attachments happened to
## be free.
##
## Nothing can put two objects on one attachment, and **which one is showing is
## still decided in exactly one place** — `GubCombat._refresh_hand`, off the
## same gates the attacks are refused by — because a hand that disagrees with
## the gate is a Gub that looks armed and is not. Two rules in two files is the
## thing that generalisation had to avoid, and the way it avoids it is that this
## file still decides nothing: every `set_*` below does what it is told and asks
## no questions, exactly as `set_letter` has always done.
##
## Attaching to the bone is done in code rather than by adding a
## `BoneAttachment3D` inside `gub.tscn`, because that would mean turning on
## editable children for the imported `.glb` and hand-writing a node into a
## subtree that a re-import can renumber.

const MODEL := preload("res://art/generated/spear.glb")
const BOW_MODEL := preload("res://art/generated/bow.glb")
const ARROW_MODEL := preload("res://art/generated/arrow.glb")
const SWORD_MODEL := preload("res://art/generated/greatsword.glb")

const HAND_BONE := "RightHand"
const BOW_HAND_BONE := "LeftHand"

## Where the shaft sits in the fist.
##
## The spear mesh's origin is at the butt and it runs 1.236 m along its own +Y,
## so the whole grip is two things: which way that +Y points in the hand's frame
## (`GRIP_ROTATION`), and which point of the shaft is in the palm
## (`GRIP_OFFSET`, the butt's position in hand-local metres).
##
## `RightHand`'s local +Y runs up the arm and out through the fingers, +X across
## the palm toward the fingertips (they reach x = +0.22 in this cartoon mitten)
## and +Z is the palm normal. A shaft near local +Y is therefore a shaft along
## the forearm, which is why the rotation below is a small tilt off identity.
##
## **The shaft lies flat, and it lies flat in every clip** (D-070). The user:
## *"for the spear idle, the spear should be horizontal not vertical."*
##
## That reverses D-065's own target, which was a shaft 75-85 deg **up** —
## *"a Gub in a guard stance with a spear held upright reads as armed"* — and it
## reverses it on the strength of the very thing D-065 said made it impossible:
##
##     the hand's world orientation differs by more than 100 deg between a
##     raised guard and a hanging arm, so a grip that stands the shaft up in
##     one lays it over in the other
##
## That sentence is true of a grip fitted against **twelve** hand orientations,
## which is what a rigid attachment on a fist the locomotion throws about is.
## The carry layer removes the premise: `UPPER_BODY_BONES` takes its pose from
## one looping carry clip in every clip a Gub walks around in, so there is one
## hand orientation to fit, and "lay the shaft flat" stops being a compromise and
## becomes an equation with one answer. `tools/preview_carry.tscn -- solve`
## solves it — aim the shaft where it is wanted in the Gub's own frame, read the
## grip back off the hand — and then **scores every bearing against the real
## skinned trunk**, which is D-065's own method and is the half no equation
## answers: where a flat shaft may point without going through the Gub.
##
## **The pose under it is the Gub's own `Idle` and the shaft is cocked to throw**
## (D-072). The user, on D-070's two-handed carry: *"This spear is only thrown so
## 2 hands doesnt make sense. I like the original one because it looks like hes
## holding it up with one hand ready to throw... a horizontial spear in its right
## hand."* `Loadout.CARRY_CLIPS` carries why the pose went back; this constant is
## the half that had to be re-solved when it did, because `Idle`'s right fist is
## up beside the head and `SwordCarry`'s was at the waist.
##
## **Which way a cocked shaft may point is a measurement, and it is not
## symmetric.** A tip that leads reads as ready; a tip lying across the chin
## reads as carrying a pole. So the ask was the bearing nearest straight forward
## that still clears the head, the trunk and the ground — and `-- solve spear
## Idle` was re-run at 5 deg of bearing and four elevations, 288 candidates, each
## scored against the real skinned trunk over all twelve carried clips. What it
## says, at the +10 deg aim that puts `Idle` level, is a single-peaked curve:
##
##   bearing   -90   -85   -80   -75   -70   -65  **-60**  -55   -50   -45   -40   -35
##   trunk    .073  .093  .111  .126  .141  .154  **.165** .158  .142  .126  .108  out
##   floor    .455  .465  .423  .383  .344  .307  **.272** .240  .210  .183  .159  out
##   off level  12    14    15    16    17    21   **25**   28    32    35    38    out
##
## Forward is 0 and positive is to the Gub's right. **Nothing on the right-hand
## side clears inside 70 deg**, and the reason is where the fist is: it sits at
## x +0.15, 0.30 m in front of the chest, so 0.68 m of butt has to go somewhere.
## Aim the tip right and the butt swings back-left through the ribs — 0.001 to
## 0.043 m from the skin across the whole sector. Aim it forward-left and the
## butt trails back past the **right shoulder into open air**, which is the one
## direction out of that fist that is not occupied by the Gub.
##
## **-60 deg is taken, and it is the peak of that curve rather than the nearest
## row to forward.** -40 is twenty degrees more forward and clears the floor by
## 9 mm; a 9 mm margin is exactly what D-066 and D-071 each took away from this
## grip without anybody noticing, and it costs 13 more degrees of swing as well.
## -60 is the furthest from the Gub's own body any bearing gets, at 0.165 m —
## better than the two-handed carry it replaces — while still clearly leading.
## What it delivers over the twelve clips, beside D-070's two-handed carry
## re-measured on the same day and the same clips:
##
##   clip              shaft elevation      lowest end
##   Idle               +0  ->    +1        0.71 -> 0.91
##   Walk               +1  ->    -1        0.71 -> 0.93
##   Run                -1  ->   -25        0.34 -> 0.27
##   CrouchIdle         -5  ->   -22        0.43 -> 0.44
##   CrouchWalk         -5  ->   -22        0.35 -> 0.40
##   StrafeLeft        -14  ->   -18        0.51 -> 0.69
##   StrafeRight       +10  ->    +2        0.49 -> 0.77
##   StrafeWalkLeft     -1  ->    -2        0.75 -> 0.96
##   StrafeWalkRight    +1  ->    -0        0.75 -> 0.97
##   RunBack            -1  ->    -3        0.72 -> 0.93
##   WalkBack           +1  ->    +3        0.84 -> 1.06
##   Drink              -1  ->    +3        0.83 -> 1.05
##
##   worst end over the set     +0.341 m -> +0.272 m
##   nearest trunk               0.146 m ->  0.165 m
##
## `Idle` and `Walk` are within a degree of level, which is the ask answered in
## the two poses the question was asked about, and the shaft is 0.91 m up rather
## than 0.71. What is bought with it is `Run` and the two crouches, which reach
## 22-25 deg: a forward-leading shaft lies nearer the sagittal plane, so pelvis
## pitch shows in it, which is the same trade `Loadout` records `BowCarry` losing
## on at 55. The tip dips as the Gub pitches into a run. That is a spear being
## carried at speed and it is inside `preview_carry.LEVEL_MAX`.
##
## **The left-hand column above is D-070's, re-measured, and it is not what D-070
## wrote down.** That record promised *"within 5 degrees of horizontal in all
## twelve clips"* and it was true the day it shipped; D-071 remirrored the four
## strafes one commit later, nobody re-ran the spear, and `StrafeLeft` reads -14.
## It is the second time this grip has been left behind by a clip change — D-065
## promised a 0.15 m floor over six clips, D-066 added six more, and D-070 found
## the butt 0.012 m off the ground. Both promises were prose. The clearances they
## sat next to were checks and neither of those ever drifted, so the flatness is
## a check now too: `preview_carry.LEVEL_MAX`, in the gate, failing on the commit
## that moves a clip rather than two steps later.
##
## `tools/preview_carry.tscn -- measure` prints the whole table and is in the
## gate; `-- solve spear Idle` is the 288-candidate scan the bearing came from,
## and `-- sweep spear SwordCarry 0 51.77,0,19.68` re-runs D-070's own grip
## through it so the left-hand column is a measurement rather than a copy.
##
## The axes are unchanged and worth restating, because the numbers moved a long
## way: `RightHand`'s local +Y runs up the arm and out through the fingers, +X
## across the palm toward the fingertips and +Z is the palm normal. The old grip
## was a small tilt off identity because the shaft ran along the forearm; this
## one is most of a right angle because it does not.
const GRIP_ROTATION := Vector3(52.31, 0.00, 53.82)

## The point of the palm the shaft passes through, in hand-local metres — the
## first term of `GRIP_OFFSET`'s derivation above, named since D-070 because
## that derivation is now code rather than a comment.
##
## Deliberately *off* the wrist bone's axis: a hand holds a stick in its palm
## rather than through its own bones. `+X` runs across the palm toward the
## fingertips, `+Y` up the arm and out through the fingers, and **`+Z` is the
## palm normal** — which in `Idle`'s raised guard points back in at the Gub's own
## chest, so this third component is the one that costs trunk clearance.
##
## **`z` is -0.01 and was -0.04, which is D-074 and is the whole of it.** The
## user, on D-072's cocked-to-throw carry: *"the spear visually is just outside
## the hand, it doesnt appear to be in the palm... right now it appears as if its
## attached to the back of the hand when in idle."*
##
## They are describing a real 4 cm. The number this vector used to be checked
## against was the `RightHand`-weighted skin **at rest** — x -0.083..0.085,
## z -0.065..0.065 — and a bone's own vertices are the wrist, not the fist: the
## three finger chains carry 918 of the mitten's 1,030 vertices and every one of
## them was outside that span. Measured instead as the whole mitten **in the pose
## the spear is carried in**, the fist's centre sits at hand-local
## `(0.002, 0.062, 0.029)`. The `y` was right to two millimetres. The `z` was
## 0.069 out, on the far side of the hand from the palm.
##
## What that did to the shaft: it passes the fist 0.68 m up its own length, where
## the carved staff is 0.040 m in radius and 0.056 at its widest knots, and the
## mitten's back surface lay only 0.018 m from the shaft's axis. So **three
## centimetres of shaft stood out through the back of the hand** while the palm
## half of the fist held nothing, which is exactly the thing the user could see.
##
## -0.01 is where the shaft's own body comes flush with the back of the hand and
## no further: it is a 3 cm move, it brings the axis from 0.076 m of the fist's
## centre to 0.050 m, and `preview_carry -- measure` checks that distance every
## run now (`palm PASS`, `PALM_MAX`). It is not the centre of the fist — centring
## it would be a 9 cm move and would put the butt through the ribs — it is the
## smallest move that stops the shaft breaking out of the back of the hand.
##
## It is paid for out of the trunk: **0.165 m to 0.142 m**, at about 7.5 mm a
## centimetre, against a `SKIN_MIN` of 0.06. The floor is not paid at all (the
## worst carried end goes +0.272 to +0.281) and neither is the letter card
## (0.117 m to 0.108 m of grass under it). `GRIP_ROTATION` is untouched and was
## never in question: the −60° bearing and the level shaft are the part the user
## says works.
const GRIP_PALM := Vector3(-0.03, 0.06, -0.01)

## Where the butt of the shaft sits in the fist, in hand-local metres.
##
## **Derived, and since D-070 derived by a function rather than by prose.** It is
## exactly `grip_offset(GRIP_ROTATION)`:
##
##     GRIP_PALM - GRIP_FRACTION * SHAFT_LENGTH * shaft_direction
##
## which slides the shaft down through the palm until the fist is 55% of the way
## up it — and that 55% is what keeps the butt clear of the ground when the arm
## hangs. Written only as a constant it was a number that went stale the moment
## anybody touched `GRIP_ROTATION`: D-065's own comment said *"change
## GRIP_ROTATION and recompute this, or the shaft stops passing through the
## hand"*, which is a warning where a function is an answer — and D-070 moved the
## rotation by eighty degrees, precisely the change that warning was about.
##
## It stays a `const` as well, because GDScript cannot call a static function to
## initialise one and half this file's readers want a constant. What closes the
## gap is `tools/preview_carry.tscn -- measure`, which recomputes it from the
## rotation on every run and fails the gate if the two have drifted apart.
const GRIP_OFFSET := Vector3(0.5187, -0.1854, -0.3276)

## The two numbers the offset above was derived from, named so the letter card
## can be placed off the same measurement instead of guessed at again. The mesh
## runs 1.236 m along its own +Y from the butt, and the fist is 55% of the way
## up it.
const SHAFT_LENGTH := 1.236
const GRIP_FRACTION := 0.55

## How far past the fist, along the shaft, the letter card sits.
##
## **Derived rather than chosen**, because the shaft is the one volume around
## this hand that has already been proven clear of the Gub's own skin in every
## clip it is carried through — the table above is that measurement. Putting the
## card on the same line inherits all of it: the card rides where the lower
## shaft rides, which in `Idle` is up beside a head it stays 11 cm off, and the
## whole thing turns with the wrist for free.
##
## 22 cm rather than further up is what keeps it out of the ground. `Walk` and
## `Run` lay the shaft over and point the tip down — see the table — and the
## card's own half-height is subtracted from wherever it lands, so at the top of
## the shaft it would plough the grass in exactly the clips a Gub is most likely
## to be running a hold out in.
##
## **It is measured in the pose a hold actually puts a Gub in, which is not the
## carried one**: a letter disarms (D-035), so `_armed()` answers no, the carry
## layer is off and the arm is back on whatever the locomotion plane is doing.
## That makes this number a hostage to `GRIP_ROTATION` without sharing any of its
## pose — which is why it is a **check** and not a note. `preview_carry
## -- measure` recomputes it every run: the card's lowest centre is 0.327 m in
## `RunBack` and its half-height is half of `Pickup.LETTER_HEIGHT` at
## `CARD_SCALE`, which is 0.210 m, so the bottom of the letter stays 11.7 cm up.
##
## D-035 wrote 0.44 m and 23 cm into this comment and both are gone: the first
## moved when D-070 swung the grip eighty degrees and the second when D-072
## re-aimed it forward. Neither was noticed by a human. The 0.22 itself did not
## have to change either time — the first thing D-072's re-aim broke was the
## *stale* `GRIP_OFFSET` beside it, which `derived FAIL` caught in one run, and
## with the offset right the card cleared on its own.
const CARD_ABOVE_FIST := 0.22

## The card in the hand against the card on the ground. Smaller on purpose: the
## world card is sized to be *found*, legible across the island as the only
## thing in a patch of grass, and at that size in a fist it is a letter wider
## than the Gub holding it. This one only has to be seen on a Gub that is
## already in view.
const CARD_SCALE := 0.70

## The card lights the Gub holding it, and this is the part that actually
## carries.
##
## A card does not read at thirty metres — it was checked, back when it was a
## glyph, with `tools/combat_range.tscn letter` from the touchline, and a gold G
## in a gold Gub's fist is a gold smudge on a gold body whether it is drawn or
## modelled. What reads at that range is that the whole Gub is *lit*. So the card
## borrows the trick the card on the ground already uses for the same reason ("a
## drop nobody can see is a drop nobody collects") and brings its own light,
## which is what turns "somebody over there is holding something" into a thing
## you notice without looking for it.
##
## Dimmer and shorter than the ground card's 2.4 over 6 m: this one is 30 cm
## from a body it must rim rather than flood, and there is at most one per
## player where a late match can have a dozen cards lying about.
const CARD_LIGHT_ENERGY := 1.8
const CARD_LIGHT_RANGE := 4.0


var _attachment: BoneAttachment3D
## The left fist's attachment. A second attachment and not a second *rule*: the
## bow is the only thing that ever hangs off it, so "one thing per hand" is
## still one object per `BoneAttachment3D` (D-065).
var _bow_attachment: BoneAttachment3D
var _model: Node3D
## The bow, and the one mesh inside it that carries the `drawn` blend shape.
## Held rather than found again per frame: `set_draw` runs on every peer's copy
## of every drawing Gub, on every frame of every draw.
var _bow: Node3D
## The grip `set_bow_grip` was last handed, and how much of `CARRY_TILT` is over
## it. Kept because the two are composed rather than set one after the other —
## see `_orient_bow`. A bow that nobody has drawn yet is being carried.
var _bow_model_scale: float = BOW_SCALE
var _bow_grip_rotation: Vector3 = BOW_GRIP_ROTATION
var _carry: float = 1.0
var _bow_string: MeshInstance3D
## The nocked arrow, in the right fist while the bow is drawn.
var _arrow: Node3D
## The Elder's crackle, while the bolt is ready (D-038). On the same attachment
## as the other two for the reason the card is, and built and freed rather than
## toggled for the reason the card is: an Elder is rare, and a `HandCrackle` on
## every Gub in the match redrawing arcs nobody can see would be seven wasted
## meshes out of eight.
var _crackle: HandCrackle
## The letter card, while a hold is running (D-035). Hung off the same
## `BoneAttachment3D` as the spear deliberately: one node owns this hand, so the
## card and the shaft cannot end up in it together and there is no second
## attachment to keep in step with the first.
var _card: Node3D
## The great sword, while a swing is running (D-068). Same attachment again, and
## for the fifth time the same reason: whatever is in this fist is in it because
## `GubCombat._refresh_hand` put it there, and there is nowhere for a second
## opinion to live.
##
## Carried at rest since D-069 rather than only during a swing. That cost a
## carry tilt then and costs nothing now (D-070): the grip the swing is fitted to
## turned out to be a grip a Gub can walk around in perfectly well, once the
## fists it hangs off are in a pose that was drawn holding a great sword.
var _sword: Node3D
## The grip `set_sword_grip` was last handed. Three fields and no fourth for a
## carry weight, because since D-070 the carried sword and the swinging sword are
## the *same* grip: what changes between them is the pose the fists are in, which
## is `GubAnimator`'s business and not this node's.
var _sword_model_scale: float = SWORD_SCALE
var _sword_grip_offset: Vector3 = SWORD_GRIP_OFFSET
var _sword_grip_rotation: Vector3 = SWORD_GRIP_ROTATION


func attach_to(skeleton: Skeleton3D) -> bool:
	if skeleton == null or skeleton.find_bone(HAND_BONE) < 0:
		push_warning("HeldGear: rig has no %s bone" % HAND_BONE)
		return false

	_attachment = BoneAttachment3D.new()
	_attachment.name = "SpearHand"
	_attachment.bone_name = HAND_BONE
	skeleton.add_child(_attachment)

	_model = MODEL.instantiate() as Node3D
	_attachment.add_child(_model)
	set_grip(GRIP_OFFSET, GRIP_ROTATION)

	_arrow = ARROW_MODEL.instantiate() as Node3D
	_attachment.add_child(_arrow)
	set_arrow_grip(ARROW_SCALE, ARROW_GRIP_OFFSET, ARROW_GRIP_ROTATION)
	_arrow.visible = false

	_sword = SWORD_MODEL.instantiate() as Node3D
	_attachment.add_child(_sword)
	set_sword_grip(SWORD_SCALE, SWORD_GRIP_OFFSET, SWORD_GRIP_ROTATION)
	_sword.visible = false

	_attach_bow(skeleton)
	return true


## The left fist, and the bow in it (D-065).
##
## A warning and not a refusal on a rig with no `LeftHand`: a Gub with a spear
## and no bow is still a playable Gub, and the pipeline's own
## `assert_same_character` is what actually guards the bone list.
func _attach_bow(skeleton: Skeleton3D) -> void:
	if skeleton.find_bone(BOW_HAND_BONE) < 0:
		push_warning("HeldGear: rig has no %s bone; no bow" % BOW_HAND_BONE)
		return
	_bow_attachment = BoneAttachment3D.new()
	_bow_attachment.name = "BowHand"
	_bow_attachment.bone_name = BOW_HAND_BONE
	skeleton.add_child(_bow_attachment)

	_bow = BOW_MODEL.instantiate() as Node3D
	_bow_attachment.add_child(_bow)
	set_bow_grip(BOW_SCALE, BOW_GRIP_OFFSET, BOW_GRIP_ROTATION)
	_bow.visible = false

	_bow_string = _bow.find_child(STRING_NODE, true, false) as MeshInstance3D
	if _bow_string == null or _bow_string.mesh == null \
			or _bow_string.mesh.get_blend_shape_count() <= STRING_SHAPE:
		# Loud, because the failure is otherwise silent: a bow whose string never
		# moves still looks like a bow, and the charge stops being visible to the
		# one person it has to be visible to.
		push_warning("HeldGear: %s carries no drawn blend shape; the string will not bend"
			% STRING_NODE)
		_bow_string = null


## Exposed so `tools/preview_grip.tscn` can sweep values without a rebuild;
## the constants above are what that sweep settled on.
func set_grip(offset: Vector3, rotation_degrees: Vector3) -> void:
	if _model == null:
		return
	_model.position = offset
	_model.rotation_degrees = rotation_degrees


## Hidden while the spear is in flight or regrowing. Kept as a visibility toggle
## rather than freeing and rebuilding, so throwing rapidly costs nothing.
func set_carried(carried: bool) -> void:
	if _model != null:
		_model.visible = carried


func is_carried() -> bool:
	return _model != null and _model.visible


## Hold a letter card up in this hand, or take it away again with a `letter` of
## 0. Built and freed rather than kept and toggled, the opposite of the spear
## above, because a hold happens a handful of times in a match where a throw
## happens every few seconds — and the glyph is baked into the mesh, so a card
## that stayed would have to be re-lettered anyway.
##
## **This does not touch the spear.** Deciding which of the two is in the hand
## belongs to `GubCombat._refresh_hand`, which asks the same question the throw
## gate asks; a second opinion here is how the hand and the gate end up
## disagreeing. See D-035.
func set_letter(letter: int) -> void:
	if _card != null:
		_card.queue_free()
		_card = null
	if letter == 0 or _attachment == null:
		return
	_card = Pickup.build_card(letter)
	_attachment.add_child(_card)
	_card.position = card_offset()
	_card.scale = Vector3.ONE * CARD_SCALE

	# Parented to the card rather than to the attachment, so it goes when the
	# card goes and there is no second thing to remember to clean up. Its scale
	# is inherited, which is why the range is divided back out — a light that
	# shrank with the glyph would be the one part of this the player never
	# notices had changed.
	var glow := OmniLight3D.new()
	glow.light_color = Pickup.LETTER_COLOUR
	glow.light_energy = CARD_LIGHT_ENERGY
	glow.omni_range = CARD_LIGHT_RANGE / CARD_SCALE
	_card.add_child(glow)


func has_letter() -> bool:
	return _card != null


## Keep the letter upright in the world and turned the way the Gub is facing.
##
## Only the orientation is taken back off the hand. The *position* is untouched
## and goes on coming from `card_offset()` through the bone, so the card still
## rides the one line around this fist that has been measured clear of the Gub's
## own skin in every clip it is carried through.
##
## The billboard needed none of this, because a billboard has no back. A mesh
## does, and a letter seen from behind is a mirrored letter, so something has to
## decide which way it points. Two obvious answers were rejected. **Aligned to
## the shaft** it inherits the wrist, and `Walk` and `Run` lay that over far
## enough to tip the card 60 degrees forward — a letter lying on its face reads
## as one that has been dropped, not one that is being held. **Spun like the
## card on the ground** it reads as a trophy being shown off, which is the
## opposite of what a hold is: ten seconds of standing in the open with no
## spear. Upright and forward is what the billboard already gave players, minus
## the part that tracked the camera.
##
## `Basis.looking_at` aims **−Z** at what it is handed and these letters front
## on **+Z**, so the target is the facing *negated*: point the back away down
## the facing and the front comes round to it.
func _process(_delta: float) -> void:
	if _card == null:
		return
	var gub := get_parent() as Gub
	if gub == null:
		return
	var upright := Basis.looking_at(-gub.facing(), Vector3.UP)
	_card.global_transform.basis = upright.scaled(Vector3.ONE * CARD_SCALE)


## Arc energy around this fist, or take it away again.
##
## **This does not touch the spear or the card**, exactly as `set_letter` does
## not touch the spear: deciding which of the three is in the hand belongs to
## `GubCombat._refresh_hand`, and a second opinion here is how the hand and the
## gate end up disagreeing.
##
## Positioned at the fist rather than up the shaft where the card goes. The card
## is a thing being *held up* to be seen; this is the hand itself being
## dangerous, and it belongs where the spear's grip is.
func set_charged(charged: bool) -> void:
	if charged == (_crackle != null):
		return
	if not charged:
		_crackle.queue_free()
		_crackle = null
		return
	if _attachment == null:
		return
	_crackle = HandCrackle.new()
	_crackle.name = "Crackle"
	_attachment.add_child(_crackle)
	_crackle.position = fist_offset()


func is_charged() -> bool:
	return _crackle != null


## The palm, in hand-local metres: the point `GRIP_OFFSET` was derived from,
## before the shaft was slid down through it. Written as the same expression
## rather than as a fourth vector, so re-aiming the grip carries the crackle
## with it the way it already carries the card.
##
## Static and public since D-068, because the great sword's fit is solved
## outside this file (`tools/preview_sword.tscn -- measure`) and starts from the
## same point: a hand holds a hilt where it holds a shaft, and a second palm
## measured separately would be a second opinion about where this fist is.
##
## **That sentence has teeth, and D-074 is when it bit.** Moving `GRIP_PALM` for
## the spear moved the great sword and the Elder's crackle with it, because both
## of them read this — three props hanging off one number, which is the point of
## the number. `SWORD_GRIP_OFFSET` had to be re-pasted and `derived FAIL` is what
## said so, on the first run, before anything shipped. Changing this function is
## never a spear change; see `GRIP_PALM` for what it cost and `SWORD_GRIP_OFFSET`
## for what it did to the sword.
static func fist_offset() -> Vector3:
	return GRIP_OFFSET + shaft_direction() * (GRIP_FRACTION * SHAFT_LENGTH)


## Where the card sits in hand-local metres: up the shaft from the butt, past
## the fist, by `CARD_ABOVE_FIST`.
##
## Computed from `GRIP_ROTATION` rather than written down as a third vector, so
## that re-aiming the grip carries the card with it. Get this wrong by hand and
## the card floats beside the Gub instead of in its hand, which is the one thing
## about the hold that has to be unambiguous from a distance.
##
## **Static since D-070, because that inheritance finally cost something.** The
## grip moved by eighty degrees, so the 0.22 m this slides the card along the
## shaft stopped pointing up the forearm and started pointing across the body —
## which moves the card, in a pose (`Idle`'s guard) that a Gub holding a letter
## is back in, because a hold disarms it and the carry layer is off for the whole
## of one. `tools/preview_carry.tscn -- measure` asks this function where the
## card is and checks the bottom of it is out of the grass, which is the number
## D-035 wrote down by hand and nothing re-checked when the grip moved.
static func card_offset() -> Vector3:
	return GRIP_OFFSET + shaft_direction() \
		* (GRIP_FRACTION * SHAFT_LENGTH + CARD_ABOVE_FIST)


## Which way the shaft points out of the fist, in hand-local space: the model's
## own +Y turned by the grip.
static func shaft_direction(rotation_degrees: Vector3 = GRIP_ROTATION) -> Vector3:
	return Basis.from_euler(rotation_degrees * (PI / 180.0)) * Vector3.UP


## Where the butt of the shaft sits for a given grip rotation — `GRIP_OFFSET`'s
## own derivation, as a function, so that sweeping the rotation cannot leave the
## shaft passing somewhere other than through the palm.
static func grip_offset(rotation_degrees: Vector3 = GRIP_ROTATION) -> Vector3:
	return GRIP_PALM - shaft_direction(rotation_degrees) 		* (GRIP_FRACTION * SHAFT_LENGTH)


## Where the spear sits in the fist, as a whole transform — the pair above,
## composed. `sword_transform`'s opposite number, and the reason both exist is
## the same: a tool that sweeps a grip and a game that draws one have to be
## asking the same function.
static func spear_transform(rotation_degrees: Vector3 = GRIP_ROTATION) -> Transform3D:
	return Transform3D(Basis.from_euler(rotation_degrees * (PI / 180.0)),
		grip_offset(rotation_degrees))


## World transform of the spear tip, used as the spawn point for a throw so the
## projectile leaves the hand rather than the middle of the Gub.
func tip_transform() -> Transform3D:
	if _model == null:
		return global_transform
	return _model.global_transform


# -------------------------------------------------------- the great sword ---

## Landmarks on `art/generated/greatsword.glb`, in the model's own units,
## measured off the built file by slicing its 5,295 vertices along Y (D-068).
##
## The mesh runs 0.000 to 1.000 along its own **+Y with the point at zero**, so
## +Y runs tip to pommel and the blade direction is **-Y**. Along it:
##
##   0.000..0.710   blade — 0.13 wide, 0.04 thick, the near-flat 901 triangles
##                  the decimator's own budget note is about
##   0.710..0.832   crossguard — the widest part of the model at 0.21
##   0.832..0.913   grip — the narrow section, radius 0.019
##   0.913..1.000   pommel — radius 0.046
##
## Named here rather than left as numbers in the solver, for the reason
## `STRING_REST_Y` and `NOCK_TRAVEL` are: the tool that fits the grip and the
## game that draws it have to agree about where on this model a fist goes, and
## two copies of that would not.
const SWORD_LENGTH := 1.000
const SWORD_GUARD := 0.832
const SWORD_POMMEL := 0.913

## Where the two fists sit on the hilt, in model units.
##
## The forward hand is just above the crossguard and the rear hand is on the
## pommel, which is how a sword this size is actually held — and, more to the
## point here, it is the **longest** span the hilt offers. That matters because
## the span is the denominator of `SWORD_SCALE`: the Gub's fists are a fixed
## distance apart in the clip, so a shorter span buys a longer sword, and the
## honest answer is the one that puts both fists on hilt rather than the one
## that flatters the size.
const SWORD_FORE_HAND := 0.850
const SWORD_REAR_HAND := 0.980

## How big the sword is, and where it sits in the right fist (D-068).
##
## **Every number here is a measurement of the swing**, the way the bow's three
## are a measurement of the draw — and it is the same construction, because it
## is the same problem: a prop held in one hand whose *other* end has to meet a
## second hand the animation is moving. `tools/preview_sword.tscn -- measure`
## solves it and prints these three lines:
##
##     P(t)   the left fist, in right-hand-local metres, sampled across the
##            window `GubAnimator` plays of `Swing`
##     d      normalise(mean P(t)), the line from the gripping fist to the one
##            that joins it — which is the hilt
##     scale  |mean P(t)| / (SWORD_REAR_HAND - SWORD_FORE_HAND)
##     R·Y    d, because the model's +Y runs from the point to the pommel
##     R·X    the blade's flat, squared up against d — taken from the hand's own
##            "across the palm", because a sword's edge is square to the knuckles
##            and nothing about the two fists decides the roll
##     offset the palm point (`fist_offset`, the same one the crackle uses)
##            minus scale · SWORD_FORE_HAND · d, which puts the model's origin —
##            its **point** — the length of the fore-hilt below the fist
##
## The scale is the interesting half, as it was for the bow. This model is
## 1.000 long with 0.130 of hilt between the two grip points; the Gub's fists
## are further apart than that through the whole swing, so the sword has to be
## scaled up or the left hand closes on empty air a long way from the pommel.
## **The size of this sword is therefore a measurement of the animation**, not a
## number anybody picked — and what it buys is the reach, which is why
## `MatchConfig.sword_reach` is checked against it rather than typed beside it.
##
## Move `SWING_CLIP_START`/`SWING_CLIP_END` in `GubAnimator` and all three go
## stale together. Re-run the tool rather than nudging one of them.
## Re-pasted at D-073, unchanged in everything but the fourth decimal. The tool
## above had been printing `1.2585` and `(0.6117, 0.4203, -0.8164)` for some time
## against the `1.2586` and `(0.6116, 0.4206, -0.8159)` that shipped — 0.6 mm of
## sword, which is nothing, found by a check rather than by a person because
## there was no check and nobody re-reads a paste. `preview_carry -- hilt` is
## that check now, and it is the general form of the fault this session kept
## hitting: **a fit against a clip set that has since changed**. See its header.
##
## **Re-pasted again at D-074, and that time it moved 3 cm**, because the offset
## is `fist_offset()` minus a length down the hilt and `fist_offset()` *is*
## `GRIP_PALM` — one palm for both props, which is D-068's own call above: a hand
## holds a hilt where it holds a shaft. So correcting the palm point for the
## spear corrected it for the sword, `derived FAIL` said so on the first run, and
## the z here went -0.8164 to -0.7864. Neither the scale nor the rotation moved,
## because neither is a function of the palm: the scale is the fists' separation
## over the model's hilt span and the rotation is the line between the fists.
## This constant is the rigid translation that puts the point below the fist, and
## it is the only part of the fit the palm can touch.
##
## What that did to the sword, which is worth having in one place because nobody
## asked for it:
##
##   pommel to the joining fist, carried   0.116 m -> 0.089 m   better
##   lowest the point dips in the swing     -0.437  ->  -0.409   better
##   the point at the release               1.434 m ->  1.412 m  against a 1.430 dial
##   worst pommel miss across the swing     0.150 m ->  0.154 m  against 0.16 allowed
##
## Three of the four improve and the fourth is `preview_sword`'s own `fit`
## residual, which loses 3.6 mm of a 10 mm margin. That residual is the fists
## *separating* through the swing and cannot be translated away — moving the
## grip trades the swing's worst sample against the carry pose's, and D-073's
## `carried` is the half that says the second hand is on the weapon.
const SWORD_SCALE := 1.2585
const SWORD_GRIP_OFFSET := Vector3(0.6117, 0.4203, -0.7864)
const SWORD_GRIP_ROTATION := Vector3(65.102, -180.000, -143.141)


## **There is no carried-sword tilt any more, and that is D-070.**
##
## D-069 put a -62 degree rotation on the swinging grip because 2.11 m of blade
## rigidly attached to a fist that `Run` swings to knee height is 2.11 m of blade
## in the grass — the point reached **0.351 m under the floor** — and it said so
## while describing itself as a stopgap: *"it is a rigid prop on an `Idle`
## authored for empty fists. A Mixamo shoulder-carry is the real answer."*
##
## `7_GreatSword_Suite/GreatSwordIdle.fbx` is that answer and it is in the build
## as `SwordCarry`, layered over the whole locomotion plane (D-070). With it the
## fists are posed **for a great sword** rather than for boxing, so the grip
## `preview_sword -- measure` solved against `Swing` is the grip the idle's own
## hands are already holding, and the worst end over the twelve carried clips
## comes out at **+0.187 m** with no tilt at all.
##
## The tilt is deleted rather than kept on top, and the reason is not tidiness.
## It would still *help* — `preview_carry -- sweep sword` puts the layered worst
## at +0.350 m at the old -62 — but a tilt is a rotation **away from where the
## clip's hands are drawn holding the thing**. On an `Idle` authored for empty
## fists there was nothing to move away from; on a clip authored for this exact
## prop, sixty-two degrees of it is the blade leaving the hands that are gripping
## it. The pose wins, and what it costs is 0.16 m of the margin the tilt bought.
##
## `CARRY_TILT` below is the opposite call, made on the same evidence, and the
## difference is which clip each prop's pose was authored for. See its header.

## Which way the hilt runs out of the fist, in hand-local space: the model's own
## +Y turned by the grip, which is point-to-pommel — so the **blade** is `-Y`
## (D-073). `shaft_direction`'s opposite number, and it exists for the same
## reason: two files ask where this prop points and one of them is a tool.
static func sword_direction(rotation_degrees: Vector3 = SWORD_GRIP_ROTATION) -> Vector3:
	return Basis.from_euler(rotation_degrees * (PI / 180.0)) * Vector3.UP


## Where the model's origin — its **point** — sits for a given grip rotation and
## scale: `SWORD_GRIP_OFFSET`'s own derivation, as a function (D-073).
##
## `grip_offset` for the great sword, and added for the fault that one was added
## for. D-072 re-aimed `GRIP_ROTATION` and left `GRIP_OFFSET` behind, which put
## 0.053 m of letter card in the ground; the same trap is here, one prop over,
## and it had already been sprung — `preview_carry -- sweep sword` swept this
## rotation with the offset held at its constant, so every cell of that table was
## a sword sliding out of the palm rather than turning in it. A sweep that lies
## is worse than no sweep.
##
## The fist holds the hilt at `SWORD_FORE_HAND`, so the point is that far back
## down the hilt line from the palm, scaled: exactly what `preview_sword`'s
## `offset` line computes, named once so the tool and the game cannot disagree.
static func sword_offset(rotation_degrees: Vector3 = SWORD_GRIP_ROTATION,
		model_scale: float = SWORD_SCALE) -> Vector3:
	var down_the_hilt := model_scale * SWORD_FORE_HAND
	return fist_offset() - sword_direction(rotation_degrees) * down_the_hilt


## Where the sword sits in the fist.
##
## **No tilt parameter since D-070**, which is the whole of the block above: the
## carry pose is a clip whose hands are already holding a great sword, so the one
## grip `preview_sword -- measure` solves against `Swing` is the grip for the
## swing *and* for the carry, and there is nothing left for a lever to do.
##
## It stays a whole `Transform3D` rather than a basis — the one place this
## departs from `bow_basis` — because the three tools that fit it hand in a scale
## and an offset as well, and a function that returned only the rotation would
## leave `_orient_sword` composing the other two by hand in a second place.
static func sword_transform(model_scale: float = SWORD_SCALE,
		offset: Vector3 = SWORD_GRIP_OFFSET,
		grip_rotation: Vector3 = SWORD_GRIP_ROTATION) -> Transform3D:
	var grip := Basis.from_euler(grip_rotation * (PI / 180.0))
	return Transform3D(grip.scaled(Vector3.ONE * model_scale), offset)


func _orient_sword() -> void:
	if _sword == null:
		return
	_sword.transform = sword_transform(_sword_model_scale, _sword_grip_offset,
		_sword_grip_rotation)


## Put a great sword in the right fist, or take it away. A visibility toggle for
## the spear's reason: a Gub swings several times a life and rebuilding a prop
## for each of them buys nothing.
##
## **This does not touch the spear, the card or the crackle**, exactly as
## `set_letter` does not touch the spear. Which of the five is in this hand
## belongs to `GubCombat._refresh_hand`, and a second opinion here is how the
## hand and the gate end up disagreeing.
func set_sword(carried: bool) -> void:
	if _sword != null:
		_sword.visible = carried


func has_sword() -> bool:
	return _sword != null and _sword.visible


## The blade, in world space, as [the point, the crossguard] (D-068).
##
## **Read off the bone attachment and not off the Gub's basis**, which is the
## whole reason this function exists. `Swing` turns the body through a full
## revolution inside the skeleton, so at the moment the blade connects the Gub's
## own `body_yaw` is pointing wherever it was when the player clicked and the
## sword is pointing somewhere else entirely. A sweep along `-basis.z` would be
## a sweep at nothing.
##
## `_sword.global_transform` is what a player can actually see, for D-066's
## reason as well: `Skeleton3D.get_bone_global_pose()` does not see a
## `SkeletonModifier3D` — the skeleton writes the modified pose into the skin and
## restores the animation's own behind it — while `BoneAttachment3D` updates off
## `skeleton_updated`, which fires *after* the modifier stack. So this is the one
## reading that includes `GubAim` and is the one the sword is drawn from.
##
## Returns two points and not a point and a direction, because what the hit is
## resolved against is a **segment**: a two-metre blade whose tip is past a
## victim and whose middle is through them has hit them.
func sword_blade() -> Array:
	if _sword == null:
		return [global_position, global_position]
	# No `* SWORD_SCALE` on the guard: `set_sword_grip` puts the scale on the
	# node itself, so it is already in this transform's basis. The bow's own
	# measurements multiply it back in because that grip carries its scale in a
	# hand-built basis instead, which is the kind of difference worth a line.
	var at := _sword.global_transform
	return [at.origin, at * Vector3(0.0, SWORD_GUARD, 0.0)]


## Exposed for `tools/preview_sword.tscn`, which solves these before they are
## pasted into the constants above — the same escape hatch `set_bow_grip` is.
func set_sword_grip(model_scale: float, offset: Vector3,
		rotation_degrees: Vector3) -> void:
	if _sword == null:
		return
	_sword_model_scale = model_scale
	_sword_grip_offset = offset
	_sword_grip_rotation = rotation_degrees
	_orient_sword()


# --------------------------------------------------------------- the bow ---

## Where the bow sits in the left fist, and how big it is (D-065).
##
## **Every number here is derived from the draw clip rather than swept by eye**,
## and that is the one way this grip differs from the spear's above. A shaft in
## a fist only has to miss the Gub's own skin, and `tools/preview_grip.tscn`
## exists because there was no better answer than looking. A bow has a
## **string**, and the string's nocking point has to be where the drawing hand's
## fingers are at *every* charge level — otherwise the one tell this whole
## weapon is built on is a lie, and it is a lie that gets worse the harder
## somebody is pulling.
##
## So the fit is an equation with one answer, solved by
## `tools/preview_bow.tscn -- measure` and pasted here:
##
##     P(c)   the drawing hand, in left-hand-local metres, at charge c, read off
##            the built `Draw` clip across the window `GubAnimator` indexes
##     d      normalise(P(1) - P(0)), the line the fingers actually travel
##     scale  |P(1) - P(0)| / NOCK_TRAVEL
##     R·Y    -d, because the bow's own -Y is the draw direction
##     R·X    up, orthogonalised against R·Y — the limb axis, vertical
##     offset P(0) + scale · STRING_REST_Y · d
##
## The scale is the interesting half of that. A bow is a lever, and this one is
## 0.986 m tip to tip, which draws its nocking point 0.285 m; the Gub's hands
## come further apart than that across this draw, so the model has to be scaled
## or the string stops short of the fingers pulling it. **The size of the bow is
## therefore a measurement of the animation**, not a number anybody picked.
##
## Move the window in `GubAnimator` and all three go stale together. Re-run the
## tool rather than nudging one of them.
##
## **What that size costs, measured** (`tools/preview_bow.tscn -- measure`
## prints this table too, over 24 samples of each clip): how far the lower limb
## tip is above the floor while a Gub is simply carrying the thing.
##
##   Idle        +0.171 m      CrouchIdle  +0.287 m
##   Walk        +0.135 m      CrouchWalk  +0.269 m
##   Run         **-0.158 m**
##
## So `Run` ploughs, by 16 cm, at the bottom of the arm swing. That is the same
## fault the spear's own grip was tuned out of — "both ends now stay at least
## 0.15 m up in every ground clip" — and it is not tunable out here, because
## every lever that would raise the tip moves the **nocking point**: sliding the
## bow up its own limb axis takes the string's V off the fingers, and shrinking
## it takes the draw with it. A rigid attachment cannot hold a 1.71 m prop clear
## of the floor at a run and meet a string constraint at the same time.
##
## Left, and left visible here rather than discovered. The honest fixes are a
## carry pose (a second grip, and a pop between it and the draw), a bone the bow
## hangs off that is not the fist, or the spine aim step 8 owes this weapon
## anyway — and none of them is a constant in this file.
## How far the bow is tipped out of the drawing grip while it is only being
## **carried** — degrees about the grip's own Y and then its Z (D-066).
##
## This is the 0.158 m of `Run` that D-065 left ploughing the ground, and the
## reason it can be fixed here after that record said it could not is that the
## record was answering a different question. Its sentence was *"every lever
## that would raise the tip moves the nocking point"*, and that is true of every
## lever on **the grip** — the one orientation the string's V has to meet the
## drawing fingers in, at every charge level, which `preview_bow -- measure`
## solves as an equation with one answer. A tilt that only exists while the bow
## is **carried**, and is blended away over the same twelfth of a second the
## draw pose comes up in, meets no string at all: at every charge above zero the
## bow is back in the grip that equation solved, unmoved to the millimetre.
##
## Swept rather than chosen. `preview_bow -- measure` walks a grid of both
## angles over all eleven clips a Gub carries a bow around in and reports the
## worst limb tip over the lot; this is the peak of it, and it is a broad one —
## every tilt within 5° of it on either axis clears 0.25 m. What it buys:
##
##     worst limb tip over all eleven carried clips
##     no tilt      **-0.158 m**  (Run, the bow through the grass)
##     this tilt    **+0.284 m**  (Walk)
##
## which is better than the *best* any clip managed before (Idle, +0.171). One
## axis alone cannot do it — tilting about the grip's Z rights `Run` and rolls
## `WalkBack` under instead, bottoming out at -0.021 m — because the axis lives
## in the fist and the fist is at a different attitude in every clip.
##
## **It survives D-070 where the sword's did not, and the difference is which
## clip each pose was authored for.** `3_Bow_Suite/BowIdle.fbx` is a Gub standing
## with a longbow, so the carry layer poses the bow arm properly — but the grip
## the bow hangs in is not a pose, it is the *equation* above, solved against
## `Draw` so the string's V meets the drawing fingers at every charge. The carry
## clip's own hand does not know that equation, and measured, the layer alone
## leaves a limb tip **+0.032 m** off the floor in `Idle` — in the grass by the
## 0.15 m standard, and worse than the tilt it would be replacing. With both, the
## worst over the twelve carried clips is **+0.251 m**.
##
## The sword's tilt is deleted on exactly this test run the other way: its carry
## clip *was* authored around its prop, so its grip and its pose agree and a tilt
## would only pull the blade out of the hands. See `sword_transform`.
const CARRY_TILT := Vector2(47.5, -25.0)

const BOW_SCALE := 1.7383
const BOW_GRIP_OFFSET := Vector3(-0.1927, -0.1376, 0.0989)
const BOW_GRIP_ROTATION := Vector3(10.162, 165.413, 19.573)

## Two facts about `art/generated/bow.glb`, in the model's own units, named here
## so the derivation above can be read without opening the GLB.
##
## The string lies along the model's X at this height, and the `drawn` blend
## shape pulls its nocking point exactly this far along -Y. Both are measured
## off the built file, and both move if the decimator's budget does:
## `tools/bow_string.py` derives the travel from `DRAW_HALF_ANGLE_DEG` and
## whatever tip separation the decimated body turns out to have.
const STRING_REST_Y := 0.0363
const NOCK_TRAVEL := 0.2847

## Where the nocked arrow sits in the right fist, and how long it is.
##
## Derived the same way and off the same two frames. The mesh runs 1.000 m along
## its own X with the head at +X and the nock at -X, and its origin is the
## middle — so the shaft is aimed by `R·X = the line from this fist to the bow
## fist` and then slid half its length forward to put its *nock* in the fingers.
##
## The length is the draw plus an overhang, because an arrow has to still be on
## the rest when the string is at brace: it is the hand separation at full draw
## plus `ARROW_OVERHANG` of head past the riser. Shorter, and the head
## disappears inside the bow on the one frame everybody is looking at.
const ARROW_SCALE := 0.8557
const ARROW_GRIP_OFFSET := Vector3(-0.2024, 0.3853, -0.0069)
const ARROW_GRIP_ROTATION := Vector3(-29.638, 107.416, 91.184)
const ARROW_OVERHANG := 0.20

## The name the string mesh takes in the GLB and the index of its one blend
## shape — `tools/bow_string.py`'s `STRING_NODE` and `SHAPE_NAME`. A rebuild
## that renamed either would leave a bow whose string never moves, which still
## looks like a bow, so a miss is a warning here rather than a silent nothing.
const STRING_NODE := "BowString"
const STRING_SHAPE := 0


## Put a bow in the left fist, or take it away. A visibility toggle for the same
## reason the spear's is: a Gub draws several times a life, and rebuilding a
## prop for each of them buys nothing.
## The bow's orientation in the bow hand, `tilt` degrees out of the drawing
## grip. `tilt` 0 is the grip `preview_bow -- measure` solved and the pose every
## charge level is fitted to; anything else is the carry.
##
## Composed rather than added: two Euler triples do not add, and the carry has
## to be a rotation *about the bow's own limb-normal* whatever the grip is, or
## the tilt would mean something different every time the grip moved.
static func bow_basis(tilt: Vector2, grip_rotation: Vector3 = BOW_GRIP_ROTATION) -> Basis:
	var grip := Basis.from_euler(grip_rotation * (PI / 180.0))
	if tilt.length_squared() < 0.0001:
		return grip
	return grip * Basis(Vector3.UP, deg_to_rad(tilt.x)) \
		* Basis(Vector3.BACK, deg_to_rad(tilt.y))


## How much of `CARRY_TILT` the bow is currently wearing: 1 while it is only
## being carried, 0 while it is being drawn or loosed.
##
## Handed the animator's own aim weight rather than the charge, and the
## difference is the loose. The charge is gone on the frame the string goes,
## and for the length of `Loose` after that the arms are still in an archer's
## pose out of a different node — a grip driven by the charge would tilt the bow
## back to the carry underneath a hand that has not moved yet, on the one frame
## everybody is looking at it.
##
## Idempotent and cheap, because it is called every frame on every Gub in the
## match: an unchanged value writes nothing.
func set_carry(amount: float) -> void:
	var want := clampf(amount, 0.0, 1.0)
	if _bow == null or is_equal_approx(want, _carry):
		return
	_carry = want
	_orient_bow()


func _orient_bow() -> void:
	if _bow == null:
		return
	_bow.basis = bow_basis(CARRY_TILT * _carry, _bow_grip_rotation) \
		.scaled(Vector3.ONE * _bow_model_scale)


func set_bow(carried: bool) -> void:
	if _bow != null:
		_bow.visible = carried


func has_bow() -> bool:
	return _bow != null and _bow.visible


## How far this bow is drawn, 0 at brace and 1 at full.
##
## One float, straight onto the string's one blend shape — and it is the *same*
## float that scrubs the draw pose (`GubAnimator.draw_time`) and picks the
## arrow's damage and speed (`GubCombat`). That is the whole reason the string
## is a morph and not a bone chain: a second thing that had to be told how drawn
## the bow is would be a second thing that could be told something else.
##
## The morph is exact rather than an approximation. A drawn string is two
## straight segments meeting at the nocking point; every vertex is displaced by
## `pull · DRAW · tent(t)`, and a blend weight scales every delta by itself,
## which scales the tent by itself, which is exactly the V of a string drawn
## that far. See `tools/bow_string.py`.
func set_draw(fraction: float) -> void:
	if _bow_string == null:
		return
	_bow_string.set_blend_shape_value(STRING_SHAPE, clampf(fraction, 0.0, 1.0))


## Nock an arrow in the right fist, or take it away.
##
## On the same attachment as the shaft, the card and the crackle, which is what
## makes "one thing per hand" a fact about the scene tree rather than a rule
## somebody has to remember: `GubCombat._refresh_hand` is the only caller and it
## sets all four of them every time it runs.
func set_arrow(nocked: bool) -> void:
	if _arrow != null:
		_arrow.visible = nocked


func has_arrow() -> bool:
	return _arrow != null and _arrow.visible


## Exposed for `tools/preview_bow.tscn`, which sweeps these before they are
## pasted into the constants above — the same escape hatch `set_grip` is.
func set_bow_grip(model_scale: float, offset: Vector3, rotation_degrees: Vector3) -> void:
	if _bow == null:
		return
	_bow_model_scale = model_scale
	_bow_grip_rotation = rotation_degrees
	_bow.position = offset
	_orient_bow()


func set_arrow_grip(model_scale: float, offset: Vector3, rotation_degrees: Vector3) -> void:
	if _arrow == null:
		return
	_arrow.scale = Vector3.ONE * model_scale
	_arrow.position = offset
	_arrow.rotation_degrees = rotation_degrees
