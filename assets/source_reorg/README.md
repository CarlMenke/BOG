# source_reorg — the BOG's new source of truth

Raw source for the rebuilt character pipeline. Nothing in here is loaded by the
game; `.gdignore` keeps Godot out. The old `assets/source/` stays until the new
pipeline ships, then goes.

```
BOG.fbx          the body: the BOG sculpt as Mixamo auto-rigged it, downloaded once
                 as a T-pose with skin. 49 mixamorig bones, one mesh, one 4096² texture.
clips.json       the clip table: every animation the game wants, with its Mixamo id,
                 the file name it lands under, whether it is fetched in place, and
                 whether it loops. Several rows per role are candidates; the
                 preview pass picks one and the rest are deleted.
anims/           one animation-only .fbx per row of clips.json, fetched by
                 tools/mixamo_fetch.py. Never carries a mesh.
```

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

Add a row to `clips.json` (the Mixamo id is in the page URL on mixamo.com, or
give a `mixamo_query` and every search result comes down), run the fetch, move
the file. That is the whole procedure.

## Godot import facts (verified in a scratch project, 2026-09-16)

- Godot 4.7 reads `BOG.fbx` directly: 49 bones named `mixamorig_*` (the colon
  becomes an underscore), one skinned mesh of 15 872 vertices, the embedded
  texture, and one `mixamo_com` animation that is the T-pose.
- Every animation-only clip imports with the identical 49-bone list, and a clip
  played on the body's skeleton lands every bone within 0.1 mm of where it
  lands on the clip's own skeleton. Retargeting by bone name is exact; no
  bone map is needed for the BOG itself.
- The files are in Mixamo's centimetre scale: at the default `root_scale` the
  body is 1 cm tall and the importer's animation optimizer collapses every hip
  position track to a single key, killing the bob. `nodes/root_scale = 100`
  makes the body 1.00 unit tall with all keys intact; 180 would make it 1.80 m.
  Verified with `animation/remove_immutable_tracks = false`.
- Five catalogue ids exported as a single frame (Walking, two Running Forward,
  Sliding, Holding Bow); they were dropped from the table and the slide is
  fetched by search instead.
