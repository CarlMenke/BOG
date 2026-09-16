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

const DISTANCE_DEFAULT := 3.6
const DISTANCE_AIMING := 2.4
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
## sphere rather than a ray, along the path the Bog's head would see it by:
## pivot out to the shoulder, then shoulder back along the boom. A ray down the
## middle of the boom, which is what the `SpringArm3D` here used to cast, tested
## a line the camera was never on — 0.62 m to one side of it.
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
## How fast a pulled-in camera goes back out, per second, as an exponential
## ease. Coming *in* is never eased: any frame spent easing in is a frame drawn
## from inside the wall.
const RETURN_RATE := 5.0

@onready var _boom: Node3D = $Boom
@onready var _camera: Camera3D = $Boom/Camera3D

var _body: Bog
var _yaw: float = 0.0
var _pitch: float = -0.12
var _distance: float = DISTANCE_DEFAULT
var _shoulder: float = SHOULDER_DEFAULT
## How much of the shoulder and the boom the scenery currently allows. The
## camera sits at these, and they only ever lag behind the scenery outwards.
var _shoulder_clear: float = SHOULDER_DEFAULT
var _boom_clear: float = DISTANCE_DEFAULT
var _probe := PhysicsShapeQueryParameters3D.new()
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


## Put the camera as far out along shoulder-then-boom as the scenery allows.
##
## Two sweeps, so the shoulder offset cannot carry the lens through a wall beside
## the Bog either; and every frame, after the view has turned, so a camera swung
## round into a wall is pulled in on the frame it would have gone in rather than
## on the next physics tick. Pulled in at once to the first hit, let back out
## with an ease, and never further out than this frame's sweep says is clear, so
## the ease cannot carry it across a surface. Ceilings and canopies are the same
## sweep: looking down lifts the boom into them like any wall.
##
## Only the lens moves. The aim is taken from the unobstructed camera
## (`aim_ray`), so where a spear goes does not depend on any of this.
func _place_camera(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var basis := _boom.global_transform.basis
	var pivot := global_position

	var shoulder_want := _shoulder * _sweep(space, pivot, basis.x * _shoulder)
	_shoulder_clear = _ease_clear(_shoulder_clear, shoulder_want, delta)
	var shoulder_point := pivot + basis.x * _shoulder_clear

	var boom_want := _distance * _sweep(space, shoulder_point, basis.z * _distance)
	_boom_clear = _ease_clear(_boom_clear, boom_want, delta)

	_camera.transform = Transform3D(Basis.IDENTITY, Vector3(_shoulder_clear, 0.0, _boom_clear))
	# With the shoulder squeezed in, the lens is off the aim ray, and a crosshair
	# at the centre of the screen would sit a parallel shoulder's width from
	# where the spear goes. Turn the lens in to meet the aim ray where the aim ray
	# meets the world, so the reticle stays on the thing being aimed at.
	if _shoulder - _shoulder_clear > 0.001:
		var ray := aim_ray()
		var origin: Vector3 = ray["origin"]
		var direction: Vector3 = ray["direction"]
		var far := origin + direction * 60.0
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			origin + direction * float(ray["clear_of"]), far, COLLISION_MASK))
		var meet: Vector3 = far if hit.is_empty() else hit["position"]
		if _camera.global_position.distance_squared_to(meet) > 0.01:
			_camera.look_at(meet, basis.y)


## Keep up with the scenery at once when it closes in; ease back when it opens.
func _ease_clear(current: float, want: float, delta: float) -> float:
	if want <= current:
		return want
	return lerpf(current, want, 1.0 - exp(-RETURN_RATE * delta))


## The fraction of `motion` from `from` a camera can travel and stay at least
## `PROBE_RADIUS + PROBE_MARGIN` clear of the scenery.
##
## If the sphere does not fit even at the start (a head right up under a low
## ceiling) that segment falls back to a ray, which is what the old spring arm
## did everywhere, rather than collapsing the camera into the Bog's skull.
func _sweep(space: PhysicsDirectSpaceState3D, from: Vector3, motion: Vector3) -> float:
	var length := motion.length()
	if length < 0.001:
		return 1.0
	_probe.transform = Transform3D(Basis.IDENTITY, from)
	_probe.motion = motion
	var safe: float = space.cast_motion(_probe)[0]
	if safe >= 1.0:
		return 1.0
	if safe <= 0.0 and not space.intersect_shape(_probe, 1).is_empty():
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, from + motion, COLLISION_MASK))
		if hit.is_empty():
			return 1.0
		var reach := from.distance_to(hit["position"]) - PROBE_RADIUS - PROBE_MARGIN
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
