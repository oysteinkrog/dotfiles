#!/usr/bin/env bash
# prefix-classifier.sh — Classify stash messages into known smell-categories.
#
# Reads inventory.tsv; writes <workspace>/prefix_classification.tsv with
# columns: n, ref, message, smell_category, default_verdict_prior, confidence.

set -euo pipefail

PROJECT="${1:?Usage: prefix-classifier.sh <project-path>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
INVENTORY="$WORKSPACE/inventory.tsv"
OUT="$WORKSPACE/prefix_classification.tsv"

classify() {
  local msg="$1"
  case "$msg" in
    other-agent-broken*|*do-not-restore*|*-broken)
      printf 'other-agent-broken\tgarbage\t0.99' ;;
    temp-pre-push*|pre-push-stash*)
      printf 'temp-pre-push\tgarbage\t0.95' ;;
    full-tree-reset-stash*|reset-bail-out*|panic-stash*)
      printf 'full-tree-reset-stash\tgarbage\t0.95' ;;
    autostash*)
      printf 'autostash\tgarbage\t0.90' ;;
    pre-deadlock-fix*|pre-*-fix*|safety-pre-*)
      printf 'pre-refactor-stash\tsuperseded\t0.75' ;;
    'WIP on (no branch)'*)
      printf 'detached-head-stash\tunknown\t0.50' ;;
    wip-*|*-wip-*|WIP-*)
      printf 'wip-ticket\tsuperseded\t0.70' ;;
    '')
      printf 'empty-message\tunknown\t0.40' ;;
    *)
      printf 'unrecognized\tunknown\t0.50' ;;
  esac
}

printf 'n\tref\tmessage\tsmell_category\tdefault_verdict_prior\tconfidence\n' > "$OUT"

awk -F'\t' 'NR > 1 {printf "%s\t%s\t%s\n", $1, $2, $7}' "$INVENTORY" \
| while IFS=$'\t' read -r n ref msg; do
  classification=$(classify "$msg")
  printf '%s\t%s\t%s\t%s\n' "$n" "$ref" "$msg" "$classification" >> "$OUT"
done

echo "wrote $OUT"
echo
echo "Smell distribution:"
awk -F'\t' 'NR > 1 {counts[$4]++} END {for (s in counts) printf "  %-30s %s\n", s, counts[s]}' "$OUT" | sort -k2 -rn
