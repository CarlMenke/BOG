# 4_Elder_Suite — a cast that is over before you can read it

A **short one-handed cast or point**. The Elder's bolt leaves 0.2 s after the
click, so the whole clip is about that long; anything with a wind-up will be
played fast enough to look silly.

This existed because the Elder borrowed the spear's own throw clip, which worked
only while that clip was a baseball throw. It stopped being one in D-063 and the
Elder stopped borrowing it in D-064.

## What is in here

One clip, With Skin, 0.0 from `GUB_2/Idle.fbx`'s bind pose:

| file | frames | length | travel | peak | what it is |
|---|---:|---:|---:|---:|---|
| `Standing1HMagicAttack1.fbx` | 138 | 2.283 s | 0.000 m | 0.124 m | A one-handed cast, thrown forward. In place: the hips end exactly where they started and never get further than 0.124 m away, so nothing here has to be locked. |

Not an alternate — it is the only candidate, and the rest of Mixamo's *Lite Magic
Pack* is in `_rejected/` with its measurements, if a second opinion is ever
wanted.

Note the length against the brief above. 2.283 s is eleven times the 0.2 s the
bolt takes to leave, so what the game plays is a **window** of this clip at a
derived rate, not the clip — exactly what `windup_rate()` already did with the
spear's throw, only against a clip that is a cast rather than a throw.

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

## It is declared, and here is what was done with it

`Standing1HMagicAttack1.fbx` is `Cast` in `PACKS` since **D-064**, aligned on
0.467. `bog_animator.gd` plays **0.467-1.600** of it and the bolt leaves at
**0.983** — the frame the hand stops going forward, which on this clip is
neither its peak speed (0.783) nor its furthest reach (1.333, in the recovery).
At the default `lightning_delay` that window is played at 2.58x.

Anything else dropped in here still does nothing on its own. A folder somebody
dropped files into is not a promise; a line in `PACKS` is. Add a `Clip(...)` for
each new file in this pack's entry in `tools/build_bog.py`, with its clip name,
whether it loops, and its alignment reference. Until then the file is skipped
and the build says so.

    bash tools/build_bog.sh -- --list-packs   # what the pipeline thinks is here
    bash tools/build_bog.sh                   # rebuild art/generated/bog.glb

Files sitting here that `PACKS` does not name are reported by both, which is
what "I downloaded the clips and nothing changed" looks like from the inside.
