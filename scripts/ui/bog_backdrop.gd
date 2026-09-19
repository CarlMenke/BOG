class_name BogBackdrop
extends Node3D
## The live 3D scene behind the menu and the lobby: a torch-lit glade in
## Whisperbloom Hollow with real Bogs standing in it.
##
## These are ordinary `bog.tscn` instances, not a rendered backdrop image and
## not a special "menu Bog" model. That matters for two reasons. The obvious one
## is that the lobby then shows you the actual roster — eight named, team-tinted
## Bogs with the same nameplates you will read across the island in ten seconds
## (PLAN 1.5). The less obvious one is the same argument the combat range is
## built on (D-011): every Bog here is a *remote* Bog, so the menu is one more
## place the remote-Bog code path is looked at before eight people rely on it.
##
## "Remote" is achieved exactly the way `MatchState` does it: multiplayer
## authority is set to a peer id that will never connect, and it is set *before*
## the node enters the tree, so no rig ever briefly believes it is local and
## steals the viewport.
##
## The glade itself is seeded rather than hand-placed, from the same CC0 kit the
## island will use (D-007), so the menu and the map are made of the same trees.

## Peer ids for the backdrop Bogs. Far outside anything ENet hands out and
## outside the combat range's 900s, so nothing can collide with a real peer.
const BACKDROP_PEER_BASE := 8100

const BOG_SCENE := preload("res://scenes/player/bog.tscn")
const KIT := "res://assets/Stylized_Nature_MegaKitStandard/glTF/"

## How the Bogs are arranged and where the camera sits.
##
##   HERO — one Bog, close, three-quarter view, held to the right of frame so a
##          column of menu items can own the left half.
##   RING — the roster gathered around the fire, heads and nameplates high in
##          frame so they clear the lobby panels below them.
enum Formation { HERO, RING }

@export var formation: Formation = Formation.HERO
## Changing this reshuffles the trees without touching anything else.
@export var glade_seed: int = 40219
## Radius of the arc the Bogs stand on, in metres.
##
## **3.0, down from 4.0, and the arc with it** — see `FRAMING`. The pair is one
## number as far as the lobby is concerned: what they decide together is how
## wide on screen eight Bogs and their nameplates are, and that has to fit
## between the roster column and the match rail rather than behind them.
@export var ring_radius: float = 3.5
## How much of the circle they occupy. They fill the *far* arc, so the near side
## stays open and the camera looks into the group rather than at its backs.
##
## 98, down from 150. Eight Bogs at 3.0 m over 98 degrees stand 0.73 m apart,
## which is a hand's width of air between shoulders — tighter than the old
## 1.05 m and still a ring rather than a queue.
@export_range(40.0, 300.0) var ring_arc_degrees: float = 98.0

## Trees and undergrowth, by how far out they sit. Pines read as silhouette at
## the treeline; the broad-leafed ones have enough canopy to catch torchlight.
const CANOPY := ["Pine_1", "Pine_3", "Pine_4", "CommonTree_2", "CommonTree_4",
	"TwistedTree_2", "TwistedTree_4"]
const UNDERGROWTH := ["Bush_Common", "Bush_Common_Flowers", "Fern_1", "Plant_1",
	"Plant_7", "Grass_Common_Tall", "Grass_Wispy_Tall"]
const FLOOR_DRESSING := ["Mushroom_Common", "Rock_Medium_1", "Rock_Medium_2",
	"Pebble_Round_2", "Pebble_Square_3", "Clover_1", "Flower_4_Group"]

## Framing per formation: where the camera sits, what it aims at, and how wide.
##
## The aim point is deliberately off to one side in HERO so the subject sits
## right of centre without the camera itself going off-axis and skewing him.
## RING is pitched down about seventeen degrees, which lifts the whole group
## into the upper third of the screen — the only band of a lobby that is not
## covered in panels.
##
## **HERO is a long lens on purpose.** The Bog stands on the far side of the
## fire, so the fire is nearer the camera than he is and is therefore drawn
## larger than life by any wide lens — at 42 degrees from 4.5 m the flame was
## the subject and he was the thing behind it. Pulling the eye back to 6.7 m and
## closing down to 24 brings the two distances within ten per cent of each
## other, which is what puts the fire at his feet instead of across his chest.
## It flattens him, and a hero shot is the one place that is a gift.
##
## `clear_radius` is the hole in the middle of the scatter. In RING it has to
## be wider than the ring itself: the first version planted boulders at three
## metres and the lobby became six Bogs standing behind a rock. HERO needs one
## now for the same reason and it did not use to: the hero Bog stands *inside*
## the scatter's own arc rather than in the clear wedge in front of the camera,
## so at the old 1.1 m a fern could be planted in him.
##
## There used to be a `plate_scale` here, and it is worth saying why there is
## not one now. `Nameplate` was `fixed_size`, so its height on screen came from
## the field of view and nothing else — and these formations are shot at 24 and
## 36 degrees against the game's 75, which made a lobby plate about twice the
## size of the one over the same head in a match. Shrinking the node was the
## only lever from out here. The plate now has a real size in the world, so a
## narrow lens magnifies the name and the Bog under it by exactly the same
## amount, and the two stay matched with nothing to tune.
const FRAMING := {
	Formation.HERO: {
		"eye": Vector3(3.60, 2.15, 5.70),
		"look": Vector3(-1.01, 0.87, -1.20),
		"fov": 24.0,
		"clear_radius": 2.6,
	},
	Formation.RING: {
		"eye": Vector3(0.0, 3.71, 9.95),
		"look": Vector3(0.18, 0.70, 0.0),
		"fov": 36.0,
		"clear_radius": 5.6,
	},
}

## **RING is framed to a gap between two panels, and the gap is the constraint.**
## The lobby is a right rail (the match) and a left column (the room) with the
## ring standing in the 740 px between them: at the 1600x900 base viewport the
## clear band runs **x 400 to 1140**, and every Bog and every nameplate has to
## be inside it. A ring wider than that does not look bigger, it looks like four
## Bogs standing behind the furniture — which is what the first cut of the rail
## layout did, with Sorrel and Nettle behind the roster card and Thistle and You
## behind the settings.
##
## Three numbers were moved together to fit it, and *not* the panels, because the
## panels are the sizes the layout was chosen at:
##
##   ring_radius        4.0  ->  3.0     narrower, and nearer the fire
##   ring_arc_degrees   150  ->   98     the ends come round out of the corners
##   eye                (0, 3.10, 8.20) -> (0, 3.71, 9.95)
##
## The arc and the radius are what buy the width back *without* shrinking a Bog:
## the group's world span goes 9.1 m to 6.4 m, so the eye only has to come back
## from 8.7 m to 10.6 m rather than the 70% further a pull-back alone would have
## needed. A Bog loses about a fifth of its height on screen and keeps a face
## twice the size of the name over it.
##
## The `look` carries an **x of 0.18**, which is the other half of "inside the
## band". The band's centre is 770 and the screen's is 800, because the rail
## (460 wide at the right margin) is wider than the roster column's 320 at the
## left. Aiming 18 cm to the right of the fire slides the whole glade left by
## the difference and centres the ring on the gap instead of on the window —
## `FRAMING[HERO]`'s trick again, and for its reason: it moves the picture
## without moving the lens off its own axis.
##
## **Measured, not estimated**, and measured by the gate rather than by hand:
## `tools/weapon_select.gd` projects every Bog's capsule and every nameplate's
## own box through this camera into base-viewport pixels on every run, and
## prints the box. Eight Bogs all called "Bramblewick", which is the widest name
## the range carries:
##
##   ring of 8: x 409.0 .. 1137.0, plate top 228.5      band is 400 .. 1140
##
## A five-Bog ring (`lobby_teams`) reads identically — the arc's *ends* do not
## move with the count, so the span is the same and only the spacing opens up —
## and the check takes that measurement too.
##
## Two notes for whoever moves these next. The numbers were arrived at by
## iterating **against that check**, not against a spreadsheet: a first pass
## solved the framing on paper, got the sign of the eye-distance term wrong, and
## produced a ring 25 px *wider* than the one it replaced. And the measurement
## has to be taken with the Weapon and Character page **closed** — opening it
## walks this camera in to one Bog over 0.6 s, and a box measured mid-tween is a
## box around a camera on its way somewhere.

## The portrait the Weapon and Character page tweens to, in the numbers it is
## computed from rather than as a second `FRAMING` entry — because it is not a
## framing of the *glade*, it is a framing of **one slot**, and which slot it is
## changes with the roster. `focus_on_local` builds it from `_slot_transform`,
## so a Bog that moves because somebody joined is still the Bog in the picture.
##
## **Antennae to feet, and the head means the antennae.** The first pass took
## the top of the frame from `Bog.STAND_HEIGHT` (1.55, which is the *collision
## capsule*) and cut both antennae off at the eyes — a portrait of a Bog with no
## antennae, which is a portrait of something else. `tools/skin_thumbs.gd`
## photographs this body and scans the silhouette's alpha, and it prints the
## answer on every run: the tips are at **1.778 m** and the hip bone is at
## **0.600**. So the top is 1.84, six centimetres of air over the tips.
##
## **The bottom is the ground, and it used to be the knee.** 0.36 was chosen
## while the subject stood two and a half metres in front of the ring with the
## fire behind the lens: there was nothing at his feet worth showing, so the
## frame spent its height on the body and let the shins run off the bottom edge.
## He stands on the arc now, three metres back with the fire in front of him at
## ground level — the light in this picture arrives from below, and a portrait
## lit from below that crops before the source is a portrait of an effect with
## its cause cut off. Cutting at zero also stops the one thing the page is for
## being cropped: a carried spear hangs past the shin, and the grounded stance
## is what says which way the weapon is pointing.
##
## It costs size. The frame was 1.81 m tall and is 2.24, so the body is 80% of
## what it was on screen — still 79% of the frame's height, and still the
## largest thing on the page by a factor of five over a 120 px tile.
const PORTRAIT_TOP := 1.84
const PORTRAIT_BOTTOM := 0.0

## A long lens again, for `FRAMING`'s reason and one more. At 2.5 m a wide lens
## would put the near shoulder half a head bigger than the far one, and the
## grid on the right is a set of small identical faces the player is comparing
## against the big one — so the big one has to be shot the way the tiles are,
## flat. 30 is also within six degrees of the ring's 36, which is what lets the
## tween between them read as a move rather than as a zoom.
const PORTRAIT_FOV := 30.0

## Air around the standing extent, as a multiplier on it.
##
## 1.22, from 1.06 — the lens pulled back 15%. At 1.06 the frame put 0.11 m over
## the antenna tips, which is 61 px at the base viewport, and on the page that
## reads as the tips *touching* the title rather than standing under it: the
## title is 34 px of type sitting in the top 96, so the two are within a line of
## each other. It survives the move to a full-length frame unchanged, and the
## arithmetic is worth writing down because the extent under it changed: 1.22 of
## 1.84 is a 2.24 m frame centred at 0.92, so the tips stand under **0.26 m** of
## air (106 px) and the feet over **0.20 m** (83 px). Measured rather than
## asserted: `tools/ui_range.gd`'s `lobby_character` prints the frame it ends up
## with on every run — tips at **0.112** down it and soles at **0.916**.
const PORTRAIT_MARGIN := 1.22

## How far round the Bog the lens sits, from the Bog's own facing, in degrees.
##
## **Negative, so the camera is on the Bog's right.** Every weapon is carried in
## the right fist (`HeldGear`), and a three-quarter from the left side puts the
## body between the lens and the thing this page exists to choose. The sign is
## the whole of that; 34 degrees is the usual three-quarter.
##
## It is also what decides the light now that the subject stands on the arc,
## and 34 is the answer to a question with no clean one. The fire is 3.0 m in
## front of him and the ring's Bogs face the lens rather than the flame, so the
## fire's bearing off a Bog's own facing runs from **-29 degrees** at one end of
## the 98-degree arc to **+29** at the other. The key is therefore between 5 and
## 63 degrees off this lens depending on which slot is yours: a flat frontal at
## one end, a strong short-side key at the other, and no fixed angle can hold
## both inside the 15-45 a portrait wants, because the spread is 58 degrees wide
## and the lens is one number. What every slot does get is a key in *front* of
## the face — which is the whole of D-106's argument and the reason the step out
## of the ring had to go.
const PORTRAIT_YAW := -34.0

## Where the Bog's spine sits across the frame, 0 at the left edge and 1 at the
## right. The skin grid is 380 px of a 1600 px screen and starts at 0.76, so the
## subject owns everything left of that.
##
## **0.32, from 0.27.** The old number was carrying two jobs: sitting the body
## left of the grid, and swinging the lens far enough right to push the Bogs
## either side of him off the left edge. The second one is `_bog_wanted`'s now,
## so this is free to be the composition alone — and as composition 0.27 was
## wrong twice. It left 0.31 of the width empty between his shoulder and the
## first tile against 0.17 outside his other arm, so the page read as a picture
## pushed into its own corner; and it stood the antennae directly under WEAPON
## AND CHARACTER, which sits at 0.075..0.33. At 0.32 the air is even, 0.24 a
## side, and the head has the empty half of the header bar over it.
const PORTRAIT_SUBJECT_X := 0.32

## The aspect the off-centring is solved for. The game's own base viewport
## (`project.godot`), rather than the live window: the page's own controls are
## anchored in those same base-viewport pixels, so solving against anything else
## would put the Bog and the grid in two different coordinate systems.
const PORTRAIT_ASPECT := 16.0 / 9.0

## How long the move to the portrait and back takes. Long enough to read as the
## camera walking over rather than as a cut, short enough that a player who
## opens the page to change one thing is not waiting on it.
const FOCUS_SECONDS := 0.6

## The ring's nameplates are laid out in **three ranks**, and this is why.
##
## Eight names have to fit across the 740 px between the roster column and the
## match rail. A name is up to 200 px wide there and the slots are 75 px apart,
## so along one line they overlap by 125 px — the middle four are a single
## illegible smear, which is what the first pass at the rail framing produced
## and is worse than the problem it fixed.
##
## Nothing in the framing can solve it. The only thing that separates names on
## one line is *depth* — a Bog nearer the lens carries its plate lower — and the
## amount of depth eight Bogs can have while staying 740 px wide is about a
## metre, which is worth a dozen pixels. The searches that did clear the names
## by geometry alone all wanted a **256 degree** arc shot from **fifteen
## metres**: a ring wrapped right round the fire, with two Bogs standing between
## it and the camera as backlit silhouettes, and every face a fifth smaller.
## That is paying for the names with the faces, and the faces are what the ring
## is on screen for.
##
## So the plates are stacked instead. Three ranks, `PLATE_RANK_STEP` apart, and
## three because that is the first number that works: on one line a name
## overlaps its neighbour, on two it overlaps the one after that (150 px apart,
## 200 px wide), and on three the nearest name sharing a rank is 225 px away and
## clears by 26. The rank is `index % 3`, so it holds for any roster size and
## does not have to be re-solved when somebody joins.
##
## **Only in RING.** The hero Bog has one name and no neighbours.
const PLATE_RANKS := 3
const PLATE_RANK_STEP := 0.26

## Half-width of the wedge, centred on the camera, that no prop may grow in.
## Without it the scatter cheerfully plants a fern on the lens: both framings
## look along +Z, so the near side of the glade is the one place a tree is
## guaranteed to be in the way rather than in the picture.
const CAMERA_WEDGE := deg_to_rad(58.0)
## And nothing at all inside this radius of the camera, whatever the angle.
const CAMERA_CLEARANCE := 6.0

## Torch flicker. Two detuned sines beat against each other so the period never
## quite repeats, which is what stops a flicker reading as a pulsing loop.
const FIRE_ENERGY := 3.0
const FIRE_FLICKER := 0.22

var _camera: Camera3D
var _fire: OmniLight3D
var _bog_root: Node3D
var _bogs: Array[Bog] = []
## `[{name, team, weapon}, ...]`, in the order they should stand.
var _roster: Array[Dictionary] = []
var _elapsed: float = 0.0
## Which slot the player at this keyboard is standing in, or -1 if the caller
## did not say. Written by `set_roster` from the entry's own `local` key, for
## `weapon` and `skin`'s reason (D-069): the ring is driven from the roster and
## nothing else, so "which of these is me" is a column of it rather than a
## second question asked of `Net` out here — where the backdrop Bogs have peer
## ids that are in no roster at all.
var _local_slot: int = -1
## Whether the Weapon and Character page is open. The camera is the only thing
## in this file that knows about that page, and this is the whole of what it
## knows.
var _focused: bool = false
## The framing the camera is at, or is on its way to. `{eye, look, fov}`, the
## same shape `FRAMING` hands out, so the ring view and a portrait are one kind
## of thing and `_apply_view` does not have to care which it was given.
var _view: Dictionary = {}
var _view_tween: Tween = null
## The height `bog.tscn` hangs a nameplate at, read off the first Bog that is
## built rather than written down here — so the ranks above are an offset from
## wherever the scene puts it and cannot drift away from it.
var _plate_home: float = -1.0


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_glade()
	_build_fire()

	_bog_root = Node3D.new()
	_bog_root.name = "Bogs"
	add_child(_bog_root)

	_build_camera()
	if _roster.is_empty():
		# Whoever is at the keyboard, so the menu is never an empty stage.
		set_roster([{
			"name": Settings.sanitized_player_name(),
			"team": MatchConfig.TEAM_NONE,
			"weapon": Settings.chosen_weapon(),
		}])


func _process(delta: float) -> void:
	_elapsed += delta
	if _fire != null:
		var flicker := sin(_elapsed * 7.3) * 0.6 + sin(_elapsed * 11.9) * 0.4
		_fire.light_energy = FIRE_ENERGY * (1.0 + FIRE_FLICKER * flicker)


# ------------------------------------------------------------------- roster ---

## Show these players, in this order. Safe to call every time the roster
## changes: Bogs are pooled and repositioned rather than rebuilt, so joining a
## lobby shuffles everyone along instead of restarting eight animations.
func set_roster(entries: Array) -> void:
	_roster.clear()
	for entry: Variant in entries:
		if entry is Dictionary:
			_roster.append(entry)
	_local_slot = -1
	for i in _roster.size():
		if bool(_roster[i].get("local", false)):
			_local_slot = i
			break
	if _bog_root == null:
		return  # still pre-`_ready`; `_ready` will apply it
	_grow_pool(_roster.size())
	for i in _bogs.size():
		_apply_slot(i)
	# The ring rearranges itself every time somebody joins or leaves, and while
	# the page is open the camera is pointed at one slot of it — so the portrait
	# is re-solved here rather than only when the page opens. Without this, a
	# join would slide the subject out of frame and leave the lens staring at
	# the gap where he used to be. `_apply_view` compares before it tweens, so
	# the ordinary refresh (a chat line, a dial moving) costs nothing.
	if _focused:
		_apply_view(_focus_view(), FOCUS_SECONDS)


func _grow_pool(wanted: int) -> void:
	var target := clampi(wanted, 0, MatchConfig.MAX_PLAYERS)
	while _bogs.size() < target:
		_bogs.append(_make_bog(_bogs.size()))


func _make_bog(index: int) -> Bog:
	var bog := BOG_SCENE.instantiate() as Bog
	bog.name = "BackdropBog_%d" % index
	bog.peer_id = BACKDROP_PEER_BASE + index
	# Before `add_child`, always. Set it afterwards and the rig spends its
	# `_ready` believing it is the local player and makes its camera current --
	# the exact bug that had every client playing out of the wrong Bog's eyes.
	bog.set_multiplayer_authority(bog.peer_id)
	_bog_root.add_child(bog)
	# A remote Bog takes its whole pose from the replicated fields, and nobody
	# is going to replicate anything to these. `sync_grounded` in particular has
	# to be set by hand: left false, `BogAnimator` plays the Jump clip forever
	# and the lobby is a ring of Bogs frozen in mid-leap.
	bog.sync_grounded = true
	bog.sync_velocity = Vector3.ZERO
	# Stagger the idle cycles. Eight Bogs breathing in perfect lockstep is the
	# one thing that would give away that they are copies of each other.
	var animator := bog.get_node_or_null("AnimationTree") as BogAnimator
	if animator != null:
		animator.advance(randf() * 4.0)
	return bog


## Position, name and tint one pooled Bog, or hide it if the roster is shorter
## than the pool.
func _apply_slot(index: int) -> void:
	var bog := _bogs[index]
	if index >= _roster.size():
		bog.visible = false
		return
	# Through `_bog_wanted` and not a bare `true`, so a roster change while the
	# portrait is open — somebody joins, somebody leaves — re-dresses the ring
	# without putting the hidden half of it back on screen.
	bog.visible = _bog_wanted(index)

	var entry := _roster[index]
	var spot := _slot_transform(index, _roster.size())
	bog.revive_at(spot)
	bog.sync_grounded = true

	var team: int = entry.get("team", MatchConfig.TEAM_NONE)
	bog.display_name = String(entry.get("name", "Bog"))
	bog.team = team
	# The weapon the lobby picked, on the same call that repaints the team and
	# for the same reason (D-069): every roster change comes through here, so a
	# weapon chosen in the strip is in the ring's hands on the next refresh. The
	# hand itself is `BogCombat`'s — this only says which weapon the Bog has, and
	# `_refresh_weapon` below is what asks the combat node to redraw from it.
	_equip(bog, Loadout.sanitize(entry.get("weapon", Loadout.DEFAULT)))
	# The body, on the same call and for the same reason: every roster change
	# comes through here, so a skin picked in the strip is on the ring's Bogs on
	# the next refresh — and in Teams that is *everyone on the picker's team*
	# changing at once, which is exactly what the ring is on screen to show.
	bog.wear_skin(Skins.texture_of(Skins.sanitize(entry.get("skin", Skins.DEFAULT))))
	# **A skin and a team recolour are two answers to one question**, so a Bog
	# that has been dressed is not also repainted: in Teams the skin *is* the
	# team's identity on the body, and the plate below keeps the team's colour to
	# say the same thing in the UI's own voice.
	#
	# An entry with no `skin` key at all is a caller from before the picker
	# existed — the menu's hero Bog, `tools/team_tint.gd`'s lobby check — and
	# those still get D-046's recolour, which is why that check is untouched.
	bog.set_team_tint(MatchConfig.TEAM_NONE if entry.has("skin") else team)
	var plate := bog.get_node_or_null("Nameplate") as Nameplate
	if plate != null:
		if _plate_home < 0.0:
			_plate_home = plate.position.y
		plate.position.y = _plate_home + _plate_rank(index)
		plate.set_display_name(bog.display_name)
		plate.set_team(team)
		plate.visible = _plate_wanted(index)


## Give this backdrop Bog a weapon and put it in its hands.
##
## The hand is drawn by `BogCombat._refresh_hand` and by nothing else, here
## exactly as in a match — which is the point of the ring being real `bog.tscn`
## instances (see the header). So this sets the field the gate reads and then
## asks the gate to run again; it does not touch `HeldGear`, because a second
## opinion about what is in a fist is the one thing that file refuses to have.
##
## Idempotent, because `set_roster` is called on every roster change and most of
## them are about somebody else.
func _equip(bog: Bog, weapon: int) -> void:
	bog.weapon = weapon
	var combat := bog.get_node_or_null("Combat") as BogCombat
	if combat != null:
		combat.refresh_hand()


func _slot_transform(index: int, count: int) -> Transform3D:
	if formation == Formation.HERO or count <= 1:
		# Stood on the *far* side of the fire from the camera, facing back across
		# it. The fire is then between him and the lens, which is the whole of
		# the lighting: it is the only warm source in the glade, so whichever
		# side of it he stands on is the side that gets a face. He used to stand
		# in front of it and be a silhouette with a rim on it — handsome, and a
		# menu whose subject you could not actually see. Turned four degrees off
		# the camera, into the frame, so the pose reads as three-quarter rather
		# than as a mugshot.
		#
		# Four, and not the eleven and a half it used to be. From this spot the
		# lens is at `yaw_towards(FRAMING[HERO].eye - here)` = 208.5 degrees, and
		# the old 197 was far enough off it to read as a Bog looking past you
		# rather than at you — at 24 degrees of field of view there is very
		# little frame left for him to be looking *into*. Four is still a
		# three-quarter, and it is his eyeline that carries it now.
		#
		# 2.05 m out. It used to be 1.65, which was as close to the flame as the
		# pose survives; a little further back reads as standing at a fire rather
		# than over it, and the light still reaches him.
		return Transform3D(Basis(Vector3.UP, deg_to_rad(204.5)), Vector3(-0.46, 0.0, -2.00))

	# Fill the far arc, centred on the back of the ring. One Bog is at the
	# middle of the arc, two straddle it, and so on outward.
	var arc := deg_to_rad(ring_arc_degrees)
	var step := arc / float(count - 1)
	var angle := PI + (float(index) - float(count - 1) * 0.5) * step
	var spot := Vector3(sin(angle) * ring_radius, 0.0, cos(angle) * ring_radius)
	# Everyone faces the *camera*, then turns a little back toward the fire, so
	# the ring reads as a group of faces rather than a circle of shoulders.
	#
	# It used to be the other way round — face the fire, then turn a few degrees
	# toward the lens — and that arithmetic never reached the ends of the arc.
	# A Bog stood 75 degrees round the circle is already 52 degrees off the
	# camera merely by facing the flame, so ten degrees of correction left him
	# side-on and the lobby was a row of profiles with one face in the middle.
	# Starting from the camera instead puts every face at the lens *by
	# construction*, whatever the arc width or the roster count, and the turn
	# back toward the fire is then a small deliberate amount rather than the
	# remainder of a much larger error.
	#
	# Scaled by `sin(angle)`, so the Bog at the middle of the arc stays square to
	# the camera and only the ones at the ends turn inward — which is all the
	# "standing around a fire" reading needs. 12 degrees is as far as the new
	# Idle will carry it: that pose is a boxer's guard with the head already
	# carried forward and down, so a Bog turned much further than this gives the
	# camera the top of his head instead of his face.
	var eye: Vector3 = FRAMING[Formation.RING]["eye"]
	var to_camera := Vector3(eye.x - spot.x, 0.0, eye.z - spot.z)
	var yaw := Bog.yaw_towards(to_camera) + deg_to_rad(sin(angle) * -12.0)
	return Transform3D(Basis(Vector3.UP, yaw), spot)


# ------------------------------------------------------------- the portrait ---

## Walk the camera in to a portrait of the player's own Bog, or back out to the
## whole ring.
##
## The lobby's Weapon and Character page is the only caller. What it is asking
## for is not "show a different picture" — nobody moves, the fire and the glade
## do not move — it is **the same scene from four metres instead of ten**, so
## that the body you are dressing is the size of a body rather than the size of
## a thumbnail. That is why this is a camera move and not a second formation: a
## formation would have to rebuild the ring, and the ring is what the player is
## picking *out of*.
##
## Three things change and all three are this client's own view of its own
## page: the lens, the subject's own nameplate, and whether the rest of the ring
## is drawn. The stage itself is untouched, which is why nothing here is sent to
## anybody and why closing the page is just the same three read the other way.
##
## Idempotent, and safe to call while a move is already running: `_apply_view`
## kills whatever tween is in flight and starts from wherever the lens actually
## got to, so mashing the button cannot leave the camera stranded between two
## framings.
func focus_on_local(on: bool) -> void:
	if _focused == on:
		return
	_focused = on
	_refresh_plates()
	_refresh_bogs()
	_apply_view(_focus_view(), FOCUS_SECONDS)


## Whether the plate over this slot's head is wanted.
##
## **Not over your own head, in a portrait of it.** A nameplate has a real size
## in the world (D-111's note on `plate_scale`), which is what keeps it matched
## to the body at any field of view — and at 4.2 m it is matched to a body that
## fills the screen, so "You" is drawn a metre high across the top of the page.
## It is also the one name on the ring that answers a question nobody asked.
##
## The other seven are left alone here and go with their bodies below, which is
## the right way round: a plate is a label on a Bog, so the rule about labels
## does not have to know the rule about who is on stage.
func _plate_wanted(index: int) -> bool:
	return not (_focused and index == _local_slot)


## Whether this slot's Bog is on stage at all.
##
## **The ring is not in the portrait, and this is the whole of why the subject
## can stand still.** A 30 degree lens on a 16:9 frame has a horizontal field
## 25 degrees either side of its axis, and the eight Bogs of a full ring stand
## 0.73 m apart on a 3.0 m arc — so the Bog next door is a dozen degrees off the
## lens at the same distance, which is half a portrait of somebody else. No lens
## reaches it: the neighbour's angular offset and the frame's angular width
## scale together, so a longer lens from further away puts him in exactly the
## same place. The first answer was to walk the *subject* 2.8 m out of the ring
## until the others fell off the left edge, and it cost the light — that step
## carried him to the camera's side of the fire, which is the arrangement
## `FRAMING[HERO]` spent a paragraph undoing.
##
## Hiding them costs nothing instead. It is this client's own view of a page
## nobody else can see, the ring is still standing where it was, and it comes
## back the instant the page closes — while the subject keeps the spot D-111
## placed him on, facing the lens with the fire in front of him.
##
## Guarded on `_local_slot`, because a roster with no `local` key (the menu's
## hero Bog, an older harness) never gets a portrait either: `_focus_view`
## falls back to the whole ring, and an empty stage is not a fallback.
func _bog_wanted(index: int) -> bool:
	if index >= _roster.size():
		return false
	return not (_focused and _local_slot >= 0 and index != _local_slot)


func _refresh_bogs() -> void:
	for i in _bogs.size():
		_bogs[i].visible = _bog_wanted(i)


## How high above its own Bog this slot's nameplate hangs. See `PLATE_RANKS`.
func _plate_rank(index: int) -> float:
	if formation != Formation.RING:
		return 0.0
	return float(index % PLATE_RANKS) * PLATE_RANK_STEP


func _refresh_plates() -> void:
	for i in _bogs.size():
		var plate := _bogs[i].get_node_or_null("Nameplate") as Nameplate
		if plate != null:
			plate.visible = _plate_wanted(i)


## What the camera should be looking at right now: a portrait if the page is
## open and we know which slot is the player's, the formation's own framing
## otherwise.
##
## **The fallback is the ring, not slot zero.** A roster with no `local` key is
## the menu's hero Bog or an older harness, and pointing the page's camera at
## whoever happens to be standing first would be a portrait of a stranger.
func _focus_view() -> Dictionary:
	if _focused and _local_slot >= 0 and _local_slot < _roster.size():
		return _portrait_view(_local_slot, _roster.size())
	return FRAMING[formation]


## The portrait framing for one slot, solved rather than authored.
##
## Three things have to come out of it and each one is a line:
##
## **The lens is on the Bog's right, at a three-quarter.** `_slot_transform`
## already turned him to face the ring camera, so his own facing is the axis to
## measure from — rotate the eye `PORTRAIT_YAW` degrees round him and the pose
## reads as three-quarter wherever on the arc he is standing, which a fixed
## world-space bearing would only manage for the Bog in the middle.
##
## **The distance comes from the framing, not the other way round.** The subject
## is `PORTRAIT_TOP - PORTRAIT_BOTTOM` metres tall; at a vertical field of view
## of `PORTRAIT_FOV` the distance that exactly fills the frame with it is
## `half / tan(fov / 2)`. Picking a distance and then hunting for a field of
## view that looked right is what this avoids — it would have to be hunted again
## the day the sculpt changes height.
##
## **He is held left of centre by aiming past him, not by moving the lens.**
## `FRAMING[HERO]`'s trick, and for its reason: swinging the camera sideways off
## its own axis skews the body, and a skewed three-quarter is a wide-angle
## portrait, which is the one thing `PORTRAIT_FOV` is long to avoid. So the eye
## stays on the axis through the subject and the *look point* slides along the
## camera's right vector. A point `s` metres to the side of the axis lands at
## `s / (half * aspect)` of a half-width across the frame, so the shift that
## puts the spine at `PORTRAIT_SUBJECT_X` is `(1 - 2x) * half * aspect` — and it
## is positive, because aiming right moves the subject left.
func _portrait_view(index: int, count: int) -> Dictionary:
	var spot := _slot_transform(index, count)
	var facing := -spot.basis.z
	facing.y = 0.0
	facing = facing.normalized()

	var half := (PORTRAIT_TOP - PORTRAIT_BOTTOM) * 0.5 * PORTRAIT_MARGIN
	var distance := half / tan(deg_to_rad(PORTRAIT_FOV) * 0.5)
	var away := facing.rotated(Vector3.UP, deg_to_rad(PORTRAIT_YAW))
	var subject := spot.origin \
		+ Vector3.UP * ((PORTRAIT_TOP + PORTRAIT_BOTTOM) * 0.5)
	var eye := subject + away * distance
	# The camera's own right, from the direction it will be pointing.
	var right := (-away).cross(Vector3.UP).normalized()
	var shift := (1.0 - 2.0 * PORTRAIT_SUBJECT_X) * half * PORTRAIT_ASPECT
	return {
		"eye": eye,
		"look": subject + right * shift,
		"fov": PORTRAIT_FOV,
	}


## Move the lens to a framing, over `seconds`, or put it there outright if the
## camera does not exist yet or nothing has changed.
##
## `look_at_from_position` per step rather than tweening the transform: a
## rotation interpolated as a basis takes the short way round in a way that has
## nothing to do with what the camera is looking at, and the two ends of this
## move are twenty degrees and five metres apart. Interpolating *what it is
## aimed at* keeps the subject in frame for the whole move, which is the only
## property of it anybody will notice.
func _apply_view(view: Dictionary, seconds: float) -> void:
	if _camera == null:
		_view = view
		return
	# Compared field by field, and **against the destination**: `FRAMING` hands
	# back the same dictionary every time and a portrait is a fresh one, so
	# identity would say "unchanged" for the ring and "changed" for a portrait
	# that is in fact the same shot. Asked before the tween is killed, so a
	# refresh that lands mid-move does not restart the move it is already making.
	if not _view.is_empty() \
			and _view["eye"] == view["eye"] and _view["look"] == view["look"] \
			and is_equal_approx(_view["fov"], view["fov"]):
		return
	var from := _live_view()
	if _view_tween != null and _view_tween.is_valid():
		_view_tween.kill()
	_view_tween = null
	_view = view
	if seconds <= 0.0 or from.is_empty():
		_write_view(view)
		return
	_view_tween = create_tween()
	_view_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_view_tween.tween_method(
		func(t: float) -> void: _write_view({
			"eye": (from["eye"] as Vector3).lerp(view["eye"], t),
			"look": (from["look"] as Vector3).lerp(view["look"], t),
			"fov": lerpf(from["fov"], view["fov"], t),
		}), 0.0, 1.0, seconds)


## Where the lens actually is, in the same `{eye, look, fov}` shape.
##
## Read off the camera rather than remembered, which is what makes a move that
## interrupts another one start from the picture on screen instead of from the
## place the interrupted move was heading for. With nothing in flight it returns
## exactly `_view`, because the aim point is reconstructed at the distance
## `_view` put it: same eye, same direction, same reach.
func _live_view() -> Dictionary:
	if _view.is_empty():
		return {}
	var eye := _camera.position
	var reach := maxf(0.5, eye.distance_to(_view["look"]))
	return {
		"eye": eye,
		"look": eye - _camera.transform.basis.z * reach,
		"fov": _camera.fov,
	}


func _write_view(view: Dictionary) -> void:
	if _camera == null:
		return
	_camera.fov = view["fov"]
	_camera.look_at_from_position(view["eye"], view["look"], Vector3.UP)


# --------------------------------------------------------------- the stage ---

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "BackdropCamera"
	_camera.near = 0.05
	_camera.far = 220.0
	add_child(_camera)
	_view = {}
	_apply_view(_focus_view(), 0.0)
	# Claimed last and explicitly, so it wins over any rig that might have
	# made itself current on the way in.
	_camera.make_current()


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	env.name = "Environment"
	# The arena's own environment, so the menu is lit by the same night the
	# match is (D-009) and retuning the sky retunes both.
	env.environment = load("res://resources/config/arena_env.tres")
	add_child(env)

	# The sky draws its moon at LIGHT0's direction, so this light *is* the moon.
	# Direction, colour and energy are the handoff values from D-009: fill only,
	# because the fire is the key light.
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 0.30
	moon.shadow_enabled = true
	moon.look_at_from_position(Vector3.ZERO, -Vector3(-0.42, 0.38, -0.82), Vector3.UP)
	add_child(moon)


func _build_ground() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Ground"
	var disc := CylinderMesh.new()
	disc.top_radius = 26.0
	disc.bottom_radius = 26.0
	disc.height = 0.6
	disc.radial_segments = 48
	var mat := StandardMaterial3D.new()
	# Kept above the floor D-009 sets for terrain albedo; darker than this and
	# a Bog standing outside the firelight has nothing to be a silhouette
	# against.
	mat.albedo_color = Color(0.16, 0.19, 0.13)
	mat.roughness = 0.98
	disc.material = mat
	mesh.mesh = disc
	mesh.position.y = -0.3
	add_child(mesh)


## A seeded glade. Same generator shape as the island (D-007): a ring of canopy
## at the treeline, undergrowth inside it, and small dressing on the floor near
## the fire. Three passes, one scatter rule, no hand-placed props.
func _build_glade() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = glade_seed
	var props := Node3D.new()
	props.name = "Glade"
	add_child(props)

	_scatter(props, rng, CANOPY, 26, 10.0, 22.0, 0.85, 1.35)
	_scatter(props, rng, UNDERGROWTH, 32, 5.5, 16.0, 0.80, 1.40)
	_scatter(props, rng, FLOOR_DRESSING, 36, 1.6, 9.0, 0.70, 1.30)


## Drop `count` props at random bearings and distances, skipping anywhere the
## camera would be looking through them.
func _scatter(parent: Node3D, rng: RandomNumberGenerator, models: Array,
		count: int, near: float, far: float, scale_lo: float, scale_hi: float) -> void:
	var eye: Vector3 = FRAMING[formation]["eye"]
	var clear: float = FRAMING[formation]["clear_radius"]
	var low := maxf(near, clear)
	var high := maxf(far, low + 2.5)
	var spread := PI - CAMERA_WEDGE
	for i in count:
		# Bearings are sampled around the *back* of the glade and the wedge in
		# front of the camera is simply never drawn from, rather than being
		# sampled and rejected: a rejection loop on a wedge this wide throws
		# away a third of the seed sequence and makes the layout depend on how
		# many times it retried.
		var angle := PI + rng.randf_range(-spread, spread)
		var distance := rng.randf_range(low, high)
		var spot := Vector3(sin(angle) * distance, 0.0, cos(angle) * distance)
		if spot.distance_to(eye) < CAMERA_CLEARANCE:
			continue
		_place(parent, String(models[rng.randi() % models.size()]), spot,
			rng.randf() * TAU, rng.randf_range(scale_lo, scale_hi))


func _place(parent: Node3D, model: String, spot: Vector3, yaw: float,
		scale_factor: float) -> void:
	var packed := load(KIT + model + ".gltf") as PackedScene
	if packed == null:
		return
	var node := packed.instantiate() as Node3D
	node.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_factor), spot)
	parent.add_child(node)


## The campfire everyone is standing around: the key light, and the only warm
## thing on screen.
func _build_fire() -> void:
	var pit := Node3D.new()
	pit.name = "Fire"
	add_child(pit)

	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.09, 0.066, 0.05)
	bark.roughness = 1.0
	for i in 5:
		var log_mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.10, 0.10, 0.74)
		box.material = bark
		log_mesh.mesh = box
		# Leaned in from a ring rather than crossed at the centre. Stacked at
		# the origin they read as a black star behind the flame instead of as
		# a fire someone built.
		var angle := TAU * float(i) / 5.0 + 0.4
		log_mesh.transform = Transform3D(
			Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, deg_to_rad(34.0)),
			Vector3(sin(angle) * 0.24, 0.12, cos(angle) * 0.24))
		pit.add_child(log_mesh)

	# The flame is two unshaded cones rather than particles: it is scenery in a
	# menu, and the environment's glow pass turns an emissive cone into a
	# believable fire for a fraction of the cost of a GPUParticles system that
	# nobody will ever stand next to.
	_add_flame_cone(pit, 0.26, 0.72, 0.30, Color(1.0, 0.55, 0.26), 2.2)
	_add_flame_cone(pit, 0.13, 0.46, 0.38, Color(1.0, 0.85, 0.52), 3.4)

	_fire = OmniLight3D.new()
	_fire.light_color = Color(1.0, 0.73, 0.47)
	_fire.light_energy = FIRE_ENERGY
	# Tight enough that the glade falls away into night a few metres out. A
	# wide range lights the whole clearing evenly and the result reads as
	# daylight with an orange filter on it.
	_fire.omni_range = 11.0
	_fire.omni_attenuation = 1.6
	_fire.shadow_enabled = true
	# D-009: torch lights need roughly this to punch a halo through the
	# volumetric fog rather than lighting geometry and nothing else.
	_fire.light_volumetric_fog_energy = 2.0
	_fire.position = Vector3(0.0, 0.55, 0.0)
	pit.add_child(_fire)


func _add_flame_cone(parent: Node3D, radius: float, height: float, centre_y: float,
		tint: Color, energy: float) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = height
	cone.radial_segments = 7
	cone.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	# Comfortably above the environment's 1.45 glow threshold, which was set
	# just over a torch-lit Bog so that only real light sources bloom.
	mat.emission_energy_multiplier = energy
	cone.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = cone
	mesh.position.y = centre_y
	parent.add_child(mesh)
