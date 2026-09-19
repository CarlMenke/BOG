class_name WeaponRack
extends Area3D
## A rack in the practice range. Walk into it and that is what you are carrying
## now.
##
## The one thing in the range that reaches into a match rule rather than adding
## furniture to a map, and the rule turned out to be smaller than it looked.
## D-069 says a weapon is fixed when the host presses Start — but that is a rule
## of the *lobby*: `Bog.weapon` is a plain field, `BogCombat.carries()` re-reads
## it every time it is asked, `HeldGear` keeps all four models loaded and only
## toggles their visibility, and `BogCombat.refresh_hand()` has been public
## since D-070 precisely because the lobby ring swaps weapons under a standing
## Bog. So the rack is a walk-over that calls one host-side function.
##
## **`MatchState.set_weapon`, and pointedly not `Net.set_weapon`.** That one is
## a client asking for a weapon and is refused while `match_running`, which is
## D-069's lock-in and must stay exactly as it is — loosening it to let a rack
## through would have opened the lobby's route on every map in the game. The
## rack goes through the host *deciding*, which writes the roster row so a
## respawn keeps the weapon and broadcasts a per-Bog message so every peer's
## copy agrees.
##
## **Walk-over, not a keypress**, for `Pickup`'s reason: there is no interact
## action bound in this project, and a key that only ever has one answer is not
## a choice. The host's overlap is the only one that decides anything.

## The marker meta's `weapon` string, as `range_map.gd`'s `RACKS` table spells
## it, to a `Loadout.Weapon`.
const WEAPONS := {
	"spear": Loadout.Weapon.SPEAR,
	"bow": Loadout.Weapon.BOW,
	"sword": Loadout.Weapon.SWORD,
}

## The tile for the plank, by weapon ordinal. The same pictures the ability bar
## uses, so the rack and the HUD slot are one object seen twice.
const TILES := [
	"res://resources/ui/tiles/spear.png",
	"res://resources/ui/tiles/bow.png",
	"res://resources/ui/tiles/greatsword.png",
]

## How long before the same player can change weapon again. The same two seconds
## the refill stone uses, and for a plainer reason: three racks stand a metre
## apart and a player running past all three would otherwise arrive at the lanes
## carrying whichever one they happened to clip last.
const COOLDOWN := 2.0

const POST_HEIGHT := 2.05
const POST_THICK := 0.13
## How far apart the two uprights stand. The weapon hangs between them.
const SPAN := 1.15
const CROSS_HEIGHT := 1.55
## Where the weapon model hangs, and how big it is drawn. Half again over the
## held scale, because a rack is read from across the deck and a great sword at
## its fist size is a twig at ten metres.
const DISPLAY_LIFT := 1.05
const DISPLAY_SCALE := 1.35

const TIMBER := Color(0.23, 0.175, 0.125)
const GLOW := Color(1.0, 0.78, 0.40)

var weapon: int = Loadout.Weapon.SPEAR

## Per peer, the earliest clock this rack will serve them again. Host only.
var _next_ok: Dictionary = {}
var _clock: float = 0.0
var _model: Node3D


static func weapon_from_meta(text: String) -> int:
	return WEAPONS.get(text, Loadout.Weapon.SPEAR)


func _ready() -> void:
	collision_layer = 0
	collision_mask = Pickup.LAYER_PLAYER
	# The host's overlap is the only one with an opinion, exactly as a `Pickup`'s
	# is — a client's copy of this node decides nothing and is told the answer
	# by `MatchState._do_set_weapon`. Unlike the refill stone, there is nothing
	# a client needs the overlap *for*: the swap's feedback is the weapon
	# appearing in the hand, which arrives on the same message.
	monitoring = Net.is_host
	body_entered.connect(_on_body_entered)
	_build()


func _process(delta: float) -> void:
	_clock += delta


func _on_body_entered(body: Node3D) -> void:
	if not Net.is_host:
		return
	var bog := body as Bog
	if bog == null or not bog.alive:
		return
	# Already carrying it. Silently nothing — not a refused action, just a
	# player walking past a rack holding what the rack holds.
	if bog.weapon == weapon:
		return
	if _clock < float(_next_ok.get(bog.peer_id, -1.0)):
		return
	_next_ok[bog.peer_id] = _clock + COOLDOWN
	MatchState.set_weapon(bog.peer_id, weapon)
	# Played from the rack on the host, and on every other peer by the same
	# overlap never happening there — so this is the one piece of the swap that
	# is not replicated, and it is deliberately the cheap one. A client hears
	# its own swap through `SPEAR_READY`, which `_tick_hand` already rings on
	# the frame a weapon lands in a hand, on the peer it belongs to.
	AudioDirector.play_3d(AudioDirector.RACK_SWAP, global_position)


# ------------------------------------------------------------------ visual ---

func _build() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SPAN + 0.6, 2.4, 1.1)
	shape.shape = box
	shape.position = Vector3(0.0, 1.2, 0.0)
	add_child(shape)

	var timber := StandardMaterial3D.new()
	timber.albedo_color = TIMBER
	timber.roughness = 0.9
	timber.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(POST_THICK, POST_HEIGHT, POST_THICK)
		post.mesh = post_mesh
		post.material_override = timber
		post.position = Vector3(side * SPAN * 0.5, POST_HEIGHT * 0.5, 0.0)
		add_child(post)

	var cross := MeshInstance3D.new()
	var cross_mesh := BoxMesh.new()
	cross_mesh.size = Vector3(SPAN + POST_THICK, POST_THICK * 0.8, POST_THICK * 0.8)
	cross.mesh = cross_mesh
	cross.material_override = timber
	cross.position = Vector3(0.0, CROSS_HEIGHT, 0.0)
	add_child(cross)

	# Solid uprights, so the rack is a thing on the deck rather than a hologram
	# you walk through. The `Area3D` above is wider than the posts, so the swap
	# fires as you reach it and not as you bump it.
	var body := StaticBody3D.new()
	for side in [-1.0, 1.0]:
		var solid := CollisionShape3D.new()
		var solid_box := BoxShape3D.new()
		solid_box.size = Vector3(POST_THICK, POST_HEIGHT, POST_THICK)
		solid.shape = solid_box
		solid.position = Vector3(side * SPAN * 0.5, POST_HEIGHT * 0.5, 0.0)
		body.add_child(solid)
	add_child(body)

	_build_display()
	_build_plank()


## The weapon itself, hanging on the rack.
##
## Instanced from `HeldGear`'s own preloads, so the thing on the rack is the
## thing that ends up in the fist rather than a second model of it that drifts
## the first time either is re-exported.
func _build_display() -> void:
	var scene: PackedScene = _model_scene()
	if scene == null:
		return
	_model = scene.instantiate() as Node3D
	if _model == null:
		return
	_model.scale = Vector3.ONE * DISPLAY_SCALE
	_model.position = Vector3(0.0, DISPLAY_LIFT, 0.0)
	# Laid across the rack rather than stood up in it: every one of the three is
	# a long object with its length on +Y at rest, and three weapons standing
	# upright in a row read as fence posts. Turned a little out of square so the
	# blade catches the lodge's torches.
	_model.rotate_z(PI * 0.5)
	_model.rotate_y(deg_to_rad(12.0))
	add_child(_model)


func _model_scene() -> PackedScene:
	match weapon:
		Loadout.Weapon.BOW:
			return HeldGear.BOW_MODEL
		Loadout.Weapon.SWORD:
			return HeldGear.SWORD_MODEL
		_:
			return HeldGear.MODEL


## The name on the plank, and the tile beside it, both on the rack's own **-Z**
## face — the facing every marker group in the game is authored in (D-166).
##
## A `Label3D` and a `Sprite3D` each face their own +Z, so a plank hung on the
## -Z side without the turn shows the deck its back: the label is double-sided
## by default and renders the name mirrored, the sprite is not and is simply not
## drawn. `signboard.gd` has turned its own label for this reason since it was
## written; these two did not, and the map turned the racks the wrong way round
## to make up for it (D-161). The turn belongs here, where the face is built.
func _build_plank() -> void:
	var label := Label3D.new()
	label.text = Loadout.NAMES[Loadout.sanitize(weapon)].to_upper()
	label.font_size = 44
	label.pixel_size = 0.0030
	label.modulate = GLOW
	label.outline_size = 14
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.position = Vector3(0.0, 0.42, -0.12)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.rotation.y = PI
	add_child(label)

	var tile := Sprite3D.new()
	tile.texture = load(TILES[Loadout.sanitize(weapon)])
	tile.pixel_size = 0.0016
	tile.position = Vector3(0.0, 1.88, -0.10)
	tile.shaded = false
	tile.double_sided = false
	tile.rotation.y = PI
	add_child(tile)
