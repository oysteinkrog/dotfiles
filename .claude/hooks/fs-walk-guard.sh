#!/usr/bin/env bash
# PreToolUse hook for Bash, Grep and Glob. Blocks a file walk over the whole
# disk or the whole home folder: find, bfs, fd, rgg, du, ncdu, tree, ls -R, rg,
# grep -r, ugrep, ug or btrfs filesystem du whose root is /, ~, /home, /var,
# /var/tmp or /var/tmp/claude (or no root while the cwd is one of those). The
# Grep tool and a Glob with `**` get the same rule for their `path`.
#
# Why: on 2026-10-27 a subagent ran `bfs -S dfs / -iname '*monitoring*plan*'`.
# With about 830 worktrees on disk it filled about 6 GiB of btrfs_inode and
# dentry slab. Reclaimable slab went from 2.5 to 9.3 GiB, free 32 KiB blocks
# fell to 96 (a KWin and NVIDIA risk) and the build queue paused. The same
# day a Grep tool call (ugrep) with cwd /var/tmp/claude did it again.
#
# Narrower folders, depth 1 or 2 (-maxdepth, fd -d, rg -d, tree -L) and a
# non-recursive `ls /` are allowed. Detection lives in fs-walk-detect.py; test
# matrix in fs-walk-guard.test.py. Run the tests after any change to either.
#
# Every failure of this hook's own parsing fails OPEN (allows the command).
# To bypass on purpose, append ` # noqa: fs-walk` to the command.

set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 0

payload=$(cat) || exit 0
tool=$(printf '%s' "$payload" | jq -r '.tool_name // "Bash"' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null) || cwd=

if [[ $tool == Grep || $tool == Glob ]]; then
  path=$(printf '%s' "$payload" | jq -r '.tool_input.path // ""' 2>/dev/null) || exit 0
  pattern=$(printf '%s' "$payload" | jq -r '.tool_input.pattern // ""' 2>/dev/null) || exit 0
  out=$(FS_WALK_TOOL="$tool" FS_WALK_PATH="$path" FS_WALK_PATTERN="$pattern" FS_WALK_CWD="$cwd" \
    timeout 10 python3 "$here/fs-walk-detect.py" 2>/dev/null) || exit 0
  [[ -n $out ]] || exit 0
  root=$(printf '%s' "$out" | head -1 | cut -f1)
  reason="BLOCKED: this $tool call searches all of $root. This disk has about 830 worktrees, and on 2026-10-27 searches like this filled GiBs of kernel inode cache and paused the build queue.
Set \`path\` to a named folder, such as ~/work/<repo> or /var/tmp/claude/<task>."
  jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}' 2>/dev/null || exit 0
  exit 0
fi

command=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0

# Cheap pre-filter so most Bash calls never start python.
if ! printf '%s' "$command" | grep -qE '(^|[^A-Za-z0-9_.-])(find|gfind|bfs|fd|fdfind|rgg|du|ncdu|tree|ls|rg|e?grep|fgrep|ugrep|ug|btrfs)([^A-Za-z0-9_.-]|$)'; then
  exit 0
fi
if [[ $command == *"noqa: fs-walk"* ]]; then
  exit 0
fi

out=$(FS_WALK_COMMAND="$command" FS_WALK_CWD="$cwd" \
  timeout 10 python3 "$here/fs-walk-detect.py" 2>/dev/null) || exit 0
[[ -n $out ]] || exit 0

root=$(printf '%s' "$out" | head -1 | cut -f1)
segment=$(printf '%s' "$out" | head -1 | cut -f2-)

reason="BLOCKED: \`$segment\` walks all of $root. This disk has about 830 worktrees, and on 2026-10-27 one walk like this filled 6 GiB of kernel inode cache and paused the build queue.
Use instead:
  rgg <name>                 file names, run inside a project folder
  fd <pattern> <folder>      a named folder such as ~/work/<repo> or /var/tmp/claude/<task>
  find <root> -maxdepth 2    a shallow look at a broad root
To bypass on purpose, append: # noqa: fs-walk"

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}' 2>/dev/null || exit 0
