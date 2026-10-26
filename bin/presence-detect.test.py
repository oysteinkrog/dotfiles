"""Tests for presence-detect. Fake clock and fake signals; never calls systemctl,
D-Bus or fooyin, and never touches the real state folder.

Run: python3 ~/.dotfiles/bin/presence-detect.test.py
"""

import atexit
import importlib.machinery
import importlib.util
import os
import shutil
import tempfile
import unittest
from pathlib import Path

_tmp = tempfile.mkdtemp(prefix="presence-test-", dir="/var/tmp")
atexit.register(shutil.rmtree, _tmp, True)
os.environ["PRESENCE_STATE_DIR"] = f"{_tmp}/state"
os.environ["PRESENCE_CONF"] = f"{_tmp}/presence.conf"

_path = str(Path(__file__).with_name("presence-detect"))
_loader = importlib.machinery.SourceFileLoader("presence_detect", _path)
_spec = importlib.util.spec_from_loader("presence_detect", _loader)
assert _spec is not None
pd = importlib.util.module_from_spec(_spec)
_loader.exec_module(pd)


def sig(li=None, clients=None, locked=False, locked_s=0.0):
    return {
        "local_input_age_s": li,
        "rdp_clients": clients or [],
        "locked": locked,
        "locked_s": locked_s,
        "lock_source": "test",
    }


class StateModel(unittest.TestCase):
    def test_day(self):
        t = 1_000_000.0
        rec = pd.step(t, sig(li=5), {})
        self.assertEqual(rec["state"], "here")
        self.assertNotIn("not_here_since", rec)
        # Locked 9 min: still here.
        rec = pd.step(t + 540, sig(li=540, locked=True, locked_s=540), rec)
        self.assertEqual(rec["state"], "here")
        # Locked 10 min: away reading, but it must hold 5 more min.
        rec = pd.step(t + 600, sig(li=600, locked=True, locked_s=600), rec)
        self.assertEqual(rec["state"], "here")
        self.assertIn("pending", rec)
        rec = pd.step(t + 900, sig(li=900, locked=True, locked_s=900), rec)
        self.assertEqual(rec["state"], "away")
        self.assertEqual(rec["since"], t + 900)
        # RDP connects: remote after 10 s.
        rec = pd.step(
            t + 1000, sig(li=1000, clients=["c"], locked=True, locked_s=1000), rec
        )
        self.assertEqual(rec["state"], "away")
        rec = pd.step(t + 1011, sig(li=1011, clients=["c"], locked=False), rec)
        self.assertEqual(rec["state"], "remote")
        # Client gone 1 min: still remote; 8 min after drop: away (held 5 min).
        rec = pd.step(t + 1071, sig(li=1071), rec)
        self.assertEqual(rec["state"], "remote")
        rec = pd.step(t + 1251, sig(li=1251), rec)
        self.assertEqual(rec["state"], "remote")
        rec = pd.step(t + 1551, sig(li=1551), rec)
        self.assertEqual(rec["state"], "away")
        # Key press at the office: here at once.
        rec = pd.step(t + 1600, sig(li=1), rec)
        self.assertEqual(rec["state"], "here")
        self.assertNotIn("not_here_since", rec)

    def test_office_key_beats_rdp(self):
        t = 2_000_000.0
        rec = pd.step(t, sig(li=3000, clients=["c"]), {})
        self.assertEqual(rec["state"], "remote")
        self.assertEqual(rec["not_here_since"], t)
        rec = pd.step(t + 5, sig(li=90, clients=["c"]), rec)
        self.assertEqual(rec["state"], "remote")  # 90 s: older than the 60 s takeover
        rec = pd.step(t + 10, sig(li=2, clients=["c"]), rec)
        self.assertEqual(rec["state"], "here")

    def test_not_here_since_spans_remote_and_away(self):
        t = 3_000_000.0
        rec = pd.step(t, sig(li=3000, clients=["c"]), {})
        rec = pd.step(
            t + 2000, sig(li=5000, clients=["c"], locked=True, locked_s=1900), rec
        )
        rec = pd.step(
            t + 2300, sig(li=5300, clients=["c"], locked=True, locked_s=2200), rec
        )
        self.assertEqual(rec["state"], "away")
        self.assertEqual(rec["not_here_since"], t)


class MissingSignals(unittest.TestCase):
    """A machine without local-input-watch, without KRDP or without a lock reading
    must never read away only because that signal is missing."""

    def test_no_local_input_file_unlocked_is_here_for_hours(self):
        t = 4_000_000.0
        rec = pd.step(t, sig(li=None), {})
        self.assertEqual(rec["state"], "here")
        for dt in (600, 3600, 4 * 3600, 24 * 3600):
            rec = pd.step(t + dt, sig(li=None), rec)
            self.assertEqual(rec["state"], "here", dt)

    def test_no_local_input_file_after_rdp_left(self):
        t = 5_000_000.0
        rec = pd.step(t, sig(li=None, clients=["c"]), {})
        self.assertEqual(rec["state"], "remote")
        rec = pd.step(t + 60, sig(li=None), rec)  # client gone, may reconnect
        for dt in (600, 1200, 3600):
            rec = pd.step(t + dt, sig(li=None), rec)
            self.assertNotEqual(rec["state"], "away", dt)

    def test_stale_rdp_record_after_reboot_without_input_file(self):
        t = 6_000_000.0
        prev = {"state": "here", "rdp_last_seen": t - 7 * 86400, "updated": t - 86400}
        for dt in (0, 600, 1200):
            prev = pd.step(t + dt, sig(li=None), prev)
            self.assertEqual(prev["state"], "here", dt)

    def test_no_ss_and_no_lock_source(self):
        t = 7_000_000.0
        s = sig(li=None)
        s["rdp_clients"] = None  # ss missing or failed
        s["lock_source"] = "none"
        rec = pd.step(t, s, {})
        rec = pd.step(t + 3 * 3600, s, rec)
        self.assertEqual(rec["state"], "here")

    def test_missing_input_file_reads_as_none(self):
        orig = pd.LOCAL_INPUT
        pd.LOCAL_INPUT = Path(_tmp) / "no-such-dir" / "last"
        try:
            self.assertIsNone(pd.last_local_input())
        finally:
            pd.LOCAL_INPUT = orig

    def test_locked_long_is_still_away_without_input_file(self):
        t = 8_000_000.0
        rec = pd.step(t, sig(li=None, locked=True, locked_s=600), {})
        self.assertEqual(rec["state"], "away")


class UnknownStateNoBoost(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.orig = (pd.set_cpu_weight, pd.signals)
        pd.set_cpu_weight = lambda w: self.calls.append(w) or True

    def tearDown(self):
        pd.set_cpu_weight, pd.signals = self.orig
        try:
            pd.OVERRIDE.unlink()
        except FileNotFoundError:
            pass

    def test_want_boost_only_for_away(self):
        conf = {"build_boost": "1"}
        self.assertFalse(pd.want_boost({}, conf))
        self.assertFalse(pd.want_boost({"state": None}, conf))
        self.assertFalse(pd.want_boost({"state": "here"}, conf))
        self.assertFalse(pd.want_boost({"state": "remote"}, conf))
        self.assertTrue(pd.want_boost({"state": "away"}, conf))
        self.assertFalse(pd.want_boost({"state": "away"}, {"build_boost": "0"}))

    def test_failed_check_turns_boost_off(self):
        b = pd.Boost({})
        b.apply(True, 100.0, "away")
        self.assertTrue(pd.OVERRIDE.exists())

        def broken(now):
            raise RuntimeError("signal read failed")

        pd.signals = broken
        fy = pd.Fooyin()
        rec = pd.check(110.0, {"state": "away", "boost": True}, b, fy)
        self.assertFalse(b.active)
        self.assertFalse(rec["boost"])
        self.assertFalse(pd.OVERRIDE.exists())
        self.assertEqual(self.calls, [100, 20])

    def test_first_check_with_no_state_file_and_no_signals(self):
        pd.signals = lambda now: sig(li=None)
        orig_fp = pd.fooyin_players
        pd.fooyin_players = lambda: {}
        try:
            b = pd.Boost({})
            rec = pd.check(200.0, {}, b, pd.Fooyin())
        finally:
            pd.fooyin_players = orig_fp
        self.assertEqual(rec["state"], "here")
        self.assertFalse(b.active)
        self.assertFalse(pd.OVERRIDE.exists())
        self.assertEqual(self.calls, [])


class FooyinConfig(unittest.TestCase):
    def test_flip_existing(self):
        text = "[General]\nA=1\n\n[Player]\nPlayMode=0\nSavePlaybackState=false\n\n[Z]\nB=2\n"
        out = pd.set_save_playback_state(text)
        self.assertIn("[Player]\nPlayMode=0\nSavePlaybackState=true\n", out)
        self.assertIn("[Z]\nB=2", out)

    def test_other_section_untouched(self):
        text = "[Other]\nSavePlaybackState=false\n[Player]\nPlayMode=0\n"
        out = pd.set_save_playback_state(text)
        self.assertIn("[Other]\nSavePlaybackState=false", out)
        self.assertIn("[Player]\nSavePlaybackState=true\nPlayMode=0", out)

    def test_no_player_section(self):
        out = pd.set_save_playback_state("[General]\nA=1\n")
        self.assertTrue(out.endswith("[Player]\nSavePlaybackState=true\n"))

    def test_save_state_skips_running(self):
        a = Path(_tmp) / "a.conf"
        b = Path(_tmp) / "b.conf"
        for p in (a, b):
            p.write_text("[Player]\nSavePlaybackState=false\n")
        orig = pd.running_fooyin_configs
        pd.running_fooyin_configs = lambda: {b}
        try:
            pd.fooyin_save_state([a, b])
        finally:
            pd.running_fooyin_configs = orig
        self.assertIn("SavePlaybackState=true", a.read_text())
        self.assertIn("SavePlaybackState=false", b.read_text())


class Boost(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.orig = pd.set_cpu_weight
        pd.set_cpu_weight = lambda w: self.calls.append(w) or True

    def tearDown(self):
        pd.set_cpu_weight = self.orig

    def test_on_off(self):
        b = pd.Boost({})
        b.apply(False, 100.0, "here")
        self.assertEqual(self.calls, [])  # nothing to undo
        b.apply(True, 100.0, "away")
        self.assertEqual(self.calls, [100])
        text = pd.OVERRIDE.read_text()
        self.assertIn("HEAVY_BUILD_MAX_JOBS=11", text)
        self.assertIn("HEAVY_BUILD_CPU_BUDGET=32", text)
        self.assertIn("expires=220", text)
        b.apply(True, 140.0, "away")
        self.assertEqual(self.calls, [100])  # weight set once
        self.assertIn("expires=260", pd.OVERRIDE.read_text())  # refreshed after 30 s
        b.apply(False, 150.0, "here")
        self.assertEqual(self.calls, [100, 20])
        self.assertFalse(pd.OVERRIDE.exists())

    def test_restart_undoes_left_boost(self):
        b = pd.Boost({"boost": True})
        b.apply(False, 1.0, "start, here")
        self.assertEqual(self.calls, [20])

    def test_restart_while_away_sets_weight_again(self):
        b = pd.Boost({"boost": True})
        b.apply(True, 1.0, "start, away")
        self.assertEqual(self.calls, [100])

    def test_failed_weight_change_is_retried(self):
        results = [False, False, True]
        pd.set_cpu_weight = lambda w: self.calls.append(w) or results.pop(0)
        b = pd.Boost({"boost": True})
        b.apply(False, 1.0, "here")
        b.apply(False, 6.0, "here")
        b.apply(False, 11.0, "here")
        b.apply(False, 16.0, "here")
        self.assertEqual(self.calls, [20, 20, 20])


class FooyinRule(unittest.TestCase):
    def setUp(self):
        self.players = {"org.mpris.MediaPlayer2.fooyin": {"status": "Paused", "pid": 0}}
        self.quits = []
        self.orig = (pd.fooyin_players, pd.run, pd.fooyin_save_state)
        pd.fooyin_players = lambda: self.players
        pd.run = lambda *cmd, **kw: self.quits.append(cmd) or ""
        pd.fooyin_save_state = lambda *a: None

    def tearDown(self):
        pd.fooyin_players, pd.run, pd.fooyin_save_state = self.orig

    def test_quit_after_30_min(self):
        fy = pd.Fooyin()
        rec = {"state": "remote", "not_here_since": 0.0}
        fy.tick(0.0, rec, True)
        fy.tick(1799.0, rec, True)
        self.assertEqual(self.quits, [])
        fy.tick(1800.0, rec, True)
        self.assertEqual(len(self.quits), 1)
        self.assertEqual(self.quits[0][-1], "Quit")

    def test_never_while_playing_or_here_or_off(self):
        fy = pd.Fooyin()
        self.players["org.mpris.MediaPlayer2.fooyin"]["status"] = "Playing"
        fy.tick(0.0, {"state": "away", "not_here_since": 0.0}, True)
        fy.tick(9000.0, {"state": "away", "not_here_since": 0.0}, True)
        self.assertEqual(self.quits, [])
        self.players["org.mpris.MediaPlayer2.fooyin"]["status"] = "Paused"
        fy.tick(9001.0, {"state": "away", "not_here_since": 0.0}, True)
        fy.tick(9000.0 + 1799, {"state": "away", "not_here_since": 0.0}, True)
        self.assertEqual(self.quits, [])  # paused only 30 min minus 2 s
        fy.tick(20000.0, {"state": "here"}, True)
        fy.tick(20000.0, {"state": "away", "not_here_since": 0.0}, False)
        self.assertEqual(self.quits, [])


if __name__ == "__main__":
    unittest.main()
