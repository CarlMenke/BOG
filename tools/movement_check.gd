extends Node3D
## The feel round's four movement claims, measured on a real Bog. Development
## tool, not shipped.
##
##   Godot --headless --fixed-fps 60 --path . tools/movement_check.tscn
##
## **Why this is not in `tools/playthrough.gd`.** The playthrough is a walk
## across the joins between whole scenes, and it runs seven times in the gate,
## once per map. Every one of these four claims is about a body on a flat floor
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
## The four verdicts:
##
##   draw        a full draw walks at WALK_SPEED * DRAW_SPEED_SCALE
##   slide_jump  crouch without sprint slides, and a jump out of it leaves at
##               1.2x the slide along the slide's own direction, with 1.12x lift
##   landing     a run-speed landing with crouch held is sliding on the tick it
##               touches down, and never plays Land or LandHard
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
## Ticks the speed is averaged over, after the body has had time to reach it.
const SETTLE_TICKS := 90
const SAMPLE_TICKS := 30
## How close a measured speed has to be to the number it is meant to be, in m/s.
const SPEED_TOLERANCE := 0.05

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
	await _check_slide_jump()
	await _check_landing()
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
	bog.set_view_basis(Basis.IDENTITY, false)
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
	_bog.revive_at(Transform3D(Basis.IDENTITY, SPAWN))
	_bog.set_view_basis(Basis.IDENTITY, false)
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
