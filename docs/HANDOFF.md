# Handoff — picking up the interrupted work

*Written 2026-09-13, after four parallel agent sessions were interrupted by rate limits and their
work was committed and pushed. This document is the brief for whoever picks it up. It lives on
`main` so it is reachable from any clone; it names no local paths and depends on nothing that is
not in this repository.*

You are picking up BOG after four parallel agent sessions were interrupted. Everything they
did is committed and pushed. Nothing is lost, and nothing you need is on the machine those sessions
ran on. You have two jobs, in this order: land the in-flight work (Phase 0), then work a backlog of
the user's playtest notes (Phase 2), planning before you start it (Phase 1).

## Getting set up

```
git clone https://github.com/CarlMenke/BOG.git
cd BOG
git fetch --all
```

All paths in this document are relative to that clone. Everything is on `origin`; there is no
uncommitted work anywhere. Before starting, confirm the toolchain this repo expects is on this
machine — the scripts find it themselves and fail loudly if it is absent:

- **Godot 4.7** — located by `tools/find_godot.sh`, which every headless tool and the gate source.
- **Blender** — no longer needed: the BOG and its clips are imported by Godot itself since
  **D-095**, and the Elder's robe was refit without it (**D-099**).
- **Python 3** — for `tools/make_sfx.py` and the asset pipeline scripts.
- **bash** — the gate and build scripts are shell scripts. On Windows use Git Bash.
- `git config user.name` / `user.email` set, and push access to `CarlMenke/BOG`.

**Not in this repository, and not needed:** the `out/` render folders (gitignored — no screenshots
or renders are in git on any branch) and, on the original machine only, a `refs/backup/preflight`
safety ref, also pushed as the tag `backup/preflight-2026-09-13`, holding a pre-split snapshot of
main's then-uncommitted tree. Nothing in that snapshot is missing from `main`. Wherever this
document mentions a render, you regenerate it by running the range tool that produced it; you do
not go looking for the file.

---

## HOW YOU WORK — read before touching anything

**Delegate implementation, keep decisions.** You are the orchestrator. Every implementation task
below goes to a subagent: the `Agent` tool, `subagent_type: general-purpose`, `model: opus`, medium
reasoning effort. You review what comes back, run the gate yourself, and decide.

**One subagent at a time. Never parallel.** These tasks overlap in `match_state.gd`,
`bog_combat.gd`, `hud.gd` and `docs/DECISIONS.md`. Four parallel sessions is exactly how this repo
ended up with three agents all claiming decision number D-040. Sequential, always, even when two
tasks look independent.

**The gate is the definition of done.** `bash tools/smoke_test.sh` — 21 checks on main today. Run it
after every task, before starting the next one. If a task adds behaviour worth asserting, it adds a
check, and the count in `docs/STATUS.md` moves with it (two places: the command comment near line 25
and the "passes, N of N" sentence near line 29). Never start a task on a red tree.

**Decision numbers are claimed at commit time, never reserved.** This is the rule that was missing
and it caused three collisions in one day. Immediately before writing a record, run
`grep -oE '^## D-0[0-9]+' docs/DECISIONS.md | tail -1`, take the next number, write it, and commit in
the same commit as the code. Do not announce a number you intend to use later.

**Commit style.** Read the last few `git log` entries first. Titles are a sentence with a clause —
"Give the lobby a second map, and let it be a container yard at noon" — and bodies explain the *why*
and what was rejected, at length. Match it. Commit and push after each task; do not accumulate a day
of work in a dirty tree, which is what went wrong last time.

**Ask, don't guess, on anything user-facing.** Several backlog items reverse decisions the user
approved a day earlier. Where a note below says "confirm with the user", stop and ask.

---

## CURRENT STATE

`main` (460f0e0) carries the day's work as eight commits: letter win condition, the letter hold, the
D-036 HUD pass, the Elder asset, Elder gameplay, two bug fixes, the D-040 Elder buffs, and the
`/host` skill. Decision records D-001..D-040 are on main. Gate: 21 checks, green.

**Those eight commits were split retroactively out of one working tree, hunk by hunk. Only the last
one (460f0e0) is a tree the gate was run against.** Do not bisect through the other seven or expect
them to build.

Three feature branches, all on `origin`, all complete as described:

| branch | tip | state |
|---|---|---|
| `feat/letter-meshes` | 942b9e2 | done, needs merging and renumbering |
| `feat/safari-map` | 3ab36df | built and passing its own checks, finishing pass unfinished |
| `feat/spear-charge` | f2dc507 | one dev tool, stale base, park it |

(`feat/play-over-tailscale` is older and unrelated; leave it alone.)

Work each branch however you prefer — `git worktree add`, or plain checkouts. The original sessions
used sibling worktrees; that is not a requirement.

### Decision numbers — settle this first

main owns D-001..D-040. D-038 is the Elder, D-039 the two bug fixes, D-040 "the Elder is twenty
seconds of being unkillable".

- `feat/letter-meshes` numbers its record **D-040**. Renumber to **D-041**. One occurrence each in
  five files on that branch: `README.md`, `docs/DECISIONS.md`, `scripts/items/pickup.gd`,
  `tools/combat_range.gd`, `tools/smoke_test.sh`.
- `feat/safari-map` has **no** record. Its agent drafted one as D-038 in a scratch directory that no
  longer exists — the draft is gone, and D-038 is the Elder anyway. Write a fresh one, next number
  free at the time you commit.
- The spear-charge session announced it had claimed D-041. It hadn't; the letter meshes have it.

---

## PHASE 0 — land the in-flight work

### 0.1 Merge `feat/letter-meshes`

Replaces the letter card's `Label3D` glyph with three real Tripo letter meshes: through the prop
pipeline at 6000 triangles with the texture cut 4096 → 512, the card 0.60 m in world, self-lit from
its own gold texture so it reads at night, spinning like other drops, and held upright and square to
the Bog's facing. A new combat-range mode stands B, O and G side by side and measures their real
height; it is wired into the smoke test.

Its bottom commit `ec94589` is a SNAPSHOT of main's then-uncommitted tree and is **NOT FOR MERGE** —
main carries that work properly now. Take only the three above it:

```
git cherry-pick 0d1fbea b782beb 942b9e2      # or: git rebase --onto main ec94589
```

Fix-ups after the pick:

- Renumber D-040 → D-041 in the five files above.
- The branch bumps the smoke count in `docs/STATUS.md` 14 → 15. Main is at 21 and the branch adds
  exactly one check ("letter cards are meshes"), so it must end at **22**, in both places.
- `assets/source/{G,U,B}_LETTER.glb` (about 9 MB total) live only on this branch and arrive with the
  cherry-pick. Do not add them to main by any other route.

Conflicts should be confined to docs and the test harness; `pickup.gd` and `held_spear.gd` have
barely drifted. The original session's screenshots are not in git — if you want to see the card, run
the letter and asset modes of `tools/combat_range.tscn` and the `hud_hold` mode of
`tools/hud_range.tscn` yourself. Gate should read 22 of 22.

### 0.2 Finish and merge `feat/safari-map`

Kopje Crossing, map id `safari`: ~96 m of savanna, 123 platforms across 8 zones built from layout
tables in `scripts/world/maps/safari_map.gd` and handed to the existing static-map collision baker
(313,400 swept triangles into 18 shapes in 540 ms). No `.glb` behind it at all.
`tools/parkour_report.gd` verifies every landing has the rock the table promises, a Bog capsule fits
on each, every landing is reachable from the ground without a frame-perfect dive, nothing strands,
the summit dives to both saddles, and no landing or trunk crowds a spawn pad. Route mix 69% hops /
31% leaps. A full headless playthrough passes, menu to results, arena in 2.8 s.

Committed deliberately unfinished. Finish in this order:

1. Safari lines in `tools/smoke_test.sh` — none of it is in the gate yet — and move the STATUS count.
2. Point the spawn-pad tool at it; the pads were never put through the physics check.
3. Renders: re-run the top-down, and add a side render and eye-height renders from each spawn. None
   of the originals are in git, so regenerate whatever you want to compare against.
4. Tint pass. Grass and ground are warm and correct, but the acacia canopies read temperate green
   rather than golden, and two trees in the south-east corner came out dark red.
5. Docs, all untouched: a decision record, plus `README.md`, `docs/STATUS.md`,
   `docs/ARCHITECTURE.md`.

### 0.3 Rebase `feat/spear-charge` and park it

Only real content is `tools/hand_track.gd`, a bone tracker that walks a clip sample by sample and
prints where a bone is and how fast it is moving — built to find the three numbers a hold-to-charge
throw needs. Its base `66e31b1` is another NOT FOR MERGE snapshot, 27 files / 1,709 lines behind
main; it predates D-040 entirely.

```
git rebase --onto main 66e31b1 feat/spear-charge
```

Then **park the branch** — hold-to-charge is not in the backlog below and the user has not asked for
it since. Do not build on it without asking. Two things that session did not know:

- It was building against an Elder that predates D-040. The Elder now cannot be killed, lasts 20 s on
  a clock, casts in 0.2 s with a 1 s recharge, and moves and jumps faster; the throw path is shared
  with the Elder's bolt.
- It planned to retire a match-config field that now has a lobby dial and a decision record behind
  it. Verify before removing anything — likely `spear_recharge` (`match_config.gd:49`, in `_FIELDS`
  at :208, clamped at :260, lobby slider at `match_settings.gd:87`). A field missing from `_FIELDS`
  is a setting the host changes and nobody else ever sees.

### 0.4 Rebuild — only on the machine that hosts games

The Windows build the user plays from is stale; it predates the bug fixes and the buffed Elder. The
`/host` skill (`.claude/skills/host/SKILL.md`) rebuilds `BOG.exe` only if it is older than its
sources, hands back the path to share, checks the playit tunnel agent, and prints the invite code. It
needs Godot export templates and the playit agent installed. **If you are not on the user's hosting
machine, skip this and say so** — tell them the build is stale and that running `/host` there is what
fixes it.

**Stop here and report to the user** — gate count, what merged, anything that fought back.

---

## PHASE 1 — plan the backlog

The user has given a list of playtest notes, detangled into the waves below. Before implementing any
of it:

1. Read the code each wave touches and write a short plan per item: the approach, the files, what it
   collides with, and what a smoke check for it would assert.
2. Flag every item marked **REVERSES A DECISION** below to the user explicitly and get a yes.
3. Present the plan and the proposed order. Then work it item by item, one subagent each.

Wave order is deliberate: bugs first, because they make every later playtest lie; then team identity,
because two later features are built on it; then modes; then feel; then maps last, because maps are
the least entangled.

---

## PHASE 2 — the backlog

Each item gives the user's own words, what it means, what it collides with, and done-when.

### Wave 1 — bugs

**1.1 Respawn hands you an item or the Elder at random**

> "there is a bug where you spawn with either an item or the elder randomly, it seems like after you
> die you respawn first where you died and picked it up from there or something?"

The user's guess is a guess; take it as a symptom report, not a diagnosis. D-032 says everything you
carry is lost on death, and D-038 says the robe is *consumed* rather than dropped when an Elder dies
— so an Elder respawning as the Elder is a clear violation of a written rule. First hypothesis to
test: inventory and elder state are not cleared on the respawn path, and/or the Bog is briefly placed
at the death position where its own drop is still lying, and the `Pickup` `Area3D` overlaps it on the
first frame. `_next_spawn` (`match_state.gd:452`) walks the pads and prefers an empty one, so a
literal respawn-at-death-point is unlikely — but a one-frame placement before the transform is
applied is not. Check `_respawn`, `BogCombat`'s round/death reset, and whether `claim_pickup` can
fire on the frame a Bog spawns.

*Done when:* a smoke check kills a Bog carrying a shield and an Elder wearing a robe, respawns
both, and asserts empty hands and no robe.

**1.2 Rematch is unreliable**

> "rematch only works 50% of the time / takes a while"

Lives in `scripts/net/net.gd`, `scripts/ui/results_screen.gd`, `scripts/ui/hud.gd`. Suspect a race
between the rematch request and the match-end broadcast, or a client acting on a results screen whose
state has already been replaced. D-021 ("ending a match is a broadcast, not a navigation") is the
relevant existing decision — read it first. `tools/net_loopback.gd` is the two-process harness and is
where a regression check for this belongs.

*Done when:* the loopback harness runs a match to a result and rematches it ten times in a row
without a stall, and that is in the gate.

**1.3 Camera clips through geometry**

> "The camera needs some better avoidance, too frequently the camera is inside meshes and stuff when
> there are meshes behind the character"

`scripts/player/bog_camera.gd`. Wants a real spring-arm sweep — a shape cast from the head to the
desired boom position, pulled in to the first hit with a margin, and eased back out rather than
snapped. Watch the interaction with the aim marker and with third-person throwing: pulling the camera
in must not move where a spear goes, since D-025 puts aim at the release.

*Done when:* there is a range mode that walks a Bog along a wall, into a corner, and under a canopy,
and asserts the camera never ends a frame inside collision geometry.

### Wave 2 — teams and identity

**2.1 Tint the Bog mesh to the team hue**

> "For teams, the gubs change color to the hue, should be able to just tiny the mesh."

Read "tiny" as "tint". The team colours already exist for UI (`scripts/ui/ui_palette.gd`,
`scripts/player/nameplate.gd`). Tint the existing material rather than authoring per-team materials
or textures.

*Collides with:* the Elder's purple robe (D-037/D-038). A tinted teammate wearing a purple robe must
still read as both. Decide and record which wins — recommended: the robe keeps its purple and the
team hue stays on the body, so "that is an Elder" and "that is mine" are two separate reads.

**2.2 Team membership must be obvious at a glance**

> "it should be obvious what team you are on and who your teammates are, teammates names should be
> clearer and always there"

Two halves: your own team stated plainly on the HUD, and teammate nameplates always visible, legible,
and distinct from enemies'. Today nameplates are distance/visibility gated — teammates should not be.
Touches `scripts/player/nameplate.gd` and `scripts/ui/hud.gd`.

*Note:* nameplates through walls for teammates is a real advantage; that is what the user is asking
for. Do it for teammates only, not enemies (2.2 and 3.2 must not merge into one wallhack).

**2.3 Random teams**

> "random teams"

A lobby option that shuffles the roster into balanced teams, host-side, before a match starts.
`scripts/game/match_config.gd` gets the field (add to `_FIELDS` or it never leaves the host),
`scripts/ui/match_settings.gd` the dial, `scripts/ui/lobby.gd` the display.

**2.4 Letter scoring is per team in Teams mode** — **REVERSES A DECISION**

> "for gub game in team, the gub spelling scoring should be per team"

`match_state.gd::_check_win` currently carries the opposite, in a comment written a day ago: *"A team
whose three members hold B, O and G between them has not won anything: the card game's ending is one
hand with all three in it."* The user now wants the team's letters pooled. Implement the pool, and
write a decision record that states the reversal and why — the old comment must not simply be
deleted, it has to be answered. Confirm with the user that pooled means pooled: three teammates
holding B, O and G between them wins.

*Also:* the scoreboard letters column and the results table are per player today (D-033 era) and need
a team row under this condition.

### Wave 3 — letters and information

**3.1 Capture-the-flag letters as a separate win condition**

> "capture the flag game mode with the letters, you have to pick up the letter and drop it in your
> base, there are only 3 and dont drop from users dying"

This is **a new win condition, not a change to `LETTERS`**. Three rules of the existing mode are
inverted: there are exactly three letters in the world rather than a drop-chance roll (D-033's
uniform-letters economy), you score by carrying one to your base rather than by holding it ten
seconds (D-035), and dying does not return the card to the map at your corpse (D-035 again). Trying
to express both through one condition will wreck the mode that already works.

Append to `MatchConfig.WinCondition` — **append, never reorder**; the ordinal is what travels on the
wire, and the enum says so at the top. Needs: bases (a per-team volume in the map, so `map_catalog`
entries or the map scenes gain base points), the three letters spawned once at match start, a carrier
that is visible, a return rule for a card dropped in open ground, and an answer for what a carrier's
death does — ask the user; the plausible options are the card drops where they fell, or it returns to
its spawn.

*Note:* Teams-only by nature. Decide what it does if the host picks it in free-for-all — likely hide
it in the lobby the way the letter dials are hidden today.

**3.2 Tell everyone when a letter is picked up**

> "some kind of notification when someone picks up a letter, maybe it should also show people with
> letters through walls / on the map?"

The kill feed is the existing channel for "something happened that everyone should know". A letter
pickup belongs there. The through-walls half is a second, bigger question: it is deliberate
counterplay information, and D-035 currently says the *opposite* — that the lit card in a fist is
meant to be an in-world tell with no HUD treatment. Propose it as an outline/marker on carriers,
visible to everyone, and get the user's yes before building it, since it partly reverses D-035.
Applies to both letter modes.

### Wave 4 — feel and combat

**4.1 Jumping and bunny hopping should carry momentum**

> "bunny hopping / jumping need to account for momentum a little more"

`scripts/player/bog.gd` — the jump is D-026 (single jump, double-tap dive) and the animator reads
`jump_velocity()`, so anything that changes take-off speed must keep the air arc a ratio (D-040
learned this the hard way; see the note in `bog_animator.gd`). Wants horizontal velocity preserved
across a landing-and-immediate-rejump rather than scrubbed, with a cap so it is a skill move and not
flight. Measure it: state the top sustainable speed before and after.

*Interacts with:* the Elder's speed and jump multipliers (D-040). A bunny-hopping Elder must not come
out absurd — check it and say what the number is.

**4.2 Lightning gets a small blast radius**

> "the lightning should have an aoe (small blast radius) so that if you hit pretty close it still
> hits them, this should still be a one shot kill, but not too far"

`scripts/player/bog_combat.gd` (the cast and `LIGHTNING_RANGE`) and `scripts/items/lightning_bolt.gd`
(the visual). Still a one-shot inside the radius, nothing outside it — no falloff, because a bolt
that sometimes leaves someone alive is a worse read than one that misses. The radius belongs in
`MatchConfig` with a lobby dial and in `_FIELDS`, like every other Elder number.

*Collides with:* D-040 — the AoE must not kill an Elder, and the existing "a spear cannot kill an
Elder" checks have an obvious sibling here. The visual radius must match the real one.

*Done when:* a combat-range mode fires a bolt at a measured miss distance and asserts a kill just
inside the radius and a survivor just outside, plus an Elder surviving a direct hit.

**4.3 Spear recharge indicator in the bottom bar only** — **PARTLY REVERSES A DECISION**

> "There should be an indicator into how long until you get a spear reload ONLY in the bottom bar
> menu, not on the main cursor"

D-036, one day old, deleted *both* the crosshair ring and the ability slots' sweep-and-countdown. The
user is asking for the slot half back and confirming the crosshair half should stay gone. That is
compatible with the spirit of D-036 — read the record before starting; its complaint is that the ring
was wrong about the wind-up, not that timers are wrong in principle. Put the countdown on the Spear
tile in the ability bar only. The crosshair stays a reticle. Record the amendment.

### Wave 5 — maps

Each of these is one subagent, one at a time, each following the pattern `feat/safari-map`
established: a builder script driven by layout tables, the static-map collision baker, a parkour
report, spawn pads through the physics check, renders, a decision record, and smoke lines.

**5.1 Rework Whisperbloom Hollow**

> "The existing enchanted forest map should be a little bigger and reduce the amount of trees by 60%
> and make them all on average way taller, double the height"

`hollow` is the procedural map — `scripts/world/island_generator.gd` for the island and
`scripts/world/prop_scatter.gd` for the trees; it has no scene file, which is what the empty
`"scene"` in `map_catalog.gd:49` means. Four changes: island radius up, tree count down 60%, average
tree height doubled, and the resulting sightlines re-checked. Taller and sparser changes the map's
whole character — cover becomes trunks rather than canopy — so render it before and after and show
the user both. Watch `scripts/world/ambience.gd`, which drops leaves from `canopy_points`: 60% fewer
trees at double height will need its numbers re-tuned or the falling leaves will look wrong.

**5.2 Indoor cave map**

> "indoor cave map, big cave so it works with 3rd person but youd want tunnels which would be hard
> with the 3rd person"

The user has already named the design problem: tunnels and a third-person camera fight. Do not solve
it by shrinking the camera boom in tunnels without telling them. Propose a shape first — recommended:
a single large cavern with wide, tall, short connectors rather than true corridors, so the boom
always has room. This is also the map that will most punish 1.3 (camera avoidance), so it must come
after it.

**5.3 A Shipment-style box map**

> "add shipment call of duty map"

Build the *shape*: a small, dense, symmetric two-base box with hard cover in the middle and
sightlines that never run long — chaotic on purpose. Original geometry and original props, not a
reproduction of Infinity Ward's assets or layout data. Name it something of ours.

**5.4 Yacht map**

> "a yacht map"

Multi-deck, verticality, a hull that reads as one object, water as the void plane. Its parkour report
matters more than most: decks stacked over each other are where "reachable from the ground without a
frame-perfect dive" gets hard.

---

## APPENDIX — file pointers

| what | where |
|---|---|
| match rules, win conditions, scoring | `scripts/game/match_state.gd`, `scripts/game/match_config.gd` |
| lobby dials (and `_FIELDS`, which is what travels) | `scripts/ui/match_settings.gd`, `match_config.gd:208` |
| combat, spear, Elder bolt | `scripts/player/bog_combat.gd` |
| movement, jump, stances | `scripts/player/bog.gd` |
| camera | `scripts/player/bog_camera.gd` |
| nameplates, team colour | `scripts/player/nameplate.gd`, `scripts/ui/ui_palette.gd` |
| HUD, ability bar, crosshair | `scripts/ui/hud.gd`, `ability_slot.gd`, `crosshair.gd` |
| rematch | `scripts/net/net.gd`, `scripts/ui/results_screen.gd` |
| maps table | `scripts/world/map_catalog.gd` |
| procedural map (`hollow`) | `scripts/world/island_generator.gd`, `prop_scatter.gd`, `ambience.gd` |
| static map pattern (`rust`, `safari`) | `scripts/world/static_map.gd`, `scripts/world/maps/` |
| the gate | `tools/smoke_test.sh` |
| headless test beds | `tools/combat_range.gd`, `tools/hud_range.gd`, `tools/match_rules.gd`, `tools/net_loopback.gd` |
| toolchain finders | `tools/find_godot.sh` |
| build + host | `"$GODOT" --import` (the clip build, D-095), `.claude/skills/host/SKILL.md` |

## APPENDIX — decisions this backlog touches

| record | what it says | which item argues with it |
|---|---|---|
| D-021 | ending a match is a broadcast, not a navigation | 1.2 rematch |
| D-025 | the spear leaves at the animation's release, not the click | 1.3 camera |
| D-026 | single jump and double-tap dive | 4.1 momentum |
| D-032 | everything carried is lost on death | 1.1 respawn bug |
| D-033 | letters are uniform, duplicates wasted | 3.1 CTF |
| D-035 | ten-second hold; death returns the card; no HUD tell for others | 3.1 CTF, 3.2 markers |
| D-036 | the crosshair ring and the slot countdown were both deleted | 4.3 reload indicator |
| D-037/38 | the Elder is a purple robe on the Bog's own skeleton | 2.1 team tint |
| D-040 | the Elder is unkillable for 20 s, and faster | 4.1 momentum, 4.2 AoE |
| `_check_win` comment | a team pooling B, O and G has not won | 2.4 per-team letters |
