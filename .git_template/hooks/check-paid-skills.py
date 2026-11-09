#!/usr/bin/env python3
"""Guard: keep paid jeffreys-skills.md skills out of this public repo.

The vendor sent copyright notices on 2026-11-02. History was rewritten on
2026-11-03 and again on 2026-11-09. jsm installs into ~/.claude/skills, which
is this repo, and its nightly auto-update (install_new = true) adds new paid
skills there without asking. So the guard runs twice:

  pre-commit:  check-paid-skills.py            (staged files)
  pre-push:    check-paid-skills.py --pre-push (every commit about to leave)

The pre-push run catches what pre-commit cannot: old local branches, merges
of pre-rewrite history (for example from the home desktop's clone), and
commits made with --no-verify.

A file is refused when it:
1. lives under .claude/skills/<name>/ where <name> is in paid-skills.txt, is a
   skill jsm reports as installed (jsm.db), or is a folder on disk that holds
   a SELF-TEST.md,
2. is a SELF-TEST.md under .claude/skills/ (the vendor's marker file),
3. lives under .claude/skills/ and mentions jeffreys-skills.md, or
4. has the same content (blob hash) as any file jsm installed on this
   machine, wherever in the repo it is.

Run the tests with: python3 check-paid-skills.test.py
"""

from __future__ import annotations

import sqlite3
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SKILLS = ".claude/skills/"
MARKER = b"jeffreys-skills.md"
ZERO = "0" * 40
SKILLS_DIR = Path.home() / ".claude" / "skills"
JSM_DB = Path.home() / ".config" / "jsm" / "jsm.db"


def banned_names(path: Path = HERE / "paid-skills.txt") -> set[str]:
    if not path.exists():
        return set()
    return {
        line.strip()
        for line in path.read_text().splitlines()
        if line.strip() and not line.startswith("#")
    }


def jsm_names(db: Path = JSM_DB) -> set[str]:
    """Skills jsm says it installed. Empty when jsm is not on this machine."""
    if not db.exists():
        return set()
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        try:
            return {r[0] for r in con.execute("select name from installed_skills")}
        finally:
            con.close()
    except sqlite3.Error:
        return set()


def marker_dirs(root: Path = SKILLS_DIR) -> set[str]:
    """Skill folders on disk that carry the vendor's SELF-TEST.md."""
    if not root.is_dir():
        return set()
    return {p.parent.relative_to(root).parts[0] for p in root.glob("*/**/SELF-TEST.md")}


def all_names() -> set[str]:
    return banned_names() | jsm_names() | marker_dirs()


def jsm_blobs(names: set[str], root: Path = SKILLS_DIR) -> set[str]:
    """Git blob ids of every file in the paid skill folders on disk."""
    files = []
    for name in names:
        d = root / name
        if d.is_dir() and not d.is_symlink():
            files += [
                str(p) for p in d.rglob("*") if p.is_file() and not p.is_symlink()
            ]
    if not files:
        return set()
    out = subprocess.run(
        ["git", "hash-object", "--stdin-paths"],
        input="\n".join(files).encode(),
        capture_output=True,
        check=True,
    ).stdout.decode()
    return set(out.split())


def problems(
    paths: list[str], names: set[str], read, blob_of=None, banned_blobs=frozenset()
) -> list[str]:
    found = []
    for path in paths:
        if blob_of and banned_blobs and blob_of(path) in banned_blobs:
            found.append(f"{path}: same content as a file jsm installed")
            continue
        if not path.startswith(SKILLS):
            continue
        parts = path[len(SKILLS) :].split("/")
        if len(parts) < 2:
            continue
        if parts[0] in names:
            found.append(f"{path}: skill '{parts[0]}' is a paid jsm skill")
        elif parts[-1] == "SELF-TEST.md":
            found.append(f"{path}: SELF-TEST.md is the jsm vendor's marker file")
        elif MARKER in read(path):
            found.append(f"{path}: mentions jeffreys-skills.md")
    return found


# ── pre-commit ───────────────────────────────────────────────────────────


def staged_entries() -> dict[str, str]:
    """Staged added or changed paths mapped to their blob ids."""
    names = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"],
        capture_output=True,
        check=True,
    ).stdout.decode("utf-8", "replace")
    paths = [p for p in names.split("\0") if p]
    if not paths:
        return {}
    out = subprocess.run(
        ["git", "ls-files", "-s", "-z", "--", *paths], capture_output=True, check=True
    ).stdout.decode("utf-8", "replace")
    entries = {}
    for rec in out.split("\0"):
        if rec:
            meta, path = rec.split("\t", 1)
            entries[path] = meta.split()[1]
    return entries


def read_blob(sha: str) -> bytes:
    return subprocess.run(
        ["git", "cat-file", "blob", sha], capture_output=True, check=False
    ).stdout


def check_staged() -> list[str]:
    entries = staged_entries()
    names = all_names()
    return problems(
        list(entries),
        names,
        lambda p: read_blob(entries[p]),
        entries.get,
        jsm_blobs(names),
    )


# ── pre-push ─────────────────────────────────────────────────────────────


def outgoing_entries(remote: str, updates: list[tuple[str, str]]) -> dict[str, str]:
    """(path, blob) pairs added or changed by commits the push sends.

    A commit counts as already published only when a remote-tracking ref of
    this remote reaches it, so a force-push of rewritten history is checked in
    full.
    """
    entries: dict[str, str] = {}
    for local_sha, remote_sha in updates:
        if local_sha == ZERO:
            continue
        args = [
            "git",
            "log",
            "--raw",
            "--no-abbrev",
            "--no-renames",
            "-m",
            "--format=",
            "-z",
            local_sha,
            "--not",
        ]
        args += [f"--remotes={remote}"] if remote else []
        if (
            remote_sha != ZERO
            and subprocess.run(
                ["git", "cat-file", "-e", remote_sha], capture_output=True
            ).returncode
            == 0
        ):
            args.append(remote_sha)
        out = subprocess.run(args, capture_output=True, check=True).stdout.decode(
            "utf-8", "replace"
        )
        fields = out.split("\0")
        i = 0
        while i < len(fields) - 1:
            meta = fields[i].lstrip("\n")
            if not meta.startswith(":"):
                i += 1
                continue
            parts = meta.split()
            path = fields[i + 1]
            if parts[4] != "D":
                entries.setdefault(path + "\0" + parts[3], parts[3])
            i += 2
    return entries


def check_push(remote: str, lines: list[str]) -> list[str]:
    updates = []
    for line in lines:
        parts = line.split()
        if len(parts) == 4:
            updates.append((parts[1], parts[3]))
    keyed = outgoing_entries(remote, updates)
    names = all_names()
    banned = jsm_blobs(names)
    found = []
    for key, sha in keyed.items():
        path = key.split("\0", 1)[0]
        found += problems(
            [path], names, lambda _p, s=sha: read_blob(s), lambda _p, s=sha: s, banned
        )
    return sorted(set(found))


def report(found: list[str], when: str) -> int:
    if not found:
        return 0
    print(f"NOT ALLOWED ({when}): paid jeffreys-skills.md skill content.")
    for line in found[:20]:
        print("  " + line)
    if len(found) > 20:
        print(f"  ... and {len(found) - 20} more")
    print(
        "Paid skills stay on disk only. See .git_template/hooks/check-paid-skills.py."
    )
    return 1


def main(argv: list[str]) -> int:
    if len(argv) > 1 and argv[1] == "--pre-push":
        remote = argv[2] if len(argv) > 2 else ""
        return report(check_push(remote, sys.stdin.read().splitlines()), "push")
    return report(check_staged(), "commit")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
