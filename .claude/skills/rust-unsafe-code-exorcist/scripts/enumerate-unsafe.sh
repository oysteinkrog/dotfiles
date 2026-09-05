#!/usr/bin/env bash
# enumerate-unsafe.sh — Phase 1 enumeration driver
# Usage: ./enumerate-unsafe.sh <project-path> <audit-dir>
# Per-crate driver; runs ast-grep + cargo-geiger + cargo expand + rustdoc JSON + ubs.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

PROJECT="${1:?usage: enumerate-unsafe.sh <project> <audit-dir>}"
AUDIT_DIR_INPUT="${2:?usage: enumerate-unsafe.sh <project> <audit-dir>}"

PROJECT_ABS=$(audit_realpath "$PROJECT")
case "$AUDIT_DIR_INPUT" in
  /*) AUDIT_DIR="$AUDIT_DIR_INPUT" ;;
  *) AUDIT_DIR="$PROJECT_ABS/$AUDIT_DIR_INPUT" ;;
esac
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT_ABS")

mkdir -p "$AUDIT_DIR/phase1"
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT_ABS")

cd "$PROJECT_ABS"
printf '%s\n' "$PROJECT_ABS" > "$AUDIT_DIR/phase1/project-root.txt"

# Enumerate crates in the workspace (or treat the project as a single crate)
CRATES=$(cargo metadata --format-version 1 --no-deps 2>/dev/null | \
         jq -r '.packages[].name' || basename "$PROJECT")

HAVE_AST_GREP=false
if command -v ast-grep >/dev/null 2>&1; then HAVE_AST_GREP=true; fi
HAVE_RG=false
if command -v rg >/dev/null 2>&1; then HAVE_RG=true; fi
if ! $HAVE_AST_GREP && ! $HAVE_RG; then
  echo "warning: neither ast-grep nor ripgrep installed; enumeration falls back to grep (very imprecise)" >&2
fi

# rg-fallback emit: convert ripgrep matches into ast-grep-like JSON so the
# downstream generate-inventory.mjs treats both consistently. ast-grep reports
# range lines as zero-based; normalize rg/grep to that convention here.
# generate-inventory.mjs converts the normalized raw lines back to the
# 1-indexed line numbers promised by INVENTORY-SCHEMA.md.
emit_rg_matches() {
  local pattern="$1"; local dir="$2"; local out="$3"
  : > "$out"
  if $HAVE_RG; then
    rg --json -n -e "$pattern" "$dir" 2>/dev/null | \
      jq -s '[.[] | select(.type == "match") | {
        file: .data.path.text,
        range: { start: { line: (.data.line_number - 1) }, end: { line: (.data.line_number - 1) } },
        text: (.data.lines.text | sub("\n$"; ""))
      }]' > "$out" 2>/dev/null || echo '[]' > "$out"
  else
    # Last-resort grep: still produce SOMETHING (file:line) so downstream can pick it up
    grep -rEn "$pattern" --include='*.rs' "$dir" 2>/dev/null | \
      awk -F: '{
        gsub(/"/, "\\\"", $0);
        printf "{\"file\":\"%s\",\"range\":{\"start\":{\"line\":%s},\"end\":{\"line\":%s}},\"text\":\"\"}\n", $1, $2 - 1, $2 - 1
      }' | jq -s '.' > "$out" 2>/dev/null || echo '[]' > "$out"
  fi
}

for crate in $CRATES; do
  echo "==> Enumerating crate: $crate"
  CRATE_DIR=$(cargo metadata --format-version 1 --no-deps 2>/dev/null | \
              jq -r --arg c "$crate" '.packages[] | select(.name == $c) | .manifest_path' | \
              xargs -I {} dirname {} || echo "$PROJECT")

  # Per shape: ast-grep (preferred) OR ripgrep fallback. Both produce the same
  # JSON shape so generate-inventory.mjs consumes either.
  # NOTE: we use plain parallel "kind|ast_pattern|rg_pattern" lines instead of
  # `declare -A` (associative arrays) — `declare -A` requires Bash 4+ but macOS
  # ships Bash 3.2. The heredoc form below is portable to all Bash 3.0+.
  # Patterns are kind|ast-grep-shape|ripgrep-fallback-regex (pipe-separated).
  # The prompt enumerated these unsafe kinds explicitly; each gets its own
  # extraction pass so the inventory schema can record kind precisely.
  #
  # NOTE on UnsafeCell / intrinsics: these are LEGAL outside `unsafe { }` blocks
  # (constructing an UnsafeCell or naming an intrinsic path doesn't require
  # unsafe), but they're strong signals of imminent unsafe use. We enumerate
  # them separately so the site-analyzer can audit the surrounding invariant
  # surface even when the unsafe block is elsewhere in the file.
  SHAPE_PATTERNS=$(cat <<'PATTERNS'
unsafe_block|unsafe { $$$ }|unsafe[[:space:]]*\{
unsafe_fn|unsafe fn $NAME($$$ARGS) $$$BODY|^[[:space:]]*(pub([[:space:]]*\([^)]*\))?[[:space:]]+)?(async[[:space:]]+)?unsafe[[:space:]]+fn[[:space:]]+
unsafe_fn_vis|$VIS unsafe fn $NAME($$$ARGS) $$$BODY|^[[:space:]]*(pub([[:space:]]*\([^)]*\))?[[:space:]]+)?(async[[:space:]]+)?unsafe[[:space:]]+fn[[:space:]]+
unsafe_fn_async|async unsafe fn $NAME($$$ARGS) $$$BODY|^[[:space:]]*(pub([[:space:]]*\([^)]*\))?[[:space:]]+)?(async[[:space:]]+)?unsafe[[:space:]]+fn[[:space:]]+
unsafe_fn_async_vis|$VIS async unsafe fn $NAME($$$ARGS) $$$BODY|^[[:space:]]*(pub([[:space:]]*\([^)]*\))?[[:space:]]+)?(async[[:space:]]+)?unsafe[[:space:]]+fn[[:space:]]+
unsafe_impl|unsafe impl $$$ for $$$ { $$$ }|^[[:space:]]*unsafe[[:space:]]+impl[[:space:]]+
unsafe_trait|unsafe trait $NAME $$$|^[[:space:]]*(pub([[:space:]]*\([^)]*\))?[[:space:]]+)?unsafe[[:space:]]+trait[[:space:]]+
unsafe_trait_vis|$VIS unsafe trait $NAME $$$|^[[:space:]]*(pub([[:space:]]*\([^)]*\))?[[:space:]]+)?unsafe[[:space:]]+trait[[:space:]]+
extern_block|extern "C" { $$$ }|^[[:space:]]*(pub([[:space:]]*\([^)]*\))?[[:space:]]+)?(unsafe[[:space:]]+)?extern([[:space:]]+"[^"]+")?[[:space:]]*\{
asm|asm!($$$)|(^|[^a-zA-Z0-9_])asm![[:space:]]*\(
unsafe_cell_decl|UnsafeCell::new($$$)|UnsafeCell[[:space:]]*::[[:space:]]*new
unsafe_cell_turbofish|UnsafeCell::<$T>::new($$$)|UnsafeCell[[:space:]]*::[[:space:]]*<
intrinsic_call_core|core::intrinsics::$INTR($$$)|core::intrinsics::(unreachable_unchecked|assert_unchecked|assume|atomic_load_unsynchronized|atomic_store_unsynchronized|likely|unlikely)
intrinsic_call_std|std::intrinsics::$INTR($$$)|std::intrinsics::(unreachable_unchecked|assert_unchecked|assume|atomic_load_unsynchronized|atomic_store_unsynchronized|likely|unlikely)
intrinsic_hint_unreach_core|core::hint::unreachable_unchecked()|core::hint::unreachable_unchecked
intrinsic_hint_unreach_std|std::hint::unreachable_unchecked()|std::hint::unreachable_unchecked
intrinsic_hint_assert_core|core::hint::assert_unchecked($$$)|core::hint::assert_unchecked
intrinsic_hint_assert_std|std::hint::assert_unchecked($$$)|std::hint::assert_unchecked
intrinsic_ptr_core|core::ptr::$OP($$$)|core::ptr::(read|write|read_unaligned|write_unaligned|read_volatile|write_volatile|copy|copy_nonoverlapping|swap|swap_nonoverlapping|replace|drop_in_place)\(
intrinsic_ptr_std|std::ptr::$OP($$$)|std::ptr::(read|write|read_unaligned|write_unaligned|read_volatile|write_volatile|copy|copy_nonoverlapping|swap|swap_nonoverlapping|replace|drop_in_place)\(
raw_ptr_decl_const|let $X: *const $TY = $$$|let[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*:[[:space:]]*\*const[[:space:]]
raw_ptr_decl_mut|let $X: *mut $TY = $$$|let[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*:[[:space:]]*\*mut[[:space:]]
raw_ptr_as_cast_const|$EXPR as *const $TY|[[:space:]]as[[:space:]]+\*const[[:space:]]
raw_ptr_as_cast_mut|$EXPR as *mut $TY|[[:space:]]as[[:space:]]+\*mut[[:space:]]
PATTERNS
)
  while IFS='|' read -r kind ast_pattern rg_pattern; do
    [ -n "$kind" ] || continue
    out="$AUDIT_DIR/phase1/${crate}__ast_${kind}.json"
    if [ "$kind" = "extern_block" ]; then
      emit_rg_matches "$rg_pattern" "$CRATE_DIR/src" "$out"
    elif $HAVE_AST_GREP; then
      ast-grep run -l Rust -p "$ast_pattern" --json "$CRATE_DIR/src" \
        > "$out" 2>/dev/null || echo '[]' > "$out"
    else
      emit_rg_matches "$rg_pattern" "$CRATE_DIR/src" "$out"
    fi
  done <<< "$SHAPE_PATTERNS"

  # cargo-geiger. Tee stderr so a silent failure leaves a breadcrumb instead
  # of an unexplained zero-byte JSON file. On success, remove any stale
  # .failed sentinel left by a previous run.
  geiger_stderr="$AUDIT_DIR/phase1/${crate}__geiger.stderr.log"
  if (cd "$CRATE_DIR" && cargo +nightly geiger --output-format Json \
       > "$AUDIT_DIR/phase1/${crate}__geiger.json" 2>"$geiger_stderr") \
     && [ -s "$AUDIT_DIR/phase1/${crate}__geiger.json" ]; then
    [ -s "$geiger_stderr" ] || rm -f "$geiger_stderr"
    rm -f "$AUDIT_DIR/phase1/${crate}__geiger.failed"
  else
    rc=$?
    echo "    geiger FAILED for $crate (exit $rc; see ${crate}__geiger.stderr.log)"
    printf '%s\n' "FAILED: cargo +nightly geiger exit $rc" \
      > "$AUDIT_DIR/phase1/${crate}__geiger.failed"
  fi

  # cargo expand. RCH_DISABLED=1 because remote-compilation helpers (rch) can
  # silently intercept cargo and produce a zero-byte expansion when the
  # offload doesn't support `cargo expand`. Forcing local execution makes
  # the failure mode loud instead of silent.
  #
  # Crates with BOTH `[lib]` and `[[bin]]` targets (common for CLI tools that
  # expose a library API too) cause `cargo expand` to error with "extra
  # arguments to rustc can only be passed to one target." We work around by
  # probing the available targets and emitting one expand pass per target,
  # concatenated. Library expansion comes first (more interesting for macro
  # surface), then each binary's expansion is appended.
  expand_stderr="$AUDIT_DIR/phase1/${crate}__expand.stderr.log"
  expand_out="$AUDIT_DIR/phase1/${crate}__expand.rs"
  : > "$expand_out"
  : > "$expand_stderr"

  # Discover this crate's targets from `cargo metadata`. The `lib`-family covers
  # `lib` / `rlib` / `cdylib` / `staticlib` / `proc-macro`; `bin` covers
  # binaries. We do not expand examples / tests / benches (too noisy).
  #
  # NOTE on the jq filter: we match `.kind` element-wise rather than stringifying
  # the array and substring-matching. The substring approach excludes
  # `["proc-macro"]` (doesn't contain "lib" or "bin"), and that's a real bug:
  # proc-macro crates emit interesting macro-expanded unsafe and should be
  # expanded. Element-wise matching is also clearer about intent.
  CRATE_TARGETS=$(cargo metadata --no-deps --format-version 1 2>/dev/null | \
    jq -r --arg c "$crate" '
      .packages[] | select(.name == $c) | .targets[]
      | select(.kind | any(
          . == "lib" or . == "rlib" or . == "cdylib" or
          . == "staticlib" or . == "proc-macro" or . == "bin"))
      | "\(.kind[0])\t\(.name)"' 2>/dev/null)

  expand_any_target_succeeded=false
  if [ -n "$CRATE_TARGETS" ]; then
    while IFS=$'\t' read -r tkind tname; do
      [ -n "$tkind" ] || continue
      case "$tkind" in
        lib|rlib|cdylib|staticlib|proc-macro) flag="--lib" ;;
        bin)                                  flag="--bin $tname" ;;
        *) continue ;;
      esac
      sub_out="${expand_out}.${tkind}.${tname}.part"
      sub_err="${expand_stderr}.${tkind}.${tname}.part"
      # shellcheck disable=SC2086 # $flag intentionally word-split
      if (cd "$CRATE_DIR" && RCH_DISABLED=1 cargo expand $flag \
           > "$sub_out" 2>"$sub_err"); then
        if [ -s "$sub_out" ]; then
          printf '\n// ===== target: %s (%s) =====\n' "$tname" "$tkind" >> "$expand_out"
          cat "$sub_out" >> "$expand_out"
          expand_any_target_succeeded=true
        fi
      fi
      # Roll subordinate stderr into the main stderr log; clean up the parts.
      if [ -s "$sub_err" ]; then
        printf '\n--- target %s (%s) ---\n' "$tname" "$tkind" >> "$expand_stderr"
        cat "$sub_err" >> "$expand_stderr"
      fi
      rm -f "$sub_out" "$sub_err"
    done <<< "$CRATE_TARGETS"
  else
    # Fallback: try the bare-form cargo expand (single-target crates).
    if (cd "$CRATE_DIR" && RCH_DISABLED=1 cargo expand \
         > "$expand_out" 2>"$expand_stderr"); then
      [ -s "$expand_out" ] && expand_any_target_succeeded=true
    fi
  fi

  if $expand_any_target_succeeded; then
    [ -s "$expand_stderr" ] || rm -f "$expand_stderr"
    rm -f "$AUDIT_DIR/phase1/${crate}__expand.failed"
  else
    echo "    expand FAILED for $crate (see ${crate}__expand.stderr.log)"
    printf '%s\n' \
      "FAILED: cargo expand produced no output for any target. Common causes:" \
      "  - cargo-expand not installed: cargo install cargo-expand --locked" \
      "  - nightly toolchain not available: rustup toolchain install nightly" \
      "  - rch (remote compilation helper) intercepted the build" \
      "    (RCH_DISABLED=1 is set internally; check for outer interference)" \
      "  - the crate has no library and no binary targets (only examples/tests/benches)" \
      > "$AUDIT_DIR/phase1/${crate}__expand.failed"
  fi

  # unsafe in expanded output — only if expand actually produced content.
  #
  # NOTE: ast-grep's `unsafe $$$` pattern does NOT parse as valid Rust syntax
  # (the `unsafe` keyword must be followed by `fn` / `impl` / `trait` / `extern`
  # / `{`); ast-grep silently returns `[]` and emits "Pattern contains an
  # ERROR node" to stderr. We therefore use a regex-based extraction here that
  # matches every unsafe construct shape: declarations + blocks. Comments and
  # string literals can sneak in via this; downstream `expand_unsafe`
  # classification de-noises them by category (TrivialClone / unreachable() /
  # other).
  if [ -s "$AUDIT_DIR/phase1/${crate}__expand.rs" ]; then
    emit_rg_matches \
      '\bunsafe[[:space:]]+(fn|impl|trait|extern|\{)' \
      "$AUDIT_DIR/phase1/${crate}__expand.rs" \
      "$AUDIT_DIR/phase1/${crate}__expand_unsafe.json"
  fi

  # rustdoc JSON (nightly)
  (cd "$CRATE_DIR" && cargo +nightly rustdoc -- -Z unstable-options --output-format json 2>/dev/null) || \
    echo "    rustdoc JSON failed for $crate"
  RUSTDOC_JSON="target/doc/${crate}.json"
  if [ ! -f "$RUSTDOC_JSON" ]; then
    RUSTDOC_JSON="target/doc/${crate//-/_}.json"
  fi
  if [ -f "$RUSTDOC_JSON" ]; then
    cp "$RUSTDOC_JSON" "$AUDIT_DIR/phase1/${crate}__rustdoc.json"
  fi

  # ubs
  if command -v ubs >/dev/null 2>&1; then
    (cd "$CRATE_DIR" && ubs --only=rust src/ > "$AUDIT_DIR/phase1/${crate}__ubs.txt" 2>/dev/null) || true
  fi
done

echo
echo "Enumeration done. Per-crate JSONs in $AUDIT_DIR/phase1/"
printf 'Now run: node %q %q\n' "$SCRIPT_DIR/generate-inventory.mjs" "$AUDIT_DIR"
