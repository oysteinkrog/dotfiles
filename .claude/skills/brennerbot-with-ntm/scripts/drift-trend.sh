#!/usr/bin/env bash
# drift-trend.sh — Cross-session trend analysis of drift verdicts.
#
# Reads CROSS-SESSION-DRIFT-CATALOG.md from the skill's references/ directory,
# OR scans many workspaces for DRIFT-CHECK.md files, and reports patterns.
#
# Usage:
#   drift-trend.sh --skill-dir=<path>       # read from references/CROSS-SESSION-DRIFT-CATALOG.md
#   drift-trend.sh --scan-workspaces=<glob> # scan multiple workspaces

set -uo pipefail

SKILL_DIR=""
WORKSPACES_GLOB=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill-dir=*) SKILL_DIR="${1#*=}" ;;
    --scan-workspaces=*) WORKSPACES_GLOB="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$SKILL_DIR" ] && [ -z "$WORKSPACES_GLOB" ]; then
  echo "Usage: drift-trend.sh [--skill-dir=<path> | --scan-workspaces=<glob>]" >&2
  exit 2
fi

declare -A VERDICT_COUNTS

if [ -n "$SKILL_DIR" ]; then
  CATALOG="$SKILL_DIR/references/CROSS-SESSION-DRIFT-CATALOG.md"
  if [ ! -f "$CATALOG" ]; then
    echo "Catalog not found: $CATALOG" >&2
    echo "Falling back to workspace scan if --scan-workspaces also provided" >&2
  else
    # Parse table rows: | session | date | verdict | top regression | top improvement | lessons |
    while IFS='|' read -r _ _session _date verdict _regression _improvement _lessons _; do
      verdict=$(echo "$verdict" | tr -d ' ')
      [ -z "$verdict" ] && continue
      [ "$verdict" = "Verdict" ] && continue
      VERDICT_COUNTS[$verdict]=$((${VERDICT_COUNTS[$verdict]:-0} + 1))
    done < <(grep -E '^\|' "$CATALOG" | tail -n +3)
  fi
fi

if [ -n "$WORKSPACES_GLOB" ]; then
  for WS in $WORKSPACES_GLOB; do
    [ -d "$WS" ] || continue
    DC="$WS/deliverables/DRIFT-CHECK.md"
    [ -f "$DC" ] || continue
    # Use the same canonical pattern as scripts/export-timeline.sh — anchored at
    # line start, restricted to [a-z-] so that markdown-decorated verdicts like
    # `**DRIFT VERDICT: convergent**` don't capture the trailing `**`. Search the
    # whole file (not just head -3) because operators sometimes shift the verdict
    # line after a "Methodology"/"Summary" preamble.
    VERDICT=$(grep -m1 -oE '^DRIFT VERDICT:[[:space:]]*[a-z-]+' "$DC" 2>/dev/null \
      | awk -F: '{gsub(/^[[:space:]]+/,"",$2); print $2}')
    [ -z "$VERDICT" ] && continue
    VERDICT_COUNTS[$VERDICT]=$((${VERDICT_COUNTS[$VERDICT]:-0} + 1))
  done
fi

echo "=== Drift verdict trend ==="
echo ""

TOTAL=0
for v in "${!VERDICT_COUNTS[@]}"; do
  TOTAL=$((TOTAL + ${VERDICT_COUNTS[$v]}))
done

if [ "$TOTAL" = "0" ]; then
  echo "No drift verdicts found."
  exit 0
fi

for v in convergent divergent-improvement divergent-regression mixed; do
  COUNT=${VERDICT_COUNTS[$v]:-0}
  PCT=$(awk -v c="$COUNT" -v t="$TOTAL" 'BEGIN{ printf "%.0f", (c/t)*100 }')
  printf "  %-25s : %d (%d%%)\n" "$v" "$COUNT" "$PCT"
done

echo ""
echo "Total drift checks: $TOTAL"
echo ""

# Health assessment
HEALTHY_PCT=$(awk -v c="${VERDICT_COUNTS[convergent]:-0}" -v t="$TOTAL" 'BEGIN{ printf "%.0f", (c/t)*100 }')
REGRESSION_PCT=$(awk -v c="${VERDICT_COUNTS[divergent-regression]:-0}" -v t="$TOTAL" 'BEGIN{ printf "%.0f", (c/t)*100 }')

echo "## Health assessment"
echo ""
if [ "$HEALTHY_PCT" -ge 70 ]; then
  echo "  ✓ Methodology stable: ${HEALTHY_PCT}% convergent across $TOTAL sessions"
elif [ "$HEALTHY_PCT" -ge 50 ]; then
  echo "  ◐ Methodology mostly stable: ${HEALTHY_PCT}% convergent (acceptable)"
else
  echo "  ⚠ Methodology unstable: only ${HEALTHY_PCT}% convergent"
fi

if [ "$REGRESSION_PCT" -ge 30 ]; then
  echo "  ⚠ High regression rate (${REGRESSION_PCT}%) — review references/OPERATORS.md and ANTI-PATTERNS.md"
elif [ "$REGRESSION_PCT" -ge 15 ]; then
  echo "  ◐ Moderate regression rate (${REGRESSION_PCT}%) — monitor"
fi

echo ""
echo "Per CROSS-SESSION-LEARNING.md, persistent regression patterns warrant methodology updates."
