---
name: host
description: Get BOG ready to play with other people. Rebuilds the Windows .exe if it is stale, hands back the path to share, makes sure the playit.gg tunnel is up, and prints the invite code to read out. Use whenever the user wants to host, play with friends, share a build, or says "set up multiplayer" / "let's play".
---

# Host a BOG game

One command between "I want to play with people" and a file plus a code to paste
into chat. Four things, in order, each skippable if it is already true:

1. **Build** `build/windows/BOG.exe` if it is older than the game's sources.
2. **Path** — hand back the absolute path so it can be shared.
3. **Tunnel** — playit agent running, public address set, hostname resolving.
4. **Code** — the invite code the lobby will hand out, computed ahead of time.

The background for all of it is `docs/PLAYING.md`. Read it if anything here is
surprising; it is the player-facing version of this same setup.

## Arguments

| | |
|---|---|
| *(none)* | Windows only. This is the target the game is actually played on. |
| `mac` | macOS instead of Windows. |
| `both` | Windows **and** macOS. Roughly doubles the build time. |
| `force` | Rebuild even if the existing build looks fresh. Combines with the above. |

## 1. Find Godot, and check nothing is in the way

```bash
ROOT="$(pwd)"; GODOT_TAG=host . tools/find_godot.sh
echo "$GODOT ($GODOT_VERSION)"
```

`tools/find_godot.sh` is the repo's own answer to where Godot is — it is sourced,
not run, and it calls `exit 2` if there is no 4.7 binary, which ends that Bash
call with its own explanation. Do not go looking for Godot by hand; if it fails,
show the user what it printed. It needs **4.7.2** and refuses older ones for a
reason it explains itself.

Then check the game is not already running:

```bash
tasklist 2>/dev/null | grep -i "BOG.exe" || echo "(BOG not running)"
```

**If BOG.exe is running, stop and say so.** Windows holds an open `.exe` locked,
so the export fails partway and leaves a truncated build. It matters for step 4
too: the game rewrites `settings.cfg` when it quits, so anything written to that
file while it is open is lost. Ask the user to close the game first.

## 2. Decide whether the build is stale

```bash
EXE="build/windows/BOG.exe"
if [ ! -f "$EXE" ]; then
    echo "STALE: no build at all"
else
    find scripts scenes resources art audio addons assets \
         project.godot export_presets.cfg -type f -newer "$EXE" \
         -not -path 'assets/source/*' \
         -not -path 'assets/Stylized_Nature_MegaKitStandard/FBX*' \
         -not -path 'assets/Stylized_Nature_MegaKitStandard/OBJ/*' \
         -not -path 'assets/Stylized_Nature_MegaKitStandard/Textures/*' \
         2>/dev/null | head -20
fi
```

Anything printed means stale. The excluded paths are the raw art that
`export_presets.cfg` already leaves out of the build, so touching them cannot
change the `.exe` — everything else can. When in doubt, **rebuild**: skipping a
needed build ships yesterday's game to five people and is discovered mid-match,
while an unnecessary build costs a few minutes and nothing else.

Show the user the first few changed files. It is the answer to "what will be
different this time", and they usually know it when they see it.

## 3. Build

Import first, then export. Both are slow — **run them in the background and
expect several minutes.** A fresh import after a big art change is the long
pole, and it will run past a default timeout, so use `run_in_background` rather
than letting it be killed and retried.

```bash
ROOT="$(pwd)"; GODOT_TAG=host . tools/find_godot.sh
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --export-release "Windows Desktop" "$GODOT_ROOT/build/windows/BOG.exe"
```

For macOS, the same shape with the other preset:

```bash
"$GODOT" --headless --path . --export-release "macOS" "$GODOT_ROOT/build/macos/BOG.app"
```

`$GODOT_ROOT` comes from `find_godot.sh` and is the project path in the form the
binary can read — it matters under WSL, where a Windows Godot cannot open a
`/mnt/c` path. **The output path must be absolute**: a relative one resolves
against the project rather than the shell, which is a quiet way to lose a build.

### Check it actually built

A zero exit code is not enough on its own — Godot prints errors and carries on.
All three of these:

* the exit code was 0,
* the `.exe` mtime advanced,
* the log has no `ERROR:` or `SCRIPT ERROR` lines, and ends in `[ DONE ] savepack`.

```bash
ls -la build/windows/BOG.exe
```

On size: it is **~295 MB** as of the two-map build, most of it the Rust map's
textures. Do not treat a specific number as the test — compare against the
previous build and be suspicious of a sudden *drop*, which is what a half-written
export looks like. Growth usually just means new art landed.

`No export template found at the expected path` means the 4.7.2 export templates
are not installed. That is a one-time ~1 GB download, and the README's *Building
a release* section has the commands; it is the only thing that normally stands
between these commands and a binary.

The `.exe` is self-contained — `binary_format/embed_pck=true`, so there is no
`.pck` beside it to remember. One file is the whole game.

## 4. The tunnel

```bash
PLAYIT="/c/Program Files/playit_gg/bin/playit.exe"
"$PLAYIT" status
```

Read the `Phase:` line.

* **`running`** — nothing to do.
* **stopped, or the command errors** — `"$PLAYIT" start`, then `status` again.
* **`playit.exe` is not there at all** — it is not installed. Send the user to
  step 1 of `docs/PLAYING.md`: a playit.gg account, the agent, and a tunnel that
  is **UDP**, local port **27015**, local address `127.0.0.1`. Do not try to
  create the tunnel from here — it is a dashboard job and takes two minutes.

Then the address the game hands out:

```bash
grep public_address "$APPDATA/Godot/app_userdata/BOG/settings.cfg"
```

* **Set** — good, carry on. It is remembered between runs, so this is normally a
  one-time job.
* **Blank or missing** — the game would hand out a LAN or tailnet address and
  nobody outside the house could join. The user sets it in **Settings → Network
  → Public address**, as the whole `host:port` from the playit dashboard. If they
  would rather paste it here, write it into that file directly with the game
  **closed** — it is a plain `ConfigFile` and the game reads it at startup.

### What this cannot check

The playit CLI has no way to list tunnels, so nothing here can confirm the tunnel
is UDP rather than TCP, or that it points at 27015. If a code reaches playit and
fails anyway, those two settings plus "is the agent running" are nearly always
the cause — `docs/PLAYING.md`, *If something goes wrong*, is written for exactly
that moment.

## 5. The invite code, before anyone launches anything

```bash
ROOT="$(pwd)"; GODOT_TAG=host . tools/find_godot.sh
"$GODOT" --headless --path . tools/invite_preview.tscn 2>&1 | grep invite_preview
```

Prints `ip=`, `port=` and `code=`. An invite code is a pure encoding of the
host's endpoint, so for a fixed tunnel it is the **same code every time** — it
can be read out before the game is even open. The tool calls the shipped
`Net.parse_public_address` and `InviteCode.encode`, so it cannot disagree with
what the lobby prints.

Note it is a **scene**, not a `--script` tool, and must be run as one. Autoloads
only exist when Godot runs a scene, and `net.gd` refers to `Settings` at compile
time — under `--script` it fails to compile and the error blames
`parse_public_address` rather than the missing autoload.

It exits 1 with a `problem=` line worded the way the lobby words it — no address
set, not `host:port`, or the hostname did not resolve. A failure here is the same
failure the user would have hit three minutes later with four people waiting,
which is the point of checking now.

**One caveat worth passing on:** the code carries the tunnel's *IP*, not its
name, and playit's A record can move. If a code that used to work stops, rerun
this and compare `ip=`. That is the whole of "codes go stale".

## 6. Report back

Give the user, in this shape:

* **The path**, in Windows form — `C:\Users\...\build\windows\BOG.exe` — with its
  size, and whether it was rebuilt just now or reused.
* **The invite code.**
* **A blurb they can paste into chat**, something like:

  > BOG — download, run it (Windows will warn: *More info → Run anyway*), click
  > **Join with a code**, paste `XXXXX-XXXXX`. Nothing to install. WASD to move,
  > left click throws.

* **Anything still not right**, said plainly — a tunnel that is down, a blank
  public address, a build that errored. A half-ready setup discovered by five
  people at once is worse than being told now.

Offer, do not assume: opening the build folder is
`explorer.exe /select,"C:\...\BOG.exe"`, and it is a reasonable thing to offer
when the user is about to go and share the file. Only run it if they say yes.
