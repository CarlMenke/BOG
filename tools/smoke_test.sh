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

    if ! "$@" >"$log" 2>&1; then
        echo "FAIL (Godot exited non-zero)"
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
# The mushroom as cover, which is the only thing about it that matters and the
# one thing nothing checked until D-039. Three assertions out of one run, and
# the order of them is the point: a spear thrown at a Gub standing behind a
# mushroom does not kill it, the *same* throw with the mushroom withered does,
# and a Gub walking into one is held off at the edge of the cap.
#
# The middle one is not a nicety. "Did not die" passes for a spear that has
# stopped killing anybody at all — a broken launch, a dummy already dead, a
# `report_kill` that never arrived — so without a control on the same geometry
# the first assertion would go green on a mushroom that stops nothing. Which is
# what the check it supplements did for this whole session: `mushroom deploys`
# asserts `snapshot: wrote`, proving a PNG exists, while the collision cap sat
# 31 cm above the head of the tallest thing it was meant to be hiding.
#
# The mode plants the mushroom half a metre off the line of fire, and that is
# the other half of why this is worth anything. Lined up perfectly, the 0.55 m
# stem blocks the shot on its own, so a dead-centre throw is stopped by a
# mushroom whose cap is a metre above the fight.
#
# Headless, and it quits itself around tick 350: it drives its own sequence and
# waits on the throw gate between the two spears rather than on a frame count.
# The picture of a spear stopping dead against a cap is a separate, earlier
# frame:
#     ... --script tools/snapshot.gd -- res://tools/combat_range.tscn \
#         out/mushroom_cover.png 100 cover
check "mushroom stops a spear" "cover PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- cover
also "mushroom stops a spear" "control PASS"
also "mushroom stops a spear" "solid PASS"
# Twelve throws, with the shaft required to be back in the fist at the end of
# every one of them — and then the fist is emptied by hand while the throw gate
# still says armed, and has to refill itself. The first half is the bug as the
# player met it ("the spear model is not reliably reappearing"); the second is
# the property that stops it coming back, and it is the half that cannot pass
# by luck. Against the one-shot `SceneTreeTimer` this replaced, all twelve
# cycles fail here and the emptied fist never refills.
check "the spear grows back" "recharge PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- recharge
# The Elder's invincibility, asserted against a real spear rather than in logic
# (D-040). `match_rules` can prove that `report_kill` refuses the kill; only this
# can prove that a shaft launched at a body fourteen metres away arrives, is
# turned aside, and leaves the Gub standing — and that is the assertion it would
# hurt most to have wrong, because an Elder that quietly dies to the first spear
# is a twenty-second power-up that does not exist.
#
# Three verdicts out of one run, and the same reasoning the mushroom's have.
# `ward` is the rule; `expiry` is the robe burning out **on its own clock**, in
# a real match loop rather than by a harness winding the row back; and `control`
# is the same throw at the same Gub with the robe gone, which is what stops
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
# either an item or the elder randomly". The player dies holding a mushroom and
# a dummy dies as the Elder holding one too, both off their spawn pads with loot
# lying on both corpses; a second after both come back, nobody may hold, wear or
# have picked up anything.
#
# The dummy is the half that caught it. It is a remote Gub, and the mode plays
# its client 200 ms behind the host — still dead, still publishing the corpse,
# a snapshot every other tick — which is the window the bug lived in: the
# host's live copy was put back on its own loot and walked into it. Against the
# code without `Gub.sync_life` this fails with the dummy holding a mushroom and
# wearing the robe. `tools/net_loopback.gd` cannot open that window at all: a
# loopback round trip is shorter than a physics tick.
#
# Headless, and it quits itself around tick 280.
check "a respawn hands back nothing" "respawn PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/combat_range.tscn -- respawn
# Bunny hopping (D-052). The local Gub runs the range as itself, as the Elder
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
# Gubs in their team's colour (D-046), read off the material the renderer will
# draw with rather than off what the script meant to set. One Gub per team has
# to be in exactly its nameplate colour, a free-for-all Gub has to be back on the
# imported yellow, the Elder's robe has to keep its purple over a tinted body,
# a corpse has to die in the colour it lived in, and a lobby roster change has to
# repaint the Gub whose team moved. The corpse half fails against a ragdoll that
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
# with a wall between the local Gub's camera and a teammate and an enemy forty
# metres behind it — the ray that proves the wall is in the way is a verdict of
# its own, so this cannot pass on open air. The teammate's plate has to ignore
# the depth test, be up and at full alpha out there; the enemy's, beside it, has
# to be depth-tested and faded exactly as before, because a plate through a wall
# is a wallhack and only a teammate's is allowed to be one. The HUD's chip has to
# say TEAM 1 in team 1's colour. Against `set_ally(false)` the ally half fails;
# against `set_ally(true)` the enemy half does, and so does the free-for-all run,
# which also wants the chip hidden and every plate at its old size. Headless,
# both quit on tick 30. The picture, from the Gub's own camera:
#     ... --resolution 1600x900 --script tools/snapshot.gd -- #         res://tools/team_plates.tscn out/team_plates.png 40
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
# at its edge, a wall at the Gub's back with the view swung and flicked through
# it, and a low tunnel walked through — 1,700 frames, each asked three ways
# whether the lens is inside collision: a point query, a near-plane sphere, and a
# ray from the eye (is it behind a wall). Against the old spring arm 942 of the
# 1,700 fail, in every leg.
#
# The `also` is the half that keeps D-025 true: the point a throw is aimed at is
# required, every frame, to be the one the *unobstructed* camera would give for
# the same view. With `aim_ray` taken from the pulled-in lens instead, 1,030
# frames fail. `--fixed-fps 60` so a tick of view-turning is the same on every
# machine; headless, about two seconds.
check "camera stays out of the scenery" "clip PASS" \
    "$GODOT" --headless --fixed-fps 60 --path "$GODOT_ROOT" tools/camera_range.tscn
also "camera stays out of the scenery" "aim PASS"
# Menu to results screen, through the real scenes and the real autoloads. The
# only check here that can notice a *join* coming apart — a lobby that never
# hands off to the arena, an arena that never registers, a results screen that
# never opens — none of which any single-seam harness can see, because each of
# those is the absence of a call rather than a fault inside one.
check "full playthrough" "playthrough: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/playthrough.tscn
# Capture G·U·B's bases and letters on this map (D-051), from the same run: two
# bases on distinct pads well apart, each team with pads of its own, and three
# letter points on a real floor with a Gub's head room, outside both bases and
# apart. No map declares its own objectives yet, so this is the fallback being
# proven playable on every map the mode can be picked on; Rust and Kopje Crossing
# carry the same line below.
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
# A Capture G·U·B match standing up in the real arena (D-051): `arena.gd` draws
# a ring per team, the host settles three cards onto the map once the physics
# has stepped, and every Gub spawns on a pad of its own team's. The rules
# themselves — carry, bank, the enemy base doing nothing, a dead carrier's drop
# and its return, an enemy recovering it, winning — are `match_rules`, in a box
# with a floor. Headless, a few seconds. The picture from above Team 1's base:
#     ... --resolution 1600x900 --script tools/snapshot.gd -- \
#         res://tools/capture_preview.tscn out/capture_base.png 150 safari
check "capture match on a real map" "capture_preview: PASS" \
    "$GODOT" --headless --path "$GODOT_ROOT" tools/capture_preview.tscn -- safari
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
# 110 ticks, not the 70 it used to be. The throw is clicked on tick 20 and the
# spear does not leave the hand until THROW_RELEASE_TIME after that (D-025),
# which on the new `Throw` clip is 0.71 s = 42.5 ticks, so the spear appears
# around tick 63; it then flies 14 m at 42 m/s (0.33 s, 20 ticks) and the kill
# lands around tick 83. The old count of 70 stopped the run before that even at
# the old 0.57 s. Worth saying out loud because the failure would have read as a
# broken throw and not as a warmup that was now too short. The lure's 132 below
# needs no allowance: a lure leaves on the click.
check "spear kills" "killed Dummy 1" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd -- \
    res://tools/combat_range.tscn "$GODOT_LOG_DIR/hit.png" 110 hit
check "lure catches" "combat_range: lure caught 1" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd -- \
    res://tools/combat_range.tscn "$GODOT_LOG_DIR/lure.png" 132 lure
# The Elder, end to end and in a world with something standing in it: a robe
# rolled out of a real death, walked over, and one bolt at a dummy fourteen
# metres away. `match_rules` proves the state machine — the robe makes an Elder,
# the clock ends it, the cooldown gates a second cast — but it has no geometry
# and nothing to hit, so the one thing it cannot prove is that the bolt kills
# anybody. That is exactly the failure a screenshot also cannot see: a bolt
# drawn beautifully past a Gub who is still standing looks identical to one that
# worked, which is why the mode prints its own verdict.
#
# 90 ticks, and the margin in it is now much larger than it was. The robe drops
# on tick 20 and is claimed on 21, the cast follows immediately, and the bolt
# leaves `lightning_delay` later — 0.2 s = 12 ticks since D-040, where it used
# to be THROW_RELEASE_TIME's 42.5 — so the kill lands around tick 34 and the
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
# `try_place_mushroom`, the two validation rays, the broadcast, the eruption —
# and `snapshot: wrote` is all it has ever asserted. Fine as half a check and
# disastrous as the whole one. "mushroom stops a spear" above is the other half.
check "mushroom deploys" "snapshot: wrote" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd -- \
    res://tools/combat_range.tscn "$GODOT_LOG_DIR/mushroom.png" 40 mushroom
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
check "spear reload timer on the tile" "reload_timer PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd -- \
    res://tools/hud_range.tscn "$GODOT_LOG_DIR/reload_timer.png" 270 reload_timer
# Holds W and requires the Gub to have gone somewhere. Movement was wired into
# the testbeds and nowhere else, so every testbed could be walked around while
# the real arena could not, and the abilities — which read their own keys —
# kept working and made it look like input was fine.
check "walking with the keyboard" "walk PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd -- \
    res://tools/combat_range.tscn "$GODOT_LOG_DIR/walk.png" 200 walk
# Pulls the peer out from under a live Gub and keeps ticking it, which is what
# leaving a match does: the peer is nulled at once and the arena survives the
# fade. `Gub.is_local` asked the missing peer for an id on every one of those
# frames, from three call sites, for thirteen frames, every time.
check "leaving a match cleanly" "leave PASS" \
    "$GODOT" --path "$GODOT_ROOT" --resolution 640x360 --script tools/snapshot.gd -- \
    res://tools/combat_range.tscn "$GODOT_LOG_DIR/leave.png" 200 leave
# Rust's eight spawn pads, checked with the physics rather than with eyes: a ray
# down onto layer 1 that has to find a floor under every marker, and a Gub-sized
# capsule that has to fit where the Gub will stand. Rendered rather than
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
# landing has the rock the table promises under it, a Gub fits on it, and it can
# be reached from the ground on the Gub's real jump arc, which the report reads
# off `Gub` rather than typing. A change to the jump that strands a platform
# fails here instead of in a match. About six seconds, so it earns its place.
check "safari parkour reachability" "parkour_report: PASS"     "$GODOT" --path "$GODOT_ROOT" --resolution 1000x1000 --script tools/snapshot.gd --     res://tools/parkour_report.tscn "$GODOT_LOG_DIR/safari_parkour.png" 30 top
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
