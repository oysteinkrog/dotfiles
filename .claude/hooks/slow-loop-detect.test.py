#!/usr/bin/env python3
"""Tests for slow-loop-detect.py. Run: python3 slow-loop-detect.test.py"""

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load():
    spec = importlib.util.spec_from_file_location("sld", HERE / "slow-loop-detect.py")
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def transcript(path: Path, replies: list[str]) -> None:
    with path.open("w") as fh:
        for r in replies:
            fh.write(
                json.dumps(
                    {"type": "user", "message": {"content": "stop hook feedback"}}
                )
                + "\n"
            )
            fh.write(
                json.dumps(
                    {
                        "type": "assistant",
                        "message": {"content": [{"type": "text", "text": r}]},
                    }
                )
                + "\n"
            )


class SlowLoopDetect(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        from unittest import mock

        env = mock.patch.dict(
            os.environ, {"SLOW_LOOP_STATE_DIR": self.tmp.name + "/state"}
        )
        env.start()
        self.addCleanup(env.stop)
        self.m = load()
        self.t = Path(self.tmp.name) / "t.jsonl"

    def tearDown(self):
        self.tmp.cleanup()

    def run_decide(self, replies, now=1_000_000.0, sid="s1"):
        """Feed the replies one stop at a time; return the first reason that fired."""
        out = None
        for i, r in enumerate(replies):
            transcript(self.t, [r])
            texts = self.m.assistant_texts(self.t)
            reason = self.m.decide(texts[-1] if texts else None, sid, now + 120 * i)
            out = out or reason
        return out

    def run_main(self, event):
        import io

        sys.stdin = io.StringIO(json.dumps(event))
        buf = io.StringIO()
        old, sys.stdout = sys.stdout, buf
        try:
            self.assertEqual(self.m.main(), 0)
        finally:
            sys.stdout, sys.stdin = old, sys.__stdin__
        return buf.getvalue()

    def test_fires_on_idle_streak(self):
        self.assertIsNotNone(self.run_decide(["Waiting for plan 31 at 20:28."] * 6))

    def test_quiet_when_working(self):
        work = "I re-ran the test: 33 of 33 pass. Next I build the A/B pair and check the DLLs."
        self.assertIsNone(self.run_decide([work] * 6))

    def test_needs_full_window(self):
        self.assertIsNone(self.run_decide(["Still waiting."] * 4))

    def test_work_resets_streak(self):
        replies = (
            ["Waiting for X."] * 4
            + ["Fixed the build and pushed it."]
            + ["Waiting for X."] * 4
        )
        self.assertIsNone(self.run_decide(replies))

    def test_long_reply_is_not_idle(self):
        long = "Waiting for plan 31. " + "Detail. " * 80
        self.assertIsNone(self.run_decide([long] * 6))

    def test_mixed_below_threshold(self):
        replies = ["Waiting for X."] * 3 + [
            "Fixed the build error and pushed the lane commit."
        ] * 2
        self.assertIsNone(self.run_decide(replies))

    def test_cooldown(self):
        idle = ["Nothing new has finished at this check."] * 5
        self.assertIsNotNone(self.run_decide(idle, now=1_000_000.0))
        self.assertIsNone(self.run_decide(idle, now=1_000_000.0 + 3600))
        self.assertIsNotNone(self.run_decide(idle, now=1_000_000.0 + 7 * 3600))

    def test_sessions_are_separate(self):
        idle = ["Still waiting for the lab."] * 6
        self.assertIsNotNone(self.run_decide(idle, sid="a"))
        self.assertIsNotNone(self.run_decide(idle, sid="b"))

    def test_same_stop_seen_twice_counts_once(self):
        # A user hook and a repository hook both run on one stop.
        for i in range(4):
            for _ in range(2):
                self.assertIsNone(
                    self.m.decide(
                        "Still waiting for the lab.", "dup", 1_000_000.0 + 120 * i
                    )
                )
        self.assertIsNotNone(
            self.m.decide("Still waiting for the lab.", "dup", 1_000_000.0 + 600)
        )

    def test_identical_waits_on_separate_stops_count(self):
        idle = ["Still waiting."] * 5
        reasons = [
            self.m.decide(r, "fast", 3_000_000.0 + 10 * i) for i, r in enumerate(idle)
        ]
        self.assertIsNotNone(reasons[-1])

    def test_work_plus_waiting_is_not_idle(self):
        reply = "Fixed the build and added a regression test. Still waiting for CI."
        self.assertIsNone(self.run_decide([reply] * 6))

    def test_parallel_hooks_count_one_stop(self):
        import threading

        for i in range(4):
            out = []
            threads = [
                threading.Thread(
                    target=lambda: out.append(
                        self.m.decide(
                            "Waiting for the lab.", "par", 4_000_000.0 + 120 * i
                        )
                    )
                )
                for _ in range(2)
            ]
            for th in threads:
                th.start()
            for th in threads:
                th.join()
            self.assertEqual(out, [None, None])
        self.assertIsNotNone(self.m.decide("Waiting for the lab.", "par", 4_000_600.0))

    def test_codex_event_uses_last_assistant_message(self):
        from unittest import mock

        out = ""
        for i in range(5):
            with mock.patch.object(
                self.m.time, "time", return_value=2_000_000.0 + 120 * i
            ):
                out = self.run_main(
                    {
                        "hook_event_name": "Stop",
                        "session_id": "codex-1",
                        "last_assistant_message": "Waiting for CI on #123.",
                        "stop_hook_active": False,
                    }
                )
        self.assertIn('"decision": "block"', out)

    def test_goal_loop_stops_still_count(self):
        # A goal loop continues the session from a Stop hook, so every stop after the
        # first carries stop_hook_active. Those stops are the case the hook exists for.
        from unittest import mock

        out = ""
        for i in range(5):
            with mock.patch.object(
                self.m.time, "time", return_value=5_000_000.0 + 120 * i
            ):
                out = self.run_main(
                    {
                        "session_id": "goal",
                        "last_assistant_message": f"Waiting for plan 31, check {i}.",
                        "stop_hook_active": True,
                    }
                )
        self.assertIn('"decision": "block"', out)

    def test_same_transcript_stop_counts_once_even_when_slow(self):
        # Two hook entries see one stop more than DUP_WINDOW_S apart (the Codex bridge
        # runs the prose check first). The transcript identity still matches.
        from unittest import mock

        for i in range(4):
            transcript(self.t, ["Still waiting for CI."] * (i + 1))
            event = {"session_id": "slow", "transcript_path": str(self.t)}
            for delay in (0, 30):
                with mock.patch.object(
                    self.m.time, "time", return_value=6_000_000.0 + 120 * i + delay
                ):
                    self.assertEqual(self.run_main(event), "")
        transcript(self.t, ["Still waiting for CI."] * 5)
        self.assertIn(
            '"decision": "block"',
            self.run_main({"session_id": "slow", "transcript_path": str(self.t)}),
        )

    def test_missing_session_id_is_left_alone(self):
        for _ in range(6):
            self.assertEqual(self.run_main({"last_assistant_message": "Waiting."}), "")

    def test_main_never_fails_on_bad_input(self):
        import io

        sys.stdin = io.StringIO("not json")
        self.assertEqual(self.m.main(), 0)
        sys.stdin = sys.__stdin__


if __name__ == "__main__":
    unittest.main(verbosity=1)
