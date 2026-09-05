#!/usr/bin/env bash
# run-soak-campaign.sh — Long-running fuzz / miri / loom / shuttle / crash-
# boundary / BOCPD / e-process campaigns. Dispatches to `rch exec --` when wall time
# exceeds the local threshold.
#
# USAGE:
#   run-soak-campaign.sh <target> <workspace> <duration-hours>
#                        [--campaigns fuzz,miri,loom,shuttle,crash,bocpd,eprocess,adversarial]
#                        [--duration <hours|24h|4d>] [--bocpd-stream <name>]
#                        [--invariant <id>] [--output <path>] [--resume] [--no-rch]
#
# EXIT CODES:
#   0 — every requested campaign completed (some may have findings)
#   1 — at least one campaign failed to launch
#   3 — usage error
#
# IDEMPOTENT: each campaign writes a deterministically-named status JSON.

set -euo pipefail

usage() { sed -n '2,13p' "$0"; exit "${1:-3}"; }

TARGET=""
WORKSPACE=""
HOURS=""
CAMPAIGNS="fuzz,miri,loom,shuttle,crash,bocpd,eprocess,adversarial"
NO_RCH=0
DURATION=""
BOCPD_STREAM=""
INVARIANT_ID=""
OUTPUT=""
RESUME=0

duration_to_hours() {
  local raw="$1" n
  case "$raw" in
    *d) n="${raw%d}"; awk -v n="$n" 'BEGIN { printf "%g", n * 24 }';;
    *h) n="${raw%h}"; awk -v n="$n" 'BEGIN { printf "%g", n }';;
    *)  printf '%s' "$raw";;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --campaigns) CAMPAIGNS="$2"; shift 2;;
    --duration)  DURATION="$2"; shift 2;;
    --bocpd-stream) BOCPD_STREAM="$2"; shift 2;;
    --invariant) INVARIANT_ID="$2"; shift 2;;
    --output)    OUTPUT="$2"; shift 2;;
    --resume)    RESUME=1; shift;;
    --no-rch)    NO_RCH=1; shift;;
    -h|--help)   usage 0;;
    *)
      if [ -z "$TARGET" ]; then TARGET="$1"
      elif [ -z "$WORKSPACE" ]; then WORKSPACE="$1"
      elif [ -z "$HOURS" ]; then HOURS="$1"
      else echo "Unexpected arg: $1" >&2; usage
      fi
      shift;;
  esac
done

[ -z "$HOURS" ] && [ -n "$DURATION" ] && HOURS="$(duration_to_hours "$DURATION")"
[ -n "$TARGET" ] && [ -n "$WORKSPACE" ] && [ -n "$HOURS" ] || usage
awk -v h="$HOURS" 'BEGIN { exit (h+0 > 0 ? 0 : 1) }' || { echo "duration-hours must be > 0" >&2; exit 3; }

SECONDS_TOTAL="$(awk -v h="$HOURS" 'BEGIN { printf "%d", h*3600 }')"
LANE="$WORKSPACE/artifacts/soak"
mkdir -p "$LANE"

# Threshold above which we offload to rch (5 min = 300s).
RCH_THRESHOLD=300
USE_RCH=0
if [ "$NO_RCH" -eq 0 ] && [ "$SECONDS_TOTAL" -gt "$RCH_THRESHOLD" ] && command -v rch >/dev/null 2>&1; then
  USE_RCH=1
fi

run_campaign() {
  local name="$1" cmd="$2"
  local status_file="$LANE/${name}_status.json"
  local log_file="$LANE/${name}.log"
  local start ended exitcode
  start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "==> $name (budget ${HOURS}h, rch=$USE_RCH)"
  if [ "$USE_RCH" -eq 1 ]; then
    ( cd "$TARGET" && rch exec -- bash -c "$cmd" 2>&1 ) > "$log_file" || exitcode=$? && exitcode=${exitcode:-0}
  else
    ( cd "$TARGET" && bash -c "$cmd" 2>&1 ) > "$log_file" || exitcode=$? && exitcode=${exitcode:-0}
  fi
  exitcode="${exitcode:-0}"
  ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    printf '{\n'
    printf '  "schema_version": "gauntlet.soak_campaign_status.v1",\n'
    printf '  "campaign": "%s",\n' "$name"
    printf '  "started_at": "%s",\n' "$start"
    printf '  "ended_at": "%s",\n' "$ended"
    printf '  "duration_hours": %s,\n' "$HOURS"
    printf '  "bocpd_stream": "%s",\n' "$BOCPD_STREAM"
    printf '  "invariant_id": "%s",\n' "$INVARIANT_ID"
    printf '  "resume": %s,\n' "$([ "$RESUME" -eq 1 ] && echo true || echo false)"
    printf '  "exit_code": %d,\n' "$exitcode"
    printf '  "log_file": "%s",\n' "$log_file"
    printf '  "via_rch": %s\n' "$([ $USE_RCH -eq 1 ] && echo true || echo false)"
    printf '}\n'
  } > "$status_file"
  return "$exitcode"
}

FAIL=0
IFS=',' read -ra REQ <<<"$CAMPAIGNS"
for c in "${REQ[@]}"; do
  c="$(echo "$c" | xargs)"
  case "$c" in
    fuzz)
      run_campaign fuzz "targets=\"\$(cargo fuzz list 2>/dev/null)\"; if [ -z \"\$targets\" ]; then echo 'ERROR: no cargo-fuzz targets discovered' >&2; exit 2; fi; fail=0; for t in \$targets; do code=0; timeout ${SECONDS_TOTAL} cargo fuzz run \$t -- -max_total_time=${SECONDS_TOTAL} || code=\$?; if [ \"\$code\" -ne 0 ] && [ \"\$code\" -ne 124 ]; then fail=1; fi; done; exit \$fail" || FAIL=$((FAIL+1));;
    miri)
      run_campaign miri "cargo +nightly miri test --workspace" || FAIL=$((FAIL+1));;
    loom)
      run_campaign loom "RUSTFLAGS='--cfg loom' cargo test --features loom --release loom_" || FAIL=$((FAIL+1));;
    shuttle)
      run_campaign shuttle "cargo test --features shuttle shuttle_ -- --test-threads 1" || FAIL=$((FAIL+1));;
    crash)
      run_campaign crash "cargo test crash_boundary -- --nocapture" || FAIL=$((FAIL+1));;
    bocpd)
      run_campaign bocpd "cargo test bocpd_soak -- --ignored --nocapture" || FAIL=$((FAIL+1));;
    eprocess)
      run_campaign eprocess "cargo test eprocess_soak -- --ignored --nocapture" || FAIL=$((FAIL+1));;
    adversarial)
      run_campaign adversarial "cargo test adversarial_search -- --ignored --nocapture" || FAIL=$((FAIL+1));;
    *)
      echo "Unknown campaign: $c (skipping)" >&2;;
  esac
done

SUMMARY="$LANE/_summary.json"
{
  printf '{\n'
  printf '  "schema_version": "gauntlet.soak_summary.v1",\n'
  printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "campaigns_requested": "%s",\n' "$CAMPAIGNS"
  printf '  "bocpd_stream": "%s",\n' "$BOCPD_STREAM"
  printf '  "invariant_id": "%s",\n' "$INVARIANT_ID"
  printf '  "resume": %s,\n' "$([ "$RESUME" -eq 1 ] && echo true || echo false)"
  printf '  "failed_campaigns": %d\n' "$FAIL"
  printf '}\n'
} > "$SUMMARY"

if [ -n "$OUTPUT" ]; then
  mkdir -p "$(dirname "$OUTPUT")"
  cp "$SUMMARY" "$OUTPUT"
fi

echo "Wrote $SUMMARY"
[ "$FAIL" -eq 0 ] || exit 1
