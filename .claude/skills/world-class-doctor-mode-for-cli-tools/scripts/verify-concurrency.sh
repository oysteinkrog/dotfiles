#!/usr/bin/env bash
# verify-concurrency.sh — Phase 5 concurrency test.
#
# Usage: verify-concurrency.sh <fm_id> [<tool>] [<fixture_root>]
# Launches two `<tool> doctor --fix` simultaneously. Asserts exactly one wins
# (exit 0 / 2) and the other refuses with exit 5.

set -euo pipefail
fm_id="${1:-}"
if [ -z "$fm_id" ]; then
    echo "usage: verify-concurrency.sh <fm_id> [<tool>] [<fixture_root>]" >&2
    exit 64
fi
tool="${2:-${TOOL:-}}"
if [ -z "$tool" ]; then
    echo "error: provide <tool> as arg 2 or set TOOL env var" >&2
    exit 64
fi
fixture_root="${3:-tests/doctor_fixtures}"

corrupt_sh="$fixture_root/$fm_id/corrupt.sh"
[ -x "$corrupt_sh" ] || { echo "FAIL: $corrupt_sh missing" >&2; exit 1; }

sandbox=$(mktemp -d)
# Per-run artifact dir under the sandbox (not /tmp directly) so concurrent
# verify-concurrency runs in different contexts don't collide on world-writable
# predictable paths. Round-53 triangulation flagged the prior version's use of
# fixed /tmp/conc_a.json / /tmp/conc_b.json as a TOCTOU + cross-test race.
artifacts="$sandbox/.verify-concurrency"
mkdir -p "$artifacts"
trap 'echo "verify-concurrency: sandbox at $sandbox" >&2' EXIT

"$corrupt_sh" "$sandbox" >&2

# Launch both. Parens isolate cd from the parent shell.
( cd "$sandbox" && "$tool" doctor --fix --json > "$artifacts/conc_a.json" 2>&1 ) &
pid_a=$!
( cd "$sandbox" && "$tool" doctor --fix --json > "$artifacts/conc_b.json" 2>&1 ) &
pid_b=$!

a_exit=0
b_exit=0
wait $pid_a || a_exit=$?
wait $pid_b || b_exit=$?

# Exactly one of the two should be 0 or 2 (winner); the other 5.
winner=0
loser=0
for code in "$a_exit" "$b_exit"; do
    case "$code" in
        0|2) winner=$((winner + 1)) ;;
        5)   loser=$((loser + 1)) ;;
    esac
done

if [ "$winner" -ne 1 ] || [ "$loser" -ne 1 ]; then
    echo "FAIL: a_exit=$a_exit b_exit=$b_exit (expected one 0/2, one 5)" >&2
    cat "$artifacts/conc_a.json" "$artifacts/conc_b.json" >&2
    exit 1
fi

echo "PASS: verify-concurrency.sh fm=$fm_id" >&2
trap - EXIT
