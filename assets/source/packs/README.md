# assets/source/packs — whole Mixamo packs, as they were downloaded

A pack arrives as a zip of twenty-odd animation-only FBXs named the way its
author named them (`sword and shield attack (3).fbx`), and it is bought for four
or five of them. This folder is where the whole thing lives, unrenamed, behind
its `.gdignore` so Godot never imports it.

A clip reaches the game the way every clip does and not one step differently: it
is **copied** into `assets/source/anims/` under `<Role>-<CamelCaseName>.fbx`,
given a row in `clips.json`, given an `.import` by `tools/clip_imports.sh`, and
imported (D-095..D-101). Nothing in here is on that path yet; the copy is what
puts it there. Keeping the original alongside is the point of the folder: the
second and third clip out of a pack are usually wanted a month later, and the
one thing a pack costs us is the ability to re-fetch — Mixamo names every
exported take `mixamo.com` internally, so a file's only identity is its name.

`loose/` is the same idea for a clip downloaded one at a time that has no role
assigned yet.

Screened on arrival, which is the first step of the route in BOG-84: every file
here carries an animation and no mesh, and none is Mixamo's one-frame dud (the
208,720-byte export that D-096 met five times and D-125 fourteen).
