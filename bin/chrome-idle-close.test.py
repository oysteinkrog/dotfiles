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
os.environ["CHROME_IDLE_JOBD_LOG"] = f"{_tmp}/no-log"
os.environ["CHROME_IDLE_JOB_QUEUE_CMD"] = "false"

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
    "--profile-directory=Profile 1\0--class=chrome-work\0".encode(),
    SCOPE + "app-com.google.Chrome-200.scope\n",
)
# Default Chrome: no --user-data-dir and no --class, a URL before any flag,
# title rewritten into one string.
fake_proc(
    500,
    b"/opt/google/chrome/chrome https://claude.ai/artifact/x\0",
    SCOPE + "app-com.google.Chrome-500.scope\n",
)
# A renderer of the default Chrome, in its service cgroup.
fake_proc(
    501,
    b"/opt/google/chrome/chrome\0--type=renderer\0",
    SCOPE + "app-com.google.Chrome@16ac.service\n",
)
# A helper of the shared data folder in no named cgroup: unknown by itself.
fake_proc(
    502,
    b"/opt/google/chrome/chrome\0--type=utility\0",
    SCOPE + "app-com.google.Chrome-500.scope\n",
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
        self.assertEqual(cic.profile_of_pid(501), "default")

    def test_default_profile(self):
        self.assertEqual(cic.profile_of_pid(500), "default")
        self.assertIsNone(cic.profile_of_pid(502))
        self.assertEqual(cic.profile_of_pid(999, "google-chrome"), "default")
        self.assertEqual(
            cic.read_cmdline(500),
            ["/opt/google/chrome/chrome", "https://claude.ai/artifact/x"],
        )

    def test_default_restore_reads_open_profiles(self):
        import json

        d = Path(_tmp) / "gc"
        for name, val in (("Default", 4), ("Profile 1", 1)):
            (d / name).mkdir(parents=True)
            (d / name / "Preferences").write_text(
                json.dumps({"session": {"restore_on_startup": val}})
            )
        old = (cic.PROFILES["default"]["data_dir"], cic.POLICY_DIR)
        cic.PROFILES["default"]["data_dir"] = str(d)
        cic.POLICY_DIR = Path(_tmp) / "no-policy"
        try:
            # No Local State: Chrome opens Default.
            self.assertEqual(cic.restore_setting("default"), 4)
            (d / "Local State").write_text(
                json.dumps({"profile": {"last_used": "Profile 1"}})
            )
            self.assertEqual(cic.restore_setting("default"), 1)
            (d / "Local State").write_text(
                json.dumps(
                    {"profile": {"last_active_profiles": ["Profile 1", "Default"]}}
                )
            )
            self.assertEqual(cic.restore_setting("default"), 4)
            pol = Path(_tmp) / "policy"
            pol.mkdir()
            (pol / "r.json").write_text('{"RestoreOnStartup": 1}')
            cic.POLICY_DIR = pol
            self.assertEqual(cic.restore_setting("default"), 1)
        finally:
            cic.PROFILES["default"]["data_dir"], cic.POLICY_DIR = old

    def test_other_windows(self):
        self.assertIsNone(cic.profile_of_pid(300))
        self.assertIsNone(cic.profile_of_pid(400))
        self.assertIsNone(cic.profile_of_pid(-1))

    def test_class_fallback(self):
        self.assertEqual(cic.profile_of_pid(999, "chrome-work"), "work")

    def test_main_pids_skip_helpers_and_headless(self):
        self.assertEqual(
            cic.main_pids(), {"personal": 100, "work": 200, "default": 500}
        )


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
        return f'{stamp} mode=live job={job} decision={decision} reason="{reason}" cap=20.0G'

    MEM = "memory: needs 4.8 GiB, charged 50%; 5.2 available; not interactive: x"
    PRESS = (
        "pressure: memory controller, 3.1 GiB free, one new build per 60 s; "
        "the last one started 20 s ago"
    )
    INTER = "interactive: claude.slice memory pressure (full) 12%, the limit is 10%"
    KEY = "key: cargo:/var/tmp/x is held by 17-1-ab"
    STARVE = "starve: 17-1-ab has waited 12 min, so nothing may pass it"
    BEHIND = "behind: its run time is not known; not interactive: mem estimate 4.8G over 2G"
    GPU = "gpu: needs 6 GiB VRAM free, 2 free"
    CORES = "cores: needs 8, 4 free"

    def test_memory_reasons(self):
        for r in (self.MEM, self.PRESS, self.INTER):
            self.assertTrue(cic.is_memory_reason(r), r)
        for r in (self.KEY, self.STARVE, self.BEHIND, self.GPU, self.CORES):
            self.assertFalse(cic.is_memory_reason(r), r)

    def test_short_memory_waits_do_not_count(self):
        now = 1_800_000_000.0
        lines = [
            self._line(now - 300, "a", "wait", self.MEM),
            self._line(now - 30, "a", "wait", self.MEM),
            self._line(now - 100, "b", "wait", self.PRESS),
        ]
        self.assertEqual(cic.hb_memory_waits(now, "\n".join(lines), {"a", "b"}), 0)

    def test_job_stuck_ten_minutes_counts(self):
        now = 1_800_000_000.0
        lines = [
            self._line(now - 900, "a", "wait", self.MEM),
            self._line(now - 500, "a", "wait", self.PRESS),
            self._line(now - 60, "a", "wait", self.MEM),
            self._line(now - 700, "b", "wait", self.INTER),
            self._line(now - 20, "b", "wait", self.MEM),
        ]
        self.assertEqual(cic.hb_memory_waits(now, "\n".join(lines), {"a", "b"}), 2)

    def test_single_old_wait_line_counts_while_waiting(self):
        now = 1_800_000_000.0
        text = self._line(now - 7200, "a", "wait", self.MEM)
        self.assertEqual(cic.hb_memory_waits(now, text, {"a", "z"}), 1)

    def test_other_wait_reasons_do_not_count(self):
        now = 1_800_000_000.0
        lines = []
        for job, r in (("k", self.KEY), ("s", self.STARVE), ("b", self.BEHIND),
                       ("g", self.GPU), ("c", self.CORES)):
            lines.append(self._line(now - 900, job, "wait", r))
            lines.append(self._line(now - 10, job, "wait", r))
        # Waited for memory long ago, but now waits for a lock key.
        lines.append(self._line(now - 900, "m", "wait", self.MEM))
        lines.append(self._line(now - 30, "m", "wait", self.KEY))
        waiting = {"k", "s", "b", "g", "c", "m"}
        self.assertEqual(cic.hb_memory_waits(now, "\n".join(lines), waiting), 0)

    def test_started_job_does_not_count(self):
        now = 1_800_000_000.0
        lines = [
            self._line(now - 7200, "a", "wait", self.MEM),
            self._line(now - 3600, "a", "start", "fits: x"),
        ]
        self.assertEqual(cic.hb_memory_waits(now, "\n".join(lines), {"a"}), 0)
        # A new memory wait after the start counts from that wait.
        lines.append(self._line(now - 300, "a", "wait", self.MEM))
        self.assertEqual(cic.hb_memory_waits(now, "\n".join(lines), {"a"}), 0)
        lines.append(self._line(now - 100, "a", "wait", self.MEM))
        self.assertEqual(cic.hb_memory_waits(now - 300 + 700, "\n".join(lines), {"a"}), 1)

    def test_job_no_longer_waiting_does_not_count(self):
        now = 1_800_000_000.0
        text = self._line(now - 7200, "a", "wait", self.MEM)
        self.assertEqual(cic.hb_memory_waits(now, text, {"z"}), 0)
        self.assertEqual(cic.hb_memory_waits(now, text, set()), 0)

    def test_queue_failure_falls_back_to_recent_line(self):
        now = 1_800_000_000.0
        lines = [
            self._line(now - 900, "a", "wait", self.MEM),
            self._line(now - 60, "a", "wait", self.MEM),
            self._line(now - 900, "b", "wait", self.MEM),
            self._line(now - 300, "b", "wait", self.MEM),
        ]
        # JOB_QUEUE_CMD is "false" in these tests, so the queue is unknown.
        self.assertIsNone(cic.job_queue_waiting())
        self.assertEqual(cic.hb_memory_waits(now, "\n".join(lines)), 1)

    def test_job_queue_parsed(self):
        q = Path(_tmp) / "queue.json"
        q.write_text(
            '{"jobs": [{"id": "a", "state": "waiting"}, '
            '{"id": "b", "state": "running"}], "maxjobs": 6}'
        )
        old = cic.JOB_QUEUE_CMD
        cic.JOB_QUEUE_CMD = ["cat", str(q)]
        try:
            self.assertEqual(cic.job_queue_waiting(), {"a"})
        finally:
            cic.JOB_QUEUE_CMD = old

    def test_reads_only_the_log_tail(self):
        now = 1_800_000_000.0
        log = Path(_tmp) / "live.log"
        old = (cic.JOBD_LOG, cic.HB_TAIL_BYTES)
        line = self._line(now - 900, "a", "wait", self.MEM)
        log.write_text(("x" * 100 + "\n") * 50 + line + "\n")
        cic.JOBD_LOG, cic.HB_TAIL_BYTES = log, len(line) + 50
        try:
            tail = cic.read_jobd_tail()
            self.assertEqual(tail.strip(), line)
            self.assertEqual(cic.hb_memory_waits(now, None, {"a"}), 1)
        finally:
            cic.JOBD_LOG, cic.HB_TAIL_BYTES = old


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
