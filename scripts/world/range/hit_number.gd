class_name HitNumber
extends Label3D
## A number that floats up off the place a hit landed, and is gone in 0.8 s.
##
## The range's one piece of purely explanatory feedback. It exists because the
## practice range is where you are supposed to *learn* what a two-thirds draw is
## worth, and the bar over a Bog's head (D-062) answers "how hurt are they"
## rather than "what did that shot do". In a real fight the bar is the honest
## gauge and a screen full of rising integers is a different game — which is why
## the HUD only ever spawns these on a practice map.
##
## Cribbed from `Nameplate` rather than invented: the font size, the pixel size
## and the outline are that file's numbers, for that file's reasons. In
## particular `FONT_SIZE` is large and `PIXEL_SIZE` small, which look
## interchangeable (only their product sets the world size) and are not — the
## first is the resolution the glyphs are rasterised at, so halving one and
## doubling the other gives the same size made of half as many pixels and goes
## to mush above 1080p.
##
## Self-freeing, top-level, and it owns no state anybody else can hold: `pop` is
## the entire API, it is fire-and-forget, and nothing ever keeps the reference.

## A little bigger than a nameplate's 0.0033. A damage number is read once, in
## passing, while you are already looking somewhere else.
const FONT_SIZE := 64
const PIXEL_SIZE := 0.0040
const OUTLINE_SIZE := 14

const LIFE := 0.8
## How far it climbs over its whole life. Enough to clear the hit point and read
## as *leaving*, not so far that a hit at head height ends up over the trees.
const RISE := 0.55
## The alpha holds for this long and then falls away over what is left, so the
## number is fully legible for most of its life rather than fading from the
## instant it appears.
const HOLD := 0.35

## Sideways scatter, in metres, so three arrows into one chest do not stack into
## an unreadable smear. Seeded off the spawn position rather than off a global
## RNG: two numbers born at the same point should not be able to land on top of
## each other, and nothing here may depend on call order.
const JITTER := 0.12

## The distance line under the number, as a fraction of the main label's size.
const SUB_SCALE := 0.55


var _age: float = 0.0
var _from: Vector3 = Vector3.ZERO
var _drift: Vector3 = Vector3.ZERO


## Put a number in the world. `sub` is the small second line under it — the
## distance of the shot — and is omitted when the distance could not be
## established honestly (see `HUD._hit_distance`).
##
## `parent` is whatever container the caller has; the label goes `top_level` and
## sets its own world transform, so a container that is not at the origin cannot
## move it. That is `WardFlash._build`'s argument and it is the same one.
static func pop(parent: Node, at: Vector3, text: String, tint: Color,
		sub: String = "") -> HitNumber:
	if parent == null:
		return null
	var label := HitNumber.new()
	label.name = "HitNumber"
	label._from = at
	parent.add_child(label)
	label._build(text, tint, sub)
	return label


func _build(body: String, tint: Color, sub: String) -> void:
	top_level = true

	text = body
	font_size = FONT_SIZE
	pixel_size = PIXEL_SIZE
	outline_size = OUTLINE_SIZE
	modulate = tint
	outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Never `fixed_size`. A number as large across the range as it is in your
	# face throws away the one cue that says which hit it belongs to, which is
	# the mistake `Nameplate`'s header records having made and undone.
	fixed_size = false
	# Drawn through scenery, unlike a nameplate. A number is feedback about
	# something you just did and it is on screen for 0.8 s; losing it behind the
	# board you just hit would be losing it exactly when it mattered.
	no_depth_test = true
	render_priority = 2
	shaded = false
	double_sided = true

	if not sub.is_empty():
		var under := Label3D.new()
		under.name = "Sub"
		under.text = sub
		under.font_size = FONT_SIZE
		under.pixel_size = PIXEL_SIZE * SUB_SCALE
		under.outline_size = OUTLINE_SIZE
		under.modulate = UIPalette.faded(tint, 0.85)
		under.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		under.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		under.fixed_size = false
		under.no_depth_test = true
		under.render_priority = 2
		under.shaded = false
		under.double_sided = true
		# Below the number, in the number's own units, so the pair moves as one
		# object however far away it is drawn.
		under.position = Vector3(0.0, -FONT_SIZE * PIXEL_SIZE * 0.95, 0.0)
		add_child(under)

	# Deterministic scatter from the point itself. `hash` on a Vector3 is stable
	# within a run, which is all this needs — it is a visual tie-breaker, not
	# anything two machines have to agree on.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_from)
	_drift = Vector3(rng.randf_range(-JITTER, JITTER), 0.0,
		rng.randf_range(-JITTER, JITTER))

	global_position = _from


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return

	var t := _age / LIFE
	# Ease out: most of the climb happens early, so the number leaves the hit
	# point promptly and then hangs where it can be read.
	var climb := 1.0 - pow(1.0 - t, 2.2)
	global_position = _from + _drift * climb + Vector3.UP * (RISE * climb)

	var alpha := 1.0
	if _age > HOLD:
		alpha = 1.0 - (_age - HOLD) / maxf(LIFE - HOLD, 0.001)
	modulate.a = clampf(alpha, 0.0, 1.0)
	var under := get_node_or_null("Sub") as Label3D
	if under != null:
		under.modulate.a = clampf(alpha * 0.85, 0.0, 1.0)
