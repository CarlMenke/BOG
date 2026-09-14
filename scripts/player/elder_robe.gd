class_name ElderRobe
extends Node
## The robe and hat a Gub wears while it is the Elder.
##
## This is the *gameplay* half of D-037, which built the asset and deliberately
## stopped there. `art/generated/elder.glb` is a purple robe and a wizard hat
## with no animation data at all: one `MeshInstance3D`, one `Skin` that binds by
## bone **name**, and a copy of the Gub's skeleton to have been bound against.
## Wearing it is therefore not "spawn a second Gub" — it is re-parenting that
## one mesh onto the Gub's own `Skeleton3D` and letting the clips it is already
## playing move the cloth for free.
##
## **The attach is the one `tools/preview_elder.gd` proves**, line for line, and
## deliberately so. That tool resolves all 49 bind names against a live Gub's
## skeleton and prints the verdict, which is the check that the robe binds at
## all; a second, subtly different attach path here would mean the thing that is
## checked and the thing that ships are not the same thing. If this ever stops
## working, `preview_elder.tscn` is where it says so first, with a list.
##
## Three details in that attach are each load-bearing:
##
## * the mesh keeps its `skin`, and its `skeleton` NodePath is left at the
##   default `".."`, which now resolves to the Gub's skeleton rather than the
##   one it shipped beside;
## * its transform is cleared, because a skinned mesh is drawn in skeleton space
##   and a leftover parent transform is a silent double-move;
## * its `owner` is nulled, because Godot warns about an owner from another
##   scene the moment a node changes parent and an owner is of no use to
##   something re-parented at runtime.
##
## **It is worn on every peer's copy of that Gub, not just the owner's** — the
## robe is the tell that tells everyone else who is dangerous, so it is put on
## by `MatchState._do_set_elder`, which runs everywhere (D-038).
##
## A plain `Node` rather than a `Node3D`: it owns nothing in space. The mesh it
## builds lives under the skeleton and is positioned entirely by the rig, and a
## transform on this would be a transform with nothing under it.

const MODEL := preload("res://art/generated/elder.glb")
## The `MeshInstance3D` inside that scene. Named by `tools/build_elder.py`, and
## found by name rather than by index for the reason every other reach into an
## imported subtree in this project is: a re-import can renumber children.
const MESH_NAME := "Elder"

## The re-parented cloth, or null if the attach never worked. Kept so `doff`
## frees exactly what `don` added — the mesh no longer lives under anything this
## node owns, so nothing else would take it away.
var _cloth: MeshInstance3D


## Dress `gub` and return the node that remembers it, or null if the rig would
## not take the robe.
##
## Static and returning the node rather than being constructed by the caller,
## because the failure case has to be *no robe at all* rather than an
## `ElderRobe` that quietly holds nothing: a Gub that is the Elder in the rules
## and a plain Gub on screen is the worst outcome available here, and a null is
## a thing the caller can see.
static func don(gub: Gub) -> ElderRobe:
	if gub == null:
		return null
	var skeleton := gub.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		push_warning("ElderRobe: %s has no Skeleton3D to bind to" % gub.name)
		return null

	var wardrobe := MODEL.instantiate() as Node3D
	var cloth := wardrobe.find_child(MESH_NAME, true, false) as MeshInstance3D
	if cloth == null:
		push_warning("ElderRobe: elder.glb has no MeshInstance3D called '%s'" % MESH_NAME)
		wardrobe.free()
		return null

	cloth.owner = null
	cloth.get_parent().remove_child(cloth)
	skeleton.add_child(cloth)
	cloth.transform = Transform3D.IDENTITY
	cloth.skeleton = NodePath("..")
	# Everything else in that scene — the spare skeleton, the scene root — has
	# done its job by existing in the file and is freed immediately. Freed
	# rather than queued: it was never in the tree, and `queue_free` on a node
	# outside it is a free that happens at an unspecified later moment.
	wardrobe.free()

	var robe := ElderRobe.new()
	robe.name = "ElderRobe"
	robe._cloth = cloth
	gub.add_child(robe)
	return robe


## Take it off and forget it. The robe is **consumed**, not dropped (D-038), so
## there is nothing to hand back — this is the whole of what happens to it.
func doff() -> void:
	if is_instance_valid(_cloth):
		_cloth.queue_free()
	_cloth = null
	queue_free()


## Is the cloth actually on the rig? Asked by `tools/match_rules.gd`, because
## "this Gub is the Elder" and "this Gub is wearing a robe" are two claims and
## the interesting bug is the one where they disagree.
func is_worn() -> bool:
	return is_instance_valid(_cloth) and _cloth.is_inside_tree()
