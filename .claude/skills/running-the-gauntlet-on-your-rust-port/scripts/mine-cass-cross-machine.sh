#!/usr/bin/env bash
# mine-cass-cross-machine.sh — Invokes cass on local + css + csd + ts1 + ts2
# (per the cass skill's Cross-Machine Search section). Uses:
#   timeout 30s cass search "<failure-term>" --robot --mode lexical --days 60 --limit 50 --timeout 30000
# Aggregates session-history hits across machines.
#
# USAGE:
#   mine-cass-cross-machine.sh <workspace>
#                              [--hosts local,css,csd,ts1,ts2]
#                              [--terms <comma-list>]
#                              [--term <single-term>] [--window 60d]
#                              [--days 60]
#                              [--limit 50]
#                              [--timeout-ms 30000]
#                              [--since <cass-date>] [--until <cass-date>]
#
# OUTPUT FILES:
#   <workspace>/reports/cass_cross_machine/<host>.json
#   <workspace>/reports/cass_cross_machine/_summary.json
#
# EXIT CODES:
#   0 — at least one host responded
#   1 — every host failed (record blocker per mandate)
#   3 — usage error

set -euo pipefail

usage() { sed -n '2,16p' "$0"; exit "${1:-3}"; }

WORKSPACE=""
HOSTS="local,css,csd,ts1,ts2"
TERMS="rejected,reverted,abandoned,slower,regressed,within noise,no improvement,rolled back,keep gate,micro-lever"
DAYS=60
DAYS_SET=0
LIMIT=50
TIMEOUT_MS=30000
SINCE=""
UNTIL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --hosts) HOSTS="$2"; shift 2;;
    --terms) TERMS="$2"; shift 2;;
    --term)  TERMS="$2"; shift 2;;
    --days)  DAYS="$2"; DAYS_SET=1; shift 2;;
    --window) DAYS="${2%d}"; DAYS_SET=1; shift 2;;
    --limit) LIMIT="$2"; shift 2;;
    --timeout-ms) TIMEOUT_MS="$2"; shift 2;;
    --since) SINCE="$2"; shift 2;;
    --until) UNTIL="$2"; shift 2;;
    -h|--help) usage 0;;
    *)
      if [ -z "$WORKSPACE" ]; then WORKSPACE="$1"
      else echo "Unexpected arg: $1" >&2; usage
      fi
      shift;;
  esac
done

SCRIPT_PARENT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$WORKSPACE" ] && { [ -f "$SCRIPT_PARENT/AGENTS.md" ] || [ -d "$SCRIPT_PARENT/docs/progress" ]; }; then
  WORKSPACE="$SCRIPT_PARENT"
fi

[ -n "$WORKSPACE" ] || usage
OUT="$WORKSPACE/reports/cass_cross_machine"
mkdir -p "$OUT"

IFS=',' read -ra HOST_LIST <<<"$HOSTS"
IFS=',' read -ra TERM_LIST <<<"$TERMS"
TIMEOUT_ARG="$(awk -v ms="$TIMEOUT_MS" 'BEGIN { printf "%.3fs", ms / 1000 }')"

if ! command -v cass >/dev/null 2>&1; then
  echo "WARN: cass not on PATH; cannot mine cross-machine." >&2
fi
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not on PATH; required to parse cass JSON" >&2; exit 3; }

ANY_OK=0
SUMMARY_ITEMS=()

for host in "${HOST_LIST[@]}"; do
  host="$(echo "$host" | xargs)"
  HOST_JSON="$OUT/${host}.json"
  HOST_LOG="$OUT/${host}.log"
  : > "$HOST_LOG"

  hits=0
  results=()

  for term in "${TERM_LIST[@]}"; do
    term="$(echo "$term" | xargs)"
    if [ "$host" = "local" ]; then
      cmd=(cass search --robot)
      if [ "$DAYS_SET" -eq 1 ] || { [ -z "$SINCE" ] && [ -z "$UNTIL" ]; }; then
        cmd+=(--days "$DAYS")
      fi
      [ -n "$SINCE" ] && cmd+=(--since "$SINCE")
      [ -n "$UNTIL" ] && cmd+=(--until "$UNTIL")
      cmd+=(--limit "$LIMIT" --mode lexical --timeout "$TIMEOUT_MS")
      cmd+=(-- "$term")
    else
      remote_term="$(printf '%q' "$term")"
      remote_limit="$(printf '%q' "$LIMIT")"
      remote_timeout="$(printf '%q' "$TIMEOUT_MS")"
      remote_cmd="cass search --robot"
      if [ "$DAYS_SET" -eq 1 ] || { [ -z "$SINCE" ] && [ -z "$UNTIL" ]; }; then
        remote_days="$(printf '%q' "$DAYS")"
        remote_cmd="$remote_cmd --days $remote_days"
      fi
      if [ -n "$SINCE" ]; then
        remote_since="$(printf '%q' "$SINCE")"
        remote_cmd="$remote_cmd --since $remote_since"
      fi
      if [ -n "$UNTIL" ]; then
        remote_until="$(printf '%q' "$UNTIL")"
        remote_cmd="$remote_cmd --until $remote_until"
      fi
      remote_cmd="$remote_cmd --limit $remote_limit --mode lexical --timeout $remote_timeout -- $remote_term"
      cmd=(ssh "$host" "$remote_cmd")
    fi
    if command -v timeout >/dev/null 2>&1; then
      run_cmd=(timeout "$TIMEOUT_ARG" "${cmd[@]}")
    else
      run_cmd=("${cmd[@]}")
    fi
    if out="$("${run_cmd[@]}" 2>>"$HOST_LOG")"; then
      count="$(printf '%s' "$out" | jq -r 'if type == "object" then (.total_matches // ((.matches // .hits // .results // []) | length) // 0) else 0 end' 2>/dev/null || echo 0)"
      case "$count" in ''|*[!0-9]*) count=0;; esac
      hits=$((hits+count))
      results+=("$term:$count")
      ANY_OK=1
    else
      results+=("$term:ERROR")
    fi
  done

  {
    printf '{\n'
    printf '  "schema_version": "gauntlet.cass_cross_machine_host.v1",\n'
    printf '  "host": "%s",\n' "$host"
    printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "days": %d,\n' "$DAYS"
    printf '  "days_filter_applied": %s,\n' "$([ "$DAYS_SET" -eq 1 ] || { [ -z "$SINCE" ] && [ -z "$UNTIL" ]; } && echo true || echo false)"
    printf '  "limit": %d,\n' "$LIMIT"
    printf '  "timeout_ms": %d,\n' "$TIMEOUT_MS"
    printf '  "since": "%s",\n' "$SINCE"
    printf '  "until": "%s",\n' "$UNTIL"
    printf '  "total_hits": %d,\n' "$hits"
    printf '  "per_term": [\n'
    n="${#results[@]}"
    for i in "${!results[@]}"; do
      sep=","; [ $((i+1)) -eq "$n" ] && sep=""
      k="${results[$i]%%:*}"; v="${results[$i]##*:}"
      k_esc="$(printf '%s' "$k" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      printf '    {"term": "%s", "result": "%s"}%s\n' "$k_esc" "$v" "$sep"
    done
    printf '  ]\n'
    printf '}\n'
  } > "$HOST_JSON"
  SUMMARY_ITEMS+=("$host:$hits")
  echo "[$host] hits=$hits (see $HOST_JSON)"
done

SUMMARY="$OUT/_summary.json"
{
  printf '{\n'
  printf '  "schema_version": "gauntlet.cass_cross_machine_summary.v1",\n'
  printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "hosts": [\n'
  n="${#SUMMARY_ITEMS[@]}"
  for i in "${!SUMMARY_ITEMS[@]}"; do
    sep=","; [ $((i+1)) -eq "$n" ] && sep=""
    h="${SUMMARY_ITEMS[$i]%%:*}"; v="${SUMMARY_ITEMS[$i]##*:}"
    printf '    {"host": "%s", "total_hits": %s}%s\n' "$h" "$v" "$sep"
  done
  printf '  ]\n'
  printf '}\n'
} > "$SUMMARY"

echo "Wrote $SUMMARY"
[ "$ANY_OK" -eq 1 ] || exit 1
