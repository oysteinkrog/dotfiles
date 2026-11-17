#!/usr/bin/env bash
# PreToolUse hook for Bash. Blocks rg, grep, egrep, fgrep, ag, ack, find, fd, du
# (and the other walkers fs-walk-detect.py knows) over all of ~/.claude/projects
# or a parent of it (~/.claude, ~/.dotfiles/.claude, ~, /home, /), including a
# search with no path after a `cd` into one of those.
#
# Why: searching all session transcripts froze the desktop on 2026-11-04 and
# nearly again on 2026-11-16 23:23 (1.1 GB/s reads).
#
# Allowed: one session folder (~/.claude/projects/<dir>/...), one named file,
# and any command ending in `# noqa: transcript-search`. A mention inside a
# quoted string or heredoc (a commit message) is not a command and is allowed.
# Detection lives in transcript-search-detect.py; tests in
# transcript-search-guard.test.py. Fails OPEN on any parsing error.

set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 0
payload=$(cat) || exit 0
command=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null) || cwd=

if ! printf '%s' "$command" | grep -qE '(^|[^A-Za-z0-9_.-])(rg|e?grep|fgrep|ag|ack|find|gfind|fd|fdfind|du|ugrep|ug|bfs|tree)([^A-Za-z0-9_.-]|$)'; then
  exit 0
fi
[[ $command == *"noqa: transcript-search"* ]] && exit 0

out=$(TS_COMMAND="$command" TS_CWD="$cwd" timeout 10 python3 "$here/transcript-search-detect.py" 2>/dev/null) || exit 0
[[ -n $out ]] || exit 0
root=$(printf '%s' "$out" | head -1 | cut -f1)
segment=$(printf '%s' "$out" | head -1 | cut -f2-)

reason="BLOCKED: \`$segment\` searches all session transcripts (via $root). Searching all session transcripts froze the desktop on 2026-11-04 and nearly again on 2026-11-16 23:23 (1.1 GB/s reads).
Use \`cass search\` instead, or scope the search to one session folder (~/.claude/projects/<one-project-dir>/...) or one file.
To bypass on purpose, append: # noqa: transcript-search"

jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}' 2>/dev/null || exit 0
