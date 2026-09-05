#!/usr/bin/env bash
# PreToolUse hook for Bash. Blocks `rg` invocations where `r` sits inside a
# clustered short-flag group, because ripgrep's `-r` is --replace.
#
# In grep, `-r` means --recursive, so `grep -rln PATTERN` is idiomatic and
# correct. In ripgrep, recursion is the default and `-r` takes an argument, so
# the same habit produces one of two silent failures depending on where the `r`
# lands in the cluster:
#
#   grep -rln alpha file   ->  file        (correct)
#   rg   -rln alpha file   ->  ln          (the cluster letters ARE the
#                                           replacement, printed per match)
#   rg   -nr  alpha file   ->  matches of "file"  (the `r` swallows the next
#                                           argument, so everything shifts)
#   rg   -l   alpha file   ->  file        (what was meant)
#
# Neither variant errors or warns. The output looks like plausible search
# results, which is why this keeps getting past review.
#
# A lone `-r X` and the long `--replace=X` are real replacement usage and are
# left alone. Append `# noqa: rg-replace` to bypass.
#
# Detection lives in rg-replace-detect.py; test matrix in
# rg-replace-guard.test.py. Run the tests after any change to either.

set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

payload=$(cat)
command=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')

# Explicit opt-out for the rare intentional attached-replacement case.
if printf '%s' "$command" | grep -q '# noqa: rg-replace'; then
  exit 0
fi

offender=$(RG_GUARD_COMMAND="$command" python3 "$here/rg-replace-detect.py" 2>/dev/null || true)

if [[ -z ${offender:-} ]]; then
  exit 0
fi

# Two distinct failures depending on where the `r` sits, and they are worth
# distinguishing because the second is harder to spot in the output.
consumed=${offender#*r}
if [[ -n $consumed ]]; then
  effect="parses as \`-r $consumed\`, so rg prints the literal text \"$consumed\" for every match instead of your results"
else
  effect="ends in \`-r\`, so rg takes your next argument as the replacement string and the one after it as the search pattern, shifting every argument by one"
fi

jq -n --arg flag "$offender" --arg effect "$effect" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("ripgrep '\''-r'\'' is --replace, not --recursive. `\($flag)` \($effect) — silently, with no error and no clue that anything went wrong. Recursion is already the default in rg, so an r inside a flag cluster is never what you want. Use the flags you actually meant (-l files-with-matches, -n line numbers, -i case-insensitive). For a real replacement write `--replace=X` or a lone `-r X`; to bypass this guard append `# noqa: rg-replace`.")
  }
}'
