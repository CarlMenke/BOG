# BOG — Master Build Plan

> Current position and how to resume: **`docs/STATUS.md`**.

A match-based 3rd-person multiplayer game in Godot 4.7.2. Players are BOGs — small yellow
aliens — fighting on a floating enchanted-forest island with instant-kill thrown spears.

This was the source of truth for scope until 2026-09-18. It is now a frozen build
log: the open items moved to Linear (workspace BOG) that day and new work goes
there, not here. See `CLAUDE.md`. Every item below is tracked to completion.
Design rationale for non-obvious choices lives in `docs/DECISIONS.md`; how the
pieces fit together is `docs/ARCHITECTURE.md`.

---

## Phase 0 — Foundation

- [x] 0.1  Git repo, `.gitignore`, `.gitattributes`, LICENSE, README
- [x] 0.2  Godot project skeleton: `project.godot`, input map, physics layers, render settings
- [x] 0.3  Asset pipeline — decimate the 500K-tri source meshes to game-ready density,
           preserving UVs + skin weights; generate import presets
- [x] 0.4  Docs: PLAN.md, DECISIONS.md, ARCHITECTURE.md

## Phase 1 — Networking & Lobby

- [x] 1.1  `Net` autoload — host / join / disconnect, peer registry, player info replication
- [x] 1.2  Invite-code system — short shareable code that encodes the host endpoint
- [x] 1.3  Main menu — name entry, Host, Join-by-code, Settings, Quit
- [x] 1.4  Lobby UI — player list, invite code + copy, match settings (host-only),
           ready toggle, team pick, start button, chat
- [x] 1.5  Lobby 3D backdrop — real Bogs standing in a ring with live nameplates
- [x] 1.6  `MatchConfig` resource — mode, limits, timers, cooldowns, friendly fire
- [x] 1.7  Scene flow — Menu → Lobby → Game → Results → Lobby
- [~] 1.8  Robust disconnect handling — host leaves and client drops are done and
           now proven over a real socket by `tools/net_test.sh`: a dropped peer's
           Bog is freed on every machine and the win check re-runs, so a lives
           match can still end. **Mid-match join as spectator is not**: a late
           joiner is never told about Bogs that already exist, because
           `_create_bog` is broadcast once at spawn time. It needs a
           world-state-on-join message. The UI's response to a mid-match
           disconnect has still only been seen in a harness.

## Phase 2 — The Bog (character)

- [x] 2.1  Bog scene — CharacterBody3D, capsule, skinned mesh, skeleton
- [x] 2.2  Third-person camera rig — spring arm, collision, shoulder offset, aim zoom
- [x] 2.3  Movement — walk / run / sprint, jump, crouch, slide, air control, coyote time
- [x] 2.4  AnimationTree — a blend tree built in code over the clip library
           `art/generated/bog_clips.res` and the markers on its clips: three
           ground planes and a crouch plane, arc-scrubbed air poses, one-shots
           for the actions, upper-body layers so throwing works while moving
           (**D-029**, rebuilt on the new pipeline in **D-098**)
- [x] 2.5  Nameplate — billboarded Label3D, team tint, distance fade, occlusion
- [x] 2.6  Network sync — transform + animation state, interpolation, ownership
- [x] 2.7  Ragdoll — 13 physical bones built at runtime, death impulse, corpse cleanup

## Phase 3 — Combat & abilities

- [x] 3.1  Spear permanently held in the right hand (bone attachment)
- [x] 3.2  Throw — aim, wind-up, release, arcing projectile
- [x] 3.2a Spear trail
- [x] 3.3  Hit resolution (server-authoritative), instant kill
- [x] 3.3a Spear sticks in the corpse
- [x] 3.4  Spear regeneration — the hand empties on the throw and refills on the cooldown
- [x] 3.5  Shield — deployed in front of the Bog, blocks spears, timed/HP, cooldown
- [x] 3.6  Magnet — thrown, arms on landing, briefly yanks nearby Bogs in and holds them
- [x] 3.7  Death & respawn — spawn points, spawn protection, fall-off-island death
- [x] 3.8  Feedback — sounds, hitmarker, camera shake and kill feed (6.3)

## Phase 4 — The map (Whisperbloom Hollow)

- [x] 4.1  Procedural floating island — surface heightfield + rocky underside + collision
- [x] 4.2  Out-of-bounds death volume below the island
- [x] 4.3  Seeded prop scatter — trees, bushes, ferns, grass, flowers, mushrooms, pebbles
- [x] 4.4  Hand-placed landmarks — shrine, mushroom grove, rock arch, log bridges, high ground
- [x] 4.5  Torches — mesh, flame particles, flickering light, crackle audio
- [x] 4.6  Sky — custom shader: dusk gradient, stars, moon, aurora, drifting cloud band
- [x] 4.7  WorldEnvironment — volumetric fog, glow, SSAO, tonemap, colour grade
- [x] 4.8  Ambience VFX — fireflies, drifting spores, wind-swayed foliage, falling leaves
- [x] 4.9  Ambient audio — forest loop, wind, water
- [~] 4.10 Spawn points + traversal pass (scale, sightlines, cover balance)
           *8 spawns solved and placed, and the stone paths are a traversal pass
           made visible — but no one has walked the map. Two pads can also end up
           ~3.8 m apart on the default seed; the ring solver enforces slope and
           landmark clearance but not separation between pads.*

## Phase 5 — Match rules

- [x] 5.1  `MatchManager` — warmup / playing / post-match phases, authoritative timers
- [x] 5.2  Free-for-all — kill limit, time limit
- [x] 5.3  Teams — assignment, team colours, team score, friendly fire toggle
- [x] 5.4  Lives / elimination — last Bog standing, spectate on elimination
- [x] 5.5  Match end → results screen → rematch or back to lobby

## Phase 6 — UI / UX

- [x] 6.1  HUD — crosshair, ability cooldowns, score, timer, lives
- [x] 6.2  Scoreboard (hold Tab)
- [x] 6.3  Kill feed
- [~] 6.4  Pause & settings — sensitivity, FOV, volume, quality preset, keybinds
           *all of it except keybinds, which are shown as a reference and cannot
           be rebound*
- [x] 6.5  Spectator camera — a dead or eliminated player follows whoever is
           still alive, and cycles with the mouse buttons
- [x] 6.6  Scene transitions / loading
- [x] 6.7  Chat (lobby + in-match)
- [x] 6.8  The look — seven candidate themes built over a parameterised copy of the
           real builder in `tools/showroom/` and photographed on the real menu, lobby
           and HUD with the live 3D behind them; the owner picked **Quiet** (white at
           an alpha, no borders, one accent, a 72 px wordmark) and it is baked into
           `resources/ui/bog_theme.tres` (**D-117**)
- [x] 6.9  The layout, on all three screens, chosen the same way: the menu becomes one
           bar along the foot with a random quip under the wordmark; the lobby becomes
           a 460 px match rail and a 480 px room with the ring reframed to stand in the
           gap on three ranks of nameplate, and the weapon and skin pickers move to a
           Weapon and Character page with a computed portrait and 256² cut-out
           thumbnails; the HUD moves everything about you to the bottom-right, the kill
           feed to the left edge, and takes the borders off the ability tiles
           (**D-118**)

## Phase 7 — Ship

- [x] 7.1  Export presets (Windows + macOS universal), icon, app metadata
- [x] 7.2  Headless import + automated smoke test script
- [x] 7.3  README — how to build, run, host, and join
- [x] 7.4  Final pass + tagged commit — both binaries build, the macOS one boots
           clean, `feat/complete-game` is merged to `main` and the release is
           tagged `v0.1.0`

## Phase 8 — The animation rebuild (D-095..D-101)

- [x] 8.1  Import layer — the body and every clip imported by Godot itself at one scale,
           a post-import script that records speed, locks the hips and files the clip
           in one shared library; `clip_check` in the gate (**D-095**)
- [x] 8.2  Clip choice — one clip per role, chosen on posture, speed and family with
           `clip_measure` and `preview_bog` (**D-096**)
- [x] 8.3  Clip table and markers — `face` and `markers` per row; every event placed
           from the clip's own kinematics and a sheet (**D-097**)
- [x] 8.4  Animator — rebuilt on the library and markers, no clip time in the file;
           the game on the new body (**D-098**)
- [x] 8.5  Grips, aim, ragdoll, robe — solved on the new hands, capsules off the mesh,
           the robe refit as a skin (**D-099**)
- [x] 8.6  Skins — a folder each, recolour and clothing examples, a README (**D-100**)
- [x] 8.7  Retire the old path — Blender builds, packs and GLBs gone; `assets/source/`
           is the clips (**D-101**)
- [ ] 8.8  Two clips only the user can fetch. The one-handed carry idle with the fist off
           the body (D-099) is **done**: it is `SpearCarry`, the spear's grip is
           re-solved over it and its trunk clearance is a measurement again (**D-103**).
           Still open: the Magic pack's `Standing Run Left` for a true lateral strafe,
           with a `mirror_of` rule for its twin (D-098)
- [x] 8.9  Skin picker — a strip in the lobby: your own skin in free-for-all, your
           team's in Teams, no two teams alike, and the ring and the arena wearing
           what was picked (**D-109**)

## Phase 9 — The practice range (D-112..D-116)

- [x] 9.1  Practice as a property of the map, not a win condition: a `practice` row in
           `MapCatalog`, five `effective_*` accessors on `MatchConfig` that every rule
           is read through, a **Practice** button on the main menu (offline, no lobby),
           the Limits rows folded away in the lobby, and a dummy substrate — real Bogs
           on roster rows at id 900+, hidden from every roster-derived screen, whose
           `Sync` node alone changes hands so the host drives them. `hit_landed` and
           `place_pickup`/`pickup_taken` are the two doors cut for the rest
           (**D-112**)
- [x] 9.2  Glowworm Grounds (`range`) — a cleared bog at night, 60 x 90 m, nine zones
           off one lodge deck: three throwing lanes, a 60 m bow lane, a gallery, a
           melee pit, an ability yard, a parkour course and two void lips. Built from
           `const` tables like every static map, its `EXPECT` row turns the sightline
           scan off and says why, and the gate greps its marker census (**D-113**).
           *The hour is golden now rather than night, and the lane fences are one
           0.60 m rail: **D-119** supersedes this line's sky and its dividers.*
- [x] 9.3  Dummy brains and stations — eight behaviours, each a position as a function
           of time because a dummy has no physics on any peer; the jumper's arc solved
           rather than integrated; the pop-up 2.6 m under the floor; six signposts
           through one RPC on the director; a parkour clock (**D-114**).
           *The stations are gone — **D-119** supersedes the six signposts, the
           cycling and the director's RPC. A zone's behaviour is authored in
           `range_map.gd`'s tables and never changes; the brains themselves stand.*
- [x] 9.4  Items in the world — item wells that re-mint a real `Pickup` on their own
           timer, a refill stone with its own caps (2/2/1), and weapon racks that swap
           your weapon live through `MatchState.set_weapon`, because D-069's lock-in
           was a rule of the lobby and never of the code (**D-115**)
- [x] 9.5  Targets and feedback — boards, drifting orbs and a gong, reached by
           `range_hit` rather than through the damage door; a hit marker on every
           landed hit **on every map**; damage numbers, distances and a per-weapon
           stats panel in the range only, with the same table on the lodge wall
           (**D-116**). *The marker's shape and its kill are **D-122**.*
- [ ] 9.6  Never played by a person. The whole of it is proven headless — four tools
           and thirty-one gate checks — and nobody has stood on the deck, walked a
           lane and shot at anything. The questions that need eyes: whether the
           golden-hour lighting reads at 45 m (the night it was asked of is
           D-119's), whether a lane says what it is now that nothing switches it,
           whether a rusher is fun or merely alarming, and whether the parkour
           course teaches the jump arc or just frustrates

## Phase 10 — The feel round (D-119..D-124)

Thirteen pieces of playtest feedback, grouped by the code they touch into six
units and implemented in parallel; `docs/PLAN_FEEL.md` is the spec they were
argued against.

- [x] 10.1  Sunset, not night. `resources/shaders/range_sky.gdshader`, a fork of
            Kopje's `safari_sky.gdshader` (D-061) with a third gradient stop, a
            stated cloud shadow colour and a warm wash keyed on the angle to the
            sun; a `Sun` 9° up on a bearing 30° east of north, so a 50.5 m shadow
            off the west bank falls off the map and no lane has the disc at its
            vanishing point. `ambient_light_energy` 8.0 → 0.62 and a shadowless
            `LIGHT_ONLY` `Bounce` at −6° from the south-south-west, so the peat at
            45 m medians 82–126 of 255 and no front pad crushes a pixel; the fog
            thinner and warmer (0.9 m at 0.015), the backdrop snags shadowless, and
            the lanterns, glowworms and torches kept, dimmer and warmer (**D-119**)
- [x] 10.2  The lanes stopped being a stockade — one rail at **0.60 m** in place of
            eight lines of 1.8 m timber, posts still 2.2 m because they carry the
            lanterns, cover blocks still 1.25 m because they hide a pop-up
            (**D-119**)
- [x] 10.3  No stations. The six signposts, the walk-near cycling, `RangeDirector`'s
            rings, reserve and RPC are gone; a zone's behaviour is authored in
            `range_map.gd`'s tables and never changes, the four reserved dummies
            stand up (27 markers, 27 dummies), and the stats reset is a plain timber
            signboard with no lantern, no light and no chime (**D-119**)
- [x] 10.4  The character page keeps its Bog where he stands. `PORTRAIT_STEP` and
            `_stage_spot` are gone; `_bog_wanted` hides every slot but your own
            while the page is open, on this client only, so the subject stays on the
            ring lit by the fire from the front. The framing re-solved at radius 3.0:
            `PORTRAIT_SUBJECT_X` 0.32 and the crop down to the ground (**D-120**)
- [x] 10.5  The bow off the face. `preview_carry -- measure` gains `HEAD_MIN`, the
            0.06 m the spear already owes the skinned head, and `-- probe` maps the
            whole 360 × 180 of the tilt: `CARRY_TILT` (47.5, −34) → (40, +10), head
            clearance 0.002 → 0.134 m and the layered floor 0.173 → 0.431 m
            (**D-121**)
- [x] 10.6  A hit marker that lands, and a kill with its own shape. Arms 3 px, a
            snap in from 1.4× over 70 ms before the fade, hit held 0.45 s; a kill is
            a full X through the centre gap held 0.6 s with `hitmarker_kill.wav`
            under it, and the void and fall kills take that shape too. Sword, spear,
            arrow and lightning each proven to reach it (**D-122**)
- [x] 10.7  A full draw creeps. `target_speed()` scales by `lerp(1.0,
            DRAW_SPEED_SCALE, draw_fraction())` with `DRAW_SPEED_SCALE = 0.5` —
            brace 2.30, half 1.72, full 1.15 m/s, and free on the seven screens that
            are not yours because `draw_fraction()` reads `sync_draw` (**D-123**)
- [x] 10.8  The camera comes in. `DISTANCE_DEFAULT` 3.6 → 3.1 and `DISTANCE_AIMING`
            2.4 → 2.15, shoulders unchanged, `bog.tscn`'s own Camera3D moved with
            the constant; the probe still clears the scenery on all 1700 frames
            (**D-123**)
- [x] 10.9  A slide jump is its own move: `max(current, SLIDE_SPEED) * 1.2` along
            the slide's heading with 1.12 of the jump impulse, replicated as
            `sync_slide_jump_serial` so remote animators see the take-off, and
            deliberately not stacking with the bunny hop's `_hop_gain` (**D-123**)
  - [x] 10.9a  **Its own clip.** `SlideJump` shipped drawn with `RunJump` through
               `BogAnimator.clip_or`; the same evening `Doing A Forward Flip While
               Running` was chosen from the 33 `"flip"` takes and its
               `lift`/`apex`/`land` placed off `tools/clip_events.gd` (**D-125**)
- [x] 10.10 Crouch alone slides. `wants_sprint` is dropped from entry, the speed
            floor and the cooldown are what make it a decision, and a crouch held in
            the air pre-arms the pose (`_crouch_pose` beside `_crouch_blend`) so a
            slide can begin on the landing tick with neither `Land` nor `LandHard`
            (**D-123**)
- [x] 10.11 Hands out, and a fist. **H** toggles `sync_holstered`, the fifth clause
            of `has_spear`/`has_bow`/`has_sword`, which empties the fists on eight
            screens and buys `FISTS_SPEED_SCALE` (5.94 m/s against 5.40); LMB then
            punches for 20 at 1.1 m inside a 50° front on a 0.5 s cycle, as an
            upper-body one-shot, with the host checking the attacker's own published
            holster (**D-124**)
  - [x] 10.9b  **A drawn bow through a jump.** The draw layer is square to its
               own hips and the archer's turn is the pelvis's; the air pose and
               `Land` took that pelvis away and the top half swung 92° left.
               `BogAim` lerps its yaw by `BogAnimator.plane_lost()` and
               `movement_check` holds a draw through a jump: 1.0° of swing,
               2.3° on the worst landing frame (**D-127**)
  - [ ] 10.9c  **The second skin batch, parked.** Eleven baked skins (`Skins.PARKED`)
               wait on Tripo retextures of the original 15 872-vertex mesh; when
               the downloads come back at that count, `extract_skins.py`, append
               the names after `void`, `skin_thumbs`, and the gate's count goes
               to twenty-five (**D-128**)
  - [x] 10.11a **Its own clip.** `Punch` shipped drawn with `Cast` through
               `clip_or`; the same evening `Cross Punch` was chosen from the 68
               `"punch"` takes and its `hit` placed at the fist's arrival
               (**D-125**)
- [x] 10.12 The dance empties the hands — `_bare_handed()` is the one sentence the
            holster and the emote share, and the prop comes back off `_tick_hand`'s
            existing poll (**D-124**)
- [x] 10.13 The great sword got a second attack rather than a nerf: the primary
            click is a three-slash chain on `SwordCombo`, 50 a slash so two connect
            to kill, upper-body over the sword plane at `SLASH_SPEED_SCALE` 0.85 with
            turning and jumping allowed and `sword_recharge` (0.8 → 0.5) running
            between chains, while `SwordSpin` becomes the **sprint attack** at 0.8 of
            run speed for the committed 100 (**D-124**)
- [ ] 10.14 A `✊` kill-feed glyph for the fist. Deliberately left out this round —
            the feed draws a weapon's glyph and the fist has none, so a punch kill
            reads with the default
- [ ] 10.15 `fist_hit.wav`. Also left out this round: the punch lands with no sound
            of its own, and `tools/make_sfx.py` is where it would be synthesised
- [ ] 10.16 **Nobody has played any of this.** Every claim above is a render, a
            headless tool line or a gate check; not one of the thirteen has been felt
            by a person with a mouse in their hand. Phase 9's 9.6 is the same
            sentence about the range itself and stays open beside this one

## Phase 11 — The letters round (D-129..D-134)

One letters game, called B·O·G: Free-for-all is the collect race, Teams is
capture-the-flag, and the Match type switch is the only thing that picks
(**D-129**). `docs/PLAN_LETTERS.md` is the contract the six groups coded
against. Every item below is a render, a headless tool line or a gate check;
nobody has played it.

- [x] 11.1  One letter alive at a time in the collect race; every death deals the
            next letter when none is out or being captured, B→O→G from B;
            `letter_drop_chance` deleted; the "Ends on" picker's fourth entry is
            **B·O·G** and the clamp says the mode decides the flavour (**D-129**)
- [x] 11.2  The hold row carries `started_at` and `seconds`; `letter_hold_fraction`,
            `letter_hold_total`, `letter_hold_is_timed`, `loose_letter_pickups`,
            `letter_carriers`, `letter_appeared` (**D-129**)
- [x] 11.3  The guide line: `scripts/world/nav/` — a navmesh baked per client per
            map from layer-1 colliders, jump and drop links from `JumpArc` (lifted
            out of `parkour_report`), a two-pass dashed ribbon in gold / red /
            blue, trunk-merged in Capture, hysteresis at 2 / 3 m; `nav_check` in
            the gate on every map (**D-130**)
- [x] 11.4  The capture performance: `CaptureRig` floats the letter from above the
            raised right hand down into a procedural wool pouch in the left over
            the hold, `Sunburst` and `letter_captured.wav` when it lands; the
            `capture` upper-body layer on the `Capture` role with `CastIdle` as its
            stand-in; the steal in reverse; a carry keeps the card in the fist
            (**D-131**)
- [ ] 11.4a **The real `Capture` clip.** The row is a `"reaching"` search; fetch,
            pick a take with the arm overhead, fill in `mixamo_id`, drop the query
- [ ] 11.4b **A Tripo pouch.** `PouchMesh.build()` is primitives; a downloaded sack
            is one row in `decimate_assets.py` and one `preload` in `held_gear.gd`
- [ ] 11.4c **The pouch grip off a render.** `POUCH_GRIP_OFFSET`/`ROTATION` were
            written down, not solved; `tools/preview_capture.tscn -- f=0.9 pouch`
            prints the anchors to correct them against
- [x] 11.5  The minimap: a heading-up circle top-right, on under B·O·G only, the
            navmesh outline as its ground, teammates, loose letters and carriers,
            never an enemy without a letter (**D-132**)
- [x] 11.6  The tutorial: six drawn, looping cards; HOW TO PLAY on the menu and
            auto-once on the first B·O·G lobby (`Settings.tutorial_seen`);
            `CAPTURING` on the lamp (**D-132**)
- [x] 11.7  The menu's wordmark is three real letters over the fire, bobbing and
            swaying, the hero Bog beside the fire; one rig at one size in menu and
            lobby; the letters dip and launch out of frame on Start before the fade
            (**D-133**)
- [x] 11.8  The finger grip layer: five poses measured out of the clip library into
            `art/generated/grip_poses.res`, two filtered blends over the emote
            (**D-134**)
- [x] 11.10 **The range by day** (**D-135**): fences, lantern spheres, the orb
            launcher and the orbs off; the sun 9° → 32° on the same bearing with a
            daytime sky; renamed Highsun Grounds; and the rule — nothing in the
            world is a bare unshaded primitive, unshaded emissive is for effects
- [x] 11.11 **A moon over the viewer's shoulder** (**D-136**): a directional fill
            aimed from each camera's own framing at a measured third of the fire
            on the body; the hero 0.35 m right and 0.5 m back; the lobby eye 18%
            further out so the 3.5 m ring sits inside the panel band again
- [x] 11.12 **Rebindable controls** (**D-137**): every Controls row is a button —
            click, press, bound; Esc cancels; right-click resets one; RESET
            CONTROLS resets all; a key taken is taken off whatever else had it.
            Saved in `settings.cfg` as the difference from `project.godot`
- [ ] 11.13 Distance marks for the range: the posts that said "twenty metres" went
            with the fences (**D-135**); flush cut-stone plaques let into the peat
            are the themed answer if the lanes read thin
- [ ] 11.9  **Nobody has played any of this.** Same sentence as 10.16 and 9.6: the
            line, the pouch, the minimap and the menu are numbers and renders until
            somebody with a mouse says otherwise
