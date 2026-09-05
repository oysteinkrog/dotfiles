#!/usr/bin/env bash
# archive-workspace.sh — Archive the workspace directory at end-of-run.
#
# Creates a timestamped tarball at <project-parent>/<basename>-stash-janitor-workspace-<DATE>.tar.gz
# so the user has the full audit trail outside the repo.
#
# Does NOT delete the workspace (per AGENTS.md "no file deletion").
# The user can rm the workspace manually after the archive is in place.

set -euo pipefail

PROJECT="${1:?Usage: archive-workspace.sh <project-path>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
BASENAME="$(basename "$PROJECT_ABS")"
PARENT="$(dirname "$PROJECT_ABS")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
DATE_TAG="$(date -u +%Y-%m-%d_%H%M%S)"
ARCHIVE="$PARENT/${BASENAME}-stash-janitor-workspace-${DATE_TAG}.tar.gz"

if [[ ! -d "$WORKSPACE" ]]; then
  echo "ERROR: workspace not found at $WORKSPACE" >&2
  exit 1
fi

cd "$PROJECT_ABS"
tar -czf "$ARCHIVE" .stash_janitor_workspace/

echo "wrote $ARCHIVE"
# Portable size reporting. `du -b` is GNU-only (no BSD/macOS support), and the
# original `||` fallback never triggered because `awk '{print $1}'` exits 0
# even on empty input. `wc -c < file` is POSIX and always works; `du -h` is
# portable for the human-readable form (BSD du has -h since 10.x).
size_human=$({ \du -h "$ARCHIVE" 2>/dev/null | awk '{print $1}' ; } || true)
size_bytes=$(wc -c < "$ARCHIVE" 2>/dev/null || echo unknown)
size_bytes="${size_bytes// /}"   # strip leading whitespace BSD wc adds
echo "  Size: ${size_human:-?} (${size_bytes} bytes)"
echo
echo "The original workspace at $WORKSPACE is unchanged."
echo "If you want to remove it after confirming the archive is good:"
echo "  mv $WORKSPACE ${WORKSPACE}.removed-$DATE_TAG"
echo "(DCG may block 'rm -rf'; use 'mv' to a non-repo location.)"
