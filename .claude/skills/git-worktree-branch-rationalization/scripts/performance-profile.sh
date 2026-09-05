#!/usr/bin/env bash
# performance-profile.sh — Per-phase profiling.
#
# Two modes:
#
#   wrap   — wraps another script invocation with `time` capture; writes a row
#            to <workspace>/phase_timings.tsv with phase / script / start /
#            duration / exit code / wall / user / sys.
#            Usage:
#              performance-profile.sh <project-path> wrap <phase> <script> [args...]
#
#   report — Phase 11 aggregator. Reads phase_timings.tsv, sums per-phase
#            totals, computes per-script breakdown, estimates parallelism
#            efficiency (sum of script times / wall span), compares totals
#            against the SLOs documented in references/MEASUREMENT.md, and
#            emits <workspace>/performance_profile.md with a bottleneck
#            callout.
#            Usage:
#              performance-profile.sh <project-path> report
#
# Both modes are non-destructive. The script never mutates the wrapped
# command's arguments and never `--no-verify`'s anything.
#
# Resume-aware: report mode skips re-rendering when phase_timings.tsv hasn't
# changed since the last report (signature embedded in markdown header).
#
# Exit codes:
#   wrap:   passes through the wrapped command's exit code
#   report: 0 on success, 2 on preflight failure, 5 if any SLO-defined budget
#           is exceeded (run still completes; the failure is informational)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage:
  performance-profile.sh <project-path> wrap <phase> <script> [args...]
  performance-profile.sh <project-path> report

wrap   — runs <script> [args...], appends a timing row to
         <workspace>/phase_timings.tsv, exits with the wrapped script's
         exit code.

report — aggregates phase_timings.tsv into <workspace>/performance_profile.md
         with per-phase totals, parallelism efficiency, and SLO compliance.

Env:
  WORKSPACE              Workspace dir override.
  PROFILE_SLO_PHASE_3    SLO budget (seconds) for Phase 3 (default 300).
  PROFILE_SLO_PHASE_5    SLO budget (seconds) for Phase 5 (default 1800).
  PROFILE_SLO_PHASE_8    SLO budget (seconds) for Phase 8 (default 3600).
  PROFILE_FORCE=1        Regenerate report even if signature unchanged.

Exit codes:
  wrap:   the wrapped command's exit code
  report: 0 ok | 2 preflight failed | 5 SLO budget exceeded (informational)
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
MODE="${2:-}"
shift 2 || { usage >&2; exit 64; }

PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
mkdir -p "$WORKSPACE_DIR"
TIMINGS="$WORKSPACE_DIR/phase_timings.tsv"
REPORT="$WORKSPACE_DIR/performance_profile.md"
RAW_TIMES="$WORKSPACE_DIR/phase_timings.raw.tsv"

if [[ ! -f "$TIMINGS" ]]; then
  printf 'phase\tscript\tstart_utc\tend_utc\tduration_s\texit_code\twall_s\tuser_s\tsys_s\targs_hash\n' > "$TIMINGS"
fi
if [[ ! -f "$RAW_TIMES" ]]; then
  printf 'run_id\tstart_utc\tphase\tscript\twall_s\tuser_s\tsys_s\n' > "$RAW_TIMES"
fi

# ---- wrap mode ----
if [[ "$MODE" == "wrap" ]]; then
  PHASE="${1:?missing phase tag}"
  SCRIPT_PATH="${2:?missing script path}"
  shift 2
  if [[ ! -x "$SCRIPT_PATH" ]]; then
    # Try sibling lookup.
    if [[ -x "$SCRIPT_DIR/$SCRIPT_PATH" ]]; then
      SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
    else
      echo "ERROR: $SCRIPT_PATH is not executable." >&2
      exit 2
    fi
  fi

  args_hash="-"
  if [[ "$#" -gt 0 ]]; then
    if command -v sha1sum >/dev/null 2>&1; then
      args_hash=$(printf '%s\n' "$@" | sha1sum | awk '{print substr($1,1,12)}')
    else
      args_hash=$(printf '%s\n' "$@" | shasum -a 1 | awk '{print substr($1,1,12)}')
    fi
  fi

  start_utc=$(date -u +%FT%TZ)
  run_id="$(date -u +%Y%m%d%H%M%S)-$$-$RANDOM"
  start_epoch=$(date -u +%s)

  # Capture wall/user/sys via /usr/bin/time when available; otherwise rely on
  # epoch-delta wall time only.
  TIMEFORMAT='%R %U %S'
  set +e
  if command -v /usr/bin/time >/dev/null 2>&1; then
    /usr/bin/time -f "$run_id\t$start_utc\t$PHASE\t$(basename "$SCRIPT_PATH")\t%e\t%U\t%S" -a -o "$RAW_TIMES" "$SCRIPT_PATH" "$@"
    rc=$?
    latest_time=$(awk -F'\t' -v id="$run_id" '$1 == id {line=$0} END {print line}' "$RAW_TIMES" 2>/dev/null || true)
    if [[ -n "$latest_time" ]]; then
      IFS=$'\t' read -r _time_run_id _time_start _time_phase _time_script wall_s user_s sys_s <<< "$latest_time"
      [[ -z "${wall_s:-}" ]] && wall_s="-"
      [[ -z "${user_s:-}" ]] && user_s="-"
      [[ -z "${sys_s:-}" ]]  && sys_s="-"
    else
      wall_s="-"; user_s="-"; sys_s="-"
    fi
  else
    "$SCRIPT_PATH" "$@"
    rc=$?
    wall_s="-"; user_s="-"; sys_s="-"
  fi
  set -e

  end_utc=$(date -u +%FT%TZ)
  end_epoch=$(date -u +%s)
  duration=$((end_epoch - start_epoch))

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$PHASE" "$(basename "$SCRIPT_PATH")" "$start_utc" "$end_utc" "$duration" \
    "$rc" "$wall_s" "$user_s" "$sys_s" "$args_hash" \
    >> "$TIMINGS"

  exit "$rc"
fi

# ---- report mode ----
if [[ "$MODE" != "report" ]]; then
  echo "ERROR: unknown mode '$MODE' (expected 'wrap' or 'report')" >&2
  usage >&2
  exit 64
fi

if [[ ! -s "$TIMINGS" ]] || [[ "$(wc -l < "$TIMINGS")" -lt 2 ]]; then
  echo "ERROR: $TIMINGS has no recorded timings; run wrap mode first." >&2
  exit 2
fi

SIG=$(sha256sum "$TIMINGS" | awk '{print $1}')
HEADER_SIG="performance-profile/v1 timings=$SIG"
if [[ -z "${PROFILE_FORCE:-}" && -f "$REPORT" ]]; then
  if grep -qE "^<!-- signature: $HEADER_SIG -->$" "$REPORT" 2>/dev/null; then
    log "performance_profile.md unchanged; reusing"
    echo "current: $REPORT"
    exit 0
  fi
fi

SLO_P3="${PROFILE_SLO_PHASE_3:-300}"
SLO_P5="${PROFILE_SLO_PHASE_5:-1800}"
SLO_P8="${PROFILE_SLO_PHASE_8:-3600}"

# Aggregate.
declare -A PHASE_TOTAL
declare -A PHASE_FIRST_START
declare -A PHASE_LAST_END
declare -A SCRIPT_TOTAL
declare -A SCRIPT_RUNS

while IFS=$'\t' read -r phase script start_utc end_utc dur rc wall _user _sys _args; do
  [[ "$phase" == "phase" ]] && continue
  [[ -z "$phase" ]] && continue
  PHASE_TOTAL[$phase]=$(( ${PHASE_TOTAL[$phase]:-0} + ${dur:-0} ))
  if [[ -z "${PHASE_FIRST_START[$phase]:-}" || "$start_utc" < "${PHASE_FIRST_START[$phase]}" ]]; then
    PHASE_FIRST_START[$phase]="$start_utc"
  fi
  if [[ -z "${PHASE_LAST_END[$phase]:-}" || "$end_utc" > "${PHASE_LAST_END[$phase]}" ]]; then
    PHASE_LAST_END[$phase]="$end_utc"
  fi
  key="$phase/$script"
  SCRIPT_TOTAL[$key]=$(( ${SCRIPT_TOTAL[$key]:-0} + ${dur:-0} ))
  SCRIPT_RUNS[$key]=$(( ${SCRIPT_RUNS[$key]:-0} + 1 ))
done < "$TIMINGS"

epoch_of() { date -u -d "$1" +%s 2>/dev/null || echo 0; }

# SLO comparison.
slo_for() {
  case "$1" in
    3|phase3|"phase 3") echo "$SLO_P3" ;;
    5|phase5|"phase 5") echo "$SLO_P5" ;;
    8|phase8|"phase 8") echo "$SLO_P8" ;;
    *) echo "" ;;
  esac
}

declare -i SLO_BREACHES=0
declare -a BREACH_LINES=()

# Build report.
{
  printf '<!-- signature: %s -->\n' "$HEADER_SIG"
  printf '# Performance profile\n\n'
  printf "Project:    \`%s\`\n" "$PROJECT_ABS"
  printf 'Generated:  %s\n' "$(date -u +%FT%TZ)"
  printf "Source:     \`%s\`\n\n" "$TIMINGS"

  printf '## Per-phase totals + parallelism efficiency\n\n'
  printf '| Phase | Total CPU-time (s) | Wall span (s) | Parallelism | SLO budget (s) | SLO status |\n'
  printf '|-------|--------------------|---------------|-------------|----------------|------------|\n'

  # Iterate phases in sorted order for stable output.
  for phase in $(printf '%s\n' "${!PHASE_TOTAL[@]}" | sort); do
    total="${PHASE_TOTAL[$phase]}"
    first="${PHASE_FIRST_START[$phase]:-}"
    last="${PHASE_LAST_END[$phase]:-}"
    if [[ -n "$first" && -n "$last" ]]; then
      wall=$(( $(epoch_of "$last") - $(epoch_of "$first") ))
      [[ "$wall" -lt 1 ]] && wall=1
    else
      wall=0
    fi
    if [[ "$wall" -gt 0 ]]; then
      par=$(awk -v t="$total" -v w="$wall" 'BEGIN{printf "%.2f", t/w}')
    else
      par="n/a"
    fi
    slo=$(slo_for "$phase")
    if [[ -n "$slo" ]]; then
      if [[ "$total" -gt "$slo" ]]; then
        slo_status="EXCEEDED ($total > $slo)"
        SLO_BREACHES=$((SLO_BREACHES+1))
        BREACH_LINES+=("- phase \`$phase\`: ${total}s vs budget ${slo}s")
      else
        slo_status="OK"
      fi
    else
      slo="-"
      slo_status="n/a"
    fi
    printf '| %s | %d | %d | %s | %s | %s |\n' "$phase" "$total" "$wall" "$par" "$slo" "$slo_status"
  done
  printf '\n'

  printf '## Per-script breakdown\n\n'
  printf '| Phase / script | Runs | Total (s) | Mean (s) |\n'
  printf '|----------------|------|-----------|----------|\n'
  for key in $(printf '%s\n' "${!SCRIPT_TOTAL[@]}" | sort); do
    total="${SCRIPT_TOTAL[$key]}"
    runs="${SCRIPT_RUNS[$key]}"
    if [[ "$runs" -gt 0 ]]; then
      mean=$(( total / runs ))
    else
      mean=0
    fi
    printf '| %s | %d | %d | %d |\n' "$key" "$runs" "$total" "$mean"
  done
  printf '\n'

  # Bottleneck callout: top 3 scripts by total time.
  printf '## Bottleneck callout\n\n'
  top3=$(for key in "${!SCRIPT_TOTAL[@]}"; do
           printf '%d\t%s\n' "${SCRIPT_TOTAL[$key]}" "$key"
         done | sort -rn | head -3)
  if [[ -n "$top3" ]]; then
    while IFS=$'\t' read -r t k; do
      printf -- "- \`%s\` — %ds total\n" "$k" "$t"
    done <<< "$top3"
  else
    printf '_(no entries)_\n'
  fi
  printf '\n'

  printf '## SLO compliance\n\n'
  if [[ "$SLO_BREACHES" -eq 0 ]]; then
    printf 'All measured phases within their SLO budgets (or no SLO defined).\n'
  else
    printf '%d phase(s) exceeded their SLO budget:\n\n' "$SLO_BREACHES"
    for line in "${BREACH_LINES[@]}"; do printf '%s\n' "$line"; done
  fi
  printf '\n'

  printf 'See references/MEASUREMENT.md for SLO definitions and per-phase\n'
  printf 'quality metrics. Override budgets via PROFILE_SLO_PHASE_{3,5,8}.\n'
} > "$REPORT"

log "wrote $REPORT"
echo "phases=${#PHASE_TOTAL[@]} slo_breaches=$SLO_BREACHES"

if [[ "$SLO_BREACHES" -gt 0 ]]; then
  exit 5
fi
exit 0
