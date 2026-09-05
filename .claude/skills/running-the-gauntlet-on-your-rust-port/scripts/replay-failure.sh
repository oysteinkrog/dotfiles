#!/usr/bin/env bash
# replay-failure.sh — takes a FailureBundle, replays it deterministically.
#
# USAGE:
#   replay-failure.sh <bundle.json> [--commit <sha>] [--expect <should-still-fail|should-now-pass>]
#
# DELEGATES to the replay-runner subagent's verbatim prompt — this is the
# CLI shim for the same logic that orchestrator subagents invoke.

set -euo pipefail

BUNDLE=""
COMMIT=""
EXPECT="should-now-pass"

while [ $# -gt 0 ]; do
  case "$1" in
    --commit)
      [ $# -ge 2 ] || { echo "Missing value for --commit" >&2; exit 2; }
      COMMIT="$2"; shift 2;;
    --expect)
      [ $# -ge 2 ] || { echo "Missing value for --expect" >&2; exit 2; }
      EXPECT="$2"; shift 2;;
    -h|--help)
      sed -n '2,8p' "$0"; exit 0;;
    *)
      if [ -z "$BUNDLE" ]; then BUNDLE="$1"; shift
      else echo "Extra arg: $1" >&2; exit 2
      fi;;
  esac
done

[ -z "$BUNDLE" ] && { echo "Missing bundle path" >&2; exit 2; }
case "$EXPECT" in
  should-still-fail|should-now-pass) ;;
  *) echo "Invalid --expect value: $EXPECT" >&2; exit 2;;
esac
[ ! -f "$BUNDLE" ] && { echo "Bundle not found: $BUNDLE" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not on PATH; required to read FailureBundle JSON" >&2; exit 2; }

# Validate bundle has the required reproducibility fields.
for field in '.reproducibility.seed' '.reproducibility.fixture_id' \
	             '.reproducibility.schedule_fingerprint' '.reproducibility.repro_command' \
	             '.first_divergence_jsonptr'; do
  if [ -z "$(jq -r "$field // empty" "$BUNDLE")" ]; then
    echo "ERROR: bundle missing required field $field" >&2
    exit 2
  fi
done
if [ -z "$(jq -r '.mismatch_signature.hash // .signature // empty' "$BUNDLE")" ]; then
  echo "ERROR: bundle missing required field .mismatch_signature.hash (or legacy .signature)" >&2
  exit 2
fi

# Determine commit.
if [ -z "$COMMIT" ]; then
  COMMIT="$(git rev-parse HEAD 2>/dev/null || echo HEAD)"
fi

BUNDLE_SIG="$(jq -r '.mismatch_signature.hash // .signature' "$BUNDLE")"
BUNDLE_RAW="$(jq -r '.mismatch_signature.raw // .signature // .mismatch_signature.hash' "$BUNDLE")"
BUNDLE_SIG_SAFE="${BUNDLE_SIG//[^A-Za-z0-9_.-]/_}"
OUTDIR=".gauntlet/replay/${BUNDLE_SIG_SAFE}-${COMMIT}"
mkdir -p "$OUTDIR"

# Pull reproducibility env from bundle.
SEED="$(jq -r .reproducibility.seed "$BUNDLE")"
FIXTURE_ID="$(jq -r .reproducibility.fixture_id "$BUNDLE")"
SCHEDULE_FP="$(jq -r .reproducibility.schedule_fingerprint "$BUNDLE")"
REPRO_CMD="$(jq -r .reproducibility.repro_command "$BUNDLE")"
EXPECTED_FD="$(jq -r .first_divergence_jsonptr "$BUNDLE")"

echo "=== replay-failure.sh ==="
echo "bundle:    $BUNDLE"
echo "signature: $BUNDLE_SIG"
echo "commit:    $COMMIT"
echo "expect:    $EXPECT"
echo "outdir:    $OUTDIR"
echo

# Execute the repro command verbatim with the captured env.
START_MS=$(date +%s%3N)
set +e
env \
  FSQLITE_FAULT_SEED="$SEED" \
  FSQLITE_FIXTURE_ID="$FIXTURE_ID" \
  FSQLITE_SCHEDULE_FP="$SCHEDULE_FP" \
  bash -c "$REPRO_CMD" > "$OUTDIR/stdout" 2> "$OUTDIR/stderr"
EXIT_CODE=$?
set -e
END_MS=$(date +%s%3N)
ELAPSED_MS=$((END_MS - START_MS))

# Decision matrix.
SIG_PRESENT=0
if grep -Fq -- "$BUNDLE_SIG" "$OUTDIR/stdout" "$OUTDIR/stderr" 2>/dev/null || \
   grep -Fq -- "$BUNDLE_RAW" "$OUTDIR/stdout" "$OUTDIR/stderr" 2>/dev/null; then
  SIG_PRESENT=1
fi
case "$EXPECT" in
  should-still-fail)
    if [ "$EXIT_CODE" -ne 0 ] && [ "$SIG_PRESENT" -eq 1 ]; then
      STATUS="passed"
    elif [ "$EXIT_CODE" -ne 0 ]; then
      STATUS="shape-changed"
    else
      STATUS="failed"
    fi
    ;;
  should-now-pass)
    if [ "$EXIT_CODE" -eq 0 ]; then
      STATUS="passed"
    elif [ "$SIG_PRESENT" -eq 1 ]; then
      STATUS="failed"
    else
      STATUS="shape-changed"
    fi
    ;;
esac

# Emit result.
cat > "$OUTDIR/replay_result.json" <<JSON
{
  "schema_version": "gauntlet.replay_result.v1",
  "bundle_sig": "$BUNDLE_SIG",
  "commit_sha": "$COMMIT",
  "expectation": "$EXPECT",
  "status": "$STATUS",
  "exit_code": $EXIT_CODE,
  "signature_present": $([ "$SIG_PRESENT" -eq 1 ] && echo true || echo false),
  "elapsed_ms": $ELAPSED_MS,
  "stdout_path": "$OUTDIR/stdout",
  "stderr_path": "$OUTDIR/stderr",
  "expected_first_divergence": "$EXPECTED_FD"
}
JSON

echo "STATUS: $STATUS  (exit_code=$EXIT_CODE, elapsed=${ELAPSED_MS}ms)"
echo "RESULT: $OUTDIR/replay_result.json"

# Exit non-zero iff status=failed (so CI can gate on this).
[ "$STATUS" = "passed" ] || exit 1
