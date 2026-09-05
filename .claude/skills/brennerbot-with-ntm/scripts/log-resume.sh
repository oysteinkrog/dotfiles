#!/usr/bin/env bash
# log-resume.sh — Append a resume event to session-logs/.
#
# Usage: log-resume.sh --workspace=<path> --resume-path=<RESUME.md>

set -uo pipefail

WORKSPACE=""
RESUME_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace=*) WORKSPACE="${1#*=}" ;;
    # Accept both hyphen and underscore — pipeline yaml callers use snake_case keys
    # (e.g., `resume_path:`) while shell callers use the documented hyphen form.
    --resume-path=*|--resume_path=*) RESUME_PATH="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$WORKSPACE" ]; then
  echo "Usage: log-resume.sh --workspace=<path> --resume-path=<RESUME.md>" >&2
  exit 2
fi

WORKSPACE_INPUT="$WORKSPACE"
if ! WORKSPACE="$(cd "$WORKSPACE_INPUT" 2>/dev/null && pwd)"; then
  echo "workspace not accessible: $WORKSPACE_INPUT" >&2
  exit 1
fi
if [ -n "$RESUME_PATH" ] && [[ "$RESUME_PATH" != /* ]] && [ ! -f "$RESUME_PATH" ] && [ -f "$WORKSPACE/$RESUME_PATH" ]; then
  RESUME_PATH="$WORKSPACE/$RESUME_PATH"
fi

mkdir -p "$WORKSPACE/session-logs"
LOG="$WORKSPACE/session-logs/resume-$(date -u +%Y%m%dT%H%M%SZ).md"

{
  echo "# Resume event — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  echo "Resumed from: $RESUME_PATH"
  echo "Workspace: $WORKSPACE"
  echo ""
  echo "## RESUME.md tokens"
  if [ -f "$RESUME_PATH" ]; then
    grep -E '^(session_id|mode_to_resume|last_phase_completed|next_loop_recommendation):' "$RESUME_PATH" 2>/dev/null
  fi
  echo ""
  echo "## ntm snapshot at resume"
  if command -v ntm >/dev/null 2>&1; then
    ntm --robot-snapshot 2>/dev/null | jq '.sessions[]? | {name, panes: (.panes | length)}' 2>/dev/null
  fi
  echo ""
  echo "## Beads at resume"
  if command -v br >/dev/null 2>&1; then
    cd "$WORKSPACE" && br list --json 2>/dev/null | jq '.issues | length' 2>/dev/null
  fi
} > "$LOG"

echo "Resume logged: $LOG" >&2
