#!/usr/bin/env bash
# run-numpy-all-check.sh — (Numerical-Python-class only) verifies the port
# covers every entry in numpy's `__all__` list.
#
# USAGE:
#   run-numpy-all-check.sh <target-port> <workspace> [--symbol <name>]
#
# Mirrors the FrankenNumPy `fnp_python_covers_full_numpy_all` test.

set -euo pipefail

usage() { sed -n '2,8p' "$0"; exit "${1:-2}"; }

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage 0
fi

[ $# -ge 2 ] || usage
TARGET="$1"
WORKSPACE="$2"
shift 2

SYMBOL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --symbol) SYMBOL="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

SKILL_ROOT="$(dirname "$(realpath "$0")")/.."

# Project-class gate.
# detect-project-class.sh writes "Numerical-Python-class" (with -class suffix);
# accept also bare "Numerical" / "Numerical-Python" for user-edited workspaces.
CLASS=$(jq -r .detected_class "$WORKSPACE/phase0_project_class.json" 2>/dev/null || echo "Unknown")
case "$CLASS" in
  Numerical-Python-class|Numerical-Python|Numerical) ;;
  *) echo "run-numpy-all-check.sh skipped: not Numerical-Python-class (class=$CLASS)"; exit 0 ;;
esac

# Detect numpy version per contract.
NUMPY_VERSION=$(grep '^version' "$WORKSPACE/docs/contracts/numpy_version_contract.toml" 2>/dev/null | cut -d'"' -f2 || echo "")
if [ -z "$NUMPY_VERSION" ]; then
  echo "WARN: no numpy_version_contract.toml; using installed numpy version"
fi

# Capture numpy.__all__ via the pinned interpreter (or system python).
NUMPY_ALL_JSON="$WORKSPACE/numpy_all.json"
python3 -c "
import json, numpy as np
out = {
    'numpy_version': np.__version__,
    'all': sorted(np.__all__),
    'count': len(np.__all__)
}
print(json.dumps(out, indent=2))
" > "$NUMPY_ALL_JSON"

EXPECTED_VERSION=$(jq -r .numpy_version "$NUMPY_ALL_JSON")
EXPECTED_COUNT=$(jq -r .count "$NUMPY_ALL_JSON")
echo "[detect] numpy $EXPECTED_VERSION, $EXPECTED_COUNT entries in __all__"

if [ -n "$NUMPY_VERSION" ] && [ "$EXPECTED_VERSION" != "$NUMPY_VERSION" ]; then
  echo "ERROR: contract pins numpy $NUMPY_VERSION but interpreter has $EXPECTED_VERSION" >&2
  exit 2
fi

# Use the syn-walker to enumerate port-side #[pyfunction] coverage.
WALKER="$SKILL_ROOT/scripts/syn-walkers/target/release/syn-walkers"
if [ ! -x "$WALKER" ]; then
  echo "[build] building syn-walkers"
  (cd "$SKILL_ROOT/scripts/syn-walkers" && cargo build --release --quiet)
fi

# Extract __all__ as a flat JSON array for the walker.
jq '.all' "$NUMPY_ALL_JSON" > "$WORKSPACE/numpy_all_array.json"

COVERAGE_JSON="$WORKSPACE/numpy_coverage.json"
"$WALKER" pyfunction-coverage \
  --subject-root "$TARGET" \
  --reference-all-json "$WORKSPACE/numpy_all_array.json" \
  > "$COVERAGE_JSON"

COVERAGE_PCT=$(jq -r .coverage_pct "$COVERAGE_JSON")
COVERED=$(jq -r .covered_count "$COVERAGE_JSON")
MISSING_COUNT=$(jq -r '.missing_in_subject | length' "$COVERAGE_JSON")

echo "[coverage] $COVERED / $EXPECTED_COUNT covered ($COVERAGE_PCT %)"
echo "[coverage] missing: $MISSING_COUNT entries"

if [ "$MISSING_COUNT" -gt 0 ]; then
  echo "[missing] first 10:"
  jq -r '.missing_in_subject | .[0:10] | .[]' "$COVERAGE_JSON" | sed 's/^/  - /'
fi

# Render markdown summary.
SUMMARY="$WORKSPACE/numpy_all_check_summary.md"
cat > "$SUMMARY" <<MD
# NumPy \`__all__\` Coverage Check

- numpy version: $EXPECTED_VERSION
- \`__all__\` count: $EXPECTED_COUNT
- Port covered:  $COVERED ($COVERAGE_PCT %)
- Missing:       $MISSING_COUNT
- Symbol filter: ${SYMBOL:-<none>}
- coverage_json: $COVERAGE_JSON

## Gates
- 100% coverage required for "Strict-Parity" tier; current = $COVERAGE_PCT %
- Each missing entry MUST appear as a FeatureUniverse Missing / Excluded entry per
  references/patterns/105-FEATURE-UNIVERSE.md.

MD

echo
echo "Summary: $SUMMARY"

# Strict gate: 100% required (per franken_numpy's "499/499 = 100% reachable" baseline).
if [ "$MISSING_COUNT" -gt 0 ]; then
  echo
  echo "[gate] STRICT-PARITY gate failed: $MISSING_COUNT missing entries"
  echo "       Each must appear as Missing or Excluded in supported_surface_matrix.toml."
  exit 1
fi
