#!/usr/bin/env bash
# run-fuzz.sh — cargo-fuzz smoke runner (60s per target)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: run-fuzz.sh <audit-dir> [<project-dir>] [<seconds-per-target>]}"
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
SECONDS_PER="${3:-60}"
LOG="$AUDIT_DIR/audit/phase7/verification-log.md"
mkdir -p "$(dirname "$LOG")"
cd "$PROJECT_DIR"

if [ ! -d fuzz ]; then
  echo "## cargo-fuzz — SKIPPED (no fuzz/ directory)" >> "$LOG"
  exit 0
fi

{
echo
echo "## cargo-fuzz (smoke, ${SECONDS_PER}s per target)"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo '```'
} >> "$LOG"

OVERALL_OK=true
for target in $(cargo fuzz list 2>/dev/null); do
  echo "    target: $target" >> "$LOG"
  if cargo +nightly fuzz run "$target" -- -max_total_time="$SECONDS_PER" 2>&1 | tee -a "$LOG"; then
    :
  else
    OVERALL_OK=false
  fi
done

echo '```' >> "$LOG"
if $OVERALL_OK; then
  echo "Status: GREEN" >> "$LOG"
else
  echo "Status: FAILED — at least one target found UB/panic" >> "$LOG"
fi
