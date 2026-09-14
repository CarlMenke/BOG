# Playing GUB

You are a Gub. You throw spears at other Gubs. Last team standing wins.

## If you are not hosting — that is it, you are done

**Get the game.** Download `GUB.exe` and put it anywhere. It is one file — there
is nothing to install, no account, and nothing else to set up. Windows will warn
you it is from an unknown publisher: *More info → Run anyway*.

**Join.** Join with a code → paste in the code the host reads out
(`XXXXX-XXXXX`). Case and dashes do not matter.

That is the whole thing. Everything below is for whoever is hosting.

---

## Hosting — once, about ten minutes

One person hosts, and that person also plays, so nobody sits out. The setup is
theirs alone.

**1. Make a tunnel.** Go to [playit.gg](https://playit.gg), make an account, and
install the playit agent. Create a tunnel and set it up like this:

| | |
|---|---|
| Tunnel type | **UDP** (not TCP — the game does not use TCP at all) |
| Local port | **27015** |
| Local address | `127.0.0.1` |

playit gives back a public address that looks like
`angry-gub.at.ply.gg:41235`. The number on the end is *not* 27015 and is not
supposed to be — playit picks the outside port and forwards it to 27015 on your
machine. Leave the agent running whenever you host.

**2. Tell the game about it.** Open GUB → Settings → **Network** → paste the
whole thing, hostname and port, into **Public address**. It is remembered, so
this is a one-time job unless you make a new tunnel.

**3. Host.** Host a Game, then read out the invite code. The caption above it
should say **INTERNET (PLAYIT)**. If it does, the code will work for anyone,
anywhere, with nothing installed on their end.

Working on the game rather than just playing it? In Claude Code, **`/host`**
does all three of these — it checks the agent is up, builds a fresh `GUB.exe`
only if the current one is stale, and prints the code before you open the lobby,
since for a fixed tunnel it is the same code every time.

### The alternative: Tailscale

If you cannot or would rather not run playit, everyone — not just you — can
install [Tailscale](https://tailscale.com/download), sign in, and join one
tailnet. Leave **Public address** blank and the game hands out your tailnet
address instead; the caption says **TAILNET**. It works, and it has always
worked, but it is five people's setup instead of one person's, and the free plan
covers six people, so a full eight-player lobby needs a paid seat or a spare
account.

Blank also covers the simplest case of all: everyone in the same building on the
same Wi-Fi needs nothing at all. The caption says **LAN**.

---

## Controls

| | | | |
|---|---|---|---|
| Move | `W` `A` `S` `D` | Throw spear | Left click |
| Jump | `Space` | Aim | Right click |
| Dive | `Space` again in the air | Place shield mushroom | `Q` |
| Sprint | `Shift` | Throw lure | `E` |
| Crouch | `Ctrl` or `C` | Interact | `F` |
| Scoreboard | `Tab` (hold) | Respawn | `R` |
| Chat | `T` | | |
| Pause / settings | `Esc` | | |

**The host picks the map** in the lobby's Match panel — Whisperbloom Hollow, the
enchanted island, or Rust, an industrial yard in daylight — and everyone in the
lobby plays whichever one they chose.

Two of those are worth a sentence. **Double-tap `Space`** — jump, then jump
again while you are still in the air — is a dive: a long committed leap that you
only get once per jump and cannot take back. And the **spear does not leave on
the click**: the Gub winds up first and throws about three quarters of a second
later, aimed where you are pointing *then*, so a moving target has to be led.

Hold right click and a ring appears on the ground where your spear would
actually land. Spears drop, and that ring is the only honest answer to how much.

**Nothing counts your spear down.** Whether you can throw is answered by your
Gub's own hand — a shaft in it means yes, an empty fist means no — and the Spear
tile at the bottom of the screen says the same thing, lit or dark. That is on
purpose: the throw has a wind-up, and every version of a reload timer drawn
around the crosshair was wrong about one half of it. The other two tiles show
how many mushrooms and lures you are carrying, and go dark at zero, which is
what every life starts on.

In a **Collect G·U·B** match, three lamps sit above those tiles. Walk over a
card and your Gub holds it up for ten seconds before the letter counts — you
cannot throw for any of them, the card lights you up for everyone in the
clearing, and if somebody kills you it drops where you fell for whoever reaches
it first. The lamp you are earning fills up, with the seconds left under it.

**Capture G·U·B** is capture the flag with the letters, always in teams. There are
only three cards, G, U and B, sitting between the two bases when the match
starts. Each team's base is a glowing ring in its colour with a column of light
over it. Walk over a card to carry it. You cannot throw while you carry, you move
a little slower, and everybody sees a gold card over your head through walls.
Walk into **your own** ring and the letter is your team's, and the card goes
back to the middle for the other team to fight over. You cannot pick up a letter
your team already has. If you die carrying, the card drops where you fell and
anyone can grab it, your team or theirs. If nobody does, it goes back to the
middle after fifteen seconds (the host can change that). The first team to bank
G, U and B wins.

**The Elder.** About one death in fifty leaves a purple robe and a wizard hat on
the ground, in every mode. Walk over it and for **twenty seconds you cannot be
killed.**

Nothing anybody throws at you will do it. A spear that hits you stops dead in a
violet flash and you keep walking. You move about a third faster, you jump half
again as high, and you have **no spear at all** — what you have instead is
lightning, on the same button, and it comes out of your hand about a fifth of a
second after you click. It kills whatever it touches and throws the body, it
reaches about thirty metres, and it is back in about a second. A shield mushroom
still stops it, so cover still works.

Everybody can see the robe, which is the point: they know what is coming and you
know they know. The countdown above your ability bar is yours alone — it goes
amber for the last three seconds.

**Two things can still end you early.** Falling off the map counts, robe or no
robe — so a lure will still drag you over an edge, and that is the play against
an Elder. And whoever hit you last gets the kill if you go over within a few
seconds of it.

When the twenty seconds are up the robe burns off and you are an ordinary Gub
again, standing exactly where you were with your spear back, your letters still
yours and whatever you were carrying still in your pockets. Running out is not
dying. The robe itself is gone for good either way — it never drops for anybody
else — so the only way another one appears is for somebody to die.

The other thing to know, if you are on the other side of one: **you do not beat
an Elder, you outlast one.** Twenty seconds is long enough to be somewhere else.

---

## If something goes wrong

**The caption says LAN or TAILNET when you expected INTERNET (PLAYIT)** — the
host left **Public address** blank, or typed it into a copy of the game that was
already hosting. Settings takes effect when the lobby is opened, so change it,
leave the lobby, and host again.

**The caption says PUBLIC ADDRESS DID NOT RESOLVE** — the hostname could not be
looked up. Usually a typo, or the tunnel was deleted from the playit dashboard.
Check the address against the dashboard and reopen the lobby.

**The caption says PUBLIC ADDRESS IS NOT HOST:PORT** — the field needs both
halves, with a colon between them: `angry-gub.at.ply.gg:41235`. A hostname on
its own is not enough, because playit picks the port and it is never 27015.

**"Could not reach…" or "Timed out reaching the host"** — the code reached
playit and playit had nowhere to send it. Nearly always one of three things: the
playit agent is not running on the host's machine, the tunnel is TCP instead of
UDP, or its local port is not 27015. Check all three in the dashboard.

**The code used to work and now does not** — codes go stale. The address is
baked into the code, so if the host reopens their lobby, reads out a fresh code,
and everyone uses that one, most of this section stops applying.

**Nothing happens when you click** — the game takes the mouse when a match
starts. Press `Esc` to get the cursor back.

Up to eight can play.
