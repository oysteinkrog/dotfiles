#!/usr/bin/env bash
# PreToolUse, PostToolUse and PostToolUseFailure hook on Bash, for Claude Code
# and Codex. Tells the agent how long a command took (over 30 s) and warns when
# it is in a slow build or test loop. The logic is in cmd-timing.py.
#
# Never blocks: always exits 0, and prints nothing on any error. The fast path
# is pure bash, so a short command that is not a build or test costs no Python.
input=$(cat)
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ $input == *'"hook_event_name":"PostToolUse'* || $input == *'"hook_event_name": "PostToolUse'* ]]; then
  # Claude Code sends duration_ms. Codex does not, so it always goes to Python.
  if [[ $input =~ \"duration_ms\":[[:space:]]*([0-9]+) ]]; then
    ms=${BASH_REMATCH[1]}
    cmdpart=${input%%\"tool_response\"*}
    if (( ms < 30000 )) && ! [[ $cmdpart =~ (cargo|dotnet|heavy-build|job\ |build|test|make|ninja|pytest|gradle|mvn|xcodebuild|bazel) ]]; then
      exit 0
    fi
  fi
fi
printf '%s' "$input" | python3 "$here/cmd-timing.py" 2>/dev/null
exit 0
