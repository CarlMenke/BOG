#!/usr/bin/env python3
"""What landed for a ticket — the commits on `main` that name it.

    python tools/ticket_commits.py BOG-43 BOG-61 ...
    python tools/ticket_commits.py --json BOG-43 ...     # for the review page

Every commit that closes a ticket is supposed to name it in the subject, the
way `(BOG-61, D-178)` does, so a review months later can find the change
without reading the whole log. This walks the log for each id and prints the
commits, newest first, with the files they touched.

An id with no commit is not an error and is printed as `NO COMMIT NAMED` —
some rounds landed as one merge that named none of its tickets. The sha is on
the Linear ticket's In Review comment in that case; record it on the ticket
while reviewing so it is never hunted for twice.
"""

import json
import re
import subprocess
import sys

FORMAT = "%H%x1f%h%x1f%ct%x1f%s"


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], capture_output=True, text=True, check=True
    ).stdout


def commits_for(ticket: str) -> list[dict]:
    # \b so BOG-5 does not match BOG-55; --all-match is not wanted, one grep.
    out = git("log", f"--format={FORMAT}", f"--grep=\\b{re.escape(ticket)}\\b", "-E")
    found = []
    for line in out.splitlines():
        if not line.strip():
            continue
        sha, short, when, subject = line.split("\x1f", 3)
        # The convention is the ticket in the *subject*. A match in the body
        # alone is a commit that merely mentioned it — a memo, a merge, a
        # STATUS sweep — and is reported as such rather than as the change.
        closes = re.search(rf"\b{re.escape(ticket)}\b", subject) is not None
        files = git("show", "--name-only", "--format=", sha).split() if closes else []
        found.append(
            {"sha": short, "full": sha, "when": int(when), "closes": closes,
             "subject": subject, "files": files}
        )
    found.sort(key=lambda r: (not r["closes"], -r["when"]))
    return found


def main(argv: list[str]) -> int:
    as_json = "--json" in argv
    tickets = [a for a in argv[1:] if a.startswith("BOG-")]
    if not tickets:
        print(__doc__)
        return 2

    found = {t: commits_for(t) for t in tickets}

    if as_json:
        print(json.dumps(found, indent=2))
        return 0

    for ticket in tickets:
        rows = found[ticket]
        if not rows:
            print(f"{ticket}: NO COMMIT NAMED — look for the sha on the ticket")
            continue
        if not any(r["closes"] for r in rows):
            print(f"{ticket}: NO COMMIT NAMES IT IN THE SUBJECT")
        for row in rows:
            if not row["closes"]:
                print(f"{ticket}: (mentioned in {row['sha']}  {row['subject']})")
                continue
            print(f"{ticket}: {row['sha']}  {row['subject']}")
            for path in row["files"][:12]:
                print(f"    {path}")
            if len(row["files"]) > 12:
                print(f"    ... and {len(row['files']) - 12} more")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
