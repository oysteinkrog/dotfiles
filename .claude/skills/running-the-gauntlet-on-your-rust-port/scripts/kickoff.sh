#!/usr/bin/env bash
# kickoff.sh — prints the verbatim mode-specific kickoff prompt for the orchestrator.
#
# USAGE:
#   kickoff.sh <mode>
#
# MODES: gauntlet-full | audit-only | harden-pillar | add-feature |
#        incremental-rebase | compliance-pass | red-team | migration |
#        cass-mine-only | quick-smoke | gauntlet-greenfield

set -euo pipefail

usage() { sed -n '2,10p' "$0"; exit "${1:-2}"; }

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage 0
fi

[ $# -ge 1 ] || usage
MODE="$1"
SKILL_ROOT="$(dirname "$(realpath "$0")")/.."

KICKOFF="$SKILL_ROOT/references/methodology/KICKOFF-PROMPTS.md"

if [ ! -f "$KICKOFF" ]; then
  echo "ERROR: $KICKOFF not found" >&2
  exit 2
fi

# Extract the section between mode headers in KICKOFF-PROMPTS.md.
# Headers look like `## ` + backticked mode name + optional suffix, e.g.:
#   ## `gauntlet-full` kickoff
#   ## `quick-smoke` kickoff (SELF-TEST workflow)
# Match the backticked mode name; print everything until the next `## ` heading.
MATCHED=$(awk -v mode="$MODE" '
  $0 ~ "^## `" mode "`" { capture = 1; print; next }
  capture && /^## / { exit }
  capture { print }
' "$KICKOFF")

if [ -z "$MATCHED" ]; then
  echo "ERROR: no kickoff section found for mode '$MODE' in $KICKOFF" >&2
  echo "       (expected a header like '## \`$MODE\` kickoff')" >&2
  echo "Available modes:" >&2
  grep -oE '^## `[a-z-]+`' "$KICKOFF" | sed 's/^## /  /' >&2
  exit 2
fi

printf '%s\n' "$MATCHED"
