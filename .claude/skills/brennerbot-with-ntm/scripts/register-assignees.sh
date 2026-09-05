#!/usr/bin/env bash
# register-assignees.sh — When Agent Mail is unavailable, register pane identities via bead assignees.
#
# Usage: register-assignees.sh --session=<session-name> [--workspace=<path>]
#
# Each pane's identity is its pane index (p1, p2, ...). To "claim" beads, panes
# update bead.assignee field. This is the soft-lock fallback per AGENT-MAIL-FALLBACKS.md.

set -uo pipefail

SESSION=""
WORKSPACE="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session=*) SESSION="${1#*=}" ;;
    --workspace=*) WORKSPACE="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$SESSION" ]; then
  echo "Usage: register-assignees.sh --session=<name> [--workspace=<path>]" >&2
  exit 2
fi

WORKSPACE_INPUT="$WORKSPACE"
if ! WORKSPACE="$(cd "$WORKSPACE_INPUT" 2>/dev/null && pwd)"; then
  echo "workspace not accessible: $WORKSPACE_INPUT" >&2
  exit 1
fi

# This script doesn't actually call br update — it just logs the convention.
# Each pane is expected to use `br update <bead-id> --assignee=p<N>` when claiming work.

LOG="$WORKSPACE/session-logs/assignee-registration-$(date -u +%Y%m%dT%H%M%SZ).log"
mkdir -p "$(dirname "$LOG")"

{
  echo "ntm-inbox-fallback mode: register-assignees.sh"
  echo "Session: $SESSION"
  echo "Convention: each pane is identified by p<N> in br assignee field."
  echo ""
  echo "Per AGENT-MAIL-FALLBACKS.md:"
  echo "  - To claim a bead: br update <bead-id> --assignee=p<N> --status=in_progress"
  echo "  - To release: br update <bead-id> --assignee="
  echo "  - Cross-pane coordination: prefix subjects with [<thread-id>] in ntm send messages"
  echo "  - File-reservation safety: NOT enforced; rely on git surface conflicts"
} | tee "$LOG"

echo "ntm-inbox"   # signal mode to caller
