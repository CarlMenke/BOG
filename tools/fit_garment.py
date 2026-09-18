"""Fit a Tripo garment onto the BOG's own skeleton, headless, in Blender.

    "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --python tools/fit_garment.py -- SHIRT shirt

Route 3 of `docs/SKIN_PIPELINE.md`: an image AI draws the BOG wearing the
outfit, Tripo turns the picture into a dressed body, Tripo's segmentation cuts
the clothing back out, and this script puts the cut piece back where it came
from, pushes it outside the real body, borrows the body's own weights and
exports `art/skins/<skin>/garment.glb` bound to the 49 `mixamorig:*` bones the
clip library drives.  Godot reads the colon as an underscore and binds by
name, so no refit and no new clips.

Inputs (read only):
    art/bog/BOG.fbx                               the body and the rig
    assets/source/skins/<SOURCE>/<SOURCE>_dressed.glb   Tripo's dressed body
    assets/source/skins/<SOURCE>/<SOURCE>_garment.glb   Tripo's cut of the clothes
    assets/source/anims/*.fbx                     the five proof clips

Outputs (overwritten every run):
    art/skins/<skin>/garment.glb
    art/skins/<skin>/README.md
    build/review/<skin>_*.png

Development tool, not shipped.  Blender 5.2.
"""

from __future__ import annotations

import math
import os
import sys
import tempfile
import traceback

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

# --------------------------------------------------------------------------
# constants
# --------------------------------------------------------------------------

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

BODY_FBX = os.path.join(ROOT, "art", "bog", "BOG.fbx")
#: What Godot's `root_scale = 180` on `BOG.fbx` makes the body stand.
BODY_HEIGHT = 1.799
#: Where on the dressed body the garment's bounding box starts out, as a
#: fraction of its height.  Only a seed for the ICP below.
SEED_Z_FRACTION = 0.62
ICP_ITERATIONS = 30
#: Tripo hands back the cut with its UV seams unwelded — coincident vertices
#: that the subdivide, the shrinkwrap and the relax then move apart, opening
#: the seam into a crack with grey body showing through.  In dressed units
#: (the model is 1.0 tall), so ~0.9 mm on the finished body.
WELD_DISTANCE = 0.0005

PROOF_CLIPS = [
    ("idle", "Idle-BreathingIdle.fbx"),
    ("walk", "Walk-StandardWalk.fbx"),
    ("crouch", "CrouchIdle-CrouchIdle-2.fbx"),
    ("roll", "Roll-DiveRollFromStanding-2.fbx"),
    ("sword", "SwordCombo-GreatSwordComboSlash.fbx"),
]
PROOF_FRAMES = 4
PANEL = (500, 750)
TPOSE_PANEL = (750, 750)
BODY_COLOUR = (0.62, 0.62, 0.64, 1.0)
GARMENT_COLOUR = (0.85, 0.12, 0.12, 1.0)

SUMMARY: list[str] = []


def say(*parts) -> None:
    line = " ".join(str(p) for p in parts)
    print("fit_garment: " + line, flush=True)


def note(line: str) -> None:
    """Say it now and keep it for the summary block and the README."""
    say(line)
    SUMMARY.append(line)


def fail(line: str) -> None:
    raise RuntimeError(line)


# --------------------------------------------------------------------------
# small scene helpers
# --------------------------------------------------------------------------


def only(objs, what):
    if len(objs) != 1:
        fail("expected exactly one %s, found %d: %s" % (what, len(objs), [o.name for o in objs]))
    return objs[0]


def activate(obj, *also):
    bpy.ops.object.select_all(action="DESELECT")
    for o in (obj,) + also:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obj


def world_verts(obj) -> list[Vector]:
    m = obj.matrix_world
    return [m @ v.co for v in obj.data.vertices]


def bounds(points):
    xs = [p.x for p in points]
    ys = [p.y for p in points]
    zs = [p.z for p in points]
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def bvh_of(obj, depsgraph=None, with_polys=False):
    """A world-space BVH of `obj`, through the depsgraph when one is given.

    `find_nearest` hands back a polygon index into the list this built from, so
    `with_polys` returns that list too — it is how a hit is traced back to the
    body part the garment sank into."""
    if depsgraph is None:
        ev, mesh = obj, obj.data
    else:
        ev = obj.evaluated_get(depsgraph)
        mesh = ev.to_mesh()
    mat = ev.matrix_world
    verts = [mat @ v.co for v in mesh.vertices]
    polys = [list(p.vertices) for p in mesh.polygons]
    tree = BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=0.0)
    if depsgraph is not None:
        ev.to_mesh_clear()
    return (tree, polys) if with_polys else tree


def dominant_groups(obj):
    """Per vertex, the name of its heaviest vertex group."""
    names = [vg.name for vg in obj.vertex_groups]
    out = []
    for v in obj.data.vertices:
        best, best_w = "", -1.0
        for g in v.groups:
            if g.weight > best_w:
                best, best_w = names[g.group], g.weight
        out.append(best.replace("mixamorig:", ""))
    return out


def penetration(points, bvh):
    """(count inside, deepest depth, per-point nearest) against a closed BVH.

    A point is inside when it sits behind the nearest surface point's face
    normal; the depth is then its distance to that surface."""
    inside = 0
    deepest = 0.0
    hits = []
    for p in points:
        loc, nor, idx, dist = bvh.find_nearest(p)
        if loc is None:
            hits.append(None)
            continue
        signed = (p - loc).dot(nor)
        hits.append((loc, nor, dist, signed, idx))
        if signed < 0.0:
            inside += 1
            deepest = max(deepest, dist)
    return inside, deepest, hits


def inside_regions(hits, polys, body_dom, top=3):
    """Which body part each sunken vertex sank into, busiest first."""
    tally = {}
    for hit in hits:
        if hit is None or hit[3] >= 0.0:
            continue
        idx = hit[4]
        if idx is None or idx >= len(polys):
            continue
        for vi in polys[idx][:1]:
            name = body_dom[vi] if vi < len(body_dom) else "?"
            tally[name] = tally.get(name, 0) + 1
    order = sorted(tally.items(), key=lambda kv: -kv[1])[:top]
    return ", ".join("%s %d" % (n, c) for n, c in order) if order else "-"


def translate_object(obj, delta: Vector) -> None:
    obj.matrix_world = Matrix.Translation(delta) @ obj.matrix_world


# --------------------------------------------------------------------------
# 1. the body
# --------------------------------------------------------------------------


def load_body():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for coll in (bpy.data.actions, bpy.data.images, bpy.data.materials):
        for item in list(coll):
            coll.remove(item)

    bpy.ops.import_scene.fbx(filepath=BODY_FBX)
    arm = only([o for o in bpy.data.objects if o.type == "ARMATURE"], "armature in BOG.fbx")
    body = only([o for o in bpy.data.objects if o.type == "MESH"], "mesh in BOG.fbx")
    body.name = "Body"
    arm.name = "Armature"

    # The T-pose clip that rides along is noise here.
    for obj in (arm, body):
        if obj.animation_data:
            obj.animation_data_clear()
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)

    # Mixamo lands at rotation (90, 0, 0) and scale 0.01.  Bake that, so the
    # armature object is identity and the bones are Z-up in metres...
    activate(arm, body)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # ...then bake the one uniform factor that makes the body the height
    # Godot's `root_scale = 180` gives it, with the feet on the floor.
    lo, hi = bounds(world_verts(body))
    raw_height = hi.z - lo.z
    factor = BODY_HEIGHT / raw_height
    arm.matrix_world = Matrix.Scale(factor, 4) @ arm.matrix_world
    body.matrix_world = Matrix.Scale(factor, 4) @ body.matrix_world
    lo, hi = bounds(world_verts(body))
    drop = Vector((0.0, 0.0, -lo.z))
    translate_object(arm, drop)
    translate_object(body, drop)
    activate(arm, body)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    lo, hi = bounds(world_verts(body))
    note("body: imported %.5f m tall, scaled x%.4f -> %.4f m, feet at z=%.5f"
         % (raw_height, factor, hi.z - lo.z, lo.z))
    if abs((hi.z - lo.z) - BODY_HEIGHT) > 1e-3 or abs(lo.z) > 1e-4:
        fail("body did not land at %.3f m with feet at 0" % BODY_HEIGHT)
    if not arm.matrix_world.is_identity:
        fail("armature object is not identity after transform_apply")

    hips = arm.data.bones.get("mixamorig:Hips")
    if hips is None:
        fail("no mixamorig:Hips on the body armature")
    note("body: hips bone head at z=%.4f m (expect ~0.618), %d bones, %d verts"
         % (hips.head_local.z, len(arm.data.bones), len(body.data.vertices)))

    # The clip FBXs import at scale 0.01 like the body did, so their pose-bone
    # location curves want the same total factor.  transform_apply does not
    # touch fcurves; we multiply them by hand in the proof below.
    return arm, body, factor * 0.01


# --------------------------------------------------------------------------
# 2-4. the garment, put back where it came from and taken into body space
# --------------------------------------------------------------------------


def load_tripo(source_dir, source_name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(source_dir, source_name + "_dressed.glb"))
    dressed_new = [o for o in bpy.data.objects if o not in before]
    dressed = only([o for o in dressed_new if o.type == "MESH"], "mesh in the dressed glb")
    for o in dressed_new:
        if o is not dressed:
            bpy.data.objects.remove(o, do_unlink=True)

    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(source_dir, source_name + "_garment.glb"))
    garment_new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in garment_new if o.type == "MESH"]
    if not meshes:
        fail("the garment glb linked no mesh into its scene")
    # Only what the scene links arrives; the loose meshes in the file do not.
    garment = max(meshes, key=lambda o: len(o.data.vertices))
    for o in garment_new:
        if o is not garment:
            bpy.data.objects.remove(o, do_unlink=True)

    dressed.name = "Dressed"
    garment.name = "Garment"
    note("tripo: dressed mesh %d verts, garment mesh '%s' %d verts"
         % (len(dressed.data.vertices), garment.data.name, len(garment.data.vertices)))
    weld(garment, WELD_DISTANCE)
    return dressed, garment


def boundary_edges(obj) -> int:
    """Edges with one face: the shell's real openings, plus every seam Tripo
    left unwelded."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    n = sum(1 for e in bm.edges if len(e.link_faces) == 1)
    bm.free()
    return n


def weld(garment, distance):
    """Merge coincident vertices.  UVs live on loops, so the UV seams survive
    the weld; only the duplicate *positions* go."""
    before_verts = len(garment.data.vertices)
    before_edges = boundary_edges(garment)
    bm = bmesh.new()
    bm.from_mesh(garment.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=distance)
    bm.to_mesh(garment.data)
    bm.free()
    garment.data.update()
    after_edges = boundary_edges(garment)
    note("weld: merge by %.5f, %d verts -> %d, boundary edges %d -> %d"
         % (distance, before_verts, len(garment.data.vertices), before_edges, after_edges))
    if after_edges > before_edges * 0.6:
        say("WARNING: the weld barely changed the boundary count; the cracks may be "
            "something other than unwelded seams.")


def replace_on_dressed(dressed, garment):
    """Translation-only ICP: Tripo re-centres the cut piece on its own origin,
    so put it back on the surface it was cut from."""
    d_lo, d_hi = bounds(world_verts(dressed))
    d_height = d_hi.z - d_lo.z
    g_lo, g_hi = bounds(world_verts(garment))
    seed = Vector((
        (d_lo.x + d_hi.x) * 0.5,
        (d_lo.y + d_hi.y) * 0.5,
        d_lo.z + SEED_Z_FRACTION * d_height,
    )) - (g_lo + g_hi) * 0.5
    translate_object(garment, seed)

    bvh = bvh_of(dressed)
    mean = max_d = float("nan")
    for _ in range(ICP_ITERATIONS):
        pts = world_verts(garment)
        total = Vector((0.0, 0.0, 0.0))
        dists = []
        for p in pts:
            loc, nor, idx, dist = bvh.find_nearest(p)
            if loc is None:
                continue
            total += loc - p
            dists.append(dist)
        if not dists:
            fail("ICP found no nearest points on the dressed mesh")
        translate_object(garment, total / len(dists))
        mean = sum(dists) / len(dists)
        max_d = max(dists)

    note("icp: %d iterations, mean nearest %.5f, max nearest %.5f (dressed units, body is %.4f tall)"
         % (ICP_ITERATIONS, mean, max_d, d_height))
    if mean > 0.005:
        say("WARNING: the garment does not lie on the dressed body (mean %.5f > 0.005)." % mean)
        say("WARNING: the cut and the dressed model may not be the same generation. Continuing.")
    return d_height


def into_body_space(dressed, garment, body, d_height):
    scale = BODY_HEIGHT / d_height
    for obj in (dressed, garment):
        obj.matrix_world = Matrix.Scale(scale, 4) @ obj.matrix_world

    d_lo, d_hi = bounds(world_verts(dressed))
    b_lo, b_hi = bounds(world_verts(body))
    delta = Vector((
        (b_lo.x + b_hi.x) * 0.5 - (d_lo.x + d_hi.x) * 0.5,
        (b_lo.y + b_hi.y) * 0.5 - (d_lo.y + d_hi.y) * 0.5,
        -d_lo.z,
    ))
    for obj in (dressed, garment):
        translate_object(obj, delta)

    d_lo, d_hi = bounds(world_verts(dressed))
    d_span = d_hi.x - d_lo.x
    b_span = b_hi.x - b_lo.x
    note("into body space: scaled x%.4f; arm span dressed %.3f m vs body %.3f m (ratio %.3f)"
         % (scale, d_span, b_span, d_span / b_span))
    if not 0.85 <= d_span / b_span <= 1.18:
        say("WARNING: the dressed body's proportions differ from the BOG's by more than 15%.")

    bpy.data.objects.remove(dressed, do_unlink=True)


# --------------------------------------------------------------------------
# 5. push the garment outside the real body
# --------------------------------------------------------------------------


def densify(garment, levels):
    """Tripo's cut is a few hundred big flat faces.  The push-out below only
    moves *vertices*, so a face that spans a bulge of the body lets the body
    through even when both its corners are outside.  One simple (shape-keeping,
    UV-keeping) subdivision gives the shrinkwrap enough vertices to follow the
    surface it is wrapping."""
    if levels <= 0:
        return
    before = len(garment.data.vertices)
    md = garment.modifiers.new("Dense", "SUBSURF")
    md.subdivision_type = "SIMPLE"
    md.levels = levels
    md.render_levels = levels
    activate(garment)
    bpy.ops.object.modifier_apply(modifier=md.name)
    note("densify: %d simple subdivision(s), %d verts -> %d"
         % (levels, before, len(garment.data.vertices)))


def lift_inside(garment, bvh, offset):
    """Move every vertex still inside the body out to its nearest surface
    point plus the clearance.  Returns how many had to move."""
    inside, _depth, hits = penetration(world_verts(garment), bvh)
    if not inside:
        return 0
    inv = garment.matrix_world.inverted()
    moved = 0
    for i, hit in enumerate(hits):
        if hit is None:
            continue
        loc, nor, dist, signed, _idx = hit
        if signed < 0.0:
            garment.data.vertices[i].co = inv @ (loc + nor * offset)
            moved += 1
    garment.data.update()
    return moved


def shrinkwrap_out(garment, body, offset):
    """Shrinkwrap OUTSIDE_SURFACE guarantees every vertex at least `offset`
    clear of the body — not only the ones that were inside."""
    md = garment.modifiers.new("PushOut", "SHRINKWRAP")
    md.target = body
    md.wrap_method = "NEAREST_SURFACEPOINT"
    md.wrap_mode = "OUTSIDE_SURFACE"
    md.offset = offset
    activate(garment)
    bpy.ops.object.modifier_apply(modifier=md.name)


def clearance(points, bvh):
    """Signed gap from each point to the body; negative means inside."""
    gaps = []
    for p in points:
        loc, nor, idx, dist = bvh.find_nearest(p)
        if loc is None:
            gaps.append(0.0)
            continue
        gaps.append(dist if (p - loc).dot(nor) >= 0.0 else -dist)
    return gaps


def inflate(garment, bvh, offset, rounds=8):
    """Give every vertex `offset` of clearance by moving it along the
    *garment's* own outward normal, not the body's.

    The shrinkwrap cannot do this in a crease — the armpit, the fold under
    that enormous head — because the nearest body point there is the crease
    line itself and pushing out along one face's normal just presses the
    vertex into the other face.  The cloth's own normal points out of the
    crease, which is where cloth goes.
    """
    mesh = garment.data
    mat = garment.matrix_world
    rot = mat.to_3x3()
    inv = mat.inverted()
    moved_total = 0
    for _ in range(rounds):
        normals = [rot @ n.vector for n in mesh.vertex_normals]
        gaps = clearance([mat @ v.co for v in mesh.vertices], bvh)
        moved = 0
        for i, gap in enumerate(gaps):
            # Only nudge vertices that are already outside but too close.  A
            # vertex that is inside has no reliable outward direction of its
            # own — its normal may point straight through the body — and
            # marching it along one would send it out the far side; those are
            # the shrinkwrap's and lift_inside's job.
            if gap < 0.0 or gap >= offset - 1e-6:
                continue
            n = normals[i]
            if n.length < 1e-9:
                continue
            step = min(offset - gap, offset)
            world = mat @ mesh.vertices[i].co
            mesh.vertices[i].co = inv @ (world + n.normalized() * step)
            moved += 1
        mesh.update()
        moved_total += moved
        if moved == 0:
            break
    return moved_total


def push_out(garment, body, offset, relax):
    bvh = bvh_of(body)
    before_inside, before_depth, _ = penetration(world_verts(garment), bvh)

    shrinkwrap_out(garment, body, offset)
    shrunk_inside, _d, _h = penetration(world_verts(garment), bvh)
    manual = lift_inside(garment, bvh, offset)

    # Lifting a vertex that was centimetres inside leaves a crease.  Relax the
    # shell a little and push it back out, so the cloth drapes over the body's
    # shape instead of being dented into it.  The re-push has to be the
    # shrinkwrap, not just a fix of whatever ended up inside: a vertex the
    # smoothing leaves a hair's breadth outside keeps no clearance at all, and
    # that is exactly the vertex the body comes through once the rig bends.
    for _ in range(max(0, relax)):
        rm = garment.modifiers.new("Relax", "SMOOTH")
        rm.factor = 0.5
        rm.iterations = 1
        activate(garment)
        bpy.ops.object.modifier_apply(modifier=rm.name)
        manual += lift_inside(garment, bvh, offset)

    # One last shrinkwrap so every vertex keeps the full clearance, not just
    # the ones the relax pushed inside, and then inflate whatever the
    # shrinkwrap could not reach.
    shrinkwrap_out(garment, body, offset)
    manual += lift_inside(garment, bvh, offset)
    tight_before = sum(1 for g in clearance(world_verts(garment), bvh) if g < offset * 0.5)
    inflated = inflate(garment, bvh, offset)
    manual += lift_inside(garment, bvh, offset)

    after_inside, after_depth, _ = penetration(world_verts(garment), bvh)
    gaps = clearance(world_verts(garment), bvh)
    tight_after = sum(1 for g in gaps if g < offset * 0.5)
    note("push-out: offset %.4f m; inside before %d (deepest %.1f mm), after shrinkwrap %d, "
         "%d relax passes, %d vertices lifted by hand, inside after %d (deepest %.1f mm)"
         % (offset, before_inside, before_depth * 1000.0, shrunk_inside,
            relax, manual, after_inside, after_depth * 1000.0))
    note("push-out: clearance at rest, smallest %.2f mm, mean %.2f mm; under half the "
         "offset %d verts -> %d after %d inflate moves"
         % (min(gaps) * 1000.0, sum(gaps) / len(gaps) * 1000.0,
            tight_before, tight_after, inflated))
    if after_inside:
        say("WARNING: %d vertices are still inside the body after the push-out." % after_inside)


# --------------------------------------------------------------------------
# 6. weights from the body, then bind
# --------------------------------------------------------------------------


def smooth_weights(garment, passes, factor=0.5):
    """Laplacian smoothing of the garment's own weights, over the mesh's edges.

    Blender's Smooth Weights operator only polls in edit or weight-paint mode,
    which a background run has no business entering, and the rule here is
    simple enough to state outright."""
    mesh = garment.data
    n = len(mesh.vertices)
    weights = [{} for _ in range(n)]
    for v in mesh.vertices:
        for g in v.groups:
            if g.weight > 0.0:
                weights[v.index][g.group] = g.weight
    adjacency = [[] for _ in range(n)]
    for e in mesh.edges:
        a, b = e.vertices
        adjacency[a].append(b)
        adjacency[b].append(a)

    for _ in range(passes):
        nxt = []
        for i in range(n):
            acc = {k: w * (1.0 - factor) for k, w in weights[i].items()}
            neighbours = adjacency[i]
            if neighbours:
                share = factor / len(neighbours)
                for j in neighbours:
                    for k, w in weights[j].items():
                        acc[k] = acc.get(k, 0.0) + w * share
            nxt.append(acc)
        weights = nxt

    names = [vg.name for vg in garment.vertex_groups]
    for vg in list(garment.vertex_groups):
        garment.vertex_groups.remove(vg)
    groups = [garment.vertex_groups.new(name=nm) for nm in names]
    for i, acc in enumerate(weights):
        total = sum(acc.values())
        if total <= 0.0:
            continue
        for k, w in acc.items():
            if w / total > 1e-4:
                groups[k].add([i], w / total, "REPLACE")


def transfer_weights(garment, body, arm, influences, smooth):
    for vg in list(garment.vertex_groups):
        garment.vertex_groups.remove(vg)

    md = garment.modifiers.new("Weights", "DATA_TRANSFER")
    md.object = body
    md.use_vert_data = True
    md.data_types_verts = {"VGROUP_WEIGHTS"}
    md.vert_mapping = "POLYINTERP_NEAREST"
    md.layers_vgroup_select_src = "ALL"
    md.layers_vgroup_select_dst = "NAME"
    md.mix_mode = "REPLACE"
    md.mix_factor = 1.0

    activate(garment)
    bpy.ops.object.datalayout_transfer(modifier=md.name)
    bpy.ops.object.modifier_apply(modifier=md.name)

    # Nearest-surface weights put arm bones on one side of the armpit and
    # spine bones a centimetre away on the other; the cloth then shears along
    # that line and the body comes through in speckles.  Smoothing the
    # garment's own weights makes it deform as one shell.
    if smooth > 0:
        smooth_weights(garment, smooth)
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=influences)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)

    counts = {}
    for v in garment.data.vertices:
        for g in v.groups:
            if g.weight > 1e-5:
                name = garment.vertex_groups[g.group].name
                counts[name] = counts.get(name, 0) + 1
    for vg in list(garment.vertex_groups):
        if vg.name not in counts:
            garment.vertex_groups.remove(vg)

    if not counts:
        fail("the data transfer gave the garment no weights at all")
    note("weights: %d bones, <=%d influences per vertex, %d smoothing passes"
         % (len(counts), influences, smooth))
    for name, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        note("    %-28s %4d verts" % (name.replace("mixamorig:", ""), n))

    activate(arm, garment)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_NAME")
    if not any(m.type == "ARMATURE" for m in garment.modifiers):
        fail("the garment did not get an armature modifier")
    return counts


# --------------------------------------------------------------------------
# 7. one material
# --------------------------------------------------------------------------


def make_material(garment, skin_name):
    image = None
    for slot in garment.data.materials:
        if slot is None or not slot.use_nodes:
            continue
        for node in slot.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image is not None:
                image = node.image
                break
        if image:
            break

    mat = bpy.data.materials.new(skin_name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0
    if image is not None:
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.location = (-400, 200)
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        note("material: '%s', base colour %s %dx%d, roughness 0.9, metallic 0"
             % (skin_name, image.name, image.size[0], image.size[1]))
    else:
        say("WARNING: the garment carried no image texture; the material is flat.")

    garment.data.materials.clear()
    garment.data.materials.append(mat)
    garment.data.name = garment.name

    activate(garment)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    # Tripo ships the cut smooth-shaded; the subdivision and the push-out drop
    # its custom normals, so put smooth shading back with real creases kept.
    for op in ("shade_smooth_by_angle", "shade_auto_smooth", "shade_smooth"):
        fn = getattr(bpy.ops.object, op, None)
        if fn is None:
            continue
        try:
            fn(angle=math.radians(50.0)) if op != "shade_smooth" else fn()
        except TypeError:
            fn()
        break


# --------------------------------------------------------------------------
# 8. export
# --------------------------------------------------------------------------


def export(arm, garment, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "garment.glb")
    activate(garment, arm)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_skins=True,
        export_animations=False,
        export_apply=True,
        export_yup=True,
        export_image_format="AUTO",
    )
    if not os.path.exists(path):
        fail("the export wrote nothing to %s" % path)
    note("export: %s, %.0f KB" % (os.path.relpath(path, ROOT).replace("\\", "/"),
                                  os.path.getsize(path) / 1024.0))
    return path


# --------------------------------------------------------------------------
# 9. proof: the clips, measured and rendered, without Godot
# --------------------------------------------------------------------------


def action_fcurves(action):
    """Blender 5.x keeps fcurves under layers > strips > channelbags."""
    for layer in action.layers:
        for strip in layer.strips:
            bags = getattr(strip, "channelbags", None)
            if bags is None:
                continue
            for bag in bags:
                for fc in bag.fcurves:
                    yield fc


def assign_action(arm, action):
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = action
    slots = [s for s in action.slots if s.target_id_type in ("OBJECT", "")]
    if slots:
        arm.animation_data.action_slot = slots[0]
    elif action.slots:
        arm.animation_data.action_slot = action.slots[0]


def load_clip(path, loc_factor):
    before_objs = set(bpy.data.objects)
    before_acts = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=path)
    new_objs = [o for o in bpy.data.objects if o not in before_objs]
    new_acts = [a for a in bpy.data.actions if a not in before_acts]
    if not new_acts:
        fail("no action came out of %s" % path)
    action = new_acts[0]
    for o in new_objs:
        if o.animation_data:
            o.animation_data_clear()
        bpy.data.objects.remove(o, do_unlink=True)
    for a in new_acts[1:]:
        bpy.data.actions.remove(a)

    # The clip armature imports at scale 0.01 like the body did; applying an
    # armature's scale never touches its pose-bone location curves, so the
    # same total factor has to go on by hand.
    scaled = 0
    for fc in action_fcurves(action):
        if not fc.data_path.endswith(".location"):
            continue
        scaled += 1
        for kp in fc.keyframe_points:
            kp.co.y *= loc_factor
            kp.handle_left.y *= loc_factor
            kp.handle_right.y *= loc_factor
        fc.update()
    if scaled == 0:
        fail("found no location fcurves in %s" % path)
    return action, scaled


def facing(arm) -> Vector:
    bones = arm.data.bones
    foot = bones.get("mixamorig:LeftFoot")
    toe = bones.get("mixamorig:LeftToeBase")
    if foot is None or toe is None:
        return Vector((0.0, -1.0, 0.0))
    d = toe.head_local - foot.head_local
    d.z = 0.0
    if d.length < 1e-6:
        return Vector((0.0, -1.0, 0.0))
    return d.normalized()


def look_at(cam, target: Vector, direction: Vector, distance: float, ortho: float):
    z = Vector((direction.x, direction.y, 0.0)).normalized()
    up = Vector((0.0, 0.0, 1.0))
    x = up.cross(z).normalized()
    y = z.cross(x)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = target + z * distance
    cam.matrix_world = m
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho
    cam.data.clip_start = 0.01
    cam.data.clip_end = distance * 3.0


def setup_render(scene, body, garment):
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.display.shading.show_object_outline = True
    scene.display.shading.show_shadows = False
    scene.display.shading.show_cavity = False
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("Review") if scene.world is None else scene.world
    scene.world.use_nodes = False
    scene.world.color = (0.92, 0.92, 0.93)
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.resolution_percentage = 100
    body.color = BODY_COLOUR
    garment.color = GARMENT_COLOUR

    cam_data = bpy.data.cameras.new("ReviewCam")
    cam = bpy.data.objects.new("ReviewCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def render_to(scene, path, size):
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def read_png(path):
    img = bpy.data.images.load(path)
    img.colorspace_settings.name = "Non-Color"
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return px


def write_strip(panels, path):
    h = panels[0].shape[0]
    big = np.concatenate(panels, axis=1)
    out = bpy.data.images.new("strip", width=big.shape[1], height=h, alpha=False)
    out.colorspace_settings.name = "Non-Color"
    out.pixels = big.ravel().tolist()
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)


def proof(arm, body, garment, loc_factor, skin_name, scratch):
    scene = bpy.context.scene
    cam = setup_render(scene, body, garment)
    fwd = facing(arm)
    review = os.path.join(ROOT, "build", "review")
    os.makedirs(review, exist_ok=True)
    os.makedirs(scratch, exist_ok=True)
    body_dom = dominant_groups(body)
    closeups = {c.strip() for c in os.environ.get("FIT_GARMENT_CLOSEUP", "").split(",") if c.strip()}

    # Rest pose first: front and side, no action.
    if arm.animation_data:
        arm.animation_data.action = None
    depsgraph = bpy.context.evaluated_depsgraph_get()
    hips = arm.data.bones["mixamorig:Hips"].head_local
    # Front, side, and a 2x close-up of the torso — the close-up is the crack
    # check: a seam that has opened shows the grey body as a hairline.
    left = Vector((-fwd.y, fwd.x, 0.0))
    torso = Vector((hips.x, hips.y, BODY_HEIGHT * 0.56))
    panels = []
    for name, direction, target, ortho in (
        ("front", fwd, Vector((hips.x, hips.y, BODY_HEIGHT * 0.5)), 2.3),
        ("side", left, Vector((hips.x, hips.y, BODY_HEIGHT * 0.5)), 2.3),
        ("closeup", fwd, torso, 0.78),
    ):
        look_at(cam, target, direction, 6.0, ortho)
        p = os.path.join(scratch, "tpose_%s.png" % name)
        render_to(scene, p, TPOSE_PANEL)
        panels.append(read_png(p))
    tpose_path = os.path.join(review, "%s_tpose.png" % skin_name)
    write_strip(panels, tpose_path)
    note("render: %s" % os.path.relpath(tpose_path, ROOT).replace("\\", "/"))

    rows = []
    renders = [tpose_path]
    for label, filename in PROOF_CLIPS:
        clip_path = os.path.join(ROOT, "assets", "source", "anims", filename)
        if not os.path.exists(clip_path):
            fail("missing proof clip %s" % clip_path)
        action, n_loc = load_clip(clip_path, loc_factor)
        assign_action(arm, action)
        start, end = action.frame_range
        scene.frame_start, scene.frame_end = int(start), int(end)
        frames = [int(round(start + (end - start) * i / (PROOF_FRAMES - 1.0)))
                  for i in range(PROOF_FRAMES)]

        panels = []
        for frame in frames:
            scene.frame_set(frame)
            depsgraph = bpy.context.evaluated_depsgraph_get()
            body_bvh, body_polys = bvh_of(body, depsgraph, with_polys=True)
            g_eval = garment.evaluated_get(depsgraph)
            g_mesh = g_eval.to_mesh()
            g_mat = g_eval.matrix_world
            pts = [g_mat @ v.co for v in g_mesh.vertices]
            inside, depth, hits = penetration(pts, body_bvh)
            where = inside_regions(hits, body_polys, body_dom)
            g_eval.to_mesh_clear()
            rows.append((label, frame, inside, len(pts), depth * 1000.0, where))

            hips_pose = arm.matrix_world @ arm.pose.bones["mixamorig:Hips"].head
            look_at(cam, Vector((hips_pose.x, hips_pose.y, max(0.55, hips_pose.z))),
                    fwd, 6.0, 2.6)
            p = os.path.join(scratch, "%s_%s_%d.png" % (skin_name, label, frame))
            render_to(scene, p, PANEL)
            panels.append(read_png(p))

            # FIT_GARMENT_CLOSEUP="sword:36,sword:72" puts extra front/back
            # close-ups of those frames in the scratch directory, for telling a
            # hem that has ridden up from cloth the body has come through.
            if "%s:%d" % (label, frame) in closeups:
                for view, direction in (("front", fwd), ("back", -fwd)):
                    look_at(cam, Vector((hips_pose.x, hips_pose.y, hips_pose.z + 0.25)),
                            direction, 6.0, 1.0)
                    cp = os.path.join(scratch, "closeup_%s_%d_%s.png" % (label, frame, view))
                    render_to(scene, cp, (900, 900))
                    say("closeup: %s" % cp)

        out = os.path.join(review, "%s_%s.png" % (skin_name, label))
        write_strip(panels, out)
        renders.append(out)
        note("render: %s (frames %s)" % (os.path.relpath(out, ROOT).replace("\\", "/"), frames))

        arm.animation_data.action = None
        bpy.data.actions.remove(action)

    note("penetration: %-8s %-6s %-15s %-9s %s"
         % ("clip", "frame", "inside", "deepest", "inside what"))
    for label, frame, inside, total, depth, where in rows:
        note("    %-8s %-6d %4d / %-8d %5.1f mm  %s" % (label, frame, inside, total, depth, where))
    worst = max(rows, key=lambda r: r[4])
    note("penetration: worst %s frame %d, %d verts inside, %.1f mm deep (%s)"
         % (worst[0], worst[1], worst[2], worst[4], worst[5]))
    return rows, renders


# --------------------------------------------------------------------------
# 10. README
# --------------------------------------------------------------------------


def write_readme(out_dir, skin_name, source_name, offset, influences, subdivide, relax, smooth):
    lines = [
        "# The %s" % skin_name,
        "",
        "A **garment** skin (D-100, `docs/SKIN_PIPELINE.md` Route 3): a mesh bound",
        "to the BOG's own 49 `mixamorig_*` bones, so it inherits every clip in",
        "`art/generated/bog_clips.res` without a refit and without touching the body,",
        "the rig or the clip library.",
        "",
        "- `garment.glb` — the mesh, skinned to the Mixamo rig by bone name. Godot",
        "  turns the exporter's `mixamorig:` into `mixamorig_`, which is what the",
        "  game's `Skeleton3D` uses, so `wear` re-parents it and nothing else.",
        "",
        "## How it was made",
        "",
        "Route 3, end to end:",
        "",
        "1. Image AI drew the BOG wearing the outfit from the front, with the Route 3",
        "   prompt in `docs/SKIN_PIPELINE.md` and `bog_front.png` as the reference.",
        "2. Tripo *Image to 3D* turned that picture into a dressed body,",
        "   `assets/source/skins/%s/%s_dressed.glb`." % (source_name, source_name),
        "3. Tripo *part segmentation* cut the clothing off it,",
        "   `assets/source/skins/%s/%s_garment.glb`." % (source_name, source_name),
        "4. `tools/fit_garment.py` put the cut back on the body it came from",
        "   (translation-only ICP), took it into the game's metres, subdivided it once,",
        "   pushed every vertex outside the real body, borrowed the body's own vertex",
        "   weights and exported the result.",
        "",
        "## Rebuilt by",
        "",
        "```",
        '"$BLENDER" --background --python tools/fit_garment.py -- %s %s' % (source_name, skin_name),
        "```",
        "",
        "It ran with the defaults: `--offset %s` metres of clearance, `--influences %d`"
        % (offset, influences),
        "bones per vertex, `--subdivide %d` simple subdivision of Tripo's coarse cut,"
        % subdivide,
        "`--relax %d` smooth-then-re-push passes to take the dents out of it and"
        % relax,
        "`--smooth-weights %d` passes over the transferred weights." % smooth,
        "",
        "## What that run printed",
        "",
        "```",
    ]
    lines += [l for l in SUMMARY]
    lines += [
        "```",
        "",
        "The review renders are `build/review/%s_tpose.png` and one strip of four" % skin_name,
        "frames per proof clip — idle, walk, crouch, dive roll, sword combo — body in",
        "grey, garment in red, rendered in Blender rather than Godot so the fit can be",
        "judged before the game ever loads it.",
        "",
        "## What the penetration table is not saying",
        "",
        "The count is *garment vertices inside the body mesh*, and the body mesh includes",
        "the arms and that enormous head. So a pose where the arms cross the chest, or",
        "where the head pitches down onto the collar, scores in the hundreds without",
        "anything being visibly wrong — the cloth is behind an arm or tucked under a chin,",
        "which is where cloth goes. Read the `inside what` column before the number:",
        "`Head`, `LeftForeArm` and the `*Hand*` bones are those cases. What is left on",
        "the torso is the hem: the BOG's abdomen is a sphere and this shirt is short, so",
        "past about sixty degrees of forward spine bend the hem lifts off the belly and",
        "bare body shows *below* the cloth — visible in the sword combo and the middle of",
        "the dive roll. That is the garment being short, not the fit being wrong.",
        "",
        "Three things in the tool exist only to keep the cloth off the body, and each was",
        "put there because a render showed the body coming through:",
        "",
        "- **The weld.** Tripo ships the cut with its UV seams unwelded — 348 boundary",
        "  edges on a shell whose only openings are a neck, two cuffs and a hem. The",
        "  subdivide, the shrinkwrap and the relax move coincident vertices differently",
        "  and every seam opens into a crack with grey body behind it.",
        "- **The inflate.** A shrinkwrap cannot clear a *crease* — in the armpit the",
        "  nearest body point is the crease line itself, so pushing out along one face's",
        "  normal presses the vertex into the other face. The inflate pass moves a vertex",
        "  along the *cloth's* own normal instead, which points out of the crease.",
        "- **The weight smoothing.** Nearest-surface weights put arm bones on one side of",
        "  the armpit and spine bones a centimetre away on the other; the cloth shears",
        "  along that line when the arm swings.",
        "",
    ]
    path = os.path.join(out_dir, "README.md")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    say("wrote %s" % os.path.relpath(path, ROOT).replace("\\", "/"))


# --------------------------------------------------------------------------


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    positional = [a for a in argv if not a.startswith("--")]
    if len(positional) < 2:
        print(__doc__)
        print("fit_garment: need <SOURCE_NAME> <skin_name>")
        return 2
    source_name, skin_name = positional[0], positional[1]
    offset = 0.008
    influences = 4
    subdivide = 1
    relax = 2
    smooth = 2
    for i, a in enumerate(argv):
        if a == "--offset":
            offset = float(argv[i + 1])
        elif a.startswith("--offset="):
            offset = float(a.split("=", 1)[1])
        elif a == "--influences":
            influences = int(argv[i + 1])
        elif a.startswith("--influences="):
            influences = int(a.split("=", 1)[1])
        elif a == "--subdivide":
            subdivide = int(argv[i + 1])
        elif a.startswith("--subdivide="):
            subdivide = int(a.split("=", 1)[1])
        elif a == "--relax":
            relax = int(argv[i + 1])
        elif a.startswith("--relax="):
            relax = int(a.split("=", 1)[1])
        elif a == "--smooth-weights":
            smooth = int(argv[i + 1])
        elif a.startswith("--smooth-weights="):
            smooth = int(a.split("=", 1)[1])

    source_dir = os.path.join(ROOT, "assets", "source", "skins", source_name)
    out_dir = os.path.join(ROOT, "art", "skins", skin_name)
    # Only the finished strips belong in build/review; the per-frame panels the
    # compositor eats are scratch.
    scratch = os.environ.get("FIT_GARMENT_SCRATCH") or os.path.join(
        tempfile.gettempdir(), "fit_garment_" + skin_name)
    for name in (source_name + "_dressed.glb", source_name + "_garment.glb"):
        if not os.path.exists(os.path.join(source_dir, name)):
            fail("missing input %s" % os.path.join(source_dir, name))

    note("source %s -> art/skins/%s, offset %.4f m, %d influences, subdivide %d, relax %d,"
         " smooth-weights %d"
         % (source_name, skin_name, offset, influences, subdivide, relax, smooth))
    arm, body, loc_factor = load_body()
    dressed, garment = load_tripo(source_dir, source_name)
    d_height = replace_on_dressed(dressed, garment)
    into_body_space(dressed, garment, body, d_height)
    densify(garment, subdivide)
    push_out(garment, body, offset, relax)
    transfer_weights(garment, body, arm, influences, smooth)
    make_material(garment, skin_name)
    export(arm, garment, out_dir)
    proof(arm, body, garment, loc_factor, skin_name, scratch)
    write_readme(out_dir, skin_name, source_name, offset, influences, subdivide, relax, smooth)

    print("")
    print("=" * 72)
    print("fit_garment summary — %s -> art/skins/%s" % (source_name, skin_name))
    print("=" * 72)
    for line in SUMMARY:
        print("  " + line)
    print("=" * 72)
    return 0


if __name__ == "__main__":
    try:
        code = main()
    except Exception:
        traceback.print_exc()
        print("fit_garment: FAILED", flush=True)
        code = 1
    sys.stdout.flush()
    sys.stderr.flush()
    sys.exit(code)
