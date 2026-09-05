#!/usr/bin/env bash
# bead-graph-validator.sh — Runs `br dep cycles` + `bv --robot-insights | jq
# '(.Cycles // [])'`. Asserts every remediation bead has a test-bead AND a benchmark-
# bead AND a documentation-bead dependency. Exits non-zero on any failure
# with the specific bead-ID and missing dependency.
#
# USAGE:
#   bead-graph-validator.sh <workspace_or_repo_with_beads>
#                           [--output-root <workspace_for_report>]
#                           [--remediation-prefix bd-rem-]
#                           [--remediation-label kind:remediation]
#                           [-v|-vv|-vvv]
#
# OUTPUT FILE: <output-root-or-bead-root>/reports/bead_graph_validation.json
#
# EXIT CODES:
#   0 — graph clean: zero cycles, every remediation bead has T+B+D deps
#   1 — at least one validation failure
#   2 — br or bv missing
#   3 — usage error
#
# IDEMPOTENT.

set -euo pipefail

usage() { sed -n '2,22p' "$0"; exit "${1:-3}"; }

WORKSPACE=""
OUTPUT_ROOT=""
PREFIX="bd-rem-"
LABEL="kind:remediation"
VERBOSE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --output-root)       OUTPUT_ROOT="$2"; shift 2;;
    --remediation-prefix) PREFIX="$2"; shift 2;;
    --remediation-label) LABEL="$2"; shift 2;;
    -v|-vv|-vvv) VERBOSE=1; shift;;
    -h|--help) usage 0;;
    *)
      if [ -z "$WORKSPACE" ]; then WORKSPACE="$1"
      else echo "Unexpected arg: $1" >&2; usage
      fi
      shift;;
  esac
done

[ -n "$WORKSPACE" ] || usage
[ -n "$OUTPUT_ROOT" ] || OUTPUT_ROOT="$WORKSPACE"
mkdir -p "$OUTPUT_ROOT/reports"
OUT="$OUTPUT_ROOT/reports/bead_graph_validation.json"

command -v br >/dev/null 2>&1 || { echo "ERROR: br not on PATH" >&2; exit 2; }
command -v bv >/dev/null 2>&1 || { echo "ERROR: bv not on PATH" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not on PATH" >&2; exit 2; }

declare -a TOOL_FAILURES=()

CYCLES_OUT=""
CYCLES_COUNT=0
if ! CYCLES_OUT="$(cd "$WORKSPACE" && RUST_LOG=error br dep cycles --json 2>&1)"; then
  TOOL_FAILURES+=("br dep cycles --json failed")
elif ! CYCLES_COUNT="$(printf '%s\n' "$CYCLES_OUT" | jq -r '(.cycles // []) | length' 2>/dev/null)"; then
  TOOL_FAILURES+=("br dep cycles --json emitted non-json")
  CYCLES_COUNT=0
fi

BV_OUT=""
BV_CYCLES=0
if ! BV_OUT="$(cd "$WORKSPACE" && RUST_LOG=error bv --robot-insights 2>&1)"; then
  TOOL_FAILURES+=("bv --robot-insights failed")
elif ! BV_CYCLES="$(printf '%s' "$BV_OUT" | jq -r '(.Cycles // []) | length' 2>/dev/null)"; then
  TOOL_FAILURES+=("bv --robot-insights emitted non-json")
  BV_CYCLES=0
fi

# List remediation beads by the Phase-13 `kind:remediation` label and by the
# historical generated-ID prefix used by older generated graphs.
REMED_LIST="$(
  {
    cd "$WORKSPACE" && RUST_LOG=error br list --label "$LABEL" --json --limit 0 2>/dev/null \
      | jq -r '(.issues // .)[]?.id' 2>/dev/null || true
    cd "$WORKSPACE" && RUST_LOG=error br list --json --limit 0 2>/dev/null \
      | jq -r --arg p "$PREFIX" '(.issues // .)[]? | select(.id|startswith($p)) | .id' 2>/dev/null || true
  } | sort -u
)"

declare -a FAILURES=()

dep_search_text() {
  local dep="$1"
  local meta
  meta="$(cd "$WORKSPACE" && RUST_LOG=error br show --json "$dep" 2>/dev/null \
    | jq -r '[.id // "", .title // "", .type // "", ((.labels // []) | join(" "))] | join(" ")' 2>/dev/null || true)"
  printf '%s %s\n' "$dep" "$meta" | tr '[:upper:]' '[:lower:]'
}

while IFS= read -r bid; do
  [ -z "$bid" ] && continue
  deps="$(cd "$WORKSPACE" && RUST_LOG=error br show --json "$bid" 2>/dev/null | jq -r '.dependencies[]?.id // .dependencies[]? // empty' 2>/dev/null || true)"
  has_test=0; has_bench=0; has_doc=0
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    dep_text="$(dep_search_text "$dep")"
    [[ "$dep_text" =~ (test|oracle|metamorphic|sanitizer|fuzz|property|golden) ]] && has_test=1
    [[ "$dep_text" =~ (bench|benchmark|criterion|hyperfine|comprehensive-bench) ]] && has_bench=1
    [[ "$dep_text" =~ (doc|docs|documentation|safety|contract|agents\.md) ]] && has_doc=1
  done <<<"$deps"
  missing=""
  [ "$has_test" -eq 0 ]  && missing="${missing}test "
  [ "$has_bench" -eq 0 ] && missing="${missing}bench "
  [ "$has_doc" -eq 0 ]   && missing="${missing}doc"
  if [ -n "$missing" ]; then
    FAILURES+=("$bid|$missing")
  fi
done <<<"$REMED_LIST"

VALID=0
[ "$CYCLES_COUNT" -gt 0 ] && VALID=1
[ "$BV_CYCLES" != "0" ] && [ -n "$BV_CYCLES" ] && VALID=1
[ "${#FAILURES[@]}" -gt 0 ] && VALID=1
[ "${#TOOL_FAILURES[@]}" -gt 0 ] && VALID=1

{
  printf '{\n'
  printf '  "schema_version": "gauntlet.bead_graph_validation.v1",\n'
  printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "br_cycle_count": %d,\n' "$CYCLES_COUNT"
  printf '  "bv_cycle_count": %s,\n' "${BV_CYCLES:-0}"
  printf '  "tool_failures": [\n'
  n="${#TOOL_FAILURES[@]}"
  for i in "${!TOOL_FAILURES[@]}"; do
    sep=","; [ $((i+1)) -eq "$n" ] && sep=""
    printf '    "%s"%s\n' "${TOOL_FAILURES[$i]}" "$sep"
  done
  printf '  ],\n'
  printf '  "missing_dependency_failures": [\n'
  n="${#FAILURES[@]}"
  for i in "${!FAILURES[@]}"; do
    sep=","; [ $((i+1)) -eq "$n" ] && sep=""
    bid="${FAILURES[$i]%%|*}"; miss="${FAILURES[$i]##*|}"
    printf '    {"bead_id":"%s","missing_dependency_kinds":"%s"}%s\n' "$bid" "$miss" "$sep"
  done
  printf '  ]\n'
  printf '}\n'
} > "$OUT"

echo "Wrote $OUT"
echo "br cycles=$CYCLES_COUNT bv cycles=$BV_CYCLES failures=${#FAILURES[@]} tool_failures=${#TOOL_FAILURES[@]}"
if [ "$VERBOSE" -eq 1 ]; then
  printf '%s\n' "$CYCLES_OUT" >&2
  printf '%s\n' "$BV_OUT" >&2
fi
[ "$VALID" -eq 0 ] || exit 1
