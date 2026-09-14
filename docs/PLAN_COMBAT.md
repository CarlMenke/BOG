# Plan — health, the bow, and a spear you can see leave the hand

*Written 2026-09-14. This is an orchestration plan, not a design document: it
says what each step is for, what it may touch, what it must not touch, and how
we know it is done. **Every step's own planning is the step's job.** Each one
goes to a single `general-purpose` subagent on Opus at high reasoning effort,
which reads the code, writes its own plan, implements it, and comes back. The
orchestrator reviews, runs the gate, and decides.*

*Decision records D-001..D-061 exist on `main`. Gate is 63 checks, green.*

---

## The six decisions this plan is built on

Asked and answered before any of it was written down, so no step has to guess:

| | decision |
|---|---|
| **Healing** | The heal potion is carried stock, like a mushroom or a lure (D-032), and drinking it is **channelled** — about 2 s, standing still. Not instant on pickup: that makes standing on a fresh corpse the strongest play in the game and removes every decision from healing. |
| **Letter hold** | A letter hold disarms the **bow as well as the spear**. One rule, not two, and it keeps "empty hands means harmless" honest (D-035). |
| **Bow vs. Elder** | `LIGHTNING_RANGE` is **raised to match the bow's flat band**, so the Elder keeps owning the point-and-click range. See the note under step 6 — that constant is derived, not typed, and raising it invalidates the derivation. |
| **Damage curve** | Arrow damage is **weighted toward the end of the draw**. Most of the 20→80 arrives in the last third, so a snap shot is genuinely bad and a full draw is worth waiting for. |
| **Animation source** | **Mixamo first.** The Gub already is a Mixamo rig. Buy a pack only if Mixamo cannot produce a readable throw. |
| **Elder balance** | **Nothing comes down to compensate** for the longer bolt range. Ship it and playtest. |
| **Locomotion** | **One neutral set, with weapons layered over it by upper-body mask** — not per-weapon full-body locomotion. The stance packs that were downloaded (`longbow/`, `magic/`) are kept, but as **upper-body overlay sources**: a longbow walk's spine-up content is the bow carry pose, and its legs are not wanted. See step 8. |
| **Great sword** | A **heavy melee one-shot** — the spear's role at melee range. Slow windup, big damage, **no blocking, no combos, no impact reactions**. See step 9. |
| **Sword moves forward** | The spin **advances**, it is not clamped in place. The user's words: *"the melee can spin forward, not in place, to give it some more range."* So the physics body produces the clip's 1.712 m rather than `lock_root_motion` deleting it — the one clip in the project where that is true, and step 9 owns the exception. |
| **Attacking airborne** | **Every attack works in the air.** Layered attacks (spear, bow, drink) already do and need nothing: they are filtered to `Spine1` and up, so the legs keep the air-arc pose — the user's *"maybe the legs just don't walk"*, which is what already happens. The sword is the exception and **cannot** be a layer; a 365° body spin is not maskable, so it is a full-body state that replaces the air pose. There is no grounded check anywhere in `gub_combat.gd` today and none should be added. |
| **Potion colour** | The heal potion **stays purple**. There is no mana in this game for it to be confused with, and the ambiguity is only against other games' conventions. |
| **Forward locomotion** | **`GUB_2`'s existing `Run` and `Walk` stay.** The user likes the run and it is what the game is built on — aligned, measured, shipping. Step 8 adds only the directions that do not exist. See the mixed-family note in step 8. |
| **Editing clips** | **Every step may trim, window, cut and retime its clips freely** — the user's own words: *"you can trim and cut and speed up the animations as needed."* This is standing permission and it is what the graph already does (the throw is a 1.60 s window of a 3.83 s clip played at 1.6x). It is **not** permission to leave a clip and the code that reads it disagreeing: a window or a rate that moves must move `THROW_RELEASE_TIME` and its kin *by derivation*, never by retyping. That is the whole of D-025. |

---

## HOW YOU WORK

**Delegate implementation, keep decisions.** One `Agent` per step:
`subagent_type: general-purpose`, `model: opus`, **high** reasoning effort. The
step brief below is the whole of what it is told; it does its own reading and
its own planning.

**One at a time, except where this document says otherwise.** Wave 0's three
steps are explicitly fenced to disjoint files and may run together. Everything
after it is sequential, because it all lands in `gub_combat.gd`,
`gub_animator.gd`, `match_state.gd` and `docs/DECISIONS.md` — the exact overlap
that produced three agents all claiming D-040 in one day.

**The gate is the definition of done.** `bash tools/smoke_test.sh` — 63 checks
today. Run it after every step, before starting the next. A step that adds
behaviour worth asserting adds a check, and the count in `docs/STATUS.md` moves
with it (two places: the command comment near line 25 and the "passes, N of N"
sentence near line 29). Never start a step on a red tree.

**Decision numbers are claimed at commit time, never reserved.** Immediately
before writing a record, run
`grep -oE '^## D-0[0-9]+' docs/DECISIONS.md | tail -1`, take the next number,
and commit it with the code. Next free at the time of writing is **D-062**.

**Commit style.** Read the last few `git log` entries first. Titles are a
sentence with a clause; bodies explain the *why* and what was rejected, at
length.

---

## BEFORE WAVE 1 — the assets, which are yours to fetch

Steps 4 onward are gated on clips that do not exist yet, and they cannot be
downloaded by an agent. `build_gub.py:372` refuses to build unless every source
file shares a body — same vertex count, same bone list, same vertex groups,
bind poses agreeing within `1e-5`. The eight files in `assets/source/GUB_2/`
are *the Gub as uploaded to Mixamo*, exported eight times. New clips must come
from **that same uploaded character**, in that same Adobe account. A generic
Mixamo download, or a CC0 pack from anywhere else, fails that assertion on the
first import and would need a retarget stage this pipeline does not have.

Export settings, matching the existing eight: **FBX Binary**, **With Skin**,
**60 fps**, **no keyframe reduction**. One animation per file.

The shopping list, by the folder each belongs in (step 1 creates the folders):

- `2_Spear_Suite/` — a javelin-style throw with a **plant and full extension at
  the release**, which is the whole point of step 4. Mixamo's "Throw Javelin"
  family. Grab two or three candidates; step 4 measures them and picks.
- `3_Bow_Suite/` — draw, a held aim loop, release, and ideally a dry-fire or
  recover. Mixamo's standing bow set.
- `4_Elder_Suite/` — a fast one-handed cast or point. Short; the Elder's bolt
  leaves 0.2 s after the click.
- `5_Locomotion/` — strafe left, strafe right, run backward, and their walk
  equivalents. This is the set that fixes the feet skating sideways.
- `6_Utility/` — a drink or quaff, for the heal potion.

`BOW.glb`, `ARROW.glb` and `HEAL_POTION.glb` are already in `assets/source/`
and need nothing from you.

---

## WAVE 0 — three steps, in parallel, no assets needed

These three touch disjoint files and none of them needs a clip that does not
exist yet. **They may run together.** Fences are stated because they are what
makes that safe; a step that finds it needs a file outside its fence stops and
asks rather than reaching.

### Step 1 — Make the animation pipeline multi-pack

*Fence: `tools/build_gub.py`, `tools/build_gub.sh`, `assets/source/` folder
layout. Nothing under `scripts/`.*

`build_gub.py` builds one `gub.glb` from one folder and one `CLIPS` tuple
(`:152`, `:177`). It needs to build from **several** source folders, each with
its own per-clip rules, so that a spear pack, a bow pack and a locomotion pack
are separate things on disk that land on the one skeleton.

Why not Godot's `BoneMap` retargeting instead, which is the obvious suggestion:
this pipeline does five things the importer cannot — strips `mixamorig:`, scales
to 1.80 m and hand-fixes Blender's location-fcurve bug, locks root motion *and
reports the authored speed* (`AUTHORED_RUN = 4.314` comes from here and is what
stops the feet skating), applies a per-clip vertical rule with a floor check,
and aligns facing (D-008/D-029). None of that comes from a bone map. The
pipeline stays; only its shape changes.

Also decide and implement whether the output stays one `gub.glb` or becomes one
mesh plus animation-only `.glb`s loaded with `add_animation_library()`. The
Elder already proves a second file can bind to the same skeleton
(`build_elder.py`), so the pattern exists.

**The safety property that makes this step reviewable:** rebuilding from the
existing eight clips must reproduce today's asset — same clip names, same
authored speeds, same measurements in the log. Prove that before adding a
single new folder.

*Done when:* the existing build reproduces equivalent measurements, the folder
layout above exists with the spear/bow/elder/locomotion/utility packs declared
and empty, a missing pack is a clear error rather than a crash, and the gate is
still green.

### Step 2 — Health, damage, and the bars that show it

*Fence: `scripts/game/match_state.gd`, `scripts/game/match_config.gd`,
`scripts/player/gub.gd`, `scripts/player/nameplate.gd`, `scripts/ui/hud.gd`,
`scripts/items/spear_projectile.gd`. Nothing in `tools/build_*`, nothing in
`gub_animator.gd`.*

There is no health in this game today, and `report_kill` (`match_state.gd:709`)
is the single place a death is decided. It has exactly **four** call sites: the
void, the bolt's direct hit, the bolt's blast, and the spear.

The shape: introduce `report_damage(victim, attacker, amount, cause, point,
blow, bone)` as the one host-authoritative entry point, and make `report_kill`
its internal consequence. Every existing caller becomes a `report_damage` of
100. That keeps friendly fire, spawn protection, the Elder's invulnerability,
the ward flash and `note_attack` in one place, asked once — and it makes "the
spear always kills" a **number rather than a branch**, so no future lobby dial
can quietly break it. The Elder's rule becomes "damage to an Elder is zero",
which is the same rule it already is.

Bars belong on `nameplate.gd`, which already draws team-coloured names with a
through-walls rule for teammates and a distance fade for enemies (D-047) — same
node, same visibility rules, no new system. Your own health goes on the HUD.

**The thing this breaks that nobody expects:** `SpearProjectile._stick_in`
buries the shaft in the victim and hands it to a corpse, and `_glance_off`
exists only because the Elder created a "this hit did not kill" case that
nothing handled. A projectile that damages a Gub who lives has no corpse to be
adopted by, and there are about to be a lot of those. Solve it here, before the
bow arrives and needs it: a projectile should be able to stick in a **living**
victim and ride the skeleton, transferring to a ragdoll if one later arrives.
`Gub.embed_spear()` almost does this already; the gate requiring death is the
change. A Gub with three arrows in it and a short bar is the best read in the
game and it comes free.

*Done when:* a combat-range mode lands partial damage and asserts the victim
lives with the expected health, lands enough to kill and asserts a normal death
with a corpse and a feed line, asserts a spear is still one shot, asserts an
Elder takes zero and still flashes its ward, and asserts a respawn restores full
health. Health survives the wire — a remote Gub's bar matches the host's number.
Plus a decision record.

### Step 3 — Bow, arrow and potion through the prop pipeline

*Fence: `tools/decimate_assets.py`, `assets/source/`, `art/generated/`. Nothing
under `scripts/`.*

`ARROW.glb`, `BOW.glb` and `HEAL_POTION.glb` are in `assets/source/` and go
through `decimate_assets.py:75` (`TARGETS`) like every other prop. Pick budgets
by the same argument the existing table uses — how many can be on screen at
once. An arrow is the tightest case: one per bow plus every shaft in flight.

The bow also needs **a string**, which the source model does not have, and the
string has to move with the draw. Two ways: skin it to a small bone chain, or
give it a single "drawn" blend shape driven by the draw fraction. Recommend the
blend shape — one float, no second skeleton, and it is the same
index-by-a-continuous-value pattern the animator already prefers. Take the other
route only with a reason.

**The trap:** `fast_simplification` will destroy blend shapes. Decimate first,
then add the string and its shape key as a separate step — or keep the string
out of the decimated mesh entirely. Whichever, the built asset must be checked
to still carry a working shape key, in the build's own log.

*Done when:* all three appear in `art/generated/`, within budget, the bow's
drawn shape key survives the build and is verified in the log, and a preview
mode shows the string at rest and fully drawn. The gate is still green.

---

## WAVE 1 — sequential from here

### Step 4 — A spear you can see leave the hand, at 0.5 s

*Depends on: step 1 (pipeline), and the spear clips being in
`assets/source/2_Spear_Suite/`.*

Two asks that pull against each other, and the step exists to hold both.

Today: `Throw` is 3.83 s, the graph plays its 0.50–2.10 s window at 1.6x, and
the release sits at 1.633 s of clip — `(1.633 - 0.50) / 1.6 = 0.708 s` after the
click. That is the delay that feels wrong.

Getting to 0.5 s is nearly free: `GubAnimator.throw_rate_for_release()` already
exists and the Elder already uses it. **But speeding the current clip up makes
the tell worse, not better** — the complaint is that the release is not legible,
and playing an illegible motion 42% faster does not fix that.

**The candidate is `SpearThrowLonger`, and it is the only one.** `2_Spear_Suite/`
holds two files and they are not two candidates:

- `SpearThrow` tracks `GUB_2/Throw` at a **near-constant** 3 cm offset — mean
  0.0292 m, worst 0.0297 m over 24 samples of the right hand relative to the
  hips. A gap that barely varies is the same motion shifted by export, not a
  different animation. It is the baseball throw already shipping.
- `SpearThrowLonger` diverges by a mean of 0.226 m and a worst of 0.502 m. It is
  genuinely a different clip: 171 frames, 2.833 s.

**Its travel is not a problem, and an early reading that said otherwise was
wrong.** Measured off the Hips location fcurves and scaled the way this pipeline
scales them — a method validated against `Run` (1.9426 m / 4.317 m/s against the
recorded 1.9412 / 4.314) — `SpearThrowLonger` travels 2.892 m. But
**`GUB_2/Throw`, the clip in the game right now, travels 1.706 m**, and
`lock_root_motion` clamps every clip's horizontal travel to its first key. Travel
is the normal case here, not a fault.

What makes it promising is the shape of the release. Sampling the right hand's
speed relative to the hips, it builds to 2.44, **spikes to 5.00 at 1.600 s**, and
falls back to 1.62 by 1.700 — a sharp, isolated peak rather than the broad
plateau the current clip has between 1.60 and 1.68. A spike is what a visible
release is made of. Confirm that on the built clip with `tools/hand_track.gd`
before committing to it, since these numbers are in armature units off the raw
FBX and not the m/s the tracker reports.

So the clip is the fix and the timing rides along. The current `Throw` is a
baseball-style over-shoulder throw whose release frame looks like every frame
around it. A javelin plant-and-extend has a silhouette change *at* the release.
Measure the candidates with `tools/hand_track.gd` (it exists for exactly this
and its header says so), pick the window whose start is a recognisable wind-up
and whose release frame is a recognisable extension, then set the rate so that
release lands at 0.5 s.

**The indication must be the animation and the model only — no UI.** The user
was explicit. Two in-world tells already exist and should be checked before
anything is added: the spear physically leaves the hand on the release tick
(D-025 guarantees it), and `spear_trail.gd`. Both are in scope.

Keep the derivation honest. `THROW_RELEASE_TIME` is derived from the window and
the rate precisely so that moving either cannot leave the spear and the hand
disagreeing — that is the bug D-025 exists because of. Do not replace it with a
typed number.

*Done when:* the release is 0.5 s within a frame, measured by a harness rather
than asserted; the hand empties on the same tick the spear appears; a contact
sheet of the release window shows a pose a player can recognise; and a decision
record amends D-025's number and says why the clip changed rather than only the
rate.

### Step 5 — The Elder gets its own cast

*Depends on: step 4.*

Forced by step 4, not optional. `GubCombat.windup_rate()` plays **the spear's
own clip** at 5.67x to land the bolt at 0.2 s. That works today only because a
sped-up baseball throw still reads as a throw. A javelin plant-and-extend at
5.67x will not, and `THROW_RATE_MAX = 8.0` is the only thing between it and
absurdity.

Give the Elder its own short cast clip from `4_Elder_Suite/`, and decouple the
Elder's branch from the spear's clip while leaving the shared *windup and
release* machinery alone — that one release tick with two outcomes is what D-038
and D-025 exist to protect, and it must not be forked.

*Done when:* the bolt still leaves at `lightning_delay`, measured; the Elder's
arm has got there when it does; the spear's own timing is untouched; a decision
record explains why the shared clip stopped being shareable.

### Step 6 — The bow

*Depends on: steps 1, 2, 3 and the pattern from 4.*

Hold to draw, release to fire, longer draw shoots faster and harder. The
biggest step here, and it needs its own plan.

Four things that are not obvious and must be in that plan:

**The charge has to be visible to your opponent.** D-025's own words: *"a tell
only the thrower can see is not a tell."* So the draw is a held pose **indexed
by charge**, not run on a clock — architecturally the same move as `arc_time()`
in `gub_animator.gd`, which indexes the jump clips by where the body is in its
arc. That pattern is proven and the animator's header explains why it cannot
freeze. A continuous draw level has to replicate; the cheapest honest way is a
synced float on `Gub` alongside `sync_crouching` and `sync_sliding`, not a
serial with a local clock.

**The hand rule breaks.** `held_spear.gd` "owns the hand" and is the single
place that decides what is in the fist — shaft, letter card, or Elder crackle,
*never two*. A bow is two-handed. That rule becomes "never more than one **per
hand**", and it must stay a rule enforced in one place rather than becoming two
rules that can disagree. Per the decision above, a letter hold disarms the bow.

**The numbers.** Damage 20 → 80, weighted toward the end of the draw. Speed and
drop should make a snap shot genuinely bad and a full draw the flattest thing in
the game — roughly 18 m/s with heavy drop up to roughly 60 m/s with light drop,
against the spear's 42 m/s and 8 m/s². Those are starting points to be measured
and tuned, not values to type in. All of them belong in `MatchConfig` with lobby
dials **and in `_FIELDS`** — a field missing from `_FIELDS` is a setting the host
changes and nobody else ever sees.

**Raising `LIGHTNING_RANGE` is not a constant edit.** It is 28 because that is
where a flat spear throw stops being flat — 0.67 s of flight and 1.78 m of drop
over 28 m — and there is a long comment saying the Elder deliberately owns
exactly the band where the spear is point-and-click. Raising it to match the bow
invalidates that derivation. **Re-derive it from the bow's flat band**, and write
a record that *answers* the old comment rather than deleting it, the way D-049
answered `_check_win`'s.

*Done when:* a combat-range mode fires at minimum and maximum draw and asserts
the damage and flight of each; the draw pose is verified on a *remote* Gub, not
only a local one; a letter hold refuses the draw; the Elder's new range is
derived in a comment rather than typed; and the lobby dials round-trip. Decision
record.

### Step 7 — The heal potion

*Depends on: steps 2 and 3.*

A fifth `Pickup.Kind` (`pickup.gd:33`), dropped on death like a mushroom or a
lure. Note the header's warning: a kind inserted in the middle of that enum
turns every drop already in flight into a different object — **append**.

Carried stock, spent with a key, healing **channelled over about 2 s while
standing still**, with a drink clip from `6_Utility/`. Being hit during the
channel should interrupt it; decide whether the potion is spent anyway and say
which in the record.

*Done when:* a smoke check picks one up, drinks it, asserts the health arrives
over the channel and not instantly, asserts an interrupted channel behaves as
recorded, and asserts stock is lost on death like every other carried thing
(D-032). Decision record.

### Step 8 — Strafes, and a spine that aims

*Depends on: step 1, and `5_Locomotion/`. Last because it is the most feel and
the least mechanic — and because it is easiest to judge with the bow in hand.*

Two gaps, one step.

**There is no strafe or backpedal.** Running sideways at full speed plays a
*forward* run cycle. The feet skate, and in a third-person shooter that is the
most visible animation fault there is. The three-point `BlendSpace1D` becomes a
2D space over the movement direction. Every new clip needs its authored speed
measured by the pipeline, the same way `AUTHORED_RUN` was.

⚠️ **This space will mix two authoring families, and that is a decision, not an
oversight.** `GUB_2`'s `Walk` and `Run` stay — the user likes the run and it is
what the game is built on. But every sideways and backward clip comes from
Mixamo's `Locomotion Pack` family, authored differently: the audit measured
`GUB_2/Run` at **4.314 m/s** against that pack's `running` at **3.148**. The
playback-rate machinery handles the *speed* difference for free — each blend
point already plays at `game speed / authored speed`. What it does not handle is
**posture**: hip height, torso lean and arm carriage can differ between families,
and a diagonal blend is where two families meet.

So measure it before trusting it. Hip height and torso pitch across every blend
boundary, forward-to-strafe and forward-to-backward, reported as numbers. If they
disagree enough to pop, the fallback is re-downloading that pack's `walking` and
`running` to get one family throughout — **ask the user before doing that**, since
it means giving up the run they explicitly chose to keep.

⚠️ **`LeftStrafe` is not a strafe, and that measurement reverses the obvious
assumption.** The angle between where the body faces and where it actually
travels, off three independent measures (shoulder line, foot direction, and the
hip line `build_gub.py` itself uses):

| clip | shoulders | feet | hip line | speed |
|---|---:|---:|---:|---:|
| `GUB_2/Run` | 6° | 3° | reference | 4.314 m/s |
| `LeftStrafe` | 28° | 21° | 19° | 3.250 m/s |
| `StandingRunLeft` | **77°** | **46°** | **61°** | 2.580 m/s |

`LeftStrafe` is a shallow **forward-left diagonal**. `StandingRunLeft` is very
nearly a true lateral. A blend space whose sideways pole is only 28° off forward
has a hole exactly where running sideways should be.

But `StandingRunLeft` is a set of one — there is no `Standing Run Right` and no
`Standing Walk Left/Right` With Skin. Taking it puts the family boundary *inside*
the strafe axis, which is worse than having it between forward and sideways. It
also costs more rate: 4.314/2.580 = **1.67x** against `LeftStrafe`'s 1.33x.

So this step opens with a decision, not with code: **four lowercase diagonals and
a soft lateral, or three more downloads** (`Standing Run Right`, `Standing Walk
Left`, `Standing Walk Right`) and a true one. Put the numbers to the user and let
them choose.

**There is no spine aim.** `UPPER_BODY_BONES` deliberately excludes Hips and
Spine, with a comment explaining that the throw's own rotation would fight the
run cycle's weight shift. That is right for a throw and wrong for a bow: a bow
held level at a run needs the torso to track the crosshair. This is a
`LookAtModifier3D` or an equivalent spine-yaw modifier, and it is the one thing
in this whole plan the repo genuinely does not have.

Watch the interaction with D-025 and D-045: rotating the spine must not move
where a spear or an arrow actually goes, since aim is read at the release from
the camera, not from the body.

*Done when:* a range mode walks a Gub in eight directions at walk and run speed
and asserts no foot skate beyond a stated threshold; a mode aims through a full
vertical and horizontal sweep and asserts the torso tracks without the release
point moving. Decision record.

### Step 9 — The great sword

*Depends on: steps 2 and 8, and a sword mesh that does not exist yet — see
below. Last, and genuinely optional: nothing else in this plan waits on it.*

**A heavy melee one-shot.** Swing, hit, kill — the spear's role at melee range,
traded from throw to reach. Slow windup, big damage, no defence. Explicitly
**not**: blocking, combos, or impact reactions. The downloaded pack carries all
three and they are set aside in `assets/source/_rejected/` rather than deleted,
because "we decided against it" and "we threw it away" are different states and
only one of them is reversible.

Why a one-shot rather than heavy damage: the same argument that keeps the spear
at 100. A melee weapon that sometimes leaves someone alive at arm's length is a
worse read than one that misses, and the health model exists to make that a
*number* rather than a branch (step 2). So the great sword is `MAX_HEALTH` on
connect, and its balance lives entirely in the windup and the reach.

It inherits the whole windup-and-release machinery from step 4 — click, wind up,
a release moment measured off the clip with `tools/hand_track.gd`, and the hit
resolved *at* that moment rather than at the click. What differs is that the
release resolves a **shape sweep in front of the body** instead of spawning a
projectile. That is a third outcome on the one release tick, and D-025 and D-038
both argue it belongs in the same place as the other two rather than in a
parallel path of its own.

**The mesh has arrived and is built.** `art/generated/greatsword.glb`, 3000
triangles at 1024, measured at 0.77 mm mean deviation from source and verified by
reading the file back off disk. The budget is the bow's counting case cut by a
quarter, because 70% of this model is a near-flat blade that holds 0.88 mm on 901
triangles while the hilt takes the other 2099 — and the texture stays at 1024
*because* the triangles came out of the blade.

⚠️ **The attack clip is not an in-place swing, and this step must be designed
around that.** `GreatSwordHighSpinAttack` is 1.867 s and measures **1.712 m of
travel with 364.9° of net body yaw**, overshooting to 415° mid-swing. It is a
spinning advance. The user chose it over the in-place `great sword attack`
(1.183 s, 0.092 m, 0° net turn, which sits in `_rejected/MANIFEST.md` as the
fallback), so it stays — but two consequences are not optional:

- `lock_root_motion` clamps the two horizontal axes and would remove the 1.7 m of
  translation. It does **nothing to yaw**, and `align_facing` applies only one
  constant rotation. **The full revolution survives into the game.** So the
  body's facing at the release is nowhere near its facing at the click, and the
  shape sweep must be taken off the **animated skeleton**, not off the Gub's own
  basis. A sweep along `-basis.z` would point somewhere the sword is not.
- **The advance is kept** (decision above). This is the one clip in the project
  whose horizontal travel is *not* clamped, so it needs an explicit exception to
  the rule rather than a quiet edit to the table — and the physics body has to
  produce the 1.712 m, or the feet skate for the whole 1.867 s. The reach a
  player feels is the sword's own length *plus* that advance, so the
  `MatchConfig` reach dial and the animation are two halves of one number and
  have to be measured together.
- **Airborne, the spin replaces the jump pose** rather than layering over it,
  because it is full-body.

**The spin chains, on purpose.** The user: *"i kinda want the chainability, it
will make the sword more fun."* So this is a movement tech as well as an attack,
and it is **not** to be bounded by refusing the chain.

Two facts make that safe, and they should be in the record rather than
rediscovered. First, the raw motion is slow: **1.712 m over 1.867 s is 0.917
m/s**, against `RUN_SPEED` 5.4 — chaining spins to cross ground is six times
worse than running, so there is no exploit in the animation itself. The advance
only becomes interesting if the swing contributes an **impulse** that accumulates
across chained swings, which is what to build.

Second, this problem is already solved next door. D-052's bunny hop is chainable
*and* capped: `HOP_SPEED_CAP = 1.3` does not refuse the chain, it puts a ceiling
on what chaining earns, which is what makes it a skill move rather than flight.
**Feed the spin's impulse into that same momentum budget under that same
ceiling**, rather than giving the sword a second, parallel speed system. Then hop
and spin compose — build speed hopping, redirect and extend it with a swing — and
there is one number bounding both, which is the one that already has a decision
record and a smoke check behind it.

*Done when, additionally:* a range mode chains spins from a standing start and
from a full-speed hop chain, and asserts the top sustainable speed against the
stated ceiling — the measurement D-052 made, repeated with the sword in hand. Say
the number in the record.

⚠️ *Balance note for the playtest, not for this step:* a chainable mobility tool
that is also a one-shot kill may make the sword the default pick over the bow.
That is a real possibility and the answer is a playtest, not a pre-emptive nerf —
the same call the user made on the Elder.

A dedicated `great sword jump attack` clip exists in `_rejected/` if the airborne
case ever wants its own animation. One download, not needed to start.

There is **no sheathe clip** anywhere in the pack. If the sword is ever holstered
that is a fresh Mixamo search, not a re-download.

**`7_GreatSword_Suite/` is not in `PACKS` yet.** `build_gub.py` cannot see its two
clips and `--list-packs` does not even nag about them. Adding that one `Pack(...)`
line is this step's job.

*Done when:* a combat-range mode swings at a dummy just inside and just outside
the reach and asserts a kill and a survivor; the release is measured, not typed;
an Elder survives a direct hit and flashes its ward; the sword is in the hand
through the whole swing and gone when it should be; and the reach is a
`MatchConfig` dial, in `_FIELDS`. Decision record.

---

## Dependency summary

```
Wave 0, together:   [1] anim pipeline    [2] health    [3] props
                            |                |            |
Wave 1, one by one:         +--> [4] spear <-+            |
                                  |                       |
                                  +--> [5] elder cast     |
                                        |                 |
                                        +--> [6] bow <----+
                                              |
                                              +--> [7] potion
                                                    |
                            [1] -----------------> [8] strafes + aim
                                                         |
                                                         +--> [9] great sword
```

Wave 0 is **done and in the gate at 70 checks.** The clips for steps 4–8 have
arrived and are audited; step 9 additionally needs a sword mesh that does not
exist yet.
