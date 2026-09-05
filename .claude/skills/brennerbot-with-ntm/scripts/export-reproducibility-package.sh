#!/usr/bin/env bash
# export-reproducibility-package.sh — Export a workspace as a reproducibility tarball
# Per Phase 8 freeze; useful for academic-replication and sharing sessions.
#
# Usage: ./export-reproducibility-package.sh <workspace> [output_dir]

set -euo pipefail

# Portable sha256 wrapper (GNU `sha256sum` vs macOS/BSD `shasum -a 256`). Same
# stdout format on both, so awk slicing downstream stays correct.
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

WORKSPACE_ARG="${1:?Usage: $0 <workspace_path> [output_dir]}"
OUTPUT_DIR="${2:-./reproducibility-exports}"

if [ ! -d "$WORKSPACE_ARG" ]; then
    echo "[FATAL] Workspace not found: $WORKSPACE_ARG" >&2
    exit 1
fi

# Resolve to absolute BEFORE the rest of the script. Otherwise `.` (a common
# argument when the operator runs the script from inside the workspace) makes
# both `dirname` and `basename` evaluate to `.`, which then makes
# `tar -C . .` archive the entire current directory instead of the workspace,
# and a SESSION_ID derived via `basename` becomes the literal string ".".
WORKSPACE="$(cd "$WORKSPACE_ARG" && pwd)" \
    || { echo "[FATAL] Could not resolve workspace path: $WORKSPACE_ARG" >&2; exit 1; }

if [ ! -f "$WORKSPACE/.brenner_workspace/phase0_scope_decision.md" ]; then
    echo "[FATAL] Not a brennerbot workspace (no phase0_scope_decision.md)" >&2
    exit 1
fi

# Read session ID from phase0_scope_decision.md. Two-stage extract: locate the
# session_id line, then strip the leading `session_id:` (or `session:`) prefix
# along with any whitespace. The previous one-stage `awk -F': '` split would
# silently fail for files written without a space after the colon
# (`session_id:RS-foo`) — awk would treat the whole line as one field, $2
# was empty, and the script then auto-generated a SESSION_ID from the
# basename instead of using the explicit one. Same class of bug as the
# round-6 tier fix in operator-self-assessment.sh.
SESSION_LINE="$(grep -E '^[[:space:]]*(session_id|session)[[:space:]]*:' \
    "$WORKSPACE/.brenner_workspace/phase0_scope_decision.md" 2>/dev/null \
    | head -1)"
SESSION_ID="$(printf '%s' "$SESSION_LINE" \
    | sed -E 's/^[[:space:]]*(session_id|session)[[:space:]]*:[[:space:]]*//' \
    | sed -E 's/[[:space:]]+#.*$//' \
    | sed -E 's/[[:space:]]+$//')"

if [ -z "$SESSION_ID" ]; then
    SESSION_ID="$(basename "$WORKSPACE")-$(date +%Y%m%d-%H%M%S)"
fi

# Sanitize session id for filename. Use printf to avoid the trailing newline
# `echo` adds — `tr -c` would otherwise replace it with `_`, leaving a stray
# trailing underscore on every archive name.
SAFE_ID="$(printf '%s' "$SESSION_ID" | tr -c 'a-zA-Z0-9-_' '_')"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_NAME="brennerbot-${SAFE_ID}-${TIMESTAMP}.tar.gz"

mkdir -p "$OUTPUT_DIR"

# Compute pre-export checksum manifest:
MANIFEST="$WORKSPACE/.brenner_workspace/.export-manifest.txt"

(
    cd "$WORKSPACE"
    {
        echo "# brennerbot reproducibility manifest"
        echo "# session_id: $SESSION_ID"
        echo "# exported_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "# host: $(uname -n)"
        echo "# git_sha: $(git -C . rev-parse HEAD 2>/dev/null || echo 'n/a')"
        echo ""
        echo "## File checksums"
        find . -type f \
            -not -path './node_modules/*' \
            -not -path './.git/*' \
            -not -path '*.tar.gz' \
            -not -name '.export-manifest.txt' \
            -print0 | { if command -v sha256sum >/dev/null 2>&1; then xargs -0 sha256sum; else xargs -0 shasum -a 256; fi; } 2>/dev/null | sort -k 2
    } > "$MANIFEST"
)

# Create archive (excluding the archive itself + node_modules + .git artifacts):
tar -czf "$OUTPUT_DIR/$ARCHIVE_NAME" \
    -C "$(dirname "$WORKSPACE")" \
    --exclude='*.tar.gz' \
    --exclude='node_modules' \
    --exclude='.git/objects' \
    --exclude='.git/logs' \
    "$(basename "$WORKSPACE")"

# Compute archive hash:
ARCHIVE_HASH="$(sha256 "$OUTPUT_DIR/$ARCHIVE_NAME" | awk '{print $1}')"

cat <<EOF
=== Reproducibility Package Created ===
Session: $SESSION_ID
Archive: $OUTPUT_DIR/$ARCHIVE_NAME
Archive size: $(du -sh "$OUTPUT_DIR/$ARCHIVE_NAME" | awk '{print $1}')
Archive hash: $ARCHIVE_HASH

Manifest: $MANIFEST (in workspace)

To verify on import:
  tar -xzf $ARCHIVE_NAME
  cd <extracted-workspace>
  # GNU/Linux: sha256sum -c .brenner_workspace/.export-manifest.txt
  # macOS/BSD: shasum -a 256 -c .brenner_workspace/.export-manifest.txt

To reproduce:
  # RESUME.md lives at deliverables/RESUME.md, not at the workspace root.
  # mode_to_resume is read from the RESUME.md body — resume-session.sh has no
  # --mode flag. The reproducibility archive contains the session workspace;
  # use resume-session.sh from an installed/copy of the brennerbot-with-ntm skill.
  SKILL_SCRIPTS=/path/to/brennerbot-with-ntm/scripts
  bash "\$SKILL_SCRIPTS/resume-session.sh" \\
    --resume <extracted-workspace>/deliverables/RESUME.md
EOF
