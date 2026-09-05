#!/usr/bin/env bash
# run-miri-matrix.sh — run Miri across the standard MIRIFLAGS matrix.
#
# Usage: run-miri-matrix.sh <source-dir> <workspace> [test-filter] [--paranoid|--strict-isolation]
#
# Every axis includes `-Zmiri-disable-isolation` by default. Without it,
# any project using chrono::Utc::now / getrandom / fs syscalls fails
# immediately with "unsupported operation: clock_gettime" etc. Use
# `--strict-isolation` if you specifically want to audit Miri's isolation
# sandbox (rare; mostly for `no_std` projects that should never hit the
# host kernel).
#
# Tees every config's output to <workspace>/phase3_raw/miri_<config>.log.
# <workspace> must resolve under <source-dir>/.ub-exorcism/<run-id>/.
# Reports a pass/fail summary at the end.
# Exits 1 if any Miri axis reports a non-clean result, after running every axis.
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

if [[ $# -lt 2 ]]; then
    echo "Usage: run-miri-matrix.sh <source-dir> <workspace> [test-filter] [--paranoid|--strict-isolation]" >&2
    exit 2
fi

SOURCE="$1"
WORKSPACE="$2"
shift 2

# Default isolation policy: DISABLED. This is the right choice for ~all
# Rust projects audited by this skill (any `chrono::Utc::now`,
# `std::time::SystemTime::now`, getrandom, or fs syscall hits Miri's
# isolation sandbox without it). To audit isolation conformance instead
# of UB conformance, pass `--strict-isolation`.
FILTER=""
ISOLATION_FLAG="-Zmiri-disable-isolation"
PARANOID_PASS="no"
for arg in "$@"; do
    case "$arg" in
        --strict-isolation) ISOLATION_FLAG="" ;;
        --paranoid)         PARANOID_PASS="yes" ;;
        --*)
            echo "Unknown flag: $arg" >&2
            echo "Usage: $0 <source-dir> <workspace> [test-filter] [--paranoid] [--strict-isolation]" >&2
            exit 64
            ;;
        *)
            if [[ -n "$FILTER" ]]; then
                echo "Only one positional filter supported (got: $FILTER and $arg)" >&2
                exit 64
            fi
            FILTER="$arg"
            ;;
    esac
done

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

FAILURES=0

run() {
    local label="$1"; shift
    local logfile="$WORKSPACE/phase3_raw/miri_${label}.log"
    echo "=== miri/${label} ==="
    if (cd "$SOURCE" && "$@" 2>&1 | tee "$logfile"); then
        echo "  [✓] miri/${label} clean (log: $logfile)"
    else
        echo "  [✗] miri/${label} found UB (log: $logfile)"
        FAILURES=$((FAILURES + 1))
    fi
}

# Each invocation is its own MIRIFLAGS axis. Running each separately makes the
# failing axis obvious in the unified summary. `$ISOLATION_FLAG` is prepended
# to every axis (default: `-Zmiri-disable-isolation`).
run default \
    env MIRIFLAGS="$ISOLATION_FLAG" \
    cargo +nightly miri test ${FILTER:+"$FILTER"}

run tree_borrows \
    env MIRIFLAGS="$ISOLATION_FLAG -Zmiri-tree-borrows" \
    cargo +nightly miri test ${FILTER:+"$FILTER"}

run strict_provenance \
    env MIRIFLAGS="$ISOLATION_FLAG -Zmiri-strict-provenance" \
    cargo +nightly miri test ${FILTER:+"$FILTER"}

run symbolic_alignment \
    env MIRIFLAGS="$ISOLATION_FLAG -Zmiri-symbolic-alignment-check" \
    cargo +nightly miri test ${FILTER:+"$FILTER"}

# Combined paranoid run — slow, useful for soaking
if [[ "$PARANOID_PASS" == "yes" ]]; then
    run paranoid \
        env MIRIFLAGS="$ISOLATION_FLAG -Zmiri-tree-borrows -Zmiri-strict-provenance -Zmiri-symbolic-alignment-check -Zmiri-ignore-leaks" \
        cargo +nightly miri test ${FILTER:+"$FILTER"}
fi

echo
echo "Done. Inspect logs in $WORKSPACE/phase3_raw/miri_*.log"
if [[ -z "$ISOLATION_FLAG" ]]; then
    echo "  (strict-isolation mode: chrono/getrandom/fs syscalls may have failed)"
fi
if [[ "$FAILURES" -gt 0 ]]; then
    echo "  $FAILURES Miri axis(es) reported a non-clean result."
    exit 1
fi
