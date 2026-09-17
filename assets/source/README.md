# assets/source — the BOG's clips, and the table that says what they are

Raw source for the rebuilt character pipeline (D-095). Godot imports every file
in here — that is the pipeline — but the game never loads a clip scene: what it
loads is the products the import writes to `art/generated/`. The body itself is
`art/bog/BOG.fbx`, because that is the one raw file the game instances and
`assets/` is excluded from exported builds.

```
clips.json       the clip table, and the whole rule table (D-097): every animation
                 the game wants, with its Mixamo id, the file name it lands under,
                 whether it loops, which body line the import squares to the body's
                 forward (`face`: hips, chest or none) and its events in seconds
                 (`markers`). One row per role: D-096 chose each from the
                 candidates that were fetched, and deleted the rest.
anims/           one animation-only .fbx per row of clips.json, fetched by
                 tools/mixamo_fetch.py, each with the .import that
                 tools/clip_imports.sh writes. Never carries a mesh.
anims/VERIFIED.md   per-clip length, hips travel and bob, as measured on the
                 first import (at root_scale 100; the pipeline runs at 180).
props/ Rust/ Mushroom/ skins/   the raw folders the other pipelines read, each behind
                 its own .gdignore (D-101); skins/ holds the Tripo retexture .glb
                 downloads that tools/extract_skins.py turns into art/skins/ (D-108).
```

The body, `art/bog/BOG.fbx`, is the sculpt as Mixamo auto-rigged it, downloaded
once as a T-pose with skin: 49 `mixamorig` bones, one mesh, one 4096² texture.

## What the import does

Every clip's `.import` names `tools/import_clip.gd` as its post-import script.
For each clip it records the hips' travel (and so the authored speed) as
metadata, yaws the hips' keys so the line its `face` rule names is square to
the body's forward, locks the hips to the vertical axis so the physics body
does the moving, sets the loop mode and writes the markers from its row, saves
the clip to `art/generated/clips/<file>.res` and files it in the shared library
`art/generated/bog_clips.res` under its role.

    "$GODOT" --headless --path . --script tools/clip_measure.gd   # every clip as numbers
    "$GODOT" --headless --path . --script tools/clip_events.gd -- Throw   # where its events are

To place or move a marker: run `clip_events` for the clip, render the window
it proposes with `preview_bog` (`... out.png 30 Throw 0.6 1.1`), look, write
the time into the row, re-import.

    "$GODOT" --headless --path . --import                  # the build, ~10 s
    "$GODOT" --headless --path . --script tools/clip_check.gd   # the gate check
    "$GODOT" --path . --resolution 1600x700 --script tools/snapshot.gd -- \
        res://tools/preview_bog.tscn out.png 30 Walk        # the picture

## Fetching the clips

    python tools/mixamo_fetch.py

writes `build/mixamo_fetch.js` and copies it to the clipboard. In Chrome, logged
in at mixamo.com with the BOG as the selected character, press F12, Console,
paste, Enter, and allow multiple downloads when asked. One `.fbx` per row lands
in Downloads; move them into `anims/`. Pasting again resumes after a failure.

Settings baked into the script: FBX binary, without skin, 30 fps, no keyframe
reduction, travel kept. (`in_place` is false on every row on purpose: Mixamo's
in-place export does keep the hip bob, but a clip that still carries its travel
tells the import how fast it was authored, and the import strips the travel
anyway.) The script only fetches rows it has not fetched with those settings
before, so re-pasting after a table change fetches just the changed rows.

## Adding a clip later

1. Add a row to `clips.json` (the Mixamo id is in the page URL on mixamo.com,
   or give a `mixamo_query` and every search result comes down as
   `<file>-<Name>`).
2. `python tools/mixamo_fetch.py`, paste, move the file into `anims/`.
3. `bash tools/clip_imports.sh` writes its `.import`.
4. `"$GODOT" --headless --path . --import` builds it into the library.

## Godot import facts (verified in a scratch project, 2026-09-16, and again here)

- Godot 4.7 reads `BOG.fbx` directly: 49 bones named `mixamorig_*` (the colon
  becomes an underscore), one skinned mesh of 15 872 vertices, the embedded
  texture, and one `mixamo_com` animation that is the T-pose.
- Every animation-only clip imports with the identical 49-bone list, and a clip
  played on the body's skeleton lands every bone within 0.12 mm of where it
  lands on the clip's own skeleton. Retargeting by bone name is exact; no
  bone map is needed for the BOG itself.
- The files are in Mixamo's centimetre scale: at the default `root_scale` the
  body is 1 cm tall and the importer's animation optimizer collapses every hip
  position track to a single key, killing the bob. `nodes/root_scale = 180`
  makes the body 1.80 m tall with all keys intact, with
  `animation/remove_immutable_tracks = false`.
- Five catalogue ids exported as a single frame (Walking, two Running Forward,
  Sliding, Holding Bow); they were dropped from the table and the slide is
  fetched by search instead.
