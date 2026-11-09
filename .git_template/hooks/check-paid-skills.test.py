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


def test_same_content_anywhere_is_refused():
    p = "notes/copied.md"
    assert cps.problems([p], NAMES, blobs({}), lambda _: "abc", {"abc"})


def test_other_content_passes_blob_check():
    p = "notes/mine.md"
    assert not cps.problems([p], NAMES, blobs({}), lambda _: "def", {"abc"})


def test_jsm_db_names_are_read():
    names = cps.jsm_names()
    if cps.JSM_DB.exists():
        assert "cass" in names and len(names) > 100


def test_pre_push_refuses_paid_file_in_older_commit():
    import os
    import subprocess
    import tempfile

    with tempfile.TemporaryDirectory(dir="/var/tmp") as d:

        def git(*a):
            return subprocess.run(
                ["git", "-C", d, *a], capture_output=True, check=True, text=True
            ).stdout.strip()

        git("init", "-q")
        git("config", "user.email", "t@t")
        git("config", "user.name", "t")
        os.makedirs(f"{d}/.claude/skills/beads-br")
        open(f"{d}/.claude/skills/beads-br/SKILL.md", "w").write("x")
        git("add", "-A")
        git("commit", "-qm", "paid", "--no-verify")
        git("rm", "-rq", ".claude/skills/beads-br")
        open(f"{d}/ok.txt", "w").write("ok")
        git("add", "-A")
        git("commit", "-qm", "clean tip", "--no-verify")
        tip = git("rev-parse", "HEAD")
        cwd = os.getcwd()
        os.chdir(d)
        try:
            found = cps.check_push(
                "", [f"refs/heads/master {tip} refs/heads/master {cps.ZERO}"]
            )
        finally:
            os.chdir(cwd)
        assert any("beads-br" in f for f in found), found


def test_shipped_list_has_all_148():
    assert len(cps.banned_names()) == 148


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print("ok", t.__name__)
    print(f"{len(tests)} passed")
