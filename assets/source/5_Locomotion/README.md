# 5_Locomotion — the set that stops the feet skating sideways

**Strafe left**, **strafe right** and **run backward**, plus their walk
equivalents. Running sideways at full speed used to play a *forward* run cycle,
which is the most visible animation fault a third-person game can have; it is now
a lateral and its own reflection, and the planted foot slides 0.43 of body speed
where it slid 1.36.

Each of these needs its authored speed measured, the way `AUTHORED_RUN = 4.314`
was: give the clip an `authored_as="AUTHORED_..."` in `PACKS` and the build
prints the number to put in `gub.gd`. A locomotion clip that names no constant
is a clip whose speed nobody will ever match, and its feet will skate.

**Five of the eleven files here are declared**, and a sixth clip is *built from*
one of them rather than downloaded (D-071). What follows is the record of how
they were chosen and what they cost; the numbers below are printed by `bash
tools/build_gub.sh` on every run.

## What is in here

Eleven files, all With Skin, all 0.0 from `GUB_2/Idle.fbx`'s bind pose. Measured
on the finished 1.80 m rig by the build itself:

| file | clip | speed | bearing | hip height | torso pitch |
|---|---|---:|---:|---:|---:|
| `StandingRunLeft.fbx` | `StrafeLeft` | 2.580 m/s | +76.5° | 0.658 m | 8.4° |
| *(reflection of the above)* | `StrafeRight` | 2.580 m/s | −75.3° | 0.658 m | 6.4° |
| `LeftStrafeWalking.fbx` | `StrafeWalkLeft` | 1.245 m/s | +35.3° | 0.665 m | 5.5° |
| `RightStrafeWalking.fbx` | `StrafeWalkRight` | 1.245 m/s | −46.5° | 0.664 m | 5.6° |
| `RunningBackward.fbx` | `RunBack` | 2.278 m/s | +171.7° | 0.647 m | 7.1° |
| `WalkingBackward.fbx` | `WalkBack` | 0.871 m/s | +173.1° | 0.683 m | 15.3° |
| `LeftStrafe.fbx` | *not declared* | 3.250 m/s | +27.5° | 0.645 m | 8.7° |
| `RightStrafe.fbx` | *not declared* | 3.250 m/s | −37.4° | 0.645 m | 8.7° |
| `StandingRunRight.fbx` | *not declared* | 2.385 m/s | −45.9° | 0.619 m | 28.0° |
| `StandingWalkLeft.fbx` | *not declared* | 1.072 m/s | +126.5° | 0.600 m | 19.7° |
| `StandingWalkRight.fbx` | *not declared* | 1.148 m/s | −46.3° | 0.613 m | 12.4° |

*Bearing* is where the clip travels in degrees off the body's own forward,
positive to its left, **after** the build has aligned it — so it is where the
blend point belongs. *Hip height* is the pelvis above the floor and *torso
pitch* is the Hips→Neck line off vertical, both averaged over the clip.

`StrafeRight` has no file because it has no file to have: it is `StrafeLeft`
reflected in the rig's own sagittal plane by `mirror_action`, which is why its
speed and hip height match to four decimals and its bearing to 1.2°. The next
section is why that is the only way this pack gets a right-hand strafe at all.

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
is (D-066), and that reference is **load-bearing rather than tidy**: `GubAim`
turns `Spine`, `Spine1` and `Spine2` by a constant measured off the draw clip,
and `Spine` sits below `UPPER_BODY_BONES`, so whatever yaw the locomotion clip
puts on it goes straight into where the bow points. Read off the `Head` instead,
every strafe in every pack here is already a true lateral (`LeftStrafe` measures
+83.0° by the head against +27.5 by the chest) and the feet would plant almost
perfectly — and a strafing archer would shoot 63° wide. The chest is what the aim
rides on, so the chest is what a strafe has to be square to.

## Mixamo's strafes are handed, and that is why one of these is built

This is the thing D-066 did not know and three downloads were spent finding out
(D-071). It is the most useful fact in this folder.

Travel off the chest line, positive to the character's left, measured across all
three locomotion packs this project has ever downloaded — the two rejected ones
read on their own broken rigs by `tools/audit_source_packs.py`. Eight files exist
in this tree both skinned and skinless, and all eight read the same to 0.1°,
which is what makes the rejected rows believable:

| pack | run left | run right | walk left | walk right |
|---|---:|---:|---:|---:|
| Locomotion (lowercase) | +27.5° | −37.4° | +35.3° | −46.5° |
| Longbow Locomotion | +116.0° | −45.8° | +126.5° | −46.3° |
| Magic Locomotion | **+76.5°** | −37.6° | **+94.4°** | −38.8° |

**Every right strafe in every pack is a −37 to −47 degree diagonal**, while its
left twin ranges from +27 to +126. These families are authored around a character
holding its chest turned to its own right — a bow arm, a casting hand, the thing
that makes them aim clips at all. Stepping right barely turns that torso;
stepping left turns it a long way.

So there is **no right-hand strafe to download**, at any price, from any pack.
The only symmetric pair this rig can be given is a left strafe and its own
reflection, and `mirror_action` is what makes one. `StandingRunLeft.fbx` at
+76.5° is the best left strafe on disk and it is now the run-left pole;
`StrafeRight` is its mirror.

The three files `StandingRunRight.fbx`, `StandingWalkLeft.fbx` and
`StandingWalkRight.fbx` are the three downloads D-066 asked for. They are the
**Longbow** pack's clips rather than the Magic pack's that `StandingRunLeft.fbx`
came from — frame counts and speeds identify them exactly in
`_rejected/MANIFEST.md` — and they stay on disk undeclared. Declaring them was
tried and measured: running left plants at 0.30 of body speed and running right
at 0.84, five of the sixteen legs get worse, and the gate's `mirror` check fails
at 0.54. Re-downloading them from the *right* pack would not have helped either,
which is what the table above is for.

**What the lowercase walk pair still costs** is measured: walking sideways plants
at 0.80 of body speed, unchanged by D-071, because the walk poles are still those
diagonals. Running sideways went from 0.98 and 0.93 to **0.43 and 0.30** when the
run poles became a lateral and its reflection.

## The one download that would finish this

**`Standing Walk Left`, from the Magic Locomotion Pack, With Skin, one clip from
its own page.** Not the Longbow one already here.

It measures **+94.4°** off its chest — a true lateral, in the same family as the
run pole above it. Mirrored the way `StandingRunLeft` is, it is *both* walk poles:
symmetric, same authoring family, and the first thing that would move walking
sideways off 0.80.

`Standing Walk Right` is **not** on that list and must not be. It measures −38.8°,
which is the handedness this README is about.

That one file also flips the blend-space position rule — see `_body_relative` in
`gub_animator.gd`, which carries the derivation — and widens
`STRAFE_SIDEWAYS_LIMIT` in `combat_range.gd`, which sits at 0.85 only because the
walk legs are still where D-066 left them.

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
moves sideways — `CHEST_JOINTS` as its `face`. Five files in here are deliberately
*not* named, for the reasons above, and the build reports all five every run,
which is exactly right.

**Measure before you declare.** A sideways clip's bearing is the whole of whether
it belongs at a pole, and it is not knowable from the filename — that is the
lesson of the table two sections up, where four files with mirror-image names
measure +76.5, −45.9, +126.5 and −46.3. `tools/preview_clips.sh` will draw any
file in here with a floor compass under it without declaring anything, and the
build prints the bearing of everything it does declare.

    bash tools/build_gub.sh -- --list-packs   # what the pipeline thinks is here
    bash tools/build_gub.sh                   # rebuild art/generated/gub.glb

Files sitting here that `PACKS` does not name are reported by both, which is
what "I downloaded the clips and nothing changed" looks like from the inside.
