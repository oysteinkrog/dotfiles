#!/usr/bin/env bash
# remediate.sh — Phase 9: reopen or create completion-debt beads for false-closed beads.
#
# Usage:
#   remediate.sh <project-path> <pass-dir> <policy>
#     policy: reopen | completion-debt | report-only
#
# Reads <pass-dir>/REPORT.md (false-closed list) and applies the policy.
# Writes <pass-dir>/remediation.md and <audit-dir>/remediation.md.
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

PROJECT="${1:?project path}"
PASS_DIR="${2:?pass dir}"
POLICY="${3:-completion-debt}"

DBS=( "$PROJECT/.beads"/*.db )
if [ -e "${DBS[0]}" ]; then
  DB="${DBS[0]}"
else
  DB=""
fi
AUDIT_DIR="$(cd "$PASS_DIR/../.." && pwd)"
PASS_NAME="$(basename "$PASS_DIR")"
REPORT="$PASS_DIR/REPORT.md"

if [ ! -f "$REPORT" ]; then
  echo "ERROR: missing audit report: $REPORT" >&2
  echo "       Run master-report.py for pass '$PASS_NAME' before remediation." >&2
  exit 2
fi
if [ ! -r "$REPORT" ]; then
  echo "ERROR: audit report is not readable: $REPORT" >&2
  exit 2
fi

# Fail-fast on missing DB for any policy that issues writes. Without this,
# `br --db "" reopen ...` and `br --db "" create ...` silently fail behind
# their `>/dev/null 2>&1` wrappers, producing a remediation.md full of
# "FAILED" rows with no explanation of *why* — the actual cause (no .db
# file under .beads/) is invisible. report-only is exempt because it never
# touches br.
if [ "$POLICY" != "report-only" ] && [ -z "$DB" ]; then
  echo "ERROR: no SQLite *.db file in $PROJECT/.beads/ — cannot apply policy '$POLICY'." >&2
  echo "       Re-run with policy=report-only, or fix the project's beads DB first." >&2
  exit 3
fi

# Extract false-closed bead IDs from REPORT.md. Reads only the False-closed
# section and captures the first backticked table cell on each row. This avoids
# baking a legacy bead-id grammar into remediation: scoped/domain IDs such as
# `auth.bd-42` or `[infra]bd-7` are already valid report rows and must be
# remediated exactly as written.
mapfile -t FC_IDS < <(awk '
  /^## False-closed list/ {flag=1; next}
  /^## / && flag {flag=0}
  flag && /^\|[[:space:]]*`/ {
    id = $0
    sub(/^\|[[:space:]]*`/, "", id)
    sub(/`.*/, "", id)
    if (id != "") print id
  }
' "$REPORT" | awk '!seen[$0]++')

REM="$PASS_DIR/remediation.md"
{
  echo "# Remediation — Pass $PASS_NAME"
  echo ""
  echo "## Policy: $POLICY"
  echo ""
  echo "## Actions"
  echo ""
  echo "| Original bead | Score | Action | New/Reopened ID | Status |"
  echo "|---------------|------:|--------|-----------------|--------|"
} > "$REM"

if [ "${#FC_IDS[@]}" -eq 0 ]; then
  echo "| (none — no false-closed beads to remediate) | - | - | - | - |" >> "$REM"
  cp "$REM" "$AUDIT_DIR/remediation.md"
  echo "No false-closed beads to remediate." >&2
  exit 0
fi

ACTED=0
for ID in "${FC_IDS[@]}"; do
  SC="$PASS_DIR/beads/$ID/scorecard.md"
  SHOW="$PASS_DIR/beads/$ID/show.json"
  [ -f "$SC" ] || continue
  [ -f "$SHOW" ] || continue
  # Portable score extraction: `grep -P` (PCRE) is GNU-only and absent from
  # BSD grep / macOS by default. `sed -nE` works on both. The pattern accepts
  # the canonical scorecard line `**Score: 700 / 1000**` and stops at the
  # first integer after `Score:`. `head -1` keeps multi-match defenses.
  SCORE="$(sed -nE 's/.*Score:[[:space:]]+([0-9]+).*/\1/p' "$SC" 2>/dev/null | head -1)"
  [ -n "$SCORE" ] || SCORE=0
  SCORE="${SCORE:-0}"
  [[ "$SCORE" =~ ^[0-9]+$ ]] || SCORE=0
  TITLE="$(jq -r '.title // "untitled"' "$SHOW")"
  TYPE="$(jq -r '.issue_type // "task"' "$SHOW")"
  # br can serialize issue_type as `{"Custom":"name"}` for custom types; flatten to a string.
  if [[ "$TYPE" == \{* ]]; then
    TYPE="$(printf '%s' "$TYPE" | jq -r 'to_entries[0].value // "task"')"
  fi
  PRI="$(jq -r '.priority // 2' "$SHOW")"
  [[ "$PRI" =~ ^[0-9]+$ ]] || PRI=2
  if [ "$SCORE" -lt 500 ] && [ "$PRI" -gt 0 ]; then
    PRI=$((PRI - 1))  # bump priority for severe theater
  fi

  # Extract verbatim "Missing items" section.
  MISSING="$(awk '/^## Missing items/,0' "$SC" | tail -n +2)"
  REASON="(closed at $(jq -r .closed_at "$SHOW"); reason: \"$(jq -r .close_reason "$SHOW")\")"

  case "$POLICY" in
    reopen)
      if br --db "$DB" reopen "$ID" >/dev/null 2>&1; then
        br --db "$DB" update "$ID" --status open >/dev/null 2>&1 || true
        echo "| \`$ID\` | $SCORE | Reopened original | \`$ID\` | open, P$PRI |" >> "$REM"
        ACTED=$((ACTED + 1))
      else
        echo "| \`$ID\` | $SCORE | reopen FAILED (likely tombstoned); falling back to completion-debt | - | - |" >> "$REM"
      fi
      ;;
    completion-debt)
      DESCRIPTION="Completion-debt for bead $ID, identified in audit pass $PASS_NAME.

Original bead $REASON
Audit score: $SCORE/1000
Scorecard: passes/$PASS_NAME/beads/$ID/scorecard.md (in audit dir)

$MISSING

## Acceptance criteria for THIS completion-debt bead

This bead is closed when EVERY missing item above has:
- A corresponding implementation cited at file:line in the close reason
- A corresponding test cited (passing) in the close reason
- The next audit pass scores the original bead ≥ threshold/1000"
      # br rejects values that begin with '-' on space-separated form. Use the
      # equals form for fields whose contents may start with '-' (descriptions,
      # acceptance_criteria) so multi-line bullet lists pass through cleanly.
      NEW_ID="$(br --db "$DB" create \
        --title "[completion-debt] $TITLE" \
        --type "$TYPE" \
        --priority "$PRI" \
        --parent "$ID" \
        --labels "audit-debt,audit-pass-$(date -u +%Y-%m-%d)" \
        --external-ref "audit-scorecard:passes/$PASS_NAME/beads/$ID/scorecard.md" \
        --description="$DESCRIPTION" \
        --json 2>/dev/null | jq -r '.id // empty')"
      if [ -n "$NEW_ID" ]; then
        # Populate the dedicated acceptance_criteria field so the next pass's
        # spec extractor finds it canonically (not just inside description).
        br --db "$DB" update "$NEW_ID" --acceptance-criteria="$MISSING" >/dev/null 2>&1 || true
        echo "| \`$ID\` | $SCORE | Created completion-debt bead | \`$NEW_ID\` | open, P$PRI |" >> "$REM"
        ACTED=$((ACTED + 1))
      else
        echo "| \`$ID\` | $SCORE | br create FAILED — manual creation needed | - | - |" >> "$REM"
      fi
      ;;
    report-only)
      echo "| \`$ID\` | $SCORE | Report only (no bead writes) | - | would be: open, P$PRI |" >> "$REM"
      ;;
    *)
      echo "ERROR: unknown policy: $POLICY" >&2
      exit 3
      ;;
  esac
done

# Sync and commit (only if anything was actually written and policy != report-only).
if [ "$POLICY" != "report-only" ] && [ "$ACTED" -gt 0 ]; then
  br --db "$DB" sync --flush-only >/dev/null 2>&1 || true
  if [ -d "$PROJECT/.git" ]; then
    git -C "$PROJECT" add .beads/ 2>/dev/null || true
    git -C "$PROJECT" commit -m "audit: remediation for pass $PASS_NAME (acted on $ACTED beads)" 2>/dev/null || true
    # Do NOT git push — that's the user's call.
  fi
fi

cp "$REM" "$AUDIT_DIR/remediation.md"
echo "Remediation complete: policy=$POLICY, acted on $ACTED beads, total false-closed=${#FC_IDS[@]}" >&2

# Hand off to Phase 9.5. We don't invoke the polish script here directly
# (run-pass.sh and the orchestrator subagents control timing); we just leave
# a marker so consumers know whether polish is owed. When ACTED == 0 (every
# row was a FAILED-create or report-only), polish has nothing to do.
if [ "$POLICY" != "report-only" ] && [ "$ACTED" -gt 0 ]; then
  echo "" >> "$REM"
  echo "## Phase 9.5 hand-off" >> "$REM"
  echo "" >> "$REM"
  echo "Phase 9 wrote $ACTED bead(s). The Phase 9.5 polish loop is MANDATORY before this audit pass is complete." >> "$REM"
  echo "" >> "$REM"
  echo "Run: \`scripts/polish-remediation-beads.sh '$PROJECT' '$PASS_DIR'\`" >> "$REM"
  echo "" >> "$REM"
  echo "Polish-loop log will be written to \`<pass-dir>/polish_log.md\`." >> "$REM"
  cp "$REM" "$AUDIT_DIR/remediation.md"
fi
