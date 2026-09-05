#!/usr/bin/env bash
# regression-test.sh — Run every fixture in assets/fixtures/, audit each, and
# compare the result to the fixture's EXPECTED.md. This is how we regression-
# test the audit infrastructure itself when the rubric, scorer, theater
# patterns, or subagent prompts change.
#
# Usage:
#   regression-test.sh [--only <fixture-name>] [--threshold 700]
#                      [--policy report-only]
#
# What it does:
#   For each fixture under assets/fixtures/<name>/:
#     1. Make a tmp copy at /tmp/audit-fixture-<name>-<unix>/
#     2. Run <fixture>/seed.sh inside it (creates .beads/, populates beads,
#        sets up implementation/test files per the fixture's design).
#     3. Run scripts/run-pass.sh against the tmp copy.
#     4. Run scripts/compare-to-expected.py to diff the audit's REPORT.md vs
#        the fixture's EXPECTED.md.
#     5. PASS if the comparison is within tolerance; FAIL otherwise.
#
# Fixture tmp dirs and sibling audit dirs are always retained. This repo's
# no-deletion policy makes cleanup a human decision, and successful fixture
# artifacts are useful regression evidence.
#
# Exit codes:
#   0  every fixture passed
#   1  one or more fixtures failed
#   2  usage error / no fixtures found
#
# This is the "test suite for the audit". CI should run it on every change to
# scripts/, references/RUBRIC.md, references/FAILURE-MODES.md, and any subagent.
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$SKILL_DIR/scripts"
FIXTURES_DIR="$SKILL_DIR/assets/fixtures"

ONLY=""
THRESHOLD=700
POLICY="report-only"

require_value() { if [ "$2" -lt 2 ]; then echo "ERROR: $1 requires a value" >&2; exit 2; fi; }
while [ $# -gt 0 ]; do
  case "$1" in
    --only)      require_value "$1" "$#"; ONLY="$2"; shift 2 ;;
    --threshold) require_value "$1" "$#"; THRESHOLD="$2"; shift 2 ;;
    --policy)    require_value "$1" "$#"; POLICY="$2"; shift 2 ;;
    --keep-tmp)  echo "NOTE: --keep-tmp is no longer needed; artifacts are always retained." >&2; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -d "$FIXTURES_DIR" ] || { echo "ERROR: fixtures dir not found: $FIXTURES_DIR" >&2; exit 2; }

PASSED=0; FAILED=0
FAILED_NAMES=()
TS="$(date -u +%s)"

for fixture in "$FIXTURES_DIR"/*/; do
  name="$(basename "$fixture")"
  [ -n "$ONLY" ] && [ "$name" != "$ONLY" ] && continue
  [ -f "$fixture/seed.sh" ] || { echo "SKIP $name: no seed.sh"; continue; }
  [ -f "$fixture/EXPECTED.md" ] || { echo "SKIP $name: no EXPECTED.md"; continue; }

  echo "── fixture: $name ──"
  tmp="/tmp/audit-fixture-${name}-${TS}"
  mkdir -p "$tmp"

  # Seed the fixture project.
  ( cd "$tmp" && bash "$fixture/seed.sh" >/dev/null 2>&1 ) || {
    echo "  ✗ seed.sh failed for $name"
    FAILED=$((FAILED+1)); FAILED_NAMES+=("$name (seed)")
    continue
  }

  # Audit it.
  "$SCRIPTS/run-pass.sh" "$tmp" --threshold "$THRESHOLD" --policy "$POLICY" \
    >"$tmp/_audit.stdout" 2>"$tmp/_audit.stderr" || true

  audit_dir="${tmp}/beads_compliance_audit"
  if [ ! -f "$audit_dir/REPORT.md" ]; then
    echo "  ✗ audit produced no REPORT.md"
    FAILED=$((FAILED+1)); FAILED_NAMES+=("$name (no REPORT.md)")
    continue
  fi

  # Compare actual to expected.
  if python3 "$SCRIPTS/compare-to-expected.py" \
       "$audit_dir/REPORT.md" "$fixture/EXPECTED.md" \
       --threshold "$THRESHOLD" >"$tmp/_diff.txt" 2>&1; then
    echo "  ✓ $name passed"
    PASSED=$((PASSED+1))
    echo "    artifacts retained: $tmp and $audit_dir"
  else
    echo "  ✗ $name FAILED — see $tmp/_diff.txt"
    head -20 "$tmp/_diff.txt" | sed 's/^/    | /'
    FAILED=$((FAILED+1)); FAILED_NAMES+=("$name")
  fi
done

echo ""
echo "==== SUMMARY ===="
echo "passed: $PASSED"
echo "failed: $FAILED"
if [ "$FAILED" -gt 0 ]; then
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  echo ""
  echo "(failed tmp dirs left in /tmp/audit-fixture-*-${TS} for inspection)"
  exit 1
fi
exit 0
