#!/usr/bin/env python3
"""Bake a regenerated Tripo skin's paint onto the body's own UV layout.

`tools/extract_skins.py` pulls a recolour straight out of its download, which
works because every one of the first thirteen downloads was the BOG sculpt
itself -- 15 872 vertices in the body's UV layout -- wearing new paint. A later
Tripo run can hand back the same creature *regenerated* (9 124 vertices, its
own UV islands, every part a little bigger or smaller and a little moved): the
paint is right, the layout is not, and worn as a texture it lands on the body
as a patchwork. This is the step for that case, and `extract_skins.py` takes it
on its own whenever a download's vertex count is not the body's.

    python tools/bake_skin.py BLOOM KOI          # bake these
    python tools/bake_skin.py --dry-run BLOOM    # report the fit, write nothing
    python tools/bake_skin.py --parts KOI        # ...and the fit bone by bone

For each skin it
  1. reads the download's mesh and its base colour texture;
  2. aligns the download to the body as a whole: the four quarter turns about
     the vertical are tried against the body's bounding box, the one that lands
     closest wins, and similarity then affine ICP tighten it -- Tripo turns,
     rescales and stretches its exports;
  3. aligns the body to the download **part by part**: every bone of the body's
     own rig takes the vertices it dominates and finds the rigid move that puts
     them on the download's surface, children starting from their parent's
     answer, and each vertex blends its bones' moves by its skin weights --
     which is what makes a head that Tripo drew four centimetres further back
     land on the download's head as a head, eyes over eyes, rather than slide
     obliquely onto it;
  4. pulls what is left smoothly: each vertex to its nearest point on the
     download, averaged over the mesh so it is a deformation and not a scatter;
  5. rasterises the body's UV layout at 2048 square, so every texel knows its
     point and its normal on the warped body;
  6. samples the download's surface densely, each sample carrying the colour
     its own texture gives it and the normal of its triangle, and paints each
     texel from the nearest samples that *face the same way* -- an eyelid's
     texel takes lid paint and not the eyeball's beneath it;
  7. fills the UV gutters from the nearest painted texel and writes
     `art/skins/<name>/basecolor.png` -- the same file, the same size and the
     same wear path (`Bog.wear_skin`) as an extracted skin.

The body it bakes onto is `build/body_ref.glb`, the body as Godot imports
`art/bog/BOG.fbx` -- positions, UVs, and the rig's joints and weights -- written
by

    "$GODOT" --headless --path . --script tools/export_body_ref.gd

and remade whenever that FBX changes. The fit is reported in millimetres on the
finished body (1.80 m tall); a residual over a centimetre after all of that
means the download is a different creature, and the bake is refused rather
than smeared.

Validated by baking one of the original downloads (BOGINA, the body's own
layout) and comparing with its extraction: the two agree to a few levels of 255
everywhere but the UV seams, where a bake blends across the seam and an
extraction cannot.
"""

from __future__ import annotations

import argparse
import io
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt
from scipy.sparse import coo_matrix
from scipy.spatial import cKDTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gltf_io import Gltf  # noqa: E402
import extract_skins as ex  # noqa: E402

REFERENCE = ex.REPO / "build" / "body_ref.glb"
SIZE = ex.TARGET
#: Surface samples over the whole download, about three per painted texel.
SAMPLES = 6_000_000
#: Points over the body's surface the download is fitted against.
BODY_SURFACE = 1_000_000
#: Neighbours considered per texel; the ones facing the texel's way are blended.
NEIGHBOURS = 12
ICP_ROUNDS = 15
#: A bone with fewer dominated vertices than this inherits its parent's move.
PART_MIN_VERTS = 60
PART_ROUNDS = 12
#: How much bigger or smaller than the body a part of the download may be.
PART_SCALE = (0.80, 1.25)
#: The share of a part's vertices its fit is solved on, each round: the best
#: matched. The head bone also owns the antennae, and an antenna that Tripo
#: drew at a different angle would otherwise drag the face off the face.
PART_TRIM = 0.8
#: Rounds of the smooth pull after the parts are placed, and how many
#: neighbour-averaging passes smooth the displacement field in each: what is
#: left after the rigid parts is small, so the schedule is short.
WARP_SMOOTHING = (8, 6, 4, 3, 2)
#: A fit worse than this after all of it is a different creature, not a
#: different paint job.
REFUSE_RESIDUAL_M = 0.010


# ------------------------------------------------------------------ input --

def load_mesh(path: Path):
    g = Gltf.load(str(path))
    prims = [p for m in g.doc["meshes"] for p in m["primitives"]]
    if len(prims) != 1:
        raise ValueError("%s has %d primitives, expected one" % (path.name, len(prims)))
    prim = prims[0]
    attrs = prim["attributes"]
    pos = g.read_accessor(attrs["POSITION"]).astype(np.float64)
    uv = g.read_accessor(attrs["TEXCOORD_0"]).astype(np.float64)
    idx = g.read_accessor(prim["indices"]).astype(np.int64).reshape(-1, 3)
    return g, pos, uv, idx


def load_rig(g: Gltf):
    """(joints (n, k), weights (n, k), parent per joint, name per joint)."""
    attrs = g.doc["meshes"][0]["primitives"][0]["attributes"]
    joints, weights = [], []
    for i in range(4):
        if "JOINTS_%d" % i not in attrs:
            break
        joints.append(g.read_accessor(attrs["JOINTS_%d" % i]).astype(np.int64))
        weights.append(g.read_accessor(attrs["WEIGHTS_%d" % i]).astype(np.float64))
    if not joints:
        raise ValueError("the body reference carries no skin weights")
    j = np.hstack(joints)
    w = np.hstack(weights)
    w = w / np.maximum(w.sum(1, keepdims=True), 1e-9)
    skin = g.doc["skins"][0]["joints"]
    node_of = {node: k for k, node in enumerate(skin)}
    parent = [-1] * len(skin)
    for n, node in enumerate(g.doc["nodes"]):
        for child in node.get("children", []):
            if child in node_of and n in node_of:
                parent[node_of[child]] = node_of[n]
    names = [g.doc["nodes"][node].get("name", str(node)) for node in skin]
    return j, w, parent, names


def texture_of(g: Gltf) -> np.ndarray:
    index, _ = ex.base_colour_image(g.doc)
    raw, _ = ex.image_bytes(g.doc, g.blob, index)
    return np.asarray(Image.open(io.BytesIO(raw)).convert("RGB"), dtype=np.uint8)


# ---------------------------------------------------------- whole-body fit --

def rot_y(angle: float) -> np.ndarray:
    c, s = np.cos(angle), np.sin(angle)
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])


def kabsch(p: np.ndarray, q: np.ndarray, scale: bool):
    """(s, R, t) with q ~ s R p + t; rigid when `scale` is False."""
    mp, mq = p.mean(0), q.mean(0)
    pc, qc = p - mp, q - mq
    cov = qc.T @ pc / len(p)
    u, d, vt = np.linalg.svd(cov)
    sgn = np.eye(3)
    if np.linalg.det(u) * np.linalg.det(vt) < 0:
        sgn[2, 2] = -1.0
    r = u @ sgn @ vt
    s = np.trace(np.diag(d) @ sgn) / (pc ** 2).sum(1).mean() if scale else 1.0
    t = mq - s * (r @ mp)
    return s, r, t


def align(src: np.ndarray, body: np.ndarray):
    """Return (transform(points), report) placing the download on the body.

    `body` is a dense sampling of the body's *surface*, not its vertices: a
    remeshed download's vertices fall between the body's, so a nearest-vertex
    residual would carry half a vertex spacing of noise that is not misfit.
    """
    tree = cKDTree(body)
    lo, hi = body.min(0), body.max(0)
    tried = []
    for quarter in range(4):
        r = rot_y(quarter * np.pi / 2.0)
        p = src @ r.T
        s = (hi[1] - lo[1]) / (p[:, 1].max() - p[:, 1].min())
        p = p * s
        t = np.array([
            (lo[0] + hi[0]) / 2.0 - (p[:, 0].min() + p[:, 0].max()) / 2.0,
            lo[1] - p[:, 1].min(),
            (lo[2] + hi[2]) / 2.0 - (p[:, 2].min() + p[:, 2].max()) / 2.0,
        ])
        p = p + t
        d, _ = tree.query(p, workers=-1)
        tried.append((d.mean(), quarter, s, r, t))
    tried.sort(key=lambda row: row[0])
    coarse, quarter, s, r, t = tried[0]
    runner_up = tried[1][0]

    scale, rot, trans = s, r, t
    p = src @ rot.T * scale + trans
    for _ in range(ICP_ROUNDS):
        _, nearest = tree.query(p, workers=-1)
        scale, rot, trans = kabsch(src, body[nearest], scale=True)
        p = src @ rot.T * scale + trans
    d, _ = tree.query(p, workers=-1)
    similarity = float(d.mean())

    # Then affine: the export is stretched by a different amount on each axis.
    affine = np.vstack([rot.T * scale, trans[None, :]])  # (4, 3): rows x, y, z, 1
    homog = np.hstack([src, np.ones((len(src), 1))])
    for _ in range(ICP_ROUNDS):
        p = homog @ affine
        _, nearest = tree.query(p, workers=-1)
        affine, *_ = np.linalg.lstsq(homog, body[nearest], rcond=None)
    p = homog @ affine
    d, _ = tree.query(p, workers=-1)

    def transform(points: np.ndarray) -> np.ndarray:
        return np.hstack([points, np.ones((len(points), 1))]) @ affine

    return transform, {
        "quarter_turns": quarter,
        "coarse_m": coarse,
        "runner_up_m": runner_up,
        "similarity_m": similarity,
        "affine_m": float(d.mean()),
        "scale": float(scale),
    }


# ------------------------------------------------------------ part-wise fit --

def rigid_parts(body: np.ndarray, joints: np.ndarray, weights: np.ndarray, parent: list,
                source_surface: np.ndarray):
    """Move the body onto the download one bone at a time, blended by skin weight.

    The download is the same creature drawn again, and what differs between
    two drawings of a creature is where its parts are and how big: the head
    sits further back, an arm is longer, the fingers spread. That is a rigid
    move per part, which is exactly what a rig describes, and the body carries
    its rig. Each bone takes the vertices it dominates and ICPs them onto the
    download's surface -- a similarity, because a regenerated head is a
    bigger or smaller head and not only a moved one, with the scale held
    within `PART_SCALE` so a thin part cannot collapse onto a neighbour --
    starting from its parent's answer, so a hand begins where its forearm
    ended up. A bone dominating
    too few vertices to fit alone inherits its parent's move. Every vertex
    then blends its bones' moves by its own weights, the way the game skins
    it, so a part boundary bends rather than tears.
    """
    tree = cKDTree(source_surface)
    n_bones = len(parent)
    dominant = joints[np.arange(len(joints)), weights.argmax(1)]
    rot = [np.eye(3) for _ in range(n_bones)]
    trans = [np.zeros(3) for _ in range(n_bones)]
    scl = [1.0] * n_bones
    report = []
    depth = [0] * n_bones
    for b in range(n_bones):
        d, p = 0, parent[b]
        while p >= 0:
            d, p = d + 1, parent[p]
        depth[b] = d
    for b in sorted(range(n_bones), key=lambda k: depth[k]):
        p = parent[b]
        if p >= 0:
            rot[b], trans[b], scl[b] = rot[p].copy(), trans[p].copy(), scl[p]
        verts = body[dominant == b]
        if len(verts) < PART_MIN_VERTS:
            report.append((b, len(verts), None, scl[b]))
            continue
        s, r, t = scl[b], rot[b], trans[b]
        keep = int(len(verts) * PART_TRIM)
        for _ in range(PART_ROUNDS):
            moved = verts @ r.T * s + t
            d, nearest = tree.query(moved, workers=-1)
            best = np.argsort(d)[:keep]
            s, r, t = kabsch(verts[best], source_surface[nearest[best]], scale=True)
            if not PART_SCALE[0] <= s <= PART_SCALE[1]:
                s = min(max(s, PART_SCALE[0]), PART_SCALE[1])
                t = source_surface[nearest[best]].mean(0) - s * (r @ verts[best].mean(0))
        scl[b], rot[b], trans[b] = s, r, t
        moved = verts @ r.T * s + t
        d, _ = tree.query(moved, workers=-1)
        report.append((b, len(verts), float(np.sort(d)[:keep].mean()), s))
    out = np.zeros_like(body)
    for k in range(joints.shape[1]):
        for b in range(n_bones):
            sel = joints[:, k] == b
            if not sel.any():
                continue
            w = weights[sel, k][:, None]
            out[sel] += w * (body[sel] @ rot[b].T * scl[b] + trans[b])
    d, _ = tree.query(out, workers=-1)
    return out, float(d.mean()), float(np.percentile(d, 95)), report


# -------------------------------------------------------------- smooth pull --

def neighbour_average(idx: np.ndarray, n: int):
    """Row-normalised vertex adjacency (with self), so `L @ field` smooths a field."""
    i = np.concatenate([idx[:, 0], idx[:, 1], idx[:, 2], idx[:, 1], idx[:, 2], idx[:, 0], np.arange(n)])
    j = np.concatenate([idx[:, 1], idx[:, 2], idx[:, 0], idx[:, 0], idx[:, 1], idx[:, 2], np.arange(n)])
    a = coo_matrix((np.ones(len(i)), (i, j)), shape=(n, n)).tocsr()
    a.data[:] = 1.0
    deg = np.asarray(a.sum(1)).ravel()
    return coo_matrix((1.0 / deg[a.nonzero()[0]], a.nonzero()), shape=(n, n)).tocsr()


def warp(body: np.ndarray, idx: np.ndarray, source_surface: np.ndarray):
    """Pull the (part-placed) body's vertices onto the download's surface, smoothly.

    Each vertex is drawn to its nearest point on the download, the pull is
    averaged over the mesh neighbourhood so it is a deformation and not a
    scatter, and the two are repeated with the averaging tightening each
    round. After the parts are placed what is left is millimetres, so the
    schedule is short and no feature has far to travel.
    """
    tree = cKDTree(source_surface)
    smooth = neighbour_average(idx, len(body))
    warped = body.copy()
    for passes in WARP_SMOOTHING:
        _, nearest = tree.query(warped, workers=-1)
        pull = source_surface[nearest] - warped
        for _ in range(passes):
            pull = smooth @ pull
        warped = warped + pull
    d, _ = tree.query(warped, workers=-1)
    return warped, float(d.mean()), float(np.percentile(d, 95))


# ------------------------------------------------------------------- paint --

def vertex_normals(pos: np.ndarray, idx: np.ndarray) -> np.ndarray:
    tri = pos[idx]
    face = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])  # area-weighted
    out = np.zeros_like(pos)
    for k in range(3):
        np.add.at(out, idx[:, k], face)
    return out / np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-12)


def rasterize(uv: np.ndarray, idx: np.ndarray, attr: np.ndarray, size: int):
    """Per-texel interpolation of `attr` (n, k) over the body's UV layout, and
    which texels are painted."""
    h = w = size
    where = np.zeros((h, w, attr.shape[1]), dtype=np.float32)
    mask = np.zeros((h, w), dtype=bool)
    px = uv * np.array([w, h])  # glTF UV: origin top-left, v runs down the image
    eps = 1e-4
    for tri in idx:
        a, b, c = px[tri]
        x0 = max(int(np.floor(min(a[0], b[0], c[0]))), 0)
        x1 = min(int(np.ceil(max(a[0], b[0], c[0]))), w - 1)
        y0 = max(int(np.floor(min(a[1], b[1], c[1]))), 0)
        y1 = min(int(np.ceil(max(a[1], b[1], c[1]))), h - 1)
        if x1 < x0 or y1 < y0:
            continue
        det = (b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])
        if abs(det) < 1e-12:
            continue
        xs = np.arange(x0, x1 + 1) + 0.5
        ys = np.arange(y0, y1 + 1) + 0.5
        gx, gy = np.meshgrid(xs, ys)
        w1 = ((gx - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (gy - a[1])) / det
        w2 = ((b[0] - a[0]) * (gy - a[1]) - (gx - a[0]) * (b[1] - a[1])) / det
        w0 = 1.0 - w1 - w2
        inside = (w0 >= -eps) & (w1 >= -eps) & (w2 >= -eps)
        if not inside.any():
            continue
        p = (w0[..., None] * attr[tri[0]] + w1[..., None] * attr[tri[1]]
             + w2[..., None] * attr[tri[2]])
        block = where[y0:y1 + 1, x0:x1 + 1]
        block[inside] = p[inside]
        mask[y0:y1 + 1, x0:x1 + 1] |= inside
    return where, mask


def surface_samples(pos: np.ndarray, uv: np.ndarray, idx: np.ndarray,
                    tex: np.ndarray, total: int):
    """Points spread over a surface by area: (position, colour, normal) each."""
    tri = pos[idx]
    face = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    area = 0.5 * np.linalg.norm(face, axis=1)
    normal = face / np.maximum(2.0 * area[:, None], 1e-12)
    counts = np.maximum(1, np.round(area / area.sum() * total)).astype(np.int64)
    which = np.repeat(np.arange(len(idx)), counts)
    rng = np.random.default_rng(7)
    r1 = np.sqrt(rng.random(len(which)))
    r2 = rng.random(len(which))
    bary = np.stack([1.0 - r1, r1 * (1.0 - r2), r1 * r2], axis=1)
    corners = idx[which]
    p = np.einsum("ni,nij->nj", bary, pos[corners]).astype(np.float32)
    t = np.einsum("ni,nij->nj", bary, uv[corners])
    th, tw = tex.shape[:2]
    col = np.clip((t[:, 0] * tw).astype(np.int64), 0, tw - 1)
    row = np.clip((t[:, 1] * th).astype(np.int64), 0, th - 1)
    return p, tex[row, col], normal[which].astype(np.float32)


def paint(texel_pos: np.ndarray, texel_normal: np.ndarray, sample_pos: np.ndarray,
          sample_col: np.ndarray, sample_normal: np.ndarray):
    """Each texel's colour from the nearest samples that face its way.

    Nearest alone is wrong wherever two surfaces lie close and face apart --
    an eyelid over an eyeball, a lip over the teeth -- because the nearest
    sample to a lid texel can be the eyeball's. Weighting by how well the
    sample's normal agrees with the texel's keeps lid paint on lids; a texel
    that finds no agreeing sample among its neighbours falls back to the
    nearest, so nothing is ever left unpainted.
    """
    tree = cKDTree(sample_pos)
    d, i = tree.query(texel_pos, k=NEIGHBOURS, workers=-1)
    facing = np.einsum("nj,nkj->nk", texel_normal, sample_normal[i])
    weight = np.clip(facing, 0.0, 1.0) ** 3 / (d + 1e-4)
    total = weight.sum(1)
    lost = total <= 1e-9
    weight[lost, 0] = 1.0
    total[lost] = 1.0
    weight /= total[:, None]
    colour = (sample_col[i].astype(np.float32) * weight[..., None]).sum(1)
    return colour, d[:, 0], float(lost.mean())


# -------------------------------------------------------------------- bake --

def bake(glb: Path, name: str, dry_run: bool = False, reference: Path = REFERENCE) -> dict:
    if not reference.is_file():
        raise FileNotFoundError(
            "%s is missing; write it with\n"
            "    \"$GODOT\" --headless --path . --script tools/export_body_ref.gd" % reference)
    t0 = time.time()
    gb, body_pos, body_uv, body_idx = load_mesh(reference)
    joints, weights, parent, _names = load_rig(gb)
    g, src_pos, src_uv, src_idx = load_mesh(glb)
    tex = texture_of(g)
    verts, prims, skinned = ex.mesh_shape(g.doc)
    blank = np.zeros((1, 1, 3), np.uint8)

    body_surface, _, _ = surface_samples(body_pos, body_uv, body_idx, blank, BODY_SURFACE)
    transform, fit = align(src_pos, body_surface)
    placed = transform(src_pos)
    sample_pos, sample_col, sample_normal = surface_samples(placed, src_uv, src_idx, tex, SAMPLES)
    fit_cloud = sample_pos[::6].astype(np.float64)

    parted, fit["parts_m"], fit["parts_p95_m"], parts = rigid_parts(
        body_pos, joints, weights, parent, fit_cloud)
    warped, fit["warped_m"], fit["warped_p95_m"] = warp(parted, body_idx, fit_cloud)
    if fit["warped_m"] > REFUSE_RESIDUAL_M:
        raise ValueError("does not fit the body: mean residual %.1f mm after warping"
                         % (fit["warped_m"] * 1000.0))

    normals = vertex_normals(warped, body_idx)
    where, mask = rasterize(body_uv, body_idx, np.hstack([warped, normals]), SIZE)
    texels = where[mask]
    colour, gap, lost = paint(texels[:, :3], texels[:, 3:], sample_pos, sample_col, sample_normal)

    img = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    img[mask] = colour
    gutter = distance_transform_edt(~mask, return_distances=False, return_indices=True)
    img = img[gutter[0], gutter[1]]
    out_img = Image.fromarray(np.clip(np.round(img), 0, 255).astype(np.uint8), "RGB")

    out = ex.DEST / name / "basecolor.png"
    written = 0
    if not dry_run:
        out.parent.mkdir(parents=True, exist_ok=True)
        out_img.save(out, "PNG", optimize=True)
        written = out.stat().st_size

    return {
        "name": name, "glb": glb, "glb_bytes": glb.stat().st_size,
        "material": "baked", "format": "BAKE", "mime": "image/png", "mode": "RGB",
        "src_size": (tex.shape[1], tex.shape[0]), "src_bytes": 0,
        "out_size": (SIZE, SIZE), "out_bytes": written, "action": "baked",
        "verts": verts, "prims": prims, "skinned": skinned,
        "fit": fit, "parts": parts, "coverage": float(mask.mean()),
        "paint_gap_mean_m": float(gap.mean()), "paint_gap_p95_m": float(np.percentile(gap, 95)),
        "paint_lost": lost, "seconds": time.time() - t0,
    }


def describe(r: dict) -> str:
    f = r["fit"]
    fitted = sum(1 for part in r["parts"] if part[2] is not None)
    return ("%-8s %6d verts  turned %d/4  scale %.3f  whole-body fit %.1f mm (coarse %.1f, "
            "runner-up %.1f, similarity %.1f)  parts %.1f mm (%d of %d bones fitted)  warped %.1f mm "
            "(p95 %.1f)  paint gap %.1f mm (p95 %.1f, %.2f%% by nearest)  coverage %.0f%%  %.0f s" % (
                r["name"], r["verts"], f["quarter_turns"], f["scale"],
                f["affine_m"] * 1000, f["coarse_m"] * 1000, f["runner_up_m"] * 1000,
                f["similarity_m"] * 1000,
                f["parts_m"] * 1000, fitted, len(r["parts"]),
                f["warped_m"] * 1000, f["warped_p95_m"] * 1000,
                r["paint_gap_mean_m"] * 1000, r["paint_gap_p95_m"] * 1000, r["paint_lost"] * 100,
                r["coverage"] * 100, r["seconds"]))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("names", nargs="+", help="skin folder names under assets/source/skins")
    ap.add_argument("--source", default=str(ex.DEFAULT_SOURCE))
    ap.add_argument("--reference", default=str(REFERENCE))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--parts", action="store_true", help="also print the per-bone fit")
    args = ap.parse_args(argv)
    failed = 0
    for name in args.names:
        folder = Path(args.source) / name
        glb = folder / (name + ".glb")
        if not glb.is_file():
            hits = sorted(folder.glob("*.glb"))
            if not hits:
                print("FAILED %s: no .glb" % name, file=sys.stderr)
                failed += 1
                continue
            glb = hits[0]
        try:
            r = bake(glb, name.lower(), args.dry_run, Path(args.reference))
            print(describe(r))
            if args.parts:
                names = load_rig(Gltf.load(str(Path(args.reference))))[3]
                for b, n, d, s in r["parts"]:
                    print("    %-28s %5d verts  x%.3f  %s" % (
                        names[b], n, s, "inherits parent" if d is None else "%.1f mm" % (d * 1000)))
        except Exception as err:
            print("FAILED %s: %s" % (name, err), file=sys.stderr)
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
