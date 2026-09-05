#!/usr/bin/env bash
# workspace-export.sh — Phase 11+: portable export of the workspace + bundle.
#
# Bundles:
#   <project-root>/.worktree_branch_rationalization_workspace/   — workspace
#   <project-parent>/<basename>-branch-worktree-archive-<DATE>/   — bundle
# plus a manifest describing both, into a single zstd-compressed tarball at
#   <project-parent>/<basename>-rationalization-export-<DATE>.tar.zst
#
# Falls back to .tar.gz when zstd is not on PATH.
#
# Used for cross-machine resume / external audit. The tarball includes
# absolute path manifests + a tools-version capture so the receiving machine
# knows what `git`, `zstd`, and bash version produced the export.
#
# Per AGENTS.md Rule 1, this script NEVER deletes the source workspace or
# bundle. With WORKSPACE_EXPORT_ARCHIVE_SOURCE_OK=1 the source dirs are MOVED
# (`mv`) to <workspace>/.archived/source-<UTC> AFTER the tarball is verified
# — never `rm -rf`'d. This is opt-in only.
#
# Idempotent: a colliding name gains a numeric -N suffix.
#
# Exit codes:
#   0  export written
#   2  preflight failed (workspace / bundle missing)
#   3  filesystem write failed

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: workspace-export.sh <project-path>

Phase 11+. Exports workspace + bundle as a portable zstd-compressed tarball
at <project-parent>/<basename>-rationalization-export-<DATE>.tar.zst.
Falls back to .tar.gz when zstd is unavailable.

Idempotent: colliding names gain -1, -2, ... suffixes.

Per AGENTS.md Rule 1: source dirs are NEVER deleted. With
WORKSPACE_EXPORT_ARCHIVE_SOURCE_OK=1 the source dirs are moved (\`mv\`) to
<workspace>/.archived/source-<UTC> AFTER tarball verification.

Env:
  WORKSPACE                              Workspace dir override.
  WORKSPACE_EXPORT_ARCHIVE_SOURCE_OK=1   Move source dirs into .archived after export.

Exit codes:
  0  export written
  2  preflight failed
  3  filesystem write failed
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
BUNDLE_PATH_FILE="$WORKSPACE_DIR/bundle_path.txt"

[[ -d "$WORKSPACE_DIR" ]] || { echo "ERROR: workspace $WORKSPACE_DIR missing" >&2; exit 2; }
[[ -f "$BUNDLE_PATH_FILE" ]] || { echo "ERROR: $BUNDLE_PATH_FILE missing" >&2; exit 2; }
BUNDLE="$(cat "$BUNDLE_PATH_FILE")"
[[ -d "$BUNDLE" ]] || { echo "ERROR: bundle $BUNDLE missing" >&2; exit 2; }

DATE_TAG=$(date -u +%Y-%m-%d)
HAVE_ZSTD=0
EXT="tar.gz"
if command -v zstd >/dev/null 2>&1; then
  HAVE_ZSTD=1
  EXT="tar.zst"
fi
BASE_NAME="${BASENAME}-rationalization-export-${DATE_TAG}"
EXPORT_PATH="$PARENT/${BASE_NAME}.${EXT}"
suffix=0
while [[ -e "$EXPORT_PATH" ]]; do
  suffix=$((suffix + 1))
  EXPORT_PATH="$PARENT/${BASE_NAME}-${suffix}.${EXT}"
  if [[ "$suffix" -gt 999 ]]; then
    echo "ERROR: cannot find a free export name in $PARENT" >&2
    exit 3
  fi
done

# Build a staging directory outside the trees being copied. If staging lives
# inside WORKSPACE_DIR, `cp -a "$WORKSPACE_DIR" "$STAGING/workspace"` tries to
# copy the workspace into its own descendant and fails or recurses.
STAGING="$PARENT/.${BASE_NAME}.export-staging-$DATE_TAG-$$"
mkdir -p "$STAGING"
STAGING_ARCHIVED=""

archive_staging() {
  if [[ -d "$STAGING" ]]; then
    # Move (never rm) to .archived per Rule 1 — preserves the manifest if
    # tarball construction failed and the user wants to inspect.
    local ARCH dest suffix
    ARCH="$WORKSPACE_DIR/.archived"
    mkdir -p "$ARCH"
    dest="$ARCH/$(basename "$STAGING")"
    suffix=0
    while [[ -e "$dest" ]]; do
      suffix=$((suffix + 1))
      dest="$ARCH/$(basename "$STAGING")-$suffix"
    done
    if mv "$STAGING" "$dest" 2>/dev/null; then
      STAGING_ARCHIVED="$dest"
    fi
  fi
}
trap archive_staging EXIT

# Manifest.
MANIFEST="$STAGING/MANIFEST.md"
{
  printf '# Rationalization export manifest\n\n'
  printf "Project:     \`%s\`\n" "$PROJECT_ABS"
  printf "Basename:    \`%s\`\n" "$BASENAME"
  printf 'Exported:    %s\n' "$(date -u +%FT%TZ)"
  printf "Workspace:   \`%s\`\n" "$WORKSPACE_DIR"
  printf "Bundle:      \`%s\`\n\n" "$BUNDLE"
  printf '## Compression\n\n'
  printf -- '- format: %s\n' "$EXT"
  if [[ "$HAVE_ZSTD" -eq 1 ]]; then
    printf -- '- tool: %s\n' "$(zstd --version 2>&1 | head -1)"
  else
    printf -- '- tool: gzip (zstd unavailable)\n'
  fi
  printf '\n## Tools (capturing reproduction context)\n\n'
  printf -- "- bash: \`%s\`\n" "${BASH_VERSION:-unknown}"
  printf -- "- git: \`%s\`\n" "$(git --version 2>/dev/null || echo unknown)"
  printf -- "- tar: \`%s\`\n" "$(tar --version 2>/dev/null | head -1 || echo unknown)"
  printf -- "- uname: \`%s\`\n\n" "$(uname -srm 2>/dev/null || echo unknown)"
  printf '## Layout inside the tarball\n\n'
  printf -- "- \`workspace/\` — copy of \`%s\`\n" "$WORKSPACE_DIR"
  printf -- "- \`bundle/\`    — copy of \`%s\`\n" "$BUNDLE"
  printf -- "- \`MANIFEST.md\` — this file\n"
  printf -- "- \`RECEIVE.md\` — instructions for the receiving machine\n\n"
  printf '## Sizes (du -sh)\n\n'
  printf -- '- workspace: %s\n' "$(du -sh "$WORKSPACE_DIR" 2>/dev/null | awk '{print $1}' || echo unknown)"
  printf -- '- bundle:    %s\n' "$(du -sh "$BUNDLE" 2>/dev/null | awk '{print $1}' || echo unknown)"
} > "$MANIFEST"

# Receive instructions on the target side.
RECEIVE="$STAGING/RECEIVE.md"
cat > "$RECEIVE" <<'RECEIVE_EOF'
# Receiving the rationalization export

This tarball contains a portable export of a git-worktree-branch-rationalization
run. Layout:

  workspace/   — the in-repo .worktree_branch_rationalization_workspace/
  bundle/      — the persistent recovery bundle (with object-bundle.pack)

To resume the run on this machine:

  1. Extract:
       zstd -d <tarball.tar.zst> -c | tar -xf -
     or for .tar.gz:
       tar -xzf <tarball.tar.gz>

  2. Move the workspace into the project root, preserving the directory name:
       mv workspace /path/to/project/.worktree_branch_rationalization_workspace

  3. Move the bundle next to the project root (NOT inside it):
       mv bundle /path/to/<project-parent>/<basename>-branch-worktree-archive-<DATE>

  4. Update <workspace>/bundle_path.txt to the new absolute bundle path:
       echo "/abs/path/to/bundle" > <workspace>/bundle_path.txt

  5. Run scripts/verify-bundle.sh and scripts/conformance-check.sh against the
     project to confirm the export wasn't damaged in transit.

Per AGENTS.md, never `rm -rf` the staging dirs after a successful import; mv
them to a `.removed-<ts>` location if cleanup is needed.
RECEIVE_EOF

# Stage the workspace and bundle as siblings inside the staging dir to keep
# tarball entry paths predictable.
# Use cp -a (preserves attrs) into staging; never `rm -rf` originals.
cp -a "$WORKSPACE_DIR" "$STAGING/workspace"
cp -a "$BUNDLE"        "$STAGING/bundle"

# Build the tarball.
if [[ "$HAVE_ZSTD" -eq 1 ]]; then
  ( cd "$STAGING" && tar --use-compress-program='zstd -19 -T0' -cf "$EXPORT_PATH" workspace bundle MANIFEST.md RECEIVE.md )
else
  ( cd "$STAGING" && tar -czf "$EXPORT_PATH" workspace bundle MANIFEST.md RECEIVE.md )
fi
[[ -f "$EXPORT_PATH" ]] || { echo "ERROR: tarball not produced at $EXPORT_PATH" >&2; exit 3; }

# Verify the tarball is readable end-to-end.
if [[ "$HAVE_ZSTD" -eq 1 ]]; then
  if ! zstd -t "$EXPORT_PATH" >/dev/null 2>&1; then
    echo "ERROR: zstd self-check failed for $EXPORT_PATH" >&2
    exit 3
  fi
fi
if ! tar -tf "$EXPORT_PATH" >/dev/null 2>&1; then
  echo "ERROR: tar listing failed for $EXPORT_PATH" >&2
  exit 3
fi

# SHA256 sidecar for integrity checking on the receiving machine.
SIDECAR="${EXPORT_PATH}.sha256"
sha256sum "$EXPORT_PATH" 2>/dev/null > "$SIDECAR" || true

size_human=$(du -h "$EXPORT_PATH" 2>/dev/null | awk '{print $1}' || echo unknown)
archive_staging
trap - EXIT
echo "wrote $EXPORT_PATH ($size_human)"
echo "sidecar: $SIDECAR"
if [[ -n "$STAGING_ARCHIVED" ]]; then
  echo "manifest archived at: $STAGING_ARCHIVED/MANIFEST.md"
else
  echo "manifest included in tarball: MANIFEST.md"
fi

# Optional: archive source dirs after verified export. Per Rule 1, only via
# `mv` — never `rm -rf`.
if [[ -n "${WORKSPACE_EXPORT_ARCHIVE_SOURCE_OK:-}" ]]; then
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  ARCH_DIR="$WORKSPACE_DIR/.archived"
  mkdir -p "$ARCH_DIR"
  # We do NOT mv WORKSPACE_DIR itself (that would remove our own .archived/
  # destination). Instead, we move the bundle if it's outside the workspace.
  if [[ "$BUNDLE" != "$WORKSPACE_DIR"* ]]; then
    mv "$BUNDLE" "$ARCH_DIR/source-bundle-$ts" 2>/dev/null && \
      log "moved bundle source to $ARCH_DIR/source-bundle-$ts (per WORKSPACE_EXPORT_ARCHIVE_SOURCE_OK=1)"
  fi
  log "WORKSPACE_EXPORT_ARCHIVE_SOURCE_OK=1: workspace itself preserved (cannot move parent of .archived)"
fi

exit 0
