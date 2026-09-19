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
pygltflib in this environment), follows the *material's* texture slots to their
images, decodes them, downsamples to 2048 square if Tripo gave 4096 (never
upsamples: the example skin is 2048 and a recolour does not need more), and
writes the PNGs.

Three slots, one file each, and only `basecolor.png` is required (D-154):

    basecolor.png   pbrMetallicRoughness.baseColorTexture
    roughness.png   pbrMetallicRoughness.metallicRoughnessTexture, green channel
                    only (glTF packs roughness in green, metallic in blue), so
                    the file is a grey map the body's material reads on red
    emission.png    emissiveTexture

A skin whose download carries neither of the optional two writes neither, and
`Skins`, `Bog.wear_skin` and the tint shader all read it exactly as they did
before. A normal map is still not followed: the silhouette is the sculpt's and
a recolour does not change it. `KHR_materials_emissive_strength` is not carried
either — the brightness of a glow is a dial in the shader, not in the download.

It also prints what it found in the mesh: vertex count and primitive count per
GLB, against the body's one skinned mesh of 15 872 vertices (D-095). A download
whose count differs is a *regenerated* sculpt in its own UV layout, and its
texture cannot be worn as it is; such a skin is handed to `tools/bake_skin.py`,
which registers the body onto the download and paints the body's layout from
it, writing the same PNG (D-126). Either way the render check is the real test:

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

# The three files a skin folder may hold, in the order they are written.
# `basecolor` is the skin; the other two are written only when the download
# carries them (D-154), and the folder convention is "the file is there or it
# is not" — nothing anywhere records which skins have a glow.
SLOTS = ("basecolor", "roughness", "emission")

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


def texture_image(gltf, tex):
    """Index of the image a texture reference points at, or None.

    textures[i] -> source -> images[j], with the source read out of an
    extension (KHR_texture_basisu and friends) when the entry has none of its
    own.
    """
    if tex is None:
        return None
    entry = (gltf.get("textures") or [])[tex["index"]]
    source = entry.get("source")
    if source is None:
        for ext in (entry.get("extensions") or {}).values():
            if isinstance(ext, dict) and "source" in ext:
                return ext["source"]
    return source


def material_maps(gltf):
    """({slot: image index}, material name) for the first textured material.

    The base colour is the slot that decides which material this is — a
    download has one, and a material without one is not the body's paint. The
    other two are taken from that same material if it carries them and left out
    if it does not (D-154). A normal map is deliberately not followed.
    """
    for mat in gltf.get("materials") or []:
        pbr = mat.get("pbrMetallicRoughness") or {}
        base = texture_image(gltf, pbr.get("baseColorTexture"))
        if base is None:
            continue
        maps = {"basecolor": base}
        rough = texture_image(gltf, pbr.get("metallicRoughnessTexture"))
        if rough is not None:
            maps["roughness"] = rough
        emissive = texture_image(gltf, mat.get("emissiveTexture"))
        if emissive is not None:
            maps["emission"] = emissive
        return maps, mat.get("name", "?")
    raise ValueError("no material with a pbrMetallicRoughness.baseColorTexture")


def image_bytes(gltf, bin_chunk, index):
    img = (gltf.get("images") or [])[index]
    if "bufferView" not in img:
        raise ValueError("image %d is a URI, not embedded" % index)
    view = gltf["bufferViews"][img["bufferView"]]
    start = view.get("byteOffset", 0)
    return bin_chunk[start: start + view["byteLength"]], img.get("mimeType", "?")


def fit(img):
    """Tripo's 4096² down to the 2048² a recolour needs, never the other way."""
    longest = max(img.size)
    if longest <= TARGET:
        return img, "kept"
    scale = TARGET / float(longest)
    size = (max(1, round(img.width * scale)), max(1, round(img.height * scale)))
    return img.resize(size, Image.LANCZOS), "downsampled"


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
    if verts != BODY_VERTS:
        # Not the body's mesh, so not the body's UV layout: the texture cannot
        # be worn as it is. `bake_skin` registers the body onto the download
        # part by part and paints the body's layout from it (the second batch
        # of skins, 2026-09-18, came back from Tripo regenerated at 9 124
        # vertices; the first thirteen were the body itself). It needs
        # `build/body_ref.glb` and says so if missing.
        import bake_skin
        return bake_skin.bake(glb, name, dry_run)
    maps, mat_name = material_maps(gltf)
    row = {
        "name": name,
        "glb": glb,
        "glb_bytes": glb.stat().st_size,
        "material": mat_name,
        "verts": verts,
        "prims": prims,
        "skinned": skinned,
        "maps": [],
    }
    for slot in SLOTS:
        if slot not in maps:
            continue
        raw, mime = image_bytes(gltf, bin_chunk, maps[slot])
        src = Image.open(io.BytesIO(raw))
        # glTF packs roughness in green and metallic in blue; the body is never
        # metal, so the green channel alone is the whole of the map and a grey
        # PNG is a third of the file. Everything else keeps its colour.
        img = src.convert("RGB")
        if slot == "roughness":
            img = img.split()[1]
        img, action = fit(img)

        out = DEST / name / (slot + ".png")
        written = 0
        if not dry_run:
            out.parent.mkdir(parents=True, exist_ok=True)
            img.save(out, "PNG", optimize=True)
            written = out.stat().st_size
        entry = {
            "slot": slot,
            "format": src.format,
            "mime": mime,
            "mode": src.mode,
            "src_size": src.size,
            "src_bytes": len(raw),
            "out_size": img.size,
            "out_bytes": written,
            "action": action,
        }
        row["maps"].append(entry)
        if slot == "basecolor":  # the row's headline numbers are the paint's
            row.update(entry)
    return row


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
        note = "" if r["verts"] == BODY_VERTS else "regenerated: baked onto the body's layout (tools/bake_skin.py)"
        if not r["skinned"]:
            note = ("unskinned; " + note).strip("; ")
        print("%-8s %-6s %-11s %-11s %-9s %8d %5d  %s" % (
            r["name"],
            r["format"],
            "%dx%d" % r["src_size"],
            "%dx%d" % r["out_size"],
            r["action"],
            r["verts"], r["prims"], note))
        print("         %s" % r["glb"])
        # One line per slot, so "this download had no roughness map" is read off
        # the report rather than off the folder afterwards.
        for m in r.get("maps") or []:
            print("         %-10s %-11s -> %-11s %-9s source %.1f MB %s, png %.1f MB" % (
                m["slot"] + ".png",
                "%dx%d" % m["src_size"], "%dx%d" % m["out_size"], m["action"],
                m["src_bytes"] / 1e6, m["mime"], m["out_bytes"] / 1e6))
        missing = [s for s in SLOTS[1:]
                   if s not in [m["slot"] for m in r.get("maps") or []]]
        if missing:
            print("         no %s map in the download" % " or ".join(missing))

    for name, err in failed:
        print("FAILED %s: %s" % (name, err), file=sys.stderr)

    print("\n%d skin%s written to %s%s" % (
        len(rows), "" if len(rows) == 1 else "s", DEST,
        " (dry run: nothing written)" if args.dry_run else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
