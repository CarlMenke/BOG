class_name Pickup
extends Area3D
## Something a Gub left on the ground when it died. Walk over it and it is
## yours.
##
## Everything a Gub gains now comes from a corpse (D-032). `MatchState` rolls
## one of these per death and spawns it at the death point; this is the thing
## that then sits there, glows, and eventually rots.
##
## Four kinds, and only two of them are stock. A mushroom or a lure goes into
## `GubCombat`'s stock, a letter goes into `MatchState.stats` and is never lost
## again (D-033), and the Elder's robe buys the Gub that walked over it twenty
## seconds of being unkillable (D-038, D-040).
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
enum Kind { MUSHROOM, LURE, LETTER, ELDER_ROBE }

const MUSHROOM_MODEL := preload("res://art/generated/mushroom.glb")
const LURE_MODEL := preload("res://art/generated/lure.glb")
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
## readable at a glance from a few metres. That is a label and a light, not a
## model — there is no card mesh in `art/generated/` and a glyph on a billboard
## is legible at any distance a mesh would be a blob at.
const LETTER_FONT_SIZE := 160
const LETTER_PIXEL_SIZE := 0.0042
const LETTER_OUTLINE := 26
const LETTER_COLOUR := Color(1.00, 0.84, 0.26)
const MUSHROOM_COLOUR := Color(0.92, 0.52, 0.44)
const LURE_COLOUR := Color(0.55, 0.85, 1.00)
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


## The letter itself: one glyph, billboarded, with an outline thick enough to
## survive being seen against grass, a sunlit container, or the sky.
##
## Unshaded on purpose — a card whose brightness depends on which side of the
## island it landed on is a card you can miss.
##
## **Static and public, because the card has two homes.** `HeldSpear` builds one
## of these into a Gub's fist for the length of a letter hold (D-035), and a
## card in the hand that was drawn any differently from the card on the ground
## would read as a second kind of object rather than as the one that was just
## picked up. One builder is what stops the two drifting apart the first time
## either colour is adjusted.
static func build_card(of_letter: int) -> Node3D:
	var label := Label3D.new()
	label.text = MatchState.letter_name(of_letter)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = false
	label.font_size = LETTER_FONT_SIZE
	label.outline_size = LETTER_OUTLINE
	label.outline_modulate = Color(0.02, 0.03, 0.04, 0.9)
	label.pixel_size = LETTER_PIXEL_SIZE
	label.modulate = LETTER_COLOUR
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.shaded = false
	label.double_sided = true
	# Occluded like anything else. A letter visible through a hill would tell
	# you where every fight on the map just ended.
	label.no_depth_test = false
	return label


func _tint() -> Color:
	match kind:
		Kind.LETTER:
			return LETTER_COLOUR
		Kind.LURE:
			return LURE_COLOUR
		Kind.ELDER_ROBE:
			return ROBE_COLOUR
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
	# A billboarded glyph is already facing you; spinning it does nothing but
	# cost a matrix. The robe turns at a third of the rate — it is a tall object
	# with a front, and a wizard's hat revolving at mushroom speed is a joke the
	# map only wants to make once.
	if kind == Kind.ELDER_ROBE:
		_model.rotate_y(SPIN_SPEED * ROBE_SPIN_SCALE * delta)
	elif kind != Kind.LETTER:
		_model.rotate_y(SPIN_SPEED * delta)
	if _age >= LIFETIME:
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
