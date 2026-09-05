#!/usr/bin/env bash
# operator-self-assessment.sh — Operator end-of-week self-assessment
# Per references/OPERATOR-ONBOARDING-CURRICULUM.md
#
# Surveys recent sessions in ~/brennerbot_sessions/ and reports calibration.

set -uo pipefail

WEEK_NUM=""
SESSIONS_ROOT="${HOME}/brennerbot_sessions"
DAYS_BACK=7

# Parse args. Bareword forms need an empty-value guard so that
# `operator-self-assessment.sh --week` (no value) emits a clean FATAL
# instead of crashing on `$2: unbound variable` under set -u.
require_value() {
    if [ -z "${2:-}" ]; then
        echo "[FATAL] $1 requires a value" >&2
        exit 2
    fi
}
while [ $# -gt 0 ]; do
    case "$1" in
        --week)
            require_value --week "${2:-}"
            WEEK_NUM="$2"; shift 2
            ;;
        --root)
            require_value --root "${2:-}"
            SESSIONS_ROOT="$2"; shift 2
            ;;
        --days-back)
            require_value --days-back "${2:-}"
            DAYS_BACK="$2"; shift 2
            ;;
        *) shift ;;
    esac
done

# Filter sessions root by --week if specified:
if [ -n "$WEEK_NUM" ]; then
    if [ -d "$SESSIONS_ROOT/week${WEEK_NUM}" ]; then
        SESSIONS_ROOT="$SESSIONS_ROOT/week${WEEK_NUM}"
    fi
fi

if [ ! -d "$SESSIONS_ROOT" ]; then
    echo "[INFO] No sessions found at: $SESSIONS_ROOT"
    echo "[INFO] Use --root <path> to specify a different location"
    exit 0
fi

echo "=== Operator Self-Assessment ==="
echo "Sessions root: $SESSIONS_ROOT"
echo "Days back:     $DAYS_BACK"
echo "Date:          $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "==="

# Find recent sessions (within DAYS_BACK):
declare -i TOTAL_SESSIONS=0
declare -i COMPLETED_SESSIONS=0
declare -i FAILED_SESSIONS=0
declare -A TIER_COUNTS
declare -i F_CODE_TOTAL=0

# Find session dirs (those with phase0_scope_decision.md). Use a null-delimited
# array so paths containing whitespace don't get split apart by `for x in $var`.
declare -a SESSION_DIRS=()
while IFS= read -r -d '' marker; do
    # marker is /<ws>/.brenner_workspace/phase0_scope_decision.md.
    # First dirname → /<ws>/.brenner_workspace; second → /<ws>.
    ws_dir="$(dirname "$(dirname "$marker")")"
    SESSION_DIRS+=("$ws_dir")
done < <(find "$SESSIONS_ROOT" -maxdepth 4 -name 'phase0_scope_decision.md' \
    -mtime -"$DAYS_BACK" -print0 2>/dev/null)

# Dedupe (a single workspace may match multiple times via symlinks, etc):
if [ ${#SESSION_DIRS[@]} -gt 0 ]; then
    mapfile -t SESSION_DIRS < <(printf '%s\n' "${SESSION_DIRS[@]}" | sort -u)
fi

if [ ${#SESSION_DIRS[@]} -eq 0 ]; then
    echo "[INFO] No recent sessions found"
    exit 0
fi

for ws in "${SESSION_DIRS[@]}"; do
    [ -d "$ws" ] || continue
    TOTAL_SESSIONS=$((TOTAL_SESSIONS + 1))

    # Tier — two-stage extract: locate the tier line, then pull the T-token.
    # The previous one-stage `grep -oE 'tier:\s*T[1-5]' | awk '{print $NF}'`
    # silently broke for files written without a space after the colon
    # (`tier:T3`): grep would match the whole `tier:T3` substring as ONE
    # field, awk's $NF would echo the entire match back, and $TIER ended up
    # as `tier:T3` instead of `T3`. Splitting the steps keeps each regex
    # narrow and the final value is just the T-token.
    TIER=$(grep -E '^[[:space:]]*tier[[:space:]]*:' \
              "$ws/.brenner_workspace/phase0_scope_decision.md" 2>/dev/null \
           | head -1 \
           | grep -oE 'T[1-5]' \
           | head -1)
    [ -z "$TIER" ] && TIER="unknown"
    TIER_COUNTS[$TIER]=$((${TIER_COUNTS[$TIER]:-0} + 1))

    # Did session reach Phase 9?
    if [ -f "$ws/deliverables/HANDBACK.md" ]; then
        COMPLETED_SESSIONS=$((COMPLETED_SESSIONS + 1))
    else
        FAILED_SESSIONS=$((FAILED_SESSIONS + 1))
    fi

    # Count F-### codes triggered:
    if [ -d "$ws/session-logs" ]; then
        F_CODES=$(grep -hroE 'F-[0-9]+' "$ws/session-logs/" 2>/dev/null | wc -l)
        F_CODE_TOTAL=$((F_CODE_TOTAL + F_CODES))
    fi
done

echo ""
echo "## Sessions overview"
echo "Total sessions:     $TOTAL_SESSIONS"
echo "Completed (Phase 9): $COMPLETED_SESSIONS"
echo "Incomplete:         $FAILED_SESSIONS"

if [ $TOTAL_SESSIONS -gt 0 ]; then
    COMPLETION_PCT=$(( COMPLETED_SESSIONS * 100 / TOTAL_SESSIONS ))
    echo "Completion rate:    ${COMPLETION_PCT}%"
fi

echo ""
echo "## Tier distribution"
for tier in T1 T2 T3 T4 T5 unknown; do
    count="${TIER_COUNTS[$tier]:-0}"
    if [ "$count" -gt 0 ]; then
        echo "$tier: $count"
    fi
done

echo ""
echo "## Failure-mode signals"
echo "F-### codes triggered (across all sessions): $F_CODE_TOTAL"
if [ $TOTAL_SESSIONS -gt 0 ]; then
    F_PER_SESSION=$(( F_CODE_TOTAL / TOTAL_SESSIONS ))
    echo "F-### per session (avg):                     $F_PER_SESSION"
fi

echo ""
echo "## Calibration recommendations"

if [ $FAILED_SESSIONS -gt 0 ] && [ $TOTAL_SESSIONS -gt 0 ]; then
    INCOMPLETE_PCT=$(( FAILED_SESSIONS * 100 / TOTAL_SESSIONS ))
    if [ $INCOMPLETE_PCT -gt 30 ]; then
        echo "- WARN: ${INCOMPLETE_PCT}% sessions incomplete; review framing or tier estimation"
    fi
fi

if [ $TOTAL_SESSIONS -gt 0 ] && [ $F_CODE_TOTAL -eq 0 ]; then
    echo "- INFO: zero F-codes triggered; either you're highly disciplined or not running into normal pitfalls (which would be unusual)"
fi

if [ $TOTAL_SESSIONS -gt 0 ] && [ $F_CODE_TOTAL -gt $((TOTAL_SESSIONS * 5)) ]; then
    echo "- WARN: high F-code rate (>5 per session); review STRESS-TEST-SCENARIOS.md and OPERATOR-CARDS.md"
fi

# Most-common F-codes:
echo ""
echo "## Top F-### codes triggered"
for ws in "${SESSION_DIRS[@]}"; do
    [ -d "$ws/session-logs" ] || continue
    grep -hroE 'F-[0-9]+' "$ws/session-logs/" 2>/dev/null
done | sort | uniq -c | sort -rn | head -5

echo ""
echo "## Next-step recommendations"

# Tier-specific:
if [ -n "$WEEK_NUM" ]; then
    case "$WEEK_NUM" in
        1)
            T1_COUNT=${TIER_COUNTS[T1]:-0}
            if [ "$T1_COUNT" -lt 1 ]; then
                echo "- Week 1 needs ≥1 T1 session (per OPERATOR-ONBOARDING-CURRICULUM.md)"
            fi
            ;;
        2)
            T2_COUNT=${TIER_COUNTS[T2]:-0}
            if [ "$T2_COUNT" -lt 1 ]; then
                echo "- Week 2 needs ≥1 T2 session"
            fi
            ;;
        3)
            T3_COUNT=${TIER_COUNTS[T3]:-0}
            if [ "$T3_COUNT" -lt 1 ]; then
                echo "- Week 3 needs ≥1 T3 session (with composition)"
            fi
            ;;
        4)
            echo "- Week 4 needs T3 with full Six-Layer-Validation pass + drift-check + reconciliation"
            ;;
    esac
fi

echo ""
echo "Self-assessment complete."
