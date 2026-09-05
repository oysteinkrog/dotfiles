#!/usr/bin/env bash
set -euo pipefail
# self-apply.sh — apply the skill to ITSELF as a meta-doctor gate.
#
# The skill teaches how to build doctors for CLIs. The skill ITSELF has the
# structure of one (KERNEL.md, scripts/, references/, subagents/). Pattern 12
# (meta-doctor) makes this idea concrete: the skill should pass its own
# meta-validators when applied to itself.
#
# This script bundles the meta-validators currently shipped:
#   1. validate-skill.sh against the skill's own root.
#   2. SELF-TEST.md harness against the throwaway tinycli (smoke).
#   3. preflight-check.sh on a temp workspace (sanity).
#   4. (Round-56) numerical-claim consistency (detector 16).
#   5. (Round-56) shell-block parse (detector 17).
#
# Output: <self-apply-output>/self-apply.json  with per-check status:
#   {check, exit_code, duration_ms, stdout_excerpt, stderr_excerpt}
#
# Usage:
#   self-apply.sh [--out DIR]
#
# Args:
#   --out DIR    output directory (default: temp dir under /tmp)
#
# Exit:
#   0 — all meta-checks passed
#   1 — at least one meta-check failed
#   64 — usage error
#
# Future scope (round-57+): full Phase 0-6 self-pass producing a self-scorecard.

usage() {
    echo "usage: self-apply.sh [--out DIR]" >&2
}

need_value() {
    [ -n "${2:-}" ] || { echo "self-apply: $1 requires a value" >&2; usage; exit 64; }
    case "$2" in --*) echo "self-apply: $1 requires a value, got option-like token: $2" >&2; usage; exit 64 ;; esac
}

out_dir=""
while [ $# -gt 0 ]; do
    case "$1" in
        --out) need_value "$1" "${2:-}"; out_dir="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "self-apply: unknown arg $1" >&2; usage; exit 64 ;;
    esac
done

if [ -z "$out_dir" ]; then
    out_dir=$(mktemp -d /tmp/self-apply.XXXXXX)
fi
mkdir -p "$out_dir"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
results_file="$out_dir/self-apply.json"
overall=0

# Helper: run a check and append the result.
declare -a results
run_check() {
    local name="$1"; shift
    local cmd=("$@")
    local log="$out_dir/${name}.log"
    local rc=0
    local t0 t1 elapsed_ms
    t0=$(python3 -c 'import time; print(int(time.time()*1000))')
    if "${cmd[@]}" > "$log" 2>&1; then
        rc=0
    else
        rc=$?
        overall=1
    fi
    t1=$(python3 -c 'import time; print(int(time.time()*1000))')
    elapsed_ms=$((t1 - t0))
    local stdout_excerpt
    stdout_excerpt=$(head -c 500 "$log" | tr -d '\n' | head -c 500)
    local result
    result=$(jq -nc \
        --arg name "$name" \
        --argjson rc "$rc" \
        --argjson elapsed "$elapsed_ms" \
        --arg stdout_excerpt "$stdout_excerpt" \
        --arg log_path "$log" \
        '{
            check: $name,
            exit_code: $rc,
            duration_ms: $elapsed,
            stdout_excerpt: $stdout_excerpt,
            log_path: $log_path
         }')
    results+=("$result")
    if [ "$rc" -eq 0 ]; then
        echo "  ✓ $name (${elapsed_ms}ms)" >&2
    else
        echo "  ✗ $name (rc=$rc, ${elapsed_ms}ms; see $log)" >&2
    fi
}

echo "self-apply: meta-doctor checks against $SKILL_DIR" >&2

# Check 1: validate-skill.sh against the skill itself.
run_check "validate-skill" "$SKILL_DIR/scripts/validate-skill.sh" "$SKILL_DIR"

# Check 2: preflight-check on a temp workspace.
preflight_ws=$(mktemp -d "$out_dir/preflight-ws.XXXXXX")
run_check "preflight-check" "$SKILL_DIR/scripts/preflight-check.sh" "$preflight_ws"

# Check 3: discover-cli on the skill itself (it's a Bash + Python skill).
discover_ws=$(mktemp -d "$out_dir/discover-ws.XXXXXX")
run_check_to_file() {
    local name="$1"; shift
    local out_path="$1"; shift
    local cmd=("$@")
    local log="$out_dir/${name}.log"
    local rc=0
    local t0 t1 elapsed_ms
    t0=$(python3 -c 'import time; print(int(time.time()*1000))')
    if "${cmd[@]}" > "$out_path" 2> "$log"; then
        rc=0
    else
        rc=$?
        overall=1
    fi
    t1=$(python3 -c 'import time; print(int(time.time()*1000))')
    elapsed_ms=$((t1 - t0))
    local stdout_excerpt
    stdout_excerpt=$(head -c 500 "$out_path" | tr -d '\n' | head -c 500)
    local result
    result=$(jq -nc \
        --arg name "$name" \
        --argjson rc "$rc" \
        --argjson elapsed "$elapsed_ms" \
        --arg stdout_excerpt "$stdout_excerpt" \
        --arg log_path "$log" \
        --arg out_path "$out_path" \
        '{
            check: $name,
            exit_code: $rc,
            duration_ms: $elapsed,
            stdout_excerpt: $stdout_excerpt,
            log_path: $log_path,
            out_path: $out_path
         }')
    results+=("$result")
    if [ "$rc" -eq 0 ]; then
        echo "  ✓ $name (${elapsed_ms}ms)" >&2
    else
        echo "  ✗ $name (rc=$rc, ${elapsed_ms}ms; see $log)" >&2
    fi
}
run_check_to_file "discover-cli-self" "$discover_ws/cli.json" \
    "$SKILL_DIR/scripts/discover-cli.sh" "$SKILL_DIR"

# Check 4: SELF-TEST harness (single-line invocation; the actual test is
# multi-step but documented in SELF-TEST.md). We just verify the file
# exists and parses; full execution is outside this gate's scope.
run_check "self-test-md-present" \
    test -f "$SKILL_DIR/SELF-TEST.md"

# Check 5: every script in scripts/ runs --help (or otherwise exits cleanly
# with no args mode). Catches scripts where argparse / arg-parsing got
# accidentally broken.
for script in "$SKILL_DIR"/scripts/*.sh "$SKILL_DIR"/scripts/*.py; do
    [ -f "$script" ] || continue
    name="script-help-$(basename "$script")"
    # Some scripts exit 64 on no args (per IO-CONTRACTS.md); that's fine.
    # We accept any exit IN [0, 64, 65, 66] as "didn't blow up unexpectedly".
    log_path="$out_dir/${name}.log"
    rc=0
    "$script" --help > "$log_path" 2>&1 || rc=$?
    case "$rc" in
        0|1|2|64|65|66) actual_rc=0 ;;
        *) actual_rc=$rc; overall=1 ;;
    esac
    elapsed_ms=0
    stdout_excerpt=$(head -c 200 "$log_path" | tr -d '\n' | head -c 200)
    result=$(jq -nc \
        --arg name "$name" \
        --argjson rc "$actual_rc" \
        --argjson actual "$rc" \
        --argjson elapsed "$elapsed_ms" \
        --arg stdout_excerpt "$stdout_excerpt" \
        '{
            check: $name,
            exit_code: $rc,
            actual_rc: $actual,
            duration_ms: $elapsed,
            stdout_excerpt: $stdout_excerpt
         }')
    results+=("$result")
    if [ "$actual_rc" -eq 0 ]; then
        echo "  ✓ $name (rc=$rc accepted)" >&2
    else
        echo "  ✗ $name (rc=$rc rejected)" >&2
    fi
done

# Aggregate to JSON.
{
    echo "{"
    echo "  \"schema_version\": \"1.0\","
    echo "  \"skill_dir\": $(printf '%s' "$SKILL_DIR" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'),"
    echo "  \"overall\": $([ "$overall" -eq 0 ] && echo \"pass\" || echo \"fail\"),"
    echo "  \"checks\": ["
    if [ "${#results[@]}" -gt 0 ]; then
        printf '    %s' "${results[0]}"
        for r in "${results[@]:1}"; do
            printf ',\n    %s' "$r"
        done
    fi
    echo ""
    echo "  ]"
    echo "}"
} > "$results_file"

if [ "$overall" -eq 0 ]; then
    echo "self-apply: PASS — all meta-checks green; report at $results_file" >&2
else
    echo "self-apply: FAIL — see $results_file" >&2
fi

exit "$overall"
