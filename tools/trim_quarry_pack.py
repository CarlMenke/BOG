"""Turn the raw quarry pack into game-ready meshes in `art/maps/quarry/`.

The pack (`assets/quarry_asset_pack`, never committed) is Tripo exports at
about 1.9 M triangles and three 4096-square textures a prop. They go through
the same weld-decimate-retransfer pipeline the hand props do
(`tools/decimate_assets.py`), because the weld is the step that matters here
too: these meshes are split along every UV seam, and a decimator that respects
those seams (`gltf-transform simplify` was tried first) stops at 200-500 k
triangles however hard it is pushed.

Exact copies are skipped by hash. Names are cleaned to snake_case and numbered
per kind. The walk-through pieces — tunnels, the entrance, the staircase — get
a bigger budget because a Bog stands inside them; everything else is seen from
metres away. Sources are never touched; re-running is safe and skips what is
already built.

Usage:  python tools/trim_quarry_pack.py [substring ...]
"""
import glob, hashlib, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import decimate_assets as da

SRC = "assets/quarry_asset_pack"
da.OUT_DIR = os.path.join(da.REPO, "art", "maps", "quarry")
BIG = ("tunnel", "entrance", "staircase")


def clean(stem):
    s = stem.lower().replace(" - copy", "")
    s = re.sub(r"\(\d+\)", "", s)
    s = re.sub(r"3d|model", "", s)
    return re.sub(r"[+ _]+", "_", s).strip("_")


def main(only):
    seen, count = set(), {}
    for path in sorted(glob.glob(os.path.join(da.REPO, SRC, "*.glb"))):
        with open(path, "rb") as fh:
            digest = hashlib.md5(fh.read()).hexdigest()
        if digest in seen:
            continue
        seen.add(digest)
        base = clean(os.path.splitext(os.path.basename(path))[0])
        count[base] = count.get(base, 0) + 1
        name = "%s_%02d" % (base, count[base])
        if only and not any(o in name for o in only):
            continue
        if os.path.exists(os.path.join(da.OUT_DIR, name + ".glb")):
            continue
        big = any(k in base for k in BIG)
        try:
            da.process(name, os.path.relpath(path, da.REPO), 14000 if big else 5000,
                       2048 if big else 1024)
        except SystemExit as err:
            da.log("  SKIPPED %s: %s" % (name, err))


if __name__ == "__main__":
    main(sys.argv[1:])
