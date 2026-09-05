#!/usr/bin/env bash
# wait-for-onboard-acks.sh — Block until every pane has acked Phase 2 onboarding.
#
# Usage:
#   wait-for-onboard-acks.sh --session=<name> [--workspace=<path>] [--timeout=<seconds>] [--via=<agent-mail|ntm-inbox>]

set -uo pipefail

usage() {
  echo "Usage: wait-for-onboard-acks.sh --session=<name> [--workspace=<path>] [--timeout=<seconds>] [--via=<agent-mail|ntm-inbox>]" >&2
}

SESSION=""
WORKSPACE="."
TIMEOUT=300
VIA="agent-mail"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session=*) SESSION="${1#*=}" ;;
    --workspace=*) WORKSPACE="${1#*=}" ;;
    --timeout=*) TIMEOUT="${1#*=}" ;;
    --via=*) VIA="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

if [ -z "$SESSION" ]; then
  usage
  exit 2
fi

case "$TIMEOUT" in
  ''|*[!0-9]*)
    echo "[FATAL] --timeout must be a non-negative integer: $TIMEOUT" >&2
    usage
    exit 2
    ;;
esac

case "$VIA" in
  agent-mail|ntm-inbox)
    ;;
  *)
    echo "[FATAL] --via must be one of: agent-mail, ntm-inbox" >&2
    usage
    exit 2
    ;;
esac

WORKSPACE_ABS="$(cd "$WORKSPACE" 2>/dev/null && pwd)" \
  || { echo "[FATAL] Cannot cd to workspace: $WORKSPACE" >&2; exit 1; }
cd "$WORKSPACE_ABS" || exit 1

if ! command -v ntm >/dev/null 2>&1; then
  echo "[FATAL] ntm not found" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "[FATAL] jq not found" >&2
  exit 2
fi

START=$(date +%s)
DEADLINE=$((START + TIMEOUT))

# Get expected pane count
EXPECTED=$(ntm --robot-snapshot 2>/dev/null | jq -r --arg s "$SESSION" '.sessions[]? | select(.name == $s) | .panes | length' 2>/dev/null || echo 0)
case "${EXPECTED:-}" in
  ''|*[!0-9]*) EXPECTED=0 ;;
esac

if [ "$EXPECTED" -eq 0 ]; then
  echo "Error: cannot determine expected pane count for session $SESSION." >&2
  echo "  Run 'ntm --robot-snapshot' to verify the session exists; pass an explicit --timeout if intentional." >&2
  echo "  Falling back to single-pane wait would risk premature exit; aborting instead." >&2
  exit 2
fi

echo "Waiting for $EXPECTED pane(s) to ack onboarding (timeout=${TIMEOUT}s, via=$VIA)..." >&2

ACKED=0
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  ACKED=0

  if [ "$VIA" = "agent-mail" ]; then
    # Use ntm mail inbox to count onboarding acks
    ACKED=$(ntm mail inbox "$SESSION" --json 2>/dev/null | \
      jq '[.messages[]? | select((.subject // "") | contains("Pane") and contains("ready"))] | length' 2>/dev/null || echo 0)
  elif [ "$VIA" = "ntm-inbox" ]; then
    # Scan pane tails for "ready, role=" pattern (onboarding ack signature from MO-02)
    # NB: don't append `|| echo 0` here — when grep -c finds 0 matches it emits
    # "0" + exits 1, so the fallback would emit a second "0", giving "0\n0" which
    # then breaks the `-ge` arithmetic comparison below. Suppress the exit code
    # without doubling the output.
    ACKED=$(ntm --robot-tail="$SESSION" --lines=50 2>/dev/null | \
      jq -r '.panes[]? | (.lines // [])[]' 2>/dev/null | \
      grep -c 'ready, role=') || true
    ACKED=${ACKED:-0}
  fi

  if [ "$ACKED" -ge "$EXPECTED" ]; then
    echo "All $EXPECTED panes acked." >&2
    exit 0
  fi

  echo "  acked: $ACKED / $EXPECTED — waiting..." >&2
  sleep 10
done

echo "Timeout: only $ACKED / $EXPECTED panes acked within ${TIMEOUT}s." >&2
echo "Check pane state via 'ntm --robot-snapshot' and dispatch MO-02-onboarding.md to laggards." >&2
exit 1
