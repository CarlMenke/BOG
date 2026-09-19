#!/usr/bin/env python3
"""Render the review queue page from a JSON description of the queue.

    python tools/review_queue.py out/review-queue.json out/review-queue.html

The template is `.claude/skills/review/queue.html`; the one token it carries,
`__QUEUE_JSON__`, is replaced with the JSON verbatim. The page is standalone —
no network, no build step — so the output can live in gitignored `out/` and be
opened straight off disk.

Reads and writes bytes as UTF-8 with LF endings on purpose: Python's text mode
on this machine means cp1252 and CRLF, which mangles the page's typography.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / ".claude" / "skills" / "review" / "queue.html"
TOKEN = "__QUEUE_JSON__"


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2

    data = json.loads(Path(argv[1]).read_bytes().decode("utf-8"))
    template = TEMPLATE.read_bytes().decode("utf-8")
    if TOKEN not in template:
        print(f"review_queue: {TEMPLATE} has no {TOKEN}")
        return 1

    page = template.replace(TOKEN, json.dumps(data, ensure_ascii=False, indent=2))
    out = Path(argv[2])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(page.encode("utf-8"))

    n = sum(len(g["tickets"]) for g in data["groups"])
    print(f"review_queue: {n} tickets in {len(data['groups'])} groups -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
