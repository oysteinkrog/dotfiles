#!/usr/bin/env bash
# miri-unsupported-extract.sh — extract "unsupported operation" errors from
# Miri output and group them so MIRI-SHIMS.md can be applied in priority order.
#
# Two invocations:
#   (1) Filter mode: `cargo +nightly miri test 2>&1 | miri-unsupported-extract.sh`
#   (2) Workspace mode: `miri-unsupported-extract.sh <workspace>`
#       — scans every $workspace/phase3_raw/miri_*.log and aggregates.
#
# Output: a sorted-by-frequency table of (count, operation) so the orchestrator
# knows which shim to author first. Routes each unique op to its MIRI-SHIMS.md
# recipe (named by operation root, e.g., "libc::write" → "Filesystem I/O shim").
#
# Exit codes:
#   0 — extraction completed (zero or more ops surfaced)
#   2 — usage error / no input
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

# Operation → shim recipe mapping (from MIRI-SHIMS.md). Extend here as new
# shim recipes are added.
shim_for() {
    local op="$1"
    # Filesystem aliases intentionally overlap (`read` covers `readdir`, `stat`
    # covers `lstat`/`fstat`) and all route to the same recipe.
    # shellcheck disable=SC2221,SC2222
    case "$op" in
        # Inline asm
        *llvm.x86*|*llvm.aarch64*|*asm!*|*inline_asm*)
            echo "Inline asm shim — see MIRI-SHIMS.md §Asm (or feature-flag out of Miri)" ;;
        # SIMD intrinsics
        *_mm_*|*simd_*|*_mm256_*|*_mm512_*)
            echo "SIMD intrinsic shim — see MIRI-SHIMS.md §SIMD (or feature-flag portable_simd path)" ;;
        # FFI / dlopen / dlsym. Keep before filesystem: dlopen/dlclose contain
        # "open"/"close" and otherwise get misrouted to FS-IO.
        *dlopen*|*dlsym*|*dlclose*|*extern_static*)
            echo "FFI shim — see MIRI-SHIMS.md §FFI" ;;
        # Networking
        *socket*|*bind*|*connect*|*accept*|*send*|*recv*|*getaddrinfo*)
            echo "Network shim — see MIRI-SHIMS.md §Network" ;;
        # Time / random / clock
        *clock_gettime*|*gettimeofday*|*time*|*nanosleep*|*sleep*|*getrandom*)
            echo "Disable-isolation OR time/randomness shim — see MIRI-SHIMS.md §Time-Random" ;;
        # Threading / sync. Keep before filesystem: pthread contains "read".
        # Keep unpark before park so the more specific operation wins.
        *pthread*|*futex*|*atomic_*|*unpark*|*park*)
            echo "Threading shim — see MIRI-SHIMS.md §Threading (may require loom instead)" ;;
        # Filesystem
        *write*|*read*|*open*|*close*|*stat*|*lstat*|*fstat*|*unlink*|*mkdir*|*rmdir*|*rename*|*readdir*)
            echo "Filesystem I/O shim — see MIRI-SHIMS.md §FS-IO" ;;
        # Catch-all
        *)
            echo "No shim recipe documented yet for this op; add one to MIRI-SHIMS.md" ;;
    esac
}

# Gather input lines from stdin OR from $workspace/phase3_raw/miri_*.log
gather_input() {
    if [[ $# -eq 0 ]]; then
        # stdin mode
        cat
        return
    fi
    local workspace_real
    workspace_real="$(realpath -m "$1")"
    case "$workspace_real" in
        */.ub-exorcism/*) ;;
        *)
            echo "Workspace must be inside <source>/.ub-exorcism/<run-id>" >&2
            echo "Got: $workspace_real" >&2
            exit 2
            ;;
    esac
    if [[ ! -d "$workspace_real/phase3_raw" ]]; then
        echo "No phase3_raw/ in $workspace_real — run scripts/run-miri-matrix.sh first" >&2
        exit 2
    fi
    # `cat phase3_raw/miri_*.log` would fail under `set -euo pipefail` when the
    # glob matches nothing (bash passes the literal pattern to cat which exits 1
    # — the command substitution propagates that and the script dies silently).
    # Use compgen so the no-match case becomes "empty stdout, exit 0" instead.
    if ! compgen -G "$workspace_real/phase3_raw/miri_*.log" >/dev/null; then
        echo "No miri_*.log files under $workspace_real/phase3_raw/ — run scripts/run-miri-matrix.sh first" >&2
        exit 2
    fi
    cat "$workspace_real"/phase3_raw/miri_*.log
}

INPUT="$(gather_input "$@")"

if [[ -z "$INPUT" ]]; then
    echo "No input received (empty stdin or empty miri_*.log files)" >&2
    exit 2
fi

# Extract op names. Miri's format is:
#   error: unsupported operation: can't call foreign function `libc::write`
# We capture the symbol after "unsupported operation:" and "foreign function `...`"
# OR after "unsupported operation:" alone for non-FFI ops.
EXTRACTED="$(
    echo "$INPUT" \
        | grep -E 'unsupported operation:' \
        | sed -E "
            s/.*foreign function .([a-zA-Z0-9_:]+)..*/\1/;
            s/.*unsupported operation: ([^[:space:]]+).*/\1/;
            t
            d
          " \
        | sort
)"

if [[ -z "$EXTRACTED" ]]; then
    echo "(no 'unsupported operation:' lines found in input)" >&2
    exit 0
fi

# Group + count
echo "=== Miri unsupported operations (sorted by frequency) ==="
echo "$EXTRACTED" \
    | uniq -c \
    | sort -rn \
    | while read -r count op; do
        recipe="$(shim_for "$op")"
        printf '%6d   %-40s  →  %s\n' "$count" "$op" "$recipe"
    done

echo
echo "Apply shim recipes in priority order (most-frequent first) per MIRI-SHIMS.md."
exit 0
