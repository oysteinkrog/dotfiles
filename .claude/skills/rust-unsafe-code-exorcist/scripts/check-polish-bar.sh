#!/usr/bin/env bash
# check-polish-bar.sh — walk every site classification + plan and verify required dimensions.
# Usage: ./check-polish-bar.sh <audit-dir>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: check-polish-bar.sh <audit-dir>}"
AUDIT_DIR=$(audit_realpath "$AUDIT_DIR")
PROJECT_ROOT=$(audit_project_root_from_dir "$AUDIT_DIR")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT_ROOT")

CLASS_DIR="$AUDIT_DIR/audit/classification"
PLAN_DIR="$AUDIT_DIR/audit/plans"
SITES_DIR="$AUDIT_DIR/audit/sites"
OUT="$AUDIT_DIR/audit/phase5/polish-bar-check.md"
mkdir -p "$(dirname "$OUT")"

if [ ! -d "$CLASS_DIR" ]; then
  echo "error: $CLASS_DIR not found. Run Phase 4 first." >&2
  exit 1
fi

PASS=0
FAIL=0
declare -a FAILURES=()

{
  echo "# Polish bar check"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Per [POLISH-BAR.md](../../references/methodology/POLISH-BAR.md)."
  echo
  echo "## Per-site results"
  echo
  echo "| Site | Bucket | Missing dimensions |"
  echo "|------|--------|--------------------|"
} > "$OUT"

for class_file in "$CLASS_DIR"/site-*.md; do
  [ -f "$class_file" ] || continue
  site_id=$(basename "$class_file" .md)

  content=$(cat "$class_file")
  bucket=$(printf '%s' "$content" | grep -oE '\*\*Bucket\.\*\*\s+`?\([ABC]\)' | head -1 \
            | grep -oE '\([ABC]\)' | tr -d '()' || echo "?")

  missing=()

  # Dim 1: invariant named — every site (look in site write-up)
  site_writeup=$(find "$SITES_DIR" -name "*.md" -exec grep -l "$site_id" {} \; 2>/dev/null | head -1)
  if [ -n "$site_writeup" ]; then
    if ! grep -qE 'sound IFF|Invariants?' "$site_writeup"; then
      missing+=("invariant-named")
    fi
  else
    missing+=("write-up-missing")
  fi

  # Per-bucket dims
  case "$bucket" in
    A)
      # Dim 2: falsifiable justification (3 alternatives + steel-man)
      if ! grep -qE '1\.\s+Alternative' "$class_file" \
         || ! grep -qE '2\.\s+Alternative' "$class_file" \
         || ! grep -qE '3\.\s+Alternative' "$class_file"; then
        missing+=("(A)-3-failed-alternatives")
      fi
      if ! grep -qiE 'attack surface|steel.?man' "$class_file"; then
        missing+=("(A)-steel-man")
      fi
      # Soundness-surface marker (dim 6)
      if grep -qE 'Public-API exposure.*yes' "$site_writeup" 2>/dev/null; then
        if ! grep -qE '#\s*Safety|hardened SAFETY' "$class_file" 2>/dev/null \
           && ! find "$PLAN_DIR" -name "$site_id.md" -exec grep -qE '#\s*Safety' {} \; 2>/dev/null; then
          missing+=("(A)-hardened-SAFETY-comment")
        fi
      fi
      ;;
    B)
      # Dim 3: perf numbers
      plan="$PLAN_DIR/$site_id.md"
      if [ -f "$plan" ]; then
        if ! grep -qE 'criterion|hyperfine|flamegraph' "$plan"; then
          missing+=("(B)-perf-numbers")
        fi
        if ! grep -qiE 'budget' "$plan"; then
          missing+=("(B)-budget-check")
        fi
      else
        missing+=("plan-missing")
      fi
      ;;
    C)
      # Dim 4: equivalence test
      plan="$PLAN_DIR/$site_id.md"
      if [ -f "$plan" ]; then
        if ! grep -qiE 'proptest|quickcheck|equivalence' "$plan"; then
          missing+=("(C)-equivalence-test")
        fi
        if ! grep -qE 'miri' "$plan"; then
          missing+=("(C)-miri-invocation")
        fi
      else
        missing+=("plan-missing")
      fi
      ;;
    *)
      missing+=("bucket-not-set")
      ;;
  esac

  # Macro-origin requires expand reference (dim 5)
  if [ -n "$site_writeup" ] && grep -qE 'Macro origin.*yes' "$site_writeup" 2>/dev/null; then
    if ! grep -qE 'phase1/.*__expand\.rs' "$site_writeup"; then
      missing+=("macro-expanded-view")
    fi
  fi

  if [ ${#missing[@]} -eq 0 ]; then
    PASS=$((PASS+1))
    echo "| $site_id | $bucket | (none) ✓ |" >> "$OUT"
  else
    FAIL=$((FAIL+1))
    FAILURES+=("$site_id: ${missing[*]}")
    miss_str=$(IFS=, ; echo "${missing[*]}")
    echo "| $site_id | $bucket | $miss_str |" >> "$OUT"
  fi
done

{
  echo
  echo "## Summary"
  echo
  echo "- **Pass:** $PASS"
  echo "- **Fail:** $FAIL"
  echo
  if [ "$FAIL" -gt 0 ]; then
    echo "## Action items"
    echo
    echo "Sites failing the polish bar do NOT exit Phase 5 / Phase 6. Re-spawn the relevant"
    echo "subagent to address the missing dimension(s):"
    echo
    for f in "${FAILURES[@]}"; do echo "- $f"; done
  else
    echo "**All sites pass the polish bar.** Ready for Phase 6 (adversarial reclassification)"
    echo "or Phase 7 (fresh-eyes) per the orchestrator's plan."
  fi
} >> "$OUT"

echo "Wrote $OUT"
echo "Pass: $PASS / Fail: $FAIL"
[ "$FAIL" -eq 0 ]
