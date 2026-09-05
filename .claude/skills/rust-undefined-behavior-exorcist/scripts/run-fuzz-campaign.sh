#!/usr/bin/env bash
# run-fuzz-campaign.sh — run one bounded cargo-fuzz campaign per target.
#
# Usage: run-fuzz-campaign.sh <source-dir> <workspace> [target-name] [seconds]
#
# If target-name is omitted, runs every target with the given budget each.
# Default per-target budget: 600s (10 min). For Phase 11 soak, pass 86400 (24h).
# <workspace> must resolve under <source-dir>/.ub-exorcism/<run-id>/.
# Exits 1 if any target crashes or fails, after running every selected target.
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

if [[ $# -lt 2 ]]; then
    echo "Usage: run-fuzz-campaign.sh <source-dir> <workspace> [target-name] [seconds]" >&2
    exit 2
fi

SOURCE="$1"
WORKSPACE="$2"
TARGET="${3:-}"
BUDGET="${4:-600}"

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
mkdir -p "$WORKSPACE/phase3_raw/fuzz_artifacts"

cd "$SOURCE"

if [[ ! -d fuzz ]]; then
    echo "No fuzz/ directory in $SOURCE. Initialize with: cd $SOURCE && cargo +nightly fuzz init"
    exit 1
fi

# List targets without parsing `ls`; file names can contain whitespace even if
# cargo-fuzz target names normally should not.
TARGETS=()
while IFS= read -r -d '' target_path; do
    target_name="$(basename "$target_path" .rs)"
    TARGETS+=("$target_name")
done < <(find fuzz/fuzz_targets -maxdepth 1 -type f -name '*.rs' -print0 2>/dev/null | sort -z)

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "No fuzz targets found in fuzz/fuzz_targets/. Author one (see subagents/fuzz-author-and-runner.md)."
    exit 1
fi

if [[ -n "$TARGET" ]]; then
    TARGETS=("$TARGET")
fi

FAILURES=0

for tgt in "${TARGETS[@]}"; do
    art_dir="$WORKSPACE/phase3_raw/fuzz_artifacts/${tgt}"
    log="$WORKSPACE/phase3_raw/fuzz_${tgt}.log"
    mkdir -p "$art_dir"
    echo "=== fuzz target: $tgt (budget ${BUDGET}s) ==="
    if cargo +nightly fuzz run "$tgt" -- \
        -max_total_time="$BUDGET" -timeout=5 \
        -artifact_prefix="$art_dir/" 2>&1 | tee "$log"; then
        echo "  [✓] $tgt completed cleanly"
    else
        echo "  [✗] $tgt found crashes (artifacts in $art_dir/)"
        FAILURES=$((FAILURES + 1))
    fi
done

echo
echo "Done. Inspect logs + artifacts under $WORKSPACE/phase3_raw/"
if [[ "$FAILURES" -gt 0 ]]; then
    echo "  $FAILURES fuzz target(s) reported crashes or failures."
    exit 1
fi
