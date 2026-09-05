#!/usr/bin/env bash
# compute-mismatch-signature.sh — hash a minimal divergent reproducer into a
# stable MismatchSignature for dedup across runs / agents / machines.
#
# USAGE:
#   compute-mismatch-signature.sh <classification> <subsystem> <schema-file> <workload-file> [<first-diverging-stmt-file>]
#
# Mirrors `crates/fsqlite-harness/src/mismatch_minimizer.rs::MismatchSignature::compute`
# (see references/patterns/45-MISMATCH-MINIMIZER.md).
#
# OUTPUTS JSON to stdout:
#   { "hash": "<16-hex-chars>", "classification": "...", "subsystem": "...", ... }

set -euo pipefail

usage() { sed -n '2,10p' "$0"; exit "${1:-2}"; }

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage 0
fi

[ $# -lt 4 ] && usage

CLASSIFICATION="$1"
SUBSYSTEM="$2"
SCHEMA_FILE="$3"
WORKLOAD_FILE="$4"
FIRST_DIVERGING_STMT_FILE="${5:-}"

# Validate classification (per references/patterns/40-METAMORPHIC-TRANSFORMS.md).
case "$CLASSIFICATION" in
  TrueDivergence|OrderDependentDifference|TypeAffinityDifference|NullHandlingDifference|FloatingPointDifference|FalsePositive) ;;
  *)
    echo "ERROR: classification must be one of TrueDivergence | OrderDependentDifference | TypeAffinityDifference | NullHandlingDifference | FloatingPointDifference | FalsePositive" >&2
    exit 2;;
esac

# Validate subsystem.
case "$SUBSYSTEM" in
  Parser|Resolver|Planner|Vdbe|Storage|Wal|Mvcc|Functions|Extension|TypeSystem|Pragma|Unknown) ;;
  *)
    echo "ERROR: subsystem must be one of Parser | Resolver | Planner | Vdbe | Storage | Wal | Mvcc | Functions | Extension | TypeSystem | Pragma | Unknown" >&2
    exit 2;;
esac

# Build the canonical content (mirrors the Rust impl):
#   sig-v1:<classification>:<subsystem>:<schema>:<workload>
CANONICAL=$(printf 'sig-v1:%s:%s:%s' "$CLASSIFICATION" "$SUBSYSTEM" \
            "$(cat "$SCHEMA_FILE")")
CANONICAL="${CANONICAL}:$(cat "$WORKLOAD_FILE")"

# SHA-256 truncated to 16 hex chars (matches Rust impl).
HASH=$(printf '%s' "$CANONICAL" | sha256sum | cut -c1-16)

# First diverging stmt (for human readability).
FIRST_STMT=""
if [ -n "$FIRST_DIVERGING_STMT_FILE" ] && [ -f "$FIRST_DIVERGING_STMT_FILE" ]; then
  FIRST_STMT=$(cat "$FIRST_DIVERGING_STMT_FILE" | head -c 1024)
fi

# Count statements robustly: wc -l counts newlines; if file lacks trailing newline,
# the last statement isn't counted. Add 1 if needed; strip whitespace from wc output.
MINIMAL_COUNT=$(awk 'END { print NR }' "$WORKLOAD_FILE")

# JSON-escape first_stmt via python's json.dumps (strip outer quotes).
FIRST_STMT_ESC=$(printf '%s' "$FIRST_STMT" | python3 -c 'import sys, json; sys.stdout.write(json.dumps(sys.stdin.read())[1:-1])')

cat <<JSON
{
  "schema_version": "gauntlet.mismatch_signature.v1",
  "hash": "$HASH",
  "classification": "$CLASSIFICATION",
  "subsystem": "$SUBSYSTEM",
  "minimal_statement_count": $MINIMAL_COUNT,
  "first_diverging_sql": "$FIRST_STMT_ESC"
}
JSON
