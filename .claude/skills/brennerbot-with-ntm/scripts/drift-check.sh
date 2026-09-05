#!/usr/bin/env bash
# drift-check.sh — Skeleton emitter for Phase 10 DRIFT-CHECK.md
#
# This script produces a skeleton with structural sections populated; the fresh agent
# (per MO-10-drift-check.md) fills in the rubric verdicts. The script does NOT make
# the verdict — that requires judgment.
#
# Usage: drift-check.sh [--workspace=<path>]

set -uo pipefail

WORKSPACE="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace=*) WORKSPACE="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

WORKSPACE_INPUT="$WORKSPACE"
if ! WORKSPACE="$(cd "$WORKSPACE_INPUT" 2>/dev/null && pwd)"; then
  echo "workspace not accessible: $WORKSPACE_INPUT" >&2
  exit 1
fi
cd "$WORKSPACE" || { echo "workspace not accessible: $WORKSPACE" >&2; exit 1; }
command -v br >/dev/null 2>&1 || { echo "br CLI not found" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "jq not found" >&2; exit 3; }
OUT="$WORKSPACE/deliverables/DRIFT-CHECK.md"
mkdir -p "$(dirname "$OUT")"

# Phase completion times
get_phase_time() {
  local n=$1
  if [ -f "$WORKSPACE/.brenner_workspace/phase_${n}_complete.flag" ]; then
    stat -c %y "$WORKSPACE/.brenner_workspace/phase_${n}_complete.flag" 2>/dev/null || \
      stat -f %Sm -t '%Y-%m-%dT%H:%M:%SZ' "$WORKSPACE/.brenner_workspace/phase_${n}_complete.flag" 2>/dev/null || \
      echo "unknown"
  else
    echo "(not complete)"
  fi
}

# Bead inventory
H_TOTAL=$(br list --label=hypothesis --json 2>/dev/null | jq '.issues | length' 2>/dev/null || echo 0)
H_REFUTED=$(br list --label=hypothesis --json 2>/dev/null | jq '[.issues[]? | select((.description // "") | test("(^|\\n)state:[[:space:]]*refuted([[:space:]]|$)"))] | length' 2>/dev/null || echo 0)
H_CONFIRMED=$(br list --label=hypothesis --json 2>/dev/null | jq '[.issues[]? | select((.description // "") | test("(^|\\n)state:[[:space:]]*confirmed([[:space:]]|$)"))] | length' 2>/dev/null || echo 0)
EV_TOTAL=$(br list --label=evidence --json 2>/dev/null | jq '.issues | length' 2>/dev/null || echo 0)

cat > "$OUT" <<EOF
DRIFT VERDICT: <FILL IN: convergent | divergent-improvement | divergent-regression | mixed>

# Drift Check — RS-<session_id>

**Audited at:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Auditor:** <FILL IN: name + model family + must NOT be one of original swarm panes>

---

## 1. Operators applied vs canonical

(Per references/OPERATORS.md, the 15 canonical Brenner operators)

| Operator | Phase fired | Evidence | Verdict |
|----------|-------------|----------|---------|
| ◊ Paradox-Hunt | 1 | <FILL IN: cite intake/question_of_record.md § Paradox> | applied / partial / skipped |
| ⊘ Level-Split | 3 (triage) | <FILL IN: cite H-*.category fields> | <verdict> |
| 𝓛 Recode | 3 (proposal) | <FILL IN: cite H-*.statement coordinate spec> | <verdict> |
| ≡ Invariant-Extract | 4 (investigation) | <FILL IN: cite EV-*.key_findings> | <verdict> |
| ✂ Exclusion-Test | 3 + 4 | <FILL IN: cite mandatory falsifier:> | <verdict> |
| ⟂ Object-Transpose | 4 | <FILL IN: cite EV-pack-*.md § Methodology> | <verdict> |
| ↑ Amplify | 4 + 5 | <FILL IN: cite T-*.expected_signal> | <verdict> |
| ⌂ Materialize | 3 | <FILL IN: cite expected_evidence:> | <verdict> |
| 🔧 DIY | 4 | <FILL IN: cite deliverables/scripts/*> | <verdict> |
| ⊞ Scale-Check | 4 + 7 | <FILL IN: cite assumption.calculation:> | <verdict> |
| 🤝 GAN | 5 | <FILL IN: cite DEBATE-* champions cross-family> | <verdict> |
| ΔE Exception-Quarantine | 4 + 7 | <FILL IN: cite anomaly_register> | <verdict> |
| † Theory-Kill | 5 | <FILL IN: cite refuted_by:> | <verdict> |
| ∿ Dephase | 7 + 10 | <FILL IN: cite consensus check> | <verdict> |
| ⊙ Productive-Ignorance | 2 | <FILL IN: cite phase0_scope_decision.md> | <verdict> |

For each \`partial\`/\`skipped\`/\`replaced\`, write a 1-paragraph note below:

<FILL IN>

---

## 2. Phase ordering vs canonical

| Phase | Started at | Completed at | Skipped? | Reordered? | Verdict |
|-------|-----------|--------------|----------|------------|---------|
| 1 | <FILL IN> | $(get_phase_time 1) | no | no | normal |
| 2 | <FILL IN> | $(get_phase_time 2) | no | no | normal |
| 3 | <FILL IN> | $(get_phase_time 3) | no | no | normal |
| 4 | <FILL IN> | $(get_phase_time 4) | no | no | <FILL IN: rounds run, kill_rate at exit> |
| 5 | <FILL IN> | $(get_phase_time 5) | no | no | normal |
| 6 | <FILL IN> | $(get_phase_time 6) | no | no | <FILL IN: passes to converge> |
| 7 | <FILL IN> | $(get_phase_time 7) | no | no | <FILL IN: trio-rounds to converge> |
| 8 | <FILL IN> | $(get_phase_time 8) | no | no | normal |
| 9 | <FILL IN> | $(get_phase_time 9) | no | no | normal |
| 10 | <FILL IN> | (this run) | n/a | n/a | n/a |

Common deviations to check for and document below:

<FILL IN>

---

## 3. Marching-order modifications

For each MO-*.md template that was dispatched, was there deviation?

(The auditor reads session-logs/dispatch-*.log and cross-references with the canonical templates.)

<FILL IN list of deviations and rationale>

---

## 4. Convergence behavior

| Phase | Rounds run | Hard cap | Converged? | Reason if not |
|-------|-----------|----------|------------|---------------|
| 4 | <FILL IN> | 6 | <FILL IN: yes / no> | <FILL IN if no> |
| 6 | <FILL IN> | 4 | <FILL IN> | <FILL IN if no> |
| 7 | <FILL IN> | 4 | <FILL IN> | <FILL IN if no> |

---

## 5. Evidence + bead invariants

Bead inventory at audit time:
- Hypotheses (total): $H_TOTAL  (refuted: $H_REFUTED, confirmed: $H_CONFIRMED)
- Evidence: $EV_TOTAL

Ran: \`./scripts/audit-bead-invariants.sh --all\`

Violations:

<FILL IN: paste audit-bead-invariants.sh output>

Each violation is a regression.

---

## 6. Improvements

(Each must pass the Replacement Test per references/DRIFT-RUBRIC.md)

### I-001: <one-line summary>
- **Replaced:** <Brenner principle + § anchor>
- **Replacement:** <what we did instead>
- **Rationale:** <why>
- **Metric:** <number-bearing measurement>
- **Verdict:** improvement

(Add more I-NNN entries as found.)

---

## 7. Regressions

### R-001: <one-line summary>
- **Source:** <§-anchor>
- **Expected:** <canonical behavior>
- **Actual:** <what happened>
- **F-code:** <F-NNN>
- **Recommendation:** <fix for next session>

(Add more R-NNN entries as found.)

---

## 8. Lessons

### L-001: <update X.md to do Y>
- **Reason:** <which improvement / regression motivates this>
- **Change:** <specific edit to <reference-file>.md>
- **Owner:** operator commits this update before closing Phase 10.

(Mandatory: ≥1 lesson with associated references/ file update. Per F-1003 hard invariant.)
EOF

echo "Skeleton emitted: $OUT"
echo ""
echo "Next: a fresh general-purpose Agent fills in the <FILL IN> markers per MO-10-drift-check.md."
echo "DO NOT dispatch this to a swarm pane (per AP-O11)."
