#!/usr/bin/env bash
# Capture working-tree state for drift detection.
# Usage: snapshot-tree.sh <project> <phase-tag>
set -euo pipefail

project="${1:?usage: snapshot-tree.sh <project> <phase-tag>}"
tag="${2:?missing phase-tag}"

cd "$project"
ws=".repo_janitor_workspace"
mkdir -p "$ws"

out="$ws/wt_${tag}.txt"
{
    echo "# snapshot @ $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# tag=$tag"
    echo "## git status (porcelain)"
    git status --porcelain
    echo "## git rev-parse HEAD"
    git rev-parse HEAD
    echo "## git symbolic-ref HEAD"
    git symbolic-ref HEAD 2>/dev/null || echo "(detached)"
    echo "## untracked count"
    # `grep -c` always prints the count (even 0) but exits 1 when count is 0;
    # `|| true` suppresses the non-zero exit without producing duplicate output.
    git status --porcelain | grep -c '^??' || true
    echo "## modified count"
    git status --porcelain | grep -c '^.M' || true
} > "$out"

echo "snapshot saved to $out"
