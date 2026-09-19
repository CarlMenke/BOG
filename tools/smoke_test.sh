#!/usr/bin/env bash
# Everything that can be checked without a person watching. Run it before any
# commit that touches gameplay, and after any asset re-import.
#
#   bash tools/smoke_test.sh
#
# Exits non-zero on the first failure, so it works as a CI gate.
#
# Two of the checks here exist because of bugs that shipped as "done": the
# ragdoll exploded half a second after every death while the preview that
# certified it only looked at the first quarter-second, and the match rules had
# never been run with more than one live player. Anything a still frame cannot
# prove belongs in this file rather than in someone's memory.
#
# What this cannot do is judge whether the game *looks* right. The preview
# scenes under tools/ are for that, and they need eyes. See docs/STATUS.md.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Beside the repo rather than in /tmp: under WSL the Godot we run is a Windows
# binary, and /tmp is inside the Linux filesystem, reachable from Windows only
# as a \wsl.localhost UNC path. `.smoke/` is gitignored.
LOG_DIR="$ROOT/.smoke"

failures=0
checks=0

# ------------------------------------------------------------- the engine ---
# Shared with `tools/net_test.sh` rather than kept here, because a search for
# where people install Godot has to stay in step with reality and two copies of
# it will not. `tools/find_godot.sh` carries the Windows/WSL path hunting, the
# 4.7 version check, and the WSL path translation, and sets $GODOT, $GODOT_ROOT
# and $GODOT_LOG_DIR. It is sourced, so a missing engine ends this script rather
# than a subshell.
GODOT_TAG=smoke
. "$ROOT/tools/find_godot.sh"

mkdir -p "$LOG_DIR"

# Run a Godot invocation and require `expect` to appear in its output. Also
# fails on any SCRIPT ERROR, which is how a broken script announces itself —
# Godot carries on running afterwards, so a silent exit code proves nothing.
check() {
    local name="$1" expect="$2"; shift 2
    local log="$LOG_DIR/${name// /_}.log"
    checks=$((checks + 1))
    printf '  %-32s ' "$name"

    # Under a wall clock, since the letters round: a tool whose root script
    # fails to parse has nothing left to call `quit`, and a check that never
    # returns is a gate that never says FAIL. Fifteen minutes is longer than
    # the slowest honest check here (the Rust playthrough) by a wide margin.
    if ! timeout "${CHECK_TIMEOUT:-900}" "$@" >"$log" 2>&1; then
        echo "FAIL (Godot exited non-zero, or ran past ${CHECK_TIMEOUT:-900} s)"
        sed 's/^/      /' "$log" | tail -20
        failures=$((failures + 1))
        return
    fi
    if grep -q "SCRIPT ERROR" "$log"; then
        echo "FAIL (script error)"
        grep -A 3 "SCRIPT ERROR" "$log" | sed 's/^/      /' | head -20
        failures=$((failures + 1))
        return
    fi
    # Always a bug, never noise, and it can surface in any check: something asked
    # the multiplayer API for an id while no peer was assigned. Godot prints it
    # and carries on, so it is invisible unless it is looked for. Checked here
    # rather than in one test because the next place it appears will be a
    # different one.
    if grep -q "No multiplayer peer is assigned" "$log"; then
        echo "FAIL (asked a multiplayer peer that is not there)"
        grep -A 4 "No multiplayer peer is assigned" "$log" | sed 's/^/      /' | head -12
        failures=$((failures + 1))
        return
    fi
    if ! grep -qF "$expect" "$log"; then
        echo "FAIL (expected: $expect)"
        sed 's/^/      /' "$log" | tail -20
        failures=$((failures + 1))
        return
    fi
    echo "ok"
}

# One more thing to find in the log a `check` has already written, named by the
# same label. A second `check` would prove the same thing by running the whole
# harness again, and the runs this is used on are the expensive ones — the Rust
# playthrough loads a 43 MB `.glb` and its fifty textures before it does
# anything at all.
also() {
    local name="$1" expect="$2"
    local log="$LOG_DIR/${name// /_}.log"
    checks=$((checks + 1))
    printf '  %-32s ' "$name, and"
    if [ ! -f "$log" ]; then
        echo "FAIL (no log — did '$name' run?)"
        failures=$((failures + 1))
        return
    fi
    if ! grep -qF "$expect" "$log"; then
        echo "FAIL (expected: $expect)"
        sed 's/^/      /' "$log" | tail -20
        failures=$((failures + 1))
        return
    fi
    echo "ok"
}

echo "smoke: $ROOT"
echo "smoke: $GODOT ($GODOT_VERSION)"
echo

echo "importing assets"
if ! "$GODOT" --headless --path "$GODOT_ROOT" --import >"$LOG_DIR/import.log" 2>&1; then
    echo "  FAIL — import did not complete"
    tail -20 "$LOG_DIR/import.log" | sed 's/^/      /'
    exit 1
fi
echo "  ok"
echo

echo "headless checks"
# The rebuilt character's import layer (D-095): the body at 1.80 m with its 49
# bones, every row of the clip table in the shared library, every clip's tracks
# landing on the body's bones with the hips locked in place, and a clip from
# each suite posing the body exactly where its own skeleton poses it. The
# products it reads are written by tools/import_clip.gd during the import pass
# above, so a broken .import setting shows up here first.
check "clip library" "clip_check: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" --script tools/clip_check.gd
# The finger grips (the letters round): one frozen pose per hand per prop,
# lifted off the clips that already draw a closed hand. It runs here and not
# earlier because what it reads, art/generated/bog_clips.res, is written by
# tools/import_clip.gd during the import pass above — and what it writes,
# art/generated/grip_poses.res, has to be **committed**: BogAnimator loads it
# at runtime, nothing derives it at load time, and a checkout without it is a
# Bog whose fingers keep whatever curl the body clip was authored with.
check "finger grips" "grip_poses: PASS"     "$GODOT" --headless --path "$GODOT_ROOT" tools/grip_poses.tscn
also "finger grips" "grip_poses: 5 poses,"
check "invite codes" "invite_codes: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/invite_codes.tscn
check "match rules" "match_rules: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/match_rules.tscn
# Whisperbloom Hollow's forest and spawn ring, measured (D-055). The user asked
# for the island "a little bigger" with 60% fewer trees at twice the height, and
# the scatter's dart throw places fewer than it is asked for, so what is held
# here is what landed: on four seeds, 10-14 trees at a mean height of 12-18 m
# (29 at 7.4 m before), the main island at its stated radius, the capture bases
# more than 25 m apart (18.8 before) and no two pads within 5.5 m (3.8 before).
# Headless, the whole procedural layout without a scene tree, about ten seconds.
check "the hollow's forest and pads" "island_report: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/island_report.tscn -- 20260904 4
# The shield as cover, which is the only thing about it that matters and the
# one thing nothing checked until D-039. Three assertions out of one run, and
# the order of them is the point: a spear thrown at a Bog standing behind a
# shield does not kill it, the *same* throw with the shield withered does,
# and a Bog walking into one is held off at the face of it.
#
# The middle one is not a nicety. "Did not die" passes for a spear that has
# stopped killing anybody at all — a broken launch, a dummy already dead, a
# `report_kill` that never arrived — so without a control on the same geometry
# the first assertion would go green on a shield that stops nothing. Which is
# what the check it supplements did for this whole session: `shield deploys`
# asserts `snapshot: wrote`, proving a PNG exists, while the mushroom's
# collision cap sat 31 cm above the head of the tallest thing it was meant to
# be hiding.
#
# The mode plants the shield half a metre off the line of fire, and that is
# the other half of why this is worth anything. It was written for the
# mushroom, where lining the shot up perfectly meant the 0.55 m stem blocked it
# on its own and the canopy a metre above the fight was never asked anything.
# On a slab it asks the other question — whether a wall 1.23 m across is still
# cover once a fight has moved you a step off your own centre line.
#
# The profile the mode prints alongside is the shield's shape, measured with
# rays rather than read off its constants: 1.22-1.24 m blocked at every height
# from 0.15 m to 1.65 m and nothing at 1.80 m, which is a wall standing on the
# ground with a Bog's antennae over the top of it (D-079).
#
# Headless, and it quits itself around tick 350: it drives its own sequence and
# waits on the throw gate between the two spears rather than on a frame count.
# The picture of a spear stopping dead against the boards is a separate,
# earlier frame:
#     ... --script tools/snapshot.gd -- res://tools/combat_range.tscn \
#         out/shield_cover.png 100 cover
check "shield stops a spear" "cover PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- cover
also "shield stops a spear" "control PASS"
also "shield stops a spear" "solid PASS"
# Twelve throws, with the shaft required to be back in the fist at the end of
# every one of them — and then the fist is emptied by hand while the throw gate
# still says armed, and has to refill itself. The first half is the bug as the
# player met it ("the spear model is not reliably reappearing"); the second is
# the property that stops it coming back, and it is the half that cannot pass
# by luck. Against the one-shot `SceneTreeTimer` this replaced, all twelve
# cycles fail here and the emptied fist never refills.
check "the spear grows back" "recharge PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- recharge
# The half second itself, measured on a running game rather than asserted about
# the constants (D-063). One throw, three numbers off it: the shaft arrives in
# the world THROW_RELEASE_TIME after the click to within a frame and a half, the
# fist is already empty at the instant it does — D-025's promise read at the one
# moment it is about — and the tick it arrives on is the tick the throwing hand
# is furthest in front of the hips.
#
# That third verdict is the only thing in this gate that reads the *animation*
# rather than a number derived from it. Move the window or the rate without
# `THROW_RELEASE_TIME` following, and it fails while the first two still agree
# with each other — which is exactly the bug D-025 exists because of and D-040
# repeated. Headless, and it quits itself about a second in.
check "the spear leaves when the arm does" "release PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- release
# The same question asked of the Elder, which since D-064 is a different
# question about a different clip. One bolt, three numbers: it arrives
# `MatchConfig.lightning_delay` after the click to within a frame and a half,
# the composed arm is 83% of the way out when it does, and the tick it arrives
# on is the tick that arm stops going forward.
#
# The second and third are what this adds over `release`. `Cast` is a clip whose
# hand stops a third of a second before it is furthest in front of the hips — it
# is *held* out there while the body unwinds — so the release rule D-063 used on
# the throw, applied to this clip, would put the bolt in the recovery while
# every constant in the file went on agreeing with every other. This is the line
# that would notice, and the mistake is eight ticks away from passing it.
# Headless, and it quits itself about a second in.
check "the bolt leaves when the arm does" "cast PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- cast
# The bow, in numbers (D-065). Four verdicts out of one run and the first is the
# cheapest to get wrong: a letter hold has to refuse the draw and empty the bow
# hand, which is the decisions table's "a letter hold disarms the bow as well as
# the spear" asserted rather than assumed.
#
# Then the two *ends* of the charge, which are two different weapons on purpose.
# A snap shot let go on the frame after the key went down has to take exactly
# `bow_damage_snap` and fly the snap dials; a full draw held past
# `bow_draw_time` has to take `bow_damage_full` and fly the full ones. Neither
# number is read off the arrow — the damage is what the victim actually lost and
# the speed and the drop are fitted off six ticks of the arrow's own positions,
# so a curve that went linear, a drop that stopped interpolating or a charge the
# host clamped to nothing all fail here with the number they produced printed
# beside the number they owed.
#
# The two shots are fired at different ranges and that is the mechanic rather
# than a convenience: a snap shot drops 4.85 m over the fourteen metres the
# spear modes use, so it is checked at five, which is as far as this weapon
# reaches without an arc. Headless, and it quits itself in about four seconds.
check "the bow's two ends" "bow PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- bow
also "the bow's two ends" "letter PASS"
also "the bow's two ends" "snap PASS"
also "the bow's two ends" "full PASS"
# The charge as a tell, on a Bog nobody is driving (D-065). Everything that
# makes a draw work does so on the client holding the key, and none of it says a
# word about the seven Bogs whose charge has to arrive over a wire — which is
# the half D-025 cares about, because a tell only the archer can see is not a
# tell.
#
# So the mode publishes one float onto a dummy, once a frame, and requires the
# two skeletons to agree about how far the string is back to within a
# centimetre, at five charge levels. Two controls sit on the same line. The draw
# has to have moved the hands at least 0.20 m, or "they agree" is satisfied by
# two Bogs standing still; and the synchroniser's own property list has to carry
# `sync_draw`, because every Bog in this testbed is in one process and the wire
# is never involved — without that, a build that had forgotten to replicate the
# field would pass every pose row and be invisible to every real client.
check "a remote Bog draws the same bow" "draw PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- draw
# The feet, round the compass (D-066). The most visible animation fault this
# game had was a Bog running sideways at full speed playing a *forward* run
# cycle, and the honest measurement of it is not an angle — it is how fast the
# foot that is on the ground is sliding along it. So the mode drives a Bog held
# facing one way, as it is held while aiming, through eight bearings at walking
# and at running speed, and takes the slower of its two toes every tick.
#
# Five verdicts, and the order is the usual one of each being the control for
# the last. `straight` is the two axes the new clips *solve* — forward and
# backward plant at 0.28 of body speed or better, where before this step the two
# backward legs measured 0.83 and 1.03 and that line fails on the old build.
# `compass` is all sixteen legs against a limit drawn between the plane's own
# worst (1.14, a walking back-diagonal) and the one-dimensional space's (1.36).
#
# `sideways` and `mirror` are the strafe axis itself, and they are D-071's
# (D-066 left this axis open and improved by a third). `sideways` is the four
# lateral legs at 0.85 of body speed or better — running sideways is 0.43 and
# 0.30 where it was 0.98 and 0.93, and the old build fails this twice.
#
# `mirror` is the one that earns its place, because `sideways` alone cannot see
# the fault it is about. Mixamo's aim-strafe families are **handed**: every right
# strafe in every pack is a -37 to -47 degree diagonal while its left twin can be
# a true lateral, so a set built from a downloaded left and a downloaded right
# plants one side and skates the other. The right pole is therefore the left one
# *reflected*, and this requires the two halves of the axis to stay within 0.20
# of each other. Declaring `5_Locomotion/StandingRunRight.fbx` instead — which is
# on disk, and is the obvious next thing for somebody to try — measures 0.30 left
# against 0.84 right: it **passes `sideways` by a hundredth** and fails this at
# 0.54, which is the whole argument for there being two lines here.
#
# `crouch` is the control in D-039's sense and it is one that has to come out
# *badly*: a crouching Bog still has one clip behind a line, so its bearings
# spread 0.21 to 1.41 across the compass. If they ever stop disagreeing, this
# measurement has stopped being able to see a skate and the sixteen lines above
# it mean nothing. `--fixed-fps 60` so every tick is the game's own length;
# headless, about a second and a half.
check "feet planted in eight directions" "strafe PASS" \
    "$GODOT" --headless --fixed-fps 60 --path "$GODOT_ROOT" tools/combat_range.tscn -- strafe
also "feet planted in eight directions" "straight PASS"
also "feet planted in eight directions" "compass PASS"
also "feet planted in eight directions" "sideways PASS"
also "feet planted in eight directions" "mirror PASS"
also "feet planted in eight directions" "crouch PASS"
# The torso that aims (D-066), swept through everything a player can point it
# at. D-065 shipped a bow pointing **91 degrees off the Bog's own facing** —
# an archer stands side-on and the whole angle lives above a pelvis the layer
# mask throws away — and left the number in `draw`'s own output for this step
# to drive down.
#
# A full draw is held while the view goes all the way round the horizon and then
# from `PITCH_MIN` to `PITCH_MAX`. `bow` is that 91 answered: the bow's bearing
# stays within 3 degrees of the crosshair and its line within 5 degrees of it in
# space. `pitch` is the half the body never had at all — 123 degrees of
# elevation tracked, with the span itself as the control, because a torso that
# never moved would agree with a level crosshair perfectly.
#
# `release` is the one that would hurt most to lose. Two arrows are fired from
# one spot at the two ends of the pitch range and have to leave from **the same
# point in space** while going 122 degrees apart: the origin is the body's
# (position, eye height and yaw, none of them on the skeleton) and the direction
# is the camera's, so this is D-025 and D-045 asserted against the one thing
# most likely to break them. Measured, 0.0000 m.
check "the torso tracks the crosshair" "spine PASS" \
    "$GODOT" --headless --fixed-fps 60 --path "$GODOT_ROOT" tools/combat_range.tscn -- spine
also "the torso tracks the crosshair" "bow PASS"
also "the torso tracks the crosshair" "pitch PASS"
also "the torso tracks the crosshair" "release PASS"
# **A grip is still the grip its own clips solve for** (D-073), asked of the bow
# — and this run has been able to ask it since D-065 and did not.
#
# `preview_bow -- measure` solves six numbers out of the string and the draw
# window: where the bow sits in the left fist at every charge level so the
# string's V meets the drawing fingers, and where the arrow sits in the right
# one. It prints them as six `const` lines for a human to paste, and until now
# nothing compared the printout with what was actually pasted — which is exactly
# how the great sword's scale shipped at `1.2586` against a solve that had been
# printing `1.2585` for four steps. A rebuilt `bow.glb`, a re-timed `BowReload`
# or a moved draw window all move this solve, and the bow would go on hanging in
# the old one, silently.
#
# **What this check used to be, and why it is not that any more.** It was a floor
# under the *bare-armed* carry — the bow on the locomotion's own arms, with no
# carry layer over them, which the game composes for the fifth of a second the
# layer takes to fade up and never otherwise. That floor and the bow's head
# clearance are provably disjoint (`HeldGear.CARRY_TILT` has the map), and its
# own motivating case — D-065's 1.71 m longbow ploughing `Run` by 0.158 m — no
# longer reproduces on the rebuilt library: untilted measures +0.003 m now. The
# table is still printed and the carry is judged where the game composes it, in
# `preview_carry -- measure` further down. Headless — nothing is rendered, the
# PNG is thrown away.
check "the bow's grip is still the one its string solves for" "grip PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" --script tools/snapshot.gd -- \
    res://tools/preview_bow.tscn "$GODOT_LOG_DIR/bow_measure.png" 4 measure
# The Elder's invincibility, asserted against a real spear rather than in logic
# (D-040). `match_rules` can prove that `report_kill` refuses the kill; only this
# can prove that a shaft launched at a body fourteen metres away arrives, is
# turned aside, and leaves the Bog standing — and that is the assertion it would
# hurt most to have wrong, because an Elder that quietly dies to the first spear
# is a twenty-second power-up that does not exist.
#
# Three verdicts out of one run, and the same reasoning the shield's have.
# `ward` is the rule; `expiry` is the robe burning out **on its own clock**, in
# a real match loop rather than by a harness winding the row back; and `control`
# is the same throw at the same Bog with the robe gone, which is what stops
# "did not die" being satisfied by a spear that never left the hand.
#
# Both halves were run against the code without them first (D-015): with the
# invincibility check removed, `ward` fails; with `_tick_elders` removed,
# `expiry` fails.
#
# Headless, and it quits itself around tick 260. A picture of a spear stopping
# dead in a violet flash with the Elder untouched behind it is a separate frame:
#     ... --script tools/snapshot.gd -- res://tools/combat_range.tscn \
#         out/elder_ward.png 90 ward
check "a spear cannot kill the Elder" "ward PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- ward
also "a spear cannot kill the Elder" "expiry PASS"
also "a spear cannot kill the Elder" "control PASS"
# A respawn hands back nothing (D-032, D-038, D-043). A player: "you spawn with
# either an item or the elder randomly". The player dies holding a shield and
# a dummy dies as the Elder holding one too, both off their spawn pads with loot
# lying on both corpses; a second after both come back, nobody may hold, wear or
# have picked up anything.
#
# The dummy is the half that caught it. It is a remote Bog, and the mode plays
# its client 200 ms behind the host — still dead, still publishing the corpse,
# a snapshot every other tick — which is the window the bug lived in: the
# host's live copy was put back on its own loot and walked into it. Against the
# code without `Bog.sync_life` this fails with the dummy holding a shield and
# wearing the robe. `tools/net_loopback.gd` cannot open that window at all: a
# loopback round trip is shorter than a physics tick.
#
# Headless, and it quits itself around tick 280.
check "a respawn hands back nothing" "respawn PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- respawn
# Health, and the damage model now standing in front of every death (D-062).
# Five verdicts out of one run, and they are in this order because each one is
# the control for the last.
#
# `partial` is the new thing itself: 35 then 40 through `report_damage` leaves a
# Bog on its feet with 25, with the host's number, the body's number and the bar
# over its head all agreeing. `lethal` is the third hit taking it to exactly
# zero and dying *normally* — a corpse on the ground and the same
# `player_killed` the kill feed is built out of. `elder` is D-040 restated as a
# number: 55 at an Elder takes nothing at all and still flashes the ward, which
# is the one piece of feedback that hit produces. `respawn` is a life beginning
# full, on a Bog that died on zero.
#
# `spear` is the one that would hurt most to lose and the reason this mode ends
# with a real throw: a spear thrown at a Bog on full health has to kill it, in
# one, still. Every other line here would pass on a damage model that had
# quietly turned the spear into a two-shot — which is exactly what a health
# system is most likely to break, and why the spear's damage is a constant equal
# to a whole Bog rather than a branch that says "die".
#
# Run against the code without the parts they check: with `revive_at` not
# restoring health `respawn` fails; with the Elder's refusal taken out `partial`
# and `lethal` fail loudly (every hit wards instead). Headless, and it quits
# itself around tick 230.
check "damage leaves a Bog standing" "partial PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- health
also "damage leaves a Bog standing" "lethal PASS"
also "damage leaves a Bog standing" "elder PASS"
also "damage leaves a Bog standing" "respawn PASS"
also "damage leaves a Bog standing" "spear PASS"
# The heal potion, end to end (D-067). Six verdicts out of one run, and the
# order is the usual one of each being the control for the last.
#
# `drop` is the fifth `Pickup.Kind` coming out of a real death and being
# collected by a real `Area3D` overlap — a dummy standing on the corpse, which
# is the only way a Bog with no client behind it ever picks anything up.
#
# `channel` is the thing the feature *is*, and it is three readings of one
# drink: no health at all on the frame of the click, some of it half way
# through, all forty at the end. The first and the second are each other's
# control — "none yet" catches a heal that fired on the keypress, "some but not
# all" catches one that waited for the end — and between them they are the whole
# reason healing is not instant on pickup.
#
# `interrupt` is the recorded rule (see D-067's own section on it): a hit through
# `report_damage` half way in ends the drink, the potion is **spent anyway**, and
# what is kept is the half that had actually arrived. The last of those is the
# line that would fail if the heal ever went back to landing in one lump.
#
# `moved` is the other rule, turned the other way up by the auto-drink (D-067,
# amended). A potion is drunk on contact now, so the drinker is moving on the
# frame the channel starts: a Bog that sprints **keeps** the drink and pays for
# it at `Bog.DRINK_SPEED_SCALE` instead, and a Bog dragged by a magnet keeps it
# too. Without both halves, movement could quietly creep back into the interrupt
# rule and every drink in the game would cancel on its first frame.
#
# `death` is D-032 restated for a fifth carried thing, and `config` is the three
# new lobby dials through `to_dict`/`apply_dict` and out the far side of both
# clamps: a field missing from `MatchConfig._FIELDS` is a setting the host
# changes and nobody else ever sees.
#
# The channel is shortened to 1.5 s for the run; every assertion is written as a
# fraction of it. Headless, and it quits itself in about four seconds.
check "a potion heals over two seconds" "drop PASS"     "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- potion
also "a potion heals over two seconds" "channel PASS"
# `hands PASS` is the fists, with something in one of them (D-075). D-067 made a
# drink empty both of them — `has_spear()` and `has_bow()` each grew a
# `not is_channelling()` clause, put in the **gate** so that the hand obeys a
# drink rather than only the throw refusing one — and proved it with a contact
# sheet of a Bog raising nothing. An empty hand is a weak thing to assert: it is
# also what a broken attachment, a missing model and a Bog that never started
# drinking all look like. So this reads the fists half way through the channel
# and requires a **bottle in the drinking one** and the spear, the bow, the arrow
# and the great sword all out of both, and then requires, one frame after the arm
# comes down, that the bottle is gone and the fist agrees with `has_spear()`
# again — which is `_end_channel` calling `_refresh_hand` on that frame rather
# than leaving it to the next frame's poll (D-069).
also "a potion heals over two seconds" "hands PASS"
also "a potion heals over two seconds" "interrupt PASS"
also "a potion heals over two seconds" "moved PASS"
also "a potion heals over two seconds" "death PASS"
also "a potion heals over two seconds" "config PASS"
# The great sword, end to end (D-068). Four verdicts out of one run, and the
# first *step* of the run is not a verdict at all — it is a rehearsal, because
# nothing in this mode can be placed until somebody has measured where the blade
# actually is. `Swing` turns the body through a whole revolution inside the
# skeleton, and the mode prints what that costs: at the release the blade is
# **55 to 66 degrees off the Bog's own facing** (the spread across runs is where
# the fade-in lands against a body doing 222 degrees a second), so a sweep taken
# along `-basis.z` would point at empty grass every time and would look correct
# in every code review. Every dummy after that is stood on the bearing the
# rehearsal measured, which is the only reason the rest of the mode can place
# anything at all.
#
# `hand` is the promise the fists make, asked on every one of the 112 ticks of a
# swing rather than at either end of it: the sword is there from the click to
# the last frame of the spin and the spear and the bow are not, and outside that
# window all three are the other way round. `release` is the timing read two
# ways off one swing — the kill lands `BogAnimator.SWING_RELEASE_TIME` after the
# click to within a frame and a half, within three ticks of the blade's own
# full extension — and it carries the measurement the reach dial is fitted to,
# 1.43 m of blade against a 1.43 m dial. That second reading is the only line in
# this gate that checks a *melee* constant against the animation it was cut
# from, and it is what would notice a window moved without the release moving
# with it. `reach` is the mechanic: 0.35 m inside the dial is a kill and 0.35 m
# outside it is a survivor, with the distance each dummy actually was at the
# instant of the hit printed beside it. `elder` is D-040 restated for a fourth
# weapon — a direct hit takes nothing and still flashes the ward.
#
# Headless, and it quits itself in about four seconds.
check "a great sword swing kills" "sword PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- sword
also "a great sword swing kills" "hand PASS"
also "a great sword swing kills" "release PASS"
also "a great sword swing kills" "reach PASS"
also "a great sword swing kills" "elder PASS"
# The sword in both fists, and the blade out of the floor (D-068). The great
# sword is two-handed, so its size is not a number anybody picked: it is
# `|the left fist - the right fist|` across the swing divided by the hilt the
# model has to span, which is the same shape `preview_bow -- measure` solves for
# a string that has to meet the drawing fingers. `fit` is that equation holding —
# the pommel stays inside the rear mitten at every sample — and `blade` is the
# point staying above the limit the follow-through authors. The same run prints
# the constants, so a grip going stale is caught by the run that would have been
# used to fix it. Headless; nothing is rendered and the PNG is thrown away.
check "the great sword fits both fists" "fit PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" --script tools/snapshot.gd -- \
    res://tools/preview_sword.tscn "$GODOT_LOG_DIR/sword_measure.png" 4 measure
also "the great sword fits both fists" "blade PASS"
# **Every carried weapon out of the grass and out of the Bog** (D-070), under the
# layer the game actually composes.
#
# This replaces the sword's own carry check and is stronger than it was.
# `preview_sword -- carry` measured one prop rigidly attached to the locomotion's
# own bare arms, which is how every weapon in this game was carried until a carry
# pose existed — and the tilt it swept, `SWORD_CARRY_TILT`, is gone: a clip drawn
# holding a great sword leaves a tilt nothing to do. Now `UPPER_BODY_BONES` takes
# its pose from a looping carry clip in every clip a Bog walks around in, so the
# height of a limb tip or a blade is a function of the *composed* pose, and this
# is the only tool that composes it — a bone at a time, exactly as the `carry`
# Blend2 does.
#
# Two floors, both of them D-065's: nothing may come within 0.15 m of the ground
# or — the spear's alone, like `LEVEL_MAX` and `PALM_MAX` and for the same reason
# — 0.06 m of the Bog's own **skinned trunk**. `SKIN_MIN` was zero for the whole
# of D-099, because `BreathingIdle` rests the fist on the hip and a number that
# reads 0.000 for all 288 candidates cannot tell a shaft along a belly from one
# through it. The spear has its own carry pose now (`SpearCarry`, D-103), so the
# floor is back at D-074's 0.06 and `carry PASS` means the shaft clears the trunk
# by it as well as clearing the grass. The bow's trunk column is printed and
# decides nothing — it reads 0.002 m for a bow leaning on a body and would read
# the same for one inside it, which is the confusion the floor was disarmed over
# in the first place. Both floors hold over twelve clips and twenty-four
# samples of each, with the carry loop walked across its own length underneath so
# that a row is the worst of two cycles beating rather than one frame held
# against another. The trunk is the real mesh — every head- and torso-weighted
# vertex, skinned by the formula the GPU runs — because the three small
# ellipsoids an earlier pass stood in for a Bog with are what let a shaft ship
# through the chin.
#
# `derived PASS` is the second line and is about **constants**:
# `HeldGear.GRIP_OFFSET` has to equal `grip_offset(GRIP_ROTATION)`, and GDScript
# cannot call a static to initialise a const, so this recomputes it and fails if
# the two have drifted. D-065's own comment asked a human to do that by hand.
# `POTION_GRIP_OFFSET` is the second one to hang off it (D-075) and the first
# whose derivation carries a **scale** as well as a rotation, so it is the one
# that goes stale if somebody decides the bottle looked chunky. One verdict for
# both, because they are one statement.
#
# Headless, about forty seconds — the skin scan is 3,587 vertices a sample.
check "every carried weapon clears the ground" "carry PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" --script tools/snapshot.gd -- \
    res://tools/preview_carry.tscn "$GODOT_LOG_DIR/carry_measure.png" 4 measure
# And `head PASS`, which is the **bow's** floor and the one the three above could
# not be. The owner, of the shipped carry: *the top limb passes through the
# nose.* It did — and every number in this run said the bow was fine, because the
# floor is about grass and the trunk column reads the same 0.002 m for a limb
# leaning on a body as for one through a face. `HEAD_MIN` asks the half of the
# body a leaning limb never touches: the nearest distance from the limb segment
# to the head's own skinned vertices and to the `Neck`/`Head`/`HeadTop_End`
# joints, 0.06 m, the spear's own `SKIN_MIN` one weapon over. D-110 is why it is
# needed now rather than at D-066 — the carry layer used to turn the head 58 deg
# away, so the face was out of the limb's path by accident, and `untwist` put it
# back in. A clearance nobody measures is a clearance that gets spent.
also "every carried weapon clears the ground" "head PASS"
also "every carried weapon clears the ground" "derived PASS"
# And `card PASS`, which is about a **third** number the grip carries. The letter
# card rides `CARD_ALONG_SHAFT` along the shaft out of the spear hand, derived
# from `GRIP_ROTATION` rather than written down, precisely so re-aiming the grip
# carries the card with it (D-035) — and D-070 re-aimed it by eighty degrees, so
# the 0.22 m that used to point up the forearm now points across the body. It is
# **negative** since D-103: the carry pose runs the shaft out through the
# fingers, which point at the ground when the arm hangs, so the card slides
# *down* the shaft at −0.22 instead of up it. D-035
# measured the bottom of the letter at 0.23 m off the ground and wrote it into a
# comment; it is 0.165 m now — D-110 re-aimed the grip and the card rode the
# shaft round with it, which is exactly the point of deriving it — it is a
# check, and the pose it is measured in is
# the one a Bog holding a letter is actually in — a hold disarms it, so the carry
# layer is off for the whole of one.
also "every carried weapon clears the ground" "card PASS"
# And `level PASS`, which is the **fourth** number and the one this file was
# missing (D-072). The three above are clearances and have never gone stale; the
# spear's flatness was a sentence in a comment and went stale twice in two steps,
# both times the same way — a clip arrived or was remirrored and nothing re-ran
# the spear against it. D-065's floor promise died to D-066's six new clips and
# D-070's "within 5 degrees" died to D-071's remirrored strafes, which said 5
# while the rig did 14. It is `LEVEL_MAX` now, it is 30, and a clip that swings
# the shaft past it fails here on the commit that lands it instead of being found
# two steps later by somebody measuring something else.
also "every carried weapon clears the ground" "level PASS"
# And `palm PASS`, which is the **fifth** and is about the hand rather than the
# Bog (D-074). Everything above asks where the spear is relative to the body, the
# floor or the horizon, and none of it can see the thing the user actually said:
# *"the spear visually is just outside the hand... it appears as if its attached
# to the back of the hand."* A shaft riding the knuckles is exactly as far from
# the trunk, exactly as level and exactly as high off the grass as one in the
# fist, so four green lines sat under a grip whose shaft passed **outside the
# mitten altogether** — 0.076 m from the centre of a fist 0.132 m thick.
#
# It went unseen because the only thing `GRIP_PALM` had ever been checked against
# was the `RightHand`-weighted skin at rest, which is the wrist: 918 of the
# mitten's 1,030 vertices hang off the three finger chains and none of them were
# in that span. This measures the whole mitten, skinned in the carry pose, and
# requires the shaft's axis to pass inside it (`PALM_MAX`). The spear reads
# 0.034 m now — 0.050 is the *bottle's* figure, in the `bottle PASS` note below,
# and the two were confused in this comment for three decision records — and
# D-072's grip reads 0.076 and fails it.
also "every carried weapon clears the ground" "palm PASS"
# And `bottle PASS`, which is the **sixth** and is `palm` asked of the other
# hand (D-075). The heal potion is the first thing this game puts in a fist that
# is not a weapon, and D-067 shipped the drink as a mime with empty hands and
# said so: *"rejected for now: a potion model in the fist... the bow's grip took
# a dedicated `preview_bow -- measure` to solve and the drinking hand would need
# the same."* That tool is `palm`, and this is it run over `LEFT_FIST_BONES` in
# the pose `Drink` puts the hand in.
#
# It is also the line that would have caught the thing that went wrong while it
# was being fitted. `HeldGear.fist_offset()` — the shared palm point D-068 made
# static so that three props could not have three opinions about one fist — lands
# **0.133 m** from the centre of the drinking mitten, twice `PALM_MAX`, because
# the hand `Drink` opens round a bottle is 9.5 cm further out along its own axis
# than the fist `SpearCarry` closes on a shaft. The rule survives and the number
# does not; `HeldGear.POTION_PALM` is the argument and this is the check.
#
# It reads 0.050 m of 0.066 allowed, and the 0.050 is spent rather than wasted:
# a bottle centred in that mitten spends half its belly inside the Bog's own
# stomach, because the drinking arm rests against a body that is a pear.
also "every carried weapon clears the ground" "bottle PASS"
# **A grip is still the grip its own clips solve for** (D-073), which is the
# general form of the fault the four steps above kept hitting one at a time.
#
# `level` made the spear's flatness a check instead of a sentence. This makes the
# *derivation itself* one, for the prop whose constants are not a function of
# each other but of a clip: `SWORD_SCALE`, `SWORD_GRIP_OFFSET` and
# `SWORD_GRIP_ROTATION` are seventeen poses of `Swing` averaged, so the only
# honest way to ask whether they are current is to average them again and
# compare. That is what `hilt` does, and it costs seventeen poses and no skin
# scan, which is why it can be its own tiny mode rather than a second forty-
# second run.
#
# Three ways to fail and they are three different accidents: `fit`, the clip or
# the window moved under the constants; `derived`, somebody re-aimed the rotation
# and left the offset behind, which is precisely what D-072 caught one prop over;
# and `carried`, the pose the sword is *carried* in no longer closes its second
# fist on the hilt. It found a live one on the commit it was written: the tool
# had been printing `1.2585` and `(0.6117, 0.4203, -0.8164)` against a shipped
# `1.2586` and `(0.6116, 0.4206, -0.8159)` for four steps, and nothing compared
# them because nothing could.
#
# The same run prints the two hilt lines and where the blade actually points,
# which is D-073's whole argument in four rows. Headless, about four seconds.
check "the great sword's grip still fits its clips" "hilt PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" --script tools/snapshot.gd -- \
    res://tools/preview_carry.tscn "$GODOT_LOG_DIR/carry_hilt.png" 4 hilt
# **One button, four weapons** (D-070), pressed on a keyboard rather than called.
#
# `throw_spear`, `draw_bow` and `swing_sword` are one `primary_attack` on the
# left mouse button, and the thing that makes that non-trivial is that the four
# weapons do not read it the same way: a spear, a swing and the Elder's bolt fire
# on the **press** and a bow charges while it is **held** and fires on the
# **release**. So the mode presses the one action on a Bog carrying each in turn
# — moving the weapon the way the lobby moves it, `Bog.weapon` and then
# `refresh_hand()` — and requires the right thing to have started on the tick
# after: a windup, a draw, a spin, and a windup again for the Elder.
#
# `Input.action_press` and not `try_throw_spear`, which is the opposite of what
# every other mode in `combat_range` does and is the whole point of this one. The
# question is about the poll in `BogCombat._process` — one action, asked
# unconditionally, four weapons refusing themselves — so the press has to be a
# real press or the poll is not what is being checked.
#
# `hold PASS` is the second meaning of the same button and the half that is easy
# to fake: the bow's round holds the button for forty ticks, requires the draw to
# still be running on every one of them and to have reached past half charge, and
# then requires letting go to have loosed. Written with a one-tick release first,
# it passed against a Bog that had snap-fired at 0.02 charge and spent the rest
# of the round on a cooldown. Headless, about four seconds.
check "one button for every weapon" "primary PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- primary
also "one button for every weapon" "press PASS"
also "one button for every weapon" "hold PASS"
# The input map, checked rather than read (D-070).
#
# **This check exists because of a bug nobody could see.** D-068 put
# `swing_sword` on physical keycode 82 and `respawn` was already there — the
# potion step had steered away from `R` for that reason one step earlier — so for
# two decision records the sword and the respawn were the same key and nothing
# anywhere could say so. A binding table is data and a clash between two rows is
# arithmetic; all that was missing was somebody doing it.
#
# Three things: every action the settings panel's controls reference names is in
# the map, because `primary_key` answers "Unbound" for one that is not and a
# reference page full of "Unbound" is a page nobody reads twice; no two actions
# in the whole project share a key or a mouse button, `ui_*` excepted because
# Godot's own are meant to overlap; and the three actions D-070 retired are gone
# rather than orphaned, since a key that is bound to nothing being polled is
# worse than one that is not bound at all.
check "no two controls share a key" "controls PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" --script tools/snapshot.gd -- \
    res://tools/hud_range.tscn "$GODOT_LOG_DIR/controls.png" 40 controls
# A shaft standing in a Bog who is still alive, and then in the corpse that Bog
# becomes (D-062). This is the half of the damage model that is not a number:
# until now a projectile that hit somebody who lived had nowhere to go, because
# `_stick_in` hid it and waited for a corpse, and the Elder was the only case
# there was. Partial damage makes it the common case, and the bow makes it the
# rule.
#
# The spear is launched by hand with nothing listening for its hit, so it damages
# nobody — which is the only way to get a *living* victim with a shaft in it in a
# build whose only weapon is a one-shot. `embed` then moves the dummy two metres
# and requires the shaft to arrive with it: a spear parked in the air where a Bog
# used to be looks identical to one riding the Bog until the Bog moves. `adopt`
# kills that dummy and requires the same shaft to end up hanging off a physical
# bone of the corpse, with nothing left waiting on the Bog's own list — a shaft
# on an invisible list is the bug `SpearProjectile._glance_off` was written to
# avoid and the one this mechanism could quietly reintroduce.
#
# With the ride removed, `embed` fails with the shaft 2.00 m adrift; with the
# hand-over removed, `adopt` fails with the shaft still parented to the arena.
# Headless, and it quits itself around tick 40.
check "a shaft rides a living Bog" "embed PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- embed
also "a shaft rides a living Bog" "adopt PASS"
# Bunny hopping (D-052). The local Bog runs the range as itself, as the Elder
# and as a capture carrier: ten hops pressed on the first ground tick have to
# climb past 1.15x run speed and stop at the 1.3x cap, while running, one jump,
# a hop pressed a quarter-second late and a hop out of a dive roll may not beat
# run speed. Against the movement before D-052 every subject tops out at 1.00x;
# with LANDING_GRACE stretched to five seconds the late hop keeps its bonus.
#
# Headless and `--fixed-fps 60`, so it is ~2 s rather than three runs of real
# time, and every tick is the same length as the game's.
check "bunny hops carry, up to a cap" "bhop PASS" \
    "$GODOT" --headless --fixed-fps 60 --path "$GODOT_ROOT" tools/combat_range.tscn -- bhop
# And the other half of that budget (D-068). The great sword's swing feeds its
# impulse into the **same** momentum the bunny hop uses, under the same
# `HOP_SPEED_CAP`, rather than having a speed system of its own — so this is
# D-052's measurement repeated with a sword in hand, and what it asserts is that
# there is one ceiling and not two.
#
# Two subjects. A Bog at a dead stop chains eight swings: the first leaves it at
# 2.00 m/s (the clip's own 0.917 plus `SPIN_GAIN` of run speed) and the last
# starts from **7.02**, which is 1.30x run and is exactly the cap. A Bog that
# builds 7.02 with ten timed hops first and then swings has to *keep* it — if
# `begin_spin` ever went back to simply setting the clip's own speed, that is
# the line that notices and every other line here still passes. Neither may go
# past the cap.
#
# Headless, and **not** `--fixed-fps`, which is the one place this differs from
# `bhop` above. A hop is timed in ticks and a swing is timed on the wall clock —
# `Bog.is_spinning()` and `MatchConfig.sword_recharge` are both
# `Time.get_ticks_msec` deadlines, like every other cooldown in `BogCombat` — so
# at a forced tick rate the simulation runs far ahead of the clock the spin is
# waiting on and a Bog advances thirty times as far through a swing that never
# ends. Twenty-odd seconds of real time is what the honest version costs.
check "swings chain into the hop budget" "chain PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- chain
# The feel round's movement, on a flat floor with two real Bogs (D-123). Four
# claims, and each of them is a number the physics either produces or does not:
# a full draw walks at WALK_SPEED x DRAW_SPEED_SCALE (1.15 m/s), crouch at run
# speed with **no sprint** starts a slide and a jump out of it leaves at 1.2x
# the slide along the slide's own heading with 1.12x the lift, a run-speed
# landing with crouch held is sliding on the tick it touches down and plays
# neither Land nor LandHard, and the slide jump's serial reaches a Bog this
# machine does not own - copied field by field out of the replication config
# `scenes/player/bog.tscn` ships, so a field left out of that config fails here
# rather than in a match.
#
# Headless and `--fixed-fps 60`, like `bhop`: every one of these is counted in
# physics ticks, and a slide is a second long.
check "movement" "movement_check: PASS"     "$GODOT" --headless --fixed-fps 60 --path "$GODOT_ROOT" tools/movement_check.tscn
also "movement" "movement_check: draw PASS"
also "movement" "movement_check: slide_jump PASS"
also "movement" "movement_check: landing PASS"
also "movement" "movement_check: remote PASS"
# Bogs in their team's colour (D-046), read off the material the renderer will
# draw with rather than off what the script meant to set. One Bog per team has
# to be in exactly its nameplate colour, a free-for-all Bog has to be back on the
# imported yellow, the Elder's robe has to keep its purple over a tinted body,
# a corpse has to die in the colour it lived in, and a lobby roster change has to
# repaint the Bog whose team moved. The corpse half fails against a ragdoll that
# copies the mesh's own material, and the lobby half against a backdrop that
# only recolours the plate. Headless, it quits itself on tick 12. The lineup:
#     ... --resolution 1800x640 --script tools/snapshot.gd -- \
#         res://tools/team_tint.tscn out/team_tint.png 40 studio|dusk|noon
check "team colours on the body" "team_tint: teams PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/team_tint.tscn
also "team colours on the body" "team_tint: robe PASS"
also "team colours on the body" "team_tint: corpse PASS"
also "team colours on the body" "team_tint: PASS"
# Which side you are on, said plainly (D-047). A player: "it should be obvious
# what team you are on and who your teammates are". Through the real spawn path,
# with a wall between the local Bog's camera and a teammate and an enemy forty
# metres behind it — the ray that proves the wall is in the way is a verdict of
# its own, so this cannot pass on open air. The teammate's plate has to ignore
# the depth test, be up and at full alpha out there; the enemy's, beside it, has
# to be depth-tested and faded exactly as before, because a plate through a wall
# is a wallhack and only a teammate's is allowed to be one. The HUD's chip has to
# say TEAM 1 in team 1's colour. Against `set_ally(false)` the ally half fails;
# against `set_ally(true)` the enemy half does, and so does the free-for-all run,
# which also wants the chip hidden and every plate at its old size. Headless,
# both quit on tick 30. The picture, from the Bog's own camera:
#     ... --resolution 1600x900 --script tools/snapshot.gd -- #         res://tools/team_plates.tscn out/team_plates.png 40
# The lobby weapon pick, which is a roster key and therefore a *wire* feature
# before it is a UI one (D-069). `match_rules` already covers the half that is a
# Bog — the gate, the hand and the three overrides that take a weapon away — so
# this covers the half that is a row: the default for a row that never heard of
# weapons, the request going through the host and coming back on the rebroadcast,
# a bogus ordinal refused into a spear, the lock the moment Start is pressed, a
# rematch keeping the pick, and the real lobby scene in the shape D-107 gave it:
# the strip up beside the panels rather than behind a collapse button, the three
# panels folding to their own headings on their own toggles, and the match config
# gone entirely for a client instead of greyed out. Its `ring` stage is the one that matters most and is the cheapest to
# lose: three **remote** Bogs in the backdrop, each holding only what its row
# says, which is the lobby half of "show only the weapon you selected".
#
# Headless; it instances the real lobby and the real glade and quits itself in
# about two seconds.
check "a weapon picked in the lobby" "weapon_select: PASS"     "$GODOT" --headless --path "$GODOT_ROOT" tools/weapon_select.tscn
also "a weapon picked in the lobby" "weapon_select: roster PASS"
also "a weapon picked in the lobby" "weapon_select: lock PASS"
also "a weapon picked in the lobby" "weapon_select: lobby PASS"
also "a weapon picked in the lobby" "weapon_select: ring PASS"

check "teammate names through walls" "team_plates: ally PASS"     "$GODOT" --headless --path "$GODOT_ROOT" tools/team_plates.tscn
also "teammate names through walls" "team_plates: enemy PASS"
also "teammate names through walls" "team_plates: hud PASS"
also "teammate names through walls" "team_plates: PASS"
check "free-for-all names unchanged" "team_plates: ffa PASS"     "$GODOT" --headless --path "$GODOT_ROOT" tools/team_plates.tscn -- ffa
# A letter picked up is told to everyone (D-050). A player: "some kind of
# notification when someone picks up a letter, maybe it should also show people
# with letters through walls". Through the real spawn path, the real HUD and real
# cards walked into through `claim_pickup`: a card that starts a hold has to put
# "Nettle picked up G" at the top of the feed, and a duplicate wasted on touch has
# to put nothing there. Two carriers forty metres behind a wall (proven by ray)
# have to have their marker up, with their letter, undepth-tested and above the
# nameplate — one of them an enemy, because the marker is for everyone — while
# the local player's own hold marks nothing on their own screen. After a hold is
# banked, and after a carrier is killed, the marker has to be gone. Without
# `_refresh_carrier_marker` the marker verdict fails; without the
# `letter_picked_up` emit both feed verdicts do. Free-for-all runs the same
# sequence. Headless, it quits itself on tick 160. The picture:
#     ... --resolution 1600x900 --script tools/snapshot.gd -- #         res://tools/letter_carriers.tscn out/letter_carriers.png 45
check "letter pickups told to everyone" "letter_carriers: PASS"     "$GODOT" --headless --path "$GODOT_ROOT" tools/letter_carriers.tscn
also "letter pickups told to everyone" "letter_carriers: feed picked up PASS"
also "letter pickups told to everyone" "letter_carriers: duplicate PASS"
also "letter pickups told to everyone" "letter_carriers: marker PASS"
check "free-for-all letter carriers" "letter_carriers: ffa PASS"     "$GODOT" --headless --path "$GODOT_ROOT" tools/letter_carriers.tscn -- ffa
# The camera, kept out of the scenery (D-045). A player: "too frequently the
# camera is inside meshes and stuff when there are meshes behind the character".
# Seven legs — a wall on each shoulder walked along, a corner, under a canopy and
# at its edge, a wall at the Bog's back with the view swung and flicked through
# it, and a low tunnel walked through — 1,700 frames, each asked three ways
# whether the lens is inside collision: a point query, a near-plane sphere, and a
# ray from the eye (is it behind a wall). Against the old spring arm 942 of the
# 1,700 fail, in every leg.
#
# The first `also` is the half that keeps D-025 true: the point a throw is aimed
# at is required, every frame, to be the one the *unobstructed* camera would give
# for the same view. With `aim_ray` taken from the pulled-in lens instead, 1,030
# frames fail. `--fixed-fps 60` so a tick of view-turning is the same on every
# machine; headless, about two seconds.
#
# The second is the framing (D-083): the lens is never allowed further off the
# boom's axis than the unobstructed camera would be at the depth the boom got to,
# so the Bog keeps its place in the frame while the camera comes in. With the
# shoulder held at its full length through the pull-in, 1,461 frames fail, by as
# much as 0.62 m — which is a Gub sliding most of a screen width sideways, the
# same way whichever way the player was turning.
#
# The third is how the lens *moves* rather than where it ends up (D-086), which
# is what is left once the placement is right: no frame may turn the lens more
# than 1.2 degrees on its own, and the frames that dolly it faster than 5.4 m/s,
# or reverse its direction, stay under 4 % each. Without the lead sweeps, the
# split pull-in and return speeds, the hold and the rate-limited reticle
# correction, that is 241 frames over the step limit against 64 allowed and a
# 13.8-degree single-frame snap of the whole picture with nobody at the mouse.
check "camera stays out of the scenery" "clip PASS" \
    "$GODOT" --headless --fixed-fps 60 --path "$GODOT_ROOT" tools/camera_range.tscn
also "camera stays out of the scenery" "aim PASS"
also "camera stays out of the scenery" "frame PASS"
also "camera stays out of the scenery" "calm PASS"
# Menu to results screen, through the real scenes and the real autoloads. The
# only check here that can notice a *join* coming apart — a lobby that never
# hands off to the arena, an arena that never registers, a results screen that
# never opens — none of which any single-seam harness can see, because each of
# those is the absence of a call rather than a fault inside one.
check "full playthrough" "playthrough: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/playthrough.tscn
# ---------------------------------------------------------------- combat ---
# The feel round's fists, emote and sword, out of the run above rather than out
# of a second one. They are `also` lines and not a `check` of their own on
# purpose: every claim is about two Bogs standing on the arena's own floor after
# the real menu, session, lobby and warmup, so the run that already walked all
# of that is the run that can make them — and repeating it would be ten seconds
# spent building an island twice to ask a different question of the same two
# bodies.
#
# `fists` is the holster: a key that takes the weapon away, three gates that
# answer no while it is gone, two empty fists, and the tenth of a metre a second
# that buys (2.53 against 2.30, which is `FISTS_SPEED_SCALE` read out of
# `target_speed` itself rather than off the constant).
# `punch` is the attack that is left: 20 at 1.1 m inside a 50-degree front, and
# **nothing at the same range behind**, which is the half that says a punch can
# miss. `Bog.Cause.FIST` arrives on `hit_landed` with it and `RangeStats` has no
# row for it, so the practice panel counts weapons and not hands.
# `emote` is D-105's dance with its hands emptied, and the prop back in the fist
# one frame after it ends — plus the holster refused mid-draw, which is the one
# `can_holster` clause a player will actually meet.
# `sword` is the chain: 50 + 50 kills at `sword_reach` plus the step, a third
# click chains and a fourth is refused by the clip's own three windows, and the
# same button at run speed still fires D-068's committed spin for the whole 100.
also "full playthrough" "combat fists PASS"
also "full playthrough" "combat punch PASS"
also "full playthrough" "combat emote PASS"
also "full playthrough" "combat sword PASS"
also "full playthrough" "playthrough: combat PASS"
# ------------------------------------------------------------ end combat ---
# Capture B·O·G's bases and letters on this map (D-051), from the same run: two
# bases on distinct pads well apart, each team with pads of its own, and three
# letter points on a real floor with a Bog's head room, outside both bases and
# apart. This map declares no objectives of its own, so this is the fallback
# being proven playable; Rust and Kopje Crossing carry the same line below, and
# Lantern Wharf carries it for a layout the map declares itself (D-056).
also "full playthrough" "playthrough: capture layout PASS"
# The same walk again on the hand-made map, which is a different branch in
# `arena.gd` from the first frame: no generation, an instanced scene bringing
# its own environment, sun, collision and spawns, and a void height a metre or
# two under the floor instead of forty-five (D-030, D-031). Two checks, because
# they fail differently — the first says the whole flow still works on a static
# map, the second says it was actually Rust that was built and not the island
# quietly falling back to itself.
check "rust playthrough" "playthrough: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/playthrough.tscn -- rust
also "rust playthrough" "arena: Rust built from"
also "rust playthrough" "playthrough: capture layout PASS"
# And on Kopje Crossing, the map with no `.glb` behind it (D-042). It is the
# same `arena.gd` branch as Rust, which is exactly why it gets its own run: the
# branch is shared but the build is not, and a hundred and twenty-three
# platforms laid out of a table in `_ready` is a very different thing to fall
# over from a scene that was imported once. The `also` is the same guard as
# Rust's — that it was the savanna that got built, not the island in its place.
check "safari playthrough" "playthrough: PASS"     "$GODOT" --headless --path "$GODOT_ROOT" tools/playthrough.tscn -- safari
also "safari playthrough" "arena: Kopje Crossing built from"
also "safari playthrough" "playthrough: capture layout PASS"
# And on Lantern Wharf, the small built map (D-056): a box yard laid out of a
# table like the savanna, so the same three lines — and a fourth, because it is
# the first map to declare its own Capture B·O·G bases and letters rather than
# leave them to the fallback, and a layout that quietly fell back would still
# pass the third.
check "wharf playthrough" "playthrough: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/playthrough.tscn -- wharf
also "wharf playthrough" "arena: Lantern Wharf built from"
also "wharf playthrough" "playthrough: capture layout PASS"
also "wharf playthrough" "capture layout on 'wharf' — declared bases"
# And on Halcyon Wake, the tall built map (D-057): a yacht of four decks laid
# out of a table, standing on a sea that is not collision. The same four lines
# as Lantern Wharf's, because it declares its own bases and letters too — one
# of them two decks up, the first letter any map has put off the main floor.
check "yacht playthrough" "playthrough: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/playthrough.tscn -- yacht
also "yacht playthrough" "arena: Halcyon Wake built from"
also "yacht playthrough" "playthrough: capture layout PASS"
also "yacht playthrough" "capture layout on 'yacht' — declared bases"
# A Capture B·O·G match standing up in the real arena (D-051): `arena.gd` draws
# And on Twin Quarry, the map drawn for Capture G·U·B rather than fitted to it
# (D-082): a stone pit whose two bases stand four metres up on cut benches with
# two haul ramps each. Same four lines again — it declares bases and letters
# too, and its letters are the first that are not three neutral points.
check "quarry playthrough" "playthrough: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/playthrough.tscn -- quarry
also "quarry playthrough" "arena: Twin Quarry built from"
also "quarry playthrough" "playthrough: capture layout PASS"
also "quarry playthrough" "capture layout on 'quarry' — declared bases"
# And on Highsun Grounds, the practice range (D-112, by day since the range wave). The same walk again, and
# then a different ending: a practice map has no clock and no win check, so the
# run swaps the kill loop and the results screen for a stage that proves what
# unit 1 of the range actually built. The four `also` lines are the four claims
# that could each be quietly wrong while the run still passed — the map brought
# its dummy registry, a dummy is hidden from every roster-derived screen, the
# host really is the peer publishing a dummy's transform (checked inside the
# stage, because a host sees its own dummies move either way and only a client
# would ever notice), and a map-placed pickup can be claimed.
check "range playthrough" "playthrough: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/playthrough.tscn -- range
also "range playthrough" "arena: Highsun Grounds built from"
also "range playthrough" "playthrough: practice PASS"
also "range playthrough" "playthrough: the range brought a RangeDummies node"
also "range playthrough" "playthrough: dummies are hidden from every roster screen"
also "range playthrough" "playthrough: a placed pickup was claimed"
# The eight dummy behaviours, the stats signboard and the parkour clock, on a
# bare fixture and then on Highsun Grounds itself. A dummy has no physics at
# all — its Bog node is authored by a peer that does not exist, so
# `move_and_slide` never runs on any machine — which means every brain is a
# position as a function of time and every one of them can be wrong in a way a
# screenshot would not show. The four `also` lines are the four that were: the
# jumper's arc is solved rather than integrated (an integrated one sinks through
# the floor over a session), the rusher drops a chase when its target walks out
# of the zone rather than running at the inside of its own fence for six
# seconds, the pop-up goes 2.6 m *under* the floor because crouching hides 20 cm
# behind a 1.25 m wall, and a run that ends in the void is reported as negative
# seconds rather than not at all.
#
# The `signboard` line replaces a `station` one. The six walk-in stations and
# their behaviour rings are gone: a zone's mix is authored in the map and never
# changes, so what is left to assert is that the one control still on the range
# calls the counter and touches nobody's brain on the way past.
check "dummy brains" "range_brains: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/range_brains.tscn
also "dummy brains" "range_brains: jumper PASS"
also "dummy brains" "range_brains: rusher PASS"
also "dummy brains" "range_brains: popup PASS"
also "dummy brains" "range_brains: signboard PASS"
also "dummy brains" "range_brains: parkour PASS"
# The wells, the refill stone and the weapon racks. The re-mint is the well's
# whole behaviour and it has two ways to be silently dead — a stock that rots
# after thirty seconds emits no `pickup_taken` and so never re-mints, and a
# robe pedestal on the shield's four-second timer turns the ability yard into a
# place where somebody is permanently unkillable — so both timers are asserted
# rather than eyeballed. The rack's line is the one that matters most: a weapon
# was fixed for the match by a *lobby* rule and never by the code, and the swap
# has to land on the Bog, the hand and the roster row (so a respawn keeps it)
# inside the overlap signal itself, which is how "within one frame" is proven.
check "range items" "range_items: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/range_items.tscn -- all
also "range items" "RangeItems: 4 wells, 3 racks, 1 refill stone(s)"
also "range items" "range_items: a well re-minted 4.0 s after it was taken PASS"
also "range items" "range_items: the refill stone raised 0/0/0 to 2/2/1 PASS"
also "range items" "range_items: a full Bog got nothing and no chime PASS"
also "range items" "range_items: a rack swapped spear to bow on the Bog, the hand and the roster within one frame PASS"
# Boards and the gong: things to shoot that are not Bogs, reached through
# `range_hit` rather than through the damage door, which stays keyed by peer id.
# The board's rings and the gong at the spear's measured flat 28 m are two
# different answers to "what becomes of the projectile", and the last `also`s
# are the counter: a hit files under the weapon that threw it, and the reset
# zeroes every row. There was a third answer — a glowing orb that took the
# shaft with it when it burst; it went with the orbs in the range wave, which
# took every bare unshaded sphere off the map.
check "range targets" "range_targets: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/range_targets.tscn
also "range targets" "range_targets: board scored 3, 2, 1 by ring"
also "range targets" "range_targets: the gong rang at 28.0 m"
also "range targets" "range_targets: 1 throw, 1 hit, 1 kill, accuracy 100%"
also "range targets" "range_targets: a board hit files under the weapon that threw it"
also "range targets" "range_targets: reset zeroed every row"
# A Capture G·U·B match standing up in the real arena (D-051): `arena.gd` draws
# a ring per team, the host settles three cards onto the map once the physics
# has stepped, and every Bog spawns on a pad of its own team's. The rules
# themselves — carry, bank, the enemy base doing nothing, a dead carrier's drop
# and its return, an enemy recovering it, winning — are `match_rules`, in a box
# with a floor. Headless, a few seconds. The picture from above Team 1's base:
#     ... --resolution 1600x900 --script tools/snapshot.gd -- \
#         res://tools/capture_preview.tscn out/capture_base.png 150 safari
check "capture match on a real map" "capture_preview: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/capture_preview.tscn -- safari
# Every map bakes a navmesh the guide line can be drawn on, and you can get from
# the first spawn pad to the last over it (the letters round). The line is local
# and cosmetic, so nothing here is a rule — but a bake that collapses to nothing
# after a layout change is a line that vanishes in a match, and the census per
# map is in the log for exactly that. Headless; every map is stood up in turn.
check "navmesh on every map" "nav_check: PASS"     "$GODOT" --headless --path "$GODOT_ROOT" tools/nav_check.tscn
also "navmesh on every map" "nav_check: hollow"
also "navmesh on every map" "nav_check: range"
# The capture performance, measured on one Bog (the letters round). Four
# structural claims out of one run, and each of them is a thing three files have
# to agree about: the pouch is in the left fist (`HeldGear`), the card is *not*
# in the right one (`BogCombat._refresh_hand` — a carry only, now), the pouch
# mouth is below the raised hand, and the floating letter is on the line between
# the two (`CaptureRig`). It also prints both anchors and the descent in world
# metres, which is how `POUCH_GRIP_OFFSET` and `POUCH_GRIP_ROTATION` — the only
# grip constants in this repo written down rather than solved — get read off a
# render and corrected. Headless, about four seconds.
check "the capture performance" "capture PASS"     "$GODOT" --headless --path "$GODOT_ROOT" tools/preview_capture.tscn -- f=0.5
# The two-process test, `tools/net_test.sh` (roster, config, chat, a kill, a
# respawn, a disconnect, and D-044's ten rematches), is deliberately not in the
# gate: it adds about 45 s to every run for a path that changes rarely. Run it
# by hand after touching `net.gd`, the lobby, the results screen or
# `MatchState.reset`.
echo

# These need a real window: Godot's headless driver uses the dummy rasteriser
# and renders nothing, and the physics still has to run for a corpse to fall.
echo "rendered checks (a window will flash)"
# 155 ticks, and the window the grab has to land in is now narrow at both ends.
# The corpse spawns on tick 10 and `ragdoll_stability` prints its verdict on tick
# 150, so the frame cannot be earlier than that; and a corpse now lingers 2.5 s
# and fades over 0.8 s, so it is transparent from tick 160 and gone by 208. 155
# is a settled, opaque body with the verdict already on the log. Anything later
# would still pass — the check greps for a line printed before the grab — while
# quietly photographing a corpse mid-dissolve.
check "ragdoll survives landing" "ragdoll_stability: PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd -- \
    res://tools/ragdoll_stability.tscn "$GODOT_LOG_DIR/ragdoll.png" 155
# Match on the victim, not the killer. The killer's name is the local player
# setting, which is persisted in Godot's user-data directory (shared by every
# checkout of this project) and is whatever anyone last typed into a name box.
#
# 95 ticks. It was 110, and before that 70, and it moves for the same reason
# each time: the throw is clicked on tick 20 and the spear does not leave the
# hand until THROW_RELEASE_TIME after that (D-025), which is 0.500 s = 30 ticks.
# Not the flat half second D-063 asked for: since D-104 the ask is the throw
# clip's own `windup`-to-`release` window, and this clip's window happens to be
# 0.500 s, so the rate is 1.0 and the number is the clip's rather than a target
# imposed on it. Re-time those markers and this warmup moves with them.
# So the spear appears around tick 50; it then flies 14 m at 42 m/s
# (0.33 s, 20 ticks) and the kill lands around tick 70, leaving 25 ticks of
# margin — the same margin the 110 had over the old release, retuned down with
# it rather than left behind as slack. Worth saying out loud because a failure
# the other way would have read as a broken throw and not as a warmup that was
# too short. The magnet's 132 below needs no allowance: a magnet leaves on the click.
check "spear kills" "killed Dummy 1" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd -- \
    res://tools/combat_range.tscn "$GODOT_LOG_DIR/hit.png" 95 hit
check "magnet catches" "combat_range: magnet caught 1" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd -- \
    res://tools/combat_range.tscn "$GODOT_LOG_DIR/magnet.png" 132 magnet
# The Elder, end to end and in a world with something standing in it: a robe
# rolled out of a real death, walked over, and one bolt at a dummy fourteen
# metres away. `match_rules` proves the state machine — the robe makes an Elder,
# the clock ends it, the cooldown gates a second cast — but it has no geometry
# and nothing to hit, so the one thing it cannot prove is that the bolt kills
# anybody. That is exactly the failure a screenshot also cannot see: a bolt
# drawn beautifully past a Bog who is still standing looks identical to one that
# worked, which is why the mode prints its own verdict.
#
# 90 ticks, and the margin in it is now much larger than it was. The robe drops
# on tick 20 and is claimed on 21, the cast follows immediately, and the bolt
# leaves `lightning_delay` later — 0.2 s = 12 ticks since D-040, where it used
# to be THROW_RELEASE_TIME's 42.5 and is now its 30, which is 0.500 s because
# that is the throw clip's own authored `windup`-to-`release` window at rate 1.0
# (D-104) and not a half second anybody picked — so the kill lands around tick 34 and the
# verdict is printed 50 ticks after the cast. The hero shot of an actual bolt is
# a separate, earlier frame, and it moved with the delay:
#     ... --script tools/snapshot.gd -- res://tools/combat_range.tscn \
#         out/lightning.png 38 lightning
check "lightning kills" "lightning PASS"     "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd --     res://tools/combat_range.tscn "$GODOT_LOG_DIR/lightning.png" 90 lightning
# The bolt's blast radius (D-053), measured: three exact casts through the
# host's own `_host_cast_lightning`, one between a dummy 0.2 m inside the radius
# and one 0.2 m outside it, one into the ground in front of a wall with a dummy
# inside the radius behind it, and one into an Elder's chest. The mode prints a
# verdict per case and `blast PASS` only if every one held, plus the config
# field's round trip. 140 ticks: the last verdict is read on 120. The ring:
#     ... --script tools/snapshot.gd -- res://tools/combat_range.tscn #         out/blast.png 43 blast
check "lightning blast radius" "blast PASS"     "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd --     res://tools/combat_range.tscn "$GODOT_LOG_DIR/blast.png" 140 blast
# Kept, and now honest about what it is: this is the *placement* path —
# `try_place_shield`, the two validation rays, the broadcast, the eruption —
# and `snapshot: wrote` is all it has ever asserted. Fine as half a check and
# disastrous as the whole one. "shield stops a spear" above is the other half.
check "shield deploys" "snapshot: wrote" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd -- \
    res://tools/combat_range.tscn "$GODOT_LOG_DIR/shield.png" 40 shield
# One of each letter on the ground, measured rather than looked at (D-041).
# `match_rules` builds real cards headless, so it already proves the builder
# does not throw; what it has no way of seeing is that what came back is a mesh
# and that the mesh stands 0.60 m. That is the failure a screenshot cannot see
# either — a letter at half the height it should be is still, unmistakably, a
# letter — so the mode prints its own verdict off the mesh's own AABB. 60 ticks:
# the cards go down on 20 and the verdict is taken on 60, a quarter turn into
# the spin.
check "letter cards are meshes" "cards PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd -- \
    res://tools/combat_range.tscn "$GODOT_LOG_DIR/cards.png" 60 cards
# The spear tile's recharge readout (D-054), read off the tile every frame of
# one real throw: no sweep and no number through the windup, a sweep between 0
# and 1 and seconds within a tenth of the real remaining time once the spear has
# left the hand, both gone the frame it is back, and a crosshair with nothing
# ring-shaped anywhere in its script at any point. 270 ticks: the verdict lands
# around 240. The picture worth looking at is the same mode at 130:
#     ... --resolution 1600x900 --script tools/snapshot.gd -- \
#         res://tools/hud_range.tscn out/reload_timer.png 130 reload_timer
# The first square on the ability bar is whichever weapon this Bog actually
# brought (D-069). It has swapped to a bolt for an Elder since D-038; it now
# swaps for a lobby pick too, because two players in three would otherwise spend
# a match watching a Spear tile that is dark for all of it and times a recharge
# they are not spending — the exact misinformation D-054 cut the old ring out of
# this bar to avoid. Three loadouts through one HUD, with the glyph, the caption
# and the **key cap** required to follow: a bolt is fired by the spear's own
# button and a bow is not, so the cap is the half that is easy to get wrong and
# invisible in a screenshot of one loadout. The Elder is checked last, because it
# is the one kind that must keep the spear's button.
check "the weapon tile follows the pick" "weapon_tiles PASS"     "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd --     res://tools/hud_range.tscn "$GODOT_LOG_DIR/weapon_tiles.png" 40 weapon_tiles
check "spear reload timer on the tile" "reload_timer PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd -- \
    res://tools/hud_range.tscn "$GODOT_LOG_DIR/reload_timer.png" 270 reload_timer
# The range's own corner of the HUD: three weapon rows, each with throws, hits,
# accuracy, the longest hit and the current streak, over a hit marker caught
# mid-flash. Not headless, like the two above and for the same reason — a
# headless snapshot writes no PNG at all, so a `--headless` photo check would be
# asserting a verdict over a picture nobody took. The panel is practice-only and
# so is the damage number beside it; the *marker* is not, and that is the one
# thing unit 5 changed about an ordinary match.
check "the range panel" "hud_range: range PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 1600x900 --script tools/snapshot.gd -- \
    res://tools/hud_range.tscn "$GODOT_LOG_DIR/range.png" 110 range
# The corner map's three kinds of blip, counted rather than photographed (the
# letters round). A loose card twelve metres north-east, an enemy carrying one
# eighteen west, a teammate eight south — and the verdict read off
# `Minimap.debug_counts()` rather than off the picture, because everything that
# can go wrong here is a *rule*: an enemy with no letter drawn, an ally drawn in
# a free-for-all, a card counted that is past the rim. A rule is a number, and a
# 180 px circle scaled into a screenshot is not a thing a number can be read out
# of. Played as Teams, because a teammate does not exist in a free-for-all.
check "the minimap's blips" "minimap allies=1 letters=1 carriers=1 PASS"     "$GODOT" --path "$GODOT_ROOT" --resolution 1600x900 --script tools/snapshot.gd --     res://tools/hud_range.tscn "$GODOT_LOG_DIR/minimap.png" 110 minimap
# HOW TO PLAY, driven three times (the letters round): it opens itself on a
# machine that has not seen it, closing is what marks it seen, and it does not
# come back. That flag is the half of this feature no picture can show and the
# half that decides whether anybody ever reads it — six cards of dots and dashed
# lines either look right or do not, and that is a person's call. The same run
# leaves card three standing for the camera, which is the one with the pouch,
# the sunburst and the HUD lamp in it. `tutorial_seen` is put back afterwards,
# because `Settings` writes to disk and this runs on somebody's own machine.
check "the how-to-play cards" "tutorial PASS"     "$GODOT" --path "$GODOT_ROOT" --resolution 1600x900 --script tools/snapshot.gd --     res://tools/hud_range.tscn "$GODOT_LOG_DIR/tutorial.png" 60 tutorial
also "the how-to-play cards" "6 cards, shown once and reopenable"
also "the how-to-play cards" "every one of the 6 cards drew"
# The ability bar's tiles are photographs of the real props (D-076), and this is
# the claim that makes seven of them a *set* rather than seven pictures: one
# camera, one light rig, and one framing rule — the geometric mean of a
# silhouette's on-screen width and height is 66% of the tile, capped at 88% on
# the longer side, with anything over 2:1 laid on the diagonal.
#
# Checked against the **committed PNGs** rather than by re-rendering them, which
# is the whole point of baking: what has to hold on every machine is that the
# pictures in the repository obey the rule, not that this machine's GPU can
# reproduce them. It re-measures each tile's alpha and fails if any one has
# drifted out of budget — a re-bake with the camera nudged, or a prop replaced
# by one of a different shape, shows up here rather than in somebody's peripheral
# vision three weeks later.
#
# The picture to look at, which no number settles:
#     ... --path . --script tools/bake_tiles.gd -- sheet   # out/tiles_sheet.png
check "the ability tiles are one set" "bake_tiles: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" --script tools/bake_tiles.gd -- check
# **A dial the host cannot drag is a setting that cannot be changed** (D-076).
#
# The match panel's readout used to sit beside its slider, and a `Label`'s
# minimum width is the width of its own text — so every unit string this panel
# learned to say came off the track. At the worst label it currently has this was
# not a squeeze but a wipe-out: `bow_drop_full` measured a **zero-pixel** track
# behind "25.5 m/s²  ·  flat to 39 m  (and the bolt with it)", with
# `sword_recharge` at 47 px and `sword_reach` at 92.
#
# So this is not a screenshot. For every slider it walks the slider's own range
# at the slider's own step, renders each formatted unit through the real font,
# and keeps the value that comes out widest — the actual worst label, not a
# typical one — then pushes all of them at once and measures what is left of
# every track, under every win condition, because `_apply_visibility` hides rows
# and a row that is not laid out has no width. 245 rows; `MIN_TRACK` is 180 px.
# With the readout put back beside the slider it fails on 27 of them.
#
# The floor it actually reads is 448 px, up from 320, and where it is measured
# moved with D-107: the host's Match panel is the one panel that stays open, and
# it is now measured standing beside a *folded* roster rather than an expanded
# one, so the stack's stretch ratio hands it more of the width than it used to
# get.
#
# 150 frames, not 60, here and for `capture_config` below. `snapshot.gd` counts
# *physics* frames -- wall time -- and the harness inside awaits *process*
# frames, two per win condition plus the lobby's own opening, so the budget has
# to hold that many rendered frames. At 60 it did until the character page grew
# to twenty-five skin tiles (D-126) and the lobby's frame rate dropped below the
# line where a second holds enough of them: the verdict then simply never
# printed, on about one run in two.
check "every slider can be dragged" "widths: PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 1600x900 --script tools/snapshot.gd -- \
    res://tools/ui_range.tscn "$GODOT_LOG_DIR/widths.png" 150 widths
# Capturing a config to the clipboard (D-076), through the real button, the real
# fields and the real `DisplayServer` clipboard.
#
# `fields` is the one that matters and the one that would rot: the capture is
# built from `MatchConfig.fields()` — what actually travels on the wire — and
# this compares the sheet's row set against that list **in both directions**, so
# a dial added next month is in the clipboard the day it lands rather than the
# day somebody remembers. A hand-written list would pass on the day it was
# written and be silently short by one for ever after.
#
# `clipboard` copies for real and reads it back, requiring every row to have
# survived into the text and the name and both lines of the notes with it, and
# then prints the whole payload into the log — because "reads correctly pasted
# into a chat window" is the actual requirement and no substring test settles it.
# `saved` keeps it for the session and applies it back over every field.
check "a config reaches the clipboard" "capture: PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 1600x900 --script tools/snapshot.gd -- \
    res://tools/ui_range.tscn "$GODOT_LOG_DIR/capture_config.png" 150 capture_config
also "a config reaches the clipboard" "capture: fields PASS"
also "a config reaches the clipboard" "capture: clipboard PASS"
also "a config reaches the clipboard" "capture: saved PASS"
# The menu's wordmark is three letter cards standing in the glade now (the
# letters round), so "is the B·O·G clear of the Bog, and are his feet clear of
# the button bar" stopped being something an anchor could promise and became a
# projection. This shoots the menu and prints every box in fractions of the
# frame — the window a screenshot is taken at is not the window a player runs —
# then says whether the row and the hero's capsule overlap.
check "the menu's letters clear the Bog" "menu_letters: PASS"     "$GODOT" --path "$GODOT_ROOT" --resolution 1600x900 --script tools/snapshot.gd --     res://tools/ui_range.tscn "$GODOT_LOG_DIR/menu_letters.png" 60 menu_letters
# The same rig at the lobby's lens over a full eight-Bog ring, and this is the
# one that will rot: that camera is pitched down at a ring standing behind the
# fire, so raising `MenuLetters.HOVER_HEIGHT` walks the row *into* the faces
# rather than out of them. Requires the row inside the panels' 400..1140 clear
# band (`tools/weapon_select.gd`'s band) and below every head, and prints which
# world height on the nearest Bog the row's top crosses.
check "the lobby's letters clear the ring" "lobby_letters: PASS"     "$GODOT" --path "$GODOT_ROOT" --resolution 1600x900 --script tools/snapshot.gd --     res://tools/ui_range.tscn "$GODOT_LOG_DIR/lobby_letters.png" 60 lobby_letters
# Holds W and requires the Bog to have gone somewhere. Movement was wired into
# the testbeds and nowhere else, so every testbed could be walked around while
# the real arena could not, and the abilities — which read their own keys —
# kept working and made it look like input was fine.
check "walking with the keyboard" "walk PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd -- \
    res://tools/combat_range.tscn "$GODOT_LOG_DIR/walk.png" 200 walk
# Pulls the peer out from under a live Bog and keeps ticking it, which is what
# leaving a match does: the peer is nulled at once and the arena survives the
# fade. `Bog.is_local` asked the missing peer for an id on every one of those
# frames, from three call sites, for thirteen frames, every time.
check "leaving a match cleanly" "leave PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd -- \
    res://tools/combat_range.tscn "$GODOT_LOG_DIR/leave.png" 200 leave
# Rust's eight spawn pads, checked with the physics rather than with eyes: a ray
# down onto layer 1 that has to find a floor under every marker, and a Bog-sized
# capsule that has to fit where the Bog will stand. Rendered rather than
# headless because the map's collision is built in `_ready` from world-space
# triangles and the physics has to actually tick for any of it to be there —
# and because the same run writes the top-down picture, which is the only way
# anybody sees where the pads are. It also asserts the geometry imported at all
# (over 90,000 triangles), so a `.glb` that silently failed to re-import fails
# here rather than as a map that is missing half its containers.
check "rust spawns and collision" "preview_map: PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 900x1100 --script tools/snapshot.gd -- \
    res://tools/preview_map.tscn "$GODOT_LOG_DIR/rust_top.png" 30 top
# The same eight-pad physics check on Kopje Crossing, through the same tool
# with the map named. The triangle floor it asserts is Rust's number and the
# savanna clears it three times over, so it still means "the geometry was
# built" rather than "some geometry exists".
check "safari spawns and collision" "preview_map: PASS"     "$GODOT" --path "$GODOT_ROOT" --resolution 900x1100 --script tools/snapshot.gd --     res://tools/preview_map.tscn "$GODOT_LOG_DIR/safari_top.png" 30 top     map=res://scenes/world/maps/safari.tscn
# And the thing that makes the savanna a map rather than a pile of rocks: every
# landing has the rock the table promises under it, a Bog fits on it, and it can
# be reached from the ground on the Bog's real jump arc, which the report reads
# off `Bog` rather than typing. A change to the jump that strands a platform
# fails here instead of in a match. About six seconds, so it earns its place.
check "safari parkour reachability" "parkour_report: PASS"     "$GODOT" --path "$GODOT_ROOT" --resolution 1000x1000 --script tools/snapshot.gd --     res://tools/parkour_report.tscn "$GODOT_LOG_DIR/safari_parkour.png" 30 top
# Lantern Wharf's eight pads through the same tool. Its floor for "the geometry
# was built" is its own: the yard is 1,700 triangles of boxes on purpose, and
# Rust's 90,000 would fail it for being cheap.
check "wharf spawns and collision" "preview_map: PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 900x1100 --script tools/snapshot.gd -- \
    res://tools/preview_map.tscn "$GODOT_LOG_DIR/wharf_top.png" 30 top \
    map=res://scenes/world/maps/wharf.tscn min_triangles=1000
# And the box yard's own promises, from the same report as the savanna's: every
# crate and climbable box is reachable, no jump at all — the one-tick dive
# included — reaches the top of a tower or a wall, no eye-to-eye sightline is
# longer than 25 m on the ground or 26 m from a roof, and no spawn pad sees the
# other base's pads.
check "wharf parkour and sightlines" "parkour_report: PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 1000x1000 --script tools/snapshot.gd -- \
    res://tools/parkour_report.tscn "$GODOT_LOG_DIR/wharf_parkour.png" 30 top \
    map=res://scenes/world/maps/wharf.tscn
# Halcyon Wake's eight pads, on its own triangle floor for the same reason as
# the wharf's: a yacht of boxes and one lofted hull is about 2,200 triangles.
check "yacht spawns and collision" "preview_map: PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 900x1100 --script tools/snapshot.gd -- \
    res://tools/preview_map.tscn "$GODOT_LOG_DIR/yacht_top.png" 30 top \
    map=res://scenes/world/maps/yacht.tscn min_triangles=1000
# And the yacht's promises: every deck, step and stair landing is reachable from
# the main deck by hops and leaps alone, the mast is out of reach of every jump,
# no eye-to-eye line runs past 21 m on the main deck or 38 m from a landing, no
# pad sees the other base's pads, and over every edge of the deck there is
# nothing between a falling Bog and the void half a metre under the sea.
check "yacht parkour and overboard" "parkour_report: PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 1000x1000 --script tools/snapshot.gd -- \
    res://tools/parkour_report.tscn "$GODOT_LOG_DIR/yacht_parkour.png" 30 top \
    map=res://scenes/world/maps/yacht.tscn
# Twin Quarry's eight pads, on the lowest triangle floor of any map: 632 big
# stone slabs' worth, and deliberately — the whole pit is 56 boxes.
check "quarry spawns and collision" "preview_map: PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 900x900 --script tools/snapshot.gd -- \
    res://tools/preview_map.tscn "$GODOT_LOG_DIR/quarry_top.png" 30 top \
    map=res://scenes/world/maps/quarry.tscn min_triangles=400
# And the quarry's promises, which are the ones the elevated bases rest on:
# every bench tile is reachable from the pit floor by the haul ramps and nothing
# else, no jump at all reaches a column top or the rim, no eye-to-eye line runs
# past 30 m on the floor or 43 m from a landing, and no pad sees the other
# base's pads — which on a rotationally symmetric map is only true because the
# Stack stands on the origin every one of those lines runs through (D-082).
check "quarry parkour and ramps" "parkour_report: PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 1000x1000 --script tools/snapshot.gd -- \
    res://tools/parkour_report.tscn "$GODOT_LOG_DIR/quarry_parkour.png" 40 top \
    map=res://scenes/world/maps/quarry.tscn
# Twin Quarry is fair (D-146). The two bases are one function called twice, and
# this re-proves it from the built scene rather than trusting that: the bases
# congruent under a half turn, all three letter runs the same length from both,
# cover and high ground counted equal either side, and every pad and letter on
# solid ground. It is the only thing standing between "not symmetrical" and
# "not even".
check "the quarry is even" "quarry_check: PASS"     "$GODOT" --headless --path "$GODOT_ROOT" tools/quarry_check.tscn
# Highsun Grounds' eight pads, all of them on one lodge deck — which is what
# makes `PAD_SEPARATION` the number the deck's 24 m width was derived from. Its
# triangle floor is its own and the lowest but the quarry's: the whole range is
# 2,640 triangles of slabs and posts, because a range is mostly empty ground.
# The second `also` is the **marker contract** units 3, 4 and 5 code against —
# the map prints its own census, so a marker dropped by a later edit fails here
# rather than in a playtest.
check "range spawns and collision" "preview_map: PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 800x1200 --script tools/snapshot.gd -- \
    res://tools/preview_map.tscn "$GODOT_LOG_DIR/range_top.png" 40 top \
    map=res://scenes/world/maps/range.tscn min_triangles=1200
# The eighth pad, named rather than counted: `preview_map`'s pad-count check
# prints nothing when it passes, so an `also` on its wording would go green on a
# map with one pad. This is the last of the two rows of four, and its height
# says it is standing on the deck with the other seven.
also "range spawns and collision" "pad 7  (9.75, 1.32, 44.00)"
also "range spawns and collision" "27 dummies (27 live, 0 reserved), 4 wells, 3 racks, 1 signboard(s), 8 targets"
# Where the sun actually ended up, read back out of the built scene rather than
# taken from the comment that claims it. Every argument this map makes about
# where a shadow falls is made from these two numbers, and they were sixty
# degrees wrong for a whole pass: a `.tscn` stores a `Transform3D` as the
# basis's three *rows* and the Sun had been written as its columns, which is a
# transpose and therefore invisible on the due-north moon this map used to have.
also "range spawns and collision" "sun 32.0 deg up, bearing 30.0 deg E of N (0.0 off design)"
# And the range's own promises, which are about the jump arc rather than about
# sightlines: every landing on the parkour course is reachable from the ground by
# hops and leaps alone, the course offers the one-tick dive as a shortcut and
# never as the only way, and nothing — not a hop, a leap or the dive — reaches
# the lodge roof, the west bank or the south banks. Its `EXPECT` row turns the
# sightline scan off and says at length why.
check "range parkour and reaches" "parkour_report: PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 1000x1000 --script tools/snapshot.gd -- \
    res://tools/parkour_report.tscn "$GODOT_LOG_DIR/range_parkour.png" 40 top \
    map=res://scenes/world/maps/range.tscn
also "range parkour and reaches" "every landing is reachable from the ground (0 stranded)"
# And the picture the capture's numbers belong beside: the raised fist with the
# card above it, half way down (the letters round). `shield deploys`' form — it
# proves the scene renders with a Bog, a pouch and a card in it, which no
# headless run can; whether the sack hangs right is a person's call.
check "the capture looks like one" "snapshot: wrote"     "$GODOT" --path "$GODOT_ROOT" --resolution 1600x900 --script tools/snapshot.gd --     res://tools/preview_capture.tscn "$GODOT_LOG_DIR/capture_hand.png" 40 f=0.5
also "the capture looks like one" "capture PASS"
# Walks the menu into a real match and asks Input.mouse_mode what happened. It
# grabs the physical mouse for about a second on the way through, which is the
# only way to prove the thing it proves: every other check here stands the arena
# up directly, and this bug only existed on the path a player takes.
check "mouse capture entering a match" "cursor_flow: PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 res://tools/cursor_flow.tscn
echo

echo "smoke: $checks checks, $failures failures"
if [ "$failures" -gt 0 ]; then
    echo "smoke: FAIL   (logs in $LOG_DIR)"
    exit 1
fi
echo "smoke: PASS"
