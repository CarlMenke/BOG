extends Node3D
## Walks the player's own Gub into the places a third-person camera ends up
## inside the scenery, and counts the frames where it did (D-045).
## Development tool, not shipped. Headless, a couple of seconds.
##
##   Godot --headless --fixed-fps 60 --path . tools/camera_range.tscn
##
## A player: "too frequently the camera is inside meshes and stuff when there
## are meshes behind the character". A screenshot can show that once; it cannot
## say how often, and it cannot say it stopped. So this stands up five stations
## — a long wall on each shoulder, a corner, a tree canopy with a trunk, a wall at
## the Gub's back, and a low tunnel (the cave in PLAN 5.2) — and drives the view
## round each of them the way a mouse would, walking where walking is the point.
##
## After the rig has placed its camera, every frame, the camera is **inside the
## scenery** if any of these is true:
##   - a point query at the camera's origin finds collision (inside a solid);
##   - a sphere of `NEAR_CLEARANCE` there touches collision — the near plane is
##     0.05 m out and about 0.09 m to its corners, so a camera closer than this
##     to a face draws the inside of it;
##   - a ray from the Gub's eye to the camera hits collision — the camera is on
##     the far side of a wall, which is what a player actually sees as "inside".
##     The first two cannot see this against a thin face or a trimesh.
##
## The third verdict is the framing (D-059). A player: *"I slowly look right and
## for a bit once the camera makes contact with the wall it'll move left first"*.
## Nothing was inverted — the shoulder was being held at its full 0.62 m while the
## boom came in, so the lens swung round to the side of the Gub as it pulled in
## and the Gub slid across the frame, the same way whichever way the view was
## turning, which is backwards for half of all turns. The invariant that kills it
## is that the lens must never be further off the boom's axis than the
## unobstructed camera would be *at the depth it got to*: the shoulder is an angle
## and it comes in with the boom. It is an inequality, so a shoulder squeezed by a
## wall of its own is still allowed.
##
## The second verdict is the aim. Pulling a camera in must not move the spear
## (D-025): the throw is aimed down the crosshair's ray, and the crosshair has to
## mean the same thing whether or not a wall behind the Gub has shoved the lens
## forward. Each checked frame the point `GubCombat` would throw at is compared
## with the point worked out here, independently, from the *unobstructed* camera
## for the same view — the rig's own yaw and pitch at the full boom and shoulder.
## It reaches past the public API once, into `GubCombat._aim_point`, because that
## function is literally what a throw reads and a copy of it would prove nothing.

## World and camera blockers, which is what the rig is meant to avoid. Gubs,
## projectiles and pickups are deliberately not in it.
const WORLD_MASK := 1 | 64
## What `GubCombat` aims against.
const AIM_MASK := 1 | 2 | 8

const NEAR_CLEARANCE := 0.1
const AIM_TOLERANCE := 0.01
## How far past its share of the shoulder the lens may sit. A centimetre is float
## slack: the rig places the two from the same frame's sweep, so the real margin
## is zero. Nothing here holds the aim button, whose shoulder and boom ease on
## slightly different ratios and would need a wider one.
const FRAME_TOLERANCE := 0.01

## The fourth verdict, `calm`, is the *motion* of the lens rather than its place
## (D-062). `clip` says the camera is never in a wall and `frame` says the Gub
## does not walk across the picture; neither of them can see a camera that
## arrives somewhere correct by jumping, or one that hunts back and forth about a
## correct place. Those are the two named failure modes of every collision
## camera — "pop" and "swim" — and they are what is left once the placement is
## right, so they are measured directly.
##
## Three numbers, all read off the lens's own offset within the rig, so the
## Gub's walking and the player's turning are already subtracted out and what is
## left is only what the scenery did:
##
##   - **step**, metres the lens moved along boom-and-shoulder in one frame. A
##     pop is a big step. 0.09 m at 60 fps is 5.4 m/s of pure camera dolly,
##     which is faster than the Gub runs and is the point at which a pull-in
##     stops reading as a movement and starts reading as a cut. This one is a
##     budget rather than a zero, and honestly so: where the boom *grazes* a
##     surface — the view tipping down until the arm lies along the floor — the
##     length that fits is clearance over the sine of the angle, and the
##     derivative of that has no bound. At the graze there is no policy, only
##     geometry, and a camera that refused to move would be in the floor. So the
##     claim the gate makes is that it is rare: 4 % of frames, against the 14.9 %
##     measured before any of D-062.
##   - **flips**, frames where the boom reversed direction by more than a
##     millimetre having been moving the other way by more than a millimetre.
##     Swim is literally a high flip count: a camera that cannot decide. One
##     flip per pull-in is correct and unavoidable (in, then out); a budget of
##     4 % of frames leaves room for that across legs that make contact
##     constantly and still fails a camera that is oscillating.
##   - **turn**, degrees per frame of the *lens's own* rotation away from the
##     boom's axis. The rig aims the lens at where the aim ray meets the world so
##     the reticle stays honest (D-045), and that meeting point jumps the whole
##     length of the ray whenever the ray crosses an edge. 1.2 deg/frame is
##     72 deg/s, about a third of a fast mouse flick, and anything above it is
##     the picture snapping on its own.
const STEP_LIMIT := 0.09
const STEP_BUDGET := 0.04
const TURN_LIMIT := 1.2
const FLIP_BUDGET := 0.04
## Movement below this is float noise and a sign change in it means nothing.
const FLIP_EPSILON := 0.001
## Radians of view turned in one frame past which the frame is a *cut*, not a
## turn, and `calm` skips it. The "back to a wall" leg deliberately flicks 1.45
## rad between two frames, which no rig can lead and no player would read as
## camera movement — the whole picture changed. 0.15 rad is 9 degrees a frame,
## 540 deg/s, well above anything the sweeping legs produce (0.06 rad at their
## fastest) and well below a flick, so it separates the two cleanly.
const CUT_TURN := 0.15
## Ticks after a teleport before anything is checked: the rig eases after the
## body (`GubCamera.FOLLOW_SPEED`), so for a moment after a forty-metre jump it
## is legitimately flying through whatever lies between two stations.
const SETTLE_TICKS := 50

## Each leg puts the Gub on `spot` facing -Z and then runs `ticks` of `drive`.
const LEGS := [
	{"name": "wall on the right", "spot": Vector3(0.0, 0.1, 12.0), "ticks": 200, "drive": "wall"},
	{"name": "wall on the left", "spot": Vector3(2.4, 0.1, 12.0), "ticks": 200, "drive": "wall"},
	{"name": "corner", "spot": Vector3(40.0, 0.1, 0.0), "ticks": 260, "drive": "spin"},
	{"name": "under a canopy", "spot": Vector3(80.0, 0.1, 0.0), "ticks": 260, "drive": "canopy"},
	{"name": "canopy edge", "spot": Vector3(80.0, 0.1, 3.4), "ticks": 260, "drive": "canopy"},
	{"name": "back to a wall", "spot": Vector3(120.0, 0.1, 0.0), "ticks": 260, "drive": "turn"},
	{"name": "tunnel", "spot": Vector3(160.0, 0.1, 10.0), "ticks": 260, "drive": "tunnel"},
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
	# station 4: a wall at the Gub's back, face at z = 0.6
	[Vector3(120.0, 2.0, 0.9), Vector3(16.0, 4.0, 0.6)],
	# station 5: a tunnel along Z — walls at x = ±1.3, ceiling at 2.2
	[Vector3(158.4, 1.5, 0.0), Vector3(0.6, 3.0, 26.0)],
	[Vector3(161.6, 1.5, 0.0), Vector3(0.6, 3.0, 26.0)],
	[Vector3(160.0, 2.5, 0.0), Vector3(3.8, 0.6, 26.0)],
]

var _leg: int = -1
var _tick: int = 0
var _gub: Gub
var _rig: GubCamera
var _boom: Node3D
var _combat: GubCombat

var _leg_checked: int = 0
var _leg_clipped: int = 0
var _leg_inside: int = 0
var _leg_touching: int = 0
var _leg_behind: int = 0
var _leg_worst_behind: float = 0.0
var _leg_aim_off: int = 0
var _leg_worst_aim: float = 0.0
var _leg_wide: int = 0
var _leg_worst_wide: float = 0.0
var _leg_nearest: float = INF
var _leg_from: Vector3 = Vector3.ZERO
var _leg_jumped: int = 0
var _leg_worst_step: float = 0.0
var _leg_flips: int = 0
var _leg_snapped: int = 0
var _leg_worst_turn: float = 0.0

## Last frame's lens offset and lens-off-boom angle, and which way the boom was
## last seen moving. Cleared at every leg, because a teleport between stations is
## a legitimate jump and comparing across it would measure the teleport.
var _prev_lens: Vector3 = Vector3.ZERO
var _prev_dev: float = 0.0
var _prev_sign: int = 0
var _prev_yaw: float = 0.0
var _prev_pitch: float = 0.0
var _have_prev: bool = false
var _leg_calm: int = 0
var _total_calm: int = 0

var _total_checked: int = 0
var _total_clipped: int = 0
var _total_aim_off: int = 0
var _total_wide: int = 0
var _total_jumped: int = 0
var _total_flips: int = 0
var _total_snapped: int = 0
var _worst_step: float = 0.0
var _worst_turn: float = 0.0


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

	_gub = MatchState.gubs.get(1) as Gub
	if _gub == null:
		print("camera_range: no local Gub was spawned — clip FAIL")
		get_tree().quit()
		return
	_rig = _gub.get_node("CameraRig") as GubCamera
	_boom = _rig.get_node("Boom") as Node3D
	_combat = _gub.get_node("Combat") as GubCombat
	print("camera_range: starting, %d legs" % LEGS.size())
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
	_leg_wide = 0
	_leg_worst_wide = 0.0
	_leg_nearest = INF
	_leg_jumped = 0
	_leg_worst_step = 0.0
	_leg_flips = 0
	_leg_snapped = 0
	_leg_worst_turn = 0.0
	_leg_calm = 0
	_have_prev = false
	_prev_sign = 0
	if _leg >= LEGS.size():
		_finish()
		return
	_gub.revive_at(Transform3D(Basis.IDENTITY, LEGS[_leg]["spot"]))


func _physics_process(_delta: float) -> void:
	if _gub == null or _leg < 0 or _leg >= LEGS.size():
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
			# Swing round through the wall at the Gub's back, then flick.
			if t < 140:
				yaw = 3.2 * sin(t * 0.045)
			else:
				yaw = 1.45 * floorf((t - 140) / 15.0)
			pitch = -0.2 + 0.7 * sin(t * 0.05)
		"tunnel":
			forward = t > 0
			yaw = 1.1 * sin(t * 0.04)
			pitch = -0.12 + 0.65 * sin(t * 0.07)
	_rig.set_view(yaw, pitch)
	if forward:
		Input.action_press("move_forward")
	else:
		Input.action_release("move_forward")


func _process(_delta: float) -> void:
	if _gub == null or _leg < 0 or _leg >= LEGS.size() or _tick <= 0:
		return
	_check_frame()


func _check_frame() -> void:
	var space := get_world_3d().direct_space_state
	var cam := _rig.camera().global_position
	var eye := _gub.global_position + Vector3.UP * _gub.eye_height()
	if _leg_checked == 0:
		_leg_from = _gub.global_position
	_leg_checked += 1
	# How far the scenery shoved the lens in, so a leg that never pushed the
	# camera at all is visible as one rather than passing quietly.
	_leg_nearest = minf(_leg_nearest, cam.distance_to(_rig.global_position))

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

	var ray := PhysicsRayQueryParameters3D.create(eye, cam, WORLD_MASK)
	var hit := space.intersect_ray(ray)
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

	var aim_error := _combat._aim_point().distance_to(_unobstructed_aim_point(space))
	if aim_error > AIM_TOLERANCE:
		_leg_aim_off += 1
	_leg_worst_aim = maxf(_leg_worst_aim, aim_error)

	# The lens's own offsets, read off the node the rig placed: how far it sits to
	# the side, and how far back it got. A lens further to the side than its share
	# of the boom is a Gub sliding across the frame (D-059).
	var lens := _rig.camera().position
	var share := GubCamera.SHOULDER_DEFAULT * lens.z / GubCamera.DISTANCE_DEFAULT
	if lens.x - share > FRAME_TOLERANCE:
		_leg_wide += 1
	_leg_worst_wide = maxf(_leg_worst_wide, lens.x - share)

	# Pop and swim (D-062). `lens` is boom-space, so the Gub's walking and the
	# player's turning are already out of it and every millimetre here was put
	# there by the scenery. The lens's own rotation is measured as its angle off
	# the boom's axis, for the same reason: turning the view turns the boom too,
	# so what is left is only the reticle correction swinging the picture.
	var dev := rad_to_deg((-_rig.camera().global_transform.basis.z).angle_to(
		-_boom.global_transform.basis.z))
	var cut := absf(_rig.yaw() - _prev_yaw) + absf(_rig.pitch() - _prev_pitch) > CUT_TURN
	if _have_prev and not cut:
		_leg_calm += 1
		var step := lens.distance_to(_prev_lens)
		_leg_worst_step = maxf(_leg_worst_step, step)
		if step > STEP_LIMIT:
			_leg_jumped += 1
		var turn := absf(dev - _prev_dev)
		_leg_worst_turn = maxf(_leg_worst_turn, turn)
		if turn > TURN_LIMIT:
			_leg_snapped += 1
		var move := lens.z - _prev_lens.z
		var sign_now := 0
		if move > FLIP_EPSILON:
			sign_now = 1
		elif move < -FLIP_EPSILON:
			sign_now = -1
		if sign_now != 0:
			if _prev_sign != 0 and sign_now != _prev_sign:
				_leg_flips += 1
			_prev_sign = sign_now
	_prev_lens = lens
	_prev_dev = dev
	_prev_yaw = _rig.yaw()
	_prev_pitch = _rig.pitch()
	# A cut breaks the chain on both sides: the frame that lands on the new view
	# is not compared with the old one, and its direction of travel is not carried
	# across either, so a flick cannot be scored as a flip.
	_have_prev = not cut
	if cut:
		_prev_sign = 0


## Where a throw should go for this view, worked out from the camera the rig
## would have with nothing in the way: the rig's pivot, its yaw and pitch, the
## full boom and the full shoulder. The ray is only tested from the Gub's own
## depth outwards — nothing behind the thrower is something it can throw at, and
## this is the same rule the rig promises (`GubCamera.aim_ray`).
func _unobstructed_aim_point(space: PhysicsDirectSpaceState3D) -> Vector3:
	var basis := Basis(Vector3.UP, _rig.yaw()) * Basis(Vector3.RIGHT, _rig.pitch())
	var origin := _rig.global_position \
		+ basis * Vector3(GubCamera.SHOULDER_DEFAULT, 0.0, GubCamera.DISTANCE_DEFAULT)
	var direction := -basis.z
	var from := origin + direction * GubCamera.DISTANCE_DEFAULT
	var query := PhysicsRayQueryParameters3D.create(
		from, origin + direction * GubCombat.MAX_AIM_DISTANCE, AIM_MASK)
	query.exclude = [_gub.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return origin + direction * GubCombat.MAX_AIM_DISTANCE
	var p: Vector3 = hit["position"]
	if origin.distance_to(p) < GubCombat.MIN_AIM_DISTANCE:
		return origin + direction * GubCombat.MIN_AIM_DISTANCE
	return p


func _report_leg() -> void:
	var leg: Dictionary = LEGS[_leg]
	print("camera_range: %-18s walked %4.1f m, camera as close as %.2f m; clipped %3d/%d frames (inside %d, near plane %d, behind a wall %d, worst %.2f m); aim off %d, worst %.3f m; lens wide %d, worst %.3f m" % [
		leg["name"], _gub.global_position.distance_to(_leg_from), _leg_nearest,
		_leg_clipped, _leg_checked, _leg_inside, _leg_touching,
		_leg_behind, _leg_worst_behind, _leg_aim_off, _leg_worst_aim,
		_leg_wide, _leg_worst_wide])
	print("camera_range: %-18s over %d unbroken frames: lens step worst %.3f m (%d over), flips %3d, lens turn worst %.2f deg (%d over)" % [
		leg["name"], _leg_calm, _leg_worst_step, _leg_jumped, _leg_flips,
		_leg_worst_turn, _leg_snapped])
	_total_checked += _leg_checked
	_total_clipped += _leg_clipped
	_total_aim_off += _leg_aim_off
	_total_wide += _leg_wide
	_total_jumped += _leg_jumped
	_total_flips += _leg_flips
	_total_snapped += _leg_snapped
	_total_calm += _leg_calm
	_worst_step = maxf(_worst_step, _leg_worst_step)
	_worst_turn = maxf(_worst_turn, _leg_worst_turn)


func _finish() -> void:
	_release_keys()
	var enough := _total_checked >= 1000
	if _total_clipped == 0 and enough:
		print("camera_range: camera inside the scenery on 0 of %d frames — clip PASS" % _total_checked)
	else:
		print("camera_range: camera inside the scenery on %d of %d frames — clip FAIL" % [
			_total_clipped, _total_checked])
	if _total_aim_off == 0 and enough:
		print("camera_range: aim matched the unobstructed camera on all %d frames — aim PASS" % _total_checked)
	else:
		print("camera_range: aim off the unobstructed camera on %d of %d frames — aim FAIL" % [
			_total_aim_off, _total_checked])
	if _total_wide == 0 and enough:
		print("camera_range: the shoulder came in with the boom on all %d frames — frame PASS" % _total_checked)
	else:
		print("camera_range: lens wider than its share of the shoulder on %d of %d frames — frame FAIL" % [
			_total_wide, _total_checked])

	var flip_allowance := int(_total_calm * FLIP_BUDGET)
	var step_allowance := int(_total_calm * STEP_BUDGET)
	var calm := _total_jumped <= step_allowance and _total_snapped == 0 \
		and _total_flips <= flip_allowance and enough and _total_calm >= 1000
	print("camera_range: over %d frames the view was turned rather than cut: lens step over %.2f m on %d (budget %d, worst %.3f m); boom flips %d (budget %d); lens turn over %.2f deg on %d (worst %.2f deg) — calm %s" % [
		_total_calm, STEP_LIMIT, _total_jumped, step_allowance, _worst_step,
		_total_flips, flip_allowance,
		TURN_LIMIT, _total_snapped, _worst_turn,
		"PASS" if calm else "FAIL"])
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
