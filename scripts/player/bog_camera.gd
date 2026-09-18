class_name BogCamera
extends Node3D
## Third-person camera rig. Lives under a `Bog`, and only wakes up for the Bog
## the local player owns.
##
## Structure: this node yaws, the `Boom` under it pitches, and the `Camera3D`
## sits at the end of the boom and off to one side so the Bog does not cover the
## crosshair. When scenery gets between the Bog and where the camera wants to be,
## the camera is pulled in along that same path — see `_place_camera` (D-045).
##
## The rig follows the body's *position* but never its rotation — the body's
## facing is a consequence of where you are moving, not of where you are
## looking, so binding the two together would make the camera lurch every time
## the Bog turned to run somewhere.
##
## While the owner is dead it can follow somebody else instead (PLAN 6.5). That
## is deliberately a change of *subject* rather than a second camera: the spring
## arm, the collision mask, the mouse look and the shake are all already solved
## here, and a separate spectator rig would have to solve them again and then
## drift out of step with this one. A dead Bog's node is only hidden, never
## freed, so its rig is still alive and still holds the viewport — pointing it at
## a living Bog is the whole of the feature.

const PITCH_MIN := -1.20   # ~-69 degrees, looking down
const PITCH_MAX := 0.95    # ~54 degrees, looking up

## How far back the lens sits, and how far back it sits with a bow up. Both came
## in half a metre in the feel round: at 3.6 m the Bog was a figure in a
## landscape and the thing the player is actually aiming — the shoulder and the
## weapon in front of it — was small enough that a fight read as two dots
## meeting. The shoulders are unchanged, so the Bog keeps the same share of the
## frame off the crosshair while the world behind it gets closer.
const DISTANCE_DEFAULT := 3.1
const DISTANCE_AIMING := 2.15
const SHOULDER_DEFAULT := 0.62
const SHOULDER_AIMING := 0.48
const FOV_AIM_SCALE := 0.82

## The rig eases toward the Bog instead of being glued to it, so single-frame
## physics corrections (a step, a slide along a wall) do not jolt the view.
const FOLLOW_SPEED := 22.0
const ZOOM_SPEED := 8.0

## Radians per pixel at a sensitivity setting of 1.0.
const SENSITIVITY_SCALE := 0.0022

## Camera collision (D-045). The camera is swept to where it wants to be as a
## sphere rather than a ray, along the path the camera itself travels: back along
## the boom, then out to the shoulder at whatever depth the boom got to (D-083).
## A ray down the middle of the boom, which is what the `SpringArm3D` here used
## to cast, tested a line the camera was never on — 0.62 m to one side of it.
##
## The world and anything marked as a camera blocker, never players: clipping to
## a team-mate standing behind you is worse than seeing through them.
const COLLISION_MASK := 1 | 64
## Wide enough that the near plane (0.05 m out, about 0.09 m to its corners) is
## nowhere near a face when the sphere is only just clear of it.
const PROBE_RADIUS := 0.26
## Held back from the first hit on top of the radius, so a camera resting
## against a wall is not re-touching it on float noise every frame.
const PROBE_MARGIN := 0.05

## The three rates, and why there are three (D-086).
##
## Every mature third-person rig splits the speed the camera comes *in* from the
## speed it goes back *out*, and the good ones have a third number that is
## neither: Cinemachine's `CinemachineDeoccluder` carries `DampingWhenOccluded`,
## `Damping` and `SmoothingTime` — "nearest camera point is held for at least
## this long" — and Unreal's `USpringArmComponent` carries none of them, which is
## why its collision is famous for popping. This rig had two of the three: in was
## instant, out was `RETURN_RATE`. Instant is not a fast damping, it is the
## absence of one, and it measured as a 3.08 m move of the lens inside one frame.
##
## `PULL_SPEED` is a speed rather than an exponential because the thing being
## bounded is metres per frame: an exponential's first frame is its biggest, so
## it is the wrong shape for a limit. 4 m/s is a little faster than a Bog runs,
## which is the fastest a dolly can move and still read as a move.
## A proportional term underneath it — pull faster the further there is to go,
## which is what damping would do — was tried and put back: it takes the frames
## over the limit from 37 to 75 without moving the worst one at all. Front-loading
## a correction spends its whole budget in the first frame or two, and the
## corrections it front-loads are the ones the clamp was going to force anyway.
## A flat speed is the right shape for a limit precisely because it is flat.
const PULL_SPEED := 4.0
## Going out is an exponential, because it should decelerate into place rather
## than arrive at speed and stop, but it is capped at a speed for the same reason
## `PULL_SPEED` is one — 3.1 m of exponential at `RETURN_RATE` starts at 13 m/s.
const RETURN_RATE := 5.0
const RETURN_SPEED := 3.0
## Cinemachine's `SmoothingTime`. After any pull-in the camera holds where it got
## to for this long before it is allowed to start back out. It is not about
## smoothness in the frame; it is about a row of tree trunks, a picket fence, a
## doorframe — scenery that crosses the boom repeatedly over a second. Without a
## hold, each one is a full in-and-out cycle and the camera hunts. With it, they
## are one pull-in.
const HOLD_TIME := 0.25

## The camera is swept where the view is *going*, not only where it is (D-086).
## A wall arriving behind the Bog is arriving at a known rate — the rate the
## player is turning — so it can be seen 0.14 s early and the boom can start
## shortening before it has to. This is the only thing that actually removes a
## pop rather than smoothing one: on a swing into a wall the camera is already
## short by the time the wall is there, so there is nothing left to hurry. The
## lead result is only ever taken as a *minimum* against the honest sweep, so a
## wrong prediction can shorten the boom early but can never lengthen it late.
const LOOKAHEAD := 0.14
## A view that jumps — a respawn, a testbed `set_view`, a spectator handover — is
## not a turn and cannot be extrapolated: there is no rate, only a discontinuity,
## and reading one as the other throws the lead half a turn away and pulls the
## camera in hard for scenery nobody is looking at. Anything past this much view
## in one frame (9 degrees, 540 deg/s) is taken as a cut and leads nowhere.
const LEAD_CUT := 0.15
## And a sustained spin is still capped, so the lead stays a prediction about the
## next sixth of a second rather than a survey of the room.
const LEAD_LIMIT := 0.5
## The rate is read from one frame's mouse movement, which is a noisy thing to
## steer a camera with — a mouse delivers its motion in bursts and the raw
## frame-to-frame rate doubles and halves inside a single smooth drag. Smoothing
## it costs a couple of frames of warning and buys a lead that does not flutter.
const LEAD_SMOOTHING := 0.25
## The lead sweep is also *fatter* than the real one, which is the old two-sphere
## trick: a small sphere that decides where the camera may be and a larger one
## that decides when it should start moving.
##
## How much fatter is not a taste setting. Sweeping at the led direction tests
## one line out of the fan the camera is about to travel through, and the rest of
## that fan — everything between here and there — is untested. Swelling the
## sphere by half the arc the lens will cover in `LOOKAHEAD` makes the one sweep
## a conservative cover of the whole fan instead. So it is zero when the player is
## still, which matters: a constant swell would have the camera sitting closer
## than it needs to for ever, and that is a worse thing to feel than the pop it
## was bought to remove. It also gets the case angular lead cannot — tip the view
## down and the boom grazes the ground, where the length that fits is clearance
## over the sine of the pitch, a curve so steep near the graze that a tenth of a
## radian of lead sees nothing and then everything. A wider sphere crosses that
## knee earlier for the same view.
##
## Capped twice. Once absolutely, at the probe's own radius, because on a
## full-speed spin half the arc is metres and a sphere that big would find the
## whole room. And once in proportion to the boom that is left, because early
## warning is only worth anything while there is somewhere to retreat to: a
## camera 0.3 m off the pivot with its back to a wall has no room to give, and
## taking another 0.26 m off it for a warning puts the lens inside the Bog's own
## head to avoid a wall it is already clear of. Measured: without the
## proportional cap the "back to a wall" leg drove the lens to 0.04 m of the
## pivot, against 0.28 m before any of this.
const LEAD_SWELL_CAP := PROBE_RADIUS
const LEAD_SWELL_SHARE := 0.3

## How fast the lens may turn on its own, away from the boom's axis, to keep the
## reticle over what the aim ray hits (D-045). That meeting point is a raycast,
## and a raycast across the edge of a wall jumps from two metres to sixty in one
## frame; the lens chasing it snapped the picture by up to 13.8 degrees in a
## frame, 830 deg/s, with nobody touching the mouse. Capping the rate is what
## Unreal calls `CameraRotationLagSpeed` and is the same idea: the correction is
## cosmetic, so it is allowed to arrive late. 60 deg/s crosses the whole
## correction in about a third of a second.
const TURN_RATE := 1.047  # 60 degrees per second

@onready var _boom: Node3D = $Boom
@onready var _camera: Camera3D = $Boom/Camera3D

var _body: Bog
var _yaw: float = 0.0
var _pitch: float = -0.12
var _distance: float = DISTANCE_DEFAULT
var _shoulder: float = SHOULDER_DEFAULT
## How much of the boom the scenery currently allows, in metres, and how much of
## the shoulder it allows at that depth, as a fraction. The camera sits at these,
## and they only ever lag behind the scenery outwards. The shoulder is a fraction
## rather than a length because the length it is a fraction *of* shrinks with the
## boom (D-083), and easing a number whose scale is moving under it would put the
## drift back in that this was written to take out.
var _boom_clear: float = DISTANCE_DEFAULT
var _shoulder_room: float = 1.0
## Seconds left on each channel's hold (`HOLD_TIME`), and the view from last
## frame, which is all the lead needs to know how fast the player is turning.
var _boom_hold: float = 0.0
var _shoulder_hold: float = 0.0
var _last_yaw: float = 0.0
var _last_pitch: float = -0.12
var _yaw_rate: float = 0.0
var _pitch_rate: float = 0.0
## Where the lens is pointing, in the boom's own space, so the reticle correction
## can be rate-limited rather than snapped. -Z is straight down the boom.
var _lens_dir: Vector3 = Vector3(0.0, 0.0, -1.0)
var _probe := PhysicsShapeQueryParameters3D.new()
var _probe_wide := PhysicsShapeQueryParameters3D.new()
var _wide_shape := SphereShape3D.new()
## Radians of view the lead covers this frame, and so how far the lens will swing
## through in `LOOKAHEAD`, which is what the wide probe is sized from.
var _lead_arc: float = 0.0
var _base_fov: float = 75.0
var _shake_strength: float = 0.0
var _shake_decay: float = 6.0
var _aiming: bool = false
## Whose shoulder we are watching over while dead. Null means our own Bog.
var _spectating: Bog = null


func _ready() -> void:
	_body = get_parent() as Bog
	if _body == null:
		push_error("BogCamera expects to be a child of a Bog")
		return

	if not _body.is_local():
		# A remote Bog still carries a rig (it is part of the scene), but it must
		# not steal the viewport or read the mouse.
		set_process(false)
		set_process_unhandled_input(false)
		_camera.current = false
		return

	_base_fov = float(Settings.get_value("fov"))
	_camera.current = true
	var sphere := SphereShape3D.new()
	sphere.radius = PROBE_RADIUS
	_probe.shape = sphere
	_probe.collision_mask = COLLISION_MASK
	_wide_shape.radius = PROBE_RADIUS
	_probe_wide.shape = _wide_shape
	_probe_wide.collision_mask = COLLISION_MASK
	Settings.changed.connect(_on_setting_changed)


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "fov":
		_base_fov = float(value)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	if SceneFlow.cursor_is_free():
		return
	var motion := event as InputEventMouseMotion
	var sensitivity := float(Settings.get_value("mouse_sensitivity")) * SENSITIVITY_SCALE
	if _aiming:
		# Aiming narrows the field of view; without matching the sensitivity to
		# it, the same hand movement would sweep further across the world.
		sensitivity *= FOV_AIM_SCALE
	_yaw -= motion.relative.x * sensitivity
	var pitch_delta := motion.relative.y * sensitivity
	if bool(Settings.get_value("invert_y")):
		pitch_delta = -pitch_delta
	_pitch = clampf(_pitch - pitch_delta, PITCH_MIN, PITCH_MAX)


func _process(delta: float) -> void:
	if _body == null:
		return

	_aiming = Input.is_action_pressed("aim") and _body.alive and _spectating == null
	_follow(delta)
	_apply_zoom(delta)
	_apply_shake(delta)

	rotation.y = _yaw
	_boom.rotation.x = _pitch
	_place_camera(delta)

	# Hand the body a view basis so WASD is relative to where you are looking,
	# and tell it to face the camera while aiming so a throw goes to the
	# crosshair rather than to wherever the Bog happened to be running.
	# Not while spectating: the corpse is not ours to steer, and turning the view
	# would spin a body somebody else is still watching.
	if _spectating == null:
		_body.set_view_basis(global_transform.basis,
			_aiming or _body_is_throwing(), _pitch)


func _body_is_throwing() -> bool:
	var animator := _body.get_node_or_null("AnimationTree") as BogAnimator
	return animator != null and animator.is_throwing()


## The Bog the rig is currently framing — the one we are spectating if that Bog
## is still around, and our own otherwise. A spectated Bog can be freed out from
## under us (they leave, the match resets), so this is checked every frame rather
## than trusted once.
func _subject() -> Bog:
	if _spectating != null and is_instance_valid(_spectating):
		return _spectating
	return _body


## Watch `target` instead of our own Bog. Pass null to go back to our own.
func spectate(target: Bog) -> void:
	_spectating = target if target != _body else null


func spectating() -> Bog:
	return _spectating if is_instance_valid(_spectating) else null


func _follow(delta: float) -> void:
	var subject := _subject()
	var target := subject.global_position + Vector3.UP * subject.eye_height()
	# Vertical follow is slower than horizontal: stairs and small bumps should
	# not pump the camera up and down.
	var next := global_position
	next.x = lerpf(next.x, target.x, clampf(FOLLOW_SPEED * delta, 0.0, 1.0))
	next.z = lerpf(next.z, target.z, clampf(FOLLOW_SPEED * delta, 0.0, 1.0))
	next.y = lerpf(next.y, target.y, clampf(FOLLOW_SPEED * 0.55 * delta, 0.0, 1.0))
	global_position = next


func _apply_zoom(delta: float) -> void:
	var want_distance := DISTANCE_AIMING if _aiming else DISTANCE_DEFAULT
	var want_shoulder := SHOULDER_AIMING if _aiming else SHOULDER_DEFAULT
	var want_fov := _base_fov * (FOV_AIM_SCALE if _aiming else 1.0)

	var t := clampf(ZOOM_SPEED * delta, 0.0, 1.0)
	_distance = lerpf(_distance, want_distance, t)
	_shoulder = lerpf(_shoulder, want_shoulder, t)
	_camera.fov = lerpf(_camera.fov, want_fov, t)


## Put the camera as far out along boom-then-shoulder as the scenery allows.
##
## Two channels — how much boom, and how much shoulder at that depth — and each
## is swept twice: once at the view as it is, which is a hard limit, and once at
## the view as it will be in `LOOKAHEAD` seconds, which is only ever allowed to
## ask for less. Both run every frame after the view has turned, so a camera
## swung round into a wall is dealt with on the frame it would have gone in
## rather than on the next physics tick. Ceilings and canopies are the same
## sweep: looking down lifts the boom into them like any wall.
##
## Each channel then *approaches* what it was asked for rather than jumping to it
## (D-086): in at a speed, out on a held, capped exponential, and clamped every
## frame to what the honest sweep says is clear. The clamp is what makes the
## slowness free — the camera cannot be a frame late into a wall no matter how
## gentle the easing is, because the easing never gets the last word.
##
## The shoulder is an angle, not a length (D-083). It is there to keep the Bog
## off the crosshair, and a lens half as far back needs half as much of it to do
## that — so it is scaled by how much of the boom survived. Held at its full
## 0.62 m while the boom came in, it swung the picture sideways: the Bog slid
## most of a screen width across the view as the camera touched a wall, always
## the same way whichever way the player was turning, so half of all turns looked
## briefly inverted.
##
## Only the lens moves. The aim is taken from the unobstructed camera
## (`aim_ray`), so where a spear goes does not depend on any of this.
func _place_camera(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var basis := _boom.global_transform.basis
	var pivot := global_position
	var lead := _lead_basis(basis, delta)
	_wide_shape.radius = PROBE_RADIUS + minf(0.5 * _distance * _lead_arc,
		minf(LEAD_SWELL_CAP, LEAD_SWELL_SHARE * _boom_clear))
	# Turning is not the only way the camera meets a wall — walking into a corner
	# brings one in at running speed with the view perfectly still. The pivot is
	# led by the body's own velocity for the same `LOOKAHEAD`, from the subject
	# rather than from the rig, because the rig is still easing after the body
	# (`FOLLOW_SPEED`) and its own motion is a frame or two stale.
	var lead_pivot := pivot + _subject().velocity * LOOKAHEAD

	# Two sweeps per channel: `hard` is where the lens may be *this* frame and is
	# never negotiable, `want` folds in the lead and is therefore never longer.
	# The approach is then free to be slow, because it is clamped to `hard`.
	var boom_hard := _distance * _sweep(space, pivot, basis.z * _distance)
	var boom_want := minf(boom_hard,
		_distance * _sweep(space, lead_pivot, lead.z * _distance, true))
	var boom := _approach(_boom_clear, boom_want, boom_hard, _boom_hold, delta,
		PULL_SPEED, RETURN_SPEED)
	_boom_clear = boom.x
	_boom_hold = boom.y

	# Out to the shoulder from where the boom got to, rather than from the pivot,
	# because that is the depth the lens is actually at: a sweep taken at the
	# Bog's head is a test of the scenery 3.1 m from the thing it is placing.
	var shoulder := _shoulder * _boom_clear / maxf(_distance, 0.001)
	var boom_point := pivot + basis.z * _boom_clear
	# The shoulder is carried as a fraction (D-083), so its speeds have to be
	# converted out of metres into fractions-of-a-shoulder per second. Below a few
	# centimetres of shoulder there is nothing left worth rate-limiting and the
	# division would only make the limit enormous, so the scale floors out.
	var per_metre := 1.0 / maxf(shoulder, 0.05)
	var room_hard := _sweep(space, boom_point, basis.x * shoulder)
	var room_want := minf(room_hard, _sweep(space,
		boom_point + (lead_pivot - pivot), lead.x * shoulder, true))
	var room := _approach(_shoulder_room, room_want, room_hard, _shoulder_hold, delta,
		PULL_SPEED * per_metre, RETURN_SPEED * per_metre)
	_shoulder_room = room.x
	_shoulder_hold = room.y
	var shoulder_now := shoulder * _shoulder_room

	var lens := Vector3(shoulder_now, 0.0, _boom_clear)
	# With the shoulder short of where the view says it should be — squeezed by a
	# wall, or scaled down with the boom — the lens is off the aim ray, and a
	# crosshair at the centre of the screen would sit a parallel shoulder's width
	# from where the spear goes. Turn the lens in to meet the aim ray where the
	# aim ray meets the world, so the reticle stays on the thing being aimed at.
	#
	# All of this is done in the boom's own space so that the player's own turning
	# is not in it: what is left is the correction alone, and it is the correction
	# alone that gets the rate limit (D-086). Aiming the lens at a world point
	# directly, as this used to, meant slerping against a frame that was itself
	# rotating and there was no honest way to say how fast the *correction* moved.
	var want_dir := Vector3(0.0, 0.0, -1.0)
	if _shoulder - shoulder_now > 0.001:
		var ray := aim_ray()
		var origin: Vector3 = ray["origin"]
		var direction: Vector3 = ray["direction"]
		var far := origin + direction * 60.0
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			origin + direction * float(ray["clear_of"]), far, COLLISION_MASK))
		var meet: Vector3 = far if hit.is_empty() else hit["position"]
		var to_meet := _boom.global_transform.affine_inverse() * meet - lens
		if to_meet.length_squared() > 0.01:
			want_dir = to_meet.normalized()
	var turn := TURN_RATE * delta
	var off := _lens_dir.angle_to(want_dir)
	_lens_dir = want_dir if off <= turn else _lens_dir.slerp(want_dir, turn / off)
	_camera.transform = Transform3D(Basis.looking_at(_lens_dir, Vector3.UP), lens)


## The boom's basis as it will be in `LOOKAHEAD` seconds if the player keeps
## turning at the rate they are turning now (D-086).
func _lead_basis(basis: Basis, delta: float) -> Basis:
	var step := maxf(delta, 0.0001)
	var moved_yaw := _yaw - _last_yaw
	var moved_pitch := _pitch - _last_pitch
	_last_yaw = _yaw
	_last_pitch = _pitch
	if absf(moved_yaw) + absf(moved_pitch) > LEAD_CUT:
		moved_yaw = 0.0
		moved_pitch = 0.0
	_yaw_rate = lerpf(_yaw_rate, moved_yaw / step, LEAD_SMOOTHING)
	_pitch_rate = lerpf(_pitch_rate, moved_pitch / step, LEAD_SMOOTHING)
	var lead_yaw := clampf(_yaw_rate * LOOKAHEAD, -LEAD_LIMIT, LEAD_LIMIT)
	var lead_pitch := clampf(_pitch_rate * LOOKAHEAD, -LEAD_LIMIT, LEAD_LIMIT)
	_lead_arc = absf(lead_yaw) + absf(lead_pitch)
	# Built off the live basis rather than from yaw and pitch, so this stays right
	# whatever the rig's parent is doing to it. Yaw is about the world's up, which
	# is the axis the rig turns on; pitch is about the leaned basis's own X, which
	# is the axis the boom turns on.
	var leaned := Basis(Vector3.UP, lead_yaw) * basis
	return leaned.rotated(leaned.x.normalized(), lead_pitch)


## Move one channel a frame's worth towards `want`, and return the new value and
## what is left of its hold.
##
## The shape of this is the whole of D-086. Coming in is rate-limited but then
## clamped to `hard`, so the limit buys smoothness on everything the lead saw
## coming and gives it straight back when it did not — the camera is never in a
## wall for a frame in exchange for being gentle. Going out is an exponential,
## capped at a speed, and does not start until the hold has run out.
func _approach(current: float, want: float, hard: float, hold: float, delta: float,
		pull_speed: float, return_speed: float) -> Vector2:
	var next := current
	if want < current:
		next = maxf(want, current - pull_speed * delta)
		hold = HOLD_TIME
	else:
		hold = maxf(0.0, hold - delta)
		if hold <= 0.0:
			var eased := lerpf(current, want, 1.0 - exp(-RETURN_RATE * delta))
			next = minf(eased, current + return_speed * delta)
	# Last word, always: whatever the easing wanted, the scenery decides.
	return Vector2(minf(next, hard), hold)


## The fraction of `motion` from `from` a camera can travel and stay at least
## `PROBE_RADIUS + PROBE_MARGIN` clear of the scenery.
##
## If the sphere cannot travel at all (a head right up under a low ceiling) that
## segment falls back to a ray, which is what the old spring arm did everywhere,
## rather than collapsing the camera into the Bog's skull.
##
## That fallback used to be conditional on `intersect_shape` also reporting an
## overlap at the start, and it is not any more (D-086). `cast_motion` returns a
## safe fraction of zero both when the sphere is genuinely wedged and when it is
## merely inside the solver's own contact margin while still technically clear —
## and only the first of those satisfied `intersect_shape`. So a sphere sitting a
## hair off a wall could flip between the ray's answer and a hard zero on float
## noise from frame to frame: a boom snapping to nothing and back with nobody
## moving. That is the "swim" every writeup of this warns about, and it came from
## having two disagreeing answers for one situation rather than from any easing.
## One answer now, and it is the conservative one.
func _sweep(space: PhysicsDirectSpaceState3D, from: Vector3, motion: Vector3,
		wide: bool = false) -> float:
	var length := motion.length()
	if length < 0.001:
		return 1.0
	var probe := _probe_wide if wide else _probe
	var radius := _wide_shape.radius if wide else PROBE_RADIUS
	probe.transform = Transform3D(Basis.IDENTITY, from)
	probe.motion = motion
	var safe: float = space.cast_motion(probe)[0]
	if safe >= 1.0:
		return 1.0
	if safe <= 0.0:
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, from + motion, COLLISION_MASK))
		if hit.is_empty():
			return 1.0
		var reach := from.distance_to(hit["position"]) - radius - PROBE_MARGIN
		return clampf(reach / length, 0.0, 1.0)
	return clampf((safe * length - PROBE_MARGIN) / length, 0.0, 1.0)


## Called on kills, hard landings and nearby impacts.
func shake(strength: float, decay: float = 6.0) -> void:
	_shake_strength = maxf(_shake_strength, strength * float(Settings.get_value("camera_shake")))
	_shake_decay = decay


func _apply_shake(delta: float) -> void:
	if _shake_strength <= 0.0001:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		return
	_shake_strength = maxf(0.0, _shake_strength - _shake_decay * _shake_strength * delta)
	_camera.h_offset = randf_range(-1.0, 1.0) * _shake_strength * 0.06
	_camera.v_offset = randf_range(-1.0, 1.0) * _shake_strength * 0.06


## World-space ray the crosshair is pointing down. Everything the player throws
## is aimed with this, so the spear goes where the reticle is rather than where
## the Bog's hand happens to be.
##
## Taken from where the camera *would* be with nothing in the way — the full boom
## and shoulder for this view — never from the lens `_place_camera` has pulled
## in (D-045), because a wall behind the Bog must not move a spear (D-025).
## `clear_of` is how far along the ray the Bog itself is. Anything nearer is
## behind the thrower, so aiming skips it; without that, the wall that pushed
## the camera forward would be the thing the throw aimed at.
func aim_ray() -> Dictionary:
	var basis := _boom.global_transform.basis
	var origin := global_position + basis * Vector3(_shoulder, 0.0, _distance)
	# Shake moves the picture, and the crosshair with it, so it moves the ray.
	origin += basis.x * _camera.h_offset + basis.y * _camera.v_offset
	return {
		"origin": origin,
		"direction": -basis.z,
		"clear_of": _distance,
	}


## Swing the rig until the crosshair is on `point`.
##
## Solved from the *camera's* position rather than the rig's — the unobstructed
## camera `aim_ray` starts from — because the camera sits behind and to one side:
## aiming the rig at a target leaves the crosshair a shoulder-width off it at
## every distance. Moving the rig moves the camera, so one call gets close and
## calling it again on the next frame converges — which is what the scripted
## testbeds do.
func look_at_point(point: Vector3) -> void:
	var to := point - (aim_ray()["origin"] as Vector3)
	if to.length_squared() < 0.0001:
		return
	to = to.normalized()
	_yaw = atan2(-to.x, -to.z)
	_pitch = clampf(asin(clampf(to.y, -1.0, 1.0)), PITCH_MIN, PITCH_MAX)


## Point the view by angle, as a mouse would. For scripted testbeds.
func set_view(yaw_angle: float, pitch_angle: float) -> void:
	_yaw = yaw_angle
	_pitch = clampf(pitch_angle, PITCH_MIN, PITCH_MAX)


func camera() -> Camera3D:
	return _camera


## True while the aim button is held and this Bog is ours to aim. Read by
## `BogCombat`, which hangs the spear's drop indicator off it: the indicator is
## the answer to "where would this land", and that question is only being asked
## while somebody is holding the button down.
func is_aiming() -> bool:
	return _aiming


func yaw() -> float:
	return _yaw


func pitch() -> float:
	return _pitch
