#!/usr/bin/env python3
"""validate-skill.py — Self-contained public skill validator.

USAGE:
    validate-skill.py [skill-dir]
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

THIS = Path(__file__).resolve()
DEFAULT_SKILL_DIR = THIS.parent.parent
FRONTMATTER_RE = re.compile(r"^---\n(?P<body>.*?)\n---\n", re.DOTALL)


def main(argv: list[str]) -> int:
    if len(argv) > 1 and argv[1] in {"-h", "--help"}:
        print(__doc__.strip())
        return 0

    skill_dir = Path(argv[1]).resolve() if len(argv) > 1 else DEFAULT_SKILL_DIR
    errors: list[str] = []

    skill_md = skill_dir / "SKILL.md"
    if not skill_md.is_file():
        errors.append(f"missing {skill_md}")
    else:
        text = skill_md.read_text(encoding="utf-8")
        match = FRONTMATTER_RE.match(text)
        if not match:
            errors.append("SKILL.md must start with YAML frontmatter delimited by ---")
        else:
            frontmatter = match.group("body")
            if not re.search(r"^name:\s*\S+", frontmatter, re.MULTILINE):
                errors.append("frontmatter missing name")
            desc_match = re.search(
                r"^description:\s*(?:>-\s*\n(?P<block>(?:  .*\n?)+)|(?P<inline>.+))",
                frontmatter,
                re.MULTILINE,
            )
            if not desc_match:
                errors.append("frontmatter missing description")
            else:
                desc = desc_match.group("block") or desc_match.group("inline") or ""
                if len(desc.strip()) > 1024:
                    errors.append("description exceeds 1024 characters")
        if len(text.splitlines()) > 800:
            errors.append("SKILL.md is longer than 800 lines; defer deep detail to references/")

    for required_dir in ("references", "scripts", "subagents"):
        path = skill_dir / required_dir
        if not path.is_dir():
            errors.append(f"missing directory: {required_dir}/")

    for script in (skill_dir / "scripts").glob("*"):
        if script.is_file() and script.suffix in {".sh", ".py"}:
            if not script.read_bytes().startswith(b"#!"):
                errors.append(f"script missing shebang: {script.relative_to(skill_dir)}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"OK: {skill_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
