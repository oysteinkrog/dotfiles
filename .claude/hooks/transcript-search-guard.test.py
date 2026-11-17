"""Test matrix for transcript-search-guard.sh. Run: python3 transcript-search-guard.test.py

Choices: a quoted or heredoc mention (echo "rg ~/.claude/projects", a commit
message) is allowed, because the shared parser blanks quoted text. Nothing here
runs a real search: the hook only parses the command.
"""

import json
import subprocess
import sys
from pathlib import Path

HOOK = str(Path(__file__).with_name("transcript-search-guard.sh"))
H = str(Path.home())
P = f"{H}/.claude/projects"
S = f"{P}/-home-oystein"
CWD = f"{H}/work/ifkb"
B, OK = True, False

cases = [
    (f"rg foo {P}", CWD, B),
    ("rg foo ~/.claude/projects", CWD, B),
    ("rg foo ~/.claude/projects/", CWD, B),
    ("grep -r foo $HOME/.claude/projects", CWD, B),
    ('grep -rn foo "${HOME}/.claude"', CWD, B),
    ("rg foo ~/.claude", CWD, B),
    ("rg foo ~/.dotfiles/.claude/projects", CWD, B),
    (f"rg foo {H}/.dotfiles/.claude", CWD, B),
    ("find ~/.claude/projects -name '*.jsonl' -mtime -1", CWD, B),
    ("du -sh ~/.claude/projects", CWD, B),
    ("fd abc ~/.claude/projects", CWD, B),
    ("ag foo ~/.claude/projects", CWD, B),
    ("ack foo ~/.claude/projects", CWD, B),
    ("egrep -r foo ~/.claude/projects", CWD, B),
    ("fgrep -r foo ~/.claude/projects", CWD, B),
    ("rg foo ~", CWD, B),
    (f"rg foo {H}", CWD, B),
    ("rg foo /home", CWD, B),
    ("grep -r foo /", CWD, B),
    ("cd ~/.claude/projects && rg foo", CWD, B),
    ("cd ~/.claude && grep -r foo .", CWD, B),
    ("cd ~/.claude/projects; find . -name x", CWD, B),
    ("rg foo", f"{H}/.claude/projects", B),
    ("grep foo ~/.claude/projects/*/*.jsonl", CWD, B),
    ("rg foo ~/.claude/projects/*", CWD, B),
    ("timeout 5 rg foo ~/.claude/projects", CWD, B),
    ("bash -c 'rg foo ~/.claude/projects'", CWD, B),
    # allowed
    ("rg foo src/", CWD, OK),
    ("rg foo", CWD, OK),
    (f"grep x {S}/abc.jsonl", CWD, OK),
    ("grep x ~/.claude/projects/-home-oystein/abc.jsonl", CWD, OK),
    ("rg foo ~/.claude/projects/-home-oystein", CWD, OK),
    (f"rg foo {S}/memory", CWD, OK),
    ("find ~/.claude/projects/-home-oystein -name '*.jsonl'", CWD, OK),
    ("cd ~/.claude/projects/-home-oystein && rg foo", CWD, OK),
    ("cat ~/.claude/settings.json", CWD, OK),
    ("rg foo ~/.claude/settings.json", CWD, OK),
    ("rg foo ~/.claude/hooks", CWD, OK),
    ("rg foo ~/.claude/skills", CWD, OK),
    ("ls ~/.claude/projects", CWD, OK),
    ("find ~/.claude/projects -maxdepth 1 -type d", CWD, OK),
    ("rg foo ~/.claude/projects # noqa: transcript-search", CWD, OK),
    ("grep -r foo ~/.claude # noqa: transcript-search", CWD, OK),
    ('echo "rg foo ~/.claude/projects"', CWD, OK),
    ('git commit -m "use cass, not rg ~/.claude/projects"', CWD, OK),
    ("cass search foo", CWD, OK),
    ("grep foo | head", CWD, OK),
    ("cd ~/.claude/projects/x && ls", CWD, OK),
]

if subprocess.run(["bash", "-n", HOOK]).returncode:
    sys.exit("FAIL hook is not valid bash")

fails = 0
for cmd, cwd, expect in cases:
    payload = json.dumps({"tool_name": "Bash", "cwd": cwd, "tool_input": {"command": cmd}})
    out = subprocess.run(["bash", HOOK], input=payload, capture_output=True, text=True)
    blocked = bool(out.stdout.strip()) and (
        json.loads(out.stdout)["hookSpecificOutput"]["permissionDecision"] == "deny"
    )
    if blocked != expect or out.returncode != 0:
        fails += 1
        print(f"FAIL block={blocked} expect={expect} rc={out.returncode}  {cmd!r} cwd={cwd}")

print(f"{len(cases) - fails}/{len(cases)} correct")
sys.exit(1 if fails else 0)
