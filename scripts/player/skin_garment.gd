class_name SkinGarment
extends Node
## The clothes a skin folder carries: `art/skins/<name>/garment.glb`, worn on
## the Bog's own rig (D-163).
##
## `ElderRobe`'s sibling, and deliberately the same three lines of attach. The
## robe (D-037, D-099) is a garment a Bog wears because of what it *is* in the
## rules; this is a garment a Bog wears because of what a player *picked*, and
## the only real difference is that the robe is one file compiled into the game
## and this is whichever `PackedScene` `Skins.garment_of` hands over. Everything
## about putting cloth on a skeleton is identical — the mesh is bound to the
## same 49 `mixamorig_*` bones by name, so it inherits every clip in
## `art/generated/bog_clips.res` without a refit and without touching the body
## (`docs/SKIN_PIPELINE.md`, Route 3).
##
## The three load-bearing details of that attach are `ElderRobe`'s, for its
## reasons: the mesh keeps its `skin` and its `skeleton` NodePath stays at the
## default `".."`, which now resolves to the Bog's skeleton; its transform is
## cleared, because a skinned mesh is drawn in skeleton space and a leftover
## parent transform is a silent double-move; and its `owner` is nulled, because
## Godot warns about an owner from another scene the moment a node changes
## parent.
##
## **`attach` is static and is the only attach in the project**, called by this
## class, by the corpse (`BogRagdoll._adopt`) and by the two render tools that
## photograph a dressed body without ever building a `Bog` — `skin_thumbs.gd`
## and `preview_bog.gd`. A second, subtly different re-parent in a tool would
## mean the thing that is looked at and the thing that ships are not the same
## thing, which is the mistake `ElderRobe` names in its own docstring.
##
## A plain `Node` rather than a `Node3D`, `ElderRobe`'s reason exactly: it owns
## nothing in space.

## The `MeshInstance3D` inside a garment scene. Named by `tools/fit_garment.py`,
## and found by name rather than by index because a re-import can renumber
## children.
const MESH_NAME := "Garment"

## The re-parented cloth, or null if the attach never worked. Kept so `doff`
## frees exactly what `don` added — the mesh no longer lives under anything this
## node owns, so nothing else would take it away.
var _cloth: MeshInstance3D
## The scene it was cut from, kept so the corpse can be dressed in a second copy
## of the same clothes without being told which skin it wore (`BogRagdoll`).
var _scene: PackedScene


## Dress `bog` in `scene` and return the node that remembers it, or null if the
## rig would not take it.
##
## Static and returning the node rather than being constructed by the caller,
## `ElderRobe.don`'s shape: the failure case has to be *no garment at all*
## rather than a `SkinGarment` that quietly holds nothing.
static func don(bog: Bog, scene: PackedScene) -> SkinGarment:
	if bog == null or scene == null:
		return null
	var skeleton := bog.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		push_warning("SkinGarment: %s has no Skeleton3D to bind to" % bog.name)
		return null
	var cloth := attach(skeleton, scene)
	if cloth == null:
		return null

	var garment := SkinGarment.new()
	garment.name = "SkinGarment"
	garment._cloth = cloth
	garment._scene = scene
	bog.add_child(garment)
	return garment


## Re-parent the cloth out of `scene` onto `skeleton` and hand it back, or null
## with a warning if the scene holds no mesh to wear.
##
## Takes a `Skeleton3D` rather than a `Bog` because two of its three callers
## have no `Bog`: a corpse is a fresh `BOG.fbx` under a `BogRagdoll`, and the
## render tools photograph the raw import.
static func attach(skeleton: Skeleton3D, scene: PackedScene) -> MeshInstance3D:
	if skeleton == null or scene == null:
		return null
	var wardrobe := scene.instantiate() as Node3D
	var cloth := wardrobe.find_child(MESH_NAME, true, false) as MeshInstance3D
	if cloth == null:
		push_warning("SkinGarment: %s has no MeshInstance3D called '%s'"
			% [scene.resource_path, MESH_NAME])
		wardrobe.free()
		return null

	cloth.owner = null
	cloth.get_parent().remove_child(cloth)
	skeleton.add_child(cloth)
	cloth.transform = Transform3D.IDENTITY
	cloth.skeleton = NodePath("..")
	# The rest of that scene — the skeleton the exporter bound against, the
	# scene root — has done its job by existing in the file. Freed rather than
	# queued, `ElderRobe.don`'s reason: it was never in the tree.
	wardrobe.free()
	return cloth


## The cloth on the rig, for whoever has to paint it — `Bog.set_team_tint` puts
## the team's colour on the garment as well as on the body. Null once it is off.
func mesh() -> MeshInstance3D:
	return _cloth if is_instance_valid(_cloth) else null


## The clothes this Bog is wearing, as the scene they came out of, for whoever
## has to make a second copy of them — which today is the corpse.
func scene() -> PackedScene:
	return _scene


## Take it off and forget it. Called when the skin changes, which is the one way
## a garment ever comes off a living Bog: a player may pick again mid-match
## (D-144), and a Bog wearing last pick's shirt under this pick's paint is the
## bug this exists to stop.
func doff() -> void:
	if is_instance_valid(_cloth):
		# Off the skeleton **now** and freed at the end of the frame, which is
		# the one place this parts company with `ElderRobe.doff`. A robe comes
		# off and nothing replaces it; a skin change dons the next garment in the
		# same call, so a queued free alone would leave two shirts on one rig for
		# a frame — and anything asking the skeleton what it is wearing in that
		# frame would get both answers.
		if _cloth.get_parent() != null:
			_cloth.get_parent().remove_child(_cloth)
		_cloth.queue_free()
	_cloth = null
	queue_free()


## Is the cloth actually on the rig? `ElderRobe.is_worn`'s twin, asked by
## `tools/team_tint.gd` for its reason: "this Bog wears a garment skin" and
## "there is cloth on this skeleton" are two claims and the interesting bug is
## the one where they disagree.
func is_worn() -> bool:
	return is_instance_valid(_cloth) and _cloth.is_inside_tree()
