---
name: triage
description: Turn a dump of feedback, ideas or playtest notes into Linear tickets for BOG. Reads the whole dump, merges it with what is already tracked, writes ready or parked tickets, sets area and priority, and reports the table back. Never starts building. Use when Carl pastes notes, points at a transcript or memo, or says "here's my feedback" / "triage this" / "thoughts from playing".
---

# Triage a feedback dump

The rules this follows are the Linear team document "How BOG uses Linear".
The output is tickets and a short report. **No code changes.**

## 1. Get the whole dump

- Pasted text: that is the dump.
- A file: read all of it. Past dumps live in `feedback/`.
- An audio memo (`memos/*.mp3`): it needs a transcript first. If no
  transcriber is on this machine, say so and ask for the transcript. Do not
  guess at what a memo says.

Read every line before writing anything. Then list each distinct want in a
sentence. One want can hide three; three sentences can be one want.

## 2. Load what already exists

- Every open ticket: `list_issues` for team BOG, all states, with labels and
  status. Read Backlog bodies; their `Open:` lines say what they are waiting
  on, and a dump often answers one.
- Standing decisions: the tail of `docs/DECISIONS.md` and any `docs/PLAN_*.md`
  the dump touches. Feedback that undoes a decision is a conflict to report,
  not a ticket to write quietly.

## 3. Place each want

- **Same outcome as an existing ticket:** add a comment on it quoting the
  feedback with the date and who said it. If it answers an `Open:` line,
  patch the body and move it to Todo.
- **Conflicts** with a D-record or another ticket: hold it for the report.
- **New:** write the ticket.
  - Title states the outcome, not the complaint.
  - Body, three short parts: *What*, *Done when* (observable: a gate line, a
    render, a thing a player sees), *Source* (who, date, file if any).
  - One Area label, one type label (Bug / Feature / Improvement). Add
    **Needs a human** when a person must act first.
  - Priority: Urgent blocks playing; High is next round; Medium is worth a
    round; Low is when convenient.
  - **Todo** if all of the above is there. Otherwise **Backlog** with an
    `Open:` line naming what is missing.
- Relate tickets that will land together with `relatedTo`. Make a project
  only when a round is big enough to want a `docs/PLAN_*.md`, and name it
  after the round.

## 4. Keep the dump

If the dump was pasted, save it as `feedback/YYYY-MM-DD-<slug>.md` so ticket
sources have something to point at. Audio stays where it is.

## 5. Report and stop

Give back, in this order, then end the turn:

1. A table: ticket id, title, state, priority, area.
2. What was merged into existing tickets, one line each.
3. Conflicts and open questions, each with the decision it needs from Carl.

Building starts from Todo in a later turn, not from this one.
