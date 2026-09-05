#!/usr/bin/env bash
# cross-incident-pattern.sh — Detect patterns across multiple post-mortems
# Per references/POST-MORTEM-FORMALIZATION-PLAYBOOK.md cross-incident pattern detection.

set -uo pipefail

CATALOG="${1:-references/INCIDENT-PATTERN-CATALOG.md}"
SESSIONS_ROOT="${2:-${HOME}/brennerbot_sessions}"

if [ ! -d "$SESSIONS_ROOT" ]; then
    echo "[FATAL] No sessions root: $SESSIONS_ROOT" >&2
    exit 1
fi

# Find all completed post-mortems. Use null-delimited array; some session paths
# may contain spaces and `for r in $var` would split them apart.
declare -a POST_MORTEM_REPORTS=()
while IFS= read -r -d '' f; do
    POST_MORTEM_REPORTS+=("$f")
done < <(find "$SESSIONS_ROOT" -name 'POST-MORTEM-REPORT.md' -type f -print0 2>/dev/null)

if [ ${#POST_MORTEM_REPORTS[@]} -eq 0 ]; then
    echo "[INFO] No post-mortem reports found"
    exit 0
fi

NUM_REPORTS=${#POST_MORTEM_REPORTS[@]}
echo "Found $NUM_REPORTS post-mortem reports"

# Extract contributing factors per report. Use a dedicated variable name
# (NOT `TMPDIR`) so we don't clobber the standard TMPDIR env var that
# downstream tools may consult to decide where to put their own temp files.
# Keep the extracted factors: repo policy forbids file deletion, and retained
# extracts make cross-incident counts reproducible.
WORK_DIR="$(mktemp -d)"

declare -i REPORT_NUM=0
for report in "${POST_MORTEM_REPORTS[@]}"; do
    [ -f "$report" ] || continue
    REPORT_NUM=$((REPORT_NUM + 1))

    # Extract contributing-factors section (between "Contributing factors"
    # heading and the next "## " heading). The previous version had a
    # `!/^## Contributing/` exclusion in the close rule — that was dead
    # code (rule 1 already consumes the entry heading via `next`, so rule 2
    # never sees it) AND would have actively misbehaved if a non-canonical
    # post-mortem ever used a second `## Contributing X` heading later: that
    # second heading would fail to close the section. The simpler form below
    # is correct in both cases.
    awk '
        /^## Contributing factors/ { flag=1; next }
        flag && /^## / { flag=0 }
        flag { print }
    ' "$report" > "$WORK_DIR/factors-$REPORT_NUM.txt"
done

factor_counts() {
    awk -F'|' '
        NF >= 3 {
            factor = $2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", factor)
            if (factor == "" || factor == "Factor" || factor ~ /^-+$/) next
            print factor
        }
    ' "$WORK_DIR"/factors-*.txt 2>/dev/null \
        | sort | uniq -c | sort -rn
}

# Aggregate factor types (extract "Factor" column from markdown table):
echo ""
echo "## Top contributing-factor patterns (across $NUM_REPORTS post-mortems)"

COUNTS="$(factor_counts || true)"
if [ -n "$COUNTS" ]; then
    printf '%s\n' "$COUNTS" | head -10
else
    echo "[INFO] No contributing-factor table rows found"
fi

# Detect 3+ recurrence (pattern threshold):
echo ""
echo "## Patterns with 3+ recurrences (consider promoting to canonical)"

RECURRENT="$(printf '%s\n' "$COUNTS" | awk '$1 >= 3 {print $0}' || true)"
if [ -n "$RECURRENT" ]; then
    printf '%s\n' "$RECURRENT"
else
    echo "[INFO] No factor has reached the 3+ recurrence threshold"
fi

echo ""
echo "## Existing patterns in catalog"
if [ -f "$CATALOG" ]; then
    EXISTING="$(grep -E '^## Pattern P-' "$CATALOG" 2>/dev/null | head -10 || true)"
    if [ -n "$EXISTING" ]; then
        printf '%s\n' "$EXISTING"
    else
        echo "[INFO] No existing Pattern P-* headings found in $CATALOG"
    fi
else
    echo "[INFO] No catalog at $CATALOG; create one when ≥3 patterns surface"
fi
