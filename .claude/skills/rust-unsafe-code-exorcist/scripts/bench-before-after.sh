#!/usr/bin/env bash
# bench-before-after.sh — measure perf for a (B) site
# Usage: ./bench-before-after.sh <audit-dir> <site-id> <bench-name> [<project>]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: bench-before-after.sh <audit-dir> <site-id> <bench-name> [<project>]}"
AUDIT_DIR=$(audit_realpath "$AUDIT_DIR")
AUDIT_PROJECT_ROOT=$(audit_project_root_from_dir "$AUDIT_DIR")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$AUDIT_PROJECT_ROOT")
SITE_ID="${2:?usage}"
BENCH="${3:?usage}"

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

PROJECT_DIR="${4:-$(infer_project_dir)}"
PROJECT_DIR=$(audit_realpath "$PROJECT_DIR")

OUT="$AUDIT_DIR/audit/plans/bench-${SITE_ID}/"
mkdir -p "$OUT"
cd "$PROJECT_DIR"

TARGETS=(
  ""                            # default target-cpu
  "-C target-cpu=x86-64-v2"
  "-C target-cpu=x86-64-v3"
)

for tflag in "${TARGETS[@]}"; do
  tname="${tflag// /_}"
  tname="${tname:--default}"
  echo "==> Bench (default features) target: $tname"
  RUSTFLAGS="$tflag" cargo bench --bench "$BENCH" -- --output-format bencher 2>&1 | \
    tee "$OUT/criterion-default${tname}.txt"

  echo "==> Bench (safe-only features) target: $tname"
  RUSTFLAGS="$tflag" cargo bench --bench "$BENCH" --features safe-only --no-default-features \
    -- --output-format bencher 2>&1 | tee "$OUT/criterion-safe${tname}.txt"
done

# Hyperfine end-to-end (if there's a representative binary)
if [ -n "${CANONICAL_BIN:-}" ]; then
  echo "==> hyperfine end-to-end"
  cargo build --release
  cargo build --release --features safe-only --no-default-features
  hyperfine --warmup 3 --runs 20 \
    "./target/release/$CANONICAL_BIN" \
    "./target/release/${CANONICAL_BIN}-safe" \
    --export-json "$OUT/hyperfine.json" || \
    echo "Hyperfine failed — set CANONICAL_BIN and ensure both default + safe-only binaries exist"
fi

# Flamegraph
if command -v cargo-flamegraph >/dev/null 2>&1; then
  echo "==> flamegraph (default)"
  cargo flamegraph --bin "${CANONICAL_BIN:-}" --output "$OUT/flame-default.svg" 2>/dev/null || true
  echo "==> flamegraph (safe-only)"
  cargo flamegraph --bin "${CANONICAL_BIN:-}" --features safe-only --no-default-features \
                   --output "$OUT/flame-safe.svg" 2>/dev/null || true
fi

# Summary
{
  echo "# Bench results — $SITE_ID"
  echo "Bench: $BENCH"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Per-target criterion"
  for f in "$OUT"/criterion-*.txt; do
    echo "### $(basename "$f" .txt)"
    grep -E "^test|ns/iter" "$f" || cat "$f"
  done
  if [ -f "$OUT/hyperfine.json" ]; then
    echo
    echo "## hyperfine"
    jq '.results' "$OUT/hyperfine.json"
  fi
} > "$OUT/SUMMARY.md"

echo "Bench summary written to $OUT/SUMMARY.md"
