class_name BogAim
extends SkeletonModifier3D
## Turns the Bog's torso so the bow points where the crosshair points (D-066).
##
## This is the one thing `docs/PLAN_COMBAT.md` says the repo genuinely does not
## have, and it exists because of a fact about archers rather than a fault in
## the animation: **an archer stands side-on**. `3_Bow_Suite/StandingDrawArrow`
## is authored with the whole body square to the string and the bow out across
## the chest, so the angle between "where this body faces" and "where this bow
## points" is most of a right angle and every degree of it lives above the
## pelvis. D-065 measured the composed pose at **91° off the Bog's own facing**
## and measured three mask variants that do not move it, for the reason none of
## them could: `align_facing` puts a clip's whole yaw on the **Hips**, `Hips` is
## outside `UPPER_BODY_BONES` on purpose (D-029), and so the one rotation that
## would have carried the difference is the one rotation the layer throws away.
##
## So the angle has to be put back somewhere, and the only place left is the
## spine. That is what this does, and it does the vertical half at the same
## time and for free: a `CharacterBody3D` standing on a floor has no pitch, so
## until now a Bog aiming at a roof aimed a level bow at it.
##
## ## Why a `SkeletonModifier3D` and not a `LookAtModifier3D`
##
## `LookAtModifier3D` answers "turn this bone until its forward axis points at
## that node", and that is the wrong question here twice over.
##
## The first reason is that the quantity this has to drive is not the
## orientation of any one bone. It is the offset between **two** bones — the gap
## between where the composed bow points (the line from the drawing fist to the
## bow fist) and where the crosshair points. A look-at aimed at the spine leaves
## the arms hanging off it at whatever angle the clip put them at, which is the
## 91°: the modifier would report success with the bow still across the chest.
## Pointing it at a target pre-turned by 91° would work, and would be this
## class with a node in the scene standing in for a constant.
##
## The second is that one bone is the wrong number of bones. A Bog is a blob
## with a 0.36 m head and 0.28 m of torso between pelvis and collarbones; 92° of
## yaw at a single joint creases it. Spread over `AIM_BONES` it is thirty
## degrees a joint, which is what a skin cluster is for. `LookAtModifier3D`
## drives one bone, so three of them would be three nodes sharing one number and
## three chances to disagree about it.
##
## What is kept from that family is the thing that actually matters: this runs
## **in the skeleton's own modifier stack**, which is the one place in the frame
## where the animation has finished writing the pose and the skin has not yet
## been computed. Writing bone poses from a sibling node's `_process` is exactly
## the race `SkeletonModifier3D` exists to remove, and `bog.tscn` puts the
## `AnimationTree` *after* the model, so a hand-rolled version would have been
## reading last frame's pose.
##
## ## What it must not do, and cannot
##
## **It does not move where an arrow goes.** `BogCombat._throw_origin()` is
## built from `global_position`, `eye_height()` and `body_yaw`, and the
## direction is `BogCamera.aim_ray()` — three things this class never touches,
## none of them on the skeleton. That is D-025 and D-045 holding: the shot is
## read from the camera at the release and has never come from the body, which
## is what made it safe to move the body at all. `tools/combat_range.tscn -- aim`
## asserts it rather than trusting it, by sweeping the view through its whole
## range with the torso tracking and requiring the release point not to move.
##
## ## One code path for eight Bogs
##
## Everything read here is either local-or-replicated already (`Bog.aim_pitch`
## is `draw_fraction`'s twin) or comes off the animator's own blend weight,
## which is itself driven by the replicated draw. A Bog aiming at the sky is
## aiming at the sky on every screen for the price of one `ON_CHANGE` float.

## The bones the correction is spread over, pelvis-end first, with the share of
## it each one takes.
##
## Three, and weighted toward the top: a human twists mostly in the thoracic
## spine and hardly at all in the lumbar, and the Bog's own proportions say the
## same thing louder — `Spine` sits 0.08 m above the hips and carries the whole
## belly, while `Spine2` sits 0.28 m up under the collarbones and carries only
## the chest. Loading the bottom joint would swing the hips' silhouette; loading
## the top one moves the shoulders, which is where the bow is.
##
## The shares sum to 1 and that is a requirement rather than a tidiness: every
## bone is turned about the **same** skeleton-space axis, so their rotations
## compose by adding their angles, and the chest ends up turned by exactly the
## total. Change one and change another.
const AIM_BONES: Array[String] = ["Spine", "Spine1", "Spine2"]
const AIM_SHARES: Array[float] = [0.25, 0.35, 0.40]

## How far the composed bow points off the Bog's own facing, in degrees, with
## the whole of `AIM_BONES` left alone — so this is the number the correction
## has to cancel and not a number anybody chose.
##
## Measured by `tools/combat_range.tscn -- draw`, which prints it at five charge
## levels every time the gate runs, and it is **stable across the draw**: -91,
## -91, -92, -94, -92 from brace to full. That it barely moves is the point.
## The angle is not a function of how far the string is back — it is the fixed
## offset between the pelvis the locomotion is driving and the shoulders the
## draw clip is driving, and a fixed offset is a thing a constant may be.
##
## Negative because `signed_angle_to` reports the turn that takes the *bow* onto
## the *facing*, which is the direction this correction has to go.
const BOW_OFF_FACING := -92.0

## The pitch the torso is allowed to take, off the camera's own limits rather
## than typed here. `BogCamera` already clamps the view to -69°..+54°, and a
## second clamp would be a place for the two to disagree: a torso that stopped
## tracking at 45° while the crosshair went on to 54° is a bow aimed at
## something other than the thing under the reticle, which is the fault this
## class exists to remove.
const PITCH_MIN := BogCamera.PITCH_MIN
const PITCH_MAX := BogCamera.PITCH_MAX

var _body: Bog
var _animator: BogAnimator
## The bone indices, resolved once. -1 for a rig that does not have one, which
## is a warning at startup and a modifier that does nothing thereafter.
var _bones: PackedInt32Array = PackedInt32Array()


## Hang one of these off `skeleton`, wired to the body and the animator that
## drive it. Called from `BogAnimator._ready`, which is the node that already
## owns what this skeleton is doing.
static func install(skeleton: Skeleton3D, body: Bog, animator: BogAnimator) -> BogAim:
	var aim := BogAim.new()
	aim.name = "Aim"
	aim._body = body
	aim._animator = animator
	skeleton.add_child(aim)
	return aim


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		push_error("BogAim expects to be a child of a Skeleton3D")
		return
	var missing: Array[String] = []
	for bone in AIM_BONES:
		var index := skeleton.find_bone(bone)
		if index < 0:
			missing.append(bone)
		_bones.append(index)
	if not missing.is_empty():
		push_warning("BogAim: rig has no %s; the torso will not aim"
			% ", ".join(missing))


## The turn the torso is currently asked to make, in the skeleton's own space.
##
## Yaw first and pitch second, read right to left: the chest is swung round
## until the bow is on the body's forward, and *then* tipped about the body's
## own lateral axis. The other order would pitch the chest about an axis the
## bow is still across, which raises a shoulder instead of the bow.
##
## The two axes are the skeleton's and not the world's, and they are not the
## same pair. `Model/bog` is turned 180° inside `bog.tscn` (the mesh is authored
## facing +Z), so the body's forward is the skeleton's **+Z** and the body's
## right is the skeleton's **-X**. Up survives the turn unchanged, which is why
## the yaw can be the world-space number `combat_range` measured without being
## converted first.
##
## Static, and takes its two angles rather than reading them, because it is the
## whole of the geometry in this file and nothing in it wants a node: the two
## paragraphs above are the argument, and they are checkable against a single
## expression rather than against a method that also has a skeleton in it.
static func correction(yaw: float, pitch: float) -> Quaternion:
	return Quaternion(Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.UP, yaw))


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _body == null or _animator == null:
		return
	if _bones.is_empty() or _bones.has(-1):
		return
	var weight := _animator.aim_blend()
	# Nothing to do, and not merely nothing visible: below this the whole
	# correction is under a tenth of a degree, and writing three bone poses a
	# frame for every Bog in the match to say so is work for nobody.
	if weight <= 0.001:
		return

	var turn := correction(deg_to_rad(BOW_OFF_FACING),
		clampf(_body.aim_pitch(), PITCH_MIN, PITCH_MAX))
	# The weight scales the whole turn along its own axis, which is what makes
	# a bow coming up read as a torso coming round rather than as a pose
	# cross-fading into another pose.
	turn = Quaternion.IDENTITY.slerp(turn, weight)

	for i in _bones.size():
		var bone := _bones[i]
		var share := Quaternion.IDENTITY.slerp(turn, AIM_SHARES[i])
		# The turn is about a fixed axis in *skeleton* space and has to be
		# applied in each bone's *parent* space, or three bones already turned
		# by their ancestors would each add their share about a different axis
		# and the chest would end up somewhere none of them meant. Conjugating
		# by the parent's global basis is the whole of that conversion, and it
		# is read fresh per bone because the bone above has just moved.
		var parent := skeleton.get_bone_parent(bone)
		var frame := Basis.IDENTITY
		if parent >= 0:
			frame = skeleton.get_bone_global_pose(parent).basis.orthonormalized()
		var local := Quaternion(frame.inverse() * Basis(share) * frame)
		skeleton.set_bone_pose_rotation(bone,
			local * skeleton.get_bone_pose_rotation(bone))
