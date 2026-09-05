#!/usr/bin/env bash
# calibrate-bottom-n.sh — Spot-check the bottom-N flagged beads against the
# real codebase BEFORE recommending remediation. Prior runs have shown that
# 80–100% of deterministic-baseline low-score beads are SCORE FALSE POSITIVES
# (real code, real tests, real fixes shipped — the audit pipeline just
# couldn't see them). Calibrating against ground truth turns "153 false-
# closed!" into "8 actually false-closed; 145 are pipeline artifacts" — the
# difference between alarming-but-wrong and actionable.
#
# Usage:
#   calibrate-bottom-n.sh <project-path> <pass-dir> [--n 5] [--threshold 700]
#                                                   [--out <file>]
#
# Output:
#   For each of the N lowest-scoring `closed` beads in REPORT.md, prints a
#   compact ground-truth checklist with:
#     - bead title + score + verdict
#     - link to scorecard.md (where the "Missing items" section lives)
#     - the `git log --grep` of commits touching this bead's ID
#     - a sample of cited file paths from evidence.json (if any)
#     - the FIRST occurrence of each cited file in git log so the user can
#       decide "yes this was actually built" or "no this is genuinely missing"
#
#   Writes to <pass-dir>/calibration.md by default; override with --out.
#
# This script does NOT modify the bead store. It's a read-only sanity-check.
# After reading the output, the user (or an LLM ground-truth subagent) decides
# which of the N beads are TRULY false-closed and which are pipeline artifacts.
# Then they re-run remediate.sh with --policy=report-only AND a --bead-filter
# argument, OR manually create completion-debt beads only for the confirmed
# misses.
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

PROJECT="${1:?project path}"
PASS_DIR="${2:?pass dir}"
shift 2 || true

N=5
THRESHOLD=700
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --n)         N="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --out)       OUT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 3 ;;
  esac
done

[[ "$N" =~ ^[0-9]+$ ]] || { echo "ERROR: --n must be an integer" >&2; exit 3; }
[[ "$THRESHOLD" =~ ^[0-9]+$ ]] || { echo "ERROR: --threshold must be an integer" >&2; exit 3; }

REPORT="$PASS_DIR/REPORT.md"
[ -f "$REPORT" ] || { echo "ERROR: missing $REPORT (run master-report.py first)" >&2; exit 2; }

PROJECT_ABS="$(cd "$PROJECT" && pwd)"
[ -z "$OUT" ] && OUT="$PASS_DIR/calibration.md"

# Extract the bottom-N false-closed bead IDs (lowest score first) by reading
# the False-closed table in REPORT.md. Each row is `| \`bead-id\` | P | type
# | score | title | scorecard |`. We pick the bottom N by score-asc; the table
# is already sorted lowest-priority-then-lowest-score, so a stable awk is fine.
mapfile -t IDS < <(awk -v n="$N" '
  /^## False-closed list/ {flag=1; next}
  /^## / && flag {flag=0}
  flag && /^\|[[:space:]]*`/ {
    id=$0
    sub(/^\|[[:space:]]*`/, "", id)
    sub(/`.*/, "", id)
    if (id != "") {
      print id
      count++
      if (count >= n) exit
    }
  }
' "$REPORT")

{
  echo "# Calibration — bottom $N flagged beads (ground-truth spot-check)"
  echo ""
  echo "_Pass:_ \`$(basename "$PASS_DIR")\`  ·  _Threshold:_ $THRESHOLD"
  echo ""
  echo "**Why this exists.** The deterministic baseline can over-flag beads when"
  echo "specs are prose-style, the LLM gatherer wasn't wired in, or theater"
  echo "patterns false-positive on idiomatic code. Across prior runs of this"
  echo "skill, 80–100% of the lowest-scoring beads turned out to be SCORE"
  echo "FALSE POSITIVES — real code, real tests, real fixes shipped."
  echo ""
  echo "**How to use this report.** For each bead below, decide:"
  echo "  1. **TRUE false-closed** — the spec asks for things that genuinely"
  echo "     don't exist in the code. Mark for reopen / completion-debt."
  echo "  2. **SCORE false positive** — the code is there; the audit pipeline"
  echo "     couldn't see it. Mark to suppress with a calibration note."
  echo "  3. **PARTIAL** — some of the spec is met, some isn't. Triage by item."
  echo ""
  echo "Then re-run remediation only for category 1."
  echo ""

  # When there are no IDS to calibrate, emit a minimal "all good" stanza and let
  # the brace group close naturally. We DO NOT `exit 0` from inside the brace
  # group (that would skip the post-group stderr summary, which the wrapper
  # scripts rely on to confirm the file landed).
  if [ "${#IDS[@]}" -eq 0 ]; then
    echo "_No false-closed beads to calibrate. ✓_"
    echo ""
  fi

  for ID in "${IDS[@]}"; do
    BEAD_DIR="$PASS_DIR/beads/$ID"
    SC="$BEAD_DIR/scorecard.md"
    EVIDENCE="$BEAD_DIR/evidence.json"
    SHOW="$BEAD_DIR/show.json"

    if [ ! -f "$SC" ]; then
      echo "## \`$ID\`"
      echo ""
      echo "_(scorecard.md missing — re-run scoring)_"
      echo ""
      continue
    fi

    SCORE="$(sed -nE 's/.*Score:[[:space:]]+([0-9]+).*/\1/p' "$SC" 2>/dev/null | head -1)"
    SCORE="${SCORE:-?}"
    VERDICT="$(sed -nE 's/.*Verdict:[[:space:]]+(.+)\*\*.*/\1/p' "$SC" 2>/dev/null | head -1)"
    VERDICT="${VERDICT:-?}"
    TITLE="$(jq -r '.title // "(untitled)"' "$SHOW" 2>/dev/null || echo "(no show.json)")"
    CLOSE_REASON="$(jq -r '.close_reason // "(no close_reason)"' "$SHOW" 2>/dev/null || echo "(no show.json)")"
    CLOSED_AT="$(jq -r '.closed_at // "(unknown)"' "$SHOW" 2>/dev/null || echo "?")"

    echo "## \`$ID\` — score $SCORE/1000 — $VERDICT"
    echo ""
    echo "**Title:** $TITLE"
    echo ""
    echo "**Closed:** $CLOSED_AT"
    echo ""
    echo "**Close reason:** $CLOSE_REASON"
    echo ""
    echo "**Scorecard:** [$BEAD_DIR/scorecard.md]($BEAD_DIR/scorecard.md)"
    echo ""

    # Commits referencing this bead
    echo "### Commits referencing \`$ID\`"
    echo ""
    if [ -d "$PROJECT_ABS/.git" ]; then
      COMMITS_OUT="$(git -C "$PROJECT_ABS" log --all -F --grep="$ID" --oneline 2>/dev/null | head -10 || true)"
      if [ -z "$COMMITS_OUT" ]; then
        echo "_(no commits found referencing this bead ID — calibrate with caution; might still be implemented under a different commit-message format)_"
      else
        echo '```'
        printf '%s\n' "$COMMITS_OUT"
        echo '```'
      fi
    else
      echo "_(project is not a git repo — cannot cross-reference commits)_"
    fi
    echo ""

    # Cited files
    echo "### Cited files (from evidence.json)"
    echo ""
    if [ -f "$EVIDENCE" ]; then
      CITED="$(jq -r '.checks[]? | .citations[]? | .path // empty' "$EVIDENCE" 2>/dev/null | sort -u | head -10 || true)"
      if [ -z "$CITED" ]; then
        echo "_(no cited files in evidence.json — Phase 3 found nothing. Spec might be prose-only; re-run Phase 3 with the LLM evidence-gatherer subagent before concluding the bead is truly missing.)_"
      else
        echo '| Path | Exists? | First commit | Last commit |'
        echo '|------|:-------:|--------------|-------------|'
        while IFS= read -r path; do
          [ -z "$path" ] && continue
          if [ -e "$PROJECT_ABS/$path" ]; then
            EXISTS="✓"
          else
            EXISTS="✗"
          fi
          if [ -d "$PROJECT_ABS/.git" ] && [ -e "$PROJECT_ABS/$path" ]; then
            FIRST="$(git -C "$PROJECT_ABS" log --diff-filter=A --format='%h %ad' --date=short -- "$path" 2>/dev/null | tail -1 || true)"
            LAST="$(git -C "$PROJECT_ABS" log -n1 --format='%h %ad' --date=short -- "$path" 2>/dev/null || true)"
          else
            FIRST=""
            LAST=""
          fi
          printf '| `%s` | %s | %s | %s |\n' "$path" "$EXISTS" "${FIRST:-—}" "${LAST:-—}"
        done <<< "$CITED"
      fi
    else
      echo "_(no evidence.json — Phase 3 didn't run or was deleted)_"
    fi
    echo ""

    # Missing-items section from the scorecard
    echo "### Missing items (per scorecard)"
    echo ""
    MISSING="$(awk '/^## Missing items/,0' "$SC" | tail -n +2 | head -40)"
    if [ -z "$MISSING" ] || [ "$MISSING" = "_(none)_" ]; then
      echo "_(scorecard reported no missing items — the score may be theater-driven rather than coverage-driven; check theater.json findings)_"
    else
      printf '%s\n' "$MISSING"
    fi
    echo ""
    echo "### Calibration verdict"
    echo ""
    echo "- [ ] **TRUE false-closed** — spec asks for things that genuinely don't exist"
    echo "- [ ] **SCORE false positive** — code is there; pipeline couldn't see it"
    echo "- [ ] **PARTIAL** — some met, some not"
    echo ""
    echo "_Notes:_"
    echo ""
    echo "---"
    echo ""
  done
} > "$OUT"

echo "Calibration report written: $OUT" >&2
if [ "${#IDS[@]}" -eq 0 ]; then
  echo "No false-closed beads in $REPORT — calibration is a no-op (this is good news)." >&2
else
  echo "Reviewed bottom ${#IDS[@]} bead(s). Open the file and fill in the checkboxes before any remediation step." >&2
fi
