#!/usr/bin/env bash
# run-sanitizer-matrix.sh — run cargo test under each LLVM sanitizer.
#
# Usage: run-sanitizer-matrix.sh <source-dir> <workspace> [test-filter]
#
# Sanitizers are mutually exclusive in a single build; runs them sequentially,
# each into its own log. TSan uses --test-threads=1.
# <workspace> must resolve under <source-dir>/.ub-exorcism/<run-id>/.
# Exits 1 if any sanitizer axis reports a non-clean result, after running every axis.
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

if [[ $# -lt 2 ]]; then
    echo "Usage: run-sanitizer-matrix.sh <source-dir> <workspace> [test-filter]" >&2
    exit 2
fi

SOURCE="$1"
WORKSPACE="$2"
FILTER="${3:-}"

canonicalize_workspace() {
    local source_real workspace_real
    source_real="$(cd "$SOURCE" && pwd -P)"
    case "$WORKSPACE" in
        /*) workspace_real="$(realpath -m "$WORKSPACE")" ;;
        *)  workspace_real="$(realpath -m "$source_real/$WORKSPACE")" ;;
    esac
    case "$workspace_real" in
        "$source_real"/.ub-exorcism/*) WORKSPACE="$workspace_real" ;;
        *)
            echo "Workspace must be inside source: <source>/.ub-exorcism/<run-id>" >&2
            echo "Source: $source_real" >&2
            echo "Got:    $workspace_real" >&2
            exit 64
            ;;
    esac
}

canonicalize_workspace
mkdir -p "$WORKSPACE/phase3_raw"

TARGET="${SANITIZER_TARGET:-x86_64-unknown-linux-gnu}"
FAILURES=0

run() {
    local label="$1"; shift
    local logfile="$WORKSPACE/phase3_raw/${label}.log"
    echo "=== sanitizer/${label} ==="
    if (cd "$SOURCE" && "$@" 2>&1 | tee "$logfile"); then
        echo "  [✓] sanitizer/${label} clean (log: $logfile)"
    else
        echo "  [✗] sanitizer/${label} flagged issues (log: $logfile)"
        FAILURES=$((FAILURES + 1))
    fi
}

# AddressSanitizer
run asan \
    env RUSTFLAGS="-Zsanitizer=address -Z sanitizer-recover=address -C panic=abort" \
    RUSTDOCFLAGS="-Zsanitizer=address" \
    cargo +nightly test --target "$TARGET" ${FILTER:+"$FILTER"}

# ThreadSanitizer — CRITICAL: --test-threads=1
run tsan \
    env RUSTFLAGS="-Zsanitizer=thread" \
    cargo +nightly test --target "$TARGET" ${FILTER:+"$FILTER"} -- --test-threads=1

# MemorySanitizer — needs std rebuilt
if [[ "${SKIP_MSAN:-no}" != "yes" ]]; then
    run msan \
        env RUSTFLAGS="-Zsanitizer=memory -C target-cpu=x86-64 -Z build-std" \
        cargo +nightly test --target "$TARGET" ${FILTER:+"$FILTER"} -- --test-threads=1
fi

# LeakSanitizer
run lsan \
    env RUSTFLAGS="-Zsanitizer=leak" \
    cargo +nightly test --target "$TARGET" ${FILTER:+"$FILTER"}

echo
echo "Done. Inspect logs in $WORKSPACE/phase3_raw/{asan,tsan,msan,lsan}.log"
echo "  (TSan + --test-threads=1 used; MSAN built std from source — slow first run)"
if [[ "$FAILURES" -gt 0 ]]; then
    echo "  $FAILURES sanitizer axis(es) reported a non-clean result."
    exit 1
fi
