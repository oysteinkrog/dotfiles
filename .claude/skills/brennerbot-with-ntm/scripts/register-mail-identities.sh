#!/usr/bin/env bash
# register-mail-identities.sh — Register Agent Mail identity per pane in the session.
#
# Usage:
#   register-mail-identities.sh --project-key=<workspace> --session=<session-name> [--from-resume=<RESUME.md>]
#
# Without --from-resume: registers identities based on the current ntm pane roster.
# With --from-resume: re-registers identities based on RESUME.md.roster.
#
# This is a thin shim. Real MCP Agent Mail registration happens via the agent's MCP tools.
# This script just emits the per-pane register_agent calls and logs them; the operator dispatches.

set -uo pipefail

PROJECT_KEY=""
SESSION=""
FROM_RESUME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    # Accept both hyphen and underscore variants — pipeline yaml files (which use
    # snake_case keys per YAML convention) call this script with `project_key:` etc.,
    # while the documented CLI surface and other shell callers use the hyphen form.
    # Supporting both keeps the shell convention canonical without breaking pipelines.
    --project-key=*|--project_key=*)   PROJECT_KEY="${1#*=}" ;;
    --session=*)                        SESSION="${1#*=}" ;;
    --from-resume=*|--from_resume=*)   FROM_RESUME="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$PROJECT_KEY" ] || [ -z "$SESSION" ]; then
  echo "Usage: register-mail-identities.sh --project-key=<path> --session=<name> [--from-resume=<RESUME.md>]" >&2
  exit 2
fi

PROJECT_KEY_INPUT="$PROJECT_KEY"
if ! PROJECT_KEY="$(cd "$PROJECT_KEY_INPUT" 2>/dev/null && pwd)"; then
  echo "project key/workspace not accessible: $PROJECT_KEY_INPUT" >&2
  exit 1
fi
if [ -n "$FROM_RESUME" ] && [[ "$FROM_RESUME" != /* ]] && [ ! -f "$FROM_RESUME" ] && [ -f "$PROJECT_KEY/$FROM_RESUME" ]; then
  FROM_RESUME="$PROJECT_KEY/$FROM_RESUME"
fi
if [ -n "$FROM_RESUME" ] && [ ! -f "$FROM_RESUME" ]; then
  echo "resume file not found: $FROM_RESUME" >&2
  exit 1
fi
RESUME_KIND=""
ROSTER_LINES=""
if [ -n "$FROM_RESUME" ]; then
  first_non_ws=$(tr -d '[:space:]' < "$FROM_RESUME" | head -c 1)
  if [ "$first_non_ws" = "{" ] || [ "$first_non_ws" = "[" ]; then
    command -v jq >/dev/null 2>&1 || { echo "jq not found; required for parsed JSON resume: $FROM_RESUME" >&2; exit 2; }
    if ! jq -e '.roster? | type == "array" and length > 0' "$FROM_RESUME" >/dev/null 2>&1; then
      echo "parsed JSON resume missing non-empty .roster array: $FROM_RESUME" >&2
      exit 1
    fi
    RESUME_KIND="json"
  else
    ROSTER_LINES=$(awk '
      /^[[:space:]]*roster:/ { in_roster=1; next }
      in_roster && /^[[:alpha:]_][[:alnum:]_]*:/ { in_roster=0 }
      in_roster && /^  - pane:/ { print }
    ' "$FROM_RESUME")
    if [ -z "$ROSTER_LINES" ]; then
      echo "resume file has no roster pane entries: $FROM_RESUME" >&2
      exit 1
    fi
    RESUME_KIND="markdown"
  fi
fi

# Check MCP Agent Mail availability (operator-side; the actual registration is per-pane)
echo "Checking MCP Agent Mail server..." >&2
MAIL_STATUS_CMD=()
if command -v am >/dev/null 2>&1; then
  MAIL_STATUS_CMD=(am mail status "$PROJECT_KEY")
elif command -v mcp-agent-mail >/dev/null 2>&1; then
  MAIL_STATUS_CMD=(env AM_INTERFACE_MODE=cli mcp-agent-mail mail status "$PROJECT_KEY")
fi

if [ "${#MAIL_STATUS_CMD[@]}" -gt 0 ]; then
  if MAIL_STATUS=$("${MAIL_STATUS_CMD[@]}" 2>&1) \
    && ! printf '%s\n' "$MAIL_STATUS" | grep -qiE 'not[[:space:]_-]*(ok|healthy|ready)|unhealthy|degraded|error|failed|unavailable|temporarily busy|"(ok|healthy|ready)"[[:space:]]*:[[:space:]]*false|(^|[^[:alnum:]_])(ok|healthy|ready)[[:space:]]*[:=][[:space:]]*false' \
    && printf '%s\n' "$MAIL_STATUS" | grep -qiE '(^|[^[:alnum:]_])(ok|healthy|ready)([^[:alnum:]_]|$)'; then
    echo "  Agent Mail: healthy" >&2
  else
    echo "  Agent Mail: degraded — falling back to ntm-inbox" >&2
    echo "ntm-inbox-fallback"
    exit 0
  fi
else
  echo "  Agent Mail CLI not present — relying on per-pane MCP availability" >&2
fi

# Build per-pane registration commands
mkdir -p "$PROJECT_KEY/session-logs"
LOG="$PROJECT_KEY/session-logs/mail-registrations-$(date -u +%Y%m%dT%H%M%SZ).log"

if [ -n "$FROM_RESUME" ] && [ -f "$FROM_RESUME" ]; then
  # Parse roster from either raw RESUME.md or the JSON emitted by parse-resume.sh.
  # The resume pipeline passes /tmp/resume-parsed.json here; direct shell callers
  # usually pass the markdown/YAML RESUME.md.
  echo "Re-registering identities from $FROM_RESUME" | tee "$LOG"
  if [ "$RESUME_KIND" = "json" ]; then
    jq -r '.roster[] | "  pane \(.pane): role=\(.role // "unknown") model=\(.model // "unknown") last_thread=\(.last_thread // "none")"' "$FROM_RESUME" >> "$LOG"
  else
    printf '%s\n' "$ROSTER_LINES" >> "$LOG"
  fi
else
  # Get current pane list from ntm
  if command -v ntm >/dev/null 2>&1; then
    command -v jq >/dev/null 2>&1 || { echo "jq not found; required to parse ntm --robot-snapshot" >&2; exit 2; }
    PANES=$(ntm --robot-snapshot 2>/dev/null | jq -r --arg s "$SESSION" '.sessions[]? | select(.name == $s) | .panes[].index' 2>/dev/null)
    if [ -z "$PANES" ]; then
      echo "No panes found for session $SESSION via ntm --robot-snapshot" >&2
      exit 1
    fi
    {
      echo "Registering identities for session $SESSION at $PROJECT_KEY"
      echo "Panes: $PANES"
      for pane in $PANES; do
        echo "  pane $pane: dispatch register_agent(project_key=$PROJECT_KEY, program=<cli>, model=<model>, task_description='brennerbot $SESSION pane p$pane') via MCP"
        echo "           record the returned Agent Mail name as p$pane -> <AgentName> in phase0_scope_decision.md"
      done
    } | tee "$LOG"
  else
    echo "ntm not found and --from-resume was not supplied; cannot derive pane roster" >&2
    exit 2
  fi
fi

echo ""
echo "Note: this script logs intent. Each pane must independently call register_agent via MCP and record the returned Agent Mail name." >&2
echo "The MO-02-onboarding.md template includes the per-pane register_agent step." >&2
echo ""
echo "agent-mail"   # signal mode
