#!/usr/bin/env bash
# mine-ledger.sh — Grep the three negative ledgers + last 60 days of cass for
# failure terms. Produces a candidate-blocker report:
#   "Before starting this perf work, the following N candidates were already
#    rejected — review before proceeding"
#
# Called by every perf-bead pre-flight.
#
# USAGE:
#   mine-ledger.sh <workspace> [--target <path>]
#                              [--terms <comma-separated>]
#                              [--filter <pipe-or-comma-separated>]
#                              [--cass-days 60]
#                              [--cass-limit 50]
#                              [--cass-timeout-ms 30000]
#                              [--since <cass-date>] [--until <cass-date>]
#   mine-ledger.sh --lint <ledger.md>
#   mine-ledger.sh --validate-seeds
#
# OUTPUT FILE: <workspace>/reports/ledger_mining_candidates.md
#              <workspace>/reports/ledger_mining_candidates.json
#
# EXIT CODES:
#   0 — mining ran (regardless of hit count)
#   2 — neither ledger nor cass available; recorded as blocker per mandate
#   3 — usage error
#
# IDEMPOTENT.

set -euo pipefail

usage() { sed -n '2,18p' "$0"; exit "${1:-3}"; }

WORKSPACE=""
TARGET=""
TERMS_RAW=""
CASS_DAYS=60
CASS_DAYS_SET=0
CASS_LIMIT=50
CASS_TIMEOUT_MS=30000
FILTER_RAW=""
LINT_FILE=""
VALIDATE_SEEDS=0
SINCE=""
UNTIL=""
POSITIONALS=()

DEFAULT_TERMS="rejected,reverted,abandoned,slower,regressed,didn't help,within noise,no improvement,failed to improve,rolled back,backed out,not a keep,keep gate,micro-lever,cold-start outlier,fused-design,DML mutation operator,frontier"

while [ $# -gt 0 ]; do
  case "$1" in
    --lint)      LINT_FILE="$2"; shift 2;;
    --validate-seeds) VALIDATE_SEEDS=1; shift;;
    --target)    TARGET="$2"; shift 2;;
    --terms)     TERMS_RAW="$2"; shift 2;;
    --filter)    FILTER_RAW="$2"; shift 2;;
    --cass-days) CASS_DAYS="$2"; CASS_DAYS_SET=1; shift 2;;
    --cass-limit) CASS_LIMIT="$2"; shift 2;;
    --cass-timeout-ms) CASS_TIMEOUT_MS="$2"; shift 2;;
    --since)     SINCE="$2"; shift 2;;
    --until)     UNTIL="$2"; shift 2;;
    --gate)      shift 2;;
    -h|--help)   usage 0;;
    *) POSITIONALS+=("$1"); shift;;
  esac
done

lint_ledger() {
  local file="$1"
  [ -f "$file" ] || { echo "ERROR: ledger not found: $file" >&2; exit 2; }
  if ! grep -qiE 'retry[-_ ]condition|retry condition predicate|not worth retrying|retry only if|reconsider only' "$file"; then
    echo "ERROR: ledger lacks a retry-condition predicate marker: $file" >&2
    exit 1
  fi
  echo "ledger lint OK: $file"
}

if [ -n "$LINT_FILE" ]; then
  lint_ledger "$LINT_FILE"
  exit 0
fi

SCRIPT_PARENT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$VALIDATE_SEEDS" -eq 1 ]; then
  lint_ledger "$SCRIPT_PARENT/assets/negative-ledger-seed.md"
  exit 0
fi

for p in "${POSITIONALS[@]:-}"; do
  case "$p" in
    perf|performance|conformance|surface|surface-parity)
      TERMS_RAW="${TERMS_RAW:+$TERMS_RAW,}$p"
      ;;
    *)
      if [ -z "$WORKSPACE" ] && { [ -d "$p" ] || [[ "$p" = */* ]]; }; then
        WORKSPACE="$p"
      else
        TERMS_RAW="${TERMS_RAW:+$TERMS_RAW,}$p"
      fi
      ;;
  esac
done

if [ -z "$WORKSPACE" ] && { [ -f "$SCRIPT_PARENT/AGENTS.md" ] || [ -d "$SCRIPT_PARENT/docs/progress" ]; }; then
  WORKSPACE="$SCRIPT_PARENT"
fi

[ -n "$WORKSPACE" ] || usage
mkdir -p "$WORKSPACE/reports"

if [ -n "$FILTER_RAW" ]; then
  FILTER_TERMS="${FILTER_RAW//|/,}"
  TERMS_RAW="${TERMS_RAW:+$TERMS_RAW,}$FILTER_TERMS"
fi
TERMS_RAW="${TERMS_RAW:-$DEFAULT_TERMS}"
IFS=',' read -ra TERMS <<<"$TERMS_RAW"

MD="$WORKSPACE/reports/ledger_mining_candidates.md"
JSON="$WORKSPACE/reports/ledger_mining_candidates.json"

LEDGER_FILES=()
for ledger in PERF_NEGATIVE_RESULTS.md CONFORMANCE_NEGATIVE_RESULTS.md SURFACE_DEFERRALS.md \
              docs/progress/perf-negative-results.md docs/progress/conformance-negative-results.md \
              docs/progress/surface-deferrals.md; do
  [ -f "$WORKSPACE/$ledger" ] && LEDGER_FILES+=("$WORKSPACE/$ledger")
  [ -n "$TARGET" ] && [ -f "$TARGET/$ledger" ] && LEDGER_FILES+=("$TARGET/$ledger")
done

TOTAL_LEDGER_HITS=0
declare -a LEDGER_LINES=()
for f in "${LEDGER_FILES[@]:-}"; do
  for t in "${TERMS[@]}"; do
    while IFS= read -r line; do
      LEDGER_LINES+=("$f|$line")
      TOTAL_LEDGER_HITS=$((TOTAL_LEDGER_HITS+1))
    done < <(grep -n -i -F -- "$t" "$f" 2>/dev/null || true)
  done
done

CASS_AVAILABLE=0
TOTAL_CASS_HITS=0
TOTAL_CASS_ERRORS=0
declare -a CASS_LINES=()
declare -a CASS_ERRORS=()
if command -v cass >/dev/null 2>&1; then
  CASS_AVAILABLE=1
  TIMEOUT_ARG="$(awk -v ms="$CASS_TIMEOUT_MS" 'BEGIN { printf "%.3fs", ms / 1000 }')"
  for t in "${TERMS[@]}"; do
    cass_args=(cass search --robot)
    if [ "$CASS_DAYS_SET" -eq 1 ] || { [ -z "$SINCE" ] && [ -z "$UNTIL" ]; }; then
      cass_args+=(--days "$CASS_DAYS")
    fi
    [ -n "$SINCE" ] && cass_args+=(--since "$SINCE")
    [ -n "$UNTIL" ] && cass_args+=(--until "$UNTIL")
    cass_args+=(--limit "$CASS_LIMIT" --mode lexical --timeout "$CASS_TIMEOUT_MS")
    cass_args+=(-- "$t")
    if command -v timeout >/dev/null 2>&1; then
      run_args=(timeout "$TIMEOUT_ARG" "${cass_args[@]}")
    else
      run_args=("${cass_args[@]}")
    fi
    if out="$("${run_args[@]}" 2>/dev/null)"; then
      if command -v jq >/dev/null 2>&1 && printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
        count="$(printf '%s' "$out" | jq -r 'if type == "object" then (.total_matches // ((.matches // .hits // .results // []) | length) // 0) else 0 end' 2>/dev/null || echo 0)"
        case "$count" in ''|*[!0-9]*) count=0;; esac
        if [ "$count" -gt 0 ]; then
          while IFS= read -r line; do
            [ -z "$line" ] && continue
            CASS_LINES+=("$line")
          done < <(printf '%s' "$out" | jq -c '.matches[]? // .hits[]? // .results[]?' 2>/dev/null | head -200)
          TOTAL_CASS_HITS=$((TOTAL_CASS_HITS+count))
        fi
      else
        while IFS= read -r line; do
          [ -z "$line" ] && continue
          CASS_LINES+=("$line")
          TOTAL_CASS_HITS=$((TOTAL_CASS_HITS+1))
        done < <(printf '%s\n' "$out" | head -200)
      fi
    else
      status=$?
      CASS_ERRORS+=("$t:$status")
      TOTAL_CASS_ERRORS=$((TOTAL_CASS_ERRORS+1))
    fi
  done
fi

BLOCKER=false
if [ "$TOTAL_LEDGER_HITS" -eq 0 ] && [ "$TOTAL_CASS_HITS" -eq 0 ]; then
  if [ "$CASS_AVAILABLE" -eq 0 ] || [ "$TOTAL_CASS_ERRORS" -gt 0 ]; then
    BLOCKER=true
  fi
fi

# ---- emit Markdown -----------------------------------------------------
{
  printf '# Ledger Mining — Candidate Blockers\n\n'
  printf '_generated_at_: `%s`\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '_terms_: `%s`\n' "$TERMS_RAW"
  printf '_cass_days_: `%d`\n\n' "$CASS_DAYS"
  [ -n "$SINCE" ] && printf '_since_: `%s`\n' "$SINCE"
  [ -n "$UNTIL" ] && printf '_until_: `%s`\n' "$UNTIL"
  if [ "$BLOCKER" = true ]; then
    printf '> **BLOCKER**: history mining did not produce usable negative evidence.\n'
    printf '> Per the AGENTS.md mandate, unavailable or timed-out ledger/cass mining counts as a blocker — record a patch-ready entry rather than skipping.\n\n'
  fi
  printf '## Negative-ledger hits (%d)\n\n' "$TOTAL_LEDGER_HITS"
  if [ "$TOTAL_LEDGER_HITS" -gt 0 ]; then
    for line in "${LEDGER_LINES[@]}"; do
      f="${line%%|*}"; rest="${line#*|}"
      printf -- '- `%s` — %s\n' "$f" "$rest"
    done
  else
    printf '_(no hits)_\n'
  fi
  printf '\n## cass session-history hits (%d)\n\n' "$TOTAL_CASS_HITS"
  if [ "$CASS_AVAILABLE" -eq 0 ]; then
    printf '_(cass not on PATH)_\n'
  elif [ "$TOTAL_CASS_HITS" -gt 0 ]; then
    for line in "${CASS_LINES[@]}"; do
      printf -- '- %s\n' "$line"
    done
  else
    printf '_(no hits)_\n'
  fi
  if [ "$TOTAL_CASS_ERRORS" -gt 0 ]; then
    printf '\n## cass search errors (%d)\n\n' "$TOTAL_CASS_ERRORS"
    for err in "${CASS_ERRORS[@]}"; do
      printf -- '- `%s`\n' "$err"
    done
  fi
  printf '\n---\n\n'
  printf 'Before starting this perf work, review every line above. If a hit\n'
  printf 'matches your candidate, the negative ledger already rejected it — read the\n'
  printf 'retry-condition predicate and confirm a satisfying condition has changed.\n'
} > "$MD"

# ---- emit JSON ---------------------------------------------------------
{
  printf '{\n'
  printf '  "schema_version": "gauntlet.ledger_mining.v1",\n'
  printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "ledger_hit_count": %d,\n' "$TOTAL_LEDGER_HITS"
  printf '  "cass_hit_count": %d,\n' "$TOTAL_CASS_HITS"
  printf '  "cass_error_count": %d,\n' "$TOTAL_CASS_ERRORS"
  printf '  "cass_available": %s,\n' "$([ $CASS_AVAILABLE -eq 1 ] && echo true || echo false)"
  printf '  "cass_days_filter_applied": %s,\n' "$([ "$CASS_DAYS_SET" -eq 1 ] || { [ -z "$SINCE" ] && [ -z "$UNTIL" ]; } && echo true || echo false)"
  printf '  "cass_days": %d,\n' "$CASS_DAYS"
  printf '  "cass_limit": %d,\n' "$CASS_LIMIT"
  printf '  "cass_timeout_ms": %d,\n' "$CASS_TIMEOUT_MS"
  printf '  "since": "%s",\n' "$SINCE"
  printf '  "until": "%s",\n' "$UNTIL"
  printf '  "blocker": %s,\n' "$BLOCKER"
  printf '  "markdown_report": "%s"\n' "$MD"
  printf '}\n'
} > "$JSON"

echo "Wrote $MD"
echo "Wrote $JSON"

if [ "$BLOCKER" = true ]; then
  exit 2
fi
exit 0
