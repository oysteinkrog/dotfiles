#!/usr/bin/env bash
# check-six-layer-validation.sh — Pre-Phase-8 mandatory check
# Per references/SIX-LAYER-VALIDATION.md
#
# Runs Layer 1-5 sweeps; reports per-layer PASS/FAIL.
# Layer 6 (external review) is N/A from script (handled by human reviewer).

set -uo pipefail

usage() {
    echo "Usage: check-six-layer-validation.sh [--workspace=<path>] [--tier=<T1|T2|T3|T4|T5>]"
    echo "       check-six-layer-validation.sh [workspace] [tier]"
}

WORKSPACE_ARG="."
TIER="T3"
POSITIONAL_COUNT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace=*)
            WORKSPACE_ARG="${1#*=}"
            ;;
        --workspace)
            if [[ $# -lt 2 ]]; then
                echo "[FATAL] --workspace requires a value" >&2
                usage >&2
                exit 2
            fi
            WORKSPACE_ARG="$2"
            shift
            ;;
        --tier=*)
            TIER="${1#*=}"
            ;;
        --tier)
            if [[ $# -lt 2 ]]; then
                echo "[FATAL] --tier requires a value" >&2
                usage >&2
                exit 2
            fi
            TIER="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            echo "[FATAL] Unknown flag: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            case "$POSITIONAL_COUNT" in
                0)
                    WORKSPACE_ARG="$1"
                    ;;
                1)
                    TIER="$1"
                    ;;
                *)
                    echo "[FATAL] Unexpected argument: $1" >&2
                    usage >&2
                    exit 2
                    ;;
            esac
            POSITIONAL_COUNT=$((POSITIONAL_COUNT + 1))
            ;;
    esac
    shift
done

case "$TIER" in
    T1|T2|T3|T4|T5)
        ;;
    *)
        echo "[FATAL] Unknown tier: $TIER" >&2
        usage >&2
        exit 2
        ;;
esac

# Resolve to absolute path BEFORE cd. The sub-scripts we invoke also accept
# --workspace=<path>; if we passed them a relative path, they'd resolve it
# against THEIR cwd (which is the workspace itself after our cd), producing
# nonsense. Absolute paths sidestep that entirely.
WORKSPACE="$(cd "$WORKSPACE_ARG" 2>/dev/null && pwd)" \
    || { echo "[FATAL] Cannot cd to workspace: $WORKSPACE_ARG" >&2; exit 1; }
cd "$WORKSPACE" || exit 1

# Find script directory (skill scripts/ folder):
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Per-layer output sink. Use mktemp so two operators running this script
# concurrently don't clobber each other's logs (the previous /tmp/.layer-N-out
# pattern was both predictable and racy on shared hosts). Keep these outputs:
# repo policy forbids file deletion, and failures print paths into this dir.
LAYER_OUT_DIR="$(mktemp -d -t brennerbot-six-layer.XXXXXX)"

# Helper: run a check and capture result. The previous version had a redundant
# `$?` re-test inside the `if` — collapsed to the single `if cmd; then` form.
check() {
    local layer_name="$1"
    local layer_num="$2"
    shift 2
    local out="$LAYER_OUT_DIR/layer-${layer_num}.out"

    if "$@" >"$out" 2>&1; then
        echo "Layer $layer_num ($layer_name): PASS"
        return 0
    fi

    echo "Layer $layer_num ($layer_name): FAIL"
    echo "  Captured output: $out"
    return 1
}

declare -i FAILURES=0

echo "=== Six-Layer Validation Check ==="
echo "Workspace: $WORKSPACE"
echo "Tier:      $TIER"
echo "==="

# Layer 1: Bead invariants
if [ -x "${SCRIPT_DIR}/audit-bead-invariants.sh" ]; then
    if check "bead invariants" 1 "${SCRIPT_DIR}/audit-bead-invariants.sh" --workspace="$WORKSPACE" --all; then
        :
    else
        FAILURES=$((FAILURES + 1))
    fi
else
    echo "Layer 1 (bead invariants): SKIPPED (audit-bead-invariants.sh not found)"
fi

# Layer 2: Convergence
if [ -x "${SCRIPT_DIR}/convergence-check.sh" ]; then
    layer2_pass=true
    for phase in 4 6 7; do
        if ! "${SCRIPT_DIR}/convergence-check.sh" --workspace="$WORKSPACE" --phase=$phase \
                >"$LAYER_OUT_DIR/layer-2-phase-$phase.out" 2>&1; then
            layer2_pass=false
            echo "  Phase $phase convergence: FAIL (see $LAYER_OUT_DIR/layer-2-phase-$phase.out)"
        fi
    done
    if [ "$layer2_pass" = "true" ]; then
        echo "Layer 2 (convergence): PASS"
    else
        echo "Layer 2 (convergence): FAIL"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo "Layer 2 (convergence): SKIPPED (convergence-check.sh not found)"
fi

# Layer 3: Marching-order discipline
if [ -d "session-logs" ]; then
    DISPATCH_LOGS=$(find session-logs -name 'dispatch-*.log' 2>/dev/null | wc -l)
    if [ "$DISPATCH_LOGS" -eq 0 ]; then
        echo "Layer 3 (marching-order): WARN (no dispatch logs found)"
    else
        # Count dispatches without recognizable MO templates (free-writes):
        FREE_WRITES=$(grep -h '^MO:' session-logs/dispatch-*.log 2>/dev/null \
            | grep -vcE 'MO:[[:space:]]*MO-[a-z0-9-]+(\.md)?$' || true)
        if [ "$FREE_WRITES" -eq 0 ]; then
            echo "Layer 3 (marching-order): PASS"
        else
            echo "Layer 3 (marching-order): FAIL ($FREE_WRITES free-write dispatches)"
            FAILURES=$((FAILURES + 1))
        fi
    fi
else
    echo "Layer 3 (marching-order): SKIPPED (no session-logs directory)"
fi

# Layer 4: Rotation rules
if [ -x "${SCRIPT_DIR}/check-rotation-rules.sh" ]; then
    if check "rotation rules" 4 "${SCRIPT_DIR}/check-rotation-rules.sh" --workspace="$WORKSPACE"; then
        :
    else
        FAILURES=$((FAILURES + 1))
    fi
else
    echo "Layer 4 (rotation rules): SKIPPED (check-rotation-rules.sh not found)"
fi

# Layer 5: Cross-session learning
# This is workspace-external; check if drift-trend or cross-session catalog exist
if [ -x "${SCRIPT_DIR}/drift-trend.sh" ]; then
    # Don't fail the whole readiness check on this; it is advisory. Do still
    # surface helper failures instead of treating usage/errors as a PASS.
    if "${SCRIPT_DIR}/drift-trend.sh" --skill-dir="$SKILL_DIR" >"$LAYER_OUT_DIR/layer-5.out" 2>&1; then
        # Look for warning-level patterns (3+ same drift verdict in row)
        if grep -qE '(persistent regression|3\+ consecutive)' "$LAYER_OUT_DIR/layer-5.out"; then
            echo "Layer 5 (cross-session): WARN (persistent regressions detected)"
        else
            echo "Layer 5 (cross-session): PASS"
        fi
    else
        echo "Layer 5 (cross-session): SKIPPED (drift-trend failed; see $LAYER_OUT_DIR/layer-5.out)"
    fi
else
    echo "Layer 5 (cross-session): SKIPPED (drift-trend.sh not found)"
fi

# Layer 6: External review
case "$TIER" in
    T1|T2|T3)
        echo "Layer 6 (external review): N/A (T1-T3)"
        ;;
    T4|T5)
        if [ -f "deliverables/EXTERNAL-REVIEW-SIGNOFF.md" ]; then
            echo "Layer 6 (external review): PASS (signoff present)"
        else
            echo "Layer 6 (external review): PENDING (signoff not yet recorded)"
            if [ "$TIER" = "T5" ]; then
                FAILURES=$((FAILURES + 1))
            fi
        fi
        ;;
    *)
        echo "Layer 6 (external review): UNKNOWN TIER ($TIER)"
        ;;
esac

echo "==="
echo "Diagnostic outputs retained at: $LAYER_OUT_DIR"
if [ $FAILURES -eq 0 ]; then
    echo "Verdict: READY FOR PHASE 8"
    exit 0
else
    echo "Verdict: BLOCKED ($FAILURES layer failure(s))"
    exit 1
fi
