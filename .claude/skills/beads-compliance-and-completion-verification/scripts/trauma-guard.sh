#!/usr/bin/env bash
# trauma-guard.sh — Detect repeat-mistake patterns by the same agent / session
# across many audit passes. Surfaces the top sloppy sessions with intervention
# recommendations.
#
# Usage:
#   trauma-guard.sh <audit-dir>
#
# Output (stdout):
#   trauma_report.md content
#
# Also writes <audit-dir>/trauma_report.md.
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

AUDIT_DIR="${1:?audit dir required}"
[ -d "$AUDIT_DIR/passes" ] || { echo "no passes/ in $AUDIT_DIR" >&2; exit 2; }

OUT="$AUDIT_DIR/trauma_report.md"
SESSIONS_TMP="$(mktemp)"
FC_TMP="$(mktemp)"
THEATER_TMP="$(mktemp)"
# Retain tmp aggregation inputs on exit. They are useful diagnostics when a
# trauma report looks wrong, and this repo forbids agents from deleting files.

PASS_DIRS=()
while IFS= read -r d; do PASS_DIRS+=("$d"); done < <(ls -1d "$AUDIT_DIR/passes"/*/ 2>/dev/null | sort)
N_PASSES="${#PASS_DIRS[@]}"
if [ "$N_PASSES" -lt 2 ]; then
  echo "# Trauma Report — insufficient history (only $N_PASSES pass(es))" > "$OUT"
  cat "$OUT"
  exit 0
fi

# Aggregate session → (closed_count, false_closed_count, top_theater_category)
# across every pass.
for pdir in "${PASS_DIRS[@]}"; do
  inv="$pdir/inventory.jsonl"
  rpt="$pdir/REPORT.md"
  [ -f "$inv" ] || continue

  # Per-pass: session → count of closed beads
  jq -r 'select(.status == "closed") | .closed_by_session // empty' "$inv" 2>/dev/null \
    | awk 'NF' >> "$SESSIONS_TMP"

  # Per-pass: false-closed bead IDs from REPORT.md
  if [ -f "$rpt" ]; then
    awk '
      /^## False-closed list/ {flag=1; next}
      /^## / && flag {flag=0}
      flag && /^\| `[a-z]/ {print}
    ' "$rpt" | grep -oE '`[a-z][a-z0-9_]*-[a-z0-9_]+(-[a-z0-9_]+|\.[0-9]+)*`' | tr -d '`' \
      | while read -r fc_id; do
          # Look up this bead's closed_by_session
          sess=$(jq -r --arg id "$fc_id" 'select(.id == $id) | .closed_by_session // empty' "$inv")
          [ -n "$sess" ] && echo "$sess" >> "$FC_TMP"
        done
  fi

  # Aggregate top theater categories per session
  for bdir in "$pdir/beads"/*/; do
    show="$bdir/show.json"
    theater="$bdir/theater.json"
    [ -f "$show" ] && [ -f "$theater" ] || continue
    sess=$(jq -r '.closed_by_session // empty' "$show")
    [ -n "$sess" ] || continue
    jq -r --arg s "$sess" '.findings[] | select(.severity == "BLOCKING" or .severity == "MAJOR")
                          | "\($s)\t\(.category)"' "$theater" 2>/dev/null \
      >> "$THEATER_TMP"
  done
done

# Tabulate
{
  echo "# Trauma Report"
  echo "Audit dir: \`$(realpath "$AUDIT_DIR")\`"
  echo "Spans $N_PASSES audit passes."
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Top sessions by false-closed count"
  echo
  echo "| Session ID | Total closed | False-closed | Rate | Top theater pattern | Intervention |"
  echo "|------------|-------------:|-------------:|-----:|---------------------|--------------|"

  # Get top 20 sessions by false-closed count.
  # IMPORTANT: `var=$(grep -c PATTERN FILE 2>/dev/null || echo 0)` is a bug —
  # `grep -c` ALWAYS prints "0" to stdout and exits 1 when no matches, so the
  # `|| echo 0` then ALSO prints "0", concatenating to "0\n0". The result fails
  # `[ "$var" -gt 0 ]` arithmetic. Use the assignment-level `||` form instead,
  # which only runs the fallback if the assignment chain fails.
  while read -r sess; do
    [ -n "$sess" ] || continue
    total=$(grep -cFx "$sess" "$SESSIONS_TMP" 2>/dev/null) || total=0
    fc=$(grep -cFx "$sess" "$FC_TMP" 2>/dev/null) || fc=0
    # Sanitize — must be a non-negative integer.
    [[ "$total" =~ ^[0-9]+$ ]] || total=0
    [[ "$fc" =~ ^[0-9]+$ ]] || fc=0
    [ "$total" -gt 0 ] || total=1
    rate=$(( fc * 100 / total ))
    top_cat=$(awk -F'\t' -v s="$sess" '$1==s {print $2}' "$THEATER_TMP" \
              | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
    top_cat="${top_cat:-no-theater-data}"
    case "$top_cat" in
      unimplemented_macro|stub_in_implementation) intervention="Retrain prompt: forbid todo!() / unimplemented!() before close" ;;
      trivial_assertion|skipped_test) intervention="Pre-merge gate on assertion-quality" ;;
      mock_where_forbidden) intervention="Pre-merge gate on no-mocks rule" ;;
      anomaly_apologetic_close|anomaly_wip_close_reason) intervention="Lint close_reason; reject hedge phrases" ;;
      anomaly_batch_close) intervention="Pre-commit hook: max 3 closes per 5 min" ;;
      sleep_as_fake_work) intervention="Lint production code: forbid sleep/setTimeout" ;;
      api_501_stub) intervention="Pre-merge gate: 501 returns block close" ;;
      *) intervention="Manual review: investigate session output quality" ;;
    esac
    printf '| `%s` | %d | %d | %d%% | %s | %s |\n' \
      "$sess" "$total" "$fc" "$rate" "$top_cat" "$intervention"
  done < <(sort "$FC_TMP" | uniq -c | sort -rn | head -20 | awk '{print $2}')

  echo
  echo "## Pattern summary across all sessions"
  echo
  echo "| Theater category | Total occurrences (BLOCKING+MAJOR) |"
  echo "|------------------|-----------------------------------:|"
  awk -F'\t' '{print $2}' "$THEATER_TMP" | sort | uniq -c | sort -rn | head -15 \
    | awk '{cat=""; for(i=2;i<=NF;i++) cat=cat (i>2?" ":"") $i; printf "| %s | %d |\n", cat, $1}'

  echo
  echo "## Long-horizon recommendation"
  echo
  TOTAL_FC=$(wc -l < "$FC_TMP" | tr -d ' ')
  TOTAL_CLOSED=$(wc -l < "$SESSIONS_TMP" | tr -d ' ')
  if [ "$TOTAL_CLOSED" -gt 0 ]; then
    PCT=$(( TOTAL_FC * 100 / TOTAL_CLOSED ))
    echo "Across $N_PASSES passes: ${TOTAL_FC} false-closed of ${TOTAL_CLOSED} total closures = **${PCT}%**."
  fi
  echo
  echo "Top sessions concentrate disproportionate false-closure volume."
  echo "Intervene on the top 3 first; expect ~50% reduction in next-pass false-closed count."

} | tee "$OUT" >&2

echo "$OUT"
