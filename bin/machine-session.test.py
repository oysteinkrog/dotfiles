"""Tests for machine-session. Each test builds a fake world: a fake /proc, a
fake cgroup tree, a fake ~/.claude/sessions, a registry and a grove registry.
Nothing touches the real cgroups or sessions.

Run: python3 ~/.dotfiles/bin/machine-session.test.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOL = str(Path(__file__).with_name("machine-session"))
UID = os.getuid()
USVC = f"user.slice/user-{UID}.slice/user@{UID}.service"

REGISTRY = """
default = "normal"
ephemeral_lanes = "pausable"
[sessions]
boss = "critical"
idler = "pausable"
pinned = "normal"
[lanes]
lane-a = "pausable"
eph-held = "critical"
"""


class World:
    def __init__(self):
        self.root = Path(tempfile.mkdtemp(prefix="ms-test.", dir="/var/tmp/claude"))
        self.proc = self.root / "proc"
        self.cg = self.root / "cg"
        self.sessions = self.root / "sessions"
        self.state = self.root / "state"
        self.work = self.root / "work"
        for d in (self.proc, self.cg, self.sessions, self.work / ".grove"):
            d.mkdir(parents=True)
        (self.root / "sessions.toml").write_text(REGISTRY)
        (self.root / "repos.json").write_text(
            json.dumps({"repos": {"desktop": {"work_dir": str(self.work)}}})
        )
        (self.work / ".grove/registry.json").write_text(
            json.dumps(
                {
                    "projects": {
                        "lane-a": {
                            "path": str(self.work / "lane-a"),
                            "expires_at": None,
                        },
                        "long": {"path": str(self.work / "long"), "expires_at": None},
                        "eph": {
                            "path": str(self.work / ".scratch/eph"),
                            "expires_at": "2026-10-20T00:00:00Z",
                        },
                        "eph-held": {
                            "path": str(self.work / ".scratch/eph-held"),
                            "expires_at": "2026-10-20T00:00:00Z",
                        },
                    }
                }
            )
        )

    def env(self, **extra):
        e = dict(os.environ)
        e.update(
            MACHINE_SESSION_REGISTRY=str(self.root / "sessions.toml"),
            MACHINE_SESSION_SESSIONS_DIR=str(self.sessions),
            MACHINE_SESSION_STATE=str(self.state),
            MACHINE_SESSION_GROVE_REPOS=str(self.root / "repos.json"),
            MACHINE_SESSION_PROC=str(self.proc),
            MACHINE_SESSION_CGROUP=str(self.cg),
            MACHINE_SESSION_FREEZE_WAIT="0",
            MACHINE_SESSION_SAMPLE_SECS="0",
            MACHINE_SESSION_JOURNAL="0",
        )
        e.update(extra)
        return e

    def proc_entry(self, pid, ppid, cgroup, start=1000):
        d = self.proc / str(pid)
        d.mkdir(exist_ok=True)
        (d / "cgroup").write_text(f"0::{cgroup}\n")
        # Fields after "(comm) ": state ppid ... starttime is the 20th.
        rest = ["S", str(ppid)] + ["0"] * 17 + [str(start)]
        (d / "stat").write_text(f"{pid} (claude a b) " + " ".join(rest) + "\n")

    def scope(self, launcher):
        d = self.cg / USVC / "claude.slice" / f"claude-{launcher}.scope"
        d.mkdir(parents=True, exist_ok=True)
        (d / "cgroup.freeze").write_text("0\n")
        (d / "cgroup.events").write_text("populated 1\nfrozen 0\n")
        (d / "memory.current").write_text(str(2 * 1073741824))
        (d / "memory.swap.current").write_text(str(1073741824))
        (d / "cpu.stat").write_text("usage_usec 7200000000\nuser_usec 1\n")
        return d

    def session(self, pid, name, launcher=None, cwd=None, status="idle", start=1000):
        """A session at pid; in claude-<launcher>.scope, or in the terminal
        service when launcher is None."""
        if launcher:
            cg = f"/{USVC}/claude.slice/claude-{launcher}.scope"
            self.scope(launcher)
        else:
            cg = f"/{USVC}/app.slice/frankenterm-mux.service"
        self.proc_entry(pid, launcher or 1, cg, start)
        (self.sessions / f"{pid}.json").write_text(
            json.dumps(
                {
                    "pid": pid,
                    "name": name,
                    "status": status,
                    "cwd": cwd or "/home/x",
                    "procStart": str(start),
                }
            )
        )
        return cg

    def run(self, *args, **env):
        return subprocess.run(
            [sys.executable, TOOL, *args],
            env=self.env(**env),
            capture_output=True,
            text=True,
        )

    def freeze_file(self, launcher):
        return (
            (
                self.cg
                / USVC
                / "claude.slice"
                / f"claude-{launcher}.scope"
                / "cgroup.freeze"
            )
            .read_text()
            .strip()
        )

    def log(self):
        p = self.state / "actions.log"
        return p.read_text() if p.exists() else ""


class Tests(unittest.TestCase):
    def setUp(self):
        self.w = World()
        w = self.w
        w.session(101, "boss", launcher=100)
        w.session(201, "idler", launcher=200, status="busy")
        w.session(301, "worker", launcher=300)
        w.session(401, "laner", launcher=400, cwd=str(w.work / "lane-a/sub"))
        w.session(501, "termbound", launcher=None)
        w.session(601, "twin", launcher=600)
        w.session(701, "twin", launcher=700)
        w.session(801, "scratcher", launcher=800, cwd=str(w.work / ".scratch/eph/src"))
        w.session(811, "pinned", launcher=810, cwd=str(w.work / ".scratch/eph"))
        w.session(821, "held", launcher=820, cwd=str(w.work / ".scratch/eph-held"))
        w.session(831, "longlane", launcher=830, cwd=str(w.work / "long"))

    def tearDown(self):
        shutil.rmtree(self.w.root)

    # ---------------------------------------------------------------- class

    def test_class_by_name_lane_default(self):
        self.assertTrue(self.w.run("class", "boss").stdout.startswith("critical"))
        self.assertTrue(self.w.run("class", "idler").stdout.startswith("pausable"))
        out = self.w.run("class", "laner").stdout
        self.assertTrue(out.startswith("pausable"), out)
        self.assertIn("lane lane-a", out)
        self.assertTrue(self.w.run("class", "worker").stdout.startswith("normal"))

    def test_ephemeral_lane_rule(self):
        out = self.w.run("class", "scratcher").stdout
        self.assertTrue(out.startswith("pausable"), out)
        self.assertIn("ephemeral lane eph", out)
        # A lane without expires_at is not ephemeral.
        self.assertTrue(self.w.run("class", "longlane").stdout.startswith("normal"))
        # A session name wins over the ephemeral rule, and so does a lane tag.
        self.assertTrue(self.w.run("class", "pinned").stdout.startswith("normal"))
        self.assertTrue(self.w.run("class", "held").stdout.startswith("critical"))
        # Its builds see the class through --pid, and pause needs no --force.
        self.w.proc_entry(805, 801, f"/{USVC}/claude.slice/claude-800.scope")
        self.assertEqual(self.w.run("class", "--pid", "805").stdout.strip(), "pausable")
        self.assertEqual(self.w.run("pause", "scratcher").returncode, 0)
        self.assertEqual(self.w.freeze_file(800), "1")

    def test_ephemeral_rule_off_without_the_key(self):
        reg = REGISTRY.replace('ephemeral_lanes = "pausable"\n', "")
        (self.w.root / "sessions.toml").write_text(reg)
        out = self.w.run("class", "scratcher").stdout
        self.assertTrue(out.startswith("normal"), out)

    def test_bad_ephemeral_class_is_an_error(self):
        (self.w.root / "sessions.toml").write_text('ephemeral_lanes = "maybe"\n')
        r = self.w.run("class", "scratcher")
        self.assertEqual(r.returncode, 1)
        self.assertIn("ephemeral_lanes is 'maybe'", r.stderr)

    def test_class_by_pid_walks_ancestors(self):
        # A build process two levels under the idler session.
        self.w.proc_entry(205, 201, f"/{USVC}/claude.slice/claude-200.scope")
        self.w.proc_entry(206, 205, f"/{USVC}/claude.slice/claude-200.scope")
        self.assertEqual(self.w.run("class", "--pid", "206").stdout.strip(), "pausable")

    def test_class_by_pid_falls_back_to_scope(self):
        # Reparented to pid 1 but still in the scope of the laner session.
        self.w.proc_entry(405, 1, f"/{USVC}/claude.slice/claude-400.scope")
        self.assertEqual(self.w.run("class", "--pid", "405").stdout.strip(), "pausable")

    def test_class_by_pid_outside_any_session_is_default(self):
        self.w.proc_entry(900, 1, f"/{USVC}/app.slice/foo.service")
        self.assertEqual(self.w.run("class", "--pid", "900").stdout.strip(), "normal")

    def test_class_missing_registry_is_normal(self):
        r = self.w.run(
            "class", "boss", MACHINE_SESSION_REGISTRY=str(self.w.root / "none")
        )
        self.assertTrue(r.stdout.startswith("normal"), r.stdout)

    def test_bad_class_in_registry_is_an_error(self):
        (self.w.root / "sessions.toml").write_text('[sessions]\nboss = "urgent"\n')
        r = self.w.run("class", "boss")
        self.assertEqual(r.returncode, 1)
        self.assertIn("must be one of", r.stderr)

    def test_reused_pid_is_not_a_session(self):
        # The json says start 1000; the live process at 301 started later.
        self.w.proc_entry(
            301, 300, f"/{USVC}/claude.slice/claude-300.scope", start=5555
        )
        r = self.w.run("class", "worker")
        self.assertEqual(r.returncode, 1)
        self.assertIn("no live session", r.stderr)

    # ---------------------------------------------------------------- list

    def test_list_shows_scopes_and_terminal_sessions(self):
        r = self.w.run("list", "--json")
        rows = {(x["name"], x["pid"]): x for x in json.loads(r.stdout)}
        boss = rows[("boss", 101)]
        self.assertEqual(boss["scope"], "claude-100.scope")
        self.assertEqual(boss["class"], "critical")
        self.assertEqual(boss["mem"], 2 * 1073741824)
        self.assertEqual(boss["swap"], 1073741824)
        self.assertFalse(boss["frozen"])
        self.assertIsNone(rows[("termbound", 501)]["scope"])
        text = self.w.run("list").stdout
        self.assertIn("claude-200.scope", text)
        self.assertIn("2.0G", text)
        self.assertIn("no own scope", text)

    # ---------------------------------------------------------------- pause

    def test_pause_pausable_writes_freeze_and_logs(self):
        r = self.w.run("pause", "idler", "--reason", "test")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.w.freeze_file(200), "1")
        self.assertIn("may time out", r.stderr)
        self.assertIn("busy right now", r.stderr)
        self.assertIn("action=pause session=idler", self.w.log())
        self.assertIn('reason="test"', self.w.log())

    def test_pause_reports_frozen_when_events_say_so(self):
        d = self.w.cg / USVC / "claude.slice/claude-200.scope"
        (d / "cgroup.events").write_text("populated 1\nfrozen 1\n")
        r = self.w.run("pause", "idler")
        self.assertIn("already frozen", r.stdout)

    def test_pause_normal_refused_without_force(self):
        r = self.w.run("pause", "worker")
        self.assertEqual(r.returncode, 1)
        self.assertIn("not pausable", r.stderr)
        self.assertEqual(self.w.freeze_file(300), "0")
        self.assertIn("result=refused-class", self.w.log())

    def test_pause_normal_with_force(self):
        r = self.w.run("pause", "worker", "--force")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.w.freeze_file(300), "1")
        self.assertIn("force=1", self.w.log())

    def test_pause_critical_refused_even_with_force(self):
        r = self.w.run("pause", "boss", "--force")
        self.assertEqual(r.returncode, 1)
        self.assertIn("never paused", r.stderr)
        self.assertEqual(self.w.freeze_file(100), "0")
        self.assertIn("result=refused-critical", self.w.log())

    def test_pause_without_own_scope_refused(self):
        r = self.w.run("pause", "termbound", "--force")
        self.assertEqual(r.returncode, 1)
        self.assertIn("no scope of its own", r.stderr)

    def test_duplicate_name_needs_pid_or_scope(self):
        (self.w.root / "sessions.toml").write_text('[sessions]\ntwin = "pausable"\n')
        r = self.w.run("pause", "twin")
        self.assertEqual(r.returncode, 1)
        self.assertIn("matches 2 live sessions", r.stderr)
        self.assertEqual(self.w.run("pause", "claude-700").returncode, 0)
        self.assertEqual(self.w.freeze_file(700), "1")
        self.assertEqual(self.w.freeze_file(600), "0")
        self.assertEqual(self.w.run("pause", "601").returncode, 0)
        self.assertEqual(self.w.freeze_file(600), "1")

    def test_unknown_session(self):
        r = self.w.run("pause", "nobody")
        self.assertEqual(r.returncode, 1)
        self.assertIn("no live session", r.stderr)

    # ---------------------------------------------------------------- resume

    def test_resume_writes_zero_and_logs(self):
        self.w.run("pause", "idler")
        r = self.w.run("resume", "idler")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.w.freeze_file(200), "0")
        self.assertIn("action=resume session=idler", self.w.log())

    def test_resume_works_for_any_class(self):
        (self.w.cg / USVC / "claude.slice/claude-100.scope/cgroup.freeze").write_text(
            "1"
        )
        r = self.w.run("resume", "boss")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.w.freeze_file(100), "0")


if __name__ == "__main__":
    unittest.main()
