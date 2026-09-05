#!/usr/bin/env bash
# check-anchor-density.sh — Verify cited evidence has sufficient anchor density
# Per CRITIQUE-CRAFT.md citation density guidance.
#
# An EV bead with claim "X" should have ≥1 anchor citing source verbatim.
# This script computes anchor density per H and per EV.

set -uo pipefail

WORKSPACE="${1:-.}"

cd "$WORKSPACE" 2>/dev/null || { echo "[FATAL] Cannot cd to: $WORKSPACE" >&2; exit 1; }

if ! command -v br >/dev/null 2>&1; then
    echo "[FATAL] br (beads) CLI not found" >&2
    exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "[FATAL] jq not found" >&2
    exit 2
fi

# Get all EV beads (label=evidence):
EVIDENCE_BEADS_JSON=$(br list --label=evidence --json 2>/dev/null || echo '{"issues":[]}')

if [ "$(echo "$EVIDENCE_BEADS_JSON" | jq '.issues | length')" -eq 0 ]; then
    echo "[INFO] No EV beads found"
    exit 0
fi

declare -i TOTAL_EVS=0
declare -i LOW_DENSITY=0
declare -i ZERO_DENSITY=0

# Process each EV bead:
while IFS= read -r ev_id; do
    [ -z "$ev_id" ] && continue
    TOTAL_EVS=$((TOTAL_EVS + 1))

    DESCRIPTION=$(br show "$ev_id" --json 2>/dev/null | jq -r 'if type == "array" then (.[0] // {}) else . end | .description // ""')

    # Count verbatim quoted excerpts (look for: 'verbatim from §' or 'E1:' etc).
    # Use [[:space:]] instead of \s for portability — BSD grep doesn't recognize
    # \s as a character class even with -E.
    QUOTE_COUNT=$(printf '%s' "$DESCRIPTION" \
        | grep -cE '(verbatim from|E[0-9]+[[:space:]]*\(verbatim|^- E[0-9]+:|"[^"]{20,}")' || true)

    # Count source citations:
    SOURCE_COUNT=$(printf '%s' "$DESCRIPTION" \
        | grep -cE '(source_id:|source:|file:line)' || true)

    # Density rubric:
    # - ZERO: no verbatim quotes at all (anti-Brenner; rejected outright)
    # - LOW: at least one quote but no source citation, OR fewer than 2 quotes
    #   for `confidence:high`-tier EVs (per CRITIQUE-CRAFT.md citation density).
    # Previously this branch tested `$QUOTE_COUNT -lt 1` which is dead code —
    # the `-eq 0` if branch already caught that case.
    if [ "$QUOTE_COUNT" -eq 0 ]; then
        echo "ZERO-DENSITY: $ev_id (no verbatim quotes)"
        ZERO_DENSITY=$((ZERO_DENSITY + 1))
    elif [ "$SOURCE_COUNT" -eq 0 ] || [ "$QUOTE_COUNT" -lt 2 ]; then
        echo "LOW-DENSITY: $ev_id (quotes=$QUOTE_COUNT, sources=$SOURCE_COUNT)"
        LOW_DENSITY=$((LOW_DENSITY + 1))
    fi
done < <(echo "$EVIDENCE_BEADS_JSON" | jq -r '.issues[]?.id // empty')

echo "==="
echo "Total EV beads: $TOTAL_EVS"
echo "Zero-density:   $ZERO_DENSITY"
echo "Low-density:    $LOW_DENSITY"
echo "Healthy:        $((TOTAL_EVS - ZERO_DENSITY - LOW_DENSITY))"

# Exit nonzero if any zero-density (these are unacceptable):
if [ "$ZERO_DENSITY" -gt 0 ]; then
    exit 1
fi
exit 0
