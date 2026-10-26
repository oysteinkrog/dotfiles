"""Tests for chrome-idle-close. They use a fake /proc and fake log text, and
never touch Chrome, KWin or the real state folder.

Run: python3 ~/.dotfiles/bin/chrome-idle-close.test.py
"""

import atexit
import importlib.machinery
import importlib.util
import os
import shutil
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

_tmp = tempfile.mkdtemp(prefix="chrome-idle-test-", dir="/var/tmp")
atexit.register(shutil.rmtree, _tmp, True)
os.environ["CHROME_IDLE_PROC"] = f"{_tmp}/proc"
os.environ["CHROME_IDLE_STATE_DIR"] = f"{_tmp}/state"
os.environ["CHROME_IDLE_MODE_FILE"] = f"{_tmp}/mode"
os.environ.pop("CHROME_IDLE_MODE", None)
os.environ["CHROME_IDLE_HB_QUEUE"] = f"{_tmp}/no-queue"
os.environ["CHROME_IDLE_HB_LOG"] = f"{_tmp}/no-log"

_path = os.environ.get("CHROME_IDLE_SCRIPT") or str(
    Path(__file__).with_name("chrome-idle-close")
)
_loader = importlib.machinery.SourceFileLoader("chrome_idle_close", _path)
_spec = importlib.util.spec_from_loader("chrome_idle_close", _loader)
assert _spec is not None
cic = importlib.util.module_from_spec(_spec)
_loader.exec_module(cic)

HOME = str(Path.home())
SCOPE = "0::/user.slice/user-1000.slice/user@1000.service/app.slice/"


def fake_proc(pid: int, cmdline: bytes, cgroup: str) -> None:
    d = Path(os.environ["CHROME_IDLE_PROC"]) / str(pid)
    d.mkdir(parents=True, exist_ok=True)
    (d / "cmdline").write_bytes(cmdline)
    (d / "cgroup").write_text(cgroup)


# Main browser process: title rewritten into one space-joined string, and
# moved into its own scope, as seen on this machine.
fake_proc(
    100,
    f"/opt/google/chrome/chrome --user-data-dir={HOME}/.config/google-chrome-personal"
    " --profile-directory=Profile 1 --class=chrome-personal\0".encode(),
    SCOPE + "app-com.google.Chrome-100.scope\n",
)
# A renderer of the personal profile, still in the service cgroup.
fake_proc(
    101,
    b"/opt/google/chrome/chrome\0--type=renderer\0",
    SCOPE + "app-chrome\\x2dpersonal@abc.service\n",
)
# Work main process with normal NUL-separated argv.
fake_proc(
    200,
    f"/opt/google/chrome/chrome\0--user-data-dir={HOME}/.config/google-chrome\0"
    "--profile-directory=Default\0--class=chrome-work\0".encode(),
    SCOPE + "app-com.google.Chrome-200.scope\n",
)
# A terminal.
fake_proc(300, b"/usr/bin/frankenterm\0", SCOPE + "app-term.scope\n")
# Headless Chrome with another data folder: not a profile.
fake_proc(
    400,
    f"/opt/google/chrome/chrome\0--user-data-dir={HOME}/.config/google-chrome-headless\0".encode(),
    SCOPE + "x.scope\n",
)


class ProfileMapping(unittest.TestCase):
    def test_main_process_by_cmdline(self):
        self.assertEqual(cic.profile_of_pid(100), "personal")
        self.assertEqual(cic.profile_of_pid(200), "work")

    def test_helper_by_cgroup(self):
        self.assertEqual(cic.profile_of_pid(101), "personal")

    def test_other_windows(self):
        self.assertIsNone(cic.profile_of_pid(300))
        self.assertIsNone(cic.profile_of_pid(400))
        self.assertIsNone(cic.profile_of_pid(-1))

    def test_class_fallback(self):
        self.assertEqual(cic.profile_of_pid(999, "chrome-work"), "work")

    def test_main_pids_skip_helpers_and_headless(self):
        self.assertEqual(cic.main_pids(), {"personal": 100, "work": 200})


def resolve(pid, wclass):
    return {100: "personal", 200: "work"}.get(pid)


class FocusTracking(unittest.TestCase):
    def test_focus_ends_at_next_event(self):
        st = {}
        cic.apply_events(st, [(1000, 100, ""), (1300, 300, "")], 2000, 0, resolve)
        self.assertEqual(st["last_focus"], {"personal": 1300})
        self.assertIsNone(st["active"]["profile"])

    def test_still_focused_counts_until_now(self):
        st = {}
        cic.apply_events(st, [(1000, 200, "")], 2000, 0, resolve)
        self.assertEqual(st["last_focus"], {"work": 2000})
        # A later run with no new events keeps moving it forward.
        cic.apply_events(st, [], 2600, 0, resolve)
        self.assertEqual(st["last_focus"], {"work": 2600})

    def test_locked_screen_stops_focus(self):
        st = {}
        cic.apply_events(st, [(1000, 100, "")], 5000, 3000, resolve)
        self.assertEqual(st["last_focus"], {"personal": 2000})

    def test_switch_between_profiles(self):
        st = {}
        ev = [(1000, 100, ""), (1100, 200, ""), (1200, 300, "")]
        cic.apply_events(st, ev, 5000, 0, resolve)
        self.assertEqual(st["last_focus"], {"personal": 1100, "work": 1200})


class Memory(unittest.TestCase):
    def test_swap_pct(self):
        mi = "MemTotal: 10 kB\nSwapTotal:     1000 kB\nSwapFree:      300 kB\n"
        self.assertAlmostEqual(cic.swap_pct(mi), 70.0)
        self.assertEqual(cic.swap_pct("SwapTotal: 0 kB\nSwapFree: 0 kB\n"), 0.0)

    @staticmethod
    def _line(t, job, decision, reason):
        stamp = datetime.fromtimestamp(t).astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")
        return f'{stamp} mode=live job={job} decision={decision} reason="{reason}: x"'

    def test_short_memory_waits_do_not_count(self):
        now = 1_800_000_000.0
        lines = [
            self._line(now - 300, "a", "wait", "memory"),
            self._line(now - 30, "a", "wait", "memory"),
            self._line(now - 100, "b", "wait", "interactive"),
        ]
        self.assertEqual(cic.hb_memory_waits(now, "\n".join(lines)), 0)

    def test_job_stuck_ten_minutes_counts(self):
        now = 1_800_000_000.0
        lines = [
            self._line(now - 900, "a", "wait", "memory"),
            self._line(now - 500, "a", "wait", "cores"),
            self._line(now - 60, "a", "wait", "swap"),
            self._line(now - 700, "b", "wait", "interactive"),
            self._line(now - 20, "b", "wait", "memory"),
        ]
        self.assertEqual(cic.hb_memory_waits(now, "\n".join(lines)), 2)

    def test_started_or_gone_quiet_does_not_count(self):
        now = 1_800_000_000.0
        lines = [
            # Waited long, then started.
            self._line(now - 900, "a", "wait", "memory"),
            self._line(now - 200, "a", "wait", "memory"),
            self._line(now - 100, "a", "start", "fits"),
            # Waited long, but no memory wait line in the last 120 s.
            self._line(now - 900, "b", "wait", "memory"),
            self._line(now - 300, "b", "wait", "memory"),
            self._line(now - 30, "b", "wait", "cores"),
            # Long wait for a reason that is not memory.
            self._line(now - 900, "c", "wait", "slice-cap"),
            self._line(now - 10, "c", "wait", "slice-cap"),
        ]
        self.assertEqual(cic.hb_memory_waits(now, "\n".join(lines)), 0)

    def test_shadow_line_counts_with_queue(self):
        now = 1_800_000_000.0
        stamp = datetime.fromtimestamp(now - 900).astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")
        line = (
            f'{stamp} mode=shadow job=a decision=wait reason="memory: 3.4 GiB '
            f'available, the first build needs 5" cap=22.0G(high) pressure=normal '
            f"actual=wait rank=1"
        )
        self.assertEqual(cic.hb_memory_waits(now, line, {"a"}), 1)
        # The shadow decision says wait, but the job really started.
        late = line.replace("actual=wait", "actual=start")
        self.assertEqual(cic.hb_memory_waits(now, late, {"a"}), 0)
        # The shadow decision says start, but the job really still waits.
        start = self._line(now - 100, "a", "start", "fits") + " actual=wait"
        self.assertEqual(cic.hb_memory_waits(now, line + "\n" + start, {"a"}), 1)

    def test_single_old_wait_line_counts_while_queued(self):
        now = 1_800_000_000.0
        text = self._line(now - 7200, "a", "wait", "memory")
        self.assertEqual(cic.hb_memory_waits(now, text, {"a", "z"}), 1)

    def test_job_no_longer_queued_does_not_count(self):
        now = 1_800_000_000.0
        text = self._line(now - 7200, "a", "wait", "memory")
        self.assertEqual(cic.hb_memory_waits(now, text, {"z"}), 0)
        self.assertEqual(cic.hb_memory_waits(now, text, set()), 0)

    def test_started_job_does_not_count_even_if_queued(self):
        now = 1_800_000_000.0
        text = "\n".join(
            [
                self._line(now - 7200, "a", "wait", "memory"),
                self._line(now - 3600, "a", "start", "fits"),
            ]
        )
        self.assertEqual(cic.hb_memory_waits(now, text, {"a"}), 0)

    def test_queue_dir_read_from_env(self):
        q = Path(_tmp) / "queue"
        q.mkdir()
        (q / "a").write_text("x")
        old = cic.HB_QUEUE_ENV
        cic.HB_QUEUE_ENV = str(q)
        try:
            self.assertEqual(cic.hb_queued_jobs(), {"a"})
        finally:
            cic.HB_QUEUE_ENV = old
        self.assertIsNone(cic.hb_queued_jobs())

    def test_log_path_picks_newest(self):
        d = Path(_tmp) / "hb"
        d.mkdir()
        (d / "live.log").write_text("x")
        (d / "shadow.log").write_text("x")
        os.utime(d / "live.log", (1, 1))
        old = (cic.HB_LOG_ENV, cic.HB_LOG_DIR)
        cic.HB_LOG_ENV, cic.HB_LOG_DIR = None, d
        try:
            self.assertEqual(cic.hb_log_path(), d / "shadow.log")
            os.utime(d / "shadow.log", (1, 1))
            os.utime(d / "live.log", (5, 5))
            self.assertEqual(cic.hb_log_path(), d / "live.log")
        finally:
            cic.HB_LOG_ENV, cic.HB_LOG_DIR = old


class Decide(unittest.TestCase):
    def test_rules(self):
        self.assertFalse(cic.decide(14.9, True, 1)[0])
        self.assertFalse(cic.decide(30, False, 1)[0])
        self.assertFalse(cic.decide(30, True, None)[0])
        self.assertFalse(cic.decide(30, True, 5)[0])
        self.assertTrue(cic.decide(15, True, 1)[0])

    def test_away_rule(self):
        # Away 60 min closes an idle profile even when memory is not tight.
        self.assertTrue(cic.decide(30, False, 1, 60, 60)[0])
        self.assertFalse(cic.decide(30, False, 1, 59, 60)[0])
        self.assertFalse(cic.decide(30, False, 1, 600, 0)[0])  # 0 = off
        self.assertFalse(cic.decide(10, False, 1, 600, 60)[0])  # focus rule still holds
        self.assertFalse(cic.decide(30, False, 5, 600, 60)[0])  # tabs would be lost

    def test_away_min_reads_presence(self):
        import json

        st = Path(_tmp) / "presence-state"
        cic.PRESENCE_STATE = st
        now = 10_000.0
        st.write_text(
            json.dumps({"state": "away", "since": now - 3900, "updated": now - 3})
        )
        self.assertAlmostEqual(cic.away_min(now), 65.0)
        st.write_text(
            json.dumps({"state": "remote", "since": now - 3900, "updated": now - 3})
        )
        self.assertEqual(cic.away_min(now), 0.0)
        st.write_text(
            json.dumps({"state": "away", "since": now - 3900, "updated": now - 300})
        )
        self.assertEqual(cic.away_min(now), 0.0)  # stale state counts as not away
        st.unlink()
        self.assertEqual(cic.away_min(now), 0.0)
        conf = Path(_tmp) / "presence.conf"
        cic.PRESENCE_CONF = conf
        self.assertEqual(cic.away_limit_min(), 60.0)
        conf.write_text("fooyin_quit=1\nchrome_away_min=0  # off\n")
        self.assertEqual(cic.away_limit_min(), 0.0)

    def test_mode_defaults_to_dry_run(self):
        self.assertEqual(cic.resolve_mode(None), "dry-run")
        Path(os.environ["CHROME_IDLE_MODE_FILE"]).write_text("live\n")
        self.assertEqual(cic.resolve_mode(None), "live")
        self.assertEqual(cic.resolve_mode("dry-run"), "dry-run")
        Path(os.environ["CHROME_IDLE_MODE_FILE"]).unlink()


if __name__ == "__main__":
    unittest.main()
