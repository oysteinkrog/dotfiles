#!/usr/bin/env bash
# Verify that recovery recipes actually work on a sample candidate.
# Usage: recovery-test.sh <project> <bundle-path>
set -euo pipefail

project="${1:?usage: recovery-test.sh <project> <bundle-path>}"
bundle="${2:?missing bundle-path}"

project_root="$(git -C "$project" rev-parse --show-toplevel)"
cd "$project_root"
project="$project_root"

case "$bundle" in
    /*) bundle_abs="$(realpath -m "$bundle")" ;;
    *) bundle_abs="$(realpath -m "$project/$bundle")" ;;
esac
case "$bundle_abs" in
    "$project"/*) ;;
    *)
        echo "ERROR: bundle path must be inside the project: $bundle" >&2
        exit 2
        ;;
esac
bundle="$bundle_abs"

# Pick a sample candidate
ws=".repo_janitor_workspace"
[[ -d "$ws" ]] || { echo "ERROR: $ws not found; run the earlier repo-janitor phases first" >&2; exit 2; }
sample=$(tail -n +2 "$ws/candidates.tsv" | head -1 | awk -F'\t' '{print $3}')
[[ -z "$sample" ]] && { echo "no candidates to test"; exit 0; }
case "$sample" in
    ""|/*|../*|*/../*)
        echo "ERROR: sample candidate path must be repo-relative and cannot escape: $sample" >&2
        exit 2
        ;;
esac

# Write to a temp dir and verify byte-equality
tmp=$(mktemp -d -t repo-janitor-recovery-test-XXXX)
cp "$bundle/working-tree-copies/$sample" "$tmp/recovered"
live_hash=$(sha256sum "$sample" | awk '{print $1}')
recovered_hash=$(sha256sum "$tmp/recovered" | awk '{print $1}')

if [[ "$live_hash" == "$recovered_hash" ]]; then
    echo "recovery test PASS for sample: $sample (hash=$live_hash)"
    echo "temp recovery copy left at: $tmp/recovered"
    exit 0
else
    echo "recovery test FAIL for sample: $sample"
    echo "  live:      $live_hash"
    echo "  recovered: $recovered_hash"
    echo "  temp copy:  $tmp/recovered"
    exit 1
fi
