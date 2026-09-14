class_name SpearProjectile
extends Node3D
## A thrown spear. One hit anywhere is a kill — `GubCombat.SPEAR_DAMAGE` is a
## whole Gub's health, so the promise is kept by the number and not by a rule in
## here (D-062).
##
## The shaft itself makes no such assumption. It sticks in whoever it lands on,
## living or dying, and rides them until a corpse takes it or they respawn,
## which is what the bow's arrows will need and what `_stick_in` describes.
##
## Every peer spawns and simulates its own copy from the same launch parameters.
## The flight is pure ballistics with no randomness, so all peers agree on where
## the spear is without a single position packet — the only thing that travels
## is the launch itself.
##
## Only the host's copy is `authoritative` and allowed to declare a kill. The
## others stop and stick at the same moment purely so the visual matches.
##
## This is a plain `Node3D` integrated by hand rather than a `RigidBody3D`. At
## 42 m/s a physics body covers 0.7 m per tick and tunnels straight through a
## Gub; stepping the flight and sweeping the segment between the old and new
## position is what makes an instant-kill weapon actually hit.

signal struck_gub(victim: Gub, point: Vector3, bone: String)
signal struck_world(point: Vector3, normal: Vector3)

const MODEL := preload("res://art/generated/spear.glb")

const SPEED := 42.0
## Spears drop, but at a third of world gravity. Enough that a long throw has to
## be led and arced — which is where the skill in the fight lives — without
## turning mid-range duels into mortar practice.
const DROP := 8.0
const MAX_LIFETIME := 6.0
## How long a spear stays stuck in the ground before fading out.
const STUCK_LINGER := 7.0
const STUCK_FADE := 1.2
## How far past the impact point the head sinks.
const BURY_DEPTH := 0.12
## How long a shaft standing in a Gub that has **died** waits for a corpse to
## claim it before giving up and removing itself. The host builds the ragdoll
## within the same frame; a client has to wait for the death to arrive over the
## network.
##
## It used to time every hit, because until D-062 a shaft went invisible the
## instant it struck a body and every one of them was waiting for a corpse — the
## grace was what stopped a hit that killed nobody leaving a spear parked on an
## invisible list for ever. A shaft now rides a living Gub in plain sight and
## waits for nothing, so this is down to the one case that still has a corpse
## coming and no corpse yet: the window between a death and the body that
## follows it. Past the window there is no ragdoll coming at all — a void death,
## or a client that never saw one — and a shaft hanging in the air where a body
## used to be is exactly the thing this number exists to prevent.
const ADOPTION_GRACE := 0.75

## How much brighter the spear burns while it is in the air.
##
## The trail says where the spear *has been*; this is what makes the spear
## itself findable at the head of it. A thrown stick is a thin, dark, fast thing
## against a dark forest, and the playtest verdict on that was blunt: "you can't
## see the spear". Lighting it is a cheat and a deliberate one — the same cheat
## as the trail, and the alternative is a weapon whose whole skill ceiling is
## reading a flight nobody can see.
##
## A *multiplier* rather than an absolute, because of how everything in
## `art/generated` is built: the models carry a **black albedo and a pre-shaded
## emission texture**, so their entire visible colour is already emission. There
## is no glow to switch on here, only one to turn up. The same fact rules out
## tinting it — the material's emission operator is multiply, so handing it a
## warm colour would *darken* the texture's blue rather than adding warmth.
##
## The number was picked by eye against `resources/config/default_env.tres`,
## which tonemaps with ACES at a white point of 6.0. Values that sound bright in
## the abstract do very little through that curve: at 1.25 the spear was
## indistinguishable from an unlit one. Here the brightest parts of the shaft
## clear the environment's 1.05 bloom threshold, so the spear reads as lit
## rather than as a stick, and stops well short of a lightsaber.
##
## It comes off the moment the spear stops. A spear standing in the dirt or
## sticking out of a corpse is scenery and has to read as scenery; a glowing one
## would turn every miss into a beacon and every body into a lamp.
const GLOW_BOOST := 3.0
## Only reached by a surface that was not emissive to begin with. Nothing on the
## shipping spear is, but a material with no emission has nothing to multiply and
## would otherwise "glow" black.
const GLOW_COLOUR := Color(1.0, 0.94, 0.76)

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_DEPLOYABLE := 8

var thrower_id: int = 0
var authoritative: bool = false

var _velocity: Vector3 = Vector3.ZERO
var _previous: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _stuck: bool = false
var _stuck_age: float = 0.0
## Set once a corpse has taken ownership of this spear.
var _embedded: bool = false
## Seconds spent waiting for a corpse to claim this spear. Only ever counts up
## while the Gub it is standing in is dead — see `ADOPTION_GRACE`.
var _pending_age: float = 0.0
## The Gub this shaft is standing in, while it is standing in a living one
## (D-062), and the bone it is riding.
##
## The shaft keeps its own parent and copies the bone's pose every tick rather
## than being re-parented under a `BoneAttachment3D`. Three reasons, and the
## third is the one that decided it: a bone attachment is a node per hit that
## somebody has to remember to free, `GubRagdoll._adopt_spears` re-parents out
## of *whatever* this is and would have to tear the mount down as well, and a
## shaft whose parent is still the arena keeps its world transform trivially
## true — which is what the ragdoll, the fade and the audio all read.
var _rider: Gub
var _rider_skeleton: Skeleton3D
var _rider_bone: int = -1
## Where the shaft sits in the bone's own space, taken once at the moment of
## impact and never recomputed. The hit is a fact about a pose; re-deriving it
## from the world each tick would let it creep.
var _rider_local: Transform3D = Transform3D.IDENTITY
## The velocity this spear was carrying at the moment it struck something.
## `_velocity` is zeroed on impact, so without this the momentum of the hit is
## gone by the time anyone downstream asks about it.
var _impact_velocity: Vector3 = Vector3.ZERO
var _model: Node3D
var _thrower: Gub
var _trail: SpearTrail
## The mesh nodes currently carrying the in-flight glow override.
var _glowing: Array[MeshInstance3D] = []


## Launch a spear. `direction` is expected to be normalised.
static func launch(parent: Node, thrower: Gub, origin: Vector3, direction: Vector3,
		is_authoritative: bool) -> SpearProjectile:
	var spear := SpearProjectile.new()
	spear.name = "Spear_%d_%d" % [thrower.peer_id, Time.get_ticks_msec()]
	spear.thrower_id = thrower.peer_id
	spear.authoritative = is_authoritative
	spear._thrower = thrower
	parent.add_child(spear)
	spear.global_position = origin
	spear._previous = origin
	spear._velocity = direction.normalized() * SPEED
	spear._face_travel()
	return spear


func _ready() -> void:
	_model = MODEL.instantiate() as Node3D
	# The mesh runs along its own +Y from butt to tip, but the projectile flies
	# along -Z like everything else in Godot, so the model is tipped forward and
	# slid back to put its point at the origin.
	_model.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_model.position = Vector3(0.0, 0.0, 0.62)
	add_child(_model)
	_light_up()

	_trail = SpearTrail.new()
	add_child(_trail)
	_trail.push_point(global_position)


func _physics_process(delta: float) -> void:
	if _stuck:
		_tick_stuck(delta)
		return

	_age += delta
	if _age > MAX_LIFETIME:
		queue_free()
		return

	_velocity.y -= DROP * delta
	_previous = global_position
	var next := global_position + _velocity * delta

	var hit := _sweep(_previous, next)
	if hit.is_empty():
		global_position = next
		_face_travel()
		if _trail != null:
			_trail.push_point(global_position)
		return

	_resolve(hit)


## Sweep the segment the spear covered this tick. A ray rather than a shape cast:
## the spear is a stick, its tip is what matters, and a ray is both cheaper and
## easier to reason about than a swept capsule that can catch on its own length.
func _sweep(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_DEPLOYABLE
	query.collide_with_areas = false
	query.collide_with_bodies = true
	# A Gub cannot spear itself on the way out of its own hand.
	if is_instance_valid(_thrower):
		query.exclude = [_thrower.get_rid()]
	return space.intersect_ray(query)


func _resolve(hit: Dictionary) -> void:
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var collider: Object = hit["collider"]

	var victim := collider as Gub
	if victim != null:
		# Spawn protection makes a Gub solid but unkillable, so the spear passes
		# through rather than stopping short and looking like a miss.
		if victim.alive and not victim.is_invulnerable():
			var bone := nearest_bone(victim, point)
			# Whether the hit *hurts* is the host's decision and is not
			# second-guessed here: the signal is emitted either way, the host
			# asks its own question in `report_damage`, and the ward flash comes
			# back from there.
			#
			# What this has to decide, locally, on every peer, is what becomes
			# of the shaft — and it cannot wait a round trip to be told, because
			# the answer is what the next frame draws. So it asks the same
			# question the host is about to ask, off the same replicated state
			# (`MatchState.damage_refusal`): a hit that lands stands in the
			# body, and a hit that does not leaves nothing behind.
			#
			# An Elder is the loudest case and the one this was written for
			# (D-040). It is not invulnerable in the sense above — it is
			# *solid*, and a spear that passed through one would be the worst of
			# both readings — so the shaft stops dead and is gone, and the ward
			# is the feedback.
			if not MatchState.damage_would_land(victim.peer_id, thrower_id,
					Gub.Cause.SPEAR):
				_glance_off(point)
				struck_gub.emit(victim, point, bone)
				return
			_stick_in(victim, point, bone)
			struck_gub.emit(victim, point, bone)
			return
		global_position = point
		return

	global_position = point
	_stick(normal)
	struck_world.emit(point, normal)


## Which bone a hit landed on, so the ragdoll spins around the right place.
## Approximate on purpose — it drives a visual, not a damage number.
##
## Static and public because the Elder's bolt asks the same question of the same
## rig for the same reason (D-038), and the answer has to be the same answer: a
## corpse that spins differently depending on which weapon killed it would be
## two ragdoll behaviours where the physics only has one.
static func nearest_bone(victim: Gub, point: Vector3) -> String:
	var skeleton := victim.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return "Spine1"
	var best := "Spine1"
	var best_distance := INF
	for segment: Dictionary in RagdollBuilder.SEGMENTS:
		var bone: int = skeleton.find_bone(segment["bone"])
		if bone < 0:
			continue
		var world := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		var distance := world.origin.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = segment["bone"]
	return best


## Bury the shaft in the Gub it just hit and leave it there.
##
## Freeing it instead — which is what the very first version did — threw away
## the clearest read in the game: a body on the ground with a spear through it
## says who died and roughly how, from across the arena, for as long as the
## corpse lasts.
##
## Since D-062 it does not wait for that corpse to exist, and that is the change
## the bow needed. The shaft **rides the living skeleton**: it stands in the
## victim, moves with the bone it went through, and is still there whether the
## victim dies in a second or walks the rest of the round off with it. A Gub
## with three arrows in it and a short bar is the best read this game has, and
## it costs one matrix multiply a tick.
##
## Three endings, and only the first is new:
##
## * the victim lives — the shaft rides until they respawn, and `Gub`
##   (`MAX_EMBEDDED_SHAFTS`) is what stops a Gub becoming a hedgehog;
## * the victim dies with a corpse — `GubRagdoll` takes it off the list while it
##   is building the body and hangs it off the matching physical bone, so it
##   tumbles with the limb;
## * the victim dies with no corpse — a void death — and `_tick_stuck` gives up
##   after `ADOPTION_GRACE` rather than leaving a shaft hanging in the air.
func _stick_in(victim: Gub, point: Vector3, bone: String) -> void:
	_stuck = true
	_stuck_age = 0.0
	_pending_age = 0.0
	_impact_velocity = _velocity
	global_position = point + _velocity.normalized() * BURY_DEPTH
	_velocity = Vector3.ZERO
	_stop_glowing()
	AudioDirector.play_3d_varied(AudioDirector.SPEAR_HIT_BODY, point)
	if _trail != null:
		_trail.begin_fade()
		_trail = null
	_mount_on(victim, bone)
	victim.embed_spear(self, bone)


## Note where in the victim's skeleton this shaft has ended up, so `_tick_stuck`
## can keep it there. A rig with no skeleton, or no such bone, simply leaves the
## shaft standing in the world at the point of impact — wrong, but only visibly
## wrong on a broken model, and better than refusing the hit.
func _mount_on(victim: Gub, bone: String) -> void:
	var skeleton := victim.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var index := skeleton.find_bone(bone)
	if index < 0:
		return
	_rider = victim
	_rider_skeleton = skeleton
	_rider_bone = index
	_rider_local = (skeleton.global_transform \
		* skeleton.get_bone_global_pose(index)).affine_inverse() * global_transform


## Stop dead against a body the hit did nothing to, and cease to exist.
##
## Written for the Elder (D-040) and now the ending for every refused hit: a
## robe, a team-mate with friendly fire off, a Gub the host had already killed.
## What they have in common since D-062 is a number — the damage was zero — and
## a shaft standing in somebody who was not hurt is a lie about the fight that
## the bar over their head then contradicts.
##
## Neither of the other two endings fits. `_stick_in` puts the shaft *in* them,
## which is the thing that must not happen here, and `_stick` would leave one
## hanging in mid-air at chest height while the Gub it hit walks out from behind
## it — a spear stuck in nothing, which reads as the game having lost track of
## the body.
##
## `_impact_velocity` is recorded before the velocity is cleared even though
## nothing will use it: the host reads it out of `struck_gub`'s handler on the
## way into `report_kill`, which is about to refuse the kill, and a zero there
## would be a lie that happens not to matter today. The sound and the flash are
## not here — they are `WardFlash.burst`'s, fired once by the host from the one
## place that knows the hit was refused, so that the Elder's bolt gets the same
## feedback without a second copy of it living on this file.
func _glance_off(point: Vector3) -> void:
	_stuck = true
	_impact_velocity = _velocity
	_velocity = Vector3.ZERO
	global_position = point
	_stop_glowing()
	if _trail != null:
		_trail.begin_fade()
		_trail = null
	visible = false
	# Deferred, so the object is still perfectly alive for the `struck_gub`
	# handler the caller is about to run.
	queue_free()


func _stick(normal: Vector3) -> void:
	_stuck = true
	set_process_priority(0)
	_impact_velocity = _velocity
	_stop_glowing()
	AudioDirector.play_3d_varied(AudioDirector.SPEAR_HIT_WORLD, global_position)
	if _trail != null:
		_trail.begin_fade()
		_trail = null
	# Bury the head a little and let the shaft keep the angle it arrived at, so
	# a spear in the dirt reads as thrown rather than placed. The tip is at the
	# origin, so pushing *along* the flight direction sinks it into the surface.
	global_position += _velocity.normalized() * BURY_DEPTH
	_velocity = Vector3.ZERO
	if normal.length_squared() > 0.001:
		# A slight lean toward the surface normal stops spears from lying flush
		# against a wall.
		var lean := global_transform.basis.z.slerp(-normal, 0.18)
		if lean.length_squared() > 0.001:
			look_at(global_position - lean, Vector3.UP)


func _tick_stuck(delta: float) -> void:
	# A spear that ended up on a corpse is owned by the corpse and disappears
	# when the corpse does; only one stuck in the scenery times itself out.
	if _embedded:
		return
	if _rider != null:
		_tick_rider(delta)
		return
	_stuck_age += delta
	if _stuck_age < STUCK_LINGER:
		return
	var fade := 1.0 - clampf((_stuck_age - STUCK_LINGER) / STUCK_FADE, 0.0, 1.0)
	if fade <= 0.0:
		queue_free()
		return
	if _model != null:
		_model.scale = Vector3.ONE * maxf(fade, 0.01)


## One tick of standing in somebody (D-062).
##
## Three states, in the order they can happen:
##
## **The Gub is gone.** Its peer left, or the arena was torn down under it.
## Nothing to ride and nothing to be adopted by.
##
## **The Gub is dead and this has not been adopted yet.** The shaft goes
## invisible immediately rather than at the end of the grace, because the body
## it is standing in has already been hidden (`MatchState._apply_death`) and a
## spear left visible for even a few frames is a spear hanging in mid-air. On
## the host the ragdoll claims it inside the same frame and it is never seen
## missing; on a client it comes back the moment the death arrives. If nothing
## claims it inside `ADOPTION_GRACE` there is no corpse coming.
##
## **The Gub is alive.** Copy the bone's pose and stay in it. The skeleton's
## pose is in the *skeleton's* space, so the world transform is the skeleton's
## own global transform through the bone and then through the offset taken at
## the moment of impact — which is why a shaft in a running Gub swings with the
## arm rather than sliding about on the surface of it.
func _tick_rider(delta: float) -> void:
	if not is_instance_valid(_rider) or not is_instance_valid(_rider_skeleton):
		queue_free()
		return
	if not _rider.alive:
		visible = false
		_pending_age += delta
		if _pending_age > ADOPTION_GRACE:
			queue_free()
		return
	_pending_age = 0.0
	global_transform = _rider_skeleton.global_transform \
		* _rider_skeleton.get_bone_global_pose(_rider_bone) * _rider_local


## Put the flight glow on every surface of the model.
##
## A copy of the imported material per spear, the same way `GubRagdoll` takes
## its own copy to fade a corpse out — and for the same reason. The imported
## material is shared by every spear in the game, the one in your hand
## included, so lighting *it* up would light up all of them and leave them lit.
##
## One small material per throw, held by the projectile and freed with it. A
## single glowing copy cached and handed to every spear would be marginally
## cheaper and would be a mutable global living past the end of the match, which
## is a much worse trade than a duplicate of a material on a two-surface stick.
func _light_up() -> void:
	for node in _model_meshes():
		var lit := false
		for surface in node.mesh.get_surface_count():
			# Null means a material this cannot copy — a shader material, say.
			# That surface simply does not glow, rather than being replaced by
			# something that would throw its texture away.
			var source := node.get_active_material(surface) as BaseMaterial3D
			if source == null:
				continue
			var glow := source.duplicate() as BaseMaterial3D
			if not glow.emission_enabled:
				glow.emission_enabled = true
				glow.emission = GLOW_COLOUR
				glow.emission_energy_multiplier = 1.0
			glow.emission_energy_multiplier *= GLOW_BOOST
			node.set_surface_override_material(surface, glow)
			lit = true
		if lit:
			_glowing.append(node)


## ...and take it off again, which is what makes a landed spear look landed.
func _stop_glowing() -> void:
	for node in _glowing:
		if not is_instance_valid(node) or node.mesh == null:
			continue
		for surface in node.mesh.get_surface_count():
			node.set_surface_override_material(surface, null)
	_glowing.clear()


func _model_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [_model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var mesh_node := node as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			out.append(mesh_node)
		stack.append_array(node.get_children())
	return out


func _face_travel() -> void:
	if _velocity.length_squared() < 0.001:
		return
	# look_at points -Z at the target, which is the direction of flight.
	look_at(global_position + _velocity, Vector3.UP)


## Where the spear is right now, for trails and audio.
func velocity() -> Vector3:
	return _velocity


## What the spear was doing at the instant it hit, direction *and* speed. This
## is what carries the weight of a throw into the corpse: a spear caught at the
## top of a long arc has shed most of its speed and should shove a body far less
## than one that arrives flat from ten metres.
func impact_velocity() -> Vector3:
	return _impact_velocity


func is_stuck() -> bool:
	return _stuck


## Called by `GubRagdoll` once the spear has been re-parented onto a physical
## bone, so it stops running its own fade-out timer.
##
## The ride ends here: the physics carries the shaft from now on, and a pose
## copied off the animated skeleton it came out of would fight it.
func mark_embedded() -> void:
	_embedded = true
	_rider = null
	_rider_skeleton = null
	visible = true
