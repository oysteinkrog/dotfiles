import json
import subprocess
import sys
from pathlib import Path

HOOK = str(Path(__file__).with_name("harness-rules-guard.sh"))

# (command, should_block)
cases = [
    # --- bv: blocked (opens the TUI) ---
    ("bv", True),
    ("bv --recipe actionable", True),
    ("cd ~/.dotfiles && bv", True),
    ("~/.local/bin/bv", True),
    ("env FOO=1 bv", True),
    # --- bv: allowed ---
    ("bv --robot-next", False),
    ("bv --robot-triage --json", False),
    ("bv --robot-plan | jq .", False),
    ("bv --help", False),
    ("bv -h", False),
    ("bv --version", False),
    ("br ready", False),
    ('echo "never run bare bv"', False),
    ("rg 'bv' ~/.claude/skills", False),
    ("bvx", False),
    ("ls bv", False),
    # --- am doctor fix: blocked ---
    ("am doctor fix", True),
    ("am doctor fix --yes", True),
    ("am --verbose doctor fix", True),
    ("pm2 status && am doctor fix", True),
    # --- am: allowed ---
    ("am doctor", False),
    ("am doctor check", False),
    ("am doctor fix --help", False),
    ("am --help", False),
    ('br update x --description "never run am doctor fix"', False),
    ("git am patch.mbox", False),
    # --- cass index --semantic: blocked ---
    ("cass index --semantic", True),
    ("cass index --full --semantic", True),
    ("cass index --semantic=true", True),
    ("time cass index --semantic", True),
    # --- cass: allowed ---
    ("cass index", False),
    ("cass index --full", False),
    ('cass search "semantic index"', False),
    ("cass search --semantic foo", False),
    ("cass index --semantic --help", False),
    ("cass --help", False),
    # --- cass-gpu index: blocked ---
    ("cass-gpu index", True),
    ("cass-gpu index --full", True),
    ("nohup cass-gpu index", True),
    # --- cass-gpu: allowed ---
    ("cass-gpu search foo", False),
    ("cass-gpu --version", False),
    ("cass-gpu index --help", False),
    ('echo "do not run cass-gpu index"', False),
    # --- unrelated ---
    ("ls -la", False),
    ("git status", False),
]


def run(command):
    payload = json.dumps(
        {
            "hook_event_name": "PreToolUse",
            "tool_name": "Bash",
            "cwd": "/tmp",
            "tool_input": {"command": command},
        }
    )
    return subprocess.run(["bash", HOOK], input=payload, capture_output=True, text=True)


def main():
    syntax = subprocess.run(["bash", "-n", HOOK], capture_output=True, text=True)
    if syntax.returncode != 0:
        print("FAIL hook is not valid bash:", syntax.stderr.strip())
        sys.exit(1)

    fails = 0
    for command, expect_block in cases:
        result = run(command)
        blocked = result.returncode == 2
        if blocked != expect_block or result.returncode not in (0, 2):
            fails += 1
            print(
                f"FAIL rc={result.returncode} expect_block={expect_block}  {command!r}"
            )
            if result.stderr.strip():
                print("   stderr:", result.stderr.strip()[:300])

    # A garbage payload must fail open.
    bad = subprocess.run(
        ["bash", HOOK], input="not json", capture_output=True, text=True
    )
    if bad.returncode != 0:
        fails += 1
        print(f"FAIL garbage payload rc={bad.returncode}")

    total = len(cases) + 1
    print(f"{total - fails}/{total} correct")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
