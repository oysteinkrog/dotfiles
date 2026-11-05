#!/usr/bin/env bash
# PreToolUse, PostToolUse and PostToolUseFailure hook on Bash, for Claude Code
# and Codex. Tells the agent how long a command took (over 30 s) and warns when
# it is in a slow build or test loop. The logic is in cmd-timing.py.
#
# Never blocks: always exits 0, and prints nothing on any error. The fast path
# is pure bash, so a short command that is not a build or test costs no Python.
# When in doubt it hands over to Python, which makes the real decision.
input=$(cat)
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ $input == *'"hook_event_name":"PostToolUse'* || $input == *'"hook_event_name": "PostToolUse'* ]]; then
  # Claude Code sends duration_ms at the top level. Codex does not, so it
  # always goes to Python. Only trust the fast path when there is exactly one
  # duration_ms and the command comes before the tool output.
  rest=${input#*\"duration_ms\"}
  if [[ $rest != "$input" && $rest != *\"duration_ms\"* ]] &&
    [[ $input =~ \"duration_ms\":[[:space:]]*([0-9]+) ]]; then
    ms=${BASH_REMATCH[1]}
    cmdpart=${input%%\"tool_response\"*}
    if [[ $cmdpart == *\"tool_input\"* ]] && ((ms < 30000)) &&
      ! [[ $cmdpart =~ (cargo|dotnet|heavy-build|job|build|test|make|ninja|gradle|mvn|bazel|go\ |npm|pnpm|yarn|bun|tox|nox|cmake|swift|msbuild) ]]; then
      exit 0
    fi
  fi
fi
printf '%s' "$input" | python3 "$here/cmd-timing.py" 2>/dev/null
exit 0
