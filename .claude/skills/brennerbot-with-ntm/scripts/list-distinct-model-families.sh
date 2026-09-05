#!/usr/bin/env bash
# list-distinct-model-families.sh — Print one model family per line (cc, cod, gmi) present in the session.
#
# Usage: list-distinct-model-families.sh [--session=<session-name>]

set -uo pipefail

SESSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session=*) SESSION="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$SESSION" ]; then
  # Fallback: assume all 3 families if no session named
  printf 'cc\ncod\ngmi\n'
  exit 0
fi

if ! command -v ntm >/dev/null 2>&1; then
  printf 'cc\ncod\ngmi\n'   # fallback
  exit 0
fi

# Extract distinct pane types from ntm snapshot
ntm --robot-snapshot 2>/dev/null | \
  jq -r --arg s "$SESSION" '.sessions[]? | select(.name == $s) | .panes[].type // empty' | \
  sort -u | \
  awk '
    /claude|^cc/  { print "cc"; next }
    /codex|^cod/  { print "cod"; next }
    /gemini|^gmi/ { print "gmi"; next }
  ' | sort -u
