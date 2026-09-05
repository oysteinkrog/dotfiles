#!/usr/bin/env bash
# falsifier-quality-trend.sh — Track falsifier quality across sessions
# Per references/CROSS-SESSION-LEARNING.md and OPERATOR-ONBOARDING-CURRICULUM.md
#
# Aggregates falsifier-grader output across recent sessions; reports trends
# in operator falsifier-writing quality.
#
# Usage:
#   falsifier-quality-trend.sh [--root <sessions_dir>] [--days-back <N>]

set -uo pipefail

SESSIONS_ROOT="${HOME}/brennerbot_sessions"
DAYS_BACK=90

# Bareword arg forms need an explicit empty-value guard so that
# `falsifier-quality-trend.sh --root` (no value) emits a clean FATAL
# instead of crashing on `$2: unbound variable`.
while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            if [ -z "${2:-}" ]; then
                echo "[FATAL] --root requires a value" >&2
                exit 2
            fi
            SESSIONS_ROOT="$2"; shift 2
            ;;
        --days-back)
            if [ -z "${2:-}" ]; then
                echo "[FATAL] --days-back requires a value" >&2
                exit 2
            fi
            DAYS_BACK="$2"; shift 2
            ;;
        --help|-h)
            sed -n '2,8p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

if [ ! -d "$SESSIONS_ROOT" ]; then
    echo "[INFO] No sessions root: $SESSIONS_ROOT" >&2
    exit 0
fi

echo "=== Falsifier Quality Trend ==="
echo "Sessions root: $SESSIONS_ROOT"
echo "Days back:     $DAYS_BACK"
echo "Date:          $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Find all falsifier-grader reports (subagents/falsifier-grader produces output
# files in analyses/falsifier-grades/ per session).
declare -a GRADE_FILES=()
while IFS= read -r -d '' f; do
    GRADE_FILES+=("$f")
done < <(find "$SESSIONS_ROOT" -path '*/analyses/falsifier-grades/*.md' \
    -mtime -"$DAYS_BACK" -type f -print0 2>/dev/null)

if [ ${#GRADE_FILES[@]} -eq 0 ]; then
    echo "[INFO] no falsifier-grader reports found in last ${DAYS_BACK} days"
    echo ""
    echo "Recommendation: dispatch subagents/falsifier-grader.md at Phase 3 + Phase 7"
    echo "of T3+ sessions to populate this trend data."
    exit 0
fi

NUM_FILES=${#GRADE_FILES[@]}
echo "Found $NUM_FILES falsifier-grader reports"
echo ""

# Aggregate grades. Per subagents/falsifier-grader.md, each report has lines like:
#   H-NNN: grade=Excellent (5/5)
#   H-NNN: grade=Acceptable (3/5)
#   H-NNN: grade=Poor (1/5)
declare -i TOTAL_HS=0
declare -A GRADE_COUNTS=( [Excellent]=0 [Good]=0 [Acceptable]=0 [Weak]=0 [Poor]=0 )

# Collect per-session timestamps for trend
declare -a SESSION_DATES=()
declare -a SESSION_AVERAGES=()

for f in "${GRADE_FILES[@]}"; do
    [ -f "$f" ] || continue

    # Extract grades from this file
    while IFS= read -r grade; do
        [ -z "$grade" ] && continue
        TOTAL_HS=$((TOTAL_HS + 1))
        if [ -n "${GRADE_COUNTS[$grade]+set}" ]; then
            GRADE_COUNTS[$grade]=$((GRADE_COUNTS[$grade] + 1))
        fi
    done < <(grep -oE 'grade=(Excellent|Good|Acceptable|Weak|Poor)' "$f" 2>/dev/null \
        | sed 's/grade=//')

    # Per-session average (1=Poor → 5=Excellent)
    file_total=$(grep -oE 'grade=(Excellent|Good|Acceptable|Weak|Poor)' "$f" 2>/dev/null | wc -l)
    if [ "$file_total" -gt 0 ]; then
        avg=$(awk -v ex="$(grep -c 'grade=Excellent' "$f" 2>/dev/null)" \
                  -v gd="$(grep -c 'grade=Good' "$f" 2>/dev/null)" \
                  -v ac="$(grep -c 'grade=Acceptable' "$f" 2>/dev/null)" \
                  -v wk="$(grep -c 'grade=Weak' "$f" 2>/dev/null)" \
                  -v po="$(grep -c 'grade=Poor' "$f" 2>/dev/null)" \
                  -v t="$file_total" \
                  'BEGIN { printf "%.2f", (5*ex + 4*gd + 3*ac + 2*wk + 1*po) / t }')
        # Use file mtime as date
        file_date=$(stat -c %y "$f" 2>/dev/null \
                  || stat -f %Sm -t %Y-%m-%d "$f" 2>/dev/null \
                  || echo "unknown")
        SESSION_DATES+=("${file_date:0:10}")
        SESSION_AVERAGES+=("$avg")
    fi
done

# Distribution summary
echo "## Aggregate distribution (across $NUM_FILES sessions; $TOTAL_HS Hs graded)"
echo ""
for grade in Excellent Good Acceptable Weak Poor; do
    count=${GRADE_COUNTS[$grade]:-0}
    if [ "$TOTAL_HS" -gt 0 ]; then
        pct=$(awk -v c="$count" -v t="$TOTAL_HS" 'BEGIN { printf "%5.1f", c*100/t }')
    else
        pct="  0.0"
    fi
    printf '  %-11s : %4d (%s%%)\n' "$grade" "$count" "$pct"
done

# Per-session trend (chronological)
echo ""
echo "## Per-session trend"
echo ""
echo "  Date         Session avg (1=Poor → 5=Excellent)"
n=${#SESSION_DATES[@]}
if [ "$n" -eq 0 ]; then
    echo "  (no per-session data)"
else
    # Pair them and sort by date
    paste -d $'\t' \
        <(printf '%s\n' "${SESSION_DATES[@]}") \
        <(printf '%s\n' "${SESSION_AVERAGES[@]}") \
        | sort \
        | awk -F'\t' '{ printf "  %s   %.2f\n", $1, $2 }'
fi

# Trend signal
echo ""
echo "## Trend signal"
echo ""
if [ "$TOTAL_HS" -lt 10 ]; then
    echo "  Insufficient data (n=$TOTAL_HS); need ≥10 graded Hs for trend signal."
elif [ "${GRADE_COUNTS[Poor]:-0}" -gt $((TOTAL_HS / 4)) ]; then
    echo "  ⚠ >25% Poor falsifiers — operator is producing weak Hs."
    echo "  Recommendation: review FRAMING-WORKBOOK.md F5 + PHASE-1-ANTI-EXAMPLES.md AE-1.2."
elif [ "${GRADE_COUNTS[Excellent]:-0}" -gt $((TOTAL_HS / 2)) ]; then
    echo "  ✓ Strong falsifier discipline — >50% Excellent."
elif [ "$TOTAL_HS" -gt 0 ] && [ "$((${GRADE_COUNTS[Excellent]:-0} + ${GRADE_COUNTS[Good]:-0}))" -gt $((TOTAL_HS * 6 / 10)) ]; then
    echo "  ✓ Healthy distribution — >60% Good or Excellent."
else
    echo "  → Mixed distribution — opportunities for improvement; review CRITIQUE-CRAFT.md."
fi

echo ""
echo "==="
echo "Trend report complete."
