#!/usr/bin/env bash
# PreToolUse hook for Bash: one line of notice when pressure-coordinator says
# memory pressure is at slow or pause, and the command looks like a build,
# test or heavy-build call. It reads only its stdin and the level file
# ~/.local/state/pressure/level, uses shell builtins only (no jq, no python),
# never blocks and always exits 0. A level file more than 30 s old is ignored.
# The notice goes to the agent as additionalContext.

input=
IFS= read -r -d '' input || true

f=${XDG_STATE_HOME:-$HOME/.local/state}/pressure/level
[[ -r $f ]] || exit 0
IFS= read -r line < "$f" || [[ -n $line ]] || exit 0
[[ $line =~ (^|[[:space:]])level=(slow|pause)([[:space:]]|$) ]] || exit 0
level=${BASH_REMATCH[2]}
[[ $line =~ (^|[[:space:]])updated=([0-9]+) ]] || exit 0
(( EPOCHSECONDS - 10#${BASH_REMATCH[2]} <= 30 )) || exit 0

# Only for commands that start builds, tests or other heavy work.
[[ $input =~ (heavy-build|cargo[[:space:]]|dotnet[[:space:]]|build\.(sh|cmd)|run-tests\.sh|localbuild[[:space:]]|cmake|ninja|msbuild|pytest|npm[[:space:]]+(run|test)) ]] || exit 0

reason=
[[ $line =~ reason=\"([^\"]*)\" ]] && reason=${BASH_REMATCH[1]}
if [[ $level == pause ]]; then
  msg="Memory pressure is at pause ($reason). heavy-build starts only critical and high builds now. Finish your current step and do not start new builds, tests or subagents unless they are critical; running work is never stopped."
else
  msg="Memory pressure is at slow ($reason). heavy-build starts one new normal build at a time. Avoid starting extra builds, tests or subagents you do not need now."
fi
msg=${msg//\\/\\\\}
msg=${msg//\"/\\\"}
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$msg"
exit 0
