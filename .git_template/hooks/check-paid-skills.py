#!/usr/bin/env python3
"""Pre-commit guard: keep paid jeffreys-skills.md skills out of this public repo.

On 2026-11-03 history was rewritten to remove 94 skills that came from a jsm
subscription, after the vendor sent copyright notices. jsm installs into
~/.claude/skills, which is this repo, so a bulk `git add` picks them up again.

The commit is refused when a staged file that is added or changed:
1. lives under .claude/skills/<name>/ where <name> is in paid-skills.txt,
2. is a SELF-TEST.md under .claude/skills/ (the vendor's marker file), or
3. lives under .claude/skills/ and mentions jeffreys-skills.md.

Skills from jsm stay on disk and are gitignored. If a skill is truly your own,
add it under a new name. Run the tests with: python3 check-paid-skills.test.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SKILLS = ".claude/skills/"
MARKER = b"jeffreys-skills.md"


def banned_names(path: Path = HERE / "paid-skills.txt") -> set[str]:
    if not path.exists():
        return set()
    return {
        line.strip()
        for line in path.read_text().splitlines()
        if line.strip() and not line.startswith("#")
    }


def staged_paths() -> list[str]:
    out = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"],
        capture_output=True,
        check=True,
    ).stdout
    return [p for p in out.decode("utf-8", "replace").split("\0") if p]


def staged_blob(path: str) -> bytes:
    return subprocess.run(
        ["git", "show", f":{path}"], capture_output=True, check=False
    ).stdout


def problems(paths: list[str], names: set[str], read=staged_blob) -> list[str]:
    found = []
    for path in paths:
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


def main() -> int:
    found = problems(staged_paths(), banned_names())
    if not found:
        return 0
    print("NOT ALLOWED: paid jeffreys-skills.md skills must not be committed.")
    for line in found[:20]:
        print("  " + line)
    if len(found) > 20:
        print(f"  ... and {len(found) - 20} more")
    print("Unstage them (git rm -r --cached <path>) and add the folder to .gitignore.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
