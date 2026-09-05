#!/usr/bin/env bash
# update-ratchet-state.sh — explicit score-artifact entrypoint for ratchet updates.
#
# USAGE:
#   update-ratchet-state.sh <workspace> <score-artifact.json> [--waiver <reason>]
#
# Delegates to apply-ratchet.sh so every state write uses the same monotonicity
# and waiver rules as the CI gate.

set -euo pipefail

usage() {
  sed -n '2,8p' "$0"
  exit "${1:-3}"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage 0
fi

WORKSPACE="${1:-}"
SCORE="${2:-}"
if [ -z "$WORKSPACE" ] || [ -z "$SCORE" ]; then
  usage
fi
shift 2

WAIVER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --waiver)
      [ $# -ge 2 ] || { echo "Missing value for --waiver" >&2; exit 2; }
      WAIVER="$2"; shift 2;;
    -h|--help) usage 0;;
    *) echo "Unknown arg: $1" >&2; usage;;
  esac
done

[ -f "$SCORE" ] || { echo "ERROR: $SCORE not found" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARGS=("$WORKSPACE" --score "$SCORE")
[ -n "$WAIVER" ] && ARGS+=(--waiver "$WAIVER")

exec "$SCRIPT_DIR/apply-ratchet.sh" "${ARGS[@]}"
