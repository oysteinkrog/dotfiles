#!/usr/bin/env bash
# render-decision-memo.sh — Render decision memo (A7 archetype Phase 9 form).
#
# Reads from beads + distillations + disagreement_register; writes deliverables/DECISION-MEMO.md.
#
# Usage: render-decision-memo.sh [--workspace=<path>] [--out=<path>]

set -uo pipefail

WORKSPACE="."
OUT=""
CALLER_PWD="$PWD"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace=*) WORKSPACE="${1#*=}" ;;
    --out=*) OUT="${1#*=}" ;;
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

if [ -z "$OUT" ]; then
  OUT="$WORKSPACE/deliverables/DECISION-MEMO.md"
elif [[ "$OUT" != /* ]]; then
  OUT="$CALLER_PWD/$OUT"
fi
mkdir -p "$(dirname "$OUT")" || { echo "failed to create output directory: $(dirname "$OUT")" >&2; exit 1; }

# Extract question
QUESTION=$(awk '/^## Question/{getline; print; exit}' intake/question_of_record.md 2>/dev/null || echo "(see question_of_record.md)")

# Find the highest-confidence confirmed H (the recommendation)
CONFIRMED_H=$(br list --label=hypothesis --json 2>/dev/null | jq -r '
  def state_is($state):
    (.description // "") | test("(^|\\n)state:[[:space:]]*" + $state + "([[:space:]]|$)");
  def confidence_rank:
    ((((.description // "") | capture("(^|\\n)confidence:[[:space:]]*(?<c>[A-Za-z_-]+)")? | .c) // "speculative") | ascii_downcase) as $c
    | if $c == "high" then 3
      elif $c == "medium" then 2
      elif $c == "low" then 1
      else 0 end;
  [.issues[]? | select(state_is("confirmed")) | . + {__rank: confidence_rank}]
  | sort_by(-.__rank, .id)
  | .[0]? // empty
  | "\(.id): \(.title // "")"
' 2>/dev/null)

# Find disagreements (for dissent)
DISAGREEMENTS_FILE="distillations/disagreement_register.md"

if {
  echo "# Decision Memo — $(basename "$WORKSPACE")"
  echo ""
  echo "**Decision date:** $(date -u +%Y-%m-%d)"
  echo "**Question:** $QUESTION"
  echo ""
  echo "## Recommendation"
  echo ""
  if [ -n "$CONFIRMED_H" ]; then
    echo "**$CONFIRMED_H**"
  else
    echo "*(no confirmed hypothesis; see § Open uncertainties below)*"
  fi
  echo ""
  echo "## Reasoning"
  echo ""
  echo "(Operator: fill in 1-2 paragraphs of reasoning, citing specific EV-NNN beads from the supporting evidence pack.)"
  echo ""

  echo "## Key uncertainties"
  echo ""
  echo "(Hypotheses that survived investigation but didn't reach confirmed state — these are the open uncertainties the user should know about.)"
  br list --label=hypothesis --json 2>/dev/null | \
    jq -r '
      def state_is($state):
        (.description // "") | test("(^|\\n)state:[[:space:]]*" + $state + "([[:space:]]|$)");
      .issues[]? | select(state_is("deferred") or state_is("active")) | "- \(.id): \(.title // "")"
    ' 2>/dev/null \
    | head -10
  echo ""

  echo "## What would change the recommendation"
  echo ""
  echo "(Operator: list specific observations or events that, if they occurred, would shift the recommendation. This is the falsifier-equivalent for the decision itself.)"
  echo ""
  echo "- ..."
  echo "- ..."
  echo ""

  echo "## Dissenting opinions"
  echo ""
  echo "(Surfaced from disagreement_register.md — even if meta-synthesis chose one view, the dissent is preserved here.)"
  if [ -f "$DISAGREEMENTS_FILE" ]; then
    awk '/^## D-[0-9]+/{flag=1} flag==1 && /^## (Anti-pattern|Validation|---)$/{flag=0} flag==1' "$DISAGREEMENTS_FILE" 2>/dev/null \
      | head -50
  else
    echo "*(no disagreement register — Solo or Pair tier, single perspective)*"
  fi
  echo ""

  echo "## Risk register"
  echo ""
  echo "(Operator: list risks of acting on this recommendation. Per HANDBACK.md style, ≤3 risks with mitigations.)"
  echo ""
  echo "1. <risk> — <mitigation>"
  echo "2. <risk> — <mitigation>"
  echo "3. <risk> — <mitigation>"
  echo ""

  echo "## Reversibility"
  echo ""
  echo "(How easily can this decision be reversed if it turns out wrong?)"
  echo ""
  echo "- Reversibility class: <fully | partially | one-way>"
  echo "- Recovery cost if wrong: <hours | days | weeks | months>"
  echo "- Recovery procedure: <one-paragraph>"
  echo ""

  echo "## Confidence"
  echo ""
  echo "Per CONFIDENCE-SCORING.md tags applied:"
  echo "- Recommendation: <high | medium | low | speculative>"
  echo "- Reasoning chain: <strength>"
  echo "- Open uncertainty impact: <impact>"
  echo ""
  echo "## Provenance"
  echo ""
  echo "- Workspace: $WORKSPACE"
  echo "- Session: $(grep -m1 -oE 'RS-[0-9]{8}-[a-z0-9-]+' .brenner_workspace/phase0_scope_decision.md 2>/dev/null || echo '?')"
  echo "- Roster tier: $(grep -m1 'Roster tier' .brenner_workspace/phase0_scope_decision.md 2>/dev/null | awk '{print $NF}' || echo '?')"
  # Wall time: stat (GNU/BSD) or python3 fallback for the session start; date +%s for now.
  # ($SECONDS is bash time-since-shell-start, NOT current epoch — using date +%s instead.)
  SESSION_START_TS=$(stat -c %Y .brenner_workspace/phase0_scope_decision.md 2>/dev/null \
    || stat -f %m .brenner_workspace/phase0_scope_decision.md 2>/dev/null \
    || python3 -c "import os; print(int(os.path.getmtime('.brenner_workspace/phase0_scope_decision.md')))" 2>/dev/null \
    || echo 0)
  NOW_TS=$(date +%s)
  if [ "$SESSION_START_TS" -gt 0 ] 2>/dev/null; then
    WALL_MIN=$(( (NOW_TS - SESSION_START_TS) / 60 ))
    echo "- Wall time: ${WALL_MIN}min"
  else
    echo "- Wall time: (unknown)"
  fi
  echo ""
  echo "Rendered: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT"; then
  :
else
  echo "failed to write decision memo: $OUT" >&2
  exit 1
fi

echo "Decision memo emitted: $OUT (operator: fill in <FILL IN> sections)" >&2
