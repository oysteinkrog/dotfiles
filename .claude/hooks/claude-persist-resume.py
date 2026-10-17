#!/usr/bin/env python3
"""Print the prompt to start a resumed Claude session with, or nothing.

Usage: claude-persist-resume.py TRANSCRIPT STATUS

claude-persist.sh resumes sessions after the terminal's mux server restarts,
and claude-version-restart resumes idle sessions on a new Claude version.
A restart loses what lives only in the Claude process:

- a /goal, which is a session-scoped Stop hook;
- a /loop, whose next ScheduleWakeup never fires;
- session-only CronCreate jobs (durable ones are on disk and survive);
- an open question (AskUserQuestion) and the turn that was running.

STATUS is the session's last saved status: busy, waiting (a dialog such as a
question was open), shell or idle. shell seems to mean a background shell
command was running; the restart killed it, and the notice that would have
woken the session never comes, so it is treated like busy. Idle sessions with
no goal, loop or cron job get no prompt, so they stay quiet.

A /loop wakeup that is still more than a minute away is not run at once: the
prompt tells the session how long was left, so it schedules the next wakeup
for the original time. A /goal takes the whole prompt (it is a slash command),
so cron jobs are not re-armed next to a goal.

claude-version-restart imports this file and calls analyze().
"""

import json
import os
import sys
import time
from datetime import datetime

# Goal, loop and cron markers are recent, so read only the end of a big transcript.
TAIL = 16 << 20

# A wakeup due sooner than this is run at once instead of being scheduled again.
RUN_NOW_WITHIN = 60

# Session-only cron jobs expire this long after they were created.
CRON_EXPIRY = 7 * 24 * 3600

CUT_OFF = ("busy", "waiting", "shell")

RESTARTED = (
    "This session was restarted (FrankenTerm mux server restart, reboot or a Claude Code"
    " update) and resumed with --resume, and your last turn was cut off. Continue where"
    " you left off. If you were waiting for my answer to a question, ask it again with"
    " AskUserQuestion. Background agents and commands from before the restart were"
    " killed, so check what finished before relying on it."
)

RESTARTED_IDLE = (
    "This session was restarted (FrankenTerm mux server restart, reboot or a Claude Code"
    " update) and resumed with --resume while it was idle. Do not start new work."
)

MARKERS = (b"goal", b"ScheduleWakeup", b"Cron", b"humanSchedule")


def timestamp(entry):
    try:
        return datetime.fromisoformat(
            entry["timestamp"].replace("Z", "+00:00")
        ).timestamp()
    except (KeyError, TypeError, ValueError, AttributeError):
        return None


# ---------------------------------------------------------------- cron times


def _field(spec, lo, hi):
    """The set of values a 5-field cron field allows, or None if it is invalid."""
    out = set()
    for part in spec.split(","):
        step = 1
        if "/" in part:
            part, s = part.split("/", 1)
            if not s.isdigit() or int(s) == 0:
                return None
            step = int(s)
        if part == "*":
            a, b = lo, hi
        elif "-" in part:
            x, y = part.split("-", 1)
            if not (x.isdigit() and y.isdigit()):
                return None
            a, b = int(x), int(y)
        elif part.isdigit():
            a = int(part)
            b = hi if step > 1 else a
        else:
            return None
        if a < lo or b > hi or a > b:
            return None
        out.update(range(a, b + 1, step))
    return out


def cron_next(expr, after):
    """The first time after `after` (epoch seconds) that the cron expression
    matches, in local time, or None. Looks at most 8 days ahead."""
    fields = expr.split()
    if len(fields) != 5:
        return None
    minute = _field(fields[0], 0, 59)
    hour = _field(fields[1], 0, 23)
    dom = _field(fields[2], 1, 31)
    month = _field(fields[3], 1, 12)
    dow = _field(fields[4].replace("7", "0"), 0, 6)
    if None in (minute, hour, dom, month, dow):
        return None
    dom_any, dow_any = fields[2] == "*", fields[4] == "*"
    t = (int(after) // 60 + 1) * 60
    for _ in range(8 * 24 * 60):
        lt = time.localtime(t)
        cron_dow = (lt.tm_wday + 1) % 7  # cron: 0 = Sunday
        if dom_any or dow_any:
            day_ok = lt.tm_mday in dom and cron_dow in dow
        else:
            day_ok = lt.tm_mday in dom or cron_dow in dow
        if lt.tm_min in minute and lt.tm_hour in hour and lt.tm_mon in month and day_ok:
            return float(t)
        t += 60
    return None


# ---------------------------------------------------------------- transcript


def scan_all(path):
    """Read the end of a transcript. Return a dict:

    goal   condition of the last /goal not yet met or cleared, or None
    loop   (due, prompt) of the last ScheduleWakeup that was not a stop, or None
    crons  CronCreate jobs created and not deleted, oldest first: dicts with
           id, cron, prompt, recurring, durable, created, next_fire
    """
    goal = None
    loop = None
    pending = {}  # tool_use id -> (input, created)
    crons = {}  # job id -> job
    deleted = set()
    with open(path, "rb") as fh:
        size = fh.seek(0, 2)
        fh.seek(max(0, size - TAIL))
        if size > TAIL:
            fh.readline()  # drop the partial first line
        for raw in fh:
            if not any(m in raw for m in MARKERS):
                continue
            try:
                entry = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(entry, dict):
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
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "tool_result":
                    use = pending.pop(block.get("tool_use_id"), None)
                    result = entry.get("toolUseResult")
                    if use and isinstance(result, dict) and result.get("id"):
                        args, created = use
                        crons[str(result["id"])] = {
                            "id": str(result["id"]),
                            "cron": str(args.get("cron") or ""),
                            "prompt": str(args.get("prompt") or ""),
                            "recurring": bool(args.get("recurring", True)),
                            "durable": bool(
                                result.get("durable", args.get("durable", False))
                            ),
                            "created": created,
                            "next_fire": (
                                result["nextFireAt"] / 1000
                                if isinstance(result.get("nextFireAt"), (int, float))
                                else None
                            ),
                        }
                    continue
                if block.get("type") != "tool_use":
                    continue
                name = block.get("name")
                args = block.get("input") or {}
                when = timestamp(entry)
                if name == "ScheduleWakeup":
                    if args.get("stop") or when is None:
                        loop = None
                    else:
                        loop = (
                            when + float(args.get("delaySeconds") or 0),
                            args.get("prompt") or "",
                        )
                elif name == "CronCreate" and when is not None:
                    pending[block.get("id")] = (args, when)
                elif name == "CronDelete" and args.get("id"):
                    deleted.add(str(args["id"]))
    jobs = [j for k, j in crons.items() if k not in deleted]
    jobs.sort(key=lambda j: j["created"])
    return {"goal": goal, "loop": loop, "crons": jobs}


def scan(path):
    """Return (goal, loop), as scan_all does."""
    found = scan_all(path)
    return found["goal"], found["loop"]


def live_crons(jobs, now):
    """The session-only cron jobs that a restart would lose: not durable, not
    expired, and for a one-shot job, not fired yet."""
    out = []
    for job in jobs:
        if job["durable"] or not job["cron"]:
            continue
        if now - job["created"] >= CRON_EXPIRY:
            continue
        if not job["recurring"]:
            fire = job["next_fire"] or cron_next(job["cron"], job["created"])
            if fire is None or fire <= now:
                continue
        out.append(job)
    return out


# ---------------------------------------------------------------- prompt


def clock(ts):
    return time.strftime("%H:%M", time.localtime(ts))


def loop_text(prompt):
    """What a /loop wakeup prompt runs, as the user would type it."""
    prompt = prompt.strip()
    if not prompt or prompt.startswith("<<autonomous-loop"):
        return "/loop"
    if prompt == "/loop" or prompt.startswith("/loop "):
        # ScheduleWakeup often stores the /loop command itself
        return prompt
    return "/loop " + prompt


def rearm_wakeup_text(due, prompt, now):
    left = int(round(due - now))
    return (
        f"A /loop was waiting for its next wakeup, due at {clock(due)} ({left} seconds"
        f" from now). Do not run the loop now. Call ScheduleWakeup once with"
        f" delaySeconds={left} and exactly this prompt, so it fires at the original"
        f" time: {json.dumps(prompt)}."
    )


def run_wakeup_text(prompt):
    return (
        f"A /loop wakeup was due when the session restarted. Run it now: "
        f"{json.dumps(loop_text(prompt))}."
    )


def cron_text(jobs, now):
    lines = []
    for job in jobs:
        nxt = cron_next(job["cron"], now)
        when = f", next run {clock(nxt)}" if nxt else ""
        lines.append(
            f"cron {json.dumps(job['cron'])} (recurring={str(job['recurring']).lower()}{when})"
            f" with prompt {json.dumps(job['prompt'])}"
        )
    return (
        "These session-only cron jobs were lost in the restart. Re-create each one with"
        " CronCreate, using the same cron, prompt and recurring values, and do not run"
        " them now: " + "; ".join(lines) + "."
    )


def analyze(path, status, now=None):
    """Work out what a restart of this session loses and the prompt to resume it
    with. Returns a dict with goal, loop (due, prompt) or None, loop_pending,
    crons (live session-only jobs) and prompt ('' for none)."""
    now = time.time() if now is None else now
    goal = loop = None
    jobs = []
    last_write = 0.0
    if path and os.path.isfile(path):
        last_write = os.path.getmtime(path)
        found = scan_all(path)
        goal, loop, jobs = found["goal"], found["loop"], found["crons"]
    crons = live_crons(jobs, now)
    # The wakeup was due after the transcript's last write, so it had not
    # fired yet: the loop was still waiting for it.
    loop_pending = bool(loop and loop[0] > last_write - 90)

    prompt = ""
    if goal:
        prompt = "/goal " + goal
    else:
        parts = []
        if loop_pending and loop[0] - now > RUN_NOW_WITHIN:
            parts.append(rearm_wakeup_text(loop[0], loop[1], now))
        elif loop_pending:
            if not crons:
                prompt = loop_text(loop[1])
            else:
                parts.append(run_wakeup_text(loop[1]))
        if crons:
            parts.append(cron_text(crons, now))
        if not prompt and (parts or status in CUT_OFF):
            head = RESTARTED if status in CUT_OFF else RESTARTED_IDLE
            prompt = " ".join([head] + parts)
    return {
        "goal": goal,
        "loop": loop,
        "loop_pending": loop_pending,
        "crons": crons,
        "prompt": prompt,
    }


def main():
    path, status = sys.argv[1], sys.argv[2]
    prompt = analyze(path, status)["prompt"]
    if prompt:
        print(prompt)


if __name__ == "__main__":
    main()
