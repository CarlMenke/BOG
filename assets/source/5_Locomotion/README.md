# 5_Locomotion — the set that stops the feet skating sideways

**Strafe left**, **strafe right** and **run backward**, plus their walk
equivalents. Running sideways at full speed currently plays a *forward* run
cycle, which is the most visible animation fault a third-person game can have.

Each of these needs its authored speed measured, the way `AUTHORED_RUN = 4.314`
was: give the clip an `authored_as="AUTHORED_..."` in `PACKS` and the build
prints the number to put in `gub.gd`. A locomotion clip that names no constant
is a clip whose speed nobody will ever match, and its feet will skate.

**Six of the seven files here are declared and built** (D-066). What follows is
the record of how they were chosen and what they cost; the numbers below are
printed by `bash tools/build_gub.sh` on every run.

## What is in here

Seven clips, all With Skin, all 0.0 from `GUB_2/Idle.fbx`'s bind pose. Measured
on the finished 1.80 m rig by the build itself:

| file | clip | speed | bearing | hip height | torso pitch |
|---|---|---:|---:|---:|---:|
| `LeftStrafe.fbx` | `StrafeLeft` | 3.250 m/s | +27.5° | 0.645 m | 8.7° |
| `RightStrafe.fbx` | `StrafeRight` | 3.250 m/s | −37.4° | 0.645 m | 8.7° |
| `LeftStrafeWalking.fbx` | `StrafeWalkLeft` | 1.245 m/s | +35.3° | 0.665 m | 5.5° |
| `RightStrafeWalking.fbx` | `StrafeWalkRight` | 1.245 m/s | −46.5° | 0.664 m | 5.6° |
| `RunningBackward.fbx` | `RunBack` | 2.278 m/s | +171.7° | 0.647 m | 7.1° |
| `WalkingBackward.fbx` | `WalkBack` | 0.871 m/s | +173.1° | 0.683 m | 15.3° |
| `StandingRunLeft.fbx` | *not declared* | 2.580 m/s | +76.5° | 0.646 m | 8.4° |

*Bearing* is where the clip travels in degrees off the body's own forward,
positive to its left, **after** the build has aligned it — so it is where the
blend point belongs. *Hip height* is the pelvis above the floor and *torso
pitch* is the Hips→Neck line off vertical, both averaged over the clip.

For comparison `GUB_2/Walk.fbx` measures 0.657 m and **4.1°**, and
`GUB_2/Run.fbx` 0.575 m and **45.1°** — the sprint is a deep lean and it is the
one clip in the whole set that is nothing like the others. The two families
agree about carriage far better than the plan expected; see D-066.

## Two families, and one of them is barely a strafe

`LeftStrafe`/`RightStrafe` and their walks are Mixamo's basic **Locomotion Pack**
(lowercase names). `StandingRunLeft` is the **`Standing *`** family, from the
Magic/Longbow locomotion packs, which are authored for a torso that holds its
facing while the legs go elsewhere.

That difference is measurable and it is large — and **which line you measure it
off changes the answer by more than twenty degrees**, which is the trap this pack
had in it. Travel in degrees off the body's own forward:

| clip | by the hip line | by the chest line |
|---|---:|---:|
| `GUB_2/Run.fbx` | −10.2° | −5.7° |
| `LeftStrafe.fbx` | **+8.6°** | **+27.5°** |
| `StandingRunLeft.fbx` | +50.8° | **+76.5°** |

`build_gub.py` aligns every clip by its **hip line**, because that is the one
measurement that stays put while the arms and torso animate. In a sidestep it is
the pelvis that moves: it turns *into* the step and the chest does not. So
aligning `LeftStrafe` by its pelvis drags the travel round with it and leaves the
game a clip that moves 8.6° off forward — a Gub jogging very slightly to one
side, where the 28° this pack was chosen on is the **shoulder** figure.

The four strafes are therefore declared with `face=CHEST_JOINTS` and nothing else
is (D-066). `LeftStrafe` is a shallow forward-left **diagonal** even so, and
`StandingRunLeft` is very nearly a true 90° lateral — they are **alternates for
the same blend point**, and the lateral one is a set of one. There is no
`Standing Run Right`, no `Standing Walk Left`, no `Standing Walk Right` With
Skin, and putting one `Standing *` clip into a lowercase set would move the
family boundary *inside* the strafe axis, which is worse than having it between
forward and sideways.

**The four lowercase diagonals were taken**, and what that costs is measured:
running sideways plants its feet 0.93 of body speed better than it did and no
better than that, because a pole that means 90° is being served by a clip that
means 37. The three downloads above are what would close it, and they are the one
thing D-066 leaves open.

## Backward arrived, and it is the best half of this pack

`RunningBackward.fbx` and `WalkingBackward.fbx` were the two files this README
used to list as missing, and they turned out to be the clips that do the most
good. Both travel within 8° of straight backward — nothing has to be blended to
get there — so a backpedal now plants its feet as well as a forward walk does:
1.03 of body speed of skate down to **0.16** at walking pace, 0.83 down to
**0.23** at a run.

The one thing to know about them is the **playback rate**. `WalkBack` is authored
at 0.871 m/s and has to carry a 2.3 m/s backpedal, which is **2.64x** — the
fastest of any cycle in the game. Its feet are planted, which is what the ratio
is for, but a Gub backing away at walking pace is visibly scampering. If that
ever needs to come down the lever is a backward speed penalty in
`Gub.target_speed`, not a number in the animator.

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
its clip name, whether it loops, its alignment reference, and — for anything that
moves sideways — `CHEST_JOINTS` as its `face`. `StandingRunLeft.fbx` is the file
in here that is deliberately *not* named, and the build reports it every run,
which is exactly right.

    bash tools/build_gub.sh -- --list-packs   # what the pipeline thinks is here
    bash tools/build_gub.sh                   # rebuild art/generated/gub.glb

Files sitting here that `PACKS` does not name are reported by both, which is
what "I downloaded the clips and nothing changed" looks like from the inside.
