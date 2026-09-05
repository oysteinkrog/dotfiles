#!/usr/bin/env bash
# scripts/dispatch-subagent.sh — best-effort wrapper for invoking a gauntlet subagent.
#
# The actual dispatch mechanism varies per operator setup:
#   - NTM-based:  `ntm send <session> --file <marching-order> --pane <N>` (preferred for swarm work)
#   - Claude Code Agent tool: render a prompt for the caller's Agent tool
#   - Inline:     read the subagent .md, treat as a prompt, execute by hand
#   - rch-offload: dispatch to a remote rch worker for long-running operations
#
# This script provides a unified CLI surface; the actual dispatch is delegated based on
# the GAUNTLET_DISPATCH environment variable.
#
# Usage:
#   dispatch-subagent.sh <subagent-name> [--param key=value ...] [--thread <id>] [--lane cc_N]
#                                        [--reservation tool://...] [--rch | --rch-if-large]
#                                        [--workspace <path>] [--target <path>]
#
# Environment:
#   GAUNTLET_DISPATCH  one of: ntm | claude-code | inline | dry-run (default: dry-run)
#   GAUNTLET_NTM_SESSION  required when GAUNTLET_DISPATCH=ntm
#
# Exit codes:
#   0  = dispatched/rendered successfully (or dry-run completed)
#   1  = subagent file not found
#   2  = bad arguments
#   3  = dispatch mechanism unavailable
#
# Per references/orchestration/PARALLEL-FAN-OUT-COOKBOOK.md.

set -euo pipefail

SKILL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUBAGENT_DIR="$SKILL_ROOT/subagents"
MO_DIR="$SKILL_ROOT/assets/ntm-marching-orders"

usage() {
  cat <<'EOF'
dispatch-subagent.sh — unified CLI for invoking a gauntlet subagent.

Usage:
  dispatch-subagent.sh <subagent-name> [options]

Options:
  --param KEY=VALUE       Subagent parameter (repeatable)
  --thread ID             MCP Agent Mail thread ID
  --lane cc_N             Pane lane (cc_1=conformance / cc_2=perf / cc_3=surface / cc_4=soak)
  --reservation URI       File-or-tool reservation URI (e.g., tool://comprehensive-bench)
  --rch                   Force rch offload
  --rch-if-large          Offload to rch only if estimated wall-time > 5 min
  --workspace PATH        Gauntlet workspace path
  --target PATH           Port/project source path
  --dry-run               Print what would be dispatched without doing it (default if
                          GAUNTLET_DISPATCH is unset)

Environment:
  GAUNTLET_DISPATCH       ntm | claude-code | inline | dry-run (default: dry-run)
  GAUNTLET_NTM_SESSION    required when GAUNTLET_DISPATCH=ntm
EOF
  exit "${1:-2}"
}

[ $# -lt 1 ] && usage 2
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage 0
fi

SUBAGENT="$1"; shift

# Parse options.
PARAMS=()
THREAD=""
LANE=""
RESERVATION=""
RCH_FLAG=""
WORKSPACE=""
TARGET=""
DRY_RUN_FORCE=""

# Helper: require a value for an option, error helpfully if missing.
need_value() {
  local opt="$1"
  local val="${2-}"
  [ -n "$val" ] || { echo "ERROR: $opt requires a value" >&2; usage 2; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --param)         need_value --param "${2-}";       PARAMS+=("$2");        shift 2 ;;
    --thread)        need_value --thread "${2-}";      THREAD="$2";           shift 2 ;;
    --lane)          need_value --lane "${2-}";        LANE="$2";             shift 2 ;;
    --reservation)   need_value --reservation "${2-}"; RESERVATION="$2";      shift 2 ;;
    --rch)           RCH_FLAG="--rch";                                        shift ;;
    --rch-if-large)  RCH_FLAG="--rch-if-large";                               shift ;;
    --workspace)     need_value --workspace "${2-}";   WORKSPACE="$2";        shift 2 ;;
    --target)        need_value --target "${2-}";      TARGET="$2";           shift 2 ;;
    --dry-run)       DRY_RUN_FORCE=1;                                         shift ;;
    -h|--help)       usage 0 ;;
    *)               echo "ERROR: unknown option '$1'" >&2; usage 2 ;;
  esac
done

SUBAGENT_FILE="$SUBAGENT_DIR/${SUBAGENT}.md"
[ -f "$SUBAGENT_FILE" ] || { echo "ERROR: subagent file not found: $SUBAGENT_FILE" >&2; exit 1; }

DISPATCH="${GAUNTLET_DISPATCH:-dry-run}"
[ -n "$DRY_RUN_FORCE" ] && DISPATCH="dry-run"

# Build the substitution payload.
PAYLOAD_VARS=""
if [ "${#PARAMS[@]}" -gt 0 ]; then
  PAYLOAD_VARS=$(printf '  - %s\n' "${PARAMS[@]}")
fi
[ -n "$WORKSPACE" ] && PAYLOAD_VARS+="${PAYLOAD_VARS:+$'\n'}  - WORKSPACE_PATH=$WORKSPACE"
[ -n "$TARGET" ]    && PAYLOAD_VARS+="${PAYLOAD_VARS:+$'\n'}  - TARGET_PATH=$TARGET"
[ -n "$LANE" ]      && PAYLOAD_VARS+="${PAYLOAD_VARS:+$'\n'}  - LANE=$LANE"

case "$DISPATCH" in
  dry-run)
    cat <<EOF
[dry-run] Would dispatch subagent: $SUBAGENT
  File:       $SUBAGENT_FILE
  Thread:     ${THREAD:-(none)}
  Lane:       ${LANE:-(none)}
  Reservation: ${RESERVATION:-(none)}
  RCH flag:   ${RCH_FLAG:-(none)}
  Workspace:  ${WORKSPACE:-(none)}
  Target:     ${TARGET:-(none)}
  Params:
${PAYLOAD_VARS:-    (none)}
EOF
    ;;

  ntm)
    [ -n "${GAUNTLET_NTM_SESSION:-}" ] || { echo "ERROR: GAUNTLET_NTM_SESSION not set" >&2; exit 3; }
    command -v ntm >/dev/null 2>&1 || { echo "ERROR: ntm not on PATH" >&2; exit 3; }
    # Map subagent → marching order if one exists.
    MO_FILE="$MO_DIR/MO-${SUBAGENT}.md"
    if [ -f "$MO_FILE" ]; then
      echo "Dispatching via NTM session=$GAUNTLET_NTM_SESSION using MO: $MO_FILE"
      ntm send "$GAUNTLET_NTM_SESSION" --file "$MO_FILE"
    else
      echo "Dispatching via NTM session=$GAUNTLET_NTM_SESSION using subagent body: $SUBAGENT_FILE"
      ntm send "$GAUNTLET_NTM_SESSION" --file "$SUBAGENT_FILE"
    fi
    ;;

  claude-code)
    # Prompt-export backend; the caller is expected to be in a Claude Code
    # session and to pass this rendered prompt to the Agent tool.
    cat "$SUBAGENT_FILE"
    echo
    echo "# PARAMS"
    printf '%s\n' "${PARAMS[@]:-}"
    ;;

  inline)
    # Just print the subagent body for the operator to read + execute by hand.
    cat "$SUBAGENT_FILE"
    ;;

  *)
    echo "ERROR: unknown GAUNTLET_DISPATCH value: $DISPATCH" >&2
    echo "Valid values: ntm | claude-code | inline | dry-run" >&2
    exit 2
    ;;
esac
