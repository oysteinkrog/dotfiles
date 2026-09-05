#!/usr/bin/env bash
# snapshot-tree.sh — Capture working-tree state for working-tree-drift detection.
#
# Usage: snapshot-tree.sh <project-path> [tag]
#   tag defaults to "phase0"; can be e.g. "pre_apply_034" or "phase6_n42"
#
# Output: <workspace>/wt_<tag>.txt with --porcelain=v2 status, diff stat, and
#         staged diff stat. The diff between two snapshots tells you what
#         appeared during the run.

set -euo pipefail

PROJECT="${1:?Usage: snapshot-tree.sh <project-path> [tag]}"
TAG="${2:-phase0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

# Refuse to run on a non-git directory. Without this check, snapshot-tree
# silently produces a workspace + a snapshot file with empty git output for
# every section — looking valid but containing no real data. The user might
# rely on the snapshot for working-tree-drift detection and never realize
# they're comparing against empty.
PROJECT_ABS="$(resolve_project_root "$PROJECT")"

WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
mkdir -p "$WORKSPACE"
OUT="$WORKSPACE/wt_${TAG}.txt"

{
  printf '## working-tree snapshot\n'
  printf 'project=%s\n' "$PROJECT_ABS"
  printf 'tag=%s\n' "$TAG"
  printf 'timestamp=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'head=%s\n' "$(git -C "$PROJECT_ABS" rev-parse HEAD 2>/dev/null || echo unknown)"
  printf 'branch=%s\n' "$(git -C "$PROJECT_ABS" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  # Exclude the skill's own workspace from every status/diff/untracked listing.
  # The point of these snapshots is to detect concurrent-agent activity on
  # PROJECT files between phases. Without the exclude, .stash_janitor_workspace/
  # artifacts (inventory.tsv, triage.tsv, apply_log.tsv, conflicts/, etc.)
  # appear as ?? entries in every snapshot and grow each phase, swamping the
  # actual concurrent-agent signal with skill-internal noise.
  printf '\n## status --porcelain=v2 --branch\n'
  git -C "$PROJECT_ABS" status --porcelain=v2 --branch -- . ':(exclude).stash_janitor_workspace' 2>/dev/null || true
  printf '\n## diff --stat (working tree)\n'
  git -C "$PROJECT_ABS" diff --stat -- . ':(exclude).stash_janitor_workspace' 2>/dev/null || true
  printf '\n## diff --staged --stat\n'
  git -C "$PROJECT_ABS" diff --staged --stat -- . ':(exclude).stash_janitor_workspace' 2>/dev/null || true
  printf '\n## untracked files (top-level)\n'
  # `head -50` closes its stdin after 50 lines, which SIGPIPEs git ls-files
  # (exits 141). Under `set -euo pipefail` that aborts the brace block. Use
  # `sed -n '1,50p'` (reads all stdin, prints only 1..50) to avoid SIGPIPE,
  # plus `|| true` as belt-and-suspenders against any other failure mode.
  { git -C "$PROJECT_ABS" ls-files --others --exclude-standard -- . ':(exclude).stash_janitor_workspace' 2>/dev/null \
      | sed -n '1,50p' ; } || true
} > "$OUT"

echo "wrote $OUT"

# If a phase0 snapshot exists, optionally show what changed since then
if [[ "$TAG" != "phase0" && -f "$WORKSPACE/wt_phase0.txt" ]]; then
  echo
  echo "Diff against phase0 snapshot:"
  diff -u "$WORKSPACE/wt_phase0.txt" "$OUT" | head -30 || true
fi
