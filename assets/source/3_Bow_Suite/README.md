# 3_Bow_Suite — draw, hold, release

Mixamo's standing bow set: a **draw**, a **held aim loop**, a **release**, and
ideally a **dry-fire or recover**. The aim loop has to loop, because the draw is
a held pose indexed by how far the bow is drawn rather than a clip run on a
clock — a charge only the archer can see is not a tell.

## What is in here

Five clips, all With Skin, all 0.0 from `GUB_2/Idle.fbx`'s bind pose, and all of
them stand still — the largest peak hip displacement in the set is 0.085 m, so
none of them fights the locomotion underneath. Measured by
`tools/audit_source_packs.py`:

| file | frames | length | peak | what it is |
|---|---:|---:|---:|---|
| `StandingEquipBow.fbx` | 54 | 0.883 s | 0.059 m | Bow out — the transition into the carry pose. |
| `StandingDrawArrow.fbx` | 62 | 1.017 s | 0.039 m | Nock and draw. The front half of the charge. |
| `StandingAimOverdraw.fbx` | 227 | 3.767 s | 0.021 m | The held aim, and the longest clip here by far. This is the one the draw is **indexed into** rather than played: a charge is a pose picked by how far the string is back, the way `arc_time()` picks a jump pose by where the body is in its arc. |
| `StandingAimRecoil.fbx` | 42 | 0.683 s | 0.024 m | The release, and the shortest — which is right, because the release is the only part of this that is on a clock. |
| `StandingDisarmBow.fbx` | 66 | 1.083 s | 0.085 m | Bow away. This is what a letter hold plays when it disarms the bow. |

None of these are alternates; there is one of each role. There is **no dry-fire
or recover** in the set — the brief asked for one "ideally", and `AimRecoil` may
cover it by being played without an arrow spawned.

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
