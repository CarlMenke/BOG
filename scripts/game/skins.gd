class_name Skins
extends RefCounted
## Which body a player is wearing. One value, chosen in the lobby, and the only
## thing about a Bog's *appearance* that is a choice.
##
## `Loadout`'s sibling, deliberately: same shape, same statics-only class, same
## `sanitize` rule, same "it is one more key in the roster row" networking
## (D-069). It is a second file rather than four more constants in `Loadout`
## because the two answer different questions and one of them has a second
## owner — a weapon is always *yours*, and in Teams a skin belongs to the
## **team**, which is a lifecycle `Loadout` has nothing to say about. Putting
## `TEAM_DEFAULTS` beside `CARRY_CLIPS` would have been one file about two
## things.
##
## A skin is a folder (D-100): `art/skins/<name>/basecolor.png` is a texture in
## the body's own UV layout, worn through `Bog.wear_skin`, and
## `art/skins/<name>/thumb.png` is the 128² head-and-shoulders the picker shows.
## Nothing here loads a `.glb`, a material or a mesh — a skin that is a *garment*
## (the Elder's robe) is the other kind and is not pickable.

## The pickable skins, in the order the picker shows them.
##
## **Appended to, never reordered**, for `Loadout.Weapon`'s reason: the *index*
## is what goes on the wire, what sits in a roster row and what sits in
## `team_skins`, so inserting a skin in the middle would silently turn one
## team's body into another's.
##
## `bog` is zero on purpose. It is the plain body — no texture, the imported
## yellow — and it is the default, so zero is what an absent key, a cleared
## dictionary and a roster row written by a harness that predates this all read
## as. It is a folder like the rest (`art/skins/bog/`) holding a README and a
## thumb and no `basecolor.png`, because "the body's own" is a real answer to
## "which skin" and the picker needs a tile for it.
##
## The folders under `art/skins/` that are **not** here are not oversights:
## `example` is D-100's worked example of how a recolour is made, `elder` is a
## garment worn by being the Elder (D-038), and `shirt` is a garment still on
## its way (docs/SKIN_PIPELINE.md). None is a thing a player picks.
##
## Two batches: the first thirteen recolours (D-108) and, after `void`, the
## eleven of 2026-09-18, which are baked rather than extracted
## (`tools/bake_skin.py`) because Tripo regenerated the sculpt for them.
const NAMES := ["bog", "bogina", "boo", "clank", "crag", "gilt", "glub", "gum",
	"muck", "rime", "roar", "slag", "toad", "void",
	"bloom", "buzz", "chip", "crack", "dash", "fudge", "gourd", "koi", "ooze", "volt", "wrap"]

## The plain body. See above.
const DEFAULT := 0

## The folder rule, in one place. `bog` has no file here and is the one name
## `texture_path` refuses to answer for.
const TEXTURE_PATH := "res://art/skins/%s/basecolor.png"

## The picker's tile. Every skin has one, `bog` included — it is the only
## picture of the plain body in the project.
const THUMB_PATH := "res://art/skins/%s/thumb.png"

## Loaded once, not per frame: a skin texture is 2048² and five megabytes, the
## lobby rebuilds its strip on every roster change, and a ring of eight Bogs is
## eight `wear_skin` calls per refresh. `load` on an already-loaded path is a
## cache hit in Godot, but it still takes the resource lock and still hashes the
## path, so this is one dictionary lookup instead. Static, so the cache is the
## project's rather than one lobby's, and survives the scene change into a match
## — which is the point: the skins in the ring are the skins in the arena.
static var _textures: Dictionary = {}
static var _thumbs: Dictionary = {}


## Turn anything that arrived from outside into a skin.
##
## `Loadout.sanitize`'s twin and the same one-rule-not-three argument: it reads a
## roster row, a `settings.cfg` and a value off the wire, and anything out of
## range, of the wrong type or missing entirely is the plain body.
static func sanitize(value: Variant) -> int:
	if value is not int and value is not float:
		return DEFAULT
	var index := int(value)
	if index < 0 or index >= NAMES.size():
		return DEFAULT
	return index


## The folder name, for a path or a log line.
static func skin_name(skin: Variant) -> String:
	return NAMES[sanitize(skin)]


## What the picker writes under the tile. `bog` is "Bog", which is the plain
## body's name and also the animal's, and that is the joke.
static func label(skin: Variant) -> String:
	return NAMES[sanitize(skin)].capitalize()


## Every skin, in picker order. A helper rather than `range(NAMES.size())` at
## each call site, so the strip and the harnesses iterate the same list.
static func all() -> Array[int]:
	var out: Array[int] = []
	for i in NAMES.size():
		out.append(i)
	return out


## Where this skin's texture lives, or "" for the plain body.
static func texture_path(skin: Variant) -> String:
	var index := sanitize(skin)
	return "" if index == DEFAULT else TEXTURE_PATH % NAMES[index]


## The texture to hand `Bog.wear_skin`, or **null for the plain body** — which
## is `wear_skin`'s own word for "put the imported texture back", so the default
## costs nothing and loads nothing.
static func texture_of(skin: Variant) -> Texture2D:
	var index := sanitize(skin)
	if index == DEFAULT:
		return null
	if not _textures.has(index):
		_textures[index] = ResourceLoader.load(TEXTURE_PATH % NAMES[index]) as Texture2D
	return _textures[index]


## The 128² tile, or null if it has not been rendered yet — which the picker
## draws as an empty square rather than refusing to build a strip.
static func thumb_of(skin: Variant) -> Texture2D:
	var index := sanitize(skin)
	if not _thumbs.has(index):
		var path := THUMB_PATH % NAMES[index]
		_thumbs[index] = ResourceLoader.load(path) as Texture2D \
			if ResourceLoader.exists(path) else null
	return _thumbs[index]


## The skin a team starts in, so that **teams differ the moment a match goes to
## Teams** rather than lining up as eight identical Bogs waiting for somebody to
## open the picker.
##
## Team 0 is the plain body and every team after it takes the next name in the
## list, which is a rule rather than a table because the only thing it has to
## guarantee is that no two teams start on the same one. The modulo cannot
## actually wrap — `MatchConfig` allows eight teams and there are twenty-five
## skins — but it is there so that adding a ninth team is a bad default rather
## than an index error.
static func default_for_team(team: int) -> int:
	if team < 0:
		return DEFAULT
	return team % NAMES.size()
