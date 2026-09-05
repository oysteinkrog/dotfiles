#!/usr/bin/env bash
set -euo pipefail
# conformance-harness.sh — compare two doctor implementations on the same fixtures.
#
# Used by upgrade-mode to compare the OLD doctor (snapshotted into baseline/
# by `subagents/baseline-snapshotter.md`) against the NEW doctor produced
# by Phase 4. A passing conformance run means: for every fixture, both
# doctors classify the same findings (modulo intentional new detectors)
# AND neither the OLD nor the NEW doctor regresses.
#
# Usage: conformance-harness.sh <doctor_a> <doctor_b> <fixture_root> [<workspace>]
#
# Args:
#   <doctor_a>     baseline doctor command (e.g., `./baseline/old-tool doctor`)
#   <doctor_b>     new doctor command (e.g., `./worktree/target/release/new-tool doctor`)
#   <fixture_root> directory containing per-FM fixture subdirs
#   <workspace>    workspace dir for output (default: cwd)
#
# Per fixture, runs `<doctor> --json` against a fresh sandbox produced by
# `corrupt.sh`, captures the JSON, and compares finding sets.
#
# Output: <workspace>/conformance_report.md + conformance_report.jsonl
# Exit:
#   0 if all fixtures' finding-sets match
#   1 if any fixture diverges (report explains)
#   64 usage

set -euo pipefail

usage() {
    echo "usage: conformance-harness.sh <doctor_a_cmd> <doctor_b_cmd> <fixture_root> [<workspace>]" >&2
    echo "  doctor commands are shell-like strings parsed into argv, e.g., './baseline/old-br doctor'" >&2
    echo "  shell operators such as pipes, redirects, and semicolons are not evaluated" >&2
}

doctor_a="${1:-}"
doctor_b="${2:-}"
fixture_root="${3:-}"
workspace="${4:-$(pwd)}"

if [ -z "$doctor_a" ] || [ -z "$doctor_b" ] || [ -z "$fixture_root" ]; then
    usage; exit 64
fi
[ -d "$fixture_root" ] || { echo "conformance-harness: $fixture_root not a directory" >&2; exit 66; }
mkdir -p "$workspace"

parse_doctor_cmd() {
    local cmd="$1"
    python3 - "$cmd" <<'PY'
import shlex
import sys

try:
    parts = shlex.split(sys.argv[1])
except ValueError as e:
    print(f"parse error: {e}", file=sys.stderr)
    sys.exit(2)

if not parts:
    print("empty doctor command", file=sys.stderr)
    sys.exit(2)

for part in parts:
    print(part)
PY
}

doctor_a_parts=$(parse_doctor_cmd "$doctor_a") \
    || { echo "conformance-harness: could not parse doctor_a command" >&2; exit 64; }
doctor_b_parts=$(parse_doctor_cmd "$doctor_b") \
    || { echo "conformance-harness: could not parse doctor_b command" >&2; exit 64; }
mapfile -t doctor_a_argv <<< "$doctor_a_parts"
mapfile -t doctor_b_argv <<< "$doctor_b_parts"

count_nonempty_lines() {
    awk 'NF { n += 1 } END { print n + 0 }'
}

extract_findings() {
    local json_path="$1"
    jq -r '
        if (.findings? | type) != "array" then
            error("missing findings array")
        else
            .findings
            | to_entries[]
            | if (.value.id | type) == "string" and .value.id != "" then
                .value.id
              else
                error("finding[" + (.key | tostring) + "] missing nonempty string id")
              end
        end
    ' "$json_path" | sort -u
}

report_md="$workspace/conformance_report.md"
report_jsonl="$workspace/conformance_report.jsonl"
: > "$report_jsonl"

cat > "$report_md" <<'EOF'
# Conformance Report — old doctor vs new doctor

| Fixture | A findings | B findings | A∩B | A only | B only | Verdict |
|---------|-----------:|-----------:|----:|-------:|-------:|---------|
EOF

total=0
diverged=0

for fm_dir in "$fixture_root"/*/; do
    [ -d "$fm_dir" ] || continue
    fm_id=$(basename "$fm_dir")
    corrupt_sh="$fm_dir/corrupt.sh"
    [ -x "$corrupt_sh" ] || continue
    total=$((total + 1))

    # Two parallel sandboxes — same corruption, two doctors.
    sandbox_a=$(mktemp -d "/tmp/conformance.${fm_id}.A.XXXXXX")
    sandbox_b=$(mktemp -d "/tmp/conformance.${fm_id}.B.XXXXXX")
    # If corrupt.sh fails we MUST mark the fixture rather than silently
    # running both doctors against a clean sandbox — that produces empty
    # finding sets on both sides and falsely verdicts "MATCH". Capture
    # exit codes; if either side fails to corrupt, skip the doctor calls
    # and emit a CORRUPT_FAILED verdict so the report flags it.
    rc_corrupt_a=0
    rc_corrupt_b=0
    "$corrupt_sh" "$sandbox_a" >/dev/null 2>&1 || rc_corrupt_a=$?
    "$corrupt_sh" "$sandbox_b" >/dev/null 2>&1 || rc_corrupt_b=$?

    # Run each doctor with --json, capture findings IDs.
    out_a="$sandbox_a/.conformance.a.json"
    out_b="$sandbox_b/.conformance.b.json"
    rc_a=0; rc_b=0
    json_error_a=""
    json_error_b=""
    findings_a=""
    findings_b=""
    if [ "$rc_corrupt_a" -eq 0 ] && [ "$rc_corrupt_b" -eq 0 ]; then
        ( cd "$sandbox_a" && "${doctor_a_argv[@]}" --json > "$out_a" 2>&1 ) || rc_a=$?
        ( cd "$sandbox_b" && "${doctor_b_argv[@]}" --json > "$out_b" 2>&1 ) || rc_b=$?

        err_a="$sandbox_a/.conformance.a.err"
        err_b="$sandbox_b/.conformance.b.err"
        findings_a=$(extract_findings "$out_a" 2>"$err_a") || {
            findings_a=""
            json_error_a=$(tr '\n' ' ' < "$err_a")
        }
        findings_b=$(extract_findings "$out_b" 2>"$err_b") || {
            findings_b=""
            json_error_b=$(tr '\n' ' ' < "$err_b")
        }
    fi

    only_a=$(comm -23 <(printf '%s\n' "$findings_a") <(printf '%s\n' "$findings_b") | grep -v '^$' || true)
    only_b=$(comm -13 <(printf '%s\n' "$findings_a") <(printf '%s\n' "$findings_b") | grep -v '^$' || true)
    both=$(comm -12 <(printf '%s\n' "$findings_a") <(printf '%s\n' "$findings_b") | grep -v '^$' || true)

    count_a=$(printf '%s\n' "$findings_a" | count_nonempty_lines)
    count_b=$(printf '%s\n' "$findings_b" | count_nonempty_lines)
    count_both=$(printf '%s\n' "$both" | count_nonempty_lines)
    count_only_a=$(printf '%s\n' "$only_a" | count_nonempty_lines)
    count_only_b=$(printf '%s\n' "$only_b" | count_nonempty_lines)

    verdict="MATCH"
    if [ "$rc_corrupt_a" -ne 0 ] || [ "$rc_corrupt_b" -ne 0 ]; then
        verdict="CORRUPT_FAILED"
        diverged=$((diverged + 1))
    elif [ "$rc_a" -ne 0 ] && [ "$rc_a" -ne 1 ]; then
        verdict="BAD_EXIT_A"
        diverged=$((diverged + 1))
    elif [ "$rc_b" -ne 0 ] && [ "$rc_b" -ne 1 ]; then
        verdict="BAD_EXIT_B"
        diverged=$((diverged + 1))
    elif [ -n "$json_error_a" ]; then
        verdict="INVALID_JSON_A"
        diverged=$((diverged + 1))
    elif [ -n "$json_error_b" ]; then
        verdict="INVALID_JSON_B"
        diverged=$((diverged + 1))
    elif [ "$count_only_a" -gt 0 ] || [ "$count_only_b" -gt 0 ]; then
        verdict="DIVERGE"
        diverged=$((diverged + 1))
    fi

    echo "| $fm_id | $count_a | $count_b | $count_both | $count_only_a | $count_only_b | $verdict |" >> "$report_md"

    # Per-fixture jsonl line.
    jq -nc \
        --arg fm "$fm_id" \
        --arg verdict "$verdict" \
        --argjson rc_a "$rc_a" \
        --argjson rc_b "$rc_b" \
        --argjson rc_corrupt_a "$rc_corrupt_a" \
        --argjson rc_corrupt_b "$rc_corrupt_b" \
        --arg both "$both" \
        --arg only_a "$only_a" \
        --arg only_b "$only_b" \
        --arg json_error_a "$json_error_a" \
        --arg json_error_b "$json_error_b" '{
            schema_version: "1.0",
            fm_id: $fm,
            verdict: $verdict,
            corrupt_a_exit: $rc_corrupt_a,
            corrupt_b_exit: $rc_corrupt_b,
            doctor_a_exit: $rc_a,
            doctor_b_exit: $rc_b,
            doctor_a_json_error: $json_error_a,
            doctor_b_json_error: $json_error_b,
            both_findings: ($both | split("\n") | map(select(. != ""))),
            only_a_findings: ($only_a | split("\n") | map(select(. != ""))),
            only_b_findings: ($only_b | split("\n") | map(select(. != "")))
        }' >> "$report_jsonl"
done

echo "" >> "$report_md"
echo "**Total: $total  |  Match: $((total - diverged))  |  Diverge: $diverged**" >> "$report_md"

echo "conformance-harness: $total fixtures, $diverged diverged" >&2
echo "wrote $report_md and $report_jsonl" >&2

if [ "$diverged" -gt 0 ]; then
    exit 1
fi
exit 0
