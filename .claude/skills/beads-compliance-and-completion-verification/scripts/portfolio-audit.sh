#!/usr/bin/env bash
# portfolio-audit.sh — Audit every repo with .beads/ under a parent directory.
#
# Usage:
#   portfolio-audit.sh [parent-dir] [max-parallel] [max-age-hours]
#
# Defaults:
#   parent-dir      /data/projects
#   max-parallel    4
#   max-age-hours   168  (one week — skip repos with a recent pass)
#
# Honors ~/.audit_portfolio_excludes (one absolute repo path per line) so you
# can exempt projects that should not be audited (forks, archives, third-party).
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

PARENT="${1:-/data/projects}"
MAX_PARALLEL="${2:-4}"
MAX_AGE_HOURS="${3:-168}"
EXCLUDES_FILE="${HOME}/.audit_portfolio_excludes"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

is_excluded() {
  [ -f "$EXCLUDES_FILE" ] || return 1
  grep -Fxq "$1" "$EXCLUDES_FILE"
}

discover_repos() {
  if command -v ru >/dev/null 2>&1; then
    ru list --has-beads --json 2>/dev/null \
      | jq -r '.[].path // empty' 2>/dev/null || true
  fi
  # `-print0 | xargs -0` (and `-printf '%h\n'` to emit the parent dir
  # directly) handles repo names containing whitespace or newlines safely;
  # the prior `... | xargs -I{} dirname {}` pipeline silently corrupted
  # such paths (SC2038).
  find "$PARENT" -maxdepth 3 -type d -name '.beads' \
    -not -path '*/beads_compliance_audit/*' \
    -not -path '*/target/*' -not -path '*/node_modules/*' \
    -printf '%h\n' 2>/dev/null
}

mapfile -t ALL_REPOS < <(discover_repos | sort -u)
REPOS=()
for r in "${ALL_REPOS[@]}"; do
  is_excluded "$r" || REPOS+=("$r")
done

if [ "${#REPOS[@]}" -eq 0 ]; then
  echo "No repos with .beads/ found under $PARENT (and not excluded)." >&2
  exit 0
fi

echo "Discovered ${#REPOS[@]} candidate repos under $PARENT" >&2

LOGDIR="$(mktemp -d)"
trap 'echo "Per-repo logs in: $LOGDIR" >&2' EXIT

audit_one() {
  local REPO="$1"
  local NAME="$(basename "$REPO")"
  local AUDIT_DIR="$REPO/beads_compliance_audit"

  # Skip if recent pass exists.
  if [ -f "$AUDIT_DIR/manifest.json" ]; then
    LAST=$(jq -r '.pass_completed_at // empty' "$AUDIT_DIR/manifest.json" 2>/dev/null || true)
    if [ -n "$LAST" ]; then
      LAST_SECS=$(date -d "$LAST" +%s 2>/dev/null || echo 0)
      AGE_HOURS=$(( ( $(date +%s) - LAST_SECS ) / 3600 ))
      if [ "$AGE_HOURS" -lt "$MAX_AGE_HOURS" ] && [ "$AGE_HOURS" -ge 0 ]; then
        echo "SKIP $NAME (last pass $AGE_HOURS h ago)" >&2
        return 0
      fi
    fi
  fi

  echo "AUDIT $NAME starting" >&2
  if "$SKILL_DIR/scripts/run-pass.sh" "$REPO" --threshold 700 --policy report-only \
       >"$LOGDIR/$NAME.log" 2>&1; then
    echo "AUDIT $NAME OK" >&2
  else
    EXIT=$?
    echo "AUDIT $NAME FAILED (exit=$EXIT) — see $LOGDIR/$NAME.log" >&2
  fi
}

export -f audit_one
export SKILL_DIR LOGDIR MAX_AGE_HOURS

# Bash-only fan-out (no GNU parallel dependency). Cap at MAX_PARALLEL.
N=0
for REPO in "${REPOS[@]}"; do
  ( audit_one "$REPO" ) &
  N=$((N+1))
  if [ "$N" -ge "$MAX_PARALLEL" ]; then
    wait -n || true
    N=$((N-1))
  fi
done
wait || true

# Roll up.
ROLLUP="$PARENT/__audit_portfolio_summary.md"
python3 "$SKILL_DIR/scripts/portfolio-rollup.py" "$PARENT" > "$ROLLUP" \
  || { echo "ERROR: portfolio rollup failed" >&2; exit 4; }

echo "" >&2
echo "Portfolio summary written to: $ROLLUP" >&2
