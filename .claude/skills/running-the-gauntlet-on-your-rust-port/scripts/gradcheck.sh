#!/usr/bin/env bash
# gradcheck.sh — (ML-System-class only) runs torch.gradcheck (or jax equivalent)
# against the port's autograd implementation, asserts gradient agreement
# within per-op ULP tolerance.
#
# USAGE:
#   gradcheck.sh <target-port> <workspace> [--op <op-name>] [--eps <eps>]

set -euo pipefail

usage() { sed -n '2,7p' "$0"; exit "${1:-2}"; }

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage 0
fi

[ $# -ge 2 ] || usage
TARGET="$1"
WORKSPACE="$2"
shift 2

OP=""
EPS="1e-6"

while [ $# -gt 0 ]; do
  case "$1" in
    --op)  OP="$2"; shift 2;;
    --eps) EPS="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

CLASS=$(jq -r .detected_class "$WORKSPACE/phase0_project_class.json" 2>/dev/null || echo "Unknown")
case "$CLASS" in
  ML-System-class|ML-System|ML) ;;
  *) echo "gradcheck.sh skipped: not ML-System-class (class=$CLASS)"; exit 0 ;;
esac

# ULP tolerance table from the project's contract.
ULP_TOML="$WORKSPACE/docs/contracts/ulp_tolerance_v1.toml"
if [ ! -f "$ULP_TOML" ]; then
  echo "WARN: $ULP_TOML missing; using defaults (4 ULP f32 matmul; 2 ULP elementwise)"
fi

OUT_JSON="$WORKSPACE/gradcheck_results.json"
mkdir -p "$(dirname "$OUT_JSON")"

# Dispatch via PyO3 bridge — assumes the port has a `gradcheck-runner` bin.
RUNNER=""
for candidate in "$TARGET/target/release-perf/gradcheck-runner" \
                 "$TARGET/target/release/gradcheck-runner"; do
  [ -x "$candidate" ] && { RUNNER="$candidate"; break; }
done
[ -z "$RUNNER" ] && { echo "ERROR: gradcheck-runner binary not found; build with 'cargo build --profile release-perf --bin gradcheck-runner'" >&2; exit 2; }

ARGS=("--out-json" "$OUT_JSON" "--eps" "$EPS")
[ -n "$ULP_TOML" ] && [ -f "$ULP_TOML" ] && ARGS+=("--ulp-table" "$ULP_TOML")
[ -n "$OP" ] && ARGS+=("--op" "$OP")

echo "[gradcheck] dispatching: $RUNNER ${ARGS[*]}"

# Determinism flags MUST be pinned per pattern:140-RELEASE-PERF-PROFILE +
# python-reference-bridger subagent.
export PYTHONHASHSEED=0
export CUBLAS_WORKSPACE_CONFIG=":4096:8"

set +e
"$RUNNER" "${ARGS[@]}"
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "ERROR: gradcheck-runner exited $EXIT_CODE; see $OUT_JSON if it was written" >&2
  exit "$EXIT_CODE"
fi

if [ ! -f "$OUT_JSON" ]; then
  echo "ERROR: gradcheck-runner produced no output at $OUT_JSON" >&2
  exit 2
fi

# Summarize.
TOTAL=$(jq -r '.results | length' "$OUT_JSON")
PASSED=$(jq -r '[.results[] | select(.status=="pass")] | length' "$OUT_JSON")
FAILED=$(jq -r '[.results[] | select(.status=="fail")] | length' "$OUT_JSON")
MAX_REL=$(jq -r '[.results[] | .max_rel_error // 0] | max' "$OUT_JSON")

echo "[gradcheck] $PASSED / $TOTAL pass; $FAILED fail; max_rel_error=$MAX_REL"

# Render summary.
SUMMARY="$WORKSPACE/gradcheck_summary.md"
cat > "$SUMMARY" <<MD
# Gradcheck Results

- Total ops:       $TOTAL
- Passed:          $PASSED
- Failed:          $FAILED
- Max rel error:   $MAX_REL
- eps:             $EPS

## Failures
$(jq -r '.results[] | select(.status=="fail") | "- " + .op + " (max_rel_error=" + (.max_rel_error|tostring) + ", ulp_required=" + (.ulp_required|tostring) + ")"' "$OUT_JSON")

MD

echo "Summary: $SUMMARY"

[ "$FAILED" -eq 0 ] || exit 1
