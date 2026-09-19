class_name MenuLetters
extends Node3D
## The word B·O·G itself, floating over the campfire: three of the same letter
## cards that drop out of a corpse in a match, at menu size.
##
## It replaces a `Label` that said "BOG" in 148 px of display type. The owner's
## words were *"remove the GUI BOG letters from the menu, replace them with the
## real, floating, gently bobbing real asset letters"*, and the argument behind
## them is the one the whole backdrop is built on (D-011, D-111): the menu is
## not a picture of the game, it is the game with a UI in front of it. A
## wordmark drawn by the UI is the one thing on that screen that could not
## possibly be in the match. These three can — they are `Pickup.build_card`,
## the same builder the ground card and the fist card come out of, so the first
## letter a player ever sees is the object they will be racing for ten minutes
## later.
##
## **One rig, one size, both formations.** The menu camera stands 7.3 m off at
## 24 degrees and these are the wordmark; the lobby camera stands 10 m off at
## 36 and the same three letters are a trinket over the fire. Nothing here
## knows which screen it is on, and that is what makes the owner's *"same scale
## relationship to the campfire in both"* true by construction rather than by
## two numbers somebody has to keep equal.
##
## The composition around it was solved the way D-117 and D-118 solved the
## menu's layout: on paper first, through the camera's own projection, and then
## measured on every run — `tools/ui_range.gd`'s `menu_letters` and
## `lobby_letters` print where the row actually landed.

## How tall one glyph stands, in metres. 0.85 against the card's own 0.60 in a
## match (`Pickup.LETTER_HEIGHT`) — bigger than the thing on the ground,
## because this one is a wordmark over a fire rather than a prize in the grass,
## and because 0.85 m at the menu's lens is 256 px of glyph where the label it
## replaces was about 105 px of cap height. The scale goes on the **pivot** and
## never on the card: `Pickup.build_card` already scales the model and says in
## its own comment why a second multiply there is a bug.
const LETTER_WORLD_HEIGHT := 0.85

## Air between one glyph's box and the next, in metres. 0.25 is a little under
## a third of a letter, which is wide tracking for type and about right for
## three objects that are meant to read as three objects rather than as a word
## welded together — they bob independently, and letters that nearly touch at
## rest collide when they do.
const LETTER_GAP := 0.25

## How high the row's centre floats above the parent, in metres. The parent is
## the `Fire` node, so this is height over the fire's own origin.
##
## **1.35 is where two constraints meet**, and they come from different
## screens:
##
##   the floor — the flame tops out at 0.813 m: the campfire model at
##     `BogBackdrop.FIRE_MODEL_SCALE`, and 0.66 m before D-138, while the flame
##     was two cones whose tips were chosen to stay out of the way. The bottom
##     of a glyph sits at `1.35 - 0.425 - 0.05` = 0.875 m, which is 0.062 m of
##     air over the tallest flame at the lowest point of the bob — close enough
##     to read as hovering over the fire and still clear of it. It was a
##     quarter of a letter's height under the cones, and the model is what
##     spent it; the scale is the constant that gives it back.
##   the ceiling — the **lobby** is the binding one, and it binds the other
##     way round from what you would guess. That camera is pitched 17 degrees
##     down and the ring stands 3.5 m *behind* the fire, so a ring Bog's face
##     projects **higher** on screen than something at the same height over the
##     fire does. Raising the letters walks them up into the faces. At 1.35 the
##     row's top lands level with 1.19 m on the nearest ring Bog — his chest —
##     and clears the lowest head in the ring by 40 px. At 1.55 it crossed four
##     chins.
##
## It applies to both formations, which is the point: the letter-to-fire
## proportion is one number, so there is nothing to keep in step.
const HOVER_HEIGHT := 1.35

## How far a letter drifts either side of its home, in metres.
const BOB_HEIGHT := 0.05

## The two rates the bob is beaten out of, in radians per second, and the phase
## each letter starts at.
##
## Two detuned sines per letter, the backdrop's own torch-flicker trick
## (`BogBackdrop.FIRE_FLICKER`): 1.10 and 1.73 rad/s are periods of 5.7 s and
## 3.6 s, so the pair never quite repeats and the drift never reads as a loop.
## The phases are 2.1 radians apart — a third of a cycle — because three
## letters rising and falling together is a sign that swings, and what the
## owner asked for was three things floating.
const BOB_RATE_A := 1.10
const BOB_RATE_B := 1.73
const BOB_PHASE := [0.0, 2.10, 4.20]

## The sway: how far a letter turns either side of square, in degrees, how many
## turns a second, and the phase each one starts at.
##
## **A sway and not a spin.** A spinning wordmark is edge-on to the reader for
## a third of every revolution and mirror-written for another third, which is a
## logo you cannot read — and reading it is the whole job. 12 degrees at
## 0.3 Hz is enough that the gold catches the firelight differently across the
## row and nothing like enough to hide a letter.
const SWAY_DEGREES := 12.0
const SWAY_HZ := 0.3
const SWAY_PHASE := [0.0, 1.45, 2.90]

## The exit, when a match is starting. The owner: *"when the game starts the
## letters should bounce down then bounce out of the top of the screen, as if
## they are leaving first, and then the screen goes, so we see them leave."*
##
## So: a dip, then a launch, and the scene change waits on the last one
## (`BogBackdrop.letters_leave`, awaited by `Lobby._on_match_start`). The dip is
## the anticipation that makes the launch read as a jump rather than as a cut —
## 0.25 m over 0.18 s easing out, so it settles at the bottom before it goes.
## 9 m is nearly three times the rise either camera needs to lose them off the
## top — 2.0 m in the menu, 3.3 m in the lobby — which is what lets one
## constant serve both screens. The 0.06 s stagger is what makes it three
## letters leaving and not a title card sliding off: at that spacing the B is
## already rising while the G is still dipping.
## The whole thing takes 0.85 s, which is about the fade `SceneFlow.go_to_arena`
## was going to spend anyway.
const LEAVE_STAGGER := 0.06
const LEAVE_DIP := 0.25
const LEAVE_DIP_TIME := 0.18
const LEAVE_RISE := 9.0
const LEAVE_RISE_TIME := 0.55

## The letters, in reading order, each on its own bob-and-sway pivot.
var _pivots: Array[Node3D] = []
var _elapsed: float = 0.0
## True from the first frame of `leave` onward, so the bob stops arguing with
## the tween about where a letter is.
var _leaving: bool = false
var _leave_tween: Tween = null


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	_elapsed += delta
	if _leaving:
		return
	for i in _pivots.size():
		var pivot := _pivots[i]
		pivot.position.y = HOVER_HEIGHT + _bob(i, _elapsed)
		pivot.rotation.y = deg_to_rad(SWAY_DEGREES) \
			* sin(TAU * SWAY_HZ * _elapsed + float(SWAY_PHASE[i]))


## Send the letters out of the top of frame, and come back when the last one
## has gone. Safe to call twice: the second caller waits on the first one's
## tween rather than starting a second exit from wherever the first got to.
func leave() -> void:
	if _leaving:
		if _leave_tween != null and _leave_tween.is_valid():
			await _leave_tween.finished
		return
	if _pivots.is_empty():
		return
	_leaving = true
	var tween := create_tween()
	# Parallel with a delay per tweener rather than a chain, because the three
	# letters overlap: chained, the G could not start dipping until the B had
	# finished rising, and the stagger is the whole effect.
	tween.set_parallel(true)
	for i in _pivots.size():
		var pivot := _pivots[i]
		var home := pivot.position.y
		var delay := LEAVE_STAGGER * float(i)
		tween.tween_property(pivot, "position:y", home - LEAVE_DIP, LEAVE_DIP_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(delay)
		tween.tween_property(pivot, "position:y", home - LEAVE_DIP + LEAVE_RISE,
				LEAVE_RISE_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN) \
			.set_delay(delay + LEAVE_DIP_TIME)
	_leave_tween = tween
	await tween.finished


## The screen box of one letter, for `tools/ui_range.gd` to print. `which` is
## 0, 1, 2 in reading order; the rectangle is in the camera's own viewport
## pixels, and is empty if nothing was found to measure.
##
## Measured off the meshes rather than off the constants above, for the reason
## `_build` measures them: the glyphs are three different widths and the tool's
## job is to say where they actually landed.
func letter_rect(camera: Camera3D, which: int) -> Rect2:
	if camera == null or which < 0 or which >= _pivots.size():
		return Rect2()
	var span := Rect2()
	var first := true
	for node: Node in _pivots[which].find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := mesh.get_aabb()
		for corner in 8:
			var at := camera.unproject_position(
				mesh.global_transform * box.get_endpoint(corner))
			if first:
				span = Rect2(at, Vector2.ZERO)
				first = false
			else:
				span = span.expand(at)
	return span


## Every letter's box merged into one, which is what the composition is judged
## against.
func row_rect(camera: Camera3D) -> Rect2:
	var out := Rect2()
	var first := true
	for i in _pivots.size():
		var one := letter_rect(camera, i)
		if one.size == Vector2.ZERO:
			continue
		out = one if first else out.merge(one)
		first = false
	return out


func letter_count() -> int:
	return _pivots.size()


# --------------------------------------------------------------- the build ---

## Three cards on three pivots, laid out left to right with `LETTER_GAP`
## between the glyph boxes.
##
## **The widths are measured, not written down.** The three letters are three
## different shapes — the O is 41 per cent wider than the G — so spacing them
## on a single pitch would put the same gap between the pivots and three
## different gaps between the glyphs, which is what makes a word look badly
## kerned. Each card is added, asked how wide it actually is along the row, and
## then slid so its own left edge lands where the last one's right edge plus a
## gap left off. It costs one AABB walk at startup and it cannot rot when the
## art is re-exported.
func _build() -> void:
	var scale_factor := LETTER_WORLD_HEIGHT / Pickup.LETTER_HEIGHT
	var spans: Array[Vector2] = []
	for letter: int in MatchState.LETTERS:
		var pivot := Node3D.new()
		pivot.name = "Letter%s" % MatchState.letter_name(letter)
		# The scale on the pivot and nothing else. `Pickup.build_card` scales
		# the model inside the card it hands back and says in its own comment
		# why a second multiply is a bug; this is the pivot above that card.
		pivot.scale = Vector3.ONE * scale_factor
		pivot.position = Vector3(0.0, HOVER_HEIGHT, 0.0)
		pivot.add_child(Pickup.build_card(letter))
		add_child(pivot)
		_hush_shadows(pivot)
		_pivots.append(pivot)
		spans.append(_span_along_row(pivot))

	var total := LETTER_GAP * float(maxi(0, spans.size() - 1))
	for span: Vector2 in spans:
		total += span.y - span.x
	var cursor := -total * 0.5
	for i in _pivots.size():
		var span := spans[i]
		# `cursor - span.x` and not `cursor`, so what is lined up is the
		# glyph's own left edge rather than the pivot it happens to hang from.
		_pivots[i].position.x = cursor - span.x
		cursor += (span.y - span.x) + LETTER_GAP


## Stop the letters casting shadows, which the card on the ground does and this
## one must not.
##
## Two reasons and the second one is the sharp one. A glyph that lights itself
## out of its own texture (`Pickup._light_from_within`) and then drops a hard
## black edge across the grass reads as a cardboard cut-out hung over the fire
## rather than as something glowing in the air. And in HERO the geometry is
## unlucky: the hero stands along the *same* axis the row runs on, so the line
## from the fire — the one warm light in the glade, at 0.55 m — to his head at
## 1.5 m passes through the bottom of the G. With shadows left on, the wordmark
## lays a bar across the face the whole composition was arranged to light.
func _hush_shadows(pivot: Node3D) -> void:
	var off := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for node: Node in pivot.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = off


## How far one built letter reaches either side of its pivot **along the row**,
## in world metres. The row is this node's own local X, so the answer does not
## change when the rig is turned to face a lens.
func _span_along_row(pivot: Node3D) -> Vector2:
	var axis := global_transform.basis.x.normalized()
	var origin := pivot.global_position
	var lo := INF
	var hi := -INF
	for node: Node in pivot.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := mesh.get_aabb()
		for corner in 8:
			var at := mesh.global_transform * box.get_endpoint(corner)
			var along := (at - origin).dot(axis)
			lo = minf(lo, along)
			hi = maxf(hi, along)
	if lo > hi:
		# No mesh came back — a missing `.glb`, which `Pickup` has already
		# warned about. Fall back to the middle of the three measured widths so
		# the row is still a row rather than three letters on one spot.
		return Vector2(-0.5, 0.5) * LETTER_WORLD_HEIGHT * 0.53
	return Vector2(lo, hi)


func _bob(index: int, at: float) -> float:
	var phase := float(BOB_PHASE[index])
	return BOB_HEIGHT * (0.62 * sin(at * BOB_RATE_A + phase)
		+ 0.38 * sin(at * BOB_RATE_B + phase * 1.7))
