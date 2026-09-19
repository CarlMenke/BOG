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
## **4.0 -> 3.0 -> 3.5, and the arc and the eye with it** — see `FRAMING`. The
## three are one number as far as the lobby is concerned: what they decide
## together is how wide on screen eight Bogs and their nameplates are, and that
## has to fit between the roster column and the match rail rather than behind
## them. The last move is the owner's, to stand the ring back off the fire so
## the letters have air around them; the eye went back 18 per cent to pay for
## the width it cost.
@export var ring_radius: float = 3.5
## How much of the circle they occupy. They fill the *far* arc, so the near side
## stays open and the camera looks into the group rather than at its backs.
##
## 98, down from 150. Eight Bogs over 98 degrees stand 0.73 m apart at a 3.0 m
## radius and 0.85 m at the 3.5 m they stand on now — a hand's width of air
## between shoulders either way, tighter than the old 1.05 m and still a ring
## rather than a queue. It is left alone when the radius moves, on purpose: the
## arc is what decides whether this is a group or a line-up, and the width on
## screen is `FRAMING[RING]`'s eye to answer.
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
## **HERO is a long lens on purpose.** The fire and the Bog are within a metre
## of each other in depth, and a wide lens draws the nearer of two such things
## larger than life — at 42 degrees from 4.5 m the flame was the subject and he
## was the thing behind it. 24 degrees from 7.5 m brings the two distances
## within five per cent of each other, which is what puts the fire beside him
## instead of across his chest. It flattens him, and a hero shot is the one
## place that is a gift.
##
## **HERO was re-aimed for the letters** (the owner: *"the campfire should be
## moved to the left in the menu and the BOG hovers above it"*). The fire is no
## longer the centre of the picture; the fire, the three letter cards over it
## and the Bog beside it are, and they are arranged left to right in that
## order. Three numbers moved together, and the reason each one is what it is:
##
##   eye  (3.60, 2.15, 5.70) -> (3.90, 2.20, 6.15)
##   look (-1.01, 0.87, -1.20) -> (1.54, 0.83, 0.25)
##   the hero slot (-0.46, 0, -2.00) -> (1.72, 0, -0.69) -> (1.86, 0, -1.28)
##
## The eye goes back 7 per cent because the hero left the far side of the fire
## and came round beside it: at the old distance he stood 7.0 m from the lens
## instead of 9.0 and was drawn a third larger, and a third larger is a Bog
## with his antennae off the top of the frame. The `look` slides right and up
## because aiming right moves the *picture* left — `_portrait_view` spells that
## trick out — and everything here has to move left to leave the right third
## for him.
##
## **Measured through the lens, not solved on paper.** The block that used to be
## here was hand-projected arithmetic and the hero's box in it was wrong by
## thirty pixels a side, because it carried a capsule radius the Bog does not
## have. So every number below is now a line `tools/ui_range.gd`'s
## `menu_letters` mode printed, and the mode prints them on every run so they
## cannot quietly rot. At the 1600x900 base viewport, before and after the hero
## stepped right and back:
##
##   B  x 104..261    O  x 317..502    G  x 563..696     all  y 116..383
##   the row          x 104..696, y 116..383
##   the hero capsule x 838..1067, y 116..632   ->   x 930..1149, y 108..593
##
## That is 234 px of clear air between the wordmark and the Bog, up from 142;
## the row inside the frame's upper-left quadrant with a 104 px margin off the
## left edge (the `Quip` under it starts at 112, so the two share an edge); and
## the Bog's feet at y 593, which is 171 px clear of the button bar at y 764,
## up from 132. Nothing the player can press is standing in front of anybody.
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
		"eye": Vector3(3.90, 2.20, 6.15),
		"look": Vector3(1.54, 0.83, 0.25),
		"fov": 24.0,
		"clear_radius": 2.6,
	},
	Formation.RING: {
		"eye": Vector3(-0.03, 4.25, 11.74),
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
##   ring_radius        4.0  ->  3.0  ->  3.5    the ring stood back off the fire
##   ring_arc_degrees   150  ->   98            the ends come round out of the corners
##   eye  (0, 3.10, 8.20) -> (0, 3.71, 9.95) -> (-0.03, 4.25, 11.74)
##
## The arc and the radius are what buy the width back *without* shrinking a Bog:
## the group's world span goes 9.1 m to 6.4 m, so the eye only has to come back
## from 8.7 m to 10.6 m rather than the 70% further a pull-back alone would have
## needed. A Bog loses about a fifth of its height on screen and keeps a face
## twice the size of the name over it.
##
## **Then the radius went to 3.5 and put the ring back outside the band.** The
## owner stood the group off the fire so the letters have air around them, and
## widening the circle by a sixth widened the picture by the same sixth: the
## measurement below went from 409..1137 to **370..1172**, which is 30 px over
## the roster column at one end and 32 px behind the match rail at the other.
##
## The radius is the owner's and the panels are the layout's, so the third
## number is the one that moved: the eye goes back **18 per cent** along its own
## eye->look line, from 10.4 m to 12.3 m, which is `(-0.03, 4.25, 11.74)`. That
## is a 689 px span inside a 740 px band with 31 px of margin at the left and
## 20 px at the right, and it costs 13 per cent of a Bog's height on screen. The
## alternative was to close `ring_arc_degrees` to about 81, which would have
## held the span at the same size with no pull-back at all — and was not taken,
## because at 3.5 m an 81-degree arc stands eight Bogs 0.70 m apart with their
## shoulders touching, and a ring the owner widened to get air in it is not a
## ring to take the air back out of.
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
##   ring of 8: x 431.2 .. 1120.3, plate top 204.0      band is 400 .. 1140
##   ring of 5: x 431.2 .. 1120.3, plate top 201.7      names below y 100
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

## **The moon, over the viewer's shoulder.** The owner: *"for the lobby and the
## main menu, there should be some faint moon lighting coming from above the
## camera, currently it's just tough with the one main center light that is
## really orange. This new moon lighting should be about 1/3 the strength of
## the campfire lighting."*
##
## The colour is the island's own moon (`Arena.MOON_COLOR`), so the menu and the
## match are lit by one night and retuning either retunes both — the same
## argument that has this scene loading `arena_env.tres` rather than an
## environment of its own (D-009).
##
## **The direction is computed, not written down**, because there are two
## cameras and "above the camera" is a different bearing for each: see
## `_moon_direction`. It replaces a moon that pointed at the island's fixed
## `(-0.42, 0.38, -0.82)` — in front of the lens and to the left, which is the
## one place a fill light cannot reach a face that is turned toward the lens.
const MOON_COLOR := Color(0.62, 0.72, 1.0)

## How far the moon is tipped down from the horizon, in degrees.
##
## 52. Under about 40 the light skims the ground and the Bogs' own shadows run
## the length of the glade toward the camera; over about 60 it is a toplight and
## the eye sockets go dark, which is the one thing a fill light is here to stop.
## At 52 the terminator on a Bog's head sits just under the antennae, the nose
## casts nothing, and the ground in front of the group picks up enough blue to
## read as ground rather than as the edge of the firelight.
const MOON_PITCH_DEGREES := 52.0

## The moon's **directional** energy, and it is not the fire's number over three.
##
## "A third of the campfire" is a ratio between two lights measured in different
## units: the fire is an `OmniLight3D` at energy 3.0 with a 1.6 falloff over an
## 11 m range, so what actually lands on a body depends on how far away it is
## standing, and the directional moon lands the same everywhere. The only honest
## comparison is the one on screen, so it was taken there. The menu was rendered
## three times with the flicker held at zero — fire alone, moon alone at energy
## 1.0, and both lights off — and a 90x115 px patch of the hero Bog's belly was
## averaged in each, converted out of sRGB to linear and weighted to luma. The
## third pass is the sky ambient, and it is subtracted from the other two so
## what is compared is what each *light* put on him:
##
##   both lights off (sky ambient alone)   0.00006 linear luma
##   the fire alone, over ambient          0.05105
##   the moon at energy 1.0, over ambient  0.03797
##
## So a third of the fire on the body is `0.05105 / 3 / 0.03797` = **0.448**, and
## that is where 0.45 comes from rather than from 3.0 over three. The same table
## says what the neighbours would be: 0.30 is 0.22 of the fire and 0.60 is 0.45.
## 0.30 was rendered as well and it is a good picture — warmer, a shade more
## night — but the owner asked for a third and a third is 0.45, so this is the
## number and that render is the one to go back to if the glade ever reads as an
## overcast afternoon with a bonfire in it.
##
## Two things the ratio does not say, and both are why this looks like a bigger
## change than a third: the moon arrives from behind the lens, so it lands on
## every surface the camera can see and the fire only rakes the near side of
## them; and the glade beyond the fire's 11 m had no direct light at all before,
## so the treeline goes from ambient-only to lit. The fire is still the key on
## the subject by three to one, which is what was asked for.
const MOON_ENERGY := 0.45

var _camera: Camera3D
var _fire: OmniLight3D
var _letters: MenuLetters
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
	_build_moon()
	_build_ground()
	_build_glade()
	_build_fire()
	_build_letters()

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
		# **Beside the fire, not behind it**, which is the composition the owner
		# picked for the letters round: fire centre-left with B·O·G floating
		# over it, and the Bog standing to its right lit from the side.
		#
		# He used to stand 2.05 m *beyond* the flame, facing back across it, so
		# that the only warm source in the glade was square in his face. That
		# was the right answer while the fire was the centre of the picture; it
		# is the wrong one now, because the letters own the space over the fire
		# and a Bog behind them is a Bog with a wordmark across his chest. So
		# he comes round the flame instead of over it.
		#
		# Along the **camera's own right** — which is what "beside" means once
		# the lens is off-axis. The same distance straight out along +X would
		# walk him toward the lens as well, and that costs twice: he is drawn
		# larger and his feet drop toward the button bar. The camera's right is
		# the one direction that buys separation in the *frame* rather than
		# separation in some other direction.
		#
		# **2.20 m right and 0.50 m back**, from 1.85 and 0. The owner: *"the
		# BOG body in main menu needs to be moved over to the right a little
		# more"* and *"also back the BOG away from the camera a little bit as
		# well."* Both are one step along a camera axis, so both are solved the
		# same way and land at `2.20 * right + 0.50 * forward`, which is
		# `(1.86, 0, -1.28)` in the glade. Measured through the lens by
		# `ui_range menu_letters`, and this is what the two moves bought:
		#
		#   the hero capsule  x 807..1093 -> 894..1163,  y 108..676 -> 128..663
		#   air to the wordmark    112 px -> 199 px
		#   his feet          y 632 (0.702 down) -> y 593 (0.659)
		#
		# The 0.50 m back is 6.7 per cent more distance, so he is drawn 6 per
		# cent smaller and his feet rise 39 px — 171 px of clearance over the
		# button bar at 764 now, up from 132. It also takes the fire from 1.85 m
		# to 2.26 m off him, which is a quarter less key on the body; the moon
		# arriving over the camera's shoulder is what pays that back, and the
		# two changes landed together for that reason.
		#
		# **177.7 degrees**, and it is two numbers, re-solved for the new spot
		# because the rule is a rule and not an angle. From here the lens bears
		# 195.4 and the flame bears 124.5 — 71 degrees apart, down from 86,
		# because stepping back off a fire closes the angle between it and the
		# lens — and this is a quarter of that turn off the lens, toward the
		# flame. A quarter is the whole of the lighting: the key then lands 53
		# degrees off his facing, on the far cheek from the lens, which is a
		# short-side key and is why the face has a shadow side at all. Square to
		# the camera it would be flat, and turned the other way the fire would
		# be lighting the side we can already see.
		return Transform3D(Basis(Vector3.UP, deg_to_rad(177.7)), Vector3(1.86, 0.0, -1.28))

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
	_refresh_letters()
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


## The wordmark is not in the portrait either, and for `_bog_wanted`'s reason
## one step further on. The page is a picture of **one body**: the ring goes,
## the subject's own nameplate goes, and three glowing letters hanging over the
## fire behind his ear are the same kind of thing — scenery that belongs to the
## room rather than to the Bog being dressed. They come straight back when the
## page closes, because nothing was moved, only hidden.
func _refresh_letters() -> void:
	if _letters != null:
		_letters.visible = not _focused


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


## Where the moon hangs, as a unit vector **pointing at it** from the glade —
## the island's convention (`Arena.MOON_DIRECTION`), so the two read the same
## way round.
##
## Behind the camera and above it, which is the whole of the owner's note. The
## camera's own forward is flattened to the ground plane first and then the
## vector is tipped back up by `MOON_PITCH_DEGREES`: flattening is what makes
## this one rule rather than two, because the menu lens is 12 degrees down and
## the lobby's is 17, and a moon derived from the unflattened forward would sit
## five degrees lower over the lobby for no reason anybody could see.
##
## It is per formation and not one number because the two cameras do not share a
## bearing: the menu looks north-west across the fire at the hero, the lobby
## looks north at the ring. One fixed direction is "over the shoulder" for at
## most one of them, and for the other it is a sidelight.
##
## **The sky's moon disc follows this** (`arena_sky.tres` has
## `moon_follow_light`), so re-aiming the light moves the disc — and out of
## shot, which is where it already was. The disc sits 52 degrees up; the menu
## frame reaches 0 degrees above the horizon and the lobby's 1.2, so neither
## camera has ever seen it. What does change is the radiance cubemap the ambient
## is read from, by the small amount a 0.038-radian disc moving across a night
## sky is worth.
func _moon_direction() -> Vector3:
	var eye: Vector3 = FRAMING[formation]["eye"]
	var look: Vector3 = FRAMING[formation]["look"]
	var ahead := Vector3(look.x - eye.x, 0.0, look.z - eye.z)
	if ahead.length_squared() < 0.0001:
		ahead = Vector3.FORWARD
	ahead = ahead.normalized()
	var pitch := deg_to_rad(MOON_PITCH_DEGREES)
	return (-ahead * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


## The fill light, and the only cool one: a moon over the viewer's shoulder.
##
## **Placed and then aimed**, rather than given a rotation, for the reason
## `Arena._build_environment` gives: the sky shader reads LIGHT0's *direction*
## and draws its moon there, so a rotation set by hand and a direction written
## in a constant are two claims that can disagree. Standing the node on the
## vector and telling it to look at the origin leaves exactly one claim.
func _build_moon() -> void:
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	add_child(moon)
	moon.position = _moon_direction() * 80.0
	moon.look_at(Vector3.ZERO, Vector3.UP)
	moon.light_color = MOON_COLOR
	moon.light_energy = MOON_ENERGY
	# Low, and lower than the island's 0.35. Moonlight on a damp Bog reads as a
	# wet highlight the moment the specular term is allowed to compete with the
	# fire's, and a wet hero is a plastic hero. 0.2 keeps a rim on the antennae
	# and gives up the cheek.
	moon.light_specular = 0.2
	moon.shadow_enabled = true
	# The whole glade is 26 m across and the subject is inside 4 m of the fire,
	# so a 90 m shadow range spends its map on trees. At 40 m the Bogs' own
	# shadows are the crisp thing and the treeline is the soft thing, which is
	# the right way round.
	moon.directional_shadow_max_distance = 40.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# Softened, because this is a fill: a hard-edged second shadow crossing the
	# fire's would say there are two suns.
	moon.shadow_blur = 1.6
	# Half the island's, for the same reason the energy is what it is: the fire
	# owns the halo in the fog here (`_build_fire` sets 2.0) and a moon that
	# lights the mist as strongly turns the glade's air grey.
	moon.light_volumetric_fog_energy = 0.5


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


## B·O·G floating over the fire, on the fire (D-098: one home per concern —
## the rig knows how to be three letters and nothing about where a fire is).
##
## **A child of `Fire`, so it cannot drift off it.** The whole point of the
## arrangement is that the letters hover over the flame; parented to the pit,
## moving the fire moves them, and there is no second position to keep in step.
## It also means `HOVER_HEIGHT` is height over the *fire*, which is the number
## anybody looking at the screen would measure.
##
## The rig is turned to wear the camera's own yaw, which lies the row flat in
## the image plane. Facing the eye point instead would be the obvious thing and
## it is wrong by ten degrees here, because the lens is aimed to the right of
## the fire rather than at it: the row would run away from the camera and the B
## would be drawn 13 per cent smaller than the G. Three letters of a wordmark
## at three sizes is a wordmark nobody drew.
func _build_letters() -> void:
	var pit := get_node_or_null("Fire") as Node3D
	if pit == null:
		return
	var eye: Vector3 = FRAMING[formation]["eye"]
	var look: Vector3 = FRAMING[formation]["look"]
	_letters = MenuLetters.new()
	_letters.name = "MenuLetters"
	# Before `add_child`, so `MenuLetters._build` measures its glyph widths
	# along the row it is actually going to stand on.
	_letters.rotation.y = Bog.yaw_towards(
		Vector3(look.x - eye.x, 0.0, look.z - eye.z))
	pit.add_child(_letters)


## Send the letters out of the top of frame and come back when the last one has
## gone; `Lobby._on_match_start` awaits this before the scene changes, on every
## peer. A backdrop with no rig returns at once rather than making the caller
## think about it.
func letters_leave() -> void:
	if _letters == null:
		return
	await _letters.leave()


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
