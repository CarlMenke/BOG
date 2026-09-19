# PLAN_CAMERA — the PvP third-person rig, from the bottom

Owner's brief (2026-09-18): *"the camera and model need a better connection,
right now they are completely separated, which is too much freedom and allows
for things that end up not being fun for the user. ... we need third person
specifically for pvp, such as Fortnite; the third person that exists for story
games where they are completely separate does not work as well in a pvp. Rework
the camera from the bottom using this new approach, trying to not take anything
from the existing camera set up at all. Match what industry leaders in pvp
third person are doing. Keep it as simple as possible, overengineer only where
it is worth it."*

## The model: camera-locked facing

Today `Bog._face` turns the body toward its **velocity** and the rig orbits
freely; the body faces the camera only while aiming or throwing (`_face_view`).
That is the story-game rig (Zelda, Uncharted). The PvP rig (Fortnite, Apex in
3P, Warzone 3P, Gears, Splitgate) is the other way round:

1. **The body faces where the camera faces. Always.** Body yaw tracks camera
   yaw on the local Bog every physics tick. The mouse turns the character; WASD
   moves it relative to that facing. Strafes and backpedals are ordinary motion,
   and the animator's nine-point body-relative blend spaces already exist for
   exactly this — nothing in `bog_animator.gd` needs to change.
2. **Camera rotation has zero lag.** Yaw and pitch are the mouse, this frame.
   Rotation lag is the story-game feel and it is what makes aiming mushy.
3. **Camera position has a short lag.** The pivot eases to the eye point
   (horizontal fast, vertical slower so steps do not pump the view). This is
   Unreal's `bEnableCameraLag`; Fortnite ships it.
4. **Over the right shoulder, fixed.** No shoulder swap. Distances are the
   feel round's: 3.1 m back / 0.62 m right at rest, 2.15 / 0.48 aiming, aim FOV
   scale 0.82, sensitivity scaled by the same factor while aiming.
5. **The shot comes from the lens.** `aim_ray()` is the actual camera's origin
   and forward, wherever scenery has pulled it. The crosshair is therefore
   always truthful — screen centre is where the spear goes — and there is no
   lens-turning reticle correction to rate-limit. This supersedes the D-045 rule
   that the aim is read from the *unobstructed* camera; the cost (a wall at your
   back moves the shot origin forward by up to the pull-in) is the trade every
   Unreal third-person game makes, and it buys the simplest possible rig.
6. **Collision is Unreal's spring arm.** One sphere sweep from the pivot to the
   full desired lens point (pivot + basis * (shoulder, 0, distance)). The lens
   sits at the clear fraction of that one segment. Because the segment passes
   through the pivot, the shoulder shrinks with the distance automatically — the
   D-083 invariant (the Bog keeps its place in the frame while the camera comes
   in) falls out of the geometry instead of being a second channel. Pull-in is
   **instant** (a frame inside a wall is worse than a pop); return is eased
   (exponential, ~6/s) with a short hold (~0.2 s) so a picket fence is one
   pull-in and not a hunt. Nothing else: no lookahead, no fat probe, no
   rate-limited pull, no per-channel holds. Mask = world | camera blockers
   (1 | 64), never players. Probe radius 0.25 m, margin 0.05 m.

### Committed states: when the body does NOT follow the camera
The mouse still turns the camera in all of these; the body holds.
- **Spin / sword swing** (`is_spinning`, D-068) — the heading was paid for at
  the click. Hold `body_yaw`.
- **Roll out of a dive** (`is_rolling`) — hold the roll's heading.
- **Slide** (`is_sliding`) — momentum move: the body faces its horizontal
  velocity while sliding. On exit it swings back to the camera at the turn cap.
- **Emote** (`is_emoting`) — Fortnite exactly: the camera orbits the dancer,
  the body holds.
- **Dead / spectating** — the rig follows a subject; there is no body to steer.
  `spectate(target)` / `spectating()` keep their contract (HUD uses them).
- **Capturing a letter** (`is_capturing`, letters round) — out of scope; do not
  touch; body follows camera like any other stance.

### Turn rate
Body yaw → camera yaw with `rotate_toward` at `Bog.TURN_SPEED` (14 rad/s,
~800°/s). That is effectively instant for a drag and only lags a flick by a
frame or two, which reads as weight rather than delay. **No idle dead zone /
turn-in-place in v1**: the feet will slide when a standing Bog looks around;
Fortnite hides that with turn-in-place clips this repo does not have. Note it
as the one known cosmetic gap in the decision text.

### Idle yaw slack (added after the first evening on the rig)
The gap above came back as the first piece of feedback, and it is closed.
Owner: *"if they are standing still, not moving at all and just moving the
camera, then let them get it a little further around before it starts moving
the character, not all the way just further, and then if they start moving,
smooth it back to inside the previous clamp."* Fortnite's standing behaviour.

`Bog._face` now carries a **`_yaw_slack`**, the radians the view is allowed to
be off the body before it drags it:

- **60° (`Bog.YAW_SLACK`) while the Bog is idle**, set outright, not eased in.
  Idle means on the floor, `input_direction` zero, horizontal speed under
  `IDLE_SPEED` (0.35 m/s), not sliding, not aiming (`wants_aim`, read in
  `_read_input` off the `aim` action), not drawing, and not mid-wind-up
  (`BogAnimator.is_throwing()`). Everything on that list is the player pointing
  the Bog at something rather than looking at it.
- **Closing to 0 at `SLACK_CLOSE_RATE` (4 rad/s) otherwise.** A rate, not a
  switch: zeroing it outright would leave the body up to 60° off the view with
  only `TURN_SPEED` between them, i.e. an 0.075 s flick on the first step of
  every walk. 4 rad/s hands the whole 60° back over 0.26 s, slower than the
  body can turn, so what you see is the Bog squaring up as it sets off.
- Every tick: `desired = view_yaw − clamp(wrapf(view_yaw − body_yaw, −π, π),
  −slack, +slack)`, then the same `rotate_toward(body_yaw, desired,
  TURN_SPEED·delta)` as before. Inside the slack that resolves to `body_yaw`
  and the body holds; past it, to the slack's **edge**, so the slack travels
  round with the view rather than being an arc the view escapes from. At a
  slack of 0 it is the welded rig above, unchanged.

The committed states still win — `_face` returns for spin/roll/emote before any
of this, and a slide keeps facing its velocity. Remote Bogs need nothing:
`body_yaw` is already replicated, so what arrives on `sync_yaw` is slacked.

`faces` in `tools/camera_range.gd` grew three claims for it: a standing 45°
look must move the body **not at all**; a standing 90° one must leave it at
rest exactly on the 60° edge; and starting to run with the view held must close
that 60° inside 0.35 s with no single physics tick turning the body further
than `rotate_toward` can. Measured: 0.000° of standing drift, 0.000° off the
edge, 15 ticks to close, 0.0667 rad in the biggest tick of the close.

### What to remove from `Bog`
- `_face_view`, and the `face_view` argument of `set_view_basis`. New shape:
  `set_view_basis(basis: Basis, pitch: float)`. Movement (`_wish_direction`)
  still reads the flat view basis; `aim_pitch_local` still comes from `pitch`.
- The velocity branch of `_face`. `_face` becomes: committed-state checks above,
  else `desired = yaw_towards(-_view_basis.z)`.
- `backward_scale` and `BACK_SPEED_SCALE` (D-098) stay and now matter always.
- Rewrite the doc comments on those members; do not leave text describing the
  old model.

## Public API that must survive (callers outside the rig)
Node name `CameraRig` under `Bog`, `class_name BogCamera`, and:
`PITCH_MIN`, `PITCH_MAX`, `DISTANCE_DEFAULT`, `SHOULDER_DEFAULT`,
`aim_ray() -> {origin, direction, clear_of}`, `is_aiming()`, `shake(strength,
decay)`, `spectate(bog)`, `spectating()`, `look_at_point(point)`,
`set_view(yaw, pitch)`, `camera() -> Camera3D`, `yaw()`, `pitch()`.
Callers: `bog_combat.gd` (aim_ray, is_aiming), `bog_aim.gd` (pitch consts),
`hud.gd` (spectate), `match_state.gd` and `lightning_bolt.gd` (shake),
`tools/combat_range.gd`, `tools/camera_range.gd`, `tools/net_loopback.gd`.
`clear_of` in `aim_ray` is how far along the ray the Bog itself is; with the
shot from the lens that is the lens's actual distance from the pivot.

`look_at_point` swings the rig so the *lens's* forward passes through the
point (solve from the lens position; converges on the second call as before).

## Files owned by the agent (everything else is off limits)
- `scripts/player/bog_camera.gd` — **rewrite from an empty file.** Do not copy
  constants, comments, structure or helpers from the old one. Read it once to
  learn the public API and the physics masks, then close it.
- `scenes/player/bog.tscn` — only the `CameraRig` subtree. Rebuild it as you
  like (a flat `CameraRig` → `Camera3D` is fine; the pitch can live in the
  script).
- `scripts/player/bog.gd` — only `_view_basis`, `_face_view`, `set_view_basis`,
  `_face`, and their comments. Nothing else in that file.
- `tools/camera_range.gd` — rewrite the verdicts for the new rig (below).
- `tools/combat_range.gd`, `tools/net_loopback.gd` — the smallest edits that
  keep their legs meaningful under the new model (legs that relied on the body
  facing its velocity, or on the aim being read from the unobstructed camera,
  need their expectations restated, not deleted).
- New `docs/PLAN_CAMERA.md` — this document, copied in.
- **Never**: `docs/DECISIONS.md`, `docs/STATUS.md`, `docs/PLAN.md`,
  `tools/smoke_test.sh`, `project.godot`, `bog_animator.gd`, `bog_aim.gd`,
  `bog_combat.gd`, `hud.gd`, anything under `scripts/ui`, `scripts/game`,
  `scripts/items`. Report anything those would need instead.

## `tools/camera_range.gd` verdicts (headless, `--fixed-fps 60`)
Keep the five stations and the mouse-driven sweeps. Verdicts:
- `clip` — the lens is never inside scenery (point query, near-plane sphere,
  eye→lens ray). Zero frames.
- `frame` — the lens is never further off the pivot→desired-lens line than
  float slack (i.e. it is on the segment). Zero frames.
- `aim` — `BogCombat._aim_point` equals where a ray from `camera().global_position`
  along `-camera().global_transform.basis.z` hits, within 1 cm. Every checked
  frame. (Crosshair truthfulness replaces "unobstructed camera" as the invariant.)
- `calm` — with **no** scenery contact, the lens moves no more per frame than
  the body moved plus lag slack; and on the return leg after a pull-in the lens
  never moves out faster than the eased cap. Pull-in frames are exempt.
- `faces` (new) — after any mouse turn with the Bog standing or running, the
  body yaw is within 2° of the camera yaw within 0.1 s; during a sword spin and
  an emote the body yaw does not change while the camera turns 180°.
Print one `NAME PASS`/`NAME FAIL` line per verdict with the count, as today.

## Gate
In the worktree: `bash tools/smoke_test.sh` (source `tools/find_godot.sh` the
way it does). The camera check there requires `clip`, `aim`, `frame`, `calm`
PASS lines — keep those names so `smoke_test.sh` does not need editing; `faces`
is extra output. Also run `tools/combat_range.tscn` legs `aim`, `spine`,
`strafe`, `sword` and report their lines verbatim.

## Return to the orchestrator
1. The branch name and the commit list (commit on the worktree branch, do not
   push, do not merge).
2. Gate output: every check line, verbatim, especially any FAIL.
3. Decision-record text, in the house style of `docs/DECISIONS.md` (quote the
   owner's brief, say what was measured, what was rejected and why), **without
   a D-number** — the orchestrator claims the number at merge.
4. Anything in the forbidden files that now needs changing, as a list.
5. Numbers: the pull-in pops you measured (largest lens move in one frame at
   each station), and the body-yaw catch-up time.
