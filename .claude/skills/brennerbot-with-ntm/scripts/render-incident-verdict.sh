#!/usr/bin/env bash
# render-incident-verdict.sh — Render INCIDENT-VERDICT.md (incident-investigation compressed loop).
#
# Usage: render-incident-verdict.sh [--workspace=<path>] [--out=<path>]

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
  OUT="$WORKSPACE/deliverables/INCIDENT-VERDICT.md"
elif [[ "$OUT" != /* ]]; then
  OUT="$CALLER_PWD/$OUT"
fi
mkdir -p "$(dirname "$OUT")" || { echo "failed to create output directory: $(dirname "$OUT")" >&2; exit 1; }

QUESTION=$(awk '/^## Question/{getline; print; exit}' intake/question_of_record.md 2>/dev/null || echo "(see question_of_record.md)")

# Confirmed root cause = highest-confidence non-refuted H
CONFIRMED_H=$(br list --label=hypothesis --json 2>/dev/null | \
  jq -r '
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
    | [.id, (.title // ""), (.description // "")]
    | @tsv
  ' 2>/dev/null)
H_ID=""
H_TITLE=""

# Get phase0_scope_decision.md mtime in epoch seconds. GNU stat uses `-c %Y`,
# BSD/macOS stat uses `-f %m`; fall back to date+ls if neither matches.
START_TIME=$(stat -c %Y .brenner_workspace/phase0_scope_decision.md 2>/dev/null \
  || stat -f %m .brenner_workspace/phase0_scope_decision.md 2>/dev/null \
  || echo 0)
NOW=$(date +%s)
DURATION_MIN=$(( (NOW - START_TIME) / 60 ))

if {
  echo "# Incident Verdict — $(basename "$WORKSPACE")"
  echo ""
  echo "**Incident:** $QUESTION"
  echo "**Investigation duration:** ~${DURATION_MIN} min"
  echo "**Verdict timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  echo "## Verdict"
  echo ""
  if [ -n "$CONFIRMED_H" ]; then
    IFS=$'\t' read -r H_ID H_TITLE _H_DESC <<< "$CONFIRMED_H"
    echo "**Root cause: $H_ID — $H_TITLE**"
  else
    echo "*(no confirmed root cause — see open hypotheses below)*"
  fi
  echo ""
  echo "Confidence: <high | medium | low> (operator to confirm)"
  echo ""

  echo "## Evidence"
  echo ""
  echo "### Confirmed via:"
  if [ -n "$H_ID" ]; then
    br list --label=evidence --json 2>/dev/null | \
      jq -r --arg h "$H_ID" 'def refs($name): ((try ((.description // "") | capture($name + ":[[:space:]]*\\[(?<ids>[^\\]]*)\\]").ids) catch "") | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))); .issues[]? | select(refs("supports") | index($h)) | "- \(.id): \(.title // "")"' 2>/dev/null \
      | head -5
  fi
  echo ""

  echo "### Killed alternatives:"
  br list --label=hypothesis --json 2>/dev/null | \
    jq -r '
      def state_is($state):
        (.description // "") | test("(^|\\n)state:[[:space:]]*" + $state + "([[:space:]]|$)");
      def field($name):
        (((.description // "") | capture("(^|\\n)" + $name + ":[[:space:]]*(?<value>[^\\n]+)")? | .value) // "?");
      .issues[]? | select(state_is("refuted")) | "- \(.id) (refuted by " + field("refuted_by") + "): \(.title // "")"
    ' 2>/dev/null \
    | head -5
  echo ""

  echo "## Causal chain"
  echo ""
  echo "(Operator: fill in 3-5 step causal chain from trigger → propagation → customer impact.)"
  echo ""
  echo "1. <step 1: trigger>"
  echo "2. <step 2: propagation>"
  echo "3. <step 3: customer impact>"
  echo ""

  echo "## Recommended remediation"
  echo ""
  echo "**Immediate (within 1h):** <action>"
  echo "**Short-term (within 24h):** <action>"
  echo "**Long-term (post-mortem):** <action>"
  echo ""

  echo "## Open questions deferred to post-mortem"
  echo ""
  br list --label=hypothesis --json 2>/dev/null | \
    jq -r '
      def state_is($state):
        (.description // "") | test("(^|\\n)state:[[:space:]]*" + $state + "([[:space:]]|$)");
      .issues[]? | select(state_is("deferred") or state_is("active")) | "- \(.id): \(.title // "")"
    ' 2>/dev/null \
    | head -5
  echo ""
  br list --label=audit-finding --status=open --json 2>/dev/null | \
    jq -r '.issues[]? | "- \(.id) (severity " + ((((.description // "") | capture("severity: (?<severity>\\w+)")? | .severity) // "?")) + "): \(.title // "")"' 2>/dev/null \
    | head -5
  echo ""

  echo "## Anomalies observed (deferred to post-mortem)"
  echo ""
  br list --label=anomaly --json 2>/dev/null | \
    jq -r '.issues[]? | "- \(.id): " + ((((.description // "") | capture("observation: (?<observation>[^\\n]+)")? | .observation) // "?"))' 2>/dev/null \
    | head -5
  echo ""

  echo "## Methodology"
  echo ""
  echo "Produced by brennerbot incident-investigation mode (compressed Phase 1 + Phase 3 + Phase 5 with inline investigation + Phase 7) in ~${DURATION_MIN} min. Roster: $(grep -m1 'Roster tier' .brenner_workspace/phase0_scope_decision.md 2>/dev/null | awk '{print $NF}' || echo '?')."
  echo ""
  echo "**Recommended next session:** post-mortem-formalization (full Phases 1-10) within 24h to capture 5-whys analysis, contributing factors, and methodology lessons."
  echo ""

  echo "## Operator"
  echo ""
  operator_signature=$(grep -m1 'operator_signature' deliverables/RESUME.md 2>/dev/null | awk -F: '{print $2}' | tr -d ' "')
  echo "$operator_signature"
  echo ""

  echo "---"
  echo ""
  echo "Rendered: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT"; then
  :
else
  echo "failed to write incident verdict: $OUT" >&2
  exit 1
fi

echo "Incident verdict emitted: $OUT (operator: fill in remediation, causal chain, confidence)" >&2
