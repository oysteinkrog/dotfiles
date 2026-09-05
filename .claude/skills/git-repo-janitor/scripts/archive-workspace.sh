#!/usr/bin/env bash
# Archive workspace as a tarball at end-of-run.
# Usage: archive-workspace.sh <project>
set -euo pipefail

project="${1:?usage: archive-workspace.sh <project>}"
cd "$project"
ws=".repo_janitor_workspace"

[[ -d "$ws" ]] || { echo "no workspace to archive"; exit 0; }

ts=$(date -u +%Y%m%dT%H%M%SZ)
out="${ws}_archive_${ts}.tar.gz"
tar czf "$out" "$ws"
echo "archived to $out"
