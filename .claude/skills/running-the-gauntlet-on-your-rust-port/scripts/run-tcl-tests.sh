#!/usr/bin/env bash
# run-tcl-tests.sh — (SQL-class only) runs the upstream SQLite TCL test suite
# against the port's CLI shim, diffs against captured reference baseline,
# dedups divergences by MismatchSignature.
#
# USAGE:
#   run-tcl-tests.sh <target-port> <workspace> [--baseline-only] [--round N] [--filter <pattern>]
#
# Mirrors the tcl-test-runner subagent's logic.

set -euo pipefail

usage() { sed -n '2,9p' "$0"; exit "${1:-2}"; }

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage 0
fi

[ $# -ge 2 ] || usage
TARGET="$1"
WORKSPACE="$2"
shift 2

BASELINE_ONLY=0
ROUND="latest"
TCL_FILTER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --baseline-only) BASELINE_ONLY=1; shift;;
    --round) ROUND="$2"; shift 2;;
    --filter) TCL_FILTER="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

# Project-class gate.
CLASS_FILE="$WORKSPACE/phase0_project_class.json"
if [ ! -f "$CLASS_FILE" ]; then
  echo "ERROR: $CLASS_FILE not found; run detect-project-class.sh first" >&2
  exit 2
fi
CLASS=$(jq -r .detected_class "$CLASS_FILE")
case "$CLASS" in
  SQL-class|SQL) ;;
  *) echo "run-tcl-tests.sh skipped: not SQL-class (class=$CLASS)"; exit 0 ;;
esac

CONTRACT_FILE="$WORKSPACE/docs/contracts/sqlite_version_contract.toml"
SQLITE_VERSION=$(grep '^version' "$CONTRACT_FILE" 2>/dev/null | cut -d'"' -f2 || echo "")
[ -z "$SQLITE_VERSION" ] && { echo "ERROR: cannot read sqlite version from $CONTRACT_FILE" >&2; exit 2; }

TCL_BASELINE="$WORKSPACE/tcl_reference_baseline"

# Phase 1: build / verify the reference baseline (one-time).
if [ ! -d "$TCL_BASELINE" ]; then
  echo "[baseline] no TCL baseline found; capturing against reference sqlite $SQLITE_VERSION"
  mkdir -p "$TCL_BASELINE"

  # SQLite source archive numeric version: major*1_000_000 + minor*10_000 + patch*100.
  # Example: 3.52.0 -> sqlite-src-3520000.zip.
  # The download URL has the release year in the path — but the same source ships under
  # multiple year directories. We try the SQLite-recommended canonical $RELEASE_YEAR
  # first (from contract if present), then fall back to a sweep across recent years.
  IFS='.' read -r MAJOR MINOR PATCH <<<"$SQLITE_VERSION"
  VERSION_FLAT=$((10#$MAJOR * 1000000 + 10#$MINOR * 10000 + 10#$PATCH * 100))
  echo "[baseline] computed VERSION_FLAT=$VERSION_FLAT"

  TARBALL_URL=""
  TMP=$(mktemp -d)
  # Allow override via the contract's [reference] download_url field.
  CONTRACT_URL=$(grep -E '^\s*source_url\s*=' "$CONTRACT_FILE" 2>/dev/null | head -1 | cut -d'"' -f2 || true)
  if [ -n "$CONTRACT_URL" ]; then
    TARBALL_URL="$CONTRACT_URL"
  else
    # Sweep recent years (sqlite.org keeps releases under the year-of-release path).
    for year in 2026 2025 2024 2023; do
      TRY="https://sqlite.org/${year}/sqlite-src-${VERSION_FLAT}.zip"
      if curl -sIfL "$TRY" -o /dev/null; then
        TARBALL_URL="$TRY"; break
      fi
    done
  fi

  if [ -z "$TARBALL_URL" ]; then
    echo "ERROR: could not locate sqlite-src-${VERSION_FLAT}.zip on sqlite.org;" >&2
    echo "       set [reference] source_url in $CONTRACT_FILE or provide TCL corpus manually under $TCL_BASELINE/test/" >&2
    echo "       retained temp directory for inspection: $TMP" >&2
    exit 2
  fi

  echo "[baseline] downloading $TARBALL_URL"
  if ! curl -sSL "$TARBALL_URL" -o "$TMP/sqlite-src.zip"; then
    echo "ERROR: failed to download $TARBALL_URL" >&2
    echo "       retained temp directory for inspection: $TMP" >&2
    exit 2
  fi
  unzip -q "$TMP/sqlite-src.zip" -d "$TMP/extracted"

  # Copy test/ into baseline.
  cp -r "$TMP/extracted"/sqlite-src-*/test "$TCL_BASELINE/"
  echo "[baseline] retained temp directory for auditability: $TMP"

  # Run each .test file through SQLite's compiled TCL test harness. Plain
  # `tclsh` is not honest here: many upstream SQLite tests depend on commands
  # registered by testfixture, and capturing those failures as "expected" output
  # would turn a broken baseline into false green evidence.
  TESTFIXTURE="${SQLITE_TESTFIXTURE:-}"
  if [ -z "$TESTFIXTURE" ] && command -v testfixture >/dev/null 2>&1; then
    TESTFIXTURE="$(command -v testfixture)"
  fi
  if [ -z "$TESTFIXTURE" ] || [ ! -x "$TESTFIXTURE" ]; then
    echo "ERROR: SQLite TCL baseline requires a compiled testfixture binary." >&2
    echo "       Build SQLite's testfixture for $SQLITE_VERSION and set SQLITE_TESTFIXTURE=/abs/path/testfixture." >&2
    echo "       Refusing to capture plain tclsh failures as a reference baseline." >&2
    echo "       retained temp directory for inspection: $TMP" >&2
    exit 2
  fi

  echo "[baseline] running TCL suite against reference testfixture: $TESTFIXTURE"

  cd "$TCL_BASELINE/test"
  BASELINE_TOTAL=0
  for tf in *.test; do
    [ -f "$tf" ] || continue
    BASELINE_TOTAL=$((BASELINE_TOTAL+1))
    out="$TCL_BASELINE/$(basename "$tf" .test).expected"
    if ! timeout 60 "$TESTFIXTURE" "$tf" > "$out" 2>&1; then
      echo "ERROR: reference testfixture failed while capturing baseline for $tf" >&2
      echo "       output: $out" >&2
      echo "       refusing to use failed reference output as expected data" >&2
      exit 2
    fi
  done
  cd - >/dev/null
  [ "$BASELINE_TOTAL" -gt 0 ] || { echo "ERROR: TCL baseline contained zero .test files" >&2; exit 2; }
fi

[ "$BASELINE_ONLY" -eq 1 ] && { echo "baseline only; done."; exit 0; }

# Phase 2: run the corpus against the port.
ROUND_DIR="$WORKSPACE/round_${ROUND}"
mkdir -p "$ROUND_DIR/tcl_actual" "$ROUND_DIR/tcl_failures"

# Locate the port's CLI shim.
PORT_CLI=""
for candidate in "$TARGET/target/release-perf/fsqlite-cli" \
                 "$TARGET/target/release-perf/$(basename "$TARGET")-cli" \
                 "$TARGET/target/release/fsqlite-cli"; do
  [ -x "$candidate" ] && { PORT_CLI="$candidate"; break; }
done
[ -z "$PORT_CLI" ] && { echo "ERROR: cannot find port CLI shim under $TARGET/target/" >&2; exit 2; }
echo "[run] using port CLI: $PORT_CLI"

PASS=0; DIVERGE=0; TOTAL=0; REGRESSIONS=0
echo > "$ROUND_DIR/tcl_results.jsonl"

cd "$TCL_BASELINE/test"
for tf in *.test; do
  [ -f "$tf" ] || continue
  name=$(basename "$tf" .test)
  if [ -n "$TCL_FILTER" ] && [[ "$name" != *"$TCL_FILTER"* ]]; then
    continue
  fi
  expected="$TCL_BASELINE/$name.expected"
  actual="$ROUND_DIR/tcl_actual/$name.actual"
  [ ! -f "$expected" ] && continue

  TOTAL=$((TOTAL+1))
  SUBJECT_EXIT=0
  timeout 60 "$PORT_CLI" -tcl-test "$tf" > "$actual" 2>&1 || SUBJECT_EXIT=$?

  if [ "$SUBJECT_EXIT" -eq 0 ] && diff -q "$expected" "$actual" >/dev/null 2>&1; then
    PASS=$((PASS+1))
    echo "{\"test\":\"$name\",\"status\":\"pass\"}" >> "$ROUND_DIR/tcl_results.jsonl"
  else
    DIVERGE=$((DIVERGE+1))
    # Compute mismatch signature (best-effort — schema is empty for TCL, workload is the test file).
    SIG=$(printf 'sig-v1:TrueDivergence:Unknown::%s' "$(cat "$tf")" | sha256sum | cut -c1-16)
    echo "{\"test\":\"$name\",\"status\":\"divergent\",\"subject_exit_code\":$SUBJECT_EXIT,\"mismatch_signature\":\"$SIG\"}" >> "$ROUND_DIR/tcl_results.jsonl"

    # Check for regression: did this test pass in the prior round?
    # ROUND may be "latest" or a numeric N; compute the prior round file safely.
    PRIOR_ROUND_FILE=""
    if [ "$ROUND" = "latest" ]; then
      # Find the most recent numeric round_N directory whose number is less than the
      # current "latest" (i.e., the last numbered round before this run).
      PRIOR=$(ls -d "$WORKSPACE"/round_[0-9]* 2>/dev/null | sort -V | tail -1 || true)
      [ -n "$PRIOR" ] && PRIOR_ROUND_FILE="$PRIOR/tcl_results.jsonl"
    elif [[ "$ROUND" =~ ^[0-9]+$ ]] && [ "$ROUND" -gt 1 ]; then
      PRIOR_ROUND_FILE="$WORKSPACE/round_$((ROUND-1))/tcl_results.jsonl"
    fi
    if [ -n "$PRIOR_ROUND_FILE" ] && [ -f "$PRIOR_ROUND_FILE" ]; then
      if grep -q "\"test\":\"$name\",\"status\":\"pass\"" "$PRIOR_ROUND_FILE"; then
        REGRESSIONS=$((REGRESSIONS+1))
      fi
    fi
  fi
done
cd - >/dev/null

if [ "$TOTAL" -eq 0 ]; then
  echo "ERROR: TCL run executed zero tests" >&2
  exit 2
fi

# Render summary.
PASS_PCT=$(python3 -c "print(round($PASS / $TOTAL * 100, 4))")
cat > "$ROUND_DIR/tcl_summary.md" <<MD
# TCL Test Suite Results — Round $ROUND

- **Total:** $TOTAL
- **Pass:** $PASS ($PASS_PCT %)
- **Divergent:** $DIVERGE
- **Regressions (vs prior round):** $REGRESSIONS

$( [ "$REGRESSIONS" -gt 0 ] && echo "**⚠ REGRESSIONS DETECTED** — see tcl_results.jsonl for details." )

## Top 10 divergent
$(jq -r 'select(.status=="divergent") | "- " + .test + " (sig=" + .mismatch_signature + ")"' "$ROUND_DIR/tcl_results.jsonl" | head -10)

MD

echo
echo "TCL run complete: $PASS / $TOTAL pass ($PASS_PCT %); $DIVERGE divergent; $REGRESSIONS regression(s)"
echo "Summary: $ROUND_DIR/tcl_summary.md"

[ "$REGRESSIONS" -eq 0 ] || exit 1
