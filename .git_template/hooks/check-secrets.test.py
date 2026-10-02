#!/usr/bin/env python3
"""Planted-defect tests for the pre-commit secret guard.

Each test fails if the behaviour it pins is removed. Run with:
    python3 check-secrets.test.py

The two cases that matter are the ones that caused real refusals:

1. A configuration key such as JIRA_SITE must not be protected. Its value is a
   hostname that appears in every Jira link in every document.
2. A merge commit must be judged on what it actually adds. `git diff --cached`
   compares the index against the first parent only, so without the MERGE_HEAD
   handling everything the other branch contributed reads as added.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent

spec = importlib.util.spec_from_file_location(
    "check_secrets", HERE / "check-secrets.py"
)
assert spec is not None and spec.loader is not None
cs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cs)

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name} {detail}")
        FAILURES.append(name)


def git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def new_repo(path: Path) -> None:
    git(path.parent, "init", "-q", path.name)
    git(path, "config", "user.email", "test@example.invalid")
    git(path, "config", "user.name", "Test")
    git(path, "config", "commit.gpgsign", "false")


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def test_env_parsing() -> None:
    print("env_secrets")
    with tempfile.TemporaryDirectory() as d:
        env = Path(d) / ".env"
        write(
            env,
            "\n".join(
                [
                    "# a comment",
                    "",
                    "REAL_TOKEN=abcdefghijklmnopqrstuvwxyz0123",
                    "SHORT=tooshort",
                    "JIRA_SITE=example.atlassian.net",
                    "ZENDESK_SUBDOMAIN=example-subdomain-long",
                    "NOT_A_PAIR_LINE",
                ]
            ),
        )
        got = {label for _, label in cs.env_secrets(env)}

    check("protects a long credential", "env:REAL_TOKEN" in got, got)
    check(
        "skips a value under MIN_DYNAMIC_LEN",
        "env:SHORT" not in got,
        got,
    )
    check(
        "does not protect JIRA_SITE, a hostname",
        "env:JIRA_SITE" not in got,
        got,
    )
    check(
        "does not protect ZENDESK_SUBDOMAIN",
        "env:ZENDESK_SUBDOMAIN" not in got,
        got,
    )
    check("missing .env yields nothing", cs.env_secrets(Path("/nonexistent/x")) == [])
    check(
        "every allowlisted key is spelled in upper snake case",
        all(k == k.upper() and " " not in k for k in cs.NOT_SECRET_KEYS),
    )


def test_static_banlist() -> None:
    print("find_match")
    import hashlib

    value = b"a-planted-value-of-known-length"
    digest = hashlib.sha256(value).hexdigest()
    blob = b"prefix " + value + b" suffix"
    check("finds a banned value mid-blob", cs.find_match(blob, len(value), digest) == 7)
    check(
        "reports nothing when the value is absent",
        cs.find_match(b"nothing here at all", len(value), digest) is None,
    )
    check(
        "reports nothing when the blob is shorter than the value",
        cs.find_match(b"short", len(value), digest) is None,
    )


def test_normal_commit() -> None:
    print("staged_added_blob, normal commit")
    with tempfile.TemporaryDirectory() as d:
        repo = Path(d) / "r"
        new_repo(repo)
        write(repo / "a.txt", "first line\n")
        git(repo, "add", "a.txt")
        git(repo, "commit", "-q", "--no-verify", "-m", "one")

        write(repo / "a.txt", "first line\nsecond line\n")
        git(repo, "add", "a.txt")

        cwd = Path.cwd()
        try:
            import os

            os.chdir(repo)
            blob = cs.staged_added_blob()
        finally:
            os.chdir(cwd)

    check("sees the added line", b"second line" in blob, blob)
    check("does not see the unchanged line", b"first line" not in blob, blob)


def test_merge_commit() -> None:
    print("staged_added_blob, merge commit")
    with tempfile.TemporaryDirectory() as d:
        repo = Path(d) / "r"
        new_repo(repo)
        write(repo / "base.txt", "shared\n")
        git(repo, "add", "base.txt")
        git(repo, "commit", "-q", "--no-verify", "-m", "base")

        # The other branch adds a file holding a protected-looking value.
        git(repo, "checkout", "-q", "-b", "other")
        write(repo / "theirs.txt", "a-value-that-looks-protected\n")
        git(repo, "add", "theirs.txt")
        git(repo, "commit", "-q", "--no-verify", "-m", "theirs")

        git(repo, "checkout", "-q", "master" if _has(repo, "master") else "main")
        write(repo / "mine.txt", "my own line\n")
        git(repo, "add", "mine.txt")
        git(repo, "commit", "-q", "--no-verify", "-m", "mine")

        subprocess.run(
            ["git", "-C", str(repo), "merge", "--no-commit", "--no-ff", "other"],
            check=False,
            capture_output=True,
        )

        import os

        cwd = Path.cwd()
        try:
            os.chdir(repo)
            parents = cs.merge_parents()
            blob = cs.staged_added_blob()
        finally:
            os.chdir(cwd)

    check("MERGE_HEAD is read", len(parents) == 1, parents)
    check(
        "a merge does not report the other side's content as added",
        b"a-value-that-looks-protected" not in blob,
        blob,
    )
    check("a merge adds nothing of its own here", blob == b"", blob)


def _has(repo: Path, branch: str) -> bool:
    res = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "--verify", branch],
        check=False,
        capture_output=True,
    )
    return res.returncode == 0


def test_merge_with_a_real_addition() -> None:
    print("staged_added_blob, merge that does add something")
    with tempfile.TemporaryDirectory() as d:
        repo = Path(d) / "r"
        new_repo(repo)
        write(repo / "base.txt", "shared\n")
        git(repo, "add", "base.txt")
        git(repo, "commit", "-q", "--no-verify", "-m", "base")

        git(repo, "checkout", "-q", "-b", "other")
        write(repo / "theirs.txt", "theirs\n")
        git(repo, "add", "theirs.txt")
        git(repo, "commit", "-q", "--no-verify", "-m", "theirs")

        git(repo, "checkout", "-q", "master" if _has(repo, "master") else "main")
        write(repo / "mine.txt", "mine\n")
        git(repo, "add", "mine.txt")
        git(repo, "commit", "-q", "--no-verify", "-m", "mine")

        subprocess.run(
            ["git", "-C", str(repo), "merge", "--no-commit", "--no-ff", "other"],
            check=False,
            capture_output=True,
        )
        # A conflict resolution that introduces genuinely new content.
        write(repo / "resolved.txt", "brand-new-secret-shaped-value\n")
        git(repo, "add", "resolved.txt")

        import os

        cwd = Path.cwd()
        try:
            os.chdir(repo)
            blob = cs.staged_added_blob()
        finally:
            os.chdir(cwd)

    check(
        "content new to both sides is still caught",
        b"brand-new-secret-shaped-value" in blob,
        blob,
    )


def test_scan() -> None:
    print("scan")
    hits = cs.scan(b"line with mytoken inside", [(b"mytoken", "env:X")])
    check("a dynamic value in the blob is a hit", hits == ["env:X"], hits)
    check("a clean blob has no hits", cs.scan(b"nothing", [(b"zzz", "env:X")]) == [])


def main() -> int:
    test_env_parsing()
    test_static_banlist()
    test_normal_commit()
    test_merge_commit()
    test_merge_with_a_real_addition()
    test_scan()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
