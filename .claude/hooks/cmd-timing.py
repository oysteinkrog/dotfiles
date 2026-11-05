#!/usr/bin/env python3
"""Tell the agent how long a shell command took, and warn on a slow test loop.

Called by cmd-timing.sh with the hook payload on stdin. Works for Claude Code
(PostToolUse and PostToolUseFailure, which carry duration_ms) and for Codex
(PreToolUse records a start time keyed by tool_use_id, PostToolUse reads it).

Report: a command over REPORT_SECS (30 s) gets one line of additionalContext
with its elapsed time. When the command ran through heavy-build or `job`, the
time is split into jobd queue wait and run time. jobd prints nothing about the
wait, so the split comes from jobd's events.log: requests submitted and ended
inside this command's time window, from this cwd or a path named in the
command.

Warn: a build or test that ran over SLOW_SECS (5 min) and either
  - the git working tree changed by fewer than SMALL_DIFF_LINES (20) lines
    since the previous build or test in this session and repo, or
  - it is the second or later such slow run within REPEAT_WINDOW (30 min).

State lives in ~/.local/state/cmd-timing/ (CMD_TIMING_STATE overrides), one
JSON file per session, pruned after 3 days. Never blocks: any error exits 0
with no output.
"""

import importlib.util
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path

REPORT_SECS = 30
SLOW_SECS = 300
SMALL_DIFF_LINES = 20
REPEAT_WINDOW = 1800
PRUNE_SECS = 3 * 86400

STATE = Path(
    os.environ.get("CMD_TIMING_STATE")
    or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
        "cmd-timing",
    )
)
JOBD_EVENTS = os.environ.get("CMD_TIMING_JOBD_EVENTS") or os.path.expanduser(
    "~/.local/state/jobd/events.log"
)
HOOK_DIR = Path(__file__).resolve().parent

# Build and test commands that build-detect.py does not cover.
EXTRA_TEST_HEADS = {"pytest", "py.test", "ctest", "nextest", "tox", "nox"}
EXTRA_BUILD_HEADS = {"make", "ninja", "msbuild", "gradle", "gradlew", "mvn"}
SUB_HEADS = {
    "go": {"test", "build", "vet"},
    "npm": {"test", "t", "run", "ci"},
    "pnpm": {"test", "t", "run", "build"},
    "yarn": {"test", "run", "build"},
    "bun": {"test", "run"},
    "localbuild": {"build"},
    "cmake": {"--build"},
    "swift": {"build", "test"},
    "xcodebuild": None,
    "bazel": {"build", "test"},
}
QUEUE_HEADS = {"heavy-build", "job"}
HB_VALUE_OPTS = {
    "--class",
    "--wait-timeout",
    "--ready-file",
    "--on",
    "--prio",
    "--priority",
}


def now():
    v = os.environ.get("CMD_TIMING_NOW")
    return float(v) if v else time.time()


def fmt(secs):
    secs = int(round(secs))
    if secs < 60:
        return f"{secs} s"
    m, s = divmod(secs, 60)
    if m < 60:
        return f"{m} min {s} s" if s else f"{m} min"
    h, m = divmod(m, 60)
    return f"{h} h {m} min" if m else f"{h} h"


# --- command classification -------------------------------------------------

_bd = None


def build_detect():
    global _bd
    if _bd is None:
        spec = importlib.util.spec_from_file_location(
            "build_detect", HOOK_DIR / "build-detect.py"
        )
        assert spec is not None and spec.loader is not None
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        setattr(mod, "seg_mod", mod.load_segmenter())
        _bd = mod
    return _bd


def unwrap_queue(tokens):
    """`heavy-build [opts] -- CMD` or `job submit|run [opts] -- CMD` -> CMD."""
    head = os.path.basename(tokens[0])
    rest = tokens[1:]
    if "--" in rest:
        return rest[rest.index("--") + 1 :]
    if head == "job" and rest and rest[0] in ("submit", "run"):
        rest = rest[1:]
    i = 0
    while i < len(rest) and rest[i].startswith("-"):
        i += 2 if rest[i] in HB_VALUE_OPTS else 1
    return rest[i:]


def classify_tokens(bd, tokens, cwd):
    assigns, rest = bd.strip(tokens)
    if not rest:
        return None
    if os.path.basename(rest[0]) in QUEUE_HEADS:
        rest = unwrap_queue(rest)
        if not rest:
            return None
        assigns, rest = bd.strip(rest)
        if not rest:
            return None
    label = bd.is_heavy_in(rest, cwd)
    if label:
        return label
    head = os.path.basename(rest[0])
    if head.startswith("python") and rest[1:3] == ["-m", "pytest"]:
        return "pytest"
    if head in EXTRA_TEST_HEADS or head in EXTRA_BUILD_HEADS:
        return head
    script = bd.script_head(rest)
    if script != rest[0] and re.search(
        r"(^|/)(run-?tests?|test|build)[\w.-]*\.sh$", script
    ):
        return os.path.basename(script)
    if re.search(r"(^|/)(run-?tests?|build)[\w.-]*\.(sh|cmd|ps1)$", rest[0]):
        return os.path.basename(rest[0])
    if head in SUB_HEADS:
        subs = SUB_HEADS[head]
        args = rest[1:]
        if subs is None:
            return head
        if head == "cmake":
            return "cmake --build" if "--build" in args else None
        sub = next((a for a in args if not a.startswith("-")), None)
        if sub in subs:
            if sub == "run":
                i = args.index("run")
                script = args[i + 1] if i + 1 < len(args) else ""
                if not re.search(r"test|build", script):
                    return None
                return f"{head} run {script}"
            return f"{head} {sub}"
    return None


def classify(command, cwd):
    """Return (label, cwd after any cd) when the command runs a build or test."""
    bd = build_detect()
    blanked = bd.seg_mod.blank_data_regions(command)
    label = None
    for raw in bd.seg_mod.split_segments(command, blanked):
        seg = raw.strip().lstrip("({ ").rstrip(")} ").strip()
        if not seg:
            continue
        try:
            tokens = shlex.split(seg, comments=True)
        except ValueError:
            continue
        if not tokens:
            continue
        if tokens[0] == "cd":
            target = tokens[1] if len(tokens) > 1 else os.path.expanduser("~")
            if target != "-":
                cwd = bd.seg_mod.resolve_dir(bd.expand(target), cwd)
            continue
        found = classify_tokens(bd, tokens, cwd)
        if found and not label:
            label = found
    return label, cwd


def uses_queue(command):
    return bool(
        re.search(r"(^|[\s;&|(])(heavy-build|job\s+(submit|run))(\s|$)", command)
    )


# --- jobd queue split ---------------------------------------------------------

EV_RE = re.compile(r"^(\S+) .*?request=(\S+) event=(\w+)")
TS_FMT = "%Y-%m-%dT%H:%M:%S%z"


def parse_ts(s):
    from datetime import datetime

    return datetime.strptime(s, TS_FMT).timestamp()


def tail_lines(path, since):
    """Lines of the log from roughly `since` on, reading backwards in blocks."""
    with open(path, "rb") as f:
        f.seek(0, 2)
        end = f.tell()
        pos = end
        block = 256 * 1024
        data = b""
        while pos > 0:
            pos = max(0, pos - block)
            f.seek(pos)
            data = f.read(end - pos)
            first = data.split(b"\n", 2)
            if pos == 0 or len(first) < 3:
                if pos == 0:
                    break
                continue
            m = EV_RE.match(first[1].decode("utf-8", "replace"))
            if m and parse_ts(m.group(1)) < since:
                break
    lines = data.decode("utf-8", "replace").splitlines()
    return lines if pos == 0 else lines[1:]


def jobd_split(command, cwd, t0, t1):
    """Return (wait_secs, run_secs, n_jobs) for jobd requests this command made."""
    reqs = {}
    for line in tail_lines(JOBD_EVENTS, t0 - 10):
        m = EV_RE.match(line)
        if not m:
            continue
        ts_s, rid, ev = m.groups()
        r = reqs.setdefault(rid, {})
        if ev == "submit":
            cm = re.search(r" cwd=(.*?) argv0=", line)
            r["cwd"] = cm.group(1) if cm else ""
            try:
                r["submit"] = int(rid.split("-", 1)[0]) / 1e9
            except ValueError:
                r["submit"] = parse_ts(ts_s)
        elif ev == "start":
            am = re.search(r"attempt=\S+-a(\d+) ", line)
            r["start"] = float(am.group(1)) if am else parse_ts(ts_s)
        elif ev == "end":
            r["end"] = parse_ts(ts_s)
    wait = run = 0.0
    n = 0
    for r in reqs.values():
        sub = r.get("submit")
        if sub is None or sub < t0 - 1 or sub > t1 + 1:
            continue
        if r.get("end", t1) > t1 + 2:
            continue
        rc = r.get("cwd", "")
        if not rc or not (
            rc == cwd or (cwd and rc.startswith(cwd.rstrip("/") + "/")) or rc in command
        ):
            continue
        start = r.get("start")
        end = r.get("end", t1)
        if start is None:
            wait += max(0.0, end - sub)
        else:
            wait += max(0.0, start - sub)
            run += max(0.0, end - start)
        n += 1
    return wait, run, n


# --- working tree snapshot ----------------------------------------------------


def git(cwd, *args, env=None):
    p = subprocess.run(
        ["git", "--no-optional-locks", "-C", cwd, *args],
        capture_output=True,
        text=True,
        timeout=10,
        env=env,
    )
    if p.returncode != 0:
        raise RuntimeError(p.stderr)
    return p.stdout


def snapshot(cwd):
    """Return (repo top, tree id of the tracked working-tree content).

    Tracked files are hashed into a throwaway copy of the index, so the real
    index and refs are never touched. Untracked files are left out, so build
    output that is not ignored does not count as a change.
    """
    top, index = git(
        cwd,
        "rev-parse",
        "--path-format=absolute",
        "--show-toplevel",
        "--git-path",
        "index",
    ).splitlines()[:2]
    tmp = STATE / f"index.{os.getpid()}"
    STATE.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(
            ["cp", "--reflink=auto", index, str(tmp)],
            check=True,
            capture_output=True,
            timeout=10,
        )
        env = dict(os.environ, GIT_INDEX_FILE=str(tmp))
        git(top, "add", "-u", env=env)
        tree = git(top, "write-tree", env=env).strip()
    finally:
        try:
            tmp.unlink()
        except OSError:
            pass
    return top, tree


def changed_lines(top, old_tree, new_tree):
    """Lines added plus lines removed between two snapshot trees."""
    if old_tree == new_tree:
        return 0
    total = 0
    for line in git(top, "diff", "--numstat", old_tree, new_tree).splitlines():
        parts = line.split("\t", 2)
        if len(parts) == 3:
            a = int(parts[0]) if parts[0].isdigit() else 1
            d = int(parts[1]) if parts[1].isdigit() else 1
            total += a + d
    return total


# --- state --------------------------------------------------------------------


def safe(s):
    return re.sub(r"[^A-Za-z0-9_.-]", "_", s or "nosession")[:120]


def load(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f".{os.getpid()}.tmp")
    tmp.write_text(json.dumps(data))
    os.replace(tmp, path)


def prune():
    cut = time.time() - PRUNE_SECS
    for p in list(STATE.glob("*.json")) + list(STATE.glob("start/*/*")):
        try:
            if p.stat().st_mtime < cut:
                p.unlink()
        except OSError:
            pass
    for d in STATE.glob("start/*"):
        try:
            d.rmdir()
        except OSError:
            pass


# --- main -----------------------------------------------------------------------


def pre_tool_use(payload):
    sid, tid = payload.get("session_id"), payload.get("tool_use_id")
    if not tid:
        return
    p = STATE / "start" / safe(sid) / safe(tid)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(repr(now()))


def elapsed_of(payload):
    d = payload.get("duration_ms")
    if isinstance(d, (int, float)):
        return d / 1000.0
    sid, tid = payload.get("session_id"), payload.get("tool_use_id")
    if not tid:
        return None
    p = STATE / "start" / safe(sid) / safe(tid)
    try:
        start = float(p.read_text())
    except (OSError, ValueError):
        return None
    try:
        p.unlink()
    except OSError:
        pass
    return now() - start


def post_tool_use(payload):
    tool_input = payload.get("tool_input") or {}
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(command, str) or not command.strip():
        return None
    if isinstance(tool_input, dict) and tool_input.get("run_in_background"):
        return None
    elapsed = elapsed_of(payload)
    if elapsed is None:
        return None
    cwd = payload.get("cwd") or os.getcwd()
    t1 = now()
    t0 = t1 - elapsed

    label = None
    run_cwd = cwd
    try:
        label, run_cwd = classify(command, cwd)
    except Exception:
        label = None

    notes = []
    run_secs = elapsed
    if elapsed >= REPORT_SECS:
        split = None
        if uses_queue(command):
            try:
                wait, run, n = jobd_split(command, run_cwd or cwd, t0, t1)
                if n:
                    split = (wait, run)
            except Exception:
                split = None
        if split:
            wait, run = split
            run_secs = run
            notes.append(
                f"Command took {fmt(elapsed)}: {fmt(wait)} waiting in the jobd queue, "
                f"{fmt(run)} running."
            )
        else:
            notes.append(f"Command took {fmt(elapsed)}.")

    if label:
        warn = track_build(payload, label, run_cwd or cwd, run_secs, t1)
        if warn:
            notes.append(warn)
    if not notes:
        return None
    return " ".join(notes)


def track_build(payload, label, cwd, run_secs, t1):
    path = STATE / f"{safe(payload.get('session_id'))}.json"
    state = load(path)
    try:
        top, snap = snapshot(cwd)
    except Exception:
        top, snap = None, None

    small = None
    if top and snap:
        prev = (state.get("snapshots") or {}).get(top)
        if isinstance(prev, str) and prev:
            try:
                small = changed_lines(top, prev, snap)
            except Exception:
                small = None
        state.setdefault("snapshots", {})[top] = snap

    slow = [r for r in state.get("slow", []) if t1 - r["end"] <= REPEAT_WINDOW]
    warn = None
    if run_secs >= SLOW_SECS:
        slow.append({"end": t1, "secs": run_secs, "label": label})
        reasons = []
        if small is not None and small < SMALL_DIFF_LINES:
            lines = "line" if small == 1 else "lines"
            reasons.append(
                f"after a change of only {small} {lines} since the last build or test"
            )
        if len(slow) >= 2:
            total = sum(r["secs"] for r in slow)
            reasons.append(
                f", and it is slow run {len(slow)} in the last 30 min ({fmt(total)} in total)"
            )
        if reasons:
            what = (
                (" " + "".join(reasons)) if reasons[0][0] != "," else "".join(reasons)
            )
            warn = (
                f"Slow test loop: {label} ran {fmt(run_secs)}{what}. "
                "For the next iteration, run something narrower first: one test filter, "
                "one project or crate, or a check-only build (such as cargo check). "
                "Run the full suite once at the end, when the narrow run passes."
            )
    state["slow"] = slow
    try:
        save(path, state)
    except OSError:
        pass
    return warn


def main():
    payload = json.load(sys.stdin)
    event = payload.get("hook_event_name") or ""
    if payload.get("tool_name") not in ("Bash", "shell", "local_shell", "exec_command"):
        return 0
    if event == "PreToolUse":
        pre_tool_use(payload)
        return 0
    if event not in ("PostToolUse", "PostToolUseFailure"):
        return 0
    text = post_tool_use(payload)
    if text:
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": event,
                        "additionalContext": text,
                    }
                }
            )
        )
    if int(now()) % 50 == 0:
        prune()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
