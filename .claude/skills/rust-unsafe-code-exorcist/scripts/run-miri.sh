#!/usr/bin/env bash
# run-miri.sh — Phase 7 / Phase 9 miri runner; tees to verification-log.md
# Usage: ./run-miri.sh <audit-dir> [<project-dir>]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: run-miri.sh <audit-dir> [<project-dir>]}"
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

{
echo
echo "## miri (default)"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo '```'
} >> "$LOG"

if cargo +nightly miri test --workspace --all-features 2>&1 | tee -a "$LOG"; then
  echo '```' >> "$LOG"
  echo "Status: GREEN" >> "$LOG"
else
  echo '```' >> "$LOG"
  echo "Status: FAILED" >> "$LOG"
  echo "Triage per operator ⚑ Pre-Existing-UB-Isolator (PHASES.md § Phase 7)" >> "$LOG"
fi

{
echo
echo "## miri (strict provenance)"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo '```'
} >> "$LOG"

if MIRIFLAGS="-Zmiri-strict-provenance" cargo +nightly miri test --workspace --all-features 2>&1 | tee -a "$LOG"; then
  echo '```' >> "$LOG"
  echo "Status: GREEN" >> "$LOG"
else
  echo '```' >> "$LOG"
  echo "Status: FAILED (strict-provenance — review)" >> "$LOG"
fi

# miri run for every binary target — covers main()-side UB that miri test
# never reaches (the test harness skips fn main entry points).
#
# Enumerate via cargo metadata. Skip cleanly when no binaries exist (pure
# library), or when miri can't execute one (FFI / fs IO miri doesn't model
# — a documented limitation, not a soundness fail).
BINARIES=$(cargo metadata --format-version 1 --no-deps 2>/dev/null | \
  jq -r '.packages[] | .targets[] | select(.kind[] == "bin") | "\(.name)\t\(.src_path)"' \
  2>/dev/null || true)

if [ -z "$BINARIES" ]; then
  {
    echo
    echo "## miri run (binaries)"
    echo "Status: SKIPPED (no binary targets found)"
  } >> "$LOG"
else
  while IFS=$'\t' read -r bin_name bin_path; do
    [ -n "$bin_name" ] || continue
    {
      echo
      echo "## miri run (binary: $bin_name)"
      echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "Source: $bin_path"
      echo '```'
    } >> "$LOG"
    # miri run can hang on programs reading stdin or opening sockets — cap at 5 min.
    set +e
    timeout 300 cargo +nightly miri run --bin "$bin_name" 2>&1 | tee -a "$LOG"
    ec=${PIPESTATUS[0]}
    set -e
    echo '```' >> "$LOG"
    if [ "$ec" -eq 0 ]; then
      echo "Status: GREEN" >> "$LOG"
    elif [ "$ec" -eq 124 ]; then
      echo "Status: TIMEOUT (>300s; binary may need stdin/network miri can't simulate)" >> "$LOG"
    else
      echo "Status: FAILED (exit $ec — triage per Phase 7 § verification-log)" >> "$LOG"
      echo "If the failure is FFI/syscall miri doesn't support, document in pre-existing-ub.md instead of refactor scope." >> "$LOG"
    fi
  done <<< "$BINARIES"
fi
