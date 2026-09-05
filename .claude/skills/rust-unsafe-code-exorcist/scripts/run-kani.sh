#!/usr/bin/env bash
# run-kani.sh — run kani proofs for sites that benefit from formal verification.
# Usage: ./run-kani.sh <audit-dir> [<project-dir>]
#
# Kani is opt-in. Sites are kani-verified if they have a `kani-proof:` line in the
# refactor plan pointing to a #[kani::proof] function in the project's `proofs/` dir.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: run-kani.sh <audit-dir> [<project-dir>]}"
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

if ! command -v cargo-kani >/dev/null 2>&1 && ! command -v kani >/dev/null 2>&1; then
  {
    echo
    echo "## kani — SKIPPED (not installed)"
    echo "Install per https://model-checking.github.io/kani/install-guide.html"
    echo "  cargo install --locked kani-verifier"
    echo "  cargo kani setup"
  } >> "$LOG"
  exit 0
fi

# Find kani proofs referenced in plans
PROOFS=$(grep -hE '^kani-proof:' "$AUDIT_DIR/audit/plans"/*.md 2>/dev/null | awk '{print $2}' | sort -u || true)

{
  echo
  echo "## kani (formal verification)"
  echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo '```'
} >> "$LOG"

if [ -z "$PROOFS" ]; then
  echo "    (no kani proofs referenced in plans; skipping kani run)" >> "$LOG"
  echo '```' >> "$LOG"
  echo "Status: SKIPPED (no proofs configured)" >> "$LOG"
  exit 0
fi

OVERALL_OK=true
for proof in $PROOFS; do
  echo "    proof: $proof" >> "$LOG"
  if cargo kani --harness "$proof" 2>&1 | tee -a "$LOG"; then
    :
  else
    OVERALL_OK=false
  fi
done

echo '```' >> "$LOG"
if $OVERALL_OK; then
  echo "Status: GREEN" >> "$LOG"
else
  echo "Status: FAILED" >> "$LOG"
fi
