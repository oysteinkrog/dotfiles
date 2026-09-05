#!/usr/bin/env bash
# run-fault-injection-matrix.sh — Exercise every named FaultSpec profile and
# every CrashBoundary for the detected project class. Assert post-recovery
# consistency-or-no-partial.
#
# USAGE:
#   run-fault-injection-matrix.sh <target> <workspace> [--class <class>]
#                                                   [--emit-coverage <path>]
#
# EXIT CODES:
#   0 — all profiles + boundaries passed
#   1 — at least one fault profile or boundary failed
#   2 — class unrecognized
#   3 — usage error
#
# IDEMPOTENT.

set -euo pipefail

usage() { sed -n '2,12p' "$0"; exit "${1:-3}"; }

TARGET=""
WORKSPACE=""
CLASS=""
EMIT_COVERAGE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --class) CLASS="$2"; shift 2;;
    --emit-coverage) EMIT_COVERAGE="$2"; shift 2;;
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

if [ -z "$CLASS" ] && [ -f "$WORKSPACE/phase0_project_class.json" ]; then
  CLASS="$(grep -oE '"detected_class": *"[^"]+"' "$WORKSPACE/phase0_project_class.json" | head -1 | sed 's/.*"detected_class": *"//; s/".*//')"
fi
CLASS="${CLASS:-UNKNOWN}"

LANE="$WORKSPACE/artifacts/fault_matrix"
mkdir -p "$LANE"
LOG="$LANE/run.log"
: > "$LOG"

# ---- per-class fault & boundary catalogs --------------------------------
case "$CLASS" in
  SQL-class)
    FAULT_PROFILES=(torn-wal-frame partial-checkpoint power-cut-after-fsync
                    io-error-mid-commit latency-spike-busy-wait disk-full-wal
                    read-failure-page-fault write-failure-shm)
    BOUNDARIES=(BeforeWalHeaderWrite BeforeWalFrameAppend
                AfterWalFrameAppendBeforeFsync AfterFsyncBeforePublish
                BetweenPageTableRebuildSteps AfterPublishBeforeCheckpoint
                MidCheckpoint AfterCheckpoint)
    ;;
  RESP-class)
    FAULT_PROFILES=(partial-aof-rewrite mid-rdb-torn-write
                    fsync-then-power-cut eagain-storm-replication
                    disk-full-aof read-failure-rdb)
    BOUNDARIES=(BeforeAofRewriteRename DuringRdbWrite
                BeforeReplicationOffsetUpdate MidPsync
                AfterReplOffsetBeforeAck DuringFsync)
    ;;
  ML-System-class)
    FAULT_PROFILES=(partial-torch-save mid-shard-nccl-drop
                    cuda-launch-failed-mid-collective checkpoint-fsync-cut
                    optimizer-state-partial)
    BOUNDARIES=(BeforeSerialize MidShardWrite AfterShardBeforeMetadata
                MidMetadataUpdate AfterRenameBeforeFsync
                MidAllReduce BeforeRendezvousAck)
    ;;
  HTTP-Protocol-class)
    FAULT_PROFILES=(connection-drop-mid-body slow-loris partial-multipart
                    cancellation-mid-handler upstream-eof)
    BOUNDARIES=(RequestOpen HeaderReceived BodyStart BodyEnd ConnectionClose
                CancellationMidHandler)
    ;;
  *)
    echo "ERROR: unknown class $CLASS" >&2; exit 2;;
esac

PASS=0; FAIL=0
declare -a FAILED_ITEMS=()

run_test_filter() {
  local kind="$1" name="$2"
  local safe_name step_log filter status ran
  echo "==> $kind: $name" | tee -a "$LOG"
  safe_name="${kind}_${name//[^A-Za-z0-9_.-]/_}"

  for filter in "$name" "${name//-/_}"; do
    step_log="$LANE/${safe_name}_${filter//[^A-Za-z0-9_.-]/_}.log"
    status=0
    ( cd "$TARGET" && cargo test "$filter" -- --nocapture 2>&1 ) > "$step_log" || status=$?
    cat "$step_log" >> "$LOG"
    ran=0
    grep -qE '^running [1-9][0-9]* tests?' "$step_log" && ran=1
    if [ "$ran" -eq 1 ] && [ "$status" -eq 0 ]; then
      PASS=$((PASS+1))
      return 0
    fi
    if [ "$ran" -eq 1 ] && [ "$status" -ne 0 ]; then
      FAIL=$((FAIL+1))
      FAILED_ITEMS+=("$kind:$name:failed")
      return 1
    fi
  done

  FAIL=$((FAIL+1))
  FAILED_ITEMS+=("$kind:$name:missing-or-zero-tests")
  return 1
}

for f in "${FAULT_PROFILES[@]}"; do
  run_test_filter "fault" "$f" || true
done
for b in "${BOUNDARIES[@]}"; do
  run_test_filter "boundary" "$b" || true
done

# ---- emit JSON summary --------------------------------------------------
SUMMARY="$LANE/summary.json"
{
  printf '{\n'
  printf '  "schema_version": "gauntlet.fault_matrix_summary.v1",\n'
  printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "project_class": "%s",\n' "$CLASS"
  printf '  "pass_count": %d,\n' "$PASS"
  printf '  "fail_count": %d,\n' "$FAIL"
  printf '  "failed_items": [\n'
  n="${#FAILED_ITEMS[@]}"
  for i in "${!FAILED_ITEMS[@]}"; do
    sep=","; [ $((i+1)) -eq "$n" ] && sep=""
    printf '    "%s"%s\n' "${FAILED_ITEMS[$i]}" "$sep"
  done
  printf '  ]\n'
  printf '}\n'
} > "$SUMMARY"

if [ -n "$EMIT_COVERAGE" ]; then
  mkdir -p "$(dirname "$EMIT_COVERAGE")"
  python3 - "$SUMMARY" "$EMIT_COVERAGE" <<'PYTHON'
import json, sys, time

summary_path, coverage_path = sys.argv[1:3]
with open(summary_path) as f:
    summary = json.load(f)

failed = summary.get("failed_items", [])
fault_failures = []
boundary_failures = []
for item in failed:
    kind, name, *_ = str(item).split(":")
    if kind == "fault":
        fault_failures.append(name)
    elif kind == "boundary":
        boundary_failures.append(name)

coverage = {
    "schema_version": "gauntlet.fault_coverage.v1",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "project_class": summary.get("project_class"),
    "source_summary": summary_path,
    "uncovered_fault_kinds": sorted(set(fault_failures)),
    "unarmed_crash_boundaries": sorted(set(boundary_failures)),
    "pass_count": summary.get("pass_count", 0),
    "fail_count": summary.get("fail_count", 0),
}
with open(coverage_path, "w") as f:
    json.dump(coverage, f, indent=2, sort_keys=True)
PYTHON
  echo "Wrote $EMIT_COVERAGE"
fi

echo "Wrote $SUMMARY"
[ "$FAIL" -eq 0 ] || exit 1
