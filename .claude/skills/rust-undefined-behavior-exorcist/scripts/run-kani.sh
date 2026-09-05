#!/usr/bin/env bash
# run-kani.sh — bounded model check via Kani for high-stakes findings.
#
# Usage: run-kani.sh <source-dir> <workspace> [harness-name]
# <workspace> must resolve under <source-dir>/.ub-exorcism/<run-id>/.
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

if [[ $# -lt 2 ]]; then
    echo "Usage: run-kani.sh <source-dir> <workspace> [harness-name]" >&2
    exit 2
fi

SOURCE="$1"
WORKSPACE="$2"
HARNESS="${3:-}"

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

if ! command -v cargo-kani >/dev/null 2>&1; then
    echo "kani not installed. Install via: cargo install --locked kani-verifier" >&2
    echo "Then run: cargo kani setup" >&2
    exit 127
fi

cd "$SOURCE"

LOG="$WORKSPACE/phase3_raw/kani${HARNESS:+_${HARNESS}}.log"

echo "=== kani${HARNESS:+ (harness: $HARNESS)} ==="
if [[ -n "$HARNESS" ]]; then
    if cargo kani --harness "$HARNESS" 2>&1 | tee "$LOG"; then
        echo "  [✓] kani harness $HARNESS verified (log: $LOG)"
    else
        echo "  [✗] kani found a counter-example (log: $LOG)"
        exit 1
    fi
else
    if cargo kani 2>&1 | tee "$LOG"; then
        echo "  [✓] all kani harnesses verified"
    else
        echo "  [✗] kani found a counter-example (log: $LOG)"
        exit 1
    fi
fi
