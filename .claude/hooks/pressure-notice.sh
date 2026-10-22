#!/usr/bin/env bash
# PreToolUse hook for Bash: one line of notice when pressure-coordinator says
# memory pressure is at slow or pause, and the command looks like a build,
# test or heavy-build call. Best-effort advice only: it blocks nothing, and
# it does not see builds started by other tools or subagents.
# It reads its stdin (the hook JSON, at most 2 s) and the level file
# ~/.local/state/pressure/level. A level file more than 30 s old is ignored.
# Only tool_input.command is matched, decoded with jq when it is there, else
# with a small builtin decoder. The notice goes to the agent as
# additionalContext. About 2 ms when there is nothing to say, under 10 ms with
# jq when there is. Always exits 0.

input=
IFS= read -r -d '' -t 2 input || true

f=${XDG_STATE_HOME:-$HOME/.local/state}/pressure/level
line=
[[ -r $f ]] || exit 0
{ IFS= read -r line || [[ -n $line ]]; } 2>/dev/null < "$f" || exit 0
[[ $line =~ (^|[[:space:]])level=(slow|pause)([[:space:]]|$) ]] || exit 0
level=${BASH_REMATCH[2]}
[[ $line =~ (^|[[:space:]])updated=([0-9]{1,15})([[:space:]]|$) ]] || exit 0
age=$(( EPOCHSECONDS - 10#${BASH_REMATCH[2]} ))
(( age >= -5 && age <= 30 )) || exit 0

have_jq=
command -v jq >/dev/null 2>&1 && have_jq=1

# tool_input.command, decoded.
cmd=
if [[ -n $have_jq ]]; then
  cmd=$(jq -r '.tool_input.command // empty | strings' <<< "$input" 2>/dev/null) || cmd=
else
  # The first "command":"..." string. Handles \" \\ \/ \n \t \r; other
  # escapes stay as they are, which is enough to match command names.
  re='"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
  if [[ $input =~ $re ]]; then
    cmd=${BASH_REMATCH[1]}
    cmd=${cmd//\\\\/$'\x01'}
    cmd=${cmd//\\\"/\"}
    cmd=${cmd//\\\//\/}
    cmd=${cmd//\\n/$'\n'}
    cmd=${cmd//\\t/$'\t'}
    cmd=${cmd//\\r/$'\r'}
    cmd=${cmd//$'\x01'/\\}
  fi
fi
[[ -n $cmd ]] || exit 0

# Only for commands that start builds, tests or other heavy work.
[[ $cmd =~ (^|[^[:alnum:]_.-])(heavy-build|cargo|dotnet|build\.(sh|cmd)|run-tests\.sh|localbuild|cmake|ninja|msbuild|pytest|npm[[:space:]]+(run|test))([[:space:]]|$) ]] || exit 0

reason=
[[ $line =~ reason=\"([^\"]*)\" ]] && reason=${BASH_REMATCH[1]}
if [[ $level == pause ]]; then
  msg="Memory pressure is at pause ($reason). heavy-build starts only critical and high builds now. Finish your current step and do not start new builds, tests or subagents unless they are critical; running work is never stopped."
else
  msg="Memory pressure is at slow ($reason). heavy-build starts one new normal build at a time. Avoid starting extra builds, tests or subagents you do not need now."
fi
# JSON string escape with builtins (no second jq start): backslash and quote,
# then any control character (the reason comes from a file) as \u00XX.
out=${msg//\\/\\\\}
out=${out//\"/\\\"}
if [[ $out == *[[:cntrl:]]* ]]; then
  esc= c=
  for (( i = 0; i < ${#out}; i++ )); do
    c=${out:i:1}
    if [[ $c == [[:cntrl:]] ]]; then printf -v c '\\u%04x' "'$c"; fi
    esc+=$c
  done
  out=$esc
fi
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$out"
exit 0
