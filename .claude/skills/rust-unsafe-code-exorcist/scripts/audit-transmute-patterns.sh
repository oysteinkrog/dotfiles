#!/usr/bin/env bash
# audit-transmute-patterns.sh — find every mem::transmute and propose safer swaps.
# Usage: ./audit-transmute-patterns.sh <project-path> [<audit-dir>]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

PROJECT="${1:?usage: audit-transmute-patterns.sh <project-path> [<audit-dir>]}"
AUDIT_DIR="${2:-$PROJECT/.unsafe-audit/audit-logs}"
PROJECT=$(audit_realpath "$PROJECT")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT")
mkdir -p "$AUDIT_DIR"
OUT="$AUDIT_DIR/audit-transmute-patterns.md"

cd "$PROJECT"

{
  echo "# transmute pattern audit"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Per [70-UNINIT-AND-TRANSMUTE.md](../../references/patterns/70-UNINIT-AND-TRANSMUTE.md)."
  echo
  echo "## Heuristic mapping"
  echo
  echo "| Source pattern (regex) | Proposed safe swap |"
  echo "|------------------------|--------------------|"
  echo "| \`transmute::<\\[u8; 4\\], u32>\` etc. | \`u32::from_ne_bytes\` / \`from_be_bytes\` / \`from_le_bytes\` |"
  echo "| \`transmute::<u32, \\[u8; 4\\]>\` | \`u32::to_ne_bytes\` etc. |"
  echo "| \`transmute::<&\\[u8\\], &\\[u32\\]>\` etc. | \`zerocopy::Ref::new_slice\` or \`bytemuck::cast_slice\` |"
  echo "| \`transmute<S, T>\` where both are repr(C) Pod | \`bytemuck::cast\` / \`bytemuck::try_cast\` |"
  echo "| \`transmute<u8, MyEnum>\` (repr(u8)) | \`TryFrom<u8>\` impl or \`num_enum::TryFromPrimitive\` |"
  echo "| \`transmute_copy(\\&MaybeUninit\\<T\\>)\` after init | \`MaybeUninit::assume_init\` (still unsafe, narrower) or \`std::array::from_fn\` |"
  echo "| \`transmute::<\\[MaybeUninit\\<T\\>; N\\], \\[T; N\\]>\` | \`array::from_fn\` / \`init_array!\` macro |"
  echo "| \`transmute::<&[u8], &str>\` | \`std::str::from_utf8\` (returns Result) |"
  echo "| \`transmute\` to change lifetime | almost always (A): write the lifetime-extending SAFETY comment instead |"
  echo
} > "$OUT"

SITES_RAW=$(mktemp); trap 'rm -f "$SITES_RAW"' EXIT
if command -v ast-grep >/dev/null 2>&1; then
  ast-grep run -l Rust -p 'std::mem::transmute::<$$$>($$$)' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1)|\((.text // "") | gsub("[\r\n\t ]+"; " "))"' >> "$SITES_RAW" || true
  ast-grep run -l Rust -p 'std::mem::transmute($$$)' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1)|\((.text // "") | gsub("[\r\n\t ]+"; " "))"' >> "$SITES_RAW" || true
  ast-grep run -l Rust -p 'mem::transmute::<$$$>($$$)' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1)|\((.text // "") | gsub("[\r\n\t ]+"; " "))"' >> "$SITES_RAW" || true
  ast-grep run -l Rust -p 'mem::transmute($$$)' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1)|\((.text // "") | gsub("[\r\n\t ]+"; " "))"' >> "$SITES_RAW" || true
  ast-grep run -l Rust -p 'transmute::<$$$>($$$)' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1)|\((.text // "") | gsub("[\r\n\t ]+"; " "))"' >> "$SITES_RAW" || true
  ast-grep run -l Rust -p 'transmute($$$)' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1)|\((.text // "") | gsub("[\r\n\t ]+"; " "))"' >> "$SITES_RAW" || true
  ast-grep run -l Rust -p 'transmute_copy::<$$$>($$$)' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1)|\((.text // "") | gsub("[\r\n\t ]+"; " "))"' >> "$SITES_RAW" || true
  ast-grep run -l Rust -p 'transmute_copy($$$)' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1)|\((.text // "") | gsub("[\r\n\t ]+"; " "))"' >> "$SITES_RAW" || true
else
  rg -n 'transmute(_copy)?\s*[(<]' -g '*.rs' --no-heading 2>/dev/null \
    | awk -F: '{print $1":"$2"|"$0}' >> "$SITES_RAW" || true
fi

{
  echo "## Sites"
  echo
} >> "$OUT"

sort -u "$SITES_RAW" | while IFS='|' read -r location excerpt; do
  file=$(echo "$location" | cut -d: -f1)
  line=$(echo "$location" | cut -d: -f2)
  [ -f "$file" ] || continue

  # Map to candidate swap
  swap_candidates=()
  if echo "$excerpt" | grep -qE 'transmute::<\s*\[u8;\s*[0-9]+\]\s*,\s*[ui][0-9]+'; then
    swap_candidates+=("u32/u64::from_ne_bytes / from_be_bytes / from_le_bytes")
  fi
  if echo "$excerpt" | grep -qE 'transmute::<\s*[ui][0-9]+\s*,\s*\[u8'; then
    swap_candidates+=("u32/u64::to_ne_bytes / to_be_bytes / to_le_bytes")
  fi
  if echo "$excerpt" | grep -qE 'transmute::<\s*&\s*\[u8\]\s*,\s*&'; then
    swap_candidates+=("zerocopy::Ref::new_slice or bytemuck::cast_slice")
  fi
  if echo "$excerpt" | grep -qE 'transmute::<\s*\[MaybeUninit'; then
    swap_candidates+=("std::array::from_fn (safe; allocate-then-fill is folklore)")
  fi
  if echo "$excerpt" | grep -qE 'transmute_copy'; then
    swap_candidates+=("ptr::read after explicit init (narrower) or zerocopy::FromBytes")
  fi

  {
    echo "### \`$file:$line\`"
    echo
    echo '```rust'
    sed -n "$line,$((line+3))p" "$file" 2>/dev/null
    echo '```'
    if [ ${#swap_candidates[@]} -gt 0 ]; then
      echo
      echo "**Candidate swaps (bias toward (C)):**"
      for c in "${swap_candidates[@]}"; do echo "- $c"; done
    else
      echo
      echo "**Candidate swap:** unable to heuristically determine; manually classify per [70-UNINIT-AND-TRANSMUTE.md](../../references/patterns/70-UNINIT-AND-TRANSMUTE.md)."
    fi
    echo
  } >> "$OUT"
done

echo "Wrote $OUT"
