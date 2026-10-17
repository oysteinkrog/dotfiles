"""Tests for claude-version-restart, claude-persist-resume.py and claude-tab-run.

They use fake sessions files, fake transcripts and a fake System (no /proc, no
mux server, no signals). Nothing touches a real Claude session.

Run: python3 ~/.dotfiles/bin/claude-version-restart.test.py
"""

import atexit
import importlib.machinery
import importlib.util
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

BIN = Path(__file__).resolve().parent
DOT = BIN.parent
RESUME_PY = DOT / ".claude/hooks/claude-persist-resume.py"

_loader = importlib.machinery.SourceFileLoader(
    "cvr", str(BIN / "claude-version-restart")
)
_spec = importlib.util.spec_from_loader("cvr", _loader)
cvr = importlib.util.module_from_spec(_spec)
sys.modules["cvr"] = cvr  # dataclasses look the module up
_loader.exec_module(cvr)
resume = cvr.load_resume_module(RESUME_PY)

_tmp = tempfile.mkdtemp(prefix="cvr-test-", dir="/var/tmp")
atexit.register(shutil.rmtree, _tmp, True)

NOW = 1_800_000_000.0
INSTALLED = "2.1.302"
OLD = "2.1.299"


def iso(ts):
    return (
        datetime.fromtimestamp(ts, timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


def tool_use(ts, name, args, use_id="toolu_1"):
    return {
        "type": "assistant",
        "timestamp": iso(ts),
        "message": {
            "content": [{"type": "tool_use", "id": use_id, "name": name, "input": args}]
        },
    }


def tool_result(ts, use_id, result):
    return {
        "type": "user",
        "timestamp": iso(ts),
        "message": {
            "content": [
                {"type": "tool_result", "tool_use_id": use_id, "content": "Cron ok"}
            ]
        },
        "toolUseResult": result,
    }


class FakeSystem:
    """Stands in for cvr.System."""

    def __init__(self, env):
        self.env = env
        self.t = NOW
        self.procs = {}  # pid -> dict(parent, argv, environ, children, tty)
        self.atimes = {}
        self.input = NOW - 3600
        self.panes = []
        self.cls = {}
        self.killed = []
        self.ignore_term = set()
        self.respawned = []
        self.ft_calls = []
        self.on_sleep = None
        self.my_ancestors = set()

    def now(self):
        return self.t

    def sleep(self, s):
        self.t += s
        if self.on_sleep:
            self.on_sleep(self)

    def boot_time(self):
        return 0.0

    def alive(self, pid):
        return pid in self.procs

    def parent(self, pid):
        return self.procs.get(pid, {}).get("parent", 1)

    def cmdline(self, pid):
        return self.procs.get(pid, {}).get("argv", [])

    def environ(self, pid):
        return self.procs.get(pid, {}).get("environ", {})

    def children(self, pid):
        return self.procs.get(pid, {}).get("children", [])

    def tty(self, pid):
        return self.procs.get(pid, {}).get("tty")

    def tty_atime(self, tty):
        return self.atimes.get(tty, NOW - 3600)

    def input_last(self):
        return self.input

    def installed_version(self):
        return INSTALLED

    def mcp_commands(self, cwd):
        return [["uvx", "some-server"]]

    def classes(self):
        return dict(self.cls)

    def mux_panes(self):
        return list(self.panes)

    def ft(self, *args):
        self.ft_calls.append(args)
        return 0, ""

    def kill(self, pid, sig):
        self.killed.append((pid, sig))
        if sig == signal.SIGTERM and pid in self.ignore_term:
            return
        self.procs.pop(pid, None)
        if self.env.respawn_after_kill:
            self.env.respawn_after_kill(pid)

    def respawn(self, entry_file, window_id):
        self.respawned.append((str(entry_file), window_id))
        self.panes.append(
            {"pane_id": 99, "tab_id": 99, "window_id": window_id, "tty_name": "x"}
        )
        return 0, "99"


class Env:
    """A temporary home with a sessions dir, transcripts and persist entries."""

    def __init__(self):
        self.root = Path(tempfile.mkdtemp(dir=_tmp))
        self.claude = self.root / "claude"
        (self.claude / "sessions").mkdir(parents=True)
        self.state = self.root / "state"
        self.persist = self.root / "persist"
        self.persist.mkdir()
        self.cwd = self.root / "work"
        self.cwd.mkdir()
        self.sys = FakeSystem(self)
        self.respawn_after_kill = None
        self.next_tab = 0

    def add(
        self,
        pid,
        sid,
        status="idle",
        version=OLD,
        name=None,
        updated_ago=3600,
        cls="normal",
        transcript=(),
        environ=None,
        children=(),
        waiting_for=None,
    ):
        cwd = str(self.cwd)
        data = {
            "pid": pid,
            "sessionId": sid,
            "cwd": cwd,
            "version": version,
            "kind": "interactive",
            "entrypoint": "cli",
            "name": name or f"s{pid}",
            "status": status,
            "statusUpdatedAt": int((NOW - updated_ago) * 1000),
        }
        if waiting_for:
            data["waitingFor"] = waiting_for
        (self.claude / "sessions" / f"{pid}.json").write_text(json.dumps(data))
        slug = cvr.project_slug(cwd)
        tdir = self.claude / "projects" / slug
        tdir.mkdir(parents=True, exist_ok=True)
        tfile = tdir / f"{sid}.jsonl"
        lines = [{"type": "user", "timestamp": iso(NOW - 4000), "message": {}}]
        lines += list(transcript)
        tfile.write_text("".join(json.dumps(x) + "\n" for x in lines))
        os.utime(tfile, (NOW - 3600, NOW - 3600))
        (self.persist / f"{sid}@{slug}.json").write_text(
            json.dumps(
                {
                    "session_id": sid,
                    "cwd": cwd,
                    "transcript": str(tfile),
                    "launcher": [],
                    "flags": [],
                    "status": status,
                }
            )
        )
        tty = f"/dev/pts/{pid}"
        kids = []
        for i, argv in enumerate(children):
            cpid = pid * 100 + i
            self.sys.procs[cpid] = {"parent": pid, "argv": argv}
            kids.append(cpid)
        self.sys.procs[pid] = {
            "parent": 1,
            "argv": ["claude"],
            "environ": dict(environ or {"WEZTERM_PANE": str(pid)}),
            "children": kids,
            "tty": tty,
        }
        self.sys.panes.append(
            {"pane_id": pid, "tab_id": self.next_tab, "window_id": 0, "tty_name": tty}
        )
        self.next_tab += 1
        self.sys.cls[pid] = cls
        return tfile

    def monitor(self, mode="dry-run"):
        args = SimpleNamespace(recheck_delay=30.0, verbose=False)
        return cvr.Monitor(
            self.sys,
            args,
            claude_dir=self.claude,
            state_dir=self.state,
            persist_dir=self.persist,
            resume_py=RESUME_PY,
            mode=mode,
        )

    def run(self, mode="dry-run"):
        results = self.monitor(mode).run()
        return {s.pid: d for s, d in results}

    def log(self):
        return (self.state / "decisions.log").read_text()


class MonitorTests(unittest.TestCase):
    def test_idle_candidate(self):
        e = Env()
        e.add(100, "sid-idle")
        self.assertEqual(e.run()[100], "candidate")
        self.assertIn("candidate pid=100", e.log())
        self.assertIn("would restart 2.1.299 -> 2.1.302 in a new tab", e.log())

    def test_dry_run_never_kills(self):
        e = Env()
        e.add(100, "sid-idle")
        e.run()
        self.assertEqual(e.sys.killed, [])
        self.assertEqual(e.sys.respawned, [])
        self.assertFalse((e.state / "intents").exists())

    def test_busy(self):
        e = Env()
        e.add(100, "s", status="busy")
        self.assertEqual(e.run()[100], "skip: status=busy")

    def test_waiting(self):
        e = Env()
        e.add(100, "s", status="waiting", waiting_for="input needed")
        self.assertEqual(e.run()[100], "skip: status=waiting (input needed)")

    def test_shell(self):
        e = Env()
        e.add(100, "s", status="shell")
        self.assertEqual(e.run()[100], "skip: status=shell")

    def test_idle_too_recent(self):
        e = Env()
        e.add(100, "s", updated_ago=120)
        self.assertEqual(e.run()[100], "skip: idle for only 120s")

    def test_critical_excluded(self):
        e = Env()
        e.add(100, "s", cls="critical", name="kpp")
        self.assertEqual(e.run()[100], "skip: critical session")

    def test_manager_excluded(self):
        e = Env()
        e.add(100, "s", name="manager-CI")
        self.assertEqual(e.run()[100], "skip: manager session")

    def test_ancestor_excluded(self):
        e = Env()
        e.add(100, "s")
        mon = e.monitor()
        mon.ancestors = lambda: {100}
        res = {s.pid: d for s, d in mon.run()}
        self.assertEqual(res[100], "skip: ancestor of this monitor")

    def test_recent_key_press(self):
        e = Env()
        e.add(100, "s")
        e.sys.input = NOW - 30
        self.assertEqual(e.run()[100], "skip: key press 30s ago")

    def test_recent_input_in_its_terminal(self):
        e = Env()
        e.add(100, "s")
        e.sys.atimes["/dev/pts/100"] = NOW - 45
        self.assertEqual(e.run()[100], "skip: input in its terminal 45s ago")

    def test_version_equal_skip(self):
        e = Env()
        e.add(100, "s", version=INSTALLED)
        self.assertEqual(
            e.run()[100],
            "skip: version 2.1.302 is not older than installed 2.1.302",
        )

    def test_persist_off(self):
        e = Env()
        e.add(100, "s", environ={"WEZTERM_PANE": "100", "CLAUDE_PERSIST": "0"})
        self.assertEqual(e.run()[100], "skip: CLAUDE_PERSIST=0")

    def test_mcp_child_allowed_other_child_not(self):
        e = Env()
        e.add(100, "a", children=[["python", "/x/pal-mcp-server/server.py"]])
        e.add(101, "b", children=[["uvx", "some-server", "--x"]])
        e.add(102, "c", children=[["/usr/bin/zsh", "-c", "sleep 100"]])
        res = e.run()
        self.assertEqual(res[100], "candidate")
        self.assertEqual(res[101], "candidate")
        self.assertTrue(res[102].startswith("skip: child process: /usr/bin/zsh"))

    def test_no_pane(self):
        e = Env()
        e.add(100, "s")
        e.sys.panes = []
        self.assertEqual(e.run()[100], "skip: no pane in the current mux server")

    def test_wakeup_due_soon(self):
        e = Env()
        e.add(
            100,
            "s",
            transcript=[
                tool_use(
                    NOW - 200,
                    "ScheduleWakeup",
                    {"delaySeconds": 260, "prompt": "/loop x"},
                )
            ],
        )
        self.assertEqual(e.run()[100], "skip: ScheduleWakeup due in 60s")

    def test_wakeup_far_is_candidate_with_rearm(self):
        e = Env()
        e.add(
            100,
            "s",
            transcript=[
                tool_use(
                    NOW - 100,
                    "ScheduleWakeup",
                    {"delaySeconds": 1300, "prompt": "/loop x"},
                )
            ],
        )
        self.assertEqual(e.run()[100], "candidate")
        self.assertIn("re-arm loop in 1170s", e.log())  # 1200 s left at the 2nd read

    def test_goal_with_loop_is_not_clean(self):
        e = Env()
        goal = {
            "type": "attachment",
            "attachment": {
                "type": "goal_status",
                "met": False,
                "condition": "tests pass",
            },
        }
        e.add(
            100,
            "s",
            transcript=[
                goal,
                tool_use(
                    NOW - 100, "ScheduleWakeup", {"delaySeconds": 1300, "prompt": "p"}
                ),
            ],
        )
        self.assertEqual(e.run()[100], "skip: unmet /goal that does not re-arm cleanly")

    def test_goal_alone_is_clean(self):
        e = Env()
        goal = {
            "type": "attachment",
            "attachment": {
                "type": "goal_status",
                "met": False,
                "condition": "tests pass",
            },
        }
        e.add(100, "s", transcript=[goal])
        self.assertEqual(e.run()[100], "candidate")
        self.assertIn("re-arm goal", e.log())

    def test_second_read_disagrees(self):
        e = Env()
        e.add(100, "s")

        def turn_busy(sysobj):
            f = e.claude / "sessions" / "100.json"
            d = json.loads(f.read_text())
            d["statusUpdatedAt"] = int(sysobj.t * 1000)
            f.write_text(json.dumps(d))

        e.sys.on_sleep = turn_busy
        self.assertTrue(e.run()[100].startswith("skip: second read: idle for only"))

    def test_tab_run_detected(self):
        e = Env()
        e.add(100, "s", environ={"WEZTERM_PANE": "100", "CLAUDE_TAB_RUN": "50"})
        e.sys.procs[50] = {"parent": 1}
        e.sys.procs[100]["parent"] = 60
        e.sys.procs[60] = {"parent": 50}
        e.run()
        self.assertIn("in the same pane (claude-tab-run)", e.log())

    def test_per_run_limit(self):
        e = Env()
        for i in range(5):
            e.add(100 + i, f"s{i}")
        res = e.run()
        self.assertEqual(sum(1 for d in res.values() if d == "candidate"), 3)
        self.assertEqual(
            sum(
                1
                for d in res.values()
                if d == "skip: over the limit of 3 restarts per run"
            ),
            2,
        )

    def test_only_looks_at_one_session(self):
        e = Env()
        e.add(100, "aaaaaaaa-1")
        e.add(101, "bbbbbbbb-2")
        mon = e.monitor()
        mon.args.only = "bbbbbbbb"
        res = {s.pid: d for s, d in mon.run()}
        self.assertEqual(res, {101: "candidate"})
        self.assertNotIn("pid=100", e.log())

    def test_live_needs_only(self):
        with self.assertRaises(SystemExit):
            cvr.main(["--live"])
        with self.assertRaises(SystemExit):
            cvr.main(["--live", "--only", "abc"])

    def test_backoff_after_failure(self):
        e = Env()
        e.add(100, "s")
        key = f"s@{cvr.project_slug(str(e.cwd))}"
        (e.state / "sessions").mkdir(parents=True)
        (e.state / "sessions" / f"{key}.json").write_text(
            json.dumps({"failed_at": NOW - 3600})
        )
        self.assertTrue(e.run()[100].startswith("skip: restart failed 3600s ago"))


class LiveRestartTests(unittest.TestCase):
    """Live mode against the fake System only: no real process gets a signal."""

    def new_session_after_kill(self, e, version=INSTALLED):
        def respawn(pid):
            f = e.claude / "sessions" / f"{pid}.json"
            d = json.loads(f.read_text())
            f.unlink()
            d.update(pid=pid + 1000, version=version)
            (e.claude / "sessions" / f"{pid + 1000}.json").write_text(json.dumps(d))
            e.sys.procs[pid + 1000] = {"parent": 1}

        e.respawn_after_kill = respawn

    def test_tab_run_restart(self):
        e = Env()
        e.add(100, "s", environ={"WEZTERM_PANE": "100", "CLAUDE_TAB_RUN": "50"})
        e.sys.procs[50] = {"parent": 1}
        e.sys.procs[100]["parent"] = 50
        self.new_session_after_kill(e)
        res = e.run(mode="live")
        self.assertEqual(res[100], "restarted")
        self.assertEqual(e.sys.killed, [(100, signal.SIGTERM)])
        self.assertEqual(e.sys.respawned, [])
        intent = json.loads((e.state / "intents" / "tabrun-50.json").read_text())
        self.assertEqual(intent["session_id"], "s")
        entry = json.loads(Path(intent["entry_file"]).read_text())
        self.assertEqual(entry["status"], "idle")

    def test_new_tab_restart_moves_tab(self):
        e = Env()
        e.add(90, "other")
        e.add(100, "s", version=OLD)
        e.sys.procs[90]["children"] = [1]
        e.sys.procs[1] = {"argv": ["bash"]}  # keeps 90 out
        self.new_session_after_kill(e)
        res = e.run(mode="live")
        self.assertEqual(res[100], "restarted")
        self.assertEqual(len(e.sys.respawned), 1)
        self.assertIn(("move-tab", "--tab-id", "99", "--index", "1"), e.sys.ft_calls)

    def test_sigkill_after_timeout(self):
        e = Env()
        e.add(100, "s")
        e.sys.ignore_term.add(100)
        self.new_session_after_kill(e)
        res = e.run(mode="live")
        self.assertEqual(e.sys.killed, [(100, signal.SIGTERM), (100, signal.SIGKILL)])
        self.assertIn("sigkill pid=100", e.log())
        self.assertEqual(res[100], "restarted")

    def test_verify_fails_sets_backoff(self):
        e = Env()
        e.add(100, "s")
        res = e.run(mode="live")  # killed, nothing comes back
        self.assertTrue(res[100].startswith("failed: no new session"))
        key = f"s@{cvr.project_slug(str(e.cwd))}"
        st = json.loads((e.state / "sessions" / f"{key}.json").read_text())
        self.assertIn("failed_at", st)


class ResumePromptTests(unittest.TestCase):
    def write(self, entries, mtime=NOW - 3600):
        f = Path(tempfile.mkdtemp(dir=_tmp)) / "t.jsonl"
        f.write_text("".join(json.dumps(x) + "\n" for x in entries))
        os.utime(f, (mtime, mtime))
        return f

    def test_remaining_delay_text(self):
        f = self.write(
            [
                tool_use(
                    NOW - 100,
                    "ScheduleWakeup",
                    {"delaySeconds": 1300, "prompt": "/loop check CI"},
                )
            ]
        )
        out = resume.analyze(str(f), "idle", NOW)["prompt"]
        self.assertIn("delaySeconds=1200", out)
        self.assertIn('"/loop check CI"', out)
        self.assertIn("Do not run the loop now", out)

    def test_wakeup_due_now_runs_loop(self):
        f = self.write(
            [
                tool_use(
                    NOW - 100,
                    "ScheduleWakeup",
                    {"delaySeconds": 130, "prompt": "/loop check CI"},
                )
            ]
        )
        self.assertEqual(
            resume.analyze(str(f), "idle", NOW)["prompt"], "/loop check CI"
        )

    def test_cron_rearm_text(self):
        f = self.write(
            [
                tool_use(
                    NOW - 7200,
                    "CronCreate",
                    {"cron": "7 * * * *", "prompt": "hourly check", "recurring": True},
                    "u1",
                ),
                tool_result(
                    NOW - 7199,
                    "u1",
                    {"id": "aaaa1111", "recurring": True, "durable": False},
                ),
                tool_use(
                    NOW - 7000,
                    "CronCreate",
                    {"cron": "*/5 * * * *", "prompt": "deleted one", "recurring": True},
                    "u2",
                ),
                tool_result(
                    NOW - 6999,
                    "u2",
                    {"id": "bbbb2222", "recurring": True, "durable": False},
                ),
                tool_use(NOW - 6000, "CronDelete", {"id": "bbbb2222"}, "u3"),
                tool_use(
                    NOW - 5000,
                    "CronCreate",
                    {
                        "cron": "0 9 * * *",
                        "prompt": "durable one",
                        "recurring": True,
                        "durable": True,
                    },
                    "u4",
                ),
                tool_result(
                    NOW - 4999,
                    "u4",
                    {"id": "cccc3333", "recurring": True, "durable": True},
                ),
                tool_use(
                    NOW - 8 * 86400,
                    "CronCreate",
                    {"cron": "1 * * * *", "prompt": "expired one", "recurring": True},
                    "u5",
                ),
                tool_result(
                    NOW - 8 * 86400,
                    "u5",
                    {"id": "dddd4444", "recurring": True, "durable": False},
                ),
            ]
        )
        info = resume.analyze(str(f), "idle", NOW)
        self.assertEqual([j["id"] for j in info["crons"]], ["aaaa1111"])
        out = info["prompt"]
        self.assertIn("Re-create each one with CronCreate", out)
        self.assertIn('cron "7 * * * *" (recurring=true', out)
        self.assertIn('"hourly check"', out)
        self.assertNotIn("deleted one", out)
        self.assertNotIn("durable one", out)
        self.assertNotIn("expired one", out)

    def test_fired_one_shot_cron_dropped(self):
        f = self.write(
            [
                tool_use(
                    NOW - 7200,
                    "CronCreate",
                    {"cron": "* * * * *", "prompt": "once", "recurring": False},
                    "u1",
                ),
                tool_result(
                    NOW - 7199,
                    "u1",
                    {"id": "eeee5555", "recurring": False, "durable": False},
                ),
            ]
        )
        self.assertEqual(resume.analyze(str(f), "idle", NOW)["crons"], [])

    def test_idle_without_anything_stays_quiet(self):
        f = self.write([{"type": "user", "timestamp": iso(NOW - 10), "message": {}}])
        self.assertEqual(resume.analyze(str(f), "idle", NOW)["prompt"], "")

    def test_cron_next(self):
        t = time.mktime((2026, 10, 17, 17, 50, 30, 0, 0, -1))
        nxt = resume.cron_next("7 * * * *", t)
        self.assertEqual(time.localtime(nxt)[3:5], (18, 7))
        self.assertIsNone(resume.cron_next("bad", t))


class TabRunTests(unittest.TestCase):
    def test_restart_in_same_pane_then_fall_through(self):
        d = Path(tempfile.mkdtemp(dir=_tmp))
        (d / "state/claude-restart/intents").mkdir(parents=True)
        (d / "entry.json").write_text("{}")
        (d / "persist.sh").write_text(
            '[ "$1" = resume-cmd ] && echo "echo second-run; exit 4"\n'
        )
        (d / "first.sh").write_text(
            "echo first-run\n"
            'printf \'{"session_id":"s1","entry_file":"%s"}\' "$D/entry.json"'
            ' > "$D/state/claude-restart/intents/tabrun-$CLAUDE_TAB_RUN.json"\n'
            "exit 7\n"
        )
        env = dict(
            os.environ,
            D=str(d),
            XDG_STATE_HOME=str(d / "state"),
            CLAUDE_PERSIST_SH=str(d / "persist.sh"),
        )
        p = subprocess.run(
            [str(BIN / "claude-tab-run"), f"bash {d}/first.sh"],
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(p.stdout.splitlines()[0], "first-run")
        self.assertIn("second-run", p.stdout)
        self.assertEqual(p.returncode, 4)  # the second run's exit code, no third run

    def test_no_intent_passes_exit_code(self):
        d = Path(tempfile.mkdtemp(dir=_tmp))
        env = dict(os.environ, XDG_STATE_HOME=str(d))
        p = subprocess.run([str(BIN / "claude-tab-run"), "exit 3"], env=env, timeout=30)
        self.assertEqual(p.returncode, 3)


if __name__ == "__main__":
    unittest.main(verbosity=2)
