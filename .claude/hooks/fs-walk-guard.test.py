"""Test matrix for fs-walk-guard.sh. Run: python3 fs-walk-guard.test.py"""

import json
import subprocess
import sys
from pathlib import Path

HOOK = str(Path(__file__).with_name("fs-walk-guard.sh"))
HOME = str(Path.home())
PROJ = f"{HOME}/work/desktop/master"
B, OK = True, False

# (command, cwd, should_block)
cases = [
    # --- the command that caused it ---
    ("bfs -S dfs / -iname '*monitoring*plan*'", PROJ, B),
    # --- broad roots, explicit ---
    ("find / -name foo.txt", PROJ, B),
    ("find ~ -name '*.md'", PROJ, B),
    ("find $HOME -type f -name x", PROJ, B),
    ('find "${HOME}" -name x', PROJ, B),
    ("find /home -name x", PROJ, B),
    (f"find {HOME}/ -name x", PROJ, B),
    ("find /var -name '*.log'", PROJ, B),
    ("find /var/tmp -name x", PROJ, B),
    ("find -L / -name x 2>/dev/null", PROJ, B),
    ("find /etc ~ -name x", PROJ, B),
    ("fd monitoring /", PROJ, B),
    ("fd -H -e md plan ~", PROJ, B),
    ("fdfind plan $HOME", PROJ, B),
    ("fd --search-path / plan", PROJ, B),
    ("du -sh ~", PROJ, B),
    ("du -sh ~/*", PROJ, B),
    ("du -h -d 1 /var/tmp", PROJ, B),
    ("ncdu /", PROJ, B),
    ("tree ~", PROJ, B),
    ("ls -R /home", PROJ, B),
    ("ls -laR ~", PROJ, B),
    ("rg -l monitoring ~", PROJ, B),
    ("rg --files /", PROJ, B),
    ("rg -e foo -l /var", PROJ, B),
    ("grep -rn foo /", PROJ, B),
    ("grep -R --include='*.md' plan ~", PROJ, B),
    ("btrfs filesystem du -s /home", PROJ, B),
    ("btrfs fi du /var/tmp", PROJ, B),
    # --- no path, broad cwd ---
    ("find . -name x", HOME, B),
    ("find -name x", HOME, B),
    ("fd plan", HOME, B),
    ("rgg monitoring", HOME, B),
    ("rg -l foo", "/", B),
    ("grep -r foo", "/var", B),
    ("du -sh", HOME, B),
    ("du -sh .", "/var/tmp", B),
    # --- cwd moved inside the command ---
    ("cd / && find . -name x", PROJ, B),
    ("cd ~ ; fd plan", PROJ, B),
    ("cd && rg -l foo", PROJ, B),
    ("cd .. && find . -name x", f"{HOME}/work", B),
    ("(cd / && find . -name x)", PROJ, B),
    # --- wrappers, pipelines, nested shells ---
    ("sh -c 'find / -name x'", PROJ, B),
    ('bash -lc "cd ~ && fd plan"', PROJ, B),
    ("find / -name x 2>/dev/null | head", PROJ, B),
    ("echo start; nice -n 19 find / -name x", PROJ, B),
    ("timeout 30 find ~ -name x", PROJ, B),
    ("sudo find / -name x", PROJ, B),
    ("env LC_ALL=C find / -name x", PROJ, B),
    ("ls && find / -name x", PROJ, B),
    ("eval 'find / -name x'", PROJ, B),
    # --- narrower paths: allowed ---
    ("find ~/work/desktop/master -name '*.cs'", PROJ, OK),
    ("find /var/tmp/claude/task -name x", PROJ, OK),
    ("find /etc -name '*.conf'", PROJ, OK),
    ("find /usr/share -name '*.desktop'", PROJ, OK),
    ("fd plan ~/work/ifkb", PROJ, OK),
    ("rg -l foo ~/.dotfiles", PROJ, OK),
    ("grep -rn foo /etc", PROJ, OK),
    ("du -sh ~/work/desktop/master", PROJ, OK),
    ("du -sh /var/tmp/claude/task", PROJ, OK),
    ("du -sh /var/tmp/claude", PROJ, B),
    ("tree -L 3 ~/work/grove", PROJ, OK),
    ("find . -name x", PROJ, OK),
    ("fd plan", PROJ, OK),
    ("rg -l foo", PROJ, OK),
    ("rgg monitoring", PROJ, OK),
    ("cd ~/work/ifkb && find . -name x", HOME, OK),
    ("cd / && cd ~/work/ifkb && fd plan", PROJ, OK),
    # --- depth-limited: allowed ---
    ("find / -maxdepth 1 -name 'x*'", PROJ, OK),
    ("find ~ -maxdepth 2 -type d -name work", PROJ, OK),
    ("bfs / -maxdepth 2 -name x", PROJ, OK),
    ("fd -d 2 plan ~", PROJ, OK),
    ("fd --max-depth=1 plan /", PROJ, OK),
    ("rg --max-depth 1 foo ~", PROJ, OK),
    ("tree -L 2 ~", PROJ, OK),
    ("find / -maxdepth 3 -name x", PROJ, B),
    # --- non-recursive or no walk: allowed ---
    ("ls /", PROJ, OK),
    ("ls -la ~", PROJ, OK),
    ("ls -lh /var/tmp", PROJ, OK),
    ("grep foo ~/.bashrc", PROJ, OK),
    ("grep -n foo /etc/fstab", PROJ, OK),
    ("locate --regex 'monitoring.*plan'", PROJ, OK),
    ("plocate monitoring", HOME, OK),
    ("df -h /", PROJ, OK),
    ("ps aux | grep -i find", HOME, OK),
    ("journalctl -u x | rg foo", HOME, OK),
    ("cat x | grep foo", "/", OK),
    ("echo / | xargs ls", PROJ, OK),
    ("btrfs filesystem usage /", PROJ, OK),
    ("ncdu -f /var/tmp/claude/scan.json", HOME, OK),
    # --- quoted mentions and heredocs: allowed ---
    ("echo 'never run find / -name x'", PROJ, OK),
    ('git commit -m "block bfs -S dfs / walks" -- a.py', PROJ, OK),
    ("cat <<'EOF'\nfind / -name x\nEOF", PROJ, OK),
    ("rg 'find /' ~/.dotfiles", PROJ, OK),
    # --- ugrep and ug ---
    ("ugrep -G --ignore-files --hidden -I plan", "/var/tmp/claude", B),
    ("ug -l plan ~", PROJ, B),
    ("ugrep -r plan /", PROJ, B),
    ("ug -l plan", PROJ, OK),
    ("ugrep -2 plan ~", PROJ, OK),
    ("cat x | ugrep plan", HOME, OK),
    ("ugrep -d skip plan", "/var/tmp/claude", OK),
    ("ugrep -e '-1' /", PROJ, B),
    # --- Astra review findings ---
    ("command -v find", HOME, OK),
    ("rg -efoo /etc/hosts", HOME, OK),
    ("(cd /); find . -name x", PROJ, OK),
    ("ls -dR /", PROJ, OK),
    ("du 2" + ">/dev/null", HOME, B),
    ("du -sh . " + "> out.txt", PROJ, OK),
    ("bfs -f / -name x", PROJ, B),
    ("fd --search-path / --search-path /etc foo", PROJ, B),
    ("find / -maxdepth 2 -maxdepth 9 -name x", PROJ, B),
    ("find / -maxdepth 9 -maxdepth 1 -name x", PROJ, OK),
    # --- bypass ---
    ("find / -name x  # noqa: fs-walk", PROJ, OK),
    ("du -sh ~ # noqa: fs-walk", HOME, OK),
]

# Claude's own Grep and Glob tools: (tool, tool_input, cwd, should_block)
tool_cases = [
    ("Grep", {"pattern": "plan"}, "/var/tmp/claude", B),
    ("Grep", {"pattern": "plan"}, HOME, B),
    ("Grep", {"pattern": "plan", "path": "/"}, PROJ, B),
    ("Grep", {"pattern": "plan", "path": "~"}, PROJ, B),
    ("Grep", {"pattern": "plan", "path": "/home"}, PROJ, B),
    ("Grep", {"pattern": "plan", "path": HOME}, PROJ, B),
    ("Grep", {"pattern": "plan", "path": "/var"}, PROJ, B),
    ("Grep", {"pattern": "plan", "path": "/var/tmp/claude/"}, PROJ, B),
    ("Grep", {"pattern": "plan"}, PROJ, OK),
    ("Grep", {"pattern": "plan", "path": "/var/tmp/claude/task"}, HOME, OK),
    ("Grep", {"pattern": "plan", "path": f"{HOME}/.dotfiles"}, HOME, OK),
    ("Grep", {"pattern": "plan", "path": "/etc"}, "/", OK),
    ("Glob", {"pattern": "**/*plan*"}, HOME, B),
    ("Glob", {"pattern": "**/*.md", "path": "/"}, PROJ, B),
    ("Glob", {"pattern": f"{HOME}/**/*plan*"}, PROJ, B),
    ("Glob", {"pattern": "/var/tmp/claude/**/x.md"}, PROJ, B),
    ("Glob", {"pattern": "*.md"}, HOME, OK),
    ("Glob", {"pattern": "my-task/**/*.py"}, "/var/tmp/claude", OK),
    ("Glob", {"pattern": "work/**/*.py", "path": "~"}, PROJ, OK),
    ("Glob", {"pattern": "./**/*.py"}, HOME, B),
    ("Glob", {"pattern": "**/*.md"}, PROJ, OK),
    ("Glob", {"pattern": f"{HOME}/work/ifkb/**/*.md"}, HOME, OK),
    ("Glob", {"pattern": "**/*.md", "path": "/var/tmp/claude/task"}, HOME, OK),
]

syntax = subprocess.run(["bash", "-n", HOOK], capture_output=True, text=True)
if syntax.returncode != 0:
    print("FAIL hook is not valid bash:", syntax.stderr.strip())
    sys.exit(1)

fails = 0
for cmd, cwd, expect in cases:
    payload = json.dumps(
        {"tool_name": "Bash", "cwd": cwd, "tool_input": {"command": cmd}}
    )
    out = subprocess.run(["bash", HOOK], input=payload, capture_output=True, text=True)
    blocked = False
    if out.stdout.strip():
        decision = json.loads(out.stdout)["hookSpecificOutput"]["permissionDecision"]
        blocked = decision == "deny"
    if blocked != expect or out.returncode != 0:
        fails += 1
        print(f"FAIL block={blocked} expect={expect} rc={out.returncode}  {cmd!r}")
        if out.stderr.strip():
            print("   stderr:", out.stderr.strip()[:200])

for tool, tool_input, cwd, expect in tool_cases:
    payload = json.dumps({"tool_name": tool, "cwd": cwd, "tool_input": tool_input})
    out = subprocess.run(["bash", HOOK], input=payload, capture_output=True, text=True)
    blocked = bool(out.stdout.strip()) and (
        json.loads(out.stdout)["hookSpecificOutput"]["permissionDecision"] == "deny"
    )
    if blocked != expect or out.returncode != 0:
        fails += 1
        print(f"FAIL block={blocked} expect={expect}  {tool} {tool_input} cwd={cwd}")

total = len(cases) + len(tool_cases)
print(f"{total - fails}/{total} correct")
sys.exit(1 if fails else 0)
