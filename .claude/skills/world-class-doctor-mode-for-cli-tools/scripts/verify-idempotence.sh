#!/usr/bin/env bash
# verify-idempotence.sh — Phase 5 idempotence test.
#
# Usage: verify-idempotence.sh <fm_id> [<tool>] [<fixture_root>]
# Asserts: <tool> doctor --fix; <tool> doctor --fix; second run reports
# actions_taken: 0 and exits 0.

set -euo pipefail
fm_id="${1:-}"
if [ -z "$fm_id" ]; then
    echo "usage: verify-idempotence.sh <fm_id> [<tool>] [<fixture_root>]" >&2
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
artifacts=$(mktemp -d)
trap 'echo "verify-idempotence: sandbox=$sandbox artifacts=$artifacts" >&2' EXIT

"$corrupt_sh" "$sandbox" >&2

# First fix. Per the canonical exit-code table, --fix legitimately exits
# 0 (all fixed) OR 2 (partial). The prior version refused exit-2, which
# masked partial-fix idempotence — i.e., a fixer that fixes some findings
# on run 1, leaves others, and reports actions_taken=0 on run 2 should be
# tested for idempotence on the SECOND run regardless of whether the first
# was 0 or 2.
rc1=0
( cd "$sandbox" && "$tool" doctor --fix --json ) > "$artifacts/run1.json" || rc1=$?
case "$rc1" in
    0|2) ;;
    *)
        echo "FAIL: first --fix exited unexpectedly with $rc1 (expected 0 or 2)" >&2
        cat "$artifacts/run1.json" >&2
        exit 1
        ;;
esac

# Second fix. The idempotent contract: actions_taken=0 AND exit=0 (or 1 if
# findings remain that the fixer can't address). Exit 2 on the SECOND run
# is a real failure — fixer is doing partial work each invocation, which
# isn't idempotent.
rc2=0
( cd "$sandbox" && "$tool" doctor --fix --json ) > "$artifacts/run2.json" || rc2=$?
case "$rc2" in
    0|1) ;;
    *)
        echo "FAIL: second --fix exited unexpectedly with $rc2 (expected 0 or 1; non-idempotent)" >&2
        cat "$artifacts/run2.json" >&2
        exit 1
        ;;
esac

# Strict missing-field handling: prior version used .get(...,-1) which then
# triggered the FAIL with a misleading "actions_taken=-1" message that
# masked the real cause (missing summary.actions_taken field).
actions=$(python3 -c '
import sys, json
try:
    obj = json.loads(sys.stdin.read())
except json.JSONDecodeError as e:
    print(f"PARSE_ERROR:{e}", file=sys.stderr); sys.exit(2)
summary = obj.get("summary")
if not isinstance(summary, dict):
    print("MISSING_FIELD:summary", file=sys.stderr); sys.exit(2)
n = summary.get("actions_taken")
if n is None:
    print("MISSING_FIELD:actions_taken", file=sys.stderr); sys.exit(2)
print(n)
' < "$artifacts/run2.json" 2>&1) || { echo "FAIL: second --fix output: $actions" >&2; exit 1; }

if [ "$actions" != "0" ]; then
    echo "FAIL: second --fix reported actions_taken=$actions (expected 0; not idempotent)" >&2
    exit 1
fi

echo "PASS: verify-idempotence.sh fm=$fm_id" >&2
trap - EXIT
