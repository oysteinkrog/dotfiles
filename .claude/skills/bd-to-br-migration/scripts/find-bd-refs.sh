#!/usr/bin/env bash
# Find files containing bd (beads) references that need migration to br
# Usage: ./find-bd-refs.sh [path]
#
# Exit codes:
#   0 - No bd references found (migration complete)
#   1 - bd references found (migration needed)

set -euo pipefail

path="${1:-.}"

if [[ ! -e "$path" ]]; then
    echo "ERROR: Path not found: $path" >&2
    exit 2
fi

count_nonempty_lines() {
    printf '%s\n' "$1" | awk 'NF{count++} END {print count + 0}'
}

echo "=== bd → br Migration Discovery ==="
echo "Scanning: $path"
echo ""

# Find files with bd command references
bd_files=$(grep -rl '`bd ' "$path" --include="*.md" 2>/dev/null || true)
if [[ -n "$bd_files" ]]; then
    echo "=== Files with \`bd\` command references ==="
    echo "$bd_files"
    echo ""
fi

# Find files with bd sync specifically
sync_files=$(grep -rl 'bd sync' "$path" --include="*.md" 2>/dev/null || true)
if [[ -n "$sync_files" ]]; then
    echo "=== Files with bd sync (critical to migrate) ==="
    echo "$sync_files"
    echo ""
fi

# Find files with bd-### issue IDs
id_files=$(grep -rl 'bd-[0-9]' "$path" --include="*.md" 2>/dev/null || true)
if [[ -n "$id_files" ]]; then
    echo "=== Files with bd-### issue IDs ==="
    echo "$id_files"
    echo ""
fi

# Count summary
bd_count=$(count_nonempty_lines "$bd_files")
sync_count=$(count_nonempty_lines "$sync_files")
id_count=$(count_nonempty_lines "$id_files")

echo "=== Summary ==="
echo "Files with bd commands: $bd_count"
echo "Files with bd sync: $sync_count"
echo "Files with bd-### IDs: $id_count"

# Unique files needing migration
all_files=$(printf '%s\n%s\n%s\n' "$bd_files" "$sync_files" "$id_files" | grep -v '^$' | sort -u || true)
total=$(count_nonempty_lines "$all_files")
echo ""
echo "Total unique files needing migration: $total"

if [[ "$total" -gt 0 ]]; then
    echo ""
    echo "=== Migration Recommendation ==="
    if [[ "$total" -le 5 ]]; then
        echo "Strategy: Sequential (1-5 files)"
        echo "Run: Apply THE EXACT PROMPT to each file"
    elif [[ "$total" -le 15 ]]; then
        echo "Strategy: 2 parallel subagents (~$((total/2)) files each)"
    elif [[ "$total" -le 50 ]]; then
        echo "Strategy: 5 parallel subagents (~$((total/5)) files each)"
    else
        echo "Strategy: 8 parallel subagents (~$((total/8)) files each)"
    fi
    exit 1
else
    echo ""
    echo "✓ No bd references found. Migration complete!"
    exit 0
fi
