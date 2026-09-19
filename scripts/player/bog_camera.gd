class_name BogCamera
extends Node3D
## The third-person rig BOG is fought from. See `docs/PLAN_CAMERA.md`.
##
## The owner, 2026-09-18: *"the camera and model need a better connection, right
## now they are completely separated, which is too much freedom and allows for
## things that end up not being fun for the user. ... we need third person
## specifically for pvp, such as Fortnite; the third person that exists for
## story games where they are completely separate does not work as well in a
## pvp."*
##
## So this is the PvP rig and not the story-game one, and the difference is a
## single sentence: **the body faces where the camera faces**. The mouse turns
## the character; WASD moves it relative to that facing; a strafe and a backpedal
## are ordinary motion rather than a pose the aim button has to unlock. The rig
## that was here before orbited a body that faced its own velocity, which is
## Zelda and Uncharted and is the freedom the owner is describing — you could
## look one way and run another, so the thing under the crosshair and the thing
## the Bog was pointed at were two different facts and the player had to hold
## both of them.
##
## Four rules, and there is nothing else in this file:
##
## 1. **Rotation has no lag.** `_yaw` and `_pitch` are the mouse, this frame,
##    written straight onto the node. Every millisecond of rotation smoothing is
##    a millisecond of aiming through treacle, and a PvP rig cannot afford one.
## 2. **Position has a short lag.** The pivot eases to the Bog's eye, flat fast
##    and vertical slower, so a step or a scrape along a wall does not pump the
##    picture. This is Unreal's `bEnableCameraLag`, which Fortnite ships.
## 3. **Over the right shoulder, fixed.** No swap. 3.1 m back and 0.62 m across
##    at rest, 2.15 / 0.48 with a bow up, and the field of view and the mouse
##    sensitivity both scaled by `FOV_AIM_SCALE` so aiming narrows the view
##    without sweeping the same hand movement further across the world (the feel
##    round's numbers, unchanged).
## 4. **The shot comes out of the lens** (`aim_ray`). Screen centre is where the
##    spear goes, wherever scenery has put the camera.
##
## Rule 4 supersedes D-045's rule that the aim is read from the *unobstructed*
## camera. That rule bought one thing — a wall behind the Bog could not move a
## throw — and charged for it twice: the crosshair stopped being the aim, so the
## lens had to be turned in to meet the ray, and that correction then had to be
## rate-limited because the ray's meeting point jumps the length of the ray
## whenever it crosses an edge (D-088). Taking the ray from the lens deletes the
## correction, the rate limit and the disagreement together. The price is the
## honest one every Unreal third-person game pays: with your back against a wall
## the shot leaves from up to a boom's length further forward than it otherwise
## would. `clear_of` is still how far along the ray the Bog itself is, so nothing
## aims at the wall that pushed the lens in (D-025 survives, by another route).
##
## While the owner is dead the rig follows somebody else (D-020): a change of
## *subject*, not a second camera. A dead Bog's node is hidden and never freed,
## so its rig still holds the viewport, and pointing it at a living Bog is the
## whole of the feature.

## The view's own limits, about -69 and +54 degrees. `BogAim` reads these rather
## than typing its own, so the torso and the crosshair cannot stop at different
## places.
const PITCH_MIN := -1.20
const PITCH_MAX := 0.95

## Where the lens sits, at rest and with a bow up, and how much narrower the view
## gets while aiming. The feel round's numbers: at 3.6 m the Bog was a figure in
## a landscape and a fight read as two dots meeting.
const DISTANCE_DEFAULT := 3.1
const DISTANCE_AIMING := 2.15
const SHOULDER_DEFAULT := 0.62
const SHOULDER_AIMING := 0.48
const FOV_AIM_SCALE := 0.82
## How fast the rig crosses between those two sets: an eighth of a second, which
## is slower than the bow comes up and faster than a player can act on it.
const STANCE_SPEED := 8.0

## Radians per pixel at a `mouse_sensitivity` of 1.0. This is what the dial in
## the options screen *means*, so it is a contract with the player's muscle
## memory rather than a rig tuning, and it is the one number here the rework
## deliberately did not touch.
const SENSITIVITY_SCALE := 0.0022

## Rule 2, as two exponentials. Flat closes 90 % of a gap in 0.115 s, short
## enough that walking into a corner does not leave the Bog off-centre and long
## enough to swallow the single-frame corrections `move_and_slide` makes against
## a wall. The rise is deliberately about half that: the body's height moves on
## every stair, every crouch and every landing, and a view that tracked all of it
## exactly would pump. At 11 /s a 0.2 m step lifts the picture over about a fifth
## of a second instead of on one frame.
const LAG_FLAT := 20.0
const LAG_RISE := 11.0

## Rule 4's collision: `USpringArmComponent`, and nothing on top of it.
##
## The world and anything flagged as a camera blocker, never players — clipping
## to a team-mate who walked in behind you is worse than seeing through them.
## Unchanged from D-045, and it is the only thing about the old rig's collision
## that survives this rework.
const COLLISION_MASK := 1 | 64
## The probe is a sphere and not a ray because the lens is a volume: the near
## plane is 0.05 m out and about 0.09 m to its corners, so a lens that is merely
## *outside* a wall still draws the inside of it. 0.25 m, held a further 0.05 m
## off whatever it finds, puts three times the near plane's reach between the
## camera and the nearest face.
const PROBE_RADIUS := 0.25
const PROBE_MARGIN := 0.05
## Coming in is **instant** and going out is eased. Those are not two settings of
## one number, they are two different jobs: a single frame drawn from inside a
## wall is a hole in the world and no amount of smoothness is worth one, while a
## camera that sprang back out the moment a doorframe cleared is the thing
## players call swim. 6 /s crosses 90 % of a full arm in about 0.38 s.
const RETURN_RATE := 6.0
## And the return waits this long after the last pull-in before it starts. The
## case it is for is a picket fence, a row of trunks, a doorway taken sideways —
## scenery that crosses the arm several times a second. Without the hold each
## crossing is a whole in-and-out cycle; with it they are one pull-in.
const HOLD_TIME := 0.2

@onready var _camera: Camera3D = $Camera3D

var _body: Bog
var _yaw: float = 0.0
var _pitch: float = -0.12
var _distance: float = DISTANCE_DEFAULT
var _shoulder: float = SHOULDER_DEFAULT
## How much of the arm the scenery allows, as a fraction of the segment from the
## pivot to the unobstructed lens point.
##
## A fraction and not a length, for two reasons. The shoulder shrinks with the
## distance for free — the segment starts at the pivot, so a lens at 20 % of it
## is 20 % back *and* 20 % across, which is the D-083 invariant (the Bog keeps
## its place in the frame while the camera comes in) falling out of the geometry
## instead of being a second channel with its own sweep, its own hold and its own
## chance to disagree with the first. And the aim zoom changes the length the
## fraction is a fraction *of*, so carrying a length here would mean easing a
## number whose scale was moving underneath it.
var _clear: float = 1.0
var _hold: float = 0.0
## The pivot is placed by easing, and on the very first frame — only then — there
## is nothing to ease from.
var _placed: bool = false
var _probe := PhysicsShapeQueryParameters3D.new()
var _base_fov: float = 75.0
var _shake_strength: float = 0.0
var _shake_decay: float = 6.0
## Where shake has pushed the lens, in the lens's own X and Y. Godot applies
## `Camera3D.h_offset`/`v_offset` by translating the render transform anyway, so
## this draws the same picture those did — but it is a translation of the *node*,
## which is what lets `aim_ray` say "the camera's own position" and mean it.
var _shake_offset := Vector3.ZERO
var _aiming: bool = false
## Whose shoulder we are watching over while dead. Null means our own Bog.
var _spectating: Bog = null


func _ready() -> void:
	_body = get_parent() as Bog
	if _body == null:
		push_error("BogCamera expects to be a child of a Bog")
		return

	if not _body.is_local():
		# A remote Bog still carries a rig — it is part of the scene — but it
		# must not steal the viewport or read the mouse.
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


## Rule 1. The mouse is the view, with nothing between them.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	if SceneFlow.cursor_is_free():
		return
	var motion := event as InputEventMouseMotion
	var sensitivity := float(Settings.get_value("mouse_sensitivity")) * SENSITIVITY_SCALE
	if _aiming:
		sensitivity *= FOV_AIM_SCALE
	_yaw -= motion.relative.x * sensitivity
	var rise := motion.relative.y * sensitivity
	if bool(Settings.get_value("invert_y")):
		rise = -rise
	_pitch = clampf(_pitch - rise, PITCH_MIN, PITCH_MAX)


func _process(delta: float) -> void:
	if _body == null:
		return

	_aiming = Input.is_action_pressed("aim") and _body.alive and _spectating == null
	_follow(delta)
	_apply_stance(delta)
	_apply_shake(delta)

	rotation.y = _yaw
	_place_lens(delta)

	# Rule 1 again, from the body's side: hand down the *flat* basis, which is
	# what movement wants (`_wish_direction` would walk a Bog into the floor if
	# it could look down it) and what the facing wants (`Bog._face` turns the
	# body onto it every physics tick). The pitch travels beside it as a number,
	# for the one thing that wants it — a torso that steers nothing (D-066).
	#
	# Not while spectating. The corpse is not ours to steer, and turning a body
	# somebody else is still watching would be us moving their Bog.
	if _spectating == null:
		_body.set_view_basis(global_transform.basis, _pitch)


## The Bog the rig is framing — the one we are spectating if that Bog is still
## around, and our own otherwise. A spectated Bog can be freed out from under us
## (they leave, the match resets), so this is asked every frame rather than
## trusted once.
func _subject() -> Bog:
	if _spectating != null and is_instance_valid(_spectating):
		return _spectating
	return _body


## Watch `target` instead of our own Bog. Pass null to go back to our own.
func spectate(target: Bog) -> void:
	_spectating = target if target != _body else null


func spectating() -> Bog:
	return _spectating if is_instance_valid(_spectating) else null


## Rule 2.
func _follow(delta: float) -> void:
	var subject := _subject()
	var eye := subject.global_position + Vector3.UP * subject.eye_height()
	if not _placed:
		_placed = true
		global_position = eye
		return
	var next := global_position
	var flat := 1.0 - exp(-LAG_FLAT * delta)
	next.x = lerpf(next.x, eye.x, flat)
	next.z = lerpf(next.z, eye.z, flat)
	next.y = lerpf(next.y, eye.y, 1.0 - exp(-LAG_RISE * delta))
	global_position = next


## Rule 3: cross between the resting shot and the aiming one.
func _apply_stance(delta: float) -> void:
	var t := clampf(STANCE_SPEED * delta, 0.0, 1.0)
	_distance = lerpf(_distance, DISTANCE_AIMING if _aiming else DISTANCE_DEFAULT, t)
	_shoulder = lerpf(_shoulder, SHOULDER_AIMING if _aiming else SHOULDER_DEFAULT, t)
	_camera.fov = lerpf(_camera.fov, _base_fov * (FOV_AIM_SCALE if _aiming else 1.0), t)


## Put the lens as far out along the arm as the scenery allows: **one** sphere
## sweep, from the pivot to the whole unobstructed lens point, and the lens at
## the clear fraction of that one segment.
##
## The old rig swept this as two channels — back along a boom, then out to the
## shoulder from whatever depth the boom reached — and then needed a second
## invariant (D-083) to stop the shoulder holding its full width while the boom
## came in and sliding the Bog across the frame. One segment that starts at the
## pivot has that property built in: the lens comes in *toward the Bog's head*,
## so the picture it draws at 20 % of the arm is the picture it draws at 100 % of
## it, only closer. The diagonal is also the honest thing to sweep, because the
## diagonal is the line the lens is actually on; a boom-then-shoulder pair tests
## an L the camera never travels.
##
## Ceilings are not a special case: looking down swings the segment up into the
## canopy exactly as looking sideways swings it into a wall.
func _place_lens(delta: float) -> void:
	# The lens's own frame, inside the rig's. The rig carries the yaw — so the
	# basis it hands the body stays flat — and this carries the pitch.
	var tilt := Basis(Vector3.RIGHT, _pitch)
	var reach := tilt * Vector3(_shoulder, 0.0, _distance)
	var room := _clear_fraction(global_transform.basis * reach)

	if room < _clear:
		# In: at once, and start the hold.
		_clear = room
		_hold = HOLD_TIME
	else:
		_hold = maxf(0.0, _hold - delta)
		if _hold <= 0.0:
			_clear = lerpf(_clear, room, 1.0 - exp(-RETURN_RATE * delta))
	# The sweep has the last word every frame, so the easing above can be as
	# gentle as it likes without ever being a frame late into a wall.
	_clear = minf(_clear, room)

	_camera.transform = Transform3D(tilt, reach * _clear + tilt * _shake_offset)


## How much of `motion` from the pivot a `PROBE_RADIUS` sphere can travel and
## stay clear of the scenery, as a fraction of it.
##
## `cast_motion` answers zero both for a sphere that is genuinely wedged and for
## one that is merely inside the solver's own contact margin while still
## technically clear, and there is no way from here to tell those apart — so both
## take the same conservative answer, a ray down the same line held back by the
## sphere's radius. Asking a *second* query which case it was is what made the
## old rig flip between two disagreeing answers on float noise (D-088's "swim").
func _clear_fraction(motion: Vector3) -> float:
	var length := motion.length()
	if length < 0.001:
		return 1.0
	var space := get_world_3d().direct_space_state
	var pivot := global_position
	_probe.transform = Transform3D(Basis.IDENTITY, pivot)
	_probe.motion = motion
	var safe: float = space.cast_motion(_probe)[0]
	if safe >= 1.0:
		return 1.0
	if safe > 0.0:
		return clampf((safe * length - PROBE_MARGIN) / length, 0.0, 1.0)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		pivot, pivot + motion, COLLISION_MASK))
	if hit.is_empty():
		return 1.0
	var reach: float = pivot.distance_to(hit["position"]) - PROBE_RADIUS - PROBE_MARGIN
	return clampf(reach / length, 0.0, 1.0)


## Called on kills, hard landings and nearby impacts.
func shake(strength: float, decay: float = 6.0) -> void:
	_shake_strength = maxf(_shake_strength,
		strength * float(Settings.get_value("camera_shake")))
	_shake_decay = decay


func _apply_shake(delta: float) -> void:
	if _shake_strength <= 0.0001:
		_shake_offset = Vector3.ZERO
		return
	_shake_strength = maxf(0.0, _shake_strength - _shake_decay * _shake_strength * delta)
	_shake_offset = Vector3(
		randf_range(-1.0, 1.0) * _shake_strength * 0.06,
		randf_range(-1.0, 1.0) * _shake_strength * 0.06,
		0.0)


## World-space ray the crosshair is pointing down. Everything the player throws
## is aimed with this.
##
## Rule 4: it is the camera's own position and the camera's own forward, so
## screen centre *is* the aim by construction and there is nothing left for a
## reticle correction to fix. Shake is in it because shake moves the node, and a
## shaken picture whose crosshair did not move with it would be a crosshair that
## lied for the length of the shake.
##
## `clear_of` is how far along the ray the Bog itself is, which with the shot
## coming from the lens is the lens's real distance from the pivot: `BogCombat`
## starts its hit test there, so the wall that pushed the camera forward is
## behind the test rather than the first thing in it (D-025).
func aim_ray() -> Dictionary:
	return {
		"origin": _camera.global_position,
		"direction": -_camera.global_transform.basis.z,
		"clear_of": _camera.global_position.distance_to(global_position),
	}


## Swing the rig until the crosshair is on `point`.
##
## Solved from the lens rather than from the pivot, because the lens is behind
## and to one side: aiming the *rig* at a target leaves the crosshair a
## shoulder's width off it at every range. Moving the rig moves the lens, so one
## call gets close and calling it again next frame converges — which is what the
## scripted testbeds do.
func look_at_point(point: Vector3) -> void:
	var to := point - _camera.global_position
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
