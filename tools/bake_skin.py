#!/usr/bin/env python3
"""Bake a remeshed Tripo skin's paint onto the body's own UV layout.

`tools/extract_skins.py` pulls a recolour straight out of its download, which
works because every one of the first thirteen downloads was the BOG sculpt
itself -- 15 872 vertices in the body's UV layout -- wearing new paint. A later
Tripo run can hand back the same sculpt *remeshed* (9 124 vertices, its own UV
islands): the paint is right, the layout is not, and worn as a texture it lands
on the body as a patchwork. This is the step for that case, and
`extract_skins.py` takes it on its own whenever a download's vertex count is
not the body's.

    python tools/bake_skin.py BLOOM KOI          # bake these
    python tools/bake_skin.py --dry-run BLOOM    # report the fit, write nothing

For each skin it
  1. reads the download's mesh and its base colour texture;
  2. aligns the mesh to the body: the four quarter turns about the vertical are
     tried against the body's bounding box, the one that lands closest wins,
     a few rounds of similarity ICP (rotation, uniform scale, translation)
     tighten it, and a few rounds of affine ICP finish it -- Tripo turns,
     rescales and stretches its exports unevenly, the sculpt underneath does
     not change;
  3. rasterises the body's UV layout at 2048 square, so every texel knows the
     point on the body it paints;
  4. samples the download's surface densely, each sample carrying the colour
     its own texture gives it, and paints each body texel from the nearest
     samples;
  5. fills the UV gutters from the nearest painted texel and writes
     `art/skins/<name>/basecolor.png` -- the same file, the same size and the
     same wear path (`Bog.wear_skin`) as an extracted skin.

The body it bakes onto is `build/body_ref.glb`, the body as Godot imports
`art/bog/BOG.fbx`, written by

    "$GODOT" --headless --path . --script tools/export_body_ref.gd

and remade whenever that FBX changes. The fit is reported in millimetres on the
finished body (1.80 m tall); a residual over a centimetre means the download is
not this sculpt, and the bake is refused rather than smeared.

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
#: Neighbours blended per texel, inverse-distance weighted.
NEIGHBOURS = 4
ICP_ROUNDS = 15
#: Points over the body's surface the download is fitted against.
BODY_SURFACE = 1_000_000
#: Rounds of the non-rigid pull, and how many neighbour-averaging passes smooth
#: the displacement field in each: wide first, so the whole head moves as one,
#: then tighter, so a brow ridge or a knuckle can settle on its own.
WARP_SMOOTHING = (16, 12, 8, 6, 4, 3)
#: A fit worse than this after warping is a different creature, not a different
#: paint job.
REFUSE_RESIDUAL_M = 0.010


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


def texture_of(g: Gltf) -> np.ndarray:
    index, _ = ex.base_colour_image(g.doc)
    raw, _ = ex.image_bytes(g.doc, g.blob, index)
    return np.asarray(Image.open(io.BytesIO(raw)).convert("RGB"), dtype=np.uint8)


def rot_y(angle: float) -> np.ndarray:
    c, s = np.cos(angle), np.sin(angle)
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])


def umeyama(p: np.ndarray, q: np.ndarray):
    """Similarity (scale, rotation, translation) taking points p onto q."""
    mp, mq = p.mean(0), q.mean(0)
    pc, qc = p - mp, q - mq
    cov = qc.T @ pc / len(p)
    u, d, vt = np.linalg.svd(cov)
    s = np.eye(3)
    if np.linalg.det(u) * np.linalg.det(vt) < 0:
        s[2, 2] = -1.0
    r = u @ s @ vt
    scale = np.trace(np.diag(d) @ s) / (pc ** 2).sum(1).mean()
    t = mq - scale * (r @ mp)
    return scale, r, t


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

    # Refine: the download's vertices onto their nearest body vertices, a
    # similarity fit, repeat. The sculpt is the same so this converges in a few.
    scale, rot, trans = s, r, t
    p = src @ rot.T * scale + trans
    for _ in range(ICP_ROUNDS):
        _, nearest = tree.query(p, workers=-1)
        scale, rot, trans = umeyama(src, body[nearest])
        p = src @ rot.T * scale + trans
    d, _ = tree.query(p, workers=-1)
    similarity = float(d.mean())

    # Then affine. Tripo does not only turn and rescale: the remeshed export
    # comes back stretched by a different amount on each axis (a tenth wider at
    # the arms, a few percent shorter), and a similarity fit leaves two
    # centimetres everywhere. Twelve parameters, least squares onto the nearest
    # body vertex, a few rounds; the same shape, so it converges the same way.
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
        "residual_mean_m": float(d.mean()),
        "residual_p95_m": float(np.percentile(d, 95)),
        "scale": float(scale),
    }


def neighbour_average(idx: np.ndarray, n: int):
    """Row-normalised vertex adjacency (with self), so `L @ field` smooths a field."""
    i = np.concatenate([idx[:, 0], idx[:, 1], idx[:, 2], idx[:, 1], idx[:, 2], idx[:, 0], np.arange(n)])
    j = np.concatenate([idx[:, 1], idx[:, 2], idx[:, 0], idx[:, 0], idx[:, 1], idx[:, 2], np.arange(n)])
    a = coo_matrix((np.ones(len(i)), (i, j)), shape=(n, n)).tocsr()
    a.data[:] = 1.0
    deg = np.asarray(a.sum(1)).ravel()
    return coo_matrix((1.0 / deg[a.nonzero()[0]], a.nonzero()), shape=(n, n)).tocsr()


def warp(body: np.ndarray, idx: np.ndarray, source_surface: np.ndarray):
    """Move the body's vertices onto the download's surface, smoothly.

    A retexture that Tripo has *regenerated* rather than repainted is the same
    creature to the eye and two centimetres off everywhere to the ruler: the
    head a little bigger, the belly a little rounder, the fingers spread. No
    affine map closes that, and a bake through one puts the eyes a socket's
    width from the sockets. So each body vertex is pulled to its nearest point
    on the download, the pull is averaged over the mesh neighbourhood so it is
    a deformation and not a scatter, and the two are repeated with the
    averaging tightening each round. The result is the body's vertices sitting
    on the download's skin with the body's own connectivity and UVs, which is
    what a texel needs to know where its paint is.
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


def rasterize(uv: np.ndarray, idx: np.ndarray, pos: np.ndarray, size: int):
    """Per-texel body position for the body's UV layout, and which texels are painted."""
    h = w = size
    where = np.zeros((h, w, 3), dtype=np.float32)
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
        p = (w0[..., None] * pos[tri[0]] + w1[..., None] * pos[tri[1]]
             + w2[..., None] * pos[tri[2]])
        block = where[y0:y1 + 1, x0:x1 + 1]
        block[inside] = p[inside]
        mask[y0:y1 + 1, x0:x1 + 1] |= inside
    return where, mask


def surface_samples(pos: np.ndarray, uv: np.ndarray, idx: np.ndarray,
                    tex: np.ndarray, total: int):
    """Points spread over the download's surface by area, each with its own colour."""
    tri = pos[idx]
    area = 0.5 * np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1)
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
    return p, tex[row, col]


def bake(glb: Path, name: str, dry_run: bool = False, reference: Path = REFERENCE) -> dict:
    if not reference.is_file():
        raise FileNotFoundError(
            "%s is missing; write it with\n"
            "    \"$GODOT\" --headless --path . --script tools/export_body_ref.gd" % reference)
    t0 = time.time()
    _, body_pos, body_uv, body_idx = load_mesh(reference)
    g, src_pos, src_uv, src_idx = load_mesh(glb)
    tex = texture_of(g)
    verts, prims, skinned = ex.mesh_shape(g.doc)

    body_surface, _ = surface_samples(body_pos, body_uv, body_idx, np.zeros((1, 1, 3), np.uint8), BODY_SURFACE)
    transform, fit = align(src_pos, body_surface)
    sample_pos, sample_col = surface_samples(transform(src_pos), src_uv, src_idx, tex, SAMPLES)
    warped, fit["warped_mean_m"], fit["warped_p95_m"] = warp(
        body_pos, body_idx, sample_pos[::6].astype(np.float64))
    if fit["warped_mean_m"] > REFUSE_RESIDUAL_M:
        raise ValueError("does not fit the body: mean residual %.1f mm after warping"
                         % (fit["warped_mean_m"] * 1000.0))

    # Every texel's point on the *warped* body, which is a point on the download.
    where, mask = rasterize(body_uv, body_idx, warped, SIZE)
    tree = cKDTree(sample_pos)
    texels = where[mask]
    d, i = tree.query(texels, k=NEIGHBOURS, workers=-1)
    weight = 1.0 / (d + 1e-4)
    weight /= weight.sum(1, keepdims=True)
    colour = (sample_col[i].astype(np.float32) * weight[..., None]).sum(1)

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
        "fit": fit, "coverage": float(mask.mean()),
        "paint_gap_mean_m": float(d[:, 0].mean()),
        "paint_gap_p95_m": float(np.percentile(d[:, 0], 95)),
        "seconds": time.time() - t0,
    }


def describe(r: dict) -> str:
    f = r["fit"]
    return ("%-8s %6d verts  turned %d/4  scale %.3f  affine fit %.1f mm (p95 %.1f; coarse %.1f, "
            "runner-up %.1f)  warped fit %.1f mm (p95 %.1f)  paint gap %.1f mm (p95 %.1f)  "
            "coverage %.0f%%  %.0f s" % (
                r["name"], r["verts"], f["quarter_turns"], f["scale"],
                f["residual_mean_m"] * 1000, f["residual_p95_m"] * 1000,
                f["coarse_m"] * 1000, f["runner_up_m"] * 1000,
                f["warped_mean_m"] * 1000, f["warped_p95_m"] * 1000,
                r["paint_gap_mean_m"] * 1000, r["paint_gap_p95_m"] * 1000,
                r["coverage"] * 100, r["seconds"]))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("names", nargs="+", help="skin folder names under assets/source/skins")
    ap.add_argument("--source", default=str(ex.DEFAULT_SOURCE))
    ap.add_argument("--reference", default=str(REFERENCE))
    ap.add_argument("--dry-run", action="store_true")
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
            print(describe(bake(glb, name.lower(), args.dry_run, Path(args.reference))))
        except Exception as err:
            print("FAILED %s: %s" % (name, err), file=sys.stderr)
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
