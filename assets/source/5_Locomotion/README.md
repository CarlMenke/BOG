# 5_Locomotion — the set that stops the feet skating sideways

**Strafe left**, **strafe right** and **run backward**, plus their walk
equivalents. Running sideways at full speed currently plays a *forward* run
cycle, which is the most visible animation fault a third-person game can have.

Each of these needs its authored speed measured, the way `AUTHORED_RUN = 4.314`
was: give the clip an `authored_as="AUTHORED_..."` in `PACKS` and the build
prints the number to put in `gub.gd`. A locomotion clip that names no constant
is a clip whose speed nobody will ever match, and its feet will skate.

## What is in here

Five clips, all With Skin, all 0.0 from `GUB_2/Idle.fbx`'s bind pose. Measured
by `tools/audit_source_packs.py`, with the posture columns measured alongside
because of the mixed-family warning below:

| file | frames | length | travel | speed | hip height | torso pitch |
|---|---:|---:|---:|---:|---:|---:|
| `LeftStrafe.fbx` | 41 | 0.667 s | 2.167 m | 3.250 m/s | 0.628 m | 8.7° |
| `RightStrafe.fbx` | 41 | 0.667 s | 2.167 m | 3.250 m/s | 0.630 m | 8.7° |
| `LeftStrafeWalking.fbx` | 63 | 1.033 s | 1.286 m | 1.245 m/s | 0.632 m | 5.5° |
| `RightStrafeWalking.fbx` | 63 | 1.033 s | 1.286 m | 1.245 m/s | 0.631 m | 5.6° |
| `StandingRunLeft.fbx` | 46 | 0.750 s | 1.935 m | 2.580 m/s | 0.646 m | 8.4° |

*Hip height* is the hips above the lowest joint in the same frame, averaged over
the clip; *torso pitch* is the Hips→Neck line off vertical, averaged the same
way. For comparison `GUB_2/Run.fbx` measures **0.569 m** and **45.1°** — it is a
deep-lean sprint, and neither family here leans anything like it.

## Two families, and one of them is barely a strafe

`LeftStrafe`/`RightStrafe` and their walks are Mixamo's basic **Locomotion Pack**
(lowercase names). `StandingRunLeft` is the **`Standing *`** family, from the
Magic/Longbow locomotion packs, which are authored for a torso that holds its
facing while the legs go elsewhere.

That difference is measurable and it is large. Taking the angle between where the
body faces and where it actually travels, off three independent measures (the
shoulder line, the foot direction, and the hip line `build_gub.py` itself uses
for facing):

| clip | shoulders | feet | hip line |
|---|---:|---:|---:|
| `GUB_2/Run.fbx` | 6° | 3° | — (the reference) |
| `LeftStrafe.fbx` | 28° | 21° | 19° |
| `StandingRunLeft.fbx` | **77°** | **46°** | **61°** |

So `LeftStrafe` is a shallow forward-left **diagonal**, not a sideways move, and
`StandingRunLeft` is very nearly a true 90° lateral. They are **alternates for
the same blend point** and the choice is not a matter of taste: a blend space
whose lateral pole is only 28° off forward has a hole in it where running
sideways should be.

The catch is that the lateral one is a set of one. There is no
`Standing Run Right`, no `Standing Walk Left`, no `Standing Walk Right` With
Skin, and putting one `Standing *` clip into a lowercase set would move the
family boundary *inside* the strafe axis, which is worse than having it between
forward and sideways. Whichever way step 8 goes, it goes there with four clips
from one family or with three more downloads.

## Still missing

**A neutral run backward and a neutral walk backward.** Nothing in this folder
moves the Gub away from where it is facing, at either speed. `_rejected/` has
`Standing Run Back` (0.617 s, 1.482 m, 2.404 m/s) and `Standing Walk Back`
(1.200 s, 1.046 m, 0.871 m/s) measured in its manifest, and both need
re-downloading With Skin before step 8 can close the space.

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
