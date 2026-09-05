#!/usr/bin/env bash
# run-loom.sh — loom concurrency-test runner
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: run-loom.sh <audit-dir> [<project-dir>]}"
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
mkdir -p "$(dirname "$LOG")"
cd "$PROJECT_DIR"

if ! grep -q "loom_concurrency_tests" Cargo.toml ./*/Cargo.toml 2>/dev/null; then
  echo "## loom — SKIPPED (no loom_concurrency_tests feature configured)" >> "$LOG"
  exit 0
fi

{
echo
echo "## loom"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo '```'
} >> "$LOG"

if RUSTFLAGS="--cfg loom" cargo test --features loom_concurrency_tests --release 2>&1 | tee -a "$LOG"; then
  echo '```' >> "$LOG"
  echo "Status: GREEN" >> "$LOG"
else
  echo '```' >> "$LOG"
  echo "Status: FAILED" >> "$LOG"
fi
