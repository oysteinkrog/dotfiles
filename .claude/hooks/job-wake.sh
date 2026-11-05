#!/usr/bin/env bash
# PostToolUse hook on Bash, registered with asyncRewake. Wakes the agent when a
# `job submit --detach` job ends, so it need not poll. Logic in job-wake.py.
# Fast path: commands without a detached submit cost no Python. Fails open.
input=$(cat)
[[ $input == *'job submit'* && $input == *'--detach'* ]] || exit 0
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
printf '%s' "$input" | python3 "$here/job-wake.py"
rc=$?
((rc == 2)) && exit 2
exit 0
