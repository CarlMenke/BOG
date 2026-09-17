# bog — the body's own

The plain BOG: no texture of its own, the yellow that `art/bog/BOG.fbx` was
imported wearing. It is a folder because it is a **pickable skin** — the first
one, `Skins.NAMES[0]`, and the default — and the picker needs a tile for it the
same as it needs one for `muck`.

So this folder holds exactly one file, and it is not a texture:

    thumb.png    the picker's 128² tile, rendered by tools/skin_thumbs.gd

There is deliberately no `basecolor.png`. `Skins.texture_of(0)` is **null**,
which is `Bog.wear_skin`'s own word for "put the imported texture back" — so
choosing this skin loads nothing and undoes whatever the last one did.

The thumb is the only picture of the undressed body in the project, and it is
made the same way every other tile is:

    "$GODOT" --path . --resolution 512x512 --script tools/skin_thumbs.gd -- bog
