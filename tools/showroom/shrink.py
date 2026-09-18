"""Web-size copies of the showroom renders. Development tool, not shipped.

    python tools/showroom/shrink.py tools/showroom/out
    python tools/showroom/shrink.py out/layouts out/web_layouts

Godot photographs at 2560x1440 whatever `--resolution` says, and a wall of
eight styles at that size is 80 MB of PNG nobody can scroll through. This writes
JPGs at 1600 wide, quality 85.

Two shapes of source directory, because the two showrooms are shaped
differently and one of them should not need a second copy of this file:

  <out>/<variant>/<mode>.png  ->  <web>/<variant>__<mode>.jpg   (theme showroom)
  <out>/<name>.png            ->  <web>/<name>.jpg              (layout showroom)

`<web>` defaults to `<out>/web`, which is where the theme showroom has always
put it.
"""

import sys
from pathlib import Path

from PIL import Image

WIDTH = 1600
QUALITY = 85
SKIP = {"web", "logs"}


def sources(out: Path) -> list[tuple[Path, str]]:
    """Every PNG under `out`, paired with the stem its JPG should carry."""
    nested = [
        (png, f"{png.parent.name}__{png.stem}")
        for png in sorted(out.glob("*/*.png"))
        if png.parent.name not in SKIP
    ]
    flat = [(png, png.stem) for png in sorted(out.glob("*.png"))]
    return nested + flat


def main() -> int:
    args = sys.argv[1:]
    out = Path(args[0]) if args else Path("tools/showroom/out")
    web = Path(args[1]) if len(args) > 1 else out / "web"
    web.mkdir(parents=True, exist_ok=True)

    written = 0
    for png, stem in sources(out):
        with Image.open(png) as image:
            height = round(image.height * WIDTH / image.width)
            small = image.convert("RGB").resize((WIDTH, height), Image.LANCZOS)
            small.save(web / f"{stem}.jpg", quality=QUALITY, optimize=True)
        written += 1

    print(f"shrink: wrote {written} jpg into {web}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
