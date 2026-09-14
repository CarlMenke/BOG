# 4_Elder_Suite — a cast that is over before you can read it

A **short one-handed cast or point**. The Elder's bolt leaves 0.2 s after the
click, so the whole clip is about that long; anything with a wind-up will be
played fast enough to look silly.

This exists because the Elder currently borrows the spear's own throw clip and
plays it at 5.67x, which only works while that clip is a baseball throw. A
javelin plant-and-extend at 5.67x will not read as anything.

## What is in here

One clip, With Skin, 0.0 from `GUB_2/Idle.fbx`'s bind pose:

| file | frames | length | travel | peak | what it is |
|---|---:|---:|---:|---:|---|
| `Standing1HMagicAttack1.fbx` | 138 | 2.283 s | 0.000 m | 0.124 m | A one-handed cast, thrown forward. In place: the hips end exactly where they started and never get further than 0.124 m away, so nothing here has to be locked. |

Not an alternate — it is the only candidate, and the rest of Mixamo's *Lite Magic
Pack* is in `_rejected/` with its measurements, if a second opinion is ever
wanted.

Note the length against the brief above. 2.283 s is eleven times the 0.2 s the
bolt takes to leave, so step 5's job is to pick a **window** and a rate off this
clip, not to play it — exactly what `windup_rate()` already does with the
spear's throw, only against a clip that is a cast rather than a throw.

## What every clip in every pack has to be

The same upload. These clips land on **one** skeleton, so each one has to come
off *the Gub as uploaded to Mixamo*, in that same Adobe account, downloaded
again with this animation applied to it. A stock Mixamo character, a CC0 pack
from anywhere else, or even the same Gub uploaded a second time gives a
different vertex count or a bind pose a fraction out, and `build_gub.py` refuses
it on the first import (`assert_same_character`) rather than shipping a subtly
broken skin in one clip. There is no retarget stage here to bridge that gap —
deliberately, because the five things this pipeline does that Godot's
import-time retargeter cannot are the reason it exists at all.

Export settings, matching `GUB_2/`: **FBX Binary**, **With Skin**, **60 fps**,
**no keyframe reduction**, one animation per file. **One animation at a time,
from that clip's own page** — the multi-select Download button in *My Assets*
ships the skin in one file of the batch and nothing in the rest, which is what
put 105 files in `_rejected/`.

## Dropping files in here does nothing on its own

A folder somebody dropped files into is not a promise; a line in `PACKS` is. Add
a `Clip(...)` for each file in this pack's entry in `tools/build_gub.py`, with
its clip name, whether it loops, and its alignment reference. Until then the
pack is skipped and the build says so.

    bash tools/build_gub.sh -- --list-packs   # what the pipeline thinks is here
    bash tools/build_gub.sh                   # rebuild art/generated/gub.glb

Files sitting here that `PACKS` does not name are reported by both, which is
what "I downloaded the clips and nothing changed" looks like from the inside.
