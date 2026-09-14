"""The bow's string — generated after the decimator has finished with the bow.

`BOW.glb` is a riser and two recurved limbs with green cord wrapped round each
nock, and nothing at all between them. A bow without a string is not a bow, and
a string that does not move when the shot is charged is worse than no string,
because the draw is the whole tell: a charge only the archer can see is not a
charge anyone can play against (D-025's own words about the spear).

**Why the string is not in the mesh that goes through the decimator.**
`fast_simplification.simplify` takes positions and faces and hands back a
shorter pair of them. It has never heard of a morph target. Author the shape key
first and the decimation renumbers every vertex underneath it: the deltas
survive as bytes, line up with nothing, and there is no field in glTF for the
file to admit that. So the string is never in the decimated mesh at all. It is a
*second* mesh and a second node, generated here out of the body the decimator
actually wrote, and appended to the file afterwards. That is not a rule somebody
has to remember to follow in the right order — there is no order in which it can
go wrong, because the two meshes never meet.

It costs one extra `MeshInstance3D` in the scene and buys a separate material,
which the string wanted anyway: there is no string anywhere in the bow's UV
atlas, so any UV invented for it would sample wood.

**Why a blend shape rather than a bone chain.** One float. `set_blend_shape_value`
on one node against the draw fraction is the same index-a-pose-by-a-continuous-
value move `gub_animator.gd` already makes for the jump arcs, and it needs no
second skeleton, no `Skin`, no second `AnimationPlayer` and nothing on the wire
beyond the draw fraction that has to replicate regardless. A bone chain would
buy the ability to bend the string in ways a bow's string does not bend.

**Why the linear interpolation is exact here and not an approximation.** A drawn
string is two straight segments meeting at the nocking point. Every vertex of
this tube is placed at a parameter `t` along the rest line and displaced by
`pull * DRAW * tri(t)`, where `tri` is the tent function peaking at the middle.
A blend weight `w` scales every delta by `w`, which scales the tent by `w`, which
is exactly the V of a string drawn `w` of the way. The in-between frames are not
eyeballed; they are right.

The one honest stylisation: the string's *length* grows with the draw, because
the limbs are not bending to pay for it. Bending the limbs would mean a shape
key on the decimated body too, which is the thing this module exists to avoid,
and nobody has ever looked at a game bow and noticed.

Generated in Python rather than authored in Blender because every number in it
is measured off the body that was just written: the nocks come from the limb
tips of the *decimated* mesh, the draw direction from where the riser sits
relative to the line between them, and the cord colour from the bow's own nock
wrap in the source texture. Author it by hand and it is correct against one
triangle budget and floats off the tips at the next one.
"""

import io

import numpy as np
from PIL import Image

from gltf_io import ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER

# The cord, in metres on the source's own scale (it is 0.99 m tip to tip).
#
# A real bowstring is 2 mm across and this one is 6 mm, because 2 mm on a bow
# held two metres from the camera is under a pixel: it aliases into a dotted
# line and then into nothing, which is the one thing the string must not do
# while the draw is being read. Six millimetres against a 25 mm limb still reads
# as cord rather than as rope.
STRING_RADIUS = 0.003

# Six sides and nine rings. Three rings is all a two-segment V needs; nine costs
# 96 triangles against the bow's 4000 and puts a vertex every 12 cm, which is
# what a later sag, serving, or a string that peels off the recurve as it draws
# would need — and none of that can be added afterwards to a tube that has no
# vertices to move.
STRING_SIDES = 6
STRING_RINGS = 9

# How far the nocking point travels at full draw.
#
# Derived rather than typed. A fully drawn recurve makes a V whose half-angle at
# the nocking point is about 30 degrees: an Olympic bow 1.73 m tip to tip, drawn
# 0.71 m from the throat of the grip over a 0.21 m brace, pulls its nocking point
# 0.50 m off the line between its tips, and atan(0.50 / 0.82) is 31.4 degrees.
# So the draw is a property of the angle, and it comes out of whatever the tip
# separation of the mesh in hand turns out to be.
DRAW_HALF_ANGLE_DEG = 30.0

# How much of each limb tip is averaged to find the nock. Wide enough to survive
# the decimator having thrown most of the tip's vertices away, narrow enough
# that the point stays inside the wood — which is where the string's end ring
# has to be, or the tube ends in mid-air with a visible open mouth.
NOCK_SLICE = 0.015

STRING_NODE = "BowString"
BODY_NODE = "BowBody"
SHAPE_NAME = "drawn"


def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def long_axis(pos):
    """Which axis the bow lies along — measured, because the source says so."""
    lo, hi = pos.min(axis=0), pos.max(axis=0)
    return int(np.argmax(hi - lo))


def measure_nocks(pos, axis):
    """The two points the string is tied to: the centroid of each limb tip.

    Taken off the decimated body rather than the source, so the string always
    meets the mesh that actually ships. `cord_colour` cross-checks the answer
    against where the art put its nock wrap.
    """
    v = pos[:, axis]
    lo = pos[v <= v.min() + NOCK_SLICE].mean(axis=0)
    hi = pos[v >= v.max() - NOCK_SLICE].mean(axis=0)
    return lo.astype(np.float64), hi.astype(np.float64)


def draw_direction(pos, axis, a, b):
    """Which way the string is pulled, and how far off the bow it starts.

    The archer's hand is on the riser and the string is pulled away from it, so
    the direction is the component of (string midpoint -> riser) perpendicular
    to the string, negated. The length of that component is the brace height,
    which is worth printing: if it ever comes out near zero the source has been
    replaced by a flat bow and the string is about to be drawn sideways.
    """
    mid = 0.5 * (a + b)
    u = (b - a) / np.linalg.norm(b - a)
    near = np.abs(pos[:, axis] - mid[axis]) < 0.05 * abs(b[axis] - a[axis])
    riser = pos[near].mean(axis=0).astype(np.float64)
    off = (riser - mid) - np.dot(riser - mid, u) * u
    brace = float(np.linalg.norm(off))
    return -off / brace, brace, riser


def cord_colour(source, axis):
    """The string's colour, taken from the bow's own nock wrap.

    The art wraps green cord round each tip; a string of that cord is the one
    colour on this model that is already established as string. The wrap is
    found by its hue in the base texture, restricted to the outer fifth of each
    limb so the matching green studs on the riser do not drag the answer.

    The *lit* colour, not the mean: the texture is a photogrammetry-style bake
    with its own shading in it, and the mean of a wrapped cylinder is the colour
    of the side facing away from the light. Averaging the brightest fifth gives
    the albedo the material wants. Returned linear, which is what glTF's
    `baseColorFactor` is in.
    """
    prim = source.doc["meshes"][0]["primitives"][0]
    pos = source.read_accessor(prim["attributes"]["POSITION"]).astype(np.float64)
    uv = source.read_accessor(prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
    image = source.doc["images"][0]
    img = Image.open(io.BytesIO(source.view_bytes(image["bufferView"]))).convert("RGB")
    tex = np.asarray(img).astype(np.float64) / 255.0
    th, tw = tex.shape[:2]
    texel = tex[np.clip((uv[:, 1] * th).astype(int), 0, th - 1),
                np.clip((uv[:, 0] * tw).astype(int), 0, tw - 1)]

    v = pos[:, axis]
    span = v.max() - v.min()
    tip = (v < v.min() + 0.2 * span) | (v > v.max() - 0.2 * span)
    green = ((texel[:, 1] > texel[:, 0] + 0.05) &
             (texel[:, 1] > texel[:, 2] + 0.05) &
             (texel[:, 1] > 0.2) & tip)
    if green.sum() < 20:
        raise SystemExit("bow_string: found only %d nock-wrap texels; the source "
                         "is not the wrapped bow this was measured against"
                         % int(green.sum()))
    picked = texel[green]
    lum = picked @ np.array([0.2126, 0.7152, 0.0722])
    lit = picked[lum >= np.percentile(lum, 80)].mean(axis=0)

    # Where the wrap is, so the caller can say whether the tips it measured and
    # the tips the art marked are the same tips.
    lo = pos[green & (pos[:, axis] < v.mean())].mean(axis=0)
    hi = pos[green & (pos[:, axis] > v.mean())].mean(axis=0)
    return srgb_to_linear(lit), lo.astype(np.float64), hi.astype(np.float64), int(green.sum())


def tube(a, b, pull, draw):
    """The string at rest and at full draw, sharing one topology.

    Returns (rest, drawn, normals, uv, faces). The cross-section frame is taken
    from the rest line and reused for the drawn pose, so the tube twists by the
    few degrees the segments rotate through and the normals do not have to move
    at all — which is why the morph target carries POSITION and nothing else. A
    6 mm cord's shading does not survive being looked at that closely anyway.
    """
    u = (b - a) / np.linalg.norm(b - a)
    e1 = pull
    e2 = np.cross(u, e1)
    e2 /= np.linalg.norm(e2)

    t = np.linspace(0.0, 1.0, STRING_RINGS)       # odd count, so 0.5 is a ring
    tent = 1.0 - np.abs(2.0 * t - 1.0)
    ang = 2.0 * np.pi * np.arange(STRING_SIDES) / STRING_SIDES
    radial = np.cos(ang)[:, None] * e1 + np.sin(ang)[:, None] * e2   # (sides, 3)

    centres = a + np.outer(t, b - a)
    rest = (centres[:, None, :] + STRING_RADIUS * radial[None, :, :]).reshape(-1, 3)
    drawn = rest + np.repeat(tent, STRING_SIDES)[:, None] * (pull * draw)[None, :]
    normals = np.tile(radial, (STRING_RINGS, 1))
    uv = np.stack([np.repeat(t, STRING_SIDES),
                   np.tile(np.arange(STRING_SIDES) / float(STRING_SIDES), STRING_RINGS)],
                  axis=1)

    faces = []
    for i in range(STRING_RINGS - 1):
        for j in range(STRING_SIDES):
            k = (j + 1) % STRING_SIDES
            v00, v01 = i * STRING_SIDES + j, i * STRING_SIDES + k
            v10, v11 = (i + 1) * STRING_SIDES + j, (i + 1) * STRING_SIDES + k
            faces.append((v00, v11, v10))
            faces.append((v00, v01, v11))
    faces = np.asarray(faces, dtype=np.int64)

    # Winding is easy to get backwards and impossible to see in a log, so check
    # it rather than claim it: a face of a convex tube must point the same way
    # as the radius through its own centroid.
    v0, v1, v2 = rest[faces[:, 0]], rest[faces[:, 1]], rest[faces[:, 2]]
    face_n = np.cross(v1 - v0, v2 - v0)
    centroid = (v0 + v1 + v2) / 3.0
    axis_t = ((centroid - a) @ u)[:, None]
    outward = centroid - (a + axis_t * u)
    if float(np.mean(np.einsum("ij,ij->i", face_n, outward))) <= 0.0:
        raise SystemExit("bow_string: tube is inside out")

    return (rest.astype(np.float32), drawn.astype(np.float32),
            normals.astype(np.float32), uv.astype(np.float32), faces)


def crossings(p, q, pos, faces):
    """Where along the segment p->q the string passes through the body's surface.

    Returns each crossing's distance from whichever end of the segment is
    nearer, in metres, sorted. Distances from the *nearer end* rather than
    parameters from the start, because the crossings that are supposed to be
    there are exactly the ones at the nocks: the string is tied inside the limb
    tips, so it leaves wood within a centimetre or two of each end, and what
    matters is whether anything happens after that.

    Moller-Trumbore, vectorised over every triangle at once. Nothing here asks
    the mesh to be watertight, which is just as well — the decimator splits its
    vertex buffer along the UV seams, so half of the body's edges belong to one
    triangle by index and two by position, and any inside/outside test built on
    winding numbers would be counting an artefact of the repack.
    """
    d = q - p
    length = float(np.linalg.norm(d))
    v0, v1, v2 = pos[faces[:, 0]], pos[faces[:, 1]], pos[faces[:, 2]]
    e1, e2 = v1 - v0, v2 - v0
    h = np.cross(d, e2)
    det = np.einsum("ij,ij->i", e1, h)
    ok = np.abs(det) > 1e-12
    inv = np.zeros_like(det)
    inv[ok] = 1.0 / det[ok]
    s = p - v0
    u = inv * np.einsum("ij,ij->i", s, h)
    w = np.cross(s, e1)
    v = inv * (w @ d)
    t = inv * np.einsum("ij,ij->i", e2, w)
    hit = (ok & (u >= 0) & (u <= 1) & (v >= 0) & (u + v <= 1) &
           (t > 1e-7) & (t < 1.0 - 1e-7))
    return np.sort(np.minimum(t[hit], 1.0 - t[hit]) * length)


def clearance(p, q, pos):
    """The closest the body comes to the segment p->q, away from its ends.

    The ends are excluded because the string is tied *inside* the limb tips, so
    the distance there is zero by design and would drown the number that matters.
    """
    d = q - p
    t = np.clip(((pos - p) @ d) / float(d @ d), 0.0, 1.0)
    near = (t > 0.05) & (t < 0.95)
    if not near.any():
        return float("inf")
    perp = (pos[near] - p) - np.outer(t[near], d)
    return float(np.linalg.norm(perp, axis=1).min())


def add_string(builder, source, body_pos, body_faces, log):
    """Append the string mesh, its node and its material to a built bow.

    `builder` is the `GltfBuilder` the decimator has already put the body into.
    Returns what the caller needs to prove, after the file is written, that the
    shape key in it is the shape key intended.
    """
    axis = long_axis(body_pos)
    a, b = measure_nocks(body_pos, axis)
    pull, brace, riser = draw_direction(body_pos, axis, a, b)
    colour, wrap_lo, wrap_hi, wrap_n = cord_colour(source, axis)

    span = float(np.linalg.norm(b - a))
    draw = float(np.tan(np.radians(DRAW_HALF_ANGLE_DEG)) * 0.5 * span)

    log("  string: nocks %s .. %s (%.3f m apart, axis %s)"
        % (np.round(a, 3).tolist(), np.round(b, 3).tolist(), span, "xyz"[axis]))
    # If the tips the decimator left and the tips the art wrapped in green cord
    # are not the same tips, the string is about to be tied to the wrong end of
    # something and the only symptom would be a picture nobody takes.
    drift = max(float(np.linalg.norm(a - wrap_lo)), float(np.linalg.norm(b - wrap_hi)))
    log("    nock wrap in the source texture (%d texels) sits %.1f mm from them"
        % (wrap_n, 1000.0 * drift))
    if drift > 0.05:
        raise SystemExit("bow_string: the limb tips and the nock wrap are %.3f m "
                         "apart; this is not the bow these numbers were measured "
                         "against" % drift)
    log("    riser centre %s -> brace height %.3f m, pull %s"
        % (np.round(riser, 3).tolist(), brace, np.round(pull, 3).tolist()))
    log("    full draw %.3f m (%.0f deg half-angle on a %.3f m string)"
        % (draw, DRAW_HALF_ANGLE_DEG, span))
    log("    cord colour %s linear, from the bow's own nock wrap"
        % np.round(colour, 4).tolist())

    rest, drawn, normals, uv, faces = tube(a, b, pull, draw)
    delta = (drawn - rest).astype(np.float32)

    # The string's own centre line, at rest and along both arms of the full-draw
    # V, against the wood.
    #
    # The *drawn* string is the one with a rule: past the nocks it must be in
    # clear air, because the pull direction having come out backwards — the one
    # way this can be catastrophically wrong — shows up as a string sawing
    # through the riser and as nothing else.
    #
    # The braced string is allowed to cross, and on this bow it does, twice a
    # side. The limbs of this model sweep out past the line between its own
    # nocks and come back to it at the recurve, so a straight string at brace
    # runs behind each limb for about four centimetres of its ninety-nine, the
    # nearer pass lying along the recurve the way a braced recurve's string
    # actually does. That is a fact about the art, not a fault, and the moment
    # the draw starts the string is clear of all of it. Recorded here so the
    # next person to read this log does not go looking for the bug.
    mid = 0.5 * (a + b) + pull * draw
    body = body_pos.astype(np.float64)
    tip_zone = 2.0 * NOCK_SLICE
    for what, p, q in (("at rest", a, b),
                       ("drawn, lower arm", a, mid),
                       ("drawn, upper arm", mid, b)):
        where = crossings(p, q, body, body_faces)
        far = where[where > tip_zone]
        log("    %-16s crosses the body %2d times, %d of them more than %d mm "
            "from a nock; nearest wood %.1f mm"
            % (what, len(where), len(far), int(1000 * tip_zone),
               1000.0 * clearance(p, q, body)))
        if far.size:
            log("      %s mm" % np.round(1000.0 * far, 1).tolist())
        if far.size and what != "at rest":
            raise SystemExit("bow_string: the string runs through the bow %s, "
                             "%.0f mm from the nearest nock; the pull direction "
                             "or the nocks are wrong" % (what, 1000.0 * far[0]))

    material = {
        "name": "BowString",
        "pbrMetallicRoughness": {
            "baseColorFactor": [float(colour[0]), float(colour[1]), float(colour[2]), 1.0],
            "metallicFactor": 0.0,
            "roughnessFactor": 0.65,
        },
        "doubleSided": False,
    }
    builder.doc.setdefault("materials", []).append(material)
    material_index = len(builder.doc["materials"]) - 1

    prim = {
        "attributes": {
            "POSITION": builder.add_accessor(rest, target=ARRAY_BUFFER, bounds=True),
            "NORMAL": builder.add_accessor(normals, target=ARRAY_BUFFER),
            "TEXCOORD_0": builder.add_accessor(uv, target=ARRAY_BUFFER),
        },
        "indices": builder.add_accessor(faces.astype(np.uint16).reshape(-1),
                                        target=ELEMENT_ARRAY_BUFFER),
        "material": material_index,
        # glTF morph targets are deltas, and `targetNames` lives in the mesh's
        # `extras` because the format never gave them a home of their own. It is
        # the spelling Blender writes and the one Godot reads, which is the only
        # reason it is the right spelling.
        "targets": [{"POSITION": builder.add_accessor(delta, target=ARRAY_BUFFER,
                                                      bounds=True)}],
    }
    mesh = {
        "name": STRING_NODE,
        "primitives": [prim],
        "weights": [0.0],
        "extras": {"targetNames": [SHAPE_NAME]},
    }
    builder.doc["meshes"].append(mesh)
    mesh_index = len(builder.doc["meshes"]) - 1

    # One shape key and no more, deliberately. Godot's `BLEND_SHAPE_MODE_NORMALIZED`
    # and `..._RELATIVE` differ only once two shapes have to share a budget, so a
    # file with exactly one of them reads the same under either, and the runtime
    # side cannot be got wrong in a way this build would not have caught.
    builder.doc["nodes"].append({"name": STRING_NODE, "mesh": mesh_index})
    node_index = len(builder.doc["nodes"]) - 1

    # The body node keeps a Tripo GUID for a name, which was fine while the file
    # held one mesh and nobody had to say which. It now holds two and step 6 has
    # to reach one of them by name, so both get named.
    root = builder.doc["nodes"][builder.doc["scenes"][builder.doc.get("scene", 0)]["nodes"][0]]
    body = builder.doc["nodes"][root["children"][0]]
    body["name"] = BODY_NODE
    builder.doc["meshes"][body["mesh"]]["name"] = BODY_NODE
    root["children"] = list(root["children"]) + [node_index]

    log("    %d verts, %d tris, one shape key %r on node %s/%s"
        % (len(rest), len(faces), SHAPE_NAME, root.get("name", "?"), STRING_NODE))

    return {
        "mesh": mesh_index,
        "shape": SHAPE_NAME,
        "rest": rest,
        "drawn": drawn,
        "draw": draw,
    }
