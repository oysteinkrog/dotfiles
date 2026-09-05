#!/usr/bin/env bash
# run-geiger.sh — cargo-geiger delta check vs baseline
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: run-geiger.sh <audit-dir> [<project-dir>]}"
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
POST="$AUDIT_DIR/geiger-after.json"
STDERR_LOG="$AUDIT_DIR/audit/phase7/geiger.stderr"
mkdir -p "$(dirname "$LOG")"
cd "$PROJECT_DIR"

{
echo
echo "## cargo-geiger (delta vs baseline)"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo '```'
} >> "$LOG"

if cargo +nightly geiger --output-format Json > "$POST" 2> "$STDERR_LOG"; then
  {
    echo "JSON output saved to: $POST"
    if [ -s "$STDERR_LOG" ]; then
      echo
      echo "stderr:"
      cat "$STDERR_LOG"
    fi
  } >> "$LOG"
else
  status=$?
  {
    echo "cargo-geiger failed with status $status"
    if [ -s "$STDERR_LOG" ]; then
      echo
      echo "stderr:"
      cat "$STDERR_LOG"
    fi
  } >> "$LOG"
  echo '```' >> "$LOG"
  exit "$status"
fi

echo '```' >> "$LOG"

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

if ! BASELINE_COUNT=$(sum_geiger_dir "$AUDIT_DIR"); then
  echo "Status: BASELINE-MISSING — no phase1 cargo-geiger baseline to compare against; saved $POST as current run" >> "$LOG"
  exit 0
fi

POST_COUNT=$(sum_geiger_file "$POST")
case "$BASELINE_COUNT" in ''|null) BASELINE_COUNT=0 ;; esac
case "$POST_COUNT" in ''|null) POST_COUNT=0 ;; esac
DELTA=$((POST_COUNT - BASELINE_COUNT))

echo "Baseline count: $BASELINE_COUNT" >> "$LOG"
echo "Post count:     $POST_COUNT" >> "$LOG"
echo "Delta:          $DELTA" >> "$LOG"

if [ "$DELTA" -gt 0 ]; then
  echo "Status: REGRESSION — count increased by $DELTA" >> "$LOG"
elif [ "$DELTA" -eq 0 ]; then
  echo "Status: UNCHANGED" >> "$LOG"
else
  echo "Status: IMPROVED — count decreased by $((-DELTA))" >> "$LOG"
fi
