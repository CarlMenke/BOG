# assets/source/skins — the Tripo retexture downloads

One folder per team skin, one `<NAME>/<NAME>.glb` in each: the BOG sculpt sent
back through Tripo with a retexture prompt (the prompt asked for the structure
to stay put, so every download is the same mesh — 15 872 vertices, one
primitive, the same UV layout — wearing a different paint job) and downloaded
with the texture embedded.

These are the source of `art/skins/<name>/basecolor.png`, and nothing else.
The game never loads a `.glb` from here:

    python tools/extract_skins.py

pulls each material's `pbrMetallicRoughness.baseColorTexture` out of the
container, downsamples Tripo's 4096² JPEG to the 2048² a recolour needs (D-100)
and writes `art/skins/<name>/basecolor.png`, lower-cased. That PNG is what is
committed and what `Bog.wear_skin` wears.

The `.gdignore` beside this file keeps Godot out, the way `Rust/`, `props/` and
`Mushroom/` do: importing 13 more copies of the body costs ten minutes of build
and buys nothing, because the mesh is already in the project as `art/bog/BOG.fbx`.

The downloads themselves are untracked — they are big, and they are a Tripo
account's history, not the game's. Keep them if you want to re-extract; the
skins in `art/skins/` stand on their own without them.

## Before the `.gdignore` landed

Godot had already imported some of these and left its work beside the
downloads: `<NAME>.glb.import` files and extracted textures
(`MUCK_MUCK_basecolor.jpg`, `BOO_tripo_rgb_<uuid>.jpg`, and their `.import`s).
They are stale the moment Godot stops looking here. Delete them:

    rm assets/source/skins/*/*.glb.import assets/source/skins/*/*.jpg \
       assets/source/skins/*/*.jpg.import

Do not extract a skin from one of those JPEGs. They are whatever Godot's
importer wrote at the time; `tools/extract_skins.py` reads the `.glb`, which is
the thing that was downloaded.
