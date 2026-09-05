#!/usr/bin/env python3
"""Delegate to writing-skills' validator.

Usage:
    ./validate-skill.py [skill-path]

If skill-path is omitted, validates this skill itself.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path


def find_validator():
    candidates = [
        Path.home() / ".claude/skills/writing-skills/scripts/validate-skill.py",
        Path.home() / ".codex/skills/writing-skills/scripts/validate-skill.py",
        Path("/data/agent_config_folder_backups/.claude/skills/writing-skills/scripts/validate-skill.py"),
    ]
    for c in candidates:
        if c.exists():
            return c
    return None


def main():
    if len(sys.argv) >= 2 and sys.argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        sys.exit(0)
    skill_path = sys.argv[1] if len(sys.argv) > 1 else str(Path(__file__).resolve().parent.parent)
    validator = find_validator()
    if validator is None:
        print("writing-skills' validate-skill.py not found in any standard location:", file=sys.stderr)
        print("  ~/.claude/skills/writing-skills/scripts/validate-skill.py", file=sys.stderr)
        print("  ~/.codex/skills/writing-skills/scripts/validate-skill.py", file=sys.stderr)
        print("  /data/agent_config_folder_backups/.claude/skills/writing-skills/scripts/validate-skill.py", file=sys.stderr)
        sys.exit(127)
    cmd = [sys.executable, str(validator), skill_path]
    print(f"+ {' '.join(cmd)}")
    sys.exit(subprocess.call(cmd))


if __name__ == "__main__":
    main()
