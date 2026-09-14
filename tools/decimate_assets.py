"""Turn the raw source props into game-ready meshes.

The three the project was handed first (Spear, Lure, Mushroom) are
photogrammetry-style meshes of roughly half a million triangles each. One spear
per Gub, every projectile in flight, and a scattering of deployed mushrooms
would be millions of triangles per frame before shadow passes. This script
reduces each one to a sane budget while keeping it visually identical at
gameplay distance.

Not everything that comes through here arrives that heavy. The three letter
cards are 9k-triangle Tripo exports, and they are in the target list for the
4096-square texture, the image rename and the single-buffer repack rather than
for the decimation: the same treatment, applied to a mesh whose triangle count
was never the problem.

Static, unskinned meshes only. The Gub came through here too until D-029: a
skinned photogrammetry mesh whose hand-made rig had to be repaired on the way
past, which is what the skin binding, the animation-curve cleanup, the clip
facing alignment and the root-motion stripping in this script existed for. It is
now built from Mixamo FBX by `tools/build_gub.py`, which does all of that at the
source instead, so all of it is gone from here and every remaining *source* is
one unskinned mesh with one material and no animation.

Pipeline, per mesh:

  1. Weld vertices by position. The sources duplicate ~17% of their vertices
     along UV seams; left alone those seams read as hard boundaries the
     decimator refuses to collapse, which wrecks quality at high reduction.
  2. Quadric-error decimation on the welded topology (`fast_simplification`).
  3. Transfer UVs back from the source by nearest-vertex lookup, disambiguated
     per-triangle so a triangle never straddles two UV islands (which would
     smear the texture across the seam).
  4. Recompute smooth normals from the new geometry, accumulated by position so
     shading stays continuous across the seams from step 1.
  5. Repack into a fresh single-buffer GLB in `art/generated/`.

The bow gets a sixth step, which is a separate module for a reason spelled out
at length in `tools/bow_string.py`: `fast_simplification` renumbers vertices and
knows nothing about morph targets, so anything carrying a shape key has to be
built *after* the decimation and never go through it. The string is therefore a
second mesh in the bow's file rather than part of the mesh that was decimated,
and `verify_blend_shapes` reads the written `.glb` back off disk afterwards and
prints the deltas it finds, because a dead shape key is invisible everywhere
else.

Sources in `assets/` are never touched; re-running this is always safe.

Usage:  python tools/decimate_assets.py [name ...]
"""

import io
import os
import sys
import time

import numpy as np
from PIL import Image
from scipy import sparse
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bow_string  # noqa: E402
import fast_simplification  # noqa: E402
from gltf_io import ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER, Gltf, GltfBuilder  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "art", "generated")

# name -> (source path, triangle budget, max texture edge)
#
# Budgets are set by how many of each thing can be on screen at once. The spear
# is tiny on screen but there is one per Gub plus every projectile in flight, so
# it gets the tightest budget; the mushroom is a placed object you walk right up
# to and gets the loosest. The props arrive at 2048x2048 and the letters at
# 4096x4096, which is far more than a thrown stick needs.
#
# The letters arrive at a tenth of the props' triangle count, so 6000 is barely
# a reduction — and it is deliberately the lure's number rather than the spear's
# tighter one, because a letter is read for its *shape*. A G that has lost the
# inside of its curve is a C, and no texture puts that back. 512 for all three
# on the spear's and the lure's argument: a 0.6 m prop, looked at from metres
# away, on a mesh with one material and nothing but base colour on it.
# The bow brought three more, and the same argument sets all three.
#
# The arrow is now the tightest case in the table, tighter than the spear. There
# is one nocked on every drawn bow, one in flight for every shot taken, and —
# since a shaft can stick in a victim who lives through it — every arrow
# standing in every Gub still walking around. Eight Gubs with three apiece is
# the ordinary case rather than the bad one, and none of those are in flight
# yet. 1200, which the shaft can afford because most of it is a cylinder; what
# the budget is actually protecting is the fletching and the knapped head, which
# are the two things that still say "arrow" at forty metres.
#
# Its texture stays at the spear's 512 all the same, because a texture is paid
# for once per asset and not once per instance — the count argument that sets
# the triangle budget has nothing to say about it. What does: an arrow standing
# in the shoulder of a Gub next to you is looked at as closely as anything in
# this game, and a Gub walking around with three of them in it is the whole
# read that partial damage exists to give.
#
# The bow is the other end of it. At most one per Gub, never one in flight, and
# it is the prop that spends the longest large and still in frame — held across
# the body for the whole of every draw, on a mesh the camera is behind. 4000,
# and the mushroom's 1024 rather than the spear's 512 on the mushroom's own
# argument: a bow being aimed is nearer the camera than a mushroom you are
# standing over, and the carving down the limbs is most of what it has.
#
# The great sword is the bow's case by the counting rule and nothing like it by
# the geometry. One per Gub at most, never one in flight — a sword is swung, not
# thrown — so the bow's argument transfers whole and 4000/1024 is the precedent.
# What the model says against that: it arrives at 9912 triangles to the bow's
# 10188, over the same 1 m span, but with **3.5 times the surface** (0.475
# against 0.135 in model units squared). A bow is a stick; a great sword is a
# slab, and the same triangle budget has three and a half times as much of it to
# cover. So equal budgets do not buy equal quality here: at 4000 the sword's mean
# deviation from its source measures 0.67 mm against the bow's 0.44.
#
# The cut comes out of the blade and only the blade. Seventy per cent of this
# model's length is a taper between two near-flat faces, and quadric-error
# decimation gets that for almost nothing: at 3000 the decimator hands the whole
# 0.7 m of blade 901 triangles and it still holds 0.88 mm. The other 30% — the
# crossguard at 0.21 m across, the grip, the pommel — takes the remaining 2099,
# because that is doubly curved and it is what says "great sword" rather than
# "plank". The budget is buying the hilt; the blade is nearly free. That is what
# "mostly long flat planes" is worth, measured rather than assumed.
#
# 3000, which is also the spear's number for the spear's reason: a long thing
# whose silhouette is a straight edge with its detail gathered at one end. It
# puts the whole model at 0.77 mm mean and 2.8 mm at the 99th percentile —
# coarser than the bow's 0.37/1.24, finer than the arrow's shipping 1.00/4.45,
# and the arrow is the prop in this table that gets looked at closest of all.
#
# 1024 for the texture, the bow's and the mushroom's, not the spear's 512. A
# texture is paid for once per asset and never once per instance, so the counting
# rule has nothing to say about it; what does is that this prop spends the whole
# of a slow swing large and in frame, and that having just taken the triangles
# out of the blade, the fuller, the edge and the grip wrap are all now texture on
# a flat plane rather than geometry. The texture is what is holding the blade up.
#
# The potion is the lure's case exactly — a small thing on the ground, a handful
# at a time, collected by running over it — so it takes the lure's numbers and
# not the spear's. For the letters' reason as well as the lure's: a bottle is a
# surface of revolution, and a circle goes visibly faceted long before a stick
# does.
TARGETS = {
    "spear":       ("assets/source/Spear.glb", 3000, 512),
    "lure":        ("assets/source/Lure.glb", 6000, 512),
    "mushroom":    ("assets/source/Mushroom/base_basic_pbr.glb", 10000, 1024),
    "letter_g":    ("assets/source/G_LETTER.glb", 6000, 512),
    "letter_u":    ("assets/source/U_LETTER.glb", 6000, 512),
    "letter_b":    ("assets/source/B_LETTER.glb", 6000, 512),
    "arrow":       ("assets/source/ARROW.glb", 1200, 512),
    "bow":         ("assets/source/BOW.glb", 4000, 1024),
    "heal_potion": ("assets/source/HEAL_POTION.glb", 6000, 512),
    "greatsword":  ("assets/source/GreatSword.glb", 3000, 1024),
}

# Targets that get something added after the decimator has finished with them.
#
# Only the bow, and only because its string carries a shape key. The whole
# reason this is a hook rather than four more lines inside `process` is that the
# order is load-bearing: a morph target authored before `fast_simplification`
# comes out the far side pointing at vertices that no longer exist. Running the
# addition from here, on the mesh the decimator has already written into the
# builder, makes that ordering the only one expressible.
AFTER_DECIMATION = {
    "bow": bow_string.add_string,
}


def log(msg):
    print(msg, flush=True)


def weld(positions):
    """Merge vertices that share a position.

    Returns (welded_positions, original_index -> welded_index).
    """
    # Quantise very slightly so float noise does not defeat the merge.
    keys = np.round(positions.astype(np.float64), 6)
    _uniq, first, inverse = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    return positions[first].astype(np.float32), inverse.astype(np.int64)


def smooth_normals(positions, faces):
    """Area-weighted vertex normals, accumulated across coincident positions.

    Accumulating by position rather than by index means the two sides of a UV
    seam receive the same normal, so the seam does not show up as a shading
    crease.
    """
    v0, v1, v2 = positions[faces[:, 0]], positions[faces[:, 1]], positions[faces[:, 2]]
    # Un-normalised cross product is already area-weighted.
    face_n = np.cross(v1 - v0, v2 - v0)

    _uniq, inverse = np.unique(np.round(positions.astype(np.float64), 6),
                               axis=0, return_inverse=True)
    inverse = inverse.astype(np.int64)
    slot = inverse[faces]  # (ntri, 3) position-slot per corner

    acc = np.zeros((inverse.max() + 1, 3), dtype=np.float64)
    for k in range(3):
        np.add.at(acc, slot[:, k], face_n)

    normals = acc[inverse]
    length = np.linalg.norm(normals, axis=1, keepdims=True)

    # A vertex touched only by zero-area triangles accumulates nothing. Leaving
    # it at (0,0,0) renders as a black speck, so fall back to pointing it away
    # from the model centre, which is right often enough to be invisible.
    degenerate = (length[:, 0] == 0.0)
    if degenerate.any():
        away = positions[degenerate] - positions.mean(axis=0)
        away_len = np.linalg.norm(away, axis=1, keepdims=True)
        away_len[away_len == 0.0] = 1.0
        normals[degenerate] = away / away_len
        length[degenerate] = 1.0

    return (normals / length).astype(np.float32)


def uv_charts(nverts, faces):
    """Label each source vertex with the UV chart it belongs to.

    An exporter splits the vertex buffer along every UV seam, so the connected
    components of the *unwelded* face graph are exactly the UV charts. That
    gives a cheap, exact island labelling with no UV-space geometry needed.
    """
    edges = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
    graph = sparse.coo_matrix(
        (np.ones(len(edges), dtype=np.int8), (edges[:, 0], edges[:, 1])),
        shape=(nverts, nverts))
    count, labels = connected_components(graph, directed=False)
    return count, labels


def transfer_attributes(src_pos, src_faces, new_pos, new_faces):
    """Pick, for each new corner, the source vertex its attributes come from.

    A plain nearest-neighbour lookup picks arbitrarily between the two sides of
    a UV seam. Worse, it picks *independently per corner*, so a vertex shared by
    six triangles ends up with six slightly different UVs and the texture shreds.

    Instead each new triangle is assigned one UV chart (from the source triangle
    nearest its centroid), and each corner then takes the nearest source vertex
    *within that chart*. The choice is a pure function of (new vertex, chart), so
    every triangle in a chart agrees on the UV of a shared vertex — the buffer
    dedups back down, and vertices split only where a real seam runs.

    Returns a per-corner (ntri, 3) array of source vertex indices.
    """
    _nchart, chart = uv_charts(len(src_pos), src_faces)

    src_centroids = src_pos[src_faces].mean(axis=1)
    _d, near_tri = cKDTree(src_centroids).query(new_pos[new_faces].mean(axis=1), k=1)
    tri_chart = chart[src_faces[near_tri, 0]]        # (ntri,)

    corner_vert = new_faces.reshape(-1)
    want_chart = np.repeat(tri_chart, 3)

    tree = cKDTree(src_pos)
    k = 48
    _dist, cand = tree.query(new_pos[corner_vert], k=k)   # sorted near -> far
    in_chart = chart[cand] == want_chart[:, None]

    # argmax on a boolean row returns the first True, i.e. the nearest candidate
    # that is in the wanted chart.
    best = np.argmax(in_chart, axis=1)
    chosen = cand[np.arange(len(corner_vert)), best]
    missed = ~in_chart.any(axis=1)
    if missed.any():
        # No vertex of that chart within the 48 nearest: the chart is a tiny
        # scrap far from this corner. Fall back to plain nearest.
        chosen[missed] = cand[missed, 0]
    return chosen.reshape(-1, 3), int(missed.sum())


def dedup_corners(corner_arrays):
    """Collapse identical corners into a shared vertex buffer.

    `corner_arrays` is a list of (ncorner, ...) arrays that must agree for two
    corners to merge. Returns (indices_into_unique, unique_selector).
    """
    flat = [a.reshape(a.shape[0], -1).astype(np.float64) for a in corner_arrays]
    key = np.round(np.concatenate(flat, axis=1), 6)
    _uniq, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return inverse.astype(np.uint32), first


def clean_image_name(name, source_stem):
    """What the embedded image should be called, so the extracted file is sane.

    Godot extracts an embedded texture to `<glb stem>_<image name>`, and the
    image name is treated as a filename whether it looks like one or not. The
    letters arrive named `G_LETTER_basecolor.jpg`, which comes back out of the
    importer as `art/generated/letter_g_G_LETTER_basecolor.jpg.png` — the
    source's name, this script's name for it, and a stale extension, all in one
    filename. Dropping the extension and then the source stem leaves
    `basecolor`, so the file on disk is `letter_g_basecolor.png`.

    A no-op for the three props: their images are already called `shaded`,
    `texture_diffuse` and the like, with no extension and no source stem in
    front of them, so nothing here changes what they extract to.
    """
    cleaned = os.path.splitext(name)[0]
    prefix = source_stem + "_"
    if cleaned.startswith(prefix):
        cleaned = cleaned[len(prefix):]
    return cleaned or name


def resize_texture(data, max_edge):
    """Downscale an embedded texture to `max_edge`, returning PNG bytes."""
    img = Image.open(io.BytesIO(data))
    if max(img.size) <= max_edge:
        return data, img.size, img.size
    before = img.size
    scale = float(max_edge) / max(img.size)
    img = img.resize((max(1, int(round(img.size[0] * scale))),
                      max(1, int(round(img.size[1] * scale)))), Image.LANCZOS)
    out = io.BytesIO()
    img.save(out, format="PNG", optimize=True)
    return out.getvalue(), before, img.size


def verify_blend_shapes(name, path, expect):
    """Read the written file back and prove the shape key in it is alive.

    `fast_simplification` destroys morph targets silently — it renumbers the
    vertices and there is nowhere in glTF for the file to say that its deltas
    now point at nothing. A build that merely *intended* to write a shape key
    therefore looks exactly like one that wrote a working one, in the log, in
    the file size, and in Godot's import dialog. So this opens the `.glb` that
    was just written, off disk, as a stranger would, and prints what is actually
    in it: the target names, how many deltas are non-zero, and every distinct
    delta with the number of vertices that share it. Then it rebuilds
    `base + delta` and compares that against the shape the caller meant to
    write. Same argument as `check_ground` in `tools/build_gub.py` — a judgement
    that is only documented is a judgement nobody is checking.
    """
    g = Gltf.load(path)
    found = []
    for mi, mesh in enumerate(g.doc.get("meshes", [])):
        for prim in mesh["primitives"]:
            if prim.get("targets"):
                found.append((mi, mesh, prim))

    if expect is None:
        if found:
            log("  shape keys: %d, none expected for %s" % (len(found), name))
        return

    want = [(mi, mesh, prim) for mi, mesh, prim in found if mi == expect["mesh"]]
    if not want:
        raise SystemExit("%s: mesh %d was written without a morph target; the "
                         "shape key did not survive the build"
                         % (name, expect["mesh"]))
    mi, mesh, prim = want[0]
    names = mesh.get("extras", {}).get("targetNames", [])
    base = g.read_accessor(prim["attributes"]["POSITION"]).astype(np.float64)
    delta = g.read_accessor(prim["targets"][0]["POSITION"]).astype(np.float64)

    log("  shape key, read back out of the written file:")
    log("    mesh %d %r, %d target(s) named %s, weights %s"
        % (mi, mesh.get("name"), len(prim["targets"]), names, mesh.get("weights")))
    if names[:1] != [expect["shape"]]:
        raise SystemExit("%s: shape key is named %s, expected %r"
                         % (name, names, expect["shape"]))

    moved = np.linalg.norm(delta, axis=1) > 1e-9
    log("    %d verts, %d with a non-zero POSITION delta" % (len(base), int(moved.sum())))
    if not moved.any():
        raise SystemExit("%s: every delta in the shape key is zero" % name)

    keys, counts = np.unique(np.round(delta, 6), axis=0, return_counts=True)
    order = np.argsort(np.linalg.norm(keys, axis=1))
    for k in order:
        log("      %2d verts move %6.1f mm  %s"
            % (counts[k], 1000.0 * float(np.linalg.norm(keys[k])),
               np.round(keys[k], 4).tolist()))

    err = float(np.abs((base + delta) - expect["drawn"].astype(np.float64)).max())
    log("    base + delta reproduces the intended drawn string to %.2e m" % err)
    if err > 1e-5:
        raise SystemExit("%s: the shape key in the file is not the shape key "
                         "that was authored (off by %.3e m)" % (name, err))
    rest_err = float(np.abs(base - expect["rest"].astype(np.float64)).max())
    if rest_err > 1e-5:
        raise SystemExit("%s: the rest pose in the file moved (%.3e m)" % (name, rest_err))
    log("    at rest the string is straight between the nocks; at weight 1.0 the "
        "nocking point is %.3f m back" % expect["draw"])


def process(name, src_path, target_tris, max_texture):
    started = time.time()
    src_full = os.path.join(REPO, src_path)
    log("\n=== %s  <-  %s" % (name, src_path))

    g = Gltf.load(src_full)
    meshes = g.doc["meshes"]
    if len(meshes) != 1 or len(meshes[0]["primitives"]) != 1:
        raise SystemExit("%s: expected exactly one mesh with one primitive" % name)
    prim = meshes[0]["primitives"][0]
    attrs = prim["attributes"]

    pos = np.ascontiguousarray(g.read_accessor(attrs["POSITION"]), dtype=np.float32)
    uv = np.ascontiguousarray(g.read_accessor(attrs["TEXCOORD_0"]), dtype=np.float32)
    faces = np.ascontiguousarray(g.read_accessor(prim["indices"]).reshape(-1, 3), dtype=np.int64)

    # Everything this script knows how to do assumes a static prop. Skin
    # weights and animation curves survive neither the weld nor the decimation
    # without the machinery that went to `tools/build_gub.py` with the Gub, so
    # say so rather than quietly writing an asset with its rig thrown away.
    if "JOINTS_0" in attrs or g.doc.get("skins") or g.doc.get("animations"):
        raise SystemExit("%s: skinned or animated source; this script only "
                         "handles static props (the Gub is built by "
                         "tools/build_gub.py)" % name)

    lo, hi = pos.min(axis=0), pos.max(axis=0)
    # Rounded as float64: rounding a float32 to two places and printing it
    # still spells 0.13 as 0.12999999523162842, which buries the number the
    # line exists to show.
    log("  source: %d verts, %d tris, bbox %s .. %s"
        % (len(pos), len(faces),
           np.round(lo.astype(np.float64), 2).tolist(),
           np.round(hi.astype(np.float64), 2).tolist()))

    # 1. weld -------------------------------------------------------------
    wpos, v2w = weld(pos)
    wfaces = v2w[faces]
    keep = ((wfaces[:, 0] != wfaces[:, 1]) &
            (wfaces[:, 1] != wfaces[:, 2]) &
            (wfaces[:, 0] != wfaces[:, 2]))
    wfaces = wfaces[keep]
    log("  welded: %d verts (%d seam duplicates removed), %d tris"
        % (len(wpos), len(pos) - len(wpos), len(wfaces)))

    # 2. decimate ---------------------------------------------------------
    new_pos, new_faces = fast_simplification.simplify(
        wpos.astype(np.float32),
        wfaces.astype(np.int32),
        target_count=int(target_tris),
    )
    new_pos = np.ascontiguousarray(new_pos, dtype=np.float32)
    new_faces = np.ascontiguousarray(new_faces, dtype=np.int64)
    log("  decimated: %d verts, %d tris (%.1f%% of source)"
        % (len(new_pos), len(new_faces), 100.0 * len(new_faces) / len(faces)))

    # 3. attribute transfer ----------------------------------------------
    corner_src, missed = transfer_attributes(pos, faces, new_pos, new_faces)
    if missed:
        log("  note: %d of %d corners fell back to plain nearest-vertex"
            % (missed, new_faces.size))
    corner_pos = new_pos[new_faces].reshape(-1, 3)
    corner_uv = uv[corner_src].reshape(-1, 2)

    # Only the UVs ride along; normals are recomputed from the new geometry
    # below rather than transferred, so a corner is (position, UV) and nothing
    # else has to agree for two of them to merge.
    indices, pick = dedup_corners([corner_pos, corner_uv])
    out_pos = corner_pos[pick]
    out_uv = corner_uv[pick]
    out_faces = indices.reshape(-1, 3).astype(np.int64)

    # Dedup can fuse two corners of a triangle together; drop the slivers.
    solid = ((out_faces[:, 0] != out_faces[:, 1]) &
             (out_faces[:, 1] != out_faces[:, 2]) &
             (out_faces[:, 0] != out_faces[:, 2]))
    if not solid.all():
        log("  dropped %d degenerate triangles" % int((~solid).sum()))
        out_faces = out_faces[solid]
    log("  rebuilt: %d verts, %d tris after seam-aware dedup"
        % (len(out_pos), len(out_faces)))

    # 4. normals ----------------------------------------------------------
    out_normal = smooth_normals(out_pos, out_faces)

    # 5. repack -----------------------------------------------------------
    b = GltfBuilder(g.doc)

    new_attrs = {
        "POSITION": b.add_accessor(out_pos, target=ARRAY_BUFFER, bounds=True),
        "NORMAL": b.add_accessor(out_normal, target=ARRAY_BUFFER),
        "TEXCOORD_0": b.add_accessor(out_uv, target=ARRAY_BUFFER),
    }

    idx_dtype = np.uint16 if len(out_pos) < 65536 else np.uint32
    new_prim = dict(prim)
    new_prim["attributes"] = new_attrs
    new_prim["indices"] = b.add_accessor(out_faces.astype(idx_dtype).reshape(-1),
                                         target=ELEMENT_ARRAY_BUFFER)
    b.doc["meshes"][0]["primitives"] = [new_prim]

    # 6. anything that could not survive the decimation ---------------------
    extra = AFTER_DECIMATION.get(name)
    expect = extra(b, g, out_pos, out_faces, log) if extra else None

    # The only thing else in the file that is not the mesh is the embedded texture,
    # which is copied across (downscaled, and renamed) into the new buffer.
    source_stem = os.path.splitext(os.path.basename(src_path))[0]
    for image in b.doc.get("images", []):
        if "bufferView" not in image:
            continue
        raw = g.view_bytes(image["bufferView"])
        data, before, after = resize_texture(raw, max_texture)
        if before != after:
            log("  texture %s: %dx%d -> %dx%d (%d KB -> %d KB)"
                % (image.get("name", "?"), before[0], before[1], after[0], after[1],
                   len(raw) // 1024, len(data) // 1024))
            image["mimeType"] = "image/png"
        cleaned = clean_image_name(image.get("name", ""), source_stem)
        if cleaned and cleaned != image.get("name"):
            log("  image %s -> %s (Godot will extract %s_%s.png)"
                % (image["name"], cleaned, name, cleaned))
            image["name"] = cleaned
        image["bufferView"] = b.add_view(data)

    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)
    out_path = os.path.join(OUT_DIR, "%s.glb" % name)
    size = b.save(out_path)
    src_size = os.path.getsize(src_full)
    log("  wrote art/generated/%s.glb  %.1f MB (from %.1f MB)  in %.1fs"
        % (name, size / 1e6, src_size / 1e6, time.time() - started))
    verify_blend_shapes(name, out_path, expect)


def main(argv):
    wanted = argv[1:] or sorted(TARGETS)
    unknown = [w for w in wanted if w not in TARGETS]
    if unknown:
        raise SystemExit("unknown target(s): %s (have: %s)"
                         % (", ".join(unknown), ", ".join(sorted(TARGETS))))
    for name in wanted:
        src, tris, tex = TARGETS[name]
        process(name, src, tris, tex)
    log("\ndone.")


if __name__ == "__main__":
    main(sys.argv)
