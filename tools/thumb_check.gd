extends Node
## Every map in the carousel still looks like the map it is (D-175). Development
## tool, not shipped.
##
##     Godot --headless --path . tools/thumb_check.tscn
##
## `tools/map_thumbs.gd` bakes the lobby's seven photographs and stamps each one
## with a hash of what it was a picture of. This recomputes those hashes and
## fails when one no longer matches — a map that was rebuilt and never
## re-photographed — naming the map and the one-argument run that fixes it.
##
## Headless and instant, which is the whole reason the check and the bake are
## two tools: baking seven arenas needs a window and the best part of a minute,
## and that does not belong in a gate. This reads files and renders nothing.
##
## What counts as a map's inputs is `map_thumbs.inputs_of` and is deliberately
## narrow — the map's own scene, script(s) and environment, plus the catalog row
## the camera is solved from. A comment-only edit to a map script does turn this
## red; that is the price of the check being deaf to nothing inside those files,
## and the cure is one command.

const THUMBS := preload("res://tools/map_thumbs.gd")

## Printed under any map that has moved, with the id filled in. The same line
## `docs/STATUS.md` carries for the baker.
const REBAKE := "\"$GODOT\" --path . --resolution 960x540 tools/map_thumbs.tscn -- %s"

var _failures: int = 0


func _ready() -> void:
	var stamps := THUMBS.load_stamps()
	for id: String in MapCatalog.ids():
		var thumb := MapCatalog.thumb_path(id)
		if not FileAccess.file_exists(thumb):
			_stale(id, "no thumbnail has ever been baked")
			continue
		if not stamps.has(id):
			_stale(id, "the thumbnail is unstamped")
			continue
		var want := THUMBS.stamp_of(id)
		if String(stamps[id]) != want:
			_stale(id, "the map has changed since its thumbnail was baked")
			continue
		print("thumb_check: %-8s ok" % id)

	print("thumb_check: %d maps, %d stale" % [MapCatalog.ids().size(), _failures])
	print("thumb_check: %s" % ("PASS" if _failures == 0 else "FAIL"))
	get_tree().quit(1 if _failures > 0 else 0)


## The command comes with the complaint. A gate line that says only "stale" is a
## line somebody has to go and read a tool's header to act on.
func _stale(id: String, why: String) -> void:
	_failures += 1
	print("thumb_check: %-8s STALE — %s" % [id, why])
	print("thumb_check:          re-bake with: %s" % (REBAKE % id))
