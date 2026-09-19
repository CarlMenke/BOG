class_name PouchMesh
extends Node3D
## The small woollen loot pouch a Bog captures a letter into.
##
## The owner, on what a capture should look like: *"there is a small woolen loot
## pouch in the user's left hand, down by their hip, maybe a little up and out;
## as the time progresses the letter gets smaller and slowly moves down into the
## pouch"*. That sentence is the whole specification for this file — the pouch
## is not a container in any code sense, it is the **destination the letter is
## seen to fall into**, and everything about it is built so that a shrinking
## card arriving at its mouth reads as a thing going in rather than a thing
## going behind.
##
## **Built from primitives, and that is now a stand-in with a date on it.** The
## original argument was that 18 cm of object at arm's length does not need a
## mesh, and the one thing a modelled pouch would buy — cloth that creases — is
## the one thing nobody looks for on a prop that size. Carl watched it and asked
## for a bigger bag with life in it, which is two different answers: the *size*
## is these constants and moved here (D-172), the *bag* is a Tripo sack under
## BOG-17. Nothing below is sculpted any further — a more elaborate primitive is
## the shape D-135 exists to refuse — and the sway that gives it life is
## deliberately **not** in this file, because it has to survive the mesh landing:
## `HeldGear` swings whatever is hanging in that fist.
##
## **The origin is the mouth's centre and the sack hangs down −Y.** That is not
## a convention, it is the contract: `CaptureRig` ends the letter's descent at
## `HeldGear.pouch_mouth_global()`, which is this node's own origin in the
## world, so the point the card aims at is the point the fabric opens at with no
## second offset to keep in step. Everything below therefore hangs *off* zero
## rather than being centred on it.
##
## One home for the shape (D-098): `HeldGear` hangs one of these in the left
## fist and `tools/preview_capture.tscn` photographs that one. There is no
## second pouch anywhere and nothing here decides when it is visible — that is
## `BogCombat._refresh_hand`'s, like every other object in a fist (D-065).

## The sack itself. A sphere of this radius, then stretched a quarter along its
## own Y by `BODY_SQUASH`, so it is an egg hanging point-up rather than a ball:
## a ball on a string reads as a bauble and the thing this has to read as is
## cloth with weight in the bottom of it.
##
## **0.095 and it was 0.065** (D-172). Carl, watching a capture: the bag wants
## to be bigger. 13 cm across is a coin purse, and what a Bog is doing with it
## is catching a letter the size of its own head — so the mouth was narrower
## than the thing going into it for the whole first half of the descent, which
## is the fault under the note. 19 cm across and 24 cm tall is a loot sack: a
## hand's span, big enough that the letter arriving at the mouth is a thing
## going *in* rather than a thing landing on top.
##
## Every other measurement in this file went up by the same 1.46, because the
## shape was right and only the scale was wrong; they are written out rather
## than multiplied so that the Tripo sack replacing all of them (BOG-17) has one
## table to be measured against.
const BODY_RADIUS := 0.095
const BODY_SQUASH := 1.25

## The gathered throat between the mouth and the sack, and the cord pulled
## tight round it. Short on purpose — a long neck turns the silhouette into a
## balloon, and what says "drawstring" is the *pinch*, which is the cinch ring
## below rather than the length of the tube.
const NECK_RADIUS := 0.041
const NECK_HEIGHT := 0.029
const CINCH_INNER := 0.038
const CINCH_OUTER := 0.050

## The two loose ends of the drawstring, splayed so they do not read as one
## stick. They are the only part of this that moves the eye, and they are why
## the pouch is legible from the side as well as from the front.
const CORD_RADIUS := 0.006
const CORD_LENGTH := 0.088
const CORD_SPLAY := 22.0

## The open mouth: a ring of gathered fabric at the origin, slightly narrower
## than the cinch below it. It exists for the letter's sake rather than the
## pouch's — a descent that ends in mid-air over a neck looks like a card
## stopping short, and a descent that ends *inside a ring* looks like a card
## going in.
const MOUTH_INNER := 0.029
const MOUTH_OUTER := 0.047

## Coarse on purpose, for `WardFlash`'s reason one file over: this is a 19 cm
## object held at a Bog's hand and nobody has ever counted its facets.
const SEGMENTS := 12
const RINGS := 6

## Undyed wool and waxed cord. Both fully rough, because the one way a
## primitive sack stops reading as cloth is a specular highlight sliding across
## it — a sphere with a hot spot is a marble, at any albedo.
const WOOL := Color(0.45, 0.36, 0.27)
const CORD := Color(0.62, 0.53, 0.36)


## Build one, mouth at the origin, hanging down −Y.
##
## Static and returning the node, exactly as `Pickup.build_card` is and for its
## reason: the caller is a hand rather than a scene, so there is nothing for a
## `.tscn` to be instanced into, and the one builder is what stops a preview's
## pouch and a match's pouch drifting apart.
static func build() -> Node3D:
	var pouch := PouchMesh.new()
	pouch.name = "Pouch"
	var wool := _fabric(WOOL)
	var cord := _fabric(CORD)

	# Down from the mouth in the order a drawstring sack is actually made: the
	# ring you look into, the throat, the cord round the throat, then the
	# weight.
	pouch._add(_torus(MOUTH_INNER, MOUTH_OUTER), wool, Vector3.ZERO)
	pouch._add(_tube(NECK_RADIUS, NECK_HEIGHT), wool,
		Vector3(0.0, -NECK_HEIGHT * 0.5, 0.0))
	pouch._add(_torus(CINCH_INNER, CINCH_OUTER), cord,
		Vector3(0.0, -NECK_HEIGHT, 0.0))

	var body := pouch._add(_ball(BODY_RADIUS), wool,
		Vector3(0.0, -NECK_HEIGHT - BODY_RADIUS * BODY_SQUASH, 0.0))
	# The squash goes on the **node** and not on the mesh, so the sphere is
	# still a sphere and one `SphereMesh` could be shared if this ever became
	# eight pouches instead of one.
	body.scale = Vector3(1.0, BODY_SQUASH, 1.0)

	# Two tails off the cinch, splayed to opposite sides and pitched apart, so
	# they cross nothing and read as two.
	for side: float in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.name = "Cord%s" % ("Left" if side < 0.0 else "Right")
		hinge.position = Vector3(0.0, -NECK_HEIGHT, 0.0)
		hinge.rotation_degrees = Vector3(CORD_SPLAY * 0.4, 0.0, CORD_SPLAY * side)
		pouch.add_child(hinge)
		var tail := MeshInstance3D.new()
		tail.mesh = _tube(CORD_RADIUS, CORD_LENGTH)
		tail.material_override = cord
		tail.position = Vector3(0.0, -CORD_LENGTH * 0.5, 0.0)
		tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hinge.add_child(tail)

	return pouch


## How far the sack hangs below its own mouth, in metres. For the preview and
## for anything that has to know where the bottom of this is without measuring
## an AABB — derived from the constants above rather than written down, so a
## fatter sack cannot leave the number stale.
static func drop() -> float:
	return NECK_HEIGHT + BODY_RADIUS * BODY_SQUASH * 2.0


func _add(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	# No shadows anywhere on this prop. It is a hand's width across, it lives
	# against a body that is already shadowing itself, and a shadow map entry
	# per Bog per frame for a sack is eight of them in a match.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


static func _fabric(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 1.0
	# Zero specular rather than only full roughness: a rough dielectric still
	# carries a broad sheen, and a sheen on a 6 cm sphere is what turns wool
	# into a plum.
	mat.metallic_specular = 0.0
	return mat


static func _ball(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = SEGMENTS
	mesh.rings = RINGS
	return mesh


static func _tube(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = SEGMENTS
	mesh.rings = 1
	return mesh


static func _torus(inner: float, outer: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = SEGMENTS
	mesh.ring_segments = 6
	return mesh
