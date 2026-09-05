#!/usr/bin/env bash
# shellcheck disable=SC2016
# render-threat-catalog.sh — Render threat catalog (A6 adversarial archetype Phase 9 form).
#
# Reads C-* (critique) beads + EV-* with refutes: + audit-finding beads. Writes deliverables/THREAT-CATALOG.md.
#
# Usage: render-threat-catalog.sh [--workspace=<path>] [--out=<path>]

set -uo pipefail
# shellcheck disable=SC2016 # jq programs are single-quoted intentionally.

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
  OUT="$WORKSPACE/deliverables/THREAT-CATALOG.md"
elif [[ "$OUT" != /* ]]; then
  OUT="$CALLER_PWD/$OUT"
fi
mkdir -p "$(dirname "$OUT")" || { echo "failed to create output directory: $(dirname "$OUT")" >&2; exit 1; }

QUESTION=$(awk '/^## Question/{getline; print; exit}' intake/question_of_record.md 2>/dev/null || echo "(see question_of_record.md)")

if {
  echo "# Threat Catalog — $(basename "$WORKSPACE")"
  echo ""
  echo "**Audit date:** $(date -u +%Y-%m-%d)"
  echo "**Subject:** $QUESTION"
  echo ""
  echo "## Methodology"
  echo ""
  echo "Adversarial design audit per QUESTION-ARCHETYPES.md A6. Operators applied: ✂ Exclusion-Test (forbidden patterns), ⊞ Scale-Check (adversary scale exploitation), ΔE Exception-Quarantine (anomaly-driven attacks), ⊕ Cross-Domain (importing known attack patterns)."
  echo ""
  echo "Devil's-Advocate panes + (T4+) red-team subagent enumerated threats. Each threat has: attack class, precondition, evidence-to-confirm, severity, recommended remediation."
  echo ""

  echo "## Threats by severity"
  echo ""

  # Helper: emit threats matching jq filter, OR "no threats" message if empty.
  # The previous `... || echo "*(no ...)*"` pattern broke when jq exited 0 with empty output.
  emit_or_default() {
    local label="$1" filter="$2" default="$3"
    echo "### $label"
    echo ""
    local result
    result=$(br list --label=critique --json 2>/dev/null | jq -r "$filter" 2>/dev/null)
    if [ -n "$result" ]; then
      echo "$result"
    else
      echo "$default"
    fi
    echo ""
  }

  emit_or_default "Critical" \
    '.issues[]? | select((.description // "") | contains("severity: critical")) | "#### \(.id) — \(.title // "")\n\n```\n\(.description // "")\n```\n"' \
    "*(no critical threats)*"

  emit_or_default "High" \
    '.issues[]? | select((.description // "") | contains("severity: serious") or contains("severity: high")) | "#### \(.id) — \(.title // "")\n\n```\n\(.description // "")\n```\n"' \
    "*(no high threats)*"

  emit_or_default "Medium" \
    '.issues[]? | select((.description // "") | contains("severity: moderate") or contains("severity: medium")) | "#### \(.id) — \(.title // "")\n\n```\n\(.description // "")\n```\n"' \
    "*(no medium threats)*"

  emit_or_default "Low" \
    '.issues[]? | select((.description // "") | contains("severity: minor") or contains("severity: low")) | "#### \(.id) — \(.title // "")\n\n```\n\(.description // "")\n```\n"' \
    "*(no low threats)*"

  echo "## Threats by attack class"
  echo ""
  for CLASS in correctness security scale regulatory social timing-oracle replay downgrade side-channel; do
    HITS=$(br list --label=critique --json 2>/dev/null | jq -r --arg c "$CLASS" '.issues[]? | select((.description // "") | contains("attack_class: " + $c) or contains("attack_class: \"" + $c + "\"")) | "  - \(.id): \(.title // "")"' 2>/dev/null)
    if [ -n "$HITS" ]; then
      echo "### $CLASS"
      echo ""
      echo "$HITS"
      echo ""
    fi
  done

  echo "## Recommended remediations (prioritized)"
  echo ""
  echo "(Operator: prioritize remediations by severity × likelihood. Top 5 here.)"
  echo ""
  echo "1. ..."
  echo "2. ..."
  echo "3. ..."
  echo ""

  echo "## Audit coverage"
  echo ""
  TOTAL_C=$(br list --label=critique --json 2>/dev/null | jq '.issues | length' 2>/dev/null || echo 0)
  TOTAL_AF=$(br list --label=audit-finding --json 2>/dev/null | jq '.issues | length' 2>/dev/null || echo 0)
  echo "- Total critiques filed: $TOTAL_C"
  echo "- Total audit findings filed: $TOTAL_AF"
  echo "- Phase 7 trio-rounds completed: $(grep -c 'trio-round' session-logs/round-*.md 2>/dev/null | awk '{s+=$1} END {print s+0}')"
  echo "- Red-team subagent run: $(test -f deliverables/threat-catalog-redteam.md && echo "yes" || echo "no")"
  echo ""

  echo "## Open questions"
  echo ""
  # Use the helper (which prints the default when the result is empty) — the
  # bare `... || echo "..."` pattern doesn't fire because jq exits 0 with no
  # stdout on an empty `.issues[]` stream, swallowing the fallback.
  af_open_block() {
    local result
    result=$(br list --label=audit-finding --status=open --json 2>/dev/null \
      | jq -r '.issues[]? | "- \(.id) (severity: " + ((((.description // "") | capture("severity: (?<severity>\\w+)")? | .severity) // "?")) + "): \(.title // "")"' 2>/dev/null)
    if [ -n "$result" ]; then
      printf '%s\n' "$result"
    else
      echo "*(no open audit findings)*"
    fi
  }
  af_open_block
  echo ""

  echo "## Re-audit recommendation"
  echo ""
  echo "After remediations applied, re-run an A6 session to verify the threat surface is closed. Recommended cadence: every 6 months for high-stakes systems, after any major architecture change."
  echo ""
  echo "Rendered: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT"; then
  :
else
  echo "failed to write threat catalog: $OUT" >&2
  exit 1
fi

echo "Threat catalog emitted: $OUT" >&2
