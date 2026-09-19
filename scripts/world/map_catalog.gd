class_name MapCatalog
extends RefCounted
## Every map a match can be played on, and the one place that knows what kind of
## thing each one is.
##
## For the whole of development there was exactly one map — Whisperbloom Hollow,
## generated from `Net.config.map_seed` (D-007) — and so "the map" was spelled
## out separately in three files: `arena.gd` built it, `SceneFlow` named it on
## the loading card, and the lobby offered a seed for it. Adding a second map by
## editing all three is how two of them end up disagreeing about which map is
## loading. This table is the single answer and `MatchConfig.map` is the key
## into it.
##
## Entries are plain Dictionaries rather than Resources because they are read
## from `_ready` on every peer during a build that already blocks the main
## thread: a table of literals costs nothing to load and has no import step that
## can fail.
##
## The fields:
##
##   id            the string that travels in the match config. Never rename
##                 one. An unknown id falls back to `DEFAULT`, which is the
##                 right answer for garbage off the wire and the wrong one for
##                 a rename — the rename would silently move every saved lobby
##                 back to the island.
##   display_name  what the lobby picker and the loading card call it.
##   kind          PROCEDURAL: `arena.gd` generates the world from the seed.
##                 STATIC: `arena.gd` instances `scene` and asks it for spawns.
##   scene         empty for a procedural map; a `res://` path for a static one.
##   loading_line  the line under the title on the loading card. If it contains
##                 `%d` it is formatted with the map seed — a static map has no
##                 seed to name, so its line must not contain one.
##   thumb_camera  where the lobby carousel's photograph of this map is taken
##                 from (D-162), as a partial override of `THUMB_CAMERA`. Never
##                 a world coordinate: see that constant.

enum Kind {
	PROCEDURAL,  ## grown from `Net.config.map_seed` by `arena.gd` itself
	STATIC,      ## a hand-made scene, instanced whole (see `static_map.gd`)
}

## What an unknown or missing id resolves to: the map that has always been here,
## and the only one that cannot fail to load because it has nothing on disk to
## load. `MAPS` must always contain it.
const DEFAULT := "hollow"

## Where a map is photographed from for the lobby's carousel (D-162), and what
## every `thumb_camera` row below is a partial override of.
##
## **A perspective, not a place.** `yaw` is the compass bearing the camera stands
## on, `pitch` how far it looks down, `zoom` how far back it stands as a multiple
## of the distance that just fits the map's half-span in the lens, and `look_at`
## how far up the map's own box the lens is pointed (0 is the floor, 1 the
## highest thing on it). `tools/map_thumbs.gd` solves the metres from the map's
## bounding box, so a map that is rebuilt — `quarry` is being redrawn as this
## lands — is re-photographed from the same angle rather than from a point that
## used to be over its rim.
const THUMB_CAMERA := {
	"yaw": 35.0,
	"pitch": -30.0,
	"zoom": 1.0,
	"look_at": 0.25,
	"fov": 50.0,
}

## Where the baked thumbs live. Beside the other generated art rather than in
## `art/maps/`, which is ignored except for the `.glb`s a map is built from.
const THUMB_DIR := "res://art/generated/map_thumbs"

## The practice range. Named here rather than spelled in `main_menu.gd` for the
## reason the whole file exists: the Practice button and the lobby's picker have
## to open the same map, and a second copy of the string is how they stop doing
## that.
const PRACTICE := "range"

const MAPS: Array[Dictionary] = [
	{
		"id": "hollow",
		"display_name": "Whisperbloom Hollow",
		"kind": Kind.PROCEDURAL,
		"scene": "",
		# Close in and side-on: the island is a night map, and at the distance
		# that frames the whole spawn ring it is a dark shape on dark water.
		# 125 puts the horizon's last light behind the trees.
		"thumb_camera": {"yaw": 125.0, "pitch": -24.0, "zoom": 0.55, "look_at": 0.35},
		"loading_line": "Growing the island from seed %d",
	},
	{
		"id": "rust",
		"display_name": "Rust",
		"kind": Kind.STATIC,
		"scene": "res://scenes/world/maps/rust.tscn",
		"thumb_camera": {"yaw": 35.0, "pitch": -38.0, "zoom": 0.95},
		# No `%d`: a static map has no seed to name, and the card would print
		# the literal "%d" if this said one.
		"loading_line": "Unloading the containers",
	},
	{
		"id": "safari",
		"display_name": "Kopje Crossing",
		"kind": Kind.STATIC,
		"scene": "res://scenes/world/maps/safari.tscn",
		# Static in a second sense as well: this one has no `.glb` behind it at
		# all. The scene is four nodes and a script that builds a hundred and
		# twenty-three rock platforms out of a layout table. From this table's
		# point of view that is none of its business, which is exactly what the
		# `kind` column is for.
		# Steep, because the kopje is a plateau on a flat plain and anything
		# shallower photographs the plain.
		"thumb_camera": {"yaw": 35.0, "pitch": -40.0, "zoom": 0.82},
		"loading_line": "Stacking the kopje",
	},
	{
		"id": "wharf",
		"display_name": "Lantern Wharf",
		"kind": Kind.STATIC,
		"scene": "res://scenes/world/maps/wharf.tscn",
		# Built from a table like Kopje Crossing, and the small one: a 43.2 m box
		# yard with two declared Capture B·O·G bases (D-056). It was 36 m until
		# the 1.2x pass, which multiplied every position in the layout and no
		# size in it.
		# 305 is the corner with the crane in it and the containers lit; a
		# shallower pitch than -38 is a photograph of the yard's own wall.
		"thumb_camera": {"yaw": 305.0, "pitch": -38.0, "zoom": 0.95},
		"loading_line": "Stringing the lanterns",
	},
	{
		"id": "yacht",
		"display_name": "Halcyon Wake",
		"kind": Kind.STATIC,
		"scene": "res://scenes/world/maps/yacht.tscn",
		# Built from a table too, and the tall one: four decks on one hull at
		# anchor, with the sea as the void (D-057).
		# The one map photographed from near the water: the hull reads as a
		# ship from beside it and as a deck plan from above, and the coast
		# D-057 put there is behind it at this bearing.
		"thumb_camera": {"yaw": 125.0, "pitch": -20.0, "zoom": 0.9, "look_at": 0.5},
		"loading_line": "Weighing anchor",
	},
	{
		"id": "quarry",
		"display_name": "Twin Quarry",
		"kind": Kind.STATIC,
		"scene": "res://scenes/world/maps/quarry.tscn",
		# Built from a table as well, and the first one drawn for Capture B·O·G
		# rather than fitted to it: a stone pit with each team's base a storey
		# up on a cut bench, reached by two haul ramps and nothing else (D-082).
		"thumb_camera": {"yaw": 35.0, "pitch": -40.0, "zoom": 0.9},
		"loading_line": "Cutting the benches",
	},
	{
		"id": "range",
		"display_name": "Highsun Grounds",
		"kind": Kind.STATIC,
		"scene": "res://scenes/world/maps/range.tscn",
		# The first row with a `practice` key, and the only one that has it. A
		# practice map is not a mode — `MatchConfig.WinCondition` is untouched —
		# it is a property of the *place*, because that is what the player
		# picked: the range is a map in this list chosen exactly like every
		# other one, and everything that follows from picking it (no clock, no
		# win check, a one-second respawn, no spawn protection) follows from
		# being *on* it. Read through `MatchConfig.is_practice` and its
		# `effective_*` accessors and nowhere else.
		"practice": true,
		# Standing well back, because the pads are all on the lodge apron and
		# the lanes they are pointed down are the map.
		"thumb_camera": {"yaw": 35.0, "pitch": -40.0, "zoom": 2.2, "look_at": 0.10},
		"loading_line": "Walking out the lanes",
	},
	# A static map is one more entry and nothing else in this file changes —
	# the lobby's picker, `SceneFlow`'s loading card and `arena.gd`'s branch all
	# read this table and none of them names a map.
	#
	# Do not add a row for a scene that is not on disk yet. Every scene a map
	# names is really loaded by `tools/playthrough.tscn`, so an entry pointing
	# at a file that has not landed fails the gate rather than waiting politely
	# for the art.
]


## The entry for `id`, or the default map's entry if nothing answers to it.
##
## Never returns empty, because every caller is mid-build with no useful way to
## handle "there is no map" — `arena.gd` is inside `_ready` and `SceneFlow` is
## mid-transition. `MatchConfig` sanitises the id on the way in, so by the time
## anything gets here a fallback means a bug or a peer from a future version,
## not a player choice being ignored.
static func get_entry(id: String) -> Dictionary:
	var found := _find(id)
	return found if not found.is_empty() else _find(DEFAULT)


## Every map id, in the order the lobby lists them. `ids()[n]` and
## `display_names()[n]` are the same map — that pairing is what lets the
## picker deal in indices while the config deals in ids.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in MAPS:
		out.append(String(entry["id"]))
	return out


static func display_names() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in MAPS:
		out.append(String(entry["display_name"]))
	return out


static func is_valid(id: String) -> bool:
	return not _find(id).is_empty()


## Whether this map is grown from the seed. The seed is meaningless for a static
## map, so this is what decides whether the lobby offers one and whether the
## loading card mentions it.
static func is_procedural(id: String) -> bool:
	return int(get_entry(id)["kind"]) == Kind.PROCEDURAL


## Whether this map is a place to practise rather than a place to compete.
##
## The defaulted `get` is what keeps the other six rows from having to say
## `"practice": false` — a map is competitive unless it says otherwise, which is
## the right way round for a key that exactly one entry will ever carry.
##
## **Nothing outside `MatchConfig` calls this.** The rules that follow from it
## are `MatchConfig.effective_*`, so there is one answer to "what does practice
## change" rather than one per caller. See `match_config.gd`.
static func is_practice(id: String) -> bool:
	return bool(get_entry(id).get("practice", false))


## Where this map's baked thumbnail is, whether or not one has been taken.
static func thumb_path(id: String) -> String:
	return "%s/%s.png" % [THUMB_DIR, String(get_entry(id)["id"])]


## The thumbnail itself, or `null` if this build has not got one. Null rather
## than a placeholder: the carousel draws the map's name under the picture
## either way, so a missing thumb costs the name of a map and not the ability to
## pick it.
static func thumb_of(id: String) -> Texture2D:
	var path := thumb_path(id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## Where `tools/map_thumbs.gd` stands to photograph this map: the default above
## with the entry's own row written over it, so a row says only what it changes.
static func thumb_camera(id: String) -> Dictionary:
	var row := THUMB_CAMERA.duplicate()
	var authored: Dictionary = get_entry(id).get("thumb_camera", {})
	for key: String in authored:
		row[key] = authored[key]
	return row


static func _find(id: String) -> Dictionary:
	for entry: Dictionary in MAPS:
		if String(entry["id"]) == id:
			return entry
	return {}
