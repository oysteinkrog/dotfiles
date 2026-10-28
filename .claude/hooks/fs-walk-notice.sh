#!/usr/bin/env bash
# PreToolUse hook for Bash: tells a Claude session that fs-walk-reaper stopped one
# of its searches. The reaper appends to ~/.local/state/fs-walk-reaper/notice/<pid>,
# where <pid> is the pid in the session's claude-<pid>.scope. This hook walks up its
# own parent chain, finds the first pid that has a notice file, prints the text as
# additionalContext and removes the file. Best effort; always exits 0.

dir=${XDG_STATE_HOME:-$HOME/.local/state}/fs-walk-reaper/notice
[[ -d $dir ]] || exit 0
shopt -s nullglob
files=("$dir"/*)
(( ${#files[@]} )) || exit 0

pid=$$
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  f=$dir/$pid
  if [[ -f $f ]]; then
    msg=$(head -c 2000 "$f") && rm -f "$f"
    [[ -n $msg ]] || exit 0
    if command -v jq >/dev/null 2>&1; then
      jq -n --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
    fi
    exit 0
  fi
  pid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null) || exit 0
  [[ -n $pid && $pid -gt 1 ]] || exit 0
done
exit 0
