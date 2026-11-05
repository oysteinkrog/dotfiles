#!/usr/bin/env bash
# PreToolUse, PostToolUse and PostToolUseFailure hook on Bash, for Claude Code
# and Codex. Tells the agent how long a command took (over 30 s) and warns when
# it is in a slow build or test loop. The logic is in cmd-timing.py.
#
# Never blocks: always exits 0, and prints nothing on any error. The fast path
# is pure bash, so a short command that is not a build or test costs no Python.
# When in doubt it hands over to Python, which makes the real decision. A
# session with a pending detached job (job submit --detach) always goes to
# Python, which reports the job once it has ended.
input=$(cat)
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ $input == *'"hook_event_name":"PostToolUse'* || $input == *'"hook_event_name": "PostToolUse'* ]]; then
  # Claude Code sends duration_ms at the top level. Codex does not, so it
  # always goes to Python. Only trust the fast path when there is exactly one
  # duration_ms and the command comes before the tool output.
  # A start file from PreToolUse means a Codex call: any duration_ms in it
  # is nested in the tool output, so Python must handle it.
  state=${CMD_TIMING_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/cmd-timing}
  started=0
  if [[ $input =~ \"session_id\":[[:space:]]*\"([A-Za-z0-9_.-]+)\" ]]; then
    sid=${BASH_REMATCH[1]}
    # A detached jobd job of this session is waiting to be reported, so any
    # later call may be the one that sees it end.
    [[ -e $state/pending/$sid ]] && started=1
    if [[ $input =~ \"tool_use_id\":[[:space:]]*\"([A-Za-z0-9_.-]+)\" ]]; then
      [[ -e $state/start/$sid/${BASH_REMATCH[1]} ]] && started=1
    fi
  fi
  rest=${input#*\"duration_ms\"}
  if ((started == 0)) && [[ $rest != "$input" && $rest != *\"duration_ms\"* ]] &&
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
