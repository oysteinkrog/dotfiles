#!/usr/bin/env bash
# diff-audit-vs-baseline.sh — produce a diff report between two audits.
# Usage: ./diff-audit-vs-baseline.sh <audit-A> <audit-B> <delta-dir> [--label-a LABEL] [--label-b LABEL]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_A=""
AUDIT_B=""
DELTA_DIR=""
LABEL_A="version-A"
LABEL_B="version-B"

usage() {
  echo "usage: diff-audit-vs-baseline.sh <audit-A> <audit-B> <delta-dir> [--label-a LABEL] [--label-b LABEL]" >&2
}

die_usage() {
  echo "error: $*" >&2
  usage
  exit 2
}

require_flag_value() {
  local flag="$1"
  local value="${2:-}"
  if [ -z "$value" ] || [[ "$value" == -* ]]; then
    die_usage "$flag requires a value"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label-a)
      require_flag_value "$1" "${2:-}"
      LABEL_A="$2"
      shift 2
      ;;
    --label-b)
      require_flag_value "$1" "${2:-}"
      LABEL_B="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die_usage "unknown flag: $1"
      ;;
    *)
      if [ -z "$AUDIT_A" ]; then AUDIT_A="$1"
      elif [ -z "$AUDIT_B" ]; then AUDIT_B="$1"
      elif [ -z "$DELTA_DIR" ]; then DELTA_DIR="$1"
      else die_usage "unexpected extra argument: $1"
      fi
      shift
      ;;
  esac
done

if [ -z "$AUDIT_A" ] || [ -z "$AUDIT_B" ] || [ -z "$DELTA_DIR" ]; then
  usage
  exit 2
fi

AUDIT_A=$(audit_realpath "$AUDIT_A")
AUDIT_B=$(audit_realpath "$AUDIT_B")
PROJECT_A=$(audit_project_root_from_dir "$AUDIT_A")
PROJECT_B=$(audit_project_root_from_dir "$AUDIT_B")
AUDIT_A=$(audit_require_under_project "$AUDIT_A" "$PROJECT_A")
AUDIT_B=$(audit_require_under_project "$AUDIT_B" "$PROJECT_B")
DELTA_DIR=$(audit_require_under_project "$DELTA_DIR" "$PROJECT_B")
case "$DELTA_DIR/" in
  "$AUDIT_B"/*) ;;
  *)
    echo "error: delta dir must be inside the current audit dir" >&2
    echo "       audit B:   $AUDIT_B" >&2
    echo "       delta dir: $DELTA_DIR" >&2
    exit 2
    ;;
esac

mkdir -p "$DELTA_DIR"

INV_A="$AUDIT_A/unsafe-inventory.jsonl"
INV_B="$AUDIT_B/unsafe-inventory.jsonl"
[ -f "$INV_A" ] || { echo "missing $INV_A"; exit 1; }
[ -f "$INV_B" ] || { echo "missing $INV_B"; exit 1; }

# Site-level diff: pair by (crate, file, line_start, kind).
# IMPORTANT: each JSONL file has ONE object per line; `jq -s` over two JSONL files
# would slurp objects from BOTH files into a single array (losing the file
# boundary). Use `--slurpfile` so each file becomes its own array.
jq -n \
  --slurpfile a "$INV_A" \
  --slurpfile b "$INV_B" \
  '
    def site_key(s):
      "\(s.crate)/\(s.file)#L\(s.line_start)/\(s.kind)";

    ($a | map({key: site_key(.), value: .}) | from_entries) as $A |
    ($b | map({key: site_key(.), value: .}) | from_entries) as $B |

    {
      added:    [$B | to_entries[] | select(.key as $k | $A | has($k) | not) | .value],
      removed:  [$A | to_entries[] | select(.key as $k | $B | has($k) | not) | .value],
      modified: [$B | to_entries[] | select(.key as $k | ($A | has($k))
                                            and ($A[$k].source_excerpt != .value.source_excerpt))
                                    | .value]
    }
  ' > "$DELTA_DIR/site-diffs.json"

ADDED_N=$(jq '.added | length' "$DELTA_DIR/site-diffs.json")
REMOVED_N=$(jq '.removed | length' "$DELTA_DIR/site-diffs.json")
MODIFIED_N=$(jq '.modified | length' "$DELTA_DIR/site-diffs.json")

# Geiger delta. New audits store per-crate `<crate>__geiger.json`; older audits
# may have a single `cargo-geiger.json`.
sum_geiger_file() {
  jq '[.packages[]?.package.metrics.counters | objects | .[] | numbers] | add // 0' "$1" 2>/dev/null || echo 0
}

sum_geiger_audit() {
  local dir="$1"
  local single="$dir/phase1/cargo-geiger.json"
  local sum=0 part
  if [ -f "$single" ]; then
    sum_geiger_file "$single"
    return
  fi
  for f in "$dir"/phase1/*__geiger.json; do
    [ -f "$f" ] || continue
    part=$(sum_geiger_file "$f")
    case "$part" in ''|null) part=0 ;; esac
    sum=$((sum + part))
  done
  echo "$sum"
}

A_GEIGER=$(sum_geiger_audit "$AUDIT_A")
B_GEIGER=$(sum_geiger_audit "$AUDIT_B")
case "$A_GEIGER" in ''|null) A_GEIGER=0 ;; esac
case "$B_GEIGER" in ''|null) B_GEIGER=0 ;; esac
GEIGER_DELTA=$((B_GEIGER - A_GEIGER))

# Classification diff
CLASS_A_DIR="$AUDIT_A/audit/classification"
CLASS_B_DIR="$AUDIT_B/audit/classification"

count_bucket_in_dir() {
  local dir="$1"; local bucket="$2"
  if [ -d "$dir" ]; then
    { grep -lE "(^#[[:space:]]+site-[0-9]+[[:space:]]+—[[:space:]]+\($bucket\)|\*\*Bucket\.\*\*[[:space:]]+\`?\($bucket\))" "$dir"/*.md 2>/dev/null || true; } | wc -l | tr -d ' '
  else
    echo 0
  fi
}

A_CLASS_A=$(count_bucket_in_dir "$CLASS_A_DIR" "A")
A_CLASS_B=$(count_bucket_in_dir "$CLASS_A_DIR" "B")
A_CLASS_C=$(count_bucket_in_dir "$CLASS_A_DIR" "C")
B_CLASS_A=$(count_bucket_in_dir "$CLASS_B_DIR" "A")
B_CLASS_B=$(count_bucket_in_dir "$CLASS_B_DIR" "B")
B_CLASS_C=$(count_bucket_in_dir "$CLASS_B_DIR" "C")

A_TOTAL=$(wc -l < "$INV_A" | tr -d ' ')
B_TOTAL=$(wc -l < "$INV_B" | tr -d ' ')

# Net recommendation heuristic
RECOMMENDATION="ADOPT-WITH-MITIGATION"
if [ "$ADDED_N" -eq 0 ] && [ "$GEIGER_DELTA" -le 0 ] && [ "$B_CLASS_A" -le "$A_CLASS_A" ]; then
  RECOMMENDATION="ADOPT"
elif [ "$ADDED_N" -gt 5 ] || [ "$GEIGER_DELTA" -gt 10 ] || [ "$B_CLASS_A" -gt "$((A_CLASS_A + 5))" ]; then
  RECOMMENDATION="DON'T-ADOPT (significant soundness regression)"
fi

# Write the report
OUT="$DELTA_DIR/diff-report.md"
cat > "$OUT" <<EOF
# Audit Diff Report

- **Version A.** $LABEL_A (audit dir: $AUDIT_A)
- **Version B.** $LABEL_B (audit dir: $AUDIT_B)
- **Generated.** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Summary

| Metric | A | B | Delta |
|--------|---|---|-------|
| Total unsafe sites | $A_TOTAL | $B_TOTAL | $((B_TOTAL - A_TOTAL)) |
| (A) STRICTLY_UNAVOIDABLE | $A_CLASS_A | $B_CLASS_A | $((B_CLASS_A - A_CLASS_A)) |
| (B) PERF_ONLY | $A_CLASS_B | $B_CLASS_B | $((B_CLASS_B - A_CLASS_B)) |
| (C) REFACTORABLE | $A_CLASS_C | $B_CLASS_C | $((B_CLASS_C - A_CLASS_C)) |
| Geiger count | $A_GEIGER | $B_GEIGER | $GEIGER_DELTA |
| Sites added (in B not A) | — | — | $ADDED_N |
| Sites removed (in A not B) | — | — | $REMOVED_N |
| Sites modified (different source) | — | — | $MODIFIED_N |

## Net recommendation

**$RECOMMENDATION**

EOF

if [ "$ADDED_N" -gt 0 ]; then
  {
    echo "## Sites added in B (top 20)"
    echo ""
    echo "| Site | File | Kind | Public-API |"
    echo "|------|------|------|------------|"
    jq -r '.added[:20] | .[] | "| \(.id // "?") | \(.file):\(.line_start) | \(.kind) | \(.public_api_exposed) |"' \
      "$DELTA_DIR/site-diffs.json"
    echo ""
  } >> "$OUT"
fi

if [ "$REMOVED_N" -gt 0 ]; then
  {
    echo "## Sites removed in B (top 20; refactored away)"
    echo ""
    echo "| Site | File | Kind | Public-API |"
    echo "|------|------|------|------------|"
    jq -r '.removed[:20] | .[] | "| \(.id // "?") | \(.file):\(.line_start) | \(.kind) | \(.public_api_exposed) |"' \
      "$DELTA_DIR/site-diffs.json"
    echo ""
  } >> "$OUT"
fi

if [ "$MODIFIED_N" -gt 0 ]; then
  {
    echo "## Sites modified (top 20; source changed but site survives)"
    echo ""
    echo "| Site | File | Kind |"
    echo "|------|------|------|"
    jq -r '.modified[:20] | .[] | "| \(.id // "?") | \(.file):\(.line_start) | \(.kind) |"' \
      "$DELTA_DIR/site-diffs.json"
    echo ""
  } >> "$OUT"
fi

cat >> "$OUT" <<EOF

## Action items

1. Investigate **$ADDED_N** new unsafe sites if adopting B.
2. Verify any **$MODIFIED_N** modified sites' SAFETY comments are still accurate.
3. Geiger delta is **$GEIGER_DELTA** (negative = improvement).
4. After adopting B, re-baseline continuous mode.

## Artifacts
- Per-site diff JSON: $DELTA_DIR/site-diffs.json
- Raw inventory A: $INV_A
- Raw inventory B: $INV_B
EOF

echo
echo "Diff report written to $OUT"
echo "Summary: A=$A_TOTAL sites, B=$B_TOTAL sites; +$ADDED_N -$REMOVED_N ~$MODIFIED_N; geiger delta=$GEIGER_DELTA"
echo "Recommendation: $RECOMMENDATION"
