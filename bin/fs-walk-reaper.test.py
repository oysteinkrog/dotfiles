"""Tests for fs-walk-reaper with a fake /proc. Run: python3 fs-walk-reaper.test.py"""

import importlib.machinery
import importlib.util
import os
import re
import tempfile
import unittest
from unittest import mock
from pathlib import Path

BIN = Path(__file__).resolve().parent / "fs-walk-reaper"
loader = importlib.machinery.SourceFileLoader("fs_walk_reaper", str(BIN))
spec = importlib.util.spec_from_loader("fs_walk_reaper", loader)
assert spec is not None
reaper = importlib.util.module_from_spec(spec)
loader.exec_module(reaper)
detector = reaper.load_detector()

HOME = str(Path.home())
CLK = 100
UPTIME = 1000.0
UID = os.getuid()


def make_proc(root: Path, pid: int, argv: list[str], cwd: str, age: float, **kw):
    """Fake /proc/PID. Age is seconds since the process started."""
    d = root / str(pid)
    (d / "fd").mkdir(parents=True)
    (d / "cmdline").write_bytes(b"\0".join(a.encode() for a in argv) + b"\0")
    ticks = int((UPTIME - age) * CLK)
    # pid (comm) state ppid ... starttime is the 22nd field overall.
    fields = ["S"] + ["0"] * 18 + [str(ticks)] + ["0"] * 10
    (d / "stat").write_text(f"{pid} (x y) " + " ".join(fields) + "\n")
    os.symlink(cwd, d / "cwd")
    os.symlink(kw.get("fd0", "/dev/null"), d / "fd/0")
    scope = kw.get("scope")
    cg = "0::/user.slice/claude.slice/" + (
        f"claude-{scope}.scope" if scope else "x.service"
    )
    (d / "cgroup").write_text(cg + "\n")
    if "hbs" in kw:
        (d / "environ").write_bytes(f"A=b\0HEAVY_BUILD_SESSION={kw['hbs']}\0".encode())


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.proc = Path(self.tmp.name)
        (self.proc / "uptime").write_text(f"{UPTIME} 5000.0\n")

    def tearDown(self):
        self.tmp.cleanup()

    def cands(self, allow=(), grace=20.0):
        return reaper.candidates(
            self.proc, detector, list(allow), UID, CLK, grace, os.getpid()
        )


class ClassifyTests(unittest.TestCase):
    def test_broad_walks(self):
        cases = [
            (["find", "/", "-name", "x"], "/var/tmp/claude", "/"),
            (["bfs", "-S", "dfs", "/", "-iname", "*x*"], HOME, "/"),
            (["ugrep", "-r", "foo"], "/var/tmp/claude", "/var/tmp/claude"),
            (["rg", "foo"], HOME, HOME),
            (["rg", "foo", "/var"], HOME + "/work", "/var"),
            (["du", "-sh", "/home"], HOME, "/home"),
            (["ls", "-R", "~"], "/", HOME),
            (["grep", "-rn", "x"], "/home", "/home"),
            (["fd", "plan", "/var/tmp"], HOME, "/var/tmp"),
            (["tree", "/"], HOME, "/"),
            (["/usr/bin/find", "/var", "-type", "f"], HOME, "/var"),
        ]
        for argv, cwd, want in cases:
            with self.subTest(argv=argv):
                self.assertEqual(reaper.classify(detector, argv, cwd, False, []), want)

    def test_narrow_or_other_is_left_alone(self):
        cases = [
            (["find", "/etc", "-name", "x"], HOME),
            (["find", "/", "-maxdepth", "2"], HOME),
            (["rg", "foo", HOME + "/work/ifkb"], HOME),
            (["rg", "foo"], HOME + "/work/ifkb"),
            (["ls", "/"], HOME),
            (["cargo", "build"], HOME),
            (["bash", "-c", "find / -name x"], HOME),
            (["rgg", "x"], HOME),
            (["btrfs", "filesystem", "du", "/"], HOME),
        ]
        for argv, cwd in cases:
            with self.subTest(argv=argv):
                self.assertIsNone(reaper.classify(detector, argv, cwd, False, []))

    def test_stdin_pipe_ugrep_is_not_a_walk(self):
        argv = ["ugrep", "foo"]
        self.assertIsNone(reaper.classify(detector, argv, HOME, True, []))
        self.assertEqual(reaper.classify(detector, argv, HOME, False, []), HOME)

    def test_noqa_in_cmdline(self):
        argv = ["find", "/", "-name", "x", "#", "noqa:", "fs-walk"]
        self.assertIsNone(reaper.classify(detector, argv, HOME, False, []))

    def test_allow_regex(self):
        argv = ["find", "/", "-name", "needle"]
        allow = [re.compile(r"-name needle")]
        self.assertIsNone(reaper.classify(detector, argv, HOME, False, allow))
        other = [re.compile(r"zzz")]
        self.assertEqual(reaper.classify(detector, argv, HOME, False, other), "/")


class AllowFileTests(unittest.TestCase):
    def test_comments_blanks_and_bad_regex(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / "allow"
            p.write_text("# note\n\nfoo.*bar\n([unclosed\n")
            pats = reaper.compile_allow(p)
            self.assertEqual([x.pattern for x in pats], ["foo.*bar"])
        self.assertEqual(reaper.compile_allow(Path("/nonexistent/allow")), [])


class FakeProcTests(Base):
    def test_old_walk_found_with_owner(self):
        make_proc(
            self.proc, 4242, ["find", "/", "-name", "x"], HOME, 60.0,
            scope=1111, hbs="sess-a",
        )  # fmt: skip
        got = self.cands()
        self.assertEqual(len(got), 1)
        c = got[0]
        self.assertEqual(
            (c["pid"], c["scope"], c["hbs"], c["root"]), (4242, "1111", "sess-a", "/")
        )
        self.assertAlmostEqual(c["age"], 60.0, delta=0.1)
        line = reaper.log_line(c, "stopped(term)")
        self.assertIn("pid=4242 session=claude-1111 hbs=sess-a", line)
        self.assertIn(f"cwd={HOME}", line)

    def test_age_grace(self):
        make_proc(self.proc, 10, ["find", "/", "-name", "x"], HOME, 19.0)
        make_proc(self.proc, 11, ["find", "/", "-name", "x"], HOME, 21.0)
        pids = [c["pid"] for c in self.cands()]
        self.assertEqual(pids, [11])
        self.assertEqual(sorted(c["pid"] for c in self.cands(grace=5.0)), [10, 11])

    def test_comm_with_parentheses_does_not_break_age(self):
        make_proc(self.proc, 12, ["du", "-s", "/"], HOME, 30.0)
        (self.proc / "12/stat").write_text(
            "12 (a) b (c) "
            + " ".join(
                ["S"] + ["0"] * 18 + [str(int((UPTIME - 30) * CLK))] + ["0"] * 10
            )
            + "\n"
        )
        self.assertEqual([c["pid"] for c in self.cands()], [12])

    def test_zombie_and_non_search_skipped(self):
        make_proc(self.proc, 20, ["find", "/"], HOME, 99.0)
        text = (self.proc / "20/stat").read_text().replace(" S ", " Z ", 1)
        (self.proc / "20/stat").write_text(text)
        make_proc(self.proc, 21, ["cargo", "build"], "/", 99.0)
        make_proc(self.proc, 22, ["rg", "x", HOME + "/work/a"], "/", 99.0)
        self.assertEqual(self.cands(), [])

    def test_no_claude_scope(self):
        make_proc(self.proc, 30, ["find", "/"], HOME, 99.0)
        self.assertEqual(self.cands()[0]["scope"], "-")
        self.assertEqual(self.cands()[0]["hbs"], "-")

    def test_command_cut_to_200(self):
        make_proc(self.proc, 31, ["find", "/", "-name", "x" * 500], HOME, 99.0)
        self.assertEqual(len(self.cands()[0]["cmd"]), reaper.CMD_MAX)

    def test_dry_run_logs_once_and_signals_nothing(self):
        make_proc(self.proc, 40, ["find", "/"], HOME, 99.0, scope=7)
        state = self.proc / "state"
        seen: set = set()
        with mock.patch("os.kill") as kill:
            reaper.scan_once(self.proc, detector, seen, True, state)
            reaper.scan_once(self.proc, detector, seen, True, state)
        kill.assert_not_called()
        lines = (state / "log").read_text().splitlines()
        self.assertEqual(len(lines), 1)
        self.assertIn("DRY-RUN would-stop pid=40", lines[0])
        self.assertFalse((state / "notice").exists())

    def test_live_term_then_kill_and_notice(self):
        make_proc(self.proc, 41, ["find", "/"], HOME, 99.0, scope=7)
        state = self.proc / "state"
        with (
            mock.patch("os.kill") as kill,
            mock.patch.object(reaper, "KILL_AFTER", 0),
        ):
            reaper.scan_once(self.proc, detector, set(), False, state)
        # The fake process is still there after SIGTERM, so SIGKILL follows.
        self.assertEqual([c.args for c in kill.call_args_list], [(41, 15), (41, 9)])
        self.assertIn("stopped(term+kill) pid=41", (state / "log").read_text())
        note = (state / "notice/7").read_text()
        self.assertIn("search over / was stopped", note)
        self.assertIn("narrower folder", note)

    def test_no_kill_when_process_exited_after_term(self):
        make_proc(self.proc, 42, ["find", "/"], HOME, 99.0)
        c = self.cands()[0]

        def gone(_: float) -> None:
            (self.proc / "42/stat").unlink()

        with mock.patch("os.kill") as kill:
            result = reaper.stop(self.proc, c, 5, gone)
        self.assertEqual(result, "term")
        self.assertEqual([x.args for x in kill.call_args_list], [(42, 15)])


if __name__ == "__main__":
    unittest.main()
