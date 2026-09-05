#!/usr/bin/env bash
# closer-respond.sh — Submit a closer's defense response for one bead.
#
# Usage:
#   closer-respond.sh <bead-id> <evidence-file>
#                                [--audit-dir <path>]
#                                [--note "<inline note>"]
#
# What it does:
#   - Resolves the audit dir (defaults to <project>/beads_compliance_audit/
#     under the project's git root).
#   - Locates the latest pass dir under passes/.
#   - Copies <evidence-file> to <pass-dir>/beads/<bead-id>/closer_response.md
#     (overwriting any prior response — a closer can iterate).
#   - If --note is supplied, prepends it as a markdown blockquote.
#   - Records the submission in <audit-dir>/closer_responses.jsonl with a
#     timestamp + closer identity (from $USER or $LOGNAME).
#   - The closer-defender subagent (subagents/closer-defender.md) reads this
#     file in Phase 8.5 and either accepts the defense (re-score upward) or
#     rejects (Phase 9 proceeds as normal).
#
# Exit codes:
#   0  response submitted; orchestrator will pick it up at next defense round
#   2  invalid arguments / target bead-dir not found
#   3  evidence-file unreadable
#
# A closer can be either a human or an AI agent. Either way, this script is
# the canonical write-side of the defense workflow described in
# references/CLOSER-DEFENSE.md.
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

BEAD_ID="${1:?bead-id required (try: closer-respond.sh --help)}"
EVIDENCE_FILE="${2:?evidence-file required (a markdown file with your response)}"
shift 2

AUDIT_DIR=""
NOTE=""

require_value() { if [ "$2" -lt 2 ]; then echo "ERROR: $1 requires a value" >&2; exit 2; fi; }
while [ $# -gt 0 ]; do
  case "$1" in
    --audit-dir) require_value "$1" "$#"; AUDIT_DIR="$2"; shift 2 ;;
    --note)      require_value "$1" "$#"; NOTE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -r "$EVIDENCE_FILE" ] || { echo "ERROR: cannot read $EVIDENCE_FILE" >&2; exit 3; }

# Resolve audit dir if not supplied: assume cwd is inside the project repo,
# walk to git root, then look for <project>/beads_compliance_audit/.
if [ -z "$AUDIT_DIR" ]; then
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
  [ -n "$PROJECT_ROOT" ] || { echo "ERROR: not inside a git repo and no --audit-dir given" >&2; exit 2; }
  AUDIT_DIR="$PROJECT_ROOT/beads_compliance_audit"
fi
[ -d "$AUDIT_DIR" ] || { echo "ERROR: audit dir not found: $AUDIT_DIR" >&2; exit 2; }

# Locate latest pass dir.
LATEST_PASS="$(ls -1d "$AUDIT_DIR/passes"/*/ 2>/dev/null | sort | tail -1)"
[ -n "$LATEST_PASS" ] || { echo "ERROR: no passes/ subdirs in $AUDIT_DIR — has the audit ever run?" >&2; exit 2; }

BEAD_DIR="${LATEST_PASS%/}/beads/$BEAD_ID"
[ -d "$BEAD_DIR" ] || { echo "ERROR: bead '$BEAD_ID' not found in $LATEST_PASS — was it audited?" >&2; exit 2; }

OUT="$BEAD_DIR/closer_response.md"
{
  echo "# Closer defense for \`$BEAD_ID\`"
  echo ""
  echo "_Submitted: $(date -u +%Y-%m-%dT%H:%M:%SZ) by ${USER:-${LOGNAME:-unknown}}_"
  echo ""
  if [ -n "$NOTE" ]; then
    echo "> **Note:** $NOTE"
    echo ""
  fi
  echo "## Evidence"
  echo ""
  cat "$EVIDENCE_FILE"
} > "$OUT"

# Append to audit-dir-level log (one JSON object per submission).
LOG="$AUDIT_DIR/closer_responses.jsonl"
jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg bead "$BEAD_ID" \
  --arg user "${USER:-${LOGNAME:-unknown}}" \
  --arg pass "$(basename "$LATEST_PASS")" \
  --arg evidence "$EVIDENCE_FILE" \
  '{ts: $ts, bead_id: $bead, user: $user, pass: $pass, evidence_file: $evidence}' \
  >> "$LOG"

echo "✓ Submitted defense for $BEAD_ID"
echo "  Pass:     $(basename "$LATEST_PASS")"
echo "  Written:  $OUT"
echo "  Logged:   $LOG"
echo ""
echo "Next: the closer-defender subagent will read closer_response.md in Phase 8.5"
echo "and either accept (score moves up) or reject (Phase 9 proceeds as normal)."
exit 0
