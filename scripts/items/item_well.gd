class_name ItemWell
extends Node3D
## A pedestal in the practice range that always has one item on it.
##
## The range's answer to "I want to practise the shield twenty times in a row"
## without lying about the game's cadence (PLAN_RANGE, "Items and loadout"). It
## is not a new kind of item and it grants nothing: it *places a real drop* —
## the same `Pickup` a corpse leaves, through the same
## `MatchState.place_pickup` — and puts another one there a few seconds after
## somebody takes it. Everything a player then does with it is the normal
## walk-over path, decided by the host in `claim_pickup` like every other drop.
##
## **`keeps` is the whole reason unit 1 added a passthrough.** A placed drop is
## furniture rather than loot: without the flag `Pickup.LIFETIME` would rot the
## stock after thirty seconds, and a rotted item never emits `pickup_taken`, so
## the pedestal would stand empty for the rest of the match with nothing to
## re-mint on.
##
## **Host places, everybody draws.** The mint and the timer run on the host
## only. The glow does not need to be told anything, because the thing it is
## about — whether there is a `Pickup` standing here — is *already* the same on
## every machine: `_spawn_pickup` and `_take_pickup` are both RPCs that run
## everywhere. So each peer reads its own copy of the world and gets the right
## answer. A host broadcast of "stocked"/"empty" would be a second opinion about
## a question the first opinion already answers, which is the shape of bug D-024
## exists because of.

## How long after a well is emptied before the next one appears, per kind.
##
## Short, because the point of a well is repetition, and long enough that the
## item is a thing you went and got rather than a thing you are standing in. The
## shield and the magnet are four seconds because they are the two abilities
## with a use cooldown of their own — you cannot spend them faster than that
## anyway. The potion is six because a drink is a two-second channel and a
## bottomless supply of them would make the healing decision (D-067) free.
##
## The robe is twenty, which is `elder_duration`: one robe on the pedestal at a
## time, and a player who wants to be the Elder again waits roughly as long as
## being the Elder lasted. Any faster and the range's ability yard is a place
## where somebody is permanently unkillable (D-040), which is a different game
## rather than practice at this one.
const DELAY := {
	Pickup.Kind.SHIELD: 4.0,
	Pickup.Kind.MAGNET: 4.0,
	Pickup.Kind.POTION: 6.0,
	Pickup.Kind.ELDER_ROBE: 20.0,
}

## The marker meta's `kind` string, as `range_map.gd`'s `WELLS` table spells it.
const KINDS := {
	"shield": Pickup.Kind.SHIELD,
	"magnet": Pickup.Kind.MAGNET,
	"potion": Pickup.Kind.POTION,
	"robe": Pickup.Kind.ELDER_ROBE,
}

## The ability tiles the HUD already uses, so the pedestal's face is the same
## picture as the slot the item will land in. There is no robe tile —
## `tools/bake_tiles.gd` bakes the seven props in `art/generated/` and the robe
## is a `.tscn` with a skeleton in it, not a prop — so that one pedestal gets a
## word instead. A word is better there than a wrong picture.
const TILES := {
	Pickup.Kind.SHIELD: "res://resources/ui/tiles/shield.png",
	Pickup.Kind.MAGNET: "res://resources/ui/tiles/magnet.png",
	Pickup.Kind.POTION: "res://resources/ui/tiles/heal_potion.png",
}

const LABELS := {
	Pickup.Kind.SHIELD: "SHIELD",
	Pickup.Kind.MAGNET: "MAGNET",
	Pickup.Kind.POTION: "POTION",
	Pickup.Kind.ELDER_ROBE: "ELDER ROBE",
}

## The pedestal. Waist high, so the item on it is at chest height and reads
## against the sky rather than against the ground.
const PEDESTAL_HEIGHT := 0.95
const PEDESTAL_RADIUS := 0.42
## Where the drop is placed, above the pedestal's own origin. `Pickup` adds its
## own `HOVER` on top of whatever it is given.
const STOCK_LIFT := 0.95

## How close a `Pickup` has to be to count as this well's stock. Generous enough
## to survive the robe's lower hang (`Pickup.ROBE_DROP`) and tight enough that
## two wells three metres apart never claim each other's.
const STOCK_RADIUS := 0.9

## How often a peer that has lost sight of its stock looks for it again. Only
## runs while the well believes it is empty, and only walks the spawned-items
## container, so this is a few dozen comparisons a second across the whole map.
const SCAN_PERIOD := 0.25

const FULL_ENERGY := 2.2
const EMPTY_ENERGY := 0.55
const FADE_TIME := 0.35

var kind: Pickup.Kind = Pickup.Kind.SHIELD

## The id the host minted, or 0. Host only — a client never learns it and does
## not need to, which is the point of reading the world instead.
var _pickup_id: int = 0
## When to mint next, in seconds on this node's own clock, or -1.0 for "not
## waiting". Host only.
var _mint_at: float = -1.0
var _clock: float = 0.0
var _scan_at: float = 0.0
## This peer's copy of the item standing here, or null. Every peer keeps one.
var _stock: Pickup
var _light: OmniLight3D
var _lit: bool = true
var _armed: bool = false


static func kind_from_meta(text: String) -> Pickup.Kind:
	return KINDS.get(text, Pickup.Kind.SHIELD)


func _ready() -> void:
	_build()
	# Placing needs `phase == PLAYING` — `claim_pickup` refuses anything else,
	# so an item minted during WARMUP would be one nobody could pick up. The
	# range reaches PLAYING almost immediately (practice has no warmup), but
	# "almost" is the word that makes this a signal rather than an assumption.
	MatchState.phase_changed.connect(_on_phase_changed)
	MatchState.pickup_taken.connect(_on_pickup_taken)
	if MatchState.phase == MatchState.Phase.PLAYING:
		_arm()


func _on_phase_changed(phase: int) -> void:
	if phase == MatchState.Phase.PLAYING:
		_arm()
	else:
		# A match that ended took every pickup with it (`MatchState.reset`
		# clears the index and the arena sweeps the nodes), so the id this well
		# is holding is about to mean nothing. Dropped rather than kept, so a
		# second match does not wait on a `pickup_taken` that can never come.
		_armed = false
		_pickup_id = 0
		_mint_at = -1.0


func _arm() -> void:
	if _armed:
		return
	_armed = true
	_mint()


## Host only. Put one item on the pedestal now.
func _mint() -> void:
	if not Net.is_host or not _armed:
		return
	_mint_at = -1.0
	_pickup_id = MatchState.place_pickup(kind, global_position + Vector3.UP * STOCK_LIFT, true)


## Somebody took a drop somewhere. Ours?
##
## Runs on every peer because the RPC behind it does, and does nothing anywhere
## but the host — the id is the host's and a client's `_pickup_id` is always 0,
## which no real id ever is (`_next_pickup_id` starts at 1).
func _on_pickup_taken(id: int, _of_kind: int, _by_peer: int) -> void:
	if id != _pickup_id or _pickup_id == 0:
		return
	_pickup_id = 0
	_mint_at = _clock + float(DELAY.get(kind, 4.0))


## Unit 3's station reset. Host only, and idempotent: a well that is already
## stocked is left exactly as it is, because putting a second item on a full
## pedestal would be two drops inside one catch volume.
func restock() -> void:
	if not Net.is_host:
		return
	if is_instance_valid(_stock) and not _stock.is_taken():
		_mint_at = -1.0
		return
	_mint()


## Whether there is an item standing here, on this peer's reading of the world.
func is_stocked() -> bool:
	return is_instance_valid(_stock) and not _stock.is_taken()


func _process(delta: float) -> void:
	_clock += delta
	if Net.is_host and _mint_at >= 0.0 and _clock >= _mint_at:
		_mint()
	_track_stock(delta)


## Find, or lose, this peer's copy of the item on the pedestal.
##
## Cached hard: while the reference is good this is one `is_instance_valid` and
## one boolean a frame. The scan only happens while the well believes it is
## empty, which is the few seconds between somebody taking the stock and the
## next one arriving.
func _track_stock(delta: float) -> void:
	if is_instance_valid(_stock) and not _stock.is_taken():
		_set_lit(true)
		return
	_stock = null
	_set_lit(false)
	_scan_at -= delta
	if _scan_at > 0.0:
		return
	_scan_at = SCAN_PERIOD
	var root := get_tree().get_first_node_in_group("spawned_items")
	if root == null:
		return
	var want := global_position + Vector3.UP * STOCK_LIFT
	for child in root.get_children():
		var item := child as Pickup
		if item == null or item.is_taken() or item.kind != kind:
			continue
		# Against the spot the drop was *placed* at rather than against the
		# node's position, because `Pickup.drop` lifts itself by `HOVER` and the
		# robe by less (`ROBE_DROP`). The horizontal distance is what identifies
		# a pedestal's own stock anyway — two wells are three metres apart and
		# nothing else is ever within a metre of one.
		if Vector2(item.global_position.x - want.x,
				item.global_position.z - want.z).length() > STOCK_RADIUS:
			continue
		_stock = item
		_set_lit(true)
		return


func _set_lit(lit: bool) -> void:
	if lit == _lit or _light == null:
		return
	_lit = lit
	var fade := create_tween()
	fade.tween_property(_light, "light_energy",
		FULL_ENERGY if lit else EMPTY_ENERGY, FADE_TIME)


# ------------------------------------------------------------------ visual ---

func _build() -> void:
	var tint: Color = _tint()

	var stone := StandardMaterial3D.new()
	# The map's own stone, by value rather than by reference: `RangeMap` builds
	# its materials into private fields and a pedestal that fetched them would
	# be a second file that breaks when unit 2 renames one.
	stone.albedo_color = Color(0.52, 0.53, 0.47)
	stone.roughness = 0.82
	stone.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	var column := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(PEDESTAL_RADIUS * 2.0, PEDESTAL_HEIGHT, PEDESTAL_RADIUS * 2.0)
	column.mesh = box
	column.material_override = stone
	column.position = Vector3(0.0, PEDESTAL_HEIGHT * 0.5, 0.0)
	# Turned an eighth, so a square pedestal reads as an eight-sided one from
	# the deck and its corner does not line up with the lodge behind it.
	column.rotate_y(PI * 0.25)
	add_child(column)

	# A rim in the item's own colour, which is what makes four identical
	# pedestals in a row tellable apart from the far end of the deck.
	var rim := MeshInstance3D.new()
	var rim_box := BoxMesh.new()
	rim_box.size = Vector3(PEDESTAL_RADIUS * 2.2, 0.08, PEDESTAL_RADIUS * 2.2)
	rim.mesh = rim_box
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = tint
	rim_mat.emission_enabled = true
	rim_mat.emission = tint
	rim_mat.emission_energy_multiplier = 1.4
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim.mesh.surface_set_material(0, rim_mat)
	rim.position = Vector3(0.0, PEDESTAL_HEIGHT - 0.04, 0.0)
	rim.rotate_y(PI * 0.25)
	add_child(rim)

	# Solid, on the world layer, so it is furniture you walk up to rather than
	# through. Added after the map's `super()` by `RangeItems`, so it is a
	# runtime body and is invisible to the collision bake and to the parkour
	# report — which is correct: neither is about the props.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var solid := BoxShape3D.new()
	solid.size = box.size
	shape.shape = solid
	shape.position = Vector3(0.0, PEDESTAL_HEIGHT * 0.5, 0.0)
	body.add_child(shape)
	body.rotate_y(PI * 0.25)
	add_child(body)

	_build_face(tint)

	_light = OmniLight3D.new()
	_light.light_color = tint
	_light.light_energy = FULL_ENERGY
	_light.omni_range = 5.5
	_light.position = Vector3(0.0, PEDESTAL_HEIGHT + 0.5, 0.0)
	add_child(_light)


## The kind's picture on the front of the pedestal, facing the way the marker
## faces (its own -Z, per `range_map.gd`'s header).
func _build_face(tint: Color) -> void:
	var path: String = TILES.get(kind, "")
	if path != "":
		var sprite := Sprite3D.new()
		sprite.texture = load(path)
		sprite.pixel_size = 0.0017
		sprite.position = Vector3(0.0, PEDESTAL_HEIGHT * 0.62, -PEDESTAL_RADIUS - 0.02)
		sprite.modulate = Color(1.0, 1.0, 1.0)
		# Lit from inside, like every other thing this map asked you to read at
		# night (D-058): a picture that depends on a torch being near it is a
		# picture nobody can see across a 90 m map. The range is daylit now and
		# the rule still holds — a well is read from the far end of a lane.
		sprite.shaded = false
		sprite.double_sided = false
		add_child(sprite)

	var label := Label3D.new()
	label.text = LABELS.get(kind, "ITEM")
	label.font_size = 48
	label.pixel_size = 0.0032
	label.modulate = tint
	label.outline_size = 14
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.position = Vector3(0.0, PEDESTAL_HEIGHT + 0.16, -PEDESTAL_RADIUS - 0.02)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = false
	add_child(label)


## The drop's own glow colour, so the pedestal and the thing standing on it are
## the same colour from across the map. Straight off `Pickup`, not copied.
func _tint() -> Color:
	match kind:
		Pickup.Kind.MAGNET:
			return Pickup.MAGNET_COLOUR
		Pickup.Kind.POTION:
			return Pickup.POTION_COLOUR
		Pickup.Kind.ELDER_ROBE:
			return Pickup.ROBE_COLOUR
		_:
			return Pickup.SHIELD_COLOUR
