#!/usr/bin/env bash
# red-flag-scan.sh — Scan pane tails for red-flag phrases per SKILL.md table.
#
# Returns 0 if no red flags detected; 1 if any red flag present.
#
# Usage: red-flag-scan.sh <workspace> [session-name]

set -uo pipefail

WORKSPACE_INPUT="${1:?usage: red-flag-scan.sh <workspace> [session-name]}"
if ! WORKSPACE="$(cd "$WORKSPACE_INPUT" 2>/dev/null && pwd)"; then
  echo "workspace not accessible: $WORKSPACE_INPUT" >&2
  exit 1
fi
SESSION="${2:-brennerbot-$(basename "$WORKSPACE" | sed 's/__brennerbot_session$//')}"

if ! command -v ntm >/dev/null 2>&1; then
  echo "ntm not installed; cannot scan pane tails" >&2
  exit 2
fi
command -v jq >/dev/null 2>&1 || { echo "jq not found; required to parse ntm --robot-tail output" >&2; exit 2; }

# Capture pane tails
TAILS=$(ntm --robot-tail="$SESSION" --lines=30 2>/dev/null | jq -r '.panes | to_entries[]? | "PANE \(.key):\n\((.value.lines // []) | join("\n"))\n---"' 2>/dev/null)

if [ -z "$TAILS" ]; then
  echo "No pane tails available for session: $SESSION" >&2
  exit 2
fi

FOUND=0

# Patterns to check (per SKILL.md Red-Flag Phrases table). Pattern → message.
# Format: pipe-separated `pat|msg` lines, parsed below.
PATTERNS_LIST=$(cat <<'PATEOF'
ready to ship.*no.*EV-|Convergence-language without EV cite (F-701 risk)
I'?ll investigate|Pane stuck in prose (no bead filed)
I'?ll look into|Pane stuck in prose
the answer is clearly|Confirmation bias (F-403)
both [^|]+ and [^|]+ are valid|False-binary collapse (F-302)
Ready for validation|Handoff failure (per /vibing-with-ntm AP-43)
MISSION ACCOMPLISHED|Handoff failure
broadly supported|Vibes-only support
it might be|Hedging in distillation
tends to|Hedging in distillation
no third alternative needed|Refusing third alternative (F-301)
the binary is genuine|Refusing third alternative
the falsifier is too narrow|Soft-falsifier drift
let'?s relax the falsifier|Soft-falsifier drift
we should defer this|Refusing to kill (F-501)
resets [0-9]|Rate limit (per /vibing-with-ntm OC-001)
You'?ve hit your limit|Rate limit
FILE_RESERVATION_CONFLICT|Agent Mail conflict
from_agent not registered|Agent Mail registration issue
PATEOF
)

# To attribute matches to specific panes, run awk over tails tracking the active pane.
# A "PANE N:" line resets current pane; pattern matches inside the block are attributed.
attribute_pane() {
  local pat="$1"
  printf '%s\n' "$TAILS" | awk -v IGNORECASE=1 -v pat="$pat" '
    /^PANE [0-9]+:/ {
      # Capture pane number
      match($0, /[0-9]+/)
      cur = substr($0, RSTART, RLENGTH)
      next
    }
    /^---$/ { cur = ""; next }
    cur != "" && $0 ~ pat { print cur }
  ' | sort -u | head -3 | tr '\n' ' '
}

while IFS='|' read -r pat msg; do
  [ -z "$pat" ] && continue
  if printf '%s\n' "$TAILS" | grep -qiE "$pat"; then
    PANE_HITS=$(attribute_pane "$pat")
    [ -z "$PANE_HITS" ] && PANE_HITS="(unattributed)"
    echo "⚠ $msg"
    echo "    pattern: '$pat'"
    echo "    in panes: $PANE_HITS"
    FOUND=1
  fi
done <<<"$PATTERNS_LIST"

if [ "$FOUND" = "1" ]; then
  echo ""
  echo "Red flags detected. Apply matching cards from SKILL.md § Red-Flag Phrases table."
  exit 1
fi

echo "No red flags detected in pane tails."
exit 0
