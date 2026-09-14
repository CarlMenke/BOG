# 7_GreatSword_Suite — one heavy swing, and the draw that precedes it

A **heavy melee one-shot**: the spear's role at melee range, traded from throw to
reach. Slow windup, big damage, no defence. Explicitly **not** blocking, combos
or impact reactions — Mixamo's *Great Sword Pack* carries all three and all three
are in `_rejected/` on purpose rather than by accident, because "we decided
against it" and "we threw it away" are different states and only one of them is
reversible.

The mesh is `assets/source/GreatSword.glb`, which goes through
`tools/decimate_assets.py` like every other prop and lands as
`art/generated/greatsword.glb`. The animations here and the mesh there are
separate pipelines and neither knows about the other.

## What is in here

Two clips, both With Skin, both 0.0 from `GUB_2/Idle.fbx`'s bind pose. Measured
by `tools/audit_source_packs.py`, plus the body's yaw — measured the way
`build_gub.py` measures facing, as the yaw of the left-hip→right-hip line, not
off the Hips bone's own quaternion, which carries the rig's rest orientation and
whose "yaw" is not the body's. That column is the one this pack lives or dies on:

| file | frames | length | travel | peak | body yaw |
|---|---:|---:|---:|---:|---:|
| `DrawAGreatSword1.fbx` | 31 | 0.500 s | 0.082 m | 0.082 m | −27° |
| `GreatSwordHighSpinAttack.fbx` | 113 | 1.867 s | **1.712 m** | 1.713 m | **+365° net, 415° peak** |

`DrawAGreatSword1` is the sword coming out: half a second, effectively in place,
8 cm of hip drift and 27° of turn as the body opens to bring the blade across.
There is a second take (`draw a great sword 2`) in `_rejected/` if this one reads
badly.

`GreatSwordHighSpinAttack` is **not an in-place swing**, and step 9 has to be
built around that rather than surprised by it. Read the two numbers together:
the body travels 1.712 m over the clip *and* turns through **a whole revolution
and five degrees**, overshooting to 415° mid-swing before settling back. That is
a spinning advance — the Gub turns away from the target, comes round, and
arrives 1.7 m from where it started, facing roughly where it began.

`lock_root_motion` will take the 1.7 m of translation away, because it locks the
two horizontal axes to their first key. It does **nothing** to yaw, and
`align_facing` only rotates the whole clip by one constant so that its reference
moment points where the rest pose points. The spin survives into the game
intact.

The two things that follow from that:

- the hit resolves at a **release moment measured off the clip**, and the body's
  facing at that moment is nowhere near its facing at the click, so the sweep has
  to be taken from the animated skeleton rather than from the Gub's own basis;
- the 1.7 m the clip was authored to cover is motion the physics body now has to
  produce or refuse, and either answer has to be deliberate. A Gub rooted in
  place through a swing drawn with an advance will have its feet skate for the
  whole 1.867 s.

The in-place alternative measures **1.183 s, 0.092 m peak, 0.0° net turn and
only 37° of swing** — that is `great sword attack` in `_rejected/`, and it is the
fallback if the spin turns out to be unplayable rather than merely demanding. It
would have to be re-downloaded With Skin; the measurement above is off the
skinless file, where the curves are intact and only the rest pose they are
relative to is wrong, so the length and the turn are trustworthy and the pose is
not.

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
