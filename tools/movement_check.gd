extends Node3D
## The feel round's four movement claims and the bow's fifth, measured on a real
## Bog. Development tool, not shipped.
##
##   Godot --headless --fixed-fps 60 --path . tools/movement_check.tscn
##
## **Why this is not in `tools/playthrough.gd`.** The playthrough is a walk
## across the joins between whole scenes, and it runs seven times in the gate,
## once per map. Every one of these claims is about a body on a flat floor
## over a known number of physics ticks — a slide has a friction and a cooldown,
## a landing has to happen on a tick nobody has to guess at, and a full draw
## takes a real second of charge — so hanging them off a match would make six
## runs slower and every one of them dependent on whatever the local Bog
## happened to be standing on. `tools/combat_range.gd` is where a measurement
## like this would otherwise live (`bhop` is its sibling), and that file belongs
## to another group this round.
##
## Nothing here is faked that the game does not already fake for itself: the
## session is `Net.start_offline()` (D-011), the floor is a box, and the two
## Bogs are a real one and a real remote one. The input is written onto the body
## the way `tools/combat_range.gd` writes it — `reads_local_input` off, the
## three fields `_read_input` would have set — because a headless harness has no
## keyboard, and everything downstream of those three fields is the shipping
## code.
##
## The seven verdicts:
##
##   draw        a full draw walks at WALK_SPEED * DRAW_SPEED_SCALE
##   air_draw    a full draw carried into a jump keeps pointing where the body
##               points, on the way up, at the top and through the landing
##   slide_jump  crouch without sprint slides, and a jump out of it leaves at
##               1.2x the slide along the slide's own direction, with 1.12x lift
##   landing     a run-speed landing with crouch held is sliding on the tick it
##               touches down, and never plays Land or LandHard
##   jump_chain  four hops taken the tick after each landing: the first two are
##               full, the third and fourth come up short, and a rest on the
##               ground gives the whole jump back
##   jump_hold   a tapped jump reaches 1.69 m and a held one about 2.20 m, and
##               a hold that starts after the rise is over is worth nothing
##   remote      the slide jump's serial reaches a Bog this machine does not
##               own, through the replication config that ships in bog.tscn,
##               and its animator picks the slide jump's leap

## A floor and nothing else. Big enough that a minute of running in one
## direction stays on it.
const FLOOR := Vector2(400.0, 400.0)
const SPAWN := Vector3(0.0, 0.2, 0.0)
const REMOTE_SPAWN := Vector3(60.0, 0.2, 0.0)

## Peer ids. `ui_range` owns the 700s, `combat_range` the 900s, `playthrough`
## the 500s; the local Bog here has to be 1, because that is the id an offline
## session hands this machine, and the remote one only has to be anything else.
const LOCAL_PEER := 1
const REMOTE_PEER := 2

## Ticks of run-up before a leg gives up waiting for the Bog to reach its speed.
const RUNUP_TICKS := 240
## Ticks between legs, with no input at all: `SLIDE_COOLDOWN` is 0.9 s and every
## tick here is a sixtieth of a second of simulation, so this is comfortably
## more than one cooldown.
const REST_TICKS := 90
## How long the draw may take to reach full. It is a **wall-clock** charge
## (`MatchConfig.bow_draw_time`, 1 s) and these are physics ticks, which at
## `--fixed-fps 60` run as fast as the machine can manage — so this is a hang
## guard and not a measurement.
const DRAW_TICKS := 40000
## Ticks the touchdown is watched for, which has to outlast the longest landing
## one-shot: `Land` is 1.1 s and `LandHard` 1.6 s, and both play whole.
const LAND_TICKS := 120
## Ticks the speed is averaged over, after the body has had time to reach it.
const SETTLE_TICKS := 90
const SAMPLE_TICKS := 30
## How close a measured speed has to be to the number it is meant to be, in m/s.
const SPEED_TOLERANCE := 0.05
## Ticks a jump is watched for, up and down again: a full one is 0.375 s of rise
## and rather less of fall, and this is comfortably over a second.
const HOP_TICKS := 90
## Ticks of standing still that count as a rest, which has to clear
## `Bog.JUMP_CHAIN_RESET` (1.5 s) with room for the landing tick.
const CHAIN_REST_TICKS := 120
## How close a measured apex has to be to the height it is meant to reach, in
## metres. The step this case is looking for is 15% of 1.76 m.
const HEIGHT_TOLERANCE := 0.03

var _bog: Bog
var _remote: Bog
var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_build_floor()
	# An offline session and **no** registered arena: `register_arena` starts a
	# warmup and spawns the session's own Bog, and this file wants the two Bogs
	# it builds itself and nothing else walking about on the floor it is
	# measuring against.
	Net.start_offline()
	await get_tree().physics_frame

	_bog = _spawn(LOCAL_PEER, SPAWN)
	_remote = _spawn(REMOTE_PEER, REMOTE_SPAWN)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if _bog.is_local() and not _remote.is_local():
		_ok("the local Bog is local and the remote one is not", true)
	else:
		_ok("the local Bog is local and the remote one is not", false)

	await _check_draw()
	await _check_air_draw()
	await _check_slide_jump()
	await _check_landing()
	await _check_jump_chain()
	await _check_jump_hold()
	await _check_remote()

	print("movement_check: %d checks, %d failures" % [_checks, _failures])
	print("movement_check: %s" % ("PASS" if _failures == 0 else "FAIL"))
	get_tree().quit(1 if _failures > 0 else 0)


# ------------------------------------------------------------------- world ---

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(FLOOR.x, 1.0, FLOOR.y)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	add_child(body)


## A Bog owned by `peer`, dressed the way `MatchState._create_bog` dresses one:
## ownership before the tree, and `Combat` held back for the host (D-004). The
## camera rig is disabled because there is nobody looking through it and a rig
## easing after a body it is not drawing is only noise.
func _spawn(peer: int, at: Vector3) -> Bog:
	var bog := MatchState.BOG_SCENE.instantiate() as Bog
	bog.name = "Bog_%d" % peer
	bog.peer_id = peer
	bog.display_name = "Bog %d" % peer
	bog.reads_local_input = false
	bog.set_multiplayer_authority(peer)
	add_child(bog)
	var combat := bog.get_node_or_null("Combat")
	if combat != null:
		combat.set_multiplayer_authority(LOCAL_PEER, false)
	var rig := bog.get_node_or_null("CameraRig")
	if rig != null:
		rig.process_mode = Node.PROCESS_MODE_DISABLED
	bog.global_position = at
	bog.set_view_basis(Basis.IDENTITY)
	MatchState.bogs[peer] = bog
	return bog


func _animator(bog: Bog) -> BogAnimator:
	return bog.get_node_or_null("AnimationTree") as BogAnimator


## The three fields `Bog._read_input` writes, written from here instead.
func _drive(forward: float, sprint: bool, crouch: bool) -> void:
	_bog.input_direction = Vector2(0.0, forward)
	_bog.wants_sprint = sprint
	_bog.wants_crouch = crouch


func _speed(bog: Bog) -> float:
	return Vector2(bog.velocity.x, bog.velocity.z).length()


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


## Put the Bog back on the spawn facing -Z, with nothing held down, and let the
## slide cooldown and the landing grace run out.
func _reset() -> void:
	_drive(0.0, false, false)
	_bog.wants_jump_hold = false
	_bog.revive_at(Transform3D(Basis.IDENTITY, SPAWN))
	_bog.set_view_basis(Basis.IDENTITY)
	await _ticks(REST_TICKS)


## Run forward until the body is at `RUN_SPEED`, and say whether it got there.
func _run_up() -> bool:
	_drive(-1.0, true, false)
	for _i in RUNUP_TICKS:
		await get_tree().physics_frame
		if _speed(_bog) >= Bog.RUN_SPEED - 0.01:
			return true
	return false


# -------------------------------------------------------------- full draw ---

## A bow at full draw walks at half a walk (`Bog.DRAW_SPEED_SCALE`).
##
## The charge is run through `BogCombat.try_draw_bow` rather than by writing
## `Bog.draw` from here, because `_tick_draw` owns that field on the owning
## client and would put it straight back: the whole point of the rule is that it
## reads the same number every other peer reads.
func _check_draw() -> void:
	await _reset()
	_bog.weapon = Loadout.Weapon.BOW
	var combat := _bog.get_node_or_null("Combat") as BogCombat
	if not _ok("the Bog has a Combat node", combat != null):
		return
	combat.refresh_hand()
	combat.try_draw_bow()

	var charged := false
	for _i in DRAW_TICKS:
		await get_tree().physics_frame
		if _bog.draw_fraction() >= 1.0:
			charged = true
			break
	if not _ok("the bow reached full draw", charged):
		return

	# Sprint held on purpose: `AIM_WALKS` refuses it while the string is back,
	# so what this measures is the walk and the draw's scale on top of it.
	_drive(-1.0, true, false)
	await _ticks(SETTLE_TICKS)
	var sum := 0.0
	for _i in SAMPLE_TICKS:
		await get_tree().physics_frame
		sum += _speed(_bog)
	var measured := sum / float(SAMPLE_TICKS)
	var want := Bog.WALK_SPEED * Bog.DRAW_SPEED_SCALE

	print("movement_check: full draw walks at %.3f m/s (target_speed %.3f, want %.2f)"
		% [measured, _bog.target_speed(), want])
	_ok("a full draw walks at %.2f m/s (%.3f)" % [want, measured],
		absf(measured - want) <= SPEED_TOLERANCE)
	_ok("target_speed agrees with the body (%.3f)" % _bog.target_speed(),
		absf(_bog.target_speed() - want) < 0.001)

	combat.release_draw()
	await _ticks(30)
	_bog.weapon = Loadout.DEFAULT
	combat.refresh_hand()
	print("movement_check: draw %s" % _verdict())


# ------------------------------------------------------------- the air draw ---

## The two bones the chest's own facing is read off, the BOG's left first. A
## shoulder line is the one pair that answers "which way is the top half
## pointing" without having to know a bone's local axes, and it is the line
## `import_clip` measures a clip's twist off, so a number here and a number
## there mean the same thing.
const CHEST_LINE: Array[String] = ["mixamorig_LeftShoulder", "mixamorig_RightShoulder"]

## How far a jump may move the drawn pose, in degrees.
##
## The quantity is a **difference**, and that is the whole of what this leg
## knows: an archer's chest is meant to sit most of a right angle off its own
## hips (it reads +92° on the floor and that is the pose, D-097), so "the chest
## faces forward" is the wrong question to ask of it. The two right questions
## are whether the bow points where the body points, which is the only thing a
## player aims with, and whether leaving the ground moved the chest — which is
## the fault itself, stated as the one number that is zero in a working game.
const CHEST_TOLERANCE := 10.0


## A full draw carried into a jump keeps pointing where the body points.
##
## The fault this exists to catch is structural and not cosmetic. The draw is an
## **upper-body layer**: it supplies the arms and the chest and nothing below
## them, and it is square to its own hips — the archer's side-on stance lives in
## the *pelvis*, which is the archer plane's to drive. So the bow points down
## the facing only while that plane is under the layer, and the plane is gone
## the instant the feet leave the ground, because an air pose is a whole body.
## Before D-127 a jump swung the whole top half ninety degrees left and the bow
## with it, for as long as the Bog was off the floor and again for the length of
## the landing.
##
## Measured off `BoneAttachment3D`s and not off `Skeleton3D.get_bone_global_pose`,
## for D-066's reason: a `SkeletonModifier3D` writes the pose the skin is built
## from and the skeleton restores the animation's own behind it, so a bone pose
## read from a `_physics_process` is the pose *before* `BogAim` turned anything.
func _check_air_draw() -> void:
	await _reset()
	_bog.weapon = Loadout.Weapon.BOW
	var combat := _bog.get_node_or_null("Combat") as BogCombat
	if not _ok("the Bog has a Combat node", combat != null):
		return
	var tree := _animator(_bog)
	if not _ok("the Bog has an animator", tree != null):
		return
	combat.refresh_hand()
	# Asked every tick until it takes, rather than once: this leg runs after the
	# one that loosed an arrow, and `bow_recharge` refuses a draw until the next
	# one has grown back.
	var charged := false
	for _i in DRAW_TICKS:
		await get_tree().physics_frame
		if not _bog.is_drawing():
			combat.try_draw_bow()
		elif _bog.draw_fraction() >= 1.0:
			charged = true
			break
	if not _ok("the bow reached full draw", charged):
		return
	# The aim plane crossfades in PLANE_XFADE and the draw layer in about a
	# tenth of a second; this is a long way past both.
	await _ticks(SETTLE_TICKS)
	var ground_chest := _chest_offset(_bog)
	var ground_bow := _bow_offset(_bog)

	_bog.request_jump()
	var airborne := false
	for _i in 30:
		await get_tree().physics_frame
		if not _bog.is_on_floor():
			airborne = true
			break
	if not _ok("the drawn Bog left the ground", airborne):
		return
	# Long enough for `_airborne` to have reached 1 (AIRBORNE_RISE_SPEED is 14
	# a second) and short enough to still be going up.
	await _ticks(12)

	var air_chest := 0.0
	var air_bow := 0.0
	var blend := 0.0
	var held := true
	var samples := 0
	for _i in 20:
		await get_tree().physics_frame
		if _bog.is_on_floor():
			break
		samples += 1
		blend = maxf(blend, float(tree.get(BogAnimator.P_AIRBORNE)))
		held = held and _bog.is_drawing()
		# The worst sample of each, and "worst" is a different question for the
		# two: the bow is measured against the facing, the chest against where
		# the same chest was standing on the floor a moment ago.
		var chest := _chest_offset(_bog)
		var bow := _bow_offset(_bog)
		if samples == 1 or absf(chest - ground_chest) > absf(air_chest - ground_chest):
			air_chest = chest
		if samples == 1 or absf(bow) > absf(air_bow):
			air_bow = bow

	print("movement_check: at a full draw the chest sits %+6.1f° off the facing on the ground and %+6.1f° in the air (worst of %d samples, %+.1f° of swing); the bow %+6.1f° and %+6.1f°"
		% [ground_chest, air_chest, samples, air_chest - ground_chest, ground_bow, air_bow])
	_ok("the jump was taken with the string still back", held and samples > 0)
	_ok("the air pose had taken over (%.2f)" % blend, blend > 0.99)
	_ok("the grounded bow points down the facing (%+.1f°, under %.0f)" % [ground_bow, CHEST_TOLERANCE],
		absf(ground_bow) <= CHEST_TOLERANCE)
	_ok("the airborne bow points down the facing (%+.1f°, under %.0f)" % [air_bow, CHEST_TOLERANCE],
		absf(air_bow) <= CHEST_TOLERANCE)
	_ok("leaving the ground did not turn the chest (%+.1f°, under %.0f)"
		% [air_chest - ground_chest, CHEST_TOLERANCE],
		absf(air_chest - ground_chest) <= CHEST_TOLERANCE)

	var landed := false
	for _i in 180:
		await get_tree().physics_frame
		if _bog.is_on_floor():
			landed = true
			break
	# The touchdown itself, and not only the settled pose after it: `Land` is a
	# **full-body** one-shot that sits *under* the draw layer in the graph, so
	# the second or so it holds is another stretch of archer's chest over a
	# square pelvis if anything here only looked at the two ends.
	var land_chest := ground_chest
	for _i in LAND_TICKS:
		await get_tree().physics_frame
		var chest := _chest_offset(_bog)
		if absf(chest - ground_chest) > absf(land_chest - ground_chest):
			land_chest = chest
	await _ticks(SETTLE_TICKS)
	var after_chest := _chest_offset(_bog)
	print("movement_check: through the landing the chest is worst at %+6.1f° (%+.1f° of swing) and settles at %+6.1f°"
		% [land_chest, land_chest - ground_chest, after_chest])
	_ok("the Bog came back down", landed)
	_ok("the landing did not turn the chest (%+.1f°, under %.0f)"
		% [land_chest - ground_chest, CHEST_TOLERANCE],
		absf(land_chest - ground_chest) <= CHEST_TOLERANCE)
	_ok("and the grounded draw is where it was (%+.1f° against %+.1f°)" % [after_chest, ground_chest],
		absf(after_chest - ground_chest) <= CHEST_TOLERANCE)

	combat.release_draw()
	await _ticks(30)
	_bog.weapon = Loadout.DEFAULT
	combat.refresh_hand()
	print("movement_check: air_draw %s" % _verdict())


## Where the chest is pointing, in degrees off the Bog's own facing, + to the
## Bog's left. Zero is a top half square with the hips.
func _chest_offset(bog: Bog) -> float:
	var probe := _probes(bog, CHEST_LINE)
	if probe.size() < 2:
		return 0.0
	return _line_offset(bog, probe[0].global_position - probe[1].global_position)


## Where the composed bow is pointing, the same way `tools/combat_range.gd`
## reads it: the line between the two fists, off the attachments the props
## themselves hang on.
func _bow_offset(bog: Bog) -> float:
	var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return 0.0
	var bow := skeleton.get_node_or_null("BowHand") as Node3D
	var draw_hand := skeleton.get_node_or_null("SpearHand") as Node3D
	if bow == null or draw_hand == null:
		return 0.0
	var along := bow.global_position - draw_hand.global_position
	var flat := Vector3(along.x, 0.0, along.z)
	if flat.length_squared() < 0.0001:
		return 0.0
	return rad_to_deg(flat.normalized().signed_angle_to(bog.facing(), Vector3.UP))


## A body line turned into degrees off the facing. The line runs to the Bog's
## left, and left crossed with up is forward.
func _line_offset(bog: Bog, line: Vector3) -> float:
	var flat := Vector3(line.x, 0.0, line.z)
	if flat.length_squared() < 0.0001:
		return 0.0
	return rad_to_deg(flat.normalized().cross(Vector3.UP).signed_angle_to(bog.facing(), Vector3.UP))


## `BoneAttachment3D`s hung off the named bones, made once and kept. They are
## the only honest reader of a pose a `SkeletonModifier3D` has touched: they
## update off `skeleton_updated`, which fires after the modifier stack.
func _probes(bog: Bog, bones: Array[String]) -> Array[Node3D]:
	var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return []
	var out: Array[Node3D] = []
	for bone in bones:
		var probe := skeleton.get_node_or_null("Probe_" + bone) as BoneAttachment3D
		if probe == null:
			probe = BoneAttachment3D.new()
			probe.name = "Probe_" + bone
			skeleton.add_child(probe)
			probe.bone_name = bone
		out.append(probe)
	return out


# ------------------------------------------------------------- slide jump ---

## Crouch at speed with no sprint slides, and a jump out of the slide leaves at
## 1.2x the slide's speed along the slide's own direction with 1.12x the lift.
func _check_slide_jump() -> void:
	await _reset()
	if not _ok("the Bog reached run speed", await _run_up()):
		return

	# Sprint **released** as crouch goes down: the old entry rule wanted both
	# keys and this is the line that proves it does not any more.
	_drive(-1.0, false, true)
	await get_tree().physics_frame
	if not _ok("crouch at run speed starts a slide without sprint", _bog.is_sliding()):
		return

	# Part way through, so the reading is taken against a slide `SLIDE_FRICTION`
	# has already eaten into: a jump at the start and a jump at the end of a
	# slide are the same move and have to measure the same way.
	await _ticks(12)
	var before := _speed(_bog)
	var direction := Vector3(_bog.velocity.x, 0.0, _bog.velocity.z).normalized()
	# What the jump will actually multiply. `_handle_slide` runs before
	# `_handle_jump` inside one `_physics_process`, so the tick the jump is
	# taken on has already paid `SLIDE_FRICTION` — a sixtieth of a second of
	# it, 0.047 m/s — and a check that multiplied the reading above would be
	# asserting a number the physics never had.
	var tick := 1.0 / float(Engine.physics_ticks_per_second)
	var slide_speed := maxf(before - Bog.SLIDE_FRICTION * tick, 0.0)
	var jumps := _bog.sync_jump_serial
	var slide_jumps := _bog.sync_slide_jump_serial

	_bog.request_jump()
	await get_tree().physics_frame
	var after := _speed(_bog)
	var lift := _bog.velocity.y
	var along := Vector3(_bog.velocity.x, 0.0, _bog.velocity.z).normalized().dot(direction)
	var want_speed := maxf(slide_speed, Bog.SLIDE_SPEED) * Bog.SLIDE_JUMP_SPEED_SCALE
	var want_lift := _bog.jump_velocity() * Bog.SLIDE_JUMP_IMPULSE_SCALE

	print("movement_check: slide at %.3f m/s (%.3f on the jump tick), jump leaves at %.3f m/s (want %.3f)"
		% [before, slide_speed, after, want_speed])
	print("movement_check: slide jump lifts at %.3f m/s (want %.3f, plain jump %.3f)"
		% [lift, want_lift, _bog.jump_velocity()])
	_ok("a slide jump leaves at 1.2x the slide (%.3f of %.3f)" % [after, slide_speed],
		after >= slide_speed * Bog.SLIDE_JUMP_SPEED_SCALE - 0.001
			and absf(after - want_speed) < 0.01)
	_ok("it leaves along the slide (%.4f)" % along, along > 0.999)
	_ok("it leaves with 1.12x the lift (%.3f)" % lift, absf(lift - want_lift) < 0.01)
	_ok("the slide ended with the jump", not _bog.is_sliding())
	_ok("one jump serial and one slide-jump serial",
		_bog.sync_jump_serial == jumps + 1
			and _bog.sync_slide_jump_serial == slide_jumps + 1)

	# And the counter that says which kind of take-off it was stays still for an
	# ordinary jump, which is the half of it a serial can get wrong silently.
	await _ticks(REST_TICKS)
	_drive(-1.0, true, false)
	await _ticks(30)
	slide_jumps = _bog.sync_slide_jump_serial
	jumps = _bog.sync_jump_serial
	_bog.request_jump()
	await get_tree().physics_frame
	_ok("an ordinary jump bumps only the jump serial",
		_bog.sync_jump_serial == jumps + 1
			and _bog.sync_slide_jump_serial == slide_jumps)
	print("movement_check: slide_jump %s" % _verdict())


# ---------------------------------------------------------------- landing ---

## A landing at run speed with crouch held is a slide on the tick the feet
## arrive, and the animator does not land it.
func _check_landing() -> void:
	await _reset()
	if not _ok("the Bog reached run speed", await _run_up()):
		return
	var tree := _animator(_bog)
	if not _ok("the Bog has an animator", tree != null):
		return

	_bog.request_jump()
	var airborne := false
	for _i in 30:
		await get_tree().physics_frame
		if not _bog.is_on_floor():
			airborne = true
			break
	if not _ok("the Bog left the ground", airborne):
		return

	# Crouch pressed in the air. The pose may tuck; the rules may not move.
	_drive(-1.0, true, true)
	await _ticks(4)
	var air_speed := _bog.target_speed()
	_ok("crouch in the air does not crouch the rules (%.2f m/s, %s)"
		% [air_speed, "crouching" if _bog.is_crouching() else "standing"],
		not _bog.is_crouching() and absf(air_speed - Bog.RUN_SPEED) < 0.001)

	var landed := false
	var pose := 0.0
	var fall := 0.0
	for _i in 120:
		await get_tree().physics_frame
		pose = maxf(pose, _bog.crouch_pose())
		fall = maxf(fall, -_bog.velocity.y)
		if _bog.is_on_floor():
			landed = true
			break
	if not _ok("the Bog came back down", landed):
		return
	var sliding_on_landing := _bog.is_sliding()

	# The one-shots, polled from the tick after touchdown: `Land` fades in over
	# LAND_FADE_IN and holds for the length of the clip, so a shot that was
	# fired cannot pass through this window unseen.
	var landed_shot := false
	var hard_shot := false
	var slide_shot := false
	for _i in 60:
		await get_tree().physics_frame
		landed_shot = landed_shot or bool(tree.get(BogAnimator.P_LAND_ACTIVE))
		hard_shot = hard_shot or bool(tree.get(BogAnimator.P_LAND_HARD_ACTIVE))
		slide_shot = slide_shot or bool(tree.get(BogAnimator.P_SLIDE_ACTIVE))

	print("movement_check: landed at %.2f m/s with the crouch pose at %.2f — %s, Land %s, LandHard %s, Slide %s"
		% [fall, pose, "sliding" if sliding_on_landing else "not sliding",
			"fired" if landed_shot else "not fired",
			"fired" if hard_shot else "not fired",
			"fired" if slide_shot else "not fired"])
	_ok("a landing with crouch held is sliding on the same tick", sliding_on_landing)
	_ok("the crouch pose was pre-armed in the air (%.2f)" % pose, pose > 0.9)
	_ok("the landing was not hard (%.2f m/s, under %.1f)" % [fall, BogAnimator.HARD_LANDING_SPEED],
		fall < BogAnimator.HARD_LANDING_SPEED)
	_ok("Land was never played", not landed_shot)
	_ok("LandHard was never played", not hard_shot)
	_ok("the Slide one-shot was", slide_shot)
	print("movement_check: landing %s" % _verdict())


# ------------------------------------------------------------- jump chain ---

## Four jumps in a row, taken the tick after each landing: the first two get the
## whole of `jump_velocity()` and the third and fourth come up short by
## `Bog.JUMP_CHAIN_SCALES` (D-156). Then a rest gives the height back.
func _check_jump_chain() -> void:
	await _reset()
	# `_reset` rests for exactly JUMP_CHAIN_RESET, and the Bog spends the first
	# few ticks of it falling the 0.2 m off the spawn — so it would arrive here
	# a hair short of rested and hop one already counted.
	await _ticks(CHAIN_REST_TICKS)
	var heights: Array[float] = []
	for _i in Bog.JUMP_CHAIN_SCALES.size():
		heights.append(await _hop())

	var launch := _bog.jump_velocity()
	print("movement_check: jump chain reaches %.3f, %.3f, %.3f, %.3f m (a full jump is %.3f)"
		% [heights[0], heights[1], heights[2], heights[3], _tick_apex(launch)])
	for i in heights.size():
		var scale := float(Bog.JUMP_CHAIN_SCALES[i])
		var want := _tick_apex(launch * scale)
		_ok("hop %d reaches %.3f m at %.2f of a jump (want %.3f)"
			% [i + 1, heights[i], scale, want],
			absf(heights[i] - want) < HEIGHT_TOLERANCE)
	_ok("the first two are the same height (%.3f, %.3f)" % [heights[0], heights[1]],
		absf(heights[0] - heights[1]) < HEIGHT_TOLERANCE)
	_ok("the third is lower than the second (%.3f under %.3f)" % [heights[2], heights[1]],
		heights[2] < heights[1] - 0.05)

	# And the rest is the reset. Long enough to clear JUMP_CHAIN_RESET with the
	# landing tick's own fraction of a second in it.
	await _ticks(CHAIN_REST_TICKS)
	var rested := await _hop()
	print("movement_check: a %.1f s rest jumps %.3f m again"
		% [float(CHAIN_REST_TICKS) / 60.0, rested])
	_ok("a rest gives the whole jump back (%.3f)" % rested,
		absf(rested - _tick_apex(launch)) < HEIGHT_TOLERANCE)
	print("movement_check: jump_chain %s" % _verdict())


# -------------------------------------------------------------- jump hold ---

## The held jump (D-179): a tap reaches the 1.69 m every map is built to, a
## press held through `Bog.JUMP_HOLD_TIME` reaches about half a metre more, and
## a hold that arrives after the rise is over is worth nothing.
func _check_jump_hold() -> void:
	await _reset()
	await _ticks(CHAIN_REST_TICKS)
	var launch := _bog.jump_velocity()
	var tapped := await _hop_held(0)
	await _ticks(CHAIN_REST_TICKS)
	var held := await _hop_held(HOP_TICKS)
	await _ticks(CHAIN_REST_TICKS)
	var late := await _hop_held(-1)

	var want_tap := _tick_apex(launch)
	var want_held := _tick_apex_held(launch, Bog.JUMP_HOLD_TIME)
	print("movement_check: a tap reaches %.3f m and a full hold %.3f m (want %.3f, %.3f)"
		% [tapped, held, want_tap, want_held])
	_ok("a tap is the jump the maps are built to (%.3f)" % tapped,
		absf(tapped - want_tap) < HEIGHT_TOLERANCE)
	_ok("a full hold reaches the held apex (%.3f)" % held,
		absf(held - want_held) < HEIGHT_TOLERANCE)
	_ok("the hold is worth a good bit but not a second jump (%.3f m more)" % (held - tapped),
		held - tapped > 0.3 and held - tapped < 0.8)
	_ok("holding after the rise is over is worth nothing (%.3f)" % late,
		absf(late - want_tap) < HEIGHT_TOLERANCE)
	print("movement_check: jump_hold %s" % _verdict())


## One jump with the key held down for `hold` ticks after the press, and how
## high it got. `hold` of -1 is the late hold: nothing held at the take-off, the
## key pressed once the Bog is already falling.
func _hop_held(hold: int) -> float:
	var floor_y := _bog.global_position.y
	_bog.wants_jump_hold = hold > 0
	_bog.request_jump()
	var top := 0.0
	var airborne := false
	for i in HOP_TICKS:
		await get_tree().physics_frame
		if hold >= 0 and i >= hold:
			_bog.wants_jump_hold = false
		elif hold < 0 and _bog.velocity.y < 0.0:
			_bog.wants_jump_hold = true
		top = maxf(top, _bog.global_position.y - floor_y)
		if not _bog.is_on_floor():
			airborne = true
		elif airborne:
			break
	_bog.wants_jump_hold = false
	return top


## `_tick_apex` with `hold` seconds of `Bog.JUMP_HOLD_GRAVITY_SCALE` gravity at
## the start of the rise, integrated tick by tick the same way.
static func _tick_apex_held(launch: float, hold: float) -> float:
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))
	var tick := 1.0 / float(Engine.physics_ticks_per_second)
	var left := hold
	var vy := launch
	var y := vy * tick
	var top := y
	while vy > 0.0:
		var g := gravity
		if left > 0.0:
			left = maxf(0.0, left - tick)
			g *= Bog.JUMP_HOLD_GRAVITY_SCALE
		vy -= g * tick
		y += vy * tick
		top = maxf(top, y)
	return top


## One jump from where the Bog is standing, and how high above that floor it
## got, in metres. Returns on the tick the feet are back down, so the call after
## this one is the next link in the chain.
func _hop() -> float:
	var floor_y := _bog.global_position.y
	_bog.request_jump()
	var top := 0.0
	var airborne := false
	for _i in HOP_TICKS:
		await get_tree().physics_frame
		top = maxf(top, _bog.global_position.y - floor_y)
		if not _bog.is_on_floor():
			airborne = true
		elif airborne:
			break
	return top


## How high a leap launched at `launch` gets in this engine, integrated the way
## the Bog is integrated: the take-off tick moves at the whole launch speed
## (`_apply_gravity` returns early on the floor and `_handle_jump` runs after
## it), and every tick after that takes its gravity first and then moves.
##
## Not `Bog.apex_for`, which is the continuous answer and is 0.08 m away from
## what sixty discrete ticks reach — larger than the 15% this case is looking
## for is on the third hop.
static func _tick_apex(launch: float) -> float:
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))
	var tick := 1.0 / float(Engine.physics_ticks_per_second)
	var vy := launch
	var y := vy * tick
	var top := y
	while vy > 0.0:
		vy -= gravity * tick
		y += vy * tick
		top = maxf(top, y)
	return top


# ----------------------------------------------------------------- remote ---

## The slide jump on somebody else's screen.
##
## The snapshot is copied field by field **out of the replication config
## `scenes/player/bog.tscn` ships**, not out of a list written here: a field
## that is not in that config is a field the synchroniser would never send, and
## copying a hand-written list would be a check that passed while the game
## desynced.
func _check_remote() -> void:
	await _reset()
	var config := _replication_config(_bog)
	if not _ok("the Bog scene carries a replication config", config != null):
		return
	var mode := -1
	for path in config.get_properties():
		if String(path).ends_with(":sync_slide_jump_serial"):
			mode = config.property_get_replication_mode(path)
	_ok("sync_slide_jump_serial is replicated ON_CHANGE (mode %d)" % mode,
		mode == SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)

	var tree := _animator(_remote)
	if not _ok("the remote Bog has an animator", tree != null):
		return

	# The remote Bog's imaginary client, publishing once a tick. Nothing else
	# about that Bog is ever written.
	_relay(config)
	if not _ok("the Bog reached run speed", await _run_up_relaying(config)):
		return
	_drive(-1.0, false, true)
	await get_tree().physics_frame
	_relay(config)
	if not _ok("the slide started", _bog.is_sliding()):
		return
	await _ticks(6)
	_relay(config)
	var serial := _bog.sync_slide_jump_serial

	_bog.request_jump()
	await get_tree().physics_frame
	_relay(config)
	_ok("the take-off was a slide jump", _bog.sync_slide_jump_serial == serial + 1)
	_ok("the serial arrived on the remote copy",
		_remote.sync_slide_jump_serial == _bog.sync_slide_jump_serial)

	# Two frames for the remote's animator to see it: one physics tick for
	# `_follow_network`, and the idle frames around it are where the tree runs.
	var leap_kind := 0.0
	var leaping := 0.0
	for _i in 10:
		await get_tree().physics_frame
		_relay(config)
		leap_kind = maxf(leap_kind, float(tree.get(BogAnimator.P_SLIDE_LEAP)))
		leaping = maxf(leaping, float(tree.get(BogAnimator.P_LEAP)))

	print("movement_check: remote leap blend %.2f, slide-leap blend %.2f, serial %d"
		% [leaping, leap_kind, _remote.sync_slide_jump_serial])
	_ok("the remote animator is playing a leap (%.2f)" % leaping, leaping > 0.5)
	_ok("and it is the slide jump's leap (%.2f)" % leap_kind, leap_kind > 0.99)
	print("movement_check: remote %s" % _verdict())


func _replication_config(bog: Bog) -> SceneReplicationConfig:
	var sync := bog.get_node_or_null("Sync") as MultiplayerSynchronizer
	return sync.replication_config if sync != null else null


## One packet, from the owner's copy to everybody else's.
func _relay(config: SceneReplicationConfig) -> void:
	for path in config.get_properties():
		var field := String(path).get_slice(":", 1)
		_remote.set(field, _bog.get(field))


func _run_up_relaying(config: SceneReplicationConfig) -> bool:
	_drive(-1.0, true, false)
	for _i in RUNUP_TICKS:
		await get_tree().physics_frame
		_relay(config)
		if _speed(_bog) >= Bog.RUN_SPEED - 0.01:
			return true
	return false


# ---------------------------------------------------------------- verdicts ---

var _failures_at_leg: int = 0


func _ok(what: String, passed: bool) -> bool:
	_checks += 1
	if not passed:
		_failures += 1
		print("  FAIL  %s" % what)
	return passed


## PASS or FAIL for everything since the last time this was asked.
func _verdict() -> String:
	var failed := _failures - _failures_at_leg
	_failures_at_leg = _failures
	return "PASS" if failed == 0 else "FAIL (%d)" % failed
