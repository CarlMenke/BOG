extends Node3D
## The PvP camera rig, driven the way a mouse drives it, and asked five
## questions every frame. See `docs/PLAN_CAMERA.md`.
## Development tool, not shipped. Headless, a couple of seconds.
##
##   Godot --headless --fixed-fps 60 --path . tools/camera_range.tscn
##
## Eight legs. Seven of them are the placement stations this file has always had
## — a long wall on each shoulder, a corner, a tree canopy and its edge, a wall
## at the Bog's back, and a low tunnel — because the complaint they were written
## for ("too frequently the camera is inside meshes and stuff when there are
## meshes behind the character") is not answered by rewriting the rig, it is
## answered by the same 1,700 frames still coming back clean. The eighth is new
## and belongs to the rework: a patch of open ground where the view is turned and
## the *body* is watched.
##
## The five verdicts:
##
## - **clip** — the lens is never inside the scenery. Three tests, because no one
##   of them sees every case: a point query at the lens (inside a solid), a
##   `NEAR_CLEARANCE` sphere there (the near plane is 0.05 m out and about 0.09 m
##   to its corners, so a lens merely *outside* a face still draws the inside of
##   it), and a ray from the Bog's eye to the lens (on the far side of a wall,
##   which is what a player actually sees as "inside" and which neither of the
##   first two can find against a thin face or a trimesh). Zero frames.
##
## - **frame** — the lens is never off the segment from the pivot to the
##   unobstructed lens point. This is D-083's invariant, and under the new rig it
##   is not a rule the code obeys but the shape of the code: there is one sweep
##   along one segment and the lens sits at a fraction of it, so the Bog cannot
##   slide across the picture while the camera comes in. Measured as the
##   perpendicular distance from that line, which is zero up to float. Zero
##   frames.
##
## - **aim** — the point `BogCombat` would throw at is the point a ray out of the
##   *actual* camera hits, within a centimetre. This is the invariant that
##   replaced D-045's: the aim used to be read from where the camera would be
##   with nothing in the way, which kept a wall from moving a spear but cost the
##   crosshair its meaning. Now screen centre is the shot. The check reaches past
##   the public API once, into `BogCombat._aim_point`, because that function is
##   literally what a throw reads and a copy of it would prove nothing; the other
##   side of the comparison is built here from the `Camera3D` node alone.
##
## - **calm** — how the rig *moves*, which is what is left once the placement is
##   right, and it is three claims rather than a budget. The old rig needed
##   budgets because it had five rates and a lead fighting each other (D-088);
##   this one has a pivot that eases, a rotation with no filter at all, and an
##   arm that comes in at once and goes out on one exponential — so every one of
##   these can be zero:
##     * **drag** — the pivot never moves further in a frame than the subject
##       moved plus the ease of the gap it already had. An exponential cannot
##       overshoot, and this says so in numbers.
##     * **loose** — with the view still and the arm out at full length, the lens
##       moves no further than the body moved plus the ease of the gap the pivot
##       already had. It passes by the lens being a rigid offset from the pivot
##       rather than by being damped, which is the thing worth asserting: there
##       is nothing else in this rig allowed to move the picture.
##     * **late** — on the way back out, the arm never grows faster than
##       `RETURN_RATE` allows from where it was.
##   Pull-ins are exempt, by design: a frame drawn from inside a wall is worse
##   than a pop, so coming in is instant. The worst one is printed rather than
##   judged, and it is the honest price of the rule.
##
## - **faces** — the body follows the camera (the whole rework), *except* while
##   the player is only looking around (`Bog.YAW_SLACK`). Five claims, and the
##   middle three are the idle slack:
##     * a 45-degree view step with the Bog standing still moves the body **not
##       at all** — 45 is inside the 60 degrees of slack, and the whole point of
##       the feature is that a look is not a turn;
##     * a second 45-degree step, putting the view 90 off the body and so 30
##       past the edge, leaves the body at rest *on* the edge — 60 degrees off
##       the view, not 90 and not 0. The slack travels round with the view;
##     * then the player runs, with the view held where it was: the body has to
##       close that 60 degrees inside 0.35 s, and no single tick of it may turn
##       the body further than `rotate_toward` can — which is the difference
##       between squaring up and snapping, and the only part of this a number
##       can tell apart;
##     * running view steps of 45 degrees are matched to within 2 degrees inside
##       0.1 s, exactly as before: once you are moving, the body is welded on;
##     * through a sword spin and an emote the body yaw must not move at all
##       while the view is swung 180 degrees, because those two are commitments
##       the camera is not allowed to re-point.

## World and camera blockers, which is what the rig is meant to avoid. Bogs,
## projectiles and pickups are deliberately not in it.
const WORLD_MASK := 1 | 64
## What `BogCombat` aims against.
const AIM_MASK := 1 | 2 | 8

const NEAR_CLEARANCE := 0.1
const AIM_TOLERANCE := 0.01
## How far off the pivot-to-lens line the lens may sit. Half a centimetre is
## float slack on a 3.16 m segment; the rig places the lens *on* the segment by
## construction, so the real margin is zero.
const FRAME_TOLERANCE := 0.005
## Metres of float slack on a per-frame motion claim, and the fraction of slack
## allowed on the eased return so a rounding difference in `delta` is not a
## verdict.
const CALM_SLACK := 0.002
const RETURN_SLACK := 1.05
## Radians of view moved in one frame past which the frame is a *cut* and not a
## turn. 0.15 rad is 9 degrees a frame, 540 deg/s: well above anything the
## sweeping legs produce and well below the deliberate flick in "back to a wall".
const CUT_TURN := 0.15
## `faces`: how close the body has to get to the view, how long it may take, and
## how much a committed heading may drift while the view swings (none, in
## practice — `Bog._face` returns before touching `body_yaw`).
const FACE_TOLERANCE := 0.0349   # 2 degrees
const FACE_CATCHUP_TICKS := 6    # 0.1 s at 60 Hz, once the slack is shut
const FACE_HOLD_TOLERANCE := 0.0087  # half a degree
## The idle slack, read off the Bog rather than typed here, so a re-tune of the
## feel cannot leave this testbed asserting a number nobody ships.
const FACE_SLACK := Bog.YAW_SLACK
## How long the body gets to hand the whole slack back once the player moves.
## `Bog.SLACK_CLOSE_RATE` puts the honest figure at 60 degrees in 0.26 s, or
## about 16 ticks; 21 is that plus the frame the view basis spends crossing from
## `_process` to the next physics tick, plus slack for the 2-degree tolerance.
const FACE_CLOSE_TICKS := 21     # 0.35 s at 60 Hz
## Ticks given to the body to come to rest on the slack's edge after the second
## standing step. It is 30 degrees of `TURN_SPEED`, about 3 ticks; 30 is room.
const FACE_EDGE_SETTLE := 30

## Ticks after a teleport before anything is checked: the pivot eases after the
## body (`BogCamera.LAG_FLAT`), so for a moment after a forty-metre jump it is
## legitimately flying through whatever lies between two stations.
const SETTLE_TICKS := 50

## The `facing` leg's clock, in ticks of its own. Two standing steps, then the
## move that closes the slack, then running steps, then a spin and an emote —
## and every phase gets room at its end, because what is being measured is where
## the body comes to *rest* and a phase that ran into the next one would be
## measuring a body still on its way somewhere.
const FACE_STEP := 0.7854        # 45 degrees a step
const FACE_STEP_TICKS := 16
## Standing. The first step is inside the slack, so the body must not move at
## all; the second puts the view 90 degrees off it, 30 past the edge.
const FACE_STAND_A := 20
const FACE_STAND_B := 70
## Then forward, with the view held where the second step left it. This is the
## owner's "if they start moving, smooth it back to inside the previous clamp",
## and it is driven from a standstill at the edge so that the 60 degrees being
## handed back is the whole 60 and not some fraction of it.
const FACE_MOVE_AT := 130
## Running steps, by which time the slack has been shut for a second.
const FACE_RUN_FROM := 190
const FACE_TURN_END := 300
const FACE_SPIN_AT := 310
## Wall-clock seconds, because `Bog.is_spinning` is on `Time.get_ticks_msec`
## and a headless loop at `--fixed-fps 60` runs many times faster than real
## time. 3 s is not a feel number, it is enough real time to be sure the spin
## outlasts the 95 ticks of sweep and settle below on any machine this runs on.
const FACE_SPIN_SECONDS := 3.0
const FACE_SPIN_SWEEP := 320
const FACE_SWEEP_TICKS := 60
const FACE_SPIN_END := 405
const FACE_EMOTE_AT := 425
const FACE_EMOTE_SWEEP := 445

## Each leg puts the Bog on `spot` facing -Z and then runs `ticks` of `drive`.
const LEGS := [
	{"name": "wall on the right", "spot": Vector3(0.0, 0.1, 12.0), "ticks": 200, "drive": "wall"},
	{"name": "wall on the left", "spot": Vector3(2.4, 0.1, 12.0), "ticks": 200, "drive": "wall"},
	{"name": "corner", "spot": Vector3(40.0, 0.1, 0.0), "ticks": 260, "drive": "spin"},
	{"name": "under a canopy", "spot": Vector3(80.0, 0.1, 0.0), "ticks": 260, "drive": "canopy"},
	{"name": "canopy edge", "spot": Vector3(80.0, 0.1, 3.4), "ticks": 260, "drive": "canopy"},
	{"name": "back to a wall", "spot": Vector3(120.0, 0.1, 0.0), "ticks": 260, "drive": "turn"},
	{"name": "tunnel", "spot": Vector3(160.0, 0.1, 10.0), "ticks": 260, "drive": "tunnel"},
	{"name": "open ground", "spot": Vector3(255.0, 0.1, 0.0), "ticks": 540, "drive": "face"},
]

## Boxes, as {centre, size}. Layer 1, like every map's collision.
const BLOCKS := [
	# ground under every station
	[Vector3(90.0, -0.5, 0.0), Vector3(240.0, 1.0, 80.0)],
	# station 1: one long wall, faces at x = 0.9 and x = 1.5
	[Vector3(1.2, 2.0, 1.5), Vector3(0.6, 4.0, 33.0)],
	# station 2: a corner behind and to the right
	[Vector3(41.1, 2.0, 0.0), Vector3(0.6, 4.0, 12.0)],
	[Vector3(40.0, 2.0, 1.1), Vector3(12.0, 4.0, 0.6)],
	# station 3: a tree — canopy underside at 2.0 m, and a trunk
	[Vector3(80.0, 2.3, 0.0), Vector3(8.0, 0.6, 8.0)],
	[Vector3(81.4, 1.0, 0.0), Vector3(0.7, 2.0, 0.7)],
	# station 4: a wall at the Bog's back, face at z = 0.6
	[Vector3(120.0, 2.0, 0.9), Vector3(16.0, 4.0, 0.6)],
	# station 5: a tunnel along Z — walls at x = ±1.3, ceiling at 2.2
	[Vector3(158.4, 1.5, 0.0), Vector3(0.6, 3.0, 26.0)],
	[Vector3(161.6, 1.5, 0.0), Vector3(0.6, 3.0, 26.0)],
	[Vector3(160.0, 2.5, 0.0), Vector3(3.8, 0.6, 26.0)],
	# station 6 is deliberately empty ground: the `facing` leg is about the body.
	# It gets a pad of its own, overlapping the shared floor at x = 205, because
	# the leg now runs for nearly three seconds and the shared floor's far edge
	# (x = 210) and the tunnel (x = 161.6) are both inside that. Nothing else
	# stands within 90 m of it, which is the point.
	[Vector3(255.0, -0.5, 0.0), Vector3(100.0, 1.0, 120.0)],
]

var _leg: int = -1
var _tick: int = 0
var _bog: Bog
var _rig: BogCamera
var _combat: BogCombat
## The full arm, pivot to unobstructed lens: 3.16 m for the 3.1 m distance and
## the 0.62 m shoulder. Read off the rig's own constants so a re-tune cannot
## leave this checking a length nobody ships.
var _arm: float = 0.0

var _leg_checked: int = 0
var _leg_clipped: int = 0
var _leg_inside: int = 0
var _leg_touching: int = 0
var _leg_behind: int = 0
var _leg_worst_behind: float = 0.0
var _leg_aim_off: int = 0
var _leg_worst_aim: float = 0.0
var _leg_off_line: int = 0
var _leg_worst_line: float = 0.0
var _leg_nearest: float = INF
var _leg_from: Vector3 = Vector3.ZERO

## `calm`'s three counts and the pull-in it does not judge.
var _leg_calm: int = 0
var _leg_drag: int = 0
var _leg_free: int = 0
var _leg_loose: int = 0
var _leg_late: int = 0
var _leg_pulls: int = 0
var _leg_flips: int = 0
var _leg_worst_pull: float = 0.0
var _leg_worst_cut: float = 0.0

## Last frame's arm length, pivot, subject eye, lens and view. Cleared at every
## leg, because a teleport between stations is a legitimate jump and comparing
## across it would measure the teleport.
var _prev_arm: float = 0.0
var _prev_pivot: Vector3 = Vector3.ZERO
var _prev_eye: Vector3 = Vector3.ZERO
var _prev_lens: Vector3 = Vector3.ZERO
var _prev_yaw: float = 0.0
var _prev_pitch: float = 0.0
var _prev_sign: int = 0
var _have_prev: bool = false

## `faces` bookkeeping. `_face_yaw` is the view the leg is driving toward,
## `_face_turned_at` the tick it last stepped, and `_face_held` the body yaw a
## commitment froze.
var _face_yaw: float = 0.0
var _face_turned_at: int = 0
var _face_settled: bool = true
var _face_turns: int = 0
var _face_slow: int = 0
var _face_worst_catchup: int = 0
var _face_worst_error: float = 0.0
## Standing phase A: the body yaw the first step was taken against, and how far
## the body wandered off it while the view sat 45 degrees away.
var _face_stand_from: float = 0.0
var _face_stand_frames: int = 0
var _face_stand_broke: int = 0
var _face_worst_stand: float = 0.0
## Standing phase B: how far the body ended up from the slack's edge once the
## view had stepped 30 degrees past it.
var _face_edge_frames: int = 0
var _face_edge_broke: int = 0
var _face_worst_edge: float = 0.0
## The move-start: ticks the body took to give the whole slack back, -1 while it
## still has not, and the largest single tick of that close.
var _face_close_ticks: int = -1
var _face_close_step: float = 0.0
## The largest body turn in any one physics tick, anywhere on the leg. This is
## `rotate_toward`'s cap being asserted rather than assumed: it is what says the
## slack closing is a turn and not a teleport.
var _face_worst_step: float = 0.0
var _face_prev_yaw: float = 0.0
var _face_have_prev: bool = false
## `Bog.TURN_SPEED` for one physics tick, plus float slack. Filled in `_ready`
## off the engine rather than off 60, because the budget above is in ticks.
var _turn_cap: float = 0.0
var _face_held: float = 0.0
var _face_holding: bool = false
var _face_held_frames: int = 0
var _face_broke: int = 0
var _face_worst_drift: float = 0.0
var _face_spun: bool = false
var _face_emoted: bool = false
var _face_notes: Array[String] = []

var _total_checked: int = 0
var _total_clipped: int = 0
var _total_aim_off: int = 0
var _total_off_line: int = 0
var _total_calm: int = 0
var _total_drag: int = 0
var _total_free: int = 0
var _total_loose: int = 0
var _total_late: int = 0
var _total_pulls: int = 0
var _total_flips: int = 0
var _worst_pull: float = 0.0
var _worst_cut: float = 0.0
var _worst_aim: float = 0.0
var _worst_line: float = 0.0


func _ready() -> void:
	# After the rig in the same frame, so what is checked is what gets drawn.
	process_priority = 1000
	_build_stage()

	var players := Node3D.new()
	players.name = "Players"
	add_child(players)

	Net.start_offline()
	var config := Net.config
	config.warmup_time = 0.0
	config.spawn_protection = 0.0
	config.time_limit = 0
	var spot: Vector3 = LEGS[0]["spot"]
	MatchState.register_arena(players, [Transform3D(Basis.IDENTITY, spot)] as Array[Transform3D])

	_bog = MatchState.bogs.get(1) as Bog
	if _bog == null:
		print("camera_range: no local Bog was spawned — clip FAIL")
		get_tree().quit()
		return
	_rig = _bog.get_node("CameraRig") as BogCamera
	_combat = _bog.get_node("Combat") as BogCombat
	_arm = Vector3(BogCamera.SHOULDER_DEFAULT, 0.0, BogCamera.DISTANCE_DEFAULT).length()
	_turn_cap = Bog.TURN_SPEED / float(Engine.physics_ticks_per_second) + 0.0001
	print("camera_range: starting, %d legs, arm %.3f m, slack %.1f deg, turn cap %.4f rad a tick" % [
		LEGS.size(), _arm, rad_to_deg(FACE_SLACK), _turn_cap])
	_next_leg()


func _next_leg() -> void:
	if _leg >= 0:
		_report_leg()
	_release_keys()
	_leg += 1
	_tick = -SETTLE_TICKS
	_leg_checked = 0
	_leg_clipped = 0
	_leg_inside = 0
	_leg_touching = 0
	_leg_behind = 0
	_leg_worst_behind = 0.0
	_leg_aim_off = 0
	_leg_worst_aim = 0.0
	_leg_off_line = 0
	_leg_worst_line = 0.0
	_leg_nearest = INF
	_leg_calm = 0
	_leg_drag = 0
	_leg_free = 0
	_leg_loose = 0
	_leg_late = 0
	_leg_pulls = 0
	_leg_flips = 0
	_leg_worst_pull = 0.0
	_leg_worst_cut = 0.0
	_have_prev = false
	_prev_sign = 0
	if _leg >= LEGS.size():
		_finish()
		return
	_bog.revive_at(Transform3D(Basis.IDENTITY, LEGS[_leg]["spot"]))
	_rig.set_view(0.0, -0.12)
	_face_yaw = 0.0
	_face_holding = false
	_face_settled = true
	# A teleport is a jump the per-tick cap is not asked about.
	_face_have_prev = false


func _physics_process(_delta: float) -> void:
	if _bog == null or _leg < 0 or _leg >= LEGS.size():
		return
	var leg: Dictionary = LEGS[_leg]
	_tick += 1
	if _tick > int(leg["ticks"]):
		_next_leg()
		return
	_drive(leg["drive"], maxi(_tick, 0))


## The view and the keys for tick `t` of a leg. Before the leg starts (the
## settle) this is held at t = 0, so the rig arrives already looking the right way.
func _drive(kind: String, t: int) -> void:
	var yaw := 0.0
	var pitch := -0.12
	var forward := false
	match kind:
		"wall":
			# Walk along the wall looking along it, then keep walking while the
			# view swings towards and away from it and tips up and down.
			forward = t > 0
			if t > 60:
				yaw = 0.8 * sin((t - 60) * 0.05)
			pitch = -0.12 + 0.5 * sin(t * 0.03)
		"spin":
			yaw = t * 0.05
			pitch = -0.12 + 0.75 * sin(t * 0.037)
		"canopy":
			# From looking up at the sky to looking down at the feet — the
			# second is the camera rising into the leaves.
			yaw = t * 0.04
			pitch = -0.25 + 0.85 * sin(t * 0.045)
		"turn":
			# Swing round through the wall at the Bog's back, then flick.
			if t < 140:
				yaw = 3.2 * sin(t * 0.045)
			else:
				yaw = 1.45 * floorf((t - 140) / 15.0)
			pitch = -0.2 + 0.7 * sin(t * 0.05)
		"tunnel":
			forward = t > 0
			yaw = 1.1 * sin(t * 0.04)
			pitch = -0.12 + 0.65 * sin(t * 0.07)
		"face":
			var driven := _drive_face(t)
			yaw = float(driven["yaw"])
			forward = bool(driven["forward"])
	_rig.set_view(yaw, pitch)
	if forward:
		Input.action_press("move_forward")
	else:
		Input.action_release("move_forward")


## The `faces` leg, in six phases, and the only leg that touches the Bog itself.
##
## The view is stepped rather than swept on purpose. A sweep measures a body
## chasing a moving target, which is a lag and not a catch-up; a step asks the
## question the player asks, which is "I flicked, when is the Bog pointing
## there". 45 degrees is a real mouse movement: one of them is inside the idle
## slack and two are not, which is exactly the pair of answers the feature owes.
## Once the Bog is moving a step closes at `Bog.TURN_SPEED` in about 3.4 ticks,
## so 6 ticks of budget is the turn plus the one frame the view basis spends
## crossing from `_process` to the next physics tick, plus slack.
##
## The move-start phase presses one key and touches the view not at all, because
## the claim there is about the *body* alone: it is at rest on the slack's edge,
## the view has not moved, and the only thing that can close the 60 degrees
## between them is the slack being given back. Anything else moving would make
## the measurement two things at once.
##
## The two commitments are then driven directly rather than through a key, for
## `tools/combat_range.gd`'s reason: what is being measured is what `Bog._face`
## does about `is_spinning()` and `is_emoting()`, and a key press would add the
## whole of `BogCombat`'s gating to the thing that could fail.
func _drive_face(t: int) -> Dictionary:
	# One sample of the body a physics tick, which is where the per-tick turn
	# cap is measured. Taken before the Bog's own `_physics_process` runs this
	# tick, so consecutive samples are one `Bog._face` apart exactly.
	if _face_have_prev:
		var step := absf(angle_difference(_bog.body_yaw, _face_prev_yaw))
		_face_worst_step = maxf(_face_worst_step, step)
		if t > FACE_MOVE_AT and t <= FACE_RUN_FROM:
			_face_close_step = maxf(_face_close_step, step)
	_face_prev_yaw = _bog.body_yaw
	_face_have_prev = true

	var forward := false
	if t <= FACE_TURN_END:
		forward = t >= FACE_MOVE_AT
		# The two standing steps, then the running ones. `t > 0` because the
		# settle calls this with t = 0 over and over, and a step there would be
		# fifty turns nobody drove and nobody watched.
		if t == FACE_STAND_A:
			# The body the first step is taken against, read before the view
			# moves — the claim is that this number does not change.
			_face_stand_from = _bog.body_yaw
			_face_yaw += FACE_STEP
		elif t == FACE_STAND_B:
			_face_yaw += FACE_STEP
		elif t >= FACE_RUN_FROM and (t - FACE_RUN_FROM) % FACE_STEP_TICKS == 0 \
				and t <= FACE_TURN_END - FACE_STEP_TICKS:
			_face_yaw += FACE_STEP
			_face_turned_at = t
			_face_settled = false
			_face_turns += 1
	elif t <= FACE_SPIN_END:
		if t == FACE_SPIN_AT:
			_bog.begin_spin(FACE_SPIN_SECONDS)
			_face_spun = _bog.is_spinning()
			if not _face_spun:
				_face_notes.append("the spin never started")
		if t == FACE_SPIN_SWEEP - 2:
			_begin_hold()
		if t == FACE_SPIN_END and _face_spun and not _bog.is_spinning():
			# The spin's clock is wall time and this leg's is ticks, so say so
			# out loud rather than let a fast machine and a slow one disagree
			# about why the body moved.
			_face_notes.append("the spin ran out before the sweep was over")
		if t >= FACE_SPIN_SWEEP:
			var through := clampf(float(t - FACE_SPIN_SWEEP) / float(FACE_SWEEP_TICKS),
				0.0, 1.0)
			return {"yaw": _face_yaw + PI * through, "forward": false}
	else:
		if t == FACE_SPIN_END + 1:
			# The spin is over: let the body come back onto the view it was
			# swung to, which is itself the other half of the claim.
			_face_yaw += PI
			_end_hold()
		if t == FACE_EMOTE_AT:
			_combat.start_emote()
			_face_emoted = _bog.is_emoting()
			if not _face_emoted:
				_face_notes.append("the emote never started")
		if t == FACE_EMOTE_SWEEP - 2:
			_begin_hold()
		if t >= FACE_EMOTE_SWEEP:
			var through := clampf(float(t - FACE_EMOTE_SWEEP) / float(FACE_SWEEP_TICKS),
				0.0, 1.0)
			return {"yaw": _face_yaw + PI * through, "forward": false}
	return {"yaw": _face_yaw, "forward": forward}


## Start watching a heading the rig is not allowed to move.
func _begin_hold() -> void:
	_face_held = _bog.body_yaw
	_face_holding = true


func _end_hold() -> void:
	_face_holding = false


func _process(delta: float) -> void:
	if _bog == null or _leg < 0 or _leg >= LEGS.size() or _tick <= 0:
		return
	_check_frame(delta)
	if LEGS[_leg]["drive"] == "face":
		_check_facing()


func _check_frame(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var cam := _rig.camera().global_position
	var pivot := _rig.global_position
	var eye := _bog.global_position + Vector3.UP * _bog.eye_height()
	if _leg_checked == 0:
		_leg_from = _bog.global_position
	_leg_checked += 1
	# How far the scenery shoved the lens in, so a leg that never pushed the
	# camera at all is visible as one rather than passing quietly.
	_leg_nearest = minf(_leg_nearest, cam.distance_to(pivot))

	# ------------------------------------------------------------------ clip ---
	var point := PhysicsPointQueryParameters3D.new()
	point.position = cam
	point.collision_mask = WORLD_MASK
	var inside := not space.intersect_point(point, 1).is_empty()

	var sphere := SphereShape3D.new()
	sphere.radius = NEAR_CLEARANCE
	var shape := PhysicsShapeQueryParameters3D.new()
	shape.shape = sphere
	shape.transform = Transform3D(Basis.IDENTITY, cam)
	shape.collision_mask = WORLD_MASK
	var touching := not space.intersect_shape(shape, 1).is_empty()

	var hit := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(eye, cam, WORLD_MASK))
	var behind := not hit.is_empty()

	if inside:
		_leg_inside += 1
	if touching:
		_leg_touching += 1
	if behind:
		_leg_behind += 1
		_leg_worst_behind = maxf(_leg_worst_behind, cam.distance_to(hit["position"]))
	if inside or touching or behind:
		_leg_clipped += 1

	# ------------------------------------------------------------------- aim ---
	var aim_error := _combat._aim_point().distance_to(_lens_aim_point(space))
	if aim_error > AIM_TOLERANCE:
		_leg_aim_off += 1
	_leg_worst_aim = maxf(_leg_worst_aim, aim_error)

	# ----------------------------------------------------------------- frame ---
	# The unobstructed lens direction for this view, built here from the rig's
	# yaw and pitch rather than read off the camera, so it is an independent
	# statement of where the segment runs. How far the lens sits off that line is
	# the Bog's drift across the picture (D-083), and it has to be zero.
	var line := (Basis(Vector3.UP, _rig.yaw()) * Basis(Vector3.RIGHT, _rig.pitch())
		* Vector3(BogCamera.SHOULDER_DEFAULT, 0.0, BogCamera.DISTANCE_DEFAULT)).normalized()
	var along := cam - pivot
	var off_line := (along - line * along.dot(line)).length()
	if off_line > FRAME_TOLERANCE:
		_leg_off_line += 1
	_leg_worst_line = maxf(_leg_worst_line, off_line)

	# ------------------------------------------------------------------ calm ---
	var arm := along.length()
	if _have_prev:
		_leg_calm += 1
		# drag: the pivot never outruns the body plus the ease of the gap it
		# already had. `LAG_FLAT` is the faster of the rig's two rates, so it
		# bounds the vertical channel as well.
		var gap := _prev_pivot.distance_to(_prev_eye)
		var cap := gap * (1.0 - exp(-BogCamera.LAG_FLAT * delta)) \
			+ _prev_eye.distance_to(eye) + CALM_SLACK
		if _prev_pivot.distance_to(pivot) > cap:
			_leg_drag += 1

		# loose: with the view still and the arm out at full length, nothing but
		# the pivot's own easing may move the lens — so the lens is held to the
		# same cap the pivot is. It is the literal form of "with no scenery
		# contact the lens moves no more than the body moved plus lag slack",
		# and it passes by being a rigid offset rather than by being damped,
		# which is the property actually worth asserting: there is no second
		# thing in this rig allowed to move the picture.
		var still := is_equal_approx(_rig.yaw(), _prev_yaw) \
			and is_equal_approx(_rig.pitch(), _prev_pitch)
		if still and arm >= _arm - 0.001 and _prev_arm >= _arm - 0.001:
			_leg_free += 1
			if _prev_lens.distance_to(cam) > cap:
				_leg_loose += 1

		var step := arm - _prev_arm
		if step < -CALM_SLACK:
			# A pull-in. Exempt, but this is the pop the design is buying, so
			# it is measured and printed. Split on whether the view was *turned*
			# or *cut* this frame: the "back to a wall" leg deliberately flicks
			# 83 degrees between two frames, which no rig can lead and no player
			# reads as camera movement — the whole picture changed — and mixing
			# that in with a mouse drag would hide the number worth knowing.
			_leg_pulls += 1
			if absf(_rig.yaw() - _prev_yaw) + absf(_rig.pitch() - _prev_pitch) > CUT_TURN:
				_leg_worst_cut = maxf(_leg_worst_cut, -step)
			else:
				_leg_worst_pull = maxf(_leg_worst_pull, -step)
		elif step > CALM_SLACK:
			var out := (_arm - _prev_arm) * (1.0 - exp(-BogCamera.RETURN_RATE * delta))
			if step > out * RETURN_SLACK + CALM_SLACK:
				_leg_late += 1
		var sign_now := 0
		if step > CALM_SLACK:
			sign_now = 1
		elif step < -CALM_SLACK:
			sign_now = -1
		if sign_now != 0:
			if _prev_sign != 0 and sign_now != _prev_sign:
				_leg_flips += 1
			_prev_sign = sign_now
	_prev_arm = arm
	_prev_pivot = pivot
	_prev_eye = eye
	_prev_lens = cam
	_prev_yaw = _rig.yaw()
	_prev_pitch = _rig.pitch()
	_have_prev = true


## Where a throw goes for this view, worked out from the `Camera3D` node and
## nothing else: its own position, its own forward, and the Bog skipped by the
## lens's own distance from the pivot — which is the whole of `aim_ray`'s
## contract restated from the outside. The ray is only tested from the Bog's own
## depth outwards, because nothing behind the thrower is something it can throw
## at.
func _lens_aim_point(space: PhysicsDirectSpaceState3D) -> Vector3:
	var cam := _rig.camera()
	var origin := cam.global_position
	var direction := -cam.global_transform.basis.z
	var from := origin + direction * origin.distance_to(_rig.global_position)
	var query := PhysicsRayQueryParameters3D.create(
		from, origin + direction * BogCombat.MAX_AIM_DISTANCE, AIM_MASK)
	query.exclude = [_bog.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return origin + direction * BogCombat.MAX_AIM_DISTANCE
	var p: Vector3 = hit["position"]
	if origin.distance_to(p) < BogCombat.MIN_AIM_DISTANCE:
		return origin + direction * BogCombat.MIN_AIM_DISTANCE
	return p


## The `faces` verdict, asked only on the open-ground leg, and routed by which
## phase of the leg's clock the tick belongs to.
##
## **Standing, inside the slack** — the body yaw is compared with the one it had
## before the view stepped, and any movement is a failure. This is the owner's
## complaint stated as a number: the feet are not allowed to leave the floor
## they are standing on because somebody looked at something.
##
## **Standing, past the edge** — what is compared is not the body against the
## view but the *gap* against `FACE_SLACK`. Asking "is the body 60 degrees off"
## rather than "is the body at 30 degrees" is the difference between checking
## the feature and checking this leg's arithmetic, and it stays true whichever
## way the view was stepped.
##
## **The move-start** — a stopwatch from the tick the key goes down to the tick
## the body is within `FACE_TOLERANCE` of the view. The *smoothness* half of
## that claim is not measured here but in `_drive_face`, one sample a physics
## tick, because a check running in `_process` cannot honestly say "no tick".
##
## **Running steps** — the old claim, unchanged: every step starts a stopwatch
## that stops when the body is within `FACE_TOLERANCE` of the view, and a step
## not matched inside `FACE_CATCHUP_TICKS` is a failure.
##
## **A commitment holding** — the body yaw is compared with the one it had when
## the hold began and any movement at all is a failure; the camera may turn
## through a whole half-circle and the body must not notice.
func _check_facing() -> void:
	var error := absf(angle_difference(_bog.body_yaw, _rig.yaw()))
	if _face_holding:
		_face_held_frames += 1
		var drift := absf(angle_difference(_bog.body_yaw, _face_held))
		_face_worst_drift = maxf(_face_worst_drift, drift)
		if drift > FACE_HOLD_TOLERANCE:
			_face_broke += 1
		return
	if _tick >= FACE_STAND_A and _tick < FACE_STAND_B:
		_face_stand_frames += 1
		var moved := absf(angle_difference(_bog.body_yaw, _face_stand_from))
		_face_worst_stand = maxf(_face_worst_stand, moved)
		if moved > FACE_TOLERANCE:
			_face_stand_broke += 1
		return
	if _tick >= FACE_STAND_B + FACE_EDGE_SETTLE and _tick < FACE_MOVE_AT:
		_face_edge_frames += 1
		var off_edge := absf(error - FACE_SLACK)
		_face_worst_edge = maxf(_face_worst_edge, off_edge)
		if off_edge > FACE_TOLERANCE:
			_face_edge_broke += 1
		return
	if _tick >= FACE_MOVE_AT and _tick < FACE_RUN_FROM:
		if _face_close_ticks < 0 and error <= FACE_TOLERANCE:
			_face_close_ticks = _tick - FACE_MOVE_AT
		return
	if _face_settled:
		return
	if error <= FACE_TOLERANCE:
		_face_settled = true
		_face_worst_catchup = maxi(_face_worst_catchup, _tick - _face_turned_at)
	elif _tick - _face_turned_at > FACE_CATCHUP_TICKS:
		# Out of budget. `_face_worst_error` is how far short the body was when
		# the stopwatch ran out, so a pass prints zero and a failure prints how
		# badly.
		_face_settled = true
		_face_slow += 1
		_face_worst_error = maxf(_face_worst_error, error)
		_face_worst_catchup = maxi(_face_worst_catchup, _tick - _face_turned_at)


func _report_leg() -> void:
	var leg: Dictionary = LEGS[_leg]
	print("camera_range: %-18s walked %4.1f m, camera as close as %.2f m; clipped %3d/%d frames (inside %d, near plane %d, behind a wall %d, worst %.2f m); aim off %d, worst %.3f m; off the line %d, worst %.4f m" % [
		leg["name"], _bog.global_position.distance_to(_leg_from), _leg_nearest,
		_leg_clipped, _leg_checked, _leg_inside, _leg_touching,
		_leg_behind, _leg_worst_behind, _leg_aim_off, _leg_worst_aim,
		_leg_off_line, _leg_worst_line])
	print("camera_range: %-18s over %d frames: pivot outran the body %d, lens adrift %d of %d loose frames, arm late out %d; %d pull-ins, worst %.3f m in a turned frame and %.3f m in a cut one, %d reversals" % [
		leg["name"], _leg_calm, _leg_drag, _leg_loose, _leg_free, _leg_late,
		_leg_pulls, _leg_worst_pull, _leg_worst_cut, _leg_flips])
	_total_checked += _leg_checked
	_total_clipped += _leg_clipped
	_total_aim_off += _leg_aim_off
	_total_off_line += _leg_off_line
	_total_calm += _leg_calm
	_total_drag += _leg_drag
	_total_free += _leg_free
	_total_loose += _leg_loose
	_total_late += _leg_late
	_total_pulls += _leg_pulls
	_total_flips += _leg_flips
	_worst_pull = maxf(_worst_pull, _leg_worst_pull)
	_worst_cut = maxf(_worst_cut, _leg_worst_cut)
	_worst_aim = maxf(_worst_aim, _leg_worst_aim)
	_worst_line = maxf(_worst_line, _leg_worst_line)


func _finish() -> void:
	_release_keys()
	var enough := _total_checked >= 1000
	if _total_clipped == 0 and enough:
		print("camera_range: camera inside the scenery on 0 of %d frames — clip PASS" % _total_checked)
	else:
		print("camera_range: camera inside the scenery on %d of %d frames — clip FAIL" % [
			_total_clipped, _total_checked])
	if _total_aim_off == 0 and enough:
		print("camera_range: the crosshair was the shot on all %d frames (worst %.4f m) — aim PASS" % [
			_total_checked, _worst_aim])
	else:
		print("camera_range: the shot was off the crosshair on %d of %d frames (worst %.3f m) — aim FAIL" % [
			_total_aim_off, _total_checked, _worst_aim])
	if _total_off_line == 0 and enough:
		print("camera_range: the lens stayed on the pivot-to-lens line on all %d frames (worst %.4f m) — frame PASS" % [
			_total_checked, _worst_line])
	else:
		print("camera_range: lens off the pivot-to-lens line on %d of %d frames (worst %.4f m) — frame FAIL" % [
			_total_off_line, _total_checked, _worst_line])

	var calm := _total_drag == 0 and _total_loose == 0 and _total_late == 0 \
		and enough and _total_calm >= 1000 and _total_free >= 100
	print("camera_range: over %d frames the pivot outran the body %d, the lens drifted on %d of %d loose frames, the arm went out over the eased cap %d; %d pull-ins, worst %.3f m in one turned frame (%.3f m across a cut), %d reversals — calm %s" % [
		_total_calm, _total_drag, _total_loose, _total_free, _total_late,
		_total_pulls, _worst_pull, _worst_cut, _total_flips,
		"PASS" if calm else "FAIL"])

	var closed := _face_close_ticks >= 0 and _face_close_ticks <= FACE_CLOSE_TICKS
	if not closed and _face_close_ticks < 0:
		_face_notes.append("the body never came back onto the view after the move")
	if _face_worst_step > _turn_cap:
		_face_notes.append("a single tick turned the body %.4f rad, over the %.4f cap"
			% [_face_worst_step, _turn_cap])
	print("camera_range: standing, a 45-degree look moved the body on %d of %d frames (worst %.3f deg); a 90-degree one left it on the %.1f-degree slack edge, off it on %d of %d frames (worst %.3f deg)" % [
		_face_stand_broke, _face_stand_frames, rad_to_deg(_face_worst_stand),
		rad_to_deg(FACE_SLACK), _face_edge_broke, _face_edge_frames,
		rad_to_deg(_face_worst_edge)])
	print("camera_range: on the first step of a walk the body gave the slack back in %d ticks of %d allowed, the biggest tick of that close %.4f rad; biggest tick anywhere on the leg %.4f rad against a %.4f cap" % [
		_face_close_ticks, FACE_CLOSE_TICKS, _face_close_step,
		_face_worst_step, _turn_cap])
	# `FACE_SLACK > FACE_TOLERANCE` is the leg refusing to be degenerate: the two
	# standing claims are both written against the Bog's own constant, so a
	# slack of zero would make the second of them read "the body is on the view"
	# and pass for the wrong reason. Only the first would catch it, and a
	# testbed that can pass a feature it has switched off is worth one line.
	var faced := _face_turns > 0 and _face_slow == 0 and _face_broke == 0 \
		and _face_spun and _face_emoted and _face_held_frames > 0 \
		and FACE_SLACK > FACE_TOLERANCE \
		and _face_stand_frames > 0 and _face_stand_broke == 0 \
		and _face_edge_frames > 0 and _face_edge_broke == 0 \
		and closed and _face_worst_step <= _turn_cap
	var note := "" if _face_notes.is_empty() else " (" + ", ".join(_face_notes) + ")"
	print("camera_range: the body matched the view on %d of %d turns within %d ticks (worst %d ticks, %.2f deg still out), held still through %d of %d standing frames and %d committed ones (worst drift %.3f deg), sat %d frames off the slack's edge, and gave the slack back in %d ticks%s — faces %s" % [
		_face_turns - _face_slow, _face_turns, FACE_CATCHUP_TICKS,
		_face_worst_catchup, rad_to_deg(_face_worst_error),
		_face_stand_frames - _face_stand_broke, _face_stand_frames,
		_face_held_frames, rad_to_deg(_face_worst_drift),
		_face_edge_broke, _face_close_ticks, note,
		"PASS" if faced else "FAIL"])
	get_tree().quit()


func _release_keys() -> void:
	Input.action_release("move_forward")


func _build_stage() -> void:
	for block: Array in BLOCKS:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.position = block[0]
		add_child(body)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = block[1]
		shape.shape = box
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = block[1]
		mesh.mesh = cube
		body.add_child(mesh)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -34, 0)
	add_child(key)
