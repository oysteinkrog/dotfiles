#!/usr/bin/env bash
# Phase 0: warn if repo is large (T4/T5) and suggest sub-tree partitioning.
# Usage: check-large-repo.sh <project>
set -euo pipefail

project="${1:?usage: check-large-repo.sh <project>}"
cd "$project"

file_count=$(git ls-files | wc -l)
echo "Tracked file count: $file_count"

if (( file_count > 100000 )); then
    echo ""
    echo "T5 — INDUSTRIAL MONOREPO. \`full\` mode strongly discouraged."
    echo ""
    echo "Recommendation: partition by sub-tree."
    echo ""
    echo "Top-level directories:"
    git ls-tree HEAD --name-only -d | head -10
    echo ""
    echo "Pick one to start with:"
    # `read -r` prevents backslash mangling in directory names.
    git ls-tree HEAD --name-only -d | head -10 | while IFS= read -r d; do
        sub_count=$(git ls-files "$d/" 2>/dev/null | wc -l)
        printf "  %-40s %s files\n" "$d/" "$sub_count"
    done
    echo ""
    echo "Then run: SUBTREE=<chosen-dir> /git-repo-janitor"
    exit 2
elif (( file_count > 20000 )); then
    echo ""
    echo "T4 — LARGE MONOREPO. Consider Comprehensive mode + Swarm orchestration."
    echo "  - Wall time estimate: 4-10 hours"
    echo "  - Bundle size estimate: hundreds of MB"
    echo "  - Multiple sessions may be needed"
    exit 0
elif (( file_count > 1000 )); then
    echo "T3 — mid-size repo. Standard mode + Squad orchestration recommended."
    exit 0
elif (( file_count > 100 )); then
    echo "T2 — single-language single-purpose repo. Pair orchestration recommended."
    exit 0
else
    echo "T1 — small repo. Solo orchestration is fine."
    exit 0
fi
