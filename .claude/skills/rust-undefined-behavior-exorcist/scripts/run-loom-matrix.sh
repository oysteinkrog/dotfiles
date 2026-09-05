#!/usr/bin/env bash
# run-loom-matrix.sh — run every #[cfg(loom)] test in the source repo.
#
# Usage: run-loom-matrix.sh <source-dir> <workspace> [test-filter]
# <workspace> must resolve under <source-dir>/.ub-exorcism/<run-id>/.
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

if [[ $# -lt 2 ]]; then
    echo "Usage: run-loom-matrix.sh <source-dir> <workspace> [test-filter]" >&2
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
LOGFILE="$WORKSPACE/phase3_raw/loom.log"

echo "=== loom matrix ==="
echo "  source: $SOURCE"
echo "  log:    $LOGFILE"

cd "$SOURCE"

# Find every test file containing #[cfg(loom)]
mapfile -t LOOM_TESTS < <(grep -rlE '#\[cfg\(loom\)\]' --include='*.rs' . 2>/dev/null | sort -u)

if [[ ${#LOOM_TESTS[@]} -eq 0 ]]; then
    echo "  No #[cfg(loom)] tests found in source tree."
    echo "  See subagents/loom-modeler.md for authoring a new model."
    exit 0
fi

printf '  Found %d loom test files:\n' "${#LOOM_TESTS[@]}"
printf '    %s\n' "${LOOM_TESTS[@]}"

# Loom runs serially by design; pass --test-threads=1 even though loom itself
# enforces this. The --release flag is recommended for any non-trivial model.
if RUSTFLAGS="--cfg loom" cargo +nightly test --release ${FILTER:+"$FILTER"} -- --test-threads=1 2>&1 | tee "$LOGFILE"; then
    echo "  [✓] loom matrix clean"
else
    echo "  [✗] loom matrix found a failing schedule (log: $LOGFILE)"
    exit 1
fi
