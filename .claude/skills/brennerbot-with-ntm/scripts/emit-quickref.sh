#!/usr/bin/env bash
# emit-quickref.sh — One-screen health dashboard for a brennerbot session.
#
# Mirrors the dashboard format in METRICS.md § Health dashboard.
#
# Usage: emit-quickref.sh <workspace> [session-name]

set -uo pipefail

WORKSPACE_INPUT="${1:?usage: emit-quickref.sh <workspace> [session-name]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! WORKSPACE="$(cd "$WORKSPACE_INPUT" 2>/dev/null && pwd)"; then
  echo "workspace not accessible: $WORKSPACE_INPUT" >&2
  exit 1
fi
SESSION="${2:-brennerbot-$(basename "$WORKSPACE" | sed 's/__brennerbot_session$//')}"
cd "$WORKSPACE" || { echo "workspace not accessible: $WORKSPACE" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found" >&2; exit 2; }

# Phase progression. Use last contiguous phase (same as dump-session-report.sh
# + tick.sh + liveness-check.sh): a session that skipped Phase 3 must report
# current = 3, not 7.
LAST_COMPLETE=0
for N in 1 2 3 4 5 6 7 8 9; do
  if [ -f ".brenner_workspace/phase_${N}_complete.flag" ]; then
    LAST_COMPLETE=$N
  else
    break
  fi
done
CURRENT=$((LAST_COMPLETE + 1))

# Wall time. Use stat (GNU/BSD) or python3 fallback. If all fail, report "(unknown)".
SESSION_START=$(stat -c %Y .brenner_workspace/phase0_scope_decision.md 2>/dev/null \
  || stat -f %m .brenner_workspace/phase0_scope_decision.md 2>/dev/null \
  || python3 -c "import os; print(int(os.path.getmtime('.brenner_workspace/phase0_scope_decision.md')))" 2>/dev/null \
  || echo "")
NOW=$(date +%s)
if [ -n "$SESSION_START" ] && [ "$SESSION_START" -gt 0 ] 2>/dev/null; then
  WALL=$(( (NOW - SESSION_START) / 60 ))
  WALL_STR="${WALL}min"
else
  WALL_STR="(unknown)"
fi

# Roster
PANES=0
LIMITED=0
SATURATED=0
if command -v ntm >/dev/null 2>&1; then
  PANES=$(ntm --robot-snapshot 2>/dev/null | jq --arg s "$SESSION" '[.sessions[]? | select(.name == $s) | .panes[]] | length' 2>/dev/null || echo 0)
  LIMITED=$(ntm --robot-health-oauth="$SESSION" 2>/dev/null | jq '[.panes[]? | select(.rate_limited == true)] | length' 2>/dev/null || echo 0)
  SATURATED=$(ntm --robot-snapshot 2>/dev/null | jq --arg s "$SESSION" '[.sessions[]? | select(.name == $s) | .panes[] | select((.context_pct // 0) >= 85)] | length' 2>/dev/null || echo 0)
fi

# Beads
H_TOTAL=0; H_ACTIVE=0; H_REFUTED=0; H_CONFIRMED=0; EV=0; EV_REFUTES=0; AF_OPEN=0; AF_CRIT=0
if command -v br >/dev/null 2>&1; then
  H_TOTAL=$(br list --label=hypothesis --json 2>/dev/null | jq '.issues | length' 2>/dev/null || echo 0)
  H_ACTIVE=$(br list --label=hypothesis --status=open --json 2>/dev/null | jq '[.issues[]? | select((.description // "") | test("(^|\\n)state:[[:space:]]*active([[:space:]]|$)"))] | length' 2>/dev/null || echo 0)
  H_REFUTED=$(br list --label=hypothesis --json 2>/dev/null | jq '[.issues[]? | select((.description // "") | test("(^|\\n)state:[[:space:]]*refuted([[:space:]]|$)"))] | length' 2>/dev/null || echo 0)
  H_CONFIRMED=$(br list --label=hypothesis --json 2>/dev/null | jq '[.issues[]? | select((.description // "") | test("(^|\\n)state:[[:space:]]*confirmed([[:space:]]|$)"))] | length' 2>/dev/null || echo 0)
  EV=$(br list --label=evidence --json 2>/dev/null | jq '.issues | length' 2>/dev/null || echo 0)
  EV_REFUTES=$(br list --label=evidence --json 2>/dev/null | jq '[.issues[]? | select((.description // "") | contains("refutes: ["))] | length' 2>/dev/null || echo 0)
  AF_OPEN=$(br list --label=audit-finding --status=open --json 2>/dev/null | jq '.issues | length' 2>/dev/null || echo 0)
  AF_CRIT=$(br list --label=audit-finding --status=open --json 2>/dev/null | jq '[.issues[]? | select((.description // "") | contains("severity: critical"))] | length' 2>/dev/null || echo 0)
fi

# Falsifier coverage
H_WITH_FALS=0
if [ "$H_TOTAL" -gt 0 ] && command -v br >/dev/null 2>&1; then
  H_WITH_FALS=$(br list --label=hypothesis --json 2>/dev/null | jq '[.issues[]? | select((.description // "") | contains("falsifier:"))] | length' 2>/dev/null || echo 0)
fi

# Third alternative
THIRD_ALT=0
if command -v br >/dev/null 2>&1; then
  THIRD_ALT=$(br list --label=hypothesis --json 2>/dev/null | jq '[.issues[]? | select((.description // "") | contains("origin: third_alternative"))] | length' 2>/dev/null || echo 0)
fi

# Source corpus coverage. Don't append `|| echo 0` to a pipeline whose normal
# emit is already a number — `set -o pipefail` on an empty `evidence/packs/`
# fails the pipe even though wc -l correctly emits "0", so the fallback
# concatenates a second "0" and produces a multi-line ANCHORS that crashes the
# `[ "$ANCHORS" -ge 15 ]` test in the heredoc (same pattern as round-25's fix
# for grep -c || echo 0). Default-or-zero via parameter expansion instead.
ANCHORS=$( { grep -h -oE '§[0-9]+' evidence/packs/*.md 2>/dev/null | sort -u | wc -l | tr -d ' '; } 2>/dev/null )
ANCHORS=${ANCHORS:-0}

# Operator coverage
OPS_FIRED=0
for OP in '◊' '⊘' '𝓛' '≡' '✂' '⟂' '↑' '⌂' '🔧' '⊞' '🤝' 'ΔE' '†' '∿' '⊙'; do
  if grep -q "$OP" session-logs/*.md evidence/packs/*.md distillations/*.md 2>/dev/null; then
    OPS_FIRED=$((OPS_FIRED + 1))
  fi
done

# Productivity
COMMITS_1H=$(git log --since="1 hour ago" --oneline 2>/dev/null | wc -l | tr -d ' ')

# Convergence (if applicable)
CONV_STATUS="(n/a)"
case "$CURRENT" in
  4|6|7)
    if [ -x "$SCRIPT_DIR/convergence-check.sh" ]; then
      if "$SCRIPT_DIR/convergence-check.sh" --phase="$CURRENT" --workspace="$WORKSPACE" 2>&1 | grep -q "CONVERGED"; then
        CONV_STATUS="CONVERGED"
      else
        CONV_STATUS="not yet"
      fi
    fi
    ;;
esac

cat <<EOF
=== $SESSION session quickref ===

Phase: $CURRENT (last complete: $LAST_COMPLETE) — convergence: $CONV_STATUS
Wall time: $WALL_STR
Roster: $PANES panes ($LIMITED rate-limited, $SATURATED saturated ≥85% ctx)

Beads:
  Hypotheses: $H_ACTIVE active, $H_REFUTED refuted, $H_CONFIRMED confirmed ($H_TOTAL total)
  Evidence:   $EV total ($EV_REFUTES with refutes: populated)
  Audit findings open: $AF_OPEN ($AF_CRIT critical)

Methodology compliance:
  Falsifier coverage: $H_WITH_FALS/$H_TOTAL
  Third alternative present: $([ "$THIRD_ALT" -gt 0 ] && echo "yes ($THIRD_ALT bead(s))" || echo "NO — F-301 risk")

Source corpus coverage: $ANCHORS §-anchors $([ "$ANCHORS" -ge 15 ] && echo "(adequate)" || echo "(thin)")
Operator coverage: $OPS_FIRED/15 fired

Productivity (last 1h): $COMMITS_1H commits

EOF
