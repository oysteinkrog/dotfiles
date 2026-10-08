#!/usr/bin/env python3
"""Print the prompt to start a resumed Claude session with, or nothing.

Usage: claude-persist-resume.py TRANSCRIPT STATUS

claude-persist.sh resumes sessions after the terminal's mux server restarts.
A restart loses what lives only in the Claude process:

- a /goal, which is a session-scoped Stop hook;
- a /loop, whose next ScheduleWakeup never fires;
- an open question (AskUserQuestion) and the turn that was running.

STATUS is the session's last saved status: busy, waiting (a dialog such as a
question was open), shell or idle. shell seems to mean a background shell
command was running; the restart killed it, and the notice that would have
woken the session never comes, so it is treated like busy. Idle sessions with
no goal or loop get no prompt, so they stay quiet.
"""

import json
import os
import sys
from datetime import datetime

# Goal and loop markers are recent, so read only the end of a big transcript.
TAIL = 16 << 20

RESTARTED = (
    "The terminal restarted (FrankenTerm mux server restart or reboot), so this session"
    " was resumed with --resume and your last turn was cut off. Continue where you left"
    " off. If you were waiting for my answer to a question, ask it again with"
    " AskUserQuestion. Background agents and commands from before the restart were"
    " killed, so check what finished before relying on it."
)


def timestamp(entry):
    try:
        return datetime.fromisoformat(
            entry["timestamp"].replace("Z", "+00:00")
        ).timestamp()
    except (KeyError, TypeError, ValueError):
        return None


def scan(path):
    """Return (goal, loop): the condition of the last goal not yet met or
    cleared, and (due, prompt) of the last ScheduleWakeup that was not a stop."""
    goal = None
    loop = None
    with open(path, "rb") as fh:
        size = fh.seek(0, 2)
        fh.seek(max(0, size - TAIL))
        if size > TAIL:
            fh.readline()  # drop the partial first line
        for raw in fh:
            if b"goal" not in raw and b"ScheduleWakeup" not in raw:
                continue
            try:
                entry = json.loads(raw)
            except ValueError:
                continue
            attachment = entry.get("attachment") or {}
            if attachment.get("type") == "goal_status":
                goal = None if attachment.get("met") else attachment.get("condition")
            content = (entry.get("message") or {}).get("content")
            if (
                entry.get("type") == "user"
                and isinstance(content, str)
                and "<command-name>/goal</command-name>" in content
                and "<command-args>clear</command-args>" in content
            ):
                goal = None
            if not isinstance(content, list):
                continue
            for block in content:
                if not (
                    isinstance(block, dict)
                    and block.get("type") == "tool_use"
                    and block.get("name") == "ScheduleWakeup"
                ):
                    continue
                args = block.get("input") or {}
                when = timestamp(entry)
                if args.get("stop") or when is None:
                    loop = None
                else:
                    loop = (
                        when + float(args.get("delaySeconds") or 0),
                        args.get("prompt") or "",
                    )
    return goal, loop


def main():
    path, status = sys.argv[1], sys.argv[2]
    goal = loop = None
    last_write = 0.0
    if os.path.isfile(path):
        last_write = os.path.getmtime(path)
        goal, loop = scan(path)

    if goal:
        print("/goal " + goal)
    elif loop and loop[0] > last_write - 90:
        # The wakeup was due after the transcript's last write, so it had not
        # fired yet: the loop was still waiting for it.
        prompt = loop[1].strip()
        if not prompt or prompt.startswith("<<autonomous-loop"):
            print("/loop")
        elif prompt == "/loop" or prompt.startswith("/loop "):
            # ScheduleWakeup often stores the /loop command itself
            print(prompt)
        else:
            print("/loop " + prompt)
    elif status in ("busy", "waiting", "shell"):
        print(RESTARTED)


if __name__ == "__main__":
    main()
