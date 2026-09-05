#!/usr/bin/env bash
# dispatch-marching-order.sh — Render an MO-*.md template with placeholder substitution and dispatch via ntm --robot-send.
#
# Usage:
#   dispatch-marching-order.sh <MO-name> [--<PLACEHOLDER>=<value>...] [--target-pane=<N>] [--target-session=<id>] [--dry-run]
#
# Examples:
#   dispatch-marching-order.sh MO-04a-investigate \
#     --PANE_N=3 --H_ID=H-007 --SESSION_ID=RS-20260506-event-log \
#     --target-pane=3 --target-session=brennerbot-event-log

set -euo pipefail

MO_NAME="${1:?usage: dispatch-marching-order.sh <MO-name> [flags]}"
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Find the MO file
MO_FILE=""
for path in "$SKILL_DIR/assets/marching-orders/$MO_NAME.md" "$SKILL_DIR/assets/marching-orders/${MO_NAME%.md}.md"; do
  if [ -f "$path" ]; then
    MO_FILE="$path"
    break
  fi
done

if [ -z "$MO_FILE" ]; then
  echo "Error: marching order not found: $MO_NAME" >&2
  echo "Looked in: $SKILL_DIR/assets/marching-orders/" >&2
  exit 1
fi

# Parse flags
TARGET_PANE=""
TARGET_SESSION=""
WORKSPACE=""
DRY_RUN="false"
declare -A PARAMS

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-pane=*) TARGET_PANE="${1#*=}" ;;
    --target-session=*) TARGET_SESSION="${1#*=}" ;;
    --workspace=*) WORKSPACE="${1#*=}" ;;
    --dry-run) DRY_RUN="true" ;;
    --*=*)
      key="${1%%=*}"
      key="${key#--}"
      val="${1#*=}"
      PARAMS[$key]="$val"
      ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -n "$WORKSPACE" ]; then
  WORKSPACE_INPUT="$WORKSPACE"
  if ! WORKSPACE="$(cd "$WORKSPACE_INPUT" 2>/dev/null && pwd)"; then
    echo "workspace not accessible: $WORKSPACE_INPUT" >&2
    exit 1
  fi
fi

# Reserved placeholders (auto-set)
PARAMS[TIMESTAMP_UTC]="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# Auto-populate WORKSPACE_PATH from --workspace if the caller didn't pass it
# explicitly. Many MOs (MO-08-freeze, MO-09-handback, MO-evidence-intake-url,
# etc.) declare <WORKSPACE_PATH> as a parameter; without this auto-set, every
# pipeline step that passes --workspace=${workspace_path} would also have to
# repeat --WORKSPACE_PATH=${workspace_path}.
if [ -n "$WORKSPACE" ] && [ -z "${PARAMS[WORKSPACE_PATH]+x}" ]; then
  PARAMS[WORKSPACE_PATH]="$WORKSPACE"
fi
WORKSPACE_HINT="${WORKSPACE:-${PARAMS[WORKSPACE_PATH]:-}}"
if [ -n "$WORKSPACE_HINT" ]; then
  if [ -z "${PARAMS[SESSION_ID]+x}" ] && [ -f "$WORKSPACE_HINT/.brenner_workspace/phase0_scope_decision.md" ]; then
    session_id=$(sed -n 's/^# Phase 0 Scope Decision .* //p' "$WORKSPACE_HINT/.brenner_workspace/phase0_scope_decision.md" | head -1)
    [ -n "$session_id" ] && PARAMS[SESSION_ID]="$session_id"
  fi
  if [ -z "${PARAMS[QUESTION_OF_RECORD_PATH]+x}" ]; then
    PARAMS[QUESTION_OF_RECORD_PATH]="$WORKSPACE_HINT/intake/question_of_record.md"
  fi
fi
if [ -z "${PARAMS[SKILL_SCRIPTS]+x}" ]; then
  PARAMS[SKILL_SCRIPTS]="$SCRIPT_DIR"
fi

# Render the MO with substitutions
RENDERED="$(cat "$MO_FILE")"
for key in "${!PARAMS[@]}"; do
  val="${PARAMS[$key]}"
  # Escape sed special chars: backslash, forward-slash, ampersand. Newlines are not supported.
  # Detect via case-glob, NOT `grep -q $'\n'`: grep treats a newline in the
  # pattern as a line separator that splits the pattern into multiple empty
  # sub-patterns ("" || ""), so `grep -q $'\n'` matches every input
  # unconditionally. The case-glob test correctly checks for an embedded
  # literal newline.
  case "$val" in
    *$'\n'*)
      echo "Warning: parameter $key contains a newline; collapsing to space" >&2
      val=$(printf '%s' "$val" | tr '\n' ' ')
      ;;
  esac
  val_escaped=$(printf '%s' "$val" | sed -e 's/[\\/&]/\\&/g')
  RENDERED=$(printf '%s' "$RENDERED" | sed "s/<$key>/$val_escaped/g")
done

# Validate: only check placeholders that the MO explicitly declares in its
# `**Parameters:**` line. The previous form `grep -oE '<[A-Z][A-Z0-9_]+>'` over
# the whole rendered body matched instructional fill-ins like `<NNN>`, `<N>`,
# `<ISO>`, `<YYYYMMDD>` that appear inside example code blocks (they're meant
# for the receiving agent to populate, not the dispatcher) — so EVERY Phase 4
# dispatch failed with "unresolved: <NNN>" before reaching ntm.
#
# Build the declared-param set from the MO body, intersect with what's still in
# RENDERED, and complain only about those.
declare -a declared_params=()
PARAM_LINE=$(grep -m1 '^\*\*Parameters:\*\*' "$MO_FILE" 2>/dev/null || true)
if [ -n "$PARAM_LINE" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] && declared_params+=("$p")
  done < <(printf '%s' "$PARAM_LINE" | grep -oE '<[A-Z][A-Z0-9_]+>' | sort -u)
fi

UNRESOLVED=""
for p in "${declared_params[@]+"${declared_params[@]}"}"; do
  if printf '%s' "$RENDERED" | grep -qF "$p"; then
    UNRESOLVED="$UNRESOLVED $p"
  fi
done

if [ -n "$UNRESOLVED" ]; then
  echo "Error: unresolved declared placeholders in rendered MO ($MO_NAME):" >&2
  for p in $UNRESOLVED; do echo "  $p" >&2; done
  echo "  (Pass them as --KEY=value flags. Instructional placeholders inside example blocks like <NNN>, <N>, <ISO> are intentional and not checked.)" >&2
  exit 1
fi

# Log the dispatch (to workspace session-logs/, not skill dir)
LOG_DIR="${WORKSPACE:-${PARAMS[WORKSPACE_PATH]:-$PWD}}/session-logs"
mkdir -p "$LOG_DIR"
LOG_STAMP="$(date -u +%Y%m%dT%H%M%S%NZ)"
LOG="$LOG_DIR/dispatch-${LOG_STAMP}-$$.log"
{
  echo "=== Dispatch ==="
  echo "MO: $MO_NAME"
  echo "Target pane: $TARGET_PANE"
  echo "Target session: $TARGET_SESSION"
  echo "Params:"
  for key in "${!PARAMS[@]}"; do
    echo "  $key=${PARAMS[$key]}"
  done
  echo ""
  echo "=== Rendered ==="
  echo "$RENDERED"
} > "$LOG"

if [ "$DRY_RUN" = "true" ]; then
  echo "Dry-run: would dispatch to pane=$TARGET_PANE session=$TARGET_SESSION"
  echo "Rendered MO logged at: $LOG"
  echo ""
  echo "$RENDERED" | head -30
  echo "..."
  exit 0
fi

# Dispatch via ntm --robot-send. `--no-cass-check` is an `ntm send` flag;
# robot-send rejects it, and robot mode already bypasses the interactive send
# path that performs CASS duplicate checks.
if [ -z "$TARGET_PANE" ] || [ -z "$TARGET_SESSION" ]; then
  echo "Error: --target-pane and --target-session required (unless --dry-run)" >&2
  exit 2
fi

ntm --robot-send="$TARGET_SESSION" --panes="$TARGET_PANE" --msg="$RENDERED"
echo "Dispatched MO=$MO_NAME to session=$TARGET_SESSION pane=$TARGET_PANE"
echo "Log: $LOG"
