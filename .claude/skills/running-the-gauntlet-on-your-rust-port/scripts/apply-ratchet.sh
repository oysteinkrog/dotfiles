#!/usr/bin/env bash
# apply-ratchet.sh — Compare current parity-score lower bound to ratchet
# state. Emit decision {Allow|Block|Quarantine|Waiver} + reason +
# required_evidence. Updates ratchet_state.json on Allow.
#
# USAGE:
#   apply-ratchet.sh <workspace> [--score <path>] [--state <path>]
#                                [--waiver <reason>]
#
# OUTPUT FILES:
#   <workspace>/reports/ratchet_decision.json
#   <workspace>/reports/ratchet_state.json (updated when decision=Allow)
#
# EXIT CODES:
#   0 — Allow
#   1 — Block (or Quarantine without waiver)
#   3 — usage error
#
# IDEMPOTENT: re-runs produce identical decision for identical inputs.

set -euo pipefail

usage() { sed -n '2,14p' "$0"; exit "${1:-3}"; }

WORKSPACE=""
SCORE_FILE=""
STATE_FILE=""
WAIVER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --score)  SCORE_FILE="$2"; shift 2;;
    --state)  STATE_FILE="$2"; shift 2;;
    --waiver) WAIVER="$2"; shift 2;;
    -h|--help) usage 0;;
    *)
      if [ -z "$WORKSPACE" ]; then WORKSPACE="$1"
      else echo "Unexpected arg: $1" >&2; usage
      fi
      shift;;
  esac
done

[ -n "$WORKSPACE" ] || usage
SCORE_FILE="${SCORE_FILE:-$WORKSPACE/reports/parity_score.json}"
STATE_FILE="${STATE_FILE:-$WORKSPACE/reports/ratchet_state.json}"
DECISION="$WORKSPACE/reports/ratchet_decision.json"

mkdir -p "$(dirname "$DECISION")"
[ -f "$SCORE_FILE" ] || { echo "ERROR: score file $SCORE_FILE missing" >&2; exit 1; }

python3 - "$SCORE_FILE" "$STATE_FILE" "$DECISION" "${WAIVER:-}" <<'PYTHON'
import json, os, sys, time
score_fp, state_fp, decision_fp, waiver = sys.argv[1:5]

with open(score_fp) as f: score = json.load(f)
current_lower = float(score.get("global_lower", 0.0))

state = None
if os.path.exists(state_fp):
    try:
        with open(state_fp) as f: state = json.load(f)
    except Exception:
        state = None

prev_lower = float(state.get("global_lower", 0.0)) if state else None
TOLERANCE = 1e-6  # drift threshold for "no movement"

decision = "Allow"
reason = ""
required_evidence = []

if prev_lower is None:
    decision = "Allow"; reason = "no prior baseline; seeding ratchet"
elif current_lower + TOLERANCE >= prev_lower:
    decision = "Allow"
    reason = f"lower bound {current_lower} >= prior {prev_lower}"
elif waiver:
    decision = "Waiver"
    reason = f"waiver granted: {waiver} (lower {current_lower} < prior {prev_lower})"
else:
    # If drop is small (<0.5%), quarantine; else block.
    drop = prev_lower - current_lower
    if drop < 0.005:
        decision = "Quarantine"
        reason = f"lower bound dropped by {drop:.6f} (within quarantine band 0.005)"
        required_evidence = [
            "produce per-category breakdown showing which category regressed",
            "run scripts/mine-ledger.sh to confirm not a known dead candidate",
            "attach FailureBundle for any new TrueDivergence",
        ]
    else:
        decision = "Block"
        reason = f"lower bound dropped by {drop:.6f} (>0.005 quarantine band)"
        required_evidence = [
            "perf or conformance regression must be identified, classified, and either fixed or waivered",
            "rerun scripts/compute-parity-score.sh after fix",
            "add ledger entry with retry-condition predicate if rejecting",
        ]

decision_out = {
    "schema_version": "gauntlet.ratchet_decision.v1",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "decision": decision,
    "reason":   reason,
    "required_evidence": required_evidence,
    "current_lower": current_lower,
    "previous_lower": prev_lower,
}
with open(decision_fp, "w") as f:
    json.dump(decision_out, f, indent=2, sort_keys=True)

print(json.dumps(decision_out, indent=2))

if decision == "Allow":
    new_state = dict(state or {})
    new_state.update({
        "schema_version": "gauntlet.ratchet_state.v1",
        "global_lower": current_lower,
        "updated_at":   decision_out["generated_at"],
        "source_score": score_fp,
    })
    with open(state_fp, "w") as f:
        json.dump(new_state, f, indent=2, sort_keys=True)

if decision in ("Block", "Quarantine"):
    sys.exit(1)
PYTHON
