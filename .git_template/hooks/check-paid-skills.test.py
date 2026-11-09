#!/usr/bin/env python3
"""Tests for the paid-skills pre-commit guard. Run: python3 check-paid-skills.test.py"""

from __future__ import annotations

import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("cps", HERE / "check-paid-skills.py")
assert spec is not None and spec.loader is not None
cps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cps)

NAMES = {"beads-br", "xf"}


def blobs(mapping):
    return lambda path: mapping.get(path, b"plain text")


def test_banned_name_is_refused():
    assert cps.problems([".claude/skills/beads-br/SKILL.md"], NAMES, blobs({}))


def test_self_test_marker_is_refused():
    assert cps.problems([".claude/skills/new-one/SELF-TEST.md"], NAMES, blobs({}))


def test_vendor_mention_in_skill_is_refused():
    p = ".claude/skills/new-one/SKILL.md"
    assert cps.problems([p], NAMES, blobs({p: b"see https://jeffreys-skills.md/x"}))


def test_own_skill_passes():
    assert not cps.problems([".claude/skills/my-own/SKILL.md"], NAMES, blobs({}))


def test_mention_outside_skills_passes():
    p = ".gitignore"
    assert not cps.problems([p], NAMES, blobs({p: b"# jeffreys-skills.md"}))


def test_name_prefix_is_not_a_match():
    assert not cps.problems([".claude/skills/xf-tools/SKILL.md"], NAMES, blobs({}))


def test_shipped_list_has_all_148():
    assert len(cps.banned_names()) == 148


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print("ok", t.__name__)
    print(f"{len(tests)} passed")
