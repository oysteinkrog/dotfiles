#!/usr/bin/env bash
# audit-pin-projection-soundness.sh — scan for Pin::new_unchecked / map_unchecked_mut
# and verify each has a SAFETY comment that survives the 80-PIN-PROJECTIONS rubric.
#
# Usage: ./audit-pin-projection-soundness.sh <project-path> [<audit-dir>]
#
# Emits a Markdown report listing each pin-unchecked site, its enclosing function,
# whether a SAFETY comment is present in the preceding 10 lines, and (heuristic)
# whether the type involved looks `!Unpin` / has `PhantomPinned`.
#
# Pair: subagents/pin-projection-auditor.md
#   This script is the MECHANICAL half — it surfaces sites + heuristic checks.
#   The JUDGMENTAL half (does the SAFETY comment actually satisfy the rubric?
#   could pin-project-lite eliminate the unsafe?) is the subagent's job.
#   The subagent reads this script's output as input.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

PROJECT="${1:?usage: audit-pin-projection-soundness.sh <project-path> [<audit-dir>]}"
AUDIT_DIR="${2:-$PROJECT/.unsafe-audit/audit-logs}"
PROJECT=$(audit_realpath "$PROJECT")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT")
mkdir -p "$AUDIT_DIR"
OUT="$AUDIT_DIR/audit-pin-projection-soundness.md"

cd "$PROJECT"

{
  echo "# Pin projection soundness audit"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Per [80-PIN-PROJECTIONS.md](../../references/patterns/80-PIN-PROJECTIONS.md)."
  echo
} > "$OUT"

# Collect Pin-unchecked call sites via ast-grep (preferred) + ripgrep fallback.
SITES_RAW=$(mktemp)
trap 'rm -f "$SITES_RAW"' EXIT

if command -v ast-grep >/dev/null 2>&1; then
  ast-grep run -l Rust -p 'Pin::new_unchecked($$$)' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1)"' >> "$SITES_RAW" || true
  ast-grep run -l Rust -p '$P.map_unchecked_mut($$$)' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1)"' >> "$SITES_RAW" || true
  ast-grep run -l Rust -p '$P.get_unchecked_mut()' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1)"' >> "$SITES_RAW" || true
else
  rg -n 'Pin::new_unchecked|map_unchecked_mut|get_unchecked_mut' \
     -g '*.rs' --no-heading 2>/dev/null \
    | awk -F: '{print $1":"$2}' >> "$SITES_RAW" || true
fi

# Pin-project-lite / pin-project usage (used to factor out manual pin-unchecked)
PIN_PROJECT_CRATES=""
if grep -qE 'pin-project(-lite)?' Cargo.toml ./*/Cargo.toml 2>/dev/null; then
  PIN_PROJECT_CRATES=$(grep -lE 'pin-project(-lite)?' Cargo.toml ./*/Cargo.toml 2>/dev/null | head -5)
fi

# Per-site audit
{
  COUNT=$(sort -u "$SITES_RAW" | wc -l | tr -d ' ')
  echo "## Summary"
  echo
  echo "- **Pin-unchecked sites found:** $COUNT"
  if [ -n "$PIN_PROJECT_CRATES" ]; then
    echo "- **pin-project / pin-project-lite present in:**"
    printf '%s\n' "$PIN_PROJECT_CRATES" | sed 's/^/    - /'
  else
    echo "- **pin-project / pin-project-lite:** NOT in any Cargo.toml — many sites may be (C) candidates"
  fi
  echo
  echo "## Per-site findings"
  echo
} >> "$OUT"

sort -u "$SITES_RAW" | while IFS=: read -r file line; do
  [ -f "$file" ] || continue

  start_ctx=$(( line - 10 ))
  [ "$start_ctx" -lt 1 ] && start_ctx=1
  end_ctx=$(( line + 2 ))

  ctx=$(awk -v s="$start_ctx" -v e="$end_ctx" 'NR>=s && NR<=e' "$file")
  has_safety=$(printf '%s' "$ctx" | grep -ciE 'SAFETY:|#\s*Safety' || true)
  has_unpin_marker=$(printf '%s' "$ctx" | grep -ciE 'PhantomPinned|!Unpin' || true)
  has_pin_box=$(printf '%s' "$ctx" | grep -ciE 'Pin<Box|Box::pin' || true)

  rubric=()
  if [ "$has_safety" -eq 0 ]; then rubric+=("⚠ SAFETY comment missing in preceding 10 lines"); fi
  if [ "$has_unpin_marker" -eq 0 ] && [ "$has_pin_box" -eq 0 ]; then
    rubric+=("⚠ no PhantomPinned / !Unpin / Pin<Box> evidence in context — verify pin discipline")
  fi

  {
    echo "### \`$file:$line\`"
    echo
    echo '```rust'
    printf '%s\n' "$ctx"
    echo '```'
    echo
    if [ ${#rubric[@]} -gt 0 ]; then
      echo "**Rubric findings:**"
      for r in "${rubric[@]}"; do echo "- $r"; done
    else
      echo "**Rubric findings:** none (SAFETY comment and pin-discipline markers present)"
    fi
    echo
  } >> "$OUT"
done

{
  echo "## Action items"
  echo
  echo "For each site:"
  echo
  echo "1. If \`pin-project-lite\` would apply, propose (C) refactor per [80-PIN-PROJECTIONS.md § P-1](../../references/patterns/80-PIN-PROJECTIONS.md)."
  echo "2. If self-referential (no pin-project mapping), justify (A) per [00-CANONICAL-UNAVOIDABLE.md § 8](../../references/patterns/00-CANONICAL-UNAVOIDABLE.md)."
  echo "3. Ensure SAFETY comment names: pin discipline, construction site, field-level invariants, async-cancellation behavior."
} >> "$OUT"

echo "Wrote $OUT"
