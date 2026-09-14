# 6_Utility — everything that is not fighting or moving

A **drink** or **quaff**, for the heal potion: healing is channelled over about
two seconds standing still, so the clip wants to be readable as "busy" for that
long, and interruptible.

## What is in here

One clip, With Skin, 0.0 from `GUB_2/Idle.fbx`'s bind pose:

| file | frames | length | travel | peak | what it is |
|---|---:|---:|---:|---:|---|
| `Drinking.fbx` | 368 | 6.117 s | 0.000 m | 0.012 m | A drink, standing still. The most nearly motionless clip in the whole tree — the hips never get 12 mm from where they started. |

Not an alternate; it is the only one. 6.117 s is three times the two-second
channel, so step 7 cuts a window out of it rather than playing it, and the frame
the bottle reaches the mouth is the one to cut around.

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
