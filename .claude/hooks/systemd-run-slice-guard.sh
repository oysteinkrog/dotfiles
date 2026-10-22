#!/usr/bin/env bash
# PreToolUse hook for Bash: one line of advice when a command runs
# `systemd-run` with `--user` but picks no slice (no --slice, no -p Slice=,
# no --property=Slice=). Such a unit lands in app.slice, which holds
# Oystein's apps at CPU weight 500, so a CPU-heavy job there competes with
# the desktop. On 2026-10-22 a bare `systemd-run --user` y-cruncher run with
# 32 threads pushed the load to about 700 and made the UI lag.
# Advice only: it never blocks. It reads its stdin (the hook JSON, at most
# 2 s), decodes tool_input.command with jq when it is there, else with a
# small builtin decoder. Always exits 0.

input=
IFS= read -r -d '' -t 2 input || true

# Cheap pre-filter before any decoding.
[[ $input == *systemd-run* ]] || exit 0

cmd=
if command -v jq >/dev/null 2>&1; then
  cmd=$(jq -r '.tool_input.command // empty | strings' <<< "$input" 2>/dev/null) || cmd=
else
  re='"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
  if [[ $input =~ $re ]]; then
    cmd=${BASH_REMATCH[1]}
    cmd=${cmd//\\\\/$'\x01'}
    cmd=${cmd//\\\"/\"}
    cmd=${cmd//\\n/$'\n'}
    cmd=${cmd//\\t/$'\t'}
    cmd=${cmd//$'\x01'/\\}
  fi
fi
[[ -n $cmd ]] || exit 0

[[ $cmd =~ (^|[^[:alnum:]_.-])systemd-run([[:space:]]|$) ]] || exit 0
[[ $cmd =~ (^|[[:space:]])--user([[:space:]]|$) ]] || exit 0
# A slice is chosen: --slice=X, --slice X, -p Slice=X, -pSlice=X, --property=Slice=X.
[[ $cmd =~ (^|[[:space:]])--slice([=[:space:]]) ]] && exit 0
[[ $cmd =~ (^|[[:space:]])(-p[[:space:]]*|--property[=[:space:]][[:space:]]*)[\"\']?Slice= ]] && exit 0
[[ $cmd == *'# noqa: systemd-run-slice'* ]] && exit 0

msg='systemd-run --user without --slice puts the job in app.slice, which is for Oystein'"'"'s apps (CPU weight 500), so a heavy job there slows the desktop. CPU-heavy or long jobs go through heavy-build or `systemd-run --user --slice=builds.slice ...`. Stress tests, benchmarks and canaries also need a CPU cap, for example `-p CPUQuota=800%`. Reason: on 2026-10-22 a bare systemd-run y-cruncher run (32 threads, load about 700) made the UI lag. Append `# noqa: systemd-run-slice` if app.slice is really meant.'
out=${msg//\\/\\\\}
out=${out//\"/\\\"}
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$out"
exit 0
