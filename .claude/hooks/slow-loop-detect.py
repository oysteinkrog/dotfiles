#!/usr/bin/env python3
"""Stop hook: notice when a session only waits, and start a loop-speed intervention.

A session in a goal loop can spend hours answering "still waiting for X" while a faster way
to get its answer exists (load-speed round, 2026-11-16: about 60 such turns before Oystein
stepped in). When IDLE_NEED replies in a row are short waiting replies (a streak kept in a
per-session state file), it blocks the stop once, with a reason that tells the agent to run the
loop-speed-intervention skill. It fires at most once per COOLDOWN_S per session, so it cannot
trap a session that really has nothing to do.

Works for Claude Code and Codex: both send a Stop event with `last_assistant_message` and
accept {"decision": "block", "reason": ...}. When that field is missing, the hook reads the
last reply from the Claude transcript tail.

It counts every stop, including stops a goal loop or another Stop hook continued
(`stop_hook_active`), because that is exactly the loop it is meant to catch. The cooldown, not
the flag, keeps it from trapping a session: after a fire the streak restarts at 0.

Two hook entries can see the same stop (a user hook and a repository hook). A stop is
identified by the transcript path and its size, which do not change while the Stop hooks run;
the second entry sees the same identity and does not count the stop again. Without a
transcript it falls back to the same reply within DUP_WINDOW_S.

Input: the Stop hook JSON on stdin (last_assistant_message or transcript_path, session_id).
Output: nothing (allow the stop) or {"decision": "block", "reason": ...}.
Never fails the stop: any error means allow.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path

try:
    import fcntl
except ImportError:  # native Windows Python: run without the lock
    fcntl = None

IDLE_NEED = 5
MAX_IDLE_CHARS = 400
COOLDOWN_S = 6 * 3600
DUP_WINDOW_S = 10
LOCK_WAIT_S = 2.0
STALE_S = 7 * 86400
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
    "nothing to do, say so in one line and stop. This reminder fires at most once per "
    "{hours} hours."
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


# A reply that reports finished work is progress, even if it also says it waits for CI.
WORK_RE = re.compile(
    r"\b(fixed|pushed|committed|merged|added|wrote|built|opened|landed|"
    r"rebased|ran|re-ran|implemented|removed|updated)\b",
    re.IGNORECASE,
)


def is_idle(text: str) -> bool:
    return (
        len(text) <= MAX_IDLE_CHARS
        and bool(IDLE_RE.search(text))
        and not WORK_RE.search(text)
    )


def prune(now: float) -> None:
    """Delete state and lock files of sessions idle for more than STALE_S, once a day."""
    marker = STATE_DIR / ".pruned"
    try:
        if now - marker.stat().st_mtime < 86400:
            return
    except OSError:
        pass
    marker.touch()
    for f in STATE_DIR.glob("*"):
        if f == marker:
            continue
        try:
            if now - f.stat().st_mtime > STALE_S:
                f.unlink()
        except OSError:
            pass


def decide(
    last_text: str | None, session_id: str, now: float, stop_key: str | None = None
) -> str | None:
    """Update the session's idle streak with its last reply; return a reason when it fires.

    The transcript can be hundreds of MB, so the hook only reads its tail for the last
    reply and keeps the streak in a small state file per session. stop_key identifies
    this stop, so a second hook entry on the same stop does not count it twice.
    """
    if last_text is None:
        return None
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    path = STATE_DIR / f"{re.sub(r'[^A-Za-z0-9_-]', '_', session_id)}.json"
    if fcntl is None:
        return _decide_locked(last_text, path, now, stop_key)
    # A user hook and a repository hook can run this at the same moment: hold a lock
    # across read and write, and replace the file atomically. Never wait long for it.
    with open(path.with_suffix(".lock"), "w") as lock:
        deadline = time.monotonic() + LOCK_WAIT_S
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() > deadline:
                    return None
                time.sleep(0.05)
        return _decide_locked(last_text, path, now, stop_key)


def _decide_locked(
    last_text: str, path: Path, now: float, stop_key: str | None
) -> str | None:
    try:
        state = json.loads(path.read_text())
    except (OSError, ValueError):
        state = {}
    digest = hashlib.sha256(last_text.encode()).hexdigest()[:16]
    if stop_key is not None:
        if state.get("last_stop") == stop_key:
            return None
    elif (
        state.get("last_hash") == digest
        and now - float(state.get("last_seen", 0)) < DUP_WINDOW_S
    ):
        return None
    streak = int(state.get("streak", 0)) + 1 if is_idle(last_text) else 0
    last_fire = float(state.get("last_fire", 0))
    fire = streak >= IDLE_NEED and now - last_fire >= COOLDOWN_S
    if fire:
        last_fire, streak = now, 0
    tmp = path.with_suffix(".tmp")
    tmp.write_text(
        json.dumps(
            {
                "streak": streak,
                "last_fire": last_fire,
                "last_hash": digest,
                "last_seen": now,
                "last_stop": stop_key,
            }
        )
    )
    tmp.replace(path)
    return REASON.format(idle=IDLE_NEED, hours=COOLDOWN_S // 3600) if fire else None


def main() -> int:
    try:
        data = json.load(sys.stdin)
        session_id = data.get("session_id")
        if not session_id:
            return 0
        transcript = Path(data.get("transcript_path") or "")
        has_transcript = bool(data.get("transcript_path")) and transcript.is_file()
        stop_key = (
            f"{transcript}:{transcript.stat().st_size}" if has_transcript else None
        )
        last = (data.get("last_assistant_message") or "").strip() or None
        if last is None:
            if not has_transcript:
                return 0
            texts = assistant_texts(transcript)
            last = texts[-1] if texts else None
        now = time.time()
        reason = decide(last, str(session_id), now, stop_key)
        prune(now)
        if reason:
            print(json.dumps({"decision": "block", "reason": reason}))
    except Exception:  # noqa: BLE001 - a hook must never break the stop
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
