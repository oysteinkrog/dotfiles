#!/usr/bin/env bash
# Phase 5: merge per-batch tsvs into triage.tsv; build user-facing decision table.
# Usage: merge-triage.sh <project>
set -euo pipefail

project="${1:?usage: merge-triage.sh <project>}"
cd "$project"
ws=".repo_janitor_workspace"

# Merge
out="$ws/triage.tsv"
{
    printf 'id\tverdict\tconfidence\tevidence\tproposed_dest\tgitignore_pattern\n'
    for batch in "$ws/triage/"batch_*.tsv; do
        [[ -f "$batch" ]] || continue
        tail -n +2 "$batch"
    done | sort -t$'\t' -k1,1n | awk -F'\t' '!seen[$1]++'
} > "$out"

# Apply user_overrides if present
if [[ -f "$ws/user_overrides.tsv" ]]; then
    # Simple last-wins merge
    python3 - <<PYEOF
import csv
overrides = {}
with open("$ws/user_overrides.tsv") as f:
    reader = csv.DictReader(f, delimiter='\t')
    for row in reader:
        overrides[row['id']] = row

rows = []
with open("$out") as f:
    reader = csv.DictReader(f, delimiter='\t')
    fields = reader.fieldnames
    for row in reader:
        if row['id'] in overrides:
            for k, v in overrides[row['id']].items():
                if v:
                    row[k] = v
        rows.append(row)

with open("$out", "w") as f:
    writer = csv.DictWriter(f, fieldnames=fields, delimiter='\t')
    writer.writeheader()
    writer.writerows(rows)
PYEOF
fi

# Build user-facing decision table
decision="$ws/triage_decision.md"
{
    total=$(tail -n +2 "$out" | wc -l)
    echo "## Audit summary: $total candidates in $project"
    echo ""

    # Group by verdict
    for verdict in keep-in-place protected move delete-and-gitignore delete-no-gitignore gitignore-only surface-to-user; do
        count=$(awk -F'\t' -v v="$verdict" 'NR>1 && $2==v' "$out" | wc -l)
        [[ "$count" -eq 0 ]] && continue
        echo "### Verdict: $verdict ($count)"
        echo ""
        echo "| id | path | confidence | evidence | dest |"
        echo "|----|------|-----------:|----------|------|"
        awk -F'\t' -v v="$verdict" 'NR>1 && $2==v {printf "| %s | %s | %s | %s | %s |\n", $1, $4, $3, $5, $6}' "$out" | head -50
        full=$(awk -F'\t' -v v="$verdict" 'NR>1 && $2==v' "$out" | wc -l)
        if [[ "$full" -gt 50 ]]; then
            echo "| ... | (showing first 50 of $full) | | | |"
        fi
        echo ""
    done
} > "$decision"

echo "merged → $out"
echo "decision table → $decision"
