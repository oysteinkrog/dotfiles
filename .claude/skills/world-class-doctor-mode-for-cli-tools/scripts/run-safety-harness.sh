#!/usr/bin/env bash
set -euo pipefail
# run-safety-harness.sh — orchestrate all Phase 5 verify-*.sh scripts.
#
# Phase 5 currently requires the agent to invoke separate verifier scripts and
# stitch their outputs. This wrapper runs them all in sequence, captures
# results into a single safety_harness.jsonl, and emits a PASS/FAIL summary.
#
# Usage: run-safety-harness.sh <fm_id> <workspace> [<tool>] [<fixture_root>]
#
# Args:
#   <fm_id>         failure mode id (e.g., fm-state-files-jsonl-tombstone-drift)
#   <workspace>     workspace dir (writes safety_harness.jsonl here)
#   <tool>          optional, falls back to TOOL env var
#   <fixture_root>  optional, defaults to tests/doctor_fixtures
#
# For each safety test (reversibility, idempotence, crash-recovery,
# concurrency, metamorphic), invokes scripts/verify-<test>.sh, captures exit code,
# stdout/stderr excerpt, and duration. Appends one JSONL line per test.
#
# Exit:
#   0 if all tests passed
#   1 if any test failed
#   64 usage

set -euo pipefail

usage() {
    echo "usage: run-safety-harness.sh <fm_id> <workspace> [<tool>] [<fixture_root>]" >&2
}

fm_id="${1:-}"
workspace="${2:-}"
tool="${3:-${TOOL:-}}"
fixture_root="${4:-tests/doctor_fixtures}"

if [ -z "$fm_id" ] || [ -z "$workspace" ]; then
    usage; exit 64
fi
if [ -z "$tool" ]; then
    echo "run-safety-harness: provide <tool> as arg 3 or set TOOL env" >&2
    exit 64
fi

mkdir -p "$workspace"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
out="$workspace/safety_harness.jsonl"

# We APPEND so a workspace run across many FMs accumulates a single file.
# (Per OUTPUT-SCHEMA.md, safety_harness.jsonl is append-only across runs.)

tests=(reversibility idempotence crash-recovery concurrency metamorphic)
script_for() {
    case "$1" in
        reversibility)   echo "$SKILL_DIR/scripts/verify-undo.sh" ;;
        idempotence)     echo "$SKILL_DIR/scripts/verify-idempotence.sh" ;;
        crash-recovery)  echo "$SKILL_DIR/scripts/verify-crash-recovery.sh" ;;
        concurrency)     echo "$SKILL_DIR/scripts/verify-concurrency.sh" ;;
        metamorphic)     echo "$SKILL_DIR/scripts/verify-metamorphic.sh" ;;
    esac
}

started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
overall_ok=1
declare -A test_rc

run_one() {
    local test_name="$1"
    local script
    script=$(script_for "$test_name")
    local t0 t1 elapsed_ms rc=0
    t0=$(python3 -c 'import time; print(int(time.time()*1000))')
    local log
    log=$(mktemp /tmp/safety-harness."${fm_id}"."${test_name}".XXXXXX)
    if "$script" "$fm_id" "$tool" "$fixture_root" > "$log" 2>&1; then
        rc=0
    else
        rc=$?
        overall_ok=0
    fi
    t1=$(python3 -c 'import time; print(int(time.time()*1000))')
    elapsed_ms=$((t1 - t0))
    local last_line
    # `|| true` is load-bearing: when the test's last line is large enough
    # (>~64 KB pipe buffer), `head -c 200` closes its stdin before `tr`
    # finishes writing, SIGPIPEing tr. With `set -euo pipefail`, that
    # propagates 141 to the assignment and aborts the harness mid-run —
    # losing the JSONL line for this test and dropping us out of the for-loop.
    # Verified: `printf 'a' x 100000 | tr -d '\n' | head -c 10` exits 141.
    last_line=$(tail -1 "$log" | tr -d '\n' | head -c 200 || true)
    test_rc[$test_name]=$rc

    # Emit one JSONL line per test, matching IO-CONTRACTS.md schema.
    jq -nc \
        --arg schema_version "1.0" \
        --arg fm_id "$fm_id" \
        --arg test "$test_name" \
        --argjson exit_code "$rc" \
        --arg stderr_excerpt "$last_line" \
        --arg started_at "$started_at" \
        --argjson duration_ms "$elapsed_ms" '{
            schema_version: $schema_version,
            fm_id: $fm_id,
            test: $test,
            exit_code: $exit_code,
            stderr_excerpt: $stderr_excerpt,
            started_at: $started_at,
            duration_ms: $duration_ms
        }' >> "$out"
    echo "  $test_name: rc=$rc (${elapsed_ms}ms) — $last_line" >&2
}

echo "run-safety-harness: fm=$fm_id tool=$tool" >&2
for t in "${tests[@]}"; do
    run_one "$t"
done

# Summary line on stderr.
if [ "$overall_ok" -eq 1 ]; then
    echo "run-safety-harness: PASS fm=$fm_id (all ${#tests[@]} tests OK)" >&2
    exit 0
else
    failed=()
    for t in "${tests[@]}"; do
        [ "${test_rc[$t]}" -ne 0 ] && failed+=("$t")
    done
    echo "run-safety-harness: FAIL fm=$fm_id (failed: ${failed[*]})" >&2
    exit 1
fi
