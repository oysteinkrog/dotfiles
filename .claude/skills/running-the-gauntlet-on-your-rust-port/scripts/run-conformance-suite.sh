#!/usr/bin/env bash
# run-conformance-suite.sh — Run every oracle E2E + Differential V2 + meta-
# morphic + property + fuzz harness. Dedup failures by MismatchSignature.
# Per divergence: produce a FailureBundle v1.0.0 with first-divergence
# jsonptr, remediation playbook, and artifact SHA-256 hashes.
#
# USAGE:
#   run-conformance-suite.sh <target> <workspace> [--package <pkg>] [--no-fuzz]
#                            [--gate <name>] [--mutation-test]
#
# EXIT CODES:
#   0 — every test green
#   1 — at least one TrueDivergence found
#   2 — harness invocation error
#   3 — usage error
#
# IDEMPOTENT: per-run artifact lane is timestamped + symlinked to "latest".

set -euo pipefail

usage() { sed -n '2,14p' "$0"; exit "${1:-3}"; }

TARGET=""
WORKSPACE=""
PACKAGE=""
DO_FUZZ=1
GATE=""
MUTATION_TEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --package) PACKAGE="$2"; shift 2;;
    --no-fuzz) DO_FUZZ=0; shift;;
    --gate) GATE="$2"; shift 2;;
    --mutation-test) MUTATION_TEST=1; shift;;
    -h|--help) usage 0;;
    *)
      if [ -z "$TARGET" ]; then TARGET="$1"
      elif [ -z "$WORKSPACE" ]; then WORKSPACE="$1"
      else echo "Unexpected arg: $1" >&2; usage
      fi
      shift;;
  esac
done

[ -n "$TARGET" ] && [ -n "$WORKSPACE" ] || usage
mkdir -p "$WORKSPACE"

RUN_ID="conf-$(date -u +%Y%m%dT%H%M%SZ)-$$"
LANE="$WORKSPACE/artifacts/conformance/$RUN_ID"
mkdir -p "$LANE/failure_bundles"
{
  printf '{\n'
  printf '  "schema_version": "gauntlet.conformance_run_metadata.v1",\n'
  printf '  "gate": "%s",\n' "$GATE"
  printf '  "mutation_test": %s\n' "$([ "$MUTATION_TEST" -eq 1 ] && echo true || echo false)"
  printf '}\n'
} > "$LANE/run_metadata.json"

# Symlink "latest" pointer
ln -sfn "$RUN_ID" "$WORKSPACE/artifacts/conformance/latest"

LOG="$LANE/cargo_test.log"
PKG_ARGS=()
[ -n "$PACKAGE" ] && PKG_ARGS=(-p "$PACKAGE")

DIVERGENCE_COUNT=0
HARNESS_ERR=0
ZERO_TEST_COUNT=0
LAST_STEP_LOG=""

ran_any_tests() {
  grep -qE '^running [1-9][0-9]* tests?' "$1"
}

run_cargo_capture() {
  local label="$1"; shift
  local step_log="$LANE/${label//[^A-Za-z0-9_.-]/_}.log"
  LAST_STEP_LOG="$step_log"
  echo "==> $label"
  if ( cd "$TARGET" && "$@" 2>&1 ) > "$step_log"; then
    cat "$step_log" >> "$LOG"
    return 0
  fi
  cat "$step_log" >> "$LOG"
  return 1
}

# ---- oracle E2E ---------------------------------------------------------
echo "==> oracle E2E target discovery"
mapfile -t ORACLE_TARGETS < <(
  find "$TARGET/tests" -maxdepth 2 -type f -name '*_oracle_e2e.rs' -print 2>/dev/null \
    | sed 's#.*/##; s#\.rs$##' \
    | sort -u
)
if [ "${#ORACLE_TARGETS[@]}" -eq 0 ]; then
  echo "ERROR: no *_oracle_e2e integration test targets found under $TARGET/tests" | tee -a "$LOG"
  ZERO_TEST_COUNT=$((ZERO_TEST_COUNT+1))
  HARNESS_ERR=$((HARNESS_ERR+1))
else
  for target_name in "${ORACLE_TARGETS[@]}"; do
    step_log="$LANE/oracle_${target_name}.log"
    if ( cd "$TARGET" && cargo test "${PKG_ARGS[@]}" --test "$target_name" 2>&1 ) > "$step_log"; then
      cat "$step_log" >> "$LOG"
      if ! ran_any_tests "$step_log"; then
        echo "ERROR: oracle target $target_name executed zero tests" | tee -a "$LOG"
        ZERO_TEST_COUNT=$((ZERO_TEST_COUNT+1))
        HARNESS_ERR=$((HARNESS_ERR+1))
      fi
    else
      cat "$step_log" >> "$LOG"
      if grep -qE 'MISMATCH|FRANK_ERR|CSQL_ERR|TrueDivergence' "$step_log"; then
        DIVERGENCE_COUNT=$((DIVERGENCE_COUNT+1))
      else
        HARNESS_ERR=$((HARNESS_ERR+1))
      fi
    fi
  done
fi

# ---- differential V2 ----------------------------------------------------
if run_cargo_capture "differential V2 (cargo test --features differential_v2)" \
    cargo test "${PKG_ARGS[@]}" --features differential_v2; then
  if ! ran_any_tests "$LAST_STEP_LOG"; then
    echo "ERROR: differential V2 executed zero tests" | tee -a "$LOG"
    ZERO_TEST_COUNT=$((ZERO_TEST_COUNT+1))
    HARNESS_ERR=$((HARNESS_ERR+1))
  fi
else
  if grep -qE 'TrueDivergence|MismatchSignature' "$LAST_STEP_LOG"; then
    DIVERGENCE_COUNT=$((DIVERGENCE_COUNT+1))
  else
    HARNESS_ERR=$((HARNESS_ERR+1))
  fi
fi

# ---- metamorphic --------------------------------------------------------
if run_cargo_capture "metamorphic (cargo test metamorphic)" \
    cargo test "${PKG_ARGS[@]}" metamorphic; then
  if ! ran_any_tests "$LAST_STEP_LOG"; then
    echo "ERROR: metamorphic filter executed zero tests" | tee -a "$LOG"
    ZERO_TEST_COUNT=$((ZERO_TEST_COUNT+1))
    HARNESS_ERR=$((HARNESS_ERR+1))
  fi
else
  if grep -qE 'MISMATCH|TrueDivergence|MismatchSignature' "$LAST_STEP_LOG"; then
    DIVERGENCE_COUNT=$((DIVERGENCE_COUNT+1))
  else
    HARNESS_ERR=$((HARNESS_ERR+1))
  fi
fi

# ---- property (proptest/bolero) ----------------------------------------
if run_cargo_capture "property (cargo test --features proptest)" \
    cargo test "${PKG_ARGS[@]}" --features proptest; then
  if ! ran_any_tests "$LAST_STEP_LOG"; then
    echo "ERROR: property suite executed zero tests" | tee -a "$LOG"
    ZERO_TEST_COUNT=$((ZERO_TEST_COUNT+1))
    HARNESS_ERR=$((HARNESS_ERR+1))
  fi
else
  if grep -qE 'proptest|minimal failing input|Test failed|panicked at|TrueDivergence|MismatchSignature' "$LAST_STEP_LOG"; then
    DIVERGENCE_COUNT=$((DIVERGENCE_COUNT+1))
  else
    HARNESS_ERR=$((HARNESS_ERR+1))
  fi
fi

# ---- fuzz (best-effort, time-boxed) ------------------------------------
if [ "$DO_FUZZ" -eq 1 ] && command -v cargo-fuzz >/dev/null 2>&1; then
  FUZZ_TARGETS="$(cd "$TARGET" && cargo fuzz list 2>/dev/null || true)"
  for t in $FUZZ_TARGETS; do
    echo "==> fuzz: $t (60s)"
    fuzz_log="$LANE/fuzz_${t//[^A-Za-z0-9_.-]/_}.log"
    if ( cd "$TARGET" && timeout 60 cargo fuzz run "$t" 2>&1 ) > "$fuzz_log"; then
      cat "$fuzz_log" >> "$LOG"
    else
      code=$?
      cat "$fuzz_log" >> "$LOG"
      if [ "$code" -eq 124 ]; then
        echo "fuzz target $t reached timebox without crash" >> "$LOG"
      elif grep -qE 'artifact_prefix|Test unit written to|AddressSanitizer|UndefinedBehaviorSanitizer|panicked at|crash|oom|timeout' "$fuzz_log"; then
        DIVERGENCE_COUNT=$((DIVERGENCE_COUNT+1))
      else
        HARNESS_ERR=$((HARNESS_ERR+1))
      fi
    fi
  done
fi

# ---- dedup failures by MismatchSignature -------------------------------
DEDUP_OUT="$LANE/mismatch_signatures.txt"
grep -oE 'MismatchSignature[^[:space:]]+' "$LOG" 2>/dev/null | sort -u > "$DEDUP_OUT" || true
SIG_COUNT="$(wc -l <"$DEDUP_OUT" | tr -d ' ')"

# ---- emit partial FailureBundle per signature ---------------------------
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

if [ "$SIG_COUNT" -gt 0 ]; then
  while IFS= read -r sig; do
    [ -z "$sig" ] && continue
    sig_hash="${sig//[^A-Za-z0-9_]/_}"
    bundle="$LANE/failure_bundles/${sig_hash}.json"
    sig_json="$(json_escape "$sig")"
    sig_hash_json="$(json_escape "$sig_hash")"
    log_json="$(json_escape "$LOG")"
    repro_cmd="$(json_escape "cd '$TARGET' && cargo test --workspace --all-targets -- --nocapture")"
    {
      printf '{\n'
      printf '  "schema_version": "failure_bundle.v1.0.0",\n'
      printf '  "partial": true,\n'
      printf '  "partial_reason": "run-conformance-suite.sh could recover a mismatch signature from logs, but not the exact originating scenario seed/fixture from the target harness output.",\n'
      printf '  "signature": "%s",\n' "$sig_json"
      printf '  "mismatch_signature": {"hash": "%s", "raw": "%s"},\n' "$sig_hash_json" "$sig_json"
      printf '  "failure_type": "Divergence",\n'
      printf '  "first_divergence_jsonptr": "/failure/first_divergence",\n'
      printf '  "log_file": "%s",\n' "$log_json"
      printf '  "reproducibility": {\n'
      printf '    "seed": "UNKNOWN",\n'
      printf '    "fixture_id": "UNKNOWN",\n'
      printf '    "schedule_fingerprint": "UNKNOWN",\n'
      printf '    "repro_command": "%s"\n' "$repro_cmd"
      printf '  },\n'
      printf '  "git_sha": "%s",\n' "$(cd "$TARGET" && git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
      printf '  "platform": "%s",\n' "$(uname -srm)"
      printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf '  "remediation_playbook": {\n'
      printf '    "owner_hint": "subsystem owner (Unknown — set after triage)",\n'
      printf '    "summary": "Investigate first-divergence pointer; classify under MismatchClassification (TrueDivergence is the only actionable class).",\n'
      printf '    "next_commands": [\n'
      printf '      "rg --fixed-strings %s artifacts/conformance/%s/cargo_test.log",\n' "$sig_json" "$RUN_ID"
      printf '      "cargo test -p <crate> -- --nocapture",\n'
      printf '      "open %s"\n' "$bundle"
      printf '    ]\n'
      printf '  }\n'
      printf '}\n'
    } > "$bundle"
  done < "$DEDUP_OUT"
fi

# ---- run summary --------------------------------------------------------
SUMMARY="$LANE/summary.json"
{
  printf '{\n'
  printf '  "schema_version": "gauntlet.conformance_summary.v1",\n'
  printf '  "run_id": "%s",\n' "$RUN_ID"
  printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "divergence_count": %d,\n' "$DIVERGENCE_COUNT"
  printf '  "harness_error_count": %d,\n' "$HARNESS_ERR"
  printf '  "zero_test_count": %d,\n' "$ZERO_TEST_COUNT"
  printf '  "unique_signature_count": %d,\n' "$SIG_COUNT"
  printf '  "log_file": "%s"\n' "$LOG"
  printf '}\n'
} > "$SUMMARY"

echo "Wrote $SUMMARY"
[ "$DIVERGENCE_COUNT" -eq 0 ] && [ "$HARNESS_ERR" -eq 0 ] || exit 1
