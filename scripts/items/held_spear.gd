class_name HeldSpear
extends Node3D
## The spear a Gub is carrying, pinned to the bone of its right hand.
##
## A Gub always has one visible unless it is in the air or on cooldown, because
## the spear is the whole read on whether an opponent is dangerous right now:
## seeing an empty hand across the clearing is how you know it is safe to
## approach. That makes this cosmetic node gameplay-critical, so it is driven
## straight off the same cooldown the throw checks rather than by its own timer.
##
## It owns the *hand*, not only the spear. Three things can be in it and never
## more than one: the shaft; a letter card, during a hold (D-035); and the
## Elder's crackle, which is what an Elder has instead of a spear (D-038). All
## three hang off the same `BoneAttachment3D`, so nothing can put two of them
## there, and which one is showing is decided in exactly one place —
## `GubCombat._refresh_hand`, off the same gates the throw is refused by —
## because a hand that disagrees with the gate is a Gub that looks armed and is
## not.
##
## Attaching to the bone is done in code rather than by adding a
## `BoneAttachment3D` inside `gub.tscn`, because that would mean turning on
## editable children for the imported `.glb` and hand-writing a node into a
## subtree that a re-import can renumber.

const MODEL := preload("res://art/generated/spear.glb")

const HAND_BONE := "RightHand"

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
var _model: Node3D
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


func attach_to(skeleton: Skeleton3D) -> bool:
	if skeleton == null or skeleton.find_bone(HAND_BONE) < 0:
		push_warning("HeldSpear: rig has no %s bone" % HAND_BONE)
		return false

	_attachment = BoneAttachment3D.new()
	_attachment.name = "SpearHand"
	_attachment.bone_name = HAND_BONE
	skeleton.add_child(_attachment)

	_model = MODEL.instantiate() as Node3D
	_attachment.add_child(_model)
	set_grip(GRIP_OFFSET, GRIP_ROTATION)
	return true


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
	_crackle.position = _fist_offset()


func is_charged() -> bool:
	return _crackle != null


## The palm, in hand-local metres: the point `GRIP_OFFSET` was derived from,
## before the shaft was slid down through it. Written as the same expression
## rather than as a fourth vector, so re-aiming the grip carries the crackle
## with it the way it already carries the card.
func _fist_offset() -> Vector3:
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
