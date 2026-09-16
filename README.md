# BOG

A match-based third-person multiplayer game in Godot 4.7.2. You are a Bog — a
small tan creature with two antennae — fighting with thrown spears that kill in
one hit, on one of six maps: **Whisperbloom Hollow**, a floating
enchanted-forest island grown from a seed; **Rust**, a hand-made industrial
yard under a hard sun; **Kopje
Crossing**, a savanna plateau with a hundred and twenty-three rocks to climb; or
**Lantern Wharf**, a small walled box yard at dusk with two bases facing each
other across it; **Halcyon Wake**, a superyacht at anchor on a bright morning,
four decks high, where going over the rail is going into the sea; or **Twin
Quarry**, a worked-out stone pit built for capture the flag, where each team's
base sits four metres up on a cut bench with two haul ramps and no other way in. The
host picks in the lobby.

Spears are the whole fight. One lands, you die, and the thrower's hand is empty
until it grows back, so an empty hand is the most useful thing on screen: it
tells everyone in sight that the Bog holding it is harmless for the next few
seconds. Two abilities exist to bend that around: a **shield** — a barricade of
weathered planks, 1.75 m tall and 1.22 wide, planted facing exactly the way you
were looking — as cover you cannot be hit through, and a **magnet** lobbed past
it that drags everyone nearby out into the open for about a second. Neither is on a timer: you spawn
with neither, every death drops one item where the body fell, and you pick them
up by walking over them. Whatever you were carrying is lost when you die.

About one death in fifty drops something else: the **Elder's robe**. Walk over it
and for twenty seconds you cannot be killed — spears bounce off — you move a
third faster, jump half again as high, and throw lightning out of your hand
instead of a spear. The robe is visible to everybody from across the map, the
clock is visible only to you, and the counter-play is not to kill an Elder but to
outlast one. Falling off the map still counts, which is what the magnet is for.

A match ends on the kill limit, the last Bog standing, the clock, or one of two
letter modes. **Collect B·O·G**: letter cards fall out of corpses, and you hold
one up for ten seconds to keep it. **Capture B·O·G**: capture the flag, in
teams, with exactly three letters that you carry into your own team's base.

---

**Just want to play it?** See [`docs/PLAYING.md`](docs/PLAYING.md) — run one
`.exe` and paste an invite code. Only the person hosting has any setup to do,
and it is one playit.gg tunnel. The rest of this file is about building it from
source.

---

## Running it

You need [Godot 4.7.2 stable](https://godotengine.org/download) — the standard
build, not .NET. Nothing else: the decimated meshes and the sound effects are
committed, so a fresh clone runs without Python.

```bash
git clone https://github.com/CarlMenke/Gubs_Game
cd Gubs_Game
godot --path .            # or open project.godot in the editor
```

**It has to be 4.7.** Godot 4.6 does not politely refuse this project — it fails
to parse it, with a wall of `Too many arguments for "add_blend_point()"` that
reads exactly like a bug in this repository and is not one. That method gained a
fourth argument in 4.7. The scripts below reject a 4.6 binary rather than running
it, but if you are invoking Godot by hand, check `--version` first.

On Windows, `run.bat` does the same thing without you typing the path to Godot:

```
run.bat
```

`tools/smoke_test.sh` finds the binary itself — it searches `$GODOT`, then
`PATH`, then `/Applications` and Downloads under `$HOME`, `$USERPROFILE` and
every Windows user profile it can see, because `$HOME` is not the Windows
profile under every bash on Windows. It also runs under WSL, where it translates
the project path with `wslpath` first: Git Bash converts POSIX paths on the way
into a native binary and WSL does not, so an untranslated `/mnt/c/...` reaches
Godot as a path it cannot read.

For the other commands here, set it yourself. Godot is on `PATH` on none of the
machines this is developed on, and note that **the `.exe` in the Windows download
path is a directory**, not the binary — which catches everyone once:

```bash
# macOS — note that /Applications/Godot.app may well be an older one
GODOT="$HOME/Downloads/Godot_v4.7.2-stable_macos/Godot.app/Contents/MacOS/Godot"

# Windows — the `.exe` in this path is a DIRECTORY, which catches everyone once
GODOT="$HOME/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
```

On Windows use the `_console` binary for anything you want output from — the
plain one detaches from the terminal and prints nowhere.

### Controls

| | |
|---|---|
| move / sprint / crouch | `WASD`, `Shift`, `Ctrl` or `C` |
| jump, slide | `Space`, crouch while sprinting |
| dive | `Space` again in mid-air — once per jump, and you commit to it |
| throw spear | left mouse — winds up, leaves the hand 0.50 s later |
| the Elder's bolt | the same left mouse, while wearing the robe — 0.2 s |
| draw the bow | hold `V` or mouse 5 — longer draw, faster and harder arrow |
| aim (zooms in) | right mouse |
| shield, magnet | `Q`, `E` |
| drink a heal potion | `F` — two seconds, standing still; moving or being hit ends it and the potion is gone |
| scoreboard, pause, chat | `Tab`, `Esc`, `T` |

---

## Playing together

The host clicks **Host** and gets a ten-character **invite code** like
`K3M9P-2XQ7R`. Anyone else picks **Join**, types it in, and is in the lobby.

That code *is* the host's address — the IP and port, Crockford base32, no
backend anywhere. This is what makes it work on a LAN, over a VPN, or across the
internet, with nothing of ours to run and no account to make with us. It is also
the trade-off: a purely random key would hide the host's IP, but would need a
relay server to turn keys back into addresses. See **D-005** — this is a product
decision worth revisiting, not a settled one.

For play across the internet the host sets a **public address** in Settings —
the `host:port` of a [playit.gg](https://playit.gg) UDP tunnel forwarding to
local **27015** — and the code then carries that endpoint instead of a local
one. Players install nothing; the host runs one agent. Leaving it blank is the
old behaviour, which is a tailnet address if Tailscale is up and a LAN address
otherwise. See **D-028**.

One player hosts and plays at the same time, and the host is authoritative: it
owns every kill, score and respawn. Movement is client-authoritative so your own
Bog never feels laggy. Up to 8 players.

---

## Building a release

Both presets are committed. Windows is the one the game is played on; macOS is
universal, so it runs natively on Apple Silicon and on Intel.

In Claude Code, **`/host`** does this and the rest of getting a game going —
rebuilds only if the build is older than the sources, hands back the path to
share, checks the playit agent, and prints the invite code. It lives in
`.claude/skills/host/`.

```bash
"$GODOT" --headless --path . --export-release "Windows Desktop" "$PWD/build/windows/BOG.exe"
"$GODOT" --headless --path . --export-release "macOS"           "$PWD/build/macos/BOG.app"
```

Pass an **absolute** output path. A relative one is resolved against the project,
not against your shell, which is a confusing way to lose a build.

You need the **4.7.2 export templates** installed first — a one-time ~1 GB
download, either from *Editor → Manage Export Templates → Download* or straight
from the release:

```bash
curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
unzip -q Godot_v4.7.2-stable_export_templates.tpz
# macOS
mkdir -p "$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable"
cp templates/* "$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable/"
# Windows: %APPDATA%\Godot\export_templates\4.7.2.stable\
```

Without them the export fails with `No export template found at the expected
path`, which is the only thing standing between these commands and a binary.

The macOS build needs `textures/vram_compression/import_etc2_astc` on, which is
why it is set in `project.godot`. Godot refuses a universal or arm64 build
without it — those targets have no S3TC/BPTC hardware — and the error names the
setting. It costs import time and nothing at runtime on desktop.

The macOS app is signed **ad-hoc**, which is enough to run it yourself and not
enough to hand to a stranger without Gatekeeper objecting. Notarisation needs an
Apple Developer account and is not set up.

Sizes, for reference: `BOG.exe` is **389 MB** with the pack embedded, as of the
five-map build with the shield, the magnet and the three letter cards in it
(D-078 to D-081). Most of the growth since the 109 MB of the two-map build is
art, not engine.

## Working on it

Read these in order:

| | |
|---|---|
| `docs/STATUS.md` | **start here** — where things are and what to do next |
| `docs/ARCHITECTURE.md` | how it is put together, and where the seams are |
| `docs/PLAN.md` | the full scope, tracked to completion |
| `docs/DECISIONS.md` | why anything non-obvious is the way it is |

### Checking your work

```bash
bash tools/smoke_test.sh
```

Everything that can be checked without a person watching: the headless import,
the invite codes, the match rules, **a full playthrough from the main menu to
the results screen**, a ragdoll that has to survive hitting the ground, several
combat modes that report what they did — including the Elder's lightning, end to
end from the robe dropping off a corpse to the Bog at the far end falling over,
and a real spear thrown at a real Elder that has to bounce off — and three checks
that walk the path a player walks: that holding W moves a Bog, that starting a
match takes the mouse, and that leaving one does not leave Bogs asking a peer
that is gone. Twenty-one in all. Run it before committing anything that touches
gameplay.

Most of those exist because of one bug shape, met repeatedly: **a thing wired
into a testbed and into nothing else.** `tools/` scenes stand their subject up
directly and hand it whatever the real scene was meant to hand it, which makes
them very good at proving a feature works and blind to whether anything calls
it. Nothing read the movement keys in a real match; nothing instanced the HUD in
the arena; the ambience pointed at a path that never existed. All three passed
every check that existed at the time.

So: **if you add a harness, ask what it is supplying by hand** — that list is
the list of things nothing else is checking. And `playthrough` is the one that
catches the rest, because it is the only check that walks the joins between the
parts rather than testing inside one.

It fails on any `SCRIPT ERROR` as well as on a bad exit code, because Godot
prints one and carries straight on — a clean exit proves nothing by itself. It
fails the same way on `No multiplayer peer is assigned`, which is always a bug
and never noise, wherever in the suite it turns up.

What it **cannot** do is tell you whether anything looks right. That needs eyes,
and `tools/` is full of scenes for it:

```bash
# Render any scene to a PNG and quit. The number is PHYSICS TICKS (D-012).
"$GODOT" --path . --resolution 1280x720 --script tools/snapshot.gd -- \
    res://tools/combat_range.tscn out.png 62 hit
```

| tool | what it is for |
|---|---|
| `combat_range.tscn` | **the combat testbed** — a real match, one player, dummies |
| `sandbox.tscn` | flat playground for movement |
| `preview_assets`, `preview_anim`, `preview_grip` | the art, the clips, the spear in the hand |
| `preview_ragdoll`, `ragdoll_stability` | how a corpse falls, and whether it survives |
| `preview_sky` | the sky and environment |
| `preview_island` | **the island** — a dozen framings (plan view, eye height on any pad, under a tree), `match` for real Bogs, `hud` to keep the HUD |
| `island_report` | **the island as numbers** — footprint, slope, placed props per layer, tree heights, spawn spacing, capture bases. In the gate |
| `preview_map` | **a static map** — top-down, side, or eye height on any spawn pad; `probe` prints the floor as ASCII. Rust by default, `map=res://scenes/world/maps/safari.tscn` for the savanna, `map=res://scenes/world/maps/wharf.tscn min_triangles=1000` for the box yard, `map=res://scenes/world/maps/yacht.tscn min_triangles=1000` for the yacht, `map=res://scenes/world/maps/quarry.tscn min_triangles=400` for the quarry. Checks every pad with the physics, and is in the gate for all five |
| `parkour_report` | **a built map** — rebuilds the Bog's jump arc and proves every platform can be reached from the ground. Kopje Crossing by default; `map=res://scenes/world/maps/wharf.tscn` also proves no jump reaches a tower top and measures the longest sightline; `map=res://scenes/world/maps/yacht.tscn` proves every deck is reachable, the mast is not, and there is nothing but the void over the side; `map=res://scenes/world/maps/quarry.tscn` proves each team's bench is reachable by its two haul ramps and by nothing else, that no jump reaches a column top or the rim, and that no pad sees the other base's pads. In the gate for all four |
| `playthrough.tscn` | the whole flow, menu to results, headless. Add `-- rust`, `-- safari`, `-- wharf`, `-- yacht` or `-- quarry` to play it on a static map |
| `match_rules.tscn` | 195 assertions across 14 scoring scenarios, headless |
| `net_loopback.tscn` | two real processes over a real socket, ten rematches included. Run by hand through `net_test.sh` (not in the gate, ~45 s); binds loopback only |
| `inspect_scene.gd` | dump a scene's tree, clips, bones and triangle counts |
| `preview_anim`, `preview_grip`, `preview_ragdoll` | contact sheets of a clip, the spear in the fist, a corpse falling |

`combat_range` runs the **real match path** — an offline session on `Net`, a
roster, `MatchState.register_arena`, kills through `MatchState.report_kill` — so
a throw that works there works in a match. Pass a mode as the trailing argument
(`flight`, `hit`, `arc`, `miss`, `aim`, `shield`, `cover`, `magnet`,
`magnet_self`, `letter`, `cards`, `lightning`, `ward`, `recharge`, `walk`,
`health`, `embed`, `hurt`,
`leave`, `free`) and `trace` after it to print the whole flight, which is the
only way to tell a miss from a hit whose kill was dropped.

Several modes print their own verdict and need no picture, so they are run
headless straight from the scene rather than through `snapshot.gd`:

```bash
Godot --headless --path . tools/combat_range.tscn -- cover
Godot --headless --path . tools/combat_range.tscn -- recharge
Godot --headless --path . tools/combat_range.tscn -- ward
```

`cover` is the one to reach for after touching `shield.gd`: it stands a
real shield up, prints the blocked width at every height a Bog occupies, and
then asserts that a spear is stopped by one, that the same throw without one is
not, and that a Bog cannot walk through it (D-039, D-079).

`ward` is the one to reach for after touching anything about the Elder: it puts
a robe on a dummy, throws a real spear at it, and asserts that the Elder
survives, that the robe then burns out on its own clock, and that the *same*
throw kills once it has (D-040). That third verdict is not a nicety — without a
control on the same geometry, "did not die" is satisfied by a spear that never
left the hand.

### Regenerating the art and audio

Both are committed, so you only need this if you change a source file:

```bash
bash tools/build_bog.sh             # the Bog: several Mixamo packs → one .glb. Needs Blender 5.2
python tools/decimate_assets.py     # spear, magnet, shield, B, O, G. numpy, scipy, pillow, fast_simplification
python tools/make_sfx.py            # needs numpy
python tools/prepare_map.py         # needs numpy, pillow
python tools/rig_report.py          # checks the Bog's rig; prints, changes nothing
```

The three props arrive at ~500k triangles each and leave at 19k between them,
with UVs transferred back seam-aware. The **three letter cards** — the meshes
the letters win condition puts on the ground and in a fist (**D-041**) — go
through the same script, and not all three for the same reason. The B and the
G arrive from Tripo at 8.5k and 9.3k triangles, so 6000 is barely a decimation;
what *they* are in the target list for is the 4096-square base colour coming
down to 512, the embedded image being renamed so Godot extracts it as
`letter_g_basecolor.png` rather than `letter_g_G_LETTER_basecolor.jpg.png`, and
the repack into one clean single-buffer `.glb`. The O (**D-080**) is the odd one
out: it arrives at 429,870 triangles, a prop-sized mesh in a letter's clothing,
and takes the same 6000 as a real 1.4% decimation. **The Bog has its own pipeline** and does
not go through `decimate_assets` at all: `tools/build_bog.sh` runs
`tools/build_bog.py` in headless Blender, which consolidates the declared FBX files
in `assets/source/GUB_2/` into one 1.5 MB `art/generated/bog.glb` — one armature,
one mesh, nine clips, 10.5k triangles, 1.80 m tall, root motion locked, every
clip's facing aligned — and prints every measurement it takes (**D-029**). Three
runs of it produce a byte-identical file, and it refuses to write one whose jump
clips go through the floor. After a rebuild, run
`"$GODOT" --headless --path . --import` once so Godot re-extracts the texture.

`tools/rig_report.py` is how you tell whether a rig change helped, and is worth
running after any change to the rig or to a source file. Sources in `assets/` are
never modified; re-running any of these is always safe.

**Maps are split raw/processed, and only the processed half is in the repository.**
`tools/prepare_map.py` reads `assets/source/Rust/rust.glb` — a 337 MB Blender
export of the Rust arena, 333 MB of which is fifty-two lossless 2K PNGs — and
writes `art/maps/rust/rust.glb` at about 43 MB. It drops Blender's default cube
and the scale-reference figure the map was blocked out against (along with the
one animation clip, which only ever animated that figure), prunes everything
left unreferenced, and re-encodes the textures as JPEG: base colour at 2048 q85,
normal maps at 1024 q90 with no chroma subsampling, and the handful of normals
covering more than 5% of the arena's surface area held at 2048. The one texture
with a real alpha channel stays a PNG, because JPEG has nowhere to put it. The
raw export is `.gitignore`d — it is over GitHub's 100 MB single-file limit — so
it lives on the team's shared drive and only has to be on disk when the map is
being regenerated. Geometry is untouched: the export is already 1 unit = 1 metre
(D-002). The run prints the arena's true world bounds and its lowest vertex,
which is where the match's void kill height comes from, and then re-reads what it
wrote and checks it.

The **textures Godot extracts back out** of that `.glb` are `.gitignore`d, and
only `rust.glb` and `rust.glb.import` are committed. The importer is set to
Extract, which is what gets each of the 51 images its own VRAM compression — but
it writes all 41 MB of them out beside the file they came from, which would
nearly double the map's cost in the repository to store nothing new. They come
back in about half a minute from the import step that `tools/smoke_test.sh` runs
first and that the editor runs on a fresh clone, so there is nothing to do by
hand.

**The map itself is four nodes and eight coordinates.** `scenes/world/maps/rust.tscn`
instances the `.glb` untouched; `scripts/world/static_map.gd` builds the
collision and puts back the back-face culling at load, because neither survives
the import (**D-031**). `tools/preview_map.gd` is how you look at it and how the
gate checks its spawn pads.

**Kopje Crossing has no import at all.** `scenes/world/maps/safari.tscn` is the
same four nodes, but its script, `scripts/world/maps/safari_map.gd`, builds the
map in `_ready` out of MegaKit rocks placed from layout tables and then lets
`StaticMap` bake the collision exactly as it does for Rust. Editing the map means
editing a table; `tools/parkour_report.gd` then says whether every platform is
still reachable (**D-042**).

**Lantern Wharf is built the same way**, smaller: `scenes/world/maps/wharf.tscn`
and `scripts/world/maps/wharf_map.gd` lay out a 36 m yard of painted containers
and crates from tables, with corrugation textures computed in code rather than
loaded. It is the first map to declare its own Capture B·O·G bases and letters,
and `parkour_report` holds it to a 25 m sightline (**D-056**).
loaded. It is the first map to declare its own Capture B·O·G bases and letters,
and `parkour_report` holds it to a 25 m sightline (**D-056**). The plant around
the boxes — pipe runs up the wall faces, machinery along the wall tops, panels
and floor markings — is Kenney Factory Kit, added after the collision is baked
and kept either above head height or flat on the ground, because on a map this
tight a prop at the height of cover that a spear flies through is a lie
(**D-060**).

**Twin Quarry is built the same way as well**, and is the first map whose
layout came out of a game mode rather than a picture:
`scenes/world/maps/quarry.tscn` and `scripts/world/maps/quarry_map.gd` cut a
48 m stone pit out of tables, put each team's Capture B·O·G base four metres up
on a bench in opposite corners, and leave exactly two haul ramps up to each. Its
symmetry is a 180 degree turn rather than a mirror, which is why the middle of
the map is a thirteen-metre rock: under a turn every spawn pad's line to its
opposite number runs through the origin. It is also the one map that dresses
itself out of the MegaKit — rubble, weeds and dead trees, none of it collision —
because an abandoned quarry taken back by weeds is the only thing that puts a
colour in a hole full of grey stone (**D-058**).

**Halcyon Wake is built the same way too**, and goes up instead of out:
`scenes/world/maps/yacht.tscn` and `scripts/world/maps/yacht_map.gd` loft a 66 m
hull and stack a main deck, upper deck, sun deck and flybridge on it from tables,
joined by stairs (ramps in the collision, treads in the render) and hop steps.
The sea is not collision; `void_height` is half a metre under it, and
`parkour_report` proves every deck is reachable and that nothing but water lies
over the side (**D-057**).

---

## Layout

```
art/generated/   game-ready meshes and textures — committed, no Python needed
assets/          raw source art (.gdignore'd; the two kits are imported)
audio/sfx/       synthesised sound effects — committed, see tools/make_sfx.py
docs/            STATUS, PLAN, DECISIONS, ARCHITECTURE
resources/       shaders, environment, bus layout
scenes/          player, items, ui, world
scripts/         game, items, net, player, ui, util, world
tools/           dev tools and testbeds — none of this ships
```

Autoloads: `Settings`, `Net`, `MatchState`, `SceneFlow`, `AudioDirector`.

---

## Credits and licence

The game's own code and assets are **MIT** licensed — see [LICENSE](LICENSE).

Environment art is the **Stylized Nature MegaKit** by Quaternius (CC0), the
**Factory Kit** by [Kenney](https://kenney.nl) (CC0) and Kenney's **City Kit
(Industrial)** (CC0) — the first is the nature pack the island, the savanna and
the quarry's weeds and rubble come out of; the second is the industrial kit, 143
models on a 1 m grid sharing one 64-pixel colour atlas, which dresses Lantern
Wharf's plant. The Bog, spear, magnet and shield are project assets. Sound
effects are synthesised from scratch by `tools/make_sfx.py`.

Every kit keeps its own `License.txt` beside the models rather than only being
