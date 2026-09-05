#!/usr/bin/env bash
# audit-allocator-changes.sh — detect plans that may silently change allocator identity.
# Usage: ./audit-allocator-changes.sh <audit-dir>
#
# Walks audit/plans/*.md; flags any plan whose ORIGINAL code mentions a custom
# allocator (bumpalo / slab / typed-arena / arena / mmap / page-aligned) but whose
# REWRITE uses Vec / Box / String / HashMap without an explicit allocator-identity note.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: audit-allocator-changes.sh <audit-dir>}"
AUDIT_DIR=$(audit_realpath "$AUDIT_DIR")
PROJECT_ROOT=$(audit_project_root_from_dir "$AUDIT_DIR")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT_ROOT")
PLANS="$AUDIT_DIR/audit/plans"
OUT="$AUDIT_DIR/audit/phase5/allocator-identity-check.md"
mkdir -p "$(dirname "$OUT")"

if [ ! -d "$PLANS" ]; then
  echo "error: $PLANS not found." >&2
  exit 1
fi

CUSTOM_ALLOC_PATTERNS='bumpalo|slab::|typed_arena|generational_arena|arena::|page_align|mmap|memmap2|GlobalAlloc|alloc_zeroed|alloc::Layout::from_size_align'
GLOBAL_ALLOC_PATTERNS='\bVec::|\bBox::|\bString::|\bHashMap::|vec!\['

{
  echo "# Allocator identity check"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Per operator 📐 Allocator-Identity ([OPERATORS.md](../../references/methodology/OPERATORS.md)) and"
  echo "[00-CANONICAL-UNAVOIDABLE.md § allocator-identity](../../references/patterns/00-CANONICAL-UNAVOIDABLE.md)."
  echo
  echo "Plans flagged where ORIGINAL uses a custom allocator AND REWRITE uses global without an explicit note."
  echo
  echo "| Site | Original allocator (heuristic) | Rewrite allocator | Note present? | Verdict |"
  echo "|------|--------------------------------|-------------------|---------------|---------|"
} > "$OUT"

FLAGS=0
for plan in "$PLANS"/site-*.md; do
  [ -f "$plan" ] || continue
  site_id=$(basename "$plan" .md)

  has_custom_original=$(grep -ciE "$CUSTOM_ALLOC_PATTERNS" "$plan" || true)
  has_global_rewrite=$(grep -ciE "$GLOBAL_ALLOC_PATTERNS" "$plan" || true)
  has_note=$(grep -ciE 'allocator (identity|change)|preserved\? *yes' "$plan" || true)

  if [ "$has_custom_original" -ge 1 ] && [ "$has_global_rewrite" -ge 1 ]; then
    orig_hint=$(grep -oiE "$CUSTOM_ALLOC_PATTERNS" "$plan" | sort -u | head -3 | paste -sd, -)
    rewrite_hint=$(grep -oiE "$GLOBAL_ALLOC_PATTERNS" "$plan" | sort -u | head -3 | paste -sd, -)
    if [ "$has_note" -ge 1 ]; then
      echo "| $site_id | $orig_hint | $rewrite_hint | yes | OK (verify note is accurate) |" >> "$OUT"
    else
      echo "| $site_id | $orig_hint | $rewrite_hint | **NO** | **FLAGGED — silent allocator change** |" >> "$OUT"
      FLAGS=$((FLAGS+1))
    fi
  fi
done

{
  echo
  echo "## Summary"
  echo
  echo "- **Flagged plans (silent allocator change):** $FLAGS"
  echo
  if [ "$FLAGS" -gt 0 ]; then
    echo "Each flagged plan must EITHER:"
    echo "1. Document the allocator change explicitly + get user approval; or"
    echo "2. Preserve allocator identity (\`bumpalo::collections::Vec\` instead of \`std::vec::Vec\`, etc.); or"
    echo "3. Reclassify as (A) if the allocator semantics are part of the soundness contract."
  fi
} >> "$OUT"

echo "Wrote $OUT (flagged: $FLAGS)"
[ "$FLAGS" -eq 0 ]
