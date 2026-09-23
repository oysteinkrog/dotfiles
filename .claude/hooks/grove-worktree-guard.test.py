import json
import subprocess
import sys
from pathlib import Path

HOOK = str(Path(__file__).with_name("grove-worktree-guard.sh"))

UNGUARDED_CWD = "/home/oystein/elsewhere"
GUARDED_CWD = "/c/work/desktop/master"

# (command, cwd, should_block) -- the required cases from the bead are
# marked inline; the rest exercise the edges the required cases don't reach
# (compound commands, -C escaping the guard, indeterminate fail-open,
# multiple guarded dirs, gh with an explicit dest).
cases = [
    # --- required: blocked ---
    ("git worktree add /c/work/desktop/foo", UNGUARDED_CWD, True),
    ("git -C /c/work/desktop worktree add foo", UNGUARDED_CWD, True),
    ("git clone https://github.com/foo/bar.git", GUARDED_CWD, True),
    ("gh repo clone owner/repo", GUARDED_CWD, True),
    # --- required: allowed ---
    ("git worktree list", GUARDED_CWD, False),
    ("git worktree prune", GUARDED_CWD, False),
    ("git worktree remove /c/work/desktop/foo", GUARDED_CWD, False),
    ("git clone https://github.com/foo/bar.git /tmp/bar", GUARDED_CWD, False),
    ("git clone https://github.com/foo/bar.git /c/work/desktop/.scratch/bar", UNGUARDED_CWD, False),
    (
        'br update bd-1 --description "run git worktree add /c/work/desktop/foo instead" -p 1',
        GUARDED_CWD,
        False,
    ),
    ("git worktree add /c/work/desktop/foo  # noqa: grove-worktree", UNGUARDED_CWD, False),
    # --- extra: worktree lock/unlock, also read/maintenance ops ---
    ("git worktree lock /c/work/desktop/foo", GUARDED_CWD, False),
    ("git worktree unlock /c/work/desktop/foo", GUARDED_CWD, False),
    # --- extra: -C moves the effective cwd OUT of the guard ---
    ("git -C /tmp worktree add relbranchdir", GUARDED_CWD, False),
    # --- extra: compound command, guarded call is the second segment ---
    ("echo hi && git worktree add /c/work/desktop/bar", UNGUARDED_CWD, True),
    ("git worktree list && git worktree add /c/work/desktop/bar", UNGUARDED_CWD, True),
    # --- extra: indeterminate target, but cwd is NOT guarded -> allow ---
    ("git clone --depth 1", UNGUARDED_CWD, False),
    # --- extra: indeterminate target, cwd IS guarded -> fail closed ---
    ("git clone --depth 1", GUARDED_CWD, True),
    # --- extra: gh repo clone with an explicit unguarded destination ---
    ("gh repo clone owner/repo /tmp/repo", GUARDED_CWD, False),
    # --- extra: relative git clone (bare URL) resolved against guarded cwd ---
    ("git clone git@github.com:foo/bar.git", GUARDED_CWD, True),
    # --- extra: relative git clone resolved against an unguarded cwd ---
    ("git clone git@github.com:foo/bar.git", UNGUARDED_CWD, False),
    # --- extra: quoted mention as the WHOLE command line still doesn't match ---
    ('echo "git clone https://github.com/foo/bar.git"', GUARDED_CWD, False),
    # --- grove list: blocked (17+ min status scan on WSL1) ---
    ("grove list", UNGUARDED_CWD, True),
    ("grove list --short", GUARDED_CWD, True),
    ("grove list --json", UNGUARDED_CWD, True),
    ("grove list --no-status", UNGUARDED_CWD, True),
    ("grove --repo desktop list", UNGUARDED_CWD, True),
    ("grove -v list --short", UNGUARDED_CWD, True),
    ("~/.cargo/bin/grove list", UNGUARDED_CWD, True),
    ("cd /c/work/desktop && grove list | head", UNGUARDED_CWD, True),
    # --- grove list: allowed near-misses ---
    ("grove list --help", UNGUARDED_CWD, False),
    ("grove list -h", UNGUARDED_CWD, False),
    ("grove help list", UNGUARDED_CWD, False),
    ("grove repo list", UNGUARDED_CWD, False),
    ("grove path mytag", UNGUARDED_CWD, False),
    ("grove status mytag", UNGUARDED_CWD, False),
    ('echo "never run grove list here"', UNGUARDED_CWD, False),
    ('br update bd-1 --description "deny grove list and grove done --force"', UNGUARDED_CWD, False),
    ("rg 'grove list' ~/.claude/skills", UNGUARDED_CWD, False),
    ("grove list  # noqa: grove-worktree", UNGUARDED_CWD, False),
    # --- grove done --force: blocked ---
    ("grove done mytag --force", UNGUARDED_CWD, True),
    ("grove done --force", GUARDED_CWD, True),
    ("grove done --force --keep-remote mytag", UNGUARDED_CWD, True),
    # --- grove done: allowed near-misses ---
    ("grove done mytag", UNGUARDED_CWD, False),
    ("grove done mytag --keep-local", UNGUARDED_CWD, False),
    ("grove done --help", UNGUARDED_CWD, False),
    ("grove done --force --help", UNGUARDED_CWD, False),
    ("grove repo remove old --force", UNGUARDED_CWD, False),
]


def run(command, cwd):
    payload = json.dumps(
        {
            "hook_event_name": "PreToolUse",
            "tool_name": "Bash",
            "cwd": cwd,
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
    for command, cwd, expect_block in cases:
        result = run(command, cwd)
        blocked = result.returncode == 2
        if blocked != expect_block:
            fails += 1
            print(f"FAIL block={blocked} expect={expect_block}  {command!r} (cwd={cwd})")
            if result.stderr.strip():
                print("   stderr:", result.stderr.strip()[:300])
        elif result.returncode not in (0, 2):
            fails += 1
            print(f"FAIL unexpected exit code {result.returncode}  {command!r} (cwd={cwd})")
            if result.stderr.strip():
                print("   stderr:", result.stderr.strip()[:300])

    print(f"{len(cases) - fails}/{len(cases)} correct")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
