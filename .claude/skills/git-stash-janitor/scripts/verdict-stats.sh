#!/usr/bin/env bash
# verdict-stats.sh — Generate triage statistics for measurement / handoff.
#
# Reads triage.tsv; emits JSON + human-readable summary.

set -euo pipefail

PROJECT="${1:?Usage: verdict-stats.sh <project-path>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
TRIAGE="$WORKSPACE/triage.tsv"

if [[ ! -f "$TRIAGE" ]]; then
  echo "ERROR: $TRIAGE not found" >&2
  exit 1
fi

OUT_JSON="$WORKSPACE/verdict_stats.json"
OUT_MD="$WORKSPACE/verdict_stats.md"

# Compute distribution + confidence stats
awk -F'\t' '
  NR > 1 {
    counts[$2]++
    conf_sum += $3
    conf_n++
    # Use uninitialized-string check so a real 0 confidence is preserved
    # as the running min (vs. comparing against the magic value 0).
    if (min_conf == "" || $3 + 0 < min_conf + 0) min_conf = $3
    if (max_conf == "" || $3 + 0 > max_conf + 0) max_conf = $3
    apply_check[$5]++
  }
  END {
    printf "{\n"
    printf "  \"total\": %d,\n", conf_n
    printf "  \"verdict_distribution\": {\n"
    first = 1
    for (v in counts) {
      if (!first) printf ",\n"
      printf "    \"%s\": %d", v, counts[v]
      first = 0
    }
    printf "\n  },\n"
    printf "  \"confidence_mean\": %.3f,\n", (conf_n > 0 ? conf_sum/conf_n : 0)
    printf "  \"confidence_min\": %.3f,\n", (conf_n > 0 ? min_conf : 0)
    printf "  \"confidence_max\": %.3f,\n", (conf_n > 0 ? max_conf : 0)
    printf "  \"apply_check_distribution\": {\n"
    first = 1
    for (a in apply_check) {
      if (!first) printf ",\n"
      printf "    \"%s\": %d", a, apply_check[a]
      first = 0
    }
    printf "\n  }\n"
    printf "}\n"
  }
' "$TRIAGE" > "$OUT_JSON"

# Human-readable summary
{
  echo "# Verdict statistics"
  echo
  total=$(awk 'NR > 1' "$TRIAGE" | wc -l)
  echo "Total stashes triaged: $total"
  echo
  echo "## Distribution"
  echo
  awk -F'\t' 'NR > 1 {counts[$2]++} END {for (v in counts) print v "\t" counts[v]}' "$TRIAGE" \
    | sort -t $'\t' -k2,2 -rn \
    | awk -F'\t' -v total="$total" 'BEGIN {print "| verdict | count | %% |"; print "|---------|-------|----|"} \
        {pct = 100 * $2 / total; printf "| %s | %s | %.1f%% |\n", $1, $2, pct}'
  echo
  echo "## Confidence"
  echo
  # Match the JSON awk's uninitialized-string check (line 29) instead of using
  # `min == 0` as the "uninitialized" sentinel. A row with confidence 0.0 (e.g.,
  # a "diff-missing" row in triage.tsv legitimately gets confidence=0.0) would
  # otherwise be silently overwritten by the next row's higher value, so the
  # markdown summary would report the WRONG min while the JSON reports the
  # right one.
  awk -F'\t' '
    NR > 1 {
      sum += $3
      n++
      if (min == "" || $3 + 0 < min + 0) min = $3
      if (max == "" || $3 + 0 > max + 0) max = $3
    }
    END {
      if (n > 0) {
        printf "- Mean: %.3f\n- Min: %.3f\n- Max: %.3f\n- N: %d\n", sum/n, min, max, n
      } else {
        printf "- Mean: n/a\n- Min: n/a\n- Max: n/a\n- N: 0\n"
      }
    }
  ' "$TRIAGE"
  echo
  echo "## Health flags"
  echo
  unknown_pct=$(awk -F'\t' -v total="$total" 'BEGIN{n=0} NR > 1 && $2 == "unknown" {n++} END {printf "%.1f", (total > 0 ? 100*n/total : 0)}' "$TRIAGE")
  echo "- Unknown rate: ${unknown_pct}% (healthy: <5%; investigate if >10%)"

  partial_pct=$(awk -F'\t' -v total="$total" 'BEGIN{n=0} NR > 1 && $2 == "partially-novel" {n++} END {printf "%.1f", (total > 0 ? 100*n/total : 0)}' "$TRIAGE")
  echo "- Partial-novel rate: ${partial_pct}% (healthy: <10%; investigate if >20%)"

  conf_low_pct=$(awk -F'\t' -v total="$total" 'BEGIN{n=0} NR > 1 && $3 < 0.75 {n++} END {printf "%.1f", (total > 0 ? 100*n/total : 0)}' "$TRIAGE")
  echo "- Confidence-below-0.75 rate: ${conf_low_pct}% (consider triangulation if >15%)"
} > "$OUT_MD"

echo "wrote $OUT_JSON"
echo "wrote $OUT_MD"
echo
cat "$OUT_MD"
