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
| `StandingDrawArrow.fbx` | 62 | 1.017 s | 0.039 m | Nock and draw. **The clip the charge is indexed into** (D-065), across its 0.567-1.017 window — the pull alone. |
| `StandingAimOverdraw.fbx` | 227 | 3.767 s | 0.021 m | The held aim, and the longest clip here by far. It was expected to be the clip the draw is indexed into and it **cannot be** — see below. Not declared in `PACKS`. |
| `StandingAimRecoil.fbx` | 42 | 0.683 s | 0.024 m | The release, and the shortest — which is right, because the release is the only part of this that is on a clock. |
| `StandingDisarmBow.fbx` | 66 | 1.083 s | 0.085 m | Bow away. This is what a letter hold plays when it disarms the bow. |

None of these are alternates; there is one of each role. There is **no dry-fire
or recover** in the set — the brief asked for one "ideally", and `AimRecoil` does
in fact cover it: a draw cancelled by a letter hold plays the loose with nothing
on the string, which is a dry-fire for free (D-065).

## What was measured, and what it changed (D-065)

Two of the five are declared in `build_bog.py`'s `PACKS`: `StandingDrawArrow` as
`Draw` and `StandingAimRecoil` as `Loose`. The other three are deliberately not,
and the first of them is the interesting one.

**`StandingAimOverdraw` is the hold, not the charge.** The table above used to
say it was the clip the draw indexes into, and so did step 6's brief. Measured
on the built asset with `tools/hand_track.gd`, it **opens fully drawn** — its
first frame is the pose `StandingDrawArrow` ends on — and the drawing hand then
creeps 0.116 m over 3.767 s. A charge indexed into it would be a bow at full
draw at charge zero, which is the one thing the tell must never show. What it
*is* is the held pose with a slow overdraw in it, and it is worth having the day
somebody minds that a Bog at full draw is perfectly still.

**The charge is `StandingDrawArrow`'s 0.567-1.017, the pull alone.** The drawing
hand comes down off the shoulder at over 4 m/s, arrives at the bow at 0.567 s
doing 0.29 m/s — the slowest frame between the reach and the pull — and then
draws back at a steady 0.95 m/s. 0.567 is the arrow meeting the string. The
0.567 s before it is a Bog taking an arrow out of a quiver, which is a lovely
flourish and cannot be in the charge: a bow is *carried*, so charge zero has to
be a nocked bow at brace.

**`StandingEquipBow` and `StandingDisarmBow` are not declared** because the bow
appears and disappears the way the spear does, as a visibility toggle off the
one gate in `BogCombat` — and an equip clip for the bow with none for the spear
would be two rules about the same hand.

## And the pose it is carried in (D-070)

`BowIdle.fbx` arrived after the four above and is a different kind of clip from
any of them: not an event with a window cut out of it, but a **pose**, looped,
whose legs nothing ever sees. It is built as `BowCarry` and played as an
upper-body layer over the whole locomotion plane — `UPPER_BODY_BONES` keeps its
spine and arms and throws its legs away — so a Bog carrying a bow stands like an
archer whether it is idling, walking, running or backpedalling, and there are not
four blend spaces to keep in step.

It does not replace `HeldGear.CARRY_TILT`, which is the interesting half of what
this clip taught. A carry pose fixes the *arm*; the bow's grip is not a pose at
all but the equation D-065 solved against `Draw` so the string's V meets the
drawing fingers at every charge, and this clip's own hand does not know that
equation. Measured, the pose alone leaves a limb tip 0.032 m off the floor in
`Idle` — in the grass — and the pose with the tilt holds 0.251 m over all twelve
carried clips. The great sword's tilt *was* deleted, because its carry clip was
drawn around its own prop; see that pack's README and D-070.

## What every clip in every pack has to be

The same upload. These clips land on **one** skeleton, so each one has to come
off *the Bog as uploaded to Mixamo*, in that same Adobe account, downloaded
again with this animation applied to it. A stock Mixamo character, a CC0 pack
from anywhere else, or even the same Bog uploaded a second time gives a
different vertex count or a bind pose a fraction out, and `build_bog.py` refuses
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
a `Clip(...)` for each file in this pack's entry in `tools/build_bog.py`, with
its clip name, whether it loops, and its alignment reference. Until then the
pack is skipped and the build says so.

    bash tools/build_bog.sh -- --list-packs   # what the pipeline thinks is here
    bash tools/build_bog.sh                   # rebuild art/generated/bog.glb

Files sitting here that `PACKS` does not name are reported by both, which is
what "I downloaded the clips and nothing changed" looks like from the inside.
