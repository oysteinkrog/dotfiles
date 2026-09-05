#!/usr/bin/env bash
# Phase 7: apply a delete via git rm. Pre-condition: cleanup_authorization.txt
# must already contain the user's verbatim authorization.
# Usage: apply-delete.sh <project> <path1> [path2 ...]
set -euo pipefail

project="${1:?usage: apply-delete.sh <project> <path1> [path2 ...]}"
shift
cd "$project"

ws=".repo_janitor_workspace"
[[ -f "$ws/cleanup_authorization.txt" ]] || {
    echo "ERROR: $ws/cleanup_authorization.txt missing — Phase 7 requires verbatim user authorization" >&2
    exit 1
}

for path in "$@"; do
    if git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
        git rm "$path"
    else
        echo "INFO: $path not tracked (already removed?); skipping"
    fi
done

echo "deletes staged for $#  paths"
echo "(commit not yet made; run gates first, then commit)"
