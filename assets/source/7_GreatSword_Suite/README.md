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

**One of the three files is declared** — `GreatSwordHighSpinAttack.fbx`, as
`Swing` — and the other two are deliberately not. See D-068; the short versions
are below the table.

Three clips, all With Skin, all 0.0 from `GUB_2/Idle.fbx`'s bind pose. Measured
by `tools/audit_source_packs.py`, plus the body's yaw — measured the way
`build_gub.py` measures facing, as the yaw of the left-hip→right-hip line, not
off the Hips bone's own quaternion, which carries the rig's rest orientation and
whose "yaw" is not the body's. That column is the one this pack lives or dies on:

| file | frames | length | travel | peak | body yaw | declared |
|---|---:|---:|---:|---:|---:|:--:|
| `DrawAGreatSword1.fbx` | 31 | 0.500 s | 0.082 m | 0.082 m | −27° | no |
| `GreatSwordHighSpinAttack.fbx` | 113 | 1.867 s | **1.712 m** | 1.713 m | **+365° net, 415° peak** | **`Swing`** |
| `GreatSwordJumpAttack.fbx` | 131 | 2.167 s | 2.334 m | 2.334 m | +15° bearing | no |

`DrawAGreatSword1` is the sword coming out: half a second, effectively in place,
8 cm of hip drift and 27° of turn as the body opens to bring the blade across.
There is a second take (`draw a great sword 2`) in `_rejected/` if this one reads
badly. **It is not declared**, because the sword is not *carried*: it is in the
fists from the click to the end of the swing and gone otherwise (D-068), so there
is nothing for a draw clip to precede — and this pack has no sheathe to match it
with anyway. Declaring it would be `3_Bow_Suite/StandingEquipBow.fbx`'s mistake
one weapon along: an equip animation for one prop and none for the other three is
two rules about the same hand.

`GreatSwordJumpAttack` was downloaded for the airborne case and **is not
declared**, and the measurement is why. `build_gub.py`'s own airborne table gives
it a peak foot clearance of **0.130 m**, feet leaving at 0.712 s and back down at
0.860 — 0.148 s in the air, 13 cm up, with the hips rising 0.163 m. A Gub's real
jump is 1.69 m over about 0.70 s. It is a lunging chop with a skip in it, not an
aerial attack, and played while a body is actually airborne it would land, plant
and recover a metre and a half above the floor. It also travels 2.334 m over
2.167 s, so taking it would mean a second advance, a second release moment and a
second reach for one weapon.

What happens instead costs nothing: the swing is a **full-body** one-shot,
because a 365° body spin is not maskable, so it already replaces the air pose and
the airborne case gets the same release, the same reach and the same advance as
the grounded one.

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

The two things that follow from that, and what D-068 did about each:

- the hit resolves at a **release moment measured off the clip** — 1.067 s, the
  peak hand speed — and the body's facing at that moment is nowhere near its
  facing at the click. Measured in a running match through the bone attachment,
  the blade at the release is **55–66° off the Gub's own facing**, so the sweep is
  taken from `HeldGear.sword_blade()` (which reads the `BoneAttachment3D`, the
  only thing that sees the modifier stack — D-066) and never from `-basis.z`;
- the 1.7 m is **kept, by the physics body**. `lock_root_motion` still clamps the
  Hips — it has to, or the mesh walks away from the capsule it is standing on —
  and the clip declares an `advance_as`, which means the metres are not
  discarded: the build prints them as `Gub.SPIN_ADVANCE` and
  `Gub._handle_movement` drives the capsule through exactly that distance over
  exactly this clip's length, which is what keeps the feet planted.

The in-place alternative measures **1.183 s, 0.092 m peak, 0.0° net turn and
only 37° of swing** — that is `great sword attack` in `_rejected/`, and it is the
fallback if the spin turns out to be unplayable rather than merely demanding. It
would have to be re-downloaded With Skin; the measurement above is off the
skinless file, where the curves are intact and only the rest pose they are
relative to is wrong, so the length and the turn are trustworthy and the pose is
not.

## And the pose it is carried between swings in (D-070)

`GreatSwordIdle.fbx` arrived after the swing and is the clip D-069's closing note
asked for by name: *"a Mixamo shoulder-carry is the real answer."* It is built as
`SwordCarry` and played as an upper-body layer over the whole locomotion plane,
so a swordsman stands like one in every clip it walks around in.

**It deleted `HeldGear.SWORD_CARRY_TILT`.** D-069 rotated the swinging grip by
−62° to keep 2.11 m of blade out of the grass, because the grip was fitted to
`Swing` and hung off an `Idle` authored for empty fists: untilted, the point
reached 0.351 m *under* the floor through `Run`. This clip's fists were drawn
holding a great sword, so the grip solved against the swing is the grip the idle
is already gripping, and the worst end over twelve carried clips comes out at
+0.187 m with no tilt at all. The tilt would still help — it measures +0.350 m on
top of the pose — and it is gone anyway, because a tilt is a rotation *away from
where the clip's hands are drawn holding the thing*.

**The spear borrows this clip.** There is no spear idle anywhere on disk, and of
the three poses the build has, this is the only one that is a genuine two-handed
grip — both fists together in front at waist height, 0.22 m apart — which is what
lets a 1.24 m shaft lie flat **across** the body where no amount of hip pitch can
tilt it. See D-070 for the scoring and `Loadout.CARRY_CLIPS` for the table. A
spear idle of its own is one download and would close it.

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
