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
  against what is already in Linear and in the D-records, and place it. Bulk
  feedback (a message, a transcript, a memo) goes through the `triage` skill,
  which writes tickets and reports back without starting work.
- **Keep it small.** One ticket per outcome. Later notes and related feedback
  are comments on that ticket, not new tickets. No new labels, statuses,
  projects or fields without a reason written into the team document.
- **`docs/PLAN.md` is frozen.** It is the build log up to 2026-09-18. New work
  is not added to it; its open items were moved to Linear on that date.
