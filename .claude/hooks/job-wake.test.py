"""Tests for job-wake.sh / job-wake.py. Run: python3 job-wake.test.py"""

import json
import os
import subprocess
import tempfile
import time
from pathlib import Path

HOOK = str(Path(__file__).with_name("job-wake.sh"))
RID = "1793900000000000000-111-abcd1234"

failures = 0


def check(name, ok, detail=""):
    global failures
    if ok:
        print(f"PASS  {name}")
    else:
        failures += 1
        print(f"FAIL  {name}\n      {detail}")


class Env:
    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory(dir="/var/tmp")
        root = Path(self.tmp.name)
        self.root = root
        self.logs = root / "jobd-logs"
        self.state = root / "state"
        self.claude = root / "claude"
        self.logs.mkdir()
        self.claude.mkdir()
        self.proj = self.claude / "projects" / "p"
        self.proj.mkdir(parents=True)
        self.sid = "11111111-2222-3333-4444-555555555555"

    def env(self, **extra):
        e = dict(
            os.environ,
            JOB_WAKE_LOGS=str(self.logs),
            JOB_WAKE_STATE=str(self.state),
            JOB_WAKE_TEST_KIND="async",
            JOB_WAKE_POLL_SECS="0.2",
            CLAUDE_CONFIG_DIR=str(self.claude),
        )
        e.update(extra)
        return e

    def job(self, rid=RID, code=0, log="line one\nline two\n"):
        (self.logs / f"{rid}.log").write_text(log + "jobd: ok, ran 3 s\n")
        if code is not None:
            (self.logs / f"{rid}.exit").write_text(f"{code}\n")
        return f"{rid} {self.logs}/{rid}.log {self.logs}/{rid}.exit\n"

    def payload(self, out, cmd="job submit --detach -- cargo build", **extra):
        p = {
            "session_id": self.sid,
            "transcript_path": str(self.proj / f"{self.sid}.jsonl"),
            "cwd": "/home/x/repo",
            "hook_event_name": "PostToolUse",
            "tool_name": "Bash",
            "tool_input": {"command": cmd},
            "tool_response": {"stdout": out, "stderr": ""},
        }
        p.update(extra)
        return p

    def teammate(
        self,
        agent_id="abuilder-0123",
        name="builder",
        team="session-t1",
        kind="in_process_teammate",
        inbox=None,
    ):
        sub = self.proj / self.sid / "subagents"
        sub.mkdir(parents=True, exist_ok=True)
        meta = {"name": name, "teamName": team, "agentType": "general-purpose"}
        if kind:
            meta["taskKind"] = kind
        (sub / f"agent-{agent_id}.meta.json").write_text(json.dumps(meta))
        tdir = self.claude / "teams" / team
        (tdir / "inboxes").mkdir(parents=True, exist_ok=True)
        (tdir / "config.json").write_text(
            json.dumps(
                {
                    "members": [
                        {"name": "team-lead", "backendType": "in-process"},
                        {"name": name, "backendType": "in-process"},
                    ]
                }
            )
        )
        ib = tdir / "inboxes" / f"{name}.json"
        if inbox is not None:
            ib.write_text(inbox)
        return ib

    def wakes(self):
        f = self.state / "wakes.jsonl"
        if not f.exists():
            return []
        return [json.loads(x) for x in f.read_text().splitlines() if x.strip()]


def run(env, payload, timeout=30):
    t = time.monotonic()
    p = subprocess.run(
        ["bash", HOOK],
        input=payload if isinstance(payload, str) else json.dumps(payload),
        capture_output=True,
        text=True,
        timeout=timeout,
        env=env,
    )
    return p.returncode, p.stderr, time.monotonic() - t


# 1. not a detached submit: silent, nothing logged
e = Env()
rc, err, _ = run(e.env(), e.payload("x", cmd="ls -la"))
check(
    "non-job command exits 0 silently",
    rc == 0 and err == "" and e.wakes() == [],
    (rc, err),
)

# 2. plain -p session: skipped and logged
e = Env()
rc, err, _ = run(e.env(JOB_WAKE_TEST_KIND="print"), e.payload(e.job(code=None)))
w = e.wakes()
check("-p session exits 0 at once", rc == 0 and err == "", (rc, err))
check("-p session logged skipped-p", len(w) == 1 and w[0]["outcome"] == "skipped-p", w)

# 3. main session, job already ended
e = Env()
rc, err, _ = run(e.env(), e.payload(e.job(code=0)))
w = e.wakes()
check(
    "main wake exits 2 with result",
    rc == 2 and "succeeded with exit 0" in err,
    (rc, err),
)
check(
    "main wake logged",
    len(w) == 1
    and w[0]["outcome"] == "woke"
    and w[0]["submitted_by"] == "main"
    and w[0]["job_id"] == RID
    and w[0]["exit_code"] == 0
    and w[0]["cmd_class"] == "cargo"
    and w[0]["session"] == e.sid
    and "exit_to_wake_s" in w[0]
    and "waited_s" in w[0],
    w,
)
check("main wake has no forward note", "subagent" not in err, err)

# 4. job ends while the hook waits
e = Env()
out = e.job(code=None)
p = subprocess.Popen(
    ["bash", HOOK],
    stdin=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env=e.env(),
)
p.stdin.write(json.dumps(e.payload(out)))
p.stdin.close()
time.sleep(1)
(e.logs / f"{RID}.exit").write_text("3\n")
p.wait(timeout=20)
err = p.stderr.read()
w = e.wakes()
check(
    "waits for exit file, reports failure",
    p.returncode == 2 and "FAILED with exit 3" in err,
    err,
)
check("failure shows log tail", "line two" in err and "data only" in err, err)
check("waited_s about 1 s", w and 0.5 < w[0]["waited_s"] < 5, w)

# 5. unproven session type: short cap, then a note
e = Env()
rc, err, secs = run(
    e.env(JOB_WAKE_TEST_KIND="unknown", JOB_WAKE_UNPROVEN_SECS="1"),
    e.payload(e.job(code=None)),
)
w = e.wakes()
check(
    "unknown session caps the wait",
    rc == 2 and secs < 6 and "could not prove" in err,
    (rc, secs, err),
)
check(
    "unknown session logged timeout",
    w and w[0]["outcome"] == "timeout" and w[0]["session_kind"] == "unknown",
    w,
)

# 6. untrusted paths are ignored
e = Env()
bad = f"{RID} /etc/{RID}.log /etc/{RID}.exit\n"
rc, err, _ = run(e.env(), e.payload(bad))
w = e.wakes()
check("untrusted paths: no wake", rc == 0 and err == "", (rc, err))
check(
    "untrusted paths logged skipped-nojob", w and w[0]["outcome"] == "skipped-nojob", w
)

# 7. run_in_background submit
e = Env()
pl = e.payload(e.job())
pl["tool_input"]["run_in_background"] = True
rc, err, _ = run(e.env(), pl)
check(
    "background submit skipped",
    rc == 0 and e.wakes()[0]["outcome"] == "skipped-bg",
    e.wakes(),
)

# 8. in-process teammate: direct delivery
e = Env()
old = [
    {
        "from": "team-lead",
        "text": "hi",
        "timestamp": "2026-11-05T10:00:00.000Z",
        "read": False,
    }
]
ib = e.teammate(inbox=json.dumps(old))
rc, err, _ = run(
    e.env(),
    e.payload(e.job(code=0), agent_id="abuilder-0123", agent_type="general-purpose"),
)
msgs = json.loads(ib.read_text())
w = e.wakes()
new = msgs[-1] if msgs else {}
check("teammate inbox keeps old message", len(msgs) == 2 and msgs[0] == old[0], msgs)
check(
    "teammate message has SendMessage fields",
    new.get("from") == "jobd-hook"
    and new.get("read") is False
    and new.get("type") == "message"
    and new.get("msgV") == 1
    and len(new.get("msg_id", "")) == 36
    and new.get("timestamp", "").endswith("Z")
    and "succeeded with exit 0" in new.get("text", "")
    and new.get("summary", "").startswith("Detached job"),
    new,
)
check(
    "main told not to forward",
    rc == 2 and "already put this result" in err and "builder" in err,
    err,
)
check(
    "delivery logged",
    w
    and w[0]["outcome"] == "direct-delivered"
    and w[0]["agent_name"] == "builder"
    and w[0]["submitted_by"] == "subagent"
    and w[0]["delivered"] is True,
    w,
)
check(
    "no lock or temp file left",
    sorted(os.listdir(ib.parent)) == ["builder.json"],
    os.listdir(ib.parent),
)

# 9. teammate without an inbox file yet: created
e = Env()
ib = e.teammate()
rc, err, _ = run(e.env(), e.payload(e.job(code=0), agent_id="abuilder-0123"))
check(
    "missing inbox is created",
    ib.exists() and len(json.loads(ib.read_text())) == 1,
    ib.exists(),
)

# 10. plain subagent: no inbox, main forwards
e = Env()
e.teammate(kind=None)
rc, err, _ = run(
    e.env(), e.payload(e.job(code=0), agent_id="abuilder-0123", agent_type="Explore")
)
w = e.wakes()
check("plain subagent: forward note", rc == 2 and "forward this result" in err, err)
check(
    "plain subagent logged woke",
    w and w[0]["outcome"] == "woke" and not w[0].get("delivered"),
    w,
)

# 11. fresh lock held: no delivery after 3 s, main forwards
e = Env()
ib = e.teammate(inbox="[]")
lock = Path(str(ib) + ".lock")
lock.mkdir()
rc, err, secs = run(e.env(), e.payload(e.job(code=0), agent_id="abuilder-0123"))
check(
    "held lock: forward note, inbox untouched",
    "forward this result" in err and ib.read_text() == "[]",
    err,
)
check("held lock: gives up in about 3 s", 2.5 < secs < 8, secs)
check("held lock: other owner's lock kept", lock.is_dir())

# 12. stale lock (over 10 s old) is taken over
e = Env()
ib = e.teammate(inbox="[]")
lock = Path(str(ib) + ".lock")
lock.mkdir()
os.utime(lock, (time.time() - 60, time.time() - 60))
rc, err, _ = run(e.env(), e.payload(e.job(code=0), agent_id="abuilder-0123"))
check(
    "stale lock taken over",
    len(json.loads(ib.read_text())) == 1 and not lock.exists(),
    ib.read_text(),
)

# 13. inbox that is not a JSON list is left alone
e = Env()
ib = e.teammate(inbox='{"x": 1}')
rc, err, _ = run(e.env(), e.payload(e.job(code=0), agent_id="abuilder-0123"))
check(
    "bad inbox untouched, main forwards",
    ib.read_text() == '{"x": 1}' and "forward this result" in err,
    err,
)

# 14. teammate not in the team config: no delivery
e = Env()
ib = e.teammate(inbox="[]")
cfg = ib.parent.parent / "config.json"
cfg.write_text(
    json.dumps({"members": [{"name": "someone-else", "backendType": "in-process"}]})
)
rc, err, _ = run(e.env(), e.payload(e.job(code=0), agent_id="abuilder-0123"))
check(
    "unknown member: no delivery",
    ib.read_text() == "[]" and "forward this result" in err,
    err,
)

# 15. a name that would collide with the sender is refused
e = Env()
ib = e.teammate(name="jobd-hook", inbox="[]")
rc, err, _ = run(e.env(), e.payload(e.job(code=0), agent_id="abuilder-0123"))
check("sender-named teammate refused", ib.read_text() == "[]", ib.read_text())

# 16. wake log rotation at 10 MB
e = Env()
e.state.mkdir()
big = e.state / "wakes.jsonl"
with open(big, "wb") as f:
    f.truncate(10 * 1024 * 1024 + 1)
rc, err, _ = run(e.env(), e.payload(e.job(code=0)))
check(
    "wake log rotated",
    (e.state / "wakes.jsonl.1").stat().st_size > 10 * 1024 * 1024
    and len(e.wakes()) == 1,
    os.listdir(e.state),
)

# 17. wake log not writable: still wakes
e = Env()
e.state.write_text("not a dir")
rc, err, _ = run(e.env(), e.payload(e.job(code=0)))
check("unwritable log fails open", rc == 2 and "succeeded" in err, (rc, err))

# 18. broken JSON input fails open
e = Env()
rc, err, _ = run(e.env(), "job submit --detach {not json")
check("bad JSON exits 0", rc == 0 and err == "", (rc, err))
w = e.wakes()
check("bad JSON logged as error", len(w) == 1 and w[0]["outcome"] == "error", w)

# --- review round 1 regressions ---
import importlib.util

spec = importlib.util.spec_from_file_location(
    "jw", str(Path(__file__).with_name("job-wake.py"))
)
jw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(jw)
C = "/home/x/.local/share/claude/versions/2.1.318"
cases = [
    ([C], True, "async"),
    ([C], False, "unknown"),
    ([C, "--dangerously-skip-permissions"], True, "async"),
    ([C, "-p", "hello"], True, "print"),
    ([C, "--print", "hello"], False, "print"),
    ([C, "-pc"], True, "print"),
    (
        [C, "-p", "--input-format", "stream-json", "--output-format", "stream-json"],
        False,
        "async",
    ),
    ([C, "-p", "--input-format=stream-json"], False, "async"),
    ([C, "-p", "--", "--input-format=stream-json"], True, "print"),
    ([C, "--", "-p"], True, "async"),
    ([C, "--input-format", "stream-json"], True, "unknown"),
]
for argv, tty, want in cases:
    got = jw.classify_argv(argv, tty)
    check("classify %s tty=%s -> %s" % (argv[1:], tty, want), got == want, got)

# unreadable exit file (a directory): give up quietly, no wake
e = Env()
out = e.job(code=None)
(e.logs / f"{RID}.exit").mkdir()
rc, err, secs = run(e.env(JOB_WAKE_BAD_EXIT_SECS="0.5"), e.payload(out))
w = e.wakes()
check(
    "bad exit file: exits 0 fast", rc == 0 and err == "" and secs < 5, (rc, err, secs)
)
check("bad exit file logged error", w and w[0]["outcome"] == "error", w)

# another roster member is named like our sender: no delivery
e = Env()
ib = e.teammate(inbox="[]")
cfg = ib.parent.parent / "config.json"
c = json.loads(cfg.read_text())
c["members"].append({"name": "jobd-hook", "backendType": "in-process"})
cfg.write_text(json.dumps(c))
rc, err, _ = run(e.env(), e.payload(e.job(code=0), agent_id="abuilder-0123"))
check(
    "sender name on roster: no delivery",
    ib.read_text() == "[]" and "forward this result" in err,
    err,
)

# teammate replaced (new joinedAt) while the hook waited: no delivery
e = Env()
ib = e.teammate(inbox="[]")
cfg = ib.parent.parent / "config.json"
c = json.loads(cfg.read_text())
c["members"][1]["joinedAt"] = 1
cfg.write_text(json.dumps(c))
out = e.job(code=None)
p = subprocess.Popen(
    ["bash", HOOK],
    stdin=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env=e.env(),
)
p.stdin.write(json.dumps(e.payload(out, agent_id="abuilder-0123")))
p.stdin.close()
time.sleep(0.8)
c["members"][1]["joinedAt"] = 2
cfg.write_text(json.dumps(c))
(e.logs / f"{RID}.exit").write_text("0\n")
p.wait(timeout=20)
err = p.stderr.read()
w = e.wakes()
check(
    "replaced teammate: no delivery",
    ib.read_text() == "[]" and "forward this result" in err,
    err,
)
check(
    "replaced teammate logged", w and w[0].get("skip_reason") == "teammate changed", w
)

# failure with a long log: inbox gets a short tail, still delivered
e = Env()
ib = e.teammate(inbox="[]")
log = "".join("error line %d %s\n" % (i, "x" * 400) for i in range(50))
rc, err, _ = run(e.env(), e.payload(e.job(code=1, log=log), agent_id="abuilder-0123"))
msgs = json.loads(ib.read_text())
check(
    "long failure: inbox has short tail",
    len(msgs) == 1
    and len(msgs[0]["text"]) < 3000
    and "error line 49" in msgs[0]["text"],
    msgs and len(msgs[0]["text"]),
)
check("long failure: main keeps full tail", "Last 20 log lines" in err, err[:200])

# wake log path is a FIFO: no hang, still wakes
e = Env()
e.state.mkdir()
os.mkfifo(e.state / "wakes.jsonl")
rc, err, secs = run(e.env(), e.payload(e.job(code=0)), timeout=15)
check("FIFO wake log: no hang", rc == 2 and secs < 5, (rc, secs))

print("\n%d failure(s)" % failures)
raise SystemExit(1 if failures else 0)
