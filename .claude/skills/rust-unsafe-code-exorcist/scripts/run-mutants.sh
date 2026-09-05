#!/usr/bin/env bash
# run-mutants.sh — cargo-mutants verifies tests pin behavior
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: run-mutants.sh <audit-dir> [<project-dir>]}"
AUDIT_DIR=$(audit_realpath "$AUDIT_DIR")
AUDIT_PROJECT_ROOT=$(audit_project_root_from_dir "$AUDIT_DIR")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$AUDIT_PROJECT_ROOT")

infer_project_dir() {
  if [ -f "$AUDIT_DIR/phase1/project-root.txt" ]; then
    sed -n '1p' "$AUDIT_DIR/phase1/project-root.txt"
    return
  fi
  local cur
  cur="$(realpath "$AUDIT_DIR/..")"
  while [ "$cur" != "/" ]; do
    if [ -f "$cur/Cargo.toml" ]; then
      printf '%s\n' "$cur"
      return
    fi
    cur="$(dirname "$cur")"
  done
  realpath "$AUDIT_DIR/.."
}

PROJECT_DIR="${2:-$(infer_project_dir)}"
PROJECT_DIR=$(audit_realpath "$PROJECT_DIR")
LOG="$AUDIT_DIR/audit/phase7/verification-log.md"
OUT="$AUDIT_DIR/audit/phase9/mutants/"
mkdir -p "$OUT"
cd "$PROJECT_DIR"

{
echo
echo "## cargo-mutants"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo '```'
} >> "$LOG"

if cargo mutants --in-place=false --jobs 4 --output "$OUT" 2>&1 | tee -a "$LOG"; then
  echo '```' >> "$LOG"
  echo "Status: GREEN" >> "$LOG"
  CAUGHT=$(jq -r '.outcomes[] | select(.outcome == "caught") | .id' "$OUT/outcomes.json" 2>/dev/null | wc -l | tr -d ' ' || echo 0)
  MISSED=$(jq -r '.outcomes[] | select(.outcome == "missed") | .id' "$OUT/outcomes.json" 2>/dev/null | wc -l | tr -d ' ' || echo 0)
  TOTAL=$((CAUGHT + MISSED))
  if [ "$TOTAL" -gt 0 ]; then
    PCT=$(echo "scale=1; 100 * $CAUGHT / $TOTAL" | bc)
    echo "Coverage: $CAUGHT/$TOTAL = ${PCT}% mutations caught" >> "$LOG"
    if (( $(echo "$PCT < 80" | bc -l) )); then
      echo "WARNING: < 80% coverage — tests may not pin behavior tightly enough" >> "$LOG"
    fi
  fi
else
  echo '```' >> "$LOG"
  echo "Status: FAILED" >> "$LOG"
fi
