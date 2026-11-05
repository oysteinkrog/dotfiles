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

import contextlib
import fcntl
import importlib.util
import json
import os
import re
import shlex
import signal
import subprocess
import sys
import time
from pathlib import Path

REPORT_SECS = 30
SLOW_SECS = 300
SMALL_DIFF_LINES = 20
REPEAT_WINDOW = 1800
PRUNE_SECS = 3 * 86400
PRUNE_EVERY = 3600
GIT_TIMEOUT = 3
LOCK_WAIT = 2.0

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
    "npm": {"test", "t", "run"},
    "pnpm": {"test", "t", "run", "build"},
    "yarn": {"test", "run", "build"},
    "bun": {"test", "run"},
    "localbuild": {"build"},
    "cmake": {"--build"},
    "swift": {"build", "test"},
    "xcodebuild": None,
    "bazel": {"build", "test"},
}
# Options before the subcommand that take a value, such as `npm --prefix web
# test` or `go -C backend test`.
SUB_VALUE_OPTS = {
    "-C",
    "--prefix",
    "--filter",
    "-F",
    "--dir",
    "--cwd",
    "-w",
    "--workspace",
}
DIRTY_SUB = ":dirty-submodule"
DIR_OPTS = {"-C", "--prefix", "--cwd", "--dir"}
CMAKE_DIR_OPTS = {"--build", "--test-dir"}
FILE_OPTS = {"--manifest-path", "--project"}
PROJECT_EXTS = (".sln", ".slnx", ".csproj", ".fsproj", ".vbproj", "Cargo.toml")
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
        i = 0
        while i < len(args) and args[i].startswith("-"):
            i += 2 if args[i] in SUB_VALUE_OPTS else 1
        sub = args[i] if i < len(args) else None
        if sub in subs:
            if sub == "run":
                script = args[i + 1] if i + 1 < len(args) else ""
                if not re.search(r"test|build", script):
                    return None
                return f"{head} run {script}"
            return f"{head} {sub}"
    return None


def classify(command, cwd):
    """Return (label, folder of that build, folders of the queue calls).

    label is the first build or test the command runs, or None. A `cd`
    inside `( ... )` ends with the subshell. A directory option such as
    `go -C dir` or `npm --prefix dir` sets the build folder.
    """
    bd = build_detect()
    blanked = bd.seg_mod.blank_data_regions(command)
    label = None
    build_cwd = cwd
    queue_cwds = []
    detached = []
    stack = []
    for raw in bd.seg_mod.split_segments(command, blanked):
        body = raw.strip()
        opened = len(body) - len(body.lstrip("( "))
        stack.extend([cwd] * body[:opened].count("("))
        tail = body.rstrip(") ")
        closed = body[len(tail) :].count(")")
        seg = body.lstrip("({ ").rstrip(")} ").strip()
        tokens = None
        if seg:
            try:
                tokens = shlex.split(seg, comments=True)
            except ValueError:
                tokens = None
        if seg:
            detached.extend(detached_in(bd, seg, cwd))
        if tokens and tokens[0] == "cd":
            target = tokens[1] if len(tokens) > 1 else os.path.expanduser("~")
            if target != "-":
                cwd = bd.seg_mod.resolve_dir(bd.expand(target), cwd)
        elif tokens:
            if is_queue(bd, tokens):
                queue_cwds.append(cwd)
            found = classify_tokens(bd, tokens, cwd)
            if found and not label:
                label = found
                build_cwd = dir_option(bd, tokens, cwd)
        for _ in range(closed):
            if stack:
                cwd = stack.pop()
    return label, build_cwd, queue_cwds, detached


DETACH_RE = re.compile(
    r"(?:^|[\s;&|(<`$])((?:\S*/)?(?:job\s+submit|heavy-build)\b[^;&|)`\n]*)"
)


def detached_in(bd, seg, cwd):
    """Detached queue submits in one segment, as [(label, build folder, cwd)].

    Matches `job submit --detach ... -- CMD` and `heavy-build --detach ...`
    anywhere in the segment, so `id=$(job submit --detach -- ...)` and
    `read id log ex < <(job submit --detach ...)` count too.
    """
    found = []
    for m in DETACH_RE.finditer(seg):
        try:
            tokens = shlex.split(m.group(1), comments=True)
        except ValueError:
            # Cut off inside a quoted string, as in `bash -lc 'job submit ...'`.
            tokens = m.group(1).replace("'", " ").replace('"', " ").split()
        if not tokens:
            continue
        opts = tokens[: tokens.index("--")] if "--" in tokens else tokens
        if "--detach" not in opts:
            continue
        label = None
        run_cwd = cwd
        try:
            label = classify_tokens(bd, tokens, cwd)
            if label:
                run_cwd = dir_option(bd, unwrap_queue(tokens), cwd)
        except Exception:
            label = None
        found.append((label, run_cwd, cwd))
    return found


def cmake_source(build_dir):
    """The source folder of a CMake build folder, from its CMakeCache.txt."""
    try:
        with open(os.path.join(build_dir, "CMakeCache.txt"), errors="replace") as f:
            for line in f:
                if line.startswith("CMAKE_HOME_DIRECTORY:"):
                    return line.split("=", 1)[1].strip() or build_dir
    except OSError:
        pass
    return build_dir


def dir_option(bd, tokens, cwd):
    """The folder the build really runs in; a CMake build folder maps to
    its source folder."""
    return cmake_source(build_dir_of(bd, tokens, cwd))


def build_dir_of(bd, tokens, cwd):
    """The folder the build really runs in.

    Follows `-C`, `--prefix`, `--cwd` and `--dir`, the folder of a
    `--manifest-path` or `--project` file, and the folder of a project or
    solution file given as an argument (dotnet test path/App.sln).
    """
    for i, t in enumerate(tokens):
        k, eq, v = t.partition("=")
        if eq and v and k in DIR_OPTS | FILE_OPTS | CMAKE_DIR_OPTS:
            name, val = k, v
        elif t in DIR_OPTS | FILE_OPTS | CMAKE_DIR_OPTS and i + 1 < len(tokens):
            name, val = t, tokens[i + 1]
        elif t.endswith(PROJECT_EXTS) and not t.startswith("-"):
            name, val = "--project", t
        else:
            continue
        path = bd.seg_mod.resolve_dir(bd.expand(val), cwd)
        if name in FILE_OPTS and not os.path.isdir(path):
            return os.path.dirname(path)
        return path
    return cwd


def is_queue(bd, tokens):
    _, rest = bd.strip(tokens)
    if not rest:
        return False
    head = os.path.basename(rest[0])
    if head == "heavy-build":
        return True
    return head == "job" and len(rest) > 1 and rest[1] in ("submit", "run")


# --- jobd queue split ---------------------------------------------------------

EV_RE = re.compile(r"^(\S+) (?:attempt=(\S+) )?request=(\S+) event=([\w-]+)")
TS_FMT = "%Y-%m-%dT%H:%M:%S%z"
TAIL_BLOCK = 256 * 1024
TAIL_MAX = 8 * 1024 * 1024


def parse_ts(s):
    from datetime import datetime

    return datetime.strptime(s, TS_FMT).timestamp()


def tail_lines(path, since):
    """Lines of the log from about `since` on.

    Reads backwards one block at a time, each block once, and stops at
    TAIL_MAX bytes. Returns None when the window is longer than that.
    """
    chunks = []
    with open(path, "rb") as f:
        f.seek(0, 2)
        pos = f.tell()
        read = 0
        while pos > 0:
            n = min(TAIL_BLOCK, pos)
            pos -= n
            f.seek(pos)
            chunks.append(f.read(n))
            read += n
            if pos == 0:
                break
            # Check the first whole line inside the block just read.
            head = chunks[-1].split(b"\n", 2)
            if len(head) == 3:
                m = re.match(rb"^(\S+) ", head[1])
                try:
                    if m and parse_ts(m.group(1).decode()) < since:
                        break
                except ValueError:
                    pass
            if read >= TAIL_MAX:
                return None
    lines = b"".join(reversed(chunks)).decode("utf-8", "replace").splitlines()
    return lines if pos == 0 else lines[1:]


def jobd_split(cwd, t0, t1):
    """Return (wait_secs, run_secs, n_ended, n_seen) for jobs from this cwd.

    n_seen counts every job submitted from the folder in the window, ended
    or not, so the caller can tell when another session shared the folder.

    Run time is the sum over attempts, so a retried job counts all the time
    it ran. An attempt ends at its last logged event, or at the request end.
    """
    lines = tail_lines(JOBD_EVENTS, t0 - 10)
    if lines is None:
        return 0.0, 0.0, 0, 0
    reqs = {}
    for line in lines:
        m = EV_RE.match(line)
        if not m:
            continue
        ts_s, att, rid, ev = m.groups()
        try:
            ts = parse_ts(ts_s)
        except ValueError:
            continue
        r = reqs.setdefault(rid, {"attempts": {}})
        if ev == "submit":
            cm = re.search(r" cwd=(.*?) argv0=", line)
            r["cwd"] = cm.group(1) if cm else ""
            try:
                r["submit"] = int(rid.split("-", 1)[0]) / 1e9
            except ValueError:
                r["submit"] = ts
        elif ev == "end":
            r["end"] = ts
        if att:
            a = r["attempts"].setdefault(att, {})
            if ev == "start":
                am = re.search(r"-a(\d+)$", att)
                a["start"] = float(am.group(1)) if am else ts
            elif ev == "route-failed":
                a["failed"] = ts
            a["last"] = ts
    wait = run = 0.0
    n = 0
    seen = 0
    for r in reqs.values():
        sub = r.get("submit")
        if sub is None or sub < t0 - 1 or sub > t1 + 1:
            continue
        rc = r.get("cwd", "")
        if not rc or not (rc == cwd or (cwd and rc.startswith(cwd.rstrip("/") + "/"))):
            continue
        seen += 1
        end = r.get("end")
        if end is None or end > t1 + 2:
            continue
        ran = 0.0
        atts = sorted(
            (a for a in r["attempts"].values() if "start" in a),
            key=lambda a: a["start"],
        )
        for i, a in enumerate(atts):
            if "failed" in a:
                stop = a["failed"]
            elif i == len(atts) - 1:
                stop = end
            else:
                stop = a["last"]
            ran += max(0.0, stop - a["start"])
        total = max(0.0, end - sub)
        ran = min(ran, total)
        run += ran
        wait += total - ran
        n += 1
    return wait, run, n, seen


# --- detached jobd jobs ---------------------------------------------------------

RID_RE = re.compile(r"\b(\d{19}-\d+-[0-9a-f]{8})\b")
JOBD_DB = os.environ.get("CMD_TIMING_JOBD_DB") or os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}",
    "jobd.state",
    "jobd.db",
)
JOBD_LOGS = os.environ.get("CMD_TIMING_JOBD_LOGS") or os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
    "jobd",
    "logs",
)
PENDING_MAX = 2 * 86400
FOOTER_TAIL = 8192
# `jobd: waited 12 s, ran 340 s` or `jobd: wait=12 run=340` (seconds; a
# trailing `min` unit is also read).
FOOTER_WAIT_RE = re.compile(r"\bwait(?:ed)?\s*[=:]?\s*([\d.]+)\s*(min|m|s)?\b")
FOOTER_RUN_RE = re.compile(r"\b(?:ran|run)\s*[=:]?\s*([\d.]+)\s*(min|m|s)?\b")


def response_text(response):
    """The text output of a tool call, for Claude Code and Codex payloads."""
    if isinstance(response, str):
        return response
    if isinstance(response, dict):
        parts = []
        for k in ("stdout", "output", "aggregated_output", "formatted_output"):
            v = response.get(k)
            if isinstance(v, str):
                parts.append(v)
        return "\n".join(parts)
    return ""


def jobd_db():
    import sqlite3

    return sqlite3.connect(f"file:{JOBD_DB}?mode=ro", uri=True, timeout=0.5)


def find_submitted(cwds, t0, t1):
    """Request ids jobd took from these folders between t0 and t1."""
    if not cwds:
        return []
    db = jobd_db()
    try:
        rows = db.execute(
            "select id, cwd from requests where submitted between ? and ? "
            "order by submitted",
            (t0 - 2, t1 + 2),
        ).fetchall()
    finally:
        db.close()
    return [rid for rid, c in rows if c in cwds]


def times_from_db(rid):
    """(submitted, ended, run_secs) from jobd's database, or None."""
    db = jobd_db()
    try:
        r = db.execute(
            "select submitted, ended from requests where id = ?", (rid,)
        ).fetchone()
        if not r or r[0] is None or r[1] is None:
            return None
        sub, end = float(r[0]), float(r[1])
        run = 0.0
        for st, en in db.execute(
            "select started, ended from attempts where request = ? and started is not null",
            (rid,),
        ):
            run += max(0.0, float(en if en is not None else end) - float(st))
    finally:
        db.close()
    total = max(0.0, end - sub)
    return sub, end, min(run, total)


def secs_of(m):
    v = float(m.group(1))
    return v * 60 if m.group(2) in ("min", "m") else v


def split_from_footer(log):
    """(wait, run) from a `jobd:` line at the end of the job log, or None."""
    with open(log, "rb") as f:
        f.seek(0, 2)
        f.seek(max(0, f.tell() - FOOTER_TAIL))
        tail = f.read().decode("utf-8", "replace")
    for line in reversed(tail.splitlines()):
        if not line.startswith("jobd:"):
            continue
        w, r = FOOTER_WAIT_RE.search(line), FOOTER_RUN_RE.search(line)
        if w and r:
            return secs_of(w), secs_of(r)
    return None


def job_paths(rid, text):
    """The log and exit file `job submit --detach` printed for rid."""
    m = re.search(re.escape(rid) + r"\s+(\S+\.log)\s+(\S+\.exit)", text)
    if m:
        return m.group(1), m.group(2)
    return os.path.join(JOBD_LOGS, rid + ".log"), os.path.join(JOBD_LOGS, rid + ".exit")


def finish_times(job, exit_mtime):
    """(wait or None, run, total, end) for a finished job.

    jobd's database first, then the `jobd:` footer in the log, then the time
    from submit to the exit file, all of it counted as run time.
    """
    with contextlib.suppress(Exception):
        t = times_from_db(job["id"])
        if t:
            sub, end, run = t
            return (end - sub) - run, run, end - sub, end
    total = max(0.0, exit_mtime - job["submit"])
    with contextlib.suppress(Exception):
        split = split_from_footer(job["log"])
        if split:
            wait, run = split
            return wait, run, wait + run, exit_mtime
    return None, total, total, exit_mtime


def exit_code(path):
    try:
        with open(path) as f:
            return f.read(64).strip().split()[0]
    except (OSError, IndexError):
        return None


def pending_mark(sid):
    return STATE / "pending" / safe(sid)


def set_pending_mark(sid, on):
    p = pending_mark(sid)
    try:
        if on:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.touch()
        else:
            p.unlink()
    except OSError:
        pass


# --- working tree snapshot ----------------------------------------------------


def git(cwd, *args, env=None):
    """Run git with a time limit that also stops any filter it started."""
    p = subprocess.Popen(
        ["git", "--no-optional-locks", "-C", cwd, *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        start_new_session=True,
    )
    try:
        out, err = p.communicate(timeout=GIT_TIMEOUT)
    except subprocess.TimeoutExpired:
        with contextlib.suppress(OSError):
            os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
        raise
    if p.returncode != 0:
        raise RuntimeError(err)
    return out


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
            timeout=GIT_TIMEOUT,
        )
        env = dict(os.environ, GIT_INDEX_FILE=str(tmp))
        git(top, "add", "-u", env=env)
        tree = git(top, "write-tree", env=env).strip()
    finally:
        try:
            tmp.unlink()
        except OSError:
            pass
    if submodule_dirty(top):
        tree += DIRTY_SUB
    return top, tree


def submodule_dirty(top):
    """True when a submodule has uncommitted changes to tracked files.

    The tree only records a submodule's commit, so edits inside it are
    invisible to the line count.
    """
    try:
        if os.path.getsize(os.path.join(top, ".gitmodules")) == 0:
            return False
    except OSError:
        return False
    out = git(top, "status", "--porcelain=v2", "-uno", "--ignore-submodules=untracked")
    for line in out.splitlines():
        parts = line.split(" ", 3)
        if parts[0] in ("1", "2") and len(parts) > 2:
            sub = parts[2]
            if sub.startswith("S") and len(sub) == 4 and sub[2] == "M":
                return True
    return False


def changed_lines(top, old_tree, new_tree):
    """Lines added plus lines removed between two snapshot trees.

    Returns None when a binary file changed, since its size in lines is
    unknown and must not count as a small change.
    """
    if old_tree.endswith(DIRTY_SUB) or new_tree.endswith(DIRTY_SUB):
        return None
    if old_tree == new_tree:
        return 0
    total = 0
    out = git(
        top,
        "diff",
        "--raw",
        "--numstat",
        "--ignore-submodules=none",
        old_tree,
        new_tree,
    )
    for line in out.splitlines():
        if line.startswith(":"):
            # A changed submodule commit (mode 160000) hides an unknown
            # amount of source change behind a one-line gitlink.
            if "160000" in line[1:].split()[:2]:
                return None
            continue
        parts = line.split("\t", 2)
        if len(parts) == 3:
            if not (parts[0].isdigit() and parts[1].isdigit()):
                return None
            total += int(parts[0]) + int(parts[1])
    return total


# --- state --------------------------------------------------------------------


def safe(s):
    return re.sub(r"[^A-Za-z0-9_.-]", "_", s or "nosession")[:120]


def load(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


@contextlib.contextmanager
def locked(path):
    """Hold an exclusive lock on path.lock for up to LOCK_WAIT seconds.

    Yields True when locked, False when the wait ran out. Parallel tool calls
    in one session would otherwise lose each other's updates.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(f"{path}.lock", os.O_CREAT | os.O_RDWR, 0o600)
    try:
        deadline = time.monotonic() + LOCK_WAIT
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                os.utime(fd)  # keeps prune() away from a live lock file
                break
            except BlockingIOError:
                if time.monotonic() > deadline:
                    yield False
                    return
                time.sleep(0.02)
        yield True
    finally:
        os.close(fd)


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f".{os.getpid()}.tmp")
    tmp.write_text(json.dumps(data))
    os.replace(tmp, path)


def prune():
    """Delete state older than PRUNE_SECS, at most once per PRUNE_EVERY."""
    mark = STATE / ".pruned"
    try:
        if time.time() - mark.stat().st_mtime < PRUNE_EVERY:
            return
    except OSError:
        pass
    try:
        STATE.mkdir(parents=True, exist_ok=True)
        mark.touch()
    except OSError:
        return
    cut = time.time() - PRUNE_SECS
    old = list(STATE.glob("*.json")) + list(STATE.glob("*.lock"))
    old += list(STATE.glob("index.*")) + list(STATE.glob("start/*/*"))
    old += list(STATE.glob("pending/*"))
    for p in old:
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
    """Return (text for the agent or None, records for notes.jsonl)."""
    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        return None, []
    command = tool_input.get("command") or tool_input.get("cmd")
    if isinstance(command, list):
        # Codex exec form: ["bash", "-lc", "CMD"] runs CMD.
        if (
            len(command) == 3
            and os.path.basename(str(command[0])) in ("bash", "sh", "zsh")
            and command[1] in ("-c", "-lc")
        ):
            command = str(command[2])
        else:
            command = shlex.join(str(c) for c in command)
    if not isinstance(command, str) or not command.strip():
        return None, []
    sid = payload.get("session_id")
    cwd = tool_input.get("workdir") or payload.get("cwd") or os.getcwd()
    # A background call, or a foreground call that hit its time limit and
    # moved to the background, is still running: its time so far says
    # nothing. Detached jobs it finished are still reported.
    response = payload.get("tool_response")
    background = bool(tool_input.get("run_in_background")) or (
        isinstance(response, dict) and bool(response.get("backgroundTaskId"))
    )
    elapsed = None if background else elapsed_of(payload)
    t1 = now()
    notes, records, submitted = [], [], set()
    if elapsed is not None:
        notes, records, submitted = timed_notes(payload, command, cwd, elapsed, t1)
    try:
        jn, jr = finish_jobs(sid, cwd, t1, submitted)
        notes += jn
        records += jr
    except Exception:
        pass
    if not notes:
        return None, records
    return " ".join(notes), records


def timed_notes(payload, command, cwd, elapsed, t1):
    """Notes on the command just run, and the jobs it submitted detached."""
    t0 = t1 - elapsed
    label = None
    run_cwd = cwd
    queue_cwds = []
    detached = []
    try:
        label, run_cwd, queue_cwds, detached = classify(command, cwd)
    except Exception:
        label = None

    notes = []
    # Time that counts toward a slow-run warning. When the command went
    # through the queue and the wait cannot be split out, the elapsed time
    # may be mostly queue wait, so it does not count.
    run_secs = elapsed
    if elapsed >= REPORT_SECS:
        split = None
        if queue_cwds:
            run_secs = 0.0
            try:
                # Only one queue folder is searched, so calls from several
                # folders get no split.
                if len(set(queue_cwds)) == 1:
                    wait, run, n, seen = jobd_split(queue_cwds[0], t0, t1)
                    # More jobs from the folder than queue calls means another
                    # session used it at the same time, a job still running
                    # means ours is not done, and more queue time than elapsed
                    # time means jobs ran in parallel: do not guess.
                    if 0 < n == seen <= len(queue_cwds) and wait + run <= elapsed + 2:
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

    submitted = set()
    warn = None
    if detached:
        # The job runs later, so its time is judged when it ends. Only the
        # working tree is recorded now.
        try:
            submitted = record_jobs(payload, command, detached, t0, t1)
        except Exception:
            submitted = set()
    elif label:
        warn = track_build(payload, label, run_cwd or cwd, run_secs, t1)
        if warn:
            notes.append(warn)
    records = []
    if notes:
        records.append(
            record(payload, cwd, "command", label, elapsed, bool(warn), None, t1)
        )
    return notes, records, submitted


def record(payload, cwd, kind, label, secs, warned, job, t1, **extra):
    r = {
        "ts": round(t1, 3),
        "session": payload.get("session_id"),
        "cwd": cwd,
        "kind": kind,
        "class": label,
        "secs": round(secs, 1),
        "warned": warned,
        "job": job,
    }
    r.update(extra)
    return r


def record_jobs(payload, command, detached, t0, t1):
    """Save the jobs this command submitted with --detach as pending."""
    text = response_text(payload.get("tool_response"))
    ids = list(dict.fromkeys(RID_RE.findall(text)))
    if not ids:
        with contextlib.suppress(Exception):
            ids = find_submitted({d[2] for d in detached}, t0, t1)
    if not ids:
        return set()
    sid = payload.get("session_id")
    path = STATE / f"{safe(sid)}.json"
    with locked(path) as ok:
        if not ok:
            return set()
        state = load(path)
        labelled = [d for d in detached if d[0]]
        small = update_snapshot(state, labelled[0][1]) if labelled else None
        pending = state.setdefault("pending", {})
        for i, rid in enumerate(ids):
            if rid in pending:
                continue
            label, run_cwd, _ = detached[min(i, len(detached) - 1)]
            log, ex = job_paths(rid, text)
            try:
                sub = int(rid.split("-", 1)[0]) / 1e9
            except ValueError:
                sub = t1
            pending[rid] = {
                "id": rid,
                "submit": sub,
                "label": label,
                "cwd": run_cwd,
                "cmd": command[:300],
                "small": small if label else None,
                "log": log,
                "exit": ex,
            }
        try:
            save(path, state)
        except OSError:
            return set()
    set_pending_mark(sid, True)
    return set(ids)


def finish_jobs(sid, cwd, t1, skip):
    """Report detached jobs of this session that have ended, once each."""
    if not pending_mark(sid).exists():
        return [], []
    path = STATE / f"{safe(sid)}.json"
    notes, records = [], []
    with locked(path) as ok:
        if not ok:
            return [], []
        state = load(path)
        pending = state.get("pending") or {}
        for rid in list(pending):
            job = pending[rid]
            if rid in skip:
                continue
            try:
                mtime = os.stat(job["exit"]).st_mtime
            except OSError:
                if t1 - job.get("submit", 0) > PENDING_MAX:
                    del pending[rid]
                continue
            except (KeyError, TypeError):
                del pending[rid]
                continue
            del pending[rid]
            wait, run, total, _ = finish_times(job, mtime)
            label = job.get("label")
            warn = None
            if label:
                warn = slow_check(state, label, run, t1, job.get("small"))
            if total < REPORT_SECS and not warn:
                continue
            code = exit_code(job["exit"])
            what = label or "command"
            ended = f"ended with exit {code}" if code is not None else "ended"
            if wait is not None:
                text = (
                    f"Job {rid} ({what}) {ended} after {fmt(total)}: "
                    f"{fmt(wait)} waiting in the jobd queue, {fmt(run)} running."
                )
            else:
                text = f"Job {rid} ({what}) {ended} after {fmt(total)} since submit."
            notes.append(text)
            if warn:
                notes.append(warn)
            records.append(
                record(
                    {"session_id": sid},
                    cwd,
                    "job",
                    label,
                    total,
                    bool(warn),
                    rid,
                    t1,
                    run=round(run, 1),
                    wait=None if wait is None else round(wait, 1),
                )
            )
        state["pending"] = pending
        try:
            save(path, state)
        except OSError:
            pass
    set_pending_mark(sid, bool(pending))
    return notes, records


def track_build(payload, label, cwd, run_secs, t1):
    path = STATE / f"{safe(payload.get('session_id'))}.json"
    with locked(path) as ok:
        if not ok:
            return None
        state = load(path)
        small = update_snapshot(state, cwd)
        warn = slow_check(state, label, run_secs, t1, small)
        try:
            save(path, state)
        except OSError:
            pass
        return warn


def update_snapshot(state, cwd):
    """Record the working tree of cwd; return lines changed since the last."""
    try:
        top, snap = snapshot(cwd)
    except Exception:
        # The tree may have changed without a record, so no earlier
        # snapshot can stand in for the previous run any more.
        state["snapshots"] = {}
        return None
    small = None
    prev = (state.get("snapshots") or {}).get(top)
    if isinstance(prev, str) and prev:
        try:
            small = changed_lines(top, prev, snap)
        except Exception:
            small = None
    state.setdefault("snapshots", {})[top] = snap
    return small


def slow_check(state, label, run_secs, t1, small):
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
    return warn


NOTES_MAX = int(os.environ.get("CMD_TIMING_NOTES_MAX") or 10 * 1024 * 1024)


def append_notes(records):
    """Append records to notes.jsonl; keep one old file past NOTES_MAX."""
    if not records:
        return
    path = STATE / "notes.jsonl"
    with contextlib.suppress(OSError):
        STATE.mkdir(parents=True, exist_ok=True)
        with contextlib.suppress(OSError):
            if path.stat().st_size > NOTES_MAX:
                os.replace(path, STATE / "notes.jsonl.1")
        data = "".join(json.dumps(r) + "\n" for r in records).encode()
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        try:
            os.write(fd, data)
        finally:
            os.close(fd)


def main():
    payload = json.load(sys.stdin)
    event = payload.get("hook_event_name") or ""
    if payload.get("tool_name") not in ("Bash", "shell", "local_shell", "exec_command"):
        return 0
    if event == "PreToolUse":
        pre_tool_use(payload)
        prune()
        return 0
    if event not in ("PostToolUse", "PostToolUseFailure"):
        return 0
    text, records = post_tool_use(payload)
    with contextlib.suppress(Exception):
        append_notes(records)
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
    prune()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
