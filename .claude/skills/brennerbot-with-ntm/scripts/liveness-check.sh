#!/usr/bin/env bash
# liveness-check.sh — Apply the Liveness Truth Stack from SKILL.md.
#
# Returns 0 if the swarm is "actually live" (artifacts landing); 1 if liveness is suspect.
#
# Usage: liveness-check.sh <workspace> [session-name]

set -uo pipefail

WORKSPACE_INPUT="${1:?usage: liveness-check.sh <workspace> [session-name]}"
if ! WORKSPACE="$(cd "$WORKSPACE_INPUT" 2>/dev/null && pwd)"; then
  echo "workspace not accessible: $WORKSPACE_INPUT" >&2
  exit 1
fi
SESSION="${2:-brennerbot-$(basename "$WORKSPACE" | sed 's/__brennerbot_session$//')}"
command -v jq >/dev/null 2>&1 || { echo "jq not found; liveness-check.sh requires jq for ntm/br JSON parsing" >&2; exit 2; }

ALL_OK=1

hr() { printf '── %s ──\n' "$*"; }

hr "1. PANE PROCESSES (tmux list-panes)"
if command -v ntm >/dev/null 2>&1; then
  CMDS=$(ntm --robot-snapshot 2>/dev/null | jq -r --arg s "$SESSION" '.sessions[]? | select(.name == $s) | .panes[] | "\(.index): \(.current_command // "?")"' 2>/dev/null)
  if [ -n "$CMDS" ]; then
    echo "$CMDS"
    if echo "$CMDS" | grep -q ': zsh$'; then
      echo "  ⚠ Some panes are at bare zsh — likely silent CLI exit"
      ALL_OK=0
    fi
  else
    echo "  (snapshot unavailable; check tmux directly)"
    ALL_OK=0
  fi
else
  echo "  ⚠ ntm not installed — cannot verify pane processes"
  ALL_OK=0
fi

hr "2. PANE TAIL (recent activity)"
if command -v ntm >/dev/null 2>&1; then
  STALE=$(ntm --robot-tail="$SESSION" --lines=5 2>/dev/null | jq -r '.panes | to_entries[]? | select(((.value.lines // []) | join("\n") | length) < 50) | .key' 2>/dev/null)
  if [ -n "$STALE" ]; then
    echo "  ⚠ Panes with very short recent tail: $STALE"
  else
    echo "  ✓ All panes show recent activity"
  fi
else
  echo "  ⚠ ntm not installed — cannot inspect pane tails"
  ALL_OK=0
fi

hr "3. ARTIFACT GROUND TRUTH (git log)"
COMMITS=$(cd "$WORKSPACE" && git log --since="15 minutes ago" --oneline -- intake/ corpus/ evidence/ distillations/ deliverables/ .beads/ 2>/dev/null | wc -l | tr -d ' ')
echo "  artifact commits last 15min: $COMMITS"
if [ "$COMMITS" = "0" ]; then
  AGE_30=$(cd "$WORKSPACE" && git log --since="30 minutes ago" --oneline -- intake/ corpus/ evidence/ distillations/ deliverables/ .beads/ 2>/dev/null | wc -l | tr -d ' ')
  if [ "$AGE_30" = "0" ]; then
    echo "  ⚠ No artifact commits in 30 minutes — possible prose-without-artifacts"
    ALL_OK=0
  fi
fi

hr "4. BEAD LEDGER ADVANCING"
BEADS_TOTAL=0
BEAD_COMMITS=0
if command -v br >/dev/null 2>&1; then
  BEADS_TOTAL=$( ( cd "$WORKSPACE" 2>/dev/null && br list --json 2>/dev/null | jq '.issues | length' 2>/dev/null ) || echo 0)
  BEADS_TOTAL=${BEADS_TOTAL:-0}
  echo "  total beads: $BEADS_TOTAL"
  # Crude: check if .beads/ git history shows recent activity
  BEAD_COMMITS=$( ( cd "$WORKSPACE" 2>/dev/null && git log --since="30 minutes ago" --oneline -- .beads/ 2>/dev/null | wc -l | tr -d ' ' ) || echo 0)
  BEAD_COMMITS=${BEAD_COMMITS:-0}
  echo "  bead commits last 30min: $BEAD_COMMITS"
  if [ "$BEAD_COMMITS" = "0" ] && [ "$BEADS_TOTAL" -gt 5 ]; then
    echo "  ⚠ Bead ledger not advancing"
  fi
else
  echo "  ⚠ br not installed — cannot verify bead ledger"
  ALL_OK=0
fi

hr "5. INVARIANTS"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x "$SCRIPT_DIR/audit-bead-invariants.sh" ]; then
  if "$SCRIPT_DIR/audit-bead-invariants.sh" --workspace="$WORKSPACE" --all 2>&1 | grep -q "Audit clean"; then
    echo "  ✓ all invariants clean"
  else
    echo "  ⚠ invariant violations present"
    ALL_OK=0
  fi
fi

hr "6. CONVERGENCE (current phase)"
# Use last contiguous phase flag (same form as dump-session-report.sh +
# tick.sh + emit-quickref.sh): a session that skipped Phase 3 must report
# current = 3, not 7.
LAST_COMPLETE=0
for N in 1 2 3 4 5 6 7 8 9; do
  if [ -f "$WORKSPACE/.brenner_workspace/phase_${N}_complete.flag" ]; then
    LAST_COMPLETE=$N
  else
    break
  fi
done
CURRENT=$((LAST_COMPLETE + 1))
echo "  current phase: $CURRENT (last complete: $LAST_COMPLETE)"

if [ "$CURRENT" = "4" ] || [ "$CURRENT" = "6" ] || [ "$CURRENT" = "7" ]; then
  if [ -x "$SCRIPT_DIR/convergence-check.sh" ]; then
    if "$SCRIPT_DIR/convergence-check.sh" --phase="$CURRENT" --workspace="$WORKSPACE" 2>&1 | grep -q "CONVERGED"; then
      echo "  ✓ phase $CURRENT converged"
    else
      echo "  ◯ phase $CURRENT not yet converged"
    fi
  fi
fi

hr "7. RATE LIMITS / OAUTH"
if command -v ntm >/dev/null 2>&1; then
  LIMITED=$(ntm --robot-health-oauth="$SESSION" 2>/dev/null | jq -r '.panes[]? | select(.rate_limited == true) | "pane \(.pane): \(.provider) resets \(.resets_at // "?")"' 2>/dev/null)
  if [ -n "$LIMITED" ]; then
    echo "  ⚠ rate-limited panes:"
    echo "$LIMITED"
  else
    echo "  ✓ no rate-limited panes"
  fi
else
  echo "  ⚠ ntm not installed — cannot inspect rate limits"
  ALL_OK=0
fi

hr "VERDICT"
if [ "$ALL_OK" = "1" ]; then
  echo "  Liveness OK"
  exit 0
else
  echo "  Liveness suspect — review warnings above"
  exit 1
fi
