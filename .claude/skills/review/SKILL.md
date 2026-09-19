---
name: review
description: Walk Carl through the BOG tickets waiting for him to test. Lists every ticket In Review (on main, gate green), says what to look at and which build has it, then records his verdict per ticket - confirmed goes to Done, feedback becomes a dated comment in his words and the ticket goes back to Todo. Never starts building. Use when Carl says "what's ready to test", "let me test", "I played it, here's what I saw", "is that done", or whenever In Review tickets exist at the start of a session.
---

# The review queue

The rules this follows are the Linear team document "How BOG uses Linear",
section "The review queue". **In Review is the list of what Carl tests next.**
The output is ticket state changes and a short report. **No code changes.**

## 0. Announce it unasked

At the start of every session, and right after any push that moves a ticket
into In Review, say what is in the queue — one line per ticket: id, title,
which build has it. Do not repeat the list within a session unless it changed.
A queue nobody is told about is a queue nobody tests.

## 1. List the queue

- `list_issues` for team BOG, state `In Review`, with description and comments'
  worth of context (`get_issue` for the *Done when* line and the commit
  comment). Highest priority first.
- For each ticket work out **which build has it**: the commit in its comment
  against `build/windows/BOG.exe`'s mtime — `git log -1 --format=%ct <sha>`
  versus the exe's timestamp. Say "in the exe from HH:MM" or "the exe is older
  than this — `/host` rebuilds it". Carl tests builds, not branches.
- Print a table: id, title, what to look at (the *Done when* line, shortened),
  build. If Carl has not tested yet, stop here.

## 2. Take the verdicts

Carl answers per ticket or in bulk, in whatever words. Match each verdict to
its ticket and record it:

- **Confirmed** ("done", "works", "good", "yep") → state **Done**, comment
  `Confirmed in play by Carl, YYYY-MM-DD.` plus his words if he said more.
- **Not there yet, same outcome** → comment with his words **verbatim**, dated.
  If the *Done when* line no longer says what done means, `patch` it. State
  back to **Todo** — building starts from there in a later turn, never from
  this one. Raise the priority to High if he is waiting on it.
- **Something else entirely** mixed into the feedback → that is a new ticket
  by the feedback-dump rules (or `/triage` if the dump is big). The reviewed
  ticket keeps its own verdict; one ticket per outcome.
- **Not looked at** → stays In Review; say so in the report.

A ticket never goes to Done on Claude's say-so while a person could confirm
it. "There was nothing to confirm" — a tool, a doc, a gate line — is the only
exception, and the comment says that.

## 3. Report and stop

Give back, then end the turn:

1. A table: ticket id, verdict, new state.
2. What still waits in the queue, one line each.
3. New tickets written from stray feedback, if any.

Building the Todo tickets is the next turn's job, highest priority first.
