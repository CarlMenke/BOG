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

- **`git pull --rebase` first.** The queue is usually ahead of the local
  checkout, and half the verdicts below are read off files that have not
  arrived yet.
- `list_issues` for team BOG, state `In Review`, with description and comments'
  worth of context (`get_issue` for the *Done when* line and the commit
  comment). Highest priority first.
- For each ticket work out **which build has it**: the commit in its comment
  against `build/windows/BOG.exe`'s mtime — `git log -1 --format=%ct <sha>`
  versus the exe's timestamp. Say "in the exe from HH:MM" or "the exe is older
  than this — `/host` rebuilds it". Carl tests builds, not branches.

### Which commit was this ticket

Everything In Review is already on `main`, so reviewing it means finding the
change again months later. `python tools/ticket_commits.py BOG-43 BOG-61 ...`
(add `--json` for the page) walks the log for each id and prints the commits
with the files they touched.

It works because a commit that closes a ticket **names it in the subject**, as
`(BOG-61, D-178)` does. Two rules keep it working:

- A match in the body alone is reported as "mentioned in" and is not the
  change — a memo commit or a STATUS sweep that happened to cite the id.
- `NO COMMIT NAMES IT IN THE SUBJECT` means a round landed as one merge that
  named none of its tickets (the letters round, `6b1ab6c`, is the example).
  The sha is on the ticket's In Review comment. **Put it on the card, and when
  writing the verdict comment, name the sha** — so it is never hunted twice.

## 2. Split it before handing any of it back

Carl is not responsible for every ticket. Sort the queue in two:

- **Claude's half** — every ticket whose *Done when* a machine can settle: a
  D-record or a STATUS line, a gate or `net_test` check, a skill, a config
  line, a tool that has already been run for real. Verify each one against the
  repo, close it, and say in the comment what was checked and where
  (`file:line`, the commit) and that there was nothing for a person to
  confirm. Where the verdict rests on a gate line, **run the gate** and quote
  its result — copy `tools/smoke_test.sh` to `tools/.gate_run_copy.sh` and run
  the copy, so the original can be edited mid-run; it resolves the repo from
  its own directory, so the copy has to live in `tools/`.
- **Carl's half** — anything that needs eyes, and anything where the *Done
  when* has a mechanical half and a feel half. Group these by **where he tests
  them**, not by priority: menu and lobby, the practice range, a letters match,
  a walk round the maps, with a friend, renders. One launch clears a group.

A ticket never goes to Done on Claude's say-so while a person could confirm
it. Half-verified is Carl's: say which half is proven and hand him the rest.
The exception is his to give — the page's **Too annoying — you check it**
button, in step 4.

## 3. Build the page

Carl reviews on a page, not in chat. Write the queue as JSON and render it:

```
python tools/review_queue.py <queue>.json out/review-queue.html
start out/review-queue.html
```

The template is `.claude/skills/review/queue.html` — a standalone page, no
network, no build step, `out/` is gitignored. The JSON is Carl's half only:

```json
{ "date": "YYYY-MM-DD",
  "build": "which exe has this, or that it needs a rebuild",
  "note": "one line — what Claude already closed, how to work the page",
  "groups": [ { "key": "A", "name": "Menu & lobby",
    "where": "how to test this group in one launch, and roughly how long",
    "tickets": [ { "id": "BOG-43", "pri": "High", "title": "...",
                   "look": "what to look at, in plain words",
                   "landed": [ { "sha": "aa842eb", "subject": "..." } ] } ] } ] }
```

`look` is the *Done when* line turned into an instruction — what to do and
what should happen — never the raw acceptance text. If a ticket carries a
comment that changes what Carl should decide (feedback from a playtest, a
known bug that will show while he looks), say so in `look`. `landed` comes
from `tools/ticket_commits.py --json`; fill any gap from the ticket's comment
rather than shipping a card that says no commit names it.

Each card gives him four answers — **Works / Not yet / Something else / Too
annoying — you check it** — and a notes box; verdicts persist in
`localStorage` per date, so he can close the page mid-round. **Copy for
Claude** puts the whole thing on the clipboard, grouped, with his notes
quoted and the untouched tickets listed.

## 4. Take the verdicts

Carl pastes the page's report, or answers per ticket or in bulk in whatever
words. Match each verdict to its ticket and record it:

- **Confirmed** ("done", "works", "good", "yep") → state **Done**, comment
  `Confirmed in play by Carl, YYYY-MM-DD.` plus his words if he said more.
- **Not there yet, same outcome** → comment with his words **verbatim**, dated.
  If the *Done when* line no longer says what done means, `patch` it. State
  back to **Todo** — building starts from there in a later turn, never from
  this one. Raise the priority to High if he is waiting on it.
- **Something else entirely** mixed into the feedback → that is a new ticket
  by the feedback-dump rules (or `/triage` if the dump is big). The reviewed
  ticket keeps its own verdict; one ticket per outcome.
- **Too annoying to test** → Carl does not care enough to launch for it and
  has given standing permission to settle it without him. Try hard: read the
  change (`tools/ticket_commits.py` gives the sha and the files), run the gate
  line or the preview scene that covers it, render a frame if a render would
  show it. Then either **Done**, with a comment saying it was verified by
  Claude at Carl's word, what was checked and how — never a bare "looks
  right" — or, if it cannot be settled that way, back to **Todo** with a
  comment saying what could not be proven and what would prove it. The one
  thing this option does not allow is leaving it In Review.
- **Not looked at** → stays In Review; say so in the report.

## 5. Report and stop

Give back, then end the turn:

1. A table: ticket id, verdict, new state.
2. What still waits in the queue, one line each.
3. New tickets written from stray feedback, if any.

Building the Todo tickets is the next turn's job, highest priority first.
