#!/usr/bin/env bash
# cass-mine.sh — Phase 0 cass automation.
#
# CASS-PLAYBOOK.md documents 13 canonical queries for Phase 1 archaeology.
# Currently agents copy-paste each one, run, stitch outputs. This script
# runs all 13 in one pass, deduplicates, and emits a single JSONL file.
#
# Usage: cass-mine.sh <target> <workspace>
# Output: <workspace>/cass_findings.jsonl
# Exit codes:
#   0 — success (cass installed, queries ran)
#   1 — cass not installed; emits empty cass_findings.jsonl + skip notice
#   64 — usage error

set -euo pipefail

usage() {
    echo "usage: cass-mine.sh <target> <workspace>" >&2
}

target="${1:-}"
workspace="${2:-}"
if [ -z "$target" ] || [ -z "$workspace" ]; then
    usage; exit 64
fi

[ -d "$workspace" ] || mkdir -p "$workspace"

out="$workspace/cass_findings.jsonl"
: > "$out"

# Skip if cass isn't installed; emit empty file + notice for downstream.
if ! command -v cass >/dev/null 2>&1; then
    echo "cass-mine: cass not installed; wrote empty $out" >&2
    echo '{"schema_version":"1.0","skipped":true,"reason":"cass not installed"}' > "$out"
    exit 1
fi

target_basename=$(basename "$target")

# The 13 canonical queries from PHASES.md / CASS-PLAYBOOK.md. Each query is a
# tuple of (id, label, query-string, jq-fields). We pipe each through
# `cass search --json --limit 20 --fields minimal` and project to a stable schema.
#
# `--robot` ensures stable JSON output (no TUI). `--limit 20` keeps each
# query bounded; the union across all 13 still yields a tractable set.
CASS_QUERIES=(
    "Q1|recurring stale lock|\"$target_basename stale lock\"|"
    "Q2|file corruption|\"$target_basename corruption\" OR \"$target_basename corrupt\"|"
    "Q3|migration failures|\"$target_basename migration\" failure|"
    "Q4|TOCTOU race|\"$target_basename race\" OR TOCTOU|"
    "Q5|deadlock|\"$target_basename deadlock\"|"
    "Q6|sqlite corruption|\"$target_basename sqlite\" corruption|"
    "Q7|jsonl drift|\"$target_basename jsonl\" tombstone OR drift|"
    "Q8|backup recovery|\"$target_basename undo\" OR \"$target_basename restore\"|"
    "Q9|crash recovery|\"$target_basename crash\" recovery|"
    "Q10|symlink TOCTOU|\"$target_basename symlink\" TOCTOU OR traversal|"
    "Q11|schema mismatch|\"$target_basename schema\" version mismatch|"
    "Q12|cache stale|\"$target_basename cache\" stale|"
    "Q13|user manual fix|\"$target_basename had to manually\"|"
)

count=0
for q in "${CASS_QUERIES[@]}"; do
    qid="${q%%|*}"
    rest="${q#*|}"
    qlabel="${rest%%|*}"
    rest="${rest#*|}"
    qstr="${rest%%|*}"
    # Use --json to get stable structured output. Suppress cass errors to
    # stderr so we don't trip the pipeline; the empty-results case is fine.
    raw=$(cass search "$qstr" --json --limit 20 --fields minimal 2>/dev/null || echo '{"hits":[]}')
    # Normalize each result with the query metadata. cass emits
    # {query, hits: [...], total_matches, ...}; we want the .hits array.
    echo "$raw" | jq -c --arg qid "$qid" --arg qlabel "$qlabel" --arg qstr "$qstr" '
        (.hits // .[]? // []) as $items
        | (if ($items | type) == "array" then $items else [$items] end)
        | .[]
        | {
            schema_version: "1.0",
            query_id: $qid,
            query_label: $qlabel,
            query_string: $qstr,
            session_path: (.source_path // .path // .session_path // null),
            line: (.line_number // .line // null),
            excerpt: (.text // .excerpt // .snippet // null),
            agent: (.agent // null),
            date: (.date // .timestamp // null)
          }
    ' 2>/dev/null >> "$out" || true
    new_count=$(wc -l < "$out")
    delta=$((new_count - count))
    count=$new_count
    echo "cass-mine: $qid '$qlabel' → $delta hits" >&2
done

# Deduplicate by the stable source location; the same hit may match multiple
# queries, and the query metadata itself would make full-line sort miss that.
dedup_tmp=$(mktemp "$workspace/cass_findings.dedup.XXXXXX")
if jq -c -s '
    reduce .[] as $item ({};
      (($item.session_path // "") + "\u0000"
       + (($item.line // "") | tostring) + "\u0000"
       + ($item.excerpt // "")) as $key
      | if has($key) then . else .[$key] = $item end
    )
    | .[]
  ' "$out" > "$dedup_tmp"; then
    mv "$dedup_tmp" "$out"
else
    echo "cass-mine: dedupe failed; leaving undeduped $out and temp $dedup_tmp" >&2
fi
count=$(wc -l < "$out")

echo "cass-mine: wrote $count findings to $out" >&2
