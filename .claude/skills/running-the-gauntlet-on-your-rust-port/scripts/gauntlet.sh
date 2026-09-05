#!/usr/bin/env bash
# gauntlet.sh — single-entry orchestrator. Dispatches the whole 16-phase pipeline
# (or a mode-restricted subset) against a target Rust port.
#
# USAGE:
#   gauntlet.sh <target-port> [<workspace>] [--mode <mode>] [--resume]
#               [--dry-run] [--soak-hours <hours>]
#               [--pillar <pillar>] [--feature-id <feature-id>]
#               [--new-ref-version <version>]
#
# MODES (per references/methodology/MODE-ROUTER.md):
#   gauntlet-full     (default) all 16 phases
#   audit-only        phases 0-9 only; no implementation
#   harden-pillar     --pillar <pillar>; all parallel capacity on one pillar
#   add-feature       --feature-id <feature-id>; phases 5-13 for one Feature
#   incremental-rebase auto-detect affected phases since last green run
#   compliance-pass   phases 0-2 + 14-16; re-certify against moved reference
#   red-team          phase 15 adversarial-only (no new authoring)
#   migration         --new-ref-version <version>; re-pin + targeted iteration
#   cass-mine-only    cass mining + ledger grep, then exit
#   quick-smoke       minimal phase 0-9 against a tiny port (for SELF-TEST)
#   gauntlet-greenfield all 16 phases with spec/property/self/round-trip oracle
#
# EXIT CODES:
#   0  every phase green; convergence reached (or mode-completion criteria met)
#   1  one or more phases red; details in <workspace>/orchestrator.log
#   2  usage error
#   3  cass / ledger unavailable; blocker entry written

set -euo pipefail

usage() {
  sed -n '2,28p' "$0"
  exit "${1:-2}"
}

TARGET=""
WORKSPACE=""
MODE="gauntlet-full"
RESUME=0
DRY_RUN=0
MODE_ARG=""
SOAK_HOURS="24"

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)     MODE="$2"; shift 2;;
    --resume)   RESUME=1; shift;;
    --dry-run)  DRY_RUN=1; shift;;
    --soak-hours) SOAK_HOURS="$2"; shift 2;;
    --pillar|--feature-id|--new-ref-version)
                MODE_ARG="$2"; shift 2;;
    -h|--help)  usage 0;;
    -*)         echo "Unknown flag: $1" >&2; usage;;
    *)
      if [ -z "$TARGET" ]; then TARGET="$1"
      elif [ -z "$WORKSPACE" ]; then WORKSPACE="$1"
      else echo "Extra arg: $1" >&2; usage
      fi
      shift;;
  esac
done

[ -z "$TARGET" ] && usage
TARGET="$(realpath "$TARGET")"
[ -z "$WORKSPACE" ] && WORKSPACE="${TARGET}__gauntlet_workspace"
SKILL_ROOT="$(realpath "$(dirname "$(realpath "$0")")/..")"

mkdir -p "$WORKSPACE"
LOG="$WORKSPACE/orchestrator.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== gauntlet.sh starting ==="
echo "target:    $TARGET"
echo "workspace: $WORKSPACE"
echo "mode:      $MODE${MODE_ARG:+ ($MODE_ARG)}"
echo "resume:    $RESUME"
echo "dry-run:   $DRY_RUN"
echo "ts:        $(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_phase() {
  local phase="$1"; shift
  local script="$1"; shift
  echo
  printf '===== PHASE %s: %s' "$phase" "$script"
  printf ' %q' "$@"
  printf ' =====\n'
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] would: %q' "$SKILL_ROOT/scripts/$script"
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$SKILL_ROOT/scripts/$script" "$@" || { echo "PHASE $phase FAILED"; exit 1; }
}

run_phase_allow_yellow() {
  local phase="$1"; shift
  local script="$1"; shift
  echo
  printf '===== PHASE %s: %s' "$phase" "$script"
  printf ' %q' "$@"
  printf ' =====\n'
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] would: %q' "$SKILL_ROOT/scripts/$script"
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  if "$SKILL_ROOT/scripts/$script" "$@"; then
    return 0
  fi
  local code=$?
  if [ "$code" -eq 1 ]; then
    echo "PHASE $phase YELLOW: $script reported advisory status; continuing."
    return 0
  fi
  echo "PHASE $phase FAILED"
  exit 1
}

# ---- Phase dispatch per mode -----------------------------------------------
case "$MODE" in
  cass-mine-only)
    run_phase 0 init-workspace.sh "$TARGET" "$WORKSPACE"
    run_phase X mine-cass-cross-machine.sh "$WORKSPACE"
    exit 0
    ;;
  quick-smoke)
    run_phase 0 install-toolchain.sh --workspace "$WORKSPACE"
    run_phase 0 init-workspace.sh "$TARGET" "$WORKSPACE"
    run_phase_allow_yellow 0 detect-project-class.sh "$TARGET" --workspace "$WORKSPACE"
    run_phase_allow_yellow 0 oracle-preflight-doctor.sh "$TARGET" --workspace "$WORKSPACE"
    run_phase 9 run-bench-matrix.sh "$TARGET" "$WORKSPACE"
    run_phase 9 run-conformance-suite.sh "$TARGET" "$WORKSPACE" --no-fuzz
    run_phase 9 compute-parity-score.sh "$WORKSPACE"
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "quick-smoke dry-run complete; phase commands were not executed; review $LOG for the planned command list"
    else
      echo "quick-smoke complete; review $WORKSPACE/artifacts/bench/, $WORKSPACE/artifacts/conformance/, and $WORKSPACE/reports/parity_score.json"
    fi
    exit 0
    ;;
  audit-only)
    PHASES=(0 1 2 3 4 5 6 7 8 9)
    ;;
  harden-pillar)
    [ -z "$MODE_ARG" ] && { echo "--mode harden-pillar requires --pillar" >&2; exit 2; }
    PHASES=(0 9 10 11 12 13 14)
    ;;
  add-feature)
    [ -z "$MODE_ARG" ] && { echo "--mode add-feature requires --feature-id" >&2; exit 2; }
    PHASES=(5 6 7 12 13 14)
    ;;
  incremental-rebase)
    # auto-detect affected phases via git diff since last green run
    PHASES=(0 1 9 11 14 16)
    ;;
  compliance-pass)
    PHASES=(0 1 2 14 15 16)
    ;;
  red-team)
    PHASES=(15)
    ;;
  migration)
    [ -z "$MODE_ARG" ] && { echo "--mode migration requires --new-ref-version" >&2; exit 2; }
    PHASES=(0 1 2 3 4 9 11 12 13 14 16)
    ;;
  gauntlet-full|gauntlet-greenfield)
    PHASES=(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    usage
    ;;
esac

# ---- Phase loop ------------------------------------------------------------
for p in "${PHASES[@]}"; do
  case "$p" in
    0)
      run_phase 0 install-toolchain.sh --workspace "$WORKSPACE"
      run_phase 0 init-workspace.sh "$TARGET" "$WORKSPACE"
      run_phase_allow_yellow 0 detect-project-class.sh "$TARGET" --workspace "$WORKSPACE"
      run_phase_allow_yellow 0 check-skills.sh "$WORKSPACE"
      run_phase_allow_yellow 0 oracle-preflight-doctor.sh "$TARGET" --workspace "$WORKSPACE"
      ;;
    1) echo "[phase 1] RECON — fan out surface-archaeologist per crate (orchestrator-driven; not a single script)";;
    2)
      if [ "$MODE" = "gauntlet-greenfield" ]; then
        echo "[phase 2] SPEC PINNING — scope-decider + spec-tag-extractor write greenfield contracts"
      else
        echo "[phase 2] REFERENCE PINNING — scope-decider subagent writes contracts (orchestrator-driven)"
      fi
      ;;
    3)
      if [ "$MODE" = "gauntlet-greenfield" ]; then
        echo "[phase 3] GREENFIELD ORACLE WIRING — greenfield-oracle-wirer builds Spec / Property / Self / Round-trip / External-tool dispatch"
      else
        echo "[phase 3] ORACLE WIRING — oracle-wirer + oracle-preflight-doctor-builder + python-reference-bridger"
      fi
      ;;
    4) echo "[phase 4] GOLDEN CAPTURE — golden-capturer subagent (parallel per tier × per fixture-source)";;
    5) echo "[phase 5] PERFORMANCE HARNESS — bench-author + hot-path-counter-instrumenter";;
    6) echo "[phase 6] CONFORMANCE HARNESS — oracle-test-author + metamorphic-author + ... (parallel)";;
    7) echo "[phase 7] SURFACE PARITY INVENTORY — feature-universe-builder + invariant-catalog-builder + coverage-dashboard-builder";;
    8) echo "[phase 8] NEGATIVE-LEDGER MANDATE — ledger-seeder subagent";;
    9)
      run_phase 9 run-bench-matrix.sh "$TARGET" "$WORKSPACE"
      run_phase 9 run-conformance-suite.sh "$TARGET" "$WORKSPACE"
      run_phase 9 compute-feature-coverage.sh "$WORKSPACE"
      run_phase 9 compute-parity-score.sh "$WORKSPACE"
      ;;
    10) echo "[phase 10] IDEA-WIZARD ROUND — idea-wizard-orchestrator + advanced-methods-miner";;
    11)
      echo "[phase 11] ITERATE — repeat phases 5-10 until convergence (≥10 rounds)"
      if [ "$DRY_RUN" -eq 1 ]; then
        run_phase 11 convergence-tracker.sh "$WORKSPACE"
        echo "[phase 11] dry-run complete; iteration-coordinator would dispatch the next round until convergence"
      elif "$SKILL_ROOT/scripts/convergence-tracker.sh" "$WORKSPACE"; then
        echo "[phase 11] converged; continuing to remediation design"
      else
        echo "[phase 11] convergence not reached; dispatch iteration-coordinator for the next round, then re-run with --resume"
        exit 1
      fi
      ;;
    12) echo "[phase 12] REMEDIATION DESIGN — remediation-architect subagent (one per pillar)";;
    13) echo "[phase 13] BEADS HANDOFF — bead-author + bead-polisher (4-5 rounds)";;
    14)
      echo "[phase 14] FRESH-EYES REVIEW — 3 verbatim prompts"
      run_phase 14 run-fresh-eyes-pass.sh "$TARGET" "$WORKSPACE"
      ;;
    15)
      run_phase 15 run-soak-campaign.sh "$TARGET" "$WORKSPACE" "$SOAK_HOURS"
      ;;
    16)
      run_phase 16 final-report-builder.sh "$WORKSPACE"
      ;;
  esac
done

echo
echo "=== gauntlet.sh complete ==="
exit 0
