#!/usr/bin/env python3
"""Exit 0 when the project the hook runs in registers its own plain-language hook.

The user-level wrappers call this first and skip when it exits 0, so the gate runs
once instead of twice. Any other exit code, any error and any doubt mean "run the gate".

Detection: take the cwd from the hook payload (stdin, JSON), else $CLAUDE_PROJECT_DIR,
else the current directory. Find the git top. Read <top>/.claude/settings.json and look
for a hook command that mentions plain-language-guard.sh or plain-language-health.sh and
is not the user-level copy. The user's own ~/.dotfiles checkout never counts as having
its own copy, because its settings.json is the user-level one.

Usage: plain-language-project-has-own.py < payload.json
"""
import json
import os
import subprocess
import sys

NAMES = ("plain-language-guard.sh", "plain-language-health.sh")


def commands(node):
    if isinstance(node, dict):
        c = node.get("command")
        if isinstance(c, str):
            yield c
        for v in node.values():
            yield from commands(v)
    elif isinstance(node, list):
        for v in node:
            yield from commands(v)


def main():
    raw = sys.stdin.read() if not sys.stdin.isatty() else ""
    cwd = None
    try:
        cwd = json.loads(raw).get("cwd")
    except Exception:
        pass
    cwd = cwd or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    if not os.path.isdir(cwd):
        return 1
    top = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True, timeout=5)
    if top.returncode != 0 or not top.stdout.strip():
        return 1
    settings = os.path.join(top.stdout.strip(), ".claude", "settings.json")
    user = os.path.join(os.path.expanduser("~"), ".claude", "settings.json")
    if os.path.realpath(settings) == os.path.realpath(user):
        return 1
    with open(settings, encoding="utf-8") as f:
        data = json.load(f)
    home = os.path.expanduser("~")
    for c in commands(data.get("hooks", {})):
        if any(n in c for n in NAMES) and "~/.claude" not in c and f"{home}/.claude" not in c \
                and "$HOME/.claude" not in c:
            return 0
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(1)
