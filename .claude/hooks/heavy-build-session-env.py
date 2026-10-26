#!/usr/bin/env python3
"""SessionStart hook: tell heavy-build which Claude session runs a build.

heavy-build finds the submitting session from its parent processes, or from
CLAUDE_PID. A build started with `systemd-run --user` has neither: the unit's
parent is the user manager, and systemd-run gives the unit none of the
caller's environment. On 2026-10-26 every job queued that way showed
session=- (the jobs of two busy lanes among them).

This hook adds a block to $CLAUDE_ENV_FILE, which Claude Code runs before
each Bash command of the session:

    export HEAVY_BUILD_SESSION_PID=<pid of this Claude process>
    export HEAVY_BUILD_SESSION=<session name now>
    systemd-run() { command systemd-run -E HEAVY_BUILD_SESSION ... "$@"; }

Each line it cannot fill is an `unset` instead, so nothing inherited stays:
no pid when no Claude process is found, no name when the session has none or
its name has characters outside [A-Za-z0-9._@+-]. The block is always
written, so a stale one from an earlier start is replaced. The pid is stable
for the session's life; the name can change (a rename), so heavy-build looks
the pid up first and uses the name only when there is no pid. The systemd-run function passes the
three variables (and CLAUDE_PID) into the unit with -E, which works for both
services and scopes. It applies only to systemd-run typed in the Bash tool,
not to one inside a script.

It never prints to stdout (SessionStart output becomes model context), and
it never fails the session: any error ends it quietly with exit 0.
Test hooks: HB_SESSION_HOOK_PROC (for /proc), MACHINE_SESSION_SESSIONS_DIR.
"""

import json
import os
import re
import sys
from pathlib import Path

BEGIN = "# >>> heavy-build session (heavy-build-session-env.py)"
END = "# <<< heavy-build session"
# Session names written to the file. Anything else (a space, a quote, a
# newline that could fake the end marker) is left out, and heavy-build finds
# the session by its pid instead.
SAFE_NAME = re.compile(r"[A-Za-z0-9._@+-]{1,128}")
WRAPPER = (
    "systemd-run() { command systemd-run -E HEAVY_BUILD_SESSION -E HEAVY_BUILD_SESSION_PID"
    ' -E CLAUDE_PID "$@"; }'
)


def stat_rest(proc: Path, pid: int) -> list[str]:
    """Fields of /proc/PID/stat after the command name, or [] if gone."""
    try:
        s = (proc / str(pid) / "stat").read_text()
    except OSError:
        return []
    return s[s.rfind(")") + 2 :].split()


def session_file(sessions: Path, proc: Path, pid: int) -> dict | None:
    """The live session file of PID: it exists and its procStart matches."""
    try:
        d = json.loads((sessions / f"{pid}.json").read_text())
    except (OSError, ValueError):
        return None
    if not isinstance(d, dict):
        return None
    rest = stat_rest(proc, pid)
    if not rest:
        return None
    if d.get("procStart") and len(rest) > 19 and rest[19] != str(d["procStart"]):
        return None
    return d


def ancestors(proc: Path, start: int) -> list[int]:
    """START and its parent processes, nearest first."""
    out: list[int] = []
    p = start
    while p > 1 and p not in out and len(out) < 64:
        out.append(p)
        rest = stat_rest(proc, p)
        p = int(rest[1]) if len(rest) > 1 and rest[1].isdigit() else 0
    return out


def claude_pid(proc: Path, start: int) -> int | None:
    """The Claude process when no session file names it: a live CLAUDE_PID,
    else the nearest parent process whose name is claude."""
    cp = os.environ.get("CLAUDE_PID", "")
    if cp.isdigit() and stat_rest(proc, int(cp)):
        return int(cp)
    for pid in ancestors(proc, start):
        try:
            if (proc / str(pid) / "comm").read_text().strip() == "claude":
                return pid
        except OSError:
            continue
    return None


def find_session(
    sessions: Path, proc: Path, start: int, session_id: str | None
) -> tuple[int, dict] | None:
    """CLAUDE_PID first, then the parent processes of START. With a session
    id from the hook input, a file with another sessionId does not count."""
    cands: list[int] = []
    cp = os.environ.get("CLAUDE_PID", "")
    if cp.isdigit():
        cands.append(int(cp))
    cands += ancestors(proc, start)
    for pid in cands:
        d = session_file(sessions, proc, pid)
        if d is None:
            continue
        if session_id and d.get("sessionId") and d["sessionId"] != session_id:
            continue
        return pid, d
    return None


def block(pid: int | None, name: str | None) -> str:
    """The block. A variable this session cannot set is unset, so a value
    inherited from another session never stays."""
    lines = [BEGIN]
    lines.append(
        f"export HEAVY_BUILD_SESSION_PID={pid}"
        if pid
        else "unset HEAVY_BUILD_SESSION_PID"
    )
    if name and SAFE_NAME.fullmatch(name):
        lines.append(f"export HEAVY_BUILD_SESSION={name}")
    else:
        lines.append("unset HEAVY_BUILD_SESSION")
    lines += [WRAPPER, END]
    return "\n".join(lines) + "\n"


def without_block(text: str) -> str:
    """TEXT with an earlier block of this hook removed (resume, clear, compact)."""
    out, skip = [], False
    for line in text.splitlines(keepends=True):
        if line.rstrip("\n") == BEGIN:
            skip = True
            continue
        if skip:
            if line.rstrip("\n") == END:
                skip = False
            continue
        out.append(line)
    return "".join(out)


def main() -> int:
    env_file = os.environ.get("CLAUDE_ENV_FILE")
    if not env_file:
        return 0
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        data = {}
    sid = data.get("session_id") if isinstance(data, dict) else None
    home = Path.home()
    sessions = Path(
        os.environ.get("MACHINE_SESSION_SESSIONS_DIR", home / ".claude/sessions")
    )
    proc = Path(os.environ.get("HB_SESSION_HOOK_PROC", "/proc"))
    found = find_session(
        sessions, proc, os.getppid(), sid if isinstance(sid, str) else None
    )
    # Without a session file the block is still written: the pid when one is
    # known, the wrapper always, and a stale block from earlier is replaced.
    if found is None:
        pid, name = claude_pid(proc, os.getppid()), None
    else:
        pid, d = found
        name = d.get("name") if isinstance(d.get("name"), str) else None
    path = Path(env_file)
    try:
        old = path.read_text()
    except OSError:
        old = ""
    text = without_block(old)
    if text and not text.endswith("\n"):
        text += "\n"
    # Written in place, not through a temp file: Claude Code may run any file
    # it finds in the session-env folder, and no Bash command reads this file
    # before SessionStart is done.
    path.write_text(text + block(pid, name))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:  # never break a session start
        sys.exit(0)
