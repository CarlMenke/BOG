# `_rejected/` — 110 files that cannot be built from, and why

**Nothing in this folder is usable and nothing in it can be repaired.** It is
kept on disk — 110 files, 54.8 MB — and out of the repository (`.gitignore`),
because a pack you can still look at is worth more than a pack you have only a
memory of, and because this list is the re-download shopping list if any of it is
ever wanted again.
`MANIFEST.md` is deliberately *not* ignored, so the measurements below survive
even if somebody deletes the `.fbx` beside them.

## Why

105 of these 110 files were downloaded **Without Skin**.

That is not a setting anybody chose. Selecting several animations in Mixamo's
*My Assets* and pressing the one **Download** button ships the skinned mesh in
exactly **one** file of the pack and every other file as skeleton-and-animation
only. A file with no skin cluster carries no bind matrices, so Blender's FBX
importer falls back to each node's own local transform and rebuilds a
**different rest pose** — same bone names, same scale, bone heads up to a
quarter of a metre out and rolls tens of degrees off. Pose-bone rotation curves
are expressed relative to the rest pose, so retargeting them by name onto the
Gub lands plausible-looking numbers on the wrong axes. Measured against
`GUB_2/Idle.fbx` the bind delta is **1.39**, against the `1e-5` that
`assert_same_character` allows, and it does not shrink when a uniform scale is
divided out — so it is a different rest pose, not a rescale, and there is no
arithmetic that puts it back.

The other **5** are the opposite problem. Each pack download carried its skin in
its own `CrouchWalking.fbx`, so those five files are intact — and are five
byte-identical copies of a clip `GUB_2/` already declares and ships. They are
here because a duplicate that `PACKS` will never name is a file
`--list-packs` would nag about forever, not because anything is wrong with them.

## How to re-download anything on this list

One animation at a time, **from that clip's own page**, never from the
multi-select Download button in *My Assets* — that button is the whole cause of
this folder. Apply the animation to *the Gub as uploaded to Mixamo*, in the same
Adobe account, and then:

| setting | value |
|---|---|
| Format | **FBX Binary (.fbx)** |
| Skin | **With Skin** ← the one that matters |
| Frames per Second | **60** |
| Keyframe Reduction | **none** |
| In Place | **unticked** — the pipeline measures the authored speed off the root travel before it throws it away, and that measurement is what stops the feet skating |

Then run the auditor before writing a `Clip(...)` for it:

    bash tools/build_bog.sh   # only after the audit is clean
    "$BLENDER" --background --python tools/audit_source_packs.py -- 5_Locomotion

A file that comes back `skin  no` was downloaded the wrong way again.

## What is in here

Filenames have been normalised to the `GUB_2` convention (PascalCase, no spaces,
`(2)` becomes a trailing `2`) so that a file moved back out of here needs no
second rename. The **Mixamo name** column is the name to search for on the site;
the pack folders keep their Mixamo names verbatim, because "which pack do I
re-download from" is the question those folders answer.

Every measurement below is from `tools/audit_source_packs.py` on the files as
they arrived. *Travel* is end-to-end hip displacement and *peak* is the furthest
the hips get from where they started — a one-shot that ends where it began has
no speed but may still lunge, and the peak is what says how far. These numbers
are as good as they get from a skinless file: the animation curves are intact,
it is only the rest pose they are relative to that is wrong, so the travel and
the length are trustworthy and the **pose is not**.


### `4_Elder_Suite/Lite Magic Pack/` — 15 files

Mixamo's **Lite Magic Pack**. Downloaded for the Elder's cast; `Standing 1H Magic Attack 01` is the clip that mattered and it has since been re-downloaded on its own into `4_Elder_Suite/`.

| file on disk | Mixamo name | frames | length s | travel m | peak m | speed m/s | skin |
|---|---|---:|---:|---:|---:|---:|:--:|
| `CrouchWalking.fbx` | CrouchWalking | 69 | 1.133 | 1.443 | 1.443 | 1.273 | **yes** |
| `Standing1HMagicAttack1.fbx` | Standing 1H Magic Attack 01 | 138 | 2.283 | 0.000 | 0.124 | 0.000 | no |
| `Standing2HMagicAreaAttack2.fbx` | Standing 2H Magic Area Attack 02 | 196 | 3.250 | 0.000 | 0.104 | 0.000 | no |
| `StandingJump.fbx` | Standing Jump | 142 | 2.350 | 0.000 | 0.082 | 0.000 | no |
| `StandingReactDeathBackward.fbx` | Standing React Death Backward | 218 | 3.617 | 0.604 | 0.629 | 0.167 | no |
| `StandingReactLargeFromFront.fbx` | Standing React Large From Front | 83 | 1.367 | 0.810 | 0.814 | 0.593 | no |
| `StandingReactSmallFromFront.fbx` | Standing React Small From Front | 72 | 1.183 | 0.000 | 0.016 | 0.000 | no |
| `StandingRunBack.fbx` | Standing Run Back | 38 | 0.617 | 1.482 | 1.482 | 2.404 | no |
| `StandingRunForward.fbx` | Standing Run Forward | 45 | 0.733 | 2.071 | 2.071 | 2.824 | no |
| `StandingTurnLeft90.fbx` | Standing Turn Left 90 | 113 | 1.867 | 0.009 | 0.140 | 0.005 | no |
| `StandingTurnRight90.fbx` | Standing Turn Right 90 | 99 | 1.633 | 0.009 | 0.176 | 0.005 | no |
| `StandingWalkBack.fbx` | Standing Walk Back | 73 | 1.200 | 1.046 | 1.046 | 0.871 | no |
| `StandingWalkForward.fbx` | Standing Walk Forward | 69 | 1.133 | 1.360 | 1.360 | 1.200 | no |
| `StandingIdle2.fbx` | standing idle 02 | 312 | 5.183 | 0.000 | 0.074 | 0.000 | no |
| `StandingIdle.fbx` | standing idle | 113 | 1.867 | 0.000 | 0.042 | 0.000 | no |


### `5_Locomotion/Locomotion Pack/` — 13 files

Mixamo's basic **Locomotion Pack** — the lowercase-named family. Its four strafes have been re-downloaded on their own into `5_Locomotion/`; its `running` (3.148 m/s) and `walking` are the fallback if the mixed-family posture check in step 8 says the whole space has to come from one family.

| file on disk | Mixamo name | frames | length s | travel m | peak m | speed m/s | skin |
|---|---|---:|---:|---:|---:|---:|:--:|
| `CrouchWalking.fbx` | CrouchWalking | 69 | 1.133 | 1.443 | 1.443 | 1.273 | **yes** |
| `Idle.fbx` | idle | 501 | 8.333 | 0.000 | 0.008 | 0.000 | no |
| `Jump.fbx` | jump | 131 | 2.167 | 0.000 | 0.095 | 0.000 | no |
| `LeftStrafeWalking.fbx` | left strafe walking | 63 | 1.033 | 1.287 | 1.287 | 1.245 | no |
| `LeftStrafe.fbx` | left strafe | 41 | 0.667 | 2.168 | 2.168 | 3.252 | no |
| `LeftTurn90.fbx` | left turn 90 | 57 | 0.933 | 0.013 | 0.094 | 0.014 | no |
| `LeftTurn.fbx` | left turn | 98 | 1.617 | 0.018 | 0.183 | 0.011 | no |
| `RightStrafeWalking.fbx` | right strafe walking | 63 | 1.033 | 1.287 | 1.287 | 1.245 | no |
| `RightStrafe.fbx` | right strafe | 41 | 0.667 | 2.168 | 2.168 | 3.252 | no |
| `RightTurn90.fbx` | right turn 90 | 57 | 0.933 | 0.014 | 0.099 | 0.015 | no |
| `RightTurn.fbx` | right turn | 98 | 1.617 | 0.016 | 0.179 | 0.010 | no |
| `Running.fbx` | running | 43 | 0.700 | 2.204 | 2.204 | 3.148 | no |
| `Walking.fbx` | walking | 63 | 1.033 | 1.240 | 1.240 | 1.200 | no |


### `5_Locomotion/Longbow Locomotion Pack/` — 13 files

Mixamo's **Longbow Locomotion Pack**. Kept as an upper-body overlay source per the plan's locomotion decision: a longbow walk's spine-up content is the bow carry pose. Nothing in it survived the download settings, so the overlay has to be re-fetched clip by clip if step 8 wants it.

⚠️ **Three of these have been re-fetched already, and into the wrong slot.** `5_Locomotion/StandingRunRight.fbx`, `StandingWalkLeft.fbx` and `StandingWalkRight.fbx` are this pack's clips, not the Magic pack's — frame counts and speeds identify them exactly against the rows below — and they were fetched as the three downloads meant to close the strafe axis beside the Magic pack's `Standing Run Left`. They are on disk, undeclared, and measured in `5_Locomotion/README.md`; declaring them makes five of the sixteen compass legs worse and fails the gate's `mirror` check (D-071). Nothing is wrong with the files. They are a different family, and its right-hand strafes are diagonals like everyone else's.

| file on disk | Mixamo name | frames | length s | travel m | peak m | speed m/s | skin |
|---|---|---:|---:|---:|---:|---:|:--:|
| `CrouchWalking.fbx` | CrouchWalking | 69 | 1.133 | 1.443 | 1.443 | 1.273 | **yes** |
| `StandingIdle1.fbx` | standing idle 01 | 306 | 5.083 | 0.000 | 0.002 | 0.000 | no |
| `StandingRunBack.fbx` | standing run back | 40 | 0.650 | 1.390 | 1.390 | 2.138 | no |
| `StandingRunForwardStop.fbx` | standing run forward stop | 55 | 0.900 | 0.335 | 0.406 | 0.372 | no |
| `StandingRunForward.fbx` | standing run forward | 53 | 0.867 | 2.265 | 2.265 | 2.613 | no |
| `StandingRunLeft.fbx` | standing run left | 41 | 0.667 | 1.543 | 1.543 | 2.315 | no |
| `StandingRunRight.fbx` | standing run right | 46 | 0.750 | 1.789 | 1.789 | 2.386 | no |
| `StandingTurn90Left.fbx` | standing turn 90 left | 76 | 1.250 | 0.027 | 0.192 | 0.022 | no |
| `StandingTurn90Right.fbx` | standing turn 90 right | 67 | 1.100 | 0.027 | 0.158 | 0.025 | no |
| `StandingWalkBack.fbx` | standing walk back | 89 | 1.467 | 0.998 | 0.998 | 0.681 | no |
| `StandingWalkForward.fbx` | standing walk forward | 72 | 1.183 | 0.998 | 0.998 | 0.844 | no |
| `StandingWalkLeft.fbx` | standing walk left | 73 | 1.200 | 1.287 | 1.287 | 1.073 | no |
| `StandingWalkRight.fbx` | standing walk right | 73 | 1.200 | 1.379 | 1.379 | 1.149 | no |


### `5_Locomotion/Magic Locomotion Pack/` — 17 files

Mixamo's **Magic Locomotion Pack** — the `Standing *` family, and the pack that matters. `Standing Run Left` has been re-downloaded on its own into `5_Locomotion/` and is the game's run-strafe pole (D-071); its right-hand twin there is that clip *reflected*, not a download.

**The one clip still worth fetching out of this pack is `Standing Walk Left`.** Measured on the unskinned copy here by `tools/audit_source_packs.py`, which reports a bearing for every file it sees — eight files in this tree exist both skinned and skinless and all eight reproduce to 0.1°, so the number is good — it travels **+94.4°** off its own chest line: a true lateral, and mirrored the way the run pole is it is both walk poles of the locomotion plane. One clip, from its own page, With Skin.

**Do not fetch `Standing Walk Right` or `Standing Run Right`.** They measure −38.8° and −37.6°, which are ordinary forward diagonals and no better than what the game already has. That is not a defect in this pack: **every right strafe in every locomotion pack below is a −37 to −47 degree diagonal**, because these families are authored around a character holding its chest turned to its own right. Travel off the chest line, + to the character's left:

| pack | run left | run right | walk left | walk right |
|---|---:|---:|---:|---:|
| Locomotion Pack | +27.5° | −37.4° | +35.3° | −46.5° |
| Longbow Locomotion | +116.0° | −45.8° | +126.5° | −46.3° |
| Magic Locomotion | **+76.5°** | −37.6° | **+94.4°** | −38.8° |

A right-hand strafe pole cannot be bought. It has to be mirrored, and `build_bog.py`'s `mirror_of` is how (D-071).

(`Standing Run Back` and `Standing Walk Back` were this entry's old shopping list. They are no longer wanted: `RunningBackward.fbx` and `WalkingBackward.fbx` closed the backward axis at D-066 and plant at 0.16 and 0.23 of body speed.)

| file on disk | Mixamo name | frames | length s | travel m | peak m | speed m/s | skin |
|---|---|---:|---:|---:|---:|---:|:--:|
| `CrouchWalking.fbx` | CrouchWalking | 69 | 1.133 | 1.443 | 1.443 | 1.273 | **yes** |
| `StandingJumpRunningLanding.fbx` | Standing Jump Running Landing | 83 | 1.367 | 3.393 | 3.393 | 2.483 | no |
| `StandingJumpRunning.fbx` | Standing Jump Running | 64 | 1.050 | 3.005 | 3.005 | 2.862 | no |
| `StandingJump.fbx` | Standing Jump | 142 | 2.350 | 0.000 | 0.082 | 0.000 | no |
| `StandingLandToStandingIdle.fbx` | Standing Land To Standing Idle | 67 | 1.100 | 0.943 | 0.944 | 0.857 | no |
| `StandingRunBack.fbx` | Standing Run Back | 38 | 0.617 | 1.482 | 1.482 | 2.404 | no |
| `StandingRunForward.fbx` | Standing Run Forward | 45 | 0.733 | 2.071 | 2.071 | 2.824 | no |
| `StandingRunLeft.fbx` | Standing Run Left | 46 | 0.750 | 1.935 | 1.935 | 2.581 | no |
| `StandingRunRight.fbx` | Standing Run Right | 47 | 0.767 | 2.178 | 2.178 | 2.840 | no |
| `StandingSprintForward.fbx` | Standing Sprint Forward | 35 | 0.567 | 2.302 | 2.302 | 4.062 | no |
| `StandingTurnLeft90.fbx` | Standing Turn Left 90 | 113 | 1.867 | 0.009 | 0.140 | 0.005 | no |
| `StandingTurnRight90.fbx` | Standing Turn Right 90 | 99 | 1.633 | 0.009 | 0.176 | 0.005 | no |
| `StandingWalkBack.fbx` | Standing Walk Back | 73 | 1.200 | 1.046 | 1.046 | 0.871 | no |
| `StandingWalkForward.fbx` | Standing Walk Forward | 69 | 1.133 | 1.360 | 1.360 | 1.200 | no |
| `StandingWalkLeft.fbx` | Standing Walk Left | 70 | 1.150 | 1.117 | 1.117 | 0.971 | no |
| `StandingWalkRight.fbx` | Standing Walk Right | 72 | 1.183 | 1.188 | 1.188 | 1.004 | no |
| `StandingIdle.fbx` | standing idle | 113 | 1.867 | 0.000 | 0.042 | 0.000 | no |


### `Great Sword Pack/` — 52 files

Mixamo's **Great Sword Pack**, 52 files. Two of them have been re-downloaded into `7_GreatSword_Suite/`. Most of the rest is deliberately unwanted rather than merely broken: the plan's great-sword decision is a heavy melee one-shot with **no blocking, no combos and no impact reactions**, which rules out every `blocking`, `impact`, `slash` and `kick` in here on purpose. They stay listed because "we decided against it" and "we threw it away" are different states and only one of them is reversible.

| file on disk | Mixamo name | frames | length s | travel m | peak m | speed m/s | skin |
|---|---|---:|---:|---:|---:|---:|:--:|
| `CrouchWalking.fbx` | CrouchWalking | 69 | 1.133 | 1.443 | 1.443 | 1.273 | **yes** |
| `DrawAGreatSword1.fbx` | draw a great sword 1 | 31 | 0.500 | 0.082 | 0.082 | 0.165 | no |
| `DrawAGreatSword2.fbx` | draw a great sword 2 | 48 | 0.783 | 0.097 | 0.098 | 0.124 | no |
| `GreatSword180Turn2.fbx` | great sword 180 turn (2) | 34 | 0.550 | 0.206 | 0.600 | 0.374 | no |
| `GreatSword180Turn.fbx` | great sword 180 turn | 48 | 0.783 | 0.041 | 0.301 | 0.052 | no |
| `GreatSwordAttack.fbx` | great sword attack | 72 | 1.183 | 0.000 | 0.092 | 0.000 | no |
| `GreatSwordBlocking2.fbx` | great sword blocking (2) | 58 | 0.950 | 0.000 | 0.002 | 0.000 | no |
| `GreatSwordBlocking3.fbx` | great sword blocking (3) | 31 | 0.500 | 0.079 | 0.079 | 0.158 | no |
| `GreatSwordBlocking.fbx` | great sword blocking | 31 | 0.500 | 0.079 | 0.079 | 0.158 | no |
| `GreatSwordCasting.fbx` | great sword casting | 288 | 4.783 | 0.000 | 0.297 | 0.000 | no |
| `GreatSwordCrouching2.fbx` | great sword crouching (2) | 43 | 0.700 | 0.259 | 0.259 | 0.369 | no |
| `GreatSwordCrouching3.fbx` | great sword crouching (3) | 111 | 1.833 | 0.000 | 0.007 | 0.000 | no |
| `GreatSwordCrouching4.fbx` | great sword crouching (4) | 23 | 0.367 | 0.053 | 0.053 | 0.145 | no |
| `GreatSwordCrouching5.fbx` | great sword crouching (5) | 85 | 1.400 | 0.000 | 0.002 | 0.000 | no |
| `GreatSwordCrouching6.fbx` | great sword crouching (6) | 29 | 0.467 | 0.053 | 0.060 | 0.114 | no |
| `GreatSwordCrouching.fbx` | great sword crouching | 41 | 0.667 | 0.274 | 0.274 | 0.410 | no |
| `GreatSwordHighSpinAttack.fbx` | great sword high spin attack | 113 | 1.867 | 1.713 | 1.714 | 0.918 | no |
| `GreatSwordIdle2.fbx` | great sword idle (2) | 223 | 3.700 | 0.000 | 0.072 | 0.000 | no |
| `GreatSwordIdle3.fbx` | great sword idle (3) | 220 | 3.650 | 0.000 | 0.078 | 0.000 | no |
| `GreatSwordIdle4.fbx` | great sword idle (4) | 226 | 3.750 | 0.000 | 0.062 | 0.000 | no |
| `GreatSwordIdle5.fbx` | great sword idle (5) | 454 | 7.550 | 0.000 | 0.066 | 0.000 | no |
| `GreatSwordIdle.fbx` | great sword idle | 121 | 2.000 | 0.000 | 0.016 | 0.000 | no |
| `GreatSwordImpact2.fbx` | great sword impact (2) | 72 | 1.183 | 0.000 | 0.174 | 0.000 | no |
| `GreatSwordImpact3.fbx` | great sword impact (3) | 76 | 1.250 | 0.000 | 0.067 | 0.000 | no |
| `GreatSwordImpact4.fbx` | great sword impact (4) | 40 | 0.650 | 0.000 | 0.025 | 0.000 | no |
| `GreatSwordImpact5.fbx` | great sword impact (5) | 58 | 0.950 | 0.000 | 0.016 | 0.000 | no |
| `GreatSwordImpact.fbx` | great sword impact | 52 | 0.850 | 0.000 | 0.025 | 0.000 | no |
| `GreatSwordJump2.fbx` | great sword jump (2) | 55 | 0.900 | 0.000 | 0.059 | 0.000 | no |
| `GreatSwordJumpAttack.fbx` | great sword jump attack | 131 | 2.167 | 2.335 | 2.335 | 1.078 | no |
| `GreatSwordJump.fbx` | great sword jump | 39 | 0.633 | 1.252 | 1.252 | 1.977 | no |
| `GreatSwordKick2.fbx` | great sword kick (2) | 105 | 1.733 | 0.000 | 0.477 | 0.000 | no |
| `GreatSwordKick.fbx` | great sword kick | 91 | 1.500 | 0.000 | 0.289 | 0.000 | no |
| `GreatSwordPowerUp.fbx` | great sword power up | 211 | 3.500 | 0.000 | 0.146 | 0.000 | no |
| `GreatSwordRun2.fbx` | great sword run (2) | 37 | 0.600 | 1.885 | 1.885 | 3.142 | no |
| `GreatSwordRun.fbx` | great sword run | 44 | 0.717 | 1.391 | 1.391 | 1.941 | no |
| `GreatSwordSlash2.fbx` | great sword slash (2) | 212 | 3.517 | 2.276 | 2.276 | 0.647 | no |
| `GreatSwordSlash3.fbx` | great sword slash (3) | 110 | 1.817 | 0.000 | 0.524 | 0.000 | no |
| `GreatSwordSlash4.fbx` | great sword slash (4) | 108 | 1.783 | 0.827 | 0.827 | 0.464 | no |
| `GreatSwordSlash5.fbx` | great sword slash (5) | 87 | 1.433 | 0.000 | 0.493 | 0.000 | no |
| `GreatSwordSlash.fbx` | great sword slash | 77 | 1.267 | 0.000 | 0.248 | 0.000 | no |
| `GreatSwordSlideAttack.fbx` | great sword slide attack | 128 | 2.117 | 2.556 | 2.556 | 1.208 | no |
| `GreatSwordStrafe2.fbx` | great sword strafe (2) | 70 | 1.150 | 1.067 | 1.067 | 0.928 | no |
| `GreatSwordStrafe3.fbx` | great sword strafe (3) | 35 | 0.567 | 0.977 | 0.977 | 1.724 | no |
| `GreatSwordStrafe4.fbx` | great sword strafe (4) | 39 | 0.633 | 1.438 | 1.438 | 2.270 | no |
| `GreatSwordStrafe.fbx` | great sword strafe | 66 | 1.083 | 0.931 | 0.931 | 0.859 | no |
| `GreatSwordTurn2.fbx` | great sword turn (2) | 50 | 0.817 | 0.135 | 0.135 | 0.166 | no |
| `GreatSwordTurn.fbx` | great sword turn | 44 | 0.717 | 0.153 | 0.171 | 0.213 | no |
| `GreatSwordWalk2.fbx` | great sword walk (2) | 78 | 1.283 | 0.960 | 0.960 | 0.748 | no |
| `GreatSwordWalk.fbx` | great sword walk | 82 | 1.350 | 1.089 | 1.089 | 0.807 | no |
| `SpellCast.fbx` | spell cast | 68 | 1.117 | 0.000 | 0.129 | 0.000 | no |
| `TwoHandedSwordDeath2.fbx` | two handed sword death (2) | 156 | 2.583 | 0.914 | 0.924 | 0.354 | no |
| `TwoHandedSwordDeath.fbx` | two handed sword death | 145 | 2.400 | 0.568 | 0.574 | 0.237 | no |


110 files listed. The five marked **yes** in the skin column are the duplicate `CrouchWalking`s described at the top; every other row is unusable as it stands.
