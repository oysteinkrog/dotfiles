#!/usr/bin/env bash
# audit-ffi-boundary.sh — for every `extern "C"` block, emit the boundary-contract template.
# Usage: ./audit-ffi-boundary.sh <project-path> [<audit-dir>]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

PROJECT="${1:?usage: audit-ffi-boundary.sh <project-path> [<audit-dir>]}"
AUDIT_DIR="${2:-$PROJECT/.unsafe-audit/audit-logs}"
PROJECT=$(audit_realpath "$PROJECT")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT")
mkdir -p "$AUDIT_DIR/ffi-contracts"
OUT="$AUDIT_DIR/audit-ffi-boundary.md"

cd "$PROJECT"

{
  echo "# FFI boundary audit"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Per [60-FFI-PATTERNS.md § contract template](../../references/patterns/60-FFI-PATTERNS.md)."
  echo
  echo "For each \`extern \"C\"\` block, a per-block contract skeleton is generated under"
  echo "\`.unsafe-audit/audit-logs/ffi-contracts/\`. Fill in each section before finalizing the audit."
  echo
} > "$OUT"

# Find extern "C" blocks
SITES_RAW=$(mktemp); trap 'rm -f "$SITES_RAW"' EXIT

if command -v ast-grep >/dev/null 2>&1; then
  ast-grep run -l Rust -p 'extern "C" { $$$ }' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1):\(.range.end.line + 1)"' >> "$SITES_RAW" || true
  ast-grep run -l Rust -p 'unsafe extern "C" { $$$ }' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1):\(.range.end.line + 1)"' >> "$SITES_RAW" || true
  # Also catch fns directly marked extern "C"
  ast-grep run -l Rust -p 'extern "C" fn $NAME($$$ARGS) $$$BODY' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1):\(.range.end.line + 1)"' >> "$SITES_RAW" || true
  ast-grep run -l Rust -p '$VIS extern "C" fn $NAME($$$ARGS) $$$BODY' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1):\(.range.end.line + 1)"' >> "$SITES_RAW" || true
  ast-grep run -l Rust -p 'unsafe extern "C" fn $NAME($$$ARGS) $$$BODY' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1):\(.range.end.line + 1)"' >> "$SITES_RAW" || true
  ast-grep run -l Rust -p '$VIS unsafe extern "C" fn $NAME($$$ARGS) $$$BODY' --json 2>/dev/null \
    | jq -r '.[] | "\(.file):\(.range.start.line + 1):\(.range.end.line + 1)"' >> "$SITES_RAW" || true
else
  rg -n 'extern\s+"C"' -g '*.rs' --no-heading 2>/dev/null \
    | awk -F: '{print $1":"$2":"$2}' >> "$SITES_RAW" || true
fi

{
  COUNT=$(sort -u "$SITES_RAW" | wc -l | tr -d ' ')
  echo "**FFI surfaces found:** $COUNT"
  echo
  echo "## Per-surface contracts"
  echo
} >> "$OUT"

# Panic-strategy check (extern "C" with Rust unwinding is UB)
profile_has_panic_abort() {
  local profile="$1"
  local manifests=()
  local manifest
  if [ -f Cargo.toml ] && grep -qE '^[[:space:]]*\[workspace\]' Cargo.toml; then
    # Cargo ignores profile sections in workspace member manifests; only the
    # workspace root profile controls member builds.
    manifests+=(Cargo.toml)
  else
    [ -f Cargo.toml ] && manifests+=(Cargo.toml)
    for manifest in ./*/Cargo.toml; do
      [ -f "$manifest" ] || continue
      manifests+=("$manifest")
    done
  fi
  [ "${#manifests[@]}" -gt 0 ] || return 1

  awk -v profile="$profile" '
    /^[[:space:]]*\[/ {
      in_profile = ($0 ~ ("^[[:space:]]*\\[profile\\." profile "\\][[:space:]]*$"))
    }
    in_profile && /^[[:space:]]*panic[[:space:]]*=/ && $0 ~ /"abort"/ {
      found = 1
    }
    END { exit(found ? 0 : 1) }
  ' "${manifests[@]}" 2>/dev/null
}

if profile_has_panic_abort dev && profile_has_panic_abort release; then
  PANIC_OK=true
else
  PANIC_OK=false
fi

{
  echo "## Panic strategy"
  echo
  if $PANIC_OK; then
    echo "✓ \`panic = \"abort\"\` declared in \`[profile.dev]\` and \`[profile.release]\`."
  else
    echo "⚠ \`panic = \"abort\"\` is NOT declared in both \`[profile.dev]\` and \`[profile.release]\`."
    echo "  Rust unwinding through \`extern \"C\"\` is UB."
    echo "  Either set \`panic = \"abort\"\` in \`[profile.release]\` AND \`[profile.dev]\`,"
    echo "  OR wrap every \`#[no_mangle] extern \"C\" fn\` body in \`std::panic::catch_unwind\`."
  fi
  echo
} >> "$OUT"

sort -u "$SITES_RAW" | while IFS=: read -r file start end; do
  [ -f "$file" ] || continue

  safe_slug=$(echo "${file#./}" | sed 's|/|__|g; s|\.rs$||')
  CONTRACT="$AUDIT_DIR/ffi-contracts/${safe_slug}__L${start}.md"

  cat > "$CONTRACT" <<EOF
# FFI boundary contract — $file:$start–$end

## Block source
\`\`\`rust
$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$file" | head -40)
\`\`\`

## C side promises (per function in this block)
- Reads: <which pointers, what length>
- Writes: <which out-params, when>
- Returns: <type, sentinel values for error>
- Errno: <yes/no — how conveyed>
- Allocates: <returns owned ptr (caller must free) / borrowed ptr / no allocation>
- Aliases: <may alias / will not alias / kernel may write asynchronously>
- May panic / abort / longjmp from Rust callbacks: <yes/no — if yes, how do we contain?>

## Rust side promises (caller of the safe wrapper)
- Pointer validity: <caller must guarantee — or our safe wrapper enforces via type>
- Lifetime: <how long the pointer must remain valid>
- Null-termination (for strings): <enforced by \`&CStr\` or explicitly>
- Encoding: <UTF-8 / locale / raw bytes>
- Thread safety: <reentrant / not reentrant>
- Alignment: <required / verified by which constructor>

## Ownership of returned values
- Returned RawFd: <owned by Rust IFF success; wrap in \`OwnedFd\`>
- Returned string: <static / owned (caller must \`libc::free\`) / borrowed for caller's lifetime>
- Returned struct: <ownership, drop responsibility>

## Errors
- Failure mode: <return = -1 + errno / out-param status / sentinel>
- Mapping: \`Err(io::Error::last_os_error())\` or custom \`Errno\` enum
- Retryable: <which errno values mean "retry">

## Panicking discipline
- Wrapper is non-panicking by construction (no \`?\`, \`unwrap\`, \`expect\`): yes / no
- panic = abort in profile: yes / no
- catch_unwind boundary on extern "C" Rust callbacks: yes / no

## Endianness / padding / ABI
- Endianness assumption: <native / explicit \`from_be/le\`>
- \`#[repr(C)]\` on shared structs: verified
- Padding: verified to match C header

## Tests
- miri runnable: yes / no (FFI usually no; document with \`#[cfg(not(miri))]\`)
- cargo-careful runnable: yes
- fuzz target: <name or "n/a">

## SAFETY comment placement
The thin safe wrapper for each function in this block lives in:
- \`<path-to-safe-wrapper>\`

Hardened SAFETY comment template:

\`\`\`rust
/// <prose>
///
/// # Safety
///
/// The caller MUST guarantee:
/// - <list>
///
/// On the C side: <C contract — what's read/written/returned>
///
/// Unwinding: <UB / handled via catch_unwind / panic=abort guards>
\`\`\`
EOF

  {
    echo "### \`$file:$start–$end\`"
    echo
    echo "Per-block contract template: [$(basename "$CONTRACT")](ffi-contracts/$(basename "$CONTRACT"))"
    echo
  } >> "$OUT"
done

echo "Wrote $OUT and contract skeletons under $AUDIT_DIR/ffi-contracts/"
