#!/usr/bin/env bash
# rustonomicon-antipatterns.sh — run a fixed ast-grep ruleset that mirrors
# the Rustonomicon's "Don't do this" examples. Each rule cites its
# Rustonomicon URL so a finding is self-documenting.
#
# Usage:
#   rustonomicon-antipatterns.sh <source-dir> [--workspace <ws>]
#
# Writes <workspace>/phase2_findings_rustonomicon.md if --workspace is given;
# otherwise prints findings to stdout. Exit 0 if no hits, 1 if any hit (so the
# script composes with `|| echo "rustonomicon clean"`).
#
# References:
#   https://doc.rust-lang.org/nomicon/what-unsafe-does.html  (master list of UB)
#   https://doc.rust-lang.org/nomicon/transmutes.html
#   https://doc.rust-lang.org/nomicon/lifetime-mismatch.html
#   https://doc.rust-lang.org/nomicon/uninitialized.html
#   https://doc.rust-lang.org/nomicon/vec.html
#   https://doc.rust-lang.org/nomicon/aliasing.html
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

if [[ $# -lt 1 ]]; then
    echo "Usage: rustonomicon-antipatterns.sh <source-dir> [--workspace <ws>]" >&2
    exit 2
fi

SOURCE="$1"
shift

WORKSPACE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)
            shift
            [[ $# -gt 0 ]] || { echo "--workspace requires a value" >&2; exit 2; }
            WORKSPACE="$1" ;;
        --workspace=*) WORKSPACE="${1#--workspace=}" ;;
        *)             echo "Unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
done

if [[ ! -d "$SOURCE" ]]; then
    echo "Source dir not found: $SOURCE" >&2
    exit 2
fi
if ! command -v ast-grep >/dev/null 2>&1; then
    echo "ast-grep not installed (try: cargo install ast-grep)" >&2
    exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "jq not installed (required for hit counting). Install via apt/brew/dnf." >&2
    exit 2
fi

# Validate workspace if provided
OUTPUT=""
if [[ -n "$WORKSPACE" ]]; then
    WORKSPACE_REAL="$(realpath -m "$WORKSPACE")"
    case "$WORKSPACE_REAL" in
        */.ub-exorcism/*) WORKSPACE="$WORKSPACE_REAL" ;;
        *)
            echo "Workspace must be inside <source>/.ub-exorcism/<run-id>" >&2
            exit 2
            ;;
    esac
    mkdir -p "$WORKSPACE"
    OUTPUT="$WORKSPACE/phase2_findings_rustonomicon.md"
fi

# Rule catalogue: each entry is "RULE_ID|ast-grep pattern|Rustonomicon URL|one-line description"
# IDs follow R-NN-shortname convention. Patterns use ast-grep meta-vars ($X, $$$).
# Rule entries intentionally contain literal ast-grep metavariables such as
# `$T`, `$E`, and `$$$ARGS`.
# shellcheck disable=SC2016
RULES=(
    # Transmute family — https://doc.rust-lang.org/nomicon/transmutes.html
    'R-01-transmute-into-mutref|transmute::<&$T, &mut $T>($E)|https://doc.rust-lang.org/nomicon/transmutes.html|Producing &mut from & is undefined behavior'
    'R-02-zeroed-ref|mem::zeroed::<&$T>()|https://doc.rust-lang.org/nomicon/uninitialized.html|mem::zeroed of a reference is instant UB (null reference)'
    'R-03-zeroed-nonzero|mem::zeroed::<NonZeroU8>()|https://doc.rust-lang.org/nomicon/what-unsafe-does.html|mem::zeroed of a NonZero* type is UB'
    'R-04-zeroed-box|mem::zeroed::<Box<$T>>()|https://doc.rust-lang.org/nomicon/uninitialized.html|mem::zeroed of a Box is UB'
    'R-05-uninit-assume|MaybeUninit::<$T>::uninit().assume_init()|https://doc.rust-lang.org/nomicon/uninitialized.html|assume_init on never-written MaybeUninit is UB'

    # Aliasing — https://doc.rust-lang.org/nomicon/aliasing.html
    'R-06-mut-from-const|$E as *const $T as *mut $T|https://doc.rust-lang.org/nomicon/aliasing.html|Casting *const through *mut and writing through it violates aliasing'

    # Vec / slice — https://doc.rust-lang.org/nomicon/vec.html
    'R-08-setlen-beyond-cap|$V.set_len($V.capacity() + $E)|https://doc.rust-lang.org/nomicon/vec.html|set_len beyond capacity exposes uninitialized memory'
    'R-09-fromrawparts-stack|Vec::from_raw_parts($P, $L, $C)|https://doc.rust-lang.org/std/vec/struct.Vec.html#method.from_raw_parts|Verify ptr came from same Vec/Box; cross-allocator UB is common'
    'R-10-slice-from-raw-null|slice::from_raw_parts($NULL_PTR, $LEN)|https://doc.rust-lang.org/std/slice/fn.from_raw_parts.html|from_raw_parts requires non-null ptr if len > 0'

    # Box — https://doc.rust-lang.org/nomicon/leaking.html
    'R-11-box-from-stack|Box::from_raw(&mut $E)|https://doc.rust-lang.org/std/boxed/struct.Box.html#method.from_raw|Box::from_raw on stack pointer is UB (the alloc must come from Box::into_raw)'
    'R-12-box-double-free|let $B = Box::from_raw($P); let $C = Box::from_raw($P);|https://doc.rust-lang.org/std/boxed/struct.Box.html#method.from_raw|Double Box::from_raw on the same pointer is double-free'

    # Pin — https://doc.rust-lang.org/std/pin/index.html
    'R-13-move-out-of-pin|Pin::into_inner_unchecked($PIN)|https://doc.rust-lang.org/std/pin/struct.Pin.html#method.into_inner_unchecked|Moving out of Pin<T> for !Unpin T is UB'

    # FFI — https://doc.rust-lang.org/nomicon/ffi.html
    'R-14-extern-c-panic|extern "C" fn $NAME($$$ARGS) { $$$BEFORE panic!($$$) $$$AFTER }|https://doc.rust-lang.org/nomicon/ffi.html|panic across extern "C" without catch_unwind is UB'

    # Atomics — https://doc.rust-lang.org/nomicon/atomics.html
    'R-15-compiler-fence-cross-thread|compiler_fence($ORD)|https://doc.rust-lang.org/std/sync/atomic/fn.compiler_fence.html|compiler_fence only constrains the compiler — NOT the CPU. For cross-thread sync use atomic::fence'

    # Niche / validity — https://doc.rust-lang.org/nomicon/what-unsafe-does.html
    'R-16-transmute-niche|transmute::<u32, NonZeroU32>($E)|https://doc.rust-lang.org/nomicon/what-unsafe-does.html|transmute into NonZeroU32 from arbitrary u32 may produce 0 → UB'
    'R-17-transmute-bool|transmute::<u8, bool>($E)|https://doc.rust-lang.org/nomicon/what-unsafe-does.html|bool must be 0 or 1; transmuting arbitrary u8 is UB'

    # Unreachable — https://doc.rust-lang.org/std/hint/fn.unreachable_unchecked.html
    'R-18-unreachable-no-guard|unreachable_unchecked()|https://doc.rust-lang.org/std/hint/fn.unreachable_unchecked.html|Verify the call is reached only when the predicate is provably true — see D-8'

    # repr(packed) — https://doc.rust-lang.org/nomicon/other-reprs.html
    # NB: ast-grep can't compose "matches X only when surrounded by Y", so we
    # can't directly flag `&self.field` only inside #[repr(packed)] types.
    # Instead, flag the repr(packed) declaration itself; the human auditor
    # then manually inspects every field access in that type for `addr_of!`
    # discipline. Use rustc -W unaligned-references for a stricter compile-time check.
    'R-19-repr-packed-decl|#[repr(packed)] struct $T { $$$FIELDS }|https://doc.rust-lang.org/nomicon/other-reprs.html|repr(packed) detected — manually verify every &self.FIELD access uses addr_of! (compile with -W unaligned-references)'
    'R-19b-repr-packed-tuple|#[repr(packed)] struct $T($$$FIELDS);|https://doc.rust-lang.org/nomicon/other-reprs.html|repr(packed) tuple struct — same addr_of! discipline required'

    # get_unchecked — https://doc.rust-lang.org/std/primitive.slice.html#method.get_unchecked
    'R-20-get-unchecked-no-bounds|$SLICE.get_unchecked($IDX)|https://doc.rust-lang.org/std/primitive.slice.html#method.get_unchecked|get_unchecked without proof IDX < len() is UB'

    # extern callback mut — https://doc.rust-lang.org/nomicon/ffi.html
    'R-21-cb-mut-from-c|extern "C" fn $NAME($P: *mut $T)|https://doc.rust-lang.org/nomicon/ffi.html|*mut from C: confirm C maintains exclusivity. Re-borrow as &mut only inside a locked region'

    # Send/Sync — https://doc.rust-lang.org/nomicon/send-and-sync.html
    'R-22-unsafe-send-rawptr|unsafe impl Send for $T|https://doc.rust-lang.org/nomicon/send-and-sync.html|unsafe impl Send: confirm the type owns/synchronizes all its fields'
    'R-23-unsafe-sync-rawptr|unsafe impl Sync for $T|https://doc.rust-lang.org/nomicon/send-and-sync.html|unsafe impl Sync: confirm all fields are accessed via Sync containers'

    # Drop — https://doc.rust-lang.org/nomicon/destructors.html
    'R-24-drop-self-ref|impl Drop for $T { fn drop(&mut self) { $$$BEFORE Box::from_raw(self.$FIELD) $$$AFTER } }|https://doc.rust-lang.org/nomicon/destructors.html|Drop body using Box::from_raw on self.field then later code uses self → likely UAF'
)

# Run each rule. ast-grep --json returns [] when no matches.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TOTAL_HITS=0

run_rule() {
    local entry="$1"
    IFS='|' read -r id pattern url desc <<< "$entry"
    local out="$TMP_DIR/$id.json"
    ast-grep run -l Rust --json -p "$pattern" "$SOURCE" 2>/dev/null > "$out" || true
    local hits
    hits=$(jq -r 'length // 0' "$out" 2>/dev/null || echo "0")
    if [[ "$hits" -gt 0 ]]; then
        TOTAL_HITS=$((TOTAL_HITS + hits))
        {
            echo ""
            echo "### $id — $desc"
            echo ""
            echo "Reference: <$url>"
            echo ""
            jq -r '.[] | "- `" + .file + ":" + (.range.start.line|tostring) + "`"' "$out" 2>/dev/null
        } >> "$TMP_DIR/all_findings.md"
    fi
}

for rule in "${RULES[@]}"; do
    run_rule "$rule"
done

# Build final report
build_report() {
    {
        echo "# Phase 2 findings — Rustonomicon anti-patterns"
        echo ""
        echo "Generated $(date -u +%FT%TZ) by \`scripts/rustonomicon-antipatterns.sh\`"
        echo "Source: \`$SOURCE\`"
        echo "Ruleset: ${#RULES[@]} rules (each citing the Rustonomicon section that documents it as UB)"
        echo "Total hits: $TOTAL_HITS"
        echo ""
        if [[ "$TOTAL_HITS" -eq 0 ]]; then
            echo "**No Rustonomicon anti-pattern hits.** This is a strong signal but not a proof — the ruleset is finite. Continue to the bucket-level sweeps."
        else
            echo "Each hit below is a CANDIDATE finding. Confirm by:"
            echo "1. Reading the cited Rustonomicon section."
            echo "2. Verifying the surrounding code does NOT have a SAFETY comment that justifies the pattern."
            echo "3. Opening a Phase 5 experiment to demonstrate the UB under Miri."
            cat "$TMP_DIR/all_findings.md" 2>/dev/null
        fi
    }
}

if [[ -n "$OUTPUT" ]]; then
    build_report > "$OUTPUT"
    echo "Wrote $OUTPUT"
    echo "Total hits: $TOTAL_HITS"
else
    build_report
fi

if [[ "$TOTAL_HITS" -gt 0 ]]; then
    exit 1
fi
exit 0
