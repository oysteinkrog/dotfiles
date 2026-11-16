#!/usr/bin/env python3
"""Stop hook: notice when a session only waits, and start a loop-speed intervention.

A session in a goal loop can spend hours answering "still waiting for X" while a faster way
to get its answer exists (load-speed round, 2026-11-16: about 60 such turns before Oystein
stepped in). This hook reads the transcript tail. When IDLE_NEED assistant replies in a
row are short waiting replies (a streak kept in a per-session state file), it blocks the stop once, with a reason
that tells Claude to run the loop-speed-intervention skill. It fires at most once per
COOLDOWN_S per session, so it cannot trap a session that really has nothing to do.

Input: the Stop hook JSON on stdin (transcript_path, session_id).
Output: nothing (allow the stop) or {"decision": "block", "reason": ...}.
Never fails the stop: any error means allow.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from pathlib import Path

IDLE_NEED = 5
MAX_IDLE_CHARS = 400
COOLDOWN_S = 6 * 3600
TAIL_BYTES = 400_000
STATE_DIR = Path(
    os.environ.get("SLOW_LOOP_STATE_DIR", Path.home() / ".local/state/slow-loop")
)

IDLE_RE = re.compile(
    r"\b(waiting (for|on)|still waiting|nothing (new|else|has finished)|"
    r"no new (results?|work)|nothing to act on|until .{0,40} (starts?|ends?|finish(es)?))\b",
    re.IGNORECASE,
)

REASON = (
    "slow-loop-detect: your last {idle} replies in a row only report waiting on something "
    "external. Before you stop again, load the loop-speed-intervention skill and run it: "
    "measure this loop (time per verdict, runs lost, no-gain share, idle resource hours), "
    "then act on the cheapest lever (a seconds-long counting test, a headless run, asking the "
    "owner for an idle resource, moving a booked run earlier). If after that you still have "
    "nothing to do, say so in one line and stop. This reminder fires at most once per 6 hours."
)


def assistant_texts(transcript: Path) -> list[str]:
    """Return the text of each assistant reply in the transcript tail, oldest first."""
    size = transcript.stat().st_size
    with transcript.open("rb") as fh:
        fh.seek(max(0, size - TAIL_BYTES))
        raw = fh.read().decode("utf-8", errors="replace")
    texts: list[str] = []
    for line in raw.splitlines():
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if entry.get("type") != "assistant":
            continue
        content = (entry.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        parts = [
            c.get("text", "")
            for c in content
            if isinstance(c, dict) and c.get("type") == "text"
        ]
        text = "\n".join(p for p in parts if p.strip())
        if text.strip():
            texts.append(text.strip())
    return texts


def is_idle(text: str) -> bool:
    return len(text) <= MAX_IDLE_CHARS and bool(IDLE_RE.search(text))


def decide(last_text: str | None, session_id: str, now: float) -> str | None:
    """Update the session's idle streak with its last reply; return a reason when it fires.

    The transcript can be hundreds of MB, so the hook only reads its tail for the last
    reply and keeps the streak in a small state file per session.
    """
    if last_text is None:
        return None
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    path = STATE_DIR / f"{re.sub(r'[^A-Za-z0-9_-]', '_', session_id)}.json"
    try:
        state = json.loads(path.read_text())
    except (OSError, ValueError):
        state = {}
    streak = int(state.get("streak", 0)) + 1 if is_idle(last_text) else 0
    last_fire = float(state.get("last_fire", 0))
    fire = streak >= IDLE_NEED and now - last_fire >= COOLDOWN_S
    if fire:
        last_fire, streak = now, 0
    path.write_text(json.dumps({"streak": streak, "last_fire": last_fire}))
    return REASON.format(idle=IDLE_NEED) if fire else None


def main() -> int:
    try:
        data = json.load(sys.stdin)
        transcript = Path(data.get("transcript_path") or "")
        if not transcript.is_file():
            return 0
        texts = assistant_texts(transcript)
        reason = decide(
            texts[-1] if texts else None,
            str(data.get("session_id") or "unknown"),
            time.time(),
        )
        if reason:
            print(json.dumps({"decision": "block", "reason": reason}))
    except Exception:  # noqa: BLE001 - a hook must never break the stop
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
