class_name Pickup
extends Area3D
## Something a Gub left on the ground when it died. Walk over it and it is
## yours.
##
## Everything a Gub gains now comes from a corpse (D-032). `MatchState` rolls
## one of these per death and spawns it at the death point; this is the thing
## that then sits there, glows, and eventually rots.
##
## Five kinds, and three of them are stock. A mushroom, a lure or a heal potion
## goes into `GubCombat`'s stock, a letter goes into `MatchState.stats` and is
## never lost again (D-033), and the Elder's robe buys the Gub that walked over
## it twenty seconds of being unkillable (D-038, D-040).
##
## **Collection is walk-over, not a keypress.** There is no interact action
## bound in this project and adding one to pick up a thing you are standing on
## would be a key press that only ever has one answer. The `Area3D` is on the
## player layer and the first *living* Gub to touch it takes it.
##
## **The host decides who got it.** The overlap that matters is the host's; a
## client's copy of this node monitors nothing and is told the answer. Which is
## also why the collect message is not sent from here: an RPC is addressed by
## node **path**, and a spawned item has no path two machines agree on — every
## peer builds its own copy into `spawned_items` and Godot disambiguates the
## duplicate name with a counter local to that process. That is the bug D-024
## exists because of. So `MatchState` hands out an integer id at spawn time and
## both messages travel on the autoload, which is `/root/MatchState` everywhere.

## Appended to, never reordered, for the reason `MatchConfig.WinCondition`
## gives: the ordinal is what `_spawn_pickup` puts on the wire, and inserting a
## kind in the middle would turn every drop already in flight into a different
## object on the far end.
enum Kind { MUSHROOM, LURE, LETTER, ELDER_ROBE, POTION }

const MUSHROOM_MODEL := preload("res://art/generated/mushroom.glb")
const LURE_MODEL := preload("res://art/generated/lure.glb")
const POTION_MODEL := preload("res://art/generated/heal_potion.glb")
## The robe itself, instanced in its rest pose. It carries a copy of the Gub's
## skeleton (D-037) and no animation, so what stands on the grass is a robe and
## hat with nobody in them — which is exactly the right picture for a garment
## lying where its owner died.
const ROBE_MODEL := preload("res://art/generated/elder.glb")

const LAYER_PLAYER := 2

## How long an uncollected drop survives. A constant rather than a config dial
## because it is a litter rule and not a balance one: eight players killing each
## other for ten minutes leaves a hundred and fifty items, and the only question
## is how long the map stays legible. Roughly a mushroom's life, which is the
## other number in the game that answers "how long does a thing left on the
## ground last".
const LIFETIME := 30.0

## Both ends of the life are animated rather than instant, for the same reason a
## mushroom erupts and withers: an item that blinks into existence is one nobody
## noticed arriving, and one that blinks out is one somebody thinks they saw
## stolen.
const GROW_TIME := 0.30
const WITHER_TIME := 0.40
## How far above the ground point the item floats, so it reads as a thing lying
## on the grass rather than a thing buried in it.
const HOVER := 0.55
## The robe hangs lower than the rest, because unlike a mushroom or a crystal it
## is a *full-height* object — 2.06 m of robe and hat at its own scale — and one
## floating with 0.55 m of clear air under its hem reads as a ghost rather than
## as a garment. Subtracted from HOVER rather than given as an absolute, so
## moving the float height moves all four together.
const ROBE_DROP := 0.40
## Bob and spin. Small — this is scenery until you are near it, and a drop that
## windmills is the most distracting object on the island.
const BOB_HEIGHT := 0.11
const BOB_SPEED := 2.2
const SPIN_SPEED := 1.1
const ROBE_SPIN_SCALE := 0.33

## The catch radius. Generous on purpose: it is a thing on the floor, and a
## player who ran over it and did not get it will read that as the pickup being
## broken rather than as their feet missing by 30 cm.
const CATCH_RADIUS := 1.15
const CATCH_HEIGHT := 2.2

## How big the robe stands on the ground. The source is fitted to a 1.80 m Gub
## and would be a second Gub standing in the clearing at 1.0 — which is a
## genuinely confusing thing to leave on a battlefield. A third of that is a
## garment on a stand: unmistakably the robe, unmistakably not a person.
const ROBE_SCALE := 0.34

## Letter cards are what players sprint across the map for, so they have to be
## readable at a glance from a few metres. That used to argue for a glyph on a
## billboard, and the reason it gave was the honest one: there was no card mesh
## in `art/generated/`. There is one per letter now (D-041), out of the same
## pipeline the spear and the lure come through, so what is lying in the grass
## is the letter rather than a picture of one.
const LETTER_G_MODEL := preload("res://art/generated/letter_g.glb")
const LETTER_U_MODEL := preload("res://art/generated/letter_u.glb")
const LETTER_B_MODEL := preload("res://art/generated/letter_b.glb")
## How tall a letter stands on the ground, in metres. The sources are exactly
## one metre with the origin at the base, so this is also the scale.
##
## 0.60 and not the glyph's 0.47, for two reasons that point the same way. A
## shaded solid has less presence at a given height than an outlined, unshaded
## glyph does — it is lit like the world instead of shouting over it — and the
## other things that fall out of a corpse stand 0.5 to 0.7 m (the lure 0.49, the
## robe 0.70). At the glyph's height a card would be the one drop on the map
## that reads as smaller than the rest of them. This one sits among them.
const LETTER_HEIGHT := 0.60
## How much of its own colour a letter emits, 0..1.
const LETTER_SELF_LIGHT := 0.7
const LETTER_COLOUR := Color(1.00, 0.84, 0.26)
const MUSHROOM_COLOUR := Color(0.92, 0.52, 0.44)
const LURE_COLOUR := Color(0.55, 0.85, 1.00)
## The potion's own purple, taken up out of the glass the way ROBE_COLOUR was
## taken up out of the cloth: `#8040A0` is the single most common colour in
## `heal_potion_basecolor.png`, and this is that hue at full value.
##
## **It lands within a tenth of the robe's violet, and that is not a mistake to
## be corrected.** The potion stays purple — that is the decision behind this
## feature, and there is no mana in this game for it to be confused with — so a
## light invented in some other hue would be a glow that does not belong to the
## thing casting it. What separates the two on the ground is the **tier** rather
## than the colour: a robe burns at 3.4 over 8.5 m and is visible across a
## clearing, a potion at 1.5 over 4.0 m and is not visible until you are nearly
## standing on it. By the time the two are confusable you can see that one is a
## bottle and the other is a robe with a hat on it.
const POTION_COLOUR := Color(0.80, 0.40, 1.00)
## The robe's own violet, taken up out of the cloth rather than matched to it.
## `#2F1D45` is the albedo (D-037) and is far too dark to be a light; this is the
## same hue at full value, so the glow on the grass reads as *that* robe and not
## as a fourth arbitrary colour in the drop palette.
const ROBE_COLOUR := Color(0.68, 0.45, 1.00)

## Match-unique, handed out by the host. This is the name both ends agree on —
## see the note in the header about why the node's own path is not.
var pickup_id: int = 0
var kind: Kind = Kind.MUSHROOM
## Which letter, as one of `MatchState.LETTER_G/U/B`. Zero for the other kinds.
var letter: int = 0

var _model: Node3D
var _light: OmniLight3D
var _age: float = 0.0
var _taken: bool = false
## Exempt from `LIFETIME`. See `drop`.
var _keeps: bool = false
## Seeded per drop so two items side by side are not bobbing in lockstep.
var _phase: float = 0.0


## Called on every peer, from `MatchState._spawn_pickup`, with the values the
## host rolled. Everything cosmetic is built here rather than in `_ready`
## because until this runs the node does not know what it is.
func drop(id: int, of_kind: Kind, of_letter: int, spot: Vector3) -> void:
	pickup_id = id
	# Clamped rather than trusted, like every other value that arrives off the
	# wire (see the header of `match_config.gd`). Only the host can send this
	# one, but a kind outside the enum would leave `_build_visual` with no model
	# to add and a SCRIPT ERROR on every client at the same instant. `letter`
	# needs no guard: `MatchState.letter_name` answers "?" to anything it does
	# not recognise.
	kind = clampi(of_kind, 0, Kind.size() - 1) as Kind
	letter = of_letter
	# A Capture G·U·B card never rots (D-051). There are exactly three letters
	# in that match and the host decides when a dropped one goes home, so a
	# card that withered on this clock would be a letter leaving the match — or,
	# on a client, a card that vanished while the host still has it on the
	# ground. Read from the config every peer already shares.
	_keeps = kind == Kind.LETTER \
		and Net.config.win_condition == MatchConfig.WinCondition.CAPTURE
	# The robe sits lower than the others — see ROBE_DROP. The catch volume is
	# built off HOVER regardless, so a drop that hangs differently is still
	# collected by walking over the same patch of ground as every other one.
	global_position = spot + Vector3.UP * (
		HOVER - (ROBE_DROP if kind == Kind.ELDER_ROBE else 0.0))
	_phase = randf() * TAU

	# Nothing collides *with* a pickup — it is not cover and it must not stop a
	# spear. It only watches for Gubs walking through it.
	collision_layer = 0
	collision_mask = LAYER_PLAYER
	# A client's copy never decides anything, so it does not need to watch
	# either. The host's overlap is the only one with an opinion.
	monitoring = Net.is_host
	body_entered.connect(_on_body_entered)
	_build_collision()
	_build_visual()


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = CATCH_RADIUS
	cylinder.height = CATCH_HEIGHT
	shape.shape = cylinder
	# Centred on the ground rather than on the item, so a Gub walking past at
	# foot level is caught by it and one standing on a ledge above is not.
	shape.position = Vector3(0.0, CATCH_HEIGHT * 0.5 - HOVER, 0.0)
	add_child(shape)


func _build_visual() -> void:
	match kind:
		Kind.MUSHROOM:
			_model = MUSHROOM_MODEL.instantiate() as Node3D
			# A quarter the size it will be once planted. It has to read as a
			# spare in your pocket, not as cover somebody already put there.
			_model.scale = Vector3.ONE * 0.32
		Kind.LURE:
			_model = LURE_MODEL.instantiate() as Node3D
			# The source crystal is nearly two metres tall, the same reason
			# `Lure` shrinks it before throwing one.
			_model.scale = Vector3.ONE * 0.26
		Kind.LETTER:
			_model = build_card(letter)
		Kind.ELDER_ROBE:
			_model = ROBE_MODEL.instantiate() as Node3D
			_model.scale = Vector3.ONE * ROBE_SCALE
		Kind.POTION:
			_model = POTION_MODEL.instantiate() as Node3D
			# The source bottle is exactly a metre tall. Half of it puts a
			# potion at 0.50 m, which is the band everything else that falls out
			# of a corpse already stands in — the lure 0.49, the letters 0.60,
			# the robe 0.70 — so it reads as one of the drops rather than as a
			# prop somebody left in the grass.
			_model.scale = Vector3.ONE * 0.50
	add_child(_model)

	# Lit as well as coloured. The island is a night map and half of it is under
	# a tree; a drop nobody can see is a drop nobody collects, and the glow is
	# what carries at the distance the model is four pixels across.
	_light = OmniLight3D.new()
	_light.light_color = _tint()
	# Three tiers, not two, and the robe is the new top one. It is the rarest
	# and strongest thing that drops (D-038) and it has to look like the prize
	# it is from further away than a letter card does — a mushroom is a top-up,
	# a card is a race, and a robe decides the next minute of the match. The
	# whole point of putting one on the ground is that somebody sees it.
	_light.light_energy = _glow_energy()
	_light.omni_range = _glow_range()
	_light.position = Vector3(0.0, 0.35, 0.0)
	add_child(_light)

	# Erupts out of the ground the way a mushroom does. `_model.scale` is the
	# final size, so the tween has to end where the builder above left it.
	var target := _model.scale
	_model.scale = target * 0.05
	var grow := create_tween()
	grow.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	grow.tween_property(_model, "scale", target, GROW_TIME)


## The letter itself: the mesh, at `LETTER_HEIGHT`, lighting itself out of its
## own texture.
##
## **The origin of what comes back is the middle of the letter**, not the foot
## of it, because that is what both callers place by — `_build_visual` hands
## this node to the bob, and `HeldGear` puts it up the shaft — and the glyph
## it replaces was centred too. So the model is pushed down half its own height
## under a pivot rather than the pivot being moved up.
##
## The scale goes on the model and never on the pivot, for those same two
## callers. `HeldGear` *assigns* `_card.scale`, and the grow tween in
## `_build_visual` reads `_model.scale` as the size to end at; a pivot that was
## not scale 1 would be silently multiplied into both of them.
##
## **Lit from inside on purpose**, which is the glyph's argument outliving the
## glyph: a card whose brightness depends on which side of the island it landed
## on is a card you can miss. What it emits is its own albedo rather than a flat
## gold, because the ornament is most of what makes one of these read as a
## letter at four metres — emit a single colour instead and it is a glyph
## again, with worse edges than the glyph had.
##
## **Static and public, because the card has two homes.** `HeldGear` builds one
## of these into a Gub's fist for the length of a letter hold (D-035), and a
## card in the hand that was drawn any differently from the card on the ground
## would read as a second kind of object rather than as the one that was just
## picked up. One builder is what stops the two drifting apart the first time
## either colour is adjusted.
static func build_card(of_letter: int) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "LetterCard"
	var model := _letter_model(of_letter).instantiate() as Node3D
	model.scale = Vector3.ONE * LETTER_HEIGHT
	model.position = Vector3(0.0, -0.5 * LETTER_HEIGHT, 0.0)
	pivot.add_child(model)
	_light_from_within(model)
	return pivot


## Which of the three scenes a letter bit stands for.
##
## Answers a bad one with the G and a warning rather than with nothing. `drop`
## clamps `kind`, because a kind off the wire with no model behind it leaves
## `_build_visual` with nothing to add; a letter cannot be clamped the same way,
## since the bits are 1, 2 and 4 and there is no range to squeeze a stray byte
## into. One card showing the wrong glyph is a far smaller thing than a SCRIPT
## ERROR on every client in the match at the same instant.
static func _letter_model(of_letter: int) -> PackedScene:
	match of_letter:
		MatchState.LETTER_G:
			return LETTER_G_MODEL
		MatchState.LETTER_U:
			return LETTER_U_MODEL
		MatchState.LETTER_B:
			return LETTER_B_MODEL
	push_warning("Pickup: no model for letter %d, showing a G" % of_letter)
	return LETTER_G_MODEL


## Turn every surface of the letter into something that emits its own texture.
##
## The material is duplicated first, and that is not tidiness. An imported
## `.glb` hands the *same* `StandardMaterial3D` to every instance of the scene,
## so setting emission on the one that arrived with the mesh would light every
## other card of that letter on the map — and every one built after it — out
## of whichever copy happened to be made last.
static func _light_from_within(model: Node3D) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for i in mesh.get_surface_override_material_count():
			var mat := mesh.get_active_material(i) as StandardMaterial3D
			if mat == null:
				continue
			mat = mat.duplicate() as StandardMaterial3D
			mat.emission_enabled = true
			mat.emission = Color.WHITE
			mat.emission_texture = mat.albedo_texture
			# MULTIPLY, and this is the whole thing working or not. The default
			# operator *adds* the emission colour to the emission texture, so a
			# white one means a flat white term on top of the gold — which at any
			# energy worth having turns all three letters into cream-coloured
			# blobs. Multiplied, `Color.WHITE` means what it is here to mean: emit
			# the albedo, unaltered, at `LETTER_SELF_LIGHT` of it.
			mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			mat.emission_energy_multiplier = LETTER_SELF_LIGHT
			mesh.set_surface_override_material(i, mat)


func _tint() -> Color:
	match kind:
		Kind.LETTER:
			return LETTER_COLOUR
		Kind.LURE:
			return LURE_COLOUR
		Kind.ELDER_ROBE:
			return ROBE_COLOUR
		Kind.POTION:
			return POTION_COLOUR
		_:
			return MUSHROOM_COLOUR


func _glow_energy() -> float:
	match kind:
		Kind.ELDER_ROBE:
			return 3.4
		Kind.LETTER:
			return 2.4
		_:
			return 1.5


func _glow_range() -> float:
	match kind:
		Kind.ELDER_ROBE:
			return 8.5
		Kind.LETTER:
			return 6.0
		_:
			return 4.0


func _process(delta: float) -> void:
	if _taken or _model == null:
		return
	_age += delta
	# Bobbing is applied to the child, not to this node, so the catch volume
	# stays where it was put. An item whose hitbox rides up and down with it
	# would be collectable on half the frames.
	_model.position.y = sin(_age * BOB_SPEED + _phase) * BOB_HEIGHT
	# Letters turn now, like everything else. The glyph did not, and was right
	# not to: a billboard is already facing you and spinning one costs a matrix
	# for nothing. A mesh is the other case — it has a front and a back, and a
	# letter seen from behind is a mirrored letter — so turning it is what makes
	# it readable from whichever side you came at it from, and it is what a thing
	# lying on the ground waiting to be collected has always done. The robe keeps
	# its third of the rate: it is a tall object with a front, and a wizard's hat
	# revolving at mushroom speed is a joke the map only wants to make once.
	if kind == Kind.ELDER_ROBE:
		_model.rotate_y(SPIN_SPEED * ROBE_SPIN_SCALE * delta)
	else:
		_model.rotate_y(SPIN_SPEED * delta)
	if _age >= LIFETIME and not _keeps:
		wither()


## Host only, and only ever from the host's own overlap. Everything this decides
## is decided again in `MatchState.claim_pickup` — this is the *notice*, not the
## award.
func _on_body_entered(body: Node3D) -> void:
	if _taken or not Net.is_host:
		return
	var gub := body as Gub
	if gub == null or not gub.alive:
		return
	MatchState.claim_pickup(pickup_id, gub.peer_id)


func is_taken() -> bool:
	return _taken


## The host has ruled that `peer_id` got this. Runs on every peer.
##
## The item leaves whether or not it was worth anything: a duplicate letter is
## consumed exactly like a new one (D-033), because a card that refuses to be
## picked up is a card three players take turns walking over.
func take(peer_id: int) -> void:
	if _taken:
		return
	_taken = true
	_stop_monitoring()
	# Feedback for the collector alone, and borrowed rather than invented: there
	# is no pickup sound in `audio/sfx/` and `tools/make_sfx.py` is where a new
	# one would have to come from. `SPEAR_READY` already means "you have
	# something you did not have a second ago", which is exactly this.
	if peer_id == Net.local_id():
		AudioDirector.play_2d(AudioDirector.SPEAR_READY)
	_vanish(0.22, Vector3.UP * 1.1)


## Rot, uncollected. Visibly, rather than blinking out — a drop that disappears
## on its own the instant you reach it reads as somebody else having taken it.
func wither() -> void:
	if _taken:
		return
	_taken = true
	_stop_monitoring()
	_vanish(WITHER_TIME, Vector3.ZERO)


## Stop watching for Gubs, on the next idle frame rather than now.
##
## `take` is reached from inside `body_entered`, and Godot refuses to change
## `monitoring` while an area is dispatching its own enter/exit signals — it
## would be re-entering the physics server mid-callback. Deferring is the
## documented answer and costs nothing here, because the thing that actually
## makes a drop collectable once is `_taken`, which is set synchronously above:
## a second Gub entering on the same frame is refused by the flag long before
## the monitoring flag catches up.
func _stop_monitoring() -> void:
	set_deferred("monitoring", false)


func _vanish(duration: float, rise: Vector3) -> void:
	if _model == null:
		queue_free()
		return
	var fade := create_tween()
	fade.set_parallel(true)
	fade.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	fade.tween_property(_model, "scale", Vector3.ZERO, duration)
	if rise != Vector3.ZERO:
		fade.tween_property(_model, "position", _model.position + rise, duration)
	if _light != null:
		fade.tween_property(_light, "light_energy", 0.0, duration)
	fade.chain().tween_callback(queue_free)
