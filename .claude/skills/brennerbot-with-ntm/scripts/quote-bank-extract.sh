#!/usr/bin/env bash
# quote-bank-extract.sh — Build per-operator quote bank from corpus + session evidence packs.
#
# For each of the 15 operators, find verbatim quotes anchored at §-citations in:
#   - corpus/ingested/<S>/main.md (source corpus)
#   - evidence/packs/EV-pack-*.md (per-H evidence packs)
# Output: quote-bank-by-operator.md (per-operator section with citations)
#
# Usage: quote-bank-extract.sh [--workspace=<path>] [--out=<path>]

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

if [ -z "$OUT" ]; then
  OUT="$WORKSPACE/deliverables/quote-bank-by-operator.md"
elif [[ "$OUT" != /* ]]; then
  OUT="$CALLER_PWD/$OUT"
fi
mkdir -p "$(dirname "$OUT")" || { echo "failed to create output directory: $(dirname "$OUT")" >&2; exit 1; }

cd "$WORKSPACE" || { echo "workspace not accessible: $WORKSPACE" >&2; exit 1; }

# Operator glyphs and their canonical names
declare -A OPS=(
  ['◊']='Paradox-Hunt'
  ['⊘']='Level-Split'
  ['𝓛']='Recode/Dimensional-Reduction'
  ['≡']='Invariant-Extract'
  ['✂']='Exclusion-Test'
  ['⟂']='Object-Transpose'
  ['↑']='Amplify'
  ['⌂']='Materialize'
  ['🔧']='DIY/Bricolage'
  ['⊞']='Scale-Check'
  ['🤝']='GAN/Conversation'
  ['ΔE']='Exception-Quarantine'
  ['†']='Theory-Kill'
  ['∿']='Dephase'
  ['⊙']='Productive-Ignorance'
)

if {
  echo "# Quote Bank by Operator — $(basename "$WORKSPACE")"
  echo ""
  echo "Auto-extracted by quote-bank-extract.sh at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  for OP in '◊' '⊘' '𝓛' '≡' '✂' '⟂' '↑' '⌂' '🔧' '⊞' '🤝' 'ΔE' '†' '∿' '⊙'; do
    NAME="${OPS[$OP]}"
    echo "## $OP $NAME"
    echo ""

    # Find lines mentioning the operator glyph in evidence packs and corpus
    HITS=$(grep -h -B 1 -A 3 "$OP" \
      evidence/packs/*.md \
      corpus/ingested/*/main.md \
      session-logs/round-*.md \
      distillations/*.md \
      2>/dev/null \
      | grep -E '§[0-9]+|"[^"]+"|\.md:[0-9]+' \
      | head -10)

    if [ -n "$HITS" ]; then
      while IFS= read -r line; do
        printf '    %s\n' "$line"
      done <<< "$HITS"
      echo ""
    else
      echo "*(no quotes found in this session for $OP $NAME)*"
      echo ""
    fi
  done

  echo "---"
  echo ""
  echo "## Source-corpus coverage"
  echo ""
  ANCHORS_TOTAL=$(grep -h -oE '§[0-9]+' evidence/packs/*.md corpus/ingested/*/main.md 2>/dev/null | sort -u | wc -l | tr -d ' ')
  echo "- Distinct §-anchors cited: $ANCHORS_TOTAL"
  echo ""
  echo "## Operator coverage"
  echo ""
  for OP in '◊' '⊘' '𝓛' '≡' '✂' '⟂' '↑' '⌂' '🔧' '⊞' '🤝' 'ΔE' '†' '∿' '⊙'; do
    COUNT=$(grep -hc "$OP" evidence/packs/*.md corpus/ingested/*/main.md session-logs/round-*.md distillations/*.md 2>/dev/null \
      | awk '{s+=$1} END {print s+0}')
    echo "- $OP ${OPS[$OP]}: $COUNT mentions"
  done
} > "$OUT"; then
  :
else
  echo "failed to write quote bank: $OUT" >&2
  exit 1
fi

echo "Quote bank emitted: $OUT" >&2
