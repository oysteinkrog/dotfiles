#!/usr/bin/env bash
# run-narrow-benches.sh — Run every focused per-workload bench in sequence.
# For each: capture cargo-flamegraph + samply + dhat-rs + strace output.
# Produces per-workload attribution profiles and a top-10 self-time table.
#
# USAGE:
#   run-narrow-benches.sh <target> <workspace>
#                         [--benches <comma-separated>]  (default: discovered)
#                         [--profile <prof>]             (default: release-perf)
#                         [--no-flamegraph] [--no-samply] [--no-strace]
#
# EXIT CODES:
#   0 — all benches ran (some attribution captures may be skipped)
#   1 — at least one bench failed hard
#   3 — usage error
#
# IDEMPOTENT: per-bench artifact subdirectories overwrite cleanly.

set -euo pipefail

usage() { sed -n '2,16p' "$0"; exit "${1:-3}"; }

TARGET=""
WORKSPACE=""
BENCHES=""
PROFILE="release-perf"
DO_FLAMEGRAPH=1
DO_SAMPLY=1
DO_STRACE=1

while [ $# -gt 0 ]; do
  case "$1" in
    --benches)        BENCHES="$2"; shift 2;;
    --profile)        PROFILE="$2"; shift 2;;
    --no-flamegraph)  DO_FLAMEGRAPH=0; shift;;
    --no-samply)      DO_SAMPLY=0; shift;;
    --no-strace)      DO_STRACE=0; shift;;
    -h|--help)        usage 0;;
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

if [ -z "$BENCHES" ]; then
  # discover Cargo.toml-declared benches
  BENCHES="$(find "$TARGET" -maxdepth 4 -path '*/benches/*.rs' -not -path '*/target/*' \
              -printf '%f\n' | sed 's/\.rs$//' | sort -u | paste -sd, -)"
  if [ -z "$BENCHES" ]; then
    echo "No benches discovered; pass --benches list." >&2
    exit 0
  fi
fi

IFS=',' read -ra BENCH_LIST <<<"$BENCHES"

FAILED=0
RESULTS=()

for bench in "${BENCH_LIST[@]}"; do
  bench="$(echo "$bench" | xargs)"
  [ -z "$bench" ] && continue
  LANE="$WORKSPACE/artifacts/narrow/$bench"
  mkdir -p "$LANE"
  LOG="$LANE/run.log"

  echo "==> $bench"

  # baseline run
  if ! ( cd "$TARGET" && cargo bench --profile "$PROFILE" --bench "$bench" -- --warm-up-time 1 2>&1 ) > "$LOG"; then
    echo "FAIL: $bench (see $LOG)" >&2
    FAILED=$((FAILED+1))
    continue
  fi

  # flamegraph
  if [ "$DO_FLAMEGRAPH" -eq 1 ] && command -v cargo-flamegraph >/dev/null 2>&1; then
    FG_OUT="$LANE/flamegraph.svg"
    ( cd "$TARGET" && cargo flamegraph --bench "$bench" --output "$FG_OUT" 2>&1 ) \
      >> "$LANE/flamegraph.log" || echo "  (flamegraph capture failed; skipping)"
  fi

  # samply
  if [ "$DO_SAMPLY" -eq 1 ] && command -v samply >/dev/null 2>&1; then
    SAMP_OUT="$LANE/samply.json"
    BIN="$(find "$TARGET/target" -maxdepth 4 -name "$bench-*" -executable -type f 2>/dev/null | head -1 || true)"
    if [ -n "$BIN" ]; then
      ( samply record --save-only -o "$SAMP_OUT" "$BIN" 2>&1 ) >> "$LANE/samply.log" || true
    fi
  fi

  # dhat — requires the bench binary to opt-in via a dhat-rs feature flag;
  # we record a note instead of forcing a build.
  cat > "$LANE/dhat.md" <<EOF
# dhat capture

dhat-rs requires the target bench to opt in (\`#[cfg(feature = "dhat-heap")]\`).
Re-run with: \`cargo bench --profile $PROFILE --bench $bench --features dhat-heap\`
and look for \`dhat-heap.json\` in the project root.
EOF

  # strace -c
  if [ "$DO_STRACE" -eq 1 ] && command -v strace >/dev/null 2>&1; then
    BIN="$(find "$TARGET/target" -maxdepth 4 -name "$bench-*" -executable -type f 2>/dev/null | head -1 || true)"
    if [ -n "$BIN" ]; then
      ( strace -c -f -o "$LANE/strace.summary" "$BIN" 2>&1 ) > /dev/null || true
    fi
  fi

  # top-10 self-time (best-effort: parse criterion output)
  awk '/^test bench/ { print }' "$LOG" | sort -k4 -n -r | head -10 > "$LANE/top10_self_time.txt" || true

  RESULTS+=("$bench")
done

# ---- emit per-narrow JSON ledger ---------------------------------------
SUMMARY="$WORKSPACE/artifacts/narrow/_summary.json"
mkdir -p "$(dirname "$SUMMARY")"
{
  printf '{\n'
  printf '  "schema_version": "gauntlet.narrow_bench_summary.v1",\n'
  printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "profile": "%s",\n' "$PROFILE"
  printf '  "failed_count": %d,\n' "$FAILED"
  printf '  "benches": [\n'
  n="${#RESULTS[@]}"
  for i in "${!RESULTS[@]}"; do
    sep=","; [ $((i+1)) -eq "$n" ] && sep=""
    printf '    "%s"%s\n' "${RESULTS[$i]}" "$sep"
  done
  printf '  ]\n'
  printf '}\n'
} > "$SUMMARY"

echo "Wrote $SUMMARY"
[ "$FAILED" -eq 0 ] || exit 1
