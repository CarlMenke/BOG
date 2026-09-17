#!/usr/bin/env python3
"""Pull each team skin's base colour texture out of its Tripo .glb.

The 13 team skins are Tripo retextures of the same BOG sculpt (one prompt per
skin, the structure held still), downloaded with the texture embedded in the
.glb. A skin in the game is a recolour (D-100): a PNG in the body's UV layout
at `art/skins/<name>/basecolor.png`, worn through `Bog.wear_skin`. This script
is the one step between the two, so the skins can be rebuilt from the downloads
rather than from whatever Godot happened to leave beside them.

    python tools/extract_skins.py                 # every skin
    python tools/extract_skins.py MUCK RIME       # just these
    python tools/extract_skins.py --source DIR    # .glb's live elsewhere
    python tools/extract_skins.py --dry-run       # report, write nothing

For each .glb it reads the glTF JSON out of the container itself (no
pygltflib in this environment), follows the *material's*
`pbrMetallicRoughness.baseColorTexture` to its image — never a normal or
metallic-roughness map, which Tripo also ships — decodes it, downsamples to
2048 square if Tripo gave 4096 (never upsamples: the example skin is 2048 and
a recolour does not need more), and writes the PNG.

It also prints what it found in the mesh: vertex count and primitive count per
GLB, against the body's one skinned mesh of 15 872 vertices (D-095). A count
that differs is worth saying out loud but does not settle anything — a Tripo
re-export can renumber vertices and still carry the same UV layout. The render
check is the real test:

    "$GODOT" --path . --resolution 1600x700 --script tools/snapshot.gd -- \
        res://tools/preview_bog.tscn build/review/skin_muck.png 30 Idle skin=muck
"""

from __future__ import annotations

import argparse
import io
import json
import struct
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = REPO / "assets" / "source" / "skins"
DEST = REPO / "art" / "skins"

# The example recolour's size (D-100): the body's own texture is 4096² / 12 MB,
# which a recolour does not need.
TARGET = 2048

# The body as Godot imports `art/bog/BOG.fbx`: one skinned mesh, this many
# vertices (assets/source/README.md, "Godot import facts").
BODY_VERTS = 15872

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def read_glb(path: Path):
    """Return (gltf_json, bin_chunk) from a binary glTF container.

    12-byte header (magic, version, length), then chunks of
    (length, type, payload) — the JSON chunk first, the BIN chunk after it.
    """
    blob = path.read_bytes()
    magic, version, total = struct.unpack_from("<III", blob, 0)
    if magic != GLB_MAGIC:
        raise ValueError("%s is not a .glb (bad magic)" % path.name)
    if version != 2:
        raise ValueError("%s is glTF binary version %d, expected 2" % (path.name, version))
    gltf = None
    bin_chunk = b""
    off = 12
    while off < min(total, len(blob)):
        length, kind = struct.unpack_from("<II", blob, off)
        payload = blob[off + 8: off + 8 + length]
        if kind == CHUNK_JSON:
            gltf = json.loads(payload.decode("utf-8"))
        elif kind == CHUNK_BIN:
            bin_chunk = payload
        off += 8 + length + (-length % 4)
    if gltf is None:
        raise ValueError("%s has no JSON chunk" % path.name)
    return gltf, bin_chunk


def base_colour_image(gltf):
    """Index of the image the first material's base colour texture points at.

    material -> pbrMetallicRoughness.baseColorTexture.index -> textures[i]
    -> source -> images[j]. Anything else a material carries (normal,
    metallicRoughness, emissive) is deliberately not followed.
    """
    materials = gltf.get("materials") or []
    textures = gltf.get("textures") or []
    for mat in materials:
        pbr = mat.get("pbrMetallicRoughness") or {}
        tex = pbr.get("baseColorTexture")
        if tex is None:
            continue
        entry = textures[tex["index"]]
        source = entry.get("source")
        if source is None:  # KHR_texture_basisu and friends
            for ext in (entry.get("extensions") or {}).values():
                if isinstance(ext, dict) and "source" in ext:
                    source = ext["source"]
                    break
        if source is not None:
            return source, mat.get("name", "?")
    raise ValueError("no material with a pbrMetallicRoughness.baseColorTexture")


def image_bytes(gltf, bin_chunk, index):
    img = (gltf.get("images") or [])[index]
    if "bufferView" not in img:
        raise ValueError("image %d is a URI, not embedded" % index)
    view = gltf["bufferViews"][img["bufferView"]]
    start = view.get("byteOffset", 0)
    return bin_chunk[start: start + view["byteLength"]], img.get("mimeType", "?")


def mesh_shape(gltf):
    """(vertices, primitives, skinned) summed over every mesh in the file."""
    verts = 0
    prims = 0
    skinned = False
    accessors = gltf.get("accessors") or []
    for mesh in gltf.get("meshes") or []:
        for prim in mesh.get("primitives") or []:
            prims += 1
            attrs = prim.get("attributes") or {}
            if "POSITION" in attrs:
                verts += accessors[attrs["POSITION"]].get("count", 0)
            if "JOINTS_0" in attrs:
                skinned = True
    return verts, prims, skinned


def extract(glb: Path, name: str, dry_run: bool) -> dict:
    gltf, bin_chunk = read_glb(glb)
    verts, prims, skinned = mesh_shape(gltf)
    index, mat_name = base_colour_image(gltf)
    raw, mime = image_bytes(gltf, bin_chunk, index)

    src = Image.open(io.BytesIO(raw))
    fmt, size, mode = src.format, src.size, src.mode
    img = src.convert("RGB")

    longest = max(img.size)
    if longest > TARGET:
        scale = TARGET / float(longest)
        out_size = (max(1, round(img.width * scale)), max(1, round(img.height * scale)))
        img = img.resize(out_size, Image.LANCZOS)
        action = "downsampled"
    else:
        action = "kept"  # never upsample

    out = DEST / name / "basecolor.png"
    written = 0
    if not dry_run:
        out.parent.mkdir(parents=True, exist_ok=True)
        img.save(out, "PNG", optimize=True)
        written = out.stat().st_size

    return {
        "name": name,
        "glb": glb,
        "glb_bytes": glb.stat().st_size,
        "material": mat_name,
        "format": fmt,
        "mime": mime,
        "mode": mode,
        "src_size": size,
        "src_bytes": len(raw),
        "out_size": img.size,
        "out_bytes": written,
        "action": action,
        "verts": verts,
        "prims": prims,
        "skinned": skinned,
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("names", nargs="*", help="skin folder names (default: all)")
    ap.add_argument("--source", default=str(DEFAULT_SOURCE),
                    help="folder of <NAME>/<NAME>.glb (default: assets/source/skins)")
    ap.add_argument("--dry-run", action="store_true", help="report only, write nothing")
    args = ap.parse_args(argv)

    source = Path(args.source)
    if not source.is_dir():
        print("no such source folder: %s" % source, file=sys.stderr)
        return 1

    if args.names:
        folders = [source / n for n in args.names]
    else:
        folders = sorted(d for d in source.iterdir() if d.is_dir())

    rows = []
    failed = []
    for folder in folders:
        glb = folder / (folder.name + ".glb")
        if not glb.is_file():
            hits = sorted(folder.glob("*.glb"))
            if not hits:
                failed.append((folder.name, "no .glb"))
                continue
            glb = hits[0]
        try:
            rows.append(extract(glb, folder.name.lower(), args.dry_run))
        except Exception as err:  # a bad download should not stop the other 12
            failed.append((folder.name, str(err)))

    print("%-8s %-6s %-11s %-11s %-9s %8s %5s  %s" % (
        "skin", "fmt", "source", "written", "png", "verts", "prim", "note"))
    for r in rows:
        note = "" if r["verts"] == BODY_VERTS else "verts differ from body's %d" % BODY_VERTS
        if not r["skinned"]:
            note = ("unskinned; " + note).strip("; ")
        print("%-8s %-6s %-11s %-11s %-9s %8d %5d  %s" % (
            r["name"],
            r["format"],
            "%dx%d" % r["src_size"],
            "%dx%d" % r["out_size"],
            r["action"],
            r["verts"], r["prims"], note))
        print("         %s  source image %.1f MB %s, png %.1f MB" % (
            r["glb"], r["src_bytes"] / 1e6, r["mime"],
            r["out_bytes"] / 1e6))

    for name, err in failed:
        print("FAILED %s: %s" % (name, err), file=sys.stderr)

    print("\n%d skin%s written to %s%s" % (
        len(rows), "" if len(rows) == 1 else "s", DEST,
        " (dry run: nothing written)" if args.dry_run else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
