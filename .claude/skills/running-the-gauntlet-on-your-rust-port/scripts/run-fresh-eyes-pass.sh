#!/usr/bin/env bash
# run-fresh-eyes-pass.sh — runs the three verbatim Phase-14 fresh-eyes prompts
# in sequence; loops until two consecutive passes come up clean.
#
# USAGE:
#   run-fresh-eyes-pass.sh <target-port> <workspace> [--max-rounds N]
#                          [--bead <id>] [--domain <name>] [--adversarial]
#                          [--onboardee <name>] [--tier-up-smoke]
#                          [--sample-rate <fraction>]
#
# This script is a CLI shim — the actual prompts live in
# subagents/fresh-eyes-reviewer-{a,b,c}.md and must be dispatched via the
# orchestrator. The script wires the loop + the cleanliness check.

set -euo pipefail

usage() { sed -n '2,10p' "$0"; exit "${1:-2}"; }

TARGET=""
WORKSPACE=""
MAX_ROUNDS=10
BEAD_ID=""
DOMAIN=""
ADVERSARIAL=0
ONBOARDEE=""
TIER_UP_SMOKE=0
SAMPLE_RATE=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0;;
    --max-rounds) MAX_ROUNDS="$2"; shift 2;;
    --bead) BEAD_ID="$2"; shift 2;;
    --domain) DOMAIN="$2"; shift 2;;
    --adversarial) ADVERSARIAL=1; shift;;
    --onboardee) ONBOARDEE="$2"; shift 2;;
    --tier-up-smoke) TIER_UP_SMOKE=1; shift;;
    --sample-rate) SAMPLE_RATE="$2"; shift 2;;
    -*)
      echo "Unknown arg: $1" >&2
      usage
      ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$1"
      elif [ -z "$WORKSPACE" ]; then
        WORKSPACE="$1"
      else
        echo "Unexpected arg: $1" >&2
        usage
      fi
      shift
      ;;
  esac
done

[ -n "$TARGET" ] && [ -n "$WORKSPACE" ] || usage

run_gate() {
  local name="$1"
  shift
  local log="$ROUND_DIR/${name}.log"
  local status="$ROUND_DIR/${name}.status"
  local code
  echo "[round $ROUND] $*"
  set +e
  "$@" 2>&1 | tee "$log"
  code=${PIPESTATUS[0]}
  set -e
  printf '%s\n' "$code" > "$status"
  return "$code"
}

# Track consecutive clean rounds.
CLEAN_STREAK=0
ROUND=0

while [ "$CLEAN_STREAK" -lt 2 ] && [ "$ROUND" -lt "$MAX_ROUNDS" ]; do
  ROUND=$((ROUND+1))
  ROUND_DIR="$WORKSPACE/phase14_fresh_eyes_round_$ROUND"
  mkdir -p "$ROUND_DIR"
  cat > "$ROUND_DIR/fresh_eyes_metadata.json" <<JSON
{
  "schema_version": "gauntlet.phase14_fresh_eyes_metadata.v1",
  "bead_id": "$BEAD_ID",
  "domain": "$DOMAIN",
  "adversarial": $([ "$ADVERSARIAL" -eq 1 ] && echo true || echo false),
  "onboardee": "$ONBOARDEE",
  "tier_up_smoke": $([ "$TIER_UP_SMOKE" -eq 1 ] && echo true || echo false),
  "sample_rate": "$SAMPLE_RATE"
}
JSON

  echo "=== Fresh-eyes round $ROUND ==="

  # The orchestrator dispatches subagents fresh-eyes-reviewer-{a,b,c} in this order.
  # Each subagent emits a NN_changes.diff in $ROUND_DIR.
  echo "[round $ROUND] Prompt A: agent reviews their own code"
  echo "[round $ROUND] Prompt B: random-walk exploration + AGENTS.md compliance"
  echo "[round $ROUND] Prompt C: review other agents' code"

  # Concrete tool gates (these CAN run as part of the script):
  cd "$TARGET"
  run_gate cargo_check cargo check --all-targets || true
  run_gate cargo_clippy cargo clippy --all-targets -- -D warnings || true
  run_gate cargo_fmt cargo fmt --check || true
  run_gate cargo_test cargo test --workspace || true

  # ubs is optional.
  if command -v ubs >/dev/null 2>&1; then
    run_gate ubs ubs . || true
  fi

  # miri on harness internals (optional; slow).
  if [ -n "${RUN_MIRI:-}" ]; then
    run_gate miri cargo +nightly miri test --lib || true
  fi
  cd - >/dev/null

  # Cleanliness check: a round is "clean" if cargo check + clippy + fmt + test
  # all returned green AND no fresh-eyes-reviewer subagent emitted material changes.
  CARGO_GREEN=1
  for status in "$ROUND_DIR"/*.status; do
    [ -f "$status" ] || continue
    if [ "$(cat "$status")" != "0" ]; then
      CARGO_GREEN=0
      break
    fi
  done

  MATERIAL_CHANGES=0
  for diff in "$ROUND_DIR"/*_changes.diff; do
    [ -f "$diff" ] || continue
    LINES=$(wc -l < "$diff")
    if [ "$LINES" -gt 3 ]; then
      MATERIAL_CHANGES=$((MATERIAL_CHANGES+1))
    fi
  done

  if [ "$CARGO_GREEN" -eq 1 ] && [ "$MATERIAL_CHANGES" -eq 0 ]; then
    CLEAN_STREAK=$((CLEAN_STREAK+1))
    echo "[round $ROUND] CLEAN  (streak: $CLEAN_STREAK/2)"
  else
    CLEAN_STREAK=0
    echo "[round $ROUND] DIRTY  (cargo_green=$CARGO_GREEN, material_changes=$MATERIAL_CHANGES; streak reset)"
  fi
done

if [ "$CLEAN_STREAK" -ge 2 ]; then
  echo
  echo "=== Fresh-eyes converged after $ROUND rounds (2 consecutive clean) ==="
  # Emit cumulative diff.
  CUMULATIVE="$WORKSPACE/phase14_fresh_eyes_diff.md"
  cat > "$CUMULATIVE" <<MD
# Phase 14 Fresh-Eyes — Cumulative Diff Across $ROUND Rounds

Final clean streak: $CLEAN_STREAK

## Per-round summary
$(for i in $(seq 1 $ROUND); do
    echo "### Round $i"
    ls -1 "$WORKSPACE/phase14_fresh_eyes_round_$i"/*.diff 2>/dev/null | while read d; do
      lines=$(wc -l < "$d")
      echo "  - $(basename $d): $lines lines"
    done
  done)
MD
  exit 0
else
  echo
  echo "=== Fresh-eyes FAILED to converge in $MAX_ROUNDS rounds ==="
  echo "    Investigate: $WORKSPACE/phase14_fresh_eyes_round_$ROUND/"
  exit 1
fi
