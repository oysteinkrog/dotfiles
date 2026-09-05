#!/usr/bin/env bash
set -euo pipefail
# single-fm-rescore.sh — tight inner loop after fixing one FM.
#
# Currently a Phase-6 rescore is all-or-nothing. After an implementer fixes
# a single FM, the right inner loop is: run safety-harness for THAT FM,
# recompute its per-dimension scores, update scorecard.md from the existing
# rows + the one update. No full Phase-6 rerun.
#
# Usage:
#   single-fm-rescore.sh <fm_id> <workspace> [<tool>] [<fixture_root>]
#
# Args:
#   <fm_id>         e.g., fm-state_files-jsonl-tombstone-drift
#   <workspace>     workspace dir containing failure_mode_scores.jsonl
#   <tool>          falls back to TOOL env var
#   <fixture_root>  defaults to tests/doctor_fixtures
#
# Procedure:
#   1. Run scripts/run-safety-harness.sh for the single FM. Captures fresh
#      pass/fail per safety test → influences reversibility, idempotence,
#      crash-recovery, concurrency dimension scores.
#   2. Snapshot the existing failure_mode_scores.jsonl.
#   3. Filter out lines for this fm_id (i.e., drop the 10 rows for this FM).
#   4. Append fresh 10 rows for this FM with updated scores. The implementer
#      provides the score values via env vars or a small input file:
#        SINGLE_FM_SCORES=<key>=<val>,<key>=<val>...
#      where keys are the 10 dimensions. Missing keys retain their existing
#      values (the script reads the existing rows first as the baseline).
#   5. Re-render scorecard.md via scripts/scorecard.py render <workspace>.
#   6. Emit a one-line summary on stderr.
#
# Exit codes: 0 on success, 64 usage, 66 missing inputs, 1 if harness fails.

usage() {
    echo "usage: single-fm-rescore.sh <fm_id> <workspace> [<tool>] [<fixture_root>]" >&2
}

fm_id="${1:-}"
workspace="${2:-}"
tool="${3:-${TOOL:-}}"
fixture_root="${4:-tests/doctor_fixtures}"

if [ -z "$fm_id" ] || [ -z "$workspace" ]; then
    usage; exit 64
fi
[ -d "$workspace" ] || { echo "single-fm-rescore: $workspace not a directory" >&2; exit 66; }
[ -n "$tool" ] || { echo "single-fm-rescore: provide tool as arg 3 or TOOL env" >&2; exit 64; }

scores_file="$workspace/failure_mode_scores.jsonl"
[ -f "$scores_file" ] || { echo "single-fm-rescore: no $scores_file (Phase 6 not yet run)" >&2; exit 66; }

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Step 1: run safety harness for just this FM.
echo "single-fm-rescore: running safety harness for $fm_id" >&2
if ! "$SKILL_DIR/scripts/run-safety-harness.sh" "$fm_id" "$workspace" "$tool" "$fixture_root"; then
    echo "single-fm-rescore: safety harness FAILED for $fm_id; not rescoring" >&2
    exit 1
fi

# Step 2/3: snapshot + filter out existing rows for this fm_id.
backup_dir="$workspace/.single-fm-rescore-backups"
mkdir -p "$backup_dir"
ts=$(date +%Y%m%dT%H%M%S)
cp "$scores_file" "$backup_dir/failure_mode_scores.jsonl.$ts"

tmp_filtered=$(mktemp "$workspace/.fmscores.XXXXXX")
trap 'echo "single-fm-rescore: filtered score rows preserved at $tmp_filtered" >&2' EXIT

# Read existing rows; keep all NOT for this fm_id; collect existing row for
# this FM as the score baseline (we'll merge with SINGLE_FM_SCORES override).
# IMPORTANT: frequency and blast_radius can be EITHER numbers (1.8) OR string
# labels ("corrupts_state") per IO-CONTRACTS.md. We capture them as raw JSON
# values and pass through with --argjson so the type round-trips correctly.
declare -A existing_dim_scores
existing_frequency_json=""
existing_blast_json=""
while IFS= read -r line; do
    [ -z "$line" ] && continue
    rec_fm=$(echo "$line" | jq -r '.fm_id // ""' 2>/dev/null || echo "")
    if [ "$rec_fm" = "$fm_id" ]; then
        # Capture for baseline merge.
        dim=$(echo "$line" | jq -r '.dimension // ""')
        score=$(echo "$line" | jq -r '.score // 0')
        [ -n "$dim" ] && existing_dim_scores[$dim]=$score
        # Use jq -c (compact) on the raw VALUE so we preserve string-vs-number
        # typing. `1.8` round-trips as `1.8`; `"corrupts_state"` round-trips
        # as `"corrupts_state"`. Both are valid --argjson inputs.
        if [ -z "$existing_frequency_json" ]; then
            existing_frequency_json=$(echo "$line" | jq -c '.frequency // 1.0')
        fi
        if [ -z "$existing_blast_json" ]; then
            existing_blast_json=$(echo "$line" | jq -c '.blast_radius // 1.0')
        fi
    else
        echo "$line" >> "$tmp_filtered"
    fi
done < "$scores_file"

if [ "${#existing_dim_scores[@]}" -eq 0 ]; then
    echo "single-fm-rescore: $fm_id has no existing rows in $scores_file (was Phase 6 run for it?)" >&2
    exit 66
fi

# Step 4: parse SINGLE_FM_SCORES override (if set) and emit fresh 10 rows.
declare -A new_scores
for dim in "${!existing_dim_scores[@]}"; do
    new_scores[$dim]=${existing_dim_scores[$dim]}
done
if [ -n "${SINGLE_FM_SCORES:-}" ]; then
    IFS=',' read -ra pairs <<< "$SINGLE_FM_SCORES"
    for pair in "${pairs[@]}"; do
        k="${pair%%=*}"
        v="${pair#*=}"
        new_scores[$k]=$v
    done
fi

# Synthesize a stable run_id for THIS rescore. The prior approach derived
# run_id from a `find` over safety_harness.jsonl, then `basename ... .jsonl`,
# which produced the literal "safety_harness" — not a valid run_id. Use a
# `single-fm-rescore-<ISO>__<short-hash>` form so the row is traceable to
# this script invocation but distinguishable from a full-pass run-id.
rescore_iso=$(date -u +%FT%TZ | tr ':' '-')
rescore_hash=$(printf '%s|%s' "$fm_id" "$rescore_iso" | python3 -c '
import hashlib, sys
print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:6])
')
run_id="single-fm-rescore-${rescore_iso}__${rescore_hash}"

for dim in "${!new_scores[@]}"; do
    score=${new_scores[$dim]}
    jq -nc \
        --arg fm "$fm_id" \
        --arg dimension "$dim" \
        --argjson score "$score" \
        --arg run_id "$run_id" \
        --arg evidence_path "$workspace/safety_harness.jsonl" \
        --arg evidence_line_or_test "single-fm-rescore $(date -u +%FT%TZ)" \
        --argjson frequency "${existing_frequency_json:-1.0}" \
        --argjson blast_radius "${existing_blast_json:-1.0}" \
        '{
            schema_version: "1.0",
            fm_id: $fm,
            dimension: $dimension,
            score: $score,
            evidence_path: $evidence_path,
            evidence_line_or_test: $evidence_line_or_test,
            run_id: $run_id,
            frequency: $frequency,
            blast_radius: $blast_radius
        }' >> "$tmp_filtered"
done

mv "$tmp_filtered" "$scores_file"
trap - EXIT

# Step 5: re-render scorecard.md.
if "$SKILL_DIR/scripts/scorecard.py" render "$workspace" 2>&1 | tail -3; then
    echo "single-fm-rescore: re-rendered scorecard.md" >&2
else
    echo "single-fm-rescore: scorecard.py render failed; check workspace" >&2
fi

echo "single-fm-rescore: $fm_id rescored (${#new_scores[@]} dimensions)" >&2
exit 0
