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
## **A near-vertical carry, decided in `Idle`.** The Gub's `Idle` is a hunched
## boxer's guard: the right fist is up beside a head that is thrust forward, and
## the head is 0.5 m of blob 0.25 m thick. The first pass aimed the tip
## forward-and-up (a 21 deg tilt off the forearm) and scored it against three
## small ellipsoids standing in for the body — which under-measured the Gub
## badly, and the shipped result ran the shaft in under the chin and out above
## the crown. So this pass scored candidates against the **real skinned mesh**:
## every head- and torso-weighted vertex, skinned at 27 poses spread over the
## six clips the spear is carried in, with the shaft's distance to the nearest
## one as the constraint.
## The target — chosen because `Idle` is the pose read across a clearing, and a
## Gub in a guard stance with a spear held upright reads as armed — is a shaft
## 75-85 deg above horizontal, leaning slightly forward and outward to the
## Gub's own right, away from the head. What the numbers below deliver:
##
##   clip        shaft elevation      lowest end   nearest skin
##   Idle        +81 to +86 deg         0.33 m        0.11 m
##   Walk        -42 to -14 deg         0.23 m        0.15 m
##   Run         -59 to -43 deg         0.15 m        0.26 m
##   CrouchWalk  +70 to +75 deg         0.59 m        0.19 m
##   CrouchIdle  +72 deg                0.59 m        0.19 m
##   Throw       -10 to +59 deg         0.43 m        0.06 m
##
## The mean `Idle` carry is 86 deg up and 53 deg round from forward toward the
## Gub's right: a near-vertical shaft leaning as much outward as forward.
## Nothing touches the skin anywhere; the tightest is the throw follow-through
## at 6 cm.
##
## `Walk` and `Run` still point the tip *down*, and that is not fixable with a
## rigid attachment: the hand's world orientation differs by more than 100 deg
## between a raised guard and a hanging arm, so a grip that stands the shaft up
## in one lays it over in the other. What was fixable is the tip ploughing the
## ground — it used to reach +0.01 m in `Walk` — and both ends now stay at least
## 0.15 m up in every ground clip.
##
## **`GRIP_OFFSET` is derived, not free.** It is
##
##     (-0.03, 0.06, -0.04) - 0.55 * 1.236 * shaft_direction
##
## where the first term is the point of the palm the shaft passes through and
## the second puts the fist 55% of the way up the shaft (which is what lifts the
## butt clear of the ground when the arm hangs in `Walk`). That palm point is
## deliberately *off* the wrist bone's axis, because a hand holds a stick in its
## palm rather than through its own bones: the `RightHand`-weighted skin spans
## x -0.083..0.085, z -0.065..0.065, y -0.025..0.103 in hand-local rest space,
## so 5 cm off the axis and 6 cm up toward the knuckles is inside the fist with
## room to spare — and moving the shaft those 5 cm is what takes it from 6 cm
## off the face to 11 cm. Change `GRIP_ROTATION` and recompute this, or the
## shaft stops passing through the hand.
##
## Swept with `tools/preview_grip.tscn` (which takes both vectors on the command
## line) at 2400x700 in all five clips, plus the `Throw` window 1.40-1.75.
const GRIP_OFFSET := Vector3(-0.206, -0.582, 0.097)
const GRIP_ROTATION := Vector3(-12.0, 0.0, -15.0)

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
## to be running a hold out in. Measured with a Gub holding W through a full run
## cycle in `tools/combat_range.tscn letter`: the card's lowest centre is 0.44 m
## and its half-height is half of `Pickup.LETTER_HEIGHT` at `CARD_SCALE`, which
## is 0.21 m, so the bottom of the letter stays 23 cm up.
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
var _sword: Node3D


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
	_card.position = _card_offset()
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
## and goes on coming from `_card_offset()` through the bone, so the card still
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
static func fist_offset() -> Vector3:
	var shaft := Basis.from_euler(GRIP_ROTATION * (PI / 180.0)) * Vector3.UP
	return GRIP_OFFSET + shaft * (GRIP_FRACTION * SHAFT_LENGTH)


## Where the card sits in hand-local metres: up the shaft from the butt, past
## the fist, by `CARD_ABOVE_FIST`.
##
## Computed from `GRIP_ROTATION` rather than written down as a third vector, so
## that re-aiming the grip carries the card with it. Get this wrong by hand and
## the card floats beside the Gub instead of in its hand, which is the one thing
## about the hold that has to be unambiguous from a distance.
func _card_offset() -> Vector3:
	var shaft := Basis.from_euler(GRIP_ROTATION * (PI / 180.0)) * Vector3.UP
	return GRIP_OFFSET + shaft * (GRIP_FRACTION * SHAFT_LENGTH + CARD_ABOVE_FIST)


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
const SWORD_SCALE := 1.2586
const SWORD_GRIP_OFFSET := Vector3(0.6116, 0.4206, -0.8159)
const SWORD_GRIP_ROTATION := Vector3(65.102, -180.000, -143.141)


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
	_sword.scale = Vector3.ONE * model_scale
	_sword.position = offset
	_sword.rotation_degrees = rotation_degrees


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
