#!/usr/bin/env bash
# build-safe-only-matrix.sh — build + test under default and safe-only features locally
# Usage: ./build-safe-only-matrix.sh <audit-dir> [<project-dir>]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: build-safe-only-matrix.sh <audit-dir> [<project-dir>]}"
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
LOG="$AUDIT_DIR/audit/phase7/safe-only-matrix.log"
mkdir -p "$(dirname "$LOG")"
cd "$PROJECT_DIR"

{
  echo "# safe-only matrix run"
  echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
} > "$LOG"

# Sanity check
if ! grep -q "safe-only" Cargo.toml ./*/Cargo.toml 2>/dev/null; then
  echo "ERROR: no safe-only feature defined in any Cargo.toml" | tee -a "$LOG"
  exit 1
fi

run_step() {
  local name="$1"; shift
  echo "==> $name" | tee -a "$LOG"
  if "$@" 2>&1 | tee -a "$LOG"; then
    echo "    OK" | tee -a "$LOG"
  else
    echo "    FAILED" | tee -a "$LOG"
    return 1
  fi
}

OVERALL=0
run_step "build (default)"   cargo build --workspace --all-features || OVERALL=1
run_step "test (default)"    cargo test  --workspace --all-features || OVERALL=1
run_step "build (safe-only)" cargo build --workspace --features safe-only --no-default-features || OVERALL=1
run_step "test (safe-only)"  cargo test  --workspace --features safe-only --no-default-features || OVERALL=1

if [ "$OVERALL" -eq 0 ]; then
  echo "Matrix run complete: GREEN. See $LOG"
else
  echo "Matrix run complete: FAILED. See $LOG"
fi
exit "$OVERALL"
