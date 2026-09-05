#!/usr/bin/env bash
# render-artifact.sh — Assemble the canonical 7-section ARTIFACT.md from beads.
#
# The 7 sections (from references/PHASES.md and brenner_bot's artifact schema):
#   1. research_thread (question of record)
#   2. hypothesis_slate
#   3. predictions_table
#   4. discriminative_tests
#   5. assumption_ledger
#   6. anomaly_register
#   7. adversarial_critique
#
# Usage: render-artifact.sh [--workspace=<path>] [--out=<path>]

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
  OUT="$WORKSPACE/deliverables/ARTIFACT.md"
elif [[ "$OUT" != /* ]]; then
  OUT="$CALLER_PWD/$OUT"
fi
mkdir -p "$(dirname "$OUT")" || { echo "failed to create output directory: $(dirname "$OUT")" >&2; exit 1; }

# Get question of record (Q-001)
QOR_PATH="intake/question_of_record.md"
QOR_TITLE=$(awk '/^# Question of Record/{print; exit}' "$QOR_PATH" 2>/dev/null || echo "# Question of Record")
QOR_QUESTION=$(awk '/^## Question/{getline; print; exit}' "$QOR_PATH" 2>/dev/null || echo "(see $QOR_PATH)")
QOR_FALSIFIER=$(awk '/^## Falsifier/{f=1; next} /^##/{f=0} f' "$QOR_PATH" 2>/dev/null || echo "(see $QOR_PATH)")

emit_rows_or_default() {
  local filter="$1" default="$2" result
  result=$(jq -r "$filter" 2>/dev/null)
  if [ -n "$result" ]; then
    printf '%s\n' "$result"
  else
    echo "$default"
  fi
}

if {
  echo "$QOR_TITLE"
  echo ""
  echo "## 1. Research thread"
  echo ""
  echo "**Question:** $QOR_QUESTION"
  echo ""
  echo "**Falsifier:**"
  echo ""
  echo "$QOR_FALSIFIER"
  echo ""
  echo "Source: \`$QOR_PATH\`"
  echo ""

  # Helper: extract a field with regex; return default if absent. Uses jq's `try` to
  # null-safe regex match (capture[] errors when match returns null). The `gsub("\\|"; "\\|")`
  # post-processing escapes literal pipe characters inside extracted text so they can't
  # corrupt the markdown table column count (e.g. a falsifier like "X | Y" would otherwise
  # render as two extra columns and break every downstream table-aware tool).
  echo "## 2. Hypothesis slate"
  echo ""
  echo "| ID | State | Category | Origin | Confidence | Claim |"
  echo "|----|-------|----------|--------|------------|-------|"
  br list --label=hypothesis --json 2>/dev/null | \
    emit_rows_or_default '.issues[]? |
      [.id,
       (((.description // "") | capture("state: (?<x>\\w+)")? | .x) // "open"),
       (((.description // "") | capture("category: (?<x>\\w+)")? | .x) // "?"),
       (((.description // "") | capture("origin: (?<x>\\w+)")? | .x) // "?"),
       (((.description // "") | capture("confidence: (?<x>\\w+)")? | .x) // "?"),
       (.title // "")
      ] | map(tostring | gsub("\\|"; "\\|")) | "| " + join(" | ") + " |"' \
      "| (no hypotheses filed) |"
  echo ""

  echo "## 3. Predictions table"
  echo ""
  echo "| H ID | Falsifier (forbidden pattern) | Expected evidence |"
  echo "|------|-------------------------------|-------------------|"
  br list --label=hypothesis --json 2>/dev/null | \
    emit_rows_or_default '.issues[]? |
      [.id,
       (((.description // "") | capture("falsifier: (?<x>[^\\n]+)")? | .x) // "(missing)"),
       (((.description // "") | capture("expected_evidence: (?<x>[^\\n]+)")? | .x) // "(missing)")
      ] | map(tostring | gsub("\\|"; "\\|")) | "| " + join(" | ") + " |"' \
      "| (no predictions) |"
  echo ""

  echo "## 4. Discriminative tests"
  echo ""
  echo "| T ID | Discriminates between | Potency check | Expected signal | Status |"
  echo "|------|-----------------------|---------------|-----------------|--------|"
  br list --label=test --json 2>/dev/null | \
    emit_rows_or_default '.issues[]? |
      [.id,
       (((.description // "") | capture("discriminates_between: \\[(?<x>[^\\]]+)\\]")? | .x) // "?"),
       (((.description // "") | capture("potency_check: (?<x>[^\\n]+)")? | .x) // "(missing)"),
       (((.description // "") | capture("expected_signal: (?<x>[^\\n]+)")? | .x) // "(missing)"),
       (.status // "?")
      ] | map(tostring | gsub("\\|"; "\\|")) | "| " + join(" | ") + " |"' \
      "| (no tests filed) |"
  echo ""

  echo "## 5. Assumption ledger"
  echo ""
  echo "| A ID | Type | Statement | Affects | Status |"
  echo "|------|------|-----------|---------|--------|"
  br list --label=assumption --json 2>/dev/null | \
    emit_rows_or_default '.issues[]? |
      [.id,
       (((.description // "") | capture("type: (?<x>\\w+)")? | .x) // "?"),
       (((.description // "") | capture("statement: (?<x>[^\\n]+)")? | .x) // "?"),
       (((.description // "") | capture("affects: \\[(?<x>[^\\]]+)\\]")? | .x) // "?"),
       (((.description // "") | capture("status: (?<x>\\w+)")? | .x) // "unchecked")
      ] | map(tostring | gsub("\\|"; "\\|")) | "| " + join(" | ") + " |"' \
      "| (no assumptions logged) |"
  echo ""

  echo "## 6. Anomaly register"
  echo ""
  echo "| AN ID | Observation | Conflicts with | Status | Cluster |"
  echo "|-------|-------------|----------------|--------|---------|"
  br list --label=anomaly --json 2>/dev/null | \
    emit_rows_or_default '.issues[]? |
      [.id,
       (((.description // "") | capture("observation: (?<x>[^\\n]+)")? | .x) // "?"),
       (((.description // "") | capture("conflicts_with: \\[(?<x>[^\\]]+)\\]")? | .x) // "?"),
       (((.description // "") | capture("status: (?<x>\\w+)")? | .x) // "active"),
       (((.description // "") | capture("cluster_with: \\[(?<x>[^\\]]+)\\]")? | .x) // "scattered")
      ] | map(tostring | gsub("\\|"; "\\|")) | "| " + join(" | ") + " |"' \
      "| (no anomalies) |"
  echo ""

  echo "## 7. Adversarial critique"
  echo ""
  echo "| C ID | Target | Severity | Attack | Status |"
  echo "|------|--------|----------|--------|--------|"
  br list --label=critique --json 2>/dev/null | \
    emit_rows_or_default '.issues[]? |
      [.id,
       (((.description // "") | capture("target: (?<x>\\S+)")? | .x) // "?"),
       (((.description // "") | capture("severity: (?<x>\\w+)")? | .x) // "?"),
       (((.description // "") | capture("attack: (?<x>[^\\n]+)")? | .x) // "?"),
       (((.description // "") | capture("status: (?<x>\\w+)")? | .x) // "active")
      ] | map(tostring | gsub("\\|"; "\\|")) | "| " + join(" | ") + " |"' \
      "| (no critiques filed) |"
  echo ""

  echo "---"
  echo ""
  echo "*Rendered by \`scripts/render-artifact.sh\` at $(date -u +%Y-%m-%dT%H:%M:%SZ)*"
  echo ""
  echo "*This file is auto-generated from beads. Do not hand-edit.*"
} > "$OUT"; then
  :
else
  echo "failed to write artifact: $OUT" >&2
  exit 1
fi

echo "Rendered: $OUT" >&2
