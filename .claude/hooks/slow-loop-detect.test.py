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
        os.environ["SLOW_LOOP_STATE_DIR"] = self.tmp.name + "/state"
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

    def test_stop_hook_active_is_left_alone(self):
        out = self.run_main(
            {
                "session_id": "x",
                "last_assistant_message": "Waiting.",
                "stop_hook_active": True,
            }
        )
        self.assertEqual(out, "")

    def test_main_never_fails_on_bad_input(self):
        import io

        sys.stdin = io.StringIO("not json")
        self.assertEqual(self.m.main(), 0)
        sys.stdin = sys.__stdin__


if __name__ == "__main__":
    unittest.main(verbosity=1)
