#!/usr/bin/env bash
# migrate-audit-dir.sh — Move an audit dir to follow a project move/rename.
#
# Usage:
#   migrate-audit-dir.sh <old-audit-dir> <new-project-path>
#
# Effects:
#   1. Renames the audit dir's parent reference in manifest.json.
#   2. Updates every pass's manifest.json `project_path`.
#   3. Records the migration in a new MIGRATION_LOG.md (commit-ed).
#   4. Verifies the move by re-running rubric_sha256 check.
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

OLD_AUDIT="${1:?old audit dir required}"
NEW_PROJECT="${2:?new project path required}"

[ -d "$OLD_AUDIT" ] || { echo "ERROR: $OLD_AUDIT does not exist" >&2; exit 2; }
[ -d "$NEW_PROJECT/.beads" ] || { echo "ERROR: $NEW_PROJECT lacks .beads/" >&2; exit 2; }

OLD_AUDIT_ABS="$(cd "$OLD_AUDIT" && pwd)"
NEW_PROJECT_ABS="$(cd "$NEW_PROJECT" && pwd)"
NEW_AUDIT_ABS="$NEW_PROJECT_ABS/beads_compliance_audit"

if [ "$OLD_AUDIT_ABS" = "$NEW_AUDIT_ABS" ]; then
  echo "Old and new audit paths are identical; nothing to do." >&2
  exit 0
fi

OLD_PROJECT_PATH="$(jq -r '.project_path // empty' "$OLD_AUDIT_ABS/manifest.json" 2>/dev/null || true)"
echo "Migrating audit dir:" >&2
echo "  Old audit dir:    $OLD_AUDIT_ABS" >&2
echo "  Old project path: $OLD_PROJECT_PATH" >&2
echo "  New audit dir:    $NEW_AUDIT_ABS" >&2
echo "  New project path: $NEW_PROJECT_ABS" >&2

# 1. Move the directory itself if needed.
if [ ! -e "$NEW_AUDIT_ABS" ]; then
  mv "$OLD_AUDIT_ABS" "$NEW_AUDIT_ABS"
else
  echo "ERROR: new audit dir $NEW_AUDIT_ABS already exists. Refusing to overwrite." >&2
  exit 3
fi

# 2. Update manifests in-place.
update_manifest() {
  local mf="$1"
  [ -f "$mf" ] || return 0
  local tmp; tmp="$(mktemp)"
  # Write through a tmp file so failed jq output never corrupts a manifest. Per
  # repo no-deletion policy, a failed write leaves the tmp artifact available
  # for diagnosis; a successful mv consumes it.
  jq --arg new "$NEW_PROJECT_ABS" '.project_path = $new' "$mf" > "$tmp"
  mv "$tmp" "$mf"
}
update_manifest "$NEW_AUDIT_ABS/manifest.json"
for pass_manifest in "$NEW_AUDIT_ABS/passes"/*/manifest.json; do
  update_manifest "$pass_manifest"
done

# 3. Record migration in MIGRATION_LOG.md
LOG="$NEW_AUDIT_ABS/MIGRATION_LOG.md"
{
  echo "# Migration log"
  echo
  echo "## $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "- Old audit dir: \`$OLD_AUDIT_ABS\`"
  echo "- Old project path: \`${OLD_PROJECT_PATH:-unknown}\`"
  echo "- New audit dir: \`$NEW_AUDIT_ABS\`"
  echo "- New project path: \`$NEW_PROJECT_ABS\`"
  echo "- Migrated by: \`migrate-audit-dir.sh\` (run by ${USER:-unknown})"
} >> "$LOG"

# 4. Verify rubric_sha256 still matches the on-disk rubric.md
RUBRIC="$NEW_AUDIT_ABS/rubric.md"
if [ -f "$RUBRIC" ]; then
  ON_DISK_SHA="$(sha256sum "$RUBRIC" | awk '{print $1}')"
  RECORDED_SHA="$(jq -r '.rubric_sha256 // empty' "$NEW_AUDIT_ABS/manifest.json")"
  if [ -n "$RECORDED_SHA" ] && [ "$ON_DISK_SHA" != "$RECORDED_SHA" ]; then
    echo "WARNING: rubric_sha256 mismatch after migration." >&2
    echo "  Recorded: $RECORDED_SHA" >&2
    echo "  On disk:  $ON_DISK_SHA" >&2
    echo "  Likely cause: rubric.md edited during/after migration. Verify intent." >&2
  fi
fi

# 5. Commit the migration if audit dir is git-tracked.
if [ -d "$NEW_AUDIT_ABS/.git" ]; then
  git -C "$NEW_AUDIT_ABS" add -A
  git -C "$NEW_AUDIT_ABS" commit -m "audit: migrate from $OLD_AUDIT_ABS to $NEW_AUDIT_ABS" \
    >/dev/null 2>&1 || echo "Note: nothing to commit (or git failed)" >&2
fi

echo "Migration complete: $NEW_AUDIT_ABS" >&2
echo "$NEW_AUDIT_ABS"
