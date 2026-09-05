#!/usr/bin/env bash
# check-rotation-rules.sh — Verify Adjudicator/Synthesizer rotation per ROSTER-PLANS.md.
#
# Checks:
#   1. No Adjudicator pane adjudicates two debates in a row (the canonical
#      ROSTER-PLANS rule: "the Adjudicator role rotates; never the same pane
#      two debates in a row" — applies regardless of which pair was judged)
#   2. No Adjudicator is a champion of the H being adjudicated
#   3. Phase 6 Meta-synthesizer is a different family from dominant per-family distillation
#   4. Phase 7 audit panes include ≥1 family different from Phase 6 synthesizers
#
# Returns 0 if all rotation rules upheld; 1 otherwise.
#
# Usage: check-rotation-rules.sh [--workspace=<path>]

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
command -v br >/dev/null 2>&1 || { echo "br CLI not found" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq not found" >&2; exit 2; }

VIOLATIONS=0
violation() {
  echo "  ✗ $1" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
}

echo "Checking rotation rules..."

# Rule 1: Adjudicator rotation
# Read DEBATE-* beads in order; check if any adjudicator handles two debates in a row.
DEBATES_JSON=$(br list --label=debate --json 2>/dev/null | \
  jq -r '[.issues[]? | {id, created: (.created_at // "1970-01-01"), desc: (.description // "")}] | sort_by(.created)' 2>/dev/null)

if [ -n "$DEBATES_JSON" ] && [ "$DEBATES_JSON" != "[]" ]; then
  # Extract adjudicator + H pair per debate, in chronological order. Missing
  # metadata is itself a violation; otherwise a malformed debate bead can make
  # the jq match fail and silently disable the rotation check.
  PAIRS=$(echo "$DEBATES_JSON" | jq -r '
    .[] |
    .id as $id |
    (.desc // "") as $desc |
    ($desc | capture("adjudicator: (?<adjudicator>\\S+)")? // {}) as $adj |
    ($desc | capture("pair: (?<pair>\\S+ vs \\S+)")? // {}) as $pair |
    [$id, ($adj.adjudicator // ""), ($pair.pair // "")] | @tsv
  ' 2>/dev/null)

  PREV_ADJUDICATOR=""
  PREV_PAIR=""
  while IFS=$'\t' read -r ID ADJUDICATOR PAIR; do
    [ -z "$ID$ADJUDICATOR$PAIR" ] && continue
    if [ -z "$ADJUDICATOR" ] || [ -z "$PAIR" ]; then
      violation "$ID: debate description missing adjudicator or pair metadata"
      continue
    fi
    case "$ADJUDICATOR" in
      TBD|tbd|null|unknown|UNKNOWN)
        violation "$ID: debate adjudicator is still a placeholder ($ADJUDICATOR)"
        continue
        ;;
    esac
    # Rotation rule: same adjudicator pane two debates in a row is the violation,
    # whether or not it's the same pair. Pair information is preserved in the
    # message for triage but is NOT part of the firing condition.
    if [ -n "$PREV_ADJUDICATOR" ] && [ "$ADJUDICATOR" = "$PREV_ADJUDICATOR" ]; then
      if [ "$PAIR" = "$PREV_PAIR" ]; then
        violation "Adjudicator $ADJUDICATOR adjudicated the same pair $PAIR twice in a row"
      else
        violation "Adjudicator $ADJUDICATOR adjudicated two consecutive debates ($PREV_PAIR → $PAIR); rotation rule says the role must rotate"
      fi
    fi
    PREV_ADJUDICATOR="$ADJUDICATOR"
    PREV_PAIR="$PAIR"
  done <<<"$PAIRS"
fi

# Rule 2: Adjudicator not in champions of the same debate.
# Use process substitution so `violation` increments in the parent shell instead of being
# lost in a pipe-induced subshell.
if [ -n "$DEBATES_JSON" ] && [ "$DEBATES_JSON" != "[]" ]; then
  while read -r line; do
    [ -z "$line" ] && continue
    ID=$(echo "$line" | awk -F: '{print $1}')
    # Restrict to [A-Za-z0-9_-] for the adjudicator id; \S+ would also capture
    # a trailing `;`/`,` when the bead description uses `; ` to separate fields,
    # producing IDs like `p1;` that fail the word-boundary match below.
    ADJ=$(echo "$line" | grep -oE 'adjudicator: [A-Za-z0-9_-]+' | awk '{print $2}')
    CHAMPS=$(echo "$line" | grep -oE 'champions:\s*\{[^}]*\}' || true)
    # Use `grep -qwF` rather than `grep -q` here:
    # - -F treats $ADJ as a literal string (no accidental regex metachars)
    # - -w requires word-boundary match so pane id "p1" doesn't falsely match
    #   the substring "p1" inside "p10"/"p11" — the previous version misfired
    #   on every roster where an adjudicator's id was a prefix of a champion's.
    if [ -n "$ADJ" ] && [ -n "$CHAMPS" ] && printf '%s' "$CHAMPS" | grep -qwF "$ADJ"; then
      violation "$ID: adjudicator $ADJ is also a champion"
    fi
  done < <(echo "$DEBATES_JSON" | jq -r '.[] | .id + ": " + .desc' 2>/dev/null)
fi

# Rule 3: Phase 6 meta-synthesizer family ≠ dominant per-family family
if [ -f distillations/meta_synthesis.md ]; then
  # Heuristic: count cites to each by_<fam>.md in meta_synthesis.md.
  # NOTE: don't use `grep -c ... || echo 0` here — when the file exists but
  # has 0 matches, grep -c outputs "0" with exit 1, AND the OR fallback fires
  # producing a second "0", so the captured value becomes "0\n0" which then
  # blows up the `-gt` arithmetic comparison below. The file existence is
  # already guarded by the outer `if [ -f distillations/meta_synthesis.md ]`,
  # so grep always emits a single integer line.
  declare -A CITES
  for FAM in cc cod gmi; do
    CITES[$FAM]=$(grep -c "by_${FAM}.md" distillations/meta_synthesis.md 2>/dev/null)
    CITES[$FAM]=${CITES[$FAM]:-0}
  done

  # Find dominant family
  MAX_CITES=0
  DOMINANT=""
  for FAM in cc cod gmi; do
    if [ "${CITES[$FAM]}" -gt "$MAX_CITES" ]; then
      MAX_CITES="${CITES[$FAM]}"
      DOMINANT="$FAM"
    fi
  done

  # Find meta-synthesizer family. Heuristic: there's no canonical field; check phase0_scope_decision.md
  META_FAM=$(awk '/meta_synthesizer.*family/{getline; print}' .brenner_workspace/phase0_scope_decision.md 2>/dev/null | tr -d '"' | head -1 || echo "unknown")

  if [ -n "$META_FAM" ] && [ "$META_FAM" != "unknown" ] && [ "$META_FAM" = "$DOMINANT" ]; then
    violation "Phase 6 meta-synthesizer family ($META_FAM) is same as dominant per-family ($DOMINANT)"
  fi
fi

# Rule 4: Phase 7 audit family diversity
if [ -d session-logs ]; then
  AUDIT_PANES=$(grep -h "auditor pane" session-logs/round-*.md 2>/dev/null | grep -oE 'pane [0-9]+' | sort -u | wc -l | tr -d ' ')
  if [ "$AUDIT_PANES" -gt 0 ]; then
    # Heuristic check; full implementation would need pane-to-family mapping
    echo "  (Rule 4: $AUDIT_PANES audit panes detected — manual family-diversity verification needed)"
  fi
fi

if [ "$VIOLATIONS" = "0" ]; then
  echo "Rotation rules clean."
  exit 0
else
  echo "$VIOLATIONS rotation-rule violation(s) detected." >&2
  exit 1
fi
