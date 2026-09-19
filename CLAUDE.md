# BOG

A match-based third-person multiplayer game in Godot 4.7.2, GDScript. Where the
code is up to and how to run and verify it: `docs/STATUS.md`. Why things are the
way they are: `docs/DECISIONS.md` (the D-records). How it fits together:
`docs/ARCHITECTURE.md`.

## Development goes through Linear, and Linear is Claude's to run

Linear (workspace BOG, team BOG, reached through the `linear` MCP server in
`.mcp.json`) is the only list of what to do next. Claude maintains it; humans
do not have to. The full rules are the Linear team document **"How BOG uses
Linear"**. The short form:

- **Build from Todo.** Before building anything that is not a quick experiment,
  find its ticket or write one. Take Todo tickets highest priority first. Move
  it to In Progress; when it is on `main` with the gate green, to In Review with
  the commit and D-record in a comment; to Done when a person has confirmed it
  in play, or there was nothing to confirm.
- **Quick changes stay quick.** Trying something, looking at it, keeping or
  throwing it away needs no ticket. Over an hour, more than a couple of files,
  or something someone will later ask "why" about: ticket first.
- **Ideas are weighed, not built.** Carl thinks out loud. Take it in, weigh it
  against what is already in Linear and in the D-records, and place it. Always
  tell a want from a brainstorm: a hedged or flagged idea is a Backlog ticket
  with the **Brainstorm** label and an `Open:` line, never something to build. Bulk
  feedback (a message, a transcript, a memo) goes through the `triage` skill,
  which writes tickets and reports back without starting work.
- **Keep it small.** One ticket per outcome. Later notes and related feedback
  are comments on that ticket, not new tickets. No new labels, statuses,
  projects or fields without a reason written into the team document.
- **In Review is Carl's test queue.** A ticket lands there when its change is
  on `main` with the gate green. Say what is in the queue at the start of every
  session and after any push that adds to it — one line per ticket, which
  build has it — so nothing waits unseen. Carl tests and gives verdicts; the
  `review` skill records them: confirmed → Done with a dated comment, not
  there yet → his words as a comment and the ticket back to Todo, something
  else → a new ticket. Nothing goes to Done on Claude's say-so while a person
  could confirm it.
- **`docs/PLAN.md` is frozen.** It is the build log up to 2026-09-18. New work
  is not added to it; its open items were moved to Linear on that date.

## Ask for real assets; do not improvise shapes

Anything a player looks at, walks past, holds or shoots is a real asset: a
modelled, textured mesh, a motion-captured clip. Primitives assembled in code
are for tools, checks and stand-ins that will be replaced, never for the
finished thing (D-135). This holds for every session working anywhere in this
repo.

- **Recognise it early and say so.** When a ticket needs a mesh, a clip, a
  texture or a sound that is not in the repo, the first message about it says
  what is needed and where it comes from: a Tripo model from a prompt Claude
  writes, a Mixamo clip named by its search term, a download Carl fetches, an
  asset pack. Getting the asset is part of the plan, not a fallback after the
  primitive version disappoints.
- **Ask, do not substitute.** If the asset has to come from Carl, the ticket
  gets **Needs a human** and an `Open:` line naming exactly what to fetch (the
  Tripo prompt, the Mixamo clip name, the file to download), and the build
  waits for it. A cone over five boxes because nobody asked for a campfire is
  the failure this rule exists to stop.
- **The route in.** Meshes: `assets/source/props/` through
  `tools/decimate_assets.py`. Clips: `assets/source/anims/` as skinless FBX
  through the Godot-native import (D-095..D-101). Skins and garments:
  `docs/SKIN_PIPELINE.md`. Every route is a D-record; follow it.
- **Quality is the reason.** Carl, 2026-09-19: "You making random shapes and
  random things in godot is not the best approach. You know the best approach
  to make the best outcome, and you should go with that even if it means
  getting a mesh from the user or if it means downloading a mesh... you
  recognizing when we need that is crucial to make this grow with quality."

## Commit and push to main, often

Small, frequent pushes to `main` are the rule here. Carl's worry is code going
stale on one machine, not merge conflicts; those are cheap when the pieces are
small and pulled often.

- Commit each coherent piece as soon as it is in a state worth keeping, and
  push it. Do not save up a round for one big commit.
- `git pull --rebase` before starting and before each push. Resolve conflicts
  on the spot; a conflict found early is a five-minute job.
- Standing permission: no need to ask before committing or pushing to `main`.
  Feature branches are for the rare change that would break `main` for hours,
  not the default.
- The last push of a batch carries a `[FINAL]` prefix in its subject.
