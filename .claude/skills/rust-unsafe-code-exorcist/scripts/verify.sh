#!/usr/bin/env bash
# verify.sh — composite harness: miri + careful + loom + fuzz + mutants + geiger
#             + default-features test + safe-only-features test
# This is the template-installed-into-audit-dir version. The harness-builder subagent
# copies + customizes assets/verify.sh.template into <audit-dir>/verify.sh.
#
# Usage from the skill scripts dir: ./verify.sh <audit-dir> [<project-dir>]
# Usage from an installed audit dir: ./verify.sh [<project-dir>]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/audit-dir-guard.sh" ]; then
  . "$SCRIPT_DIR/audit-dir-guard.sh"
else
  audit_realpath() {
    python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
  }
  audit_project_root_from_dir() {
    local audit_abs="$1"
    if [ -f "$audit_abs/phase1/project-root.txt" ]; then
      audit_realpath "$(sed -n '1p' "$audit_abs/phase1/project-root.txt")"
      return
    fi
    local cur
    cur="$(dirname "$audit_abs")"
    while [ "$cur" != "/" ]; do
      if [ -f "$cur/Cargo.toml" ]; then audit_realpath "$cur"; return; fi
      cur="$(dirname "$cur")"
    done
    echo "error: cannot infer audited project root from audit dir: $audit_abs" >&2
    return 2
  }
  audit_require_under_project() {
    local audit_abs project_abs
    audit_abs="$(audit_realpath "$1")"
    project_abs="$(audit_realpath "$2")"
    if [ "$audit_abs" = "$project_abs" ]; then
      echo "error: audit dir must be a child directory inside the project, not the project root" >&2
      return 2
    fi
    case "$audit_abs/" in "$project_abs"/*) printf '%s\n' "$audit_abs" ;; *)
      echo "error: audit dir must live inside the project being audited" >&2
      echo "       project:   $project_abs" >&2
      echo "       audit dir: $audit_abs" >&2
      return 2 ;;
    esac
  }
fi

if [ -f "$SCRIPT_DIR/phase1/project-root.txt" ] || [ -d "$SCRIPT_DIR/audit" ]; then
  AUDIT_DIR="${AUDIT_DIR:-$SCRIPT_DIR}"
  PROJECT_ARG="${1:-}"
else
  AUDIT_DIR="${1:?usage: verify.sh <audit-dir> [<project-dir>]}"
  PROJECT_ARG="${2:-}"
fi
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

PROJECT_DIR="${PROJECT_DIR:-${PROJECT_ARG:-$(infer_project_dir)}}"
PROJECT_DIR=$(audit_realpath "$PROJECT_DIR")

LOG="$AUDIT_DIR/audit/phase9/verify.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

cd "$PROJECT_DIR"

echo "verify.sh — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Project: $PROJECT_DIR"
echo "Audit:   $AUDIT_DIR"
echo

echo "==> [1/9] cargo +nightly miri test (default)"
cargo +nightly miri test --workspace --all-features

echo "==> [2/9] cargo +nightly miri test (strict provenance)"
MIRIFLAGS="-Zmiri-strict-provenance" cargo +nightly miri test --workspace --all-features

echo "==> [3/9] cargo +nightly careful test"
cargo +nightly careful test --workspace --all-features

echo "==> [4/9] loom"
if grep -q "loom_concurrency_tests" Cargo.toml ./*/Cargo.toml 2>/dev/null; then
  RUSTFLAGS="--cfg loom" cargo test --workspace --features loom_concurrency_tests --release
else
  echo "    (no loom suites configured; skipping)"
fi

echo "==> [5/9] cargo fuzz (60s per target)"
if [ -d fuzz ]; then
  for target in $(cargo fuzz list 2>/dev/null); do
    cargo +nightly fuzz run "$target" -- -max_total_time=60
  done
else
  echo "    (no fuzz/ directory; skipping)"
fi

echo "==> [6/9] cargo mutants"
cargo mutants --in-place=false --jobs 4 --output "$AUDIT_DIR/audit/phase9/mutants/"

echo "==> [7/9] cargo +nightly geiger (delta vs baseline)"
cargo +nightly geiger --output-format Json > "$AUDIT_DIR/geiger-after.json"

sum_geiger_file() {
  jq '[.packages[]?.package.metrics.counters | objects | .[] | numbers] | add // 0' "$1" 2>/dev/null || echo 0
}

sum_geiger_dir() {
  local dir="$1"
  local single="$dir/phase1/cargo-geiger.json"
  local sum=0 part found=0
  if [ -f "$single" ]; then
    sum_geiger_file "$single"
    return
  fi
  for f in "$dir"/phase1/*__geiger.json; do
    [ -f "$f" ] || continue
    found=1
    part=$(sum_geiger_file "$f")
    case "$part" in ''|null) part=0 ;; esac
    sum=$((sum + part))
  done
  if [ "$found" -eq 0 ]; then
    return 1
  fi
  echo "$sum"
}

if BL=$(sum_geiger_dir "$AUDIT_DIR"); then
  PT=$(sum_geiger_file "$AUDIT_DIR/geiger-after.json")
  case "$BL" in ''|null) BL=0 ;; esac
  case "$PT" in ''|null) PT=0 ;; esac
  echo "    baseline: $BL  post: $PT  delta: $((PT - BL))"
  if [ "$PT" -gt "$BL" ]; then
    echo "    GEIGER REGRESSION"
    exit 1
  fi
else
  echo "    no phase1 cargo-geiger baseline found; saved current geiger output only"
fi

echo "==> [8/9] cargo test (default features)"
cargo test --workspace --all-features

echo "==> [9/9] cargo test (safe-only features)"
if grep -q "safe-only" Cargo.toml ./*/Cargo.toml 2>/dev/null; then
  cargo test --workspace --features safe-only --no-default-features
else
  echo "    (no safe-only feature configured; skipping)"
fi

echo
echo "verify.sh OK — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
