class_name RefillStone
extends Area3D
## A flat stone by the lodge that tops your pockets up. Stand on it.
##
## The range's supply problem is not that items are scarce, it is that walking
## back to a well four times to practise one thing is walking rather than
## practising. So the stone fills what you are missing, on a short cooldown,
## and the wells stay the place where a *single* item is a thing you went and
## got.
##
## **The caps are this stone's, not the game's.** There is no carried-stock cap
## anywhere in BOG: `BogCombat`'s `_shields`, `_magnets` and `_potions` are
## incremented by the `grant_*` calls, decremented by use and zeroed by death,
## and nothing clamps them. Adding a real cap to `BogCombat` to give this stone
## a number to fill to would have changed every map in the game — a corpse drop
## refused because your pockets are full is a new rule for Rust and the Hollow,
## and this unit has no mandate to write one. So `FULL` lives here, is read by
## nothing else, and the stone is the only thing in the build that has an
## opinion about what "full" means.
##
## **Only what is missing.** A Bog that already has everything gets nothing at
## all: no grant, no chime, no pulse, and the cooldown is not even started. A
## stone that chimed at a full player would be a stone that says "there you go"
## when it did nothing, which is the one thing a feedback sound must never do.
##
## **The host grants; every peer draws.** The grant is `Net.is_host` only, like
## every other award in the game. The chime and the pulse are not sent — they
## are *derived*, on each peer, from the counts `BogCombat._do_set_inventory`
## already broadcasts to everybody. So the stone needs no RPC of its own, which
## matters here more than usual: this node is built by code into a map, and an
## RPC is addressed by node path (see `Pickup`'s header on why that is the bug
## D-024 exists because of).

## What the stone fills you to.
##
## Two shields, because `MatchConfig.shield_max_active` defaults to 2 and two is
## therefore one full planting — enough to set up the thing you are practising
## and not enough to wall yourself in. Two magnets to match.
##
## One potion, deliberately not two. A potion is the *option* to stand still for
## two seconds (D-067), and the decision it buys is the interesting part; a
## stack of them is a different item, one that means "you cannot lose a duel of
## attrition". One is a decision, two is a resource.
const FULL := {"shields": 2, "magnets": 2, "potions": 1}

## How long before the same player can be filled again. Long enough that the
## stone is a place you return to rather than a place you stand, short enough
## that it never makes you wait for the thing you came to practise.
const COOLDOWN := 2.0

## How often a Bog standing on the stone is looked at again. The stone re-checks
## rather than firing once on entry, so a player who walks on with full pockets,
## spends two shields where they stand and is still on the stone is filled — the
## alternative is a stone that only works if you step off and back on, which
## reads as broken.
const RECHECK := 0.25

const RADIUS := 2.2
const THICKNESS := 0.14
const STONE_TINT := Color(0.52, 0.53, 0.47)
const GLOW := Color(0.55, 0.92, 0.78)

const PULSE_TIME := 0.35
const REST_ENERGY := 0.9
const PULSE_ENERGY := 3.2

## Per peer, the earliest clock this stone will fill them again. Host only.
var _next_ok: Dictionary = {}
var _clock: float = 0.0
var _recheck_at: float = 0.0

## Per peer, the counts this peer last saw. The pulse fires when one goes up
## while its Bog is standing here, which is the same event on every machine
## without a message being sent about it.
var _seen: Dictionary = {}

var _light: OmniLight3D
var _disc: MeshInstance3D
var _ring: MeshInstance3D


func _ready() -> void:
	# Nothing collides with the stone — it is a flagstone in the deck, not an
	# obstacle — and it watches for Bogs only. `Pickup`'s layers exactly.
	collision_layer = 0
	collision_mask = Pickup.LAYER_PLAYER
	# **Monitoring everywhere, unlike a `Pickup`.** A drop's overlap is a
	# decision and so belongs to the host alone; this overlap is also the
	# question "whose numbers do I watch", which every peer has to answer to
	# draw the pulse. Nothing is decided off it except on the host.
	monitoring = true
	_build()


func _process(delta: float) -> void:
	_clock += delta
	_recheck_at -= delta
	var due := _recheck_at <= 0.0
	if due:
		_recheck_at = RECHECK
	for body in get_overlapping_bodies():
		var bog := body as Bog
		if bog == null or not bog.alive:
			continue
		var combat := bog.get_node_or_null("Combat") as BogCombat
		if combat == null:
			continue
		_watch(bog.peer_id, combat)
		if due and Net.is_host:
			_fill(bog.peer_id, combat)


## Host only. Raise this Bog to the caps, granting only the difference.
func _fill(peer_id: int, combat: BogCombat) -> void:
	if _clock < float(_next_ok.get(peer_id, -1.0)):
		return
	var shields: int = FULL["shields"] - combat.shield_count()
	var magnets: int = FULL["magnets"] - combat.magnet_count()
	var potions: int = FULL["potions"] - combat.potion_count()
	if shields <= 0 and magnets <= 0 and potions <= 0:
		# Nothing missing. Nothing happens — not even the cooldown, so a player
		# who arrives full and immediately spends a shield is filled on the next
		# re-check rather than two seconds later.
		return
	if shields > 0:
		combat.grant_shield(shields)
	if magnets > 0:
		combat.grant_magnet(magnets)
	if potions > 0:
		combat.grant_potion(potions)
	_next_ok[peer_id] = _clock + COOLDOWN


## Every peer. Notice a Bog's stock going up while it is standing here, and say
## so out loud.
##
## Derived rather than told: `_do_set_inventory` is an RPC that runs on every
## peer, so the rise this reads is the same rise on every machine, on the same
## message. The one thing it must not do is fire for stock that arrived some
## other way — but the only other ways are a corpse drop and a death, and
## neither happens to a Bog standing on this stone without also going through
## this node's own overlap test first.
func _watch(peer_id: int, combat: BogCombat) -> void:
	var now := Vector3i(combat.shield_count(), combat.magnet_count(), combat.potion_count())
	var before: Variant = _seen.get(peer_id)
	_seen[peer_id] = now
	if before == null:
		return
	var was: Vector3i = before
	if now.x > was.x or now.y > was.y or now.z > was.z:
		_pulse()


func _pulse() -> void:
	if _light == null:
		return
	AudioDirector.play_3d(AudioDirector.REFILL_CHIME, global_position)
	var beat := create_tween()
	beat.set_parallel(true)
	beat.tween_property(_light, "light_energy", PULSE_ENERGY, PULSE_TIME * 0.3)
	if _ring != null:
		beat.tween_property(_ring, "scale", Vector3(1.18, 1.0, 1.18), PULSE_TIME * 0.3)
	var settle := beat.chain()
	settle.set_parallel(true)
	settle.tween_property(_light, "light_energy", REST_ENERGY, PULSE_TIME * 0.7)
	if _ring != null:
		settle.tween_property(_ring, "scale", Vector3.ONE, PULSE_TIME * 0.7)


# ------------------------------------------------------------------ visual ---

func _build() -> void:
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = RADIUS
	# Tall enough that a Bog running across it is caught on some frame, for the
	# reason `Pickup.CATCH_HEIGHT` is 2.2: a volume the height of the stone is
	# one a sprinting player steps over between two physics ticks.
	cylinder.height = 2.4
	shape.shape = cylinder
	shape.position = Vector3(0.0, 1.2, 0.0)
	add_child(shape)

	var stone := StandardMaterial3D.new()
	stone.albedo_color = STONE_TINT
	stone.roughness = 0.84
	stone.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	_disc = MeshInstance3D.new()
	var slab := CylinderMesh.new()
	slab.top_radius = RADIUS
	slab.bottom_radius = RADIUS
	slab.height = THICKNESS
	slab.radial_segments = 8
	_disc.mesh = slab
	_disc.material_override = stone
	_disc.position = Vector3(0.0, THICKNESS * 0.5, 0.0)
	add_child(_disc)

	# The carved ring that lights up. Separate from the slab so the pulse can
	# scale it without the flagstone growing out of the deck.
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS * 0.58
	torus.outer_radius = RADIUS * 0.72
	_ring.mesh = torus
	var lit := StandardMaterial3D.new()
	lit.albedo_color = GLOW
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lit.emission_enabled = true
	lit.emission = GLOW
	lit.emission_energy_multiplier = 1.8
	lit.disable_receive_shadows = true
	_ring.material_override = lit
	_ring.position = Vector3(0.0, THICKNESS + 0.02, 0.0)
	add_child(_ring)

	var label := Label3D.new()
	label.text = "REFILL"
	label.font_size = 44
	label.pixel_size = 0.0030
	label.modulate = GLOW
	label.outline_size = 14
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.position = Vector3(0.0, 0.05, -RADIUS - 0.35)
	label.rotate_x(-PI * 0.5)
	add_child(label)

	_light = OmniLight3D.new()
	_light.light_color = GLOW
	_light.light_energy = REST_ENERGY
	_light.omni_range = 6.5
	_light.position = Vector3(0.0, 0.7, 0.0)
	add_child(_light)
