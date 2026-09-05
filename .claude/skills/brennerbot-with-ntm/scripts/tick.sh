#!/usr/bin/env bash
# tick.sh — One-tick orchestrator snapshot for the brennerbot operator.
#
# Mirror of /vibing-with-ntm orchestrator-tick.sh adapted for research-session metrics.
# Call this every 10-17 min during steady-state Phase 4-7 activity.
#
# Usage: tick.sh <workspace> [session-name]

set -uo pipefail

WORKSPACE_INPUT="${1:?usage: tick.sh <workspace> [session-name]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! WORKSPACE="$(cd "$WORKSPACE_INPUT" 2>/dev/null && pwd)"; then
  echo "workspace not accessible: $WORKSPACE_INPUT" >&2
  exit 1
fi
SESSION="${2:-brennerbot-$(basename "$WORKSPACE" | sed 's/__brennerbot_session$//')}"
command -v jq >/dev/null 2>&1 || { echo "jq not found; tick.sh requires jq for ntm/br JSON parsing" >&2; exit 2; }

hr() { printf '── %s ──\n' "$*"; }
ok() { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*"; }
bad() { printf '  ✗ %s\n' "$*"; }

# 1. Phase progression
hr "PHASE PROGRESSION"
for N in 1 2 3 4 5 6 7 8 9 10; do
  flag="$WORKSPACE/.brenner_workspace/phase_${N}_complete.flag"
  if [ -f "$flag" ]; then
    ok "Phase $N: complete"
  else
    echo "  ◯ Phase $N: pending"
    break
  fi
done

# 2. Pane state via ntm
hr "PANE STATE"
if command -v ntm >/dev/null 2>&1; then
  ntm --robot-snapshot 2>/dev/null \
    | jq -r --arg s "$SESSION" '.sessions[]? | select(.name == $s) | .panes[] |
        "  pane \(.index) (\(.type // "?")): is_working=\(.is_working // false) ctx=\(.context_pct // "?")%"' \
    || warn "ntm --robot-snapshot unavailable or session $SESSION not found"
else
  warn "ntm not installed"
fi

# 3. Bead inventory
hr "BEAD INVENTORY"
if command -v br >/dev/null 2>&1; then
  cd "$WORKSPACE" 2>/dev/null || { warn "workspace not accessible"; exit 1; }
  H_ACTIVE=$(br list --label=hypothesis --status=open --json 2>/dev/null | jq '[.issues[]? | select((.description // "") | test("(^|\\n)state:[[:space:]]*active([[:space:]]|$)"))] | length' 2>/dev/null || echo 0)
  H_REFUTED=$(br list --label=hypothesis --json 2>/dev/null | jq '[.issues[]? | select((.description // "") | test("(^|\\n)state:[[:space:]]*refuted([[:space:]]|$)"))] | length' 2>/dev/null || echo 0)
  H_CONFIRMED=$(br list --label=hypothesis --json 2>/dev/null | jq '[.issues[]? | select((.description // "") | test("(^|\\n)state:[[:space:]]*confirmed([[:space:]]|$)"))] | length' 2>/dev/null || echo 0)
  EV=$(br list --label=evidence --json 2>/dev/null | jq '.issues | length' 2>/dev/null || echo 0)
  EV_REFUTES=$(br list --label=evidence --json 2>/dev/null | jq '[.issues[]? | select((.description // "") | contains("refutes: ["))] | length' 2>/dev/null || echo 0)
  AF_OPEN=$(br list --label=audit-finding --status=open --json 2>/dev/null | jq '.issues | length' 2>/dev/null || echo 0)
  AF_CRIT=$(br list --label=audit-finding --status=open --json 2>/dev/null | jq '[.issues[]? | select((.description // "") | contains("severity: critical"))] | length' 2>/dev/null || echo 0)

  echo "  Hypotheses: $H_ACTIVE active, $H_REFUTED refuted, $H_CONFIRMED confirmed"
  echo "  Evidence: $EV total ($EV_REFUTES with refutes: populated)"
  echo "  Audit findings open: $AF_OPEN ($AF_CRIT critical)"
else
  warn "br not installed"
fi

# 4. Bead invariants
hr "BEAD INVARIANTS"
if [ -x "$SCRIPT_DIR/audit-bead-invariants.sh" ]; then
  if "$SCRIPT_DIR/audit-bead-invariants.sh" --workspace="$WORKSPACE" --check=phase4_round 2>&1 | grep -q "Audit clean"; then
    ok "phase 4 invariants clean"
  else
    warn "phase 4 invariants have violations (run audit-bead-invariants.sh --all for details)"
  fi
fi

# 5. Productivity (git log)
hr "PRODUCTIVITY · git log last 1h"
COMMITS=$(cd "$WORKSPACE" && git log --since="1 hour ago" --oneline 2>/dev/null | wc -l | tr -d ' ')
echo "  commits_1h=$COMMITS"
cd "$WORKSPACE" && git log --since="1 hour ago" --format='  %ar %an %h %s' 2>/dev/null | head -5

# 6. Convergence check (current phase guess)
hr "CONVERGENCE CHECK"
# Determine current phase by the last *contiguous* phase_*_complete.flag.
# `else break` matters: a session that skipped Phase 3 (flags 1, 2, 5, 6) must
# report current phase = 3, NOT 7. dump-session-report.sh's
# last_contiguous_phase_completed() uses the same form; this loop was the
# odd one out (also affected liveness-check.sh and emit-quickref.sh).
LAST_COMPLETE=0
for N in 1 2 3 4 5 6 7 8 9; do
  if [ -f "$WORKSPACE/.brenner_workspace/phase_${N}_complete.flag" ]; then
    LAST_COMPLETE=$N
  else
    break
  fi
done
CURRENT=$((LAST_COMPLETE + 1))
echo "  Current phase (estimated): $CURRENT"

if [ "$CURRENT" = "4" ] || [ "$CURRENT" = "6" ] || [ "$CURRENT" = "7" ]; then
  if [ -x "$SCRIPT_DIR/convergence-check.sh" ]; then
    "$SCRIPT_DIR/convergence-check.sh" --phase="$CURRENT" --workspace="$WORKSPACE" 2>&1 | sed 's/^/  /'
  fi
fi

# 7. Tick log
TICK_LOG="$WORKSPACE/.brenner_workspace/tick_history.jsonl"
mkdir -p "$(dirname "$TICK_LOG")"
{
  printf '{"ts": "%s", "phase": %s, "h_active": %s, "h_refuted": %s, "h_confirmed": %s, "ev": %s, "af_open": %s, "commits_1h": %s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${CURRENT:-0}" "${H_ACTIVE:-0}" "${H_REFUTED:-0}" "${H_CONFIRMED:-0}" "${EV:-0}" "${AF_OPEN:-0}" "${COMMITS:-0}"
} >> "$TICK_LOG"

hr "TICK LOG APPENDED"
echo "  $TICK_LOG"
