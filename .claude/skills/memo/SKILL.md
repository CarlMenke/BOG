---
name: memo
description: Turn a voice memo in memos/ into Linear tickets for BOG. Transcribes the audio locally (tools/transcribe.py), untangles the transcript into a dated feedback file with each want quoted and timestamped, then hands that file to the triage skill and asks Carl the few questions that change a ticket. Never starts building. Use when Carl says "there's a new memo", "I recorded something", "/memo", drops an mp3 in memos/, or when a memo sits in memos/ with no feedback file naming it.
---

# A memo becomes tickets

The rules this follows are the Linear team document "How BOG uses Linear".
The output is a raw transcript next to the memo, a feedback file, tickets, and
a short report. **No code changes.** The Linear half is the `triage` skill;
this skill only gets a memo into a shape triage can read.

## 0. Find what is new

`/memo` with no argument means every memo in `memos/` not yet run; with a
path, just that one.

A memo has been **run** when a file in `feedback/` names it on its `Source:`
line: `grep -l "<memo basename>" feedback/*.md`. Never run one twice. A memo
with a `.raw.txt` but no feedback file was transcribed and then interrupted:
pick it up at step 2.

Memos are recordings Carl or a friend made on a phone, or a whole play session
captured with the mic open. Three habits of theirs to read for:
- **"I'm talking to the recording."** A line addressed to the memo itself is
  the highest-signal line in the file; it is a want said on purpose.
- **"We're just brainstorming."** A want flagged that way, or hedged in the
  next breath ("I don't know, I guess..."), is a lean, not a decision: Backlog
  with the **Brainstorm** label and an `Open:` line, and say so in the
  feedback file. Always draw this line; Carl asked for it on 2026-09-19.
- **Two voices, no labels.** Whisper does not say who spoke. Attribute from
  context (who set up Linear, who made the exe, who is remaking which map)
  and mark the attribution where it changes what a want means. Sizes vary from two minutes to three hours; the
first one, `2026-09-18 21-02-05.mp3`, was 3h22m of two people playing. Both
shapes go through the same steps.

## 1. Transcribe

```
python tools/transcribe.py            # every memo without a .raw.txt
python tools/transcribe.py memos/x.mp3
```

Writes `memos/<name>.raw.txt`: header lines, then `[h:mm:ss] text` per
segment. Runs on the GPU when the CUDA DLLs load (about ten times realtime),
otherwise the CPU (slower than realtime, so say so and run it in the
background). Progress goes to stderr every ten minutes of audio. The install
is in `docs/STATUS.md` under "Voice memos".

If the script fails to import faster-whisper, install it per STATUS and retry;
do not guess at what a memo says and do not fall back to an API without asking.

## 2. Untangle into a feedback file

Read the whole `.raw.txt`. All of it: the wants in a play session are sparse
and come in the middle of gameplay chatter, and the last hour is where the
"honestly the biggest problem is" lines live.

Whisper has no speaker labels and mishears the game's words. Fix them from
this glossary before deciding what a line means:

| heard | means |
|---|---|
| sphere, spear, speer | spear (the throwable) |
| gub, gubs, gubbies | Bog (the old name; the character or the player) |
| magnet, shield, letters, B O G | the three pickups and the letter collect (D-077..D-081, D-129..) |
| the bag, pouch | the letter pouch on the Bog's back |
| range, dummies, glow worm | the practice range, Glowworm Grounds |
| last (one) standing, Alaska standing | the last-one-standing mode |
| twerk, emote, Y | the emote on Y |
| Claude, cloud | Claude (the pipeline, not the sky) |
| puffball, fairy ring, log chute, firefly jar | the movement proposals in docs/PLAN_MOVEMENT.md |

Then write `feedback/YYYY-MM-DD-memo-<slug>.md` (date is the memo's, slug is
what it was about), in this order:

1. A header: who was talking (ask Carl if the voices are not obvious from
   context), the memo filename on a `Source:` line, its duration, and one
   paragraph of what the session was: which map, mode, how many players, what
   they spent their time doing.
2. **Wants.** One numbered entry per distinct want, each with:
   - the want in one sentence, in the outcome's words, not the complaint's;
   - the timestamp(s) it came from and the line quoted **verbatim** from the
     raw transcript, mishearings and all, so Carl can check the audio;
   - what it already touches: a ticket id, a D-record, a `docs/PLAN_*.md`
     section, or a file. This is the grounding: triage decides from it whether
     the want is a comment on something tracked or a new ticket.
   A want said three times in three hours is one entry with three timestamps.
   A bug they hit and a fix they proposed for it are one entry.
3. **Not wants.** Things that sounded like feedback but were not: jokes,
   things already fixed since the recording (check the D-records after the
   memo's date), one-off confusion that resolved itself. A line each, so the
   next reader does not re-triage them.
4. **Cleaned transcript**, only when the memo is under about fifteen minutes:
   filler out, sentences repaired, glossary applied. For a long session the
   quotes in the wants list are the record and the raw file stays next to the
   audio.

Write the file as bytes, UTF-8, LF (the Windows text trap).

## 3. Triage it

Run the `triage` skill from its step 2 on the feedback file just written. Its
rules about merging into existing tickets, conflicts, Todo versus Backlog,
labels and priority apply unchanged. Do not restate them here.

## 4. Ask what changes a ticket, park the rest

Before writing tickets, collect the questions. Ask Carl at most three per
memo, with AskUserQuestion, and only ones whose answer changes what the ticket
says or whether it exists: two wants that contradict each other in the same
session, a want that undoes a D-record, a want that could mean two different
outcomes. Everything else goes to Backlog with an `Open:` line, the way
triage already does, and into the report.

## 5. Keep it, report, stop

Commit and push the feedback file (`memos/` is gitignored; the audio and the
raw transcript stay on this machine). Then give back, in this order, and end
the turn:

1. The triage table: ticket id, title, state, priority, area.
2. What was merged into existing tickets, one line each.
3. The not-wants that a reader might expect to see as tickets, one line each.
4. Conflicts and open questions still waiting on Carl.

Building starts from Todo in a later turn, not from this one.
