#!/usr/bin/env bash
# Phase 3 gate: byte-equality + sha256 hash verification.
# Usage: verify-bundle.sh <project> <bundle-path>
set -euo pipefail

project="${1:?usage: verify-bundle.sh <project> <bundle-path>}"
bundle="${2:?missing bundle-path}"

project_root="$(git -C "$project" rev-parse --show-toplevel)"
cd "$project_root"
project="$project_root"
ws=".repo_janitor_workspace"
log="$project/$ws/bundle_verification.log"

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
mkdir -p "$ws"

mismatches=0
verified=0

while IFS=$'\t' read -r id _blob_sha path _size _mtime _smell _first_sha has_lfs content_hash; do
    [[ "$id" == "id" ]] && continue
    [[ "$id" == \#* ]] && continue
    [[ -z "$id" ]] && continue
    case "$path" in
        ""|/*|../*|*/../*)
            echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) BAD-PATH  $path  (candidate path escapes repo)" >> "$log"
            mismatches=$((mismatches + 1))
            continue
            ;;
    esac

    src="$path"
    dst="$bundle/working-tree-copies/$path"

    if [[ ! -f "$src" ]]; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) MISSING-LIVE  $path  (file gone from working tree)" >> "$log"
        mismatches=$((mismatches + 1))
        continue
    fi
    if [[ ! -f "$dst" ]]; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) MISSING-BUNDLE  $path  (bundle copy missing)" >> "$log"
        mismatches=$((mismatches + 1))
        continue
    fi

    if [[ "$has_lfs" == "true" ]]; then
        # For LFS, the live file is the pointer; the bundle copy is the smudged blob.
        # Compare the bundle copy hash against the recorded content_hash only.
        actual_hash=$(sha256sum "$dst" | awk '{print $1}')
        if [[ "$actual_hash" == "$content_hash" ]]; then
            echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) OK-LFS  $path  (bundle=$actual_hash)" >> "$log"
            verified=$((verified + 1))
        else
            echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) MISMATCH-LFS  $path  bundle=$actual_hash recorded=$content_hash" >> "$log"
            mismatches=$((mismatches + 1))
        fi
    else
        # Plain file: live and bundle should match exactly
        live_hash=$(sha256sum "$src" | awk '{print $1}')
        bundle_hash=$(sha256sum "$dst" | awk '{print $1}')

        if [[ "$live_hash" == "$bundle_hash" ]] && [[ "$live_hash" == "$content_hash" ]]; then
            echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) OK  $path  ($live_hash)" >> "$log"
            verified=$((verified + 1))
        else
            echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) MISMATCH  $path  live=$live_hash bundle=$bundle_hash recorded=$content_hash" >> "$log"
            mismatches=$((mismatches + 1))
        fi
    fi
done < "$bundle/index.tsv"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) SUMMARY  verified=$verified mismatches=$mismatches" >> "$log"

if [[ "$mismatches" -gt 0 ]]; then
    echo "FAIL: $mismatches mismatches" >&2
    exit 1
fi

echo "verified $verified candidates"
