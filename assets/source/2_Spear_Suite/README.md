# 2_Spear_Suite — the throw you can see leave the hand

A **javelin-style throw**: a plant and a full extension at the release, so the
frame the spear leaves the fist does not look like every frame around it.
Mixamo's "Throw Javelin" family. Grab two or three candidates — the step that
uses them measures each with `tools/hand_track.gd` and picks the window whose
start reads as a wind-up and whose release reads as an extension.

The clip this replaces, `GUB_2/Throw.fbx`, is a baseball-style over-shoulder
throw 3.83 s long whose release sits at 1.633 s. It is not being deleted; the
point is a release with a silhouette of its own.

## What is in here

Both files carry skin and both sit 0.0 from `GUB_2/Idle.fbx`'s bind pose.
Measured by `tools/audit_source_packs.py`:

| file | frames | length | travel | peak | what it is |
|---|---:|---:|---:|---:|---|
| `SpearThrow.fbx` | 231 | 3.833 s | 0.858 m | 1.227 m | **The clip already shipping.** It measures identically to `GUB_2/Throw.fbx` — same Mixamo animation, downloaded a second time — so it is the baseball over-shoulder throw, here as the control the other one is judged against rather than as a new candidate. |
| `SpearThrowLonger.fbx` | 171 | 2.833 s | 2.842 m | 2.842 m | A javelin throw **with a run-up**: the hips cover 2.84 m over the clip at 1.003 m/s. That travel is real motion, not root drift, and the window step 4 cuts has to start after the approach or the Gub will slide into its own throw. |

**`SpearThrowLonger` is the one, and it is declared** (D-063). It is not the
javelin plant-and-extend the brief above asked for — it is an overhand delivery
with a run-up — but it does the thing the brief wanted a javelin for: the arm
goes up over the head with the shaft raised, and one sixth of a second later the
hand is empty and out in front. `PACKS` takes 1.067-1.900 s of it under the name
`Throw`, which is the delivery with the approach cut off the front, and plays it
at 1.0 — its authored speed, because that window is exactly the half second the
release was asked to land at.

The run-up does not survive and does not need to: `lock_root_motion` clamps the
2.842 m away, the window opens after it, and the throw is a layer filtered to
the upper body, so the clip's own forward pitch of the hips never reaches the
game at all. The Gub throws standing upright from wherever it is.

`SpearThrow.fbx` stays here undeclared, as the control: it measures identically
to the retired `GUB_2/Throw.fbx`, so it is the clip that was replaced, not a
second candidate. The build reports it as a file `PACKS` does not name, which is
what it is.

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
