#!/usr/bin/env bash
# generate-soundness-changelog.sh — auto-append to <project>/audit/SOUNDNESS-LOG.md.
# Usage: ./generate-soundness-changelog.sh <audit-dir> <project> [--allow-incomplete]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Sourced through runtime SCRIPT_DIR.
# shellcheck disable=SC1091
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: generate-soundness-changelog.sh <audit-dir> <project> [--allow-incomplete]}"
PROJECT="${2:?usage: generate-soundness-changelog.sh <audit-dir> <project> [--allow-incomplete]}"
ALLOW_INCOMPLETE=0
case "${3:-}" in
  "") ;;
  --allow-incomplete) ALLOW_INCOMPLETE=1 ;;
  *)
    echo "usage: generate-soundness-changelog.sh <audit-dir> <project> [--allow-incomplete]" >&2
    exit 2
    ;;
esac
PROJECT=$(audit_realpath "$PROJECT")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT")

DATE=$(date -u +%Y-%m-%d)
SUMMARY="$AUDIT_DIR/AUDIT_SUMMARY.md"
if [ ! -f "$SUMMARY" ]; then
  if [ "$ALLOW_INCOMPLETE" -ne 1 ]; then
    echo "error: $SUMMARY not found" >&2
    echo "       run this after AUDIT_SUMMARY.md exists, or pass --allow-incomplete" >&2
    echo "       to append an explicitly incomplete entry with unknown metrics." >&2
    exit 2
  fi
  echo "warning: $SUMMARY not found; appending incomplete entry with unknown metrics" >&2
fi

LOG="$PROJECT/audit/SOUNDNESS-LOG.md"
mkdir -p "$(dirname "$LOG")"

# Bootstrap if missing
if [ ! -f "$LOG" ]; then
  cp "$SCRIPT_DIR/../assets/project-level-changelog.md.template" "$LOG"
fi

extract_count() {
  local pattern="$1"
  local default_value="${2:-unknown}"
  local value
  value=$(grep -oE "$pattern" "$SUMMARY" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_value"
  fi
}

# Extract bucket counts from AUDIT_SUMMARY.md (best-effort regex).
A_COUNT=$(extract_count 'STRICTLY_UNAVOIDABLE.*\| [0-9]+')
B_COUNT=$(extract_count 'PERF_ONLY.*\| [0-9]+')
C_COUNT=$(extract_count 'REFACTORABLE.*\| [0-9]+')
if [ -f "$SUMMARY" ]; then
  PEUB_COUNT=$(extract_count 'pre-existing-ub.*\| [0-9]+' 0)
else
  PEUB_COUNT="unknown"
fi

GEIGER="unknown"
if [ -f "$AUDIT_DIR/geiger-after.json" ]; then
  GEIGER=$(jq '[.packages[]?.package.metrics.counters | objects | .[] | numbers] | add // 0' \
           "$AUDIT_DIR/geiger-after.json" 2>/dev/null || echo "unknown")
fi

# Find the version of the primary crate
VERSION=$(grep -m1 '^version' "$PROJECT/Cargo.toml" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")

if grep -Fq -- "- **Audit dir:** \`$AUDIT_DIR\`" "$LOG"; then
  echo "SOUNDNESS-LOG already contains an entry for $AUDIT_DIR; nothing to append."
  exit 0
fi

# Audit number: count existing "### Audit #N" entries (digits required so the
# template's literal "### Audit #<N>" placeholder doesn't get miscounted).
# Also: `grep -c || true` rather than `|| echo 0` so we don't poison the value
# with a trailing "0" on grep's exit-1 (no matches).
N=$(grep -cE '^### Audit #[0-9]+' "$LOG" 2>/dev/null || true)
N=${N:-0}
N=$((N + 1))

# Find the audit-history section's insertion point (right after "## Audit history\n\n(Newest first...)\n\n")
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT

if ! awk -v N="$N" -v date="$DATE" -v ver="$VERSION" -v a="$A_COUNT" -v b="$B_COUNT" -v c="$C_COUNT" \
    -v peub="$PEUB_COUNT" -v g="$GEIGER" -v audir="$AUDIT_DIR" '
  /^## Audit history/ { in_history=1 }
  /^## Incident history/ { in_history=0 }
  in_history && /^\(Newest first/ {
    inserted=1
    print
    print ""
    printf "### Audit #%s — %s — v%s\n\n", N, date, ver
    printf "- **Mode:** see audit dir\n"
    printf "- **Tally:** A=%s; B=%s; C=%s; pre-existing-UB=%s\n", a, b, c, peub
    printf "- **Geiger count:** %s\n", g
    printf "- **Audit dir:** `%s`\n", audir
    printf "- **Auto-generated:** %s\n\n", date
    next
  }
  { print }
  END {
    if (!inserted) exit 3
  }
' "$LOG" > "$TMP"; then
  echo "error: could not find audit-history insertion point in $LOG" >&2
  echo "       expected a line beginning with '(Newest first' after '## Audit history'" >&2
  echo "       leaving SOUNDNESS-LOG unchanged" >&2
  exit 2
fi

mv "$TMP" "$LOG"

echo "Appended audit #$N entry to $LOG"
echo "  Tally: A=$A_COUNT B=$B_COUNT C=$C_COUNT pre-ub=$PEUB_COUNT geiger=$GEIGER"
echo
echo "Review the generated entry and adjust manual fields (Reviewer, Highlights) as needed."
echo "Commit when ready: git add $LOG && git commit -m 'soundness log: audit #$N'"
