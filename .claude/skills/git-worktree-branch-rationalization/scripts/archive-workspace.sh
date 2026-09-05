#!/usr/bin/env bash
# archive-workspace.sh — Phase 11+: archive the workspace at end-of-run.
#
# Tarballs <project>/.worktree_branch_rationalization_workspace/ to a sibling
# location at <project-parent>/<basename>-rationalization-workspace-<DATE>.tar.gz
# so the user has a portable audit trail for resumability and bug reports.
#
# Per AGENTS.md Rule 1, this script NEVER deletes the workspace. The user can
# `mv` it to a trash location after verifying the tarball is good.
#
# Idempotent: if a tarball with the same date already exists, append a numeric
# suffix and keep going (so re-running on the same day produces -1, -2, etc.).
#
# Records the tarball path in the handoff report under "## Workspace archive"
# (best-effort; only when handoff_report.md exists).
#
# Exit codes:
#   0  archive written (or already current)
#   2  not a git work tree
#   3  workspace dir absent (nothing to archive)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: archive-workspace.sh <project-path>

Phase 11+. Archives the workspace dir to a tarball at
<project-parent>/<basename>-rationalization-workspace-<DATE>.tar.gz.
Idempotent: a colliding name gains a numeric -N suffix.

Per AGENTS.md Rule 1, never deletes the workspace. The user manages
workspace lifecycle after verifying the tarball.

Env:
  WORKSPACE   Workspace dir override.

Exit codes:
  0  archive written or current
  2  not a git work tree
  3  workspace absent
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
BASENAME="$(basename "$PROJECT_ABS")"
PARENT="$(dirname "$PROJECT_ABS")"
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"

if [[ ! -d "$WORKSPACE_DIR" ]]; then
  echo "ERROR: workspace not found at $WORKSPACE_DIR" >&2
  exit 3
fi
if [[ "$WORKSPACE_DIR" == "/" || "$WORKSPACE_DIR" == "$PROJECT_ABS" ]]; then
  echo "ERROR: refusing to archive suspicious workspace path: $WORKSPACE_DIR" >&2
  echo "WORKSPACE must point at the rationalization workspace, not / or the repo root." >&2
  exit 3
fi

DATE_TAG="$(date -u +%Y-%m-%d)"
BASE_NAME="${BASENAME}-rationalization-workspace-${DATE_TAG}"
ARCHIVE="$PARENT/${BASE_NAME}.tar.gz"

# Idempotent name selection. If <name>.tar.gz exists, try <name>-1.tar.gz,
# then <name>-2.tar.gz, etc.
suffix=0
while [[ -e "$ARCHIVE" ]]; do
  suffix=$((suffix + 1))
  ARCHIVE="$PARENT/${BASE_NAME}-${suffix}.tar.gz"
  # Defensive bound — re-running 1000 times in one day is pathological.
  if [[ "$suffix" -gt 999 ]]; then
    echo "ERROR: cannot find a free archive name in $PARENT (gave up at $suffix)" >&2
    exit 3
  fi
done

# Workspace dir must be enumerated relative to PROJECT_ABS so the tarball's
# top-level entry is just `.worktree_branch_rationalization_workspace/`. If
# the user supplied a custom WORKSPACE outside the repo, fall back to absolute.
WS_NAME=$(basename "$WORKSPACE_DIR")
if [[ "$WORKSPACE_DIR" == "$PROJECT_ABS/$WS_NAME" ]]; then
  ( cd "$PROJECT_ABS" && tar -czf "$ARCHIVE" "$WS_NAME" )
else
  # Custom WORKSPACE override — chdir to its parent for a tidy entry path.
  WS_PARENT=$(dirname "$WORKSPACE_DIR")
  ( cd "$WS_PARENT" && tar -czf "$ARCHIVE" "$WS_NAME" )
fi

# Portable size reporting.
size_bytes=$(wc -c < "$ARCHIVE" 2>/dev/null || echo unknown)
size_bytes="${size_bytes// /}"
size_human=$(du -h "$ARCHIVE" 2>/dev/null | awk '{print $1}' || echo "?")

echo "wrote $ARCHIVE"
echo "  size: ${size_human:-?} (${size_bytes} bytes)"

# Best-effort: append a "## Workspace archive" section to the handoff report
# if it exists. Use Edit-style append (printf >>); never sed/awk-mutate.
HANDOFF="$WORKSPACE_DIR/handoff_report.md"
if [[ -f "$HANDOFF" ]]; then
  if ! grep -qE '^## Workspace archive' "$HANDOFF"; then
    {
      printf '\n## Workspace archive\n\n'
      printf -- '- path: `%s`\n' "$ARCHIVE"
      printf -- '- size: %s (%s bytes)\n' "$size_human" "$size_bytes"
      printf -- '- created: %s\n' "$(date -u +%FT%TZ)"
      printf '\n'
      printf 'The workspace at `%s` is unchanged.\n' "$WORKSPACE_DIR"
      printf 'After verifying the tarball, you can `mv` (not `rm`) the workspace to a trash location.\n'
    } >> "$HANDOFF"
    log "Appended ## Workspace archive section to $HANDOFF"
  else
    # The section exists from a prior run; append a "newer archive" pointer
    # rather than rewriting the existing section.
    {
      printf '\n### Additional archive (re-run on %s)\n\n' "$DATE_TAG"
      printf -- '- path: `%s`\n' "$ARCHIVE"
      printf -- '- size: %s (%s bytes)\n' "$size_human" "$size_bytes"
    } >> "$HANDOFF"
    log "Appended ### Additional archive subsection to $HANDOFF"
  fi
fi

echo
echo "The workspace at $WORKSPACE_DIR is unchanged."
echo "If you want to remove it after confirming the archive:"
removed_path="${WORKSPACE_DIR}.removed-$(date -u +%Y%m%d-%H%M%S)"
printf '  mv -- %q %q\n' "$WORKSPACE_DIR" "$removed_path"
echo "(DCG blocks rm -rf; mv to a non-repo location is the safe pattern.)"
exit 0
