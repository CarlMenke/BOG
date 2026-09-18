class_name OrbLauncher
extends RangeTarget
## The thing at the far end of the long lane that throws glowworms across it.
##
## It is a `RangeTarget` for one reason only: it is built from the same `Targets`
## marker group by the same builder, and inheriting means `RangeTarget.build_all`
## does not need a special case. It is **not** shootable — no collision shape,
## and it leaves the `range_targets` group so the sword never swings at it —
## because a launcher you can knock over is a launcher somebody will knock over.
##
## **The host launches, everybody simulates.** Every `INTERVAL` the host picks a
## seed and sends it; each peer builds the same parabola from it (see
## `GlowOrb`). The launch time travels with it so a client that joined half a
## second ago starts its orb in phase rather than watching one teleport into
## place.

## Seconds between launches. Slow enough that a missed orb is a real loss and
## fast enough that practice is practice.
const INTERVAL := 4.0

## How many may be in the air at once. A cap rather than a consequence: at 4 s
## apart and 6 s of flight there are usually two, and a peer that hitched should
## not come back to eleven.
const MAX_LIVE := 3

const HOUSING := 0.42

var lane_length: float = 60.0

var _clock: float = 0.0
var _serial: int = 0
var _rng := RandomNumberGenerator.new()
var _live: Array[GlowOrb] = []


func setup_from_meta(kind_of: String, range_m: float) -> void:
	kind = kind_of
	declared_range = range_m
	if range_m > 0.0:
		lane_length = range_m
	_build_housing()


func _ready() -> void:
	# Deliberately *not* `add_to_group(GROUP)` and no collision: see the header.
	collision_layer = 0
	collision_mask = 0
	_rng.randomize()
	_build_housing()
	# Stagger the first one, so a range with more than one launcher on it does
	# not fire them in lockstep.
	_clock = _rng.randf_range(0.0, INTERVAL)


func hit_radius() -> float:
	return 0.0


func _build_housing() -> void:
	if has_node("Housing"):
		return
	var housing := MeshInstance3D.new()
	housing.name = "Housing"
	var box := BoxMesh.new()
	box.size = Vector3(HOUSING, HOUSING, HOUSING * 1.6)
	housing.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.26, 0.22, 0.18)
	material.roughness = 0.9
	material.emission_enabled = true
	material.emission = GlowOrb.COLOUR
	material.emission_energy_multiplier = 0.25
	housing.mesh.material = material
	add_child(housing)


func _process(delta: float) -> void:
	if not Net.is_host:
		return
	_prune()
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = INTERVAL
	if _live.size() >= MAX_LIVE:
		return
	_serial += 1
	var seed_value := _rng.randi()
	_do_launch.rpc(seed_value, global_transform, lane_length)
	_do_launch(seed_value, global_transform, lane_length)


## The launch, on every machine.
##
## The transform travels rather than being read off this node, for the reason
## the spear's origin travels: the orb must start from the same place on every
## peer even if this launcher has not finished being built on one of them.
@rpc("authority", "call_remote", "reliable")
func _do_launch(seed_value: int, at: Transform3D, length: float) -> void:
	var orb := GlowOrb.launch(_orb_root(), at, seed_value, length)
	if orb != null:
		_live.append(orb)


func _prune() -> void:
	var kept: Array[GlowOrb] = []
	for orb: GlowOrb in _live:
		if is_instance_valid(orb):
			kept.append(orb)
	_live = kept


## Orbs go in the arena's item container, not under the launcher: an orb is a
## thing in the world with its own life, and parenting it here would make the
## launcher's own transform part of its flight.
func _orb_root() -> Node:
	var root := get_tree().get_first_node_in_group("spawned_items")
	return root if root != null else get_parent()
