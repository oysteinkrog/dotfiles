#!/usr/bin/env bash
# metrics-export.sh — Export the latest audit pass's KPIs as Prometheus
# textfile-collector format (one metric per line, key {labels} value).
#
# Usage:
#   metrics-export.sh <audit-dir> [output-path]
#
# Defaults:
#   output-path  /tmp/beads_audit.prom
#
# Typical cron line:
#   */30 * * * * /path/to/metrics-export.sh /audit/dir /var/lib/node_exporter/textfile_collector/beads_audit.prom
#
# Emitted metrics include: beads_audit_score_median, beads_audit_false_closed_count,
# beads_audit_total_beads, beads_audit_pass_age_seconds, beads_audit_theater_findings_total
# (with severity={BLOCKING,MAJOR,MINOR,NOTE,ADVISORY} label).
#
# Exits 0 on success, 1 if no passes / no manifest exist yet.
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

AUDIT_DIR="${1:?audit dir required}"
OUT="${2:-/tmp/beads_audit.prom}"

LATEST="$(find "$AUDIT_DIR/passes" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort | tail -1 || true)"
[ -n "$LATEST" ] || { echo "no passes" >&2; exit 1; }
MANIFEST="$LATEST/manifest.json"
[ -f "$MANIFEST" ] || { echo "no manifest in $LATEST" >&2; exit 1; }

PROJECT="$(jq -r .project_path "$MANIFEST")"
PASS_ID="$(basename "${LATEST%/}")"

emit_metric() {
  local name="$1" help="$2" mtype="${3:-gauge}" value="$4"
  printf '# HELP %s %s\n# TYPE %s %s\n%s{project="%s",pass_id="%s"} %s\n' \
    "$name" "$help" "$name" "$mtype" "$name" "$PROJECT" "$PASS_ID" "$value"
}

# Variant for labeled metrics (HELP/TYPE printed once per group). Used for the
# theater-findings histogram-style emission where the same metric carries a
# severity label per row — matches what `assets/grafana-dashboard.json`
# scrapes (`beads_audit_theater_findings_total{severity="BLOCKING"}` etc.).
emit_labeled() {
  local name="$1" severity="$2" value="$3"
  printf '%s{project="%s",pass_id="%s",severity="%s"} %s\n' \
    "$name" "$PROJECT" "$PASS_ID" "$severity" "$value"
}

# Counters / gauges
TOTAL=$(jq -r '.bead_counts.total_issues // .bead_counts.total // 0' "$MANIFEST")
CLOSED=$(jq -r '.bead_counts.closed_issues // 0' "$MANIFEST")
THRESHOLD=$(jq -r '.score_threshold // 700' "$MANIFEST")

# False-closed count from REPORT.md
FC=0
if [ -f "$LATEST/REPORT.md" ]; then
  FC=$(awk '
    /^## False-closed list/ {flag=1; next}
    /^## / && flag {flag=0; exit}
    flag && /^\| `[a-z]/ {n++}
    END {print n+0}
  ' "$LATEST/REPORT.md")
fi

# Score median + mean (compute from scorecards). Use portable `sed -nE`
# instead of `grep -hoP` (GNU PCRE) so the same script works on macOS BSD
# grep without forcing users to `brew install grep`. The `|| true` keeps
# us alive when the glob hits no scorecards (sed errors on the literal
# unexpanded pattern); $SCORES ends up empty and the median branch skips.
SCORES=$(sed -nE 's/.*Score:[[:space:]]+([0-9]+).*/\1/p' "$LATEST/beads"/*/scorecard.md 2>/dev/null || true)
MEDIAN=0
MEAN=0
SCORE_COUNT=0
if [ -n "$SCORES" ]; then
  MEDIAN=$(echo "$SCORES" | sort -n | awk '
    {a[NR]=$1}
    END {
      if (NR>0) print (NR%2==1) ? a[(NR+1)/2] : int((a[NR/2]+a[NR/2+1])/2);
      else print 0
    }')
  MEAN=$(echo "$SCORES" | awk '{s+=$1; n+=1} END {print (n>0 ? int(s/n) : 0)}')
  SCORE_COUNT=$(echo "$SCORES" | wc -l | tr -d ' ')
fi

# Convergence indicator
CONVERGED=$(jq -r '.convergence.is_converged // false' "$MANIFEST")
CONV_INT=$([ "$CONVERGED" = "true" ] && echo 1 || echo 0)

# Theater finding aggregates. The trailing `// 0` ensures we always emit a number
# even when (a) no theater.json files match the glob OR (b) the slurped array
# sums to null because every entry was null.
agg_severity() {
  local sev="$1"
  local out
  out=$(jq -s --arg k "$sev" '(map(.summary[$k] // 0) | add) // 0' \
        "$LATEST/beads"/*/theater.json 2>/dev/null) || out=0
  # Strip any trailing newline from jq output, default to 0 on empty.
  printf '%s' "${out:-0}" | tr -d '\n'
}
BLOCKING=$(agg_severity BLOCKING)
MAJOR=$(agg_severity MAJOR)
MINOR=$(agg_severity MINOR)

# Wall time (if recorded)
WALL=$(jq -r '.cost.wall_time_seconds // 0' "$MANIFEST")

# Pass age (seconds since pass_completed_at)
PASS_AGE=0
COMPLETED_AT=$(jq -r '.pass_completed_at // empty' "$MANIFEST")
if [ -n "$COMPLETED_AT" ]; then
  COMPLETED_S=$(date -d "$COMPLETED_AT" +%s 2>/dev/null || echo 0)
  if [ "$COMPLETED_S" -gt 0 ]; then
    PASS_AGE=$(( $(date +%s) - COMPLETED_S ))
  fi
fi

{
  emit_metric "beads_audit_total_beads"         "Total beads in inventory" gauge "$TOTAL"
  emit_metric "beads_audit_closed_beads"        "Closed beads" gauge "$CLOSED"
  # Renamed from `beads_audit_false_closed` to match (a) this script's
  # docstring at the top, (b) `assets/grafana-dashboard.json`'s scrape
  # expression. The old name was never queried by any shipped consumer.
  emit_metric "beads_audit_false_closed_count" "Closed beads scoring below threshold" gauge "$FC"
  emit_metric "beads_audit_score_threshold"     "Configured score threshold" gauge "$THRESHOLD"
  emit_metric "beads_audit_score_median"        "Median bead score, latest pass" gauge "$MEDIAN"
  emit_metric "beads_audit_score_mean"          "Mean bead score, latest pass" gauge "$MEAN"
  emit_metric "beads_audit_score_count"         "Number of beads scored in latest pass" gauge "$SCORE_COUNT"
  emit_metric "beads_audit_converged"           "1 if last two passes converged" gauge "$CONV_INT"
  # Replaced three separate metrics (theater_blocking/major/minor) with one
  # Prometheus-idiomatic metric carrying the severity label. The Grafana
  # dashboard scrapes `beads_audit_theater_findings_total{severity=...}`;
  # the old per-severity names left those panels empty.
  printf '# HELP %s %s\n# TYPE %s %s\n' \
    "beads_audit_theater_findings_total" "Theater findings, latest pass, by severity" \
    "beads_audit_theater_findings_total" "gauge"
  emit_labeled "beads_audit_theater_findings_total" "BLOCKING" "${BLOCKING:-0}"
  emit_labeled "beads_audit_theater_findings_total" "MAJOR"    "${MAJOR:-0}"
  emit_labeled "beads_audit_theater_findings_total" "MINOR"    "${MINOR:-0}"
  emit_metric "beads_audit_pass_wall_time_s"    "Wall time of latest pass in seconds" gauge "$WALL"
  emit_metric "beads_audit_pass_age_seconds"    "Seconds since latest pass completed" gauge "$PASS_AGE"
} > "${OUT}.tmp"
mv "${OUT}.tmp" "$OUT"

echo "Wrote $OUT" >&2
